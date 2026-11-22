-- Умения классов (блок 5). Клиент только просит («UseAbility», имя умения), сервер решает всё сам:
-- подходит ли умение классу, идёт ли смена (день или ночь), может ли охранник действовать (не лежит,
-- не смотрит камеры), прошла ли перезарядка, где встанет датчик, кого учуяла собака.
--  • Patrol — рывок (Shift): несколько секунд бежит быстрее;
--  • Technician — датчик движения (G, 1 за ночь): вор прошёл рядом — у всей охраны писк и стрелка к датчику;
--    камеры у рубильника перезапускает мгновенно (Abilities.client убирает удержание у своей кнопки);
--  • Operator — телефон с камерами (RoleService, CameraController);
--  • Assault — здоровье (HealthService) и отдача (Weapons.client).
-- Состояние умения — в атрибутах игрока (AbilityReadyAt, AbilityUntil, AbilityCharges): по ним клиент
-- рисует кнопку умения с полоской перезарядки (Abilities.client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClassModels = require(Shared:WaitForChild("ClassModels"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local PlayerAttr = GameState.PlayerAttr
local Phase = GameState.Phase
local Classes = Config.Classes

local AbilityService = {}

type Handler = (player: Player, info: { [string]: any }) -> ()
local handlers: { [string]: Handler } = {}

type Sensor = { model: Model, owner: Player, position: Vector3, lastPing: number }
local sensors: { Sensor } = {}
local sensorsFolder: Folder
local map: Instance

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function onShiftPhase(): boolean
	local phase = GameState.phase()
	return phase == Phase.Day or phase == Phase.Night
end

local function readyAt(player: Player): number
	return tonumber(player:GetAttribute(PlayerAttr.AbilityReadyAt)) or 0
end

---------------------------------------------------------------- рывок патруля

-- Shift: SprintSeconds бежит со скоростью SprintSpeed (скорость считает RoleService.refreshMovement),
-- перезарядка SprintCooldown — после конца рывка. Присевший сначала встаёт (сам).
handlers.Dash = function(player: Player, info: { [string]: any })
	if player:GetAttribute(PlayerAttr.Crouch) == true then
		return
	end
	local endsAt = now() + info.SprintSeconds
	player:SetAttribute(PlayerAttr.AbilityUntil, endsAt)
	player:SetAttribute(PlayerAttr.AbilityReadyAt, endsAt + info.SprintCooldown)
	RoleService.refreshMovement(player)
	task.delay(info.SprintSeconds + 0.05, function()
		if player.Parent then
			RoleService.refreshMovement(player)
		end
	end)
end

---------------------------------------------------------------- кого чуют датчики и собаки

local ASLEEP: { [string]: boolean } = { -- вор уже не опасен: арестован, сдался, «убит»
	[GameState.ThiefAnim.Arrest] = true,
	[GameState.ThiefAnim.Surrender] = true,
	[GameState.ThiefAnim.Knockout] = true,
}

type Seen = { model: Model, position: Vector3 }

-- Воры, которые сейчас в музее и на ногах (обычные воры, грабители, Фальшивый охранник).
-- Шахтёра под полом ещё нет в мире — его не чуют.
local function livingThieves(): { Seen }
	local list = {}
	local folder = Workspace:FindFirstChild(MapSchema.Thieves)
	if not folder then
		return list
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute(GameState.ThiefAttr.Surrendered) ~= true then
			local state = model:GetAttribute(GameState.NpcAttr.AnimState)
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and not (typeof(state) == "string" and ASLEEP[state]) then
				table.insert(list, { model = model, position = root.Position })
			end
		end
	end
	return list
end

---------------------------------------------------------------- датчик движения техника

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Луч по твёрдым деталям карты: без людей, воров, туристов, собак и датчиков.
local function mapRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { sensorsFolder }
	for _, name in { MapSchema.Thieves, MapSchema.Tourists, MapSchema.Dogs } do
		local found = Workspace:FindFirstChild(name)
		if found then
			table.insert(ignore, found)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Круг на полу из светящихся чёрточек: докуда видит датчик.
local function addRing(model: Model, center: CFrame, radius: number)
	local settings = Classes.Sensor
	local ring = Instance.new("Model")
	ring.Name = "Range"
	local count = settings.RingSegments
	local length = 2 * math.pi * radius / count * 0.55
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local position = center * Vector3.new(math.cos(angle) * radius, 0.06, math.sin(angle) * radius)
		local tangent = center:VectorToWorldSpace(Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		local dash = Instance.new("Part")
		dash.Name = "Dash" .. index
		dash.Anchored = true
		dash.CanCollide = false
		dash.CanQuery = false
		dash.CanTouch = false
		dash.CastShadow = false
		dash.Material = Enum.Material.Neon
		dash.Color = settings.RingColor
		dash.Transparency = settings.RingTransparency
		dash.Size = Vector3.new(0.18, 0.04, length)
		dash.CFrame = CFrame.lookAt(position, position + tangent)
		dash.Parent = ring
	end
	ring.Parent = model
end

local function removeSensors()
	for _, sensor in sensors do
		sensor.model:Destroy()
	end
	table.clear(sensors)
end

-- G: датчик встаёт на пол на PlaceReach перед ногами (если там стена — прямо под ногами).
-- Ставить можно днём и ночью, SensorsPerNight раз за ночь; утром датчики убираются.
handlers.Sensor = function(player: Player, info: { [string]: any })
	local charges = tonumber(player:GetAttribute(PlayerAttr.AbilityCharges)) or 0
	local root = rootOf(player)
	if charges <= 0 or not root then
		return
	end
	local params = mapRayParams()
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local spot = root.Position
	if not Workspace:Raycast(root.Position, look * (info.PlaceReach + 0.8), params) then
		spot += look * info.PlaceReach
	end
	local hit = Workspace:Raycast(spot + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), params)
	if not hit or not hit.Instance:IsDescendantOf(map) or root.Position.Y - hit.Position.Y > 6 then
		return -- под ногами нет пола (прыжок, край балкона)
	end
	for _, other in sensors do
		if (other.position - hit.Position).Magnitude < info.PlaceMinGap then
			return
		end
	end
	local pivot = CFrame.lookAt(hit.Position, hit.Position + look)
	local built = ClassModels.sensor()
	WeaponModels.anchor(built, pivot)
	local model = built.model
	model.Name = "Sensor_" .. player.UserId
	model:SetAttribute(GameState.SensorAttr.Owner, player.UserId)
	model:SetAttribute(GameState.SensorAttr.PlacedAt, now())
	model:SetAttribute(GameState.SensorAttr.PingAt, 0)
	model:SetAttribute(GameState.SensorAttr.Radius, info.SensorRadius)
	addRing(model, pivot, info.SensorRadius)
	model.Parent = sensorsFolder
	table.insert(sensors, { model = model, owner = player, position = hit.Position, lastPing = 0 })
	player:SetAttribute(PlayerAttr.AbilityCharges, charges - 1)
	player:SetAttribute(PlayerAttr.AbilityReadyAt, now() + 1)
	Audio.playOnce(Config.Sounds.SensorPlace, built.root, Config.Sounds.SensorPlaceVolume, nil, Config.Sounds.SensorPlaceSpeed)
end

-- Вор ближе SensorRadius к датчику — PingAt: у всей охраны писк и стрелка (Abilities.client).
-- Пока вор рядом, писк повторяется раз в PingSeconds.
local function checkSensors(thieves: { Seen })
	local settings = Classes.Technician
	local t = now()
	for _, sensor in sensors do
		if t - sensor.lastPing >= settings.PingSeconds then
			for _, thief in thieves do
				if (thief.position - sensor.position).Magnitude <= settings.SensorRadius then
					sensor.lastPing = t
					sensor.model:SetAttribute(GameState.SensorAttr.PingAt, t)
					break
				end
			end
		end
	end
end

local function onUseAbility(player: Player, name: any)
	if typeof(name) ~= "string" then
		return
	end
	local info = GameState.classInfo(GameState.roleOf(player))
	if not info or info.Ability ~= name then
		return -- умение не этого класса
	end
	local handler = handlers[name]
	if not handler or not onShiftPhase() or not RoleService.canAct(player) then
		return
	end
	if readyAt(player) > now() + Classes.AbilitySlack then
		return -- ещё перезаряжается
	end
	handler(player, info)
end

-- Умение сброшено: готово, ничего не действует.
local function resetPlayer(player: Player)
	player:SetAttribute(PlayerAttr.AbilityReadyAt, 0)
	player:SetAttribute(PlayerAttr.AbilityUntil, 0)
	player:SetAttribute(PlayerAttr.AbilityCharges, 0)
end

---------------------------------------------------------------- фазы

-- Утро нового дня (и первый день забега): у техников снова есть датчики.
function AbilityService.beginDay()
	removeSensors()
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
		if GameState.roleOf(player) == GameState.Role.Technician then
			player:SetAttribute(PlayerAttr.AbilityCharges, Classes.Technician.SensorsPerNight)
		end
	end
end

function AbilityService.beginNight() end

-- Ночь кончилась: датчики убираются.
function AbilityService.endNight()
	removeSensors()
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
		RoleService.refreshMovement(player)
	end
end

-- Конец забега: всё убрать.
function AbilityService.resetRun()
	AbilityService.endNight()
end

local function folder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = Workspace
	return created
end

function AbilityService.init(builtMap: Instance)
	map = builtMap
	sensorsFolder = folder(MapSchema.Sensors)
	Remotes.get(Remotes.Names.UseAbility).OnServerEvent:Connect(onUseAbility)

	-- Датчики проверяют воров раз в CheckSeconds, только ночью
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Classes.CheckSeconds then
			return
		end
		accumulator = 0
		if GameState.phase() ~= Phase.Night then
			return
		end
		local thieves = livingThieves()
		checkSensors(thieves)
	end)
	Players.PlayerAdded:Connect(resetPlayer)
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
	end
end

return AbilityService
