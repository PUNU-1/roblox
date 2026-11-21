-- Строит музей кодом, если в Workspace ещё нет готовой карты "Map".
-- Если владелец соберёт настоящую карту в Studio с именами из MapSchema, этот код её не тронет.
-- Координаты ниже — геометрия уровня, а не баланс, поэтому они здесь, а не в Config.
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
--   X = -100     -50  портик с колоннами  50           100
--
-- Как выглядит (решил Claude, 21.11.2026):
--  • Снаружи — светлый песчаник, перед входом портик с колоннами и вывеской NIGHT MUSEUM.
--  • Главный зал — красные стены, тёмные деревянные панели внизу, золотой карниз, пол в шахматную
--    клетку из мрамора, стеклянный потолок над Моной Лизой, две люстры, картины на стенах.
--  • Мона Лиза — на стене из тёмно-красного бархата, с табличкой и канатным ограждением.
--  • Драгоценности — фиолетовые стены, тёмный паркет, красная ковровая дорожка, золотые колонны.
--  • Скульптуры — светлый камень, белый мрамор, колонны, стеклянный потолок.
--  • Люстры горят только днём; ночью — тусклые синие дежурные лампы.
-- Боковые залы закрыты досками, пока их не купят (HallService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local hex = Color3.fromHex

local COLORS = {
	Exterior = hex("D8CCB4"), -- песчаник снаружи
	Staff = hex("1E2A44"), -- служебные помещения
	Plank = hex("8A5A2B"),
	Marble = hex("E8DCC4"),
	MarbleDark = hex("3A3F4B"),
	WhiteMarble = hex("F2EEE6"),
	Gold = hex("D4A93A"),
	Red = hex("C8343A"),
	Velvet = hex("5E1622"),
	VelvetDark = hex("3D0E16"),
	Turquoise = hex("3BC6C1"),
	Ground = Color3.fromRGB(60, 90, 60),
	Dark = Color3.fromRGB(40, 40, 45),
	Wood = Color3.fromRGB(120, 80, 50),
	DarkWood = hex("5A3A22"),
	Canvas = Color3.fromRGB(110, 95, 60),
	Steel = Color3.fromRGB(90, 110, 140),
	Ceiling = hex("F4EFE4"),
	Stone = hex("BFB6A3"),
	Glass = hex("BFE3F2"),
	Terracotta = hex("B5651D"),
	Leaves = hex("3E7D3A"),
	LeavesLight = hex("5AA34F"),
	Navy = hex("1E2A44"),
}

-- Отделка стены изнутри зала: обои, деревянные панели внизу, карниз
type WallStyle = {
	wall: Color3,
	wallMaterial: Enum.Material,
	wainscot: Color3,
	trim: Color3,
	trimMaterial: Enum.Material,
}

local STYLES: { [string]: WallStyle } = {
	Main = { wall = hex("8C2A2A"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("4A2E1F"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Jewelry = { wall = hex("3B2559"), wallMaterial = Enum.Material.Fabric, wainscot = hex("2A1A12"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Sculptures = { wall = hex("D9D2C3"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("A89F8C"), trim = hex("F7F3EA"), trimMaterial = Enum.Material.Marble },
}

-- Картины-украшения на стенах (их не крадут): небо, солнце и холмы разных цветов
local PALETTES = {
	{ top = "2B5876", bottom = "F2A65A", sun = "FFE29A", hill = "3E5641", far = "2C3E2F" }, -- закат
	{ top = "8EC5FC", bottom = "E0F7FA", sun = "FFFFFF", hill = "6A994E", far = "386641" }, -- летний день
	{ top = "0F2027", bottom = "2C5364", sun = "F8F4E3", hill = "1B263B", far = "0D1B2A" }, -- лунная ночь
	{ top = "F6D365", bottom = "FDA085", sun = "FFFFFF", hill = "B5651D", far = "7F4F24" }, -- пустыня
	{ top = "355C7D", bottom = "6C5B7B", sun = "F67280", hill = "2A363B", far = "1F2A30" }, -- сумерки
	{ top = "A1C4FD", bottom = "C2E9FB", sun = "FFF3B0", hill = "4A7C59", far = "2F5233" }, -- озеро
}

local WALL_T = 1 -- толщина стен
local HALL_WALL_H = 16 -- высота залов (на ней потолок)
local ROOM_WALL_H = 12
local OPENING_H = 9 -- высота проёмов (выше — перемычка)
local WAINSCOT_H = 4 -- деревянные панели снизу
local CROWN_Y = 15 -- карниз под потолком
local DAY_LIGHT = "DayLight" -- атрибут: этот свет горит только днём (люстры)

local MapBuilder = {}

local geometryFolder: Folder -- стены, полы, потолки (по полам рисуется схема)
local decorFolder: Folder -- отделка без столкновений: обои, карнизы, картины, люстры
local paletteIndex = 0

---------------------------------------------------------------- помощники

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

-- Украшение: сквозь него можно пройти, оно не мешает путям воров и туристов
local function decorPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = newPart(decorFolder, name, size, cframe, color, material)
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
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

local function corner(parent: Instance, radius: UDim)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = radius
	uiCorner.Parent = parent
end

local function guiFrame(parent: Instance, position: UDim2, size: UDim2, color: Color3, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

local function surfaceGui(part: BasePart, face: Enum.NormalId, pixelsPerStud: number, lightInfluence: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = lightInfluence
	gui.Parent = part
	return gui
end

local function textOn(part: BasePart, face: Enum.NormalId, text: string, color: Color3, lightInfluence: number)
	local gui = surfaceGui(part, face, 40, lightInfluence)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

---------------------------------------------------------------- стены с отделкой

-- Отделка одной стороны куска стены. side = -1 или 1: какая сторона (по оси, поперёк стены).
local function decorateSegment(axis: string, fixed: number, a: number, b: number, y0: number, y1: number, side: number, style: WallStyle)
	local length = b - a
	if length <= 0 then
		return
	end
	local mid = (a + b) / 2
	local function strip(name: string, bottom: number, top: number, thickness: number, color: Color3, material: Enum.Material)
		local h = top - bottom
		if h <= 0.01 then
			return
		end
		local offset = WALL_T / 2 + thickness / 2
		local size, position
		if axis == "X" then
			size = Vector3.new(length, h, thickness)
			position = Vector3.new(mid, bottom + h / 2, fixed + side * offset)
		else
			size = Vector3.new(thickness, h, length)
			position = Vector3.new(fixed + side * offset, bottom + h / 2, mid)
		end
		decorPart(name, size, CFrame.new(position), color, material)
	end
	strip("Wallpaper", math.max(y0, WAINSCOT_H), math.min(y1, CROWN_Y), 0.1, style.wall, style.wallMaterial)
	if y0 < WAINSCOT_H then
		strip("Wainscot", y0, math.min(y1, WAINSCOT_H), 0.25, style.wainscot, Enum.Material.Wood)
		if y1 > WAINSCOT_H then
			strip("ChairRail", WAINSCOT_H - 0.15, WAINSCOT_H + 0.15, 0.35, style.trim, style.trimMaterial)
		end
	end
	if y1 > CROWN_Y then
		strip("Crown", CROWN_Y, y1, 0.4, style.trim, style.trimMaterial)
	end
end

-- Рамка вокруг проёма: две стойки и перемычка.
local function doorFrame(axis: string, fixed: number, a: number, b: number, side: number, style: WallStyle)
	local thickness = 0.45
	local offset = WALL_T / 2 + thickness / 2
	local function piece(along: number, width: number, bottom: number, top: number)
		local h = top - bottom
		local size, position
		if axis == "X" then
			size = Vector3.new(width, h, thickness)
			position = Vector3.new(along, bottom + h / 2, fixed + side * offset)
		else
			size = Vector3.new(thickness, h, width)
			position = Vector3.new(fixed + side * offset, bottom + h / 2, along)
		end
		decorPart("DoorFrame", size, CFrame.new(position), style.trim, style.trimMaterial)
	end
	piece(a - 0.35, 0.7, 0, OPENING_H)
	piece(b + 0.35, 0.7, 0, OPENING_H)
	piece((a + b) / 2, (b - a) + 1.4, OPENING_H, OPENING_H + 0.7)
end

-- Стена с проёмами. axis = "X": стена тянется вдоль X на линии z = fixed.
-- axis = "Z": тянется вдоль Z на линии x = fixed. openings — список {от, до}.
-- negStyle / posStyle — отделка зала со стороны меньших / больших координат (nil — улица).
-- color — цвет самой стены (по умолчанию песчаник снаружи).
local function newWall(
	axis: string,
	fixed: number,
	from: number,
	to: number,
	height: number,
	openings: { { number } }?,
	negStyle: WallStyle?,
	posStyle: WallStyle?,
	color: Color3?
)
	local wallColor = color or COLORS.Exterior
	local material = if color then Enum.Material.SmoothPlastic else Enum.Material.Concrete
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
		newPart(geometryFolder, "Wall", size, CFrame.new(position), wallColor, material)
		if negStyle then
			decorateSegment(axis, fixed, a, b, y0, y1, -1, negStyle)
		end
		if posStyle then
			decorateSegment(axis, fixed, a, b, y0, y1, 1, posStyle)
		end
	end

	local cursor = from
	local list: { { number } } = openings or {}
	for _, opening in ipairs(list) do
		segment(cursor, opening[1], 0, height)
		segment(opening[1], opening[2], OPENING_H, height) -- перемычка над проёмом
		if negStyle then
			doorFrame(axis, fixed, opening[1], opening[2], -1, negStyle)
		end
		if posStyle then
			doorFrame(axis, fixed, opening[1], opening[2], 1, posStyle)
		end
		cursor = opening[2]
	end
	segment(cursor, to, 0, height)
end

---------------------------------------------------------------- потолки, полы, колонны

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

-- Потолок на высоте y. skylight — стеклянный проём (свет днём сверху).
local function ceiling(area: Rect, y: number, skylight: Rect?)
	local function slab(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 <= 0 or z1 - z0 <= 0 then
			return
		end
		newPart(geometryFolder, "Ceiling", Vector3.new(x1 - x0, 1, z1 - z0), CFrame.new((x0 + x1) / 2, y + 0.5, (z0 + z1) / 2), COLORS.Ceiling)
	end
	if not skylight then
		slab(area.minX, area.maxX, area.minZ, area.maxZ)
		return
	end
	local s = skylight
	slab(area.minX, area.maxX, area.minZ, s.minZ)
	slab(area.minX, area.maxX, s.maxZ, area.maxZ)
	slab(area.minX, s.minX, s.minZ, s.maxZ)
	slab(s.maxX, area.maxX, s.minZ, s.maxZ)
	local width, depth = s.maxX - s.minX, s.maxZ - s.minZ
	local centerX, centerZ = (s.minX + s.maxX) / 2, (s.minZ + s.maxZ) / 2
	local glass = newPart(geometryFolder, "Skylight", Vector3.new(width, 0.3, depth), CFrame.new(centerX, y + 0.85, centerZ), COLORS.Glass, Enum.Material.Glass)
	glass.Transparency = 0.6
	glass.CastShadow = false
	-- Золотая рама и переплёт
	local bar = 0.5
	decorPart("SkylightFrame", Vector3.new(width + bar, 0.4, bar), CFrame.new(centerX, y + 0.2, s.minZ), COLORS.Gold, Enum.Material.Metal)
	decorPart("SkylightFrame", Vector3.new(width + bar, 0.4, bar), CFrame.new(centerX, y + 0.2, s.maxZ), COLORS.Gold, Enum.Material.Metal)
	decorPart("SkylightFrame", Vector3.new(bar, 0.4, depth), CFrame.new(s.minX, y + 0.2, centerZ), COLORS.Gold, Enum.Material.Metal)
	decorPart("SkylightFrame", Vector3.new(bar, 0.4, depth), CFrame.new(s.maxX, y + 0.2, centerZ), COLORS.Gold, Enum.Material.Metal)
	for i = 1, 3 do
		local x = s.minX + width * i / 4
		decorPart("SkylightBar", Vector3.new(0.25, 0.3, depth), CFrame.new(x, y + 0.7, centerZ), COLORS.Gold, Enum.Material.Metal)
	end
	decorPart("SkylightBar", Vector3.new(width, 0.3, 0.25), CFrame.new(centerX, y + 0.7, centerZ), COLORS.Gold, Enum.Material.Metal)
end

local function floorPart(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material, hall: string): Part
	local floor = newPart(geometryFolder, name, size, CFrame.new(center), color, material)
	floor:SetAttribute("Hall", hall) -- по этим полам рисуется схема и гуляют туристы
	return floor
end

-- Шахматная плитка поверх пола (только тёмные клетки).
local function checkerTiles(area: Rect, tile: number, color: Color3)
	local countX = math.floor((area.maxX - area.minX) / tile)
	local countZ = math.floor((area.maxZ - area.minZ) / tile)
	for i = 0, countX - 1 do
		for j = 0, countZ - 1 do
			if (i + j) % 2 == 0 then
				local x = area.minX + (i + 0.5) * tile
				local z = area.minZ + (j + 0.5) * tile
				local part = decorPart("Tile", Vector3.new(tile, 0.04, tile), CFrame.new(x, 0.02, z), color, Enum.Material.Marble)
				part.CanQuery = false
			end
		end
	end
end

-- Классическая колонна: база (её рисует схема), круглый ствол, капитель.
local function column(x: number, z: number, height: number, color: Color3, material: Enum.Material)
	newPart(geometryFolder, "Column", Vector3.new(2.8, 0.8, 2.8), CFrame.new(x, 0.4, z), color, material)
	local shaftHeight = height - 1.6
	local shaft = newPart(geometryFolder, "ColumnShaft", Vector3.new(shaftHeight, 2, 2), CFrame.new(x, 0.8 + shaftHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	shaft.Shape = Enum.PartType.Cylinder
	newPart(geometryFolder, "ColumnTop", Vector3.new(2.8, 0.8, 2.8), CFrame.new(x, height - 0.4, z), color, material)
end

---------------------------------------------------------------- картины, люстры, растения

-- Картина-украшение. wallPoint — точка на средней линии стены, facing — куда смотрит картина.
local function wallPainting(wallPoint: Vector3, facing: Vector3, width: number, height: number)
	paletteIndex = paletteIndex % #PALETTES + 1
	local palette = PALETTES[paletteIndex]
	local look = CFrame.lookAt(wallPoint, wallPoint + facing)
	decorPart("PaintingFrame", Vector3.new(width + 0.6, height + 0.6, 0.3), look * CFrame.new(0, 0, -0.8), COLORS.Gold, Enum.Material.Metal)
	local canvas = decorPart("PaintingCanvas", Vector3.new(width, height, 0.1), look * CFrame.new(0, 0, -1), COLORS.Canvas)
	local gui = surfaceGui(canvas, Enum.NormalId.Front, 30, 1)
	local root = guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), Color3.new(1, 1, 1), 1)
	root.ClipsDescendants = true
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(hex(palette.top), hex(palette.bottom))
	gradient.Rotation = 90
	gradient.Parent = root
	local sun = guiFrame(root, UDim2.fromScale(0.62, 0.18), UDim2.fromScale(0.16, 0.16 * width / height), hex(palette.sun), 2)
	corner(sun, UDim.new(0.5, 0))
	local far = guiFrame(root, UDim2.fromScale(-0.25, 0.5), UDim2.fromScale(0.95, 0.9), hex(palette.far), 3)
	corner(far, UDim.new(0.5, 0))
	local hill = guiFrame(root, UDim2.fromScale(0.3, 0.62), UDim2.fromScale(1.05, 0.9), hex(palette.hill), 4)
	corner(hill, UDim.new(0.5, 0))
end

-- Люстра: горит только днём (MapBuilder.setDayLights).
local function chandelier(x: number, z: number, ceilingY: number)
	local settings = Config.Lighting.Chandelier
	local hangY = ceilingY - 3.2
	decorPart("ChandelierChain", Vector3.new(0.2, ceilingY - hangY, 0.2), CFrame.new(x, (ceilingY + hangY) / 2, z), COLORS.Gold, Enum.Material.Metal)
	local ring = decorPart("Chandelier", Vector3.new(0.4, 4.4, 4.4), CFrame.new(x, hangY, z) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Gold, Enum.Material.Metal)
	ring.Shape = Enum.PartType.Cylinder
	local core = decorPart("ChandelierCore", Vector3.new(1.2, 1.2, 1.2), CFrame.new(x, hangY - 0.5, z), COLORS.Gold, Enum.Material.Metal)
	core.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Range = settings.Range
	light.Brightness = settings.Brightness
	light.Color = settings.Color
	light.Shadows = true
	light:SetAttribute(DAY_LIGHT, true)
	light.Parent = core
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local bulb = decorPart("Bulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(x + math.cos(angle) * 2, hangY + 0.5, z + math.sin(angle) * 2), settings.Color, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb:SetAttribute(DAY_LIGHT, true)
	end
end

local function plant(x: number, z: number)
	local pot = newPart(geometryFolder, "PlantPot", Vector3.new(1.6, 2, 2), CFrame.new(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Terracotta)
	pot.Shape = Enum.PartType.Cylinder
	local leaves = decorPart("Leaves", Vector3.new(2.8, 2.8, 2.8), CFrame.new(x, 2.8, z), COLORS.Leaves, Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	local top = decorPart("Leaves", Vector3.new(1.9, 1.9, 1.9), CFrame.new(x + 0.3, 4, z - 0.2), COLORS.LeavesLight, Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

-- Лампа на стене: светящаяся планка + точечный свет. Ночью это почти единственный свет в залах.
local function newLamp(parent: Instance, position: Vector3, size: Vector3, settings: { Range: number, Brightness: number, Color: Color3 })
	local lamp = newPart(parent, "Lamp", size, CFrame.new(position), settings.Color, Enum.Material.Neon)
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = settings.Range
	light.Brightness = settings.Brightness
	light.Color = settings.Color
	light.Parent = lamp
end

---------------------------------------------------------------- залы

local function warnAboutDefaultPlace()
	for _, name in { "Baseplate", "SpawnLocation" } do
		if Workspace:FindFirstChild(name) then
			warn(
				("[MapBuilder] В Workspace есть стандартный %s. Удалите его в Studio: он мешает карте."):format(name)
			)
		end
	end
end

local function buildMainHall()
	local half = WALL_T / 2
	local main = STYLES.Main

	newPart(geometryFolder, "Ground", Vector3.new(500, 1, 500), CFrame.new(0, -0.55, 0), COLORS.Ground, Enum.Material.Grass)
	floorPart("HallFloor", Vector3.new(100, 1, 70), Vector3.new(0, -0.5, 0), COLORS.Marble, Enum.Material.Marble, "Main")
	checkerTiles({ minX = -50, maxX = 50, minZ = -35, maxZ = 35 }, 10, COLORS.MarbleDark)

	-- Внешние стены главного зала. Проёмы на уровне пола.
	newWall("X", -35, -50 - half, 50 + half, HALL_WALL_H, { { -44, -36 }, { 30, 38 } }, nil, main) -- север: коридор, служебная дверь
	newWall("X", 35, -50 - half, 50 + half, HALL_WALL_H, { { -4, 4 }, { 38, 46 } }, main, nil) -- юг: главный вход, люк
	-- Запад: общая стена с Драгоценностями посередине
	newWall("Z", -50, -35, -25, HALL_WALL_H, nil, nil, main)
	newWall("Z", -50, -25, 25, HALL_WALL_H, { { -4, 4 } }, STYLES.Jewelry, main)
	newWall("Z", -50, 25, 35, HALL_WALL_H, nil, nil, main)
	-- Восток: общая стена со Скульптурами посередине
	newWall("Z", 50, -35, -25, HALL_WALL_H, nil, main, nil)
	newWall("Z", 50, -25, 25, HALL_WALL_H, { { -4, 4 } }, main, STYLES.Sculptures)
	newWall("Z", 50, 25, 35, HALL_WALL_H, nil, main, nil)

	-- Стеклянный потолок над Моной Лизой
	ceiling({ minX = -50.5, maxX = 50.5, minZ = -35.5, maxZ = 35.5 }, HALL_WALL_H, { minX = -18, maxX = 18, minZ = -9, maxZ = 9 })

	-- Стена в центре из тёмно-красного бархата, на ней Мона Лиза (лицом на юг)
	newPart(geometryFolder, "DisplayWall", Vector3.new(24, 12, 2), CFrame.new(0, 6, 0), COLORS.Velvet, Enum.Material.Fabric)
	decorPart("DisplayWallTop", Vector3.new(24.6, 0.6, 2.6), CFrame.new(0, 12.3, 0), COLORS.Gold, Enum.Material.Metal)
	decorPart("DisplayWallBase", Vector3.new(24.4, 1, 2.4), CFrame.new(0, 0.5, 0), COLORS.DarkWood, Enum.Material.Wood)
	for _, x in { -12.15, 12.15 } do
		decorPart("DisplayWallEdge", Vector3.new(0.4, 12, 2.4), CFrame.new(x, 6, 0), COLORS.Gold, Enum.Material.Metal)
	end
	decorPart("MonaLisaBackdrop", Vector3.new(7.6, 8.6, 0.15), CFrame.new(0, 7, 1.08), COLORS.VelvetDark, Enum.Material.Fabric)
	local plaque = decorPart("MonaLisaPlaque", Vector3.new(2.8, 0.8, 0.1), CFrame.lookAt(Vector3.new(0, 3.1, 1.2), Vector3.new(0, 3.1, 2)), COLORS.Gold, Enum.Material.Metal)
	textOn(plaque, Enum.NormalId.Front, "MONA LISA\nLeonardo da Vinci", hex("2A1A12"), 1)
	-- Картина на обратной стороне стены
	wallPainting(Vector3.new(0, 6.5, -0.5), Vector3.new(0, 0, -1), 10, 6)

	-- Колонны по бокам стены с Моной Лизой
	for _, x in { -14.2, 14.2 } do
		column(x, 0, HALL_WALL_H, COLORS.WhiteMarble, Enum.Material.Marble)
	end

	-- Перегородки: укрытия и слепые зоны для камер, на них тоже картины
	for _, spot in { { x = -30, z = 15 }, { x = 30, z = -15 } } do
		newPart(geometryFolder, "Partition", Vector3.new(1, 12, 20), CFrame.new(spot.x, 6, spot.z), main.wall)
		decorPart("PartitionTop", Vector3.new(1.4, 0.5, 20.4), CFrame.new(spot.x, 12.25, spot.z), COLORS.Gold, Enum.Material.Metal)
		decorPart("PartitionBase", Vector3.new(1.5, 1.2, 20.2), CFrame.new(spot.x, 0.6, spot.z), main.wainscot, Enum.Material.Wood)
		wallPainting(Vector3.new(spot.x, 6.5, spot.z), Vector3.new(1, 0, 0), 6, 4.5)
		wallPainting(Vector3.new(spot.x, 6.5, spot.z), Vector3.new(-1, 0, 0), 6, 4.5)
	end

	-- Картины на стенах
	for _, x in { -22, 0, 18 } do
		wallPainting(Vector3.new(x, 6.5, -35), Vector3.new(0, 0, 1), 6, 4.5)
	end
	for _, x in { -28, -14, 18 } do
		wallPainting(Vector3.new(x, 6.5, 35), Vector3.new(0, 0, -1), 6, 4.5)
	end
	for _, z in { -18, 18 } do
		wallPainting(Vector3.new(-50, 6.5, z), Vector3.new(1, 0, 0), 6, 4.5)
		wallPainting(Vector3.new(50, 6.5, z), Vector3.new(-1, 0, 0), 6, 4.5)
	end

	chandelier(-28, 0, HALL_WALL_H)
	chandelier(28, 0, HALL_WALL_H)
	plant(46, -31)
	plant(-46, 31)
end

local function buildSideHalls()
	local half = WALL_T / 2
	local jewelry, sculptures = STYLES.Jewelry, STYLES.Sculptures

	-- Драгоценности: фиолетовые стены, тёмный паркет, красная ковровая дорожка
	floorPart("JewelryFloor", Vector3.new(50, 1, 50), Vector3.new(-75, -0.5, 0), COLORS.DarkWood, Enum.Material.WoodPlanks, "Jewelry")
	newWall("X", -25, -100 - half, -50, HALL_WALL_H, nil, nil, jewelry)
	newWall("X", 25, -100 - half, -50, HALL_WALL_H, nil, jewelry, nil)
	newWall("Z", -100, -25, 25, HALL_WALL_H, { { 12, 20 } }, nil, jewelry) -- окно: вход вора
	ceiling({ minX = -100.5, maxX = -50.5, minZ = -25.5, maxZ = 25.5 }, HALL_WALL_H, nil)
	decorPart("Carpet", Vector3.new(47, 0.05, 6), CFrame.new(-73.5, 0.025, 0), COLORS.Red, Enum.Material.Fabric)
	for _, z in { -3.1, 3.1 } do
		decorPart("CarpetEdge", Vector3.new(47, 0.06, 0.3), CFrame.new(-73.5, 0.03, z), COLORS.Gold, Enum.Material.Fabric)
	end
	column(-96, -21, HALL_WALL_H, COLORS.Gold, Enum.Material.Metal)
	column(-54, 21, HALL_WALL_H, COLORS.Gold, Enum.Material.Metal)
	for _, x in { -82, -68 } do
		wallPainting(Vector3.new(x, 6.5, -25), Vector3.new(0, 0, 1), 6, 4.5)
		wallPainting(Vector3.new(x, 6.5, 25), Vector3.new(0, 0, -1), 6, 4.5)
	end
	wallPainting(Vector3.new(-100, 6.5, -8), Vector3.new(1, 0, 0), 6, 4.5)
	chandelier(-75, 0, HALL_WALL_H)

	-- Скульптуры: светлый камень, белый мрамор с каймой, колонны, стеклянный потолок
	floorPart("SculptureFloor", Vector3.new(50, 1, 50), Vector3.new(75, -0.5, 0), COLORS.WhiteMarble, Enum.Material.Marble, "Sculptures")
	newWall("X", -25, 50, 100 + half, HALL_WALL_H, nil, nil, sculptures)
	newWall("X", 25, 50, 100 + half, HALL_WALL_H, nil, sculptures, nil)
	newWall("Z", 100, -25, 25, HALL_WALL_H, { { -20, -12 } }, sculptures, nil) -- дверь: вход вора
	ceiling({ minX = 50.5, maxX = 100.5, minZ = -25.5, maxZ = 25.5 }, HALL_WALL_H, { minX = 63, maxX = 87, minZ = -9, maxZ = 9 })
	for _, z in { -22, 22 } do
		decorPart("FloorBorder", Vector3.new(45.5, 0.04, 1.5), CFrame.new(75, 0.02, z), COLORS.Stone, Enum.Material.Marble)
	end
	for _, x in { 53, 97 } do
		decorPart("FloorBorder", Vector3.new(1.5, 0.04, 45.5), CFrame.new(x, 0.02, 0), COLORS.Stone, Enum.Material.Marble)
	end
	for _, z in { -12, 12 } do
		column(75, z, HALL_WALL_H, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	for _, x in { 62, 88 } do
		wallPainting(Vector3.new(x, 6.5, -25), Vector3.new(0, 0, 1), 6, 4.5)
		wallPainting(Vector3.new(x, 6.5, 25), Vector3.new(0, 0, -1), 6, 4.5)
	end
	plant(97, -23)
	plant(53, 22)
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
	local sign = newPart(door, MapSchema.HallDoorSign, Vector3.new(6, 2.4, 0.2), cframe * CFrame.new(0, OPENING_H + 2, -0.8), COLORS.Dark)
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

-- Портрет на холсте заглушки Моны Лизы (пока владелец не загрузил настоящую картинку).
local function paintPortrait(canvas: BasePart)
	local gui = surfaceGui(canvas, Enum.NormalId.Front, 50, 1)
	local root = guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), Color3.new(1, 1, 1), 1)
	root.ClipsDescendants = true
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(hex("56664A"), hex("6B5A3A"))
	gradient.Rotation = 90
	gradient.Parent = root
	local function oval(x: number, y: number, w: number, h: number, color: string, z: number, radius: number?)
		local frame = guiFrame(root, UDim2.fromScale(x, y), UDim2.fromScale(w, h), hex(color), z)
		frame.AnchorPoint = Vector2.new(0.5, 0)
		corner(frame, UDim.new(radius or 0.5, 0))
	end
	oval(0.5, 0.1, 0.44, 0.42, "2A1E14", 2) -- волосы
	oval(0.5, 0.44, 0.84, 0.7, "2B2418", 3, 0.35) -- платье
	oval(0.5, 0.45, 0.3, 0.12, "C9A27A", 4) -- шея и вырез
	oval(0.5, 0.17, 0.27, 0.28, "D9B48A", 5) -- лицо
	oval(0.5, 0.79, 0.42, 0.1, "D9B48A", 6) -- сложенные руки
end

local function buildMonaLisa(map: Folder, exhibits: Folder, markers: Folder)
	-- Origin — центр нижнего края рамы, перед смотрит на юг (+Z)
	local position = Vector3.new(0, 4, 1.16)
	local pivot = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	local painting = ModelLibrary.place(MapSchema.Models.MonaLisa, pivot, {
		-- Портретная, как настоящая (Ш × В = 4.4 × 6)
		{ name = "Frame", size = Vector3.new(4.4, 6, 0.4), offset = CFrame.new(0, 3, -0.2), color = COLORS.Gold, material = Enum.Material.Metal },
		{ name = "Canvas", size = Vector3.new(3.6, 5.2, 0.1), offset = CFrame.new(0, 3, -0.45), color = COLORS.Canvas },
	}, exhibits)
	local canvas = painting:FindFirstChild("Canvas")
	if canvas and canvas:IsA("BasePart") and not ModelLibrary.has(MapSchema.Models.MonaLisa) then
		paintPortrait(canvas)
	end

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
	-- Канатное ограждение перед Моной Лизой, с проходом посередине
	local barrier = {
		{ size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(-1.8, 1.5, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(1.8, 1.5, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(3.6, 0.25, 0.25), offset = CFrame.new(0, 2.5, 0), color = COLORS.Red, material = Enum.Material.Fabric },
	}
	ModelLibrary.place(MapSchema.Models.Barrier, CFrame.new(-5, 0, 7.5), barrier, props)
	ModelLibrary.place(MapSchema.Models.Barrier, CFrame.new(5, 0, 7.5), barrier, props)

	-- Банкетки без спинки: тёмно-синее сиденье, золотая рама и ножки
	local bench = {
		{ size = Vector3.new(6, 0.5, 2), offset = CFrame.new(0, 1.35, 0), color = COLORS.Navy, material = Enum.Material.Fabric },
		{ size = Vector3.new(6.2, 0.2, 2.2), offset = CFrame.new(0, 1, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(-2.8, 0.45, -0.8), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(2.8, 0.45, -0.8), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(-2.8, 0.45, 0.8), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(2.8, 0.45, 0.8), color = COLORS.Gold, material = Enum.Material.Metal },
	}
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(0, 0, 17), bench, props)
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(0, 0, -14), bench, props)
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(-75, 0, 0), bench, props)
	ModelLibrary.place(MapSchema.Models.Bench, CFrame.new(75, 0, 0), bench, props)
end

local function buildFacade()
	-- Площадь и дорожка перед входом
	newPart(geometryFolder, "Plaza", Vector3.new(34, 0.2, 14), CFrame.new(0, 0.05, 43), COLORS.Stone, Enum.Material.Slate)
	newPart(geometryFolder, "Path", Vector3.new(8, 0.2, 40), CFrame.new(0, 0.05, 70), COLORS.Stone, Enum.Material.Slate)
	-- Портик: 4 колонны, перекрытие, фронтон и вывеска
	for _, x in { -13, -7, 7, 13 } do
		column(x, 41.5, 12, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	local beam = newPart(geometryFolder, "Portico", Vector3.new(32, 1.5, 7.5), CFrame.new(0, 12.75, 39.25), hex("EDE6D6"), Enum.Material.Marble)
	textOn(beam, Enum.NormalId.Back, "NIGHT MUSEUM", COLORS.Gold, 0)
	local left = Instance.new("WedgePart")
	left.Name = "Pediment"
	left.Anchored = true
	left.Size = Vector3.new(7.5, 4, 16)
	left.CFrame = CFrame.new(-8, 15.5, 39.25) * CFrame.Angles(0, math.rad(90), 0)
	left.Color = hex("EDE6D6")
	left.Material = Enum.Material.Marble
	left.Parent = geometryFolder
	local right = left:Clone()
	right.CFrame = CFrame.new(8, 15.5, 39.25) * CFrame.Angles(0, math.rad(-90), 0)
	right.Parent = geometryFolder
	-- Фонари у дорожки
	for _, x in { -10, 10 } do
		newPart(geometryFolder, "LampPost", Vector3.new(0.5, 8, 0.5), CFrame.new(x, 4, 52), COLORS.Dark, Enum.Material.Metal)
		newLamp(geometryFolder, Vector3.new(x, 8.4, 52), Vector3.new(1, 1, 1), Config.Lighting.LobbyLamp)
	end
end

local function buildCameras(props: Folder, cameraPoints: Folder)
	-- По 2 камеры на зал, под потолком в углах, без колонн и перегородок на пути взгляда.
	-- Камера 1 смотрит прямо на Мону Лизу.
	local y = 13.5
	local spots = {
		{ hall = "Main", position = Vector3.new(47.5, y, 32.5), target = Vector3.new(0, 5.5, 2) }, -- Мона Лиза и юг зала
		{ hall = "Main", position = Vector3.new(-47.5, y, -32.5), target = Vector3.new(12, 2, -12) }, -- север зала, служебная дверь
		{ hall = "Jewelry", position = Vector3.new(-51.5, y, -23.5), target = Vector3.new(-95, 3, 12) }, -- окно
		{ hall = "Jewelry", position = Vector3.new(-98.5, y, 23.5), target = Vector3.new(-55, 2, -5) }, -- зал и дверь
		{ hall = "Sculptures", position = Vector3.new(51.5, y, -23.5), target = Vector3.new(99, 2, -15) }, -- дверь
		{ hall = "Sculptures", position = Vector3.new(98.5, y, 23.5), target = Vector3.new(60, 2, -5) }, -- зал
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

local function buildControlRoom(map: Folder)
	local half = WALL_T / 2
	local staff = COLORS.Staff

	-- Длинный коридор от зала на север
	newPart(geometryFolder, "CorridorFloor", Vector3.new(8, 1, 80), CFrame.new(-40, -0.5, -75), COLORS.Marble, Enum.Material.Marble)
	newWall("Z", -44, -115, -35, ROOM_WALL_H, nil, nil, nil, staff)
	newWall("Z", -36, -115, -35, ROOM_WALL_H, nil, nil, nil, staff)
	ceiling({ minX = -44.5, maxX = -35.5, minZ = -115, maxZ = -35.5 }, ROOM_WALL_H, nil)

	-- Диспетчерская 16×12
	newPart(geometryFolder, "ControlRoomFloor", Vector3.new(16, 1, 12), CFrame.new(-40, -0.5, -121), COLORS.Dark)
	newWall("X", -115, -48 - half, -32 + half, ROOM_WALL_H, { { -44, -36 } }, nil, nil, staff)
	newWall("X", -127, -48 - half, -32 + half, ROOM_WALL_H, nil, nil, nil, staff)
	newWall("Z", -48, -127, -115, ROOM_WALL_H, nil, nil, nil, staff)
	newWall("Z", -32, -127, -115, ROOM_WALL_H, nil, nil, nil, staff)
	ceiling({ minX = -48.5, maxX = -31.5, minZ = -127.5, maxZ = -114.5 }, ROOM_WALL_H, nil)

	newPart(map, MapSchema.ControlConsole, Vector3.new(10, 3, 3), CFrame.new(-40, 1.5, -124), COLORS.Dark)
	newPart(geometryFolder, "Monitors", Vector3.new(10, 5, 0.5), CFrame.new(-40, 6, -126.2), COLORS.Turquoise, Enum.Material.Neon)
end

local function buildLobby(props: Folder, markers: Folder)
	local half = WALL_T / 2
	local wood = COLORS.Wood

	-- Комната охраны 30×20, закрытая: в зал игроков переносит игра
	newPart(geometryFolder, "LobbyFloor", Vector3.new(30, 1, 20), CFrame.new(0, -0.5, 160), COLORS.Wood, Enum.Material.WoodPlanks)
	newWall("X", 150, -15 - half, 15 + half, ROOM_WALL_H, nil, nil, nil, wood)
	newWall("X", 170, -15 - half, 15 + half, ROOM_WALL_H, nil, nil, nil, wood)
	newWall("Z", -15, 150, 170, ROOM_WALL_H, nil, nil, nil, wood)
	newWall("Z", 15, 150, 170, ROOM_WALL_H, nil, nil, nil, wood)
	ceiling({ minX = -15.5, maxX = 15.5, minZ = 149.5, maxZ = 170.5 }, ROOM_WALL_H, nil)

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

local function buildLamps(props: Folder)
	local night = Config.Lighting.NightLamp
	local alongX = Vector3.new(1.6, 0.4, 0.3) -- на стенах вдоль X (север / юг)
	local alongZ = Vector3.new(0.3, 0.4, 1.6) -- на стенах вдоль Z (запад / восток)
	-- Главный зал: по две на северной и южной стене
	for _, x in { -25, 25 } do
		newLamp(props, Vector3.new(x, 10, -34.2), alongX, night)
		newLamp(props, Vector3.new(x, 10, 34.2), alongX, night)
	end
	-- Драгоценности и Скульптуры: по одной на северной и южной стене
	for _, x in { -75, 75 } do
		newLamp(props, Vector3.new(x, 10, -24.2), alongX, night)
		newLamp(props, Vector3.new(x, 10, 24.2), alongX, night)
	end
	-- Коридор и диспетчерская
	newLamp(props, Vector3.new(-43.3, 8, -60), alongZ, night)
	newLamp(props, Vector3.new(-43.3, 8, -95), alongZ, night)
	newLamp(props, Vector3.new(-40, 9, -115.8), alongX, night)
	-- Комната охраны: тёплый свет, опоздавшие ждут тут и ночью
	newLamp(props, Vector3.new(0, 10, 169.3), alongX, Config.Lighting.LobbyLamp)
end

---------------------------------------------------------------- для игрового цикла

-- Люстры горят только днём. Ночью в залах темно (решение 57).
function MapBuilder.setDayLights(map: Instance, on: boolean)
	for _, descendant in map:GetDescendants() do
		if descendant:GetAttribute(DAY_LIGHT) == true then
			if descendant:IsA("Light") then
				descendant.Enabled = on
			elseif descendant:IsA("BasePart") then
				descendant.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

-- Строит карту (или возвращает уже готовую) и отдаёт Workspace.Map.
function MapBuilder.build(): Instance
	local existing = Workspace:FindFirstChild(MapSchema.Root)
	if existing then
		return existing
	end

	warnAboutDefaultPlace()

	local map = newFolder(Workspace, MapSchema.Root)
	geometryFolder = newFolder(map, MapSchema.Geometry)
	decorFolder = newFolder(map, "Decor")
	local props = newFolder(map, MapSchema.Props)
	local exhibits = newFolder(map, MapSchema.Exhibits)
	local markers = newFolder(map, MapSchema.Markers)
	local entrances = newFolder(map, MapSchema.ThiefEntrances)
	local cameraPoints = newFolder(map, MapSchema.CameraPoints)
	local hallDoors = newFolder(map, MapSchema.HallDoors)
	local pedestals = newFolder(map, MapSchema.Pedestals)

	buildMainHall()
	buildSideHalls()
	buildHallDoor(hallDoors, "Jewelry", Vector3.new(-50, 0, 0), Vector3.new(1, 0, 0))
	buildHallDoor(hallDoors, "Sculptures", Vector3.new(50, 0, 0), Vector3.new(-1, 0, 0))
	buildPedestals(pedestals)
	buildMonaLisa(map, exhibits, markers)
	buildProps(props)
	buildFacade()
	buildCameras(props, cameraPoints)
	buildEntrances(entrances)
	buildControlRoom(map)
	buildLobby(props, markers)
	buildLamps(props)

	newMarker(markers, MapSchema.PatrolSpawn, CFrame.new(-40, 3, -28))
	newMarker(markers, MapSchema.TouristEntrance, CFrame.new(0, 3, 42)) -- снаружи главного входа
	-- Главная дверь: днём открыта для туристов, ночью закрыта (переключает HallService)
	local frontDoor = newPart(map, MapSchema.FrontDoor, Vector3.new(8, OPENING_H, 0.6), CFrame.new(0, OPENING_H / 2, 35), COLORS.DarkWood, Enum.Material.Wood)
	frontDoor.CanCollide = false
	frontDoor.Transparency = 1

	MapBuilder.setDayLights(map, false)
	return map
end

return MapBuilder
