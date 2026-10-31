--[[
	Museum Hunt (V0.3, jalon 6) : déroulement complet et anti-abus, par le vrai MuseumCore.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local MuseumCore = Loader.server("Core/MuseumCore")
local MuseumLayout = Loader.server("Map/MuseumLayout")
local ProfileSchema = Loader.server("Core/ProfileSchema")
local Rng = Loader.shared("Logic/Rng")

local named = Fixtures.named
local OWNER, VISITOR, OTHER = 801, 802, 803
local RULES = Fixtures.GameConfig.MuseumHunt

local function profileWith(userId, list, exhibit)
	local profile = ProfileSchema.new(0)
	profile.tutorialDone = true
	for i, spec in list do
		local id = ProfileSchema.specimenId(userId, i)
		profile.specimens[id] = {
			id = id,
			speciesId = spec[1],
			rarity = Fixtures.MimicCatalog.get(spec[1]).rarity,
			mutation = spec[2] or "Standard",
			seed = 700 + i,
			acquiredAt = i,
			favorite = false,
		}
		profile.codex[spec[1]] =
			{ discoveredAt = 0, order = i, captured = 1, mutations = { [spec[2] or "Standard"] = true } }
		if exhibit then
			profile.museum.slots[i] = id
		end
	end
	profile.nextSerial = #list + 1
	return profile
end

local function setup(seed)
	local config = Fixtures.config()
	local world = Fixtures.world(seed or 120)
	local core = MuseumCore.new({
		world = world,
		layout = MuseumLayout,
		config = config,
		catalog = Fixtures.MimicCatalog,
		rng = Rng.new(seed or 120),
	})
	world:addPlayer(
		OWNER,
		0,
		profileWith(OWNER, { { "chairy" }, { "lumino", "Chromatic" }, { "posty", "Spectral" } }, true)
	)
	core:join(OWNER, 0)
	world:addPlayer(VISITOR, 0, profileWith(VISITOR, { { "trashling" } }))
	core:join(VISITOR, 0)
	return world, core
end

local function signOf(core, userId)
	return MuseumLayout.toWorld(core:plotOf(userId), MuseumLayout.HuntSign)
end

local function spotOf(_core, hunt, entry)
	return MuseumLayout.toWorld(hunt.plot, MuseumLayout.HuntSpots[entry.spot])
end

local function start(core, now)
	return core:startHunt(VISITOR, OWNER, signOf(core, OWNER), now or 1)
end

-- Session interne (pour savoir où sont les copies : connu du serveur seulement).
local function session(core)
	return core:huntOf(VISITOR)
end

describe("Museum Hunt — lancement", function()
	it("refuse les lancements invalides", function()
		local world, core = setup()
		local _, reply = core:startHunt(VISITOR, VISITOR, signOf(core, VISITOR), 1)
		expect(reply.reason).toBe("OwnMuseum")
		_, reply = core:startHunt(VISITOR, 4242, signOf(core, OWNER), 2)
		expect(reply.reason).toBe("UnknownMuseum")
		_, reply = core:startHunt(VISITOR, "OWNER", signOf(core, OWNER), 3)
		expect(reply.reason).toBe("BadInput")
		_, reply = core:startHunt(VISITOR, OWNER, { X = 0, Y = 0, Z = 0 }, 4)
		expect(reply.reason).toBe("OutOfRange")
		_, reply = core:startHunt(VISITOR, OWNER, nil, 5)
		expect(reply.reason).toBe("NoCharacter")
		-- Musée sans aucun Mimic : rien à cacher.
		world:addPlayer(OTHER, 0, ProfileSchema.new(0))
		core:join(OTHER, 0)
		_, reply = core:startHunt(VISITOR, OTHER, signOf(core, OTHER), 6)
		expect(reply.reason).toBe("EmptyMuseum")
	end)

	it("cache 3 copies et 5 leurres sans jamais révéler lesquels au client", function()
		local _, core = setup()
		local events, reply = start(core)
		expect(reply.ok).toBe(true)
		expect(reply.total).toBe(3)
		local spawn = named(events, "_HuntSpawn")[1].payload
		expect(#spawn.props).toBe(8)
		for _, prop in spawn.props do
			expect(prop.copy).toBeNil()
			expect(prop.speciesId).toBeNil()
		end
		-- Le propriétaire est prévenu ; aucune information sur les cachettes ne lui est envoyée.
		expect(named(events, "HuntUpdate", OWNER)[1].payload.phase).toBe("visitorStart")
		local hunt = session(core)
		local copies = 0
		for _, entry in hunt.props do
			if entry.copy then
				copies += 1
			end
		end
		expect(copies).toBe(3)
	end)

	it("dérive les copies des exemplaires exposés, avec leur apparence exacte", function()
		local world, core = setup()
		start(core)
		local exhibited = {}
		for _, specimen in world:inventoryOf(OWNER):museumView().slots do
			if specimen then
				exhibited[specimen.seed] = specimen
			end
		end
		for _, entry in session(core).props do
			if entry.copy then
				local original = exhibited[entry.copy.seed]
				expect(original ~= nil).toBe(true)
				expect(entry.copy.mutation).toBe(original.mutation)
				expect(entry.kind).toBe(Fixtures.MimicCatalog.get(original.speciesId).kind)
			end
		end
	end)

	it("empêche les défis concurrents incohérents", function()
		local world, core = setup()
		world:addPlayer(OTHER, 0, profileWith(OTHER, { { "vendoo" } }, true))
		core:join(OTHER, 0)
		start(core)
		-- Un second visiteur dans le même musée : occupé.
		local _, busy = core:startHunt(OTHER, OWNER, signOf(core, OWNER), 2)
		expect(busy.reason).toBe("Busy")
		-- Le même visiteur ailleurs : déjà en chasse.
		local _, again = core:startHunt(VISITOR, OTHER, signOf(core, OTHER), 3)
		expect(again.reason).toBe("AlreadyHunting")
		local _, list = core:list(OTHER, 4)
		for _, entry in list.entries do
			if entry.userId == OWNER then
				expect(entry.busy).toBe(true)
			end
		end
	end)
end)

describe("Museum Hunt — déroulement", function()
	it("guide le scanner selon la copie la plus proche", function()
		local _, core = setup()
		start(core)
		local hunt = session(core)
		local copy
		for _, entry in hunt.props do
			if entry.copy then
				copy = entry
			end
		end
		local events, reply = core:huntScan(VISITOR, spotOf(core, hunt, copy), 2)
		expect(reply.band).toBe("Strong")
		expect(named(events, "Clue", VISITOR)[1].payload.propId).toBe(copy.propId)
		local _, cooldown = core:huntScan(VISITOR, spotOf(core, hunt, copy), 2.5)
		expect(cooldown.reason).toBe("Cooldown")
		local far = { X = spotOf(core, hunt, copy).X + 60, Y = 0, Z = spotOf(core, hunt, copy).Z }
		local _, none = core:huntScan(VISITOR, far, 6)
		expect(none.band).toBe("None")
	end)

	it("joue une partie complète : ratés, trouvailles, score, record", function()
		local world, core = setup()
		start(core, 1)
		local hunt = session(core)
		local now = 2
		local decoy
		for _, entry in hunt.props do
			if not entry.copy then
				decoy = entry
			end
		end
		local missEvents, miss = core:huntInspect(VISITOR, spotOf(core, hunt, decoy), decoy.propId, now)
		expect(miss.result).toBe("Ordinary")
		expect(miss.kind).toBe(decoy.kind)
		expect(named(missEvents, "HuntUpdate", VISITOR)[1].payload.misses).toBe(1)
		local last
		for _, entry in hunt.props do
			if entry.copy then
				now += 2
				local events, reply = core:huntInspect(VISITOR, spotOf(core, hunt, entry), entry.propId, now)
				expect(reply.result).toBe("HuntFound")
				expect(#named(events, "_HuntRemoveProp")).toBe(1)
				last = events
			end
		end
		local finished = named(last, "HuntUpdate", VISITOR)
		local result = finished[#finished].payload
		expect(result.phase).toBe("end")
		expect(result.reason).toBe("Complete")
		expect(result.found).toBe(3)
		local remaining = hunt.endsAt - now
		expect(result.score).toBe(
			3 * RULES.FoundPoints - RULES.MissPenalty + math.floor(remaining * RULES.TimeBonusPerSecond)
		)
		expect(result.newRecord).toBe(true)
		expect(result.museums).toBe(1)
		expect(named(last, "HuntUpdate", OWNER)[1].payload.phase).toBe("visitorEnd")
		local hunts = world:inventoryOf(VISITOR):profile().hunts
		expect(hunts.best).toBe(result.score)
		expect(hunts.completed).toBe(1)
		expect(core:huntOf(VISITOR)).toBeNil()
	end)

	it("vérifie la portée, les cachettes inventées et les cachettes déjà trouvées", function()
		local _, core = setup()
		start(core)
		local hunt = session(core)
		local copy
		for _, entry in hunt.props do
			if entry.copy then
				copy = entry
			end
		end
		local farAway = { X = 0, Y = 0, Z = 0 }
		local _, out = core:huntInspect(VISITOR, farAway, copy.propId, 2)
		expect(out.reason).toBe("OutOfRange")
		local _, fake = core:huntInspect(VISITOR, spotOf(core, hunt, copy), "MH999-1", 3)
		expect(fake.reason).toBe("UnknownMimic")
		local _, wrongType = core:huntInspect(VISITOR, spotOf(core, hunt, copy), { copy.propId }, 4)
		expect(wrongType.reason).toBe("UnknownMimic")
		core:huntInspect(VISITOR, spotOf(core, hunt, copy), copy.propId, 5)
		local _, twice = core:huntInspect(VISITOR, spotOf(core, hunt, copy), copy.propId, 6)
		expect(twice.reason).toBe("UnknownMimic")
		expect(hunt.found).toBe(1)
	end)

	it("termine au temps imparti avec un score partiel", function()
		local world, core = setup()
		start(core, 1)
		local hunt = session(core)
		for _, entry in hunt.props do
			if entry.copy then
				core:huntInspect(VISITOR, spotOf(core, hunt, entry), entry.propId, 3)
				break
			end
		end
		local events = core:tick(1 + RULES.Duration + 0.1, {})
		local result = named(events, "HuntUpdate", VISITOR)[1].payload
		expect(result.reason).toBe("Timeout")
		expect(result.found).toBe(1)
		expect(result.score).toBe(RULES.FoundPoints)
		expect(#named(events, "_HuntDespawn")).toBe(1)
		expect(world:inventoryOf(VISITOR):profile().hunts.completed).toBe(0)
	end)

	it("n'envoie les indices des copies qu'au visiteur", function()
		local _, core = setup()
		start(core, 1)
		local clues = {}
		for t = 2, 20, 0.5 do
			for _, event in named(core:tick(t, {}), "Clue") do
				table.insert(clues, event)
			end
		end
		expect(#clues).toBeGreaterThan(2)
		local copies = {}
		for _, entry in session(core).props do
			if entry.copy then
				copies[entry.propId] = true
			end
		end
		for _, clue in clues do
			expect(clue.userId).toBe(VISITOR)
			expect(copies[clue.payload.propId]).toBe(true)
		end
	end)
end)

describe("Museum Hunt — départs et anti-abus", function()
	it("annule proprement si le propriétaire part (musée détruit), sans récompense", function()
		local world, core = setup()
		start(core, 1)
		local events = core:leave(OWNER, 5)
		local cancel = named(events, "HuntUpdate", VISITOR)[1].payload
		expect(cancel.phase).toBe("cancel")
		expect(cancel.reason).toBe("OwnerLeft")
		expect(#named(events, "_HuntDespawn")).toBe(1)
		expect(#named(events, "_MuseumClear")).toBe(1)
		expect(world:inventoryOf(VISITOR):profile().hunts.played).toBe(0)
		expect(core:huntOf(VISITOR)).toBeNil()
	end)

	it("annule si le visiteur part ou quitte le jardin", function()
		local _, core = setup()
		start(core, 1)
		local events = core:leave(VISITOR, 3)
		expect(named(events, "HuntUpdate", VISITOR)[1].payload.reason).toBe("VisitorLeft")

		local _, core2 = setup(121)
		start(core2, 1)
		local plot = core2:plotOf(OWNER)
		local zone = MuseumLayout.toWorld(plot, MuseumLayout.HuntZone.center)
		local outside = { X = zone.X + RULES.ZoneRadius + 5, Y = 0, Z = zone.Z }
		local tickEvents = core2:tick(4, { [VISITOR] = outside })
		expect(named(tickEvents, "HuntUpdate", VISITOR)[1].payload.reason).toBe("LeftZone")
	end)

	it("ne touche jamais aux vrais exemplaires du propriétaire", function()
		local world, core = setup()
		local owner = world:inventoryOf(OWNER)
		local before = ProfileSchema.deepCopy(owner:profile())
		start(core, 1)
		local hunt = session(core)
		for _, entry in hunt.props do
			core:huntInspect(VISITOR, spotOf(core, hunt, entry), entry.propId, 2 + entry.spot * 2)
		end
		core:tick(100, {})
		expect(owner:profile().specimens).toEqual(before.specimens)
		expect(owner:profile().museum).toEqual(before.museum)
		expect(world:inventoryOf(VISITOR):owned()).toBe(1)
	end)

	it(
		"limite la répétition : délai entre défis, un seul musée compté, record seulement s'il est battu",
		function()
			local world, core = setup()
			local now = 1
			local function playOnce(findAll)
				start(core, now)
				local hunt = session(core)
				for _, entry in hunt.props do
					if entry.copy then
						now += 1
						core:huntInspect(VISITOR, spotOf(core, hunt, entry), entry.propId, now)
						if not findAll then
							break
						end
					end
				end
				core:tick(now + RULES.Duration + 1, {})
				now += RULES.Duration + RULES.RepeatCooldown + 2
			end
			playOnce(true)
			local best = world:inventoryOf(VISITOR):profile().hunts.best
			-- Relancer 5 s après la fin du défi précédent : refusé.
			local _, early = start(core, core._lastHuntEnd[VISITOR] + 5)
			expect(early.reason).toBe("Cooldown")
			playOnce(false)
			playOnce(true)
			local hunts = world:inventoryOf(VISITOR):profile().hunts
			expect(hunts.played).toBe(3)
			expect(#hunts.museumOrder).toBe(1) -- toujours le même musée
			expect(hunts.best >= best).toBe(true)
			-- L'objectif « 3 musées différents » ne s'obtient pas en répétant le même défi.
			expect(world:inventoryOf(VISITOR):profile().objectives.museum_explorer).toBeNil()
		end
	)

	it("limite le spam de requêtes pendant un défi", function()
		local config = Fixtures.config({ RateLimits = { Hunt = { capacity = 3, refillPerSecond = 0.1 } } })
		local world = Fixtures.world(130)
		local core = MuseumCore.new({
			world = world,
			layout = MuseumLayout,
			config = config,
			catalog = Fixtures.MimicCatalog,
			rng = Rng.new(130),
		})
		world:addPlayer(OWNER, 0, profileWith(OWNER, { { "chairy" } }, true))
		core:join(OWNER, 0)
		world:addPlayer(VISITOR, 0, profileWith(VISITOR, { { "trashling" } }))
		core:join(VISITOR, 0)
		start(core, 1)
		local limited = 0
		for i = 1, 20 do
			local _, reply = core:huntInspect(VISITOR, signOf(core, OWNER), "MH1-1", 1 + i * 0.01)
			if reply.reason == "RateLimited" then
				limited += 1
			end
		end
		expect(limited).toBeAtLeast(17)
	end)
end)

describe("Museum Hunt — correctifs de l'audit V0.3.1", function()
	it("envoie les objets triés par cachette : l'ordre ne désigne jamais les copies", function()
		for seed = 130, 140 do
			local _, core = setup(seed)
			local events = start(core)
			local props = named(events, "_HuntSpawn")[1].payload.props
			for i = 2, #props do
				expect(props[i].spot > props[i - 1].spot).toBe(true)
			end
		end
	end)

	it("donne aux leurres les types d'objet des copies", function()
		for seed = 130, 140 do
			local _, core = setup(seed)
			start(core)
			local hunt = session(core)
			local copyKinds = {}
			for _, entry in hunt.props do
				if entry.copy then
					copyKinds[entry.kind] = true
				end
			end
			for _, entry in hunt.props do
				expect(copyKinds[entry.kind]).toBe(true)
			end
		end
	end)

	it("applique le délai entre deux défis après une sortie du jardin", function()
		local _, core = setup()
		start(core, 1)
		local zone = MuseumLayout.toWorld(core:plotOf(OWNER), MuseumLayout.HuntZone.center)
		core:tick(4, { [VISITOR] = { X = zone.X + RULES.ZoneRadius + 5, Y = 0, Z = zone.Z } })
		local _, reply = start(core, 6)
		expect(reply.reason).toBe("Cooldown")
		_, reply = start(core, 4 + RULES.RepeatCooldown + 1)
		expect(reply.ok).toBe(true)
	end)

	it("refuse un musée sans vitrine, sans jamais révéler la collection privée", function()
		local world, core = setup()
		-- OTHER possède des Mimics mais n'en expose aucun.
		world:addPlayer(OTHER, 0, profileWith(OTHER, { { "chairy" }, { "posty", "Spectral" } }, false))
		core:join(OTHER, 0)
		local events, reply = core:startHunt(VISITOR, OTHER, signOf(core, OTHER), 1)
		expect(reply.reason).toBe("EmptyMuseum")
		expect(#named(events, "_HuntSpawn")).toBe(0)
	end)

	it("limite aussi les requêtes hors défi", function()
		local _, core = setup()
		-- Limites réelles (les tests fonctionnels les assouplissent).
		core._limiter = Loader.server("Core/RateLimiter").new(Fixtures.GameConfig.RateLimits)
		local limited = false
		for i = 1, 20 do
			local _, reply = core:huntInspect(VISITOR, signOf(core, OWNER), "MH1-1", 1 + i * 0.01)
			if reply.reason == "RateLimited" then
				limited = true
			end
		end
		expect(limited).toBe(true)
	end)
end)
