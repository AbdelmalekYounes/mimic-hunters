--!strict
--[[
	HuntWorld — cœur autoritaire de la chasse, sans aucune dépendance Roblox.

	Le serveur Roblox (HuntServer) n'est qu'un adaptateur : il transmet les
	requêtes brutes des RemoteEvents, la position du personnage et l'heure,
	puis diffuse les événements retournés. Toute la validation (types,
	anti-spam, portée, états, délais, récompenses) se fait ici, ce qui permet
	de la tester entièrement dans Lune, y compris les accès concurrents.

	Chaque méthode publique retourne (events, reply) :
	- events : liste { name, userId?, payload } ; userId nil = diffusion à tous ;
	- reply  : la réponse destinée au joueur (déjà incluse dans events).
	Les événements dont le nom commence par « _ » sont internes au serveur (jamais envoyés) :
	« _ProfileChanged » demande une sauvegarde du profil.

	Collection persistante (V0.2) : chaque joueur a une Collection (profil v2). Tant que son
	profil n'est pas chargé de manière sûre (`ready = false`), aucune capture ne peut démarrer :
	une acquisition qui ne pourrait pas être sauvegardée serait perdue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaptureMinigame = require(Shared.Logic.CaptureMinigame)
local Validation = require(Shared.Logic.Validation)

local Core = script.Parent
local MimicStateMachine = require(Core.MimicStateMachine)
local EncounterGenerator = require(Core.EncounterGenerator)
local CaptureLedger = require(Core.CaptureLedger)
local RewardValidator = require(Core.RewardValidator)
local Collection = require(Core.Collection)
local ProfileSchema = require(Core.ProfileSchema)
local RateLimiter = require(Core.RateLimiter)
local TutorialFlow = require(Core.TutorialFlow)

export type Event = { name: string, userId: number?, payload: any }

export type Profile = ProfileSchema.Profile

type Slot = { id: string, kind: string, zone: string, position: any }

type PlayerState = {
	userId: number,
	-- Collection persistante (nom historique conservé : `inventoryOf`).
	inventory: any,
	-- Profil chargé de manière sûre : les acquisitions sont autorisées et sauvegardées.
	ready: boolean,
	profileStatus: string,
	tutorialStep: TutorialFlow.Step,
	tutorialMimic: MimicStateMachine.Record?,
	scanReadyAt: number,
	inspectReadyAt: number,
}

local LEDGER_KEEP_SECONDS = 120

local HuntWorld = {}
HuntWorld.__index = HuntWorld

local function push(events: { Event }, name: string, userId: number?, payload: any)
	table.insert(events, { name = name, userId = userId, payload = payload })
end

local function toSlot(spec: any): Slot
	return { id = spec.id, kind = spec.kind, zone = spec.zone, position = spec.position }
end

--[[
	options = {
		config, catalog, rarities,  -- modules de configuration
		slots = { PropSpec },       -- emplacements partagés
		tutorialSlot = PropSpec?,   -- objet du tutoriel (jamais partagé)
		zones = { string },
		rng = Rng,
		serverId = string?,         -- préfixe des clés de capture (unique par serveur : JobId)
		wallClock = () -> number?,  -- horloge murale (os.time) pour les dates d'acquisition
		objectives = { Objective }?, -- objectifs du collectionneur (Config/Objectives)
		mutations = Mutations?,      -- tirage des mutations (Config/Mutations)
	}
]]
function HuntWorld.new(options: any)
	local self = setmetatable({}, HuntWorld)
	self._config = options.config
	self._catalog = options.catalog
	self._rarities = options.rarities
	self._rng = options.rng
	self._zones = options.zones
	self._serverId = options.serverId or "local"
	self._wallClock = options.wallClock or os.time
	self._objectives = options.objectives or {}
	self._mutations = options.mutations
	self._cosmeticDefaults = options.cosmeticDefaults or {}
	self._slotList = {} :: { Slot }
	self._slots = {} :: { [string]: Slot }
	for _, spec in options.slots do
		local slot = toSlot(spec)
		table.insert(self._slotList, slot)
		self._slots[slot.id] = slot
	end
	self._tutorialSlot = if options.tutorialSlot then toSlot(options.tutorialSlot) else nil
	self._mimics = {} :: { [string]: MimicStateMachine.Record }
	self._bySlot = {} :: { [string]: string }
	self._players = {} :: { [number]: PlayerState }
	self._ledger = CaptureLedger.new()
	self._limiter = RateLimiter.new(self._config.RateLimits)
	self._blocked = {} :: { [string]: number }
	self._respawnAt = {} :: { number }
	self._counter = 0
	self._lastPrune = 0
	return self
end

-- ─── Utilitaires internes ──────────────────────────────────────────────

function HuntWorld._nextId(self: any, prefix: string): string
	self._counter += 1
	return prefix .. tostring(self._counter)
end

function HuntWorld._lookupSlot(self: any, id: string): Slot?
	local slot = self._slots[id]
	if slot then
		return slot
	end
	local tutorial = self._tutorialSlot
	if tutorial and tutorial.id == id then
		return tutorial
	end
	return nil
end

function HuntWorld._slotOf(self: any, record: MimicStateMachine.Record): Slot
	return assert(self:_lookupSlot(record.slotId), "emplacement inconnu " .. record.slotId)
end

function HuntWorld._blockedSet(self: any, now: number): { [string]: boolean }
	local set = {}
	for slotId, untilTime in self._blocked do
		if untilTime > now then
			set[slotId] = true
		else
			self._blocked[slotId] = nil
		end
	end
	return set
end

function HuntWorld._activeCount(self: any): number
	local count = 0
	for _ in self._mimics do
		count += 1
	end
	return count
end

function HuntWorld._species(self: any, speciesId: string): any
	return assert(self._catalog.get(speciesId), "espèce inconnue " .. speciesId)
end

function HuntWorld._scheduleClue(self: any, record: MimicStateMachine.Record, now: number)
	if record.personal then
		local cfg = self._config.Tutorial
		record.nextClueAt = now + self._rng:nextRange(cfg.ClueIntervalMin, cfg.ClueIntervalMax)
	else
		local behavior = self:_species(record.speciesId).behavior
		record.nextClueAt = now + self._rng:nextRange(behavior.clueIntervalMin, behavior.clueIntervalMax)
	end
end

function HuntWorld._pickClue(self: any, record: MimicStateMachine.Record): string
	local clues = self:_species(record.speciesId).behavior.clues
	return self._rng:pick(clues) or "Wiggle"
end

function HuntWorld._publicMimic(_self: any, record: MimicStateMachine.Record, now: number): any
	local untilTime = record.stateUntil
	return {
		mimicId = record.id,
		propId = record.slotId,
		speciesId = record.speciesId,
		state = record.state,
		ownerUserId = record.ownerId,
		remaining = if untilTime then math.max(untilTime - now, 0) else nil,
	}
end

function HuntWorld._pushMimic(self: any, events: { Event }, record: MimicStateMachine.Record, now: number)
	push(events, "MimicUpdate", record.audience, self:_publicMimic(record, now))
end

function HuntWorld._spawnOne(self: any, now: number): boolean
	local zoneCounts: { [string]: number } = {}
	for _, record in self._mimics do
		local zone = self:_slotOf(record).zone
		zoneCounts[zone] = (zoneCounts[zone] or 0) + 1
	end
	local slot, species = EncounterGenerator.chooseSpawn({
		slots = self._slotList,
		occupied = self._bySlot,
		blocked = self:_blockedSet(now),
		zoneCounts = zoneCounts,
		zones = self._zones,
		minPerZone = self._config.Hunt.MinPerZone,
		species = self._catalog.list(),
		weightOf = self._rarities.weightOf,
	}, self._rng)
	if slot == nil or species == nil then
		return false
	end
	local record = MimicStateMachine.new(self:_nextId("M"), species.id, slot.id, now, nil)
	-- Premier indice rapide pour que le monde paraisse vivant dès l'arrivée.
	record.nextClueAt = now + self._rng:nextRange(1, species.behavior.clueIntervalMin)
	self._mimics[record.id] = record
	self._bySlot[slot.id] = record.id
	return true
end

function HuntWorld._fill(self: any, now: number, maxCount: number?): number
	local target = self._config.Hunt.ActiveMimics
	local spawned = 0
	while self:_activeCount() < target and (maxCount == nil or spawned < maxCount) do
		if not self:_spawnOne(now) then
			break
		end
		spawned += 1
	end
	return spawned
end

function HuntWorld._tutorialEvent(self: any, player: PlayerState, event: string, events: { Event }, _now: number)
	local before = player.tutorialStep
	local after = TutorialFlow.advance(before, event)
	if after == before then
		return
	end
	player.tutorialStep = after
	if after == "Done" then
		if player.ready then
			player.inventory:setTutorialDone(true)
			push(events, "_ProfileChanged", player.userId, { important = true })
		end
		local record = player.tutorialMimic
		if record and record.state ~= "Disguised" and record.state ~= "Captured" then
			push(events, "MimicUpdate", player.userId, {
				mimicId = record.id,
				propId = record.slotId,
				state = "Hidden",
			})
		end
		player.tutorialMimic = nil
	end
	local tutorial = self._tutorialSlot
	push(events, "TutorialUpdate", player.userId, {
		step = after,
		propId = if tutorial then tutorial.id else nil,
	})
end

function HuntWorld._newTutorialMimic(self: any, userId: number, now: number): MimicStateMachine.Record?
	local slot = self._tutorialSlot
	if slot == nil then
		return nil
	end
	local record = MimicStateMachine.new(self:_nextId("T"), self._config.Tutorial.SpeciesId, slot.id, now, userId)
	record.nextClueAt = now + 2
	return record
end

function HuntWorld._findRecord(self: any, player: PlayerState, mimicId: string): MimicStateMachine.Record?
	local personal = player.tutorialMimic
	if personal and personal.id == mimicId then
		return personal
	end
	return self._mimics[mimicId]
end

function HuntWorld._recordForAttempt(self: any, attempt: CaptureMinigame.Attempt): MimicStateMachine.Record?
	if attempt.personal then
		local player = self._players[attempt.userId]
		local record = player and player.tutorialMimic
		if record and record.id == attempt.mimicId then
			return record
		end
		return nil
	end
	return self._mimics[attempt.mimicId]
end

-- Un joueur ne garde qu'une révélation à la fois : les autres s'enfuient.
function HuntWorld._releaseOtherClaims(
	self: any,
	player: PlayerState,
	keep: MimicStateMachine.Record,
	now: number,
	events: { Event }
)
	local flee = self._config.Hunt.FleeDuration
	local function check(record: MimicStateMachine.Record)
		if record ~= keep and record.state == "Revealed" and record.ownerId == player.userId then
			MimicStateMachine.release(record, now, flee)
			self:_pushMimic(events, record, now)
		end
	end
	for _, record in self._mimics do
		check(record)
	end
	if player.tutorialMimic then
		check(player.tutorialMimic)
	end
end

-- ─── Résolution des captures ───────────────────────────────────────────

function HuntWorld._resolveFailure(
	self: any,
	attempt: CaptureMinigame.Attempt,
	now: number,
	events: { Event },
	reason: string
)
	if attempt.status == "Active" then
		attempt.status = "Failed"
	end
	self._ledger:close(attempt.id, now)
	local record = self:_recordForAttempt(attempt)
	if record and record.state == "Capturing" and record.attemptId == attempt.id then
		MimicStateMachine.failCapture(record, attempt.userId, attempt.id, now, self._config.Hunt.FleeDuration)
		self:_pushMimic(events, record, now)
	end
	push(events, "CaptureResolved", attempt.userId, {
		success = false,
		attemptId = attempt.id,
		mimicId = attempt.mimicId,
		speciesId = attempt.speciesId,
		reason = reason,
	})
	local player = self._players[attempt.userId]
	if player then
		self:_tutorialEvent(player, "Escaped", events, now)
	end
end

function HuntWorld._resolveSuccess(self: any, attempt: CaptureMinigame.Attempt, now: number, events: { Event })
	local record = self:_recordForAttempt(attempt)
	local completed = false
	if record then
		completed = MimicStateMachine.completeCapture(record, attempt.userId, attempt.id, now)
	end
	if not completed or record == nil then
		attempt.status = "Failed"
		self:_resolveFailure(attempt, now, events, "Invalid")
		return
	end

	local player = self._players[attempt.userId]
	local valid = RewardValidator.validate(attempt, record, self._ledger)
	self._ledger:close(attempt.id, now)

	if valid and player and not player.ready then
		-- Profil perdu pendant la tentative : rien ne peut être sauvegardé, rien n'est accordé.
		push(events, "CaptureResolved", attempt.userId, {
			success = false,
			attemptId = attempt.id,
			mimicId = record.id,
			speciesId = record.speciesId,
			reason = "ProfileUnavailable",
		})
	elseif valid and player and self._ledger:markRewarded(attempt.id) then
		-- Tirages faits ici seulement, côté serveur, au moment de la capture réussie.
		-- Le Mimic du tutoriel est toujours Standard (première capture garantie et lisible).
		local mutation = if self._mutations and not record.personal then self._mutations.roll(self._rng) else "Standard"
		local seed = self._rng:nextInteger(1, 2147483646)
		local species = self:_species(record.speciesId)
		-- Clé unique entre serveurs : un même événement de capture n'accorde qu'un exemplaire.
		local key = self._serverId .. ":" .. attempt.id
		local added, info = player.inventory:grant(key, record.speciesId, species.rarity, mutation, seed)
		if added then
			local specimen = player.inventory:specimenView(info.specimen)
			push(events, "CaptureResolved", attempt.userId, {
				success = true,
				attemptId = attempt.id,
				mimicId = record.id,
				speciesId = record.speciesId,
				specimen = specimen,
				mutation = mutation,
				isNew = info.isNewSpecies,
				isNewMutation = info.isNewMutation,
				completed = info.completed,
				count = player.inventory:count(record.speciesId),
				totalCaptures = info.totalCaptures,
				discovered = info.discovered,
			})
			push(events, "CollectionDelta", attempt.userId, {
				added = specimen,
				summary = player.inventory:summary(),
			})
			push(events, "_ProfileChanged", attempt.userId, { important = true })
			if mutation ~= "Standard" then
				-- Capture rare : annoncée à tout le serveur (de quoi la montrer).
				push(events, "RareCapture", nil, {
					userId = attempt.userId,
					speciesId = record.speciesId,
					mutation = mutation,
				})
			end
		else
			push(events, "CaptureResolved", attempt.userId, {
				success = false,
				attemptId = attempt.id,
				mimicId = record.id,
				speciesId = record.speciesId,
				reason = info,
			})
		end
	end

	self:_pushMimic(events, record, now)

	if record.personal then
		if player and player.tutorialMimic == record then
			player.tutorialMimic = nil
		end
	else
		self._mimics[record.id] = nil
		self._bySlot[record.slotId] = nil
		self._blocked[record.slotId] = now + self._config.Hunt.SlotReuseDelay
		table.insert(self._respawnAt, now + self._config.Hunt.RespawnDelay)
	end

	if player then
		self:_tutorialEvent(player, "Captured", events, now)
	end
end

-- ─── Cycle de vie des joueurs ──────────────────────────────────────────

function HuntWorld.populate(self: any, now: number): { Event }
	self:_fill(now, nil)
	return {}
end

-- Contexte de migration des profils (rareté actuelle des espèces, horloge murale).
function HuntWorld._schemaContext(self: any, userId: number): ProfileSchema.Context
	return {
		userId = userId,
		now = self._wallClock(),
		rarityOf = function(speciesId: string): string?
			local species = self._catalog.get(speciesId)
			return if species then species.rarity else nil
		end,
	}
end

function HuntWorld._newCollection(self: any, userId: number, profile: ProfileSchema.Profile): any
	local collection = Collection.new(userId, profile, {
		now = self._wallClock,
		objectives = self._objectives,
		defaults = self._cosmeticDefaults,
	})
	-- Rattrapage : un objectif ajouté après coup est validé dès la connexion s'il est déjà atteint.
	collection:evaluateObjectives()
	return collection
end

-- Cosmétiques équipés (titre, couleur de scanner), ou nil si le profil n'est pas sûr.
function HuntWorld.cosmeticsOf(self: any, userId: number): any
	local player = self._players[userId]
	if player == nil or not player.ready then
		return nil
	end
	local cosmetics = player.inventory:profile().cosmetics
	return { title = cosmetics.title, scannerColor = cosmetics.scannerColor }
end

--[[
	Ajoute un joueur. `rawProfile` : données lues dans le stockage (nil = nouveau joueur,
	v1 ou v2 : migrées ici). options.ready = false : profil non chargé de manière sûre
	(stockage indisponible, verrouillé ailleurs) → le joueur peut explorer et scanner,
	mais aucune capture ne démarre tant que `attachProfile` n'a pas réussi.
]]
function HuntWorld.addPlayer(self: any, userId: number, now: number, rawProfile: any?, options: any?)
	if self._players[userId] then
		return
	end
	local ready = not (options and options.ready == false)
	local status = if ready then "Ready" else ((options and options.status) or "Unavailable")
	local profile, err = ProfileSchema.migrate(if ready then rawProfile else nil, self:_schemaContext(userId))
	if profile == nil then
		-- Profil illisible ou d'une version plus récente : ne jamais l'écraser.
		ready = false
		status = if err == "FutureVersion" then "FutureVersion" else "Corrupt"
		profile = ProfileSchema.new(self._wallClock())
	end
	assert(profile, "profil")
	local collection = self:_newCollection(userId, profile)
	local done = collection:tutorialDone()
	local player: PlayerState = {
		userId = userId,
		inventory = collection,
		ready = ready,
		profileStatus = status,
		tutorialStep = TutorialFlow.initial(done),
		tutorialMimic = nil,
		scanReadyAt = -math.huge,
		inspectReadyAt = -math.huge,
	}
	if not done then
		player.tutorialMimic = self:_newTutorialMimic(userId, now)
	end
	self._players[userId] = player
end

--[[
	Profil enfin chargé pour un joueur qui jouait sans profil sûr (`ready = false`).
	Aucune acquisition n'a pu avoir lieu entre-temps : on remplace simplement la collection.
]]
function HuntWorld.attachProfile(self: any, userId: number, rawProfile: any, _now: number): { Event }
	local events = {}
	local player = self._players[userId]
	if player == nil or player.ready then
		return events
	end
	local profile, err = ProfileSchema.migrate(rawProfile, self:_schemaContext(userId))
	if profile == nil then
		player.profileStatus = if err == "FutureVersion" then "FutureVersion" else "Corrupt"
		push(events, "ProfileStatus", userId, { status = player.profileStatus })
		return events
	end
	player.inventory = self:_newCollection(userId, profile)
	player.ready = true
	player.profileStatus = "Ready"
	if player.inventory:tutorialDone() and player.tutorialStep ~= "Done" then
		self:_finishTutorialSilently(player, events)
	end
	push(events, "ProfileStatus", userId, { status = "Ready" })
	push(events, "CollectionSnapshot", userId, player.inventory:view())
	return events
end

-- Le profil chargé indique un tutoriel déjà terminé : on retire le Mimic du tutoriel.
function HuntWorld._finishTutorialSilently(self: any, player: PlayerState, events: { Event })
	local record = player.tutorialMimic
	if record and record.state ~= "Disguised" then
		push(events, "MimicUpdate", player.userId, { mimicId = record.id, propId = record.slotId, state = "Hidden" })
	end
	player.tutorialMimic = nil
	player.tutorialStep = "Done"
	local tutorial = self._tutorialSlot
	push(events, "TutorialUpdate", player.userId, { step = "Done", propId = if tutorial then tutorial.id else nil })
end

-- Le serveur a perdu le verrou du profil (ouvert ailleurs) : plus aucune acquisition.
function HuntWorld.setProfileLost(self: any, userId: number): { Event }
	local events = {}
	local player = self._players[userId]
	if player == nil then
		return events
	end
	player.ready = false
	player.profileStatus = "Lost"
	push(events, "ProfileStatus", userId, { status = "Lost" })
	return events
end

function HuntWorld.profileStatusOf(self: any, userId: number): string?
	local player = self._players[userId]
	return if player then player.profileStatus else nil
end

function HuntWorld.clientReady(self: any, userId: number, now: number): ({ Event }, any)
	local events = {}
	local player = self._players[userId]
	if player == nil or not self._limiter:allow(userId, "Ready", now) then
		return events, nil
	end
	local list = {}
	for _, record in self._mimics do
		if record.state ~= "Disguised" then
			table.insert(list, self:_publicMimic(record, now))
		end
	end
	local personal = player.tutorialMimic
	if personal and personal.state ~= "Disguised" then
		table.insert(list, self:_publicMimic(personal, now))
	end
	push(events, "WorldSnapshot", userId, { mimics = list })
	push(events, "ProfileStatus", userId, { status = player.profileStatus })
	push(events, "CollectionSnapshot", userId, player.inventory:view())
	local tutorial = self._tutorialSlot
	push(events, "TutorialUpdate", userId, {
		step = player.tutorialStep,
		propId = if tutorial then tutorial.id else nil,
	})
	return events, true
end

function HuntWorld.removePlayer(self: any, userId: number, now: number): { Event }
	local events = {}
	local player = self._players[userId]
	if player == nil then
		return events
	end
	local attempt = self._ledger:activeFor(userId)
	if attempt then
		self:_resolveFailure(attempt, now, events, "Left")
	end
	local flee = self._config.Hunt.FleeDuration
	for _, record in self._mimics do
		if record.ownerId == userId and (record.state == "Revealed" or record.state == "Capturing") then
			MimicStateMachine.release(record, now, flee)
			self:_pushMimic(events, record, now)
		end
	end
	self._players[userId] = nil
	self._limiter:forget(userId)
	-- Les messages destinés au joueur parti sont inutiles.
	local kept = {}
	for _, event in events do
		if event.userId ~= userId then
			table.insert(kept, event)
		end
	end
	return kept
end

--[[
	Profil à sauvegarder (référence vivante : ProfileService en fait une copie).
	nil si le profil n'a pas été chargé de manière sûre : on n'écrit jamais un profil
	vide ou provisoire par-dessus des données existantes.
]]
function HuntWorld.getProfile(self: any, userId: number): Profile?
	local player = self._players[userId]
	if player == nil or not player.ready then
		return nil
	end
	if player.tutorialStep == "Done" then
		player.inventory:setTutorialDone(true)
	end
	return player.inventory:profile()
end

-- ─── Collection : favoris, cosmétiques, réglages ───────────────────────

function HuntWorld._collectionRequest(
	self: any,
	userId: number,
	now: number,
	apply: (player: PlayerState) -> (boolean, any)
): ({ Event }, any)
	local events = {}
	local player = self._players[userId]
	local function reply(payload: any)
		push(events, "CollectionResult", userId, payload)
		return events, payload
	end
	if player == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not player.ready then
		return reply({ ok = false, reason = "ProfileUnavailable" })
	end
	if not self._limiter:allow(userId, "Collection", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	local ok, result = apply(player)
	if not ok then
		return reply({ ok = false, reason = result })
	end
	push(events, "_ProfileChanged", userId, { important = false })
	return reply({ ok = true, result = result })
end

function HuntWorld.setFavorite(self: any, userId: number, specimenId: any, value: any, now: number): ({ Event }, any)
	return self:_collectionRequest(userId, now, function(player)
		local ok, specimen = player.inventory:setFavorite(specimenId, value)
		if not ok then
			return false, specimen
		end
		return true, { updated = player.inventory:specimenView(specimen) }
	end)
end

function HuntWorld.equipCosmetic(self: any, userId: number, kind: any, id: any, now: number): ({ Event }, any)
	local events, reply = self:_collectionRequest(userId, now, function(player)
		local ok, err = player.inventory:equip(kind, id)
		if not ok then
			return false, err
		end
		return true, { summary = player.inventory:summary() }
	end)
	-- Le titre est affiché à tous les joueurs : HuntServer met à jour l'attribut du joueur.
	if reply.ok then
		push(events, "_CosmeticsChanged", userId, self:cosmeticsOf(userId))
	end
	return events, reply
end

function HuntWorld.updateSettings(self: any, userId: number, settings: any, now: number): ({ Event }, any)
	return self:_collectionRequest(userId, now, function(player)
		local ok, err = player.inventory:setSettings(settings)
		if not ok then
			return false, err
		end
		return true, { summary = player.inventory:summary() }
	end)
end

-- ─── Requêtes des joueurs ──────────────────────────────────────────────

function HuntWorld.scan(self: any, userId: number, position: any, now: number): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		push(events, "ScanResult", userId, payload)
		return events, payload
	end
	local player = self._players[userId]
	if player == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(userId, "Scan", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if not Validation.isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	if now < player.scanReadyAt then
		return reply({ ok = false, reason = "Cooldown", remaining = player.scanReadyAt - now })
	end

	local cfg = self._config.Scanner
	player.scanReadyAt = now + cfg.Cooldown
	local nearest = math.huge

	local function consider(record: MimicStateMachine.Record)
		if record.state ~= "Disguised" then
			return
		end
		local slot = self:_slotOf(record)
		local distance = Validation.horizontalDistance(position, slot.position)
		if distance > cfg.SignalRange then
			return
		end
		nearest = math.min(nearest, distance)
		if distance <= cfg.FlinchRange then
			push(events, "Clue", userId, { propId = slot.id, clue = self:_pickClue(record), strong = true })
		end
	end
	for _, record in self._mimics do
		consider(record)
	end
	if player.tutorialMimic then
		consider(player.tutorialMimic)
	end

	local band = "None"
	if nearest <= cfg.StrongBand then
		band = "Strong"
	elseif nearest <= cfg.MediumBand then
		band = "Medium"
	elseif nearest <= cfg.SignalRange then
		band = "Weak"
	end
	local _, payload = reply({ ok = true, band = band, cooldown = cfg.Cooldown })
	self:_tutorialEvent(player, "Scanned", events, now)
	return events, payload
end

function HuntWorld.inspect(self: any, userId: number, position: any, propId: any, now: number): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		push(events, "InspectResult", userId, payload)
		return events, payload
	end
	local player = self._players[userId]
	if player == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(userId, "Inspect", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if not Validation.isId(propId, 16) then
		return reply({ ok = false, reason = "BadInput" })
	end
	local slot = self:_lookupSlot(propId)
	if slot == nil then
		return reply({ ok = false, reason = "UnknownProp" })
	end
	if not Validation.isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	if now < player.inspectReadyAt then
		return reply({ ok = false, reason = "Cooldown", remaining = player.inspectReadyAt - now })
	end
	local cfg = self._config.Inspect
	if not Validation.withinReach(position, slot.position, cfg.Range, cfg.VerticalTolerance) then
		return reply({ ok = false, reason = "OutOfRange" })
	end
	if self._ledger:activeFor(userId) then
		return reply({ ok = false, reason = "Capturing" })
	end
	player.inspectReadyAt = now + cfg.Cooldown

	local record: MimicStateMachine.Record?
	local tutorial = self._tutorialSlot
	if tutorial and slot.id == tutorial.id then
		record = player.tutorialMimic
	else
		local mimicId = self._bySlot[slot.id]
		record = if mimicId then self._mimics[mimicId] else nil
	end

	if record == nil then
		player.inspectReadyAt = now + cfg.MissCooldown
		return reply({ ok = true, result = "Ordinary", propId = slot.id, kind = slot.kind })
	end

	if record.state == "Disguised" then
		self:_releaseOtherClaims(player, record, now, events)
		local claim = if record.personal
			then self._config.Tutorial.ClaimDuration
			else self._config.Hunt.RevealClaimDuration
		MimicStateMachine.reveal(record, userId, now, claim)
		self:_pushMimic(events, record, now)
		local _, payload = reply({
			ok = true,
			result = "Mimic",
			propId = slot.id,
			mimicId = record.id,
			speciesId = record.speciesId,
			claim = claim,
		})
		self:_tutorialEvent(player, "Revealed", events, now)
		return events, payload
	elseif (record.state == "Revealed" or record.state == "Capturing") and record.ownerId == userId then
		return reply({
			ok = true,
			result = "Mimic",
			propId = slot.id,
			mimicId = record.id,
			speciesId = record.speciesId,
			already = true,
		})
	elseif record.state == "Revealed" or record.state == "Capturing" then
		return reply({ ok = true, result = "Busy", propId = slot.id, ownerUserId = record.ownerId })
	end
	return reply({ ok = true, result = "Fled", propId = slot.id })
end

function HuntWorld.startCapture(self: any, userId: number, position: any, mimicId: any, now: number): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		push(events, "CaptureStarted", userId, payload)
		return events, payload
	end
	local player = self._players[userId]
	if player == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(userId, "Capture", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if not Validation.isId(mimicId, 32) then
		return reply({ ok = false, reason = "BadInput" })
	end
	local record = self:_findRecord(player, mimicId)
	if record == nil then
		return reply({ ok = false, reason = "UnknownMimic" })
	end
	if self._ledger:activeFor(userId) then
		return reply({ ok = false, reason = "AlreadyCapturing" })
	end
	-- Pas d'acquisition persistante sans profil chargé de manière sûre.
	if not player.ready then
		return reply({ ok = false, reason = "ProfileUnavailable" })
	end
	if player.inventory:isFull() then
		return reply({ ok = false, reason = "CollectionFull" })
	end
	local slot = self:_slotOf(record)
	if not Validation.isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	local capture = self._config.Capture
	if not Validation.withinReach(position, slot.position, capture.Range, self._config.Inspect.VerticalTolerance) then
		return reply({ ok = false, reason = "OutOfRange" })
	end

	local attemptId = self:_nextId("A")
	local timeout = if record.personal then self._config.Tutorial.AttemptTimeout else capture.AttemptTimeout
	local ok, err = MimicStateMachine.startCapture(record, userId, attemptId, now, timeout)
	if not ok then
		return reply({ ok = false, reason = err })
	end

	local difficulty = if record.personal
		then self._config.Tutorial.Difficulty
		else self:_species(record.speciesId).behavior.capture
	local attempt = CaptureMinigame.newAttempt({
		id = attemptId,
		userId = userId,
		mimicId = record.id,
		speciesId = record.speciesId,
		slotId = slot.id,
		personal = record.personal,
		difficulty = difficulty,
		now = now,
		timeout = timeout,
		hitsRequired = capture.HitsRequired,
		maxMisses = if record.personal then nil else capture.MaxMisses,
		rng = self._rng,
	})
	local opened = self._ledger:open(attempt)
	assert(opened, "tentative déjà ouverte")

	local _, payload = reply({
		ok = true,
		attemptId = attemptId,
		mimicId = record.id,
		speciesId = record.speciesId,
		propId = slot.id,
		stage = CaptureMinigame.publicStage(attempt.stage),
		hitsRequired = attempt.hitsRequired,
		maxMisses = attempt.maxMisses or -1,
		timeout = timeout,
		minStageElapsed = capture.MinStageElapsed,
	})
	self:_pushMimic(events, record, now)
	return events, payload
end

function HuntWorld.pulse(
	self: any,
	userId: number,
	position: any,
	attemptId: any,
	claimedElapsed: any,
	allowance: number,
	now: number
): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		push(events, "PulseResult", userId, payload)
		return events, payload
	end
	local player = self._players[userId]
	if player == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(userId, "Pulse", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if not Validation.isId(attemptId, 32) then
		return reply({ ok = false, reason = "BadInput" })
	end
	local attempt = self._ledger:get(attemptId)
	if attempt == nil then
		return reply({ ok = false, reason = "UnknownAttempt" })
	end
	if attempt.userId ~= userId then
		return reply({ ok = false, reason = "NotYours" })
	end
	if attempt.status ~= "Active" then
		return reply({ ok = false, reason = "Resolved", attemptId = attempt.id })
	end
	local record = self:_recordForAttempt(attempt)
	if record == nil then
		self:_resolveFailure(attempt, now, events, "Invalid")
		return reply({ ok = false, reason = "Resolved", attemptId = attempt.id })
	end
	local capture = self._config.Capture
	local slot = self:_slotOf(record)
	if
		not Validation.withinReach(position, slot.position, capture.PulseRange, self._config.Inspect.VerticalTolerance)
	then
		return reply({ ok = false, reason = "OutOfRange", attemptId = attempt.id })
	end

	local window = math.clamp(
		if Validation.isFiniteNumber(allowance) then allowance else 0,
		capture.LatencyMin,
		capture.LatencyMax
	)
	local result = CaptureMinigame.evaluatePulse(attempt, claimedElapsed, now, window, capture, self._rng)
	local _, payload = reply({
		ok = result.accepted,
		reason = result.reason,
		attemptId = attempt.id,
		hit = result.hit,
		position = result.position,
		hits = result.hits,
		misses = result.misses,
		status = result.status,
		stage = if result.stage then CaptureMinigame.publicStage(result.stage) else nil,
	})

	if attempt.status == "Succeeded" then
		self:_resolveSuccess(attempt, now, events)
	elseif attempt.status == "Failed" then
		self:_resolveFailure(attempt, now, events, "Escaped")
	elseif attempt.status == "Expired" then
		self:_resolveFailure(attempt, now, events, "Timeout")
	end
	return events, payload
end

-- ─── Horloge ───────────────────────────────────────────────────────────

function HuntWorld._tickRecord(self: any, record: MimicStateMachine.Record, now: number, events: { Event })
	local flee = self._config.Hunt.FleeDuration
	local event = MimicStateMachine.tick(record, now, flee)
	if event == "ClaimExpired" then
		self:_pushMimic(events, record, now)
		if record.audience then
			local player = self._players[record.audience]
			if player then
				self:_tutorialEvent(player, "Escaped", events, now)
			end
		end
	elseif event == "CaptureTimeout" then
		local attemptId = record.attemptId
		local attempt = if attemptId then self._ledger:get(attemptId) else nil
		if attempt and attempt.status == "Active" then
			attempt.status = "Expired"
			self:_resolveFailure(attempt, now, events, "Timeout")
		else
			MimicStateMachine.release(record, now, flee)
			self:_pushMimic(events, record, now)
		end
	elseif event == "FleeFinished" then
		local from = self:_slotOf(record)
		local target = from
		if not record.personal then
			self._bySlot[from.id] = nil
			local chosen =
				EncounterGenerator.chooseFleeSlot(self._slotList, self._bySlot, self:_blockedSet(now), from, self._rng)
			target = chosen or from
			self._bySlot[target.id] = record.id
		end
		MimicStateMachine.settle(record, target.id, now)
		self:_scheduleClue(record, now)
		push(events, "MimicUpdate", record.audience, { mimicId = record.id, propId = from.id, state = "Hidden" })
	end
end

function HuntWorld._tickClues(self: any, now: number, positions: { [number]: any }, events: { Event })
	local range = self._config.Clues.BroadcastRange
	for _, record in self._mimics do
		if record.state == "Disguised" and now >= record.nextClueAt then
			self:_scheduleClue(record, now)
			local slot = self:_slotOf(record)
			local clue = self:_pickClue(record)
			for userId, position in positions do
				if
					self._players[userId]
					and Validation.isPosition(position)
					and Validation.horizontalDistance(position, slot.position) <= range
				then
					push(events, "Clue", userId, { propId = slot.id, clue = clue, strong = false })
				end
			end
		end
	end
	for userId, player in self._players do
		local record = player.tutorialMimic
		if record and record.state == "Disguised" and now >= record.nextClueAt then
			self:_scheduleClue(record, now)
			local position = positions[userId]
			local slot = self:_slotOf(record)
			if Validation.isPosition(position) and Validation.horizontalDistance(position, slot.position) <= range then
				push(events, "Clue", userId, {
					propId = slot.id,
					clue = self:_pickClue(record),
					strong = player.tutorialStep == "Inspect",
				})
			end
		end
	end
end

function HuntWorld.tick(self: any, now: number, positions: { [number]: any }): { Event }
	local events = {}

	for _, attempt in self._ledger:activeAttempts() do
		if CaptureMinigame.checkExpiry(attempt, now) then
			self:_resolveFailure(attempt, now, events, "Timeout")
		end
	end

	local records = {}
	for _, record in self._mimics do
		table.insert(records, record)
	end
	for _, player in self._players do
		if player.tutorialMimic then
			table.insert(records, player.tutorialMimic)
		end
	end
	for _, record in records do
		self:_tickRecord(record, now, events)
	end

	local due = 0
	local pending = {}
	for _, at in self._respawnAt do
		if at <= now then
			due += 1
		else
			table.insert(pending, at)
		end
	end
	self._respawnAt = pending
	if due > 0 then
		self:_fill(now, due)
	elseif #pending == 0 then
		-- Rattrapage si un remplissage précédent a échoué (emplacements bloqués).
		self:_fill(now, 1)
	end

	self:_tickClues(now, positions, events)

	if now - self._lastPrune > 30 then
		self._lastPrune = now
		self._ledger:prune(now, LEDGER_KEEP_SECONDS)
	end
	return events
end

-- ─── Lecture (tests, débogage) ─────────────────────────────────────────

function HuntWorld.mimicAtSlot(self: any, slotId: string): MimicStateMachine.Record?
	local id = self._bySlot[slotId]
	return if id then self._mimics[id] else nil
end

function HuntWorld.sharedMimics(self: any): { MimicStateMachine.Record }
	local out = {}
	for _, record in self._mimics do
		table.insert(out, record)
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function HuntWorld.inventoryOf(self: any, userId: number): any
	local player = self._players[userId]
	return if player then player.inventory else nil
end

function HuntWorld.tutorialStepOf(self: any, userId: number): string?
	local player = self._players[userId]
	return if player then player.tutorialStep else nil
end

function HuntWorld.tutorialMimicOf(self: any, userId: number): MimicStateMachine.Record?
	local player = self._players[userId]
	return if player then player.tutorialMimic else nil
end

function HuntWorld.slot(self: any, slotId: string): Slot?
	return self:_lookupSlot(slotId)
end

return HuntWorld
