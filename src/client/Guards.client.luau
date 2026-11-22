-- Позы охранников (блоки 3–4). Каждый клиент сам двигает суставы чужих персонажей (Motor6D.Transform) по атрибутам,
-- которые пишет сервер, — поверх обычных анимаций Roblox (ходьба, прыжок):
--  • удар Громилы: падает на спину, лежит со звёздочками, встаёт (KnockedAt / KnockedUntil);
--  • без сил (блок 4): падает лицом вниз, лежит и ползёт, руки по очереди тянутся вперёд (Downed); встаёт (RevivedAt);
--  • поднимает друга: на одном колене, руки вперёд-вниз, качается в такт (ReviveTarget);
--  • оружие в руках, выстрел, перезарядка, аптечка, присед, наклон (блок 4, позы — ниже, «стойка и оружие»).
-- Сам игрок своё тело не видит (вид от первого лица): ему — только камера (ниже, когда лежит, присел, наклон).
-- Свои кнопки «Check ID» и «Revive» (их видят другие охранники) у себя прячем.
-- Это только картинка: что с охранником, решает сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local PlayerAttr = GameState.PlayerAttr
local Knock = Config.Knockdown
local HealthSettings = Config.Health
local Stance = Config.Stance

local localPlayer = Players.LocalPlayer

local JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
}

type Joint = Motor6D | AnimationConstraint
type Pose = { [string]: CFrame }

-- Состояние одного персонажа: суставы, наша поза поверх анимации и её вес по каждому суставу.
type Rig = {
	joints: { [string]: Joint },
	current: Pose, -- наша поза (плавно догоняет нужную)
	weights: { [string]: number }, -- 0 — сустав двигает обычная анимация, 1 — наша поза
	phase: number, -- шаг (ползёт, идёт присев)
	lastPosition: Vector3?,
	speed: number,
}

local rigs: { [Model]: Rig } = {}

---------------------------------------------------------------- помощники

local function R(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

local function number(player: Player, attr: string): number
	return tonumber(player:GetAttribute(attr)) or 0
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

-- Сколько стадов от корня до пола (персонажи бывают разного роста).
local function rootHeight(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hip = if humanoid then humanoid.HipHeight else 2
	local half = if root and root:IsA("BasePart") then root.Size.Y / 2 else 1
	return hip + half
end

---------------------------------------------------------------- удар Громилы (блок 3)

-- Насколько охранник лежит: 0 — стоит, 1 — лежит. Быстро падает, лежит, в конце встаёт.
local function knockAmount(elapsed: number, duration: number): number
	if elapsed < Knock.FallSeconds then
		return math.sin(elapsed / Knock.FallSeconds * math.pi / 2)
	end
	local riseFrom = duration - Knock.RiseSeconds
	if elapsed > riseFrom then
		return 1 - smooth((elapsed - riseFrom) / Knock.RiseSeconds)
	end
	return 1
end

-- Сбит с ног: корень заваливается назад и опускается к полу, руки раскинуты, голова покачивается.
local function knockPose(character: Model, k: number, clock: number): Pose
	local height = rootHeight(character)
	local down = (height - 0.8) * k
	local back = (height - 1) * 0.8 * k
	local wobble = math.sin(clock * 2.5)
	return {
		Root = CFrame.new(0, -down, back) * R(Knock.Tilt * k, 0, 0),
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

local function knockState(player: Player, clock: number): number
	local at = number(player, PlayerAttr.KnockedAt)
	local untilTime = number(player, PlayerAttr.KnockedUntil)
	if untilTime > clock and clock >= at then
		return knockAmount(clock - at, untilTime - at)
	end
	return 0
end

---------------------------------------------------------------- без сил: лежит и ползёт (блок 4)

-- Насколько охранник лежит без сил: падает за FallSeconds, после подъёма встаёт за RiseSeconds.
local function downAmount(player: Player, clock: number): number
	if player:GetAttribute(PlayerAttr.Downed) == true then
		return smooth((clock - number(player, PlayerAttr.DownedAt)) / HealthSettings.FallSeconds)
	end
	local rose = clock - number(player, PlayerAttr.RevivedAt)
	if rose >= 0 and rose < HealthSettings.RiseSeconds then
		return 1 - smooth(rose / HealthSettings.RiseSeconds)
	end
	return 0
end

-- Лежит лицом вниз, голова поднята; ползёт: руки по очереди тянутся вперёд и подтягивают тело, ноги толкаются.
local function crawlPose(character: Model, k: number, phase: number, move: number, clock: number): Pose
	local height = rootHeight(character)
	local s = math.sin(phase)
	local c = math.cos(phase)
	local breathe = 0.04 * math.sin(clock * 2)
	return {
		Root = CFrame.new(0, -(height - 0.75) * k, 0) * R(-1.5 * k, 0.06 * s * move * k, 0),
		Waist = R(breathe * k, 0.14 * s * move * k, 0),
		Neck = R(1.05 * k, 0.15 * math.sin(clock * 0.7) * k, 0),
		LeftShoulder = R((2.55 + 0.45 * s * move) * k, 0, -0.25 * k),
		RightShoulder = R((2.55 - 0.45 * s * move) * k, 0, 0.25 * k),
		LeftElbow = R((0.55 - 0.4 * s * move) * k),
		RightElbow = R((0.55 + 0.4 * s * move) * k),
		LeftHip = R((0.05 - 0.28 * s * move) * k, 0, -0.12 * k),
		RightHip = R((0.05 + 0.28 * s * move) * k, 0, 0.12 * k),
		LeftKnee = R((-0.25 - 0.6 * math.max(0, c) * move) * k),
		RightKnee = R((-0.25 - 0.6 * math.max(0, -c) * move) * k),
		LeftAnkle = R(0.5 * k),
		RightAnkle = R(0.5 * k),
	}
end

-- Поднимает друга: на правом колене, наклонился, руки вперёд-вниз, качается в такт.
local function revivePose(clock: number): Pose
	local pump = math.sin(clock * 5)
	return {
		Root = CFrame.new(0, -1.15, 0),
		RightHip = R(0.1),
		RightKnee = R(-1.55),
		RightAnkle = R(0.6),
		LeftHip = R(1.5),
		LeftKnee = R(-1.5),
		LeftAnkle = R(0.1),
		Waist = R(-0.55 - 0.08 * pump),
		Neck = R(-0.3),
		LeftShoulder = R(0.95 + 0.12 * pump, 0, 0.22),
		RightShoulder = R(0.95 + 0.12 * pump, 0, -0.22),
		LeftElbow = R(0.35),
		RightElbow = R(0.35),
		LeftWrist = R(-0.4),
		RightWrist = R(-0.4),
	}
end

---------------------------------------------------------------- стойка и оружие (блок 4, 4.2–4.4)

-- Поза стоящего охранника с оружием, присевшего или в наклоне. nil — обычная анимация Roblox.
-- (заполняется в следующих пунктах блока 4)
local function standingPose(_player: Player, _character: Model, _rig: Rig, _clock: number): Pose?
	return nil
end

---------------------------------------------------------------- кадр

local function poseFor(player: Player, character: Model, rig: Rig, clock: number): (Pose?, number)
	local knocked = knockState(player, clock)
	if knocked > 0 then
		return knockPose(character, knocked, clock), 0.06 -- падение уже плавное (knockAmount): вес сразу
	end
	local down = downAmount(player, clock)
	if down > 0 then
		local move = math.clamp(rig.speed / HealthSettings.CrawlSpeed, 0, 1)
		return crawlPose(character, down, rig.phase, move, clock), 0.06
	end
	if number(player, PlayerAttr.ReviveTarget) ~= 0 then
		return revivePose(clock), 0.25
	end
	return standingPose(player, character, rig, clock), 0.2
end

local function newRig(character: Model): Rig
	return { joints = findJoints(character), current = {}, weights = {}, phase = 0, lastPosition = nil, speed = 0 }
end

local function step(dt: number)
	local clock = Workspace:GetServerTimeNow()
	local blend = 1 - math.exp(-dt * 14)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or player == localPlayer then
			continue -- себя не видно (первое лицо)
		end
		local rig = rigs[character]
		if not rig then
			rig = newRig(character)
			rigs[character] = rig
		end
		-- Скорость по сдвигу корня: для шага ползком и присев
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local position = root.Position
			local last = rig.lastPosition or position
			local moved = Vector3.new(position.X - last.X, 0, position.Z - last.Z).Magnitude
			rig.lastPosition = position
			local instant = if dt > 0 then moved / dt else 0
			rig.speed += (instant - rig.speed) * math.min(1, dt * 8)
			rig.phase = (rig.phase + rig.speed * dt * 0.9) % (math.pi * 2)
		end
		local pose, fade = poseFor(player, character, rig, clock)
		-- Плавно: наш вес по каждому суставу растёт к 1 (поза есть) или падает к 0 (обычная анимация)
		local weightBlend = 1 - math.exp(-dt / math.max(0.05, fade) * 3)
		for name, joint in rig.joints do
			if not joint.Parent then
				rig.joints = findJoints(character) -- Roblox пересобрал суставы
				break
			end
			local target = pose and pose[name]
			local weight = rig.weights[name] or 0
			weight += ((if target then 1 else 0) - weight) * weightBlend
			if weight < 0.002 and not target then
				rig.weights[name] = nil
				rig.current[name] = nil
				continue
			end
			rig.weights[name] = weight
			local current = rig.current[name] or joint.Transform
			if target then
				current = current:Lerp(target, blend)
			end
			rig.current[name] = current
			-- joint.Transform сейчас — свежая поза обычной анимации: смешиваем её с нашей
			joint.Transform = joint.Transform:Lerp(current, weight)
		end
		-- Звёздочки над головой сбитого охранника кружатся
		local head = character:FindFirstChild("Head")
		local stars = head and head:FindFirstChild("DizzyStars")
		local label = stars and stars:FindFirstChild("Stars")
		if label and label:IsA("TextLabel") then
			label.Rotation = (clock * Knock.StarsSpin) % 360
		end
	end
	for character in rigs do
		if not character.Parent then
			rigs[character] = nil
		end
	end
end

---------------------------------------------------------------- свой вид

local lastPitch = 0
local cameraOffset = Vector3.zero
local lastRoll = 0

-- Камера своего охранника: ниже, когда лежит без сил или сбит, присел; вбок и с наклоном — в наклоне (Q / E).
local function ownCamera(dt: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local clock = Workspace:GetServerTimeNow()
	local knocked = knockState(localPlayer, clock)
	local down = downAmount(localPlayer, clock)
	local crouch = if localPlayer:GetAttribute(PlayerAttr.Crouch) == true then 1 else 0
	local lean = number(localPlayer, PlayerAttr.Lean)
	if down > 0 or knocked > 0 then
		crouch, lean = 0, 0
	end
	local drop = math.max(Knock.CameraDrop * knocked, HealthSettings.CameraDrop * down, Stance.CrouchDrop * crouch)
	local target = Vector3.new(lean * Stance.LeanOffset, -drop, 0)
	cameraOffset = cameraOffset:Lerp(target, 1 - math.exp(-dt * Stance.BlendSpeed))
	if (humanoid.CameraOffset - cameraOffset).Magnitude > 0.001 then
		humanoid.CameraOffset = cameraOffset
	end
	local camera = Workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		lastPitch = 0
		return
	end
	-- Камера Roblox запоминает, куда смотрит: наклон вверх добавляем приращением (сбит — смотрит в потолок, встал — обратно)
	local pitch = Knock.CameraPitch * knocked
	local roll = Knock.CameraRoll * knocked - lean * Stance.LeanRoll
	lastRoll += (roll - lastRoll) * (1 - math.exp(-dt * Stance.BlendSpeed))
	camera.CFrame = camera.CFrame * CFrame.Angles(pitch - lastPitch, 0, 0) * CFrame.Angles(0, 0, lastRoll)
	lastPitch = pitch
end

---------------------------------------------------------------- свои кнопки

-- Свои кнопки Check ID и Revive видны только другим: у себя выключаем их (только на этом клиенте)
local OWN_HIDDEN = { CheckIdPrompt = true, RevivePrompt = true }

local function hideOwnPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and OWN_HIDDEN[prompt.Name] then
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

localPlayer.CharacterAdded:Connect(function(character)
	lastPitch = 0
	cameraOffset = Vector3.zero
	watchCharacter(character)
end)
if localPlayer.Character then
	watchCharacter(localPlayer.Character)
end

-- Позы пишем последними перед отрисовкой кадра, после обычных анимаций Roblox (как в NpcAnimator);
-- камеру — сразу после камеры Roblox
RunService:BindToRenderStep("GuardPoses", Enum.RenderPriority.Last.Value, step)
RunService:BindToRenderStep("GuardCamera", Enum.RenderPriority.Camera.Value + 1, ownCamera)
