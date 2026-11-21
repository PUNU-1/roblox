-- Игровой цикл — забег на выживание: Лобби -> (День -> Ночь -> Итог) x N -> снова Лобби.
-- Цель — продержаться как можно больше ночей. Мону Лизу вынесли — игра окончена, всё с нуля.
-- Сервер решает всё: когда начинается ночь, кто участвует, чем она закончилась.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local MapBuilder = require(Server:WaitForChild("MapBuilder"))
local RoleService = require(Server:WaitForChild("RoleService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
local CatchService = require(Server:WaitForChild("CatchService"))
local TrapService = require(Server:WaitForChild("TrapService"))
local CommsService = require(Server:WaitForChild("CommsService"))
local TouristService = require(Server:WaitForChild("TouristService"))
local HallService = require(Server:WaitForChild("HallService"))
local CameraService = require(Server:WaitForChild("CameraService"))
local VoteService = require(Server:WaitForChild("VoteService"))
local Audio = require(Server:WaitForChild("Audio"))

local Phase = GameState.Phase
local Attr = GameState.Attr

ModelLibrary.setupCollisionGroups()
-- Тени: без них свет ламп и фонариков проходит сквозь стены, и ночью не темно
Lighting.GlobalShadows = true
local map = MapBuilder.build()
RoleService.init(map)
ExhibitService.init(map)
ThiefService.init(map)
CatchService.init()
TrapService.init(map)
CommsService.init(map)
TouristService.init(map)
HallService.init(map)
CameraService.init(map)
VoteService.init()

-- Что смотрят туристы: Мону Лизу и купленные экспонаты в открытых залах.
TouristService.setAttractions(ExhibitService.attractions)

local resultsRemote = Remotes.get(Remotes.Names.NightResults)
local bannerRemote = Remotes.get(Remotes.Names.Banner)

local bestNights = 0 -- рекорд сервера
GameState.set(Attr.BestNights, 0)
GameState.set(Attr.NightNumber, 0)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setPhase(phase: string, duration: number?)
	GameState.set(Attr.Phase, phase)
	GameState.set(Attr.PhaseEndsAt, if duration then now() + duration else 0)
end

local function tick()
	task.wait(Config.Phases.TickSeconds)
end

local function anyoneLeft(): boolean
	return #RoleService.participants() > 0
end

local function setLighting(settings: { ClockTime: number, Brightness: number, Ambient: Color3, OutdoorAmbient: Color3 })
	Lighting.ClockTime = settings.ClockTime
	Lighting.Brightness = settings.Brightness
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient
end

-- Лобби: ждём, пока все нажмут READY или пройдёт отсчёт после первого READY.
local function runLobby()
	setLighting(Config.Lighting.Lobby)
	setPhase(Phase.Lobby, nil)
	RoleService.resetReady()
	RoleService.setConsoleEnabled(false)
	local endsAt = 0
	while true do
		local ready, total = RoleService.readyCounts()
		if total > 0 and ready == total then
			break
		end
		if ready > 0 then
			if endsAt == 0 then
				endsAt = now() + Config.Phases.LobbyCountdownSeconds
				GameState.set(Attr.PhaseEndsAt, endsAt)
			end
			if now() >= endsAt then
				break
			end
		elseif endsAt ~= 0 then
			endsAt = 0
			GameState.set(Attr.PhaseEndsAt, 0)
		end
		tick()
	end
end

-- День: светло, туристы, покупки. Возвращает false, если все ушли.
local function runDay(night: number): boolean
	VoteService.admitApproved() -- кого пустили голосованием, входят с утра
	ExhibitService.returnAll()
	setLighting(Config.Lighting.Day)
	GameState.set(Attr.NightNumber, night)
	setPhase(Phase.Day, Config.Phases.DaySeconds)
	RoleService.setConsoleEnabled(true)
	TrapService.beginDay()
	ScoreService.beginDay()
	TouristService.beginDay(ExhibitService.totalAppeal())
	HallService.setDayActive(true)
	ExhibitService.setDayActive(true)
	bannerRemote:FireAllClients(("DAY %d"):format(night), "info")
	Audio.startMusic(Config.Sounds.DayMusic)
	local closing = false
	while GameState.secondsLeft() > 0 do
		if not anyoneLeft() then
			return false
		end
		-- За 10 секунд до ночи музей закрывается: туристы идут к выходу, а не пропадают с наступлением ночи
		if not closing and GameState.secondsLeft() <= Config.Tourists.LeaveBeforeNightSeconds then
			closing = true
			TouristService.closeMuseum()
			bannerRemote:FireAllClients("THE MUSEUM IS CLOSING", "info")
		end
		tick()
	end
	return true
end

-- Ночь. Возвращает: survived (картина на месте), aborted (все ушли).
local function runNight(night: number): (boolean, boolean)
	TouristService.endDay()
	HallService.setDayActive(false)
	ExhibitService.setDayActive(false)
	setLighting(Config.Lighting.Night)
	setPhase(Phase.Night, Config.Phases.NightSeconds)
	GameState.set(Attr.NightStartedAt, now())
	TrapService.beginNight()
	local participants = RoleService.participants()
	ScoreService.beginNight(participants)
	Audio.startMusic(Config.Sounds.NightMusic)

	local survived, aborted = true, false
	local escapedConnection = ThiefService.Escaped.Event:Connect(function()
		survived = false
	end)
	ThiefService.beginNight(#participants, night)
	bannerRemote:FireAllClients(("NIGHT %d"):format(night), "danger")

	while survived and GameState.secondsLeft() > 0 do
		if not anyoneLeft() then
			aborted = true
			break
		end
		tick()
	end

	escapedConnection:Disconnect()
	ThiefService.endNight()
	Audio.stopMusic()
	return survived, aborted
end

local function runResults(survived: boolean, night: number)
	RoleService.closeAllViews()
	setPhase(Phase.Results, Config.Phases.ResultsSeconds)
	local results = ScoreService.finish(survived)
	local nightsSurvived = if survived then night else night - 1
	if not survived then
		bestNights = math.max(bestNights, nightsSurvived)
		GameState.set(Attr.BestNights, bestNights)
	end
	results.night = night
	results.gameOver = not survived
	results.nightsSurvived = nightsSurvived
	results.best = bestNights
	resultsRemote:FireAllClients(results)
	while GameState.secondsLeft() > 0 do
		tick()
	end
end

-- Конец забега: всех обратно в комнату охраны, музей с нуля.
local function finishRun()
	Audio.stopMusic()
	VoteService.setRunActive(false)
	TouristService.endDay()
	HallService.setDayActive(false)
	HallService.reset()
	CameraService.repairAll()
	ThiefService.endNight()
	TrapService.clear()
	RoleService.endRound()
	RoleService.setConsoleEnabled(false)
	ExhibitService.setDayActive(false)
	ExhibitService.reset()
	setLighting(Config.Lighting.Lobby)
	GameState.set(Attr.NightNumber, 0)
end

while true do
	runLobby()
	local participants = RoleService.startRound()
	ScoreService.beginRun(participants)
	VoteService.setRunActive(true)
	local night = 0
	while true do
		night += 1
		if not runDay(night) then
			break
		end
		local survived, aborted = runNight(night)
		if aborted then
			break
		end
		runResults(survived, night)
		if not survived then
			break
		end
	end
	finishRun()
end
