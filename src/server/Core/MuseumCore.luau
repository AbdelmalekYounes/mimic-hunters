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

-- ─── Museum Hunt (jalon 6) : points d'accroche ─────────────────────────

function MuseumCore._huntInPlot(self: any, plot: number): any
	for _, hunt in self._hunts do
		if hunt.plot == plot and hunt.status == "Active" then
			return hunt
		end
	end
	return nil
end

function MuseumCore._cancelHuntsFor(_self: any, _events: { Event }, _userId: number, _now: number) end

return MuseumCore
