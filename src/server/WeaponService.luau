-- Оружие игроков (блок 4). Всё решает сервер, клиент только шлёт намерения (Equip / Fire / Reload / UseMedkit).
--  • Что у кого есть — атрибуты игрока (HasTaser, HasPistol, Primary, Medkits, патроны AmmoX / ReserveX):
--    по ним клиент рисует слоты, патроны и руки с оружием. Покупает оружейная (ArmoryService).
--  • С собой 4 места: 1 — основное (автомат или дробовик), 2 — пистолет, 3 — шокер, 4 — аптечка.
--  • Огнестрел в кобуре, пока нет налёта (атрибут GameState Raid): достать нельзя, налёт кончился — убирается сам.
--    Шокер стреляет только ночью (днём в музее туристы).
--  • Выстрел: клиент шлёт точку и направление. Сервер проверяет, что оружие в руках, темп, патроны, что точка
--    у головы стрелка, а направление — туда, куда он смотрит, и сам пускает луч. Пули проходят сквозь охрану,
--    туристов и обычных воров (по безоружным не стреляем) — попадают только в «цели» (грабители, RobberService).
--    Шокер попадает и в обычных воров (ThiefService.stun).
--  • Оружие видно на персонаже: в руке, пистолет и шокер на поясе, основное за спиной, бронежилет поверх формы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local HealthService = require(Server:WaitForChild("HealthService"))

local PlayerAttr = GameState.PlayerAttr
local Weapons = Config.Weapons
local Phase = GameState.Phase

local WeaponService = {}

-- Кто может получить пулю или шокер. owns — это его модель; shoot — урон (вернёт "hit" / "ko" или nil,
-- если не ранен); stun — шокер (вернёт true, если оглушён).
export type Targets = {
	owns: (Model) -> boolean,
	shoot: ((Model, number, Player) -> string?)?,
	stun: ((Model, Player) -> boolean)?,
}

type State = {
	nextShot: number, -- раньше этого (минус FireJitter) следующий выстрел не принимается
	reloadToken: number,
	healToken: number,
	connections: { RBXScriptConnection },
}

local FIREARMS = { Pistol = true, Rifle = true, Shotgun = true }
local SLOT_KINDS = { "Primary", "Pistol", "Taser", "Medkit" }
local GEAR_NAME = "Gear"

local targets: { Targets } = {}
local states: { [Player]: State } = {}
local random = Random.new()

local shotRemote = Remotes.get(Remotes.Names.ShotFx)
local hitRemote = Remotes.get(Remotes.Names.HitConfirm)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function info(weapon: string): any
	return (Weapons :: any)[weapon]
end

function WeaponService.addTargets(handler: Targets)
	table.insert(targets, handler)
end

local function targetFor(model: Model): Targets?
	for _, handler in targets do
		if handler.owns(model) then
			return handler
		end
	end
	return nil
end

local function raidActive(): boolean
	return GameState.get(GameState.Attr.Raid) == true
end

local function roundPhase(): boolean
	local phase = GameState.phase()
	return phase == Phase.Day or phase == Phase.Night
end

---------------------------------------------------------------- патроны

local function ammo(player: Player, weapon: string): number
	return tonumber(player:GetAttribute(GameState.ammoAttr(weapon))) or 0
end

local function reserve(player: Player, weapon: string): number
	return tonumber(player:GetAttribute(GameState.reserveAttr(weapon))) or 0
end

local function setAmmo(player: Player, weapon: string, mag: number, spare: number)
	player:SetAttribute(GameState.ammoAttr(weapon), mag)
	player:SetAttribute(GameState.reserveAttr(weapon), spare)
end

---------------------------------------------------------------- оружие на персонаже

-- Хват в правой кисти: ствол вдоль пальцев (когда рука поднята — вперёд), верх оружия — к тыльной стороне кисти.
local GRIP = CFrame.new(0, -0.18, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

local function partOf(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function addGear(folder: Model, kind: string, toPart: BasePart?, offset: CFrame)
	if not toPart then
		return
	end
	local built = WeaponModels.build(kind)
	WeaponModels.weld(built, toPart, toPart.CFrame * offset)
	built.model.Name = kind
	built.model.Parent = folder
end

-- Пересобрать всё снаряжение на персонаже (вызывается только при изменениях: достал, убрал, купил, броня).
local function refreshGear(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild(GEAR_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = GEAR_NAME
	local equipped = player:GetAttribute(PlayerAttr.Equipped)
	local hand = partOf(character, "RightHand")
	local lower = partOf(character, "LowerTorso")
	local upper = partOf(character, "UpperTorso")
	if typeof(equipped) == "string" and equipped ~= "" then
		local offset = if equipped == "Medkit" then CFrame.new(0, -0.2, 0) * CFrame.Angles(0, math.pi / 2, 0) else GRIP
		addGear(folder, equipped, hand, offset)
		local held = folder:FindFirstChild(equipped)
		if held then
			held.Name = "Held"
		end
	end
	local l = if lower then lower.Size else Vector3.new(2, 0.4, 1)
	local t = if upper then upper.Size else Vector3.new(2, 1.6, 1)
	-- Пистолет справа на поясе, шокер слева: стволом вниз, рукоятью назад
	if GameState.hasWeapon(player, "Pistol") and equipped ~= "Pistol" then
		addGear(folder, "Pistol", lower, CFrame.new(l.X * 0.56, -0.15, 0.05) * CFrame.Angles(-math.pi / 2, 0, 0))
	end
	if GameState.hasWeapon(player, "Taser") and equipped ~= "Taser" then
		addGear(folder, "Taser", lower, CFrame.new(-l.X * 0.56, -0.15, 0.05) * CFrame.Angles(-math.pi / 2, 0, 0))
	end
	-- Основное — наискосок за спиной, стволом вверх-влево
	local primary = player:GetAttribute(PlayerAttr.Primary)
	if typeof(primary) == "string" and primary ~= "" and equipped ~= primary then
		addGear(folder, primary, upper, CFrame.new(t.X * 0.22, -t.Y * 0.32, t.Z * 0.5 + 0.32) * CFrame.Angles(0, 0, math.rad(38)) * CFrame.Angles(math.pi / 2, 0, 0))
	end
	-- Бронежилет поверх формы, пока есть броня
	if upper and HealthService.armor(player) > 0 then
		local vest = WeaponModels.fromSpecs("guard_vest_01", WeaponModels.vestSpecs(t))
		WeaponModels.weld(vest, upper, upper.CFrame)
		WeaponModels.labelVest(vest.model)
		vest.model.Name = "Vest"
		vest.model.Parent = folder
	end
	folder.Parent = character
end

---------------------------------------------------------------- в руках

local function cancelActions(player: Player)
	local state = states[player]
	if state then
		state.reloadToken += 1
		state.healToken += 1
	end
	player:SetAttribute(PlayerAttr.ReloadUntil, 0)
	player:SetAttribute(PlayerAttr.HealUntil, 0)
end

local function setEquipped(player: Player, weapon: string)
	if player:GetAttribute(PlayerAttr.Equipped) == weapon then
		return
	end
	cancelActions(player)
	player:SetAttribute(PlayerAttr.Equipped, weapon)
	refreshGear(player)
end

-- Что лежит в месте slot (1–4) у игрока: имя оружия или nil.
local function weaponInSlot(player: Player, slot: number): string?
	local kind = SLOT_KINDS[slot]
	if kind == "Primary" then
		local primary = player:GetAttribute(PlayerAttr.Primary)
		return if typeof(primary) == "string" and primary ~= "" then primary else nil
	elseif kind == "Pistol" or kind == "Taser" then
		return if GameState.hasWeapon(player, kind) then kind else nil
	elseif kind == "Medkit" then
		return if (tonumber(player:GetAttribute(PlayerAttr.Medkits)) or 0) > 0 then "Medkit" else nil
	end
	return nil
end

local function canHold(player: Player, weapon: string): boolean
	if not RoleService.canAct(player) or not roundPhase() then
		return false
	end
	if FIREARMS[weapon] then
		return raidActive() -- огнестрел — только во время налёта
	end
	return true
end

-- Убрать всё огнестрельное (налёт кончился) или вообще всё (лежит без сил).
local function holster(player: Player, onlyFirearms: boolean)
	local equipped = player:GetAttribute(PlayerAttr.Equipped)
	if typeof(equipped) == "string" and equipped ~= "" and (not onlyFirearms or FIREARMS[equipped]) then
		setEquipped(player, "")
	end
end

---------------------------------------------------------------- выстрел

local function headPosition(player: Player): Vector3?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else nil
end

-- Луч не задевает охрану, туристов и тех, кого это оружие не берёт (обычных воров — пуля).
local function rayParams(stunning: boolean): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local tourists = Workspace:FindFirstChild(MapSchema.Tourists)
	if tourists then
		table.insert(ignore, tourists)
	end
	local thieves = Workspace:FindFirstChild(MapSchema.Thieves)
	if thieves then
		for _, model in thieves:GetChildren() do
			if model:IsA("Model") then
				local handler = targetFor(model)
				if not handler or (stunning and not handler.stun) or (not stunning and not handler.shoot) then
					table.insert(ignore, model)
				end
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

-- Модель вора или грабителя, в которую попал луч (прямой ребёнок папки Thieves).
local function thiefModel(part: Instance): Model?
	local thieves = Workspace:FindFirstChild(MapSchema.Thieves)
	local current: Instance? = part
	while current and current.Parent ~= thieves do
		current = current.Parent
	end
	return if current and current:IsA("Model") then current else nil
end

-- Направление с разбросом (дробь) в конусе spread градусов.
local function spreadDirection(direction: Vector3, spread: number): Vector3
	if spread <= 0 then
		return direction
	end
	local angle = math.rad(spread) * math.sqrt(random:NextNumber())
	local spin = random:NextNumber() * math.pi * 2
	local basis = CFrame.lookAt(Vector3.zero, direction)
	return (basis * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Урон дробины с расстоянием: полный вблизи, дальше всё слабее.
local function falloff(weaponInfo: any, distance: number): number
	if not weaponInfo.FalloffStart then
		return 1
	end
	local t = math.clamp((distance - weaponInfo.FalloffStart) / (weaponInfo.FalloffEnd - weaponInfo.FalloffStart), 0, 1)
	return 1 - (1 - weaponInfo.FalloffMin) * t
end

local function fire(player: Player, weapon: string, origin: Vector3, direction: Vector3)
	local state = states[player]
	local weaponInfo = info(weapon)
	if not state or not weaponInfo or player:GetAttribute(PlayerAttr.Equipped) ~= weapon then
		return
	end
	if GameState.phase() ~= Phase.Night or not RoleService.canAct(player) then
		return
	end
	local time = now()
	local stunning = weapon == "Taser"
	if stunning then
		if time < (tonumber(player:GetAttribute(PlayerAttr.TaserReadyAt)) or 0) then
			return
		end
	else
		if not raidActive() or (tonumber(player:GetAttribute(PlayerAttr.ReloadUntil)) or 0) > time then
			return
		end
		if time < state.nextShot - Weapons.FireJitter then
			return -- слишком часто
		end
		if ammo(player, weapon) < 1 then
			return
		end
	end
	-- Точка выстрела — у головы стрелка, направление — туда, куда он смотрит (с запасом на задержку сети)
	local head = headPosition(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not head or not (root and root:IsA("BasePart")) or (origin - head).Magnitude > Weapons.OriginSlack then
		return
	end
	local length = direction.Magnitude
	if length < 0.5 or length > 1.5 or length ~= length then
		return
	end
	direction = direction.Unit
	local flatAim = Vector3.new(direction.X, 0, direction.Z)
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatAim.Magnitude > 0.1 and flatLook.Magnitude > 0.1 and flatAim.Unit:Dot(flatLook.Unit) < Weapons.AimDot then
		return
	end

	state.nextShot = math.max(time, state.nextShot) + weaponInfo.Interval
	if stunning then
		player:SetAttribute(PlayerAttr.TaserReadyAt, time + weaponInfo.Cooldown)
	else
		player:SetAttribute(GameState.ammoAttr(weapon), ammo(player, weapon) - 1)
	end

	local params = rayParams(stunning)
	local pellets = weaponInfo.Pellets or 1
	local ends: { Vector3 } = {}
	local hits: { boolean } = {}
	local damageBy: { [Model]: number } = {}
	local headBy: { [Model]: boolean } = {}
	local confirm: string? = nil
	for _ = 1, pellets do
		local dir = spreadDirection(direction, weaponInfo.Spread or 0)
		local result = Workspace:Raycast(origin, dir * weaponInfo.Range, params)
		local point = if result then result.Position else origin + dir * weaponInfo.Range
		local hitModel = if result then thiefModel(result.Instance) else nil
		table.insert(ends, point)
		table.insert(hits, hitModel ~= nil)
		if hitModel and result then
			if stunning then
				local handler = targetFor(hitModel)
				if handler and handler.stun and handler.stun(hitModel, player) then
					confirm = "stun"
				end
			else
				local isHead = result.Instance.Name == "Head"
				local amount = weaponInfo.Damage * falloff(weaponInfo, (point - origin).Magnitude)
					* (if isHead then Weapons.HeadMultiplier else 1)
				damageBy[hitModel] = (damageBy[hitModel] or 0) + amount
				headBy[hitModel] = headBy[hitModel] or isHead
			end
		end
	end
	-- Урон по каждому задетому грабителю — одним разом (дробь)
	for model, amount in damageBy do
		local handler = targetFor(model)
		local result = if handler and handler.shoot then handler.shoot(model, math.floor(amount + 0.5), player) else nil
		if result == "ko" then
			confirm = "ko"
		elseif result and confirm ~= "ko" then
			confirm = if headBy[model] then "head" else "hit"
		end
	end
	shotRemote:FireAllClients(player, weapon, origin, ends, hits)
	if confirm then
		hitRemote:FireClient(player, confirm)
	end
end

---------------------------------------------------------------- перезарядка и аптечка

local function reload(player: Player)
	local state = states[player]
	local weapon = player:GetAttribute(PlayerAttr.Equipped)
	if not state or typeof(weapon) ~= "string" or not FIREARMS[weapon] or not RoleService.canAct(player) then
		return
	end
	local weaponInfo = info(weapon)
	if (tonumber(player:GetAttribute(PlayerAttr.ReloadUntil)) or 0) > 0 then
		return -- уже перезаряжает
	end
	if ammo(player, weapon) >= weaponInfo.MagSize or reserve(player, weapon) <= 0 then
		return
	end
	state.reloadToken += 1
	local token = state.reloadToken
	player:SetAttribute(PlayerAttr.ReloadUntil, now() + weaponInfo.ReloadSeconds)
	task.delay(weaponInfo.ReloadSeconds, function()
		if state.reloadToken ~= token or not player.Parent then
			return
		end
		player:SetAttribute(PlayerAttr.ReloadUntil, 0)
		if player:GetAttribute(PlayerAttr.Equipped) ~= weapon or RoleService.isDowned(player) then
			return
		end
		local mag, spare = ammo(player, weapon), reserve(player, weapon)
		local take = math.min(weaponInfo.MagSize - mag, spare)
		setAmmo(player, weapon, mag + take, spare - take)
	end)
end

local function useMedkit(player: Player)
	local state = states[player]
	if not state or player:GetAttribute(PlayerAttr.Equipped) ~= "Medkit" or not RoleService.canAct(player) then
		return
	end
	if (tonumber(player:GetAttribute(PlayerAttr.HealUntil)) or 0) > 0 then
		return
	end
	if (tonumber(player:GetAttribute(PlayerAttr.Medkits)) or 0) < 1 or HealthService.health(player) >= HealthService.maxHealth(player) then
		return
	end
	local settings = Weapons.Medkit
	state.healToken += 1
	local token = state.healToken
	player:SetAttribute(PlayerAttr.HealUntil, now() + settings.UseSeconds)
	task.delay(settings.UseSeconds, function()
		if state.healToken ~= token or not player.Parent then
			return
		end
		player:SetAttribute(PlayerAttr.HealUntil, 0)
		if player:GetAttribute(PlayerAttr.Equipped) ~= "Medkit" or RoleService.isDowned(player) then
			return
		end
		local left = (tonumber(player:GetAttribute(PlayerAttr.Medkits)) or 0) - 1
		if left < 0 then
			return
		end
		local healed = HealthService.heal(player, settings.Heal)
		HealthService.healEffect(player, healed)
		player:SetAttribute(PlayerAttr.Medkits, left)
		if left == 0 then
			setEquipped(player, "")
		end
	end)
end

---------------------------------------------------------------- покупки (ArmoryService)

-- Новое оружие. Автомат и дробовик занимают одно место: новое заменяет старое.
function WeaponService.grantWeapon(player: Player, weapon: string)
	local weaponInfo = info(weapon)
	if weapon == "Taser" then
		player:SetAttribute(PlayerAttr.HasTaser, true)
		player:SetAttribute(PlayerAttr.TaserReadyAt, 0)
	elseif weapon == "Pistol" then
		player:SetAttribute(PlayerAttr.HasPistol, true)
		setAmmo(player, weapon, weaponInfo.MagSize, weaponInfo.StartReserve)
	elseif weapon == "Rifle" or weapon == "Shotgun" then
		local old = player:GetAttribute(PlayerAttr.Primary)
		if typeof(old) == "string" and old ~= "" and old ~= weapon then
			holster(player, false)
			setAmmo(player, old, 0, 0)
		end
		player:SetAttribute(PlayerAttr.Primary, weapon)
		setAmmo(player, weapon, weaponInfo.MagSize, weaponInfo.StartReserve)
	end
	refreshGear(player)
end

-- Магазин патронов к своему оружию.
function WeaponService.grantAmmo(player: Player, weapon: string)
	local weaponInfo = info(weapon)
	if not weaponInfo or not weaponInfo.MaxReserve then
		return
	end
	player:SetAttribute(GameState.reserveAttr(weapon), math.min(weaponInfo.MaxReserve, reserve(player, weapon) + weaponInfo.MagSize))
end

function WeaponService.grantMedkit(player: Player)
	local count = tonumber(player:GetAttribute(PlayerAttr.Medkits)) or 0
	player:SetAttribute(PlayerAttr.Medkits, math.min(Weapons.Medkit.MaxCarry, count + 1))
end

---------------------------------------------------------------- игроки

-- Ничего нет: новый забег, опоздавший вошёл, вышел из забега.
local function resetInventory(player: Player)
	cancelActions(player)
	player:SetAttribute(PlayerAttr.Equipped, "")
	player:SetAttribute(PlayerAttr.HasTaser, false)
	player:SetAttribute(PlayerAttr.HasPistol, false)
	player:SetAttribute(PlayerAttr.Primary, "")
	player:SetAttribute(PlayerAttr.Medkits, 0)
	player:SetAttribute(PlayerAttr.TaserReadyAt, 0)
	for _, weapon in { "Pistol", "Rifle", "Shotgun" } do
		setAmmo(player, weapon, 0, 0)
	end
	refreshGear(player)
end

local function onPlayerAdded(player: Player)
	local state: State = { nextShot = 0, reloadToken = 0, healToken = 0, connections = {} }
	states[player] = state
	resetInventory(player)
	table.insert(state.connections, player:GetAttributeChangedSignal(PlayerAttr.InRound):Connect(function()
		resetInventory(player)
	end))
	-- Бронежилет появляется и пропадает вместе с бронёй
	local hadArmor = false
	table.insert(state.connections, player:GetAttributeChangedSignal(PlayerAttr.Armor):Connect(function()
		local hasArmor = HealthService.armor(player) > 0
		if hasArmor ~= hadArmor then
			hadArmor = hasArmor
			refreshGear(player)
		end
	end))
	-- Новый персонаж: снаряжение заново, когда у него появятся руки
	table.insert(state.connections, player.CharacterAdded:Connect(function(character)
		character:WaitForChild("RightHand", 10)
		character:WaitForChild("UpperTorso", 10)
		character:WaitForChild("LowerTorso", 10)
		if player.Character == character then
			refreshGear(player)
		end
	end))
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state then
		for _, connection in state.connections do
			connection:Disconnect()
		end
		states[player] = nil
	end
end

local function setupRemotes()
	Remotes.get(Remotes.Names.Equip).OnServerEvent:Connect(function(player, slot)
		if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 0 or slot > #SLOT_KINDS then
			return
		end
		if slot == 0 then
			setEquipped(player, "")
			return
		end
		local weapon = weaponInSlot(player, slot)
		if not weapon then
			return
		end
		if player:GetAttribute(PlayerAttr.Equipped) == weapon then
			setEquipped(player, "") -- то же место ещё раз — убрать в кобуру
		elseif canHold(player, weapon) then
			setEquipped(player, weapon)
		end
	end)
	Remotes.get(Remotes.Names.Fire).OnServerEvent:Connect(function(player, weapon, origin, direction)
		if typeof(weapon) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		if weapon ~= "Taser" and not FIREARMS[weapon] then
			return
		end
		fire(player, weapon, origin, direction)
	end)
	Remotes.get(Remotes.Names.Reload).OnServerEvent:Connect(reload)
	Remotes.get(Remotes.Names.UseMedkit).OnServerEvent:Connect(useMedkit)
end

function WeaponService.init()
	setupRemotes()
	-- Налёт кончился — огнестрел у всех в кобуру
	GameState.folder():GetAttributeChangedSignal(GameState.Attr.Raid):Connect(function()
		if not raidActive() then
			for _, player in Players:GetPlayers() do
				holster(player, true)
			end
		end
	end)
	-- Упал без сил — всё из рук
	HealthService.Downed.Event:Connect(function(player: Player)
		holster(player, false)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- Конец ночи: из рук всё убирается (днём можно снова достать шокер и аптечку).
function WeaponService.endNight()
	for _, player in Players:GetPlayers() do
		holster(player, false)
	end
end

return WeaponService
