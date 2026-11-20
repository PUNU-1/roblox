-- Вор-Карманник: появляется у входа -> крадётся к Моне Лизе -> снимает её за 3 сек ->
-- бежит с картиной над головой к ближайшему выходу. Замечает охранника и убегает.
-- Пока один вор несёт картину (или снимает её), остальные загораживают путь охране.
-- Всё поведение считает сервер.

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
local PaintingService = require(Server:WaitForChild("PaintingService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local ThiefConfig = Config.Thief

local ThiefService = {}

-- Вор вынес картину из музея. GameLoop заканчивает ночь.
ThiefService.Escaped = Instance.new("BindableEvent")
-- Появился новый вор (model). CatchService вешает на него кнопку ареста.
ThiefService.Spawned = Instance.new("BindableEvent")

type Thief = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	path: Path,
	state: string, -- Approach | Steal | Escape | Flee | Block | Arrested | Escaped
	waypoints: { PathWaypoint },
	waypointIndex: number,
	pathTarget: Vector3?,
	pathTime: number,
	computing: boolean,
	stealStarted: number,
	fleeUntil: number,
	fleeTarget: Vector3,
	footsteps: Sound?,
	connections: { RBXScriptConnection },
}

local thieves: { [Model]: Thief } = {}
local folder: Folder
local entrances: { BasePart } = {}
local active = false
local spawnThread: thread? = nil
local updateConnection: RBXScriptConnection? = nil
local random = Random.new()

local bannerRemote = Remotes.get(Remotes.Names.Banner)

local MASK_STUB: { ModelLibrary.StubPart } = {
	{ size = Vector3.new(1.3, 1.3, 1.3), offset = CFrame.identity, color = ThiefConfig.Color, material = Enum.Material.Fabric },
	{ size = Vector3.new(1.0, 0.28, 0.05), offset = CFrame.new(0, 0.15, -0.66), color = Color3.fromHex("F5CDA8") },
	{ size = Vector3.new(0.16, 0.16, 0.04), offset = CFrame.new(-0.22, 0.15, -0.7), color = Color3.fromHex("111111") },
	{ size = Vector3.new(0.16, 0.16, 0.04), offset = CFrame.new(0.22, 0.15, -0.7), color = Color3.fromHex("111111") },
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

---------------------------------------------------------------- охранники рядом

local function nearestGuard(position: Vector3): (Vector3?, number)
	local bestPosition, bestDistance = nil, math.huge
	for _, player in RoleService.participants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local distance = flatDistance(root.Position, position)
			if distance < bestDistance then
				bestPosition, bestDistance = root.Position, distance
			end
		end
	end
	return bestPosition, bestDistance
end

-- Входы боковых залов работают, только когда зал открыт.
local function openEntrances(): { BasePart }
	local list = {}
	for _, entrance in entrances do
		if GameState.isHallOpen(entrance:GetAttribute("Hall")) then
			table.insert(list, entrance)
		end
	end
	return list
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

---------------------------------------------------------------- анимации и шаги

-- Сами движения рук и ног делает каждый клиент (NpcAnimator.client.luau).
-- Сервер только сообщает, что вор сейчас делает.
local ANIM_FOR_STATE: { [string]: string } = {
	Approach = GameState.ThiefAnim.Sneak,
	Flee = GameState.ThiefAnim.Run,
	Block = GameState.ThiefAnim.Run,
	Steal = GameState.ThiefAnim.Steal,
	Escape = GameState.ThiefAnim.Carry,
	Escaped = GameState.ThiefAnim.Carry,
	Arrested = GameState.ThiefAnim.Arrest,
}

local function syncAnim(thief: Thief)
	local anim = ANIM_FOR_STATE[thief.state] or GameState.ThiefAnim.Sneak
	if thief.model:GetAttribute(GameState.NpcAttr.AnimState) ~= anim then
		thief.model:SetAttribute(GameState.NpcAttr.AnimStateAt, now())
		thief.model:SetAttribute(GameState.NpcAttr.AnimState, anim)
	end
end

local function setupFootsteps(thief: Thief)
	local footsteps = Audio.create(Config.Sounds.ThiefStep, thief.root, Config.Sounds.StepVolume, true)
	if not footsteps then
		return
	end
	footsteps.RollOffMaxDistance = Config.Sounds.StepRollOff
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

---------------------------------------------------------------- поведение

local function speedFor(thief: Thief, base: number): number
	local slowedUntil = thief.model:GetAttribute("SlowedUntil")
	if typeof(slowedUntil) == "number" and slowedUntil > now() then
		return base * ThiefConfig.SlowMultiplier
	end
	return base
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

local function startEscape(thief: Thief)
	thief.state = "Escape"
	syncAnim(thief)
	bannerRemote:FireAllClients("THE PAINTING IS STOLEN!", "danger")
	Audio.playOnce(Config.Sounds.Alarm, nil, Config.Sounds.AlarmVolume)
end

local function updateThief(thief: Thief)
	if thief.state == "Arrested" or thief.state == "Escaped" then
		return
	end
	local model = thief.model
	local position = thief.root.Position
	local carrier = PaintingService.getCarrier()
	local stealer = PaintingService.getStealer()

	-- Выбираем, что делать
	if carrier == model then
		thief.state = "Escape"
	elseif carrier or (stealer and stealer ~= model) then
		thief.state = "Block"
	elseif thief.state == "Block" or thief.state == "Escape" then
		thief.state = "Approach"
	elseif thief.state == "Flee" and now() >= thief.fleeUntil then
		thief.state = "Approach"
	end

	if thief.state == "Approach" then
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
	if thief.state == "Approach" then
		local standPosition = PaintingService.standPosition()
		if flatDistance(position, standPosition) < ThiefConfig.StealReachDistance and PaintingService.tryStartSteal(model) then
			thief.state = "Steal"
			thief.stealStarted = now()
			stand(thief)
			local wall = PaintingService.wallPosition()
			thief.root.CFrame = CFrame.lookAt(position, Vector3.new(wall.X, position.Y, wall.Z))
		else
			moveTowards(thief, standPosition, speedFor(thief, ThiefConfig.SneakSpeed))
		end
	elseif thief.state == "Steal" then
		stand(thief)
		if not PaintingService.isOnWall() then
			PaintingService.cancelSteal(model)
			thief.state = "Block"
		elseif now() - thief.stealStarted >= ThiefConfig.StealSeconds then
			if PaintingService.take(model) then
				startEscape(thief)
			else
				PaintingService.cancelSteal(model)
				thief.state = "Approach"
			end
		end
	elseif thief.state == "Escape" then
		local exit = nearestEntrance(position)
		if exit then
			if flatDistance(position, exit) < ThiefConfig.EscapeReachDistance then
				thief.state = "Escaped"
				stand(thief)
				ThiefService.Escaped:Fire(model)
			else
				moveTowards(thief, exit, speedFor(thief, ThiefConfig.CarrySpeed))
			end
		end
	elseif thief.state == "Flee" then
		moveTowards(thief, thief.fleeTarget, speedFor(thief, ThiefConfig.RunSpeed))
	elseif thief.state == "Block" then
		-- Встаёт между охранником и тем, кто снимает или несёт картину
		local protected = carrier or stealer
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

local function createRig(): Model?
	local description = Instance.new("HumanoidDescription")
	local color = ThiefConfig.Color
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color
	description.RightLegColor = color
	return ModelLibrary.createRig(description)
end

local function aliveCount(): number
	local count = 0
	for _, thief in thieves do
		if thief.state ~= "Arrested" then
			count += 1
		end
	end
	return count
end

local function spawnThief(): boolean
	if #entrances == 0 then
		return false
	end
	local model = createRig()
	if not model then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return false
	end
	model.Name = "Thief"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = ThiefConfig.SneakSpeed
	humanoid:AddAccessory(ModelLibrary.accessory(MapSchema.Models.ThiefMask, MASK_STUB, "FaceCenterAttachment"))

	local open = openEntrances()
	if #open == 0 then
		model:Destroy()
		return false
	end
	local entrance = open[random:NextInteger(1, #open)]
	model:PivotTo(entrance.CFrame)
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil) -- воров двигает только сервер
	end)

	local thief: Thief = {
		model = model,
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 }),
		state = "Approach",
		waypoints = {},
		waypointIndex = 1,
		pathTarget = nil,
		pathTime = 0,
		computing = false,
		stealStarted = 0,
		fleeUntil = 0,
		fleeTarget = root.Position,
		footsteps = nil,
		connections = {},
	}
	thieves[model] = thief
	syncAnim(thief)
	setupFootsteps(thief)
	ScoreService.addSpawned()
	ThiefService.Spawned:Fire(model)
	return true
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
	PaintingService.cancelSteal(model)
	if PaintingService.getCarrier() == model then
		PaintingService.returnToWall()
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
	PaintingService.cancelSteal(model)
	if PaintingService.getCarrier() == model then
		PaintingService.returnToWall()
	end
	return true
end

---------------------------------------------------------------- ночь

local function spawnLoop(playerCount: number)
	local perNight = ThiefConfig.PerNight
	local total = perNight[math.clamp(playerCount, 1, #perNight)]
	local maxAlive = playerCount + ThiefConfig.MaxAliveExtra
	local nightStart = now()

	task.wait(random:NextNumber(ThiefConfig.FirstSpawnMin, ThiefConfig.FirstSpawnMax))
	local spawned = 0
	while active and spawned < total do
		if aliveCount() < maxAlive and spawnThief() then
			spawned += 1
			local fraction = math.clamp((now() - nightStart) / Config.Phases.NightSeconds, 0, 1)
			local interval = ThiefConfig.IntervalStart + (ThiefConfig.IntervalEnd - ThiefConfig.IntervalStart) * fraction
			local jitter = 1 + ThiefConfig.IntervalJitter * (random:NextNumber() * 2 - 1)
			task.wait(interval * jitter)
		else
			task.wait(1)
		end
	end
end

function ThiefService.beginNight(playerCount: number)
	ThiefService.endNight()
	active = true
	spawnThread = task.spawn(spawnLoop, playerCount)
	local accumulator = 0
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ThiefConfig.UpdateSeconds then
			return
		end
		accumulator = 0
		for _, thief in thieves do
			if thief.model.Parent then
				updateThief(thief)
			end
		end
	end)
end

function ThiefService.endNight()
	active = false
	if spawnThread then
		pcall(task.cancel, spawnThread)
		spawnThread = nil
	end
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	-- Сначала картина на стену, потом убираем воров, иначе она упадёт вместе с ними
	PaintingService.returnToWall()
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
	local entranceFolder = map:FindFirstChild(MapSchema.ThiefEntrances)
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
