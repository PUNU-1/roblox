-- Окно голосования за опоздавшего: «Let <имя> join the team?» — YES / NO и обратный отсчёт.
-- Голос отправляется на сервер, решает сервер (половина или больше «за»).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Colors = Theme.Colors

local gui = Theme.screenGui("Vote", 5)
local panel = Theme.new("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 70),
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
	Text = "YES",
	Parent = panel,
})
local noButton = Theme.button({
	Position = UDim2.new(0.52, 0, 0.55, 0),
	Size = UDim2.new(0.48, 0, 0.45, 0),
	BackgroundColor3 = Colors.Red,
	Text = "NO",
	Parent = panel,
})

local currentId: number? = nil
local endsAt = 0

local function answer(yes: boolean)
	if currentId then
		Remotes.get(Remotes.Names.VoteCast):FireServer(currentId, yes)
	end
	currentId = nil
	panel.Visible = false
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
	currentId = id
	endsAt = os.clock() + seconds
	question.Text = ("Let %s join the team?"):format(name)
	panel.Visible = true
end)

RunService.Heartbeat:Connect(function()
	if not panel.Visible then
		return
	end
	local left = endsAt - os.clock()
	if left <= 0 then
		currentId = nil
		panel.Visible = false
		return
	end
	timer.Text = tostring(math.ceil(left))
end)
