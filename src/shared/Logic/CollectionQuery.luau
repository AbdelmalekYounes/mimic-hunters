--!strict
--[[
	CollectionQuery — filtres, tris, pages et complétion de la collection (pur, testé).

	Utilisé par l'interface (inventaire, codex) ; ne modifie jamais les exemplaires reçus.
	Un exemplaire est la vue envoyée par le serveur :
	{ id, speciesId, rarity, mutation, seed, acquiredAt, favorite }.
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)
local Mutations = require(script.Parent.Parent.Config.Mutations)

export type Filter = {
	rarity: string?, -- nil = toutes
	species: string?,
	mutation: string?,
	favoritesOnly: boolean?,
}

local CollectionQuery = {}

CollectionQuery.SortModes = table.freeze({ "Recent", "Rarity" })

-- Numéro d'exemplaire (« S12-34 » → 34), pour départager à seconde égale.
function CollectionQuery.serialOf(id: string): number
	return tonumber(string.match(id, "%-(%d+)$")) or 0
end

local function recentFirst(a: any, b: any): boolean
	if a.acquiredAt ~= b.acquiredAt then
		return a.acquiredAt > b.acquiredAt
	end
	return CollectionQuery.serialOf(a.id) > CollectionQuery.serialOf(b.id)
end

local function rarityScore(specimen: any): (number, number)
	local mutation = Mutations.get(specimen.mutation)
	local rarity = Rarities.get(specimen.rarity)
	return (if mutation then mutation.order else 0), (if rarity then rarity.order else 0)
end

function CollectionQuery.filter(specimens: { any }, filter: Filter): { any }
	local out = {}
	for _, s in specimens do
		if
			(filter.rarity == nil or s.rarity == filter.rarity)
			and (filter.species == nil or s.speciesId == filter.species)
			and (filter.mutation == nil or s.mutation == filter.mutation)
			and (not filter.favoritesOnly or s.favorite == true)
		then
			table.insert(out, s)
		end
	end
	return out
end

--[[
	Tri : "Recent" (capture la plus récente d'abord) ou "Rarity" (mutation la plus rare, puis
	rareté d'espèce la plus haute, puis plus récent). Les favoris ne changent pas l'ordre.
]]
function CollectionQuery.sort(specimens: { any }, mode: string): { any }
	local out = table.clone(specimens)
	if mode == "Rarity" then
		table.sort(out, function(a, b)
			local ma, ra = rarityScore(a)
			local mb, rb = rarityScore(b)
			if ma ~= mb then
				return ma > mb
			end
			if ra ~= rb then
				return ra > rb
			end
			return recentFirst(a, b)
		end)
	else
		table.sort(out, recentFirst)
	end
	return out
end

-- Page `page` (1..n) de `perPage` éléments. Retourne (éléments, page effective, nombre de pages).
function CollectionQuery.paginate(list: { any }, page: number, perPage: number): ({ any }, number, number)
	perPage = math.max(1, math.floor(perPage))
	local pages = math.max(1, math.ceil(#list / perPage))
	page = math.clamp(math.floor(page), 1, pages)
	local out = {}
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #list) do
		table.insert(out, list[i])
	end
	return out, page, pages
end

--[[
	Complétion : espèces découvertes, mutations trouvées par espèce et au total.
	`summary` : résumé envoyé par le serveur ; `catalog` : MimicCatalog.
]]
function CollectionQuery.completion(summary: any, catalog: any): any
	local species = catalog.list()
	local discovered = 0
	local variants, variantsTotal = 0, 0
	local mutationCount = #Mutations.list()
	for _, s in species do
		local entry = summary and summary.codex and summary.codex[s.id]
		variantsTotal += mutationCount
		if entry then
			discovered += 1
			variants += #(entry.mutations or {})
		end
	end
	return {
		discovered = discovered,
		total = #species,
		percent = if #species > 0 then math.floor(discovered / #species * 100 + 0.5) else 0,
		-- Toutes les apparences : 6 espèces × 3 mutations.
		variants = variants,
		variantsTotal = variantsTotal,
		complete = discovered == #species,
	}
end

-- Valeurs proposées par un filtre qui défile (nil = « Tous »).
function CollectionQuery.cycle(options: { string }, current: string?): string?
	if current == nil then
		return options[1]
	end
	for i, option in options do
		if option == current then
			return options[i + 1] -- nil après la dernière : retour à « Tous »
		end
	end
	return nil
end

return CollectionQuery
