local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local HudLayout = Loader.shared("Logic/HudLayout")

-- Tailles de la ScreenGui (barre Roblox du haut déjà déduite, ~58 px).
-- Les tailles mobiles viennent des appareils simulés par Studio ; elles ne remplacent pas un vrai téléphone.
local SCREENS = {
	{ name = "iPhone SE paysage", w = 667, h = 317, touch = true, mode = "touchCompact" },
	{ name = "iPhone 13 paysage (mesuré en Studio)", w = 749, h = 331, touch = true, mode = "touchCompact" },
	{ name = "iPhone 13 paysage sans encoche", w = 844, h = 332, touch = true, mode = "touchCompact" },
	{ name = "Android 640×360 paysage", w = 640, h = 302, touch = true, mode = "touchCompact" },
	{ name = "iPhone 13 portrait", w = 390, h = 786, touch = true, mode = "touchCompact" },
	{ name = "tablette 1024×768", w = 1024, h = 710, touch = true, mode = "touch" },
	{ name = "PC 1920×1080", w = 1920, h = 1022, touch = false, mode = "pc" },
	{ name = "PC fenêtre Studio (mesurée)", w = 1187, h = 517, touch = false, mode = "pc" },
	{ name = "PC petite fenêtre (VM)", w = 556, h = 375, touch = false, mode = "pc" },
}

-- Éléments toujours affichés (ou presque) qui ne doivent jamais se chevaucher.
local PERSISTENT = { "counter", "banner", "action", "scan", "codex", "signal" }
-- Pendant le minijeu, ces éléments restent visibles à côté du panneau de capture.
-- (Le signal est masqué au début d'une capture.)
local BESIDE_CAPTURE = { "counter", "banner", "action", "scan", "codex" }

local function describeRect(r)
	return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h)
end

describe("HudLayout", function()
	for _, screen in SCREENS do
		local layout = HudLayout.compute(screen.w, screen.h, screen.touch)

		it(screen.name .. " : disposition " .. screen.mode, function()
			expect(layout.mode).toBe(screen.mode)
		end)

		it(screen.name .. " : tout tient dans l'écran", function()
			for _, key in { "counter", "banner", "action", "scan", "codex", "signal", "capture", "panel" } do
				local r = layout[key]
				if not HudLayout.inside(r, screen.w, screen.h) then
					error(key .. " sort de l'écran " .. describeRect(r), 0)
				end
			end
		end)

		it(screen.name .. " : aucun chevauchement entre éléments", function()
			for i, a in PERSISTENT do
				for j = i + 1, #PERSISTENT do
					local b = PERSISTENT[j]
					if HudLayout.overlaps(layout[a], layout[b]) then
						error(
							string.format(
								"%s %s chevauche %s %s",
								a,
								describeRect(layout[a]),
								b,
								describeRect(layout[b])
							),
							0
						)
					end
				end
			end
			for _, key in BESIDE_CAPTURE do
				if HudLayout.overlaps(layout.capture, layout[key]) then
					error(string.format("le minijeu chevauche %s %s", key, describeRect(layout[key])), 0)
				end
			end
		end)

		if screen.touch then
			it(screen.name .. " : bouton de saut de Roblox dégagé", function()
				local zone = if screen.mode == "touchCompact"
					then HudLayout.JumpZone.compact
					else HudLayout.JumpZone.large
				local jump = { x = screen.w - zone.w, y = screen.h - zone.h, w = zone.w, h = zone.h }
				for _, key in { "action", "scan", "codex", "signal" } do
					if HudLayout.overlaps(layout[key], jump) then
						error(key .. " recouvre le bouton de saut " .. describeRect(layout[key]), 0)
					end
				end
			end)
		end
	end

	it("garde la disposition PC d'origine sur grand écran", function()
		local layout = HudLayout.compute(1187, 517, false)
		expect(layout.action.x).toBe(1187 - 20 - 190)
		expect(layout.action.y).toBe(517 - 24 - 62)
		expect(layout.scan.y).toBe(517 - 102 - 86)
		expect(layout.counter.x).toBe(12)
	end)

	it("détecte chevauchements et débordements", function()
		local a = { x = 0, y = 0, w = 10, h = 10 }
		expect(HudLayout.overlaps(a, { x = 9, y = 9, w = 5, h = 5 })).toBe(true)
		expect(HudLayout.overlaps(a, { x = 10, y = 0, w = 5, h = 5 })).toBe(false)
		expect(HudLayout.inside(a, 10, 10)).toBe(true)
		expect(HudLayout.inside({ x = -1, y = 0, w = 5, h = 5 }, 10, 10)).toBe(false)
	end)
end)
