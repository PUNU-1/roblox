-- Умения классов (блок 5). Клиент только просит («UseAbility», имя умения), сервер решает всё сам:
-- подходит ли умение классу, идёт ли смена (день или ночь), может ли охранник действовать (не лежит,
-- не смотрит камеры), прошла ли перезарядка, где встанет датчик, кого учуяла собака.
--  • Operator — телефон с камерами (RoleService, CameraController);
--  • Assault — здоровье (HealthService) и отдача (Weapons.client).
-- Состояние умения — в атрибутах игрока (AbilityReadyAt, AbilityUntil, AbilityCharges): по ним клиент
-- рисует кнопку умения с полоской перезарядки (Abilities.client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))

local PlayerAttr = GameState.PlayerAttr
local Phase = GameState.Phase
local Classes = Config.Classes

local AbilityService = {}

type Handler = (player: Player, info: { [string]: any }) -> ()
local handlers: { [string]: Handler } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function onShiftPhase(): boolean
	local phase = GameState.phase()
	return phase == Phase.Day or phase == Phase.Night
end

local function readyAt(player: Player): number
	return tonumber(player:GetAttribute(PlayerAttr.AbilityReadyAt)) or 0
end

local function onUseAbility(player: Player, name: any)
	if typeof(name) ~= "string" then
		return
	end
	local info = GameState.classInfo(GameState.roleOf(player))
	if not info or info.Ability ~= name then
		return -- умение не этого класса
	end
	local handler = handlers[name]
	if not handler or not onShiftPhase() or not RoleService.canAct(player) then
		return
	end
	if readyAt(player) > now() + Classes.AbilitySlack then
		return -- ещё перезаряжается
	end
	handler(player, info)
end

-- Умение сброшено: готово, ничего не действует.
local function resetPlayer(player: Player)
	player:SetAttribute(PlayerAttr.AbilityReadyAt, 0)
	player:SetAttribute(PlayerAttr.AbilityUntil, 0)
	player:SetAttribute(PlayerAttr.AbilityCharges, 0)
end

---------------------------------------------------------------- фазы

-- Утро нового дня (и первый день забега).
function AbilityService.beginDay()
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
	end
end

function AbilityService.beginNight() end

-- Ночь кончилась.
function AbilityService.endNight()
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
		RoleService.refreshMovement(player)
	end
end

-- Конец забега: всё убрать.
function AbilityService.resetRun()
	AbilityService.endNight()
end

function AbilityService.init(_map: Instance)
	Remotes.get(Remotes.Names.UseAbility).OnServerEvent:Connect(onUseAbility)
	Players.PlayerAdded:Connect(resetPlayer)
	for _, player in Players:GetPlayers() do
		resetPlayer(player)
	end
end

return AbilityService
