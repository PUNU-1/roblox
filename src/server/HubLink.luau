-- Связь музея с хабом (блок 6). Команда прилетает из хаба на свой отдельный сервер музея:
-- Player:GetJoinData() даёт состав команды и классы (TeleportTicket). Музей ставит каждому класс из хаба,
-- ждёт всю команду (не дольше Config.GameOver.WaitTeamSeconds после первого) и сразу начинает забег —
-- без круга START SHIFT. Свой игрок, который долетел позже, входит с ближайшего дня без голосования.
-- Без данных хаба (Studio, неопубликованная игра, прямой вход) музей работает как раньше: свой круг и выбор класса.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local TeleportTicket = require(Shared:WaitForChild("TeleportTicket"))

local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr

local HubLink = {}

local tickets: { [Player]: TeleportTicket.Ticket } = {}
local checked: { [Player]: boolean } = {}
local expected: { number } = {} -- UserId команды из хаба (по данным всех, кто уже прилетел)
local firstArrival = 0 -- когда прилетел первый из команды
local teamStarted = false -- команда из хаба уже начала забег: дальше Play again или круг START SHIFT

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Данные хаба игрока (читаются один раз). nil — пришёл не из хаба.
local function ticketOf(player: Player): TeleportTicket.Ticket?
	if not checked[player] then
		checked[player] = true
		local ok, joinData = pcall(player.GetJoinData, player)
		local ticket = if ok then TeleportTicket.read(joinData, player.UserId) else nil
		if ticket then
			tickets[player] = ticket
			for _, id in ticket.team do
				if not table.find(expected, id) then
					table.insert(expected, id)
				end
			end
			if firstArrival == 0 then
				firstArrival = now()
			end
		end
	end
	return tickets[player]
end

local function arrivedTeam(): { Player }
	local list = {}
	for _, id in expected do
		local player = Players:GetPlayerByUserId(id)
		if player and not table.find(list, player) then
			table.insert(list, player)
		end
	end
	return list
end

-- У всех долетевших уже есть персонаж: иначе перенос в музей в начале забега некого переносить.
local function allSpawned(team: { Player }): boolean
	for _, player in team do
		local character = player.Character
		if not (character and character:FindFirstChild("HumanoidRootPart")) then
			return false
		end
	end
	return true
end

-- Прилетела команда из хаба, а забег с ней ещё не начат: круг START SHIFT не нужен.
function HubLink.teamPending(): boolean
	return not teamStarted and #expected > 0
end

-- Ждёт всю команду из хаба (не дольше WaitTeamSeconds после первого) и отдаёт тех, кто долетел.
-- Пока ждём — на экране «Your team is arriving 2/3» (атрибуты HubArrival, HubArrived, HubExpected).
function HubLink.waitForTeam(): { Player }
	GameState.set(Attr.HubArrival, true)
	GameState.set(Attr.PhaseEndsAt, firstArrival + Config.GameOver.WaitTeamSeconds)
	local team = arrivedTeam()
	while true do
		team = arrivedTeam()
		GameState.set(Attr.HubArrived, #team)
		GameState.set(Attr.HubExpected, #expected)
		if (#team >= #expected and allSpawned(team)) or now() >= firstArrival + Config.GameOver.WaitTeamSeconds then
			break
		end
		task.wait(Config.Phases.TickSeconds)
	end
	teamStarted = true
	GameState.set(Attr.HubArrival, false)
	return team
end

-- VoteService: игрок своей команды из хаба долетел, когда забег уже идёт — пустить без голосования.
function HubLink.isLateTeammate(player: Player): boolean
	return teamStarted and ticketOf(player) ~= nil
end

local function onPlayerAdded(player: Player)
	local ticket = ticketOf(player)
	if not ticket then
		return
	end
	-- Класс из хаба. RoleService ставит новому игроку класс по умолчанию — свой ставим следом
	local role = ticket.classes[player.UserId]
	if role then
		task.defer(function()
			if player.Parent then
				player:SetAttribute(PlayerAttr.Role, role)
			end
		end)
	end
end

function HubLink.init()
	GameState.set(Attr.HubArrival, false)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		tickets[player] = nil
		checked[player] = nil
	end)
end

return HubLink
