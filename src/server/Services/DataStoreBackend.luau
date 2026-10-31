--!strict
--[[
	DataStoreBackend — adaptateur Roblox DataStore pour ProfileService.

	- UpdateAsync uniquement : lecture et écriture atomiques, la transformation peut être
	  rejouée par Roblox si une autre écriture a eu lieu entre-temps.
	- Aucune erreur ne remonte : `update` retourne (false, message) et ProfileService réessaie.
	- `choose` sélectionne le stockage :
	    * jeu publié : GameConfig.Save.StoreName ;
	    * Studio : GameConfig.Save.StudioStoreName, un DataStore DISTINCT, pour que les essais
	      n'écrasent jamais les profils d'une expérience publique ;
	    * Studio sans accès aux DataStores (place locale, accès API désactivé) : stockage en
	      mémoire (MemoryBackend), avec un avertissement.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local MemoryBackend = require(Server.Core.MemoryBackend)

local DataStoreBackend = {}
DataStoreBackend.__index = DataStoreBackend

function DataStoreBackend.new(storeName: string)
	local self = setmetatable({}, DataStoreBackend)
	self.name = storeName
	self._store = DataStoreService:GetDataStore(storeName)
	return self
end

function DataStoreBackend.update(self: any, key: string, transform: (any) -> any): (boolean, any)
	return pcall(function()
		return self._store:UpdateAsync(key, function(current)
			return transform(current)
		end)
	end)
end

function DataStoreBackend.budget(_self: any): number
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return if ok and type(budget) == "number" then budget else 1
end

--[[
	Retourne (backend, description). En Studio, vérifie d'abord que le DataStore répond ;
	sinon bascule sur la mémoire. En jeu publié, une erreur au démarrage est passagère :
	on garde le DataStore (les réessais de ProfileService s'en chargent).
]]
-- Stockage qui échoue toujours (même interface) : profils « Unavailable », rien n'est écrit.
function DataStoreBackend.unavailable(reason: string): any
	return {
		update = function(_self: any, _key: string, _transform: (any) -> any): (boolean, any)
			return false, "DataStore indisponible : " .. reason
		end,
		budget = function(_self: any): number
			return 1
		end,
	}
end

function DataStoreBackend.choose(saveConfig: any): (any, string)
	local studio = RunService:IsStudio()
	local name = if studio then saveConfig.StudioStoreName else saveConfig.StoreName
	local ok, backendOrError = pcall(DataStoreBackend.new, name)
	if ok and studio then
		local probeOk, probeError = pcall(function()
			return backendOrError._store:GetAsync("__probe")
		end)
		if not probeOk then
			warn(
				"[Profils] DataStores indisponibles dans Studio ("
					.. tostring(probeError)
					.. ") : profils en mémoire, perdus à l'arrêt du serveur."
			)
			return MemoryBackend.new(), "mémoire (Studio)"
		end
	end
	if not ok then
		if studio then
			warn("[Profils] DataStore inaccessible dans Studio : profils en mémoire.")
			return MemoryBackend.new(), "mémoire (Studio)"
		end
		-- Jeu publié : surtout PAS de repli mémoire (les captures seraient perdues sans que le
		-- joueur le sache). Un stockage qui refuse tout : chaque profil passe « Unavailable »,
		-- aucune acquisition n'est possible, et le serveur continue de tourner (audit P10).
		warn("[Profils] DataStore inaccessible : " .. tostring(backendOrError) .. " — sauvegardes indisponibles.")
		return DataStoreBackend.unavailable(tostring(backendOrError)), "indisponible"
	end
	return backendOrError, "DataStore " .. name
end

return DataStoreBackend
