--!strict
-- Эффекты боя на клиенте (блок 4): трассер пули, вспышка у ствола, искры и пыль на месте попадания,
-- провода шокера с разрядом, звуки выстрелов. Только картинка: кто попал и сколько ранил, решает сервер.
-- Без крови: попадание в грабителя — белая вспышка-звёздочка.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Weapons = Config.Weapons
local Sounds = Config.Sounds

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "LocalFx"
folder.Parent = Workspace

local function quietPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	return part
end

local function fade(part: BasePart, seconds: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, seconds + 0.05)
end

-- Трассер: светящаяся полоска от ствола до точки попадания, гаснет за доли секунды.
function Fx.tracer(from: Vector3, to: Vector3, color: Color3?, width: number?)
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.5 then
		return
	end
	-- Короткий «хвост», летящий к цели, читается лучше, чем линия на всю длину
	local w = width or Weapons.TracerWidth
	local piece = math.min(length, 18)
	local start = from + offset.Unit * math.max(0, length - piece) * 0.15
	local part = quietPart("Tracer", Vector3.new(w, w, piece), CFrame.lookAt(start, to) * CFrame.new(0, 0, -piece / 2), color or Weapons.TracerColor)
	part.Transparency = 0.15
	TweenService:Create(part, TweenInfo.new(Weapons.TracerSeconds, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to - offset.Unit * piece, to) * CFrame.new(0, 0, -piece / 2),
	}):Play()
	fade(part, Weapons.TracerSeconds * 1.6)
end

-- Вспышка у ствола: яркий шарик и короткий свет.
function Fx.muzzleFlash(at: CFrame, scale: number?)
	local s = scale or 1
	local flash = quietPart("MuzzleFlash", Vector3.new(0.45, 0.45, 0.7) * s, at * CFrame.new(0, 0, -0.25 * s), Color3.fromHex("FFD27A"))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = flash
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FFC266")
	light.Range = 10 * s
	light.Brightness = 3
	light.Parent = flash
	fade(flash, 0.06)
	Debris:AddItem(light, 0.05)
end

-- Попадание: в стену — искры и облачко пыли; в грабителя — белая звёздочка (без крови).
function Fx.impact(position: Vector3, onTarget: boolean)
	if onTarget then
		local star = quietPart("HitStar", Vector3.new(0.3, 0.3, 0.3), CFrame.new(position), Color3.new(1, 1, 1))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = star
		fade(star, Weapons.ImpactSeconds, Vector3.new(1.4, 1.4, 1.4))
		return
	end
	local dust = quietPart("Dust", Vector3.new(0.3, 0.3, 0.3), CFrame.new(position), Color3.fromHex("BFB6A3"))
	dust.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = dust
	dust.Transparency = 0.3
	fade(dust, Weapons.ImpactSeconds * 1.4, Vector3.new(1, 1, 1))
	local holder = quietPart("Sparks", Vector3.new(0.1, 0.1, 0.1), CFrame.new(position), Color3.new(1, 1, 1))
	holder.Transparency = 1
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromHex("FFE7A0"), Color3.fromHex("FF9A3C"))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.1, 0.25)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 0
	sparks.Parent = holder
	sparks:Emit(7)
	Debris:AddItem(holder, 0.5)
end

-- Провода шокера: две ломаные голубые линии от электродов до цели, мерцают и гаснут.
function Fx.wire(from: Vector3, to: Vector3, color: Color3?)
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.5 then
		return
	end
	local basis = CFrame.lookAt(from, to)
	for side = -1, 1, 2 do
		local points = {}
		local segments = math.clamp(math.floor(length / 2), 4, 14)
		for index = 0, segments do
			local t = index / segments
			local jitter = if index == 0 or index == segments then Vector3.zero
				else Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.5
			points[index] = (basis * CFrame.new(side * 0.06 * (1 - t) + jitter.X, jitter.Y, -length * t)).Position
		end
		for index = 1, segments do
			local a, b = points[index - 1], points[index]
			local piece = (b - a).Magnitude
			local part = quietPart("TaserWire", Vector3.new(0.05, 0.05, piece), CFrame.lookAt(a, b) * CFrame.new(0, 0, -piece / 2), color or Weapons.Taser.Color)
			fade(part, 0.35)
		end
	end
	Fx.impact(to, true)
end

local function bindEffects(sound: Sound)
	local group = SoundService:FindFirstChild("Effects")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
end

-- Звук выстрела. at — где (3D, слышно издалека); nil — у самого игрока (свой выстрел).
function Fx.shotSound(weapon: string, at: Vector3?)
	local info = (Sounds.Shots :: any)[weapon]
	if not info or info.Id == "" then
		return
	end
	local parent: Instance
	if at then
		local holder = quietPart("ShotSound", Vector3.new(0.1, 0.1, 0.1), CFrame.new(at), Color3.new(1, 1, 1))
		holder.Transparency = 1
		Debris:AddItem(holder, 3)
		parent = holder
	else
		parent = folder
	end
	local sound = Instance.new("Sound")
	sound.SoundId = info.Id
	sound.Volume = info.Volume
	sound.PlaybackSpeed = info.Speed * (0.95 + math.random() * 0.1)
	sound.RollOffMaxDistance = Sounds.ShotRollOff
	bindEffects(sound)
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- Звук действия только у этого игрока (аптечка, бронежилет, отвёртка — этап 8, блок O). Пустой адрес — тишина.
function Fx.sound(id: string, volume: number?)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or Sounds.ActionVolume
	bindEffects(sound)
	sound.Parent = folder
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Короткий щелчок (перезарядка, пустой магазин, попадание): только у этого игрока.
function Fx.click(speed: number, volume: number?)
	if Sounds.Click == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Sounds.Click
	sound.Volume = volume or Sounds.ClickVolume
	sound.PlaybackSpeed = speed
	bindEffects(sound)
	sound.Parent = folder
	sound:Play()
	Debris:AddItem(sound, 2)
end

return Fx
