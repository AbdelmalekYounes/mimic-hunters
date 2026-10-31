local TestKit = require("../lib/TestKit")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local named = Fixtures.named
local A, B = 1001, 2002

local function spawnPos()
	local spawn = Fixtures.MapLayout.Spawn.position
	return { X = spawn.X, Y = 3, Z = spawn.Z }
end

local function veteranWorld(seed)
	local world, config = Fixtures.world(seed)
	world:addPlayer(A, 0, Fixtures.veteran())
	world:addPlayer(B, 0, Fixtures.veteran())
	return world, config
end

local function countByZone(world)
	local counts = {}
	for _, record in world:sharedMimics() do
		local zone = world:slot(record.slotId).zone
		counts[zone] = (counts[zone] or 0) + 1
	end
	return counts
end

-- Révèle et capture un Mimic partagé pour `userId`. Retourne tous les événements et l'heure finale.
local function captureShared(world, userId, record, now, plan)
	local pos = Fixtures.near(world, record.slotId)
	local events = {}
	local e1, inspect = world:inspect(userId, pos, record.slotId, now)
	assert(inspect.result == "Mimic", "révélation attendue, obtenu " .. tostring(inspect.result or inspect.reason))
	local e2, started = world:startCapture(userId, pos, record.id, now + 0.5)
	assert(started.ok, "démarrage attendu, obtenu " .. tostring(started.reason))
	local e3, finalNow = Fixtures.playCapture(world, userId, pos, started, now + 0.5, plan or { "hit", "hit" })
	for _, list in { e1, e2, e3 } do
		for _, e in list do
			table.insert(events, e)
		end
	end
	return events, finalNow, started
end

describe("HuntWorld — mise en place", function()
	it("cache 12 Mimics, au moins 3 par zone, sans rien diffuser", function()
		local world = Fixtures.world(1)
		expect(#world:sharedMimics()).toBe(Fixtures.GameConfig.Hunt.ActiveMimics)
		for _, zone in Fixtures.MapLayout.zoneIds() do
			expect(countByZone(world)[zone] or 0).toBeAtLeast(3)
		end
		for _, record in world:sharedMimics() do
			expect(record.state).toBe("Disguised")
		end
	end)

	it("envoie l'état initial au client prêt", function()
		local world = Fixtures.world(1)
		world:addPlayer(A, 0)
		local events = world:clientReady(A, 0)
		expect(#named(events, "WorldSnapshot", A)).toBe(1)
		expect(#named(events, "CollectionSnapshot", A)).toBe(1)
		expect(named(events, "ProfileStatus", A)[1].payload.status).toBe("Ready")
		local tutorial = named(events, "TutorialUpdate", A)[1]
		expect(tutorial.payload.step).toBe("Scan")
		expect(tutorial.payload.propId).toBe("TUTO")
		-- L'instantané ne révèle aucun Mimic caché.
		expect(#named(events, "WorldSnapshot", A)[1].payload.mimics).toBe(0)
	end)
end)

describe("HuntWorld — tutoriel (première capture guidée)", function()
	it("guide de l'apparition jusqu'à la première capture", function()
		local world = Fixtures.world(2)
		world:addPlayer(A, 0)
		local pos = spawnPos()

		local scanEvents, scan = world:scan(A, pos, 1)
		expect(scan.ok).toBe(true)
		expect(scan.band).toBe("Strong")
		local flinch = false
		for _, e in named(scanEvents, "Clue", A) do
			if e.payload.propId == "TUTO" and e.payload.strong then
				flinch = true
			end
		end
		expect(flinch).toBe(true)
		expect(world:tutorialStepOf(A)).toBe("Inspect")

		local inspectEvents, inspect = world:inspect(A, pos, "TUTO", 2)
		expect(inspect.result).toBe("Mimic")
		expect(inspect.speciesId).toBe("chairy")
		expect(world:tutorialStepOf(A)).toBe("Capture")
		-- Mimic personnel : jamais diffusé aux autres joueurs.
		for _, e in inspectEvents do
			expect(e.userId).toBe(A)
		end

		local _, started = world:startCapture(A, pos, inspect.mimicId, 3)
		expect(started.ok).toBe(true)
		expect(started.maxMisses).toBe(-1)

		-- Même après plusieurs ratés, la capture du tutoriel reste possible.
		local events = Fixtures.playCapture(world, A, pos, started, 3, { "miss", "miss", "miss", "hit", "hit" })
		local resolved = named(events, "CaptureResolved", A)
		expect(#resolved).toBe(1)
		expect(resolved[1].payload.success).toBe(true)
		expect(resolved[1].payload.isNew).toBe(true)
		expect(world:inventoryOf(A):count("chairy")).toBe(1)
		expect(world:tutorialStepOf(A)).toBe("Done")
		for _, e in events do
			expect(e.userId).toBe(A)
		end

		-- La chaise du tutoriel redevient une chaise ordinaire.
		local _, after = world:inspect(A, pos, "TUTO", 30)
		expect(after.result).toBe("Ordinary")
	end)

	it("donne à chaque nouveau joueur son propre Mimic de tutoriel", function()
		local world = Fixtures.world(3)
		world:addPlayer(A, 0)
		world:addPlayer(B, 0)
		local pos = spawnPos()
		local _, ia = world:inspect(A, pos, "TUTO", 1)
		local _, ib = world:inspect(B, pos, "TUTO", 1)
		expect(ia.result).toBe("Mimic")
		expect(ib.result).toBe("Mimic")
		expect(ia.mimicId ~= ib.mimicId).toBe(true)
	end)

	it("ignore la chaise du tutoriel pour un joueur expérimenté", function()
		local world = veteranWorld(4)
		local events, scan = world:scan(A, spawnPos(), 1)
		for _, e in named(events, "Clue") do
			expect(e.payload.propId ~= "TUTO").toBe(true)
		end
		expect(scan.ok).toBe(true)
		local _, inspect = world:inspect(A, spawnPos(), "TUTO", 2)
		expect(inspect.result).toBe("Ordinary")
	end)

	it("recache le Mimic du tutoriel au même endroit après une fuite", function()
		local world = Fixtures.world(5)
		world:addPlayer(A, 0)
		local pos = spawnPos()
		local _, inspect = world:inspect(A, pos, "TUTO", 1)
		local cfg = Fixtures.GameConfig
		world:tick(1 + cfg.Tutorial.ClaimDuration + 0.1, {})
		expect(world:tutorialMimicOf(A).state).toBe("Fleeing")
		expect(world:tutorialStepOf(A)).toBe("Inspect")
		world:tick(1 + cfg.Tutorial.ClaimDuration + cfg.Hunt.FleeDuration + 0.5, {})
		local record = world:tutorialMimicOf(A)
		expect(record.state).toBe("Disguised")
		expect(record.slotId).toBe("TUTO")
		expect(record.id).toBe(inspect.mimicId)
	end)
end)

describe("HuntWorld — chasse partagée", function()
	it("capture un Mimic, l'ajoute à l'inventaire et le remplace", function()
		local world, config = veteranWorld(6)
		local record = Fixtures.findHidden(world)
		local events, now = captureShared(world, A, record, 10)

		local reveal = named(events, "MimicUpdate")[1]
		expect(reveal.userId).toBeNil() -- diffusé à tous les chasseurs
		expect(reveal.payload.state).toBe("Revealed")
		expect(reveal.payload.ownerUserId).toBe(A)

		local resolved = named(events, "CaptureResolved", A)
		expect(#resolved).toBe(1)
		expect(resolved[1].payload.success).toBe(true)
		expect(resolved[1].payload.speciesId).toBe(record.speciesId)
		expect(world:inventoryOf(A):count(record.speciesId)).toBe(1)
		expect(world:mimicAtSlot(record.slotId)).toBeNil()
		expect(#world:sharedMimics()).toBe(config.Hunt.ActiveMimics - 1)

		world:tick(now + config.Hunt.RespawnDelay + 0.1, {})
		expect(#world:sharedMimics()).toBe(config.Hunt.ActiveMimics)
		-- L'emplacement libéré n'est pas réutilisé immédiatement.
		expect(world:mimicAtSlot(record.slotId)).toBeNil()
	end)

	it("répond « ordinaire » pour un objet sans Mimic et applique un délai", function()
		local world, config = veteranWorld(7)
		local slotId = Fixtures.findEmptySlot(world)
		local pos = Fixtures.near(world, slotId)
		local _, r = world:inspect(A, pos, slotId, 1)
		expect(r.result).toBe("Ordinary")
		local _, again = world:inspect(A, pos, slotId, 1 + config.Inspect.Cooldown + 0.01)
		expect(again.reason).toBe("Cooldown")
		local _, later = world:inspect(A, pos, slotId, 1 + config.Inspect.MissCooldown + 0.01)
		expect(later.result).toBe("Ordinary")
	end)

	it("fait fuir puis recacher le Mimic après un échec, sans récompense", function()
		local world, config = veteranWorld(8)
		local record = Fixtures.findHidden(world, function(r)
			return r.speciesId == "chairy" or r.speciesId == "trashling"
		end) or Fixtures.findHidden(world)
		local oldSlot = record.slotId
		local events, now = captureShared(world, A, record, 10, { "miss", "miss" })
		local resolved = named(events, "CaptureResolved", A)[1]
		expect(resolved.payload.success).toBe(false)
		expect(resolved.payload.reason).toBe("Escaped")
		expect(record.state).toBe("Fleeing")
		expect(world:inventoryOf(A):totalCaptures()).toBe(0)

		local tickEvents = world:tick(now + config.Hunt.FleeDuration + 0.1, {})
		local hidden = named(tickEvents, "MimicUpdate")[1]
		expect(hidden.payload.state).toBe("Hidden")
		expect(hidden.payload.propId).toBe(oldSlot)
		expect(record.state).toBe("Disguised")
		expect(world:slot(record.slotId).kind).toBe(world:slot(oldSlot).kind)
		expect(#world:sharedMimics()).toBe(config.Hunt.ActiveMimics)
		-- Pas de punition : le joueur peut rechasser tout de suite.
		local _, scan = world:scan(A, Fixtures.near(world, record.slotId), now + config.Hunt.FleeDuration + 0.2)
		expect(scan.ok).toBe(true)
	end)

	it("fait fuir un Mimic révélé mais abandonné", function()
		local world, config = veteranWorld(9)
		local record = Fixtures.findHidden(world)
		world:inspect(A, Fixtures.near(world, record.slotId), record.slotId, 1)
		local events = world:tick(1 + config.Hunt.RevealClaimDuration + 0.01, {})
		expect(named(events, "MimicUpdate")[1].payload.state).toBe("Fleeing")
		local _, late = world:startCapture(
			A,
			Fixtures.near(world, record.slotId),
			record.id,
			1 + config.Hunt.RevealClaimDuration + 0.5
		)
		expect(late.ok).toBe(false)
	end)

	it("ne garde qu'une révélation par joueur", function()
		local world = veteranWorld(10)
		local list = world:sharedMimics()
		local first, second = list[1], list[2]
		world:inspect(A, Fixtures.near(world, first.slotId), first.slotId, 1)
		world:inspect(A, Fixtures.near(world, second.slotId), second.slotId, 5)
		expect(first.state).toBe("Fleeing")
		expect(second.state).toBe("Revealed")
	end)

	it("chaque capture partagée fait progresser le tutoriel jusqu'à la fin", function()
		local world = Fixtures.world(11)
		world:addPlayer(A, 0)
		local record = Fixtures.findHidden(world)
		captureShared(world, A, record, 5)
		expect(world:tutorialStepOf(A)).toBe("Done")
		expect(world:tutorialMimicOf(A)).toBeNil()
	end)
end)

describe("HuntWorld — interactions simultanées", function()
	it("verrouille un Mimic sur le premier joueur qui le révèle", function()
		local world = veteranWorld(12)
		local record = Fixtures.findHidden(world)
		local posA = Fixtures.near(world, record.slotId, 2)
		local posB = Fixtures.near(world, record.slotId, -2)

		local _, ra = world:inspect(A, posA, record.slotId, 1)
		local _, rb = world:inspect(B, posB, record.slotId, 1)
		expect(ra.result).toBe("Mimic")
		expect(rb.result).toBe("Busy")
		expect(rb.ownerUserId).toBe(A)

		local _, sb = world:startCapture(B, posB, record.id, 1.1)
		expect(sb.ok).toBe(false)
		expect(sb.reason).toBe("NotOwner")

		local _, sa = world:startCapture(A, posA, record.id, 1.2)
		expect(sa.ok).toBe(true)
		Fixtures.playCapture(world, A, posA, sa, 1.2, { "hit", "hit" })
		expect(world:inventoryOf(A):count(record.speciesId)).toBe(1)
		expect(world:inventoryOf(B):totalCaptures()).toBe(0)

		local _, after = world:inspect(B, posB, record.slotId, 5)
		expect(after.result).toBe("Ordinary")
	end)

	it("refuse une seconde tentative simultanée du même joueur", function()
		local world = veteranWorld(13)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		local _, first = world:startCapture(A, pos, record.id, 1.1)
		local _, second = world:startCapture(A, pos, record.id, 1.1)
		expect(first.ok).toBe(true)
		expect(second.ok).toBe(false)
		expect(second.reason).toBe("AlreadyCapturing")
	end)

	it("crée un exemplaire individuel par capture, avec identifiant et graine serveur", function()
		local world = veteranWorld(15)
		local specimens = {}
		for i = 1, 3 do
			local events = captureShared(world, A, Fixtures.findHidden(world), i * 10)
			local resolved = named(events, "CaptureResolved", A)[1].payload
			expect(resolved.success).toBe(true)
			local delta = named(events, "CollectionDelta", A)[1].payload
			expect(delta.added.id).toBe(resolved.specimen.id)
			expect(delta.summary.owned).toBe(i)
			table.insert(specimens, resolved.specimen)
		end
		local ids, seeds = {}, {}
		for _, s in specimens do
			expect(ids[s.id]).toBeNil()
			ids[s.id] = true
			seeds[s.seed] = true
			expect(s.rarity).toBe(Fixtures.MimicCatalog.get(s.speciesId).rarity)
			expect(type(s.acquiredAt)).toBe("number")
			expect(s.favorite).toBe(false)
		end
		local distinctSeeds = 0
		for _ in seeds do
			distinctSeeds += 1
		end
		expect(distinctSeeds).toBe(3)
	end)

	it("ne duplique jamais une récompense quand la requête est rejouée", function()
		local world = veteranWorld(14)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		local events, now, started = captureShared(world, A, record, 1)
		expect(#named(events, "CaptureResolved", A)).toBe(1)
		for i = 1, 20 do
			local replayEvents, reply = world:pulse(A, pos, started.attemptId, 0.5, 0.12, now + i * 0.3)
			expect(reply.ok).toBe(false)
			expect(reply.reason).toBe("Resolved")
			expect(#named(replayEvents, "CaptureResolved")).toBe(0)
			expect(#named(replayEvents, "CollectionDelta")).toBe(0)
		end
		expect(world:inventoryOf(A):count(record.speciesId)).toBe(1)
	end)

	it("permet à deux joueurs de capturer deux Mimics en parallèle", function()
		local world = veteranWorld(15)
		local list = world:sharedMimics()
		local ma, mb = list[1], list[2]
		local pa, pb = Fixtures.near(world, ma.slotId), Fixtures.near(world, mb.slotId)
		world:inspect(A, pa, ma.slotId, 1)
		world:inspect(B, pb, mb.slotId, 1)
		local _, sa = world:startCapture(A, pa, ma.id, 1.5)
		local _, sb = world:startCapture(B, pb, mb.id, 1.5)
		expect(sa.ok and sb.ok).toBe(true)

		-- Impulsions entrelacées A/B.
		local stageA, stageB = sa.stage, sb.stage
		local startA, startB = 1.5, 1.5
		for _ = 1, 2 do
			local tA = startA + Fixtures.hitTime(stageA)
			local tB = startB + Fixtures.hitTime(stageB)
			local _, ra = world:pulse(A, pa, sa.attemptId, tA - startA, 0.12, tA)
			local _, rb = world:pulse(B, pb, sb.attemptId, tB - startB, 0.12, tB)
			expect(ra.hit and rb.hit).toBe(true)
			if ra.stage then
				stageA, startA = ra.stage, tA
			end
			if rb.stage then
				stageB, startB = rb.stage, tB
			end
		end
		expect(world:inventoryOf(A):count(ma.speciesId)).toBe(1)
		expect(world:inventoryOf(B):count(mb.speciesId)).toBe(1)
	end)

	it("refuse qu'un joueur pilote la tentative d'un autre", function()
		local world = veteranWorld(16)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		local _, started = world:startCapture(A, pos, record.id, 1.1)
		local _, hijack = world:pulse(B, pos, started.attemptId, 1, 0.12, 2)
		expect(hijack.ok).toBe(false)
		expect(hijack.reason).toBe("NotYours")
	end)

	it("libère le Mimic si le chasseur quitte le serveur en pleine capture", function()
		local world, config = veteranWorld(17)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		world:startCapture(A, pos, record.id, 1.1)
		local events = world:removePlayer(A, 2)
		expect(record.state).toBe("Fleeing")
		for _, e in events do
			expect(e.userId ~= A).toBe(true)
		end
		world:tick(2 + config.Hunt.FleeDuration + 0.1, {})
		expect(record.state).toBe("Disguised")
		-- B peut maintenant le trouver et le capturer.
		captureShared(world, B, record, 10)
		expect(world:inventoryOf(B):count(record.speciesId)).toBe(1)
	end)

	it("clôt une tentative expirée et laisse le Mimic s'enfuir", function()
		local world, config = veteranWorld(18)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		world:startCapture(A, pos, record.id, 1.1)
		local events = world:tick(1.1 + config.Capture.AttemptTimeout + 0.1, {})
		local resolved = named(events, "CaptureResolved", A)[1]
		expect(resolved.payload.reason).toBe("Timeout")
		expect(record.state).toBe("Fleeing")
		-- Le joueur peut relancer une chasse.
		local other = Fixtures.findHidden(world)
		local _, r = world:inspect(A, Fixtures.near(world, other.slotId), other.slotId, 30)
		expect(r.result).toBe("Mimic")
	end)
end)

describe("HuntWorld — protections", function()
	it("refuse les actions hors de portée", function()
		local world = veteranWorld(19)
		local record = Fixtures.findHidden(world)
		local far = Fixtures.near(world, record.slotId, 40)
		local _, inspect = world:inspect(A, far, record.slotId, 1)
		expect(inspect.reason).toBe("OutOfRange")
		local close = Fixtures.near(world, record.slotId)
		world:inspect(A, close, record.slotId, 2)
		local _, start = world:startCapture(A, far, record.id, 2.1)
		expect(start.reason).toBe("OutOfRange")
		local _, started = world:startCapture(A, close, record.id, 2.2)
		local _, pulse = world:pulse(A, Fixtures.near(world, record.slotId, 80), started.attemptId, 1, 0.12, 3.2)
		expect(pulse.reason).toBe("OutOfRange")
	end)

	it("refuse une action depuis le ciel", function()
		local world = veteranWorld(20)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		pos.Y = 120
		local _, r = world:inspect(A, pos, record.slotId, 1)
		expect(r.reason).toBe("OutOfRange")
	end)

	it("rejette les données invalides ou inconnues", function()
		local world = veteranWorld(21)
		local pos = spawnPos()
		for _, bad in { 42, {}, "", "../../ServerStorage", string.rep("x", 200) } do
			local _, r = world:inspect(A, pos, bad, 1)
			expect(r.reason).toBe("BadInput")
		end
		expect(select(2, world:inspect(A, pos, "ZZZ", 1)).reason).toBe("UnknownProp")
		expect(select(2, world:startCapture(A, pos, "M999999", 1)).reason).toBe("UnknownMimic")
		expect(select(2, world:pulse(A, pos, "A999999", 1, 0.12, 1)).reason).toBe("UnknownAttempt")
		expect(select(2, world:pulse(A, pos, {}, 1, 0.12, 1)).reason).toBe("BadInput")
		expect(select(2, world:scan(A, "pas une position", 1)).reason).toBe("NoCharacter")
		expect(select(2, world:scan(999, pos, 1)).reason).toBe("UnknownPlayer")
	end)

	it("ignore un faux temps de latence", function()
		local world = veteranWorld(22)
		local record = Fixtures.findHidden(world)
		local pos = Fixtures.near(world, record.slotId)
		world:inspect(A, pos, record.slotId, 1)
		local _, started = world:startCapture(A, pos, record.id, 1)
		local stage = started.stage
		local perfect = Fixtures.hitTime(stage)
		-- Le serveur reçoit l'impulsion 5 s plus tard ; une fenêtre « infinie »
		-- fournie par erreur est bornée à LatencyMax.
		local late = 1 + perfect + 5
		local _, r = world:pulse(A, pos, started.attemptId, perfect, 999, late)
		local cfg = Fixtures.GameConfig.Capture
		local evaluatedAt = math.clamp(perfect, (late - 1) - cfg.LatencyMax, late - 1)
		expect(r.position).toBeCloseTo(Fixtures.CaptureMinigame.cursorAt(stage, evaluatedAt))
	end)

	it("limite le spam de requêtes avec les vraies règles", function()
		local world = Fixtures.world(23, { RateLimits = Fixtures.GameConfig.RateLimits })
		world:addPlayer(A, 0, Fixtures.veteran())
		local slotId = Fixtures.findEmptySlot(world)
		local pos = Fixtures.near(world, slotId)
		local limited = 0
		for _ = 1, 100 do
			local _, r = world:inspect(A, pos, slotId, 5)
			if r.reason == "RateLimited" then
				limited += 1
			end
		end
		expect(limited).toBeAtLeast(100 - Fixtures.GameConfig.RateLimits.Inspect.capacity)
		local scans = 0
		for _ = 1, 50 do
			local _, r = world:scan(A, pos, 6)
			if r.ok then
				scans += 1
			end
		end
		expect(scans).toBe(1) -- délai de recharge du scanner
	end)

	it("applique le délai de recharge du scanner", function()
		local world, config = veteranWorld(24)
		local _, first = world:scan(A, spawnPos(), 1)
		local _, second = world:scan(A, spawnPos(), 1.5)
		local _, third = world:scan(A, spawnPos(), 1 + config.Scanner.Cooldown)
		expect(first.ok).toBe(true)
		expect(second.reason).toBe("Cooldown")
		expect(third.ok).toBe(true)
	end)
end)

describe("HuntWorld — indices et serveurs peu peuplés", function()
	it("envoie les indices uniquement aux joueurs proches", function()
		local world = veteranWorld(25)
		local record = Fixtures.findHidden(world)
		local near = Fixtures.near(world, record.slotId)
		local far = { X = 1000, Y = 3, Z = 1000 }
		local nearCount, farCount = 0, 0
		for t = 1, 40 do
			for _, e in named(world:tick(t, { [A] = near, [B] = far }), "Clue") do
				if e.userId == A and e.payload.propId == record.slotId then
					nearCount += 1
				elseif e.userId == B then
					farCount += 1
				end
			end
		end
		expect(nearCount).toBeAtLeast(2)
		expect(farCount).toBe(0)
	end)

	it("garde 12 Mimics répartis pour un joueur seul qui capture en boucle", function()
		local world, config = veteranWorld(26)
		local now = 1
		for _ = 1, 20 do
			local record = Fixtures.findHidden(world)
			local _, finalNow = captureShared(world, A, record, now)
			now = finalNow + config.Hunt.RespawnDelay + 0.5
			world:tick(now, {})
		end
		expect(world:inventoryOf(A):totalCaptures()).toBe(20)
		expect(#world:sharedMimics()).toBe(config.Hunt.ActiveMimics)
		local counts = countByZone(world)
		for _, zone in Fixtures.MapLayout.zoneIds() do
			expect(counts[zone] or 0).toBeAtLeast(config.Hunt.MinPerZone)
		end
	end)

	it("permet de découvrir plusieurs espèces rapidement", function()
		local world = veteranWorld(27)
		local species = {}
		for _, record in world:sharedMimics() do
			species[record.speciesId] = true
		end
		local distinct = 0
		for _ in species do
			distinct += 1
		end
		expect(distinct).toBeAtLeast(4)
	end)
end)

describe("HuntWorld — profil", function()
	it("exporte et restaure collection et tutoriel", function()
		local world = Fixtures.world(28)
		world:addPlayer(A, 0)
		captureShared(world, A, Fixtures.findHidden(world), 5)
		local profile = world:getProfile(A)
		expect(profile.tutorialDone).toBe(true)
		expect(profile.stats.totalCaptures).toBe(1)

		local other = Fixtures.world(29)
		other:addPlayer(A, 0, profile)
		expect(other:inventoryOf(A):totalCaptures()).toBe(1)
		expect(other:tutorialStepOf(A)).toBe("Done")
		expect(other:tutorialMimicOf(A)).toBeNil()
	end)
end)
