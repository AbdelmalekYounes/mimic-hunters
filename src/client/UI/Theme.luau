--!strict
-- Theme — couleurs, polices et petits constructeurs d'interface.

local UserInputService = game:GetService("UserInputService")

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(26, 20, 40),
	PanelLight = Color3.fromRGB(44, 36, 66),
	Stroke = Color3.fromRGB(150, 120, 220),
	Text = Color3.fromRGB(250, 246, 255),
	Muted = Color3.fromRGB(190, 180, 214),
	Mint = Color3.fromRGB(110, 250, 200),
	Pink = Color3.fromRGB(255, 120, 186),
	Yellow = Color3.fromRGB(255, 220, 100),
	Red = Color3.fromRGB(255, 96, 110),
	Cyan = Color3.fromRGB(110, 220, 255),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

-- Tactile sans clavier : boutons plus grands et placés au-dessus du bouton de saut.
function Theme.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Theme.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function Theme.create(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Theme.corner(radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	return c
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Colors.Stroke
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

function Theme.padding(px: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	return p
end

function Theme.panel(props: { [string]: any }): Frame
	local merged = table.clone(props)
	merged.BackgroundColor3 = merged.BackgroundColor3 or Theme.Colors.Panel
	merged.BackgroundTransparency = merged.BackgroundTransparency or 0.12
	merged.BorderSizePixel = 0
	local frame = Theme.create("Frame", merged, { Theme.corner(), Theme.stroke() }) :: Frame
	return frame
end

function Theme.text(props: { [string]: any }): TextLabel
	local merged = table.clone(props)
	merged.BackgroundTransparency = 1
	merged.Font = merged.Font or Theme.Fonts.Body
	merged.TextColor3 = merged.TextColor3 or Theme.Colors.Text
	merged.TextScaled = if merged.TextScaled == nil then true else merged.TextScaled
	merged.MaxTextSize = nil
	local label = Theme.create("TextLabel", merged) :: TextLabel
	if merged.TextScaled then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = props.MaxTextSize or 28
		limit.Parent = label
	end
	return label
end

function Theme.button(props: { [string]: any }): TextButton
	local merged = table.clone(props)
	merged.BackgroundColor3 = merged.BackgroundColor3 or Theme.Colors.PanelLight
	merged.AutoButtonColor = true
	merged.BorderSizePixel = 0
	merged.Font = merged.Font or Theme.Fonts.Title
	merged.TextColor3 = merged.TextColor3 or Theme.Colors.Text
	merged.TextScaled = true
	-- Options propres au thème, qui ne sont pas des propriétés Roblox.
	merged.MaxTextSize = nil
	merged.Radius = nil
	merged.StrokeColor = nil
	local button = Theme.create("TextButton", merged, {
		Theme.corner(props.Radius or 16),
		Theme.stroke(props.StrokeColor, 3, 0.1),
	}) :: TextButton
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.MaxTextSize or 26
	limit.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = button
	return button
end

return Theme
