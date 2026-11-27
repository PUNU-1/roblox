-- Камеры наблюдения на сервере (блок 2):
--  • Покупка: на карте 12 мест для камер (кронштейн и табличка CAMERA SPOT). Первая камера — на
--    Мону Лизу — работает сразу и бесплатно, остальные днём покупаются удержанием F у таблички
--    (целиком или вскладчину, Purchase.luau). Купленная камера остаётся до конца забега.
--  • Поломка: вор-взломщик ломает купленную камеру (атрибут Broken — клиенты показывают «NO SIGNAL»),
--    игрок перезапускает все камеры рубильником CAMERA RESET справа от пульта на балконе (держать F).
--    Пока есть сломанные камеры, лампа на рубильнике горит красным.
--  • Ремонт одной камеры (этап 5, блок E): на табличке CAMERA SPOT под сломанной камерой — кнопка F «Repair camera»
--    (держать RepairHoldSeconds, у техника сразу); чинится только эта камера. Сервер проверяет, что камера сломана,
--    игрок может действовать (RoleService.canAct) и стоит рядом.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local Purchase = require(Server:WaitForChild("Purchase"))
local ShopService = require(Server:WaitForChild("ShopService"))
local ProgressService = require(Server:WaitForChild("ProgressService"))

local Attr = GameState.CameraAttr
local Cameras = Config.Cameras

local CameraService = {}

type Camera = {
	index: number,
	point: BasePart, -- точка обзора (Map.CameraPoints.CameraN)
	plaque: BasePart?, -- табличка CAMERA SPOT: на ней кнопка покупки
	label: TextLabel?,
	prompt: ProximityPrompt?,
	fixPrompt: ProximityPrompt?, -- «Repair camera» на табличке, пока камера сломана
	model: PVInstance?, -- купленная камера на кронштейне
	paid: number,
	free: boolean,
}

local cameras: { Camera } = {}
local points: { BasePart } = {}
local repairPrompt: ProximityPrompt? = nil
local repairLamp: BasePart? = nil
local installedFolder: Folder
local dayActive = false

-- Камера на конце кронштейна (R3), смотрит вперёд (−Z): шарнир с вилкой, двухцветный корпус со скосами,
-- козырёк со щёчками, кабель, ступенчатый объектив со стеклом, ИК-диодами и красным индикатором.
local function buildCameraStub(): { ModelLibrary.StubPart }
	local hex = Color3.fromHex
	local dark = hex("242936")
	local shell = hex("F2EEE6")
	local navy = hex("1E2A44")
	local metal = hex("8A93A6")
	local list: { ModelLibrary.StubPart } = {
		{ name = "Swivel", size = Vector3.new(0.7, 0.7, 0.7), offset = CFrame.identity, color = dark, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "SwivelCollar", size = Vector3.new(0.2, 0.56, 0.56), offset = CFrame.new(0, 0, 0.24) * CFrame.Angles(0, math.rad(90), 0), color = metal, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "ForkBase", size = Vector3.new(1.06, 0.22, 0.24), offset = CFrame.new(0, -0.38, -0.15), color = dark, material = Enum.Material.Metal },
		{ name = "ForkL", size = Vector3.new(0.14, 0.5, 0.24), offset = CFrame.new(-0.46, -0.15, -0.15), color = dark, material = Enum.Material.Metal },
		{ name = "ForkR", size = Vector3.new(0.14, 0.5, 0.24), offset = CFrame.new(0.46, -0.15, -0.15), color = dark, material = Enum.Material.Metal },
		{ name = "Body", size = Vector3.new(1.16, 0.78, 1.9), offset = CFrame.new(0, 0.04, -1.06), color = shell },
		{ name = "BodyLower", size = Vector3.new(1.08, 0.24, 1.82), offset = CFrame.new(0, -0.42, -1.06), color = navy, material = Enum.Material.Metal },
		{ name = "BodyBevelL", size = Vector3.new(1.86, 0.16, 0.16), offset = CFrame.new(-0.5, 0.5, -1.06) * CFrame.Angles(0, math.rad(90), 0), color = shell, wedge = true },
		{ name = "BodyBevelR", size = Vector3.new(1.86, 0.16, 0.16), offset = CFrame.new(0.5, 0.5, -1.06) * CFrame.Angles(0, math.rad(-90), 0), color = shell, wedge = true },
		{ name = "BodyTop", size = Vector3.new(0.84, 0.16, 1.86), offset = CFrame.new(0, 0.5, -1.06), color = shell },
		{ name = "Hood", size = Vector3.new(1.38, 0.12, 2.34), offset = CFrame.new(0, 0.62, -1.2), color = dark, material = Enum.Material.Metal },
		{ name = "HoodCheekL", size = Vector3.new(0.08, 0.36, 0.5), offset = CFrame.new(-0.65, 0.44, -2.08), color = dark, material = Enum.Material.Metal, wedge = true },
		{ name = "HoodCheekR", size = Vector3.new(0.08, 0.36, 0.5), offset = CFrame.new(0.65, 0.44, -2.08), color = dark, material = Enum.Material.Metal, wedge = true },
		{ name = "Cable", size = Vector3.new(0.14, 0.14, 0.75), offset = CFrame.new(0.28, -0.22, -0.25) * CFrame.Angles(math.rad(-22), math.rad(18), 0), color = hex("15181F"), material = Enum.Material.Rubber, shape = Enum.PartType.Cylinder },
		{ name = "LensRing", size = Vector3.new(0.24, 0.86, 0.86), offset = CFrame.new(0, 0.02, -2.06) * CFrame.Angles(0, math.rad(90), 0), color = metal, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Lens", size = Vector3.new(0.32, 0.7, 0.7), offset = CFrame.new(0, 0.02, -2.14) * CFrame.Angles(0, math.rad(90), 0), color = hex("15181F"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Glass", size = Vector3.new(0.06, 0.54, 0.54), offset = CFrame.new(0, 0.02, -2.31) * CFrame.Angles(0, math.rad(90), 0), color = hex("3BC6C1"), material = Enum.Material.Glass, transparency = 0.52, shape = Enum.PartType.Cylinder },
		{ name = "LedBezel", size = Vector3.new(0.06, 0.24, 0.24), offset = CFrame.new(0.42, 0.3, -2.03) * CFrame.Angles(0, math.rad(90), 0), color = hex("15181F"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Led", size = Vector3.new(0.16, 0.16, 0.16), offset = CFrame.new(0.42, 0.3, -2.07), color = hex("FF3B3B"), material = Enum.Material.Neon, shape = Enum.PartType.Ball },
	}
	for _, x in { -0.59, 0.59 } do
		table.insert(list, { name = "Vent", size = Vector3.new(0.04, 0.24, 0.7), offset = CFrame.new(x, 0.04, -0.75), color = navy })
	end
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		table.insert(list, { name = "IRLed", size = Vector3.new(0.08, 0.08, 0.08), offset = CFrame.new(math.cos(a) * 0.28, 0.02 + math.sin(a) * 0.28, -2.28), color = hex("FF6B6B"), material = Enum.Material.Neon, shape = Enum.PartType.Ball })
	end
	return list
end
local CAMERA_STUB: { ModelLibrary.StubPart } = buildCameraStub()

---------------------------------------------------------------- покупка

local function isOwned(point: BasePart): boolean
	return point:GetAttribute(Attr.Owned) == true
end

local function refreshCamera(camera: Camera)
	local owned = isOwned(camera.point)
	local broken = owned and camera.point:GetAttribute(Attr.Broken) == true
	if camera.fixPrompt then
		camera.fixPrompt.Enabled = broken
	end
	if camera.prompt then
		camera.prompt.Enabled = dayActive and not owned and GameState.isHallOpen(camera.point:GetAttribute(Attr.Hall))
		camera.prompt.ObjectText = Purchase.progressText(("Camera %d"):format(camera.index), camera.paid, Cameras.Price)
		Purchase.setProgress(camera.prompt, camera.paid, Cameras.Price)
	end
	if camera.label then
		camera.label.Text = if broken
			then ("CAM %d\nNO SIGNAL"):format(camera.index)
			elseif owned then ("CAM %d"):format(camera.index)
			elseif camera.paid > 0 then ("CAMERA SPOT\n$%d / $%d"):format(camera.paid, Cameras.Price)
			else ("CAMERA SPOT\nCAM %d"):format(camera.index)
		camera.label.TextColor3 = if broken then Cameras.PlaqueBrokenColor elseif owned then Cameras.PlaqueOwnedColor else Cameras.PlaqueColor
	end
end

-- Камера появляется на кронштейне: выезжает из шарнира вперёд.
local function installModel(camera: Camera, animate: boolean)
	if camera.model then
		camera.model:Destroy()
	end
	local mount = camera.point.CFrame * CFrame.new(0, 0, 3.5) -- точка обзора на 3.5 впереди шарнира
	local model = ModelLibrary.place(MapSchema.Models.Camera, mount, CAMERA_STUB, installedFolder)
	model.Name = "Camera" .. camera.index
	ModelLibrary.forEachPart(model, function(part)
		part.CanCollide = false
		part.CanQuery = false -- не загораживает вид другим камерам
	end)
	camera.model = model
	if animate then
		local progress = Instance.new("NumberValue")
		local start = mount * CFrame.new(0, 0, 1.2)
		model:PivotTo(start)
		progress.Changed:Connect(function(value)
			if model.Parent then
				model:PivotTo(start:Lerp(mount, value))
			end
		end)
		local tween = TweenService:Create(progress, TweenInfo.new(Cameras.InstallSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
		tween.Completed:Once(function()
			progress:Destroy()
		end)
		tween:Play()
	end
end

local function own(camera: Camera, animate: boolean)
	camera.point:SetAttribute(Attr.Owned, true)
	camera.point:SetAttribute(Attr.Broken, false)
	installModel(camera, animate)
	refreshCamera(camera)
end

-- Удержание F у таблички (или покупка из окна магазина — fromShop, без проверки расстояния): остаток цены,
-- если хватает денег, иначе всё, что есть (Purchase.take). Возвращает, сколько взяли.
local function contribute(camera: Camera, player: Player, fromShop: boolean?): number
	local plaque = camera.plaque
	if not dayActive or not plaque or isOwned(camera.point) or not GameState.isHallOpen(camera.point:GetAttribute(Attr.Hall)) then
		return 0
	end
	local amount = Purchase.take(player, plaque, camera.paid, Cameras.Price, fromShop)
	if amount <= 0 then
		return 0
	end
	camera.paid += amount
	if camera.paid >= Cameras.Price then
		ProgressService.teamBought(Purchase.backers(plaque), "Camera")
		own(camera, true)
		Remotes.get(Remotes.Names.Banner):FireAllClients(("CAMERA %d INSTALLED"):format(camera.index), "info")
	else
		refreshCamera(camera)
	end
	return amount
end

local function refreshAll()
	for _, camera in cameras do
		refreshCamera(camera)
	end
end

---------------------------------------------------------------- поломка и перезапуск

local function anyBroken(): boolean
	for _, point in points do
		if point:GetAttribute(Attr.Broken) == true then
			return true
		end
	end
	return false
end

local function refreshRepair()
	local broken = anyBroken()
	if repairPrompt then
		repairPrompt.Enabled = broken
	end
	if repairLamp then
		repairLamp.Color = if broken then Cameras.ResetLampOnColor else Cameras.ResetLampOffColor
	end
	refreshAll() -- кнопки «Repair camera» и надписи на табличках
end

-- Деталь-украшение, приваренная к месту (без столкновений): болты, ручки, полоски (этап 5, блок F2).
local function trimPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Рубильник справа от пульта (если смотреть на пульт с юга, с балкона).
local function buildResetSwitch(console: BasePart): BasePart
	local size = Cameras.ResetSwitchSize
	local switch = Instance.new("Part")
	switch.Name = "CameraResetSwitch"
	switch.Anchored = true
	switch.Size = size
	switch.Color = Cameras.ResetSwitchColor
	switch.Material = Enum.Material.Metal
	switch.CFrame = console.CFrame * CFrame.new(console.Size.X / 2 + Cameras.ResetSwitchGap + size.X / 2, -console.Size.Y / 2 + size.Y / 2, 0)
	switch.Parent = console.Parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- на юг, к игроку
	gui.LightInfluence = 0
	gui.PixelsPerStud = 50
	gui.Parent = switch
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, 0.45)
	label.Size = UDim2.fromScale(0.9, 0.3)
	label.Text = "CAMERA\nRESET"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("FFFFFF")
	label.Parent = gui

	local lamp = Instance.new("Part")
	lamp.Name = "ResetLamp"
	lamp.Shape = Enum.PartType.Ball
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanTouch = false
	lamp.CastShadow = false
	lamp.Material = Enum.Material.Neon
	lamp.Color = Cameras.ResetLampOffColor
	lamp.Size = Vector3.new(0.7, 0.7, 0.7)
	lamp.CFrame = switch.CFrame * CFrame.new(0, size.Y / 2 - 0.6, size.Z / 2)
	lamp.Parent = switch
	repairLamp = lamp

	-- Этап 5, блок F2: рычаг с красной ручкой сбоку, жёлто-чёрная полоса внизу, болты, кабель в пол.
	-- Лицо рубильника — сторона +Z (к игроку на балконе).
	local dark = Color3.fromHex("1C1F26")
	local steel = Color3.fromHex("9AA6BC")
	local frame = switch.CFrame
	trimPart(switch, "LeverHub", Vector3.new(0.3, 0.5, 0.5), frame * CFrame.new(size.X / 2 + 0.15, 0.3, 0), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
	local leverTop = frame * CFrame.new(size.X / 2 + 0.25, 1.1, 0.35)
	local leverFrom = (frame * CFrame.new(size.X / 2 + 0.25, 0.3, 0)).Position
	trimPart(switch, "Lever", Vector3.new(0.14, 0.14, (leverTop.Position - leverFrom).Magnitude), CFrame.lookAt((leverFrom + leverTop.Position) / 2, leverTop.Position), steel, Enum.Material.Metal)
	trimPart(switch, "LeverGrip", Vector3.new(0.34, 0.34, 0.34), leverTop, Color3.fromHex("E63946"), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	trimPart(switch, "Hazard", Vector3.new(size.X, 0.4, 0.04), frame * CFrame.new(0, -size.Y / 2 + 0.35, size.Z / 2 + 0.02), Color3.fromHex("F2C230"))
	for i = -1, 1 do
		trimPart(switch, "HazardStripe", Vector3.new(0.18, 0.5, 0.05), frame * CFrame.new(i * 0.42, -size.Y / 2 + 0.35, size.Z / 2 + 0.03) * CFrame.Angles(0, 0, math.rad(35)), dark)
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			trimPart(switch, "Bolt", Vector3.new(0.14, 0.14, 0.14), frame * CFrame.new(x * (size.X / 2 - 0.15), y * (size.Y / 2 - 0.15), size.Z / 2), steel, Enum.Material.Metal, Enum.PartType.Ball)
		end
	end
	trimPart(switch, "Cable", Vector3.new(0.16, 0.6, 0.16), frame * CFrame.new(-size.X / 2 + 0.3, -size.Y / 2 - 0.0, -size.Z / 2 + 0.2), dark)
	return switch
end

function CameraService.isBroken(point: BasePart): boolean
	return point:GetAttribute(Attr.Broken) == true
end

-- Камера работает: куплена, не сломана, её зал открыт и в музее есть свет (блэкаут гасит все камеры).
function CameraService.isWorking(point: BasePart): boolean
	return isOwned(point) and not CameraService.isBroken(point) and GameState.isHallOpen(point:GetAttribute(Attr.Hall))
		and GameState.get(GameState.Attr.Blackout) ~= true
end

-- Ближайшая работающая камера (её и ломает взломщик).
function CameraService.nearestWorking(position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, point in points do
		if CameraService.isWorking(point) then
			local distance = (point.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = point, distance
			end
		end
	end
	return best
end

-- Работающие камеры не дальше radius от точки, ближние первыми (план «Ослепление»).
function CameraService.workingNear(position: Vector3, radius: number): { BasePart }
	local list = {}
	for _, point in points do
		if CameraService.isWorking(point) and (point.Position - position).Magnitude <= radius then
			table.insert(list, point)
		end
	end
	table.sort(list, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	return list
end

-- Где встать вору под камерой: на полу под кронштейном, чуть дальше от стены (StandPoint пишет MapBuilder).
function CameraService.standPoint(point: BasePart): Vector3
	local stand = point:GetAttribute(Attr.StandPoint)
	if typeof(stand) == "Vector3" then
		return stand
	end
	return Vector3.new(point.Position.X, 3, point.Position.Z)
end

function CameraService.breakCamera(point: BasePart)
	if CameraService.isBroken(point) or not isOwned(point) then
		return
	end
	point:SetAttribute(Attr.Broken, true)
	Audio.playOnce(Config.Sounds.CameraBreak, point, Config.Sounds.CameraBreakVolume)
	refreshRepair()
end

-- Починить одну камеру (кнопка на табличке CAMERA SPOT под ней).
local function repairOne(camera: Camera, player: Player)
	local plaque = camera.plaque
	if not plaque or not isOwned(camera.point) or not CameraService.isBroken(camera.point) or not RoleService.canAct(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	if (root.Position - plaque.Position).Magnitude > Cameras.RepairPromptDistance + Config.Catch.ServerDistanceSlack then
		return
	end
	camera.point:SetAttribute(Attr.Broken, false)
	refreshRepair()
	Remotes.get(Remotes.Names.Banner):FireAllClients(("CAM %d IS BACK ONLINE"):format(camera.index), "info")
	ProgressService.cameraRepaired(player) -- задание «почини камеру» (этап 6, блок H1)
end

function CameraService.repairAll()
	for _, point in points do
		point:SetAttribute(Attr.Broken, false)
	end
	refreshRepair()
end

---------------------------------------------------------------- фазы

-- Днём камеры можно покупать, ночью — нет.
function CameraService.setDayActive(active: boolean)
	dayActive = active
	refreshAll()
end

-- Новый забег: остаются только бесплатные камеры, деньги в табличках обнуляются.
function CameraService.reset()
	for _, camera in cameras do
		camera.paid = 0
		if camera.free then
			if not isOwned(camera.point) then
				own(camera, false)
			end
		else
			camera.point:SetAttribute(Attr.Owned, false)
			if camera.model then
				camera.model:Destroy()
				camera.model = nil
			end
		end
	end
	CameraService.repairAll()
	refreshAll()
end

local function setupRepair(map: Instance)
	local console = map:FindFirstChild(MapSchema.ControlConsole, true)
	if not (console and console:IsA("BasePart")) then
		return
	end
	local switch = buildResetSwitch(console)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RepairPrompt"
	prompt.ActionText = "Restart cameras"
	prompt.ObjectText = "Some cameras are offline"
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.HoldDuration = Cameras.RepairHoldSeconds
	prompt.MaxActivationDistance = Cameras.ConsolePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = switch
	prompt.Triggered:Connect(function(player)
		if not RoleService.canAct(player) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local maxDistance = Cameras.ConsolePromptDistance + Config.Catch.ServerDistanceSlack
		if (root.Position - switch.Position).Magnitude > maxDistance then
			return
		end
		CameraService.repairAll()
		Remotes.get(Remotes.Names.Banner):FireAllClients("CAMERAS ARE BACK ONLINE", "info")
	end)
	repairPrompt = prompt
end

local function setupCamera(point: BasePart, index: number, spotsFolder: Instance?)
	point:SetAttribute(Attr.Broken, false)
	point:SetAttribute(Attr.Owned, false)
	table.insert(points, point)
	local camera: Camera = {
		index = index,
		point = point,
		plaque = nil,
		label = nil,
		prompt = nil,
		fixPrompt = nil,
		model = nil,
		paid = 0,
		free = table.find(Cameras.FreeIndices, index) ~= nil,
	}
	local spot = spotsFolder and spotsFolder:FindFirstChild("CameraSpot" .. index)
	local plaque = spot and spot:FindFirstChild(MapSchema.CameraPlaque, true)
	if plaque and plaque:IsA("BasePart") then
		camera.plaque = plaque
		local label = plaque:FindFirstChild("Text", true)
		if label and label:IsA("TextLabel") then
			camera.label = label
		end
		local prompt = Purchase.newPrompt(plaque, "BuyPrompt", Cameras.Price)
		prompt.Triggered:Connect(function(player)
			contribute(camera, player)
		end)
		camera.prompt = prompt
		-- Ремонт этой камеры (этап 5, блок E): видна, только пока камера сломана. У техника удержание
		-- обнуляет его клиент (Abilities), как у рубильника.
		local fix = Instance.new("ProximityPrompt")
		fix.Name = Cameras.FixPromptName
		fix.ActionText = "Repair camera"
		fix.ObjectText = ("CAM %d - no signal"):format(index)
		fix.KeyboardKeyCode = Config.Keys.Action
		fix.HoldDuration = Cameras.RepairHoldSeconds
		fix.MaxActivationDistance = Cameras.RepairPromptDistance
		fix.RequiresLineOfSight = false
		fix.Enabled = false
		fix.Parent = plaque
		fix.Triggered:Connect(function(player)
			repairOne(camera, player)
		end)
		camera.fixPrompt = fix
	end
	table.insert(cameras, camera)
end

function CameraService.init(map: Instance)
	local existing = map:FindFirstChild(MapSchema.InstalledCameras)
	if existing and existing:IsA("Folder") then
		installedFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = MapSchema.InstalledCameras
		created.Parent = map
		installedFolder = created
	end

	local folder = map:FindFirstChild(MapSchema.CameraPoints)
	local spotsFolder = map:FindFirstChild(MapSchema.CameraSpots)
	if folder then
		for _, child in folder:GetChildren() do
			local index = child:GetAttribute(Attr.Index)
			if child:IsA("BasePart") and typeof(index) == "number" then
				setupCamera(child, index, spotsFolder)
			end
		end
	end
	table.sort(cameras, function(a, b)
		return a.index < b.index
	end)

	-- Зал открыли днём — его места для камер сразу можно покупать
	GameState.folder().AttributeChanged:Connect(function(attr)
		if string.sub(attr, 1, #"HallOpen_") == "HallOpen_" then
			refreshAll()
		end
	end)

	setupRepair(map)
	CameraService.reset()

	-- Камеры во вкладке Security окна магазина (этап 4, блок 1b), после сигнализации и сеток
	for _, camera in cameras do
		local hall = camera.point:GetAttribute(Attr.Hall)
		ShopService.register({
			category = "Security",
			id = "Camera" .. camera.index,
			title = ("CAM %d"):format(camera.index),
			info = ("Camera — %s"):format(Cameras.Names[camera.index] or "Museum"),
			order = 100 + camera.index,
			price = Cameras.Price,
			hall = if typeof(hall) == "string" then hall else nil,
			preview = ModelLibrary.build(MapSchema.Models.Camera, CAMERA_STUB),
			state = function(): ShopService.State
				return { paid = camera.paid, owned = isOwned(camera.point) }
			end,
			buy = function(player: Player): (string, string)
				local title = ("CAM %d"):format(camera.index)
				if isOwned(camera.point) then
					return ShopService.fail(title .. " is already installed")
				elseif not GameState.isHallOpen(camera.point:GetAttribute(Attr.Hall)) then
					return ShopService.fail("Open the hall first — Halls tab")
				end
				local amount = contribute(camera, player, true)
				return ShopService.sharedResult(title, amount, camera.paid, Cameras.Price)
			end,
		})
	end
end

return CameraService
