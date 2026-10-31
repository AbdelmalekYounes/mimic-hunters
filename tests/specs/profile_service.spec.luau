local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ProfileService = Loader.server("Core/ProfileService")
local MemoryBackend = Loader.server("Core/MemoryBackend")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local USER = 501

-- Horloge simulée : `wait` avance le temps au lieu de bloquer, `spawn` exécute tout de suite.
local function environment()
	local env = { t = 10000, waited = 0, logs = {}, lost = {} }
	function env.clock()
		return env.t
	end
	function env.wait(seconds)
		env.t += seconds
		env.waited += seconds
	end
	function env.spawn(fn)
		fn()
	end
	return env
end

local function service(backend, env, jobId)
	return ProfileService.new({
		backend = backend,
		jobId = jobId or "jobA",
		clock = env.clock,
		wait = env.wait,
		spawn = env.spawn,
		log = function(message)
			table.insert(env.logs, message)
		end,
		onLost = function(userId)
			table.insert(env.lost, userId)
		end,
	})
end

local function profileWith(captures)
	local profile = ProfileSchema.new(0)
	profile.stats.totalCaptures = captures
	return profile
end

describe("ProfileService — transformations", function()
	it("pose le verrou sur un profil libre", function()
		local record, outcome = ProfileService.acquireTransform(nil, "jobA", "s1", 100, 360)
		expect(outcome).toBe("Acquired")
		expect(record.meta.lock.sessionId).toBe("s1")
	end)

	it("refuse un verrou frais d'un autre serveur, reprend un verrou périmé", function()
		local held = { data = {}, meta = { lock = { jobId = "jobB", sessionId = "s9", at = 100 } } }
		local record, outcome = ProfileService.acquireTransform(ProfileSchema.deepCopy(held), "jobA", "s1", 200, 360)
		expect(record).toBeNil()
		expect(outcome).toBe("Locked")
		local _, stale = ProfileService.acquireTransform(ProfileSchema.deepCopy(held), "jobA", "s1", 100 + 361, 360)
		expect(stale).toBe("Stolen")
	end)

	it("n'écrit que si le verrou est toujours le nôtre", function()
		local held = { data = { v = 1 }, meta = { lock = { jobId = "jobB", sessionId = "s9", at = 100 } } }
		local record, outcome = ProfileService.commitTransform(held, "s1", { v = 2 }, 150, false)
		expect(record).toBeNil()
		expect(outcome).toBe("LockLost")
		local saved, ok = ProfileService.commitTransform(held, "s9", { v = 2 }, 150, true)
		expect(ok).toBe("Saved")
		expect(saved.data.v).toBe(2)
		expect(saved.meta.lock).toBeNil()
	end)
end)

describe("ProfileService — cycle de vie", function()
	it("charge un nouveau joueur, sauvegarde, libère, recharge", function()
		local backend, env = MemoryBackend.new(), environment()
		local s = service(backend, env)
		local status, data = s:load(USER)
		expect(status).toBe("Ready")
		expect(data).toBeNil()
		expect(backend:peek("player_501").meta.lock ~= nil).toBe(true)

		expect(s:release(USER, profileWith(3))).toBe(true)
		local stored = backend:peek("player_501")
		expect(stored.data.stats.totalCaptures).toBe(3)
		expect(stored.meta.lock).toBeNil()

		local again, loaded = service(backend, env, "jobB"):load(USER)
		expect(again).toBe("Ready")
		expect(loaded.stats.totalCaptures).toBe(3)
	end)

	it("bloque un second serveur tant que le premier tient la session", function()
		local backend, env = MemoryBackend.new(), environment()
		local a, b = service(backend, env, "jobA"), service(backend, env, "jobB")
		a:load(USER)
		a:save(USER, profileWith(1))
		local status = b:load(USER)
		expect(status).toBe("Locked")
		-- B a patienté puis abandonné, sans rien écrire.
		expect(env.waited).toBeAtLeast(ProfileService.DefaultConfig.LockedRetries * 5)
		expect(backend:peek("player_501").data.stats.totalCaptures).toBe(1)

		a:release(USER, profileWith(2))
		local retry, data = b:load(USER)
		expect(retry).toBe("Ready")
		expect(data.stats.totalCaptures).toBe(2)
	end)

	it("reprend la session d'un serveur arrêté brutalement, et l'ancien ne peut plus écrire", function()
		local backend, env = MemoryBackend.new(), environment()
		local a, b = service(backend, env, "jobA"), service(backend, env, "jobB")
		a:load(USER)
		a:save(USER, profileWith(5))
		-- jobA « plante » : plus de sauvegarde. Le verrou devient périmé.
		env.t += ProfileService.DefaultConfig.LockTimeout + 1
		local status, data = b:load(USER)
		expect(status).toBe("Ready")
		expect(data.stats.totalCaptures).toBe(5)
		b:save(USER, profileWith(6))

		-- jobA revient (serveur figé puis réveillé) : sa sauvegarde est refusée.
		env.t += 10
		expect(a:save(USER, profileWith(99))).toBe(false)
		expect(a:status(USER)).toBe("Lost")
		expect(env.lost[1]).toBe(USER)
		expect(backend:peek("player_501").data.stats.totalCaptures).toBe(6)
	end)

	it("permet une reconnexion rapide sur le même serveur", function()
		local backend, env = MemoryBackend.new(), environment()
		local s = service(backend, env)
		s:load(USER)
		s:release(USER, profileWith(4))
		local status, data = s:load(USER)
		expect(status).toBe("Ready")
		expect(data.stats.totalCaptures).toBe(4)
	end)

	it("libère sans écraser quand aucune donnée sûre n'existe", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:poke("player_501", { data = { schemaVersion = 99, secret = true }, meta = {} })
		local s = service(backend, env)
		local status, data = s:load(USER)
		expect(status).toBe("Ready")
		expect(data.schemaVersion).toBe(99)
		s:release(USER, nil)
		local stored = backend:peek("player_501")
		expect(stored.data.secret).toBe(true)
		expect(stored.meta.lock).toBeNil()
	end)
end)

describe("ProfileService — pannes et limites", function()
	it("réessaie après des erreurs passagères du stockage", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:failNext(3)
		local status = service(backend, env):load(USER)
		expect(status).toBe("Ready")
		-- Délais croissants : 1 + 2 + 4 s.
		expect(env.waited).toBe(7)
	end)

	it("abandonne proprement si le stockage reste en panne", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:failNext(100)
		local status, data = service(backend, env):load(USER)
		expect(status).toBe("Unavailable")
		expect(data).toBeNil()
	end)

	it("garde la modification en attente quand une sauvegarde échoue, puis la réussit", function()
		local backend, env = MemoryBackend.new(), environment()
		local s = service(backend, env)
		s:load(USER)
		local profile = profileWith(1)
		s:markDirty(USER, true)
		backend:failNext(ProfileService.DefaultConfig.MaxRetries)
		env.t += 10
		s:step(function()
			return profile
		end)
		expect(backend:peek("player_501").data).toBeNil()
		-- Sauvegarde suivante : le stockage répond de nouveau.
		env.t += 10
		s:step(function()
			return profile
		end)
		expect(backend:peek("player_501").data.stats.totalCaptures).toBe(1)
	end)

	it("attend le budget de requêtes avant d'écrire", function()
		local backend, env = MemoryBackend.new(), environment()
		backend:setBudget(0)
		local s = service(backend, env)
		local status = s:load(USER)
		-- Budget épuisé : ~10 s d'attente, puis la requête part quand même (Roblox la met en file).
		expect(status).toBe("Ready")
		expect(env.waited).toBe(10)
	end)
end)

describe("ProfileService — planification", function()
	it("sauvegarde vite une modification importante, sinon toutes les 60 s", function()
		local backend, env = MemoryBackend.new(), environment()
		local s = service(backend, env)
		s:load(USER)
		local profile = profileWith(0)
		local function step()
			s:step(function()
				return profile
			end)
		end
		local writes = backend.writes
		step()
		expect(backend.writes).toBe(writes) -- rien de dû

		profile.stats.totalCaptures = 1
		s:markDirty(USER, true)
		env.t += 3
		step()
		expect(backend.writes).toBe(writes) -- intervalle minimal (7 s) pas encore écoulé
		env.t += 5
		step()
		expect(backend.writes).toBe(writes + 1)
		expect(backend:peek("player_501").data.stats.totalCaptures).toBe(1)

		s:markDirty(USER, false) -- favori : attendra la sauvegarde périodique
		env.t += 30
		step()
		expect(backend.writes).toBe(writes + 1)
		env.t += 31
		step()
		expect(backend.writes).toBe(writes + 2)
	end)

	it("libère toutes les sessions à la fermeture du serveur", function()
		local backend, env = MemoryBackend.new(), environment()
		local s = service(backend, env)
		for userId = 1, 3 do
			s:load(userId)
		end
		s:closeAll(function(userId)
			return profileWith(userId)
		end)
		for userId = 1, 3 do
			local stored = backend:peek("player_" .. userId)
			expect(stored.data.stats.totalCaptures).toBe(userId)
			expect(stored.meta.lock).toBeNil()
			expect(s:status(userId)).toBeNil()
		end
	end)
end)
