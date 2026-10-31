--!strict
--[[
	ObjectivesTab — onglet « Objectifs » du panneau Collection.

	- Objectifs du collectionneur : progression, récompense garantie, bouton pour équiper
	  le titre ou la couleur de scanner une fois débloqués (validé par le serveur).
	- Couleur de scanner par défaut (Cyan), toujours disponible.
	- Réglages sauvegardés dans le profil : sons, effets réduits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Objectives = require(Shared.Config.Objectives)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Audio = require(Client.Util.Audio)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local ObjectivesTab = {}

local rows: { [string]: any } = {}
local list: ScrollingFrame
local defaultRow: any
local settingsRow: any

local function equip(kind: string, id: string?)
	Audio.play("UiClick", 1.2)
	Remotes.get("EquipCosmetic"):FireServer(kind, id)
end

local function makeRow(order: number, height: number): Frame
	return Theme.panel({
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = Color3.fromRGB(40, 32, 62),
		BackgroundTransparency = 0.1,
		Parent = list,
	})
end

local function header(text: string, order: number)
	Theme.text({
		Text = text,
		LayoutOrder = order,
		Font = Theme.Fonts.Title,
		TextColor3 = C.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -10, 0, 26),
		MaxTextSize = 20,
		Parent = list,
	})
end

local function build(): Frame
	local page = Theme.create("Frame", { Name = "ObjectivesPage", BackgroundTransparency = 1 }) :: Frame
	list = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
	}) :: ScrollingFrame
	Theme.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	header("Objectifs du collectionneur", 0)
	for index, objective in Objectives.list() do
		local row = makeRow(index, 62)
		row.Name = objective.id
		local status = Theme.text({
			Name = "Status",
			Text = "",
			Font = Theme.Fonts.Title,
			Size = UDim2.new(0, 56, 1, -12),
			Position = UDim2.fromOffset(6, 6),
			MaxTextSize = 22,
			Parent = row,
		})
		local title = Theme.text({
			Name = "Title",
			Text = objective.title,
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.62, -70, 0.42, 0),
			Position = UDim2.fromOffset(66, 4),
			MaxTextSize = 18,
			Parent = row,
		})
		local detail = Theme.text({
			Name = "Detail",
			Text = objective.description .. "  ·  " .. Objectives.rewardText(objective),
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(0.62, -70, 0.5, 0),
			Position = UDim2.new(0, 66, 0.45, 0),
			MaxTextSize = 13,
			Parent = row,
		})
		local button = Theme.button({
			Name = "Equip",
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0.34, 0, 1, -16),
			BackgroundColor3 = Color3.fromRGB(60, 110, 90),
			StrokeColor = C.Mint,
			MaxTextSize = 16,
			Parent = row,
		})
		button.Activated:Connect(function()
			local summary = ClientState.summary
			local reward = objective.reward
			if summary == nil or summary.objectives[objective.id] == nil then
				return
			end
			if reward.kind == "pedestal" then
				-- Style de musée : appliqué par le serveur au musée du joueur.
				Audio.play("UiClick", 1.2)
				Remotes.get("SetMuseumStyle"):FireServer("pedestal", reward.id)
				return
			end
			local equipped = summary.cosmetics[reward.kind] == reward.id
			if reward.kind == "title" and equipped then
				equip("title", nil) -- retirer le titre
			elseif not equipped then
				equip(reward.kind, reward.id)
			end
		end)
		rows[objective.id] = { row = row, status = status, title = title, detail = detail, button = button }
	end

	header("Couleur du scanner", 100)
	local row = makeRow(101, 46)
	Theme.text({
		Text = "Cyan (par défaut)",
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, -12, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		MaxTextSize = 16,
		Parent = row,
	})
	local defaultButton = Theme.button({
		Name = "EquipDefault",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.34, 0, 1, -12),
		BackgroundColor3 = Color3.fromRGB(40, 110, 130),
		StrokeColor = C.Cyan,
		MaxTextSize = 16,
		Parent = row,
	})
	defaultButton.Activated:Connect(function()
		equip("scannerColor", Objectives.DefaultScannerColor)
	end)
	defaultRow = { button = defaultButton }

	header("Réglages", 200)
	local settings = makeRow(201, 46)
	local layout = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		Parent = settings,
	}) :: Frame
	Theme.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		Parent = layout,
	})
	local sound = Theme.button({
		Name = "Sound",
		Text = "",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = C.PanelLight,
		MaxTextSize = 16,
		Parent = layout,
	})
	local effects = Theme.button({
		Name = "Effects",
		Text = "",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = C.PanelLight,
		MaxTextSize = 16,
		Parent = layout,
	})
	sound.Activated:Connect(function()
		local summary = ClientState.summary
		if summary then
			Remotes.get("UpdateSettings"):FireServer({ sfx = not summary.settings.sfx })
		end
	end)
	effects.Activated:Connect(function()
		local summary = ClientState.summary
		if summary then
			Remotes.get("UpdateSettings"):FireServer({ reducedEffects = not summary.settings.reducedEffects })
		end
	end)
	settingsRow = { sound = sound, effects = effects }
	return page
end

local function refresh()
	local summary = ClientState.summary
	for _, objective in Objectives.list() do
		local row = rows[objective.id]
		local current, target = Objectives.progress(objective, summary)
		local done = summary ~= nil and summary.objectives[objective.id] ~= nil
		row.status.Text = if done then "✓" else string.format("%d/%d", current, target)
		row.status.TextColor3 = if done then C.Mint else C.Muted
		row.row.BackgroundColor3 = if done then Color3.fromRGB(38, 56, 60) else Color3.fromRGB(40, 32, 62)
		local reward = objective.reward
		local equipped = done
			and (
				if reward.kind == "pedestal"
					then summary.museum ~= nil and summary.museum.pedestal == reward.id
					else summary.cosmetics[reward.kind] == reward.id
			)
		row.button.Visible = done
		row.button.Text = if equipped then (if reward.kind == "title" then "Retirer" else "Équipée") else "Équiper"
		row.button.AutoButtonColor = not (equipped and reward.kind ~= "title")
	end
	local scanner = summary and summary.cosmetics.scannerColor
	defaultRow.button.Text = if scanner == Objectives.DefaultScannerColor then "Équipée" else "Équiper"
	local settings = summary and summary.settings
	settingsRow.sound.Text = if settings and not settings.sfx then "Sons : coupés" else "Sons : activés"
	settingsRow.effects.Text = if settings and settings.reducedEffects
		then "Effets réduits : oui"
		else "Effets réduits : non"
end

function ObjectivesTab.register(CollectionPanel: any)
	CollectionPanel.addTab("Objectives", "Objectifs", build(), refresh)
end

return ObjectivesTab
