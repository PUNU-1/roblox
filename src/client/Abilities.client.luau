-- Умения классов на экране (блок 5). Клиент только показывает и просит — решает сервер (AbilityService).
--  • Кнопка умения справа внизу: 3D-картинка класса, название, клавиша, полоска перезарядки.
--    На компьютере — клавиша (Shift, G), на телефоне — кнопка на экране (ContextActionService).
--  • Рывок патруля: свой вид шире, полосы скорости по краям экрана, свист ветра;
--    у других патрульных в рывке — пыль из-под ног и белый шлейф.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ClassCards = require(UI:WaitForChild("ClassCards"))

local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Classes = Config.Classes
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
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
	-- компьютер: справа внизу над патронами; телефон: справа под деньгами (внизу справа — кнопки на экране)
	Position = if touchOnly then UDim2.new(1, -12, 0, 66) else UDim2.new(1, -20, 1, -96),
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
	local key = tostring(info.KeyLabel or "")
	local title = tostring(info.AbilityTitle)
	if key ~= "" and not touchOnly then
		nameLabel.Text = ('<font color="#D4A93A">[%s]</font> %s'):format(string.upper(key), title)
	else
		nameLabel.Text = title
	end
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

	if pictureModel then
		pictureAngle += dt * (if active then 4 else 0.6)
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

-- На телефоне на кнопке умения тоже видна перезарядка (шторка поверх кнопки ContextActionService)
local touchShade: Frame? = nil

local function refreshTouchButton()
	if not touchOnly then
		return
	end
	local button = ContextActionService:GetButton(ABILITY_ACTION)
	if not button then
		touchShade = nil
		return
	end
	if not touchShade or touchShade.Parent ~= button then
		touchShade = Theme.new("Frame", {
			Name = "Cooldown",
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Colors.Dark,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = button,
		}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	local shade = touchShade :: Frame
	local t = now()
	local readyAt = number(localPlayer, PlayerAttr.AbilityReadyAt)
	local fraction = 0
	if myInfo().Ability == "Sensor" and number(localPlayer, PlayerAttr.AbilityCharges) <= 0 then
		fraction = 1
	elseif readyAt > t then
		local total = if GameState.roleOf(localPlayer) == Role.Patrol then Classes.Patrol.SprintSeconds + Classes.Patrol.SprintCooldown else 1
		fraction = math.clamp((readyAt - t) / total, 0, 1)
	end
	shade.Size = UDim2.fromScale(1, fraction)
end

local boundRole: string? = nil

-- Клавиша умения работает только на смене и только у классов с клавишей (Patrol — Shift, Technician — G)
local function refreshBinding()
	local info = myInfo()
	local want: string? = if onShift() and info.Keys ~= nil then GameState.roleOf(localPlayer) else nil
	if want == boundRole then
		return
	end
	if boundRole then
		ContextActionService:UnbindAction(ABILITY_ACTION)
		touchShade = nil
	end
	boundRole = want
	if want then
		ContextActionService:BindActionAtPriority(ABILITY_ACTION, onAbilityAction, touchOnly, Enum.ContextActionPriority.High.Value, table.unpack(info.Keys))
		if touchOnly then
			ContextActionService:SetTitle(ABILITY_ACTION, if info.Ability == "Dash" then "Dash" else "Sensor")
			ContextActionService:SetPosition(ABILITY_ACTION, UDim2.new(1, -170, 1, -170))
		end
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

---------------------------------------------------------------- каждый кадр

local slowTick = 0
RunService.RenderStepped:Connect(function(dt)
	refreshWidget(dt)
	updateDashScreen(dt)
	slowTick += dt
	if slowTick >= 0.1 then
		slowTick = 0
		refreshBinding()
		refreshTouchButton()
		updateOthersDash()
	end
end)
