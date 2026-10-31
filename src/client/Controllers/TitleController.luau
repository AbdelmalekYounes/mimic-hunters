--!strict
--[[
	TitleController — titre de collectionneur au-dessus de chaque personnage.

	Le serveur place l'identifiant du titre équipé dans l'attribut « MimicTitle » du joueur
	(seul un titre débloqué peut être équipé). Chaque client affiche une petite étiquette
	au-dessus de la tête, visible de près (de quoi montrer sa progression).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Objectives = require(ReplicatedStorage:WaitForChild("Shared").Config.Objectives)

local Theme = require(script.Parent.Parent.UI.Theme)

local TitleController = {}

local function refresh(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head == nil then
		return
	end
	local existing = head:FindFirstChild("MimicTitle")
	local cosmetic = Objectives.cosmetic(player:GetAttribute("MimicTitle") :: string?)
	if cosmetic == nil or cosmetic.kind ~= "title" then
		if existing then
			existing:Destroy()
		end
		return
	end
	local gui = existing :: BillboardGui?
	if gui == nil then
		local created = Instance.new("BillboardGui")
		created.Name = "MimicTitle"
		created.Size = UDim2.fromOffset(200, 26)
		created.StudsOffset = Vector3.new(0, 2.6, 0)
		created.MaxDistance = 60
		created.LightInfluence = 0
		created.Adornee = head
		created.Parent = head
		local text = Theme.text({
			Name = "Text",
			Text = "",
			Font = Theme.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 20,
			TextStrokeTransparency = 0.25,
			Parent = created,
		})
		text.TextStrokeColor3 = Color3.fromRGB(20, 12, 30)
		gui = created
	end
	local label = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
	label.Text = "« " .. cosmetic.name .. " »"
	label.TextColor3 = Theme.rgb(cosmetic.color)
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("MimicTitle"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		refresh(player)
	end)
	if player.Character then
		refresh(player)
	end
end

function TitleController.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return TitleController
