-- Собаки кинологов (блок 5) — только картинка; что собака чует и когда лает, решает сервер (AbilityService).
-- Сервер ставит модель собаки (Workspace.Dogs, закреплена), а каждый клиент двигает её детали сам:
--  • идёт по следу хозяина чуть позади и левее (по следу — значит, не срезает углы сквозь стены);
--    отстала или хозяина перенесли (к Моне Лизе, в лобби) — появляется рядом;
--  • шагает рысью, на бегу — галопом; хозяин стоит — собака садится, смотрит на него, машет хвостом, дышит;
--  • рядом вор (атрибут Alert, вор — ObjectValue Target): стоит, хвост трубой, смотрит на вора, над ней «!»;
--  • лай (атрибут BarkAt): «гав-гав» — челюсть открывается, голова вскидывается, звук.
-- Кости — по началу имени деталей (ClassModels.boneOf), точки вращения — атрибуты Bone_* у модели.
-- Этот же модуль оживляет собаку на карточке класса в лобби (ClassCards).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ClassModels = require(Shared:WaitForChild("ClassModels"))

local Settings = Config.Classes.Dog
local DogAttr = GameState.DogAttr

local DogAnimator = {}

---------------------------------------------------------------- скелет и поза

export type Rig = {
	parts: { BasePart },
	rest: { CFrame }, -- где деталь относительно точки привязки собаки в покое
	bones: { string },
	pivots: { [string]: Vector3 },
	cframes: { CFrame },
	known: { [BasePart]: boolean },
}

export type Pose = {
	bodyY: number, -- вверх-вниз (покачивание, сесть)
	sit: number, -- поворот туловища вокруг задних лап (сидит — перед поднят)
	rock: number, -- наклон туловища вперёд-назад (галоп)
	roll: number, -- покачивание с боку на бок (рысь)
	headYaw: number,
	headPitch: number,
	headTilt: number, -- голова набок (умилительно)
	jaw: number, -- рот открыт
	tailYaw: number, -- хвост машет
	tailLift: number, -- хвост вниз (+) или вверх (−)
	tail2Lift: number,
	legFL: number, -- лапы: + — вперёд
	legFR: number,
	legBL: number,
	legBR: number,
}

local POSE_KEYS = {
	"bodyY", "sit", "rock", "roll", "headYaw", "headPitch", "headTilt", "jaw",
	"tailYaw", "tailLift", "tail2Lift", "legFL", "legFR", "legBL", "legBR",
}

function DogAnimator.newPose(): Pose
	return {
		bodyY = 0, sit = 0, rock = 0, roll = 0, headYaw = 0, headPitch = 0, headTilt = 0, jaw = 0,
		tailYaw = 0, tailLift = 0, tail2Lift = 0, legFL = 0, legFR = 0, legBL = 0, legBR = 0,
	}
end

local function defaultPivots(): { [string]: Vector3 }
	local pivots = {}
	for _, bone in ClassModels.DogBones do
		pivots[bone.name] = bone.pivot
	end
	return pivots
end

function DogAnimator.newRig(pivots: { [string]: Vector3 }?): Rig
	return { parts = {}, rest = {}, bones = {}, pivots = pivots or defaultPivots(), cframes = {}, known = {} }
end

-- Добавить деталь: rest — где она относительно точки привязки собаки, когда собака стоит.
function DogAnimator.addPart(rig: Rig, part: BasePart, rest: CFrame)
	if rig.known[part] then
		return
	end
	rig.known[part] = true
	table.insert(rig.parts, part)
	table.insert(rig.rest, rest)
	table.insert(rig.bones, ClassModels.boneOf(part))
	table.insert(rig.cframes, rest)
end

local function around(pivot: Vector3, rotation: CFrame): CFrame
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot)
end

local boneFrames: { [string]: CFrame } = {}

-- Поставить детали по позе. bulk — детали в мире (Workspace:BulkMoveTo), иначе — по одной (ViewportFrame).
function DogAnimator.solve(rig: Rig, root: CFrame, pose: Pose, bulk: boolean)
	local pv = rig.pivots
	local hips = (pv.LegBL + pv.LegBR) / 2
	local body = CFrame.new(0, pose.bodyY, 0)
		* around(hips, CFrame.Angles(pose.sit, 0, 0))
		* around(pv.Body, CFrame.Angles(pose.rock, 0, pose.roll))
	local head = body * around(pv.Head, CFrame.Angles(0, pose.headYaw, 0) * CFrame.Angles(pose.headPitch, 0, pose.headTilt))
	local tail1 = body * around(pv.Tail1, CFrame.Angles(0, pose.tailYaw, 0) * CFrame.Angles(pose.tailLift, 0, 0))
	boneFrames.Body = body
	boneFrames.Head = head
	boneFrames.Jaw = head * around(pv.Jaw, CFrame.Angles(-pose.jaw, 0, 0))
	boneFrames.Tail1 = tail1
	boneFrames.Tail2 = tail1 * around(pv.Tail2, CFrame.Angles(0, pose.tailYaw * 0.8, 0) * CFrame.Angles(pose.tail2Lift, 0, 0))
	boneFrames.LegFL = body * around(pv.LegFL, CFrame.Angles(pose.legFL, 0, 0))
	boneFrames.LegFR = body * around(pv.LegFR, CFrame.Angles(pose.legFR, 0, 0))
	boneFrames.LegBL = body * around(pv.LegBL, CFrame.Angles(pose.legBL, 0, 0))
	boneFrames.LegBR = body * around(pv.LegBR, CFrame.Angles(pose.legBR, 0, 0))
	local cframes = rig.cframes
	for index, rest in rig.rest do
		cframes[index] = root * (boneFrames[rig.bones[index]] or body) * rest
	end
	if bulk then
		Workspace:BulkMoveTo(rig.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for index, part in rig.parts do
			part.CFrame = cframes[index]
		end
	end
end

local function blendPose(pose: Pose, target: Pose, dt: number)
	local a = 1 - math.exp(-dt * Settings.BlendSpeed)
	local p, q = pose :: any, target :: any
	for _, key in POSE_KEYS do
		p[key] += (q[key] - p[key]) * a
	end
end

local function clearPose(pose: Pose)
	local p = pose :: any
	for _, key in POSE_KEYS do
		p[key] = 0
	end
end

-- «Гав»: короткий рывок 0 → 1 → 0 за 0.18 сек.
local function bump(x: number): number
	if x < 0 or x > 0.18 then
		return 0
	end
	return math.sin(math.pi * x / 0.18)
end

local function barkPulse(since: number): number
	return math.max(bump(since), bump(since - Settings.BarkSeconds * 0.5))
end

-- Сидит: перед поднят вокруг задних лап, туловище ниже, передние лапы стоят прямо, задние подогнуты вперёд.
local function sitPose(p: Pose, t: number, lookYaw: number, lookPitch: number)
	p.sit = Settings.SitPitch
	p.bodyY = -Settings.SitDrop + 0.02 * math.sin(t * 6)
	p.legFL = -Settings.SitPitch
	p.legFR = -Settings.SitPitch
	p.legBL = Settings.SitBackLegs
	p.legBR = Settings.SitBackLegs
	p.headYaw = lookYaw
	p.headPitch = lookPitch - Settings.SitPitch
	p.headTilt = 0.16 * math.sin(t * 0.7)
	p.tailLift = 1.0
	p.tail2Lift = 0.35
	p.tailYaw = 0.45 * math.sin(t * 7) -- машет хвостом по полу
	p.jaw = 0.1 + 0.04 * math.sin(t * 12) -- дышит с открытым ртом
end

-- Собака на карточке класса: сидит, машет хвостом, иногда гавкает (без звука).
function DogAnimator.previewPose(pose: Pose, t: number)
	clearPose(pose)
	sitPose(pose, t, 0.25 * math.sin(t * 0.5), 0.1)
	local since = t % 4.5 - 3.6
	local pulse = barkPulse(since)
	pose.jaw = math.max(pose.jaw, 0.6 * pulse)
	pose.headPitch += 0.2 * pulse
end

---------------------------------------------------------------- собаки в мире

type View = {
	model: Model,
	owner: number,
	rig: Rig,
	partCount: number,
	spawnPivot: CFrame,
	targetValue: ObjectValue?,
	pos: Vector3?,
	yaw: number,
	speed: number,
	moveDir: Vector3,
	gait: number,
	still: number,
	trail: { Vector3 },
	pose: Pose,
	goal: Pose,
	barkStart: number,
	lookMode: string,
	lookOffset: number,
	nextLook: number,
	head: BasePart?,
	alert: BillboardGui?,
	alertScale: UIScale?,
	alertShown: boolean,
	lastSolve: number,
	connections: { RBXScriptConnection },
}

local views: { [Model]: View } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local lastFilter = 0

local function refreshFilter()
	local ignore: { Instance } = {}
	for _, name in { MapSchema.Dogs, MapSchema.Thieves, MapSchema.Tourists, MapSchema.Sensors } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function yawFor(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function turnToward(current: number, target: number, rate: number): number
	local delta = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + delta * math.min(1, rate)
end

local function playBark(view: View)
	local head = view.head
	if not head or Config.Sounds.Bark == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Bark
	sound.Volume = Config.Sounds.BarkVolume
	sound.PlaybackSpeed = Config.Sounds.BarkSpeed * (0.94 + math.random() * 0.12)
	sound.RollOffMaxDistance = Config.Sounds.BarkRollOff
	local group = SoundService:FindFirstChild("Effects")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = head
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(3, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function onBark(view: View)
	local barkAt = tonumber(view.model:GetAttribute(DogAttr.BarkAt)) or 0
	if barkAt <= 0 or Workspace:GetServerTimeNow() - barkAt > 1.5 then
		return
	end
	view.barkStart = os.clock()
	playBark(view)
	task.delay(Settings.BarkSeconds * 0.5, function()
		if views[view.model] then
			playBark(view)
		end
	end)
end

-- «!» над головой собаки, видно сквозь стены (как у вора, который заметил охрану).
local function makeAlert(view: View)
	local head = view.head
	if not head then
		return
	end
	local spotted = Config.Effects.Spotted
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DogAlert"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromScale(Settings.AlertSize, Settings.AlertSize)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Settings.AlertHeight, 0)
	billboard.MaxDistance = Settings.AlertMaxDistance
	billboard.Enabled = false
	billboard.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "!"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = spotted.Color
	label.TextStrokeColor3 = Color3.fromHex("151821")
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Parent = label
	billboard.Parent = head
	view.alert = billboard
	view.alertScale = scale
end

local function scanParts(view: View)
	for _, descendant in view.model:GetDescendants() do
		if descendant:IsA("BasePart") and not view.rig.known[descendant] then
			DogAnimator.addPart(view.rig, descendant, view.spawnPivot:ToObjectSpace(descendant.CFrame))
			if not view.head and ClassModels.boneOf(descendant) == "Head" and string.find(descendant.Name, "Skull") then
				view.head = descendant
			end
		end
	end
	if not view.head then
		for index, bone in view.rig.bones do
			if bone == "Head" then
				view.head = view.rig.parts[index]
				break
			end
		end
	end
	if view.head and not view.alert then
		makeAlert(view)
	end
end

local function removeView(model: Model)
	local view = views[model]
	if view then
		for _, connection in view.connections do
			connection:Disconnect()
		end
		if view.alert then
			view.alert:Destroy()
		end
		views[model] = nil
	end
end

local function addView(model: Model)
	if views[model] then
		return
	end
	local owner = model:GetAttribute(DogAttr.Owner)
	local spawnPivot = model:GetAttribute(DogAttr.SpawnPivot)
	if typeof(owner) ~= "number" or typeof(spawnPivot) ~= "CFrame" then
		return
	end
	local pivots = defaultPivots()
	for name in pivots do
		local value = model:GetAttribute("Bone_" .. name)
		if typeof(value) == "Vector3" then
			pivots[name] = value
		end
	end
	local target = model:FindFirstChild("Target")
	local view: View = {
		model = model,
		owner = owner,
		rig = DogAnimator.newRig(pivots),
		partCount = tonumber(model:GetAttribute(DogAttr.PartCount)) or 0,
		spawnPivot = spawnPivot,
		targetValue = if target and target:IsA("ObjectValue") then target else nil,
		pos = nil,
		yaw = 0,
		speed = 0,
		moveDir = Vector3.zero,
		gait = 0,
		still = 0,
		trail = {},
		pose = DogAnimator.newPose(),
		goal = DogAnimator.newPose(),
		barkStart = -10,
		lookMode = "owner",
		lookOffset = 0,
		nextLook = os.clock() + 3,
		head = nil,
		alert = nil,
		alertScale = nil,
		alertShown = false,
		lastSolve = 0,
		connections = {},
	}
	table.insert(view.connections, model:GetAttributeChangedSignal(DogAttr.BarkAt):Connect(function()
		onBark(view)
	end))
	table.insert(view.connections, model.ChildAdded:Connect(function(child)
		if child.Name == "Target" and child:IsA("ObjectValue") then
			view.targetValue = child
		end
	end))
	views[model] = view
	scanParts(view)
end

-- Точка на следу хозяина на FollowDistance позади него и направление следа там. nil — след ещё короткий.
local function followPoint(view: View, feet: Vector3): (Vector3?, Vector3?)
	local remaining = Settings.FollowDistance
	local current = feet
	for index = #view.trail, 1, -1 do
		local point = view.trail[index]
		local segment = current - point
		local length = segment.Magnitude
		if length > 0.001 then
			if length >= remaining then
				local direction = segment / length
				return current - direction * remaining, direction
			end
			remaining -= length
			current = point
		end
	end
	return nil, nil
end

local function trimTrail(view: View, feet: Vector3)
	local keep = Settings.FollowDistance + 8
	local total = 0
	local current = feet
	for index = #view.trail, 1, -1 do
		total += (current - view.trail[index]).Magnitude
		current = view.trail[index]
		if total > keep and index > 1 then
			for _ = 1, index - 1 do
				table.remove(view.trail, 1)
			end
			return
		end
	end
end

local function targetPart(view: View): BasePart?
	local value = view.targetValue
	local model = value and value.Value
	if not model then
		return nil
	end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	return if head and head:IsA("BasePart") then head else nil
end

local function updateView(view: View, dt: number, camera: Camera?)
	if #view.rig.parts < view.partCount then
		scanParts(view)
	end
	local clock = os.clock()
	local owner = Players:GetPlayerByUserId(view.owner)
	local character = owner and owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local feet: Vector3? = nil
	if root and root:IsA("BasePart") and humanoid then
		feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	end

	-- Первый раз или хозяина перенесли далеко — собака появляется позади него
	if feet and root and root:IsA("BasePart") and (not view.pos or (feet - (view.pos :: Vector3)).Magnitude > Settings.SnapDistance) then
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local back = if flat.Magnitude > 0.01 then -flat.Unit else Vector3.new(0, 0, 1)
		view.pos = feet + back * Settings.FollowDistance * 0.7
		view.trail = { feet }
		view.yaw = yawFor(-back)
		view.speed = 0
	end
	local pos = view.pos
	if not pos then
		return -- хозяина ещё не видно
	end

	-- След хозяина и место, куда идти
	local goal: Vector3? = nil
	if feet then
		local last = view.trail[#view.trail]
		if not last or (feet - last).Magnitude >= Settings.TrailStep then
			table.insert(view.trail, feet)
		end
		trimTrail(view, feet)
		local point, direction = followPoint(view, feet)
		if point and direction then
			local left = Vector3.new(direction.Z, 0, -direction.X)
			if left.Magnitude > 0.01 then
				left = left.Unit
				local side = left * Settings.SideOffset
				if not Workspace:Raycast(point + Vector3.new(0, 1, 0), side + left * 0.6, rayParams) then
					point += side
				end
			end
			goal = point
		end
	end

	local desired = 0
	local distance = 0
	if goal then
		local delta = (goal - pos) * Vector3.new(1, 0, 1)
		distance = delta.Magnitude
		if distance > 0.3 then
			view.moveDir = delta / distance
			desired = math.min(Settings.MaxSpeed, distance * Settings.Catchup)
		end
	end
	view.speed += (desired - view.speed) * math.min(1, dt * 7)
	local step = 0
	if view.speed > 0.05 and distance > 0.05 then
		step = math.min(view.speed * dt, distance)
		pos += view.moveDir * step
	end

	-- По полу: луч вниз (лестницы, балкон)
	local top = math.max(pos.Y, if feet then feet.Y else pos.Y) + 2.5
	local hit = Workspace:Raycast(Vector3.new(pos.X, top, pos.Z), Vector3.new(0, -9, 0), rayParams)
	local groundY = if hit then hit.Position.Y elseif feet then feet.Y else pos.Y
	pos = Vector3.new(pos.X, pos.Y + (groundY - pos.Y) * math.min(1, dt * 14), pos.Z)
	view.pos = pos

	local moving = view.speed > 0.6
	if moving then
		view.still = 0
	else
		view.still += dt
	end
	local alert = view.model:GetAttribute(DogAttr.Alert) == true
	local thief = if alert then targetPart(view) else nil
	local sitting = not alert and view.still > Settings.SitDelay

	-- Куда повёрнута: на ходу — по ходу, рядом вор — на вора, стоит — на хозяина
	local desiredYaw = view.yaw
	if moving then
		desiredYaw = yawFor(view.moveDir)
	elseif thief then
		desiredYaw = yawFor((thief.Position - pos) * Vector3.new(1, 0, 1))
	elseif feet and ((feet - pos) * Vector3.new(1, 0, 1)).Magnitude > 1.2 then
		desiredYaw = yawFor((feet - pos) * Vector3.new(1, 0, 1))
	end
	local turnDelta = (desiredYaw - view.yaw + math.pi) % (2 * math.pi) - math.pi
	local turnLead = math.clamp(turnDelta, -0.7, 0.7)
	view.yaw = turnToward(view.yaw, desiredYaw, 1 - math.exp(-dt * (if moving then 10 else 5)))
	local rootCFrame = CFrame.new(pos) * CFrame.Angles(0, view.yaw, 0)

	-- Куда смотрит голова
	if clock > view.nextLook then
		view.nextLook = clock + 2.5 + math.random() * 3
		if math.random() < 0.3 then
			view.lookMode = "around"
			view.lookOffset = (math.random() * 2 - 1) * 0.9
		else
			view.lookMode = "owner"
		end
	end
	local lookPoint: Vector3? = nil
	if thief then
		lookPoint = thief.Position
	elseif root and root:IsA("BasePart") and view.lookMode == "owner" then
		lookPoint = root.Position + Vector3.new(0, 1.2, 0)
	end
	local lookYaw, lookPitch = 0, 0
	if lookPoint then
		local relative = rootCFrame:VectorToObjectSpace(lookPoint - rootCFrame * view.rig.pivots.Head)
		lookYaw = math.clamp(math.atan2(-relative.X, -relative.Z), -1.1, 1.1)
		lookPitch = math.clamp(math.atan2(relative.Y, Vector2.new(relative.X, relative.Z).Magnitude), -0.5, 0.7)
	elseif view.lookMode == "around" then
		lookYaw = view.lookOffset
	end

	-- Поза
	local p = view.goal
	clearPose(p)
	local t = clock
	if moving then
		local gallop = view.speed > Settings.RunSpeed
		view.gait = (view.gait + step * (if gallop then Settings.GallopStride else Settings.TrotStride)) % (math.pi * 2)
		local phase = view.gait
		local s = math.sin(phase)
		if gallop then
			local amp = 0.75
			p.legFL = amp * s
			p.legFR = amp * math.sin(phase - 0.35)
			p.legBL = -amp * math.sin(phase + 0.3)
			p.legBR = -amp * math.sin(phase - 0.05)
			p.rock = 0.12 * math.cos(phase)
			p.bodyY = 0.12 * math.abs(s)
			p.headPitch = -0.06 * math.cos(phase)
			p.tailLift = -0.15
			p.tailYaw = 0.12 * math.sin(t * 9)
			p.jaw = 0.18
		else
			local amp = 0.55 * math.clamp(view.speed / 6, 0.35, 1)
			p.legFL = amp * s
			p.legBR = amp * s
			p.legFR = -amp * s
			p.legBL = -amp * s
			p.bodyY = 0.05 * math.abs(math.cos(phase))
			p.roll = 0.035 * s
			p.headPitch = 0.04 * math.sin(phase * 2)
			p.tailLift = 0.15
			p.tailYaw = 0.35 * math.sin(t * 8)
		end
		p.headYaw = math.clamp(lookYaw * 0.4 + turnLead, -1.1, 1.1)
		p.roll -= turnLead * 0.15
	elseif sitting then
		sitPose(p, t, lookYaw, lookPitch)
	else
		local breathe = math.sin(t * 2.5)
		p.headYaw = math.clamp(lookYaw + turnLead * 0.5, -1.1, 1.1)
		p.headPitch = lookPitch + 0.02 * breathe
		p.bodyY = 0.015 * breathe
		if alert then
			-- Стойка: собрана, чуть вперёд, хвост трубой и мелко дрожит
			p.bodyY += 0.04
			p.rock = -0.05
			p.tailLift = -0.45
			p.tail2Lift = -0.15
			p.tailYaw = 0.1 * math.sin(t * 16)
			p.legFL = -0.1
			p.legFR = 0.06
		else
			p.tailLift = 0.3
			p.tailYaw = 0.25 * math.sin(t * 5)
			p.jaw = 0.08 + 0.03 * math.sin(t * 11)
		end
	end
	-- Лай поверх позы
	local pulse = barkPulse(clock - view.barkStart)
	if pulse > 0 then
		p.jaw = math.max(p.jaw, 0.6 * pulse)
		p.headPitch += 0.2 * pulse
		p.bodyY += 0.06 * pulse
		p.legFL -= 0.12 * pulse
		p.legFR -= 0.12 * pulse
	end
	blendPose(view.pose, p, dt)

	-- «!» над собакой, пока рядом вор
	if view.alert and alert ~= view.alertShown then
		view.alertShown = alert
		view.alert.Enabled = alert
		if alert and view.alertScale then
			view.alertScale.Scale = 0.2
			TweenService:Create(view.alertScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	-- Далеко от камеры — детали двигаем реже (15 Гц за 80 стадов, ещё реже за CullDistance)
	local dist = if camera then (camera.CFrame.Position - pos).Magnitude else 0
	if dist > Settings.CullDistance and clock - view.lastSolve < 0.5 then
		return
	elseif dist > Config.Animations.LodDistance and clock - view.lastSolve < Config.Animations.LodInterval then
		return
	end
	view.lastSolve = clock
	DogAnimator.solve(view.rig, rootCFrame, view.pose, true)
end

-- Своя собака сейчас чует вора (для кнопки умения): true / false.
function DogAnimator.ownAlert(userId: number): boolean
	for model, view in views do
		if view.owner == userId then
			return model:GetAttribute(DogAttr.Alert) == true
		end
	end
	return false
end

local started = false

-- Запустить собак в мире (один раз, из Abilities.client).
function DogAnimator.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local folder = Workspace:WaitForChild(MapSchema.Dogs)
		local function tryAdd(child: Instance)
			if not child:IsA("Model") then
				return
			end
			-- атрибуты и детали могут прийти чуть позже самой модели
			for _ = 1, 50 do
				if child:GetAttribute(DogAttr.SpawnPivot) ~= nil or not child.Parent then
					break
				end
				task.wait(0.1)
			end
			if child.Parent then
				addView(child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			task.spawn(tryAdd, child)
		end)
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				removeView(child)
			end
		end)
		for _, child in folder:GetChildren() do
			task.spawn(tryAdd, child)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local clock = os.clock()
		if clock - lastFilter > 0.5 then
			lastFilter = clock
			refreshFilter()
		end
		local camera = Workspace.CurrentCamera
		for model, view in views do
			if not model.Parent then
				removeView(model)
			else
				updateView(view, math.min(dt, 0.1), camera)
			end
		end
	end)
end

return DogAnimator
