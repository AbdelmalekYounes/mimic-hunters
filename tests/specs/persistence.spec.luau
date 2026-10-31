--[[
	Intégration : HuntWorld (vraie chasse, vraies captures) + ProfileService (verrou, sauvegarde)
	sur un stockage simulé, avec plusieurs « serveurs » qui partagent ce stockage.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ProfileService = Loader.server("Core/ProfileService")
local MemoryBackend = Loader.server("Core/MemoryBackend")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local A = 9001
local named = Fixtures.named

local function environment()
	local env = { t = 50000 }
	function env.clock()
		return env.t
	end
	function env.wait(seconds)
		env.t += seconds
	end
	function env.spawn(fn)
		fn()
	end
	return env
end

local function service(backend, env, jobId)
	return ProfileService.new({
		backend = backend,
		jobId = jobId,
		clock = env.clock,
		wait = env.wait,
		spawn = env.spawn,
	})
end

-- Un « serveur » : un monde de chasse et son service de profils.
local function server(backend, env, jobId, seed)
	local world = Fixtures.world(seed, nil, { serverId = jobId, wallClock = env.clock })
	return { world = world, profiles = service(backend, env, jobId), jobId = jobId }
end

-- Le joueur arrive : chargement verrouillé, puis ajout au monde (comme HuntServer).
local function join(srv, userId)
	local status, data = srv.profiles:load(userId)
	if status == "Ready" then
		srv.world:addPlayer(userId, 0, data)
	else
		srv.world:addPlayer(userId, 0, nil, { ready = false, status = status })
	end
	return status
end

-- Transmet les demandes de sauvegarde internes, comme le dispatch de HuntServer.
local function forward(srv, events)
	for _, event in events do
		if event.name == "_ProfileChanged" then
			srv.profiles:markDirty(event.userId, event.payload.important)
		end
	end
end

local function leave(srv, userId)
	local data = srv.world:getProfile(userId)
	srv.world:removePlayer(userId, 0)
	return srv.profiles:release(userId, data)
end

-- Capture complète d'un Mimic partagé ; retourne le résultat de capture.
local function capture(srv, userId, startAt)
	local world = srv.world
	local record = assert(Fixtures.findHidden(world), "aucun Mimic caché")
	local position = Fixtures.near(world, record.slotId)
	local _, inspected = world:inspect(userId, position, record.slotId, startAt)
	assert(inspected.result == "Mimic", "examen : " .. tostring(inspected.result))
	local startEvents, started = world:startCapture(userId, position, record.id, startAt + 0.1)
	if not started.ok then
		return nil, started.reason, startEvents
	end
	local events = Fixtures.playCapture(world, userId, position, started, startAt + 0.1, { "hit", "hit" })
	forward(srv, events)
	local resolved = named(events, "CaptureResolved", userId)[1]
	return resolved and resolved.payload, nil, events
end

describe("Persistance — bout en bout", function()
	it("conserve exemplaires, mutations et graines après reconnexion sur un autre serveur", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = server(backend, env, "job1", 31)
		expect(join(one, A)).toBe("Ready")
		local captured = {}
		for i = 1, 3 do
			local result = capture(one, A, i * 10)
			expect(result.success).toBe(true)
			table.insert(captured, result.specimen)
		end
		one.world:setFavorite(A, captured[2].id, true, 40)
		expect(leave(one, A)).toBe(true)

		local two = server(backend, env, "job2", 32)
		expect(join(two, A)).toBe("Ready")
		local collection = two.world:inventoryOf(A)
		expect(collection:owned()).toBe(3)
		for _, specimen in captured do
			local restored = collection:specimen(specimen.id)
			expect(restored ~= nil).toBe(true)
			expect(restored.mutation).toBe(specimen.mutation)
			expect(restored.seed).toBe(specimen.seed)
			expect(restored.speciesId).toBe(specimen.speciesId)
		end
		expect(collection:specimen(captured[2].id).favorite).toBe(true)
		expect(two.world:tutorialStepOf(A)).toBe("Done")
	end)

	it("sauvegarde chaque capture rapidement, avant même le départ du joueur", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = server(backend, env, "job1", 33)
		join(one, A)
		capture(one, A, 10)
		env.t += 8
		one.profiles:step(function(userId)
			return one.world:getProfile(userId)
		end)
		local stored = backend:peek("player_" .. A)
		expect(stored.data.stats.totalCaptures).toBe(1)
		expect(stored.meta.lock ~= nil).toBe(true) -- session toujours ouverte
	end)

	it("refuse toute capture tant que le profil n'est pas chargé de manière sûre", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:failNext(1000)
		local one = server(backend, env, "job1", 34)
		expect(join(one, A)).toBe("Unavailable")
		local result, reason = capture(one, A, 10)
		expect(result).toBeNil()
		expect(reason).toBe("ProfileUnavailable")
		-- Rien n'est écrit pour ce joueur.
		expect(one.world:getProfile(A)).toBeNil()

		-- Le stockage revient : le profil est rattaché et les captures reprennent.
		backend:failNext(0)
		local status, data = one.profiles:load(A)
		expect(status).toBe("Ready")
		local events = one.world:attachProfile(A, data, 20)
		expect(named(events, "ProfileStatus", A)[1].payload.status).toBe("Ready")
		local ok = capture(one, A, 30)
		expect(ok.success).toBe(true)
	end)

	it("bloque un second serveur pendant la session, puis lui transmet tout", function()
		local backend, env = MemoryBackend.new(), environment()
		local one, two = server(backend, env, "job1", 35), server(backend, env, "job2", 36)
		join(one, A)
		capture(one, A, 10)
		-- Le joueur apparaît sur job2 avant que job1 ait fini (changement de serveur rapide).
		expect(join(two, A)).toBe("Locked")
		local result, reason = capture(two, A, 10)
		expect(result).toBeNil()
		expect(reason).toBe("ProfileUnavailable")
		expect(two.world:getProfile(A)).toBeNil()

		leave(one, A)
		two.world:removePlayer(A, 0)
		expect(join(two, A)).toBe("Ready")
		expect(two.world:inventoryOf(A):owned()).toBe(1)
	end)

	it("arrête les acquisitions quand le verrou est perdu", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = server(backend, env, "job1", 37)
		local lost = false
		one.profiles._onLost = function(userId)
			lost = true
			one.world:setProfileLost(userId)
		end
		join(one, A)
		capture(one, A, 10)
		one.profiles:save(A, one.world:getProfile(A))
		-- job1 se fige ; le verrou expire et job2 reprend le profil.
		env.t += ProfileService.DefaultConfig.LockTimeout + 1
		local two = server(backend, env, "job2", 38)
		expect(join(two, A)).toBe("Ready")
		capture(two, A, 10)
		two.profiles:save(A, two.world:getProfile(A))

		-- job1 se réveille : sa sauvegarde est refusée, il ne peut plus rien accorder.
		expect(one.profiles:save(A, one.world:getProfile(A))).toBe(false)
		expect(lost).toBe(true)
		local _, reason = capture(one, A, 20)
		expect(reason).toBe("ProfileUnavailable")
		expect(backend:peek("player_" .. A).data.stats.totalCaptures).toBe(2)
	end)

	it("ne touche jamais à un profil d'une version plus récente", function()
		local backend, env = MemoryBackend.new(), environment()
		local future = { schemaVersion = ProfileSchema.Version + 1, futureField = "garder" }
		backend:poke("player_" .. A, { data = future, meta = {} })
		local one = server(backend, env, "job1", 39)
		join(one, A)
		expect(one.world:profileStatusOf(A)).toBe("FutureVersion")
		expect(one.world:getProfile(A)).toBeNil()
		local _, reason = capture(one, A, 10)
		expect(reason).toBe("ProfileUnavailable")
		leave(one, A)
		expect(backend:peek("player_" .. A).data.futureField).toBe("garder")
	end)

	it("garde des identifiants uniques sur toute la vie du profil", function()
		local backend, env = MemoryBackend.new(), environment()
		local seen = {}
		for session = 1, 3 do
			local srv = server(backend, env, "job" .. session, 40 + session)
			join(srv, A)
			for i = 1, 2 do
				local result = capture(srv, A, i * 10)
				expect(seen[result.specimen.id]).toBeNil()
				seen[result.specimen.id] = true
			end
			leave(srv, A)
		end
		local data = backend:peek("player_" .. A).data
		local count = 0
		for _ in data.specimens do
			count += 1
		end
		expect(count).toBe(6)
		expect(data.nextSerial).toBe(7)
	end)

	it("garde un profil migré depuis la V0.1", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:poke("player_" .. A, {
			data = {
				version = 1,
				tutorialDone = true,
				inventory = { version = 1, totalCaptures = 2, species = { lumino = { count = 2, discoveryOrder = 1 } } },
			},
			meta = {},
		})
		local one = server(backend, env, "job1", 44)
		join(one, A)
		expect(one.world:inventoryOf(A):count("lumino")).toBe(2)
		leave(one, A)
		local stored = backend:peek("player_" .. A).data
		expect(stored.schemaVersion).toBe(ProfileSchema.Version)
	end)
end)

describe("Persistance — musées", function()
	local MuseumCore = Loader.server("Core/MuseumCore")
	local MuseumLayout = Loader.server("Map/MuseumLayout")

	local function withMuseum(srv)
		srv.museum = MuseumCore.new({ world = srv.world, layout = MuseumLayout, config = Fixtures.config() })
		return srv
	end

	it("retrouve vitrines et styles après reconnexion sur un autre serveur", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = withMuseum(server(backend, env, "job1", 50))
		join(one, A)
		one.museum:join(A, 0)
		local ids = {}
		for i = 1, 3 do
			local result = capture(one, A, i * 10)
			table.insert(ids, result.specimen.id)
		end
		one.museum:setExhibit(A, 1, ids[3], 40)
		one.museum:setExhibit(A, 4, ids[1], 41)
		one.museum:moveExhibit(A, 4, 6, 42)
		one.museum:setStyle(A, "lighting", "aurora", 43)
		one.museum:leave(A, 44)
		expect(leave(one, A)).toBe(true)

		local two = withMuseum(server(backend, env, "job2", 51))
		join(two, A)
		local events = two.museum:join(A, 0)
		local render = Fixtures.named(events, "_MuseumRender")[1].payload
		expect(render.slots[1].id).toBe(ids[3])
		expect(render.slots[6].id).toBe(ids[1])
		expect(render.slots[4]).toBe(false)
		expect(render.styles.lighting).toBe("aurora")
		expect(render.slots[1].seed).toBe(two.world:inventoryOf(A):specimen(ids[3]).seed)
		-- Toujours le même nombre d'exemplaires : exposer n'en crée aucun.
		expect(two.world:inventoryOf(A):owned()).toBe(3)
	end)

	it("sauvegarde rapidement un changement de vitrine", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = withMuseum(server(backend, env, "job1", 52))
		join(one, A)
		one.museum:join(A, 0)
		local result = capture(one, A, 10)
		env.t += 8
		one.profiles:step(function(userId)
			return one.world:getProfile(userId)
		end)
		local events = one.museum:setExhibit(A, 2, result.specimen.id, 20)
		forward(one, events)
		env.t += 8
		one.profiles:step(function(userId)
			return one.world:getProfile(userId)
		end)
		expect(backend:peek("player_" .. A).data.museum.slots[2]).toBe(result.specimen.id)
	end)

	it("empêche un second serveur de modifier le musée pendant la session", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = withMuseum(server(backend, env, "job1", 53))
		local two = withMuseum(server(backend, env, "job2", 54))
		join(one, A)
		one.museum:join(A, 0)
		local result = capture(one, A, 10)
		expect(join(two, A)).toBe("Locked")
		two.museum:join(A, 0)
		local _, reply = two.museum:setExhibit(A, 1, result.specimen.id, 20)
		expect(reply.ok).toBe(false)
		expect(reply.reason).toBe("ProfileUnavailable")
		expect(two.world:getProfile(A)).toBeNil()
	end)

	it("migre un profil V0.2 stocké sans perdre aucun Mimic", function()
		local backend, env = MemoryBackend.new(), environment()
		local v2 = ProfileSchema.new(0)
		v2.schemaVersion = 2
		v2.museum = nil
		v2.hunts = nil
		v2.tutorialDone = true
		for i = 1, 4 do
			local id = ProfileSchema.specimenId(A, i)
			v2.specimens[id] = {
				id = id,
				speciesId = "vendoo",
				rarity = "Epic",
				mutation = if i == 2 then "Spectral" else "Standard",
				seed = i,
				acquiredAt = i,
				favorite = false,
			}
		end
		v2.nextSerial = 5
		backend:poke("player_" .. A, { data = v2, meta = {} })
		local one = withMuseum(server(backend, env, "job1", 55))
		join(one, A)
		expect(one.world:inventoryOf(A):owned()).toBe(4)
		local _, reply = one.museum:setExhibit(A, 1, ProfileSchema.specimenId(A, 2), 1)
		expect(reply.ok).toBe(true)
		leave(one, A)
		local stored = backend:peek("player_" .. A).data
		expect(stored.schemaVersion).toBe(3)
		local count = 0
		for _ in stored.specimens do
			count += 1
		end
		expect(count).toBe(4)
		expect(stored.museum.slots[1]).toBe(ProfileSchema.specimenId(A, 2))
	end)

	-- Scénarios 5 à 9 du jalon 2 (V0.3.1) en un aller-retour complet entre deux serveurs.
	it("conserve tout le profil entre deux serveurs : mutations, favoris, 6 vitrines, styles, objectifs", function()
		local backend, env = MemoryBackend.new(), environment()
		local stored = ProfileSchema.new(0)
		stored.tutorialDone = true
		-- Même espèce en trois mutations (scénario 5), plus trois autres exemplaires.
		local plan = {
			{ "chairy", "Standard" },
			{ "chairy", "Chromatic" },
			{ "chairy", "Spectral" },
			{ "lumino", "Standard" },
			{ "posty", "Chromatic" },
			{ "vendoo", "Standard" },
		}
		for i, spec in plan do
			local id = ProfileSchema.specimenId(A, i)
			stored.specimens[id] = {
				id = id,
				speciesId = spec[1],
				rarity = Fixtures.MimicCatalog.get(spec[1]).rarity,
				mutation = spec[2],
				seed = 1000 + i,
				acquiredAt = i,
				favorite = false,
			}
			stored.codex[spec[1]] = { discoveredAt = 0, order = i, captured = 1, mutations = { [spec[2]] = true } }
		end
		stored.nextSerial = #plan + 1
		stored.stats.totalCaptures = #plan
		stored.cosmetics.unlocked = { title_apprentice = true, color_mint = true, pedestal_star = true }
		stored.objectives.first_capture = 5
		backend:poke("player_" .. A, { data = stored, meta = {} })

		local one = withMuseum(server(backend, env, "job1", 60))
		join(one, A)
		one.museum:join(A, 0)
		local collection = one.world:inventoryOf(A)
		-- Favoris (scénario 6), six vitrines (7), quatre réglages de style (8).
		expect((collection:setFavorite(ProfileSchema.specimenId(A, 2), true))).toBe(true)
		expect((collection:setFavorite(ProfileSchema.specimenId(A, 5), true))).toBe(true)
		for slot = 1, 6 do
			local _, reply = one.museum:setExhibit(A, slot, ProfileSchema.specimenId(A, 7 - slot), slot)
			expect(reply.ok).toBe(true)
		end
		local styles = { wall = "night", lighting = "lantern", pedestal = "pedestal_star", theme = "lab" }
		for kind, id in styles do
			local _, reply = one.museum:setStyle(A, kind, id, 10)
			expect(reply.ok).toBe(true)
		end
		-- Cosmétiques équipés et statistiques de Museum Hunt (scénario 9).
		expect((collection:equip("title", "title_apprentice"))).toBe(true)
		expect((collection:equip("scannerColor", "color_mint"))).toBe(true)
		collection:recordHunt(4242, 260, 3, 3)
		one.museum:leave(A, 20)
		expect(leave(one, A)).toBe(true)

		local two = withMuseum(server(backend, env, "job2", 61))
		join(two, A)
		local profile = two.world:getProfile(A)
		for i, spec in plan do
			local specimen = profile.specimens[ProfileSchema.specimenId(A, i)]
			expect(specimen.speciesId).toBe(spec[1])
			expect(specimen.mutation).toBe(spec[2])
			expect(specimen.seed).toBe(1000 + i)
			expect(specimen.favorite).toBe(i == 2 or i == 5)
		end
		for slot = 1, 6 do
			expect(profile.museum.slots[slot]).toBe(ProfileSchema.specimenId(A, 7 - slot))
		end
		for kind, id in styles do
			expect(profile.museum[kind]).toBe(id)
		end
		expect(profile.objectives.first_capture).toBe(5)
		expect(profile.cosmetics.unlocked.pedestal_star).toBe(true)
		expect(profile.cosmetics.title).toBe("title_apprentice")
		expect(profile.cosmetics.scannerColor).toBe("color_mint")
		expect(profile.hunts.best).toBe(260)
		expect(profile.hunts.completed).toBe(1)
		expect(profile.hunts.museums["4242"]).toBeTruthy()
		expect(profile.nextSerial).toBe(#plan + 1)
	end)

	it("refuse toute capture tant que la sauvegarde est en panne prolongée", function()
		local backend, env = MemoryBackend.new(), environment()
		local one = server(backend, env, "job1", 62)
		join(one, A)
		local events = one.world:setSaveHealthy(A, false)
		expect(named(events, "ProfileStatus", A)[1].payload.status).toBe("Degraded")
		local result, reason = capture(one, A, 10)
		expect(result).toBeNil()
		expect(reason).toBe("SaveUnavailable")
		-- Le profil reste chargé (il sera sauvegardé dès que possible).
		expect(one.world:getProfile(A)).toBeTruthy()
		one.world:setSaveHealthy(A, true)
		local again = capture(one, A, 30)
		expect(again and again.success).toBe(true)
	end)
end)
