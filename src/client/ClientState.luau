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

local ClientState = {
	userId = Players.LocalPlayer.UserId,
	mimics = {} :: { [string]: MimicInfo },
	inventory = nil :: any,
	tutorialStep = "Done",
	tutorialPropId = nil :: string?,
	attemptActive = false,

	MimicChanged = Signal.new(), -- (info: MimicInfo, previousState: string?)
	InventoryChanged = Signal.new(), -- (snapshot)
	TutorialChanged = Signal.new(), -- (step, propId)
	AttemptChanged = Signal.new(), -- (active: boolean)
	Toast = Signal.new(), -- (text, kind)
}

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
