--!strict
--[[
	CaptureLedger — registre des tentatives de capture.

	Garanties :
	- un joueur n'a qu'une seule tentative active à la fois ;
	- un identifiant de tentative n'est jamais réutilisé ;
	- une récompense n'est attribuée qu'une seule fois par tentative,
	  même si le client renvoie la même requête plusieurs fois.
]]

type Attempt = {
	id: string,
	userId: number,
	status: string,
	createdAt: number,
}

export type Ledger = {
	_attempts: { [string]: Attempt },
	_active: { [number]: string },
	_rewarded: { [string]: boolean },
	_closedAt: { [string]: number },
	open: (self: Ledger, attempt: Attempt) -> (boolean, string?),
	get: (self: Ledger, id: string) -> Attempt?,
	activeFor: (self: Ledger, userId: number) -> Attempt?,
	close: (self: Ledger, id: string, now: number) -> (),
	markRewarded: (self: Ledger, id: string) -> boolean,
	isRewarded: (self: Ledger, id: string) -> boolean,
	activeAttempts: (self: Ledger) -> { Attempt },
	prune: (self: Ledger, now: number, keepSeconds: number) -> number,
}

local CaptureLedger = {}
CaptureLedger.__index = CaptureLedger

function CaptureLedger.new(): Ledger
	return (
		setmetatable({
			_attempts = {},
			_active = {},
			_rewarded = {},
			_closedAt = {},
		}, CaptureLedger) :: any
	) :: Ledger
end

function CaptureLedger.open(self: Ledger, attempt: Attempt): (boolean, string?)
	if self._attempts[attempt.id] ~= nil then
		return false, "DuplicateId"
	end
	if self._active[attempt.userId] ~= nil then
		return false, "PlayerBusy"
	end
	self._attempts[attempt.id] = attempt
	self._active[attempt.userId] = attempt.id
	return true, nil
end

function CaptureLedger.get(self: Ledger, id: string): Attempt?
	return self._attempts[id]
end

function CaptureLedger.activeFor(self: Ledger, userId: number): Attempt?
	local id = self._active[userId]
	return if id then self._attempts[id] else nil
end

function CaptureLedger.close(self: Ledger, id: string, now: number)
	local attempt = self._attempts[id]
	if attempt == nil then
		return
	end
	if self._active[attempt.userId] == id then
		self._active[attempt.userId] = nil
	end
	if self._closedAt[id] == nil then
		self._closedAt[id] = now
	end
end

function CaptureLedger.markRewarded(self: Ledger, id: string): boolean
	if self._rewarded[id] then
		return false
	end
	self._rewarded[id] = true
	return true
end

function CaptureLedger.isRewarded(self: Ledger, id: string): boolean
	return self._rewarded[id] == true
end

function CaptureLedger.activeAttempts(self: Ledger): { Attempt }
	local out = {}
	for _, id in self._active do
		local attempt = self._attempts[id]
		if attempt then
			table.insert(out, attempt)
		end
	end
	return out
end

-- Oublie les tentatives closes depuis longtemps. Les identifiants récompensés
-- restent mémorisés (coût minime) pour que la règle « une seule fois » tienne.
function CaptureLedger.prune(self: Ledger, now: number, keepSeconds: number): number
	local removed = 0
	for id, closedAt in self._closedAt do
		if now - closedAt > keepSeconds then
			self._attempts[id] = nil
			self._closedAt[id] = nil
			removed += 1
		end
	end
	return removed
end

return CaptureLedger
