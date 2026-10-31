--!strict
--[[
	MuseumStyles — personnalisation simple du musée (V0.3).

	Quatre réglages, chacun avec trois options GRATUITES et immédiatement disponibles :
	couleur des murs, ambiance lumineuse, style des socles, thème général. Une option de socle
	supplémentaire (« Étoilé ») est une récompense d'objectif (`reward`), débloquée une fois
	pour toutes. Plus tard : d'autres récompenses, ou des cosmétiques à résultat connu.

	Le serveur refuse toute option inconnue ou verrouillée ; une valeur inconnue lue dans un
	profil retombe sur l'option par défaut au rendu (aucune donnée n'est perdue).
	Couleurs en RGB 0-255 (utilisables dans Lune).
]]

export type Option = {
	id: string,
	name: string,
	color: { number },
	-- Seconde couleur (accents, néons).
	accent: { number }?,
	brightness: number?,
	material: string?,
	reward: boolean?,
}

local Styles: { [string]: { Option } } = {
	wall = {
		{ id = "lilac", name = "Lilas", color = { 150, 120, 200 }, accent = { 255, 150, 210 } },
		{ id = "mint", name = "Menthe", color = { 110, 190, 170 }, accent = { 200, 255, 230 } },
		{ id = "night", name = "Nuit", color = { 52, 44, 92 }, accent = { 120, 220, 255 } },
	},
	lighting = {
		{ id = "dusk", name = "Crépuscule", color = { 255, 170, 200 }, brightness = 1.4 },
		{ id = "aurora", name = "Aurore", color = { 140, 230, 255 }, brightness = 1.5 },
		{ id = "lantern", name = "Lanterne", color = { 255, 200, 120 }, brightness = 1.6 },
	},
	pedestal = {
		{
			id = "classic",
			name = "Classique",
			color = { 214, 206, 230 },
			accent = { 255, 150, 210 },
			material = "Marble",
		},
		{ id = "crystal", name = "Cristal", color = { 170, 230, 255 }, accent = { 120, 255, 230 }, material = "Glass" },
		{ id = "wood", name = "Bois", color = { 160, 110, 70 }, accent = { 255, 210, 120 }, material = "WoodPlanks" },
		{
			id = "pedestal_star",
			name = "Étoilé",
			color = { 60, 50, 110 },
			accent = { 255, 220, 100 },
			material = "Slate",
			reward = true,
		},
	},
	theme = {
		{ id = "mystic", name = "Mystique", color = { 60, 48, 84 }, accent = { 255, 120, 186 }, material = "Slate" },
		{
			id = "lab",
			name = "Laboratoire",
			color = { 220, 235, 240 },
			accent = { 110, 220, 255 },
			material = "SmoothPlastic",
		},
		{
			id = "fair",
			name = "Fête foraine",
			color = { 170, 110, 80 },
			accent = { 255, 220, 100 },
			material = "WoodPlanks",
		},
	},
}

local MuseumStyles = {}

MuseumStyles.Kinds = table.freeze({ "wall", "lighting", "pedestal", "theme" })
MuseumStyles.Defaults = table.freeze({ wall = "lilac", lighting = "dusk", pedestal = "classic", theme = "mystic" })

function MuseumStyles.options(kind: string): { Option }
	return Styles[kind] or {}
end

function MuseumStyles.get(kind: string, id: string?): Option?
	for _, option in Styles[kind] or {} do
		if option.id == id then
			return option
		end
	end
	return nil
end

-- Option à utiliser pour le rendu : l'option demandée si elle existe, sinon celle par défaut.
function MuseumStyles.resolve(kind: string, id: string?): Option
	return MuseumStyles.get(kind, id) or (MuseumStyles.get(kind, MuseumStyles.Defaults[kind]) :: Option)
end

--[[
	Une option peut-elle être choisie ? Gratuite, ou récompense déjà débloquée
	(`unlocked` : ensemble des récompenses du profil).
]]
function MuseumStyles.isAvailable(kind: string, id: any, unlocked: { [string]: boolean }?): boolean
	if type(id) ~= "string" then
		return false
	end
	local option = MuseumStyles.get(kind, id)
	if option == nil then
		return false
	end
	return option.reward ~= true or (unlocked ~= nil and unlocked[id] == true)
end

return MuseumStyles
