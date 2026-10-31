--!strict
--[[
	MIMIC HUNTERS — point d'entrée client.
	Construit l'interface, démarre les contrôleurs, puis signale au serveur
	que le client est prêt à recevoir l'état du monde.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Remotes = require(Shared.Net.Remotes)

local ClientState = require(script.ClientState)
local Hud = require(script.UI.Hud)
local Theme = require(script.UI.Theme)
local PropTracker = require(script.Controllers.PropTracker)
local MimicVisuals = require(script.Controllers.MimicVisuals)
local ScannerController = require(script.Controllers.ScannerController)
local CaptureController = require(script.Controllers.CaptureController)
local CollectionController = require(script.Controllers.CollectionController)
local TutorialController = require(script.Controllers.TutorialController)
local TitleController = require(script.Controllers.TitleController)

local refs = Hud.build()

ClientState.Toast:Connect(function(text: string, kind: string)
	Hud.toast(refs, text, if kind == "mimic" then Theme.Colors.Pink else nil)
end)

PropTracker.start()
MimicVisuals.start()
ScannerController.start(refs)
CaptureController.start(refs)
CollectionController.start(refs)
TutorialController.start(refs)
TitleController.start()

Remotes.get("MimicUpdate").OnClientEvent:Connect(function(payload)
	ClientState.applyUpdate(payload)
end)
Remotes.get("WorldSnapshot").OnClientEvent:Connect(function(payload)
	for _, mimic in payload.mimics do
		ClientState.applyUpdate(mimic)
	end
end)
Remotes.get("Clue").OnClientEvent:Connect(function(payload)
	MimicVisuals.playClue(payload.propId, payload.clue, payload.strong == true)
end)
Remotes.get("Notice").OnClientEvent:Connect(function(payload)
	ClientState.toast(tostring(payload.text))
end)
-- L'exemplaire obtenu arrive juste avant l'état « Captured » : la révélation peut l'utiliser.
Remotes.get("CaptureResolved").OnClientEvent:Connect(function(payload)
	if payload.success and payload.specimen then
		MimicVisuals.noteCapture(payload.mimicId, payload.specimen)
	end
end)
-- Capture rare d'un autre joueur : annoncée à tout le serveur.
Remotes.get("RareCapture").OnClientEvent:Connect(function(payload)
	if payload.userId == ClientState.userId then
		return
	end
	local who = Players:GetPlayerByUserId(payload.userId)
	local species = MimicCatalog.get(payload.speciesId)
	if who and species then
		ClientState.toast(
			string.format("%s a capturé un %s %s !", who.DisplayName, species.name, tostring(payload.mutation)),
			"mimic"
		)
	end
end)

-- État du profil : le joueur sait toujours si ses captures seront conservées.
local PROFILE_MESSAGES = {
	Unavailable = "Sauvegarde indisponible : captures en pause, nouvel essai dans 30 s.",
	Locked = "Ton profil est encore ouvert sur un autre serveur : captures en pause, nouvel essai bientôt.",
	FutureVersion = "Ton profil vient d'une version plus récente du jeu : captures désactivées ici.",
	Corrupt = "Profil illisible : captures désactivées pour protéger tes données.",
	Lost = "Profil ouvert ailleurs : captures arrêtées.",
}
Remotes.get("ProfileStatus").OnClientEvent:Connect(function(payload)
	local previous = ClientState.profileStatus
	ClientState.profileStatus = payload.status
	ClientState.ProfileStatusChanged:Fire(payload.status)
	local message = PROFILE_MESSAGES[payload.status]
	if message then
		ClientState.toast(message)
	elseif payload.status == "Ready" and previous ~= "Loading" and previous ~= "Ready" then
		ClientState.toast("Profil chargé : tes captures sont de nouveau sauvegardées.")
	end
end)

Remotes.get("ClientReady"):FireServer()
