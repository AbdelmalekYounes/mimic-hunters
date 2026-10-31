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

--[[
	Bouclier d'entrées. Constaté le 31/10/2026 : sur le bureau Windows caché, Studio reçoit
	quand même des clics et des touches (entrée brute du système) pendant que l'utilisateur se
	sert de son PC. Ils déclenchaient des captures, des impulsions et des déplacements parasites.
	Les tests n'utilisent jamais le clavier ni la souris (tout passe par les RemoteEvents) :
	on neutralise donc toutes ces entrées dans le client de test.
]]
local ContextActionService = game:GetService("ContextActionService")
ContextActionService:BindActionAtPriority(
	"MH_TestInputShield",
	function()
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value + 1000,
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.Touch,
	Enum.KeyCode.Space,
	Enum.KeyCode.E,
	Enum.KeyCode.F,
	Enum.KeyCode.C,
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Slash,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY,
	Enum.KeyCode.ButtonSelect,
	Enum.KeyCode.Thumbstick1
)
do
	-- Clics sur le monde : absorbés par une couche transparente (« traités par l'interface »).
	local shield = Instance.new("ScreenGui")
	shield.Name = "MH_TestShield"
	shield.DisplayOrder = 1000
	shield.IgnoreGuiInset = true
	shield.ResetOnSpawn = false
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Text = ""
	blocker.BackgroundTransparency = 1
	blocker.AutoButtonColor = false
	blocker.Selectable = false
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Parent = shield
	shield.Parent = player:WaitForChild("PlayerGui")
	-- Personnage immobile : aucune touche ne peut l'éloigner de l'objet du tutoriel.
	local function freeze(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
		end
	end
	if player.Character then
		task.spawn(freeze, player.Character)
	end
	player.CharacterAdded:Connect(freeze)
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
			-- Prochain passage du curseur au centre, jamais dans le passé (robuste à un à-coup du client).
			local earliest = math.max(GameConfig.Capture.MinStageElapsed + 0.05, os.clock() - stageStart + 0.05)
			while t < earliest do
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

	-- ─── Capture rare par le réseau (révélation de mutation) ──────────────
	check("e2e.capture_mutation", function()
		-- PC : Chromatic ; mobile simulé : Spectral (les deux apparaissent dans les captures d'écran).
		-- Appareil déclaré par le pilote : la détection tactile peut être lue avant la simulation.
		local wanted = if payload and payload.device and payload.device ~= "pc" then "Spectral" else "Chromatic"
		local ready = nil
		local conn = bus.OnClientEvent:Connect(function(kind, data)
			if kind == "mutation_ready" then
				ready = data
			end
		end)
		task.wait(1.5) -- laisse finir la carte de la capture précédente
		bus:FireServer("prepare_mutation", { mutation = wanted })
		local deadline = os.clock() + 6
		while ready == nil and os.clock() < deadline do
			task.wait(0.1)
		end
		conn:Disconnect()
		expect(ready and ready.ok, "préparation : " .. tostring(ready and ready.reason))
		local resolved, delta = nil, nil
		local c1 = remote("CaptureResolved").OnClientEvent:Connect(function(p)
			resolved = p
		end)
		local c2 = remote("CollectionDelta").OnClientEvent:Connect(function(p)
			delta = p
		end)
		local started = request("RequestCapture", "CaptureStarted", 5, ready.mimicId)
		expect(started and started.ok, "CaptureStarted refusé : " .. tostring(started and started.reason))
		local stage, stageStart = started.stage, os.clock()
		for _ = 1, 6 do
			local t = if stage.phase == 0 then stage.center / stage.speed else (1 - stage.center) / stage.speed
			-- Prochain passage du curseur au centre, jamais dans le passé (robuste à un à-coup du client).
			local earliest = math.max(GameConfig.Capture.MinStageElapsed + 0.05, os.clock() - stageStart + 0.05)
			while t < earliest do
				t += 2 / stage.speed
			end
			while os.clock() - stageStart < t do
				task.wait()
			end
			local reply = request("SubmitPulse", "PulseResult", 5, started.attemptId, os.clock() - stageStart)
			expect(reply and reply.ok, "impulsion refusée : " .. tostring(reply and reply.reason))
			if reply.stage then
				stage, stageStart = reply.stage, os.clock()
			end
			if reply.status ~= "Active" then
				break
			end
		end
		deadline = os.clock() + 5
		while (resolved == nil or delta == nil) and os.clock() < deadline do
			task.wait()
		end
		c1:Disconnect()
		c2:Disconnect()
		expect(
			resolved and resolved.success,
			"capture rare non confirmée : " .. tostring(resolved and resolved.reason)
		)
		expect(resolved.mutation == wanted, "mutation : " .. tostring(resolved.mutation))
		expect(delta and delta.added and delta.added.mutation == wanted, "exemplaire muté absent de la collection")
		env.mutationSpecimen = delta.added.id
		-- Carte de capture dédiée (titre de la mutation).
		task.wait(1.2)
		local headline = hud.Discovery:FindFirstChild("Headline") :: TextLabel
		expect(
			headline and string.find(headline.Text, string.upper(wanted), 1, true),
			"carte : " .. tostring(headline and headline.Text)
		)
		task.wait(2.2)
	end)

	-- ─── Panneau Collection (Codex, Inventaire, fiche, favori) ───────────
	-- Modules du jeu côté client : même instance que l'interface affichée.
	local clientRoot = player:WaitForChild("PlayerScripts"):WaitForChild("Client", 10)
	local CollectionPanel = clientRoot and require(clientRoot.UI.CollectionPanel) :: any
	local ClientState = clientRoot and require(clientRoot.ClientState) :: any
	local panel = hud and hud:FindFirstChild("CollectionPanel") :: Frame
	-- Pause courte par vue : laisse le temps aux captures d'écran de la VM (une toutes les 2 s).
	local VIEW_PAUSE = 2.2

	local function inside(child: GuiObject, parent: GuiObject): boolean
		local p, s = child.AbsolutePosition, child.AbsoluteSize
		local pp, ps = parent.AbsolutePosition, parent.AbsoluteSize
		return p.X >= pp.X - 1 and p.Y >= pp.Y - 1 and p.X + s.X <= pp.X + ps.X + 1 and p.Y + s.Y <= pp.Y + ps.Y + 1
	end

	check("collection.panneau_ouvert", function()
		expect(CollectionPanel and panel, "panneau Collection absent")
		CollectionPanel.setOpen(true)
		CollectionPanel.showTab("Codex")
		task.wait(0.3)
		expect(panel.Visible, "panneau non affiché")
		local screen = hud.AbsoluteSize
		local p, s = panel.AbsolutePosition, panel.AbsoluteSize
		env.panel = string.format("%d,%d %dx%d", p.X, p.Y, s.X, s.Y)
		expect(p.X >= 0 and p.Y >= 0 and p.X + s.X <= screen.X + 1 and p.Y + s.Y <= screen.Y + 1, "panneau hors écran")
		local completion = panel:FindFirstChild("Completion") :: TextLabel
		local discovered = ClientState.summary and ClientState.summary.discovered or 0
		env.discovered = discovered
		expect(discovered >= 1, "aucune espèce découverte")
		expect(
			completion and string.find(completion.Text, tostring(discovered) .. "/6", 1, true),
			"complétion : " .. tostring(completion and completion.Text)
		)
		task.wait(VIEW_PAUSE)
	end)

	check("collection.codex", function()
		local grid = panel:FindFirstChild("CodexPage", true) :: Frame
		expect(grid and grid.Visible, "onglet Codex non affiché")
		-- Visibilité réelle : la page remplit le contenu et les cartes sont dans le panneau.
		expect(grid.AbsoluteSize.X > panel.AbsoluteSize.X * 0.8, "page Codex trop étroite : " .. grid.AbsoluteSize.X)
		local firstCard = grid:FindFirstChild("chairy", true) :: GuiObject
		expect(
			firstCard and firstCard.AbsoluteSize.X > 60 and inside(firstCard, panel),
			"carte du codex invisible ou hors du panneau"
		)
		local chairy = grid:FindFirstChild("chairy", true) :: GuiObject
		local name = chairy and chairy:FindFirstChild("Name") :: TextLabel
		expect(name and name.Text == "Chairy", "Chairy non découvert dans le codex")
		-- Chaque espèce : nom si découverte, « ??? » sinon (au plus 2 découvertes dans ce test).
		local hiddenCount = 0
		for _, species in { "chairy", "trashling", "posty", "lumino", "chompy", "vendoo" } do
			local card = grid:FindFirstChild(species, true) :: GuiObject
			local label = card and card:FindFirstChild("Name") :: TextLabel
			local known = ClientState.summary.codex[species] ~= nil
			expect(
				label and ((known and label.Text ~= "???") or (not known and label.Text == "???")),
				species .. " mal affiché"
			)
			if not known then
				hiddenCount += 1
			end
		end
		expect(hiddenCount >= 4, "espèces manquantes : " .. hiddenCount)
		local chances = grid:FindFirstChild("Chances") :: TextLabel
		expect(chances and string.find(chances.Text, "Chromatic 4 %", 1, true), "probabilités non affichées")
	end)

	check("collection.inventaire_et_fiche", function()
		expect(env.specimenId, "pré-requis : exemplaire capturé")
		CollectionPanel.showTab("Inventory")
		CollectionPanel.select(env.specimenId)
		task.wait(0.4)
		local page = panel:FindFirstChild("InventoryPage", true) :: Frame
		expect(page and page.Visible, "onglet Inventaire non affiché")
		local detail = page:FindFirstChild("Detail") :: Frame
		expect(detail and detail.Visible, "fiche détaillée non affichée")
		local idLabel = detail:FindFirstChild("Id", true) :: TextLabel
		expect(idLabel and string.find(idLabel.Text, env.specimenId, 1, true), "fiche d'un autre exemplaire")
		local preview = detail:FindFirstChild("Preview") :: ViewportFrame
		expect(preview and preview:FindFirstChildWhichIsA("Model") ~= nil, "aperçu 3D absent")
		for _, name in { "Filters", "Detail" } do
			local child = page:FindFirstChild(name) :: GuiObject
			expect(child and inside(child, panel), name .. " déborde du panneau")
		end
		local grid = page:FindFirstChild("Grid") :: Frame
		if grid.Visible then
			expect(grid:FindFirstChild(env.specimenId) ~= nil, "carte de l'exemplaire absente de la grille")
			local g, d = grid.AbsolutePosition, detail.AbsolutePosition
			expect(g.X + grid.AbsoluteSize.X <= d.X + 1, "grille et fiche se chevauchent")
		end
		env.detailMode = if grid.Visible then "colonne" else "superposée"
		task.wait(VIEW_PAUSE)
	end)

	check("collection.favori", function()
		local reply = request("SetFavorite", "CollectionResult", 5, env.specimenId, true)
		expect(reply and reply.ok, "favori refusé : " .. tostring(reply and reply.reason))
		local deadline = os.clock() + 3
		while os.clock() < deadline and not ClientState.specimensById[env.specimenId].favorite do
			task.wait(0.1)
		end
		expect(ClientState.specimensById[env.specimenId].favorite == true, "favori non appliqué côté client")
		local favorite = panel:FindFirstChild("Favorite", true) :: TextButton
		expect(favorite and string.find(favorite.Text, "★", 1, true), "bouton favori non mis à jour")
		local bad = request("SetFavorite", "CollectionResult", 5, "S1-999999", true)
		expect(bad and not bad.ok and bad.reason == "NotOwned", "favori d'un exemplaire non possédé accepté")
		task.wait(VIEW_PAUSE)
	end)

	check("collection.objectifs_et_titre", function()
		CollectionPanel.showTab("Objectives")
		task.wait(0.3)
		local page = panel:FindFirstChild("ObjectivesPage", true) :: Frame
		expect(page and page.Visible, "onglet Objectifs non affiché")
		expect(
			page.AbsoluteSize.X > panel.AbsoluteSize.X * 0.8,
			"page Objectifs trop étroite : " .. page.AbsoluteSize.X
		)
		local firstRow = page:FindFirstChild("first_capture", true) :: GuiObject
		expect(
			firstRow and firstRow.AbsoluteSize.X > 200 and inside(firstRow, panel),
			"ligne d'objectif invisible ou hors du panneau"
		)
		local row = page:FindFirstChild("first_capture", true) :: Frame
		local status = row and row:FindFirstChild("Status") :: TextLabel
		expect(
			status and status.Text == "✓",
			"objectif « Première capture » non validé : " .. tostring(status and status.Text)
		)
		local pending = page:FindFirstChild("ten_captures", true) :: Frame
		local progress = pending and pending:FindFirstChild("Status") :: TextLabel
		expect(
			progress and progress.Text == string.format("%d/10", ClientState.summary.totalCaptures),
			"progression « Dix captures » : " .. tostring(progress and progress.Text)
		)
		local reply = request("EquipCosmetic", "CollectionResult", 5, "title", "title_apprentice")
		expect(reply and reply.ok, "titre refusé : " .. tostring(reply and reply.reason))
		local deadline = os.clock() + 4
		local head = player.Character and player.Character:FindFirstChild("Head")
		while os.clock() < deadline and not (head and head:FindFirstChild("MimicTitle")) do
			task.wait(0.1)
		end
		expect(player:GetAttribute("MimicTitle") == "title_apprentice", "attribut de titre non posé par le serveur")
		expect(head and head:FindFirstChild("MimicTitle") ~= nil, "titre non affiché au-dessus du personnage")
		local locked = request("EquipCosmetic", "CollectionResult", 5, "title", "title_master")
		expect(locked and not locked.ok and locked.reason == "Locked", "titre verrouillé accepté")
		task.wait(VIEW_PAUSE)
		CollectionPanel.setOpen(false)
	end)

	-- ─── Musées (V0.3) ─────────────────────────────────────────────────
	local MuseumController = clientRoot and require(clientRoot.Controllers.MuseumController) :: any
	local CollectionServiceC = game:GetService("CollectionService")
	local viewCamera = workspace.CurrentCamera

	local function rootPart(): BasePart?
		local current = player.Character
		return current and current:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	local function museumOf(userId: number): Model?
		for _, model in CollectionServiceC:GetTagged("Museum") do
			if model:GetAttribute("OwnerUserId") == userId then
				return model :: Model
			end
		end
		return nil
	end
	-- Déplacement rapide par le réseau ; attend la réponse et le déplacement du personnage.
	local function travel(kind: string, target: number?): any
		local before = rootPart() and (rootPart() :: BasePart).Position
		local reply = request("RequestTravel", "MuseumResult", 5, kind, target)
		local deadline = os.clock() + 3
		while os.clock() < deadline do
			local now = rootPart() and (rootPart() :: BasePart).Position
			if now and before and (now - before).Magnitude > 5 then
				break
			end
			task.wait(0.1)
		end
		return reply
	end
	-- Caméra de présentation (captures d'écran de la VM) : vue de trois quarts sur un musée.
	local function frameMuseum(model: Model, localOffset: CFrame?, localTarget: Vector3?)
		local floor = model.PrimaryPart :: BasePart
		viewCamera.CameraType = Enum.CameraType.Scriptable
		local eye = floor.CFrame * (localOffset or CFrame.new(0, 15, -23))
		camera.CFrame =
			CFrame.lookAt(eye.Position, (floor.CFrame * CFrame.new(localTarget or Vector3.new(0, 2, 2))).Position)
	end
	local function releaseCamera()
		viewCamera.CameraType = Enum.CameraType.Custom
	end

	check("musee.ma_base", function()
		local deadline = os.clock() + 5
		while ClientState.museumPlot == nil and os.clock() < deadline do
			task.wait(0.1)
		end
		expect(ClientState.museumPlot ~= nil, "aucune parcelle reçue")
		local mine = museumOf(player.UserId)
		expect(mine ~= nil, "musée du joueur introuvable")
		local reply = travel("base")
		expect(reply and reply.ok, "MA BASE refusé : " .. tostring(reply and reply.reason))
		local root = rootPart()
		local distance = root
			and ((root.Position - (mine :: Model).PrimaryPart.Position) * Vector3.new(1, 0, 1)).Magnitude
		expect(distance and distance < 20, "personnage loin de son musée : " .. tostring(distance))
		-- Musée vide (capture d'écran).
		frameMuseum(mine :: Model)
		task.wait(VIEW_PAUSE)
	end)

	check("musee.exposer_et_examiner", function()
		expect(env.specimenId, "pré-requis : exemplaire capturé")
		local reply = request("SetExhibit", "MuseumResult", 5, 1, env.specimenId)
		expect(reply and reply.ok, "exposition refusée : " .. tostring(reply and reply.reason))
		local mine = museumOf(player.UserId) :: Model
		local model = nil
		local deadline = os.clock() + 4
		while os.clock() < deadline and model == nil do
			local candidate = mine:FindFirstChild("Exhibits") and mine.Exhibits:FindFirstChild("Exhibit1")
			if candidate and candidate:GetAttribute("SpecimenId") == env.specimenId then
				model = candidate
			end
			task.wait(0.1)
		end
		expect(model ~= nil, "Mimic exposé absent du musée")
		expect(
			#ClientState.specimens >= 1 and ClientState.summary.museum.slots[1] == env.specimenId,
			"résumé non mis à jour"
		)
		local dup = request("SetExhibit", "MuseumResult", 5, 2, env.specimenId)
		expect(dup and not dup.ok and dup.reason == "AlreadyExhibited", "même exemplaire exposé deux fois")
		MuseumController.inspect(model)
		local sheet = MuseumController.sheet()
		task.wait(0.3)
		expect(sheet.panel.Visible, "fiche d'inspection non affichée")
		expect(string.find(sheet.number.Text, env.specimenId, 1, true), "fiche : " .. sheet.number.Text)
		expect(string.find(sheet.owner.Text, player.DisplayName, 1, true), "fiche : collectionneur absent")
		local screen = hud.AbsoluteSize
		local p, s = sheet.panel.AbsolutePosition, sheet.panel.AbsoluteSize
		expect(p.X >= 0 and p.Y >= 0 and p.X + s.X <= screen.X + 1 and p.Y + s.Y <= screen.Y + 1, "fiche hors écran")
		frameMuseum(mine, CFrame.new(-2, 7, -6), Vector3.new(-8, 2, 3))
		task.wait(VIEW_PAUSE)
		MuseumController.closeSheet()
	end)

	check("musee.onglet_vitrines_et_selecteur", function()
		local MuseumTab = require(clientRoot.UI.MuseumTab) :: any
		releaseCamera()
		CollectionPanel.setOpen(true)
		CollectionPanel.showTab("Museum")
		task.wait(0.4)
		local tabUi = MuseumTab.ui()
		expect(tabUi.page.Visible, "onglet Musée non affiché")
		for slot = 1, 6 do
			local card = tabUi.slots[slot].card :: Frame
			expect(
				card.AbsoluteSize.X > 60 and inside(card, panel),
				"vitrine " .. slot .. " invisible ou hors du panneau"
			)
		end
		expect(string.find(tabUi.slots[1].title.Text, "Chairy", 1, true), "vitrine 1 : " .. tabUi.slots[1].title.Text)
		expect(string.find(tabUi.slots[2].title.Text, "libre", 1, true), "vitrine 2 : " .. tabUi.slots[2].title.Text)
		task.wait(VIEW_PAUSE)
		MuseumTab.openPicker(2)
		task.wait(0.4)
		expect(tabUi.picker.Visible, "sélecteur non affiché")
		local card = tabUi.pickerGrid:FindFirstChild(env.specimenId)
		expect(card ~= nil, "exemplaire absent du sélecteur")
		local marked = false
		for _, d in (card :: Instance):GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, "Exposé (vitrine 1)", 1, true) then
				marked = true
			end
		end
		expect(marked, "exemplaire déjà exposé non signalé dans le sélecteur")
		task.wait(VIEW_PAUSE)
		MuseumTab.closePicker()
		CollectionPanel.setOpen(false)
	end)

	check("musee.visite_six_mimics", function()
		local ready = nil
		local conn = bus.OnClientEvent:Connect(function(kind, data)
			if kind == "museum_ready" then
				ready = data
			end
		end)
		bus:FireServer("prepare_museum")
		local deadline = os.clock() + 5
		while ready == nil and os.clock() < deadline do
			task.wait(0.1)
		end
		conn:Disconnect()
		expect(ready and ready.plot, "collectionneur fictif non préparé")
		env.collector = ready.ownerUserId
		local reply = travel("museum", ready.ownerUserId)
		expect(
			reply and reply.ok and reply.plot == ready.plot,
			"visite refusée : " .. tostring(reply and reply.reason)
		)
		local museumModel = museumOf(ready.ownerUserId) :: Model
		local count = 0
		for _, child in museumModel.Exhibits:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("Exhibit") then
				count += 1
			end
		end
		expect(count == 6, "Mimics visibles chez le collectionneur : " .. count)
		-- Vue d'ensemble, puis gros plans Chromatic (vitrine 2) et Spectral (vitrine 3).
		frameMuseum(museumModel)
		task.wait(VIEW_PAUSE)
		frameMuseum(museumModel, CFrame.new(1.5, 4.2, -2.5), Vector3.new(0, 2.6, 3))
		task.wait(VIEW_PAUSE)
		frameMuseum(museumModel, CFrame.new(5.5, 4.2, -2.5), Vector3.new(8, 2.6, 3))
		task.wait(VIEW_PAUSE)
	end)

	check("musee.retour_village", function()
		releaseCamera()
		local reply = travel("village")
		expect(reply and reply.ok, "retour au village refusé")
		local root = rootPart()
		expect(root and (root.Position * Vector3.new(1, 0, 1)).Magnitude < 25, "personnage loin du village")
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
