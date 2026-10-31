--!strict
--[[
	ClientState — ce que le client sait (uniquement ce que le serveur lui a dit).

	Le client ne connaît jamais l'emplacement des Mimics cachés : il n'apprend
	qu'un Mimic existe qu'au moment où il est révélé.
]]

local Players = game:GetService("Players")

local Signal = require(script.Parent.Util.Signal)

export type MimicInfo = {
	mimicId: string,
	propId: string,
	speciesId: string?,
	state: string,
	ownerUserId: number?,
	expiresAt: number?,
}

--[[
	Collection vue par le client (copie de ce que le serveur envoie, jamais modifiée localement) :
	summary = { totalCaptures, discovered, owned, maxSpecimens, mutations, codex, objectives,
	            cosmetics, settings }
	specimens = liste des exemplaires, du plus récent au plus ancien ; byId pour l'accès direct.
]]
local ClientState = {
	userId = Players.LocalPlayer.UserId,
	mimics = {} :: { [string]: MimicInfo },
	summary = nil :: any,
	specimens = {} :: { any },
	specimensById = {} :: { [string]: any },
	profileStatus = "Loading",
	-- Musée (V0.3) : parcelle attribuée par le serveur, ou file d'attente.
	museumPlot = nil :: number?,
	museumWaiting = false,
	tutorialStep = "Done",
	tutorialPropId = nil :: string?,
	attemptActive = false,

	MimicChanged = Signal.new(), -- (info: MimicInfo, previousState: string?)
	CollectionChanged = Signal.new(), -- (reason: "snapshot" | "added" | "updated" | "summary", specimen?)
	ProfileStatusChanged = Signal.new(), -- (status)
	MuseumChanged = Signal.new(), -- () parcelle, vitrines ou résultat d'une action de musée
	TutorialChanged = Signal.new(), -- (step, propId)
	AttemptChanged = Signal.new(), -- (active: boolean)
	Toast = Signal.new(), -- (text, kind)
}

function ClientState.applyCollectionSnapshot(view: any)
	ClientState.summary = view
	ClientState.specimens = {}
	ClientState.specimensById = {}
	for _, specimen in view.specimens or {} do
		table.insert(ClientState.specimens, specimen)
		ClientState.specimensById[specimen.id] = specimen
	end
	view.specimens = nil
	ClientState.CollectionChanged:Fire("snapshot", nil)
end

function ClientState.applyCollectionDelta(delta: any)
	if delta.summary then
		ClientState.summary = delta.summary
	end
	local added = delta.added
	if added and ClientState.specimensById[added.id] == nil then
		table.insert(ClientState.specimens, 1, added)
		ClientState.specimensById[added.id] = added
		ClientState.CollectionChanged:Fire("added", added)
	elseif delta.summary then
		ClientState.CollectionChanged:Fire("summary", nil)
	end
end

function ClientState.applySpecimenUpdate(updated: any)
	local current = ClientState.specimensById[updated.id]
	if current == nil then
		return
	end
	for k, v in updated do
		current[k] = v
	end
	ClientState.CollectionChanged:Fire("updated", current)
end

-- Nombre d'exemplaires possédés d'une espèce.
function ClientState.ownedCount(speciesId: string): number
	local n = 0
	for _, specimen in ClientState.specimens do
		if specimen.speciesId == speciesId then
			n += 1
		end
	end
	return n
end

function ClientState.mimicAtProp(propId: string): MimicInfo?
	for _, info in ClientState.mimics do
		if info.propId == propId and info.state ~= "Hidden" and info.state ~= "Captured" then
			return info
		end
	end
	return nil
end

function ClientState.myRevealedMimic(): MimicInfo?
	for _, info in ClientState.mimics do
		if info.ownerUserId == ClientState.userId and info.state == "Revealed" then
			return info
		end
	end
	return nil
end

function ClientState.applyUpdate(payload: any)
	local previous = ClientState.mimics[payload.mimicId]
	local info: MimicInfo = {
		mimicId = payload.mimicId,
		propId = payload.propId or (previous and previous.propId) or "",
		speciesId = payload.speciesId or (previous and previous.speciesId),
		state = payload.state,
		ownerUserId = payload.ownerUserId,
		expiresAt = if type(payload.remaining) == "number" then os.clock() + payload.remaining else nil,
	}
	if info.state == "Hidden" or info.state == "Captured" then
		ClientState.mimics[info.mimicId] = nil
	else
		ClientState.mimics[info.mimicId] = info
	end
	ClientState.MimicChanged:Fire(info, if previous then previous.state else nil)
end

function ClientState.toast(text: string, kind: string?)
	ClientState.Toast:Fire(text, kind or "info")
end

return ClientState
