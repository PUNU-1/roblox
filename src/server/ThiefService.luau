-- Воры (блок 3). У каждого вора есть вид (Config.ThiefTypes, внешний вид — ThiefKinds) и приказ от волны
-- (Options, WaveService): через какую дверь войти, что сделать до кражи, ждать ли во входном холле.
-- Обычный путь: дверь без охраны -> (задание) -> (ждёт) -> экспонат подальше от охраны -> кража 3 сек ->
-- бегом с экспонатом над головой к ближайшей двери. Замечает охранника — убегает.
-- Пока один вор несёт (или снимает) Мону Лизу, остальные загораживают путь охране.
-- Всё поведение считает сервер; руки и ноги двигают клиенты (NpcAnimator) по атрибуту AnimState.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local CameraService = require(Server:WaitForChild("CameraService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))
local HeistFx = require(Server:WaitForChild("HeistFx"))
local ThiefKinds = require(Server:WaitForChild("ThiefKinds"))
local BlackoutService = require(Server:WaitForChild("BlackoutService"))

local ThiefConfig = Config.Thief
local Smart = Config.Smart
local Anim = GameState.ThiefAnim

local ThiefService = {}

-- Вор вынес картину из музея. GameLoop заканчивает ночь.
ThiefService.Escaped = Instance.new("BindableEvent")
-- Появился новый вор (model). CatchService вешает на него кнопку ареста.
ThiefService.Spawned = Instance.new("BindableEvent")

-- Приказ вору от волны (WaveService и планы Tactics). Всё необязательно.
export type Options = {
	kind: string?, -- вид вора (Config.ThiefTypes), по умолчанию Pickpocket
	entrance: BasePart?, -- через какую дверь войти (nil — сам выберет дверь без охраны)
	target: string?, -- "Main" — Мона Лиза, "Cheap" — дешёвый экспонат подальше от неё, nil — сам по охране
	task: string?, -- задание до кражи: "Lure" — пнуть витрину вдали от охраны, "Smash" — разбить её (Громила),
	-- "Camera" — сломать камеру
	hold: (() -> boolean)?, -- ждать во входном холле, пока не вернёт true
	holdTimeout: number?, -- но не дольше стольки секунд
	silent: boolean?, -- шагов не слышно
	loud: boolean?, -- бежит и громко топает (приманка)
	noFlee: boolean?, -- не убегает от охраны
	cameras: { BasePart }?, -- задание "Camera": какие камеры сломать (план «Ослепление»)
	disguise: Player?, -- Фальшивый охранник: копия этого игрока
	plan: string?, -- какой план (для отладки)
}

-- Шахтёр и Стекольщик приходят не через дверь: у них своя часть пути (подкоп, крыша, верёвка).
type Special = {
	started: number, -- когда началась текущая часть (вылезает, режет, ждёт, спускается, лезет вверх)
	floorY: number, -- высота корня, когда вор стоит на полу
	floor: number, -- высота самого пола
	-- Шахтёр
	digUntil: number, -- когда вылезет
	digPoint: Vector3, -- где вылезет (точка на полу)
	hole: HeistFx.Hole?,
	-- Стекольщик
	cut: HeistFx.Cut?,
	holeCenter: Vector3, -- центр дыры на стекле
	landPoint: Vector3, -- где он на полу под дырой (туда же бежит с добычей)
	roofY: number, -- высота корня на крыше
}

type Thief = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	path: Path,
	kind: string,
	info: any, -- Config.ThiefTypes[kind]
	options: Options,
	state: string, -- Approach | GoTask | Task | Hold | Steal | Escape | Flee | Block | Arrested | Escaped
	-- Шахтёр: Dig (под полом, его не видно) -> Emerge; Стекольщик: Roof -> RoofWait -> Descend ... Ascend
	waypoints: { PathWaypoint },
	waypointIndex: number,
	pathTarget: Vector3?,
	pathTime: number,
	computing: boolean,
	stealStarted: number,
	target: ExhibitService.Exhibit?, -- какой экспонат крадёт
	fleeUntil: number,
	fleeTarget: Vector3,
	-- задание до кражи
	task: string?,
	taskDone: boolean,
	taskStarted: number,
	taskCase: HeistFx.Case?, -- витрина, которую пинает
	cameraQueue: { BasePart }, -- камеры, которые надо сломать
	autoCamera: boolean, -- взломщик без приказа: сам находит ближайшую работающую камеру (одну)
	-- ожидание во входном холле
	holdPoint: Vector3,
	holdStarted: number,
	holdDone: boolean,
	holdArrived: boolean,
	-- удар Громилы
	punchStarted: number, -- 0 — не бьёт
	punchTarget: Player?,
	punchHit: boolean,
	nextPunch: number,
	special: Special?, -- подкоп или крыша
	stunUntil: number, -- шокер (блок 4): лежит до этого времени
	footsteps: Sound?,
	connections: { RBXScriptConnection },
}

local thieves: { [Model]: Thief } = {}
local folder: Folder
local entrances: { BasePart } = {}
local active = false
local updateConnection: RBXScriptConnection? = nil
local random = Random.new()
local currentNight = 1
local speedMultiplier = 1

local bannerRemote = Remotes.get(Remotes.Names.Banner)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function kindInfo(kind: string): any
	return (Config.ThiefTypes :: any)[kind] or Config.ThiefTypes.Pickpocket
end

---------------------------------------------------------------- охранники рядом

-- Где сейчас охранники (живые участники смены).
function ThiefService.guardPositions(): { Vector3 }
	local list = {}
	for _, player in RoleService.participants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Лежащий без сил охранник воров не пугает и не сторожит (блок 4)
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and not RoleService.isDowned(player) then
			table.insert(list, root.Position)
		end
	end
	return list
end

local function nearestGuard(position: Vector3): (Vector3?, number)
	local bestPosition, bestDistance = nil, math.huge
	for _, guard in ThiefService.guardPositions() do
		local distance = flatDistance(guard, position)
		if distance < bestDistance then
			bestPosition, bestDistance = guard, distance
		end
	end
	return bestPosition, bestDistance
end

---------------------------------------------------------------- двери

-- Вход работает, только когда его зал открыт (все 4 двери музея — в главном зале, открыты всегда).
local function openEntrances(): { BasePart }
	local list = {}
	for _, entrance in entrances do
		if GameState.isHallOpen(entrance:GetAttribute("Hall")) then
			table.insert(list, entrance)
		end
	end
	return list
end

function ThiefService.entrances(): { BasePart }
	return openEntrances()
end

local function nearestEntrance(position: Vector3): Vector3?
	local best, bestDistance = nil, math.huge
	for _, entrance in openEntrances() do
		local distance = flatDistance(entrance.Position, position)
		if distance < bestDistance then
			best, bestDistance = entrance.Position, distance
		end
	end
	return best
end

-- Дверь для вора (воры следят за охраной): у которой нет охранника ближе EntranceGuardRadius.
-- Таких несколько — любая из них; все под охраной — та, где охрана дальше всего. exclude — уже занятые двери волны.
function ThiefService.pickEntrance(exclude: { BasePart }?): BasePart?
	local open = openEntrances()
	local pool = {}
	for _, entrance in open do
		if not (exclude and table.find(exclude, entrance)) then
			table.insert(pool, entrance)
		end
	end
	if #pool == 0 then
		pool = open -- все двери уже заняты волной — можно и вдвоём через одну
	end
	if #pool == 0 then
		return nil
	end
	local guards = ThiefService.guardPositions()
	local free, best, bestDistance = {}, nil, -1
	for _, entrance in pool do
		local distance = math.huge
		for _, guard in guards do
			distance = math.min(distance, flatDistance(guard, entrance.Position))
		end
		if distance >= Smart.EntranceGuardRadius then
			table.insert(free, entrance)
		end
		if distance > bestDistance then
			best, bestDistance = entrance, distance
		end
	end
	if #free > 0 then
		return free[random:NextInteger(1, #free)]
	end
	return best
end

-- Место ожидания во входном холле: чуть за дверью, немного вбок.
local function holdPointFor(entrance: BasePart): Vector3
	local cframe = entrance.CFrame
	local point = cframe.Position + flat(cframe.LookVector).Unit * Smart.HoldInside
		+ flat(cframe.RightVector).Unit * random:NextNumber(-Smart.HoldSpread, Smart.HoldSpread)
	return Vector3.new(point.X, entrance.Position.Y, point.Z)
end

---------------------------------------------------------------- анимации и шаги

-- Сами движения рук и ног делает каждый клиент (NpcAnimator.client.luau).
-- Сервер только сообщает, что вор сейчас делает.
local function animFor(thief: Thief): string
	local state = thief.state
	if state == "Arrested" then
		return Anim.Arrest
	elseif state == "Stunned" then
		return Anim.Stunned
	elseif state == "Emerge" or state == "Ascend" then
		return Anim.Climb
	elseif state == "Roof" then
		return Anim.Cut
	elseif state == "RoofWait" then
		return Anim.Hold
	elseif state == "Descend" then
		return Anim.Rappel
	elseif thief.punchStarted > 0 then
		return Anim.Punch
	elseif state == "Steal" then
		return Anim.Steal
	elseif state == "Escape" or state == "Escaped" then
		return Anim.Carry
	elseif state == "Flee" or state == "Block" then
		return thief.info.RunAnim or Anim.Run
	elseif state == "Task" then
		if thief.task == "Lure" then
			return Anim.Kick
		elseif thief.task == "Smash" then
			return Anim.Smash
		elseif thief.task == "Fuse" then
			return Anim.Work
		end
		return Anim.Steal
	elseif state == "Hold" and thief.holdArrived then
		return Anim.Hold
	end
	-- Идёт: приманка бежит, у Громилы и Тени своя походка, остальные крадутся
	if thief.options.loud then
		return Anim.Run
	end
	return thief.info.WalkAnim or Anim.Sneak
end

local function syncAnim(thief: Thief)
	local anim = animFor(thief)
	if thief.model:GetAttribute(GameState.NpcAttr.AnimState) ~= anim then
		thief.model:SetAttribute(GameState.NpcAttr.AnimStateAt, now())
		thief.model:SetAttribute(GameState.NpcAttr.AnimState, anim)
	end
end

local function setupFootsteps(thief: Thief)
	if thief.options.silent or thief.info.Silent then
		return -- Тень и тихие воры планов ходят без звука
	end
	local sounds = Config.Sounds
	local loud = thief.options.loud == true
	local volume = sounds.StepVolume * (if loud then ThiefConfig.LoudStepMultiplier else 1)
	local footsteps = Audio.create(sounds.ThiefStep, thief.root, volume, true)
	if not footsteps then
		return
	end
	footsteps.RollOffMaxDistance = sounds.StepRollOff * (if loud then ThiefConfig.LoudStepMultiplier else 1)
	thief.footsteps = footsteps
	table.insert(
		thief.connections,
		thief.humanoid.Running:Connect(function(speed)
			local moving = speed > 0.5
			if moving and not footsteps.IsPlaying then
				footsteps:Play()
			elseif not moving and footsteps.IsPlaying then
				footsteps:Stop()
			end
		end)
	)
end

---------------------------------------------------------------- движение по пути

local function computePath(thief: Thief, target: Vector3)
	thief.computing = true
	task.spawn(function()
		local ok = pcall(function()
			thief.path:ComputeAsync(thief.root.Position, target)
		end)
		thief.computing = false
		if not thieves[thief.model] then
			return
		end
		if ok and thief.path.Status == Enum.PathStatus.Success then
			thief.waypoints = thief.path:GetWaypoints()
			thief.waypointIndex = 2 -- первая точка — там, где вор уже стоит
		else
			thief.waypoints = {}
			thief.waypointIndex = 1
		end
		thief.pathTarget = target
		thief.pathTime = now()
	end)
end

local function moveTowards(thief: Thief, target: Vector3, speed: number)
	thief.humanoid.WalkSpeed = speed
	local needPath = thief.pathTarget == nil
		or (thief.pathTarget :: Vector3 - target).Magnitude > ThiefConfig.PathRecomputeDistance
		or now() - thief.pathTime > ThiefConfig.PathRecomputeSeconds
	if needPath and not thief.computing then
		computePath(thief, target)
	end

	local waypoint = thief.waypoints[thief.waypointIndex]
	if waypoint and flatDistance(waypoint.Position, thief.root.Position) < ThiefConfig.WaypointReachDistance then
		thief.waypointIndex += 1
		waypoint = thief.waypoints[thief.waypointIndex]
	end
	thief.humanoid:MoveTo(if waypoint then waypoint.Position else target)
end

local function stand(thief: Thief)
	thief.humanoid:MoveTo(thief.root.Position)
end

local function face(thief: Thief, point: Vector3)
	local position = thief.root.Position
	if flatDistance(position, point) > 0.1 then
		thief.root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
	end
end

---------------------------------------------------------------- поведение

local function speedFor(thief: Thief, base: number): number
	local speed = base * speedMultiplier * (thief.info.SpeedMul or 1)
	local slowedUntil = thief.model:GetAttribute("SlowedUntil")
	if typeof(slowedUntil) == "number" and slowedUntil > now() then
		return speed * ThiefConfig.SlowMultiplier
	end
	return speed
end

-- Скорость, пока вор идёт к цели: крадётся, приманка бежит, Фальшивый охранник идёт спокойно.
local function walkSpeed(thief: Thief): number
	if thief.info.WalkSpeed then
		return speedFor(thief, thief.info.WalkSpeed)
	end
	return speedFor(thief, if thief.options.loud then ThiefConfig.RunSpeed else ThiefConfig.SneakSpeed)
end

-- Фальшивого охранника кто-то из охраны видит: ближе WatchRadius и между ними нет стены.
local function watched(thief: Thief): boolean
	local head = thief.model:FindFirstChild("Head")
	local from = if head and head:IsA("BasePart") then head.Position else thief.root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { folder }
	local eyes = {}
	for _, player in RoleService.participants() do
		local character = player.Character
		if character then
			table.insert(ignore, character)
			local guardHead = character:FindFirstChild("Head")
			if guardHead and guardHead:IsA("BasePart") and not RoleService.isDowned(player)
				and (guardHead.Position - from).Magnitude <= thief.info.WatchRadius
			then
				table.insert(eyes, guardHead.Position)
			end
		end
	end
	params.FilterDescendantsInstances = ignore
	for _, eye in eyes do
		if not Workspace:Raycast(eye, from - eye, params) then
			return true
		end
	end
	return false
end

-- «!» над головой: вор заметил охранника. Сквозь стены не видно.
local function showSpotted(thief: Thief)
	local head = thief.model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild("SpottedAlert")
	if old then
		old:Destroy()
	end
	local spotted = Config.Effects.Spotted
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpottedAlert"
	billboard.Size = UDim2.fromScale(spotted.Size, spotted.Size)
	billboard.StudsOffset = Vector3.new(0, spotted.Height, 0)
	billboard.MaxDistance = spotted.MaxDistance
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "!"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = spotted.Color
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = head
	Debris:AddItem(billboard, spotted.Seconds)
end

local function startEscape(thief: Thief, exhibit: ExhibitService.Exhibit)
	thief.state = "Escape"
	if thief.options.disguise then
		-- С экспонатом в руках он уже не охранник: кнопка становится обычным арестом (CatchService)
		thief.model:SetAttribute(GameState.ThiefAttr.Disguise, nil)
	end
	syncAnim(thief)
	bannerRemote:FireAllClients(("THE %s IS STOLEN!"):format(string.upper(exhibit.title)), "danger")
	Audio.alarm()
end

-- Что делать дальше, когда вор свободен: задание, ожидание в холле или кража.
local function nextState(thief: Thief): string
	if thief.task and not thief.taskDone then
		return "GoTask"
	elseif thief.options.hold and not thief.holdDone then
		return "Hold"
	end
	return "Approach"
end

local function finishTask(thief: Thief)
	thief.taskDone = true
	thief.state = nextState(thief)
end

-- Где вору делать задание. nil — делать нечего (витрин нет, камеры уже сломаны), задание закончено.
local function taskPoint(thief: Thief): Vector3?
	if thief.task == "Lure" or thief.task == "Smash" then
		local case = thief.taskCase
		if not case or case.cracked or case.broken then
			case = HeistFx.pickCase(ThiefService.guardPositions())
			thief.taskCase = case
		end
		return if case then case.stand else nil
	elseif thief.task == "Camera" then
		while #thief.cameraQueue > 0 and not CameraService.isWorking(thief.cameraQueue[1]) do
			table.remove(thief.cameraQueue, 1)
		end
		local camera = thief.cameraQueue[1]
		if not camera and thief.autoCamera then
			-- Взломщик без приказа: ближайшая работающая камера
			camera = CameraService.nearestWorking(thief.root.Position)
			if camera then
				table.insert(thief.cameraQueue, camera)
			end
		end
		return if camera then CameraService.standPoint(camera) else nil
	elseif thief.task == "Fuse" then
		-- Светорез: к щитку POWER, если свет ещё есть
		return if BlackoutService.isOut() then nil else BlackoutService.standPoint()
	end
	return nil
end

local function taskSeconds(thief: Thief): number
	if thief.task == "Lure" then
		return Smart.LureSeconds
	elseif thief.task == "Smash" then
		return thief.info.SmashSeconds or Smart.LureSeconds
	elseif thief.task == "Fuse" then
		return thief.info.WorkSeconds or 4
	end
	return thief.info.BreakSeconds or 2
end

-- Задание сделано: витрина в трещинах (или разбита) с тревогой, или сломанная камера.
local function completeTask(thief: Thief)
	if thief.task == "Lure" or thief.task == "Smash" then
		local case = thief.taskCase
		if case and thief.task == "Smash" then
			HeistFx.smashCase(case)
		elseif case then
			HeistFx.caseAlarm(case)
		end
		finishTask(thief)
	elseif thief.task == "Camera" then
		local camera = table.remove(thief.cameraQueue, 1)
		if camera then
			CameraService.breakCamera(camera)
		end
		thief.autoCamera = false -- сам ломает только одну камеру
		if #thief.cameraQueue == 0 then
			finishTask(thief)
		else
			thief.state = "GoTask"
		end
	elseif thief.task == "Fuse" then
		BlackoutService.cut() -- свет и камеры гаснут во всём музее
		finishTask(thief)
	end
end

---------------------------------------------------------------- удар Громилы

-- Охранник стоит перед вором (ближе range и в конусе PunchCone) и ещё на ногах.
local function inFront(thief: Thief, player: Player, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) or RoleService.isKnocked(player)
		or RoleService.isDowned(player)
	then
		return false
	end
	local offset = flat(root.Position - thief.root.Position)
	if offset.Magnitude > range then
		return false
	end
	if offset.Magnitude < 0.5 then
		return true
	end
	return flat(thief.root.CFrame.LookVector).Unit:Dot(offset.Unit) >= thief.info.PunchCone
end

-- Кого бить: ближайший охранник спереди.
local function guardToPunch(thief: Thief): Player?
	local best, bestDistance = nil, math.huge
	for _, player in RoleService.participants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and inFront(thief, player, thief.info.PunchRange) then
			local distance = flatDistance(root.Position, thief.root.Position)
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function knockDown(thief: Thief, player: Player)
	local seconds = thief.info.KnockSeconds
	if not RoleService.knockDown(player, seconds) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local sounds = Config.Sounds
	Audio.playOnce(sounds.Punch, root, sounds.PunchVolume, nil, sounds.PunchSpeed)
	Audio.playOnce(sounds.GuardFall, root, sounds.GuardFallVolume)
	task.delay(math.max(0, seconds - Config.Knockdown.RiseSeconds), function()
		if root.Parent then
			Audio.playOnce(sounds.GuardGetUp, root, sounds.GuardGetUpVolume)
		end
	end)
end

-- Громила бьёт охранника, который подошёл спереди: замах, удар, охранник падает на KnockSeconds.
-- Пока бьёт, стоит на месте (кража и задание ждут). Возвращает true, если сейчас занят ударом.
local function updatePunch(thief: Thief): boolean
	local info = thief.info
	if not info.PunchRange or thief.state == "Arrested" or thief.state == "Escaped" then
		return false
	end
	local time = now()
	if thief.punchStarted > 0 then
		local elapsed = time - thief.punchStarted
		if not thief.punchHit and elapsed >= info.PunchWindup then
			thief.punchHit = true
			local player = thief.punchTarget
			-- Охранник мог отскочить, пока Громила замахивался
			if player and inFront(thief, player, info.PunchRange + 1.5) then
				knockDown(thief, player)
			end
		end
		if elapsed < info.PunchSeconds then
			stand(thief)
			return true
		end
		-- Удар закончен: кража и задание продолжаются с того же места
		thief.punchStarted = 0
		thief.punchTarget = nil
		thief.stealStarted += info.PunchSeconds
		thief.taskStarted += info.PunchSeconds
		return false
	end
	if time < thief.nextPunch then
		return false
	end
	local player = guardToPunch(thief)
	if not player then
		return false
	end
	thief.punchStarted = time
	thief.punchTarget = player
	thief.punchHit = false
	thief.nextPunch = time + info.PunchCooldown
	stand(thief)
	return true
end

---------------------------------------------------------------- побег, подкоп, крыша

-- Вор вынес экспонат из музея (через дверь или по верёвке на крышу). Мона Лиза — игра окончена,
-- дешёвый экспонат пропадает, вор уходит. Возвращает true, если вора уже убрали.
local function getAway(thief: Thief, carried: ExhibitService.Exhibit): boolean
	if carried.isMain then
		thief.state = "Escaped"
		stand(thief)
		ThiefService.Escaped:Fire(thief.model)
		return false
	end
	bannerRemote:FireAllClients(("THE %s IS GONE!"):format(string.upper(carried.title)), "danger")
	ExhibitService.lose(carried)
	ThiefService.remove(thief.model)
	return true
end

local function rootHeight(thief: Thief): number
	return thief.humanoid.HipHeight + thief.root.Size.Y / 2
end

-- Ставит закреплённого вора (в дыре, на верёвке) в точку, лицом к цели.
local function anchoredAt(thief: Thief, x: number, y: number, z: number)
	local position = Vector3.new(x, y, z)
	local target = thief.target
	local look = if target then Vector3.new(target.look.X, y, target.look.Z) else position + flat(thief.root.CFrame.LookVector)
	if flatDistance(position, look) > 0.1 then
		thief.root.CFrame = CFrame.lookAt(position, look)
	else
		thief.root.CFrame = CFrame.new(position) * thief.root.CFrame.Rotation
	end
end

-- Вор встал на пол: дальше ходит сам, как обычный.
local function land(thief: Thief)
	thief.root.Anchored = false
	pcall(function()
		thief.root:SetNetworkOwner(nil)
	end)
	thief.holdDone = true
	thief.state = nextState(thief)
end

local function guardNear(point: Vector3, radius: number): boolean
	for _, guard in ThiefService.guardPositions() do
		if flatDistance(guard, point) < radius then
			return true
		end
	end
	return false
end

local function smoothStep(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Шахтёр под полом: за CrackSeconds до появления пол трескается, потом он вылезает из дыры.
local function updateDig(thief: Thief)
	local special = thief.special :: Special
	local info = thief.info
	local time = now()
	if not special.hole and time >= special.digUntil - info.CrackSeconds then
		special.hole = HeistFx.crackFloor(special.digPoint)
	end
	if time < special.digUntil then
		return
	end
	local hole = special.hole
	if hole then
		HeistFx.openHole(hole)
	end
	local point = special.digPoint
	thief.model:PivotTo(CFrame.new(point.X, special.floorY - info.EmergeDepth, point.Z))
	thief.model.Parent = folder
	thief.state = "Emerge"
	special.started = time
	anchoredAt(thief, point.X, special.floorY - info.EmergeDepth, point.Z)
	syncAnim(thief)
	setupFootsteps(thief)
	ScoreService.addSpawned()
	ThiefService.Spawned:Fire(thief.model)
end

-- Части пути Шахтёра и Стекольщика, пока они закреплены: вылезает из дыры, режет стекло, ждёт на крыше,
-- спускается и поднимается на верёвке.
local SPECIAL_STATES = { Emerge = true, Roof = true, RoofWait = true, Descend = true, Ascend = true }

local function updateSpecial(thief: Thief)
	local special = thief.special :: Special
	local info = thief.info
	local state = thief.state
	local elapsed = now() - special.started
	local cut = special.cut
	if state == "Emerge" then
		local t = math.clamp(elapsed / info.EmergeSeconds, 0, 1)
		local k = 1 - (1 - t) * (1 - t) -- быстро вначале, плавно в конце
		local point = special.digPoint
		anchoredAt(thief, point.X, special.floorY - info.EmergeDepth * (1 - k), point.Z)
		if t >= 1 then
			land(thief)
		end
	elseif state == "Roof" then
		if cut then
			HeistFx.cutProgress(cut, elapsed / info.CutSeconds)
		end
		if elapsed >= info.CutSeconds then
			if cut then
				HeistFx.finishCut(cut)
			end
			thief.state = "RoofWait"
			special.started = now()
		end
	elseif state == "RoofWait" then
		-- Ждёт, пока охрана отойдёт от места спуска (и сигнала своего плана), но не дольше WaitMax
		local hold = thief.options.hold
		local ready = (not hold or hold()) and not guardNear(special.landPoint, info.ClearRadius)
		if ready or elapsed >= info.WaitMax then
			thief.state = "Descend"
			special.started = now()
			anchoredAt(thief, special.holeCenter.X, special.roofY, special.holeCenter.Z)
		end
	elseif state == "Descend" then
		local t = math.clamp(elapsed / info.DescendSeconds, 0, 1)
		local y = special.roofY + (special.floorY - special.roofY) * smoothStep(t)
		anchoredAt(thief, special.landPoint.X, y, special.landPoint.Z)
		if cut then
			HeistFx.setRope(cut, y + 0.8)
		end
		if t >= 1 then
			if cut then
				HeistFx.setRope(cut, special.floor + 0.2) -- верёвка висит до пола
			end
			land(thief)
		end
	elseif state == "Ascend" then
		local t = math.clamp(elapsed / info.ClimbSeconds, 0, 1)
		local y = special.floorY + (special.roofY - special.floorY) * t
		anchoredAt(thief, special.landPoint.X, y, special.landPoint.Z)
		if cut then
			HeistFx.setRope(cut, y + 0.8)
		end
		if t >= 1 then
			local carried = ExhibitService.getCarried(thief.model)
			if carried then
				getAway(thief, carried)
			else
				ThiefService.remove(thief.model)
			end
		end
	end
end

-- Состояния, в которых вор замечает охранника и убегает.
local FLEE_STATES = { Approach = true, GoTask = true, Hold = true }
-- Состояния, из которых вор бросается загораживать того, кто несёт Мону Лизу.
local BLOCK_STATES = { Approach = true, GoTask = true, Hold = true, Flee = true, Block = true }

local function updateThief(thief: Thief)
	if thief.state == "Arrested" or thief.state == "Escaped" then
		return
	end
	if thief.state == "Stunned" then
		-- Шокер: лежит, его можно арестовать; время вышло — встаёт и продолжает своё
		if now() >= thief.stunUntil then
			thief.humanoid.WalkSpeed = ThiefConfig.SneakSpeed
			thief.state = nextState(thief)
			syncAnim(thief)
		else
			stand(thief)
		end
		return
	end
	if updatePunch(thief) then
		syncAnim(thief)
		return
	end
	if SPECIAL_STATES[thief.state] then
		updateSpecial(thief)
		if thieves[thief.model] then
			syncAnim(thief)
		end
		return
	end
	local model = thief.model
	local position = thief.root.Position
	local carried = ExhibitService.getCarried(model)
	local mainBusy = ExhibitService.mainBusyBy() -- кто снимает или несёт Мону Лизу

	-- Выбираем, что делать
	if carried then
		thief.state = "Escape"
	elseif mainBusy and mainBusy ~= model and BLOCK_STATES[thief.state] and not thief.options.disguise then
		thief.state = "Block"
	elseif thief.state == "Block" or thief.state == "Escape" then
		thief.state = nextState(thief)
	elseif thief.state == "Flee" and now() >= thief.fleeUntil then
		thief.state = nextState(thief)
	end

	if FLEE_STATES[thief.state] and not (thief.options.noFlee or thief.info.NoFlee) then
		local guardPosition, guardDistance = nearestGuard(position)
		if guardPosition and guardDistance < ThiefConfig.FleeRadius then
			-- Заметил охранника — убегает в другую сторону
			thief.state = "Flee"
			thief.fleeUntil = now() + ThiefConfig.FleeSeconds
			local away = flat(position - guardPosition)
			if away.Magnitude < 0.1 then
				away = Vector3.new(1, 0, 0)
			end
			thief.fleeTarget = position + away.Unit * ThiefConfig.FleeDistance
			showSpotted(thief)
		end
	end

	-- Делаем
	local state = thief.state
	if state == "GoTask" then
		local point = taskPoint(thief)
		if not point then
			finishTask(thief)
		elseif flatDistance(position, point) < (if thief.taskCase then Smart.CaseReach else ThiefConfig.StealReachDistance) then
			thief.state = "Task"
			thief.taskStarted = now()
			stand(thief)
			local look = if thief.taskCase
				then thief.taskCase.model:GetPivot().Position
				elseif thief.cameraQueue[1] then thief.cameraQueue[1].Position
				elseif thief.task == "Fuse" then BlackoutService.lookPoint() or point
				else point
			face(thief, look)
			if thief.task == "Fuse" then
				BlackoutService.sparks(taskSeconds(thief)) -- искры, пока возится с проводами
			end
		else
			moveTowards(thief, point, walkSpeed(thief))
		end
	elseif state == "Task" then
		stand(thief)
		if now() - thief.taskStarted >= taskSeconds(thief) then
			completeTask(thief)
		end
	elseif state == "Hold" then
		local hold = thief.options.hold
		if thief.holdStarted <= 0 then
			thief.holdStarted = now()
		end
		local timeout = thief.options.holdTimeout or Smart.HoldTimeout
		if not hold or hold() or now() - thief.holdStarted >= timeout then
			thief.holdDone = true
			thief.holdArrived = false
			thief.state = "Approach"
		elseif flatDistance(position, thief.holdPoint) > 2.5 then
			thief.holdArrived = false
			moveTowards(thief, thief.holdPoint, walkSpeed(thief))
		else
			thief.holdArrived = true
			stand(thief)
		end
	elseif state == "Approach" then
		-- Цель пропала (её унёс другой вор или снимает другой) — выбираем новую, подальше от охраны
		local target = thief.target
		if not target or not ExhibitService.isFree(target, model) then
			target = ExhibitService.pickTarget(model, thief.options.target, ThiefService.guardPositions())
			if not target and thief.options.target ~= nil then
				target = ExhibitService.pickTarget(model, nil, ThiefService.guardPositions())
			end
			thief.target = target
		end
		local near = target ~= nil and flatDistance(position, target.stand) < ThiefConfig.StealReachDistance
		if not target then
			stand(thief)
		elseif near and thief.options.disguise and watched(thief) then
			stand(thief) -- Фальшивый охранник ждёт у экспоната, пока на него никто не смотрит
		elseif near and ExhibitService.tryStartSteal(target, model) then
			thief.state = "Steal"
			thief.stealStarted = now()
			stand(thief)
			face(thief, target.look)
		else
			moveTowards(thief, target.stand, walkSpeed(thief))
		end
	elseif state == "Steal" then
		stand(thief)
		local target = thief.target
		if not target or target.stealer ~= model then
			ExhibitService.cancelSteal(model)
			thief.state = "Approach"
		elseif now() - thief.stealStarted >= ThiefConfig.StealSeconds then
			if ExhibitService.take(target, model) then
				startEscape(thief, target)
			else
				ExhibitService.cancelSteal(model)
				thief.state = "Approach"
			end
		end
	elseif state == "Escape" then
		-- Стекольщик убегает к своей верёвке, остальные — к ближайшей двери
		local special = thief.special
		local rope = special and special.cut and special.landPoint
		local exit = rope or nearestEntrance(position)
		if exit and carried then
			if flatDistance(position, exit) < ThiefConfig.EscapeReachDistance then
				if rope and special then
					thief.state = "Ascend" -- лезет по верёвке на крышу с добычей
					special.started = now()
					thief.root.Anchored = true
					stand(thief)
				elseif getAway(thief, carried) then
					return
				end
			else
				moveTowards(thief, exit, speedFor(thief, ThiefConfig.CarrySpeed))
			end
		end
	elseif state == "Flee" then
		moveTowards(thief, thief.fleeTarget, speedFor(thief, ThiefConfig.RunSpeed))
	elseif state == "Block" then
		-- Встаёт между охранником и тем, кто снимает или несёт Мону Лизу
		local protected = mainBusy
		local protectedRoot = protected and protected:FindFirstChild("HumanoidRootPart")
		if protectedRoot and protectedRoot:IsA("BasePart") then
			local base = protectedRoot.Position
			local guardPosition = nearestGuard(base)
			local target
			if guardPosition and flat(guardPosition - base).Magnitude > 0.1 then
				target = base + flat(guardPosition - base).Unit * ThiefConfig.BlockDistance
			else
				target = base - protectedRoot.CFrame.LookVector * ThiefConfig.BlockDistance
			end
			moveTowards(thief, target, speedFor(thief, ThiefConfig.RunSpeed))
		else
			stand(thief)
		end
	end
	syncAnim(thief)
end

---------------------------------------------------------------- появление и удаление

-- Сколько воров сейчас занимают место в музее (пойманные, которые вот-вот исчезнут, не считаются).
function ThiefService.aliveCount(): number
	local count = 0
	for _, thief in thieves do
		if thief.state ~= "Arrested" then
			count += 1
		end
	end
	return count
end

-- Шахтёр: выбирает экспонат подальше от охраны (не тот, у которого уже копает другой) и место рядом.
local function setupMiner(thief: Thief): boolean
	local info = thief.info
	local guards = ThiefService.guardPositions()
	local avoid = {}
	for _, other in thieves do
		if other.kind == "Miner" and (other.state == "Dig" or other.state == "Emerge") and other.target then
			table.insert(avoid, other.target)
		end
	end
	local target = ExhibitService.pickTarget(nil, thief.options.target, guards, avoid)
	if not target and #avoid > 0 then
		target = ExhibitService.pickTarget(nil, thief.options.target, guards)
	end
	if not target then
		return false
	end
	local point = HeistFx.digPoint(target.stand, target.look, info.EmergeDistance, guards)
	if not point then
		return false
	end
	thief.target = target
	local height = rootHeight(thief)
	thief.special = {
		started = now(),
		floorY = point.Y + height,
		floor = point.Y,
		digUntil = now() + info.DigSeconds + random:NextNumber(-info.DigJitter, info.DigJitter),
		digPoint = point,
		hole = nil,
		cut = nil,
		holeCenter = point,
		landPoint = point,
		roofY = point.Y + height,
	}
	thief.root.Anchored = true
	thief.state = "Dig" -- его не видно, пока не вылезет (модель ещё не в мире)
	return true
end

-- Стекольщик: место спуска перед экспонатом (чаще Мона Лиза) под стеклянным потолком, на крыше рядом с ним.
local function setupGlazier(thief: Thief): boolean
	local info = thief.info
	local target = ExhibitService.pickTarget(thief.model, thief.options.target or "Main", ThiefService.guardPositions())
	if not target then
		return false
	end
	local away = flat(target.stand - target.look)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local top = HeistFx.skylightPoint(target.stand + away * info.LandOffset, info.SkylightMargin + info.HoleRadius)
	if not top then
		return false
	end
	local floorPoint = HeistFx.floorAt(Vector3.new(top.X, target.stand.Y, top.Z))
	local floor = if floorPoint then floorPoint.Y else target.stand.Y - 3
	local height = rootHeight(thief)
	local roofY = top.Y + height
	thief.target = target
	thief.special = {
		started = now(),
		floorY = floor + height,
		floor = floor,
		digUntil = 0,
		digPoint = top,
		hole = nil,
		cut = HeistFx.startCut(top, info.HoleRadius),
		holeCenter = top,
		landPoint = Vector3.new(top.X, floor + height, top.Z),
		roofY = roofY,
	}
	thief.root.Anchored = true
	local kneel = top + Vector3.new(info.HoleRadius + 0.9, 0, 0)
	thief.model:PivotTo(CFrame.lookAt(Vector3.new(kneel.X, roofY, kneel.Z), Vector3.new(top.X, roofY, top.Z)))
	thief.model.Parent = folder
	thief.state = "Roof"
	return true
end

-- Новый вор по приказу волны. Возвращает модель или nil (нет дверей, Roblox не собрал персонажа, ночь кончилась).
function ThiefService.spawnSpecial(options: Options): Model?
	if not active then
		return nil
	end
	local kind = options.kind or "Pickpocket"
	local info = kindInfo(kind)
	-- Шахтёр приходит из-под пола, Стекольщик — по крыше (если у музея есть стеклянный потолок)
	local special = kind == "Miner" or (kind == "Glazier" and HeistFx.skylight() ~= nil)
	local entrance = if special then nil else (options.entrance or ThiefService.pickEntrance())
	if not special and not entrance then
		return nil
	end
	local model = ThiefKinds.build(kind, options.disguise)
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not active or not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy() -- ночь кончилась, пока собирался персонаж, или он собрался без частей
		return nil
	end
	if options.disguise then
		-- Ник игрока над головой, как у настоящих охранников
		humanoid.DisplayName = options.disguise.DisplayName
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		model:SetAttribute(GameState.ThiefAttr.Disguise, options.disguise.DisplayName)
	else
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	humanoid.WalkSpeed = ThiefConfig.SneakSpeed
	ModelLibrary.setCollisionGroup(model, ModelLibrary.Groups.Thieves)
	if entrance then
		model:PivotTo(entrance.CFrame)
		model.Parent = folder
		pcall(function()
			root:SetNetworkOwner(nil) -- воров двигает только сервер
		end)
	end

	local taskName = options.task
	if taskName == nil and kind == "Breaker" then
		taskName = "Camera" -- взломщик сначала ломает ближайшую камеру
	elseif taskName == nil and kind == "Brute" and random:NextNumber() < info.SmashChance then
		taskName = "Smash" -- Громила иногда сначала разбивает витрину вдали от охраны
	elseif taskName == nil and kind == "Cutter" and not BlackoutService.isOut() and BlackoutService.standPoint() then
		taskName = "Fuse" -- Светорез сначала вырубает свет у щитка
	end
	local thief: Thief = {
		model = model,
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 }),
		kind = kind,
		info = info,
		options = options,
		state = "Approach",
		waypoints = {},
		waypointIndex = 1,
		pathTarget = nil,
		pathTime = 0,
		computing = false,
		stealStarted = 0,
		target = nil,
		fleeUntil = 0,
		fleeTarget = root.Position,
		task = taskName,
		taskDone = false,
		taskStarted = 0,
		taskCase = nil,
		cameraQueue = if options.cameras then table.clone(options.cameras) else {},
		autoCamera = taskName == "Camera" and options.task == nil,
		holdPoint = if entrance then holdPointFor(entrance) else root.Position,
		holdStarted = 0,
		holdDone = false,
		holdArrived = false,
		punchStarted = 0,
		punchTarget = nil,
		punchHit = false,
		nextPunch = 0,
		special = nil,
		stunUntil = 0,
		footsteps = nil,
		connections = {},
	}
	thief.state = nextState(thief)
	if kind == "Miner" then
		if not setupMiner(thief) then
			model:Destroy()
			return nil
		end
		thieves[model] = thief -- копает: место в музее занимает, но появится позже (Spawned — когда вылезет)
		return model
	elseif special then
		if not setupGlazier(thief) then
			model:Destroy()
			return nil
		end
	end
	thieves[model] = thief
	syncAnim(thief)
	setupFootsteps(thief)
	ScoreService.addSpawned()
	ThiefService.Spawned:Fire(model)
	return model
end

-- Убирает вора совсем (после ареста или в конце ночи).
function ThiefService.remove(model: Model)
	local thief = thieves[model]
	if thief then
		for _, connection in thief.connections do
			connection:Disconnect()
		end
		thieves[model] = nil
	end
	ExhibitService.cancelSteal(model)
	local carried = ExhibitService.getCarried(model)
	if carried then
		ExhibitService.returnHome(carried)
	end
	model:Destroy()
end

function ThiefService.isThief(instance: Instance): boolean
	return instance:IsA("Model") and thieves[instance] ~= nil
end

function ThiefService.isArrested(model: Model): boolean
	local thief = thieves[model]
	return thief == nil or thief.state == "Arrested"
end

-- Вора больше нет в музее: пойман, убежал или исчез.
function ThiefService.isGone(model: Model?): boolean
	if not model then
		return false
	end
	local thief = thieves[model]
	return thief == nil or thief.state == "Arrested" or thief.state == "Escaped"
end

-- Задание вора сделано (витрина, камеры…) — или вора уже нет.
function ThiefService.taskDone(model: Model?): boolean
	if not model then
		return false
	end
	local thief = thieves[model]
	return thief == nil or thief.task == nil or thief.taskDone
end

-- Вор несёт экспонат.
function ThiefService.isCarrying(model: Model?): boolean
	return model ~= nil and ExhibitService.getCarried(model) ~= nil
end

-- Арест: вор замирает (руки вверх, потом в наручники — анимация на клиентах). Картина, если была у него, возвращается на стену.
-- Возвращает true, если арест получился.
function ThiefService.arrest(model: Model): boolean
	local thief = thieves[model]
	if not thief or thief.state == "Arrested" then
		return false
	end
	thief.state = "Arrested"
	thief.humanoid.WalkSpeed = 0
	stand(thief)
	thief.root.Anchored = true
	syncAnim(thief)
	if thief.footsteps then
		thief.footsteps:Stop()
	end
	ExhibitService.cancelSteal(model)
	local carried = ExhibitService.getCarried(model)
	if carried then
		ExhibitService.returnHome(carried)
	end
	return true
end

-- Шокер (блок 4): вор падает на спину на seconds секунд, дёргается, его можно арестовать.
-- Что нёс — роняет (экспонат возвращается на место). Фальшивый охранник при этом выдаёт себя.
-- Шахтёра под полом и Стекольщика на верёвке шокер не берёт. Возвращает true, если оглушил.
function ThiefService.stun(model: Model, seconds: number): boolean
	local thief = thieves[model]
	if not thief or thief.state == "Arrested" or thief.state == "Escaped" or thief.state == "Dig" or SPECIAL_STATES[thief.state] then
		return false
	end
	local wasStunned = thief.state == "Stunned"
	thief.state = "Stunned"
	thief.stunUntil = now() + seconds
	thief.punchStarted = 0
	thief.punchTarget = nil
	thief.humanoid.WalkSpeed = 0
	stand(thief)
	if thief.footsteps then
		thief.footsteps:Stop()
	end
	ExhibitService.cancelSteal(model)
	local carried = ExhibitService.getCarried(model)
	if carried then
		ExhibitService.returnHome(carried)
	end
	if thief.options.disguise then
		model:SetAttribute(GameState.ThiefAttr.Disguise, nil)
	end
	if not wasStunned then
		syncAnim(thief) -- лежал уже — не падает заново
	end
	HeistFx.stunEffect(model, seconds)
	return true
end

---------------------------------------------------------------- ночь

-- Сколько воров придёт за ночь (решение 70): в 1-ю ночь 3 на игрока, каждую следующую +1 на игрока,
-- но только до 5-й ночи — дальше сложность растёт за счёт видов воров и планов (блок 3).
function ThiefService.countForNight(playerCount: number, night: number): number
	local players = math.max(1, playerCount)
	local grownNights = math.clamp(night, 1, ThiefConfig.GrowUntilNight) - 1
	return players * (ThiefConfig.PerPlayerFirstNight + grownNights * ThiefConfig.PerPlayerGrowth)
end

-- night — какая по счёту ночь: чем дальше, тем воры быстрее. Когда и кто приходит, решает WaveService.
function ThiefService.beginNight(night: number)
	ThiefService.endNight()
	currentNight = math.max(1, night)
	local difficulty = Config.Difficulty
	speedMultiplier = math.min(difficulty.MaxSpeedMultiplier, 1 + (currentNight - 1) * difficulty.SpeedGrowthPerNight)
	active = true
	local accumulator = 0
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ThiefConfig.UpdateSeconds then
			return
		end
		accumulator = 0
		for _, thief in thieves do
			if thief.state == "Dig" then
				updateDig(thief) -- Шахтёр под полом: модели ещё нет в мире
			elseif thief.model.Parent then
				updateThief(thief)
			end
		end
	end)
end

function ThiefService.endNight()
	active = false
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	-- Сначала экспонаты на место, потом убираем воров, иначе экспонаты упадут вместе с ними
	ExhibitService.returnAll()
	local models = {}
	for model in thieves do
		table.insert(models, model)
	end
	for _, model in models do
		ThiefService.remove(model)
	end
end

function ThiefService.init(map: Instance)
	local existing = Workspace:FindFirstChild(MapSchema.Thieves)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = MapSchema.Thieves
		created.Parent = Workspace
		folder = created
	end
	local entranceFolder = map:FindFirstChild(MapSchema.Entrances)
	if entranceFolder then
		for _, child in entranceFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(entrances, child)
			end
		end
	end
	if #entrances == 0 then
		warn("[ThiefService] На карте нет входов для воров")
	end
end

return ThiefService
