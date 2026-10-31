--!strict
--[[
	CollectionController — la collection vue par le joueur :
	compteur permanent (HUD), carte de capture (nouvelle espèce, mutation rare) et ouverture
	du panneau Collection (Codex, Inventaire, Objectifs : UI/CollectionPanel).
	Reçoit les mises à jour du serveur et les range dans ClientState.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Objectives = require(Shared.Config.Objectives)
local Rarities = require(Shared.Config.Rarities)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local SpecimenLook = require(Shared.Logic.SpecimenLook)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local MutationFx = require(Client.Util.MutationFx)
local Theme = require(Client.UI.Theme)
local ModelView = require(Client.UI.ModelView)
local CollectionPanel = require(Client.UI.CollectionPanel)

local CollectionController = {}

local refs: any
local popupModel: Model? = nil
local popupToken = 0

local function refreshStats()
	local summary = ClientState.summary
	local total = if summary then summary.totalCaptures or 0 else 0
	local discovered = if summary then summary.discovered or 0 else 0
	refs.stats.Text = string.format("Captures : %d   ·   Espèces : %d/%d", total, discovered, MimicCatalog.count())
end
local function showDiscovery(payload: any)
	local species = MimicCatalog.get(payload.speciesId)
	if species == nil then
		return
	end
	local rarity = Rarities.get(species.rarity)
	popupToken += 1
	local token = popupToken
	-- L'exemplaire réellement obtenu (couleurs et taille issues de sa graine, mutation).
	local specimen = payload.specimen
	local mutation = if specimen then Mutations.get(specimen.mutation) else nil
	local rare = mutation ~= nil and Mutations.isRare(mutation.id)
	if rare and mutation then
		refs.popupHeadline.Text = string.format("%s !", string.upper(mutation.displayName))
		refs.popupHeadline.TextColor3 = Theme.rgb(mutation.color)
	elseif payload.isNew then
		refs.popupHeadline.Text = "NOUVELLE ESPÈCE !"
		refs.popupHeadline.TextColor3 = Theme.Colors.Yellow
	else
		refs.popupHeadline.Text = "CAPTURÉ !"
		refs.popupHeadline.TextColor3 = Theme.Colors.Mint
	end
	refs.popupName.Text = species.name
	refs.popupRarity.Text = (if rarity then rarity.displayName else "")
		.. (if rare and mutation then "  ·  " .. mutation.displayName else "")
	refs.popupRarity.TextColor3 = if rare and mutation
		then Theme.rgb(mutation.color)
		elseif rarity then Theme.rgb(rarity.color)
		else Theme.Colors.Text
	if rare and mutation then
		refs.popupCount.Text = string.format(
			"%sChance : %s par capture",
			if payload.isNew then "Nouvelle espèce  ·  " else "",
			Mutations.chanceText(mutation.id)
		)
	else
		refs.popupCount.Text = string.format(
			"Possédés x%d   ·   Espèces %d/%d",
			payload.count or 1,
			payload.discovered or 1,
			MimicCatalog.count()
		)
	end
	local look = if specimen then SpecimenLook.compute(species, specimen.seed, specimen.mutation) else nil
	local model = MimicModelBuilder.build(species.id, nil, look)
	ModelView.frame(refs.popupViewport, model, species.kind)
	MutationFx.attach(model, look)
	popupModel = model
	refs.popup.Visible = true
	-- Rare : apparition plus ample et fond aux couleurs de la mutation. Nouvelle espèce : rebond doré.
	refs.popupScale.Scale = if rare then 0.3 else 0.5
	Animate.tween(
		refs.popupScale,
		if rare then 0.5 else 0.35,
		{ Scale = 1 },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	local baseColor = Color3.fromRGB(36, 26, 60)
	if rare and mutation then
		refs.popup.BackgroundColor3 = Theme.rgb(mutation.color):Lerp(baseColor, 0.35)
		Animate.tween(refs.popup, 1.2, { BackgroundColor3 = baseColor })
	elseif payload.isNew then
		refs.popup.BackgroundColor3 = Color3.fromRGB(90, 70, 30)
		Animate.tween(refs.popup, 0.9, { BackgroundColor3 = baseColor })
	else
		refs.popup.BackgroundColor3 = baseColor
	end
	Audio.play("Capture", if rare then 1.5 elseif payload.isNew then 1.25 else 1)
	if rare then
		task.delay(0.25, function()
			Audio.play("Reveal", 1.6)
		end)
	end
	task.delay(if rare then 4 elseif payload.isNew then 3.2 else 2.2, function()
		if token ~= popupToken then
			return
		end
		Animate.tween(refs.popupScale, 0.2, { Scale = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.2)
		if token == popupToken then
			refs.popup.Visible = false
			popupModel = nil
			-- Le modèle restait dans l'aperçu masqué et ses effets tournaient jusqu'à la capture
			-- suivante (audit V0.3.1, C5).
			ModelView.clear(refs.popupViewport)
		end
	end)
end

function CollectionController.start(hudRefs: any)
	refs = hudRefs
	CollectionPanel.build(refs.gui, refs.touch)
	refreshStats()

	-- Pastille « ! » sur le bouton CODEX : quelque chose de nouveau à voir dans la collection.
	local badge = Theme.text({
		Name = "NewBadge",
		Text = "!",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		ZIndex = 3,
		MaxTextSize = 18,
		Parent = refs.codexButton,
	})
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Theme.Colors.Pink
	Theme.corner(12).Parent = badge
	local buttonScale = Theme.create("UIScale", { Scale = 1, Parent = refs.codexButton }) :: UIScale
	local function flagNew()
		badge.Visible = true
		buttonScale.Scale = 1.18
		Animate.tween(buttonScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	local function toggle()
		CollectionPanel.toggle()
		if CollectionPanel.isOpen() then
			badge.Visible = false
		end
	end

	refs.codexButton.Activated:Connect(toggle)
	ContextActionService:BindAction("MH_Codex", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonSelect)
	Remotes.get("CaptureResolved").OnClientEvent:Connect(function(payload)
		if payload.success and (payload.isNew or payload.isNewMutation or #(payload.completed or {}) > 0) then
			task.delay(1.5, flagNew)
		end
	end)

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
		-- Réglages du profil appliqués au client.
		local settings = ClientState.summary and ClientState.summary.settings
		if settings then
			Audio.muted = settings.sfx == false
			MutationFx.enabled = settings.reducedEffects ~= true
		end
	end)
	Remotes.get("CaptureResolved").OnClientEvent:Connect(function(payload)
		if payload.success then
			showDiscovery(payload)
			-- Objectifs atteints par cette capture : récompense annoncée tout de suite.
			for index, id in payload.completed or {} do
				for _, objective in Objectives.list() do
					if objective.id == id then
						task.delay(1 + index * 0.6, function()
							Audio.play("Reveal", 1.8)
							ClientState.toast(
								string.format(
									"Objectif « %s » atteint : %s débloqué !",
									objective.title,
									Objectives.rewardText(objective)
								),
								"mimic"
							)
						end)
					end
				end
			end
		end
	end)

	-- Rotation lente du Mimic dans la carte de capture.
	RunService.RenderStepped:Connect(function()
		local model = popupModel
		if model and model.Parent then
			model:PivotTo(CFrame.Angles(0, os.clock() * 1.4, 0))
		end
	end)
end

return CollectionController
