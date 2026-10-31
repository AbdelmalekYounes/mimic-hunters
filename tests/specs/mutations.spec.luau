local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Mutations = Loader.shared("Config/Mutations")
local SpecimenLook = Loader.shared("Logic/SpecimenLook")
local Rng = Loader.shared("Logic/Rng")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local A = 31
local named = Fixtures.named

-- Tirage forcé, pour tester le comportement autour d'une mutation donnée.
local function forced(id)
	return {
		roll = function()
			return id
		end,
	}
end

local function captureOne(world, userId, now)
	local record = Fixtures.findHidden(world)
	local pos = Fixtures.near(world, record.slotId)
	world:inspect(userId, pos, record.slotId, now)
	local _, started = world:startCapture(userId, pos, record.id, now + 0.2)
	local events = Fixtures.playCapture(world, userId, pos, started, now + 0.2, { "hit", "hit" })
	return events, named(events, "CaptureResolved", userId)[1].payload
end

describe("Mutations — configuration", function()
	it("définit des probabilités cohérentes (somme = 1, rareté croissante)", function()
		local total, lastOrder, lastChance = 0, 0, math.huge
		for _, mutation in Mutations.list() do
			expect(mutation.chance > 0 and mutation.chance < 1).toBe(true)
			expect(mutation.order).toBeGreaterThan(lastOrder)
			expect(mutation.chance).toBeLessThan(lastChance)
			total += mutation.chance
			lastOrder, lastChance = mutation.order, mutation.chance
		end
		expect(total).toBeCloseTo(1, 1e-9)
	end)

	it("tire les mutations selon ces probabilités (200 000 tirages)", function()
		local rng = Rng.new(2024)
		local counts = {}
		local n = 200000
		for _ = 1, n do
			local id = Mutations.roll(rng)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, mutation in Mutations.list() do
			local observed = (counts[mutation.id] or 0) / n
			-- Écart toléré : 5 écarts-types.
			local sigma = math.sqrt(mutation.chance * (1 - mutation.chance) / n)
			expect(math.abs(observed - mutation.chance)).toBeLessThan(5 * sigma)
		end
	end)

	it("affiche les probabilités à la française", function()
		expect(Mutations.chanceText("Chromatic")).toBe("4 %")
		expect(Mutations.chanceText("Spectral")).toBe("1,5 %")
		expect(Mutations.chanceText("Standard")).toBe("94,5 %")
		expect(Mutations.isRare("Standard")).toBe(false)
		expect(Mutations.isRare("Spectral")).toBe(true)
	end)
end)

describe("Mutations — apparence", function()
	local species = Fixtures.MimicCatalog.get("posty")

	it("donne une palette distinctive et un éclat aux Chromatic", function()
		local look = SpecimenLook.compute(species, 99, "Chromatic")
		expect(look.mutation).toBe("Chromatic")
		expect(look.glow ~= nil).toBe(true)
		expect(look.transparency).toBe(0)
		local _, saturation, value = SpecimenLook.rgbToHsv(look.body)
		expect(saturation).toBeGreaterThan(0.5)
		expect(value).toBeGreaterThan(0.95)
		expect(SpecimenLook.compute(species, 99, "Chromatic")).toEqual(look)
	end)

	it("rend les Spectral translucides, aux yeux lumineux", function()
		local look = SpecimenLook.compute(species, 99, "Spectral")
		expect(look.transparency).toBeGreaterThan(0.3)
		expect(look.eyeGlow ~= nil).toBe(true)
		local hue = SpecimenLook.rgbToHsv(look.body)
		expect(hue >= 0.45 and hue <= 0.8).toBe(true)
	end)

	it("fait glisser la teinte des Chromatic dans le temps sans changer d'éclat", function()
		local look = SpecimenLook.compute(species, 5, "Chromatic")
		local later = SpecimenLook.chromaticAt(look.body, 3)
		local _, s1, v1 = SpecimenLook.rgbToHsv(look.body)
		local _, s2, v2 = SpecimenLook.rgbToHsv(later)
		expect(table.concat(later, ",") ~= table.concat(look.body, ",")).toBe(true)
		expect(math.abs(s1 - s2)).toBeLessThan(0.02)
		expect(math.abs(v1 - v2)).toBeLessThan(0.02)
	end)
end)

describe("Mutations — tirage serveur", function()
	it("tire la mutation au moment de la capture et l'enregistre partout", function()
		local world = Fixtures.world(70, nil, { mutations = forced("Spectral") })
		world:addPlayer(A, 0, Fixtures.veteran())
		local events, resolved = captureOne(world, A, 10)
		expect(resolved.success).toBe(true)
		expect(resolved.mutation).toBe("Spectral")
		expect(resolved.specimen.mutation).toBe("Spectral")
		expect(resolved.isNewMutation).toBe(true)
		local collection = world:inventoryOf(A)
		local profile = collection:profile()
		expect(profile.stats.mutations.Spectral).toBe(1)
		expect(profile.codex[resolved.speciesId].mutations.Spectral).toBe(true)
		-- Annonce à tout le serveur (userId nil = diffusion).
		local rare = named(events, "RareCapture")[1]
		expect(rare.userId).toBeNil()
		expect(rare.payload.userId).toBe(A)
		expect(rare.payload.mutation).toBe("Spectral")
	end)

	it("n'annonce pas les captures Standard", function()
		local world = Fixtures.world(71, nil, { mutations = forced("Standard") })
		world:addPlayer(A, 0, Fixtures.veteran())
		local events = captureOne(world, A, 10)
		expect(#named(events, "RareCapture")).toBe(0)
	end)

	it("garde le Mimic du tutoriel toujours Standard", function()
		local world = Fixtures.world(72, nil, { mutations = forced("Chromatic") })
		world:addPlayer(A, 0)
		local slot = world:slot("TUTO")
		local pos = { X = slot.position.X + 3, Y = 3, Z = slot.position.Z }
		local _, inspected = world:inspect(A, pos, "TUTO", 1)
		local _, started = world:startCapture(A, pos, inspected.mimicId, 1.2)
		local events = Fixtures.playCapture(world, A, pos, started, 1.2, { "hit", "hit" })
		local resolved = named(events, "CaptureResolved", A)[1].payload
		expect(resolved.success).toBe(true)
		expect(resolved.mutation).toBe("Standard")
	end)

	it("garde mutation et apparence identiques après reconnexion", function()
		local world = Fixtures.world(73, nil, { mutations = forced("Chromatic") })
		world:addPlayer(A, 0, Fixtures.veteran())
		local _, resolved = captureOne(world, A, 10)
		local saved = ProfileSchema.deepCopy(world:getProfile(A))
		world:removePlayer(A, 20)

		local other = Fixtures.world(74, nil, { mutations = forced("Standard") })
		other:addPlayer(A, 0, saved)
		local restored = other:inventoryOf(A):specimen(resolved.specimen.id)
		expect(restored.mutation).toBe("Chromatic")
		local species = Fixtures.MimicCatalog.get(restored.speciesId)
		expect(SpecimenLook.compute(species, restored.seed, restored.mutation)).toEqual(
			SpecimenLook.compute(species, resolved.specimen.seed, resolved.specimen.mutation)
		)
	end)

	it("ne permet au client aucun choix de mutation (aucune entrée client n'y touche)", function()
		-- Les seules entrées client d'une capture sont l'identifiant du Mimic et le temps des
		-- impulsions : même des arguments supplémentaires sont ignorés par le serveur.
		local world = Fixtures.world(75, nil, { mutations = forced("Standard") })
		world:addPlayer(A, 0, Fixtures.veteran())
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		local _, started = (world.startCapture :: any)(world, A, pos, record.id, 1.2, "Spectral")
		local events = Fixtures.playCapture(world, A, pos, started, 1.2, { "hit", "hit" })
		expect(named(events, "CaptureResolved", A)[1].payload.mutation).toBe("Standard")
	end)
end)
