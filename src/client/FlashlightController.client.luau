-- Фонарик (решение 57). Ночью в залах темно, у каждого охранника на смене горит фонарик.
--  • Свой фонарик светит туда, куда смотришь (от первого лица — из камеры), с тенями.
--  • Фонарики других охранников тоже видно: свет из головы вперёд.
-- Это только картинка, на игру не влияет, поэтому живёт на клиенте. Батарейки пока нет.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local PlayerAttr = GameState.PlayerAttr
local Settings = Config.Flashlight

local localPlayer = Players.LocalPlayer
local LIGHT_NAME = "GuardFlashlight"

-- Свой фонарик: невидимая деталь у камеры, видна только этому игроку
local holder = Instance.new("Part")
holder.Name = "MyFlashlight"
holder.Size = Vector3.new(0.2, 0.2, 0.2)
holder.Transparency = 1
holder.Anchored = true
holder.CanCollide = false
holder.CanQuery = false
holder.CanTouch = false
holder.CastShadow = false

local ownLight = Instance.new("SpotLight")
ownLight.Face = Enum.NormalId.Front
ownLight.Range = Settings.Range
ownLight.Angle = Settings.Angle
ownLight.Brightness = Settings.Brightness
ownLight.Color = Settings.Color
ownLight.Shadows = true
ownLight.Enabled = false
ownLight.Parent = holder

local function onShift(player: Player): boolean
	return GameState.phase() == GameState.Phase.Night and player:GetAttribute(PlayerAttr.InRound) == true
end

local function viewingCameras(): boolean
	return localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
end

-- Фонарик в голове охранника (для других игроков, и для себя — когда смотришь камеры)
local function headLight(player: Player): SpotLight?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local light = head:FindFirstChild(LIGHT_NAME)
	if light and light:IsA("SpotLight") then
		return light
	end
	local created = Instance.new("SpotLight")
	created.Name = LIGHT_NAME
	created.Face = Enum.NormalId.Front
	created.Range = Settings.OthersRange
	created.Angle = Settings.Angle
	created.Brightness = Settings.OthersBrightness
	created.Color = Settings.Color
	created.Shadows = false
	created.Enabled = false
	created.Parent = head
	return created
end

local function refreshHeadLights()
	for _, player in Players:GetPlayers() do
		local on = onShift(player)
		if player == localPlayer then
			-- Свой свет из головы нужен, только когда смотришь камеры (иначе светит камера)
			on = on and viewingCameras()
		end
		local light = if on then headLight(player) else nil
		if light then
			light.Enabled = true
		elseif not on then
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local existing = head and head:FindFirstChild(LIGHT_NAME)
			if existing and existing:IsA("SpotLight") then
				existing.Enabled = false
			end
		end
	end
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then
		return
	end
	accumulator = 0
	refreshHeadLights()
end)

-- Свой фонарик каждый кадр идёт за камерой, чуть правее и ниже глаз — как в руке
RunService:BindToRenderStep("Flashlight", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = Workspace.CurrentCamera
	local on = onShift(localPlayer) and not viewingCameras()
	ownLight.Enabled = on and camera ~= nil
	if not on or not camera then
		return
	end
	if holder.Parent ~= camera then
		holder.Parent = camera -- деталь внутри камеры видна только этому игроку
	end
	holder.CFrame = camera.CFrame * Settings.HandOffset
end)
