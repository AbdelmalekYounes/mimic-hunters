--!strict
--[[
	SessionMetrics — mesures de session pour les playtests (V0.3.1, jalon 7). Module pur.

	Observe les événements que le jeu produit déjà (ceux que HuntServer diffuse) et en déduit
	des mesures légères :
	- temps avant la 1re capture, la 1re ouverture du Codex, la 1re visite de sa base, la
	  1re exposition, la 1re visite d'un autre musée, la 1re Museum Hunt réussie ;
	- nombre de captures réussies et ratées, mutations obtenues ;
	- Museum Hunts lancées et terminées ; durée de session (au départ).

	Retourne des « appels d'analyse » neutres ({ kind, name, value, step }) que l'adaptateur
	(Services/AnalyticsServer) transmet à AnalyticsService en jeu publié.

	Données : aucune donnée personnelle (pas de nom, pas de texte libre, pas d'identifiant
	d'exemplaire) ; seulement des compteurs et des durées, gardés en mémoire pour la session.
	Totalement indépendant des profils sauvegardés : une panne ici ne touche jamais la
	collection d'un joueur.
]]

export type Call = {
	kind: string, -- "onboarding" | "custom"
	name: string,
	value: number?,
	step: number?,
}

type Session = {
	joinedAt: number,
	firsts: { [string]: boolean },
	captures: number,
	failures: number,
	mutations: { [string]: number },
	huntsStarted: number,
	huntsCompleted: number,
}

local SessionMetrics = {}
SessionMetrics.__index = SessionMetrics

-- Entonnoir d'intégration (une seule fois par joueur, géré par Roblox) : ordre des étapes.
SessionMetrics.OnboardingSteps = table.freeze({
	"Arrivée",
	"Premier scan",
	"Première capture",
	"Codex ouvert",
	"Base visitée",
	"Premier Mimic exposé",
	"Autre musée visité",
	"Museum Hunt réussie",
})

local STEP: { [string]: number } = {}
for index, name in SessionMetrics.OnboardingSteps do
	STEP[name] = index
end

function SessionMetrics.new()
	local self = setmetatable({}, SessionMetrics)
	self._sessions = {} :: { [number]: Session }
	return self
end

function SessionMetrics.join(self: any, userId: number, now: number): { Call }
	self._sessions[userId] = {
		joinedAt = now,
		firsts = {},
		captures = 0,
		failures = 0,
		mutations = {},
		huntsStarted = 0,
		huntsCompleted = 0,
	}
	return { { kind = "onboarding", name = "Arrivée", step = STEP["Arrivée"] } }
end

-- Première fois dans la session : étape d'intégration + temps écoulé depuis l'arrivée.
local function first(session: Session, calls: { Call }, step: string, timer: string?, now: number)
	if session.firsts[step] then
		return
	end
	session.firsts[step] = true
	table.insert(calls, { kind = "onboarding", name = step, step = STEP[step] })
	if timer then
		table.insert(calls, { kind = "custom", name = timer, value = math.floor(now - session.joinedAt + 0.5) })
	end
end

--[[
	Observe un événement du jeu ({ name, userId?, payload }) et retourne les appels d'analyse.
	Les événements internes (« _… ») et ceux des autres joueurs sont ignorés sauf mention.
]]
function SessionMetrics.observe(self: any, event: any, now: number): { Call }
	local calls = {}
	local userId = event.userId
	local session = if type(userId) == "number" then self._sessions[userId] else nil
	if session == nil then
		return calls
	end
	local p = event.payload or {}
	local name = event.name
	if name == "ScanResult" and p.ok then
		first(session, calls, "Premier scan", nil, now)
	elseif name == "CaptureResolved" then
		if p.success then
			session.captures += 1
			table.insert(calls, { kind = "custom", name = "CaptureReussie", value = 1 })
			first(session, calls, "Première capture", "TempsPremiereCapture", now)
			local mutation = p.specimen and p.specimen.mutation
			if type(mutation) == "string" and mutation ~= "Standard" then
				session.mutations[mutation] = (session.mutations[mutation] or 0) + 1
				table.insert(calls, { kind = "custom", name = "Mutation" .. mutation, value = 1 })
			end
		else
			session.failures += 1
			table.insert(calls, { kind = "custom", name = "CaptureRatee", value = 1 })
		end
	elseif name == "MuseumResult" and p.ok then
		if p.action == "travel" and p.kind == "base" then
			first(session, calls, "Base visitée", "TempsPremiereBase", now)
		elseif p.action == "travel" and p.kind == "museum" then
			first(session, calls, "Autre musée visité", "TempsPremiereVisite", now)
		elseif p.action == "exhibit" then
			first(session, calls, "Premier Mimic exposé", "TempsPremiereExposition", now)
		end
	elseif name == "HuntUpdate" then
		if p.phase == "start" then
			session.huntsStarted += 1
			table.insert(calls, { kind = "custom", name = "MuseumHuntLancee", value = 1 })
		elseif p.phase == "end" then
			session.huntsCompleted += 1
			table.insert(calls, { kind = "custom", name = "MuseumHuntTerminee", value = 1 })
			if p.found == p.total then
				first(session, calls, "Museum Hunt réussie", nil, now)
			end
		end
	elseif name == "_CodexOpened" then
		-- Signalé par le client (étape purement informative, sans effet sur le jeu).
		first(session, calls, "Codex ouvert", "TempsPremierCodex", now)
	end
	return calls
end

-- Départ : durée de session et bilan ; la session est oubliée.
function SessionMetrics.leave(self: any, userId: number, now: number): { Call }
	local session = self._sessions[userId]
	self._sessions[userId] = nil
	if session == nil then
		return {}
	end
	return {
		{ kind = "custom", name = "DureeSession", value = math.floor(now - session.joinedAt + 0.5) },
		{ kind = "custom", name = "CapturesParSession", value = session.captures },
	}
end

-- Résumé d'une session en cours (tests, journal de playtest).
function SessionMetrics.snapshot(self: any, userId: number, now: number): any
	local session = self._sessions[userId]
	if session == nil then
		return nil
	end
	local firsts = {}
	for step in session.firsts do
		table.insert(firsts, step)
	end
	table.sort(firsts, function(a, b)
		return STEP[a] < STEP[b]
	end)
	return {
		minutes = (now - session.joinedAt) / 60,
		captures = session.captures,
		failures = session.failures,
		mutations = table.clone(session.mutations),
		huntsStarted = session.huntsStarted,
		huntsCompleted = session.huntsCompleted,
		firsts = firsts,
	}
end

return SessionMetrics
