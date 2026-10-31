--!strict
--[[
	MimicVisuals — tout ce qui se voit dans le monde :
	- indices discrets sur les objets (bouger, vibrer, yeux, bruit, glitch…) ;
	- révélation exagérée (le Mimic jaillit de son objet) ;
	- animation d'attente / de lutte pendant la capture ;
	- animation de capture (aspiré vers le chasseur) et de fuite.

	Le client ne fait qu'illustrer les états décidés par le serveur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local PropBuilder = require(Shared.Builders.PropBuilder)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local SpecimenLook = require(Shared.Logic.SpecimenLook)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local MutationFx = require(Client.Util.MutationFx)
local Theme = require(Client.UI.Theme)
local PropTracker = require(script.Parent.PropTracker)

local C = CFrame.new

type Creature = {
	mimicId: string,
	propId: string,
	speciesId: string,
	model: Model,
	base: CFrame,
	mode: string,
	animating: boolean,
	billboard: BillboardGui,
	status: TextLabel,
	info: ClientState.MimicInfo,
}

local MimicVisuals = {}

local creatures: { [string]: Creature } = {}
local clueBusy: { [string]: boolean } = {}
local effects: Folder
-- Exemplaire obtenu par mimicId, reçu (CaptureResolved) juste avant l'état « Captured ».
local pendingSpecimens: { [string]: any } = {}

local function rarityColor(speciesId: string): Color3
	local species = MimicCatalog.get(speciesId)
	local rarity = species and Rarities.get(species.rarity)
	return if rarity then Theme.rgb(rarity.color) else Color3.new(1, 1, 1)
end

local function partsOf(model: Model): { BasePart }
	local out = {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			table.insert(out, child)
		end
	end
	return out
end

-- Réglage « Effets réduits » du joueur (profil) : moins de particules, pas d'anneaux.
local function reducedEffects(): boolean
	local summary = ClientState.summary
	return summary ~= nil and summary.settings ~= nil and summary.settings.reducedEffects == true
end

-- Ordre de rareté de l'espèce (1 = Commun … 4 = Épique) : dose les effets.
local function rarityOrder(speciesId: string): number
	local species = MimicCatalog.get(speciesId)
	local rarity = species and Rarities.get(species.rarity)
	return if rarity then rarity.order else 1
end

-- Anneau lumineux qui s'élargit au sol (révélation rare, capture d'une espèce rare).
local function ring(position: Vector3, color: Color3, diameter: number, duration: number)
	if reducedEffects() then
		return
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(0.2, 2, 2)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = effects
	Animate.tween(part, duration, { Size = Vector3.new(0.2, diameter, diameter), Transparency = 1 })
	Debris:AddItem(part, duration + 0.1)
end

-- Petite explosion de particules (aucune texture externe : texture intégrée).
local function burst(position: Vector3, color: Color3, amount: number)
	if reducedEffects() then
		amount = math.max(4, math.floor(amount / 3))
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	holder.Parent = effects
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(amount)
	Debris:AddItem(holder, 1.5)
end

-- ─── Indices sur les objets déguisés ───────────────────────────────────

local function restorePivot(model: Model, base: CFrame)
	if model.Parent then
		model:PivotTo(base)
	end
end

local function wiggle(model: Model, strong: boolean)
	local base = model:GetPivot()
	local amp = if strong then 9 else 4.5
	Audio.playAt(model.PrimaryPart :: BasePart, "ClueCreak")
	Animate.linear(0.7, function(_, t)
		local angle = math.sin(t * math.pi * 5) * amp * (1 - t)
		model:PivotTo(base * CFrame.Angles(0, math.rad(angle), math.rad(angle * 0.4)))
	end)
	restorePivot(model, base)
end

local function vibrate(model: Model, strong: boolean, duration: number?)
	local base = model:GetPivot()
	local amp = if strong then 0.14 else 0.07
	Animate.linear(duration or 0.5, function(_, t)
		local fade = 1 - t
		model:PivotTo(
			base
				* C(
					(math.random() - 0.5) * amp * fade,
					math.random() * amp * 0.5 * fade,
					(math.random() - 0.5) * amp * fade
				)
		)
	end)
	restorePivot(model, base)
end

local function eyes(model: Model, kind: string, strong: boolean)
	local anchor = PropBuilder.FaceAnchors[kind]
	if anchor == nil then
		return
	end
	local base = model:GetPivot()
	local holder = Instance.new("Model")
	holder.Name = "PeekingEyes"
	MimicModelBuilder.addEyes(holder, kind, "Round", base)
	holder.WorldPivot = base * anchor.cframe
	holder.Parent = effects
	Animate.scale(holder, 0.05)
	Animate.run(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		Animate.scale(holder, Animate.lerp(0.05, 1, a))
	end)
	task.wait(if strong then 0.7 else 0.35)
	-- Clignement : les pupilles disparaissent un court instant.
	for _, part in holder:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Pupil" then
			part.Transparency = 1
		end
	end
	task.wait(0.08)
	for _, part in holder:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Pupil" then
			part.Transparency = 0
		end
	end
	task.wait(if strong then 0.4 else 0.2)
	Animate.run(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		Animate.scale(holder, Animate.lerp(1, 0.05, a))
	end)
	holder:Destroy()
end

local function rattle(model: Model, kind: string, strong: boolean)
	local parts = PropBuilder.groupParts(model, "Lid")
	if #parts == 0 then
		vibrate(model, strong)
		return
	end
	local saved = {}
	for _, part in parts do
		saved[part] = part.CFrame
	end
	local height = if strong then 0.6 else 0.3
	Audio.playAt(model.PrimaryPart :: BasePart, "ClueChomp", if kind == "Chest" then 1.3 else 0.9)
	Animate.linear(0.6, function(_, t)
		local lift = math.abs(math.sin(t * math.pi * 4)) * height * (1 - t)
		local tilt = math.sin(t * math.pi * 8) * 0.08 * (1 - t)
		for part, original in saved do
			part.CFrame = original * C(0, lift, 0) * CFrame.Angles(0, 0, tilt)
		end
	end)
	for part, original in saved do
		part.CFrame = original
	end
end

local function flag(model: Model, kind: string, strong: boolean)
	local anchor = PropBuilder.FaceAnchors[kind]
	local parts = PropBuilder.groupParts(model, "Flag")
	if #parts == 0 or anchor == nil or anchor.hinge == nil then
		wiggle(model, strong)
		return
	end
	local hinge = model:GetPivot() * (anchor.hinge :: CFrame)
	local saved = {}
	for _, part in parts do
		saved[part] = hinge:ToObjectSpace(part.CFrame)
	end
	local function setAngle(angle: number)
		for part, relative in saved do
			part.CFrame = hinge * CFrame.Angles(math.rad(angle), 0, 0) * relative
		end
	end
	local target = if strong then -85 else -55
	Animate.run(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		setAngle(target * a)
	end)
	task.wait(if strong then 0.6 else 0.35)
	Animate.run(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		setAngle(target * (1 - a))
	end)
	setAngle(0)
end

local function glowParts(model: Model): ({ BasePart }, { Light })
	local parts, lights = {}, {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("Glow") then
			table.insert(parts, child)
		elseif child:IsA("Light") then
			table.insert(lights, child)
		end
	end
	return parts, lights
end

local function flicker(model: Model, strong: boolean)
	local parts, lights = glowParts(model)
	if #parts == 0 then
		vibrate(model, strong)
		return
	end
	local flashes = if strong then 8 else 5
	for i = 1, flashes do
		local on = i % 2 == 0
		for _, part in parts do
			part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		for _, light in lights do
			light.Enabled = on
		end
		task.wait(0.06 + math.random() * 0.08)
	end
	for _, part in parts do
		part.Material = Enum.Material.Neon
	end
	for _, light in lights do
		light.Enabled = true
	end
end

local function glitch(model: Model, strong: boolean)
	local parts = glowParts(model)
	local saved = {}
	for _, part in parts do
		saved[part] = part.Color
	end
	local palette = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(60, 255, 200), Color3.fromRGB(255, 255, 80) }
	local base = model:GetPivot()
	Audio.playAt(model.PrimaryPart :: BasePart, "ClueHum")
	Animate.linear(if strong then 0.9 else 0.55, function()
		for part in saved do
			part.Color = palette[math.random(1, #palette)]
		end
		model:PivotTo(base * C((math.random() - 0.5) * 0.12, 0, 0))
	end)
	for part, color in saved do
		part.Color = color
	end
	restorePivot(model, base)
end

local function sound(model: Model, kind: string, strong: boolean)
	local name = if kind == "TrashCan" or kind == "Chest"
		then "ClueChomp"
		elseif kind == "Vending" then "ClueHum"
		else "ClueCreak"
	Audio.playAt(model.PrimaryPart :: BasePart, name, 0.8 + math.random() * 0.4)
	vibrate(model, strong, 0.3)
end

function MimicVisuals.playClue(propId: string, clue: string, strong: boolean)
	if clueBusy[propId] or PropTracker.isHidden(propId) then
		return
	end
	local model = PropTracker.get(propId)
	local kind = PropTracker.kindOf(propId)
	if model == nil or kind == nil or model.PrimaryPart == nil then
		return
	end
	clueBusy[propId] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if strong then
				task.spawn(eyes, model, kind, true)
			end
			-- "Wiggle" et tout indice inconnu : la branche finale.
			if clue == "Vibrate" then
				vibrate(model, strong)
			elseif clue == "Eyes" then
				if not strong then
					eyes(model, kind, false)
				else
					wiggle(model, true)
				end
			elseif clue == "Rattle" then
				rattle(model, kind, strong)
			elseif clue == "Flag" then
				flag(model, kind, strong)
			elseif clue == "Flicker" then
				flicker(model, strong)
			elseif clue == "Glitch" then
				glitch(model, strong)
			elseif clue == "Sound" then
				sound(model, kind, strong)
			else
				wiggle(model, strong)
			end
		end)
		clueBusy[propId] = nil
		if not ok then
			warn("[MimicVisuals] indice", clue, err)
		end
	end)
end

-- ─── Créatures révélées ────────────────────────────────────────────────

local function statusText(creature: Creature): string
	local info = creature.info
	local mine = info.ownerUserId == ClientState.userId
	local owner = if info.ownerUserId then Players:GetPlayerByUserId(info.ownerUserId) else nil
	local ownerName = if owner then owner.DisplayName else "un chasseur"
	if creature.mode == "Capturing" then
		return if mine then "Stabilise-le !" else ownerName .. " tente la capture…"
	end
	if mine then
		local remaining = if info.expiresAt then math.max(0, math.ceil(info.expiresAt - os.clock())) else nil
		return if remaining then string.format("À toi ! Capture-le (%ds)", remaining) else "À toi ! Capture-le"
	end
	return "Repéré par " .. ownerName
end

local function makeBillboard(model: Model, species: any, height: number, base: CFrame): (BillboardGui, TextLabel)
	local primary = model.PrimaryPart :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "MimicTag"
	gui.Size = UDim2.fromOffset(230, 62)
	gui.StudsOffsetWorldSpace = Vector3.new(0, base.Position.Y + height + 1.8 - primary.Position.Y, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.Adornee = primary
	local name = Theme.text({
		Text = species.name,
		Font = Theme.Fonts.Title,
		TextColor3 = rarityColor(species.id),
		Size = UDim2.fromScale(1, 0.6),
		MaxTextSize = 30,
		TextStrokeTransparency = 0.2,
		Parent = gui,
	})
	name.TextStrokeColor3 = Color3.fromRGB(20, 12, 30)
	local status = Theme.text({
		Text = "",
		Font = Theme.Fonts.Bold,
		Size = UDim2.new(1, 0, 0.4, 0),
		Position = UDim2.fromScale(0, 0.6),
		MaxTextSize = 18,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})
	gui.Parent = model
	return gui, status
end

local function revealAnimation(creature: Creature)
	local species = MimicCatalog.get(creature.speciesId)
	if species == nil then
		return
	end
	creature.animating = true
	local model, base = creature.model, creature.base
	local style = species.behavior.revealStyle
	local spin = if style == "Hop" or style == "Flag" then math.pi * 2 else math.pi
	Audio.playAt(model.PrimaryPart :: BasePart, "Reveal", 1.1 - rarityOrder(species.id) * 0.06)
	-- Plus l'espèce est rare, plus la révélation est marquée (particules, anneau dès « Rare »).
	local order = rarityOrder(species.id)
	burst(base.Position + Vector3.new(0, 2, 0), rarityColor(species.id), 12 + order * 6)
	if order >= 3 then
		ring(base.Position, rarityColor(species.id), 10 + order * 2, 0.5)
	end
	if style == "Flash" then
		for _, light in model:GetDescendants() do
			if light:IsA("PointLight") then
				light.Range = 40
				light.Brightness = 5
				Animate.tween(light, 0.9, { Range = 18, Brightness = 2.2 })
			end
		end
	end
	Animate.run(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a, raw)
		Animate.scale(model, Animate.lerp(0.55, 1.15, a))
		local jump = math.sin(raw * math.pi) * 3
		model:PivotTo(base * C(0, jump, 0) * CFrame.Angles(0, spin * raw, 0))
	end)
	if style == "LidPop" or style == "Chomp" then
		local lid = PropBuilder.groupParts(model, "Lid")
		local saved = {}
		for _, part in lid do
			saved[part] = model:GetPivot():ToObjectSpace(part.CFrame)
		end
		Animate.linear(0.6, function(_, t)
			local pivot = model:GetPivot()
			local open = math.abs(math.sin(t * math.pi * (if style == "Chomp" then 3 else 1))) * (1 - t * 0.5)
			for part, relative in saved do
				part.CFrame = pivot * C(0, open * 1.2, 0) * relative
			end
		end)
	elseif style == "Glitch" then
		Animate.linear(0.4, function()
			model:PivotTo(base * C((math.random() - 0.5) * 0.4, 0, (math.random() - 0.5) * 0.4))
		end)
	end
	Animate.run(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
		Animate.scale(model, Animate.lerp(1.15, 1, a))
	end)
	model:PivotTo(base)
	creature.animating = false
end

local function destroyCreature(creature: Creature)
	creatures[creature.mimicId] = nil
	if creature.model.Parent then
		creature.model:Destroy()
	end
end

local function ownerRoot(userId: number?): BasePart?
	local owner = if userId then Players:GetPlayerByUserId(userId) else nil
	local character = owner and owner.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

--[[
	Révélation d'une mutation (capture rare, joueur concerné uniquement) : éclair et anneau aux
	couleurs de la mutation, le Mimic prend son apparence mutée, petit bond, puis la capture
	continue normalement. ≈ 0,8 s de plus qu'une capture ordinaire.
]]
local function mutationReveal(creature: Creature, specimen: any): Model
	local species = MimicCatalog.get(creature.speciesId)
	local mutation = Mutations.get(specimen.mutation)
	if species == nil or mutation == nil then
		return creature.model
	end
	local old = creature.model
	local pivot = old:GetPivot()
	local color = Theme.rgb(mutation.color)
	local look = SpecimenLook.compute(species, specimen.seed, specimen.mutation)
	local model = MimicModelBuilder.build(species.id, nil, look)
	model:PivotTo(pivot)
	model.Parent = effects
	old:Destroy()
	creature.model = model
	MutationFx.attach(model, look)
	Audio.play("Reveal", 1.35)
	burst(pivot.Position + Vector3.new(0, 2.5, 0), color, 60)
	ring(pivot.Position, color, 16, 0.6)
	Animate.run(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a, raw)
		Animate.scale(model, Animate.lerp(0.7, 1.25, a))
		model:PivotTo(pivot * C(0, math.sin(raw * math.pi) * 2.2, 0) * CFrame.Angles(0, raw * math.pi * 2, 0))
	end)
	task.wait(0.25)
	return model
end

local function captureAnimation(creature: Creature, ownerUserId: number?)
	creature.animating = true
	creature.mode = "Leaving"
	creature.billboard.Enabled = false
	local mine = ownerUserId == ClientState.userId
	local specimen = pendingSpecimens[creature.mimicId]
	pendingSpecimens[creature.mimicId] = nil
	if mine and specimen and Mutations.isRare(specimen.mutation) then
		mutationReveal(creature, specimen)
	end
	local model = creature.model
	local start = model:GetPivot()
	local color = rarityColor(creature.speciesId)
	local order = rarityOrder(creature.speciesId)
	-- Écrasement puis étirement (anticipation) avant l'aspiration : la capture « claque ».
	Animate.run(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
		Animate.scale(model, Animate.lerp(1, 0.82, a))
		model:PivotTo(start * C(0, -0.25 * a, 0))
	end)
	Animate.run(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		Animate.scale(model, Animate.lerp(0.82, 1.3, a))
		model:PivotTo(start * C(0, 0.6 * a, 0))
	end)
	start = model:GetPivot()
	local root = ownerRoot(ownerUserId)
	local target = if root then root.Position + Vector3.new(0, 1, 0) else start.Position + Vector3.new(0, 8, 0)
	if mine then
		Audio.play("Capture")
	end
	Animate.run(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		local position = start.Position:Lerp(target, a) + Vector3.new(0, math.sin(a * math.pi) * 4, 0)
		model:PivotTo(CFrame.new(position) * start.Rotation * CFrame.Angles(0, a * math.pi * 6, 0))
		Animate.scale(model, Animate.lerp(1.3, 0.06, a))
	end)
	burst(target, color, 26 + order * 10)
	if order >= 3 then
		ring(target - Vector3.new(0, 1, 0), color, 8 + order * 2, 0.45)
	end
	destroyCreature(creature)
	task.delay(1.4, function()
		PropTracker.show(creature.propId, 0.8)
	end)
end

local function fleeDirection(base: CFrame): Vector3
	local nearest: Vector3? = nil
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - base.Position).Magnitude
			if d < best then
				best = d
				nearest = root.Position
			end
		end
	end
	if nearest then
		local away = base.Position - nearest
		local flat = Vector3.new(away.X, 0, away.Z)
		if flat.Magnitude > 0.1 then
			return flat.Unit
		end
	end
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function fleeAnimation(creature: Creature)
	creature.animating = true
	creature.mode = "Leaving"
	creature.billboard.Enabled = false
	local species = MimicCatalog.get(creature.speciesId)
	local style = if species then species.behavior.fleeStyle else "Hop"
	local model = creature.model
	local base = model:GetPivot()
	local direction = fleeDirection(base)
	local facing = CFrame.lookAt(base.Position, base.Position + direction)
	Audio.playAt(model.PrimaryPart :: BasePart, "Escape")
	if style == "Dash" then
		Animate.run(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			model:PivotTo(facing * C(0, 0.3, -14 * a) * CFrame.Angles(math.rad(-15), 0, 0))
		end)
	elseif style == "Teleport" then
		Animate.linear(0.45, function()
			model:PivotTo(base * C((math.random() - 0.5) * 0.6, math.random() * 0.4, (math.random() - 0.5) * 0.6))
		end)
		burst(base.Position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 255, 230), 30)
	else
		for hop = 1, 3 do
			local from = facing * C(0, 0, -3.5 * (hop - 1))
			Animate.linear(0.32, function(_, t)
				model:PivotTo(
					from
						* C(0, math.sin(t * math.pi) * 2.6, -3.5 * t)
						* CFrame.Angles(0, math.sin(t * math.pi) * 0.4, 0)
				)
			end)
		end
	end
	local current = model:GetPivot()
	Animate.run(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		Animate.scale(model, Animate.lerp(1, 0.05, a))
		model:PivotTo(current * C(0, -a, 0))
	end)
	destroyCreature(creature)
	PropTracker.show(creature.propId, 0.8)
end

local function ensureCreature(info: ClientState.MimicInfo): Creature?
	local existing = creatures[info.mimicId]
	if existing then
		existing.info = info
		return existing
	end
	local speciesId = info.speciesId
	local species = if speciesId then MimicCatalog.get(speciesId) else nil
	local prop = PropTracker.get(info.propId)
	if species == nil or prop == nil or speciesId == nil then
		return nil
	end
	local variant = prop:GetAttribute("Variant")
	local model = MimicModelBuilder.build(speciesId, if type(variant) == "number" then variant else nil)
	local base = prop:GetPivot()
	model:PivotTo(base)
	model:SetAttribute("MimicId", info.mimicId)
	model.Parent = effects
	PropTracker.hide(info.propId)
	local anchor = PropBuilder.FaceAnchors[species.kind]
	local billboard, status = makeBillboard(model, species, anchor.height, base)
	local creature: Creature = {
		mimicId = info.mimicId,
		propId = info.propId,
		speciesId = speciesId,
		model = model,
		base = base,
		mode = info.state,
		animating = false,
		billboard = billboard,
		status = status,
		info = info,
	}
	creatures[info.mimicId] = creature
	task.spawn(revealAnimation, creature)
	return creature
end

local function onMimicChanged(info: ClientState.MimicInfo)
	local state = info.state
	local creature = creatures[info.mimicId]
	if state == "Revealed" or state == "Capturing" then
		local c = ensureCreature(info)
		if c then
			c.mode = state
			c.info = info
		end
	elseif state == "Captured" then
		if creature and creature.mode ~= "Leaving" then
			task.spawn(captureAnimation, creature, info.ownerUserId)
		end
	elseif state == "Fleeing" then
		if creature and creature.mode ~= "Leaving" then
			task.spawn(fleeAnimation, creature)
		end
	elseif state == "Hidden" then
		if creature and creature.mode ~= "Leaving" then
			destroyCreature(creature)
			PropTracker.show(info.propId, 0.5)
		elseif
			creature == nil
			and PropTracker.isHidden(info.propId)
			and ClientState.mimicAtProp(info.propId) == nil
		then
			PropTracker.show(info.propId, 0.5)
		end
	end
end

-- Animation d'attente (rebond) et de lutte (tremblement) des Mimics révélés.
local function idle()
	local t = os.clock()
	for _, creature in creatures do
		if creature.animating or creature.mode == "Leaving" or creature.model.Parent == nil then
			continue
		end
		local offset
		if creature.mode == "Capturing" then
			offset = C(
				(math.random() - 0.5) * 0.18,
				0.3 + math.abs(math.sin(t * 11)) * 0.35,
				(math.random() - 0.5) * 0.18
			) * CFrame.Angles(0, math.sin(t * 13) * 0.14, math.sin(t * 9) * 0.08)
		else
			offset = C(0, 0.3 + math.sin(t * 4) * 0.3, 0) * CFrame.Angles(0, math.sin(t * 1.7) * 0.25, 0)
		end
		creature.model:PivotTo(creature.base * offset)
		creature.status.Text = statusText(creature)
	end
end

function MimicVisuals.getModel(mimicId: string): Model?
	local creature = creatures[mimicId]
	return if creature then creature.model else nil
end

function MimicVisuals.mimicIdFromPart(part: Instance?): string?
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") then
			local id = current:GetAttribute("MimicId")
			if type(id) == "string" then
				return id
			end
		end
		current = current.Parent
	end
	return nil
end

function MimicVisuals.effectsFolder(): Folder
	return effects
end

-- Mémorise l'exemplaire obtenu pour la révélation (appelé sur CaptureResolved réussi).
function MimicVisuals.noteCapture(mimicId: string, specimen: any)
	pendingSpecimens[mimicId] = specimen
	task.delay(10, function()
		if pendingSpecimens[mimicId] == specimen then
			pendingSpecimens[mimicId] = nil
		end
	end)
end

function MimicVisuals.start()
	effects = Instance.new("Folder")
	effects.Name = "MimicEffects"
	effects.Parent = workspace
	ClientState.MimicChanged:Connect(onMimicChanged)
	RunService.RenderStepped:Connect(idle)
end

MimicVisuals.burst = function(position: Vector3, color: Color3, amount: number)
	burst(position, color, amount)
end

MimicVisuals.partsOf = partsOf

return MimicVisuals
