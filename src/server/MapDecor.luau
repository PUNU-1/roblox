-- Украшения залов за деньги: свет, растения, картины и большие украшения каждого зала.
-- Помощники (стены, колонны, люстры, картины) живут в MapBuilder и приходят сюда набором Kit.
-- Каждый зал описан в координатах зала Скульптур (k = 0): x от −96 до −8, z от 48 до 106,
-- дверь — в восточной стене (x = −8) у северного края (z от 52 до 60). Остальные залы повёрнуты (T).

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))

local hex = Color3.fromHex

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
}

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

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

local function newRoom(kit: Kit, T: CFrame, r: Rect): Room
	return {
		kit = kit,
		T = T,
		r = r,
		height = kit.hallHeight,
		at = function(x: number, y: number, z: number): Vector3
			return T * Vector3.new(x, y, z)
		end,
		cf = function(cframe: CFrame): CFrame
			return T * cframe
		end,
		dir = function(x: number, z: number): Vector3
			return T:VectorToWorldSpace(Vector3.new(x, 0, z))
		end,
	}
end

-- Картина на стене зала: side — "N" (z = minZ), "S" (z = maxZ), "W" (x = minX), "E" (x = maxX).
local function painting(room: Room, side: string, along: number, y: number, width: number, height: number)
	local r = room.r
	local point, facing
	if side == "N" then
		point, facing = Vector3.new(along, y, r.minZ - 0.5), Vector3.new(0, 0, 1)
	elseif side == "S" then
		point, facing = Vector3.new(along, y, r.maxZ + 0.5), Vector3.new(0, 0, -1)
	elseif side == "W" then
		point, facing = Vector3.new(r.minX - 0.5, y, along), Vector3.new(1, 0, 0)
	else
		point, facing = Vector3.new(r.maxX + 0.5, y, along), Vector3.new(-1, 0, 0)
	end
	room.kit.painting(room.T * point, room.T:VectorToWorldSpace(facing), width, height)
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

-- Потолочный светильник-диск (горит только днём): для зала Космоса вместо люстр.
local function spotLight(room: Room, x: number, z: number, color: Color3)
	local kit = room.kit
	local y = room.height - 0.25
	local disc = kit.decor("CeilingSpot", Vector3.new(0.3, 3, 3), room.cf(CFrame.new(x, y, z)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon)
	disc.Shape = Enum.PartType.Cylinder
	disc:SetAttribute(kit.dayLight, true)
	kit.decor("CeilingSpotRim", Vector3.new(0.25, 3.6, 3.6), room.cf(CFrame.new(x, y + 0.05, z)) * CFrame.Angles(0, 0, math.rad(90)), hex("3A4250"), Enum.Material.Metal).Shape =
		Enum.PartType.Cylinder
	local light = Instance.new("PointLight")
	light.Range = 34
	light.Brightness = 1.2
	light.Color = color
	light.Shadows = true
	light:SetAttribute(kit.dayLight, true)
	light.Parent = disc
end

---------------------------------------------------------------- залы

local function sculptures(room: Room)
	local kit = room.kit
	-- Кайма пола из камня
	for _, z in { 51, 103 } do
		kit.decor("FloorBorder", Vector3.new(84, 0.04, 1.5), room.cf(CFrame.new(-52, 0.02, z)), kit.colors.Stone, Enum.Material.Marble)
	end
	for _, x in { -93, -11 } do
		kit.decor("FloorBorder", Vector3.new(1.5, 0.04, 52), room.cf(CFrame.new(x, 0.02, 77)), kit.colors.Stone, Enum.Material.Marble)
	end
	-- Колонны вокруг середины (под стеклянным потолком)
	for _, spot in { { -66, 63 }, { -66, 91 }, { -38, 63 }, { -38, 91 } } do
		columnAt(room, spot[1], spot[2], kit.colors.WhiteMarble, Enum.Material.Marble)
	end
	chandelierAt(room, -82, 77)
	chandelierAt(room, -22, 77)
	for _, spot in { { -93, 51 }, { -93, 103 }, { -11, 103 } } do
		plantAt(room, spot[1], spot[2])
	end
	for _, x in { -80, -24 } do
		painting(room, "N", x, 8, 6, 4.5)
		painting(room, "S", x, 8, 6, 4.5)
	end
end

local function dinosaurs(room: Room)
	chandelierAt(room, -30, 77)
	chandelierAt(room, -74, 77)
	for _, spot in { { -93, 51 }, { -93, 103 }, { -11, 103 } } do
		plantAt(room, spot[1], spot[2])
	end
end

local function jewelry(room: Room)
	local kit = room.kit
	-- Красная ковровая дорожка вдоль зала и от двери к ней
	kit.decor("Carpet", Vector3.new(82, 0.05, 6), room.cf(CFrame.new(-52, 0.025, 77)), kit.colors.Red, Enum.Material.Fabric)
	kit.decor("Carpet", Vector3.new(6, 0.05, 25), room.cf(CFrame.new(-14, 0.026, 64.5)), kit.colors.Red, Enum.Material.Fabric)
	for _, z in { 73.9, 80.1 } do
		kit.decor("CarpetEdge", Vector3.new(82, 0.06, 0.3), room.cf(CFrame.new(-52, 0.03, z)), kit.colors.Gold, Enum.Material.Fabric)
	end
	for _, spot in { { -88, 62 }, { -88, 92 } } do
		columnAt(room, spot[1], spot[2], kit.colors.Gold, Enum.Material.Metal)
	end
	chandelierAt(room, -70, 77)
	chandelierAt(room, -34, 77)
	for _, x in { -82, -56, -30 } do
		painting(room, "N", x, 9, 5, 3.6)
		painting(room, "S", x, 9, 5, 3.6)
	end
end

local function space(room: Room)
	local light = hex("CFE8FF")
	for _, spot in { { -70, 64 }, { -70, 90 }, { -34, 64 }, { -34, 90 } } do
		spotLight(room, spot[1], spot[2], light)
	end
end

local BUILDERS: { [string]: (Room) -> () } = {
	Sculptures = sculptures,
	Dinosaurs = dinosaurs,
	Jewelry = jewelry,
	Space = space,
}

-- Украшает зал hall. T — поворот зала, r — его пол в координатах зала Скульптур, ceilingSlabs — плиты потолка (мир).
function MapDecor.hall(kit: Kit, hall: string, T: CFrame, r: Rect, ceilingSlabs: { Part })
	local builder = BUILDERS[hall]
	if builder then
		builder(newRoom(kit, T, r))
	end
	local _ = ceilingSlabs
end

return MapDecor
