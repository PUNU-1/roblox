-- Поимка: у каждого вора кнопка «Arrest» (ProximityPrompt). Охранник держит её 1 сек рядом с вором.
-- Если вор убежал дальше, чем достаёт кнопка, удержание сбрасывается само.
-- Арест: руки вверх -> наручники -> облачко «пуф». Картина возвращается на стену.
-- Сервер ещё раз проверяет фазу, роль и расстояние: клиенту не доверяем.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local RoleService = require(Server:WaitForChild("RoleService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
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

local function tryArrest(player: Player, model: Model, prompt: ProximityPrompt)
	if GameState.phase() ~= GameState.Phase.Night then
		return
	end
	if not RoleService.isParticipant(player) or RoleService.isViewing(player) then
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
	if not ThiefService.arrest(model) then
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
			ThiefService.remove(model)
		end
	end)
end

local function onThiefSpawned(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArrestPrompt"
	prompt.ActionText = "Arrest"
	prompt.ObjectText = "Thief"
	prompt.HoldDuration = Config.Catch.HoldSeconds
	prompt.MaxActivationDistance = Config.Catch.MaxDistance
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		tryArrest(player, model, prompt)
	end)
end

function CatchService.init()
	ThiefService.Spawned.Event:Connect(onThiefSpawned)
end

return CatchService
