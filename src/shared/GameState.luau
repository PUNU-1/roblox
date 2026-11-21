--!strict
-- Общее состояние игры, которое видят все клиенты.
-- Хранится в атрибутах: ReplicatedStorage.GameState (состояние раунда) и у каждого Player.
-- Пишет только сервер, клиенты только читают.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = {}

GameState.Phase = {
	Lobby = "Lobby",
	Day = "Day",
	Night = "Night",
	Results = "Results",
}

GameState.Role = {
	Patrol = "Patrol",
	Operator = "Operator",
}

-- Атрибуты модели NPC (вор, турист): сервер пишет, что он сейчас делает, клиенты по этому двигают руки и ноги.
GameState.NpcAttr = {
	AnimState = "AnimState", -- string, одна из GameState.ThiefAnim или GameState.TouristAnim
	AnimStateAt = "AnimStateAt", -- number, workspace:GetServerTimeNow(), когда началось это состояние
}

GameState.ThiefAnim = {
	Sneak = "Sneak", -- крадётся к экспонату на цыпочках
	Run = "Run", -- убегает от охранника или загораживает путь
	Steal = "Steal", -- оглядывается и снимает экспонат
	Carry = "Carry", -- несёт экспонат над головой
	Arrest = "Arrest", -- руки вверх, потом руки вперёд в наручники
}

-- Залы музея. Главный открыт всегда, боковые открываются за деньги (вскладчину).
GameState.Hall = {
	Main = "Main",
	Jewelry = "Jewelry",
	Sculptures = "Sculptures",
}

-- Атрибут GameState «зал открыт»: HallOpen_Jewelry и т.д.
function GameState.hallOpenAttr(hall: string): string
	return "HallOpen_" .. hall
end

-- Открыт ли зал (атрибут Hall у детали карты; без атрибута — главный зал).
function GameState.isHallOpen(hall: any): boolean
	if hall == nil or hall == GameState.Hall.Main then
		return true
	end
	return GameState.get(GameState.hallOpenAttr(hall)) == true
end

GameState.TouristAnim = {
	Stroll = "Stroll", -- спокойно гуляет
	Admire = "Admire", -- стоит у экспоната, руки за спиной
	Photo = "Photo", -- фотографирует экспонат
}

-- Атрибуты ReplicatedStorage.GameState
GameState.Attr = {
	Phase = "Phase", -- string, одна из GameState.Phase
	PhaseEndsAt = "PhaseEndsAt", -- number, workspace:GetServerTimeNow(); 0 — таймера нет
	NightStartedAt = "NightStartedAt", -- number, для часов 00:00 -> 06:00
	PaintingStolen = "PaintingStolen", -- boolean, картину сейчас несёт вор
	StealEndsAt = "StealEndsAt", -- number, когда вор снимет картину; 0 — никто не снимает
	Caught = "Caught", -- number, поймано воров за ночь
	ThievesSpawned = "ThievesSpawned", -- number, сколько воров уже пришло
	Solo = "Solo", -- boolean, в игре один игрок
	NightNumber = "NightNumber", -- number, какая по счёту ночь идёт (или будет после этого дня)
	BestNights = "BestNights", -- number, рекорд сервера: сколько ночей продержались
	TouristsToday = "TouristsToday", -- number, сколько туристов пришло за день
}

-- Атрибуты Player
GameState.PlayerAttr = {
	Role = "Role", -- string, GameState.Role
	InTeam = "InTeam", -- boolean, стоит в круге START SHIFT в лобби и попал в команду (не больше 5)
	InRound = "InRound", -- boolean, игрок участвует в текущей ночи
	ViewingCameras = "ViewingCameras", -- boolean, открыт телефон или пульт
	ViewSource = "ViewSource", -- string: "Phone" | "Console"
	Money = "Money", -- number, доллары за этот забег
	JoinStatus = "JoinStatus", -- string?, опоздавший: Voting | Approved | Rejected | Full
}

local FOLDER_NAME = "GameState"

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function GameState.folder(): Folder
	return folder
end

function GameState.get(attr: string): any
	return folder:GetAttribute(attr)
end

-- Только на сервере.
function GameState.set(attr: string, value: any)
	assert(RunService:IsServer(), "GameState.set вызывается только на сервере")
	folder:SetAttribute(attr, value)
end

function GameState.phase(): string
	local value = folder:GetAttribute(GameState.Attr.Phase)
	if typeof(value) == "string" then
		return value
	end
	return GameState.Phase.Lobby
end

-- Команда в лобби: кто стоит в круге START SHIFT (атрибут InTeam ставит сервер, LobbyService).
function GameState.lobbyTeam(): { Player }
	local team = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(GameState.PlayerAttr.InTeam) == true then
			table.insert(team, player)
		end
	end
	return team
end

-- Какая часть ночи прошла: 0 — полночь, 1 — 06:00. Ночь бывает разной длины (решение 66),
-- поэтому длину берём из времени начала ночи и конца фазы.
function GameState.nightProgress(): number
	local started = folder:GetAttribute(GameState.Attr.NightStartedAt)
	local endsAt = folder:GetAttribute(GameState.Attr.PhaseEndsAt)
	if typeof(started) ~= "number" or typeof(endsAt) ~= "number" or endsAt <= started then
		return 0
	end
	return math.clamp((workspace:GetServerTimeNow() - started) / (endsAt - started), 0, 1)
end

function GameState.secondsLeft(): number
	local endsAt = folder:GetAttribute(GameState.Attr.PhaseEndsAt)
	if typeof(endsAt) ~= "number" or endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

return GameState
