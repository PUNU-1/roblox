-- Интерфейс игрока: лобби (карточки классов, команда в круге START SHIFT), верхняя строка (таймер, часы ночи),
-- деньги, крупные надписи и экран итога ночи. Клиент только показывает и шлёт намерения.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local ClassCards = require(script.Parent:WaitForChild("UI"):WaitForChild("ClassCards"))

local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local gui = Theme.screenGui("HUD", 1)

---------------------------------------------------------------- верхняя строка и деньги

local topBar = Theme.new("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0.5, 0, 0, 46),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Theme.corner(12), Theme.stroke(Colors.Gold, 2) })
local topLabel = Theme.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 28, Parent = topBar })
Theme.padding(6).Parent = topBar

local moneyFrame = Theme.new("Frame", {
	Name = "Money",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 150, 0, 46),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Theme.corner(12), Theme.stroke(Colors.Gold, 2) })
local moneyLabel = Theme.label({ Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Gold, Text = "$0", Parent = moneyFrame })
Theme.padding(6).Parent = moneyFrame

---------------------------------------------------------------- крупная надпись

local banner = Theme.label({
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.14, 0),
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
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local CLASS_KEYS = {
	{ Enum.KeyCode.One, Enum.KeyCode.KeypadOne },
	{ Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo },
	{ Enum.KeyCode.Three, Enum.KeyCode.KeypadThree },
	{ Enum.KeyCode.Four, Enum.KeyCode.KeypadFour },
	{ Enum.KeyCode.Five, Enum.KeyCode.KeypadFive },
}

local function canChooseClass(): boolean
	return GameState.phase() == Phase.Lobby or localPlayer:GetAttribute(PlayerAttr.InRound) ~= true
end

-- Сервер сам проверит, можно ли сейчас менять класс; тут только не шлём лишнего
local function chooseClass(role: string)
	if not canChooseClass() or GameState.roleOf(localPlayer) == role then
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

local resultsFrame = Theme.new("Frame", {
	Name = "Results",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.3,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})

local resultsPanel = Theme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.55, 0.7),
	BackgroundColor3 = Colors.Navy,
	ZIndex = 5,
	Parent = resultsFrame,
}, { Theme.corner(18), Theme.stroke(Colors.Gold, 3), Theme.padding(16), Theme.new("UISizeConstraint", { MinSize = Vector2.new(320, 300) }) })

local resultsTitle = Theme.label({ Size = UDim2.fromScale(1, 0.18), MaxTextSize = 60, ZIndex = 5, Parent = resultsPanel })
local resultsCaught = Theme.label({
	Position = UDim2.fromScale(0, 0.2),
	Size = UDim2.fromScale(1, 0.1),
	TextColor3 = Colors.Marble,
	ZIndex = 5,
	Parent = resultsPanel,
})
-- «Thieves used: Decoy, Pincer» — какие планы были у воров (блок 3; заранее о планах ничего не говорится)
local resultsPlans = Theme.label({
	Position = UDim2.fromScale(0, 0.3),
	Size = UDim2.fromScale(1, 0.06),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gold,
	MaxTextSize = 20,
	ZIndex = 5,
	Parent = resultsPanel,
})
local resultsList = Theme.new("Frame", {
	Position = UDim2.fromScale(0, 0.38),
	Size = UDim2.fromScale(1, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = resultsPanel,
})
Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = resultsList })
local resultsFooter = Theme.label({
	Position = UDim2.fromScale(0, 0.9),
	Size = UDim2.fromScale(1, 0.1),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gray,
	MaxTextSize = 18,
	ZIndex = 5,
	Parent = resultsPanel,
})

local resultsGameOver = false

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

	local earnings = if typeof(results.earnings) == "table" then results.earnings else {}
	local catches = if typeof(results.catches) == "table" then results.catches else {}
	local wallets = if typeof(results.wallets) == "table" then results.wallets else {}
	local best = tonumber(results.bestUserId) or 0
	local order = 0
	for userIdText, amount in earnings do
		order += 1
		local userId = tonumber(userIdText) or 0
		local player = Players:GetPlayerByUserId(userId)
		local name = if player then player.DisplayName else "Guard"
		local star = if userId == best and best ~= 0 then "  ★ BEST GUARD" else ""
		Theme.label({
			LayoutOrder = order,
			Font = Theme.BodyFont,
			RichText = true,
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 22,
			ZIndex = 5,
			-- Имя, поймал (и сколько заработал арестами), сколько денег у него сейчас
			Text = ('%s   caught: %d <font color="#3FB56B">(+$%d)</font>   money: <font color="#D4A93A">$%d</font>%s'):format(
				name,
				tonumber(catches[userIdText]) or 0,
				tonumber(amount) or 0,
				tonumber(wallets[userIdText]) or 0,
				star
			),
			Parent = resultsList,
		})
	end
	resultsFrame.Visible = true
end

Remotes.get(Remotes.Names.NightResults).OnClientEvent:Connect(function(results)
	if typeof(results) == "table" then
		showResults(results)
	end
end)

---------------------------------------------------------------- подсказки новичку

local hintFrame = Theme.new("Frame", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0.55, 0, 0, 40),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.25,
	Visible = false,
	Parent = gui,
}, { Theme.corner(12), Theme.padding(6), Theme.new("UISizeConstraint", { MinSize = Vector2.new(300, 0) }) })
local hintLabel = Theme.label({ Size = UDim2.fromScale(1, 1), Font = Theme.BodyFont, MaxTextSize = 20, Parent = hintFrame })

local HINT_ARREST = if touchOnly then "Hold the button next to a thief to arrest him" else "Hold F next to a thief to arrest him"
local HINT_BUY = if touchOnly
	then "Hold the button at boarded doors, pedestals and CAMERA SPOT signs to buy halls, exhibits, cameras"
	else "Hold F at boarded doors, pedestals and CAMERA SPOT signs to buy halls, exhibits, cameras"
local HINT_PHONE = if touchOnly then "Phone button — cameras" else "Tab — cameras"
local HINT_CONSOLE = "Camera console: on the balcony above the Mona Lisa"
local HINT_STOLEN = "The thief has the painting — catch him before he gets out!"

-- Раунд засчитан, когда закончилась ночь, в которой игрок участвовал
local roundsPlayed = 0
local playedThisNight = false

local function countRounds(phase: string)
	if phase == Phase.Night then
		if localPlayer:GetAttribute(PlayerAttr.InRound) == true then
			playedThisNight = true
		end
	elseif playedThisNight then
		playedThisNight = false
		roundsPlayed += 1
	end
end

local function hintText(phase: string): string?
	if roundsPlayed >= Config.Hints.Rounds or localPlayer:GetAttribute(PlayerAttr.InRound) ~= true then
		return nil
	end
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		return nil -- у экрана камер своя подсказка
	end
	local hasPhone = GameState.roleOf(localPlayer) == Role.Operator
	local cameras = if hasPhone then HINT_PHONE else HINT_CONSOLE
	if phase == Phase.Day then
		local money = tonumber(localPlayer:GetAttribute(PlayerAttr.Money)) or 0
		local closedHall = false
		for _, hall in GameState.PaidHalls do
			if not GameState.isHallOpen(hall) then
				closedHall = true
			end
		end
		if closedHall and money > 0 then
			return HINT_BUY
		end
		return "Thieves come at midnight. Don't let them take the Mona Lisa!   •   " .. cameras
	elseif phase == Phase.Night then
		if GameState.get(Attr.PaintingStolen) == true then
			return HINT_STOLEN
		end
		return HINT_ARREST .. "   •   " .. cameras
	end
	return nil
end

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
	topLabel.Text = topBarText(phase)
	moneyLabel.Text = "$" .. tostring(localPlayer:GetAttribute(PlayerAttr.Money) or 0)

	countRounds(phase)
	local hint = hintText(phase)
	hintFrame.Visible = hint ~= nil
	if hint then
		hintLabel.Text = hint
	end

	local choosing = canChooseClass() and phase ~= Phase.Results
	classCards.setVisible(choosing)
	if choosing then
		classCards.refresh(GameState.roleOf(localPlayer))
	end

	if phase == Phase.Results then
		local left = Theme.formatTime(GameState.secondsLeft())
		resultsFooter.Text = if resultsGameOver
			then "Back to the guard room in " .. left
			else ("Day %d starts in %s"):format((tonumber(GameState.get(Attr.NightNumber)) or 0) + 1, left)
	elseif phase == Phase.Lobby or phase == Phase.Day then
		-- Прячем итог только в лобби: событие с итогом может прийти чуть раньше смены фазы
		resultsFrame.Visible = false
	end
end)
