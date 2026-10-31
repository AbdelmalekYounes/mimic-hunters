--!strict
--[[
	MimicModelBuilder — la forme révélée de chaque espèce.

	Part du même objet que le déguisement (PropBuilder), le recolore à la
	couleur de l'espèce et ajoute un visage expressif : grands yeux, bouche,
	détails propres à l'espèce. Uniquement des Parts : aucun rig, aucun asset.
]]

local Shared = script.Parent.Parent
local Geometry = require(script.Parent.Geometry)
local PropBuilder = require(script.Parent.PropBuilder)
local MimicCatalog = require(Shared.Config.MimicCatalog)

local MimicModelBuilder = {}

local V = Vector3.new
local C = CFrame.new
local WHITE = Color3.fromRGB(250, 250, 250)
local INK = Color3.fromRGB(28, 22, 36)
local PINK = Color3.fromRGB(255, 130, 160)

local function feature(model: Instance, props: any): BasePart
	props.Parent = model
	props.CanCollide = false
	props.CastShadow = false
	local p = Geometry.part(props)
	p:SetAttribute("Feature", true)
	return p
end

local function eye(model: Instance, cf: CFrame, size: number)
	feature(model, {
		Name = "EyeWhite",
		Shape = Enum.PartType.Ball,
		Size = V(size, size, size),
		CFrame = cf * C(0, 0, -size * 0.12),
		Color = WHITE,
	})
	feature(model, {
		Name = "Pupil",
		Shape = Enum.PartType.Ball,
		Size = V(size * 0.52, size * 0.52, size * 0.52),
		CFrame = cf * C(0, -size * 0.06, -size * 0.36),
		Color = INK,
	})
	feature(model, {
		Name = "Glint",
		Shape = Enum.PartType.Ball,
		Size = V(size * 0.17, size * 0.17, size * 0.17),
		CFrame = cf * C(size * 0.1, size * 0.08, -size * 0.6),
		Color = WHITE,
		Material = Enum.Material.Neon,
	})
end

--[[
	Ajoute une paire d'yeux au modèle. Utilisé pour la forme révélée et pour
	l'indice « Eyes » (des yeux qui apparaissent brièvement sur l'objet).
	Les positions sont relatives au pivot `base`.
]]
function MimicModelBuilder.addEyes(model: Instance, kind: string, style: string, base: CFrame?): ()
	local anchor = PropBuilder.FaceAnchors[kind]
	if anchor == nil then
		return
	end
	local origin = (base or CFrame.identity) * anchor.cframe
	local size, spacing = anchor.eyeSize, anchor.eyeSpacing
	if style == "Cyclops" then
		eye(model, origin, size * 1.7)
	elseif style == "Odd" then
		eye(model, origin * C(-spacing / 2, 0.05, 0), size * 1.2)
		eye(model, origin * C(spacing / 2, -0.05, 0), size * 0.82)
	elseif style == "Screen" then
		for _, side in { -1, 1 } do
			feature(model, {
				Name = "ScreenEye",
				Size = V(size * 0.7, size * 0.42, 0.08),
				CFrame = origin * C(side * spacing / 2, 0, -0.06),
				Color = Color3.fromRGB(120, 255, 230),
				Material = Enum.Material.Neon,
			})
		end
	else
		eye(model, origin * C(-spacing / 2, 0, 0), size)
		eye(model, origin * C(spacing / 2, 0, 0), size)
		if style == "Angry" then
			for _, side in { -1, 1 } do
				feature(model, {
					Name = "Brow",
					Size = V(size * 1.05, size * 0.2, 0.1),
					CFrame = origin
						* C(side * spacing / 2, size * 0.62, -size * 0.3)
						* CFrame.Angles(0, 0, math.rad(-side * 22)),
					Color = INK,
				})
			end
		end
	end
end

local function addMouth(model: Model, kind: string, style: string, accent: Color3)
	local anchor = PropBuilder.FaceAnchors[kind]
	local m = anchor.mouth
	if style == "Smile" then
		feature(model, { Name = "Mouth", Size = V(0.42, 0.12, 0.06), CFrame = m * C(0, 0, -0.04), Color = INK })
		for _, side in { -1, 1 } do
			feature(model, {
				Name = "Mouth",
				Size = V(0.26, 0.12, 0.06),
				CFrame = m * C(side * 0.3, 0.07, -0.04) * CFrame.Angles(0, 0, math.rad(side * 28)),
				Color = INK,
			})
			feature(model, {
				Name = "Cheek",
				Shape = Enum.PartType.Ball,
				Size = V(0.32, 0.32, 0.32),
				CFrame = m * C(side * 0.75, 0.32, -0.02),
				Color = accent,
			})
		end
	elseif style == "Teeth" then
		feature(model, { Name = "Mouth", Size = V(1.3, 0.4, 0.06), CFrame = m * C(0, 0, -0.04), Color = INK })
		for i = 0, 3 do
			feature(model, {
				Name = "Tooth",
				Size = V(0.2, 0.2, 0.07),
				CFrame = m * C(-0.45 + i * 0.3, 0.1, -0.08) * CFrame.Angles(0, 0, math.rad(45)),
				Color = WHITE,
			})
		end
	elseif style == "Letter" then
		feature(model, { Name = "Mouth", Size = V(0.8, 0.22, 0.06), CFrame = m * C(0, 0, -0.04), Color = INK })
		feature(model, {
			Name = "Letter",
			Size = V(0.75, 0.5, 0.06),
			CFrame = m * C(0.1, -0.25, -0.12) * CFrame.Angles(math.rad(-25), 0, math.rad(-12)),
			Color = WHITE,
		})
		feature(model, {
			Name = "Stamp",
			Size = V(0.16, 0.16, 0.07),
			CFrame = m * C(0.32, -0.18, -0.15) * CFrame.Angles(math.rad(-25), 0, math.rad(-12)),
			Color = Color3.fromRGB(235, 80, 80),
		})
	elseif style == "Small" then
		feature(model, { Name = "Mouth", Size = V(0.26, 0.14, 0.06), CFrame = m * C(0, 0, -0.04), Color = INK })
	elseif style == "Chomp" then
		-- Rangée de dents le long de l'ouverture du coffre et langue rose.
		for i = 0, 5 do
			feature(model, {
				Name = "Tooth",
				Size = V(0.3, 0.32, 0.14),
				CFrame = C(-1.25 + i * 0.5, 1.55, -1.13) * CFrame.Angles(0, 0, math.rad(45)),
				Color = WHITE,
			})
		end
		feature(model, { Name = "Tongue", Size = V(1.2, 0.14, 1.0), CFrame = C(0, 1.62, -0.55), Color = accent })
	elseif style == "Wave" then
		for i = 0, 3 do
			feature(model, {
				Name = "Mouth",
				Size = V(0.32, 0.1, 0.06),
				CFrame = m
					* C(-0.42 + i * 0.28, 0, -0.04)
					* CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)),
				Color = Color3.fromRGB(120, 255, 230),
				Material = Enum.Material.Neon,
			})
		end
	end
end

local function addSpeciesDetails(model: Model, species: any, accent: Color3)
	if species.id == "chairy" then
		-- Petit nœud sur le dossier.
		feature(model, { Name = "Bow", Size = V(0.5, 0.3, 0.15), CFrame = C(0.7, 4.3, 0.78), Color = PINK })
	elseif species.id == "trashling" then
		-- Une arête de poisson qui dépasse du couvercle.
		feature(model, {
			Name = "Snack",
			Size = V(0.12, 0.9, 0.12),
			CFrame = C(0.7, 3.9, 0.3) * CFrame.Angles(0, 0, math.rad(25)),
			Color = accent,
		})
	elseif species.id == "lumino" then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") and child:GetAttribute("Glow") then
				child.Color = accent
				local light = child:FindFirstChildOfClass("PointLight")
				if light then
					light.Color = accent
					light.Brightness = 2.2
				end
			end
		end
	elseif species.id == "vendoo" then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") and child:GetAttribute("Glow") then
				child.Color = accent
			end
		end
		feature(model, {
			Name = "Antenna",
			Size = V(0.12, 1.2, 0.12),
			CFrame = C(1.2, 7.2, 0),
			Color = INK,
		})
		feature(model, {
			Name = "AntennaTip",
			Shape = Enum.PartType.Ball,
			Size = V(0.4, 0.4, 0.4),
			CFrame = C(1.2, 7.85, 0),
			Color = accent,
			Material = Enum.Material.Neon,
		})
	end
end

-- Effets propres aux mutations, appliqués après la construction (voir SpecimenLook).
-- Le client anime ensuite ces éléments (MutationFx) : teinte changeante, lueurs en orbite.
local function applyMutationLook(model: Model, species: any, look: any)
	local anchor = PropBuilder.FaceAnchors[species.kind]
	local height = if anchor then anchor.height else 4
	if look.mutation == "Spectral" then
		-- Trois petites lueurs autour du Mimic (positions de départ ; l'orbite est animée).
		for i = 1, 3 do
			local angle = (i - 1) * math.pi * 2 / 3
			local wisp = feature(model, {
				Name = "Wisp",
				Shape = Enum.PartType.Ball,
				Size = V(0.38, 0.38, 0.38),
				CFrame = C(math.cos(angle) * 2.2, height * (0.45 + 0.15 * i), math.sin(angle) * 2.2),
				Color = Geometry.rgb(look.eyeGlow or look.accent),
				Material = Enum.Material.Neon,
				Transparency = 0.15,
			})
			wisp:SetAttribute("Wisp", i)
		end
	elseif look.mutation == "Chromatic" then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") and child.Name == "Glint" then
				child.Color = Geometry.rgb(look.glow or look.accent)
			end
		end
	end
	if look.transparency and look.transparency > 0 then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") and child:GetAttribute("Tint") then
				child.Transparency = look.transparency
				child.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	if look.eyeGlow then
		local color = Geometry.rgb(look.eyeGlow)
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") and (child.Name == "Pupil" or child.Name == "ScreenEye") then
				child.Color = color
				child.Material = Enum.Material.Neon
			end
		end
	end
	if look.glow then
		local root = model.PrimaryPart
		if root then
			local light = Instance.new("PointLight")
			light.Name = "MutationGlow"
			light.Color = Geometry.rgb(look.glow)
			light.Brightness = 1.4
			light.Range = 9
			light.Parent = root
		end
	end
	model:SetAttribute("Mutation", look.mutation)
end

--[[
	Construit la forme révélée d'une espèce, à l'origine.
	`look` (SpecimenLook) : apparence d'un exemplaire précis (couleurs, taille, mutation) ;
	sans `look`, l'apparence de référence de l'espèce.
]]
function MimicModelBuilder.build(speciesId: string, variant: number?, look: any?): Model
	local species = MimicCatalog.get(speciesId)
	assert(species, "MimicModelBuilder : espèce inconnue " .. tostring(speciesId))
	local model = PropBuilder.build(species.kind, variant)
	model.Name = species.name
	local body = Geometry.rgb(if look then look.body else species.appearance.bodyColor)
	local accent = Geometry.rgb(if look then look.accent else species.appearance.accentColor)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.CanCollide = false
			if child:GetAttribute("Tint") then
				child.Color = body
			end
		end
	end
	MimicModelBuilder.addEyes(model, species.kind, species.appearance.eyes)
	addMouth(model, species.kind, species.appearance.mouth, accent)
	addSpeciesDetails(model, species, accent)
	model:SetAttribute("SpeciesId", species.id)
	if look then
		applyMutationLook(model, species, look)
		-- Taille de l'exemplaire, autour du pivot (posé au sol : il reste au sol).
		if look.scale and math.abs(look.scale - 1) > 1e-3 then
			pcall(function()
				model:ScaleTo(look.scale)
			end)
		end
	end
	return model
end

-- Silhouette noire (espèce non découverte dans le codex).
function MimicModelBuilder.silhouette(speciesId: string): Model
	local model = MimicModelBuilder.build(speciesId)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Color = Color3.fromRGB(20, 18, 30)
			child.Material = Enum.Material.SmoothPlastic
			child.Transparency = 0
		elseif child:IsA("Light") then
			child.Enabled = false
		end
	end
	return model
end

return MimicModelBuilder
