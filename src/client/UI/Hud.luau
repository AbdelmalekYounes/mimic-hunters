--!strict
--[[
	Hud — construit toute l'interface en code (aucun asset).

	Principes : rien ne masque le jeu en permanence ; les boutons d'action
	sont regroupés en bas à droite, au-dessus du bouton de saut sur mobile ;
	les panneaux (codex, capture) restent compacts.
	Positions et tailles des éléments principaux : HudLayout (pur, testé), recalculées
	quand la taille de l'écran change (rotation, fenêtre redimensionnée).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudLayout = require(ReplicatedStorage:WaitForChild("Shared").Logic.HudLayout)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local create = Theme.create

local Hud = {}

export type Refs = {
	gui: ScreenGui,
	stats: TextLabel,
	banner: Frame,
	bannerText: TextLabel,
	toasts: Frame,
	signal: Frame,
	signalText: TextLabel,
	signalBars: { Frame },
	scanButton: TextButton,
	scanCooldown: Frame,
	actionButton: TextButton,
	actionHint: TextLabel,
	codexButton: TextButton,
	capture: Frame,
	captureTitle: TextLabel,
	gauge: Frame,
	zone: Frame,
	cursor: Frame,
	pips: TextLabel,
	lives: TextLabel,
	feedback: TextLabel,
	pulseButton: TextButton,
	timerFill: Frame,
	popup: Frame,
	popupScale: UIScale,
	popupViewport: ViewportFrame,
	popupHeadline: TextLabel,
	popupName: TextLabel,
	popupRarity: TextLabel,
	popupCount: TextLabel,
	codex: Frame,
	codexGrid: ScrollingFrame,
	codexClose: TextButton,
	codexProgress: TextLabel,
	touch: boolean,
}

local function keyHint(parent: Instance, text: string, touch: boolean): TextLabel
	local hint = Theme.text({
		Name = "KeyHint",
		Text = text,
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 4, 0, 4),
		BackgroundTransparency = 0,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Panel,
		MaxTextSize = 18,
		Visible = not touch,
		Parent = parent,
	})
	hint.BackgroundTransparency = 0
	hint.BackgroundColor3 = C.Yellow
	Theme.corner(8).Parent = hint
	return hint
end

function Hud.build(): Refs
	local touch = Theme.isTouch()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = create("ScreenGui", {
		Name = "MimicHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	-- ── Compteur (haut gauche, sous la barre Roblox) ──
	local counter = Theme.panel({
		Name = "Counter",
		Parent = gui,
	})
	Theme.padding(8).Parent = counter
	Theme.text({
		Text = "MIMIC HUNTERS",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Mint,
		Size = UDim2.new(1, 0, 0.45, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = counter,
	})
	local stats = Theme.text({
		Name = "Stats",
		Text = "Captures : 0   ·   Espèces : 0/6",
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.fromScale(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = counter,
	})

	-- ── Bandeau du tutoriel (haut, à droite du compteur ou dessous) ──
	local banner = Theme.panel({
		Name = "Banner",
		BackgroundColor3 = Color3.fromRGB(56, 36, 92),
		Visible = false,
		Parent = gui,
	})
	Theme.padding(8).Parent = banner
	local bannerText = Theme.text({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Title,
		MaxTextSize = 22,
		Parent = banner,
	})

	-- ── Notifications ──
	local toasts = create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})

	-- ── Boutons d'action (bas droite) ──
	local actionButton = Theme.button({
		Name = "Action",
		Text = "EXAMINER",
		BackgroundColor3 = Color3.fromRGB(70, 52, 120),
		StrokeColor = C.Mint,
		Parent = gui,
	})
	local actionHint = keyHint(actionButton, "F", touch)

	local scanButton = Theme.button({
		Name = "Scan",
		Text = "SCAN",
		BackgroundColor3 = Color3.fromRGB(40, 110, 130),
		StrokeColor = C.Cyan,
		Radius = 43,
		Parent = gui,
	})
	keyHint(scanButton, "E", touch)
	local scanCooldown = create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = scanButton,
	}) :: Frame
	Theme.corner(43).Parent = scanCooldown

	local codexButton = Theme.button({
		Name = "Codex",
		Text = "CODEX",
		BackgroundColor3 = Color3.fromRGB(110, 60, 110),
		StrokeColor = C.Pink,
		MaxTextSize = 18,
		Parent = gui,
	})
	keyHint(codexButton, "C", touch)

	-- ── Lecture du scanner ──
	local signal = Theme.panel({
		Name = "Signal",
		Visible = false,
		Parent = gui,
	})
	Theme.padding(6).Parent = signal
	local signalText = Theme.text({
		Name = "Value",
		Text = "SIGNAL : —",
		Size = UDim2.new(0.68, 0, 1, 0),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = signal,
	})
	local signalBars = {}
	for i = 1, 3 do
		local bar = create("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0, 1),
			Size = UDim2.new(0, 10, i / 3, 0),
			Position = UDim2.new(0.7, (i - 1) * 16, 1, 0),
			BackgroundColor3 = C.Muted,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Parent = signal,
		}) :: Frame
		Theme.corner(3).Parent = bar
		table.insert(signalBars, bar)
	end

	-- ── Minijeu de capture (bas, à gauche des boutons si la place manque) ──
	local capture = Theme.panel({
		Name = "Capture",
		BackgroundColor3 = Color3.fromRGB(30, 22, 48),
		Visible = false,
		Parent = gui,
	})
	Theme.padding(12).Parent = capture
	local captureTitle = Theme.text({
		Name = "Title",
		Text = "Stabilise le Mimic !",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(0.62, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = capture,
	})
	local pips = Theme.text({
		Name = "Pips",
		Text = "○ ○",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Mint,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0.2, 0, 0, 26),
		Position = UDim2.new(1, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Parent = capture,
	})
	local lives = Theme.text({
		Name = "Lives",
		Text = "♥ ♥",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Pink,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0.18, 0, 0, 26),
		Position = UDim2.new(0.8, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 20,
		Parent = capture,
	})
	local gauge = create("Frame", {
		Name = "Gauge",
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.fromOffset(0, 34),
		BackgroundColor3 = Color3.fromRGB(16, 12, 26),
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Parent = capture,
	}) :: Frame
	Theme.corner(12).Parent = gauge
	Theme.stroke(C.Stroke, 2, 0.4).Parent = gauge
	local zone = create("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.25, 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.Mint,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gauge,
	}) :: Frame
	Theme.corner(8).Parent = zone
	local cursor = create("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 8, 1, 14),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = gauge,
	}) :: Frame
	Theme.corner(4).Parent = cursor
	Theme.stroke(C.Yellow, 2, 0).Parent = cursor
	local timerBack = create("Frame", {
		Name = "Timer",
		Size = UDim2.new(1, 0, 0, 5),
		Position = UDim2.fromOffset(0, 78),
		BackgroundColor3 = Color3.fromRGB(16, 12, 26),
		BorderSizePixel = 0,
		Parent = capture,
	}) :: Frame
	Theme.corner(3).Parent = timerBack
	local timerFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Yellow,
		BorderSizePixel = 0,
		Parent = timerBack,
	}) :: Frame
	Theme.corner(3).Parent = timerFill
	local feedback = Theme.text({
		Name = "Feedback",
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(0.4, 0, 0, 44),
		Position = UDim2.fromOffset(0, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxTextSize = 22,
		Parent = capture,
	})
	local pulseButton = Theme.button({
		Name = "Pulse",
		Text = if touch then "IMPULSION !" else "IMPULSION  [Espace / Clic]",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.new(if touch then 0.6 else 0.55, 0, 0, if touch then 92 else 56),
		Position = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 150, 120),
		StrokeColor = C.Mint,
		MaxTextSize = if touch then 30 else 20,
		Parent = capture,
	})

	-- ── Carte de découverte (centre) ──
	local popup = Theme.panel({
		Name = "Discovery",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(300, 340),
		Position = UDim2.fromScale(0.5, 0.42),
		BackgroundColor3 = Color3.fromRGB(36, 26, 60),
		Visible = false,
		Parent = gui,
	})
	local popupScale = create("UIScale", { Scale = 1, Parent = popup }) :: UIScale
	Theme.padding(12).Parent = popup
	local popupHeadline = Theme.text({
		Name = "Headline",
		Text = "NOUVELLE ESPÈCE !",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Yellow,
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 26,
		Parent = popup,
	})
	local popupViewport = create("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.new(1, 0, 0, 190),
		Position = UDim2.fromOffset(0, 34),
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(200, 190, 220),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, 1),
		Parent = popup,
	}) :: ViewportFrame
	Theme.corner(12).Parent = popupViewport
	local popupName = Theme.text({
		Name = "Name",
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 230),
		MaxTextSize = 30,
		Parent = popup,
	})
	local popupRarity = Theme.text({
		Name = "Rarity",
		Text = "",
		Font = Theme.Fonts.Bold,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 266),
		MaxTextSize = 20,
		Parent = popup,
	})
	local popupCount = Theme.text({
		Name = "Count",
		Text = "",
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 292),
		MaxTextSize = 18,
		Parent = popup,
	})

	-- ── Codex (panneau latéral) ──
	local codex = Theme.panel({
		Name = "Codex",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0.5, 0, 0.74, 0),
		Position = UDim2.new(0, 12, 0.52, 0),
		Visible = false,
		Parent = gui,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(560, 620), MinSize = Vector2.new(300, 260), Parent = codex })
	Theme.padding(12).Parent = codex
	Theme.text({
		Text = "CODEX DES MIMICS",
		Font = Theme.Fonts.Title,
		TextColor3 = C.Pink,
		Size = UDim2.new(1, -50, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = codex,
	})
	local codexProgress = Theme.text({
		Name = "Progress",
		Text = "0 / 6 découverts",
		TextColor3 = C.Muted,
		Size = UDim2.new(1, -50, 0, 20),
		Position = UDim2.fromOffset(0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = codex,
	})
	local codexClose = Theme.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.fromRGB(110, 50, 80),
		StrokeColor = C.Pink,
		Parent = codex,
	})
	local codexGrid = create("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, 0, 1, -62),
		Position = UDim2.fromOffset(0, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = codex,
	}) :: ScrollingFrame
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 200),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = codexGrid,
	})

	-- ── Disposition (HudLayout), recalculée à chaque changement de taille ──
	local placed: { [string]: GuiObject } = {
		counter = counter,
		banner = banner,
		toasts = toasts,
		action = actionButton,
		scan = scanButton,
		codex = codexButton,
		signal = signal,
		capture = capture,
	}
	local function applyLayout()
		local size = gui.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			return -- vue pas encore dimensionnée
		end
		local layout = HudLayout.compute(size.X, size.Y, touch)
		for key, object in placed do
			local r = (layout :: any)[key] :: HudLayout.Rect
			object.AnchorPoint = Vector2.zero
			object.Position = UDim2.fromOffset(r.x, r.y)
			object.Size = UDim2.fromOffset(r.w, r.h)
		end
		gui:SetAttribute("Layout", layout.mode)
	end
	applyLayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	return {
		gui = gui,
		stats = stats,
		banner = banner,
		bannerText = bannerText,
		toasts = toasts,
		signal = signal,
		signalText = signalText,
		signalBars = signalBars,
		scanButton = scanButton,
		scanCooldown = scanCooldown,
		actionButton = actionButton,
		actionHint = actionHint,
		codexButton = codexButton,
		capture = capture,
		captureTitle = captureTitle,
		gauge = gauge,
		zone = zone,
		cursor = cursor,
		pips = pips,
		lives = lives,
		feedback = feedback,
		pulseButton = pulseButton,
		timerFill = timerFill,
		popup = popup,
		popupScale = popupScale,
		popupViewport = popupViewport,
		popupHeadline = popupHeadline,
		popupName = popupName,
		popupRarity = popupRarity,
		popupCount = popupCount,
		codex = codex,
		codexGrid = codexGrid,
		codexClose = codexClose,
		codexProgress = codexProgress,
		touch = touch,
	}
end

-- Notification courte, empilée sous le bandeau.
function Hud.toast(refs: Refs, text: string, color: Color3?)
	local frame = Theme.panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Color3.fromRGB(30, 24, 46),
		Parent = refs.toasts,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(460, 40), Parent = frame })
	local label = Theme.text({
		Text = text,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Font = Theme.Fonts.Bold,
		TextColor3 = color or C.Text,
		MaxTextSize = 18,
		Parent = frame,
	})
	local children = refs.toasts:GetChildren()
	local count = 0
	for _, child in children do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 3 then
		for _, child in children do
			if child:IsA("Frame") and child ~= frame then
				child:Destroy()
				break
			end
		end
	end
	task.delay(2.4, function()
		if frame.Parent then
			label.TextTransparency = 0.5
			frame.BackgroundTransparency = 0.6
			task.wait(0.25)
			frame:Destroy()
		end
	end)
end

return Hud
