--[[
	TestKit — mini framework de tests pour Lune (describe / it / expect).
]]

local TestKit = {}

type Test = { name: string, fn: () -> () }
type Suite = { name: string, file: string, tests: { Test } }

local suites: { Suite } = {}
local currentFile = "?"
local currentSuite: Suite? = nil

function TestKit.setFile(file: string)
	currentFile = file
end

function TestKit.describe(name: string, fn: () -> ())
	local suite = { name = name, file = currentFile, tests = {} }
	table.insert(suites, suite)
	local previous = currentSuite
	currentSuite = suite
	fn()
	currentSuite = previous
end

function TestKit.it(name: string, fn: () -> ())
	assert(currentSuite, "it() doit être appelé dans describe()")
	table.insert(currentSuite.tests, { name = name, fn = fn })
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	local count = 0
	for k, v in value do
		count += 1
		if count > 12 then
			table.insert(parts, "…")
			break
		end
		table.insert(parts, tostring(k) .. "=" .. (if type(v) == "table" then "{…}" else tostring(v)))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fail(message: string)
	error(message, 3)
end

function TestKit.expect(actual: any)
	local matchers = {}
	function matchers.toBe(expected: any)
		if actual ~= expected then
			fail("attendu " .. show(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			fail("attendu (profond) " .. show(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toBeTruthy()
		if not actual then
			fail("attendu une valeur vraie, obtenu " .. show(actual))
		end
	end
	function matchers.toBeFalsy()
		if actual then
			fail("attendu une valeur fausse, obtenu " .. show(actual))
		end
	end
	function matchers.toBeNil()
		if actual ~= nil then
			fail("attendu nil, obtenu " .. show(actual))
		end
	end
	function matchers.toBeCloseTo(expected: number, epsilon: number?)
		local eps = epsilon or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			fail(string.format("attendu %s ± %s, obtenu %s", tostring(expected), tostring(eps), show(actual)))
		end
	end
	function matchers.toBeGreaterThan(expected: number)
		if not (actual > expected) then
			fail("attendu > " .. tostring(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toBeLessThan(expected: number)
		if not (actual < expected) then
			fail("attendu < " .. tostring(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toBeAtLeast(expected: number)
		if not (actual >= expected) then
			fail("attendu >= " .. tostring(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toBeAtMost(expected: number)
		if not (actual <= expected) then
			fail("attendu <= " .. tostring(expected) .. ", obtenu " .. show(actual))
		end
	end
	function matchers.toThrow()
		local ok = pcall(actual)
		if ok then
			fail("attendu une erreur, aucune levée")
		end
	end
	return matchers
end

function TestKit.run(): boolean
	local passed, failed = 0, 0
	local failures = {}
	for _, suite in suites do
		print(string.format("\n▶ %s  (%s)", suite.name, suite.file))
		for _, test in suite.tests do
			local ok, err = pcall(test.fn)
			if ok then
				passed += 1
				print("  ✓ " .. test.name)
			else
				failed += 1
				print("  ✗ " .. test.name)
				print("      " .. tostring(err))
				table.insert(failures, suite.name .. " › " .. test.name)
			end
		end
	end
	print(string.format("\n%d réussi(s), %d échoué(s), %d au total", passed, failed, passed + failed))
	if failed > 0 then
		print("Échecs :")
		for _, name in failures do
			print("  - " .. name)
		end
	end
	return failed == 0
end

return TestKit
