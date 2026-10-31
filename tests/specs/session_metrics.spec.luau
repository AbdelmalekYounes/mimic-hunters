--[[
	Mesures de playtest (V0.3.1, jalon 7) : SessionMetrics déduit les étapes et compteurs
	des événements du jeu, sans donnée personnelle.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local SessionMetrics = Loader.server("Core/SessionMetrics")

local U = 42

local function names(calls)
	local out = {}
	for _, call in calls do
		table.insert(out, call.name)
	end
	return table.concat(out, ",")
end

describe("SessionMetrics", function()
	it("mesure le temps avant les premières fois, une seule fois chacune", function()
		local m = SessionMetrics.new()
		local join = m:join(U, 100)
		expect(join[1].step).toBe(1)
		local calls = m:observe({ name = "CaptureResolved", userId = U, payload = { success = true } }, 145)
		expect(names(calls)).toBe("CaptureReussie,Première capture,TempsPremiereCapture")
		expect(calls[3].value).toBe(45)
		local again = m:observe({ name = "CaptureResolved", userId = U, payload = { success = true } }, 160)
		expect(names(again)).toBe("CaptureReussie")
	end)

	it("suit la boucle complète : Codex, base, exposition, visite, Museum Hunt", function()
		local m = SessionMetrics.new()
		m:join(U, 0)
		m:observe({ name = "_CodexOpened", userId = U }, 30)
		m:observe({ name = "MuseumResult", userId = U, payload = { ok = true, action = "travel", kind = "base" } }, 60)
		m:observe({ name = "MuseumResult", userId = U, payload = { ok = true, action = "exhibit" } }, 70)
		m:observe(
			{ name = "MuseumResult", userId = U, payload = { ok = true, action = "travel", kind = "museum" } },
			90
		)
		m:observe({ name = "HuntUpdate", userId = U, payload = { phase = "start" } }, 95)
		m:observe({ name = "HuntUpdate", userId = U, payload = { phase = "end", found = 3, total = 3 } }, 130)
		local snap = m:snapshot(U, 130)
		expect(table.concat(snap.firsts, ",")).toBe(
			"Codex ouvert,Base visitée,Premier Mimic exposé,Autre musée visité,Museum Hunt réussie"
		)
		expect(snap.huntsStarted).toBe(1)
		expect(snap.huntsCompleted).toBe(1)
	end)

	it("compte les ratés et les mutations, et clôt la session au départ", function()
		local m = SessionMetrics.new()
		m:join(U, 0)
		m:observe({ name = "CaptureResolved", userId = U, payload = { success = false } }, 10)
		local rare = m:observe(
			{ name = "CaptureResolved", userId = U, payload = { success = true, specimen = { mutation = "Spectral" } } },
			20
		)
		expect(string.find(names(rare), "MutationSpectral", 1, true) ~= nil).toBe(true)
		local snap = m:snapshot(U, 20)
		expect(snap.failures).toBe(1)
		expect(snap.mutations.Spectral).toBe(1)
		local leave = m:leave(U, 600)
		expect(leave[1].name).toBe("DureeSession")
		expect(leave[1].value).toBe(600)
		expect(m:snapshot(U, 601)).toBeNil()
	end)

	it("ignore les autres joueurs et les refus, sans aucune donnée personnelle", function()
		local m = SessionMetrics.new()
		m:join(U, 0)
		expect(#m:observe({ name = "CaptureResolved", userId = 99, payload = { success = true } }, 5)).toBe(0)
		expect(#m:observe({ name = "MuseumResult", userId = U, payload = { ok = false, action = "exhibit" } }, 5)).toBe(
			0
		)
		local calls = m:observe(
			{ name = "CaptureResolved", userId = U, payload = { success = true, specimen = { id = "S42-1" } } },
			6
		)
		for _, call in calls do
			for key, value in call do
				expect(key == "kind" or key == "name" or key == "value" or key == "step").toBe(true)
				expect(type(value) == "string" or type(value) == "number").toBe(true)
			end
			expect(call.name ~= "S42-1").toBe(true)
		end
	end)
end)
