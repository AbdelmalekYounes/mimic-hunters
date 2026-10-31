--!strict
--[[
	DataStoreCheck — scénarios de sauvegarde exécutés par le vrai ProfileService sur un
	stockage donné (V0.3.1, jalon 2).

	Module sans dépendance Roblox : tout est injecté.
	- En jeu (expérience de test privée) : RealDataStoreCheck.server.luau le lance sur un VRAI
	  DataStore dédié (jamais celui des joueurs).
	- Dans Lune : datastore_check.spec le lance sur un DataStore simulé, pour vérifier le
	  script lui-même avant de l'exécuter pour de vrai.

	deps = {
		ProfileService, ProfileSchema,
		store,            -- GetAsync / SetAsync / UpdateAsync (DataStore ou simulation)
		backend,          -- interface ProfileService (update, budget) sur ce même store
		clock, wait, spawn, elapsed,   -- os.time, task.wait, task.spawn, os.clock
		encode,           -- sérialisation pour comparer deux tables (JSONEncode)
		runId, print,
	}
	Retour : liste { name, ok, detail }.

	Garanties : clés « check_<runId>_<n> » avec n négatif (jamais un vrai joueur), aucune
	suppression.
]]

return function(deps: any): { any }
	local ProfileService = deps.ProfileService
	local ProfileSchema = deps.ProfileSchema
	local store = deps.store
	local results = {}

	local function report(name: string, ok: boolean, detail: string?)
		table.insert(results, { name = name, ok = ok, detail = detail })
		deps.print(
			string.format(
				"[DataStoreCheck] %s %s%s",
				if ok then "RÉUSSI" else "ÉCHEC ",
				name,
				if detail then " — " .. detail else ""
			)
		)
	end

	local keyCounter = 0
	local function freshUser(): number
		keyCounter += 1
		-- Identifiants négatifs : impossibles pour un vrai joueur.
		return -(100000 + keyCounter)
	end
	local prefix = string.format("check_%s_", deps.runId)
	local function keyOf(user: number): string
		return prefix .. tostring(user)
	end

	local function service(jobId: string, overrides: any?)
		local config = { KeyPrefix = prefix, LockedRetries = 1, LockedRetryDelay = 2 }
		for k, v in overrides or {} do
			config[k] = v
		end
		local lost = {}
		local s = ProfileService.new({
			backend = deps.backend,
			jobId = jobId,
			clock = deps.clock,
			wait = deps.wait,
			spawn = deps.spawn,
			log = function(message: string)
				deps.print("[DataStoreCheck]   " .. message)
			end,
			onLost = function(userId: number)
				table.insert(lost, userId)
			end,
			config = config,
		})
		return s, lost
	end

	local function richProfile(): any
		local profile = ProfileSchema.new(deps.clock())
		for i, spec in { { "chairy", "Standard" }, { "chairy", "Chromatic" }, { "chairy", "Spectral" } } do
			local id = ProfileSchema.specimenId(1, i)
			profile.specimens[id] = {
				id = id,
				speciesId = spec[1],
				rarity = "Common",
				mutation = spec[2],
				seed = 500 + i,
				acquiredAt = i,
				favorite = i == 2,
			}
			profile.museum.slots[i] = id
		end
		profile.nextSerial = 4
		profile.museum.wall = "night"
		profile.cosmetics.unlocked = { title_apprentice = true }
		profile.cosmetics.title = "title_apprentice"
		profile.objectives.first_capture = 1
		return profile
	end

	local function step(name: string, fn: () -> (boolean, string?))
		local ok, passed, detail = pcall(fn)
		if not ok then
			report(name, false, "erreur : " .. tostring(passed))
		else
			report(name, passed == true, detail)
		end
	end

	step("1. première connexion : profil vide, verrou posé", function()
		local s = service("check-A")
		local user = freshUser()
		local status, data = s:load(user)
		local record = store:GetAsync(keyOf(user))
		local locked = type(record) == "table" and type(record.meta) == "table" and record.meta.lock ~= nil
		s:release(user, nil)
		return status == "Ready" and data == nil and locked, status
	end)

	step("2-4. sauvegarde, libération, rechargement par un autre « serveur »", function()
		local user = freshUser()
		local a = service("check-A")
		assert(a:load(user) == "Ready", "chargement")
		local profile = ProfileSchema.new(deps.clock())
		profile.stats.totalCaptures = 7
		assert(a:release(user, profile), "libération")
		local b = service("check-B")
		local status, data = b:load(user)
		b:release(user, nil)
		return status == "Ready" and data ~= nil and data.stats.totalCaptures == 7, status
	end)

	step("5-9. mutations, favoris, vitrines, styles, cosmétiques, objectifs conservés", function()
		local user = freshUser()
		local a = service("check-A")
		assert(a:load(user) == "Ready", "chargement")
		local original = richProfile()
		assert(a:release(user, original), "libération")
		local b = service("check-B")
		local _, data = b:load(user)
		b:release(user, nil)
		local same = data ~= nil
			and deps.encode(data.specimens) == deps.encode(original.specimens)
			and deps.encode(data.museum) == deps.encode(original.museum)
			and data.cosmetics.title == "title_apprentice"
			and data.objectives.first_capture == 1
		return same, nil
	end)

	step("10. profil V0.2 stocké : migré en v3 sans perte", function()
		local user = freshUser()
		local v2 = richProfile()
		v2.schemaVersion = 2
		v2.museum = nil
		v2.hunts = nil
		store:SetAsync(keyOf(user), { data = v2, meta = { hasData = true } })
		local s = service("check-A")
		local status, data = s:load(user)
		s:release(user, nil)
		local migrated = ProfileSchema.migrate(data, {
			userId = user,
			now = deps.clock(),
			rarityOf = function()
				return "Common"
			end,
		})
		local count = 0
		local specimens: { [string]: any } = if migrated then migrated.specimens else {}
		for _ in specimens do
			count += 1
		end
		return status == "Ready" and migrated ~= nil and migrated.schemaVersion == ProfileSchema.Version and count == 3,
			string.format("%s, %d exemplaires", status, count)
	end)

	step("13. deux serveurs, même profil : le second est bloqué", function()
		local user = freshUser()
		local a = service("check-A")
		assert(a:load(user) == "Ready", "chargement")
		local b = service("check-B")
		local status = b:load(user)
		a:release(user, nil)
		return status == "Locked", status
	end)

	step("14. serveur arrêté brutalement : verrou périmé repris", function()
		local user = freshUser()
		store:SetAsync(keyOf(user), {
			data = ProfileSchema.new(0),
			meta = { hasData = true, lock = { jobId = "check-crashed", sessionId = "x", at = deps.clock() - 400 } },
		})
		local s = service("check-A")
		local status = s:load(user)
		s:release(user, nil)
		return status == "Ready", status
	end)

	step("15. verrou perdu : plus aucune écriture, serveur prévenu", function()
		local user = freshUser()
		local a, lost = service("check-A", { MinSaveInterval = 0 })
		assert(a:load(user) == "Ready", "chargement")
		-- Un autre serveur reprend le verrou (comme après expiration).
		store:UpdateAsync(keyOf(user), function(record)
			record.meta.lock = { jobId = "check-B", sessionId = "intrus", at = deps.clock() }
			return record
		end)
		local saved = a:save(user, ProfileSchema.new(deps.clock()), false)
		return saved == false and lost[1] == user, nil
	end)

	step("P4. enregistrement illisible : jamais remplacé", function()
		local user = freshUser()
		store:SetAsync(keyOf(user), "texte illisible")
		local s = service("check-A")
		local status = s:load(user)
		local after = store:GetAsync(keyOf(user))
		return status == "Corrupt" and after == "texte illisible", status
	end)

	step("16 (partiel). fermeture : toutes les sessions libérées avant l'échéance", function()
		local s = service("check-A")
		local users = { freshUser(), freshUser(), freshUser() }
		for _, user in users do
			assert(s:load(user) == "Ready", "chargement")
		end
		local started = deps.elapsed()
		s:closeAll(function()
			return ProfileSchema.new(deps.clock())
		end)
		local elapsed = deps.elapsed() - started
		local remaining = 0
		for _, user in users do
			if s:status(user) then
				remaining += 1
			end
		end
		return remaining == 0 and elapsed < 25, string.format("%.1f s", elapsed)
	end)

	return results
end
