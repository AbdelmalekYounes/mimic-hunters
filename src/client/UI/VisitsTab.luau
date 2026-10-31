--!strict
--[[
	VisitsTab — onglet « Visites » : les musées des joueurs présents sur le serveur.

	Pour chacun : nom, espèces découvertes, Mimics exposés, mutations différentes exposées,
	et un bouton Visiter (le serveur choisit la destination : l'entrée du musée). La liste est
	demandée au serveur à chaque ouverture de l'onglet (RequestMuseums → MuseumList).
	Un visiteur peut tout regarder et examiner, mais rien modifier : les requêtes de
	modification ne portent que sur la collection de celui qui les envoie.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local Audio = require(Client.Util.Audio)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local VisitsTab = {}

local ui: any = {}
local entries: { any } = {}
local panelApi: any

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else string.format("Collectionneur %d", math.abs(userId))
end

function VisitsTab.visit(userId: number)
	Audio.play("UiClick")
	Remotes.get("RequestTravel"):FireServer("museum", userId)
	if panelApi then
		panelApi.setOpen(false)
	end
end

local function render()
	for _, child in ui.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.sort(entries, function(a, b)
		if a.mine ~= b.mine then
			return a.mine -- son propre musée en premier
		end
		return a.exhibited > b.exhibited
	end)
	for index, entry in entries do
		local row = Theme.panel({
			Name = "Museum_" .. tostring(entry.userId),
			LayoutOrder = index,
			Size = UDim2.new(1, -10, 0, 58),
			BackgroundColor3 = if entry.mine then Color3.fromRGB(44, 40, 72) else Color3.fromRGB(40, 32, 62),
			BackgroundTransparency = 0.1,
			Parent = ui.list,
		})
		Theme.text({
			Name = "Name",
			Text = (if entry.mine then "Ton musée" else "Musée de " .. nameOf(entry.userId))
				.. (if entry.busy then "  ·  défi en cours" else ""),
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.66, -12, 0.5, -2),
			Position = UDim2.fromOffset(12, 4),
			MaxTextSize = 18,
			Parent = row,
		})
		Theme.text({
			Name = "Stats",
			Text = string.format(
				"Espèces %d/%d  ·  Exposés %d/6  ·  Mutations exposées %d",
				entry.discovered,
				MimicCatalog.count(),
				entry.exhibited,
				entry.mutationsExhibited
			),
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.66, -12, 0.42, 0),
			Position = UDim2.new(0, 12, 0.52, 0),
			MaxTextSize = 14,
			Parent = row,
		})
		local button = Theme.button({
			Name = "Visit",
			Text = if entry.mine then "Y aller" else "Visiter",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0.3, 0, 1, -14),
			BackgroundColor3 = if entry.mine then Color3.fromRGB(120, 70, 150) else Color3.fromRGB(60, 110, 90),
			StrokeColor = if entry.mine then C.Pink else C.Mint,
			MaxTextSize = 16,
			Parent = row,
		})
		button.Activated:Connect(function()
			VisitsTab.visit(entry.userId)
		end)
	end
	ui.empty.Visible = #entries == 0
	ui.header.Text = string.format("%d musée%s sur ce serveur", #entries, if #entries > 1 then "s" else "")
end

local function build(): Frame
	local page = Theme.create("Frame", { Name = "VisitsPage", BackgroundTransparency = 1 }) :: Frame
	ui.page = page
	ui.header = Theme.text({
		Name = "Header",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Mint,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -10, 0, 26),
		MaxTextSize = 16,
		Parent = page,
	})
	ui.list = Theme.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
	}) :: ScrollingFrame
	Theme.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.list })
	ui.empty = Theme.text({
		Name = "Empty",
		Text = "Aucun musée pour l'instant.",
		TextColor3 = C.Muted,
		Visible = false,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 40),
		MaxTextSize = 16,
		Parent = page,
	})
	Remotes.get("MuseumList").OnClientEvent:Connect(function(payload)
		if payload.ok then
			entries = payload.entries
			render()
		end
	end)
	return page
end

-- À chaque affichage de l'onglet : liste fraîche demandée au serveur.
local function refresh()
	Remotes.get("RequestMuseums"):FireServer()
end

function VisitsTab.register(CollectionPanel: any)
	panelApi = CollectionPanel
	CollectionPanel.addTab("Visits", "Visites", build(), refresh)
end

function VisitsTab.ui(): any
	return ui
end

function VisitsTab.entries(): { any }
	return entries
end

return VisitsTab
