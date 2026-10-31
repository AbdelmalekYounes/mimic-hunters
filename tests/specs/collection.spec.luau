local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Collection = Loader.server("Core/Collection")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local USER = 77

local OBJECTIVES = {
	{ id = "first", condition = { type = "captures", count = 1 }, reward = { id = "title_a", kind = "title" } },
	{
		id = "two_species",
		condition = { type = "species", count = 2 },
		reward = { id = "color_b", kind = "scannerColor" },
	},
	{
		id = "chroma",
		condition = { type = "mutation", mutation = "Chromatic" },
		reward = { id = "title_c", kind = "title" },
	},
}

local function make(profile, clock)
	clock = clock or { t = 100 }
	return Collection.new(USER, profile or ProfileSchema.new(clock.t), {
		now = function()
			return clock.t
		end,
		objectives = OBJECTIVES,
		defaults = { Cyan = true },
	}),
		clock
end

describe("Collection", function()
	it("crée un exemplaire individuel complet", function()
		local c = make()
		local ok, info = c:grant("srv:A1", "chairy", "Common", "Standard", 123)
		expect(ok).toBe(true)
		local s = info.specimen
		expect(s.id).toBe("S77-1")
		expect(s.speciesId).toBe("chairy")
		expect(s.rarity).toBe("Common")
		expect(s.mutation).toBe("Standard")
		expect(s.seed).toBe(123)
		expect(s.acquiredAt).toBe(100)
		expect(s.favorite).toBe(false)
		expect(info.isNewSpecies).toBe(true)
		expect(info.isNewMutation).toBe(true)
	end)

	it("garde plusieurs exemplaires d'une même espèce, chacun avec son identifiant", function()
		local c = make()
		local ids = {}
		for i = 1, 5 do
			local ok, info = c:grant("srv:A" .. i, "chairy", "Common", "Standard", i)
			expect(ok).toBe(true)
			expect(ids[info.specimen.id]).toBeNil()
			ids[info.specimen.id] = true
		end
		expect(c:count("chairy")).toBe(5)
		expect(c:discoveredCount()).toBe(1)
		expect(c:profile().codex.chairy.captured).toBe(5)
	end)

	it("n'accorde jamais deux exemplaires pour un même événement de capture", function()
		local c = make()
		c:grant("srv:A1", "chairy", "Common", "Standard", 1)
		local ok, err = c:grant("srv:A1", "chairy", "Common", "Chromatic", 2)
		expect(ok).toBe(false)
		expect(err).toBe("Duplicate")
		expect(c:owned()).toBe(1)
		expect(c:totalCaptures()).toBe(1)
	end)

	it("reste idempotent après rechargement du profil", function()
		local c = make()
		c:grant("srv:A1", "chairy", "Common", "Standard", 1)
		local saved = ProfileSchema.deepCopy(c:profile())
		local reloaded = make(saved)
		local ok, err = reloaded:grant("srv:A1", "chairy", "Common", "Standard", 1)
		expect(ok).toBe(false)
		expect(err).toBe("Duplicate")
		-- Le numéro suivant continue après le dernier attribué.
		local _, info = reloaded:grant("srv:A2", "posty", "Common", "Standard", 1)
		expect(info.specimen.id).toBe("S77-2")
	end)

	it("borne la mémoire des clés de capture", function()
		local c = make()
		for i = 1, ProfileSchema.MaxGrants + 10 do
			c:grant("k" .. i, "chairy", "Common", "Standard", i)
		end
		local profile = c:profile()
		expect(#profile.grantOrder).toBe(ProfileSchema.MaxGrants)
		expect(profile.grants.k1).toBeNil()
		expect(c:hasSource("k" .. (ProfileSchema.MaxGrants + 10))).toBe(true)
	end)

	it("refuse une capture quand la collection est pleine", function()
		local profile = ProfileSchema.new(0)
		for i = 1, ProfileSchema.MaxSpecimens do
			local id = ProfileSchema.specimenId(USER, i)
			profile.specimens[id] = {
				id = id,
				speciesId = "chairy",
				rarity = "Common",
				mutation = "Standard",
				seed = i,
				acquiredAt = 0,
				favorite = false,
			}
		end
		profile.nextSerial = ProfileSchema.MaxSpecimens + 1
		local c = make(profile)
		expect(c:isFull()).toBe(true)
		local ok, err = c:grant("x", "chairy", "Common", "Standard", 1)
		expect(ok).toBe(false)
		expect(err).toBe("CollectionFull")
	end)

	it("gère les favoris des seuls exemplaires possédés", function()
		local c = make()
		local _, info = c:grant("k1", "chairy", "Common", "Standard", 1)
		expect((c:setFavorite(info.specimen.id, true))).toBe(true)
		expect(c:specimen(info.specimen.id).favorite).toBe(true)
		expect(select(2, c:setFavorite("S1-1", true))).toBe("NotOwned")
		expect(select(2, c:setFavorite(info.specimen.id, "oui"))).toBe("BadRequest")
	end)

	it("valide les objectifs une seule fois et débloque leur récompense", function()
		local c = make()
		local _, first = c:grant("k1", "chairy", "Common", "Standard", 1)
		expect(first.completed).toEqual({ "first" })
		local _, second = c:grant("k2", "posty", "Common", "Standard", 1)
		expect(second.completed).toEqual({ "two_species" })
		local _, third = c:grant("k3", "posty", "Common", "Chromatic", 1)
		expect(third.completed).toEqual({ "chroma" })
		local _, fourth = c:grant("k4", "posty", "Common", "Chromatic", 1)
		expect(#fourth.completed).toBe(0)
		local unlocked = c:profile().cosmetics.unlocked
		expect(unlocked.title_a).toBe(true)
		expect(unlocked.color_b).toBe(true)
	end)

	it("n'équipe que des cosmétiques débloqués ou par défaut", function()
		local c = make()
		expect(select(2, c:equip("title", "title_a"))).toBe("Locked")
		c:grant("k1", "chairy", "Common", "Standard", 1)
		expect((c:equip("title", "title_a"))).toBe(true)
		expect((c:equip("scannerColor", "Cyan"))).toBe(true)
		expect(select(2, c:equip("scannerColor", "color_b"))).toBe("Locked")
		expect((c:equip("title", nil))).toBe(true)
		expect(c:profile().cosmetics.title).toBeNil()
		expect(select(2, c:equip("hat", "x"))).toBe("BadKind")
	end)

	it("n'équipe un cosmétique que dans son emplacement (audit V0.3.1)", function()
		local profile = ProfileSchema.new(100)
		profile.cosmetics.unlocked = { title_a = true, color_b = true }
		local kinds = { title_a = "title", color_b = "scannerColor", Cyan = "scannerColor" }
		local c = Collection.new(USER, profile, {
			now = function()
				return 100
			end,
			objectives = OBJECTIVES,
			defaults = { Cyan = true },
			cosmeticKind = function(id)
				return kinds[id]
			end,
		})
		expect(select(2, c:equip("title", "Cyan"))).toBe("BadKind")
		expect(select(2, c:equip("title", "color_b"))).toBe("BadKind")
		expect(select(2, c:equip("scannerColor", "title_a"))).toBe("BadKind")
		expect((c:equip("title", "title_a"))).toBe(true)
		expect((c:equip("scannerColor", "color_b"))).toBe(true)
	end)

	it("valide les réglages", function()
		local c = make()
		expect((c:setSettings({ sfx = false }))).toBe(true)
		expect(c:profile().settings.sfx).toBe(false)
		expect(select(2, c:setSettings({ reducedEffects = 1 }))).toBe("BadRequest")
		expect(select(2, c:setSettings("x"))).toBe("BadRequest")
	end)

	it("envoie au client les exemplaires du plus récent au plus ancien", function()
		local c, clock = make()
		for i = 1, 12 do
			clock.t = 100 + (if i <= 10 then 0 else i)
			c:grant("k" .. i, "chairy", "Common", "Standard", i)
		end
		local view = c:view()
		expect(#view.specimens).toBe(12)
		expect(view.specimens[1].id).toBe("S77-12")
		-- À seconde égale, l'ordre numérique (S77-10 avant S77-9) est respecté.
		expect(view.specimens[3].id).toBe("S77-10")
		expect(view.specimens[4].id).toBe("S77-9")
		expect(view.owned).toBe(12)
		expect(view.discovered).toBe(1)
	end)
end)
