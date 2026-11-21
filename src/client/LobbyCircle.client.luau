-- Круг START SHIFT в лобби (блок B1): цвет круга и табличка над ним — «Team N/5», имена, отсчёт.
-- Кто в команде, решает сервер (LobbyService): атрибут игрока InTeam и таймер фазы. Здесь только показываем.
-- Команда полная, а ты не в ней — круг для тебя красный. Пока команда на смене — круг серый.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors
local Settings = Config.Lobby

local localPlayer = Players.LocalPlayer
local map = Workspace:WaitForChild(MapSchema.Root)
local circle = map:WaitForChild(MapSchema.StartCircle) :: BasePart
local glow = circle:FindFirstChildOfClass("PointLight")

-- Мягкое мерцание круга (только у этого игрока, на сервере круг не меняется)
TweenService:Create(circle, TweenInfo.new(Settings.PulseSeconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Transparency = Settings.PulseTransparency,
}):Play()

---------------------------------------------------------------- табличка над кругом

local billboard = Theme.new("BillboardGui", {
	Name = "StartShiftLabel",
	Adornee = circle,
	Size = UDim2.fromScale(11, 6.5), -- в стадах: табличка уменьшается вместе с расстоянием
	StudsOffset = Vector3.new(0, Settings.LabelHeight, 0),
	LightInfluence = 0,
	MaxDistance = Settings.LabelMaxDistance,
	Parent = circle,
})

local panel = Theme.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.2,
	Parent = billboard,
}, { Theme.corner(16), Theme.stroke(Colors.Gold, 3) })
Theme.padding(8).Parent = panel

local titleLabel = Theme.label({
	Text = "START SHIFT",
	TextColor3 = Colors.Gold,
	Size = UDim2.fromScale(1, 0.22),
	MaxTextSize = 60,
	Parent = panel,
})
local teamLabel = Theme.label({
	Position = UDim2.fromScale(0, 0.23),
	Size = UDim2.fromScale(1, 0.16),
	MaxTextSize = 44,
	Parent = panel,
})
local namesLabel = Theme.label({
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	Position = UDim2.fromScale(0, 0.41),
	Size = UDim2.fromScale(1, 0.42),
	TextYAlignment = Enum.TextYAlignment.Top,
	MaxTextSize = 30,
	Parent = panel,
})
local statusLabel = Theme.label({
	Position = UDim2.fromScale(0, 0.85),
	Size = UDim2.fromScale(1, 0.15),
	MaxTextSize = 36,
	Parent = panel,
})

---------------------------------------------------------------- обновление

local currentColor: Color3? = nil

local function setColor(color: Color3)
	if currentColor == color then
		return
	end
	currentColor = color
	circle.Color = color
	if glow then
		glow.Color = color
	end
end

local function refresh()
	local phase = GameState.phase()
	if phase ~= Phase.Lobby then
		-- Команда на смене: круг не работает, опоздавшие ждут голосования
		setColor(Settings.IdleColor)
		titleLabel.Text = "START SHIFT"
		teamLabel.Text = "The team is on shift"
		namesLabel.Text = ""
		statusLabel.Text = ""
		return
	end

	local team = GameState.lobbyTeam()
	local inTeam = localPlayer:GetAttribute(PlayerAttr.InTeam) == true
	local full = #team >= Config.Players.Max
	setColor(if full and not inTeam then Settings.FullColor else Settings.Color)

	teamLabel.Text = ("Team %d/%d"):format(#team, Config.Players.Max)
	local names = {}
	for _, player in team do
		table.insert(names, ("%s (%s)"):format(player.DisplayName, tostring(player:GetAttribute(PlayerAttr.Role) or "Patrol")))
	end
	namesLabel.Text = table.concat(names, "\n")

	local left = GameState.secondsLeft()
	if full and not inTeam then
		statusLabel.Text = "TEAM FULL"
		statusLabel.TextColor3 = Colors.Red
	elseif #team > 0 and left > 0 then
		statusLabel.Text = ("Starting in %d"):format(math.ceil(left))
		statusLabel.TextColor3 = Colors.Gold
	else
		statusLabel.Text = "Stand here to join"
		statusLabel.TextColor3 = Colors.White
	end
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	refresh()
end)
refresh()
