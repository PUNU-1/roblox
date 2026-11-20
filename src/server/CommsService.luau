-- Связь: метка оператора на вора и готовые фразы.
-- Метка — красная стрелка над вором, видна всем сквозь стены и держится несколько секунд.
-- Сервер проверяет: игрок правда смотрит камеры, это правда вор, вор виден с какой-то камеры.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))

local CommsService = {}

local cameraPoints: { BasePart } = {}
local lastMark: { [Player]: number } = {}
local lastPhrase: { [Player]: number } = {}
local markTokens: { [Model]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function visibleFromSomeCamera(position: Vector3): boolean
	for _, point in cameraPoints do
		if (point.Position - position).Magnitude <= Config.Comms.MarkMaxDistance then
			return true
		end
	end
	return false
end

local function placeMark(thief: Model)
	local head = thief:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local billboard = head:FindFirstChild("OperatorMark")
	if not billboard then
		local created = Instance.new("BillboardGui")
		created.Name = "OperatorMark"
		created.AlwaysOnTop = true -- видно сквозь стены
		created.Size = UDim2.new(0, Config.Effects.MarkSize, 0, Config.Effects.MarkSize)
		created.StudsOffset = Vector3.new(0, Config.Effects.MarkHeight, 0)
		created.LightInfluence = 0
		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.Size = UDim2.fromScale(1, 1)
		arrow.Text = "▼"
		arrow.TextScaled = true
		arrow.Font = Enum.Font.FredokaOne
		arrow.TextColor3 = Config.Effects.MarkColor
		arrow.TextStrokeTransparency = 0
		arrow.Parent = created
		created.Parent = head
	end
	local token = (markTokens[thief] or 0) + 1
	markTokens[thief] = token
	task.delay(Config.Comms.MarkSeconds, function()
		if markTokens[thief] == token then
			markTokens[thief] = nil
			local existing = head:FindFirstChild("OperatorMark")
			if existing then
				existing:Destroy()
			end
		end
	end)
end

local function onMarkThief(player: Player, thief: any)
	if typeof(thief) ~= "Instance" or not thief:IsA("Model") then
		return
	end
	if GameState.phase() ~= GameState.Phase.Night or not RoleService.isViewing(player) then
		return
	end
	if not ThiefService.isThief(thief) or ThiefService.isArrested(thief) then
		return
	end
	local time = now()
	if time - (lastMark[player] or 0) < Config.Comms.MarkCooldown then
		return
	end
	local root = thief:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or not visibleFromSomeCamera(root.Position) then
		return
	end
	lastMark[player] = time
	placeMark(thief)
end

local function onQuickPhrase(player: Player, index: any)
	if typeof(index) ~= "number" or index ~= math.floor(index) then
		return
	end
	if index < 1 or index > #Config.Comms.Phrases then
		return
	end
	local time = now()
	if time - (lastPhrase[player] or 0) < Config.Comms.PhraseCooldown then
		return
	end
	lastPhrase[player] = time
	Remotes.get(Remotes.Names.PhraseShown):FireAllClients(player.UserId, index)
end

function CommsService.init(map: Instance)
	local folder = map:FindFirstChild(MapSchema.CameraPoints)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(cameraPoints, child)
			end
		end
	end
	Remotes.get(Remotes.Names.MarkThief).OnServerEvent:Connect(onMarkThief)
	Remotes.get(Remotes.Names.QuickPhrase).OnServerEvent:Connect(onQuickPhrase)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastMark[player] = nil
		lastPhrase[player] = nil
	end)
end

return CommsService
