--[[
	Fiabilité des sauvegardes (V0.3.1, jalon 2) : accès concurrents reproduits avec un
	ordonnanceur coopératif (tâches qui s'entrelacent, horloge entière comme os.time,
	stockage qui cède la main). Chaque test correspond à un constat de docs/V031_AUDIT.md.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local Scheduler = require("../lib/Scheduler")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ProfileService = Loader.server("Core/ProfileService")
local MemoryBackend = Loader.server("Core/MemoryBackend")
local ProfileSchema = Loader.server("Core/ProfileSchema")

local USER = 7301
local KEY = "player_" .. USER

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
		onHealth = function(userId, healthy)
			table.insert(env.health, { userId = userId, healthy = healthy })
		end,
	})
end

local function profileWith(captures)
	local profile = ProfileSchema.new(0)
	profile.stats.totalCaptures = captures
	return profile
end

local function hasLog(env, pattern)
	for _, message in env.logs do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

describe("Sauvegardes — accès concurrents (audit V0.3.1)", function()
	it("P1 : un ancien chargement ne remplace jamais la session d'un nouveau", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		-- Profil existant, verrouillé par un autre serveur encore actif.
		memory:poke(KEY, {
			data = profileWith(5),
			meta = { hasData = true, lock = { jobId = "jobB", sessionId = "jobB:1", at = env.t } },
		})
		local backend = Scheduler.slowBackend(env, memory)
		local s = service(backend, env)
		local firstPresent, firstResult = true, nil
		local secondResult, secondData, secondSession
		env.run(function()
			-- 1er passage du joueur : profil verrouillé, nouvelles tentatives en cours…
			env.spawn(function()
				firstResult = s:load(USER, function()
					return firstPresent
				end)
			end)
			env.wait(3)
			-- … il part et revient aussitôt (nouvel objet Player) : second chargement.
			firstPresent = false
			env.spawn(function()
				secondResult, secondData, secondSession = s:load(USER, function()
					return true
				end)
			end)
			-- L'autre serveur libère enfin le profil.
			env.wait(4)
			local record = memory:peek(KEY)
			record.meta.lock = nil
			memory:poke(KEY, record)
		end)
		expect(firstResult).toBe("Cancelled")
		expect(secondResult).toBe("Ready")
		expect(secondData.stats.totalCaptures).toBe(5)
		-- Une seule session, celle du second chargement, qui détient bien le verrou.
		expect(s:sessionOf(USER)).toBe(secondSession)
		expect(memory:peek(KEY).meta.lock.sessionId).toBe(secondSession)
		-- Et elle sauvegarde normalement.
		local saved
		env.run(function()
			env.wait(8)
			saved = s:save(USER, profileWith(6), false)
		end)
		expect(saved).toBe(true)
		expect(memory:peek(KEY).data.stats.totalCaptures).toBe(6)
		expect(#env.lost).toBe(0)
	end)

	it("P1 : une libération ciblée ne touche pas la session d'un autre chargement", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local s = service(Scheduler.slowBackend(env, memory), env)
		local session
		env.run(function()
			local _, _, id = s:load(USER)
			session = id
			-- Une libération qui vise une autre session (ancien chargement) est ignorée.
			expect(s:release(USER, nil, "jobA:7301:999")).toBe(false)
		end)
		expect(s:sessionOf(USER)).toBe(session)
		expect(memory:peek(KEY).meta.lock.sessionId).toBe(session)
	end)

	it("P2 : départ puis fermeture du serveur : une seule libération, avec les données", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local s = service(Scheduler.slowBackend(env, memory), env)
		env.run(function()
			s:load(USER)
			s:save(USER, profileWith(1), false)
			env.wait(2)
			-- Le joueur part juste après une capture : la libération attend l'intervalle minimal.
			env.spawn(function()
				s:release(USER, profileWith(2))
			end)
			env.wait(1)
			-- Le serveur ferme pendant ce temps ; le joueur a déjà quitté le monde (données nil).
			s:closeAll(function()
				return nil
			end)
		end)
		local record = memory:peek(KEY)
		expect(record.data.stats.totalCaptures).toBe(2)
		expect(record.meta.lock).toBeNil()
		expect(#env.lost).toBe(0)
		expect(hasLog(env, "sauvegarde finale impossible")).toBe(false)
	end)

	it("P3 : la fermeture respecte son échéance même pendant une panne du stockage", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		-- DataStore lent (2 s par appel) et en panne pendant la fermeture.
		local backend = Scheduler.slowBackend(env, memory, 2)
		local s = service(backend, env)
		local started
		env.run(function()
			for i = 1, 3 do
				s:load(USER + i)
			end
			backend.failing = true
			started = env.clock()
			s:closeAll(function(userId)
				return profileWith(userId)
			end)
		end)
		-- `run` ne rend la main que lorsque TOUTES les tâches sont finies (libérations et
		-- réessais compris) : aucune ne doit continuer après l'échéance de 24 s (BindToClose
		-- accorde ≈ 30 s), à la latence d'un dernier appel près (2 s).
		expect(env.t - started <= ProfileService.DefaultConfig.CloseTimeout + 2).toBe(true)
		expect(hasLog(env, "sauvegarde finale impossible") or hasLog(env, "non libéré")).toBe(true)
	end)

	it("P7 : une écriture appliquée mais signalée en erreur n'est pas un verrou perdu", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local backend = Scheduler.slowBackend(env, memory)
		local s = service(backend, env)
		local ok
		env.run(function()
			s:load(USER)
			env.wait(8)
			-- La libération est appliquée (verrou retiré) mais la réponse se perd : nouvel essai.
			backend.failAfterCommit = 1
			ok = s:release(USER, profileWith(3))
		end)
		expect(ok).toBe(true)
		expect(#env.lost).toBe(0)
		local record = memory:peek(KEY)
		expect(record.data.stats.totalCaptures).toBe(3)
		expect(record.meta.lock).toBeNil()
	end)

	it("P6 : sauvegardes en échec répétées → acquisitions suspendues, puis reprises", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local backend = Scheduler.slowBackend(env, memory)
		local s = service(backend, env)
		env.run(function()
			s:load(USER)
			backend.failing = true
			env.wait(8)
			expect(s:save(USER, profileWith(1), false)).toBe(false)
			expect(#env.health).toBe(0) -- un échec isolé ne suffit pas
			env.wait(8)
			expect(s:save(USER, profileWith(1), false)).toBe(false)
			backend.failing = false
			env.wait(8)
			expect(s:save(USER, profileWith(2), false)).toBe(true)
		end)
		expect(#env.health).toBe(2)
		expect(env.health[1].healthy).toBe(false)
		expect(env.health[2].healthy).toBe(true)
		expect(memory:peek(KEY).data.stats.totalCaptures).toBe(2)
	end)
end)

describe("Sauvegardes — enregistrements illisibles (audit V0.3.1)", function()
	it("P4 : un enregistrement corrompu n'est jamais remplacé par un profil vide", function()
		for _, raw in { "texte", 42, { data = "texte", meta = {} }, { meta = { hasData = true, writes = 3 } } } do
			local env = Scheduler.new()
			local memory = MemoryBackend.new()
			memory:poke(KEY, raw)
			local s = service(Scheduler.slowBackend(env, memory), env)
			local status
			env.run(function()
				status = s:load(USER)
			end)
			expect(status).toBe("Corrupt")
			expect(memory.writes).toBe(0) -- rien n'a été écrit : l'enregistrement est intact
			expect(type(memory:peek(KEY))).toBe(type(raw))
			expect(s:sessionOf(USER)).toBeNil()
		end
	end)

	it("P4 : un joueur parti avant tout chargement (verrou libéré, sans données) reste neuf", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local s = service(Scheduler.slowBackend(env, memory), env)
		local status, data
		env.run(function()
			local _, _, id = s:load(USER)
			s:release(USER, nil, id) -- libération sans écrire (meta.writes = 1, pas de data)
			status, data = s:load(USER)
		end)
		expect(status).toBe("Ready")
		expect(data).toBeNil()
	end)

	it("P10 : stockage qui refuse tout : aucun profil chargé, rien n'est écrit", function()
		local env = Scheduler.new()
		local memory = MemoryBackend.new()
		local backend = Scheduler.slowBackend(env, memory)
		backend.failing = true
		local s = service(backend, env)
		local status
		env.run(function()
			status = s:load(USER)
		end)
		expect(status).toBe("Unavailable")
		expect(memory.writes).toBe(0)
	end)
end)

describe("Profils — réparation sans perte (audit V0.3.1)", function()
	local context = {
		userId = USER,
		now = 1000,
		rarityOf = function(speciesId)
			local species = Fixtures.MimicCatalog.get(speciesId)
			return if species then species.rarity else nil
		end,
	}

	it("P5 : un exemplaire illisible est mis en quarantaine, pas effacé", function()
		local raw = ProfileSchema.new(0)
		raw.specimens["S7301-1"] = {
			id = "S7301-1",
			speciesId = "chairy",
			rarity = "Common",
			mutation = "Standard",
			seed = 1,
			acquiredAt = 1,
			favorite = false,
		}
		raw.specimens["S7301-2"] = { id = "S7301-2", speciesId = "posty" } -- champs manquants
		local profile, err, dropped = ProfileSchema.migrate(raw, context)
		expect(err).toBeNil()
		expect(dropped).toBe(1)
		expect(profile.specimens["S7301-1"]).toBeTruthy()
		expect(#profile.quarantine).toBe(1)
		expect(profile.quarantine[1].key).toBe("S7301-2")
		expect(profile.quarantine[1].item.speciesId).toBe("posty")
		-- La quarantaine survit à un nouveau chargement.
		local again = ProfileSchema.migrate(ProfileSchema.deepCopy(profile), context)
		expect(#again.quarantine).toBe(1)
	end)

	it("P5 : un champ inconnu (version plus récente, même schéma) est conservé", function()
		local raw = ProfileSchema.new(0)
		raw.futureFeature = { level = 3 }
		local profile = ProfileSchema.migrate(raw, context)
		expect(profile.futureFeature.level).toBe(3)
	end)

	it("P8 : une migration v1 produit un profil v3 complet, sans étape rejouée", function()
		local v1 = {
			version = 1,
			inventory = { version = 1, totalCaptures = 2, species = { chairy = { count = 2, discoveryOrder = 1 } } },
			tutorialDone = true,
		}
		local profile, err = ProfileSchema.migrate(v1, context)
		expect(err).toBeNil()
		expect(profile.schemaVersion).toBe(ProfileSchema.Version)
		local count = 0
		for _ in profile.specimens do
			count += 1
		end
		expect(count).toBe(2)
		expect(profile.museum).toBeTruthy()
	end)
end)
