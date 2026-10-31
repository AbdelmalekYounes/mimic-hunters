local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local CaptureLedger = Loader.server("Core/CaptureLedger")
local RewardValidator = Loader.server("Core/RewardValidator")

local function attempt(id, userId, status)
	return {
		id = id,
		userId = userId,
		status = status or "Active",
		createdAt = 0,
		hits = 2,
		hitsRequired = 2,
		speciesId = "chairy",
	}
end

local function capturedRecord(userId, attemptId)
	return { state = "Captured", ownerId = userId, attemptId = attemptId, speciesId = "chairy" }
end

describe("CaptureLedger", function()
	it("n'autorise qu'une tentative active par joueur", function()
		local ledger = CaptureLedger.new()
		expect(ledger:open(attempt("A1", 1))).toBe(true)
		local ok, err = ledger:open(attempt("A2", 1))
		expect(ok).toBe(false)
		expect(err).toBe("PlayerBusy")
		-- Un autre joueur n'est pas bloqué.
		expect(ledger:open(attempt("A3", 2))).toBe(true)
	end)

	it("refuse un identifiant déjà utilisé", function()
		local ledger = CaptureLedger.new()
		ledger:open(attempt("A1", 1))
		ledger:close("A1", 1)
		local ok, err = ledger:open(attempt("A1", 3))
		expect(ok).toBe(false)
		expect(err).toBe("DuplicateId")
	end)

	it("libère le joueur à la clôture", function()
		local ledger = CaptureLedger.new()
		ledger:open(attempt("A1", 1))
		expect(ledger:activeFor(1).id).toBe("A1")
		ledger:close("A1", 5)
		expect(ledger:activeFor(1)).toBeNil()
		expect(ledger:open(attempt("A2", 1))).toBe(true)
	end)

	it("ne verse une récompense qu'une seule fois", function()
		local ledger = CaptureLedger.new()
		expect(ledger:markRewarded("A1")).toBe(true)
		expect(ledger:markRewarded("A1")).toBe(false)
		expect(ledger:isRewarded("A1")).toBe(true)
	end)

	it("oublie entièrement les vieilles tentatives (mémoire bornée, audit V0.3.1)", function()
		local ledger = CaptureLedger.new()
		ledger:open(attempt("A1", 1))
		ledger:markRewarded("A1")
		ledger:close("A1", 0)
		-- Récente : la marque de récompense est gardée (rejeu immédiat refusé).
		expect(ledger:prune(100, 120)).toBe(0)
		expect(ledger:isRewarded("A1")).toBe(true)
		-- Ancienne : tentative et marque oubliées. Sans tentative connue, aucune résolution n'est
		-- possible (identifiants jamais réutilisés sur un serveur) ; l'idempotence durable est
		-- assurée par les clés de capture du profil.
		expect(ledger:prune(200, 120)).toBe(1)
		expect(ledger:get("A1")).toBeNil()
		expect(ledger:isRewarded("A1")).toBe(false)
	end)
end)

describe("RewardValidator", function()
	it("valide une capture cohérente", function()
		local ledger = CaptureLedger.new()
		local a = attempt("A1", 1, "Succeeded")
		expect(RewardValidator.validate(a, capturedRecord(1, "A1"), ledger)).toBe(true)
	end)

	it("refuse chaque incohérence", function()
		local ledger = CaptureLedger.new()
		local cases = {
			{ nil, capturedRecord(1, "A1"), "NoAttempt" },
			{ attempt("A1", 1, "Active"), capturedRecord(1, "A1"), "NotSucceeded" },
			{ attempt("A1", 1, "Failed"), capturedRecord(1, "A1"), "NotSucceeded" },
			{ attempt("A1", 1, "Succeeded"), nil, "NoMimic" },
			{ attempt("A1", 1, "Succeeded"), { state = "Fleeing", ownerId = 1, attemptId = "A1" }, "MimicNotCaptured" },
			{ attempt("A1", 1, "Succeeded"), capturedRecord(2, "A1"), "OwnerMismatch" },
			{ attempt("A1", 1, "Succeeded"), capturedRecord(1, "A9"), "AttemptMismatch" },
		}
		for _, case in cases do
			local ok, err = RewardValidator.validate(case[1], case[2], ledger)
			expect(ok).toBe(false)
			expect(err).toBe(case[3])
		end
	end)

	it("refuse une récompense déjà versée", function()
		local ledger = CaptureLedger.new()
		ledger:markRewarded("A1")
		local ok, err = RewardValidator.validate(attempt("A1", 1, "Succeeded"), capturedRecord(1, "A1"), ledger)
		expect(ok).toBe(false)
		expect(err).toBe("AlreadyRewarded")
	end)

	it("refuse une tentative « réussie » sans assez d'impulsions", function()
		local a = attempt("A1", 1, "Succeeded")
		a.hits = 1
		local ok, err = RewardValidator.validate(a, capturedRecord(1, "A1"), CaptureLedger.new())
		expect(ok).toBe(false)
		expect(err).toBe("InsufficientHits")
	end)
end)
