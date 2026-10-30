--!strict
--[[
	LightingSetup — ambiance « cute-creepy » : fin d'après-midi violacée,
	lumière douce, légère brume et lampadaires allumés.
]]

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

function LightingSetup.apply()
	Lighting.ClockTime = 17.3
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(72, 62, 92)
	Lighting.OutdoorAmbient = Color3.fromRGB(132, 120, 162)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.4
	Lighting.GlobalShadows = true

	local atmosphere = ensure("Atmosphere", "MimicAtmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(212, 186, 236)
	atmosphere.Decay = Color3.fromRGB(122, 96, 162)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2

	local color = ensure("ColorCorrectionEffect", "MimicColor") :: ColorCorrectionEffect
	color.Saturation = 0.12
	color.Contrast = 0.06
	color.TintColor = Color3.fromRGB(255, 246, 255)

	local bloom = ensure("BloomEffect", "MimicBloom") :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.6
end

return LightingSetup
