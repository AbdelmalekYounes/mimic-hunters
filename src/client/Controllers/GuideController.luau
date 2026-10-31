--!strict
--[[
	GuideController — guide de première session après le tutoriel (V0.3.1, jalon 6).

	Le tutoriel apprend à scanner, examiner et capturer. Ensuite, rien n'amenait le joueur vers
	sa collection, son musée et les visites. Ce guide affiche UNE consigne à la fois dans le
	bandeau du tutoriel, déduite de la progression réelle (aucune donnée sauvegardée en plus) :

	  1. « Ouvre ta collection »        tant que le panneau n'a pas été ouvert (session) ;
	  2. « Va dans ton musée (MA BASE) » tant qu'aucun Mimic n'est exposé ;
	  3. « Remplis une vitrine »         dans son musée, tant qu'aucun Mimic n'est exposé ;
	  4. « Visite les autres musées »    une fois, après la première exposition.

	Jamais pendant une capture, une Museum Hunt ou avec le panneau ouvert. Vérifié une fois par
	seconde (coût négligeable).
]]

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local CollectionPanel = require(Client.UI.CollectionPanel)
local MuseumController = require(script.Parent.MuseumController)
local HuntController = require(script.Parent.HuntController)

local GuideController = {}

local refs: any
local openedCollection = false
local visitsShownAt: number? = nil
local current: string? = nil
-- Fin du tutoriel pendant cette session : son message de félicitations reste affiché 8 s.
local tutorialDoneAt = -math.huge

local function exhibitedCount(): number
	local summary = ClientState.summary
	local slots = summary and summary.museum and summary.museum.slots
	local count = 0
	for _, id in slots or {} do
		if type(id) == "string" and id ~= "" then
			count += 1
		end
	end
	return count
end

-- Consigne du moment, ou nil (rien à dire, ou ce n'est pas le moment).
function GuideController.hint(): string?
	local summary = ClientState.summary
	if ClientState.tutorialStep ~= "Done" or summary == nil or (summary.owned or 0) == 0 then
		return nil
	end
	if os.clock() - tutorialDoneAt < 8 then
		return nil
	end
	if CollectionPanel.isOpen() or HuntController.active() or ClientState.attemptActive then
		return nil
	end
	local touch = refs.touch
	if not openedCollection then
		return if touch
			then "Ton Mimic t'attend dans ta collection : touche CODEX."
			else "Ton Mimic t'attend dans ta collection : appuie sur [C]."
	end
	local exhibited = exhibitedCount()
	if exhibited == 0 then
		if MuseumController.inOwnMuseum() then
			return "Voici ton musée ! MA BASE ouvre l'onglet Musée : choisis une vitrine pour exposer un Mimic."
		end
		return if touch
			then "Expose tes Mimics dans ton musée personnel : touche MA BASE."
			else "Expose tes Mimics dans ton musée personnel : appuie sur [B] (MA BASE)."
	end
	if visitsShownAt == nil or os.clock() - visitsShownAt < 8 then
		visitsShownAt = visitsShownAt or os.clock()
		return "Bravo, ton musée est ouvert ! Visite celui des autres : onglet Visites de la collection."
	end
	return nil
end

local function update()
	if CollectionPanel.isOpen() then
		openedCollection = true
	end
	local text = GuideController.hint()
	local banner = refs.banner :: Frame
	if text then
		if current ~= text then
			current = text
			refs.bannerText.Text = text
		end
		banner.Visible = true
	elseif current ~= nil then
		-- Le guide ne masque que le bandeau qu'il a lui-même affiché.
		if refs.bannerText.Text == current and ClientState.tutorialStep == "Done" then
			banner.Visible = false
		end
		current = nil
	end
end

function GuideController.start(hudRefs: any)
	refs = hudRefs
	ClientState.TutorialChanged:Connect(function(step)
		if step == "Done" then
			tutorialDoneAt = os.clock()
		end
	end)
	task.spawn(function()
		-- Laisse le message de fin du tutoriel s'afficher d'abord.
		while Players.LocalPlayer.Parent do
			task.wait(1)
			local ok, err = pcall(function()
				update()
				return nil
			end)
			if not ok then
				warn("[Guide] " .. tostring(err))
			end
		end
	end)
end

-- Tests Studio : état du guide.
function GuideController.state(): any
	return { openedCollection = openedCollection, current = current, exhibited = exhibitedCount() }
end

return GuideController
