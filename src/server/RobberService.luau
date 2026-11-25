-- Налёт (блок 4): вооружённое ограбление вместо одной волны воров (решает WaveService).
--  • Грабителей — игроки × 3, все входят через одну дверь (дальнюю от охраны), с сиреной и надписью ARMED ROBBERY!
--    Вверху у всех отсчёт POLICE: 60 (атрибут GameState PoliceAt). Пока идёт налёт, огнестрел можно достать.
--  • Стрелки (Gunner) прячутся за укрытиями (витрины, колонны, банкетки), выглядывают и стреляют по охране:
--    у бота шанс попадания (пистолет 40%, автомат 25%, на следующих налётах выше), присед, укрытие и дым мешают.
--    У каждого одна дымовая шашка. Охранника вплотную бьют прикладом.
--  • Хватальщики (Grabber) с дубинкой и мешком хватают экспонаты (как воры) и бегут к своей двери;
--    охранника рядом бьют дубинкой.
--  • У грабителя 100 здоровья. Убит — падает со звёздочками, роняет добычу и исчезает в облачке, денег нет.
--    Шокер — лежит 5 сек, его можно арестовать ($5).
--  • Полиция приехала — оставшиеся сдаются: 15 сек с поднятыми руками, арест (F) — $5, остальных забирает полиция.
--  • Мону Лизу вынесли — конец игры, как обычно (Escaped).
-- Всё считает сервер; руки и ноги двигают клиенты (NpcAnimator) по атрибуту AnimState.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local ThiefKinds = require(Server:WaitForChild("ThiefKinds"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local RoleService = require(Server:WaitForChild("RoleService"))
local HealthService = require(Server:WaitForChild("HealthService"))
local WeaponService = require(Server:WaitForChild("WeaponService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local HeistFx = require(Server:WaitForChild("HeistFx"))
local Audio = require(Server:WaitForChild("Audio"))

local Raid = Config.Raid
local Settings = Config.Robber
local Anim = GameState.ThiefAnim
local Attr = GameState.Attr
local ThiefAttr = GameState.ThiefAttr

local RobberService = {}

-- Грабитель вынес Мону Лизу (model). GameLoop заканчивает ночь.
RobberService.Escaped = Instance.new("BindableEvent")
-- Новый грабитель (model). CatchService вешает на него кнопку ареста (работает, пока он сдался или оглушён).
RobberService.Spawned = Instance.new("BindableEvent")

RobberService.ArrestableAttr = "Arrestable" -- атрибут модели: сейчас можно арестовать

type Cover = {
	position: Vector3, -- где сидит (на полу)
	peek: Vector3, -- откуда выглядывает (рядом или там же, если укрытие низкое)
	object: Vector3, -- центр укрытия
	hall: string,
}

type Robber = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	path: Path,
	role: string, -- Gunner | Grabber
	gun: string?, -- Pistol | Rifle у стрелков
	health: number,
	state: string, -- Move | Cover | Fight | Throw | Strike | Steal | Escape | Stunned | Surrender | Down | Arrested
	entrance: BasePart,
	waypoints: { PathWaypoint },
	waypointIndex: number,
	pathTarget: Vector3?,
	pathTime: number,
	computing: boolean,
	-- стрелок
	cover: Cover?,
	coverAt: number, -- когда искать новое укрытие
	peeking: boolean,
	phaseUntil: number, -- конец «выглядывает» / «прячется»
	nextShot: number,
	burstLeft: number,
	smokes: number,
	lastSeen: number, -- когда в последний раз видел охранника
	-- удар
	strikeStarted: number,
	strikeTarget: Player?,
	strikeHit: boolean,
	nextStrike: number,
	-- бросок шашки
	throwStarted: number,
	throwTarget: Vector3,
	thrown: boolean,
	-- хватальщик
	target: ExhibitService.Exhibit?,
	stealStarted: number,
	-- прочее
	stunUntil: number,
	surrenderUntil: number,
	downAt: number,
	connections: { RBXScriptConnection },
}

type Smoke = { center: Vector3, radius: number, untilTime: number, part: BasePart }

local robbers: { [Model]: Robber } = {}
local covers: { Cover } = {}
local reserved: { [Cover]: Robber } = {}
local smokes: { Smoke } = {}
local policeLights: { Instance } = {}
local folder: Folder
local entrances: { BasePart } = {}
local active = false
local raidIndex = 0 -- какой по счёту налёт в этом забеге (шанс попадания растёт)
local spawningUntil = 0 -- пока грабители налёта ещё входят, налёт не может кончиться
local updateConnection: RBXScriptConnection? = nil
local policeThread: thread? = nil
local random = Random.new()

local bannerRemote = Remotes.get(Remotes.Names.Banner)
local shotRemote = Remotes.get(Remotes.Names.ShotFx)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

---------------------------------------------------------------- охрана

type Guard = { player: Player, root: BasePart, head: BasePart, torso: Vector3 }

local function guards(): { Guard }
	local list = {}
	for _, player in RoleService.participants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local head = character and character:FindFirstChild("Head")
		if root and root:IsA("BasePart") and head and head:IsA("BasePart") and not RoleService.isDowned(player) then
			table.insert(list, { player = player, root = root, head = head, torso = root.Position + Vector3.new(0, 0.6, 0) })
		end
	end
	return list
end

local losParams: RaycastParams? = nil

-- Луч только по стенам и предметам: люди, воры и туристы не загораживают.
local function sightParams(): RaycastParams
	local params = losParams or RaycastParams.new()
	losParams = params
	local ignore: { Instance } = { folder }
	local tourists = Workspace:FindFirstChild(MapSchema.Tourists)
	if tourists then
		table.insert(ignore, tourists)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

local function clearLine(from: Vector3, to: Vector3): boolean
	return Workspace:Raycast(from, to - from, sightParams()) == nil
end

-- Проходит ли отрезок через облако дыма.
local function throughSmoke(from: Vector3, to: Vector3): boolean
	local time = now()
	local segment = to - from
	local length = segment.Magnitude
	if length < 0.01 then
		return false
	end
	local dir = segment / length
	for _, smoke in smokes do
		if smoke.untilTime > time then
			local t = math.clamp((smoke.center - from):Dot(dir), 0, length)
			if (from + dir * t - smoke.center).Magnitude < smoke.radius then
				return true
			end
		end
	end
	return false
end

local function eyeOf(robber: Robber): Vector3
	local head = robber.model:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else robber.root.Position + Vector3.new(0, 1.5, 0)
end

-- Ближайший охранник и видит ли его грабитель (голову или корпус).
local function threatFor(robber: Robber): (Guard?, boolean, number)
	local best, bestDistance, bestVisible = nil, math.huge, false
	local eye = eyeOf(robber)
	for _, guard in guards() do
		local distance = (guard.root.Position - robber.root.Position).Magnitude
		if distance <= Settings.SightRange then
			local visible = clearLine(eye, guard.head.Position) or clearLine(eye, guard.torso)
			-- Видимый важнее близкого невидимого
			local score = distance - (if visible then 1000 else 0)
			local bestScore = bestDistance - (if bestVisible then 1000 else 0)
			if score < bestScore then
				best, bestDistance, bestVisible = guard, distance, visible
			end
		end
	end
	return best, bestVisible, bestDistance
end

---------------------------------------------------------------- анимации

local function animFor(robber: Robber): string
	local state = robber.state
	if state == "Arrested" then
		return Anim.Arrest
	elseif state == "Down" then
		return Anim.Knockout
	elseif state == "Stunned" then
		return Anim.Stunned
	elseif state == "Surrender" then
		return Anim.Surrender
	elseif state == "Strike" then
		return Anim.Strike
	elseif state == "Throw" then
		return Anim.Throw
	elseif state == "Steal" then
		return Anim.Steal
	elseif state == "Escape" then
		return Anim.Carry
	elseif state == "Cover" then
		return if robber.peeking then Anim.Aim else Anim.Cover
	elseif state == "Fight" then
		return Anim.Aim
	elseif robber.role == "Grabber" then
		return Anim.Run
	end
	return Anim.Advance
end

local function syncAnim(robber: Robber)
	local anim = animFor(robber)
	if robber.model:GetAttribute(GameState.NpcAttr.AnimState) ~= anim then
		robber.model:SetAttribute(GameState.NpcAttr.AnimStateAt, now())
		robber.model:SetAttribute(GameState.NpcAttr.AnimState, anim)
	end
end

local function setArrestable(robber: Robber, value: boolean)
	robber.model:SetAttribute(RobberService.ArrestableAttr, value)
end

---------------------------------------------------------------- движение

local function computePath(robber: Robber, target: Vector3)
	robber.computing = true
	task.spawn(function()
		local ok = pcall(function()
			robber.path:ComputeAsync(robber.root.Position, target)
		end)
		robber.computing = false
		if not robbers[robber.model] then
			return
		end
		if ok and robber.path.Status == Enum.PathStatus.Success then
			robber.waypoints = robber.path:GetWaypoints()
			robber.waypointIndex = 2
		else
			robber.waypoints = {}
			robber.waypointIndex = 1
		end
		robber.pathTarget = target
		robber.pathTime = now()
	end)
end

local function speedFor(robber: Robber, base: number): number
	local slowed = robber.model:GetAttribute("SlowedUntil") -- лазерная сетка (TrapService)
	if typeof(slowed) == "number" and slowed > now() then
		return base * Config.Thief.SlowMultiplier
	end
	return base
end

local function moveTowards(robber: Robber, target: Vector3, speed: number)
	robber.humanoid.WalkSpeed = speedFor(robber, speed)
	local thief = Config.Thief
	local needPath = robber.pathTarget == nil
		or (robber.pathTarget :: Vector3 - target).Magnitude > thief.PathRecomputeDistance
		or now() - robber.pathTime > thief.PathRecomputeSeconds
	if needPath and not robber.computing then
		computePath(robber, target)
	end
	local waypoint = robber.waypoints[robber.waypointIndex]
	if waypoint and flatDistance(waypoint.Position, robber.root.Position) < thief.WaypointReachDistance then
		robber.waypointIndex += 1
		waypoint = robber.waypoints[robber.waypointIndex]
	end
	robber.humanoid:MoveTo(if waypoint then waypoint.Position else target)
end

local function stand(robber: Robber)
	robber.humanoid:MoveTo(robber.root.Position)
end

local function face(robber: Robber, point: Vector3)
	local position = robber.root.Position
	if flatDistance(position, point) > 0.1 then
		robber.root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
	end
end

---------------------------------------------------------------- укрытия

-- Места за укрытиями: у каждой витрины, колонны, банкетки, статуи — по 4 стороны. Считается один раз.
local function buildCovers(map: Instance)
	local objects: { { cframe: CFrame, size: Vector3 } } = {}
	local props = map:FindFirstChild(MapSchema.Props)
	if props then
		for _, child in props:GetDescendants() do
			if child:IsA("Model") and child.Parent and not child.Parent:IsA("Model") then
				local ok, cframe, size = pcall(function()
					return child:GetBoundingBox()
				end)
				if ok then
					table.insert(objects, { cframe = cframe, size = size })
				end
			end
		end
	end
	for _, part in map:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "ColumnShaft" then
			-- Колонна лежит цилиндром на боку: её высота — Size.X
			table.insert(objects, { cframe = CFrame.new(part.Position), size = Vector3.new(part.Size.Y, part.Size.X, part.Size.Z) })
		end
	end
	local overlap = OverlapParams.new()
	overlap.RespectCanCollide = true
	for _, object in objects do
		local size = object.size
		local footMin, footMax = math.min(size.X, size.Z), math.max(size.X, size.Z)
		local bottom = object.cframe.Position.Y - size.Y / 2
		if size.Y >= 1.8 and footMin >= 1 and footMax <= 12 and bottom < 2 then
			local center = object.cframe.Position
			local right = flat(object.cframe.RightVector)
			local look = flat(object.cframe.LookVector)
			right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
			look = if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis
			local sides = {
				{ normal = right, half = size.X / 2, across = look, width = size.Z / 2 },
				{ normal = -right, half = size.X / 2, across = look, width = size.Z / 2 },
				{ normal = look, half = size.Z / 2, across = right, width = size.X / 2 },
				{ normal = -look, half = size.Z / 2, across = right, width = size.X / 2 },
			}
			for _, side in sides do
				local point = Vector3.new(center.X, 0, center.Z) + side.normal * (side.half + Settings.CoverGap)
				local floor = HeistFx.floorAt(point + Vector3.new(0, 3, 0))
				if floor then
					local blocked = #Workspace:GetPartBoundsInBox(CFrame.new(floor + Vector3.new(0, 2.6, 0)), Vector3.new(1.4, 3, 1.4), overlap) > 0
					if not blocked then
						local _, hall = HeistFx.areaAt(floor)
						-- Низкое укрытие — выглядывает, встав; высокое — шагнув вбок
						local peek = floor
						if size.Y > 4.2 then
							local offset = side.across * (side.width + 1.4) * (if random:NextNumber() < 0.5 then -1 else 1)
							peek = floor + offset
						end
						table.insert(covers, { position = floor, peek = peek, object = Vector3.new(center.X, floor.Y, center.Z), hall = hall })
					end
				end
			end
		end
	end
end

-- Укрытие для стрелка: охранник по ту сторону укрытия, не слишком близко и не слишком далеко, не занято другим.
local function chooseCover(robber: Robber, threat: Vector3): Cover?
	local best, bestScore = nil, math.huge
	local position = robber.root.Position
	for _, cover in covers do
		local holder = reserved[cover]
		if (holder == nil or holder == robber) and GameState.isHallOpen(cover.hall) then
			local fromRobber = flatDistance(cover.position, position)
			local toThreat = flatDistance(cover.position, threat)
			if fromRobber <= Settings.CoverSearchRadius and toThreat >= Settings.CoverMinDistance and toThreat <= Settings.CoverMaxDistance then
				local toObject = flat(cover.object - cover.position)
				local toGuard = flat(threat - cover.position)
				if toObject.Magnitude > 0.1 and toGuard.Magnitude > 0.1 and toObject.Unit:Dot(toGuard.Unit) >= 0.55 then
					local score = fromRobber + math.abs(toThreat - 30) * 0.6
					if score < bestScore then
						best, bestScore = cover, score
					end
				end
			end
		end
	end
	return best
end

local function setCover(robber: Robber, cover: Cover?)
	if robber.cover then
		reserved[robber.cover] = nil
	end
	robber.cover = cover
	if cover then
		reserved[cover] = robber
	end
end

---------------------------------------------------------------- стрельба, дым, удар

local function chanceFor(robber: Robber, guard: Guard, eye: Vector3): number
	local gun = (Settings.Guns :: any)[robber.gun or "Pistol"]
	local chance = math.min(Settings.MaxChance, gun.Chance + Settings.ChanceGrowth * math.max(0, raidIndex - 1))
	local player = guard.player
	if player:GetAttribute(GameState.PlayerAttr.Crouch) == true then
		chance *= Settings.CrouchFactor
	end
	if (tonumber(player:GetAttribute(GameState.PlayerAttr.Lean)) or 0) ~= 0 then
		chance *= Settings.LeanFactor
	end
	-- Корпус за укрытием, видна только голова — попасть труднее
	if not clearLine(eye, guard.torso) then
		chance *= Settings.CoverFactor
	end
	if throughSmoke(eye, guard.head.Position) then
		chance *= Settings.SmokeFactor
	end
	if (guard.root.Position - robber.root.Position).Magnitude > Settings.FarDistance then
		chance *= Settings.FarFactor
	end
	return chance
end

local function muzzleOf(robber: Robber): Vector3
	local gear = robber.model:FindFirstChild("Gear")
	local held = gear and gear:FindFirstChild("Held")
	local root = held and held:FindFirstChild("Root")
	local muzzle = root and root:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return eyeOf(robber)
end

local function shootAt(robber: Robber, guard: Guard)
	local gun = (Settings.Guns :: any)[robber.gun or "Pistol"]
	local eye = eyeOf(robber)
	local from = muzzleOf(robber)
	local hit = random:NextNumber() < chanceFor(robber, guard, eye)
	local target: Vector3
	if hit then
		target = guard.torso + Vector3.new(random:NextNumber(-0.4, 0.4), random:NextNumber(-0.5, 0.8), random:NextNumber(-0.4, 0.4))
		HealthService.damage(guard.player, gun.Damage, eye)
	else
		-- Промах пролетает рядом и бьёт в стену за охранником
		local miss = guard.head.Position + Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.6, 1), random:NextNumber(-1, 1)).Unit * Settings.MissSpread
		local dir = (miss - from).Unit
		local result = Workspace:Raycast(from, dir * Settings.ShootRange * 1.5, sightParams())
		target = if result then result.Position else from + dir * Settings.ShootRange
	end
	shotRemote:FireAllClients(robber.model, robber.gun or "Pistol", from, { target }, { hit })
end

-- Дымовое облако на полу: густой серый дым, закрывает вид и мешает стрелкам целиться.
local function spawnSmoke(at: Vector3)
	local part = Instance.new("Part")
	part.Name = "SmokeCloud"
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0))
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(205, 208, 212), Color3.fromRGB(150, 155, 162))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, Settings.SmokeRadius * 1.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(4, 6)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 30)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.Rate = 28
	emitter.Parent = part
	Audio.playOnce(Config.Sounds.Smoke, part, Config.Sounds.SmokeVolume, 3, Config.Sounds.SmokeSpeed)
	table.insert(smokes, { center = at + Vector3.new(0, 3, 0), radius = Settings.SmokeRadius, untilTime = now() + Settings.SmokeSeconds, part = part })
	task.delay(Settings.SmokeSeconds, function()
		emitter.Rate = 0
		Debris:AddItem(part, 7)
	end)
end

-- Шашка летит по дуге из руки к точке, падает и дымит.
local function throwSmoke(robber: Robber)
	local hand = robber.model:FindFirstChild("RightHand")
	local from = if hand and hand:IsA("BasePart") then hand.Position else eyeOf(robber)
	local to = robber.throwTarget
	local built = WeaponModels.build("Smoke")
	WeaponModels.anchor(built, CFrame.new(from))
	built.model.Parent = folder
	-- Шашка на жилете пропадает: брошена
	local onVest = robber.model:FindFirstChild("Grenade")
	if onVest then
		onVest:Destroy()
	end
	local flight = Settings.SmokeFlightSeconds
	task.spawn(function()
		local started = os.clock()
		while true do
			local t = math.clamp((os.clock() - started) / flight, 0, 1)
			local position = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 5, 0)
			WeaponModels.anchor(built, CFrame.new(position) * CFrame.Angles(t * 9, t * 5, 0))
			if t >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		WeaponModels.anchor(built, CFrame.new(to + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2))
		if active then
			spawnSmoke(to)
		end
		Debris:AddItem(built.model, Settings.SmokeSeconds + 4)
	end)
end

-- Удар дубинкой (хватальщик) или прикладом (стрелок): охранник спереди вплотную.
local function guardInReach(robber: Robber): Player?
	local look = flat(robber.root.CFrame.LookVector)
	for _, guard in guards() do
		if math.abs(guard.root.Position.Y - robber.root.Position.Y) > 5 then
			continue
		end
		local offset = flat(guard.root.Position - robber.root.Position)
		if offset.Magnitude <= Settings.BatonRange and (offset.Magnitude < 0.5 or look.Unit:Dot(offset.Unit) > 0.2) then
			return guard.player
		end
	end
	return nil
end

local function startStrike(robber: Robber, player: Player)
	robber.state = "Strike"
	robber.strikeStarted = now()
	robber.strikeTarget = player
	robber.strikeHit = false
	robber.nextStrike = now() + Settings.BatonCooldown
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		face(robber, root.Position)
	end
	stand(robber)
end

-- Возвращает true, пока удар идёт.
local function updateStrike(robber: Robber): boolean
	local elapsed = now() - robber.strikeStarted
	if not robber.strikeHit and elapsed >= Settings.BatonWindup then
		robber.strikeHit = true
		local player = robber.strikeTarget
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		-- Охранник мог отскочить, пока грабитель замахивался
		if player and root and root:IsA("BasePart") and (root.Position - robber.root.Position).Magnitude <= Settings.BatonRange + 1.5 then
			if HealthService.damage(player, Settings.BatonDamage, robber.root.Position) then
				Audio.playOnce(Config.Sounds.Baton, root, Config.Sounds.BatonVolume, nil, Config.Sounds.BatonSpeed)
			end
		end
	end
	if elapsed < Settings.BatonSeconds then
		stand(robber)
		return true
	end
	robber.strikeTarget = nil
	return false
end

---------------------------------------------------------------- стрелок

local function updateGunner(robber: Robber)
	local time = now()
	local guard, visible, distance = threatFor(robber)
	if visible then
		robber.lastSeen = time
	end
	-- Охранник вплотную — бьёт прикладом
	if guard and time >= robber.nextStrike then
		local player = guardInReach(robber)
		if player then
			startStrike(robber, player)
			return
		end
	end
	-- Бросок шашки: видит охранника недалеко — иногда кидает дым ему под ноги
	if guard and visible and robber.smokes > 0 and distance <= Settings.SmokeRange and random:NextNumber() < Settings.SmokeChance * Settings.UpdateSeconds then
		robber.smokes -= 1
		robber.state = "Throw"
		robber.throwStarted = time
		robber.throwTarget = Vector3.new(guard.root.Position.X, guard.root.Position.Y - 2.5, guard.root.Position.Z)
		robber.thrown = false
		face(robber, guard.root.Position)
		stand(robber)
		return
	end
	local threatPosition = if guard then guard.root.Position else nil
	if not threatPosition then
		-- Охраны не видно — идут к Моне Лизе (туда, куда пойдут хватальщики)
		local main = ExhibitService.main()
		threatPosition = if main then main.stand else robber.entrance.Position
	end
	-- Укрытие: пора искать новое, или охранник обошёл и видит грабителя, пока тот прячется
	if not robber.cover or time >= robber.coverAt then
		local previous = robber.cover
		setCover(robber, chooseCover(robber, threatPosition :: Vector3))
		robber.coverAt = time + Settings.CoverRescanSeconds
		if robber.cover ~= previous then
			robber.state = "Move" -- новое укрытие: идти к нему по пути, а не напрямик
			robber.peeking = false
		end
	end
	local cover = robber.cover
	if cover then
		local spot = if robber.peeking then cover.peek else cover.position
		if robber.state ~= "Cover" and flatDistance(robber.root.Position, cover.position) > 2.5 then
			robber.state = "Move"
			moveTowards(robber, cover.position, Settings.WalkSpeed)
			return
		end
		if robber.state ~= "Cover" then
			robber.state = "Cover"
			robber.peeking = false
			robber.phaseUntil = time + Settings.HideSeconds * random:NextNumber(0.6, 1.2)
		end
		-- Подойти к своей точке (сесть или выглянуть) — короткий шаг без поиска пути
		if flatDistance(robber.root.Position, spot) > 1 then
			robber.humanoid.WalkSpeed = Settings.WalkSpeed * 0.6
			robber.humanoid:MoveTo(spot)
		else
			stand(robber)
		end
		if guard then
			face(robber, guard.root.Position)
		end
		if time >= robber.phaseUntil then
			if not robber.peeking and guard and visible and clearLine(guard.head.Position, eyeOf(robber)) then
				robber.coverAt = time -- спрятался, а его всё равно видно: укрытие не работает — искать другое
			end
			robber.peeking = not robber.peeking
			robber.phaseUntil = time + (if robber.peeking then Settings.PeekSeconds else Settings.HideSeconds) * random:NextNumber(0.8, 1.3)
			robber.burstLeft = 0
		end
		-- Давно никого не видит — двигается ближе к охране
		if time - robber.lastSeen > 6 and not visible then
			robber.coverAt = math.min(robber.coverAt, time + 0.5)
		end
		if robber.peeking and guard and visible and distance <= Settings.ShootRange then
			local gun = (Settings.Guns :: any)[robber.gun or "Pistol"]
			if time >= robber.nextShot then
				shootAt(robber, guard)
				if gun.Burst then
					-- Автомат стреляет короткими очередями
					if robber.burstLeft <= 0 then
						robber.burstLeft = gun.Burst
					end
					robber.burstLeft -= 1
					robber.nextShot = time + (if robber.burstLeft > 0 then gun.Interval else gun.BurstPause * random:NextNumber(0.8, 1.2))
				else
					robber.nextShot = time + gun.Interval * random:NextNumber(0.9, 1.3)
				end
			end
		end
		return
	end
	-- Укрытия нет: видит охранника на расстоянии выстрела — стоит и стреляет, иначе идёт к нему
	if guard and visible and distance <= Settings.ShootRange then
		robber.state = "Fight"
		stand(robber)
		face(robber, guard.root.Position)
		local gun = (Settings.Guns :: any)[robber.gun or "Pistol"]
		if time >= robber.nextShot then
			shootAt(robber, guard)
			robber.nextShot = time + (if gun.Burst then gun.BurstPause * 0.5 else gun.Interval)
		end
	else
		robber.state = "Move"
		moveTowards(robber, threatPosition :: Vector3, Settings.WalkSpeed)
	end
end

---------------------------------------------------------------- хватальщик

-- Вынес добычу за дверь: Мона Лиза — конец игры, дешёвый экспонат пропадает. Возвращает true, если грабителя уже нет.
local function getAway(robber: Robber, carried: ExhibitService.Exhibit): boolean
	if carried.isMain then
		robber.state = "Arrested" -- стоит на месте, пока GameLoop заканчивает ночь
		stand(robber)
		RobberService.Escaped:Fire(robber.model)
		return false
	end
	bannerRemote:FireAllClients(("THE %s IS GONE!"):format(string.upper(carried.title)), "danger")
	ExhibitService.lose(carried)
	RobberService.remove(robber.model)
	return true
end

local function updateGrabber(robber: Robber)
	local time = now()
	local model = robber.model
	local carried = ExhibitService.getCarried(model)
	if carried then
		robber.state = "Escape"
		local exit = robber.entrance.Position
		if flatDistance(robber.root.Position, exit) < Config.Thief.EscapeReachDistance then
			getAway(robber, carried)
			return
		end
		moveTowards(robber, exit, Settings.CarrySpeed)
		return
	end
	-- Охранник рядом — дубинкой
	if time >= robber.nextStrike and robber.state ~= "Steal" then
		local player = guardInReach(robber)
		if player then
			startStrike(robber, player)
			return
		end
	end
	if robber.state == "Steal" then
		stand(robber)
		local target = robber.target
		if not target or target.stealer ~= model then
			ExhibitService.cancelSteal(model)
			robber.state = "Move"
		elseif time - robber.stealStarted >= Config.Thief.StealSeconds then
			if ExhibitService.take(target, model) then
				robber.state = "Escape"
				bannerRemote:FireAllClients(("THE %s IS STOLEN!"):format(string.upper(target.title)), "danger")
				Audio.alarm()
			else
				ExhibitService.cancelSteal(model)
				robber.state = "Move"
			end
		end
		return
	end
	robber.state = "Move"
	local target = robber.target
	if not target or not ExhibitService.isFree(target, model) then
		local points = {}
		for _, guard in guards() do
			table.insert(points, guard.root.Position)
		end
		target = ExhibitService.pickTarget(model, nil, points)
		robber.target = target
	end
	if not target then
		stand(robber)
		return
	end
	if flatDistance(robber.root.Position, target.stand) < Config.Thief.StealReachDistance and ExhibitService.tryStartSteal(target, model) then
		robber.state = "Steal"
		robber.stealStarted = time
		stand(robber)
		face(robber, target.look)
		return
	end
	moveTowards(robber, target.stand, Settings.RunSpeed)
end

---------------------------------------------------------------- общее

local function dropLoot(robber: Robber)
	ExhibitService.cancelSteal(robber.model)
	local carried = ExhibitService.getCarried(robber.model)
	if carried then
		ExhibitService.returnHome(carried)
	end
end

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
	local tween = TweenService:Create(cloud, TweenInfo.new(Config.Effects.PoofSeconds), { Size = Vector3.new(size, size, size), Transparency = 1 })
	tween.Completed:Once(function()
		cloud:Destroy()
	end)
	tween:Play()
end

local function updateRobber(robber: Robber)
	local state = robber.state
	local time = now()
	if state == "Arrested" or state == "Down" then
		return
	elseif state == "Surrender" then
		stand(robber)
		return
	elseif state == "Stunned" then
		stand(robber)
		if time >= robber.stunUntil then
			setArrestable(robber, false)
			robber.state = "Move"
		end
		syncAnim(robber)
		return
	elseif state == "Strike" then
		if updateStrike(robber) then
			syncAnim(robber)
			return
		end
		robber.state = "Move"
	elseif state == "Throw" then
		local elapsed = time - robber.throwStarted
		if not robber.thrown and elapsed >= Settings.SmokeThrowSeconds * 0.6 then
			robber.thrown = true
			throwSmoke(robber)
		end
		if elapsed < Settings.SmokeThrowSeconds then
			stand(robber)
			syncAnim(robber)
			return
		end
		robber.state = "Move"
	end
	if robber.role == "Gunner" then
		updateGunner(robber)
	else
		updateGrabber(robber)
	end
	if robbers[robber.model] then
		syncAnim(robber)
	end
end

---------------------------------------------------------------- внешний вид

local function sizeOf(model: Model, partName: string): Vector3
	local part = model:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part.Size else Vector3.new(1, 1, 1)
end

-- Балаклава: вязаная маска на всю голову с прорезями для глаз и рта, рубчик у шеи; у хватальщика — красная полоса.
local function balaclava(model: Model, colors: any, stripe: Color3?)
	local h = sizeOf(model, "Head")
	local skin = Settings.Colors.Skin
	local specs: { ModelLibrary.StubPart } = {
		{ name = "Mask", size = Vector3.new(h.X * 1.08, h.Y * 1.08, h.Z * 1.08), offset = CFrame.new(0, h.Y * 0.03, 0), color = colors.Mask, material = Enum.Material.Fabric, sphere = true },
		{ name = "Top", size = Vector3.new(h.X * 0.9, h.Y * 0.3, h.Z * 0.9), offset = CFrame.new(0, h.Y * 0.46, 0), color = colors.Mask, material = Enum.Material.Fabric, sphere = true },
		{ name = "EyeSlit", size = Vector3.new(h.X * 0.66, h.Y * 0.18, 0.06), offset = CFrame.new(0, h.Y * 0.1, -h.Z * 0.53), color = skin },
		{ name = "EyeL", size = Vector3.new(h.X * 0.12, h.Y * 0.12, 0.04), offset = CFrame.new(-h.X * 0.17, h.Y * 0.1, -h.Z * 0.56), color = Color3.fromHex("141414") },
		{ name = "EyeR", size = Vector3.new(h.X * 0.12, h.Y * 0.12, 0.04), offset = CFrame.new(h.X * 0.17, h.Y * 0.1, -h.Z * 0.56), color = Color3.fromHex("141414") },
		{ name = "Brows", size = Vector3.new(h.X * 0.6, h.Y * 0.05, 0.05), offset = CFrame.new(0, h.Y * 0.21, -h.Z * 0.555) * CFrame.Angles(0, 0, 0), color = colors.Mask:Lerp(Color3.new(0, 0, 0), 0.3) },
		{ name = "Mouth", size = Vector3.new(h.X * 0.28, h.Y * 0.1, 0.06), offset = CFrame.new(0, -h.Y * 0.24, -h.Z * 0.53), color = skin },
		{ name = "Rim", size = Vector3.new(0.18, h.X * 0.95, h.Z * 0.95), offset = CFrame.new(0, -h.Y * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), color = colors.Mask:Lerp(Color3.new(1, 1, 1), 0.08), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
	}
	if stripe then
		table.insert(specs, { name = "Stripe", size = Vector3.new(h.X * 1.1, h.Y * 0.12, h.Z * 1.1), offset = CFrame.new(0, h.Y * 0.32, 0), color = stripe, material = Enum.Material.Fabric })
	end
	ThiefKinds.attach(model, "Head", if stripe then "robber_balaclava_red_01" else "robber_balaclava_01", specs, CFrame.identity)
end

-- Тактический жилет: пластины, подсумки, лямки; у стрелка — рация и дымовая шашка на груди.
local function vest(model: Model, colors: any, gunner: boolean)
	local t = sizeOf(model, "UpperTorso")
	local front = -t.Z * 0.5 - 0.1
	local back = t.Z * 0.5 + 0.1
	local pouch = colors.Vest:Lerp(Color3.new(0, 0, 0), 0.25)
	local specs: { ModelLibrary.StubPart } = {
		{ name = "Front", size = Vector3.new(t.X * 0.88, t.Y * 0.86, 0.22), offset = CFrame.new(0, -t.Y * 0.03, front), color = colors.Vest, material = Enum.Material.Fabric },
		{ name = "Back", size = Vector3.new(t.X * 0.9, t.Y * 0.88, 0.22), offset = CFrame.new(0, -t.Y * 0.02, back), color = colors.Vest, material = Enum.Material.Fabric },
		{ name = "StrapL", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.26), offset = CFrame.new(-t.X * 0.27, t.Y * 0.47, 0), color = pouch, material = Enum.Material.Fabric },
		{ name = "StrapR", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.26), offset = CFrame.new(t.X * 0.27, t.Y * 0.47, 0), color = pouch, material = Enum.Material.Fabric },
		{ name = "SideL", size = Vector3.new(0.12, t.Y * 0.44, t.Z * 1.22), offset = CFrame.new(-t.X * 0.5 - 0.05, -t.Y * 0.18, 0), color = pouch, material = Enum.Material.Fabric },
		{ name = "SideR", size = Vector3.new(0.12, t.Y * 0.44, t.Z * 1.22), offset = CFrame.new(t.X * 0.5 + 0.05, -t.Y * 0.18, 0), color = pouch, material = Enum.Material.Fabric },
	}
	for index = -1, 1 do
		table.insert(specs, { name = "Pouch", size = Vector3.new(t.X * 0.22, t.Y * 0.3, 0.2), offset = CFrame.new(index * t.X * 0.26, -t.Y * 0.24, front - 0.19), color = pouch, material = Enum.Material.Fabric })
		table.insert(specs, { name = "Flap", size = Vector3.new(t.X * 0.23, 0.06, 0.22), offset = CFrame.new(index * t.X * 0.26, -t.Y * 0.08, front - 0.19), color = colors.Vest, material = Enum.Material.Fabric })
	end
	if gunner then
		table.insert(specs, { name = "Radio", size = Vector3.new(0.22, 0.36, 0.14), offset = CFrame.new(t.X * 0.27, t.Y * 0.18, front - 0.17), color = Color3.fromHex("141518") })
		table.insert(specs, { name = "Antenna", size = Vector3.new(0.04, 0.4, 0.04), offset = CFrame.new(t.X * 0.32, t.Y * 0.45, front - 0.17), color = Color3.fromHex("141518") })
	else
		-- Хватальщик: светлый жилет с большими карманами
		table.insert(specs, { name = "PocketL", size = Vector3.new(t.X * 0.3, t.Y * 0.3, 0.12), offset = CFrame.new(-t.X * 0.24, t.Y * 0.15, front - 0.15), color = pouch, material = Enum.Material.Fabric })
		table.insert(specs, { name = "PocketR", size = Vector3.new(t.X * 0.3, t.Y * 0.3, 0.12), offset = CFrame.new(t.X * 0.24, t.Y * 0.15, front - 0.15), color = pouch, material = Enum.Material.Fabric })
	end
	ThiefKinds.attach(model, "UpperTorso", if gunner then "robber_vest_01" else "robber_vest_light_01", specs, CFrame.identity)
	if gunner then
		-- Дымовая шашка на груди слева (пропадает, когда брошена)
		local grenade = WeaponModels.build("Smoke")
		local torso = model:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			WeaponModels.weld(grenade, torso, torso.CFrame * CFrame.new(-t.X * 0.27, t.Y * 0.16, front - 0.3))
			grenade.model.Name = "Grenade"
			grenade.model.Parent = model
		end
	end
end

-- Мешок для добычи за спиной хватальщика, со знаком $ и завязкой.
local function lootBag(model: Model)
	local t = sizeOf(model, "UpperTorso")
	local bag = ThiefKinds.attach(model, "UpperTorso", "robber_bag_01", {
		{ name = "Sack", size = Vector3.new(t.X * 0.95, t.Y * 1.35, 1.3), offset = CFrame.new(0, t.Y * 0.05, t.Z * 0.5 + 0.75), color = Color3.fromHex("B89B6A"), material = Enum.Material.Fabric, sphere = true },
		{ name = "Neck", size = Vector3.new(0.5, 0.6, 0.5), offset = CFrame.new(0, t.Y * 0.78, t.Z * 0.5 + 0.7), color = Color3.fromHex("A0845A"), material = Enum.Material.Fabric },
		{ name = "Tie", size = Vector3.new(0.12, 0.62, 0.62), offset = CFrame.new(0, t.Y * 0.68, t.Z * 0.5 + 0.7) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromHex("6B4A2E"), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "StrapL", size = Vector3.new(0.16, t.Y * 1.0, 0.08), offset = CFrame.new(-t.X * 0.3, 0, -t.Z * 0.5 - 0.06), color = Color3.fromHex("6B4A2E"), material = Enum.Material.Fabric },
		{ name = "StrapR", size = Vector3.new(0.16, t.Y * 1.0, 0.08), offset = CFrame.new(t.X * 0.3, 0, -t.Z * 0.5 - 0.06), color = Color3.fromHex("6B4A2E"), material = Enum.Material.Fabric },
	}, CFrame.identity)
	local sack = bag and bag:FindFirstChild("Sack")
	if sack and sack:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "$"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromHex("3FB56B")
		label.Parent = gui
		gui.Parent = sack
	end
end

local function gloves(model: Model)
	for _, hand in { "LeftHand", "RightHand" } do
		local g = sizeOf(model, hand)
		ThiefKinds.attach(model, hand, "robber_glove_01", {
			{ name = "Glove", size = Vector3.new(g.X * 1.18, g.Y * 1.3, g.Z * 1.18), offset = CFrame.identity, color = Color3.fromHex("141518"), material = Enum.Material.Leather },
		}, CFrame.identity)
	end
	for _, foot in { "LeftFoot", "RightFoot" } do
		local f = sizeOf(model, foot)
		ThiefKinds.attach(model, foot, "robber_boot_01", {
			{ name = "Boot", size = Vector3.new(f.X * 1.12, f.Y * 1.2, f.Z * 1.15), offset = CFrame.new(0, 0, -f.Z * 0.05), color = Color3.fromHex("1C1A18"), material = Enum.Material.Leather },
		}, CFrame.identity)
	end
end

-- Оружие или дубинка в правой руке (как у охранника: Gear.Held, конец ствола — Muzzle).
local GRIP = CFrame.new(0, -0.18, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

local function arm(model: Model, kind: string)
	local hand = model:FindFirstChild("RightHand")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local gear = Instance.new("Model")
	gear.Name = "Gear"
	local built = WeaponModels.build(kind)
	WeaponModels.weld(built, hand, hand.CFrame * GRIP)
	built.model.Name = "Held"
	built.model.Parent = gear
	gear.Parent = model
end

local function buildRobber(role: string, gun: string?): Model?
	local colors = (Settings.Colors :: any)[role]
	local skin = Settings.Colors.Skin
	local model = ThiefKinds.rig({ head = skin, torso = colors.Shirt, arms = colors.Shirt, legs = colors.Pants })
	if not model then
		return nil
	end
	balaclava(model, colors, if role == "Grabber" then colors.Stripe else nil)
	vest(model, colors, role == "Gunner")
	gloves(model)
	if role == "Grabber" then
		lootBag(model)
		arm(model, "Baton")
	else
		arm(model, gun or "Pistol")
	end
	model.Name = "Robber"
	model:SetAttribute(ThiefAttr.Kind, "Robber")
	model:SetAttribute(ThiefAttr.Robber, true)
	model:SetAttribute(ThiefAttr.RobberRole, role)
	model:SetAttribute("RobberGun", gun or "")
	model:SetAttribute(RobberService.ArrestableAttr, false)
	return model
end

---------------------------------------------------------------- появление и удаление

local function spawnRobber(role: string, gun: string?, entrance: BasePart): Model?
	if not active then
		return nil
	end
	local model = buildRobber(role, gun)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not (model and humanoid and root and root:IsA("BasePart")) or not active then
		if model then
			model:Destroy()
		end
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = Settings.WalkSpeed
	ModelLibrary.setCollisionGroup(model, ModelLibrary.Groups.Thieves)
	model:PivotTo(entrance.CFrame * CFrame.new(random:NextNumber(-3, 3), 0, random:NextNumber(-1, 1)))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local robber: Robber = {
		model = model,
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 }),
		role = role,
		gun = gun,
		health = Settings.Health,
		state = "Move",
		entrance = entrance,
		waypoints = {},
		waypointIndex = 1,
		pathTarget = nil,
		pathTime = 0,
		computing = false,
		cover = nil,
		coverAt = 0,
		peeking = false,
		phaseUntil = 0,
		nextShot = now() + random:NextNumber(0.5, 1.5),
		burstLeft = 0,
		smokes = if role == "Gunner" then 1 else 0,
		lastSeen = now(),
		strikeStarted = 0,
		strikeTarget = nil,
		strikeHit = false,
		nextStrike = 0,
		throwStarted = 0,
		throwTarget = Vector3.zero,
		thrown = false,
		target = nil,
		stealStarted = 0,
		stunUntil = 0,
		surrenderUntil = 0,
		downAt = 0,
		connections = {},
	}
	robbers[model] = robber
	syncAnim(robber)
	ScoreService.addSpawned()
	RobberService.Spawned:Fire(model)
	return model
end

function RobberService.remove(model: Model)
	local robber = robbers[model]
	if robber then
		for _, connection in robber.connections do
			connection:Disconnect()
		end
		setCover(robber, nil)
		robbers[model] = nil
	end
	ExhibitService.cancelSteal(model)
	local carried = ExhibitService.getCarried(model)
	if carried then
		ExhibitService.returnHome(carried)
	end
	model:Destroy()
end

function RobberService.isRobber(instance: Instance): boolean
	return instance:IsA("Model") and robbers[instance] ~= nil
end

-- Арест: только сдавшегося или оглушённого шокером. Возвращает true, если получилось.
function RobberService.arrest(model: Model): boolean
	local robber = robbers[model]
	if not robber or (robber.state ~= "Surrender" and robber.state ~= "Stunned") then
		return false
	end
	robber.state = "Arrested"
	setArrestable(robber, false)
	robber.humanoid.WalkSpeed = 0
	stand(robber)
	robber.root.Anchored = true
	dropLoot(robber)
	syncAnim(robber)
	return true
end

-- Попадание пули (WeaponService). Возвращает "ko" — упал, "hit" — ранен, nil — пуля не берёт (сдался, лежит).
local function shoot(model: Model, amount: number, _shooter: Player): string?
	local robber = robbers[model]
	if not robber or robber.state == "Down" or robber.state == "Arrested" or robber.state == "Surrender" then
		return nil
	end
	robber.health -= amount
	-- Белая вспышка (без крови)
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.35
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = model
	Debris:AddItem(flash, 0.12)
	if robber.health > 0 then
		robber.lastSeen = now()
		return "hit"
	end
	-- «Убит»: падает со звёздочками, роняет добычу, потом исчезает в облачке. Денег нет.
	robber.state = "Down"
	robber.downAt = now()
	setArrestable(robber, false)
	setCover(robber, nil)
	robber.humanoid.WalkSpeed = 0
	stand(robber)
	dropLoot(robber)
	syncAnim(robber)
	HeistFx.stunEffect(model, Settings.KnockoutSeconds + 0.5)
	Audio.playOnce(Config.Sounds.RobberDown, robber.root, Config.Sounds.GuardDownVolume, nil, Config.Sounds.RobberDownSpeed)
	ScoreService.addStopped()
	task.delay(Settings.KnockoutSeconds, function()
		if robbers[model] then
			poof(robber.root.Position)
			RobberService.remove(model)
		end
	end)
	return "ko"
end

-- Шокер: лежит StunSeconds, роняет добычу, можно арестовать.
local function stun(model: Model, _shooter: Player): boolean
	local robber = robbers[model]
	if not robber or robber.state == "Down" or robber.state == "Arrested" or robber.state == "Surrender" then
		return false
	end
	local was = robber.state
	robber.state = "Stunned"
	robber.stunUntil = now() + Settings.StunSeconds
	robber.strikeTarget = nil
	robber.humanoid.WalkSpeed = 0
	stand(robber)
	dropLoot(robber)
	setArrestable(robber, true)
	if was ~= "Stunned" then
		syncAnim(robber)
	end
	HeistFx.stunEffect(model, Settings.StunSeconds)
	return true
end

---------------------------------------------------------------- налёт

local function clearPoliceLights()
	for _, light in policeLights do
		light:Destroy()
	end
	table.clear(policeLights)
end

-- Мигалки у всех дверей: красный и синий по очереди.
local function policeArrive()
	clearPoliceLights()
	for _, entrance in entrances do
		local base = entrance.CFrame * CFrame.new(0, 0, 6)
		local bar = ModelLibrary.place("prop_police_lights_01", base, {
			{ name = "Post", size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(0, 1.5, 0), color = Color3.fromHex("2B2F3A"), material = Enum.Material.Metal },
			{ name = "Bar", size = Vector3.new(3, 0.4, 0.8), offset = CFrame.new(0, 3.2, 0), color = Color3.fromHex("141518") },
			{ name = "Red", size = Vector3.new(1.3, 0.45, 0.85), offset = CFrame.new(-0.75, 3.25, 0), color = Color3.fromHex("FF2B2B"), material = Enum.Material.Neon },
			{ name = "Blue", size = Vector3.new(1.3, 0.45, 0.85), offset = CFrame.new(0.75, 3.25, 0), color = Color3.fromHex("2B6BFF"), material = Enum.Material.Neon },
		}, folder)
		local red = bar:FindFirstChild("Red")
		local blue = bar:FindFirstChild("Blue")
		if red and blue and red:IsA("BasePart") and blue:IsA("BasePart") then
			local lights: { PointLight } = {}
			for _, part in { red, blue } do
				local light = Instance.new("PointLight")
				light.Color = part.Color
				light.Range = Raid.PoliceLightRange
				light.Brightness = 3
				light.Parent = part
				table.insert(lights, light)
			end
			task.spawn(function()
				local on = true
				while bar.Parent do
					on = not on
					red.Transparency = if on then 0 else 0.85
					blue.Transparency = if on then 0.85 else 0
					lights[1].Enabled = on
					lights[2].Enabled = not on
					task.wait(0.25)
				end
			end)
		end
		table.insert(policeLights, bar)
	end
end

local function endRaid(early: boolean)
	if GameState.get(Attr.Raid) == true and early then
		bannerRemote:FireAllClients("THE RAID IS OVER!", "info")
	end
	GameState.set(Attr.Raid, false)
	GameState.set(Attr.PoliceAt, 0)
	GameState.set(Attr.PoliceArrived, false)
end

-- Полиция приехала: оставшиеся грабители сдаются на SurrenderSeconds, потом их забирает полиция.
local function surrenderAll()
	GameState.set(Attr.PoliceArrived, true)
	bannerRemote:FireAllClients("POLICE ARRIVED! ARREST THE ROBBERS!", "info")
	Audio.playOnce(Config.Sounds.Alarm, nil, Config.Sounds.AlarmVolume, Config.Sounds.AlarmSeconds, Config.Sounds.PoliceSpeed)
	policeArrive()
	local time = now()
	for model, robber in robbers do
		if robber.state ~= "Down" and robber.state ~= "Arrested" then
			robber.state = "Surrender"
			robber.surrenderUntil = time + Raid.SurrenderSeconds
			robber.strikeTarget = nil
			robber.humanoid.WalkSpeed = 0
			stand(robber)
			dropLoot(robber)
			setCover(robber, nil)
			model:SetAttribute(GameState.ThiefAttr.Surrendered, true)
			setArrestable(robber, true)
			syncAnim(robber)
			task.delay(Raid.SurrenderSeconds, function()
				-- Не арестовали — забирает полиция (денег нет)
				local current = robbers[model]
				if current and current.state == "Surrender" then
					poof(current.root.Position)
					ScoreService.addStopped()
					RobberService.remove(model)
				end
			end)
		end
	end
	task.delay(Raid.SurrenderSeconds + 1, function()
		clearPoliceLights()
		if active then
			endRaid(false)
		end
	end)
end

-- Дверь налёта: дальняя от охраны.
local function raidEntrance(): BasePart?
	local open = ThiefService.entrances()
	local best, bestDistance = nil, -1
	for _, entrance in open do
		local distance = math.huge
		for _, guard in guards() do
			distance = math.min(distance, flatDistance(guard.root.Position, entrance.Position))
		end
		if distance > bestDistance then
			best, bestDistance = entrance, distance
		end
	end
	return best
end

-- Начать налёт: игроки × 3 грабителя через одну дверь, отсчёт полиции.
function RobberService.startRaid(playerCount: number)
	if not active or GameState.get(Attr.Raid) == true then
		return
	end
	local entrance = raidEntrance()
	if not entrance then
		return
	end
	raidIndex += 1
	local total = math.max(1, playerCount) * Raid.PerPlayer
	local grabbers = math.max(1, math.floor(total * Raid.GrabberShare + 0.5))
	local rifleShare = math.clamp(Settings.RifleShare + Settings.RifleShareGrowth * (raidIndex - 1), 0, 0.8)
	spawningUntil = now() + total * Raid.Stagger + 1.5
	GameState.set(Attr.Raid, true)
	GameState.set(Attr.PoliceArrived, false)
	GameState.set(Attr.PoliceAt, now() + Raid.PoliceSeconds)
	bannerRemote:FireAllClients("ARMED ROBBERY!", "danger")
	Audio.alarm()
	task.spawn(function()
		for index = 1, total do
			if not active then
				return
			end
			local role = if index % 3 == 0 and grabbers > 0 then "Grabber" else "Gunner"
			if total - index < grabbers then
				role = "Grabber" -- остаток — хватальщики
			end
			if role == "Grabber" then
				grabbers -= 1
			end
			local gun = if role == "Gunner" then (if random:NextNumber() < rifleShare then "Rifle" else "Pistol") else nil
			spawnRobber(role, gun, entrance)
			task.wait(Raid.Stagger)
		end
	end)
	if policeThread then
		pcall(task.cancel, policeThread)
	end
	policeThread = task.delay(Raid.PoliceSeconds, function()
		policeThread = nil
		if active and GameState.get(Attr.Raid) == true then
			surrenderAll()
		end
	end)
end

function RobberService.raidActive(): boolean
	return GameState.get(Attr.Raid) == true
end

---------------------------------------------------------------- ночь

function RobberService.beginNight()
	RobberService.endNight()
	active = true
	local accumulator = 0
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Settings.UpdateSeconds then
			return
		end
		accumulator = 0
		local any = false
		for _, robber in robbers do
			any = true
			if robber.model.Parent then
				updateRobber(robber)
			end
		end
		-- Всех остановили до приезда полиции — налёт кончился
		if not any and GameState.get(Attr.Raid) == true and GameState.get(Attr.PoliceArrived) ~= true and now() > spawningUntil then
			if policeThread then
				pcall(task.cancel, policeThread)
				policeThread = nil
			end
			endRaid(true)
		end
		for index = #smokes, 1, -1 do
			if smokes[index].untilTime < now() then
				table.remove(smokes, index)
			end
		end
	end)
end

function RobberService.endNight()
	active = false
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	if policeThread then
		pcall(task.cancel, policeThread)
		policeThread = nil
	end
	local models = {}
	for model in robbers do
		table.insert(models, model)
	end
	for _, model in models do
		RobberService.remove(model)
	end
	table.clear(reserved)
	for _, smoke in smokes do
		smoke.part:Destroy()
	end
	table.clear(smokes)
	clearPoliceLights()
	-- Брошенные шашки и облака дыма
	for _, child in folder:GetChildren() do
		if child.Name == "SmokeCloud" or child.Name == WeaponModels.Names.Smoke then
			child:Destroy()
		end
	end
	endRaid(false)
end

-- Новый забег: налёты считаются заново (шанс попадания грабителей снова с начала).
function RobberService.resetRun()
	raidIndex = 0
end

function RobberService.init(map: Instance)
	folder = Workspace:WaitForChild(MapSchema.Thieves) :: Folder
	local entranceFolder = map:FindFirstChild(MapSchema.Entrances)
	if entranceFolder then
		for _, child in entranceFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(entrances, child)
			end
		end
	end
	buildCovers(map)
	GameState.set(Attr.Raid, false)
	GameState.set(Attr.PoliceAt, 0)
	GameState.set(Attr.PoliceArrived, false)
	WeaponService.addTargets({ owns = RobberService.isRobber, shoot = shoot, stun = stun })
end

return RobberService
