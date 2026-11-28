-- Оружие от первого лица (блок 4). Сам игрок видит у камеры свои руки (рукава формы, перчатки) и оружие:
-- достаёт, покачивается при ходьбе и повороте, стреляет с отдачей (камера уходит вверх), передёргивает затвор
-- и помпу, перезаряжает (магазин выпадает и вставляется новый, дробовик — по патрону), шокер с проводами,
-- аптечка; лёжа без сил — руки ползут, поднимая друга — руки помогают ему встать.
-- Клавиши: 1–4 — места (то же ещё раз — убрать), мышь — стрелять, R — перезарядка. На телефоне — кнопки.
-- Клиент только шлёт намерения: что в руках, сколько патронов и кого задело, решает сервер (WeaponService).

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
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local TouchButtons = require(script.Parent:WaitForChild("UI"):WaitForChild("TouchButtons"))
local PixelButton = require(script.Parent:WaitForChild("UI"):WaitForChild("PixelButton"))
local Mobile = require(script.Parent:WaitForChild("UI"):WaitForChild("Mobile"))
local MobileMenu = require(script.Parent:WaitForChild("UI"):WaitForChild("MobileMenu"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local ActionProps = require(script.Parent:WaitForChild("ActionProps"))

local PlayerAttr = GameState.PlayerAttr
local Weapons = Config.Weapons
local Actions = Config.Actions
local Keys = Config.Keys
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

local equipRemote = Remotes.get(Remotes.Names.Equip)
local fireRemote = Remotes.get(Remotes.Names.Fire)
local reloadRemote = Remotes.get(Remotes.Names.Reload)
local medkitRemote = Remotes.get(Remotes.Names.UseMedkit)
local stanceRemote = Remotes.get(Remotes.Names.SetStance)

local FIREARMS = { Pistol = true, Rifle = true, Shotgun = true }
local SLOT_TITLES = { "PRIMARY", "PISTOL", "TASER", "MEDKIT" }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function number(attr: string): number
	return tonumber(localPlayer:GetAttribute(attr)) or 0
end

local function equipped(): string
	local value = localPlayer:GetAttribute(PlayerAttr.Equipped)
	return if typeof(value) == "string" then value else ""
end

local function onShift(): boolean
	local phase = GameState.phase()
	return localPlayer:GetAttribute(PlayerAttr.InRound) == true and (phase == GameState.Phase.Day or phase == GameState.Phase.Night)
end

local function raidActive(): boolean
	return GameState.get(GameState.Attr.Raid) == true
end

local function downed(): boolean
	return localPlayer:GetAttribute(PlayerAttr.Downed) == true
end

local function viewing(): boolean
	return localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
end

local function spectating(): boolean
	return localPlayer:GetAttribute(PlayerAttr.Spectating) == true
end

local function knocked(): boolean
	return number(PlayerAttr.KnockedUntil) > now()
end

local function reviving(): boolean
	return number(PlayerAttr.ReviveTarget) ~= 0
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Подъём и спад внутри отрезка [a, b] времени t (0 → 1 → 0).
local function bump(t: number, a: number, b: number): number
	if t <= a or t >= b then
		return 0
	end
	return math.sin((t - a) / (b - a) * math.pi)
end

---------------------------------------------------------------- руки и оружие у камеры

-- Где оружие у камеры (справа внизу) — у каждого своё.
local HOLD: { [string]: CFrame } = {
	Pistol = CFrame.new(0.42, -0.6, -1.55) * CFrame.Angles(0, 0.05, 0),
	Taser = CFrame.new(0.44, -0.6, -1.5) * CFrame.Angles(0, 0.05, 0),
	Rifle = CFrame.new(0.55, -0.78, -1.45) * CFrame.Angles(0, 0.06, 0),
	Shotgun = CFrame.new(0.55, -0.8, -1.4) * CFrame.Angles(0, 0.06, 0),
	Medkit = CFrame.new(0, -0.32, -1.7) * CFrame.Angles(0.25, 0, 0),
}
-- Куда от кисти уходит предплечье (к нижним углам экрана), в системе камеры
local RIGHT_ARM_DIR = Vector3.new(0.38, -0.55, 1).Unit
local LEFT_ARM_DIR = Vector3.new(-0.45, -0.5, 1).Unit

type View = {
	kind: string,
	built: WeaponModels.Built,
	groups: { string? }, -- у каждой детали: Mag / Slide / Pump / Lid или nil
	magBottom: Vector3?, -- низ магазина (в системе оружия): сюда левая рука вставляет новый
	slideAt: Vector3?, -- затвор или его рукоять: сюда левая рука тянется в конце перезарядки
}

-- Крышка аптечки (этап 8, блок O): эти детали открываются на петле у переднего края
local MEDKIT_LID = { LidBevelF = true, LidBevelB = true, LidTop = true, Label = true, Handle = true, HandleGrip = true, PostL = true, PostR = true, PostBaseL = true, PostBaseR = true }
local MEDKIT_HINGE = CFrame.new(0, -0.32, -0.24)

local container = Instance.new("Model")
container.Name = "ViewModel"
local view: View? = nil

local function viewPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = container
	return part
end

type Arm = { sleeve: Part, cuff: Part, glove: Part, thumb: Part }

local function newArm(side: string): Arm
	local uniform = Config.Uniform.Arms
	return {
		sleeve = viewPart(side .. "Sleeve", Vector3.new(0.46, 0.46, 1.8), uniform, Enum.Material.Fabric),
		cuff = viewPart(side .. "Cuff", Vector3.new(0.5, 0.5, 0.16), uniform:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric),
		glove = viewPart(side .. "Glove", Vector3.new(0.38, 0.32, 0.5), Color3.fromHex("1A1B1F"), Enum.Material.Leather),
		thumb = viewPart(side .. "Thumb", Vector3.new(0.14, 0.14, 0.26), Color3.fromHex("1A1B1F"), Enum.Material.Leather),
	}
end

local rightArm = newArm("Right")
local leftArm = newArm("Left")

local function setArmVisible(arm: Arm, visible: boolean)
	local t = if visible then 0 else 1
	for _, part in { arm.sleeve, arm.cuff, arm.glove, arm.thumb } do
		part.Transparency = t
	end
end

-- Рука: кисть в точке hand (пальцы — вдоль forward), предплечье уходит по dir (к краю экрана).
local function placeArm(arm: Arm, hand: Vector3, dir: Vector3, up: Vector3, side: number)
	local forward = -dir
	local gloveCF = CFrame.lookAt(hand, hand + forward, up)
	arm.glove.CFrame = gloveCF
	arm.thumb.CFrame = gloveCF * CFrame.new(-side * 0.17, 0.06, -0.12) * CFrame.Angles(0, -side * 0.5, 0)
	local cuffAt = hand + dir * 0.32
	arm.cuff.CFrame = CFrame.lookAt(cuffAt, cuffAt + dir, up)
	local sleeveAt = hand + dir * (0.32 + 0.9)
	arm.sleeve.CFrame = CFrame.lookAt(sleeveAt, sleeveAt + dir, up)
end

local function clearView()
	if view then
		view.built.model:Destroy()
		view = nil
	end
end

local function buildView(kind: string)
	clearView()
	if kind == "" then
		return
	end
	local built = WeaponModels.build(kind)
	local groups = {}
	local magBottom: Vector3? = nil
	local slideAt: Vector3? = nil
	for index, part in built.parts do
		part.Anchored = true
		part.CastShadow = false
		local name = part.Name
		groups[index] = if name == "Mag" or name == "Slide" or name == "Pump" then name
			elseif kind == "Medkit" and MEDKIT_LID[name] then "Lid"
			else nil
		local offset = built.offsets[index]
		if name == "Mag" then
			local bottom = (offset * CFrame.new(0, -part.Size.Y / 2, 0)).Position
			if not magBottom or bottom.Y < magBottom.Y then
				magBottom = bottom
			end
		elseif name == "Slide" and not slideAt then
			slideAt = offset.Position
		end
	end
	built.root.Anchored = true
	built.model.Parent = container
	view = { kind = kind, built = built, groups = groups, magBottom = magBottom, slideAt = slideAt }
end

---------------------------------------------------------------- вещи в руках (этап 8, блок O)

-- Отвёртка, наручники, бинт, патрон дробовика, бронежилет (ActionProps): детали у камеры, видны только в своём действии.
type Prop = { parts: { BasePart }, offsets: { CFrame } }

local props: { [string]: Prop } = {}
local usedProps: { [string]: boolean } = {}

local function showProp(name: string, cframe: CFrame)
	local prop = props[name]
	if not prop then
		prop = { parts = {}, offsets = {} }
		for index, spec in ActionProps.Specs[name] do
			local part = ActionProps.part(spec, true)
			part.Parent = container
			prop.parts[index] = part
			prop.offsets[index] = spec.offset
		end
		props[name] = prop
	end
	usedProps[name] = true
	for index, part in prop.parts do
		part.CFrame = cframe * prop.offsets[index]
		part.Transparency = 0
	end
end

-- Вещи, которые в этом кадре не показали, прячутся.
local function hideUnusedProps()
	for name, prop in props do
		if not usedProps[name] then
			for _, part in prop.parts do
				part.Transparency = 1
			end
		end
	end
	table.clear(usedProps)
end

-- Оружие убирается из кадра (руки заняты действием).
local function hideWeapon(cf: CFrame)
	local current = view
	if not current then
		return
	end
	local away = cf * CFrame.new(0, -20, 0)
	current.built.root.CFrame = away
	for _, part in current.built.parts do
		part.CFrame = away
	end
end

---------------------------------------------------------------- состояние

local shownKind = "" -- что сейчас у камеры
local equipStarted = 0
local triggerHeld = false
local nextShotAt = 0
local localAmmo: { [string]: number } = {}
local lastShotAt = 0
local lastShotKind = ""
local taserReadyLocal = 0
local recoilKick = 0 -- оружие у камеры уходит назад и вверх
local cameraKick = 0 -- сколько ещё увести камеру вверх (радианы)
local cameraKickYaw = 0
local spread = 0 -- прицел расходится от отдачи
local swayX, swayY = 0, 0
local lastLook: Vector3? = nil
local bobPhase = 0
local bobSpeed = 0
local crouchBlend = 0
local leanBlend = 0
local healBlend = 0
local healWasActive = false
local holsterStarted = 0 -- убирает оружие (0 — нет)
local actionKind = "" -- действие из атрибута Action, которое сейчас видно (этап 8, блок O)
local actionStart = 0
local holsterWarnUntil = 0

local function ammoOf(weapon: string): number
	return number(GameState.ammoAttr(weapon))
end

local function reserveOf(weapon: string): number
	return number(GameState.reserveAttr(weapon))
end

-- Патроны в магазине с учётом выстрелов, о которых сервер ещё не ответил
local function predictedAmmo(weapon: string): number
	local server = ammoOf(weapon)
	local mine = localAmmo[weapon]
	if mine == nil or now() - lastShotAt > 0.6 then
		localAmmo[weapon] = server
		return server
	end
	local value = math.min(mine, server)
	localAmmo[weapon] = value
	return value
end

local function reloading(): boolean
	return number(PlayerAttr.ReloadUntil) > now()
end

---------------------------------------------------------------- выстрел

local function rayParams(stunning: boolean): RaycastParams
	local ignore: { Instance } = { container }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local tourists = Workspace:FindFirstChild(MapSchema.Tourists)
	if tourists then
		table.insert(ignore, tourists)
	end
	local fx = Workspace:FindFirstChild("LocalFx")
	if fx then
		table.insert(ignore, fx)
	end
	if not stunning then
		-- Пули проходят сквозь обычных воров (по безоружным не стреляем): задевают только грабителей
		local thieves = Workspace:FindFirstChild(MapSchema.Thieves)
		if thieves then
			for _, model in thieves:GetChildren() do
				if model:GetAttribute(GameState.ThiefAttr.Robber) ~= true then
					table.insert(ignore, model)
				end
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

local function muzzleWorld(): CFrame
	local camera = Workspace.CurrentCamera
	local current = view
	if current then
		return current.built.root.CFrame * current.built.muzzle
	end
	return if camera then camera.CFrame else CFrame.identity
end

local function shoot(kind: string)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local info = (Weapons :: any)[kind]
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	local stunning = kind == "Taser"
	local params = rayParams(stunning)
	local muzzle = muzzleWorld()
	local pellets = info.Pellets or 1
	for _ = 1, pellets do
		local dir = direction
		if info.Spread then
			local angle = math.rad(info.Spread) * math.sqrt(math.random())
			dir = (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, math.random() * math.pi * 2) * CFrame.Angles(angle, 0, 0)).LookVector
		end
		local result = Workspace:Raycast(origin, dir * info.Range, params)
		local point = if result then result.Position else origin + dir * info.Range
		local onTarget = false
		if result then
			local thieves = Workspace:FindFirstChild(MapSchema.Thieves)
			onTarget = thieves ~= nil and result.Instance:IsDescendantOf(thieves)
		end
		if stunning then
			Fx.wire(muzzle.Position, point)
		else
			Fx.tracer(muzzle.Position, point)
			if result then
				Fx.impact(point, onTarget)
			end
		end
	end
	if stunning then
		taserReadyLocal = now() + 1
		recoilKick = math.min(1.2, recoilKick + 0.5)
	else
		Fx.muzzleFlash(muzzle, if kind == "Shotgun" then 1.4 elseif kind == "Rifle" then 1.1 else 0.9)
		localAmmo[kind] = predictedAmmo(kind) - 1
		-- Штурмовик (блок 5) держит оружие крепче: отдача ×AssaultRecoil
		local recoil = GameState.recoilFor(localPlayer)
		recoilKick = math.min(1.5, recoilKick + recoil * (if kind == "Shotgun" then 1 elseif kind == "Rifle" then 0.45 else 0.7))
		-- Отдача: прицел уходит вверх и чуть вбок (камера запоминает это сама)
		cameraKick += math.rad(info.RecoilPitch) * recoil
		cameraKickYaw += math.rad(info.RecoilYaw) * recoil * (math.random() * 2 - 1)
		spread = math.min(1, spread + 0.25 * recoil)
	end
	Fx.shotSound(kind, nil)
	lastShotAt = now()
	lastShotKind = kind
	nextShotAt = now() + (info.Interval or 0)
	fireRemote:FireServer(kind, origin, direction)
end

local function requestReload()
	local kind = equipped()
	if FIREARMS[kind] and not reloading() and predictedAmmo(kind) < (Weapons :: any)[kind].MagSize and reserveOf(kind) > 0 then
		reloadRemote:FireServer()
	end
end

local showToast: (text: string) -> ()

-- Не время стрелять (этап 8, решение 97): сухой щелчок и короткая надпись, патроны не тратятся.
local function refuseShot(text: string)
	Fx.click(Config.Sounds.EmptySpeed)
	showToast(text)
	triggerHeld = false
end

-- Можно ли сейчас выстрелить (сервер всё равно проверит сам).
-- Огнестрел — только в налёт, шокер — ночью всегда, днём не стреляет ничего.
local function tryFire()
	local kind = equipped()
	if kind == "Medkit" then
		if not onShift() or downed() or viewing() or knocked() or reviving() then
			return
		end
		medkitRemote:FireServer()
		triggerHeld = false
		return
	end
	local info = (Weapons :: any)[kind]
	if not info or kind ~= shownKind or not onShift() or downed() or viewing() or knocked() or reviving() then
		return
	end
	if now() < equipStarted + Weapons.EquipSeconds or now() < nextShotAt then
		return
	end
	if FIREARMS[kind] and not (raidActive() and GameState.phase() == GameState.Phase.Night) then
		refuseShot("RAID ONLY")
		return
	end
	if GameState.phase() ~= GameState.Phase.Night then
		refuseShot("NIGHT ONLY")
		return
	end
	if kind == "Taser" then
		if now() < math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt)) then
			Fx.click(Config.Sounds.EmptySpeed)
			triggerHeld = false
			return
		end
		shoot(kind)
		triggerHeld = false
		return
	end
	if reloading() then
		return
	end
	if predictedAmmo(kind) <= 0 then
		Fx.click(Config.Sounds.EmptySpeed)
		triggerHeld = false
		requestReload()
		return
	end
	shoot(kind)
	if not info.Automatic then
		triggerHeld = false
	end
end

---------------------------------------------------------------- интерфейс: слоты, патроны, прицел

local gui = Theme.screenGui("Weapons", 2)

-- Места 1–4 — пиксельные кнопки без рамки и фона (этап 5, блок D): иконка оружия, под ней патроны / READY / × 2.
-- Пустые места не видны. Выбранное — иконка выше и подпись золотом. На телефоне — в самом низу по центру
-- (справа внизу — кнопки FIRE, RELOAD, CROUCH, слева — джойстик).
local HOTBAR_CELL = Config.PixelUI.HudCell
local SLOT_WIDTH = 16 * HOTBAR_CELL + 40
local hotbar = Theme.new("Frame", {
	Name = "Hotbar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = if touchOnly then UDim2.new(0.5, 0, 1, -6) else UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.new(0, 4 * SLOT_WIDTH + 3 * 6, 0, 16 * HOTBAR_CELL + 40),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
Theme.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = hotbar,
})

local SLOT_ICONS = { "Rifle", "Pistol", "Taser", "Medkit" }
type Slot = { button: PixelButton.IconButton, icon: string }
local slots: { Slot } = {}

for index = 1, 4 do
	local button = PixelButton.new({
		icon = SLOT_ICONS[index],
		label = "",
		key = tostring(index),
		cell = HOTBAR_CELL,
		width = SLOT_WIDTH,
		name = "Slot" .. index,
		layoutOrder = index,
		parent = hotbar,
		onActivated = function()
			equipRemote:FireServer(index)
		end,
	})
	button.root.Visible = false
	slots[index] = { button = button, icon = SLOT_ICONS[index] }
end

local toast = Theme.label({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	-- телефон: под прицелом, не шире Config.Mobile.PanelWidth экрана (внизу — джойстик и кнопки)
	Position = if touchOnly then UDim2.new(0.5, 0, 0.5, 64) else UDim2.new(0.5, 0, 1, -146),
	Size = if touchOnly then UDim2.new(Config.Mobile.PanelWidth, 0, 0, 28) else UDim2.new(0, 420, 0, 28),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gold,
	MaxTextSize = 20,
	Visible = false,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = toast })

local ammoPanel = Theme.new("Frame", {
	Name = "Ammo",
	AnchorPoint = if touchOnly then Vector2.new(0.5, 1) else Vector2.new(1, 1),
	Position = if touchOnly then UDim2.new(0.5, 0, 1, -100) else UDim2.new(1, -20, 1, -20), -- телефон: над местами 1–4
	Size = UDim2.new(0, 170, 0, 64),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local ammoBig = Theme.label({ Size = UDim2.fromScale(0.55, 1), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 48, Parent = ammoPanel })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2.5, Parent = ammoBig })
local ammoSmall = Theme.label({ Position = UDim2.fromScale(0.58, 0.4), Size = UDim2.fromScale(0.42, 0.5), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Colors.Marble, MaxTextSize = 24, Parent = ammoPanel })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = ammoSmall })
local ammoTitle = Theme.label({ Position = UDim2.fromScale(0.58, 0.05), Size = UDim2.fromScale(0.42, 0.35), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Colors.Gold, Font = Theme.BodyFont, MaxTextSize = 14, Parent = ammoPanel })
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1.5, Parent = ammoTitle })
Theme.pixelize(ammoBig, ammoSmall, ammoTitle)

-- Прицел: 4 чёрточки, расходятся от отдачи; попадание — крестик
local crosshair = Theme.new("Frame", {
	Name = "Crosshair",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(60, 60),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local ticks: { Frame } = {}
for index = 1, 4 do
	local horizontal = index <= 2
	local tick = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = if horizontal then UDim2.fromOffset(10, 2) else UDim2.fromOffset(2, 10),
		BackgroundColor3 = Colors.White,
		BorderSizePixel = 0,
		Parent = crosshair,
	}, { Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1 }) })
	ticks[index] = tick
end
local centerDot = Theme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(3, 3),
	BackgroundColor3 = Colors.White,
	BorderSizePixel = 0,
	Parent = crosshair,
})
local hitmarks: { Frame } = {}
for index = 1, 4 do
	local mark = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, (if index % 2 == 0 then 1 else -1) * 9, 0.5, (if index <= 2 then -1 else 1) * 9),
		Size = UDim2.fromOffset(10, 2),
		Rotation = if (index == 1 or index == 4) then 45 else -45,
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = crosshair,
	})
	hitmarks[index] = mark
end

local HIT_COLORS = { hit = Colors.White, head = Color3.fromHex("FFB13B"), ko = Colors.Red, stun = Color3.fromHex("6FD3FF") }

Remotes.get(Remotes.Names.HitConfirm).OnClientEvent:Connect(function(kind)
	local color = HIT_COLORS[kind] or Colors.White
	for _, mark in hitmarks do
		mark.BackgroundColor3 = color
		mark.BackgroundTransparency = 0
		TweenService:Create(mark, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
	Fx.click(Config.Sounds.HitSpeed, 0.5)
end)

showToast = function(text: string)
	toast.Text = text
	toast.Visible = true
	holsterWarnUntil = os.clock() + 1.8
end

local function slotWeapon(index: number): string?
	if index == 1 then
		local primary = localPlayer:GetAttribute(PlayerAttr.Primary)
		return if typeof(primary) == "string" and primary ~= "" then primary else nil
	elseif index == 2 then
		return if GameState.hasWeapon(localPlayer, "Pistol") then "Pistol" else nil
	elseif index == 3 then
		return if GameState.hasWeapon(localPlayer, "Taser") then "Taser" else nil
	end
	return if number(PlayerAttr.Medkits) > 0 then "Medkit" else nil
end

local refreshTouch: (() -> ())? = nil

local function refreshHud()
	local shift = onShift()
	local any = false
	local current = equipped()
	for index, slot in slots do
		local weapon = slotWeapon(index)
		any = any or weapon ~= nil
		local selected = weapon ~= nil and weapon == current
		local button = slot.button
		button.root.Visible = weapon ~= nil
		if weapon then
			if index == 1 and weapon ~= slot.icon then
				slot.icon = weapon
				button.setIcon(weapon) -- автомат или дробовик
			end
			local text
			if FIREARMS[weapon] then
				text = ("%d|%d"):format(predictedAmmo(weapon), reserveOf(weapon))
			elseif weapon == "Taser" then
				local left = math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt)) - now()
				text = if left > 0 then ("%dS"):format(math.ceil(left)) else "READY"
			else
				text = ("X%d"):format(number(PlayerAttr.Medkits))
			end
			button.setLabel(text)
			local label = button.label
			if label then
				label.TextColor3 = if selected then Colors.Gold elseif FIREARMS[weapon] and not raidActive() then Colors.Gray else Colors.White
			end
			local holder = button.root:FindFirstChild("IconHolder") :: Frame?
			if holder then
				holder.Position = UDim2.new(0.5, 0, 0, 8 * HOTBAR_CELL - (if selected then 2 * HOTBAR_CELL else 0))
			end
		end
	end
	-- Телефон (этап 8, блок Q): мест 1–4 и патронов внизу нет — их заменяет кнопка оружия с колесом справа
	hotbar.Visible = shift and any and not viewing() and not spectating() and not touchOnly
	local showAmmo = shift and FIREARMS[current] == true and not viewing() and not downed() and not spectating() and not touchOnly
	ammoPanel.Visible = showAmmo
	if showAmmo then
		local info = (Weapons :: any)[current]
		ammoTitle.Text = if reloading() then "RELOADING" else info.Title
		ammoBig.Text = tostring(predictedAmmo(current))
		ammoBig.TextColor3 = if predictedAmmo(current) == 0 then Colors.Red else Colors.White
		ammoSmall.Text = "/ " .. tostring(reserveOf(current))
	end
	if toast.Visible and os.clock() > holsterWarnUntil then
		toast.Visible = false
	end
	local touchRefresh = refreshTouch
	if touchRefresh then
		touchRefresh()
	end
end

---------------------------------------------------------------- управление

local function onSlot(index: number)
	if not onShift() or viewing() then
		return
	end
	local weapon = slotWeapon(index)
	if not weapon then
		if index == 4 then
			showToast("No medkit — buy one in the armory")
		else
			showToast(("No %s — buy it in the armory"):format(string.lower(SLOT_TITLES[index])))
		end
		return
	end
	if downed() then
		return
	end
	equipRemote:FireServer(index)
end

local SLOT_ACTION = "WeaponSlot"
local RELOAD_ACTION = "WeaponReload"
local FIRE_ACTION = "WeaponFire"
local CROUCH_ACTION = "StanceCrouch"
local LEAN_LEFT_ACTION = "StanceLeanLeft"
local LEAN_RIGHT_ACTION = "StanceLeanRight"

---------------------------------------------------------------- присед и наклон (блок 4.4)

-- Присед (C) — переключатель; наклон (Q / E) — пока держишь (на телефоне — нажал / нажал ещё раз).
-- Решает сервер (скорость, позу видят все); здесь — только намерение.
local wantCrouch = false
local leanLeftHeld, leanRightHeld = false, false
local sentCrouch, sentLean = false, 0

local function sendStance()
	local lean = if leanLeftHeld and not leanRightHeld then -1 elseif leanRightHeld and not leanLeftHeld then 1 else 0
	if downed() then
		wantCrouch, leanLeftHeld, leanRightHeld, lean = false, false, false, 0
	end
	if wantCrouch ~= sentCrouch or lean ~= sentLean then
		sentCrouch, sentLean = wantCrouch, lean
		stanceRemote:FireServer(wantCrouch, lean)
	end
end

-- Сервер сам снял стойку (упал без сил, конец забега) — забываем и у себя
localPlayer:GetAttributeChangedSignal(PlayerAttr.Crouch):Connect(function()
	local crouch = localPlayer:GetAttribute(PlayerAttr.Crouch) == true
	if not crouch and sentCrouch then
		wantCrouch, sentCrouch = false, false
	end
end)
localPlayer:GetAttributeChangedSignal(PlayerAttr.Lean):Connect(function()
	if number(PlayerAttr.Lean) == 0 and sentLean ~= 0 then
		leanLeftHeld, leanRightHeld, sentLean = false, false, 0
	end
end)

local function onCrouchAction(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and not viewing() then
		wantCrouch = not wantCrouch
		sendStance()
	end
	return Enum.ContextActionResult.Sink
end

local function onLeanAction(name: string, state: Enum.UserInputState)
	local left = name == LEAN_LEFT_ACTION
	if state == Enum.UserInputState.Begin and not viewing() then
		if touchOnly then
			-- На телефоне кнопка — переключатель
			if left then
				leanLeftHeld, leanRightHeld = not leanLeftHeld, false
			else
				leanRightHeld, leanLeftHeld = not leanRightHeld, false
			end
		elseif left then
			leanLeftHeld = true
		else
			leanRightHeld = true
		end
	elseif (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) and not touchOnly then
		if left then
			leanLeftHeld = false
		else
			leanRightHeld = false
		end
	end
	sendStance()
	return Enum.ContextActionResult.Sink
end

local function onSlotAction(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin or viewing() then
		return Enum.ContextActionResult.Pass
	end
	local index = table.find(Keys.Slots, input.KeyCode)
	if index then
		onSlot(index)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function onReloadAction(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		requestReload()
	end
	return Enum.ContextActionResult.Sink
end

local function onFireAction(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		triggerHeld = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		triggerHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local bound = false
local fireBound = false

-- Кнопки на телефоне (этап 8, блок Q, раскладка «одна умная кнопка»): справа кнопка оружия (открывает колесо) и
-- маленькая R (видна, когда в руках огнестрел и магазин не полный; пустой магазин перезаряжается сам), огонь — умная
-- кнопка (SmartButton.client), присед и наклоны — в «Меню». Нажатие вызывает те же функции, что и клавиши.
local touch: { [string]: TouchButtons.TouchButton } = {}
local stanceInMenu = false -- присед и наклоны сейчас доступны (на смене, не лежит, не смотрит камеры)
local wheelOpen = false
if touchOnly then
	local function begin(handler: (string, Enum.UserInputState, InputObject?) -> any, action: string): () -> ()
		return function()
			handler(action, Enum.UserInputState.Begin, nil)
		end
	end
	local setWheelOpen: (open: boolean) -> ()
	touch.Reload = TouchButtons.new({ place = "Reload", icon = "Reload", label = "", onActivated = begin(onReloadAction, RELOAD_ACTION) })
	touch.Wheel = TouchButtons.new({
		place = "Wheel",
		icon = "Pistol",
		label = "",
		onActivated = function()
			setWheelOpen(not wheelOpen)
		end,
	})

	local function stanceVisible(): boolean
		return stanceInMenu
	end
	MobileMenu.add({
		id = "Crouch",
		icon = "Crouch",
		label = "CROUCH",
		order = 5,
		visible = stanceVisible,
		text = function(): string
			return if wantCrouch then "STAND UP" else "CROUCH"
		end,
		onActivated = begin(onCrouchAction, CROUCH_ACTION),
	})
	MobileMenu.add({
		id = "LeanLeft",
		icon = "ArrowLeft",
		label = "LEAN LEFT",
		order = 6,
		visible = stanceVisible,
		text = function(): string
			return if leanLeftHeld then "LEAN OFF" else "LEAN LEFT"
		end,
		onActivated = begin(onLeanAction, LEAN_LEFT_ACTION),
	})
	MobileMenu.add({
		id = "LeanRight",
		icon = "ArrowRight",
		label = "LEAN RIGHT",
		order = 7,
		visible = stanceVisible,
		text = function(): string
			return if leanRightHeld then "LEAN OFF" else "LEAN RIGHT"
		end,
		onActivated = begin(onLeanAction, LEAN_RIGHT_ACTION),
	})

	-- Колесо оружия: места 1–4 (только те, что есть) и «убрать», по дуге вокруг кнопки оружия вверх-влево.
	-- Нажал — выбрал, колесо закрылось само. Нажал мимо — закрылось.
	local _, mobileRoot = Mobile.gui()
	local dismiss = Theme.new("TextButton", {
		Name = "WheelDismiss",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.7,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 1,
		Parent = mobileRoot,
	})
	dismiss.Activated:Connect(function()
		setWheelOpen(false)
	end)
	type WheelItem = { round: Mobile.RoundButton, slot: number }
	local wheelItems: { WheelItem } = {}
	for slot = 0, 4 do
		local round = Mobile.roundButton({
			name = "Wheel" .. slot,
			icon = if slot == 0 then "Close" else SLOT_ICONS[slot],
			label = if slot == 0 then "OFF" else "",
			onActivated = function()
				setWheelOpen(false)
				if slot == 0 then
					if equipped() ~= "" and not viewing() then
						equipRemote:FireServer(0)
					end
				else
					onSlot(slot)
				end
			end,
		})
		round.root.Visible = false
		round.root.ZIndex = 3
		table.insert(wheelItems, { round = round, slot = slot })
	end

	local function slotLabel(weapon: string): string
		if FIREARMS[weapon] then
			return ("%d|%d"):format(predictedAmmo(weapon), reserveOf(weapon))
		elseif weapon == "Taser" then
			local left = math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt)) - now()
			return if left > 0 then ("%dS"):format(math.ceil(left)) else "READY"
		elseif weapon == "Medkit" then
			return ("X%d"):format(number(PlayerAttr.Medkits))
		end
		return ""
	end

	local function layoutWheel()
		local center = Mobile.slot("Wheel").center
		local s = Mobile.scale()
		local settings = Config.Mobile
		local size = math.floor(settings.WheelItemSize * s)
		local current = equipped()
		local order = 0
		for _, item in wheelItems do
			local weapon = if item.slot == 0 then nil else slotWeapon(item.slot)
			local show = wheelOpen and (if item.slot == 0 then current ~= "" else weapon ~= nil)
			item.round.setVisible(show)
			if show then
				local angle = math.rad(settings.WheelStartAngle + order * settings.WheelStepAngle)
				order += 1
				local x = center.X + math.cos(angle) * settings.WheelRadius * s
				local y = center.Y - math.sin(angle) * settings.WheelRadius * s
				item.round.root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
				item.round.root.Size = UDim2.fromOffset(size, size)
				if weapon then
					item.round.setIcon(weapon)
					item.round.setLabel(slotLabel(weapon))
					item.round.setColor(if weapon == current then Colors.Gold else Colors.Gray)
				end
			end
		end
	end

	setWheelOpen = function(open: boolean)
		wheelOpen = open
		dismiss.Visible = open
		if open then
			MobileMenu.close()
		end
		layoutWheel()
	end

	-- Автоперезарядка: магазин пуст — через Config.Mobile.AutoReloadDelay сек сама
	local emptySince = 0
	refreshTouch = function()
		local shift = onShift()
		local current = equipped()
		local free = shift and not viewing() and not spectating() and not downed()
		local any = false
		for index = 1, 4 do
			if slotWeapon(index) then
				any = true
				break
			end
		end
		local wheel = touch.Wheel
		wheel.setVisible(free and any)
		if free and any then
			local shownWeapon = if current ~= "" then current else (slotWeapon(1) or slotWeapon(2) or slotWeapon(3) or slotWeapon(4) or "Pistol")
			wheel.setIcon(shownWeapon)
			wheel.setLabel(if current == "" then "" elseif reloading() then "..." else slotLabel(current))
			wheel.setColor(if current ~= "" then Colors.Gold else Colors.Gray)
		end
		if wheelOpen and not (free and any) then
			setWheelOpen(false)
		elseif wheelOpen then
			layoutWheel()
		end

		local firearm = FIREARMS[current] == true and shownKind == current
		local info = if firearm then (Weapons :: any)[current] else nil
		local ammo = if firearm then predictedAmmo(current) else 0
		local canReload = info ~= nil and not reloading() and ammo < info.MagSize and reserveOf(current) > 0
		touch.Reload.setVisible(free and canReload)
		if free and firearm and ammo <= 0 and canReload then
			if emptySince == 0 then
				emptySince = os.clock()
			elseif os.clock() - emptySince >= Config.Mobile.AutoReloadDelay then
				emptySince = 0
				requestReload()
			end
		else
			emptySince = 0
		end
	end

	-- Огонь — умная кнопка (этап 8, блок Q, SmartButton.client): FIRE в налёт, TASER ночью, HEAL с аптечкой.
	-- Вне налёта огнестрел не стреляет — кнопка бледная (подсказка рядом всё равно важнее).
	local function trigger(label: string, icon: string): Mobile.Action
		return {
			label = label,
			icon = icon,
			press = function()
				onFireAction(FIRE_ACTION, Enum.UserInputState.Begin)
			end,
			release = function()
				onFireAction(FIRE_ACTION, Enum.UserInputState.End)
			end,
		}
	end
	Mobile.setWeaponAction(function(): Mobile.Action?
		if not onShift() or downed() or viewing() or spectating() or knocked() or reviving() then
			return nil
		end
		local kind = equipped()
		local night = GameState.phase() == GameState.Phase.Night
		if FIREARMS[kind] and night and raidActive() then
			return trigger("FIRE", "Fire")
		elseif kind == "Taser" and night then
			return trigger("TASER", "Taser")
		elseif kind == "Medkit" then
			return trigger("HEAL", "Medkit")
		end
		return nil
	end)
end

-- Клавиши оружия работают только на смене (в лобби 1 / 2 — выбор роли)
local function setBound(shift: boolean, holding: boolean)
	if shift ~= bound then
		bound = shift
		if shift then
			ContextActionService:BindAction(SLOT_ACTION, onSlotAction, false, table.unpack(Keys.Slots))
			ContextActionService:BindAction(RELOAD_ACTION, onReloadAction, false, Keys.Reload)
			ContextActionService:BindAction(CROUCH_ACTION, onCrouchAction, false, Keys.Crouch, Enum.KeyCode.ButtonB)
			ContextActionService:BindAction(LEAN_LEFT_ACTION, onLeanAction, false, Keys.LeanLeft, Enum.KeyCode.ButtonL1)
			ContextActionService:BindAction(LEAN_RIGHT_ACTION, onLeanAction, false, Keys.LeanRight, Enum.KeyCode.ButtonR1)
		else
			ContextActionService:UnbindAction(SLOT_ACTION)
			ContextActionService:UnbindAction(RELOAD_ACTION)
			ContextActionService:UnbindAction(CROUCH_ACTION)
			ContextActionService:UnbindAction(LEAN_LEFT_ACTION)
			ContextActionService:UnbindAction(LEAN_RIGHT_ACTION)
			if sentCrouch or sentLean ~= 0 then
				stanceRemote:FireServer(false, 0)
			end
			wantCrouch, leanLeftHeld, leanRightHeld = false, false, false
			sentCrouch, sentLean = false, 0
			taserReadyLocal = 0
		end
	end
	-- На геймпаде — правый курок, пока в руках оружие или аптечка (на телефоне — умная кнопка, SmartButton.client)
	local wantFire = shift and holding
	if wantFire ~= fireBound then
		fireBound = wantFire
		if wantFire then
			ContextActionService:BindAction(FIRE_ACTION, onFireAction, false, Enum.KeyCode.ButtonR2)
		else
			ContextActionService:UnbindAction(FIRE_ACTION)
			triggerHeld = false
		end
	end
	stanceInMenu = shift and not viewing() and not downed()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and onShift() and equipped() ~= "" then
		triggerHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = false
	end
end)

---------------------------------------------------------------- анимации у камеры

-- Смещения подвижных частей (магазин, затвор, помпа) и левой руки при перезарядке.
-- leftAt — где левая рука (в системе оружия), если не у цевья; shellAt — патрон дробовика в руке.
type Motion = { root: CFrame, mag: CFrame, slide: CFrame, pump: CFrame, left: CFrame, hideMag: boolean, leftAt: Vector3?, shellAt: Vector3? }

local function newMotion(): Motion
	return { root = CFrame.identity, mag = CFrame.identity, slide = CFrame.identity, pump = CFrame.identity, left = CFrame.identity, hideMag = false }
end

-- Пояс с подсумками (в системе оружия): сюда левая рука тянется за магазином или патроном
local BELT = Vector3.new(-0.95, -1.2, 0.85)

-- Перезарядка заметнее (этап 8, блок O): пистолет и автомат — наклон, старый магазин выпадает, кувыркаясь,
-- рука идёт к поясу и вставляет новый снизу, в конце — затвор (у автомата — рукоять затвора);
-- дробовик — по патрону от пояса в окно снизу, потом помпа.
local function reloadMotion(kind: string, p: number, current: View): Motion
	local motion = newMotion()
	local support = current.built.support.Position
	if kind == "Shotgun" then
		local tilt = smooth(p / 0.1) * (1 - smooth((p - 0.86) / 0.12))
		motion.root = CFrame.new(-0.1 * tilt, 0.12 * tilt, 0.05 * tilt) * CFrame.Angles(0.15 * tilt, 0, 0.55 * tilt)
		local port = support + Vector3.new(0, -0.12, 0.55)
		if p >= 0.1 and p < 0.8 then
			local cycle = ((p - 0.1) / 0.7 * 4) % 1
			if cycle < 0.45 then
				motion.leftAt = port:Lerp(BELT, smooth(cycle / 0.45))
			else
				local hand = BELT:Lerp(port, smooth((cycle - 0.45) / 0.45))
				motion.leftAt = hand
				motion.shellAt = hand
			end
		elseif p >= 0.8 and p < 0.84 then
			motion.leftAt = port:Lerp(support, smooth((p - 0.8) / 0.04))
		end
		motion.pump = CFrame.new(0, 0, 0.4 * bump(p, 0.84, 0.98))
		return motion
	end
	local tilt = smooth(p / 0.12) * (1 - smooth((p - 0.86) / 0.14))
	motion.root = CFrame.new(-0.06 * tilt, 0.1 * tilt, 0.04 * tilt) * CFrame.Angles(0.25 * tilt, 0.15 * tilt, 0.5 * tilt)
	local magBottom = current.magBottom or (support + Vector3.new(0, -0.4, 0.6))
	if p >= 0.1 and p < 0.32 then
		local k = (p - 0.1) / 0.22
		motion.mag = CFrame.new(0, -2.6 * k * k, 0.15 * k) * CFrame.Angles(0.9 * k, 0, 0.5 * k)
		motion.hideMag = k > 0.85
	elseif p >= 0.32 and p < 0.47 then
		motion.hideMag = true
		motion.leftAt = support:Lerp(BELT, smooth((p - 0.32) / 0.15))
	elseif p >= 0.47 and p < 0.78 then
		-- Новый магазин в левой руке: от пояса вверх в шахту, в конце — толчок снизу
		local hand = BELT:Lerp(magBottom, smooth((p - 0.47) / 0.23)) + Vector3.new(0, 0.08 * bump(p, 0.7, 0.78), 0)
		motion.leftAt = hand
		motion.mag = CFrame.new(hand - magBottom)
	elseif p >= 0.78 then
		local slideAt = current.slideAt or (support + Vector3.new(0, 0.2, 0.4))
		local pull = bump(p, 0.83, 0.95)
		motion.slide = CFrame.new(0, 0, 0.3 * pull)
		local slideHand = slideAt + Vector3.new(0, 0.04, 0.3 * pull)
		if p < 0.83 then
			motion.leftAt = magBottom:Lerp(slideHand, smooth((p - 0.78) / 0.05))
		elseif p < 0.95 then
			motion.leftAt = slideHand
		else
			motion.leftAt = slideHand:Lerp(support, smooth((p - 0.95) / 0.05))
		end
	end
	return motion
end

-- Достать и убрать (этап 8, блок O): t = 1 — в руках, 0 — в кобуре. Пистолет — из кобуры на правом бедре,
-- шокер — с левого бедра (правая рука тянется накрест), автомат и дробовик — из-за правого плеча со спины,
-- аптечка — снизу.
local function drawPose(kind: string, t: number): CFrame
	local u = 1 - t
	if kind == "Rifle" or kind == "Shotgun" then
		return CFrame.new(0.25 * u, 1.0 * u, 0.8 * u) * CFrame.Angles(1.5 * u, 0, -0.5 * u)
	elseif kind == "Pistol" then
		return CFrame.new(0.15 * u, -1.1 * u, 0.45 * u) * CFrame.Angles(-1.3 * u, 0, -0.3 * u)
	elseif kind == "Taser" then
		return CFrame.new(-0.6 * u, -1.1 * u, 0.4 * u) * CFrame.Angles(-1.3 * u, 0, 0.4 * u)
	end
	return CFrame.new(0, -0.9 * u, 0.2 * u) * CFrame.Angles(-0.7 * u, 0, 0)
end

-- Действие из атрибута Action (сервер): что сейчас и насколько (0..1). Звук — в начале действия.
local function currentAction(): (string, number)
	local kind = localPlayer:GetAttribute(PlayerAttr.Action)
	local untilTime = number(PlayerAttr.ActionUntil)
	local time = now()
	if typeof(kind) ~= "string" or kind == "" or untilTime <= time then
		actionKind = ""
		return "", 0
	end
	if kind ~= actionKind then
		actionKind = kind
		actionStart = time
		if kind == "Vest" then
			Fx.sound(Config.Sounds.VestOn)
		elseif kind == "Repair" then
			Fx.sound(Config.Sounds.Screwdriver)
		end
	end
	return kind, math.clamp((time - actionStart) / math.max(0.05, untilTime - actionStart), 0, 1)
end

local function camPoint(cf: CFrame, x: number, y: number, z: number): Vector3
	return (cf * CFrame.new(x, y, z)).Position
end

-- Руки в действии (оружие убрано из кадра): бронежилет через голову и застёгивает, покупка — правая рука
-- тянется и берёт, ремонт — отвёртка крутится в правой руке, арест — наручники обеими руками вперёд-вниз.
local function actionArms(action: string, p: number, cf: CFrame, up: Vector3, time: number)
	setArmVisible(leftArm, true)
	setArmVisible(rightArm, true)
	local leftDir = cf:VectorToWorldSpace(LEFT_ARM_DIR)
	local rightDir = cf:VectorToWorldSpace(RIGHT_ARM_DIR)
	if action == "Vest" then
		if p < 0.5 then
			local over = smooth(p / 0.5)
			local y, z = -1.05 + 1.75 * over, -1.35 + 1.1 * over
			local l, r = camPoint(cf, -0.5, y, z), camPoint(cf, 0.5, y, z)
			placeArm(leftArm, l, leftDir, up, -1)
			placeArm(rightArm, r, rightDir, up, 1)
			local mid = (l + r) / 2
			showProp("Vest", CFrame.lookAt(mid, mid + cf.LookVector, up) * CFrame.new(0, -0.45, 0))
		else
			local side = 1 - smooth((p - 0.5) / 0.15)
			local zip = smooth((p - 0.6) / 0.35)
			placeArm(leftArm, camPoint(cf, -0.2 - 0.3 * side, -1.2, -0.75), leftDir, up, -1)
			placeArm(rightArm, camPoint(cf, 0.12 + 0.35 * side, -1.3 + 0.45 * zip, -0.72), rightDir, up, 1)
		end
	elseif action == "Buy" then
		local reach = math.sin(p * math.pi)
		setArmVisible(leftArm, false)
		placeArm(rightArm, camPoint(cf, 0.3 - 0.08 * reach, -0.6 + 0.2 * reach, -1.3 - 0.7 * reach), rightDir, up, 1)
	elseif action == "Repair" then
		local twist = math.sin(time * Actions.ScrewdriverSpeed) * 0.9
		local hand = camPoint(cf, 0.22, -0.38, -1.45)
		local handUp = cf:VectorToWorldSpace(Vector3.new(math.sin(twist) * 0.8, math.cos(twist), 0).Unit)
		placeArm(rightArm, hand, rightDir, handUp, 1)
		showProp("Screwdriver", CFrame.lookAt(hand, hand + cf.LookVector, handUp) * CFrame.new(0, 0, -0.08))
		placeArm(leftArm, camPoint(cf, -0.32, -0.5, -1.4), leftDir, up, -1)
	else
		local shake = math.sin(time * 14) * 0.03
		local l, r = camPoint(cf, -0.2, -0.78 + shake, -1.25), camPoint(cf, 0.2, -0.78 - shake, -1.25)
		placeArm(leftArm, l, leftDir, up, -1)
		placeArm(rightArm, r, rightDir, up, 1)
		local mid = (l + r) / 2
		showProp("Cuffs", CFrame.lookAt(mid, mid + cf.LookVector, up) * CFrame.new(0, -0.04, -0.18))
	end
end

local function shotMotion(kind: string, since: number): (CFrame, CFrame)
	-- Затвор пистолета отскакивает после выстрела, помпа дробовика ходит назад-вперёд
	local slide = CFrame.identity
	local pump = CFrame.identity
	if kind == "Pistol" then
		slide = CFrame.new(0, 0, 0.24 * bump(since, 0, 0.12))
	elseif kind == "Shotgun" then
		pump = CFrame.new(0, 0, 0.4 * bump(since, 0.22, 0.62))
	end
	return slide, pump
end

local function placeView(dt: number, camera: Camera)
	local current = view
	local kind = shownKind
	local cf = camera.CFrame
	local time = now()
	local clampedDt = math.min(dt, 0.1)

	-- Покачивание: от поворота камеры оружие чуть отстаёт, при ходьбе и беге — шаг от реальной скорости
	local look = cf.LookVector
	if lastLook then
		local delta = cf:VectorToObjectSpace(lastLook)
		swayX = math.clamp(swayX + delta.X * 0.6, -0.15, 0.15)
		swayY = math.clamp(swayY + delta.Y * 0.6, -0.15, 0.15)
	end
	lastLook = look
	local decay = math.exp(-clampedDt * 10)
	swayX *= decay
	swayY *= decay
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rawSpeed = if root and root:IsA("BasePart") then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	if rawSpeed < 0.2 then
		rawSpeed = 0
	end
	bobSpeed += (rawSpeed - bobSpeed) * (1 - math.exp(-clampedDt * Config.Animations.BlendSpeed))
	bobPhase = (bobPhase + bobSpeed * clampedDt * Config.Animations.WeaponBobStride) % (math.pi * 2)
	local walkRatio = math.clamp(bobSpeed / Config.Players.WalkSpeed, 0, 1)
	local sprintRange = math.max(1, Config.Classes.Patrol.SprintSpeed - Config.Players.WalkSpeed)
	local sprintRatio = math.clamp((bobSpeed - Config.Players.WalkSpeed) / sprintRange, 0, 1)
	local bobAmp = walkRatio + sprintRatio * Config.Animations.WeaponSprintBobBoost
	local idleBreath = (1 - walkRatio) * 0.004 * math.sin(time * Config.Animations.BreathSpeed)
	local bob = CFrame.new(
		math.sin(bobPhase) * 0.035 * bobAmp,
		-math.abs(math.cos(bobPhase)) * 0.03 * bobAmp + idleBreath,
		0
	) * CFrame.Angles(-0.025 * sprintRatio * math.abs(math.cos(bobPhase)), 0, -0.04 * sprintRatio * math.sin(bobPhase))
	local sway = CFrame.new(swayX, swayY, 0) * CFrame.Angles(swayY * 0.6, swayX * 0.6, swayX * 0.8)

	-- Отдача: назад и вверх, быстро возвращается
	recoilKick *= math.exp(-clampedDt * 12)
	spread *= math.exp(-clampedDt * 6)
	local kick = CFrame.new(0, 0.03 * recoilKick, 0.22 * recoilKick) * CFrame.Angles(0.16 * recoilKick, 0, 0)

	-- Достать (из кобуры, со спины, снизу) или убрать обратно (этап 8, блок O)
	local drawT = smooth((time - equipStarted) / Weapons.EquipSeconds)
	if holsterStarted > 0 then
		drawT = math.min(drawT, 1 - smooth((time - holsterStarted) / Actions.HolsterSeconds))
	end
	local raise = drawPose(kind, drawT)
	-- Взмах шокером при ударе
	if kind == "Taser" and lastShotKind == "Taser" then
		local swing = bump(time - lastShotAt, 0, Actions.TaserSwingSeconds)
		raise = raise * CFrame.new(-0.12 * swing, 0.06 * swing, -0.25 * swing) * CFrame.Angles(0.25 * swing, 0.35 * swing, -0.5 * swing)
	end

	-- Присел — оружие плавно опускается ниже; наклон — чуть повёрнуто
	local downedNow = downed()
	local reviving = number(PlayerAttr.ReviveTarget) ~= 0
	local crouchTarget = if localPlayer:GetAttribute(PlayerAttr.Crouch) == true and not downedNow and not reviving then 1 else 0
	local leanTarget = if not downedNow and not reviving then number(PlayerAttr.Lean) else 0
	local stanceAlpha = 1 - math.exp(-clampedDt * Config.Stance.BlendSpeed)
	crouchBlend += (crouchTarget - crouchBlend) * stanceAlpha
	leanBlend += (leanTarget - leanBlend) * stanceAlpha
	local crouchDrop = CFrame.new(0, -Config.Animations.WeaponCrouchDrop * crouchBlend, 0)
	local stance = CFrame.Angles(0, 0, leanBlend * 0.08 - crouchBlend * 0.04)

	local up = cf.UpVector

	if downedNow then
		-- Лежит без сил: руки внизу экрана по очереди тянутся вперёд и подтягивают тело
		local s = math.sin(bobPhase * 0.8)
		local move = math.clamp(bobSpeed / Config.Health.CrawlSpeed, 0, 1)
		setArmVisible(leftArm, true)
		setArmVisible(rightArm, true)
		local leftHand = cf * CFrame.new(-0.55, -0.9 + 0.1 * s * move, -1.25 - 0.3 * s * move)
		local rightHand = cf * CFrame.new(0.55, -0.9 - 0.1 * s * move, -1.25 + 0.3 * s * move)
		placeArm(leftArm, leftHand.Position, cf:VectorToWorldSpace(Vector3.new(-0.25, -0.35, 1).Unit), up, -1)
		placeArm(rightArm, rightHand.Position, cf:VectorToWorldSpace(Vector3.new(0.25, -0.35, 1).Unit), up, 1)
		return
	elseif reviving then
		-- Поднимает друга: обе руки вперёд-вниз, в такт
		local pump = math.sin(time * 5)
		setArmVisible(leftArm, true)
		setArmVisible(rightArm, true)
		local leftHand = cf * CFrame.new(-0.3, -0.95 + 0.06 * pump, -1.35)
		local rightHand = cf * CFrame.new(0.3, -0.95 + 0.06 * pump, -1.35)
		placeArm(leftArm, leftHand.Position, cf:VectorToWorldSpace(Vector3.new(-0.3, -0.5, 1).Unit), up, -1)
		placeArm(rightArm, rightHand.Position, cf:VectorToWorldSpace(Vector3.new(0.3, -0.5, 1).Unit), up, 1)
		return
	end

	-- Действие (бронежилет, покупка, ремонт, арест): оружие из кадра, руки заняты (этап 8, блок O)
	local action, actionP = currentAction()
	if action ~= "" then
		hideWeapon(cf)
		actionArms(action, actionP, cf, up, time)
		return
	end

	if not current then
		setArmVisible(leftArm, false)
		setArmVisible(rightArm, false)
		return
	end

	-- Перезарядка и выстрел двигают части оружия и левую руку
	local motion = newMotion()
	local reloadUntil = number(PlayerAttr.ReloadUntil)
	local info = (Weapons :: any)[kind]
	if FIREARMS[kind] and reloadUntil > time then
		motion = reloadMotion(kind, 1 - (reloadUntil - time) / info.ReloadSeconds, current)
	end
	if lastShotKind == kind then
		local slide, pump = shotMotion(kind, time - lastShotAt)
		motion.slide = motion.slide * slide
		motion.pump = motion.pump * pump
	end
	-- Аптечка (этап 8, блок O): подносит к груди, открывает крышку, левая рука берёт бинт и бинтует грудь,
	-- кладёт обратно и закрывает (Weapons.Medkit.UseSeconds); возвращается плавно
	local healUntil = number(PlayerAttr.HealUntil)
	local healActive = kind == "Medkit" and healUntil > time
	if healActive and not healWasActive then
		Fx.sound(Config.Sounds.MedkitUse)
	end
	healWasActive = healActive
	healBlend += ((if healActive then 1 else 0) - healBlend) * (1 - math.exp(-clampedDt * Config.Animations.BlendSpeed))
	local healP = if healActive then math.clamp(1 - (healUntil - time) / Weapons.Medkit.UseSeconds, 0, 1) else 1
	local healMotion = CFrame.identity
	local lidOpen = 0
	if kind == "Medkit" and healBlend > 0.002 then
		local k = smooth(healP / 0.15) * healBlend
		healMotion = CFrame.new(0.12 * k, 0.05 * k, 0.4 * k) * CFrame.Angles(0.35 * k, 0, 0)
		lidOpen = smooth((healP - 0.12) / 0.15) * (1 - smooth((healP - 0.78) / 0.12)) * 1.35 * healBlend
	end
	local lidMotion = MEDKIT_HINGE * CFrame.Angles(-lidOpen, 0, 0) * MEDKIT_HINGE:Inverse()
	-- Шокер на перезарядке: экран красный
	local base = cf * crouchDrop * HOLD[kind] * stance * sway * bob * raise * kick * motion.root * healMotion
	local built = current.built
	built.root.CFrame = base
	for index, part in built.parts do
		local group = current.groups[index]
		local offset = built.offsets[index]
		if group == "Mag" then
			part.CFrame = base * motion.mag * offset
			part.Transparency = if motion.hideMag then 1 else 0
		elseif group == "Slide" then
			part.CFrame = base * motion.slide * offset
		elseif group == "Pump" then
			part.CFrame = base * motion.pump * offset
		elseif group == "Lid" then
			part.CFrame = base * lidMotion * offset
		else
			part.CFrame = base * offset
		end
		if kind == "Taser" and part.Name == "Screen" then
			local ready = time >= math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt))
			part.Color = if ready then WeaponModels.Colors.Turquoise else Colors.Red
		end
	end
	-- Руки: правая держит рукоять, левая — цевьё, помпу, низ рукояти или аптечку
	setArmVisible(rightArm, true)
	setArmVisible(leftArm, true)
	if kind == "Medkit" then
		placeArm(rightArm, (base * CFrame.new(0.62, -0.5, 0)).Position, cf:VectorToWorldSpace(RIGHT_ARM_DIR), up, 1)
		local leftHand = (base * CFrame.new(-0.62, -0.5, 0)).Position
		if healActive then
			local inside = (base * CFrame.new(-0.15, -0.2, 0)).Position
			local chest = camPoint(cf, -0.05, -0.95, -0.7)
			if healP >= 0.3 and healP < 0.4 then
				leftHand = leftHand:Lerp(inside, smooth((healP - 0.3) / 0.1))
			elseif healP >= 0.4 and healP < 0.5 then
				leftHand = inside:Lerp(chest, smooth((healP - 0.4) / 0.1))
			elseif healP >= 0.5 and healP < 0.7 then
				-- Бинтует: два круга у груди
				local q = (healP - 0.5) / 0.2
				local radius = math.sin(q * math.pi)
				local a = q * math.pi * 4
				leftHand = chest + cf:VectorToWorldSpace(Vector3.new(math.cos(a) * 0.2 * radius, math.sin(a) * 0.12 * radius, 0))
			elseif healP >= 0.7 and healP < 0.8 then
				leftHand = chest:Lerp(leftHand, smooth((healP - 0.7) / 0.1))
			end
			if healP >= 0.36 and healP < 0.74 then
				showProp("Bandage", CFrame.lookAt(leftHand, leftHand + cf.LookVector, up) * CFrame.new(0.05, 0.1, -0.1))
			end
		end
		placeArm(leftArm, leftHand, cf:VectorToWorldSpace(LEFT_ARM_DIR), up, -1)
		return
	end
	placeArm(rightArm, (base * CFrame.new(0.02, -0.08, 0.06)).Position, cf:VectorToWorldSpace(RIGHT_ARM_DIR), up, 1)
	local support = built.support
	if kind == "Shotgun" then
		support = motion.pump * support
	end
	local leftAt = motion.leftAt
	local leftHand = if leftAt then base * CFrame.new(leftAt) else base * support * motion.left
	local shellAt = motion.shellAt
	if shellAt then
		showProp("Shell", base * CFrame.new(shellAt) * CFrame.new(0, 0.12, -0.05))
	end
	placeArm(leftArm, leftHand.Position, cf:VectorToWorldSpace(LEFT_ARM_DIR), up, -1)
end

---------------------------------------------------------------- кадр

local function syncView()
	local kind = equipped()
	local calm = onShift() and not viewing() and not downed() and not reviving()
	local show = calm and kind ~= ""
	local wanted = if show then kind else ""
	if wanted == shownKind then
		holsterStarted = 0
	elseif calm and shownKind ~= "" and shownKind ~= "Medkit" and (holsterStarted == 0 or now() < holsterStarted + Actions.HolsterSeconds) then
		-- Сначала старое оружие уходит в кобуру или за спину (этап 8, блок O), потом достаётся новое
		if holsterStarted == 0 then
			holsterStarted = now()
			triggerHeld = false
		end
	else
		holsterStarted = 0
		shownKind = wanted
		buildView(wanted)
		equipStarted = now()
		triggerHeld = false
		if wanted ~= "" then
			Fx.click(0.6, 0.4)
		end
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local shift = onShift()
	syncView()
	setBound(shift, shownKind ~= "")
	local acting = currentAction() ~= ""
	local visible = shift and not viewing() and not spectating() and (shownKind ~= "" or downed() or number(PlayerAttr.ReviveTarget) ~= 0 or acting)
	if visible then
		if container.Parent ~= camera then
			container.Parent = camera
		end
		placeView(dt, camera)
	elseif container.Parent then
		container.Parent = nil
	end
	hideUnusedProps()
	-- Отдача уводит прицел: камера Roblox запоминает поворот сама, поэтому добавляем понемногу
	if cameraKick > 0.0001 or math.abs(cameraKickYaw) > 0.0001 then
		local part = math.min(1, dt * 28)
		local pitch, yaw = cameraKick * part, cameraKickYaw * part
		cameraKick -= pitch
		cameraKickYaw -= yaw
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CFrame = camera.CFrame * CFrame.Angles(pitch, yaw, 0)
		end
	end
	if triggerHeld then
		tryFire()
	end
	-- Прицел вместо стрелки мыши, пока в руках оружие
	local aiming = visible and shownKind ~= "" and shownKind ~= "Medkit" and not acting
	crosshair.Visible = aiming
	-- Стрелку мыши прячем, только пока она заперта в центре (список фраз и экран камер её освобождают)
	local hideMouse = aiming and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	if UserInputService.MouseIconEnabled == hideMouse then
		UserInputService.MouseIconEnabled = not hideMouse
	end
	if aiming then
		local gap = 6 + spread * 16 + (if shownKind == "Shotgun" then 10 else 0)
		ticks[1].Position = UDim2.new(0.5, -gap - 5, 0.5, 0)
		ticks[2].Position = UDim2.new(0.5, gap + 5, 0.5, 0)
		ticks[3].Position = UDim2.new(0.5, 0, 0.5, -gap - 5)
		ticks[4].Position = UDim2.new(0.5, 0, 0.5, gap + 5)
		centerDot.Visible = shownKind ~= "Shotgun"
	end
	refreshHud()
end

-- Сразу после камеры Roblox (и после своего вида охранника в Guards.client)
RunService:BindToRenderStep("Weapons", Enum.RenderPriority.Camera.Value + 2, step)

localPlayer.CharacterAdded:Connect(function()
	shownKind = ""
	clearView()
	triggerHeld = false
	bobSpeed = 0
	crouchBlend = 0
	leanBlend = 0
	healBlend = 0
	healWasActive = false
	holsterStarted = 0
	actionKind = ""
end)
