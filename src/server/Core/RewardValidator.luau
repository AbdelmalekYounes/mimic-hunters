--!strict
--[[
	RewardValidator — dernier contrôle avant d'ajouter un Mimic à l'inventaire.

	La récompense ne dépend jamais d'un message client : elle exige une
	tentative réussie selon le serveur, un Mimic capturé par ce même joueur
	avec cette même tentative, et aucune récompense déjà versée.
]]

local RewardValidator = {}

function RewardValidator.validate(attempt: any, record: any, ledger: any): (boolean, string?)
	if attempt == nil then
		return false, "NoAttempt"
	end
	if attempt.status ~= "Succeeded" then
		return false, "NotSucceeded"
	end
	if attempt.hits < attempt.hitsRequired then
		return false, "InsufficientHits"
	end
	if ledger:isRewarded(attempt.id) then
		return false, "AlreadyRewarded"
	end
	if record == nil then
		return false, "NoMimic"
	end
	if record.state ~= "Captured" then
		return false, "MimicNotCaptured"
	end
	if record.ownerId ~= attempt.userId then
		return false, "OwnerMismatch"
	end
	if record.attemptId ~= attempt.id then
		return false, "AttemptMismatch"
	end
	if record.speciesId ~= attempt.speciesId then
		return false, "SpeciesMismatch"
	end
	return true, nil
end

return RewardValidator
