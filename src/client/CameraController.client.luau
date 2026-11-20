-- Камеры наблюдения: вид с камер через телефон оператора (Tab) или пульт в диспетчерской.
-- Переключение 1-4 и кнопками, помеха, ночью ч/б, надписи как у настоящих камер,
-- схема музея со своими игроками, метка на вора — нажать на него.
-- Открыть камеры разрешает только сервер (атрибут ViewingCameras), клиент только просит.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local CAMERA_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

-- Tab открывает телефон, поэтому стандартный список игроков Roblox отключаем.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local map = Workspace:WaitForChild(MapSchema.Root)
local cameraPointsFolder = map:WaitForChild(MapSchema.CameraPoints)

local viewing = false
local currentIndex = 1
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

local camLabel = Theme.label({
	Position = UDim2.new(0, 30, 0, 24),
	Size = UDim2.new(0.5, 0, 0, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 30,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = camLabel })

local recFrame = Theme.new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -190, 0, 24), -- левее счётчика денег (он справа сверху, 150 пикселей)
	Size = UDim2.new(0, 110, 0, 34),
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
	Position = UDim2.new(1, -30, 0.72, -10),
	Size = UDim2.new(0, 200, 0, 34),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = clockLabel })

local hintLabel = Theme.label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 30, 0.72, -10),
	Size = UDim2.new(0.45, 0, 0, 26),
	Font = Theme.BodyFont,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 18,
	Text = "Tap a thief to mark him for everyone",
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
	Size = UDim2.new(1, 0, 0.28, 0),
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
	CellSize = UDim2.new(0.48, 0, 0.46, 0),
	CellPadding = UDim2.new(0.04, 0, 0.08, 0),
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
}, { Theme.new("UIAspectRatioConstraint", { AspectRatio = 100 / 70 }) })

local closeButton = Theme.button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromScale(0.26, 0.5),
	BackgroundColor3 = Colors.Red,
	Text = "CLOSE (Tab)",
	ZIndex = 2,
	Parent = panel,
})

---------------------------------------------------------------- схема музея

-- Границы зала берём с карты, чтобы схема совпадала с тем, что построено.
local hallCenter, hallSize = Vector3.zero, Vector3.new(100, 1, 70)
do
	local floor = map:FindFirstChild("HallFloor", true)
	if floor and floor:IsA("BasePart") then
		hallCenter, hallSize = floor.Position, floor.Size
	end
end

local function toMap(position: Vector3): UDim2
	local x = (position.X - hallCenter.X) / hallSize.X + 0.5
	local y = (position.Z - hallCenter.Z) / hallSize.Z + 0.5
	return UDim2.fromScale(math.clamp(x, 0, 1), math.clamp(y, 0, 1))
end

local function drawRect(part: BasePart, color: Color3)
	local half = part.Size / 2
	local corner = part.Position - Vector3.new(half.X, 0, half.Z)
	local topLeft = toMap(corner)
	Theme.new("Frame", {
		Position = topLeft,
		Size = UDim2.fromScale(part.Size.X / hallSize.X, part.Size.Z / hallSize.Z),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = mapCanvas,
	})
end

do
	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = mapCanvas,
	}, { Theme.new("UIStroke", { Color = Colors.Marble, Thickness = 2 }) })
	local geometry = map:FindFirstChild(MapSchema.Geometry)
	if geometry then
		for _, part in geometry:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "DisplayWall" or part.Name == "Partition" or part.Name == "Column") then
				drawRect(part, Colors.Marble)
			end
		end
	end
end

local cameraDots: { Frame } = {}
local playerDots: { [Player]: Frame } = {}

local function cameraPoint(index: number): BasePart?
	local point = cameraPointsFolder:FindFirstChild("Camera" .. index)
	if point and point:IsA("BasePart") then
		return point
	end
	return nil
end

local cameraCount = 0
for index = 1, Config.Cameras.Count do
	local point = cameraPoint(index)
	if not point then
		break
	end
	cameraCount = index
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(point.Position),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Colors.Red,
		ZIndex = 3,
		Parent = mapCanvas,
	}, { Theme.corner(6) })
	cameraDots[index] = dot

	local button = Theme.button({ Text = tostring(index), LayoutOrder = index, ZIndex = 2, MaxTextSize = 32, Parent = buttonsFrame })
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

local function applyColorMode()
	if colorEffect then
		colorEffect.Saturation = if isNight() then Config.Cameras.NightSaturation else 0
		colorEffect.Contrast = if isNight() then Config.Cameras.NightContrast else 0
	end
end

local function playStatic()
	staticFrame.Visible = true
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started >= Config.Cameras.StaticSeconds then
			staticFrame.Visible = false
			connection:Disconnect()
			return
		end
		staticFrame.BackgroundColor3 = Color3.fromRGB(math.random(40, 110), math.random(40, 110), math.random(40, 110))
		for _, bar in staticBars do
			bar.Position = UDim2.fromScale(0, math.random())
		end
	end)
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
	for i, dot in cameraDots do
		dot.BackgroundColor3 = if i == index then Colors.Gold else Colors.Red
		dot.Size = if i == index then UDim2.new(0, 16, 0, 16) else UDim2.new(0, 12, 0, 12)
	end
	for i, button in cameraButtons do
		button.BackgroundColor3 = if i == index then Colors.Gold else Colors.NavyLight
		button.TextColor3 = if i == index then Colors.Navy else Colors.White
	end
	playStatic()
end

local function switchTo(index: number)
	if viewing and index ~= currentIndex and index >= 1 and index <= cameraCount then
		showCamera(index)
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
	showCamera(currentIndex)
	ContextActionService:BindAction(SWITCH_ACTION, onSwitchAction, false, table.unpack(CAMERA_KEYS))

	local blink = 0
	renderConnection = RunService.Heartbeat:Connect(function(dt)
		blink += dt
		recDot.Visible = blink % 1 < 0.5
		grain.BackgroundTransparency = 0.95 + math.random() * 0.04
		if isNight() then
			local started = GameState.get(Attr.NightStartedAt)
			local elapsed = if typeof(started) == "number" then Workspace:GetServerTimeNow() - started else 0
			clockLabel.Text = Theme.nightClock(elapsed)
		else
			clockLabel.Text = "PREP " .. Theme.formatTime(GameState.secondsLeft())
		end
		updatePlayerDots()
	end)
end

local function closeView()
	viewing = false
	gui.Enabled = false
	ContextActionService:UnbindAction(SWITCH_ACTION)
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if colorEffect then
		colorEffect:Destroy()
		colorEffect = nil
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
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
	local operator = localPlayer:GetAttribute(PlayerAttr.Role) == Role.Operator or GameState.get(Attr.Solo) == true
	return inRound and operator and (phase == Phase.Prep or phase == Phase.Night)
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
