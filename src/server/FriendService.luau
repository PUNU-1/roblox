-- Друзья по Roblox (этап 6, блок H2, решение 86): бонус алмазов за игру с другом.
-- Дружба — Player:IsFriendsWithAsync в pcall, ответ запоминается (кэш на сервер): Roblox отвечает не сразу,
-- поэтому команду проверяем заранее (warm, в начале ночи), а в итоге ночи берём только из кэша.
-- Ошибка сети или ещё нет ответа — «не друзья» (бонуса нет, но и ничего не ломается).

local Players = game:GetService("Players")

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

-- Игрок вышел — кэш по нему не нужен (дружба могла измениться к следующему входу).
Players.PlayerRemoving:Connect(function(player)
	local prefix, suffix = tostring(player.UserId) .. ":", ":" .. tostring(player.UserId)
	for key in cache do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			cache[key] = nil
		end
	end
end)

return FriendService
