--!strict
--[[
	MapLayout — description déclarative de la carte V0.1.

	Données pures (aucune Instance) : la carte est construite par MapBuilder
	et validée par les tests Lune. Le sol est à Y = 0. Les positions sont la
	base (centre au sol) de chaque objet. `face` est le point que l'avant de
	l'objet regarde.

	Repères : Village Central en (0, 0), Parc Étrange à l'ouest (x < 0),
	Zone Commerciale à l'est (x > 0).
]]

export type Point = { X: number, Y: number, Z: number }

export type PropSpec = {
	id: string,
	kind: string,
	zone: string,
	position: Point,
	face: Point?,
	variant: number,
}

local function p(x: number, z: number): Point
	return { X = x, Y = 0, Z = z }
end

local MapLayout = {}

MapLayout.Zones = {
	{ id = "Village", displayName = "Village Central", center = p(0, 0), radius = 62 },
	{ id = "Park", displayName = "Parc Étrange", center = p(-125, 0), radius = 60 },
	{ id = "Market", displayName = "Zone Commerciale", center = p(125, 0), radius = 62 },
}

MapLayout.Spawn = { position = p(0, 8), face = p(0, 30) }

MapLayout.Ground = { size = { 400, 160 } }

-- Objet du tutoriel : une chaise juste devant le point d'apparition.
MapLayout.TutorialProp = {
	id = "TUTO",
	kind = "Chair",
	zone = "Village",
	position = p(-2, 18),
	face = p(0, 8),
	variant = 1,
} :: PropSpec

-- Les 40 objets pouvant abriter un Mimic.
MapLayout.Props = {
	-- Village Central (16)
	{ id = "V01", kind = "Chair", zone = "Village", position = p(6.5, -12), face = p(9, -12), variant = 1 },
	{ id = "V02", kind = "Chair", zone = "Village", position = p(11.5, -12), face = p(9, -12), variant = 1 },
	{ id = "V03", kind = "Chair", zone = "Village", position = p(-12, -3), face = p(0, 0), variant = 2 },
	{ id = "V04", kind = "TrashCan", zone = "Village", position = p(16, 5), face = p(0, 0), variant = 1 },
	{ id = "V05", kind = "TrashCan", zone = "Village", position = p(-16, -5), face = p(0, 0), variant = 1 },
	{ id = "V06", kind = "TrashCan", zone = "Village", position = p(7, 20), face = p(0, 20), variant = 2 },
	{ id = "V07", kind = "TrashCan", zone = "Village", position = p(-30, 7), face = p(-30, 0), variant = 2 },
	{ id = "V08", kind = "Mailbox", zone = "Village", position = p(-33, -14), face = p(-33, 0), variant = 1 },
	{ id = "V09", kind = "Mailbox", zone = "Village", position = p(-33, 14), face = p(-33, 0), variant = 2 },
	{ id = "V10", kind = "Mailbox", zone = "Village", position = p(33, -14), face = p(33, 0), variant = 2 },
	{ id = "V11", kind = "Mailbox", zone = "Village", position = p(33, 14), face = p(33, 0), variant = 1 },
	{ id = "V12", kind = "Mailbox", zone = "Village", position = p(-7, -40), face = p(0, -40), variant = 1 },
	{ id = "V13", kind = "Lamp", zone = "Village", position = p(15, 15), face = p(0, 0), variant = 1 },
	{ id = "V14", kind = "Lamp", zone = "Village", position = p(-15, 15), face = p(0, 0), variant = 1 },
	{ id = "V15", kind = "Lamp", zone = "Village", position = p(15, -15), face = p(0, 0), variant = 1 },
	{ id = "V16", kind = "Lamp", zone = "Village", position = p(-15, -15), face = p(0, 0), variant = 1 },

	-- Parc Étrange (11)
	{ id = "P01", kind = "Chair", zone = "Park", position = p(-106, -14.5), face = p(-106, -18), variant = 2 },
	{ id = "P02", kind = "Chair", zone = "Park", position = p(-106, -21.5), face = p(-106, -18), variant = 2 },
	{ id = "P03", kind = "Chair", zone = "Park", position = p(-140, 20), face = p(-125, 0), variant = 1 },
	{ id = "P04", kind = "TrashCan", zone = "Park", position = p(-95, 6), face = p(-95, 0), variant = 1 },
	{ id = "P05", kind = "TrashCan", zone = "Park", position = p(-130, -25), face = p(-125, -5), variant = 2 },
	{ id = "P06", kind = "Lamp", zone = "Park", position = p(-100, -5), face = p(-100, 0), variant = 2 },
	{ id = "P07", kind = "Lamp", zone = "Park", position = p(-125, 12), face = p(-125, 0), variant = 2 },
	{ id = "P08", kind = "Lamp", zone = "Park", position = p(-150, -8), face = p(-125, -5), variant = 2 },
	{ id = "P09", kind = "Chest", zone = "Park", position = p(-135, -35), face = p(-125, -5), variant = 1 },
	{ id = "P10", kind = "Chest", zone = "Park", position = p(-155, 25), face = p(-125, 0), variant = 2 },
	{ id = "P11", kind = "Chest", zone = "Park", position = p(-115, 35), face = p(-115, 0), variant = 1 },

	-- Zone Commerciale (13)
	{ id = "C01", kind = "Chair", zone = "Market", position = p(104.5, 17), face = p(107, 17), variant = 1 },
	{ id = "C02", kind = "Chair", zone = "Market", position = p(109.5, 17), face = p(107, 17), variant = 1 },
	{ id = "C03", kind = "TrashCan", zone = "Market", position = p(100, -8), face = p(100, 0), variant = 1 },
	{ id = "C04", kind = "TrashCan", zone = "Market", position = p(142, 8), face = p(142, 0), variant = 2 },
	{ id = "C05", kind = "Vending", zone = "Market", position = p(112, -25), face = p(112, 0), variant = 1 },
	{ id = "C06", kind = "Vending", zone = "Market", position = p(130, -25), face = p(130, 0), variant = 2 },
	{ id = "C07", kind = "Vending", zone = "Market", position = p(134.5, -25), face = p(134.5, 0), variant = 3 },
	{ id = "C08", kind = "Vending", zone = "Market", position = p(130, 25), face = p(130, 0), variant = 1 },
	{ id = "C09", kind = "Vending", zone = "Market", position = p(158, 0), face = p(125, 0), variant = 2 },
	{ id = "C10", kind = "Chest", zone = "Market", position = p(148, -18), face = p(125, 0), variant = 2 },
	{ id = "C11", kind = "Chest", zone = "Market", position = p(148, 20), face = p(125, 0), variant = 1 },
	{ id = "C12", kind = "Mailbox", zone = "Market", position = p(92, 10), face = p(92, 0), variant = 2 },
	{ id = "C13", kind = "Mailbox", zone = "Market", position = p(120, -14), face = p(120, 0), variant = 1 },
} :: { PropSpec }

-- Décor non interactif (ne cache jamais de Mimic).
MapLayout.Decor = {
	houses = {
		{ position = p(-38, -30), face = p(-38, 0), color = { 255, 214, 186 }, roof = { 196, 84, 84 } },
		{ position = p(-38, 30), face = p(-38, 0), color = { 206, 232, 255 }, roof = { 80, 110, 190 } },
		{ position = p(38, -30), face = p(38, 0), color = { 220, 250, 210 }, roof = { 70, 150, 110 } },
		{ position = p(38, 30), face = p(38, 0), color = { 255, 240, 190 }, roof = { 210, 130, 60 } },
		{ position = p(-17, -50), face = p(0, -50), color = { 240, 214, 255 }, roof = { 140, 90, 190 } },
		{ position = p(17, 48), face = p(0, 48), color = { 255, 220, 230 }, roof = { 200, 90, 130 } },
	},
	villageTrees = { p(-50, -8), p(50, 8), p(-26, -44), p(26, 38), p(-55, 45), p(55, -45), p(-52, 20), p(52, -18) },
	benches = {
		{ position = p(0, -17), face = p(0, 0) },
		{ position = p(-18, 4), face = p(0, 0) },
		{ position = p(18, -4), face = p(0, 0) },
		{ position = p(-115, -8), face = p(-125, -5) },
		{ position = p(-135, 3), face = p(-125, -5) },
		{ position = p(118, 6), face = p(125, 0) },
	},
	tables = { p(9, -12), p(-106, -18), p(107, 17) },
	signposts = {
		{ position = p(-27, -7), face = p(-27, 0), text = "< Parc Étrange" },
		{ position = p(27, 7), face = p(27, 0), text = "Zone Commerciale >" },
		{ position = p(-72, -7), face = p(-72, 0), text = "Parc Étrange" },
		{ position = p(76, 7), face = p(76, 0), text = "Zone Commerciale" },
	},
	parkTrees = {
		p(-90, -25),
		p(-95, 28),
		p(-104, 24),
		p(-140, 42),
		p(-163, 8),
		p(-165, -20),
		p(-150, -32),
		p(-120, -42),
		p(-84, 14),
		p(-128, 40),
		p(-170, 32),
		p(-100, -40),
	},
	mushrooms = { p(-118, 20), p(-145, -15), p(-100, 16), p(-160, -5), p(-132, -21), p(-110, 44), p(-158, 38) },
	rocks = { p(-112, -30), p(-152, 12), p(-131, -12), p(-88, -10), p(-170, -36) },
	pond = { center = p(-125, -5), radius = 9 },
	arch = { position = p(-172, 0), face = p(-125, 0) },
	crystals = { { X = -125, Y = 7, Z = -5 }, { X = -172, Y = 5, Z = 0 }, { X = -96, Y = 4, Z = -32 } },
	shops = {
		{
			position = p(100, -35),
			face = p(100, 0),
			name = "SNACKS",
			color = { 255, 196, 120 },
			awning = { 230, 80, 80 },
		},
		{
			position = p(122, -35),
			face = p(122, 0),
			name = "GADGETS",
			color = { 170, 220, 255 },
			awning = { 60, 120, 220 },
		},
		{
			position = p(146, -35),
			face = p(146, 0),
			name = "BRIC-À-BRAC",
			color = { 220, 255, 190 },
			awning = { 80, 170, 90 },
		},
		{
			position = p(104, 35),
			face = p(104, 0),
			name = "JOUETS",
			color = { 255, 210, 240 },
			awning = { 220, 90, 170 },
		},
		{
			position = p(146, 35),
			face = p(146, 0),
			name = "BOUTIQUE",
			color = { 240, 230, 255 },
			awning = { 140, 100, 220 },
		},
	},
	crates = { p(155, -22), p(156, 24), p(88, -24), p(122, 30) },
	planters = { p(88, -14), p(88, 18), p(160, -10), p(160, 12) },
	kiosk = { position = p(125, 0) },
}

function MapLayout.allProps(): { PropSpec }
	local out = table.clone(MapLayout.Props)
	table.insert(out, MapLayout.TutorialProp)
	return out
end

function MapLayout.zoneIds(): { string }
	local out = {}
	for _, zone in MapLayout.Zones do
		table.insert(out, zone.id)
	end
	return out
end

return MapLayout
