--!strict
--[[
	ScannerController — détection côté client.

	- SCAN (E / bouton / X manette) : onde visuelle + demande au serveur, qui
	  répond par une intensité de signal (jamais une position) et fait
	  sursauter les Mimics très proches.
	- EXAMINER / CAPTURER (F / bouton / Y manette / clic / toucher) : vise
	  l'objet le plus pertinent à portée et l'envoie au serveur.

	La visée est une aide à l'ergonomie : le serveur revérifie tout.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Objectives = require(Shared.Config.Objectives)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local Theme = require(Client.UI.Theme)
local PropTracker = require(script.Parent.PropTracker)
local MimicVisuals = require(script.Parent.MimicVisuals)

type Target = { kind: "Prop" | "Mimic", propId: string, mimicId: string?, model: Model }

local ScannerController = {}

local localPlayer = Players.LocalPlayer
local refs: any
local target: Target? = nil
local highlight: Highlight
local scanReadyAt = 0
local inspectPendingUntil = 0
local signalToken = 0

local INSPECT_RANGE = GameConfig.Inspect.Range - 0.5
local CAPTURE_RANGE = GameConfig.Capture.Range - 1

local BANDS = {
	Strong = { text = "TRÈS FORT", bars = 3, color = Theme.Colors.Pink },
	Medium = { text = "MOYEN", bars = 2, color = Theme.Colors.Yellow },
	Weak = { text = "FAIBLE", bars = 1, color = Theme.Colors.Cyan },
	None = { text = "AUCUN", bars = 0, color = Theme.Colors.Muted },
}

local REASONS: { [string]: string } = {
	OutOfRange = "Approche-toi davantage.",
	NoCharacter = "Ton personnage n'est pas prêt.",
	NotOwner = "Ce Mimic a été repéré par un autre chasseur.",
	Expired = "Trop tard… il s'est faufilé ailleurs.",
	AlreadyCapturing = "Termine d'abord ta capture en cours.",
	UnknownMimic = "Ce Mimic n'est plus là.",
	ProfileUnavailable = "Ton profil n'est pas encore sauvegardable : capture impossible pour l'instant.",
	CollectionFull = "Collection pleine (2000 Mimics) : impossible d'en capturer davantage pour l'instant.",
}

local function rootPart(): BasePart?
	local character = localPlayer.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- ─── Visée ─────────────────────────────────────────────────────────────

local function mimicTarget(info: ClientState.MimicInfo): Target?
	local model = MimicVisuals.getModel(info.mimicId)
	if model == nil then
		return nil
	end
	return { kind = "Mimic", propId = info.propId, mimicId = info.mimicId, model = model }
end

-- Traduit une part touchée (rayon) en cible, ou nil.
local function targetFromPart(part: Instance?): Target?
	local mimicId = MimicVisuals.mimicIdFromPart(part)
	if mimicId then
		local info = ClientState.mimics[mimicId]
		if info and info.ownerUserId == ClientState.userId and info.state == "Revealed" then
			return mimicTarget(info)
		end
		if info then
			-- Mimic d'un autre chasseur : on examine son objet (le serveur répondra « occupé »).
			local prop = PropTracker.get(info.propId)
			return if prop then { kind = "Prop", propId = info.propId, model = prop } else nil
		end
		return nil
	end
	local propId, prop = PropTracker.fromPart(part)
	if propId and prop then
		local info = ClientState.mimicAtProp(propId)
		if info and info.ownerUserId == ClientState.userId and info.state == "Revealed" then
			return mimicTarget(info)
		end
		return { kind = "Prop", propId = propId, model = prop }
	end
	return nil
end

local function inRange(t: Target, root: BasePart): boolean
	local range = if t.kind == "Mimic" then CAPTURE_RANGE else INSPECT_RANGE
	return flatDistance(t.model:GetPivot().Position, root.Position) <= range
end

-- `viewport` : coordonnées incluant la barre Roblox (GetMouseLocation) ;
-- sinon coordonnées d'InputObject / TouchTapInWorld (barre exclue).
local function raycastScreen(position: Vector2, viewport: boolean?): Instance?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ray = if viewport
		then camera:ViewportPointToRay(position.X, position.Y)
		else camera:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if localPlayer.Character then
		table.insert(exclude, localPlayer.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	return if result then result.Instance else nil
end

local function chooseTarget(): Target?
	local root = rootPart()
	if root == nil or ClientState.attemptActive then
		return nil
	end
	-- 1. Mon Mimic révélé, prioritaire.
	local mine = ClientState.myRevealedMimic()
	if mine then
		local t = mimicTarget(mine)
		if t and inRange(t, root) then
			return t
		end
	end
	-- 2. Survol souris (PC).
	if UserInputService.MouseEnabled and not Theme.isTouch() then
		local hovered = targetFromPart(raycastScreen(UserInputService:GetMouseLocation(), true))
		if hovered and inRange(hovered, root) then
			return hovered
		end
	end
	-- 3. L'objet le mieux placé face à la caméra.
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0 then flatLook.Unit else Vector3.zAxis
	local best: Target? = nil
	local bestScore = -math.huge
	for propId, model in PropTracker.all() do
		if PropTracker.isHidden(propId) or model.Parent == nil then
			continue
		end
		local position = model:GetPivot().Position
		local distance = flatDistance(position, root.Position)
		if distance <= INSPECT_RANGE then
			local offset = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
			local facing = if offset.Magnitude > 0.1 then flatLook:Dot(offset.Unit) else 1
			local score = facing * 1.5 - distance / INSPECT_RANGE
			if score > bestScore then
				bestScore = score
				best = { kind = "Prop", propId = propId, model = model }
			end
		end
	end
	return best
end

local function refreshActionButton()
	local button = refs.actionButton :: TextButton
	if ClientState.attemptActive then
		button.Visible = false
		return
	end
	button.Visible = true
	local t = target
	if t and t.kind == "Mimic" then
		button.Text = "CAPTURER !"
		button.BackgroundColor3 = Color3.fromRGB(190, 60, 130)
		button.BackgroundTransparency = 0
	elseif t then
		button.Text = "EXAMINER"
		button.BackgroundColor3 = Color3.fromRGB(70, 52, 120)
		button.BackgroundTransparency = 0
	else
		button.Text = "EXAMINER"
		button.BackgroundColor3 = Color3.fromRGB(60, 56, 72)
		button.BackgroundTransparency = 0.45
	end
end

local function updateTarget()
	target = chooseTarget()
	local t = target
	if t then
		highlight.Adornee = t.model
		highlight.Enabled = true
		if t.kind == "Mimic" then
			highlight.OutlineColor = Theme.Colors.Yellow
			highlight.FillColor = Theme.Colors.Pink
			highlight.FillTransparency = 0.7
		else
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.FillColor = Color3.new(1, 1, 1)
			highlight.FillTransparency = 0.92
		end
	else
		highlight.Enabled = false
		highlight.Adornee = nil
	end
	refreshActionButton()
end

-- ─── Actions ───────────────────────────────────────────────────────────

local function act(t: Target?)
	if ClientState.attemptActive then
		return
	end
	if t == nil then
		ClientState.toast("Approche-toi d'un objet pour l'examiner.")
		return
	end
	if t.kind == "Mimic" and t.mimicId then
		Remotes.get("RequestCapture"):FireServer(t.mimicId)
		return
	end
	if os.clock() < inspectPendingUntil then
		return
	end
	inspectPendingUntil = os.clock() + 1
	Audio.play("UiClick")
	Remotes.get("RequestInspect"):FireServer(t.propId)
end

local function radar(root: BasePart)
	local sphere = Instance.new("Part")
	sphere.Name = "ScanWave"
	sphere.Shape = Enum.PartType.Ball
	sphere.Material = Enum.Material.ForceField
	-- Couleur de scanner équipée (récompense d'objectif), Cyan par défaut.
	local summary = ClientState.summary
	local cosmetic = Objectives.cosmetic(summary and summary.cosmetics and summary.cosmetics.scannerColor)
	sphere.Color = if cosmetic then Theme.rgb(cosmetic.color) else Theme.Colors.Cyan
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Size = Vector3.one * 4
	sphere.CFrame = CFrame.new(root.Position)
	sphere.Parent = MimicVisuals.effectsFolder()
	task.spawn(function()
		local diameter = GameConfig.Scanner.SignalRange * 2
		Animate.run(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			sphere.Size = Vector3.one * Animate.lerp(4, diameter, a)
			sphere.Transparency = Animate.lerp(0.1, 1, a)
		end)
		sphere:Destroy()
	end)
end

local function scan()
	if ClientState.attemptActive or os.clock() < scanReadyAt then
		return
	end
	local root = rootPart()
	if root == nil then
		return
	end
	local cooldown = GameConfig.Scanner.Cooldown
	scanReadyAt = os.clock() + cooldown
	radar(root)
	Audio.play("Scan")
	Remotes.get("RequestScan"):FireServer()
	local overlay = refs.scanCooldown :: Frame
	overlay.Size = UDim2.fromScale(1, 1)
	Animate.tween(overlay, cooldown, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Linear)
end

local function showSignal(band: string)
	local spec = BANDS[band] or BANDS.None
	local frame = refs.signal :: Frame
	frame.Visible = true
	refs.signalText.Text = "SIGNAL : " .. spec.text
	refs.signalText.TextColor3 = spec.color
	-- Retour sonore lisible sans regarder l'écran : un bip par barre, de plus en plus aigu,
	-- et les barres s'allument au même rythme. Aucun signal : un son sourd.
	for _, bar in refs.signalBars do
		bar.BackgroundColor3 = Theme.Colors.Muted
		bar.BackgroundTransparency = 0.6
	end
	if spec.bars > 0 then
		for i = 1, spec.bars do
			task.delay((i - 1) * 0.12, function()
				local bar = refs.signalBars[i]
				bar.BackgroundColor3 = spec.color
				bar.BackgroundTransparency = 0
				bar.Size = UDim2.new(0, 10, i / 3 + 0.15, 0)
				Animate.tween(bar, 0.12, { Size = UDim2.new(0, 10, i / 3, 0) })
				Audio.play("ScanHit", 0.75 + i * 0.22)
			end)
		end
	else
		Audio.play("Ordinary", 0.7)
	end
	signalToken += 1
	local token = signalToken
	task.delay(3.5, function()
		if token == signalToken then
			frame.Visible = false
		end
	end)
end

local function onScanResult(payload: any)
	if payload.ok then
		showSignal(payload.band)
		if payload.band == "None" then
			ClientState.toast("Rien par ici… essaie une autre zone.")
		end
	elseif payload.reason == "Cooldown" and type(payload.remaining) == "number" then
		scanReadyAt = os.clock() + payload.remaining
	end
end

local function onInspectResult(payload: any)
	inspectPendingUntil = 0
	if not payload.ok then
		local message = REASONS[payload.reason]
		if message then
			ClientState.toast(message)
		end
		return
	end
	if payload.result == "Ordinary" then
		Audio.play("Ordinary")
		ClientState.toast(string.format("Ce n'est qu'une %s ordinaire.", MimicCatalog.kindName(payload.kind)))
		local prop = PropTracker.get(payload.propId)
		if prop then
			MimicVisuals.burst(prop:GetPivot().Position + Vector3.new(0, 2, 0), Color3.fromRGB(220, 220, 230), 6)
		end
	elseif payload.result == "Mimic" then
		if not payload.already then
			local species = MimicCatalog.get(payload.speciesId)
			ClientState.toast(
				string.format("UN MIMIC ! %s ! Capture-le vite !", if species then species.name else "?"),
				"mimic"
			)
		end
	elseif payload.result == "Busy" then
		local owner = if payload.ownerUserId then Players:GetPlayerByUserId(payload.ownerUserId) else nil
		ClientState.toast((if owner then owner.DisplayName else "Un chasseur") .. " est déjà sur ce Mimic !")
	elseif payload.result == "Fled" then
		ClientState.toast("Trop tard, il s'enfuit !")
	end
end

local function onCaptureRefused(payload: any)
	if payload.ok then
		return
	end
	local message = REASONS[payload.reason]
	if message then
		ClientState.toast(message)
	end
end

function ScannerController.start(hudRefs: any)
	refs = hudRefs
	highlight = Instance.new("Highlight")
	highlight.Name = "MimicTargetHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Parent = MimicVisuals.effectsFolder()

	ContextActionService:BindAction("MH_Scan", function(_, state)
		if state == Enum.UserInputState.Begin then
			scan()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("MH_Action", function(_, state)
		if state == Enum.UserInputState.Begin then
			act(target)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

	refs.scanButton.Activated:Connect(scan)
	refs.actionButton.Activated:Connect(function()
		act(target)
	end)

	-- Clic souris sur un objet du monde.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or ClientState.attemptActive then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local root = rootPart()
			local t = targetFromPart(raycastScreen(Vector2.new(input.Position.X, input.Position.Y)))
			if t and root and inRange(t, root) then
				act(t)
			end
		end
	end)
	-- Toucher un objet du monde (mobile).
	UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if processedByUI or ClientState.attemptActive then
			return
		end
		local root = rootPart()
		local t = targetFromPart(raycastScreen(position))
		if t and root and inRange(t, root) then
			act(t)
		end
	end)

	Remotes.get("ScanResult").OnClientEvent:Connect(onScanResult)
	Remotes.get("InspectResult").OnClientEvent:Connect(onInspectResult)
	Remotes.get("CaptureStarted").OnClientEvent:Connect(onCaptureRefused)
	ClientState.AttemptChanged:Connect(refreshActionButton)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			updateTarget()
		end
	end)
end

return ScannerController
