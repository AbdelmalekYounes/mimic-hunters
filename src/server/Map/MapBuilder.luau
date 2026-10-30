--!strict
--[[
	MapBuilder — génère toute la carte au démarrage du serveur.

	Aucune dépendance à un modèle externe : uniquement des Parts, des
	matériaux Roblox et quelques SurfaceGui pour les panneaux. Les objets
	camouflés reçoivent le tag CollectionService "MimicProp" et les attributs
	PropId / PropKind / Zone / Variant.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geometry = require(Shared.Builders.Geometry)
local PropBuilder = require(Shared.Builders.PropBuilder)
local MapLayout = require(script.Parent.MapLayout)

local V = Vector3.new
local C = CFrame.new
local rgb = Geometry.rgb

local PROP_TAG = "MimicProp"

local MapBuilder = {}

export type PropEntry = { model: Model, spec: MapLayout.PropSpec }

local function vec(point: MapLayout.Point): Vector3
	return V(point.X, point.Y, point.Z)
end

local function origin(position: MapLayout.Point, face: MapLayout.Point?): CFrame
	return Geometry.faceTowards(vec(position), if face then vec(face) else nil)
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, props: any?): BasePart
	local p = (props or {}) :: any
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Parent = parent
	return Geometry.part(p)
end

local function cyl(parent: Instance, cf: CFrame, height: number, diameter: number, color: Color3, props: any?): BasePart
	local p = (props or {}) :: any
	p.CFrame = cf
	p.height = height
	p.diameter = diameter
	p.Color = color
	p.Parent = parent
	return Geometry.cylinder(p)
end

local function ball(parent: Instance, position: Vector3, size: number, color: Color3, props: any?): BasePart
	local p = (props or {}) :: any
	p.Shape = Enum.PartType.Ball
	p.CFrame = CFrame.new(position)
	p.Size = V(size, size, size)
	p.Color = color
	p.Parent = parent
	return Geometry.part(p)
end

local function label(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = part
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Text = text
	text_.TextScaled = true
	text_.Font = Enum.Font.FredokaOne
	text_.TextColor3 = color
	text_.Parent = gui
end

-- ─── Décor ─────────────────────────────────────────────────────────────

local function house(parent: Instance, spec: any)
	local model = Instance.new("Model")
	model.Name = "House"
	model.Parent = parent
	local o = origin(spec.position, spec.face)
	local wall = rgb(spec.color)
	local roof = rgb(spec.roof)
	block(model, o * C(0, 4, 0), V(12, 8, 10), wall)
	-- Toit à deux pans, pignons en escalier (style low-poly).
	for _, side in { -1, 1 } do
		block(model, o * C(side * 3.07, 10.15, 0) * CFrame.Angles(0, 0, math.rad(-side * 35)), V(7.8, 0.6, 11), roof)
	end
	for i, width in { 9.2, 6.4, 3.5 } do
		block(model, o * C(0, 8 + (i - 0.5), 0), V(width, 1, 9.8), Geometry.shade(wall, 0.92))
	end
	block(model, o * C(3.5, 12, 2), V(1.4, 3, 1.4), Geometry.shade(roof, 0.7))
	block(model, o * C(0, 2.1, -5.05), V(2.6, 4.2, 0.3), Color3.fromRGB(120, 80, 54), { CanCollide = false })
	ball(model, (o * C(0.85, 2.1, -5.25)).Position, 0.3, Color3.fromRGB(240, 196, 80), { CanCollide = false })
	block(model, o * C(0, 0.2, -5.8), V(4, 0.4, 1.6), Color3.fromRGB(170, 160, 150))
	for _, x in { -3.6, 3.6 } do
		block(model, o * C(x, 4.8, -5.08), V(2.4, 2.2, 0.2), Color3.fromRGB(255, 226, 160), {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		block(model, o * C(x, 4.8, -5.02), V(2.8, 2.6, 0.2), Color3.fromRGB(250, 250, 250), { CanCollide = false })
	end
	for _, x in { -6.05, 6.05 } do
		block(model, o * C(x, 4.8, 0), V(0.2, 2.2, 2.4), Color3.fromRGB(255, 226, 160), {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function tree(parent: Instance, position: MapLayout.Point, strange: boolean, index: number)
	local model = Instance.new("Model")
	model.Name = if strange then "StrangeTree" else "Tree"
	model.Parent = parent
	local base = vec(position)
	local trunkColor = if strange then Color3.fromRGB(90, 70, 96) else Color3.fromRGB(122, 86, 58)
	local height = 5 + (index % 3)
	if strange then
		-- Tronc tordu : segments décalés.
		for i = 0, 2 do
			local twist = CFrame.Angles(0, math.rad(i * 40 + index * 17), math.rad(if i % 2 == 0 then 8 else -8))
			block(model, CFrame.new(base + V(0, 1 + i * 2, 0)) * twist, V(1.1, 2.2, 1.1), trunkColor)
		end
	else
		cyl(model, CFrame.new(base + V(0, height / 2, 0)), height, 1.1, trunkColor)
	end
	local palette = if strange
		then { Color3.fromRGB(156, 112, 214), Color3.fromRGB(92, 186, 176), Color3.fromRGB(214, 120, 190) }
		else { Color3.fromRGB(96, 170, 84), Color3.fromRGB(120, 190, 96) }
	local leaves = palette[index % #palette + 1]
	local top = base + V(0, height + 2, 0)
	ball(model, top, 6.5, leaves, { Material = Enum.Material.SmoothPlastic })
	ball(model, top + V(2, -0.8, 1), 4.5, Geometry.shade(leaves, 1.1))
	ball(model, top + V(-1.8, -0.5, -1.4), 4.2, Geometry.shade(leaves, 0.9))
	if strange then
		for i = 1, 3 do
			local angle = math.rad(i * 120 + index * 30)
			local fruit = ball(
				model,
				top + V(math.cos(angle) * 3, -2.4, math.sin(angle) * 3),
				0.6,
				Color3.fromRGB(255, 240, 140),
				{ Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
			)
			if i == 1 then
				local light = Instance.new("PointLight")
				light.Range = 10
				light.Brightness = 0.8
				light.Color = Color3.fromRGB(255, 230, 160)
				light.Parent = fruit
			end
		end
	end
end

local function bench(parent: Instance, spec: any)
	local o = origin(spec.position, spec.face)
	local wood = Color3.fromRGB(150, 104, 66)
	local iron = Color3.fromRGB(50, 48, 60)
	block(parent, o * C(0, 1.3, 0), V(5, 0.35, 1.6), wood)
	block(parent, o * C(0, 2.3, 0.75), V(5, 1.3, 0.3), wood)
	for _, x in { -2.1, 2.1 } do
		block(parent, o * C(x, 0.65, 0), V(0.3, 1.3, 1.5), iron)
	end
end

local function picnicTable(parent: Instance, position: MapLayout.Point)
	local base = vec(position)
	cyl(parent, CFrame.new(base + V(0, 2.55, 0)), 0.3, 3.2, Color3.fromRGB(240, 236, 228))
	cyl(parent, CFrame.new(base + V(0, 1.2, 0)), 2.4, 0.4, Color3.fromRGB(60, 58, 70))
end

local function signpost(parent: Instance, spec: any)
	local o = origin(spec.position, spec.face)
	block(parent, o * C(0, 2.5, 0), V(0.4, 5, 0.4), Color3.fromRGB(110, 80, 56))
	local board = block(parent, o * C(0, 4.3, 0), V(7, 1.5, 0.3), Color3.fromRGB(250, 240, 220))
	label(board, Enum.NormalId.Front, spec.text, Color3.fromRGB(70, 50, 90))
	label(board, Enum.NormalId.Back, spec.text, Color3.fromRGB(70, 50, 90))
end

local function fountain(parent: Instance)
	local stone = Color3.fromRGB(200, 196, 210)
	cyl(parent, C(0, 0.6, 0), 1.2, 11, stone, { Material = Enum.Material.Slate })
	cyl(parent, C(0, 1.1, 0), 0.3, 9.6, Color3.fromRGB(110, 190, 240), {
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
	})
	cyl(parent, C(0, 2.6, 0), 3, 1.4, stone, { Material = Enum.Material.Slate })
	cyl(parent, C(0, 4.1, 0), 0.5, 4, stone, { Material = Enum.Material.Slate })
	local orb = ball(parent, V(0, 4.9, 0), 1.2, Color3.fromRGB(170, 230, 255), {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 1
	light.Color = Color3.fromRGB(170, 220, 255)
	light.Parent = orb
end

local function mushroom(parent: Instance, position: MapLayout.Point, index: number)
	local base = vec(position)
	local colors = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 220, 255), Color3.fromRGB(190, 140, 255) }
	local color = colors[index % #colors + 1]
	cyl(parent, CFrame.new(base + V(0, 0.7, 0)), 1.4, 0.5, Color3.fromRGB(245, 240, 230), { CanCollide = false })
	local cap = cyl(parent, CFrame.new(base + V(0, 1.55, 0)), 0.5, 2, color, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 0.9
	light.Color = color
	light.Parent = cap
end

local function rock(parent: Instance, position: MapLayout.Point, index: number)
	local size = V(2.5 + index % 3, 1.6 + (index % 2) * 0.8, 2 + (index * 7) % 3)
	block(
		parent,
		CFrame.new(vec(position) + V(0, size.Y / 2 - 0.2, 0))
			* CFrame.Angles(math.rad(index * 7), math.rad(index * 41), math.rad(index * 5)),
		size,
		Color3.fromRGB(130, 128, 146),
		{ Material = Enum.Material.Slate }
	)
end

local function crystal(parent: Instance, position: MapLayout.Point)
	local part = block(
		parent,
		CFrame.new(vec(position)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		V(1.4, 1.4, 1.4),
		Color3.fromRGB(200, 140, 255),
		{
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}
	)
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(200, 150, 255)
	light.Parent = part
	-- Flottement lent répliqué (3 parts seulement : coût négligeable).
	local tween = TweenService:Create(
		part,
		TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = part.CFrame * C(0, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0) }
	)
	tween:Play()
end

local function arch(parent: Instance, spec: any)
	local o = origin(spec.position, spec.face)
	local stone = Color3.fromRGB(150, 140, 170)
	for _, x in { -4.5, 4.5 } do
		block(parent, o * C(x, 4.5, 0), V(2, 9, 2), stone, { Material = Enum.Material.Slate })
	end
	block(parent, o * C(0, 9.8, 0), V(12, 1.8, 2.2), stone, { Material = Enum.Material.Slate })
	for i = -2, 2 do
		block(parent, o * C(i * 1.8, 9.8, -1.15), V(0.6, 0.6, 0.1), Color3.fromRGB(190, 140, 255), {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function shop(parent: Instance, spec: any)
	local model = Instance.new("Model")
	model.Name = "Shop"
	model.Parent = parent
	local o = origin(spec.position, spec.face)
	local wall = rgb(spec.color)
	local awning = rgb(spec.awning)
	block(model, o * C(0, 4.5, 0), V(16, 9, 10), wall)
	block(model, o * C(0, 9.3, 0), V(16.6, 0.6, 10.6), Geometry.shade(wall, 0.8))
	block(model, o * C(-3, 3.2, -5.06), V(8, 3.6, 0.2), Color3.fromRGB(255, 236, 190), {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	block(model, o * C(4.5, 2.2, -5.06), V(3, 4.4, 0.2), Color3.fromRGB(90, 70, 60), { CanCollide = false })
	for i = 0, 7 do
		block(
			model,
			o * C(-7 + i * 2, 6.3, -6.2) * CFrame.Angles(math.rad(-22), 0, 0),
			V(2, 0.25, 3),
			if i % 2 == 0 then awning else Color3.fromRGB(250, 250, 250),
			{ CanCollide = false }
		)
	end
	local sign = block(model, o * C(0, 8.1, -5.15), V(9, 1.6, 0.3), Color3.fromRGB(40, 34, 56), { CanCollide = false })
	label(sign, Enum.NormalId.Front, spec.name, Color3.fromRGB(255, 240, 200))
end

local function crates(parent: Instance, position: MapLayout.Point, index: number)
	local base = vec(position)
	local wood = Color3.fromRGB(176, 132, 84)
	block(parent, CFrame.new(base + V(0, 1, 0)), V(2, 2, 2), wood, { Material = Enum.Material.WoodPlanks })
	block(parent, CFrame.new(base + V(2.1, 1, 0.3)) * CFrame.Angles(0, math.rad(12), 0), V(2, 2, 2), wood, {
		Material = Enum.Material.WoodPlanks,
	})
	block(parent, CFrame.new(base + V(1, 3, 0.1)) * CFrame.Angles(0, math.rad(index * 23), 0), V(2, 2, 2), wood, {
		Material = Enum.Material.WoodPlanks,
	})
end

local function planter(parent: Instance, position: MapLayout.Point)
	local base = vec(position)
	block(parent, CFrame.new(base + V(0, 0.6, 0)), V(3, 1.2, 3), Color3.fromRGB(200, 190, 180))
	ball(parent, base + V(0, 2, 0), 3, Color3.fromRGB(90, 160, 90))
end

local function kiosk(parent: Instance, position: MapLayout.Point)
	local base = vec(position)
	cyl(parent, CFrame.new(base + V(0, 0.5, 0)), 1, 6, Color3.fromRGB(240, 230, 220))
	for i = 0, 3 do
		local angle = math.rad(i * 90 + 45)
		block(
			parent,
			CFrame.new(base + V(math.cos(angle) * 2.4, 3, math.sin(angle) * 2.4)),
			V(0.3, 4, 0.3),
			Color3.fromRGB(60, 58, 70)
		)
	end
	cyl(parent, CFrame.new(base + V(0, 5.2, 0)), 0.5, 8, Color3.fromRGB(240, 110, 140))
	ball(
		parent,
		base + V(0, 5.8, 0),
		1.2,
		Color3.fromRGB(255, 220, 120),
		{ Material = Enum.Material.Neon, CanCollide = false }
	)
end

-- ─── Sol, chemins, limites ─────────────────────────────────────────────

local function ground(parent: Instance)
	local size = MapLayout.Ground.size
	block(parent, C(0, -1, 0), V(size[1] + 20, 2, size[2] + 20), Color3.fromRGB(118, 176, 96), {
		Name = "Ground",
		Material = Enum.Material.Grass,
	})
	-- Disques de zone (hauteurs différentes pour éviter le z-fighting).
	cyl(
		parent,
		C(-125, 0, 0),
		0.12,
		118,
		Color3.fromRGB(96, 142, 116),
		{ Name = "ParkGround", Material = Enum.Material.Grass }
	)
	cyl(
		parent,
		C(0, 0, 0),
		0.3,
		44,
		Color3.fromRGB(222, 204, 176),
		{ Name = "Plaza", Material = Enum.Material.Cobblestone }
	)
	block(
		parent,
		C(125, 0, 0),
		V(92, 0.3, 82),
		Color3.fromRGB(196, 192, 200),
		{ Name = "MarketFloor", Material = Enum.Material.Pavement }
	)
	-- Routes et chemins.
	local road = Color3.fromRGB(206, 194, 176)
	block(parent, C(0, 0, 0), V(156, 0.2, 9), road, { Name = "MainRoad", Material = Enum.Material.Concrete })
	block(parent, C(0, 0, 0), V(8, 0.2, 124), road, { Name = "VillagePath", Material = Enum.Material.Concrete })
	block(
		parent,
		C(-97, 0.06, 0),
		V(40, 0.12, 6),
		Color3.fromRGB(168, 138, 104),
		{ Name = "ParkPath", Material = Enum.Material.Ground }
	)
	-- Petits chemins vers les maisons.
	for _, spec in MapLayout.Decor.houses do
		local from = vec(spec.position)
		local to = vec(spec.face)
		local mid = (from + to) / 2
		local length = (to - from).Magnitude - 6
		if length > 1 then
			-- Légèrement plus bas que la route principale pour éviter le z-fighting.
			block(parent, Geometry.faceTowards(V(mid.X, 0, mid.Z), to), V(3, 0.16, length), road, {
				Name = "HousePath",
				Material = Enum.Material.Concrete,
			})
		end
	end
	-- Limites : haies visibles et murs invisibles.
	local hx, hz = size[1] / 2, size[2] / 2
	local hedge = Color3.fromRGB(64, 118, 70)
	for _, wall in
		{
			{ C(0, 1.5, -hz), V(size[1], 3, 2) },
			{ C(0, 1.5, hz), V(size[1], 3, 2) },
			{ C(-hx, 1.5, 0), V(2, 3, size[2]) },
			{ C(hx, 1.5, 0), V(2, 3, size[2]) },
		}
	do
		block(parent, wall[1], wall[2], hedge, { Name = "Hedge", Material = Enum.Material.Grass })
		block(parent, wall[1] * C(0, 15, 0), wall[2] + V(0, 30, 0), hedge, {
			Name = "InvisibleWall",
			Transparency = 1,
			CastShadow = false,
		})
	end
	-- Étang du parc.
	local pond = MapLayout.Decor.pond
	cyl(parent, CFrame.new(vec(pond.center) + V(0, 0.12, 0)), 0.25, pond.radius * 2, Color3.fromRGB(100, 170, 220), {
		Name = "Pond",
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		CanCollide = false,
	})
	for i = 0, 9 do
		local angle = math.rad(i * 36)
		local r = pond.radius + 0.6
		block(
			parent,
			CFrame.new(vec(pond.center) + V(math.cos(angle) * r, 0.3, math.sin(angle) * r))
				* CFrame.Angles(0, -angle, 0),
			V(1.4, 0.6, 5.6),
			Color3.fromRGB(150, 148, 160),
			{ Material = Enum.Material.Slate }
		)
	end
end

local function spawnLocation(parent: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HunterSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = V(6, 0.4, 6)
	spawn.Color = Color3.fromRGB(170, 230, 210)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.CFrame = Geometry.faceTowards(vec(MapLayout.Spawn.position) + V(0, 0.2, 0), vec(MapLayout.Spawn.face))
	spawn.Parent = parent
end

-- ─── Construction ──────────────────────────────────────────────────────

function MapBuilder.build(): { [string]: PropEntry }
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = folder("Map", Workspace)
	local terrain = folder("Ground", map)
	local village = folder("Village", map)
	local park = folder("Park", map)
	local market = folder("Market", map)
	local propsFolder = folder("Props", map)

	ground(terrain)
	spawnLocation(map)
	fountain(village)

	local decor = MapLayout.Decor
	for _, spec in decor.houses do
		house(village, spec)
	end
	for i, position in decor.villageTrees do
		tree(village, position, false, i)
	end
	for _, spec in decor.benches do
		bench(if spec.position.X < -60 then park elseif spec.position.X > 60 then market else village, spec)
	end
	for _, position in decor.tables do
		picnicTable(if position.X < -60 then park elseif position.X > 60 then market else village, position)
	end
	for _, spec in decor.signposts do
		signpost(village, spec)
	end
	for i, position in decor.parkTrees do
		tree(park, position, true, i)
	end
	for i, position in decor.mushrooms do
		mushroom(park, position, i)
	end
	for i, position in decor.rocks do
		rock(park, position, i)
	end
	arch(park, decor.arch)
	for _, position in decor.crystals do
		crystal(park, position)
	end
	for _, spec in decor.shops do
		shop(market, spec)
	end
	for i, position in decor.crates do
		crates(market, position, i)
	end
	for _, position in decor.planters do
		planter(market, position)
	end
	kiosk(market, decor.kiosk.position)

	local registry: { [string]: PropEntry } = {}
	for _, spec in MapLayout.allProps() do
		local model = PropBuilder.build(spec.kind, spec.variant)
		model.Name = spec.id
		model:SetAttribute("PropId", spec.id)
		model:SetAttribute("Zone", spec.zone)
		model:SetAttribute("Variant", spec.variant)
		model:PivotTo(origin(spec.position, spec.face))
		model.Parent = propsFolder
		CollectionService:AddTag(model, PROP_TAG)
		registry[spec.id] = { model = model, spec = spec }
	end
	return registry
end

MapBuilder.PropTag = PROP_TAG

return MapBuilder
