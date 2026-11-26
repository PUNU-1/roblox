-- Профиль игрока (этап 4, блок 1, решение 74): алмазы 💎 и купленные классы — навсегда. Общий для хаба и музея
-- (hub.project.json подключает этот файл). DataStore Config.Diamonds.Store, ключ — UserId,
-- данные { diamonds = 120, ownedClasses = { Patrol = true, Operator = true }, giftDay = 20418, giftStreak = 3 }.
-- Этап 5, блок A: ежедневный подарок (giftDay — номер дня UTC, когда забрал, giftStreak — день серии 1–7)
-- забирается тоже внутри UpdateAsync, как покупка класса.
-- Этап 5, блок C: настройка «обучение выключено» (tutorialOff) — Remote SetTutorial, хаб и музей.
--
-- Правило 5 из CLAUDE.md: только UpdateAsync в pcall с повтором (Retry). Каждое изменение сохраняется сразу:
-- алмазы — разницей (pending), поэтому, даже если запись не удалась, ничего не теряется — она уйдёт со следующей
-- попыткой (новое начисление, выход игрока, закрытие сервера). Покупка класса — тоже внутри UpdateAsync:
-- цена и «уже куплен» проверяются по сохранённым данным, а не по кэшу.
--
-- Клиенты видят профиль атрибутами игрока (Diamonds, OwnedClasses, ProfileStatus, GiftDay, GiftStreak, TutorialOff), пишет их
-- только этот модуль.
-- Studio без доступа к API: все классы открыты, алмазы считаются в памяти и не сохраняются (статус Offline).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retry = require(script.Parent:WaitForChild("Retry"))

local Settings = Config.Diamonds
local PlayerAttr = GameState.PlayerAttr
local Status = GameState.ProfileStatus

local ProfileStore = {}

type Profile = {
	userId: number,
	diamonds: number, -- сколько видит игрок (сохранённое + ещё не записанное)
	owned: { [string]: boolean },
	giftDay: number, -- номер дня UTC, когда последний раз забрал подарок (0 — никогда)
	giftStreak: number, -- какой это был день серии (1–7)
	tutorialOff: boolean, -- игрок выключил обучение (этап 5, блок C)
	status: string, -- GameState.ProfileStatus
	pending: number, -- алмазы, которые ещё не записаны в DataStore
	busy: boolean, -- идёт запрос к DataStore (запросы одного игрока — по очереди)
}

local profiles: { [Player]: Profile } = {}
local offline = false -- Studio без доступа к API: всё только в памяти
local inflight = 0 -- сколько запросов к DataStore идёт сейчас (BindToClose ждёт их)
local started = false
local lastToggle: { [Player]: number } = {} -- когда игрок последний раз менял настройку обучения (SetTutorial)

local function key(userId: number): string
	return tostring(userId)
end

-- Сохранённые данные профиля после проверки
type Data = {
	diamonds: number,
	owned: { [string]: boolean },
	giftDay: number,
	giftStreak: number,
	tutorialOff: boolean,
}

-- Данные из DataStore → алмазы, классы и подарки. Чужие и сломанные поля отбрасываются.
local function clean(data: any): Data
	local diamonds = 0
	local owned: { [string]: boolean } = {}
	local giftDay, giftStreak = 0, 0
	local tutorialOff = false
	if typeof(data) == "table" then
		tutorialOff = data.tutorialOff == true
		diamonds = math.max(0, math.floor(tonumber(data.diamonds) or 0))
		giftDay = math.max(0, math.floor(tonumber(data.giftDay) or 0))
		giftStreak = math.clamp(math.floor(tonumber(data.giftStreak) or 0), 0, #Config.DailyGift.Rewards)
		if typeof(data.ownedClasses) == "table" then
			for name, value in data.ownedClasses do
				if value == true and GameState.classInfo(name) then
					owned[name] = true
				end
			end
		end
	end
	for _, name in Config.Classes.Order do
		if GameState.classPrice(name) <= 0 then
			owned[name] = true -- бесплатные классы есть у всех
		end
	end
	return { diamonds = diamonds, owned = owned, giftDay = giftDay, giftStreak = giftStreak, tutorialOff = tutorialOff }
end

local function pack(data: Data): { [string]: any }
	local classes = {}
	for name in data.owned do
		classes[name] = true
	end
	return {
		diamonds = math.max(0, math.floor(data.diamonds)),
		ownedClasses = classes,
		giftDay = data.giftDay,
		giftStreak = data.giftStreak,
		tutorialOff = data.tutorialOff,
	}
end

-- Профиль → атрибуты игрока (их видят клиенты: алмазы вверху, замки на карточках, витрина).
local function publish(player: Player, profile: Profile)
	if not player.Parent then
		return
	end
	local names = {}
	for _, name in Config.Classes.Order do
		if profile.owned[name] then
			table.insert(names, name)
		end
	end
	player:SetAttribute(PlayerAttr.Diamonds, profile.diamonds)
	player:SetAttribute(PlayerAttr.OwnedClasses, table.concat(names, ","))
	player:SetAttribute(PlayerAttr.GiftDay, profile.giftDay)
	player:SetAttribute(PlayerAttr.GiftStreak, profile.giftStreak)
	player:SetAttribute(PlayerAttr.TutorialOff, profile.tutorialOff)
	player:SetAttribute(PlayerAttr.ProfileStatus, profile.status)
end

-- Запросы к DataStore одного игрока идут по очереди: начисление не перебьёт покупку.
local function lock(profile: Profile)
	inflight += 1
	while profile.busy do
		task.wait(0.1)
	end
	profile.busy = true
end

local function unlock(profile: Profile)
	profile.busy = false
	inflight -= 1
end

-- Один UpdateAsync: прибавляет ещё не записанные алмазы (pending) и, если надо, что-то меняет (change).
-- После удачи кэш берётся из сохранённых данных. Возвращает, удалось ли.
local function update(profile: Profile, change: ((data: Data) -> ())?): (boolean, string?)
	local delta = profile.pending
	local attempts = if RunService:IsStudio() then 1 else Settings.Retries -- в Studio без API ошибка сразу и навсегда
	local ok, result = Retry.call(attempts, Settings.RetryDelay, function()
		local store = DataStoreService:GetDataStore(Settings.Store)
		return store:UpdateAsync(key(profile.userId), function(old: any): any
			local data = clean(old)
			data.diamonds = math.max(0, data.diamonds + delta)
			if change then
				change(data)
			end
			return pack(data)
		end)
	end)
	if not ok then
		return false, tostring(result)
	end
	profile.pending -= delta
	local data = clean(result)
	profile.diamonds = data.diamonds + profile.pending
	profile.owned = data.owned
	profile.giftDay = data.giftDay
	profile.giftStreak = data.giftStreak
	profile.tutorialOff = data.tutorialOff
	profile.status = Status.Ready
	return true, nil
end

-- Записать ещё не записанные алмазы (и заодно загрузить профиль, если он ещё не загружен).
local function sync(player: Player, profile: Profile)
	if offline or profile.status == Status.Offline then
		return
	end
	lock(profile)
	if profile.pending ~= 0 or profile.status ~= Status.Ready then
		local ok, err = update(profile, nil)
		if not ok then
			if profile.status == Status.Loading then
				if RunService:IsStudio() then
					-- Studio без доступа к API: дальше всё в памяти, все классы открыты
					offline = true
					print("[ProfileStore] DataStore недоступен в Studio — алмазы не сохраняются, все классы открыты")
				else
					profile.status = Status.Error
					warn(("[ProfileStore] Не удалось загрузить профиль %d: %s"):format(profile.userId, tostring(err)))
				end
			else
				warn(("[ProfileStore] Не удалось сохранить профиль %d (повторим позже): %s"):format(profile.userId, tostring(err)))
			end
			if offline then
				profile.status = Status.Offline
			end
		end
	end
	unlock(profile)
	publish(player, profile)
end

local function newProfile(player: Player): Profile
	local data = clean(nil)
	return {
		userId = player.UserId,
		diamonds = data.diamonds,
		owned = data.owned,
		giftDay = data.giftDay,
		giftStreak = data.giftStreak,
		tutorialOff = data.tutorialOff,
		status = if offline then Status.Offline else Status.Loading,
		pending = 0,
		busy = false,
	}
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local profile = newProfile(player)
	profiles[player] = profile
	publish(player, profile)
	sync(player, profile)
	-- Roblox не ответил — пробуем снова, пока игрок на сервере
	while player.Parent and profiles[player] == profile and profile.status == Status.Error do
		task.wait(Settings.ReloadSeconds)
		if player.Parent and profiles[player] == profile then
			sync(player, profile)
		end
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	-- Последняя попытка записать то, что не записалось; профиль забываем после неё
	if profile.pending ~= 0 and profile.status ~= Status.Offline and not offline then
		sync(player, profile)
	end
	if profiles[player] == profile then
		profiles[player] = nil
	end
	lastToggle[player] = nil
end

---------------------------------------------------------------- для других сервисов

function ProfileStore.init()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Обучение вкл / выкл (этап 5, блок C): аргумент — только boolean, не чаще раза в ToggleCooldown сек
	Remotes.get(Remotes.Names.SetTutorial).OnServerEvent:Connect(function(player: Player, on: any)
		if typeof(on) ~= "boolean" then
			return
		end
		local now = os.clock()
		if lastToggle[player] and now - lastToggle[player] < Config.Tutorial.ToggleCooldown then
			return
		end
		lastToggle[player] = now
		ProfileStore.setTutorial(player, on)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	-- Сервер закрывается: дописать всё, что не записано, и дождаться идущих запросов
	game:BindToClose(function()
		for player, profile in profiles do
			if profile.pending ~= 0 and not offline and profile.status ~= Status.Offline then
				task.spawn(sync, player, profile)
			end
		end
		local deadline = os.clock() + Settings.CloseWaitSeconds
		task.wait(0.1)
		while inflight > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

-- Алмазы в памяти и не сохраняются (Studio без доступа к API).
function ProfileStore.isOffline(): boolean
	return offline
end

-- Ждёт, пока профиль загрузится (или станет ясно, что не загрузится), не дольше timeout. true — загружен.
function ProfileStore.waitLoaded(player: Player, timeout: number): boolean
	local deadline = os.clock() + timeout
	while player.Parent and os.clock() < deadline do
		local profile = profiles[player]
		if profile and profile.status ~= Status.Loading then
			break
		end
		task.wait(0.2)
	end
	local profile = profiles[player]
	return profile ~= nil and (profile.status == Status.Ready or profile.status == Status.Offline)
end

-- Есть ли у игрока класс. Бесплатный — у всех; пока профиль не загружен — только бесплатные;
-- в Studio без доступа к API — все.
function ProfileStore.owns(player: Player, role: any): boolean
	if not GameState.classInfo(role) then
		return false
	end
	if GameState.classPrice(role) <= 0 then
		return true
	end
	local profile = profiles[player]
	if not profile then
		return false
	end
	if offline or profile.status == Status.Offline then
		return true
	end
	return profile.status == Status.Ready and profile.owned[role] == true
end

function ProfileStore.diamonds(player: Player): number
	local profile = profiles[player]
	return if profile then profile.diamonds else 0
end

-- Начислить алмазы (итог ночи). Игрок видит их сразу, запись в DataStore — тут же, в фоне.
function ProfileStore.addDiamonds(player: Player, amount: number)
	local profile = profiles[player]
	local value = math.floor(tonumber(amount) or 0)
	if not profile or value <= 0 then
		return
	end
	profile.diamonds += value
	if not offline and profile.status ~= Status.Offline then
		profile.pending += value
		task.spawn(sync, player, profile)
	end
	publish(player, profile)
end

-- Купить класс за алмазы. Цена и «уже куплен» проверяются по сохранённым данным внутри UpdateAsync.
-- Возвращает (удалось, текст для игрока).
function ProfileStore.buyClass(player: Player, role: any): (boolean, string)
	local info = GameState.classInfo(role)
	if not info then
		return false, "Unknown class"
	end
	local title = tostring(info.Title)
	local price = GameState.classPrice(role)
	local profile = profiles[player]
	if not profile then
		return false, "Try again in a moment"
	end
	if price <= 0 or ProfileStore.owns(player, role) then
		return false, title .. " is already yours"
	end
	if offline or profile.status == Status.Offline then
		return false, title .. " is already yours" -- в Studio без API все классы открыты
	end
	if profile.status ~= Status.Ready then
		return false, "Diamonds are loading — try again in a moment"
	end
	if profile.diamonds < price then
		return false, ("You need %d more 💎"):format(price - profile.diamonds)
	end

	lock(profile)
	local outcome = "error"
	local ok = update(profile, function(data: Data)
		if data.owned[role] then
			outcome = "owned"
			return
		elseif data.diamonds < price then
			outcome = "poor"
			return
		end
		outcome = "bought"
		data.owned[role] = true
		data.diamonds -= price
	end)
	unlock(profile)
	publish(player, profile)

	if not ok then
		return false, "The shop is not responding — try again"
	elseif outcome == "owned" then
		return false, title .. " is already yours"
	elseif outcome == "poor" then
		return false, ("You need %d more 💎"):format(math.max(1, price - profile.diamonds))
	end
	return true, title .. " unlocked!"
end

-- Забрать ежедневный подарок (этап 5, блок A). День и серия проверяются по сохранённым данным внутри UpdateAsync
-- (не по кэшу): забрать дважды за день нельзя, даже с двух серверов сразу. День — по времени сервера (UTC).
-- Возвращает (удалось, сколько алмазов, какой день серии, текст для игрока).
function ProfileStore.claimGift(player: Player): (boolean, number, number, string)
	local profile = profiles[player]
	if not profile then
		return false, 0, 0, "Try again in a moment"
	end
	local rewards = Config.DailyGift.Rewards
	local today = GameState.dayNumber(os.time())

	-- Studio без доступа к API: как алмазы — в памяти, не сохраняется
	if offline or profile.status == Status.Offline then
		local can, streak = GameState.giftNext(profile.giftDay, profile.giftStreak, today)
		if not can then
			return false, 0, profile.giftStreak, "Come back tomorrow for the next gift"
		end
		local reward = rewards[streak]
		profile.giftDay = today
		profile.giftStreak = streak
		profile.diamonds += reward
		publish(player, profile)
		return true, reward, streak, ("Day %d: +%d 💎 (not saved in Studio)"):format(streak, reward)
	end
	if profile.status ~= Status.Ready then
		return false, 0, 0, "Diamonds are loading — try again in a moment"
	end
	if not GameState.giftNext(profile.giftDay, profile.giftStreak, today) then
		return false, 0, profile.giftStreak, "Come back tomorrow for the next gift"
	end

	lock(profile)
	local outcome = "error"
	local reward, day = 0, 0
	local ok = update(profile, function(data: Data)
		local can, streak = GameState.giftNext(data.giftDay, data.giftStreak, today)
		if not can then
			outcome = "claimed"
			return
		end
		outcome = "gift"
		reward = rewards[streak]
		day = streak
		data.diamonds += reward
		data.giftDay = today
		data.giftStreak = streak
	end)
	unlock(profile)
	publish(player, profile)

	if not ok then
		return false, 0, 0, "Gifts are not responding — try again"
	elseif outcome ~= "gift" then
		return false, 0, profile.giftStreak, "Come back tomorrow for the next gift"
	end
	return true, reward, day, ("Day %d: +%d 💎"):format(day, reward)
end

-- Включить / выключить обучение навсегда (этап 5, блок C). Игрок видит сразу (атрибут TutorialOff), запись — в фоне.
-- Профиль ещё не загрузился или Roblox не ответил — настройка действует только до выхода (это не деньги, повторять
-- запись не стоит: игрок просто выключит ещё раз).
function ProfileStore.setTutorial(player: Player, on: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	local off = not on
	profile.tutorialOff = off
	publish(player, profile)
	if offline or profile.status == Status.Offline then
		return -- Studio без доступа к API: только в памяти
	end
	task.spawn(function()
		lock(profile)
		if profile.status == Status.Ready then
			local ok, err = update(profile, function(data: Data)
				data.tutorialOff = off
			end)
			if not ok then
				warn(("[ProfileStore] Не удалось сохранить настройку обучения %d: %s"):format(profile.userId, tostring(err)))
			end
		end
		profile.tutorialOff = off -- последнее нажатие игрока важнее того, что пришло из DataStore
		unlock(profile)
		publish(player, profile)
	end)
end

return ProfileStore
