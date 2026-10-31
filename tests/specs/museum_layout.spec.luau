local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local MuseumLayout = Loader.server("Map/MuseumLayout")
local MapLayout = Loader.server("Map/MapLayout")
local PlotRegistry = Loader.server("Core/PlotRegistry")

local function overlaps(a, b, size)
	return math.abs(a.X - b.X) < size.width and math.abs(a.Z - b.Z) < size.depth
end

describe("MuseumLayout", function()
	it("prévoit 8 parcelles qui ne se chevauchent pas et tournent l'entrée vers la rue", function()
		expect(#MuseumLayout.Plots).toBe(8)
		for i, a in MuseumLayout.Plots do
			for j = i + 1, #MuseumLayout.Plots do
				expect(overlaps(a.center, MuseumLayout.Plots[j].center, MuseumLayout.PlotSize)).toBe(false)
			end
			local entrance = MuseumLayout.toWorld(a.index, MuseumLayout.Entrance)
			-- L'entrée est plus proche de la rue que le centre de la parcelle.
			expect(math.abs(entrance.Z - MuseumLayout.StreetZ)).toBeLessThan(
				math.abs(a.center.Z - MuseumLayout.StreetZ)
			)
		end
	end)

	it("laisse l'avenue centrale libre jusqu'à la rue", function()
		local avenue = MuseumLayout.Avenue
		for _, plot in MuseumLayout.Plots do
			local half = MuseumLayout.PlotSize.width / 2
			local clear = plot.center.X + half <= avenue.minX or plot.center.X - half >= avenue.maxX
			expect(clear).toBe(true)
		end
	end)

	it("reste hors des trois zones de chasse et de leurs objets", function()
		for _, zone in MapLayout.Zones do
			for _, plot in MuseumLayout.Plots do
				-- Le coin le plus proche de la parcelle reste en dehors du rayon de la zone.
				local dz = math.max(0, math.abs(plot.center.Z - zone.center.Z) - MuseumLayout.PlotSize.depth / 2)
				local dx = math.max(0, math.abs(plot.center.X - zone.center.X) - MuseumLayout.PlotSize.width / 2)
				expect(math.sqrt(dx * dx + dz * dz)).toBeGreaterThan(zone.radius)
			end
		end
		for _, prop in MapLayout.allProps() do
			expect(MuseumLayout.plotAt(prop.position)).toBeNil()
		end
	end)

	it("place socles, cachettes et panneau à l'intérieur de la parcelle", function()
		local half = MuseumLayout.PlotSize
		local points = { MuseumLayout.Entrance, MuseumLayout.Board, MuseumLayout.HuntSign, MuseumLayout.UpgradeSpot }
		for _, list in { MuseumLayout.Pedestals, MuseumLayout.HuntSpots } do
			for _, point in list do
				table.insert(points, point)
			end
		end
		for _, point in points do
			expect(math.abs(point.X)).toBeLessThan(half.width / 2)
			expect(math.abs(point.Z)).toBeLessThan(half.depth / 2)
		end
		expect(#MuseumLayout.Pedestals).toBe(6)
		expect(#MuseumLayout.HuntSpots).toBe(8)
		-- Les socles sont dans la salle, les cachettes dans le jardin (devant le mur).
		for _, pedestal in MuseumLayout.Pedestals do
			expect(pedestal.Z > MuseumLayout.Room.minZ and pedestal.Z < MuseumLayout.Room.maxZ).toBe(true)
		end
		for _, spot in MuseumLayout.HuntSpots do
			expect(spot.Z).toBeLessThan(MuseumLayout.Room.minZ)
			-- Toutes atteignables depuis le jardin.
			expect(MuseumLayout.distance(spot, MuseumLayout.HuntZone.center)).toBeLessThan(MuseumLayout.HuntZone.radius)
		end
	end)

	it("convertit local → monde selon l'orientation de la parcelle", function()
		local south = MuseumLayout.toWorld(1, { X = 2, Y = 0, Z = -3 })
		expect(south.X).toBe(-60 - 2)
		expect(south.Z).toBe(104 + 3)
		local north = MuseumLayout.toWorld(5, { X = 2, Y = 0, Z = -3 })
		expect(north.X).toBe(-60 + 2)
		expect(north.Z).toBe(152 - 3)
		expect(MuseumLayout.plotAt(south)).toBe(1)
	end)
end)

describe("PlotRegistry", function()
	it("donne une parcelle distincte à chaque joueur", function()
		local r = PlotRegistry.new(8)
		local seen = {}
		for userId = 1, 8 do
			local plot = r:assign(userId)
			expect(plot ~= nil).toBe(true)
			expect(seen[plot]).toBeNil()
			seen[plot] = true
		end
		expect(r:freeCount()).toBe(0)
		-- Idempotent.
		expect(r:assign(3)).toBe(r:plotOf(3))
	end)

	it("met en attente quand tout est pris, puis sert le premier en attente", function()
		local r = PlotRegistry.new(2)
		r:assign(1)
		r:assign(2)
		expect(r:assign(3)).toBeNil()
		expect(r:assign(4)).toBeNil()
		expect(r:isWaiting(3)).toBe(true)
		local freed, served = r:release(1)
		expect(freed).toBe(1)
		expect(served).toBe(3)
		expect(r:plotOf(3)).toBe(1)
		expect(r:ownerOf(1)).toBe(3)
		expect(r:isWaiting(4)).toBe(true)
	end)

	it("libère proprement et retire de la file un joueur qui attendait", function()
		local r = PlotRegistry.new(1)
		r:assign(1)
		r:assign(2)
		r:release(2)
		expect(r:isWaiting(2)).toBe(false)
		local freed, served = r:release(1)
		expect(freed).toBe(1)
		expect(served).toBeNil()
		expect(r:ownerOf(1)).toBeNil()
		expect(r:freeCount()).toBe(1)
		expect(select(1, r:release(99))).toBeNil()
	end)
end)
