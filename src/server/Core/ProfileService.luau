--!strict
--[[
	ProfileService — chargement et sauvegarde des profils, avec verrou de session.

	Pourquoi un verrou : un joueur qui change de serveur peut être « ouvert » sur deux serveurs
	pendant quelques secondes. Sans verrou, l'ancien serveur pourrait écraser les captures faites
	sur le nouveau (perte) ou les deux pourraient attribuer le même numéro d'exemplaire.

	Enregistrement stocké pour chaque joueur (une clé) :
		{ data = Profile, meta = { lock = { jobId, sessionId, at }?, savedAt, writes } }

	- Chargement : UpdateAsync pose le verrou. Un verrou d'une autre session encore frais
	  (< LockTimeout) bloque : on réessaie quelques fois, puis le profil est « Locked ».
	  Un verrou périmé (serveur arrêté brutalement) est repris.
	- Sauvegarde : n'écrit que si le verrou est toujours le nôtre, et le rafraîchit.
	  Sinon la session est « Lost » : plus aucune écriture, le serveur est prévenu (onLost).
	- Départ / fermeture : dernière sauvegarde qui libère le verrou.

	Les erreurs du stockage sont réessayées avec un délai croissant ; le budget de requêtes est
	respecté. Aucune dépendance Roblox : le stockage (backend), l'horloge, l'attente et le
	lancement de tâches sont injectés, ce qui permet de tout tester dans Lune (pannes, verrous,
	serveurs concurrents).

	Backend attendu :
		backend:update(key, transform) -> (ok: boolean, result: any | message: string)  -- ne lève jamais
		backend:budget() -> number   -- requêtes d'écriture disponibles
	`transform` peut être appelé plusieurs fois et ne doit pas céder la main (comme UpdateAsync).
]]

local ProfileSchema = require(script.Parent.ProfileSchema)

export type Config = {
	KeyPrefix: string,
	LockTimeout: number,
	AutosaveInterval: number,
	MinSaveInterval: number,
	MaxRetries: number,
	RetryBase: number,
	LockedRetries: number,
	LockedRetryDelay: number,
	CloseTimeout: number,
}

type Session = {
	userId: number,
	sessionId: string,
	status: string, -- "Active" | "Releasing" | "Lost"
	lastSave: number,
	dirty: number, -- génération de modification
	savedDirty: number,
	important: boolean,
	busy: boolean,
}

local ProfileService = {}
ProfileService.__index = ProfileService

ProfileService.DefaultConfig = table.freeze({
	KeyPrefix = "player_",
	-- Un verrou non rafraîchi depuis ce délai est considéré abandonné (serveur arrêté).
	LockTimeout = 360,
	AutosaveInterval = 60,
	-- Roblox limite les écritures sur une même clé à environ une toutes les 6 s.
	MinSaveInterval = 7,
	MaxRetries = 5,
	RetryBase = 1,
	LockedRetries = 4,
	LockedRetryDelay = 5,
	CloseTimeout = 25,
})

-- ─── Transformations pures (appelées dans UpdateAsync) ──────────────────

--[[
	Pose le verrou de `sessionId`. Retourne (nouvel enregistrement | nil pour annuler, résultat).
	Résultats : "Acquired" (libre ou à nous), "Stolen" (verrou périmé repris), "Locked".
]]
function ProfileService.acquireTransform(record: any, jobId: string, sessionId: string, now: number, timeout: number)
	if type(record) ~= "table" then
		record = { data = nil, meta = {} }
	end
	if type(record.meta) ~= "table" then
		record.meta = {}
	end
	local lock = record.meta.lock
	local outcome = "Acquired"
	if type(lock) == "table" and lock.sessionId ~= sessionId then
		local sameServer = lock.jobId == jobId
		local fresh = type(lock.at) == "number" and now - lock.at < timeout
		if fresh and not sameServer then
			return nil, "Locked"
		end
		-- Même serveur : l'ancienne session de ce joueur a déjà été close par ce service.
		outcome = if sameServer then "Acquired" else "Stolen"
	end
	record.meta.lock = { jobId = jobId, sessionId = sessionId, at = now }
	return record, outcome
end

--[[
	Écrit `data` si le verrou appartient toujours à `sessionId`. `release` libère le verrou.
	Résultats : "Saved" ou "LockLost" (enregistrement non modifié).
]]
function ProfileService.commitTransform(record: any, sessionId: string, data: any, now: number, release: boolean)
	local lock = type(record) == "table" and type(record.meta) == "table" and record.meta.lock
	if type(lock) ~= "table" or lock.sessionId ~= sessionId then
		return nil, "LockLost"
	end
	-- data nil : libération seule, les données déjà stockées sont conservées telles quelles.
	if data ~= nil then
		record.data = data
	end
	record.meta.savedAt = now
	record.meta.writes = (if type(record.meta.writes) == "number" then record.meta.writes else 0) + 1
	if release then
		record.meta.lock = nil
	else
		lock.at = now
	end
	return record, "Saved"
end

-- ─── Service ───────────────────────────────────────────────────────────

--[[
	options = {
		backend, jobId,
		clock: () -> number        -- secondes (os.time) ; sert aux verrous entre serveurs
		wait: (seconds) -> ()      -- task.wait en jeu, horloge simulée en test
		spawn: (fn) -> ()          -- task.spawn en jeu
		log: (message) -> ()?,
		onLost: (userId) -> ()?,   -- la session a perdu son verrou : arrêter les acquisitions
		config: Config?,
	}
]]
function ProfileService.new(options: any)
	local self = setmetatable({}, ProfileService)
	self._backend = options.backend
	self._jobId = options.jobId
	self._clock = options.clock
	self._wait = options.wait
	self._spawn = options.spawn
	self._log = options.log or function(_: string) end
	self._onLost = options.onLost or function(_: number) end
	local config = table.clone(ProfileService.DefaultConfig) :: any
	if options.config then
		for k, v in options.config do
			config[k] = v
		end
	end
	self._config = config :: Config
	self._sessions = {} :: { [number]: Session }
	self._counter = 0
	return self
end

function ProfileService.key(self: any, userId: number): string
	return self._config.KeyPrefix .. tostring(userId)
end

function ProfileService.status(self: any, userId: number): string?
	local session = self._sessions[userId]
	return if session then session.status else nil
end

-- Attend qu'il reste du budget d'écriture (au plus ~10 s, puis on laisse Roblox mettre en file).
function ProfileService._awaitBudget(self: any)
	for _ = 1, 10 do
		if self._backend:budget() >= 1 then
			return
		end
		self._wait(1)
	end
end

--[[
	Appelle backend:update avec réessais (délai 1, 2, 4, 8 s…). `makeTransform` reçoit une
	table où la transformation range son résultat (la dernière exécution fait foi).
	Retourne (ok, outcome?, record?).
]]
function ProfileService._update(self: any, key: string, transform: (any, any) -> any): (boolean, string?, any)
	local config = self._config
	local delay = config.RetryBase
	for attempt = 1, config.MaxRetries do
		self:_awaitBudget()
		local box = { outcome = nil :: string? }
		local ok, result = self._backend:update(key, function(record)
			local out, outcome = transform(record, box)
			box.outcome = outcome
			return out
		end)
		if ok then
			return true, box.outcome, result
		end
		self._log(string.format("[Profils] %s : échec %d/%d (%s)", key, attempt, config.MaxRetries, tostring(result)))
		if attempt < config.MaxRetries then
			self._wait(delay)
			delay *= 2
		end
	end
	return false, nil, nil
end

--[[
	Charge le profil brut d'un joueur et pose le verrou. Cède la main.
	Retours : ("Ready", données brutes ou nil pour un nouveau joueur) | ("Locked", nil) | ("Unavailable", nil).
	Les données brutes sont ensuite migrées par ProfileSchema (dans HuntWorld).
]]
function ProfileService.load(self: any, userId: number): (string, any)
	-- Une session précédente de ce joueur (départ en cours) doit d'abord se terminer.
	for _ = 1, 30 do
		local previous = self._sessions[userId]
		if previous == nil or previous.status == "Lost" then
			break
		end
		self._wait(0.5)
	end
	if self._sessions[userId] and self._sessions[userId].status ~= "Lost" then
		return "Unavailable", nil
	end

	self._counter += 1
	local sessionId = string.format("%s:%d:%d", self._jobId, userId, self._counter)
	local key = self:key(userId)
	local config = self._config
	for attempt = 1, config.LockedRetries + 1 do
		local now = self._clock()
		local ok, outcome, record = self:_update(key, function(current)
			return ProfileService.acquireTransform(current, self._jobId, sessionId, now, config.LockTimeout)
		end)
		if not ok then
			return "Unavailable", nil
		end
		if outcome == "Acquired" or outcome == "Stolen" then
			if outcome == "Stolen" then
				self._log(string.format("[Profils] %s : verrou périmé repris", key))
			end
			self._sessions[userId] = {
				userId = userId,
				sessionId = sessionId,
				status = "Active",
				lastSave = self._clock(),
				dirty = 0,
				savedDirty = 0,
				important = false,
				busy = false,
			}
			local data = if type(record) == "table" then record.data else nil
			return "Ready", ProfileSchema.deepCopy(data)
		end
		-- Verrou d'une autre session encore active : on patiente un peu.
		if attempt <= config.LockedRetries then
			self._wait(config.LockedRetryDelay)
		end
	end
	return "Locked", nil
end

-- Signale une modification ; `important` = à sauvegarder dès que possible (capture, objectif).
function ProfileService.markDirty(self: any, userId: number, important: boolean?)
	local session = self._sessions[userId]
	if session == nil or session.status ~= "Active" then
		return
	end
	session.dirty += 1
	if important then
		session.important = true
	end
end

--[[
	Sauvegarde `data` (profil v2). `release` = dernière sauvegarde, libère le verrou.
	Avec release et data nil, le verrou est libéré sans toucher aux données stockées
	(profil jamais chargé correctement : on ne l'écrase pas).
	Retourne true si l'écriture a réussi. Cède la main.
]]
function ProfileService.save(self: any, userId: number, data: any, release: boolean?): boolean
	local session = self._sessions[userId]
	if session == nil or session.status == "Lost" or (data == nil and not release) then
		return false
	end
	-- Une seule écriture à la fois par joueur.
	while session.busy do
		if not release then
			return false
		end
		self._wait(0.25)
	end
	if session.status == "Lost" then
		return false
	end
	local config = self._config
	if release then
		session.status = "Releasing"
		-- Respecte l'intervalle minimal d'écriture sur la clé.
		local remaining = config.MinSaveInterval - (self._clock() - session.lastSave)
		if remaining > 0 then
			self._wait(remaining)
		end
	end

	session.busy = true
	local generation = session.dirty
	local copy = ProfileSchema.deepCopy(data)
	local now = self._clock()
	if copy then
		copy.updatedAt = now
	end
	local ok, outcome = self:_update(self:key(userId), function(current)
		return ProfileService.commitTransform(current, session.sessionId, copy, now, release == true)
	end)
	session.busy = false

	if ok and outcome == "Saved" then
		session.lastSave = now
		session.savedDirty = generation
		if session.dirty == generation then
			session.important = false
		end
		return true
	end
	if ok and outcome == "LockLost" then
		session.status = "Lost"
		self._log(string.format("[Profils] %s : verrou perdu, écritures arrêtées", self:key(userId)))
		self._onLost(userId)
	end
	return false
end

--[[
	À appeler régulièrement (≈ chaque seconde). Lance les sauvegardes dues :
	- modification importante, dès que l'intervalle minimal est écoulé ;
	- sinon toutes les AutosaveInterval secondes (rafraîchit aussi le verrou).
]]
function ProfileService.step(self: any, getData: (number) -> any)
	local now = self._clock()
	local config = self._config
	for userId, session in self._sessions do
		if session.status == "Active" and not session.busy then
			local elapsed = now - session.lastSave
			local due = (session.important and elapsed >= config.MinSaveInterval) or elapsed >= config.AutosaveInterval
			if due then
				local data = getData(userId)
				if data then
					self._spawn(function()
						self:save(userId, data, false)
					end)
				end
			end
		end
	end
end

-- Dernière sauvegarde et libération du verrou. Cède la main.
function ProfileService.release(self: any, userId: number, data: any): boolean
	local session = self._sessions[userId]
	if session == nil then
		return false
	end
	local ok = false
	if session.status ~= "Lost" then
		ok = self:save(userId, data, true)
		if not ok then
			-- Après tous les réessais : le verrou expirera seul (LockTimeout). Les modifications
			-- depuis la dernière sauvegarde réussie sont perdues ; c'est journalisé.
			self._log(string.format("[Profils] %s : sauvegarde finale impossible", self:key(userId)))
		end
	end
	if self._sessions[userId] == session then
		self._sessions[userId] = nil
	end
	return ok
end

-- Fermeture du serveur : libère toutes les sessions en parallèle, attend au plus CloseTimeout.
function ProfileService.closeAll(self: any, getData: (number) -> any)
	local pending = 0
	for userId in self._sessions do
		pending += 1
		local data = getData(userId)
		self._spawn(function()
			self:release(userId, data)
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < self._config.CloseTimeout do
		self._wait(0.5)
		waited += 0.5
	end
end

return ProfileService
