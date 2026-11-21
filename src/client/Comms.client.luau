-- Готовые фразы: кнопка на экране (или T) открывает список, нажал фразу (или её цифру) — она всплывает у всех.
-- Q / E / C не заняты: они понадобятся для наклонов и приседа (блок 4).
-- Работает и на ПК, и на телефоне (касанием). Пока список открыт, курсор свободен (вид от первого лица).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local Colors = Theme.Colors

local gui = Theme.screenGui("Comms", 3)
local keyboard = UserInputService.KeyboardEnabled

local TOGGLE_ACTION = "QuickPhrases"
local PICK_ACTION = "PickPhrase"
local DIGIT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }

-- Слева посередине: внизу слева на телефоне джойстик движения
local toggleButton = Theme.button({
	Name = "PhrasesButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.45, 0),
	Size = UDim2.new(0, 120, 0, 50),
	BackgroundColor3 = Colors.Navy,
	Text = if keyboard then "💬 Say (T)" else "💬 Say",
	Parent = gui,
})
Theme.stroke(Colors.Gold, 2).Parent = toggleButton

local list = Theme.new("Frame", {
	Name = "PhraseList",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 146, 0.45, 0),
	Size = UDim2.new(0, 260, 0, #Config.Comms.Phrases * 46),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

local function say(index: number)
	Remotes.get(Remotes.Names.QuickPhrase):FireServer(index)
end

local setListOpen: (boolean) -> ()

for index, phrase in Config.Comms.Phrases do
	local button = Theme.button({
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Colors.NavyLight,
		Font = Theme.BodyFont,
		Text = if keyboard and DIGIT_KEYS[index] then ("%d  %s"):format(index, phrase) else phrase,
		MaxTextSize = 20,
		Modal = index == 1, -- пока список виден, курсор свободен
		Parent = list,
	})
	button.Activated:Connect(function()
		say(index)
		setListOpen(false)
	end)
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

toggleButton.Activated:Connect(function()
	setListOpen(not list.Visible)
end)

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

-- Лента фраз слева сверху
local feed = Theme.new("Frame", {
	Name = "Feed",
	Position = UDim2.new(0, 16, 0, 70),
	Size = UDim2.new(0, 360, 0, 160),
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
		Size = UDim2.new(1, 0, 0, 30),
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
	if #lines > 4 then
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

-- Кнопка фраз нужна только на смене
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then
		return
	end
	accumulator = 0
	local phase = GameState.phase()
	local show = phase == Phase.Day or phase == Phase.Night
	toggleButton.Visible = show
	setToggleBound(show)
	if not show then
		setListOpen(false)
	end
end)
