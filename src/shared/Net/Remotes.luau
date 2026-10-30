--!strict
--[[
	Remotes — noms et création des RemoteEvents.

	Client → serveur : demandes uniquement (jamais de résultat).
	Serveur → client : états et résultats décidés par le serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "MimicRemotes"

local Remotes = {}

Remotes.ClientToServer = table.freeze({
	"ClientReady",
	"RequestScan",
	"RequestInspect",
	"RequestCapture",
	"SubmitPulse",
})

Remotes.ServerToClient = table.freeze({
	"WorldSnapshot",
	"ScanResult",
	"InspectResult",
	"MimicUpdate",
	"CaptureStarted",
	"PulseResult",
	"CaptureResolved",
	"InventoryUpdate",
	"TutorialUpdate",
	"Clue",
	"Notice",
})

-- Serveur uniquement : crée le dossier et tous les RemoteEvents.
function Remotes.setup(): { [string]: RemoteEvent }
	assert(RunService:IsServer(), "Remotes.setup est réservé au serveur")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	assert(folder, "folder")
	local out = {}
	for _, list in { Remotes.ClientToServer, Remotes.ServerToClient } do
		for _, name in list do
			local remote = folder:FindFirstChild(name) :: RemoteEvent?
			if remote == nil then
				local created = Instance.new("RemoteEvent")
				created.Name = name
				created.Parent = folder
				remote = created
			end
			out[name] = remote :: RemoteEvent
		end
	end
	return out
end

-- Client : attend un RemoteEvent créé par le serveur.
function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
