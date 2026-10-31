local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local MimicCatalog = Loader.shared("Config/MimicCatalog")
local Rarities = Loader.shared("Config/Rarities")
local WeightedPicker = Loader.shared("Logic/WeightedPicker")
local Rng = Loader.shared("Logic/Rng")

describe("MimicCatalog", function()
	it("contient exactement les six espèces de départ, ids stables", function()
		local ids = {}
		for _, species in MimicCatalog.list() do
			table.insert(ids, species.id)
		end
		expect(ids).toEqual({ "chairy", "trashling", "posty", "lumino", "chompy", "vendoo" })
	end)

	it("associe chaque espèce à un type d'objet unique et connu", function()
		local seen = {}
		for _, species in MimicCatalog.list() do
			expect(MimicCatalog.Kinds[species.kind] ~= nil).toBe(true)
			expect(seen[species.kind]).toBeNil()
			seen[species.kind] = true
			expect(MimicCatalog.getByKind(species.kind)).toBe(species)
		end
	end)

	it("donne à chaque espèce les champs requis", function()
		for _, species in MimicCatalog.list() do
			expect(type(species.name) == "string" and #species.name > 0).toBe(true)
			expect(Rarities.get(species.rarity) ~= nil).toBe(true)
			expect(#species.behavior.clues).toBeGreaterThan(0)
			expect(species.behavior.clueIntervalMin).toBeLessThan(species.behavior.clueIntervalMax)
			local capture = species.behavior.capture
			expect(capture.speed).toBeGreaterThan(0)
			expect(capture.zoneWidth > 0 and capture.zoneWidth < 0.5).toBe(true)
			expect(type(species.behavior.revealStyle)).toBe("string")
			expect(type(species.behavior.fleeStyle)).toBe("string")
			expect(#species.appearance.bodyColor).toBe(3)
		end
	end)

	it("rend les espèces rares plus difficiles à capturer", function()
		local chairy = MimicCatalog.get("chairy").behavior.capture
		local vendoo = MimicCatalog.get("vendoo").behavior.capture
		expect(vendoo.speed).toBeGreaterThan(chairy.speed)
		expect(vendoo.zoneWidth).toBeLessThan(chairy.zoneWidth)
	end)

	it("renvoie nil pour un id inconnu", function()
		expect(MimicCatalog.get("pikachu")).toBeNil()
	end)
end)

describe("MimicCatalog — noms d'objets (V0.3.1)", function()
	it("accorde l'article au genre du nom", function()
		expect(MimicCatalog.kindWithArticle("Chest")).toBe("un coffre")
		expect(MimicCatalog.kindWithArticle("Vending")).toBe("un distributeur")
		expect(MimicCatalog.kindWithArticle("Chair")).toBe("une chaise")
		expect(MimicCatalog.kindWithArticle("Mailbox")).toBe("une boîte aux lettres")
		expect(MimicCatalog.kindWithArticle("Inconnu")).toBe("un objet")
	end)
end)

describe("Raretés", function()
	it("ordonne les poids : Commun > Peu commun > Rare > Épique", function()
		expect(Rarities.weightOf("Common")).toBeGreaterThan(Rarities.weightOf("Uncommon"))
		expect(Rarities.weightOf("Uncommon")).toBeGreaterThan(Rarities.weightOf("Rare"))
		expect(Rarities.weightOf("Rare")).toBeGreaterThan(Rarities.weightOf("Epic"))
		expect(Rarities.weightOf("Inconnue")).toBe(0)
	end)

	it("tire les raretés proportionnellement à leur poids", function()
		local entries = {}
		local total = 0
		for _, rarity in Rarities.list() do
			table.insert(entries, { item = rarity.id, weight = rarity.spawnWeight })
			total += rarity.spawnWeight
		end
		local rng = Rng.new(2024)
		local counts = {}
		local draws = 20000
		for _ = 1, draws do
			local id = WeightedPicker.pick(entries, rng)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, rarity in Rarities.list() do
			local expected = rarity.spawnWeight / total
			local observed = (counts[rarity.id] or 0) / draws
			expect(observed).toBeCloseTo(expected, 0.02)
		end
	end)

	it("ne choisit jamais une entrée de poids nul", function()
		local rng = Rng.new(5)
		for _ = 1, 500 do
			local pick = WeightedPicker.pick({ { item = "a", weight = 0 }, { item = "b", weight = 1 } }, rng)
			expect(pick).toBe("b")
		end
	end)

	it("renvoie nil si aucun poids n'est positif", function()
		expect(WeightedPicker.pick({}, Rng.new(1))).toBeNil()
		expect(WeightedPicker.pick({ { item = "a", weight = 0 } }, Rng.new(1))).toBeNil()
	end)
end)
