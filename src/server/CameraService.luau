-- Камеры наблюдения на сервере: вор-взломщик ломает камеру (атрибут Broken у точки камеры —
-- клиенты показывают «NO SIGNAL»), игрок перезапускает все камеры на пульте в диспетчерской (держать F).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))

local CameraService = {}

local points: { BasePart } = {}
local repairPrompt: ProximityPrompt? = nil
local hallCenters: { [string]: Vector3 } = {}

local function anyBroken(): boolean
	for _, point in points do
		if point:GetAttribute("Broken") == true then
			return true
		end
	end
	return false
end

local function refreshPrompt()
	if repairPrompt then
		repairPrompt.Enabled = anyBroken()
	end
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

-- Где встать вору под камерой: на полу, чуть ближе к середине зала.
function CameraService.standPoint(point: BasePart): Vector3
	local hall = point:GetAttribute("Hall")
	local center = hallCenters[if typeof(hall) == "string" then hall else GameState.Hall.Main] or Vector3.zero
	local flat = Vector3.new(point.Position.X, 3, point.Position.Z)
	local toCenter = Vector3.new(center.X - flat.X, 0, center.Z - flat.Z)
	local inset = Config.CameraBreaker.StandInset
	return if toCenter.Magnitude > inset then flat + toCenter.Unit * inset else flat
end

function CameraService.breakCamera(point: BasePart)
	if CameraService.isBroken(point) then
		return
	end
	point:SetAttribute("Broken", true)
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
	local geometry = map:FindFirstChild(MapSchema.Geometry)
	if geometry then
		for _, part in geometry:GetChildren() do
			local hall = part:GetAttribute("Hall")
			if part:IsA("BasePart") and typeof(hall) == "string" then
				hallCenters[hall] = part.Position
			end
		end
	end

	local console = map:FindFirstChild(MapSchema.ControlConsole, true)
	if console and console:IsA("BasePart") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RepairPrompt"
		prompt.ActionText = "Restart cameras"
		prompt.ObjectText = "Some cameras are offline"
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = Config.Cameras.RepairHoldSeconds
		prompt.MaxActivationDistance = Config.Cameras.ConsolePromptDistance
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(0, 90) -- ниже кнопки «Watch cameras»
		prompt.Enabled = false
		prompt.Parent = console
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
			if (root.Position - console.Position).Magnitude > maxDistance then
				return
			end
			CameraService.repairAll()
			Remotes.get(Remotes.Names.Banner):FireAllClients("CAMERAS ARE BACK ONLINE", "info")
		end)
		repairPrompt = prompt
	end
end

return CameraService
