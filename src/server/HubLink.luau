-- Связь музея с хабом (блок 6). Команда прилетает из хаба на свой отдельный сервер музея:
-- Player:GetJoinData() даёт состав команды и классы (TeleportTicket). Музей ставит каждому класс из хаба,
-- ждёт всю команду (не дольше Config.GameOver.WaitTeamSeconds после первого) и сразу начинает забег —
-- без круга START SHIFT. Свой игрок, который долетел позже, входит с ближайшего дня без голосования.
-- Без данных хаба (Studio, неопубликованная игра, прямой вход) музей работает как раньше: свой круг и выбор класса.
-- Конец забега: кнопки Play again (та же команда, новый забег на этом сервере) и Lobby (телепорт в хаб;
-- если телепорта нет — в домик SECURITY). Ничего не нажал за Config.GameOver.ChoiceSeconds — в лобби.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local TeleportTicket = require(Shared:WaitForChild("TeleportTicket"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Teleporter = require(script.Parent:WaitForChild("Teleporter"))
local PlaceFinder = require(script.Parent:WaitForChild("PlaceFinder"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr

local HubLink = {}

local tickets: { [Player]: TeleportTicket.Ticket } = {}
local checked: { [Player]: boolean } = {}
local roleReady: { [Player]: boolean } = {}
local expected: { number } = {} -- UserId команды из хаба (по данным всех, кто уже прилетел)
local firstArrival = 0 -- когда прилетел первый из команды
local teamStarted = false -- команда из хаба уже начала забег: дальше Play again или круг START SHIFT

-- Конец забега: кто выбирает и что выбрал
local choosing = false
local choosers: { Player } = {}
local choices: { [Player]: string } = {}
local sentToHub: { [Player]: boolean } = {}
local lastNights = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Данные хаба игрока (читаются один раз). nil — пришёл не из хаба.
-- Может подождать, пока PlaceFinder найдёт место хаба (первые секунды сервера).
local function ticketOf(player: Player): TeleportTicket.Ticket?
	if not checked[player] then
		local hubPlaceId = PlaceFinder.hubId()
		if checked[player] then
			return tickets[player] -- пока ждали, прочитал другой вызов
		end
		checked[player] = true
		local ok, joinData = pcall(player.GetJoinData, player)
		local ticket = if ok then TeleportTicket.read(joinData, player.UserId, hubPlaceId) else nil
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

local function allRolesReady(team: { Player }): boolean
	for _, player in team do
		if roleReady[player] ~= true then
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
		if (#team >= #expected and allSpawned(team) and allRolesReady(team)) or now() >= firstArrival + Config.GameOver.WaitTeamSeconds then
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

-- В лобби: в опубликованной игре — телепорт в хаб (с «Welcome back, N nights»), иначе остаются в музее —
-- GameLoop.finishRun перенесёт их в домик SECURITY с кругом START SHIFT.
local function sendToLobby(players: { Player })
	local hubPlaceId = PlaceFinder.hubId()
	if not Teleporter.canTeleport(hubPlaceId) then
		return
	end
	local list = {}
	for _, player in players do
		if player.Parent and not sentToHub[player] then
			sentToHub[player] = true
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		local ok, message = Teleporter.toPublic(hubPlaceId, list, TeleportTicket.packReturn(lastNights))
		if not ok then
			for _, player in list do
				sentToHub[player] = nil
				if player.Parent then
					Remotes.get(Remotes.Names.Banner):FireClient(player, message or "Teleport failed — try again", "danger")
				end
			end
		end
	end)
end

local function onChoice(player: Player, choice: any)
	if not choosing or not table.find(choosers, player) or choices[player] ~= nil then
		return
	end
	if choice ~= "PlayAgain" and choice ~= "Lobby" then
		return
	end
	choices[player] = choice
	player:SetAttribute(PlayerAttr.EndChoice, choice)
	if choice == "Lobby" then
		sendToLobby({ player }) -- в хаб сразу, не ждём остальных
	end
end

-- GameLoop: экран GAME OVER с кнопками. Ждёт, пока все выберут (или кончится время фазы итога),
-- отправляет в лобби всех, кто не нажал Play again, и отдаёт тех, кто нажал: с ними — новый забег.
function HubLink.runGameOverChoice(participants: { Player }, nights: number): { Player }
	choosers = table.clone(participants)
	table.clear(choices)
	lastNights = nights
	for _, player in choosers do
		player:SetAttribute(PlayerAttr.EndChoice, "")
	end
	choosing = true
	while GameState.secondsLeft() > 0 do
		local waiting = false
		for _, player in choosers do
			if player.Parent and choices[player] == nil then
				waiting = true
			end
		end
		if not waiting then
			break -- все выбрали (или ушли) — не ждём конца отсчёта
		end
		task.wait(Config.Phases.TickSeconds)
	end
	choosing = false
	local again, rest = {}, {}
	for _, player in choosers do
		if player.Parent then
			if choices[player] == "PlayAgain" then
				table.insert(again, player)
			else
				table.insert(rest, player) -- нажал Lobby или ничего не нажал за 20 сек
			end
			player:SetAttribute(PlayerAttr.EndChoice, "")
		end
	end
	sendToLobby(rest)
	return again
end

local function onPlayerAdded(player: Player)
	local ticket = ticketOf(player)
	if not ticket then
		if player.Parent then
			roleReady[player] = true
		end
		return
	end
	-- Класс из хаба. RoleService ставит новому игроку класс по умолчанию — свой ставим следом.
	-- Этап 4, блок 1: хабу не верим — купил ли игрок класс, музей проверяет сам по его профилю (ProfileStore).
	-- Пока профиль грузится, у игрока Patrol; не загрузился или класс не куплен — так и остаётся Patrol.
	local role = ticket.classes[player.UserId]
	if role and role ~= Config.Classes.Default then
		ProfileStore.waitLoaded(player, Config.Diamonds.LoadWaitSeconds)
		if player.Parent and ProfileStore.owns(player, role) then
			player:SetAttribute(PlayerAttr.Role, role)
		elseif player.Parent then
			warn(("[HubLink] %s прилетел с классом %s, но не купил его — Patrol"):format(player.Name, tostring(role)))
		end
	end
	if player.Parent then
		roleReady[player] = true
	end
end

function HubLink.init()
	PlaceFinder.init("Museum") -- место хаба ищется в фоне; строка [PlaceFinder] в Output
	GameState.set(Attr.HubArrival, false)
	Remotes.get(Remotes.Names.GameOverChoice).OnServerEvent:Connect(onChoice)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player) -- может ждать PlaceFinder — не держим init
	end
	Players.PlayerRemoving:Connect(function(player)
		tickets[player] = nil
		checked[player] = nil
		roleReady[player] = nil
		choices[player] = nil
		sentToHub[player] = nil
	end)
end

return HubLink
