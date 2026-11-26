-- Окно голосования за опоздавшего: «Let <имя> join the team?» — YES / NO и обратный отсчёт.
-- Голос отправляется на сервер, решает сервер (половина или больше «за»).
-- С клавиатуры — Y / N: в виде от первого лица мышь заперта в центре экрана.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local PixelButton = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelButton"))
local PixelWindow = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local keyboard = not Theme.touchOnly()
local VOTE_ACTION = "VoteKeys"

local gui = Theme.screenGui("Vote", 5)
local panel = Theme.new("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 136), -- под деньгами и кнопкой SHOP (этап 4, блок 1b; пиксельная SHOP выше — блок D)
	Size = UDim2.new(0, 300, 0, 120),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
-- Пиксельная рамка, как у окон хаба (этап 5, блок D); всё содержимое — во внутренней части
local inset = PixelWindow.box(panel)
local content = Theme.new("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(inset + 4, inset + 4),
	Size = UDim2.new(1, -2 * inset - 8, 1, -2 * inset - 8),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = panel,
})

local question = Theme.pixelLabel({
	Size = UDim2.new(1, -40, 0.45, 0),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
	Parent = content,
}, 8)
local timer = Theme.pixelLabel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 40, 0, 20),
	TextColor3 = Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 3,
	Parent = content,
}, 16)
local answer: (yes: boolean) -> ()
PixelButton.text({
	text = if keyboard then "YES (Y)" else "YES",
	color = Colors.Green,
	textSize = 8,
	position = UDim2.new(0, 0, 0.5, 0),
	size = UDim2.new(0.48, 0, 0.5, 0),
	zIndex = 3,
	parent = content,
	onActivated = function()
		answer(true)
	end,
})
PixelButton.text({
	text = if keyboard then "NO (N)" else "NO",
	color = Colors.Red,
	textSize = 8,
	position = UDim2.new(0.52, 0, 0.5, 0),
	size = UDim2.new(0.48, 0, 0.5, 0),
	zIndex = 3,
	parent = content,
	onActivated = function()
		answer(false)
	end,
})

local currentId: number? = nil
local endsAt = 0

local function hidePanel()
	currentId = nil
	panel.Visible = false
	ContextActionService:UnbindAction(VOTE_ACTION)
end

answer = function(yes: boolean)
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
