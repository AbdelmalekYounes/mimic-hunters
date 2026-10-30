--!strict
--[[
	MIMIC HUNTERS — point d'entrée serveur.
	1. Ambiance lumineuse   2. Génération de la carte   3. Boucle de chasse
]]

local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)
local LightingSetup = require(script.Map.LightingSetup)
local MapBuilder = require(script.Map.MapBuilder)
local HuntServer = require(script.Services.HuntServer)

StarterPlayer.CharacterWalkSpeed = GameConfig.Player.WalkSpeed

local started = os.clock()
LightingSetup.apply()
local props = MapBuilder.build()
HuntServer.start()

local count = 0
for _ in props do
	count += 1
end
print(
	string.format(
		"[MimicHunters] v%s prêt : %d objets, carte générée en %.0f ms",
		GameConfig.Version,
		count,
		(os.clock() - started) * 1000
	)
)
