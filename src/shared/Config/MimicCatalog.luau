--!strict
--[[
	MimicCatalog — les six espèces de départ.

	L'identifiant (`id`) est stable : il sera la clé de sauvegarde en V0.2.
	Ne jamais renommer un id existant ; ajouter une nouvelle entrée à la place.

	Chaque espèce se cache dans un seul type d'objet (`kind`). Le comportement
	décrit les indices qu'elle émet, la difficulté du minijeu et le style de
	ses animations (interprété par le client).
]]

export type CaptureDifficulty = {
	speed: number, -- vitesse du curseur (largeurs de jauge par seconde)
	zoneWidth: number, -- largeur de la zone cible (fraction de la jauge)
	speedUp: number, -- accélération par étape réussie
	shrink: number, -- rétrécissement de la zone par étape réussie
}

export type Behavior = {
	temperament: string,
	clues: { string },
	clueIntervalMin: number,
	clueIntervalMax: number,
	capture: CaptureDifficulty,
	revealStyle: string,
	fleeStyle: string,
}

export type Appearance = {
	bodyColor: { number },
	accentColor: { number },
	eyes: string,
	mouth: string,
}

export type Species = {
	id: string,
	name: string,
	kind: string,
	rarity: string,
	description: string,
	behavior: Behavior,
	appearance: Appearance,
}

-- Types d'objets camouflés et leur nom affiché.
local Kinds = table.freeze({
	Chair = "chaise",
	TrashCan = "poubelle",
	Mailbox = "boîte aux lettres",
	Lamp = "lampe",
	Chest = "coffre",
	Vending = "distributeur",
})

local list: { Species } = {
	{
		id = "chairy",
		name = "Chairy",
		kind = "Chair",
		rarity = "Common",
		description = "Une chaise timide qui frissonne dès qu'on la regarde. Elle adore qu'on s'assoie… presque.",
		behavior = {
			temperament = "Timide",
			clues = { "Wiggle", "Eyes" },
			clueIntervalMin = 6,
			clueIntervalMax = 10,
			capture = { speed = 0.75, zoneWidth = 0.26, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "Hop",
			fleeStyle = "Hop",
		},
		appearance = { bodyColor = { 214, 138, 74 }, accentColor = { 255, 150, 170 }, eyes = "Round", mouth = "Smile" },
	},
	{
		id = "trashling",
		name = "Trashling",
		kind = "TrashCan",
		rarity = "Common",
		description = "Une poubelle goulue. Son couvercle claque quand elle a faim, c'est-à-dire tout le temps.",
		behavior = {
			temperament = "Gourmand",
			clues = { "Rattle", "Sound" },
			clueIntervalMin = 6,
			clueIntervalMax = 11,
			capture = { speed = 0.85, zoneWidth = 0.24, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "LidPop",
			fleeStyle = "Hop",
		},
		appearance = { bodyColor = { 96, 178, 110 }, accentColor = { 255, 230, 120 }, eyes = "Odd", mouth = "Teeth" },
	},
	{
		id = "posty",
		name = "Posty",
		kind = "Mailbox",
		rarity = "Uncommon",
		description = "Une boîte aux lettres bavarde. Elle lève son drapeau pour attirer l'attention.",
		behavior = {
			temperament = "Bavard",
			clues = { "Flag", "Eyes" },
			clueIntervalMin = 7,
			clueIntervalMax = 12,
			capture = { speed = 0.95, zoneWidth = 0.22, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "Flag",
			fleeStyle = "Dash",
		},
		appearance = { bodyColor = { 70, 120, 230 }, accentColor = { 255, 255, 255 }, eyes = "Round", mouth = "Letter" },
	},
	{
		id = "lumino",
		name = "Lumino",
		kind = "Lamp",
		rarity = "Uncommon",
		description = "Un lampadaire curieux à l'œil unique. Il clignote quand on le fixe trop longtemps.",
		behavior = {
			temperament = "Curieux",
			clues = { "Flicker", "Eyes" },
			clueIntervalMin = 7,
			clueIntervalMax = 12,
			capture = { speed = 1.0, zoneWidth = 0.2, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "Flash",
			fleeStyle = "Hop",
		},
		appearance = { bodyColor = { 70, 64, 96 }, accentColor = { 255, 236, 140 }, eyes = "Cyclops", mouth = "Small" },
	},
	{
		id = "chompy",
		name = "Chompy",
		kind = "Chest",
		rarity = "Rare",
		description = "Un coffre qui claque des dents. Il garde jalousement un trésor… qu'il a sûrement mangé.",
		behavior = {
			temperament = "Grincheux",
			clues = { "Rattle", "Sound", "Vibrate" },
			clueIntervalMin = 8,
			clueIntervalMax = 14,
			capture = { speed = 1.15, zoneWidth = 0.18, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "Chomp",
			fleeStyle = "Dash",
		},
		appearance = { bodyColor = { 150, 96, 56 }, accentColor = { 255, 120, 150 }, eyes = "Angry", mouth = "Chomp" },
	},
	{
		id = "vendoo",
		name = "Vendoo",
		kind = "Vending",
		rarity = "Epic",
		description = "Un distributeur mystérieux. Personne ne sait ce qu'il vend, ni à qui.",
		behavior = {
			temperament = "Mystérieux",
			clues = { "Glitch", "Sound" },
			clueIntervalMin = 9,
			clueIntervalMax = 15,
			capture = { speed = 1.3, zoneWidth = 0.16, speedUp = 0.25, shrink = 0.2 },
			revealStyle = "Glitch",
			fleeStyle = "Teleport",
		},
		appearance = { bodyColor = { 120, 70, 190 }, accentColor = { 120, 255, 230 }, eyes = "Screen", mouth = "Wave" },
	},
}

local byId: { [string]: Species } = {}
local byKind: { [string]: Species } = {}
for _, species in list do
	byId[species.id] = species
	byKind[species.kind] = species
end

local MimicCatalog = {}

MimicCatalog.Kinds = Kinds

function MimicCatalog.get(id: string): Species?
	return byId[id]
end

function MimicCatalog.getByKind(kind: string): Species?
	return byKind[kind]
end

function MimicCatalog.list(): { Species }
	return list
end

function MimicCatalog.count(): number
	return #list
end

function MimicCatalog.kindName(kind: string): string
	return (Kinds :: any)[kind] or "objet"
end

-- Types d'objets masculins (pour l'article : « un coffre », « une chaise »).
local Masculine = table.freeze({ Chest = true, Vending = true })

-- Nom avec son article indéfini : « un coffre », « une boîte aux lettres », « un objet ».
function MimicCatalog.kindWithArticle(kind: string): string
	local known = (Kinds :: any)[kind] ~= nil
	local article = if not known or (Masculine :: any)[kind] then "un" else "une"
	return article .. " " .. MimicCatalog.kindName(kind)
end

return MimicCatalog
