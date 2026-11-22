-- Хаб (блок 6) — общее лобби игры, отдельное место Hub. Большая комната охраны: раздевалка, стена мониторов,
-- доска рекордов и 5 кругов на полу. Каждый круг — своя команда 1–5 человек; отсчёт кончился — команда
-- телепортируется на свой сервер места Museum. Класс выбирается здесь (карточки, клавиши 1–5) и летит с игроком.
-- Сервер решает всё: кто в команде, когда старт, какой класс уходит в данные телепорта.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local HubBuilder = require(Server:WaitForChild("HubBuilder"))
local PadService = require(Server:WaitForChild("PadService"))
local Uniform = require(Server:WaitForChild("Uniform"))

local PlayerAttr = GameState.PlayerAttr

-- Свет: в комнате всегда вечер, тени от ламп
local light = Config.Hub.Lighting
Lighting.GlobalShadows = true
Lighting.ClockTime = light.ClockTime
Lighting.Brightness = light.Brightness
Lighting.Ambient = light.Ambient
Lighting.OutdoorAmbient = light.OutdoorAmbient

local _, pads = HubBuilder.build()
PadService.init(pads)

---------------------------------------------------------------- игроки

local connections: { [Player]: RBXScriptConnection } = {}

local function onPlayerAdded(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- вид от первого лица, как в музее (решение 56)
	player:SetAttribute(PlayerAttr.Role, Config.Classes.Default)
	-- Форма охраны: в хабе все уже в смене (шапки и волосы остаются)
	connections[player] = player.CharacterAppearanceLoaded:Connect(function(character)
		Uniform.apply(character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	local connection = connections[player]
	if connection then
		connection:Disconnect()
		connections[player] = nil
	end
end)

-- Класс (карточки, клавиши 1–5): любой из Config.Classes.Order, пока команда игрока не улетает
Remotes.get(Remotes.Names.SetRole).OnServerEvent:Connect(function(player, role)
	if not GameState.classInfo(role) or PadService.isLaunching(player) then
		return
	end
	player:SetAttribute(PlayerAttr.Role, role)
end)
