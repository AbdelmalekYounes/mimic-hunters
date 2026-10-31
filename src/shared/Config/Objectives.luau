--!strict
--[[
	Objectives — progression du collectionneur (V0.2).

	Des objectifs simples, liés aux découvertes, qui donnent chacun une récompense cosmétique
	GARANTIE : un titre (affiché au-dessus du personnage, visible par tous) ou une couleur de
	scanner. Aucune monnaie, aucun rebirth, aucun arbre d'amélioration.

	Le serveur valide les objectifs (Collection.evaluateObjectives) après chaque capture ;
	le client n'affiche que la progression calculée à partir du résumé reçu.
]]

export type Cosmetic = {
	id: string,
	kind: string, -- "title" | "scannerColor"
	name: string,
	color: { number },
}

export type Objective = {
	id: string,
	title: string,
	description: string,
	condition: { type: string, count: number?, mutation: string? },
	reward: { id: string, kind: string },
}

local cosmetics: { Cosmetic } = {
	-- Couleurs de scanner (onde du scan).
	{ id = "Cyan", kind = "scannerColor", name = "Cyan", color = { 110, 220, 255 } },
	{ id = "color_mint", kind = "scannerColor", name = "Menthe", color = { 110, 250, 200 } },
	{ id = "color_coral", kind = "scannerColor", name = "Corail", color = { 255, 140, 120 } },
	{ id = "color_prism", kind = "scannerColor", name = "Prisme", color = { 255, 132, 214 } },
	-- Titres de collectionneur.
	{ id = "title_apprentice", kind = "title", name = "Apprenti chasseur", color = { 146, 214, 120 } },
	{ id = "title_whisper", kind = "title", name = "Murmure spectral", color = { 132, 236, 255 } },
	{ id = "title_master", kind = "title", name = "Maître des Mimics", color = { 255, 210, 90 } },
	-- V0.3 : musée.
	{ id = "title_explorer", kind = "title", name = "Explorateur de musées", color = { 255, 150, 210 } },
	{ id = "pedestal_star", kind = "pedestal", name = "Socles Étoilés", color = { 255, 220, 100 } },
}

local objectives: { Objective } = {
	{
		id = "first_capture",
		title = "Première capture",
		description = "Capture ton tout premier Mimic.",
		condition = { type = "captures", count = 1 },
		reward = { id = "title_apprentice", kind = "title" },
	},
	{
		id = "three_species",
		title = "Trois espèces",
		description = "Découvre trois espèces différentes.",
		condition = { type = "species", count = 3 },
		reward = { id = "color_mint", kind = "scannerColor" },
	},
	{
		id = "ten_captures",
		title = "Dix captures",
		description = "Capture dix Mimics, doublons compris.",
		condition = { type = "captures", count = 10 },
		reward = { id = "color_coral", kind = "scannerColor" },
	},
	{
		id = "first_chromatic",
		title = "Première Chromatic",
		description = "Capture un Mimic à la mutation Chromatic.",
		condition = { type = "mutation", mutation = "Chromatic" },
		reward = { id = "color_prism", kind = "scannerColor" },
	},
	{
		id = "first_spectral",
		title = "Première Spectral",
		description = "Capture un Mimic à la mutation Spectral.",
		condition = { type = "mutation", mutation = "Spectral" },
		reward = { id = "title_whisper", kind = "title" },
	},
	{
		id = "full_codex",
		title = "Collection complète",
		description = "Découvre les six espèces de Mimics.",
		condition = { type = "species", count = 6 },
		reward = { id = "title_master", kind = "title" },
	},
	-- V0.3 : exposer, puis visiter les musées des autres.
	{
		id = "first_exhibit",
		title = "Première vitrine",
		description = "Expose un Mimic dans ton musée.",
		condition = { type = "exhibits", count = 1 },
		reward = { id = "pedestal_star", kind = "pedestal" },
	},
	{
		id = "museum_explorer",
		title = "Explorateur de musées",
		description = "Réussis une Museum Hunt dans 3 musées différents.",
		condition = { type = "museums", count = 3 },
		reward = { id = "title_explorer", kind = "title" },
	},
}

local cosmeticById: { [string]: Cosmetic } = {}
for _, c in cosmetics do
	cosmeticById[c.id] = c
end

local Objectives = {}

Objectives.DefaultScannerColor = "Cyan"

function Objectives.list(): { Objective }
	return objectives
end

function Objectives.cosmetic(id: string?): Cosmetic?
	return if id then cosmeticById[id] else nil
end

function Objectives.cosmetics(): { Cosmetic }
	return cosmetics
end

-- Cosmétiques disponibles sans objectif.
function Objectives.defaults(): { [string]: boolean }
	return { [Objectives.DefaultScannerColor] = true }
end

--[[
	Progression d'un objectif à partir du résumé envoyé par le serveur.
	Retourne (actuel, cible) ; l'objectif est atteint quand actuel >= cible.
]]
function Objectives.progress(objective: Objective, summary: any): (number, number)
	local condition = objective.condition
	if summary == nil then
		return 0, condition.count or 1
	end
	if condition.type == "captures" then
		local target = condition.count or 1
		return math.min(summary.totalCaptures or 0, target), target
	elseif condition.type == "species" then
		local target = condition.count or 1
		return math.min(summary.discovered or 0, target), target
	elseif condition.type == "mutation" then
		local count = summary.mutations and summary.mutations[condition.mutation] or 0
		return math.min(count, 1), 1
	elseif condition.type == "exhibits" then
		local target = condition.count or 1
		local exhibited = 0
		for _, id in (summary.museum and summary.museum.slots) or {} do
			if id ~= "" then
				exhibited += 1
			end
		end
		return math.min(exhibited, target), target
	elseif condition.type == "museums" then
		local target = condition.count or 1
		return math.min(summary.hunts and summary.hunts.museums or 0, target), target
	end
	return 0, 1
end

-- Texte de la récompense : « Titre « Apprenti chasseur » », « Couleur de scanner Menthe ».
function Objectives.rewardText(objective: Objective): string
	local cosmetic = cosmeticById[objective.reward.id]
	if cosmetic == nil then
		return "?"
	end
	if cosmetic.kind == "title" then
		return string.format("Titre « %s »", cosmetic.name)
	elseif cosmetic.kind == "pedestal" then
		return cosmetic.name .. " pour ton musée"
	end
	return string.format("Couleur de scanner %s", cosmetic.name)
end

return Objectives
