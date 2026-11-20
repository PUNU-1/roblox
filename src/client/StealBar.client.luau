-- Полоска кражи над Моной Лизой: пока вор снимает картину, она заполняется красным.
-- Сквозь стены её не видно — заметит тот, кто рядом, или оператор на камере.
-- Сервер пишет в GameState время, когда вор снимет картину (StealEndsAt), клиент только рисует.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Colors = Theme.Colors
local Bar = Config.Effects.StealBar

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local map = Workspace:WaitForChild(MapSchema.Root)
local painting = map:WaitForChild(MapSchema.Exhibits):WaitForChild(MapSchema.Models.MonaLisa)

-- Самая большая деталь картины (рама): над ней и висит полоска.
local function biggestPart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end
	local best: BasePart? = nil
	local bestVolume = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if volume > bestVolume then
				best = descendant
				bestVolume = volume
			end
		end
	end
	return best
end

local frame = biggestPart(painting)
if not frame then
	warn("[StealBar] У картины нет деталей — полоски кражи не будет")
	return
end

local billboard = Theme.new("BillboardGui", {
	Name = "StealBar",
	Adornee = frame,
	Size = UDim2.new(Bar.Width, 0, Bar.Height, 0), -- в стадах: вдали полоска меньше, как настоящая
	StudsOffsetWorldSpace = Vector3.new(0, frame.Size.Y / 2 + Bar.Gap, 0),
	MaxDistance = Bar.MaxDistance,
	AlwaysOnTop = false, -- стены её закрывают
	LightInfluence = 0,
	ResetOnSpawn = false,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

local background = Theme.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.2,
	Parent = billboard,
}, { Theme.corner(8), Theme.stroke(Colors.Red, 2) })

local fill = Theme.new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Colors.Red,
	Parent = background,
}, { Theme.corner(8) })

local label = Theme.label({ Size = UDim2.fromScale(1, 1), Text = "STEALING!", ZIndex = 2, MaxTextSize = 100, Parent = background })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = label })

local connection = RunService.Heartbeat:Connect(function()
	local endsAt = GameState.get(GameState.Attr.StealEndsAt)
	local left = if typeof(endsAt) == "number" and endsAt > 0 then endsAt - Workspace:GetServerTimeNow() else 0
	billboard.Enabled = left > 0
	if left > 0 then
		fill.Size = UDim2.fromScale(math.clamp(1 - left / Config.Thief.StealSeconds, 0, 1), 1)
	end
end)

-- Если карту пересоздадут, старая полоска больше не нужна
painting.AncestryChanged:Connect(function()
	if not painting:IsDescendantOf(Workspace) then
		connection:Disconnect()
		billboard:Destroy()
	end
end)
