--!strict
--[[
	CaptureMinigame — logique pure de la jauge de capture.

	Le curseur fait des allers-retours sur [0, 1] :
		u   = (phase + elapsed * speed) mod 2
		pos = u si u <= 1, sinon 2 - u
	Le client utilise `cursorAt` pour l'affichage ; le serveur l'utilise pour
	juger chaque impulsion. Le client n'envoie que son temps écoulé depuis le
	début de l'étape. Le serveur borne ce temps dans une fenêtre de latence
	[serverElapsed - allowance, serverElapsed] avant d'évaluer le résultat :
	un client ne peut donc pas « choisir » un instant arbitraire.
]]

export type Difficulty = {
	speed: number,
	zoneWidth: number,
	speedUp: number,
	shrink: number,
}

export type Stage = {
	index: number,
	speed: number,
	center: number,
	width: number,
	phase: number,
}

export type AttemptStatus = "Active" | "Succeeded" | "Failed" | "Expired"

export type Attempt = {
	id: string,
	userId: number,
	mimicId: string,
	speciesId: string,
	slotId: string,
	personal: boolean,
	difficulty: Difficulty,
	createdAt: number,
	expiresAt: number,
	stage: Stage,
	stageStartedAt: number,
	hits: number,
	misses: number,
	pulses: number,
	hitsRequired: number,
	maxMisses: number?, -- nil = illimité (tutoriel)
	lastPulseAt: number,
	status: AttemptStatus,
}

export type PulseConfig = {
	MinPulseInterval: number,
	MinStageElapsed: number,
	HitTolerance: number,
	MaxPulses: number,
}

export type PulseResult = {
	accepted: boolean,
	reason: string?,
	hit: boolean?,
	position: number?,
	hits: number,
	misses: number,
	status: AttemptStatus,
	stage: Stage?,
}

local CaptureMinigame = {}

function CaptureMinigame.cursorAt(stage: Stage, elapsed: number): number
	local u = (stage.phase + math.max(elapsed, 0) * stage.speed) % 2
	if u <= 1 then
		return u
	end
	return 2 - u
end

function CaptureMinigame.isHit(stage: Stage, position: number, tolerance: number): boolean
	return math.abs(position - stage.center) <= stage.width / 2 + tolerance
end

function CaptureMinigame.makeStage(difficulty: Difficulty, index: number, rng: any): Stage
	local step = index - 1
	local width = math.clamp(difficulty.zoneWidth * (1 - difficulty.shrink) ^ step, 0.06, 0.6)
	local speed = difficulty.speed * (1 + difficulty.speedUp) ^ step
	local margin = width / 2 + 0.05
	local center = rng:nextRange(margin, 1 - margin)
	-- La phase place le curseur à une extrémité, loin de la zone, pour éviter
	-- un succès « gratuit » dès l'apparition de l'étape.
	local phase = if center > 0.5 then 0 else 1
	return {
		index = index,
		speed = speed,
		center = center,
		width = width,
		phase = phase,
	}
end

function CaptureMinigame.newAttempt(args: {
	id: string,
	userId: number,
	mimicId: string,
	speciesId: string,
	slotId: string,
	personal: boolean,
	difficulty: Difficulty,
	now: number,
	timeout: number,
	hitsRequired: number,
	maxMisses: number?,
	rng: any,
}): Attempt
	return {
		id = args.id,
		userId = args.userId,
		mimicId = args.mimicId,
		speciesId = args.speciesId,
		slotId = args.slotId,
		personal = args.personal,
		difficulty = args.difficulty,
		createdAt = args.now,
		expiresAt = args.now + args.timeout,
		stage = CaptureMinigame.makeStage(args.difficulty, 1, args.rng),
		stageStartedAt = args.now,
		hits = 0,
		misses = 0,
		pulses = 0,
		hitsRequired = args.hitsRequired,
		maxMisses = args.maxMisses,
		lastPulseAt = -math.huge,
		status = "Active",
	}
end

-- Marque la tentative comme expirée si son délai est dépassé.
function CaptureMinigame.checkExpiry(attempt: Attempt, now: number): boolean
	if attempt.status == "Active" and now > attempt.expiresAt then
		attempt.status = "Expired"
		return true
	end
	return false
end

local function result(attempt: Attempt, accepted: boolean, reason: string?): PulseResult
	return {
		accepted = accepted,
		reason = reason,
		hits = attempt.hits,
		misses = attempt.misses,
		status = attempt.status,
	}
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -1e6 and value < 1e6
end

--[[
	Évalue une impulsion. `claimedElapsed` vient du client et n'est qu'un
	indice : il est borné par la fenêtre de latence calculée côté serveur.
]]
function CaptureMinigame.evaluatePulse(
	attempt: Attempt,
	claimedElapsed: any,
	now: number,
	allowance: number,
	config: PulseConfig,
	rng: any
): PulseResult
	if attempt.status ~= "Active" then
		return result(attempt, false, "Resolved")
	end
	if CaptureMinigame.checkExpiry(attempt, now) then
		return result(attempt, false, "Expired")
	end
	if not isFinite(claimedElapsed) then
		return result(attempt, false, "BadInput")
	end

	local serverElapsed = now - attempt.stageStartedAt
	if serverElapsed < config.MinStageElapsed then
		return result(attempt, false, "TooEarly")
	end
	if now - attempt.lastPulseAt < config.MinPulseInterval then
		return result(attempt, false, "TooFast")
	end

	local effective = math.clamp(claimedElapsed :: number, serverElapsed - math.max(allowance, 0), serverElapsed)
	local position = CaptureMinigame.cursorAt(attempt.stage, effective)
	local hit = CaptureMinigame.isHit(attempt.stage, position, config.HitTolerance)

	attempt.pulses += 1
	attempt.lastPulseAt = now

	if hit then
		attempt.hits += 1
	else
		attempt.misses += 1
	end

	if attempt.hits >= attempt.hitsRequired then
		attempt.status = "Succeeded"
	elseif (attempt.maxMisses ~= nil and attempt.misses >= attempt.maxMisses) or attempt.pulses >= config.MaxPulses then
		attempt.status = "Failed"
	end

	local out = result(attempt, true, nil)
	out.hit = hit
	out.position = position

	if attempt.status == "Active" then
		-- Chaque impulsion acceptée relance une étape : la ligne de temps
		-- client/serveur est resynchronisée à chaque échange.
		attempt.stage = CaptureMinigame.makeStage(attempt.difficulty, attempt.hits + 1, rng)
		attempt.stageStartedAt = now
		out.stage = attempt.stage
	end
	return out
end

-- Copie sérialisable d'une étape pour le réseau.
function CaptureMinigame.publicStage(stage: Stage): Stage
	return {
		index = stage.index,
		speed = stage.speed,
		center = stage.center,
		width = stage.width,
		phase = stage.phase,
	}
end

return CaptureMinigame
