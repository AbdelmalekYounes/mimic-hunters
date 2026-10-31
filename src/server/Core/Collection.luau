--!strict
--[[
	Collection — la collection persistante d'un joueur, manipulée par le serveur.

	Enveloppe un profil v2 (ProfileSchema) et garantit ses invariants :
	- `grant` est idempotent par clé de capture : rejouer la même capture ne crée jamais un
	  second exemplaire, y compris après rechargement du profil (clés persistées) ;
	- les identifiants d'exemplaires viennent d'un compteur persistant qui ne recule jamais ;
	- les objectifs atteints débloquent leurs récompenses une seule fois.

	Aucune dépendance Roblox : testé dans Lune.
]]

local ProfileSchema = require(script.Parent.ProfileSchema)

export type Objective = {
	id: string,
	-- Conditions : { type = "captures", count } | { type = "species", count } | { type = "mutation", mutation }
	condition: { type: string, count: number?, mutation: string? },
	reward: { id: string, kind: string }, -- kind : "title" | "scannerColor"
}

export type GrantInfo = {
	specimen: ProfileSchema.Specimen,
	isNewSpecies: boolean,
	isNewMutation: boolean,
	completed: { string },
	discovered: number,
	totalCaptures: number,
	owned: number,
}

export type Options = {
	now: () -> number,
	objectives: { Objective }?,
	-- Cosmétiques disponibles sans objectif (couleur de scanner par défaut, etc.).
	defaults: { [string]: boolean }?,
}

local Collection = {}
Collection.__index = Collection

function Collection.new(userId: number, profile: ProfileSchema.Profile, options: Options)
	local self = setmetatable({}, Collection)
	self.userId = userId
	self._profile = profile
	self._now = options.now
	self._objectives = options.objectives or {}
	self._defaults = options.defaults or {}
	-- Index dérivés (non persistés).
	self._owned = 0
	self._bySpecies = {} :: { [string]: number }
	for _, specimen in profile.specimens do
		self._owned += 1
		self._bySpecies[specimen.speciesId] = (self._bySpecies[specimen.speciesId] or 0) + 1
	end
	return self
end

-- ─── Lecture ───────────────────────────────────────────────────────────

function Collection.profile(self: any): ProfileSchema.Profile
	return self._profile
end

function Collection.count(self: any, speciesId: string): number
	return self._bySpecies[speciesId] or 0
end

function Collection.owned(self: any): number
	return self._owned
end

function Collection.totalCaptures(self: any): number
	return self._profile.stats.totalCaptures
end

function Collection.discoveredCount(self: any): number
	local n = 0
	for _ in self._profile.codex do
		n += 1
	end
	return n
end

function Collection.hasSource(self: any, key: string): boolean
	return self._profile.grants[key] ~= nil
end

function Collection.isFull(self: any): boolean
	return self._owned >= ProfileSchema.MaxSpecimens
end

function Collection.specimen(self: any, id: string): ProfileSchema.Specimen?
	return self._profile.specimens[id]
end

function Collection.tutorialDone(self: any): boolean
	return self._profile.tutorialDone
end

function Collection.setTutorialDone(self: any, done: boolean)
	self._profile.tutorialDone = done
end

-- ─── Objectifs ─────────────────────────────────────────────────────────

local function conditionMet(self: any, condition: any): boolean
	local profile = self._profile
	if condition.type == "captures" then
		return profile.stats.totalCaptures >= (condition.count or 1)
	elseif condition.type == "species" then
		return self:discoveredCount() >= (condition.count or 1)
	elseif condition.type == "mutation" then
		return (profile.stats.mutations[condition.mutation] or 0) > 0
	end
	return false
end

-- Valide les objectifs atteints et non encore validés ; retourne leurs identifiants.
function Collection.evaluateObjectives(self: any): { string }
	local completed = {}
	local profile = self._profile
	for _, objective in self._objectives do
		if profile.objectives[objective.id] == nil and conditionMet(self, objective.condition) then
			profile.objectives[objective.id] = self._now()
			profile.cosmetics.unlocked[objective.reward.id] = true
			table.insert(completed, objective.id)
		end
	end
	return completed
end

-- ─── Écriture ──────────────────────────────────────────────────────────

--[[
	Ajoute un exemplaire pour la capture `key`. Retours :
	(true, GrantInfo) ou (false, "Duplicate" | "CollectionFull" | "BadSpecies" | "BadKey" | "BadRarity").
]]
function Collection.grant(
	self: any,
	key: string,
	speciesId: string,
	rarity: string,
	mutation: string,
	seed: number
): (boolean, any)
	if type(key) ~= "string" or key == "" then
		return false, "BadKey"
	end
	if type(speciesId) ~= "string" or speciesId == "" then
		return false, "BadSpecies"
	end
	if type(rarity) ~= "string" or rarity == "" then
		return false, "BadRarity"
	end
	local profile = self._profile
	if profile.grants[key] ~= nil then
		return false, "Duplicate"
	end
	if self:isFull() then
		return false, "CollectionFull"
	end

	local now = self._now()
	local id = ProfileSchema.specimenId(self.userId, profile.nextSerial)
	profile.nextSerial += 1
	local specimen: ProfileSchema.Specimen = {
		id = id,
		speciesId = speciesId,
		rarity = rarity,
		mutation = mutation,
		seed = math.floor(seed),
		acquiredAt = now,
		favorite = false,
	}
	profile.specimens[id] = specimen
	self._owned += 1
	self._bySpecies[speciesId] = (self._bySpecies[speciesId] or 0) + 1

	-- Idempotence persistante, bornée aux MaxGrants captures les plus récentes.
	profile.grants[key] = id
	table.insert(profile.grantOrder, key)
	while #profile.grantOrder > ProfileSchema.MaxGrants do
		local oldest = table.remove(profile.grantOrder, 1)
		if oldest then
			profile.grants[oldest] = nil
		end
	end

	local entry = profile.codex[speciesId]
	local isNewSpecies = entry == nil
	if entry == nil then
		entry = { discoveredAt = now, order = self:discoveredCount() + 1, captured = 0, mutations = {} }
		profile.codex[speciesId] = entry
	end
	assert(entry, "codex")
	entry.captured += 1
	local isNewMutation = entry.mutations[mutation] ~= true
	entry.mutations[mutation] = true

	profile.stats.totalCaptures += 1
	profile.stats.mutations[mutation] = (profile.stats.mutations[mutation] or 0) + 1
	profile.updatedAt = now

	local completed = self:evaluateObjectives()
	return true,
		{
			specimen = specimen,
			isNewSpecies = isNewSpecies,
			isNewMutation = isNewMutation,
			completed = completed,
			discovered = self:discoveredCount(),
			totalCaptures = profile.stats.totalCaptures,
			owned = self._owned,
		} :: GrantInfo
end

function Collection.setFavorite(self: any, id: any, value: any): (boolean, any)
	if type(id) ~= "string" or type(value) ~= "boolean" then
		return false, "BadRequest"
	end
	local specimen = self._profile.specimens[id]
	if specimen == nil then
		return false, "NotOwned"
	end
	specimen.favorite = value
	self._profile.updatedAt = self._now()
	return true, specimen
end

-- Équipe un cosmétique débloqué (ou un cosmétique par défaut). id nil = retirer (titre seulement).
function Collection.equip(self: any, kind: any, id: any): (boolean, string?)
	local cosmetics = self._profile.cosmetics
	if kind == "title" then
		if id == nil then
			cosmetics.title = nil
			return true, nil
		end
		if type(id) ~= "string" or not (cosmetics.unlocked[id] or self._defaults[id]) then
			return false, "Locked"
		end
		cosmetics.title = id
		return true, nil
	elseif kind == "scannerColor" then
		if type(id) ~= "string" or not (cosmetics.unlocked[id] or self._defaults[id]) then
			return false, "Locked"
		end
		cosmetics.scannerColor = id
		return true, nil
	end
	return false, "BadKind"
end

function Collection.setSettings(self: any, settings: any): (boolean, string?)
	if type(settings) ~= "table" then
		return false, "BadRequest"
	end
	local current = self._profile.settings
	if settings.sfx ~= nil then
		if type(settings.sfx) ~= "boolean" then
			return false, "BadRequest"
		end
		current.sfx = settings.sfx
	end
	if settings.reducedEffects ~= nil then
		if type(settings.reducedEffects) ~= "boolean" then
			return false, "BadRequest"
		end
		current.reducedEffects = settings.reducedEffects
	end
	return true, nil
end

-- ─── Vues envoyées au client ───────────────────────────────────────────

function Collection.specimenView(_self: any, s: ProfileSchema.Specimen): any
	return {
		id = s.id,
		speciesId = s.speciesId,
		rarity = s.rarity,
		mutation = s.mutation,
		seed = s.seed,
		acquiredAt = s.acquiredAt,
		favorite = s.favorite,
	}
end

function Collection.summary(self: any): any
	local profile = self._profile
	local mutations = table.clone(profile.stats.mutations)
	local codex = {}
	for speciesId, e in profile.codex do
		local found = {}
		for m in e.mutations do
			table.insert(found, m)
		end
		table.sort(found)
		codex[speciesId] = { order = e.order, captured = e.captured, discoveredAt = e.discoveredAt, mutations = found }
	end
	local objectives = table.clone(profile.objectives)
	local unlocked = {}
	for id in profile.cosmetics.unlocked do
		table.insert(unlocked, id)
	end
	table.sort(unlocked)
	return {
		totalCaptures = profile.stats.totalCaptures,
		discovered = self:discoveredCount(),
		owned = self._owned,
		maxSpecimens = ProfileSchema.MaxSpecimens,
		mutations = mutations,
		codex = codex,
		objectives = objectives,
		cosmetics = {
			title = profile.cosmetics.title,
			scannerColor = profile.cosmetics.scannerColor,
			unlocked = unlocked,
		},
		settings = { sfx = profile.settings.sfx, reducedEffects = profile.settings.reducedEffects },
	}
end

-- Vue complète (connexion) : résumé + liste des exemplaires, du plus récent au plus ancien.
function Collection.view(self: any): any
	local list = {}
	for _, s in self._profile.specimens do
		table.insert(list, self:specimenView(s))
	end
	-- À seconde égale, le numéro d'exemplaire départage (comparaison numérique, pas textuelle).
	local function serial(id: string): number
		return tonumber(string.match(id, "%-(%d+)$")) or 0
	end
	table.sort(list, function(a, b)
		if a.acquiredAt ~= b.acquiredAt then
			return a.acquiredAt > b.acquiredAt
		end
		return serial(a.id) > serial(b.id)
	end)
	local view = self:summary()
	view.specimens = list
	return view
end

return Collection
