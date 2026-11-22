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
local TeleportTicket = require(Shared:WaitForChild("TeleportTicket"))

local Server = script.Parent
local HubBuilder = require(Server:WaitForChild("HubBuilder"))
local PadService = require(Server:WaitForChild("PadService"))
local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local Teleporter = require(Server:WaitForChild("Teleporter"))
local PlaceFinder = require(Server:WaitForChild("PlaceFinder"))
local Uniform = require(Server:WaitForChild("Uniform"))
local ProfileStore = require(Server:WaitForChild("ProfileStore"))

local PlayerAttr = GameState.PlayerAttr

-- Свет: в комнате всегда вечер, тени от ламп
local light = Config.Hub.Lighting
Lighting.GlobalShadows = true
Lighting.ClockTime = light.ClockTime
Lighting.Brightness = light.Brightness
Lighting.Ambient = light.Ambient
Lighting.OutdoorAmbient = light.OutdoorAmbient

PlaceFinder.init("Hub") -- место музея ищется в фоне; строка [PlaceFinder] в Output
ProfileStore.init() -- алмазы 💎 и купленные классы (этап 4, блок 1)

local map, pads = HubBuilder.build()
PadService.init(pads)
LeaderboardService.init(map) -- доска рекордов: топ-10 команд за всё время и за неделю

local bannerRemote = Remotes.get(Remotes.Names.Banner)

---------------------------------------------------------------- телепорт команды в музей

-- Отсчёт круга кончился: свой отдельный сервер музея (ReserveServer) и TeleportAsync всей команды
-- с данными { team, classes }. Место музея находит PlaceFinder. В Studio — надпись «Teleport works only in the
-- published game», в опубликованной игре без места музея — «Museum place not found — ask the owner to publish it».
PadService.setLauncher(function(team: { Player }): (boolean, string?)
	return Teleporter.toReserved(PlaceFinder.museumId(), team, TeleportTicket.pack(team))
end)

-- Кто-то не улетел (Roblox отказал уже после отправки) — он остаётся в хабе и видит надпись
Teleporter.onFailed(function(player: Player, message: string)
	bannerRemote:FireClient(player, message, "danger")
end)

---------------------------------------------------------------- игроки

local connections: { [Player]: RBXScriptConnection } = {}

local function onPlayerAdded(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- вид от первого лица, как в музее (решение 56)
	player:SetAttribute(PlayerAttr.Role, Config.Classes.Default)
	-- Форма охраны: в хабе все уже в смене (шапки и волосы остаются)
	connections[player] = player.CharacterAppearanceLoaded:Connect(function(character)
		Uniform.apply(character)
	end)
	-- Вернулся из музея — «Welcome back» и сколько ночей продержалась команда.
	-- Место музея может ещё искаться (PlaceFinder) — ждём в отдельном потоке.
	task.spawn(function()
		local museumPlaceId = PlaceFinder.museumId()
		local ok, joinData = pcall(player.GetJoinData, player)
		local nights = if ok then TeleportTicket.readReturn(joinData, museumPlaceId) else nil
		if nights then
			task.delay(4, function()
				if player.Parent then
					local text = if nights == 1 then "WELCOME BACK! YOUR TEAM SURVIVED 1 NIGHT" else ("WELCOME BACK! YOUR TEAM SURVIVED %d NIGHTS"):format(nights)
					bannerRemote:FireClient(player, text, "info")
				end
			end)
		end
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
