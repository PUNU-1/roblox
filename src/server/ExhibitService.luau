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

local ExhibitConfig = Config.Exhibits

local ExhibitService = {}

-- Вор начал снимать экспонат (exhibit). Сигнализация на Мону Лизу слушает его.
ExhibitService.StealStarted = Instance.new("BindableEvent")
-- Экспонат купили (exhibit): для него можно купить лазерную сетку.
ExhibitService.Added = Instance.new("BindableEvent")
-- Экспонат унесли насовсем (exhibit): его сетка пропадает.
ExhibitService.Lost = Instance.new("BindableEvent")

export type Exhibit = {
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

local GOLD = Color3.fromHex("D4A93A")
local MARBLE = Color3.fromHex("F2EEE6")
local WOOD = Color3.fromHex("7A5230")
local BONE = Color3.fromHex("E9DFC6")
local BONE_DARK = Color3.fromHex("C9B98F")
local SOCKET = Color3.fromHex("3A2E22")
local STAND = Color3.fromHex("2B2F3A")
local NAVY = Color3.fromHex("1E2A44")

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

local function join(first: { ModelLibrary.StubPart }, second: { ModelLibrary.StubPart }): { ModelLibrary.StubPart }
	local result: { ModelLibrary.StubPart } = table.clone(first)
	for _, part in second do
		table.insert(result, part)
	end
	return result
end

-- Заглушки экспонатов из деталей (друг может заменить моделью с тем же именем: exhibit_<вид>_01).
local STUBS: { [string]: { ModelLibrary.StubPart } } = {
	GoldVase = {
		{ size = Vector3.new(1, 0.3, 1), offset = CFrame.new(0, 0.15, 0), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(1.5, 1.5, 1.5), offset = CFrame.new(0, 1.05, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ size = Vector3.new(0.6, 0.7, 0.6), offset = CFrame.new(0, 1.95, 0), color = GOLD, material = Enum.Material.Metal },
	},
	AncientClock = {
		{ size = Vector3.new(1.4, 2.2, 1), offset = CFrame.new(0, 1.1, 0), color = WOOD, material = Enum.Material.Wood },
		{ size = Vector3.new(1, 1, 0.1), offset = CFrame.new(0, 1.5, -0.52), color = MARBLE },
		{ size = Vector3.new(1.6, 0.3, 1.2), offset = CFrame.new(0, 2.35, 0), color = GOLD, material = Enum.Material.Metal },
	},
	Necklace = {
		{ size = Vector3.new(1.2, 0.2, 1.2), offset = CFrame.new(0, 0.1, 0), color = Color3.fromHex("2B1B3D"), material = Enum.Material.Fabric },
		{ size = Vector3.new(0.35, 0.35, 0.35), offset = CFrame.new(-0.4, 0.4, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ size = Vector3.new(0.35, 0.35, 0.35), offset = CFrame.new(0.4, 0.4, 0), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ size = Vector3.new(0.35, 0.35, 0.35), offset = CFrame.new(0, 0.4, 0.4), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ size = Vector3.new(0.45, 0.45, 0.45), offset = CFrame.new(0, 0.4, -0.4), color = Color3.fromHex("E0245E"), material = Enum.Material.Neon, shape = Enum.PartType.Ball },
	},
	Crown = {
		{ size = Vector3.new(1.6, 0.5, 1.6), offset = CFrame.new(0, 0.25, 0), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.6, 0.3), offset = CFrame.new(-0.65, 0.8, -0.65), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.6, 0.3), offset = CFrame.new(0.65, 0.8, -0.65), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.6, 0.3), offset = CFrame.new(-0.65, 0.8, 0.65), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.3, 0.6, 0.3), offset = CFrame.new(0.65, 0.8, 0.65), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.45, 0.45, 0.45), offset = CFrame.new(0, 0.3, -0.85), color = Color3.fromHex("C8343A"), material = Enum.Material.Neon, shape = Enum.PartType.Ball },
	},
	Scepter = {
		{ size = Vector3.new(0.3, 2.4, 0.3), offset = CFrame.new(0, 1.2, 0), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(0.7, 0.7, 0.7), offset = CFrame.new(0, 2.6, 0), color = Color3.fromHex("8E44AD"), material = Enum.Material.Neon, shape = Enum.PartType.Ball },
	},
	Diamond = {
		{ size = Vector3.new(0.8, 0.4, 0.8), offset = CFrame.new(0, 0.2, 0), color = GOLD, material = Enum.Material.Metal },
		{ size = Vector3.new(1, 1, 1), offset = CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = Color3.fromHex("7FE7FF"), material = Enum.Material.Glass, transparency = 0.15 },
	},
	Amphora = {
		{ size = Vector3.new(0.8, 0.3, 0.8), offset = CFrame.new(0, 0.15, 0), color = Color3.fromHex("A0522D") },
		{ size = Vector3.new(1.5, 1.8, 1.5), offset = CFrame.new(0, 1.2, 0), color = Color3.fromHex("C0703E"), shape = Enum.PartType.Ball },
		{ size = Vector3.new(0.5, 0.7, 0.5), offset = CFrame.new(0, 2.3, 0), color = Color3.fromHex("C0703E") },
	},
	Bust = {
		{ size = Vector3.new(1.2, 0.5, 1), offset = CFrame.new(0, 0.25, 0), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(1.8, 0.7, 0.8), offset = CFrame.new(0, 0.85, 0), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(1.1, 1.2, 1.1), offset = CFrame.new(0, 1.75, 0), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball },
	},
	Statue = {
		{ size = Vector3.new(1, 0.4, 1), offset = CFrame.new(0, 0.2, 0), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.8, 2, 0.6), offset = CFrame.new(0, 1.4, 0), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(2.2, 0.3, 0.3), offset = CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, 0.4), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.7, 0.7, 0.7), offset = CFrame.new(0, 2.75, 0), color = MARBLE, material = Enum.Material.Marble, shape = Enum.PartType.Ball },
	},
	-- Динозавры (блок 2)
	TRexSkull = join({
		{ name = "Jaw", size = Vector3.new(1.6, 0.35, 2.6), offset = CFrame.new(0, 0.3, -0.45) * CFrame.Angles(rad(-5), 0, 0), color = BONE_DARK },
		{ name = "Cranium", size = Vector3.new(2, 1.3, 1.5), offset = CFrame.new(0, 1.1, 0.55), color = BONE },
		{ name = "Brow", size = Vector3.new(2.1, 0.35, 0.8), offset = CFrame.new(0, 1.85, 0.35), color = BONE },
		{ name = "Snout", size = Vector3.new(1.4, 0.9, 1.6), offset = CFrame.new(0, 0.95, -0.9), color = BONE },
		{ name = "SnoutTip", size = Vector3.new(1.15, 0.7, 0.6), offset = CFrame.new(0, 0.88, -1.9), color = BONE },
		{ name = "Nostrils", size = Vector3.new(0.7, 0.12, 0.25), offset = CFrame.new(0, 1.24, -1.95), color = SOCKET },
		{ name = "EyeL", size = Vector3.new(0.12, 0.5, 0.5), offset = CFrame.new(-1.01, 1.25, 0.35), color = SOCKET },
		{ name = "EyeR", size = Vector3.new(0.12, 0.5, 0.5), offset = CFrame.new(1.01, 1.25, 0.35), color = SOCKET },
		{ name = "CheekL", size = Vector3.new(0.12, 0.35, 0.8), offset = CFrame.new(-0.71, 0.9, -0.7), color = SOCKET },
		{ name = "CheekR", size = Vector3.new(0.12, 0.35, 0.8), offset = CFrame.new(0.71, 0.9, -0.7), color = SOCKET },
		{ name = "Neck", size = Vector3.new(0.8, 0.8, 0.6), offset = CFrame.new(0, 0.95, 1.55), color = BONE_DARK },
	}, teeth(0.4, -2.05, -0.55, 4)),
	DinoEgg = {
		{ name = "Nest", size = Vector3.new(0.5, 1.9, 1.9), offset = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("7A5A34"), material = Enum.Material.Grass, shape = Enum.PartType.Cylinder },
		{ name = "NestRim", size = Vector3.new(0.3, 2.1, 2.1), offset = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("5C4326"), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder },
		{ name = "Twig", size = Vector3.new(0.12, 0.12, 1.9), offset = CFrame.new(0.4, 0.62, 0) * CFrame.Angles(0, rad(20), rad(10)), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(0.12, 0.12, 1.9), offset = CFrame.new(-0.4, 0.62, 0.1) * CFrame.Angles(0, rad(-35), rad(-8)), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Twig", size = Vector3.new(1.9, 0.12, 0.12), offset = CFrame.new(0, 0.62, -0.45) * CFrame.Angles(0, rad(10), 0), color = Color3.fromHex("4A3520"), material = Enum.Material.Wood },
		{ name = "Egg", size = Vector3.new(1.1, 1.5, 1.1), offset = CFrame.new(0, 1.25, 0), color = Color3.fromHex("D8CBA8"), sphere = true },
		{ name = "Spot", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0.42, 1.35, -0.2), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.22, 0.22, 0.22), offset = CFrame.new(-0.36, 1.05, -0.32), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.2, 0.2, 0.2), offset = CFrame.new(0.05, 1.72, -0.36), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
		{ name = "Spot", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(-0.32, 1.5, 0.34), color = Color3.fromHex("8E7A52"), shape = Enum.PartType.Ball },
	},
	RaptorClaw = {
		{ name = "Stand", size = Vector3.new(1.2, 0.3, 0.9), offset = CFrame.new(0, 0.15, 0), color = STAND, material = Enum.Material.Metal },
		{ name = "Label", size = Vector3.new(0.8, 0.12, 0.05), offset = CFrame.new(0, 0.15, -0.47), color = GOLD, material = Enum.Material.Metal },
		{ name = "Root", size = Vector3.new(0.45, 0.45, 0.4), offset = CFrame.new(0, 0.5, 0.2), color = BONE_DARK },
		{ name = "Claw", size = Vector3.new(0.4, 0.6, 0.36), offset = CFrame.new(0, 0.95, 0.12), color = BONE },
		{ name = "Claw", size = Vector3.new(0.34, 0.55, 0.3), offset = CFrame.new(0, 1.42, -0.02) * CFrame.Angles(rad(-20), 0, 0), color = BONE },
		{ name = "Claw", size = Vector3.new(0.28, 0.5, 0.25), offset = CFrame.new(0, 1.82, -0.28) * CFrame.Angles(rad(-42), 0, 0), color = BONE_DARK },
		{ name = "Claw", size = Vector3.new(0.22, 0.45, 0.2), offset = CFrame.new(0, 2.08, -0.62) * CFrame.Angles(rad(-68), 0, 0), color = Color3.fromHex("9C8A64") },
		{ name = "Tip", size = Vector3.new(0.15, 0.35, 0.14), offset = CFrame.new(0, 2.16, -0.95) * CFrame.Angles(rad(-95), 0, 0), color = Color3.fromHex("6B5A40") },
	},
	DinoTooth = {
		{ name = "Stand", size = Vector3.new(1, 0.3, 1), offset = CFrame.new(0, 0.15, 0), color = STAND, material = Enum.Material.Metal },
		{ name = "Rod", size = Vector3.new(0.12, 0.35, 0.12), offset = CFrame.new(0, 0.47, 0), color = STAND, material = Enum.Material.Metal },
		{ name = "Root", size = Vector3.new(0.5, 0.3, 0.36), offset = CFrame.new(0, 0.78, 0), color = Color3.fromHex("B8A47E") },
		{ name = "Tooth", size = Vector3.new(0.6, 0.5, 0.42), offset = CFrame.new(0, 1.15, 0), color = BONE },
		{ name = "Tooth", size = Vector3.new(0.48, 0.5, 0.35), offset = CFrame.new(0, 1.6, 0.04) * CFrame.Angles(rad(8), 0, 0), color = BONE },
		{ name = "Tooth", size = Vector3.new(0.34, 0.5, 0.26), offset = CFrame.new(0, 2.02, 0.1) * CFrame.Angles(rad(14), 0, 0), color = BONE },
		{ name = "Tip", size = Vector3.new(0.18, 0.32, 0.15), offset = CFrame.new(0, 2.34, 0.17) * CFrame.Angles(rad(20), 0, 0), color = Color3.fromHex("F7F3EA") },
	},
	-- Космос (блок 2)
	Meteorite = {
		{ name = "Stand", size = Vector3.new(0.3, 1.4, 1.4), offset = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, rad(90)), color = STAND, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(0.45, 0.6, 0) * CFrame.Angles(0, 0, rad(-15)), color = GOLD, material = Enum.Material.Metal },
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(-0.25, 0.6, 0.4) * CFrame.Angles(rad(15), 0, rad(10)), color = GOLD, material = Enum.Material.Metal },
		{ name = "Prong", size = Vector3.new(0.1, 0.8, 0.1), offset = CFrame.new(-0.25, 0.6, -0.4) * CFrame.Angles(rad(-15), 0, rad(10)), color = GOLD, material = Enum.Material.Metal },
		{ name = "Rock", size = Vector3.new(1.3, 1.3, 1.3), offset = CFrame.new(0, 1.3, 0), color = Color3.fromHex("3B3530"), material = Enum.Material.Basalt, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.9, 0.9, 0.9), offset = CFrame.new(0.42, 1.6, 0.2), color = Color3.fromHex("4A403A"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.8, 0.8, 0.8), offset = CFrame.new(-0.36, 1.1, -0.25), color = Color3.fromHex("2F2925"), material = Enum.Material.Basalt, shape = Enum.PartType.Ball },
		{ name = "Glow", size = Vector3.new(0.08, 0.55, 0.06), offset = CFrame.new(0.3, 1.25, -0.6) * CFrame.Angles(0, 0, rad(25)), color = Color3.fromHex("FF8A3D"), material = Enum.Material.Neon },
		{ name = "Glow", size = Vector3.new(0.08, 0.45, 0.06), offset = CFrame.new(-0.45, 1.5, 0.45) * CFrame.Angles(0, rad(40), rad(-30)), color = Color3.fromHex("FF8A3D"), material = Enum.Material.Neon },
		{ name = "Glow", size = Vector3.new(0.06, 0.35, 0.06), offset = CFrame.new(0.6, 1.75, 0.1) * CFrame.Angles(0, 0, rad(-40)), color = Color3.fromHex("FFC24A"), material = Enum.Material.Neon },
	},
	AstronautHelmet = {
		{ name = "Collar", size = Vector3.new(0.35, 1.55, 1.55), offset = CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("A9B0BC"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Helmet", size = Vector3.new(1.6, 1.6, 1.6), offset = CFrame.new(0, 1.15, 0), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Ball },
		{ name = "Visor", size = Vector3.new(1.15, 0.85, 0.5), offset = CFrame.new(0, 1.22, -0.6), color = Color3.fromHex("D4A93A"), material = Enum.Material.Metal, sphere = true },
		{ name = "VisorRim", size = Vector3.new(1.3, 0.14, 0.2), offset = CFrame.new(0, 1.7, -0.58), color = Color3.fromHex("A9B0BC"), material = Enum.Material.Metal },
		{ name = "Lamp", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0.55, 1.72, -0.42), color = Color3.fromHex("FFFFFF"), material = Enum.Material.Neon, shape = Enum.PartType.Ball },
		{ name = "Antenna", size = Vector3.new(0.06, 0.6, 0.06), offset = CFrame.new(-0.45, 2.05, 0.25), color = Color3.fromHex("A9B0BC"), material = Enum.Material.Metal },
		{ name = "Patch", size = Vector3.new(0.06, 0.3, 0.45), offset = CFrame.new(0.79, 1.15, 0.12), color = Color3.fromHex("2E6FD8") },
		{ name = "PatchStripe", size = Vector3.new(0.07, 0.08, 0.45), offset = CFrame.new(0.8, 1.15, 0.12), color = Color3.fromHex("C8343A") },
	},
	RocketModel = {
		{ name = "Stand", size = Vector3.new(1.2, 0.2, 1.2), offset = CFrame.new(0, 0.1, 0), color = STAND, material = Enum.Material.Metal },
		{ name = "Nozzle", size = Vector3.new(0.3, 0.5, 0.5), offset = CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("3A3F4B"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Body", size = Vector3.new(1.6, 0.7, 0.7), offset = CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Band", size = Vector3.new(0.18, 0.74, 0.74), offset = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("C8343A"), shape = Enum.PartType.Cylinder },
		{ name = "Band", size = Vector3.new(0.14, 0.74, 0.74), offset = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("C8343A"), shape = Enum.PartType.Cylinder },
		{ name = "Window", size = Vector3.new(0.08, 0.3, 0.3), offset = CFrame.new(0, 1.45, -0.36) * CFrame.Angles(0, rad(90), 0), color = Color3.fromHex("7FE7FF"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder },
		{ name = "Nose", size = Vector3.new(0.4, 0.56, 0.56), offset = CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Nose", size = Vector3.new(0.3, 0.36, 0.36), offset = CFrame.new(0, 2.63, 0) * CFrame.Angles(0, 0, rad(90)), color = Color3.fromHex("F2F4F7"), shape = Enum.PartType.Cylinder },
		{ name = "Tip", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(0, 2.86, 0), color = Color3.fromHex("C8343A"), shape = Enum.PartType.Ball },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.new(0, 0.85, -0.55), color = Color3.fromHex("C8343A"), wedge = true },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.Angles(0, rad(120), 0) * CFrame.new(0, 0.85, -0.55), color = Color3.fromHex("C8343A"), wedge = true },
		{ name = "Fin", size = Vector3.new(0.1, 0.7, 0.45), offset = CFrame.Angles(0, rad(240), 0) * CFrame.new(0, 0.85, -0.55), color = Color3.fromHex("C8343A"), wedge = true },
	},
	MoonRock = {
		{ name = "Base", size = Vector3.new(0.3, 1.3, 1.3), offset = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, rad(90)), color = NAVY, shape = Enum.PartType.Cylinder },
		{ name = "Ring", size = Vector3.new(0.08, 1.36, 1.36), offset = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, rad(90)), color = GOLD, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Rock", size = Vector3.new(0.8, 0.8, 0.8), offset = CFrame.new(0, 0.72, 0), color = Color3.fromHex("A7A9AC"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		{ name = "Rock", size = Vector3.new(0.5, 0.5, 0.5), offset = CFrame.new(0.25, 0.86, 0.15), color = Color3.fromHex("8E9094"), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
		{ name = "Dome", size = Vector3.new(1.15, 1.45, 1.15), offset = CFrame.new(0, 0.98, 0), color = Color3.fromHex("BFE3F2"), material = Enum.Material.Glass, transparency = 0.75, sphere = true },
		{ name = "Label", size = Vector3.new(0.6, 0.14, 0.05), offset = CFrame.new(0, 0.16, -0.66), color = GOLD, material = Enum.Material.Metal },
	},
	Lion = {
		{ size = Vector3.new(2, 1, 1), offset = CFrame.new(0, 0.9, 0), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(1, 1.1, 1.1), offset = CFrame.new(0, 1.4, -1), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.3, 0.4, 0.3), offset = CFrame.new(-0.7, 0.2, -0.3), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.3, 0.4, 0.3), offset = CFrame.new(0.7, 0.2, -0.3), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.3, 0.4, 0.3), offset = CFrame.new(-0.7, 0.2, 0.4), color = MARBLE, material = Enum.Material.Marble },
		{ size = Vector3.new(0.3, 0.4, 0.3), offset = CFrame.new(0.7, 0.2, 0.4), color = MARBLE, material = Enum.Material.Marble },
	},
}

local exhibits: { Exhibit } = {}
local mainExhibit: Exhibit? = nil
local slots: { Slot } = {}
local exhibitsFolder: Instance? = nil
local dayActive = false
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function newExhibit(title: string, model: PVInstance, home: CFrame, appeal: number, isMain: boolean, hall: string): Exhibit
	local front = home.Position + home.LookVector * Config.Thief.StandOffset
	local exhibit: Exhibit = {
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

-- Цель для нового вора: чаще Мона Лиза, иначе любой свободный купленный экспонат.
function ExhibitService.pickTarget(thief: Model?): Exhibit?
	local others = {}
	for _, exhibit in exhibits do
		if not exhibit.isMain and ExhibitService.isFree(exhibit, thief) and GameState.isHallOpen(exhibit.hall) then
			table.insert(others, exhibit)
		end
	end
	local main = mainExhibit
	local mainFree = main ~= nil and ExhibitService.isFree(main, thief)
	if mainFree and (#others == 0 or random:NextNumber() < ExhibitConfig.MonaLisaChance) then
		return main
	end
	if #others > 0 then
		return others[random:NextInteger(1, #others)]
	end
	return if mainFree then main else nil
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

local function placeExhibit(slot: Slot)
	local folder = exhibitsFolder or Workspace
	local stub = STUBS[slot.kind] or STUBS.GoldVase
	local model = ModelLibrary.place("exhibit_" .. string.lower(slot.kind) .. "_01", slotTop(slot), stub, folder)
	local exhibit = newExhibit(slot.title, model, slotTop(slot), slot.appeal, false, slot.hall)
	slot.exhibit = exhibit
	table.insert(exhibits, exhibit)
	refreshSlot(slot)
	ExhibitService.Added:Fire(exhibit)
end

-- Удержание F у постамента: остаток цены, если хватает денег, иначе всё, что есть (Purchase.take).
local function contribute(slot: Slot, player: Player, base: BasePart)
	if not dayActive or slot.exhibit or not GameState.isHallOpen(slot.hall) then
		return
	end
	local amount = Purchase.take(player, base, slot.paid, slot.price)
	if amount <= 0 then
		return
	end
	slot.paid += amount
	if slot.paid >= slot.price then
		placeExhibit(slot)
	else
		refreshSlot(slot)
	end
end

local function setupSlot(slot: Slot)
	local base = slot.pedestal.PrimaryPart or slot.pedestal:FindFirstChildWhichIsA("BasePart", true)
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
		mainExhibit = newExhibit("Mona Lisa", painting, home, 0, true, GameState.Hall.Main)
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
end

return ExhibitService
