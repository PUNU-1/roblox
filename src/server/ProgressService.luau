-- Прогресс игрока (этап 6, блок H1, решение 85): опыт, уровни и звания, ежедневные задания, достижения.
-- Общий для хаба и музея (hub.project.json подключает этот файл). Сервисы музея сообщают, что произошло
-- (arrest, nightEnded, teamBought, revived, stunned, cameraRepaired, runStarted), этот модуль превращает это
-- в опыт и счётчики заданий и отдаёт ProfileStore (тот сохраняет разницей, внутри UpdateAsync).
-- Игроку — Remote ProgressEvent: LEVEL UP, «Quest done», новое достижение. Над головой — плашка «LV 7 GUARD».
-- Клиенту не доверяем ничего: всё считает сервер.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local Settings = Config.Progress
local PlayerAttr = GameState.PlayerAttr
local Status = GameState.ProfileStatus

local ProgressService = {}

local PLATE_NAME = "RankPlate"

local started = false
local hideOwnPlate = false -- музей: от первого лица своя плашка мешала бы смотреть вверх
local eventRemote: RemoteEvent
local connections: { [Player]: { RBXScriptConnection } } = {}
local wingsRun: { [Player]: number } = {} -- в сколько крыльев игрок вложил за этот забег (достижение Shop Lover)

local okFont, pixelFont = pcall(Font.new, Config.PixelUI.Font)
local PLATE_FONT = if okFont then pixelFont else Font.fromEnum(Enum.Font.Arcade)

---------------------------------------------------------------- плашка над головой

-- Текст и цвет плашки: «LV 7 GUARD». nil — профиль ещё не загружен (плашки нет).
local function plateInfo(player: Player): (string?, Color3)
	local status = player:GetAttribute(PlayerAttr.ProfileStatus)
	if status ~= Status.Ready and status ~= Status.Offline then
		return nil, Color3.new(1, 1, 1)
	end
	local level = tonumber(player:GetAttribute(PlayerAttr.Level)) or 1
	local rank = Progress.rankOf(level)
	return ("LV %d %s"):format(level, rank.Name), rank.Color
end

local function buildPlate(text: string, color: Color3): BillboardGui
	local plate = Settings.Plate
	local billboard = Instance.new("BillboardGui")
	billboard.Name = PLATE_NAME
	billboard.Size = UDim2.fromOffset(#text * plate.TextSize + 16, plate.TextSize + 10)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, plate.Height, 0)
	billboard.MaxDistance = plate.MaxDistance
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Name = "Box"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromHex("151821")
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = PLATE_FONT
	label.TextSize = plate.TextSize
	label.TextColor3 = color
	label.Text = text
	label.Parent = frame
	return billboard
end

-- Плашка на модели (персонаж игрока; копия — у Фальшивого охранника, она не обновляется).
local function setPlate(model: Model, text: string?, color: Color3, hideFrom: Player?)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild(PLATE_NAME)
	if old then
		old:Destroy()
	end
	if not text then
		return
	end
	local plate = buildPlate(text, color)
	plate.PlayerToHideFrom = hideFrom
	plate.Adornee = head
	plate.Parent = head
end

local function refreshPlate(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local text, color = plateInfo(player)
	setPlate(character, text, color, if hideOwnPlate then player else nil)
end

-- Фальшивый охранник (план FakeGuard) — копия игрока, поэтому и плашка как у него: иначе его видно сразу.
function ProgressService.attachPlate(model: Model, player: Player)
	local text, color = plateInfo(player)
	setPlate(model, text, color, nil)
end

---------------------------------------------------------------- салют и надписи

-- Салют над игроком (видят все): разноцветные искры вверх и вниз.
local function salute(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local fx = Settings.Salute
	local attachment = Instance.new("Attachment")
	attachment.Name = "LevelUpSalute"
	attachment.Position = Vector3.new(0, 3, 0)
	attachment.Parent = root
	local keys = {}
	for index, color in fx.Colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / math.max(1, #fx.Colors - 1), color))
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(keys)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.1) })
	emitter.Lifetime = NumberRange.new(1.2, 1.9)
	emitter.Speed = NumberRange.new(16, 28)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, -32, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(fx.Particles)
	Debris:AddItem(attachment, 3)
end

-- Показать игроку, что случилось (надписи рисует клиент: UI/ProgressFx).
local function announce(player: Player, events: Progress.Events)
	if not player.Parent then
		return
	end
	if #events.levels > 0 then
		local level = events.levels[#events.levels]
		local rank = events.ranks[#events.ranks] or ""
		local diamonds = #events.levels * Settings.LevelDiamonds + #events.ranks * Settings.RankDiamonds
		eventRemote:FireClient(player, "LevelUp", level, rank, diamonds)
		salute(player)
	end
	for _, quest in events.quests do
		eventRemote:FireClient(player, "Quest", Progress.questText(quest), quest.r)
	end
	for _, id in events.badges do
		local info = (Config.Badges :: any)[id]
		eventRemote:FireClient(player, "Badge", if info then tostring(info.Title) else id)
	end
end

local function send(player: Player, delta: Progress.Delta)
	local events = ProfileStore.addProgress(player, delta)
	if events then
		announce(player, events)
	end
end

local function questCount(delta: Progress.Delta, key: string, amount: number)
	delta.questDay = GameState.dayNumber(os.time())
	delta.quest[key] = (delta.quest[key] or 0) + amount
end

---------------------------------------------------------------- что произошло (музей)

-- Свой арест (вор, сдавшийся или оглушённый грабитель). kind — вид вора (ThiefAttr.Kind), если есть.
function ProgressService.arrest(player: Player, kind: any)
	local delta = Progress.newDelta()
	delta.xp = Settings.XpArrest
	delta.stats.arrests = 1
	questCount(delta, "Arrest", 1)
	if typeof(kind) == "string" and table.find(Config.ThiefOrder, kind) then
		delta.kinds[kind] = true
	end
	send(player, delta)
end

-- Ночь кончилась, игрок был на смене. survived — пережили; raided — этой ночью был налёт.
function ProgressService.nightEnded(player: Player, survived: boolean, raided: boolean)
	local delta = Progress.newDelta()
	questCount(delta, "PlayClass:" .. GameState.roleOf(player), 1) -- «сыграй ночь за класс» — и проигранная считается
	if survived then
		delta.xp = Settings.XpNight
		delta.stats.nights = 1
		questCount(delta, "Survive", 1)
		if raided then
			delta.stats.raids = 1
		end
	end
	send(player, delta)
end

-- Покупка для команды (кнопка F или окно магазина, складчина) закончена. backers — все, кто вкладывал.
-- what: "Wing" | "Hall" | "Exhibit" | "Camera" | "Trap".
function ProgressService.teamBought(backers: { Player }, what: string)
	for _, player in backers do
		if player.Parent then
			local delta = Progress.newDelta()
			delta.xp = Settings.XpTeamBuy
			if what == "Wing" then
				questCount(delta, "BuyWing", 1)
				wingsRun[player] = (wingsRun[player] or 0) + 1
				delta.best.wingsRun = wingsRun[player]
			elseif what == "Exhibit" then
				questCount(delta, "BuyExhibit", 1)
			end
			send(player, delta)
		end
	end
end

-- Поднял лежащего друга.
function ProgressService.revived(reviver: Player)
	local delta = Progress.newDelta()
	delta.xp = Settings.XpRevive
	delta.stats.revives = 1
	questCount(delta, "Revive", 1)
	send(reviver, delta)
end

-- Попал шокером в вора или грабителя.
function ProgressService.stunned(player: Player)
	local delta = Progress.newDelta()
	questCount(delta, "Taser", 1)
	send(player, delta)
end

-- Починил камеру (у её таблички).
function ProgressService.cameraRepaired(player: Player)
	local delta = Progress.newDelta()
	questCount(delta, "Repair", 1)
	send(player, delta)
end

-- Начался забег (достижение Night Owl — 10 забегов).
function ProgressService.runStarted(players: { Player })
	for _, player in players do
		wingsRun[player] = 0
		local delta = Progress.newDelta()
		delta.stats.runs = 1
		send(player, delta)
	end
end

---------------------------------------------------------------- запуск

local function onPlayerAdded(player: Player)
	if connections[player] then
		return
	end
	connections[player] = {
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			if character.Parent then
				refreshPlate(player)
			end
		end),
		player:GetAttributeChangedSignal(PlayerAttr.Level):Connect(function()
			refreshPlate(player)
		end),
		player:GetAttributeChangedSignal(PlayerAttr.ProfileStatus):Connect(function()
			refreshPlate(player)
		end),
	}
	if player.Character then
		refreshPlate(player)
	end
end

local function onPlayerRemoving(player: Player)
	local list = connections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[player] = nil
	end
	wingsRun[player] = nil
end

-- options.hideOwnPlate — своя плашка не видна самому игроку (музей, вид от первого лица).
function ProgressService.init(options: { hideOwnPlate: boolean? }?)
	if started then
		return
	end
	started = true
	hideOwnPlate = options ~= nil and options.hideOwnPlate == true
	eventRemote = Remotes.get(Remotes.Names.ProgressEvent)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	-- Новый день (00:00 UTC) — новые задания и у тех, кто сидит в игре
	task.spawn(function()
		while true do
			task.wait(Settings.DayCheckSeconds)
			for _, player in Players:GetPlayers() do
				ProfileStore.refreshDay(player)
			end
		end
	end)
end

return ProgressService
