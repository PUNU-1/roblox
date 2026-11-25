-- Окно голосования за опоздавшего: «Let <имя> join the team?» — YES / NO и обратный отсчёт.
-- Голос отправляется на сервер, решает сервер (половина или больше «за»).
-- С клавиатуры — Y / N: в виде от первого лица мышь заперта в центре экрана.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Colors = Theme.Colors
local keyboard = UserInputService.KeyboardEnabled
local VOTE_ACTION = "VoteKeys"

local gui = Theme.screenGui("Vote", 5)
local panel = Theme.new("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 112), -- под деньгами и кнопкой SHOP (этап 4, блок 1b)
	Size = UDim2.new(0, 300, 0, 120),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
}, { Theme.corner(14), Theme.stroke(Colors.Gold, 2), Theme.padding(10) })

local question = Theme.label({
	Size = UDim2.new(1, 0, 0.45, 0),
	Font = Theme.BodyFont,
	MaxTextSize = 22,
	Text = "",
	Parent = panel,
})
local timer = Theme.label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 40, 0, 20),
	TextColor3 = Colors.Gold,
	MaxTextSize = 18,
	Parent = panel,
})
local yesButton = Theme.button({
	Position = UDim2.new(0, 0, 0.55, 0),
	Size = UDim2.new(0.48, 0, 0.45, 0),
	BackgroundColor3 = Colors.Green,
	Text = if keyboard then "YES (Y)" else "YES",
	Parent = panel,
})
local noButton = Theme.button({
	Position = UDim2.new(0.52, 0, 0.55, 0),
	Size = UDim2.new(0.48, 0, 0.45, 0),
	BackgroundColor3 = Colors.Red,
	Text = if keyboard then "NO (N)" else "NO",
	Parent = panel,
})

local currentId: number? = nil
local endsAt = 0

local function hidePanel()
	currentId = nil
	panel.Visible = false
	ContextActionService:UnbindAction(VOTE_ACTION)
end

local function answer(yes: boolean)
	if currentId then
		Remotes.get(Remotes.Names.VoteCast):FireServer(currentId, yes)
	end
	hidePanel()
end

local function onVoteKey(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	answer(input.KeyCode == Enum.KeyCode.Y)
	return Enum.ContextActionResult.Sink
end

yesButton.Activated:Connect(function()
	answer(true)
end)
noButton.Activated:Connect(function()
	answer(false)
end)

Remotes.get(Remotes.Names.VoteRequest).OnClientEvent:Connect(function(id, name, seconds)
	if typeof(id) ~= "number" or typeof(name) ~= "string" or typeof(seconds) ~= "number" then
		return
	end
	if id == 0 or seconds <= 0 then
		hidePanel()
		return
	end
	currentId = id
	endsAt = os.clock() + seconds
	question.Text = ("Let %s join the team?"):format(name)
	panel.Visible = true
	ContextActionService:BindAction(VOTE_ACTION, onVoteKey, false, Enum.KeyCode.Y, Enum.KeyCode.N)
end)

GameState.folder():GetAttributeChangedSignal(GameState.Attr.Phase):Connect(function()
	local phase = GameState.phase()
	if phase == GameState.Phase.Lobby or phase == GameState.Phase.Results then
		hidePanel()
	end
end)

RunService.Heartbeat:Connect(function()
	if not panel.Visible then
		return
	end
	local left = endsAt - os.clock()
	if left <= 0 then
		hidePanel()
		return
	end
	timer.Text = tostring(math.ceil(left))
end)
