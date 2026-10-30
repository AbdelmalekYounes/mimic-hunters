local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Fixtures = require("../lib/Fixtures")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local CaptureMinigame = Loader.shared("Logic/CaptureMinigame")
local Rng = Loader.shared("Logic/Rng")
local GameConfig = Loader.shared("Config/GameConfig")

local CFG = GameConfig.Capture
local DIFFICULTY = { speed = 0.8, zoneWidth = 0.24, speedUp = 0.25, shrink = 0.2 }

local function newAttempt(maxMisses, rngSeed)
	return CaptureMinigame.newAttempt({
		id = "A1",
		userId = 1,
		mimicId = "M1",
		speciesId = "chairy",
		slotId = "V01",
		personal = false,
		difficulty = DIFFICULTY,
		now = 100,
		timeout = 14,
		hitsRequired = 2,
		maxMisses = maxMisses,
		rng = Rng.new(rngSeed or 9),
	})
end

-- Envoie une impulsion « honnête » : temps client = temps serveur.
local function pulse(attempt, mode, rng)
	local stage = attempt.stage
	local elapsed = if mode == "hit" then Fixtures.hitTime(stage) else Fixtures.missTime(stage)
	local now = attempt.stageStartedAt + elapsed
	return CaptureMinigame.evaluatePulse(attempt, elapsed, now, 0.12, CFG, rng or Rng.new(1)), now
end

describe("CaptureMinigame.cursorAt", function()
	it("fait des allers-retours entre 0 et 1 (phase 0)", function()
		local stage = { index = 1, speed = 1, center = 0.5, width = 0.2, phase = 0 }
		expect(CaptureMinigame.cursorAt(stage, 0)).toBeCloseTo(0)
		expect(CaptureMinigame.cursorAt(stage, 0.5)).toBeCloseTo(0.5)
		expect(CaptureMinigame.cursorAt(stage, 1)).toBeCloseTo(1)
		expect(CaptureMinigame.cursorAt(stage, 1.5)).toBeCloseTo(0.5)
		expect(CaptureMinigame.cursorAt(stage, 2)).toBeCloseTo(0)
	end)

	it("part de l'extrémité haute en phase 1", function()
		local stage = { index = 1, speed = 1, center = 0.2, width = 0.2, phase = 1 }
		expect(CaptureMinigame.cursorAt(stage, 0)).toBeCloseTo(1)
		expect(CaptureMinigame.cursorAt(stage, 0.25)).toBeCloseTo(0.75)
	end)

	it("ignore un temps négatif", function()
		local stage = { index = 1, speed = 1, center = 0.5, width = 0.2, phase = 0 }
		expect(CaptureMinigame.cursorAt(stage, -5)).toBeCloseTo(0)
	end)
end)

describe("CaptureMinigame.makeStage", function()
	it("garde la zone entièrement dans la jauge", function()
		local rng = Rng.new(31)
		for _ = 1, 500 do
			local stage = CaptureMinigame.makeStage(DIFFICULTY, 1, rng)
			expect(stage.center - stage.width / 2).toBeGreaterThan(0)
			expect(stage.center + stage.width / 2).toBeLessThan(1)
		end
	end)

	it("accélère et rétrécit la zone à l'étape suivante", function()
		local rng = Rng.new(4)
		local s1 = CaptureMinigame.makeStage(DIFFICULTY, 1, rng)
		local s2 = CaptureMinigame.makeStage(DIFFICULTY, 2, rng)
		expect(s2.speed).toBeGreaterThan(s1.speed)
		expect(s2.width).toBeLessThan(s1.width)
	end)

	it("ne démarre jamais le curseur dans la zone", function()
		local rng = Rng.new(12)
		for _ = 1, 300 do
			local stage = CaptureMinigame.makeStage(DIFFICULTY, 1, rng)
			local start = CaptureMinigame.cursorAt(stage, 0)
			expect(CaptureMinigame.isHit(stage, start, CFG.HitTolerance)).toBe(false)
		end
	end)
end)

describe("CaptureMinigame.evaluatePulse", function()
	it("stabilise le Mimic après deux impulsions réussies", function()
		local attempt = newAttempt(2)
		local r1 = pulse(attempt, "hit")
		expect(r1.accepted).toBe(true)
		expect(r1.hit).toBe(true)
		expect(r1.status).toBe("Active")
		expect(r1.stage.index).toBe(2)
		local r2 = pulse(attempt, "hit")
		expect(r2.hit).toBe(true)
		expect(r2.status).toBe("Succeeded")
		expect(attempt.hits).toBe(2)
	end)

	it("laisse s'échapper le Mimic après deux ratés", function()
		local attempt = newAttempt(2)
		expect(pulse(attempt, "miss").status).toBe("Active")
		local r = pulse(attempt, "miss")
		expect(r.hit).toBe(false)
		expect(r.status).toBe("Failed")
	end)

	it("tolère un raté puis deux réussites", function()
		local attempt = newAttempt(2)
		pulse(attempt, "miss")
		pulse(attempt, "hit")
		expect(pulse(attempt, "hit").status).toBe("Succeeded")
		expect(attempt.misses).toBe(1)
	end)

	it("refuse une impulsion trop précoce sans la compter", function()
		local attempt = newAttempt(2)
		local r = CaptureMinigame.evaluatePulse(attempt, 0.05, attempt.stageStartedAt + 0.05, 0.12, CFG, Rng.new(1))
		expect(r.accepted).toBe(false)
		expect(r.reason).toBe("TooEarly")
		expect(attempt.pulses).toBe(0)
	end)

	it("refuse deux impulsions trop rapprochées", function()
		local attempt = newAttempt(2)
		local _, now = pulse(attempt, "miss")
		-- Requête rejouée immédiatement (double clic, script).
		local r = CaptureMinigame.evaluatePulse(attempt, 0.3, now + 0.05, 0.12, CFG, Rng.new(1))
		expect(r.accepted).toBe(false)
		expect(r.reason == "TooFast" or r.reason == "TooEarly").toBe(true)
		expect(attempt.pulses).toBe(1)
	end)

	it("rejette les entrées invalides", function()
		for _, bad in { "0.5", 0 / 0, math.huge, -math.huge, nil, {} } do
			local attempt = newAttempt(2)
			local r = CaptureMinigame.evaluatePulse(attempt, bad, attempt.stageStartedAt + 1, 0.12, CFG, Rng.new(1))
			expect(r.accepted).toBe(false)
			expect(r.reason).toBe("BadInput")
		end
	end)

	it("borne l'horodatage client à la fenêtre de latence (anti-triche)", function()
		local attempt = newAttempt(2)
		local stage = attempt.stage
		-- Le tricheur prétend avoir appuyé au moment parfait, mais envoie sa
		-- requête bien plus tard, quand le curseur est loin de la zone.
		local perfect = Fixtures.hitTime(stage)
		local late = Fixtures.missTime({
			index = stage.index,
			speed = stage.speed,
			center = stage.center,
			width = stage.width,
			phase = stage.phase,
		})
		while late < perfect + 0.5 do
			late += 2 / stage.speed
		end
		local r = CaptureMinigame.evaluatePulse(attempt, perfect, attempt.stageStartedAt + late, 0.12, CFG, Rng.new(1))
		expect(r.accepted).toBe(true)
		expect(r.hit).toBe(false)
	end)

	it("n'accepte pas un horodatage dans le futur", function()
		local attempt = newAttempt(2)
		local stage = attempt.stage
		local missAt = Fixtures.missTime(stage)
		local perfect = Fixtures.hitTime(stage)
		if perfect > missAt then
			-- Le client affirme être plus avancé que le serveur : borné à serverElapsed.
			local r =
				CaptureMinigame.evaluatePulse(attempt, perfect, attempt.stageStartedAt + missAt, 0.12, CFG, Rng.new(1))
			expect(r.position).toBeCloseTo(CaptureMinigame.cursorAt(stage, missAt))
		end
	end)

	it("accepte un léger retard réseau dans la fenêtre", function()
		local attempt = newAttempt(2)
		local perfect = Fixtures.hitTime(attempt.stage)
		local r = CaptureMinigame.evaluatePulse(
			attempt,
			perfect,
			attempt.stageStartedAt + perfect + 0.1,
			0.12,
			CFG,
			Rng.new(1)
		)
		expect(r.hit).toBe(true)
	end)

	it("expire après le délai et refuse ensuite toute impulsion", function()
		local attempt = newAttempt(2)
		local r = CaptureMinigame.evaluatePulse(attempt, 1, attempt.expiresAt + 0.1, 0.12, CFG, Rng.new(1))
		expect(r.accepted).toBe(false)
		expect(r.reason).toBe("Expired")
		expect(attempt.status).toBe("Expired")
		local again = CaptureMinigame.evaluatePulse(attempt, 1, attempt.expiresAt + 1, 0.12, CFG, Rng.new(1))
		expect(again.reason).toBe("Resolved")
	end)

	it("ne compte plus rien après la réussite", function()
		local attempt = newAttempt(2)
		pulse(attempt, "hit")
		pulse(attempt, "hit")
		local r = pulse(attempt, "hit")
		expect(r.accepted).toBe(false)
		expect(r.reason).toBe("Resolved")
		expect(attempt.hits).toBe(2)
	end)

	it("tutoriel : ratés illimités mais nombre d'impulsions plafonné", function()
		local attempt = newAttempt(nil)
		for _ = 1, CFG.MaxPulses - 1 do
			expect(pulse(attempt, "miss").status).toBe("Active")
		end
		expect(pulse(attempt, "miss").status).toBe("Failed")
	end)

	it("tutoriel : réussit après plusieurs ratés", function()
		local attempt = newAttempt(nil)
		for _ = 1, 5 do
			pulse(attempt, "miss")
		end
		pulse(attempt, "hit")
		expect(pulse(attempt, "hit").status).toBe("Succeeded")
	end)

	it("tient dans la durée cible de 5 à 12 secondes pour un joueur moyen", function()
		-- Joueur moyen : rate une fois, attend en moyenne un aller-retour par étape.
		local attempt = newAttempt(2)
		local start = attempt.createdAt
		pulse(attempt, "miss")
		pulse(attempt, "hit")
		local _, now = pulse(attempt, "hit")
		local minigame = now - start
		-- + ~1,5 s de révélation et de clic sur « Capturer ».
		expect(minigame + 1.5).toBeLessThan(12)
		expect(minigame).toBeLessThan(CFG.AttemptTimeout)
	end)
end)
