local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local EncounterGenerator = Loader.server("Core/EncounterGenerator")
local MapLayout = Loader.server("Map/MapLayout")
local MimicCatalog = Loader.shared("Config/MimicCatalog")
local Rarities = Loader.shared("Config/Rarities")
local Rng = Loader.shared("Logic/Rng")

local function input(occupied, zoneCounts, blocked)
	return {
		slots = MapLayout.Props,
		occupied = occupied or {},
		blocked = blocked,
		zoneCounts = zoneCounts or {},
		zones = MapLayout.zoneIds(),
		minPerZone = 3,
		species = MimicCatalog.list(),
		weightOf = Rarities.weightOf,
	}
end

local slotsById = {}
for _, slot in MapLayout.Props do
	slotsById[slot.id] = slot
end

describe("EncounterGenerator.chooseSpawn", function()
	it("associe toujours l'espèce au type d'objet de l'emplacement", function()
		local rng = Rng.new(11)
		for _ = 1, 300 do
			local slot, species = EncounterGenerator.chooseSpawn(input(), rng)
			expect(slot.kind).toBe(species.kind)
		end
	end)

	it("n'utilise jamais un emplacement occupé ou bloqué", function()
		local rng = Rng.new(3)
		local occupied, blocked = {}, {}
		for i, slot in MapLayout.Props do
			if i % 2 == 0 then
				occupied[slot.id] = "M"
			elseif i % 3 == 0 then
				blocked[slot.id] = true
			end
		end
		for _ = 1, 300 do
			local slot = EncounterGenerator.chooseSpawn(input(occupied, nil, blocked), rng)
			expect(occupied[slot.id]).toBeNil()
			expect(blocked[slot.id]).toBeNil()
		end
	end)

	it("renvoie nil quand tout est occupé", function()
		local occupied = {}
		for _, slot in MapLayout.Props do
			occupied[slot.id] = "M"
		end
		local slot, species = EncounterGenerator.chooseSpawn(input(occupied), Rng.new(1))
		expect(slot).toBeNil()
		expect(species).toBeNil()
	end)

	it("sert en priorité les zones sous le minimum", function()
		local rng = Rng.new(8)
		for _ = 1, 200 do
			local slot = EncounterGenerator.chooseSpawn(input(nil, { Village = 5, Park = 0, Market = 5 }), rng)
			expect(slot.zone).toBe("Park")
		end
	end)

	it("génère 12 Mimics répartis dans les trois zones", function()
		for seed = 1, 30 do
			local rng = Rng.new(seed)
			local occupied, zoneCounts = {}, {}
			for _ = 1, 12 do
				local slot = EncounterGenerator.chooseSpawn(input(occupied, zoneCounts), rng)
				occupied[slot.id] = true
				zoneCounts[slot.zone] = (zoneCounts[slot.zone] or 0) + 1
			end
			for _, zone in MapLayout.zoneIds() do
				expect(zoneCounts[zone] or 0).toBeAtLeast(3)
			end
		end
	end)

	it("fait apparaître les communs bien plus souvent que l'épique", function()
		local rng = Rng.new(77)
		local counts = {}
		for _ = 1, 6000 do
			local _, species = EncounterGenerator.chooseSpawn(input(nil, { Village = 9, Park = 9, Market = 9 }), rng)
			counts[species.rarity] = (counts[species.rarity] or 0) + 1
		end
		expect(counts.Common).toBeGreaterThan((counts.Epic or 0) * 4)
		expect(counts.Epic or 0).toBeGreaterThan(0)
	end)
end)

describe("EncounterGenerator.chooseFleeSlot", function()
	it("choisit un autre emplacement libre du même type, de préférence dans la zone", function()
		local from = slotsById.V13 -- lampadaire du village
		local rng = Rng.new(4)
		for _ = 1, 100 do
			local target = EncounterGenerator.chooseFleeSlot(MapLayout.Props, {}, nil, from, rng)
			expect(target.kind).toBe("Lamp")
			expect(target.id ~= from.id).toBe(true)
			expect(target.zone).toBe("Village")
		end
	end)

	it("change de zone si la zone n'a plus de place", function()
		local from = slotsById.V13
		local occupied = { V14 = true, V15 = true, V16 = true }
		local target = EncounterGenerator.chooseFleeSlot(MapLayout.Props, occupied, nil, from, Rng.new(2))
		expect(target.kind).toBe("Lamp")
		expect(target.zone).toBe("Park")
	end)

	it("renvoie nil si aucun emplacement n'est libre", function()
		local from = slotsById.C05
		local occupied = { C06 = true, C07 = true, C08 = true, C09 = true }
		expect(EncounterGenerator.chooseFleeSlot(MapLayout.Props, occupied, nil, from, Rng.new(2))).toBeNil()
	end)
end)
