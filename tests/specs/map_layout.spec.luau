local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local MapLayout = Loader.server("Map/MapLayout")
local MimicCatalog = Loader.shared("Config/MimicCatalog")
local GameConfig = Loader.shared("Config/GameConfig")

local function distance(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

describe("MapLayout", function()
	it("place 40 objets partagés plus l'objet du tutoriel", function()
		expect(#MapLayout.Props).toBe(40)
		expect(#MapLayout.allProps()).toBe(41)
	end)

	it("utilise des identifiants uniques et valides", function()
		local seen = {}
		for _, prop in MapLayout.allProps() do
			expect(string.match(prop.id, "^[%w_%-]+$") ~= nil).toBe(true)
			expect(seen[prop.id]).toBeNil()
			seen[prop.id] = true
		end
	end)

	it("n'utilise que des types d'objets du catalogue", function()
		for _, prop in MapLayout.allProps() do
			expect(MimicCatalog.getByKind(prop.kind) ~= nil).toBe(true)
		end
	end)

	it("offre au moins deux cachettes pour chaque espèce", function()
		local perKind = {}
		for _, prop in MapLayout.Props do
			perKind[prop.kind] = (perKind[prop.kind] or 0) + 1
		end
		for _, species in MimicCatalog.list() do
			expect(perKind[species.kind] or 0).toBeAtLeast(2)
		end
	end)

	it("place chaque objet dans sa zone", function()
		local zones = {}
		for _, zone in MapLayout.Zones do
			zones[zone.id] = zone
		end
		for _, prop in MapLayout.allProps() do
			local zone = zones[prop.zone]
			expect(zone ~= nil).toBe(true)
			expect(distance(prop.position, zone.center)).toBeAtMost(zone.radius)
		end
	end)

	it("donne à chaque zone assez de cachettes pour le minimum par zone", function()
		local perZone = {}
		for _, prop in MapLayout.Props do
			perZone[prop.zone] = (perZone[prop.zone] or 0) + 1
		end
		for _, zoneId in MapLayout.zoneIds() do
			expect(perZone[zoneId] or 0).toBeGreaterThan(GameConfig.Hunt.MinPerZone * 2)
		end
	end)

	it("espace les objets d'au moins 3 studs", function()
		local props = MapLayout.allProps()
		for i = 1, #props do
			for j = i + 1, #props do
				local d = distance(props[i].position, props[j].position)
				if d < 3 then
					error(string.format("%s et %s trop proches (%.2f)", props[i].id, props[j].id, d))
				end
			end
		end
	end)

	it("place l'objet du tutoriel à portée d'examen du point d'apparition", function()
		local d = distance(MapLayout.Spawn.position, MapLayout.TutorialProp.position)
		expect(d).toBeLessThan(GameConfig.Scanner.FlinchRange)
		expect(d).toBeGreaterThan(4)
	end)

	it("cache moins de la moitié des objets en même temps", function()
		expect(GameConfig.Hunt.ActiveMimics).toBeLessThan(#MapLayout.Props / 2)
	end)
end)
