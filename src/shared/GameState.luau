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

-- Классы игроков (блок 5): значение атрибута Role. Числа и умения — Config.Classes.
GameState.Role = {
	Patrol = "Patrol",
	Operator = "Operator",
	Technician = "Technician",
	DogHandler = "DogHandler",
	Assault = "Assault",
}

-- Описание класса из Config.Classes (Title, Ability, числа). nil — такого класса нет.
function GameState.classInfo(role: any): { [string]: any }?
	if typeof(role) ~= "string" or not table.find(Config.Classes.Order, role) then
		return nil
	end
	return (Config.Classes :: any)[role]
end

-- Класс игрока (если атрибута нет или он странный — класс по умолчанию).
function GameState.roleOf(player: Player): string
	local role = player:GetAttribute(GameState.PlayerAttr.Role)
	if GameState.classInfo(role) then
		return role :: string
	end
	return Config.Classes.Default
end

-- Сколько здоровья у охранника этого класса (Штурмовик — больше).
function GameState.maxHealthFor(player: Player): number
	if GameState.roleOf(player) == GameState.Role.Assault then
		return Config.Classes.Assault.AssaultHealth
	end
	return Config.Health.Max
end

-- Отдача оружия у этого класса (Штурмовик — меньше): множитель.
function GameState.recoilFor(player: Player): number
	if GameState.roleOf(player) == GameState.Role.Assault then
		return Config.Classes.Assault.AssaultRecoil
	end
	return 1
end

-- Атрибуты собаки кинолога (модель в Workspace.Dogs, блок 5). Пишет сервер, двигают собаку клиенты.
GameState.DogAttr = {
	Owner = "Owner", -- number, UserId хозяина
	SpawnPivot = "SpawnPivot", -- CFrame, где сервер поставил модель (от него клиенты считают положение деталей)
	PartCount = "PartCount", -- number, сколько деталей в модели (клиент ждёт, пока придут все)
	Alert = "Alert", -- boolean, рядом вор: собака смотрит на него, над ней «!» (вор — ObjectValue Target)
	BarkAt = "BarkAt", -- number, когда собака гавкнула (workspace:GetServerTimeNow())
}

-- Атрибуты датчика движения техника (модель в Workspace.Sensors, блок 5).
GameState.SensorAttr = {
	Owner = "Owner", -- number, UserId техника
	PlacedAt = "PlacedAt", -- number, когда поставили (анимация раскладывания)
	PingAt = "PingAt", -- number, когда рядом прошёл вор: писк и стрелка у всей охраны
	Radius = "Radius", -- number, докуда видит
}

-- Атрибуты круга-команды в хабе (Map.TeamPads.TeamPadN, блок 6). Пишет сервер (PadService), клиенты показывают.
GameState.PadAttr = {
	Index = "Index", -- number, номер круга 1..5
	Team = "Team", -- string, UserId команды через запятую, по порядку входа (первый — создатель)
	FriendsOnly = "FriendsOnly", -- boolean, создатель пускает только друзей
	EndsAt = "EndsAt", -- number, когда кончится отсчёт (workspace:GetServerTimeNow()); 0 — отсчёта нет
	State = "State", -- string, GameState.PadState
	Message = "Message", -- string, надпись на табличке («Teleport works only in the published game»)
}

GameState.PadState = {
	Open = "Open", -- ждёт игроков, идёт отсчёт
	Launching = "Launching", -- команда телепортируется
	Blocked = "Blocked", -- телепорт не работает (Studio) или не удался: надпись, потом снова Open
}

-- Команда круга хаба из атрибута Team: список UserId.
function GameState.padTeam(pad: Instance): { number }
	local ids = {}
	local text = pad:GetAttribute(GameState.PadAttr.Team)
	if typeof(text) == "string" then
		for piece in string.gmatch(text, "-?%d+") do
			table.insert(ids, tonumber(piece) :: number)
		end
	end
	return ids
end

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
	-- грабители налёта (у модели атрибут RobberGun: "Pistol" | "Rifle" | "" — у хватальщика дубинка)
	Advance = "Advance", -- бежит к укрытию, оружие у груди
	Aim = "Aim", -- целится и стреляет (выглянул из-за укрытия)
	Cover = "Cover", -- сидит за укрытием, оружие стволом вверх, выглядывает
	Throw = "Throw", -- кидает дымовую шашку
	Strike = "Strike", -- удар дубинкой (хватальщик) или прикладом (стрелок)
	Surrender = "Surrender", -- сдался: руки вверх
	Knockout = "Knockout", -- «убит»: упал на спину со звёздочками
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

-- Крылья (этап 5, блок B): коридор + входной холл стороны. Покупаются (WingService); открыто ли — тот же атрибут
-- «зал открыт» (HallOpen_WingSouth), поэтому пол, камеры и входы крыла работают через GameState.isHallOpen.
GameState.Wings = {
	South = "WingSouth",
	West = "WingWest",
	North = "WingNorth",
	East = "WingEast",
}
GameState.WingOrder = { "WingSouth", "WingWest", "WingNorth", "WingEast" }
function GameState.isWing(name: any): boolean
	return typeof(name) == "string" and table.find(GameState.WingOrder, name) ~= nil
end
-- Зал угла открывается только из своего крыла: купить зал можно, когда крыло открыто.
GameState.HallWing = {
	Sculptures = "WingSouth",
	Dinosaurs = "WingWest",
	Jewelry = "WingNorth",
	Space = "WingEast",
}

-- Атрибуты точек входа (Map.Entrances): у двери центра и у наружной двери крыла.
GameState.EntranceAttr = {
	UntilWing = "UntilWing", -- string, крыло: вход работает, пока оно закрыто (дверь центра)
	HoldInside = "HoldInside", -- number, на сколько стадов за дверью воры ждут (иначе Config.Waves.Smart.HoldInside)
	HoldSpread = "HoldSpread", -- number, разброс места ожидания вбок
	DoorPoint = "DoorPoint", -- Vector3, середина двери этого входа на полу (этап 5, блок E: туристы уходят за неё)
	DoorOutward = "DoorOutward", -- Vector3, направление из музея наружу через эту дверь (по полу, длина 1)
}

-- Работает ли сейчас вход (точка в Map.Entrances): его зал открыт, а крыло, пока закрыто которое он работает, — закрыто.
function GameState.isEntranceOpen(marker: Instance): boolean
	local untilWing = marker:GetAttribute(GameState.EntranceAttr.UntilWing)
	if typeof(untilWing) == "string" and GameState.isHallOpen(untilWing) then
		return false
	end
	return GameState.isHallOpen(marker:GetAttribute("Hall"))
end

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
	Wing = "Wing", -- string, у двери центра (этап 5, блок B): крыло куплено — дверь открыта всегда (арка)
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

-- Окно магазина в музее (этап 4, блок 1b): товары лежат в ReplicatedStorage.Shop.<вкладка>.<id> (Configuration,
-- внутри — модель Preview для 3D-картинки). Пишет только сервер (ShopService), окно (Shop.client) читает.
GameState.ShopFolder = "Shop"
GameState.ShopAttr = {
	Title = "Title", -- string, название товара
	Info = "Info", -- string, одна строка описания
	Order = "Order", -- number, место во вкладке
	Price = "Price", -- number, полная цена
	Hall = "Hall", -- string, зал товара ("" — не привязан к залу): закрыт — HALL CLOSED
	Item = "Item", -- string, товар оружейной (Config.Armory.Goods): у каждого свой, что можно купить — GameState.armoryOffer
	Paid = "Paid", -- number, сколько уже вложили вскладчину (общие товары)
	Owned = "Owned", -- boolean, куплено (зал — открыт)
	Missing = "Missing", -- string, почему сейчас нельзя купить, кроме денег и зала («NO EXHIBIT»); "" — можно
}

-- Ответ сервера на покупку из окна (Remote ShopReply)
GameState.ShopReply = {
	Bought = "Bought", -- куплено: «Bought: Golden Vase»
	PutIn = "PutIn", -- деньги ушли в полоску складчины
	Fail = "Fail", -- не вышло (денег нет, зал закрыт, ночь…)
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
	-- блок 6: команда из хаба
	HubArrival = "HubArrival", -- boolean, музей ждёт команду из хаба (круг START SHIFT не работает)
	HubArrived = "HubArrived", -- number, сколько из команды уже прилетело
	HubExpected = "HubExpected", -- number, сколько всего в команде
}

-- Атрибуты Player
GameState.PlayerAttr = {
	Role = "Role", -- string, GameState.Role — класс игрока (блок 5)
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
	-- блок 5: умение класса (пишет AbilityService)
	AbilityReadyAt = "AbilityReadyAt", -- number, когда умение снова можно использовать (0 — готово)
	AbilityUntil = "AbilityUntil", -- number, умение действует до этого времени (рывок)
	AbilityCharges = "AbilityCharges", -- number, сколько раз ещё можно этой ночью (датчики техника)
	-- блок 6
	Pad = "Pad", -- number, в каком круге хаба стоит игрок и попал в команду (0 — ни в каком)
	EndChoice = "EndChoice", -- string, выбор в конце забега: "" | "PlayAgain" | "Lobby"
	-- этап 4, блок 1: профиль игрока (пишет ProfileStore; сохраняется навсегда)
	Diamonds = "Diamonds", -- number, алмазы 💎
	OwnedClasses = "OwnedClasses", -- string, купленные классы через запятую: "Patrol,Operator"
	ProfileStatus = "ProfileStatus", -- string, GameState.ProfileStatus
	-- этап 5, блок A: ежедневные подарки (пишет ProfileStore; сохраняется навсегда)
	GiftDay = "GiftDay", -- number, номер дня (UTC), когда игрок последний раз забрал подарок (0 — никогда)
	GiftStreak = "GiftStreak", -- number, какой это был день серии: 1–7
	-- этап 5, блок C: обучение со стрелками
	TutorialOff = "TutorialOff", -- boolean, игрок выключил обучение (пишет ProfileStore; сохраняется навсегда)
	RunSpent = "RunSpent", -- number, сколько долларов игрок потратил за забег (пишет Purchase; шаг «купи»)
	RunArrests = "RunArrests", -- number, сколько воров игрок арестовал за забег (пишет ScoreService; шаг «арестуй»)
	ShopOpen = "ShopOpen", -- boolean, ТОЛЬКО НА КЛИЕНТЕ: открыто окно магазина (пишет Shop.client, читает Tutorial)
	Spectating = "Spectating", -- boolean, ТОЛЬКО НА КЛИЕНТЕ: игрок в режиме зрителя (пишет Spectate.client)
	-- этап 6, блок H1: прогресс игрока (пишет ProfileStore; сохраняется навсегда, shared/Progress)
	Xp = "Xp", -- number, весь опыт
	Level = "Level", -- number, уровень (по опыту)
	Quests = "Quests", -- string, JSON: день и 3 задания дня с прогрессом (Progress.decodeQuests)
	Stats = "Stats", -- string, JSON: счётчики, виды арестованных воров, достижения (Progress.decodeStats)
	FreeTries = "FreeTries", -- number, сколько осталось бесплатных забегов некупленным классом (подарок новичку)
	-- этап 6, блок H2: рекорды друзей (пишет FriendService) — JSON [{ n = имя, v = ночей }] по убыванию; "" — скрыто
	FriendRecords = "FriendRecords",
	TrialClass = "TrialClass", -- string, музей: класс этого забега взят на пробу (после забега снова закрыт); "" — нет
}

-- Профиль игрока (этап 4, блок 1): загружен ли он из DataStore.
GameState.ProfileStatus = {
	Loading = "Loading", -- ещё грузится: пока открыты только бесплатные классы
	Ready = "Ready", -- загружен и сохраняется
	Offline = "Offline", -- Studio без доступа к API: все классы открыты, алмазы не сохраняются
	Error = "Error", -- Roblox не ответил: пробуем снова, пока открыты только бесплатные классы
}

-- Цена класса в алмазах 💎 (0 — бесплатный).
function GameState.classPrice(role: any): number
	local info = GameState.classInfo(role)
	return if info then math.max(0, tonumber(info.Price) or 0) else 0
end

-- Есть ли у игрока этот класс (по атрибутам профиля, их пишет только сервер). Бесплатный — есть у всех.
-- Для клиента — показать замок; сервер решает сам (ProfileStore.owns) по тем же правилам.
function GameState.ownsClass(player: Player, role: any): boolean
	if not GameState.classInfo(role) then
		return false
	end
	if GameState.classPrice(role) <= 0 then
		return true
	end
	if player:GetAttribute(GameState.PlayerAttr.ProfileStatus) == GameState.ProfileStatus.Offline then
		return true
	end
	local owned = player:GetAttribute(GameState.PlayerAttr.OwnedClasses)
	if typeof(owned) ~= "string" then
		return false
	end
	for name in string.gmatch(owned, "[^,]+") do
		if name == role then
			return true
		end
	end
	return false
end

-- Номер дня по UTC для времени seconds (os.time() на сервере, workspace:GetServerTimeNow() на клиенте).
function GameState.dayNumber(seconds: number): number
	return math.floor(seconds / Config.DailyGift.DaySeconds)
end

-- Ежедневный подарок (этап 5, блок A): можно ли забрать сегодня и какой это будет день серии.
-- Последний раз забрал вчера — серия +1 (после 7-го снова 1-й), раньше или никогда — снова 1-й.
-- Сервер проверяет по сохранённым данным (ProfileStore), клиент — по атрибутам, чтобы показать окно.
function GameState.giftNext(giftDay: number, giftStreak: number, today: number): (boolean, number)
	if today <= giftDay then
		return false, giftStreak
	end
	if today == giftDay + 1 and giftStreak >= 1 then
		return true, (giftStreak % #Config.DailyGift.Rewards) + 1
	end
	return true, 1
end

-- Алмазы игрока (атрибут профиля).
function GameState.diamondsOf(player: Player): number
	return tonumber(player:GetAttribute(GameState.PlayerAttr.Diamonds)) or 0
end

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
