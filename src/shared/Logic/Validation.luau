--!strict
--[[
	Validation — contrôles de base des données reçues par le réseau.
	Fonctionne avec les Vector3 Roblox comme avec des tables {X, Y, Z}.
]]

local Validation = {}

function Validation.isId(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = #value
	if length == 0 or length > (maxLength or 24) then
		return false
	end
	return string.match(value, "^[%w_%-]+$") ~= nil
end

function Validation.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validation.isPosition(value: any): boolean
	local kind = typeof(value)
	if kind ~= "Vector3" and kind ~= "table" then
		return false
	end
	return Validation.isFiniteNumber(value.X)
		and Validation.isFiniteNumber(value.Y)
		and Validation.isFiniteNumber(value.Z)
end

function Validation.horizontalDistance(a: any, b: any): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Portée horizontale + tolérance verticale (empêche d'agir depuis le ciel).
function Validation.withinReach(origin: any, target: any, range: number, verticalTolerance: number): boolean
	if not Validation.isPosition(origin) or not Validation.isPosition(target) then
		return false
	end
	if math.abs(origin.Y - target.Y) > verticalTolerance then
		return false
	end
	return Validation.horizontalDistance(origin, target) <= range
end

return Validation
