--[[
	balance.luau — analyse d'équilibrage (V0.3.1, jalon 5). Lancer : `lune run tools/balance`.

	1. Museum Hunt : des « bots » jouent de vrais défis contre le vrai MuseumCore (même code
	   que le serveur), avec le temps de marche réel (vitesse du personnage, 18 studs/s).
	   Stratégies comparées :
	     - hasard     : examine les cachettes dans un ordre aléatoire ;
	     - balayage   : examine la cachette la plus proche non encore vue (force brute optimale) ;
	     - indices    : attend un indice visuel (Clue) et n'examine que l'objet qui a bougé ;
	     - scanner    : indices + scanner ; sans indice depuis 4 s, va vers la cachette que la
	                    bande du scanner désigne (approche « chasseur »).
	   On compare la configuration actuelle et une proposition (argument `--proposition`).
	2. Mutations : probabilités sur des sessions de 10, 20, 30 minutes, selon un rythme de
	   captures (hypothèse, à mesurer au playtest).
	3. Codex : nombre de captures pour découvrir les 6 espèces (pondérations réelles).

	Les résultats sont des simulations : ils ne remplacent pas des joueurs réels.
]]

local Loader = require("../tests/lib/Loader")
local Fixtures = require("../tests/lib/Fixtures")

local MuseumCore = Loader.server("Core/MuseumCore")
local MuseumLayout = Loader.server("Map/MuseumLayout")
local ProfileSchema = Loader.server("Core/ProfileSchema")
local Rng = Loader.shared("Logic/Rng")
local Mutations = Loader.shared("Config/Mutations")
local Rarities = Loader.shared("Config/Rarities")
local MimicCatalog = Loader.shared("Config/MimicCatalog")

local OWNER, VISITOR = 801, 802
local WALK_SPEED = Fixtures.GameConfig.Player.WalkSpeed
local RUNS = 400

local function profileWith(userId, list)
	local profile = ProfileSchema.new(0)
	profile.tutorialDone = true
	for i, spec in list do
		local id = ProfileSchema.specimenId(userId, i)
		profile.specimens[id] = {
			id = id,
			speciesId = spec,
			rarity = MimicCatalog.get(spec).rarity,
			mutation = "Standard",
			seed = 700 + i,
			acquiredAt = i,
			favorite = false,
		}
		profile.museum.slots[i] = id
	end
	profile.nextSerial = #list + 1
	return profile
end

local function flat(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- Joue un défi complet ; retourne { completed, found, misses, time, score }.
local function play(strategy: string, overrides: any, seed: number)
	local config = Fixtures.config(overrides)
	local world = Fixtures.world(seed)
	local core = MuseumCore.new({
		world = world,
		layout = MuseumLayout,
		config = config,
		catalog = Fixtures.MimicCatalog,
		rng = Rng.new(seed),
	})
	-- Musée typique : 3 espèces exposées, de types d'objets différents.
	world:addPlayer(OWNER, 0, profileWith(OWNER, { "chairy", "lumino", "posty" }))
	core:join(OWNER, 0)
	world:addPlayer(VISITOR, 0, ProfileSchema.new(0))
	core:join(VISITOR, 0)
	local plot = core:plotOf(OWNER)
	local pos = MuseumLayout.toWorld(plot, MuseumLayout.HuntSign)
	local now = 1
	local _, started = core:startHunt(VISITOR, OWNER, pos, now)
	assert(started.ok, "défi refusé : " .. tostring(started.reason))
	local hunt = core:huntOf(VISITOR)
	local rules = config.MuseumHunt
	local result = nil
	local clued: { [string]: boolean } = {}
	local visited: { [string]: boolean } = {}
	local scanned: { [string]: boolean } = {}
	local lastClue = now

	local function absorb(events)
		for _, e in events do
			if e.name == "Clue" and e.userId == VISITOR then
				clued[e.payload.propId] = true
				lastClue = now
			elseif e.name == "HuntUpdate" and e.userId == VISITOR then
				if e.payload.phase == "end" then
					result = e.payload
				elseif e.payload.phase == "cancel" then
					result = { cancelled = true, found = 0, misses = 0, score = 0 }
				end
			end
		end
	end
	local function advance(dt)
		local target = now + dt
		while now < target and result == nil do
			now = math.min(target, now + 0.2)
			absorb(core:tick(now, { [VISITOR] = pos }))
		end
	end
	local function spotPos(entry)
		return MuseumLayout.toWorld(plot, MuseumLayout.HuntSpots[entry.spot])
	end
	local function goTo(entry)
		local target = spotPos(entry)
		advance(flat(pos, target) / WALK_SPEED)
		pos = target
	end
	local function inspect(entry)
		if now < hunt.inspectReadyAt then
			advance(hunt.inspectReadyAt - now + 0.01)
		end
		if result then
			return
		end
		visited[entry.propId] = true
		local events = core:huntInspect(VISITOR, pos, entry.propId, now)
		absorb(events)
	end
	local function remaining()
		local list = {}
		for _, entry in hunt.props do
			if not entry.found and not visited[entry.propId] then
				table.insert(list, entry)
			end
		end
		table.sort(list, function(a, b)
			return a.spot < b.spot
		end)
		return list
	end
	local rng = Rng.new(seed * 7 + 3)

	local guard = 0
	while result == nil and guard < 2000 do
		guard += 1
		local list = remaining()
		if #list == 0 then
			advance(0.5)
			continue
		end
		local pick
		if strategy == "hasard" then
			pick = list[rng:nextInteger(1, #list)]
		elseif strategy == "balayage" then
			table.sort(list, function(a, b)
				return flat(pos, spotPos(a)) < flat(pos, spotPos(b))
			end)
			pick = list[1]
		else
			for _, entry in list do
				if clued[entry.propId] then
					pick = entry
					break
				end
			end
			if pick == nil and strategy == "scanner" then
				-- Sans indice : il passe de cachette en cachette et scanne. Une bande « Forte »
				-- fait trahir la copie la plus proche (indice fort), qu'il examine aussitôt.
				local candidates = {}
				for _, entry in list do
					if not scanned[entry.propId] then
						table.insert(candidates, entry)
					end
				end
				if #candidates == 0 then
					table.clear(scanned)
					candidates = list
				end
				table.sort(candidates, function(a, b)
					return flat(pos, spotPos(a)) < flat(pos, spotPos(b))
				end)
				local target = candidates[1]
				goTo(target)
				scanned[target.propId] = true
				if now < hunt.scanReadyAt then
					advance(hunt.scanReadyAt - now + 0.01)
				end
				if result == nil then
					absorb((core:huntScan(VISITOR, pos, now)))
				end
				continue
			end
			if pick == nil then
				advance(0.2)
				continue
			end
		end
		goTo(pick)
		inspect(pick)
	end
	local elapsed = now - 1
	return {
		completed = result ~= nil and not result.cancelled and result.found == result.total,
		found = result and result.found or 0,
		misses = result and result.misses or 0,
		time = elapsed,
		score = result and result.score or 0,
	}
end

local function summarize(strategy, overrides)
	local total = { completed = 0, found = 0, misses = 0, time = 0, score = 0 }
	local scores = {}
	for seed = 1, RUNS do
		local r = play(strategy, overrides, 1000 + seed)
		total.completed += if r.completed then 1 else 0
		total.found += r.found
		total.misses += r.misses
		total.time += r.time
		total.score += r.score
		table.insert(scores, r.score)
	end
	table.sort(scores)
	return string.format(
		"| %-9s | %5.1f %% | %4.2f | %4.2f | %5.1f s | %5.0f | %5.0f |",
		strategy,
		total.completed / RUNS * 100,
		total.found / RUNS,
		total.misses / RUNS,
		total.time / RUNS,
		total.score / RUNS,
		scores[math.floor(RUNS / 2)]
	)
end

-- Réglages de la V0.3, pour comparaison (la configuration actuelle est celle de la V0.3.1).
local before = {
	MuseumHunt = {
		MissPenalty = 15,
		MissCooldown = 1.0,
		SequentialClues = false,
		FirstClueMin = 1.5,
		ClueIntervalMin = 5,
		ClueIntervalMax = 8,
	},
}

print("# Analyse d'équilibrage MIMIC HUNTERS (simulation, " .. RUNS .. " défis par ligne)\n")
for _, variant in { { "V0.3 (avant)", before }, { "V0.3.1 (actuelle)", nil } } do
	local rules = Fixtures.config(variant[2]).MuseumHunt
	print(
		string.format(
			"## Museum Hunt — configuration %s (raté : −%d points, %.1f s d'attente)\n",
			variant[1],
			rules.MissPenalty,
			rules.MissCooldown
		)
	)
	print("| Stratégie | Réussite | Copies | Ratés | Durée | Score moyen | Score médian |")
	print("|---|---|---|---|---|---|---|")
	for _, strategy in { "hasard", "balayage", "indices", "scanner" } do
		print(summarize(strategy, variant[2]))
	end
	print("")
end

-- ─── Mutations ─────────────────────────────────────────────────────────
local chromatic = Mutations.get("Chromatic").chance
local spectral = Mutations.get("Spectral").chance
print("## Mutations (4 % Chromatic, 1,5 % Spectral) : probabilité d'en obtenir au moins une\n")
print("| Rythme | Session | Captures | ≥ 1 Chromatic | ≥ 1 Spectral | ≥ 1 mutation rare |")
print("|---|---|---|---|---|---|")
for _, rate in { 1, 1.5, 2 } do
	for _, minutes in { 10, 20, 30 } do
		local n = math.floor(rate * minutes)
		print(
			string.format(
				"| %.1f / min | %d min | %d | %.0f %% | %.0f %% | %.0f %% |",
				rate,
				minutes,
				n,
				(1 - (1 - chromatic) ^ n) * 100,
				(1 - (1 - spectral) ^ n) * 100,
				(1 - (1 - chromatic - spectral) ^ n) * 100
			)
		)
	end
end
print(
	string.format(
		"\nCaptures moyennes avant la 1re mutation rare : %.1f ; avant le 1er Spectral : %.1f.\n",
		1 / (chromatic + spectral),
		1 / spectral
	)
)

-- ─── Codex : découvrir les 6 espèces ───────────────────────────────────
local weights = {}
local totalWeight = 0
for _, species in MimicCatalog.list() do
	local w = Rarities.weightOf(species.rarity)
	table.insert(weights, { id = species.id, w = w })
	totalWeight += w
end
local rng = Rng.new(42)
local samples = {}
for _ = 1, 20000 do
	local seen, count, n = {}, 0, 0
	while count < #weights do
		n += 1
		local roll = rng:nextRange(0, totalWeight)
		for _, item in weights do
			roll -= item.w
			if roll <= 0 then
				if not seen[item.id] then
					seen[item.id] = true
					count += 1
				end
				break
			end
		end
	end
	table.insert(samples, n)
end
table.sort(samples)
local sum = 0
for _, n in samples do
	sum += n
end
print("## Codex : captures pour découvrir les 6 espèces (pondérations réelles)\n")
print(
	string.format(
		"Moyenne %.1f ; médiane %d ; 90 %% des joueurs en moins de %d captures.",
		sum / #samples,
		samples[#samples // 2],
		samples[math.floor(#samples * 0.9)]
	)
)
for _, item in weights do
	print(string.format("- %s : %.1f %% des rencontres", item.id, item.w / totalWeight * 100))
end
