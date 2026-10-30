--!strict
--[[
	WeightedPicker — tirage pondéré générique.
	Les entrées de poids nul ou négatif ne sont jamais choisies.
]]

export type Entry<T> = { item: T, weight: number }

local WeightedPicker = {}

function WeightedPicker.total<T>(entries: { Entry<T> }): number
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 then
			total += entry.weight
		end
	end
	return total
end

function WeightedPicker.pick<T>(entries: { Entry<T> }, rng: any): T?
	local total = WeightedPicker.total(entries)
	if total <= 0 then
		return nil
	end
	local roll = rng:nextNumber() * total
	local last: T? = nil
	for _, entry in entries do
		if entry.weight > 0 then
			last = entry.item
			roll -= entry.weight
			if roll < 0 then
				return entry.item
			end
		end
	end
	-- Sécurité contre les erreurs d'arrondi : dernier élément valide.
	return last
end

return WeightedPicker
