--!strict
-- Поиск мест игры (этап 4, блок 0): хаб и музей сами находят друг друга, номера вручную не нужны.
-- Общий для музея и хаба (hub.project.json подключает этот файл).
-- Список мест — AssetService:GetGamePlacesAsync() (pcall с повтором). Своё место — game.PlaceId,
-- второе место — другое место этой игры. Номера в Config.Places — запасной путь: берём их, если такое
-- место есть в игре (или если список мест получить не удалось). Результат кэшируется.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Retry = require(script.Parent:WaitForChild("Retry"))

local Places = Config.Places

export type Role = "Hub" | "Museum"

type PlaceInfo = { id: number, name: string }

local PlaceFinder = {}

local role: Role? = nil
local ready = false -- первый поиск закончен (удачно или нет)
local waiting: { thread } = {}
local hubId = 0
local museumId = 0

-- Все места этой игры. nil — Roblox не ответил; пустой список — игра не опубликована.
local function listPlaces(): { PlaceInfo }?
	if game.GameId == 0 or game.PlaceId == 0 then
		return {}
	end
	local ok, pages = Retry.call(Places.TeleportRetries, Places.RetryDelay, function()
		return AssetService:GetGamePlacesAsync()
	end)
	if not ok or typeof(pages) ~= "Instance" or not pages:IsA("Pages") then
		warn(("[PlaceFinder] GetGamePlacesAsync не удался: %s"):format(tostring(pages)))
		return nil
	end
	local list: { PlaceInfo } = {}
	while true do
		for _, item in (pages :: Pages):GetCurrentPage() do
			if typeof(item) == "table" and typeof(item.PlaceId) == "number" then
				table.insert(list, { id = item.PlaceId, name = tostring(item.Name or "") })
			end
		end
		if (pages :: Pages).IsFinished then
			break
		end
		local advanced = Retry.call(Places.TeleportRetries, Places.RetryDelay, function()
			(pages :: Pages):AdvanceToNextPageAsync()
			return true
		end)
		if not advanced then
			break -- что успели получить — тем и пользуемся
		end
	end
	return list
end

local function has(list: { PlaceInfo }, id: number): boolean
	for _, place in list do
		if place.id == id then
			return true
		end
	end
	return false
end

-- Второе место игры: номер из Config (если он есть в игре) → место, в названии которого есть hint → любое другое.
local function pickOther(list: { PlaceInfo }?, configured: number, hint: string): number
	local mine = game.PlaceId
	if not list then
		-- Список не получили: запасной путь — номер из Config (TeleportAsync сам откажет, если он чужой)
		return if configured ~= 0 and configured ~= mine then configured else 0
	end
	if configured ~= 0 and configured ~= mine and has(list, configured) then
		return configured
	end
	for _, place in list do
		if place.id ~= mine and string.find(string.lower(place.name), hint, 1, true) then
			return place.id
		end
	end
	for _, place in list do
		if place.id ~= mine then
			return place.id
		end
	end
	return 0
end

local function lookup(): boolean
	local list = listPlaces()
	if role == "Hub" then
		hubId = game.PlaceId
		museumId = pickOther(list, Places.MuseumPlaceId, "museum")
	else
		museumId = game.PlaceId
		hubId = pickOther(list, Places.HubPlaceId, "hub")
	end
	local where = if RunService:IsStudio() then ", Studio" else ""
	local count = if list then tostring(#list) else "unknown"
	print(("[PlaceFinder] hub=%d museum=%d (this=%s, places=%s%s)"):format(hubId, museumId, string.lower(role or "?"), count, where))
	return list ~= nil
end

-- Запуск поиска в фоне (один раз, при старте сервера). Хаб: init("Hub"), музей: init("Museum").
function PlaceFinder.init(myRole: Role)
	if role then
		return
	end
	role = myRole
	task.spawn(function()
		local ok = lookup()
		ready = true
		for _, thread in waiting do
			task.spawn(thread)
		end
		table.clear(waiting)
		-- Roblox не ответил — пробуем ещё, пока не получится (а пока работают номера из Config)
		while not ok do
			task.wait(Places.LookupRetrySeconds)
			ok = lookup()
		end
	end)
end

-- Ждёт первого поиска (если он ещё идёт). Вызывать после init.
local function waitReady()
	if not ready and role then
		table.insert(waiting, coroutine.running())
		coroutine.yield()
	end
end

-- Номер места хаба (0 — не найден). Может подождать первый поиск.
function PlaceFinder.hubId(): number
	waitReady()
	return hubId
end

-- Номер места музея (0 — не найден). Может подождать первый поиск.
function PlaceFinder.museumId(): number
	waitReady()
	return museumId
end

return PlaceFinder
