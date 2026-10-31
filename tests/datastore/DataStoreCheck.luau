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

	-- Comparaison champ par champ (l'ordre des clés d'un JSONEncode n'est pas garanti par
	-- Roblox : comparer deux chaînes JSON peut échouer sans aucune différence réelle).
	-- Retourne (true) ou (false, chemin de la première différence).
	local function sameValue(a: any, b: any, path: string): (boolean, string?)
		if type(a) ~= type(b) then
			return false, string.format("%s : %s ≠ %s", path, tostring(a), tostring(b))
		end
		if type(a) ~= "table" then
			if a ~= b then
				return false, string.format("%s : %s ≠ %s", path, tostring(a), tostring(b))
			end
			return true, nil
		end
		for k, v in a do
			local ok, where = sameValue(v, b[k], path .. "." .. tostring(k))
			if not ok then
				return false, where
			end
		end
		for k, v in b do
			if a[k] == nil then
				return false, string.format("%s.%s : absent ≠ %s", path, tostring(k), tostring(v))
			end
		end
		return true, nil
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
		if data == nil then
			return false, "aucune donnée relue"
		end
		for _, field in { "specimens", "museum", "cosmetics", "objectives", "nextSerial" } do
			local ok, where = sameValue(original[field], data[field], field)
			if not ok then
				return false, where
			end
		end
		return true, "exemplaires, vitrines, styles, cosmétiques, objectifs identiques"
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

	step("Libération : verrou retiré, données intactes", function()
		local user = freshUser()
		local s = service("check-A")
		assert(s:load(user) == "Ready", "chargement")
		local profile = ProfileSchema.new(deps.clock())
		profile.stats.totalCaptures = 4
		assert(s:release(user, profile), "libération")
		local record = store:GetAsync(keyOf(user))
		local released = type(record) == "table" and record.meta.lock == nil
		local intact = released and record.data.stats.totalCaptures == 4 and record.meta.hasData == true
		return intact and s:status(user) == nil, if released then "verrou retiré" else "verrou encore posé"
	end)

	step("P7. écriture appliquée puis réessayée : reconnue, pas de verrou perdu", function()
		local user = freshUser()
		local s = service("check-A")
		assert(s:load(user) == "Ready", "chargement")
		local sessionId = s:sessionOf(user)
		local profile = ProfileSchema.new(deps.clock())
		profile.stats.totalCaptures = 9
		local commitId = sessionId .. "#rejeu"
		local function attempt()
			local outcome = nil
			local ok = deps.backend:update(keyOf(user), function(current)
				local out, result =
					ProfileService.commitTransform(current, sessionId, profile, deps.clock(), true, commitId)
				outcome = result
				return out
			end)
			return ok, outcome
		end
		-- 1er essai : écriture appliquée (et verrou libéré). 2e essai, comme après une réponse
		-- perdue : le verrou n'est plus là, mais l'identifiant d'écriture prouve qu'elle est faite.
		local ok1, first = attempt()
		local ok2, second = attempt()
		local record = store:GetAsync(keyOf(user))
		return ok1 and ok2 and first == "Saved" and second == "Saved" and record.data.stats.totalCaptures == 9,
			string.format("%s puis %s", tostring(first), tostring(second))
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
