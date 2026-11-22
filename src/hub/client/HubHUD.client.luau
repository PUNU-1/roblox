-- Экран хаба (блок 6): верхняя строка (что делать сейчас), карточки классов (клавиши 1–5, на телефоне — пальцем),
-- панель создателя команды (START — F, Friends only — G, на телефоне — кнопки), крупные надписи и затемнение
-- «Teleporting to the museum». Клиент только показывает и шлёт намерения; всё решает сервер (PadService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ClassCards = require(UI:WaitForChild("ClassCards"))

local PadAttr = GameState.PadAttr
local PadState = GameState.PadState
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local map = Workspace:WaitForChild(MapSchema.Root)
local padFolder = map:WaitForChild(MapSchema.TeamPads)
local gui = Theme.screenGui("HubHUD", 1)

-- На телефоне и планшете без клавиатуры вместо клавиш — кнопки на экране
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Свой круг и его состояние (nil — не в команде).
local function myPad(): BasePart?
	local index = tonumber(localPlayer:GetAttribute(PlayerAttr.Pad)) or 0
	if index <= 0 then
		return nil
	end
	local pad = padFolder:FindFirstChild(MapSchema.TeamPadPrefix .. index)
	return if pad and pad:IsA("BasePart") then pad else nil
end

local function isCreator(pad: BasePart): boolean
	return GameState.padTeam(pad)[1] == localPlayer.UserId
end

local function launching(): boolean
	local pad = myPad()
	return pad ~= nil and pad:GetAttribute(PadAttr.State) == PadState.Launching
end

---------------------------------------------------------------- верхняя строка

local topBar = Theme.new("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0.55, 0, 0, 46),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Theme.corner(12), Theme.stroke(Colors.Gold, 2), Theme.new("UISizeConstraint", { MinSize = Vector2.new(320, 0) }) })
local topLabel = Theme.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 26, Parent = topBar })
Theme.padding(6).Parent = topBar

---------------------------------------------------------------- алмазы 💎 (этап 4, блок 1)
-- Справа вверху: сколько алмазов (сохраняются навсегда). В Studio без доступа к API — пометка, что не сохраняются.

local diamondFrame = Theme.new("Frame", {
	Name = "Diamonds",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(150, 46),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Theme.corner(12), Theme.stroke(Colors.Diamond, 2) })
local diamondLabel = Theme.label({ Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Diamond, Text = "💎 0", MaxTextSize = 30, Parent = diamondFrame })
Theme.padding(6).Parent = diamondFrame
local diamondNote = Theme.label({
	Name = "DiamondNote",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 62),
	Size = UDim2.fromOffset(240, 18),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	TextXAlignment = Enum.TextXAlignment.Right,
	MaxTextSize = 14,
	Visible = false,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1.5, Parent = diamondNote })

local function refreshDiamonds()
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	if status == ProfileStatus.Loading or status == nil then
		diamondLabel.Text = "💎 ..."
	else
		diamondLabel.Text = "💎 " .. tostring(GameState.diamondsOf(localPlayer))
	end
	if status == ProfileStatus.Offline then
		diamondNote.Text = "Diamonds are not saved in Studio"
	elseif status == ProfileStatus.Error then
		diamondNote.Text = "Diamonds are unavailable — trying again"
	else
		diamondNote.Text = ""
	end
	diamondNote.Visible = diamondNote.Text ~= ""
end

---------------------------------------------------------------- крупная надпись

local banner = Theme.label({
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.14, 0),
	Size = UDim2.new(0.8, 0, 0, 60),
	TextColor3 = Colors.Gold,
	MaxTextSize = 48,
	Visible = false,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = banner })
local bannerToken = 0

local function showBanner(text: string, kind: string?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = if kind == "danger" then Colors.Red else Colors.Gold
	banner.Visible = true
	task.delay(Config.Effects.BannerSeconds + 1, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

Remotes.get(Remotes.Names.Banner).OnClientEvent:Connect(function(text, kind)
	if typeof(text) == "string" then
		showBanner(text, if typeof(kind) == "string" then kind else nil)
	end
end)

---------------------------------------------------------------- карточки классов

local CLASS_KEYS = {
	{ Enum.KeyCode.One, Enum.KeyCode.KeypadOne },
	{ Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo },
	{ Enum.KeyCode.Three, Enum.KeyCode.KeypadThree },
	{ Enum.KeyCode.Four, Enum.KeyCode.KeypadFour },
	{ Enum.KeyCode.Five, Enum.KeyCode.KeypadFive },
}

-- Сервер сам проверит, можно ли сейчас менять класс; тут только не шлём лишнего
local function chooseClass(role: string)
	if launching() or GameState.roleOf(localPlayer) == role then
		return
	end
	Remotes.get(Remotes.Names.SetRole):FireServer(role)
end

local classCards = ClassCards.new(gui, touchOnly, chooseClass)

---------------------------------------------------------------- панель создателя команды

local leader = Theme.new("Frame", {
	Name = "LeaderPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.42, 0),
	Size = UDim2.fromOffset(250, 176),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { Theme.corner(16), Theme.stroke(Colors.Gold, 2), Theme.padding(12) })
local leaderTitle = Theme.label({
	Size = UDim2.new(1, 0, 0, 26),
	TextColor3 = Colors.Gold,
	MaxTextSize = 24,
	Parent = leader,
})
Theme.label({
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 18),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	Text = "You stepped in first — you lead",
	MaxTextSize = 14,
	Parent = leader,
})
local startButton = Theme.button({
	Name = "Start",
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = Colors.Green,
	Text = if touchOnly then "START NOW" else "START NOW  [F]",
	MaxTextSize = 24,
	Parent = leader,
})
local friendsButton = Theme.button({
	Name = "FriendsOnly",
	Position = UDim2.fromOffset(0, 108),
	Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = Colors.NavyLight,
	MaxTextSize = 20,
	Parent = leader,
})
Theme.stroke(Config.Hub.FriendsColor, 2).Parent = friendsButton

local function pressStart()
	local pad = myPad()
	if pad and isCreator(pad) and pad:GetAttribute(PadAttr.State) == PadState.Open then
		Remotes.get(Remotes.Names.PadAction):FireServer("Start")
	end
end

local function toggleFriends()
	local pad = myPad()
	if pad and isCreator(pad) and pad:GetAttribute(PadAttr.State) ~= PadState.Launching then
		Remotes.get(Remotes.Names.PadAction):FireServer("FriendsOnly", pad:GetAttribute(PadAttr.FriendsOnly) ~= true)
	end
end

startButton.Activated:Connect(pressStart)
friendsButton.Activated:Connect(toggleFriends)

---------------------------------------------------------------- затемнение при телепорте

local overlay = Theme.new("Frame", {
	Name = "Teleporting",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.25,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})
Theme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.new(0.8, 0, 0, 64),
	Text = "TELEPORTING TO THE MUSEUM...",
	TextColor3 = Colors.Gold,
	MaxTextSize = 52,
	ZIndex = 10,
	Parent = overlay,
})
local overlayHint = Theme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.new(0.7, 0, 0, 30),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 24,
	ZIndex = 10,
	Parent = overlay,
})

---------------------------------------------------------------- клавиши

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Keys.Action then
		pressStart()
		return
	elseif input.KeyCode == Enum.KeyCode.G then
		toggleFriends()
		return
	end
	for index, keys in CLASS_KEYS do
		local role = Config.Classes.Order[index]
		if role and table.find(keys, input.KeyCode) then
			chooseClass(role)
			return
		end
	end
end)

---------------------------------------------------------------- обновление

local function topText(pad: BasePart?): string
	if not pad then
		return if touchOnly
			then "Step into a glowing circle to start a team   •   Tap a card to pick your class"
			else "Step into a glowing circle to start a team   •   Keys 1–5 — your class"
	end
	local index = tonumber(pad:GetAttribute(PadAttr.Index)) or 0
	local ids = GameState.padTeam(pad)
	local state = pad:GetAttribute(PadAttr.State)
	local message = pad:GetAttribute(PadAttr.Message)
	if state == PadState.Launching then
		return "Teleporting to the museum..."
	elseif state == PadState.Blocked and typeof(message) == "string" then
		return message
	end
	local endsAt = tonumber(pad:GetAttribute(PadAttr.EndsAt)) or 0
	local left = Theme.formatTime(math.max(0, endsAt - Workspace:GetServerTimeNow()))
	if isCreator(pad) then
		return ("You lead Team %d (%d/%d)   •   Starting in %s"):format(index, #ids, Config.Players.Max, left)
	end
	return ("You're in Team %d (%d/%d)   •   Starting in %s"):format(index, #ids, Config.Players.Max, left)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0

	refreshDiamonds()
	local pad = myPad()
	topLabel.Text = topText(pad)
	local flying = pad ~= nil and pad:GetAttribute(PadAttr.State) == PadState.Launching
	overlay.Visible = flying
	if flying then
		local info = GameState.classInfo(GameState.roleOf(localPlayer))
		overlayHint.Text = ("Your class: %s"):format(if info then tostring(info.Title) else "Patrol")
	end

	classCards.setVisible(not flying)
	if not flying then
		classCards.refresh(GameState.roleOf(localPlayer))
	end

	local leading = pad ~= nil and isCreator(pad) and not flying
	leader.Visible = leading
	if pad and leading then
		leaderTitle.Text = ("TEAM %d — LEADER"):format(tonumber(pad:GetAttribute(PadAttr.Index)) or 0)
		local open = pad:GetAttribute(PadAttr.State) == PadState.Open
		startButton.AutoButtonColor = open
		startButton.BackgroundTransparency = if open then 0 else 0.5
		local on = pad:GetAttribute(PadAttr.FriendsOnly) == true
		local key = if touchOnly then "" else "  [G]"
		friendsButton.Text = (if on then "FRIENDS ONLY: ON" else "FRIENDS ONLY: OFF") .. key
		friendsButton.BackgroundColor3 = if on then Config.Hub.FriendsColor else Colors.NavyLight
	end
end)
