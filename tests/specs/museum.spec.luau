--[[
	Musées (V0.3) : parcelles, vitrines, styles, visites — par le vrai MuseumCore au-dessus du
	vrai HuntWorld (collections réelles), sans Roblox.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local MuseumCore = Loader.server("Core/MuseumCore")
local MuseumLayout = Loader.server("Map/MuseumLayout")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local named = Fixtures.named
local A, B, C = 701, 702, 703

-- Profil d'un joueur qui possède des exemplaires (dont un Chromatic et un Spectral).
local function profileWith(userId, list)
	local profile = ProfileSchema.new(0)
	profile.tutorialDone = true
	for i, spec in list do
		local id = ProfileSchema.specimenId(userId, i)
		profile.specimens[id] = {
			id = id,
			speciesId = spec[1],
			rarity = Fixtures.MimicCatalog.get(spec[1]).rarity,
			mutation = spec[2] or "Standard",
			seed = 1000 + i,
			acquiredAt = i,
			favorite = false,
		}
		profile.codex[spec[1]] =
			{ discoveredAt = 0, order = i, captured = 1, mutations = { [spec[2] or "Standard"] = true } }
	end
	profile.nextSerial = #list + 1
	return profile
end

local function setup(seed)
	local world = Fixtures.world(seed or 90)
	local core = MuseumCore.new({ world = world, layout = MuseumLayout, config = Fixtures.config() })
	return world, core
end

local function join(world, core, userId, profile)
	world:addPlayer(userId, 0, profile or profileWith(userId, { { "chairy" } }))
	return core:join(userId, 0)
end

describe("Musées — parcelles", function()
	it("attribue une parcelle et construit le musée à l'arrivée", function()
		local world, core = setup()
		local events = join(world, core, A)
		expect(core:plotOf(A)).toBe(1)
		local render = named(events, "_MuseumRender")[1]
		expect(render.payload.plot).toBe(1)
		expect(render.payload.ownerId).toBe(A)
		expect(#render.payload.slots).toBe(6)
		expect(named(events, "MuseumInfo", A)[1].payload.plot).toBe(1)
	end)

	it("libère la parcelle au départ et la donne au premier joueur en attente", function()
		local world, core = setup()
		for userId = 1, 8 do
			join(world, core, userId)
		end
		local waitingEvents = join(world, core, 99)
		expect(core:plotOf(99)).toBeNil()
		expect(named(waitingEvents, "MuseumInfo", 99)[1].payload.waiting).toBe(true)
		-- Le jeu reste jouable : le joueur en attente peut aller au village.
		local _, reply = core:travel(99, "village", nil, 1)
		expect(reply.ok).toBe(true)
		local plotOf3 = core:plotOf(3)
		local events = core:leave(3, 2)
		expect(named(events, "_MuseumClear")[1].payload.plot).toBe(plotOf3)
		expect(core:plotOf(99)).toBe(plotOf3)
		expect(named(events, "_MuseumRender")[1].payload.ownerId).toBe(99)
		expect(named(events, "MuseumInfo", 99)[1].payload.plot).toBe(plotOf3)
	end)

	it("ne donne jamais la même parcelle à deux joueurs", function()
		local world, core = setup()
		local seen = {}
		for userId = 1, 8 do
			join(world, core, userId)
			local plot = core:plotOf(userId)
			expect(seen[plot]).toBeNil()
			seen[plot] = true
		end
	end)
end)

describe("Musées — déplacements", function()
	it("emmène à sa base, au village, ou au musée d'un joueur présent", function()
		local world, core = setup()
		join(world, core, A)
		join(world, core, B)
		local events, reply = core:travel(A, "base", nil, 1)
		expect(reply.ok).toBe(true)
		expect(named(events, "_Teleport", A)[1].payload.plot).toBe(core:plotOf(A))
		_, reply = core:travel(A, "museum", B, 5)
		expect(reply.plot).toBe(core:plotOf(B))
		_, reply = core:travel(A, "museum", 424242, 9)
		expect(reply.reason).toBe("UnknownMuseum")
		_, reply = core:travel(A, "teleport-anywhere", nil, 13)
		expect(reply.reason).toBe("BadInput")
	end)

	it("limite le spam de déplacements", function()
		local world = Fixtures.world(91, { RateLimits = { Travel = { capacity = 2, refillPerSecond = 0.1 } } })
		local core = MuseumCore.new({
			world = world,
			layout = MuseumLayout,
			config = Fixtures.config({ RateLimits = { Travel = { capacity = 2, refillPerSecond = 0.1 } } }),
		})
		join(world, core, A)
		local refused = 0
		for i = 1, 10 do
			local _, reply = core:travel(A, "base", nil, i * 0.01)
			if not reply.ok and reply.reason == "RateLimited" then
				refused += 1
			end
		end
		expect(refused).toBe(8)
	end)
end)

describe("Musées — vitrines", function()
	local function chromaProfile(userId)
		return profileWith(userId, { { "chairy" }, { "lumino", "Chromatic" }, { "posty", "Spectral" } })
	end

	it("expose un exemplaire possédé sans rien créer dans la collection", function()
		local world, core = setup()
		join(world, core, A, chromaProfile(A))
		local collection = world:inventoryOf(A)
		local owned, total = collection:owned(), collection:totalCaptures()
		local events, reply = core:setExhibit(A, 2, "S701-2", 1)
		expect(reply.ok).toBe(true)
		expect(collection:owned()).toBe(owned)
		expect(collection:totalCaptures()).toBe(total)
		local render = named(events, "_MuseumRender")[1].payload
		expect(render.slots[2].id).toBe("S701-2")
		expect(render.slots[2].mutation).toBe("Chromatic")
		expect(render.slots[2].seed).toBe(1002)
		expect(#named(events, "_ProfileChanged", A)).toBe(1)
		-- Premier Mimic exposé : objectif « Première vitrine » (socles Étoilés débloqués).
		expect(table.find(reply.completed, "first_exhibit") ~= nil).toBe(true)
	end)

	it("refuse un exemplaire non possédé (y compris celui d'un autre joueur)", function()
		local world, core = setup()
		join(world, core, A, chromaProfile(A))
		join(world, core, B, chromaProfile(B))
		local _, reply = core:setExhibit(A, 1, "S702-2", 1)
		expect(reply.ok).toBe(false)
		expect(reply.reason).toBe("NotOwned")
		_, reply = core:setExhibit(A, 1, "S701-999", 2)
		expect(reply.reason).toBe("NotOwned")
		_, reply = core:setExhibit(A, 7, "S701-1", 3)
		expect(reply.reason).toBe("BadSlot")
		_, reply = core:setExhibit(A, 1.5, "S701-1", 4)
		expect(reply.reason).toBe("BadSlot")
	end)

	it("refuse d'exposer le même exemplaire dans deux vitrines", function()
		local world, core = setup()
		join(world, core, A, chromaProfile(A))
		core:setExhibit(A, 1, "S701-1", 1)
		local _, reply = core:setExhibit(A, 4, "S701-1", 2)
		expect(reply.ok).toBe(false)
		expect(reply.reason).toBe("AlreadyExhibited")
		-- Réexposer au même endroit ne change rien.
		_, reply = core:setExhibit(A, 1, "S701-1", 3)
		expect(reply.ok).toBe(true)
	end)

	it("remplace, retire et réorganise les vitrines", function()
		local world, core = setup()
		join(world, core, A, chromaProfile(A))
		core:setExhibit(A, 1, "S701-1", 1)
		core:setExhibit(A, 1, "S701-3", 2) -- remplacement : S701-1 redevient libre
		local slots = world:inventoryOf(A):profile().museum.slots
		expect(slots[1]).toBe("S701-3")
		local _, reply = core:setExhibit(A, 2, "S701-1", 3)
		expect(reply.ok).toBe(true)
		core:moveExhibit(A, 1, 6, 4)
		expect(slots[1]).toBe("")
		expect(slots[6]).toBe("S701-3")
		core:setExhibit(A, 2, nil, 5)
		expect(slots[2]).toBe("")
		local _, bad = core:moveExhibit(A, 3, 3, 6)
		expect(bad.reason).toBe("BadSlot")
	end)

	it("ne laisse un visiteur rien modifier chez un autre", function()
		local world, core = setup()
		join(world, core, A, chromaProfile(A))
		join(world, core, B, chromaProfile(B))
		core:setExhibit(A, 1, "S701-2", 1)
		local before = table.clone(world:inventoryOf(A):profile().museum)
		-- B tente d'agir sur les exemplaires / le musée de A : ses requêtes ne portent que
		-- sur SA collection, et les identifiants de A ne lui appartiennent pas.
		core:setExhibit(B, 1, "S701-2", 2)
		core:setExhibit(B, 1, nil, 3)
		core:moveExhibit(B, 1, 2, 4)
		core:setStyle(B, "wall", "night", 5)
		local after = world:inventoryOf(A):profile().museum
		expect(after.slots[1]).toBe(before.slots[1])
		expect(after.wall).toBe(before.wall)
		expect(world:inventoryOf(A):specimen("S701-2") ~= nil).toBe(true)
		expect(world:inventoryOf(B):specimen("S701-2")).toBeNil()
	end)

	it("refuse toute modification tant que le profil n'est pas sûr", function()
		local world, core = setup()
		world:addPlayer(A, 0, nil, { ready = false, status = "Unavailable" })
		core:join(A, 0)
		local _, reply = core:setExhibit(A, 1, "S701-1", 1)
		expect(reply.reason).toBe("ProfileUnavailable")
	end)
end)

describe("Musées — styles", function()
	it("accepte les options gratuites, refuse les verrouillées et les inconnues", function()
		local world, core = setup()
		join(world, core, A)
		local events, reply = core:setStyle(A, "wall", "night", 1)
		expect(reply.ok).toBe(true)
		expect(named(events, "_MuseumRender")[1].payload.styles.wall).toBe("night")
		_, reply = core:setStyle(A, "pedestal", "pedestal_star", 2)
		expect(reply.reason).toBe("Locked")
		_, reply = core:setStyle(A, "wall", "gold", 3)
		expect(reply.reason).toBe("Locked")
		_, reply = core:setStyle(A, "roof", "red", 4)
		expect(reply.reason).toBe("BadKind")
		-- Après « Première vitrine », le socle Étoilé devient disponible.
		core:setExhibit(A, 1, "S701-1", 5)
		_, reply = core:setStyle(A, "pedestal", "pedestal_star", 6)
		expect(reply.ok).toBe(true)
	end)
end)

describe("Musées — visites", function()
	it("liste les musées présents avec leurs statistiques publiques", function()
		local world, core = setup()
		join(world, core, A, profileWith(A, { { "chairy" }, { "lumino", "Chromatic" }, { "posty", "Spectral" } }))
		join(world, core, B)
		core:setExhibit(A, 1, "S701-2", 1)
		core:setExhibit(A, 2, "S701-3", 2)
		core:setExhibit(A, 3, "S701-1", 3)
		local _, reply = core:list(B, 4)
		expect(#reply.entries).toBe(2)
		local entryA
		for _, entry in reply.entries do
			if entry.userId == A then
				entryA = entry
			end
		end
		expect(entryA.discovered).toBe(3)
		expect(entryA.exhibited).toBe(3)
		expect(entryA.mutationsExhibited).toBe(3)
		expect(entryA.mine).toBe(false)
	end)

	it("ne liste plus un joueur parti", function()
		local world, core = setup()
		join(world, core, A)
		join(world, core, B)
		join(world, core, C)
		core:leave(B, 1)
		world:removePlayer(B, 1)
		local _, reply = core:list(A, 2)
		expect(#reply.entries).toBe(2)
	end)
end)

describe("Musées — configuration des styles", function()
	local MuseumStyles = Loader.shared("Config/MuseumStyles")

	it("propose trois options gratuites par réglage, et une récompense verrouillée", function()
		for _, kind in MuseumStyles.Kinds do
			local free = 0
			for _, option in MuseumStyles.options(kind) do
				if not option.reward then
					free += 1
					expect(MuseumStyles.isAvailable(kind, option.id, nil)).toBe(true)
				end
			end
			expect(free).toBe(3)
			expect(MuseumStyles.get(kind, MuseumStyles.Defaults[kind]) ~= nil).toBe(true)
		end
		expect(MuseumStyles.isAvailable("pedestal", "pedestal_star", {})).toBe(false)
		expect(MuseumStyles.isAvailable("pedestal", "pedestal_star", { pedestal_star = true })).toBe(true)
		expect(MuseumStyles.isAvailable("wall", 12, nil)).toBe(false)
	end)

	it("retombe sur l'option par défaut pour une valeur inconnue", function()
		expect(MuseumStyles.resolve("wall", "gold").id).toBe("lilac")
		expect(MuseumStyles.resolve("theme", nil).id).toBe("mystic")
		expect(MuseumStyles.resolve("lighting", "aurora").id).toBe("aurora")
	end)

	it("relie la récompense du socle Étoilé à un objectif", function()
		local Objectives = Loader.shared("Config/Objectives")
		local found = false
		for _, objective in Objectives.list() do
			if objective.reward.id == "pedestal_star" then
				found = objective.reward.kind == "pedestal"
			end
		end
		expect(found).toBe(true)
	end)
end)

describe("Musées — correctifs de l'audit V0.3.1", function()
	it("refuse un déplacement rapide pendant une capture", function()
		local world, core = setup()
		join(world, core, A)
		join(world, core, B)
		world.isCapturing = function(_, userId)
			return userId == A
		end
		local _, reply = core:travel(A, "village", nil, 1)
		expect(reply.reason).toBe("Capturing")
		_, reply = core:travel(B, "village", nil, 1)
		expect(reply.ok).toBe(true)
	end)

	it("garde la liste des musées disponible après une rafale d'actions d'exposition", function()
		local world, core = setup()
		join(world, core, A)
		-- Limites réelles (les tests fonctionnels les assouplissent).
		core._limiter = Loader.server("Core/RateLimiter").new(Fixtures.GameConfig.RateLimits)
		local limited = false
		for i = 1, 12 do
			local _, styleReply = core:setStyle(A, "wall", "mint", 1 + i * 0.01)
			limited = limited or styleReply.reason == "RateLimited"
		end
		expect(limited).toBe(true)
		local _, reply = core:list(A, 1.2)
		expect(reply.reason).toBeNil()
	end)
end)
