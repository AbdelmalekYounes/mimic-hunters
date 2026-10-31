--!strict
--[[
	PlotRegistry — attribution des parcelles de musée (pur, testé).

	- Une parcelle n'a jamais deux propriétaires, un joueur n'a jamais deux parcelles.
	- Serveur plein : le joueur attend (file d'attente) ; il reçoit la première parcelle
	  libérée, sans action de sa part. Le jeu reste jouable sans musée en attendant.
	- Libération au départ du joueur.
]]

local PlotRegistry = {}
PlotRegistry.__index = PlotRegistry

function PlotRegistry.new(count: number)
	local self = setmetatable({}, PlotRegistry)
	self._count = count
	self._owners = {} :: { [number]: number } -- parcelle → userId
	self._plots = {} :: { [number]: number } -- userId → parcelle
	self._waiting = {} :: { number }
	return self
end

function PlotRegistry.plotOf(self: any, userId: number): number?
	return self._plots[userId]
end

function PlotRegistry.ownerOf(self: any, plot: number): number?
	return self._owners[plot]
end

function PlotRegistry.isWaiting(self: any, userId: number): boolean
	return table.find(self._waiting, userId) ~= nil
end

function PlotRegistry.freeCount(self: any): number
	local used = 0
	for _ in self._owners do
		used += 1
	end
	return self._count - used
end

-- Propriétaires actuels, triés par parcelle.
function PlotRegistry.owners(self: any): { { plot: number, userId: number } }
	local out = {}
	for plot = 1, self._count do
		local userId = self._owners[plot]
		if userId then
			table.insert(out, { plot = plot, userId = userId })
		end
	end
	return out
end

--[[
	Attribue la première parcelle libre. Retourne le numéro de parcelle, ou nil si le joueur
	est mis en file d'attente. Idempotent : un joueur qui a déjà une parcelle la garde.
]]
function PlotRegistry.assign(self: any, userId: number): number?
	local existing = self._plots[userId]
	if existing then
		return existing
	end
	for plot = 1, self._count do
		if self._owners[plot] == nil then
			self._owners[plot] = userId
			self._plots[userId] = plot
			return plot
		end
	end
	if not self:isWaiting(userId) then
		table.insert(self._waiting, userId)
	end
	return nil
end

--[[
	Libère la parcelle du joueur (ou le retire de la file). Si quelqu'un attendait, il reçoit
	aussitôt la parcelle libérée. Retourne (parcelle libérée?, joueur servi?).
]]
function PlotRegistry.release(self: any, userId: number): (number?, number?)
	local index = table.find(self._waiting, userId)
	if index then
		table.remove(self._waiting, index)
	end
	local plot = self._plots[userId]
	if plot == nil then
		return nil, nil
	end
	self._plots[userId] = nil
	self._owners[plot] = nil
	local nextUser = table.remove(self._waiting, 1)
	if nextUser then
		self._owners[plot] = nextUser
		self._plots[nextUser] = plot
	end
	return plot, nextUser
end

return PlotRegistry
