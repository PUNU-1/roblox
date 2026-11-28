-- Готовые фразы: кнопка на экране (или T) открывает список, нажал фразу (или её цифру) — она всплывает у всех.
-- Q / E / C не заняты: они понадобятся для наклонов и приседа (блок 4).
-- Работает и на ПК, и на телефоне (касанием). Пока список открыт, курсор свободен (вид от первого лица).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local PixelButton = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelButton"))

local Phase = GameState.Phase
local Colors = Theme.Colors
local localPlayer = Players.LocalPlayer

local gui = Theme.screenGui("Comms", 3)
local keyboard = not Theme.touchOnly()
local MobileMenu = require(script.Parent:WaitForChild("UI"):WaitForChild("MobileMenu"))

local TOGGLE_ACTION = "QuickPhrases"
local PICK_ACTION = "PickPhrase"
local DIGIT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }

-- Слева посередине: внизу слева на телефоне джойстик движения
-- Пиксельная кнопка без рамки и фона, как в хабе (этап 5, блок D)
local setListOpen: (boolean) -> ()
local list: Frame
local toggleButton = PixelButton.new({
	icon = "Chat",
	label = "SAY",
	key = "T",
	cell = Config.PixelUI.HudCell,
	name = "PhrasesButton",
	parent = gui,
	onActivated = function()
		setListOpen(not list.Visible)
	end,
})
toggleButton.root.AnchorPoint = Vector2.new(0, 0.5)
toggleButton.root.Position = UDim2.new(0, 16, 0.45, 0)

-- Телефон (этап 8, блок Q): кнопка SAY — в «Меню» (MobileMenu), список фраз — двумя столбиками слева сверху,
-- под верхней полосой (слева внизу джойстик, справа кнопки). Видна ли кнопка — так же по toggleButton.root.Visible,
-- только сама кнопка не на экране.
local PHRASE_W, PHRASE_H = if keyboard then 280 else 230, if keyboard then 40 else 36
local phraseRows = if keyboard then #Config.Comms.Phrases else math.ceil(#Config.Comms.Phrases / 2)
list = Theme.new("Frame", {
	Name = "PhraseList",
	AnchorPoint = if keyboard then Vector2.new(0, 0.5) else Vector2.new(0, 0),
	Position = if keyboard then UDim2.new(0, 16 + toggleButton.width() + 10, 0.45, 0) else UDim2.fromOffset(Config.Mobile.Margin, 62),
	Size = UDim2.new(0, if keyboard then PHRASE_W else 2 * PHRASE_W + 6, 0, phraseRows * (PHRASE_H + 6)),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
if keyboard then
	Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
else
	toggleButton.root.Parent = nil
	Theme.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(PHRASE_W, PHRASE_H),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
end

local function say(index: number)
	Remotes.get(Remotes.Names.QuickPhrase):FireServer(index)
end

for index, phrase in Config.Comms.Phrases do
	local button = PixelButton.text({
		text = string.upper(if keyboard and DIGIT_KEYS[index] then ("%d %s"):format(index, phrase) else phrase),
		color = Colors.NavyLight,
		textSize = 8,
		size = UDim2.new(1, 0, 0, PHRASE_H),
		parent = list,
		onActivated = function()
			say(index)
			setListOpen(false)
		end,
	})
	button.root.LayoutOrder = index
	button.root.Modal = index == 1 -- пока список виден, курсор свободен
end

-- Цифры выбирают фразу, только пока список открыт (иначе цифры переключают камеры)
local function onPick(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local index = table.find(DIGIT_KEYS, input.KeyCode)
	if index and Config.Comms.Phrases[index] then
		say(index)
		setListOpen(false)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

setListOpen = function(open: boolean)
	if list.Visible == open then
		return
	end
	list.Visible = open
	if open then
		local keys = {}
		for index in Config.Comms.Phrases do
			table.insert(keys, DIGIT_KEYS[index])
		end
		ContextActionService:BindActionAtPriority(PICK_ACTION, onPick, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	else
		ContextActionService:UnbindAction(PICK_ACTION)
	end
end


local toggleBound = false
local function setToggleBound(bound: boolean)
	if bound == toggleBound then
		return
	end
	toggleBound = bound
	if bound then
		ContextActionService:BindAction(TOGGLE_ACTION, function(_name, state)
			if state == Enum.UserInputState.Begin then
				setListOpen(not list.Visible)
			end
			return Enum.ContextActionResult.Sink
		end, false, Config.Keys.Phrases)
	else
		ContextActionService:UnbindAction(TOGGLE_ACTION)
	end
end

-- Лента фраз слева сверху (на телефоне — ниже плашки шага обучения и уже, до 3 строк)
local FEED_LINE = if keyboard then 30 else 24
local FEED_MAX = if keyboard then 4 else 2
local feed = Theme.new("Frame", {
	Name = "Feed",
	Position = if keyboard then UDim2.new(0, 16, 0, 70) else UDim2.fromOffset(Config.Mobile.Margin, 144),
	Size = if keyboard then UDim2.new(0, 360, 0, 160) else UDim2.new(0, 300, 0, FEED_MAX * (FEED_LINE + 4)),
	BackgroundTransparency = 1,
	Parent = gui,
})
Theme.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = feed })
local feedOrder = 0

Remotes.get(Remotes.Names.PhraseShown).OnClientEvent:Connect(function(userId, index)
	local phrase = typeof(index) == "number" and Config.Comms.Phrases[index]
	if not phrase then
		return
	end
	local player = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local name = if player then player.DisplayName else "Guard"

	feedOrder += 1
	local line = Theme.label({
		LayoutOrder = feedOrder,
		Size = UDim2.new(1, 0, 0, FEED_LINE),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Colors.Navy,
		RichText = true,
		Font = Theme.BodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Text = ('<font color="#D4A93A">%s:</font> %s'):format(name, phrase),
		Parent = feed,
	})
	Theme.corner(8).Parent = line
	Theme.padding(4).Parent = line
	local lines = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	if #lines > FEED_MAX then
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		lines[1]:Destroy()
	end
	task.delay(Config.Comms.PhraseShowSeconds, function()
		if line.Parent then
			line:Destroy()
		end
	end)

	-- Облачко над головой того, кто сказал (если в игре включены облачка чата)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		pcall(function()
			TextChatService:DisplayBubble(head, phrase)
		end)
	end
end)

MobileMenu.add({
	id = "Say",
	icon = "Chat",
	label = "SAY",
	order = 4,
	visible = function()
		return toggleButton.root.Visible
	end,
	onActivated = function()
		setListOpen(not list.Visible)
	end,
})

-- Кнопка фраз нужна только на смене
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then
		return
	end
	accumulator = 0
	local phase = GameState.phase()
	local show = localPlayer:GetAttribute(GameState.PlayerAttr.InRound) == true and (phase == Phase.Day or phase == Phase.Night)
	toggleButton.root.Visible = show
	setToggleBound(show)
	if not show then
		setListOpen(false)
	end
end)
