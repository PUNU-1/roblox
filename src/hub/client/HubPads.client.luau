-- Круги-команды хаба (блок 6): цвет каждого круга и табличка над ним — номер, «Team N/5», имена
-- (у создателя ★), FRIENDS ONLY и отсчёт. Кто в команде, решает сервер (PadService): атрибуты круга
-- (GameState.PadAttr) и атрибут игрока Pad. Здесь только показываем.

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

local PadAttr = GameState.PadAttr
local PadState = GameState.PadState
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors
local Settings = Config.Hub

local localPlayer = Players.LocalPlayer
local map = Workspace:WaitForChild(MapSchema.Root)
local folder = map:WaitForChild(MapSchema.TeamPads)

type PadView = {
	part: BasePart,
	glow: PointLight?,
	color: Color3?,
	title: TextLabel,
	friends: Frame,
	team: TextLabel,
	names: TextLabel,
	status: TextLabel,
}

local views: { PadView } = {}

local function buildView(part: BasePart, index: number): PadView
	-- Мягкое мерцание круга (только у этого игрока)
	TweenService:Create(part, TweenInfo.new(Settings.PulseSeconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = Settings.PulseTransparency,
	}):Play()

	local billboard = Theme.new("BillboardGui", {
		Name = "TeamLabel",
		Adornee = part,
		Size = UDim2.fromScale(11, 7), -- в стадах: табличка уменьшается вместе с расстоянием
		StudsOffset = Vector3.new(0, Settings.LabelHeight, 0),
		LightInfluence = 0,
		MaxDistance = Settings.LabelMaxDistance,
		Parent = part,
	})
	local panel = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Navy,
		BackgroundTransparency = 0.2,
		Parent = billboard,
	}, { Theme.corner(16), Theme.stroke(Colors.Gold, 3) })
	Theme.padding(8).Parent = panel

	local title = Theme.label({
		Text = ("TEAM %d"):format(index),
		TextColor3 = Colors.Gold,
		Size = UDim2.fromScale(1, 0.2),
		MaxTextSize = 60,
		Parent = panel,
	})
	-- Ярлык FRIENDS ONLY (виден, когда создатель включил)
	local friends = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.21),
		Size = UDim2.fromScale(0.62, 0.1),
		BackgroundColor3 = Settings.FriendsColor,
		Visible = false,
		Parent = panel,
	}, { Theme.corner(10) })
	Theme.label({ Size = UDim2.fromScale(1, 1), Text = "FRIENDS ONLY", MaxTextSize = 28, Parent = friends })
	local team = Theme.label({
		Position = UDim2.fromScale(0, 0.32),
		Size = UDim2.fromScale(1, 0.14),
		MaxTextSize = 44,
		Parent = panel,
	})
	local names = Theme.label({
		Font = Theme.BodyFont,
		TextColor3 = Colors.Marble,
		Position = UDim2.fromScale(0, 0.47),
		Size = UDim2.fromScale(1, 0.38),
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 28,
		Parent = panel,
	})
	local status = Theme.label({
		Position = UDim2.fromScale(0, 0.86),
		Size = UDim2.fromScale(1, 0.14),
		MaxTextSize = 34,
		Parent = panel,
	})
	return {
		part = part,
		glow = part:FindFirstChildOfClass("PointLight"),
		color = nil,
		title = title,
		friends = friends,
		team = team,
		names = names,
		status = status,
	}
end

local function setColor(view: PadView, color: Color3)
	if view.color == color then
		return
	end
	view.color = color
	view.part.Color = color
	local glow = view.glow
	if glow then
		glow.Color = color
	end
end

local function refresh(view: PadView)
	local part = view.part
	local ids = GameState.padTeam(part)
	local state = part:GetAttribute(PadAttr.State)
	local friendsOnly = part:GetAttribute(PadAttr.FriendsOnly) == true
	local mine = table.find(ids, localPlayer.UserId) ~= nil
	local full = #ids >= Config.Players.Max

	-- Цвет: твой круг — зелёный, улетает — жёлтый, не работает — серый,
	-- полный или «только друзья» (а ты не в команде) — красный или фиолетовый
	if state == PadState.Launching then
		setColor(view, Settings.LaunchColor)
	elseif state == PadState.Blocked then
		setColor(view, Settings.BlockedColor)
	elseif mine then
		setColor(view, Settings.MineColor)
	elseif full then
		setColor(view, Settings.FullColor)
	elseif friendsOnly and #ids > 0 then
		setColor(view, Settings.FriendsColor)
	else
		setColor(view, Settings.Color)
	end

	view.friends.Visible = friendsOnly and #ids > 0
	view.team.Text = ("Team %d/%d"):format(#ids, Config.Players.Max)
	local names = {}
	for index, id in ids do
		local player = Players:GetPlayerByUserId(id)
		local name = if player then player.DisplayName else "Guard"
		table.insert(names, if index == 1 then "★ " .. name else name)
	end
	view.names.Text = table.concat(names, "\n")

	local status = view.status
	local message = part:GetAttribute(PadAttr.Message)
	local endsAt = tonumber(part:GetAttribute(PadAttr.EndsAt)) or 0
	local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
	if (state == PadState.Launching or state == PadState.Blocked) and typeof(message) == "string" and message ~= "" then
		status.Text = message
		status.TextColor3 = if state == PadState.Launching then Colors.Gold else Colors.Red
	elseif full and not mine then
		status.Text = "TEAM FULL"
		status.TextColor3 = Colors.Red
	elseif friendsOnly and #ids > 0 and not mine then
		local creator = Players:GetPlayerByUserId(ids[1])
		status.Text = ("Friends of %s only"):format(if creator then creator.DisplayName else "the leader")
		status.TextColor3 = Settings.FriendsColor:Lerp(Colors.White, 0.35)
	elseif #ids > 0 and endsAt > 0 then
		status.Text = ("Starting in %d"):format(math.ceil(left))
		status.TextColor3 = Colors.Gold
	elseif #ids > 0 then
		status.Text = "Starting..."
		status.TextColor3 = Colors.Gold
	else
		status.Text = "Stand here to start a team"
		status.TextColor3 = Colors.White
	end
end

for index = 1, Settings.Pads do
	local part = folder:WaitForChild(MapSchema.TeamPadPrefix .. index) :: BasePart
	table.insert(views, buildView(part, index))
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	for _, view in views do
		refresh(view)
	end
end)
for _, view in views do
	refresh(view)
end

-- Свой круг виден в атрибуте Pad — сразу перерисовать цвет, не ждать 0,1 сек
localPlayer:GetAttributeChangedSignal(PlayerAttr.Pad):Connect(function()
	for _, view in views do
		refresh(view)
	end
end)
