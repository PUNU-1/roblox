-- Туристы днём: входят через один из 4 входов музея (WingService.entrances: двери центра или наружные двери крыльев), платят за билет («+$10» над головой, деньги
-- делятся поровну между игроками), гуляют от одного места к другому — смотрят, иногда
-- фотографируют — и уходят через ближайшую дверь. Чем привлекательнее экспонаты, тем больше туристов за день.
-- Уход (этап 5, блок E): цель — точка снаружи за дверью входа; прошёл дверь — плавно тает. Уходящие расходятся
-- по разным дверям. Застрял — путь пересчитывается, стоит долго — тает. За 1 сек до ночи тают все оставшиеся.
-- Движения рук и ног делает NpcAnimator на клиентах по атрибуту AnimState.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local Audio = require(Server:WaitForChild("Audio"))
local WingService = require(Server:WaitForChild("WingService"))
local TouristLooks = require(Server:WaitForChild("TouristLooks"))

local TouristConfig = Config.Tourists
local Anim = GameState.TouristAnim

local TouristService = {}

-- Место, которое турист идёт смотреть: где встать и куда смотреть.
export type Attraction = {
	stand: Vector3,
	look: Vector3,
}

type Bench = {
	model: PVInstance,
	hall: string,
	floorY: number,
	seatTopY: number,
	lookDir: Vector3,
	seats: { BenchSeat },
}

type BenchSeat = {
	bench: Bench,
	seatWorld: Vector3,
	approach: Vector3,
	occupant: Model?,
}

type Tourist = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	isChild: boolean,
	walkSpeed: number,
	leaveSpeed: number,
	state: string, -- Walk | Admire | GoBench | Sit | Orbit | Leave
	waypoints: { PathWaypoint },
	waypointIndex: number,
	target: Vector3,
	look: Vector3,
	atExhibit: boolean,
	pointAt: number,
	admireUntil: number,
	sitUntil: number,
	justSat: boolean,
	benchSeat: BenchSeat?,
	orbitTarget: Model?,
	orbitUntil: number,
	orbitAngle: number,
	orbitDir: number,
	visitsLeft: number,
	computing: boolean,
	pathToken: number,
	walkStarted: number,
	exit: BasePart?, -- вход, через который уходит (state = Leave)
	progressAt: number, -- когда последний раз заметно сдвинулся
	progressPosition: Vector3,
	repaths: number, -- сколько раз пересчитан путь с тех пор, как встал
}


local tourists: { [Model]: Tourist } = {}
local fading: { [Model]: true } = {} -- тают: уже не обновляются, исчезнут сами (или в endDay)
local floors: { BasePart } = {} -- полы залов (атрибут Hall), кроме служебных (Wander = false)
local benches: { Bench } = {} -- скамейки prop_bench_01 в открываемых залах (максимум 2 места на каждой)
local folder: Folder
local attractionsProvider: (() -> { Attraction })? = nil
local updateConnection: RBXScriptConnection? = nil
local spawnThread: thread? = nil
local random = Random.new()
local touristsToday = 0
local closing = false -- музей закрывается: новые не приходят, все идут к выходу

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

local function setAnim(tourist: Tourist, anim: string)
	if tourist.model:GetAttribute(GameState.NpcAttr.AnimState) ~= anim then
		tourist.model:SetAttribute(GameState.NpcAttr.AnimStateAt, now())
		tourist.model:SetAttribute(GameState.NpcAttr.AnimState, anim)
	end
end

local function walkAnim(tourist: Tourist): string
	return if tourist.isChild then Anim.Skip else Anim.Stroll
end

local function floorAt(position: Vector3): BasePart?
	for _, floor in floors do
		local rel = floor.CFrame:PointToObjectSpace(position)
		if math.abs(rel.X) <= floor.Size.X / 2
			and math.abs(rel.Z) <= floor.Size.Z / 2
			and position.Y >= floor.Position.Y - 1
			and position.Y <= floor.Position.Y + floor.Size.Y / 2 + 3
		then
			return floor
		end
	end
	return nil
end

local function releaseBench(tourist: Tourist)
	local seat = tourist.benchSeat
	if seat then
		if seat.occupant == tourist.model then
			seat.occupant = nil
		end
		tourist.benchSeat = nil
	end
end

local function unseat(tourist: Tourist)
	local seat = tourist.benchSeat
	if seat and tourist.state == "Sit" then
		local standY = seat.bench.floorY + tourist.humanoid.HipHeight + tourist.root.Size.Y / 2
		local standPos = Vector3.new(seat.approach.X, standY, seat.approach.Z)
		tourist.root.CFrame = CFrame.lookAt(standPos, standPos + seat.bench.lookDir)
	end
	tourist.root.Anchored = false
	releaseBench(tourist)
end

-- «+$10» (цена билета) всплывает над туристом и тает.
local function showTicket(tourist: Tourist)
	local head = tourist.model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local reward = Config.Effects.Reward
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Ticket"
	billboard.Size = UDim2.fromScale(reward.Width * 0.8, reward.Height * 0.8)
	billboard.StudsOffset = Vector3.new(0, reward.StartHeight, 0)
	billboard.MaxDistance = reward.MaxDistance
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "+$" .. tostring(Config.Money.TicketPrice)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = reward.Color
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = head
	local seconds = 1.5
	TweenService:Create(billboard, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, reward.EndHeight, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(billboard, seconds)
end

---------------------------------------------------------------- куда идти

-- Случайное место в одном из открытых залов. Чем больше пол, тем чаще туда идут:
-- туристы гуляют по центру и залам, а не по узким коридорам.
local function randomWanderSpot(): Attraction
	local open = {}
	local totalArea = 0
	for _, floor in floors do
		if GameState.isHallOpen(floor:GetAttribute("Hall")) then
			table.insert(open, floor)
			totalArea += floor.Size.X * floor.Size.Z
		end
	end
	local stand = Vector3.new(0, 3, 20)
	if #open > 0 then
		local floor = open[#open]
		local roll = random:NextNumber(0, totalArea)
		for _, candidate in open do
			roll -= candidate.Size.X * candidate.Size.Z
			if roll <= 0 then
				floor = candidate
				break
			end
		end
		local inset = TouristConfig.WanderInset
		local halfX = math.max(0, floor.Size.X / 2 - inset)
		local halfZ = math.max(0, floor.Size.Z / 2 - inset)
		stand = Vector3.new(
			floor.Position.X + random:NextNumber(-halfX, halfX),
			3,
			floor.Position.Z + random:NextNumber(-halfZ, halfZ)
		)
	end
	local angle = random:NextNumber(0, math.pi * 2)
	return { stand = stand, look = stand + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5 }
end

local function nextAttraction(): (Attraction, boolean)
	local list = if attractionsProvider then attractionsProvider() else {}
	if #list > 0 and random:NextNumber() < 0.75 then
		local spot = pick(list)
		-- Встаём не в одну точку, чтобы туристы не толпились друг в друге
		local offset = Vector3.new(random:NextNumber(-2.5, 2.5), 0, random:NextNumber(-1.5, 1.5))
		return { stand = spot.stand + offset, look = spot.look }, true
	end
	return randomWanderSpot(), false
end

local function goTo(tourist: Tourist, target: Vector3)
	tourist.target = target
	tourist.walkStarted = now()
	tourist.waypoints = {}
	tourist.waypointIndex = 1
	tourist.computing = true
	tourist.pathToken += 1
	local token = tourist.pathToken
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
		local ok = pcall(function()
			path:ComputeAsync(tourist.root.Position, target)
		end)
		if not tourists[tourist.model] or tourist.pathToken ~= token then
			return
		end
		tourist.computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			tourist.waypoints = path:GetWaypoints()
			tourist.waypointIndex = 2
		end
	end)
end

-- Новая прогулка: счётчик застревания с нуля.
local function walkTo(tourist: Tourist, target: Vector3)
	tourist.progressAt = now()
	tourist.progressPosition = tourist.root.Position
	tourist.repaths = 0
	goTo(tourist, target)
end

local function startVisit(tourist: Tourist)
	local spot, atExhibit = nextAttraction()
	tourist.state = "Walk"
	tourist.look = spot.look
	tourist.atExhibit = atExhibit
	tourist.pointAt = 0
	tourist.justSat = false
	walkTo(tourist, spot.stand)
	setAnim(tourist, walkAnim(tourist))
end

local function trySitOnBench(tourist: Tourist): boolean
	if closing or tourist.justSat or #benches == 0 or random:NextNumber() >= TouristConfig.BenchChance then
		return false
	end
	local free: { BenchSeat } = {}
	for _, bench in benches do
		if GameState.isHallOpen(bench.hall) then
			for _, seat in bench.seats do
				if seat.occupant == nil then
					table.insert(free, seat)
				end
			end
		end
	end
	if #free == 0 then
		return false
	end
	local seat = pick(free)
	seat.occupant = tourist.model
	tourist.benchSeat = seat
	tourist.state = "GoBench"
	tourist.atExhibit = false
	tourist.pointAt = 0
	tourist.look = seat.bench.lookDir
	walkTo(tourist, seat.approach)
	setAnim(tourist, walkAnim(tourist))
	return true
end

local function tryOrbitAdult(tourist: Tourist): boolean
	if not tourist.isChild or closing or random:NextNumber() >= TouristConfig.ChildOrbitChance then
		return false
	end
	local position = tourist.root.Position
	local candidates: { Tourist } = {}
	for _, other in tourists do
		if not other.isChild
			and other.state ~= "Leave"
			and flatDistance(position, other.root.Position) <= TouristConfig.ChildOrbitSearchRadius
		then
			table.insert(candidates, other)
		end
	end
	if #candidates == 0 then
		return false
	end
	local adult = pick(candidates)
	local delta = position - adult.root.Position
	tourist.state = "Orbit"
	tourist.orbitTarget = adult.model
	tourist.orbitUntil = now() + random:NextNumber(TouristConfig.ChildOrbitMin, TouristConfig.ChildOrbitMax)
	tourist.orbitAngle = math.atan2(delta.Z, delta.X)
	tourist.orbitDir = if random:NextNumber() < 0.5 then 1 else -1
	tourist.computing = false
	tourist.pathToken += 1
	tourist.progressAt = now()
	tourist.progressPosition = position
	tourist.repaths = 0
	setAnim(tourist, Anim.Skip)
	return true
end

-- Середина двери входа и направление наружу (атрибуты MapBuilder). У старой карты без них — сама точка входа.
local function doorOf(marker: BasePart): (Vector3, Vector3?)
	local point = marker:GetAttribute(GameState.EntranceAttr.DoorPoint)
	local outward = marker:GetAttribute(GameState.EntranceAttr.DoorOutward)
	if typeof(point) == "Vector3" and typeof(outward) == "Vector3" then
		return point, outward
	end
	return marker.Position, nil
end

-- Куда идти, чтобы выйти: точка снаружи, на ExitBeyond стадов за дверью (а не створки и не тамбур за углом).
local function exitPoint(marker: BasePart): Vector3
	local point, outward = doorOf(marker)
	if outward then
		return Vector3.new(point.X, marker.Position.Y, point.Z) + outward * TouristConfig.ExitBeyond
	end
	return marker.Position
end

-- Прошёл ли турист дверь своего выхода (он уже снаружи).
local function passedDoor(tourist: Tourist): boolean
	local marker = tourist.exit
	if not marker then
		return false
	end
	local point, outward = doorOf(marker)
	if not outward then
		return false
	end
	local offset = tourist.root.Position - point
	offset = Vector3.new(offset.X, 0, offset.Z)
	local depth = offset:Dot(outward)
	local lateral = (offset - outward * depth).Magnitude
	return depth > TouristConfig.DoorPassDepth and lateral < TouristConfig.DoorPassLateral
end

-- Выход для туриста: ближайшая дверь (по прямой до середины двери), но к каждому, кто уже идёт к этой двери,
-- прибавляется ExitCrowdPenalty стадов — туристы расходятся по разным входам, а не толпятся в одном.
local function chooseExit(position: Vector3): BasePart?
	local load: { [BasePart]: number } = {}
	for _, other in tourists do
		if other.state == "Leave" and other.exit then
			load[other.exit] = (load[other.exit] or 0) + 1
		end
	end
	local best, bestScore = nil, math.huge
	for _, marker in WingService.entrances() do
		local point = doorOf(marker)
		local score = flatDistance(point, position) + (load[marker] or 0) * TouristConfig.ExitCrowdPenalty
		if score < bestScore then
			best, bestScore = marker, score
		end
	end
	return best
end

local function startLeaving(tourist: Tourist)
	unseat(tourist)
	tourist.orbitTarget = nil
	tourist.pointAt = 0
	if closing then
		tourist.humanoid.WalkSpeed = tourist.leaveSpeed
	end
	tourist.state = "Leave"
	setAnim(tourist, walkAnim(tourist))
	tourist.exit = nil -- чтобы сам себя не считал в толпе у двери
	local exit = chooseExit(tourist.root.Position)
	tourist.exit = exit
	if exit then
		walkTo(tourist, exitPoint(exit))
	end
end

local function advanceAfterStop(tourist: Tourist)
	tourist.visitsLeft -= 1
	if closing or tourist.visitsLeft <= 0 then
		startLeaving(tourist)
		return
	end
	if tryOrbitAdult(tourist) then
		return
	end
	if trySitOnBench(tourist) then
		return
	end
	startVisit(tourist)
end

---------------------------------------------------------------- поведение

-- Турист плавно тает (без облачка) и исчезает. Пока тает, идёт дальше, куда шёл.
local function fadeOut(tourist: Tourist)
	local model = tourist.model
	if not tourists[model] then
		return
	end
	releaseBench(tourist)
	tourist.orbitTarget = nil
	tourists[model] = nil
	fading[model] = true
	local info = TweenInfo.new(TouristConfig.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, item in model:GetDescendants() do
		if (item:IsA("BasePart") or item:IsA("Decal")) and item.Transparency < 1 then
			TweenService:Create(item, info, { Transparency = 1 }):Play()
		elseif item:IsA("TextLabel") then
			TweenService:Create(item, info, { TextTransparency = 1 }):Play() -- надпись на футболке
		end
	end
	task.delay(TouristConfig.FadeSeconds, function()
		fading[model] = nil
		model:Destroy()
	end)
end

-- Застрял ли: не сдвинулся заметно за StuckSeconds — пересчитать путь; за GiveUpSeconds — сдаться.
-- Возвращает true, если пора сдаваться.
local function checkStuck(tourist: Tourist, position: Vector3): boolean
	if flatDistance(position, tourist.progressPosition) > TouristConfig.StuckMoveDistance then
		tourist.progressPosition = position
		tourist.progressAt = now()
		tourist.repaths = 0
		return false
	end
	local still = now() - tourist.progressAt
	if still >= TouristConfig.GiveUpSeconds then
		return true
	end
	if still >= TouristConfig.StuckSeconds * (tourist.repaths + 1) then
		tourist.repaths += 1
		goTo(tourist, tourist.target) -- новый путь от того места, где стоит
	end
	return false
end

local function updateOrbit(tourist: Tourist, position: Vector3)
	local adultModel = tourist.orbitTarget
	local adult = if adultModel then tourists[adultModel] else nil
	if closing or now() >= tourist.orbitUntil or not adult or adult.state == "Leave" then
		tourist.orbitTarget = nil
		advanceAfterStop(tourist)
		return
	end
	local adultPos = adult.root.Position
	local dist = flatDistance(position, adultPos)
	local radius = TouristConfig.ChildOrbitRadius
	if dist > radius * 2.5 then
		if checkStuck(tourist, position) then
			tourist.orbitTarget = nil
			startVisit(tourist)
			return
		end
		local dir = Vector3.new(position.X - adultPos.X, 0, position.Z - adultPos.Z)
		local unit = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		tourist.humanoid:MoveTo(adultPos + unit * radius)
		return
	end
	tourist.orbitAngle += tourist.orbitDir * TouristConfig.ChildOrbitAngularSpeed * TouristConfig.UpdateSeconds
	local offset = Vector3.new(math.cos(tourist.orbitAngle) * radius, 0, math.sin(tourist.orbitAngle) * radius)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { folder }
	local origin = Vector3.new(adultPos.X, position.Y, adultPos.Z)
	local hit = Workspace:Raycast(origin, offset, params)
	local targetPoint = origin + offset
	if hit then
		tourist.orbitDir = -tourist.orbitDir
		local safeDist = math.max(1, hit.Distance - 1)
		targetPoint = origin + offset.Unit * safeDist
	end
	if checkStuck(tourist, position) then
		tourist.orbitTarget = nil
		startVisit(tourist)
		return
	end
	tourist.humanoid:MoveTo(targetPoint)
end

local function updateTourist(tourist: Tourist)
	if tourist.computing then
		return
	end
	local position = tourist.root.Position
	if tourist.state == "Sit" then
		if closing then
			startLeaving(tourist)
			return
		end
		if now() >= tourist.sitUntil then
			unseat(tourist)
			advanceAfterStop(tourist)
		end
		return
	end

	if tourist.state == "Admire" then
		tourist.humanoid:MoveTo(position)
		if tourist.pointAt > 0 and now() >= tourist.pointAt then
			tourist.pointAt = 0
			setAnim(tourist, Anim.Point)
			tourist.admireUntil = now() + random:NextNumber(TouristConfig.PointMin, TouristConfig.PointMax)
		elseif now() >= tourist.admireUntil then
			advanceAfterStop(tourist)
		end
		return
	end

	if tourist.state == "Orbit" then
		updateOrbit(tourist, position)
		return
	end

	if tourist.state == "Leave" then
		-- Прошёл дверь или дошёл до точки снаружи — тает. Застрял надолго — тоже тает, где стоит.
		if passedDoor(tourist) or flatDistance(position, tourist.target) < TouristConfig.ReachDistance or not tourist.exit then
			fadeOut(tourist)
			return
		end
		if checkStuck(tourist, position) then
			fadeOut(tourist)
			return
		end
		if tourist.computing then
			return -- путь пересчитывается
		end
	elseif tourist.state == "GoBench" then
		local seat = tourist.benchSeat
		local stuck = checkStuck(tourist, position) or now() - tourist.walkStarted > TouristConfig.WalkTimeout
		if not seat or seat.occupant ~= tourist.model then
			releaseBench(tourist)
			startVisit(tourist)
			return
		end
		if flatDistance(position, tourist.target) < TouristConfig.ReachDistance then
			tourist.state = "Sit"
			tourist.sitUntil = now() + random:NextNumber(TouristConfig.SitMin, TouristConfig.SitMax)
			tourist.justSat = true
			tourist.humanoid:MoveTo(position)
			tourist.root.Anchored = true
			local scale = tourist.model:GetScale()
			local sitY = seat.bench.seatTopY + 0.55 * scale
			local seatPos = Vector3.new(seat.seatWorld.X, sitY, seat.seatWorld.Z)
			tourist.root.CFrame = CFrame.lookAt(seatPos, seatPos + seat.bench.lookDir)
			setAnim(tourist, Anim.Sit)
			return
		end
		if stuck then
			releaseBench(tourist)
			startVisit(tourist)
			return
		end
		if tourist.computing then
			return
		end
	else
		-- Walk: дошёл — или застрял (тогда смотрит, где стоит)
		local stuck = checkStuck(tourist, position) or now() - tourist.walkStarted > TouristConfig.WalkTimeout
		if flatDistance(position, tourist.target) < TouristConfig.ReachDistance or stuck then
			tourist.state = "Admire"
			tourist.admireUntil = now() + random:NextNumber(TouristConfig.AdmireMin, TouristConfig.AdmireMax)
			tourist.root.CFrame = CFrame.lookAt(position, Vector3.new(tourist.look.X, position.Y, tourist.look.Z))
			local atExhibit = tourist.atExhibit and not stuck
			if atExhibit and random:NextNumber() < TouristConfig.PhotoChance then
				tourist.pointAt = 0
				setAnim(tourist, Anim.Photo)
			else
				setAnim(tourist, Anim.Admire)
				if atExhibit and random:NextNumber() < TouristConfig.PointChance then
					local delay = math.min(1.5, (tourist.admireUntil - now()) * 0.4)
					tourist.pointAt = now() + delay
				else
					tourist.pointAt = 0
				end
			end
			tourist.humanoid:MoveTo(position)
			return
		end
		if tourist.computing then
			return
		end
	end
	local waypoint = tourist.waypoints[tourist.waypointIndex]
	if waypoint and flatDistance(waypoint.Position, position) < 2.5 then
		tourist.waypointIndex += 1
		waypoint = tourist.waypoints[tourist.waypointIndex]
	end
	tourist.humanoid:MoveTo(if waypoint then waypoint.Position else tourist.target)
end

---------------------------------------------------------------- появление

-- Внешний вид — TouristLooks (этап 5, блок F1): шляпы, волосы, очки, рюкзаки, фотоаппараты, разные цвета.
local function createTourist(isChild: boolean): Model?
	return TouristLooks.create(isChild)
end

local function spawnTourist(): boolean
	local entrances = WingService.entrances() -- входы сейчас: двери центра или наружные двери купленных крыльев
	if #entrances == 0 then
		return false
	end
	local isChild = (touristsToday + 1) % TouristConfig.ChildEvery == 0
	local model = createTourist(isChild)
	if not model then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return false
	end
	local speedMul = if isChild then TouristConfig.ChildSpeedMultiplier else 1
	local walkSpeed = TouristConfig.WalkSpeed * speedMul
	local leaveSpeed = TouristConfig.LeaveWalkSpeed * speedMul
	model.Name = "Tourist"
	ModelLibrary.setCollisionGroup(model, ModelLibrary.Groups.Tourists)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = walkSpeed
	model:PivotTo(pick(entrances).CFrame) -- через любой из 4 входов
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local tourist: Tourist = {
		model = model,
		humanoid = humanoid,
		root = root,
		isChild = isChild,
		walkSpeed = walkSpeed,
		leaveSpeed = leaveSpeed,
		state = "Walk",
		waypoints = {},
		waypointIndex = 1,
		target = root.Position,
		look = root.Position,
		atExhibit = false,
		pointAt = 0,
		admireUntil = 0,
		sitUntil = 0,
		justSat = false,
		benchSeat = nil,
		orbitTarget = nil,
		orbitUntil = 0,
		orbitAngle = 0,
		orbitDir = 1,
		visitsLeft = random:NextInteger(TouristConfig.VisitsMin, TouristConfig.VisitsMax),
		computing = false,
		pathToken = 0,
		walkStarted = now(),
		exit = nil,
		progressAt = now(),
		progressPosition = root.Position,
		repaths = 0,
	}
	tourists[model] = tourist
	startVisit(tourist)

	touristsToday += 1
	GameState.set(GameState.Attr.TouristsToday, touristsToday)
	ScoreService.addIncome(Config.Money.TicketPrice)
	showTicket(tourist)
	Audio.purchase(root, Config.Sounds.TicketVolume)
	return true
end

local function aliveCount(): number
	local count = 0
	for _ in tourists do
		count += 1
	end
	return count
end

-- Сколько туристов придёт сегодня: база + привлекательность экспонатов + за каждое открытое крыло (этап 5, блок B).
local function touristsForDay(appeal: number): number
	return TouristConfig.BasePerDay + math.floor(appeal * TouristConfig.PerAppeal) + WingService.openCount() * Config.Wings.Tourists
end

---------------------------------------------------------------- день

-- Откуда брать места для осмотра (экспонаты). Вызывается из GameLoop.
function TouristService.setAttractions(provider: () -> { Attraction })
	attractionsProvider = provider
end

-- appeal — сумма привлекательности купленных экспонатов (Мона Лиза входит в базу).
-- daySeconds — длина этого дня (растёт с каждым днём, решение 66).
function TouristService.beginDay(appeal: number, daySeconds: number)
	TouristService.endDay()
	closing = false
	touristsToday = 0
	GameState.set(GameState.Attr.TouristsToday, 0)
	local total = touristsForDay(appeal)
	-- Туристы приходят в первую часть дня, пока музей открыт (за 10 сек до ночи он закрывается)
	local openSeconds = math.max(1, daySeconds - TouristConfig.LeaveBeforeNightSeconds)
	local window = openSeconds * TouristConfig.SpawnWindow
	local interval = window / math.max(1, total)

	spawnThread = task.spawn(function()
		local spawned = 0
		while spawned < total do
			if aliveCount() < TouristConfig.MaxAlive then
				if spawnTourist() then
					spawned += 1
				end
			end
			task.wait(interval)
		end
	end)

	local accumulator = 0
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TouristConfig.UpdateSeconds then
			return
		end
		accumulator = 0
		for _, tourist in tourists do
			updateTourist(tourist)
		end
	end)
end

-- Музей закрывается (за несколько секунд до ночи): новые туристы не приходят, все идут к выходу.
function TouristService.closeMuseum()
	closing = true
	if spawnThread then
		pcall(task.cancel, spawnThread)
		spawnThread = nil
	end
	for _, tourist in tourists do
		if tourist.state ~= "Leave" then
			startLeaving(tourist)
		else
			tourist.humanoid.WalkSpeed = tourist.leaveSpeed
		end
	end
end

-- За секунду до ночи (FadeBeforeNightSeconds): все, кто ещё в музее, плавно тают — к ночи туристов нет.
function TouristService.fadeAll()
	closing = true
	if spawnThread then
		pcall(task.cancel, spawnThread)
		spawnThread = nil
	end
	local list = {}
	for _, tourist in tourists do
		table.insert(list, tourist)
	end
	for _, tourist in list do
		fadeOut(tourist)
	end
end

-- Ночь: кто не успел выйти, уходит сразу (ночью музей закрыт).
function TouristService.endDay()
	if spawnThread then
		pcall(task.cancel, spawnThread) -- поток мог уже закончиться сам
		spawnThread = nil
	end
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	for _, bench in benches do
		for _, seat in bench.seats do
			seat.occupant = nil
		end
	end
	for model in tourists do
		model:Destroy()
	end
	table.clear(tourists)
	for model in fading do
		model:Destroy()
	end
	table.clear(fading)
end

local function collectBenches(map: Instance)
	table.clear(benches)
	local props = map:FindFirstChild(MapSchema.Props)
	if not props then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local offset = TouristConfig.BenchSeatOffset
	local approachDist = TouristConfig.BenchApproachDistance
	for _, child in props:GetChildren() do
		if child.Name ~= MapSchema.Models.Bench or not child:IsA("PVInstance") then
			continue
		end
		local pivot = child:GetPivot()
		local floor = floorAt(pivot.Position)
		local hall = if floor then floor:GetAttribute("Hall") else nil
		if not (floor and typeof(hall) == "string") then
			continue -- скамейки комнаты охраны (Lobby) и прочих зон вне музея не берём
		end
		local floorY = floor.Position.Y + floor.Size.Y / 2
		local seatPart = child:FindFirstChild("Seat", true)
		local seatTopY = if seatPart and seatPart:IsA("BasePart")
			then seatPart.Position.Y + seatPart.Size.Y / 2
			else floorY + TouristConfig.BenchSeatHeight

		params.FilterDescendantsInstances = { child, folder }
		local function isSideOpen(side: number): boolean
			local probe = (pivot * CFrame.new(0, 0, side * approachDist)).Position
			if not floorAt(Vector3.new(probe.X, floorY, probe.Z)) then
				return false
			end
			local origin = Vector3.new(pivot.Position.X, floorY + 2, pivot.Position.Z)
			local delta = Vector3.new(probe.X - origin.X, 0, probe.Z - origin.Z)
			return Workspace:Raycast(origin, delta, params) == nil
		end

		local openSide: number? = if isSideOpen(-1) then -1 elseif isSideOpen(1) then 1 else nil
		if not openSide then
			continue
		end
		local rawDir = pivot.LookVector * (if openSide == -1 then 1 else -1)
		local flatDir = Vector3.new(rawDir.X, 0, rawDir.Z)
		local lookDir = if flatDir.Magnitude > 0.05 then flatDir.Unit else Vector3.new(0, 0, -1)

		local seats: { BenchSeat } = {}
		local bench: Bench = {
			model = child,
			hall = hall,
			floorY = floorY,
			seatTopY = seatTopY,
			lookDir = lookDir,
			seats = seats,
		}
		for i = 1, TouristConfig.BenchMaxOccupants do
			local x = if TouristConfig.BenchMaxOccupants == 1 then 0 else ((i - 1) * 2 - 1) * offset
			local seatWorld = (pivot * CFrame.new(x, 0, 0)).Position
			local approachWorld = (pivot * CFrame.new(x, 0, openSide * approachDist)).Position
			table.insert(seats, {
				bench = bench,
				seatWorld = seatWorld,
				approach = Vector3.new(approachWorld.X, floorY + 2, approachWorld.Z),
				occupant = nil,
			})
		end
		table.insert(benches, bench)
	end
end

function TouristService.init(map: Instance)
	local existing = Workspace:FindFirstChild(MapSchema.Tourists)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = MapSchema.Tourists
		created.Parent = Workspace
		folder = created
	end
	table.clear(floors)
	local geometry = map:FindFirstChild(MapSchema.Geometry)
	if geometry then
		for _, part in geometry:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Hall") ~= nil and part:GetAttribute("Wander") ~= false then
				table.insert(floors, part)
			end
		end
	end
	collectBenches(map)
	if not map:FindFirstChild(MapSchema.Entrances) then
		warn("[TouristService] На карте нет входов для туристов")
	end
end

return TouristService
