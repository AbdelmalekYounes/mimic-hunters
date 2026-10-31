--[[
	ClientSuite — tests exécutés DANS le client d'une session Studio.

	Injecté dans StarterPlayerScripts par le pilote. Attend les ordres du
	serveur de test (RemoteEvent MH_TestBus) :
	- "run"   : vérifie l'interface puis joue le tutoriel de bout en bout
	            en appelant directement les RemoteEvents du jeu
	            (aucune souris, aucun clavier simulés) ;
	- "leave" : quitte la session (StudioTestService:LeaveTest).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer

-- Silence : un bureau Windows caché ne coupe pas l'audio de Studio.
local function mute(instance: Instance)
	if instance:IsA("Sound") then
		instance.Volume = 0
		instance:GetPropertyChangedSignal("Volume"):Connect(function()
			if instance.Volume ~= 0 then
				instance.Volume = 0
			end
		end)
	end
end
for _, d in game:GetDescendants() do
	pcall(mute, d)
end
game.DescendantAdded:Connect(function(d)
	pcall(mute, d)
end)

local bus = ReplicatedStorage:WaitForChild("MH_TestBus", 60)
if bus == nil then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaptureMinigame = require(Shared.Logic.CaptureMinigame)
local GameConfig = require(Shared.Config.GameConfig)
local remotesFolder = ReplicatedStorage:WaitForChild("MimicRemotes")

local running = false

local function remote(name: string): RemoteEvent
	return remotesFolder:WaitForChild(name) :: RemoteEvent
end

-- Envoie une requête et attend la réponse correspondante (ou nil après délai).
local function request(sendName: string, replyName: string, timeout: number, ...: any): any
	local reply = nil
	local conn = remote(replyName).OnClientEvent:Connect(function(payload)
		reply = payload
	end)
	remote(sendName):FireServer(...)
	local deadline = os.clock() + timeout
	while reply == nil and os.clock() < deadline do
		task.wait()
	end
	conn:Disconnect()
	return reply
end

local function runTests(payload: any)
	local results = {}
	local SKIP = "__skip__:"
	local function check(name: string, fn: () -> ())
		local t0 = os.clock()
		local ok, err = pcall(fn)
		local message = if ok then nil else tostring(err)
		local skipped = message ~= nil and string.find(message, SKIP, 1, true) ~= nil
		table.insert(results, {
			name = name,
			ok = ok or skipped,
			skipped = skipped or nil,
			message = if skipped
				then string.sub(message :: string, (string.find(message :: string, SKIP, 1, true) :: number) + #SKIP)
				else message,
			duration = math.floor((os.clock() - t0) * 1000) / 1000,
		})
	end
	local function skip(reason: string)
		error(SKIP .. reason, 0)
	end
	local function expect(cond: any, message: string)
		if not cond then
			error(message, 2)
		end
	end

	local camera = workspace.CurrentCamera
	local env = {
		device = payload and payload.device,
		touchEnabled = UserInputService.TouchEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		mouseEnabled = UserInputService.MouseEnabled,
		viewport = if camera then { camera.ViewportSize.X, camera.ViewportSize.Y } else nil,
		platformIsTenFoot = GuiService:IsTenFootInterface(),
	}
	local capturedSpecies = nil

	local hud = player:WaitForChild("PlayerGui"):WaitForChild("MimicHud", 15)
	check("hud.construit", function()
		expect(hud ~= nil, "ScreenGui MimicHud absent après 15 s")
		for _, name in { "Counter", "Banner", "Toasts", "Action", "Scan", "Codex", "Capture", "Discovery" } do
			expect(hud:FindFirstChild(name) ~= nil, "élément absent : " .. name)
		end
	end)

	check("hud.disposition_selon_appareil", function()
		expect(hud ~= nil, "HUD absent")
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		env.touchLayout = touch
		local action = hud:FindFirstChild("Action") :: TextButton
		local pulse = hud.Capture:FindFirstChild("Pulse") :: TextButton
		local layout = hud:GetAttribute("Layout")
		env.layout = layout
		env.pulseText = pulse.Text
		env.keyHintVisible = (action:FindFirstChild("KeyHint") :: TextLabel).Visible
		if touch then
			expect(
				layout == "touch" or layout == "touchCompact",
				"disposition tactile attendue, obtenu " .. tostring(layout)
			)
			expect(pulse.Text == "IMPULSION !", "texte tactile attendu, obtenu " .. pulse.Text)
			expect(not env.keyHintVisible, "indices de touches clavier visibles en tactile")
		else
			expect(layout == "pc", "disposition PC attendue, obtenu " .. tostring(layout))
			expect(env.keyHintVisible, "indices de touches clavier masqués sur PC")
		end
	end)

	check("hud.tient_dans_l_ecran", function()
		expect(hud ~= nil, "HUD absent")
		-- Au lancement du client, la caméra vaut encore 1×1 le temps que Studio dimensionne la vue
		-- (constaté dans la VM : vue mesurée 1×1 alors qu'elle s'affichait normalement).
		local function viewSize(): Vector2
			return if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.zero
		end
		local deadline = os.clock() + 5
		while (viewSize().X < 320 or viewSize().Y < 240) and os.clock() < deadline do
			task.wait(0.1)
		end
		task.wait(0.2) -- laisse l'interface se recalculer à la nouvelle taille
		local view = viewSize()
		local screen = hud.AbsoluteSize
		env.screen = { screen.X, screen.Y }
		env.viewport = { view.X, view.Y }
		if view.X < 320 or view.Y < 240 then
			-- Vue jamais dimensionnée après 5 s : la géométrie n'est pas mesurable dans cette session.
			skip(string.format("vue de rendu %dx%d après 5 s : géométrie non mesurable", view.X, view.Y))
		end
		-- La disposition suit la taille finale : sur téléphone (petit côté ≤ 500 px), la compacte.
		env.layout = hud:GetAttribute("Layout")
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			local expected = if math.min(screen.X, screen.Y) <= 500 then "touchCompact" else "touch"
			expect(env.layout == expected, "disposition " .. expected .. " attendue, obtenu " .. tostring(env.layout))
		end
		-- Positions réellement appliquées par Roblox (y compris les éléments masqués pour l'instant).
		local names = { "Counter", "Banner", "Action", "Scan", "Codex", "Signal", "Capture" }
		local rects = {}
		env.rects = {}
		for _, name in names do
			local gui = hud:FindFirstChild(name) :: GuiObject
			local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
			rects[name] = { x = pos.X, y = pos.Y, w = size.X, h = size.Y }
			env.rects[name] = string.format("%d,%d %dx%d", pos.X, pos.Y, size.X, size.Y)
			expect(pos.X >= 0 and pos.Y >= 0, name .. " déborde en haut/gauche (" .. env.rects[name] .. ")")
			expect(
				pos.X + size.X <= screen.X + 1 and pos.Y + size.Y <= screen.Y + 1,
				name .. " déborde de l'écran (" .. env.rects[name] .. ")"
			)
		end
		local function overlaps(a, b)
			-- 1 px de tolérance pour les arrondis.
			return a.x + 1 < b.x + b.w and b.x + 1 < a.x + a.w and a.y + 1 < b.y + b.h and b.y + 1 < a.y + a.h
		end
		local persistent = { "Counter", "Banner", "Action", "Scan", "Codex", "Signal" }
		for i, a in persistent do
			for j = i + 1, #persistent do
				local b = persistent[j]
				expect(not overlaps(rects[a], rects[b]), a .. " chevauche " .. b)
			end
		end
		for _, name in { "Counter", "Banner", "Action", "Scan", "Codex" } do
			expect(not overlaps(rects.Capture, rects[name]), "le minijeu chevauche " .. name)
		end
	end)

	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 15)
	task.wait(1)

	check("tutoriel.bandeau_initial", function()
		local banner = hud and hud:FindFirstChild("Banner") :: Frame
		expect(banner and banner.Visible, "bandeau du tutoriel non affiché")
	end)

	local scan
	check("e2e.scan", function()
		scan = request("RequestScan", "ScanResult", 5)
		expect(scan ~= nil, "pas de ScanResult")
		expect(scan.ok, "scan refusé : " .. tostring(scan.reason))
		expect(scan.band == "Strong", "signal TRÈS FORT attendu près de la chaise, obtenu " .. tostring(scan.band))
	end)

	local inspect
	check("e2e.examiner_tutoriel", function()
		task.wait(0.6)
		inspect = request("RequestInspect", "InspectResult", 5, "TUTO")
		expect(inspect ~= nil, "pas d'InspectResult")
		expect(
			inspect.ok and inspect.result == "Mimic",
			"Mimic attendu, obtenu " .. tostring(inspect.result or inspect.reason)
		)
		expect(inspect.speciesId == "chairy", "Chairy attendu")
	end)

	check("e2e.capture_complete", function()
		expect(inspect and inspect.mimicId, "pré-requis : révélation")
		local resolved = nil
		local inventory = nil
		local c1 = remote("CaptureResolved").OnClientEvent:Connect(function(p)
			resolved = p
		end)
		local c2 = remote("CollectionDelta").OnClientEvent:Connect(function(p)
			inventory = p
		end)
		local started = request("RequestCapture", "CaptureStarted", 5, inspect.mimicId)
		expect(started and started.ok, "CaptureStarted refusé : " .. tostring(started and started.reason))
		local stage, stageStart = started.stage, os.clock()
		local hits = 0
		for _ = 1, 6 do
			-- Vise le centre de la zone avec la même formule que le serveur.
			local t = if stage.phase == 0 then stage.center / stage.speed else (1 - stage.center) / stage.speed
			while t < GameConfig.Capture.MinStageElapsed + 0.05 do
				t += 2 / stage.speed
			end
			while os.clock() - stageStart < t do
				task.wait()
			end
			local elapsed = os.clock() - stageStart
			local reply = request("SubmitPulse", "PulseResult", 5, started.attemptId, elapsed)
			expect(reply and reply.ok, "impulsion refusée : " .. tostring(reply and reply.reason))
			if reply.hit then
				hits += 1
			end
			if reply.stage then
				stage, stageStart = reply.stage, os.clock()
			end
			if reply.status ~= "Active" then
				break
			end
		end
		local deadline = os.clock() + 5
		while (resolved == nil or inventory == nil) and os.clock() < deadline do
			task.wait()
		end
		c1:Disconnect()
		c2:Disconnect()
		expect(hits >= 2, "2 impulsions réussies attendues, obtenu " .. hits)
		expect(resolved and resolved.success, "capture non confirmée par le serveur")
		expect(
			inventory and inventory.added and inventory.added.speciesId == "chairy",
			"exemplaire Chairy absent de la collection"
		)
		expect(type(inventory.added.id) == "string" and inventory.added.id ~= "", "identifiant d'exemplaire absent")
		-- Le Mimic du tutoriel est toujours Standard.
		expect(inventory.added.mutation == "Standard", "mutation du tutoriel : " .. tostring(inventory.added.mutation))
		capturedSpecies = "chairy"
		env.specimenId = inventory.added.id
		-- Contrôle indicatif de cohérence affichage/serveur (non bloquant).
		env.cursorCheck = CaptureMinigame.cursorAt(stage, 0)
	end)

	check("hud.carte_decouverte", function()
		local popup = hud and hud:FindFirstChild("Discovery") :: Frame
		expect(popup and popup.Visible, "carte « Nouvelle espèce » non affichée")
	end)

	check("hud.compteur_mis_a_jour", function()
		local stats = hud and hud.Counter:FindFirstChild("Stats") :: TextLabel
		local deadline = os.clock() + 3
		while stats and not string.find(stats.Text, "Captures : 1", 1, true) and os.clock() < deadline do
			task.wait(0.1)
		end
		expect(
			stats and string.find(stats.Text, "Captures : 1", 1, true),
			"compteur : " .. tostring(stats and stats.Text)
		)
	end)

	bus:FireServer("report", { results = results, env = env, capturedSpecies = capturedSpecies })
end

bus.OnClientEvent:Connect(function(kind, payload)
	if kind == "run" and not running then
		running = true
		local ok, err = pcall(runTests, payload)
		if not ok then
			bus:FireServer(
				"report",
				{ results = { { name = "client.erreur", ok = false, message = tostring(err), duration = 0 } } }
			)
		end
	elseif kind == "leave" then
		if StudioTestService:CanLeaveTest() then
			StudioTestService:LeaveTest()
		end
	end
end)
