--!strict
--[[
	Sounds — sons de la V0.1.

	Uniquement des sons livrés avec le client Roblox (rbxasset://), pour ne
	dépendre d'aucun asset externe. La variété « étrange » vient de la hauteur
	(PlaybackSpeed). Si un fichier est absent d'une version du client, Roblox
	journalise un avertissement et le jeu continue sans ce son.
	Vérifié dans Studio le 30/10/2026 : swoosh.wav n'est pas disponible (retiré).
]]

export type SoundSpec = { id: string, volume: number, speed: number }

local Sounds: { [string]: SoundSpec } = {
	Scan = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.0 },
	ScanHit = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.5 },
	Ordinary = { id = "rbxasset://sounds/button.wav", volume = 0.4, speed = 0.8 },
	Reveal = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 0.6 },
	PulseHit = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 2.0 },
	PulseMiss = { id = "rbxasset://sounds/button.wav", volume = 0.6, speed = 0.5 },
	Capture = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 0.75 },
	Escape = { id = "rbxasset://sounds/button.wav", volume = 0.7, speed = 0.45 },
	ClueCreak = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, speed = 0.45 },
	ClueChomp = { id = "rbxasset://sounds/snap.wav", volume = 0.6, speed = 0.7 },
	ClueHum = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35, speed = 0.35 },
	UiClick = { id = "rbxasset://sounds/button.wav", volume = 0.3, speed = 1.2 },
}

return Sounds
