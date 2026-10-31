--[[
	Fixtures — fabrique un HuntWorld complet avec la vraie configuration,
	le vrai catalogue et la vraie carte, plus des aides pour le minijeu.
]]

local Loader = require("./Loader")

local GameConfig = Loader.shared("Config/GameConfig")
local MimicCatalog = Loader.shared("Config/MimicCatalog")
local Rarities = Loader.shared("Config/Rarities")
local CaptureMinigame = Loader.shared("Logic/CaptureMinigame")
local Rng = Loader.shared("Logic/Rng")
local MapLayout = Loader.server("Map/MapLayout")
local HuntWorld = Loader.server("Core/HuntWorld")

local Fixtures = {}

Fixtures.GameConfig = GameConfig
Fixtures.MimicCatalog = MimicCatalog
Fixtures.MapLayout = MapLayout
Fixtures.CaptureMinigame = CaptureMinigame

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function merge(target: any, overrides: any)
	for k, v in overrides do
		if type(v) == "table" and type(target[k]) == "table" then
			merge(target[k], v)
		else
			target[k] = v
		end
	end
end

-- Configuration de test : copie de la vraie, avec surcharges optionnelles.
function Fixtures.config(overrides: any?): any
	local config = deepCopy(GameConfig)
	-- Les tests fonctionnels ne testent pas l'anti-spam : on l'assouplit,
	-- sauf si une surcharge le redéfinit explicitement.
	for _, rule in config.RateLimits do
		rule.capacity = 1000
		rule.refillPerSecond = 1000
	end
	if overrides then
		merge(config, overrides)
	end
	return config
end

-- `worldOptions` complète les options de HuntWorld.new (serverId, wallClock, mutations, objectives…).
function Fixtures.world(seed: number?, overrides: any?, worldOptions: any?): (any, any)
	local config = Fixtures.config(overrides)
	local options = {
		config = config,
		catalog = MimicCatalog,
		rarities = Rarities,
		slots = MapLayout.Props,
		tutorialSlot = MapLayout.TutorialProp,
		zones = MapLayout.zoneIds(),
		rng = Rng.new(seed or 1234),
		wallClock = function()
			return 1700000000
		end,
	}
	for k, v in worldOptions or {} do
		options[k] = v
	end
	local world = HuntWorld.new(options)
	world:populate(0)
	return world, config
end

-- Profil d'un joueur qui a déjà fini le tutoriel.
function Fixtures.veteran(): any
	return { version = 1, inventory = nil, tutorialDone = true }
end

-- Position d'un personnage à côté d'un emplacement.
function Fixtures.near(world: any, slotId: string, dx: number?): any
	local slot = assert(world:slot(slotId), "emplacement " .. slotId)
	return { X = slot.position.X + (dx or 3), Y = 3, Z = slot.position.Z }
end

function Fixtures.named(events: { any }, name: string, userId: number?): { any }
	local out = {}
	for _, event in events do
		if event.name == name and (userId == nil or event.userId == userId) then
			table.insert(out, event)
		end
	end
	return out
end

-- Temps écoulé pour lequel le curseur est au centre de la zone.
function Fixtures.hitTime(stage: any): number
	local t
	if stage.phase == 0 then
		t = stage.center / stage.speed
	else
		t = (1 - stage.center) / stage.speed
	end
	-- Toujours au-delà du délai minimal de l'étape.
	while t < GameConfig.Capture.MinStageElapsed do
		t += 2 / stage.speed
	end
	return t
end

-- Temps écoulé pour lequel le curseur est nettement hors de la zone.
function Fixtures.missTime(stage: any): number
	local t = GameConfig.Capture.MinStageElapsed + 0.01
	while true do
		local position = CaptureMinigame.cursorAt(stage, t)
		-- Marge large pour rester un raté même avec la fenêtre de latence.
		if math.abs(position - stage.center) > stage.width / 2 + 0.2 then
			return t
		end
		t += 0.01
	end
end

-- Trouve un emplacement occupé par un Mimic déguisé.
function Fixtures.findHidden(world: any, predicate: ((any) -> boolean)?): any
	for _, record in world:sharedMimics() do
		if record.state == "Disguised" and (predicate == nil or predicate(record)) then
			return record
		end
	end
	return nil
end

-- Trouve un emplacement partagé sans Mimic.
function Fixtures.findEmptySlot(world: any): string
	for _, spec in MapLayout.Props do
		if world:mimicAtSlot(spec.id) == nil then
			return spec.id
		end
	end
	error("aucun emplacement vide")
end

--[[
	Joue une capture complète par le serveur. `plan` est une liste de
	"hit" / "miss". Retourne la liste de tous les événements et l'heure finale.
]]
function Fixtures.playCapture(
	world: any,
	userId: number,
	position: any,
	started: any,
	startNow: number,
	plan: { string }
)
	local all = {}
	local stage = started.stage
	local stageStart = startNow
	local now = startNow
	local last = nil
	for _, step in plan do
		local elapsed = if step == "hit" then Fixtures.hitTime(stage) else Fixtures.missTime(stage)
		now = stageStart + elapsed
		local events, reply = world:pulse(userId, position, started.attemptId, elapsed, 0.12, now)
		for _, e in events do
			table.insert(all, e)
		end
		last = reply
		if reply.stage then
			stage = reply.stage
			stageStart = now
		end
	end
	return all, now, last
end

return Fixtures
