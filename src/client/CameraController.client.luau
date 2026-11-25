-- Камеры наблюдения: вид с камер через телефон оператора (Tab) или пульт на балконе над Моной Лизой.
-- Работают только купленные камеры (атрибут Owned у точки, блок 2). Переключение цифрами 1–9,
-- стрелками ← → по кругу, кнопками и кликом по камере на схеме; помеха, ночью ч/б, надписи как у
-- настоящих камер, схема музея со своими игроками и местами для новых камер, метка на вора — нажать на него.
-- Открыть камеры разрешает только сервер (атрибут ViewingCameras), клиент только просит.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local requestCameras = Remotes.get(Remotes.Names.RequestCameras)
local markThief = Remotes.get(Remotes.Names.MarkThief)

local PHONE_ACTION = "OpenPhone"
local SWITCH_ACTION = "SwitchCamera"
local CAMERA_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}
local PREVIOUS_KEYS = { Enum.KeyCode.Left, Enum.KeyCode.Up }
local NEXT_KEYS = { Enum.KeyCode.Right, Enum.KeyCode.Down }
local CamAttr = GameState.CameraAttr
local PANEL_HEIGHT = 0.32 -- нижняя панель телефона (доля экрана)

-- Tab открывает телефон, поэтому стандартный список игроков Roblox отключаем.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local map = Workspace:WaitForChild(MapSchema.Root)
local cameraPointsFolder = map:WaitForChild(MapSchema.CameraPoints)

local viewing = false
local currentIndex = 1

-- Щелчок переключения камер: звук только у этого игрока
local switchSound: Sound? = nil
if Config.Sounds.CameraSwitch ~= "" then
	local sound = Instance.new("Sound")
	sound.Name = "CameraSwitch"
	sound.SoundId = Config.Sounds.CameraSwitch
	sound.Volume = Config.Sounds.CameraSwitchVolume
	sound.Parent = SoundService
	switchSound = sound
end
local colorEffect: ColorCorrectionEffect? = nil
local renderConnection: RBXScriptConnection? = nil

---------------------------------------------------------------- интерфейс

local gui = Theme.screenGui("Cameras", 2)
gui.Enabled = false

-- Рамка телефона по краям экрана
Theme.new("Frame", {
	Name = "Bezel",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
}, { Theme.corner(36), Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 14 }) })

-- Полосы помех поверх картинки
local scanlines = Theme.new("Frame", { Name = "Scanlines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
for i = 0, 39 do
	Theme.new("Frame", {
		Position = UDim2.fromScale(0, i / 40),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = scanlines,
	})
end
local grain = Theme.new("Frame", {
	Name = "Grain",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.White,
	BackgroundTransparency = 0.97,
	BorderSizePixel = 0,
	Parent = gui,
})

-- Надписи камеры — внизу картинки, над панелью телефона: верх экрана занят верхней строкой,
-- деньгами (справа) и лентой фраз (слева), и на узком экране надписи на них наезжали.
local camLabel = Theme.label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 30, 1 - PANEL_HEIGHT, -44),
	Size = UDim2.new(0.45, 0, 0, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 30,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = camLabel })

local recFrame = Theme.new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -30, 1 - PANEL_HEIGHT, -44), -- над часами, справа внизу картинки
	Size = UDim2.new(0, 90, 0, 34),
	BackgroundTransparency = 1,
	Parent = gui,
})
local recDot = Theme.new("Frame", {
	Size = UDim2.new(0, 22, 0, 22),
	Position = UDim2.new(0, 0, 0.5, -11),
	BackgroundColor3 = Colors.Red,
	Parent = recFrame,
}, { Theme.corner(11) })
Theme.label({ Position = UDim2.new(0, 30, 0, 0), Size = UDim2.new(1, -30, 1, 0), Text = "REC", TextXAlignment = Enum.TextXAlignment.Left, Parent = recFrame })

local clockLabel = Theme.label({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -30, 1 - PANEL_HEIGHT, -10),
	Size = UDim2.new(0, 200, 0, 34),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = clockLabel })

local hintLabel = Theme.label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 30, 1 - PANEL_HEIGHT, -10),
	Size = UDim2.new(0.45, 0, 0, 26),
	Font = Theme.BodyFont,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 18,
	Text = if UserInputService.KeyboardEnabled
		then "Tap a thief to mark him  •  1–9 or ← → switch cameras"
		else "Tap a thief to mark him for everyone",
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = hintLabel })

-- Помеха при переключении камер
local staticFrame = Theme.new("Frame", {
	Name = "Static",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(70, 70, 70),
	Visible = false,
	ZIndex = 3,
	Parent = gui,
})
local staticBars = {}
for i = 1, 12 do
	staticBars[i] = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = staticFrame,
	})
end

-- Нижняя панель телефона: кнопки камер, схема, закрыть
local panel = Theme.new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(1, 0, PANEL_HEIGHT, 0),
	BackgroundColor3 = Colors.Navy,
	ZIndex = 2,
	Parent = gui,
}, { Theme.corner(24), Theme.stroke(Colors.Dark, 4), Theme.padding(14) })

local buttonsFrame = Theme.new("Frame", {
	Size = UDim2.fromScale(0.28, 1),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = panel,
})
Theme.new("UIGridLayout", {
	CellSize = UDim2.new(0.22, 0, 0.29, 0), -- 4 × 3 кнопки (12 камер)
	CellPadding = UDim2.new(0.035, 0, 0.055, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = buttonsFrame,
})
local cameraButtons: { TextButton } = {}

local mapFrame = Theme.new("Frame", {
	Name = "Map",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.4, 1),
	BackgroundColor3 = Colors.Dark,
	ZIndex = 2,
	Parent = panel,
}, { Theme.corner(10), Theme.stroke(Colors.Turquoise, 2) })
local mapCanvas = Theme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.9),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = mapFrame,
})

local closeButton = Theme.button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromScale(0.26, 0.5),
	BackgroundColor3 = Colors.Red,
	Text = "CLOSE (Tab)",
	ZIndex = 2,
	Modal = true, -- пока открыт экран камер, курсор свободен: можно нажимать на воров и кнопки
	Parent = panel,
})

---------------------------------------------------------------- схема музея

-- Границы схемы — все полы залов (атрибут Hall), чтобы схема совпадала с тем, что построено.
local hallFloors: { BasePart } = {}
local hallCenter, hallSize = Vector3.zero, Vector3.new(100, 1, 70)
do
	local geometry = map:WaitForChild(MapSchema.Geometry, 30)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	if geometry then
		for _, part in geometry:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Hall") ~= nil then
				table.insert(hallFloors, part)
				minX = math.min(minX, part.Position.X - part.Size.X / 2)
				maxX = math.max(maxX, part.Position.X + part.Size.X / 2)
				minZ = math.min(minZ, part.Position.Z - part.Size.Z / 2)
				maxZ = math.max(maxZ, part.Position.Z + part.Size.Z / 2)
			end
		end
	end
	if #hallFloors > 0 then
		hallCenter = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
		hallSize = Vector3.new(maxX - minX, 1, maxZ - minZ)
	end
	-- Схема в пропорциях музея
	Theme.new("UIAspectRatioConstraint", { AspectRatio = hallSize.X / hallSize.Z, Parent = mapCanvas })
end

local function toMap(position: Vector3): UDim2
	local x = (position.X - hallCenter.X) / hallSize.X + 0.5
	local y = (position.Z - hallCenter.Z) / hallSize.Z + 0.5
	return UDim2.fromScale(math.clamp(x, 0, 1), math.clamp(y, 0, 1))
end

-- Прямоугольник на схеме по центру и размеру (размер — уже повёрнутый, вид сверху).
local function drawBox(center: Vector3, sizeX: number, sizeZ: number, color: Color3): Frame
	local topLeft = toMap(center - Vector3.new(sizeX / 2, 0, sizeZ / 2))
	return Theme.new("Frame", {
		Position = topLeft,
		Size = UDim2.fromScale(sizeX / hallSize.X, sizeZ / hallSize.Z),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = mapCanvas,
	})
end

local function drawRect(part: BasePart, color: Color3): Frame
	return drawBox(part.Position, part.Size.X, part.Size.Z, color)
end

-- Размер детали или модели на полу (с учётом поворота на 90°).
local function footprint(instance: Instance): (Vector3?, number, number)
	local cframe, size
	if instance:IsA("BasePart") then
		cframe, size = instance.CFrame, instance.Size
	elseif instance:IsA("Model") then
		cframe, size = instance:GetBoundingBox()
	else
		return nil, 0, 0
	end
	local right = cframe.RightVector
	if math.abs(right.X) >= math.abs(right.Z) then
		return cframe.Position, size.X, size.Z
	end
	return cframe.Position, size.Z, size.X
end

-- Полы залов: открытый зал светлее, закрытый — тёмный
local floorFrames: { [BasePart]: Frame } = {}
local function refreshFloors()
	for floor, frame in floorFrames do
		local open = GameState.isHallOpen(floor:GetAttribute("Hall"))
		frame.BackgroundColor3 = if open then Colors.NavyLight else Colors.Dark
		frame.BackgroundTransparency = if open then 0.2 else 0.5
	end
end

do
	for _, floor in hallFloors do
		local frame = drawRect(floor, Colors.NavyLight)
		frame.ZIndex = 1
		Theme.new("UIStroke", { Color = Colors.Marble, Thickness = 1, Parent = frame })
		floorFrames[floor] = frame
	end
	refreshFloors()
	-- Укрытия и стены внутри залов (атрибут MapObstacle у детали или модели): колонны, витрины, пульт
	for _, folderName in { MapSchema.Geometry, MapSchema.Props } do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, item in folder:GetDescendants() do
				if item:GetAttribute("MapObstacle") == true then
					local center, sizeX, sizeZ = footprint(item)
					if center then
						drawBox(center, sizeX, sizeZ, Colors.Marble)
					end
				end
			end
		end
	end
	local console = map:FindFirstChild(MapSchema.ControlConsole, true)
	if console and console:IsA("BasePart") then
		drawRect(console, Colors.Gold)
	end
end

local cameraDots: { TextButton } = {}

-- Сломанная камера: вместо картинки помехи и «NO SIGNAL» (камеру перезапускают на пульте).
-- Блэкаут (Светорез, блок 3): все камеры — «NO POWER», свет возвращают у щитка POWER.
local noSignal = Theme.new("Frame", {
	Name = "NoSignal",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 1,
	Parent = gui,
})
local noSignalTitle = Theme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.new(0.6, 0, 0, 60),
	Text = "NO SIGNAL",
	TextColor3 = Colors.Red,
	MaxTextSize = 56,
	ZIndex = 1,
	Parent = noSignal,
})
local NO_SIGNAL_HINT = if UserInputService.KeyboardEnabled
	then "Restart the cameras: red switch next to the console on the balcony (hold F)"
	else "Restart the cameras: red switch next to the console on the balcony"
local NO_POWER_HINT = if UserInputService.KeyboardEnabled
	then "The power is out: POWER box in the staff corridor (hold F)"
	else "The power is out: POWER box in the staff corridor"
local noSignalHint = Theme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.new(0.6, 0, 0, 26),
	Font = Theme.BodyFont,
	Text = NO_SIGNAL_HINT,
	MaxTextSize = 20,
	ZIndex = 1,
	Parent = noSignal,
})
local playerDots: { [Player]: Frame } = {}

local function cameraPoint(index: number): BasePart?
	local point = cameraPointsFolder:FindFirstChild("Camera" .. index)
	if point and point:IsA("BasePart") then
		return point
	end
	return nil
end

-- Камеры по номерам: Camera1, Camera2, … пока есть точки
local cameraCount = 0
while cameraPoint(cameraCount + 1) do
	cameraCount += 1
end

local switchTo: (number) -> ()

for index = 1, cameraCount do
	local point = cameraPoint(index) :: BasePart
	-- Точка камеры на схеме: по ней можно нажать, чтобы переключиться
	local dot = Theme.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(point.Position),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Colors.Red,
		Text = tostring(index),
		TextColor3 = Colors.White,
		TextScaled = true,
		Font = Theme.Font,
		AutoButtonColor = true,
		ZIndex = 3,
		Parent = mapCanvas,
	}, { Theme.corner(8) })
	local dotStroke = Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = dot })
	dotStroke.Name = "Ring"
	dot.Activated:Connect(function()
		switchTo(index)
	end)
	cameraDots[index] = dot

	local button = Theme.button({ Text = tostring(index), LayoutOrder = index, ZIndex = 2, MaxTextSize = 28, Parent = buttonsFrame })
	cameraButtons[index] = button
end

local function updatePlayerDots()
	for player, dot in playerDots do
		if not player.Parent then
			dot:Destroy()
			playerDots[player] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local show = player:GetAttribute(PlayerAttr.InRound) == true and root ~= nil
		local dot = playerDots[player]
		if show and root and root:IsA("BasePart") then
			if not dot then
				dot = Theme.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.new(0, 12, 0, 12),
					BackgroundColor3 = if player == localPlayer then Colors.Gold else Colors.Turquoise,
					ZIndex = 4,
					Parent = mapCanvas,
				}, { Theme.corner(6) })
				Theme.label({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0, -2),
					Size = UDim2.new(0, 90, 0, 16),
					Font = Theme.BodyFont,
					Text = player.DisplayName,
					MaxTextSize = 14,
					ZIndex = 4,
					Parent = dot,
				})
				playerDots[player] = dot
			end
			dot.Position = toMap(root.Position)
			dot.Visible = true
		elseif dot then
			dot.Visible = false
		end
	end
end

---------------------------------------------------------------- переключение камер

local function isNight(): boolean
	return GameState.phase() == Phase.Night
end

-- Ночью камеры — ночное видение: ч/б и светлее, чем видит глаз (в залах темно).
-- Яркость меняется только у этого игрока и только пока он смотрит камеры.
local function applyColorMode()
	if colorEffect then
		colorEffect.Saturation = if isNight() then Config.Cameras.NightSaturation else 0
		colorEffect.Contrast = if isNight() then Config.Cameras.NightContrast else 0
	end
	Lighting.ExposureCompensation = if viewing and isNight() then Config.Cameras.NightExposure else 0
end

local staticConnection: RBXScriptConnection? = nil

local function playStatic()
	if staticConnection then
		staticConnection:Disconnect()
		staticConnection = nil
	end
	staticFrame.Visible = true
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started >= Config.Cameras.StaticSeconds then
			staticFrame.Visible = false
			connection:Disconnect()
			if staticConnection == connection then
				staticConnection = nil
			end
			return
		end
		staticFrame.BackgroundColor3 = Color3.fromRGB(math.random(40, 110), math.random(40, 110), math.random(40, 110))
		for _, bar in staticBars do
			bar.Position = UDim2.fromScale(0, math.random())
		end
	end)
	staticConnection = connection
end

local function showCamera(index: number)
	local point = cameraPoint(index)
	if not point then
		return
	end
	currentIndex = index
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = point.CFrame
	camera.FieldOfView = Config.Cameras.FieldOfView
	local name = Config.Cameras.Names[index] or ""
	camLabel.Text = ("CAM %d — %s"):format(index, name)
	for i, button in cameraButtons do
		button.TextColor3 = if i == index then Colors.Navy else Colors.White
	end
	playStatic()
	if switchSound then
		switchSound:Play()
	end
end

local function cameraBroken(index: number): boolean
	local point = cameraPoint(index)
	return point ~= nil and point:GetAttribute(CamAttr.Broken) == true
end

local function cameraOwned(index: number): boolean
	local point = cameraPoint(index)
	return point ~= nil and point:GetAttribute(CamAttr.Owned) == true
end

local function hallOpen(index: number): boolean
	local point = cameraPoint(index)
	return point ~= nil and GameState.isHallOpen(point:GetAttribute(CamAttr.Hall))
end

-- Камеру можно смотреть, если она куплена и её зал открыт.
local function cameraAvailable(index: number): boolean
	return cameraOwned(index) and hallOpen(index)
end

local function refreshCameraButtons()
	for index, button in cameraButtons do
		local available = cameraAvailable(index)
		button.AutoButtonColor = available
		button.Text = if not hallOpen(index) then "🔒" elseif not cameraOwned(index) then "$" elseif cameraBroken(index) then "✖" else tostring(index)
		button.BackgroundColor3 = if index == currentIndex then Colors.Gold elseif available then Colors.NavyLight else Colors.Dark
		button.TextTransparency = if available or index == currentIndex then 0 else 0.4
	end
	refreshFloors()
	local blackout = GameState.get(Attr.Blackout) == true
	noSignal.Visible = blackout or cameraBroken(currentIndex)
	noSignalTitle.Text = if blackout then "NO POWER" else "NO SIGNAL"
	noSignalHint.Text = if blackout then NO_POWER_HINT else NO_SIGNAL_HINT
	for index, dot in cameraDots do
		local owned = cameraOwned(index)
		local ring = dot:FindFirstChild("Ring")
		-- Купленная камера — закрашенный кружок, место для новой — пустое колечко
		dot.BackgroundTransparency = if owned then 0 else 1
		dot.TextTransparency = if owned then 0 else 0.5
		dot.AutoButtonColor = cameraAvailable(index)
		dot.Size = if index == currentIndex then UDim2.new(0, 20, 0, 20) else UDim2.new(0, 16, 0, 16)
		dot.BackgroundColor3 = if index == currentIndex then Colors.Gold elseif cameraBroken(index) then Colors.Gray else Colors.Red
		if ring and ring:IsA("UIStroke") then
			ring.Color = if owned then Colors.Dark else Colors.Gray
			ring.Thickness = if owned then 1 else 2
		end
	end
end

switchTo = function(index: number)
	if viewing and index ~= currentIndex and index >= 1 and index <= cameraCount and cameraAvailable(index) then
		showCamera(index)
		refreshCameraButtons()
	end
end

-- Следующая (step = 1) или предыдущая (step = −1) камера, которую можно смотреть, по кругу.
local function cycle(step: number)
	for offset = 1, cameraCount - 1 do
		local index = (currentIndex - 1 + step * offset) % cameraCount + 1
		if cameraAvailable(index) then
			switchTo(index)
			return
		end
	end
end

for index, button in cameraButtons do
	button.Activated:Connect(function()
		switchTo(index)
	end)
end

closeButton.Activated:Connect(function()
	requestCameras:FireServer(false)
end)

---------------------------------------------------------------- метка на вора

-- Не надо попадать точно в вора: берём вора, который на экране ближе всего к нажатию
-- (в пределах MarkTapRadius пикселей) и которого не закрывает стена.
-- Позиция нажатия (input.Position) считается без верхней полосы Roblox,
-- поэтому сравниваем с WorldToScreenPoint — он считает так же.
local function isVisibleFromCamera(camera: Camera, position: Vector3, params: RaycastParams): boolean
	local origin = camera.CFrame.Position
	return Workspace:Raycast(origin, position - origin, params) == nil
end

local function thiefAt(screenPosition: Vector2): Model?
	local thieves = Workspace:FindFirstChild(MapSchema.Thieves)
	if not thieves then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- картина у вора в руках и лучи сетки не закрывают обзор
	local ignore: { Instance } = { thieves }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	local best: Model? = nil
	local bestDistance = Config.Comms.MarkTapRadius
	for _, thief in thieves:GetChildren() do
		local root = thief:FindFirstChild("HumanoidRootPart")
		if thief:IsA("Model") and root and root:IsA("BasePart") then
			local head = thief:FindFirstChild("Head")
			local headPosition = if head and head:IsA("BasePart") then head.Position else root.Position
			local screen, onScreen = camera:WorldToScreenPoint(root.Position)
			local distance = (Vector2.new(screen.X, screen.Y) - screenPosition).Magnitude
			if onScreen and distance < bestDistance then
				if isVisibleFromCamera(camera, root.Position, params) or isVisibleFromCamera(camera, headPosition, params) then
					best = thief
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- Экран камер рисуется поверх верхней полосы Roblox (IgnoreGuiInset), а позиция нажатия
-- считается без неё, поэтому добавляем высоту полосы.
local function toGuiPosition(screenPosition: Vector2): UDim2
	local inset = GuiService:GetGuiInset()
	return UDim2.fromOffset(screenPosition.X + inset.X, screenPosition.Y + inset.Y)
end

-- Ответ на нажатие: попал по вору — красный круг и «MARKED!», промахнулся — серый круг.
local function showTap(screenPosition: Vector2, marked: boolean)
	local tap = Config.Effects.Tap
	local ring = Theme.new("Frame", {
		Name = "TapRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toGuiPosition(screenPosition),
		Size = UDim2.fromOffset(tap.StartSize, tap.StartSize),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = gui,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local ringStroke = Theme.new("UIStroke", { Color = if marked then Colors.Red else Colors.Gray, Thickness = 3, Parent = ring })
	local ringInfo = TweenInfo.new(tap.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, ringInfo, { Size = UDim2.fromOffset(tap.EndSize, tap.EndSize) }):Play()
	local ringFade = TweenService:Create(ringStroke, ringInfo, { Transparency = 1 })
	ringFade.Completed:Once(function()
		ring:Destroy()
	end)
	ringFade:Play()

	if not marked then
		return
	end
	local text = Theme.label({
		Name = "MarkedText",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = toGuiPosition(screenPosition - Vector2.new(0, tap.EndSize / 2)),
		Size = UDim2.fromOffset(160, 32),
		Text = "MARKED!",
		TextColor3 = Colors.Red,
		ZIndex = 20,
		MaxTextSize = 28,
		Parent = gui,
	})
	local textStroke = Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = text })
	local textInfo = TweenInfo.new(tap.TextSeconds)
	TweenService:Create(textStroke, textInfo, { Transparency = 1 }):Play()
	local textFade = TweenService:Create(text, textInfo, {
		TextTransparency = 1,
		Position = text.Position - UDim2.fromOffset(0, 20),
	})
	textFade.Completed:Once(function()
		text:Destroy()
	end)
	textFade:Play()
end

local lastMarkTime = 0

local function tryMark(screenPosition: Vector2)
	if noSignal.Visible then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera and screenPosition.Y >= camera.ViewportSize.Y * (1 - PANEL_HEIGHT) then
		return
	end
	local thief = thiefAt(screenPosition)
	local time = os.clock()
	-- Сервер всё равно проверит сам; тут только чтобы не обещать метку, которой не будет
	local marked = thief ~= nil and isNight() and time - lastMarkTime >= Config.Comms.MarkCooldown
	if thief and marked then
		lastMarkTime = time
		markThief:FireServer(thief)
	end
	showTap(screenPosition, marked)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not viewing or gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tryMark(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

---------------------------------------------------------------- открыть / закрыть

local function onSwitchAction(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	for index, key in CAMERA_KEYS do
		if input.KeyCode == key then
			switchTo(index)
			return Enum.ContextActionResult.Sink
		end
	end
	if table.find(PREVIOUS_KEYS, input.KeyCode) then
		cycle(-1)
		return Enum.ContextActionResult.Sink
	elseif table.find(NEXT_KEYS, input.KeyCode) then
		cycle(1)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function openView()
	viewing = true
	gui.Enabled = true
	colorEffect = Theme.new("ColorCorrectionEffect", { Name = "CameraColor", Parent = Workspace.CurrentCamera })
	applyColorMode()
	hintLabel.Visible = true
	panel.Position = UDim2.new(0.5, 0, 1.4, 0)
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 1, 0),
	}):Play()
	if not cameraAvailable(currentIndex) then
		currentIndex = 1 -- камера закрытого зала или ещё не купленная не работает
		for index = 1, cameraCount do
			if cameraAvailable(index) then
				currentIndex = index
				break
			end
		end
	end
	showCamera(currentIndex)
	refreshCameraButtons()
	local keys = table.clone(CAMERA_KEYS)
	for _, key in PREVIOUS_KEYS do
		table.insert(keys, key)
	end
	for _, key in NEXT_KEYS do
		table.insert(keys, key)
	end
	ContextActionService:BindAction(SWITCH_ACTION, onSwitchAction, false, table.unpack(keys))

	local blink = 0
	local refreshTimer = 0
	renderConnection = RunService.Heartbeat:Connect(function(dt)
		blink += dt
		recDot.Visible = blink % 1 < 0.5
		grain.BackgroundTransparency = 0.95 + math.random() * 0.04
		if isNight() then
			clockLabel.Text = Theme.nightClock(GameState.nightProgress())
		else
			clockLabel.Text = "DAY " .. Theme.formatTime(GameState.secondsLeft())
		end
		updatePlayerDots()
		refreshTimer += dt
		if refreshTimer > 0.5 then
			refreshTimer = 0
			refreshCameraButtons() -- зал могли открыть или камеру купить, пока смотрим
		end
	end)
end

local function closeView()
	viewing = false
	gui.Enabled = false
	staticFrame.Visible = false
	if staticConnection then
		staticConnection:Disconnect()
		staticConnection = nil
	end
	ContextActionService:UnbindAction(SWITCH_ACTION)
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if colorEffect then
		colorEffect:Destroy()
		colorEffect = nil
	end
	applyColorMode() -- вернуть обычную яркость
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = Config.Players.FieldOfView
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function onViewingChanged()
	local shouldView = localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
	if shouldView and not viewing then
		openView()
	elseif not shouldView and viewing then
		closeView()
	end
end

---------------------------------------------------------------- кнопка телефона (Tab / кнопка на экране)

local function canUsePhone(): boolean
	local phase = GameState.phase()
	local inRound = localPlayer:GetAttribute(PlayerAttr.InRound) == true
	local operator = localPlayer:GetAttribute(PlayerAttr.Role) == Role.Operator -- телефон только у оператора (решение 59)
	return inRound and operator and (phase == Phase.Day or phase == Phase.Night)
end

local phoneBound = false

local function onPhoneAction(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		requestCameras:FireServer(not viewing)
	end
	return Enum.ContextActionResult.Sink
end

local function refreshPhoneBinding()
	-- Пульт закрывается той же кнопкой, поэтому она нужна и тому, кто смотрит с пульта
	local shouldBind = canUsePhone() or viewing
	if shouldBind and not phoneBound then
		ContextActionService:BindAction(PHONE_ACTION, onPhoneAction, true, Enum.KeyCode.Tab)
		ContextActionService:SetTitle(PHONE_ACTION, "Phone")
		ContextActionService:SetPosition(PHONE_ACTION, UDim2.new(1, -170, 1, -170))
		phoneBound = true
	elseif not shouldBind and phoneBound then
		ContextActionService:UnbindAction(PHONE_ACTION)
		phoneBound = false
	end
end

local function onStateChanged()
	onViewingChanged()
	applyColorMode()
	refreshPhoneBinding()
end

for _, name in { PlayerAttr.ViewingCameras, PlayerAttr.Role, PlayerAttr.InRound } do
	localPlayer:GetAttributeChangedSignal(name):Connect(onStateChanged)
end
for _, name in { Attr.Phase, Attr.Solo } do
	GameState.folder():GetAttributeChangedSignal(name):Connect(onStateChanged)
end
localPlayer.CharacterAdded:Connect(function()
	if viewing then
		closeView()
	end
	task.defer(onStateChanged)
end)
onStateChanged()
