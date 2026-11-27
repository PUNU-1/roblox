--!strict
-- Модели оружия и снаряжения (блок 4), общие для сервера и клиента:
--  • сервер приваривает их к персонажу (в руке, в кобуре, на спине, бронежилет) и ставит в оружейной;
--  • клиент ставит те же модели у камеры — руки и оружие от первого лица.
-- Модель друга из ReplicatedStorage/Models с тем же именем сама заменяет модель Claude.
-- Договорённость: точка привязки оружия — рукоять (где её держит кисть), ствол смотрит в −Z, верх — +Y.
-- Части с именем Mag / Slide / Pump двигаются в анимациях (перезарядка, затвор, помпа),
-- Muzzle — конец ствола (вспышка и трассер), Support — где держит левая рука.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponModels = {}

export type Spec = {
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
	wedge: boolean?,
	sphere: boolean?,
	neon: boolean?,
}

export type Built = {
	model: Model,
	root: BasePart, -- невидимая деталь в точке привязки, к ней приварено всё остальное
	parts: { BasePart },
	offsets: { CFrame }, -- где каждая деталь относительно root
	muzzle: CFrame, -- конец ствола относительно root
	support: CFrame, -- где левая рука относительно root
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local C = {
	Polymer = hex("2E3545"),
	PolymerDark = hex("1B202B"),
	Steel = hex("495366"),
	SteelLight = hex("9AA6BC"),
	Black = hex("14171F"),
	Yellow = hex("FFD036"),
	Wood = hex("A36632"),
	WoodDark = hex("6E411E"),
	Brass = hex("F5BE42"),
	Red = hex("E63946"),
	White = hex("F8F9FC"),
	Turquoise = hex("2CE6D8"),
	Electric = hex("6BF0FF"),
	Navy = hex("243B6B"),
	NavyDark = hex("172647"),
	Gold = hex("F5C542"),
}
WeaponModels.Colors = C

local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (X) вдоль ствола
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вертикально

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Короткие помощники деталей (этап 5, блок F3): блок, цилиндр (length — вдоль своей оси X; повернуть ALONG_Z /
-- ALONG_Y), шар, светящаяся деталь.
local function box(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Spec
	return { name = name, size = size, offset = offset, color = color, material = material }
end

local function cyl(name: string, length: number, thick: number, offset: CFrame, color: Color3, material: Enum.Material?): Spec
	return { name = name, size = Vector3.new(length, thick, thick), offset = offset, color = color, material = material, shape = CYL }
end

local function ball(name: string, d: number, offset: CFrame, color: Color3, material: Enum.Material?): Spec
	return { name = name, size = Vector3.new(d, d, d), offset = offset, color = color, material = material, shape = BALL }
end

local function glow(spec: Spec): Spec
	spec.neon = true
	return spec
end

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Добавить в список count одинаковых деталей: make(i) для i = 0 .. count − 1.
local function addRow(list: { Spec }, count: number, make: (number) -> Spec)
	for i = 0, count - 1 do
		table.insert(list, make(i))
	end
end

---------------------------------------------------------------- оружие

-- Шокер: жёлтый корпус с чёрной планкой и молнией на боках, рукоять с выемками под пальцы, сменный картридж
-- с двумя электродами, экран заряда сзади в рамке (Screen — его цвет меняет Weapons.client), лазер под стволом,
-- красный предохранитель.
local TASER_GRIP = at(0, -0.1, 0.04) * CFrame.Angles(0.22, 0, 0)
local TASER: { Spec } = {
	box("Grip", v3(0.24, 0.56, 0.3), TASER_GRIP, C.PolymerDark, M.Fabric),
	box("GripCap", v3(0.26, 0.07, 0.32), TASER_GRIP * at(0, -0.27, 0), C.Yellow),
	box("Body", v3(0.28, 0.32, 0.78), at(0, 0.3, -0.24), C.Yellow),
	box("Rail", v3(0.29, 0.06, 0.78), at(0, 0.48, -0.24), C.Black),
	box("Stripe", v3(0.29, 0.07, 0.36), at(0, 0.24, -0.06) * CFrame.Angles(-0.4, 0, 0), C.Black),
	box("Safety", v3(0.3, 0.05, 0.07), at(0, 0.42, 0.06), C.Red),
	-- Молния на обоих боках (одна деталь чуть шире корпуса видна с двух сторон)
	glow(box("Bolt", v3(0.3, 0.14, 0.035), at(0, 0.365, -0.4) * CFrame.Angles(0.63, 0, 0), C.Electric)),
	glow(box("Bolt", v3(0.3, 0.035, 0.08), at(0, 0.31, -0.41), C.Electric)),
	glow(box("Bolt", v3(0.3, 0.14, 0.035), at(0, 0.25, -0.42) * CFrame.Angles(0.6, 0, 0), C.Electric)),
	-- Картридж: тёмный, жёлтая полоса, лицевая панель с электродами
	box("Cartridge", v3(0.3, 0.3, 0.24), at(0, 0.3, -0.74), C.Polymer),
	box("CartridgeBand", v3(0.31, 0.07, 0.12), at(0, 0.41, -0.74), C.Yellow),
	box("CartridgeFace", v3(0.26, 0.26, 0.02), at(0, 0.3, -0.865), C.Black),
	glow(cyl("ProngL", 0.08, 0.05, at(-0.07, 0.3, -0.87) * ALONG_Z, C.Electric)),
	glow(cyl("ProngR", 0.08, 0.05, at(0.07, 0.3, -0.87) * ALONG_Z, C.Electric)),
	-- Экран заряда сзади в чёрной рамке
	box("Bezel", v3(0.22, 0.17, 0.016), at(0, 0.33, 0.152), C.Black),
	glow(box("Screen", v3(0.18, 0.13, 0.02), at(0, 0.33, 0.155), C.Turquoise)),
	-- Лазер в корпусе под стволом
	box("LaserBox", v3(0.14, 0.1, 0.16), at(0, 0.16, -0.52), C.Black),
	glow(ball("Laser", 0.07, at(0, 0.16, -0.6), C.Red)),
	-- Спусковая скоба и курок
	box("Guard", v3(0.06, 0.04, 0.32), at(0, 0.04, -0.2), C.Black),
	box("GuardFront", v3(0.06, 0.16, 0.04), at(0, 0.1, -0.36), C.Black),
	box("Trigger", v3(0.04, 0.12, 0.04), at(0, 0.11, -0.18) * CFrame.Angles(0.2, 0, 0), C.Yellow),
}
-- Выемки под пальцы спереди рукояти
addRow(TASER, 3, function(i)
	return cyl("Finger", 0.25, 0.07, TASER_GRIP * at(0, 0.1 - i * 0.13, -0.15), C.Black, M.Rubber)
end)

-- Пистолет: стальной затвор с насечками спереди и сзади, окно выброса с латунным стволом, целик с двумя точками
-- и мушка с точкой (всё на затворе — имя Slide, двигается при выстреле), рамка с планкой, рукоять с насечкой,
-- курок, курковый молоток, магазин с патроном сверху (виден, когда выпадает).
local PISTOL_GRIP = at(0, -0.1, 0.05) * CFrame.Angles(0.22, 0, 0)
local PISTOL_MAG = at(0, -0.18, 0.08) * CFrame.Angles(0.22, 0, 0)
local PISTOL: { Spec } = {
	box("Grip", v3(0.22, 0.56, 0.3), PISTOL_GRIP, C.Polymer),
	box("GripPanel", v3(0.24, 0.38, 0.22), at(0, -0.12, 0.06) * CFrame.Angles(0.22, 0, 0), C.PolymerDark, M.Fabric),
	box("Beavertail", v3(0.2, 0.06, 0.16), at(0, 0.27, 0.2), C.Polymer),
	box("Mag", v3(0.18, 0.5, 0.24), PISTOL_MAG, C.Black),
	box("Mag", v3(0.23, 0.06, 0.3), at(0, -0.43, 0.14) * CFrame.Angles(0.22, 0, 0), C.Polymer),
	cyl("Mag", 0.14, 0.07, PISTOL_MAG * at(0, 0.26, -0.02) * ALONG_Z, C.Brass, M.Metal),
	box("MagRelease", v3(0.235, 0.05, 0.06), at(0, 0.17, -0.03), C.Black),
	box("Frame", v3(0.2, 0.16, 0.84), at(0, 0.2, -0.27), C.Polymer),
	box("Rail", v3(0.16, 0.05, 0.28), at(0, 0.1, -0.56), C.Black),
	box("Guard", v3(0.06, 0.04, 0.3), at(0, 0.05, -0.2), C.Polymer),
	box("GuardFront", v3(0.06, 0.14, 0.04), at(0, 0.11, -0.35), C.Polymer),
	box("Trigger", v3(0.04, 0.11, 0.04), at(0, 0.12, -0.17) * CFrame.Angles(0.2, 0, 0), C.Black),
	box("SlideStop", v3(0.24, 0.04, 0.12), at(0, 0.285, -0.06), C.Black),
	box("Hammer", v3(0.06, 0.12, 0.07), at(0, 0.38, 0.24) * CFrame.Angles(-0.4, 0, 0), C.Black),
	box("Accent", v3(0.235, 0.025, 0.55), at(0, 0.29, -0.42), C.Gold, M.Metal),
	cyl("Barrel", 0.1, 0.12, at(0, 0.37, -0.82) * ALONG_Z, C.Black),
	-- Затвор и всё, что на нём
	box("Slide", v3(0.23, 0.2, 1.0), at(0, 0.37, -0.3), C.Steel, M.Metal),
	box("Slide", v3(0.02, 0.09, 0.24), at(0.116, 0.4, -0.3), C.Brass, M.Metal), -- окно выброса: виден ствол
	box("Slide", v3(0.05, 0.06, 0.05), at(-0.045, 0.5, 0.13), C.Black), -- целик из двух половинок
	box("Slide", v3(0.05, 0.06, 0.05), at(0.045, 0.5, 0.13), C.Black),
	glow(box("Slide", v3(0.02, 0.02, 0.01), at(-0.045, 0.51, 0.157), C.White)),
	glow(box("Slide", v3(0.02, 0.02, 0.01), at(0.045, 0.51, 0.157), C.White)),
	box("Slide", v3(0.035, 0.06, 0.05), at(0, 0.5, -0.74), C.Black), -- мушка
	glow(box("Slide", v3(0.02, 0.02, 0.01), at(0, 0.51, -0.712), C.White)),
}
-- Насечка на затворе: 4 полосы сзади, 2 спереди
addRow(PISTOL, 4, function(i)
	return box("Slide", v3(0.24, 0.15, 0.025), at(0, 0.37, 0.15 - i * 0.06), C.Black)
end)
addRow(PISTOL, 2, function(i)
	return box("Slide", v3(0.24, 0.15, 0.025), at(0, 0.37, -0.6 - i * 0.06), C.Black)
end)
-- Насечка на рукояти
addRow(PISTOL, 4, function(i)
	return box("GripRidge", v3(0.25, 0.03, 0.2), PISTOL_GRIP * at(0, -0.2 + i * 0.08, 0.01), C.Black)
end)

-- Помповый дробовик: деревянные приклад с насечкой и белой прокладкой, стальная ствольная коробка с золотой
-- гравировкой, ствол с прицельной планкой и латунной мушкой, трубка магазина с хомутом, деревянная помпа
-- с бороздками и тягами (всё Pump — двигается), патронташ на левом боку на 3 красных патрона.
local SHOTGUN_GRIP = at(0, -0.06, 0.08) * CFrame.Angles(0.35, 0, 0)
local SHOTGUN_STOCK = at(0, 0.1, 0.82) * CFrame.Angles(-0.08, 0, 0)
local SHOTGUN: { Spec } = {
	box("Grip", v3(0.22, 0.48, 0.34), SHOTGUN_GRIP, C.Wood, M.Wood),
	box("Stock", v3(0.25, 0.4, 1.1), SHOTGUN_STOCK, C.Wood, M.Wood),
	box("StockInlay", v3(0.26, 0.06, 0.6), SHOTGUN_STOCK * at(0, 0.06, -0.05), C.WoodDark, M.Wood),
	box("Spacer", v3(0.28, 0.53, 0.02), at(0, 0.06, 1.39) * CFrame.Angles(-0.08, 0, 0) * at(0, 0, -0.035), C.White), -- белая кайма у затыльника
	box("Butt", v3(0.27, 0.52, 0.09), at(0, 0.06, 1.39) * CFrame.Angles(-0.08, 0, 0), C.Black, M.Rubber),
	box("Swivel", v3(0.04, 0.1, 0.1), SHOTGUN_STOCK * at(0, -0.24, 0.3), C.SteelLight, M.Metal),
	box("Receiver", v3(0.3, 0.38, 0.9), at(0, 0.32, -0.34), C.Steel, M.Metal),
	box("Engraving", v3(0.31, 0.03, 0.6), at(0, 0.24, -0.34), C.Gold, M.Metal),
	box("Engraving", v3(0.31, 0.03, 0.3), at(0, 0.2, -0.49), C.Gold, M.Metal),
	box("Port", v3(0.02, 0.14, 0.34), at(0.155, 0.36, -0.3), C.Black),
	box("LoadPort", v3(0.2, 0.02, 0.4), at(0, 0.125, -0.45), C.Black),
	cyl("Safety", 0.06, 0.08, at(0, 0.52, 0.05) * ALONG_Y, C.Red),
	cyl("Barrel", 2.2, 0.16, at(0, 0.43, -1.9) * ALONG_Z, C.SteelLight, M.Metal),
	box("Rib", v3(0.06, 0.04, 2.1), at(0, 0.53, -1.95), C.Black),
	cyl("MuzzleRing", 0.06, 0.18, at(0, 0.43, -2.97) * ALONG_Z, C.Steel, M.Metal),
	ball("Bead", 0.07, at(0, 0.57, -2.95), C.Brass, M.Metal),
	cyl("Tube", 1.7, 0.14, at(0, 0.24, -1.62) * ALONG_Z, C.Steel, M.Metal),
	box("Clamp", v3(0.1, 0.32, 0.1), at(0, 0.335, -2.38), C.Steel, M.Metal),
	cyl("Cap", 0.08, 0.17, at(0, 0.24, -2.49) * ALONG_Z, C.Black),
	-- Помпа с бороздками и стальными тягами к ствольной коробке
	box("Pump", v3(0.3, 0.26, 0.8), at(0, 0.24, -1.42), C.Wood, M.Wood),
	box("Pump", v3(0.31, 0.27, 0.04), at(0, 0.24, -1.2), C.WoodDark, M.Wood),
	box("Pump", v3(0.31, 0.27, 0.04), at(0, 0.24, -1.42), C.WoodDark, M.Wood),
	box("Pump", v3(0.31, 0.27, 0.04), at(0, 0.24, -1.64), C.WoodDark, M.Wood),
	box("Pump", v3(0.03, 0.03, 0.4), at(-0.12, 0.3, -0.9), C.SteelLight, M.Metal),
	box("Pump", v3(0.03, 0.03, 0.4), at(0.12, 0.3, -0.9), C.SteelLight, M.Metal),
	box("Guard", v3(0.06, 0.04, 0.32), at(0, 0.07, -0.18), C.Steel),
	box("Trigger", v3(0.04, 0.12, 0.04), at(0, 0.14, -0.16) * CFrame.Angles(0.2, 0, 0), C.Black),
	-- Патронташ на левом боку (его видно от первого лица)
	box("Saddle", v3(0.03, 0.34, 0.5), at(-0.165, 0.34, -0.28), C.Black),
}
addRow(SHOTGUN, 3, function(i)
	return cyl("Shell", 0.3, 0.12, at(-0.22, 0.36, -0.12 - i * 0.16) * ALONG_Y, C.Red)
end)
addRow(SHOTGUN, 3, function(i)
	return cyl("ShellBase", 0.08, 0.125, at(-0.22, 0.22, -0.12 - i * 0.16) * ALONG_Y, C.Brass, M.Metal)
end)
-- Насечка на шейке приклада
addRow(SHOTGUN, 3, function(i)
	return box("GripRidge", v3(0.23, 0.03, 0.3), SHOTGUN_GRIP * at(0, -0.12 + i * 0.09, 0), C.WoodDark, M.Wood)
end)

-- Автомат: верхняя стальная и нижняя тёмная ствольные коробки, окно выброса, переводчик огня, цевьё с прорезями
-- и планками, верхняя планка с зубцами, мушка в «ушах», ствол с дульным тормозом, коллиматор-трубка
-- с красной точкой сзади, изогнутый магазин с рёбрами и патроном сверху (Mag), рукоять затвора с «крыльями»
-- (Slide — двигается при перезарядке), приклад на буферной трубке с щекой и антабкой.
local RIFLE_GRIP = at(0, -0.06, 0.05) * CFrame.Angles(0.3, 0, 0)
local RIFLE_MAG = at(0, -0.02, -0.62) * CFrame.Angles(-0.12, 0, 0)
local RIFLE: { Spec } = {
	box("Grip", v3(0.22, 0.5, 0.28), RIFLE_GRIP, C.Polymer),
	box("Upper", v3(0.28, 0.18, 1.2), at(0, 0.41, -0.36), C.Steel, M.Metal),
	box("Lower", v3(0.26, 0.2, 0.9), at(0, 0.22, -0.42), C.PolymerDark),
	box("Magwell", v3(0.3, 0.12, 0.36), at(0, 0.12, -0.62), C.Polymer),
	box("Port", v3(0.02, 0.1, 0.28), at(0.145, 0.4, -0.3), C.Black),
	box("Deflector", v3(0.06, 0.1, 0.08), at(0.16, 0.41, -0.1), C.Steel, M.Metal),
	box("BoltRelease", v3(0.04, 0.1, 0.14), at(-0.14, 0.25, -0.75), C.Black),
	glow(box("Selector", v3(0.02, 0.06, 0.06), at(-0.14, 0.25, -0.05), C.Red)),
	box("Handguard", v3(0.34, 0.32, 1.0), at(0, 0.33, -1.42), C.Polymer),
	box("RailL", v3(0.02, 0.05, 0.9), at(-0.175, 0.37, -1.42), C.Black),
	box("RailR", v3(0.02, 0.05, 0.9), at(0.175, 0.37, -1.42), C.Black),
	box("RailBottom", v3(0.14, 0.04, 0.7), at(0, 0.155, -1.45), C.Black),
	box("RailTop", v3(0.16, 0.04, 1.9), at(0, 0.51, -0.95), C.Black),
	box("Accent", v3(0.345, 0.04, 0.5), at(0, 0.2, -1.42), C.Gold, M.Metal),
	cyl("Barrel", 0.7, 0.14, at(0, 0.36, -2.25) * ALONG_Z, C.Black, M.Metal),
	cyl("Brake", 0.22, 0.2, at(0, 0.36, -2.66) * ALONG_Z, C.Steel, M.Metal),
	cyl("BrakeRing", 0.03, 0.21, at(0, 0.36, -2.61) * ALONG_Z, C.Black),
	cyl("BrakeRing", 0.03, 0.21, at(0, 0.36, -2.71) * ALONG_Z, C.Black),
	-- Мушка: основание, два «уха» и столбик со светящейся точкой
	box("SightBase", v3(0.16, 0.12, 0.12), at(0, 0.58, -1.8), C.Black),
	box("SightEar", v3(0.04, 0.18, 0.08), at(-0.08, 0.7, -1.8), C.Black),
	box("SightEar", v3(0.04, 0.18, 0.08), at(0.08, 0.7, -1.8), C.Black),
	box("SightPost", v3(0.03, 0.14, 0.04), at(0, 0.67, -1.8), C.Black),
	glow(box("SightTip", v3(0.03, 0.03, 0.01), at(0, 0.73, -1.778), C.Turquoise)),
	-- Коллиматор: трубка с козырьком, барабанчик сбоку, сзади стекло с красной точкой
	box("OpticMount", v3(0.18, 0.1, 0.3), at(0, 0.53, -0.42), C.Black),
	cyl("Optic", 0.5, 0.26, at(0, 0.7, -0.42) * ALONG_Z, C.PolymerDark),
	cyl("OpticHood", 0.08, 0.3, at(0, 0.7, -0.65) * ALONG_Z, C.Black),
	cyl("OpticRing", 0.06, 0.29, at(0, 0.7, -0.2) * ALONG_Z, C.Black),
	cyl("OpticKnob", 0.06, 0.1, at(0.15, 0.7, -0.42), C.Black),
	{ name = "Lens", size = v3(0.02, 0.2, 0.2), offset = at(0, 0.7, -0.692) * ALONG_Z, color = hex("FF7A7A"), material = M.Glass, transparency = 0.35, shape = CYL },
	{ name = "LensBack", size = v3(0.02, 0.22, 0.22), offset = at(0, 0.7, -0.162) * ALONG_Z, color = hex("8FD8FF"), material = M.Glass, transparency = 0.25, shape = CYL },
	glow(box("Dot", v3(0.03, 0.03, 0.01), at(0, 0.7, -0.148), C.Red)),
	-- Магазин: изогнутый, рёбра, патрон сверху (прячется в шахте)
	box("Mag", v3(0.2, 0.46, 0.3), RIFLE_MAG, C.Black),
	box("Mag", v3(0.2, 0.36, 0.3), at(0, -0.36, -0.7) * CFrame.Angles(-0.3, 0, 0), C.Black),
	box("Mag", v3(0.22, 0.05, 0.32), at(0, -0.55, -0.76) * CFrame.Angles(-0.3, 0, 0), C.Polymer),
	box("Mag", v3(0.21, 0.035, 0.31), RIFLE_MAG * at(0, -0.06, 0), C.Polymer),
	box("Mag", v3(0.21, 0.035, 0.31), RIFLE_MAG * at(0, -0.16, 0), C.Polymer),
	cyl("Mag", 0.22, 0.09, RIFLE_MAG * at(0, 0.25, 0) * ALONG_Z, C.Brass, M.Metal),
	-- Рукоять затвора с «крыльями»
	box("Slide", v3(0.08, 0.05, 0.2), at(0, 0.53, 0.14), C.Black),
	box("Slide", v3(0.28, 0.06, 0.07), at(0, 0.53, 0.24), C.Black),
	-- Приклад на буферной трубке
	cyl("Buffer", 0.45, 0.16, at(0, 0.38, 0.45) * ALONG_Z, C.Steel, M.Metal),
	box("Stock", v3(0.22, 0.3, 0.5), at(0, 0.28, 0.83), C.Polymer),
	box("Cheek", v3(0.18, 0.08, 0.4), at(0, 0.46, 0.85), C.PolymerDark),
	box("StockPad", v3(0.25, 0.4, 0.1), at(0, 0.27, 1.13), C.Black, M.Rubber),
	box("SlingLoop", v3(0.04, 0.1, 0.1), at(0, 0.09, 0.95), C.SteelLight, M.Metal),
	box("Guard", v3(0.06, 0.04, 0.32), at(0, 0.07, -0.18), C.Polymer),
	box("Trigger", v3(0.04, 0.12, 0.04), at(0, 0.14, -0.16) * CFrame.Angles(0.2, 0, 0), C.Black),
}
-- Прорези в цевье (насквозь — видны с обеих сторон) и зубцы верхней планки
addRow(RIFLE, 3, function(i)
	return box("Vent", v3(0.35, 0.06, 0.16), at(0, 0.27, -1.1 - i * 0.32), C.Black)
end)
addRow(RIFLE, 6, function(i)
	return box("RailTooth", v3(0.17, 0.03, 0.05), at(0, 0.545, -0.75 - i * 0.16), C.Black)
end)
-- Насечка на рукояти
addRow(RIFLE, 4, function(i)
	return box("GripRidge", v3(0.23, 0.03, 0.24), RIFLE_GRIP * at(0, -0.18 + i * 0.08, 0.01), C.Black)
end)

-- Аптечка: белый чемоданчик с красными крестами, ручка сверху (точка привязки — ручка).
local MEDKIT: { Spec } = {
	{ name = "Case", size = Vector3.new(1.2, 0.8, 0.45), offset = at(0, -0.55, 0), color = C.White },
	{ name = "Rim", size = Vector3.new(1.24, 0.06, 0.49), offset = at(0, -0.36, 0), color = hex("C9CED6") },
	{ name = "CrossH", size = Vector3.new(0.46, 0.14, 0.47), offset = at(0, -0.58, 0), color = C.Red },
	{ name = "CrossV", size = Vector3.new(0.14, 0.46, 0.47), offset = at(0, -0.58, 0), color = C.Red },
	{ name = "Handle", size = Vector3.new(0.5, 0.08, 0.1), offset = at(0, 0, 0), color = C.Polymer },
	{ name = "PostL", size = Vector3.new(0.08, 0.16, 0.1), offset = at(-0.21, -0.08, 0), color = C.Polymer },
	{ name = "PostR", size = Vector3.new(0.08, 0.16, 0.1), offset = at(0.21, -0.08, 0), color = C.Polymer },
	{ name = "LatchL", size = Vector3.new(0.1, 0.08, 0.04), offset = at(-0.4, -0.33, -0.24), color = C.Gold, material = M.Metal },
	{ name = "LatchR", size = Vector3.new(0.1, 0.08, 0.04), offset = at(0.4, -0.33, -0.24), color = C.Gold, material = M.Metal },
}

-- Дубинка грабителя: резиновая с ручкой-темляком (точка привязки — рукоять, бьющий конец в −Z).
local BATON: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.5, 0.18, 0.18), offset = at(0, 0, 0) * ALONG_Z, color = C.Black, material = M.Rubber, shape = CYL },
	{ name = "Rod", size = Vector3.new(1.7, 0.14, 0.14), offset = at(0, 0, -1.05) * ALONG_Z, color = C.PolymerDark, material = M.Rubber, shape = CYL },
	{ name = "Tip", size = Vector3.new(0.16, 0.16, 0.16), offset = at(0, 0, -1.9), color = C.PolymerDark, material = M.Rubber, shape = BALL },
	{ name = "Side", size = Vector3.new(0.4, 0.1, 0.1), offset = at(0, 0, -0.35) * CFrame.Angles(0, 0, math.pi / 2), color = C.Black, material = M.Rubber, shape = CYL },
	{ name = "Pommel", size = Vector3.new(0.08, 0.22, 0.22), offset = at(0, 0, 0.27) * ALONG_Z, color = C.Steel, material = M.Metal, shape = CYL },
}

-- Дымовая шашка: зелёно-серая банка с кольцом и рычагом.
local SMOKE: { Spec } = {
	{ name = "Can", size = Vector3.new(0.62, 0.36, 0.36), offset = at(0, 0, 0) * ALONG_Y, color = hex("5A6B4A"), shape = CYL },
	{ name = "Band", size = Vector3.new(0.12, 0.37, 0.37), offset = at(0, 0.12, 0) * ALONG_Y, color = C.Yellow, shape = CYL },
	{ name = "Top", size = Vector3.new(0.08, 0.26, 0.26), offset = at(0, 0.34, 0) * ALONG_Y, color = C.SteelLight, material = M.Metal, shape = CYL },
	{ name = "Lever", size = Vector3.new(0.06, 0.4, 0.08), offset = at(0.15, 0.18, 0), color = C.SteelLight, material = M.Metal },
	{ name = "Ring", size = Vector3.new(0.03, 0.16, 0.16), offset = at(-0.12, 0.42, 0), color = C.SteelLight, material = M.Metal, shape = CYL },
}

type Info = { specs: { Spec }, muzzle: CFrame, support: CFrame }

WeaponModels.Names = {
	Taser = "weapon_taser_01",
	Pistol = "weapon_pistol_01",
	Shotgun = "weapon_shotgun_01",
	Rifle = "weapon_rifle_01",
	Medkit = "prop_medkit_01",
	Baton = "robber_baton_01",
	Smoke = "prop_smoke_grenade_01",
}

local INFO: { [string]: Info } = {
	Taser = { specs = TASER, muzzle = at(0, 0.3, -0.9), support = at(-0.12, -0.12, 0.08) },
	Pistol = { specs = PISTOL, muzzle = at(0, 0.37, -0.9), support = at(-0.12, -0.12, 0.08) },
	Shotgun = { specs = SHOTGUN, muzzle = at(0, 0.43, -3.02), support = at(0, 0.08, -1.42) },
	Rifle = { specs = RIFLE, muzzle = at(0, 0.36, -2.78), support = at(0, 0.14, -1.45) },
	Medkit = { specs = MEDKIT, muzzle = at(0, -0.55, -0.3), support = at(-0.55, -0.55, 0) },
	Baton = { specs = BATON, muzzle = at(0, 0, -1.9), support = at(0, 0, 0) },
	Smoke = { specs = SMOKE, muzzle = at(0, 0.4, 0), support = at(0, 0, 0) },
}

---------------------------------------------------------------- сборка

local function newPart(spec: Spec, index: number): BasePart
	local part: BasePart
	if spec.wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if spec.shape then
			block.Shape = spec.shape
		end
		part = block
	end
	part.Name = spec.name or ("Part" .. index)
	part.Size = spec.size
	part.CFrame = spec.offset
	part.Color = spec.color
	local mat = if spec.neon then Enum.Material.Neon else (spec.material or Enum.Material.SmoothPlastic)
	part.Material = mat
	if mat == Enum.Material.Metal then
		part.Reflectance = 0.25
	elseif mat == Enum.Material.Glass then
		part.Reflectance = 0.22
	elseif mat == Enum.Material.SmoothPlastic then
		part.Reflectance = 0.05
	end
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	return part
end

local function quiet(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Модель по своим деталям (specs) с невидимым корнем в точке привязки. Модель друга с тем же именем — вместо неё.
function WeaponModels.fromSpecs(name: string, specs: { Spec }, muzzle: CFrame?, support: CFrame?): Built
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.CFrame = CFrame.identity
	quiet(root)
	root.Parent = model
	model.PrimaryPart = root
	local parts, offsets = {}, {}
	local muzzleOffset = muzzle or CFrame.identity
	local supportOffset = support or CFrame.identity
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		local copy = template:Clone()
		local pivot = copy:GetPivot()
		for _, descendant in copy:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then
				descendant:Destroy() -- скриптов в моделях быть не должно
			elseif descendant:IsA("BasePart") then
				table.insert(parts, descendant)
				table.insert(offsets, pivot:ToObjectSpace(descendant.CFrame))
			elseif descendant:IsA("Attachment") and descendant.Name == "Muzzle" then
				muzzleOffset = pivot:ToObjectSpace(descendant.WorldCFrame)
			elseif descendant:IsA("Attachment") and descendant.Name == "Support" then
				supportOffset = pivot:ToObjectSpace(descendant.WorldCFrame)
			end
		end
		for index, part in parts do
			part.CFrame = offsets[index]
			part.Parent = model
		end
		copy:Destroy()
	else
		for index, spec in specs do
			local part = newPart(spec, index)
			table.insert(parts, part)
			table.insert(offsets, spec.offset)
			part.Parent = model
		end
	end
	for _, part in parts do
		quiet(part)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Muzzle"
	attachment.CFrame = muzzleOffset
	attachment.Parent = root
	model.WorldPivot = CFrame.identity
	return { model = model, root = root, parts = parts, offsets = offsets, muzzle = muzzleOffset, support = supportOffset }
end

-- Оружие или снаряжение по короткому имени: Taser, Pistol, Shotgun, Rifle, Medkit, Baton, Smoke.
function WeaponModels.build(kind: string): Built
	local info = INFO[kind] or INFO.Pistol
	return WeaponModels.fromSpecs(WeaponModels.Names[kind] or kind, info.specs, info.muzzle, info.support)
end

-- Приварить собранную модель к детали персонажа: модель встаёт в cframe (в мире) и двигается вместе с частью тела.
-- Weld с явным C0: так модель держится там, где её поставили, как бы ни двигалась часть тела.
function WeaponModels.weld(built: Built, toPart: BasePart, cframe: CFrame)
	for index, part in built.parts do
		part.CFrame = cframe * built.offsets[index]
		local weld = Instance.new("Weld")
		weld.Name = "GearWeld"
		weld.Part0 = built.root
		weld.Part1 = part
		weld.C0 = built.offsets[index]
		weld.Parent = part
	end
	built.root.CFrame = cframe
	local weld = Instance.new("Weld")
	weld.Name = "GearWeld"
	weld.Part0 = toPart
	weld.Part1 = built.root
	weld.C0 = toPart.CFrame:ToObjectSpace(cframe)
	weld.Parent = built.root
end

-- Закрепить модель в мире (оружейная): всё закреплено, стоит в cframe.
function WeaponModels.anchor(built: Built, cframe: CFrame)
	built.root.Anchored = true
	built.root.CFrame = cframe
	for index, part in built.parts do
		part.Anchored = true
		part.CFrame = cframe * built.offsets[index]
	end
end

---------------------------------------------------------------- бронежилет охраны

-- Детали бронежилета для верхней части туловища размером t (точка привязки — центр туловища).
-- Тёмные пластины спереди и сзади, плечевые лямки, боковые ремни, подсумки, рация и значок.
function WeaponModels.vestSpecs(t: Vector3): { Spec }
	local front = -t.Z * 0.5 - 0.1
	local back = t.Z * 0.5 + 0.1
	local plate = C.NavyDark
	local strap = hex("0E1322")
	return {
		{ name = "FrontPlate", size = Vector3.new(t.X * 0.86, t.Y * 0.84, 0.2), offset = at(0, -t.Y * 0.04, front), color = plate, material = M.Fabric },
		{ name = "BackPlate", size = Vector3.new(t.X * 0.88, t.Y * 0.86, 0.2), offset = at(0, -t.Y * 0.03, back), color = plate, material = M.Fabric },
		{ name = "StrapL", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.24), offset = at(-t.X * 0.27, t.Y * 0.47, 0), color = strap, material = M.Fabric },
		{ name = "StrapR", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.24), offset = at(t.X * 0.27, t.Y * 0.47, 0), color = strap, material = M.Fabric },
		{ name = "SideL", size = Vector3.new(0.12, t.Y * 0.42, t.Z * 1.2), offset = at(-t.X * 0.5 - 0.04, -t.Y * 0.18, 0), color = strap, material = M.Fabric },
		{ name = "SideR", size = Vector3.new(0.12, t.Y * 0.42, t.Z * 1.2), offset = at(t.X * 0.5 + 0.04, -t.Y * 0.18, 0), color = strap, material = M.Fabric },
		{ name = "PouchL", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(-t.X * 0.27, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "PouchM", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(0, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "PouchR", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(t.X * 0.27, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "Radio", size = Vector3.new(0.22, 0.34, 0.14), offset = at(t.X * 0.26, t.Y * 0.16, front - 0.16), color = C.Black },
		{ name = "Antenna", size = Vector3.new(0.04, 0.36, 0.04), offset = at(t.X * 0.31, t.Y * 0.4, front - 0.16), color = C.Black },
		{ name = "Badge", size = Vector3.new(0.34, 0.34, 0.05), offset = at(-t.X * 0.25, t.Y * 0.16, front - 0.12), color = C.Gold, material = M.Metal },
		{ name = "Stripe", size = Vector3.new(t.X * 0.88, 0.07, 0.21), offset = at(0, t.Y * 0.02, back + 0.005), color = hex("F2C230") },
	}
end

-- Надпись SECURITY на спине бронежилета (у детали BackPlate).
function WeaponModels.labelVest(model: Instance)
	local back = model:FindFirstChild("BackPlate", true)
	if not (back and back:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.32)
	label.Position = UDim2.fromScale(0, 0.12)
	label.Text = "SECURITY"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = hex("F2C230")
	label.Parent = gui
	gui.Parent = back
end

return WeaponModels
