--!strict
--[[
	HuntServer — adaptateur Roblox autour de HuntWorld.

	Responsabilités (et rien d'autre) :
	- relier les RemoteEvents aux méthodes de HuntWorld ;
	- fournir la position réelle du personnage (jamais celle annoncée par le client) ;
	- fournir l'heure serveur et une estimation de latence ;
	- diffuser les événements retournés ;
	- charger / sauvegarder les profils via le ProfileStore.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local Rarities = require(Shared.Config.Rarities)
local Rng = require(Shared.Logic.Rng)
local Remotes = require(Shared.Net.Remotes)

local Server = script.Parent.Parent
local HuntWorld = require(Server.Core.HuntWorld)
local MapLayout = require(Server.Map.MapLayout)
local MemoryProfileStore = require(script.Parent.MemoryProfileStore)

local TICK_INTERVAL = 0.2

local HuntServer = {}

function HuntServer.start()
	local seed = os.time() + math.floor(os.clock() * 1000)
	local world = HuntWorld.new({
		config = GameConfig,
		catalog = MimicCatalog,
		rarities = Rarities,
		slots = MapLayout.Props,
		tutorialSlot = MapLayout.TutorialProp,
		zones = MapLayout.zoneIds(),
		rng = Rng.new(seed),
	})
	local store = MemoryProfileStore.new()
	local remotes = Remotes.setup()

	local function now(): number
		return os.clock()
	end

	local studio = RunService:IsStudio()
	if studio then
		-- Accès de débogage depuis la barre de commande de Studio (serveur seulement).
		-- selene: allow(global_usage)
		(_G :: any).MimicHuntWorld = world
	end

	local function dispatch(events: { HuntWorld.Event })
		for _, event in events do
			if studio and event.name == "CaptureResolved" then
				local p = event.payload
				print(
					string.format(
						"[MimicHunters] capture %s : joueur %s, %s (%s)",
						if p.success then "réussie" else "échouée",
						tostring(event.userId),
						tostring(p.speciesId),
						tostring(p.reason or (if p.isNew then "nouvelle espèce" else "doublon"))
					)
				)
			elseif studio and event.name == "PulseResult" and event.payload.ok then
				local p = event.payload
				print(
					string.format(
						"[MimicHunters] impulsion %s : %s à %.2f (%d/%d)",
						tostring(p.attemptId),
						if p.hit then "réussie" else "ratée",
						p.position or -1,
						p.hits or 0,
						p.misses or 0
					)
				)
			end
			local remote = remotes[event.name]
			if remote == nil then
				warn("[HuntServer] RemoteEvent inconnu :", event.name)
				continue
			end
			if event.userId then
				local player = Players:GetPlayerByUserId(event.userId)
				if player then
					remote:FireClient(player, event.payload)
				end
			else
				remote:FireAllClients(event.payload)
			end
		end
	end

	-- Position autoritaire : celle du HumanoidRootPart vivant, sinon nil.
	local function positionOf(player: Player): Vector3?
		local character = player.Character
		if character == nil then
			return nil
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			return root.Position
		end
		return nil
	end

	local function allowanceOf(player: Player): number
		local ok, ping = pcall(function()
			return player:GetNetworkPing()
		end)
		local value = if ok and type(ping) == "number" then ping else 0
		return value + GameConfig.Capture.LatencyBase
	end

	-- Une erreur dans un gestionnaire ne doit jamais casser la boucle de jeu.
	local function guarded(name: string, handler: (...any) -> ())
		return function(...)
			local ok, err = pcall(handler, ...)
			if not ok then
				warn(string.format("[HuntServer] erreur dans %s : %s", name, tostring(err)))
			end
		end
	end

	local function onPlayerAdded(player: Player)
		local profile = store:load(player.UserId)
		world:addPlayer(player.UserId, now(), profile)
	end

	world:populate(now())
	Players.PlayerAdded:Connect(guarded("PlayerAdded", onPlayerAdded))
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(guarded("PlayerRemoving", function(player: Player)
		local profile = world:getProfile(player.UserId)
		if profile then
			store:save(player.UserId, profile)
		end
		dispatch(world:removePlayer(player.UserId, now()))
	end))

	remotes.ClientReady.OnServerEvent:Connect(guarded("ClientReady", function(player: Player)
		dispatch((world:clientReady(player.UserId, now())))
	end))

	remotes.RequestScan.OnServerEvent:Connect(guarded("RequestScan", function(player: Player)
		dispatch((world:scan(player.UserId, positionOf(player), now())))
	end))

	remotes.RequestInspect.OnServerEvent:Connect(guarded("RequestInspect", function(player: Player, propId: any)
		dispatch((world:inspect(player.UserId, positionOf(player), propId, now())))
	end))

	remotes.RequestCapture.OnServerEvent:Connect(guarded("RequestCapture", function(player: Player, mimicId: any)
		dispatch((world:startCapture(player.UserId, positionOf(player), mimicId, now())))
	end))

	remotes.SubmitPulse.OnServerEvent:Connect(
		guarded("SubmitPulse", function(player: Player, attemptId: any, elapsed: any)
			dispatch((world:pulse(player.UserId, positionOf(player), attemptId, elapsed, allowanceOf(player), now())))
		end)
	)

	local accumulator = 0
	RunService.Heartbeat:Connect(guarded("Tick", function(dt: number)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		accumulator = 0
		local positions: { [number]: Vector3 } = {}
		for _, player in Players:GetPlayers() do
			local position = positionOf(player)
			if position then
				positions[player.UserId] = position
			end
		end
		dispatch(world:tick(now(), positions))
	end))

	return world
end

return HuntServer
