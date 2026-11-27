-- Интерфейс игрока: лобби (карточки классов, команда в круге START SHIFT), верхняя строка (таймер, часы ночи),
-- деньги, крупные надписи и экран итога ночи; в конце забега — кнопки Play again / Lobby (блок 6).
-- Клиент только показывает и шлёт намерения.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Progress = require(Shared:WaitForChild("Progress"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local ClassCards = require(script.Parent:WaitForChild("UI"):WaitForChild("ClassCards"))
local PixelButton = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelButton"))
local GoalBar = require(script.Parent:WaitForChild("UI"):WaitForChild("GoalBar"))
local PixelIcon = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelIcon"))
local MvpShowcase = require(script.Parent:WaitForChild("UI"):WaitForChild("MvpShowcase"))
local SettingsWindow = require(script.Parent:WaitForChild("UI"):WaitForChild("SettingsWindow"))

local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local gui = Theme.screenGui("HUD", 1)
SettingsWindow.start() -- применяем сохранённые настройки сразу при входе (этап 6, блок J1)

---------------------------------------------------------------- кнопка настроек (рядом с SHOP / STATS)

local settingsGui = Theme.screenGui("SettingsHud", 5)
local function canOpenSettings(): boolean
	if GameState.phase() == Phase.Results then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.ShopOpen) == true then
		return false
	end
	return true
end

local settingsButton = PixelButton.new({
	icon = "Settings",
	label = "SETTINGS",
	key = Config.Settings.KeyLabel,
	cell = Config.PixelUI.HudCell,
	name = "SettingsButton",
	parent = settingsGui,
	onActivated = function()
		if SettingsWindow.isOpen() then
			SettingsWindow.close()
		elseif canOpenSettings() then
			SettingsWindow.open()
		end
	end,
})
settingsButton.root.AnchorPoint = Vector2.new(1, 0)
settingsButton.root.Position = UDim2.new(1, -12, 0, 62)

local function updateSettingsButton()
	local phase = GameState.phase()
	local allowed = canOpenSettings()
	settingsButton.root.Visible = allowed
	if allowed then
		local onShift = localPlayer:GetAttribute(PlayerAttr.InRound) == true
		local statsVisible = phase == Phase.Day or phase == Phase.Night
		local slot = (if onShift then 1 else 0) + (if statsVisible then 1 else 0)
		local rightOffset = 12 + slot * (settingsButton.width() + Config.Settings.ButtonGap)
		settingsButton.root.Position = UDim2.new(1, -rightOffset, 0, 62)
	elseif SettingsWindow.isOpen() then
		SettingsWindow.close()
	end
end

local settingsConns: { RBXScriptConnection } = {
	GameState.folder():GetAttributeChangedSignal(Attr.Phase):Connect(updateSettingsButton),
	localPlayer:GetAttributeChangedSignal(PlayerAttr.InRound):Connect(updateSettingsButton),
	localPlayer:GetAttributeChangedSignal(PlayerAttr.ViewingCameras):Connect(updateSettingsButton),
	localPlayer:GetAttributeChangedSignal(PlayerAttr.ShopOpen):Connect(updateSettingsButton),
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Config.Settings.Key then
			if SettingsWindow.isOpen() then
				SettingsWindow.close()
			elseif canOpenSettings() then
				SettingsWindow.open()
			end
		end
	end),
}
updateSettingsButton()

---------------------------------------------------------------- верхняя строка и деньги

local topBar = Theme.new("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0.5, 0, 0, 46),
	BackgroundTransparency = 1, -- без рамки и фона: пиксельный шрифт с чёрной обводкой (этап 5, блок D)
	Parent = gui,
})
local topLabel = Theme.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 20, Parent = topBar })
Theme.padding(6).Parent = topBar

local moneyFrame = Theme.new("Frame", {
	Name = "Money",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 150, 0, 46),
	BackgroundTransparency = 1,
	Parent = gui,
})
local moneyLabel = Theme.label({ Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Gold, Text = "$0", TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 24, Parent = moneyFrame })
Theme.padding(6).Parent = moneyFrame
Theme.pixelize(topLabel, moneyLabel)

---------------------------------------------------------------- крупная надпись

local banner = Theme.label({
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 140), -- под плашкой шага обучения (Tutorial.client)
	Size = UDim2.new(0.8, 0, 0, 70),
	TextColor3 = Colors.Red,
	MaxTextSize = 56,
	Visible = false,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = banner })
local bannerToken = 0

local function showBanner(text: string, kind: string?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = if kind == "info" then Colors.Gold else Colors.Red
	banner.Visible = true
	task.delay(Config.Effects.BannerSeconds, function()
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

---------------------------------------------------------------- лобби: выбор класса
-- Команду собирает круг START SHIFT на полу (LobbyCircle.client, LobbyService), кнопки READY нет.
-- Курсор в лобби не освобождаем (у карточек нет Modal): в первом лице надо крутить камеру и дойти до круга.
-- Поэтому класс с клавиатуры — клавишами 1–5 (подписаны на карточках), на телефоне карточки нажимаются пальцем.
-- Класс выбирают в лобби и пока ждут в комнате охраны (опоздавший); на смене он не меняется (блок 5).

-- На телефоне и планшете без клавиатуры вместо клавиш — кнопки на экране
local touchOnly = Theme.touchOnly()

local CLASS_KEYS = {
	{ Enum.KeyCode.One, Enum.KeyCode.KeypadOne },
	{ Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo },
	{ Enum.KeyCode.Three, Enum.KeyCode.KeypadThree },
	{ Enum.KeyCode.Four, Enum.KeyCode.KeypadFour },
	{ Enum.KeyCode.Five, Enum.KeyCode.KeypadFive },
}

local function canChooseClass(): boolean
	local phase = GameState.phase()
	if phase == Phase.Results or GameState.get(Attr.HubArrival) == true then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.Spectating) == true then
		return false
	end
	return phase == Phase.Lobby or localPlayer:GetAttribute(PlayerAttr.InRound) ~= true
end

-- Сервер сам проверит, можно ли сейчас менять класс; тут только не шлём лишнего.
-- Некупленный класс (этап 4, блок 1) покупается только в магазине хаба — подсказываем.
local function chooseClass(role: string)
	if not canChooseClass() or GameState.roleOf(localPlayer) == role then
		return
	end
	if not GameState.ownsClass(localPlayer, role) then
		local info = GameState.classInfo(role)
		showBanner(("%s — %d 💎. Buy it in the lobby shop"):format(if info then string.upper(tostring(info.Title)) else role, GameState.classPrice(role)), "info")
		return
	end
	Remotes.get(Remotes.Names.SetRole):FireServer(role)
end

local classCards = ClassCards.new(gui, touchOnly, chooseClass)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not canChooseClass() then
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

---------------------------------------------------------------- итог ночи

local PANEL_SOLO_W = 640
local PANEL_MVP_W = 860
local PANEL_H = 570
local CHOICE_H = 114
local COL_GAP = 16

local resultsFrame = Theme.new("Frame", {
	Name = "Results",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.3,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})

local resultsContainer = Theme.new("Frame", {
	Name = "Container",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_SOLO_W, PANEL_H),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = resultsFrame,
})
local resultsScale = Theme.new("UIScale", { Parent = resultsContainer })

-- Этап 6, блоки H2 и I3: панель итога и витрина MVP справа (масштабируется целиком под экран)
local resultsPanel = Theme.new("Frame", {
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.fromOffset(PANEL_SOLO_W, PANEL_H),
	BackgroundColor3 = Colors.Navy,
	ZIndex = 5,
	Parent = resultsContainer,
}, { Theme.corner(18), Theme.stroke(Colors.Gold, 3), Theme.padding(16) })

local resultsTitle = Theme.label({ Size = UDim2.new(1, 0, 0, 60), MaxTextSize = 52, ZIndex = 5, Parent = resultsPanel })
local resultsCaught = Theme.label({
	Position = UDim2.fromOffset(0, 62),
	Size = UDim2.new(1, 0, 0, 34),
	TextColor3 = Colors.Marble,
	MaxTextSize = 26,
	ZIndex = 5,
	Parent = resultsPanel,
})

local mvpShowcase = MvpShowcase.new(resultsPanel, 6)
mvpShowcase.frame.AnchorPoint = Vector2.new(1, 0)
mvpShowcase.frame.Position = UDim2.new(1, 0, 0, 102)

local resultsLeftCol = Theme.new("Frame", {
	Name = "LeftColumn",
	Position = UDim2.fromOffset(0, 102),
	Size = UDim2.new(1, 0, 0, 392),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = resultsPanel,
})

-- «Thieves used: Decoy, Pincer» — какие планы были у воров (блок 3; заранее о планах ничего не говорится)
local resultsPlans = Theme.label({
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 24),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gold,
	MaxTextSize = 20,
	ZIndex = 5,
	Parent = resultsLeftCol,
})
-- Алмазы 💎 (этап 4, блок 1): «+12 💎» за эту ночь или «Diamonds this run: +46 💎» на GAME OVER
local resultsDiamonds = Theme.label({
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 34),
	RichText = true,
	TextColor3 = Colors.Diamond,
	MaxTextSize = 30,
	ZIndex = 5,
	Parent = resultsLeftCol,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = resultsDiamonds })
local resultsList = Theme.new("Frame", {
	Position = UDim2.fromOffset(0, 68),
	Size = UDim2.new(1, 0, 0, 146),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = resultsLeftCol,
})
Theme.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = resultsList })
-- Низ панели (этап 6, блок H2): полоска до ближайшей награды, сундук после ночи, «чуть-чуть не хватило» на GAME OVER
local resultsExtras = Theme.new("Frame", {
	Name = "Extras",
	Position = UDim2.fromOffset(0, 220),
	Size = UDim2.new(1, 0, 0, 168),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = resultsLeftCol,
})
-- GAME OVER (этап 6, блок H2): крупно ближайшая цель — «1 NIGHT TO BEAT YOUR RECORD!», «30 💎 TO TECHNICIAN»
local nearMiss = Theme.label({
	Name = "NearMiss",
	Size = UDim2.new(1, 0, 0, 40),
	TextColor3 = Colors.Gold,
	MaxTextSize = 34,
	Visible = false,
	ZIndex = 6,
	Parent = resultsExtras,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = nearMiss })
local resultsGoal = GoalBar.new(resultsExtras, { width = 380, zIndex = 6 })
-- GAME OVER (этап 6, блок H2): «Your friend Alex survived 9 nights — beat it!» (рекорды друзей; нет данных — пусто)
local friendRecord = Theme.label({
	Name = "FriendRecord",
	Position = UDim2.new(0, 0, 0, 104),
	Size = UDim2.new(1, 0, 0, 24),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Turquoise,
	MaxTextSize = 20,
	Visible = false,
	ZIndex = 6,
	Parent = resultsExtras,
})
resultsGoal.frame.AnchorPoint = Vector2.new(0.5, 0)
resultsGoal.frame.Position = UDim2.fromScale(0.5, 0)

-- Сундук после ночи (этап 6, блок H2): «OPEN FREE CHEST», сколько внутри — решает сервер (ChestService).
-- Только бесплатно. Не открыл до конца итога — алмазы всё равно начислятся.
local chestRow = Theme.new("Frame", {
	Name = "Chest",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(380, 64),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 6,
	Parent = resultsExtras,
})
local GOLD_CHEST: PixelIcon.Icon = {
	rows = PixelIcon.Icons.Chest.rows,
	palette = { K = "141420", b = "D4A93A", h = "FFE08A", y = "FFFFFF", d = "8B5A2B" },
}
local chestIcon = PixelIcon.new("Chest", true, 7)
chestIcon.Size = PixelIcon.size("Chest", 4)
chestIcon.Parent = chestRow
local chestGoldIcon = PixelIcon.new(GOLD_CHEST, true, 7)
chestGoldIcon.Size = chestIcon.Size
chestGoldIcon.Visible = false
chestGoldIcon.Parent = chestRow
local chestScale = Theme.new("UIScale", { Parent = chestRow })
local chestState = "none" -- "none" | "ready" | "opening" | "open"
local function openChest()
	if chestState ~= "ready" then
		return
	end
	chestState = "opening"
	Remotes.get(Remotes.Names.OpenChest):FireServer()
end
local chestButton = PixelButton.text({
	name = "OpenChest",
	text = if touchOnly then "OPEN FREE CHEST" else "OPEN FREE CHEST [O]",
	color = Colors.Gold,
	textSize = 12,
	position = UDim2.fromOffset(76, 6),
	size = UDim2.new(1, -76, 0, 52),
	zIndex = 7,
	parent = chestRow,
	onActivated = openChest,
})
chestButton.root.Modal = true -- курсор свободен, пока кнопка на экране
local chestText = Theme.label({
	Position = UDim2.fromOffset(76, 0),
	Size = UDim2.new(1, -76, 1, 0),
	RichText = true,
	TextColor3 = Colors.Diamond,
	MaxTextSize = 30,
	Visible = false,
	ZIndex = 7,
	Parent = chestRow,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = chestText })

local function resetChest(has: boolean)
	chestState = if has then "ready" else "none"
	chestRow.Visible = has
	chestButton.root.Visible = has
	chestText.Visible = false
	chestIcon.Visible = true
	chestGoldIcon.Visible = false
	chestScale.Scale = 1
end

Remotes.get(Remotes.Names.ChestResult).OnClientEvent:Connect(function(amount, gold)
	if typeof(amount) ~= "number" or chestState == "none" then
		return
	end
	chestState = "open"
	chestButton.root.Visible = false
	chestIcon.Visible = gold ~= true
	chestGoldIcon.Visible = gold == true
	chestText.Text = if gold == true
		then ('<font color="#FFE08A">GOLDEN CHEST! x%d</font>   +%d 💎'):format(Config.Chest.GoldMultiplier, amount)
		else ("+%d 💎"):format(amount)
	chestText.Visible = true
	-- Подпрыгивает, когда открылся
	chestScale.Scale = 0.7
	TweenService:Create(chestScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.O and resultsFrame.Visible then
		openChest()
	end
end)
local resultsFooter = Theme.label({
	Position = UDim2.fromOffset(0, 502),
	Size = UDim2.new(1, 0, 0, 34),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gray,
	MaxTextSize = 18,
	ZIndex = 5,
	Parent = resultsPanel,
})

local resultsGameOver = false
local resultsMvpVisible = false

---------------------------------------------------------------- конец забега: Play again / Lobby (блок 6)
-- Кнопки под экраном GAME OVER. Пока они видны, курсор свободен (Modal), с клавиатуры — P и L.
-- Выбор решает сервер (HubLink): Play again — новый забег той же командой, Lobby — в хаб (или в домик SECURITY).

local choiceBar = Theme.new("Frame", {
	Name = "GameOverChoice",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, PANEL_H + 12),
	Size = UDim2.fromOffset(520, 72),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 6,
	Parent = resultsContainer,
})

local function rescaleResults()
	local panelW = if resultsMvpVisible then PANEL_MVP_W else PANEL_SOLO_W
	local totalH = if choiceBar.Visible then PANEL_H + CHOICE_H else PANEL_H
	resultsContainer.Size = UDim2.fromOffset(panelW, totalH)
	resultsPanel.Size = UDim2.fromOffset(panelW, PANEL_H)
	resultsLeftCol.Size = if resultsMvpVisible
		then UDim2.new(1, -(mvpShowcase.width + COL_GAP), 0, 392)
		else UDim2.new(1, 0, 0, 392)
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	resultsScale.Scale = math.clamp(math.min((viewport.X - 24) / panelW, (viewport.Y - 24) / totalH), 0.35, 1)
end

local viewportConn: RBXScriptConnection? = nil
local function watchViewport()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleResults)
	end
	rescaleResults()
end
watchViewport()
local camPropConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)
-- Этап 6, блок H2: PLAY AGAIN крупнее, ярче и «дышит», LOBBY — маленькая и спокойная
local AGAIN_COLOR = Color3.fromHex("56D97F")
-- Пиксельные кнопки с текстом, как в хабе (этап 5, блок D)
local chooseEnd: (choice: string) -> ()
local againButton = PixelButton.text({
	name = "PlayAgain",
	text = if touchOnly then "PLAY AGAIN" else "PLAY AGAIN [P]",
	color = AGAIN_COLOR,
	textSize = 20,
	size = UDim2.new(0.64, 0, 1, 0),
	zIndex = 6,
	parent = choiceBar,
	onActivated = function()
		chooseEnd("PlayAgain")
	end,
})
againButton.root.Modal = true -- курсор свободен, пока кнопки на экране
local againScale = Theme.new("UIScale", { Parent = againButton.root })
local lobbyButton = PixelButton.text({
	name = "Lobby",
	text = if touchOnly then "LOBBY" else "LOBBY [L]",
	color = Colors.NavyLight,
	textSize = 12,
	anchor = Vector2.new(0, 0.5),
	position = UDim2.new(0.67, 0, 0.5, 0),
	size = UDim2.new(0.33, 0, 0, 44),
	zIndex = 6,
	parent = choiceBar,
	onActivated = function()
		chooseEnd("Lobby")
	end,
})
local choiceHint = Theme.label({
	Position = UDim2.new(0, 0, 1, 6),
	Size = UDim2.new(1, 0, 0, 22),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 18,
	ZIndex = 6,
	Parent = choiceBar,
})
local choiceOpen = false

local function myChoice(): string
	local value = localPlayer:GetAttribute(PlayerAttr.EndChoice)
	return if typeof(value) == "string" then value else ""
end

chooseEnd = function(choice: string)
	if not choiceOpen or myChoice() ~= "" then
		return
	end
	Remotes.get(Remotes.Names.GameOverChoice):FireServer(choice)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not choiceOpen then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		chooseEnd("PlayAgain")
	elseif input.KeyCode == Enum.KeyCode.L then
		chooseEnd("Lobby")
	end
end)

local function refreshChoice()
	local chosen = myChoice()
	local locked = chosen ~= ""
	-- Выбранная — золотая, другая после выбора бледнеет
	againButton.setColor(if chosen == "PlayAgain" then Colors.Gold else AGAIN_COLOR)
	lobbyButton.setColor(if chosen == "Lobby" then Colors.Gold else Colors.NavyLight)
	againButton.setEnabled(not locked or chosen == "PlayAgain")
	lobbyButton.setEnabled(not locked or chosen == "Lobby")
	if chosen == "PlayAgain" then
		choiceHint.Text = "Waiting for the others — a new run starts soon"
	elseif chosen == "Lobby" then
		choiceHint.Text = "Going to the lobby..."
	else
		choiceHint.Text = "Same team, new run — or back to the lobby"
	end
end

-- «Чуть-чуть не хватило» (этап 6, блок H2): до личного рекорда пара ночей — об этом; побил рекорд — праздник;
-- иначе — ближайшая награда (класс, задание, уровень). Только честные цели, без давления.
local function nearMissText(survivedNights: number, best: number): string
	if best > 0 and survivedNights > best then
		return ("NEW PERSONAL RECORD: %d NIGHTS!"):format(survivedNights)
	end
	local gap = best + 1 - survivedNights
	if best > 0 and gap >= 1 and gap <= Config.GameOver.NearRecordNights then
		return if gap == 1 then "1 NIGHT TO BEAT YOUR RECORD!" else ("%d NIGHTS TO BEAT YOUR RECORD!"):format(gap)
	end
	local goal = GoalBar.current()
	if goal then
		return goal.near
	end
	return if best > 0 then ("YOUR RECORD: %d NIGHTS - BEAT IT!"):format(best) else ""
end

local function showResults(results: { [string]: any })
	for _, child in resultsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local survived = results.survived == true
	local night = tonumber(results.night) or 0
	resultsGameOver = results.gameOver == true
	if resultsGameOver then
		resultsTitle.Text = "GAME OVER"
		resultsCaught.Text = ("You survived %d nights   •   Server record: %d"):format(
			tonumber(results.nightsSurvived) or 0,
			tonumber(results.best) or 0
		)
	else
		resultsTitle.Text = ("NIGHT %d SURVIVED"):format(night)
		resultsCaught.Text = ("Thieves caught: %d / %d   •   Tickets: +$%d"):format(
			tonumber(results.caught) or 0,
			tonumber(results.total) or 0,
			tonumber(results.tickets) or 0
		)
	end
	resultsTitle.TextColor3 = if survived then Colors.Gold else Colors.Red
	local plans = {}
	if typeof(results.plans) == "table" then
		for _, title in results.plans do
			if typeof(title) == "string" then
				table.insert(plans, title)
			end
		end
	end
	resultsPlans.Text = if #plans > 0 then "Thieves used: " .. table.concat(plans, ", ") else ""
	-- Свои алмазы: за ночь или за весь забег; в Studio без доступа к API — пометка, что не сохраняются
	local myKey = tostring(localPlayer.UserId)
	local nightDiamonds = if typeof(results.diamonds) == "table" then tonumber(results.diamonds[myKey]) else nil
	local runDiamonds = if typeof(results.diamondsRun) == "table" then tonumber(results.diamondsRun[myKey]) else nil
	local notSaved = if results.diamondsSaved == false then '  <font size="16" color="#8A93A6">(not saved in Studio)</font>' else ""
	-- Бонус за друга в команде (этап 6, блок H2)
	local bonus = if typeof(results.friendsBonus) == "table" then tonumber(results.friendsBonus[myKey]) or 0 else 0
	if bonus > 0 then
		notSaved = ('   <font size="18" color="#%s">Friends bonus +%d%%</font>'):format(
			Colors.Turquoise:ToHex(),
			math.floor(Config.Diamonds.FriendsBonus * 100 + 0.5)
		) .. notSaved
	end
	if resultsGameOver and runDiamonds then
		resultsDiamonds.Text = ("Diamonds this run: +%d 💎%s"):format(runDiamonds, notSaved)
	elseif nightDiamonds then
		resultsDiamonds.Text = ("+%d 💎%s"):format(nightDiamonds, notSaved)
	else
		resultsDiamonds.Text = ""
	end
	-- Кнопки Play again / Lobby — только тем, кто был на смене
	choiceOpen = results.choice == true and localPlayer:GetAttribute(PlayerAttr.InRound) == true
	choiceBar.Visible = choiceOpen
	if choiceOpen then
		refreshChoice()
	end

	local earnings = if typeof(results.earnings) == "table" then results.earnings else {}
	local catches = if typeof(results.catches) == "table" then results.catches else {}
	local wallets = if typeof(results.wallets) == "table" then results.wallets else {}
	local gems = if typeof(results.diamonds) == "table" then results.diamonds else {}
	local best = tonumber(results.bestUserId) or 0
	local bestCatches = tonumber(results.bestCatches)
		or (if best ~= 0 then tonumber(catches[tostring(best)]) or 0 else 0)
	local bestName = if typeof(results.bestName) == "string" and results.bestName ~= "" then results.bestName else nil
	local order = 0
	for userIdText, amount in earnings do
		order += 1
		local userId = tonumber(userIdText) or 0
		local player = Players:GetPlayerByUserId(userId)
		local name = if player then player.DisplayName else "Guard"
		if userId == best and not bestName then
			bestName = name
		end
		Theme.label({
			LayoutOrder = order,
			Font = Theme.BodyFont,
			RichText = true,
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			ZIndex = 5,
			-- Имя, поймал (и сколько заработал арестами), сколько денег у него сейчас, алмазы за ночь
			Text = ('%s   caught: %d <font color="#3FB56B">(+$%d)</font>   money: <font color="#D4A93A">$%d</font>   <font color="#%s">+%d 💎</font>'):format(
				name,
				tonumber(catches[userIdText]) or 0,
				tonumber(amount) or 0,
				tonumber(wallets[userIdText]) or 0,
				Colors.Diamond:ToHex(),
				tonumber(gems[userIdText]) or 0
			),
			Parent = resultsList,
		})
	end
	resultsMvpVisible = best ~= 0 and bestCatches > 0
	if resultsMvpVisible then
		local bestPlayer = Players:GetPlayerByUserId(best)
		local displayName = bestName or (if bestPlayer then bestPlayer.DisplayName else "Guard")
		mvpShowcase.show(best, displayName, bestCatches)
	else
		mvpShowcase.hide()
	end
	rescaleResults()
	resultsGoal.refresh()
	-- Низ панели: на GAME OVER сверху крупная цель, под ней полоска; после ночи — полоска и сундук
	if resultsGameOver then
		local bests = if typeof(results.personalBest) == "table" then results.personalBest else {}
		nearMiss.Text = nearMissText(tonumber(results.nightsSurvived) or 0, tonumber(bests[myKey]) or 0)
		nearMiss.Visible = nearMiss.Text ~= ""
		resultsGoal.frame.Position = UDim2.new(0.5, 0, 0, 46)
		local survivedNights = tonumber(results.nightsSurvived) or 0
		local rival, beaten = Progress.friendRival(
			Progress.decodeFriendRecords(localPlayer:GetAttribute(PlayerAttr.FriendRecords)),
			survivedNights
		)
		friendRecord.Text = if not rival
			then ""
			elseif beaten then ("You beat your friend %s (%d nights)!"):format(rival.n, rival.v)
			else ("Your friend %s survived %d nights — beat it!"):format(rival.n, rival.v)
		friendRecord.Visible = friendRecord.Text ~= ""
	else
		friendRecord.Visible = false
		nearMiss.Visible = false
		resultsGoal.frame.Position = UDim2.fromScale(0.5, 0)
	end
	local chests = if typeof(results.chests) == "table" then results.chests else {}
	resetChest(not resultsGameOver and chests[myKey] == true)
	resultsFrame.Visible = true
end

Remotes.get(Remotes.Names.NightResults).OnClientEvent:Connect(function(results)
	if typeof(results) == "table" then
		showResults(results)
	end
end)

-- Подсказки новичку внизу экрана (решение 36) заменены обучением со стрелками в каждом забеге
-- (этап 5, блок C, решение 78): client/Tutorial.client.luau.

---------------------------------------------------------------- обновление каждый кадр

local JOIN_STATUS_TEXT = {
	Voting = "The team is voting to let you in...",
	Approved = "You're in! You join the team at the start of the next day",
	Rejected = "Not this time — wait for the next game in the guard room",
	Full = "The team is full — wait for the next game in the guard room",
}

local function topBarText(phase: string): string
	local left = GameState.secondsLeft()
	-- Опоздавший: игра уже идёт, а он в комнате охраны
	if phase ~= Phase.Lobby and localPlayer:GetAttribute(PlayerAttr.InRound) ~= true then
		local status = localPlayer:GetAttribute(PlayerAttr.JoinStatus)
		local text = if typeof(status) == "string" then JOIN_STATUS_TEXT[status] else nil
		return text or ("Game in progress — night %d"):format(tonumber(GameState.get(Attr.NightNumber)) or 1)
	end
	if phase == Phase.Lobby and GameState.get(Attr.HubArrival) == true then
		-- Блок 6: команда прилетела из хаба, музей ждёт остальных и сразу начинает забег
		return ("Your team is arriving from the lobby...   •   %d/%d"):format(
			tonumber(GameState.get(Attr.HubArrived)) or 0,
			tonumber(GameState.get(Attr.HubExpected)) or 0
		)
	end
	if phase == Phase.Lobby then
		local count = #GameState.lobbyTeam()
		local inTeam = localPlayer:GetAttribute(PlayerAttr.InTeam) == true
		if inTeam and left > 0 then
			return ("You're in!   •   Shift starts in %s   •   Team %d/%d"):format(Theme.formatTime(left), count, Config.Players.Max)
		elseif inTeam then
			return "You're in the team!"
		elseif count >= Config.Players.Max then
			return ("The team is full (%d/%d) — wait in the guard room"):format(count, Config.Players.Max)
		elseif left > 0 then
			return ("Shift starts in %s   •   Step into the circle to join!"):format(Theme.formatTime(left))
		end
		return "Step into the START SHIFT circle"
	elseif phase == Phase.Day then
		return ("DAY %d   •   Night in %s   •   Tourists: %d"):format(
			tonumber(GameState.get(Attr.NightNumber)) or 1,
			Theme.formatTime(left),
			tonumber(GameState.get(Attr.TouristsToday)) or 0
		)
	elseif phase == Phase.Night then
		return ("NIGHT %d   •   %s   •   Caught: %d"):format(
			tonumber(GameState.get(Attr.NightNumber)) or 1,
			Theme.nightClock(GameState.nightProgress()),
			tonumber(GameState.get(Attr.Caught)) or 0
		)
	end
	return ""
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0

	local phase = GameState.phase()
	topBar.Visible = phase ~= Phase.Results
	topLabel.Text = Theme.pixelText(topBarText(phase))
	moneyLabel.Text = "$" .. tostring(localPlayer:GetAttribute(PlayerAttr.Money) or 0)

	-- Класс из хаба уже выбран: пока команда прилетает, карточек нет
	local choosing = canChooseClass() and phase ~= Phase.Results and GameState.get(Attr.HubArrival) ~= true
	classCards.setVisible(choosing)
	if choosing then
		classCards.refresh(GameState.roleOf(localPlayer))
	end

	if phase == Phase.Results then
		local left = Theme.formatTime(GameState.secondsLeft())
		if choiceOpen then
			refreshChoice()
		end
		-- PLAY AGAIN «дышит», пока не выбрал
		againScale.Scale = if choiceOpen and myChoice() == "" then 1 + 0.04 * math.sin(os.clock() * 4) else 1
		resultsFooter.Text = if resultsGameOver
			then "Back to the lobby in " .. left
			else ("Day %d starts in %s"):format((tonumber(GameState.get(Attr.NightNumber)) or 0) + 1, left)
	elseif phase == Phase.Lobby or phase == Phase.Day then
		-- Прячем итог только в лобби: событие с итогом может прийти чуть раньше смены фазы
		if resultsFrame.Visible then
			resultsFrame.Visible = false
			mvpShowcase.hide()
		end
		choiceOpen = false
		choiceBar.Visible = false
	end
end)

gui.Destroying:Connect(function()
	for _, conn in settingsConns do
		conn:Disconnect()
	end
	table.clear(settingsConns)
	SettingsWindow.close()
	if settingsGui.Parent then
		settingsGui:Destroy()
	end
	mvpShowcase.destroy()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	camPropConn:Disconnect()
end)
