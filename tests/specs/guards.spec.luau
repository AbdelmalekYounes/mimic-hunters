local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local RateLimiter = Loader.server("Core/RateLimiter")
local Validation = Loader.shared("Logic/Validation")
local TutorialFlow = Loader.server("Core/TutorialFlow")

describe("RateLimiter", function()
	it("autorise une rafale puis bloque", function()
		local limiter = RateLimiter.new({ Scan = { capacity = 3, refillPerSecond = 1 } })
		expect(limiter:allow(1, "Scan", 0)).toBe(true)
		expect(limiter:allow(1, "Scan", 0)).toBe(true)
		expect(limiter:allow(1, "Scan", 0)).toBe(true)
		expect(limiter:allow(1, "Scan", 0)).toBe(false)
	end)

	it("se recharge avec le temps", function()
		local limiter = RateLimiter.new({ Scan = { capacity = 1, refillPerSecond = 2 } })
		expect(limiter:allow(1, "Scan", 0)).toBe(true)
		expect(limiter:allow(1, "Scan", 0.2)).toBe(false)
		expect(limiter:allow(1, "Scan", 0.6)).toBe(true)
	end)

	it("sépare les joueurs et les actions", function()
		local limiter =
			RateLimiter.new({ A = { capacity = 1, refillPerSecond = 0 }, B = { capacity = 1, refillPerSecond = 0 } })
		expect(limiter:allow(1, "A", 0)).toBe(true)
		expect(limiter:allow(1, "A", 0)).toBe(false)
		expect(limiter:allow(1, "B", 0)).toBe(true)
		expect(limiter:allow(2, "A", 0)).toBe(true)
	end)

	it("refuse une action inconnue", function()
		expect(RateLimiter.new({}):allow(1, "Hack", 0)).toBe(false)
	end)

	it("résiste à 1000 requêtes en une seconde", function()
		local limiter = RateLimiter.new({ Pulse = { capacity = 6, refillPerSecond = 5 } })
		local accepted = 0
		for i = 1, 1000 do
			if limiter:allow(1, "Pulse", i / 1000) then
				accepted += 1
			end
		end
		expect(accepted).toBeAtMost(11)
	end)

	it("oublie un joueur", function()
		local limiter = RateLimiter.new({ A = { capacity = 1, refillPerSecond = 0 } })
		limiter:allow(1, "A", 0)
		limiter:forget(1)
		expect(limiter:allow(1, "A", 0)).toBe(true)
	end)
end)

describe("Validation", function()
	it("valide les identifiants", function()
		expect(Validation.isId("V01")).toBe(true)
		expect(Validation.isId("A_12-b")).toBe(true)
		expect(Validation.isId("")).toBe(false)
		expect(Validation.isId(12)).toBe(false)
		expect(Validation.isId(nil)).toBe(false)
		expect(Validation.isId("V01; drop")).toBe(false)
		expect(Validation.isId(string.rep("a", 40), 16)).toBe(false)
	end)

	it("valide les nombres finis", function()
		expect(Validation.isFiniteNumber(1.5)).toBe(true)
		expect(Validation.isFiniteNumber(0 / 0)).toBe(false)
		expect(Validation.isFiniteNumber(math.huge)).toBe(false)
		expect(Validation.isFiniteNumber("1")).toBe(false)
	end)

	it("valide les positions", function()
		expect(Validation.isPosition({ X = 1, Y = 2, Z = 3 })).toBe(true)
		expect(Validation.isPosition({ X = 1, Y = 0 / 0, Z = 3 })).toBe(false)
		expect(Validation.isPosition("here")).toBe(false)
		expect(Validation.isPosition(nil)).toBe(false)
	end)

	it("contrôle la portée horizontale et verticale", function()
		local origin = { X = 0, Y = 3, Z = 0 }
		expect(Validation.withinReach(origin, { X = 10, Y = 0, Z = 0 }, 14, 20)).toBe(true)
		expect(Validation.withinReach(origin, { X = 15, Y = 0, Z = 0 }, 14, 20)).toBe(false)
		expect(Validation.withinReach({ X = 0, Y = 80, Z = 0 }, { X = 1, Y = 0, Z = 0 }, 14, 20)).toBe(false)
		expect(Validation.withinReach(nil, { X = 1, Y = 0, Z = 0 }, 14, 20)).toBe(false)
	end)
end)

describe("TutorialFlow", function()
	it("suit Scan → Inspect → Capture → Done", function()
		local step = TutorialFlow.initial(false)
		expect(step).toBe("Scan")
		step = TutorialFlow.advance(step, "Scanned")
		expect(step).toBe("Inspect")
		step = TutorialFlow.advance(step, "Revealed")
		expect(step).toBe("Capture")
		step = TutorialFlow.advance(step, "Captured")
		expect(step).toBe("Done")
	end)

	it("permet de sauter le scan", function()
		expect(TutorialFlow.advance("Scan", "Revealed")).toBe("Capture")
	end)

	it("revient à Inspect après une fuite", function()
		expect(TutorialFlow.advance("Capture", "Escaped")).toBe("Inspect")
	end)

	it("reste terminé", function()
		expect(TutorialFlow.initial(true)).toBe("Done")
		expect(TutorialFlow.advance("Done", "Escaped")).toBe("Done")
	end)
end)
