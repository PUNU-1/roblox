-- Экспонаты: Мона Лиза (главная — если её вынесли, игра окончена) и дешёвые экспонаты на постаментах.
-- Днём игроки покупают экспонаты: у каждого постамента свой экспонат, держишь F — хватает денег,
-- покупаешь сразу, нет — все деньги идут в полоску (вскладчину, Purchase.luau).
-- Ночью вор выбирает цель (чаще Мону Лизу), снимает её, несёт над головой.
-- Поймали — экспонат возвращается на место. Унёс дешёвый — экспонат пропадает, его надо купить заново.
-- Вор несёт копию экспоната, а настоящий прячется под картой: настоящий всегда закреплён и никогда
-- не приваривается к вору, поэтому после ареста точно встаёт на место.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local Purchase = require(Server:WaitForChild("Purchase"))
local ShopService = require(Server:WaitForChild("ShopService"))

local ExhibitConfig = Config.Exhibits

local ExhibitService = {}

ExhibitService.MainId = "MonaLisa" -- id Моны Лизы (у остальных — вид экспоната из Config.Exhibits.Kinds)

-- Вор начал снимать экспонат (exhibit). Сигнализация на Мону Лизу слушает его.
ExhibitService.StealStarted = Instance.new("BindableEvent")
-- Экспонат купили (exhibit): для него можно купить лазерную сетку.
ExhibitService.Added = Instance.new("BindableEvent")
-- Экспонат унесли насовсем (exhibit): его сетка пропадает.
ExhibitService.Lost = Instance.new("BindableEvent")

export type Exhibit = {
	id: string, -- вид экспоната (Config.Exhibits.Kinds) или "MonaLisa"
	title: string,
	model: PVInstance,
	home: CFrame,
	stand: Vector3, -- где встаёт вор, чтобы снять
	look: Vector3, -- куда смотрят туристы
	appeal: number, -- привлекательность для туристов
	isMain: boolean, -- Мона Лиза
	hall: string,
	carrier: Model?,
	stealer: Model?,
	carryCopy: PVInstance?, -- копия, которую несёт вор
}

type Slot = {
	pedestal: Model,
	hall: string,
	kind: string,
	title: string,
	price: number,
	appeal: number,
	paid: number,
	exhibit: Exhibit?,
	prompt: ProximityPrompt?,
	label: TextLabel?,
	billboard: BillboardGui?,
}

local GOLD = Color3.fromHex("F5C542")
local GOLD_BRIGHT = Color3.fromHex("FFE066")
local MARBLE = Color3.fromHex("FBF8F1")
local WOOD = Color3.fromHex("9E6230")
local BONE = Color3.fromHex("F5EBD4")
local BONE_DARK = Color3.fromHex("D9C59A")
local SOCKET = Color3.fromHex("36281C")
local STAND = Color3.fromHex("243B6B")
local NAVY = Color3.fromHex("243B6B")
local RUBY = Color3.fromHex("FF2E55")
local SAPPHIRE = Color3.fromHex("2E8BFF")
local EMERALD = Color3.fromHex("2EE88A")
local AMETHYST = Color3.fromHex("B55CFF")
local VELVET = Color3.fromHex("7A182B")

local function rad(degrees: number): number
	return math.rad(degrees)
end

-- Ровный ряд зубов на челюсти черепа (вперёд — в −Z).
local function teeth(y: number, zFrom: number, zTo: number, count: number): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {}
	for i = 0, count - 1 do
		local z = zFrom + (zTo - zFrom) * i / math.max(1, count - 1)
		for _, x in { -0.55, 0.55 } do
			table.insert(list, {
				name = "Tooth",
				size = Vector3.new(0.14, 0.3, 0.14),
				offset = CFrame.new(x, y, z) * CFrame.Angles(math.pi, 0, 0),
				color = Color3.fromHex("F7F3EA"),
				wedge = true,
			})
		end
	end
	return list
end

local function join(...: { ModelLibrary.StubPart }): { ModelLibrary.StubPart }
	local result: { ModelLibrary.StubPart } = {}
	for _, list in { ... } do
		for _, part in list do
			table.insert(result, part)
		end
	end
	return result
end

---------------------------------------------------------------- помощники для заглушек (этап 5, блок F2)

local Metal = Enum.Material.Metal
local Neon = Enum.Material.Neon
local Marble = Enum.Material.Marble
local GLASS = Color3.fromHex("DFF6FF")
local PAINT_DARK = Color3.fromHex("2B1B12")
local MARBLE_SHADE = Color3.fromHex("E8E0D0")

-- Стоячий цилиндр (у Roblox ось цилиндра — X, поэтому поворачиваем).
local function vcyl(name: string, height: number, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
	return { name = name, size = Vector3.new(height, diameter, diameter), offset = CFrame.new(position) * CFrame.Angles(0, 0, rad(90)), color = color, material = material, shape = Enum.PartType.Cylinder }
end

-- Круглая пластинка лицом вперёд (−Z): шайба, клапан, розетка.
local function disc(name: string, depth: number, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
	return { name = name, size = Vector3.new(depth, diameter, diameter), offset = CFrame.new(position) * CFrame.Angles(0, rad(90), 0), color = color, material = material, shape = Enum.PartType.Cylinder }
end

local function ball(name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
	return { name = name, size = Vector3.new(diameter, diameter, diameter), offset = CFrame.new(position), color = color, material = material, shape = Enum.PartType.Ball }
end

local function box(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
	return { name = name, size = size, offset = offset, color = color, material = material }
end

-- Палочка от a до b (не строго вертикальная): ручки, дужки, трещины.
local function rod(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): ModelLibrary.StubPart
	return { name = name, size = Vector3.new(thickness, thickness, (b - a).Magnitude), offset = CFrame.lookAt((a + b) / 2, b), color = color, material = material }
end

-- Та же деталь с другими свойствами (прозрачность, блеск, сквозь неё можно пройти).
local function with(part: ModelLibrary.StubPart, extra: { [string]: any }): ModelLibrary.StubPart
	local result: any = table.clone(part)
	for key, value in extra do
		result[key] = value
	end
	return result
end

-- Детали по кругу на высоте y: make получает точку на круге и направление наружу.
local function around(count: number, radius: number, y: number, phase: number, make: (Vector3, Vector3) -> ModelLibrary.StubPart): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {}
	for i = 0, count - 1 do
		local angle = phase + i * 2 * math.pi / count
		local outward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		table.insert(list, make(Vector3.new(0, y, 0) + outward * radius, outward))
	end
	return list
end

-- Деления циферблата: 12 штрихов, у 12, 3, 6 и 9 — длиннее.
local function clockTicks(center: Vector3, radius: number): { ModelLibrary.StubPart }
	local list: { ModelLibrary.StubPart } = {}
	for i = 0, 11 do
		local angle = i * math.pi / 6
		local long = i % 3 == 0
		local position = center + Vector3.new(math.sin(angle) * radius, math.cos(angle) * radius, 0)
		table.insert(list, box("Tick", Vector3.new(0.05, if long then 0.16 else 0.08, 0.03), CFrame.new(position) * CFrame.Angles(0, 0, -angle), NAVY, Metal))
	end
	return list
end

-- Стеклянный колпак-цилиндр с золотой крышкой (для мелких экспонатов).
local function glassCover(height: number, diameter: number, bottom: number): { ModelLibrary.StubPart }
	return {
		with(vcyl("Glass", height, diameter, Vector3.new(0, bottom + height / 2, 0), GLASS, Enum.Material.Glass), { transparency = 0.85, collide = false }),
		vcyl("Cap", 0.1, diameter + 0.06, Vector3.new(0, bottom + height + 0.05, 0), GOLD, Metal),
		ball("CapKnob", 0.16, Vector3.new(0, bottom + height + 0.15, 0), GOLD_BRIGHT, Metal),
	}
end

-- Заглушки экспонатов из деталей (друг может заменить моделью с тем же именем: exhibit_<вид>_01).
-- Этап 5, блок F2: больше деталей, металл, мрамор, стекло, неон; низ по центру и занятое место прежние —
-- экспонат по-прежнему встаёт на верх постамента. Цвета — из коммита друга 1073908.
local STUBS: { [string]: { ModelLibrary.StubPart } } = {
	GoldVase = join({
		{ name = "Foot", size = Vector3.new(1.1, 0.3, 1.1), offset = CFrame.new(0, 0.15, 0), color = GOLD, material = Metal, reflectance = 0.35 },
		vcyl("FootRing", 0.08, 1.25, Vector3.new(0, 0.32, 0), GOLD_BRIGHT, Metal),
		{ name = "Body", size = Vector3.new(1.55, 1.55, 1.55), offset = CFrame.new(0, 1.05, 0), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Ball, reflectance = 0.35 },
		{ name = "Band", size = Vector3.new(0.24, 1.62, 1.62), offset = CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("2CE6D8"), material = Neon, shape = Enum.PartType.Cylinder },
		vcyl("Shoulder", 0.12, 1.2, Vector3.new(0, 1.62, 0), GOLD, Metal),
		{ name = "Neck", size = Vector3.new(0.65, 0.75, 0.65), offset = CFrame.new(0, 1.95, 0), color = GOLD, material = Metal, reflectance = 0.35 },
		{ name = "Rim", size = Vector3.new(0.16, 0.95, 0.95), offset = CFrame.new(0, 2.34, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Cylinder, reflectance = 0.35 },
		vcyl("Lip", 0.1, 1.08, Vector3.new(0, 2.45, 0), GOLD, Metal),
		vcyl("Mouth", 0.02, 0.7, Vector3.new(0, 2.5, 0), PAINT_DARK),
		{ name = "HandleL", size = Vector3.new(0.16, 0.85, 0.2), offset = CFrame.new(-0.88, 1.4, 0) * CFrame.Angles(0, 0, rad(18)), color = GOLD, material = Metal },
		{ name = "HandleR", size = Vector3.new(0.16, 0.85, 0.2), offset = CFrame.new(0.88, 1.4, 0) * CFrame.Angles(0, 0, rad(-18)), color = GOLD, material = Metal },
		ball("CurlL", 0.24, Vector3.new(-1, 1.84, 0), GOLD_BRIGHT, Metal),
		ball("CurlR", 0.24, Vector3.new(1, 1.84, 0), GOLD_BRIGHT, Metal),
	}, around(6, 0.84, 1.05, math.pi / 6, function(p)
		return ball("Gem", 0.18, p, RUBY, Neon)
	end)),

	AncientClock = join({
		{ name = "Base", size = Vector3.new(1.6, 0.25, 1.2), offset = CFrame.new(0, 0.125, 0), color = GOLD, material = Metal },
		{ name = "Body", size = Vector3.new(1.4, 2.1, 1), offset = CFrame.new(0, 1.25, 0), color = WOOD, material = Enum.Material.Wood },
		vcyl("ColumnL", 1.9, 0.16, Vector3.new(-0.62, 1.25, -0.5), GOLD_BRIGHT, Metal),
		vcyl("ColumnR", 1.9, 0.16, Vector3.new(0.62, 1.25, -0.5), GOLD_BRIGHT, Metal),
		{ name = "Face", size = Vector3.new(0.12, 1.05, 1.05), offset = CFrame.new(0, 1.6, -0.52) * CFrame.Angles(0, rad(90), 0), color = MARBLE, shape = Enum.PartType.Cylinder },
		{ name = "FaceRim", size = Vector3.new(0.08, 1.18, 1.18), offset = CFrame.new(0, 1.6, -0.5) * CFrame.Angles(0, rad(90), 0), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Cylinder },
		{ name = "HandH", size = Vector3.new(0.08, 0.36, 0.05), offset = CFrame.new(0, 1.74, -0.6), color = NAVY, material = Metal },
		{ name = "HandM", size = Vector3.new(0.32, 0.07, 0.05), offset = CFrame.new(0.14, 1.6, -0.6), color = NAVY, material = Metal },
		disc("Pin", 0.06, 0.1, Vector3.new(0, 1.6, -0.62), GOLD_BRIGHT, Metal),
		-- Окошко с маятником внизу
		box("PendulumRod", Vector3.new(0.05, 0.26, 0.04), CFrame.new(0, 0.86, -0.53), GOLD, Metal),
		{ name = "Pendulum", size = Vector3.new(0.35, 0.35, 0.12), offset = CFrame.new(0, 0.65, -0.52), color = GOLD_BRIGHT, material = Neon, shape = Enum.PartType.Ball },
		with(box("PendulumGlass", Vector3.new(0.8, 0.66, 0.03), CFrame.new(0, 0.64, -0.62), GLASS, Enum.Material.Glass), { transparency = 0.6 }),
		box("WindowTop", Vector3.new(0.9, 0.06, 0.06), CFrame.new(0, 0.98, -0.62), GOLD, Metal),
		box("WindowBottom", Vector3.new(0.9, 0.06, 0.06), CFrame.new(0, 0.3, -0.62), GOLD, Metal),
		box("WindowSide", Vector3.new(0.06, 0.7, 0.06), CFrame.new(-0.45, 0.64, -0.62), GOLD, Metal),
		box("WindowSide", Vector3.new(0.06, 0.7, 0.06), CFrame.new(0.45, 0.64, -0.62), GOLD, Metal),
		{ name = "Crown", size = Vector3.new(1.65, 0.3, 1.2), offset = CFrame.new(0, 2.42, 0), color = GOLD, material = Metal },
		vcyl("FinialBase", 0.1, 0.4, Vector3.new(0, 2.62, 0), GOLD, Metal),
		ball("Finial", 0.3, Vector3.new(0, 2.78, 0), GOLD_BRIGHT, Metal),
	}, clockTicks(Vector3.new(0, 1.6, -0.6), 0.42)),

	Necklace = join({
		{ name = "Cushion", size = Vector3.new(1.4, 0.28, 1.4), offset = CFrame.new(0, 0.14, 0), color = Color3.fromHex("4C2678"), material = Enum.Material.Fabric },
		{ name = "Trim", size = Vector3.new(1.48, 0.08, 1.48), offset = CFrame.new(0, 0.05, 0), color = GOLD, material = Metal },
		{ name = "PearlL", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(-0.44, 0.42, 0), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Ball },
		{ name = "PearlR", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(0.44, 0.42, 0), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Ball },
		{ name = "GemL", size = Vector3.new(0.34, 0.34, 0.34), offset = CFrame.new(-0.32, 0.44, -0.32), color = SAPPHIRE, material = Neon, shape = Enum.PartType.Ball },
		{ name = "GemR", size = Vector3.new(0.34, 0.34, 0.34), offset = CFrame.new(0.32, 0.44, -0.32), color = EMERALD, material = Neon, shape = Enum.PartType.Ball },
		{ name = "Clasp", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(0, 0.42, 0.44), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Ball },
		{ name = "Ruby", size = Vector3.new(0.5, 0.5, 0.5), offset = CFrame.new(0, 0.48, -0.44), color = RUBY, material = Neon, shape = Enum.PartType.Ball },
		disc("Setting", 0.06, 0.58, Vector3.new(0, 0.48, -0.42), GOLD, Metal),
		ball("Drop", 0.2, Vector3.new(0, 0.37, -0.66), RUBY, Neon),
	}, around(16, 0.46, 0.34, 0, function(p)
		return ball("Bead", 0.13, p, Color3.fromHex("FFF7EC"))
	end), around(4, 0.78, 0.29, math.pi / 4, function(p)
		return ball("Tuft", 0.1, p, GOLD, Metal)
	end)),

	Crown = join({
		{ name = "Velvet", size = Vector3.new(1.38, 0.85, 1.38), offset = CFrame.new(0, 0.52, 0), color = VELVET, material = Enum.Material.Fabric, sphere = true },
		box("Ermine", Vector3.new(1.74, 0.16, 1.74), CFrame.new(0, 0.08, 0), Color3.fromHex("FFF9F0"), Enum.Material.Fabric),
		{ name = "Band", size = Vector3.new(1.65, 0.5, 1.65), offset = CFrame.new(0, 0.25, 0), color = GOLD_BRIGHT, material = Metal, reflectance = 0.35 },
		{ name = "SpikeFL", size = Vector3.new(0.3, 0.65, 0.3), offset = CFrame.new(-0.65, 0.82, -0.65), color = GOLD, material = Metal },
		{ name = "SpikeFR", size = Vector3.new(0.3, 0.65, 0.3), offset = CFrame.new(0.65, 0.82, -0.65), color = GOLD, material = Metal },
		{ name = "SpikeBL", size = Vector3.new(0.3, 0.65, 0.3), offset = CFrame.new(-0.65, 0.82, 0.65), color = GOLD, material = Metal },
		{ name = "SpikeBR", size = Vector3.new(0.3, 0.65, 0.3), offset = CFrame.new(0.65, 0.82, 0.65), color = GOLD, material = Metal },
		-- Дужки от зубцов к державе наверху, на ней крестик
		rod("Arch", Vector3.new(-0.6, 1.12, -0.6), Vector3.new(0, 1.2, 0), 0.1, GOLD_BRIGHT, Metal),
		rod("Arch", Vector3.new(0.6, 1.12, -0.6), Vector3.new(0, 1.2, 0), 0.1, GOLD_BRIGHT, Metal),
		rod("Arch", Vector3.new(-0.6, 1.12, 0.6), Vector3.new(0, 1.2, 0), 0.1, GOLD_BRIGHT, Metal),
		rod("Arch", Vector3.new(0.6, 1.12, 0.6), Vector3.new(0, 1.2, 0), 0.1, GOLD_BRIGHT, Metal),
		{ name = "Orb", size = Vector3.new(0.34, 0.34, 0.34), offset = CFrame.new(0, 1.32, 0), color = GOLD_BRIGHT, material = Neon, shape = Enum.PartType.Ball },
		box("Cross", Vector3.new(0.07, 0.3, 0.07), CFrame.new(0, 1.6, 0), GOLD, Metal),
		box("Cross", Vector3.new(0.22, 0.07, 0.07), CFrame.new(0, 1.64, 0), GOLD, Metal),
		{ name = "Ruby", size = Vector3.new(0.42, 0.42, 0.42), offset = CFrame.new(0, 0.28, -0.86), color = RUBY, material = Neon, shape = Enum.PartType.Ball },
		{ name = "SapphireL", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(-0.85, 0.28, 0), color = SAPPHIRE, material = Neon, shape = Enum.PartType.Ball },
		{ name = "EmeraldR", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(0.85, 0.28, 0), color = EMERALD, material = Neon, shape = Enum.PartType.Ball },
		ball("AmethystB", 0.32, Vector3.new(0, 0.28, 0.85), AMETHYST, Neon),
	}, around(4, 0.92, 1.18, math.pi / 4, function(p)
		return ball("Pearl", 0.2, p, Color3.fromHex("FFF7EC"))
	end), around(4, 0.82, 0.74, 0, function(p)
		return box("SpikeMid", Vector3.new(0.2, 0.45, 0.2), CFrame.new(p), GOLD, Metal)
	end)),

	Scepter = join({
		{ name = "Base", size = Vector3.new(0.7, 0.2, 0.7), offset = CFrame.new(0, 0.1, 0), color = GOLD, material = Metal },
		vcyl("Tier", 0.12, 0.5, Vector3.new(0, 0.26, 0), GOLD_BRIGHT, Metal),
		{ name = "Shaft", size = Vector3.new(2.3, 0.28, 0.28), offset = CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Cylinder, reflectance = 0.35 },
		ball("Knob", 0.36, Vector3.new(0, 0.44, 0), GOLD_BRIGHT, Metal),
		vcyl("Grip", 0.08, 0.36, Vector3.new(0, 0.9, 0), GOLD, Metal),
		vcyl("Grip", 0.08, 0.36, Vector3.new(0, 1.2, 0), GOLD, Metal),
		vcyl("Grip", 0.08, 0.36, Vector3.new(0, 1.5, 0), GOLD, Metal),
		{ name = "Collar", size = Vector3.new(0.2, 0.65, 0.65), offset = CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Metal, shape = Enum.PartType.Cylinder },
		{ name = "Orb", size = Vector3.new(0.75, 0.75, 0.75), offset = CFrame.new(0, 2.68, 0), color = AMETHYST, material = Neon, shape = Enum.PartType.Ball },
		{ name = "Finial", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(0, 3.12, 0), color = GOLD_BRIGHT, material = Metal, shape = Enum.PartType.Ball },
		box("Cross", Vector3.new(0.06, 0.26, 0.06), CFrame.new(0, 3.32, 0), GOLD, Metal),
		box("Cross", Vector3.new(0.18, 0.06, 0.06), CFrame.new(0, 3.35, 0), GOLD, Metal),
	}, around(4, 0.34, 2.25, math.pi / 4, function(p)
		return ball("Gem", 0.13, p, RUBY, Neon)
	end), around(4, 0.3, 0, 0, function(p)
		-- Лапки, которые держат державу
		return rod("Prong", Vector3.new(p.X, 2.33, p.Z), Vector3.new(p.X * 1.15, 2.92, p.Z * 1.15), 0.06, GOLD, Metal)
	end)),

	Diamond = {
		vcyl("Plate", 0.12, 1.6, Vector3.new(0, 0.06, 0), VELVET, Enum.Material.Fabric),
		{ name = "Stand", size = Vector3.new(0.9, 0.35, 0.9), offset = CFrame.new(0, 0.175, 0), color = GOLD, material = Metal, reflectance = 0.35 },
		rod("Prong", Vector3.new(-0.3, 0.35, -0.3), Vector3.new(-0.38, 0.9, -0.38), 0.07, GOLD_BRIGHT, Metal),
		rod("Prong", Vector3.new(0.3, 0.35, -0.3), Vector3.new(0.38, 0.9, -0.38), 0.07, GOLD_BRIGHT, Metal),
		rod("Prong", Vector3.new(-0.3, 0.35, 0.3), Vector3.new(-0.38, 0.9, 0.38), 0.07, GOLD_BRIGHT, Metal),
		rod("Prong", Vector3.new(0.3, 0.35, 0.3), Vector3.new(0.38, 0.9, 0.38), 0.07, GOLD_BRIGHT, Metal),
		{ name = "Core", size = Vector3.new(0.65, 0.65, 0.65), offset = CFrame.new(0, 1.2, 0) * CFrame.Angles(rad(45), 0, rad(45)), color = Color3.fromHex("8CF6FF"), material = Neon },
		{ name = "Crystal", size = Vector3.new(1.15, 1.15, 1.15), offset = CFrame.new(0, 1.2, 0) * CFrame.Angles(rad(45), 0, rad(45)), color = Color3.fromHex("6BF0FF"), material = Enum.Material.Glass, transparency = 0.2, reflectance = 0.4 },
		-- Искорки и стеклянный колпак
		box("Sparkle", Vector3.new(0.04, 0.4, 0.04), CFrame.new(0.55, 1.75, -0.35), Color3.fromHex("FFFFFF"), Neon),
		box("Sparkle", Vector3.new(0.4, 0.04, 0.04), CFrame.new(0.55, 1.75, -0.35), Color3.fromHex("FFFFFF"), Neon),
		box("Sparkle", Vector3.new(0.03, 0.26, 0.03), CFrame.new(-0.5, 0.95, -0.45), Color3.fromHex("FFFFFF"), Neon),
		box("Sparkle", Vector3.new(0.26, 0.03, 0.03), CFrame.new(-0.5, 0.95, -0.45), Color3.fromHex("FFFFFF"), Neon),
		{ name = "Dome", size = Vector3.new(1.9, 2.4, 1.9), offset = CFrame.new(0, 1.32, 0), color = GLASS, material = Enum.Material.Glass, transparency = 0.85, sphere = true, collide = false },
		vcyl("DomeRing", 0.1, 1.95, Vector3.new(0, 0.16, 0), GOLD_BRIGHT, Metal),
		ball("DomeKnob", 0.18, Vector3.new(0, 2.55, 0), GOLD_BRIGHT, Metal),
	},

	Amphora = join({
		{ name = "Foot", size = Vector3.new(0.85, 0.3, 0.85), offset = CFrame.new(0, 0.15, 0), color = Color3.fromHex("B85A2A") },
		vcyl("FootRing", 0.08, 0.95, Vector3.new(0, 0.32, 0), PAINT_DARK),
		{ name = "Body", size = Vector3.new(1.5, 1.8, 1.5), offset = CFrame.new(0, 1.2, 0), color = Color3.fromHex("E0783E"), sphere = true },
		vcyl("PaintBand", 0.5, 1.52, Vector3.new(0, 1.15, 0), PAINT_DARK),
		vcyl("Band", 0.1, 1.36, Vector3.new(0, 1.62, 0), GOLD, Metal),
		vcyl("Neck", 0.7, 0.55, Vector3.new(0, 2.3, 0), Color3.fromHex("E0783E")),
		vcyl("NeckBand", 0.08, 0.58, Vector3.new(0, 2.2, 0), PAINT_DARK),
		vcyl("Lip", 0.14, 0.75, Vector3.new(0, 2.66, 0), Color3.fromHex("B85A2A")),
		vcyl("Mouth", 0.02, 0.5, Vector3.new(0, 2.73, 0), PAINT_DARK),
		{ name = "HandleL", size = Vector3.new(0.14, 0.75, 0.16), offset = CFrame.new(-0.78, 1.65, 0) * CFrame.Angles(0, 0, rad(15)), color = GOLD, material = Metal },
		{ name = "HandleR", size = Vector3.new(0.14, 0.75, 0.16), offset = CFrame.new(0.78, 1.65, 0) * CFrame.Angles(0, 0, rad(-15)), color = GOLD, material = Metal },
		rod("HandleTop", Vector3.new(-0.88, 2, 0), Vector3.new(-0.26, 2.45, 0), 0.14, GOLD, Metal),
		rod("HandleTop", Vector3.new(0.88, 2, 0), Vector3.new(0.26, 2.45, 0), 0.14, GOLD, Metal),
	}, around(4, 0.765, 1.15, math.pi / 4, function(p, outward)
		-- Фигурки на чёрном поясе, как на греческих вазах
		return box("Figure", Vector3.new(0.18, 0.36, 0.05), CFrame.lookAt(p, p + outward), Color3.fromHex("E0783E"))
	end)),

	Bust = join({
		{ name = "Plinth", size = Vector3.new(1.3, 0.2, 1.1), offset = CFrame.new(0, 0.1, 0), color = GOLD, material = Metal },
		{ name = "Socle", size = Vector3.new(1.2, 0.45, 1), offset = CFrame.new(0, 0.35, 0), color = MARBLE, material = Marble },
		box("SoclePlate", Vector3.new(0.62, 0.18, 0.03), CFrame.new(0, 0.35, -0.515), GOLD, Metal),
		{ name = "Shoulders", size = Vector3.new(1.8, 0.7, 0.8), offset = CFrame.new(0, 0.9, 0), color = MARBLE, material = Marble },
		ball("ShoulderL", 0.7, Vector3.new(-0.75, 0.98, 0), MARBLE, Marble),
		ball("ShoulderR", 0.7, Vector3.new(0.75, 0.98, 0), MARBLE, Marble),
		box("Drape", Vector3.new(1.9, 0.35, 0.86), CFrame.new(0, 1.08, 0) * CFrame.Angles(0, 0, rad(-18)), MARBLE_SHADE, Marble),
		vcyl("Neck", 0.45, 0.48, Vector3.new(0, 1.35, 0), MARBLE, Marble),
		{ name = "Head", size = Vector3.new(1.1, 1.2, 1.1), offset = CFrame.new(0, 1.8, 0), color = MARBLE, material = Marble, shape = Enum.PartType.Ball },
		{ name = "Hair", size = Vector3.new(1.15, 0.9, 1.15), offset = CFrame.new(0, 2.03, 0.08), color = MARBLE_SHADE, material = Marble, sphere = true },
		box("Nose", Vector3.new(0.14, 0.24, 0.14), CFrame.new(0, 1.76, -0.57), MARBLE, Marble),
		box("Brow", Vector3.new(0.48, 0.06, 0.06), CFrame.new(0, 1.94, -0.52), MARBLE_SHADE, Marble),
		box("EarL", Vector3.new(0.08, 0.24, 0.16), CFrame.new(-0.56, 1.8, 0.02), MARBLE, Marble),
		box("EarR", Vector3.new(0.08, 0.24, 0.16), CFrame.new(0.56, 1.8, 0.02), MARBLE, Marble),
		vcyl("Laurel", 0.08, 1.17, Vector3.new(0, 2, 0), GOLD, Metal),
	}, around(8, 0.6, 2.02, 0, function(p, outward)
		return box("Leaf", Vector3.new(0.14, 0.06, 0.22), CFrame.lookAt(p, p + outward) * CFrame.Angles(rad(20), 0, 0), GOLD_BRIGHT, Metal)
	end)),

	Statue = {
		{ name = "Plinth", size = Vector3.new(1.15, 0.2, 1.15), offset = CFrame.new(0, 0.1, 0), color = GOLD, material = Metal },
		{ name = "Base", size = Vector3.new(1, 0.35, 1), offset = CFrame.new(0, 0.35, 0), color = MARBLE, material = Marble },
		box("LegL", Vector3.new(0.26, 0.95, 0.32), CFrame.new(-0.17, 0.99, 0), MARBLE, Marble),
		box("LegR", Vector3.new(0.26, 0.95, 0.32), CFrame.new(0.17, 0.99, 0.05) * CFrame.Angles(rad(-5), 0, 0), MARBLE, Marble),
		box("Robe", Vector3.new(0.8, 0.55, 0.48), CFrame.new(0, 1.5, 0), MARBLE_SHADE, Marble),
		box("Torso", Vector3.new(0.7, 0.72, 0.42), CFrame.new(0, 2.1, 0), MARBLE, Marble),
		box("Drape", Vector3.new(0.85, 0.2, 0.46), CFrame.new(0, 2.15, 0) * CFrame.Angles(0, 0, rad(30)), MARBLE_SHADE, Marble),
		box("ArmL", Vector3.new(0.2, 0.8, 0.22), CFrame.new(-0.46, 2, 0) * CFrame.Angles(0, 0, rad(-8)), MARBLE, Marble),
		rod("ArmR", Vector3.new(0.42, 2.38, 0), Vector3.new(0.62, 3, -0.05), 0.2, MARBLE, Marble),
		vcyl("Torch", 0.35, 0.12, Vector3.new(0.63, 3.12, -0.05), GOLD, Metal),
		{ name = "Flame", size = Vector3.new(0.22, 0.32, 0.22), offset = CFrame.new(0.63, 3.4, -0.05), color = Color3.fromHex("FFB347"), material = Neon, sphere = true },
		vcyl("Neck", 0.14, 0.2, Vector3.new(0, 2.52, 0), MARBLE, Marble),
		ball("Head", 0.48, Vector3.new(0, 2.8, 0), MARBLE, Marble),
		{ name = "Hair", size = Vector3.new(0.5, 0.38, 0.5), offset = CFrame.new(0, 2.93, 0.04), color = MARBLE_SHADE, material = Marble, sphere = true },
	},

	-- Динозавры (блок 2)
	TRexSkull = join({
		{ name = "Jaw", size = Vector3.new(1.6, 0.35, 2.6), offset = CFrame.new(0, 0.3, -0.45) * CFrame.Angles(rad(-5), 0, 0), color = BONE_DARK },
		{ name = "Cranium", size = Vector3.new(2, 1.3, 1.5), offset = CFrame.new(0, 1.1, 0.55), color = BONE },
		{ name = "Brow", size = Vector3.new(2.1, 0.35, 0.8), offset = CFrame.new(0, 1.85, 0.35), color = BONE },
		{ name = "HornL", size = Vector3.new(0.25, 0.35, 0.3), offset = CFrame.new(-0.75, 2.12, 0.35), color = BONE_DARK, wedge = true },
		{ name = "HornR", size = Vector3.new(0.25, 0.35, 0.3), offset = CFrame.new(0.75, 2.12, 0.35), color = BONE_DARK, wedge = true },
		{ name = "Snout", size = Vector3.new(1.4, 0.9, 1.6), offset = CFrame.new(0, 0.95, -0.9), color = BONE },
		{ name = "SnoutTip", size = Vector3.new(1.15, 0.7, 0.6), offset = CFrame.new(0, 0.88, -1.9), color = BONE },
		{ name = "Ridge", size = Vector3.new(0.3, 0.18, 1.8), offset = CFrame.new(0, 1.44, -1.05), color = BONE_DARK },
		{ name = "Nostrils", size = Vector3.new(0.7, 0.12, 0.25), offset = CFrame.new(0, 1.24, -1.95), color = SOCKET },
		{ name = "EyeL", size = Vector3.new(0.12, 0.5, 0.5), offset = CFrame.new(-1.01, 1.25, 0.35), color = SOCKET },
		{ name = "EyeR", size = Vector3.new(0.12, 0.5, 0.5), offset = CFrame.new(1.01, 1.25, 0.35), color = SOCKET },
		{ name = "CheekL", size = Vector3.new(0.12, 0.35, 0.8), offset = CFrame.new(-0.71, 0.9, -0.7), color = SOCKET },
		{ name = "CheekR", size = Vector3.new(0.12, 0.35, 0.8), offset = CFrame.new(0.71, 0.9, -0.7), color = SOCKET },
		{ name = "FrillL", size = Vector3.new(0.3, 0.6, 0.5), offset = CFrame.new(-0.95, 1.15, 1.15) * CFrame.Angles(0, 0, rad(12)), color = BONE_DARK },
		{ name = "FrillR", size = Vector3.new(0.3, 0.6, 0.5), offset = CFrame.new(0.95, 1.15, 1.15) * CFrame.Angles(0, 0, rad(-12)), color = BONE_DARK },
		{ name = "Neck", size = Vector3.new(0.8, 0.8, 0.6), offset = CFrame.new(0, 0.95, 1.55), color = BONE_DARK },
	}, teeth(0.4, -2.05, -0.55, 4)),

	DinoEgg = {
		{ name = "Nest", size = Vector3.new(0.5, 1.9, 1.9), offset = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("7A5A34"), material = Enum.Material.Grass, shape = Enum.PartType.Cylinder },
		{ name = "NestRim", size = Vector3.new(0.3, 2.1, 2.1), offset = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("5C4326"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder },
		{ name = "Twig", size = Vector3.new(0.12, 0.12, 1.9), offset = CFrame.new(0.4, 0.62, 0) * CFrame.Angles(0, rad(20), rad(10)), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(0.12, 0.12, 1.9), offset = CFrame.new(-0.4, 0.62, 0.1) * CFrame.Angles(0, rad(-35), rad(-8)), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(1.9, 0.12, 0.12), offset = CFrame.new(0, 0.62, -0.45) * CFrame.Angles(0, rad(10), 0), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(1.7, 0.1, 0.1), offset = CFrame.new(0.1, 0.64, 0.5) * CFrame.Angles(0, rad(-15), rad(5)), color = Color3.fromHex("6B4E2E"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(0.1, 0.1, 1.6), offset = CFrame.new(-0.7, 0.66, -0.2) * CFrame.Angles(rad(6), rad(50), 0), color = Color3.fromHex("6B4E2E"), material = Enum.Material.Wood },
		ball("Pebble", 0.2, Vector3.new(0.72, 0.62, 0.45), Color3.fromHex("8E8A80"), Enum.Material.Slate),
		ball("Pebble", 0.16, Vector3.new(-0.62, 0.62, -0.58), Color3.fromHex("A39E92"), Enum.Material.Slate),
		box("ShellBit", Vector3.new(0.3, 0.06, 0.22), CFrame.new(-0.62, 0.66, 0.5) * CFrame.Angles(0, 0.5, 0.3), Color3.fromHex("D8CBA8")),
		{ name = "Egg", size = Vector3.new(1.1, 1.5, 1.1), offset = CFrame.new(0, 1.25, 0), color = Color3.fromHex("D8CBA8"), sphere = true },
		{ name = "Spot", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0.42, 1.35, -0.2), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.22, 0.22, 0.22), offset = CFrame.new(-0.36, 1.05, -0.32), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.2, 0.2, 0.2), offset = CFrame.new(0.05, 1.72, -0.36), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(-0.32, 1.5, 0.34), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		-- Светящаяся трещина: вот-вот вылупится
		rod("Crack", Vector3.new(0.12, 1.78, -0.42), Vector3.new(-0.08, 1.55, -0.52), 0.05, Color3.fromHex("FFB347"), Neon),
		rod("Crack", Vector3.new(-0.08, 1.55, -0.52), Vector3.new(0.12, 1.38, -0.55), 0.05, Color3.fromHex("FFB347"), Neon),
		rod("Crack", Vector3.new(0.12, 1.38, -0.55), Vector3.new(-0.02, 1.2, -0.57), 0.05, Color3.fromHex("FFB347"), Neon),
	},

	RaptorClaw = {
		{ name = "Stand", size = Vector3.new(1.2, 0.3, 0.9), offset = CFrame.new(0, 0.15, 0), color = STAND, material = Metal },
		box("StandTrim", Vector3.new(1.26, 0.06, 0.96), CFrame.new(0, 0.31, 0), GOLD, Metal),
		{ name = "Label", size = Vector3.new(0.8, 0.12, 0.05), offset = CFrame.new(0, 0.15, -0.47), color = GOLD, material = Metal },
		vcyl("Support", 1.5, 0.06, Vector3.new(0, 1.05, 0.36), STAND, Metal),
		{ name = "Root", size = Vector3.new(0.45, 0.45, 0.4), offset = CFrame.new(0, 0.5, 0.2), color = BONE_DARK },
		rod("Toe", Vector3.new(0, 0.42, 0.35), Vector3.new(0, 0.38, -0.3), 0.2, BONE),
		ball("Knuckle", 0.3, Vector3.new(0, 0.72, 0.22), BONE_DARK),
		{ name = "Claw", size = Vector3.new(0.4, 0.6, 0.36), offset = CFrame.new(0, 0.95, 0.12), color = BONE },
		{ name = "Claw", size = Vector3.new(0.34, 0.55, 0.3), offset = CFrame.new(0, 1.42, -0.02) * CFrame.Angles(rad(-20), 0, 0), color = BONE },
		{ name = "Claw", size = Vector3.new(0.28, 0.5, 0.25), offset = CFrame.new(0, 1.82, -0.28) * CFrame.Angles(rad(-42), 0, 0), color = BONE_DARK },
		{ name = "Claw", size = Vector3.new(0.22, 0.45, 0.2), offset = CFrame.new(0, 2.08, -0.62) * CFrame.Angles(rad(-68), 0, 0), color = Color3.fromHex("9C8A64") },
		{ name = "Tip", size = Vector3.new(0.15, 0.35, 0.14), offset = CFrame.new(0, 2.16, -0.95) * CFrame.Angles(rad(-95), 0, 0), color = Color3.fromHex("6B5A40") },
	},

	DinoTooth = join({
		{ name = "Stand", size = Vector3.new(1, 0.3, 1), offset = CFrame.new(0, 0.15, 0), color = STAND, material = Metal },
		box("StandTrim", Vector3.new(1.06, 0.06, 1.06), CFrame.new(0, 0.31, 0), GOLD, Metal),
		{ name = "Rod", size = Vector3.new(0.12, 0.35, 0.12), offset = CFrame.new(0, 0.47, 0), color = STAND, material = Metal },
		{ name = "Root", size = Vector3.new(0.5, 0.3, 0.36), offset = CFrame.new(0, 0.78, 0), color = Color3.fromHex("B8A47E") },
		{ name = "Tooth", size = Vector3.new(0.6, 0.5, 0.42), offset = CFrame.new(0, 1.15, 0), color = BONE },
		{ name = "Tooth", size = Vector3.new(0.48, 0.5, 0.35), offset = CFrame.new(0, 1.6, 0.04) * CFrame.Angles(rad(8), 0, 0), color = BONE },
		{ name = "Tooth", size = Vector3.new(0.34, 0.5, 0.26), offset = CFrame.new(0, 2.02, 0.1) * CFrame.Angles(rad(14), 0, 0), color = BONE },
		{ name = "Tip", size = Vector3.new(0.18, 0.32, 0.15), offset = CFrame.new(0, 2.34, 0.17) * CFrame.Angles(rad(20), 0, 0), color = Color3.fromHex("F7F3EA") },
		box("Ridge", Vector3.new(0.05, 1.2, 0.05), CFrame.new(0, 1.62, 0.25) * CFrame.Angles(rad(12), 0, 0), BONE_DARK),
	}, glassCover(2.25, 0.95, 0.34)),

	-- Космос (блок 2)
	Meteorite = {
		{ name = "Stand", size = Vector3.new(0.3, 1.4, 1.4), offset = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, rad(90)), color = STAND, material = Metal, shape = Enum.PartType.Cylinder },
		vcyl("StandRing", 0.06, 1.46, Vector3.new(0, 0.31, 0), GOLD, Metal),
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(0.45, 0.6, 0) * CFrame.Angles(0, 0, rad(-15)), color = GOLD, material = Metal },
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(-0.25, 0.6, 0.4) * CFrame.Angles(rad(15), 0, rad(10)), color = GOLD, material = Metal },
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(-0.25, 0.6, -0.4) * CFrame.Angles(rad(-15), 0, rad(10)), color = GOLD, material = Metal },
		{ name = "Rock", size = Vector3.new(1.3, 1.3, 1.3), offset = CFrame.new(0, 1.3, 0), color = Color3.fromHex("3B3530"), material = Enum.Material.Basalt, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.9, 0.9, 0.9), offset = CFrame.new(0.42, 1.6, 0.2), color = Color3.fromHex("4A403A"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.8, 0.8, 0.8), offset = CFrame.new(-0.36, 1.1, -0.25), color = Color3.fromHex("2F2925"), material = Enum.Material.Basalt, shape = Enum.PartType.Ball },
		ball("Crater", 0.24, Vector3.new(0.12, 1.62, -0.56), Color3.fromHex("1E1A17"), Enum.Material.Basalt),
		ball("Crater", 0.2, Vector3.new(-0.62, 1.32, -0.3), Color3.fromHex("1E1A17"), Enum.Material.Basalt),
		ball("Crater", 0.18, Vector3.new(0.6, 1.05, -0.32), Color3.fromHex("1E1A17"), Enum.Material.Basalt),
		{ name = "Glow", size = Vector3.new(0.08, 0.55, 0.06), offset = CFrame.new(0.3, 1.25, -0.6) * CFrame.Angles(0, 0, rad(25)), color = Color3.fromHex("FF8A3D"), material = Neon },
		{ name = "Glow", size = Vector3.new(0.08, 0.45, 0.06), offset = CFrame.new(-0.45, 1.5, 0.45) * CFrame.Angles(0, rad(40), rad(-30)), color = Color3.fromHex("FF8A3D"), material = Neon },
		{ name = "Glow", size = Vector3.new(0.06, 0.35, 0.06), offset = CFrame.new(0.6, 1.75, 0.1) * CFrame.Angles(0, 0, rad(-40)), color = Color3.fromHex("FFC24A"), material = Neon },
		{ name = "Glow", size = Vector3.new(0.06, 0.4, 0.06), offset = CFrame.new(-0.15, 0.85, -0.5) * CFrame.Angles(rad(20), 0, rad(60)), color = Color3.fromHex("FF8A3D"), material = Neon },
	},

	AstronautHelmet = {
		{ name = "Collar", size = Vector3.new(0.35, 1.55, 1.55), offset = CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("A9B0BC"), material = Metal, shape = Enum.PartType.Cylinder },
		vcyl("CollarRing", 0.1, 1.62, Vector3.new(0, 0.38, 0), Color3.fromHex("2E6FD8"), Metal),
		disc("ValveRed", 0.16, 0.24, Vector3.new(-0.38, 0.22, -0.74), Color3.fromHex("E63946"), Metal),
		disc("ValveBlue", 0.16, 0.24, Vector3.new(0.38, 0.22, -0.74), Color3.fromHex("2E6FD8"), Metal),
		{ name = "Helmet", size = Vector3.new(1.6, 1.6, 1.6), offset = CFrame.new(0, 1.15, 0), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Ball },
		{ name = "Visor", size = Vector3.new(1.15, 0.85, 0.5), offset = CFrame.new(0, 1.22, -0.6), color = GOLD, material = Metal, sphere = true, reflectance = 0.45 },
		{ name = "VisorRim", size = Vector3.new(1.3, 0.14, 0.2), offset = CFrame.new(0, 1.7, -0.58), color = Color3.fromHex("A9B0BC"), material = Metal },
		{ name = "Lamp", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0.55, 1.72, -0.42), color = Color3.fromHex("FFFFFF"), material = Neon, shape = Enum.PartType.Ball },
		ball("LampL", 0.26, Vector3.new(-0.55, 1.72, -0.42), Color3.fromHex("FFFFFF"), Neon),
		{ name = "CommL", size = Vector3.new(0.15, 0.42, 0.42), offset = CFrame.new(-0.8, 1.15, 0), color = Color3.fromHex("A9B0BC"), material = Metal, shape = Enum.PartType.Cylinder },
		{ name = "Antenna", size = Vector3.new(0.06, 0.6, 0.06), offset = CFrame.new(-0.45, 2.05, 0.25), color = Color3.fromHex("A9B0BC"), material = Metal },
		ball("AntennaTip", 0.12, Vector3.new(-0.45, 2.36, 0.25), Color3.fromHex("E63946"), Neon),
		{ name = "Patch", size = Vector3.new(0.06, 0.3, 0.45), offset = CFrame.new(0.79, 1.15, 0.12), color = Color3.fromHex("2E6FD8") },
		{ name = "PatchStripe", size = Vector3.new(0.07, 0.08, 0.45), offset = CFrame.new(0.8, 1.15, 0.12), color = Color3.fromHex("E63946") },
	},

	RocketModel = join({
		{ name = "Stand", size = Vector3.new(1.2, 0.2, 1.2), offset = CFrame.new(0, 0.1, 0), color = STAND, material = Metal },
		vcyl("StandRing", 0.06, 1.0, Vector3.new(0, 0.21, 0), GOLD, Metal),
		vcyl("Exhaust", 0.04, 0.42, Vector3.new(0, 0.23, 0), Color3.fromHex("FF8A3D"), Neon),
		{ name = "Nozzle", size = Vector3.new(0.3, 0.5, 0.5), offset = CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("3A3F4B"), material = Metal, shape = Enum.PartType.Cylinder },
		{ name = "Body", size = Vector3.new(1.6, 0.7, 0.7), offset = CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Band", size = Vector3.new(0.18, 0.74, 0.74), offset = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, rad(90)), color = RUBY, shape = Enum.PartType.Cylinder },
		{ name = "Band", size = Vector3.new(0.14, 0.74, 0.74), offset = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, rad(90)), color = RUBY, shape = Enum.PartType.Cylinder },
		{ name = "Window", size = Vector3.new(0.08, 0.3, 0.3), offset = CFrame.new(0, 1.45, -0.36) * CFrame.Angles(0, rad(90), 0), color = Color3.fromHex("7FE7FF"), material = Neon, shape = Enum.PartType.Cylinder },
		disc("WindowRim", 0.06, 0.38, Vector3.new(0, 1.45, -0.34), GOLD, Metal),
		disc("Porthole", 0.08, 0.18, Vector3.new(0, 1.12, -0.36), Color3.fromHex("7FE7FF"), Neon),
		{ name = "Nose", size = Vector3.new(0.4, 0.56, 0.56), offset = CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Nose", size = Vector3.new(0.3, 0.36, 0.36), offset = CFrame.new(0, 2.63, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Tip", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0, 2.86, 0), color = RUBY, shape = Enum.PartType.Ball },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.new(0, 0.85, -0.55), color = RUBY, wedge = true },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.Angles(0, rad(120), 0) * CFrame.new(0, 0.85, -0.55), color = RUBY, wedge = true },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.Angles(0, rad(240), 0) * CFrame.new(0, 0.85, -0.55), color = RUBY, wedge = true },
	}, around(3, 0.46, 0.85, math.pi / 3, function(p)
		-- Боковые ускорители между крыльями
		return vcyl("Booster", 0.9, 0.22, p, Color3.fromHex("F2F4F7"))
	end), around(3, 0.46, 1.3, math.pi / 3, function(p)
		return ball("BoosterTip", 0.22, p, RUBY)
	end)),

	MoonRock = {
		{ name = "Base", size = Vector3.new(0.3, 1.3, 1.3), offset = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, rad(90)), color = NAVY, shape = Enum.PartType.Cylinder },
		{ name = "Ring", size = Vector3.new(0.08, 1.36, 1.36), offset = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Metal, shape = Enum.PartType.Cylinder },
		vcyl("LedRing", 0.05, 1.16, Vector3.new(0, 0.34, 0), Color3.fromHex("7FE7FF"), Neon),
		{ name = "Rock", size = Vector3.new(0.8, 0.8, 0.8), offset = CFrame.new(0, 0.72, 0), color = Color3.fromHex("A7A9AC"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.5, 0.5, 0.5), offset = CFrame.new(0.25, 0.86, 0.15), color = Color3.fromHex("8E9094"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		ball("Rock", 0.3, Vector3.new(-0.28, 0.5, 0.18), Color3.fromHex("BDBFC2"), Enum.Material.Slate),
		box("FlagPole", Vector3.new(0.03, 0.5, 0.03), CFrame.new(0.3, 0.85, -0.22), Color3.fromHex("A9B0BC"), Metal),
		box("Flag", Vector3.new(0.2, 0.12, 0.02), CFrame.new(0.4, 1.04, -0.22), Color3.fromHex("2E6FD8")),
		{ name = "Dome", size = Vector3.new(1.15, 1.45, 1.15), offset = CFrame.new(0, 0.98, 0), color = Color3.fromHex("BFE3F2"), material = Enum.Material.Glass, transparency = 0.75, sphere = true },
		ball("DomeKnob", 0.16, Vector3.new(0, 1.74, 0), GOLD, Metal),
		{ name = "Label", size = Vector3.new(0.6, 0.14, 0.05), offset = CFrame.new(0, 0.16, -0.66), color = GOLD, material = Metal },
	},

	Lion = {
		box("Plinth", Vector3.new(1.5, 0.2, 2.9), CFrame.new(0, 0.1, -0.15), MARBLE_SHADE, Marble),
		box("PlinthTrim", Vector3.new(1.56, 0.06, 2.96), CFrame.new(0, 0.2, -0.15), GOLD, Metal),
		box("LegFL", Vector3.new(0.32, 0.62, 0.36), CFrame.new(-0.32, 0.51, -0.45), MARBLE, Marble),
		box("LegFR", Vector3.new(0.32, 0.62, 0.36), CFrame.new(0.32, 0.51, -0.45), MARBLE, Marble),
		box("LegBL", Vector3.new(0.32, 0.62, 0.36), CFrame.new(-0.32, 0.51, 0.6), MARBLE, Marble),
		box("LegBR", Vector3.new(0.32, 0.62, 0.36), CFrame.new(0.32, 0.51, 0.6), MARBLE, Marble),
		box("Paw", Vector3.new(0.36, 0.14, 0.46), CFrame.new(-0.32, 0.27, -0.52), MARBLE, Marble),
		box("Paw", Vector3.new(0.36, 0.14, 0.46), CFrame.new(0.32, 0.27, -0.52), MARBLE, Marble),
		box("Paw", Vector3.new(0.36, 0.14, 0.46), CFrame.new(-0.32, 0.27, 0.56), MARBLE, Marble),
		box("Paw", Vector3.new(0.36, 0.14, 0.46), CFrame.new(0.32, 0.27, 0.56), MARBLE, Marble),
		{ name = "Body", size = Vector3.new(1, 0.85, 1.6), offset = CFrame.new(0, 1.15, 0.1), color = MARBLE, material = Marble, sphere = true },
		{ name = "Chest", size = Vector3.new(1, 1, 0.9), offset = CFrame.new(0, 1.3, -0.5), color = MARBLE, material = Marble, sphere = true },
		{ name = "Mane", size = Vector3.new(1.45, 1.45, 0.95), offset = CFrame.new(0, 1.75, -0.85), color = MARBLE_SHADE, material = Marble, sphere = true },
		box("Face", Vector3.new(0.7, 0.7, 0.5), CFrame.new(0, 1.72, -1.15), MARBLE, Marble),
		box("Snout", Vector3.new(0.46, 0.32, 0.32), CFrame.new(0, 1.58, -1.44), MARBLE, Marble),
		box("Nose", Vector3.new(0.18, 0.1, 0.08), CFrame.new(0, 1.72, -1.6), Color3.fromHex("8C8478"), Marble),
		box("EyeL", Vector3.new(0.1, 0.06, 0.04), CFrame.new(-0.17, 1.88, -1.41), Color3.fromHex("8C8478"), Marble),
		box("EyeR", Vector3.new(0.1, 0.06, 0.04), CFrame.new(0.17, 1.88, -1.41), Color3.fromHex("8C8478"), Marble),
		ball("EarL", 0.24, Vector3.new(-0.4, 2.3, -1), MARBLE, Marble),
		ball("EarR", 0.24, Vector3.new(0.4, 2.3, -1), MARBLE, Marble),
		rod("Tail", Vector3.new(0, 1.25, 0.85), Vector3.new(0, 0.62, 1.2), 0.12, MARBLE, Marble),
		ball("TailTuft", 0.28, Vector3.new(0, 0.58, 1.22), MARBLE_SHADE, Marble),
	},
}

-- Мягкий свет дорогих экспонатов (Config.Exhibits.GlowMinPrice): на какой детали и какого цвета.
-- У модели друга такой детали может не быть — тогда свет на первой детали модели.
local GLOW: { [string]: { part: string, color: Color3 } } = {
	Scepter = { part = "Orb", color = AMETHYST },
	Diamond = { part = "Core", color = Color3.fromHex("8CF6FF") },
	TRexSkull = { part = "Cranium", color = Color3.fromHex("FFD9A0") },
	Meteorite = { part = "Rock", color = Color3.fromHex("FF8A3D") },
	AstronautHelmet = { part = "Lamp", color = Color3.fromHex("CFE8FF") },
	RocketModel = { part = "Exhaust", color = Color3.fromHex("FF9A4A") },
}

local function addGlow(model: PVInstance, kind: string, price: number)
	if price < ExhibitConfig.GlowMinPrice then
		return
	end
	local glow = GLOW[kind]
	local holder = glow and model:FindFirstChild(glow.part)
	if not (holder and holder:IsA("BasePart")) then
		holder = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not (holder and holder:IsA("BasePart")) then
		return
	end
	local settings = Config.Lighting.ExhibitGlow
	local light = Instance.new("PointLight")
	light.Name = "ExhibitGlow"
	light.Range = settings.Range
	light.Brightness = settings.Brightness
	light.Color = if glow then glow.color else settings.Color
	light.Parent = holder
end

local exhibits: { Exhibit } = {}
local mainExhibit: Exhibit? = nil
local slots: { Slot } = {}
local exhibitsFolder: Instance? = nil
local dayActive = false
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function newExhibit(id: string, title: string, model: PVInstance, home: CFrame, appeal: number, isMain: boolean, hall: string): Exhibit
	local front = home.Position + home.LookVector * Config.Thief.StandOffset
	local exhibit: Exhibit = {
		id = id,
		title = title,
		model = model,
		home = home,
		stand = Vector3.new(front.X, 3, front.Z),
		look = home.Position,
		appeal = appeal,
		isMain = isMain,
		hall = hall,
		carrier = nil,
		stealer = nil,
		carryCopy = nil,
	}
	return exhibit
end

-- Полоска кражи у клиентов показывается только для Моны Лизы.
local function setStealer(exhibit: Exhibit, thief: Model?)
	exhibit.stealer = thief
	if exhibit.isMain then
		local endsAt = if thief then now() + Config.Thief.StealSeconds else 0
		GameState.set(GameState.Attr.StealEndsAt, endsAt)
	end
end

---------------------------------------------------------------- для воров

-- Экспонат на месте и его никто не снимает (или снимает этот же вор).
function ExhibitService.isFree(exhibit: Exhibit, thief: Model?): boolean
	return exhibit.carrier == nil and (exhibit.stealer == nil or exhibit.stealer == thief or not (exhibit.stealer :: Model).Parent)
		and table.find(exhibits, exhibit) ~= nil
end

-- Сколько по полу от точки до ближайшего охранника (охраны нет — бесконечно далеко).
local function guardDistance(position: Vector3, guards: { Vector3 }): number
	local best = math.huge
	for _, guard in guards do
		local offset = guard - position
		best = math.min(best, Vector3.new(offset.X, 0, offset.Z).Magnitude)
	end
	return best
end

-- Цель вора (блок 3: воры следят за охраной). guards — где стоят охранники.
--  mode = "Main"  — только Мона Лиза (если её уже снимают или несут — экспонат подальше от охраны);
--  mode = "Cheap" — дешёвый экспонат подальше от Моны Лизы (приманка уводит туда охрану);
--  mode = nil     — чаще Мона Лиза, если рядом с ней нет охраны, иначе экспонат, рядом с которым охраны нет.
-- avoid — экспонаты, которые уже выбрали другие воры (шахтёры вылезают у разных экспонатов).
function ExhibitService.pickTarget(thief: Model?, mode: string?, guards: { Vector3 }?, avoid: { Exhibit }?): Exhibit?
	local guardList = guards or {}
	local others: { Exhibit } = {}
	local main: Exhibit? = nil
	for _, exhibit in exhibits do
		if ExhibitService.isFree(exhibit, thief) and GameState.isHallOpen(exhibit.hall) and not (avoid and table.find(avoid, exhibit)) then
			if exhibit.isMain then
				main = exhibit
			else
				table.insert(others, exhibit)
			end
		end
	end
	local radius = Config.Smart.GuardedTargetRadius
	local function farthestFromGuards(list: { Exhibit }): Exhibit?
		local best, bestDistance = nil, -1
		for _, exhibit in list do
			local distance = guardDistance(exhibit.stand, guardList) + random:NextNumber() -- случайно при равенстве
			if distance > bestDistance then
				best, bestDistance = exhibit, distance
			end
		end
		return best
	end

	if mode == "Main" then
		return main or farthestFromGuards(others)
	end
	if mode == "Cheap" then
		local home = if mainExhibit then mainExhibit.home.Position else Vector3.zero
		local best, bestDistance = nil, -1
		for _, exhibit in others do
			local distance = (exhibit.home.Position - home).Magnitude
			if distance > bestDistance then
				best, bestDistance = exhibit, distance
			end
		end
		return best
	end

	local mainSafe = main ~= nil and guardDistance(main.stand, guardList) >= radius
	if main and mainSafe and (#others == 0 or random:NextNumber() < ExhibitConfig.MonaLisaChance) then
		return main
	end
	local safe: { Exhibit } = {}
	for _, exhibit in others do
		if guardDistance(exhibit.stand, guardList) >= radius then
			table.insert(safe, exhibit)
		end
	end
	if #safe > 0 then
		return safe[random:NextInteger(1, #safe)]
	end
	if main and mainSafe then
		return main
	end
	-- Всё под охраной: берут то, что дальше всего от охранников
	local all = table.clone(others)
	if main then
		table.insert(all, main)
	end
	return farthestFromGuards(all)
end

-- Мона Лиза (её экспонат).
function ExhibitService.main(): Exhibit?
	return mainExhibit
end

function ExhibitService.getCarried(thief: Model): Exhibit?
	for _, exhibit in exhibits do
		if exhibit.carrier == thief then
			return exhibit
		end
	end
	return nil
end

-- Вор, который снимает или несёт Мону Лизу (остальные воры его загораживают).
function ExhibitService.mainBusyBy(): Model?
	local main = mainExhibit
	if not main then
		return nil
	end
	return main.carrier or main.stealer
end

function ExhibitService.tryStartSteal(exhibit: Exhibit, thief: Model): boolean
	if not ExhibitService.isFree(exhibit, thief) then
		return false
	end
	if exhibit.stealer ~= thief then
		setStealer(exhibit, thief)
		ExhibitService.StealStarted:Fire(exhibit)
	end
	return true
end

function ExhibitService.cancelSteal(thief: Model)
	for _, exhibit in exhibits do
		if exhibit.stealer == thief then
			setStealer(exhibit, nil)
		end
	end
end

local function destroyCopy(exhibit: Exhibit)
	local copy = exhibit.carryCopy
	if copy then
		copy:Destroy()
		exhibit.carryCopy = nil
	end
end

-- Вор снял экспонат: над его головой появляется копия, настоящий прячется под картой.
function ExhibitService.take(exhibit: Exhibit, thief: Model): boolean
	local head = thief:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) or exhibit.carrier then
		return false
	end
	setStealer(exhibit, nil)
	exhibit.carrier = thief
	destroyCopy(exhibit)
	local copy = exhibit.model:Clone()
	for _, descendant in copy:GetDescendants() do
		-- Кнопки покупки и таблички с ценой у копии не нужны
		if descendant:IsA("ProximityPrompt") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
	copy.Name = exhibit.model.Name .. "_Carried"
	local offset = Config.Painting.CarryOffset
	ModelLibrary.weldTo(copy, head, head.CFrame * CFrame.new(offset.X, offset.Y, offset.Z))
	copy.Parent = thief -- пропадёт вместе с вором
	exhibit.carryCopy = copy
	exhibit.model:PivotTo(exhibit.home - Vector3.new(0, ExhibitConfig.HideDepth, 0))
	if exhibit.isMain then
		GameState.set(GameState.Attr.PaintingStolen, true)
	end
	return true
end

-- Экспонат возвращается на место (вора поймали, или ночь кончилась).
function ExhibitService.returnHome(exhibit: Exhibit)
	setStealer(exhibit, nil)
	exhibit.carrier = nil
	destroyCopy(exhibit)
	exhibit.model:PivotTo(exhibit.home)
	if exhibit.isMain then
		GameState.set(GameState.Attr.PaintingStolen, false)
	end
end

function ExhibitService.returnAll()
	for _, exhibit in exhibits do
		ExhibitService.returnHome(exhibit)
	end
end

local refreshSlot: (Slot) -> ()

-- Вор унёс дешёвый экспонат: его больше нет, постамент снова пустой (можно купить заново).
function ExhibitService.lose(exhibit: Exhibit)
	local index = table.find(exhibits, exhibit)
	if index then
		table.remove(exhibits, index)
	end
	destroyCopy(exhibit)
	exhibit.model:Destroy()
	ExhibitService.Lost:Fire(exhibit)
	for _, slot in slots do
		if slot.exhibit == exhibit then
			slot.exhibit = nil
			slot.paid = 0
			refreshSlot(slot)
		end
	end
end

-- Все экспонаты, что сейчас есть в музее (Мона Лиза и купленные).
function ExhibitService.list(): { Exhibit }
	return table.clone(exhibits)
end

---------------------------------------------------------------- для туристов

function ExhibitService.attractions(): { { stand: Vector3, look: Vector3 } }
	local list = {}
	for _, exhibit in exhibits do
		if exhibit.carrier == nil and GameState.isHallOpen(exhibit.hall) then
			-- Туристы встают чуть дальше, чем вор
			local direction = exhibit.stand - Vector3.new(exhibit.look.X, exhibit.stand.Y, exhibit.look.Z)
			local away = if direction.Magnitude > 0.1 then direction.Unit else Vector3.new(0, 0, 1)
			table.insert(list, { stand = exhibit.stand + away * 3, look = exhibit.look })
		end
	end
	return list
end

-- Привлекательность купленных экспонатов (Мона Лиза — в базе числа туристов).
function ExhibitService.totalAppeal(): number
	local total = 0
	for _, exhibit in exhibits do
		if not exhibit.isMain and GameState.isHallOpen(exhibit.hall) then
			total += exhibit.appeal
		end
	end
	return total
end

---------------------------------------------------------------- покупка на постаментах

-- Верх постамента, экспонат смотрит туда же, куда постамент (вор встаёт перед ним).
local function slotTop(slot: Slot): CFrame
	local pivot = slot.pedestal:GetPivot()
	return pivot.Rotation + pivot.Position + Vector3.new(0, ExhibitConfig.PedestalHeight, 0)
end

refreshSlot = function(slot: Slot)
	local open = GameState.isHallOpen(slot.hall)
	local empty = slot.exhibit == nil
	if slot.prompt then
		slot.prompt.Enabled = dayActive and open and empty
		slot.prompt.ObjectText = Purchase.progressText(slot.title, slot.paid, slot.price)
		Purchase.setProgress(slot.prompt, slot.paid, slot.price)
	end
	if slot.label then
		slot.label.Text = if slot.paid > 0
			then ("%s\n$%d / $%d"):format(slot.title, slot.paid, slot.price)
			else ("%s\n$%d"):format(slot.title, slot.price)
	end
	if slot.billboard then
		slot.billboard.Enabled = dayActive and open and empty
	end
end

local function modelName(kind: string): string
	return "exhibit_" .. string.lower(kind) .. "_01"
end

local function placeExhibit(slot: Slot)
	local folder = exhibitsFolder or Workspace
	local stub = STUBS[slot.kind] or STUBS.GoldVase
	local model = ModelLibrary.place(modelName(slot.kind), slotTop(slot), stub, folder)
	addGlow(model, slot.kind, slot.price)
	local exhibit = newExhibit(slot.kind, slot.title, model, slotTop(slot), slot.appeal, false, slot.hall)
	slot.exhibit = exhibit
	table.insert(exhibits, exhibit)
	refreshSlot(slot)
	ExhibitService.Added:Fire(exhibit)
end

-- Удержание F у постамента (или покупка из окна магазина — fromShop, без проверки расстояния): остаток цены,
-- если хватает денег, иначе всё, что есть (Purchase.take). Возвращает, сколько взяли.
local function contribute(slot: Slot, player: Player, base: BasePart, fromShop: boolean?): number
	if not dayActive or slot.exhibit or not GameState.isHallOpen(slot.hall) then
		return 0
	end
	local amount = Purchase.take(player, base, slot.paid, slot.price, fromShop)
	if amount <= 0 then
		return 0
	end
	slot.paid += amount
	if slot.paid >= slot.price then
		placeExhibit(slot)
	else
		refreshSlot(slot)
	end
	return amount
end

local function slotBase(slot: Slot): BasePart?
	return slot.pedestal.PrimaryPart or slot.pedestal:FindFirstChildWhichIsA("BasePart", true)
end

local function setupSlot(slot: Slot)
	local base = slotBase(slot)
	if not base then
		return
	end
	local prompt = Purchase.newPrompt(base, "BuyPrompt", slot.price)
	prompt.Triggered:Connect(function(player)
		contribute(slot, player, base)
	end)
	slot.prompt = prompt

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PriceTag"
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, ExhibitConfig.PedestalHeight + 1.6, 0)
	billboard.MaxDistance = 40
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = base
	slot.billboard = billboard
	slot.label = label
	refreshSlot(slot)
end

---------------------------------------------------------------- окно магазина (этап 4, блок 1b)

-- 3D-картинка экспоната для окна магазина (модель друга или заглушка). Мона Лиза — копия картины.
function ExhibitService.preview(kind: string): PVInstance
	local main = mainExhibit
	if kind == ExhibitService.MainId and main then
		local copy = main.model:Clone()
		copy:PivotTo(CFrame.identity)
		return copy
	end
	return ModelLibrary.build(modelName(kind), STUBS[kind] or STUBS.GoldVase)
end

-- Все экспонаты музея для окна магазина: Мона Лиза, потом постаменты по порядку.
function ExhibitService.catalog(): { { id: string, title: string, hall: string } }
	local list = { { id = ExhibitService.MainId, title = "Mona Lisa", hall = GameState.Hall.Main } }
	for _, slot in slots do
		table.insert(list, { id = slot.kind, title = slot.title, hall = slot.hall })
	end
	return list
end

-- 3D-картинка зала для окна магазина: постамент зала с самым дорогим его экспонатом.
function ExhibitService.hallPreview(hall: string): PVInstance?
	local best: Slot? = nil
	for _, slot in slots do
		if slot.hall == hall and (best == nil or slot.price > best.price) then
			best = slot
		end
	end
	if not best then
		return nil
	end
	local container = Instance.new("Model")
	container.Name = "HallPreview"
	local pedestal = best.pedestal:Clone()
	pedestal:PivotTo(CFrame.identity)
	pedestal.Parent = container
	local exhibit = ExhibitService.preview(best.kind)
	exhibit:PivotTo(CFrame.new(0, ExhibitConfig.PedestalHeight, 0))
	exhibit.Parent = container
	return container
end

local function hallTitle(hall: string): string
	local settings = (Config.Halls :: any)[hall]
	return if typeof(settings) == "table" then tostring(settings.Title) else "CENTER HALL"
end

local function registerInShop(slot: Slot, order: number)
	ShopService.register({
		category = "Exhibits",
		id = slot.kind,
		title = slot.title,
		info = ("+%d tourist%s a day • %s"):format(slot.appeal, if slot.appeal == 1 then "" else "s", hallTitle(slot.hall)),
		order = order,
		price = slot.price,
		hall = slot.hall,
		preview = ExhibitService.preview(slot.kind),
		state = function(): ShopService.State
			return { paid = slot.paid, owned = slot.exhibit ~= nil }
		end,
		buy = function(player: Player): (string, string)
			local base = slotBase(slot)
			if slot.exhibit then
				return ShopService.fail(slot.title .. " is already in the museum")
			elseif not GameState.isHallOpen(slot.hall) then
				return ShopService.fail(("Open the %s first — Halls tab"):format(hallTitle(slot.hall)))
			elseif not base then
				return ShopService.fail("This pedestal is missing")
			end
			local amount = contribute(slot, player, base, true)
			return ShopService.sharedResult(slot.title, amount, slot.paid, slot.price)
		end,
	})
end

-- Днём можно покупать экспонаты.
function ExhibitService.setDayActive(active: boolean)
	dayActive = active
	for _, slot in slots do
		refreshSlot(slot)
	end
end

-- Новый забег: купленные экспонаты убираем, деньги в постаментах обнуляются.
function ExhibitService.reset()
	for _, slot in slots do
		local exhibit = slot.exhibit
		if exhibit then
			local index = table.find(exhibits, exhibit)
			if index then
				table.remove(exhibits, index)
			end
			destroyCopy(exhibit)
			exhibit.model:Destroy()
			slot.exhibit = nil
		end
		slot.paid = 0
		refreshSlot(slot)
	end
	if mainExhibit then
		ExhibitService.returnHome(mainExhibit)
	end
end

function ExhibitService.init(map: Instance)
	exhibitsFolder = map:FindFirstChild(MapSchema.Exhibits)
	local spot = map:FindFirstChild(MapSchema.PaintingSpot, true)
	local painting = exhibitsFolder and exhibitsFolder:FindFirstChild(MapSchema.Models.MonaLisa)
	if painting and painting:IsA("PVInstance") then
		local home = if spot and spot:IsA("BasePart") then spot.CFrame else painting:GetPivot()
		mainExhibit = newExhibit(ExhibitService.MainId, "Mona Lisa", painting, home, 0, true, GameState.Hall.Main)
		table.insert(exhibits, mainExhibit :: Exhibit)
	else
		warn("[ExhibitService] На карте нет Моны Лизы")
	end
	GameState.set(GameState.Attr.PaintingStolen, false)
	GameState.set(GameState.Attr.StealEndsAt, 0)

	-- Зал открыли посреди дня — его постаменты сразу можно покупать, не дожидаясь следующего дня
	GameState.folder().AttributeChanged:Connect(function(attr)
		if string.sub(attr, 1, #"HallOpen_") == "HallOpen_" then
			for _, slot in slots do
				refreshSlot(slot)
			end
		end
	end)

	local pedestals = map:FindFirstChild(MapSchema.Pedestals)
	if pedestals then
		for _, pedestal in pedestals:GetChildren() do
			local slotIndex = pedestal:GetAttribute("Slot")
			local hall = pedestal:GetAttribute("Hall")
			local kind = typeof(slotIndex) == "number" and ExhibitConfig.Slots[slotIndex] or nil
			local info = kind and (ExhibitConfig.Kinds :: any)[kind]
			if pedestal:IsA("Model") and typeof(hall) == "string" and kind and info then
				local slot: Slot = {
					pedestal = pedestal,
					hall = hall,
					kind = kind,
					title = info.Title,
					price = info.Price,
					appeal = info.Appeal,
					paid = 0,
					exhibit = nil,
					prompt = nil,
					label = nil,
					billboard = nil,
				}
				table.insert(slots, slot)
				setupSlot(slot)
			end
		end
	end
	table.sort(slots, function(a, b)
		return (tonumber(a.pedestal:GetAttribute("Slot")) or 0) < (tonumber(b.pedestal:GetAttribute("Slot")) or 0)
	end)
	for order, slot in slots do
		registerInShop(slot, order)
	end
end

return ExhibitService
