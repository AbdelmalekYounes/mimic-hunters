--!strict
--[[
	CaptureController — affichage et commandes du minijeu de capture.

	Le curseur est calculé avec la même fonction que le serveur
	(CaptureMinigame.cursorAt). Le client envoie seulement son temps écoulé
	depuis le début de l'étape ; le serveur décide si c'est réussi.
	Commandes : Espace, clic gauche, bouton A (manette) ou bouton IMPULSION.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaptureMinigame = require(Shared.Logic.CaptureMinigame)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Rarities = require(Shared.Config.Rarities)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local Theme = require(Client.UI.Theme)

type Active = {
	attemptId: string,
	speciesId: string,
	stage: CaptureMinigame.Stage,
	stageStart: number,
	startedAt: number,
	timeout: number,
	hitsRequired: number,
	maxMisses: number,
	hits: number,
	misses: number,
	minElapsed: number,
	waitingSince: number?,
	resolved: boolean,
}

local CaptureController = {}

local refs: any
local active: Active? = nil
local feedbackToken = 0

local PULSE_ACTION = "MH_Pulse"

local function pipsText(hits: number, required: number): string
	local parts = {}
	for i = 1, required do
		table.insert(parts, if i <= hits then "●" else "○")
	end
	return table.concat(parts, " ")
end

local function livesText(misses: number, maxMisses: number): string
	if maxMisses < 0 then
		return "∞"
	end
	local parts = {}
	for i = 1, maxMisses do
		table.insert(parts, if i <= maxMisses - misses then "♥" else "♡")
	end
	return table.concat(parts, " ")
end

local function setFeedback(text: string, color: Color3)
	local label = refs.feedback :: TextLabel
	label.Text = text
	label.TextColor3 = color
	feedbackToken += 1
	local token = feedbackToken
	task.delay(0.9, function()
		if token == feedbackToken then
			label.Text = ""
		end
	end)
end

local function layoutStage(stage: CaptureMinigame.Stage)
	local zone = refs.zone :: Frame
	zone.Size = UDim2.fromScale(stage.width, 0.8)
	zone.Position = UDim2.fromScale(stage.center, 0.5)
	zone.BackgroundTransparency = 0.6
	Animate.tween(zone, 0.2, { BackgroundTransparency = 0.15 })
end

local function refreshCounters(a: Active)
	refs.pips.Text = pipsText(a.hits, a.hitsRequired)
	refs.lives.Text = livesText(a.misses, a.maxMisses)
end

local function pulse()
	local a = active
	if a == nil or a.resolved then
		return
	end
	local now = os.clock()
	if a.waitingSince and now - a.waitingSince < 1 then
		return
	end
	local elapsed = now - a.stageStart
	if elapsed < a.minElapsed then
		return
	end
	a.waitingSince = now
	Remotes.get("SubmitPulse"):FireServer(a.attemptId, elapsed)
	local cursor = refs.cursor :: Frame
	cursor.Size = UDim2.new(0, 14, 1, 22)
	Animate.tween(cursor, 0.15, { Size = UDim2.new(0, 8, 1, 14) })
end

local function bindInput()
	ContextActionService:BindActionAtPriority(
		PULSE_ACTION,
		function(_, state)
			if state == Enum.UserInputState.Begin then
				pulse()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 50,
		Enum.KeyCode.Space,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
end

local function finish(success: boolean)
	ContextActionService:UnbindAction(PULSE_ACTION)
	local a = active
	if a then
		a.resolved = true
	end
	task.delay(if success then 0.5 else 0.8, function()
		if active == a then
			active = nil
			refs.capture.Visible = false
			ClientState.attemptActive = false
			ClientState.AttemptChanged:Fire(false)
		end
	end)
end

local function onCaptureStarted(payload: any)
	if not payload.ok then
		return
	end
	local species = MimicCatalog.get(payload.speciesId)
	local rarity = species and Rarities.get(species.rarity)
	active = {
		attemptId = payload.attemptId,
		speciesId = payload.speciesId,
		stage = payload.stage,
		stageStart = os.clock(),
		startedAt = os.clock(),
		timeout = payload.timeout,
		hitsRequired = payload.hitsRequired,
		maxMisses = payload.maxMisses,
		hits = 0,
		misses = 0,
		minElapsed = payload.minStageElapsed or 0.25,
		waitingSince = nil,
		resolved = false,
	}
	local a = active :: Active
	refs.captureTitle.Text = string.format("Stabilise %s !", if species then species.name else "le Mimic")
	refs.captureTitle.TextColor3 = if rarity then Theme.rgb(rarity.color) else Theme.Colors.Text
	refs.feedback.Text = if refs.touch
		then "Touche IMPULSION dans la zone verte"
		else "Appuie quand le curseur est dans la zone verte"
	refs.feedback.TextColor3 = Theme.Colors.Muted
	refreshCounters(a)
	layoutStage(a.stage)
	refs.capture.Visible = true
	ClientState.attemptActive = true
	ClientState.AttemptChanged:Fire(true)
	bindInput()
end

local function onPulseResult(payload: any)
	local a = active
	if a == nil or payload.attemptId ~= a.attemptId then
		return
	end
	a.waitingSince = nil
	if not payload.ok then
		if payload.reason == "OutOfRange" then
			setFeedback("Reste près du Mimic !", Theme.Colors.Yellow)
		end
		return
	end
	a.hits = payload.hits
	a.misses = payload.misses
	refreshCounters(a)
	if payload.hit then
		Audio.play("PulseHit", 1 + a.hits * 0.15)
		setFeedback(if a.hits >= a.hitsRequired then "STABILISÉ !" else "PARFAIT !", Theme.Colors.Mint)
	else
		Audio.play("PulseMiss")
		setFeedback("RATÉ !", Theme.Colors.Red)
	end
	if payload.stage then
		a.stage = payload.stage
		a.stageStart = os.clock()
		layoutStage(a.stage)
	end
end

local function onCaptureResolved(payload: any)
	local a = active
	if a == nil or payload.attemptId ~= a.attemptId then
		return
	end
	if payload.success then
		finish(true)
	else
		local message = if payload.reason == "Timeout"
			then "Trop lent ! Le Mimic s'est enfui."
			else "Le Mimic s'est échappé ! Retrouve-le."
		setFeedback("ÉCHAPPÉ !", Theme.Colors.Red)
		ClientState.toast(message)
		Audio.play("Escape")
		finish(false)
	end
end

local function render()
	local a = active
	if a == nil then
		return
	end
	local now = os.clock()
	local elapsed = if a.resolved then 0 else now - a.stageStart
	local position = CaptureMinigame.cursorAt(a.stage, elapsed)
	refs.cursor.Position = UDim2.fromScale(position, 0.5)
	local inZone = CaptureMinigame.isHit(a.stage, position, 0)
	refs.cursor.BackgroundColor3 = if inZone then Theme.Colors.Mint else Color3.new(1, 1, 1)
	refs.timerFill.Size = UDim2.fromScale(math.clamp(1 - (now - a.startedAt) / a.timeout, 0, 1), 1)
end

function CaptureController.start(hudRefs: any)
	refs = hudRefs
	refs.pulseButton.Activated:Connect(pulse)
	Remotes.get("CaptureStarted").OnClientEvent:Connect(onCaptureStarted)
	Remotes.get("PulseResult").OnClientEvent:Connect(onPulseResult)
	Remotes.get("CaptureResolved").OnClientEvent:Connect(onCaptureResolved)
	RunService.RenderStepped:Connect(render)
end

return CaptureController
