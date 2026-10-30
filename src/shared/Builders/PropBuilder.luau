--!strict
--[[
	PropBuilder — construit les objets ordinaires (et les déguisements).

	Un objet normal et un Mimic déguisé sont construits par la même fonction,
	avec la même variante de couleur : au repos ils sont strictement
	identiques. Seuls les indices (côté client) et la révélation les trahissent.

	Convention : base de l'objet en (0, 0, 0), avant de l'objet vers -Z.
	Attributs de parts utilisés par les animations :
	- Tint  = true : recoloré à la couleur de l'espèce lors de la révélation ;
	- Group = "Lid" | "Flag" : pièces mobiles ;
	- Glow  = true : pièce lumineuse (Neon).
]]

local Geometry = require(script.Parent.Geometry)

export type FaceAnchor = {
	cframe: CFrame, -- centre du « visage » sur la face avant
	eyeSize: number,
	eyeSpacing: number,
	mouth: CFrame, -- position de la bouche
	height: number, -- hauteur totale de l'objet
	hinge: CFrame?, -- charnière des pièces mobiles
}

local PropBuilder = {}

local V = Vector3.new
local C = CFrame.new

local DARK = Color3.fromRGB(46, 44, 58)
local METAL = Color3.fromRGB(150, 156, 170)
local GOLD = Color3.fromRGB(240, 196, 80)

local PALETTES: { [string]: { { number } } } = {
	Chair = { { 168, 116, 74 }, { 84, 164, 164 } },
	TrashCan = { { 82, 132, 100 }, { 112, 124, 146 } },
	Mailbox = { { 64, 106, 196 }, { 196, 70, 70 } },
	Lamp = { { 54, 52, 70 }, { 112, 88, 62 } },
	Chest = { { 138, 88, 50 }, { 100, 64, 42 } },
	Vending = { { 206, 64, 64 }, { 62, 112, 206 }, { 64, 168, 104 } },
}

PropBuilder.FaceAnchors = {
	Chair = { cframe = C(0, 3.55, 0.78), eyeSize = 0.7, eyeSpacing = 0.8, mouth = C(0, 2.75, 0.78), height = 4.6 },
	TrashCan = { cframe = C(0, 2.05, -1.2), eyeSize = 0.75, eyeSpacing = 0.85, mouth = C(0, 1.2, -1.2), height = 3.8 },
	Mailbox = {
		cframe = C(0, 4.0, -1.28),
		eyeSize = 0.55,
		eyeSpacing = 0.62,
		mouth = C(0, 3.45, -1.28),
		height = 5.1,
		hinge = C(0.86, 3.85, 0.7),
	},
	Lamp = { cframe = C(0, 9.5, -0.66), eyeSize = 0.42, eyeSpacing = 0.46, mouth = C(0, 9.02, -0.66), height = 10.9 },
	Chest = {
		cframe = C(0, 0.95, -1.12),
		eyeSize = 0.55,
		eyeSpacing = 0.95,
		mouth = C(0, 1.6, -1.12),
		height = 2.3,
		hinge = C(0, 1.6, 1.15),
	},
	Vending = {
		cframe = C(-0.35, 4.9, -1.36),
		eyeSize = 0.85,
		eyeSpacing = 0.95,
		mouth = C(-0.35, 3.25, -1.36),
		height = 6.6,
	},
} :: { [string]: FaceAnchor }

function PropBuilder.colorFor(kind: string, variant: number?): Color3
	local palette = PALETTES[kind] or { { 200, 200, 200 } }
	local index = ((variant or 1) - 1) % #palette + 1
	return Geometry.rgb(palette[index])
end

local function part(model: Model, props: any): BasePart
	props.Parent = model
	return Geometry.part(props)
end

local function cylinder(model: Model, props: any): BasePart
	props.Parent = model
	return Geometry.cylinder(props)
end

local builders: { [string]: (model: Model, color: Color3) -> BasePart } = {}

builders.Chair = function(model, color)
	local legColor = Geometry.shade(color, 0.75)
	for _, offset in { V(0.9, 0, 0.9), V(-0.9, 0, 0.9), V(0.9, 0, -0.9), V(-0.9, 0, -0.9) } do
		part(model, { Name = "Leg", Size = V(0.3, 1.8, 0.3), CFrame = C(offset.X, 0.9, offset.Z), Color = legColor })
	end
	local body = part(model, { Name = "Body", Size = V(2.2, 0.35, 2.2), CFrame = C(0, 1.975, 0), Color = color })
	body:SetAttribute("Tint", true)
	local back = part(model, { Name = "Back", Size = V(2.2, 2.4, 0.3), CFrame = C(0, 3.35, 0.95), Color = color })
	back:SetAttribute("Tint", true)
	part(model, {
		Name = "BackTrim",
		Size = V(2.3, 0.25, 0.4),
		CFrame = C(0, 4.6, 0.95),
		Color = legColor,
		CanCollide = false,
	})
	return body
end

builders.TrashCan = function(model, color)
	local body = cylinder(model, { Name = "Body", height = 3.2, diameter = 2.4, CFrame = C(0, 1.6, 0), Color = color })
	body:SetAttribute("Tint", true)
	cylinder(model, {
		Name = "Band",
		height = 0.25,
		diameter = 2.5,
		CFrame = C(0, 2.6, 0),
		Color = Geometry.shade(color, 0.7),
		CanCollide = false,
	})
	local lid = cylinder(model, {
		Name = "Lid",
		height = 0.3,
		diameter = 2.7,
		CFrame = C(0, 3.35, 0),
		Color = Geometry.shade(color, 0.85),
		Material = Enum.Material.Metal,
	})
	lid:SetAttribute("Group", "Lid")
	local handle = part(model, {
		Name = "Handle",
		Size = V(0.9, 0.3, 0.3),
		CFrame = C(0, 3.65, 0),
		Color = METAL,
		CanCollide = false,
	})
	handle:SetAttribute("Group", "Lid")
	return body
end

builders.Mailbox = function(model, color)
	part(model, { Name = "Post", Size = V(0.4, 3, 0.4), CFrame = C(0, 1.5, 0), Color = DARK })
	local body = part(model, { Name = "Body", Size = V(1.6, 1.3, 2.4), CFrame = C(0, 3.65, 0), Color = color })
	body:SetAttribute("Tint", true)
	local top = part(model, {
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = V(2.4, 1.6, 1.6),
		CFrame = C(0, 4.3, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
	})
	top:SetAttribute("Tint", true)
	part(model, {
		Name = "Door",
		Size = V(1.45, 1.25, 0.1),
		CFrame = C(0, 3.9, -1.22),
		Color = Geometry.shade(color, 0.8),
		CanCollide = false,
	})
	local pole = part(model, {
		Name = "FlagPole",
		Size = V(0.12, 1.0, 0.12),
		CFrame = C(0.86, 4.3, 0.7),
		Color = DARK,
		CanCollide = false,
	})
	pole:SetAttribute("Group", "Flag")
	local flag = part(model, {
		Name = "Flag",
		Size = V(0.08, 0.45, 0.6),
		CFrame = C(0.86, 4.6, 0.95),
		Color = Color3.fromRGB(235, 70, 70),
		CanCollide = false,
	})
	flag:SetAttribute("Group", "Flag")
	return body
end

builders.Lamp = function(model, color)
	part(model, { Name = "Base", Size = V(1.4, 0.6, 1.4), CFrame = C(0, 0.3, 0), Color = color })
	part(model, { Name = "Pole", Size = V(0.45, 8.2, 0.45), CFrame = C(0, 4.7, 0), Color = color })
	local body = part(model, { Name = "Body", Size = V(1.6, 0.25, 1.6), CFrame = C(0, 8.75, 0), Color = color })
	body:SetAttribute("Tint", true)
	for _, corner in { V(0.66, 0, 0.66), V(-0.66, 0, 0.66), V(0.66, 0, -0.66), V(-0.66, 0, -0.66) } do
		local post = part(model, {
			Name = "Frame",
			Size = V(0.22, 1.4, 0.22),
			CFrame = C(corner.X, 9.5, corner.Z),
			Color = color,
			CanCollide = false,
		})
		post:SetAttribute("Tint", true)
	end
	local glow = part(model, {
		Name = "Glow",
		Size = V(1.2, 1.3, 1.2),
		CFrame = C(0, 9.5, 0),
		Color = Color3.fromRGB(255, 220, 150),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	glow:SetAttribute("Glow", true)
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Shadows = false
	light.Parent = glow
	local cap = part(model, { Name = "Cap", Size = V(1.9, 0.3, 1.9), CFrame = C(0, 10.3, 0), Color = color })
	cap:SetAttribute("Tint", true)
	part(
		model,
		{ Name = "Finial", Size = V(0.4, 0.45, 0.4), CFrame = C(0, 10.67, 0), Color = color, CanCollide = false }
	)
	return body
end

builders.Chest = function(model, color)
	local body = part(model, { Name = "Body", Size = V(3.2, 1.6, 2.2), CFrame = C(0, 0.8, 0), Color = color })
	body:SetAttribute("Tint", true)
	local lid = part(model, {
		Name = "Lid",
		Size = V(3.3, 0.7, 2.3),
		CFrame = C(0, 1.95, 0),
		Color = Geometry.shade(color, 1.1),
	})
	lid:SetAttribute("Group", "Lid")
	lid:SetAttribute("Tint", true)
	for _, x in { 1.1, -1.1 } do
		local band = part(model, {
			Name = "Band",
			Size = V(0.25, 0.7, 2.36),
			CFrame = C(x, 1.95, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
		band:SetAttribute("Group", "Lid")
		part(model, {
			Name = "Band",
			Size = V(0.25, 1.62, 2.26),
			CFrame = C(x, 0.8, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	part(model, {
		Name = "Lock",
		Size = V(0.5, 0.6, 0.15),
		CFrame = C(0, 1.55, -1.17),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	return body
end

builders.Vending = function(model, color)
	local body = part(model, { Name = "Body", Size = V(3.4, 6.6, 2.4), CFrame = C(0, 3.3, 0), Color = color })
	body:SetAttribute("Tint", true)
	local snackColors = { { 255, 210, 80 }, { 120, 220, 120 }, { 255, 120, 150 }, { 140, 180, 255 } }
	for row = 0, 2 do
		for col = 0, 3 do
			local snack = snackColors[(row + col) % #snackColors + 1]
			part(model, {
				Name = "Snack",
				Size = V(0.38, 0.5, 0.06),
				CFrame = C(-1.15 + col * 0.53, 3.1 + row * 1.1, -1.24),
				Color = Geometry.rgb(snack),
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
	part(model, {
		Name = "Glass",
		Size = V(2.3, 3.8, 0.08),
		CFrame = C(-0.35, 4.2, -1.3),
		Color = Color3.fromRGB(190, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		CanCollide = false,
		CastShadow = false,
	})
	local screen = part(model, {
		Name = "Screen",
		Size = V(0.7, 0.5, 0.1),
		CFrame = C(1.2, 5.2, -1.25),
		Color = Color3.fromRGB(120, 255, 230),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	screen:SetAttribute("Glow", true)
	for i = 0, 2 do
		part(model, {
			Name = "Button",
			Size = V(0.25, 0.25, 0.1),
			CFrame = C(1.2, 4.4 - i * 0.4, -1.25),
			Color = Color3.fromRGB(240, 240, 240),
			CanCollide = false,
		})
	end
	part(model, {
		Name = "Slot",
		Size = V(2.2, 0.6, 0.1),
		CFrame = C(-0.35, 1.1, -1.25),
		Color = DARK,
		CanCollide = false,
	})
	local sign = part(model, {
		Name = "Sign",
		Size = V(3.4, 0.7, 0.2),
		CFrame = C(0, 6.25, -1.3),
		Color = Geometry.shade(color, 1.35),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	sign:SetAttribute("Glow", true)
	return body
end

--[[
	Construit un objet du type demandé à l'origine.
	`variant` choisit la couleur (déterminée par l'emplacement, jamais par
	la présence d'un Mimic).
]]
function PropBuilder.build(kind: string, variant: number?): Model
	local builder = builders[kind]
	assert(builder, "PropBuilder : type inconnu " .. tostring(kind))
	local model = Instance.new("Model")
	model.Name = kind
	local body = builder(model, PropBuilder.colorFor(kind, variant))
	model.PrimaryPart = body
	model.WorldPivot = CFrame.identity
	model:SetAttribute("PropKind", kind)
	return model
end

-- Parts d'un groupe mobile (Lid, Flag…).
function PropBuilder.groupParts(model: Model, group: string): { BasePart }
	local out = {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("Group") == group then
			table.insert(out, child)
		end
	end
	return out
end

return PropBuilder
