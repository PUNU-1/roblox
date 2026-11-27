-- Обучение со стрелками в каждом забеге (этап 5, блок C, решение 78). Заменило подсказки новичку (решение 36).
--
-- Что видит игрок:
--  * сверху по центру — пиксельная плашка шага: «2/9», текст, иконка; шаг выполнен — зелёная галочка и звук,
--    через Config.Tutorial.NextDelay сек следующий шаг;
--  * светящиеся шевроны по полу от игрока к цели — по пути PathfindingService (пересчёт раз в RepathSeconds), плывут
--    вперёд. Их создаёт этот скрипт, поэтому они только у этого игрока;
--  * большая прыгающая пиксельная стрелка над целью (BillboardGui, AlwaysOnTop — видна сквозь стены);
--  * кнопка SKIP (клавиша K) — пропустить обучение в этом забеге. Выключить навсегда — TUTORIAL: OFF в окне
--    HOW TO PLAY в хабе (сохраняется в профиле, атрибут TutorialOff).
--
-- Шаги, тексты и числа — Config.Tutorial.Segments: день 1, ночь 1, день 2 (+ свой шаг оператора и техника).
-- Уже сделанное засчитывается сразу. Всё здесь — только подсказки: ничего важного клиент не решает. Траты и аресты
-- забега считает сервер (атрибуты RunSpent, RunArrests), окно магазина пишет локальный атрибут ShopOpen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))

type Step = Config.TutorialStep
type Target = {
	goal: Vector3, -- куда ведут шевроны (точка на полу или рядом)
	top: Vector3, -- где висит стрелка (уже с высотой)
	near: Vector3, -- до чего считать «подошёл»
}

local Settings = Config.Tutorial
local ChevronSettings = Settings.Chevrons
local ArrowSettings = Settings.Arrow
local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

---------------------------------------------------------------- плашка шага сверху

local gui = Theme.screenGui("Tutorial", 2) -- над HUD, под окном магазина и голосованием

local PLATE_CELL = 3
local PLATE_HEIGHT = 58
local ICON_CELL = 2 -- иконка шага 32 × 32

local plate = Theme.new("Frame", {
	Name = "StepPlate",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64), -- под верхней строкой HUD (таймер)
	Size = UDim2.new(0.92, 0, 0, PLATE_HEIGHT),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, { Theme.new("UISizeConstraint", { MaxSize = Vector2.new(780, PLATE_HEIGHT) }) })
local plateScale = Theme.new("UIScale", { Parent = plate })
local _, inset = PixelIcon.box(plate, PLATE_CELL, {
	layers = { PixelIcon.Outline, Colors.Gold, Colors.Navy },
	shadow = true,
})

local counterLabel = Theme.pixelLabel({
	Name = "Counter",
	Position = UDim2.fromOffset(inset + 6, inset),
	Size = UDim2.new(0, 56, 1, -2 * inset),
	TextColor3 = Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
	Parent = plate,
}, 12, 2)

local textLabel = Theme.pixelLabel({
	Name = "Text",
	Position = UDim2.fromOffset(inset + 68, inset),
	Size = UDim2.new(1, -(2 * inset + 68 + 48), 1, -2 * inset),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	ZIndex = 6,
	Parent = plate,
}, 12, 2)

local iconHolder = Theme.new("Frame", {
	Name = "IconHolder",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -(inset + 6), 0.5, 0),
	Size = UDim2.fromOffset(16 * ICON_CELL, 16 * ICON_CELL),
	BackgroundTransparency = 1,
	ZIndex = 6,
	Parent = plate,
})

local function setIcon(name: string?)
	iconHolder:ClearAllChildren()
	if not name or not PixelIcon.Icons[name] then
		return
	end
	local icon = PixelIcon.new(name, true, 7)
	icon.Size = UDim2.fromScale(1, 1)
	icon.Parent = iconHolder
end

local skipped = false -- пропустил обучение в этом забеге (SKIP / K)
local messageText = "" -- «Tutorial complete!» / «Tutorial skipped…» вместо шага
local messageUntil = 0

local skipButton = PixelButton.text({
	text = if touchOnly then "SKIP" else "K - SKIP",
	name = "SkipTutorial",
	color = Colors.NavyLight,
	textSize = 8,
	cell = 2,
	size = UDim2.fromOffset(if touchOnly then 90 else 118, 30),
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, 0, 1, 4),
	zIndex = 6,
	parent = plate,
	onActivated = function() end, -- подключается ниже (skip объявлен позже)
})

local doneSound = Instance.new("Sound")
doneSound.Name = "TutorialStepDone"
doneSound.SoundId = Settings.DoneSound
doneSound.Volume = Settings.DoneVolume
doneSound.Parent = SoundService
Theme.bindEffects(doneSound)

local function pop()
	plateScale.Scale = 1.07
	TweenService:Create(plateScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Текст шага: на телефоне — TouchText, если есть. Пиксельный шрифт — заглавными, как окна хаба.
local function stepText(step: Step): string
	local text = if touchOnly and step.TouchText then step.TouchText else step.Text
	return string.upper(text)
end

local function fitText()
	local camera = Workspace.CurrentCamera
	local wide = camera ~= nil and camera.ViewportSize.X >= 1000
	textLabel.TextSize = if wide then 12 else 8
end

---------------------------------------------------------------- 3D: шевроны по полу и стрелка над целью

local fxFolder = Instance.new("Folder")
fxFolder.Name = "TutorialFx" -- создан клиентом: есть только у этого игрока
fxFolder.Parent = Workspace

local function newFxPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = ChevronSettings.Color
	part.Transparency = 1
	part.Size = size
	part.Parent = fxFolder
	return part
end

type Chevron = { left: Part, right: Part }
local chevrons: { Chevron } = {}
for index = 1, ChevronSettings.Count do
	local size = Vector3.new(ChevronSettings.ArmWidth, 0.08, ChevronSettings.ArmLength)
	table.insert(chevrons, { left = newFxPart("ChevronL" .. index, size), right = newFxPart("ChevronR" .. index, size) })
end

local arrowAnchor = newFxPart("ArrowAnchor", Vector3.new(0.2, 0.2, 0.2))
local arrowCells = 16 * ArrowSettings.Cell
local billboard = Theme.new("BillboardGui", {
	Name = "TutorialArrow",
	Size = UDim2.fromOffset(arrowCells + 16, arrowCells + 22),
	AlwaysOnTop = true, -- видна сквозь стены
	LightInfluence = 0,
	ResetOnSpawn = false,
	Enabled = false,
	Parent = arrowAnchor,
})
local arrowIcon = PixelIcon.new("ArrowDown", true, 2)
arrowIcon.AnchorPoint = Vector2.new(0.5, 0)
arrowIcon.Position = UDim2.fromScale(0.5, 0)
arrowIcon.Size = UDim2.fromOffset(arrowCells, arrowCells)
arrowIcon.Parent = billboard
local distanceLabel = Theme.pixelLabel({
	Name = "Distance",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.new(1, 0, 0, 16),
	TextColor3 = Color3.fromHex("FFD23F"),
	ZIndex = 3,
	Parent = billboard,
}, 8, 2)

local function hideChevrons()
	for _, chevron in chevrons do
		chevron.left.Transparency = 1
		chevron.right.Transparency = 1
	end
end

local function hideFx()
	hideChevrons()
	billboard.Enabled = false
end

---------------------------------------------------------------- путь по полу

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function floorFilter(): { Instance }
	local list: { Instance } = { fxFolder }
	if localPlayer.Character then
		table.insert(list, localPlayer.Character)
	end
	for _, name in { MapSchema.Thieves, MapSchema.Tourists } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

-- Точка на полу под p (ищем вниз от чуть выше p). Пола нет — p чуть ниже (на уровне ног).
local function snapToFloor(p: Vector3): Vector3
	rayParams.FilterDescendantsInstances = floorFilter()
	local hit = Workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position else p - Vector3.new(0, 3, 0)
end

local path = PathfindingService:CreatePath({
	AgentRadius = ChevronSettings.AgentRadius,
	AgentHeight = 5,
	AgentCanJump = false,
	WaypointSpacing = 4,
	SupportPartialPath = true, -- цель внутри препятствия (касса, прилавок) — путь до ближайшего места
})

local points: { Vector3 } = {} -- путь по полу
local lengths: { number } = {} -- расстояние вдоль пути до каждой точки
local repathAt = 0
local computing = false
local pathGeneration = 0 -- путь к старой цели, посчитанный поздно, не нужен

local function setPoints(list: { Vector3 })
	points = list
	lengths = { 0 }
	for index = 2, #list do
		lengths[index] = lengths[index - 1] + (list[index] - list[index - 1]).Magnitude
	end
end

-- Прямая линия от from к goal, точки на полу через каждые 4 стада (запасной путь, если PathfindingService не смог).
local function straightLine(from: Vector3, goal: Vector3): { Vector3 }
	local list = {}
	local distance = (goal - from).Magnitude
	local steps = math.max(1, math.ceil(distance / 4))
	for index = 0, steps do
		table.insert(list, snapToFloor(from:Lerp(goal, index / steps)))
	end
	return list
end

local function repath(from: Vector3, goal: Vector3)
	computing = true
	local generation = pathGeneration
	task.spawn(function()
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		local list: { Vector3 } = {}
		if ok and (path.Status == Enum.PathStatus.Success or path.Status == Enum.PathStatus.ClosestNoPath) then
			for _, waypoint in path:GetWaypoints() do
				table.insert(list, waypoint.Position)
			end
			if path.Status == Enum.PathStatus.ClosestNoPath then
				table.insert(list, snapToFloor(goal))
			end
		end
		if #list < 2 then
			list = straightLine(from, goal)
		end
		if generation == pathGeneration then
			setPoints(list)
		end
		computing = false
	end)
end

-- Где на пути ближе всего к pos (по горизонтали): расстояние вдоль пути.
local function projectOnPath(pos: Vector3): number
	local best, bestAlong = math.huge, 0
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		if lengthSq > 1e-6 then
			local t = math.clamp((pos - a):Dot(ab) / lengthSq, 0, 1)
			local q = a + ab * t
			local distance = Vector3.new(pos.X - q.X, 0, pos.Z - q.Z).Magnitude
			if distance < best then
				best = distance
				bestAlong = lengths[index] + math.sqrt(lengthSq) * t
			end
		end
	end
	return bestAlong
end

-- Точка и направление (по горизонтали) на расстоянии along вдоль пути.
local function pointOnPath(along: number): (Vector3, Vector3)
	for index = 1, #points - 1 do
		if along <= lengths[index + 1] or index == #points - 1 then
			local a, b = points[index], points[index + 1]
			local segment = lengths[index + 1] - lengths[index]
			local t = if segment > 1e-6 then math.clamp((along - lengths[index]) / segment, 0, 1) else 0
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local direction = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
			return a:Lerp(b, t), direction
		end
	end
	return points[1], Vector3.new(0, 0, -1)
end

local ARM_ANGLE = math.rad(45)

-- Один шеврон «>» остриём вперёд: две палочки от острия назад-влево и назад-вправо.
local function placeChevron(chevron: Chevron, at: Vector3, forward: Vector3, transparency: number)
	local right = forward:Cross(Vector3.yAxis)
	local length = ChevronSettings.ArmLength
	local tip = at + forward * (length * math.cos(ARM_ANGLE) / 2) + Vector3.new(0, ChevronSettings.Height, 0)
	for side, part in { [-1] = chevron.left, [1] = chevron.right } do
		local arm = -forward * math.cos(ARM_ANGLE) + right * (side * math.sin(ARM_ANGLE))
		local center = tip + arm * (length / 2)
		part.CFrame = CFrame.lookAt(center, center + arm)
		part.Transparency = transparency
	end
end

local function drawChevrons(rootPosition: Vector3, now: number)
	if #points < 2 then
		hideChevrons()
		return
	end
	local total = lengths[#points]
	local start = projectOnPath(rootPosition) + 1.5 -- чуть впереди ног
	local spacing = ChevronSettings.Spacing
	local offset = (now * ChevronSettings.Speed) % spacing -- плывут вперёд
	local base = ChevronSettings.Transparency
	for index, chevron in chevrons do
		local along = start + offset + (index - 1) * spacing
		if along > total - 1 then
			chevron.left.Transparency = 1
			chevron.right.Transparency = 1
		else
			-- Первый появляется, последние тают — поток без рывков
			local fadeIn = math.clamp((along - start) / spacing, 0, 1)
			local fadeOut = math.clamp((start + #chevrons * spacing - along) / spacing, 0, 1)
			local fadeEnd = math.clamp((total - along) / spacing, 0, 1)
			local visible = math.min(fadeIn, fadeOut, fadeEnd)
			local at, forward = pointOnPath(along)
			placeChevron(chevron, at, forward, 1 - (1 - base) * visible)
		end
	end
end

---------------------------------------------------------------- цели

local function mapRoot(): Instance?
	return Workspace:FindFirstChild(MapSchema.Root)
end

local function markerPosition(name: string): Vector3?
	local map = mapRoot()
	local markers = map and map:FindFirstChild(MapSchema.Markers)
	local part = markers and markers:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part.Position else nil
end

local function monaLisa(): Target?
	local spot = markerPosition(MapSchema.PaintingSpot)
	if not spot then
		return nil
	end
	local stand = markerPosition(MapSchema.PatrolSpawn) or spot -- перед картиной: туда и ведут шевроны
	return { goal = stand, top = spot + Vector3.new(0, ArrowSettings.Height, 0), near = spot }
end

local function shopCounter(): Target?
	local map = mapRoot()
	local props = map and map:FindFirstChild(MapSchema.Props)
	local counter = props and props:FindFirstChild(MapSchema.ShopCounter)
	if not (counter and counter:IsA("Model")) then
		return nil
	end
	local pivot = counter:GetPivot()
	return {
		goal = pivot.Position + pivot.LookVector * 4, -- перед кассой, со стороны покупателя
		top = pivot.Position + Vector3.new(0, 3 + ArrowSettings.Height, 0),
		near = pivot.Position,
	}
end

-- Ближайшая заколоченная стена ещё не купленного крыла (WingService), со стороны центра.
local function wingWall(rootPosition: Vector3): Target?
	local map = mapRoot()
	local walls = map and map:FindFirstChild(MapSchema.WingDoors)
	if not walls then
		return nil
	end
	local center = markerPosition(MapSchema.PaintingSpot) or Vector3.zero
	local best: Target? = nil
	local bestDistance = math.huge
	for _, model in walls:GetChildren() do
		local id = model:GetAttribute("Wing")
		local boards = model:FindFirstChild(MapSchema.HallDoorPanel)
		if GameState.isWing(id) and not GameState.isHallOpen(id) and boards and boards:IsA("BasePart") then
			-- Стена тонкая: подходим вдоль самой тонкой оси, с той стороны, что ближе к центру музея
			local size = boards.Size
			local axis = if size.X <= size.Y and size.X <= size.Z
				then boards.CFrame.RightVector
				elseif size.Z <= size.Y then boards.CFrame.LookVector
				else boards.CFrame.UpVector
			local a = boards.Position + axis * 4
			local b = boards.Position - axis * 4
			local front = if (a - center).Magnitude < (b - center).Magnitude then a else b
			local distance = (front - rootPosition).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = {
					goal = snapToFloor(front),
					top = boards.Position + Vector3.new(0, ArrowSettings.Height, 0),
					near = front,
				}
			end
		end
	end
	return best
end

-- Шокер: оружейная (служебный коридор открывается с южным крылом), иначе касса SHOP — вкладка Weapons.
local function taserSeller(): Target?
	if GameState.isHallOpen(GameState.Wings.South) then
		local map = mapRoot()
		local props = map and map:FindFirstChild(MapSchema.Props)
		local armory = props and props:FindFirstChild("Armory")
		local point = armory and armory:FindFirstChild("Buy_Taser")
		if point and point:IsA("BasePart") then
			return {
				goal = point.Position,
				top = point.Position + Vector3.new(0, ArrowSettings.Height - 2, 0),
				near = point.Position,
			}
		end
	end
	return shopCounter()
end

-- Первый вор 1-й ночи: стрелка только к нему одному (решение 70 «без подсказок» — для остальных воров и ночей).
local firstThief: Model? = nil
local firstThiefChosen = false

local function trackFirstThief()
	if firstThiefChosen then
		return
	end
	local folder = Workspace:FindFirstChild(MapSchema.Thieves)
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute(GameState.ThiefAttr.Robber) ~= true then
			firstThief = model
			firstThiefChosen = true
			return
		end
	end
end

local function thiefTarget(): Target?
	local thief = firstThief
	if not (thief and thief.Parent) then
		return nil
	end
	if thief:GetAttribute(GameState.NpcAttr.AnimState) == GameState.ThiefAnim.Arrest then
		return nil -- его уже арестовали
	end
	local root = thief:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	return { goal = root.Position, top = root.Position + Vector3.new(0, ArrowSettings.ThiefHeight, 0), near = root.Position }
end

local function resolveTarget(kind: string?, rootPosition: Vector3): Target?
	if kind == "MonaLisa" then
		return monaLisa()
	elseif kind == "ShopCounter" then
		return shopCounter()
	elseif kind == "WingWall" then
		return wingWall(rootPosition)
	elseif kind == "TaserSeller" then
		return taserSeller()
	elseif kind == "FirstThief" then
		return thiefTarget()
	end
	return nil
end

---------------------------------------------------------------- выполнено ли

-- «Уже делал в этом забеге»: окно магазина и камеры открываются ненадолго, поэтому запоминаем
local seen = { shop = false, cameras = false, sensor = false, firstArrested = false }

localPlayer:GetAttributeChangedSignal(PlayerAttr.ShopOpen):Connect(function()
	if localPlayer:GetAttribute(PlayerAttr.ShopOpen) == true then
		seen.shop = true
	end
end)
localPlayer:GetAttributeChangedSignal(PlayerAttr.ViewingCameras):Connect(function()
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		seen.cameras = true
	end
end)

local function hasSensor(): boolean
	local folder = Workspace:FindFirstChild(MapSchema.Sensors)
	if not folder then
		return false
	end
	for _, model in folder:GetChildren() do
		if model:GetAttribute(GameState.SensorAttr.Owner) == localPlayer.UserId then
			return true
		end
	end
	return false
end

local function anyWingOpen(): boolean
	for _, wing in GameState.WingOrder do
		if GameState.isHallOpen(wing) then
			return true
		end
	end
	return false
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function isDone(step: Step, target: Target?, rootPosition: Vector3?): boolean
	local done = step.Done
	if done == "Near" then
		return target ~= nil and rootPosition ~= nil and flatDistance(rootPosition, target.near) <= Settings.NearDistance
	elseif done == "ShopOpened" then
		return seen.shop
	elseif done == "Bought" then
		return (tonumber(localPlayer:GetAttribute(PlayerAttr.RunSpent)) or 0) > 0
	elseif done == "PhoneOpened" then
		return seen.cameras
	elseif done == "SensorPlaced" then
		if not seen.sensor and hasSensor() then
			seen.sensor = true
		end
		return seen.sensor
	elseif done == "ThiefSeen" then
		return (tonumber(GameState.get(Attr.ThievesSpawned)) or 0) > 0
	elseif done == "Arrested" then
		-- Первого вора (к нему вела стрелка) арестовал товарищ — шаг тоже выполнен: иначе в команде он висел бы
		-- без стрелки до конца ночи у всех, кто сам не успел арестовать (seen.firstArrested пишет tick)
		return seen.firstArrested or (tonumber(localPlayer:GetAttribute(PlayerAttr.RunArrests)) or 0) > 0
	elseif done == "WingOpen" then
		return anyWingOpen()
	elseif done == "HasTaser" then
		return localPlayer:GetAttribute(PlayerAttr.HasTaser) == true
	end
	return false -- Info: без галочки
end

---------------------------------------------------------------- шаги

local segmentIndex = 0 -- какая часть идёт (0 — никакая)
local stepIndex = 0 -- какой шаг части (больше числа шагов — часть пройдена)
local stepStartedAt = 0
local doneAt: number? = nil -- когда шаг выполнен (галочка)
local shownKey = "" -- что сейчас нарисовано на плашке (перерисовываем только при смене)

local function roleApplies(step: Step): boolean
	return step.Role == nil or step.Role == GameState.roleOf(localPlayer)
end

local function nextApplicable(segment: number, from: number): number
	local steps = Settings.Segments[segment].Steps
	local index = from + 1
	while index <= #steps and not roleApplies(steps[index]) do
		index += 1
	end
	return index
end

-- Номер шага среди всех шагов обучения этого класса: «3/9».
local function numbering(segment: number, index: number): (number, number)
	local total, current = 0, 0
	for s, part in Settings.Segments do
		for i, step in part.Steps do
			if roleApplies(step) then
				total += 1
				if s < segment or (s == segment and i <= index) then
					current = total
				end
			end
		end
	end
	return current, total
end

local function segmentFor(phase: string, night: number): number
	for index, part in Settings.Segments do
		if part.Phase == phase and part.Night == night then
			return index
		end
	end
	return 0
end

local function startStep(index: number)
	stepIndex = index
	stepStartedAt = os.clock()
	doneAt = nil
	-- Новая цель: старый путь не показываем, новый считаем сразу
	pathGeneration += 1
	setPoints({})
	repathAt = 0
end

local function showMessage(text: string, seconds: number)
	messageText = string.upper(text)
	messageUntil = os.clock() + seconds
end

local function resetRun()
	skipped = false
	seen.shop, seen.cameras, seen.sensor, seen.firstArrested = false, false, false, false
	firstThief = nil
	firstThiefChosen = false
	segmentIndex = 0
	stepIndex = 0
	doneAt = nil
	messageUntil = 0
end

local function skip()
	if skipped or segmentIndex == 0 then
		return
	end
	skipped = true
	hideFx()
	showMessage(Settings.SkippedText, Settings.CompleteSeconds)
end

skipButton.root.Activated:Connect(skip)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Config.Keys.SkipTutorial then
		return
	end
	if plate.Visible and messageUntil <= os.clock() then
		skip()
	end
end)

local function render(step: Step?)
	local now = os.clock()
	if messageUntil > now then
		local key = "message:" .. messageText
		if shownKey ~= key then
			shownKey = key
			counterLabel.Text = ""
			textLabel.Text = messageText
			setIcon("Check")
			skipButton.root.Visible = false
			fitText()
		end
		plate.Visible = true
		return
	end
	if not step then
		plate.Visible = false
		shownKey = ""
		return
	end
	local key = ("%d:%d:%s"):format(segmentIndex, stepIndex, if doneAt then "done" else "")
	if shownKey ~= key then
		shownKey = key
		local current, total = numbering(segmentIndex, stepIndex)
		counterLabel.Text = ("%d/%d"):format(current, total)
		textLabel.Text = stepText(step)
		setIcon(if doneAt then "Check" else step.Icon)
		skipButton.root.Visible = true
		fitText()
	end
	plate.Visible = true
end

---------------------------------------------------------------- главный цикл

local lastPhase = ""
local accumulator = 0

-- Шаг, который сейчас показываем (nil — обучения сейчас нет)
local function currentStep(): Step?
	if segmentIndex == 0 then
		return nil
	end
	local steps = Settings.Segments[segmentIndex].Steps
	return steps[stepIndex]
end

local function active(): boolean
	return not skipped
		and localPlayer:GetAttribute(PlayerAttr.TutorialOff) ~= true
		and localPlayer:GetAttribute(PlayerAttr.InRound) == true
end

local function rootPart(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tick()
	local phase = GameState.phase()
	local night = tonumber(GameState.get(Attr.NightNumber)) or 1
	if phase ~= lastPhase then
		-- Новый забег (лобби или снова день 1 после Play again) — обучение с начала
		if phase == Phase.Lobby or (phase == Phase.Day and night == 1) then
			resetRun()
		end
		lastPhase = phase
	end

	local segment = if active() then segmentFor(phase, night) else 0
	if segment ~= segmentIndex then
		segmentIndex = segment
		if segment ~= 0 then
			startStep(nextApplicable(segment, 0))
		end
	end
	if phase == Phase.Night and night == 1 then
		trackFirstThief()
		local thief = firstThief
		if thief and thief.Parent and thief:GetAttribute(GameState.NpcAttr.AnimState) == GameState.ThiefAnim.Arrest then
			seen.firstArrested = true -- арестовал кто угодно из охраны
		end
	end

	local step = currentStep()
	if step then
		local now = os.clock()
		local root = rootPart()
		local target = if root then resolveTarget(step.Target, root.Position) else nil
		if not doneAt then
			local elapsed = now - stepStartedAt
			if step.Done == "Info" then
				if step.Seconds and elapsed >= step.Seconds then
					startStep(nextApplicable(segmentIndex, stepIndex))
				end
			elseif elapsed >= Settings.MinStepSeconds
				and (isDone(step, target, if root then root.Position else nil) or (step.Seconds ~= nil and elapsed >= step.Seconds))
			then
				doneAt = now
				doneSound:Play()
				pop()
			end
		elseif now - (doneAt :: number) >= Settings.NextDelay then
			local nextIndex = nextApplicable(segmentIndex, stepIndex)
			local steps = Settings.Segments[segmentIndex].Steps
			if nextIndex > #steps and segmentIndex == #Settings.Segments then
				showMessage(Settings.CompleteText, Settings.CompleteSeconds)
			end
			startStep(nextIndex)
		end
	end
	render(currentStep())
end

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	tick()
end)

-- Каждый кадр: шевроны плывут, стрелка прыгает, путь пересчитывается раз в RepathSeconds
RunService.RenderStepped:Connect(function()
	local step = currentStep()
	local root = rootPart()
	local hidden = step == nil
		or root == nil
		or doneAt ~= nil
		or localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
		or localPlayer:GetAttribute(PlayerAttr.ShopOpen) == true
	local target = if not hidden and step and root then resolveTarget(step.Target, root.Position) else nil
	if not (target and root) then
		hideFx()
		return
	end

	local now = os.clock()
	billboard.Enabled = true
	local bounce = math.abs(math.sin(now * math.pi / ArrowSettings.BounceSeconds)) * ArrowSettings.Bounce
	arrowAnchor.CFrame = CFrame.new(target.top + Vector3.new(0, bounce, 0))
	local distance = flatDistance(root.Position, target.near)
	distanceLabel.Text = ("%dM"):format(math.floor(distance + 0.5))

	if flatDistance(root.Position, target.goal) < ChevronSettings.HideNear then
		hideChevrons()
		return
	end
	if not computing and now >= repathAt then
		repathAt = now + ChevronSettings.RepathSeconds
		repath(root.Position, target.goal)
	end
	drawChevrons(root.Position, now)
end)
