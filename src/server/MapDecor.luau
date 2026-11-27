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

-- Кость-отрезок от a до b (в координатах модели).
local function bone(list: Stub, a: Vector3, b: Vector3, thickness: number, color: Color3)
	local mid = (a + b) / 2
	table.insert(list, { name = "Bone", size = Vector3.new(thickness, thickness, (b - a).Magnitude), offset = CFrame.lookAt(mid, b), color = color, collide = false })
end

-- Позвоночник: отрезки по точкам, шарики-позвонки в сочленениях, отростки сверху (spines).
local function spine(list: Stub, points: { Vector3 }, thickness: number, spines: boolean)
	for i = 1, #points - 1 do
		bone(list, points[i], points[i + 1], thickness, BONE)
	end
	for i, point in points do
		local size = thickness * (if i % 2 == 0 then 1.35 else 1.15)
		table.insert(list, { name = "Vertebra", size = Vector3.new(size, size, size), offset = CFrame.new(point), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		if spines and i > 1 and i < #points then
			table.insert(list, { name = "Spine", size = Vector3.new(0.18, thickness * 1.1, 0.3), offset = CFrame.new(point + Vector3.new(0, thickness * 0.85, 0)), color = BONE, collide = false })
		end
	end
end

-- Пара рёбер с изгибом: от позвоночника наружу и вниз, потом внутрь.
local function ribs(list: Stub, z: number, top: number, width: number, depth: number)
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * 0.4, top, z)
		local b = Vector3.new(s * width, top - depth * 0.45, z + 0.15)
		local c = Vector3.new(s * width * 0.7, top - depth, z + 0.3)
		bone(list, a, b, 0.22, BONE)
		bone(list, b, c, 0.2, BONE)
	end
end

-- Металлическая подпорка от пола до скелета (как в настоящем музее).
local function supportRod(list: Stub, x: number, z: number, height: number)
	table.insert(list, { name = "Support", size = Vector3.new(0.22, height, 0.22), offset = CFrame.new(x, height / 2, z), color = DARK_METAL, material = Enum.Material.Metal, collide = false })
end

-- Скелет тираннозавра ~20 в длину и 12 в высоту. Голова — в −Z, низ по центру.
local function trexSkeletonStub(): Stub
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
	}, 0.75, true)
	for _, z in { -1.4, -2.4, -3.4, -4.4 } do
		ribs(list, z, 8, 1.55, 2.8)
	end
	table.insert(list, { name = "Pelvis", size = Vector3.new(2.2, 1.3, 1.9), offset = CFrame.new(0, 7.3, 0.5), color = BONE_DARK, collide = false })
	table.insert(list, { name = "PelvisBlade", size = Vector3.new(0.3, 1.6, 2.6), offset = CFrame.new(-1.1, 7.6, 0.5), color = BONE, collide = false })
	table.insert(list, { name = "PelvisBlade", size = Vector3.new(0.3, 1.6, 2.6), offset = CFrame.new(1.1, 7.6, 0.5), color = BONE, collide = false })
	for _, s in { -1, 1 } do
		-- Нога: бедро, голень, плюсна, три пальца
		local hip = Vector3.new(s * 1.3, 7.1, 0.5)
		local knee = Vector3.new(s * 1.45, 4.3, -0.9)
		local ankle = Vector3.new(s * 1.35, 1.5, 0.6)
		local heel = Vector3.new(s * 1.35, 0.45, 0.2)
		bone(list, hip, knee, 0.85, BONE)
		bone(list, knee, ankle, 0.6, BONE)
		bone(list, ankle, heel, 0.45, BONE_DARK)
		for i = -1, 1 do
			bone(list, heel, Vector3.new(s * 1.35 + i * 0.4, 0.15, -1.2), 0.22, BONE)
		end
		table.insert(list, { name = "Knee", size = Vector3.new(0.9, 0.9, 0.9), offset = CFrame.new(knee), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		-- Маленькие ручки
		local shoulder = Vector3.new(s * 0.85, 7.9, -4.8)
		local elbow = Vector3.new(s * 1.1, 7.1, -5.5)
		bone(list, shoulder, elbow, 0.26, BONE)
		bone(list, elbow, Vector3.new(s * 1, 7.25, -6.25), 0.2, BONE)
	end
	-- Череп с приоткрытой пастью
	table.insert(list, { name = "Cranium", size = Vector3.new(1.6, 1.5, 2.2), offset = CFrame.new(0, 10.3, -8.5), color = BONE, collide = false })
	table.insert(list, { name = "Snout", size = Vector3.new(1.2, 1, 1.9), offset = CFrame.new(0, 10, -10.4), color = BONE, collide = false })
	table.insert(list, { name = "Jaw", size = Vector3.new(1.25, 0.35, 3.1), offset = CFrame.new(0, 9.15, -9.6) * CFrame.Angles(rad(-12), 0, 0), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "Eye", size = Vector3.new(0.1, 0.5, 0.6), offset = CFrame.new(s * 0.81, 10.6, -8.3), color = hex("3A2E22"), collide = false })
		for i = 0, 3 do
			table.insert(list, { name = "Tooth", size = Vector3.new(0.12, 0.3, 0.12), offset = CFrame.new(s * 0.45, 9.38, -9.9 - i * 0.4) * CFrame.Angles(math.pi, 0, 0), color = hex("F7F3EA"), wedge = true, collide = false })
		end
	end
	supportRod(list, 0, -3, 7.8)
	supportRod(list, 0, 4, 6)
	return list
end

-- Скелет длинношеего динозавра ~26 в длину и 14 в высоту. Голова — в −Z, низ по центру.
local function longneckSkeletonStub(): Stub
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
	}, 0.8, true)
	for _, z in { -3, -1.5, 0, 1.5 } do
		ribs(list, z, 8.6, 2, 3.4)
	end
	table.insert(list, { name = "Pelvis", size = Vector3.new(2.4, 1.2, 1.8), offset = CFrame.new(0, 7.8, 3.2), color = BONE_DARK, collide = false })
	table.insert(list, { name = "Shoulders", size = Vector3.new(2.6, 1, 1.2), offset = CFrame.new(0, 8, -3.2), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		for _, leg in { { z = -3, knee = -3.3 }, { z = 3, knee = 2.5 } } do
			local top = Vector3.new(s * 1.5, 7.4, leg.z)
			local knee = Vector3.new(s * 1.65, 4.1, leg.knee)
			local foot = Vector3.new(s * 1.6, 0.7, leg.z + 0.1)
			bone(list, top, knee, 0.95, BONE)
			bone(list, knee, foot, 0.75, BONE)
			table.insert(list, { name = "Foot", size = Vector3.new(1.1, 0.45, 1.3), offset = CFrame.new(s * 1.6, 0.22, leg.z - 0.1), color = BONE_DARK, collide = false })
			table.insert(list, { name = "Knee", size = Vector3.new(1, 1, 1), offset = CFrame.new(knee), color = BONE_DARK, shape = Enum.PartType.Ball, collide = false })
		end
	end
	table.insert(list, { name = "Skull", size = Vector3.new(0.95, 0.8, 1.7), offset = CFrame.new(0, 13.7, -12), color = BONE, collide = false })
	table.insert(list, { name = "Jaw", size = Vector3.new(0.8, 0.25, 1.3), offset = CFrame.new(0, 13.15, -12.1) * CFrame.Angles(rad(-8), 0, 0), color = BONE_DARK, collide = false })
	for _, s in { -1, 1 } do
		table.insert(list, { name = "Eye", size = Vector3.new(0.08, 0.3, 0.35), offset = CFrame.new(s * 0.48, 13.85, -11.8), color = hex("3A2E22"), collide = false })
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

-- Фонтан со статуей: каменная чаша с водой, колонна, верхняя чаша, струи. Низ по центру.
local FOUNTAIN_STUB: Stub = {
	{ name = "Basin", size = Vector3.new(1.6, 9, 9), offset = CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
	{ name = "Rim", size = Vector3.new(0.3, 9.6, 9.6), offset = CFrame.new(0, 1.65, 0) * CFrame.Angles(0, 0, rad(90)), color = STONE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
	{ name = "Water", size = Vector3.new(0.1, 8.2, 8.2), offset = CFrame.new(0, 1.82, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("5FB8E0"), material = Enum.Material.Glass, transparency = 0.25, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Pillar", size = Vector3.new(2.6, 1.4, 1.4), offset = CFrame.new(0, 3.1, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
	{ name = "Bowl", size = Vector3.new(0.5, 4, 4), offset = CFrame.new(0, 4.4, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
	{ name = "BowlWater", size = Vector3.new(0.08, 3.4, 3.4), offset = CFrame.new(0, 4.66, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("5FB8E0"), material = Enum.Material.Glass, transparency = 0.25, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Urn", size = Vector3.new(0.9, 0.9, 0.9), offset = CFrame.new(0, 5.1, 0) * CFrame.Angles(0, 0, rad(90)), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Cylinder },
	{ name = "UrnBody", size = Vector3.new(1.1, 1.1, 1.1), offset = CFrame.new(0, 5.9, 0), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball },
	{ name = "UrnTop", size = Vector3.new(0.45, 0.45, 0.45), offset = CFrame.new(0, 6.6, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
	{ name = "Jet", size = Vector3.new(0.14, 0.14, 2.3), offset = CFrame.Angles(0, 0, 0) * CFrame.new(0, 3.4, -2.4) * CFrame.Angles(rad(55), 0, 0), color = hex("9AD7F0"), material = Enum.Material.Glass, transparency = 0.35, collide = false },
	{ name = "Jet", size = Vector3.new(0.14, 0.14, 2.3), offset = CFrame.Angles(0, rad(90), 0) * CFrame.new(0, 3.4, -2.4) * CFrame.Angles(rad(55), 0, 0), color = hex("9AD7F0"), material = Enum.Material.Glass, transparency = 0.35, collide = false },
	{ name = "Jet", size = Vector3.new(0.14, 0.14, 2.3), offset = CFrame.Angles(0, rad(180), 0) * CFrame.new(0, 3.4, -2.4) * CFrame.Angles(rad(55), 0, 0), color = hex("9AD7F0"), material = Enum.Material.Glass, transparency = 0.35, collide = false },
	{ name = "Jet", size = Vector3.new(0.14, 0.14, 2.3), offset = CFrame.Angles(0, rad(270), 0) * CFrame.new(0, 3.4, -2.4) * CFrame.Angles(rad(55), 0, 0), color = hex("9AD7F0"), material = Enum.Material.Glass, transparency = 0.35, collide = false },
}

-- Большая мраморная статуя на постаменте: фигура в тоге, правая рука поднимает венок. Перед в −Z.
local STATUE_STUB: Stub = {
	{ name = "Plinth", size = Vector3.new(3, 2, 3), offset = CFrame.new(0, 1, 0), color = STONE, material = Enum.Material.Marble },
	{ name = "PlinthCap", size = Vector3.new(3.4, 0.3, 3.4), offset = CFrame.new(0, 2.15, 0), color = MARBLE, material = Enum.Material.Marble },
	{ name = "LegL", size = Vector3.new(0.7, 2.6, 0.8), offset = CFrame.new(-0.45, 3.6, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "LegR", size = Vector3.new(0.7, 2.6, 0.8), offset = CFrame.new(0.45, 3.6, 0.1) * CFrame.Angles(rad(-6), 0, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "Robe", size = Vector3.new(1.9, 1.7, 1.1), offset = CFrame.new(0, 4.4, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "Torso", size = Vector3.new(1.8, 2, 1), offset = CFrame.new(0, 6, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "Drape", size = Vector3.new(2.2, 0.45, 1.15), offset = CFrame.new(0, 6.3, 0) * CFrame.Angles(0, 0, rad(28)), color = hex("E8E2D4"), material = Enum.Material.Marble, collide = false },
	{ name = "ArmL", size = Vector3.new(0.55, 2, 0.6), offset = CFrame.new(-1.2, 5.8, 0) * CFrame.Angles(0, 0, rad(-6)), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "ArmR", size = Vector3.new(0.55, 2.2, 0.6), offset = CFrame.new(1.3, 7.5, -0.15) * CFrame.Angles(rad(-10), 0, rad(-22)), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "Wreath", size = Vector3.new(0.15, 1, 1), offset = CFrame.new(1.75, 8.7, -0.35) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Neck", size = Vector3.new(0.5, 0.4, 0.5), offset = CFrame.new(0, 7.15, 0), color = MARBLE, material = Enum.Material.Marble, collide = false },
	{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), offset = CFrame.new(0, 7.75, 0), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
	{ name = "Hair", size = Vector3.new(1.15, 1.15, 1.15), offset = CFrame.new(0, 7.9, 0.12), color = hex("E8E2D4"), material = Enum.Material.Marble, shape = Enum.PartType.Ball, collide = false },
}

-- Сатурн: шар и наклонное кольцо с тёмной щелью. Точка привязки — центр планеты.
local PLANET_STUB: Stub = {
	{ name = "Planet", size = Vector3.new(7, 7, 7), offset = CFrame.identity, color = hex("E3C98B"), shape = Enum.PartType.Ball, collide = false },
	{ name = "Band", size = Vector3.new(7.05, 0.9, 7.05), offset = CFrame.new(0, 1.1, 0), color = hex("C9A86A"), sphere = true, collide = false },
	{ name = "Band", size = Vector3.new(7.05, 0.7, 7.05), offset = CFrame.new(0, -1.3, 0), color = hex("D6B67A"), sphere = true, collide = false },
	{ name = "RingInner", size = Vector3.new(0.13, 10, 10), offset = CFrame.Angles(rad(18), 0, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("8E7A52"), transparency = 0.3, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Ring", size = Vector3.new(0.12, 13, 13), offset = CFrame.Angles(rad(18), 0, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("D9C28A"), transparency = 0.15, shape = Enum.PartType.Cylinder, collide = false },
}

-- Большая ракета на стартовом столе и красная башня обслуживания. Низ по центру.
local function rocketStub(): Stub
	local function vertical(name: string, height: number, diameter: number, y: number, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
		return { name = name, size = Vector3.new(height, diameter, diameter), offset = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, rad(90)), color = color, material = material, shape = Enum.PartType.Cylinder }
	end
	local list: Stub = {
		vertical("Pad", 1, 9, 0.5, DARK_METAL, Enum.Material.Metal),
		vertical("PadRing", 0.05, 8.4, 1.02, hex("F2C230")),
		vertical("PadInner", 0.06, 7, 1.04, hex("2B2F3A")),
		vertical("Glow", 0.1, 1.8, 1.1, hex("FF8A3D"), Enum.Material.Neon),
		vertical("Engine", 1.2, 2.2, 1.75, hex("4A5060"), Enum.Material.Metal),
		vertical("BodyLow", 6, 3.2, 5.35, WHITE),
		vertical("BandLow", 0.6, 3.3, 3.2, RED),
		vertical("BandHigh", 0.5, 3.3, 7.9, RED),
		vertical("BodyHigh", 4, 2.8, 10.35, WHITE),
		vertical("Nose", 1.2, 2.2, 12.95, WHITE),
		vertical("NoseTop", 1, 1.4, 14, WHITE),
		{ name = "Tip", size = Vector3.new(0.9, 0.9, 0.9), offset = CFrame.new(0, 14.7, 0), color = RED, shape = Enum.PartType.Ball },
		{ name = "WindowRing", size = Vector3.new(0.12, 1.5, 1.5), offset = CFrame.new(0, 10.6, -1.38) * CFrame.Angles(0, rad(90), 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Window", size = Vector3.new(0.15, 1.15, 1.15), offset = CFrame.new(0, 10.6, -1.42) * CFrame.Angles(0, rad(90), 0), color = hex("7FE7FF"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder },
	}
	for i = 0, 3 do
		table.insert(list, { name = "Fin", size = Vector3.new(0.3, 3, 2.2), offset = CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 3.6, -2.5), color = RED, wedge = true })
		table.insert(list, { name = "Leg", size = Vector3.new(0.5, 1.4, 0.5), offset = CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 1.7, -1.9), color = DARK_METAL, material = Enum.Material.Metal })
	end
	-- Башня обслуживания позади ракеты
	for _, x in { -1.4, 1.4 } do
		table.insert(list, { name = "Tower", size = Vector3.new(0.5, 15, 0.5), offset = CFrame.new(x, 8.5, 3.6), color = RED, material = Enum.Material.Metal })
	end
	for y = 2.5, 14.5, 3 do
		table.insert(list, { name = "TowerBar", size = Vector3.new(3.3, 0.3, 0.3), offset = CFrame.new(0, y, 3.6), color = RED, material = Enum.Material.Metal })
	end
	table.insert(list, { name = "TowerArm", size = Vector3.new(0.3, 0.3, 2.3), offset = CFrame.new(0, 11.5, 2.4), color = DARK_METAL, material = Enum.Material.Metal })
	return list
end

-- Космонавт с флагом на подставке. Перед в −Z.
local ASTRONAUT_STUB: Stub = {
	{ name = "Base", size = Vector3.new(0.4, 3, 3), offset = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("1E2A44"), shape = Enum.PartType.Cylinder },
	{ name = "BootL", size = Vector3.new(0.8, 0.6, 1.1), offset = CFrame.new(-0.5, 0.7, -0.1), color = hex("A9B0BC"), collide = false },
	{ name = "BootR", size = Vector3.new(0.8, 0.6, 1.1), offset = CFrame.new(0.5, 0.7, -0.1), color = hex("A9B0BC"), collide = false },
	{ name = "LegL", size = Vector3.new(0.8, 1.8, 0.85), offset = CFrame.new(-0.5, 1.9, 0), color = WHITE, collide = false },
	{ name = "LegR", size = Vector3.new(0.8, 1.8, 0.85), offset = CFrame.new(0.5, 1.9, 0), color = WHITE, collide = false },
	{ name = "Torso", size = Vector3.new(2, 2, 1.2), offset = CFrame.new(0, 3.8, 0), color = WHITE, collide = false },
	{ name = "ChestPanel", size = Vector3.new(1, 0.6, 0.1), offset = CFrame.new(0, 4, -0.62), color = hex("1E2A44"), collide = false },
	{ name = "Button", size = Vector3.new(0.2, 0.2, 0.06), offset = CFrame.new(-0.25, 4, -0.68), color = RED, material = Enum.Material.Neon, collide = false },
	{ name = "Button", size = Vector3.new(0.2, 0.2, 0.06), offset = CFrame.new(0.05, 4, -0.68), color = hex("3FB56B"), material = Enum.Material.Neon, collide = false },
	{ name = "Button", size = Vector3.new(0.2, 0.2, 0.06), offset = CFrame.new(0.35, 4, -0.68), color = hex("F2C230"), material = Enum.Material.Neon, collide = false },
	{ name = "Backpack", size = Vector3.new(1.8, 2, 0.8), offset = CFrame.new(0, 3.9, 0.95), color = hex("C9CED6"), collide = false },
	{ name = "ArmL", size = Vector3.new(0.7, 1.9, 0.75), offset = CFrame.new(-1.4, 3.6, 0), color = WHITE, collide = false },
	{ name = "ArmR", size = Vector3.new(0.7, 1.9, 0.75), offset = CFrame.new(1.4, 3.8, -0.2) * CFrame.Angles(rad(-25), 0, 0), color = WHITE, collide = false },
	{ name = "GloveL", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(-1.45, 2.5, 0), color = hex("A9B0BC"), shape = Enum.PartType.Ball, collide = false },
	{ name = "GloveR", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(1.45, 2.95, -0.7), color = hex("A9B0BC"), shape = Enum.PartType.Ball, collide = false },
	{ name = "Helmet", size = Vector3.new(1.5, 1.5, 1.5), offset = CFrame.new(0, 5.5, 0), color = WHITE, shape = Enum.PartType.Ball, collide = false },
	{ name = "Visor", size = Vector3.new(1.05, 0.8, 0.4), offset = CFrame.new(0, 5.55, -0.58), color = GOLD, material = Enum.Material.Metal, sphere = true, collide = false },
	{ name = "Pole", size = Vector3.new(0.15, 5.2, 0.15), offset = CFrame.new(1.45, 3.4, -0.7), color = STEEL, material = Enum.Material.Metal, collide = false },
	{ name = "Flag", size = Vector3.new(1.8, 1.1, 0.06), offset = CFrame.new(2.35, 5.4, -0.7), color = hex("1E2A44"), collide = false },
	{ name = "FlagStar", size = Vector3.new(0.5, 0.5, 0.07), offset = CFrame.new(2.35, 5.4, -0.7) * CFrame.Angles(0, 0, rad(45)), color = GOLD, collide = false },
}

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

-- Кадка с деревом: деревянный ящик с золотым кантом, ствол и крона из шаров. Низ по центру.
local PLANTER_TREE_STUB: Stub = {
	{ name = "Box", size = Vector3.new(2.6, 1.8, 2.6), offset = CFrame.new(0, 0.9, 0), color = hex("5A3A22"), material = Enum.Material.WoodPlanks },
	{ name = "Rim", size = Vector3.new(2.8, 0.2, 2.8), offset = CFrame.new(0, 1.8, 0), color = GOLD, material = Enum.Material.Metal },
	{ name = "Soil", size = Vector3.new(2.3, 0.1, 2.3), offset = CFrame.new(0, 1.85, 0), color = hex("3B2A1E"), material = Enum.Material.Ground, collide = false },
	{ name = "Trunk", size = Vector3.new(0.5, 4.4, 0.5), offset = CFrame.new(0, 4, 0), color = hex("6B4A2E"), material = Enum.Material.Wood, collide = false },
	{ name = "Crown", size = Vector3.new(3.8, 3.8, 3.8), offset = CFrame.new(0, 6.8, 0), color = LEAF, material = Enum.Material.Grass, shape = Enum.PartType.Ball, collide = false },
	{ name = "Crown", size = Vector3.new(2.8, 2.8, 2.8), offset = CFrame.new(0.9, 7.9, 0.4), color = LEAF_DARK, material = Enum.Material.Grass, shape = Enum.PartType.Ball, collide = false },
	{ name = "Crown", size = Vector3.new(2.6, 2.6, 2.6), offset = CFrame.new(-0.9, 7.6, -0.5), color = hex("4FA352"), material = Enum.Material.Grass, shape = Enum.PartType.Ball, collide = false },
}

-- Напольный светильник: тяжёлое основание, золотая стойка, тканевый абажур, лампочка Bulb (игра вешает на неё свет). Низ по центру.
local FLOOR_LAMP_STUB: Stub = {
	{ name = "Base", size = Vector3.new(0.3, 1.4, 1.4), offset = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, rad(90)), color = DARK_METAL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	{ name = "Pole", size = Vector3.new(0.22, 5.8, 0.22), offset = CFrame.new(0, 3.2, 0), color = GOLD, material = Enum.Material.Metal, collide = false },
	{ name = "Shade", size = Vector3.new(1.3, 1.7, 1.7), offset = CFrame.new(0, 6.5, 0) * CFrame.Angles(0, 0, rad(90)), color = hex("F3E3C3"), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder, transparency = 0.15, collide = false },
	{ name = "ShadeTrim", size = Vector3.new(0.12, 1.8, 1.8), offset = CFrame.new(0, 5.85, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Bulb", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(0, 6.3, 0), color = hex("FFE7B8"), material = Enum.Material.Neon, shape = Enum.PartType.Ball, collide = false },
}

-- Столбики с канатом перед статуей (шире, чем у Моны Лизы: под постамент 3.4).
local ROPE_STUB: Stub = {
	{ name = "Post", size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(-2.3, 1.5, 0), color = GOLD, material = Enum.Material.Metal },
	{ name = "Post", size = Vector3.new(0.4, 3, 0.4), offset = CFrame.new(2.3, 1.5, 0), color = GOLD, material = Enum.Material.Metal },
	{ name = "Rope", size = Vector3.new(4.6, 0.25, 0.25), offset = CFrame.new(0, 2.5, 0), color = RED, material = Enum.Material.Fabric, collide = false },
}

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
