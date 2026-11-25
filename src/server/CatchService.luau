-- Поимка: у каждого вора кнопка «Arrest» (ProximityPrompt). Охранник держит её 1 сек рядом с вором.
-- Если вор убежал дальше, чем достаёт кнопка, удержание сбрасывается само.
-- Арест: руки вверх -> наручники -> облачко «пуф». Картина возвращается на стену.
-- Сервер ещё раз проверяет фазу, роль и расстояние: клиенту не доверяем.
-- Check ID (блок 3): с ночи Фальшивого охранника на каждом охраннике кнопка «Check ID» (1 сек). На настоящем
-- игроке — «ID OK» тому, кто проверял, и короткая перезарядка; на Фальшивом охраннике та же кнопка — арест.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local RoleService = require(Server:WaitForChild("RoleService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
local RobberService = require(Server:WaitForChild("RobberService"))
local Audio = require(Server:WaitForChild("Audio"))

local CatchService = {}

local SILVER = Color3.fromHex("C9CED6")
local HANDCUFFS_STUB: { ModelLibrary.StubPart } = {
	{ name = "CuffLeft", size = Vector3.new(0.4, 0.4, 0.15), offset = CFrame.new(-0.4, 0, 0), color = SILVER, material = Enum.Material.Metal },
	{ name = "CuffRight", size = Vector3.new(0.4, 0.4, 0.15), offset = CFrame.new(0.4, 0, 0), color = SILVER, material = Enum.Material.Metal },
	{ name = "Chain", size = Vector3.new(0.45, 0.08, 0.08), offset = CFrame.identity, color = SILVER, material = Enum.Material.Metal },
}

local function poof(position: Vector3)
	local cloud = Instance.new("Part")
	cloud.Name = "Poof"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.new(1, 1, 1)
	cloud.Position = position
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Material = Enum.Material.Neon
	cloud.Color = Color3.fromRGB(235, 235, 235)
	cloud.Transparency = 0.2
	cloud.Parent = Workspace
	local size = Config.Effects.PoofSize
	local tween = TweenService:Create(cloud, TweenInfo.new(Config.Effects.PoofSeconds), {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		cloud:Destroy()
	end)
	tween:Play()
end

local function attachHandcuffs(model: Model)
	local hand = model:FindFirstChild("LeftHand")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local cuffs = ModelLibrary.build(MapSchema.Models.Handcuffs, HANDCUFFS_STUB)
	-- Наручники привариваются к левой кисти: у клиентов кисть двигает анимация ареста,
	-- и наручники оказываются между сведёнными руками
	local offset = Config.Catch.HandcuffsOffset
	ModelLibrary.weldTo(cuffs, hand, hand.CFrame * CFrame.new(offset.X, offset.Y, offset.Z))
	cuffs.Parent = model
end

-- «+$5» всплывает над головой пойманного вора и тает к моменту «пуф» (деньги — тому, кто арестовал).
local function showReward(model: Model)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local reward = Config.Effects.Reward
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Reward"
	billboard.Size = UDim2.fromScale(reward.Width, reward.Height)
	billboard.StudsOffset = Vector3.new(0, reward.StartHeight, 0)
	billboard.MaxDistance = reward.MaxDistance
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "+$" .. tostring(Config.Money.PerArrest)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = reward.Color
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = head
	local seconds = Config.Thief.ArrestSeconds
	TweenService:Create(billboard, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, reward.EndHeight, 0),
	}):Play()
	-- Тает в конце, чтобы надпись успели прочитать
	TweenService:Create(label, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function tryArrest(player: Player, model: Model, prompt: ProximityPrompt, robber: boolean?)
	if GameState.phase() ~= GameState.Phase.Night then
		return
	end
	if not RoleService.canAct(player) then
		return -- смотрит камеры, лежит после удара Громилы или без сил
	end
	local entry = holdStarted[player]
	holdStarted[player] = nil
	if not entry or entry.prompt ~= prompt or Workspace:GetServerTimeNow() - entry.at < Config.Catch.HoldSeconds - 0.3 then
		return
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local thiefRoot = model:FindFirstChild("HumanoidRootPart")
	if not (playerRoot and playerRoot:IsA("BasePart") and thiefRoot and thiefRoot:IsA("BasePart")) then
		return
	end
	local maxDistance = Config.Catch.MaxDistance + Config.Catch.ServerDistanceSlack
	if (playerRoot.Position - thiefRoot.Position).Magnitude > maxDistance then
		return
	end
	-- Грабителя (блок 4) можно арестовать, только пока он сдался или оглушён шокером
	local arrested = if robber then RobberService.arrest(model) else ThiefService.arrest(model)
	if not arrested then
		return
	end

	prompt.Enabled = false
	ScoreService.addCatch(player)
	attachHandcuffs(model)
	showReward(model)
	Audio.playOnce(Config.Sounds.Arrest, thiefRoot, Config.Sounds.ArrestVolume)

	task.delay(Config.Thief.ArrestSeconds, function()
		if model.Parent then
			poof(thiefRoot.Position)
			if robber then
				RobberService.remove(model)
			else
				ThiefService.remove(model)
			end
		end
	end)
end

local ThiefAttr = GameState.ThiefAttr
local CHECK_PROMPT = "CheckIdPrompt"
local checkActive = false
local holdStarted: { [Player]: { prompt: ProximityPrompt, at: number } } = {}

local function hookHold(prompt: ProximityPrompt)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if RoleService.canAct(player) then
			holdStarted[player] = { prompt = prompt, at = Workspace:GetServerTimeNow() }
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		local entry = holdStarted[player]
		if entry and entry.prompt == prompt then
			holdStarted[player] = nil
		end
	end)
end

-- Подпись кнопки на воре: у Фальшивого охранника — как у настоящего («Check ID» и ник), пока он не схватил экспонат.
local function labelArrestPrompt(model: Model, prompt: ProximityPrompt)
	local disguise = model:GetAttribute(ThiefAttr.Disguise)
	if typeof(disguise) == "string" then
		prompt.ActionText = "Check ID"
		prompt.ObjectText = disguise
	else
		prompt.ActionText = "Arrest"
		prompt.ObjectText = "Thief"
	end
end

local function onThiefSpawned(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArrestPrompt"
	labelArrestPrompt(model, prompt)
	model:GetAttributeChangedSignal(ThiefAttr.Disguise):Connect(function()
		labelArrestPrompt(model, prompt)
	end)
	prompt.HoldDuration = Config.Catch.HoldSeconds
	prompt.MaxActivationDistance = Config.Catch.MaxDistance
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	hookHold(prompt)
	prompt.Triggered:Connect(function(player)
		tryArrest(player, model, prompt)
	end)
end

-- Грабитель налёта (блок 4): кнопка «Arrest» видна, только пока он сдался полиции или лежит после шокера.
local function onRobberSpawned(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArrestPrompt"
	prompt.ActionText = "Arrest"
	prompt.ObjectText = "Robber"
	prompt.HoldDuration = Config.Catch.HoldSeconds
	prompt.MaxActivationDistance = Config.Catch.MaxDistance
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.RequiresLineOfSight = false
	prompt.Enabled = model:GetAttribute(RobberService.ArrestableAttr) == true
	prompt.Parent = root
	model:GetAttributeChangedSignal(RobberService.ArrestableAttr):Connect(function()
		prompt.Enabled = model:GetAttribute(RobberService.ArrestableAttr) == true
	end)
	hookHold(prompt)
	prompt.Triggered:Connect(function(player)
		tryArrest(player, model, prompt, true)
	end)
end

---------------------------------------------------------------- Check ID на охранниках

local function onCheckId(checker: Player, target: Player, prompt: ProximityPrompt)
	if GameState.phase() ~= GameState.Phase.Night or checker == target then
		return
	end
	if not RoleService.canAct(checker) or RoleService.isDowned(target) then
		return
	end
	local checkerRoot = checker.Character and checker.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not (checkerRoot and checkerRoot:IsA("BasePart") and targetRoot and targetRoot:IsA("BasePart")) then
		return
	end
	if (checkerRoot.Position - targetRoot.Position).Magnitude > Config.Catch.MaxDistance + Config.Catch.ServerDistanceSlack then
		return
	end
	-- Настоящий охранник: «ID OK» тому, кто проверял, и кнопка ненадолго гаснет
	Remotes.get(Remotes.Names.Banner):FireClient(checker, ("ID OK — %s is a real guard"):format(target.DisplayName), "info")
	prompt.Enabled = false
	task.delay(Config.Catch.CheckIdCooldown, function()
		if prompt.Parent and checkActive and not RoleService.isDowned(target) then
			prompt.Enabled = true
		end
	end)
end

local function addCheckPrompt(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or root:FindFirstChild(CHECK_PROMPT) or not RoleService.isParticipant(player) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CHECK_PROMPT
	prompt.ActionText = "Check ID"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = Config.Catch.HoldSeconds
	prompt.MaxActivationDistance = Config.Catch.MaxDistance
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not RoleService.isDowned(player) -- на лежащем без сил охраннике — кнопка Revive
	prompt.Parent = root
	prompt.Triggered:Connect(function(checker)
		onCheckId(checker, player, prompt)
	end)
end

local function removeCheckPrompts()
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild(CHECK_PROMPT)
		if prompt then
			prompt:Destroy()
		end
	end
end

-- Ночь началась: с ночи Фальшивого охранника на всех охранниках кнопка Check ID (чтобы его не выдала кнопка ареста).
function CatchService.beginNight(night: number)
	removeCheckPrompts()
	checkActive = Config.Waves.TestUnlockAll or night >= Config.Plans.FakeGuard.FromNight
	if checkActive then
		for _, player in RoleService.participants() do
			addCheckPrompt(player)
		end
	end
end

function CatchService.endNight()
	checkActive = false
	removeCheckPrompts()
end

local function watchPlayer(player: Player)
	-- Упал без сил — Check ID на нём прячется (на одной клавише F Roblox покажет только Revive), встал — снова видна
	player:GetAttributeChangedSignal(GameState.PlayerAttr.Downed):Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild(CHECK_PROMPT)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = checkActive and not RoleService.isDowned(player)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		-- Новый персонаж посреди ночи тоже получает кнопку (когда появится HumanoidRootPart)
		character:WaitForChild("HumanoidRootPart", 10)
		if checkActive then
			addCheckPrompt(player)
		end
	end)
end

function CatchService.init()
	ThiefService.Spawned.Event:Connect(onThiefSpawned)
	RobberService.Spawned.Event:Connect(onRobberSpawned)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		holdStarted[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return CatchService
