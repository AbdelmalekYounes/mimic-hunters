--!strict
--[[
	Rarities — raretés provisoires de la V0.1.

	`spawnWeight` pondère le choix de l'espèce lors de la génération d'une
	rencontre. Les couleurs sont en RGB 0-255 pour rester utilisables hors
	Roblox (tests Lune) ; le client les convertit avec Color3.fromRGB.
]]

export type Rarity = {
	id: string,
	displayName: string,
	order: number,
	spawnWeight: number,
	color: { number },
}

local list: { Rarity } = {
	{ id = "Common", displayName = "Commun", order = 1, spawnWeight = 50, color = { 146, 214, 120 } },
	{ id = "Uncommon", displayName = "Peu commun", order = 2, spawnWeight = 28, color = { 92, 178, 255 } },
	{ id = "Rare", displayName = "Rare", order = 3, spawnWeight = 15, color = { 196, 120, 255 } },
	{ id = "Epic", displayName = "Épique", order = 4, spawnWeight = 7, color = { 255, 176, 64 } },
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

local Rarities = {}

function Rarities.get(id: string): Rarity?
	return byId[id]
end

function Rarities.list(): { Rarity }
	return list
end

function Rarities.weightOf(id: string): number
	local rarity = byId[id]
	return if rarity then rarity.spawnWeight else 0
end

return Rarities
