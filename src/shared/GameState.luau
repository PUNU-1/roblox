--!strict
-- Общее состояние игры, которое видят все клиенты.
-- Хранится в атрибутах: ReplicatedStorage.GameState (состояние раунда) и у каждого Player.
-- Пишет только сервер, клиенты только читают.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))

local GameState = {}

GameState.Phase = {
	Lobby = "Lobby",
	Day = "Day",
	Night = "Night",
	Results = "Results",
}

GameState.Role = {
	Patrol = "Patrol",
	Operator = "Operator",
}

-- Атрибуты модели NPC (вор, турист): сервер пишет, что он сейчас делает, клиенты по этому двигают руки и ноги.
GameState.NpcAttr = {
	AnimState = "AnimState", -- string, одна из GameState.ThiefAnim или GameState.TouristAnim
	AnimStateAt = "AnimStateAt", -- number, workspace:GetServerTimeNow(), когда началось это состояние
}

GameState.ThiefAnim = {
	Sneak = "Sneak", -- крадётся к экспонату на цыпочках
	Run = "Run", -- убегает от охранника или загораживает путь
	Steal = "Steal", -- оглядывается и снимает экспонат
	Carry = "Carry", -- несёт экспонат над головой
	Arrest = "Arrest", -- руки вверх, потом руки вперёд в наручники
	-- блок 3
	Kick = "Kick", -- пинает витрину (шумит, чтобы выманить охрану)
	Hold = "Hold", -- присел и ждёт во входном холле, выглядывает
	Stomp = "Stomp", -- Громила: тяжёлая походка вразвалку
	Punch = "Punch", -- Громила: замах и удар правой
	Smash = "Smash", -- Громила: бьёт витрину двумя руками сверху
	Prowl = "Prowl", -- Тень: крадётся на полусогнутых
	Climb = "Climb", -- Шахтёр вылезает из дыры, Стекольщик лезет вверх по верёвке
	Rappel = "Rappel", -- Стекольщик спускается на верёвке
	Cut = "Cut", -- Стекольщик на коленях режет круг в стекле
	Work = "Work", -- Светорез возится у щитка с кусачками
	Patrol = "Patrol", -- Фальшивый охранник: спокойно ходит и стоит, руки за спиной
	-- блок 4
	Stunned = "Stunned", -- шокер: упал на спину, дёргается, звёздочки
}

-- Атрибуты модели вора (пишет сервер).
GameState.ThiefAttr = {
	Kind = "ThiefKind", -- string, вид вора (Config.ThiefTypes)
	Disguise = "Disguise", -- string?, Фальшивый охранник: чей ник у него над головой (пока он не схватил экспонат)
	Robber = "Robber", -- boolean, грабитель налёта (блок 4): в него попадают пули
	RobberRole = "RobberRole", -- string, "Gunner" | "Grabber"
	Surrendered = "Surrendered", -- boolean, сдался полиции: руки вверх
}

-- Залы музея. Главный (центр, коридоры, входные холлы) открыт всегда,
-- 4 зала по углам открываются за деньги (вскладчину).
GameState.Hall = {
	Main = "Main",
	Sculptures = "Sculptures",
	Dinosaurs = "Dinosaurs",
	Jewelry = "Jewelry",
	Space = "Space",
}

-- Залы за деньги по порядку цены (для подсказок и проверок).
GameState.PaidHalls = { "Sculptures", "Dinosaurs", "Jewelry", "Space" }

-- Атрибуты точки камеры (Map.CameraPoints.CameraN). Пишет только сервер.
GameState.CameraAttr = {
	Index = "Index", -- number, номер камеры (1..N)
	Hall = "Hall", -- string, зал: камера закрытого зала не работает
	Owned = "Owned", -- boolean, камера куплена (первая — бесплатная)
	Broken = "Broken", -- boolean, сломал вор-взломщик
	StandPoint = "StandPoint", -- Vector3, где на полу встаёт взломщик, чтобы сломать камеру
}

-- Атрибуты двери, которая открывается сама (Map.Doors): сервер решает, клиенты двигают створки.
GameState.DoorAttr = {
	Open = "Open", -- boolean, у модели двери
	SlideX = "SlideX", -- number, у створки: на сколько она сдвигается вдоль своей оси X, когда дверь открыта
}

-- Атрибут GameState «зал открыт»: HallOpen_Jewelry и т.д.
function GameState.hallOpenAttr(hall: string): string
	return "HallOpen_" .. hall
end

-- Открыт ли зал (атрибут Hall у детали карты; без атрибута — главный зал).
function GameState.isHallOpen(hall: any): boolean
	if hall == nil or hall == GameState.Hall.Main then
		return true
	end
	return GameState.get(GameState.hallOpenAttr(hall)) == true
end

GameState.TouristAnim = {
	Stroll = "Stroll", -- спокойно гуляет
	Admire = "Admire", -- стоит у экспоната, руки за спиной
	Photo = "Photo", -- фотографирует экспонат
}

-- Кнопки покупки (Purchase.luau на сервере, BuyPrompts.client на клиенте): тег и атрибуты ProximityPrompt.
GameState.BuyPrompt = {
	Tag = "BuyPrompt",
	Price = "BuyPrice", -- number, полная цена
	Paid = "BuyPaid", -- number, сколько уже вложили вскладчину
	-- блок 4: личные покупки оружейной (без складчины)
	Item = "BuyItem", -- string, товар из Config.Armory.Goods
	Open = "BuyOpen", -- boolean, покупать сейчас можно (днём); видна ли кнопка игроку, решает его клиент по своим вещам
}

-- Что будет, если удержать кнопку покупки (решение 67): хватает денег на остаток — «Buy $остаток»,
-- не хватает — «Put in $все деньги», денег нет совсем — «Need $остаток».
function GameState.buyActionText(remaining: number, money: number): string
	local left = math.max(0, math.floor(remaining))
	local cash = math.max(0, math.floor(money))
	if cash >= left then
		return ("Buy $%d"):format(left)
	elseif cash > 0 then
		return ("Put in $%d"):format(cash)
	end
	return ("Need $%d"):format(left)
end

-- Атрибуты ReplicatedStorage.GameState
GameState.Attr = {
	Phase = "Phase", -- string, одна из GameState.Phase
	PhaseEndsAt = "PhaseEndsAt", -- number, workspace:GetServerTimeNow(); 0 — таймера нет
	NightStartedAt = "NightStartedAt", -- number, для часов 00:00 -> 06:00
	PaintingStolen = "PaintingStolen", -- boolean, картину сейчас несёт вор
	StealEndsAt = "StealEndsAt", -- number, когда вор снимет картину; 0 — никто не снимает
	Caught = "Caught", -- number, поймано воров за ночь
	ThievesSpawned = "ThievesSpawned", -- number, сколько воров уже пришло
	Solo = "Solo", -- boolean, в игре один игрок
	NightNumber = "NightNumber", -- number, какая по счёту ночь идёт (или будет после этого дня)
	BestNights = "BestNights", -- number, рекорд сервера: сколько ночей продержались
	TouristsToday = "TouristsToday", -- number, сколько туристов пришло за день
	Blackout = "Blackout", -- boolean, Светорез вырубил свет и камеры (блок 3)
	Raid = "Raid", -- boolean, идёт налёт: огнестрел можно достать (блок 4)
	PoliceAt = "PoliceAt", -- number, когда приедет полиция (0 — налёта нет); вверху POLICE: 60
	PoliceArrived = "PoliceArrived", -- boolean, полиция приехала: грабители сдаются
}

-- Атрибуты Player
GameState.PlayerAttr = {
	Role = "Role", -- string, GameState.Role
	InTeam = "InTeam", -- boolean, стоит в круге START SHIFT в лобби и попал в команду (не больше 5)
	InRound = "InRound", -- boolean, игрок участвует в текущей ночи
	ViewingCameras = "ViewingCameras", -- boolean, открыт телефон или пульт
	ViewSource = "ViewSource", -- string: "Phone" | "Console"
	Money = "Money", -- number, доллары за этот забег
	JoinStatus = "JoinStatus", -- string?, опоздавший: Voting | Approved | Rejected | Full
	KnockedAt = "KnockedAt", -- number, когда Громила сбил охранника с ног (workspace:GetServerTimeNow())
	KnockedUntil = "KnockedUntil", -- number, до какого времени охранник лежит
	-- блок 4: здоровье (пишет HealthService)
	Health = "Health", -- number, здоровье охранника (0..MaxHealth)
	MaxHealth = "MaxHealth", -- number
	Armor = "Armor", -- number, броня бронежилета (0 — жилета нет)
	Downed = "Downed", -- boolean, здоровье кончилось: лежит и ползёт, ждёт друга
	DownedAt = "DownedAt", -- number, когда упал (для анимации)
	RevivedAt = "RevivedAt", -- number, когда друг поднял (анимация «встаёт»)
	ReviveTarget = "ReviveTarget", -- number, UserId друга, которого этот игрок сейчас поднимает (0 — никого)
	RevivedBy = "RevivedBy", -- number, UserId того, кто поднимает лежащего (0 — никто)
	ReviveStartedAt = "ReviveStartedAt", -- number, когда начали поднимать (полоска у лежащего)
	-- блок 4: стойка (пишет WeaponService по просьбе клиента)
	Crouch = "Crouch", -- boolean, присел
	Lean = "Lean", -- number, наклон: -1 влево, 0 нет, 1 вправо
	-- блок 4: оружие (пишет WeaponService); патроны — атрибуты GameState.ammoAttr / reserveAttr
	HasTaser = "HasTaser", -- boolean
	HasPistol = "HasPistol", -- boolean
	Primary = "Primary", -- string: "" | "Rifle" | "Shotgun"
	Medkits = "Medkits", -- number, аптечек с собой
	Equipped = "Equipped", -- string, что в руках: "" | "Rifle" | "Shotgun" | "Pistol" | "Taser" | "Medkit"
	TaserReadyAt = "TaserReadyAt", -- number, когда шокер снова заряжен
	ReloadUntil = "ReloadUntil", -- number, перезарядка кончится (0 — не перезаряжает)
	HealUntil = "HealUntil", -- number, аптечка подействует (0 — не лечится)
}

-- Патронов в магазине и в запасе у оружия (Pistol, Rifle, Shotgun).
function GameState.ammoAttr(weapon: string): string
	return "Ammo" .. weapon
end

function GameState.reserveAttr(weapon: string): string
	return "Reserve" .. weapon
end

-- Можно ли игроку купить товар оружейной (блок 4) и что будет: "Buy" — купить, "Swap" — основное оружие
-- заменит другое (автомат ↔ дробовик). show = false — уже есть, полная броня, аптечек с собой максимум,
-- патроны к оружию, которого нет, или запас полный. Сервер проверяет этим же, клиент — прячет кнопку.
function GameState.armoryOffer(player: Player, item: string): (boolean, string)
	local good = (Config.Armory.Goods :: any)[item]
	if not good then
		return false, "Buy"
	end
	local attr = GameState.PlayerAttr
	if good.Kind == "Weapon" then
		if GameState.hasWeapon(player, item) then
			return false, "Buy"
		end
		local primary = player:GetAttribute(attr.Primary)
		if (item == "Rifle" or item == "Shotgun") and typeof(primary) == "string" and primary ~= "" then
			return true, "Swap"
		end
		return true, "Buy"
	elseif good.Kind == "Vest" then
		return (tonumber(player:GetAttribute(attr.Armor)) or 0) < Config.Weapons.Vest.Armor, "Buy"
	elseif good.Kind == "Medkit" then
		return (tonumber(player:GetAttribute(attr.Medkits)) or 0) < Config.Weapons.Medkit.MaxCarry, "Buy"
	elseif good.Kind == "Ammo" then
		local weapon = good.Weapon
		local info = (Config.Weapons :: any)[weapon]
		if not info or not GameState.hasWeapon(player, weapon) then
			return false, "Buy"
		end
		return (tonumber(player:GetAttribute(GameState.reserveAttr(weapon))) or 0) < info.MaxReserve, "Buy"
	end
	return false, "Buy"
end

-- Есть ли у игрока это оружие (Taser, Pistol, Rifle, Shotgun).
function GameState.hasWeapon(player: Player, weapon: string): boolean
	if weapon == "Taser" then
		return player:GetAttribute(GameState.PlayerAttr.HasTaser) == true
	elseif weapon == "Pistol" then
		return player:GetAttribute(GameState.PlayerAttr.HasPistol) == true
	end
	return weapon ~= "" and player:GetAttribute(GameState.PlayerAttr.Primary) == weapon
end

local FOLDER_NAME = "GameState"

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function GameState.folder(): Folder
	return folder
end

function GameState.get(attr: string): any
	return folder:GetAttribute(attr)
end

-- Только на сервере.
function GameState.set(attr: string, value: any)
	assert(RunService:IsServer(), "GameState.set вызывается только на сервере")
	folder:SetAttribute(attr, value)
end

function GameState.phase(): string
	local value = folder:GetAttribute(GameState.Attr.Phase)
	if typeof(value) == "string" then
		return value
	end
	return GameState.Phase.Lobby
end

-- Команда в лобби: кто стоит в круге START SHIFT (атрибут InTeam ставит сервер, LobbyService).
function GameState.lobbyTeam(): { Player }
	local team = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(GameState.PlayerAttr.InTeam) == true then
			table.insert(team, player)
		end
	end
	return team
end

-- Какая часть ночи прошла: 0 — полночь, 1 — 06:00. Ночь бывает разной длины (решение 66),
-- поэтому длину берём из времени начала ночи и конца фазы.
function GameState.nightProgress(): number
	local started = folder:GetAttribute(GameState.Attr.NightStartedAt)
	local endsAt = folder:GetAttribute(GameState.Attr.PhaseEndsAt)
	if typeof(started) ~= "number" or typeof(endsAt) ~= "number" or endsAt <= started then
		return 0
	end
	return math.clamp((workspace:GetServerTimeNow() - started) / (endsAt - started), 0, 1)
end

function GameState.secondsLeft(): number
	local endsAt = folder:GetAttribute(GameState.Attr.PhaseEndsAt)
	if typeof(endsAt) ~= "number" or endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

return GameState
