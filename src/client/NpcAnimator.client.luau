-- Анимации NPC кодом: воры и туристы. Каждый клиент сам двигает суставы R15 (Transform) по состоянию,
-- которое сервер пишет в атрибут модели (AnimState). Воры: крадётся, бежит, снимает экспонат, несёт,
-- арест. Туристы: гуляет, смотрит на экспонат, фотографирует.
-- В Roblox ничего загружать не нужно, а сеть не нагружается: Transform видит только этот клиент.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Anim = GameState.ThiefAnim
local TouristAnim = GameState.TouristAnim
local NpcAttr = GameState.NpcAttr
local Settings = Config.Animations

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

type Pose = { [string]: CFrame }

-- Сустав: у старых персонажей Motor6D, у новых (CreateHumanoidModelFromDescription) — AnimationConstraint.
-- У обоих есть Transform.
type Joint = Motor6D | AnimationConstraint

type Rig = {
	root: BasePart,
	motors: { [string]: Joint },
	jointCount: number,
	current: Pose,
	phase: number,
	lastPosition: Vector3,
	speed: number,
}

local rigs: { [Model]: Rig } = {}

---------------------------------------------------------------- помощники

-- Поворот сустава в радианах. У суставов R15 ось X — вправо: +X машет рукой или ногой вперёд.
local function R(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- Плавно от 0 до 1 (медленно в начале и в конце).
local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Ноги. move: 0 — стоит, 1 — полный шаг. crouch — насколько согнуты колени, toe < 0 — на цыпочках.
local function legs(pose: Pose, phase: number, move: number, swing: number, lift: number, crouch: number, toe: number)
	local s = math.sin(phase)
	local c = math.cos(phase)
	pose.LeftHip = R(crouch + swing * s * move)
	pose.RightHip = R(crouch - swing * s * move)
	pose.LeftKnee = R(-2 * crouch - lift * math.max(0, c) * move)
	pose.RightKnee = R(-2 * crouch - lift * math.max(0, -c) * move)
	pose.LeftAnkle = R(crouch + toe)
	pose.RightAnkle = R(crouch + toe)
end

-- Руки «лапками» перед грудью, как у мультяшного вора.
local function pawArms(pose: Pose, sway: number)
	pose.LeftShoulder = R(1.0 - sway, 0, 0.2)
	pose.RightShoulder = R(1.0 + sway, 0, -0.2)
	pose.LeftElbow = R(1.4)
	pose.RightElbow = R(1.4)
	pose.LeftWrist = R(-0.8)
	pose.RightWrist = R(-0.8)
end

---------------------------------------------------------------- позы

-- Крадётся на цыпочках: сгорбился, голова вперёд и вертится, большие плавные шаги.
local function sneakPose(clock: number, phase: number, move: number): Pose
	local pose: Pose = {}
	local s = math.sin(phase)
	pose.Root = CFrame.new(0, -0.18 + 0.1 * math.abs(s) * move, 0)
	pose.Waist = R(-0.35, 0.12 * s * move, 0)
	pose.Neck = R(0.3, 0.45 * math.sin(clock * 1.6), 0)
	pawArms(pose, 0.15 * s * move)
	legs(pose, phase, move, 0.65, 0.7, 0.25, -0.4)
	return pose
end

-- Бежит: наклон вперёд, руки машут навстречу ногам.
local function runPose(phase: number, move: number): Pose
	local pose: Pose = {}
	local s = math.sin(phase)
	pose.Root = CFrame.new(0, -0.1 + 0.18 * math.abs(s) * move, 0)
	pose.Waist = R(-0.25, 0.1 * s * move, 0)
	pose.Neck = R(0.15)
	pose.LeftShoulder = R(-0.9 * s * move, 0, 0.1)
	pose.RightShoulder = R(0.9 * s * move, 0, -0.1)
	pose.LeftElbow = R(1.3)
	pose.RightElbow = R(1.3)
	legs(pose, phase, move, 0.9, 1.1, 0.1, 0)
	return pose
end

-- Несёт экспонат над головой: руки вверх и чуть покачиваются, ноги бегут.
local function carryPose(phase: number, move: number): Pose
	local pose: Pose = {}
	local s = math.sin(phase)
	local wobble = 0.08 * s * move
	pose.Root = CFrame.new(0, -0.1 + 0.15 * math.abs(s) * move, 0)
	pose.Waist = R(-0.1)
	pose.Neck = R(-0.05)
	pose.LeftShoulder = R(2.9 + wobble, 0, -0.15)
	pose.RightShoulder = R(2.9 - wobble, 0, 0.15)
	pose.LeftElbow = R(0.35)
	pose.RightElbow = R(0.35)
	legs(pose, phase, move, 0.8, 1.0, 0.1, 0)
	return pose
end

-- Снимает экспонат: оглядывается влево-вправо, потом тянется вверх на цыпочках и снимает.
local function stealPose(t: number): Pose
	local pose: Pose = {}
	local look = Settings.StealLookSeconds
	local reach = Settings.StealReachSeconds
	pose.Root = CFrame.new(0, -0.1, 0)
	if t < look then
		local side = math.sin(t / look * math.pi * 2)
		pose.Neck = R(0.1, 0.8 * side, 0)
		pose.Waist = R(-0.15, 0.25 * side, 0)
		pawArms(pose, 0)
		legs(pose, 0, 0, 0, 0, 0.1, 0)
		return pose
	end
	local k = smooth((t - look) / reach)
	local tug = if t > look + reach then 0.08 * math.sin((t - look - reach) * 9) else 0
	local up = lerp(1.0, 2.8, k) + tug
	pose.Neck = R(lerp(0.1, 0.5, k))
	pose.Waist = R(lerp(-0.15, 0.1, k))
	pose.LeftShoulder = R(up, 0, lerp(0.2, -0.15, k))
	pose.RightShoulder = R(up, 0, lerp(-0.2, 0.15, k))
	pose.LeftElbow = R(lerp(1.4, 0.3, k))
	pose.RightElbow = R(lerp(1.4, 0.3, k))
	pose.LeftWrist = R(lerp(-0.8, 0, k))
	pose.RightWrist = R(lerp(-0.8, 0, k))
	legs(pose, 0, 0, 0, 0, 0.1, -0.5 * k)
	return pose
end

-- Арест: резко руки вверх, потом руки вперёд и вместе (там наручники), голова вниз.
local function arrestPose(t: number): Pose
	local pose: Pose = {}
	local upTime = Settings.ArrestHandsUpSeconds
	local cuffTime = Settings.ArrestCuffSeconds
	legs(pose, 0, 0, 0, 0, 0.05, 0)
	if t < upTime then
		local k = smooth(t / upTime)
		pose.LeftShoulder = R(lerp(0, 3.0, k), 0, lerp(0, -0.3, k))
		pose.RightShoulder = R(lerp(0, 3.0, k), 0, lerp(0, 0.3, k))
		pose.LeftElbow = R(0.2)
		pose.RightElbow = R(0.2)
		pose.Neck = R(0.2 * k)
		return pose
	end
	local k = smooth((t - upTime) / cuffTime)
	pose.Root = CFrame.new(0, -0.1 * k, 0)
	pose.Waist = R(lerp(0, -0.2, k))
	pose.Neck = R(lerp(0.2, -0.55, k))
	pose.LeftShoulder = R(lerp(3.0, 0.55, k), 0, lerp(-0.3, 0.68, k))
	pose.RightShoulder = R(lerp(3.0, 0.55, k), 0, lerp(0.3, -0.68, k))
	pose.LeftElbow = R(lerp(0.2, 0.9, k))
	pose.RightElbow = R(lerp(0.2, 0.9, k))
	return pose
end

-- Турист гуляет: спокойный шаг, руки слегка покачиваются, головой вертит по сторонам.
local function strollPose(clock: number, phase: number, move: number): Pose
	local pose: Pose = {}
	local s = math.sin(phase)
	pose.Root = CFrame.new(0, 0.06 * math.abs(s) * move, 0)
	pose.Neck = R(0.05, 0.25 * math.sin(clock * 0.7), 0)
	pose.LeftShoulder = R(-0.4 * s * move, 0, -0.08)
	pose.RightShoulder = R(0.4 * s * move, 0, 0.08)
	pose.LeftElbow = R(0.3)
	pose.RightElbow = R(0.3)
	legs(pose, phase, move, 0.55, 0.6, 0.03, 0)
	return pose
end

-- Турист смотрит на экспонат: руки за спиной, голова чуть вверх и покачивается.
local function admirePose(clock: number): Pose
	local pose: Pose = {}
	pose.Neck = R(0.18, 0.15 * math.sin(clock * 0.5), 0)
	pose.Waist = R(0.05, 0.08 * math.sin(clock * 0.4), 0)
	pose.LeftShoulder = R(-0.45, 0, 0.25)
	pose.RightShoulder = R(-0.45, 0, -0.25)
	pose.LeftElbow = R(1.1)
	pose.RightElbow = R(1.1)
	legs(pose, 0, 0, 0, 0, 0, 0)
	return pose
end

-- Турист фотографирует: руки с телефоном перед лицом, лёгкий наклон назад.
local function photoPose(clock: number): Pose
	local pose: Pose = {}
	pose.Neck = R(0.05)
	pose.Waist = R(0.08 + 0.02 * math.sin(clock * 2), 0, 0)
	pose.LeftShoulder = R(1.25, 0, 0.6)
	pose.RightShoulder = R(1.25, 0, -0.6)
	pose.LeftElbow = R(1.1)
	pose.RightElbow = R(1.1)
	legs(pose, 0, 0, 0, 0, 0, 0)
	return pose
end

local function poseFor(state: any, t: number, clock: number, phase: number, move: number): Pose
	if state == TouristAnim.Stroll then
		return strollPose(clock, phase, move)
	elseif state == TouristAnim.Admire then
		return admirePose(clock)
	elseif state == TouristAnim.Photo then
		return photoPose(clock)
	elseif state == Anim.Run then
		return runPose(phase, move)
	elseif state == Anim.Carry then
		return carryPose(phase, move)
	elseif state == Anim.Steal then
		return stealPose(t)
	elseif state == Anim.Arrest then
		return arrestPose(t)
	end
	return sneakPose(clock, phase, move)
end

---------------------------------------------------------------- воры в мире

local function findJoints(model: Model): ({ [string]: Joint }, number)
	local motors: { [string]: Joint } = {}
	local count = 0
	for _, descendant in model:GetDescendants() do
		if (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) and table.find(JOINTS, descendant.Name) then
			if not motors[descendant.Name] then
				count += 1
			end
			motors[descendant.Name] = descendant :: any
		end
	end
	return motors, count
end

local function register(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) or not model.Parent then
		return
	end
	local motors, count = findJoints(model)
	rigs[model] = {
		root = root,
		motors = motors,
		jointCount = count,
		current = {},
		phase = 0,
		lastPosition = root.Position,
		speed = 0,
	}
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local clock = Workspace:GetServerTimeNow()
	local blend = 1 - math.exp(-dt * Settings.BlendSpeed)
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		-- Скорость считаем сами по сдвигу: так одинаково работает и у бегущего, и у замершего вора
		local position = rig.root.Position
		local moved = Vector3.new(position.X - rig.lastPosition.X, 0, position.Z - rig.lastPosition.Z).Magnitude
		rig.lastPosition = position
		local instant = if dt > 0 then moved / dt else 0
		rig.speed += (instant - rig.speed) * math.min(1, dt * 8)
		if (position - cameraPosition).Magnitude > Settings.CullDistance then
			continue
		end

		local state = model:GetAttribute(NpcAttr.AnimState)
		local startedAt = model:GetAttribute(NpcAttr.AnimStateAt)
		local t = if typeof(startedAt) == "number" then math.max(0, clock - startedAt) else 0
		local stride = if state == Anim.Sneak then Settings.SneakStride
			elseif state == TouristAnim.Stroll then Settings.StrollStride
			else Settings.RunStride
		rig.phase = (rig.phase + rig.speed * dt * stride) % (math.pi * 2)
		local move = math.clamp(rig.speed / 6, 0, 1)

		local target = poseFor(state, t, clock, rig.phase, move)
		-- Суставы догружаются по сети уже после появления вора (а Roblox может их пересобрать) — ищем заново
		local stale = rig.jointCount < #JOINTS
		if not stale then
			for _, motor in rig.motors do
				if not motor.Parent then
					stale = true
					break
				end
			end
		end
		if stale then
			rig.motors, rig.jointCount = findJoints(model)
		end
		for name, motor in rig.motors do
			local current = (rig.current[name] or CFrame.identity):Lerp(target[name] or CFrame.identity, blend)
			rig.current[name] = current
			motor.Transform = current
		end
	end
end

-- Следим за папками с ворами и туристами
for _, folderName in { MapSchema.Thieves, MapSchema.Tourists } do
	local folder = Workspace:WaitForChild(folderName)
	folder.ChildAdded:Connect(function(child)
		task.spawn(register, child)
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			rigs[child] = nil
		end
	end)
	for _, child in folder:GetChildren() do
		task.spawn(register, child)
	end
end

-- Позу пишем последней перед отрисовкой кадра: иначе встроенный Animator может перезаписать её
-- (порядок обработчиков одного события зависит от того, кто подключился раньше)
RunService:BindToRenderStep("NpcAnimator", Enum.RenderPriority.Last.Value, step)
