-- Украшения залов за деньги: свет, растения, картины и большие украшения каждого зала —
-- скелеты динозавров, пальмы и раскоп; звёздный потолок, планеты, ракета и космонавт; витрины и
-- дверь хранилища; фонтан и статуи. Всё строится кодом из деталей (модели-заглушки ModelLibrary:
-- если друг положит модель с тем же именем, она сама заменит заглушку).
-- Помощники (стены, колонны, люстры, картины) живут в MapBuilder и приходят сюда набором Kit.
-- Каждый зал описан в координатах зала Скульптур (k = 0): x от −96 до −8, z от 48 до 106,
-- дверь — в восточной стене (x = −8) у северного края (z от 52 до 60). Остальные залы повёрнуты (T).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))

local hex = Color3.fromHex
local Models = MapSchema.Models

export type Kit = {
	colors: { [string]: Color3 },
	styles: { [string]: any },
	dayLight: string,
	hallHeight: number,
	solid: (name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	decor: (name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	column: (x: number, z: number, height: number, color: Color3, material: Enum.Material) -> (),
	plant: (x: number, z: number) -> (),
	chandelier: (x: number, z: number, ceilingY: number, drop: number?) -> (),
	painting: (wallPoint: Vector3, facing: Vector3, width: number, height: number) -> (),
	textOn: (part: BasePart, face: Enum.NormalId, text: string, color: Color3, lightInfluence: number) -> TextLabel,
	surfaceGui: (part: BasePart, face: Enum.NormalId, pixelsPerStud: number, lightInfluence: number) -> SurfaceGui,
	guiFrame: (parent: Instance, position: UDim2, size: UDim2, color: Color3, zIndex: number) -> Frame,
	corner: (parent: Instance, radius: UDim) -> (),
	lamp: (position: Vector3, size: Vector3, settings: { Range: number, Brightness: number, Color: Color3 }) -> Part,
	place: (name: string, cframe: CFrame, stub: { ModelLibrary.StubPart }, collide: boolean?) -> PVInstance,
	sign: (point: Vector3, facing: Vector3, width: number, height: number, text: string, color: Color3?, background: Color3?) -> Part,
	displayCase: { ModelLibrary.StubPart },
	bench: { ModelLibrary.StubPart },
}

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
type Stub = { ModelLibrary.StubPart }

-- Всё, что нужно украшению одного зала: набор помощников и перевод координат зала в мир.
type Room = {
	kit: Kit,
	T: CFrame,
	r: Rect,
	height: number,
	at: (x: number, y: number, z: number) -> Vector3,
	cf: (cframe: CFrame) -> CFrame,
	dir: (x: number, z: number) -> Vector3,
}

local MapDecor = {}

local BONE = hex("F5EBD4")
local BONE_DARK = hex("DAC8A2")
local STEEL = hex("9AA6BC")
local DARK_METAL = hex("364054")
local WHITE = hex("F8FAFC")
local MARBLE = hex("FBF8F1")
local STONE = hex("CFC5B2")
local GOLD = hex("F5C542")
local RED = hex("E63946")
local LEAF = hex("36B856")
local LEAF_DARK = hex("248F42")

local function rad(degrees: number): number
	return math.rad(degrees)
end

-- Украшения ниже расставлены по старому залу 88 × 58 (z от 48 до 106, середина 77). С этапа 5 (блок B) центр
-- стал 120 × 120 и зал — мельче: z от r.minZ до r.maxZ. Пересчёт z: у стен (10 стадов) — тот же отступ от стены,
-- середина сжимается. Так витрины у стен не влезают в стену, а середина зала остаётся посередине.
local OLD_MIN_Z, OLD_MAX_Z, WALL_BAND = 48, 106, 10

function MapDecor.hallZ(r: Rect, z: number): number
	if z <= OLD_MIN_Z + WALL_BAND then
		return r.minZ + (z - OLD_MIN_Z)
	elseif z >= OLD_MAX_Z - WALL_BAND then
		return r.maxZ - (OLD_MAX_Z - z)
	end
	local a, b = r.minZ + WALL_BAND, r.maxZ - WALL_BAND
	return a + (z - (OLD_MIN_Z + WALL_BAND)) * (b - a) / ((OLD_MAX_Z - WALL_BAND) - (OLD_MIN_Z + WALL_BAND))
end

local function newRoom(kit: Kit, T: CFrame, r: Rect): Room
	local function mapCFrame(cframe: CFrame): CFrame
		local p = cframe.Position
		return CFrame.new(p.X, p.Y, MapDecor.hallZ(r, p.Z)) * cframe.Rotation
	end
	return {
		kit = kit,
		T = T,
		r = r,
		height = kit.hallHeight,
		at = function(x: number, y: number, z: number): Vector3
			return T * Vector3.new(x, y, MapDecor.hallZ(r, z))
		end,
		cf = function(cframe: CFrame): CFrame
			return T * mapCFrame(cframe)
		end,
		dir = function(x: number, z: number): Vector3
			return T:VectorToWorldSpace(Vector3.new(x, 0, z))
		end,
	}
end

-- Точка на поверхности стены зала и направление от стены: side — "N" (z = minZ), "S", "W" (x = minX), "E".
local function wallPoint(room: Room, side: string, along: number, y: number): (Vector3, Vector3)
	local r = room.r
	local point, facing
	if side == "N" then
		point, facing = Vector3.new(along, y, r.minZ), Vector3.new(0, 0, 1)
	elseif side == "S" then
		point, facing = Vector3.new(along, y, r.maxZ), Vector3.new(0, 0, -1)
	elseif side == "W" then
		point, facing = Vector3.new(r.minX, y, MapDecor.hallZ(r, along)), Vector3.new(1, 0, 0)
	else
		point, facing = Vector3.new(r.maxX, y, MapDecor.hallZ(r, along)), Vector3.new(-1, 0, 0)
	end
	return room.T * point, room.T:VectorToWorldSpace(facing)
end

-- Картина на стене зала (wallPainting ждёт точку на средней линии стены).
local function painting(room: Room, side: string, along: number, y: number, width: number, height: number)
	local point, facing = wallPoint(room, side, along, y)
	room.kit.painting(point - facing * 0.5, facing, width, height)
end

-- Название зала большими буквами на дальней (западной) стене.
local function hallTitle(room: Room, text: string, color: Color3, background: Color3)
	local point, facing = wallPoint(room, "W", 77, 15.6)
	room.kit.sign(point, facing, 16, 2.4, text, color, background)
end

local function plantAt(room: Room, x: number, z: number)
	local p = room.at(x, 0, z)
	room.kit.plant(p.X, p.Z)
end

local function chandelierAt(room: Room, x: number, z: number, drop: number?)
	local p = room.at(x, 0, z)
	room.kit.chandelier(p.X, p.Z, room.height, drop)
end

local function columnAt(room: Room, x: number, z: number, color: Color3, material: Enum.Material)
	local p = room.at(x, 0, z)
	room.kit.column(p.X, p.Z, room.height, color, material)
end

-- Модель из библиотеки в зале: x, z — где, (fx, fz) — куда смотрит перед модели.
local function placeAt(room: Room, name: string, x: number, y: number, z: number, fx: number, fz: number, stub: Stub, collide: boolean?): PVInstance
	local position = Vector3.new(x, y, z)
	return room.kit.place(name, room.cf(CFrame.lookAt(position, position + Vector3.new(fx, 0, fz))), stub, collide)
end

-- Деталь-украшение в координатах зала.
local function deco(room: Room, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return room.kit.decor(name, size, room.cf(cframe), color, material)
end

local function solid(room: Room, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return room.kit.solid(name, size, room.cf(cframe), color, material)
end

-- Стойка с табличкой у большого украшения.
local function infoStand(room: Room, x: number, z: number, fx: number, fz: number, text: string)
	local base = room.cf(CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x + fx, 0, z + fz)))
	room.kit.decor("InfoPost", Vector3.new(0.3, 2.6, 0.3), base * CFrame.new(0, 1.3, 0), DARK_METAL, Enum.Material.Metal)
	local board = room.kit.decor("InfoBoard", Vector3.new(2.6, 1.4, 0.12), base * CFrame.new(0, 2.8, -0.15) * CFrame.Angles(rad(-30), 0, 0), hex("1E2A44"))
	room.kit.textOn(board, Enum.NormalId.Front, text, GOLD, 0)
end

-- Потолочный светильник-диск (горит только днём): для зала Космоса вместо люстр.
local function spotLight(room: Room, x: number, z: number, color: Color3)
	local kit = room.kit
	local y = room.height - 0.25
	local disc = kit.decor("CeilingSpot", Vector3.new(0.3, 3, 3), room.cf(CFrame.new(x, y, z)) * CFrame.Angles(0, 0, rad(90)), color, Enum.Material.Neon)
	disc.Shape = Enum.PartType.Cylinder
	disc:SetAttribute(kit.dayLight, true)
	local rim = kit.decor("CeilingSpotRim", Vector3.new(0.25, 3.6, 3.6), room.cf(CFrame.new(x, y + 0.05, z)) * CFrame.Angles(0, 0, rad(90)), hex("3A4250"), Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	local light = Instance.new("PointLight")
	light.Range = 34
	light.Brightness = 1.2
	light.Color = color
	light.Shadows = true
	light:SetAttribute(kit.dayLight, true)
	light.Parent = disc
end

---------------------------------------------------------------- кости: скелеты собираются из отрезков

-- Кость-отрезок от a до b (в координатах модели). cylinder = true делает круглую кость.
local function bone(list: Stub, a: Vector3, b: Vector3, thickness: number, color: Color3, cylinder: boolean?)
	local mid = (a + b) / 2
	if cylinder then
		table.insert(list, {
			name = "Bone",
			size = Vector3.new((b - a).Magnitude, thickness, thickness),
			offset = CFrame.lookAt(mid, b) * CFrame.Angles(0, rad(90), 0),
			color = color,
			shape = Enum.PartType.Cylinder,
			collide = false,
		})
	else
		table.insert(list, { name = "Bone", size = Vector3.new(thickness, thickness, (b - a).Magnitude), offset = CFrame.lookAt(mid, b), color = color, collide = false })
	end
end

-- Позвоночник: отрезки по точкам, шарики-позвонки в сочленениях, отростки сверху (spines).
local function spine(list: Stub, points: { Vector3 }, thickness: number, spines: boolean)
	for i = 1, #points - 1 do
		bone(list, points[i], points[i + 1], thickness, BONE, true)
	end
	for i, point in points do
		local size = thickness * (if i % 2 == 0 then 1.35 else 1.15)
		table.insert(list, { name = "Vertebra", size = Vector3.new(size, size, size), offset = CFrame.new(point), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		if spines and i > 1 and i < #points then
			table.insert(list, { name = "Spine", size = Vector3.new(0.18, thickness * 1.15, 0.28), offset = CFrame.new(point + Vector3.new(0, thickness * 0.85, 0)), color = BONE, collide = false })
		end
	end
end

-- Пара рёбер с изгибом: от позвоночника наружу и вниз, потом внутрь.
local function ribs(list: Stub, z: number, top: number, width: number, depth: number)
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * 0.35, top, z)
		local b = Vector3.new(s * width, top - depth * 0.45, z + 0.15)
		local c = Vector3.new(s * width * 0.68, top - depth, z + 0.3)
		bone(list, a, b, 0.22, BONE, true)
		bone(list, b, c, 0.19, BONE, true)
	end
end

-- Металлическая подпорка от пола до скелета с латунным кольцом (как в настоящем музее).
local function supportRod(list: Stub, x: number, z: number, height: number)
	table.insert(list, { name = "Support", size = Vector3.new(height, 0.22, 0.22), offset = CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, rad(90)), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
	table.insert(list, { name = "SupportBase", size = Vector3.new(0.14, 1.1, 1.1), offset = CFrame.new(x, 0.07, z) * CFrame.Angles(0, 0, rad(90)), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
	table.insert(list, { name = "SupportCollar", size = Vector3.new(0.12, 0.38, 0.38), offset = CFrame.new(x, 0.2, z) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
end

-- Скелет тираннозавра (R3) ~20 в длину и 12 в высоту. Голова — в −Z, низ по центру.
local function trexSkeletonStub(): Stub
	local darkSocket = hex("2E2319")
	local toothColor = hex("FBF7EE")
	local list: Stub = {}
	spine(list, {
		Vector3.new(0, 3.2, 10),
		Vector3.new(0, 4.2, 8),
		Vector3.new(0, 5.3, 6),
		Vector3.new(0, 6.4, 4),
		Vector3.new(0, 7.3, 2),
		Vector3.new(0, 7.8, 0.4),
		Vector3.new(0, 8, -1.1),
		Vector3.new(0, 8.15, -2.6),
		Vector3.new(0, 8.35, -4),
		Vector3.new(0, 8.7, -5.2),
		Vector3.new(0, 9.35, -6.3),
		Vector3.new(0, 9.95, -7.2),
	}, 0.72, true)
	for i, z in { -0.9, -1.7, -2.5, -3.3, -4.1, -4.8 } do
		local scale = 1 - math.abs(i - 3) * 0.08
		ribs(list, z, 8.05, 1.55 * scale, 2.85 * scale)
	end
	table.insert(list, { name = "Sternum", size = Vector3.new(0.9, 0.25, 2.2), offset = CFrame.new(0, 5.5, -3.6) * CFrame.Angles(rad(10), 0, 0), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Pelvis", size = Vector3.new(2.2, 1.3, 1.9), offset = CFrame.new(0, 7.3, 0.5), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "PelvisBlade", size = Vector3.new(0.28, 1.55, 2.7), offset = CFrame.new(s * 1.1, 7.6, 0.5), color = BONE, collide = false })
		table.insert(list, { name = "Scapula", size = Vector3.new(0.24, 1.5, 0.55), offset = CFrame.new(s * 0.92, 8.2, -4.6) * CFrame.Angles(rad(28), 0, rad(s * -10)), color = BONE_DARK, collide = false })
		-- Нога с суставными шарами: бедро, колено, голень, лодыжка, плюсна, 3 пальца + шпора
		local hip = Vector3.new(s * 1.3, 7.1, 0.5)
		local knee = Vector3.new(s * 1.45, 4.3, -0.9)
		local ankle = Vector3.new(s * 1.35, 1.5, 0.6)
		local heel = Vector3.new(s * 1.35, 0.45, 0.2)
		table.insert(list, { name = "HipJoint", size = Vector3.new(1, 1, 1), offset = CFrame.new(hip), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		bone(list, hip, knee, 0.84, BONE, true)
		table.insert(list, { name = "Knee", size = Vector3.new(0.92, 0.92, 0.92), offset = CFrame.new(knee), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		bone(list, knee, ankle, 0.58, BONE, true)
		table.insert(list, { name = "Ankle", size = Vector3.new(0.65, 0.65, 0.65), offset = CFrame.new(ankle), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		bone(list, ankle, heel, 0.44, BONE_DARK, true)
		bone(list, heel, Vector3.new(s * 1.35, 0.55, 0.8), 0.18, BONE_DARK, true)
		for i = -1, 1 do
			local tip = Vector3.new(s * 1.35 + i * 0.4, 0.15, -1.2)
			bone(list, heel, tip, 0.22, BONE, true)
			table.insert(list, { name = "ToeClaw", size = Vector3.new(0.16, 0.2, 0.34), offset = CFrame.new(tip + Vector3.new(0, -0.02, -0.18)), color = BONE_DARK, wedge = true, collide = false })
		end
		-- Маленькие двупалые ручки с суставами и когтями
		local shoulder = Vector3.new(s * 0.88, 7.85, -4.8)
		local elbow = Vector3.new(s * 1.12, 7.05, -5.5)
		local hand = Vector3.new(s * 1.0, 7.22, -6.25)
		table.insert(list, { name = "Shoulder", size = Vector3.new(0.4, 0.4, 0.4), offset = CFrame.new(shoulder), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		bone(list, shoulder, elbow, 0.26, BONE, true)
		table.insert(list, { name = "Elbow", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(elbow), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		bone(list, elbow, hand, 0.2, BONE, true)
		for _, f in { -0.08, 0.08 } do
			table.insert(list, { name = "Claw", size = Vector3.new(0.09, 0.32, 0.11), offset = CFrame.new(hand + Vector3.new(f, -0.06, -0.16)) * CFrame.Angles(rad(-42), 0, 0), color = BONE_DARK, wedge = true, collide = false })
		end
	end
	-- Скульптурный череп тираннозавра с надбровными дугами, височными впадинами, скошенной мордой и зубами
	table.insert(list, { name = "Cranium", size = Vector3.new(1.66, 1.48, 2.1), offset = CFrame.new(0, 10.35, -8.5), color = BONE, collide = false })
	table.insert(list, { name = "CraniumBack", size = Vector3.new(1.85, 1.3, 0.7), offset = CFrame.new(0, 10.4, -7.6), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Snout", size = Vector3.new(1.18, 0.92, 1.95), offset = CFrame.new(0, 10.05, -10.35), color = BONE, collide = false })
	table.insert(list, { name = "SnoutTip", size = Vector3.new(0.96, 0.7, 0.65), offset = CFrame.new(0, 10.0, -11.45), color = BONE, wedge = true, collide = false })
	table.insert(list, { name = "NasalCrest", size = Vector3.new(0.45, 0.24, 1.75), offset = CFrame.new(0, 10.6, -10.2), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Jaw", size = Vector3.new(1.24, 0.36, 3.15), offset = CFrame.new(0, 9.15, -9.65) * CFrame.Angles(rad(-12), 0, 0), color = BONE_DARK, collide = false })
	table.insert(list, { name = "JawTip", size = Vector3.new(0.95, 0.32, 0.6), offset = CFrame.new(0, 8.85, -11.35) * CFrame.Angles(rad(-12), 0, rad(180)), color = BONE_DARK, wedge = true, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "BrowRidge", size = Vector3.new(0.28, 0.26, 1.05), offset = CFrame.new(s * 0.72, 11.12, -8.65), color = BONE_DARK, collide = false })
		table.insert(list, { name = "Eye", size = Vector3.new(0.12, 0.56, 0.66), offset = CFrame.new(s * 0.82, 10.6, -8.45), color = darkSocket, collide = false })
		table.insert(list, { name = "Fenestra", size = Vector3.new(0.12, 0.6, 0.75), offset = CFrame.new(s * 0.62, 10.2, -9.7), color = darkSocket, collide = false })
		table.insert(list, { name = "Temple", size = Vector3.new(0.12, 0.65, 0.65), offset = CFrame.new(s * 0.84, 10.45, -7.7), color = darkSocket, collide = false })
		for i = 0, 4 do
			table.insert(list, { name = "ToothTop", size = Vector3.new(0.11, 0.32, 0.12), offset = CFrame.new(s * 0.45, 9.46, -9.6 - i * 0.38) * CFrame.Angles(math.pi, 0, 0), color = toothColor, wedge = true, collide = false })
		end
		for i = 0, 3 do
			table.insert(list, { name = "ToothBot", size = Vector3.new(0.1, 0.24, 0.1), offset = CFrame.new(s * 0.4, 9.15 + i * 0.08, -9.85 - i * 0.38), color = toothColor, wedge = true, collide = false })
		end
	end
	for _, point in { Vector3.new(0, 4.2, 8), Vector3.new(0, 5.3, 6), Vector3.new(0, 6.4, 4), Vector3.new(0, 7.3, 2) } do
		table.insert(list, { name = "Chevron", size = Vector3.new(0.18, 0.75, 0.18), offset = CFrame.new(point + Vector3.new(0, -0.65, 0.1)) * CFrame.Angles(rad(-20), 0, 0), color = BONE_DARK, collide = false })
	end
	supportRod(list, 0, -3, 7.8)
	supportRod(list, 0, 4, 6)
	return list
end

-- Скелет длинношеего динозавра (R3) ~26 в длину и 14 в высоту. Голова — в −Z, низ по центру.
local function longneckSkeletonStub(): Stub
	local darkSocket = hex("2E2319")
	local list: Stub = {}
	spine(list, {
		Vector3.new(0, 2.2, 12.6),
		Vector3.new(0, 3.2, 11.3),
		Vector3.new(0, 4.4, 9.8),
		Vector3.new(0, 5.6, 8.2),
		Vector3.new(0, 6.7, 6.6),
		Vector3.new(0, 7.6, 5),
		Vector3.new(0, 8.2, 3.5),
		Vector3.new(0, 8.6, 2),
		Vector3.new(0, 8.8, 0),
		Vector3.new(0, 8.8, -2),
		Vector3.new(0, 8.6, -4),
		Vector3.new(0, 9.6, -5.5),
		Vector3.new(0, 10.7, -7),
		Vector3.new(0, 11.8, -8.4),
		Vector3.new(0, 12.7, -9.8),
		Vector3.new(0, 13.3, -11),
	}, 0.78, true)
	for i, z in { -3.2, -2.0, -0.8, 0.4, 1.6 } do
		local scale = 1 - math.abs(i - 3) * 0.08
		ribs(list, z, 8.65, 2.05 * scale, 3.5 * scale)
	end
	table.insert(list, { name = "Sternum", size = Vector3.new(1.3, 0.26, 3.2), offset = CFrame.new(0, 5.15, -1.2), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Pelvis", size = Vector3.new(2.4, 1.2, 1.8), offset = CFrame.new(0, 7.8, 3.2), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Shoulders", size = Vector3.new(2.6, 1.1, 1.2), offset = CFrame.new(0, 8, -3.2), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "PelvisBlade", size = Vector3.new(0.28, 1.4, 2.2), offset = CFrame.new(s * 1.2, 8.1, 3.2), color = BONE, collide = false })
		table.insert(list, { name = "Scapula", size = Vector3.new(0.28, 1.8, 0.9), offset = CFrame.new(s * 1.35, 8.2, -3.2) * CFrame.Angles(rad(12), 0, 0), color = BONE, collide = false })
		for _, leg in { { z = -3, knee = -3.3 }, { z = 3, knee = 2.5 } } do
			local top = Vector3.new(s * 1.5, 7.4, leg.z)
			local knee = Vector3.new(s * 1.65, 4.1, leg.knee)
			local foot = Vector3.new(s * 1.6, 0.7, leg.z + 0.1)
			table.insert(list, { name = "HipJoint", size = Vector3.new(1.1, 1.1, 1.1), offset = CFrame.new(top), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
			bone(list, top, knee, 0.92, BONE, true)
			table.insert(list, { name = "Knee", size = Vector3.new(1.02, 1.02, 1.02), offset = CFrame.new(knee), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
			bone(list, knee, foot, 0.74, BONE, true)
			table.insert(list, { name = "Foot", size = Vector3.new(0.46, 1.35, 1.35), offset = CFrame.new(s * 1.6, 0.23, leg.z - 0.1) * CFrame.Angles(0, 0, rad(90)), color = BONE_DARK, shape = Enum.PartType.Cylinder, collide = false })
			for i = -1, 1 do
				table.insert(list, { name = "ToeClaw", size = Vector3.new(0.18, 0.22, 0.34), offset = CFrame.new(s * 1.6 + i * 0.36, 0.12, leg.z - 0.88), color = BONE, wedge = true, collide = false })
			end
		end
	end
	-- Череп брахиозавра: высокий носовой гребень, суженная морда, глазницы и челюсть
	table.insert(list, { name = "Skull", size = Vector3.new(0.95, 0.82, 1.55), offset = CFrame.new(0, 13.7, -11.95), color = BONE, collide = false })
	table.insert(list, { name = "NasalCrest", size = Vector3.new(0.54, 0.56, 0.92), offset = CFrame.new(0, 14.22, -12.15), color = BONE, sphere = true, collide = false })
	table.insert(list, { name = "Snout", size = Vector3.new(0.78, 0.44, 0.75), offset = CFrame.new(0, 13.52, -12.9), color = BONE, wedge = true, collide = false })
	table.insert(list, { name = "Jaw", size = Vector3.new(0.76, 0.26, 1.45), offset = CFrame.new(0, 13.15, -12.15) * CFrame.Angles(rad(-8), 0, 0), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "Eye", size = Vector3.new(0.1, 0.34, 0.4), offset = CFrame.new(s * 0.48, 13.85, -11.8), color = darkSocket, collide = false })
		table.insert(list, { name = "Fenestra", size = Vector3.new(0.1, 0.36, 0.42), offset = CFrame.new(s * 0.44, 13.72, -12.4), color = darkSocket, collide = false })
	end
	for _, point in { Vector3.new(0, 9.6, -5.5), Vector3.new(0, 10.7, -7), Vector3.new(0, 11.8, -8.4), Vector3.new(0, 12.7, -9.8) } do
		for _, s in { -1, 1 } do
			table.insert(list, { name = "NeckRib", size = Vector3.new(0.14, 0.14, 0.75), offset = CFrame.new(point + Vector3.new(s * 0.45, -0.32, 0.1)) * CFrame.Angles(rad(60), 0, 0), color = BONE_DARK, collide = false })
		end
	end
	for _, point in { Vector3.new(0, 4.4, 9.8), Vector3.new(0, 5.6, 8.2), Vector3.new(0, 6.7, 6.6), Vector3.new(0, 7.6, 5) } do
		table.insert(list, { name = "Chevron", size = Vector3.new(0.18, 0.72, 0.18), offset = CFrame.new(point + Vector3.new(0, -0.62, 0.1)) * CFrame.Angles(rad(-20), 0, 0), color = BONE_DARK, collide = false })
	end
	supportRod(list, 0, -6, 9.8)
	supportRod(list, 0, -9.2, 12.4)
	supportRod(list, 0, 8.4, 5.4)
	return list
end

-- Пальма в каменной кадке: изогнутый ствол с кольцами, листья в две части (чтобы свисали), кокосы.
local function palmStub(): Stub
	local list: Stub = {
		{ name = "Planter", size = Vector3.new(1.1, 3.2, 3.2), offset = CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("8E8A80"), material = Enum.Material.Slate, shape = Enum.PartType.Cylinder },
		{ name = "Soil", size = Vector3.new(0.1, 2.8, 2.8), offset = CFrame.new(0, 1.12, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("5C4326"), material = Enum.Material.Ground, shape = Enum.PartType.Cylinder },
	}
	local top = Vector3.new(0, 1.1, 0)
	for i = 1, 5 do
		local nextTop = Vector3.new(0.12 * i ^ 1.4, 1.1 + 1.75 * i, 0)
		bone(list, top, nextTop, 0.95 - i * 0.08, hex("7A5A3A"))
		list[#list].material = Enum.Material.Wood
		list[#list].collide = true
		table.insert(list, { name = "TrunkRing", size = Vector3.new(1.05 - i * 0.08, 0.18, 1.05 - i * 0.08), offset = CFrame.new(nextTop), color = hex("5C4326"), material = Enum.Material.Wood, collide = false })
		top = nextTop
	end
	for i = 0, 7 do
		local around = CFrame.new(top) * CFrame.Angles(0, i * math.pi / 4 + 0.2, 0)
		local inner = around * CFrame.Angles(rad(12), 0, 0) * CFrame.new(0, 0, -1.25)
		table.insert(list, { name = "Frond", size = Vector3.new(1, 0.1, 2.6), offset = inner, color = if i % 2 == 0 then LEAF else LEAF_DARK, material = Enum.Material.Grass, collide = false })
		local outer = inner * CFrame.new(0, 0, -1.2) * CFrame.Angles(rad(-38), 0, 0) * CFrame.new(0, 0, -1.1)
		table.insert(list, { name = "FrondTip", size = Vector3.new(0.8, 0.1, 2.3), offset = outer, color = if i % 2 == 0 then LEAF_DARK else LEAF, material = Enum.Material.Grass, collide = false })
	end
	for i = 0, 2 do
		local angle = i * 2.1
		table.insert(list, { name = "Coconut", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(top + Vector3.new(math.cos(angle) * 0.45, -0.5, math.sin(angle) * 0.45)), color = hex("6B4A2B"), shape = Enum.PartType.Ball, collide = false })
	end
	return list
end

-- Папоротник: листья веером.
local function fern(room: Room, x: number, z: number, scale: number)
	for i = 0, 5 do
		local cframe = CFrame.new(x, 0.3 * scale, z) * CFrame.Angles(0, i * math.pi / 3 + x, 0) * CFrame.Angles(rad(32), 0, 0) * CFrame.new(0, 0, -1.1 * scale)
		deco(room, "Fern", Vector3.new(0.55 * scale, 0.08, 2.2 * scale), cframe, if i % 2 == 0 then LEAF else LEAF_DARK, Enum.Material.Grass)
	end
end

-- Валун: несколько камней вместе (твёрдые — за ними можно укрыться).
local function boulder(room: Room, x: number, z: number, size: number)
	local color = hex("8E8A80")
	local main = solid(room, "Rock", Vector3.new(size, size, size), CFrame.new(x, size * 0.35, z), color, Enum.Material.Slate)
	main.Shape = Enum.PartType.Ball
	local side = solid(room, "Rock", Vector3.new(size * 0.7, size * 0.7, size * 0.7), CFrame.new(x + size * 0.45, size * 0.2, z + size * 0.2), hex("A39E92"), Enum.Material.Slate)
	side.Shape = Enum.PartType.Ball
end

---------------------------------------------------------------- модели других залов

-- Фонтан со статуей (R3): ступенчатая мраморная чаша, золотые изливы на ободе, переливающиеся струи,
-- рифлёная колонна с кронштейнами, верхняя чаша, урна с ручками и бирюзовая вода. Низ по центру.
local function buildFountainStub(): Stub
	local waterColor = hex("3BC6C1")
	local jetColor = hex("AEEBFF")
	local foamColor = hex("F2FAFF")
	local brassDark = hex("C9922A")
	local marbleWarm = hex("E8DCC4")
	local list: Stub = {
		{ name = "BasinStep", size = Vector3.new(0.32, 10.1, 10.1), offset = CFrame.new(0, 0.16, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "Basin", size = Vector3.new(1.36, 9, 9), offset = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "BasinBand", size = Vector3.new(0.18, 9.2, 9.2), offset = CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, rad(90)), color = marbleWarm, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Rim", size = Vector3.new(0.32, 9.6, 9.6), offset = CFrame.new(0, 1.72, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "RimLip", size = Vector3.new(0.12, 9.1, 9.1), offset = CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PoolGlow", size = Vector3.new(0.08, 3.2, 3.2), offset = CFrame.new(0, 1.48, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("3BC6C1"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Water", size = Vector3.new(0.14, 8.2, 8.2), offset = CFrame.new(0, 1.76, 0) * CFrame.Angles(0, 0, rad(90)), color = waterColor, material = Enum.Material.Glass, transparency = 0.55, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PillarBase", size = Vector3.new(0.45, 2.2, 2.2), offset = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Pillar", size = Vector3.new(2.3, 1.45, 1.45), offset = CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "PillarCap", size = Vector3.new(0.3, 2, 2), offset = CFrame.new(0, 4.35, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Bowl", size = Vector3.new(0.46, 4.2, 4.2), offset = CFrame.new(0, 4.65, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "BowlRim", size = Vector3.new(0.18, 4.6, 4.6), offset = CFrame.new(0, 4.88, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "BowlWater", size = Vector3.new(0.08, 3.6, 3.6), offset = CFrame.new(0, 4.9, 0) * CFrame.Angles(0, 0, rad(90)), color = waterColor, material = Enum.Material.Glass, transparency = 0.55, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "UrnBase", size = Vector3.new(0.45, 1.35, 1.35), offset = CFrame.new(0, 5.15, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Urn", size = Vector3.new(0.7, 0.85, 0.85), offset = CFrame.new(0, 5.65, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
		{ name = "UrnBody", size = Vector3.new(1.2, 1.1, 1.2), offset = CFrame.new(0, 6.2, 0), color = MARBLE, material = Enum.Material.Marble, sphere = true },
		{ name = "UrnCollar", size = Vector3.new(0.16, 0.72, 0.72), offset = CFrame.new(0, 6.82, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "UrnTop", size = Vector3.new(0.46, 0.46, 0.46), offset = CFrame.new(0, 7.12, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "UrnTip", size = Vector3.new(0.32, 0.14, 0.14), offset = CFrame.new(0, 7.42, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
	}
	for _, x in { -0.66, 0.66 } do
		table.insert(list, { name = "UrnHandle", size = Vector3.new(0.12, 0.62, 0.18), offset = CFrame.new(x, 6.32, 0) * CFrame.Angles(0, 0, rad(if x < 0 then 18 else -18)), color = GOLD, material = Enum.Material.Metal, collide = false })
	end
	for i = 0, 3 do
		local rot = CFrame.Angles(0, i * math.pi / 2, 0)
		table.insert(list, { name = "PillarFlute", size = Vector3.new(0.18, 2.1, 0.18), offset = rot * CFrame.new(0, 3.2, -0.74), color = STONE, material = Enum.Material.Marble, collide = false })
		table.insert(list, { name = "Bracket", size = Vector3.new(0.3, 0.6, 0.7), offset = rot * CFrame.new(0, 4.2, -1.05) * CFrame.Angles(rad(180), 0, 0), color = marbleWarm, material = Enum.Material.Marble, wedge = true, collide = false })
		-- Кардинальные маскароны-изливы на ободе чаши и струи воды в 2 сегмента с пеной
		table.insert(list, { name = "SpoutBoss", size = Vector3.new(0.75, 0.75, 0.45), offset = rot * CFrame.new(0, 1.35, -4.6), color = STONE, material = Enum.Material.Marble, collide = false })
		table.insert(list, { name = "SpoutNozzle", size = Vector3.new(0.28, 0.24, 0.24), offset = rot * CFrame.new(0, 1.48, -4.25) * CFrame.Angles(0, rad(90), 0), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "JetTop", size = Vector3.new(0.12, 0.12, 1.4), offset = rot * CFrame.new(0, 4.55, -2.55) * CFrame.Angles(rad(-24), 0, 0), color = jetColor, material = Enum.Material.Glass, transparency = 0.55, collide = false })
		table.insert(list, { name = "JetLow", size = Vector3.new(0.14, 0.14, 2.3), offset = rot * CFrame.new(0, 3.05, -3.25) * CFrame.Angles(rad(-68), 0, 0), color = jetColor, material = Enum.Material.Glass, transparency = 0.55, collide = false })
		table.insert(list, { name = "Splash", size = Vector3.new(0.08, 0.9, 0.9), offset = rot * CFrame.new(0, 1.84, -3.5) * CFrame.Angles(0, 0, rad(90)), color = foamColor, material = Enum.Material.Glass, transparency = 0.52, shape = Enum.PartType.Cylinder, collide = false })
	end
	return list
end
local FOUNTAIN_STUB: Stub = buildFountainStub()

-- Большая мраморная статуя на постаменте (R3): ступенчатый пьедестал, фигура в тоге со свитком и лавровым венком.
-- Перед в −Z (y = 1.2, z = -1.56 оставлен чистым для frontPlaque).
local function buildStatueStub(): Stub
	local marbleWarm = hex("E8DCC4")
	local brassDark = hex("C9922A")
	local list: Stub = {
		{ name = "PlinthBase", size = Vector3.new(3.3, 0.34, 3.3), offset = CFrame.new(0, 0.17, 0), color = STONE, material = Enum.Material.Marble },
		{ name = "Plinth", size = Vector3.new(3, 1.66, 3), offset = CFrame.new(0, 1.17, 0), color = STONE, material = Enum.Material.Marble },
		{ name = "PlinthCap", size = Vector3.new(3.4, 0.24, 3.4), offset = CFrame.new(0, 2.12, 0), color = MARBLE, material = Enum.Material.Marble },
		{ name = "PlinthBevel", size = Vector3.new(3.08, 0.14, 3.08), offset = CFrame.new(0, 2.31, 0), color = marbleWarm, material = Enum.Material.Marble, collide = false },
		{ name = "StatuePad", size = Vector3.new(2.2, 0.14, 2.2), offset = CFrame.new(0, 2.45, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
		{ name = "PanelBack", size = Vector3.new(2.1, 1.15, 0.06), offset = CFrame.new(0, 1.18, 1.52), color = MARBLE, material = Enum.Material.Marble, collide = false },
		{ name = "PanelL", size = Vector3.new(0.06, 1.15, 2.1), offset = CFrame.new(-1.52, 1.18, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
		{ name = "PanelR", size = Vector3.new(0.06, 1.15, 2.1), offset = CFrame.new(1.52, 1.18, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
		-- Ноги, сандалии и складки тоги
		{ name = "FootL", size = Vector3.new(0.58, 0.26, 0.9), offset = CFrame.new(-0.46, 2.62, -0.18), color = marbleWarm, material = Enum.Material.Marble, collide = false },
		{ name = "FootR", size = Vector3.new(0.58, 0.26, 0.9), offset = CFrame.new(0.46, 2.62, 0.08), color = marbleWarm, material = Enum.Material.Marble, collide = false },
		{ name = "LegL", size = Vector3.new(2.3, 0.68, 0.68), offset = CFrame.new(-0.46, 3.7, -0.04) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "LegR", size = Vector3.new(2.3, 0.68, 0.68), offset = CFrame.new(0.46, 3.7, 0.12) * CFrame.Angles(rad(-7), 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Robe", size = Vector3.new(1.9, 1.85, 1.15), offset = CFrame.new(0, 4.45, 0.02), color = MARBLE, material = Enum.Material.Marble, collide = false },
		{ name = "RobeFoldL", size = Vector3.new(1.75, 0.34, 0.34), offset = CFrame.new(-0.55, 4.45, -0.52) * CFrame.Angles(0, 0, rad(90)), color = marbleWarm, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "RobeFoldC", size = Vector3.new(1.85, 0.36, 0.36), offset = CFrame.new(0, 4.42, -0.55) * CFrame.Angles(0, 0, rad(90)), color = marbleWarm, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "RobeFoldR", size = Vector3.new(1.75, 0.34, 0.34), offset = CFrame.new(0.55, 4.45, -0.52) * CFrame.Angles(0, 0, rad(90)), color = marbleWarm, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		-- Торс, перевязь, свиток в левой руке, лавровый венок в поднятой правой
		{ name = "Torso", size = Vector3.new(1.82, 2.05, 1.05), offset = CFrame.new(0, 6.05, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
		{ name = "Chest", size = Vector3.new(1.56, 0.9, 1.12), offset = CFrame.new(0, 6.45, -0.05), color = MARBLE, material = Enum.Material.Marble, sphere = true, collide = false },
		{ name = "Drape", size = Vector3.new(2.26, 0.44, 1.18), offset = CFrame.new(0, 6.32, 0) * CFrame.Angles(0, 0, rad(28)), color = marbleWarm, material = Enum.Material.Marble, collide = false },
		{ name = "Clasp", size = Vector3.new(0.14, 0.36, 0.36), offset = CFrame.new(-0.68, 6.72, -0.56) * CFrame.Angles(0, rad(90), 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "ShoulderL", size = Vector3.new(0.65, 0.65, 0.65), offset = CFrame.new(-1.1, 6.75, 0), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
		{ name = "ArmL", size = Vector3.new(1.85, 0.56, 0.56), offset = CFrame.new(-1.24, 5.85, -0.1) * CFrame.Angles(rad(-12), 0, rad(84)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "HandL", size = Vector3.new(0.42, 0.42, 0.42), offset = CFrame.new(-1.35, 4.95, -0.28), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
		{ name = "Scroll", size = Vector3.new(1.1, 0.24, 0.24), offset = CFrame.new(-1.35, 4.95, -0.35) * CFrame.Angles(0, rad(75), 0), color = marbleWarm, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "ShoulderR", size = Vector3.new(0.65, 0.65, 0.65), offset = CFrame.new(1.1, 6.8, -0.05), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
		{ name = "ArmR", size = Vector3.new(2.15, 0.56, 0.56), offset = CFrame.new(1.32, 7.65, -0.18) * CFrame.Angles(rad(-10), 0, rad(68)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "HandR", size = Vector3.new(0.42, 0.42, 0.42), offset = CFrame.new(1.72, 8.62, -0.34), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
		{ name = "Wreath", size = Vector3.new(0.16, 1.04, 1.04), offset = CFrame.new(1.78, 8.95, -0.36) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "WreathCore", size = Vector3.new(0.2, 0.62, 0.62), offset = CFrame.new(1.78, 8.95, -0.36) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "WreathGem", size = Vector3.new(0.22, 0.22, 0.22), offset = CFrame.new(1.78, 9.46, -0.36), color = RED, material = Enum.Material.Neon, shape = Enum.PartType.Ball, collide = false },
		-- Голова с профилем и лавровой лентой
		{ name = "Neck", size = Vector3.new(0.5, 0.48, 0.48), offset = CFrame.new(0, 7.18, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Head", size = Vector3.new(1.06, 1.18, 1.12), offset = CFrame.new(0, 7.8, -0.02), color = MARBLE, material = Enum.Material.Marble, sphere = true, collide = false },
		{ name = "Nose", size = Vector3.new(0.16, 0.26, 0.22), offset = CFrame.new(0, 7.78, -0.58), color = MARBLE, material = Enum.Material.Marble, wedge = true, collide = false },
		{ name = "Hair", size = Vector3.new(1.18, 1.02, 1.16), offset = CFrame.new(0, 8.05, 0.14), color = marbleWarm, material = Enum.Material.Marble, sphere = true, collide = false },
		{ name = "Laurel", size = Vector3.new(0.14, 1.14, 1.14), offset = CFrame.new(0, 8.08, -0.02) * CFrame.Angles(rad(12), 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
	}
	for _, x in { -1.48, 1.48 } do
		for _, z in { -1.48, 1.48 } do
			table.insert(list, { name = "PlinthCorner", size = Vector3.new(0.24, 1.66, 0.24), offset = CFrame.new(x, 1.17, z), color = marbleWarm, material = Enum.Material.Marble, collide = false })
		end
	end
	return list
end
local STATUE_STUB: Stub = buildStatueStub()

-- Сатурн (R3): многослойные полосы облаков, штормовой овал, многоступенчатые кольца с щелью Кассини,
-- спутник Титан с дымкой атмосферы и ледяной спутник. Точка привязки — центр планеты.
local function buildPlanetStub(): Stub
	local ringTilt = CFrame.Angles(rad(18), 0, rad(8)) * CFrame.Angles(0, 0, rad(90))
	return {
		{ name = "Planet", size = Vector3.new(7, 7, 7), offset = CFrame.identity, color = hex("E3C98B"), shape = Enum.PartType.Ball, collide = false },
		{ name = "Band", size = Vector3.new(7.04, 0.45, 7.04), offset = CFrame.new(0, 2.3, 0), color = hex("B8955A"), sphere = true, collide = false },
		{ name = "Band", size = Vector3.new(7.05, 0.85, 7.05), offset = CFrame.new(0, 1.1, 0), color = hex("C9A86A"), sphere = true, collide = false },
		{ name = "Band", size = Vector3.new(7.06, 0.45, 7.06), offset = CFrame.new(0, 0.1, 0), color = hex("F2E3B8"), sphere = true, collide = false },
		{ name = "Band", size = Vector3.new(7.05, 0.55, 7.05), offset = CFrame.new(0, -0.7, 0), color = hex("EAD7A6"), sphere = true, collide = false },
		{ name = "Band", size = Vector3.new(7.05, 0.75, 7.05), offset = CFrame.new(0, -1.65, 0), color = hex("C9A468"), sphere = true, collide = false },
		{ name = "Band", size = Vector3.new(7.04, 0.45, 7.04), offset = CFrame.new(0, -2.45, 0), color = hex("A88A55"), sphere = true, collide = false },
		{ name = "StormSpot", size = Vector3.new(1.5, 0.8, 0.4), offset = CFrame.new(1.2, -1.1, -3.15) * CFrame.Angles(rad(-16), rad(-20), 0), color = hex("E63946"), sphere = true, collide = false },
		{ name = "PoleN", size = Vector3.new(3.1, 0.55, 3.1), offset = CFrame.new(0, 3.28, 0), color = hex("8E7A52"), sphere = true, collide = false },
		{ name = "PoleS", size = Vector3.new(3.0, 0.55, 3.0), offset = CFrame.new(0, -3.28, 0), color = hex("8E7A52"), sphere = true, collide = false },
		{ name = "HookRing", size = Vector3.new(0.18, 0.52, 0.52), offset = CFrame.new(0, 3.55, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		-- Кольца: внутреннее C, яркое B, тёмная щель Кассини, внешнее A и кайма F
		{ name = "RingC", size = Vector3.new(0.14, 9.6, 9.6), offset = ringTilt, color = hex("8E7A52"), transparency = 0.45, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "RingB", size = Vector3.new(0.12, 11.8, 11.8), offset = ringTilt, color = hex("EAD7A6"), transparency = 0.14, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "CassiniGap", size = Vector3.new(0.13, 12.2, 12.2), offset = ringTilt, color = hex("1B202B"), transparency = 0.55, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "RingA", size = Vector3.new(0.1, 13.8, 13.8), offset = ringTilt, color = hex("D9C28A"), transparency = 0.2, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "RingF", size = Vector3.new(0.08, 14.8, 14.8), offset = ringTilt, color = hex("F5E8C8"), transparency = 0.58, shape = Enum.PartType.Cylinder, collide = false },
		-- Спутники: Титан с оранжевой дымкой и ледяной Энцелад
		{ name = "Moon", size = Vector3.new(1.3, 1.3, 1.3), offset = CFrame.new(8.6, 1.5, -2.2), color = hex("D9A55A"), shape = Enum.PartType.Ball, collide = false },
		{ name = "MoonHaze", size = Vector3.new(1.52, 1.52, 1.52), offset = CFrame.new(8.6, 1.5, -2.2), color = hex("FFE29A"), material = Enum.Material.Glass, transparency = 0.65, shape = Enum.PartType.Ball, collide = false },
		{ name = "Moonlet", size = Vector3.new(0.7, 0.7, 0.7), offset = CFrame.new(-7.6, -1.2, 3.4), color = hex("D6E8F5"), shape = Enum.PartType.Ball, collide = false },
	}
end
local PLANET_STUB: Stub = buildPlanetStub()

-- Большая ракета на стартовом столе и красная башня обслуживания (R3). Низ по центру.
local function rocketStub(): Stub
	local function vertical(name: string, height: number, diameter: number, y: number, color: Color3, material: Enum.Material?, collide: boolean?): ModelLibrary.StubPart
		return { name = name, size = Vector3.new(height, diameter, diameter), offset = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, rad(90)), color = color, material = material, shape = Enum.PartType.Cylinder, collide = collide }
	end
	local brassDark = hex("C9922A")
	local list: Stub = {
		vertical("PadBase", 0.35, 9.6, 0.175, hex("2B2F3A"), Enum.Material.Metal),
		vertical("Pad", 0.72, 9, 0.66, DARK_METAL, Enum.Material.Metal),
		vertical("PadRing", 0.06, 8.5, 1.03, hex("F2C230")),
		vertical("PadInner", 0.08, 7.1, 1.05, hex("1E2A44")),
		vertical("Glow", 0.12, 2.2, 1.1, hex("FF8A3D"), Enum.Material.Neon, false),
		vertical("Engine", 1.2, 2.2, 1.75, hex("4A5060"), Enum.Material.Metal),
		vertical("EngineRing", 0.22, 2.45, 2.3, DARK_METAL, Enum.Material.Metal),
		vertical("EngineCore", 0.15, 1.55, 1.15, hex("FF9E3D"), Enum.Material.Neon, false),
		vertical("BodyLow", 6, 3.2, 5.35, WHITE),
		vertical("BandLow", 0.55, 3.3, 3.1, RED),
		vertical("BandGold", 0.16, 3.32, 3.46, GOLD, Enum.Material.Metal, false),
		vertical("BandHigh", 0.5, 3.3, 7.9, RED),
		vertical("Interstage", 0.45, 3.1, 8.38, hex("243B6B"), Enum.Material.Metal),
		vertical("BodyHigh", 3.8, 2.8, 10.45, WHITE),
		vertical("NoseCollar", 0.25, 2.9, 12.35, RED, Enum.Material.Metal),
		vertical("Nose", 1.2, 2.25, 13.05, WHITE),
		vertical("NoseTop", 1, 1.45, 14.05, WHITE),
		vertical("EscapePost", 0.9, 0.32, 14.95, RED, Enum.Material.Metal, false),
		{ name = "Tip", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(0, 15.45, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball, collide = false },
		{ name = "WindowRing", size = Vector3.new(0.16, 1.55, 1.55), offset = CFrame.new(0, 10.6, -1.36) * CFrame.Angles(0, rad(90), 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Window", size = Vector3.new(0.18, 1.18, 1.18), offset = CFrame.new(0, 10.6, -1.4) * CFrame.Angles(0, rad(90), 0), color = hex("3BC6C1"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, collide = false },
	}
	-- 4 стабилизатора, посадочные опоры с гидравликой и дефлекторы стола
	for i = 0, 3 do
		local rot = CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0)
		table.insert(list, { name = "Fin", size = Vector3.new(0.28, 3.1, 2.2), offset = rot * CFrame.new(0, 3.6, -2.5), color = RED, wedge = true })
		table.insert(list, { name = "FinTip", size = Vector3.new(0.32, 1.1, 0.3), offset = rot * CFrame.new(0, 2.6, -3.55), color = GOLD, material = Enum.Material.Metal, collide = false })
		table.insert(list, { name = "Leg", size = Vector3.new(0.42, 1.55, 0.42), offset = rot * CFrame.new(0, 1.75, -1.95) * CFrame.Angles(rad(-18), 0, 0), color = DARK_METAL, material = Enum.Material.Metal })
		table.insert(list, { name = "FootPad", size = Vector3.new(0.18, 0.85, 0.85), offset = rot * CFrame.new(0, 1.12, -2.3) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "BlastDeflector", size = Vector3.new(1.4, 0.45, 0.9), offset = rot * CFrame.new(0, 1.25, -3.7), color = hex("4A5060"), material = Enum.Material.Metal, wedge = true, collide = false })
	end
	-- Башня обслуживания позади ракеты с раскосами, лестницей и рукавами заправки
	for _, x in { -1.4, 1.4 } do
		table.insert(list, { name = "Tower", size = Vector3.new(0.48, 15, 0.48), offset = CFrame.new(x, 8.5, 3.6), color = RED, material = Enum.Material.Metal })
	end
	for y = 2.5, 14.5, 3 do
		table.insert(list, { name = "TowerBar", size = Vector3.new(3.3, 0.28, 0.28), offset = CFrame.new(0, y, 3.6), color = RED, material = Enum.Material.Metal })
		if y < 14 then
			table.insert(list, { name = "TowerBrace", size = Vector3.new(0.16, 4.1, 0.16), offset = CFrame.new(0, y + 1.5, 3.6) * CFrame.Angles(0, 0, rad(if math.floor(y) % 2 == 0 then 42 else -42)), color = RED, material = Enum.Material.Metal, collide = false })
		end
	end
	for y = 4, 13, 3 do
		table.insert(list, { name = "TowerDeck", size = Vector3.new(3.5, 0.16, 1.2), offset = CFrame.new(0, y, 3.6), color = hex("F2C230"), material = Enum.Material.DiamondPlate, collide = false })
		table.insert(list, { name = "DeckRail", size = Vector3.new(3.5, 0.08, 0.08), offset = CFrame.new(0, y + 0.65, 3.04), color = DARK_METAL, material = Enum.Material.Metal, collide = false })
	end
	table.insert(list, { name = "TowerArm", size = Vector3.new(0.32, 0.32, 2.3), offset = CFrame.new(0, 11.5, 2.4), color = DARK_METAL, material = Enum.Material.Metal })
	table.insert(list, { name = "Umbilical", size = Vector3.new(0.16, 0.16, 2.1), offset = CFrame.new(0.35, 11.1, 2.4) * CFrame.Angles(rad(14), 0, 0), color = GOLD, material = Enum.Material.Metal, collide = false })
	table.insert(list, { name = "BeaconPost", size = Vector3.new(0.2, 0.5, 0.2), offset = CFrame.new(0, 15.9, 3.6), color = DARK_METAL, material = Enum.Material.Metal, collide = false })
	table.insert(list, { name = "Beacon", size = Vector3.new(0.52, 0.52, 0.52), offset = CFrame.new(0, 16.25, 3.6), color = RED, material = Enum.Material.Neon, shape = Enum.PartType.Ball, collide = false })
	-- Два боковых ускорителя со ступенчатыми соплами и двойными креплениями
	for _, x in { -2.18, 2.18 } do
		table.insert(list, vertical("Booster", 6.4, 1.14, 4.9, hex("E8ECF2"), nil, true))
		table.insert(list, { name = "BoosterNose", size = Vector3.new(1.14, 1.35, 1.14), offset = CFrame.new(x, 8.2, 0), color = RED, sphere = true, collide = false })
		table.insert(list, { name = "BoosterBand", size = Vector3.new(0.3, 1.2, 1.2), offset = CFrame.new(x, 6.6, 0) * CFrame.Angles(0, 0, rad(90)), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "BoosterBandLow", size = Vector3.new(0.24, 1.2, 1.2), offset = CFrame.new(x, 2.3, 0) * CFrame.Angles(0, 0, rad(90)), color = RED, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "BoosterNozzle", size = Vector3.new(0.55, 0.84, 0.84), offset = CFrame.new(x, 1.45, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("4A5060"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "BoosterGlow", size = Vector3.new(0.1, 0.56, 0.56), offset = CFrame.new(x, 1.16, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("FF8A3D"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, collide = false })
		for _, sy in { 3.2, 6.4 } do
			table.insert(list, { name = "Strut", size = Vector3.new(0.95, 0.22, 0.24), offset = CFrame.new(x * 0.78, sy, 0), color = DARK_METAL, material = Enum.Material.Metal, collide = false })
		end
	end
	for _, y in { 8.9, 12 } do
		table.insert(list, { name = "PortholeRim", size = Vector3.new(0.1, 0.92, 0.92), offset = CFrame.new(0, y, -1.35) * CFrame.Angles(0, rad(90), 0), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "Porthole", size = Vector3.new(0.14, 0.68, 0.68), offset = CFrame.new(0, y, -1.38) * CFrame.Angles(0, rad(90), 0), color = hex("3BC6C1"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, collide = false })
	end
	table.insert(list, { name = "Stripe", size = Vector3.new(0.45, 2.2, 0.12), offset = CFrame.new(0, 5.6, -1.61), color = hex("243B6B"), collide = false })
	return list
end

-- Космонавт с флагом на лунном камне (R3). Перед в −Z.
local function buildAstronautStub(): Stub
	local navy = hex("1E2A44")
	local suitGrey = hex("A9B0BC")
	local moonGrey = hex("8B929E")
	return {
		{ name = "Base", size = Vector3.new(0.32, 3.1, 3.1), offset = CFrame.new(0, 0.16, 0) * CFrame.Angles(0, 0, rad(90)), color = navy, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "BaseRim", size = Vector3.new(0.08, 3.16, 3.16), offset = CFrame.new(0, 0.34, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "LunarMound", size = Vector3.new(0.26, 2.7, 2.7), offset = CFrame.new(0, 0.44, 0) * CFrame.Angles(0, 0, rad(90)), color = moonGrey, material = Enum.Material.Slate, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "MoonRockL", size = Vector3.new(0.55, 0.36, 0.48), offset = CFrame.new(-0.95, 0.65, -0.55) * CFrame.Angles(0, rad(24), 0), color = hex("6E7686"), material = Enum.Material.Slate, sphere = true, collide = false },
		{ name = "MoonRockR", size = Vector3.new(0.48, 0.32, 0.42), offset = CFrame.new(0.9, 0.62, 0.65) * CFrame.Angles(0, rad(-18), 0), color = hex("6E7686"), material = Enum.Material.Slate, sphere = true, collide = false },
		{ name = "BootSoleL", size = Vector3.new(0.84, 0.16, 1.16), offset = CFrame.new(-0.5, 0.62, -0.1), color = DARK_METAL, material = Enum.Material.Rubber, collide = false },
		{ name = "BootSoleR", size = Vector3.new(0.84, 0.16, 1.16), offset = CFrame.new(0.5, 0.62, -0.1), color = DARK_METAL, material = Enum.Material.Rubber, collide = false },
		{ name = "BootL", size = Vector3.new(0.8, 0.52, 1.08), offset = CFrame.new(-0.5, 0.9, -0.08), color = suitGrey, collide = false },
		{ name = "BootR", size = Vector3.new(0.8, 0.52, 1.08), offset = CFrame.new(0.5, 0.9, -0.08), color = suitGrey, collide = false },
		{ name = "LegL", size = Vector3.new(1.75, 0.84, 0.84), offset = CFrame.new(-0.5, 1.95, 0) * CFrame.Angles(0, 0, rad(90)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "LegR", size = Vector3.new(1.75, 0.84, 0.84), offset = CFrame.new(0.5, 1.95, 0) * CFrame.Angles(0, 0, rad(90)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "KneePadL", size = Vector3.new(0.54, 0.38, 0.14), offset = CFrame.new(-0.5, 1.9, -0.42), color = suitGrey, collide = false },
		{ name = "KneePadR", size = Vector3.new(0.54, 0.38, 0.14), offset = CFrame.new(0.5, 1.9, -0.42), color = suitGrey, collide = false },
		{ name = "Belt", size = Vector3.new(2.08, 0.28, 1.28), offset = CFrame.new(0, 2.95, 0), color = suitGrey, collide = false },
		{ name = "BeltBuckle", size = Vector3.new(0.45, 0.3, 0.1), offset = CFrame.new(0, 2.95, -0.66), color = GOLD, material = Enum.Material.Metal, collide = false },
		{ name = "Torso", size = Vector3.new(2, 1.95, 1.2), offset = CFrame.new(0, 3.9, 0), color = WHITE, collide = false },
		{ name = "ChestPanel", size = Vector3.new(1.1, 0.72, 0.14), offset = CFrame.new(0, 4.05, -0.64), color = navy, collide = false },
		{ name = "ChestDial", size = Vector3.new(0.06, 0.26, 0.26), offset = CFrame.new(-0.32, 4.18, -0.72) * CFrame.Angles(0, rad(90), 0), color = hex("3BC6C1"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Button", size = Vector3.new(0.18, 0.18, 0.06), offset = CFrame.new(0, 4.16, -0.72), color = RED, material = Enum.Material.Neon, collide = false },
		{ name = "Button", size = Vector3.new(0.18, 0.18, 0.06), offset = CFrame.new(0.28, 4.16, -0.72), color = hex("3FB56B"), material = Enum.Material.Neon, collide = false },
		{ name = "Button", size = Vector3.new(0.6, 0.14, 0.06), offset = CFrame.new(0.14, 3.88, -0.72), color = GOLD, material = Enum.Material.Neon, collide = false },
		-- Ранец жизнеобеспечения PLSS с баллонами и антенной
		{ name = "Backpack", size = Vector3.new(1.8, 1.95, 0.78), offset = CFrame.new(0, 3.95, 0.96), color = hex("C9CED6"), collide = false },
		{ name = "TankL", size = Vector3.new(1.5, 0.5, 0.5), offset = CFrame.new(-0.48, 3.95, 1.32) * CFrame.Angles(0, 0, rad(90)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "TankR", size = Vector3.new(1.5, 0.5, 0.5), offset = CFrame.new(0.48, 3.95, 1.32) * CFrame.Angles(0, 0, rad(90)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PackStripe", size = Vector3.new(1.82, 0.2, 0.8), offset = CFrame.new(0, 4.45, 0.96), color = RED, collide = false },
		{ name = "Antenna", size = Vector3.new(1.1, 0.08, 0.08), offset = CFrame.new(-0.68, 5.4, 1.1) * CFrame.Angles(0, 0, rad(90)), color = STEEL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		-- Руки с плечевыми кольцами и перчатками
		{ name = "ShoulderL", size = Vector3.new(0.75, 0.75, 0.75), offset = CFrame.new(-1.26, 4.5, 0), color = RED, shape = Enum.PartType.Ball, collide = false },
		{ name = "ShoulderR", size = Vector3.new(0.75, 0.75, 0.75), offset = CFrame.new(1.26, 4.5, -0.08), color = RED, shape = Enum.PartType.Ball, collide = false },
		{ name = "ArmL", size = Vector3.new(1.6, 0.68, 0.68), offset = CFrame.new(-1.42, 3.65, 0) * CFrame.Angles(0, 0, rad(84)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "ArmR", size = Vector3.new(1.65, 0.68, 0.68), offset = CFrame.new(1.42, 3.85, -0.24) * CFrame.Angles(rad(-26), 0, rad(90)), color = WHITE, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "CuffL", size = Vector3.new(0.14, 0.74, 0.74), offset = CFrame.new(-1.46, 2.85, 0) * CFrame.Angles(0, 0, rad(90)), color = navy, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "CuffR", size = Vector3.new(0.14, 0.74, 0.74), offset = CFrame.new(1.44, 3.16, -0.56) * CFrame.Angles(rad(64), 0, 0), color = navy, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "GloveL", size = Vector3.new(0.58, 0.58, 0.58), offset = CFrame.new(-1.48, 2.52, 0), color = suitGrey, shape = Enum.PartType.Ball, collide = false },
		{ name = "GloveR", size = Vector3.new(0.58, 0.58, 0.58), offset = CFrame.new(1.45, 2.95, -0.7), color = suitGrey, shape = Enum.PartType.Ball, collide = false },
		-- Шлем с кольцом воротника, золотым визором и фонариками
		{ name = "NeckRing", size = Vector3.new(0.2, 1.32, 1.32), offset = CFrame.new(0, 4.92, 0) * CFrame.Angles(0, 0, rad(90)), color = RED, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Helmet", size = Vector3.new(1.56, 1.56, 1.56), offset = CFrame.new(0, 5.55, 0), color = WHITE, shape = Enum.PartType.Ball, collide = false },
		{ name = "VisorRim", size = Vector3.new(1.16, 0.9, 0.36), offset = CFrame.new(0, 5.58, -0.54), color = DARK_METAL, material = Enum.Material.Metal, sphere = true, collide = false },
		{ name = "Visor", size = Vector3.new(1.04, 0.78, 0.42), offset = CFrame.new(0, 5.58, -0.6), color = GOLD, material = Enum.Material.Metal, reflectance = 0.45, sphere = true, collide = false },
		{ name = "HeadLampL", size = Vector3.new(0.16, 0.18, 0.24), offset = CFrame.new(-0.74, 5.72, -0.18), color = hex("3BC6C1"), material = Enum.Material.Neon, collide = false },
		{ name = "HeadLampR", size = Vector3.new(0.16, 0.18, 0.24), offset = CFrame.new(0.74, 5.72, -0.18), color = hex("3BC6C1"), material = Enum.Material.Neon, collide = false },
		-- Флагшток с перекладиной и флагом
		{ name = "Pole", size = Vector3.new(5.4, 0.15, 0.15), offset = CFrame.new(1.45, 3.35, -0.7) * CFrame.Angles(0, 0, rad(90)), color = STEEL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PoleTip", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(1.45, 6.1, -0.7), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball, collide = false },
		{ name = "Crossbar", size = Vector3.new(1.9, 0.08, 0.08), offset = CFrame.new(2.38, 5.98, -0.7), color = STEEL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Flag", size = Vector3.new(1.85, 1.1, 0.06), offset = CFrame.new(2.38, 5.4, -0.7), color = navy, collide = false },
		{ name = "FlagStripe", size = Vector3.new(1.85, 0.22, 0.07), offset = CFrame.new(2.38, 5.05, -0.7), color = RED, collide = false },
		{ name = "FlagStar", size = Vector3.new(0.46, 0.46, 0.08), offset = CFrame.new(2.38, 5.5, -0.7) * CFrame.Angles(0, 0, rad(45)), color = GOLD, collide = false },
	}
end
local ASTRONAUT_STUB: Stub = buildAstronautStub()

---------------------------------------------------------------- залы

local function sculptures(room: Room)
	local kit = room.kit
	-- Кайма пола из камня
	for _, z in { 51, 103 } do
		deco(room, "FloorBorder", Vector3.new(84, 0.04, 1.5), CFrame.new(-52, 0.02, z), STONE, Enum.Material.Marble)
	end
	for _, x in { -93, -11 } do
		deco(room, "FloorBorder", Vector3.new(1.5, 0.04, room.r.maxZ - room.r.minZ - 6), CFrame.new(x, 0.02, 77), STONE, Enum.Material.Marble)
	end
	-- Фонтан посередине под стеклянным потолком, колонны вокруг, банкетки смотрят на фонтан
	placeAt(room, Models.Fountain, -52, 0, 77, 0, 1, FOUNTAIN_STUB):SetAttribute("MapObstacle", true)
	for _, spot in { { -66, 63 }, { -66, 91 }, { -38, 63 }, { -38, 91 } } do
		columnAt(room, spot[1], spot[2], MARBLE, Enum.Material.Marble)
	end
	for _, x in { -66, -38 } do
		placeAt(room, Models.Bench, x, 0, 77, 1, 0, kit.bench)
	end
	-- Две большие статуи у дальней стены, между ними картина
	for _, z in { 62, 92 } do
		placeAt(room, Models.Statue, -92, 0, z, 1, 0, STATUE_STUB):SetAttribute("MapObstacle", true)
	end
	painting(room, "W", 77, 8, 10, 6)
	hallTitle(room, "SCULPTURES", hex("5A4E3C"), MARBLE)
	-- Рельефы на длинных стенах: каменная плита с медальоном
	for _, side in { "N", "S" } do
		local point, facing = wallPoint(room, side, -52, 7)
		local look = CFrame.lookAt(point, point + facing)
		kit.decor("Relief", Vector3.new(8, 4, 0.3), look * CFrame.new(0, 0, -0.15), STONE, Enum.Material.Marble)
		kit.decor("ReliefInner", Vector3.new(7.2, 3.2, 0.2), look * CFrame.new(0, 0, -0.3), MARBLE, Enum.Material.Marble)
		local medal = kit.decor("ReliefMedal", Vector3.new(0.3, 2.4, 2.4), look * CFrame.new(0, 0, -0.45) * CFrame.Angles(0, rad(90), 0), STONE, Enum.Material.Marble)
		medal.Shape = Enum.PartType.Cylinder
		for _, x in { -2.6, 2.6 } do
			kit.decor("ReliefFigure", Vector3.new(0.8, 2.2, 0.25), look * CFrame.new(x, -0.1, -0.45), STONE, Enum.Material.Marble)
		end
	end
	chandelierAt(room, -82, 77)
	chandelierAt(room, -22, 77)
	for _, spot in { { -93, 51 }, { -93, 103 }, { -11, 103 }, { -11, 51 } } do -- у восточной стены посередине — дверь зала
		plantAt(room, spot[1], spot[2])
	end
	for _, x in { -80, -24 } do
		painting(room, "N", x, 7, 6, 4.5)
		painting(room, "S", x, 7, 6, 4.5)
	end
end

local function dinosaurs(room: Room)
	-- Скелет тираннозавра на каменном помосте посередине, голова к двери
	solid(room, "DinoPlatform", Vector3.new(25, 1.2, 9.5), CFrame.new(-52, 0.6, 77), hex("8A7F6A"), Enum.Material.Slate):SetAttribute("MapObstacle", true)
	deco(room, "DinoPlatformEdge", Vector3.new(25.6, 0.3, 10.1), CFrame.new(-52, 1.25, 77), hex("6E6452"), Enum.Material.Slate)
	placeAt(room, Models.TRexSkeleton, -52, 1.2, 77, 1, 0, trexSkeletonStub(), false)
	infoStand(room, -52, 85, 0, 1, "TYRANNOSAURUS REX\n68 million years ago")
	-- Длинношеий у дальней стены, голова на север
	solid(room, "DinoPlatform", Vector3.new(9, 1, 28), CFrame.new(-84, 0.5, 77), hex("8A7F6A"), Enum.Material.Slate):SetAttribute("MapObstacle", true)
	placeAt(room, Models.LongneckSkeleton, -84, 1, 78, 0, -1, longneckSkeletonStub(), false)
	infoStand(room, -76, 94, 1, 0, "BRACHIOSAURUS\n150 million years ago")
	hallTitle(room, "DINOSAURS", hex("FFF3D6"), hex("6B4A2B"))
	-- Пальмы, папоротники и валуны (за валунами можно укрыться)
	local palm = palmStub()
	for _, spot in { { -91, 52 }, { -91, 102 }, { -13, 102 }, { -40, 52 } } do
		placeAt(room, Models.Palm, spot[1], 0, spot[2], 0, 1, palm)
	end
	for _, spot in { { -64, 71 }, { -40, 83 }, { -88, 62 }, { -79, 92 }, { -14, 70 }, { -20, 92 }, { -70, 104 }, { -48, 50 } } do
		fern(room, spot[1], spot[2], 1)
	end
	boulder(room, -22, 72, 2.6)
	boulder(room, -22, 84, 2.2)
	boulder(room, -68, 51, 2)
	-- Раскоп: тёмный песок, кости, лопата и кисть за канатным ограждением
	deco(room, "DigPit", Vector3.new(9, 0.06, 6), CFrame.new(-80, 0.03, 53), hex("B8955C"), Enum.Material.Sand)
	for i, spot in { { -82.5, 52.5, 20 }, { -79, 54, -35 }, { -77.5, 52, 70 } } do
		local boneCf = CFrame.new(spot[1], 0.15, spot[2]) * CFrame.Angles(0, rad(spot[3]), 0)
		deco(room, "DigBone", Vector3.new(0.35, 0.35, 1.8 + i * 0.2), boneCf, BONE)
		local knob = deco(room, "DigBoneEnd", Vector3.new(0.55, 0.55, 0.55), boneCf * CFrame.new(0, 0, (0.9 + i * 0.1)), BONE_DARK)
		knob.Shape = Enum.PartType.Ball
	end
	deco(room, "Shovel", Vector3.new(0.15, 0.15, 3), CFrame.new(-76, 0.6, 55) * CFrame.Angles(rad(12), rad(30), 0), hex("7A5A3A"), Enum.Material.Wood)
	deco(room, "ShovelBlade", Vector3.new(0.7, 0.08, 0.9), CFrame.new(-75.3, 0.3, 56.2) * CFrame.Angles(0, rad(30), 0), STEEL, Enum.Material.Metal)
	for _, spot in { { -84.8, 49.6 }, { -75.2, 49.6 }, { -84.8, 56.4 }, { -75.2, 56.4 } } do
		deco(room, "RopePost", Vector3.new(0.25, 2.2, 0.25), CFrame.new(spot[1], 1.1, spot[2]), hex("6B4A2B"), Enum.Material.Wood)
	end
	for _, rope in { { -80, 56.4, 9.6, 0.12 }, { -84.8, 53, 0.12, 6.8 }, { -75.2, 53, 0.12, 6.8 } } do
		deco(room, "Rope", Vector3.new(rope[3], 0.12, rope[4]), CFrame.new(rope[1], 1.8, rope[2]), hex("C9A86A"), Enum.Material.Fabric)
	end
	chandelierAt(room, -30, 77)
	chandelierAt(room, -70, 66)
	for _, x in { -66, -36 } do
		painting(room, "N", x, 7, 6, 4.5)
		painting(room, "S", x, 7, 6, 4.5)
	end
end

local GEM_COLORS = { hex("E0245E"), hex("2E9BFF"), hex("3FD27F"), hex("B05CFF"), hex("FFD23F") }

local function jewelry(room: Room)
	local kit = room.kit
	-- Красная ковровая дорожка вдоль зала и от двери к ней
	local carpet = deco(room, "Carpet", Vector3.new(82, 0.05, 6), CFrame.new(-52, 0.025, 77), RED, Enum.Material.Fabric)
	for _, z in { -3.1, 3.1 } do
		kit.decor("CarpetEdge", Vector3.new(82, 0.06, 0.3), carpet.CFrame * CFrame.new(0, 0.005, z), GOLD, Enum.Material.Fabric)
	end
	-- Кусок дорожки от двери зала (восточная стена, z 74..82) к большой дорожке
	kit.decor("Carpet", Vector3.new(6, 0.05, 8), room.T * CFrame.new(-11, 0.026, 79), RED, Enum.Material.Fabric)
	for _, spot in { { -88, 62 }, { -88, 92 } } do
		columnAt(room, spot[1], spot[2], GOLD, Enum.Material.Metal)
	end
	-- Витрины вдоль длинных стен, в них сверкают камни (укрытия)
	local gem = 0
	for _, wall in { { z = 49.2, fz = 1 }, { z = 104.8, fz = -1 } } do
		for _, x in { -82, -56, -30 } do
			local case = placeAt(room, Models.DisplayCase, x, 0, wall.z, 0, wall.fz, kit.displayCase)
			case:SetAttribute("MapObstacle", true)
			local base = case:GetPivot()
			for i = -1, 1 do
				gem = gem % #GEM_COLORS + 1
				kit.decor("Gem", Vector3.new(0.45, 0.45, 0.45), base * CFrame.new(i * 1.1, 2.95, 0) * CFrame.Angles(rad(45), rad(45), 0), GEM_COLORS[gem], Enum.Material.Neon)
			end
			local ring = kit.decor("Ring", Vector3.new(0.1, 0.55, 0.55), base * CFrame.new(1.1, 2.75, 0.3) * CFrame.Angles(0, 0, rad(90)), GOLD, Enum.Material.Metal)
			ring.Shape = Enum.PartType.Cylinder
		end
	end
	-- Круглая дверь хранилища на дальней стене
	local point, facing = wallPoint(room, "W", 77, 7)
	local look = CFrame.lookAt(point, point + facing) * CFrame.Angles(0, rad(90), 0) -- ось цилиндра — от стены
	local function disc(name: string, depth: number, diameter: number, offset: number, color: Color3, material: Enum.Material)
		local part = kit.decor(name, Vector3.new(depth, diameter, diameter), look * CFrame.new(offset, 0, 0), color, material)
		part.Shape = Enum.PartType.Cylinder
	end
	disc("VaultFrame", 0.6, 11.4, 0.3, STEEL, Enum.Material.Metal)
	disc("VaultRing", 0.7, 9.8, 0.4, GOLD, Enum.Material.Metal)
	disc("VaultDoor", 0.8, 8.8, 0.5, hex("6E7686"), Enum.Material.DiamondPlate)
	disc("VaultHub", 1.4, 1.8, 0.8, GOLD, Enum.Material.Metal)
	local face = CFrame.lookAt(point, point + facing)
	for i = 0, 2 do
		kit.decor("VaultSpoke", Vector3.new(0.35, 6.2, 0.35), face * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, 0, i * math.pi / 3), GOLD, Enum.Material.Metal)
	end
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local bolt = kit.decor("VaultBolt", Vector3.new(1, 0.55, 0.55), face * CFrame.new(math.cos(angle) * 5.1, math.sin(angle) * 5.1, -0.6) * CFrame.Angles(0, rad(90), 0), GOLD, Enum.Material.Metal)
		bolt.Shape = Enum.PartType.Cylinder
	end
	hallTitle(room, "JEWELRY", GOLD, hex("2A1A3D"))
	chandelierAt(room, -70, 77)
	chandelierAt(room, -34, 77)
	for _, spot in { { -11, 103 }, { -11, 51 } } do -- у восточной стены посередине — дверь зала
		plantAt(room, spot[1], spot[2])
	end
	for _, x in { -68, -36 } do
		painting(room, "N", x, 7.5, 5, 3.6)
	end
	for _, x in { -60, -30 } do
		painting(room, "S", x, 7.5, 5, 3.6)
	end
end

-- Звёздное небо на потолке: точки-звёзды и туманности светятся сами (видно и ночью).
local function starCeiling(room: Room, slab: BasePart)
	local kit = room.kit
	local gui = kit.surfaceGui(slab, Enum.NormalId.Bottom, 6, 0)
	local sky = kit.guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), hex("0B1024"), 1)
	-- Туманности: несколько полупрозрачных кругов друг в друге — мягкое свечение без резкого края
	for _, nebula in { { 0.25, 0.3, 0.4, "6A3FB5" }, { 0.7, 0.68, 0.42, "2E5FB8" }, { 0.58, 0.14, 0.26, "B53F8E" } } do
		for layer = 1, 4 do
			local scale = nebula[3] * (1.25 - layer * 0.22)
			local cloud = kit.guiFrame(sky, UDim2.fromScale(nebula[1], nebula[2]), UDim2.fromScale(scale, scale * 0.7), hex(nebula[4]), 2)
			cloud.AnchorPoint = Vector2.new(0.5, 0.5)
			cloud.BackgroundTransparency = 0.86
			kit.corner(cloud, UDim.new(0.5, 0))
		end
	end
	local random = Random.new(7)
	local colors = { hex("FFFFFF"), hex("CFE8FF"), hex("FFF3C4"), hex("FFFFFF") }
	for _ = 1, 170 do
		local size = random:NextInteger(2, 5)
		local star = kit.guiFrame(sky, UDim2.fromScale(random:NextNumber(), random:NextNumber()), UDim2.fromOffset(size, size), colors[random:NextInteger(1, #colors)], 3)
		kit.corner(star, UDim.new(0.5, 0))
	end
end

-- Иллюминатор на стене: металлическая рама, за стеклом звёзды и планета.
local function porthole(room: Room, side: string, along: number)
	local kit = room.kit
	local point, facing = wallPoint(room, side, along, 9)
	local look = CFrame.lookAt(point, point + facing)
	local rim = kit.decor("PortholeRim", Vector3.new(0.5, 5, 5), look * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, rad(90), 0), STEEL, Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	local window = kit.decor("PortholeView", Vector3.new(4.2, 4.2, 0.1), look * CFrame.new(0, 0, -0.5), hex("0B1024"))
	local gui = kit.surfaceGui(window, Enum.NormalId.Front, 30, 0)
	local view = kit.guiFrame(gui, UDim2.new(), UDim2.fromScale(1, 1), hex("0B1024"), 1)
	kit.corner(view, UDim.new(0.5, 0))
	view.ClipsDescendants = true
	local random = Random.new(math.floor(along * 10))
	for _ = 1, 18 do
		local star = kit.guiFrame(view, UDim2.fromScale(random:NextNumber(), random:NextNumber()), UDim2.fromOffset(3, 3), hex("FFFFFF"), 2)
		kit.corner(star, UDim.new(0.5, 0))
	end
	local planet = kit.guiFrame(view, UDim2.fromScale(0.55, 0.5), UDim2.fromScale(0.45, 0.45), if along > -50 then hex("2E6FD8") else hex("C1440E"), 3)
	kit.corner(planet, UDim.new(0.5, 0))
end

-- Планета без кольца: шар, «материки» и полосы.
local function planet(room: Room, x: number, y: number, z: number, diameter: number, color: Color3, spots: { { number } }, spotColor: Color3)
	local kit = room.kit
	local center = room.cf(CFrame.new(x, y, z))
	local body = kit.decor("Planet", Vector3.new(diameter, diameter, diameter), center, color)
	body.Shape = Enum.PartType.Ball
	for _, spot in spots do
		local direction = Vector3.new(spot[1], spot[2], spot[3]).Unit
		local size = diameter * spot[4]
		local bump = kit.decor("PlanetSpot", Vector3.new(size, size, size), center * CFrame.new(direction * (diameter / 2 - size * 0.32)), spotColor)
		bump.Shape = Enum.PartType.Ball
	end
	-- Этап 5, блок F2: прозрачная дымка атмосферы чуть больше планеты
	if diameter >= 3 then
		local haze = kit.decor("Atmosphere", Vector3.new(diameter * 1.08, diameter * 1.08, diameter * 1.08), center, color:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.Glass)
		haze.Shape = Enum.PartType.Ball
		haze.Transparency = 0.82
		haze.CastShadow = false
	end
	kit.decor("Wire", Vector3.new(0.06, room.height - y - diameter / 2, 0.06), room.cf(CFrame.new(x, (room.height + y + diameter / 2) / 2, z)), STEEL, Enum.Material.Metal)
end

local function space(room: Room, ceilingSlabs: { Part })
	local kit = room.kit
	for _, slab in ceilingSlabs do
		starCeiling(room, slab)
	end
	local light = hex("CFE8FF")
	for _, spot in { { -70, 64 }, { -70, 90 }, { -34, 64 }, { -34, 90 } } do
		spotLight(room, spot[1], spot[2], light)
	end
	-- Светящиеся полосы на полу вдоль стен
	for _, z in { 49.6, 104.4 } do
		deco(room, "NeonStrip", Vector3.new(84, 0.06, 0.3), CFrame.new(-52, 0.03, z), kit.colors.Turquoise, Enum.Material.Neon)
	end
	for _, x in { -94.4, -9.6 } do
		deco(room, "NeonStrip", Vector3.new(0.3, 0.06, room.r.maxZ - room.r.minZ - 6), CFrame.new(x, 0.03, 77), kit.colors.Turquoise, Enum.Material.Neon)
	end
	-- Ракета на стартовом столе и космонавт с флагом у дальней стены
	placeAt(room, Models.Rocket, -84, 0, 62, 1, 0, rocketStub()):SetAttribute("MapObstacle", true)
	infoStand(room, -77, 68, 1, 0, "MOON ROCKET\nmodel 1 : 10")
	placeAt(room, Models.Astronaut, -86, 0, 92, 1, 0, ASTRONAUT_STUB)
	hallTitle(room, "SPACE", kit.colors.Turquoise, hex("0B1024"))
	-- Планеты под потолком: Сатурн посередине, вокруг Земля с Луной, Марс, Юпитер, Нептун
	placeAt(room, Models.Planet, -50, 13.5, 77, 0, 1, PLANET_STUB, false)
	kit.decor("Wire", Vector3.new(0.06, room.height - 17, 0.06), room.cf(CFrame.new(-50, (room.height + 17) / 2, 77)), STEEL, Enum.Material.Metal)
	planet(room, -24, 14, 66, 5, hex("2E6FD8"), { { 1, 0.3, 0.2, 0.36 }, { -0.6, -0.2, 0.8, 0.32 }, { 0.2, -0.4, -1, 0.3 }, { 0, 1, 0, 0.3 } }, hex("3FA34D"))
	planet(room, -20, 15.5, 62, 1.3, hex("B8B8BC"), {}, hex("FFFFFF"))
	planet(room, -70, 15, 93, 3.8, hex("C1440E"), { { 0, 1, 0, 0.35 } }, hex("F2F4F7"))
	planet(room, -70, 14.5, 62, 6, hex("D8A56B"), { { 0.8, -0.2, 0.6, 0.22 } }, hex("C0603A"))
	planet(room, -30, 16, 94, 3, hex("4B70DD"), {}, hex("FFFFFF"))
	for _, spot in { { "N", -70 }, { "N", -34 }, { "S", -70 }, { "S", -34 } } do
		porthole(room, spot[1], spot[2])
	end
end

local BUILDERS: { [string]: (Room, { Part }) -> () } = {
	Sculptures = function(room: Room)
		sculptures(room)
	end,
	Dinosaurs = function(room: Room)
		dinosaurs(room)
	end,
	Jewelry = function(room: Room)
		jewelry(room)
	end,
	Space = space,
}

-- Украшает зал hall. T — поворот зала, r — его пол в координатах зала Скульптур, ceilingSlabs — плиты потолка (мир).
function MapDecor.hall(kit: Kit, hall: string, T: CFrame, r: Rect, ceilingSlabs: { Part })
	local builder = BUILDERS[hall]
	if builder then
		builder(newRoom(kit, T, r), ceilingSlabs)
	end
end

---------------------------------------------------------------- края центра (этап 5, блок E)

-- Кадка с деревом (R3): ящик с филёнками и латунными пилястрами, изогнутый ствол с корнями, пышная крона с ягодами. Низ по центру.
local function buildPlanterTreeStub(): Stub
	local woodDark = hex("4A2B16")
	local brassDark = hex("C9922A")
	local list: Stub = {
		{ name = "Base", size = Vector3.new(2.84, 0.22, 2.84), offset = CFrame.new(0, 0.11, 0), color = hex("364054"), material = Enum.Material.Slate },
		{ name = "Box", size = Vector3.new(2.6, 1.58, 2.6), offset = CFrame.new(0, 1.01, 0), color = hex("5A3A22"), material = Enum.Material.WoodPlanks },
		{ name = "Rim", size = Vector3.new(2.86, 0.2, 2.86), offset = CFrame.new(0, 1.88, 0), color = GOLD, material = Enum.Material.Metal },
		{ name = "RimStep", size = Vector3.new(2.68, 0.1, 2.68), offset = CFrame.new(0, 1.74, 0), color = brassDark, material = Enum.Material.Metal, collide = false },
		{ name = "Soil", size = Vector3.new(2.34, 0.12, 2.34), offset = CFrame.new(0, 1.92, 0), color = hex("3B2A1E"), material = Enum.Material.Ground, collide = false },
		{ name = "Plaque", size = Vector3.new(0.84, 0.3, 0.06), offset = CFrame.new(0, 0.96, -1.35), color = GOLD, material = Enum.Material.Metal, collide = false },
		-- Ствол в два колена, ветки и корневые наплывы
		{ name = "TrunkBase", size = Vector3.new(1.1, 0.72, 0.72), offset = CFrame.new(0, 2.45, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("6B4A2E"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "TrunkMid", size = Vector3.new(2.1, 0.56, 0.56), offset = CFrame.new(0.08, 3.85, 0.05) * CFrame.Angles(rad(-4), 0, rad(84)), color = hex("6B4A2E"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "TrunkTop", size = Vector3.new(1.8, 0.44, 0.44), offset = CFrame.new(0.14, 5.45, -0.04) * CFrame.Angles(rad(6), 0, rad(94)), color = hex("7A5638"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "BranchR", size = Vector3.new(1.5, 0.24, 0.24), offset = CFrame.new(0.68, 5.7, 0.24) * CFrame.Angles(rad(18), rad(-15), rad(42)), color = hex("6B4A2E"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "BranchL", size = Vector3.new(1.4, 0.22, 0.22), offset = CFrame.new(-0.56, 5.45, -0.28) * CFrame.Angles(rad(-20), rad(15), rad(132)), color = hex("6B4A2E"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "BranchF", size = Vector3.new(1.2, 0.2, 0.2), offset = CFrame.new(0.05, 5.85, -0.52) * CFrame.Angles(rad(52), 0, rad(90)), color = hex("6B4A2E"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, collide = false },
	}
	for i = 0, 3 do
		local rot = CFrame.Angles(0, i * math.pi / 2, 0)
		table.insert(list, { name = "Panel", size = Vector3.new(1.85, 1.05, 0.06), offset = rot * CFrame.new(0, 1.01, -1.31), color = woodDark, material = Enum.Material.Wood, collide = false })
		table.insert(list, { name = "Root", size = Vector3.new(0.24, 0.36, 0.55), offset = rot * CFrame.new(0, 2.08, -0.45), color = hex("5A3A22"), material = Enum.Material.Wood, wedge = true, collide = false })
		table.insert(list, { name = "Pebble", size = Vector3.new(0.36, 0.22, 0.32), offset = rot * CFrame.new(0.7, 2.02, -0.55), color = STONE, material = Enum.Material.Slate, sphere = true, collide = false })
	end
	for _, x in { -1.32, 1.32 } do
		for _, z in { -1.32, 1.32 } do
			table.insert(list, { name = "Corner", size = Vector3.new(0.22, 1.58, 0.22), offset = CFrame.new(x, 1.01, z), color = GOLD, material = Enum.Material.Metal, collide = false })
			table.insert(list, { name = "CornerCap", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(x, 2.02, z), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball, collide = false })
		end
	end
	for _, c in {
		{ x = 0, y = 6.9, z = 0, d = 3.9, col = LEAF },
		{ x = 1.0, y = 7.9, z = 0.45, d = 2.8, col = LEAF_DARK },
		{ x = -0.95, y = 7.6, z = -0.5, d = 2.6, col = hex("4FA352") },
		{ x = 0.2, y = 8.7, z = -0.25, d = 2.3, col = hex("5CE06E") },
		{ x = -0.35, y = 6.85, z = 1.15, d = 2.2, col = LEAF_DARK },
		{ x = 0.75, y = 6.75, z = -1.1, d = 2.1, col = hex("4FA352") },
	} do
		table.insert(list, { name = "Crown", size = Vector3.new(c.d, c.d, c.d), offset = CFrame.new(c.x, c.y, c.z), color = c.col, material = Enum.Material.Grass, shape = Enum.PartType.Ball, collide = false })
	end
	for _, b in {
		{ x = 1.4, y = 7.2, z = -1.0, col = RED },
		{ x = -1.55, y = 7.85, z = 0.35, col = RED },
		{ x = 0.4, y = 6.4, z = -1.75, col = RED },
		{ x = -0.75, y = 8.4, z = -1.1, col = GOLD },
		{ x = 1.25, y = 8.5, z = 0.9, col = GOLD },
	} do
		table.insert(list, { name = "Berry", size = Vector3.new(0.28, 0.28, 0.28), offset = CFrame.new(b.x, b.y, b.z), color = b.col, shape = Enum.PartType.Ball, collide = false })
	end
	return list
end
local PLANTER_TREE_STUB: Stub = buildPlanterTreeStub()

-- Напольный светильник (R3): ступенчатое основание, точёная стойка, плиссированный абажур с рёбрами,
-- цепочка выключателя и лампочка Bulb (сохранена для dayLight и PointLight). Низ по центру.
local function buildFloorLampStub(): Stub
	local brassDark = hex("C9922A")
	local list: Stub = {
		{ name = "Base", size = Vector3.new(0.24, 1.5, 1.5), offset = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, rad(90)), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "BaseStep", size = Vector3.new(0.18, 1.15, 1.15), offset = CFrame.new(0, 0.32, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "BaseNeck", size = Vector3.new(0.32, 0.56, 0.56), offset = CFrame.new(0, 0.54, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Pole", size = Vector3.new(5.5, 0.22, 0.22), offset = CFrame.new(0, 3.4, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PoleNodeLow", size = Vector3.new(0.24, 0.4, 0.4), offset = CFrame.new(0, 2.0, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PoleNodeHigh", size = Vector3.new(0.24, 0.4, 0.4), offset = CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Socket", size = Vector3.new(0.34, 0.34, 0.34), offset = CFrame.new(0, 5.95, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Shade", size = Vector3.new(1.36, 1.78, 1.78), offset = CFrame.new(0, 6.55, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("F3E3C3"), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder, transparency = 0.15, collide = false },
		{ name = "ShadeTrimBot", size = Vector3.new(0.1, 1.88, 1.88), offset = CFrame.new(0, 5.88, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "ShadeTrimTop", size = Vector3.new(0.1, 1.82, 1.82), offset = CFrame.new(0, 7.22, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "FinialBase", size = Vector3.new(0.18, 0.38, 0.38), offset = CFrame.new(0, 7.34, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Finial", size = Vector3.new(0.28, 0.28, 0.28), offset = CFrame.new(0, 7.52, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball, collide = false },
		{ name = "PullChain", size = Vector3.new(0.65, 0.04, 0.04), offset = CFrame.new(0.45, 5.55, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "PullBead", size = Vector3.new(0.16, 0.16, 0.16), offset = CFrame.new(0.45, 5.2, 0), color = RED, shape = Enum.PartType.Ball, collide = false },
		{ name = "Bulb", size = Vector3.new(0.62, 0.62, 0.62), offset = CFrame.new(0, 6.4, 0), color = hex("FFE7B8"), material = Enum.Material.Neon, shape = Enum.PartType.Ball, collide = false },
	}
	for i = 0, 3 do
		local rot = CFrame.Angles(0, i * math.pi / 2, 0)
		table.insert(list, { name = "ShadeRib", size = Vector3.new(0.05, 1.32, 0.06), offset = rot * CFrame.new(0, 6.55, -0.9), color = brassDark, material = Enum.Material.Metal, collide = false })
	end
	return list
end
local FLOOR_LAMP_STUB: Stub = buildFloorLampStub()

-- Столбики с провисающим бархатным канатом (R3): тяжёлые круглые основания, точёные стойки с шарами и дуга каната.
function MapDecor.barrierStub(halfSpan: number): Stub
	local brassDark = hex("C9922A")
	local list: Stub = {}
	for _, s in { -1, 1 } do
		local x = s * halfSpan
		table.insert(list, { name = "Base", size = Vector3.new(0.16, 1.0, 1.0), offset = CFrame.new(x, 0.08, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder })
		table.insert(list, { name = "BaseBell", size = Vector3.new(0.24, 0.62, 0.62), offset = CFrame.new(x, 0.28, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "Post", size = Vector3.new(2.65, 0.28, 0.28), offset = CFrame.new(x, 1.62, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder })
		table.insert(list, { name = "PostCollar", size = Vector3.new(0.14, 0.38, 0.38), offset = CFrame.new(x, 2.48, 0) * CFrame.Angles(0, 0, rad(90)), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
		table.insert(list, { name = "Finial", size = Vector3.new(0.42, 0.42, 0.42), offset = CFrame.new(x, 3.04, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball, collide = false })
		table.insert(list, { name = "Clasp", size = Vector3.new(0.2, 0.26, 0.26), offset = CFrame.new(x - s * 0.18, 2.48, 0), color = brassDark, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false })
	end
	local span = math.max(0.4, halfSpan - 0.16)
	local segments = 5
	for i = 1, segments do
		local t0 = -1 + (i - 1) * (2 / segments)
		local t1 = -1 + i * (2 / segments)
		local p0 = Vector3.new(t0 * span, 2.48 - 0.4 * (1 - t0 * t0), 0)
		local p1 = Vector3.new(t1 * span, 2.48 - 0.4 * (1 - t1 * t1), 0)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 0.08
		table.insert(list, {
			name = "Rope",
			size = Vector3.new(len, 0.2, 0.2),
			offset = CFrame.lookAt(mid, p1) * CFrame.Angles(0, rad(90), 0),
			color = RED,
			material = Enum.Material.Fabric,
			shape = Enum.PartType.Cylinder,
			collide = false,
		})
	end
	return list
end

-- Столбики с канатом перед статуей (шире, чем у Моны Лизы: под постамент 3.4).
local ROPE_STUB: Stub = MapDecor.barrierStub(2.3)

-- Что лежит в витринах у стен центра (по кругу) и что написано на табличке.
local CASE_ITEMS = {
	{ kind = "Coins", label = "ROMAN COINS\n2nd century" },
	{ kind = "Scrolls", label = "ANCIENT SCROLLS\nEgypt" },
	{ kind = "Mask", label = "GOLDEN MASK\nSouth America" },
	{ kind = "Jewels", label = "ROYAL JEWELS\n17th century" },
}
local STATUE_LABELS = { "THE THINKER\nMarble", "GODDESS OF WISDOM\nMarble", "THE ATHLETE\nMarble", "THE POET\nMarble" }
local BANNERS = {
	{ text = "ANCIENT\nEGYPT", color = hex("1E4E79") },
	{ text = "THE\nRENAISSANCE", color = hex("7A1E24") },
	{ text = "GOLDEN\nAGE", color = hex("6B4A12") },
	{ text = "TREASURES\nOF ROME", color = hex("3D2A5C") },
	{ text = "MASTERS\nOF LIGHT", color = hex("1F5C4A") },
	{ text = "THE SILK\nROAD", color = hex("8A3A12") },
}

-- Точка на полу у стены центра: side — "N" (z = minZ), "S", "W" (x = minX), "E"; along — вдоль стены,
-- depth — на сколько от стены, y — высота. Второе — направление от стены в зал.
local function edgePoint(r: Rect, side: string, along: number, depth: number, y: number?): (Vector3, Vector3)
	local h = y or 0
	if side == "N" then
		return Vector3.new(along, h, r.minZ + depth), Vector3.new(0, 0, 1)
	elseif side == "S" then
		return Vector3.new(along, h, r.maxZ - depth), Vector3.new(0, 0, -1)
	elseif side == "W" then
		return Vector3.new(r.minX + depth, h, along), Vector3.new(1, 0, 0)
	end
	return Vector3.new(r.maxX - depth, h, along), Vector3.new(-1, 0, 0)
end

-- Наклонная табличка с описанием на передней стороне предмета. base — низ предмета, «перед» в −Z.
local function frontPlaque(kit: Kit, base: CFrame, y: number, z: number, text: string)
	local board = kit.decor("InfoPlaque", Vector3.new(1.9, 0.6, 0.08), base * CFrame.new(0, y, z) * CFrame.Angles(rad(-15), 0, 0), GOLD, Enum.Material.Metal)
	kit.textOn(board, Enum.NormalId.Front, text, hex("2A1A12"), 0)
end

-- Мелкие вещи под стеклом витрины. base — низ витрины (бархат на высоте 2.7).
local function fillCase(kit: Kit, base: CFrame, kind: string)
	if kind == "Coins" then
		for i, stack in { 3, 1, 2, 4 } do
			for level = 1, stack do
				local coin = kit.decor("Coin", Vector3.new(0.12, 0.55, 0.55), base * CFrame.new(-1.35 + (i - 1) * 0.9, 2.66 + level * 0.12, (i % 2) * 0.3 - 0.15) * CFrame.Angles(0, 0, rad(90)), GOLD, Enum.Material.Metal)
				coin.Shape = Enum.PartType.Cylinder
			end
		end
	elseif kind == "Scrolls" then
		for i, x in { -0.8, 0.9 } do
			local roll = kit.decor("Scroll", Vector3.new(1.5, 0.42, 0.42), base * CFrame.new(x, 2.95, (i - 1.5) * 0.6) * CFrame.Angles(0, rad(i * 12), 0), hex("E9D9B0"), Enum.Material.Fabric)
			roll.Shape = Enum.PartType.Cylinder
			for _, e in { -0.8, 0.8 } do
				local cap = kit.decor("ScrollRod", Vector3.new(0.14, 0.55, 0.55), roll.CFrame * CFrame.new(e, 0, 0), hex("6B4A2E"), Enum.Material.Wood)
				cap.Shape = Enum.PartType.Cylinder
			end
		end
	elseif kind == "Mask" then
		local face = base * CFrame.new(0, 3.45, 0.15) * CFrame.Angles(rad(-12), 0, 0)
		kit.decor("Mask", Vector3.new(1.1, 1.4, 0.3), face, GOLD, Enum.Material.Metal)
		for _, x in { -0.25, 0.25 } do
			kit.decor("MaskEye", Vector3.new(0.28, 0.14, 0.05), face * CFrame.new(x, 0.18, -0.16), hex("1A1A1A"))
		end
		kit.decor("MaskMouth", Vector3.new(0.4, 0.08, 0.05), face * CFrame.new(0, -0.35, -0.16), hex("1A1A1A"))
		kit.decor("MaskGem", Vector3.new(0.18, 0.18, 0.05), face * CFrame.new(0, 0.5, -0.17) * CFrame.Angles(0, 0, rad(45)), hex("2E9BFF"), Enum.Material.Neon)
		kit.decor("MaskStand", Vector3.new(0.15, 0.7, 0.15), base * CFrame.new(0, 2.95, 0.35), DARK_METAL, Enum.Material.Metal)
	else
		for i = -1, 1 do
			kit.decor("Gem", Vector3.new(0.4, 0.4, 0.4), base * CFrame.new(i * 1.1, 2.95, -0.2) * CFrame.Angles(rad(45), rad(45), 0), GEM_COLORS[i + 3], Enum.Material.Neon)
		end
		for _, side in { -1, 1 } do -- ожерелье: две золотые нити буквой V
			kit.decor("Necklace", Vector3.new(0.08, 0.08, 1.1), base * CFrame.new(side * 0.3, 2.72, 0.45) * CFrame.Angles(0, rad(side * 35), 0), GOLD, Enum.Material.Metal)
		end
		local ring = kit.decor("Ring", Vector3.new(0.1, 0.5, 0.5), base * CFrame.new(1.3, 2.95, 0.4) * CFrame.Angles(0, 0, rad(90)), GOLD, Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
	end
end

-- Баннер выставки высоко на стене (над головой): ткань с надписью, золотая перекладина и бахрома.
local function banner(kit: Kit, r: Rect, side: string, along: number, info: { text: string, color: Color3 })
	local point, facing = edgePoint(r, side, along, 0.15, 17)
	local look = CFrame.lookAt(point, point + facing)
	local cloth = kit.decor("BannerCloth", Vector3.new(4, 8, 0.1), look, info.color, Enum.Material.Fabric)
	kit.textOn(cloth, Enum.NormalId.Front, info.text, GOLD, 0)
	kit.decor("BannerRod", Vector3.new(4.8, 0.3, 0.3), look * CFrame.new(0, 4.1, 0), GOLD, Enum.Material.Metal)
	kit.decor("BannerFringe", Vector3.new(4, 0.35, 0.12), look * CFrame.new(0, -4.15, 0), GOLD, Enum.Material.Fabric)
end

-- Края центра 120 × 120 (этап 5, блок E): вдоль стен витрины с мелкими вещами и статуи (укрытия, MapObstacle,
-- их не крадут), скамейки, кадки с деревьями, напольные светильники, канаты, баннеры выставок и большие картины.
-- Свободно остаётся: 4 двери (±12 от середины стены), табличка CAMERA SPOT на южной (x = −14) и восточной
-- (z = 30) стенах, лестницы на балкон и площадки под ними (z от −50 до −18 у западной и восточной стен).
-- Всё стоит не дальше 6 стадов от стены: до кольца перегородок остаётся проход ~20 стадов.
function MapDecor.centerEdges(kit: Kit, r: Rect)
	local caseIndex, statueIndex = 0, 0
	local function displayCase(side: string, along: number)
		local position, facing = edgePoint(r, side, along, 2.5)
		local case = kit.place(Models.DisplayCase, CFrame.lookAt(position, position + facing), kit.displayCase)
		case:SetAttribute("MapObstacle", true)
		caseIndex += 1
		local item = CASE_ITEMS[(caseIndex - 1) % #CASE_ITEMS + 1]
		local base = case:GetPivot()
		fillCase(kit, base, item.kind)
		frontPlaque(kit, base, 1.6, -1.06, item.label)
	end
	local function statue(side: string, along: number)
		local position, facing = edgePoint(r, side, along, 2.7)
		local model = kit.place(Models.Statue, CFrame.lookAt(position, position + facing), STATUE_STUB)
		model:SetAttribute("MapObstacle", true)
		statueIndex += 1
		frontPlaque(kit, model:GetPivot(), 1.2, -1.56, STATUE_LABELS[(statueIndex - 1) % #STATUE_LABELS + 1])
		local ropeAt = edgePoint(r, side, along, 5.9)
		kit.place(Models.Barrier, CFrame.lookAt(ropeAt, ropeAt + facing), ROPE_STUB)
	end
	local function bench(side: string, along: number)
		local position, facing = edgePoint(r, side, along, 1.6)
		kit.place(Models.Bench, CFrame.lookAt(position, position + facing), kit.bench)
	end
	local function tree(side: string, along: number)
		local position, facing = edgePoint(r, side, along, 2)
		kit.place(Models.PlanterTree, CFrame.lookAt(position, position + facing), PLANTER_TREE_STUB)
	end
	local function lamp(side: string, along: number)
		local position, facing = edgePoint(r, side, along, 1.2)
		local model = kit.place(Models.FloorLamp, CFrame.lookAt(position, position + facing), FLOOR_LAMP_STUB)
		local bulb = model:FindFirstChild("Bulb", true)
		if bulb and bulb:IsA("BasePart") then -- днём горит, ночью гаснет, как люстры (MapBuilder.setDayLights)
			local settings = Config.Lighting.FloorLamp
			bulb:SetAttribute(kit.dayLight, true)
			local light = Instance.new("PointLight")
			light.Range = settings.Range
			light.Brightness = settings.Brightness
			light.Color = settings.Color
			light:SetAttribute(kit.dayLight, true)
			light.Parent = bulb
		end
	end
	local function bigPainting(side: string, along: number)
		local point, facing = edgePoint(r, side, along, 0, 17)
		kit.painting(point - facing * 0.5, facing, 12, 7)
	end

	-- Южная стена (z = maxZ): дверь посередине, CAMERA SPOT 1 на x = −14
	for _, s in { -1, 1 } do
		lamp("S", s * 49)
		displayCase("S", s * 40)
		statue("S", s * 31)
		displayCase("S", s * 22)
		bigPainting("S", s * 45)
	end
	tree("S", 16)
	-- Западная и восточная стены: дверь посередине, у северного края — лестница на балкон
	for _, side in { "W", "E" } do
		tree(side, -15)
		displayCase(side, 21)
		displayCase(side, 46)
		lamp(side, 51.5)
		bigPainting(side, 46)
	end
	statue("W", 30)
	bench("W", 38)
	statue("E", 39) -- на восточной стене z 26..34 свободно: табличка CAMERA SPOT 2
	-- Северная стена — под балконом (высота 11): витрины, статуи, скамейки, лампы
	for _, s in { -1, 1 } do
		bench("N", s * 20)
		displayCase("N", s * 30)
		lamp("N", s * 35)
		displayCase("N", s * 40)
		statue("N", s * 48)
	end
	-- Баннеры выставок высоко на стенах
	local spots = { { "S", -30 }, { "S", 30 }, { "W", 16 }, { "W", -36 }, { "E", 16 }, { "E", -36 } }
	for index, spot in spots do
		banner(kit, r, spot[1], spot[2], BANNERS[index])
	end
end

return MapDecor
