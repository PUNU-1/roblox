-- Охранники (блок 3): охранник от удара Громилы падает на спину, лежит и встаёт.
--  • Все клиенты двигают суставы сбитого охранника (Transform) по атрибутам KnockedAt / KnockedUntil,
--    которые пишет сервер (RoleService.knockDown): падает назад, руки в стороны, голова кружится, встаёт.
--  • Сам сбитый охранник видит это от первого лица: вид опускается к полу, смотрит в потолок, потом поднимается.
--  • Звёздочки над головой (BillboardGui от сервера) кружатся.
--  • Свою кнопку «Check ID» (её видят другие охранники) у себя прячем: проверять самого себя незачем.
-- Это только картинка: лежит охранник или нет, решает сервер (он и не даёт ходить и ловить).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local PlayerAttr = GameState.PlayerAttr
local Settings = Config.Knockdown

local localPlayer = Players.LocalPlayer

local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip", "LeftKnee", "RightKnee" }

type Joint = Motor6D | AnimationConstraint

-- Персонажи, у которых мы сейчас двигаем суставы (чтобы вернуть их, когда охранник встал).
local touched: { [Model]: { [string]: Joint } } = {}
local cameraTouched = false

local function R(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

local function findJoints(character: Model): { [string]: Joint }
	local found: { [string]: Joint } = {}
	for _, descendant in character:GetDescendants() do
		if (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) and table.find(JOINTS, descendant.Name) then
			found[descendant.Name] = descendant :: any
		end
	end
	return found
end

-- Насколько охранник лежит: 0 — стоит, 1 — лежит. Быстро падает, лежит, в конце встаёт.
local function amount(elapsed: number, duration: number): number
	if elapsed < Settings.FallSeconds then
		return math.sin(elapsed / Settings.FallSeconds * math.pi / 2)
	end
	local riseFrom = duration - Settings.RiseSeconds
	if elapsed > riseFrom then
		return 1 - smooth((elapsed - riseFrom) / Settings.RiseSeconds)
	end
	return 1
end

-- Поза сбитого охранника. k — насколько лежит. Корень заваливается назад вокруг бёдер и опускается к полу,
-- руки раскинуты над головой, ноги чуть согнуты, голова покачивается.
local function knockPose(character: Model, k: number, clock: number): { [string]: CFrame }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	local rootHalf = if root and root:IsA("BasePart") then root.Size.Y / 2 else 1
	local down = (hipHeight + rootHalf - 0.8) * k
	local back = hipHeight * 0.8 * k
	local wobble = math.sin(clock * 2.5)
	return {
		Root = CFrame.new(0, -down, back) * R(Settings.Tilt * k, 0, 0),
		Waist = R(0.12 * k),
		Neck = R(0.3 * k, 0, 0.28 * k * wobble),
		LeftShoulder = R(2.2 * k, 0, -0.55 * k),
		RightShoulder = R(2.0 * k, 0, 0.65 * k),
		LeftElbow = R(0.5 * k),
		RightElbow = R(0.6 * k),
		LeftHip = R(0.35 * k, 0, -0.15 * k),
		RightHip = R(0.15 * k, 0, 0.2 * k),
		LeftKnee = R(-0.6 * k),
		RightKnee = R(-0.3 * k),
	}
end

local function release(character: Model)
	local joints = touched[character]
	if joints then
		for _, joint in joints do
			if joint.Parent then
				joint.Transform = CFrame.identity
			end
		end
		touched[character] = nil
	end
end

local function spinStars(character: Model, clock: number)
	local head = character:FindFirstChild("Head")
	local billboard = head and head:FindFirstChild("DizzyStars")
	local label = billboard and billboard:FindFirstChild("Stars")
	if label and label:IsA("TextLabel") then
		label.Rotation = (clock * Settings.StarsSpin) % 360
	end
end

-- Свой вид, пока лежишь: камера ниже, смотрит вверх и чуть набок (поверх обычной камеры первого лица).
local function ownCamera(k: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, -Settings.CameraDrop * k, 0)
	end
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CFrame = camera.CFrame * CFrame.Angles(Settings.CameraPitch * k, 0, Settings.CameraRoll * k)
	end
	cameraTouched = k > 0
end

local function step()
	local clock = Workspace:GetServerTimeNow()
	local ownKnocked = false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local at = player:GetAttribute(PlayerAttr.KnockedAt)
		local untilTime = player:GetAttribute(PlayerAttr.KnockedUntil)
		local knocked = character ~= nil and typeof(at) == "number" and typeof(untilTime) == "number" and clock >= at and clock < untilTime
		if knocked and character then
			local k = amount(clock - at, untilTime - at)
			local joints = touched[character] or findJoints(character)
			touched[character] = joints
			local pose = knockPose(character, k, clock)
			for name, joint in joints do
				if joint.Parent then
					joint.Transform = pose[name] or CFrame.identity
				end
			end
			spinStars(character, clock)
			if player == localPlayer then
				ownKnocked = true
				ownCamera(k)
			end
		elseif character and touched[character] then
			release(character)
		end
	end
	if not ownKnocked and cameraTouched then
		ownCamera(0)
	end
	for character in touched do
		if not character.Parent then
			touched[character] = nil
		end
	end
end

-- Своя кнопка Check ID видна только другим: у себя выключаем её (только на этом клиенте)
local function hideOwnPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt.Name == "CheckIdPrompt" then
		prompt.Enabled = false
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if prompt.Enabled then
				prompt.Enabled = false -- сервер включил после перезарядки — у себя снова прячем
			end
		end)
	end
end

local function watchCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		hideOwnPrompt(descendant)
	end
	character.DescendantAdded:Connect(hideOwnPrompt)
end

localPlayer.CharacterAdded:Connect(watchCharacter)
if localPlayer.Character then
	watchCharacter(localPlayer.Character)
end

-- Позу пишем последней перед отрисовкой кадра, после стандартных анимаций Roblox (как в NpcAnimator)
RunService:BindToRenderStep("GuardKnockdown", Enum.RenderPriority.Last.Value, step)
