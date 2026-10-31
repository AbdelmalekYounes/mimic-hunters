--!strict
--[[
	RealDataStoreCheck — lance DataStoreCheck sur un VRAI DataStore (V0.3.1, jalon 2).

	N'est inclus QUE dans `datastore-check.project.json`, destiné à une expérience de test
	privée distincte (jamais dans default.project.json ni dans une expérience publique).

	Sécurité des données :
	- DataStore dédié « MimicHunters_DataStoreCheck_v031 » : jamais le stockage des joueurs ;
	- clés « check_<exécution>_<n> » propres à chaque exécution, jamais un vrai userId ;
	- aucune suppression (pas de RemoveAsync) : les clés de test restent, elles sont minuscules.

	Résultats dans la sortie (« [DataStoreCheck] ») et dans l'attribut `DataStoreCheck` de
	Workspace (« 9/9 réussis… »). Limites : voir docs/PRIVATE_TEST_PUBLISH.md.
]]

local HttpService = game:GetService("HttpService")

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local ProfileService = require(Server.Core.ProfileService)
local ProfileSchema = require(Server.Core.ProfileSchema)
local DataStoreBackend = require(Server.Services.DataStoreBackend)
local DataStoreCheck = require(script.Parent.DataStoreCheck)

local STORE = "MimicHunters_DataStoreCheck_v031"

local function main()
	local created, backend = pcall(DataStoreBackend.new, STORE)
	if not created then
		warn("[DataStoreCheck] DataStore inaccessible : " .. tostring(backend))
		workspace:SetAttribute("DataStoreCheck", "DataStore inaccessible")
		return
	end
	local readable = pcall(function()
		return backend._store:GetAsync("check_probe")
	end)
	if not readable then
		warn("[DataStoreCheck] DataStores désactivés (place non publiée ou accès API coupé) : rien n'est testé.")
		workspace:SetAttribute("DataStoreCheck", "DataStores désactivés : non testé")
		return
	end
	local runId = string.sub(HttpService:GenerateGUID(false), 1, 8)
	print(string.format("[DataStoreCheck] exécution %s sur %s", runId, STORE))
	local results = DataStoreCheck({
		ProfileService = ProfileService,
		ProfileSchema = ProfileSchema,
		store = backend._store,
		backend = backend,
		clock = os.time,
		wait = task.wait,
		spawn = task.spawn,
		elapsed = os.clock,
		encode = function(value: any): string
			return HttpService:JSONEncode(value)
		end,
		runId = runId,
		print = print,
	})
	local passed = 0
	for _, r in results do
		if r.ok then
			passed += 1
		end
	end
	local summary = string.format("%d/%d réussis (exécution %s)", passed, #results, runId)
	print("[DataStoreCheck] " .. summary)
	workspace:SetAttribute("DataStoreCheck", summary)
end

task.spawn(main)
