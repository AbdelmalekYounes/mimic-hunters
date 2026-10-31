--!strict
--[[
	CollectionPanel — panneau Collection : Codex, Inventaire (et Objectifs, jalon 5).

	- Codex : les 6 espèces, découvertes ou non (silhouette + indice), exemplaires possédés,
	  mutations déjà trouvées, probabilités des mutations.
	- Inventaire : chaque exemplaire individuel, par pages (pas de défilement de centaines
	  d'aperçus 3D : seules les cartes de la page sont construites), filtres rareté / espèce /
	  mutation / favoris, tri récent / rareté, fiche détaillée avec aperçu animé et favori.
	- Compteur de complétion permanent dans l'en-tête.

	Disposition : rectangle donné par HudLayout (presque plein écran sur téléphone). La fiche
	est une colonne à droite quand la place le permet, sinon elle recouvre la grille (bouton
	« Retour »). Le panneau ne décide de rien : favoris et cosmétiques passent par le serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local CollectionQuery = require(Shared.Logic.CollectionQuery)
local HudLayout = require(Shared.Logic.HudLayout)
local SpecimenLook = require(Shared.Logic.SpecimenLook)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local Theme = require(script.Parent.Theme)
local ModelView = require(script.Parent.ModelView)

local C = Theme.Colors

local CollectionPanel = {}

-- Onglets : les autres modules peuvent en ajouter (Objectifs, jalon 5).
type Tab = { id: string, label: string, page: GuiObject, refresh: () -> () }

local ui: any = {}
local tabs: { Tab } = {}
local state = {
	tab = "Codex",
	filter = {} :: CollectionQuery.Filter,
	sort = "Recent",
	page = 1,
	selectedId = nil :: string?,
	detailOpen = false, -- disposition étroite : fiche affichée par-dessus la grille
	dirty = true,
	compact = false,
}
local detailModel: Model? = nil

-- ─── Petits utilitaires ────────────────────────────────────────────────

local function rarityColor(id: string): Color3
	local rarity = Rarities.get(id)
	return if rarity then Theme.rgb(rarity.color) else C.Muted
end

local function mutationColor(id: string): Color3
	local mutation = Mutations.get(id)
	return if mutation then Theme.rgb(mutation.color) else C.Muted
end

local function formatDate(timestamp: number): string
	local ok, t = pcall(os.date, "*t", timestamp)
	if not ok or type(t) ~= "table" then
		return "?"
	end
	local d = t :: any
	return string.format("%02d/%02d/%04d à %02dh%02d", d.day, d.month, d.year, d.hour, d.min)
end

local function clearChildren(parent: Instance, keep: { [string]: boolean }?)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and not (keep and keep[child.Name]) then
			child:Destroy()
		end
	end
end

local function label(props: any): TextLabel
	return Theme.text(props)
end

-- ─── Construction ──────────────────────────────────────────────────────

local function makeTabButton(tab: Tab, index: number)
	local button = Theme.button({
		Name = "Tab_" .. tab.id,
		Text = tab.label,
		LayoutOrder = index,
		Size = UDim2.new(0, 130, 1, 0),
		BackgroundColor3 = C.PanelLight,
		StrokeColor = C.Stroke,
		MaxTextSize = 18,
		Parent = ui.tabBar,
	})
	button.Activated:Connect(function()
		CollectionPanel.showTab(tab.id)
	end)
	return button
end

function CollectionPanel.addTab(id: string, text: string, page: GuiObject, refresh: () -> ())
	local tab: Tab = { id = id, label = text, page = page, refresh = refresh }
	table.insert(tabs, tab)
	page.Visible = false
	page.Parent = ui.content
	makeTabButton(tab, #tabs)
	return tab
end

local function buildHeader(panel: Frame)
	ui.title = label({
		Name = "Title",
		Text = "COLLECTION",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = panel,
	})
	ui.completion = label({
		Name = "Completion",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Mint,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 16,
		Parent = panel,
	})
	ui.close = Theme.button({
		Name = "Close",
		Text = "X",
		BackgroundColor3 = Color3.fromRGB(110, 50, 80),
		StrokeColor = C.Pink,
		Parent = panel,
	})
	ui.tabBar = Theme.create("Frame", { Name = "Tabs", BackgroundTransparency = 1, Parent = panel }) :: Frame
	Theme.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.tabBar,
	})
	ui.content = Theme.create("Frame", { Name = "Content", BackgroundTransparency = 1, Parent = panel }) :: Frame
end

-- ─── Codex ─────────────────────────────────────────────────────────────

local function buildCodexPage(): Frame
	local page = Theme.create("Frame", { Name = "CodexPage", BackgroundTransparency = 1 }) :: Frame
	ui.codexGrid = Theme.create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
	}) :: ScrollingFrame
	ui.codexLayout = Theme.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = ui.codexGrid,
	}) :: UIGridLayout
	local chances = {}
	for _, mutation in Mutations.list() do
		if Mutations.isRare(mutation.id) then
			table.insert(chances, string.format("%s %s", mutation.displayName, Mutations.chanceText(mutation.id)))
		end
	end
	ui.codexFooter = label({
		Name = "Chances",
		Text = "Mutations par capture : " .. table.concat(chances, "  ·  ") .. "  (purement cosmétiques)",
		TextColor3 = C.Muted,
		MaxTextSize = 14,
		Parent = page,
	})
	ui.codexCards = {}
	for index, species in MimicCatalog.list() do
		local card = Theme.create("TextButton", {
			Name = species.id,
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = index,
			BackgroundColor3 = Color3.fromRGB(40, 32, 62),
			BorderSizePixel = 0,
			Parent = ui.codexGrid,
		}, { Theme.corner(12) }) :: TextButton
		local stroke = Theme.stroke(rarityColor(species.rarity), 2, 0.35)
		stroke.Parent = card
		local viewport = Theme.create("ViewportFrame", {
			Name = "Preview",
			BackgroundColor3 = Color3.fromRGB(22, 16, 36),
			BackgroundTransparency = 0.2,
			Ambient = Color3.fromRGB(200, 190, 220),
			LightColor = Color3.fromRGB(255, 250, 240),
			LightDirection = Vector3.new(-1, -1, 1),
			Size = UDim2.new(1, -12, 0.5, 0),
			Position = UDim2.fromOffset(6, 6),
			Parent = card,
		}, { Theme.corner(10) }) :: ViewportFrame
		local name = label({
			Name = "Name",
			Text = "???",
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -12, 0.12, 0),
			Position = UDim2.new(0, 6, 0.5, 10),
			MaxTextSize = 20,
			Parent = card,
		})
		local rarity = Rarities.get(species.rarity)
		local rarityLabel = label({
			Name = "Rarity",
			Text = if rarity then rarity.displayName else "",
			Font = Theme.Fonts.Bold,
			TextColor3 = rarityColor(species.rarity),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.6, -6, 0.09, 0),
			Position = UDim2.new(0, 6, 0.62, 10),
			MaxTextSize = 14,
			Parent = card,
		})
		local count = label({
			Name = "Count",
			Text = "",
			Font = Theme.Fonts.Bold,
			TextColor3 = C.Mint,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.new(0.4, -6, 0.09, 0),
			Position = UDim2.new(1, -6, 0.62, 10),
			MaxTextSize = 14,
			Parent = card,
		})
		-- Une pastille par mutation : allumée quand cette apparence a été capturée.
		local dots = Theme.create("Frame", {
			Name = "Mutations",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0.08, 0),
			Position = UDim2.new(0, 6, 0.72, 10),
			Parent = card,
		}) :: Frame
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Parent = dots,
		})
		local dotFrames = {}
		for _, mutation in Mutations.list() do
			local dot = Theme.create("Frame", {
				Name = mutation.id,
				Size = UDim2.new(0, 0, 1, 0),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				BackgroundColor3 = Color3.fromRGB(60, 50, 80),
				BorderSizePixel = 0,
				Parent = dots,
			}, { Theme.corner(99) }) :: Frame
			dot.Size = UDim2.fromScale(1, 1)
			dotFrames[mutation.id] = dot
		end
		local hint = label({
			Name = "Hint",
			Text = "",
			TextColor3 = C.Muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -12, 0.14, 0),
			Position = UDim2.new(0, 6, 0.82, 8),
			MaxTextSize = 12,
			Parent = card,
		})
		card.Activated:Connect(function()
			if ClientState.summary and ClientState.summary.codex and ClientState.summary.codex[species.id] then
				-- Espèce découverte : ses exemplaires dans l'inventaire.
				state.filter = { species = species.id }
				state.page = 1
				state.selectedId = nil
				CollectionPanel.showTab("Inventory")
			end
		end)
		ui.codexCards[species.id] = {
			card = card,
			viewport = viewport,
			name = name,
			rarity = rarityLabel,
			count = count,
			dots = dotFrames,
			hint = hint,
			discovered = nil :: boolean?,
		}
	end
	return page
end

local function refreshCodex()
	local summary = ClientState.summary
	for _, species in MimicCatalog.list() do
		local card = ui.codexCards[species.id]
		local entry = summary and summary.codex and summary.codex[species.id]
		local discovered = entry ~= nil
		if card.discovered ~= discovered then
			card.discovered = discovered
			ModelView.species(card.viewport, species.id, discovered)
		end
		card.name.Text = if discovered then species.name else "???"
		local owned = ClientState.ownedCount(species.id)
		card.count.Text = if discovered then string.format("x%d", owned) else ""
		local found = {}
		for _, m in (entry and entry.mutations) or {} do
			found[m] = true
		end
		for id, dot in card.dots do
			dot.BackgroundColor3 = if found[id] then mutationColor(id) else Color3.fromRGB(60, 50, 80)
		end
		card.hint.Text = if discovered
			then species.description
			else string.format("Se cache en %s.", MimicCatalog.kindName(species.kind))
	end
end

-- ─── Inventaire ────────────────────────────────────────────────────────

local function filterButton(name: string, order: number): TextButton
	return Theme.button({
		Name = name,
		Text = "",
		LayoutOrder = order,
		Size = UDim2.new(0, 120, 1, 0),
		BackgroundColor3 = Color3.fromRGB(48, 38, 74),
		StrokeColor = C.Stroke,
		Radius = 10,
		MaxTextSize = 15,
		Parent = ui.filters,
	})
end

local rarityOptions, speciesOptions, mutationOptions = {}, {}, {}
for _, r in Rarities.list() do
	table.insert(rarityOptions, r.id)
end
for _, s in MimicCatalog.list() do
	table.insert(speciesOptions, s.id)
end
for _, m in Mutations.list() do
	table.insert(mutationOptions, m.id)
end

local function buildInventoryPage(): Frame
	local page = Theme.create("Frame", { Name = "InventoryPage", BackgroundTransparency = 1 }) :: Frame
	ui.filters = Theme.create("Frame", { Name = "Filters", BackgroundTransparency = 1, Parent = page }) :: Frame
	Theme.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.filters,
	})
	ui.filterRarity = filterButton("Rarity", 1)
	ui.filterSpecies = filterButton("Species", 2)
	ui.filterMutation = filterButton("Mutation", 3)
	ui.filterFavorite = filterButton("Favorites", 4)
	ui.sortButton = filterButton("Sort", 5)

	ui.filterRarity.Activated:Connect(function()
		state.filter.rarity = CollectionQuery.cycle(rarityOptions, state.filter.rarity)
		state.page, state.selectedId = 1, nil
		CollectionPanel.refresh()
	end)
	ui.filterSpecies.Activated:Connect(function()
		state.filter.species = CollectionQuery.cycle(speciesOptions, state.filter.species)
		state.page, state.selectedId = 1, nil
		CollectionPanel.refresh()
	end)
	ui.filterMutation.Activated:Connect(function()
		state.filter.mutation = CollectionQuery.cycle(mutationOptions, state.filter.mutation)
		state.page, state.selectedId = 1, nil
		CollectionPanel.refresh()
	end)
	ui.filterFavorite.Activated:Connect(function()
		state.filter.favoritesOnly = not state.filter.favoritesOnly
		state.page, state.selectedId = 1, nil
		CollectionPanel.refresh()
	end)
	ui.sortButton.Activated:Connect(function()
		state.sort = if state.sort == "Recent" then "Rarity" else "Recent"
		state.page = 1
		CollectionPanel.refresh()
	end)

	ui.grid = Theme.create("Frame", { Name = "Grid", BackgroundTransparency = 1, Parent = page }) :: Frame
	ui.gridLayout = Theme.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.grid,
	}) :: UIGridLayout
	ui.empty = label({
		Name = "Empty",
		Text = "",
		TextColor3 = C.Muted,
		TextWrapped = true,
		Visible = false,
		MaxTextSize = 18,
		Parent = page,
	})

	ui.pager = Theme.create("Frame", { Name = "Pager", BackgroundTransparency = 1, Parent = page }) :: Frame
	ui.prev = Theme.button({ Name = "Prev", Text = "<", Size = UDim2.new(0, 56, 1, 0), Parent = ui.pager })
	ui.next = Theme.button({
		Name = "Next",
		Text = ">",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 56, 1, 0),
		Parent = ui.pager,
	})
	ui.pageLabel = label({
		Name = "PageLabel",
		Text = "",
		Font = Theme.Fonts.Bold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, -130, 1, 0),
		MaxTextSize = 16,
		Parent = ui.pager,
	})
	ui.prev.Activated:Connect(function()
		state.page -= 1
		state.selectedId = nil
		CollectionPanel.refresh()
	end)
	ui.next.Activated:Connect(function()
		state.page += 1
		state.selectedId = nil
		CollectionPanel.refresh()
	end)

	-- Fiche détaillée.
	ui.detail = Theme.panel({
		Name = "Detail",
		BackgroundColor3 = Color3.fromRGB(34, 26, 54),
		BackgroundTransparency = 0.05,
		Parent = page,
	})
	ui.detailViewport = Theme.create("ViewportFrame", {
		Name = "Preview",
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(200, 190, 220),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, 1),
		Position = UDim2.fromOffset(8, 8),
		Parent = ui.detail,
	}, { Theme.corner(10) }) :: ViewportFrame
	ui.detailInfo = Theme.create("Frame", { Name = "Info", BackgroundTransparency = 1, Parent = ui.detail }) :: Frame
	Theme.create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.detailInfo,
	})
	local function infoLine(name: string, order: number, font: Enum.Font?, size: number?, color: Color3?): TextLabel
		return label({
			Name = name,
			Text = "",
			LayoutOrder = order,
			Font = font or Theme.Fonts.Body,
			TextColor3 = color or C.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, size or 18),
			MaxTextSize = size or 16,
			Parent = ui.detailInfo,
		})
	end
	ui.detailName = infoLine("Name", 1, Theme.Fonts.Title, 26)
	ui.detailRarity = infoLine("Rarity", 2, Theme.Fonts.Bold, 18)
	ui.detailMutation = infoLine("Mutation", 3, Theme.Fonts.Bold, 18)
	ui.detailDate = infoLine("Date", 4, nil, 16, C.Muted)
	ui.detailId = infoLine("Id", 5, nil, 14, C.Muted)
	ui.detailSize = infoLine("Size", 6, nil, 14, C.Muted)
	ui.favorite = Theme.button({
		Name = "Favorite",
		Text = "",
		BackgroundColor3 = Color3.fromRGB(110, 90, 30),
		StrokeColor = C.Yellow,
		MaxTextSize = 18,
		Parent = ui.detail,
	})
	ui.back = Theme.button({
		Name = "Back",
		Text = "Retour",
		BackgroundColor3 = C.PanelLight,
		Visible = false,
		MaxTextSize = 16,
		Parent = ui.detail,
	})
	ui.favorite.Activated:Connect(function()
		local specimen = state.selectedId and ClientState.specimensById[state.selectedId]
		if specimen then
			Audio.play("UiClick", 1.3)
			Remotes.get("SetFavorite"):FireServer(specimen.id, not specimen.favorite)
		end
	end)
	ui.back.Activated:Connect(function()
		state.detailOpen = false
		CollectionPanel.refresh()
	end)
	return page
end

local function filterText(): (string, string, string, string, string)
	local f = state.filter
	local rarity = f.rarity and Rarities.get(f.rarity)
	local species = f.species and MimicCatalog.get(f.species)
	local mutation = f.mutation and Mutations.get(f.mutation)
	return (if rarity then rarity.displayName else "Toutes raretés"),
		(if species then species.name else "Toutes espèces"),
		(if mutation then mutation.displayName else "Toutes mutations"),
		(if f.favoritesOnly then "★ Favoris" else "☆ Tous"),
		(if state.sort == "Rarity" then "Tri : rareté" else "Tri : récents")
end

local function makeCard(specimen: any, order: number): TextButton
	local species = MimicCatalog.get(specimen.speciesId)
	local selected = specimen.id == state.selectedId
	local card = Theme.create("TextButton", {
		Name = specimen.id,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = order,
		BackgroundColor3 = if selected then Color3.fromRGB(58, 46, 92) else Color3.fromRGB(40, 32, 62),
		BorderSizePixel = 0,
		Parent = ui.grid,
	}, { Theme.corner(10) }) :: TextButton
	local mutation = Mutations.get(specimen.mutation)
	local rare = mutation ~= nil and Mutations.isRare(mutation.id)
	local stroke = Theme.stroke(
		if selected then C.Mint elseif rare then mutationColor(specimen.mutation) else rarityColor(specimen.rarity),
		if selected or rare then 3 else 2,
		if selected then 0 else 0.3
	)
	stroke.Parent = card
	local viewport = Theme.create("ViewportFrame", {
		Name = "Preview",
		BackgroundColor3 = Color3.fromRGB(22, 16, 36),
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(200, 190, 220),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, 1),
		Size = UDim2.new(1, -8, 0.68, 0),
		Position = UDim2.fromOffset(4, 4),
		Parent = card,
	}, { Theme.corner(8) }) :: ViewportFrame
	ModelView.specimen(viewport, specimen, false)
	label({
		Name = "Name",
		Text = if species then species.name else specimen.speciesId,
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -8, 0.15, 0),
		Position = UDim2.new(0, 4, 0.7, 2),
		MaxTextSize = 16,
		Parent = card,
	})
	label({
		Name = "Mutation",
		Text = if rare and mutation
			then mutation.displayName
			else (Rarities.get(specimen.rarity) or {}).displayName or "",
		Font = Theme.Fonts.Bold,
		TextColor3 = if rare then mutationColor(specimen.mutation) else rarityColor(specimen.rarity),
		Size = UDim2.new(1, -8, 0.12, 0),
		Position = UDim2.new(0, 4, 0.85, 2),
		MaxTextSize = 12,
		Parent = card,
	})
	if specimen.favorite then
		label({
			Name = "Star",
			Text = "★",
			Font = Theme.Fonts.Bold,
			TextColor3 = C.Yellow,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.fromOffset(22, 22),
			MaxTextSize = 20,
			ZIndex = 3,
			Parent = card,
		})
	end
	card.Activated:Connect(function()
		Audio.play("UiClick")
		state.selectedId = specimen.id
		state.detailOpen = true
		CollectionPanel.refresh()
	end)
	return card
end

local function refreshDetail(specimen: any?)
	if specimen == nil then
		ui.detail.Visible = false
		detailModel = nil
		ModelView.clear(ui.detailViewport)
		return
	end
	local species = MimicCatalog.get(specimen.speciesId)
	local rarity = Rarities.get(specimen.rarity)
	local mutation = Mutations.get(specimen.mutation)
	if ui.detailViewport:GetAttribute("SpecimenId") ~= specimen.id then
		ui.detailViewport:SetAttribute("SpecimenId", specimen.id)
		detailModel = ModelView.specimen(ui.detailViewport, specimen, true)
	end
	ui.detailName.Text = if species then species.name else specimen.speciesId
	ui.detailRarity.Text = "Rareté : " .. (if rarity then rarity.displayName else specimen.rarity)
	ui.detailRarity.TextColor3 = rarityColor(specimen.rarity)
	if mutation and Mutations.isRare(mutation.id) then
		ui.detailMutation.Text =
			string.format("Mutation : %s (%s par capture)", mutation.displayName, Mutations.chanceText(mutation.id))
	else
		ui.detailMutation.Text = "Apparence : Standard"
	end
	ui.detailMutation.TextColor3 = mutationColor(specimen.mutation)
	ui.detailDate.Text = "Capturé le " .. formatDate(specimen.acquiredAt)
	ui.detailId.Text = "N° " .. specimen.id
	local look = if species then SpecimenLook.compute(species, specimen.seed, specimen.mutation) else nil
	ui.detailSize.Text = if look then string.format("Taille : %d %%", math.floor(look.scale * 100 + 0.5)) else ""
	ui.favorite.Text = if specimen.favorite then "★ Favori" else "☆ Ajouter aux favoris"
end

local function refreshInventory()
	local rarityText, speciesText, mutationText, favoriteText, sortText = filterText()
	ui.filterRarity.Text = rarityText
	ui.filterSpecies.Text = speciesText
	ui.filterMutation.Text = mutationText
	ui.filterFavorite.Text = favoriteText
	ui.sortButton.Text = sortText

	local list = CollectionQuery.sort(CollectionQuery.filter(ClientState.specimens, state.filter), state.sort)
	local items, page, pages = CollectionQuery.paginate(list, state.page, ui.perPage or 8)
	state.page = page
	clearChildren(ui.grid)
	for index, specimen in items do
		makeCard(specimen, index)
	end
	ui.pageLabel.Text =
		string.format("Page %d / %d   ·   %d Mimic%s", page, pages, #list, if #list > 1 then "s" else "")
	ui.prev.Visible = page > 1
	ui.next.Visible = page < pages
	ui.empty.Visible = #items == 0
	ui.empty.Text = if #ClientState.specimens == 0
		then "Aucun Mimic pour l'instant : scanne, examine, capture !"
		else "Aucun Mimic ne correspond à ces filtres."

	-- Sélection : l'exemplaire choisi s'il est toujours visible, sinon le premier de la page.
	local selected = state.selectedId and ClientState.specimensById[state.selectedId]
	local visible = false
	for _, s in items do
		if selected and s.id == selected.id then
			visible = true
		end
	end
	if not visible then
		selected = if ui.sideDetail then items[1] else nil
		state.selectedId = if selected then selected.id else nil
	end
	local showDetail = selected ~= nil and (ui.sideDetail or state.detailOpen)
	refreshDetail(if showDetail then selected else nil)
	ui.detail.Visible = showDetail
	ui.back.Visible = showDetail and not ui.sideDetail
	ui.grid.Visible = ui.sideDetail or not showDetail
	ui.pager.Visible = ui.grid.Visible
end

-- ─── Disposition interne (recalculée à chaque changement de taille) ─────

local function layout()
	local panel = ui.panel :: Frame
	local size = panel.AbsoluteSize
	if size.X < 10 then
		return
	end
	local compact = state.compact
	local pad = if compact then 6 else 10
	local headerH = if compact then 30 else 40
	local tabsH = if compact then 28 else 34
	local w = size.X - 2 * pad
	ui.title.Position = UDim2.fromOffset(pad, pad)
	ui.title.Size = UDim2.fromOffset(math.floor(w * 0.35), headerH)
	ui.completion.Position = UDim2.fromOffset(pad + math.floor(w * 0.35), pad)
	ui.completion.Size = UDim2.fromOffset(math.floor(w * 0.65) - headerH - 8, headerH)
	ui.close.Position = UDim2.fromOffset(size.X - pad - headerH, pad)
	ui.close.Size = UDim2.fromOffset(headerH, headerH)
	ui.tabBar.Position = UDim2.fromOffset(pad, pad + headerH + 6)
	ui.tabBar.Size = UDim2.fromOffset(w, tabsH)
	for _, child in ui.tabBar:GetChildren() do
		if child:IsA("TextButton") then
			child.Size = UDim2.new(0, math.min(150, math.floor((w - 6 * (#tabs - 1)) / #tabs)), 1, 0)
		end
	end
	local contentY = pad + headerH + 6 + tabsH + 8
	local contentH = size.Y - contentY - pad
	ui.content.Position = UDim2.fromOffset(pad, contentY)
	ui.content.Size = UDim2.fromOffset(w, contentH)

	-- Codex : 2 à 6 colonnes selon la largeur.
	local footerH = if compact then 18 else 22
	ui.codexGrid.Size = UDim2.new(1, 0, 0, contentH - footerH - 4)
	ui.codexFooter.Position = UDim2.fromOffset(0, contentH - footerH)
	ui.codexFooter.Size = UDim2.new(1, 0, 0, footerH)
	local cols = math.clamp(math.floor((w + 8) / (if compact then 150 else 170)), 2, 6)
	local cellW = math.floor((w - 8 * (cols - 1) - 8) / cols)
	ui.codexLayout.CellSize = UDim2.fromOffset(cellW, if compact then 170 else 210)

	-- Inventaire.
	local filtersH = if compact then 28 else 32
	local pagerH = if compact then 26 else 30
	ui.filters.Size = UDim2.new(1, 0, 0, filtersH)
	for _, child in ui.filters:GetChildren() do
		if child:IsA("TextButton") then
			child.Size = UDim2.new(0, math.floor((w - 6 * 4) / 5), 1, 0)
		end
	end
	local bodyY = filtersH + 6
	local bodyH = contentH - bodyY
	ui.sideDetail = w >= 600
	local detailW = if ui.sideDetail then math.clamp(math.floor(w * 0.34), 220, 320) else w
	local gridW = if ui.sideDetail then w - detailW - 8 else w
	local gridH = bodyH - pagerH - 6
	ui.grid.Position = UDim2.fromOffset(0, bodyY)
	ui.grid.Size = UDim2.fromOffset(gridW, gridH)
	ui.empty.Position = ui.grid.Position
	ui.empty.Size = ui.grid.Size
	ui.pager.Position = UDim2.fromOffset(0, bodyY + gridH + 6)
	ui.pager.Size = UDim2.fromOffset(gridW, pagerH)
	local cellW2, cellH2 = if compact then 92 else 118, if compact then 112 else 142
	local gcols = math.max(1, math.floor((gridW + 8) / (cellW2 + 8)))
	local grows = math.max(1, math.floor((gridH + 8) / (cellH2 + 8)))
	ui.gridLayout.CellSize = UDim2.fromOffset(cellW2, cellH2)
	ui.gridLayout.FillDirectionMaxCells = gcols
	ui.perPage = gcols * grows

	ui.detail.Position = UDim2.fromOffset(if ui.sideDetail then gridW + 8 else 0, bodyY)
	ui.detail.Size = UDim2.fromOffset(detailW, bodyH)
	local buttonH = if compact then 30 else 36
	local previewH = math.floor(if ui.sideDetail then bodyH * 0.45 else bodyH - buttonH - 16)
	local previewW = if ui.sideDetail then detailW - 16 else math.floor(detailW * 0.45)
	ui.detailViewport.Size = UDim2.fromOffset(previewW, previewH)
	if ui.sideDetail then
		ui.detailInfo.Position = UDim2.fromOffset(10, previewH + 14)
		ui.detailInfo.Size = UDim2.fromOffset(detailW - 20, bodyH - previewH - buttonH - 28)
		ui.favorite.Position = UDim2.fromOffset(8, bodyH - buttonH - 8)
		ui.favorite.Size = UDim2.fromOffset(detailW - 16, buttonH)
	else
		ui.detailInfo.Position = UDim2.fromOffset(previewW + 18, 8)
		ui.detailInfo.Size = UDim2.fromOffset(detailW - previewW - 26, bodyH - buttonH - 24)
		ui.favorite.Position = UDim2.fromOffset(previewW + 18, bodyH - buttonH - 8)
		ui.favorite.Size = UDim2.fromOffset(math.floor((detailW - previewW - 34) * 0.62), buttonH)
		ui.back.Position = UDim2.new(1, -math.floor((detailW - previewW - 34) * 0.36) - 8, 0, bodyH - buttonH - 8)
		ui.back.Size = UDim2.fromOffset(math.floor((detailW - previewW - 34) * 0.36), buttonH)
	end
	state.dirty = true
	if panel.Visible then
		CollectionPanel.refresh()
	end
end

-- ─── API ───────────────────────────────────────────────────────────────

local function refreshCompletion()
	local summary = ClientState.summary
	local completion = CollectionQuery.completion(summary, MimicCatalog)
	local owned = if summary then summary.owned or 0 else 0
	local narrow = ui.panel.AbsoluteSize.X < 700
	ui.completion.Text = if narrow
		then string.format(
			"%d/%d espèces · %d/%d apparences · %d",
			completion.discovered,
			completion.total,
			completion.variants,
			completion.variantsTotal,
			owned
		)
		else string.format(
			"Espèces %d/%d (%d %%)   ·   Apparences %d/%d   ·   %d Mimic%s",
			completion.discovered,
			completion.total,
			completion.percent,
			completion.variants,
			completion.variantsTotal,
			owned,
			if owned > 1 then "s" else ""
		)
end

function CollectionPanel.refresh()
	if ui.panel == nil then
		return
	end
	refreshCompletion()
	for _, tab in tabs do
		if tab.id == state.tab then
			tab.refresh()
		end
	end
	state.dirty = false
end

function CollectionPanel.showTab(id: string)
	state.tab = id
	for _, tab in tabs do
		tab.page.Visible = tab.id == id
		local button = ui.tabBar:FindFirstChild("Tab_" .. tab.id) :: TextButton?
		if button then
			button.BackgroundColor3 = if tab.id == id then Color3.fromRGB(110, 70, 150) else C.PanelLight
		end
	end
	state.detailOpen = false
	CollectionPanel.refresh()
end

function CollectionPanel.isOpen(): boolean
	return ui.panel ~= nil and ui.panel.Visible
end

function CollectionPanel.setOpen(open: boolean)
	local panel = ui.panel :: Frame
	if open == panel.Visible then
		return
	end
	Audio.play("UiClick")
	-- La liste des joueurs de Roblox recouvrirait l'en-tête du panneau : masquée pendant la lecture.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not open)
	end)
	if open then
		panel.Visible = true
		-- Ouverture rapide (0,15 s) : léger zoom depuis 92 %.
		ui.scale.Scale = 0.92
		Animate.tween(ui.scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		CollectionPanel.showTab(state.tab)
	else
		panel.Visible = false
		detailModel = nil
		ModelView.clear(ui.detailViewport)
		ui.detailViewport:SetAttribute("SpecimenId", nil)
	end
end

function CollectionPanel.toggle()
	CollectionPanel.setOpen(not CollectionPanel.isOpen())
end

-- Sélectionne un exemplaire (fiche affichée) et va à sa page. Utilisé aussi par les tests Studio.
function CollectionPanel.select(specimenId: string)
	local list = CollectionQuery.sort(CollectionQuery.filter(ClientState.specimens, state.filter), state.sort)
	for index, specimen in list do
		if specimen.id == specimenId then
			state.page = math.ceil(index / (ui.perPage or 8))
			break
		end
	end
	state.selectedId = specimenId
	state.detailOpen = true
	CollectionPanel.refresh()
end

function CollectionPanel.page(): any
	return ui
end

function CollectionPanel.build(gui: ScreenGui, touch: boolean)
	local panel = Theme.panel({
		Name = "CollectionPanel",
		Visible = false,
		ZIndex = 10,
		BackgroundColor3 = Color3.fromRGB(24, 18, 38),
		BackgroundTransparency = 0.03,
		Parent = gui,
	})
	ui.panel = panel
	ui.scale = Theme.create("UIScale", { Scale = 1, Parent = panel }) :: UIScale
	buildHeader(panel)
	CollectionPanel.addTab("Codex", "Codex", buildCodexPage(), refreshCodex)
	CollectionPanel.addTab("Inventory", "Inventaire", buildInventoryPage(), refreshInventory)
	require(script.Parent.ObjectivesTab).register(CollectionPanel)

	ui.close.Activated:Connect(function()
		CollectionPanel.setOpen(false)
	end)

	-- Rectangle du panneau (HudLayout), recalculé avec la taille de l'écran.
	local function place()
		local size = gui.AbsoluteSize
		if size.X < 2 then
			return
		end
		local layoutRects = HudLayout.compute(size.X, size.Y, touch)
		state.compact = layoutRects.mode == "touchCompact"
		local r = layoutRects.panel
		panel.Position = UDim2.fromOffset(r.x, r.y)
		panel.Size = UDim2.fromOffset(r.w, r.h)
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	ClientState.CollectionChanged:Connect(function()
		state.dirty = true
		if panel.Visible then
			CollectionPanel.refresh()
		else
			refreshCompletion()
		end
	end)

	-- Rotation lente de l'aperçu de la fiche, seulement quand il est affiché.
	RunService.RenderStepped:Connect(function()
		local model = detailModel
		if model and model.Parent and panel.Visible then
			model:PivotTo(CFrame.Angles(0, os.clock() * 0.9, 0))
		end
	end)
	return ui
end

return CollectionPanel
