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

--[[
	Place `model` à l'origine dans le ViewportFrame, caméra de trois quarts face.
	Cadrage sur l'encombrement réel du modèle (et non une hauteur de référence par type
	d'objet) : le coffre, large et bas, apparaissait trop gros sur les captures de la VM.
]]
function ModelView.frame(viewport: ViewportFrame, model: Model, kind: string, zoom: number?)
	ModelView.clear(viewport)
	model:PivotTo(CFrame.identity)
	model.Parent = viewport
	local box, size = model:GetBoundingBox()
	local anchor = PropBuilder.FaceAnchors[kind]
	local height = math.max(size.Y, (if anchor then anchor.height else 4) * model:GetScale())
	-- Rayon de la sphère englobante : le modèle tient entier quelle que soit sa rotation.
	local radius = size.Magnitude / 2
	local fov = 40
	local distance = (radius / math.tan(math.rad(fov / 2)) * 1.08 + 0.5) * (zoom or 1)
	local target = Vector3.new(0, box.Position.Y, 0)
	local direction = Vector3.new(0.35, 0.3, -1).Unit
	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(target + direction * distance, target + Vector3.new(0, height * 0.02, 0))
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
