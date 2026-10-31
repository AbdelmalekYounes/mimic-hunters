--!strict
--[[
	MemoryBackend — stockage simulé, même interface que DataStoreBackend.

	Sert aux tests automatisés (Lune et Studio) et de repli dans Studio quand les DataStores
	sont inaccessibles (place non publiée). Les données ne survivent pas à l'arrêt du serveur.

	Outils de test : pannes injectées (`failNext`), budget de requêtes réglable (`setBudget`),
	lecture et écriture directes (`peek`, `poke`), compteur d'écritures.
]]

local ProfileSchema = require(script.Parent.ProfileSchema)

local MemoryBackend = {}
MemoryBackend.__index = MemoryBackend

function MemoryBackend.new()
	local self = setmetatable({}, MemoryBackend)
	self._data = {} :: { [string]: any }
	self._failures = 0
	self._failMessage = "panne simulée"
	self._budget = math.huge
	self.writes = 0
	self.calls = 0
	return self
end

-- Les `count` prochains appels échouent (comme une erreur réseau de DataStore).
function MemoryBackend.failNext(self: any, count: number, message: string?)
	self._failures = count
	self._failMessage = message or "panne simulée"
end

function MemoryBackend.setBudget(self: any, budget: number)
	self._budget = budget
end

function MemoryBackend.budget(self: any): number
	return self._budget
end

function MemoryBackend.update(self: any, key: string, transform: (any) -> any): (boolean, any)
	self.calls += 1
	if self._failures > 0 then
		self._failures -= 1
		return false, self._failMessage
	end
	-- Copies : aucune référence partagée entre le stockage et le jeu.
	local current = ProfileSchema.deepCopy(self._data[key])
	local ok, result = pcall(transform, current)
	if not ok then
		return false, tostring(result)
	end
	if result ~= nil then
		self._data[key] = ProfileSchema.deepCopy(result)
		self.writes += 1
	end
	return true, ProfileSchema.deepCopy(if result ~= nil then result else self._data[key])
end

function MemoryBackend.peek(self: any, key: string): any
	return ProfileSchema.deepCopy(self._data[key])
end

function MemoryBackend.poke(self: any, key: string, value: any)
	self._data[key] = ProfileSchema.deepCopy(value)
end

return MemoryBackend
