-- Друзья по Roblox (этап 6, блок H2, решение 86). Общий для хаба и музея (hub.project.json подключает этот файл).
--  • Бонус алмазов за игру с другом. Дружба — Player:IsFriendsWithAsync в pcall, ответ запоминается (кэш на сервер):
--    Roblox отвечает не сразу, поэтому команду проверяем заранее (warm, в начале ночи), а в итоге ночи берём только
--    из кэша. Ошибка сети или ещё нет ответа — «не друзья» (бонуса нет, но и ничего не ломается).
--  • Рекорды друзей: Players:GetFriendsAsync → до Config.FriendRecords.MaxFriends друзей → их профили (GetAsync
--    в pcall, только чтение) → личный рекорд stats.bestRun. Итог — атрибут игрока FriendRecords (JSON). Лимит
--    запросов DataStore бережём: общий кэш, пауза между запросами, остановка при малом запасе. Studio без API или
--    ошибка — атрибут пустой, строка у игрока скрыта.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local Records = Config.FriendRecords

local FriendService = {}

local cache: { [string]: boolean } = {} -- "меньший:больший UserId" -> друзья ли
local asking: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then ("%d:%d"):format(a, b) else ("%d:%d"):format(b, a)
end

-- Проверить пару сейчас (ждёт ответа Roblox). Тестовые игроки Studio (UserId <= 0) — не друзья.
local function ask(a: Player, b: Player): boolean
	if a.UserId <= 0 or b.UserId <= 0 or a == b then
		return false
	end
	local key = pairKey(a.UserId, b.UserId)
	if cache[key] ~= nil then
		return cache[key]
	end
	if asking[key] then
		return false
	end
	asking[key] = true
	local ok, result = pcall(a.IsFriendsWithAsync, a, b.UserId)
	asking[key] = nil
	if not ok then
		warn(("[FriendService] Не удалось проверить дружбу %d и %d: %s"):format(a.UserId, b.UserId, tostring(result)))
		return false
	end
	cache[key] = result == true
	return cache[key]
end

-- Друзья ли (только из кэша; nil — ещё не знаем).
function FriendService.known(a: Player, b: Player): boolean?
	if a.UserId <= 0 or b.UserId <= 0 or a == b then
		return false
	end
	return cache[pairKey(a.UserId, b.UserId)]
end

-- Заранее спросить Roblox про все пары команды (в фоне).
function FriendService.warm(players: { Player })
	for i, a in players do
		for j = i + 1, #players do
			local b = players[j]
			if FriendService.known(a, b) == nil then
				task.spawn(ask, a, b)
			end
		end
	end
end

-- Есть ли у игрока друг в команде (только из кэша — не ждёт).
function FriendService.hasFriendIn(player: Player, team: { Player }): boolean
	for _, other in team do
		if other ~= player and FriendService.known(player, other) == true then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- рекорды друзей

type Cached = { value: number, at: number }
local recordCache: { [number]: Cached } = {} -- UserId друга -> его рекорд ночей и когда прочитан
local loading: { [Player]: boolean } = {}
local recordsStarted = false

-- Друзья игрока (UserId, имя), не больше MaxFriends. Ошибка — пусто.
local function friendsOf(player: Player): { { id: number, name: string } }
	local list = {}
	local ok, err = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		while #list < Records.MaxFriends do
			for _, item in pages:GetCurrentPage() do
				if #list >= Records.MaxFriends then
					break
				end
				local id = tonumber(item.Id)
				if id and id > 0 then
					local name = if typeof(item.DisplayName) == "string" and item.DisplayName ~= "" then item.DisplayName else tostring(item.Username)
					table.insert(list, { id = id, name = name })
				end
			end
			if pages.IsFinished or #list >= Records.MaxFriends then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn(("[FriendService] Не удалось получить друзей %d: %s"):format(player.UserId, tostring(err)))
	end
	return list
end

-- Рекорд друга из его профиля (кэш, если свежий). nil — не прочитали (нет запаса или ошибка).
local function recordOf(userId: number): number?
	local cached = recordCache[userId]
	if cached and os.clock() - cached.at < Records.CacheSeconds then
		return cached.value
	end
	local okBudget, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, Enum.DataStoreRequestType.GetAsync)
	if not okBudget or budget < Records.MinBudget then
		return nil
	end
	local ok, data = pcall(function()
		return DataStoreService:GetDataStore(Config.Diamonds.Store):GetAsync(tostring(userId))
	end)
	if not ok then
		return nil
	end
	local value = 0
	if typeof(data) == "table" and typeof(data.stats) == "table" then
		value = math.max(0, math.floor(tonumber(data.stats.bestRun) or 0))
	end
	recordCache[userId] = { value = value, at = os.clock() }
	task.wait(Records.Spacing)
	return value
end

-- Прочитать рекорды друзей игрока и положить в атрибут FriendRecords (лучшие Show по убыванию).
function FriendService.loadRecords(player: Player)
	if loading[player] or player.UserId <= 0 then
		return
	end
	loading[player] = true
	local list = {}
	for _, friend in friendsOf(player) do
		if not player.Parent then
			break
		end
		local value = recordOf(friend.id)
		if value and value > 0 then
			table.insert(list, { n = friend.name, v = value })
		end
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	while #list > Records.Show do
		table.remove(list)
	end
	loading[player] = nil
	if player.Parent then
		player:SetAttribute(GameState.PlayerAttr.FriendRecords, if #list > 0 then HttpService:JSONEncode(list) else "")
	end
end

-- Каждый вошедший: рекорды друзей через LoadDelay сек и потом раз в RefreshSeconds (хаб и музей).
function FriendService.startRecords()
	if recordsStarted then
		return
	end
	recordsStarted = true
	local function onPlayer(player: Player)
		task.delay(Records.LoadDelay, function()
			while player.Parent do
				FriendService.loadRecords(player)
				task.wait(Records.RefreshSeconds)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

-- Игрок вышел — кэш по нему не нужен (дружба могла измениться к следующему входу).
Players.PlayerRemoving:Connect(function(player)
	local prefix, suffix = tostring(player.UserId) .. ":", ":" .. tostring(player.UserId)
	for key in cache do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			cache[key] = nil
		end
	end
	loading[player] = nil
end)

return FriendService
