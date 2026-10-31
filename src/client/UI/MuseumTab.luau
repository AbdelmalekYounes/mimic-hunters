--!strict
--[[
	MuseumTab — onglet « Musée » du panneau Collection (mode décoration, V0.3).

	- Les 6 vitrines : aperçu 3D de l'exemplaire exposé (ou « Vitrine libre »), boutons
	  Choisir / Retirer / ◀ ▶ (réorganiser). Les emplacements occupés se voient d'un coup d'œil.
	- Sélecteur : exemplaires possédés (les plus rares d'abord, par pages) ; ceux déjà exposés
	  sont marqués et ne peuvent pas être exposés une seconde fois.
	- Personnalisation (jalon 4) : murs, lumière, socles, thème.
	Tout passe par le serveur (SetExhibit, MoveExhibit, SetMuseumStyle) : le client n'affiche
	que le résumé reçu en retour.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local CollectionQuery = require(Shared.Logic.CollectionQuery)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Audio = require(Client.Util.Audio)
local Theme = require(script.Parent.Theme)
local ModelView = require(script.Parent.ModelView)

local C = Theme.Colors
local SLOTS = 6

local MuseumTab = {}

local ui: any = {}
local pickerSlot: number? = nil
local pickerPage = 1

local function slotsOf(): { string }
	local summary = ClientState.summary
	return (summary and summary.museum and summary.museum.slots) or {}
end

local function send(remote: string, ...: any)
	Audio.play("UiClick", 1.1)
	Remotes.get(remote):FireServer(...)
end

-- ─── Vitrines ──────────────────────────────────────────────────────────

local function makeSlotCard(slot: number): any
	local card = Theme.create("Frame", {
		Name = "Slot" .. slot,
		LayoutOrder = slot,
		BackgroundColor3 = Color3.fromRGB(40, 32, 62),
		BorderSizePixel = 0,
		Parent = ui.slotGrid,
	}, { Theme.corner(10) }) :: Frame
	local stroke = Theme.stroke(C.Stroke, 2, 0.4)
	stroke.Parent = card
	local viewport = Theme.create("ViewportFrame", {
		Name = "Preview",
		BackgroundColor3 = Color3.fromRGB(22, 16, 36),
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(200, 190, 220),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, 1),
		Size = UDim2.new(1, -8, 0.5, 0),
		Position = UDim2.fromOffset(4, 4),
		Parent = card,
	}, { Theme.corner(8) }) :: ViewportFrame
	local title = Theme.text({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -8, 0.16, 0),
		Position = UDim2.new(0, 4, 0.5, 4),
		MaxTextSize = 15,
		Parent = card,
	})
	local buttons = Theme.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0.26, 0),
		Position = UDim2.new(0, 4, 0.7, 0),
		Parent = card,
	}) :: Frame
	Theme.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	local function small(name: string, text: string, order: number, scale: number, color: Color3): TextButton
		return Theme.button({
			Name = name,
			Text = text,
			LayoutOrder = order,
			Size = UDim2.new(scale, -3, 1, 0),
			BackgroundColor3 = color,
			Radius = 8,
			MaxTextSize = 14,
			Parent = buttons,
		})
	end
	local left = small("Left", "◀", 1, 0.16, C.PanelLight)
	local choose = small("Choose", "Choisir", 2, 0.42, Color3.fromRGB(60, 110, 90))
	local remove = small("Remove", "Retirer", 3, 0.26, Color3.fromRGB(110, 50, 80))
	local right = small("Right", "▶", 4, 0.16, C.PanelLight)
	choose.Activated:Connect(function()
		MuseumTab.openPicker(slot)
	end)
	remove.Activated:Connect(function()
		send("SetExhibit", slot, nil)
	end)
	left.Activated:Connect(function()
		if slot > 1 then
			send("MoveExhibit", slot, slot - 1)
		end
	end)
	right.Activated:Connect(function()
		if slot < SLOTS then
			send("MoveExhibit", slot, slot + 1)
		end
	end)
	return {
		card = card,
		stroke = stroke,
		viewport = viewport,
		title = title,
		remove = remove,
		left = left,
		right = right,
		shown = nil :: string?,
	}
end

local function refreshSlots()
	local slots = slotsOf()
	local exhibited = 0
	for slot = 1, SLOTS do
		local card = ui.slots[slot]
		local id = slots[slot] or ""
		local specimen = if id ~= "" then ClientState.specimensById[id] else nil
		if specimen then
			exhibited += 1
		end
		if card.shown ~= id then
			card.shown = id
			if specimen then
				ModelView.specimen(card.viewport, specimen, false)
			else
				ModelView.clear(card.viewport)
			end
		end
		local species = specimen and MimicCatalog.get(specimen.speciesId)
		local mutation = specimen and Mutations.get(specimen.mutation)
		local rare = mutation ~= nil and Mutations.isRare(mutation.id)
		card.title.Text = if species
			then string.format(
				"%d · %s%s",
				slot,
				species.name,
				if rare and mutation then " " .. mutation.displayName else ""
			)
			else string.format("%d · Vitrine libre", slot)
		card.title.TextColor3 = if rare and mutation
			then Theme.rgb(mutation.color)
			elseif species then C.Text
			else C.Muted
		card.stroke.Color = if rare and mutation then Theme.rgb(mutation.color) elseif species then C.Mint else C.Stroke
		card.card.BackgroundColor3 = if species then Color3.fromRGB(44, 40, 72) else Color3.fromRGB(34, 28, 52)
		card.remove.Visible = specimen ~= nil
		card.left.Visible = slot > 1
		card.right.Visible = slot < SLOTS
	end
	local plot = ClientState.museumPlot
	ui.header.Text = if plot
		then string.format("Ton musée (parcelle %d)  ·  %d / %d vitrines occupées", plot, exhibited, SLOTS)
		elseif
			ClientState.museumWaiting
		then "Tous les musées sont pris : le tien arrive dès qu'une parcelle se libère."
		else "Ton musée"
end

-- ─── Sélecteur d'exemplaire ────────────────────────────────────────────

function MuseumTab.openPicker(slot: number)
	pickerSlot = slot
	pickerPage = 1
	ui.picker.Visible = true
	MuseumTab.refreshPicker()
end

function MuseumTab.closePicker()
	pickerSlot = nil
	ui.picker.Visible = false
	for _, child in ui.pickerGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function MuseumTab.refreshPicker()
	local slot = pickerSlot
	if slot == nil then
		return
	end
	for _, child in ui.pickerGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local exhibitedAt: { [string]: number } = {}
	for i, id in slotsOf() do
		if id ~= "" then
			exhibitedAt[id] = i
		end
	end
	-- Les plus rares d'abord : mettre en valeur les mutations est le but d'un musée.
	local list = CollectionQuery.sort(ClientState.specimens, "Rarity")
	local size = ui.pickerGrid.AbsoluteSize
	local cellW, cellH = 96, 118
	local cols = math.max(1, math.floor((size.X + 6) / (cellW + 6)))
	local rows = math.max(1, math.floor((size.Y + 6) / (cellH + 6)))
	ui.pickerLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	ui.pickerLayout.FillDirectionMaxCells = cols
	local items, page, pages = CollectionQuery.paginate(list, pickerPage, cols * rows)
	pickerPage = page
	for index, specimen in items do
		local species = MimicCatalog.get(specimen.speciesId)
		local mutation = Mutations.get(specimen.mutation)
		local rare = mutation ~= nil and Mutations.isRare(mutation.id)
		local where = exhibitedAt[specimen.id]
		local card = Theme.create("TextButton", {
			Name = specimen.id,
			Text = "",
			LayoutOrder = index,
			AutoButtonColor = where == nil,
			BackgroundColor3 = if where then Color3.fromRGB(30, 26, 44) else Color3.fromRGB(44, 36, 70),
			BorderSizePixel = 0,
			Parent = ui.pickerGrid,
		}, { Theme.corner(8) }) :: TextButton
		local rarity = Rarities.get(specimen.rarity)
		local stroke = Theme.stroke(
			if rare and mutation then Theme.rgb(mutation.color) elseif rarity then Theme.rgb(rarity.color) else C.Stroke,
			2,
			0.3
		)
		stroke.Parent = card
		local viewport = Theme.create("ViewportFrame", {
			BackgroundColor3 = Color3.fromRGB(22, 16, 36),
			BackgroundTransparency = 0.3,
			Ambient = Color3.fromRGB(200, 190, 220),
			LightColor = Color3.fromRGB(255, 250, 240),
			LightDirection = Vector3.new(-1, -1, 1),
			Size = UDim2.new(1, -6, 0.66, 0),
			Position = UDim2.fromOffset(3, 3),
			Parent = card,
		}, { Theme.corner(6) }) :: ViewportFrame
		ModelView.specimen(viewport, specimen, false)
		Theme.text({
			Text = if species then species.name else specimen.speciesId,
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -6, 0.16, 0),
			Position = UDim2.new(0, 3, 0.68, 0),
			MaxTextSize = 14,
			Parent = card,
		})
		Theme.text({
			Text = if where
				then string.format("Exposé (vitrine %d)", where)
				elseif rare and mutation then mutation.displayName
				else (if rarity then rarity.displayName else ""),
			Font = Theme.Fonts.Bold,
			TextColor3 = if where then C.Muted elseif rare and mutation then Theme.rgb(mutation.color) else C.Mint,
			Size = UDim2.new(1, -6, 0.14, 0),
			Position = UDim2.new(0, 3, 0.84, 0),
			MaxTextSize = 12,
			Parent = card,
		})
		card.Activated:Connect(function()
			if where then
				ClientState.toast(string.format("Ce Mimic est déjà exposé dans la vitrine %d.", where))
				return
			end
			send("SetExhibit", slot, specimen.id)
			MuseumTab.closePicker()
		end)
	end
	ui.pickerTitle.Text = string.format("Choisis un Mimic pour la vitrine %d", slot)
	ui.pickerPageLabel.Text = string.format("Page %d / %d", page, pages)
	ui.pickerPrev.Visible = page > 1
	ui.pickerNext.Visible = page < pages
	ui.pickerEmpty.Visible = #list == 0
end

-- ─── Construction ──────────────────────────────────────────────────────

local function build(): Frame
	local page = Theme.create("Frame", { Name = "MuseumPage", BackgroundTransparency = 1 }) :: Frame
	ui.page = page
	local scroll = Theme.create("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
	}) :: ScrollingFrame
	ui.scroll = scroll
	Theme.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local top = Theme.create("Frame", {
		Name = "Top",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -10, 0, 28),
		Parent = scroll,
	}) :: Frame
	ui.header = Theme.text({
		Name = "Header",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Mint,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.68, 0, 1, 0),
		MaxTextSize = 16,
		Parent = top,
	})
	local go = Theme.button({
		Name = "GoToMuseum",
		Text = "Aller à mon musée",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(120, 70, 150),
		StrokeColor = C.Pink,
		MaxTextSize = 15,
		Parent = top,
	})
	go.Activated:Connect(function()
		send("RequestTravel", "base")
	end)

	ui.slotGrid = Theme.create("Frame", {
		Name = "Slots",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -10, 0, 300),
		Parent = scroll,
	}) :: Frame
	ui.slotLayout = Theme.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.slotGrid,
	}) :: UIGridLayout
	ui.slots = {}
	for slot = 1, SLOTS do
		ui.slots[slot] = makeSlotCard(slot)
	end

	-- Sélecteur : recouvre l'onglet, au-dessus de la liste.
	local picker = Theme.panel({
		Name = "Picker",
		Visible = false,
		ZIndex = 5,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(26, 20, 42),
		BackgroundTransparency = 0.02,
		Parent = page,
	})
	ui.picker = picker
	ui.pickerTitle = Theme.text({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.7, 0, 0, 28),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 20,
		ZIndex = 6,
		Parent = picker,
	})
	local cancel = Theme.button({
		Name = "Cancel",
		Text = "Annuler",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(100, 30),
		BackgroundColor3 = Color3.fromRGB(110, 50, 80),
		StrokeColor = C.Pink,
		MaxTextSize = 15,
		ZIndex = 6,
		Parent = picker,
	})
	cancel.Activated:Connect(MuseumTab.closePicker)
	ui.pickerGrid = Theme.create("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -84),
		ZIndex = 6,
		Parent = picker,
	}) :: Frame
	ui.pickerLayout = Theme.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.pickerGrid,
	}) :: UIGridLayout
	ui.pickerEmpty = Theme.text({
		Name = "Empty",
		Text = "Capture d'abord un Mimic pour pouvoir l'exposer !",
		TextColor3 = C.Muted,
		Visible = false,
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -84),
		MaxTextSize = 18,
		ZIndex = 6,
		Parent = picker,
	})
	ui.pickerPrev = Theme.button({
		Name = "Prev",
		Text = "<",
		Position = UDim2.new(0, 10, 1, -36),
		Size = UDim2.fromOffset(50, 30),
		ZIndex = 6,
		Parent = picker,
	})
	ui.pickerNext = Theme.button({
		Name = "Next",
		Text = ">",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 1, -36),
		Size = UDim2.fromOffset(50, 30),
		ZIndex = 6,
		Parent = picker,
	})
	ui.pickerPageLabel = Theme.text({
		Name = "PageLabel",
		Text = "",
		Font = Theme.Fonts.Bold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.new(0.5, 0, 0, 30),
		MaxTextSize = 15,
		ZIndex = 6,
		Parent = picker,
	})
	ui.pickerPrev.Activated:Connect(function()
		pickerPage -= 1
		MuseumTab.refreshPicker()
	end)
	ui.pickerNext.Activated:Connect(function()
		pickerPage += 1
		MuseumTab.refreshPicker()
	end)

	-- Grille des vitrines : 3 colonnes (2 sur écran très étroit). Hauteur choisie pour que les
	-- 6 vitrines tiennent sans défiler (en-tête de 28 px + espacements), dans la limite du lisible.
	local function layout()
		local width = scroll.AbsoluteSize.X - 16
		if width < 50 then
			return
		end
		local cols = if width < 420 then 2 else 3
		local rowsNeeded = math.ceil(SLOTS / cols)
		local cellW = math.floor((width - 8 * (cols - 1)) / cols)
		local fit = math.floor((scroll.AbsoluteSize.Y - 28 - 16 - 8 * (rowsNeeded - 1)) / rowsNeeded)
		local cellH = math.clamp(math.min(math.floor(cellW * 0.78), fit), 92, 190)
		ui.slotLayout.CellSize = UDim2.fromOffset(cellW, cellH)
		local rows = math.ceil(SLOTS / cols)
		ui.slotGrid.Size = UDim2.new(1, -10, 0, rows * cellH + (rows - 1) * 8)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	return page
end

local function refresh()
	refreshSlots()
	if pickerSlot then
		MuseumTab.refreshPicker()
	end
end

function MuseumTab.register(CollectionPanel: any)
	CollectionPanel.addTab("Museum", "Musée", build(), refresh)
	ClientState.MuseumChanged:Connect(function()
		if ui.page and ui.page.Visible then
			refresh()
		end
	end)
end

function MuseumTab.ui(): any
	return ui
end

return MuseumTab
