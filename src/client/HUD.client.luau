-- Интерфейс игрока: лобби (роль и READY), верхняя строка (таймер, часы ночи),
-- деньги, крупные надписи и экран итога ночи. Клиент только показывает и шлёт намерения.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local gui = Theme.screenGui("HUD", 1)

local ROLE_INFO = {
	[Role.Patrol] = "Runs through the museum and arrests thieves.",
	[Role.Operator] = "Also has a phone with the cameras (Tab). Can't move while looking at it.",
}

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

---------------------------------------------------------------- лобби

local lobbyPanel = Theme.new("Frame", {
	Name = "Lobby",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.new(0.5, 0, 0.45, 0),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, {
	Theme.corner(16),
	Theme.stroke(Colors.Gold, 3),
	Theme.padding(12),
	Theme.new("UISizeConstraint", { MinSize = Vector2.new(320, 260) }),
})

Theme.label({ Text = "CHOOSE YOUR ROLE", TextColor3 = Colors.Gold, Size = UDim2.fromScale(1, 0.12), Parent = lobbyPanel })

local roleButtons: { [string]: TextButton } = {
	[Role.Patrol] = Theme.button({
		Text = "PATROL",
		Position = UDim2.fromScale(0, 0.15),
		Size = UDim2.fromScale(0.48, 0.2),
		Parent = lobbyPanel,
	}),
	[Role.Operator] = Theme.button({
		Text = "OPERATOR",
		Position = UDim2.fromScale(0.52, 0.15),
		Size = UDim2.fromScale(0.48, 0.2),
		Parent = lobbyPanel,
	}),
}

local roleInfo = Theme.label({
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	Position = UDim2.fromScale(0, 0.37),
	Size = UDim2.fromScale(1, 0.12),
	MaxTextSize = 18,
	Parent = lobbyPanel,
})

local readyButton = Theme.button({
	Text = "READY",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromScale(0.6, 0.18),
	BackgroundColor3 = Colors.Green,
	MaxTextSize = 34,
	Parent = lobbyPanel,
})

local playerList = Theme.label({
	Font = Theme.BodyFont,
	RichText = true,
	TextColor3 = Colors.White,
	Position = UDim2.fromScale(0, 0.74),
	Size = UDim2.fromScale(1, 0.26),
	MaxTextSize = 18,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = lobbyPanel,
})

for role, button in roleButtons do
	button.Activated:Connect(function()
		Remotes.get(Remotes.Names.SetRole):FireServer(role)
	end)
end

readyButton.Activated:Connect(function()
	Remotes.get(Remotes.Names.SetReady):FireServer(localPlayer:GetAttribute(PlayerAttr.Ready) ~= true)
end)

local function refreshLobby()
	local myRole = localPlayer:GetAttribute(PlayerAttr.Role) or Role.Patrol
	for role, button in roleButtons do
		local selected = role == myRole
		button.BackgroundColor3 = if selected then Colors.Gold else Colors.NavyLight
		button.TextColor3 = if selected then Colors.Navy else Colors.White
	end
	roleInfo.Text = ROLE_INFO[myRole] or ""

	local ready = localPlayer:GetAttribute(PlayerAttr.Ready) == true
	readyButton.Text = if ready then "READY ✓" else "READY"
	readyButton.BackgroundColor3 = if ready then Colors.Gold else Colors.Green

	local lines = {}
	for _, player in Players:GetPlayers() do
		local mark = if player:GetAttribute(PlayerAttr.Ready) == true then "✓" else "…"
		table.insert(lines, ("%s — %s %s"):format(player.DisplayName, tostring(player:GetAttribute(PlayerAttr.Role) or Role.Patrol), mark))
	end
	playerList.Text = table.concat(lines, "\n")
end

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
local resultsList = Theme.new("Frame", {
	Position = UDim2.fromScale(0, 0.33),
	Size = UDim2.fromScale(1, 0.54),
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

	local earnings = if typeof(results.earnings) == "table" then results.earnings else {}
	local catches = if typeof(results.catches) == "table" then results.catches else {}
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
			Text = ('%s   <font color="#D4A93A">+$%d</font>   caught: %d%s'):format(
				name,
				tonumber(amount) or 0,
				tonumber(catches[userIdText]) or 0,
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

-- На телефоне и планшете без клавиатуры вместо клавиш — кнопки на экране
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local HINT_PLACE = if touchOnly
	then "Hold the button on a glowing spot to place a laser grid"
	else "Hold E on a glowing spot to place a laser grid"
local HINT_ARREST = if touchOnly then "Hold the button next to a thief to arrest him" else "Hold E next to a thief to arrest him"
local HINT_PHONE = if touchOnly then "Phone button — cameras" else "Tab — cameras"
local HINT_CONSOLE = "Camera console: end of the north corridor"
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
	local hasPhone = localPlayer:GetAttribute(PlayerAttr.Role) == Role.Operator or GameState.get(Attr.Solo) == true
	local cameras = if hasPhone then HINT_PHONE else HINT_CONSOLE
	if phase == Phase.Day then
		if Config.Traps.LaserGrid.Enabled and (tonumber(GameState.get(Attr.LasersLeft)) or 0) > 0 then
			return HINT_PLACE
		end
		local money = tonumber(localPlayer:GetAttribute(PlayerAttr.Money)) or 0
		local closedHall = not GameState.isHallOpen(GameState.Hall.Jewelry) or not GameState.isHallOpen(GameState.Hall.Sculptures)
		if closedHall and money >= Config.Halls.ContributeStep then
			return "Hold E at a boarded door to chip in for a new hall   •   " .. cameras
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

local function topBarText(phase: string): string
	local left = GameState.secondsLeft()
	if phase == Phase.Lobby then
		if left > 0 then
			return "The museum opens in " .. Theme.formatTime(left)
		end
		return "Choose a role and press READY"
	elseif phase == Phase.Day then
		return ("DAY %d   •   Night in %s   •   Tourists: %d"):format(
			tonumber(GameState.get(Attr.NightNumber)) or 1,
			Theme.formatTime(left),
			tonumber(GameState.get(Attr.TouristsToday)) or 0
		)
	elseif phase == Phase.Night then
		local started = GameState.get(Attr.NightStartedAt)
		local elapsed = if typeof(started) == "number" then Workspace:GetServerTimeNow() - started else 0
		return ("NIGHT %d   •   %s   •   Caught: %d"):format(
			tonumber(GameState.get(Attr.NightNumber)) or 1,
			Theme.nightClock(elapsed),
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

	lobbyPanel.Visible = phase == Phase.Lobby
	if lobbyPanel.Visible then
		refreshLobby()
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
