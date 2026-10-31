local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local CollectionQuery = Loader.shared("Logic/CollectionQuery")
local MimicCatalog = Loader.shared("Config/MimicCatalog")

local function s(id, speciesId, rarity, mutation, at, favorite)
	return {
		id = id,
		speciesId = speciesId,
		rarity = rarity,
		mutation = mutation,
		seed = 1,
		acquiredAt = at,
		favorite = favorite == true,
	}
end

local LIST = {
	s("S1-1", "chairy", "Common", "Standard", 100),
	s("S1-2", "posty", "Uncommon", "Chromatic", 200, true),
	s("S1-3", "vendoo", "Epic", "Standard", 300),
	s("S1-4", "chairy", "Common", "Spectral", 300),
	s("S1-10", "lumino", "Rare", "Standard", 300, true),
}

local function ids(list)
	local out = {}
	for _, x in list do
		table.insert(out, x.id)
	end
	return out
end

describe("CollectionQuery", function()
	it("filtre par rareté, espèce, mutation et favoris", function()
		expect(ids(CollectionQuery.filter(LIST, { rarity = "Common" }))).toEqual({ "S1-1", "S1-4" })
		expect(ids(CollectionQuery.filter(LIST, { species = "chairy", mutation = "Spectral" }))).toEqual({ "S1-4" })
		expect(ids(CollectionQuery.filter(LIST, { favoritesOnly = true }))).toEqual({ "S1-2", "S1-10" })
		expect(#CollectionQuery.filter(LIST, {})).toBe(5)
	end)

	it("trie par capture récente (numéro départage à seconde égale)", function()
		expect(ids(CollectionQuery.sort(LIST, "Recent"))).toEqual({ "S1-10", "S1-4", "S1-3", "S1-2", "S1-1" })
	end)

	it("trie par rareté : mutation, puis rareté d'espèce, puis récence", function()
		expect(ids(CollectionQuery.sort(LIST, "Rarity"))).toEqual({ "S1-4", "S1-2", "S1-3", "S1-10", "S1-1" })
	end)

	it("ne modifie pas la liste reçue", function()
		local before = ids(LIST)
		CollectionQuery.sort(LIST, "Rarity")
		expect(ids(LIST)).toEqual(before)
	end)

	it("découpe en pages et borne la page demandée", function()
		local items, page, pages = CollectionQuery.paginate(LIST, 2, 2)
		expect(ids(items)).toEqual({ "S1-3", "S1-4" })
		expect(page).toBe(2)
		expect(pages).toBe(3)
		local _, clamped = CollectionQuery.paginate(LIST, 99, 2)
		expect(clamped).toBe(3)
		local empty, p, n = CollectionQuery.paginate({}, 1, 12)
		expect(#empty).toBe(0)
		expect(p).toBe(1)
		expect(n).toBe(1)
	end)

	it("calcule la complétion de la collection", function()
		local summary = {
			codex = {
				chairy = { mutations = { "Spectral", "Standard" } },
				posty = { mutations = { "Chromatic" } },
			},
		}
		local c = CollectionQuery.completion(summary, MimicCatalog)
		expect(c.discovered).toBe(2)
		expect(c.total).toBe(6)
		expect(c.percent).toBe(33)
		expect(c.variants).toBe(3)
		expect(c.variantsTotal).toBe(18)
		expect(c.complete).toBe(false)
		expect(CollectionQuery.completion(nil, MimicCatalog).discovered).toBe(0)
	end)

	it("fait défiler les options d'un filtre puis revient à « Tous »", function()
		local options = { "Common", "Rare" }
		expect(CollectionQuery.cycle(options, nil)).toBe("Common")
		expect(CollectionQuery.cycle(options, "Common")).toBe("Rare")
		expect(CollectionQuery.cycle(options, "Rare")).toBeNil()
	end)
end)
