--!strict
--[[
	MuseumController — le musée côté client (V0.3).

	- Parcelle reçue du serveur (MuseumInfo), déplacements rapides MA BASE / VILLAGE
	  (boutons du HUD, touches B / V) : le serveur choisit la destination.
	- Mimics exposés « vivants » : respiration, clignement, petit mouvement occasionnel,
	  réaction quand un joueur approche, effets de mutation. Budget : 12 Mimics animés au plus
	  (les plus proches, à moins de 70 studs), 30 mises à jour par seconde ; au-delà, le modèle
	  reste immobile. Les animations ne modifient que l'affichage local : les modèles sont ceux
	  du serveur et la vitrine (solide) les contient.
	- Fiche d'inspection d'une vitrine (invite « Examiner ») : nom, rareté, mutation, taille,
	  numéro de l'exemplaire, collectionneur, aperçu 3D.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Objectives = require(Shared.Config.Objectives)
local Rarities = require(Shared.Config.Rarities)
local HudLayout = require(Shared.Logic.HudLayout)
local SpecimenLook = require(Shared.Logic.SpecimenLook)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local MutationFx = require(Client.Util.MutationFx)
local Theme = require(Client.UI.Theme)
local ModelView = require(Client.UI.ModelView)

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

local MuseumController = {}

-- Budget d'animation des Mimics exposés.
MuseumController.MaxAnimated = 12
MuseumController.AnimateDistance = 70
MuseumController.EffectsDistance = 45
MuseumController.ReactDistance = 9

type Exhibit = {
	model: Model,
	base: CFrame,
	phase: number,
	eyes: { BasePart },
	nextBlink: number,
	blinkUntil: number,
	nextFidget: number,
	fidgetStart: number,
	near: boolean,
	reactStart: number,
	displaced: boolean,
}

local exhibits: { [Model]: Exhibit } = {}
local refs: any
local sheet: any = {}
local sheetModel: Model? = nil

-- ─── Déplacements ──────────────────────────────────────────────────────

local TRAVEL_ERRORS = {
	NoPlot = "Tu n'as pas encore de musée.",
	Waiting = "Tous les musées sont pris : tu recevras le prochain qui se libère.",
	UnknownMuseum = "Ce musée n'est plus disponible.",
	RateLimited = "Un instant…",
}

function MuseumController.travel(kind: string, target: number?)
	Audio.play("UiClick")
	Remotes.get("RequestTravel"):FireServer(kind, target)
end

-- ─── Mimics exposés ────────────────────────────────────────────────────

local function register(model: Instance)
	if not model:IsA("Model") or exhibits[model] then
		return
	end
	local eyes = {}
	for _, d in model:GetDescendants() do
		if
			d:IsA("BasePart")
			and (d.Name == "EyeWhite" or d.Name == "Pupil" or d.Name == "Glint" or d.Name == "ScreenEye")
		then
			table.insert(eyes, d)
		end
	end
	local now = os.clock()
	exhibits[model] = {
		model = model,
		base = model:GetPivot(),
		phase = math.random() * math.pi * 2,
		eyes = eyes,
		nextBlink = now + 1 + math.random() * 3,
		blinkUntil = 0,
		nextFidget = now + 4 + math.random() * 6,
		fidgetStart = -1,
		near = false,
		reactStart = -1,
		displaced = false,
	}
	-- Effets de mutation (Chromatic, Spectral) : apparence recalculée depuis la graine.
	local species = MimicCatalog.get(model:GetAttribute("SpeciesId") :: string)
	local seed = model:GetAttribute("Seed")
	local mutation = model:GetAttribute("Mutation")
	if species and type(seed) == "number" and type(mutation) == "string" and Mutations.isRare(mutation) then
		MutationFx.attach(model, SpecimenLook.compute(species, seed, mutation), MuseumController.EffectsDistance)
	end
end

local function setEyes(entry: Exhibit, visible: boolean)
	for _, part in entry.eyes do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

local accumulator = 0
local function animate(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	accumulator = 0
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local now = os.clock()

	-- Les plus proches d'abord, dans la limite du budget.
	local candidates = {}
	for model, entry in exhibits do
		if model.Parent == nil then
			exhibits[model] = nil
			continue
		end
		local distance = (entry.base.Position - eye).Magnitude
		if distance <= MuseumController.AnimateDistance then
			table.insert(candidates, { entry = entry, distance = distance })
		elseif entry.displaced then
			model:PivotTo(entry.base)
			setEyes(entry, true)
			entry.displaced = false
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index, item in candidates do
		local entry = item.entry
		if index > MuseumController.MaxAnimated then
			if entry.displaced then
				entry.model:PivotTo(entry.base)
				entry.displaced = false
			end
			continue
		end
		local t = now + entry.phase
		-- Respiration : léger va-et-vient vertical et balancement.
		local offset = CFrame.new(0, math.sin(t * 1.8) * 0.06, 0) * CFrame.Angles(0, math.sin(t * 0.6) * 0.06, 0)
		-- Réaction : un joueur approche → petit bond et regard vers lui.
		local near = root ~= nil and (root.Position - entry.base.Position).Magnitude <= MuseumController.ReactDistance
		if near and not entry.near then
			entry.reactStart = now
		end
		entry.near = near
		if near and root then
			local look = entry.base:PointToObjectSpace(root.Position)
			local yaw = math.clamp(math.atan2(-look.X, -look.Z), -0.7, 0.7)
			offset *= CFrame.Angles(0, yaw, 0)
		end
		local react = now - entry.reactStart
		if react >= 0 and react < 0.45 then
			offset = CFrame.new(0, math.sin(react / 0.45 * math.pi) * 0.5, 0) * offset
		end
		-- Mouvement occasionnel : petite rotation sur place.
		if now >= entry.nextFidget then
			entry.fidgetStart = now
			entry.nextFidget = now + 6 + math.random() * 8
		end
		local fidget = now - entry.fidgetStart
		if entry.fidgetStart > 0 and fidget < 0.8 then
			offset *= CFrame.Angles(0, math.sin(fidget / 0.8 * math.pi * 2) * 0.35, 0)
		end
		entry.model:PivotTo(entry.base * offset)
		entry.displaced = true
		-- Clignement des yeux.
		if now >= entry.nextBlink then
			entry.blinkUntil = now + 0.12
			entry.nextBlink = now + 2.5 + math.random() * 3.5
		end
		setEyes(entry, now >= entry.blinkUntil)
	end
end

-- ─── Fiche d'inspection ────────────────────────────────────────────────

local function buildSheet(gui: ScreenGui)
	local panel = Theme.panel({
		Name = "ExhibitSheet",
		Visible = false,
		ZIndex = 15,
		BackgroundColor3 = Color3.fromRGB(28, 20, 46),
		BackgroundTransparency = 0.02,
		Parent = gui,
	})
	sheet.panel = panel
	sheet.scale = Theme.create("UIScale", { Scale = 1, Parent = panel }) :: UIScale
	sheet.viewport = Theme.create("ViewportFrame", {
		Name = "Preview",
		BackgroundColor3 = Color3.fromRGB(18, 12, 30),
		BackgroundTransparency = 0.15,
		Ambient = Color3.fromRGB(200, 190, 220),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, 1),
		Position = UDim2.fromOffset(10, 10),
		Parent = panel,
	}, { Theme.corner(10) }) :: ViewportFrame
	local info = Theme.create("Frame", { Name = "Info", BackgroundTransparency = 1, Parent = panel }) :: Frame
	sheet.info = info
	Theme.create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = info })
	local function line(name: string, order: number, font: Enum.Font?, size: number, color: Color3?): TextLabel
		return Theme.text({
			Name = name,
			Text = "",
			LayoutOrder = order,
			Font = font or Theme.Fonts.Body,
			TextColor3 = color or C.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, size),
			MaxTextSize = size,
			Parent = info,
		})
	end
	sheet.name = line("Name", 1, Theme.Fonts.Title, 28)
	sheet.rarity = line("Rarity", 2, Theme.Fonts.Bold, 18)
	sheet.mutation = line("Mutation", 3, Theme.Fonts.Bold, 18)
	sheet.size = line("Size", 4, nil, 16, C.Muted)
	sheet.number = line("Number", 5, nil, 15, C.Muted)
	sheet.owner = line("Owner", 6, Theme.Fonts.Bold, 17, C.Mint)
	sheet.close = Theme.button({
		Name = "Close",
		Text = "Fermer",
		BackgroundColor3 = Color3.fromRGB(110, 50, 80),
		StrokeColor = C.Pink,
		MaxTextSize = 18,
		Parent = panel,
	})
	sheet.close.Activated:Connect(function()
		MuseumController.closeSheet()
	end)

	-- Fiche centrée, plus petite que le panneau Collection, lisible sur téléphone.
	local function place()
		local size = gui.AbsoluteSize
		if size.X < 2 then
			return
		end
		local layout = HudLayout.compute(size.X, size.Y, refs.touch)
		local r = layout.panel
		local w = math.min(r.w, 620)
		local h = math.min(r.h, 330)
		panel.Position = UDim2.fromOffset(r.x + (r.w - w) / 2, r.y + (r.h - h) / 2)
		panel.Size = UDim2.fromOffset(w, h)
		local preview = math.min(math.floor(w * 0.42), h - 20)
		sheet.viewport.Size = UDim2.fromOffset(preview, h - 20)
		info.Position = UDim2.fromOffset(preview + 22, 12)
		info.Size = UDim2.fromOffset(w - preview - 34, h - 70)
		sheet.close.Position = UDim2.fromOffset(preview + 22, h - 52)
		sheet.close.Size = UDim2.fromOffset(math.min(160, w - preview - 34), 40)
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

function MuseumController.closeSheet()
	if sheet.panel and sheet.panel.Visible then
		sheet.panel.Visible = false
		sheetModel = nil
		ModelView.clear(sheet.viewport)
	end
end

-- Ouvre la fiche d'un Mimic exposé (modèle tagué « MuseumExhibit »). Utilisé aussi par les tests.
function MuseumController.inspect(model: Model)
	local species = MimicCatalog.get(model:GetAttribute("SpeciesId") :: string)
	if species == nil then
		return
	end
	local specimen = {
		id = model:GetAttribute("SpecimenId"),
		speciesId = species.id,
		rarity = model:GetAttribute("Rarity"),
		mutation = model:GetAttribute("Mutation"),
		seed = model:GetAttribute("Seed"),
	}
	local rarity = Rarities.get(specimen.rarity :: string)
	local mutation = Mutations.get(specimen.mutation :: string)
	local look = SpecimenLook.compute(species, specimen.seed :: number, specimen.mutation :: string)
	sheet.name.Text = species.name
	sheet.rarity.Text = "Rareté : " .. (if rarity then rarity.displayName else tostring(specimen.rarity))
	sheet.rarity.TextColor3 = if rarity then Theme.rgb(rarity.color) else C.Text
	if mutation and Mutations.isRare(mutation.id) then
		sheet.mutation.Text =
			string.format("Mutation : %s (%s par capture)", mutation.displayName, Mutations.chanceText(mutation.id))
		sheet.mutation.TextColor3 = Theme.rgb(mutation.color)
	else
		sheet.mutation.Text = "Apparence : Standard"
		sheet.mutation.TextColor3 = C.Muted
	end
	sheet.size.Text = string.format("Taille : %d %%", math.floor(look.scale * 100 + 0.5))
	sheet.number.Text = "Exemplaire N° " .. tostring(specimen.id)
	sheet.owner.Text = "Collection de " .. tostring(model:GetAttribute("OwnerName"))
	sheetModel = ModelView.specimen(sheet.viewport, specimen, true)
	sheet.panel.Visible = true
	sheet.scale.Scale = 0.9
	Animate.tween(sheet.scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Audio.play("UiClick", 1.15)
end

function MuseumController.sheet(): any
	return sheet
end

-- ─── Démarrage ─────────────────────────────────────────────────────────

function MuseumController.start(hudRefs: any)
	refs = hudRefs
	buildSheet(refs.gui)

	refs.baseButton.Activated:Connect(function()
		MuseumController.travel("base")
	end)
	refs.villageButton.Activated:Connect(function()
		MuseumController.travel("village")
	end)
	ContextActionService:BindAction("MH_Travel", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			MuseumController.travel(if input.KeyCode == Enum.KeyCode.B then "base" else "village")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B, Enum.KeyCode.V)

	Remotes.get("MuseumInfo").OnClientEvent:Connect(function(payload)
		local before = ClientState.museumPlot
		ClientState.museumPlot = payload.plot
		ClientState.museumWaiting = payload.waiting == true
		if payload.plot and before ~= payload.plot then
			ClientState.toast("Ton musée t'attend dans le Quartier des collectionneurs (bouton MA BASE).")
		elseif payload.waiting then
			ClientState.toast(TRAVEL_ERRORS.Waiting)
		end
		ClientState.MuseumChanged:Fire()
	end)

	Remotes.get("MuseumResult").OnClientEvent:Connect(function(payload)
		if not payload.ok then
			local message = if payload.action == "travel" then TRAVEL_ERRORS[payload.reason] else nil
			if message then
				ClientState.toast(message)
			end
			ClientState.MuseumChanged:Fire()
			return
		end
		if payload.summary then
			ClientState.applyCollectionDelta({ summary = payload.summary })
		end
		for _, id in payload.completed or {} do
			for _, objective in Objectives.list() do
				if objective.id == id then
					ClientState.toast(
						string.format(
							"Objectif « %s » atteint : %s !",
							objective.title,
							Objectives.rewardText(objective)
						),
						"mimic"
					)
				end
			end
		end
		ClientState.MuseumChanged:Fire()
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "InspectPrompt" then
			return
		end
		local slot = prompt:GetAttribute("Slot")
		local folder = prompt.Parent and prompt.Parent.Parent
		local model = folder and folder:FindFirstChild("Exhibit" .. tostring(slot))
		if model and model:IsA("Model") then
			MuseumController.inspect(model)
		end
	end)

	for _, model in CollectionService:GetTagged("MuseumExhibit") do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal("MuseumExhibit"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("MuseumExhibit"):Connect(function(model)
		exhibits[model :: Model] = nil
	end)
	RunService.RenderStepped:Connect(animate)
	RunService.RenderStepped:Connect(function()
		local model = sheetModel
		if model and model.Parent then
			model:PivotTo(CFrame.Angles(0, os.clock() * 0.9, 0))
		end
	end)
end

return MuseumController
