-- Готовые фразы: кнопка на экране открывает список, нажал фразу — она всплывает у всех.
-- Работает и на ПК (мышью), и на телефоне (касанием).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local Colors = Theme.Colors

local gui = Theme.screenGui("Comms", 3)

-- Слева посередине: внизу слева на телефоне джойстик движения
local toggleButton = Theme.button({
	Name = "PhrasesButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.45, 0),
	Size = UDim2.new(0, 120, 0, 50),
	BackgroundColor3 = Colors.Navy,
	Text = "💬 Say",
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

for index, phrase in Config.Comms.Phrases do
	local button = Theme.button({
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Colors.NavyLight,
		Font = Theme.BodyFont,
		Text = phrase,
		MaxTextSize = 20,
		Parent = list,
	})
	button.Activated:Connect(function()
		Remotes.get(Remotes.Names.QuickPhrase):FireServer(index)
		list.Visible = false
	end)
end

toggleButton.Activated:Connect(function()
	list.Visible = not list.Visible
end)

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
	local show = phase == Phase.Prep or phase == Phase.Night
	toggleButton.Visible = show
	if not show then
		list.Visible = false
	end
end)
