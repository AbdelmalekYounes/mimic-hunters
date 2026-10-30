--[[
	ServerSuite — tests exécutés DANS une session Studio (DataModel serveur).

	Injecté par le pilote (tests/studio/Driver.luau) via StudioTestService.
	Selon GetTestArgs().suite :
	- "server"      : jeu réel démarré, carte, objets, espèces, états, captures,
	                  récompenses, concurrence (faux joueurs, sans client) ;
	- "client"      : attend le client, lui demande de se tester, vérifie côté serveur ;
	- "multiplayer" : 2 clients, déconnexion via LeaveTest, reconnexion via AddPlayers.
	Termine toujours par StudioTestService:EndTest(rapport).
	Aucune entrée clavier/souris n'est simulée : tout passe par l'API du jeu.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local SUITE_TIMEOUT = 120
local suiteStart = os.clock()
local args = StudioTestService:GetTestArgs() or {}
local suite = if type(args) == "table" then args.suite else nil

local results = {}
local logs = {}

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	table.insert(logs, table.concat(parts, " "))
end

local function check(name: string, fn: () -> ())
	local t0 = os.clock()
	local ok, err = pcall(fn)
	table.insert(results, {
		name = name,
		ok = ok,
		message = if ok then nil else tostring(err),
		duration = math.floor((os.clock() - t0) * 1000) / 1000,
	})
end

local function expect(cond: any, message: string)
	if not cond then
		error(message, 2)
	end
end

local function waitFor(predicate: () -> any, timeout: number, step: number?): any
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(step or 0.1)
	end
	return nil
end

local finished = false
local function finish(extra: { [string]: any }?)
	if finished then
		return
	end
	finished = true
	local report = {
		suite = suite,
		results = results,
		logs = logs,
		duration = os.clock() - suiteStart,
	}
	if extra then
		for k, v in extra do
			report[k] = v
		end
	end
	StudioTestService:EndTest(report)
end

-- Garde-fou : un test bloqué ne doit jamais bloquer Studio.
task.delay(SUITE_TIMEOUT, function()
	table.insert(
		results,
		{ name = "suite.timeout", ok = false, message = "délai global dépassé", duration = SUITE_TIMEOUT }
	)
	finish({ timedOut = true })
end)

-- ─── Démarrage du jeu ──────────────────────────────────────────────────

local world = waitFor(function()
	-- Accès debug exposé par HuntServer en Studio uniquement.
	-- selene: allow(global_usage)
	return (_G :: any).MimicHuntWorld
end, 30)
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local ServerRoot = ServerScriptService:WaitForChild("Server", 10)

check("serveur.demarrage", function()
	expect(Shared ~= nil, "ReplicatedStorage.Shared absent")
	expect(ServerRoot ~= nil, "ServerScriptService.Server absent")
	expect(world ~= nil, "_G.MimicHuntWorld absent après 30 s (serveur non démarré ?)")
	expect(workspace:FindFirstChild("Map") ~= nil, "Workspace.Map absent")
end)

if world == nil or Shared == nil or ServerRoot == nil then
	finish({ fatal = "jeu non démarré" })
	return
end

local GameConfig = require(Shared.Config.GameConfig)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local CaptureMinigame = require(Shared.Logic.CaptureMinigame)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local Remotes = require(Shared.Net.Remotes)
local MapLayout = require(ServerRoot.Map.MapLayout)

local function slotPosition(slotId: string): Vector3
	local slot = world:slot(slotId)
	return Vector3.new(slot.position.X + 3, 3, slot.position.Z)
end

local function hitTime(stage: any): number
	local t = if stage.phase == 0 then stage.center / stage.speed else (1 - stage.center) / stage.speed
	while t < GameConfig.Capture.MinStageElapsed + 0.05 do
		t += 2 / stage.speed
	end
	return t
end

local function missTime(stage: any): number
	local t = GameConfig.Capture.MinStageElapsed + 0.05
	while math.abs(CaptureMinigame.cursorAt(stage, t) - stage.center) <= stage.width / 2 + 0.2 do
		t += 0.02
	end
	return t
end

local function named(events: { any }, name: string): { any }
	local out = {}
	for _, e in events do
		if e.name == name then
			table.insert(out, e)
		end
	end
	return out
end

-- Joue une capture en temps réel (le serveur juge avec son horloge).
local function playCapture(userId: number, position: Vector3, started: any, plan: { string }): ({ any }, any)
	local all, last = {}, nil
	local stage = started.stage
	local stageStart = started._t0
	for _, step in plan do
		local target = stageStart + (if step == "hit" then hitTime(stage) else missTime(stage))
		while os.clock() < target do
			task.wait()
		end
		local now = os.clock()
		local events, reply = world:pulse(userId, position, started.attemptId, now - stageStart, 0.12, now)
		for _, e in events do
			table.insert(all, e)
		end
		last = reply
		if reply.stage then
			stage = reply.stage
			stageStart = now
		end
	end
	return all, last
end

local function findHidden(exclude: { [string]: boolean }?): any
	for _, record in world:sharedMimics() do
		if record.state == "Disguised" and not (exclude and exclude[record.id]) then
			return record
		end
	end
	return nil
end

local function startOn(userId: number, record: any): (Vector3, any)
	local pos = slotPosition(record.slotId)
	local _, inspect = world:inspect(userId, pos, record.slotId, os.clock())
	expect(inspect.result == "Mimic", "révélation attendue, obtenu " .. tostring(inspect.result or inspect.reason))
	local t0 = os.clock()
	local _, started = world:startCapture(userId, pos, record.id, t0)
	expect(started.ok, "démarrage attendu, obtenu " .. tostring(started.reason))
	started._t0 = t0
	return pos, started
end

-- ─── Suite « server » (session Run, sans client) ───────────────────────

local function serverSuite()
	check("carte.trois_zones", function()
		local map = workspace.Map
		for _, name in { "Ground", "Village", "Park", "Market", "Props" } do
			expect(map:FindFirstChild(name) ~= nil, "dossier Map." .. name .. " absent")
		end
		expect(#map.Village:GetChildren() > 10, "Village trop vide")
		expect(#map.Park:GetChildren() > 10, "Parc trop vide")
		expect(#map.Market:GetChildren() > 10, "Zone Commerciale trop vide")
		expect(workspace.Map:FindFirstChild("HunterSpawn") ~= nil, "SpawnLocation absent")
	end)

	check("carte.41_objets", function()
		local tagged = CollectionService:GetTagged("MimicProp")
		expect(#tagged == 41, "41 objets attendus, trouvé " .. #tagged)
		local ids, perZone = {}, {}
		for _, model in tagged do
			local id = model:GetAttribute("PropId")
			expect(type(id) == "string" and ids[id] == nil, "PropId invalide ou dupliqué : " .. tostring(id))
			ids[id] = true
			expect(MimicCatalog.getByKind(model:GetAttribute("PropKind")) ~= nil, "type inconnu sur " .. id)
			local zone = model:GetAttribute("Zone")
			perZone[zone] = (perZone[zone] or 0) + 1
		end
		expect(ids.TUTO, "objet TUTO absent")
		expect(
			perZone.Village == 17 and perZone.Park == 11 and perZone.Market == 13,
			"répartition par zone inattendue"
		)
	end)

	check("carte.objets_poses_au_sol", function()
		-- Régression : avant correctif, les objets étaient posés par leur corps.
		for _, model in CollectionService:GetTagged("MimicProp") do
			local pivot = model:GetPivot()
			local cf, size = model:GetBoundingBox()
			local bottom = cf.Position.Y - size.Y / 2
			expect(math.abs(pivot.Position.Y) < 0.05, model.Name .. " pivot Y = " .. pivot.Position.Y)
			expect(bottom > -0.2 and bottom < 0.3, model.Name .. " bas de l'objet à Y = " .. bottom)
			expect(math.abs(pivot.UpVector.Y - 1) < 1e-3, model.Name .. " n'est pas debout")
		end
	end)

	check("especes.six_modeles", function()
		local list = MimicCatalog.list()
		expect(#list == 6, "6 espèces attendues")
		for _, species in list do
			local model = MimicModelBuilder.build(species.id)
			expect(model.PrimaryPart ~= nil, species.id .. " sans PrimaryPart")
			expect(model:GetAttribute("SpeciesId") == species.id, species.id .. " attribut manquant")
			local eyes = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "EyeWhite" or d.Name == "ScreenEye") then
					eyes += 1
				end
			end
			expect(eyes >= 1, species.id .. " sans yeux")
			expect(math.abs(model:GetPivot().Position.Y) < 0.05, species.id .. " pivot hors du sol")
			model:Destroy()
		end
	end)

	check("reseau.remote_events", function()
		local folder = ReplicatedStorage:FindFirstChild("MimicRemotes")
		expect(folder ~= nil, "dossier MimicRemotes absent")
		for _, list in { Remotes.ClientToServer, Remotes.ServerToClient } do
			for _, name in list do
				expect(folder:FindFirstChild(name) ~= nil, "RemoteEvent absent : " .. name)
			end
		end
	end)

	check("monde.population", function()
		local list = world:sharedMimics()
		expect(#list == GameConfig.Hunt.ActiveMimics, "Mimics actifs : " .. #list)
		local perZone = {}
		for _, record in list do
			local zone = world:slot(record.slotId).zone
			perZone[zone] = (perZone[zone] or 0) + 1
		end
		for _, zone in MapLayout.zoneIds() do
			expect((perZone[zone] or 0) >= GameConfig.Hunt.MinPerZone, "zone " .. zone .. " sous le minimum")
		end
	end)

	-- Faux joueurs (identifiants négatifs : jamais de vrais comptes).
	local A, B = -1001, -2002
	local veteran = { version = 1, inventory = nil, tutorialDone = true }
	world:addPlayer(A, os.clock(), veteran)
	world:addPlayer(B, os.clock(), veteran)

	local captured = {}

	check("etats.revelation_et_verrou", function()
		local record = findHidden()
		expect(record, "aucun Mimic caché")
		local posA, posB = slotPosition(record.slotId), slotPosition(record.slotId) + Vector3.new(-6, 0, 0)
		local _, ra = world:inspect(A, posA, record.slotId, os.clock())
		local _, rb = world:inspect(B, posB, record.slotId, os.clock())
		expect(ra.result == "Mimic", "A devait révéler")
		expect(record.state == "Revealed" and record.ownerId == A, "état Revealed/A attendu")
		expect(rb.result == "Busy" and rb.ownerUserId == A, "B devait voir Busy")
		local _, sb = world:startCapture(B, posB, record.id, os.clock())
		expect(not sb.ok and sb.reason == "NotOwner", "B ne doit pas capturer : " .. tostring(sb.reason))
		local t0 = os.clock()
		local _, sa = world:startCapture(A, posA, record.id, t0)
		expect(sa.ok and record.state == "Capturing", "A doit démarrer la capture")
		local _, again = world:startCapture(A, posA, record.id, os.clock())
		expect(not again.ok and again.reason == "AlreadyCapturing", "seconde tentative refusée attendue")
		sa._t0 = t0
		local events, last = playCapture(A, posA, sa, { "hit", "hit" })
		expect(last.status == "Succeeded", "capture attendue, statut " .. tostring(last.status))
		expect(#named(events, "CaptureResolved") == 1, "un seul CaptureResolved attendu")
		expect(world:inventoryOf(A):count(record.speciesId) == 1, "récompense absente")
		expect(world:inventoryOf(B):totalCaptures() == 0, "B ne doit rien recevoir")
		expect(world:mimicAtSlot(record.slotId) == nil, "emplacement non libéré")
		captured.first = { record = record, started = sa, pos = posA }
		log("capturé", record.speciesId, "en", record.slotId)
	end)

	check("recompenses.rejeu_sans_doublon", function()
		local first = captured.first
		expect(first, "pré-requis : capture précédente")
		local before = world:inventoryOf(A):totalCaptures()
		for _ = 1, 5 do
			task.wait(0.25)
			local events, reply = world:pulse(A, first.pos, first.started.attemptId, 0.5, 0.12, os.clock())
			expect(not reply.ok and reply.reason == "Resolved", "rejeu : " .. tostring(reply.reason))
			expect(#named(events, "CaptureResolved") == 0, "rejeu a produit une récompense")
		end
		expect(world:inventoryOf(A):totalCaptures() == before, "inventaire modifié par un rejeu")
	end)

	check("concurrence.deux_captures_paralleles", function()
		local ma = findHidden()
		local mb = findHidden({ [ma.id] = true })
		expect(ma and mb, "deux Mimics cachés requis")
		local pa, sa = startOn(A, ma)
		local pb, sb = startOn(B, mb)
		-- Les deux minijeux tournent en même temps, impulsions entrelacées.
		local doneA, doneB = false, false
		task.spawn(function()
			playCapture(A, pa, sa, { "hit", "hit" })
			doneA = true
		end)
		task.spawn(function()
			playCapture(B, pb, sb, { "hit", "hit" })
			doneB = true
		end)
		expect(
			waitFor(function()
				return doneA and doneB
			end, 15),
			"captures parallèles non terminées"
		)
		expect(world:inventoryOf(A):count(ma.speciesId) >= 1, "A sans récompense")
		expect(world:inventoryOf(B):count(mb.speciesId) >= 1, "B sans récompense")
	end)

	check("etats.echec_fuite_puis_recache", function()
		local record = findHidden()
		local oldSlot = record.slotId
		local pos, started = startOn(A, record)
		local _, last = playCapture(A, pos, started, { "miss", "miss" })
		expect(last.status == "Failed", "échec attendu")
		expect(record.state == "Fleeing", "fuite attendue")
		expect(
			waitFor(function()
				return record.state == "Disguised"
			end, GameConfig.Hunt.FleeDuration + 3),
			"le Mimic ne s'est pas recaché (tick serveur réel)"
		)
		expect(world:slot(record.slotId).kind == world:slot(oldSlot).kind, "nouvel emplacement d'un autre type")
	end)

	check("protections.portee_et_donnees", function()
		task.wait(1.3)
		local record = findHidden()
		local far = slotPosition(record.slotId) + Vector3.new(60, 0, 0)
		local _, r1 = world:inspect(B, far, record.slotId, os.clock())
		expect(r1.reason == "OutOfRange", "hors de portée attendu : " .. tostring(r1.reason or r1.result))
		task.wait(0.3)
		local _, r2 = world:inspect(B, slotPosition(record.slotId), "../../x", os.clock())
		expect(r2.reason == "BadInput", "BadInput attendu")
		local _, r3 = world:startCapture(B, far, "M999999", os.clock())
		expect(r3.reason == "UnknownMimic", "UnknownMimic attendu")
		local _, r4 = world:pulse(B, far, "A999999", 1, 0.12, os.clock())
		expect(r4.reason == "UnknownAttempt", "UnknownAttempt attendu")
	end)

	check("monde.reapparition", function()
		expect(
			waitFor(function()
				return #world:sharedMimics() == GameConfig.Hunt.ActiveMimics
			end, GameConfig.Hunt.RespawnDelay + 6, 0.25),
			"population non revenue à " .. GameConfig.Hunt.ActiveMimics
		)
	end)

	world:removePlayer(A, os.clock())
	world:removePlayer(B, os.clock())
	check("joueurs.retrait_faux_joueurs", function()
		expect(world:inventoryOf(A) == nil and world:inventoryOf(B) == nil, "faux joueurs non retirés")
	end)
end

-- ─── Bus de test serveur ↔ client ──────────────────────────────────────

local bus = Instance.new("RemoteEvent")
bus.Name = "MH_TestBus"
bus.Parent = ReplicatedStorage
local reports: { [number]: any } = {}
bus.OnServerEvent:Connect(function(player, kind, data)
	if kind == "report" then
		reports[player.UserId] = data
	end
end)

local function waitPlayers(count: number, timeout: number): { Player }
	waitFor(function()
		return #Players:GetPlayers() >= count
	end, timeout)
	return Players:GetPlayers()
end

local function askClient(player: Player, payload: any, timeout: number): any
	reports[player.UserId] = nil
	-- Le client peut ne pas être encore prêt : on répète la demande.
	return waitFor(function()
		if reports[player.UserId] == nil then
			bus:FireClient(player, "run", payload)
		end
		return reports[player.UserId]
	end, timeout, 1)
end

-- ─── Suite « client » (session Play, 1 joueur) ─────────────────────────

local function clientSuite()
	local players = waitPlayers(1, 30)
	local player = players[1]
	check("joueur.connexion", function()
		expect(player ~= nil, "aucun joueur après 30 s")
		expect(
			waitFor(function()
				return world:inventoryOf(player.UserId) ~= nil
			end, 10),
			"joueur non enregistré dans le monde"
		)
	end)
	if player == nil then
		return nil
	end
	local report = askClient(player, { device = args.device }, 60)
	check("client.rapport_recu", function()
		expect(report ~= nil, "aucun rapport du client en 60 s")
	end)
	if report then
		for _, r in report.results or {} do
			table.insert(results, {
				name = "client." .. r.name,
				ok = r.ok,
				skipped = r.skipped,
				message = r.message,
				duration = r.duration,
			})
		end
		check("serveur.recompense_client_confirmee", function()
			if report.capturedSpecies then
				local inventory = world:inventoryOf(player.UserId)
				expect(inventory and inventory:count(report.capturedSpecies) >= 1, "capture non visible côté serveur")
				expect(world:tutorialStepOf(player.UserId) == "Done", "tutoriel non terminé côté serveur")
			else
				error("le client n'a pas capturé (voir client.*)")
			end
		end)
	end
	return report and report.env
end

-- ─── Suite « multiplayer » (2 clients, départ, retour) ─────────────────

local function multiplayerSuite()
	local players = waitPlayers(2, 45)
	check("multi.deux_joueurs", function()
		expect(#players >= 2, "2 joueurs attendus, " .. #players .. " connectés")
		for _, p in players do
			expect(
				waitFor(function()
					return world:inventoryOf(p.UserId) ~= nil
				end, 10),
				"joueur " .. p.Name .. " non enregistré"
			)
		end
	end)
	if #players < 2 then
		return
	end
	local leaver = players[2]
	local leaverId = leaver.UserId
	check("multi.deconnexion_LeaveTest", function()
		local gone = false
		local conn = Players.PlayerRemoving:Connect(function(p)
			if p == leaver then
				gone = true
			end
		end)
		waitFor(function()
			if not gone then
				bus:FireClient(leaver, "leave")
			end
			return gone
		end, 20, 1)
		conn:Disconnect()
		expect(gone, "le client n'a pas quitté (LeaveTest)")
		expect(
			waitFor(function()
				return world:inventoryOf(leaverId) == nil
			end, 5),
			"joueur parti encore présent dans le monde"
		)
		expect(world:inventoryOf(players[1].UserId) ~= nil, "l'autre joueur a été affecté")
	end)
	check("multi.reconnexion_AddPlayers", function()
		local before = #Players:GetPlayers()
		StudioTestService:AddPlayers(1)
		expect(
			waitFor(function()
				return #Players:GetPlayers() > before
			end, 45),
			"aucun joueur ajouté par AddPlayers"
		)
		for _, p in Players:GetPlayers() do
			expect(
				waitFor(function()
					return world:inventoryOf(p.UserId) ~= nil
				end, 10),
				"nouveau joueur non enregistré"
			)
		end
	end)
end

local env
if suite == "server" then
	serverSuite()
elseif suite == "client" then
	env = clientSuite()
elseif suite == "multiplayer" then
	multiplayerSuite()
else
	check("suite.inconnue", function()
		error("suite inconnue : " .. tostring(suite))
	end)
end
finish({ clientEnv = env })
