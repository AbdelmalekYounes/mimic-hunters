--!strict
--[[
	HuntController — Museum Hunt côté client (V0.3).

	- Panneau « MUSEUM HUNT » d'un musée : lance le défi (le serveur vérifie tout).
	- Pendant le défi : barre d'état (trouvés, temps, ratés) à la place du bandeau ; le
	  scanner (E) et l'examen (F, clic, toucher) sont ceux du jeu, routés vers le défi par
	  le serveur ; indices des copies joués par MimicVisuals.
	- Copie trouvée : courte révélation (l'apparence exacte de l'exemplaire du propriétaire),
	  puis elle disparaît : ce n'est qu'une copie, le vrai Mimic reste dans sa vitrine.
	- Fin : carte de résultat (score, record, musées différents visités).
	- Propriétaire : prévenu quand quelqu'un relève le défi chez lui.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Objectives = require(Shared.Config.Objectives)
local Rarities = require(Shared.Config.Rarities)
local MimicModelBuilder = require(Shared.Builders.MimicModelBuilder)
local HudLayout = require(Shared.Logic.HudLayout)
local SpecimenLook = require(Shared.Logic.SpecimenLook)
local Remotes = require(Shared.Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Audio = require(Client.Util.Audio)
local MutationFx = require(Client.Util.MutationFx)
local Theme = require(Client.UI.Theme)
local MimicVisuals = require(script.Parent.MimicVisuals)

local C = Theme.Colors

local HuntController = {}

local refs: any
local status: any = {}
local result: any = {}
local active: any = nil -- { huntId, total, found, misses, endsAt }
local resultToken = 0

local REFUSALS: { [string]: string } = {
	OwnMuseum = "C'est ton musée : invite un ami à relever le défi !",
	Busy = "Un autre visiteur relève déjà le défi ici. Réessaie dans un instant.",
	OutOfRange = "Approche-toi du panneau MUSEUM HUNT.",
	EmptyMuseum = "Ce musée n'expose encore aucun Mimic : rien à cacher.",
	AlreadyHunting = "Termine d'abord ton défi en cours.",
	ProfileUnavailable = "Ton profil n'est pas encore sauvegardable : défi impossible pour l'instant.",
	UnknownMuseum = "Ce musée n'est plus disponible.",
	RateLimited = "Un instant…",
}

local CANCELS: { [string]: string } = {
	OwnerLeft = "Le propriétaire est parti : défi annulé (son musée a fermé).",
	VisitorLeft = "Défi annulé.",
	LeftZone = "Tu as quitté le jardin : défi annulé.",
}

local function nameOf(userId: number?): string
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	return if player then player.DisplayName else "Un visiteur"
end

-- ─── Interface ─────────────────────────────────────────────────────────

local function build(gui: ScreenGui)
	status.frame = Theme.panel({
		Name = "HuntStatus",
		Visible = false,
		BackgroundColor3 = Color3.fromRGB(70, 36, 96),
		Parent = gui,
	})
	Theme.padding(6).Parent = status.frame
	status.text = Theme.text({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 20,
		Parent = status.frame,
	})

	result.frame = Theme.panel({
		Name = "HuntResult",
		Visible = false,
		ZIndex = 18,
		BackgroundColor3 = Color3.fromRGB(32, 22, 52),
		BackgroundTransparency = 0.02,
		Parent = gui,
	})
	result.scale = Theme.create("UIScale", { Scale = 1, Parent = result.frame }) :: UIScale
	local list = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 10),
		Parent = result.frame,
	}) :: Frame
	Theme.create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local function line(name: string, order: number, font: Enum.Font, size: number, color: Color3): TextLabel
		return Theme.text({
			Name = name,
			Text = "",
			LayoutOrder = order,
			Font = font,
			TextColor3 = color,
			Size = UDim2.new(1, 0, 0, size),
			MaxTextSize = size,
			Parent = list,
		})
	end
	result.title = line("Title", 1, Theme.Fonts.Title, 26, C.Pink)
	result.score = line("Score", 2, Theme.Fonts.Title, 40, C.Yellow)
	result.detail = line("Detail", 3, Theme.Fonts.Bold, 17, C.Text)
	result.record = line("Record", 4, Theme.Fonts.Bold, 17, C.Mint)
	result.museums = line("Museums", 5, Theme.Fonts.Body, 15, C.Muted)
	result.close = Theme.button({
		Name = "Close",
		Text = "OK",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(120, 40),
		BackgroundColor3 = Color3.fromRGB(60, 110, 90),
		StrokeColor = C.Mint,
		Parent = result.frame,
	})
	result.close.Activated:Connect(function()
		result.frame.Visible = false
	end)

	local function place()
		local size = gui.AbsoluteSize
		if size.X < 2 then
			return
		end
		local layout = HudLayout.compute(size.X, size.Y, refs.touch)
		-- Barre d'état à la place du bandeau (masqué pendant le défi).
		local b = layout.banner
		status.frame.Position = UDim2.fromOffset(b.x, b.y)
		status.frame.Size = UDim2.fromOffset(b.w, b.h)
		local p = layout.panel
		local w, h = math.min(p.w, 420), math.min(p.h, 270)
		result.frame.Position = UDim2.fromOffset(p.x + (p.w - w) / 2, p.y + (p.h - h) / 2)
		result.frame.Size = UDim2.fromOffset(w, h)
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

local function refreshStatus()
	local a = active
	if a == nil then
		return
	end
	local remaining = math.max(0, math.ceil(a.endsAt - os.clock()))
	status.text.Text = string.format(
		"MUSEUM HUNT  ·  %d/%d trouvés  ·  %d:%02d%s",
		a.found,
		a.total,
		remaining // 60,
		remaining % 60,
		if a.misses > 0 then string.format("  ·  %d raté%s", a.misses, if a.misses > 1 then "s" else "") else ""
	)
end

local function setActive(value: any)
	active = value
	status.frame.Visible = value ~= nil
	-- Le bandeau du tutoriel laisse la place à la barre du défi, puis revient.
	if value then
		status.bannerWasVisible = refs.banner.Visible
		refs.banner.Visible = false
		refreshStatus()
	elseif status.bannerWasVisible ~= nil then
		refs.banner.Visible = status.bannerWasVisible and ClientState.tutorialStep ~= "Done"
		status.bannerWasVisible = nil
	end
end

-- Copie trouvée : la créature jaillit de sa cachette, puis s'évapore (≈ 1,2 s).
local function reveal(payload: any)
	local copy = payload.copy
	local species = copy and MimicCatalog.get(copy.speciesId)
	local position = payload.position
	if species == nil or position == nil then
		return
	end
	local look = SpecimenLook.compute(species, copy.seed, copy.mutation)
	local model = MimicModelBuilder.build(species.id, nil, look)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	local base = CFrame.new(position.X, 0, position.Z)
	model:PivotTo(base)
	model.Parent = MimicVisuals.effectsFolder()
	MutationFx.attach(model, look)
	local rarity = Rarities.get(species.rarity)
	local color = if rarity then Theme.rgb(rarity.color) else C.Mint
	MimicVisuals.burst(base.Position + Vector3.new(0, 2, 0), color, 30)
	Audio.play("Reveal", 1.2)
	task.spawn(function()
		Animate.run(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a, raw)
			Animate.scale(model, math.max(0.05, a))
			model:PivotTo(
				base * CFrame.new(0, math.sin(raw * math.pi) * 2.5, 0) * CFrame.Angles(0, raw * math.pi * 2, 0)
			)
		end)
		task.wait(0.4)
		Animate.run(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			Animate.scale(model, math.max(0.05, 1 - a))
		end)
		MimicVisuals.burst(base.Position + Vector3.new(0, 2, 0), Color3.fromRGB(230, 220, 255), 12)
		model:Destroy()
	end)
end

local function showResult(payload: any)
	resultToken += 1
	local token = resultToken
	result.title.Text = if payload.reason == "Complete" then "MUSEUM HUNT RÉUSSIE !" else "TEMPS ÉCOULÉ"
	result.score.Text = string.format("%d points", payload.score or 0)
	result.detail.Text = string.format(
		"%d / %d Mimics trouvés%s%s",
		payload.found or 0,
		payload.total or 0,
		if (payload.misses or 0) > 0
			then string.format("  ·  %d raté%s", payload.misses, if payload.misses > 1 then "s" else "")
			else "",
		if (payload.bonus or 0) > 0 then string.format("  ·  bonus temps +%d", payload.bonus) else ""
	)
	result.record.Text = if payload.newRecord
		then "Nouveau record personnel !"
		else string.format("Record personnel : %d", payload.best or 0)
	result.museums.Text = string.format(
		"Musées différents explorés : %d%s",
		payload.museums or 0,
		if payload.newMuseum then " (nouveau !)" else ""
	)
	result.frame.Visible = true
	result.scale.Scale = 0.6
	Animate.tween(result.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Audio.play("Capture", if payload.newRecord then 1.4 else 1.1)
	task.delay(7, function()
		if token == resultToken then
			result.frame.Visible = false
		end
	end)
end

-- ─── Événements du serveur ─────────────────────────────────────────────

local function onUpdate(payload: any)
	local phase = payload.phase
	if phase == "refused" then
		local message = REFUSALS[payload.reason]
		if payload.reason == "Cooldown" and type(payload.remaining) == "number" then
			message = string.format("Encore %d s avant un nouveau défi.", math.ceil(payload.remaining))
		end
		if message then
			ClientState.toast(message)
		end
	elseif phase == "start" then
		setActive({
			huntId = payload.huntId,
			total = payload.total,
			found = 0,
			misses = 0,
			endsAt = os.clock() + (payload.remaining or 75),
		})
		Audio.play("Reveal", 0.9)
		ClientState.toast(
			string.format(
				"Trouve les %d Mimics cachés ! Scanne (E) puis examine (F) les objets du jardin.",
				payload.total
			),
			"mimic"
		)
	elseif phase == "found" then
		if active and active.huntId == payload.huntId then
			active.found = payload.found
			refreshStatus()
		end
		reveal(payload)
		local species = payload.copy and MimicCatalog.get(payload.copy.speciesId)
		ClientState.toast(string.format("Trouvé : %s !", if species then species.name else "un Mimic"), "mimic")
	elseif phase == "miss" then
		if active and active.huntId == payload.huntId then
			active.misses = payload.misses
			refreshStatus()
		end
	elseif phase == "end" then
		setActive(nil)
		showResult(payload)
		if payload.summary then
			ClientState.applyCollectionDelta({ summary = payload.summary })
		end
		for _, id in payload.completed or {} do
			for _, objective in Objectives.list() do
				if objective.id == id then
					ClientState.toast(
						string.format(
							"Objectif « %s » atteint : %s !",
							objective.title,
							Objectives.rewardText(objective)
						),
						"mimic"
					)
				end
			end
		end
	elseif phase == "cancel" then
		setActive(nil)
		ClientState.toast(CANCELS[payload.reason] or "Défi annulé.")
	elseif phase == "visitorStart" then
		ClientState.toast(
			string.format("%s relève la Museum Hunt de ton musée !", nameOf(payload.visitorId)),
			"mimic"
		)
	elseif phase == "visitorEnd" then
		ClientState.toast(
			string.format(
				"%s a trouvé %d/%d Mimics chez toi (score %d).",
				nameOf(payload.visitorId),
				payload.found,
				payload.total,
				payload.score
			)
		)
	end
end

-- Lance le défi du musée dont le panneau a été activé (ou d'un propriétaire donné).
function HuntController.start(ownerUserId: number)
	Audio.play("UiClick")
	Remotes.get("StartMuseumHunt"):FireServer(ownerUserId)
end

function HuntController.active(): any
	return active
end

function HuntController.ui(): any
	return { status = status, result = result }
end

function HuntController.init(hudRefs: any)
	refs = hudRefs
	build(refs.gui)
	Remotes.get("HuntUpdate").OnClientEvent:Connect(onUpdate)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "HuntPrompt" then
			return
		end
		local museum = prompt.Parent and prompt.Parent.Parent
		local owner = museum and museum:GetAttribute("OwnerUserId")
		if type(owner) == "number" then
			HuntController.start(owner)
		else
			ClientState.toast("Cette parcelle est libre : aucun musée à explorer.")
		end
	end)
	RunService.Heartbeat:Connect(function()
		if active then
			refreshStatus()
		end
	end)
end

return HuntController
