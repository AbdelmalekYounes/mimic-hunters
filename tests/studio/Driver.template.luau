--[[
	Driver — script exécuté par Roblox Studio en ligne de commande :
		RobloxStudioBeta.exe --task RunScript --localPlaceFile <place>
		                     --runScriptFile <driver> --outputFile <x.log> --quitAfterExecution

	Il s'exécute dans le DataModel d'ÉDITION avec les permissions de la barre
	de commande, ce qui autorise StudioTestService (PluginSecurity).
	Ce fichier est un gabarit : tools/studio-tests.ps1 remplace les trois
	marqueurs des chaînes longues ci-dessous (suites et sessions) avant le
	lancement. Ne pas citer ces marqueurs ailleurs dans ce fichier.

	Chaque résultat est émis sur une ligne « @@MH@@ <json> » lue par le lanceur.
]]

local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local SERVER_SUITE = [==[__SERVER_SUITE__]==]
local CLIENT_SUITE = [==[__CLIENT_SUITE__]==]
local SESSIONS = HttpService:JSONDecode([==[__SESSIONS__]==])
local WARMUP_SECONDS = 4

local function emit(kind: string, data: any)
	print("@@MH@@ " .. HttpService:JSONEncode({ kind = kind, data = data }))
end

local function studioVersion(): string
	local ok, v = pcall(function()
		-- selene: allow(undefined_variable)
		return version()
	end)
	return if ok then v else "?"
end

emit("start", { studioVersion = studioVersion(), sessions = #SESSIONS })

-- Laisse Studio finir son initialisation : une session lancée trop tôt
-- se termine immédiatement sans résultat (observé expérimentalement).
task.wait(WARMUP_SECONDS)

local serverScript = Instance.new("Script")
serverScript.Name = "MH_TestServer"
serverScript.Source = SERVER_SUITE
serverScript.Parent = ServerScriptService

local clientScript = Instance.new("LocalScript")
clientScript.Name = "MH_TestClient"
clientScript.Source = CLIENT_SUITE
clientScript.Parent = StarterPlayer:WaitForChild("StarterPlayerScripts")

-- Simulation d'appareil (optionnelle, PluginSecurity). Toujours restaurée.
local DeviceSim = nil
pcall(function()
	DeviceSim = game:GetService("StudioDeviceSimulatorService")
end)

local function pickDevice(wanted: string): (string?, string?)
	if DeviceSim == nil then
		return nil, "StudioDeviceSimulatorService indisponible"
	end
	local ok, list = pcall(function()
		return DeviceSim:GetDeviceListAsync()
	end)
	if not ok then
		return nil, "GetDeviceListAsync : " .. tostring(list)
	end
	emit("devices", list)
	for _, id in list do
		if string.find(string.lower(id), string.lower(wanted), 1, true) then
			return id, nil
		end
	end
	return nil, "aucun appareil ne correspond à « " .. wanted .. " »"
end

local function runSession(session: any): (boolean, any)
	return pcall(function()
		if session.mode == "Run" then
			return StudioTestService:ExecuteRunModeAsync(session.args)
		elseif session.mode == "Play" then
			return StudioTestService:ExecutePlayModeAsync(session.args)
		elseif session.mode == "Multiplayer" then
			return StudioTestService:ExecuteMultiplayerTestAsync(session.players or 2, session.args)
		end
		error("mode inconnu " .. tostring(session.mode))
	end)
end

for _, session in SESSIONS do
	local info: { [string]: any } = { name = session.name, mode = session.mode }
	local deviceActive = false
	if session.device then
		local id, why = pickDevice(session.device)
		info.deviceId = id
		if id then
			local ok, err = pcall(function()
				DeviceSim:SetDeviceAsync(id)
			end)
			deviceActive = ok
			if ok then
				pcall(function()
					info.simulatedResolution = tostring(DeviceSim:GetResolutionAsync())
					info.simulatedOrientation = tostring(DeviceSim:GetOrientationAsync())
				end)
			else
				info.deviceError = tostring(err)
			end
		else
			info.deviceError = why
		end
	end

	local attempts = 0
	local ok, result
	local t0 = os.clock()
	repeat
		attempts += 1
		ok, result = runSession(session)
	-- nil = session terminée sans EndTest (démarrage trop précoce) : on réessaie une fois.
	until not (ok and result == nil) or attempts >= 2
	info.attempts = attempts
	info.duration = os.clock() - t0
	info.ok = ok
	if ok then
		info.report = result
	else
		info.error = tostring(result)
	end

	if deviceActive then
		pcall(function()
			DeviceSim:StopSimulationAsync()
		end)
	end
	emit("session", info)
	task.wait(1)
end

serverScript:Destroy()
clientScript:Destroy()
emit("done", {})
