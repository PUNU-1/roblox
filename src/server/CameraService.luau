-- Камеры наблюдения на сервере: вор-взломщик ломает камеру (атрибут Broken у точки камеры —
-- клиенты показывают «NO SIGNAL»), игрок перезапускает все камеры рубильником справа от пульта
-- в диспетчерской (держать F). Пока есть сломанные камеры, лампа на рубильнике горит красным.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local CameraService = {}

local points: { BasePart } = {}
local repairPrompt: ProximityPrompt? = nil
local repairLamp: BasePart? = nil

local function anyBroken(): boolean
	for _, point in points do
		if point:GetAttribute("Broken") == true then
			return true
		end
	end
	return false
end

local function refreshPrompt()
	local broken = anyBroken()
	if repairPrompt then
		repairPrompt.Enabled = broken
	end
	if repairLamp then
		repairLamp.Color = if broken then Config.Cameras.ResetLampOnColor else Config.Cameras.ResetLampOffColor
	end
end

-- Рубильник справа от пульта (если смотреть на пульт с юга, со стороны входа в диспетчерскую).
local function buildResetSwitch(console: BasePart): BasePart
	local cameras = Config.Cameras
	local size = cameras.ResetSwitchSize
	local switch = Instance.new("Part")
	switch.Name = "CameraResetSwitch"
	switch.Anchored = true
	switch.Size = size
	switch.Color = cameras.ResetSwitchColor
	switch.Material = Enum.Material.Metal
	switch.CFrame = console.CFrame
		* CFrame.new(console.Size.X / 2 + cameras.ResetSwitchGap + size.X / 2, -console.Size.Y / 2 + size.Y / 2, 0)
	switch.Parent = console.Parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- на юг, к игроку
	gui.LightInfluence = 0
	gui.PixelsPerStud = 50
	gui.Parent = switch
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, 0.45)
	label.Size = UDim2.fromScale(0.9, 0.3)
	label.Text = "CAMERA\nRESET"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("FFFFFF")
	label.Parent = gui

	local lamp = Instance.new("Part")
	lamp.Name = "ResetLamp"
	lamp.Shape = Enum.PartType.Ball
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanTouch = false
	lamp.CastShadow = false
	lamp.Material = Enum.Material.Neon
	lamp.Color = cameras.ResetLampOffColor
	lamp.Size = Vector3.new(0.7, 0.7, 0.7)
	lamp.CFrame = switch.CFrame * CFrame.new(0, size.Y / 2 - 0.6, size.Z / 2)
	lamp.Parent = switch
	repairLamp = lamp
	return switch
end

function CameraService.isBroken(point: BasePart): boolean
	return point:GetAttribute("Broken") == true
end

-- Ближайшая рабочая камера открытого зала.
function CameraService.nearestWorking(position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, point in points do
		if not CameraService.isBroken(point) and GameState.isHallOpen(point:GetAttribute("Hall")) then
			local distance = (point.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = point, distance
			end
		end
	end
	return best
end

-- Где встать вору под камерой: на полу под кронштейном, чуть дальше от стены (StandPoint пишет MapBuilder).
function CameraService.standPoint(point: BasePart): Vector3
	local stand = point:GetAttribute(GameState.CameraAttr.StandPoint)
	if typeof(stand) == "Vector3" then
		return stand
	end
	return Vector3.new(point.Position.X, 3, point.Position.Z)
end

function CameraService.breakCamera(point: BasePart)
	if CameraService.isBroken(point) then
		return
	end
	point:SetAttribute("Broken", true)
	Audio.playOnce(Config.Sounds.CameraBreak, point, Config.Sounds.CameraBreakVolume)
	refreshPrompt()
end

function CameraService.repairAll()
	for _, point in points do
		point:SetAttribute("Broken", false)
	end
	refreshPrompt()
end

function CameraService.init(map: Instance)
	local folder = map:FindFirstChild(MapSchema.CameraPoints)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				child:SetAttribute("Broken", false)
				table.insert(points, child)
			end
		end
	end

	local console = map:FindFirstChild(MapSchema.ControlConsole, true)
	if console and console:IsA("BasePart") then
		local switch = buildResetSwitch(console)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RepairPrompt"
		prompt.ActionText = "Restart cameras"
		prompt.ObjectText = "Some cameras are offline"
		prompt.KeyboardKeyCode = Config.Keys.Action
		prompt.HoldDuration = Config.Cameras.RepairHoldSeconds
		prompt.MaxActivationDistance = Config.Cameras.ConsolePromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = switch
		prompt.Triggered:Connect(function(player)
			if not RoleService.isParticipant(player) then
				return
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				return
			end
			local maxDistance = Config.Cameras.ConsolePromptDistance + Config.Catch.ServerDistanceSlack
			if (root.Position - switch.Position).Magnitude > maxDistance then
				return
			end
			CameraService.repairAll()
			Remotes.get(Remotes.Names.Banner):FireAllClients("CAMERAS ARE BACK ONLINE", "info")
		end)
		repairPrompt = prompt
	end
end

return CameraService
