--!strict
--[[
	MuseumBuilder — géométrie du Quartier des collectionneurs et des musées (Parts uniquement).

	Style cute-creepy, coloré, un peu futuriste : murs pastel ou nuit, liserés néon, lanternes,
	vitrines de verre. Budget par musée (voir ARCHITECTURE.md) : ~70 Parts pour le bâtiment,
	2 PointLights, aucune particule ; les Mimics exposés s'ajoutent (≤ 6).

	Le bâtiment est construit une fois au démarrage pour les 8 parcelles (« Parcelle libre »).
	Le rendu d'un propriétaire ne modifie que : nom, panneau, couleurs/matériaux (styles),
	socles et Mimics exposés. Les vitrines restent pleines (CanCollide) : un Mimic exposé ne
	peut pas quitter son socle, et personne ne peut entrer dans la vitrine.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geometry = require(Shared.Builders.Geometry)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local MuseumStyles = require(Shared.Config.MuseumStyles)
local SpecimenLook = require(Shared.Logic.SpecimenLook)

local MuseumLayout = require(script.Parent.MuseumLayout)

local V = Vector3.new
local C = CFrame.new

-- Les Mimics exposés sont un peu réduits pour tenir dans les vitrines.
local EXHIBIT_SCALE = 0.8
local PEDESTAL_HEIGHT = 1.6

export type PlotRefs = {
	index: number,
	model: Model,
	frame: CFrame,
	walls: { BasePart },
	floor: BasePart,
	trims: { BasePart },
	lights: { PointLight },
	pedestals: { BasePart },
	slotLabels: { TextLabel },
	nameLabel: TextLabel,
	boardLabel: TextLabel,
	exhibits: Folder,
	hunt: Folder,
	sign: BasePart,
}

local MuseumBuilder = {}

local function part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, props: any?): BasePart
	local p = (props or {}) :: any
	p.Name = name
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Parent = parent
	return Geometry.part(p)
end

local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3, ppm: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppm or 40
	gui.LightInfluence = 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Parent = gui
	return label
end

function MuseumBuilder.plotFrame(index: number): CFrame
	local plot = MuseumLayout.Plots[index]
	return C(plot.center.X, 0, plot.center.Z) * CFrame.Angles(0, plot.yaw, 0)
end

-- Point local (MuseumLayout) → CFrame monde à la hauteur `y`, orienté comme la parcelle.
function MuseumBuilder.localCFrame(index: number, point: MuseumLayout.Point, y: number?): CFrame
	return MuseumBuilder.plotFrame(index) * C(point.X, y or 0, point.Z)
end

-- ─── Quartier ──────────────────────────────────────────────────────────

local function lantern(parent: Instance, position: Vector3, color: Color3)
	part(parent, "LanternPole", C(position + V(0, 3, 0)), V(0.5, 6, 0.5), Color3.fromRGB(50, 40, 70))
	local bulb = part(parent, "LanternBulb", C(position + V(0, 6.4, 0)), V(1.2, 1.2, 1.2), color, {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = bulb
end

function MuseumBuilder.buildDistrict(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "District"
	folder.Parent = parent
	local g = MuseumLayout.Ground
	part(
		folder,
		"DistrictGround",
		C((g.minX + g.maxX) / 2, -0.5, (g.minZ + g.maxZ) / 2),
		V(g.maxX - g.minX, 1, g.maxZ - g.minZ),
		Color3.fromRGB(96, 150, 110),
		{ Material = Enum.Material.Grass }
	)
	-- Rue des musées (est-ouest) et avenue jusqu'au Village.
	part(
		folder,
		"Street",
		C(0, 0.02, MuseumLayout.StreetZ),
		V(g.maxX - g.minX, 0.1, 14),
		Color3.fromRGB(176, 150, 196),
		{ Material = Enum.Material.Cobblestone }
	)
	local a = MuseumLayout.Avenue
	part(
		folder,
		"Avenue",
		C(0, 0.03, (a.minZ + a.maxZ) / 2),
		V(a.maxX - a.minX, 0.1, a.maxZ - a.minZ),
		Color3.fromRGB(176, 150, 196),
		{ Material = Enum.Material.Cobblestone }
	)
	-- Arche d'entrée du quartier.
	local archZ = g.minZ - 2
	for _, x in { -5.5, 5.5 } do
		part(folder, "ArchPillar", C(x, 4, archZ), V(1.4, 8, 1.4), Color3.fromRGB(70, 56, 110))
	end
	local beam = part(folder, "ArchBeam", C(0, 8.6, archZ), V(13, 1.6, 1.4), Color3.fromRGB(70, 56, 110))
	surfaceText(beam, Enum.NormalId.Back, "QUARTIER DES COLLECTIONNEURS", Color3.fromRGB(255, 200, 235), 24)
	surfaceText(beam, Enum.NormalId.Front, "VILLAGE", Color3.fromRGB(255, 200, 235), 24)
	for i, x in { -70, -41, -3.5, 3.5, 41, 70 } do
		local color = if i % 2 == 0 then Color3.fromRGB(255, 150, 210) else Color3.fromRGB(140, 230, 255)
		lantern(folder, V(x, 0, MuseumLayout.StreetZ - 7.5), color)
	end
	return folder
end

-- ─── Musée d'une parcelle ──────────────────────────────────────────────

local function pedestal(parent: Instance, index: number, slot: number): BasePart
	local point = MuseumLayout.Pedestals[slot]
	local cf = MuseumBuilder.localCFrame(index, point, PEDESTAL_HEIGHT / 2)
	local base = part(parent, "Pedestal" .. slot, cf, V(3.6, PEDESTAL_HEIGHT, 3.6), Color3.fromRGB(214, 206, 230), {
		Material = Enum.Material.Marble,
	})
	base:SetAttribute("Slot", slot)
	-- Liseré lumineux autour du socle (couleur selon le style).
	part(
		parent,
		"PedestalRim" .. slot,
		cf * C(0, PEDESTAL_HEIGHT / 2, 0),
		V(3.8, 0.12, 3.8),
		Color3.fromRGB(255, 150, 210),
		{
			Material = Enum.Material.Neon,
			CastShadow = false,
			CanCollide = false,
		}
	):SetAttribute("Rim", slot)
	return base
end

--[[
	Construit le musée vide d'une parcelle. Retourne les références utilisées par le rendu.
]]
function MuseumBuilder.buildPlot(index: number, parent: Instance): PlotRefs
	local model = Instance.new("Model")
	model.Name = "Museum" .. index
	model:SetAttribute("PlotIndex", index)
	local frame = MuseumBuilder.plotFrame(index)
	local room = MuseumLayout.Room
	local width, depth = room.maxX - room.minX, room.maxZ - room.minZ
	local midZ = (room.minZ + room.maxZ) / 2
	local wallColor = Color3.fromRGB(150, 120, 200)
	local h = room.wallHeight

	local floor = part(model, "Floor", frame * C(0, 0.1, midZ), V(width, 0.2, depth), Color3.fromRGB(60, 48, 84), {
		Material = Enum.Material.Slate,
	})
	local walls, trims = {}, {}
	local function wall(name: string, cf: CFrame, size: Vector3)
		table.insert(walls, part(model, name, cf, size, wallColor, { Material = Enum.Material.SmoothPlastic }))
	end
	wall("WallBack", frame * C(0, h / 2, room.maxZ), V(width, h, 1))
	wall("WallLeft", frame * C(room.minX, h / 2, midZ), V(1, h, depth))
	wall("WallRight", frame * C(room.maxX, h / 2, midZ), V(1, h, depth))
	-- Mur avant en deux morceaux autour de la porte, et linteau.
	local door = room.door
	local side = (width - door * 2) / 2
	wall("WallFrontL", frame * C(room.minX + side / 2, h / 2, room.minZ), V(side, h, 1))
	wall("WallFrontR", frame * C(room.maxX - side / 2, h / 2, room.minZ), V(side, h, 1))
	wall("Lintel", frame * C(0, h - 1.5, room.minZ), V(door * 2, 3, 1))
	-- Liserés néon en haut des murs.
	for _, spec in
		{
			{ C(0, h + 0.15, room.maxZ), V(width + 1, 0.3, 1.2) },
			{ C(room.minX, h + 0.15, midZ), V(1.2, 0.3, depth) },
			{ C(room.maxX, h + 0.15, midZ), V(1.2, 0.3, depth) },
			{ C(0, h + 0.15, room.minZ), V(width + 1, 0.3, 1.2) },
		}
	do
		table.insert(
			trims,
			part(model, "Trim", frame * spec[1], spec[2], Color3.fromRGB(255, 120, 186), {
				Material = Enum.Material.Neon,
				CastShadow = false,
			})
		)
	end
	-- Enseigne au-dessus de l'entrée (nom du propriétaire).
	local plate =
		part(model, "NamePlate", frame * C(0, h + 1.6, room.minZ - 0.4), V(14, 2.4, 0.4), Color3.fromRGB(40, 30, 64))
	local nameLabel = surfaceText(plate, Enum.NormalId.Front, "Parcelle libre", Color3.fromRGB(255, 220, 245), 30)

	-- Deux lanternes de plafond (ambiance lumineuse).
	local lights = {}
	for _, x in { -6, 6 } do
		local lamp =
			part(model, "CeilingLamp", frame * C(x, h - 1.2, midZ), V(1.4, 1.4, 1.4), Color3.fromRGB(255, 220, 240), {
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.Neon,
				CastShadow = false,
				CanCollide = false,
			})
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = lamp
		table.insert(lights, light)
	end

	-- Six socles numérotés, avec leur plaque « Libre / numéro ».
	local pedestals, slotLabels = {}, {}
	for slot = 1, #MuseumLayout.Pedestals do
		local base = pedestal(model, index, slot)
		table.insert(pedestals, base)
		local point = MuseumLayout.Pedestals[slot]
		local tag = part(
			model,
			"SlotTag" .. slot,
			MuseumBuilder.localCFrame(index, { X = point.X, Y = 0, Z = point.Z - 1.95 }, 0.55),
			V(2.4, 0.7, 0.15),
			Color3.fromRGB(30, 24, 48),
			{ CanCollide = false }
		)
		table.insert(
			slotLabels,
			surfaceText(tag, Enum.NormalId.Front, tostring(slot), Color3.fromRGB(200, 190, 230), 40)
		)
	end

	-- Panneau des statistiques de la collection (mur du fond).
	local board = part(
		model,
		"StatsBoard",
		MuseumBuilder.localCFrame(index, MuseumLayout.Board, 7.4),
		V(12, 4, 0.3),
		Color3.fromRGB(30, 24, 48)
	)
	local boardLabel = surfaceText(board, Enum.NormalId.Front, "", Color3.fromRGB(230, 220, 255), 30)

	-- Emplacement des futures améliorations (salle suivante, à venir).
	local upgrade = part(
		model,
		"UpgradeSpot",
		MuseumBuilder.localCFrame(index, MuseumLayout.UpgradeSpot, 0.15),
		V(3, 0.3, 4),
		Color3.fromRGB(80, 64, 120),
		{ Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false }
	)
	local upgradeSign =
		part(model, "UpgradeSign", upgrade.CFrame * C(0, 1.4, 0), V(2.8, 1, 0.2), Color3.fromRGB(30, 24, 48), {
			CanCollide = false,
		})
	surfaceText(upgradeSign, Enum.NormalId.Front, "Bientôt : nouvelle salle", Color3.fromRGB(200, 190, 230), 30)

	-- Jardin de la Museum Hunt : bordure, repères des cachettes et panneau du défi.
	for i, spot in MuseumLayout.HuntSpots do
		part(
			model,
			"HuntSpot" .. i,
			MuseumBuilder.localCFrame(index, spot, 0.06),
			V(3.2, 0.12, 3.2),
			Color3.fromRGB(120, 96, 150),
			{
				Material = Enum.Material.Cobblestone,
				CanCollide = false,
			}
		)
	end
	local sign = part(
		model,
		"HuntSign",
		MuseumBuilder.localCFrame(index, MuseumLayout.HuntSign, 2.4),
		V(4.4, 2.2, 0.4),
		Color3.fromRGB(70, 40, 100)
	)
	part(
		model,
		"HuntSignPole",
		MuseumBuilder.localCFrame(index, MuseumLayout.HuntSign, 0.7),
		V(0.4, 1.4, 0.4),
		Color3.fromRGB(50, 40, 70)
	)
	surfaceText(
		sign,
		Enum.NormalId.Front,
		"MUSEUM HUNT\nTrouve les Mimics cachés !",
		Color3.fromRGB(255, 220, 120),
		26
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HuntPrompt"
	prompt.ActionText = "Lancer le défi"
	prompt.ObjectText = "Museum Hunt"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PlotIndex", index)
	prompt.Parent = sign

	local exhibits = Instance.new("Folder")
	exhibits.Name = "Exhibits"
	exhibits.Parent = model
	local hunt = Instance.new("Folder")
	hunt.Name = "Hunt"
	hunt.Parent = model
	model.PrimaryPart = floor
	model.Parent = parent
	CollectionService:AddTag(model, "Museum")

	return {
		index = index,
		model = model,
		frame = frame,
		walls = walls,
		floor = floor,
		trims = trims,
		lights = lights,
		pedestals = pedestals,
		slotLabels = slotLabels,
		nameLabel = nameLabel,
		boardLabel = boardLabel,
		exhibits = exhibits,
		hunt = hunt,
		sign = sign,
	}
end

-- ─── Rendu d'un propriétaire ───────────────────────────────────────────

local function material(name: string?): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or "SmoothPlastic"]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

-- Couleurs, matériaux et lumières (styles du musée), en place : aucune reconstruction.
function MuseumBuilder.applyStyles(refs: PlotRefs, styles: any)
	local wall = MuseumStyles.resolve("wall", styles and styles.wall)
	local lighting = MuseumStyles.resolve("lighting", styles and styles.lighting)
	local pedestalStyle = MuseumStyles.resolve("pedestal", styles and styles.pedestal)
	local theme = MuseumStyles.resolve("theme", styles and styles.theme)
	for _, w in refs.walls do
		w.Color = Geometry.rgb(wall.color)
	end
	for _, t in refs.trims do
		t.Color = Geometry.rgb(theme.accent or wall.color)
	end
	refs.floor.Color = Geometry.rgb(theme.color)
	refs.floor.Material = material(theme.material)
	for _, light in refs.lights do
		light.Color = Geometry.rgb(lighting.color)
		light.Brightness = lighting.brightness or 1.4
		local lamp = light.Parent :: BasePart
		lamp.Color = Geometry.rgb(lighting.color)
	end
	for slot, base in refs.pedestals do
		base.Color = Geometry.rgb(pedestalStyle.color)
		base.Material = material(pedestalStyle.material)
		base.Transparency = if pedestalStyle.material == "Glass" then 0.25 else 0
		local rim = refs.model:FindFirstChild("PedestalRim" .. slot) :: BasePart?
		if rim then
			rim.Color = Geometry.rgb(pedestalStyle.accent or pedestalStyle.color)
		end
	end
	refs.model:SetAttribute("Styles", string.format("%s/%s/%s/%s", wall.id, lighting.id, pedestalStyle.id, theme.id))
end

function MuseumBuilder.setOwner(refs: PlotRefs, ownerName: string?, ownerUserId: number?)
	refs.nameLabel.Text = if ownerName then "Musée de " .. ownerName else "Parcelle libre"
	refs.model:SetAttribute("OwnerUserId", ownerUserId)
	refs.model:SetAttribute("OwnerName", ownerName)
end

function MuseumBuilder.setBoard(refs: PlotRefs, text: string)
	refs.boardLabel.Text = text
end

function MuseumBuilder.clearExhibits(refs: PlotRefs)
	refs.exhibits:ClearAllChildren()
	for slot, label in refs.slotLabels do
		label.Text = tostring(slot)
		label.TextColor3 = Color3.fromRGB(200, 190, 230)
	end
end

--[[
	Expose les exemplaires (vues envoyées par le serveur : id, speciesId, rarity, mutation,
	seed). `slots[i]` = exemplaire ou false. Chaque Mimic garde son apparence exacte
	(SpecimenLook : couleurs, taille, mutation) ; le modèle n'est qu'une représentation :
	l'exemplaire reste dans la collection du propriétaire.
]]
function MuseumBuilder.renderExhibits(refs: PlotRefs, slots: { any }, ownerName: string, ownerUserId: number)
	MuseumBuilder.clearExhibits(refs)
	for slot, specimen in slots do
		local base = refs.pedestals[slot]
		local species = specimen and MimicCatalog.get(specimen.speciesId)
		-- Vitrine vide (false) ou espèce disparue : rien à poser.
		if base == nil or not species then
			continue
		end
		local look = SpecimenLook.compute(species, specimen.seed, specimen.mutation)
		local model = MimicModelBuilder.build(species.id, nil, look)
		model.Name = "Exhibit" .. slot
		pcall(function()
			model:ScaleTo(model:GetScale() * EXHIBIT_SCALE)
		end)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
		end
		-- Posé sur le socle, tourné vers l'entrée (l'avant des modèles est -Z, comme la parcelle).
		local top = base.CFrame * C(0, base.Size.Y / 2, 0)
		model:PivotTo(top)
		model:SetAttribute("Exhibit", true)
		model:SetAttribute("Slot", slot)
		model:SetAttribute("SpecimenId", specimen.id)
		model:SetAttribute("SpeciesId", species.id)
		model:SetAttribute("Rarity", specimen.rarity)
		model:SetAttribute("Mutation", specimen.mutation)
		model:SetAttribute("Seed", specimen.seed)
		model:SetAttribute("Scale", look.scale)
		model:SetAttribute("OwnerName", ownerName)
		model:SetAttribute("OwnerUserId", ownerUserId)
		model:SetAttribute("PlotIndex", refs.index)
		model.Parent = refs.exhibits
		CollectionService:AddTag(model, "MuseumExhibit")

		-- Vitrine de verre ajustée au Mimic : il ne peut pas en sortir.
		local _, size = model:GetBoundingBox()
		local case = part(
			refs.exhibits,
			"Case" .. slot,
			top * C(0, size.Y / 2 + 0.3, 0),
			V(3.4, size.Y + 0.6, 3.4),
			Color3.fromRGB(200, 230, 255),
			{ Material = Enum.Material.Glass, Transparency = 0.82, CastShadow = false }
		)
		case:SetAttribute("Case", slot)
		-- Examiner : invite de proximité (PC, mobile, manette), traitée côté client.
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "InspectPrompt"
		prompt.ActionText = "Examiner"
		prompt.ObjectText = species.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt:SetAttribute("Slot", slot)
		prompt:SetAttribute("PlotIndex", refs.index)
		prompt.Parent = case
		local label = refs.slotLabels[slot]
		label.Text = string.format("%d · %s", slot, species.name)
		label.TextColor3 = Color3.fromRGB(255, 230, 250)
	end
end

return MuseumBuilder
