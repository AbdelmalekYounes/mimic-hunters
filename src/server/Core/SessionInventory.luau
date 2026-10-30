--!strict
--[[
	SessionInventory — collection d'un joueur pendant la session (V0.1).

	`add` est idempotent par `sourceId` (identifiant de tentative) : rejouer la
	même capture ne duplique jamais l'entrée. `snapshot` / `fromSnapshot`
	définissent le format qui sera persisté par DataStore en V0.2.
]]

export type SpeciesEntry = {
	count: number,
	discoveryOrder: number,
}

export type Snapshot = {
	version: number,
	totalCaptures: number,
	species: { [string]: SpeciesEntry },
}

export type AddInfo = {
	speciesId: string,
	isNew: boolean,
	count: number,
	totalCaptures: number,
	discovered: number,
}

export type Inventory = {
	userId: number,
	_species: { [string]: SpeciesEntry },
	_sources: { [string]: boolean },
	_total: number,
	_discovered: number,
	add: (self: Inventory, speciesId: string, sourceId: string) -> (boolean, AddInfo | string),
	count: (self: Inventory, speciesId: string) -> number,
	totalCaptures: (self: Inventory) -> number,
	discoveredCount: (self: Inventory) -> number,
	hasSource: (self: Inventory, sourceId: string) -> boolean,
	snapshot: (self: Inventory) -> Snapshot,
}

local SNAPSHOT_VERSION = 1

local SessionInventory = {}
SessionInventory.__index = SessionInventory
SessionInventory.SnapshotVersion = SNAPSHOT_VERSION

function SessionInventory.new(userId: number): Inventory
	return (
		setmetatable({
			userId = userId,
			_species = {},
			_sources = {},
			_total = 0,
			_discovered = 0,
		}, SessionInventory) :: any
	) :: Inventory
end

function SessionInventory.add(self: Inventory, speciesId: string, sourceId: string): (boolean, AddInfo | string)
	if type(speciesId) ~= "string" or speciesId == "" then
		return false, "BadSpecies"
	end
	if type(sourceId) ~= "string" or sourceId == "" then
		return false, "BadSource"
	end
	if self._sources[sourceId] then
		return false, "Duplicate"
	end
	self._sources[sourceId] = true

	local entry = self._species[speciesId]
	local isNew = entry == nil
	if entry == nil then
		self._discovered += 1
		entry = { count = 0, discoveryOrder = self._discovered }
		self._species[speciesId] = entry
	end
	assert(entry, "entry")
	entry.count += 1
	self._total += 1

	return true,
		{
			speciesId = speciesId,
			isNew = isNew,
			count = entry.count,
			totalCaptures = self._total,
			discovered = self._discovered,
		}
end

function SessionInventory.count(self: Inventory, speciesId: string): number
	local entry = self._species[speciesId]
	return if entry then entry.count else 0
end

function SessionInventory.totalCaptures(self: Inventory): number
	return self._total
end

function SessionInventory.discoveredCount(self: Inventory): number
	return self._discovered
end

function SessionInventory.hasSource(self: Inventory, sourceId: string): boolean
	return self._sources[sourceId] == true
end

function SessionInventory.snapshot(self: Inventory): Snapshot
	local species = {}
	for id, entry in self._species do
		species[id] = { count = entry.count, discoveryOrder = entry.discoveryOrder }
	end
	return {
		version = SNAPSHOT_VERSION,
		totalCaptures = self._total,
		species = species,
	}
end

-- Reconstruit un inventaire depuis une sauvegarde ; ignore les entrées invalides.
function SessionInventory.fromSnapshot(userId: number, data: any): Inventory
	local inventory = SessionInventory.new(userId)
	if type(data) ~= "table" or data.version ~= SNAPSHOT_VERSION or type(data.species) ~= "table" then
		return inventory
	end
	local total = 0
	local discovered = 0
	for id, entry in data.species do
		if type(id) == "string" and type(entry) == "table" and type(entry.count) == "number" and entry.count > 0 then
			local count = math.floor(entry.count)
			discovered += 1
			inventory._species[id] = {
				count = count,
				discoveryOrder = if type(entry.discoveryOrder) == "number" then entry.discoveryOrder else discovered,
			}
			total += count
		end
	end
	inventory._total = total
	inventory._discovered = discovered
	return inventory
end

return SessionInventory
