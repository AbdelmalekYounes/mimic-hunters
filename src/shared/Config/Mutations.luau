--!strict
--[[
	Mutations — apparences rares, purement cosmétiques (aucun effet sur le gameplay).

	Le tirage a lieu UNIQUEMENT sur le serveur, au moment d'une capture réussie
	(HuntWorld._resolveSuccess), avec le générateur du serveur. Le Mimic du tutoriel est
	toujours Standard. Les probabilités ci-dessous sont les seules sources de vérité :
	l'interface les affiche telles quelles.

	Pourquoi ces valeurs : avec environ une capture par minute, un joueur voit sa première
	Chromatic vers la 25e capture (≈ une session), et une Spectral vers la 67e : un vrai
	événement, sans être hors d'atteinte.

	Les palettes visuelles sont appliquées par SpecimenLook (couleurs) et MimicModelBuilder
	(transparence, éclat, petites lueurs).
]]

export type Mutation = {
	id: string,
	displayName: string,
	-- Probabilité par capture réussie (la somme vaut 1).
	chance: number,
	-- Ordre de rareté (tri et affichage) : plus grand = plus rare.
	order: number,
	-- Couleur d'interface (badge, titre de révélation), RGB 0-255.
	color: { number },
	description: string,
}

local list: { Mutation } = {
	{
		id = "Standard",
		displayName = "Standard",
		chance = 0.945,
		order = 1,
		color = { 214, 206, 230 },
		description = "L'apparence habituelle de l'espèce, avec sa petite variation personnelle.",
	},
	{
		id = "Chromatic",
		displayName = "Chromatic",
		chance = 0.04,
		order = 2,
		color = { 255, 132, 214 },
		description = "Couleurs irisées qui changent doucement, et un léger éclat lumineux.",
	},
	{
		id = "Spectral",
		displayName = "Spectral",
		chance = 0.015,
		order = 3,
		color = { 132, 236, 255 },
		description = "À moitié translucide, des yeux qui luisent et de petites lueurs qui flottent autour.",
	},
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
end

local Mutations = {}

function Mutations.get(id: string): Mutation?
	return byId[id]
end

function Mutations.list(): { Mutation }
	return list
end

-- Tire une mutation selon les probabilités (rng : Rng, nombre dans [0, 1)).
function Mutations.roll(rng: any): string
	local x = rng:nextNumber()
	local cumulative = 0
	-- Les plus rares d'abord : un arrondi en fin de liste retombe toujours sur Standard.
	for i = #list, 2, -1 do
		cumulative += list[i].chance
		if x < cumulative then
			return list[i].id
		end
	end
	return "Standard"
end

-- Texte de probabilité à la française : « 4 % », « 1,5 % », « 94,5 % ».
function Mutations.chanceText(id: string): string
	local mutation = byId[id]
	if mutation == nil then
		return "?"
	end
	local percent = mutation.chance * 100
	local text = if math.abs(percent - math.floor(percent + 0.5)) < 1e-9
		then string.format("%d", math.floor(percent + 0.5))
		else (string.gsub(string.format("%.1f", percent), "%.", ","))
	return text .. " %"
end

function Mutations.isRare(id: string): boolean
	local mutation = byId[id]
	return mutation ~= nil and mutation.order > 1
end

return Mutations
