-- Двери, которые открываются сами (блок 2): 4 двери входов, 4 двери центра (этап 5, блок B) и дверь STAFF ONLY.
-- Сервер раз в CheckSeconds смотрит, есть ли рядом с дверью кто-нибудь (охрана, вор, турист),
-- и пишет атрибут Open у модели двери. Створки плавно двигает каждый клиент (Doors.client).
-- Створки не твёрдые: дверь всегда успевает открыться, а пути воров и туристов она не загораживает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Settings = Config.Doors
local OPEN = GameState.DoorAttr.Open

local DoorService = {}

type Door = {
	model: Model,
	center: Vector3,
	lastSeen: number, -- когда рядом последний раз кто-то был
}

local doors: { Door } = {}
local connection: RBXScriptConnection? = nil

-- Где сейчас все, кто может пройти в дверь.
local function walkerPositions(): { Vector3 }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(list, root.Position)
		end
	end
	for _, folderName in { MapSchema.Thieves, MapSchema.Tourists } do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, npc in folder:GetChildren() do
				local root = npc:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					table.insert(list, root.Position)
				end
			end
		end
	end
	return list
end

local function update()
	local now = os.clock()
	local positions = walkerPositions()
	local radius = Settings.OpenRadius
	for _, door in doors do
		for _, position in positions do
			local offset = position - door.center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < radius and math.abs(offset.Y) < 12 then
				door.lastSeen = now
				break
			end
		end
		local open = now - door.lastSeen < Settings.CloseDelay
		local wing = door.model:GetAttribute(GameState.DoorAttr.Wing)
		if typeof(wing) == "string" and GameState.isHallOpen(wing) then
			open = true -- дверь центра купленного крыла — просто арка (этап 5, блок B)
		end
		if door.model:GetAttribute(OPEN) ~= open then
			door.model:SetAttribute(OPEN, open)
		end
	end
end

function DoorService.init(map: Instance)
	local folder = map:FindFirstChild(MapSchema.Doors)
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				model:SetAttribute(OPEN, false)
				table.insert(doors, { model = model, center = model:GetPivot().Position, lastSeen = -math.huge })
			end
		end
	end
	if connection then
		connection:Disconnect()
	end
	local accumulator = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Settings.CheckSeconds then
			accumulator = 0
			update()
		end
	end)
end

return DoorService
