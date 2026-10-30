--!strict
-- Audio — lecture des sons locaux (interface) ou positionnés (objets).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local Audio = {}

local function make(name: string, speedMultiplier: number?): Sound?
	local spec = Sounds[name]
	if spec == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed * (speedMultiplier or 1)
	return sound
end

-- Son d'interface (non spatialisé).
function Audio.play(name: string, speedMultiplier: number?)
	local sound = make(name, speedMultiplier)
	if sound then
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

-- Son 3D attaché à une part (indices sonores des Mimics).
function Audio.playAt(part: BasePart, name: string, speedMultiplier: number?)
	local sound = make(name, speedMultiplier)
	if sound then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 6
		sound.RollOffMaxDistance = 55
		sound.Parent = part
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

return Audio
