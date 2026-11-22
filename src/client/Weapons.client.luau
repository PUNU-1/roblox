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
local Fx = require(script.Parent:WaitForChild("Fx"))

local PlayerAttr = GameState.PlayerAttr
local Weapons = Config.Weapons
local Keys = Config.Keys
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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

local function knocked(): boolean
	return number(PlayerAttr.KnockedUntil) > now()
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
	groups: { string? }, -- у каждой детали: Mag / Slide / Pump или nil
}

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
	for index, part in built.parts do
		part.Anchored = true
		part.CastShadow = false
		local name = part.Name
		groups[index] = if name == "Mag" or name == "Slide" or name == "Pump" then name else nil
	end
	built.root.Anchored = true
	built.model.Parent = container
	view = { kind = kind, built = built, groups = groups }
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
		taserReadyLocal = now() + info.Cooldown
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
	nextShotAt = now() + info.Interval
	fireRemote:FireServer(kind, origin, direction)
end

local function requestReload()
	local kind = equipped()
	if FIREARMS[kind] and not reloading() and predictedAmmo(kind) < (Weapons :: any)[kind].MagSize and reserveOf(kind) > 0 then
		reloadRemote:FireServer()
	end
end

-- Можно ли сейчас выстрелить (сервер всё равно проверит сам).
local function tryFire()
	local kind = equipped()
	if kind == "Medkit" then
		medkitRemote:FireServer()
		triggerHeld = false
		return
	end
	local info = (Weapons :: any)[kind]
	if not info or kind ~= shownKind or not onShift() or downed() or viewing() or knocked() then
		return
	end
	if GameState.phase() ~= GameState.Phase.Night then
		return
	end
	if now() < equipStarted + Weapons.EquipSeconds or now() < nextShotAt then
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
	if not raidActive() or reloading() then
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

local hotbar = Theme.new("Frame", {
	Name = "Hotbar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -66),
	Size = UDim2.new(0, 4 * 92 + 3 * 8, 0, 74),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
Theme.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = hotbar,
})

type Slot = { button: TextButton, name: TextLabel, info: TextLabel, cooldown: Frame, stroke: UIStroke }
local slots: { Slot } = {}

for index = 1, 4 do
	local button = Theme.new("TextButton", {
		Name = "Slot" .. index,
		LayoutOrder = index,
		Size = UDim2.new(0, 92, 1, 0),
		BackgroundColor3 = Colors.Navy,
		BackgroundTransparency = 0.2,
		AutoButtonColor = true,
		Text = "",
		Parent = hotbar,
	}, { Theme.corner(10) })
	local stroke = Theme.stroke(Colors.Gray, 2)
	stroke.Parent = button
	local cooldown = Theme.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
		Parent = button,
	}, { Theme.corner(10) })
	if not touchOnly then
		Theme.label({ Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(18, 18), Text = tostring(index), TextColor3 = Colors.Gold, MaxTextSize = 16, ZIndex = 3, Parent = button })
	end
	local name = Theme.label({ Position = UDim2.fromScale(0.05, 0.22), Size = UDim2.fromScale(0.9, 0.36), MaxTextSize = 18, ZIndex = 3, Parent = button })
	local infoLabel = Theme.label({ Position = UDim2.fromScale(0.05, 0.6), Size = UDim2.fromScale(0.9, 0.3), Font = Theme.BodyFont, TextColor3 = Colors.Marble, MaxTextSize = 14, ZIndex = 3, Parent = button })
	button.Activated:Connect(function()
		equipRemote:FireServer(index)
	end)
	slots[index] = { button = button, name = name, info = infoLabel, cooldown = cooldown, stroke = stroke }
end

local toast = Theme.label({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -146),
	Size = UDim2.new(0, 420, 0, 28),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gold,
	MaxTextSize = 20,
	Visible = false,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = toast })

local ammoPanel = Theme.new("Frame", {
	Name = "Ammo",
	AnchorPoint = Vector2.new(1, 1),
	Position = if touchOnly then UDim2.new(0.5, 4 * 50 + 30, 1, -70) else UDim2.new(1, -20, 1, -20),
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

local function showToast(text: string)
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

local function refreshHud()
	local shift = onShift()
	local any = false
	local current = equipped()
	for index, slot in slots do
		local weapon = slotWeapon(index)
		any = any or weapon ~= nil
		local selected = weapon ~= nil and weapon == current
		slot.stroke.Color = if selected then Colors.Gold else Colors.Gray
		slot.stroke.Thickness = if selected then 3 else 2
		slot.button.BackgroundTransparency = if weapon then 0.15 else 0.55
		slot.cooldown.Size = UDim2.fromScale(1, 0)
		if not weapon then
			slot.name.Text = SLOT_TITLES[index]
			slot.name.TextColor3 = Colors.Gray
			slot.info.Text = "—"
		else
			slot.name.TextColor3 = Colors.White
			local info = (Weapons :: any)[weapon]
			slot.name.Text = if info and info.Title then info.Title else string.upper(weapon)
			if FIREARMS[weapon] then
				slot.info.Text = if raidActive() then ("%d | %d"):format(predictedAmmo(weapon), reserveOf(weapon)) else "🔒 raid only"
			elseif weapon == "Taser" then
				local left = math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt)) - now()
				if left > 0 then
					slot.info.Text = ("%ds"):format(math.ceil(left))
					slot.cooldown.Size = UDim2.fromScale(1, math.clamp(left / Weapons.Taser.Cooldown, 0, 1))
				else
					slot.info.Text = "READY"
				end
			else
				slot.info.Text = ("× %d"):format(number(PlayerAttr.Medkits))
			end
		end
	end
	hotbar.Visible = shift and any and not viewing()
	local showAmmo = shift and FIREARMS[current] == true and not viewing() and not downed()
	ammoPanel.Visible = showAmmo
	if showAmmo then
		local info = (Weapons :: any)[current]
		ammoTitle.Text = if reloading() then "RELOADING…" else info.Title
		ammoBig.Text = tostring(predictedAmmo(current))
		ammoBig.TextColor3 = if predictedAmmo(current) == 0 then Colors.Red else Colors.White
		ammoSmall.Text = "/ " .. tostring(reserveOf(current))
	end
	if toast.Visible and os.clock() > holsterWarnUntil then
		toast.Visible = false
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
	if FIREARMS[weapon] and not raidActive() and equipped() ~= weapon then
		showToast("Firearms stay holstered — only during a raid!")
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

-- Клавиши оружия работают только на смене (в лобби 1 / 2 — выбор роли)
local function setBound(shift: boolean, holding: boolean)
	if shift ~= bound then
		bound = shift
		if shift then
			ContextActionService:BindAction(SLOT_ACTION, onSlotAction, false, table.unpack(Keys.Slots))
			ContextActionService:BindAction(RELOAD_ACTION, onReloadAction, touchOnly, Keys.Reload)
			ContextActionService:BindAction(CROUCH_ACTION, onCrouchAction, touchOnly, Keys.Crouch, Enum.KeyCode.ButtonB)
			ContextActionService:BindAction(LEAN_LEFT_ACTION, onLeanAction, touchOnly, Keys.LeanLeft, Enum.KeyCode.ButtonL1)
			ContextActionService:BindAction(LEAN_RIGHT_ACTION, onLeanAction, touchOnly, Keys.LeanRight, Enum.KeyCode.ButtonR1)
			if touchOnly then
				ContextActionService:SetTitle(RELOAD_ACTION, "Reload")
				ContextActionService:SetPosition(RELOAD_ACTION, UDim2.new(1, -180, 1, -250))
				ContextActionService:SetTitle(CROUCH_ACTION, "Crouch")
				ContextActionService:SetPosition(CROUCH_ACTION, UDim2.new(1, -250, 1, -170))
				ContextActionService:SetTitle(LEAN_LEFT_ACTION, "◀ Lean")
				ContextActionService:SetPosition(LEAN_LEFT_ACTION, UDim2.new(1, -340, 1, -250))
				ContextActionService:SetTitle(LEAN_RIGHT_ACTION, "Lean ▶")
				ContextActionService:SetPosition(LEAN_RIGHT_ACTION, UDim2.new(1, -260, 1, -250))
			end
		else
			ContextActionService:UnbindAction(SLOT_ACTION)
			ContextActionService:UnbindAction(RELOAD_ACTION)
			ContextActionService:UnbindAction(CROUCH_ACTION)
			ContextActionService:UnbindAction(LEAN_LEFT_ACTION)
			ContextActionService:UnbindAction(LEAN_RIGHT_ACTION)
			wantCrouch, leanLeftHeld, leanRightHeld = false, false, false
			sentCrouch, sentLean = false, 0
		end
	end
	-- На телефоне — большая кнопка «огонь», пока в руках оружие или аптечка (на геймпаде — правый курок)
	local wantFire = shift and holding
	if wantFire ~= fireBound then
		fireBound = wantFire
		if wantFire then
			ContextActionService:BindAction(FIRE_ACTION, onFireAction, touchOnly, Enum.KeyCode.ButtonR2)
			if touchOnly then
				ContextActionService:SetTitle(FIRE_ACTION, "FIRE")
				ContextActionService:SetPosition(FIRE_ACTION, UDim2.new(1, -100, 1, -250))
			end
		else
			ContextActionService:UnbindAction(FIRE_ACTION)
			triggerHeld = false
		end
	end
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
type Motion = { root: CFrame, mag: CFrame, slide: CFrame, pump: CFrame, left: CFrame, hideMag: boolean }

local function reloadMotion(kind: string, p: number): Motion
	local motion: Motion = { root = CFrame.identity, mag = CFrame.identity, slide = CFrame.identity, pump = CFrame.identity, left = CFrame.identity, hideMag = false }
	if kind == "Shotgun" then
		-- Наклон влево и патроны по одному: левая рука ныряет вниз за патроном и толкает его в окно снизу
		local tilt = smooth(p / 0.12) * (1 - smooth((p - 0.88) / 0.12))
		motion.root = CFrame.new(-0.08 * tilt, 0.1 * tilt, 0) * CFrame.Angles(0.12 * tilt, 0, 0.45 * tilt)
		local cycle = math.clamp((p - 0.12) / 0.7, 0, 1) * 4
		local inCycle = cycle % 1
		local dip = if p > 0.12 and p < 0.82 then math.sin(inCycle * math.pi) else 0
		motion.left = CFrame.new(0.12 * tilt, -0.55 * dip, 0.9 * tilt)
		-- В конце — передёрнуть помпу
		motion.pump = CFrame.new(0, 0, 0.35 * bump(p, 0.84, 0.98))
		return motion
	end
	-- Пистолет и автомат: наклон, магазин выпадает, новый вставляется снизу, затвор
	local tilt = smooth(p / 0.15) * (1 - smooth((p - 0.85) / 0.15))
	motion.root = CFrame.new(-0.05 * tilt, 0.08 * tilt, 0) * CFrame.Angles(0.2 * tilt, 0.1 * tilt, 0.35 * tilt)
	if p < 0.18 then
		motion.mag = CFrame.identity
	elseif p < 0.4 then
		local k = (p - 0.18) / 0.22
		motion.mag = CFrame.new(0, -2.2 * k * k, 0.1 * k)
		motion.hideMag = k > 0.85
	elseif p < 0.55 then
		motion.hideMag = true
		motion.mag = CFrame.new(0, -2, 0)
	elseif p < 0.75 then
		local k = smooth((p - 0.55) / 0.2)
		motion.mag = CFrame.new(0, -1.1 * (1 - k), 0)
	end
	-- Левая рука уходит вниз за новым магазином, приносит его и бьёт снизу
	local reach = bump(p, 0.3, 0.78)
	motion.left = CFrame.new(0, -0.9 * reach, 0.25 * reach)
	-- Затвор (пистолет) / рукоять затвора (автомат) — в конце
	motion.slide = CFrame.new(0, 0, 0.26 * bump(p, 0.8, 0.95))
	return motion
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

	-- Покачивание: от поворота камеры оружие чуть отстаёт, при ходьбе — шаг
	local look = cf.LookVector
	if lastLook then
		local delta = cf:VectorToObjectSpace(lastLook)
		swayX = math.clamp(swayX + delta.X * 0.6, -0.15, 0.15)
		swayY = math.clamp(swayY + delta.Y * 0.6, -0.15, 0.15)
	end
	lastLook = look
	local decay = math.exp(-dt * 10)
	swayX *= decay
	swayY *= decay
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed = if root and root:IsA("BasePart") then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	bobPhase += dt * (4 + speed * 0.45)
	local walk = math.clamp(speed / Config.Players.WalkSpeed, 0, 1)
	local bob = CFrame.new(math.sin(bobPhase) * 0.035 * walk, -math.abs(math.cos(bobPhase)) * 0.03 * walk, 0)
	local sway = CFrame.new(swayX, swayY, 0) * CFrame.Angles(swayY * 0.6, swayX * 0.6, swayX * 0.8)

	-- Отдача: назад и вверх, быстро возвращается
	recoilKick *= math.exp(-dt * 12)
	spread *= math.exp(-dt * 6)
	local kick = CFrame.new(0, 0.03 * recoilKick, 0.22 * recoilKick) * CFrame.Angles(0.16 * recoilKick, 0, 0)

	-- Достать: поднимается снизу
	local equipT = smooth((time - equipStarted) / Weapons.EquipSeconds)
	local raise = CFrame.new(0, -0.9 * (1 - equipT), 0.2 * (1 - equipT)) * CFrame.Angles(-0.7 * (1 - equipT), 0, 0)

	-- Присел — оружие чуть ниже; наклон — чуть повёрнуто
	local lean = number(PlayerAttr.Lean)
	local stance = CFrame.Angles(0, 0, lean * 0.08)

	local downedNow = downed()
	local reviving = number(PlayerAttr.ReviveTarget) ~= 0
	local up = cf.UpVector

	if downedNow then
		-- Лежит без сил: руки внизу экрана по очереди тянутся вперёд и подтягивают тело
		local s = math.sin(bobPhase * 0.8)
		local move = math.clamp(speed / Config.Health.CrawlSpeed, 0, 1)
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

	if not current then
		setArmVisible(leftArm, false)
		setArmVisible(rightArm, false)
		return
	end

	-- Перезарядка и выстрел двигают части оружия и левую руку
	local motion: Motion = { root = CFrame.identity, mag = CFrame.identity, slide = CFrame.identity, pump = CFrame.identity, left = CFrame.identity, hideMag = false }
	local reloadUntil = number(PlayerAttr.ReloadUntil)
	local info = (Weapons :: any)[kind]
	if FIREARMS[kind] and reloadUntil > time then
		motion = reloadMotion(kind, 1 - (reloadUntil - time) / info.ReloadSeconds)
	end
	if lastShotKind == kind then
		local slide, pump = shotMotion(kind, time - lastShotAt)
		motion.slide = motion.slide * slide
		motion.pump = motion.pump * pump
	end
	-- Аптечка: подносит к груди и нажимает, в конце — зелёный «+»
	local healUntil = number(PlayerAttr.HealUntil)
	local healMotion = CFrame.identity
	if kind == "Medkit" and healUntil > time then
		local p = 1 - (healUntil - time) / Weapons.Medkit.UseSeconds
		local k = smooth(p / 0.3)
		healMotion = CFrame.new(0, 0.15 * k - 0.05 * math.abs(math.sin(p * 18)) * k, 0.45 * k) * CFrame.Angles(-0.35 * k, 0, 0)
	end
	-- Шокер на перезарядке: экран красный
	local base = cf * HOLD[kind] * stance * sway * bob * raise * kick * motion.root * healMotion
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
		else
			part.CFrame = base * offset
		end
		if kind == "Taser" and part.Name == "Screen" then
			local ready = time >= math.max(taserReadyLocal, number(PlayerAttr.TaserReadyAt))
			part.Color = if ready then Color3.fromHex("3BC6C1") else Colors.Red
		end
	end
	-- Руки: правая держит рукоять, левая — цевьё, помпу, низ рукояти или аптечку
	setArmVisible(rightArm, true)
	setArmVisible(leftArm, true)
	if kind == "Medkit" then
		placeArm(rightArm, (base * CFrame.new(0.62, -0.5, 0)).Position, cf:VectorToWorldSpace(RIGHT_ARM_DIR), up, 1)
		placeArm(leftArm, (base * CFrame.new(-0.62, -0.5, 0)).Position, cf:VectorToWorldSpace(LEFT_ARM_DIR), up, -1)
		return
	end
	placeArm(rightArm, (base * CFrame.new(0.02, -0.08, 0.06)).Position, cf:VectorToWorldSpace(RIGHT_ARM_DIR), up, 1)
	local support = built.support
	if kind == "Shotgun" then
		support = motion.pump * support
	end
	local leftHand = base * support * motion.left
	placeArm(leftArm, leftHand.Position, cf:VectorToWorldSpace(LEFT_ARM_DIR), up, -1)
end

---------------------------------------------------------------- кадр

local function syncView()
	local kind = equipped()
	local show = onShift() and not viewing() and not downed() and kind ~= ""
	local wanted = if show then kind else ""
	if wanted ~= shownKind then
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
	local visible = shift and not viewing() and (shownKind ~= "" or downed() or number(PlayerAttr.ReviveTarget) ~= 0)
	if visible then
		if container.Parent ~= camera then
			container.Parent = camera
		end
		placeView(dt, camera)
	elseif container.Parent then
		container.Parent = nil
	end
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
	local aiming = visible and shownKind ~= "" and shownKind ~= "Medkit"
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
end)
