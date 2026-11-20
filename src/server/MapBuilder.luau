-- Строит карту-заглушку из блоков, если в Workspace ещё нет готовой карты "Map".
-- Если владелец соберёт настоящую карту в Studio с именами из MapSchema, этот код её не тронет.
-- Координаты ниже — геометрия уровня-заглушки, а не баланс, поэтому они здесь, а не в Config.
--
-- Вид сверху (X вправо, Z вниз):
--
--   комната охраны (лобби)          — далеко на юге, Z 150..170
--   диспетчерская с пультом         — далеко на севере, Z -127..-115
--        | коридор 80 стадов
--   +----[ ]------------------------+  Z = -35
--   |                     [окно]    |  вход вора «Window» (восток)
--   |        [стена с Моной Лизой]  |
--   | [дверь]                       |  вход вора «Door» (запад)
--   +---------------------[люк]-----+  Z = 35, вход вора «Hatch» (юг)
--   X = -50                         X = 50

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

local function buildHall(geometry: Folder)
	local half = WALL_T / 2

	newPart(geometry, "Ground", Vector3.new(500, 1, 500), CFrame.new(0, -0.55, 0), COLORS.Ground, Enum.Material.Grass)
	newPart(geometry, "HallFloor", Vector3.new(100, 1, 70), CFrame.new(0, -0.5, 0), COLORS.Marble, Enum.Material.Marble)

	-- Внешние стены зала. В прототипе все проёмы на уровне пола, даже «окно».
	newWall(geometry, "X", -35, -50 - half, 50 + half, HALL_WALL_H, { { -44, -36 } }) -- север: проход в коридор
	newWall(geometry, "X", 35, -50 - half, 50 + half, HALL_WALL_H, { { 26, 34 } }) -- юг: люк
	newWall(geometry, "Z", -50, -35, 35, HALL_WALL_H, { { 16, 24 } }) -- запад: дверь
	newWall(geometry, "Z", 50, -35, 35, HALL_WALL_H, { { -24, -16 } }) -- восток: окно

	-- Стена в центре, на ней висит Мона Лиза (лицом на юг)
	newPart(geometry, "DisplayWall", Vector3.new(24, 12, 2), CFrame.new(0, 6, 0), COLORS.Wall)

	-- Перегородки и колонны: укрытия и слепые зоны для камер (примерные, проверим в игре)
	newPart(geometry, "Partition", Vector3.new(1, 12, 20), CFrame.new(-30, 6, 15), COLORS.Wall)
	newPart(geometry, "Partition", Vector3.new(1, 12, 20), CFrame.new(30, 6, -15), COLORS.Wall)
	newPart(geometry, "Column", Vector3.new(3, HALL_WALL_H, 3), CFrame.new(-15, HALL_WALL_H / 2, -20), COLORS.Marble)
	newPart(geometry, "Column", Vector3.new(3, HALL_WALL_H, 3), CFrame.new(15, HALL_WALL_H / 2, 20), COLORS.Marble)
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
	-- Точка привязки камеры — пластина крепления в самом углу зала (как в GEMINI.md, задание 3)
	local spots = {
		Vector3.new(-49.2, 14, 34.2), -- 1: юго-запад
		Vector3.new(49.2, 14, 34.2), -- 2: юго-восток
		Vector3.new(-49.2, 14, -34.2), -- 3: северо-запад
		Vector3.new(49.2, 14, -34.2), -- 4: северо-восток
	}
	local cameraStub = {
		{ size = Vector3.new(1, 1, 0.2), offset = CFrame.new(0, 0, -0.1), color = COLORS.Marble }, -- пластина
		{ size = Vector3.new(0.3, 0.3, 0.8), offset = CFrame.new(0, 0, -0.6), color = COLORS.Dark }, -- кронштейн
		{ size = Vector3.new(1.2, 1, 2), offset = CFrame.new(0, 0, -2), color = COLORS.Marble }, -- корпус
		{ size = Vector3.new(0.6, 0.6, 0.3), offset = CFrame.new(0, 0, -3.1), color = COLORS.Dark }, -- объектив
	}

	for index = 1, math.min(#spots, Config.Cameras.Count) do
		local position = spots[index]
		local target = Vector3.new(-position.X * 0.3, 2, -position.Z * 0.3)
		local cframe = CFrame.lookAt(position, target)
		ModelLibrary.place(MapSchema.Models.Camera, cframe, cameraStub, props)
		-- Точка обзора чуть впереди объектива, чтобы корпус не закрывал вид
		newMarker(cameraPoints, "Camera" .. index, cframe * CFrame.new(0, 0, -3.5))
	end
end

local function buildTrapSlots(trapSlots: Folder)
	local slots = {
		{ cframe = CFrame.new(-46, 0.05, 20), size = Vector3.new(2, 0.1, 8) }, -- у двери
		{ cframe = CFrame.new(46, 0.05, -20), size = Vector3.new(2, 0.1, 8) }, -- у окна
		{ cframe = CFrame.new(30, 0.05, 31), size = Vector3.new(8, 0.1, 2) }, -- у люка
		{ cframe = CFrame.new(-18, 0.05, 6), size = Vector3.new(2, 0.1, 8) }, -- проход слева от картины
		{ cframe = CFrame.new(18, 0.05, 6), size = Vector3.new(2, 0.1, 8) }, -- проход справа от картины
	}
	for index, slot in slots do
		local part = newPart(trapSlots, "Slot" .. index, slot.size, slot.cframe, COLORS.Turquoise, Enum.Material.Neon)
		part.Transparency = 0.5
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

local function buildEntrances(entrances: Folder)
	-- Точки снаружи у каждого проёма: тут воры появляются и сюда убегают
	newMarker(entrances, "Door", CFrame.new(-56, 3, 20))
	newMarker(entrances, "Window", CFrame.new(56, 3, -20))
	newMarker(entrances, "Hatch", CFrame.new(30, 3, 41))
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
	local trapSlots = newFolder(map, MapSchema.TrapSlots)

	buildHall(geometry)
	buildMonaLisa(map, exhibits, markers)
	buildProps(props)
	buildCameras(props, cameraPoints)
	buildTrapSlots(trapSlots)
	buildEntrances(entrances)
	buildControlRoom(map, geometry)
	buildLobby(geometry, props, markers)

	newMarker(markers, MapSchema.PatrolSpawn, CFrame.new(-40, 3, -28))
	newMarker(markers, MapSchema.TouristEntrance, CFrame.new(-56, 3, 20)) -- пока у западной двери

	return map
end

return MapBuilder
