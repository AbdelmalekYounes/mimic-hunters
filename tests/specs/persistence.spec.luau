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
