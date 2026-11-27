-- Полоска до ближайшей награды (этап 6, блок H2, решение 86). Общий модуль: хаб (сверху по центру, HubHUD) и музей
-- (экран итога ночи, HUD). Игра сама выбирает самую близкую цель (Progress.nearestGoal): класс за алмазы, следующий
-- уровень или задание дня — «38/150 TO TECHNICIAN», «LV 7 > 8: 120/380 XP», «QUEST 3/5: ARREST 5 THIEVES».
-- Читает только атрибуты игрока (Diamonds, OwnedClasses, Xp, Quests, ProfileStatus) — пишет их сервер (ProfileStore).
-- Пока профиль грузится — не видна.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local Progress = require(Shared:WaitForChild("Progress"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))
local PixelWindow = require(script.Parent:WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus

local localPlayer = Players.LocalPlayer

local GoalBar = {}

export type Bar = {
	frame: Frame,
	height: number,
	refresh: () -> (),
	destroy: () -> (),
}

-- Профиль загружен (или Studio без API).
local function profileReady(): boolean
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	return status == ProfileStatus.Ready or status == ProfileStatus.Offline
end

-- Ближайшая награда игрока сейчас (по его атрибутам). nil — профиль не загружен или целей нет.
function GoalBar.current(): Progress.Goal?
	if not profileReady() then
		return nil
	end
	local xp = tonumber(localPlayer:GetAttribute(PlayerAttr.Xp)) or 0
	local day, quests = Progress.decodeQuests(localPlayer:GetAttribute(PlayerAttr.Quests))
	if day ~= GameState.dayNumber(Workspace:GetServerTimeNow()) then
		quests = {} -- вчерашние задания уже не в счёт
	end
	return Progress.nearestGoal(xp, quests, GameState.diamondsOf(localPlayer), function(role: string): boolean
		return GameState.ownsClass(localPlayer, role)
	end)
end

-- options.width — ширина в пикселях (по умолчанию 380), zIndex — слой рамки (по умолчанию 2).
function GoalBar.new(parent: Instance, options: { width: number?, zIndex: number? }?): Bar
	local width = options and options.width or 380
	local z = options and options.zIndex or 2
	local height = 52
	local frame = Theme.new("Frame", {
		Name = "GoalBar",
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	local inset = PixelWindow.box(frame, Colors.Navy, Colors.Gold)
	for _, child in frame:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = math.max(child.ZIndex, z)
		end
	end
	local icons: { [string]: Frame } = {}
	for _, name in { "Diamond", "Quests", "Medal" } do
		local icon = PixelIcon.new(name, true, z + 2)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, inset + 4, 0.5, 0)
		icon.Size = PixelIcon.size(name, 2)
		icon.Visible = false
		icon.Parent = frame
		icons[name] = icon
	end
	local left = inset + 4 + 32 + 8
	Theme.pixelLabel({
		Name = "Caption",
		Position = UDim2.fromOffset(left, inset + 3),
		Size = UDim2.new(1, -left - inset - 4, 0, 8),
		Text = "NEXT REWARD",
		TextColor3 = Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 2,
		Parent = frame,
	}, 8, 1)
	local track = Theme.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(left, inset + 15),
		Size = UDim2.new(1, -left - inset - 4, 0, 18),
		BackgroundColor3 = Colors.Dark,
		BorderSizePixel = 0,
		ZIndex = z + 2,
		Parent = frame,
	})
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = z + 3,
		Parent = track,
	})
	local label = Theme.pixelLabel({
		Name = "Text",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextScaled = true,
		ZIndex = z + 4,
		Parent = track,
	}, 8, 1)
	Theme.new("UITextSizeConstraint", { MaxTextSize = 8, MinTextSize = 6, Parent = label })

	local lastFraction = -1
	local function refresh()
		local goal = GoalBar.current()
		frame.Visible = goal ~= nil
		if not goal then
			return
		end
		for name, icon in icons do
			icon.Visible = name == goal.icon
		end
		label.Text = goal.text
		fill.BackgroundColor3 = if goal.ready then Colors.Green elseif goal.kind == "Class" then Colors.Diamond else Colors.Gold
		local fraction = math.clamp(goal.fraction, 0, 1)
		if fraction ~= lastFraction then
			lastFraction = fraction
			-- Плавно доезжает: видно, что стало ближе
			TweenService:Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
	end

	local connections: { RBXScriptConnection } = {}
	for _, name in { PlayerAttr.Diamonds, PlayerAttr.OwnedClasses, PlayerAttr.Xp, PlayerAttr.Quests, PlayerAttr.ProfileStatus } do
		table.insert(connections, localPlayer:GetAttributeChangedSignal(name):Connect(refresh))
	end
	refresh()

	local function destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		frame:Destroy()
	end
	return { frame = frame, height = height, refresh = refresh, destroy = destroy }
end

return GoalBar
