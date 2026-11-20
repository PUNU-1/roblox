-- Строит карту-заглушку из блоков, если в Workspace ещё нет готовой карты "Map".
-- Если владелец соберёт настоящую карту в Studio с именами из MapSchema, этот код её не тронет.
-- Координаты ниже — геометрия уровня-заглушки, а не баланс, поэтому они здесь, а не в Config.
--
-- Вид сверху (X вправо, Z вниз):
--
--   комната охраны (лобби)          — далеко на юге, Z 150..170
--   диспетчерская с пультом         — далеко на севере, Z -127..-115
--                       | коридор          служебная дверь (вход вора)
--   +-------------+----[ ]------------[ ]---+-------------+  Z = -35 / -25
--   | ДРАГОЦЕН-   |                         |  СКУЛЬПТУРЫ |
--   окно  НОСТИ  [доски]  [стена с Моной Лизой]  [доски]  дверь (вход вора)
--   | (вход вора) |                         |             |
--   +-------------+------[вход]--------[люк]+-------------+  Z = 25 / 35
--   X = -100     -50   туристы       вор    50           100
--   Боковые залы закрыты досками, пока их не купят (HallService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

-- Палитра из GEMINI.md
local COLORS = {
	Wall = Color3.fromHex("1E2A44"),
	JewelryWall = Color3.fromHex("3B2559"),
	JewelryFloor = Color3.fromHex("6E1E2E"),
	SculptureWall = Color3.fromHex("CFC8B8"),
	SculptureFloor = Color3.fromHex("F2EEE6"),
	Plank = Color3.fromHex("8A5A2B"),
	Marble = Color3.fromHex("E8DCC4"),
	Gold = Color3.fromHex("D4A93A"),
	Red = Color3.fromHex("C8343A"),
	Turquoise = Color3.fromHex("3BC6C1"),
	Ground = Color3.fromRGB(60, 90, 60),
	Dark = Color3.fromRGB(40, 40, 45),
	Wood = Color3.fromRGB(120, 80, 50),
	Canvas = Color3.fromRGB(110, 95, 60),
	Steel = Color3.fromRGB(90, 110, 140),
}

local WALL_T = 1 -- толщина стен
local HALL_WALL_H = 16
local ROOM_WALL_H = 12
local OPENING_H = 9 -- высота проёмов (выше — перемычка)

local MapBuilder = {}

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Невидимая точка без столкновений.
local function newMarker(parent: Instance, name: string, cframe: CFrame): Part
	local part = newPart(parent, name, Vector3.new(2, 2, 2), cframe, COLORS.Turquoise)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Стена с проёмами. axis = "X": стена тянется вдоль X на линии z = fixed.
-- axis = "Z": тянется вдоль Z на линии x = fixed. openings — список {от, до}.
local function newWall(
	parent: Instance,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	height: number,
	openings: { { number } }?
)
	local function segment(a: number, b: number, y0: number, y1: number)
		local length = b - a
		local h = y1 - y0
		if length <= 0 or h <= 0 then
			return
		end
		local mid = (a + b) / 2
		local size, position
		if axis == "X" then
			size = Vector3.new(length, h, WALL_T)
			position = Vector3.new(mid, y0 + h / 2, fixed)
		else
			size = Vector3.new(WALL_T, h, length)
			position = Vector3.new(fixed, y0 + h / 2, mid)
		end
		newPart(parent, "Wall", size, CFrame.new(position), COLORS.Wall)
	end

	local cursor = from
	local list: { { number } } = openings or {}
	for _, opening in ipairs(list) do
		segment(cursor, opening[1], 0, height)
		segment(opening[1], opening[2], OPENING_H, height) -- перемычка над проёмом
		cursor = opening[2]
	end
	segment(cursor, to, 0, height)
end

local function applyNightLighting()
	local night = Config.Lighting.Night
	Lighting.ClockTime = night.ClockTime
	Lighting.Brightness = night.Brightness
	Lighting.Ambient = night.Ambient
	Lighting.OutdoorAmbient = night.OutdoorAmbient
end

local function warnAboutDefaultPlace()
	for _, name in { "Baseplate", "SpawnLocation" } do
		if Workspace:FindFirstChild(name) then
			warn(
				("[MapBuilder] В Workspace есть стандартный %s. Удалите его в Studio: он мешает карте-заглушке."):format(
					name
				)
			)
		end
	end
end

local function floorPart(geometry: Folder, name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material, hall: string): Part
	local floor = newPart(geometry, name, size, CFrame.new(center), color, material)
	floor:SetAttribute("Hall", hall) -- по этим полам рисуется схема и гуляют туристы
	return floor
end

local function buildHall(geometry: Folder)
	local half = WALL_T / 2

	newPart(geometry, "Ground", Vector3.new(500, 1, 500), CFrame.new(0, -0.55, 0), COLORS.Ground, Enum.Material.Grass)
	floorPart(geometry, "HallFloor", Vector3.new(100, 1, 70), Vector3.new(0, -0.5, 0), COLORS.Marble, Enum.Material.Marble, "Main")

	-- Внешние стены главного зала. Проёмы на уровне пола.
	newWall(geometry, "X", -35, -50 - half, 50 + half, HALL_WALL_H, { { -44, -36 }, { 30, 38 } }) -- север: коридор, служебная дверь
	newWall(geometry, "X", 35, -50 - half, 50 + half, HALL_WALL_H, { { -4, 4 }, { 38, 46 } }) -- юг: главный вход, люк
	newWall(geometry, "Z", -50, -35, 35, HALL_WALL_H, { { -4, 4 } }) -- запад: дверь в Драгоценности
	newWall(geometry, "Z", 50, -35, 35, HALL_WALL_H, { { -4, 4 } }) -- восток: дверь в Скульптуры

	-- Стена в центре, на ней висит Мона Лиза (лицом на юг)
	newPart(geometry, "DisplayWall", Vector3.new(24, 12, 2), CFrame.new(0, 6, 0), COLORS.Wall)

	-- Перегородки и колонны: укрытия и слепые зоны для камер
	newPart(geometry, "Partition", Vector3.new(1, 12, 20), CFrame.new(-30, 6, 15), COLORS.Wall)
	newPart(geometry, "Partition", Vector3.new(1, 12, 20), CFrame.new(30, 6, -15), COLORS.Wall)
	newPart(geometry, "Column", Vector3.new(3, HALL_WALL_H, 3), CFrame.new(-15, HALL_WALL_H / 2, -20), COLORS.Marble)
	newPart(geometry, "Column", Vector3.new(3, HALL_WALL_H, 3), CFrame.new(15, HALL_WALL_H / 2, 20), COLORS.Marble)
end

-- Боковые залы 50×50: Драгоценности на западе, Скульптуры на востоке. Общая стена — стена главного зала.
local function buildSideHalls(geometry: Folder)
	local half = WALL_T / 2

	-- Драгоценности: тёмно-фиолетовые стены, красный ковёр
	floorPart(geometry, "JewelryFloor", Vector3.new(50, 1, 50), Vector3.new(-75, -0.5, 0), COLORS.JewelryFloor, Enum.Material.Fabric, "Jewelry")
	local function jewelryWall(axis: string, fixed: number, from: number, to: number, openings: { { number } }?)
		newWall(geometry, axis, fixed, from, to, HALL_WALL_H, openings)
	end
	jewelryWall("X", -25, -100 - half, -50, nil)
	jewelryWall("X", 25, -100 - half, -50, nil)
	jewelryWall("Z", -100, -25, 25, { { 12, 20 } }) -- окно: вход вора
	for _, wall in geometry:GetChildren() do
		if wall:IsA("BasePart") and wall.Name == "Wall" and wall.Position.X < -50 and wall.Color == COLORS.Wall then
			wall.Color = COLORS.JewelryWall
		end
	end
	-- Золотые колонны по углам
	for _, x in { -96, -54 } do
		for _, z in { -21, 21 } do
			newPart(geometry, "Column", Vector3.new(2, HALL_WALL_H, 2), CFrame.new(x, HALL_WALL_H / 2, z), COLORS.Gold, Enum.Material.Metal)
		end
	end

	-- Скульптуры: светлый камень, белый мрамор, колонны
	floorPart(geometry, "SculptureFloor", Vector3.new(50, 1, 50), Vector3.new(75, -0.5, 0), COLORS.SculptureFloor, Enum.Material.Marble, "Sculptures")
	newWall(geometry, "X", -25, 50, 100 + half, HALL_WALL_H)
	newWall(geometry, "X", 25, 50, 100 + half, HALL_WALL_H)
	newWall(geometry, "Z", 100, -25, 25, HALL_WALL_H, { { -20, -12 } }) -- дверь: вход вора
	for _, wall in geometry:GetChildren() do
		if wall:IsA("BasePart") and wall.Name == "Wall" and wall.Position.X > 50 and wall.Color == COLORS.Wall then
			wall.Color = COLORS.SculptureWall
		end
	end
	for _, z in { -12, 12 } do
		newPart(geometry, "Column", Vector3.new(3, HALL_WALL_H, 3), CFrame.new(75, HALL_WALL_H / 2, z), COLORS.SculptureFloor, Enum.Material.Marble)
	end
end

-- Заколоченная дверь: доски + щит, который не пускает, и табличка с ценой (текст пишет HallService).
local function buildHallDoor(folder: Folder, hall: string, center: Vector3, facing: Vector3)
	local door = Instance.new("Model")
	door.Name = "HallDoor_" .. hall
	door:SetAttribute("Hall", hall)
	local cframe = CFrame.lookAt(center, center + facing)
	local panel = newPart(door, MapSchema.HallDoorPanel, Vector3.new(8, OPENING_H, 0.6), cframe * CFrame.new(0, OPENING_H / 2, 0), COLORS.Plank, Enum.Material.WoodPlanks)
	panel.Transparency = 0.2
	for index, angle in { 0.35, -0.35, 0 } do
		local plank = newPart(door, "Plank", Vector3.new(9, 0.8, 0.3), cframe * CFrame.new(0, 2 + index * 2.2, -0.45) * CFrame.Angles(0, 0, angle), COLORS.Plank, Enum.Material.Wood)
		plank.CanCollide = false
	end
	local sign = newPart(door, MapSchema.HallDoorSign, Vector3.new(6, 2.4, 0.2), cframe * CFrame.new(0, OPENING_H + 1.6, -0.6), COLORS.Dark)
	sign.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = COLORS.Gold
	label.Text = hall
	label.Parent = gui
	gui.Parent = sign
	door.PrimaryPart = panel
	door.Parent = folder
end

-- Постамент: мраморная тумба с золотым верхом. Атрибуты Hall и Slot — для покупки экспонатов.
local function buildPedestals(folder: Folder)
	local spots = {
		{ hall = "Main", position = Vector3.new(-22, 0, 24) },
		{ hall = "Main", position = Vector3.new(22, 0, -24) },
		{ hall = "Jewelry", position = Vector3.new(-87, 0, -12) },
		{ hall = "Jewelry", position = Vector3.new(-87, 0, 12) },
		{ hall = "Jewelry", position = Vector3.new(-63, 0, -12) },
		{ hall = "Jewelry", position = Vector3.new(-63, 0, 12) },
		{ hall = "Sculptures", position = Vector3.new(63, 0, -18) },
		{ hall = "Sculptures", position = Vector3.new(63, 0, 18) },
		{ hall = "Sculptures", position = Vector3.new(87, 0, -6) },
		{ hall = "Sculptures", position = Vector3.new(87, 0, 6) },
	}
	local stub = {
		{ size = Vector3.new(2.4, 3, 2.4), offset = CFrame.new(0, 1.5, 0), color = COLORS.Marble, material = Enum.Material.Marble },
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 3.15, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 0.15, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	}
	for index, spot in spots do
		local pedestal = ModelLibrary.place(MapSchema.Models.Pedestal, CFrame.new(spot.position), stub, folder)
		pedestal.Name = "Pedestal" .. index
		pedestal:SetAttribute("Hall", spot.hall)
		pedestal:SetAttribute("Slot", index)
	end
end

local function buildMonaLisa(map: Folder, exhibits: Folder, markers: Folder)
	-- Origin — центр нижнего края рамы, перед смотрит на юг (+Z)
	local position = Vector3.new(0, 4, 1.01)
	local pivot = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	ModelLibrary.place(MapSchema.Models.MonaLisa, pivot, {
		-- Портретная, как настоящая (Ш × В = 4.4 × 6)
		{ size = Vector3.new(4.4, 6, 0.4), offset = CFrame.new(0, 3, -0.2), color = COLORS.Gold },
		{ size = Vector3.new(3.6, 5.2, 0.1), offset = CFrame.new(0, 3, -0.45), color = COLORS.Canvas },
	}, exhibits)

	newMarker(markers, MapSchema.PaintingSpot, pivot)

	local lightSettings = Config.Lighting.PaintingLight
	local lamp = newMarker(map, MapSchema.PaintingLight, CFrame.new(0, 9, 5))
	local light = Instance.new("PointLight")
	light.Range = lightSettings.Range
	light.Brightness = lightSettings.Brightness
	light.Color = lightSettings.Color
	light.Parent = lamp
end

local function buildProps(props: Folder)
	local barrier = {
		{ size = Vector3.new(0.6, 3, 0.6), offset = CFrame.new(-1.5, 1.5, 0), color = COLORS.Gold },
		{ size = Vector3.new(0.6, 3, 0.6), offset = CFrame.new(1.5, 1.5, 0), color = COLORS.Gold },
		{ size = Vector3.new(3, 0.2, 0.2), offset = CFrame.new(0, 2.6, 0), color = COLORS.Red },
	}
	ModelLibrary.place(MapSchema.Models.Barrier, CFrame.new(-8, 0, 4), barrier, props)
	ModelLibrary.place(MapSchema.Models.Barrier, CFrame.new(8, 0, 4), barrier, props)

	local bench = {
		{ size = Vector3.new(6, 1.5, 2), offset = CFrame.new(0, 0.75, 0), color = COLORS.Wood },
	}
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(0, 0, 14), bench, props)
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(-35, 0, -15), bench, props)
end

local function buildCameras(props: Folder, cameraPoints: Folder)
	-- По 2 камеры на зал, в углах, смотрят на середину своего зала (GEMINI.md, задание 3)
	local spots = {
		{ hall = "Main", position = Vector3.new(-49.2, 14, 34.2), target = Vector3.new(10, 2, -5) },
		{ hall = "Main", position = Vector3.new(49.2, 14, -34.2), target = Vector3.new(-10, 2, 5) },
		{ hall = "Jewelry", position = Vector3.new(-99.2, 14, 24.2), target = Vector3.new(-70, 2, -4) },
		{ hall = "Jewelry", position = Vector3.new(-50.8, 14, -24.2), target = Vector3.new(-80, 2, 4) },
		{ hall = "Sculptures", position = Vector3.new(99.2, 14, -24.2), target = Vector3.new(70, 2, 4) },
		{ hall = "Sculptures", position = Vector3.new(50.8, 14, 24.2), target = Vector3.new(80, 2, -4) },
	}
	local cameraStub = {
		{ size = Vector3.new(1, 1, 0.2), offset = CFrame.new(0, 0, -0.1), color = COLORS.Marble }, -- пластина
		{ size = Vector3.new(0.3, 0.3, 0.8), offset = CFrame.new(0, 0, -0.6), color = COLORS.Dark }, -- кронштейн
		{ size = Vector3.new(1.2, 1, 2), offset = CFrame.new(0, 0, -2), color = COLORS.Marble }, -- корпус
		{ size = Vector3.new(0.6, 0.6, 0.3), offset = CFrame.new(0, 0, -3.1), color = COLORS.Dark }, -- объектив
	}

	for index = 1, math.min(#spots, Config.Cameras.Count) do
		local spot = spots[index]
		local cframe = CFrame.lookAt(spot.position, spot.target)
		ModelLibrary.place(MapSchema.Models.Camera, cframe, cameraStub, props)
		-- Точка обзора чуть впереди объектива, чтобы корпус не закрывал вид
		local point = newMarker(cameraPoints, "Camera" .. index, cframe * CFrame.new(0, 0, -3.5))
		point:SetAttribute("Hall", spot.hall)
	end
end

local function buildEntrances(entrances: Folder)
	-- Точки снаружи у каждого входа воров: тут они появляются и сюда убегают.
	-- Входы боковых залов работают, только когда зал открыт (атрибут Hall).
	local spots = {
		{ name = "Hatch", hall = "Main", position = Vector3.new(42, 3, 41) },
		{ name = "ServiceDoor", hall = "Main", position = Vector3.new(34, 3, -41) },
		{ name = "JewelryWindow", hall = "Jewelry", position = Vector3.new(-106, 3, 16) },
		{ name = "SculptureDoor", hall = "Sculptures", position = Vector3.new(106, 3, -16) },
	}
	for _, spot in spots do
		local marker = newMarker(entrances, spot.name, CFrame.new(spot.position))
		marker:SetAttribute("Hall", spot.hall)
	end
end

local function buildControlRoom(map: Folder, geometry: Folder)
	local half = WALL_T / 2

	-- Длинный коридор от зала на север
	newPart(geometry, "CorridorFloor", Vector3.new(8, 1, 80), CFrame.new(-40, -0.5, -75), COLORS.Marble, Enum.Material.Marble)
	newWall(geometry, "Z", -44, -115, -35, ROOM_WALL_H)
	newWall(geometry, "Z", -36, -115, -35, ROOM_WALL_H)

	-- Диспетчерская 16×12
	newPart(geometry, "ControlRoomFloor", Vector3.new(16, 1, 12), CFrame.new(-40, -0.5, -121), COLORS.Dark)
	newWall(geometry, "X", -115, -48 - half, -32 + half, ROOM_WALL_H, { { -44, -36 } })
	newWall(geometry, "X", -127, -48 - half, -32 + half, ROOM_WALL_H)
	newWall(geometry, "Z", -48, -127, -115, ROOM_WALL_H)
	newWall(geometry, "Z", -32, -127, -115, ROOM_WALL_H)

	newPart(map, MapSchema.ControlConsole, Vector3.new(10, 3, 3), CFrame.new(-40, 1.5, -124), COLORS.Dark)
	newPart(geometry, "Monitors", Vector3.new(10, 5, 0.5), CFrame.new(-40, 6, -126.2), COLORS.Turquoise, Enum.Material.Neon)
end

local function buildLobby(geometry: Folder, props: Folder, markers: Folder)
	local half = WALL_T / 2

	-- Комната охраны 30×20, закрытая: в зал игроков переносит игра
	newPart(geometry, "LobbyFloor", Vector3.new(30, 1, 20), CFrame.new(0, -0.5, 160), COLORS.Wood, Enum.Material.WoodPlanks)
	newWall(geometry, "X", 150, -15 - half, 15 + half, ROOM_WALL_H)
	newWall(geometry, "X", 170, -15 - half, 15 + half, ROOM_WALL_H)
	newWall(geometry, "Z", -15, 150, 170, ROOM_WALL_H)
	newWall(geometry, "Z", 15, 150, 170, ROOM_WALL_H)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = MapSchema.LobbySpawn
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- без защитного поля
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(0, 0.5, 162)
	spawn.Color = COLORS.Steel
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = markers

	local locker = {
		{ size = Vector3.new(3, 7, 2), offset = CFrame.new(0, 3.5, 0), color = COLORS.Steel },
	}
	for _, x in { -10, -6, -2, 2, 6, 10 } do
		local position = Vector3.new(x, 0, 151.5)
		ModelLibrary.place(MapSchema.Models.Locker, CFrame.lookAt(position, position + Vector3.new(0, 0, 1)), locker, props)
	end
end

-- Строит карту (или возвращает уже готовую) и отдаёт Workspace.Map.
function MapBuilder.build(): Instance
	local existing = Workspace:FindFirstChild(MapSchema.Root)
	if existing then
		return existing
	end

	warnAboutDefaultPlace()
	applyNightLighting()

	local map = newFolder(Workspace, MapSchema.Root)
	local geometry = newFolder(map, MapSchema.Geometry)
	local props = newFolder(map, MapSchema.Props)
	local exhibits = newFolder(map, MapSchema.Exhibits)
	local markers = newFolder(map, MapSchema.Markers)
	local entrances = newFolder(map, MapSchema.ThiefEntrances)
	local cameraPoints = newFolder(map, MapSchema.CameraPoints)
	local hallDoors = newFolder(map, MapSchema.HallDoors)
	local pedestals = newFolder(map, MapSchema.Pedestals)

	buildHall(geometry)
	buildSideHalls(geometry)
	buildHallDoor(hallDoors, "Jewelry", Vector3.new(-50, 0, 0), Vector3.new(1, 0, 0))
	buildHallDoor(hallDoors, "Sculptures", Vector3.new(50, 0, 0), Vector3.new(-1, 0, 0))
	buildPedestals(pedestals)
	buildMonaLisa(map, exhibits, markers)
	buildProps(props)
	buildCameras(props, cameraPoints)
	buildEntrances(entrances)
	buildControlRoom(map, geometry)
	buildLobby(geometry, props, markers)

	newMarker(markers, MapSchema.PatrolSpawn, CFrame.new(-40, 3, -28))
	newMarker(markers, MapSchema.TouristEntrance, CFrame.new(0, 3, 42)) -- снаружи главного входа
	-- Главная дверь: днём открыта для туристов, ночью закрыта (переключает HallService)
	local frontDoor = newPart(map, MapSchema.FrontDoor, Vector3.new(8, OPENING_H, 0.6), CFrame.new(0, OPENING_H / 2, 35), COLORS.Wood, Enum.Material.Wood)
	frontDoor.CanCollide = false
	frontDoor.Transparency = 1

	return map
end

return MapBuilder
