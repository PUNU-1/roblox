-- Умения классов на экране (блок 5). Клиент только показывает и просит — решает сервер (AbilityService).
--  • Кнопка умения справа внизу: 3D-картинка класса, название, клавиша, полоска перезарядки.
--    На компьютере — клавиша (Shift, G), на телефоне — кнопка на экране (ContextActionService).
--  • Рывок патруля: свой вид шире, полосы скорости по краям экрана, свист ветра;
--    у других патрульных в рывке — пыль из-под ног и белый шлейф.
--  • Датчики техников: раскладываются на полу, лампочка мигает зелёным; вор рядом — у всей охраны на смене
--    писк, стрелка к датчику вокруг прицела и метка MOTION! над датчиком сквозь стены, по полу бежит волна.
--  • Техник перезапускает камеры у рубильника CAMERA RESET без удержания.
--  • Собаки кинологов ходят, сидят и лают (DogAnimator); у хозяина кнопка умения краснеет: «THIEF NEAR!».

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ClassCards = require(UI:WaitForChild("ClassCards"))
local TouchButtons = require(UI:WaitForChild("TouchButtons"))
local DogAnimator = require(script.Parent:WaitForChild("DogAnimator"))

local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Classes = Config.Classes
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()
local useRemote = Remotes.get(Remotes.Names.UseAbility)

local ABILITY_ACTION = "ClassAbility"

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function number(player: Player, attr: string): number
	return tonumber(player:GetAttribute(attr)) or 0
end

local function onShift(): boolean
	local phase = GameState.phase()
	return localPlayer:GetAttribute(PlayerAttr.InRound) == true and (phase == GameState.Phase.Day or phase == GameState.Phase.Night)
end

local function viewing(): boolean
	return localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
end

local function blocked(): boolean
	return viewing() or localPlayer:GetAttribute(PlayerAttr.Downed) == true or number(localPlayer, PlayerAttr.KnockedUntil) > now()
end

local function myInfo(): { [string]: any }
	return GameState.classInfo(GameState.roleOf(localPlayer)) or (Classes :: any)[Classes.Default]
end

local function playSound(id: string, volume: number, speed: number, parent: Instance)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Parent = parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

---------------------------------------------------------------- кнопка умения

local gui = Theme.screenGui("Abilities", 2)

local SIZE = if touchOnly then 70 else 88
local widget = Theme.new("Frame", {
	Name = "Ability",
	AnchorPoint = if touchOnly then Vector2.new(1, 0) else Vector2.new(1, 1),
	-- компьютер: справа внизу над патронами; телефон: справа под деньгами и кнопкой SHOP (внизу справа — кнопки на экране)
	Position = if touchOnly then UDim2.new(1, -12, 0, 136) else UDim2.new(1, -20, 1, -96),
	Size = UDim2.fromOffset(SIZE + 40, SIZE + 30),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local square = Theme.new("Frame", {
	Name = "Square",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(SIZE, SIZE),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.15,
	ClipsDescendants = true,
	Parent = widget,
}, { Theme.corner(16) })
local squareScale = Theme.new("UIScale", { Parent = square })
local squareStroke = Theme.stroke(Colors.Turquoise, 2.5)
squareStroke.Parent = square
local glow = Theme.new("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.8),
	BackgroundColor3 = Colors.Turquoise,
	BackgroundTransparency = 0.75,
	Parent = square,
}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local viewport = Theme.new("ViewportFrame", {
	Name = "Picture",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(150, 150, 165),
	LightColor = Color3.fromRGB(255, 246, 230),
	LightDirection = Vector3.new(-0.6, -1, -0.8),
	ZIndex = 2,
	Parent = square,
})
local viewportCamera = Instance.new("Camera")
viewportCamera.Parent = viewport
viewport.CurrentCamera = viewportCamera

-- Перезарядка: тёмная шторка сверху вниз и секунды
local cooldownShade = Theme.new("Frame", {
	Name = "Cooldown",
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = square,
})
local cooldownLabel = Theme.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 34, ZIndex = 4, Visible = false, Parent = square })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = cooldownLabel })
-- Умение действует (рывок): полоска внизу тает
local activeBar = Theme.new("Frame", {
	Name = "Active",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = Colors.Turquoise,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 4,
	Parent = square,
})
-- Сколько ещё раз этой ночью (датчики техника)
local chargesBadge = Theme.new("Frame", {
	Name = "Charges",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -4, 0, 4),
	Size = UDim2.fromOffset(22, 22),
	BackgroundColor3 = Colors.Gold,
	Visible = false,
	ZIndex = 5,
	Parent = square,
}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local chargesLabel = Theme.label({ Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Navy, MaxTextSize = 16, ZIndex = 5, Parent = chargesBadge })
local usedLabel = Theme.label({ Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.3), Text = "USED", MaxTextSize = 22, ZIndex = 4, Visible = false, Parent = square })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = usedLabel })

local nameLabel = Theme.label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, SIZE + 3),
	Size = UDim2.new(1, 0, 0, 22),
	RichText = true,
	MaxTextSize = 16,
	Parent = widget,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = nameLabel })

-- Короткая подсказка над кнопкой («Stand up to dash»)
local toast = Theme.label({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 0, -6),
	Size = UDim2.fromOffset(260, 22),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Right,
	MaxTextSize = 16,
	Visible = false,
	Parent = widget,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = toast })
local toastToken = 0

local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(1.6, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

local function bump(scale: number)
	squareScale.Scale = scale
	TweenService:Create(squareScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local shownRole = ""
local pictureModel: Model? = nil
local pictureBase = CFrame.identity
local pictureAngle = 0

local function setWidgetRole(role: string)
	if role == shownRole then
		return
	end
	shownRole = role
	local info = myInfo()
	local color: Color3 = info.Color
	squareStroke.Color = color
	glow.BackgroundColor3 = color
	activeBar.BackgroundColor3 = color
	if pictureModel then
		pictureModel:Destroy()
	end
	local model = ClassCards.picture(role)
	model.Parent = viewport
	ClassCards.frameCamera(viewportCamera, model)
	pictureModel = model
	pictureBase = model.WorldPivot
end

-- Подпись под кнопкой: «[SHIFT] DASH»; у кинолога, когда собака чует вора, — «THIEF NEAR!»
local function abilityCaption(info: { [string]: any }, dogAlert: boolean): string
	if dogAlert then
		return '<font color="#FF5A5A">THIEF NEAR!</font>'
	end
	local key = tostring(info.KeyLabel or "")
	local title = tostring(info.AbilityTitle)
	if key ~= "" and not touchOnly then
		return ('<font color="#D4A93A">[%s]</font> %s'):format(string.upper(key), title)
	end
	return title
end

local readyFlashFor = 0 -- когда перезарядка кончилась — кнопка вспыхивает

local function refreshWidget(dt: number)
	local show = onShift() and not viewing()
	widget.Visible = show
	if not show then
		return
	end
	local role = GameState.roleOf(localPlayer)
	setWidgetRole(role)
	local info = myInfo()
	local t = now()
	local readyAt = number(localPlayer, PlayerAttr.AbilityReadyAt)
	local activeUntil = number(localPlayer, PlayerAttr.AbilityUntil)
	local active = activeUntil > t and role == Role.Patrol
	local cooling = readyAt > t and not active

	activeBar.Visible = active
	if active then
		activeBar.Size = UDim2.new(math.clamp((activeUntil - t) / Classes.Patrol.SprintSeconds, 0, 1), 0, 0, 6)
	end
	local total = if role == Role.Patrol then Classes.Patrol.SprintCooldown else 1
	cooldownShade.Size = UDim2.fromScale(1, if cooling then math.clamp((readyAt - t) / total, 0, 1) else (if active then 1 else 0))
	cooldownShade.BackgroundTransparency = if active then 0.75 else 0.3
	cooldownLabel.Visible = cooling and readyAt - t > 0.95
	cooldownLabel.Text = tostring(math.ceil(readyAt - t))

	if cooling then
		readyFlashFor = 1
	elseif readyFlashFor > 0 then
		readyFlashFor = 0
		bump(1.15)
	end

	local usesCharges = info.Ability == "Sensor"
	local charges = number(localPlayer, PlayerAttr.AbilityCharges)
	chargesBadge.Visible = usesCharges and charges > 0
	chargesLabel.Text = tostring(charges)
	usedLabel.Visible = usesCharges and charges <= 0
	if usesCharges and charges <= 0 then
		cooldownShade.Size = UDim2.fromScale(1, 1)
	end

	-- Кинолог: собака чует вора — кнопка мигает красным
	local dogAlert = role == Role.DogHandler and DogAnimator.ownAlert(localPlayer.UserId)
	nameLabel.Text = abilityCaption(info, dogAlert)
	if dogAlert then
		local pulse = 0.5 + 0.5 * math.sin(t * 10)
		squareStroke.Color = Classes.Sensor.AlarmColor
		squareStroke.Thickness = 2.5 + 1.5 * pulse
		glow.BackgroundColor3 = Classes.Sensor.AlarmColor
	else
		squareStroke.Color = info.Color
		squareStroke.Thickness = 2.5
		glow.BackgroundColor3 = info.Color
	end

	if pictureModel then
		pictureAngle += dt * (if active or dogAlert then 4 else 0.6)
		pictureModel:PivotTo(pictureBase * CFrame.Angles(0, pictureAngle, 0))
	end
end

---------------------------------------------------------------- нажатие

local lastRequest = 0

local function tryUse()
	local info = myInfo()
	local ability = info.Ability
	if not onShift() or blocked() then
		return
	end
	local t = now()
	if t - lastRequest < 0.25 then
		return
	end
	if number(localPlayer, PlayerAttr.AbilityReadyAt) > t + Classes.AbilitySlack then
		bump(0.9)
		return
	end
	if ability == "Dash" and localPlayer:GetAttribute(PlayerAttr.Crouch) == true then
		showToast(if touchOnly then "Stand up to dash" else "Stand up to dash (C)")
		bump(0.9)
		return
	end
	if ability == "Sensor" and number(localPlayer, PlayerAttr.AbilityCharges) <= 0 then
		showToast("No sensors left tonight")
		bump(0.9)
		return
	end
	lastRequest = t
	useRemote:FireServer(ability)
end

local function onAbilityAction(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		tryUse()
	end
	return Enum.ContextActionResult.Sink
end

-- На телефоне — пиксельная кнопка умения справа внизу (этап 5, блок D; раньше — кнопка ContextActionService).
-- На ней видна перезарядка: вместо названия — секунды, у датчика без зарядов — USED.
local touchButton: TouchButtons.TouchButton? = nil
if touchOnly then
	touchButton = TouchButtons.new({
		place = "Ability",
		icon = "Dash",
		label = "DASH",
		onActivated = tryUse,
	})
end

local boundRole: string? = nil

local function refreshTouchButton()
	local button = touchButton
	if not button then
		return
	end
	-- Открыт экран камер (пульт) — на этом месте кнопка CLOSE телефона (CameraController)
	button.setVisible(boundRole ~= nil and localPlayer:GetAttribute(PlayerAttr.ViewingCameras) ~= true)
	local info = myInfo()
	local title = if info.Ability == "Dash" then "DASH" else "SENSOR"
	local t = now()
	local readyAt = number(localPlayer, PlayerAttr.AbilityReadyAt)
	if info.Ability == "Sensor" and number(localPlayer, PlayerAttr.AbilityCharges) <= 0 then
		title = "USED"
	elseif readyAt > t then
		title = ("%dS"):format(math.ceil(readyAt - t))
	end
	button.setLabel(title)
end

-- Клавиша умения работает только на смене и только у классов с клавишей (Patrol — Shift, Technician — G)
local function refreshBinding()
	local info = myInfo()
	local want: string? = if onShift() and info.Keys ~= nil then GameState.roleOf(localPlayer) else nil
	if want == boundRole then
		return
	end
	if boundRole then
		ContextActionService:UnbindAction(ABILITY_ACTION)
	end
	boundRole = want
	if want then
		ContextActionService:BindActionAtPriority(ABILITY_ACTION, onAbilityAction, false, Enum.ContextActionPriority.High.Value, table.unpack(info.Keys))
	end
	local button = touchButton
	if button then
		button.setIcon(if info.Ability == "Dash" then "Dash" else "Sensor")
	end
end

---------------------------------------------------------------- рывок: свой экран

local speedLines = Theme.new("Frame", {
	Name = "SpeedLines",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 0,
	Parent = gui,
})

type Streak = { frame: Frame, angle: number, radius: number, speed: number, length: number }
local streaks: { Streak } = {}
for index = 1, 22 do
	local frame = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Colors.White,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Parent = speedLines,
	})
	table.insert(streaks, { frame = frame, angle = index / 22 * math.pi * 2, radius = math.random(), speed = 0, length = 0 })
end

local function respawnStreak(streak: Streak)
	streak.angle = math.random() * math.pi * 2
	streak.radius = 0.55 + math.random() * 0.15
	streak.speed = 0.9 + math.random() * 0.8
	streak.length = 50 + math.random() * 90
	streak.frame.Size = UDim2.fromOffset(streak.length, if math.random() < 0.3 then 3 else 2)
end

for _, streak in streaks do
	respawnStreak(streak)
	streak.radius = 0.55 + math.random() * 0.45
end

local fovKick = 0 -- насколько сейчас шире свой вид
local dashFxStarted = false

local function updateDashScreen(dt: number)
	local t = now()
	local dashing = GameState.roleOf(localPlayer) == Role.Patrol and number(localPlayer, PlayerAttr.AbilityUntil) > t and onShift()
	if dashing and not dashFxStarted then
		dashFxStarted = true
		playSound(Config.Sounds.Dash, Config.Sounds.DashVolume, Config.Sounds.DashSpeed, gui)
	elseif not dashing then
		dashFxStarted = false
	end

	-- Свой вид шире, пока рывок (камеры и пульт задают свой угол сами — тогда не трогаем)
	local camera = Workspace.CurrentCamera
	local target = if dashing and not viewing() then Classes.Patrol.FovKick else 0
	local before = fovKick
	fovKick += (target - fovKick) * math.min(1, dt * (if target > fovKick then 10 else 4))
	if camera and not viewing() and (fovKick > 0.01 or before > 0.01) then
		camera.FieldOfView = Config.Players.FieldOfView + (if fovKick > 0.01 then fovKick else 0)
	end

	-- Полосы скорости летят от центра к краям
	local strength = fovKick / Classes.Patrol.FovKick
	speedLines.Visible = strength > 0.02
	if not speedLines.Visible then
		return
	end
	local size = speedLines.AbsoluteSize
	local half = math.max(size.X, size.Y) * 0.5
	for _, streak in streaks do
		streak.radius += dt * streak.speed
		if streak.radius > 1.15 then
			respawnStreak(streak)
		end
		local r = streak.radius * half
		streak.frame.Position = UDim2.new(0.5, math.cos(streak.angle) * r, 0.5, math.sin(streak.angle) * r)
		streak.frame.Rotation = math.deg(streak.angle)
		local fade = math.clamp((streak.radius - 0.55) / 0.2, 0, 1) * math.clamp((1.15 - streak.radius) / 0.2, 0, 1)
		streak.frame.BackgroundTransparency = 1 - 0.55 * fade * strength
	end
end

---------------------------------------------------------------- рывок: другие патрульные

type DashFx = { attachments: { Attachment }, dust: ParticleEmitter, trail: Trail, root: BasePart }
local dashFx: { [Player]: DashFx } = {}

local function removeDashFx(player: Player)
	local fx = dashFx[player]
	if fx then
		for _, attachment in fx.attachments do
			attachment:Destroy()
		end
		dashFx[player] = nil
	end
end

local function addDashFx(player: Player, root: BasePart)
	local feet = Instance.new("Attachment")
	feet.Name = "DashFeet"
	feet.Position = Vector3.new(0, -root.Size.Y / 2 - 2, 0.4)
	feet.Parent = root
	local top = Instance.new("Attachment")
	top.Name = "DashTrailTop"
	top.Position = Vector3.new(0, 1, 0.35)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "DashTrailBottom"
	bottom.Position = Vector3.new(0, -1.2, 0.35)
	bottom.Parent = root

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "DashDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromHex("D8CCB4"))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(1.5, 3.5)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Rate = 26
	dust.LightInfluence = 0.6
	dust.Parent = feet

	local trail = Instance.new("Trail")
	trail.Name = "DashTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(Colors.White, Classes.Patrol.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.22
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = top

	dashFx[player] = { attachments = { feet, top, bottom }, dust = dust, trail = trail, root = root }
end

local function updateOthersDash()
	local t = now()
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local dashing = root ~= nil and root:IsA("BasePart") and GameState.roleOf(player) == Role.Patrol and number(player, PlayerAttr.AbilityUntil) > t
			local fx = dashFx[player]
			if fx and (not dashing or fx.root ~= root or not fx.root.Parent) then
				removeDashFx(player)
				fx = nil
			end
			if dashing and not fx and root and root:IsA("BasePart") then
				addDashFx(player, root)
			end
			local current = dashFx[player]
			if current then
				local moving = current.root.AssemblyLinearVelocity.Magnitude > 8
				current.dust.Enabled = moving
				current.trail.Enabled = moving
			end
		end
	end
end

Players.PlayerRemoving:Connect(removeDashFx)

---------------------------------------------------------------- датчики движения техников

local SensorSettings = Classes.Sensor
local SensorAttr = GameState.SensorAttr

local arrowLayer = Theme.new("Frame", {
	Name = "SensorArrows",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 6,
	Parent = gui,
})

type SensorView = {
	model: Model,
	root: BasePart,
	lamp: BasePart?,
	light: PointLight?,
	dashes: { BasePart },
	pivot: CFrame,
	placedAt: number,
	pingAt: number,
	arrow: Frame,
	arrowScale: UIScale,
	arrowText: TextLabel,
	marker: BillboardGui,
	markerText: TextLabel,
	connection: RBXScriptConnection,
}
local sensorViews: { [Model]: SensorView } = {}

local function beep()
	for index = 0, SensorSettings.Beeps - 1 do
		task.delay(index * SensorSettings.BeepGap, function()
			playSound(Config.Sounds.SensorBeep, Config.Sounds.SensorBeepVolume, Config.Sounds.SensorBeepSpeed, gui)
		end)
	end
end

-- Волна по полу от датчика: светящийся диск расходится до края круга и тает (видят все рядом).
local function wave(view: SensorView)
	local radius = tonumber(view.model:GetAttribute(SensorAttr.Radius)) or Classes.Technician.SensorRadius
	local disc = Instance.new("Part")
	disc.Name = "SensorWave"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Color = SensorSettings.AlarmColor
	disc.Transparency = 0.5
	disc.Size = Vector3.new(0.05, 1, 1)
	disc.CFrame = view.pivot * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Parent = view.model
	local tween = TweenService:Create(disc, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		disc:Destroy()
	end)
	tween:Play()
end

local function onPing(view: SensorView)
	view.pingAt = tonumber(view.model:GetAttribute(SensorAttr.PingAt)) or 0
	if now() - view.pingAt > 2 then
		return -- старое значение (зашли в игру позже)
	end
	wave(view)
	if onShift() then
		beep()
		view.arrowScale.Scale = 1.5
		TweenService:Create(view.arrowScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function removeSensorView(model: Model)
	local view = sensorViews[model]
	if view then
		view.connection:Disconnect()
		view.arrow:Destroy()
		view.marker:Destroy()
		if view.light then
			view.light:Destroy()
		end
		sensorViews[model] = nil
	end
end

local function addSensorView(model: Model)
	if sensorViews[model] then
		return
	end
	local root = model:WaitForChild("Root", 5)
	if not (root and root:IsA("BasePart")) or not model.Parent then
		return
	end
	-- Ждём, пока придут все детали (круг на полу — последним)
	model:WaitForChild("Range", 5)
	local lamp = model:FindFirstChild("Lamp", true)
	local lampPart = if lamp and lamp:IsA("BasePart") then lamp else nil
	local light: PointLight? = nil
	if lampPart then
		local created = Instance.new("PointLight")
		created.Range = 5
		created.Brightness = 1.5
		created.Color = SensorSettings.LampColor
		created.Shadows = false
		created.Parent = lampPart
		light = created
	end
	local dashes = {}
	local range = model:FindFirstChild("Range")
	if range then
		for _, child in range:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(dashes, child)
			end
		end
	end

	-- Стрелка к датчику по краю круга вокруг прицела и расстояние
	local arrow = Theme.new("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(80, 64),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = arrowLayer,
	})
	local arrowScale = Theme.new("UIScale", { Parent = arrow })
	local glyph = Theme.label({
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(40, 40),
		Text = "▲",
		TextColor3 = SensorSettings.AlarmColor,
		MaxTextSize = 40,
		Parent = arrow,
	})
	Theme.new("UIStroke", { Color = Colors.White, Thickness = 2, Parent = glyph })
	local arrowText = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(1, 40, 0, 20),
		Font = Theme.BodyFont,
		TextColor3 = Colors.White,
		MaxTextSize = 15,
		Parent = arrow,
	})
	Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = arrowText })

	-- Метка MOTION! над датчиком, видна сквозь стены
	local marker = Instance.new("BillboardGui")
	marker.Name = "MotionMarker"
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.fromOffset(130, 52)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	marker.MaxDistance = SensorSettings.MarkerMaxDistance
	marker.Enabled = false
	marker.Adornee = root
	local pill = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = SensorSettings.AlarmColor,
		Parent = marker,
	}, { Theme.corner(15), Theme.stroke(Colors.White, 2) })
	Theme.label({ Size = UDim2.fromScale(1, 1), Text = "MOTION!", MaxTextSize = 22, Parent = pill })
	local markerText = Theme.label({
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.BodyFont,
		MaxTextSize = 14,
		Parent = marker,
	})
	Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = markerText })
	marker.Parent = root

	local view: SensorView
	view = {
		model = model,
		root = root,
		lamp = lampPart,
		light = light,
		dashes = dashes,
		pivot = root.CFrame,
		placedAt = tonumber(model:GetAttribute(SensorAttr.PlacedAt)) or 0,
		pingAt = tonumber(model:GetAttribute(SensorAttr.PingAt)) or 0,
		arrow = arrow,
		arrowScale = arrowScale,
		arrowText = arrowText,
		marker = marker,
		markerText = markerText,
		connection = model:GetAttributeChangedSignal(SensorAttr.PingAt):Connect(function()
			onPing(view)
		end),
	}
	sensorViews[model] = view
end

local function easeOutBack(x: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function updateSensors()
	local t = now()
	local camera = Workspace.CurrentCamera
	local shift = onShift() and not viewing()
	local halfSize = arrowLayer.AbsoluteSize / 2
	local radius = math.min(SensorSettings.ArrowRadius, math.min(halfSize.X, halfSize.Y) - 50)
	for model, view in sensorViews do
		if not model.Parent then
			removeSensorView(model)
			continue
		end
		-- Датчик раскладывается: поднимается из пола с поворотом
		local deploy = (t - view.placedAt) / SensorSettings.DeploySeconds
		if deploy < 1.2 then
			local e = easeOutBack(math.clamp(deploy, 0, 1))
			model:PivotTo(view.pivot * CFrame.new(0, -1.4 * (1 - e), 0) * CFrame.Angles(0, (1 - e) * math.pi, 0))
		end
		local alarm = t - view.pingAt < Classes.Technician.PingSeconds
		-- Лампочка: тихо — зелёная вспышка раз в BlinkSeconds, вор рядом — часто мигает красным
		local on: boolean
		local color: Color3
		if alarm then
			on = (t * 6) % 1 < 0.5
			color = SensorSettings.AlarmColor
		else
			on = t % SensorSettings.BlinkSeconds < 0.15
			color = SensorSettings.LampColor
		end
		if view.lamp then
			view.lamp.Color = if on then color else color:Lerp(Color3.new(0, 0, 0), 0.7)
		end
		if view.light then
			view.light.Color = color
			view.light.Enabled = on
		end
		local pulse = if alarm then 0.35 + 0.25 * math.sin(t * 12) else SensorSettings.RingTransparency
		for _, dash in view.dashes do
			dash.Color = if alarm then SensorSettings.AlarmColor else SensorSettings.RingColor
			dash.Transparency = pulse
		end

		-- Стрелка и метка — у охраны на смене, пока горит тревога
		local showAlert = alarm and shift and camera ~= nil
		view.marker.Enabled = alarm and onShift()
		view.arrow.Visible = false
		if showAlert and camera then
			local position = view.root.Position
			local distance = (position - camera.CFrame.Position).Magnitude
			view.markerText.Text = ("%d studs"):format(math.floor(distance))
			local relative = camera.CFrame:PointToObjectSpace(position)
			local angle = math.atan2(relative.X, -relative.Z)
			view.arrow.Visible = true
			view.arrow.Position = UDim2.new(0.5, math.sin(angle) * radius, 0.5, -math.cos(angle) * radius)
			view.arrow.Rotation = math.deg(angle)
			view.arrowText.Rotation = -math.deg(angle) -- надпись не переворачивается
			view.arrowText.Text = ("MOTION  %d"):format(math.floor(distance))
			local left = Classes.Technician.PingSeconds - (t - view.pingAt)
			local glyph = view.arrow:FindFirstChild("Glyph")
			if glyph and glyph:IsA("TextLabel") then
				glyph.TextTransparency = if left < 0.6 then 1 - left / 0.6 else 0
			end
		end
	end
end

task.spawn(function()
	local folder = Workspace:WaitForChild(MapSchema.Sensors)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			addSensorView(child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			removeSensorView(child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(addSensorView, child)
		end
	end
end)

---------------------------------------------------------------- техник: камеры перезапускаются мгновенно

-- Рубильник CAMERA RESET у пульта: у техника кнопка срабатывает сразу, у остальных — удержание
-- (сервер не проверяет время удержания этой кнопки, поэтому меняем его только у себя).
local repairPrompt: ProximityPrompt? = nil

local function refreshRepairPrompt()
	if not repairPrompt then
		local map = Workspace:FindFirstChild(MapSchema.Root)
		local switch = map and map:FindFirstChild("CameraResetSwitch", true)
		local prompt = switch and switch:FindFirstChild("RepairPrompt")
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			return
		end
		repairPrompt = prompt
	end
	local prompt = repairPrompt :: ProximityPrompt
	local instant = GameState.roleOf(localPlayer) == Role.Technician and Classes.Technician.InstantCameraReset
	local hold = if instant then 0 else Config.Cameras.RepairHoldSeconds
	if prompt.HoldDuration ~= hold then
		prompt.HoldDuration = hold
	end
end

---------------------------------------------------------------- каждый кадр

DogAnimator.start() -- собаки кинологов в мире

local slowTick = 0
RunService.RenderStepped:Connect(function(dt)
	refreshWidget(dt)
	updateDashScreen(dt)
	updateSensors()
	slowTick += dt
	if slowTick >= 0.1 then
		slowTick = 0
		refreshBinding()
		refreshTouchButton()
		updateOthersDash()
		refreshRepairPrompt()
	end
end)
