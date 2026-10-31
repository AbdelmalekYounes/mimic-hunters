local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local SpecimenLook = Loader.shared("Logic/SpecimenLook")
local MimicCatalog = Loader.shared("Config/MimicCatalog")

local chairy = MimicCatalog.get("chairy")

local function distance(a, b)
	return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
end

describe("SpecimenLook", function()
	it("convertit RGB ↔ HSV sans dérive", function()
		for _, rgb in { { 214, 138, 74 }, { 0, 0, 0 }, { 255, 255, 255 }, { 12, 200, 99 }, { 255, 0, 128 } } do
			local back = SpecimenLook.hsvToRgb(SpecimenLook.rgbToHsv(rgb))
			expect(distance(rgb, back)).toBeAtMost(3)
		end
	end)

	it("donne la même apparence pour la même graine (reproductible)", function()
		local a = SpecimenLook.compute(chairy, 123456, "Standard")
		local b = SpecimenLook.compute(chairy, 123456, "Standard")
		expect(a).toEqual(b)
	end)

	it("varie d'un exemplaire à l'autre, sans s'éloigner de l'espèce", function()
		local distinct = {}
		for seed = 1, 40 do
			local look = SpecimenLook.compute(chairy, seed * 7919, "Standard")
			distinct[table.concat(look.body, ",")] = true
			expect(look.scale).toBeAtLeast(SpecimenLook.Variation.scaleMin)
			expect(look.scale).toBeAtMost(SpecimenLook.Variation.scaleMax)
			-- Reste reconnaissable : couleur proche de celle de l'espèce.
			expect(distance(look.body, chairy.appearance.bodyColor)).toBeLessThan(120)
			expect(look.transparency).toBe(0)
		end
		local count = 0
		for _ in distinct do
			count += 1
		end
		expect(count).toBeAtLeast(30)
	end)

	it("garde des couleurs RGB valides pour toutes les espèces", function()
		for _, species in MimicCatalog.list() do
			for seed = 1, 20 do
				local look = SpecimenLook.compute(species, seed, "Standard")
				for _, rgb in { look.body, look.accent } do
					for _, c in rgb do
						expect(c >= 0 and c <= 255 and c == math.floor(c)).toBe(true)
					end
				end
			end
		end
	end)
end)
