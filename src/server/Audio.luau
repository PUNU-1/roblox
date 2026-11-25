-- Звуки. Адреса звуков — в Config.Sounds (сейчас там временные звуки, их заменят владелец и друг).
-- Пустая строка — звука нет, ничего не играет.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Audio = {}

-- Создаёт звук. parent = деталь — звук слышно рядом с ней; parent = nil — на весь музей.
function Audio.create(id: string, parent: Instance?, volume: number?, looped: boolean?): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.Looped = looped == true
	if parent and parent:IsA("BasePart") then
		sound.RollOffMaxDistance = Config.Sounds.EffectRollOff
	end
	sound.Parent = parent or Workspace
	return sound
end

-- Проиграть один раз и удалить. maxSeconds — оборвать длинный звук раньше (например, сирену).
-- speed — выше (больше 1) или ниже тоном: так из одного звука получаются разные.
function Audio.playOnce(id: string, parent: Instance?, volume: number?, maxSeconds: number?, speed: number?)
	local sound = Audio.create(id, parent, volume, false)
	if not sound then
		return
	end
	if speed then
		sound.PlaybackSpeed = speed
	end
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(maxSeconds or 15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Сирена на весь музей (кража, лазерная сетка, сигнализация на Моне Лизе).
function Audio.alarm()
	Audio.playOnce(Config.Sounds.Alarm, nil, Config.Sounds.AlarmVolume, Config.Sounds.AlarmSeconds)
end

-- Деньги вложены (дверь зала, постамент, защита) или турист заплатил — звук кассы рядом.
function Audio.purchase(part: BasePart, volume: number?)
	Audio.playOnce(Config.Sounds.Purchase, part, volume or Config.Sounds.PurchaseVolume)
end

local music: Sound? = nil

-- Музыка на весь музей по кругу: Config.Sounds.DayMusic или NightMusic.
function Audio.startMusic(id: string)
	Audio.stopMusic()
	music = Audio.create(id, nil, Config.Sounds.MusicVolume, true)
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
