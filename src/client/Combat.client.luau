-- Бой на экране (блок 4): здоровье и броня, «ты лежишь», полоска подъёма, вспышка края экрана при попадании,
-- метка «REVIVE» над лежащими друзьями сквозь стены.
-- Всё только показывает: здоровье, урон и подъём считает сервер (HealthService), сюда приходят атрибуты и события.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors
local Settings = Config.Health

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()
local gui = Theme.screenGui("Combat", 2)

local function number(player: Player, attr: string): number
	return tonumber(player:GetAttribute(attr)) or 0
end

local function onShift(): boolean
	local phase = GameState.phase()
	return localPlayer:GetAttribute(PlayerAttr.InRound) == true and (phase == GameState.Phase.Day or phase == GameState.Phase.Night)
end

---------------------------------------------------------------- здоровье и броня

-- На компьютере — слева внизу; на телефоне там джойстик, поэтому слева сверху под лентой фраз
local healthPanel = Theme.new("Frame", {
	Name = "Health",
	AnchorPoint = if touchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if touchOnly then UDim2.new(0, 16, 0, 236) else UDim2.new(0, 16, 1, -16),
	Size = UDim2.new(0, 250, 0, 66),
	BackgroundColor3 = Colors.Navy,
	BackgroundTransparency = 0.2,
	Visible = false,
	Parent = gui,
}, { Theme.corner(12), Theme.stroke(Colors.Gold, 2), Theme.padding(8) })

local function bar(name: string, y: number, color: Color3): (Frame, Frame, TextLabel)
	local back = Theme.new("Frame", {
		Name = name,
		Position = UDim2.new(0, 0, y, 0),
		Size = UDim2.new(1, 0, 0.46, 0),
		BackgroundColor3 = Colors.Dark,
		Parent = healthPanel,
	}, { Theme.corner(8) })
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { Theme.corner(8) })
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.BodyFont,
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = back,
	})
	Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1.5, Parent = label })
	return back, fill, label
end

local armorBack, armorFill, armorLabel = bar("Armor", 0, Color3.fromHex("4A90E2"))
local _healthBack, healthFill, healthLabel = bar("HealthBar", 0.54, Colors.Green)

local function healthColor(fraction: number): Color3
	if fraction > 0.5 then
		return Colors.Green
	elseif fraction > 0.25 then
		return Color3.fromHex("F2C230")
	end
	return Colors.Red
end

local function refreshHealth()
	local maxHealth = math.max(1, number(localPlayer, PlayerAttr.MaxHealth))
	local health = math.clamp(number(localPlayer, PlayerAttr.Health), 0, maxHealth)
	local armor = number(localPlayer, PlayerAttr.Armor)
	local fraction = health / maxHealth
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthFill.BackgroundColor3 = healthColor(fraction)
	healthLabel.Text = ("HEALTH %d / %d"):format(math.ceil(health), maxHealth)
	armorBack.Visible = armor > 0
	armorFill.Size = UDim2.fromScale(math.clamp(armor / Config.Weapons.Vest.Armor, 0, 1), 1)
	armorLabel.Text = ("ARMOR %d"):format(math.ceil(armor))
end

---------------------------------------------------------------- «ты лежишь»

local downColor = Instance.new("ColorCorrectionEffect")
downColor.Name = "DownedView"
downColor.Saturation = 0
downColor.Enabled = false
downColor.Parent = Lighting

local downPanel = Theme.new("Frame", {
	Name = "Downed",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.new(0.5, 0, 0, 120),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, { Theme.new("UISizeConstraint", { MinSize = Vector2.new(320, 0), MaxSize = Vector2.new(700, 200) }) })
local downTitle = Theme.label({
	Size = UDim2.fromScale(1, 0.42),
	Text = "YOU ARE DOWN",
	TextColor3 = Colors.Red,
	MaxTextSize = 44,
	Parent = downPanel,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = downTitle })
local downHint = Theme.label({
	Position = UDim2.fromScale(0, 0.44),
	Size = UDim2.fromScale(1, 0.22),
	Font = Theme.BodyFont,
	MaxTextSize = 20,
	Text = if touchOnly
		then "Crawl to a teammate — they can revive you (hold the button 10 s)"
		else "Crawl to a teammate (WASD) — they can revive you (hold F for 10 s)",
	Parent = downPanel,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = downHint })
local reviveBack = Theme.new("Frame", {
	Name = "ReviveBar",
	Position = UDim2.fromScale(0.15, 0.74),
	Size = UDim2.fromScale(0.7, 0.2),
	BackgroundColor3 = Colors.Dark,
	Visible = false,
	Parent = downPanel,
}, { Theme.corner(10), Theme.stroke(Colors.Gold, 2) })
local reviveFill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Colors.Green, Parent = reviveBack }, { Theme.corner(10) })
local reviveLabel = Theme.label({ Size = UDim2.fromScale(1, 1), Font = Theme.BodyFont, MaxTextSize = 18, ZIndex = 2, Parent = reviveBack })

local downedNow = false

local function refreshDowned()
	local downed = localPlayer:GetAttribute(PlayerAttr.Downed) == true and onShift()
	if downed ~= downedNow then
		downedNow = downed
		downPanel.Visible = downed
		downColor.Enabled = true
		TweenService:Create(downColor, TweenInfo.new(0.5), {
			Saturation = if downed then -0.85 else 0,
			Contrast = if downed then 0.1 else 0,
			TintColor = if downed then Color3.fromRGB(255, 225, 225) else Color3.new(1, 1, 1),
		}):Play()
		-- Пока лежишь, кнопки у предметов (покупка, арест, пульт) не нужны: сервер всё равно не даст
		ProximityPromptService.Enabled = not downed
	end
	if not downed then
		return
	end
	local by = number(localPlayer, PlayerAttr.RevivedBy)
	local started = number(localPlayer, PlayerAttr.ReviveStartedAt)
	if by ~= 0 and started > 0 then
		local reviver = Players:GetPlayerByUserId(by)
		local fraction = math.clamp((Workspace:GetServerTimeNow() - started) / Settings.ReviveSeconds, 0, 1)
		reviveBack.Visible = true
		reviveFill.Size = UDim2.fromScale(fraction, 1)
		reviveLabel.Text = ("%s is reviving you…"):format(if reviver then reviver.DisplayName else "A teammate")
	else
		reviveBack.Visible = false
	end
end

---------------------------------------------------------------- вспышка края экрана при попадании

-- Без крови: тёплое свечение с той стороны, откуда прилетело
local EDGE_COLOR = Color3.fromHex("FF5A36")

local function edge(name: string, anchor: Vector2, position: UDim2, size: UDim2, rotation: number): Frame
	local frame = Theme.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundColor3 = EDGE_COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	Theme.new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Parent = frame,
	})
	return frame
end

local edges = {
	front = edge("HurtTop", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.22), 90),
	back = edge("HurtBottom", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.22), -90),
	left = edge("HurtLeft", Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.18, 1), 0),
	right = edge("HurtRight", Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.18, 1), 180),
}

local function flash(frame: Frame, strength: number)
	frame.BackgroundTransparency = 1 - strength
	TweenService:Create(frame, TweenInfo.new(Settings.HurtFlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

Remotes.get(Remotes.Names.Hurt).OnClientEvent:Connect(function(from, amount)
	local strength = math.clamp(0.35 + (tonumber(amount) or 0) / 40, 0.35, 0.85)
	local camera = Workspace.CurrentCamera
	if typeof(from) ~= "Vector3" or not camera then
		for _, frame in edges do
			flash(frame, strength * 0.6)
		end
		return
	end
	-- С какой стороны: угол между взглядом и направлением на источник (по полу)
	local look = camera.CFrame.LookVector
	local toSource = from - camera.CFrame.Position
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatTo = Vector3.new(toSource.X, 0, toSource.Z)
	if flatLook.Magnitude < 0.01 or flatTo.Magnitude < 0.01 then
		flash(edges.front, strength)
		return
	end
	flatLook, flatTo = flatLook.Unit, flatTo.Unit
	local forward = flatLook:Dot(flatTo)
	local side = flatLook:Cross(flatTo).Y -- > 0 — слева
	if forward > 0.5 then
		flash(edges.front, strength)
	elseif forward < -0.5 then
		flash(edges.back, strength)
	elseif side > 0 then
		flash(edges.left, strength)
	else
		flash(edges.right, strength)
	end
end)

-- Аптечка подействовала — весь край экрана мягко зеленеет; броню пробили — полоска брони мигает
local lastHealth = number(localPlayer, PlayerAttr.Health)
localPlayer:GetAttributeChangedSignal(PlayerAttr.Health):Connect(function()
	local health = number(localPlayer, PlayerAttr.Health)
	if health > lastHealth and onShift() and localPlayer:GetAttribute(PlayerAttr.Downed) ~= true and lastHealth > 0 then
		for _, frame in edges do
			frame.BackgroundColor3 = Config.Weapons.Medkit.Color
			flash(frame, 0.45)
			task.delay(Settings.HurtFlashSeconds, function()
				frame.BackgroundColor3 = EDGE_COLOR
			end)
		end
	end
	lastHealth = health
end)

local lastArmor = number(localPlayer, PlayerAttr.Armor)
localPlayer:GetAttributeChangedSignal(PlayerAttr.Armor):Connect(function()
	local armor = number(localPlayer, PlayerAttr.Armor)
	if armor < lastArmor then
		armorFill.BackgroundColor3 = Colors.White
		TweenService:Create(armorFill, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromHex("4A90E2") }):Play()
	end
	lastArmor = armor
end)

---------------------------------------------------------------- чужие выстрелы

-- Конец ствола у оружия в руках стрелка (охранника или грабителя): модель Gear.Held, деталь Root, точка Muzzle.
local function muzzleOf(shooter: Instance): CFrame?
	local model = if shooter:IsA("Player") then shooter.Character else shooter
	local gear = model and model:FindFirstChild("Gear")
	local held = gear and gear:FindFirstChild("Held")
	local root = held and held:FindFirstChild("Root")
	local muzzle = root and root:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldCFrame
	end
	return nil
end

-- Свой выстрел уже нарисован сразу (Weapons.client); здесь — выстрелы других охранников и грабителей
Remotes.get(Remotes.Names.ShotFx).OnClientEvent:Connect(function(shooter, weapon, origin, ends, hits)
	if shooter == localPlayer or typeof(shooter) ~= "Instance" or typeof(weapon) ~= "string" or typeof(ends) ~= "table" then
		return
	end
	local muzzle = muzzleOf(shooter)
	local from = if muzzle then muzzle.Position elseif typeof(origin) == "Vector3" then origin else nil
	if not from then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - from).Magnitude > 260 then
		return -- далеко: не видно и не слышно
	end
	for index, point in ends do
		if typeof(point) == "Vector3" then
			local onTarget = typeof(hits) == "table" and hits[index] == true
			if weapon == "Taser" then
				Fx.wire(from, point)
			else
				Fx.tracer(from, point)
				Fx.impact(point, onTarget)
			end
		end
	end
	if muzzle and weapon ~= "Taser" then
		Fx.muzzleFlash(muzzle, if weapon == "Shotgun" then 1.4 else 1)
	end
	Fx.shotSound(weapon, from)
end)

---------------------------------------------------------------- метки «REVIVE» над лежащими друзьями

local markers: { [Player]: BillboardGui } = {}

local function setMarker(player: Player, show: boolean)
	local marker = markers[player]
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if show and head and head:IsA("BasePart") then
		if marker and marker.Adornee == head then
			return
		end
		if marker then
			marker:Destroy()
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ReviveMarker_" .. player.Name
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(120, 46)
		billboard.StudsOffset = Vector3.new(0, 1.5, 0)
		billboard.MaxDistance = Settings.MarkerMaxDistance
		local label = Theme.label({ Size = UDim2.fromScale(1, 0.6), Text = "✚ REVIVE", TextColor3 = Colors.Green, MaxTextSize = 24, Parent = billboard })
		Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = label })
		local name = Theme.label({ Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4), Font = Theme.BodyFont, Text = player.DisplayName, MaxTextSize = 14, Parent = billboard })
		Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 1.5, Parent = name })
		billboard.Parent = gui
		markers[player] = billboard
	elseif marker then
		marker:Destroy()
		markers[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	setMarker(player, false)
end)

---------------------------------------------------------------- налёт: POLICE: 60

local policeFrame = Theme.new("Frame", {
	Name = "Police",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.new(0, 360, 0, 62),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.25,
	Visible = false,
	Parent = gui,
}, { Theme.corner(12), Theme.padding(4) })
local policeStroke = Theme.stroke(Colors.Red, 3)
policeStroke.Parent = policeFrame
local policeLabel = Theme.label({ Size = UDim2.fromScale(1, 0.62), MaxTextSize = 34, Parent = policeFrame })
local policeHint = Theme.label({
	Position = UDim2.fromScale(0, 0.62),
	Size = UDim2.fromScale(1, 0.38),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 15,
	Parent = policeFrame,
})

local function hasGun(): boolean
	return GameState.hasWeapon(localPlayer, "Pistol") or (localPlayer:GetAttribute(PlayerAttr.Primary) or "") ~= ""
end

local function refreshPolice()
	local raid = GameState.get(GameState.Attr.Raid) == true and onShift()
	policeFrame.Visible = raid
	if not raid then
		return
	end
	-- Мигалка: текст и рамка красный ↔ синий
	local blue = math.floor(os.clock() * 3) % 2 == 0
	local color = if blue then Color3.fromHex("4A8BFF") else Colors.Red
	policeStroke.Color = color
	if GameState.get(GameState.Attr.PoliceArrived) == true then
		policeLabel.Text = "🚨 POLICE ARRIVED"
		policeLabel.TextColor3 = color
		policeHint.Text = if touchOnly then "The robbers give up — arrest them for $5!" else "The robbers give up — hold F to arrest them for $5!"
		return
	end
	local left = math.max(0, (tonumber(GameState.get(GameState.Attr.PoliceAt)) or 0) - Workspace:GetServerTimeNow())
	policeLabel.Text = ("🚨 POLICE: %d"):format(math.ceil(left))
	policeLabel.TextColor3 = color
	if hasGun() then
		policeHint.Text = if touchOnly then "Draw your gun and take cover!" else "Draw your gun (1 / 2), take cover (C, Q / E)!"
	else
		policeHint.Text = "No gun? Stay in cover, use the taser, protect the Mona Lisa!"
	end
end

---------------------------------------------------------------- кадр

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	refreshDowned()
	refreshPolice()
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	local shift = onShift()
	healthPanel.Visible = shift
	if healthPanel.Visible then
		refreshHealth()
	end
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			setMarker(player, shift and player:GetAttribute(PlayerAttr.Downed) == true and player:GetAttribute(PlayerAttr.InRound) == true)
		end
	end
end)
