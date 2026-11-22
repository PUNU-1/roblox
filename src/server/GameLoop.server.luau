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
local LobbyService = require(Server:WaitForChild("LobbyService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
local WaveService = require(Server:WaitForChild("WaveService"))
local HeistFx = require(Server:WaitForChild("HeistFx"))
local BlackoutService = require(Server:WaitForChild("BlackoutService"))
local CatchService = require(Server:WaitForChild("CatchService"))
local HealthService = require(Server:WaitForChild("HealthService"))
local WeaponService = require(Server:WaitForChild("WeaponService"))
local ArmoryService = require(Server:WaitForChild("ArmoryService"))
local TrapService = require(Server:WaitForChild("TrapService"))
local CommsService = require(Server:WaitForChild("CommsService"))
local TouristService = require(Server:WaitForChild("TouristService"))
local HallService = require(Server:WaitForChild("HallService"))
local CameraService = require(Server:WaitForChild("CameraService"))
local DoorService = require(Server:WaitForChild("DoorService"))
local VoteService = require(Server:WaitForChild("VoteService"))
local Audio = require(Server:WaitForChild("Audio"))

local Phase = GameState.Phase
local Attr = GameState.Attr

ModelLibrary.setupCollisionGroups()
-- Тени: без них свет ламп и фонариков проходит сквозь стены, и ночью не темно
Lighting.GlobalShadows = true
local map = MapBuilder.build()
RoleService.init(map)
LobbyService.init(map)
ExhibitService.init(map)
HeistFx.init(map)
BlackoutService.init(map)
ThiefService.init(map)
CatchService.init()
HealthService.init()
WeaponService.init()
ArmoryService.init(map)
-- Шокер берёт и обычных воров (пули — только грабителей, их добавляет RobberService)
WeaponService.addTargets({
	owns = ThiefService.isThief,
	stun = function(model: Model)
		return ThiefService.stun(model, Config.Weapons.Taser.StunThief)
	end,
})
TrapService.init(map)
CommsService.init(map)
TouristService.init(map)
HallService.init(map)
CameraService.init(map)
DoorService.init(map)
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

-- Длина дня и ночи растёт с каждым днём забега (решение 66): день 30 -> 60 сек, ночь 2 -> 5 мин.
local function daySeconds(day: number): number
	local phases = Config.Phases
	return math.min(phases.DayMaxSeconds, phases.DayFirstSeconds + (day - 1) * phases.DayGrowSeconds)
end

local function nightSeconds(night: number): number
	local phases = Config.Phases
	return math.min(phases.NightMaxSeconds, phases.NightFirstSeconds + (night - 1) * phases.NightGrowSeconds)
end

local function setLighting(settings: { ClockTime: number, Brightness: number, Ambient: Color3, OutdoorAmbient: Color3 })
	Lighting.ClockTime = settings.ClockTime
	Lighting.Brightness = settings.Brightness
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient
end

-- Лобби: ждём, пока в круге START SHIFT кто-то постоит до конца отсчёта (LobbyService).
-- Возвращает команду из круга — она и идёт на смену.
local function runLobby(): { Player }
	setLighting(Config.Lighting.Lobby)
	setPhase(Phase.Lobby, nil)
	RoleService.setConsoleEnabled(false)
	LobbyService.open()
	while true do
		if LobbyService.teamReady() then
			local team = LobbyService.takeTeam()
			if #team > 0 then
				return team
			end
			LobbyService.open() -- вся команда успела уйти с сервера — ждём заново
		end
		tick()
	end
end

-- День: светло, туристы, покупки. Возвращает false, если все ушли.
local function runDay(night: number): boolean
	VoteService.admitApproved() -- кого пустили голосованием, входят с утра
	ExhibitService.returnAll()
	HeistFx.resetForDay() -- следы воров убраны: витрины, дыры в полу, дыра в стеклянном потолке
	BlackoutService.reset() -- утром свет снова есть
	setLighting(Config.Lighting.Day)
	MapBuilder.setDayLights(map, true) -- днём горят люстры
	GameState.set(Attr.NightNumber, night)
	local length = daySeconds(night)
	setPhase(Phase.Day, length)
	RoleService.setConsoleEnabled(true)
	TrapService.beginDay()
	ScoreService.beginDay()
	TouristService.beginDay(ExhibitService.totalAppeal(), length)
	HallService.setDayActive(true)
	ExhibitService.setDayActive(true)
	CameraService.setDayActive(true)
	ArmoryService.setDayActive(true)
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
	CameraService.setDayActive(false)
	ArmoryService.setDayActive(false)
	setLighting(Config.Lighting.Night)
	MapBuilder.setDayLights(map, false) -- ночью только дежурные лампы и фонарики
	local length = nightSeconds(night)
	GameState.set(Attr.NightStartedAt, now())
	setPhase(Phase.Night, length)
	TrapService.beginNight()
	RoleService.gatherAtPainting() -- ночь начинается: все охранники у Моны Лизы
	local participants = RoleService.participants()
	ScoreService.beginNight(participants)
	Audio.startMusic(Config.Sounds.NightMusic)

	local survived, aborted = true, false
	local escapedConnection = ThiefService.Escaped.Event:Connect(function()
		survived = false
	end)
	ThiefService.beginNight(night)
	WaveService.beginNight(#participants, night, length) -- волны воров и их планы
	CatchService.beginNight(night) -- кнопки Check ID на охранниках (с ночи Фальшивого охранника)
	bannerRemote:FireAllClients(("NIGHT %d"):format(night), "danger")

	while survived and GameState.secondsLeft() > 0 do
		if not anyoneLeft() then
			aborted = true
			break
		end
		if HealthService.allDown() then
			-- Лежат все охранники: грабители забирают всё, игра проиграна (блок 4)
			survived = false
			bannerRemote:FireAllClients("ALL GUARDS ARE DOWN!", "danger")
			break
		end
		tick()
	end

	escapedConnection:Disconnect()
	CatchService.endNight()
	WaveService.endNight()
	ThiefService.endNight()
	BlackoutService.reset()
	HealthService.endNight() -- кто пролежал до утра, встаёт
	WeaponService.endNight() -- оружие из рук
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
	results.plans = WaveService.usedPlans() -- «Thieves used: …» — единственная подсказка о планах воров
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
	CameraService.setDayActive(false)
	CameraService.reset() -- остаётся только бесплатная камера на Мону Лизу
	ArmoryService.setDayActive(false)
	WaveService.endNight()
	ThiefService.endNight()
	HeistFx.resetForDay()
	BlackoutService.reset()
	TrapService.clear()
	RoleService.endRound()
	RoleService.setConsoleEnabled(false)
	ExhibitService.setDayActive(false)
	ExhibitService.reset()
	setLighting(Config.Lighting.Lobby)
	MapBuilder.setDayLights(map, false)
	GameState.set(Attr.NightNumber, 0)
end

while true do
	local team = runLobby()
	local participants = RoleService.startRound(team)
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
