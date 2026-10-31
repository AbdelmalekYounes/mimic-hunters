local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Objectives = Loader.shared("Config/Objectives")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local A = 64
local named = Fixtures.named

local function captureOne(world, userId, now)
	local record = Fixtures.findHidden(world)
	local pos = Fixtures.near(world, record.slotId)
	world:inspect(userId, pos, record.slotId, now)
	local _, started = world:startCapture(userId, pos, record.id, now + 0.2)
	local events = Fixtures.playCapture(world, userId, pos, started, now + 0.2, { "hit", "hit" })
	return named(events, "CaptureResolved", userId)[1].payload, events
end

describe("Objectifs — configuration", function()
	it("relie chaque objectif à une récompense cosmétique existante, du bon type", function()
		local seen = {}
		for _, objective in Objectives.list() do
			expect(seen[objective.id]).toBeNil()
			seen[objective.id] = true
			local cosmetic = Objectives.cosmetic(objective.reward.id)
			expect(cosmetic ~= nil).toBe(true)
			expect(cosmetic.kind).toBe(objective.reward.kind)
		end
		expect(#Objectives.list()).toBeAtLeast(5)
		expect(Objectives.cosmetic(Objectives.DefaultScannerColor).kind).toBe("scannerColor")
		expect(Objectives.defaults()[Objectives.DefaultScannerColor]).toBe(true)
	end)

	it("couvre les exemples demandés (1re capture, 3 espèces, Chromatic, Spectral, collection complète)", function()
		local wanted = {
			first_capture = true,
			three_species = true,
			first_chromatic = true,
			first_spectral = true,
			full_codex = true,
		}
		for _, objective in Objectives.list() do
			wanted[objective.id] = nil
		end
		expect(next(wanted)).toBeNil()
	end)

	it("calcule la progression à partir du résumé", function()
		local byId = {}
		for _, o in Objectives.list() do
			byId[o.id] = o
		end
		local summary = { totalCaptures = 4, discovered = 2, mutations = { Chromatic = 1 } }
		expect(select(1, Objectives.progress(byId.ten_captures, summary))).toBe(4)
		expect(select(2, Objectives.progress(byId.ten_captures, summary))).toBe(10)
		expect(select(1, Objectives.progress(byId.three_species, summary))).toBe(2)
		expect(select(1, Objectives.progress(byId.first_chromatic, summary))).toBe(1)
		expect(select(1, Objectives.progress(byId.first_spectral, summary))).toBe(0)
		expect(select(1, Objectives.progress(byId.first_capture, nil))).toBe(0)
		expect(Objectives.rewardText(byId.first_capture)).toBe("Titre « Apprenti chasseur »")
		expect(Objectives.rewardText(byId.three_species)).toBe("Couleur de scanner Menthe")
	end)
end)

describe("Objectifs — serveur", function()
	it("valide la première capture et débloque son titre", function()
		local world = Fixtures.world(80)
		world:addPlayer(A, 0, Fixtures.veteran())
		local resolved = captureOne(world, A, 10)
		expect(resolved.completed).toEqual({ "first_capture" })
		local profile = world:inventoryOf(A):profile()
		expect(profile.objectives.first_capture ~= nil).toBe(true)
		expect(profile.cosmetics.unlocked.title_apprentice).toBe(true)
	end)

	it("équipe un titre débloqué, refuse un cosmétique verrouillé", function()
		local world = Fixtures.world(81)
		world:addPlayer(A, 0, Fixtures.veteran())
		local events, reply = world:equipCosmetic(A, "title", "title_apprentice", 1)
		expect(reply.ok).toBe(false)
		expect(reply.reason).toBe("Locked")
		expect(#named(events, "_CosmeticsChanged")).toBe(0)
		captureOne(world, A, 10)
		events, reply = world:equipCosmetic(A, "title", "title_apprentice", 20)
		expect(reply.ok).toBe(true)
		expect(reply.result.summary.cosmetics.title).toBe("title_apprentice")
		local changed = named(events, "_CosmeticsChanged", A)[1]
		expect(changed.payload.title).toBe("title_apprentice")
		expect(#named(events, "_ProfileChanged", A)).toBe(1)
		expect(world:cosmeticsOf(A).title).toBe("title_apprentice")
		-- Couleur par défaut toujours disponible.
		local _, back = world:equipCosmetic(A, "scannerColor", "Cyan", 21)
		expect(back.ok).toBe(true)
	end)

	it("rattrape les objectifs déjà atteints au chargement d'un ancien profil", function()
		local world = Fixtures.world(82)
		world:addPlayer(A, 0, {
			version = 1,
			tutorialDone = true,
			inventory = {
				version = 1,
				species = {
					chairy = { count = 1, discoveryOrder = 1 },
					posty = { count = 1, discoveryOrder = 2 },
					lumino = { count = 1, discoveryOrder = 3 },
				},
			},
		})
		local profile = world:inventoryOf(A):profile()
		expect(profile.objectives.first_capture ~= nil).toBe(true)
		expect(profile.objectives.three_species ~= nil).toBe(true)
		expect(profile.cosmetics.unlocked.color_mint).toBe(true)
		expect(profile.objectives.full_codex).toBeNil()
	end)

	it("enregistre les réglages et les garde après reconnexion", function()
		local world = Fixtures.world(83)
		world:addPlayer(A, 0, Fixtures.veteran())
		local _, reply = world:updateSettings(A, { sfx = false, reducedEffects = true }, 1)
		expect(reply.ok).toBe(true)
		local saved = ProfileSchema.deepCopy(world:getProfile(A))
		local other = Fixtures.world(84)
		other:addPlayer(A, 0, saved)
		local settings = other:inventoryOf(A):profile().settings
		expect(settings.sfx).toBe(false)
		expect(settings.reducedEffects).toBe(true)
		local _, bad = world:updateSettings(A, { sfx = "non" }, 2)
		expect(bad.ok).toBe(false)
	end)

	it("refuse les demandes de collection quand le profil n'est pas sûr", function()
		local world = Fixtures.world(85)
		world:addPlayer(A, 0, nil, { ready = false, status = "Unavailable" })
		local _, reply = world:setFavorite(A, "S64-1", true, 1)
		expect(reply.reason).toBe("ProfileUnavailable")
		local _, equip = world:equipCosmetic(A, "scannerColor", "Cyan", 1)
		expect(equip.reason).toBe("ProfileUnavailable")
		expect(world:cosmeticsOf(A)).toBeNil()
	end)
end)
