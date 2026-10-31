--!strict
--[[
	MutationFx — animation légère des exemplaires mutés, uniquement sur les modèles affichés
	(carte de capture, fiche détaillée, révélation dans le monde).

	- Chromatic : la teinte des parties colorées glisse lentement (SpecimenLook.chromaticAt),
	  la lumière suit.
	- Spectral : les lueurs tournent autour du Mimic et la translucidité « respire ».

	Coût : quelques parties par modèle, mises à jour ~30 fois par seconde au plus ; les modèles
	retirés du jeu sont oubliés automatiquement. Désactivé si le joueur réduit les effets.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpecimenLook = require(ReplicatedStorage:WaitForChild("Shared").Logic.SpecimenLook)

type Entry = {
	model: Model,
	mutation: string,
	look: any,
	tints: { BasePart },
	wisps: { BasePart },
	light: PointLight?,
	baseTransparency: number,
	-- Au-delà de cette distance de la caméra : plus d'animation (lumière coupée).
	maxDistance: number?,
}

local MutationFx = {}

local entries: { Entry } = {}
local accumulator = 0
local started = false

MutationFx.enabled = true
-- « Effets réduits » : éclats de mutation allumés seulement à moins de cette distance.
MutationFx.ReducedLightDistance = 20

local function step(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	accumulator = 0
	local t = os.clock()
	for i = #entries, 1, -1 do
		local entry = entries[i]
		local model = entry.model
		if model.Parent == nil then
			table.remove(entries, i)
			continue
		end
		-- Limite de distance de la lumière : celle de l'objet (musée), et au plus
		-- ReducedLightDistance en « Effets réduits ». Testée AVANT de sauter l'animation :
		-- sinon, en effets réduits, les éclats restaient allumés partout (audit V0.3.1, C4).
		local limit = entry.maxDistance
		if not MutationFx.enabled then
			limit = math.min(limit or math.huge, MutationFx.ReducedLightDistance)
		end
		local far = false
		if limit then
			local camera = workspace.CurrentCamera
			far = camera ~= nil and (camera.CFrame.Position - model:GetPivot().Position).Magnitude > limit
			if entry.light then
				entry.light.Enabled = not far
			end
		end
		if far or not MutationFx.enabled then
			continue
		end
		if entry.mutation == "Chromatic" then
			local rgb = SpecimenLook.chromaticAt(entry.look.body, t)
			local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
			for _, part in entry.tints do
				part.Color = color
			end
			if entry.light then
				entry.light.Color = color
			end
		elseif entry.mutation == "Spectral" then
			local pivot = model:GetPivot()
			for index, wisp in entry.wisps do
				local angle = t * 1.6 + (index - 1) * math.pi * 2 / 3
				local radius = 2.2 * (model:GetScale())
				local height = wisp:GetAttribute("Height") :: number
				wisp.CFrame = pivot
					* CFrame.new(
						math.cos(angle) * radius,
						height + math.sin(t * 3 + index) * 0.25,
						math.sin(angle) * radius
					)
			end
			local breath = entry.baseTransparency + math.sin(t * 2.2) * 0.08
			for _, part in entry.tints do
				part.Transparency = breath
			end
		end
	end
end

-- Enregistre un modèle construit avec une apparence (SpecimenLook) ; sans effet si Standard.
function MutationFx.attach(model: Model, look: any, maxDistance: number?)
	if look == nil or (look.mutation ~= "Chromatic" and look.mutation ~= "Spectral") then
		return
	end
	if not started then
		started = true
		RunService.RenderStepped:Connect(step)
	end
	local entry: Entry = {
		model = model,
		mutation = look.mutation,
		look = look,
		tints = {},
		wisps = {},
		light = nil,
		baseTransparency = look.transparency or 0,
		maxDistance = maxDistance,
	}
	local pivot = model:GetPivot()
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			if child:GetAttribute("Tint") then
				table.insert(entry.tints, child)
			elseif child:GetAttribute("Wisp") then
				-- Hauteur de départ relative au pivot, conservée pendant l'orbite.
				child:SetAttribute("Height", pivot:PointToObjectSpace(child.Position).Y)
				table.insert(entry.wisps, child)
			end
		elseif child:IsA("PointLight") and child.Name == "MutationGlow" then
			entry.light = child
		end
	end
	table.insert(entries, entry)
end

return MutationFx
