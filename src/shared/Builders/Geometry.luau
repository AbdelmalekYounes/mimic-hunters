--!strict
--[[
	Geometry — fabrique de Parts ancrées, sans assets externes.
]]

local Geometry = {}

function Geometry.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Assombrit (factor < 1) ou éclaircit (factor > 1) une couleur.
function Geometry.shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

export type PartProps = {
	Name: string?,
	Shape: Enum.PartType?,
	Size: Vector3?,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Reflectance: number?,
	ClassName: string?,
	Parent: Instance?,
}

--[[
	Crée une Part ancrée. Les propriétés sont appliquées dans un ordre fixe
	(Shape avant Size, Size avant CFrame) pour un résultat déterministe.
]]
function Geometry.part(props: PartProps): BasePart
	local part: BasePart
	if props.ClassName == "WedgePart" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if props.Shape then
			p.Shape = props.Shape
		end
		part = p
	end
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Size = props.Size or Vector3.one
	part.CFrame = props.CFrame
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.Name = props.Name or "Part"
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

-- Cylindre vertical (l'axe des cylindres Roblox est X : on le tourne vers Y).
function Geometry.cylinder(props: PartProps & { height: number, diameter: number }): BasePart
	local copy = table.clone(props) :: any
	copy.Shape = Enum.PartType.Cylinder
	copy.Size = Vector3.new(props.height, props.diameter, props.diameter)
	copy.CFrame = props.CFrame * CFrame.Angles(0, 0, math.rad(90))
	copy.height = nil
	copy.diameter = nil
	return Geometry.part(copy)
end

function Geometry.ball(props: PartProps): BasePart
	local copy = table.clone(props) :: any
	copy.Shape = Enum.PartType.Ball
	return Geometry.part(copy)
end

-- Rotation qui fait regarder l'avant (-Z) d'un objet vers un point au sol.
function Geometry.faceTowards(position: Vector3, target: Vector3?): CFrame
	if target == nil then
		return CFrame.new(position)
	end
	local flat = Vector3.new(target.X, position.Y, target.Z)
	if (flat - position).Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flat)
end

function Geometry.toVector(point: { X: number, Y: number, Z: number }): Vector3
	return Vector3.new(point.X, point.Y, point.Z)
end

return Geometry
