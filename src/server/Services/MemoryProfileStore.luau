--!strict
--[[
	MemoryProfileStore — stockage des profils pour la V0.1 (mémoire du serveur).

	Interface commune à respecter par le futur DataStoreProfileStore (V0.2) :
		store:load(userId: number): Profile?   -- peut céder la main (yield)
		store:save(userId: number, profile: Profile): boolean

	Ici les profils survivent à une reconnexion sur le même serveur, mais pas
	à la fermeture du serveur. Les profils sont copiés pour qu'aucune
	référence partagée ne fuite entre le monde de jeu et le stockage.
]]

local MemoryProfileStore = {}
MemoryProfileStore.__index = MemoryProfileStore

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

function MemoryProfileStore.new()
	return setmetatable({ _profiles = {} :: { [number]: any } }, MemoryProfileStore)
end

function MemoryProfileStore.load(self: any, userId: number): any
	return deepCopy(self._profiles[userId])
end

function MemoryProfileStore.save(self: any, userId: number, profile: any): boolean
	self._profiles[userId] = deepCopy(profile)
	return true
end

return MemoryProfileStore
