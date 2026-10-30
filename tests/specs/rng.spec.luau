local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Rng = Loader.shared("Logic/Rng")

describe("Rng", function()
	it("est déterministe pour une même graine", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 50 do
			expect(a:nextNumber()).toBe(b:nextNumber())
		end
	end)

	it("produit des graines différentes pour des suites différentes", function()
		local a, b = Rng.new(1), Rng.new(2)
		local same = 0
		for _ = 1, 20 do
			if a:nextNumber() == b:nextNumber() then
				same += 1
			end
		end
		expect(same).toBeLessThan(2)
	end)

	it("reste dans [0, 1)", function()
		local rng = Rng.new(7)
		for _ = 1, 5000 do
			local n = rng:nextNumber()
			expect(n >= 0 and n < 1).toBe(true)
		end
	end)

	it("nextInteger inclut ses deux bornes", function()
		local rng = Rng.new(99)
		local seen = {}
		for _ = 1, 2000 do
			local n = rng:nextInteger(1, 4)
			expect(n >= 1 and n <= 4).toBe(true)
			seen[n] = true
		end
		expect(seen[1] and seen[2] and seen[3] and seen[4]).toBe(true)
	end)

	it("accepte une graine nulle ou négative", function()
		local rng = Rng.new(0)
		expect(rng:nextNumber() >= 0).toBe(true)
		local neg = Rng.new(-123.7)
		expect(neg:nextNumber() >= 0).toBe(true)
	end)

	it("pick renvoie nil sur une liste vide", function()
		expect(Rng.new(3):pick({})).toBeNil()
		expect(Rng.new(3):pick({ "a" })).toBe("a")
	end)
end)
