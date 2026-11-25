-- Профиль игрока (этап 4, блок 1, решение 74): алмазы 💎 и купленные классы — навсегда. Общий для хаба и музея
-- (hub.project.json подключает этот файл). DataStore Config.Diamonds.Store, ключ — UserId,
-- данные { diamonds = 120, ownedClasses = { Patrol = true, Operator = true } }.
--
-- Правило 5 из CLAUDE.md: только UpdateAsync в pcall с повтором (Retry). Каждое изменение сохраняется сразу:
-- алмазы — разницей (pending), поэтому, даже если запись не удалась, ничего не теряется — она уйдёт со следующей
-- попыткой (новое начисление, выход игрока, закрытие сервера). Покупка класса — тоже внутри UpdateAsync:
-- цена и «уже куплен» проверяются по сохранённым данным, а не по кэшу.
--
-- Клиенты видят профиль атрибутами игрока (Diamonds, OwnedClasses, ProfileStatus), пишет их только этот модуль.
-- Studio без доступа к API: все классы открыты, алмазы считаются в памяти и не сохраняются (статус Offline).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Retry = require(script.Parent:WaitForChild("Retry"))

local Settings = Config.Diamonds
local PlayerAttr = GameState.PlayerAttr
local Status = GameState.ProfileStatus

local ProfileStore = {}

type Profile = {
	userId: number,
	diamonds: number, -- сколько видит игрок (сохранённое + ещё не записанное)
	owned: { [string]: boolean },
	status: string, -- GameState.ProfileStatus
	pending: number, -- алмазы, которые ещё не записаны в DataStore
	busy: boolean, -- идёт запрос к DataStore (запросы одного игрока — по очереди)
}

local profiles: { [Player]: Profile } = {}
local offline = false -- Studio без доступа к API: всё только в памяти
local inflight = 0 -- сколько запросов к DataStore идёт сейчас (BindToClose ждёт их)
local started = false

local function key(userId: number): string
	return tostring(userId)
end

-- Данные из DataStore → алмазы и классы. Чужие и сломанные поля отбрасываются.
local function clean(data: any): (number, { [string]: boolean })
	local diamonds = 0
	local owned: { [string]: boolean } = {}
	if typeof(data) == "table" then
		diamonds = math.max(0, math.floor(tonumber(data.diamonds) or 0))
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
	return diamonds, owned
end

local function pack(diamonds: number, owned: { [string]: boolean }): { [string]: any }
	local classes = {}
	for name in owned do
		classes[name] = true
	end
	return { diamonds = math.max(0, math.floor(diamonds)), ownedClasses = classes }
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
local function update(profile: Profile, change: ((diamonds: number, owned: { [string]: boolean }) -> (number, { [string]: boolean }))?): (boolean, string?)
	local delta = profile.pending
	local attempts = if RunService:IsStudio() then 1 else Settings.Retries -- в Studio без API ошибка сразу и навсегда
	local ok, result = Retry.call(attempts, Settings.RetryDelay, function()
		local store = DataStoreService:GetDataStore(Settings.Store)
		return store:UpdateAsync(key(profile.userId), function(old: any): any
			local diamonds, owned = clean(old)
			diamonds = math.max(0, diamonds + delta)
			if change then
				diamonds, owned = change(diamonds, owned)
			end
			return pack(diamonds, owned)
		end)
	end)
	if not ok then
		return false, tostring(result)
	end
	profile.pending -= delta
	local diamonds, owned = clean(result)
	profile.diamonds = diamonds + profile.pending
	profile.owned = owned
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
	local diamonds, owned = clean(nil)
	return {
		userId = player.UserId,
		diamonds = diamonds,
		owned = owned,
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
end

---------------------------------------------------------------- для других сервисов

function ProfileStore.init()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
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
	local ok = update(profile, function(diamonds: number, owned: { [string]: boolean })
		if owned[role] then
			outcome = "owned"
			return diamonds, owned
		elseif diamonds < price then
			outcome = "poor"
			return diamonds, owned
		end
		outcome = "bought"
		owned[role] = true
		return diamonds - price, owned
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

return ProfileStore
