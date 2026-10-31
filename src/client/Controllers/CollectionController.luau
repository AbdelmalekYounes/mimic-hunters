--!strict
--[[
	CollectionController — inventaire de session vu par le joueur :
	compteur permanent, carte de découverte après chaque capture et codex.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Rarities = require(Shared.Config.Rarities)
local PropBuilder = require(Shared.Builders.PropBuilder)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local Theme = require(Client.UI.Theme)

type Card = {
	frame: Frame,
	viewport: ViewportFrame,
	name: TextLabel,
	rarity: TextLabel,
	count: TextLabel,
	description: TextLabel,
	discovered: boolean?,
}

local CollectionController = {}

local refs: any
local cards: { [string]: Card } = {}
local popupModel: Model? = nil
local popupToken = 0

local function snapshotCount(speciesId: string): number
	return ClientState.ownedCount(speciesId)
end

-- Place un modèle dans un ViewportFrame avec une caméra cadrée sur sa hauteur.
local function frameModel(viewport: ViewportFrame, model: Model, kind: string)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	model:PivotTo(CFrame.identity)
	model.Parent = viewport
	local anchor = PropBuilder.FaceAnchors[kind]
	local height = if anchor then anchor.height else 4
	local distance = height * 1.45 + 4
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame =
		CFrame.lookAt(Vector3.new(distance * 0.35, height * 0.62, -distance), Vector3.new(0, height * 0.5, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function refreshStats()
	local summary = ClientState.summary
	local total = if summary then summary.totalCaptures or 0 else 0
	local discovered = if summary then summary.discovered or 0 else 0
	refs.stats.Text = string.format("Captures : %d   ·   Espèces : %d/%d", total, discovered, MimicCatalog.count())
	refs.codexProgress.Text = string.format("%d / %d espèces découvertes", discovered, MimicCatalog.count())
end

local function refreshCard(species: any)
	local card = cards[species.id]
	if card == nil then
		return
	end
	local count = snapshotCount(species.id)
	local discovered = count > 0
	local rarity = Rarities.get(species.rarity)
	if card.discovered ~= discovered then
		card.discovered = discovered
		local model = if discovered
			then MimicModelBuilder.build(species.id)
			else MimicModelBuilder.silhouette(species.id)
		frameModel(card.viewport, model, species.kind)
	end
	card.name.Text = if discovered then species.name else "???"
	card.rarity.Text = if rarity then rarity.displayName else ""
	card.rarity.TextColor3 = if rarity then Theme.rgb(rarity.color) else Theme.Colors.Muted
	card.count.Text = if discovered then string.format("x%d", count) else ""
	card.description.Text = if discovered
		then species.description
		else string.format("Se cache en %s.", MimicCatalog.kindName(species.kind))
end

local function buildCards()
	for index, species in MimicCatalog.list() do
		local frame = Theme.panel({
			Name = species.id,
			LayoutOrder = index,
			BackgroundColor3 = Color3.fromRGB(40, 32, 62),
			Parent = refs.codexGrid,
		})
		local viewport = Theme.create("ViewportFrame", {
			Size = UDim2.new(1, -12, 0, 96),
			Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Color3.fromRGB(22, 16, 36),
			BackgroundTransparency = 0.2,
			Ambient = Color3.fromRGB(200, 190, 220),
			LightColor = Color3.fromRGB(255, 250, 240),
			LightDirection = Vector3.new(-1, -1, 1),
			Parent = frame,
		}) :: ViewportFrame
		Theme.corner(10).Parent = viewport
		local name = Theme.text({
			Text = "???",
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -12, 0, 22),
			Position = UDim2.fromOffset(6, 104),
			MaxTextSize = 20,
			Parent = frame,
		})
		local rarity = Theme.text({
			Text = "",
			Font = Theme.Fonts.Bold,
			Size = UDim2.new(0.62, -6, 0, 16),
			Position = UDim2.fromOffset(6, 126),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 14,
			Parent = frame,
		})
		local count = Theme.text({
			Text = "",
			Font = Theme.Fonts.Bold,
			TextColor3 = Theme.Colors.Mint,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.new(0.35, -6, 0, 16),
			Position = UDim2.new(1, -6, 0, 126),
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxTextSize = 14,
			Parent = frame,
		})
		local description = Theme.text({
			Text = "",
			TextColor3 = Theme.Colors.Muted,
			Size = UDim2.new(1, -12, 0, 50),
			Position = UDim2.fromOffset(6, 144),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 12,
			Parent = frame,
		})
		cards[species.id] = {
			frame = frame,
			viewport = viewport,
			name = name,
			rarity = rarity,
			count = count,
			description = description,
			discovered = nil,
		}
		refreshCard(species)
	end
end

local function setCodexVisible(visible: boolean)
	refs.codex.Visible = visible
	if visible then
		Audio.play("UiClick")
		for _, species in MimicCatalog.list() do
			refreshCard(species)
		end
	end
end

local function showDiscovery(payload: any)
	local species = MimicCatalog.get(payload.speciesId)
	if species == nil then
		return
	end
	local rarity = Rarities.get(species.rarity)
	popupToken += 1
	local token = popupToken
	refs.popupHeadline.Text = if payload.isNew then "NOUVELLE ESPÈCE !" else "CAPTURÉ !"
	refs.popupHeadline.TextColor3 = if payload.isNew then Theme.Colors.Yellow else Theme.Colors.Mint
	refs.popupName.Text = species.name
	refs.popupRarity.Text = if rarity then rarity.displayName else ""
	refs.popupRarity.TextColor3 = if rarity then Theme.rgb(rarity.color) else Theme.Colors.Text
	refs.popupCount.Text = string.format(
		"Capturé x%d   ·   Espèces %d/%d",
		payload.count or 1,
		payload.discovered or 1,
		MimicCatalog.count()
	)
	local model = MimicModelBuilder.build(species.id)
	frameModel(refs.popupViewport, model, species.kind)
	popupModel = model
	refs.popup.Visible = true
	refs.popupScale.Scale = 0.5
	Animate.tween(refs.popupScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Audio.play("Capture", if payload.isNew then 1.25 else 1)
	task.delay(if payload.isNew then 3.2 else 2.2, function()
		if token ~= popupToken then
			return
		end
		Animate.tween(refs.popupScale, 0.2, { Scale = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.2)
		if token == popupToken then
			refs.popup.Visible = false
			popupModel = nil
		end
	end)
end

function CollectionController.start(hudRefs: any)
	refs = hudRefs
	buildCards()
	refreshStats()

	refs.codexButton.Activated:Connect(function()
		setCodexVisible(not refs.codex.Visible)
	end)
	refs.codexClose.Activated:Connect(function()
		setCodexVisible(false)
	end)
	ContextActionService:BindAction("MH_Codex", function(_, state)
		if state == Enum.UserInputState.Begin then
			setCodexVisible(not refs.codex.Visible)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonSelect)

	Remotes.get("CollectionSnapshot").OnClientEvent:Connect(function(view)
		ClientState.applyCollectionSnapshot(view)
	end)
	Remotes.get("CollectionDelta").OnClientEvent:Connect(function(delta)
		ClientState.applyCollectionDelta(delta)
	end)
	Remotes.get("CollectionResult").OnClientEvent:Connect(function(payload)
		if payload.ok and payload.result then
			if payload.result.updated then
				ClientState.applySpecimenUpdate(payload.result.updated)
			end
			if payload.result.summary then
				ClientState.applyCollectionDelta({ summary = payload.result.summary })
			end
		end
	end)
	ClientState.CollectionChanged:Connect(function()
		refreshStats()
		for _, species in MimicCatalog.list() do
			refreshCard(species)
		end
	end)
	Remotes.get("CaptureResolved").OnClientEvent:Connect(function(payload)
		if payload.success then
			showDiscovery(payload)
		end
	end)

	-- Rotation lente du Mimic dans la carte de découverte.
	RunService.RenderStepped:Connect(function()
		local model = popupModel
		if model and model.Parent then
			model:PivotTo(CFrame.Angles(0, os.clock() * 1.4, 0))
		end
	end)
end

return CollectionController
