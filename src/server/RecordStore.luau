-- Рекорды команд (блок 6): сколько ночей продержалась команда. Два OrderedDataStore — за всё время и за
-- текущую неделю (своё хранилище на каждую неделю, поэтому «за неделю» само начинается с нуля по понедельникам).
-- Ключ — состав команды (UserId по возрастанию), значение — лучший результат этой команды.
-- Музей записывает рекорд в конце забега, хаб показывает топ-10 на доске. Общий модуль (hub.project.json).
-- Все запросы — в pcall с повтором (Retry). В Studio рекорды не пишутся: тестовые забеги не попадут на доску.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Retry = require(script.Parent:WaitForChild("Retry"))

local Settings = Config.Leaderboard
local WEEK_SECONDS = 7 * 24 * 60 * 60
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local RecordStore = {}
local inflight = 0

if not RunService:IsStudio() then
	game:BindToClose(function()
		local deadline = os.clock() + Config.Diamonds.CloseWaitSeconds
		task.wait(0.1)
		while inflight > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

export type Entry = {
	key: string,
	nights: number,
	userIds: { number },
}

local function base36(value: number): string
	local n = math.floor(value)
	if n <= 0 then
		return "0"
	end
	local out = ""
	while n > 0 do
		local digit = n % 36
		out = string.sub(DIGITS, digit + 1, digit + 1) .. out
		n = n // 36
	end
	return out
end

-- Ключ команды: UserId по возрастанию в 36-ричной записи через «_» (5 игроков — около 40 символов, лимит 50).
function RecordStore.teamKey(userIds: { number }): string
	local sorted = table.clone(userIds)
	table.sort(sorted)
	local parts = {}
	for _, id in sorted do
		table.insert(parts, base36(id))
	end
	return table.concat(parts, "_")
end

function RecordStore.decodeKey(key: string): { number }
	local ids = {}
	for piece in string.gmatch(key, "[^_]+") do
		local id = tonumber(piece, 36)
		if id then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Номер недели: неделя начинается в понедельник 00:00 UTC.
function RecordStore.weekNumber(time: number?): number
	return math.floor(((time or os.time()) - Settings.WeekOffsetSeconds) / WEEK_SECONDS)
end

local function storeName(scope: string): string
	if scope == "Weekly" then
		return Settings.WeeklyStorePrefix .. tostring(RecordStore.weekNumber())
	end
	return Settings.AllTimeStore
end

-- Музей, конец забега: команда продержалась nights ночей. Остаётся лучший результат команды (UpdateAsync).
function RecordStore.submit(userIds: { number }, nights: number): boolean
	if #userIds == 0 or nights < Settings.MinNights or RunService:IsStudio() then
		return false
	end
	local key = RecordStore.teamKey(userIds)
	local allOk = true
	for _, scope in { "AllTime", "Weekly" } do
		local name = storeName(scope)
		local ok, err = Retry.call(Settings.Retries, Settings.RetryDelay, function()
			local store = DataStoreService:GetOrderedDataStore(name)
			store:UpdateAsync(key, function(old: any): any
				local best = tonumber(old) or 0
				if nights <= best then
					return nil -- было не хуже — не переписываем
				end
				return math.floor(nights)
			end)
			return true
		end)
		if not ok then
			allOk = false
			warn(("[RecordStore] Не удалось записать рекорд в %s: %s"):format(name, tostring(err)))
		end
	end
	return allOk
end

-- То же, но не ждём ответа (игровой цикл не стоит, пока DataStore отвечает).
function RecordStore.submitAsync(userIds: { number }, nights: number)
	if #userIds == 0 or nights < Settings.MinNights or RunService:IsStudio() then
		return
	end
	inflight += 1
	local copy = table.clone(userIds)
	task.spawn(function()
		pcall(RecordStore.submit, copy, nights)
		inflight -= 1
	end)
end

-- Хаб: лучшие команды. scope — "AllTime" или "Weekly". nil и текст ошибки — хранилище недоступно
-- (например, Studio без доступа к API).
function RecordStore.top(scope: string, count: number): ({ Entry }?, string?)
	local name = storeName(scope)
	-- В Studio без доступа к API ошибка сразу и навсегда — повторять незачем
	local attempts = if RunService:IsStudio() then 1 else Settings.Retries
	local ok, result = Retry.call(attempts, Settings.RetryDelay, function()
		local store = DataStoreService:GetOrderedDataStore(name)
		local pages = store:GetSortedAsync(false, count)
		return pages:GetCurrentPage()
	end)
	if not ok or typeof(result) ~= "table" then
		return nil, tostring(result)
	end
	local entries: { Entry } = {}
	for _, item in result do
		if typeof(item) == "table" and typeof(item.key) == "string" then
			table.insert(entries, {
				key = item.key,
				nights = tonumber(item.value) or 0,
				userIds = RecordStore.decodeKey(item.key),
			})
		end
	end
	return entries, nil
end

return RecordStore
