--!strict
--[[
	Animate — petites animations procédurales pilotées par TweenService.

	TweenService:GetValue fournit les courbes d'accélération ; la boucle met
	à jour le pivot / l'échelle d'un Model à chaque image. Aucune animation
	n'est répliquée : tout est local au client.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Animate = {}

-- Exécute `step(alpha)` de 0 à 1 sur `duration` secondes (bloquant : à appeler dans task.spawn).
function Animate.run(
	duration: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	step: (alpha: number, raw: number) -> ()
)
	local start = os.clock()
	while true do
		local raw = math.min((os.clock() - start) / math.max(duration, 1e-3), 1)
		step(TweenService:GetValue(raw, style, direction), raw)
		if raw >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

function Animate.linear(duration: number, step: (alpha: number, raw: number) -> ())
	Animate.run(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, step)
end

-- Échelle d'un Model, bornée pour éviter les erreurs de ScaleTo.
function Animate.scale(model: Model, value: number)
	if model.Parent then
		model:ScaleTo(math.max(value, 0.02))
	end
end

function Animate.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Fondu d'une liste de parts vers une transparence cible.
function Animate.fade(parts: { BasePart }, target: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in parts do
		TweenService:Create(part, info, { Transparency = target }):Play()
	end
end

function Animate.tween(
	instance: Instance,
	duration: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

return Animate
