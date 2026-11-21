-- Лобби (блок B1): светящийся круг START SHIFT посреди комнаты охраны вместо кнопки READY.
-- Встал в круг — ты в команде (не больше Config.Players.Max), вышел — вышел из команды.
-- Пока в круге хоть один игрок, идёт отсчёт; кончился — GameLoop забирает команду в музей.
-- Кто в круге, сервер проверяет раз в Config.Lobby.CheckSeconds по расстоянию до HumanoidRootPart
-- (Touched ненадёжный). Клиентам — атрибут игрока InTeam и таймер фазы PhaseEndsAt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local PlayerAttr = GameState.PlayerAttr

local LobbyService = {}

local circle: BasePart? = nil
local isOpen = false
local members: { Player } = {} -- по порядку входа: кто встал раньше, тот и держит место
local endsAt = 0 -- когда кончится отсчёт; 0 — отсчёта нет

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isInside(player: Player, center: Vector3): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return false
	end
	local offset = root.Position - center
	if math.abs(offset.Y) > Config.Lobby.CircleHeight then
		return false
	end
	return Vector2.new(offset.X, offset.Z).Magnitude <= Config.Lobby.CircleRadius
end

local function setInTeam(player: Player, inTeam: boolean)
	if player:GetAttribute(PlayerAttr.InTeam) ~= inTeam then
		player:SetAttribute(PlayerAttr.InTeam, inTeam)
	end
end

local function setMembers(list: { Player })
	members = list
	for _, player in Players:GetPlayers() do
		setInTeam(player, table.find(list, player) ~= nil)
	end
end

local function setCountdown(value: number)
	if endsAt ~= value then
		endsAt = value
		GameState.set(GameState.Attr.PhaseEndsAt, value)
	end
end

local function update()
	local pad = circle
	if not isOpen or not pad then
		return
	end
	local center = pad.Position
	local list: { Player } = {}
	-- Кто уже в команде и всё ещё в круге — остаётся на своём месте
	for _, player in members do
		if player.Parent and isInside(player, center) then
			table.insert(list, player)
		end
	end
	-- Новые — пока есть места. Шестой не помещается: круг для него красный (LobbyCircle.client)
	for _, player in Players:GetPlayers() do
		if #list >= Config.Players.Max then
			break
		end
		if not table.find(list, player) and isInside(player, center) then
			table.insert(list, player)
		end
	end
	setMembers(list)

	if #list == 0 then
		setCountdown(0) -- круг опустел — отсчёт сначала
		return
	end
	local time = now()
	local target = if endsAt == 0 then time + Config.Lobby.CountdownSeconds else endsAt
	if #list >= #Players:GetPlayers() then
		-- В круге все, кто есть на сервере, — ждать незачем, но пару секунд даём, чтобы передумать
		target = math.min(target, time + Config.Lobby.AllInSeconds)
	end
	setCountdown(target)
end

-- GameLoop: лобби началось, круг принимает игроков.
function LobbyService.open()
	isOpen = true
	endsAt = 0
	setMembers({})
	update()
end

-- Отсчёт кончился, а в круге есть хоть один игрок.
function LobbyService.teamReady(): boolean
	return isOpen and #members > 0 and endsAt > 0 and now() >= endsAt
end

-- Забирает команду из круга и закрывает лобби (круг до конца забега не работает).
function LobbyService.takeTeam(): { Player }
	local team = {}
	for _, player in members do
		if player.Parent then
			table.insert(team, player)
		end
	end
	isOpen = false
	endsAt = 0 -- таймер фазы перепишет следующая фаза
	setMembers({})
	return team
end

function LobbyService.init(map: Instance)
	local found = map:FindFirstChild(MapSchema.StartCircle, true)
	if found and found:IsA("BasePart") then
		circle = found
	else
		warn("[LobbyService] Нет круга StartCircle на карте — команду не собрать")
	end

	local function onPlayerAdded(player: Player)
		setInTeam(player, false)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local index = table.find(members, player)
		if index then
			table.remove(members, index) -- ушёл с сервера — место в команде свободно сразу
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Lobby.CheckSeconds)
			update()
		end
	end)
end

return LobbyService
