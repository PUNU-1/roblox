-- Телепорт между местами игры (блок 6): хаб → отдельный сервер музея для команды, музей → хаб.
-- Общий для музея и хаба (hub.project.json подключает этот файл). Всё через pcall с повтором.
-- Номера мест находит PlaceFinder (этап 4, блок 0). В Studio и пока место не найдено телепорт не работает —
-- возвращаем понятный текст.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Retry = require(script.Parent:WaitForChild("Retry"))

local Places = Config.Places

local Teleporter = {}

Teleporter.StudioText = "Teleport works only in the published game"
Teleporter.MuseumNotFoundText = "Museum place not found — ask the owner to publish it"
Teleporter.HubNotFoundText = "Lobby place not found — ask the owner to publish it"

-- Можно ли сейчас телепортировать в это место: не Studio и место найдено (PlaceFinder вернул не 0).
function Teleporter.canTeleport(placeId: number): boolean
	return not RunService:IsStudio() and placeId ~= 0
end

-- Почему телепорта нет: в Studio — StudioText, в опубликованной игре — «место не найдено».
local function blockedText(notFound: string): string
	return if RunService:IsStudio() then Teleporter.StudioText else notFound
end

local function send(placeId: number, players: { Player }, options: TeleportOptions): (boolean, string?)
	local list = {}
	for _, player in players do
		if player.Parent then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return false, "Nobody to teleport"
	end
	local ok, err = Retry.call(Places.TeleportRetries, Places.RetryDelay, function()
		return TeleportService:TeleportAsync(placeId, list, options)
	end)
	if not ok then
		warn(("[Teleporter] TeleportAsync в место %d не удался: %s"):format(placeId, tostring(err)))
		return false, "Teleport failed — try again"
	end
	return true, nil
end

-- Команду — на новый отдельный сервер места (ReserveServer): туда больше никто не попадёт.
function Teleporter.toReserved(placeId: number, players: { Player }, data: { [string]: any }): (boolean, string?)
	if not Teleporter.canTeleport(placeId) then
		return false, blockedText(Teleporter.MuseumNotFoundText)
	end
	local ok, code = Retry.call(Places.TeleportRetries, Places.RetryDelay, function()
		local accessCode = TeleportService:ReserveServer(placeId)
		return accessCode
	end)
	if not ok or typeof(code) ~= "string" then
		warn(("[Teleporter] ReserveServer для места %d не удался: %s"):format(placeId, tostring(code)))
		return false, "Could not open a museum server — try again"
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData(data)
	return send(placeId, players, options)
end

-- В обычный (общий) сервер места — например, обратно в хаб.
function Teleporter.toPublic(placeId: number, players: { Player }, data: { [string]: any }?): (boolean, string?)
	if not Teleporter.canTeleport(placeId) then
		return false, blockedText(Teleporter.HubNotFoundText)
	end
	local options = Instance.new("TeleportOptions")
	if data then
		options:SetTeleportData(data)
	end
	return send(placeId, players, options)
end

-- Телепорт игрока не удался уже после отправки (Roblox сообщает об этом отдельно). Если сервер был занят
-- или сеть подвела — пробуем ещё раз сами, потом зовём callback (показать игроку надпись).
local failures: { [Player]: number } = {}
function Teleporter.onFailed(callback: (player: Player, message: string) -> ())
	TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, placeId, options)
		local count = (failures[player] or 0) + 1
		failures[player] = count
		local retryable = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
		if retryable and count < Places.TeleportRetries and options then
			task.delay(Places.RetryDelay, function()
				if player.Parent then
					local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, { player }, options)
					if not ok then
						failures[player] = nil
						warn(("[Teleporter] %s не улетел: %s"):format(player.Name, tostring(err)))
						callback(player, "Teleport failed — try again")
					end
				end
			end)
			return
		end
		failures[player] = nil
		warn(("[Teleporter] %s не улетел: %s (%s)"):format(player.Name, tostring(errorMessage), tostring(result)))
		callback(player, "Teleport failed — try again")
	end)
	Players.PlayerRemoving:Connect(function(player)
		failures[player] = nil
	end)
end

return Teleporter
