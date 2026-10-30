--!strict
--[[
	Rng — générateur pseudo-aléatoire déterministe (Park–Miller, 48271).

	Utilisé à la place de `Random` pour que la logique pure soit testable
	hors Roblox avec une graine fixe. Tous les produits restent < 2^53 :
	le calcul est exact en double précision.
]]

local MODULUS = 2147483647
local MULTIPLIER = 48271

export type Rng = {
	_state: number,
	nextNumber: (self: Rng) -> number,
	nextInteger: (self: Rng, min: number, max: number) -> number,
	nextRange: (self: Rng, min: number, max: number) -> number,
	pick: <T>(self: Rng, list: { T }) -> T?,
}

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	return (setmetatable({ _state = state }, Rng) :: any) :: Rng
end

-- Nombre dans [0, 1).
function Rng.nextNumber(self: Rng): number
	self._state = (self._state * MULTIPLIER) % MODULUS
	return (self._state - 1) / (MODULUS - 1)
end

-- Entier dans [min, max], bornes incluses.
function Rng.nextInteger(self: Rng, min: number, max: number): number
	if max < min then
		min, max = max, min
	end
	return min + math.floor(self:nextNumber() * (max - min + 1))
end

function Rng.nextRange(self: Rng, min: number, max: number): number
	return min + (max - min) * self:nextNumber()
end

function Rng.pick<T>(self: Rng, list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[self:nextInteger(1, #list)]
end

return Rng
