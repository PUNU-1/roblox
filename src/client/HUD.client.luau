-- Интерфейс игрока: лобби (карточки классов, команда в круге START SHIFT), верхняя строка (таймер, часы ночи),
-- деньги, крупные надписи и экран итога ночи; в конце забега — кнопки Play again / Lobby (блок 6).
-- Клиент только показывает и шлёт намерения.

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
	local phase = GameState.phase()
	if phase == Phase.Results or GameState.get(Attr.HubArrival) == true then
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
-- Алмазы 💎 (этап 4, блок 1): «+12 💎» за эту ночь или «Diamonds this run: +46 💎» на GAME OVER
local resultsDiamonds = Theme.label({
	Position = UDim2.fromScale(0, 0.365),
	Size = UDim2.fromScale(1, 0.075),
	RichText = true,
	TextColor3 = Colors.Diamond,
	MaxTextSize = 30,
	ZIndex = 5,
	Parent = resultsPanel,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = resultsDiamonds })
local resultsList = Theme.new("Frame", {
	Position = UDim2.fromScale(0, 0.46),
	Size = UDim2.fromScale(1, 0.43),
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

---------------------------------------------------------------- конец забега: Play again / Lobby (блок 6)
-- Кнопки под экраном GAME OVER. Пока они видны, курсор свободен (Modal), с клавиатуры — P и L.
-- Выбор решает сервер (HubLink): Play again — новый забег той же командой, Lobby — в хаб (или в домик SECURITY).

local choiceBar = Theme.new("Frame", {
	Name = "GameOverChoice",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.865, 0),
	Size = UDim2.new(0.42, 0, 0, 56),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 6,
	Parent = resultsFrame,
}, { Theme.new("UISizeConstraint", { MinSize = Vector2.new(320, 0) }) })
local againButton = Theme.button({
	Name = "PlayAgain",
	Size = UDim2.new(0.49, 0, 1, 0),
	BackgroundColor3 = Colors.Green,
	Text = if touchOnly then "PLAY AGAIN" else "PLAY AGAIN  [P]",
	Modal = true, -- курсор свободен, пока кнопки на экране
	ZIndex = 6,
	Parent = choiceBar,
})
local lobbyButton = Theme.button({
	Name = "Lobby",
	Position = UDim2.new(0.51, 0, 0, 0),
	Size = UDim2.new(0.49, 0, 1, 0),
	BackgroundColor3 = Colors.NavyLight,
	Text = if touchOnly then "LOBBY" else "LOBBY  [L]",
	ZIndex = 6,
	Parent = choiceBar,
})
local againStroke = Theme.stroke(Colors.Gold, 3)
againStroke.Enabled = false
againStroke.Parent = againButton
local lobbyStroke = Theme.stroke(Colors.Gold, 3)
lobbyStroke.Enabled = false
lobbyStroke.Parent = lobbyButton
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

local function chooseEnd(choice: string)
	if not choiceOpen or myChoice() ~= "" then
		return
	end
	Remotes.get(Remotes.Names.GameOverChoice):FireServer(choice)
end

againButton.Activated:Connect(function()
	chooseEnd("PlayAgain")
end)
lobbyButton.Activated:Connect(function()
	chooseEnd("Lobby")
end)
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
	againStroke.Enabled = chosen == "PlayAgain"
	lobbyStroke.Enabled = chosen == "Lobby"
	local locked = chosen ~= ""
	againButton.AutoButtonColor = not locked
	lobbyButton.AutoButtonColor = not locked
	againButton.BackgroundTransparency = if locked and chosen ~= "PlayAgain" then 0.6 else 0
	lobbyButton.BackgroundTransparency = if locked and chosen ~= "Lobby" then 0.6 else 0
	if chosen == "PlayAgain" then
		choiceHint.Text = "Waiting for the others — a new run starts soon"
	elseif chosen == "Lobby" then
		choiceHint.Text = "Going to the lobby..."
	else
		choiceHint.Text = "Same team, new run — or back to the lobby"
	end
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
			-- Имя, поймал (и сколько заработал арестами), сколько денег у него сейчас, алмазы за ночь
			Text = ('%s   caught: %d <font color="#3FB56B">(+$%d)</font>   money: <font color="#D4A93A">$%d</font>   <font color="#%s">+%d 💎</font>%s'):format(
				name,
				tonumber(catches[userIdText]) or 0,
				tonumber(amount) or 0,
				tonumber(wallets[userIdText]) or 0,
				Colors.Diamond:ToHex(),
				tonumber(gems[userIdText]) or 0,
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
	then "SHOP button — or hold the button at boarded doors, pedestals and CAMERA SPOT signs"
	else "B — shop, or hold F at boarded doors, pedestals and CAMERA SPOT signs"
-- Этап 4, блок 1b: в первый день — где магазин
local HINT_SHOP = if touchOnly
	then "Tap SHOP to buy halls, exhibits, cameras and weapons"
	else "Press B to open the shop — halls, exhibits, cameras, weapons"
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
		if (tonumber(GameState.get(Attr.NightNumber)) or 1) <= Config.Shop.HintNights then
			return HINT_SHOP
		end
		local money = tonumber(localPlayer:GetAttribute(PlayerAttr.Money)) or 0
		local closedHall = false
		for _, list in { GameState.PaidHalls, GameState.WingOrder } do -- залы и крылья (этап 5, блок B)
			for _, hall in list do
				if not GameState.isHallOpen(hall) then
					closedHall = true
				end
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
	topLabel.Text = topBarText(phase)
	moneyLabel.Text = "$" .. tostring(localPlayer:GetAttribute(PlayerAttr.Money) or 0)

	countRounds(phase)
	local hint = hintText(phase)
	hintFrame.Visible = hint ~= nil
	if hint then
		hintLabel.Text = hint
	end

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
		resultsFooter.Text = if resultsGameOver
			then "Back to the lobby in " .. left
			else ("Day %d starts in %s"):format((tonumber(GameState.get(Attr.NightNumber)) or 0) + 1, left)
	elseif phase == Phase.Lobby or phase == Phase.Day then
		-- Прячем итог только в лобби: событие с итогом может прийти чуть раньше смены фазы
		resultsFrame.Visible = false
		choiceOpen = false
		choiceBar.Visible = false
	end
end)
