--!strict
--[[
	AnalyticsServer — transmet les mesures de SessionMetrics à AnalyticsService (V0.3.1, jalon 7).

	API Roblox utilisées (documentation vérifiée le 31/10/2026, les méthodes Fire… sont
	dépréciées) :
	- AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName) : entonnoir
	  d'intégration (une fois par joueur) ;
	- AnalyticsService:LogCustomEvent(player, eventName, value) : compteurs et durées.

	Envoi seulement en jeu publié (pas dans Studio : les tests n'alimentent pas les tableaux de
	bord). Chaque appel est protégé : une panne d'analyse ne touche jamais le jeu. Aucune
	donnée personnelle n'est transmise au-delà de l'objet Player exigé par l'API.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local SessionMetrics = require(Server.Core.SessionMetrics)

local AnalyticsServer = {}

function AnalyticsServer.start(options: { now: () -> number, enabled: boolean? })
	local metrics = SessionMetrics.new()
	local enabled = if options.enabled ~= nil then options.enabled else not RunService:IsStudio()
	local sent = 0

	local function send(userId: number, calls: { SessionMetrics.Call })
		if not enabled or #calls == 0 then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return
		end
		for _, call in calls do
			local ok, err = pcall(function()
				if call.kind == "onboarding" then
					AnalyticsService:LogOnboardingFunnelStepEvent(player, call.step :: number, call.name)
				else
					AnalyticsService:LogCustomEvent(player, call.name, call.value or 1)
				end
			end)
			if ok then
				sent += 1
			else
				warn("[Analyse] " .. tostring(err))
			end
		end
	end

	local service = {}
	function service.join(userId: number)
		send(userId, metrics:join(userId, options.now()))
	end
	function service.observe(event: any)
		local userId = event.userId
		if type(userId) == "number" then
			send(userId, metrics:observe(event, options.now()))
		end
	end
	function service.leave(userId: number, player: Player?)
		-- Au départ, l'objet Player existe encore (PlayerRemoving) : envoi direct.
		local calls = metrics:leave(userId, options.now())
		if enabled and player then
			for _, call in calls do
				pcall(function()
					AnalyticsService:LogCustomEvent(player, call.name, call.value or 1)
				end)
			end
		end
	end
	function service.snapshot(userId: number): any
		return metrics:snapshot(userId, options.now())
	end
	function service.sentCount(): number
		return sent
	end
	return service
end

return AnalyticsServer
