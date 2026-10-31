--!strict
--[[
	ModelView — aperçus 3D des Mimics dans l'interface (ViewportFrame).

	Construit le modèle (référence, silhouette ou exemplaire précis avec sa mutation), le cadre
	avec une caméra adaptée à sa hauteur, et branche les effets de mutation (MutationFx).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local PropBuilder = require(Shared.Builders.PropBuilder)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local SpecimenLook = require(Shared.Logic.SpecimenLook)

local MutationFx = require(script.Parent.Parent.Util.MutationFx)

local ModelView = {}

-- Vide le ViewportFrame (modèles et caméras).
function ModelView.clear(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") or child:IsA("WorldModel") then
			child:Destroy()
		end
	end
end

-- Place `model` à l'origine dans le ViewportFrame avec une caméra cadrée sur sa hauteur.
function ModelView.frame(viewport: ViewportFrame, model: Model, kind: string, zoom: number?)
	ModelView.clear(viewport)
	model:PivotTo(CFrame.identity)
	model.Parent = viewport
	local anchor = PropBuilder.FaceAnchors[kind]
	local height = (if anchor then anchor.height else 4) * model:GetScale()
	local distance = (height * 1.45 + 4) * (zoom or 1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame =
		CFrame.lookAt(Vector3.new(distance * 0.35, height * 0.62, -distance), Vector3.new(0, height * 0.5, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Aperçu d'un exemplaire (vue serveur) avec son apparence et sa mutation. Retourne le modèle.
function ModelView.specimen(viewport: ViewportFrame, specimen: any, animated: boolean?): Model?
	local species = MimicCatalog.get(specimen.speciesId)
	if species == nil then
		ModelView.clear(viewport)
		return nil
	end
	local look = SpecimenLook.compute(species, specimen.seed, specimen.mutation)
	local model = MimicModelBuilder.build(species.id, nil, look)
	ModelView.frame(viewport, model, species.kind)
	if animated then
		MutationFx.attach(model, look)
	end
	return model
end

-- Aperçu de référence d'une espèce, ou sa silhouette si elle n'est pas encore découverte.
function ModelView.species(viewport: ViewportFrame, speciesId: string, discovered: boolean): Model?
	local species = MimicCatalog.get(speciesId)
	if species == nil then
		return nil
	end
	local model = if discovered then MimicModelBuilder.build(species.id) else MimicModelBuilder.silhouette(species.id)
	ModelView.frame(viewport, model, species.kind)
	return model
end

return ModelView
