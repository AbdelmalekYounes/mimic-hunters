--!strict
--[[
	SpecimenLook — apparence d'un exemplaire, calculée à partir de sa graine (pur, testé).

	Deux exemplaires de la même espèce ne sont jamais tout à fait identiques : teinte, saturation,
	luminosité et taille varient légèrement. Le calcul est déterministe (même graine = même
	apparence sur tous les clients, après reconnexion, et plus tard dans un musée ou un échange).

	Couleurs en RGB 0-255 (utilisables dans Lune) ; le client les convertit avec Color3.fromRGB.
	Les mutations (Chromatic, Spectral) remplacent la palette : voir Config/Mutations.
]]

local Rng = require(script.Parent.Rng)

export type Look = {
	mutation: string,
	body: { number },
	accent: { number },
	scale: number,
	-- Transparence des parties teintées (Spectral).
	transparency: number,
	-- Éclat lumineux léger (Chromatic) : couleur de la lumière, ou nil.
	glow: { number }?,
	-- Couleur des yeux lumineux (Spectral), ou nil pour les yeux normaux.
	eyeGlow: { number }?,
}

local SpecimenLook = {}

-- Amplitude des variations d'un exemplaire Standard.
SpecimenLook.Variation = table.freeze({
	hue = 0.035,
	saturation = 0.1,
	value = 0.08,
	scaleMin = 0.93,
	scaleMax = 1.07,
})

-- ─── Conversions de couleurs (pures) ───────────────────────────────────

function SpecimenLook.rgbToHsv(rgb: { number }): (number, number, number)
	local r, g, b = rgb[1] / 255, rgb[2] / 255, rgb[3] / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta > 0 then
		if max == r then
			h = ((g - b) / delta) % 6
		elseif max == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	local s = if max > 0 then delta / max else 0
	return h, s, max
end

function SpecimenLook.hsvToRgb(h: number, s: number, v: number): { number }
	h = h % 1
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	i %= 6
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
end

local function shift(rgb: { number }, rng: any, amount: { hue: number, saturation: number, value: number }): { number }
	local h, s, v = SpecimenLook.rgbToHsv(rgb)
	h += rng:nextRange(-amount.hue, amount.hue)
	s = math.clamp(s + rng:nextRange(-amount.saturation, amount.saturation), 0, 1)
	v = math.clamp(v + rng:nextRange(-amount.value, amount.value), 0.15, 1)
	return SpecimenLook.hsvToRgb(h, s, v)
end

--[[
	Apparence d'un exemplaire. `species` : entrée de MimicCatalog ; `seed` : graine serveur ;
	`mutation` : "Standard" par défaut.
]]
function SpecimenLook.compute(species: any, seed: number, mutation: string?): Look
	local rng = Rng.new(seed)
	local variation = SpecimenLook.Variation
	local look: Look = {
		mutation = mutation or "Standard",
		body = shift(species.appearance.bodyColor, rng, variation),
		accent = shift(species.appearance.accentColor, rng, variation),
		scale = rng:nextRange(variation.scaleMin, variation.scaleMax),
		transparency = 0,
		glow = nil,
		eyeGlow = nil,
	}
	return look
end

return SpecimenLook
