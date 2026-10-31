--!strict
--[[
	MuseumLayout — plan du Quartier des collectionneurs (données pures, testées dans Lune).

	Le quartier est au nord du Village (z > 80), relié par une avenue centrale. Huit parcelles
	de 36 × 32 studs bordent une rue est-ouest (z = 128) : 4 au sud, 4 au nord, tournées vers
	la rue. Distance du point d'apparition à la rue : ~120 studs (≈ 7 s à pied), et les
	boutons MA BASE / VILLAGE téléportent.

	Coordonnées LOCALES d'une parcelle : x vers la droite, z vers le fond ; l'avant (rue) est
	en z négatif. Musée : salle de 26 × 18 (z de -4 à 14), entrée au centre du mur avant.
	Devant : le jardin de la Museum Hunt (8 cachettes) et son panneau.
]]

export type Point = { X: number, Y: number, Z: number }

export type Plot = {
	index: number,
	center: Point,
	-- 0 ou math.pi : rotation autour de Y pour que l'avant local (-Z) regarde la rue.
	yaw: number,
}

local function p(x: number, z: number): Point
	return { X = x, Y = 0, Z = z }
end

local MuseumLayout = {}

MuseumLayout.PlotCount = 8
MuseumLayout.PlotSize = { width = 36, depth = 32 }
MuseumLayout.StreetZ = 128
-- Sol du quartier et avenue qui le relie au Village.
MuseumLayout.Ground = { minX = -80, maxX = 80, minZ = 84, maxZ = 172 }
MuseumLayout.Avenue = { minX = -4, maxX = 4, minZ = 60, maxZ = 136 }

local plots: { Plot } = {}
for i, x in { -60, -22, 22, 60 } do
	-- Rangée sud : la rue est au nord (+Z) → rotation de 180°.
	table.insert(plots, { index = i, center = p(x, 104), yaw = math.pi })
end
for i, x in { -60, -22, 22, 60 } do
	table.insert(plots, { index = 4 + i, center = p(x, 152), yaw = 0 })
end
MuseumLayout.Plots = plots

-- ─── Éléments en coordonnées locales ───────────────────────────────────

MuseumLayout.Room = { minX = -13, maxX = 13, minZ = -4, maxZ = 14, wallHeight = 11, door = 3 }
-- Point d'arrivée des visiteurs et du propriétaire (devant l'entrée, dans le jardin).
MuseumLayout.Entrance = p(0, -9)
-- Six socles : deux rangées de trois.
MuseumLayout.Pedestals = {
	p(-8, 3),
	p(0, 3),
	p(8, 3),
	p(-8, 10),
	p(0, 10),
	p(8, 10),
}
-- Panneau des statistiques (mur du fond) et emplacement des futures améliorations.
MuseumLayout.Board = p(0, 13.6)
MuseumLayout.UpgradeSpot = p(11, -1)
-- Jardin de la Museum Hunt : 8 cachettes de part et d'autre de l'allée d'entrée.
MuseumLayout.HuntSpots = {
	p(-14, -13),
	p(-9, -13),
	p(-14, -8),
	p(-9, -8),
	p(9, -13),
	p(14, -13),
	p(9, -8),
	p(14, -8),
}
MuseumLayout.HuntSign = p(-5, -14.5)
-- Rayon autour du centre du jardin dans lequel le visiteur doit rester pendant la chasse.
MuseumLayout.HuntZone = { center = p(0, -10.5), radius = 20 }

-- ─── Conversions ───────────────────────────────────────────────────────

-- Point local → monde (rotations de 0 ou 180° seulement : calcul exact).
function MuseumLayout.toWorld(plotIndex: number, localPoint: Point): Point
	local plot = plots[plotIndex]
	assert(plot, "parcelle inconnue " .. tostring(plotIndex))
	local flip = if plot.yaw ~= 0 then -1 else 1
	return {
		X = plot.center.X + localPoint.X * flip,
		Y = localPoint.Y,
		Z = plot.center.Z + localPoint.Z * flip,
	}
end

function MuseumLayout.plot(plotIndex: number): Plot?
	return plots[plotIndex]
end

-- Parcelle qui contient un point du monde (ou nil).
function MuseumLayout.plotAt(point: Point): number?
	local half = MuseumLayout.PlotSize
	for _, plot in plots do
		if
			math.abs(point.X - plot.center.X) <= half.width / 2
			and math.abs(point.Z - plot.center.Z) <= half.depth / 2
		then
			return plot.index
		end
	end
	return nil
end

function MuseumLayout.distance(a: Point, b: Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- Le quartier commence au-delà du Village (sert au libellé du bouton de retour).
function MuseumLayout.inDistrict(point: Point): boolean
	local g = MuseumLayout.Ground
	return point.X >= g.minX and point.X <= g.maxX and point.Z >= g.minZ - 4 and point.Z <= g.maxZ
end

return MuseumLayout
