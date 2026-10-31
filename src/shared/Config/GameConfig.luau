--!strict
--[[
	GameConfig — tous les réglages de gameplay.

	Les distances sont en studs, les durées en secondes. Ces valeurs sont
	lues à la fois par le serveur (autorité) et par le client (affichage,
	prédiction). Le serveur ne fait jamais confiance aux valeurs du client :
	il applique toujours ses propres copies de ces constantes.
]]

local GameConfig = {
	Version = "0.2.0",

	Hunt = {
		-- Nombre de Mimics partagés cachés simultanément dans le monde.
		ActiveMimics = 12,
		-- Chaque zone garde au moins ce nombre de Mimics (serveur peu peuplé).
		MinPerZone = 3,
		-- Délai avant qu'un nouveau Mimic remplace un Mimic capturé.
		RespawnDelay = 5,
		-- Un emplacement libéré ne peut pas être réoccupé tout de suite.
		SlotReuseDelay = 10,
		-- Durée de l'animation de fuite avant que le Mimic se recache ailleurs.
		FleeDuration = 2.2,
		-- Temps laissé au joueur qui a révélé un Mimic pour lancer la capture.
		RevealClaimDuration = 8,
	},

	Scanner = {
		Cooldown = 3,
		-- Au-delà de cette portée, le scanner ne capte rien.
		SignalRange = 45,
		-- Les Mimics dans ce rayon « sursautent » (indice fort) pour le scanneur.
		FlinchRange = 18,
		StrongBand = 14,
		MediumBand = 28,
	},

	Inspect = {
		Range = 14,
		VerticalTolerance = 20,
		Cooldown = 0.5,
		-- Examiner un objet ordinaire coûte un peu plus de temps.
		MissCooldown = 1.2,
	},

	Clues = {
		-- Les indices ne sont envoyés qu'aux joueurs à moins de cette distance.
		BroadcastRange = 60,
	},

	Capture = {
		Range = 22,
		-- Tolérance de distance pendant le minijeu (le joueur peut bouger un peu).
		PulseRange = 34,
		HitsRequired = 2,
		MaxMisses = 2,
		AttemptTimeout = 14,
		MinPulseInterval = 0.2,
		-- Délai minimal après le début d'une étape avant d'accepter une impulsion.
		MinStageElapsed = 0.25,
		HitTolerance = 0.015,
		MaxPulses = 12,
		-- Compensation de latence : fenêtre de temps acceptée pour l'horodatage client.
		LatencyBase = 0.08,
		LatencyMin = 0.12,
		LatencyMax = 0.4,
	},

	Tutorial = {
		SpeciesId = "chairy",
		SlotId = "TUTO",
		ClueIntervalMin = 2.5,
		ClueIntervalMax = 3.5,
		ClaimDuration = 30,
		AttemptTimeout = 45,
		Difficulty = {
			speed = 0.55,
			zoneWidth = 0.34,
			speedUp = 0.1,
			shrink = 0.1,
		},
	},

	-- Seaux à jetons anti-spam par joueur et par action.
	RateLimits = {
		Ready = { capacity = 2, refillPerSecond = 0.2 },
		Scan = { capacity = 3, refillPerSecond = 1 },
		Inspect = { capacity = 6, refillPerSecond = 4 },
		Capture = { capacity = 4, refillPerSecond = 2 },
		Pulse = { capacity = 6, refillPerSecond = 5 },
		-- Favoris, cosmétiques, réglages.
		Collection = { capacity = 8, refillPerSecond = 3 },
	},

	-- Sauvegardes (voir ProfileService pour le détail des délais).
	Save = {
		-- Expérience publiée.
		StoreName = "MimicHunters_Profiles_v2",
		-- Studio : stockage distinct, pour ne jamais écraser les profils du jeu publié.
		StudioStoreName = "MimicHunters_Profiles_v2_STUDIO",
		-- Nouvelle tentative de chargement quand le profil était indisponible ou verrouillé.
		ReloadRetryInterval = 30,
	},

	Player = {
		WalkSpeed = 18,
	},
}

return GameConfig
