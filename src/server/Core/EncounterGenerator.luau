--!strict
--[[
	EncounterGenerator — choisit où et quelle espèce faire apparaître.

	Règles :
	1. Seuls les emplacements libres (ni occupés, ni bloqués) sont candidats.
	2. Si une zone a moins de `minPerZone` Mimics, on la sert en priorité :
	   la découverte reste possible partout, même dans un serveur peu peuplé.
	3. L'espèce est tirée selon le poids de sa rareté, parmi les espèces
	   dont le type d'objet a au moins un emplacement candidat.
	4. L'emplacement est tiré uniformément parmi les candidats de ce type.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeightedPicker = require(Shared.Logic.WeightedPicker)

export type Slot = {
	id: string,
	kind: string,
	zone: string,
	position: any,
}

export type SpawnInput = {
	slots: { Slot },
	occupied: { [string]: any },
	blocked: { [string]: any }?,
	zoneCounts: { [string]: number },
	zones: { string },
	minPerZone: number,
	species: { any },
	weightOf: (rarity: string) -> number,
}

local EncounterGenerator = {}

local function freeSlots(slots: { Slot }, occupied: { [string]: any }, blocked: { [string]: any }?): { Slot }
	local out = {}
	for _, slot in slots do
		if occupied[slot.id] == nil and (blocked == nil or blocked[slot.id] == nil) then
			table.insert(out, slot)
		end
	end
	return out
end

function EncounterGenerator.chooseSpawn(input: SpawnInput, rng: any): (Slot?, any?)
	local pool = freeSlots(input.slots, input.occupied, input.blocked)
	if #pool == 0 then
		return nil, nil
	end

	local needy: { [string]: boolean } = {}
	local hasNeedy = false
	for _, zone in input.zones do
		if (input.zoneCounts[zone] or 0) < input.minPerZone then
			needy[zone] = true
			hasNeedy = true
		end
	end
	if hasNeedy then
		local restricted = {}
		for _, slot in pool do
			if needy[slot.zone] then
				table.insert(restricted, slot)
			end
		end
		if #restricted > 0 then
			pool = restricted
		end
	end

	local byKind: { [string]: { Slot } } = {}
	for _, slot in pool do
		local bucket = byKind[slot.kind]
		if bucket == nil then
			bucket = {}
			byKind[slot.kind] = bucket
		end
		table.insert(bucket, slot)
	end

	local candidates = {}
	for _, species in input.species do
		if byKind[species.kind] then
			table.insert(candidates, { item = species, weight = input.weightOf(species.rarity) })
		end
	end
	local species = WeightedPicker.pick(candidates, rng)
	if species == nil then
		return nil, nil
	end
	local slot = rng:pick(byKind[species.kind])
	return slot, species
end

-- Emplacement de repli après une fuite : même type, libre, différent, même zone si possible.
function EncounterGenerator.chooseFleeSlot(
	slots: { Slot },
	occupied: { [string]: any },
	blocked: { [string]: any }?,
	from: Slot,
	rng: any
): Slot?
	local sameZone, otherZone = {}, {}
	for _, slot in freeSlots(slots, occupied, blocked) do
		if slot.kind == from.kind and slot.id ~= from.id then
			if slot.zone == from.zone then
				table.insert(sameZone, slot)
			else
				table.insert(otherZone, slot)
			end
		end
	end
	if #sameZone > 0 then
		return rng:pick(sameZone)
	end
	return rng:pick(otherZone)
end

return EncounterGenerator
