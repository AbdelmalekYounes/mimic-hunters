--!strict
--[[
	MuseumServer — adaptateur Roblox des musées (V0.3).

	- Construit le quartier et les 8 musées au démarrage (MuseumBuilder).
	- Relie les RemoteEvents du musée à MuseumCore et diffuse ses événements.
	- Traite les événements internes : rendu d'un musée, parcelle libérée, téléportation,
	  objets de la Museum Hunt.
	Toute décision (parcelle, propriété, destination, résultats de chasse) est prise par
	MuseumCore ; ce module ne fait qu'appliquer.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MimicCatalog = require(Shared.Config.MimicCatalog)
local PropBuilder = require(Shared.Builders.PropBuilder)

local Server = script.Parent.Parent
local MuseumCore = require(Server.Core.MuseumCore)
local MuseumLayout = require(Server.Map.MuseumLayout)
local MapLayout = require(Server.Map.MapLayout)
local MuseumBuilder = require(Server.Map.MuseumBuilder)

local MuseumServer = {}

-- Nom affiché du propriétaire (les faux joueurs des tests Studio n'ont pas d'objet Player).
local function displayName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else string.format("Collectionneur %d", math.abs(userId))
end

local function boardText(name: string, stats: any): string
	return string.format(
		"Collection de %s\nEspèces %d/%d  ·  %d Mimic%s\nExposés %d/6  ·  Mutations exposées %d",
		name,
		stats.discovered,
		MimicCatalog.count(),
		stats.owned,
		if stats.owned > 1 then "s" else "",
		stats.exhibited,
		stats.mutationsExhibited
	)
end

--[[
	context = { world, remotes, dispatch, studio, rng }
	Retourne l'objet utilisé par HuntServer (crochets de cycle de vie, routage des scans).
]]
function MuseumServer.start(context: any)
	local world = context.world
	local remotes = context.remotes
	local dispatch = context.dispatch
	local core = MuseumCore.new({
		world = world,
		layout = MuseumLayout,
		config = GameConfig,
		catalog = MimicCatalog,
		rng = context.rng,
		hunt = context.hunt,
	})

	local map = Workspace:FindFirstChild("Map") or Workspace
	local root = Instance.new("Folder")
	root.Name = "Museums"
	root.Parent = map
	MuseumBuilder.buildDistrict(root)
	local plots: { MuseumBuilder.PlotRefs } = {}
	for index = 1, #MuseumLayout.Plots do
		local refs = MuseumBuilder.buildPlot(index, root)
		MuseumBuilder.applyStyles(refs, nil)
		plots[index] = refs
	end

	local function now(): number
		return os.clock()
	end

	-- ─── Événements internes ───────────────────────────────────────────
	local handlers: { [string]: (event: any) -> () } = {}

	handlers._MuseumRender = function(event)
		local p = event.payload
		local refs = plots[p.plot]
		if refs == nil then
			return
		end
		local name = displayName(p.ownerId)
		MuseumBuilder.setOwner(refs, name, p.ownerId)
		MuseumBuilder.applyStyles(refs, p.styles)
		MuseumBuilder.setBoard(refs, boardText(name, p.stats))
		MuseumBuilder.renderExhibits(refs, p.slots, name, p.ownerId)
	end

	handlers._MuseumClear = function(event)
		local refs = plots[event.payload.plot]
		if refs == nil then
			return
		end
		MuseumBuilder.setOwner(refs, nil, nil)
		MuseumBuilder.applyStyles(refs, nil)
		MuseumBuilder.setBoard(refs, "")
		MuseumBuilder.clearExhibits(refs)
	end

	handlers._Teleport = function(event)
		local p = event.payload
		local player = Players:GetPlayerByUserId(p.userId)
		local character = player and player.Character
		if character == nil then
			return
		end
		local target: CFrame
		if p.point == "village" then
			local spawn = MapLayout.Spawn
			target = CFrame.lookAt(
				Vector3.new(spawn.position.X, 3, spawn.position.Z),
				Vector3.new(spawn.face.X, 3, spawn.face.Z)
			)
		else
			-- Devant l'entrée du musée, tourné vers la porte.
			local entrance = MuseumBuilder.localCFrame(p.plot, MuseumLayout.Entrance, 3)
			target = entrance * CFrame.Angles(0, math.pi, 0)
		end
		character:PivotTo(target)
	end

	-- Objets de la Museum Hunt : objets ordinaires du jeu (PropBuilder), tagués comme ceux du
	-- monde pour que le client les cible et y joue les indices sans code particulier.
	-- Le modèle ne dit jamais s'il abrite une copie : seul MuseumCore le sait.
	local huntProps: { [string]: { [string]: Model } } = {}

	handlers._HuntSpawn = function(event)
		local p = event.payload
		local refs = plots[p.plot]
		if refs == nil then
			return
		end
		local list = {}
		local garden = MuseumBuilder.localCFrame(p.plot, MuseumLayout.HuntZone.center, 0)
		for _, prop in p.props do
			local model = PropBuilder.build(prop.kind, prop.variant)
			local spot = MuseumBuilder.localCFrame(p.plot, MuseumLayout.HuntSpots[prop.spot], 0)
			-- Tourné vers l'allée centrale du jardin.
			model:PivotTo(CFrame.lookAt(spot.Position, Vector3.new(garden.X, spot.Y, spot.Z)))
			model.Name = prop.propId
			model:SetAttribute("PropId", prop.propId)
			model:SetAttribute("Zone", "Museum")
			model:SetAttribute("HuntId", p.huntId)
			model.Parent = refs.hunt
			CollectionService:AddTag(model, "MimicProp")
			list[prop.propId] = model
		end
		huntProps[p.huntId] = list
	end

	handlers._HuntRemoveProp = function(event)
		local list = huntProps[event.payload.huntId]
		local model = list and list[event.payload.propId]
		if model then
			list[event.payload.propId] = nil
			model:Destroy()
		end
	end

	handlers._HuntDespawn = function(event)
		local list = huntProps[event.payload.huntId]
		huntProps[event.payload.huntId] = nil
		for _, model in list or {} do
			model:Destroy()
		end
	end

	local function handle(event: any): boolean
		local handler = handlers[event.name]
		if handler then
			handler(event)
			return true
		end
		return false
	end

	-- ─── RemoteEvents ──────────────────────────────────────────────────
	local function guarded(name: string, fn: (...any) -> ())
		return function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				warn(string.format("[MuseumServer] erreur dans %s : %s", name, tostring(err)))
			end
		end
	end

	remotes.RequestTravel.OnServerEvent:Connect(
		guarded("RequestTravel", function(player: Player, kind: any, target: any)
			dispatch((core:travel(player.UserId, kind, target, now())))
		end)
	)
	remotes.SetExhibit.OnServerEvent:Connect(guarded("SetExhibit", function(player: Player, slot: any, specimenId: any)
		dispatch((core:setExhibit(player.UserId, slot, specimenId, now())))
	end))
	remotes.MoveExhibit.OnServerEvent:Connect(guarded("MoveExhibit", function(player: Player, from: any, to: any)
		dispatch((core:moveExhibit(player.UserId, from, to, now())))
	end))
	remotes.SetMuseumStyle.OnServerEvent:Connect(guarded("SetMuseumStyle", function(player: Player, kind: any, id: any)
		dispatch((core:setStyle(player.UserId, kind, id, now())))
	end))
	remotes.RequestMuseums.OnServerEvent:Connect(guarded("RequestMuseums", function(player: Player)
		dispatch((core:list(player.UserId, now())))
	end))
	remotes.StartMuseumHunt.OnServerEvent:Connect(guarded("StartMuseumHunt", function(player: Player, ownerId: any)
		dispatch((core:startHunt(player.UserId, ownerId, context.positionOf(player), now())))
	end))

	local service = {
		core = core,
		plots = plots,
		handle = handle,
	}

	-- Diffuse des événements du cœur (utilisé par les crochets ci-dessous et par les tests Studio).
	function service.run(events: { any })
		dispatch(events)
	end

	-- Crochets appelés par HuntServer.
	function service.onPlayerReady(userId: number)
		dispatch(core:join(userId, now()))
	end
	function service.refresh(userId: number)
		dispatch(core:refresh(userId))
	end
	function service.onPlayerRemoving(userId: number)
		dispatch(core:leave(userId, now()))
	end
	-- Routage des scans et examens : pendant une Museum Hunt, ils vont au défi.
	function service.hunting(userId: number): boolean
		return core:huntOf(userId) ~= nil
	end
	function service.isHuntProp(propId: any): boolean
		return type(propId) == "string" and string.sub(propId, 1, 2) == "MH"
	end
	function service.scan(player: Player)
		dispatch((core:huntScan(player.UserId, context.positionOf(player), now())))
	end
	function service.inspect(player: Player, propId: any)
		dispatch((core:huntInspect(player.UserId, context.positionOf(player), propId, now())))
	end
	function service.tick(positions: { [number]: any })
		dispatch(core:tick(now(), positions))
	end

	return service
end

return MuseumServer
