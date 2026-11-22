-- Строит музей кодом, если в Workspace ещё нет готовой карты "Map".
-- Если владелец соберёт настоящую карту в Studio с именами из MapSchema, этот код её не тронет.
-- Координаты ниже — геометрия уровня, а не баланс, поэтому они здесь, а не в Config.
--
-- Новый большой музей (блок 2, решение 69). Вид сверху: X вправо, Z вниз, север — вверх (−Z).
-- Наружная стена — квадрат ±130 (260 × 260), двери посередине сторон.
--
--   +-----------------------------[ N ]--------------------------------+
--   |  ДИНОЗАВРЫ (вход из W)        |холл|   ДРАГОЦЕННОСТИ (вход из N)    |
--   |                         коридор N, повороты                        |
--  [W] холл                   +-----------+                     холл  [E]
--   |  коридор W, повороты    |   ЦЕНТР   |    коридор E, повороты       |
--   |                         | Мона Лиза |                              |
--   |                         +-----------+                              |
--   |  СКУЛЬПТУРЫ (вход из S)   коридор S     КОСМОС (вход из E)         |
--   |                               |        служебный угол: щиток, оружейная
--   +-----------------------------[ S ]--------------------------------+
--                         портик NIGHT MUSEUM, площадь
--                         домик SECURITY (лобби, круг START SHIFT)
--
--  • Центр 88 × 88 в два этажа: Мона Лиза на бархатной стене в самой середине, над ней стеклянный
--    потолок; вдоль северной стены балкон с двумя лестницами, на балконе пульт камер.
--  • Крыло (входной холл + коридор с тремя поворотами + зал за деньги) описано в координатах южного
--    крыла и повёрнуто на 90° для остальных: дверь → холл → на восток → на север → на запад → в центр.
--    От двери до Моны Лизы ~190 стадов: охраннику (скорость 16) бежать ~12 сек.
--  • Каждая комната — прямоугольник со своими стенами; соседние комнаты стоят вплотную (стены
--    касаются), проходы между ними — арки. Всё, что не комната, — глухое пространство за стенами.
--  • Залы открываются за деньги (HallService), в зал ведёт одна дверь — из коридора у самого центра.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local MapDecor = require(Server:WaitForChild("MapDecor"))

local hex = Color3.fromHex

local COLORS = {
	Exterior = hex("D8CCB4"), -- песчаник снаружи
	ExteriorDark = hex("B8AA8E"), -- цоколь и карниз снаружи
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
	Parquet = hex("6B4A2E"),
	Canvas = Color3.fromRGB(110, 95, 60),
	Steel = Color3.fromRGB(90, 110, 140),
	Metal = hex("8A93A6"),
	Ceiling = hex("F4EFE4"),
	Stone = hex("BFB6A3"),
	Glass = hex("BFE3F2"),
	Terracotta = hex("B5651D"),
	Leaves = hex("3E7D3A"),
	LeavesLight = hex("5AA34F"),
	Navy = hex("1E2A44"),
	ExitGreen = hex("2FA35A"),
	Window = hex("2B3A55"),
}

-- Отделка стены изнутри комнаты: обои, деревянные панели внизу, карниз
export type WallStyle = {
	wall: Color3,
	wallMaterial: Enum.Material,
	wainscot: Color3,
	trim: Color3,
	trimMaterial: Enum.Material,
}

local STYLES: { [string]: WallStyle } = {
	Main = { wall = hex("8C2A2A"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("4A2E1F"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Corridor = { wall = hex("2E4A5A"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("4A2E1F"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Lobby = { wall = hex("E6D9BE"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("6B4A2B"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Sculptures = { wall = hex("D9D2C3"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("A89F8C"), trim = hex("F7F3EA"), trimMaterial = Enum.Material.Marble },
	Dinosaurs = { wall = hex("D9B98A"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("6B4A2B"), trim = hex("8A6A45"), trimMaterial = Enum.Material.Wood },
	Jewelry = { wall = hex("3B2559"), wallMaterial = Enum.Material.Fabric, wainscot = hex("2A1A12"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
	Space = { wall = hex("1B2340"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("0F1428"), trim = hex("3BC6C1"), trimMaterial = Enum.Material.Neon },
	Staff = { wall = hex("4A5266"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("2B2F3A"), trim = hex("8A93A6"), trimMaterial = Enum.Material.Metal },
	Armory = { wall = hex("3A4250"), wallMaterial = Enum.Material.Concrete, wainscot = hex("2B2F3A"), trim = hex("C8343A"), trimMaterial = Enum.Material.Metal },
	Guard = { wall = hex("1E2A44"), wallMaterial = Enum.Material.SmoothPlastic, wainscot = hex("5A3A22"), trim = COLORS.Gold, trimMaterial = Enum.Material.Metal },
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
local OPENING_H = 9 -- высота дверей в залы (доски 8 × 9)
local ARCH_H = 11 -- высота арок между коридорами и в центр
local WAINSCOT_H = 4 -- деревянные панели снизу
local DAY_LIGHT = "DayLight" -- атрибут: этот свет горит только днём (люстры)

-- Размеры музея
local HALF = 130 -- внутренняя сторона наружной стены
local SHELL_H = 21 -- высота наружной стены
local CENTER_H = 26 -- центр в два этажа
local CORRIDOR_H = 14
local LOBBY_H = 16
local HALL_H = 20
local STAFF_H = 12
local DOOR_HALF = 5 -- входная дверь шириной 10
local DOOR_H = 10
local BALCONY_Y = 12 -- пол балкона
local STAIR_STEPS = 20

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local CENTER = rect(-44, 44, -44, 44)
local SKYLIGHT = rect(-18, 18, -18, 18)
-- Крыло в координатах южного крыла (k = 0). Остальные крылья — поворот на 90°: k = 1 запад, 2 север, 3 восток.
local WING = {
	Lobby = rect(-14, 46, 110, 129), -- входной холл, дверь в южной стене (x от −5 до 5)
	C1 = rect(34, 46, 86, 108), -- из холла на север
	C2 = rect(-6, 46, 72, 84), -- на запад
	C3 = rect(-6, 6, 46, 70), -- на север, в центр; в западной стене — дверь зала
}
-- Ковровая дорожка от двери до центра (осевая линия коридора)
local WING_PATH = { Vector2.new(0, 130), Vector2.new(0, 116), Vector2.new(40, 116), Vector2.new(40, 78), Vector2.new(0, 78), Vector2.new(0, 44) }
local HALL_RECT = rect(-96, -8, 48, 106) -- зал южного крыла (Скульптуры); остальные залы — поворот
local HALL_DOOR = { x = -7, z1 = 52, z2 = 60 } -- дверь зала: в западной стене коридора C3
local SIDE_NAMES = { [0] = "South", [1] = "West", [2] = "North", [3] = "East" }
local WING_HALLS = { [0] = "Sculptures", [1] = "Dinosaurs", [2] = "Jewelry", [3] = "Space" }
-- Служебный угол на юго-востоке (только у южного крыла): дверь STAFF ONLY из коридора C1
local STAFF_CORRIDOR = rect(48, 100, 98, 106)
local ARMORY = rect(102, 128, 98, 128)
local STAFF_DOOR = { x = 47, z1 = 99, z2 = 105 }
-- Комната охраны (лобби) — отдельный домик SECURITY к югу от площади
local LOBBY = rect(-25, 25, 200, 240)
local GUARD_H = 14 -- высота домика охраны
local START_CIRCLE_CENTER = Vector3.new(0, 0, 218)
local LOBBY_SPAWN = Vector3.new(0, 0.5, 232)

local MapBuilder = {}

local geometryFolder: Folder -- стены, полы, потолки (по полам рисуется схема)
local decorFolder: Folder -- отделка без столкновений: обои, карнизы, картины, люстры
local propsFolder: Folder
local paletteIndex = 0

---------------------------------------------------------------- повороты крыльев

-- Поворот точки на k четвертей: юг → запад → север → восток.
local function rotXZ(k: number, x: number, z: number): (number, number)
	for _ = 1, k % 4 do
		x, z = -z, x
	end
	return x, z
end

local function rotRect(k: number, r: Rect): Rect
	local x1, z1 = rotXZ(k, r.minX, r.minZ)
	local x2, z2 = rotXZ(k, r.maxX, r.maxZ)
	return rect(math.min(x1, x2), math.max(x1, x2), math.min(z1, z2), math.max(z1, z2))
end

-- Тот же поворот в виде CFrame (вокруг вертикальной оси через центр музея).
local function turn(k: number): CFrame
	return CFrame.Angles(0, -k * math.pi / 2, 0)
end

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

-- Твёрдая деталь здания (в папке Geometry)
local function solidPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return newPart(geometryFolder, name, size, cframe, color, material)
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

local function textOn(part: BasePart, face: Enum.NormalId, text: string, color: Color3, lightInfluence: number): TextLabel
	local gui = surfaceGui(part, face, 40, lightInfluence)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

-- Табличка на стене: тёмная доска с золотой рамкой и надписью. point — на поверхности стены, facing — от стены.
local function wallSign(point: Vector3, facing: Vector3, width: number, height: number, text: string, color: Color3?, background: Color3?): Part
	local look = CFrame.lookAt(point, point + facing)
	decorPart("SignFrame", Vector3.new(width + 0.3, height + 0.3, 0.1), look * CFrame.new(0, 0, -0.05), COLORS.Gold, Enum.Material.Metal)
	local board = decorPart("Sign", Vector3.new(width, height, 0.1), look * CFrame.new(0, 0, -0.12), background or COLORS.Navy)
	textOn(board, Enum.NormalId.Front, text, color or COLORS.Gold, 0)
	return board
end

-- Модель из библиотеки (заглушка, пока друг не сделал свою). collide = false — украшение, сквозь него можно пройти.
local function placeModel(name: string, cframe: CFrame, stub: { ModelLibrary.StubPart }, collide: boolean?): PVInstance
	local instance = ModelLibrary.place(name, cframe, stub, propsFolder)
	if collide == false then
		ModelLibrary.forEachPart(instance, function(part)
			part.CanCollide = false
			part.CanTouch = false
		end)
	end
	return instance
end

---------------------------------------------------------------- стены с отделкой

-- Отделка одной стороны куска стены. side = -1 или 1: какая сторона (по оси, поперёк стены).
local function decorateSegment(axis: string, fixed: number, a: number, b: number, y0: number, y1: number, side: number, style: WallStyle, crownY: number)
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
	strip("Wallpaper", math.max(y0, WAINSCOT_H), math.min(y1, crownY), 0.1, style.wall, style.wallMaterial)
	if y0 < WAINSCOT_H then
		strip("Wainscot", y0, math.min(y1, WAINSCOT_H), 0.25, style.wainscot, Enum.Material.Wood)
		if y1 > WAINSCOT_H then
			strip("ChairRail", WAINSCOT_H - 0.15, WAINSCOT_H + 0.15, 0.35, style.trim, style.trimMaterial)
		end
	end
	if y1 > crownY then
		strip("Crown", crownY, y1, 0.4, style.trim, style.trimMaterial)
	end
end

-- Рамка вокруг проёма: две стойки и перемычка.
local function doorFrame(axis: string, fixed: number, a: number, b: number, side: number, style: WallStyle, top: number)
	local thickness = 0.45
	local offset = WALL_T / 2 + thickness / 2
	local function piece(along: number, width: number, bottom: number, pieceTop: number)
		local h = pieceTop - bottom
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
	piece(a - 0.35, 0.7, 0, top)
	piece(b + 0.35, 0.7, 0, top)
	piece((a + b) / 2, (b - a) + 1.4, top, top + 0.7)
end

type Opening = { number } -- { от, до, верх проёма? }

export type WallOptions = {
	openings: { Opening }?,
	neg: WallStyle?, -- отделка со стороны меньших координат (nil — без отделки)
	pos: WallStyle?, -- со стороны больших координат
	color: Color3?, -- цвет самой стены (по умолчанию песчаник)
	decorMin: number?, -- отделку кладём только в этих пределах (внутри комнаты, без углов)
	decorMax: number?,
}

-- Стена с проёмами. axis = "X": стена тянется вдоль X на линии z = fixed.
-- axis = "Z": тянется вдоль Z на линии x = fixed. Проёмы — список {от, до, верх}, по возрастанию.
local function newWall(axis: string, fixed: number, from: number, to: number, height: number, options: WallOptions?)
	local opts: WallOptions = options or {}
	local wallColor = opts.color or COLORS.Exterior
	local material = if opts.color then Enum.Material.SmoothPlastic else Enum.Material.Concrete
	local crownY = height - 1
	local decorMin = opts.decorMin or from
	local decorMax = opts.decorMax or to
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
		solidPart("Wall", size, CFrame.new(position), wallColor, material)
		local da, db = math.max(a, decorMin), math.min(b, decorMax)
		if opts.neg then
			decorateSegment(axis, fixed, da, db, y0, y1, -1, opts.neg, crownY)
		end
		if opts.pos then
			decorateSegment(axis, fixed, da, db, y0, y1, 1, opts.pos, crownY)
		end
	end

	local cursor = from
	local openings: { Opening } = opts.openings or {}
	for _, opening in openings do
		local top = opening[3] or OPENING_H
		segment(cursor, opening[1], 0, height)
		segment(opening[1], opening[2], top, height) -- перемычка над проёмом
		if opts.neg then
			doorFrame(axis, fixed, opening[1], opening[2], -1, opts.neg, top)
		end
		if opts.pos then
			doorFrame(axis, fixed, opening[1], opening[2], 1, opts.pos, top)
		end
		cursor = opening[2]
	end
	segment(cursor, to, 0, height)
end

---------------------------------------------------------------- проходы между комнатами

-- Проход — отрезок на границе двух соседних комнат (между их стенами). Каждая комната сама
-- находит проходы на своих стенах и оставляет в них проём.
type Doorway = { axis: string, line: number, from: number, to: number, top: number }

local doorways: { Doorway } = {}

local function addDoorway(k: number, x1: number, z1: number, x2: number, z2: number, top: number)
	local a, b = rotXZ(k, x1, z1)
	local c, d = rotXZ(k, x2, z2)
	if math.abs(b - d) < 0.01 then
		table.insert(doorways, { axis = "X", line = b, from = math.min(a, c), to = math.max(a, c), top = top })
	else
		table.insert(doorways, { axis = "Z", line = a, from = math.min(b, d), to = math.max(b, d), top = top })
	end
end

local function openingsFor(axis: string, fixed: number, from: number, to: number): { Opening }
	local list: { Opening } = {}
	for _, doorway in doorways do
		if doorway.axis == axis and math.abs(doorway.line - fixed) <= 0.75 and doorway.from >= from - 0.01 and doorway.to <= to + 0.01 then
			table.insert(list, { doorway.from, doorway.to, doorway.top })
		end
	end
	table.sort(list, function(p, q)
		return p[1] < q[1]
	end)
	return list
end

local function insideOpening(openings: { Opening }, along: number, margin: number): boolean
	for _, opening in openings do
		if along > opening[1] - margin and along < opening[2] + margin then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- потолки, полы, колонны

-- Потолок на высоте y. skylight — стеклянный проём (свет днём сверху). Возвращает плиты потолка.
local function ceiling(area: Rect, y: number, skylight: Rect?, color: Color3?, glassName: string?): { Part }
	local slabs: { Part } = {}
	local function slab(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 <= 0 or z1 - z0 <= 0 then
			return
		end
		table.insert(slabs, solidPart("Ceiling", Vector3.new(x1 - x0, 1, z1 - z0), CFrame.new((x0 + x1) / 2, y + 0.5, (z0 + z1) / 2), color or COLORS.Ceiling))
	end
	if not skylight then
		slab(area.minX, area.maxX, area.minZ, area.maxZ)
		return slabs
	end
	local s = skylight
	slab(area.minX, area.maxX, area.minZ, s.minZ)
	slab(area.minX, area.maxX, s.maxZ, area.maxZ)
	slab(area.minX, s.minX, s.minZ, s.maxZ)
	slab(s.maxX, area.maxX, s.minZ, s.maxZ)
	local width, depth = s.maxX - s.minX, s.maxZ - s.minZ
	local centerX, centerZ = (s.minX + s.maxX) / 2, (s.minZ + s.maxZ) / 2
	local glass = solidPart(glassName or "HallSkylight", Vector3.new(width, 0.3, depth), CFrame.new(centerX, y + 0.85, centerZ), COLORS.Glass, Enum.Material.Glass)
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
		local z = s.minZ + depth * i / 4
		decorPart("SkylightBar", Vector3.new(width, 0.3, 0.25), CFrame.new(centerX, y + 0.7, z), COLORS.Gold, Enum.Material.Metal)
	end
	return slabs
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
	local base = solidPart("Column", Vector3.new(2.8, 0.8, 2.8), CFrame.new(x, 0.4, z), color, material)
	base:SetAttribute("MapObstacle", true)
	local shaftHeight = height - 1.6
	local shaft = solidPart("ColumnShaft", Vector3.new(shaftHeight, 2, 2), CFrame.new(x, 0.8 + shaftHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	shaft.Shape = Enum.PartType.Cylinder
	solidPart("ColumnTop", Vector3.new(2.8, 0.8, 2.8), CFrame.new(x, height - 0.4, z), color, material)
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

-- Люстра: горит только днём (MapBuilder.setDayLights). drop — на сколько висит ниже потолка.
local function chandelier(x: number, z: number, ceilingY: number, drop: number?)
	local settings = Config.Lighting.Chandelier
	local hangY = ceilingY - (drop or 3.2)
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
	local pot = solidPart("PlantPot", Vector3.new(1.6, 2, 2), CFrame.new(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Terracotta)
	pot.Shape = Enum.PartType.Cylinder
	local leaves = decorPart("Leaves", Vector3.new(2.8, 2.8, 2.8), CFrame.new(x, 2.8, z), COLORS.Leaves, Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	local top = decorPart("Leaves", Vector3.new(1.9, 1.9, 1.9), CFrame.new(x + 0.3, 4, z - 0.2), COLORS.LeavesLight, Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

-- Лампа на стене: светящаяся планка + точечный свет. Ночью это почти единственный свет в залах.
local function newLamp(parent: Instance, position: Vector3, size: Vector3, settings: { Range: number, Brightness: number, Color: Color3 }): Part
	local lamp = newPart(parent, "Lamp", size, CFrame.new(position), settings.Color, Enum.Material.Neon)
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = settings.Range
	light.Brightness = settings.Brightness
	light.Color = settings.Color
	light.Parent = lamp
	if settings == Config.Lighting.NightLamp then
		lamp:SetAttribute("NightLamp", true) -- дежурная лампа: гаснет в блэкаут (BlackoutService)
	end
	return lamp
end

---------------------------------------------------------------- комнаты

export type RoomSpec = {
	name: string,
	rect: Rect, -- пол внутри стен
	height: number,
	style: WallStyle,
	floorColor: Color3,
	floorMaterial: Enum.Material,
	hall: string?, -- атрибут Hall у пола: схема, туристы, открыт ли зал (nil — не часть музея)
	wander: boolean?, -- false — туристы сюда не ходят (служебные помещения)
	skylight: Rect?,
	skylightName: string?, -- имя стекла (MapSchema.Skylight — только у центра)
	ceilingColor: Color3?,
	lampSpacing: number?, -- шаг дежурных ламп по длинным стенам; 0 — без ламп
	area: string?, -- название места для надписей (атрибут Area у пола): «CENTER HALL», «SOUTH CORRIDOR»
}

type BuiltRoom = { rect: Rect, kind: string }
local builtRooms: { BuiltRoom } = {} -- для схемы на стенде MUSEUM MAP

-- Комната: пол, 4 стены с отделкой изнутри и проёмами, потолок, дежурные лампы. Возвращает пол и плиты потолка.
local function buildRoom(spec: RoomSpec, kind: string?): (Part, { Part })
	local r = spec.rect
	local h = spec.height
	local floor = solidPart(
		spec.name .. "Floor",
		Vector3.new(r.maxX - r.minX + 2, 1, r.maxZ - r.minZ + 2),
		CFrame.new((r.minX + r.maxX) / 2, -0.5, (r.minZ + r.maxZ) / 2),
		spec.floorColor,
		spec.floorMaterial
	)
	if spec.hall then
		floor:SetAttribute("Hall", spec.hall) -- по этим полам рисуется схема и гуляют туристы
	end
	if spec.wander == false then
		floor:SetAttribute("Wander", false)
	end
	if spec.area then
		floor:SetAttribute(MapSchema.AreaAttribute, spec.area) -- «GLASS ALARM — WEST CORRIDOR!» (блок 3)
	end
	table.insert(builtRooms, { rect = r, kind = kind or spec.hall or "Main" })

	local walls = {
		{ axis = "X", fixed = r.minZ - 0.5, from = r.minX - 1, to = r.maxX + 1, side = 1, dmin = r.minX, dmax = r.maxX },
		{ axis = "X", fixed = r.maxZ + 0.5, from = r.minX - 1, to = r.maxX + 1, side = -1, dmin = r.minX, dmax = r.maxX },
		{ axis = "Z", fixed = r.minX - 0.5, from = r.minZ, to = r.maxZ, side = 1, dmin = r.minZ, dmax = r.maxZ },
		{ axis = "Z", fixed = r.maxX + 0.5, from = r.minZ, to = r.maxZ, side = -1, dmin = r.minZ, dmax = r.maxZ },
	}
	local spacing = spec.lampSpacing or 24
	local longX = (r.maxX - r.minX) >= (r.maxZ - r.minZ)
	local lampY = math.min(10, h - 4)
	for index, w in walls do
		local openings = openingsFor(w.axis, w.fixed, w.from, w.to)
		newWall(w.axis, w.fixed, w.from, w.to, h, {
			openings = openings,
			neg = if w.side < 0 then spec.style else nil,
			pos = if w.side > 0 then spec.style else nil,
			decorMin = w.dmin,
			decorMax = w.dmax,
		})
		-- Дежурные лампы по длинным стенам, на второй стене со сдвигом на полшага
		if spacing > 0 and (w.axis == "X") == longX then
			local length = w.dmax - w.dmin
			local count = math.max(1, math.floor(length / spacing))
			local shift = if index % 2 == 0 and count > 1 then 0.25 else 0
			for i = 1, count do
				local along = w.dmin + length * math.clamp((i - 0.5) / count + shift / count, 0.05, 0.95)
				if not insideOpening(openings, along, 2) then
					local face = w.fixed + w.side * (WALL_T / 2 + 0.2)
					local position = if w.axis == "X" then Vector3.new(along, lampY, face) else Vector3.new(face, lampY, along)
					local size = if w.axis == "X" then Vector3.new(1.6, 0.4, 0.3) else Vector3.new(0.3, 0.4, 1.6)
					newLamp(propsFolder, position, size, Config.Lighting.NightLamp)
				end
			end
		end
	end
	local slabs = ceiling(rect(r.minX - 1, r.maxX + 1, r.minZ - 1, r.maxZ + 1), h, spec.skylight, spec.ceilingColor, spec.skylightName)
	return floor, slabs
end

-- Точка на внутренней поверхности стены комнаты r: side — "N" (−Z), "S" (+Z), "W" (−X), "E" (+X).
local function onWall(r: Rect, side: string, along: number, y: number): (Vector3, Vector3)
	if side == "N" then
		return Vector3.new(along, y, r.minZ), Vector3.new(0, 0, 1)
	elseif side == "S" then
		return Vector3.new(along, y, r.maxZ), Vector3.new(0, 0, -1)
	elseif side == "W" then
		return Vector3.new(r.minX, y, along), Vector3.new(1, 0, 0)
	end
	return Vector3.new(r.maxX, y, along), Vector3.new(-1, 0, 0)
end

-- Картина на стене комнаты (wallPainting ждёт точку на средней линии стены).
local function paintingOn(r: Rect, side: string, along: number, y: number, width: number, height: number)
	local point, facing = onWall(r, side, along, y)
	wallPainting(point - facing * (WALL_T / 2), facing, width, height)
end

---------------------------------------------------------------- модели-заглушки

-- Банкетка без спинки: тёмно-синее сиденье, золотая рама и ножки (в залах и в лобби)
local BENCH_STUB: { ModelLibrary.StubPart } = {
	{ size = Vector3.new(6, 0.5, 2), offset = CFrame.new(0, 1.35, 0), color = COLORS.Navy, material = Enum.Material.Fabric },
	{ size = Vector3.new(6.2, 0.2, 2.2), offset = CFrame.new(0, 1, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(-2.8, 0.45, -0.8), color = COLORS.Gold, material = Enum.Material.Metal },
	{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(2.8, 0.45, -0.8), color = COLORS.Gold, material = Enum.Material.Metal },
	{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(-2.8, 0.45, 0.8), color = COLORS.Gold, material = Enum.Material.Metal },
	{ size = Vector3.new(0.3, 0.9, 0.3), offset = CFrame.new(2.8, 0.45, 0.8), color = COLORS.Gold, material = Enum.Material.Metal },
}

-- Створка входной двери: стекло в золотой раме, ручка у внутреннего края (+X). Низ по центру.
local ENTRANCE_DOOR_STUB: { ModelLibrary.StubPart } = {
	{ name = "StileOuter", size = Vector3.new(0.45, DOOR_H, 0.4), offset = CFrame.new(-2.275, DOOR_H / 2, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "StileInner", size = Vector3.new(0.45, DOOR_H, 0.4), offset = CFrame.new(2.275, DOOR_H / 2, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "RailTop", size = Vector3.new(4.1, 0.5, 0.4), offset = CFrame.new(0, DOOR_H - 0.25, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "RailBottom", size = Vector3.new(4.1, 0.9, 0.4), offset = CFrame.new(0, 0.45, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "RailMiddle", size = Vector3.new(4.1, 0.3, 0.4), offset = CFrame.new(0, 3.2, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "GlassLow", size = Vector3.new(4.1, 2.15, 0.12), offset = CFrame.new(0, 1.975, 0), color = COLORS.Glass, material = Enum.Material.Glass, transparency = 0.55 },
	{ name = "GlassHigh", size = Vector3.new(4.1, 6.1, 0.12), offset = CFrame.new(0, 6.4, 0), color = COLORS.Glass, material = Enum.Material.Glass, transparency = 0.55 },
	{ name = "HandleIn", size = Vector3.new(0.18, 2.2, 0.18), offset = CFrame.new(1.7, 4.6, -0.35), color = COLORS.WhiteMarble, material = Enum.Material.Metal },
	{ name = "HandleOut", size = Vector3.new(0.18, 2.2, 0.18), offset = CFrame.new(1.7, 4.6, 0.35), color = COLORS.WhiteMarble, material = Enum.Material.Metal },
	{ name = "Emblem", size = Vector3.new(1.2, 1.2, 0.14), offset = CFrame.new(0, 6.4, 0), color = COLORS.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
}

-- Створка двери STAFF ONLY: серый металл, окошко, табличка, ручка. Низ по центру.
local STAFF_DOOR_STUB: { ModelLibrary.StubPart } = {
	{ name = "Panel", size = Vector3.new(5.8, OPENING_H - 0.2, 0.3), offset = CFrame.new(0, (OPENING_H - 0.2) / 2, 0), color = hex("6E7686"), material = Enum.Material.Metal },
	{ name = "Window", size = Vector3.new(1.6, 1.6, 0.34), offset = CFrame.new(0, 6.4, 0), color = COLORS.Glass, material = Enum.Material.Glass, transparency = 0.4 },
	{ name = "KickPlate", size = Vector3.new(5.4, 1.1, 0.36), offset = CFrame.new(0, 0.75, 0), color = hex("4A5060"), material = Enum.Material.DiamondPlate },
	{ name = "Stripe", size = Vector3.new(5.8, 0.4, 0.34), offset = CFrame.new(0, 4.2, 0), color = hex("F2C230") },
	{ name = "Handle", size = Vector3.new(0.9, 0.2, 0.2), offset = CFrame.new(2.1, 4.2, -0.3), color = COLORS.WhiteMarble, material = Enum.Material.Metal },
}

-- Витрина-укрытие: тумба тёмного дерева с золотой каймой и стеклянный короб. Низ по центру, 4 × 2.
local DISPLAY_CASE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Base", size = Vector3.new(4, 2.4, 2), offset = CFrame.new(0, 1.2, 0), color = COLORS.DarkWood, material = Enum.Material.Wood },
	{ name = "Plinth", size = Vector3.new(4.2, 0.3, 2.2), offset = CFrame.new(0, 0.15, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "Trim", size = Vector3.new(4.2, 0.2, 2.2), offset = CFrame.new(0, 2.5, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "Velvet", size = Vector3.new(3.6, 0.1, 1.6), offset = CFrame.new(0, 2.65, 0), color = COLORS.Velvet, material = Enum.Material.Fabric },
	{ name = "Glass", size = Vector3.new(3.8, 1.7, 1.8), offset = CFrame.new(0, 3.45, 0), color = COLORS.Glass, material = Enum.Material.Glass, transparency = 0.75 },
	{ name = "Lid", size = Vector3.new(4, 0.15, 2), offset = CFrame.new(0, 4.37, 0), color = COLORS.Gold, material = Enum.Material.Metal },
}

-- Стойка TICKETS во входном холле: деревянный прилавок с мраморной столешницей. Перед — к посетителю (−Z).
local RECEPTION_STUB: { ModelLibrary.StubPart } = {
	{ name = "Counter", size = Vector3.new(8, 3.2, 2.4), offset = CFrame.new(0, 1.6, 0), color = COLORS.DarkWood, material = Enum.Material.Wood },
	{ name = "Top", size = Vector3.new(8.4, 0.3, 2.8), offset = CFrame.new(0, 3.35, -0.1), color = COLORS.Marble, material = Enum.Material.Marble },
	{ name = "Front", size = Vector3.new(7.6, 2, 0.1), offset = CFrame.new(0, 1.6, -1.25), color = COLORS.Velvet, material = Enum.Material.Fabric },
	{ name = "Trim", size = Vector3.new(8.1, 0.2, 2.5), offset = CFrame.new(0, 0.1, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	{ name = "Register", size = Vector3.new(1.2, 0.8, 1), offset = CFrame.new(2.4, 3.9, 0.3), color = COLORS.Dark },
	{ name = "RegisterScreen", size = Vector3.new(0.9, 0.5, 0.1), offset = CFrame.new(2.4, 4.2, -0.2), color = COLORS.Turquoise, material = Enum.Material.Neon },
	{ name = "Brochures", size = Vector3.new(1.4, 0.5, 0.9), offset = CFrame.new(-2.6, 3.75, -0.4), color = hex("F2C230") },
	{ name = "Bell", size = Vector3.new(0.5, 0.5, 0.5), offset = CFrame.new(0, 3.75, -0.6), color = COLORS.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
}

-- Щиток POWER: металлический шкаф у стены, дверца с молнией, рубильники. Задник на z = 0, перед в −Z.
local FUSEBOX_STUB: { ModelLibrary.StubPart } = {
	{ name = "Cabinet", size = Vector3.new(3, 4.4, 1), offset = CFrame.new(0, 2.6, -0.5), color = hex("6E7686"), material = Enum.Material.Metal },
	{ name = "Door", size = Vector3.new(2.6, 3.4, 0.1), offset = CFrame.new(0, 2.9, -1.05), color = hex("8A93A6"), material = Enum.Material.Metal },
	{ name = "Bolt", size = Vector3.new(0.2, 0.6, 0.2), offset = CFrame.new(1.05, 2.9, -1.15), color = COLORS.Dark },
	{ name = "Warning", size = Vector3.new(1.2, 1.2, 0.05), offset = CFrame.new(0, 3.6, -1.12), color = hex("F2C230") },
	{ name = "Lever", size = Vector3.new(0.3, 1.2, 0.3), offset = CFrame.new(1.8, 3, -0.6) * CFrame.Angles(0, 0, math.rad(-20)), color = COLORS.Red, material = Enum.Material.Metal },
	{ name = "Pipe", size = Vector3.new(0.4, 4, 0.4), offset = CFrame.new(-1, 6.8, -0.3), color = hex("4A5060"), material = Enum.Material.Metal },
	{ name = "Lamp", size = Vector3.new(0.4, 0.4, 0.2), offset = CFrame.new(-0.9, 4.5, -1.1), color = hex("3FB56B"), material = Enum.Material.Neon },
	{ name = "Feet", size = Vector3.new(3.2, 0.4, 1.1), offset = CFrame.new(0, 0.2, -0.55), color = hex("2B2F3A"), material = Enum.Material.Metal },
}

-- Пустая оружейная стойка у стены (товары — блок 4): задняя панель, крючки, полка. Задник на z = 0.
local WEAPON_RACK_STUB: { ModelLibrary.StubPart } = {
	{ name = "Board", size = Vector3.new(8, 5, 0.3), offset = CFrame.new(0, 4, -0.15), color = hex("2B2F3A"), material = Enum.Material.Metal },
	{ name = "Frame", size = Vector3.new(8.4, 0.3, 0.5), offset = CFrame.new(0, 6.6, -0.25), color = COLORS.Red, material = Enum.Material.Metal },
	{ name = "Shelf", size = Vector3.new(8, 0.3, 1.2), offset = CFrame.new(0, 1.4, -0.6), color = hex("4A5060"), material = Enum.Material.Metal },
	{ name = "Leg", size = Vector3.new(0.3, 1.4, 0.3), offset = CFrame.new(-3.8, 0.7, -1), color = hex("4A5060"), material = Enum.Material.Metal },
	{ name = "Leg", size = Vector3.new(0.3, 1.4, 0.3), offset = CFrame.new(3.8, 0.7, -1), color = hex("4A5060"), material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(-2.7, 5.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(-0.9, 5.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(0.9, 5.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(2.7, 5.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(-2.7, 3.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(-0.9, 3.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(0.9, 3.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
	{ name = "Hook", size = Vector3.new(0.2, 0.2, 0.7), offset = CFrame.new(2.7, 3.4, -0.5), color = COLORS.Metal, material = Enum.Material.Metal },
}

---------------------------------------------------------------- набор помощников для украшений залов (MapDecor)

local function makeKit(): MapDecor.Kit
	return {
		colors = COLORS,
		styles = STYLES,
		dayLight = DAY_LIGHT,
		hallHeight = HALL_H,
		solid = solidPart,
		decor = decorPart,
		column = column,
		plant = plant,
		chandelier = chandelier,
		painting = wallPainting,
		textOn = textOn,
		surfaceGui = surfaceGui,
		guiFrame = guiFrame,
		corner = corner,
		lamp = function(position: Vector3, size: Vector3, settings: { Range: number, Brightness: number, Color: Color3 }): Part
			return newLamp(propsFolder, position, size, settings)
		end,
		place = placeModel,
		sign = wallSign,
		displayCase = DISPLAY_CASE_STUB,
		bench = BENCH_STUB,
	}
end

-- Помощники для комнаты другого места (хаб, блок 6): те же стены с отделкой, потолки, лампы, растения,
-- таблички, банкетки и модели, что в музее, — чтобы хаб был того же качества и ничего не дублировалось.
export type RoomKit = {
	kit: MapDecor.Kit,
	props: Folder,
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	marker: (parent: Instance, name: string, cframe: CFrame) -> Part,
	room: (spec: RoomSpec, kind: string?) -> (Part, { Part }),
	wall: (axis: string, fixed: number, from: number, to: number, height: number, options: WallOptions?) -> (),
	checker: (area: Rect, tile: number, color: Color3) -> (),
	rect: (minX: number, maxX: number, minZ: number, maxZ: number) -> Rect,
	onWall: (r: Rect, side: string, along: number, y: number) -> (Vector3, Vector3),
	paintingOn: (r: Rect, side: string, along: number, y: number, width: number, height: number) -> (),
	wallThickness: number,
}

-- root — папка карты (Workspace.Map): в ней появятся папки Geometry, Decor и Props.
function MapBuilder.newKit(root: Folder): RoomKit
	geometryFolder = newFolder(root, MapSchema.Geometry)
	decorFolder = newFolder(root, "Decor")
	propsFolder = newFolder(root, MapSchema.Props)
	return {
		kit = makeKit(),
		props = propsFolder,
		part = newPart,
		marker = newMarker,
		room = buildRoom,
		wall = newWall,
		checker = checkerTiles,
		rect = rect,
		onWall = onWall,
		paintingOn = paintingOn,
		wallThickness = WALL_T,
	}
end

---------------------------------------------------------------- Мона Лиза

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

local function buildMonaLisaPainting(map: Folder, exhibits: Folder, markers: Folder)
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

---------------------------------------------------------------- центр

local function buildCenter(map: Folder, exhibits: Folder, markers: Folder)
	local main = STYLES.Main
	buildRoom({
		name = "Center",
		rect = CENTER,
		height = CENTER_H,
		style = main,
		floorColor = COLORS.Marble,
		floorMaterial = Enum.Material.Marble,
		hall = GameState.Hall.Main,
		skylight = SKYLIGHT,
		skylightName = MapSchema.Skylight, -- стекольщики режут его в блоке 3
		lampSpacing = 22,
		area = "CENTER HALL",
	}, "Center")
	checkerTiles(CENTER, 11, COLORS.MarbleDark)

	-- Стена в самом центре из тёмно-красного бархата, на ней Мона Лиза (лицом на юг)
	local displayWall = solidPart("DisplayWall", Vector3.new(24, 12, 2), CFrame.new(0, 6, 0), COLORS.Velvet, Enum.Material.Fabric)
	displayWall:SetAttribute("MapObstacle", true)
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
	-- Колонны по бокам и бархатный навес над стеной: «храм» для Моны Лизы
	for _, x in { -14.2, 14.2 } do
		column(x, 0, 13, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	decorPart("DisplayCanopy", Vector3.new(31.6, 1.2, 3.4), CFrame.new(0, 13.6, 0), COLORS.VelvetDark, Enum.Material.Fabric)
	for _, y in { 13.05, 14.25 } do
		decorPart("DisplayCanopyTrim", Vector3.new(32, 0.25, 3.8), CFrame.new(0, y, 0), COLORS.Gold, Enum.Material.Metal)
	end

	buildMonaLisaPainting(map, exhibits, markers)

	-- Балкон вдоль северной стены: пол на высоте 12, золотой край, колонны снизу
	solidPart(MapSchema.Balcony, Vector3.new(88, 1, 14), CFrame.new(0, BALCONY_Y - 0.5, -37), COLORS.Parquet, Enum.Material.WoodPlanks)
	decorPart("BalconyUnderside", Vector3.new(88, 0.1, 14), CFrame.new(0, BALCONY_Y - 1.05, -37), COLORS.Ceiling)
	decorPart("BalconyFascia", Vector3.new(88, 1.4, 0.5), CFrame.new(0, BALCONY_Y - 0.6, -29.8), COLORS.Gold, Enum.Material.Metal)
	for _, x in { -28, -14, 14, 28 } do
		column(x, -31.6, BALCONY_Y - 1, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	-- Перила балкона: золотые стойки, стекло (не упасть) и поручень. По краям — выход на лестницы.
	for x = -36, 36, 4 do
		decorPart("RailPost", Vector3.new(0.3, 3.4, 0.3), CFrame.new(x, BALCONY_Y + 1.7, -30.4), COLORS.Gold, Enum.Material.Metal)
	end
	local railGlass = solidPart("RailGlass", Vector3.new(76, 2.8, 0.15), CFrame.new(0, BALCONY_Y + 1.5, -30.4), COLORS.Glass, Enum.Material.Glass)
	railGlass.Transparency = 0.7
	railGlass.CastShadow = false
	decorPart("RailTop", Vector3.new(76.4, 0.3, 0.45), CFrame.new(0, BALCONY_Y + 3.45, -30.4), COLORS.Gold, Enum.Material.Metal)

	-- Две лестницы у западной и восточной стен: 20 ступеней с красным ковром, поручень
	for _, sign in { -1, 1 } do
		local x = sign * 41
		for i = 1, STAIR_STEPS do
			local top = BALCONY_Y * i / STAIR_STEPS
			local z = -10 - (i - 0.5)
			solidPart("Stair", Vector3.new(6, top, 1), CFrame.new(x, top / 2, z), COLORS.Marble, Enum.Material.Marble)
			decorPart("StairCarpet", Vector3.new(3.6, 0.06, 1), CFrame.new(x, top + 0.03, z), COLORS.Red, Enum.Material.Fabric)
		end
		local railX = sign * 38.2
		for i = 2, STAIR_STEPS, 6 do
			decorPart("StairPost", Vector3.new(0.3, 3.4, 0.3), CFrame.new(railX, BALCONY_Y * i / STAIR_STEPS + 1.7, -10 - (i - 0.5)), COLORS.Gold, Enum.Material.Metal)
		end
		local p0 = Vector3.new(railX, BALCONY_Y / STAIR_STEPS + 3.4, -10.5)
		local p1 = Vector3.new(railX, BALCONY_Y + 3.4, -29.5)
		decorPart("StairRail", Vector3.new(0.3, 0.3, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), COLORS.Gold, Enum.Material.Metal)
	end

	-- Пульт камер на балконе у северной стены, над ним стена мониторов. Справа от пульта ~3 стада
	-- свободно: там CameraService ставит рубильник CAMERA RESET.
	local console = newPart(map, MapSchema.ControlConsole, Vector3.new(10, 3, 3), CFrame.new(0, BALCONY_Y + 1.5, -42), hex("2B2F3A"), Enum.Material.Metal)
	decorPart("ConsoleDesk", Vector3.new(10.4, 0.3, 3.4), CFrame.new(0, BALCONY_Y + 3.15, -41.9), COLORS.DarkWood, Enum.Material.Wood)
	decorPart("ConsolePanel", Vector3.new(8, 0.2, 1.4), CFrame.new(0, BALCONY_Y + 3.45, -42.6) * CFrame.Angles(math.rad(20), 0, 0), COLORS.Navy)
	for i = -3, 3 do
		local color = if i % 3 == 0 then COLORS.Red elseif i % 2 == 0 then hex("3FB56B") else hex("F2C230")
		local button = decorPart("ConsoleButton", Vector3.new(0.4, 0.15, 0.4), CFrame.new(i * 1.05, BALCONY_Y + 3.65, -42.4) * CFrame.Angles(math.rad(20), 0, 0), color, Enum.Material.Neon)
		button.Shape = Enum.PartType.Cylinder
	end
	decorPart("MonitorWall", Vector3.new(11.4, 5, 0.3), CFrame.new(0, BALCONY_Y + 6.6, -43.85), hex("15181F"), Enum.Material.Metal)
	for row = 0, 1 do
		for col = -1, 1 do
			local screen = decorPart("Monitor", Vector3.new(3.4, 2, 0.1), CFrame.new(col * 3.6, BALCONY_Y + 5.4 + row * 2.4, -43.65), hex("1E5C5A"), Enum.Material.Neon)
			local label = textOn(screen, Enum.NormalId.Back, ("CAM %d"):format(row * 3 + col + 2), COLORS.Turquoise, 0)
			label.TextTransparency = 0.2
		end
	end
	local chair = {
		{ size = Vector3.new(2.2, 0.4, 2.2), offset = CFrame.new(0, 1.9, 0), color = COLORS.Dark, material = Enum.Material.Fabric },
		{ size = Vector3.new(2.2, 2.2, 0.4), offset = CFrame.new(0, 3.1, 1), color = COLORS.Dark, material = Enum.Material.Fabric },
		{ size = Vector3.new(0.4, 1.7, 0.4), offset = CFrame.new(0, 0.85, 0), color = COLORS.Metal, material = Enum.Material.Metal },
		{ size = Vector3.new(1.8, 0.2, 1.8), offset = CFrame.new(0, 0.1, 0), color = COLORS.Metal, material = Enum.Material.Metal },
	}
	placeModel(MapSchema.Models.Chair, CFrame.new(-2.5, BALCONY_Y, -38.2), chair, false)
	console:SetAttribute("MapObstacle", true)

	-- Канатное ограждение перед Моной Лизой, с проходом посередине
	local barrier = {
		{ size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(-1.8, 1.5, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(1.8, 1.5, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(3.6, 0.25, 0.25), offset = CFrame.new(0, 2.5, 0), color = COLORS.Red, material = Enum.Material.Fabric },
	}
	placeModel(MapSchema.Models.Barrier, CFrame.new(-5, 0, 7.5), barrier)
	placeModel(MapSchema.Models.Barrier, CFrame.new(5, 0, 7.5), barrier)
	for _, x in { -11, 11 } do -- по бокам от ковровой дорожки, лицом к картине
		placeModel(MapSchema.Models.Bench, CFrame.new(x, 0, 24), BENCH_STUB)
	end
	placeModel(MapSchema.Models.Bench, CFrame.new(0, 0, -16), BENCH_STUB)
	-- Ковровая дорожка от южной арки к Моне Лизе
	decorPart("Carpet", Vector3.new(4, 0.05, 34), CFrame.new(0, 0.03, 27), COLORS.Red, Enum.Material.Fabric)
	for _, x in { -2.1, 2.1 } do
		decorPart("CarpetEdge", Vector3.new(0.3, 0.06, 34), CFrame.new(x, 0.035, 27), COLORS.Gold, Enum.Material.Fabric)
	end

	-- Картины, люстры, растения
	local c = CENTER
	for _, x in { -26, 26 } do
		paintingOn(c, "S", x, 7, 7, 5)
		paintingOn(c, "N", x, 5.5, 6, 3.5) -- под балконом
		paintingOn(c, "N", x, 18.5, 8, 5) -- над балконом
	end
	paintingOn(c, "S", 0, 18, 12, 7)
	for _, side in { "W", "E" } do
		paintingOn(c, side, 24, 7, 7, 5)
		paintingOn(c, side, 0, 18, 10, 6)
	end
	chandelier(-28, 16, CENTER_H, 7)
	chandelier(28, 16, CENTER_H, 7)
	chandelier(0, 32, CENTER_H, 7)
	for _, spot in { { -40, 40 }, { 40, 40 }, { -40, 14 }, { 40, 14 } } do
		plant(spot[1], spot[2])
	end
end

---------------------------------------------------------------- крылья: входной холл и коридор

-- Ковровая дорожка по осевой линии коридора (в координатах крыла T).
local function carpetPath(T: CFrame)
	for i = 1, #WING_PATH - 1 do
		local a, b = WING_PATH[i], WING_PATH[i + 1]
		local length = (b - a).Magnitude + 4 -- +4: углы дорожки перекрываются
		local mid = (a + b) / 2
		local along = Vector3.new(b.X - a.X, 0, b.Y - a.Y).Unit
		local base = T * CFrame.lookAt(Vector3.new(mid.X, 0.03, mid.Y), Vector3.new(mid.X, 0.03, mid.Y) + along)
		decorPart("Carpet", Vector3.new(4, 0.05, length), base, COLORS.Red, Enum.Material.Fabric)
		for _, side in { -2.1, 2.1 } do
			decorPart("CarpetEdge", Vector3.new(0.3, 0.06, length - 4), base * CFrame.new(side, 0.005, 0), COLORS.Gold, Enum.Material.Fabric)
		end
	end
end

local function buildWing(k: number, doorsFolder: Folder)
	local T = turn(k)
	local side = SIDE_NAMES[k]
	local main = GameState.Hall.Main
	local function at(x: number, y: number, z: number): Vector3
		return T * Vector3.new(x, y, z)
	end
	local function dir(x: number, z: number): Vector3
		return T:VectorToWorldSpace(Vector3.new(x, 0, z))
	end

	local lobby = rotRect(k, WING.Lobby)
	buildRoom({ name = side .. "Lobby", rect = lobby, height = LOBBY_H, style = STYLES.Lobby, floorColor = COLORS.Marble, floorMaterial = Enum.Material.Marble, hall = main, lampSpacing = 30, area = string.upper(side) .. " ENTRANCE" }, "Lobby")
	checkerTiles(lobby, 4, hex("C9BBA0"))
	for _, key in { "C1", "C2", "C3" } do
		buildRoom({ name = side .. "Corridor", rect = rotRect(k, WING[key]), height = CORRIDOR_H, style = STYLES.Corridor, floorColor = COLORS.Parquet, floorMaterial = Enum.Material.WoodPlanks, hall = main, lampSpacing = 20, area = string.upper(side) .. " CORRIDOR" }, "Corridor")
	end
	carpetPath(T)

	-- Входной холл (местные координаты: x от −14 до 46, z от 110 до 129, дверь в южной стене)
	decorPart("WelcomeMat", Vector3.new(9, 0.06, 4), T * CFrame.new(0, 0.04, 126.5), hex("7A1E24"), Enum.Material.Fabric)
	placeModel(MapSchema.Models.Reception, T * CFrame.lookAt(Vector3.new(-10, 0, 118), Vector3.new(-9, 0, 118)), RECEPTION_STUB)
	wallSign(at(-14, 9, 118), dir(1, 0), 6, 1.6, "TICKETS  $" .. Config.Money.TicketPrice)
	placeModel(MapSchema.Models.Bench, T * CFrame.new(16, 0, 112.4), BENCH_STUB)
	for _, spot in { { -12, 127 }, { 44, 127 }, { 26, 112 }, { -4, 111.5 } } do
		local p = at(spot[1], 0, spot[2])
		plant(p.X, p.Z)
	end
	wallSign(at(0, 11.6, 129), dir(0, -1), 3.4, 1.2, "EXIT", hex("FFFFFF"), COLORS.ExitGreen)
	wallSign(at(40, 12.6, 110), dir(0, 1), 7, 1.4, "▲  MONA LISA", COLORS.Gold)
	wallSign(at(-14, 12.5, 124), dir(1, 0), 7, 1.2, string.upper(side) .. " ENTRANCE", COLORS.Gold)
	local lobbyArea = WING.Lobby
	for _, x in { 20, 34 } do
		local point, facing = onWall(lobbyArea, "S", x, 7)
		wallPainting(at(point.X, point.Y, point.Z) - dir(facing.X, facing.Z) * 0.5, dir(facing.X, facing.Z), 6, 4.5)
	end
	do
		local point, facing = onWall(lobbyArea, "E", 120, 7)
		wallPainting(at(point.X, point.Y, point.Z) - dir(facing.X, facing.Z) * 0.5, dir(facing.X, facing.Z), 6, 4.5)
	end
	local chandelierPoint = at(14, 0, 119.5)
	chandelier(chandelierPoint.X, chandelierPoint.Z, LOBBY_H, 3.6)

	-- Коридор C1 (x от 34 до 46, z от 86 до 108): витрина у западной стены
	placeModel(MapSchema.Models.DisplayCase, T * CFrame.lookAt(Vector3.new(35.2, 0, 97), Vector3.new(36.2, 0, 97)), DISPLAY_CASE_STUB):SetAttribute("MapObstacle", true)
	local function paint(area: Rect, wallSide: string, along: number)
		local point, facing = onWall(area, wallSide, along, 7)
		wallPainting(at(point.X, point.Y, point.Z) - dir(facing.X, facing.Z) * 0.5, dir(facing.X, facing.Z), 5, 3.8)
	end
	paint(WING.C1, "W", 89)
	paint(WING.C1, "W", 105)
	paint(WING.C1, "E", 91)

	-- Коридор C2 (x от −6 до 46, z от 72 до 84): «ворота» из двух колонн, витрины по разные стороны, банкетка
	for _, z in { 73.5, 82.5 } do
		local p = at(20, 0, z)
		column(p.X, p.Z, CORRIDOR_H, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	placeModel(MapSchema.Models.DisplayCase, T * CFrame.lookAt(Vector3.new(31, 0, 73.2), Vector3.new(31, 0, 74.2)), DISPLAY_CASE_STUB):SetAttribute("MapObstacle", true)
	placeModel(MapSchema.Models.DisplayCase, T * CFrame.lookAt(Vector3.new(9, 0, 82.8), Vector3.new(9, 0, 81.8)), DISPLAY_CASE_STUB):SetAttribute("MapObstacle", true)
	placeModel(MapSchema.Models.Bench, T * CFrame.new(32, 0, 82.8), BENCH_STUB)
	paint(WING.C2, "N", 12)
	paint(WING.C2, "N", 40)
	paint(WING.C2, "S", 0)
	paint(WING.C2, "S", 22)
	for _, spot in { { -4, 82.4 }, { 44, 73.6 } } do
		local p = at(spot[1], 0, spot[2])
		plant(p.X, p.Z)
	end

	-- Коридор C3 (x от −6 до 6, z от 46 до 70): банкетка у восточной стены, табличка над аркой в центр
	placeModel(MapSchema.Models.Bench, T * CFrame.new(4.8, 0, 64) * CFrame.Angles(0, math.rad(90), 0), BENCH_STUB)
	paint(WING.C3, "E", 54)
	paint(WING.C3, "W", 66)
	wallSign(at(0, 12.4, 46), dir(0, 1), 6, 1.2, "▲  MONA LISA", COLORS.Gold)
	-- Изнутри центра над аркой — куда она ведёт
	wallSign(at(0, 12.6, 44), dir(0, -1), 7, 1.2, string.upper(side) .. " EXIT", COLORS.Gold)

	-- Дверь входа: две стеклянные створки, разъезжаются в стену, когда рядом кто-то есть (DoorService)
	local door = Instance.new("Model")
	door.Name = side .. "Door"
	door:SetAttribute(GameState.DoorAttr.Open, false)
	local base = T * CFrame.new(0, 0, HALF)
	for _, s in { -1, 1 } do
		local leafPivot = base * CFrame.new(s * DOOR_HALF / 2, 0, 0) * (if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		local leaf = ModelLibrary.place(MapSchema.Models.EntranceDoor, leafPivot, ENTRANCE_DOOR_STUB, door)
		leaf.Name = if s < 0 then "LeafLeft" else "LeafRight"
		leaf:SetAttribute(GameState.DoorAttr.SlideX, -DOOR_HALF)
		ModelLibrary.forEachPart(leaf, function(part)
			part.CanCollide = false -- дверь всегда успевает открыться; так она не мешает путям воров
			part.CanQuery = false
			part.CanTouch = false
		end)
	end
	door.WorldPivot = base
	door.Parent = doorsFolder

end

local function addWingDoorways(k: number)
	addDoorway(k, -DOOR_HALF, HALF, DOOR_HALF, HALF, DOOR_H) -- входная дверь (холл + наружная стена)
	addDoorway(k, 34, 109, 46, 109, ARCH_H) -- холл → C1
	addDoorway(k, 34, 85, 46, 85, ARCH_H) -- C1 → C2
	addDoorway(k, -6, 71, 6, 71, ARCH_H) -- C2 → C3
	addDoorway(k, -6, 45, 6, 45, ARCH_H) -- C3 → центр
	addDoorway(k, HALL_DOOR.x, HALL_DOOR.z1, HALL_DOOR.x, HALL_DOOR.z2, OPENING_H) -- C3 → зал
end

---------------------------------------------------------------- залы за деньги

-- Заколоченная дверь: доски + щит, который не пускает, и табличка с ценой (текст пишет HallService).
-- Проём в двух стенах (коридор и зал), поэтому табличка на 1.15 стада впереди середины проёма.
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
	local sign = newPart(door, MapSchema.HallDoorSign, Vector3.new(6, 2.4, 0.2), cframe * CFrame.new(0, OPENING_H + 2, -1.15), COLORS.Dark)
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

-- Вид залов: стены, пол, потолок. Украшения — MapDecor.
local HALL_LOOK: { [string]: { floor: Color3, material: Enum.Material, ceiling: Color3?, skylight: Rect? } } = {
	Sculptures = { floor = COLORS.WhiteMarble, material = Enum.Material.Marble, skylight = rect(-70, -34, 62, 92) },
	Dinosaurs = { floor = hex("E2C48B"), material = Enum.Material.Sand, ceiling = hex("EADBC0") },
	Jewelry = { floor = COLORS.DarkWood, material = Enum.Material.WoodPlanks },
	Space = { floor = hex("232A40"), material = Enum.Material.SmoothPlastic, ceiling = hex("0B1024") },
}

local function buildHall(k: number, hallDoors: Folder, kit: MapDecor.Kit)
	local hall = WING_HALLS[k]
	local look = HALL_LOOK[hall]
	local T = turn(k)
	local _, slabs = buildRoom({
		name = hall,
		rect = rotRect(k, HALL_RECT),
		height = HALL_H,
		style = STYLES[hall],
		floorColor = look.floor,
		floorMaterial = look.material,
		hall = hall,
		skylight = if look.skylight then rotRect(k, look.skylight) else nil,
		ceilingColor = look.ceiling,
		lampSpacing = 28,
		area = (Config.Halls :: any)[hall].Title,
	}, hall)
	buildHallDoor(hallDoors, hall, T * Vector3.new(HALL_DOOR.x, 0, (HALL_DOOR.z1 + HALL_DOOR.z2) / 2), T:VectorToWorldSpace(Vector3.new(1, 0, 0)))
	MapDecor.hall(kit, hall, T, HALL_RECT, slabs)
end

---------------------------------------------------------------- постаменты

-- Постамент под каждый зал (модель одна — prop_pedestal_01, заглушка своя у каждого зала). Верх — 3.3.
local PEDESTAL_STUBS: { [string]: { ModelLibrary.StubPart } } = {
	Main = { -- мраморная тумба с золотым верхом
		{ size = Vector3.new(2.4, 3, 2.4), offset = CFrame.new(0, 1.5, 0), color = COLORS.Marble, material = Enum.Material.Marble },
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 3.15, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 0.15, 0), color = COLORS.Gold, material = Enum.Material.Metal },
	},
	Sculptures = { -- белая мраморная колонна-тумба на каменной базе
		{ size = Vector3.new(2.9, 0.5, 2.9), offset = CFrame.new(0, 0.25, 0), color = COLORS.Stone, material = Enum.Material.Marble },
		{ size = Vector3.new(2.2, 2.5, 2.2), offset = CFrame.new(0, 1.75, 0), color = COLORS.WhiteMarble, material = Enum.Material.Marble },
		{ size = Vector3.new(2.5, 0.15, 2.5), offset = CFrame.new(0, 2.85, 0), color = COLORS.Stone, material = Enum.Material.Marble },
		{ size = Vector3.new(2.9, 0.3, 2.9), offset = CFrame.new(0, 3.15, 0), color = COLORS.WhiteMarble, material = Enum.Material.Marble },
	},
	Dinosaurs = { -- глыба песчаника с каменной плитой, табличка, камешки
		{ size = Vector3.new(2.8, 2.9, 2.6), offset = CFrame.new(0, 1.45, 0), color = hex("C9A46A"), material = Enum.Material.Sandstone },
		{ size = Vector3.new(3.1, 0.4, 2.9), offset = CFrame.new(0, 3.1, 0), color = hex("8A7A5A"), material = Enum.Material.Slate },
		{ size = Vector3.new(1.4, 0.5, 0.06), offset = CFrame.new(0, 2.1, -1.33), color = COLORS.DarkWood, material = Enum.Material.Wood },
		{ size = Vector3.new(1.1, 0.7, 0.9), offset = CFrame.new(1.3, 0.35, -1.3) * CFrame.Angles(0, 0.5, 0), color = hex("8E8A80"), material = Enum.Material.Slate, collide = false },
		{ size = Vector3.new(0.7, 0.5, 0.6), offset = CFrame.new(-1.4, 0.25, -1.2) * CFrame.Angles(0, -0.4, 0), color = hex("A39E92"), material = Enum.Material.Slate, collide = false },
	},
	Jewelry = { -- тёмное дерево, золотые пояса, бархатная подушка
		{ size = Vector3.new(2.8, 0.25, 2.8), offset = CFrame.new(0, 0.125, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(2.3, 2.8, 2.3), offset = CFrame.new(0, 1.65, 0), color = COLORS.DarkWood, material = Enum.Material.Wood },
		{ size = Vector3.new(2.8, 0.25, 2.8), offset = CFrame.new(0, 3.175, 0), color = COLORS.Gold, material = Enum.Material.Metal },
		{ size = Vector3.new(2, 0.06, 2), offset = CFrame.new(0, 3.3, 0), color = hex("5E2A7A"), material = Enum.Material.Fabric },
	},
	Space = { -- тёмно-синяя тумба со светящимися кольцами
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 0.15, 0), color = hex("2B2F3A"), material = Enum.Material.Metal },
		{ size = Vector3.new(2, 2.7, 2), offset = CFrame.new(0, 1.65, 0), color = COLORS.Navy },
		{ size = Vector3.new(2.3, 0.15, 2.3), offset = CFrame.new(0, 0.45, 0), color = COLORS.Turquoise, material = Enum.Material.Neon },
		{ size = Vector3.new(2.3, 0.15, 2.3), offset = CFrame.new(0, 2.85, 0), color = COLORS.Turquoise, material = Enum.Material.Neon },
		{ size = Vector3.new(2.8, 0.3, 2.8), offset = CFrame.new(0, 3.15, 0), color = hex("3A4250"), material = Enum.Material.Metal },
	},
}

-- Где стоят постаменты залов (в координатах зала Скульптур): x, z и куда смотрит экспонат.
-- Порядок = порядок экспонатов в Config.Exhibits.Slots (в зале — по возрастанию цены).
local HALL_PEDESTALS: { [string]: { { number } } } = {
	Sculptures = { { -52, 58, 0, 1 }, { -52, 96, 0, -1 }, { -80, 77, 1, 0 }, { -24, 77, -1, 0 } }, -- крестом вокруг фонтана
	Dinosaurs = { { -62, 56, 0, 1 }, { -62, 98, 0, -1 }, { -30, 56, 0, 1 }, { -30, 98, 0, -1 } }, -- по бокам от скелета
	Jewelry = { { -70, 68, 0, 1 }, { -70, 86, 0, -1 }, { -40, 68, 0, 1 }, { -40, 86, 0, -1 } }, -- вдоль ковровой дорожки
	Space = { { -62, 58, 0, 1 }, { -62, 96, 0, -1 }, { -34, 58, 0, 1 }, { -34, 96, 0, -1 } }, -- под планетами
}

-- Постаменты: 2 в центре рядом с Моной Лизой и по 4 в каждом зале. Атрибуты Hall и Slot — для покупки экспонатов.
local function buildPedestals(folder: Folder)
	local spots: { { hall: string, cframe: CFrame, stub: string } } = {}
	for _, x in { -21, 21 } do
		local position = Vector3.new(x, 0, 8)
		table.insert(spots, { hall = GameState.Hall.Main, cframe = CFrame.lookAt(position, position + Vector3.new(0, 0, 1)), stub = "Main" })
	end
	for k = 0, 3 do
		local hall = WING_HALLS[k]
		local T = turn(k)
		for _, spot in HALL_PEDESTALS[hall] do
			local position = Vector3.new(spot[1], 0, spot[2])
			local cframe = T * CFrame.lookAt(position, position + Vector3.new(spot[3], 0, spot[4]))
			table.insert(spots, { hall = hall, cframe = cframe, stub = hall })
		end
	end
	for index, spot in spots do
		local pedestal = ModelLibrary.place(MapSchema.Models.Pedestal, spot.cframe, PEDESTAL_STUBS[spot.stub], folder)
		pedestal.Name = "Pedestal" .. index
		pedestal:SetAttribute("Hall", spot.hall)
		pedestal:SetAttribute("Slot", index)
	end
end

---------------------------------------------------------------- служебный угол

local function buildStaffArea(doorsFolder: Folder)
	local main = GameState.Hall.Main
	buildRoom({ name = "StaffCorridor", rect = STAFF_CORRIDOR, height = STAFF_H, style = STYLES.Staff, floorColor = hex("5A6070"), floorMaterial = Enum.Material.Concrete, hall = main, wander = false, lampSpacing = 18, area = "STAFF CORRIDOR" }, "Staff")
	buildRoom({ name = "Armory", rect = ARMORY, height = STAFF_H, style = STYLES.Armory, floorColor = hex("4A505C"), floorMaterial = Enum.Material.DiamondPlate, hall = main, wander = false, lampSpacing = 14, area = "ARMORY" }, "Staff")
	-- Жёлто-чёрная полоса по полу у входа и табличка на стороне коридора
	decorPart("HazardStripe", Vector3.new(2, 0.05, 6), CFrame.new(49.2, 0.03, 102), hex("F2C230"))
	wallSign(Vector3.new(46, 10.6, 102), Vector3.new(-1, 0, 0), 5, 1.4, "STAFF ONLY", hex("FFFFFF"), COLORS.Red)

	-- Дверь STAFF ONLY: одна створка, уезжает в стену
	local door = Instance.new("Model")
	door.Name = "StaffDoor"
	door:SetAttribute(GameState.DoorAttr.Open, false)
	local center = Vector3.new(STAFF_DOOR.x, 0, (STAFF_DOOR.z1 + STAFF_DOOR.z2) / 2)
	local base = CFrame.lookAt(center, center + Vector3.new(-1, 0, 0))
	local leaf = ModelLibrary.place(MapSchema.Models.StaffDoor, base, STAFF_DOOR_STUB, door)
	leaf.Name = "Leaf"
	leaf:SetAttribute(GameState.DoorAttr.SlideX, -5.5)
	ModelLibrary.forEachPart(leaf, function(part)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end)
	door.WorldPivot = base
	door.Parent = doorsFolder

	-- Щиток POWER у северной стены коридора (для вора, который выключает свет, блок 3)
	local fuse = placeModel(MapSchema.Models.FuseBox, CFrame.lookAt(Vector3.new(86, 0, 98), Vector3.new(86, 0, 99)), FUSEBOX_STUB)
	fuse.Name = MapSchema.FuseBox
	wallSign(Vector3.new(86, 8.4, 98), Vector3.new(0, 0, 1), 3.6, 1, "⚡ POWER", hex("1E2A44"), hex("F2C230"))
	wallSign(Vector3.new(100, 8, 102), Vector3.new(-1, 0, 0), 4, 1, "ARMORY", hex("FFFFFF"), COLORS.Red)
	for _, z in { 99.2, 104.8 } do
		local pipe = decorPart("Pipe", Vector3.new(52, 0.6, 0.6), CFrame.new(74, 10.8, z), hex("6E7686"), Enum.Material.Metal)
		pipe.Shape = Enum.PartType.Cylinder
	end

	-- Оружейная: стойка у восточной стены (товары ставит ArmoryService, блок 4), шкафчики, мишень
	local rack = placeModel(MapSchema.Models.WeaponRack, CFrame.lookAt(Vector3.new(ARMORY.maxX, 0, 113), Vector3.new(ARMORY.maxX - 1, 0, 113)), WEAPON_RACK_STUB)
	rack.Name = MapSchema.ArmoryRack
	wallSign(Vector3.new(ARMORY.maxX, 9.2, 113), Vector3.new(-1, 0, 0), 6, 1.4, "ARMORY", hex("FFFFFF"), COLORS.Red)
	-- Прилавок с оружием, стол с патронами и манекен в бронежилете ставит ArmoryService (блок 4) от этой стойки
	local locker = {
		{ size = Vector3.new(3, 7, 2), offset = CFrame.new(0, 3.5, 0), color = COLORS.Steel, material = Enum.Material.Metal },
		{ size = Vector3.new(0.1, 6.6, 0.1), offset = CFrame.new(0, 3.5, -1.02), color = hex("2B2F3A") },
	}
	for _, x in { 106, 110, 114, 118 } do
		placeModel(MapSchema.Models.Locker, CFrame.lookAt(Vector3.new(x, 0, ARMORY.maxZ - 1.1), Vector3.new(x, 0, ARMORY.maxZ - 2)), locker)
	end
	local target = decorPart("TargetBoard", Vector3.new(4, 4, 0.1), CFrame.lookAt(Vector3.new(115, 6, ARMORY.minZ + 0.6), Vector3.new(115, 6, ARMORY.minZ + 2)), hex("F2EEE6"))
	local gui = surfaceGui(target, Enum.NormalId.Front, 30, 1)
	for index, ring in { { 1, "C8343A" }, { 0.7, "F2EEE6" }, { 0.45, "C8343A" }, { 0.2, "1E2A44" } } do
		local frame = guiFrame(gui, UDim2.fromScale((1 - ring[1]) / 2, (1 - ring[1]) / 2), UDim2.fromScale(ring[1], ring[1]), hex(ring[2]), index)
		corner(frame, UDim.new(0.5, 0))
	end
end

---------------------------------------------------------------- снаружи: стены, фасады, площадь

-- Окно-обманка на фасаде (внутри музея окон нет).
local function fakeWindow(T: CFrame, x: number, z: number)
	local frame = T * CFrame.new(x, 11, z)
	decorPart("WindowFrame", Vector3.new(3.4, 6.4, 0.3), frame, COLORS.WhiteMarble, Enum.Material.Marble)
	decorPart("WindowGlass", Vector3.new(2.8, 5.8, 0.32), frame, COLORS.Window, Enum.Material.Glass)
	decorPart("WindowBar", Vector3.new(0.2, 5.8, 0.36), frame, COLORS.WhiteMarble, Enum.Material.Marble)
	decorPart("WindowBar", Vector3.new(2.8, 0.2, 0.36), frame * CFrame.new(0, 0.6, 0), COLORS.WhiteMarble, Enum.Material.Marble)
	decorPart("WindowSill", Vector3.new(3.8, 0.4, 0.8), frame * CFrame.new(0, -3.3, 0.3), COLORS.WhiteMarble, Enum.Material.Marble)
end

local function buildShellAndFacades()
	-- Наружная стена 260 × 260 с 4 дверями
	local outer = HALF + 0.5
	newWall("X", -outer, -outer - 0.5, outer + 0.5, SHELL_H, { openings = openingsFor("X", -outer, -outer - 0.5, outer + 0.5) })
	newWall("X", outer, -outer - 0.5, outer + 0.5, SHELL_H, { openings = openingsFor("X", outer, -outer - 0.5, outer + 0.5) })
	newWall("Z", -outer, -outer + 0.5, outer - 0.5, SHELL_H, { openings = openingsFor("Z", -outer, -outer + 0.5, outer - 0.5) })
	newWall("Z", outer, -outer + 0.5, outer - 0.5, SHELL_H, { openings = openingsFor("Z", outer, -outer + 0.5, outer - 0.5) })

	for k = 0, 3 do
		local T = turn(k)
		local side = SIDE_NAMES[k]
		-- Цоколь, карниз и пилястры по фасаду
		for _, s in { -1, 1 } do -- у двери цоколь прерывается
			local from, to = DOOR_HALF + 1.6, HALF + 1.5
			decorPart("Plinth", Vector3.new(to - from, 1.6, 0.8), T * CFrame.new(s * (from + to) / 2, 0.8, HALF + 1.3), COLORS.ExteriorDark, Enum.Material.Concrete)
		end
		decorPart("Cornice", Vector3.new(2 * HALF + 4, 1.2, 1.6), T * CFrame.new(0, SHELL_H + 0.1, HALF + 1.2), COLORS.ExteriorDark, Enum.Material.Concrete)
		decorPart("CorniceTop", Vector3.new(2 * HALF + 4.4, 0.4, 2), T * CFrame.new(0, SHELL_H + 0.9, HALF + 1.2), COLORS.WhiteMarble, Enum.Material.Marble)
		for _, x in { -117, -91, -65, -39, 39, 65, 91, 117 } do
			decorPart("Pilaster", Vector3.new(1.8, SHELL_H - 1.6, 0.6), T * CFrame.new(x, SHELL_H / 2 + 0.8, HALF + 1.2), COLORS.Exterior, Enum.Material.Concrete)
		end
		for _, x in { -104, -78, -52, -26, 26, 52, 78, 104 } do
			fakeWindow(T, x, HALF + 1.15)
		end
		-- Порог в проёме двери и ступени перед ней
		solidPart("Threshold", Vector3.new(DOOR_HALF * 2, 1, 2), T * CFrame.new(0, -0.5, HALF + 1), COLORS.Stone, Enum.Material.Slate)
		solidPart("Step", Vector3.new(18, 0.4, 5), T * CFrame.new(0, 0.2 - 0.25, HALF + 4.5), COLORS.Stone, Enum.Material.Slate)
		-- Обрамление двери и фонари по бокам
		for _, s in { -1, 1 } do
			decorPart("DoorPilaster", Vector3.new(1.4, DOOR_H + 1, 0.8), T * CFrame.new(s * (DOOR_HALF + 0.9), (DOOR_H + 1) / 2, HALF + 1.4), COLORS.WhiteMarble, Enum.Material.Marble)
			local lampPos = T * Vector3.new(s * 8.5, 8.5, HALF + 1.6)
			decorPart("LanternArm", Vector3.new(0.3, 0.3, 1.2), T * CFrame.new(s * 8.5, 8.2, HALF + 1.3), COLORS.Dark, Enum.Material.Metal)
			newLamp(propsFolder, lampPos, Vector3.new(0.9, 1.3, 0.9), { Range = 14, Brightness = 1, Color = Config.Lighting.LobbyLamp.Color })
		end
		decorPart("DoorLintel", Vector3.new(DOOR_HALF * 2 + 3.2, 1, 1), T * CFrame.new(0, DOOR_H + 0.5, HALF + 1.4), COLORS.WhiteMarble, Enum.Material.Marble)
		if k ~= 0 then
			-- Простой фасад: навес над дверью и табличка
			decorPart("Canopy", Vector3.new(16, 0.8, 5), T * CFrame.new(0, DOOR_H + 2, HALF + 3.4), COLORS.WhiteMarble, Enum.Material.Marble)
			decorPart("CanopyTrim", Vector3.new(16.4, 0.3, 5.4), T * CFrame.new(0, DOOR_H + 1.5, HALF + 3.4), COLORS.Gold, Enum.Material.Metal)
			for _, s in { -1, 1 } do
				decorPart("CanopyBracket", Vector3.new(0.4, 2.2, 3.6), T * CFrame.new(s * 7, DOOR_H + 0.6, HALF + 2.8), COLORS.Dark, Enum.Material.Metal)
			end
			local board = decorPart("EntranceSign", Vector3.new(12, 1.8, 0.2), T * CFrame.lookAt(Vector3.new(0, DOOR_H + 4.2, HALF + 1.2), Vector3.new(0, DOOR_H + 4.2, HALF + 3)), COLORS.Navy)
			textOn(board, Enum.NormalId.Front, side:upper() .. " ENTRANCE", COLORS.Gold, 0)
		end
	end

	-- Юг: портик с 4 колоннами, фронтон и вывеска NIGHT MUSEUM
	for _, x in { -13, -7, 7, 13 } do
		column(x, HALF + 7.5, 12, COLORS.WhiteMarble, Enum.Material.Marble)
	end
	local beam = solidPart("Portico", Vector3.new(32, 1.5, 7.5), CFrame.new(0, 12.75, HALF + 5.25), hex("EDE6D6"), Enum.Material.Marble)
	textOn(beam, Enum.NormalId.Back, "NIGHT MUSEUM", COLORS.Gold, 0)
	local left = Instance.new("WedgePart")
	left.Name = "Pediment"
	left.Anchored = true
	left.Size = Vector3.new(7.5, 4, 16)
	left.CFrame = CFrame.new(-8, 15.5, HALF + 5.25) * CFrame.Angles(0, math.rad(90), 0)
	left.Color = hex("EDE6D6")
	left.Material = Enum.Material.Marble
	left.Parent = geometryFolder
	local right = left:Clone()
	right.CFrame = CFrame.new(8, 15.5, HALF + 5.25) * CFrame.Angles(0, math.rad(-90), 0)
	right.Parent = geometryFolder
	-- Площадь перед портиком и дорожка к домику охраны, фонари
	solidPart("Plaza", Vector3.new(64, 0.2, 30), CFrame.new(0, 0.05, HALF + 16), COLORS.Stone, Enum.Material.Slate)
	solidPart("Path", Vector3.new(8, 0.2, LOBBY.minZ - HALF - 31), CFrame.new(0, 0.05, (HALF + 31 + LOBBY.minZ) / 2), COLORS.Stone, Enum.Material.Slate)
	for _, spot in { { -26, HALF + 16 }, { 26, HALF + 16 }, { -6, HALF + 40 }, { 6, HALF + 55 } } do
		solidPart("LampPost", Vector3.new(0.5, 8, 0.5), CFrame.new(spot[1], 4, spot[2]), COLORS.Dark, Enum.Material.Metal)
		newLamp(geometryFolder, Vector3.new(spot[1], 8.4, spot[2]), Vector3.new(1, 1, 1), Config.Lighting.LobbyLamp)
	end
end

---------------------------------------------------------------- точки входа и камер

local function buildEntrances(entrances: Folder)
	-- Точки снаружи у каждой двери: тут появляются воры и туристы, сюда убегают воры и уходят туристы.
	for k = 0, 3 do
		local T = turn(k)
		local position = T * Vector3.new(0, 3, HALF + 11)
		local inside = T * Vector3.new(0, 3, HALF - 5)
		local marker = newMarker(entrances, SIDE_NAMES[k], CFrame.lookAt(position, inside))
		marker:SetAttribute("Hall", GameState.Hall.Main) -- все 4 двери работают с первой ночи
		marker:SetAttribute("Side", SIDE_NAMES[k])
	end
end

-- Места для камер (блок 2): 2 в центре, по 1 во входных холлах, по 1–2 в залах. Номер = порядок в списке.
-- wall — точка на поверхности стены на высоте камеры, normal — от стены в комнату, target — куда смотрит.
type CameraSpot = { hall: string, wall: Vector3, normal: Vector3, target: Vector3 }

local function cameraSpots(): { CameraSpot }
	local spots: { CameraSpot } = {
		{ hall = GameState.Hall.Main, wall = Vector3.new(-14, 17, CENTER.maxZ), normal = Vector3.new(0, 0, -1), target = Vector3.new(0, 5.5, 2) }, -- 1 Mona Lisa
		{ hall = GameState.Hall.Main, wall = Vector3.new(CENTER.maxX, 19, 30), normal = Vector3.new(-1, 0, 0), target = Vector3.new(-16, 2, -20) }, -- 2 Center Hall
	}
	local function rotated(k: number, hall: string, wall: Vector3, normal: Vector3, target: Vector3): CameraSpot
		local T = turn(k)
		return { hall = hall, wall = T * wall, normal = T:VectorToWorldSpace(normal), target = T * target }
	end
	for k = 0, 3 do -- 3..6: входные холлы
		table.insert(spots, rotated(k, GameState.Hall.Main, Vector3.new(-10, 13, WING.Lobby.minZ), Vector3.new(0, 0, 1), Vector3.new(6, 2, 126)))
	end
	for k = 0, 3 do -- 7..10: залы
		table.insert(spots, rotated(k, WING_HALLS[k], Vector3.new(HALL_RECT.minX, 16.5, 100), Vector3.new(1, 0, 0), Vector3.new(-30, 2, 58)))
	end
	for _, k in { 2, 3 } do -- 11, 12: вторые камеры дорогих залов (Драгоценности, Космос)
		table.insert(spots, rotated(k, WING_HALLS[k], Vector3.new(HALL_RECT.maxX, 16.5, 100), Vector3.new(-1, 0, 0), Vector3.new(-80, 2, 58)))
	end
	return spots
end

-- Место для камеры: пластина на стене и кронштейн (видны сразу) и табличка CAMERA SPOT под ними —
-- на ней кнопка покупки (CameraService). Купленная камера встаёт на конец кронштейна.
local function buildCameraSpot(spotsFolder: Folder, index: number, spot: CameraSpot)
	local model = Instance.new("Model")
	model.Name = "CameraSpot" .. index
	model:SetAttribute(GameState.CameraAttr.Index, index)
	local wallFrame = CFrame.lookAt(spot.wall, spot.wall + spot.normal)
	local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local part = newPart(model, name, size, cframe, color, material)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		return part
	end
	piece("MountPlate", Vector3.new(1.4, 1.4, 0.2), wallFrame * CFrame.new(0, 0, -0.1), hex("3A3F4B"), Enum.Material.Metal)
	piece("MountArm", Vector3.new(0.3, 0.3, 1.6), wallFrame * CFrame.new(0, 0, -0.95), hex("3A3F4B"), Enum.Material.Metal)
	for _, offset in { Vector3.new(0, 0.8, 0), Vector3.new(0, -0.8, 0) } do
		piece("MountRing", Vector3.new(1.8, 0.12, 0.08), wallFrame * CFrame.new(offset) * CFrame.new(0, 0, -0.05), COLORS.Turquoise, Enum.Material.Neon)
	end
	-- Табличка на высоте глаз под кронштейном
	local plaqueFrame = CFrame.lookAt(Vector3.new(spot.wall.X, 5, spot.wall.Z), Vector3.new(spot.wall.X, 5, spot.wall.Z) + spot.normal)
	piece("PlaqueFrame", Vector3.new(2.9, 1.6, 0.08), plaqueFrame * CFrame.new(0, 0, -0.04), COLORS.Gold, Enum.Material.Metal)
	local plaque = piece(MapSchema.CameraPlaque, Vector3.new(2.6, 1.3, 0.1), plaqueFrame * CFrame.new(0, 0, -0.12), COLORS.Navy)
	textOn(plaque, Enum.NormalId.Front, ("CAMERA SPOT\nCAM %d"):format(index), COLORS.Gold, 0)
	model.Parent = spotsFolder
end

local function buildCameraPoints(cameraPoints: Folder, spotsFolder: Folder)
	local attr = GameState.CameraAttr
	for index, spot in cameraSpots() do
		buildCameraSpot(spotsFolder, index, spot)
		local head = spot.wall + spot.normal * 1.8 -- камера на конце кронштейна
		local cframe = CFrame.lookAt(head, spot.target)
		-- Точка обзора чуть впереди объектива, чтобы корпус не закрывал вид
		local point = newMarker(cameraPoints, "Camera" .. index, cframe * CFrame.new(0, 0, -3.5))
		point:SetAttribute(attr.Index, index)
		point:SetAttribute(attr.Hall, spot.hall)
		point:SetAttribute(attr.Broken, false)
		local floorPoint = spot.wall + spot.normal * 3
		point:SetAttribute(attr.StandPoint, Vector3.new(floorPoint.X, 3, floorPoint.Z))
	end
end

---------------------------------------------------------------- лобби: домик охраны

-- Лобби (блок B1): просторная комната охраны 50×40, закрытая — в музей команду переносит игра.
-- Посередине светящийся круг START SHIFT (кто в нём — в команде, LobbyService), игроки появляются
-- у южной стены лицом к кругу. Шкафчики у северной стены, над ними подсказка.
-- Снаружи — домик из песчаника с вывеской SECURITY к югу от площади музея.
local function buildLobby(map: Folder, markers: Folder)
	local r = LOBBY
	local half = WALL_T / 2
	buildRoom({ name = "Lobby", rect = r, height = GUARD_H, style = STYLES.Guard, floorColor = COLORS.Wood, floorMaterial = Enum.Material.WoodPlanks, lampSpacing = 0 }, "Lobby")

	-- Игроки появляются у южной стены и смотрят на север, прямо на круг
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = MapSchema.LobbySpawn
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- без защитного поля
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(LOBBY_SPAWN)
	spawn.Color = COLORS.Steel
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = markers

	-- Круг START SHIFT: светящийся диск на полу с золотым ободком. Цвет и табличку над ним
	-- показывает клиент (LobbyCircle.client), кто в команде — решает сервер (LobbyService).
	local settings = Config.Lobby
	local diameter = settings.CircleRadius * 2
	local rim = decorPart("StartCircleRim", Vector3.new(0.1, diameter + 1.2, diameter + 1.2), CFrame.new(START_CIRCLE_CENTER + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Gold, Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	rim.CanQuery = false
	local circle = newPart(map, MapSchema.StartCircle, Vector3.new(0.12, diameter, diameter), CFrame.new(START_CIRCLE_CENTER + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), settings.Color, Enum.Material.Neon)
	circle.Shape = Enum.PartType.Cylinder
	circle.CanCollide = false
	circle.CanTouch = false
	circle.CanQuery = false
	circle.CastShadow = false
	circle.Transparency = 0.1
	local glow = Instance.new("PointLight")
	glow.Range = settings.LightRange
	glow.Brightness = settings.LightBrightness
	glow.Color = settings.Color
	glow.Parent = circle

	-- Шкафчики вдоль северной стены и подсказка над ними
	local locker = {
		{ size = Vector3.new(3, 7, 2), offset = CFrame.new(0, 3.5, 0), color = COLORS.Steel },
	}
	for x = -20, 20, 4 do
		local position = Vector3.new(x, 0, r.minZ + 1.5)
		placeModel(MapSchema.Models.Locker, CFrame.lookAt(position, position + Vector3.new(0, 0, 1)), locker)
	end
	local sign = solidPart("LobbySign", Vector3.new(30, 2.5, 0.2), CFrame.new(0, 9.5, r.minZ + half + 0.1), COLORS.Navy)
	sign.CanCollide = false
	textOn(sign, Enum.NormalId.Back, "STAND IN THE CIRCLE TO START YOUR SHIFT", COLORS.Gold, 0)

	-- Банкетки у западной и восточной стен, растения в углах
	for _, x in { r.minX + 2.5, r.maxX - 2.5 } do
		placeModel(MapSchema.Models.Bench, CFrame.new(x, 0, (r.minZ + r.maxZ) / 2) * CFrame.Angles(0, math.rad(90), 0), BENCH_STUB)
	end
	for _, spot in { { r.minX + 2, r.minZ + 4 }, { r.maxX - 2, r.minZ + 4 }, { r.minX + 2, r.maxZ - 2 }, { r.maxX - 2, r.maxZ - 2 } } do
		plant(spot[1], spot[2])
	end

	-- Тёплый свет: опоздавшие ждут тут и ночью
	local alongX = Vector3.new(1.6, 0.4, 0.3)
	local alongZ = Vector3.new(0.3, 0.4, 1.6)
	for _, z in { r.minZ + 10, r.maxZ - 10 } do
		newLamp(propsFolder, Vector3.new(r.minX + half + 0.2, 10, z), alongZ, Config.Lighting.LobbyLamp)
		newLamp(propsFolder, Vector3.new(r.maxX - half - 0.2, 10, z), alongZ, Config.Lighting.LobbyLamp)
	end
	newLamp(propsFolder, Vector3.new(0, 10, r.maxZ - half - 0.2), alongX, Config.Lighting.LobbyLamp)

	-- Снаружи: вывеска SECURITY и дверь-обманка на северной стене (к музею)
	local outside = r.minZ - WALL_T - 0.05
	local board = decorPart("SecuritySign", Vector3.new(14, 2.4, 0.2), CFrame.lookAt(Vector3.new(0, 10.5, outside), Vector3.new(0, 10.5, outside - 1)), COLORS.Navy)
	textOn(board, Enum.NormalId.Front, "SECURITY", COLORS.Gold, 0)
	decorPart("FakeDoor", Vector3.new(5, 8, 0.2), CFrame.new(0, 4, outside), COLORS.DarkWood, Enum.Material.Wood)
	decorPart("FakeDoorKnob", Vector3.new(0.4, 0.4, 0.4), CFrame.new(1.8, 4, outside - 0.2), COLORS.Gold, Enum.Material.Metal)
	newLamp(propsFolder, Vector3.new(0, 8.6, outside - 0.4), Vector3.new(1.2, 0.5, 0.4), Config.Lighting.LobbyLamp)
end

---------------------------------------------------------------- стенд MUSEUM MAP во входных холлах

local PLAN_COLORS: { [string]: string } = {
	Center = "D4A93A",
	Lobby = "E6D9BE",
	Corridor = "6C8CA0",
	Staff = "4A5266",
	Sculptures = "F2EEE6",
	Dinosaurs = "D9B98A",
	Jewelry = "8E5BC2",
	Space = "3BC6C1",
}

local PLAN_LABELS: { [string]: string } = {
	Center = "MONA LISA",
	Sculptures = "SCULPTURES",
	Dinosaurs = "DINOSAURS",
	Jewelry = "JEWELRY",
	Space = "SPACE",
}

-- Схема музея (север вверху) с точкой «YOU ARE HERE» у этой двери.
local function museumMapBoard(cframe: CFrame, here: Vector3)
	decorPart("MapBoardFrame", Vector3.new(8.4, 5.4, 0.15), cframe * CFrame.new(0, 0, -0.08), COLORS.Gold, Enum.Material.Metal)
	local board = decorPart("MapBoard", Vector3.new(8, 5, 0.1), cframe * CFrame.new(0, 0, -0.18), COLORS.Navy)
	local gui = surfaceGui(board, Enum.NormalId.Front, 50, 0)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.64, 0.06)
	title.Size = UDim2.fromScale(0.33, 0.16)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = COLORS.Gold
	title.Text = "MUSEUM MAP"
	title.Parent = gui
	local plan = guiFrame(gui, UDim2.fromScale(0.03, 0.05), UDim2.fromScale(0.56, 0.9), hex("141B2E"), 1)
	local size = 2 * HALF
	local function toPlan(x: number, z: number): (number, number)
		return (x + HALF) / size, (z + HALF) / size
	end
	for _, room in builtRooms do
		local color = PLAN_COLORS[room.kind]
		local r = room.rect
		if color and math.abs(r.minX) <= HALF and math.abs(r.maxZ) <= HALF then
			local u0, v0 = toPlan(r.minX, r.minZ)
			local u1, v1 = toPlan(r.maxX, r.maxZ)
			local frame = guiFrame(plan, UDim2.fromScale(u0, v0), UDim2.fromScale(u1 - u0, v1 - v0), hex(color), 2)
			local label = PLAN_LABELS[room.kind]
			if label then
				local text = Instance.new("TextLabel")
				text.BackgroundTransparency = 1
				text.Size = UDim2.fromScale(1, 1)
				text.TextScaled = true
				text.Font = Enum.Font.FredokaOne
				text.TextColor3 = hex("141B2E")
				text.Text = label
				text.ZIndex = 3
				text.Parent = frame
			end
		end
	end
	local u, v = toPlan(here.X, here.Z)
	local dot = guiFrame(plan, UDim2.fromScale(u, v), UDim2.fromScale(0.08, 0.08), COLORS.Red, 5) -- схема почти квадратная
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(dot, UDim.new(0.5, 0))
	local legendDot = guiFrame(gui, UDim2.fromScale(0.66, 0.42), UDim2.fromScale(0.05, 0.08), COLORS.Red, 2)
	corner(legendDot, UDim.new(0.5, 0))
	local legend = Instance.new("TextLabel")
	legend.BackgroundTransparency = 1
	legend.Position = UDim2.fromScale(0.73, 0.38)
	legend.Size = UDim2.fromScale(0.25, 0.16)
	legend.TextScaled = true
	legend.Font = Enum.Font.FredokaOne
	legend.TextColor3 = hex("FFFFFF")
	legend.Text = "YOU ARE HERE"
	legend.Parent = gui
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromScale(0.64, 0.62)
	hint.Size = UDim2.fromScale(0.34, 0.3)
	hint.TextScaled = true
	hint.Font = Enum.Font.FredokaOne
	hint.TextColor3 = COLORS.Gold
	hint.Text = "Follow the red carpet to the Mona Lisa"
	hint.Parent = gui
end

---------------------------------------------------------------- для игрового цикла

local function warnAboutDefaultPlace()
	for _, name in { "Baseplate", "SpawnLocation" } do
		if Workspace:FindFirstChild(name) then
			warn(
				("[MapBuilder] В Workspace есть стандартный %s. Удалите его в Studio: он мешает карте."):format(name)
			)
		end
	end
end

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
	propsFolder = newFolder(map, MapSchema.Props)
	local exhibits = newFolder(map, MapSchema.Exhibits)
	local markers = newFolder(map, MapSchema.Markers)
	local entrances = newFolder(map, MapSchema.Entrances)
	local cameraPoints = newFolder(map, MapSchema.CameraPoints)
	local cameraSpotsFolder = newFolder(map, MapSchema.CameraSpots)
	local hallDoors = newFolder(map, MapSchema.HallDoors)
	local pedestals = newFolder(map, MapSchema.Pedestals)
	local doorsFolder = newFolder(map, MapSchema.Doors)
	local kit = makeKit()

	solidPart("Ground", Vector3.new(900, 1, 900), CFrame.new(0, -0.55, 0), COLORS.Ground, Enum.Material.Grass)

	-- Сначала все проходы: комнаты находят их на своих стенах
	for k = 0, 3 do
		addWingDoorways(k)
	end
	addDoorway(0, STAFF_DOOR.x, STAFF_DOOR.z1, STAFF_DOOR.x, STAFF_DOOR.z2, OPENING_H) -- C1 → служебный коридор
	addDoorway(0, ARMORY.minX - 1, STAFF_DOOR.z1, ARMORY.minX - 1, STAFF_DOOR.z2, OPENING_H) -- коридор → оружейная

	buildCenter(map, exhibits, markers)
	for k = 0, 3 do
		buildWing(k, doorsFolder)
		buildHall(k, hallDoors, kit)
	end
	buildPedestals(pedestals)
	buildStaffArea(doorsFolder)
	buildShellAndFacades()
	buildEntrances(entrances)
	buildCameraPoints(cameraPoints, cameraSpotsFolder)
	buildLobby(map, markers)
	-- Стенды MUSEUM MAP — когда все комнаты уже построены
	for k = 0, 3 do
		local T = turn(k)
		local point = T * Vector3.new(6, 7, WING.Lobby.minZ)
		museumMapBoard(CFrame.lookAt(point, point + T:VectorToWorldSpace(Vector3.new(0, 0, 1))), T * Vector3.new(0, 0, HALF))
	end

	-- Охрана появляется перед Моной Лизой, лицом к ней
	newMarker(markers, MapSchema.PatrolSpawn, CFrame.lookAt(Vector3.new(0, 3, 15), Vector3.new(0, 3, 0)))

	MapBuilder.setDayLights(map, false)
	return map
end

return MapBuilder
