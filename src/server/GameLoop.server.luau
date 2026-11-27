-- Игровой цикл — забег на выживание: Лобби -> (День -> Ночь -> Итог) x N -> снова Лобби.
-- Цель — продержаться как можно больше ночей. Мону Лизу вынесли — игра окончена, всё с нуля.
-- Сервер решает всё: когда начинается ночь, кто участвует, чем она закончилась.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
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
local RobberService = require(Server:WaitForChild("RobberService"))
local AbilityService = require(Server:WaitForChild("AbilityService"))
local TrapService = require(Server:WaitForChild("TrapService"))
local CommsService = require(Server:WaitForChild("CommsService"))
local TouristService = require(Server:WaitForChild("TouristService"))
local HallService = require(Server:WaitForChild("HallService"))
local WingService = require(Server:WaitForChild("WingService"))
local CameraService = require(Server:WaitForChild("CameraService"))
local DoorService = require(Server:WaitForChild("DoorService"))
local VoteService = require(Server:WaitForChild("VoteService"))
local HubLink = require(Server:WaitForChild("HubLink"))
local RecordStore = require(Server:WaitForChild("RecordStore"))
local Audio = require(Server:WaitForChild("Audio"))
local ProfileStore = require(Server:WaitForChild("ProfileStore"))
local ProgressService = require(Server:WaitForChild("ProgressService"))
local Purchase = require(Server:WaitForChild("Purchase"))
local ShopService = require(Server:WaitForChild("ShopService"))
local ChestService = require(Server:WaitForChild("ChestService"))
local FriendService = require(Server:WaitForChild("FriendService"))

local Phase = GameState.Phase
local Attr = GameState.Attr

ProfileStore.init() -- алмазы 💎 и купленные классы (этап 4, блок 1): грузятся сразу, как игрок вошёл
-- Опыт, уровни, задания, достижения (этап 6, блок H1). От первого лица своя плашка над головой не видна
ProgressService.init({ hideOwnPlate = true })
ChestService.init() -- сундук после ночи (этап 6, блок H2)
FriendService.startRecords() -- рекорды друзей для GAME OVER (этап 6, блок H2)
ModelLibrary.setupCollisionGroups()
-- Тени и реалистичная графика в музее: мягкие тени, отражения, bloom, цветокоррекция и лёгкая дымка
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.35

local function getOrCreate<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing :: any
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created :: any
end

local museumBloom: BloomEffect = getOrCreate("BloomEffect", "MuseumBloom")
museumBloom.Size = 18

local museumColor: ColorCorrectionEffect = getOrCreate("ColorCorrectionEffect", "MuseumColor")
museumColor.Brightness = 0

local museumAtmosphere: Atmosphere = getOrCreate("Atmosphere", "MuseumAtmosphere")
museumAtmosphere.Offset = 0.25
museumAtmosphere.Glare = 0.15
museumAtmosphere.Haze = 0.6
local map = MapBuilder.build()
ShopService.init(map) -- окно магазина (этап 4, блок 1b): товары регистрируют сервисы ниже
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
RobberService.init(map)
AbilityService.init(map) -- умения классов: рывок, датчик движения, собака (блок 5)
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
WingService.init(map) -- крылья (этап 5, блок B): до залов — зал угла открывается из своего крыла
HallService.init(map)
CameraService.init(map)
DoorService.init(map)
VoteService.init()
HubLink.init() -- блок 6: команда и классы из хаба
VoteService.setAutoApprove(HubLink.isLateTeammate)
VoteService.setIgnoreJoiner(HubLink.isLeaving)

-- Что смотрят туристы: Мону Лизу и купленные экспонаты в открытых залах.
TouristService.setAttractions(ExhibitService.attractions)

local resultsRemote = Remotes.get(Remotes.Names.NightResults)
local progressRemote = Remotes.get(Remotes.Names.ProgressEvent)
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

-- Длина дня и ночи растёт с каждым днём забега (решения 66, 77): день 45 -> 60 сек, ночь 2 -> 5 мин.
local function daySeconds(day: number): number
	local phases = Config.Phases
	return math.min(phases.DayMaxSeconds, phases.DayFirstSeconds + (day - 1) * phases.DayGrowSeconds)
end

local function nightSeconds(night: number): number
	local phases = Config.Phases
	return math.min(phases.NightMaxSeconds, phases.NightFirstSeconds + (night - 1) * phases.NightGrowSeconds)
end

local function setLighting(settings: { [string]: any })
	Lighting.ClockTime = settings.ClockTime
	Lighting.Brightness = settings.Brightness
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient
	if settings.DiffuseScale ~= nil then
		Lighting.EnvironmentDiffuseScale = settings.DiffuseScale
	end
	if settings.SpecularScale ~= nil then
		Lighting.EnvironmentSpecularScale = settings.SpecularScale
	end
	if settings.BloomIntensity ~= nil then
		museumBloom.Intensity = settings.BloomIntensity
		museumBloom.Threshold = settings.BloomThreshold or 1.1
	end
	if settings.Contrast ~= nil then
		museumColor.Contrast = settings.Contrast
		museumColor.Saturation = settings.Saturation or 0
		museumColor.TintColor = settings.TintColor or Color3.new(1, 1, 1)
	end
	if settings.AtmosphereDensity ~= nil then
		museumAtmosphere.Density = settings.AtmosphereDensity
		museumAtmosphere.Color = settings.AtmosphereColor or Color3.fromRGB(200, 200, 210)
	end
end

-- Лобби: ждём, пока в круге START SHIFT кто-то постоит до конца отсчёта (LobbyService).
-- Возвращает команду из круга — она и идёт на смену.
-- Блок 6: команда прилетела из хаба — круг не нужен, ждём всю команду (HubLink) и сразу в музей.
local function runLobby(): { Player }
	setLighting(Config.Lighting.Lobby)
	setPhase(Phase.Lobby, nil)
	RoleService.setConsoleEnabled(false)
	LobbyService.open()
	while true do
		if HubLink.teamPending() then
			LobbyService.takeTeam() -- круг START SHIFT закрыт, пока ждём команду из хаба
			local hubTeam = HubLink.waitForTeam()
			if #hubTeam > 0 then
				return hubTeam
			end
			LobbyService.open() -- никто не долетел — лобби как обычно
		end
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
	AbilityService.beginDay() -- умения готовы, у техника снова есть датчик
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
	WingService.setDayActive(true)
	HallService.setDayActive(true)
	ExhibitService.setDayActive(true)
	CameraService.setDayActive(true)
	ArmoryService.setDayActive(true)
	ShopService.setDayActive(true)
	bannerRemote:FireAllClients(("DAY %d"):format(night), "info")
	Audio.startMusic(Config.Sounds.DayMusic)
	local closing = false
	local touristsGone = false
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
		-- За секунду до ночи все, кто не успел выйти, плавно тают (этап 5, блок E): к ночи туристов нет
		if not touristsGone and GameState.secondsLeft() <= Config.Tourists.FadeBeforeNightSeconds then
			touristsGone = true
			TouristService.fadeAll()
		end
		tick()
	end
	return true
end

-- Ночь. Возвращает: survived (картина на месте), aborted (все ушли).
local function runNight(night: number): (boolean, boolean)
	TouristService.endDay()
	WingService.setDayActive(false)
	HallService.setDayActive(false)
	ExhibitService.setDayActive(false)
	CameraService.setDayActive(false)
	ArmoryService.setDayActive(false)
	ShopService.setDayActive(false)
	setLighting(Config.Lighting.Night)
	MapBuilder.setDayLights(map, false) -- ночью только дежурные лампы и фонарики
	local length = nightSeconds(night)
	GameState.set(Attr.NightStartedAt, now())
	setPhase(Phase.Night, length)
	TrapService.beginNight()
	RoleService.gatherAtPainting() -- ночь начинается: все охранники у Моны Лизы
	AbilityService.beginNight()
	local participants = RoleService.participants()
	ScoreService.beginNight(participants)
	Audio.startMusic(Config.Sounds.NightMusic)

	local survived, aborted = true, false
	local escapedConnection = ThiefService.Escaped.Event:Connect(function()
		survived = false
	end)
	-- Грабитель налёта вынес Мону Лизу — тоже конец (блок 4)
	local robberConnection = RobberService.Escaped.Event:Connect(function()
		survived = false
	end)
	ThiefService.beginNight(night)
	RobberService.beginNight()
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
	robberConnection:Disconnect()
	CatchService.endNight()
	WaveService.endNight()
	RobberService.endNight()
	ThiefService.endNight()
	BlackoutService.reset()
	HealthService.endNight() -- кто пролежал до утра, встаёт
	AbilityService.endNight() -- датчики убираются, собаки успокаиваются
	WeaponService.endNight() -- оружие из рук
	Audio.stopMusic()
	return survived, aborted
end

-- Итог ночи. Конец забега (картину вынесли) — экран GAME OVER с кнопками Play again / Lobby (блок 6):
-- возвращает тех, кто нажал Play again (с ними сразу новый забег), остальные идут в лобби.
local function runResults(survived: boolean, night: number): { Player }
	RoleService.closeAllViews()
	local gameOver = not survived
	setPhase(Phase.Results, if gameOver then Config.GameOver.ChoiceSeconds else Config.Phases.ResultsSeconds)
	-- Был ли этой ночью налёт (достижение Raid Survivor)
	local raided = table.find(WaveService.usedPlans(), Config.Raid.Title) ~= nil
	local results = ScoreService.finish(survived, raided)
	local nightsSurvived = if survived then night else night - 1
	if not survived then
		bestNights = math.max(bestNights, nightsSurvived)
		GameState.set(Attr.BestNights, bestNights)
		-- Рекорд команды — на общую доску рекордов в хабе (блок 6; в Studio не пишется)
		local ids = {}
		for _, player in RoleService.participants() do
			table.insert(ids, player.UserId)
		end
		RecordStore.submitAsync(ids, nightsSurvived)
	end
	-- Личный рекорд каждого (этап 6, блок H2): на GAME OVER — «1 night to beat your record!»
	results.personalBest = if gameOver then ProgressService.runEnded(RoleService.participants(), nightsSurvived) else nil
	results.night = night
	results.gameOver = not survived
	results.nightsSurvived = nightsSurvived
	results.best = bestNights
	results.plans = WaveService.usedPlans() -- «Thieves used: …» — единственная подсказка о планах воров
	results.choice = gameOver -- кнопки Play again / Lobby
	-- Сундук после пережитой ночи (этап 6, блок H2): только бесплатно, случай считает сервер
	results.chests = if survived then ChestService.grantAll(RoleService.participants(), night) else {}
	resultsRemote:FireAllClients(results)
	if gameOver then
		-- Пробный забег кончился (этап 6, блок H1): предложить купить класс в магазине хаба
		for _, player in Players:GetPlayers() do
			local trial = player:GetAttribute(GameState.PlayerAttr.TrialClass)
			local info = GameState.classInfo(trial)
			if info then
				progressRemote:FireClient(player, "TrialOver", tostring(info.Title), GameState.classPrice(trial))
			end
		end
		return HubLink.runGameOverChoice(RoleService.participants(), nightsSurvived)
	end
	while GameState.secondsLeft() > 0 do
		tick()
	end
	ChestService.flush() -- кто не открыл сундук — алмазы всё равно его
	return {}
end

-- Конец забега: всех обратно в комнату охраны, музей с нуля.
local function finishRun()
	ChestService.flush()
	Audio.stopMusic()
	VoteService.setRunActive(false)
	TouristService.endDay()
	WingService.setDayActive(false)
	WingService.reset() -- новый забег: снова открыт только центр
	HallService.setDayActive(false)
	HallService.reset()
	CameraService.setDayActive(false)
	CameraService.reset() -- остаётся только бесплатная камера на Мону Лизу
	ArmoryService.setDayActive(false)
	ShopService.setDayActive(false)
	WaveService.endNight()
	RobberService.endNight()
	RobberService.resetRun()
	AbilityService.resetRun()
	ThiefService.endNight()
	HeistFx.resetForDay()
	BlackoutService.reset()
	TrapService.clear()
	RoleService.endRound()
	RoleService.setConsoleEnabled(false)
	ExhibitService.setDayActive(false)
	ExhibitService.reset()
	Purchase.clearBackers()
	-- Класс на пробу (этап 6, блок H1) — только на один забег: снова Patrol, если так и не купил
	for _, player in Players:GetPlayers() do
		local trial = player:GetAttribute(GameState.PlayerAttr.TrialClass)
		if typeof(trial) == "string" and trial ~= "" then
			player:SetAttribute(GameState.PlayerAttr.TrialClass, "")
			if GameState.roleOf(player) == trial and not ProfileStore.owns(player, trial) then
				player:SetAttribute(GameState.PlayerAttr.Role, Config.Classes.Default)
			end
		end
	end -- вклады в недокупленное забыты: в новом забеге всё с нуля
	setLighting(Config.Lighting.Lobby)
	MapBuilder.setDayLights(map, false)
	GameState.set(Attr.NightNumber, 0)
end

local playAgain: { Player } = {} -- кто нажал Play again: с ними новый забег без лобби (блок 6)
while true do
	local team: { Player } = {}
	for _, player in playAgain do
		if player.Parent then
			table.insert(team, player)
		end
	end
	playAgain = {}
	if #team == 0 then
		team = runLobby()
	end
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
		local again = runResults(survived, night)
		if not survived then
			playAgain = again
			break
		end
	end
	finishRun()
end
