--!strict
--[[
	MuseumCore — cœur autoritaire des musées (V0.3), sans dépendance Roblox (testé dans Lune).

	Même principe que HuntWorld : chaque méthode publique reçoit des données brutes et
	retourne (events, reply). Les événements internes (« _ ») sont traités par l'adaptateur
	Roblox (MuseumServer) et jamais envoyés au client :
	- _MuseumRender { plot, ownerId, slots, styles, stats } : (re)construire un musée ;
	- _MuseumClear { plot }                                  : parcelle libérée ;
	- _Teleport { userId, plot?, point }                       : déplacer un personnage ;
	- _ProfileChanged { important }                            : sauvegarde (comme HuntWorld) ;
	- _HuntSpawn / _HuntRemoveProp / _HuntDespawn              : objets de la Museum Hunt.

	Sécurité : toute modification (vitrines, styles) porte sur la collection DU DEMANDEUR.
	Aucune requête ne prend un propriétaire cible pour modifier : un visiteur ne peut donc
	rien changer chez les autres, par construction. Visiter et chasser ne lisent que des vues.
]]

local PlotRegistry = require(script.Parent.PlotRegistry)
local RateLimiter = require(script.Parent.RateLimiter)

export type Event = { name: string, userId: number?, payload: any }

local MuseumCore = {}
MuseumCore.__index = MuseumCore

local function push(events: { Event }, name: string, userId: number?, payload: any)
	table.insert(events, { name = name, userId = userId, payload = payload })
end

--[[
	options = {
		world,        -- HuntWorld : collections et état des profils
		layout,       -- MuseumLayout (parcelles, socles, cachettes)
		config,       -- GameConfig (RateLimits, Museum)
		hunt = MuseumHunt?, rng?, catalog?   -- Museum Hunt (jalon 6)
	}
]]
function MuseumCore.new(options: any)
	local self = setmetatable({}, MuseumCore)
	self._world = options.world
	self._layout = options.layout
	self._config = options.config
	self._catalog = options.catalog
	self._rng = options.rng
	self._plots = PlotRegistry.new(#options.layout.Plots)
	self._limiter = RateLimiter.new(options.config.RateLimits)
	self._hunts = {} :: { [string]: any } -- huntId → session (jalon 6)
	self._huntCounter = 0
	self._lastHuntEnd = {} :: { [number]: number } -- visiteur → fin de son dernier défi
	return self
end

function MuseumCore.plotOf(self: any, userId: number): number?
	return self._plots:plotOf(userId)
end

function MuseumCore.ownerOf(self: any, plot: number): number?
	return self._plots:ownerOf(plot)
end

function MuseumCore._ready(self: any, userId: number): boolean
	return self._world:profileStatusOf(userId) == "Ready"
end

-- Vue complète d'un musée pour le rendu (exemplaires exposés, styles, statistiques).
function MuseumCore._renderEvent(self: any, events: { Event }, userId: number)
	local plot = self._plots:plotOf(userId)
	local collection = self._world:inventoryOf(userId)
	if plot == nil or collection == nil then
		return
	end
	local view = collection:museumView()
	push(events, "_MuseumRender", nil, {
		plot = plot,
		ownerId = userId,
		slots = view.slots,
		styles = view.styles,
		stats = view.stats,
	})
end

function MuseumCore._info(self: any, events: { Event }, userId: number)
	local plot = self._plots:plotOf(userId)
	push(events, "MuseumInfo", userId, {
		plot = plot,
		waiting = plot == nil and self._plots:isWaiting(userId),
	})
end

-- ─── Cycle de vie ──────────────────────────────────────────────────────

-- Joueur ajouté au monde : parcelle attribuée (ou file d'attente) et musée construit.
function MuseumCore.join(self: any, userId: number, _now: number): { Event }
	local events = {}
	self._plots:assign(userId)
	self:_renderEvent(events, userId)
	self:_info(events, userId)
	return events
end

-- Profil rattaché ou modifié hors requête : le musée est reconstruit.
function MuseumCore.refresh(self: any, userId: number): { Event }
	local events = {}
	self:_renderEvent(events, userId)
	return events
end

--[[
	Départ : défis en cours annulés (jalon 6), parcelle libérée puis donnée au premier joueur
	en attente. Les exemplaires ne bougent pas : ils restent dans le profil du propriétaire.
]]
function MuseumCore.leave(self: any, userId: number, now: number): { Event }
	local events = {}
	self:_cancelHuntsFor(events, userId, now)
	local freed, served = self._plots:release(userId)
	if freed then
		push(events, "_MuseumClear", nil, { plot = freed })
	end
	if served then
		self:_renderEvent(events, served)
		self:_info(events, served)
	end
	self._limiter:forget(userId)
	return events
end

-- ─── Requêtes du propriétaire (sa propre collection uniquement) ─────────

function MuseumCore._ownRequest(
	self: any,
	userId: number,
	action: string,
	now: number,
	apply: (collection: any) -> (boolean, any)
): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		payload.action = action
		push(events, "MuseumResult", userId, payload)
		return events, payload
	end
	local collection = self._world:inventoryOf(userId)
	if collection == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self:_ready(userId) then
		return reply({ ok = false, reason = "ProfileUnavailable" })
	end
	if not self._limiter:allow(userId, "Museum", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	local ok, result = apply(collection)
	if not ok then
		return reply({ ok = false, reason = result })
	end
	-- Choix délibéré du joueur : sauvegardé rapidement, comme une capture.
	push(events, "_ProfileChanged", userId, { important = true })
	self:_renderEvent(events, userId)
	return reply({
		ok = true,
		summary = collection:summary(),
		completed = if type(result) == "table" then result.completed else nil,
	})
end

-- Expose un exemplaire possédé (specimenId nil ou "" = vider la vitrine).
function MuseumCore.setExhibit(self: any, userId: number, slot: any, specimenId: any, now: number): ({ Event }, any)
	return self:_ownRequest(userId, "exhibit", now, function(collection)
		if specimenId == nil or specimenId == "" then
			return collection:clearSlot(slot)
		end
		return collection:exhibit(slot, specimenId)
	end)
end

function MuseumCore.moveExhibit(self: any, userId: number, from: any, to: any, now: number): ({ Event }, any)
	return self:_ownRequest(userId, "move", now, function(collection)
		return collection:moveExhibit(from, to)
	end)
end

function MuseumCore.setStyle(self: any, userId: number, kind: any, id: any, now: number): ({ Event }, any)
	return self:_ownRequest(userId, "style", now, function(collection)
		return collection:setMuseumStyle(kind, id)
	end)
end

-- ─── Visites ───────────────────────────────────────────────────────────

-- Musées des joueurs présents : statistiques publiques seulement.
function MuseumCore.list(self: any, userId: number, now: number): ({ Event }, any)
	local events = {}
	if not self._limiter:allow(userId, "Museum", now) then
		local payload = { ok = false, reason = "RateLimited" }
		push(events, "MuseumList", userId, payload)
		return events, payload
	end
	local entries = {}
	for _, owner in self._plots:owners() do
		local collection = self._world:inventoryOf(owner.userId)
		if collection then
			local view = collection:museumView()
			table.insert(entries, {
				userId = owner.userId,
				plot = owner.plot,
				discovered = view.stats.discovered,
				exhibited = view.stats.exhibited,
				mutationsExhibited = view.stats.mutationsExhibited,
				speciesExhibited = view.stats.speciesExhibited,
				mine = owner.userId == userId,
				busy = self:_huntInPlot(owner.plot) ~= nil,
			})
		end
	end
	local payload = { ok = true, entries = entries }
	push(events, "MuseumList", userId, payload)
	return events, payload
end

--[[
	Déplacements rapides : « base » (son musée), « village », « museum » (musée d'un joueur
	présent). Le serveur choisit la destination ; le client ne donne jamais de position.
]]
function MuseumCore.travel(self: any, userId: number, kind: any, target: any, now: number): ({ Event }, any)
	local events = {}
	local function reply(payload: any)
		payload.action = "travel"
		push(events, "MuseumResult", userId, payload)
		return events, payload
	end
	if self._world:inventoryOf(userId) == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(userId, "Travel", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if kind == "village" then
		push(events, "_Teleport", userId, { userId = userId, point = "village" })
		return reply({ ok = true, kind = "village" })
	end
	local plot
	if kind == "base" then
		plot = self._plots:plotOf(userId)
		if plot == nil then
			return reply({ ok = false, reason = if self._plots:isWaiting(userId) then "Waiting" else "NoPlot" })
		end
	elseif kind == "museum" then
		if type(target) ~= "number" then
			return reply({ ok = false, reason = "BadInput" })
		end
		plot = self._plots:plotOf(target)
		if plot == nil then
			return reply({ ok = false, reason = "UnknownMuseum" })
		end
	else
		return reply({ ok = false, reason = "BadInput" })
	end
	push(events, "_Teleport", userId, { userId = userId, plot = plot, point = "entrance" })
	return reply({ ok = true, kind = kind, plot = plot })
end

-- ─── Museum Hunt (jalon 6) ─────────────────────────────────────────────
--[[
	Mini-chasse dans le jardin d'un musée visité. Le serveur décide de tout :
	- quelles cachettes abritent des COPIES temporaires de Mimics du propriétaire (apparence
	  de ses exemplaires exposés ; les vrais exemplaires ne bougent jamais) et lesquelles sont
	  des leurres ;
	- la bande du scanner, la portée d'examen, le score, la fin et l'annulation.
	Le client n'envoie que « scanner » et « examiner telle cachette ». Les récompenses sont
	bornées (record personnel, compteur de musées DIFFÉRENTS) : rejouer ne rapporte rien de
	plus, et deux comptes qui s'aident ne gagnent chacun qu'un musée de plus.
]]

local PROP_KINDS = { "Chair", "TrashCan", "Mailbox", "Lamp", "Chest", "Vending" }

function MuseumCore._huntInPlot(self: any, plot: number): any
	for _, hunt in self._hunts do
		if hunt.plot == plot and hunt.status == "Active" then
			return hunt
		end
	end
	return nil
end

function MuseumCore.huntOf(self: any, userId: number): any
	for _, hunt in self._hunts do
		if hunt.visitorId == userId and hunt.status == "Active" then
			return hunt
		end
	end
	return nil
end

function MuseumCore._spotPosition(self: any, hunt: any, spot: number): any
	return self._layout.toWorld(hunt.plot, self._layout.HuntSpots[spot])
end

-- Distance au sol entre une position (Vector3 ou table X/Z) et un point du plan.
local function flatDistance(position: any, point: any): number
	return math.sqrt((position.X - point.X) ^ 2 + (position.Z - point.Z) ^ 2)
end

local function isPosition(position: any): boolean
	return (type(position) == "table" or typeof(position) == "Vector3")
		and type(position.X) == "number"
		and type(position.Z) == "number"
end

function MuseumCore._finishHunt(self: any, events: { Event }, hunt: any, now: number, reason: string)
	local rules = self._config.MuseumHunt
	hunt.status = "Finished"
	local remaining = math.max(0, hunt.endsAt - now)
	local bonus = if hunt.found >= hunt.total then math.floor(remaining * rules.TimeBonusPerSecond) else 0
	local score = math.max(0, hunt.found * rules.FoundPoints - hunt.misses * rules.MissPenalty + bonus)
	self._lastHuntEnd[hunt.visitorId] = now
	push(events, "_HuntDespawn", nil, { huntId = hunt.id, plot = hunt.plot })
	local collection = self._world:inventoryOf(hunt.visitorId)
	local record = nil
	if collection and self:_ready(hunt.visitorId) then
		record = collection:recordHunt(hunt.ownerId, score, hunt.found, hunt.total)
		push(events, "_ProfileChanged", hunt.visitorId, { important = true })
	end
	push(events, "HuntUpdate", hunt.visitorId, {
		phase = "end",
		huntId = hunt.id,
		reason = reason,
		ownerId = hunt.ownerId,
		score = score,
		bonus = bonus,
		found = hunt.found,
		total = hunt.total,
		misses = hunt.misses,
		best = record and record.best,
		newRecord = record and record.newRecord,
		newMuseum = record and record.newMuseum,
		museums = record and record.museums,
		completed = record and record.completed,
		summary = collection and collection:summary(),
	})
	-- Le propriétaire est prévenu (interaction sociale), sans rien perdre.
	push(events, "HuntUpdate", hunt.ownerId, {
		phase = "visitorEnd",
		visitorId = hunt.visitorId,
		found = hunt.found,
		total = hunt.total,
		score = score,
	})
end

function MuseumCore._cancelHunt(_self: any, events: { Event }, hunt: any, reason: string)
	hunt.status = "Cancelled"
	push(events, "_HuntDespawn", nil, { huntId = hunt.id, plot = hunt.plot })
	push(events, "HuntUpdate", hunt.visitorId, { phase = "cancel", huntId = hunt.id, reason = reason })
end

-- Départ d'un joueur : ses défis (comme visiteur ou propriétaire) sont annulés, sans récompense.
function MuseumCore._cancelHuntsFor(self: any, events: { Event }, userId: number, _now: number)
	for _, hunt in self._hunts do
		if hunt.status == "Active" and (hunt.visitorId == userId or hunt.ownerId == userId) then
			self:_cancelHunt(events, hunt, if hunt.ownerId == userId then "OwnerLeft" else "VisitorLeft")
		end
	end
end

-- Lance un défi chez `ownerId`. `position` : position réelle du personnage (serveur).
function MuseumCore.startHunt(self: any, visitorId: number, ownerId: any, position: any, now: number): ({ Event }, any)
	local events = {}
	local rules = self._config.MuseumHunt
	local function reply(payload: any)
		payload.phase = if payload.ok then "start" else "refused"
		push(events, "HuntUpdate", visitorId, payload)
		return events, payload
	end
	if self._world:inventoryOf(visitorId) == nil then
		return reply({ ok = false, reason = "UnknownPlayer" })
	end
	if not self._limiter:allow(visitorId, "Hunt", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if type(ownerId) ~= "number" then
		return reply({ ok = false, reason = "BadInput" })
	end
	local plot = self._plots:plotOf(ownerId)
	if plot == nil then
		return reply({ ok = false, reason = "UnknownMuseum" })
	end
	if ownerId == visitorId then
		return reply({ ok = false, reason = "OwnMuseum" })
	end
	if not self:_ready(visitorId) then
		return reply({ ok = false, reason = "ProfileUnavailable" })
	end
	if self:huntOf(visitorId) then
		return reply({ ok = false, reason = "AlreadyHunting" })
	end
	if self:_huntInPlot(plot) then
		return reply({ ok = false, reason = "Busy" })
	end
	local last = self._lastHuntEnd[visitorId]
	if last and now - last < rules.RepeatCooldown then
		return reply({ ok = false, reason = "Cooldown", remaining = rules.RepeatCooldown - (now - last) })
	end
	if not isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	local sign = self._layout.toWorld(plot, self._layout.HuntSign)
	if flatDistance(position, sign) > rules.StartRange then
		return reply({ ok = false, reason = "OutOfRange" })
	end
	local owner = self._world:inventoryOf(ownerId)
	local sources = if owner and self:_ready(ownerId) then owner:huntSources() else {}
	if #sources == 0 then
		return reply({ ok = false, reason = "EmptyMuseum" })
	end

	-- Tirages serveur : cachettes mélangées, copies parmi les exemplaires du propriétaire.
	local rng = self._rng
	local spots = {}
	for i = 1, #self._layout.HuntSpots do
		spots[i] = i
	end
	for i = #spots, 2, -1 do
		local j = rng:nextInteger(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	self._huntCounter += 1
	local huntId = "MH" .. self._huntCounter
	local hunt = {
		id = huntId,
		plot = plot,
		ownerId = ownerId,
		visitorId = visitorId,
		status = "Active",
		startedAt = now,
		endsAt = now + rules.Duration,
		found = 0,
		misses = 0,
		total = math.min(rules.Copies, #spots),
		props = {} :: { [string]: any },
		scanReadyAt = -math.huge,
		inspectReadyAt = -math.huge,
	}
	local props = {}
	for order, spot in spots do
		local propId = string.format("%s-%d", huntId, spot)
		local entry: any = { propId = propId, spot = spot, found = false }
		if order <= hunt.total then
			local source = sources[rng:nextInteger(1, #sources)]
			local species = self._catalog and self._catalog.get(source.speciesId)
			entry.copy = {
				speciesId = source.speciesId,
				mutation = source.mutation,
				seed = source.seed,
				rarity = source.rarity,
			}
			entry.kind = if species then species.kind else "Chair"
			entry.clues = if species then species.behavior.clues else { "Wiggle" }
			entry.nextClueAt = now + rng:nextRange(1.5, rules.ClueIntervalMax)
		else
			entry.kind = PROP_KINDS[rng:nextInteger(1, #PROP_KINDS)]
		end
		entry.variant = rng:nextInteger(1, 2)
		hunt.props[propId] = entry
		-- Seuls l'emplacement et l'apparence d'objet partent vers l'adaptateur : jamais « copie ou leurre ».
		table.insert(props, { propId = propId, spot = spot, kind = entry.kind, variant = entry.variant })
	end
	self._hunts[huntId] = hunt
	push(events, "_HuntSpawn", nil, { huntId = huntId, plot = plot, props = props })
	push(events, "HuntUpdate", ownerId, { phase = "visitorStart", visitorId = visitorId })
	return reply({
		ok = true,
		huntId = huntId,
		ownerId = ownerId,
		plot = plot,
		total = hunt.total,
		duration = rules.Duration,
		remaining = rules.Duration,
	})
end

-- Scan pendant un défi : bande selon la copie non trouvée la plus proche.
function MuseumCore.huntScan(self: any, visitorId: number, position: any, now: number): ({ Event }, any)
	local events = {}
	local rules = self._config.MuseumHunt
	local function reply(payload: any)
		payload.hunt = true
		push(events, "ScanResult", visitorId, payload)
		return events, payload
	end
	local hunt = self:huntOf(visitorId)
	if hunt == nil then
		return reply({ ok = false, reason = "NoHunt" })
	end
	if not self._limiter:allow(visitorId, "Hunt", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	if now < hunt.scanReadyAt then
		return reply({ ok = false, reason = "Cooldown", remaining = hunt.scanReadyAt - now })
	end
	if not isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	hunt.scanReadyAt = now + rules.ScanCooldown
	local nearest, nearestEntry = math.huge, nil
	for _, entry in hunt.props do
		if entry.copy and not entry.found then
			local d = flatDistance(position, self:_spotPosition(hunt, entry.spot))
			if d < nearest then
				nearest, nearestEntry = d, entry
			end
		end
	end
	local band = if nearest <= rules.StrongBand
		then "Strong"
		elseif nearest <= rules.MediumBand then "Medium"
		elseif nearest <= rules.WeakBand then "Weak"
		else "None"
	if band == "Strong" and nearestEntry then
		-- Tout près : la copie sursaute (indice fort), pour le seul visiteur.
		push(events, "Clue", visitorId, { propId = nearestEntry.propId, clue = nearestEntry.clues[1], strong = true })
	end
	return reply({ ok = true, band = band })
end

-- Examen d'une cachette pendant un défi.
function MuseumCore.huntInspect(self: any, visitorId: number, position: any, propId: any, now: number): ({ Event }, any)
	local events = {}
	local rules = self._config.MuseumHunt
	local function reply(payload: any)
		payload.hunt = true
		push(events, "InspectResult", visitorId, payload)
		return events, payload
	end
	local hunt = self:huntOf(visitorId)
	if hunt == nil then
		return reply({ ok = false, reason = "NoHunt" })
	end
	if not self._limiter:allow(visitorId, "Hunt", now) then
		return reply({ ok = false, reason = "RateLimited" })
	end
	local entry = if type(propId) == "string" then hunt.props[propId] else nil
	if entry == nil or entry.found then
		return reply({ ok = false, reason = "UnknownMimic" })
	end
	if now < hunt.inspectReadyAt then
		return reply({ ok = false, reason = "Cooldown" })
	end
	if not isPosition(position) then
		return reply({ ok = false, reason = "NoCharacter" })
	end
	if flatDistance(position, self:_spotPosition(hunt, entry.spot)) > rules.InspectRange then
		return reply({ ok = false, reason = "OutOfRange" })
	end
	if entry.copy then
		entry.found = true
		hunt.found += 1
		hunt.inspectReadyAt = now + rules.InspectCooldown
		push(events, "_HuntRemoveProp", nil, { huntId = hunt.id, propId = entry.propId })
		push(events, "HuntUpdate", visitorId, {
			phase = "found",
			huntId = hunt.id,
			propId = entry.propId,
			copy = entry.copy,
			-- Où jouer la révélation (l'objet est retiré au même moment).
			position = self:_spotPosition(hunt, entry.spot),
			found = hunt.found,
			total = hunt.total,
			misses = hunt.misses,
		})
		local _, payload =
			reply({ ok = true, result = "HuntFound", propId = entry.propId, speciesId = entry.copy.speciesId })
		if hunt.found >= hunt.total then
			self:_finishHunt(events, hunt, now, "Complete")
		end
		return events, payload
	end
	hunt.misses += 1
	hunt.inspectReadyAt = now + rules.MissCooldown
	push(events, "HuntUpdate", visitorId, {
		phase = "miss",
		huntId = hunt.id,
		propId = entry.propId,
		found = hunt.found,
		total = hunt.total,
		misses = hunt.misses,
	})
	return reply({ ok = true, result = "Ordinary", propId = entry.propId, kind = entry.kind })
end

--[[
	Horloge des défis (appelée régulièrement par le serveur) : fin au temps imparti,
	annulation si le visiteur quitte le jardin, indices discrets des copies.
	`positions` : userId → position réelle du personnage.
]]
function MuseumCore.tick(self: any, now: number, positions: { [number]: any }): { Event }
	local events = {}
	local rules = self._config.MuseumHunt
	for id, hunt in self._hunts do
		if hunt.status ~= "Active" then
			-- Les défis terminés sont oubliés une minute plus tard.
			if now - (hunt.endsAt or now) > 60 then
				self._hunts[id] = nil
			end
			continue
		end
		if now >= hunt.endsAt then
			self:_finishHunt(events, hunt, now, "Timeout")
			continue
		end
		local position = positions[hunt.visitorId]
		local zone = self._layout.toWorld(hunt.plot, self._layout.HuntZone.center)
		if position and flatDistance(position, zone) > rules.ZoneRadius then
			self:_cancelHunt(events, hunt, "LeftZone")
			continue
		end
		for _, entry in hunt.props do
			if entry.copy and not entry.found and now >= entry.nextClueAt then
				entry.nextClueAt = now + self._rng:nextRange(rules.ClueIntervalMin, rules.ClueIntervalMax)
				push(events, "Clue", hunt.visitorId, {
					propId = entry.propId,
					clue = entry.clues[self._rng:nextInteger(1, #entry.clues)],
					strong = false,
				})
			end
		end
	end
	return events
end

return MuseumCore
