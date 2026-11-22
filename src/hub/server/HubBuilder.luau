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
--   | картина   доска HOW TO PLAY   [ дверь ]   кулер, кофе            картина |
--   +--------------------------------- вход ------------------------------------+
--   Игроки появляются у южной двери лицом к кругам.

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

---------------------------------------------------------------- модели-заглушки

-- Шкафчик охраны: стальной корпус, дверца с прорезями, ручка, табличка с номером. Перед — в −Z.
local LOCKER_STUB: { ModelLibrary.StubPart } = {
	{ name = "Body", size = Vector3.new(2.4, 7, 2), offset = CFrame.new(0, 3.65, 0), color = STEEL, material = Enum.Material.Metal },
	{ name = "Base", size = Vector3.new(2.4, 0.3, 1.9), offset = CFrame.new(0, 0.15, 0.05), color = STEEL_DARK, material = Enum.Material.Metal },
	{ name = "Top", size = Vector3.new(2.5, 0.16, 2.1), offset = CFrame.new(0, 7.2, 0), color = STEEL_DARK, material = Enum.Material.Metal },
	{ name = "Door", size = Vector3.new(2.1, 6.5, 0.08), offset = CFrame.new(0, 3.75, -1.04), color = STEEL_LIGHT, material = Enum.Material.Metal },
	{ name = "Vent1", size = Vector3.new(1.4, 0.1, 0.04), offset = CFrame.new(0, 6.3, -1.1), color = STEEL_DARK },
	{ name = "Vent2", size = Vector3.new(1.4, 0.1, 0.04), offset = CFrame.new(0, 6.05, -1.1), color = STEEL_DARK },
	{ name = "Vent3", size = Vector3.new(1.4, 0.1, 0.04), offset = CFrame.new(0, 5.8, -1.1), color = STEEL_DARK },
	{ name = "Vent4", size = Vector3.new(1.4, 0.1, 0.04), offset = CFrame.new(0, 1.5, -1.1), color = STEEL_DARK },
	{ name = "Vent5", size = Vector3.new(1.4, 0.1, 0.04), offset = CFrame.new(0, 1.25, -1.1), color = STEEL_DARK },
	{ name = "Handle", size = Vector3.new(0.14, 0.9, 0.14), offset = CFrame.new(0.7, 3.8, -1.16), color = CHROME, material = Enum.Material.Metal },
	{ name = "Lock", size = Vector3.new(0.22, 0.22, 0.06), offset = CFrame.new(0.7, 4.5, -1.1), color = hex("D4A93A"), material = Enum.Material.Metal, shape = Enum.PartType.Block },
	{ name = "Plate", size = Vector3.new(0.9, 0.42, 0.05), offset = CFrame.new(0, 5.2, -1.1), color = hex("E8DCC4") },
	{ name = "HingeTop", size = Vector3.new(0.1, 0.4, 0.1), offset = CFrame.new(-1.02, 6.2, -1.08), color = CHROME, material = Enum.Material.Metal },
	{ name = "HingeBottom", size = Vector3.new(0.1, 0.4, 0.1), offset = CFrame.new(-1.02, 1.4, -1.08), color = CHROME, material = Enum.Material.Metal },
}

-- Пульт охраны под стеной мониторов: столешница, тумбы, клавиатуры, панели с кнопками. Перед (к сидящему) — в −Z.
local DESK_STUB: { ModelLibrary.StubPart } = {
	{ name = "Top", size = Vector3.new(14, 0.3, 3.2), offset = CFrame.new(0, 3.15, 0), color = hex("3A2A1E"), material = Enum.Material.Wood },
	{ name = "Edge", size = Vector3.new(14.1, 0.18, 0.2), offset = CFrame.new(0, 3.15, -1.6), color = hex("D4A93A"), material = Enum.Material.Metal },
	{ name = "Front", size = Vector3.new(13.6, 2.6, 0.2), offset = CFrame.new(0, 1.7, -1.2), color = hex("1E2A44") },
	{ name = "Stripe", size = Vector3.new(13.6, 0.25, 0.22), offset = CFrame.new(0, 2.5, -1.22), color = hex("3BC6C1"), material = Enum.Material.Neon },
	{ name = "PedestalL", size = Vector3.new(2.4, 3, 3), offset = CFrame.new(-5.6, 1.5, 0), color = hex("2B2F3A"), material = Enum.Material.Metal },
	{ name = "PedestalR", size = Vector3.new(2.4, 3, 3), offset = CFrame.new(5.6, 1.5, 0), color = hex("2B2F3A"), material = Enum.Material.Metal },
	{ name = "Keyboard1", size = Vector3.new(2, 0.12, 0.7), offset = CFrame.new(-4, 3.36, -0.7), color = hex("151821") },
	{ name = "Keyboard2", size = Vector3.new(2, 0.12, 0.7), offset = CFrame.new(0, 3.36, -0.7), color = hex("151821") },
	{ name = "Keyboard3", size = Vector3.new(2, 0.12, 0.7), offset = CFrame.new(4, 3.36, -0.7), color = hex("151821") },
	{ name = "Panel", size = Vector3.new(2.6, 0.2, 0.9), offset = CFrame.new(-6.2, 3.4, -0.6) * CFrame.Angles(math.rad(-12), 0, 0), color = hex("2B2F3A"), material = Enum.Material.Metal },
	{ name = "ButtonRed", size = Vector3.new(0.3, 0.12, 0.3), offset = CFrame.new(-6.9, 3.55, -0.65), color = hex("C8343A"), material = Enum.Material.Neon },
	{ name = "ButtonGreen", size = Vector3.new(0.3, 0.12, 0.3), offset = CFrame.new(-6.3, 3.55, -0.65), color = hex("3FB56B"), material = Enum.Material.Neon },
	{ name = "ButtonYellow", size = Vector3.new(0.3, 0.12, 0.3), offset = CFrame.new(-5.7, 3.55, -0.65), color = hex("FFD23F"), material = Enum.Material.Neon },
	{ name = "Microphone", size = Vector3.new(0.12, 1.2, 0.12), offset = CFrame.new(6.2, 3.9, -0.4) * CFrame.Angles(math.rad(-25), 0, 0), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "Mug", size = Vector3.new(0.5, 0.45, 0.45), offset = CFrame.new(2.1, 3.53, -0.5) * CFrame.Angles(0, 0, math.rad(90)), color = hex("F2EEE6"), shape = Enum.PartType.Cylinder },
	{ name = "Papers", size = Vector3.new(1, 0.06, 1.3), offset = CFrame.new(-2.1, 3.33, -0.3) * CFrame.Angles(0, math.rad(12), 0), color = hex("FFFFFF") },
}

-- Монитор на подставке для пульта: экран светится. Перед (экран) — в −Z.
local MONITOR_STUB: { ModelLibrary.StubPart } = {
	{ name = "Foot", size = Vector3.new(1, 0.1, 0.7), offset = CFrame.new(0, 0.05, 0), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "Neck", size = Vector3.new(0.18, 0.7, 0.18), offset = CFrame.new(0, 0.45, 0.1), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "Frame", size = Vector3.new(2.6, 1.6, 0.16), offset = CFrame.new(0, 1.4, 0), color = hex("151821") },
	{ name = "Screen", size = Vector3.new(2.4, 1.4, 0.04), offset = CFrame.new(0, 1.4, -0.09), color = hex("3BC6C1"), material = Enum.Material.Neon, transparency = 0.15 },
}

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

-- Кулер с бутылью воды и стаканчиками. Перед — в −Z.
local COOLER_STUB: { ModelLibrary.StubPart } = {
	{ name = "Body", size = Vector3.new(1.4, 3, 1.4), offset = CFrame.new(0, 1.5, 0), color = hex("F2EEE6") },
	{ name = "Panel", size = Vector3.new(1, 0.8, 0.05), offset = CFrame.new(0, 2.5, -0.72), color = hex("8A93A6"), material = Enum.Material.Metal },
	{ name = "TapBlue", size = Vector3.new(0.2, 0.25, 0.2), offset = CFrame.new(-0.25, 2.4, -0.82), color = hex("3B7DD8") },
	{ name = "TapRed", size = Vector3.new(0.2, 0.25, 0.2), offset = CFrame.new(0.25, 2.4, -0.82), color = hex("C8343A") },
	{ name = "Bottle", size = Vector3.new(1.6, 1.1, 1.1), offset = CFrame.new(0, 3.85, 0) * CFrame.Angles(0, 0, math.rad(90)), color = hex("7FC8F8"), material = Enum.Material.Glass, transparency = 0.35, shape = Enum.PartType.Cylinder },
	{ name = "Cap", size = Vector3.new(0.3, 0.5, 0.5), offset = CFrame.new(0, 4.75, 0) * CFrame.Angles(0, 0, math.rad(90)), color = hex("3B7DD8"), shape = Enum.PartType.Cylinder },
	{ name = "Cups", size = Vector3.new(0.9, 0.3, 0.3), offset = CFrame.new(0.85, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), color = hex("FFFFFF"), shape = Enum.PartType.Cylinder },
}

-- Кофемашина на тумбе, рядом кружки. Перед — в −Z.
local COFFEE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Cabinet", size = Vector3.new(2.4, 2.8, 1.6), offset = CFrame.new(0, 1.4, 0), color = hex("5A3A22"), material = Enum.Material.Wood },
	{ name = "CabinetTop", size = Vector3.new(2.5, 0.15, 1.7), offset = CFrame.new(0, 2.88, 0), color = hex("E8DCC4"), material = Enum.Material.Marble },
	{ name = "Machine", size = Vector3.new(1.2, 1.4, 1), offset = CFrame.new(-0.4, 3.65, 0.1), color = hex("151821"), material = Enum.Material.Metal },
	{ name = "MachineFront", size = Vector3.new(1, 0.5, 0.05), offset = CFrame.new(-0.4, 3.95, -0.42), color = hex("C8343A") },
	{ name = "Spout", size = Vector3.new(0.15, 0.3, 0.15), offset = CFrame.new(-0.4, 3.3, -0.3), color = hex("D9DEE7"), material = Enum.Material.Metal },
	{ name = "Light", size = Vector3.new(0.12, 0.12, 0.05), offset = CFrame.new(-0.1, 4.2, -0.43), color = hex("3FB56B"), material = Enum.Material.Neon },
	{ name = "MugA", size = Vector3.new(0.4, 0.38, 0.38), offset = CFrame.new(0.6, 3.15, -0.2) * CFrame.Angles(0, 0, math.rad(90)), color = hex("1E2A44"), shape = Enum.PartType.Cylinder },
	{ name = "MugB", size = Vector3.new(0.4, 0.38, 0.38), offset = CFrame.new(0.95, 3.15, 0.25) * CFrame.Angles(0, 0, math.rad(90)), color = hex("D4A93A"), shape = Enum.PartType.Cylinder },
	{ name = "Handle", size = Vector3.new(0.5, 0.08, 0.08), offset = CFrame.new(0, 2.3, -0.82), color = hex("D4A93A"), material = Enum.Material.Metal },
}

-- Пробковая доска объявлений: рамка, пробка, листки (на главном игра пишет HOW TO PLAY). Перед — в −Z.
local NOTICE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Frame", size = Vector3.new(6.2, 4.2, 0.2), offset = CFrame.new(0, 2.1, 0.05), color = hex("5A3A22"), material = Enum.Material.Wood },
	{ name = "Cork", size = Vector3.new(5.8, 3.8, 0.1), offset = CFrame.new(0, 2.1, -0.08), color = hex("B08850"), material = Enum.Material.Sand },
	{ name = "Paper", size = Vector3.new(3.8, 3.3, 0.04), offset = CFrame.new(-0.7, 2.1, -0.15), color = hex("FFFBF0") },
	{ name = "NoteYellow", size = Vector3.new(1.1, 1.1, 0.04), offset = CFrame.new(2.1, 2.9, -0.15) * CFrame.Angles(0, 0, math.rad(6)), color = hex("FFE38A") },
	{ name = "NotePink", size = Vector3.new(1.1, 1, 0.04), offset = CFrame.new(2.2, 1.4, -0.15) * CFrame.Angles(0, 0, math.rad(-5)), color = hex("F7B7C8") },
	{ name = "Pin1", size = Vector3.new(0.18, 0.18, 0.12), offset = CFrame.new(-0.7, 3.65, -0.2), color = hex("C8343A"), shape = Enum.PartType.Ball },
	{ name = "Pin2", size = Vector3.new(0.18, 0.18, 0.12), offset = CFrame.new(2.1, 3.35, -0.2), color = hex("3B7DD8"), shape = Enum.PartType.Ball },
	{ name = "Pin3", size = Vector3.new(0.18, 0.18, 0.12), offset = CFrame.new(2.2, 1.85, -0.2), color = hex("3FB56B"), shape = Enum.PartType.Ball },
}

-- Кубок «лучшая смена» на постаменте у доски рекордов. Перед — в −Z.
local TROPHY_STUB: { ModelLibrary.StubPart } = {
	{ name = "Pedestal", size = Vector3.new(2.4, 3.2, 2.4), offset = CFrame.new(0, 1.6, 0), color = hex("1E2A44") },
	{ name = "PedestalTop", size = Vector3.new(2.7, 0.2, 2.7), offset = CFrame.new(0, 3.3, 0), color = hex("D4A93A"), material = Enum.Material.Metal },
	{ name = "PedestalBase", size = Vector3.new(2.7, 0.3, 2.7), offset = CFrame.new(0, 0.15, 0), color = hex("D4A93A"), material = Enum.Material.Metal },
	{ name = "Plinth", size = Vector3.new(1.2, 0.5, 1.2), offset = CFrame.new(0, 3.65, 0), color = hex("151821") },
	{ name = "Stem", size = Vector3.new(0.9, 0.3, 0.3), offset = CFrame.new(0, 4.35, 0) * CFrame.Angles(0, 0, math.rad(90)), color = hex("D4A93A"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	{ name = "Cup", size = Vector3.new(1.4, 1.5, 1.4), offset = CFrame.new(0, 5.4, 0), color = hex("D4A93A"), material = Enum.Material.Metal, sphere = true },
	{ name = "Rim", size = Vector3.new(0.15, 1.5, 1.5), offset = CFrame.new(0, 6.05, 0) * CFrame.Angles(0, 0, math.rad(90)), color = hex("F2C230"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	{ name = "HandleL", size = Vector3.new(0.5, 0.8, 0.15), offset = CFrame.new(-0.85, 5.5, 0), color = hex("D4A93A"), material = Enum.Material.Metal },
	{ name = "HandleR", size = Vector3.new(0.5, 0.8, 0.15), offset = CFrame.new(0.85, 5.5, 0), color = hex("D4A93A"), material = Enum.Material.Metal },
	{ name = "Star", size = Vector3.new(0.5, 0.5, 0.1), offset = CFrame.new(0, 5.3, -0.72) * CFrame.Angles(0, 0, math.rad(45)), color = hex("FFFFFF"), material = Enum.Material.Neon },
}

---------------------------------------------------------------- части комнаты

type Kit = MapBuilder.RoomKit

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
	for _, x in { -7.2, 7.2 } do
		k.place(Models.Desk, CFrame.new(x, 0, wallZ + 4.4) * CFrame.Angles(0, math.pi, 0), DESK_STUB)
		for _, dx in { -4, 0, 4 } do
			local monitor = k.place(Models.Monitor, CFrame.new(x + dx, 3.3, wallZ + 3.6) * CFrame.Angles(0, math.pi, 0), MONITOR_STUB, false)
			-- Экран монитора светится, как у стены
			local screenPart = monitor:FindFirstChild("Screen", true)
			if screenPart and screenPart:IsA("BasePart") then
				screenPart.CastShadow = false
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
	k.place(Models.Trophy, CFrame.lookAt(Vector3.new(wallX - 3, 0, 0), Vector3.new(wallX - 10, 0, 0)), TROPHY_STUB)
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
	-- Часы над доской: циферблат и стрелки на 18:00
	local clockCenter = Vector3.new(-14, 11, wallZ - 0.2)
	local face = k.decor("ClockFace", Vector3.new(0.2, 3, 3), CFrame.new(clockCenter) * CFrame.Angles(0, math.rad(90), 0), hex("FFFBF0"))
	face.Shape = Enum.PartType.Cylinder
	local rim = k.decor("ClockRim", Vector3.new(0.15, 3.3, 3.3), CFrame.new(clockCenter + Vector3.new(0, 0, 0.05)) * CFrame.Angles(0, math.rad(90), 0), colors.Gold, Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	k.decor("ClockHour", Vector3.new(0.18, 0.9, 0.06), CFrame.new(clockCenter + Vector3.new(0, -0.4, -0.15)), hex("151821"))
	k.decor("ClockMinute", Vector3.new(0.12, 1.25, 0.06), CFrame.new(clockCenter + Vector3.new(0, 0.6, -0.17)), hex("151821"))

	-- Кулер и кофемашина справа от двери
	k.place(Models.WaterCooler, CFrame.lookAt(Vector3.new(11, 0, wallZ - 1.2), Vector3.new(11, 0, wallZ - 5)), COOLER_STUB)
	k.place(Models.CoffeeMachine, CFrame.lookAt(Vector3.new(15.5, 0, wallZ - 1.1), Vector3.new(15.5, 0, wallZ - 5)), COFFEE_STUB)
	-- Коврик у входа (на нём появляются игроки)
	local mat = k.decor("WelcomeMat", Vector3.new(8, 0.06, 4), CFrame.lookAt(SPAWN + Vector3.new(0, -0.47, 0), SPAWN + Vector3.new(0, 0.53, 0), Vector3.new(0, 0, -1)), hex("3A2A1E"), Enum.Material.Fabric)
	mat.CanQuery = false
	k.textOn(mat, Enum.NormalId.Front, "WELCOME, GUARD", colors.Gold, 1)
	k.plant(-6.5, wallZ - 2.5)
	k.plant(6.5, wallZ - 2.5)
	k.plant(-HALF_X + 2.5, wallZ - 3)
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
	kit.paintingOn(r, "S", -38, 8.5, 6, 4)
	kit.paintingOn(r, "S", 38, 8.5, 6, 4)
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
	local northWall = -HALF_Z
	wantedPoster(kit, Vector3.new(-40, 9, northWall), Vector3.new(0, 0, 1), "THE BRUTE", hex("3A3F4B"), -4)
	wantedPoster(kit, Vector3.new(-33, 9.4, northWall), Vector3.new(0, 0, 1), "THE SHADOW", hex("1C1C24"), 3)
	wantedPoster(kit, Vector3.new(33, 9.4, northWall), Vector3.new(0, 0, 1), "THE MINER", hex("C27C2C"), -3)
	wantedPoster(kit, Vector3.new(40, 9, northWall), Vector3.new(0, 0, 1), "POWER CUTTER", hex("3B5A8C"), 4)
	local pads = buildPads(kit, map)
	return map, pads
end

return HubBuilder
