--!strict
--[[
	HudLayout — positions du HUD en pixels, calculées à partir de la taille de l'écran (pur, testé).

	Trois dispositions :
	- "pc"           : clavier/souris, boutons en bas à droite ;
	- "touch"        : tablette, boutons au-dessus du grand bouton de saut de Roblox (120 px) ;
	- "touchCompact" : téléphone (petit côté ≤ 500 px), boutons au-dessus du petit bouton de
	                   saut (70 px) : la disposition tablette sortait de l'écran en paysage.

	La taille reçue est celle de la ScreenGui (barre Roblox du haut déjà déduite).
	Tous les rectangles sont { x, y, w, h } avec l'origine en haut à gauche.
]]

export type Rect = { x: number, y: number, w: number, h: number }

export type Layout = {
	mode: string,
	counter: Rect,
	banner: Rect,
	toasts: Rect,
	action: Rect,
	scan: Rect,
	codex: Rect,
	signal: Rect,
	capture: Rect,
}

local HudLayout = {}

local MARGIN = 12
local GAP = 8
-- En dessous, Roblox affiche le petit bouton de saut (70 px, à ~25 px des bords bas et droit).
HudLayout.CompactMaxSide = 500
-- Bouton de saut : zone à laisser libre en bas à droite (petit et grand modèle).
HudLayout.JumpZone = {
	compact = { w = 100, h = 96 },
	large = { w = 176, h = 216 },
}

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) }
end

function HudLayout.mode(width: number, height: number, touch: boolean): string
	if not touch then
		return "pc"
	end
	return if math.min(width, height) <= HudLayout.CompactMaxSide then "touchCompact" else "touch"
end

-- Haut de l'écran : compteur à gauche, bandeau du tutoriel à droite du compteur, ou dessous
-- quand la largeur manque. Les notifications passent sous le bandeau.
local function topArea(width: number, compact: boolean): (Rect, Rect, Rect)
	local counter = if compact then rect(MARGIN, 8, 200, 52) else rect(MARGIN, 10, 240, 62)
	local bannerH = if compact then 48 else 58
	local bannerW = math.clamp(width * 0.6, 280, 620)
	local bannerX = width / 2 - bannerW / 2
	local besideX = counter.x + counter.w + GAP
	local banner
	if bannerX >= besideX then
		banner = rect(bannerX, counter.y, bannerW, bannerH)
	elseif width - MARGIN - besideX >= 280 then
		banner = rect(besideX, counter.y, math.min(bannerW, width - MARGIN - besideX), bannerH)
	else
		banner = rect(MARGIN, counter.y + counter.h + GAP, math.min(width - 2 * MARGIN, 620), bannerH)
	end
	local toastW = math.clamp(width * 0.5, 260, 460)
	local toasts = rect(width / 2 - toastW / 2, banner.y + banner.h + GAP, toastW, 140)
	return counter, banner, toasts
end

function HudLayout.compute(width: number, height: number, touch: boolean): Layout
	local mode = HudLayout.mode(width, height, touch)
	local compact = mode == "touchCompact"
	local counter, banner, toasts = topArea(width, compact)

	local action: Rect, scan: Rect, codex: Rect, signal: Rect
	local captureW: number, captureH: number, captureBottom: number
	if compact then
		-- Colonne de droite au-dessus du petit bouton de saut ; le signal se place à gauche du
		-- CODEX, ou au-dessus du SCAN si l'écran est trop étroit (portrait).
		local right = 16
		local bottom = HudLayout.JumpZone.compact.h + 4
		action = rect(width - right - 150, height - bottom - 56, 150, 56)
		scan = rect(width - right - 72, action.y - GAP - 72, 72, 72)
		codex = rect(scan.x - GAP - 88, scan.y + scan.h - 40, 88, 40)
		local signalW, signalH = 200, 44
		if codex.x - GAP - signalW >= MARGIN then
			signal = rect(codex.x - GAP - signalW, scan.y + scan.h - signalH, signalW, signalH)
		else
			signal = rect(width - right - signalW, scan.y - GAP - signalH, signalW, signalH)
		end
		captureW = 560
		captureH = math.clamp(height - 2 * MARGIN - (banner.y + banner.h), 150, 200)
		captureBottom = MARGIN
	else
		local touchLarge = mode == "touch"
		-- Tablette : le grand bouton de saut monte à ~210 px du bas (l'ancien 190 le chevauchait).
		local bottom = if touchLarge then HudLayout.JumpZone.large.h + 6 else 24
		local actionW, actionH = if touchLarge then 176 else 190, if touchLarge then 66 else 62
		action = rect(width - 20 - actionW, height - bottom - actionH, actionW, actionH)
		scan = rect(width - 20 - 86, height - (bottom + 78) - 86, 86, 86)
		codex = rect(width - 116 - 96, height - (bottom + 78) - 46, 96, 46)
		signal = rect(width - 20 - 240, height - (bottom + 176) - 54, 240, 54)
		captureW = math.clamp(width * 0.62, 300, 560)
		captureH = if touchLarge then 210 else 176
		captureBottom = if touchLarge then 18 else 24
	end

	-- Minijeu : centré en bas, mais jamais sur la colonne de boutons (l'action reste affichée
	-- pendant la capture). Décalé vers la gauche, puis rétréci ; si la place manque encore
	-- (portrait), il passe au-dessus des boutons sur toute la largeur.
	local columnLeft = math.min(action.x, scan.x, codex.x)
	local x = width / 2 - captureW / 2
	local y = height - captureBottom - captureH
	if x + captureW > columnLeft - GAP then
		x = columnLeft - GAP - captureW
	end
	if x < MARGIN then
		x = MARGIN
		captureW = columnLeft - GAP - MARGIN
		if captureW < 260 then
			captureW = width - 2 * MARGIN
			y = math.max(math.min(signal.y, scan.y) - GAP - captureH, banner.y + banner.h + GAP)
		end
	end
	local capture = rect(x, y, captureW, captureH)

	return {
		mode = mode,
		counter = counter,
		banner = banner,
		toasts = toasts,
		action = action,
		scan = scan,
		codex = codex,
		signal = signal,
		capture = capture,
	}
end

function HudLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function HudLayout.inside(r: Rect, width: number, height: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= width and r.y + r.h <= height
end

return HudLayout
