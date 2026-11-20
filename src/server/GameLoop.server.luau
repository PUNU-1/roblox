-- Игровой цикл: Lobby -> Prep -> Night -> Results -> снова Lobby.
-- Сервер решает всё: когда начинается ночь, кто участвует, чем она закончилась.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local MapBuilder = require(Server:WaitForChild("MapBuilder"))
local RoleService = require(Server:WaitForChild("RoleService"))
local ScoreService = require(Server:WaitForChild("ScoreService"))
local PaintingService = require(Server:WaitForChild("PaintingService"))
local ThiefService = require(Server:WaitForChild("ThiefService"))
local CatchService = require(Server:WaitForChild("CatchService"))
local Audio = require(Server:WaitForChild("Audio"))

local Phase = GameState.Phase
local Attr = GameState.Attr

local map = MapBuilder.build()
RoleService.init(map)
PaintingService.init(map)
ThiefService.init(map)
CatchService.init()

local resultsRemote = Remotes.get(Remotes.Names.NightResults)

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

-- Лобби: ждём, пока все нажмут READY или пройдёт отсчёт после первого READY.
local function runLobby()
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

-- Подготовка: игроки в зале, ставят сетки. Возвращает false, если все ушли.
local function runPrep(): boolean
	PaintingService.returnToWall()
	setPhase(Phase.Prep, Config.Phases.PrepSeconds)
	RoleService.startRound()
	RoleService.setConsoleEnabled(true)
	while GameState.secondsLeft() > 0 do
		if not anyoneLeft() then
			return false
		end
		tick()
	end
	return true
end

-- Ночь. Возвращает: survived (картина на месте), aborted (все ушли).
local function runNight(): (boolean, boolean)
	setPhase(Phase.Night, Config.Phases.NightSeconds)
	GameState.set(Attr.NightStartedAt, now())
	local participants = RoleService.participants()
	ScoreService.beginNight(participants)
	Audio.startMusic()

	local survived, aborted = true, false
	local escapedConnection = ThiefService.Escaped.Event:Connect(function()
		survived = false
	end)
	ThiefService.beginNight(#participants)

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

local function runResults(survived: boolean)
	RoleService.closeAllViews()
	RoleService.setConsoleEnabled(false)
	setPhase(Phase.Results, Config.Phases.ResultsSeconds)
	resultsRemote:FireAllClients(ScoreService.finish(survived))
	while GameState.secondsLeft() > 0 do
		tick()
	end
end

local function finishRound()
	RoleService.endRound()
	PaintingService.returnToWall()
end

while true do
	runLobby()
	if runPrep() then
		local survived, aborted = runNight()
		if not aborted then
			runResults(survived)
		end
	end
	finishRound()
end
