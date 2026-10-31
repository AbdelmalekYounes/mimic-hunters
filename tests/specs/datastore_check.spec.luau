--[[
	Vérifie le script de contrôle du vrai DataStore (tests/datastore/DataStoreCheck) sur un
	DataStore SIMULÉ, avant de l'exécuter dans une expérience de test privée. Ce test ne
	prouve rien sur le vrai DataStore : il prouve que le script est juste.
]]

local TestKit = require("../lib/TestKit")
local Loader = require("../lib/Loader")
local Scheduler = require("../lib/Scheduler")
local DataStoreCheck = require("../datastore/DataStoreCheck")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ProfileService = Loader.server("Core/ProfileService")
local ProfileSchema = Loader.server("Core/ProfileSchema")

-- Sérialisation déterministe (clés triées) pour comparer deux tables, comme JSONEncode.
local function encode(value): string
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for k in value do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		local v = value[k]
		if v == nil then
			v = value[tonumber(k)]
		end
		table.insert(parts, k .. "=" .. encode(v))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- DataStore simulé : mêmes règles que Roblox pour ce que le script utilise.
local function fakeStore(env)
	local data = {}
	local store = {}
	function store.GetAsync(_self, key)
		env.wait(0.1)
		return ProfileSchema.deepCopy(data[key])
	end
	function store.SetAsync(_self, key, value)
		env.wait(0.1)
		data[key] = ProfileSchema.deepCopy(value)
	end
	function store.UpdateAsync(_self, key, transform)
		env.wait(0.1)
		local result = transform(ProfileSchema.deepCopy(data[key]))
		if result ~= nil then
			data[key] = ProfileSchema.deepCopy(result)
		end
		return ProfileSchema.deepCopy(data[key])
	end
	-- Interface ProfileService, comme DataStoreBackend (pcall autour d'UpdateAsync).
	local backend = {}
	function backend.update(_self, key, transform)
		return pcall(function()
			return store:UpdateAsync(key, transform)
		end)
	end
	function backend.budget(_self)
		return 10
	end
	return store, backend, data
end

describe("Contrôle du vrai DataStore — script vérifié sur un DataStore simulé", function()
	it("passe ses 9 scénarios sans jamais toucher une clé de joueur", function()
		local env = Scheduler.new(1700000000)
		local store, backend, data = fakeStore(env)
		local results
		local elapsed = 0
		env.run(function()
			results = DataStoreCheck({
				ProfileService = ProfileService,
				ProfileSchema = ProfileSchema,
				store = store,
				backend = backend,
				clock = env.clock,
				wait = env.wait,
				spawn = env.spawn,
				elapsed = function()
					elapsed = env.t
					return elapsed
				end,
				encode = encode,
				runId = "lune",
				print = function() end,
			})
		end)
		expect(#results).toBe(9)
		for _, r in results do
			if not r.ok then
				error(r.name .. " : " .. tostring(r.detail), 0)
			end
		end
		-- Uniquement des clés de contrôle, avec des identifiants impossibles pour un joueur.
		for key in data do
			expect(string.match(key, "^check_lune_%-%d+$") ~= nil).toBe(true)
		end
	end)
end)
