--!strict
-- Данные телепорта между хабом и музеем (блок 6). Хаб кладёт в TeleportData команду и классы,
-- музей читает их из Player:GetJoinData(). TeleportData идёт через клиента, поэтому музей всё проверяет:
-- метку источника, место, откуда пришёл игрок, и что классы — из Config.Classes. Подделать можно только
-- свой класс, а его и так выбирают свободно.

local Config = require(script.Parent:WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))

local Places = Config.Places

local TeleportTicket = {}

export type Ticket = {
	team: { number }, -- UserId всей команды из круга хаба (по порядку, первый — создатель)
	classes: { [number]: string }, -- UserId -> класс
}

-- Хаб: команда и классы. В TeleportData — только строки, числа и таблицы со строковыми ключами.
function TeleportTicket.pack(team: { Player }): { [string]: any }
	local ids = {}
	local classes = {}
	for _, player in team do
		table.insert(ids, player.UserId)
		classes[tostring(player.UserId)] = GameState.roleOf(player)
	end
	return { source = Places.TicketSource, team = ids, classes = classes }
end

-- Музей: данные хаба из Player:GetJoinData(). nil — игрок пришёл не из хаба (Studio, прямой вход) или данные странные.
-- hubPlaceId — место хаба (server/PlaceFinder); 0 — не найдено, тогда место, откуда пришёл игрок, не проверяем.
function TeleportTicket.read(joinData: any, userId: number, hubPlaceId: number): Ticket?
	if typeof(joinData) ~= "table" then
		return nil
	end
	if hubPlaceId ~= 0 and joinData.SourcePlaceId ~= hubPlaceId then
		return nil
	end
	local data = joinData.TeleportData
	if typeof(data) ~= "table" or data.source ~= Places.TicketSource then
		return nil
	end
	local team: { number } = {}
	if typeof(data.team) == "table" then
		for _, id in data.team do
			if typeof(id) == "number" and id > 0 and id == math.floor(id) and not table.find(team, id) and #team < Config.Players.Max then
				table.insert(team, id)
			end
		end
	end
	if not table.find(team, userId) then
		return nil -- в данных нет самого игрока — это не его команда
	end
	local classes: { [number]: string } = {}
	if typeof(data.classes) == "table" then
		for _, id in team do
			local role = data.classes[tostring(id)]
			if GameState.classInfo(role) then
				classes[id] = role
			end
		end
	end
	return { team = team, classes = classes }
end

-- Музей → хаб: сколько ночей продержалась команда (хаб скажет «Welcome back»).
function TeleportTicket.packReturn(nights: number): { [string]: any }
	return { source = Places.ReturnSource, nights = math.max(0, math.floor(nights)) }
end

-- Хаб: игрок вернулся из музея? Сколько ночей продержались (nil — пришёл не из музея).
-- museumPlaceId — место музея (server/PlaceFinder); 0 — не найдено, тогда место, откуда пришёл игрок, не проверяем.
function TeleportTicket.readReturn(joinData: any, museumPlaceId: number): number?
	if typeof(joinData) ~= "table" then
		return nil
	end
	if museumPlaceId ~= 0 and joinData.SourcePlaceId ~= museumPlaceId then
		return nil
	end
	local data = joinData.TeleportData
	if typeof(data) ~= "table" or data.source ~= Places.ReturnSource or typeof(data.nights) ~= "number" then
		return nil
	end
	return math.clamp(math.floor(data.nights), 0, 999)
end

return TeleportTicket
