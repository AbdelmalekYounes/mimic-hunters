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
	museumStyles: any?,
	-- Emplacement d'un cosmétique (« title », « scannerColor »…) ; nil = non vérifié.
	cosmeticKind: ((id: string) -> string?)?,
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
	-- Config/MuseumStyles (options gratuites et récompenses) ; nil = styles refusés.
	self._museumStyles = options.museumStyles
	self._cosmeticKind = options.cosmeticKind
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
	elseif condition.type == "exhibits" then
		return self:exhibitedCount() >= (condition.count or 1)
	elseif condition.type == "museums" then
		return #profile.hunts.museumOrder >= (condition.count or 1)
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
-- Un cosmétique ne s'équipe que dans son emplacement (un titre n'est pas une couleur de
-- scanner). Sans catalogue fourni (anciens tests), on ne peut pas vérifier : accepté.
function Collection._cosmeticKindIs(self: any, id: string, kind: string): boolean
	local lookup = self._cosmeticKind
	if lookup == nil then
		return true
	end
	return lookup(id) == kind
end

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
		if not self:_cosmeticKindIs(id, "title") then
			return false, "BadKind"
		end
		cosmetics.title = id
		return true, nil
	elseif kind == "scannerColor" then
		if type(id) ~= "string" or not (cosmetics.unlocked[id] or self._defaults[id]) then
			return false, "Locked"
		end
		if not self:_cosmeticKindIs(id, "scannerColor") then
			return false, "BadKind"
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

-- ─── Musée (V0.3) ──────────────────────────────────────────────────────
--[[
	Les vitrines ne stockent que des identifiants d'exemplaires POSSÉDÉS. Exposer ne crée,
	ne copie ni ne déplace aucun exemplaire : il reste dans la collection, la vitrine le
	référence. Un exemplaire n'est jamais référencé par deux vitrines.
]]

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= ProfileSchema.MuseumSlots
end

function Collection.slotOf(self: any, specimenId: string): number?
	for i, id in self._profile.museum.slots do
		if id == specimenId then
			return i
		end
	end
	return nil
end

function Collection.exhibitedCount(self: any): number
	local n = 0
	for _, id in self._profile.museum.slots do
		if id ~= "" then
			n += 1
		end
	end
	return n
end

-- Expose `specimenId` dans la vitrine `slot` (remplace l'occupant éventuel).
function Collection.exhibit(self: any, slot: any, specimenId: any): (boolean, any)
	if not validSlot(slot) then
		return false, "BadSlot"
	end
	if type(specimenId) ~= "string" or self._profile.specimens[specimenId] == nil then
		return false, "NotOwned"
	end
	local current = self:slotOf(specimenId)
	if current == slot then
		return true, { completed = {} }
	end
	if current ~= nil then
		return false, "AlreadyExhibited"
	end
	self._profile.museum.slots[slot] = specimenId
	self._profile.updatedAt = self._now()
	return true, { completed = self:evaluateObjectives() }
end

function Collection.clearSlot(self: any, slot: any): (boolean, string?)
	if not validSlot(slot) then
		return false, "BadSlot"
	end
	self._profile.museum.slots[slot] = ""
	self._profile.updatedAt = self._now()
	return true, nil
end

-- Échange le contenu de deux vitrines (réorganisation ; une vitrine vide est permise).
function Collection.moveExhibit(self: any, from: any, to: any): (boolean, string?)
	if not validSlot(from) or not validSlot(to) or from == to then
		return false, "BadSlot"
	end
	local slots = self._profile.museum.slots
	slots[from], slots[to] = slots[to], slots[from]
	self._profile.updatedAt = self._now()
	return true, nil
end

-- Style du musée : option gratuite, ou récompense déjà débloquée.
function Collection.setMuseumStyle(self: any, kind: any, id: any): (boolean, string?)
	local styles = self._museumStyles
	if styles == nil or type(kind) ~= "string" or table.find(styles.Kinds, kind) == nil then
		return false, "BadKind"
	end
	if not styles.isAvailable(kind, id, self._profile.cosmetics.unlocked) then
		return false, "Locked"
	end
	self._profile.museum[kind] = id
	self._profile.updatedAt = self._now()
	return true, nil
end

--[[
	Ce que le musée affiche : exemplaire de chaque vitrine (ou false), styles, statistiques.
	Une référence devenue invalide est affichée comme vitrine vide (jamais d'erreur).
]]
function Collection.museumView(self: any): any
	local profile = self._profile
	local slots, mutations, species = {}, {}, {}
	local exhibited = 0
	for i = 1, ProfileSchema.MuseumSlots do
		local specimen = profile.specimens[profile.museum.slots[i] or ""]
		if specimen then
			slots[i] = self:specimenView(specimen)
			exhibited += 1
			mutations[specimen.mutation] = true
			species[specimen.speciesId] = true
		else
			slots[i] = false
		end
	end
	local mutationCount, speciesCount = 0, 0
	for _ in mutations do
		mutationCount += 1
	end
	for _ in species do
		speciesCount += 1
	end
	return {
		slots = slots,
		styles = {
			wall = profile.museum.wall,
			lighting = profile.museum.lighting,
			pedestal = profile.museum.pedestal,
			theme = profile.museum.theme,
		},
		stats = {
			discovered = self:discoveredCount(),
			owned = self._owned,
			totalCaptures = profile.stats.totalCaptures,
			exhibited = exhibited,
			mutationsExhibited = mutationCount,
			speciesExhibited = speciesCount,
		},
	}
end

-- Exemplaires que les copies de la Museum Hunt peuvent imiter : uniquement ceux que le
-- propriétaire a choisi d'exposer. Un musée vide ne révèle rien de la collection privée
-- (audit V0.3.1 : l'ancien repli envoyait au visiteur des exemplaires non exposés).
function Collection.huntSources(self: any): { any }
	local list = {}
	for _, specimen in self:museumView().slots do
		if specimen then
			table.insert(list, specimen)
		end
	end
	return list
end

--[[
	Résultat d'une Museum Hunt jouée chez `ownerId`. Le record est personnel ; le compteur de
	musées différents n'augmente qu'une fois par musée (et seulement avec au moins une
	trouvaille) : rejouer le même défi, seul ou à deux comptes, ne fait rien gagner de plus.
]]
function Collection.recordHunt(self: any, ownerId: number, score: number, found: number, total: number): any
	local hunts = self._profile.hunts
	local now = self._now()
	hunts.played += 1
	if found >= total and total > 0 then
		hunts.completed += 1
	end
	local newRecord = score > hunts.best
	if newRecord then
		hunts.best = score
	end
	local key = tostring(ownerId)
	local newMuseum = false
	if found > 0 and hunts.museums[key] == nil then
		hunts.museums[key] = now
		table.insert(hunts.museumOrder, key)
		newMuseum = true
		while #hunts.museumOrder > ProfileSchema.MaxHuntMuseums do
			local oldest = table.remove(hunts.museumOrder, 1)
			if oldest then
				hunts.museums[oldest] = nil
			end
		end
	elseif hunts.museums[key] ~= nil then
		hunts.museums[key] = now
	end
	self._profile.updatedAt = now
	return {
		best = hunts.best,
		newRecord = newRecord,
		newMuseum = newMuseum,
		museums = #hunts.museumOrder,
		completed = self:evaluateObjectives(),
	}
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
		museum = {
			slots = table.clone(profile.museum.slots),
			wall = profile.museum.wall,
			lighting = profile.museum.lighting,
			pedestal = profile.museum.pedestal,
			theme = profile.museum.theme,
		},
		hunts = {
			played = profile.hunts.played,
			completed = profile.hunts.completed,
			best = profile.hunts.best,
			museums = #profile.hunts.museumOrder,
		},
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
