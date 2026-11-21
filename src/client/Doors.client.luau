-- Плавно двигает створки дверей (входы и STAFF ONLY). Открыта дверь или нет, решает сервер
-- (DoorService, атрибут Open у модели двери); створка сдвигается вдоль своей оси X на SlideX стадов.
-- Двигаем только у себя: так плавно и без нагрузки на сеть.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local DoorAttr = GameState.DoorAttr

local map = Workspace:WaitForChild(MapSchema.Root)
local doorsFolder = map:WaitForChild(MapSchema.Doors, 60)

type Leaf = {
	model: PVInstance,
	closed: CFrame, -- где створка стоит, когда дверь закрыта (сервер её не двигает)
	slide: number,
}

local function setupDoor(door: Instance)
	if not door:IsA("Model") then
		return
	end
	local leaves: { Leaf } = {}
	for _, child in door:GetChildren() do
		local slide = child:GetAttribute(DoorAttr.SlideX)
		if child:IsA("PVInstance") and typeof(slide) == "number" then
			table.insert(leaves, { model = child, closed = child:GetPivot(), slide = slide })
		end
	end
	if #leaves == 0 then
		return
	end

	local progress = Instance.new("NumberValue") -- 0 — закрыта, 1 — открыта
	progress.Value = if door:GetAttribute(DoorAttr.Open) == true then 1 else 0
	local function apply()
		for _, leaf in leaves do
			leaf.model:PivotTo(leaf.closed * CFrame.new(leaf.slide * progress.Value, 0, 0))
		end
	end
	apply()
	progress.Changed:Connect(apply)

	local tween: Tween? = nil
	local function onOpenChanged()
		local target = if door:GetAttribute(DoorAttr.Open) == true then 1 else 0
		if tween then
			tween:Cancel()
		end
		local seconds = Config.Doors.SlideSeconds * math.abs(target - progress.Value)
		local created = TweenService:Create(progress, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = target })
		tween = created
		created:Play()
	end
	local changed = door:GetAttributeChangedSignal(DoorAttr.Open):Connect(onOpenChanged)
	door.Destroying:Connect(function()
		changed:Disconnect()
		if tween then
			tween:Cancel()
		end
		progress:Destroy()
	end)
end

if doorsFolder then
	for _, door in doorsFolder:GetChildren() do
		setupDoor(door)
	end
	doorsFolder.ChildAdded:Connect(setupDoor)
end
