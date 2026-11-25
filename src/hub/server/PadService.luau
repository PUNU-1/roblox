-- Круги-команды хаба (блок 6): 5 одинаковых светящихся кругов на полу, на каждом своя команда 1–5 человек.
-- Встал в круг — вошёл в команду, вышел — вышел. Кто встал первым — создатель: идёт отсчёт 30 сек,
-- создатель может нажать START раньше и включить Friends only (новых пускают, только если они его друзья;
-- кто уже в команде — остаётся). Создатель ушёл — создателем становится следующий, Friends only выключается.
-- Кто в круге, сервер проверяет раз в Config.Hub.CheckSeconds по расстоянию (как круг START SHIFT в музее).
-- Клиентам — атрибуты круга (GameState.PadAttr) и атрибут игрока Pad. Отсчёт кончился — телепорт команды.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PadAttr = GameState.PadAttr
local PadState = GameState.PadState
local PlayerAttr = GameState.PlayerAttr
local Settings = Config.Hub

local Teleporter = require(script.Parent:WaitForChild("Teleporter"))

local STUDIO_TEXT = Teleporter.StudioText

local PadService = {}

type Pad = {
	index: number,
	part: BasePart,
	members: { Player }, -- по порядку входа: первый — создатель
	friendsOnly: boolean,
	endsAt: number, -- когда кончится отсчёт; 0 — отсчёта нет
	state: string, -- GameState.PadState
	stateUntil: number, -- Blocked — до какого времени висит надпись; Launching — когда сдаться и открыть круг
	message: string,
}

-- Отправить команду (её задаёт Hub.server: телепорт в музей). Возвращает удалось ли и текст ошибки.
export type Launcher = (team: { Player }) -> (boolean, string?)

local pads: { Pad } = {}
local launcher: Launcher = function(_team: { Player })
	return false, STUDIO_TEXT
end
local friendCache: { [string]: boolean } = {}
local friendPending: { [string]: boolean } = {}

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
	if math.abs(offset.Y) > Settings.PadHeight then
		return false
	end
	return Vector2.new(offset.X, offset.Z).Magnitude <= Settings.PadRadius
end

-- Друг ли игрок создателю (Friends only). Ответ Roblox приходит не сразу: пока ждём — «нет».
-- Ошибку сети тоже считаем «нет»: лучше не пустить чужого, чем пустить.
local function isFriend(creator: Player, player: Player): boolean
	local key = ("%d:%d"):format(creator.UserId, player.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	if not friendPending[key] then
		friendPending[key] = true
		task.spawn(function()
			local ok, result = pcall(creator.IsFriendsWithAsync, creator, player.UserId)
			friendPending[key] = nil
			if not ok then
				warn(("[PadService] Не удалось проверить дружбу %s и %s: %s"):format(creator.Name, player.Name, tostring(result)))
			end
			if ok and creator.Parent and player.Parent then
				friendCache[key] = result == true
			end
		end)
	end
	return false
end

local function padOfPlayer(player: Player): Pad?
	for _, pad in pads do
		if table.find(pad.members, player) then
			return pad
		end
	end
	return nil
end

local function setPlayerPad(player: Player, index: number)
	if player:GetAttribute(PlayerAttr.Pad) ~= index then
		player:SetAttribute(PlayerAttr.Pad, index)
	end
end

local function setAttr(part: BasePart, name: string, value: any)
	if part:GetAttribute(name) ~= value then
		part:SetAttribute(name, value)
	end
end

-- Состояние круга — клиентам (табличка, цвет, панель создателя).
local function publish(pad: Pad)
	local ids = {}
	for _, player in pad.members do
		table.insert(ids, tostring(player.UserId))
	end
	setAttr(pad.part, PadAttr.Team, table.concat(ids, ","))
	setAttr(pad.part, PadAttr.FriendsOnly, pad.friendsOnly)
	setAttr(pad.part, PadAttr.EndsAt, pad.endsAt)
	setAttr(pad.part, PadAttr.State, pad.state)
	setAttr(pad.part, PadAttr.Message, pad.message)
end

local function setMembers(pad: Pad, list: { Player })
	for _, player in pad.members do
		if player.Parent and not table.find(list, player) then
			setPlayerPad(player, 0)
		end
	end
	pad.members = list
	for _, player in list do
		setPlayerPad(player, pad.index)
	end
end

local function banner(team: { Player }, text: string, kind: string)
	local remote = Remotes.get(Remotes.Names.Banner)
	for _, player in team do
		if player.Parent then
			remote:FireClient(player, text, kind)
		end
	end
end

-- Надпись вместо отсчёта (телепорт не работает в Studio или не удался); потом круг снова ждёт.
local function block(pad: Pad, message: string, seconds: number)
	pad.state = PadState.Blocked
	pad.message = message
	pad.stateUntil = now() + seconds
	pad.endsAt = 0
	publish(pad)
	banner(pad.members, message, "danger")
end

local function reopen(pad: Pad)
	pad.state = PadState.Open
	pad.friendsOnly = false
	pad.message = ""
	pad.stateUntil = 0
	pad.endsAt = 0
end

-- Отсчёт кончился: команда улетает. Пока летит, в круг никто не входит и класс не меняется.
local function launch(pad: Pad)
	pad.state = PadState.Launching
	pad.message = "Teleporting to the museum..."
	pad.stateUntil = now() + Settings.LaunchTimeout
	publish(pad)
	local team = table.clone(pad.members)
	task.spawn(function()
		local ok, message = launcher(team)
		if not ok and pad.state == PadState.Launching then
			local text = message or "Teleport failed — try again"
			local lasting = text == STUDIO_TEXT or text == Teleporter.MuseumNotFoundText -- само не пройдёт
			block(pad, text, if lasting then Settings.BlockedSeconds else Settings.FailedSeconds)
		end
	end)
end

local function update(pad: Pad)
	local time = now()
	if pad.state == PadState.Launching then
		-- Улетевшие уходят с сервера сами; не улетели за LaunchTimeout — круг снова открыт
		local still = {}
		for _, player in pad.members do
			if player.Parent then
				table.insert(still, player)
			end
		end
		setMembers(pad, still)
		if #still == 0 or time >= pad.stateUntil then
			reopen(pad)
		end
		publish(pad)
		return
	end
	if pad.state == PadState.Blocked and time >= pad.stateUntil then
		reopen(pad)
	end

	local center = pad.part.Position
	local list: { Player } = {}
	-- Кто уже в команде и всё ещё в круге — остаётся на своём месте
	for _, player in pad.members do
		if player.Parent and isInside(player, center) then
			table.insert(list, player)
		end
	end
	-- Создатель сменился (или круг опустел) — Friends only выключается: друзья были не его
	if list[1] ~= pad.members[1] then
		pad.friendsOnly = false
	end
	-- Новые — пока есть места и (если Friends only) они друзья создателя
	for _, player in Players:GetPlayers() do
		if #list >= Config.Players.Max then
			break
		end
		if not table.find(list, player) and isInside(player, center) then
			local other = padOfPlayer(player)
			local creator = list[1]
			if (other == nil or other == pad) and (not pad.friendsOnly or creator == nil or isFriend(creator, player)) then
				table.insert(list, player)
			end
		end
	end
	setMembers(pad, list)

	if #list == 0 then
		pad.endsAt = 0
	elseif pad.state == PadState.Open then
		if pad.endsAt == 0 then
			pad.endsAt = time + Settings.CountdownSeconds
		end
		if time >= pad.endsAt then
			launch(pad)
			return
		end
	end
	publish(pad)
end

-- Игрок в команде, которая сейчас улетает (класс уже упакован в данные телепорта).
function PadService.isLaunching(player: Player): boolean
	local pad = padOfPlayer(player)
	return pad ~= nil and pad.state == PadState.Launching
end

-- Hub.server: чем отправлять команду (телепорт в музей).
function PadService.setLauncher(fn: Launcher)
	launcher = fn
end

local function onPadAction(player: Player, action: any, value: any)
	local pad = padOfPlayer(player)
	if not pad or pad.members[1] ~= player or typeof(action) ~= "string" then
		return -- только создатель своего круга
	end
	if action == "Start" then
		if pad.state == PadState.Open and isInside(player, pad.part.Position) then
			pad.endsAt = now() -- старт сейчас, отсчёт до конца не ждём
			update(pad)
		end
	elseif action == "FriendsOnly" then
		if typeof(value) == "boolean" and pad.state ~= PadState.Launching then
			pad.friendsOnly = value
			publish(pad)
		end
	end
end

function PadService.init(parts: { BasePart })
	for index, part in parts do
		local pad: Pad = {
			index = index,
			part = part,
			members = {},
			friendsOnly = false,
			endsAt = 0,
			state = PadState.Open,
			stateUntil = 0,
			message = "",
		}
		table.insert(pads, pad)
		publish(pad)
	end

	Remotes.get(Remotes.Names.PadAction).OnServerEvent:Connect(onPadAction)
	Players.PlayerAdded:Connect(function(player)
		setPlayerPad(player, 0)
	end)
	for _, player in Players:GetPlayers() do
		setPlayerPad(player, 0)
	end
	Players.PlayerRemoving:Connect(function(player)
		local pad = padOfPlayer(player)
		if pad then
			local index = table.find(pad.members, player)
			if index then
				table.remove(pad.members, index) -- ушёл с сервера (или улетел) — место свободно сразу
				if index == 1 then
					pad.friendsOnly = false
				end
			end
			publish(pad)
		end
		-- Ответы «друг ли» с этим игроком больше не нужны
		local id = tostring(player.UserId)
		for key in friendCache do
			local a, b = string.match(key, "^(-?%d+):(-?%d+)$")
			if a == id or b == id then
				friendCache[key] = nil
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Settings.CheckSeconds)
			for _, pad in pads do
				update(pad)
			end
		end
	end)
end

return PadService
