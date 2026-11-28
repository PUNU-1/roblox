-- Позы охранников (блоки 3–4). Каждый клиент сам двигает суставы чужих персонажей (Motor6D.Transform) по атрибутам,
-- которые пишет сервер, — поверх обычных анимаций Roblox (ходьба, прыжок):
--  • удар Громилы: падает на спину, лежит со звёздочками, встаёт (KnockedAt / KnockedUntil);
--  • без сил (блок 4): падает лицом вниз, лежит и ползёт, руки по очереди тянутся вперёд (Downed); встаёт (RevivedAt);
--  • поднимает друга: на одном колене, руки вперёд-вниз, качается в такт (ReviveTarget);
--  • оружие в руках, выстрел, перезарядка, аптечка, присед, наклон (блок 4, позы — ниже, «стойка и оружие»);
--  • действия (этап 8, блок O): достать и убрать оружие (кобура на бедре, спина), взмах шокером, рука к поясу при
--    перезарядке, аптечка с бинтом, бронежилет через голову, покупка в оружейной, отвёртка при ремонте, наручники
--    при аресте (атрибуты Action / ActionUntil, Equipped, ReloadUntil, HealUntil); вещи в руке — ActionProps.
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
local ActionProps = require(script.Parent:WaitForChild("ActionProps"))

local PlayerAttr = GameState.PlayerAttr
local Knock = Config.Knockdown
local HealthSettings = Config.Health
local Stance = Config.Stance
local Anim = Config.Animations
local Actions = Config.Actions

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
	jointCount: number,
	lastScan: number,
	current: Pose, -- наша поза (плавно догоняет нужную)
	weights: { [string]: number }, -- 0 — сустав двигает обычная анимация, 1 — наша поза
	phase: number, -- шаг (ползёт, идёт присев)
	speed: number,
	lastYaw: number?,
	turnLead: number,
	breathOffset: number,
	-- этап 8, блок O: достать / убрать, действие и вещь в руке
	lastEquipped: string,
	equipFrom: string,
	equipAt: number,
	actionKind: string,
	actionStart: number,
	prop: Instance?,
	propKind: string,
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

---------------------------------------------------------------- стойка и оружие (блок 4)

local Weapons = Config.Weapons
local shotAt: { [Player]: number } = {} -- когда игрок выстрелил (руки дёргаются отдачей)

local function bump(t: number, a: number, b: number): number
	if t <= a or t >= b then
		return 0
	end
	return math.sin((t - a) / (b - a) * math.pi)
end

-- Руки с оружием: автомат и дробовик — правая у рукояти, левая под цевьём, корпус чуть боком;
-- пистолет — обе руки вперёд; шокер — правая вперёд; аптечка — обе руки у груди.
local function armsPose(pose: Pose, weapon: string, kick: number, reload: number, heal: number)
	if weapon == "Rifle" or weapon == "Shotgun" then
		pose.Waist = R(0.02, 0.28, 0)
		pose.Neck = R(0.05, -0.24, 0)
		pose.RightShoulder = R(0.62 + 0.15 * kick, 0.1, 0.42)
		pose.RightElbow = R(1.0 + 0.1 * kick)
		pose.RightWrist = R(0, 0, 0.35 * reload)
		pose.LeftShoulder = R(1.42 + 0.12 * kick - 1.0 * reload, 0, 0.55 - 0.3 * reload)
		pose.LeftElbow = R(0.35 + 0.9 * reload)
	elseif weapon == "Pistol" then
		pose.RightShoulder = R(1.5 + 0.2 * kick - 0.4 * reload, 0, -0.22)
		pose.RightElbow = R(0.08 + 0.15 * kick + 0.6 * reload)
		pose.LeftShoulder = R(1.45 + 0.2 * kick - 1.0 * reload, 0, 0.38)
		pose.LeftElbow = R(0.22 + 0.6 * reload)
		pose.Neck = R(0.02)
	elseif weapon == "Taser" then
		-- Взмах при ударе (этап 8, блок O): kick — от 0 до 1 за Actions.TaserSwingSeconds
		pose.RightShoulder = R(1.5 + 0.5 * kick, 0, -0.12 - 0.6 * kick)
		pose.RightElbow = R(0.1 + 0.3 * kick)
		pose.Waist = R(0, -0.25 * kick, 0)
	elseif weapon == "Medkit" then
		pose.RightShoulder = R(0.75 + 0.2 * heal, 0, -0.05)
		pose.RightElbow = R(1.0 + 0.5 * heal)
		pose.LeftShoulder = R(0.75 + 0.2 * heal, 0, 0.05)
		pose.LeftElbow = R(1.0 + 0.5 * heal)
		pose.Neck = R(-0.25 * heal)
	end
end

-- Рука тянется к оружию в кобуре (этап 8, блок O): пистолет — правое бедро, шокер — левое бедро (накрест),
-- автомат и дробовик — за правое плечо, к спине.
local function reachHolster(pose: Pose, weapon: string)
	if weapon == "Rifle" or weapon == "Shotgun" then
		pose.RightShoulder = R(2.8, 0, 0.35)
		pose.RightElbow = R(2.2)
		pose.Neck = R(0, 0.3, 0)
	elseif weapon == "Pistol" then
		pose.RightShoulder = R(-0.25, 0, 0.15)
		pose.RightElbow = R(0.3)
	elseif weapon == "Taser" then
		pose.RightShoulder = R(0.3, 0, -0.6)
		pose.RightElbow = R(1.2)
		pose.Waist = R(0, -0.2, 0)
	end
end

-- Перезарядка заметнее для других: левая рука идёт к поясу за магазином и обратно к оружию;
-- у дробовика — 4 раза за патронами, голова смотрит вниз.
local function reloadArms(pose: Pose, weapon: string, p: number)
	local belt
	if weapon == "Shotgun" then
		belt = if p > 0.1 and p < 0.8 then math.sin((((p - 0.1) / 0.7 * 4) % 1) * math.pi) else 0
	else
		belt = bump(p, 0.15, 0.75)
	end
	pose.LeftShoulder = (pose.LeftShoulder or CFrame.identity):Lerp(R(-0.35, 0, 0.12), belt)
	pose.LeftElbow = (pose.LeftElbow or CFrame.identity):Lerp(R(0.5), belt)
	pose.Waist = (pose.Waist or CFrame.identity) * R(0.08 * belt, 0, 0)
	pose.Neck = (pose.Neck or CFrame.identity) * R(-0.25 * belt)
end

-- Аптечка (p от 0 до 1): подносит кейс к груди, левая рука берёт бинт и бинтует грудь кругами, кладёт обратно.
local function medkitArms(pose: Pose, p: number)
	local lift = smooth(p / 0.15) * (1 - smooth((p - 0.9) / 0.1))
	local chest = bump(p, 0.35, 0.78)
	local wrap = if p > 0.5 and p < 0.7 then math.sin((p - 0.5) / 0.2 * math.pi * 4) else 0
	pose.RightShoulder = R(0.75 + 0.35 * lift, 0, -0.05)
	pose.RightElbow = R(1.0 + 0.6 * lift)
	pose.LeftShoulder = R(0.75 + 0.3 * lift + 0.2 * wrap, 0, 0.05 + 0.35 * chest)
	pose.LeftElbow = R(1.0 + 0.7 * chest + 0.15 * wrap)
	pose.Neck = R(-0.35 * lift)
end

-- Действие из атрибута Action: бронежилет через голову и застёгивает, покупка — рука к стойке,
-- ремонт — правая рука вперёд и кисть крутит отвёртку, арест — наклон, обе руки вперёд-вниз с наручниками.
local function actionPose(pose: Pose, action: string, p: number, clock: number)
	if action == "Vest" then
		if p < 0.5 then
			local u = math.sin(p / 0.5 * math.pi)
			pose.LeftShoulder = R(2.9 * u, 0, -0.25 * u)
			pose.RightShoulder = R(2.9 * u, 0, 0.25 * u)
			pose.LeftElbow = R(0.9 * u)
			pose.RightElbow = R(0.9 * u)
			pose.Neck = R(-0.2 * u)
		else
			local zip = math.sin((p - 0.5) / 0.5 * math.pi)
			pose.LeftShoulder = R(0.6, 0, 0.35)
			pose.LeftElbow = R(1.5)
			pose.RightShoulder = R(0.5 + 0.5 * zip, 0, -0.35)
			pose.RightElbow = R(1.6 - 0.3 * zip)
			pose.Neck = R(-0.35)
		end
	elseif action == "Buy" then
		local reach = math.sin(p * math.pi)
		pose.RightShoulder = R(1.5 * reach, 0, -0.1 * reach)
		pose.RightElbow = R(0.25 * reach)
		pose.Waist = R(-0.15 * reach)
	elseif action == "Repair" then
		pose.RightShoulder = R(1.55, 0, -0.1)
		pose.RightElbow = R(0.35)
		pose.RightWrist = R(0, math.sin(clock * Actions.ScrewdriverSpeed) * 0.7, 0)
		pose.LeftShoulder = R(1.3, 0, 0.25)
		pose.LeftElbow = R(0.5)
	elseif action == "Arrest" then
		local shake = math.sin(clock * 14) * 0.06
		pose.Waist = R(-0.35)
		pose.Neck = R(0.2)
		pose.LeftShoulder = R(0.95 + shake, 0, 0.18)
		pose.RightShoulder = R(0.95 - shake, 0, -0.18)
		pose.LeftElbow = R(0.35)
		pose.RightElbow = R(0.35)
	end
end

-- Действие игрока сейчас: вид и доля (0..1). Начало запоминается на клиенте, когда атрибут сменился.
local function actionOf(player: Player, rig: Rig, clock: number): (string, number)
	local kind = player:GetAttribute(PlayerAttr.Action)
	local untilTime = number(player, PlayerAttr.ActionUntil)
	if typeof(kind) ~= "string" or kind == "" or untilTime <= clock then
		rig.actionKind = ""
		return "", 0
	end
	if kind ~= rig.actionKind then
		rig.actionKind = kind
		rig.actionStart = clock
	end
	return kind, math.clamp((clock - rig.actionStart) / math.max(0.05, untilTime - rig.actionStart), 0, 1)
end

-- Ноги присевшего: колени согнуты, корпус ниже; идёт — короткие шаги на полусогнутых.
local function crouchLegs(pose: Pose, phase: number, move: number)
	local s = math.sin(phase)
	local c = math.cos(phase)
	pose.Root = CFrame.new(0, -1.0 + 0.05 * math.abs(s) * move, 0)
	pose.LeftHip = R(1.0 + 0.4 * s * move)
	pose.RightHip = R(1.0 - 0.4 * s * move)
	pose.LeftKnee = R(-1.9 - 0.35 * math.max(0, c) * move)
	pose.RightKnee = R(-1.9 - 0.35 * math.max(0, -c) * move)
	pose.LeftAnkle = R(0.85)
	pose.RightAnkle = R(0.85)
	pose.Waist = (pose.Waist or CFrame.identity) * R(-0.25, 0, 0)
end

-- Поза стоящего охранника с оружием, присевшего или в наклоне. nil — обычная анимация Roblox.
local function standingPose(player: Player, _character: Model, rig: Rig, clock: number): Pose?
	local weapon = player:GetAttribute(PlayerAttr.Equipped)
	local crouch = player:GetAttribute(PlayerAttr.Crouch) == true
	local lean = number(player, PlayerAttr.Lean)
	local holding = typeof(weapon) == "string" and weapon ~= ""
	local action, actionP = actionOf(player, rig, clock)
	-- Достать или убрать (этап 8, блок O): первая половина — рука у кобуры или за спиной
	local sinceEquip = clock - rig.equipAt
	local drawing = holding and sinceEquip < Weapons.EquipSeconds
	local holstering = not holding and rig.equipFrom ~= "" and sinceEquip < Actions.HolsterSeconds
	if not holding and not crouch and lean == 0 and action == "" and not holstering then
		return nil
	end
	local pose: Pose = {}
	if action ~= "" then
		actionPose(pose, action, actionP, clock)
	elseif holstering then
		reachHolster(pose, rig.equipFrom)
	elseif holding then
		local kick = if weapon == "Taser"
			then bump(clock - (shotAt[player] or 0), 0, Actions.TaserSwingSeconds)
			else bump(clock - (shotAt[player] or 0), 0, 0.14)
		local healUntil = number(player, PlayerAttr.HealUntil)
		armsPose(pose, weapon :: string, kick, 0, 0)
		if drawing and sinceEquip < Weapons.EquipSeconds / 2 then
			reachHolster(pose, weapon :: string)
		end
		local reloadUntil = number(player, PlayerAttr.ReloadUntil)
		local info = (Weapons :: any)[weapon]
		if reloadUntil > clock and info and info.ReloadSeconds then
			reloadArms(pose, weapon :: string, 1 - (reloadUntil - clock) / info.ReloadSeconds)
		end
		if weapon == "Medkit" and healUntil > clock then
			medkitArms(pose, math.clamp(1 - (healUntil - clock) / Weapons.Medkit.UseSeconds, 0, 1))
		end
	end
	if crouch then
		crouchLegs(pose, rig.phase, math.clamp(rig.speed / Stance.CrouchSpeed, 0, 1))
	end
	if lean ~= 0 then
		-- Наклон в поясе: выглядывает из-за укрытия, голова чуть выпрямляется
		pose.Waist = (pose.Waist or CFrame.identity) * R(0, 0, -lean * 0.38)
		pose.Neck = (pose.Neck or CFrame.identity) * R(0, 0, lean * 0.15)
	end
	if math.abs(rig.turnLead) > 0.002 then
		local lead = rig.turnLead
		pose.Root = (pose.Root or CFrame.identity) * R(0, -lead * 0.15, 0)
		pose.Waist = (pose.Waist or CFrame.identity) * R(0, lead * 0.25, 0)
		pose.Neck = (pose.Neck or CFrame.identity) * R(0, lead * 0.3, 0)
	end
	local idle = 1 - math.clamp(rig.speed / 4, 0, 1)
	if idle > 0.01 then
		local b = math.sin(clock * Anim.BreathSpeed + rig.breathOffset) * idle
		local chest = Anim.BreathChest * b
		local arm = Anim.BreathArm * b
		pose.Waist = (pose.Waist or CFrame.identity) * R(chest)
		pose.LeftShoulder = (pose.LeftShoulder or CFrame.identity) * R(arm, 0, -arm * 0.5)
		pose.RightShoulder = (pose.RightShoulder or CFrame.identity) * R(arm, 0, arm * 0.5)
	end
	return pose
end

---------------------------------------------------------------- кадр

local function poseFor(player: Player, character: Model, rig: Rig, clock: number): (Pose?, number)
	local knocked = knockState(player, clock)
	if knocked > 0 then
		return knockPose(character, knocked, clock), 0.18
	end
	local down = downAmount(player, clock)
	if down > 0 then
		local move = math.clamp(rig.speed / HealthSettings.CrawlSpeed, 0, 1)
		return crawlPose(character, down, rig.phase, move, clock), 0.18
	end
	if number(player, PlayerAttr.ReviveTarget) ~= 0 then
		return revivePose(clock), 0.25
	end
	return standingPose(player, character, rig, clock), 0.25
end

local function countKeys(t: { [string]: Joint }): number
	local count = 0
	for _ in t do
		count += 1
	end
	return count
end

local function newRig(character: Model, userId: number): Rig
	local joints = findJoints(character)
	return {
		joints = joints,
		jointCount = countKeys(joints),
		lastScan = os.clock(),
		current = {},
		weights = {},
		phase = 0,
		speed = 0,
		lastYaw = nil,
		turnLead = 0,
		breathOffset = (userId * 1.618) % (math.pi * 2),
		lastEquipped = "",
		equipFrom = "",
		equipAt = -math.huge,
		actionKind = "",
		actionStart = 0,
		prop = nil,
		propKind = "",
	}
end

-- Вещь в руке другого охранника (ActionProps): отвёртка при ремонте, наручники при аресте, бинт с аптечкой.
local function syncProp(player: Player, character: Model, rig: Rig, clock: number)
	local kind = ""
	local action = actionOf(player, rig, clock)
	if action == "Repair" then
		kind = "Screwdriver"
	elseif action == "Arrest" then
		kind = "Cuffs"
	elseif player:GetAttribute(PlayerAttr.Equipped) == "Medkit" then
		local healUntil = number(player, PlayerAttr.HealUntil)
		local p = 1 - (healUntil - clock) / Weapons.Medkit.UseSeconds
		if healUntil > clock and p >= 0.36 and p < 0.74 then
			kind = "Bandage"
		end
	end
	if kind == rig.propKind and (kind == "" or (rig.prop and rig.prop.Parent)) then
		return
	end
	if rig.prop then
		rig.prop:Destroy()
		rig.prop = nil
	end
	rig.propKind = kind
	if kind ~= "" then
		rig.prop = ActionProps.attach(character, kind)
	end
end

local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function step(dt: number)
	local clock = Workspace:GetServerTimeNow()
	local clampedDt = math.min(dt, 0.1)
	local blend = 1 - math.exp(-clampedDt * Anim.BlendSpeed)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or player == localPlayer then
			continue -- себя не видно (первое лицо)
		end
		local rig = rigs[character]
		if not rig then
			rig = newRig(character, player.UserId)
			rigs[character] = rig
		end
		-- Фаза шага растёт от реальной горизонтальной скорости AssemblyLinearVelocity
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local vel = root.AssemblyLinearVelocity
			local horizVel = Vector3.new(vel.X, 0, vel.Z)
			local horizSpeed = horizVel.Magnitude
			if horizSpeed < 0.15 then
				horizSpeed = 0
			end
			rig.speed += (horizSpeed - rig.speed) * math.min(1, clampedDt * 8)
			local stride = if player:GetAttribute(PlayerAttr.Downed) == true then Anim.CrawlStride else Anim.CrouchStride
			rig.phase = (rig.phase + horizSpeed * clampedDt * stride) % (math.pi * 2)

			local currentYaw = yawOf(root.CFrame)
			local lastYaw = rig.lastYaw or currentYaw
			local deltaYaw = (currentYaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
			rig.lastYaw = currentYaw
			local yawRate = if clampedDt > 0.0001 then deltaYaw / clampedDt else 0
			local dirLead = 0
			if horizSpeed > 0.5 then
				local localVel = root.CFrame:VectorToObjectSpace(horizVel)
				local velYawOffset = math.atan2(-localVel.X, -localVel.Z)
				if math.abs(velYawOffset) < 2.2 then
					dirLead = math.clamp(velYawOffset, -Anim.TurnLeadMax, Anim.TurnLeadMax)
				end
			end
			local rateLead = math.clamp(yawRate * Anim.TurnLeadRateScale, -0.5, 0.5)
			local targetLead = math.clamp(dirLead * 0.5 + rateLead, -Anim.TurnLeadMax, Anim.TurnLeadMax)
			rig.turnLead += (targetLead - rig.turnLead) * (1 - math.exp(-clampedDt * Anim.TurnLeadSpeed))
		end
		-- Сменилось оружие в руках: запоминаем, что было, — для анимации «достать / убрать» (этап 8, блок O)
		local equippedNow = player:GetAttribute(PlayerAttr.Equipped)
		local equippedName = if typeof(equippedNow) == "string" then equippedNow else ""
		if equippedName ~= rig.lastEquipped then
			rig.equipFrom = rig.lastEquipped
			rig.lastEquipped = equippedName
			rig.equipAt = clock
		end
		local pose, fade = poseFor(player, character, rig, clock)
		syncProp(player, character, rig, clock)
		-- Плавно: наш вес по каждому суставу растёт к 1 (поза есть) или падает к 0 (обычная анимация)
		local weightBlend = 1 - math.exp(-clampedDt / math.max(0.15, fade) * 3)
		if rig.jointCount < #JOINTS and os.clock() - rig.lastScan >= 0.5 then
			rig.joints = findJoints(character)
			rig.jointCount = countKeys(rig.joints)
			rig.lastScan = os.clock()
		end
		for name, joint in rig.joints do
			if not joint.Parent then
				rig.joints = findJoints(character) -- Roblox пересобрал суставы
				rig.jointCount = countKeys(rig.joints)
				rig.lastScan = os.clock()
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
	-- Наклон не заглядывает сквозь стену: вбок — не дальше, чем свободно от головы
	local leanOffset = lean * Stance.LeanOffset
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if lean ~= 0 and root and root:IsA("BasePart") and head and head:IsA("BasePart") then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character :: Instance, Workspace.CurrentCamera :: Instance }
		local side = root.CFrame.RightVector * leanOffset
		local hit = Workspace:Raycast(head.Position - Vector3.new(0, drop, 0), side + side.Unit * 0.4, params)
		if hit then
			leanOffset = lean * math.max(0, (hit.Position - (head.Position - Vector3.new(0, drop, 0))).Magnitude - 0.5)
		end
	end
	local target = Vector3.new(leanOffset, -drop, 0)
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

-- Чужой выстрел: руки стрелка дёргаются отдачей
local Remotes = require(Shared:WaitForChild("Remotes"))
Remotes.get(Remotes.Names.ShotFx).OnClientEvent:Connect(function(shooter)
	if typeof(shooter) == "Instance" and shooter:IsA("Player") then
		shotAt[shooter] = Workspace:GetServerTimeNow()
	end
end)
Players.PlayerRemoving:Connect(function(player)
	shotAt[player] = nil
end)

-- Позы пишем последними перед отрисовкой кадра, после обычных анимаций Roblox (как в NpcAnimator);
-- камеру — сразу после камеры Roblox
RunService:BindToRenderStep("GuardPoses", Enum.RenderPriority.Last.Value, step)
RunService:BindToRenderStep("GuardCamera", Enum.RenderPriority.Camera.Value + 1, ownCamera)
