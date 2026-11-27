-- Уровень и звание в хабе (этап 6, блок H1, решение 85): слева сверху под кнопками Roblox — пиксельная рамка,
-- «LV 7» золотом, звание его цветом и полоска опыта «120/380 XP». Пока профиль грузится — не видна.
-- Читает атрибуты игрока (Xp, Level, ProfileStatus), пишет их только сервер (ProfileStore).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local Progress = require(Shared:WaitForChild("Progress"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus

local localPlayer = Players.LocalPlayer

local LevelBar = {}

export type Bar = {
	frame: Frame,
	height: number,
}

function LevelBar.new(parent: Instance, touchOnly: boolean): Bar
	local width = if touchOnly then 200 else 250
	local height = 56
	local frame = Theme.new("Frame", {
		Name = "LevelBar",
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local inset = PixelWindow.box(frame, Colors.Navy, Colors.Gold)
	local levelLabel = Theme.pixelLabel({
		Name = "Level",
		Position = UDim2.fromOffset(inset + 6, inset + 4),
		Size = UDim2.fromOffset(90, 16),
		TextColor3 = Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = frame,
	}, 16, 2)
	local rankLabel = Theme.pixelLabel({
		Name = "Rank",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -inset - 6, 0, inset + 8),
		Size = UDim2.new(1, -2 * inset - 100, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
		Parent = frame,
	}, 8, 1)
	local track = Theme.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(inset + 6, inset + 26),
		Size = UDim2.new(1, -2 * inset - 12, 0, 14),
		BackgroundColor3 = Colors.Dark,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = frame,
	})
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Green,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	local xpLabel = Theme.pixelLabel({
		Name = "Xp",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = track,
	}, 8, 1)

	local function refresh()
		local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
		local ready = status == ProfileStatus.Ready or status == ProfileStatus.Offline
		frame.Visible = ready
		if not ready then
			return
		end
		local xp = tonumber(localPlayer:GetAttribute(PlayerAttr.Xp)) or 0
		local level, into, need = Progress.levelOf(xp)
		local rank = Progress.rankOf(level)
		levelLabel.Text = ("LV %d"):format(level)
		rankLabel.Text = rank.Name
		rankLabel.TextColor3 = rank.Color
		fill.BackgroundColor3 = rank.Color
		local part = if need > 0 then into / need else 1
		TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(part, 1) }):Play()
		xpLabel.Text = if need > 0 then ("%d/%d XP"):format(into, need) else "MAX LEVEL"
	end

	for _, name in { PlayerAttr.Xp, PlayerAttr.ProfileStatus } do
		localPlayer:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
	return { frame = frame, height = height }
end

return LevelBar
