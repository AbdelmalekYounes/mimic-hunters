--!strict
--[[
	ProfileSchema — format persistant d'un profil joueur (schéma v3) et migrations.

	Le profil est ce qui est écrit dans le DataStore (dans record.data, voir ProfileSession).
	Il ne contient que des types acceptés par les DataStores : tables à clés texte,
	listes contiguës, nombres, textes, booléens.

	Profil v2 :
	{
		schemaVersion = 2,
		createdAt, updatedAt,         -- os.time()
		nextSerial = 1,               -- compteur des identifiants d'exemplaires (jamais réutilisé)
		specimens = { [id] = Specimen },
		codex = { [speciesId] = { discoveredAt, order, captured, mutations = { [mutationId] = true } } },
		grants = { [captureKey] = specimenId },  -- idempotence : une capture = un exemplaire
		grantOrder = { captureKey },             -- pour borner `grants` (les plus anciens sont oubliés)
		objectives = { [objectiveId] = completedAt },
		cosmetics = { title = id?, scannerColor = id, unlocked = { [rewardId] = true } },
		settings = { sfx = boolean, reducedEffects = boolean },
		stats = { totalCaptures, mutations = { [mutationId] = count } },
		tutorialDone = boolean,
		-- v3 (V0.3) :
		museum = { slots = { specimenId | "" } × 6, wall, lighting, pedestal, theme },
		hunts = { played, completed, best, museums = { ["<userId>"] = lastAt }, museumOrder = { "<userId>" } },
	}

	museum.slots ne contient QUE des identifiants d'exemplaires possédés (jamais une copie du
	Mimic) ; "" = vitrine vide. Un même exemplaire n'apparaît que dans une vitrine.
	hunts.museums : musées où le joueur a réussi au moins une trouvaille en Museum Hunt
	(compteur de musées différents, borné à MaxHuntMuseums).

	Specimen = { id, speciesId, rarity, mutation, seed, acquiredAt, favorite }
	  - id : "S<userId d'origine>-<numéro>", attribué par le serveur, unique même après un futur échange ;
	  - rarity : figée à la capture (un rééquilibrage ne modifie pas les exemplaires possédés) ;
	  - seed : graine de la variation d'apparence (SpecimenLook), reproductible sur tout client.

	Migrations : chaque étape transforme la version N en N+1. Une version plus récente que
	celle du code est refusée (un ancien serveur ne doit jamais écraser un profil plus récent).
]]

export type Specimen = {
	id: string,
	speciesId: string,
	rarity: string,
	mutation: string,
	seed: number,
	acquiredAt: number,
	favorite: boolean,
}

export type CodexEntry = {
	discoveredAt: number,
	order: number,
	captured: number,
	mutations: { [string]: boolean },
}

export type Profile = {
	schemaVersion: number,
	createdAt: number,
	updatedAt: number,
	nextSerial: number,
	specimens: { [string]: Specimen },
	codex: { [string]: CodexEntry },
	grants: { [string]: string },
	grantOrder: { string },
	objectives: { [string]: number },
	cosmetics: { title: string?, scannerColor: string, unlocked: { [string]: boolean } },
	settings: { sfx: boolean, reducedEffects: boolean },
	stats: { totalCaptures: number, mutations: { [string]: number } },
	tutorialDone: boolean,
	museum: Museum,
	hunts: Hunts,
}

export type Museum = {
	slots: { string },
	wall: string,
	lighting: string,
	pedestal: string,
	theme: string,
}

export type Hunts = {
	played: number,
	completed: number,
	best: number,
	museums: { [string]: number },
	museumOrder: { string },
}

export type Context = {
	userId: number,
	now: number,
	-- Rareté actuelle d'une espèce (nil si l'espèce n'existe plus).
	rarityOf: (speciesId: string) -> string?,
}

local ProfileSchema = {}

ProfileSchema.Version = 3
-- Vitrines du musée de départ.
ProfileSchema.MuseumSlots = 6
-- Musées différents mémorisés pour la Museum Hunt.
ProfileSchema.MaxHuntMuseums = 200
ProfileSchema.MuseumDefaults =
	table.freeze({ wall = "lilac", lighting = "dusk", pedestal = "classic", theme = "mystic" })
ProfileSchema.DefaultScannerColor = "Cyan"
-- Limite de taille : ~140 octets par exemplaire, bien sous les 4 Mo d'une clé DataStore.
ProfileSchema.MaxSpecimens = 2000
-- Nombre de clés de capture mémorisées pour l'idempotence.
ProfileSchema.MaxGrants = 100

function ProfileSchema.new(now: number): Profile
	return {
		schemaVersion = ProfileSchema.Version,
		createdAt = now,
		updatedAt = now,
		nextSerial = 1,
		specimens = {},
		codex = {},
		grants = {},
		grantOrder = {},
		objectives = {},
		cosmetics = { title = nil, scannerColor = ProfileSchema.DefaultScannerColor, unlocked = {} },
		settings = { sfx = true, reducedEffects = false },
		stats = { totalCaptures = 0, mutations = {} },
		tutorialDone = false,
		museum = ProfileSchema.newMuseum(),
		hunts = ProfileSchema.newHunts(),
	}
end

function ProfileSchema.newMuseum(): Museum
	local slots = {}
	for i = 1, ProfileSchema.MuseumSlots do
		slots[i] = ""
	end
	local d = ProfileSchema.MuseumDefaults
	return { slots = slots, wall = d.wall, lighting = d.lighting, pedestal = d.pedestal, theme = d.theme }
end

function ProfileSchema.newHunts(): Hunts
	return { played = 0, completed = 0, best = 0, museums = {}, museumOrder = {} }
end

function ProfileSchema.specimenId(userId: number, serial: number): string
	return string.format("S%d-%d", userId, serial)
end

-- Graine déterministe (utilisée par la migration v1, où aucune graine n'existait).
local function hashSeed(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return if h == 0 then 1 else h
end
ProfileSchema.hashSeed = hashSeed

-- ─── Migrations ────────────────────────────────────────────────────────

local migrations: { [number]: (data: any, context: Context) -> any } = {}

--[[
	v1 (V0.1, jamais écrit dans un DataStore, seulement en mémoire) :
	{ version = 1, inventory = { version = 1, totalCaptures, species = { [id] = { count, discoveryOrder } } }, tutorialDone }
	Chaque capture comptée devient un exemplaire Standard, avec une graine déterministe.
]]
migrations[1] = function(data: any, context: Context): any
	local profile = ProfileSchema.new(context.now)
	profile.tutorialDone = data.tutorialDone == true
	local inventory = data.inventory
	local species = if type(inventory) == "table" and type(inventory.species) == "table" then inventory.species else {}
	local ids = {}
	for speciesId, entry in species do
		if type(speciesId) == "string" and type(entry) == "table" and type(entry.count) == "number" then
			table.insert(ids, { id = speciesId, entry = entry })
		end
	end
	table.sort(ids, function(a, b)
		local oa = if type(a.entry.discoveryOrder) == "number" then a.entry.discoveryOrder else math.huge
		local ob = if type(b.entry.discoveryOrder) == "number" then b.entry.discoveryOrder else math.huge
		if oa ~= ob then
			return oa < ob
		end
		return a.id < b.id
	end)
	for order, item in ids do
		local rarity = context.rarityOf(item.id)
		local count = math.clamp(math.floor(item.entry.count), 0, ProfileSchema.MaxSpecimens)
		if rarity and count > 0 then
			profile.codex[item.id] =
				{ discoveredAt = context.now, order = order, captured = count, mutations = { Standard = true } }
			for i = 1, count do
				local id = ProfileSchema.specimenId(context.userId, profile.nextSerial)
				profile.nextSerial += 1
				profile.specimens[id] = {
					id = id,
					speciesId = item.id,
					rarity = rarity,
					mutation = "Standard",
					seed = hashSeed(string.format("%d:%s:%d", context.userId, item.id, i)),
					acquiredAt = context.now,
					favorite = false,
				}
			end
			profile.stats.totalCaptures += count
		end
	end
	profile.stats.mutations.Standard = profile.stats.totalCaptures
	return profile
end

--[[
	v2 (V0.2) → v3 (V0.3) : ajoute le musée (vitrines vides, styles par défaut) et les
	statistiques de Museum Hunt. Tout le reste est conservé tel quel : aucun exemplaire,
	objectif ou réglage n'est modifié.
]]
migrations[2] = function(data: any, _context: Context): any
	local out = table.clone(data)
	out.schemaVersion = 3
	if type(out.museum) ~= "table" then
		out.museum = ProfileSchema.newMuseum()
	end
	if type(out.hunts) ~= "table" then
		out.hunts = ProfileSchema.newHunts()
	end
	return out
end

-- ─── Validation ────────────────────────────────────────────────────────

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function str(v: any): string?
	return if type(v) == "string" and v ~= "" and #v <= 64 then v else nil
end

--[[
	Répare un profil v2 lu dans le stockage : tout champ invalide est remplacé par sa valeur
	par défaut, tout exemplaire invalide est écarté (et compté dans `dropped`).
	Ne lève jamais d'erreur.
]]
function ProfileSchema.sanitize(data: any, context: Context): (Profile, number)
	local profile = ProfileSchema.new(context.now)
	local dropped = 0
	profile.createdAt = if isNumber(data.createdAt) then data.createdAt else context.now
	profile.updatedAt = if isNumber(data.updatedAt) then data.updatedAt else context.now
	profile.tutorialDone = data.tutorialDone == true

	local maxSerial = 0
	if type(data.specimens) == "table" then
		for key, s in data.specimens do
			local ok = type(key) == "string"
				and type(s) == "table"
				and s.id == key
				and str(s.speciesId) ~= nil
				and str(s.rarity) ~= nil
				and str(s.mutation) ~= nil
				and isNumber(s.seed)
				and isNumber(s.acquiredAt)
			if ok then
				profile.specimens[key] = {
					id = key,
					speciesId = s.speciesId,
					rarity = s.rarity,
					mutation = s.mutation,
					seed = math.floor(s.seed),
					acquiredAt = s.acquiredAt,
					favorite = s.favorite == true,
				}
				local serial = tonumber(string.match(key, "%-(%d+)$"))
				if serial and serial > maxSerial then
					maxSerial = serial
				end
			else
				dropped += 1
			end
		end
	end
	-- Le compteur ne recule jamais sous un numéro déjà utilisé.
	local serial = if isNumber(data.nextSerial) then math.floor(data.nextSerial) else 1
	profile.nextSerial = math.max(serial, maxSerial + 1, 1)

	if type(data.codex) == "table" then
		for speciesId, e in data.codex do
			if str(speciesId) and type(e) == "table" and isNumber(e.order) then
				local mutations = {}
				if type(e.mutations) == "table" then
					for m, v in e.mutations do
						if str(m) and v == true then
							mutations[m] = true
						end
					end
				end
				profile.codex[speciesId] = {
					discoveredAt = if isNumber(e.discoveredAt) then e.discoveredAt else context.now,
					order = e.order,
					captured = if isNumber(e.captured) then math.max(0, math.floor(e.captured)) else 0,
					mutations = mutations,
				}
			end
		end
	end

	if type(data.grantOrder) == "table" and type(data.grants) == "table" then
		for _, key in data.grantOrder do
			local target = data.grants[key]
			if str(key) and type(target) == "string" and profile.grants[key] == nil then
				profile.grants[key] = target
				table.insert(profile.grantOrder, key)
			end
		end
	end

	if type(data.objectives) == "table" then
		for id, at in data.objectives do
			if str(id) and isNumber(at) then
				profile.objectives[id] = at
			end
		end
	end

	local cosmetics = data.cosmetics
	if type(cosmetics) == "table" then
		if type(cosmetics.unlocked) == "table" then
			for id, v in cosmetics.unlocked do
				if str(id) and v == true then
					profile.cosmetics.unlocked[id] = true
				end
			end
		end
		profile.cosmetics.title = str(cosmetics.title)
		profile.cosmetics.scannerColor = str(cosmetics.scannerColor) or ProfileSchema.DefaultScannerColor
	end

	local settings = data.settings
	if type(settings) == "table" then
		profile.settings.sfx = settings.sfx ~= false
		profile.settings.reducedEffects = settings.reducedEffects == true
	end

	-- Musée : seuls des exemplaires possédés, chacun dans une seule vitrine.
	local museum = data.museum
	if type(museum) == "table" then
		local used: { [string]: boolean } = {}
		if type(museum.slots) == "table" then
			for i = 1, ProfileSchema.MuseumSlots do
				local id = museum.slots[i]
				if type(id) == "string" and id ~= "" then
					if profile.specimens[id] ~= nil and not used[id] then
						profile.museum.slots[i] = id
						used[id] = true
					else
						-- Référence inexistante ou en double : vitrine vidée (l'exemplaire, s'il
						-- existe, reste dans la collection).
						dropped += 1
					end
				end
			end
		end
		for _, kind in { "wall", "lighting", "pedestal", "theme" } do
			profile.museum[kind] = str(museum[kind]) or ProfileSchema.MuseumDefaults[kind]
		end
	end

	local hunts = data.hunts
	if type(hunts) == "table" then
		for _, key in { "played", "completed", "best" } do
			local value = hunts[key]
			profile.hunts[key] = if isNumber(value) then math.max(0, math.floor(value)) else 0
		end
		if type(hunts.museumOrder) == "table" and type(hunts.museums) == "table" then
			for _, key in hunts.museumOrder do
				local at = hunts.museums[key]
				if str(key) and isNumber(at) and profile.hunts.museums[key] == nil then
					profile.hunts.museums[key] = at
					table.insert(profile.hunts.museumOrder, key)
				end
			end
		end
	end

	local stats = data.stats
	if type(stats) == "table" then
		profile.stats.totalCaptures = if isNumber(stats.totalCaptures)
			then math.max(0, math.floor(stats.totalCaptures))
			else 0
		if type(stats.mutations) == "table" then
			for m, n in stats.mutations do
				if str(m) and isNumber(n) then
					profile.stats.mutations[m] = math.max(0, math.floor(n))
				end
			end
		end
	end
	return profile, dropped
end

--[[
	Lit des données brutes (nil, v1 ou v2) et retourne un profil v2 valide.
	Retours : (profil, nil) ou (nil, "FutureVersion" | "Corrupt").
	nil en entrée = nouveau joueur : un profil neuf est créé.
]]
function ProfileSchema.migrate(data: any, context: Context): (Profile?, string?)
	if data == nil then
		return ProfileSchema.new(context.now), nil
	end
	if type(data) ~= "table" then
		return nil, "Corrupt"
	end
	local version = data.schemaVersion or data.version
	if not isNumber(version) or version < 1 then
		return nil, "Corrupt"
	end
	if version > ProfileSchema.Version then
		return nil, "FutureVersion"
	end
	local current = data
	while version < ProfileSchema.Version do
		local step = migrations[version]
		if step == nil then
			return nil, "Corrupt"
		end
		current = step(current, context)
		version += 1
	end
	local profile = ProfileSchema.sanitize(current, context)
	return profile, nil
end

function ProfileSchema.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = ProfileSchema.deepCopy(v)
	end
	return out
end

return ProfileSchema
