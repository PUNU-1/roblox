-- Звуки. Номера — в Config.Sounds; если номер 0, звука пока нет и ничего не играет.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Audio = {}

-- Создаёт звук. parent = деталь — звук слышно рядом с ней; parent = nil — на весь музей.
function Audio.create(id: number, parent: Instance?, volume: number?, looped: boolean?): Sound?
	if id == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = volume or 0.5
	sound.Looped = looped == true
	sound.Parent = parent or Workspace
	return sound
end

-- Проиграть один раз и удалить.
function Audio.playOnce(id: number, parent: Instance?, volume: number?)
	local sound = Audio.create(id, parent, volume, false)
	if sound then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		sound:Play()
	end
end

local music: Sound? = nil

function Audio.startMusic()
	Audio.stopMusic()
	music = Audio.create(Config.Sounds.NightMusic, nil, Config.Sounds.MusicVolume, true)
	if music then
		music:Play()
	end
end

function Audio.stopMusic()
	if music then
		music:Destroy()
		music = nil
	end
end

return Audio
