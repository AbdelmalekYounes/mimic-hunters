--!strict
--[[
	MIMIC HUNTERS — point d'entrée client.
	Construit l'interface, démarre les contrôleurs, puis signale au serveur
	que le client est prêt à recevoir l'état du monde.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)

local ClientState = require(script.ClientState)
local Hud = require(script.UI.Hud)
local Theme = require(script.UI.Theme)
local PropTracker = require(script.Controllers.PropTracker)
local MimicVisuals = require(script.Controllers.MimicVisuals)
local ScannerController = require(script.Controllers.ScannerController)
local CaptureController = require(script.Controllers.CaptureController)
local CollectionController = require(script.Controllers.CollectionController)
local TutorialController = require(script.Controllers.TutorialController)

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

Remotes.get("ClientReady"):FireServer()
