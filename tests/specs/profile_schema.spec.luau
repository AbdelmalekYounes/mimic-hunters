local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ProfileSchema = Loader.server("Core/ProfileSchema")
local MimicCatalog = Loader.shared("Config/MimicCatalog")

local USER = 4242

local function context(now)
	return {
		userId = USER,
		now = now or 1000,
		rarityOf = function(id)
			local species = MimicCatalog.get(id)
			return if species then species.rarity else nil
		end,
	}
end

-- Profil V0.1 tel que l'écrivait MemoryProfileStore.
local function v1Profile()
	return {
		version = 1,
		tutorialDone = true,
		inventory = {
			version = 1,
			totalCaptures = 3,
			species = {
				chairy = { count = 2, discoveryOrder = 1 },
				posty = { count = 1, discoveryOrder = 2 },
				removed_species = { count = 4, discoveryOrder = 3 },
			},
		},
	}
end

describe("ProfileSchema", function()
	it("crée un profil neuf au schéma courant", function()
		local profile, err = ProfileSchema.migrate(nil, context())
		expect(err).toBeNil()
		expect(profile.schemaVersion).toBe(ProfileSchema.Version)
		expect(profile.nextSerial).toBe(1)
		expect(profile.tutorialDone).toBe(false)
		expect(profile.cosmetics.scannerColor).toBe(ProfileSchema.DefaultScannerColor)
		expect(profile.settings.sfx).toBe(true)
	end)

	it("migre un profil V0.1 : chaque capture devient un exemplaire Standard", function()
		local profile = ProfileSchema.migrate(v1Profile(), context(5000))
		expect(profile.schemaVersion).toBe(2)
		expect(profile.tutorialDone).toBe(true)
		expect(profile.stats.totalCaptures).toBe(3)
		local bySpecies, ids = {}, {}
		for id, s in profile.specimens do
			bySpecies[s.speciesId] = (bySpecies[s.speciesId] or 0) + 1
			expect(ids[id]).toBeNil()
			ids[id] = true
			expect(s.mutation).toBe("Standard")
			expect(s.acquiredAt).toBe(5000)
			expect(s.rarity).toBe(MimicCatalog.get(s.speciesId).rarity)
		end
		expect(bySpecies.chairy).toBe(2)
		expect(bySpecies.posty).toBe(1)
		-- Une espèce qui n'existe plus n'est pas convertie.
		expect(bySpecies.removed_species).toBeNil()
		expect(profile.codex.chairy.order).toBe(1)
		expect(profile.codex.posty.order).toBe(2)
		expect(profile.nextSerial).toBe(4)
	end)

	it("donne des graines reproductibles lors de la migration", function()
		local a = ProfileSchema.migrate(v1Profile(), context())
		local b = ProfileSchema.migrate(v1Profile(), context())
		expect(a.specimens).toEqual(b.specimens)
	end)

	it("refuse un profil d'une version future (jamais écrasé par un ancien serveur)", function()
		local profile, err = ProfileSchema.migrate({ schemaVersion = 99 }, context())
		expect(profile).toBeNil()
		expect(err).toBe("FutureVersion")
	end)

	it("refuse des données illisibles", function()
		expect(select(2, ProfileSchema.migrate("texte", context()))).toBe("Corrupt")
		expect(select(2, ProfileSchema.migrate({ schemaVersion = "2" }, context()))).toBe("Corrupt")
	end)

	it("répare un profil v2 abîmé sans lever d'erreur", function()
		local data = ProfileSchema.new(10)
		data.specimens["S1-5"] =
			{ id = "S1-5", speciesId = "chairy", rarity = "Common", mutation = "Standard", seed = 7, acquiredAt = 10 }
		data.specimens["S1-6"] = { id = "S1-6", speciesId = 42 } -- invalide
		data.specimens["mauvaise-cle"] =
			{ id = "S1-9", speciesId = "chairy", rarity = "Common", mutation = "Standard", seed = 7, acquiredAt = 10 }
		data.nextSerial = 2 -- en retard sur les numéros déjà utilisés
		data.settings = { sfx = "oui" }
		local profile, dropped = ProfileSchema.sanitize(data, context())
		expect(dropped).toBe(2)
		expect(profile.specimens["S1-5"].favorite).toBe(false)
		-- Le compteur ne repasse jamais sous un numéro existant.
		expect(profile.nextSerial).toBe(6)
		expect(profile.settings.sfx).toBe(true)
	end)

	it("laisse inchangé un profil v2 valide (aller-retour)", function()
		local profile = ProfileSchema.migrate(v1Profile(), context())
		profile.objectives.first_capture = 1234
		profile.cosmetics.unlocked.title_novice = true
		profile.cosmetics.title = "title_novice"
		local again = ProfileSchema.migrate(ProfileSchema.deepCopy(profile), context(9999))
		expect(again).toEqual(profile)
	end)

	it("formate des identifiants d'exemplaires uniques par joueur d'origine", function()
		expect(ProfileSchema.specimenId(12, 3)).toBe("S12-3")
		expect(ProfileSchema.specimenId(12, 3) ~= ProfileSchema.specimenId(1, 23)).toBe(true)
	end)
end)
