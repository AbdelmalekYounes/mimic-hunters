--!strict
--[[
	MimicStateMachine — cycle de vie d'un Mimic côté serveur.

	    Disguised ──reveal──▶ Revealed ──startCapture──▶ Capturing ──complete──▶ Captured
	        ▲                    │ (délai)                   │ (échec / délai)
	        │                    ▼                           ▼
	        └──────settle──── Fleeing ◀──────────────────────┘

	- Revealed et Capturing sont verrouillés sur un seul joueur (`ownerId`).
	- Captured est terminal : le Mimic est retiré et remplacé plus tard.
	- Toutes les transitions sont synchrones (aucun yield) : sur le serveur
	  Luau, deux requêtes ne peuvent donc pas s'entrelacer au milieu d'une
	  transition. La première requête valide gagne, les autres échouent.
]]

export type State = "Disguised" | "Revealed" | "Capturing" | "Fleeing" | "Captured"

export type Record = {
	id: string,
	speciesId: string,
	slotId: string,
	state: State,
	ownerId: number?,
	attemptId: string?,
	stateUntil: number?,
	changedAt: number,
	revision: number,
	-- nil = Mimic partagé visible par tous ; userId = Mimic personnel (tutoriel).
	audience: number?,
	personal: boolean,
	nextClueAt: number,
}

local MimicStateMachine = {}

function MimicStateMachine.new(id: string, speciesId: string, slotId: string, now: number, audience: number?): Record
	return {
		id = id,
		speciesId = speciesId,
		slotId = slotId,
		state = "Disguised",
		ownerId = nil,
		attemptId = nil,
		stateUntil = nil,
		changedAt = now,
		revision = 0,
		audience = audience,
		personal = audience ~= nil,
		nextClueAt = now,
	}
end

local function setState(record: Record, state: State, now: number, untilTime: number?)
	record.state = state
	record.stateUntil = untilTime
	record.changedAt = now
	record.revision += 1
end

function MimicStateMachine.reveal(
	record: Record,
	userId: number,
	now: number,
	claimDuration: number
): (boolean, string?)
	if record.state ~= "Disguised" then
		return false, "WrongState"
	end
	record.ownerId = userId
	record.attemptId = nil
	setState(record, "Revealed", now, now + claimDuration)
	return true, nil
end

function MimicStateMachine.startCapture(
	record: Record,
	userId: number,
	attemptId: string,
	now: number,
	timeout: number
): (boolean, string?)
	if record.state ~= "Revealed" then
		return false, "WrongState"
	end
	if record.ownerId ~= userId then
		return false, "NotOwner"
	end
	if record.stateUntil ~= nil and now > record.stateUntil then
		return false, "Expired"
	end
	record.attemptId = attemptId
	setState(record, "Capturing", now, now + timeout)
	return true, nil
end

local function checkAttempt(record: Record, userId: number, attemptId: string): (boolean, string?)
	if record.state ~= "Capturing" then
		return false, "WrongState"
	end
	if record.ownerId ~= userId then
		return false, "NotOwner"
	end
	if record.attemptId ~= attemptId then
		return false, "AttemptMismatch"
	end
	return true, nil
end

function MimicStateMachine.completeCapture(
	record: Record,
	userId: number,
	attemptId: string,
	now: number
): (boolean, string?)
	local ok, err = checkAttempt(record, userId, attemptId)
	if not ok then
		return false, err
	end
	setState(record, "Captured", now, nil)
	return true, nil
end

function MimicStateMachine.failCapture(
	record: Record,
	userId: number,
	attemptId: string,
	now: number,
	fleeDuration: number
): (boolean, string?)
	local ok, err = checkAttempt(record, userId, attemptId)
	if not ok then
		return false, err
	end
	setState(record, "Fleeing", now, now + fleeDuration)
	return true, nil
end

-- Libère un Mimic verrouillé (délai dépassé, joueur parti) : il s'enfuit.
function MimicStateMachine.release(record: Record, now: number, fleeDuration: number): (boolean, string?)
	if record.state ~= "Revealed" and record.state ~= "Capturing" then
		return false, "WrongState"
	end
	setState(record, "Fleeing", now, now + fleeDuration)
	return true, nil
end

-- Fin de fuite : le Mimic se recache dans un emplacement (éventuellement nouveau).
function MimicStateMachine.settle(record: Record, slotId: string, now: number): (boolean, string?)
	if record.state ~= "Fleeing" then
		return false, "WrongState"
	end
	record.slotId = slotId
	record.ownerId = nil
	record.attemptId = nil
	setState(record, "Disguised", now, nil)
	return true, nil
end

--[[
	Fait avancer les délais. Retourne un événement à traiter par l'appelant :
	"ClaimExpired"   Revealed → Fleeing (déjà appliqué)
	"CaptureTimeout" Capturing a dépassé son délai (l'appelant clôt la tentative)
	"FleeFinished"   Fleeing terminé (l'appelant choisit l'emplacement et appelle settle)
]]
function MimicStateMachine.tick(record: Record, now: number, fleeDuration: number): string?
	local untilTime = record.stateUntil
	if untilTime == nil or now < untilTime then
		return nil
	end
	if record.state == "Revealed" then
		MimicStateMachine.release(record, now, fleeDuration)
		return "ClaimExpired"
	elseif record.state == "Capturing" then
		return "CaptureTimeout"
	elseif record.state == "Fleeing" then
		return "FleeFinished"
	end
	return nil
end

function MimicStateMachine.isHidden(record: Record): boolean
	return record.state == "Disguised"
end

return MimicStateMachine
