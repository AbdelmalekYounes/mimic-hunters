--!strict
--[[
	PropTracker — connaît les objets inspectables (tag "MimicProp") et sait
	les masquer / réafficher localement quand un Mimic prend leur place.
	Les modifications sont locales : elles ne sont jamais répliquées.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local PROP_TAG = "MimicProp"

local PropTracker = {}

local props: { [string]: Model } = {}
local hidden: { [string]: { { part: BasePart, transparency: number } } } = {}

local function register(instance: Instance)
	if instance:IsA("Model") then
		local id = instance:GetAttribute("PropId")
		if type(id) == "string" then
			props[id] = instance
		end
	end
end

function PropTracker.start()
	for _, instance in CollectionService:GetTagged(PROP_TAG) do
		register(instance)
	end
	CollectionService:GetInstanceAddedSignal(PROP_TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(PROP_TAG):Connect(function(instance)
		local id = instance:GetAttribute("PropId")
		if type(id) == "string" and props[id] == instance then
			props[id] = nil
		end
	end)
end

function PropTracker.get(propId: string): Model?
	return props[propId]
end

function PropTracker.all(): { [string]: Model }
	return props
end

function PropTracker.kindOf(propId: string): string?
	local model = props[propId]
	local kind = model and model:GetAttribute("PropKind")
	return if type(kind) == "string" then kind else nil
end

function PropTracker.isHidden(propId: string): boolean
	return hidden[propId] ~= nil
end

-- Retrouve l'objet à partir d'une part touchée par un rayon.
function PropTracker.fromPart(part: Instance?): (string?, Model?)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") and CollectionService:HasTag(current, PROP_TAG) then
			local id = current:GetAttribute("PropId")
			return if type(id) == "string" then id else nil, current
		end
		current = current.Parent
	end
	return nil, nil
end

function PropTracker.hide(propId: string)
	local model = props[propId]
	if model == nil or hidden[propId] then
		return
	end
	local saved = {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			table.insert(saved, { part = child, transparency = child.Transparency })
			child.Transparency = 1
		elseif child:IsA("Light") then
			child.Enabled = false
		end
	end
	hidden[propId] = saved
end

-- Réaffiche l'objet (avec un fondu si `fade` est donné).
function PropTracker.show(propId: string, fade: number?)
	local saved = hidden[propId]
	local model = props[propId]
	hidden[propId] = nil
	if saved == nil or model == nil then
		return
	end
	for _, entry in saved do
		if fade and fade > 0 then
			TweenService:Create(entry.part, TweenInfo.new(fade), { Transparency = entry.transparency }):Play()
		else
			entry.part.Transparency = entry.transparency
		end
	end
	for _, child in model:GetDescendants() do
		if child:IsA("Light") then
			child.Enabled = true
		end
	end
end

return PropTracker
