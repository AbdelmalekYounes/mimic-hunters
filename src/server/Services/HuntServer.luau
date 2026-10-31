--!strict
--[[
	HuntServer — adaptateur Roblox autour de HuntWorld.

	Responsabilités (et rien d'autre) :
	- relier les RemoteEvents aux méthodes de HuntWorld ;
	- fournir la position réelle du personnage (jamais celle annoncée par le client) ;
	- fournir l'heure serveur et une estimation de latence ;
	- diffuser les événements retournés ;
	- charger / sauvegarder les profils via ProfileService (verrou de session, DataStore).

	Cycle d'un profil :
	1. Arrivée : chargement (cède la main) puis ajout au monde. Pendant le chargement, le
	   client voit « Chargement du profil » et ses demandes sont ignorées.
	2. Profil indisponible ou verrouillé ailleurs : le joueur explore sans pouvoir capturer ;
	   nouvelle tentative toutes les ReloadRetryInterval secondes.
	3. Capture : sauvegarde rapide (≈ 7 s au plus). Sinon sauvegarde toutes les 60 s.
	4. Départ et fermeture du serveur : sauvegarde finale et libération du verrou.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Rng = require(Shared.Logic.Rng)
local Remotes = require(Shared.Net.Remotes)

local Server = script.Parent.Parent
local HuntWorld = require(Server.Core.HuntWorld)
local ProfileService = require(Server.Core.ProfileService)
local MapLayout = require(Server.Map.MapLayout)
local DataStoreBackend = require(script.Parent.DataStoreBackend)

local TICK_INTERVAL = 0.2
local SAVE_STEP_INTERVAL = 1

local HuntServer = {}

function HuntServer.start()
	local seed = os.time() + math.floor(os.clock() * 1000)
	local studio = RunService:IsStudio()
	-- Studio uniquement : l'attribut Workspace « MH_ForceMutation » impose la prochaine mutation
	-- (tests visuels, captures d'écran). Sans effet dans un jeu publié.
	local mutationSource: any = Mutations
	if studio then
		mutationSource = {
			roll = function(rng: any): string
				local forced = workspace:GetAttribute("MH_ForceMutation")
				if type(forced) == "string" and Mutations.get(forced) then
					return forced
				end
				return Mutations.roll(rng)
			end,
		}
	end
	-- Identifiant de ce serveur : préfixe des clés de capture et propriétaire des verrous.
	local serverId = if game.JobId ~= "" then game.JobId else string.format("studio-%d", seed)
	local world = HuntWorld.new({
		config = GameConfig,
		catalog = MimicCatalog,
		rarities = Rarities,
		slots = MapLayout.Props,
		tutorialSlot = MapLayout.TutorialProp,
		zones = MapLayout.zoneIds(),
		rng = Rng.new(seed),
		serverId = serverId,
		wallClock = os.time,
		mutations = mutationSource,
	})
	local remotes = Remotes.setup()

	local function now(): number
		return os.clock()
	end

	local dispatch: (events: { HuntWorld.Event }) -> ()

	local backend, backendName = DataStoreBackend.choose(GameConfig.Save)
	local inMemory = string.find(backendName, "mémoire", 1, true) ~= nil
	local profiles = ProfileService.new({
		backend = backend,
		jobId = serverId,
		clock = os.time,
		wait = task.wait,
		spawn = task.spawn,
		log = function(message: string)
			warn(message)
		end,
		onLost = function(userId: number)
			dispatch(world:setProfileLost(userId))
			local player = Players:GetPlayerByUserId(userId)
			if player then
				player:Kick("Ton profil MIMIC HUNTERS a été ouvert sur un autre serveur. Reconnecte-toi.")
			end
		end,
		-- En mémoire, pas de limite d'écriture par clé : inutile d'attendre entre deux sauvegardes.
		config = if inMemory then { MinSaveInterval = 0, LockedRetryDelay = 1 } else nil,
	})
	print("[MimicHunters] profils :", backendName)

	if studio then
		-- Accès de débogage depuis la barre de commande de Studio (serveur seulement).
		-- selene: allow(global_usage)
		(_G :: any).MimicHuntWorld = world;
		-- selene: allow(global_usage)
		(_G :: any).MimicProfiles = { service = profiles, backend = backend, name = backendName }
	end

	dispatch = function(events: { HuntWorld.Event })
		for _, event in events do
			if string.sub(event.name, 1, 1) == "_" then
				-- Événement interne : jamais envoyé au client.
				if event.name == "_ProfileChanged" and event.userId then
					profiles:markDirty(event.userId, event.payload.important)
				end
				continue
			end
			if studio and event.name == "CaptureResolved" then
				local p = event.payload
				print(
					string.format(
						"[MimicHunters] capture %s : joueur %s, %s (%s)",
						if p.success then "réussie" else "échouée",
						tostring(event.userId),
						tostring(p.speciesId),
						tostring(
							p.reason
								or string.format(
									"%s, %s",
									if p.isNew then "nouvelle espèce" else "doublon",
									tostring(p.mutation)
								)
						)
					)
				)
			elseif studio and event.name == "PulseResult" and event.payload.ok then
				local p = event.payload
				print(
					string.format(
						"[MimicHunters] impulsion %s : %s à %.2f (%d/%d)",
						tostring(p.attemptId),
						if p.hit then "réussie" else "ratée",
						p.position or -1,
						p.hits or 0,
						p.misses or 0
					)
				)
			end
			local remote = remotes[event.name]
			if remote == nil then
				warn("[HuntServer] RemoteEvent inconnu :", event.name)
				continue
			end
			if event.userId then
				local player = Players:GetPlayerByUserId(event.userId)
				if player then
					remote:FireClient(player, event.payload)
				end
			else
				remote:FireAllClients(event.payload)
			end
		end
	end

	-- Position autoritaire : celle du HumanoidRootPart vivant, sinon nil.
	local function positionOf(player: Player): Vector3?
		local character = player.Character
		if character == nil then
			return nil
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			return root.Position
		end
		return nil
	end

	local function allowanceOf(player: Player): number
		local ok, ping = pcall(function()
			return player:GetNetworkPing()
		end)
		local value = if ok and type(ping) == "number" then ping else 0
		return value + GameConfig.Capture.LatencyBase
	end

	-- Une erreur dans un gestionnaire ne doit jamais casser la boucle de jeu.
	local function guarded(name: string, handler: (...any) -> ())
		return function(...)
			local ok, err = pcall(handler, ...)
			if not ok then
				warn(string.format("[HuntServer] erreur dans %s : %s", name, tostring(err)))
			end
		end
	end

	local function getProfile(userId: number): any
		return world:getProfile(userId)
	end

	local function inGame(player: Player): boolean
		return player.Parent == Players
	end

	-- Clients qui ont dit « prêt » avant la fin du chargement de leur profil.
	local pendingReady: { [number]: boolean } = {}

	-- Profil chargé mais illisible par ce serveur (version future, données corrompues) :
	-- on libère le verrou SANS écrire, pour ne jamais écraser ces données.
	local function releaseUntouched(userId: number)
		task.spawn(function()
			profiles:release(userId, nil)
		end)
	end

	-- Nouvelles tentatives de chargement tant que le profil n'est pas sûr.
	local function retryLoad(player: Player)
		local userId = player.UserId
		task.spawn(function()
			while inGame(player) do
				task.wait(GameConfig.Save.ReloadRetryInterval)
				local status = world:profileStatusOf(userId)
				if not inGame(player) or status == nil or status == "Ready" then
					return
				end
				if status ~= "Unavailable" and status ~= "Locked" then
					return -- version future ou données corrompues : réessayer ne changera rien
				end
				local loaded, data = profiles:load(userId)
				if not inGame(player) then
					if loaded == "Ready" then
						releaseUntouched(userId)
					end
					return
				end
				if loaded == "Ready" then
					dispatch(world:attachProfile(userId, data, now()))
					if world:profileStatusOf(userId) ~= "Ready" then
						releaseUntouched(userId)
					end
					return
				end
			end
		end)
	end

	local function onPlayerAdded(player: Player)
		local userId = player.UserId
		remotes.ProfileStatus:FireClient(player, { status = "Loading" })
		local status, data = profiles:load(userId)
		if not inGame(player) then
			-- Parti pendant le chargement : libérer le verrou sans rien écrire.
			if status == "Ready" then
				releaseUntouched(userId)
			end
			return
		end
		if status == "Ready" then
			world:addPlayer(userId, now(), data)
			if world:profileStatusOf(userId) ~= "Ready" then
				releaseUntouched(userId)
			end
		else
			world:addPlayer(userId, now(), nil, { ready = false, status = status })
			retryLoad(player)
		end
		if pendingReady[userId] then
			pendingReady[userId] = nil
			dispatch((world:clientReady(userId, now())))
		end
	end

	world:populate(now())
	Players.PlayerAdded:Connect(guarded("PlayerAdded", onPlayerAdded))
	for _, player in Players:GetPlayers() do
		task.spawn(guarded("PlayerAdded", onPlayerAdded), player)
	end

	Players.PlayerRemoving:Connect(guarded("PlayerRemoving", function(player: Player)
		local userId = player.UserId
		pendingReady[userId] = nil
		local data = world:getProfile(userId)
		dispatch(world:removePlayer(userId, now()))
		if profiles:status(userId) then
			task.spawn(function()
				profiles:release(userId, data)
			end)
		end
	end))

	-- Fermeture du serveur : sauvegarde finale de tous les profils (Roblox accorde ~30 s).
	game:BindToClose(function()
		profiles:closeAll(getProfile)
	end)

	remotes.ClientReady.OnServerEvent:Connect(guarded("ClientReady", function(player: Player)
		if world:profileStatusOf(player.UserId) == nil then
			pendingReady[player.UserId] = true
			return
		end
		dispatch((world:clientReady(player.UserId, now())))
	end))

	remotes.RequestScan.OnServerEvent:Connect(guarded("RequestScan", function(player: Player)
		dispatch((world:scan(player.UserId, positionOf(player), now())))
	end))

	remotes.RequestInspect.OnServerEvent:Connect(guarded("RequestInspect", function(player: Player, propId: any)
		dispatch((world:inspect(player.UserId, positionOf(player), propId, now())))
	end))

	remotes.RequestCapture.OnServerEvent:Connect(guarded("RequestCapture", function(player: Player, mimicId: any)
		dispatch((world:startCapture(player.UserId, positionOf(player), mimicId, now())))
	end))

	remotes.SubmitPulse.OnServerEvent:Connect(
		guarded("SubmitPulse", function(player: Player, attemptId: any, elapsed: any)
			dispatch((world:pulse(player.UserId, positionOf(player), attemptId, elapsed, allowanceOf(player), now())))
		end)
	)

	remotes.SetFavorite.OnServerEvent:Connect(
		guarded("SetFavorite", function(player: Player, specimenId: any, value: any)
			dispatch((world:setFavorite(player.UserId, specimenId, value, now())))
		end)
	)

	remotes.EquipCosmetic.OnServerEvent:Connect(guarded("EquipCosmetic", function(player: Player, kind: any, id: any)
		dispatch((world:equipCosmetic(player.UserId, kind, id, now())))
	end))

	remotes.UpdateSettings.OnServerEvent:Connect(guarded("UpdateSettings", function(player: Player, settings: any)
		dispatch((world:updateSettings(player.UserId, settings, now())))
	end))

	local accumulator = 0
	local saveAccumulator = 0
	RunService.Heartbeat:Connect(guarded("Tick", function(dt: number)
		saveAccumulator += dt
		if saveAccumulator >= SAVE_STEP_INTERVAL then
			saveAccumulator = 0
			profiles:step(getProfile)
		end
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		accumulator = 0
		local positions: { [number]: Vector3 } = {}
		for _, player in Players:GetPlayers() do
			local position = positionOf(player)
			if position then
				positions[player.UserId] = position
			end
		end
		dispatch(world:tick(now(), positions))
	end))

	return world
end

return HuntServer
