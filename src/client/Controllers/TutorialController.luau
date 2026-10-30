--!strict
--[[
	TutorialController — un bandeau d'une phrase par étape, et un marqueur
	« ? » au-dessus de l'objet suspect quand le joueur doit l'examiner.
	Pas de dialogue, pas de menu bloquant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Animate = require(Client.Util.Animate)
local Theme = require(Client.UI.Theme)
local PropTracker = require(script.Parent.PropTracker)

local TutorialController = {}

local refs: any
local marker: BillboardGui? = nil
local bannerToken = 0

local function hint(step: string): string?
	local touch = refs.touch
	if step == "Scan" then
		return if touch
			then "Quelque chose cloche ici… Touche SCAN."
			else "Quelque chose cloche ici… Appuie sur [E] pour scanner."
	elseif step == "Inspect" then
		return if touch
			then "Un objet a bougé ! Approche-toi et touche-le pour l'examiner."
			else "Un objet a bougé ! Approche-toi et examine-le : [F] ou clic."
	elseif step == "Capture" then
		return "C'est un Mimic ! CAPTURER, puis IMPULSION quand le curseur est dans la zone verte."
	elseif step == "Done" then
		return "Bravo ! D'autres Mimics se cachent au Village, au Parc Étrange et à la Zone Commerciale."
	end
	return nil
end

local function setMarker(propId: string?, visible: boolean)
	if marker then
		marker:Destroy()
		marker = nil
	end
	if not visible or propId == nil then
		return
	end
	local prop = PropTracker.get(propId)
	local primary = prop and prop.PrimaryPart
	if primary == nil then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TutorialMarker"
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = primary
	Theme.text({
		Text = "?",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Yellow,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 56,
		TextStrokeTransparency = 0,
		Parent = gui,
	})
	gui.Parent = primary
	marker = gui
end

local function apply(step: string, propId: string?)
	ClientState.tutorialStep = step
	ClientState.tutorialPropId = propId
	ClientState.TutorialChanged:Fire(step, propId)
	local text = hint(step)
	local banner = refs.banner :: Frame
	bannerToken += 1
	local token = bannerToken
	if text then
		refs.bannerText.Text = text
		banner.Visible = true
		banner.BackgroundTransparency = 0.6
		Animate.tween(banner, 0.3, { BackgroundTransparency = 0.12 })
	end
	if step == "Done" then
		task.delay(7, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end
	setMarker(propId, step == "Inspect")
end

function TutorialController.start(hudRefs: any)
	refs = hudRefs
	local firstUpdate = true
	Remotes.get("TutorialUpdate").OnClientEvent:Connect(function(payload)
		-- Un joueur qui a déjà fini le tutoriel ne revoit pas le message final.
		if firstUpdate and payload.step == "Done" then
			firstUpdate = false
			ClientState.tutorialStep = "Done"
			return
		end
		firstUpdate = false
		apply(payload.step, payload.propId)
	end)
	-- Le marqueur disparaît pendant que le Mimic est révélé.
	ClientState.MimicChanged:Connect(function()
		if ClientState.tutorialStep == "Inspect" then
			local propId = ClientState.tutorialPropId
			setMarker(propId, propId ~= nil and not PropTracker.isHidden(propId))
		end
	end)
end

return TutorialController
