-- Хаб (блок 6): большая комната охраны — общее лобби игры. Строится кодом теми же помощниками, что музей
-- (MapBuilder.newKit: стены с обоями и деревянными панелями, карниз, потолок, лампы, растения, таблички).
-- Координаты ниже — геометрия комнаты, а не баланс, поэтому они здесь, а не в Config.
--
--   Вид сверху (север вверху, −Z):
--   +------------------- стена мониторов, пульт с креслами -------------------+
--   | WANTED                                                          WANTED |
--   | шкафчики   (1)        (2)        (3)        (4)        (5)     доска    |
--   | банкетки                    5 светящихся кругов                рекордов |
--   |                                  ковёр                         кубок    |
--   | картина   доска HOW TO PLAY   [ дверь ]   кулер, кофе   CLASS SHOP (5 подставок) |
--   +--------------------------------- вход ------------------------------------+
--   Игроки появляются у южной двери лицом к кругам. Витрина CLASS SHOP (этап 4, блок 1) — у южной стены справа.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local MapBuilder = require(Server:WaitForChild("MapBuilder"))
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))

local hex = Color3.fromHex
local Models = MapSchema.Models
local PadAttr = GameState.PadAttr

local HubBuilder = {}

local HALF_X, HALF_Z = 50, 36 -- пол комнаты: x от −50 до 50, z от −36 до 36
local HEIGHT = 20
local SPAWN = Vector3.new(0, 0.5, 29)
-- Круги дугой: средний дальше всех, крайние ближе к двери — со входа видны все пять
local PAD_CENTERS = {
	Vector3.new(-32, 0, 4),
	Vector3.new(-16, 0, -1),
	Vector3.new(0, 0, -3),
	Vector3.new(16, 0, -1),
	Vector3.new(32, 0, 4),
}

local STEEL = hex("5A6E8C")
local STEEL_LIGHT = hex("6F84A3")
local STEEL_DARK = hex("2B2F3A")
local CHROME = hex("D9DEE7")
local SCREEN = hex("0E1626")

-- Камеры на стене мониторов: название и что на картинке (сцена рисуется кодом).
local FEEDS: { { title: string, scene: string } } = {
	{ title = "MONA LISA", scene = "Painting" },
	{ title = "CENTER HALL", scene = "Hall" },
	{ title = "SOUTH HALL", scene = "Arch" },
	{ title = "WEST HALL", scene = "Arch" },
	{ title = "NORTH HALL", scene = "Arch" },
	{ title = "EAST HALL", scene = "Arch" },
	{ title = "SCULPTURES", scene = "Sculptures" },
	{ title = "DINOSAURS", scene = "Dinosaurs" },
	{ title = "JEWELRY", scene = "Jewelry" },
	{ title = "SPACE", scene = "Space" },
	{ title = "JEWELRY VAULT", scene = "Jewelry" },
	{ title = "SPACE ROCKET", scene = "Space" },
	{ title = "PLAZA", scene = "Plaza" },
	{ title = "ROOF", scene = "Roof" },
	{ title = "STAFF CORRIDOR", scene = "Arch" },
	{ title = "ARMORY", scene = "Armory" },
	{ title = "LOADING DOCK", scene = "Plaza" },
	{ title = "SECURITY HQ", scene = "Hall" },
}

-- Цвета сцены на мониторе: стена, пол, предмет.
local SCENES: { [string]: { wall: string, floor: string, thing: string } } = {
	Painting = { wall = "5E1622", floor = "3A3F4B", thing = "D4A93A" },
	Hall = { wall = "8C2A2A", floor = "E8DCC4", thing = "D4A93A" },
	Arch = { wall = "2E4A5A", floor = "6B4A2E", thing = "C8343A" },
	Sculptures = { wall = "D9D2C3", floor = "F2EEE6", thing = "F7F3EA" },
	Dinosaurs = { wall = "D9B98A", floor = "C9A66B", thing = "E9DFC6" },
	Jewelry = { wall = "3B2559", floor = "6B4A2E", thing = "7FD8FF" },
	Space = { wall = "1B2340", floor = "0F1428", thing = "3BC6C1" },
	Plaza = { wall = "1C2A3A", floor = "4A5060", thing = "D8CCB4" },
	Roof = { wall = "0F1A2A", floor = "BFE3F2", thing = "8A93A6" },
	Armory = { wall = "3A4250", floor = "2B2F3A", thing = "C8343A" },
}

---------------------------------------------------------------- модели-заглушки (R4)

local GOLD = hex("D4A93A")
local GOLD_BRIGHT = hex("F2C230")
local NAVY = hex("1E2A44")
local NAVY_DARK = hex("141B2E")
local MARBLE = hex("E8DCC4")
local MARBLE_DARK = hex("2B2F3A")
local RED = hex("C8343A")
local CYAN = hex("3BC6C1")
local WOOD = hex("5A3A22")
local WOOD_DARK = hex("3A2A1E")

local function stubPart(
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	opts: { shape: Enum.PartType?, transparency: number?, wedge: boolean?, sphere: boolean?, collide: boolean? }?
): ModelLibrary.StubPart
	local o = opts or {}
	return {
		name = name,
		size = size,
		offset = offset,
		color = color,
		material = material,
		shape = o.shape,
		transparency = o.transparency,
		wedge = o.wedge,
		sphere = o.sphere,
		collide = o.collide,
	}
end

-- Шкафчик охраны (R4): цоколь, стальной корпус со скошенным верхом, рамка дверцы, наклонные жалюзи вентиляции,
-- ручка на стойках, кодовый замок, петли и табличка Plate под номер. Ширина ≤ 2.42 (шаг 2.45). Перед — в −Z.
local function buildLockerStub(): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {
		stubPart("Base", Vector3.new(2.36, 0.28, 1.88), CFrame.new(0, 0.14, 0.04), STEEL_DARK, Enum.Material.Metal),
		stubPart("Body", Vector3.new(2.4, 6.72, 2), CFrame.new(0, 3.64, 0), STEEL, Enum.Material.Metal),
		stubPart("Top", Vector3.new(2.42, 0.12, 2.04), CFrame.new(0, 7.06, -0.02), STEEL_DARK, Enum.Material.Metal),
		stubPart("TopSlope", Vector3.new(2.42, 0.18, 2.04), CFrame.new(0, 7.21, -0.02), STEEL_DARK, Enum.Material.Metal, { wedge = true, collide = false }),
		stubPart("DoorFrame", Vector3.new(2.24, 6.56, 0.05), CFrame.new(0, 3.68, -1.01), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("Door", Vector3.new(2.1, 6.42, 0.08), CFrame.new(0, 3.68, -1.04), STEEL_LIGHT, Enum.Material.Metal),
		stubPart("HandleRecess", Vector3.new(0.24, 0.96, 0.04), CFrame.new(0.7, 3.75, -1.08), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("Handle", Vector3.new(0.74, 0.1, 0.1), CFrame.new(0.7, 3.75, -1.16) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Lock", Vector3.new(0.06, 0.26, 0.26), CFrame.new(0.7, 4.48, -1.1) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("LockDial", Vector3.new(0.04, 0.14, 0.14), CFrame.new(0.7, 4.48, -1.13) * CFrame.Angles(0, math.rad(90), 0), STEEL_DARK, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("PlateRim", Vector3.new(0.98, 0.5, 0.04), CFrame.new(0, 5.2, -1.08), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("Plate", Vector3.new(0.88, 0.4, 0.05), CFrame.new(0, 5.2, -1.1), MARBLE, nil, { collide = false }),
		stubPart("Stripe", Vector3.new(1.8, 0.08, 0.03), CFrame.new(0, 4.86, -1.09), NAVY, nil, { collide = false }),
	}
	for _, y in { 4.1, 3.4 } do
		table.insert(list, stubPart("HandlePost", Vector3.new(0.08, 0.08, 0.08), CFrame.new(0.7, y, -1.12), CHROME, Enum.Material.Metal, { collide = false }))
	end
	for _, y in { 6.45, 6.22, 5.99, 5.76 } do
		table.insert(list, stubPart("VentTop", Vector3.new(1.36, 0.08, 0.07), CFrame.new(0, y, -1.1), STEEL_DARK, Enum.Material.Metal, { wedge = true, collide = false }))
	end
	for _, y in { 1.62, 1.39, 1.16 } do
		table.insert(list, stubPart("VentBottom", Vector3.new(1.36, 0.08, 0.07), CFrame.new(0, y, -1.1), STEEL_DARK, Enum.Material.Metal, { wedge = true, collide = false }))
	end
	for _, y in { 6.2, 3.7, 1.3 } do
		table.insert(list, stubPart("Hinge", Vector3.new(0.36, 0.1, 0.1), CFrame.new(-1.04, y, -1.07) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }))
	end
	return list
end
local LOCKER_STUB: { ModelLibrary.StubPart } = buildLockerStub()

-- Подставка витрины CLASS SHOP (R4): ступенчатый мраморный цоколь, тёмно-синяя тумба с угловыми пилястрами,
-- золотые канты с подкосами, светящееся кольцо Glow (цвет класса ставит код), поворотный круг сверху (y = 2.4).
-- Выше y = 2.42 ничего нет, чтобы вращающаяся модель класса не задевала детали. Перед — в −Z.
local function buildClassStandStub(): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {
		stubPart("Base", Vector3.new(3, 0.24, 3), CFrame.new(0, 0.12, 0), MARBLE_DARK, Enum.Material.Marble),
		stubPart("BaseStep", Vector3.new(2.76, 0.12, 2.76), CFrame.new(0, 0.3, 0), MARBLE_DARK, Enum.Material.Marble),
		stubPart("BaseTrim", Vector3.new(2.64, 0.1, 2.64), CFrame.new(0, 0.41, 0), GOLD, Enum.Material.Metal),
		stubPart("Body", Vector3.new(2.26, 1.56, 2.26), CFrame.new(0, 1.24, 0), NAVY),
		stubPart("BodyBand", Vector3.new(2.38, 0.12, 2.38), CFrame.new(0, 1.88, 0), GOLD, Enum.Material.Metal),
		stubPart("Glow", Vector3.new(0.14, 2.48, 2.48), CFrame.new(0, 2.04, 0) * CFrame.Angles(0, 0, math.rad(90)), CYAN, Enum.Material.Neon, { shape = Enum.PartType.Cylinder }),
		stubPart("TopTrim", Vector3.new(2.68, 0.14, 2.68), CFrame.new(0, 2.2, 0), GOLD, Enum.Material.Metal),
		stubPart("TopPlate", Vector3.new(2.5, 0.12, 2.5), CFrame.new(0, 2.33, 0), MARBLE, Enum.Material.Marble),
		stubPart("TurntableRim", Vector3.new(0.02, 2.06, 2.06), CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("TurntablePad", Vector3.new(0.025, 1.82, 1.82), CFrame.new(0, 2.405, 0) * CFrame.Angles(0, 0, math.rad(90)), NAVY_DARK, Enum.Material.Fabric, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Plaque", Vector3.new(1.56, 0.56, 0.06), CFrame.new(0, 1.12, -1.16), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("PlaqueFace", Vector3.new(1.42, 0.42, 0.04), CFrame.new(0, 1.12, -1.18), NAVY_DARK, nil, { collide = false }),
	}
	for _, x in { -1.1, 1.1 } do
		for _, z in { -1.1, 1.1 } do
			table.insert(list, stubPart("CornerPost", Vector3.new(0.18, 1.58, 0.18), CFrame.new(x, 1.24, z), GOLD, Enum.Material.Metal, { collide = false }))
			table.insert(list, stubPart("CornerBolt", Vector3.new(0.12, 0.12, 0.12), CFrame.new(x * 1.14, 0.47, z * 1.14), GOLD_BRIGHT, Enum.Material.Metal, { shape = Enum.PartType.Ball, collide = false }))
		end
	end
	for _, side in {
		{ pos = Vector3.new(0, 1.12, 1.15), size = Vector3.new(1.5, 1.1, 0.04) },
		{ pos = Vector3.new(-1.15, 1.12, 0), size = Vector3.new(0.04, 1.1, 1.5) },
		{ pos = Vector3.new(1.15, 1.12, 0), size = Vector3.new(0.04, 1.1, 1.5) },
	} do
		table.insert(list, stubPart("RecessPanel", side.size, CFrame.new(side.pos), NAVY_DARK, nil, { collide = false }))
	end
	for _, yaw in { 0, 90, 180, 270 } do
		table.insert(list, stubPart("UnderBevel", Vector3.new(2.2, 0.16, 0.18), CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 2.05, -1.2) * CFrame.Angles(0, 0, math.rad(180)), GOLD, Enum.Material.Metal, { wedge = true, collide = false }))
	end
	return list
end
local CLASS_STAND_STUB: { ModelLibrary.StubPart } = buildClassStandStub()
local STAND_TOP = 2.4 -- высота верха подставки

-- Пульт охраны под стеной мониторов (R4): столешница с фаской и кабель-каналами, тумбы с ящиками,
-- кессонный фасад со светящейся полосой, 3 клавиатуры с мышками, панель тревоги, микрофон, кружка и журнал смены.
-- Перед (к сидящему) — в −Z. Зоны x = −4, 0, +4 при z > 0.35 свободны под 3 монитора.
local function buildDeskStub(): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {
		stubPart("Top", Vector3.new(14, 0.3, 3.2), CFrame.new(0, 3.15, 0), WOOD_DARK, Enum.Material.Wood),
		stubPart("Edge", Vector3.new(14.08, 0.18, 0.2), CFrame.new(0, 3.15, -1.6), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("EdgeBevel", Vector3.new(14.08, 0.12, 0.12), CFrame.new(0, 3.28, -1.56), GOLD, Enum.Material.Metal, { wedge = true, collide = false }),
		stubPart("Front", Vector3.new(13.6, 2.6, 0.2), CFrame.new(0, 1.7, -1.2), NAVY),
		stubPart("FrontBase", Vector3.new(13.6, 0.24, 0.24), CFrame.new(0, 0.12, -1.2), MARBLE_DARK, Enum.Material.Metal),
		stubPart("StripeHousing", Vector3.new(13.6, 0.36, 0.22), CFrame.new(0, 2.5, -1.22), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("Stripe", Vector3.new(13.5, 0.2, 0.24), CFrame.new(0, 2.5, -1.23), CYAN, Enum.Material.Neon, { collide = false }),
		stubPart("PedestalL", Vector3.new(2.4, 3, 3), CFrame.new(-5.6, 1.5, 0), MARBLE_DARK, Enum.Material.Metal),
		stubPart("PedestalR", Vector3.new(2.4, 3, 3), CFrame.new(5.6, 1.5, 0), MARBLE_DARK, Enum.Material.Metal),
		-- Угловая панель тревоги слева
		stubPart("Panel", Vector3.new(2.4, 0.22, 0.96), CFrame.new(-6, 3.4, -0.58) * CFrame.Angles(math.rad(-14), 0, 0), MARBLE_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("PanelScreen", Vector3.new(1.05, 0.34, 0.04), CFrame.new(-5.95, 3.55, -0.35) * CFrame.Angles(math.rad(76), 0, 0), NAVY_DARK, nil, { collide = false }),
		stubPart("ButtonRed", Vector3.new(0.12, 0.28, 0.28), CFrame.new(-6.75, 3.52, -0.78) * CFrame.Angles(math.rad(-14), 0, math.rad(90)), RED, Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("ButtonGreen", Vector3.new(0.12, 0.28, 0.28), CFrame.new(-6.2, 3.52, -0.78) * CFrame.Angles(math.rad(-14), 0, math.rad(90)), hex("3FB56B"), Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("ButtonYellow", Vector3.new(0.12, 0.28, 0.28), CFrame.new(-5.65, 3.52, -0.78) * CFrame.Angles(math.rad(-14), 0, math.rad(90)), hex("FFD23F"), Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Микрофон на гибкой стойке и рация справа
		stubPart("MicBase", Vector3.new(0.12, 0.6, 0.6), CFrame.new(6.15, 3.36, -0.35) * CFrame.Angles(0, 0, math.rad(90)), hex("151821"), Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Microphone", Vector3.new(0.95, 0.08, 0.08), CFrame.new(6.15, 3.76, -0.45) * CFrame.Angles(math.rad(-25), 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("MicHead", Vector3.new(0.24, 0.22, 0.22), CFrame.new(6.15, 4.18, -0.64), hex("151821"), Enum.Material.Fabric, { shape = Enum.PartType.Ball, collide = false }),
		stubPart("MicRing", Vector3.new(0.05, 0.16, 0.16), CFrame.new(6.15, 4.08, -0.59) * CFrame.Angles(math.rad(-25), 0, math.rad(90)), RED, Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Кружка с кофе и ручкой
		stubPart("Mug", Vector3.new(0.46, 0.44, 0.44), CFrame.new(2.05, 3.53, -0.5) * CFrame.Angles(0, 0, math.rad(90)), hex("F2EEE6"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("CoffeeTop", Vector3.new(0.04, 0.36, 0.36), CFrame.new(2.05, 3.75, -0.5) * CFrame.Angles(0, 0, math.rad(90)), hex("2C1A0E"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("MugHandle", Vector3.new(0.12, 0.26, 0.08), CFrame.new(2.3, 3.53, -0.5), hex("F2EEE6"), nil, { collide = false }),
		-- Журнал смены и ручка
		stubPart("Papers", Vector3.new(1.05, 1.35, 0.05), CFrame.new(-2.05, 3.33, -0.35) * CFrame.Angles(0, math.rad(10), 0) * CFrame.Angles(math.rad(90), 0, 0), hex("FFFBF0"), nil, { collide = false }),
		stubPart("ClipboardClip", Vector3.new(0.46, 0.07, 0.14), CFrame.new(-1.94, 3.37, 0.26) * CFrame.Angles(0, math.rad(10), 0), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("Pen", Vector3.new(0.65, 0.05, 0.05), CFrame.new(-1.38, 3.33, -0.32) * CFrame.Angles(0, math.rad(-24), 0), NAVY, nil, { shape = Enum.PartType.Cylinder, collide = false }),
	}
	for _, x in { -7.02, 7.02 } do
		table.insert(list, stubPart("SideTrim", Vector3.new(0.08, 0.22, 3.24), CFrame.new(x, 3.15, 0), GOLD, Enum.Material.Metal, { collide = false }))
	end
	-- Фасадные кассеты и вертикальные рёбра под столешницей
	for _, x in { -3.2, 0, 3.2 } do
		table.insert(list, stubPart("FrontBay", Vector3.new(2.7, 1.8, 0.06), CFrame.new(x, 1.3, -1.31), NAVY_DARK, nil, { collide = false }))
		table.insert(list, stubPart("FrontBayTrim", Vector3.new(2.8, 0.08, 0.08), CFrame.new(x, 2.22, -1.31), GOLD, Enum.Material.Metal, { collide = false }))
	end
	for _, x in { -4.6, -1.6, 1.6, 4.6 } do
		table.insert(list, stubPart("FrontRib", Vector3.new(0.14, 2.4, 0.1), CFrame.new(x, 1.5, -1.3), STEEL_DARK, Enum.Material.Metal, { collide = false }))
	end
	-- Ящики в обеих тумбах (смотрят в −Z) и боковые вент-индикаторы
	for _, px in { -5.6, 5.6 } do
		for i, y in { 0.72, 1.52, 2.32 } do
			table.insert(list, stubPart("Drawer", Vector3.new(1.9, 0.64, 0.08), CFrame.new(px, y, -1.52), STEEL_DARK, Enum.Material.Metal, { collide = false }))
			table.insert(list, stubPart("DrawerPull", Vector3.new(0.65, 0.08, 0.08), CFrame.new(px, y + (if i == 3 then 0.05 else 0), -1.58), GOLD, Enum.Material.Metal, { collide = false }))
		end
	end
	-- 3 рабочих места (клавиатура + коврик + мышь + кабель-канал)
	for i, x in { -4, 0, 4 } do
		table.insert(list, stubPart("Keyboard" .. i, Vector3.new(1.95, 0.09, 0.68), CFrame.new(x - 0.15, 3.35, -0.72) * CFrame.Angles(math.rad(-4), 0, 0), hex("151821"), nil, { collide = false }))
		table.insert(list, stubPart("KeyCluster", Vector3.new(0.55, 0.04, 0.24), CFrame.new(x - 0.72, 3.4, -0.72) * CFrame.Angles(math.rad(-4), 0, 0), CYAN, Enum.Material.Neon, { collide = false }))
		table.insert(list, stubPart("MousePad", Vector3.new(0.75, 0.02, 0.85), CFrame.new(x + 1.25, 3.31, -0.68), NAVY_DARK, Enum.Material.Fabric, { collide = false }))
		table.insert(list, stubPart("Mouse", Vector3.new(0.26, 0.12, 0.4), CFrame.new(x + 1.25, 3.37, -0.68), hex("151821"), nil, { shape = Enum.PartType.Ball, collide = false }))
		table.insert(list, stubPart("Grommet", Vector3.new(0.04, 0.34, 0.34), CFrame.new(x, 3.31, 1.25) * CFrame.Angles(0, 0, math.rad(90)), STEEL_DARK, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }))
	end
	return list
end
local DESK_STUB: { ModelLibrary.StubPart } = buildDeskStub()

-- Монитор на подставке для пульта (R4): утяжелённая подставка, стойка с VESA-креплением,
-- двухцветный корпус со скосами и вентиляцией сзади, индикатор питания и светящийся экран Screen. Перед — в −Z.
local function buildMonitorStub(): { ModelLibrary.StubPart }
	local dark = hex("151821")
	return {
		stubPart("Foot", Vector3.new(1.08, 0.08, 0.74), CFrame.new(0, 0.04, 0), dark, Enum.Material.Metal),
		stubPart("FootStep", Vector3.new(0.8, 0.06, 0.54), CFrame.new(0, 0.11, 0.04), STEEL_DARK, Enum.Material.Metal),
		stubPart("Neck", Vector3.new(0.2, 0.78, 0.16), CFrame.new(0, 0.5, 0.15) * CFrame.Angles(math.rad(-10), 0, 0), STEEL_DARK, Enum.Material.Metal),
		stubPart("CableLoop", Vector3.new(0.14, 0.22, 0.12), CFrame.new(0, 0.45, 0.27), GOLD, Enum.Material.Metal),
		stubPart("VesaMount", Vector3.new(0.6, 0.55, 0.08), CFrame.new(0, 1.35, 0.14), STEEL_DARK, Enum.Material.Metal),
		stubPart("BackShell", Vector3.new(2.1, 1.15, 0.1), CFrame.new(0, 1.4, 0.09), NAVY, Enum.Material.Metal),
		stubPart("Frame", Vector3.new(2.6, 1.6, 0.14), CFrame.new(0, 1.4, 0), dark),
		stubPart("FrameBevelTop", Vector3.new(2.6, 0.08, 0.1), CFrame.new(0, 2.22, 0.02) * CFrame.Angles(math.rad(180), 0, 0), NAVY, nil, { wedge = true }),
		stubPart("TopLip", Vector3.new(2.6, 0.08, 0.08), CFrame.new(0, 2.16, -0.09), dark),
		stubPart("BottomChin", Vector3.new(2.6, 0.14, 0.08), CFrame.new(0, 0.67, -0.09), STEEL_DARK, Enum.Material.Metal),
		stubPart("SideL", Vector3.new(0.08, 1.56, 0.08), CFrame.new(-1.26, 1.4, -0.09), dark),
		stubPart("SideR", Vector3.new(0.08, 1.56, 0.08), CFrame.new(1.26, 1.4, -0.09), dark),
		stubPart("BrandBadge", Vector3.new(0.32, 0.06, 0.04), CFrame.new(0, 0.67, -0.13), GOLD, Enum.Material.Metal),
		stubPart("PowerLed", Vector3.new(0.08, 0.05, 0.04), CFrame.new(1.06, 0.67, -0.13), hex("3FB56B"), Enum.Material.Neon),
		stubPart("Vent1", Vector3.new(1.4, 0.06, 0.04), CFrame.new(0, 1.78, 0.15), dark),
		stubPart("Vent2", Vector3.new(1.4, 0.06, 0.04), CFrame.new(0, 1.62, 0.15), dark),
		stubPart("Screen", Vector3.new(2.4, 1.38, 0.04), CFrame.new(0, 1.43, -0.085), CYAN, Enum.Material.Neon, { transparency = 0.12 }),
	}
end
local MONITOR_STUB: { ModelLibrary.StubPart } = buildMonitorStub()

-- Офисное кресло охранника: спинка сзади (+Z), сидящий смотрит в −Z.
local CHAIR_STUB: { ModelLibrary.StubPart } = {
	{ name = "Seat", size = Vector3.new(2, 0.4, 2), offset = CFrame.new(0, 1.9, 0), color = hex("1E2A44"), material = Enum.Material.Fabric },
	{ name = "Back", size = Vector3.new(2, 2.4, 0.35), offset = CFrame.new(0, 3.3, 0.9) * CFrame.Angles(math.rad(-8), 0, 0), color = hex("1E2A44"), material = Enum.Material.Fabric },
	{ name = "Column", size = Vector3.new(0.25, 1.4, 0.25), offset = CFrame.new(0, 1, 0), color = hex("8A93A6"), material = Enum.Material.Metal },
	{ name = "LegX", size = Vector3.new(2, 0.2, 0.25), offset = CFrame.new(0, 0.3, 0), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "LegZ", size = Vector3.new(0.25, 0.2, 2), offset = CFrame.new(0, 0.3, 0), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "ArmL", size = Vector3.new(0.2, 0.2, 1.4), offset = CFrame.new(-1.05, 2.7, 0.1), color = hex("151821") },
	{ name = "ArmR", size = Vector3.new(0.2, 0.2, 1.4), offset = CFrame.new(1.05, 2.7, 0.1), color = hex("151821") },
}

-- Кулер с бутылью воды (Glass) и стаканчиками (R4). Перед — в −Z.
local function buildCoolerStub(): { ModelLibrary.StubPart }
	local cream = hex("F2EEE6")
	local coldBlue = hex("3B7DD8")
	local list: { ModelLibrary.StubPart } = {
		stubPart("Plinth", Vector3.new(1.42, 0.14, 1.42), CFrame.new(0, 0.07, 0), MARBLE_DARK, Enum.Material.Metal),
		stubPart("Body", Vector3.new(1.4, 2.86, 1.4), CFrame.new(0, 1.57, 0), cream),
		stubPart("SideStripeL", Vector3.new(0.04, 2.6, 0.26), CFrame.new(-0.71, 1.55, -0.35), NAVY, nil, { collide = false }),
		stubPart("SideStripeR", Vector3.new(0.04, 2.6, 0.26), CFrame.new(0.71, 1.55, -0.35), NAVY, nil, { collide = false }),
		stubPart("TopRim", Vector3.new(1.44, 0.14, 1.44), CFrame.new(0, 3.04, 0), NAVY, Enum.Material.Metal, { collide = false }),
		stubPart("BottleCollar", Vector3.new(0.18, 0.88, 0.88), CFrame.new(0, 3.16, 0) * CFrame.Angles(0, 0, math.rad(90)), coldBlue, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Ниша раздачи воды с решёткой и стаканчиком
		stubPart("AlcoveBack", Vector3.new(1.02, 0.86, 0.08), CFrame.new(0, 2.28, -0.69), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("CoolerBadge", Vector3.new(0.96, 0.34, 0.04), CFrame.new(0, 2.82, -0.72), NAVY, nil, { collide = false }),
		stubPart("DripTray", Vector3.new(1.08, 0.1, 0.36), CFrame.new(0, 1.82, -0.78), CHROME, Enum.Material.Metal, { collide = false }),
		stubPart("DripGrate", Vector3.new(0.96, 0.03, 0.28), CFrame.new(0, 1.88, -0.78), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("TrayCup", Vector3.new(0.24, 0.22, 0.22), CFrame.new(-0.25, 2.01, -0.78) * CFrame.Angles(0, 0, math.rad(90)), hex("FFFBF0"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Краны холодной и горячей воды + лампочки
		stubPart("TapBlue", Vector3.new(0.16, 0.22, 0.18), CFrame.new(-0.25, 2.48, -0.78), coldBlue, nil, { collide = false }),
		stubPart("TapBlueSpout", Vector3.new(0.12, 0.09, 0.09), CFrame.new(-0.25, 2.34, -0.8) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("TapBlueLed", Vector3.new(0.08, 0.08, 0.04), CFrame.new(-0.25, 2.62, -0.75), CYAN, Enum.Material.Neon, { collide = false }),
		stubPart("TapRed", Vector3.new(0.16, 0.22, 0.18), CFrame.new(0.25, 2.48, -0.78), RED, nil, { collide = false }),
		stubPart("TapRedSpout", Vector3.new(0.12, 0.09, 0.09), CFrame.new(0.25, 2.34, -0.8) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("TapRedLed", Vector3.new(0.08, 0.08, 0.04), CFrame.new(0.25, 2.62, -0.75), hex("FF6B4A"), Enum.Material.Neon, { collide = false }),
		-- Нижняя дверца шкафчика и прорези вентиляции
		stubPart("LowerDoor", Vector3.new(1.12, 1.38, 0.05), CFrame.new(0, 0.96, -0.71), hex("E2DDD3"), nil, { collide = false }),
		-- Прозрачная бутыль воды с видимым уровнем воды внутри
		stubPart("WaterLevel", Vector3.new(0.84, 1.02, 1.02), CFrame.new(0, 3.66, 0) * CFrame.Angles(0, 0, math.rad(90)), CYAN, Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.35, collide = false }),
		stubPart("Bottle", Vector3.new(1.42, 1.14, 1.14), CFrame.new(0, 3.92, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("7FC8F8"), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.56 }),
		stubPart("BottleShoulder", Vector3.new(0.22, 0.72, 0.72), CFrame.new(0, 4.65, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("7FC8F8"), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.56, collide = false }),
		stubPart("Cap", Vector3.new(0.22, 0.48, 0.48), CFrame.new(0, 4.82, 0) * CFrame.Angles(0, 0, math.rad(90)), coldBlue, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Держатель стаканчиков сбоку
		stubPart("CupMount", Vector3.new(0.18, 0.12, 0.22), CFrame.new(0.76, 2.32, 0), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("CupStack", Vector3.new(0.72, 0.22, 0.22), CFrame.new(0.86, 2.22, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("FFFBF0"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Cups", Vector3.new(0.92, 0.32, 0.32), CFrame.new(0.86, 2.22, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("CFE8F5"), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.58, collide = false }),
		stubPart("CupsCap", Vector3.new(0.08, 0.35, 0.35), CFrame.new(0.86, 2.71, 0) * CFrame.Angles(0, 0, math.rad(90)), coldBlue, nil, { shape = Enum.PartType.Cylinder, collide = false }),
	}
	for _, y in { 3.55, 3.92, 4.28 } do
		table.insert(list, stubPart("BottleRib", Vector3.new(0.05, 1.18, 1.18), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("9BD7FF"), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.5, collide = false }))
	end
	for _, y in { 0.72, 0.54, 0.36 } do
		table.insert(list, stubPart("VentSlit", Vector3.new(0.8, 0.06, 0.04), CFrame.new(0, y, -0.74), STEEL_DARK, nil, { collide = false }))
	end
	return list
end
local COOLER_STUB: { ModelLibrary.StubPart } = buildCoolerStub()

-- Кофемашина на деревянной тумбе с мраморной столешницей, бункером зёрен (Glass), рожком и кружками (R4). Перед — в −Z.
local function buildCoffeeStub(): { ModelLibrary.StubPart }
	local dark = hex("151821")
	local list: { ModelLibrary.StubPart } = {
		stubPart("Plinth", Vector3.new(2.32, 0.2, 1.52), CFrame.new(0, 0.1, 0.02), NAVY_DARK, Enum.Material.Metal),
		stubPart("Cabinet", Vector3.new(2.4, 2.6, 1.6), CFrame.new(0, 1.5, 0), WOOD, Enum.Material.Wood),
		stubPart("CabinetTop", Vector3.new(2.5, 0.15, 1.7), CFrame.new(0, 2.88, 0), MARBLE, Enum.Material.Marble),
		stubPart("TopEdge", Vector3.new(2.52, 0.06, 0.08), CFrame.new(0, 2.8, -0.84), GOLD, Enum.Material.Metal, { collide = false }),
		-- Корпус эспрессо-машины
		stubPart("DripBase", Vector3.new(1.26, 0.12, 1.08), CFrame.new(-0.42, 3.01, 0.04), CHROME, Enum.Material.Metal, { collide = false }),
		stubPart("DripGrate", Vector3.new(1.12, 0.03, 0.42), CFrame.new(-0.42, 3.08, -0.28), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		stubPart("Machine", Vector3.new(1.24, 1.32, 0.92), CFrame.new(-0.42, 3.7, 0.12), dark, Enum.Material.Metal),
		stubPart("MachineCrown", Vector3.new(1.28, 0.1, 0.96), CFrame.new(-0.42, 4.38, 0.12), CHROME, Enum.Material.Metal, { collide = false }),
		stubPart("MachineFront", Vector3.new(1.14, 0.48, 0.06), CFrame.new(-0.42, 4.04, -0.36), RED, nil, { collide = false }),
		stubPart("FrontBand", Vector3.new(1.18, 0.06, 0.07), CFrame.new(-0.42, 3.79, -0.36), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("BrewRecess", Vector3.new(1.06, 0.64, 0.12), CFrame.new(-0.42, 3.42, -0.32), STEEL_DARK, Enum.Material.Metal, { collide = false }),
		-- Группа, рожок, носики и чашка под кофе
		stubPart("GroupHead", Vector3.new(0.16, 0.36, 0.36), CFrame.new(-0.42, 3.68, -0.24) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("PortafilterHandle", Vector3.new(0.45, 0.08, 0.08), CFrame.new(-0.42, 3.64, -0.52) * CFrame.Angles(0, math.rad(90), 0), WOOD_DARK, Enum.Material.Wood, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Spout", Vector3.new(0.14, 0.14, 0.1), CFrame.new(-0.42, 3.5, -0.24), CHROME, Enum.Material.Metal, { collide = false }),
		stubPart("BrewCup", Vector3.new(0.28, 0.28, 0.28), CFrame.new(-0.42, 3.22, -0.24) * CFrame.Angles(0, 0, math.rad(90)), hex("FFFBF0"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("BrewCoffee", Vector3.new(0.03, 0.22, 0.22), CFrame.new(-0.42, 3.35, -0.24) * CFrame.Angles(0, 0, math.rad(90)), hex("2C1A0E"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Манометр и кнопки с подсветкой
		stubPart("Gauge", Vector3.new(0.05, 0.24, 0.24), CFrame.new(-0.76, 4.04, -0.4) * CFrame.Angles(0, math.rad(90), 0), MARBLE, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("GaugeRim", Vector3.new(0.04, 0.28, 0.28), CFrame.new(-0.76, 4.04, -0.39) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Light", Vector3.new(0.05, 0.1, 0.1), CFrame.new(-0.02, 4.14, -0.4) * CFrame.Angles(0, math.rad(90), 0), hex("3FB56B"), Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("BtnAmber", Vector3.new(0.05, 0.1, 0.1), CFrame.new(-0.18, 4.14, -0.4) * CFrame.Angles(0, math.rad(90), 0), GOLD_BRIGHT, Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("BtnCyan", Vector3.new(0.05, 0.1, 0.1), CFrame.new(-0.34, 4.14, -0.4) * CFrame.Angles(0, math.rad(90), 0), CYAN, Enum.Material.Neon, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("SteamWand", Vector3.new(0.42, 0.05, 0.05), CFrame.new(0.08, 3.46, -0.26) * CFrame.Angles(0, 0, math.rad(72)), CHROME, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Бункер кофейных зёрен сверху (стекло + тёмные зёрна внутри)
		stubPart("BeanCore", Vector3.new(0.32, 0.42, 0.32), CFrame.new(-0.42, 4.58, 0.14) * CFrame.Angles(0, 0, math.rad(90)), hex("3A2212"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("BeanHopper", Vector3.new(0.48, 0.54, 0.54), CFrame.new(-0.42, 4.66, 0.14) * CFrame.Angles(0, 0, math.rad(90)), hex("C8E4F0"), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.55, collide = false }),
		stubPart("HopperLid", Vector3.new(0.08, 0.58, 0.58), CFrame.new(-0.42, 4.92, 0.14) * CFrame.Angles(0, 0, math.rad(90)), dark, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		-- Кружки, подставка и мини-меню справа на столешнице
		stubPart("MugA", Vector3.new(0.4, 0.38, 0.38), CFrame.new(0.55, 3.15, -0.22) * CFrame.Angles(0, 0, math.rad(90)), NAVY, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("MugAHandle", Vector3.new(0.1, 0.24, 0.07), CFrame.new(0.76, 3.15, -0.22), NAVY, nil, { collide = false }),
		stubPart("MugB", Vector3.new(0.4, 0.38, 0.38), CFrame.new(0.92, 3.15, 0.28) * CFrame.Angles(0, 0, math.rad(90)), GOLD, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("MugBHandle", Vector3.new(0.1, 0.24, 0.07), CFrame.new(1.13, 3.15, 0.28), GOLD, nil, { collide = false }),
		stubPart("SugarCaddy", Vector3.new(0.42, 0.32, 0.34), CFrame.new(0.52, 3.11, 0.42), MARBLE, nil, { collide = false }),
		stubPart("CoffeeMenu", Vector3.new(0.68, 0.48, 0.05), CFrame.new(0.92, 3.18, -0.36) * CFrame.Angles(math.rad(-18), math.rad(14), 0), NAVY_DARK, nil, { collide = false }),
	}
	-- Дверцы тумбы и латунные ручки
	for _, x in { -0.56, 0.56 } do
		table.insert(list, stubPart("CabinetDoor", Vector3.new(1.02, 2.24, 0.06), CFrame.new(x, 1.48, -0.81), hex("6B462B"), Enum.Material.Wood, { collide = false }))
		table.insert(list, stubPart("Handle", Vector3.new(0.08, 0.46, 0.08), CFrame.new(x + (if x < 0 then 0.34 else -0.34), 2.1, -0.87), GOLD, Enum.Material.Metal, { collide = false }))
	end
	return list
end
local COFFEE_STUB: { ModelLibrary.StubPart } = buildCoffeeStub()

-- Пробковая доска объявлений (R4): деревянная рама с латунными уголками, полка с маркерами,
-- пробка, лист Paper под HOW TO PLAY (грань −Z открыта), стикеры, кнопки-гвоздики и красная нить. Перед — в −Z.
local function buildNoticeStub(): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {
		stubPart("Backboard", Vector3.new(6.1, 4.1, 0.1), CFrame.new(0, 2.1, 0.06), WOOD, Enum.Material.Wood, { collide = false }),
		stubPart("Cork", Vector3.new(5.8, 3.8, 0.1), CFrame.new(0, 2.1, -0.06), hex("B08850"), Enum.Material.Sand, { collide = false }),
		-- Планки рамы по периметру
		stubPart("FrameTop", Vector3.new(6.24, 0.22, 0.24), CFrame.new(0, 4.1, -0.02), WOOD, Enum.Material.Wood, { collide = false }),
		stubPart("FrameBottom", Vector3.new(6.24, 0.22, 0.24), CFrame.new(0, 0.1, -0.02), WOOD, Enum.Material.Wood, { collide = false }),
		stubPart("FrameL", Vector3.new(0.22, 3.82, 0.24), CFrame.new(-3.01, 2.1, -0.02), WOOD, Enum.Material.Wood, { collide = false }),
		stubPart("FrameR", Vector3.new(0.22, 3.82, 0.24), CFrame.new(3.01, 2.1, -0.02), WOOD, Enum.Material.Wood, { collide = false }),
		-- Полка для маркеров внизу
		stubPart("Tray", Vector3.new(5.7, 0.1, 0.28), CFrame.new(0, 0.16, -0.2), WOOD_DARK, Enum.Material.Wood, { collide = false }),
		stubPart("MarkerRed", Vector3.new(0.55, 0.08, 0.08), CFrame.new(-1.8, 0.25, -0.22), RED, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("MarkerCyan", Vector3.new(0.55, 0.08, 0.08), CFrame.new(-1.1, 0.25, -0.22), CYAN, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Eraser", Vector3.new(0.55, 0.12, 0.18), CFrame.new(1.5, 0.27, -0.22), NAVY, Enum.Material.Fabric, { collide = false }),
		-- Главный лист Paper (HOW TO PLAY) и подложка
		stubPart("PaperShadow", Vector3.new(3.84, 3.34, 0.03), CFrame.new(-0.74, 2.08, -0.125) * CFrame.Angles(0, 0, math.rad(-1.5)), MARBLE, nil, { collide = false }),
		stubPart("Paper", Vector3.new(3.76, 3.26, 0.04), CFrame.new(-0.76, 2.1, -0.15), hex("FFFBF0"), nil, { collide = false }),
		-- Правые заметки и заголовок доски
		stubPart("NoteHeader", Vector3.new(1.35, 0.42, 0.04), CFrame.new(2.05, 3.66, -0.145), CYAN, nil, { collide = false }),
		stubPart("NoteYellow", Vector3.new(1.16, 1.12, 0.04), CFrame.new(2.08, 2.75, -0.15) * CFrame.Angles(0, 0, math.rad(6)), hex("FFE38A"), nil, { collide = false }),
		stubPart("NotePink", Vector3.new(1.14, 1.02, 0.04), CFrame.new(2.14, 1.35, -0.15) * CFrame.Angles(0, 0, math.rad(-5)), hex("F7B7C8"), nil, { collide = false }),
		stubPart("String", Vector3.new(0.03, 1.4, 0.02), CFrame.new(2.11, 2.52, -0.17) * CFrame.Angles(0, 0, math.rad(2)), RED, nil, { collide = false }),
		-- Кнопки-гвоздики
		stubPart("Pin1", Vector3.new(0.12, 0.18, 0.18), CFrame.new(-0.76, 3.64, -0.2) * CFrame.Angles(0, math.rad(90), 0), RED, nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Pin2", Vector3.new(0.12, 0.18, 0.18), CFrame.new(2.08, 3.22, -0.2) * CFrame.Angles(0, math.rad(90), 0), hex("3B7DD8"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Pin3", Vector3.new(0.12, 0.18, 0.18), CFrame.new(2.14, 1.78, -0.2) * CFrame.Angles(0, math.rad(90), 0), hex("3FB56B"), nil, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Pin4", Vector3.new(0.12, 0.16, 0.16), CFrame.new(2.05, 3.82, -0.2) * CFrame.Angles(0, math.rad(90), 0), GOLD_BRIGHT, nil, { shape = Enum.PartType.Cylinder, collide = false }),
	}
	for _, x in { -3.01, 3.01 } do
		for _, y in { 0.1, 4.1 } do
			table.insert(list, stubPart("CornerBrass", Vector3.new(0.28, 0.28, 0.27), CFrame.new(x, y, -0.02), GOLD, Enum.Material.Metal, { collide = false }))
		end
	end
	return list
end
local NOTICE_STUB: { ModelLibrary.StubPart } = buildNoticeStub()

-- Кубок «лучшая смена» в стеклянной витрине (Glass) на постаменте с золотыми пилястрами и табличкой (R4). Перед — в −Z.
local function buildTrophyStub(): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {
		-- Постамент (0 .. 3.4)
		stubPart("PedestalBase", Vector3.new(2.7, 0.26, 2.7), CFrame.new(0, 0.13, 0), GOLD, Enum.Material.Metal),
		stubPart("BaseStep", Vector3.new(2.5, 0.14, 2.5), CFrame.new(0, 0.33, 0), MARBLE_DARK, Enum.Material.Marble),
		stubPart("Pedestal", Vector3.new(2.3, 2.68, 2.3), CFrame.new(0, 1.74, 0), NAVY),
		stubPart("PedestalCornice", Vector3.new(2.54, 0.14, 2.54), CFrame.new(0, 3.15, 0), GOLD, Enum.Material.Metal),
		stubPart("PedestalTop", Vector3.new(2.7, 0.18, 2.7), CFrame.new(0, 3.31, 0), GOLD, Enum.Material.Metal),
		stubPart("Plaque", Vector3.new(1.64, 0.68, 0.06), CFrame.new(0, 1.8, -1.18), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("PlaqueFace", Vector3.new(1.48, 0.52, 0.04), CFrame.new(0, 1.8, -1.2), NAVY_DARK, nil, { collide = false }),
		-- Стеклянная витрина сверху (3.4 .. 6.2)
		stubPart("CaseGlass", Vector3.new(2.14, 2.66, 2.14), CFrame.new(0, 4.74, 0), hex("CFE8F5"), Enum.Material.Glass, { transparency = 0.62, collide = false }),
		stubPart("CaseCap", Vector3.new(2.26, 0.12, 2.26), CFrame.new(0, 6.13, 0), GOLD, Enum.Material.Metal, { collide = false }),
		stubPart("CaseFinial", Vector3.new(1.7, 0.1, 1.7), CFrame.new(0, 6.24, 0), GOLD_BRIGHT, Enum.Material.Metal, { collide = false }),
		-- Пьедестал кубка внутри витрины
		stubPart("Plinth", Vector3.new(1.16, 0.42, 1.16), CFrame.new(0, 3.61, 0), hex("151821")),
		stubPart("PlinthTag", Vector3.new(0.84, 0.22, 0.04), CFrame.new(0, 3.61, -0.59), GOLD, Enum.Material.Metal, { collide = false }),
		-- Многоступенчатая ножка и чаша кубка
		stubPart("StemFoot", Vector3.new(0.16, 0.84, 0.84), CFrame.new(0, 3.9, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Stem", Vector3.new(0.76, 0.28, 0.28), CFrame.new(0, 4.32, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("StemRing", Vector3.new(0.1, 0.44, 0.44), CFrame.new(0, 4.44, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD_BRIGHT, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("CupBase", Vector3.new(0.86, 0.72, 0.86), CFrame.new(0, 4.92, 0), GOLD, Enum.Material.Metal, { sphere = true, collide = false }),
		stubPart("Cup", Vector3.new(0.78, 1.24, 1.24), CFrame.new(0, 5.32, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { shape = Enum.PartType.Cylinder }),
		stubPart("Rim", Vector3.new(0.14, 1.38, 1.38), CFrame.new(0, 5.74, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD_BRIGHT, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("CupInner", Vector3.new(0.06, 1.14, 1.14), CFrame.new(0, 5.79, 0) * CFrame.Angles(0, 0, math.rad(90)), hex("7A5812"), Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false }),
		stubPart("Star", Vector3.new(0.36, 0.36, 0.08), CFrame.new(0, 5.32, -0.63) * CFrame.Angles(0, 0, math.rad(45)), hex("FFFFFF"), Enum.Material.Neon, { collide = false }),
		stubPart("StarTop", Vector3.new(0.24, 0.24, 0.24), CFrame.new(0, 5.92, 0) * CFrame.Angles(0, 0, math.rad(45)), GOLD_BRIGHT, Enum.Material.Neon, { collide = false }),
	}
	-- Угловые пилястры постамента и стойки стеклянной витрины
	for _, x in { -1.08, 1.08 } do
		for _, z in { -1.08, 1.08 } do
			table.insert(list, stubPart("PedestalPilaster", Vector3.new(0.18, 2.7, 0.18), CFrame.new(x, 1.74, z), GOLD, Enum.Material.Metal, { collide = false }))
			table.insert(list, stubPart("CasePost", Vector3.new(0.08, 2.68, 0.08), CFrame.new(x, 4.74, z), GOLD, Enum.Material.Metal, { collide = false }))
		end
	end
	-- Изогнутые ручки кубка слева и справа
	for _, side in { -1, 1 } do
		table.insert(list, stubPart("HandleTop", Vector3.new(0.32, 0.1, 0.12), CFrame.new(side * 0.72, 5.62, 0), GOLD, Enum.Material.Metal, { collide = false }))
		table.insert(list, stubPart("HandleMid", Vector3.new(0.12, 0.62, 0.12), CFrame.new(side * 0.86, 5.33, 0), GOLD, Enum.Material.Metal, { collide = false }))
		table.insert(list, stubPart("HandleLow", Vector3.new(0.34, 0.1, 0.12), CFrame.new(side * 0.68, 5.02, 0), GOLD, Enum.Material.Metal, { collide = false }))
	end
	return list
end
local TROPHY_STUB: { ModelLibrary.StubPart } = buildTrophyStub()

---------------------------------------------------------------- части комнаты

type Kit = MapBuilder.RoomKit

-- Надпись на детали модели по имени (если деталь найдена).
local function labelOnPart(
	kit: Kit,
	model: Instance,
	partName: string,
	text: string,
	textColor: Color3,
	font: Enum.Font?,
	lightInfluence: number?
)
	local part = model:FindFirstChild(partName, true)
	if not (part and part:IsA("BasePart")) then
		return
	end
	local gui = kit.kit.surfaceGui(part, Enum.NormalId.Front, 70, lightInfluence or 0.5)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.06, 0.06)
	label.Size = UDim2.fromScale(0.88, 0.88)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

-- Надпись на детали шрифтом камер (моноширинный) — для мониторов.
local function monoLabel(parent: Instance, name: string, text: string, position: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align
	label.Text = text
	label.ZIndex = 8
	label.Parent = parent
	return label
end

-- Мини-интерфейс наблюдения на настольном мониторе пульта (Screen остаётся светящимся).
local function drawDeskScreen(kit: Kit, screen: BasePart, channel: number)
	local k = kit.kit
	local gui = k.surfaceGui(screen, Enum.NormalId.Front, 64, 0)
	local root = k.guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), hex("0A1D29"), 1)
	root.BackgroundTransparency = 0.2
	k.guiFrame(root, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.18), NAVY_DARK, 2)
	monoLabel(root, "Head", ("SYS %02d  •  ONLINE"):format(channel), UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.75, 0.14), CYAN, Enum.TextXAlignment.Left)
	local dot = k.guiFrame(root, UDim2.fromScale(0.88, 0.05), UDim2.fromScale(0.05, 0.09), hex("3FB56B"), 3)
	k.corner(dot, UDim.new(0.5, 0))
	for i = 1, 4 do
		local barH = 0.18 + ((channel + i) % 4) * 0.12
		k.guiFrame(root, UDim2.fromScale(0.08 + (i - 1) * 0.22, 0.82 - barH), UDim2.fromScale(0.14, barH), CYAN, 2)
	end
	monoLabel(root, "Foot", "MUSEUM TELEMETRY", UDim2.fromScale(0.05, 0.85), UDim2.fromScale(0.9, 0.11), MARBLE, Enum.TextXAlignment.Center)
end

-- Картинка камеры на мониторе: стена, пол, предмет в середине, полосы помех, CAM N, REC и часы.
local function drawFeed(kit: Kit, screen: BasePart, index: number, title: string, sceneName: string)
	local k = kit.kit
	local scene = SCENES[sceneName] or SCENES.Hall
	local gui = k.surfaceGui(screen, Enum.NormalId.Front, 36, 0)
	local root = k.guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), hex(scene.wall), 1)
	root.ClipsDescendants = true
	-- Пол и «глубина»: тёмные края стен слева и справа
	k.guiFrame(root, UDim2.fromScale(0, 0.64), UDim2.fromScale(1, 0.36), hex(scene.floor), 2)
	local left = k.guiFrame(root, UDim2.fromScale(0, 0), UDim2.fromScale(0.13, 1), Color3.new(0, 0, 0), 3)
	left.BackgroundTransparency = 0.6
	local right = k.guiFrame(root, UDim2.fromScale(0.87, 0), UDim2.fromScale(0.13, 1), Color3.new(0, 0, 0), 3)
	right.BackgroundTransparency = 0.6
	local thing = hex(scene.thing)
	if sceneName == "Painting" then
		k.guiFrame(root, UDim2.fromScale(0.39, 0.12), UDim2.fromScale(0.22, 0.46), thing, 4)
		local canvas = k.guiFrame(root, UDim2.fromScale(0.415, 0.17), UDim2.fromScale(0.17, 0.36), hex("6E5B3A"), 5)
		local face = k.guiFrame(canvas, UDim2.fromScale(0.3, 0.15), UDim2.fromScale(0.4, 0.38), hex("D9B48A"), 6)
		k.corner(face, UDim.new(0.5, 0))
		k.guiFrame(root, UDim2.fromScale(0.3, 0.6), UDim2.fromScale(0.4, 0.04), hex("D4A93A"), 4) -- канат ограждения
	elseif sceneName == "Arch" or sceneName == "Plaza" then
		local arch = k.guiFrame(root, UDim2.fromScale(0.4, 0.2), UDim2.fromScale(0.2, 0.44), Color3.new(0, 0, 0), 4)
		arch.BackgroundTransparency = 0.35
		k.corner(arch, UDim.new(0.3, 0))
		k.guiFrame(root, UDim2.fromScale(0.45, 0.64), UDim2.fromScale(0.1, 0.36), thing, 4) -- ковровая дорожка
	elseif sceneName == "Space" or sceneName == "Roof" then
		for i = 1, 14 do
			local x = (i * 37 % 100) / 100
			local y = (i * 53 % 60) / 100
			local star = k.guiFrame(root, UDim2.fromScale(x, y), UDim2.fromScale(0.012, 0.025), Color3.new(1, 1, 1), 4)
			k.corner(star, UDim.new(0.5, 0))
		end
		local planet = k.guiFrame(root, UDim2.fromScale(0.42, 0.24), UDim2.fromScale(0.13, 0.27), thing, 4)
		k.corner(planet, UDim.new(0.5, 0))
	else
		-- Постамент с экспонатом
		k.guiFrame(root, UDim2.fromScale(0.44, 0.42), UDim2.fromScale(0.12, 0.26), hex("F2EEE6"), 4)
		local item = k.guiFrame(root, UDim2.fromScale(0.455, 0.27), UDim2.fromScale(0.09, 0.17), thing, 5)
		k.corner(item, UDim.new(0.35, 0))
	end
	-- Полосы помех
	for i = 1, 4 do
		local line = k.guiFrame(root, UDim2.fromScale(0, (i * 0.23 + index * 0.07) % 1), UDim2.fromScale(1, 0.018), Color3.new(1, 1, 1), 7)
		line.BackgroundTransparency = 0.88
	end
	monoLabel(root, "Title", ("CAM %02d  %s"):format(index, title), UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.7, 0.16), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
	local rec = k.guiFrame(root, UDim2.fromScale(0.82, 0.05), UDim2.fromScale(0.035, 0.075), hex("FF3B3B"), 8)
	rec.Name = "RecDot"
	k.corner(rec, UDim.new(0.5, 0))
	monoLabel(root, "Rec", "REC", UDim2.fromScale(0.86, 0.03), UDim2.fromScale(0.12, 0.13), hex("FF3B3B"), Enum.TextXAlignment.Left)
	monoLabel(root, "Clock", "00:00:00", UDim2.fromScale(0.03, 0.83), UDim2.fromScale(0.35, 0.13), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
end

-- Северная стена: 18 мониторов в рамке, вывеска SECURITY CONTROL, пульт и кресла.
local function buildMonitorWall(kit: Kit, map: Folder)
	local k = kit.kit
	local colors = k.colors
	local wallZ = -HALF_Z
	local cols, rows = 6, 3
	local screenW, screenH, gapX, gapY = 6.8, 3, 0.6, 0.45
	local totalW = cols * screenW + (cols - 1) * gapX
	local totalH = rows * screenH + (rows - 1) * gapY
	local bottom = 6
	local centerY = bottom + totalH / 2
	-- Тёмная стойка под мониторами и золотая рама
	k.decor("ScreenRack", Vector3.new(totalW + 1.6, totalH + 1.4, 0.4), CFrame.new(0, centerY, wallZ + 0.2), STEEL_DARK, Enum.Material.Metal)
	for _, edge in { { 0, totalH / 2 + 0.75, totalW + 2, 0.3 }, { 0, -totalH / 2 - 0.75, totalW + 2, 0.3 } } do
		k.decor("ScreenRackTrim", Vector3.new(edge[3], edge[4], 0.5), CFrame.new(edge[1], centerY + edge[2], wallZ + 0.25), colors.Gold, Enum.Material.Metal)
	end
	for _, x in { -(totalW / 2 + 0.9), totalW / 2 + 0.9 } do
		k.decor("ScreenRackTrim", Vector3.new(0.3, totalH + 1.8, 0.5), CFrame.new(x, centerY, wallZ + 0.25), colors.Gold, Enum.Material.Metal)
	end
	local screens = Instance.new("Folder")
	screens.Name = MapSchema.MonitorScreens
	screens.Parent = map
	local index = 0
	for row = 1, rows do
		for col = 1, cols do
			index += 1
			local x = -totalW / 2 + screenW / 2 + (col - 1) * (screenW + gapX)
			local y = bottom + totalH - screenH / 2 - (row - 1) * (screenH + gapY)
			local position = Vector3.new(x, y, wallZ + 0.45)
			k.decor("ScreenBezel", Vector3.new(screenW + 0.3, screenH + 0.3, 0.12), CFrame.new(position), hex("151821"))
			local screen = kit.part(screens, "Screen" .. index, Vector3.new(screenW, screenH, 0.08), CFrame.lookAt(position + Vector3.new(0, 0, 0.08), position + Vector3.new(0, 0, 1)), SCREEN)
			screen.CanCollide = false
			screen.CanQuery = false
			screen.CastShadow = false
			local feed = FEEDS[index] or FEEDS[1]
			drawFeed(kit, screen, index, feed.title, feed.scene)
		end
	end
	-- Голубой отсвет экранов на пол и пульт
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = Config.Hub.MonitorLight.Range
	light.Brightness = Config.Hub.MonitorLight.Brightness
	light.Color = Config.Hub.MonitorLight.Color
	light.Angle = 120
	local emitter = kit.part(map, "MonitorLight", Vector3.new(totalW, totalH, 0.1), CFrame.lookAt(Vector3.new(0, centerY, wallZ + 0.7), Vector3.new(0, centerY, wallZ + 2)), SCREEN)
	emitter.Transparency = 1
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	light.Parent = emitter

	-- Вывеска над мониторами
	k.sign(Vector3.new(0, bottom + totalH + 2.1, wallZ), Vector3.new(0, 0, 1), 22, 1.8, "SECURITY CONTROL")

	-- Пульт из двух столов, на каждом 3 монитора, перед пультом 3 кресла
	local channel = 0
	for _, x in { -7.2, 7.2 } do
		local desk = k.place(Models.Desk, CFrame.new(x, 0, wallZ + 4.4) * CFrame.Angles(0, math.pi, 0), DESK_STUB)
		labelOnPart(kit, desk, "PanelScreen", "ALARM  •  LOCKDOWN", CYAN, Enum.Font.Code, 0)
		labelOnPart(kit, desk, "Papers", "SHIFT LOG\n• Cameras: OK\n• Doors: LOCKED\n• Guards: ON DUTY", NAVY, Enum.Font.GothamBold, 0.9)
		for _, dx in { -4, 0, 4 } do
			channel += 1
			local monitor = k.place(Models.Monitor, CFrame.new(x + dx, 3.3, wallZ + 3.6) * CFrame.Angles(0, math.pi, 0), MONITOR_STUB, false)
			-- Экран монитора светится, как у стены
			local screenPart = monitor:FindFirstChild("Screen", true)
			if screenPart and screenPart:IsA("BasePart") then
				screenPart.CastShadow = false
				drawDeskScreen(kit, screenPart, channel)
			end
		end
	end
	for _, x in { -9, 0, 9 } do
		k.place(Models.Chair, CFrame.new(x, 0, wallZ + 8.2) * CFrame.Angles(0, math.rad((x / 9) * 8), 0), CHAIR_STUB)
	end
end

-- Плакат WANTED с портретом вора в маске.
local function wantedPoster(kit: Kit, point: Vector3, facing: Vector3, name: string, mask: Color3, tilt: number)
	local k = kit.kit
	local look = CFrame.lookAt(point, point + facing) * CFrame.Angles(0, 0, math.rad(tilt))
	local paper = k.decor("WantedPoster", Vector3.new(3.2, 4.2, 0.05), look * CFrame.new(0, 0, -0.05), hex("F3E3C3"))
	local gui = k.surfaceGui(paper, Enum.NormalId.Front, 40, 1)
	local root = k.guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), hex("F3E3C3"), 1)
	local function text(value: string, y: number, h: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.05, y)
		label.Size = UDim2.fromScale(0.9, h)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = value
		label.ZIndex = 5
		label.Parent = root
	end
	text("WANTED", 0.03, 0.17, hex("8C2A2A"))
	local frame = k.guiFrame(root, UDim2.fromScale(0.18, 0.22), UDim2.fromScale(0.64, 0.46), hex("C9B48A"), 2)
	local head = k.guiFrame(frame, UDim2.fromScale(0.22, 0.12), UDim2.fromScale(0.56, 0.6), hex("E0B48C"), 3)
	k.corner(head, UDim.new(0.5, 0))
	k.guiFrame(head, UDim2.fromScale(0, 0.3), UDim2.fromScale(1, 0.22), mask, 4)
	local body = k.guiFrame(frame, UDim2.fromScale(0.12, 0.72), UDim2.fromScale(0.76, 0.4), mask, 3)
	k.corner(body, UDim.new(0.3, 0))
	text(name, 0.7, 0.12, hex("3A2A1E"))
	text("REWARD $5", 0.84, 0.11, hex("8C2A2A"))
	k.decor("Pin", Vector3.new(0.2, 0.2, 0.2), look * CFrame.new(0, 1.9, -0.12), hex("C8343A"))
end

-- Западная стена: раздевалка — три ряда шкафчиков, банкетки, сумки, вывеска LOCKER ROOM.
local function buildLockerRoom(kit: Kit)
	local k = kit.kit
	local wallX = -HALF_X
	local number = 0
	for _, bankZ in { -20, 0, 20 } do
		for i = 1, 6 do
			number += 1
			local z = bankZ + (i - 3.5) * 2.45
			local position = Vector3.new(wallX + 1.05, 0, z)
			local locker = k.place(Models.Locker, CFrame.lookAt(position, position + Vector3.new(1, 0, 0)), LOCKER_STUB)
			local plate = locker:FindFirstChild("Plate", true)
			if plate and plate:IsA("BasePart") then
				k.textOn(plate, Enum.NormalId.Front, tostring(number), hex("1E2A44"), 1)
			end
		end
		-- Банкетка перед рядом и сумка на ней
		k.place(Models.Bench, CFrame.new(wallX + 6, 0, bankZ) * CFrame.Angles(0, math.rad(90), 0), k.bench)
		local bag = k.decor("DuffelBag", Vector3.new(2.2, 1, 1), CFrame.new(wallX + 6, 2.1, bankZ + 1.3) * CFrame.Angles(0, math.rad(90), 0), hex("1E2A44"), Enum.Material.Fabric)
		bag.Shape = Enum.PartType.Cylinder
		k.decor("DuffelStripe", Vector3.new(0.3, 1.05, 1.05), CFrame.new(wallX + 6, 2.1, bankZ + 1.3) * CFrame.Angles(0, math.rad(90), 0), hex("D4A93A"), Enum.Material.Fabric).Shape = Enum.PartType.Cylinder
	end
	k.sign(Vector3.new(wallX, 10.5, 0), Vector3.new(1, 0, 0), 16, 1.8, "LOCKER ROOM")
	-- Зеркало у раздевалки
	k.decor("MirrorFrame", Vector3.new(0.12, 4.4, 3.2), CFrame.new(wallX + 0.06, 10.5, -30.5), hex("D4A93A"), Enum.Material.Metal)
	local mirror = k.decor("Mirror", Vector3.new(0.1, 4, 2.8), CFrame.new(wallX + 0.12, 10.5, -30.5), hex("CFE3EC"), Enum.Material.Glass)
	mirror.Reflectance = 0.4
end

-- Восточная стена: две доски рекордов (за всё время и за неделю), вывеска HALL OF FAME, кубок.
local function buildHallOfFame(kit: Kit, map: Folder)
	local k = kit.kit
	local colors = k.colors
	local wallX = HALF_X
	local width, height = 16, 11.5
	local y = 8.6
	for _, spec in { { z = -10, name = MapSchema.LeaderboardAllTime }, { z = 10, name = MapSchema.LeaderboardWeekly } } do
		local center = Vector3.new(wallX - 0.2, y, spec.z)
		local look = CFrame.lookAt(center, center + Vector3.new(-1, 0, 0))
		k.decor("BoardFrame", Vector3.new(width + 0.8, height + 0.8, 0.3), look * CFrame.new(0, 0, 0.05), colors.Gold, Enum.Material.Metal)
		local board = kit.part(map, spec.name, Vector3.new(width, height, 0.2), look * CFrame.new(0, 0, -0.15), hex("141B2E"))
		board.CanCollide = false
		board.CastShadow = false
		-- Лампы-подсветки над доской
		for _, dz in { -5, 0, 5 } do
			k.decor("BoardLampArm", Vector3.new(1.2, 0.15, 0.15), CFrame.new(wallX - 0.6, y + height / 2 + 0.9, spec.z + dz), colors.Gold, Enum.Material.Metal)
			k.lamp(Vector3.new(wallX - 1.2, y + height / 2 + 0.8, spec.z + dz), Vector3.new(0.5, 0.3, 0.9), Config.Lighting.LobbyLamp)
		end
	end
	k.sign(Vector3.new(wallX, 17.6, 0), Vector3.new(-1, 0, 0), 26, 2, "HALL OF FAME")
	local trophy = k.place(Models.Trophy, CFrame.lookAt(Vector3.new(wallX - 3, 0, 0), Vector3.new(wallX - 10, 0, 0)), TROPHY_STUB)
	labelOnPart(kit, trophy, "PlaqueFace", "BEST SHIFT\nTROPHY", GOLD, Enum.Font.FredokaOne, 0.3)
	labelOnPart(kit, trophy, "PlinthTag", "#1 GUARD TEAM", NAVY_DARK, Enum.Font.GothamBold, 0.5)
	k.plant(wallX - 2.5, -HALF_Z + 3)
	k.plant(wallX - 2.5, HALF_Z - 3)
end

-- Южная стена: двойная дверь входа, логотип игры, доска HOW TO PLAY, кулер, кофемашина, часы.
local function buildEntrance(kit: Kit)
	local k = kit.kit
	local colors = k.colors
	local wallZ = HALF_Z
	-- Двойная дверь (обманка): золотая рама, две створки с окошками и ручками-штангами
	k.decor("DoorFrame", Vector3.new(9.4, 10.6, 0.4), CFrame.new(0, 5.3, wallZ - 0.15), colors.Gold, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		local x = side * 2.15
		k.decor("DoorLeaf", Vector3.new(4.2, 10, 0.3), CFrame.new(x, 5, wallZ - 0.3), colors.DarkWood, Enum.Material.Wood)
		k.decor("DoorWindow", Vector3.new(2.4, 3.2, 0.32), CFrame.new(x, 7, wallZ - 0.3), colors.Glass, Enum.Material.Glass).Transparency = 0.3
		k.decor("PushBar", Vector3.new(3, 0.25, 0.25), CFrame.new(x, 4, wallZ - 0.6), CHROME, Enum.Material.Metal)
		k.decor("KickPlate", Vector3.new(3.8, 1, 0.34), CFrame.new(x, 0.6, wallZ - 0.32), colors.Gold, Enum.Material.Metal)
	end
	-- Вывеска над дверью и значок
	local logoPoint = Vector3.new(0, 15.9, wallZ)
	k.sign(logoPoint, Vector3.new(0, 0, -1), 26, 3.2, "NIGHT GUARD: MUSEUM")
	local badge = k.decor("LogoBadge", Vector3.new(0.3, 3.4, 3.4), CFrame.new(0, 12.4, wallZ - 0.3) * CFrame.Angles(0, math.rad(90), 0), colors.Gold, Enum.Material.Metal)
	badge.Shape = Enum.PartType.Cylinder
	local star = k.decor("LogoStar", Vector3.new(0.35, 2.2, 2.2), CFrame.new(0, 12.4, wallZ - 0.4) * CFrame.Angles(0, math.rad(90), 0), colors.Navy)
	star.Shape = Enum.PartType.Cylinder
	k.textOn(star, Enum.NormalId.Right, "★", colors.Gold, 0) -- Right — грань диска, которая смотрит в комнату

	-- Доска объявлений HOW TO PLAY слева от двери
	local noticePosition = Vector3.new(-14, 4.2, wallZ - 0.2)
	local notice = k.place(Models.NoticeBoard, CFrame.lookAt(noticePosition, noticePosition + Vector3.new(0, 0, -1)), NOTICE_STUB, false)
	local paper = notice:FindFirstChild("Paper", true)
	if paper and paper:IsA("BasePart") then
		local gui = k.surfaceGui(paper, Enum.NormalId.Front, 60, 1)
		local lines = {
			"HOW TO PLAY",
			"1. Step into a glowing circle to make a team (1–5 guards).",
			"2. Pick your class with keys 1–5.",
			"3. The first guard in the circle leads: START or FRIENDS ONLY.",
			"4. Guard the Mona Lisa night after night!",
		}
		for index, value in lines do
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0.06, if index == 1 then 0.04 else 0.08 + index * 0.17)
			label.Size = UDim2.fromScale(0.88, if index == 1 then 0.2 else 0.16)
			label.Font = if index == 1 then Enum.Font.FredokaOne else Enum.Font.GothamBold
			label.TextScaled = true
			label.TextWrapped = true
			label.TextXAlignment = if index == 1 then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
			label.TextColor3 = if index == 1 then hex("8C2A2A") else hex("1E2A44")
			label.Text = value
			label.Parent = gui
		end
	end
	labelOnPart(kit, notice, "NoteHeader", "SHIFT BOARD", NAVY_DARK, Enum.Font.FredokaOne, 0.8)
	labelOnPart(kit, notice, "NoteYellow", "CHECK\nCAMERAS!", NAVY, Enum.Font.GothamBold, 0.9)
	labelOnPart(kit, notice, "NotePink", "ARREST\n+$5 BONUS", hex("8C2A2A"), Enum.Font.GothamBold, 0.9)
	-- Часы над доской: циферблат и стрелки на 18:00
	local clockCenter = Vector3.new(-14, 11, wallZ - 0.2)
	local face = k.decor("ClockFace", Vector3.new(0.2, 3, 3), CFrame.new(clockCenter) * CFrame.Angles(0, math.rad(90), 0), hex("FFFBF0"))
	face.Shape = Enum.PartType.Cylinder
	local rim = k.decor("ClockRim", Vector3.new(0.15, 3.3, 3.3), CFrame.new(clockCenter + Vector3.new(0, 0, 0.05)) * CFrame.Angles(0, math.rad(90), 0), colors.Gold, Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	k.decor("ClockHour", Vector3.new(0.18, 0.9, 0.06), CFrame.new(clockCenter + Vector3.new(0, -0.4, -0.15)), hex("151821"))
	k.decor("ClockMinute", Vector3.new(0.12, 1.25, 0.06), CFrame.new(clockCenter + Vector3.new(0, 0.6, -0.17)), hex("151821"))

	-- Кулер и кофемашина справа от двери
	local cooler = k.place(Models.WaterCooler, CFrame.lookAt(Vector3.new(11, 0, wallZ - 1.2), Vector3.new(11, 0, wallZ - 5)), COOLER_STUB)
	labelOnPart(kit, cooler, "CoolerBadge", "SPRING WATER", CYAN, Enum.Font.FredokaOne, 0.3)
	local coffee = k.place(Models.CoffeeMachine, CFrame.lookAt(Vector3.new(15.5, 0, wallZ - 1.1), Vector3.new(15.5, 0, wallZ - 5)), COFFEE_STUB)
	labelOnPart(kit, coffee, "CoffeeMenu", "GUARD BREW\nESPRESSO • LATTE\nFREE!", GOLD, Enum.Font.FredokaOne, 0.4)
	-- Коврик у входа (на нём появляются игроки)
	local mat = k.decor("WelcomeMat", Vector3.new(8, 0.06, 4), CFrame.lookAt(SPAWN + Vector3.new(0, -0.47, 0), SPAWN + Vector3.new(0, 0.53, 0), Vector3.new(0, 0, -1)), hex("3A2A1E"), Enum.Material.Fabric)
	mat.CanQuery = false
	k.textOn(mat, Enum.NormalId.Front, "WELCOME, GUARD", colors.Gold, 1)
	k.plant(-6.5, wallZ - 2.5)
	k.plant(6.5, wallZ - 2.5)
	k.plant(-HALF_X + 2.5, wallZ - 3)
end

-- Витрина CLASS SHOP (этап 4, блок 1) у южной стены справа от двери: помост с ковром, тёмная стена-фон
-- с золотой рамой, вывеска CLASS SHOP с двумя алмазами, 5 подставок с подсветкой. Над каждой — табличка
-- (название и цена или OWNED — пишет клиент, у каждого своё). F у подставки открывает окно магазина
-- (ProximityPrompt, его ловит клиент: окно — только картинка, покупку проверяет сервер).
local function buildClassShop(kit: Kit, map: Folder)
	local k = kit.kit
	local colors = k.colors
	local wallZ = HALF_Z
	local left, right = 19.5, 45.5
	local centerX = (left + right) / 2
	local width = right - left
	local front = 27.2 -- передний край помоста
	local depth = wallZ - front
	local folder = Instance.new("Folder")
	folder.Name = MapSchema.ClassShop
	folder.Parent = map

	-- Помост: ступенька 0.4, тёмно-синий ковёр, золотой кант спереди и по бокам
	local dais = kit.part(folder, "Dais", Vector3.new(width, 0.4, depth), CFrame.new(centerX, 0.2, front + depth / 2), hex("1E2A44"), Enum.Material.Fabric)
	dais:SetAttribute("MapObstacle", true)
	k.decor("DaisEdge", Vector3.new(width, 0.42, 0.3), CFrame.new(centerX, 0.21, front + 0.15), colors.Gold, Enum.Material.Metal)
	for _, x in { left + 0.15, right - 0.15 } do
		k.decor("DaisSide", Vector3.new(0.3, 0.42, depth), CFrame.new(x, 0.21, front + depth / 2), colors.Gold, Enum.Material.Metal)
	end

	-- Стена-фон: тёмная панель с золотой рамой и тонкими полосами
	local backZ = wallZ - 0.12
	local backHeight = 9.6
	k.decor("ShopBackFrame", Vector3.new(width + 0.6, backHeight + 0.6, 0.12), CFrame.new(centerX, 0.4 + backHeight / 2, backZ + 0.04), colors.Gold, Enum.Material.Metal)
	k.decor("ShopBack", Vector3.new(width, backHeight, 0.14), CFrame.new(centerX, 0.4 + backHeight / 2, backZ - 0.04), hex("141B2E"))
	for i = 1, 4 do
		local x = left + i * width / 5
		k.decor("ShopBackStripe", Vector3.new(0.12, backHeight - 0.4, 0.16), CFrame.new(x, 0.4 + backHeight / 2, backZ - 0.06), hex("2E4170"), Enum.Material.Metal)
	end

	-- Вывеска CLASS SHOP и строка под ней, по бокам — светящиеся алмазы
	k.sign(Vector3.new(centerX, 12.6, wallZ), Vector3.new(0, 0, -1), 15, 2.6, "CLASS SHOP")
	k.sign(Vector3.new(centerX, 10.7, wallZ), Vector3.new(0, 0, -1), 22, 0.9, "EARN 💎 BY SURVIVING NIGHTS  •  CLASSES ARE YOURS FOREVER", colors.Marble)
	for _, side in { -1, 1 } do
		local point = Vector3.new(centerX + side * 9.3, 12.6, wallZ - 0.3)
		local gem = k.decor("ShopGem", Vector3.new(1.5, 1.5, 0.35), CFrame.new(point) * CFrame.Angles(0, 0, math.rad(45)), Config.Diamonds.Color, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 1.2
		light.Color = Config.Diamonds.Color
		light.Parent = gem
		k.decor("ShopGemRim", Vector3.new(1.8, 1.8, 0.2), CFrame.new(point + Vector3.new(0, 0, 0.12)) * CFrame.Angles(0, 0, math.rad(45)), colors.Gold, Enum.Material.Metal)
	end

	-- Подсветка: рельс вдоль стены-фона и по фонарю над каждой подставкой
	k.decor("TrackRail", Vector3.new(width - 1, 0.25, 0.25), CFrame.new(centerX, 9.7, wallZ - 1.4), hex("2B2F3A"), Enum.Material.Metal)
	for _, x in { left + 1, right - 1 } do
		k.decor("TrackArm", Vector3.new(0.2, 0.2, 1.4), CFrame.new(x, 9.7, wallZ - 0.75), hex("2B2F3A"), Enum.Material.Metal)
	end

	local order = Config.Classes.Order
	local step = width / #order
	for index, role in order do
		local info = (Config.Classes :: any)[role]
		local x = left + (index - 0.5) * step
		local z = front + 4.2
		local standCFrame = CFrame.lookAt(Vector3.new(x, 0.4, z), Vector3.new(x, 0.4, z - 1))
		local stand = k.place(Models.ClassStand, standCFrame, CLASS_STAND_STUB)
		stand.Name = MapSchema.ClassStandPrefix .. role
		stand.Parent = folder
		stand:SetAttribute("Class", role)
		labelOnPart(kit, stand, "PlaqueFace", string.upper(tostring(info.Title)), GOLD, Enum.Font.FredokaOne, 0.25)
		local glow = stand:FindFirstChild("Glow", true)
		if glow and glow:IsA("BasePart") then
			glow.Color = info.Color
			local light = Instance.new("PointLight")
			light.Range = 7
			light.Brightness = 1
			light.Color = info.Color
			light.Parent = glow
		end
		-- Невидимая точка на верху подставки: сюда клиент ставит модель класса, на ней кнопка F
		local top = kit.part(stand, "Top", Vector3.new(1.6, 0.2, 1.6), standCFrame * CFrame.new(0, STAND_TOP + 0.1, 0), colors.Gold)
		top.Transparency = 1
		top.CanCollide = false
		top.CanQuery = false
		top.CanTouch = false
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open shop"
		prompt.ObjectText = tostring(info.Title)
		prompt.KeyboardKeyCode = Config.Keys.Action
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = top

		-- Фонарь на рельсе светит на подставку
		local lampPoint = Vector3.new(x, 9.35, wallZ - 1.4)
		local can = k.decor("ShopSpot", Vector3.new(0.7, 0.9, 0.7), CFrame.lookAt(lampPoint, Vector3.new(x, STAND_TOP + 1, z)), hex("2B2F3A"), Enum.Material.Metal)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 50
		spot.Range = 14
		spot.Brightness = 2.2
		spot.Color = Color3.fromRGB(255, 240, 220)
		spot.Shadows = true
		spot.Parent = can

		-- Табличка над подставкой: золотая рама и тёмная доска (надпись у каждого игрока своя — ставит клиент)
		local labelPoint = Vector3.new(x, 7.7, backZ - 0.2)
		local look = CFrame.lookAt(labelPoint, labelPoint + Vector3.new(0, 0, -1))
		k.decor("ShopLabelFrame", Vector3.new(4.5, 2.1, 0.08), look * CFrame.new(0, 0, 0.04), colors.Gold, Enum.Material.Metal)
		local label = kit.part(stand, "Label", Vector3.new(4.3, 1.9, 0.1), look * CFrame.new(0, 0, -0.03), hex("1E2A44"))
		label.CanCollide = false
		label.CanQuery = false
		label.CanTouch = false
		label.CastShadow = false
	end
end

-- 5 светящихся кругов: диск (по нему сервер считает команду), золотой ободок, заклёпки, номер на полу.
local function buildPads(kit: Kit, map: Folder): { BasePart }
	local k = kit.kit
	local colors = k.colors
	local settings = Config.Hub
	local folder = Instance.new("Folder")
	folder.Name = MapSchema.TeamPads
	folder.Parent = map
	local pads: { BasePart } = {}
	local diameter = settings.PadRadius * 2
	for index = 1, settings.Pads do
		local center = PAD_CENTERS[index] or Vector3.new((index - 3) * 16, 0, 0)
		local rim = k.decor("PadRim", Vector3.new(0.1, diameter + 1.2, diameter + 1.2), CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), colors.Gold, Enum.Material.Metal)
		rim.Shape = Enum.PartType.Cylinder
		rim.CanQuery = false
		local disc = kit.part(folder, MapSchema.TeamPadPrefix .. index, Vector3.new(0.12, diameter, diameter), CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), settings.Color, Enum.Material.Neon)
		disc.Shape = Enum.PartType.Cylinder
		disc.CanCollide = false
		disc.CanTouch = false
		disc.CanQuery = false
		disc.CastShadow = false
		disc.Transparency = 0.1
		disc:SetAttribute(PadAttr.Index, index)
		disc:SetAttribute(PadAttr.Team, "")
		disc:SetAttribute(PadAttr.FriendsOnly, false)
		disc:SetAttribute(PadAttr.EndsAt, 0)
		disc:SetAttribute(PadAttr.State, GameState.PadState.Open)
		disc:SetAttribute(PadAttr.Message, "")
		local glow = Instance.new("PointLight")
		glow.Range = settings.LightRange
		glow.Brightness = settings.LightBrightness
		glow.Color = settings.Color
		glow.Parent = disc
		-- Золотые заклёпки по ободку
		for i = 1, 12 do
			local angle = i / 12 * math.pi * 2
			local stud = k.decor("PadStud", Vector3.new(0.5, 0.18, 0.5), CFrame.new(center + Vector3.new(math.cos(angle) * (settings.PadRadius + 0.3), 0.16, math.sin(angle) * (settings.PadRadius + 0.3))), colors.Gold, Enum.Material.Metal)
			stud.Shape = Enum.PartType.Cylinder
			stud.CFrame = stud.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
		-- Номер круга на полу перед ним (со стороны входа)
		local platePoint = center + Vector3.new(0, 0.04, settings.PadRadius + 2.4)
		local plateCFrame = CFrame.lookAt(platePoint, platePoint + Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
		k.decor("PadPlateFrame", Vector3.new(3.4, 2.4, 0.06), plateCFrame, colors.Gold, Enum.Material.Metal).CanQuery = false
		local plate = k.decor("PadPlate", Vector3.new(3, 2, 0.08), plateCFrame * CFrame.new(0, 0, -0.01), colors.Navy)
		plate.CanQuery = false
		k.textOn(plate, Enum.NormalId.Front, ("TEAM %d"):format(index), colors.Gold, 0)
		table.insert(pads, disc)
	end
	return pads
end

-- Ковёр от входа к кругам и потолочные светильники.
local function buildFloorAndCeiling(kit: Kit)
	local k = kit.kit
	local colors = k.colors
	local runnerStart, runnerEnd = HALF_Z - 0.5, 8
	local length = runnerStart - runnerEnd
	local runner = k.decor("Runner", Vector3.new(8, 0.04, length), CFrame.new(0, 0.02, (runnerStart + runnerEnd) / 2), colors.Navy, Enum.Material.Fabric)
	runner.CanQuery = false
	for _, x in { -4.2, 4.2 } do
		k.decor("RunnerEdge", Vector3.new(0.4, 0.05, length), CFrame.new(x, 0.025, (runnerStart + runnerEnd) / 2), colors.Gold, Enum.Material.Fabric).CanQuery = false
	end
	-- Колонны по углам середины комнаты
	for _, spot in { { -24, -20 }, { 24, -20 }, { -24, 20 }, { 24, 20 } } do
		k.column(spot[1], spot[2], HEIGHT, colors.Marble, Enum.Material.Marble)
	end
	-- Светильники на потолке: рамка и светящийся плафон
	local settings = Config.Hub.CeilingLight
	for _, x in { -36, -12, 12, 36 } do
		for _, z in { -22, 0, 22 } do
			local y = HEIGHT - 0.15
			k.decor("CeilingLightFrame", Vector3.new(5, 0.3, 5), CFrame.new(x, y, z), colors.Gold, Enum.Material.Metal)
			local panel = k.decor("CeilingLight", Vector3.new(4.4, 0.35, 4.4), CFrame.new(x, y - 0.05, z), settings.Color, Enum.Material.Neon)
			local light = Instance.new("PointLight")
			light.Range = settings.Range
			light.Brightness = settings.Brightness
			light.Color = settings.Color
			light.Parent = panel
		end
	end
	-- Бра на длинных стенах
	for _, z in { -28, 28 } do
		k.lamp(Vector3.new(-HALF_X + 0.7, 11, z), Vector3.new(0.3, 0.4, 1.6), Config.Lighting.LobbyLamp)
		k.lamp(Vector3.new(HALF_X - 0.7, 11, z), Vector3.new(0.3, 0.4, 1.6), Config.Lighting.LobbyLamp)
	end
	-- Картины по краям северной и южной стен
	local r = kit.rect(-HALF_X, HALF_X, -HALF_Z, HALF_Z)
	kit.paintingOn(r, "S", -38, 8.5, 6, 4) -- справа на южной стене — витрина CLASS SHOP
end

---------------------------------------------------------------- сборка

-- Строит комнату (или возвращает уже готовую карту) и отдаёт Workspace.Map и круги.
function HubBuilder.build(): (Instance, { BasePart })
	local existing = Workspace:FindFirstChild(MapSchema.Root)
	if existing then
		local pads = {}
		local folder = existing:FindFirstChild(MapSchema.TeamPads)
		for index = 1, Config.Hub.Pads do
			local pad = folder and folder:FindFirstChild(MapSchema.TeamPadPrefix .. index)
			if pad and pad:IsA("BasePart") then
				table.insert(pads, pad)
			end
		end
		return existing, pads
	end

	local map = Instance.new("Folder")
	map.Name = MapSchema.Root
	map.Parent = Workspace
	local kit = MapBuilder.newKit(map)
	local k = kit.kit
	local colors = k.colors

	kit.room({
		name = "Hub",
		rect = kit.rect(-HALF_X, HALF_X, -HALF_Z, HALF_Z),
		height = HEIGHT,
		style = k.styles.Guard,
		floorColor = colors.Wood,
		floorMaterial = Enum.Material.WoodPlanks,
		lampSpacing = 0,
		ceilingColor = hex("2B3550"), -- тёмный потолок: светлый под потолочными лампами пересвечен
	}, "Hub")

	-- Игроки появляются у южной двери лицом к кругам (на север)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = MapSchema.HubSpawn
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(SPAWN)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Parent = map

	buildFloorAndCeiling(kit)
	buildMonitorWall(kit, map)
	buildLockerRoom(kit)
	buildHallOfFame(kit, map)
	buildEntrance(kit)
	buildClassShop(kit, map) -- этап 4, блок 1
	local northWall = -HALF_Z
	wantedPoster(kit, Vector3.new(-40, 9, northWall), Vector3.new(0, 0, 1), "THE BRUTE", hex("3A3F4B"), -4)
	wantedPoster(kit, Vector3.new(-33, 9.4, northWall), Vector3.new(0, 0, 1), "THE SHADOW", hex("1C1C24"), 3)
	wantedPoster(kit, Vector3.new(33, 9.4, northWall), Vector3.new(0, 0, 1), "THE MINER", hex("C27C2C"), -3)
	wantedPoster(kit, Vector3.new(40, 9, northWall), Vector3.new(0, 0, 1), "POWER CUTTER", hex("3B5A8C"), 4)
	local pads = buildPads(kit, map)
	return map, pads
end

return HubBuilder
