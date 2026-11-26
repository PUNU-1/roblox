-- Экран хаба (блок 6; этап 5, блок A — «как в настоящих играх», решение 75). Чистый экран:
--  • слева пиксельные кнопки без рамки и фона: SHOP, CLASSES, GIFTS, HOW TO PLAY, GROUP, FAVORITE — каждая
--    открывает своё окно (на телефоне — двумя столбиками сверху, чтобы не мешать джойстику);
--  • справа вверху — алмазы пиксельной иконкой и числом;
--  • сверху по центру — свой класс и, если стоишь в круге, команда и отсчёт;
--  • панель создателя команды (START — F, FRIENDS ONLY — G, на телефоне — кнопки) — только у создателя, пока он в круге;
--  • крупные надписи и затемнение «Teleporting to the museum».
-- Клавиши: B — магазин классов, C — окно классов (пока оно открыто — 1–5). Клиент только показывает и шлёт
-- намерения; всё решает сервер (PadService, ProfileStore).

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
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))
local ClassShop = require(script.Parent:WaitForChild("ClassShop"))
local ClassesWindow = require(script.Parent:WaitForChild("ClassesWindow"))
local HowToPlay = require(script.Parent:WaitForChild("HowToPlay"))
local Gifts = require(script.Parent:WaitForChild("Gifts"))

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
local touchOnly = Theme.touchOnly()

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

---------------------------------------------------------------- сверху по центру: класс и команда

local classLine = Theme.pixelLabel({
	Name = "ClassLine",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0.6, 0, 0, 20),
	Parent = gui,
}, 16)
local teamLine = Theme.pixelLabel({
	Name = "TeamLine",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 42),
	Size = UDim2.new(0.7, 0, 0, 20),
	TextColor3 = Colors.Gold,
	TextWrapped = true,
	Parent = gui,
}, 16)

---------------------------------------------------------------- алмазы 💎 (этап 4, блок 1)
-- Справа вверху: пиксельный алмаз и число (сохраняются навсегда). В Studio без доступа к API — пометка.

local diamondIcon = PixelIcon.new("Diamond", true, 2)
diamondIcon.AnchorPoint = Vector2.new(1, 0)
diamondIcon.Position = UDim2.new(1, -16, 0, 10)
diamondIcon.Size = PixelIcon.size("Diamond", 3)
diamondIcon.Parent = gui
local diamondLabel = Theme.pixelLabel({
	Name = "Diamonds",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -72, 0, 22),
	Size = UDim2.fromOffset(200, 26),
	Text = "0",
	TextColor3 = Colors.Diamond,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = gui,
}, 24, 3)
local diamondNote = Theme.pixelLabel({
	Name = "DiamondNote",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 62),
	Size = UDim2.fromOffset(420, 12),
	TextColor3 = Colors.Marble,
	TextXAlignment = Enum.TextXAlignment.Right,
	Visible = false,
	Parent = gui,
}, 8)

local function refreshDiamonds()
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	if status == ProfileStatus.Loading or status == nil then
		diamondLabel.Text = "..."
	else
		diamondLabel.Text = tostring(GameState.diamondsOf(localPlayer))
	end
	if status == ProfileStatus.Offline then
		diamondNote.Text = "DIAMONDS ARE NOT SAVED IN STUDIO"
	elseif status == ProfileStatus.Error then
		diamondNote.Text = "DIAMONDS ARE UNAVAILABLE - TRYING AGAIN"
	else
		diamondNote.Text = ""
	end
	diamondNote.Visible = diamondNote.Text ~= ""
end

---------------------------------------------------------------- крупная надпись

local banner = Theme.pixelLabel({
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.new(0.8, 0, 0, 64),
	TextColor3 = Colors.Gold,
	TextWrapped = true,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
}, if touchOnly then 16 else 24, 3)
local bannerToken = 0

local function showBanner(text: string, kind: string?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = string.upper(text)
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

---------------------------------------------------------------- выбор класса (окно CLASSES)

local CLASS_KEYS = {
	{ Enum.KeyCode.One, Enum.KeyCode.KeypadOne },
	{ Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo },
	{ Enum.KeyCode.Three, Enum.KeyCode.KeypadThree },
	{ Enum.KeyCode.Four, Enum.KeyCode.KeypadFour },
	{ Enum.KeyCode.Five, Enum.KeyCode.KeypadFive },
}

-- Сервер сам проверит, можно ли сейчас менять класс; тут только не шлём лишнего
local function chooseClass(role: string)
	if launching() then
		return
	end
	if not GameState.ownsClass(localPlayer, role) then
		ClassShop.open(role) -- некупленный класс — сразу в магазин на нём (окно классов закроется само)
		return
	end
	if GameState.roleOf(localPlayer) ~= role then
		Remotes.get(Remotes.Names.SetRole):FireServer(role)
	end
	ClassesWindow.close()
end

ClassesWindow.init(chooseClass)

---------------------------------------------------------------- маленькое окно «Coming soon!»

local soonWindow = PixelWindow.new({ name = "ComingSoon", title = "COMING SOON!", width = 480, height = 230 })
local soonText = Theme.pixelLabel({
	Name = "Text",
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -32, 1, -20),
	TextColor3 = Colors.Marble,
	TextWrapped = true,
	ZIndex = 3,
	Parent = soonWindow.content,
}, 12, 2)

local function comingSoon(title: string, text: string)
	soonWindow.setTitle(title)
	soonText.Text = text
	soonWindow.open()
end

---------------------------------------------------------------- кнопки слева

local menu = Theme.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	Parent = gui,
})

type MenuItem = { icon: string, label: string, key: string?, action: () -> () }

local function openShop()
	if not launching() then
		ClassShop.toggle()
	end
end

local function openClasses()
	if not launching() then
		ClassesWindow.toggle()
	end
end

local ITEMS: { MenuItem } = {
	{ icon = "Shop", label = "SHOP", key = "B", action = openShop },
	{ icon = "Classes", label = "CLASSES", key = "C", action = openClasses },
	{
		icon = "Gift",
		label = "GIFTS",
		action = Gifts.toggle,
	},
	{
		icon = "HowToPlay",
		label = "HOW TO PLAY",
		action = HowToPlay.toggle,
	},
	{
		icon = "Group",
		label = "GROUP",
		action = function()
			-- Группы пока нет (Config.Rewards.GroupId = 0): награду за вступление сделаем, когда владелец пришлёт номер
			comingSoon("COMING SOON!", "Join our Roblox group and get a gift. Coming soon!")
		end,
	},
	{
		icon = "Favorite",
		label = "FAVORITE",
		action = function()
			-- Roblox не даёт проверить, добавил ли игрок игру в избранное, — награды не будет, позже только окно Roblox
			comingSoon("COMING SOON!", "Add Night Guard: Museum to your favorites. Coming soon!")
		end,
	},
}

local buttons: { [string]: PixelButton.IconButton } = {}
local buttonList: { PixelButton.IconButton } = {}
for index, item in ITEMS do
	local button = PixelButton.new({
		icon = item.icon,
		label = item.label,
		key = item.key,
		layoutOrder = index,
		parent = menu,
		onActivated = item.action,
	})
	buttons[item.icon] = button
	table.insert(buttonList, button)
end

-- Раскладка: на компьютере — столбик по центру высоты слева, на телефоне — 2 столбика сверху слева
-- (внизу слева джойстик). Клетка иконки — целое число пикселей, на маленьком экране меньше.
local COLUMNS = if touchOnly then 2 else 1
local ROWS = math.ceil(#buttonList / COLUMNS)
local function layoutMenu()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local room = if touchOnly then viewport.Y * 0.62 else viewport.Y * 0.86
	local cell = Config.PixelUI.MinCell
	for try = Config.PixelUI.Cell, Config.PixelUI.MinCell, -1 do
		buttonList[1].setCell(try)
		if ROWS * buttonList[1].height() + (ROWS - 1) * try <= room then
			cell = try
			break
		end
	end
	local width, height = 0, 0
	for _, button in buttonList do
		button.setCell(cell)
		width = math.max(width, button.width())
		height = math.max(height, button.height())
	end
	for index, button in buttonList do
		local column = (index - 1) % COLUMNS
		local row = (index - 1) // COLUMNS
		button.root.Position = UDim2.fromOffset(column * width, row * (height + cell))
	end
	menu.Size = UDim2.fromOffset(COLUMNS * width, ROWS * height + (ROWS - 1) * cell)
	if touchOnly then
		menu.AnchorPoint = Vector2.new(0, 0)
		menu.Position = UDim2.fromOffset(8, 64)
	else
		menu.AnchorPoint = Vector2.new(0, 0.5)
		menu.Position = UDim2.new(0, 12, 0.5, 0)
	end
end
layoutMenu()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutMenu)
end

---------------------------------------------------------------- панель создателя команды

local LEADER_W, LEADER_H = 300, 210
local leader = Theme.new("Frame", {
	Name = "LeaderPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.45, 0),
	Size = UDim2.fromOffset(LEADER_W, LEADER_H),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local leaderInset = PixelWindow.box(leader)
local leaderScale = Theme.new("UIScale", { Parent = leader })
local leaderTitle = Theme.pixelLabel({
	Position = UDim2.fromOffset(leaderInset, leaderInset + 6),
	Size = UDim2.new(1, -2 * leaderInset, 0, 20),
	TextColor3 = Colors.Gold,
	ZIndex = 3,
	Parent = leader,
}, 16)
Theme.pixelLabel({
	Position = UDim2.fromOffset(leaderInset, leaderInset + 34),
	Size = UDim2.new(1, -2 * leaderInset, 0, 12),
	TextColor3 = Colors.Marble,
	Text = "YOU STEPPED IN FIRST - YOU LEAD",
	ZIndex = 3,
	Parent = leader,
}, 8)

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

local startButton = PixelButton.text({
	name = "Start",
	text = if touchOnly then "START NOW" else "START NOW [F]",
	color = Colors.Green,
	position = UDim2.fromOffset(leaderInset + 4, leaderInset + 60),
	size = UDim2.new(1, -2 * leaderInset - 8, 0, 56),
	zIndex = 3,
	parent = leader,
	onActivated = pressStart,
})
local friendsButton = PixelButton.text({
	name = "FriendsOnly",
	text = "FRIENDS ONLY: OFF",
	color = Colors.NavyLight,
	textSize = 12,
	position = UDim2.fromOffset(leaderInset + 4, leaderInset + 124),
	size = UDim2.new(1, -2 * leaderInset - 8, 0, 48),
	zIndex = 3,
	parent = leader,
	onActivated = toggleFriends,
})

local function rescaleLeader()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	leaderScale.Scale = math.clamp(math.min(viewport.X * 0.3 / LEADER_W, viewport.Y * 0.45 / LEADER_H), 0.5, 1)
end
rescaleLeader()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleLeader)
end

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
Theme.pixelLabel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.new(0.9, 0, 0, 40),
	Text = "TELEPORTING TO THE MUSEUM...",
	TextColor3 = Colors.Gold,
	TextWrapped = true,
	ZIndex = 10,
	Parent = overlay,
}, if touchOnly then 16 else 32, 3)
local overlayHint = Theme.pixelLabel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.new(0.8, 0, 0, 20),
	TextColor3 = Colors.Marble,
	ZIndex = 10,
	Parent = overlay,
}, 16)

---------------------------------------------------------------- клавиши

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Keys.Shop then
		openShop()
		return
	elseif input.KeyCode == Enum.KeyCode.C then
		openClasses()
		return
	end
	if ClassesWindow.isOpen() then
		for index, keys in CLASS_KEYS do
			local role = Config.Classes.Order[index]
			if role and table.find(keys, input.KeyCode) then
				chooseClass(role)
				return
			end
		end
		return
	end
	if PixelWindow.anyOpen() then
		return -- пока открыто окно, клавиши хаба не работают
	end
	if input.KeyCode == Config.Keys.Action then
		pressStart()
	elseif input.KeyCode == Enum.KeyCode.G then
		toggleFriends()
	end
end)

---------------------------------------------------------------- обновление

local function teamText(pad: BasePart?): string
	if not pad then
		return ""
	end
	local index = tonumber(pad:GetAttribute(PadAttr.Index)) or 0
	local ids = GameState.padTeam(pad)
	local state = pad:GetAttribute(PadAttr.State)
	local message = pad:GetAttribute(PadAttr.Message)
	if state == PadState.Launching then
		return "TELEPORTING TO THE MUSEUM..."
	elseif state == PadState.Blocked and typeof(message) == "string" then
		return string.upper(message)
	end
	local endsAt = tonumber(pad:GetAttribute(PadAttr.EndsAt)) or 0
	local left = Theme.formatTime(math.max(0, endsAt - Workspace:GetServerTimeNow()))
	local who = if isCreator(pad) then "YOU LEAD" else "YOU'RE IN"
	return ("%s TEAM %d (%d/%d) - STARTING IN %s"):format(who, index, #ids, Config.Players.Max, left)
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
	local info = GameState.classInfo(GameState.roleOf(localPlayer))
	local className = string.upper(if info then tostring(info.Title) else "Patrol")
	classLine.Text = "YOUR CLASS: " .. className
	teamLine.Text = teamText(pad)

	local flying = pad ~= nil and pad:GetAttribute(PadAttr.State) == PadState.Launching
	overlay.Visible = flying
	if flying then
		overlayHint.Text = "YOUR CLASS: " .. className
		if PixelWindow.anyOpen() then
			PixelWindow.closeAll() -- команда улетает — окна закрываем
		end
	end
	menu.Visible = not flying
	ClassesWindow.refresh()
	-- Подарок можно забрать — красная точка на GIFTS (окно само не открываем)
	buttons.Gift.setDot(Gifts.canClaim())

	local leading = pad ~= nil and isCreator(pad) and not flying
	leader.Visible = leading
	if pad and leading then
		leaderTitle.Text = ("TEAM %d - LEADER"):format(tonumber(pad:GetAttribute(PadAttr.Index)) or 0)
		local open = pad:GetAttribute(PadAttr.State) == PadState.Open
		startButton.setEnabled(open)
		startButton.setColor(if open then Colors.Green else Colors.Gray)
		local on = pad:GetAttribute(PadAttr.FriendsOnly) == true
		local key = if touchOnly then "" else " [G]"
		friendsButton.setText((if on then "FRIENDS ONLY: ON" else "FRIENDS ONLY: OFF") .. key)
		friendsButton.setColor(if on then Config.Hub.FriendsColor else Colors.NavyLight)
	end
end)
