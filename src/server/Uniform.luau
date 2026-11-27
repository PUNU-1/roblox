-- Форма охраны (решения 12, 55, 82, ремодель R2): убираем свою одежду и аксессуары на теле, красим тело в
-- тёмно-синюю форму, надеваем значок, рубашку с карманами, галстуком и ремень. Шапки, волосы, очки и брови
-- игрока остаются. Поверх формы — костюм класса:
--   Patrol      — светоотражающие полосы на груди, спине, руках и ногах, детализированные кроссовки;
--   Operator    — гарнитура с амбушюрами и микрофоном (или на шее) и планшет с камерой на поясе;
--   Technician  — жёлтая каска с очками на лбу (или на поясе) и пояс с инструментами;
--   DogHandler  — жилет K-9 с нашивками, свистком, поводком и сумочкой для лакомств;
--   Assault     — тяжёлый стально-синий тактический жилет с наплечниками, подсумками и наколенниками.
-- Общая для музея (RoleService, ThiefKinds) и хаба (Hub.server). Все детали — Weld с явным C0 к костям тела.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local Uniform = {}

type Stub = { ModelLibrary.StubPart }

local KIT_ATTR = "UniformKit" -- у деталей формы и костюма класса: снимаются при переодевании

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local C = {
	Navy = Config.Uniform.Torso,
	NavyDark = hex("141C30"),
	Gold = hex("F5C542"),
	Silver = hex("D6DCE4"),
	Black = hex("15171C"),
	Leather = hex("2A2320"),
	Brown = hex("6B4A2E"),
	BrownDark = hex("4E3420"),
	Lime = hex("D4F53C"), -- светоотражающие полосы патруля
	White = hex("F7F7F2"),
	Red = hex("E63946"),
	Yellow = hex("FFC21A"),
	YellowDark = hex("D99A0E"),
	Steel = hex("8D9BB2"),
	Screen = hex("4FC3F7"),
	K9 = hex("1C1F26"),
	K9Yellow = hex("FFD036"),
	Armor = hex("3A4F7A"), -- стально-синий: штурмовика не спутать с грабителем в чёрном жилете
	ArmorDark = hex("26344F"),
	Turquoise = hex("3BC6C1"),
}
Uniform.Colors = C

local BADGE_STUB: Stub = {
	{ name = "Shield", size = Vector3.new(0.48, 0.52, 0.08), offset = CFrame.identity, color = Color3.fromHex("F5C542"), material = Enum.Material.Metal, reflectance = 0.35 },
	{ name = "Core", size = Vector3.new(0.34, 0.36, 0.09), offset = CFrame.new(0, 0, -0.01), color = Color3.fromHex("243B6B"), material = Enum.Material.SmoothPlastic },
	{ name = "Star", size = Vector3.new(0.18, 0.18, 0.1), offset = CFrame.new(0, 0.02, -0.02) * CFrame.Angles(0, 0, math.rad(45)), color = Color3.fromHex("FFE066"), material = Enum.Material.Neon },
}

-- Всё, что носят на голове, остаётся (решение 55): шапки, волосы, очки, брови.
local HEAD_ACCESSORY_TYPES: { [Enum.AccessoryType]: boolean } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}
-- У старых аксессуаров тип бывает Unknown — тогда смотрим, к чему он крепится
local HEAD_ATTACHMENTS: { [string]: boolean } = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

local function isHeadAccessory(accessory: Accessory): boolean
	if HEAD_ACCESSORY_TYPES[accessory.AccessoryType] then
		return true
	end
	local handle = accessory:FindFirstChild("Handle")
	if handle then
		for _, child in handle:GetChildren() do
			if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
				return true
			end
		end
	end
	return false
end

-- Есть ли на голове что-то своё (шапка, волосы, очки): тогда деталь класса для головы идёт на тело.
-- Брови и ресницы не считаются — под каской и гарнитурой их и так видно.
local function headIsBusy(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and isHeadAccessory(child)
			and child.AccessoryType ~= Enum.AccessoryType.Eyebrow and child.AccessoryType ~= Enum.AccessoryType.Eyelash
		then
			return true
		end
	end
	return false
end

local function sizeOf(character: Model, partName: string): Vector3
	local part = character:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part.Size else Vector3.new(1, 1, 1)
end

-- Надеть деталь формы на часть тела (снимется при следующем переодевании).
local function wear(character: Model, partName: string, name: string, stub: Stub, offset: CFrame?): Instance?
	local prop = ModelLibrary.attachTo(character, partName, name, stub, offset or CFrame.identity)
	if prop then
		prop:SetAttribute(KIT_ATTR, true)
	end
	return prop
end

-- Надпись на грани детали (K-9, SECURITY).
local function label(prop: Instance?, partName: string, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number?)
	local part = prop and prop:FindFirstChild(partName, true)
	if not (part and part:IsA("BasePart")) or part:FindFirstChildOfClass("SurfaceGui") then
		return -- у модели друга надпись может быть своя
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 50
	gui.LightInfluence = 1
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Text = text
	text_.TextScaled = true
	text_.Font = Enum.Font.FredokaOne
	text_.TextColor3 = color
	text_.Parent = gui
	gui.Parent = part
end

---------------------------------------------------------------- общая форма

local function shirt(character: Model)
	local t = sizeOf(character, "UpperTorso")
	local front = -t.Z * 0.5 - 0.025
	local stub: Stub = {
		-- Воротник и центральная планка с пуговками
		{ name = "CollarL", size = Vector3.new(t.X * 0.22, t.Y * 0.12, 0.06), offset = CFrame.new(-t.X * 0.11, t.Y * 0.44, front) * CFrame.Angles(0, 0, -0.45), color = C.NavyDark },
		{ name = "CollarR", size = Vector3.new(t.X * 0.22, t.Y * 0.12, 0.06), offset = CFrame.new(t.X * 0.11, t.Y * 0.44, front) * CFrame.Angles(0, 0, 0.45), color = C.NavyDark },
		{ name = "CollarBack", size = Vector3.new(t.X * 0.44, t.Y * 0.11, 0.06), offset = CFrame.new(0, t.Y * 0.46, -front), color = C.NavyDark },
		{ name = "Placket", size = Vector3.new(0.14, t.Y * 0.78, 0.04), offset = CFrame.new(0, -t.Y * 0.02, front + 0.005), color = C.NavyDark, material = Enum.Material.Fabric },
		{ name = "PlacketBtn1", size = Vector3.new(0.06, 0.06, 0.05), offset = CFrame.new(0, t.Y * 0.12, front - 0.01), color = C.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "PlacketBtn2", size = Vector3.new(0.06, 0.06, 0.05), offset = CFrame.new(0, -t.Y * 0.12, front - 0.01), color = C.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		-- Нагрудные карманы с клапанами, пуговками и именной планкой справа
		{ name = "PocketL", size = Vector3.new(t.X * 0.21, t.Y * 0.2, 0.05), offset = CFrame.new(-t.X * 0.25, t.Y * 0.15, front), color = C.NavyDark, material = Enum.Material.Fabric },
		{ name = "PocketR", size = Vector3.new(t.X * 0.21, t.Y * 0.2, 0.05), offset = CFrame.new(t.X * 0.25, t.Y * 0.15, front), color = C.NavyDark, material = Enum.Material.Fabric },
		{ name = "FlapL", size = Vector3.new(t.X * 0.22, t.Y * 0.06, 0.07), offset = CFrame.new(-t.X * 0.25, t.Y * 0.26, front), color = C.Navy, material = Enum.Material.Fabric },
		{ name = "FlapR", size = Vector3.new(t.X * 0.22, t.Y * 0.06, 0.07), offset = CFrame.new(t.X * 0.25, t.Y * 0.26, front), color = C.Navy, material = Enum.Material.Fabric },
		{ name = "ButtonL", size = Vector3.new(0.08, 0.08, 0.08), offset = CFrame.new(-t.X * 0.25, t.Y * 0.24, front - 0.04), color = C.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "ButtonR", size = Vector3.new(0.08, 0.08, 0.08), offset = CFrame.new(t.X * 0.25, t.Y * 0.24, front - 0.04), color = C.Gold, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "NameTag", size = Vector3.new(t.X * 0.2, 0.09, 0.04), offset = CFrame.new(t.X * 0.25, t.Y * 0.34, front - 0.01), color = C.Gold, material = Enum.Material.Metal },
		-- Погоны с золотой пуговкой
		{ name = "EpauletL", size = Vector3.new(t.X * 0.2, 0.06, t.Z * 0.56), offset = CFrame.new(-t.X * 0.37, t.Y * 0.5 + 0.02, 0), color = C.NavyDark },
		{ name = "EpauletR", size = Vector3.new(t.X * 0.2, 0.06, t.Z * 0.56), offset = CFrame.new(t.X * 0.37, t.Y * 0.5 + 0.02, 0), color = C.NavyDark },
		{ name = "EpButtonL", size = Vector3.new(0.09, 0.05, 0.09), offset = CFrame.new(-t.X * 0.3, t.Y * 0.5 + 0.06, -t.Z * 0.15), color = C.Gold, material = Enum.Material.Metal },
		{ name = "EpButtonR", size = Vector3.new(0.09, 0.05, 0.09), offset = CFrame.new(t.X * 0.3, t.Y * 0.5 + 0.06, -t.Z * 0.15), color = C.Gold, material = Enum.Material.Metal },
	}
	wear(character, "UpperTorso", "guard_shirt_01", stub)
	-- Нашивка SECURITY на плечах (щит с золотой каймой)
	for _, side in { "Left", "Right" } do
		local a = sizeOf(character, side .. "UpperArm")
		local x = if side == "Left" then -a.X * 0.5 - 0.02 else a.X * 0.5 + 0.02
		wear(character, side .. "UpperArm", "guard_patch_01", {
			{ name = "Patch", size = Vector3.new(0.05, a.Y * 0.32, a.Z * 0.52), offset = CFrame.new(x, a.Y * 0.18, 0), color = C.Gold, material = Enum.Material.Metal },
			{ name = "Inner", size = Vector3.new(0.06, a.Y * 0.24, a.Z * 0.4), offset = CFrame.new(x, a.Y * 0.18, 0), color = C.NavyDark },
			{ name = "Chevron", size = Vector3.new(0.07, a.Y * 0.06, a.Z * 0.24), offset = CFrame.new(x, a.Y * 0.21, 0), color = C.Gold },
		})
	end
end

local function belt(character: Model)
	local l = sizeOf(character, "LowerTorso")
	wear(character, "LowerTorso", "guard_belt_01", {
		{ name = "Belt", size = Vector3.new(l.X * 1.05, math.min(0.26, l.Y * 0.6), l.Z * 1.06), offset = CFrame.new(0, l.Y * 0.18, 0), color = C.Black, material = Enum.Material.Leather },
		{ name = "Buckle", size = Vector3.new(0.34, math.min(0.24, l.Y * 0.54), 0.07), offset = CFrame.new(0, l.Y * 0.18, -l.Z * 0.53 - 0.02), color = C.Silver, material = Enum.Material.Metal },
		{ name = "KeeperL", size = Vector3.new(0.08, math.min(0.28, l.Y * 0.64), 0.08), offset = CFrame.new(-0.24, l.Y * 0.18, -l.Z * 0.53 - 0.01), color = C.Black, material = Enum.Material.Leather },
		{ name = "KeeperR", size = Vector3.new(0.08, math.min(0.28, l.Y * 0.64), 0.08), offset = CFrame.new(0.24, l.Y * 0.18, -l.Z * 0.53 - 0.01), color = C.Black, material = Enum.Material.Leather },
		{ name = "Keys", size = Vector3.new(0.18, 0.26, 0.06), offset = CFrame.new(-l.X * 0.2, -l.Y * 0.2, -l.Z * 0.55), color = C.Silver, material = Enum.Material.Metal },
		{ name = "CuffPouch", size = Vector3.new(0.42, 0.42, 0.22), offset = CFrame.new(l.X * 0.24, -0.1, l.Z * 0.54), color = C.Black, material = Enum.Material.Leather },
		{ name = "CuffFlap", size = Vector3.new(0.44, 0.12, 0.24), offset = CFrame.new(l.X * 0.24, 0.08, l.Z * 0.54), color = C.Leather, material = Enum.Material.Leather },
		{ name = "CuffSnap", size = Vector3.new(0.08, 0.08, 0.04), offset = CFrame.new(l.X * 0.24, 0.04, l.Z * 0.66), color = C.Silver, material = Enum.Material.Metal },
	})
end

---------------------------------------------------------------- классы

local function patrol(character: Model, _headBusy: boolean)
	local t = sizeOf(character, "UpperTorso")
	local band = function(y: number, name: string): { ModelLibrary.StubPart }
		return {
			{ name = name, size = Vector3.new(t.X * 1.03, t.Y * 0.11, t.Z * 1.06), offset = CFrame.new(0, y, 0), color = C.Lime },
			{ name = name .. "Shine", size = Vector3.new(t.X * 1.035, t.Y * 0.04, t.Z * 1.065), offset = CFrame.new(0, y, 0), color = C.Silver, material = Enum.Material.Metal, reflectance = 0.5 },
		}
	end
	local stub: Stub = {}
	for _, part in band(t.Y * 0.34, "ChestBand") do
		table.insert(stub, part)
	end
	for _, part in band(-t.Y * 0.4, "WaistBand") do
		table.insert(stub, part)
	end
	for _, x in { -t.X * 0.4, t.X * 0.4 } do
		table.insert(stub, { name = "Strap", size = Vector3.new(t.X * 0.09, t.Y * 0.64, 0.05), offset = CFrame.new(x, -t.Y * 0.03, -t.Z * 0.53), color = C.Lime })
		table.insert(stub, { name = "Strap", size = Vector3.new(t.X * 0.09, t.Y * 0.64, 0.05), offset = CFrame.new(x, -t.Y * 0.03, t.Z * 0.53), color = C.Lime })
	end
	-- Светоотражающий шеврон на спине (заметен издали и на камерах)
	table.insert(stub, { name = "BackChevronL", size = Vector3.new(t.X * 0.38, t.Y * 0.09, 0.05), offset = CFrame.new(-t.X * 0.14, t.Y * 0.04, t.Z * 0.53) * CFrame.Angles(0, 0, 0.45), color = C.Lime })
	table.insert(stub, { name = "BackChevronR", size = Vector3.new(t.X * 0.38, t.Y * 0.09, 0.05), offset = CFrame.new(t.X * 0.14, t.Y * 0.04, t.Z * 0.53) * CFrame.Angles(0, 0, -0.45), color = C.Lime })
	wear(character, "UpperTorso", "guard_patrol_stripes_01", stub)

	-- Светоотражающие кольца на руках и голенях
	for _, part in { "LeftUpperArm", "RightUpperArm", "LeftLowerLeg", "RightLowerLeg" } do
		local s = sizeOf(character, part)
		local y = if string.find(part, "Arm") then -s.Y * 0.28 else -s.Y * 0.12
		wear(character, part, "guard_patrol_band_01", {
			{ name = "Band", size = Vector3.new(s.X * 1.07, s.Y * 0.15, s.Z * 1.07), offset = CFrame.new(0, y, 0), color = C.Lime },
			{ name = "Shine", size = Vector3.new(s.X * 1.075, s.Y * 0.055, s.Z * 1.075), offset = CFrame.new(0, y, 0), color = C.Silver, material = Enum.Material.Metal, reflectance = 0.5 },
		})
	end
	-- Кроссовки: рельефная подошва, красный верх, скруглённый носок, боковые полосы, шнурки и пятка
	for _, foot in { "LeftFoot", "RightFoot" } do
		local f = sizeOf(character, foot)
		wear(character, foot, "guard_patrol_sneaker_01", {
			{ name = "Sole", size = Vector3.new(f.X * 1.14, f.Y * 0.42, f.Z * 1.22), offset = CFrame.new(0, -f.Y * 0.32, -f.Z * 0.06), color = C.White, material = Enum.Material.Rubber },
			{ name = "Tread", size = Vector3.new(f.X * 1.16, f.Y * 0.1, f.Z * 1.24), offset = CFrame.new(0, -f.Y * 0.48, -f.Z * 0.06), color = C.Black, material = Enum.Material.Rubber },
			{ name = "Upper", size = Vector3.new(f.X * 1.08, f.Y * 0.8, f.Z * 1.12), offset = CFrame.new(0, f.Y * 0.18, -f.Z * 0.03), color = C.Red },
			{ name = "Toe", size = Vector3.new(f.X * 1.04, f.Y * 0.58, f.Z * 0.36), offset = CFrame.new(0, f.Y * 0.02, -f.Z * 0.52), color = C.White, sphere = true },
			{ name = "Stripe", size = Vector3.new(f.X * 1.11, f.Y * 0.2, f.Z * 0.58), offset = CFrame.new(0, f.Y * 0.15, f.Z * 0.04) * CFrame.Angles(-0.22, 0, 0), color = C.White },
			{ name = "Tongue", size = Vector3.new(f.X * 0.54, f.Y * 0.42, 0.12), offset = CFrame.new(0, f.Y * 0.58, -f.Z * 0.32) * CFrame.Angles(-0.4, 0, 0), color = C.NavyDark, material = Enum.Material.Fabric },
			{ name = "Laces", size = Vector3.new(f.X * 0.46, 0.06, f.Z * 0.42), offset = CFrame.new(0, f.Y * 0.62, -f.Z * 0.18), color = C.White, material = Enum.Material.Fabric },
			{ name = "Heel", size = Vector3.new(f.X * 0.72, f.Y * 0.52, 0.09), offset = CFrame.new(0, f.Y * 0.25, f.Z * 0.58), color = C.Lime },
		})
	end
end

local function operator(character: Model, headBusy: boolean)
	local cup = hex("23262E")
	if not headBusy then
		-- Гарнитура: мягкая дуга, амбушюры, бирюзовые крышки, штанга микрофона и зелёный огонёк
		local h = sizeOf(character, "Head")
		wear(character, "Head", "guard_operator_headset_01", {
			{ name = "Band", size = Vector3.new(h.X * 0.92, 0.12, h.Z * 0.22), offset = CFrame.new(0, h.Y * 0.56, 0), color = cup },
			{ name = "BandPad", size = Vector3.new(h.X * 0.62, 0.08, h.Z * 0.24), offset = CFrame.new(0, h.Y * 0.52, 0), color = C.Black, material = Enum.Material.Fabric },
			{ name = "BandL", size = Vector3.new(0.12, h.Y * 0.44, h.Z * 0.18), offset = CFrame.new(-h.X * 0.5, h.Y * 0.36, 0) * CFrame.Angles(0, 0, -0.35), color = cup },
			{ name = "BandR", size = Vector3.new(0.12, h.Y * 0.44, h.Z * 0.18), offset = CFrame.new(h.X * 0.5, h.Y * 0.36, 0) * CFrame.Angles(0, 0, 0.35), color = cup },
			{ name = "EarPadL", size = Vector3.new(0.09, h.Y * 0.48, h.Y * 0.48), offset = CFrame.new(-h.X * 0.5, 0, 0), color = C.Black, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
			{ name = "EarPadR", size = Vector3.new(0.09, h.Y * 0.48, h.Y * 0.48), offset = CFrame.new(h.X * 0.5, 0, 0), color = C.Black, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
			{ name = "CupL", size = Vector3.new(0.18, h.Y * 0.44, h.Y * 0.44), offset = CFrame.new(-h.X * 0.58, 0, 0), color = cup, shape = Enum.PartType.Cylinder },
			{ name = "CupR", size = Vector3.new(0.18, h.Y * 0.44, h.Y * 0.44), offset = CFrame.new(h.X * 0.58, 0, 0), color = cup, shape = Enum.PartType.Cylinder },
			{ name = "CapL", size = Vector3.new(0.06, h.Y * 0.3, h.Y * 0.3), offset = CFrame.new(-h.X * 0.68, 0, 0), color = C.Screen, shape = Enum.PartType.Cylinder },
			{ name = "CapR", size = Vector3.new(0.06, h.Y * 0.3, h.Y * 0.3), offset = CFrame.new(h.X * 0.68, 0, 0), color = C.Screen, shape = Enum.PartType.Cylinder },
			{ name = "Boom", size = Vector3.new(0.06, 0.06, h.Z * 0.64), offset = CFrame.new(-h.X * 0.5, -h.Y * 0.18, -h.Z * 0.28) * CFrame.Angles(0, -0.5, 0), color = cup },
			{ name = "Mic", size = Vector3.new(0.18, 0.14, 0.14), offset = CFrame.new(-h.X * 0.32, -h.Y * 0.22, -h.Z * 0.56), color = C.Black, material = Enum.Material.Fabric, sphere = true },
			{ name = "Led", size = Vector3.new(0.05, 0.08, 0.08), offset = CFrame.new(-h.X * 0.71, h.Y * 0.12, -h.Z * 0.08), color = hex("38F28A"), material = Enum.Material.Neon },
		})
	else
		-- Голова занята (шапка, волосы) — гарнитура висит на шее
		local t = sizeOf(character, "UpperTorso")
		local y = t.Y * 0.5 + 0.08
		wear(character, "UpperTorso", "guard_operator_headset_neck_01", {
			{ name = "Band", size = Vector3.new(t.X * 0.44, 0.1, 0.12), offset = CFrame.new(0, y + 0.04, t.Z * 0.32), color = cup },
			{ name = "EarPadL", size = Vector3.new(0.08, 0.44, 0.44), offset = CFrame.new(-t.X * 0.2, y - 0.06, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = C.Black, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
			{ name = "EarPadR", size = Vector3.new(0.08, 0.44, 0.44), offset = CFrame.new(t.X * 0.2, y - 0.06, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = C.Black, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
			{ name = "CupL", size = Vector3.new(0.16, 0.4, 0.4), offset = CFrame.new(-t.X * 0.2, y, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = cup, shape = Enum.PartType.Cylinder },
			{ name = "CupR", size = Vector3.new(0.16, 0.4, 0.4), offset = CFrame.new(t.X * 0.2, y, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = cup, shape = Enum.PartType.Cylinder },
			{ name = "CapL", size = Vector3.new(0.05, 0.28, 0.28), offset = CFrame.new(-t.X * 0.2, y + 0.1, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = C.Screen, shape = Enum.PartType.Cylinder },
			{ name = "CapR", size = Vector3.new(0.05, 0.28, 0.28), offset = CFrame.new(t.X * 0.2, y + 0.1, -t.Z * 0.12) * CFrame.Angles(0, 0, math.pi / 2), color = C.Screen, shape = Enum.PartType.Cylinder },
			{ name = "Boom", size = Vector3.new(0.06, 0.06, 0.5), offset = CFrame.new(-t.X * 0.14, y + 0.02, -t.Z * 0.42) * CFrame.Angles(0, 0.4, 0), color = cup },
			{ name = "Mic", size = Vector3.new(0.16, 0.13, 0.13), offset = CFrame.new(-t.X * 0.06, y + 0.02, -t.Z * 0.62), color = C.Black, material = Enum.Material.Fabric, sphere = true },
		})
	end
	-- Планшет на поясе спереди слева: чехол, стилус, светящийся экран с камерой и индикатором REC
	local l = sizeOf(character, "LowerTorso")
	local front = -l.Z * 0.5 - 0.1
	local x = -l.X * 0.26
	local yTop = -l.Y * 0.1
	wear(character, "LowerTorso", "guard_operator_tablet_01", {
		{ name = "Case", size = Vector3.new(0.82, 1.02, 0.12), offset = CFrame.new(x, yTop - 0.45, front) * CFrame.Angles(0, 0, 0.12), color = C.Black, material = Enum.Material.Leather },
		{ name = "Tablet", size = Vector3.new(0.7, 0.88, 0.06), offset = CFrame.new(x, yTop - 0.43, front - 0.07) * CFrame.Angles(0, 0, 0.12), color = hex("2E3545") },
		{ name = "Screen", size = Vector3.new(0.6, 0.68, 0.02), offset = CFrame.new(x, yTop - 0.41, front - 0.105) * CFrame.Angles(0, 0, 0.12), color = C.Screen, material = Enum.Material.Neon },
		{ name = "ScreenCam", size = Vector3.new(0.22, 0.15, 0.02), offset = CFrame.new(x + 0.05, yTop - 0.34, front - 0.12) * CFrame.Angles(0, 0, 0.12), color = hex("1A5C8A"), material = Enum.Material.Neon },
		{ name = "ScreenLens", size = Vector3.new(0.02, 0.1, 0.1), offset = CFrame.new(x + 0.18, yTop - 0.33, front - 0.125) * CFrame.Angles(0, math.pi / 2, 0), color = C.NavyDark, shape = Enum.PartType.Cylinder },
		{ name = "ScreenBar", size = Vector3.new(0.46, 0.06, 0.02), offset = CFrame.new(x - 0.02, yTop - 0.62, front - 0.12) * CFrame.Angles(0, 0, 0.12), color = C.NavyDark },
		{ name = "Rec", size = Vector3.new(0.07, 0.07, 0.02), offset = CFrame.new(x - 0.16, yTop - 0.18, front - 0.12), color = hex("FF3B4E"), material = Enum.Material.Neon },
		{ name = "Stylus", size = Vector3.new(0.06, 0.62, 0.06), offset = CFrame.new(x + 0.41, yTop - 0.42, front - 0.04) * CFrame.Angles(0, 0, 0.12), color = C.Silver, material = Enum.Material.Metal },
		{ name = "Clip", size = Vector3.new(0.28, 0.34, 0.08), offset = CFrame.new(x, yTop + 0.08, front + 0.02), color = C.Silver, material = Enum.Material.Metal },
	})
end

-- Каска: купол, кант, козырёк, рёбра, наклейка и поднятые защитные очки на лбу.
local function hardhatStub(h: Vector3): Stub
	return {
		{ name = "Dome", size = Vector3.new(h.X * 1.16, h.Y * 0.84, h.Z * 1.16), offset = CFrame.new(0, h.Y * 0.32, 0), color = C.Yellow, sphere = true },
		{ name = "Rim", size = Vector3.new(0.08, h.X * 1.24, h.Z * 1.24), offset = CFrame.new(0, h.Y * 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), color = C.YellowDark, shape = Enum.PartType.Cylinder },
		{ name = "Visor", size = Vector3.new(h.X * 0.96, 0.08, h.Z * 0.44), offset = CFrame.new(0, h.Y * 0.12, -h.Z * 0.67), color = C.Yellow },
		{ name = "Ridge", size = Vector3.new(0.16, h.Y * 0.14, h.Z * 0.96), offset = CFrame.new(0, h.Y * 0.69, 0), color = C.YellowDark },
		{ name = "Sticker", size = Vector3.new(h.X * 0.32, h.Y * 0.17, 0.04), offset = CFrame.new(0, h.Y * 0.4, -h.Z * 0.57) * CFrame.Angles(-0.35, 0, 0), color = C.Navy },
		{ name = "Bolt", size = Vector3.new(0.08, 0.08, 0.04), offset = CFrame.new(0, h.Y * 0.4, -h.Z * 0.6) * CFrame.Angles(-0.35, 0, 0), color = C.Gold, material = Enum.Material.Metal },
		{ name = "GoggleBand", size = Vector3.new(h.X * 1.18, h.Y * 0.09, h.Z * 1.18), offset = CFrame.new(0, h.Y * 0.22, 0), color = C.Black, material = Enum.Material.Fabric },
		{ name = "LensL", size = Vector3.new(h.X * 0.28, h.Y * 0.15, 0.08), offset = CFrame.new(-h.X * 0.18, h.Y * 0.22, -h.Z * 0.61), color = C.Turquoise, material = Enum.Material.Glass, transparency = 0.55 },
		{ name = "LensR", size = Vector3.new(h.X * 0.28, h.Y * 0.15, 0.08), offset = CFrame.new(h.X * 0.18, h.Y * 0.22, -h.Z * 0.61), color = C.Turquoise, material = Enum.Material.Glass, transparency = 0.55 },
	}
end

local function technician(character: Model, headBusy: boolean)
	local h = sizeOf(character, "Head")
	local l = sizeOf(character, "LowerTorso")
	if not headBusy then
		wear(character, "Head", "guard_tech_hardhat_01", hardhatStub(h))
	else
		wear(character, "LowerTorso", "guard_tech_hardhat_clip_01", hardhatStub(h * 0.8),
			CFrame.new(-l.X * 0.24, -l.Y * 0.3 - 0.25, l.Z * 0.5 + 0.08) * CFrame.Angles(math.pi / 2, 0, 0))
	end
	local front = -l.Z * 0.5 - 0.17
	local back = l.Z * 0.5 + 0.15
	wear(character, "LowerTorso", "guard_tech_toolbelt_01", {
		{ name = "Belt", size = Vector3.new(l.X * 1.07, math.max(0.28, l.Y * 0.7), l.Z * 1.09), offset = CFrame.new(0, l.Y * 0.1, 0), color = C.Brown, material = Enum.Material.Leather },
		{ name = "Buckle", size = Vector3.new(0.36, 0.24, 0.08), offset = CFrame.new(0, l.Y * 0.1, -l.Z * 0.55 - 0.02), color = C.Silver, material = Enum.Material.Metal },
		{ name = "PouchL", size = Vector3.new(0.5, 0.6, 0.3), offset = CFrame.new(-l.X * 0.3, -0.25, front), color = C.BrownDark, material = Enum.Material.Leather },
		{ name = "PouchR", size = Vector3.new(0.5, 0.6, 0.3), offset = CFrame.new(l.X * 0.3, -0.25, front), color = C.BrownDark, material = Enum.Material.Leather },
		{ name = "FlapL", size = Vector3.new(0.52, 0.1, 0.32), offset = CFrame.new(-l.X * 0.3, 0.04, front), color = C.Brown, material = Enum.Material.Leather },
		{ name = "FlapR", size = Vector3.new(0.52, 0.1, 0.32), offset = CFrame.new(l.X * 0.3, 0.04, front), color = C.Brown, material = Enum.Material.Leather },
		-- Гаечный ключ с раздвоенной головкой
		{ name = "WrenchHandle", size = Vector3.new(0.12, 0.7, 0.07), offset = CFrame.new(l.X * 0.3 + 0.06, 0.2, front - 0.04) * CFrame.Angles(0, 0, -0.15), color = C.Steel, material = Enum.Material.Metal },
		{ name = "WrenchJawL", size = Vector3.new(0.11, 0.2, 0.08), offset = CFrame.new(l.X * 0.3 + 0.03, 0.56, front - 0.04) * CFrame.Angles(0, 0, -0.15), color = C.Steel, material = Enum.Material.Metal },
		{ name = "WrenchJawR", size = Vector3.new(0.11, 0.2, 0.08), offset = CFrame.new(l.X * 0.3 + 0.21, 0.54, front - 0.04) * CFrame.Angles(0, 0, -0.15), color = C.Steel, material = Enum.Material.Metal },
		-- Отвёртка с жёлтой ручкой и стальным жалом
		{ name = "DriverGrip", size = Vector3.new(0.15, 0.3, 0.15), offset = CFrame.new(-l.X * 0.3 - 0.1, 0.22, front - 0.04), color = C.Yellow, material = Enum.Material.Rubber },
		{ name = "DriverCollar", size = Vector3.new(0.17, 0.06, 0.17), offset = CFrame.new(-l.X * 0.3 - 0.1, 0.06, front - 0.04), color = C.Black, material = Enum.Material.Rubber },
		{ name = "DriverTip", size = Vector3.new(0.05, 0.32, 0.05), offset = CFrame.new(-l.X * 0.3 - 0.1, -0.06, front - 0.04), color = C.Steel, material = Enum.Material.Metal },
		-- Молоток с деревянной ручкой и гвоздодёром сзади
		{ name = "HammerHandle", size = Vector3.new(0.13, 0.8, 0.13), offset = CFrame.new(l.X * 0.22, -0.35, back), color = hex("A8763E"), material = Enum.Material.Wood },
		{ name = "HammerHead", size = Vector3.new(0.38, 0.18, 0.18), offset = CFrame.new(l.X * 0.16, 0.06, back), color = C.Steel, material = Enum.Material.Metal },
		{ name = "HammerClaw", size = Vector3.new(0.18, 0.16, 0.2), offset = CFrame.new(l.X * 0.36, 0.06, back) * CFrame.Angles(0, -math.pi / 2, 0), color = C.Steel, material = Enum.Material.Metal, wedge = true },
		-- Рулетка с металлической клипсой
		{ name = "Tape", size = Vector3.new(0.22, 0.44, 0.44), offset = CFrame.new(-l.X * 0.12, -0.2, back + 0.02) * CFrame.Angles(0, math.pi / 2, 0), color = C.Yellow, shape = Enum.PartType.Cylinder },
		{ name = "TapeClip", size = Vector3.new(0.06, 0.24, 0.12), offset = CFrame.new(-l.X * 0.12, -0.14, back - 0.1), color = C.Steel, material = Enum.Material.Metal },
	})
end

local function dogHandler(character: Model, _headBusy: boolean)
	local t = sizeOf(character, "UpperTorso")
	local front = -t.Z * 0.5 - 0.12
	local back = t.Z * 0.5 + 0.12
	local vest = wear(character, "UpperTorso", "guard_k9_vest_01", {
		{ name = "Front", size = Vector3.new(t.X * 0.92, t.Y * 0.84, 0.16), offset = CFrame.new(0, -t.Y * 0.05, front), color = C.K9, material = Enum.Material.Fabric },
		{ name = "FrontBevel", size = Vector3.new(t.X * 0.78, t.Y * 0.12, 0.15), offset = CFrame.new(0, t.Y * 0.42, front + 0.01), color = C.K9, material = Enum.Material.Fabric, wedge = true },
		{ name = "Back", size = Vector3.new(t.X * 0.94, t.Y * 0.86, 0.16), offset = CFrame.new(0, -t.Y * 0.04, back), color = C.K9, material = Enum.Material.Fabric },
		{ name = "StrapL", size = Vector3.new(t.X * 0.2, 0.12, t.Z * 1.28), offset = CFrame.new(-t.X * 0.28, t.Y * 0.47, 0), color = C.K9, material = Enum.Material.Fabric },
		{ name = "StrapR", size = Vector3.new(t.X * 0.2, 0.12, t.Z * 1.28), offset = CFrame.new(t.X * 0.28, t.Y * 0.47, 0), color = C.K9, material = Enum.Material.Fabric },
		{ name = "DRingL", size = Vector3.new(0.12, 0.08, 0.12), offset = CFrame.new(-t.X * 0.28, t.Y * 0.48, front + 0.04), color = C.Silver, material = Enum.Material.Metal },
		{ name = "DRingR", size = Vector3.new(0.12, 0.08, 0.12), offset = CFrame.new(t.X * 0.28, t.Y * 0.48, front + 0.04), color = C.Silver, material = Enum.Material.Metal },
		{ name = "SideL", size = Vector3.new(0.1, t.Y * 0.4, t.Z * 1.24), offset = CFrame.new(-t.X * 0.5 - 0.04, -t.Y * 0.2, 0), color = C.K9, material = Enum.Material.Fabric },
		{ name = "SideR", size = Vector3.new(0.1, t.Y * 0.4, t.Z * 1.24), offset = CFrame.new(t.X * 0.5 + 0.04, -t.Y * 0.2, 0), color = C.K9, material = Enum.Material.Fabric },
		{ name = "StripeFront", size = Vector3.new(t.X * 0.93, t.Y * 0.075, 0.17), offset = CFrame.new(0, -t.Y * 0.36, front - 0.005), color = C.K9Yellow },
		{ name = "StripeBack", size = Vector3.new(t.X * 0.95, t.Y * 0.075, 0.17), offset = CFrame.new(0, -t.Y * 0.36, back + 0.005), color = C.K9Yellow },
		{ name = "Patch", size = Vector3.new(t.X * 0.38, t.Y * 0.22, 0.04), offset = CFrame.new(t.X * 0.22, t.Y * 0.16, front - 0.09), color = C.K9Yellow },
		{ name = "Badge", size = Vector3.new(0.34, 0.38, 0.05), offset = CFrame.new(-t.X * 0.24, t.Y * 0.16, front - 0.1), color = C.Gold, material = Enum.Material.Metal },
		{ name = "BadgeCore", size = Vector3.new(0.22, 0.24, 0.06), offset = CFrame.new(-t.X * 0.24, t.Y * 0.16, front - 0.11), color = C.NavyDark },
		{ name = "BackLabel", size = Vector3.new(t.X * 0.8, t.Y * 0.4, 0.02), offset = CFrame.new(0, t.Y * 0.1, back + 0.09), color = C.K9, material = Enum.Material.Fabric },
		{ name = "GrabHandle", size = Vector3.new(t.X * 0.34, 0.08, 0.1), offset = CFrame.new(0, t.Y * 0.36, back + 0.12), color = C.Black, material = Enum.Material.Fabric },
		{ name = "Whistle", size = Vector3.new(0.11, 0.11, 0.32), offset = CFrame.new(t.X * 0.05, t.Y * 0.3, front - 0.12), color = C.Silver, material = Enum.Material.Metal },
	})
	label(vest, "Patch", Enum.NormalId.Front, "K-9", C.K9)
	label(vest, "BackLabel", Enum.NormalId.Back, "K-9", C.K9Yellow)

	local l = sizeOf(character, "LowerTorso")
	local lf = -l.Z * 0.5 - 0.12
	local x = -l.X * 0.28
	wear(character, "LowerTorso", "guard_k9_leash_01", {
		{ name = "Coil", size = Vector3.new(0.18, 0.64, 0.64), offset = CFrame.new(x, -0.3, lf) * CFrame.Angles(0, math.pi / 2, 0), color = C.Red, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "CoilHole", size = Vector3.new(0.2, 0.3, 0.3), offset = CFrame.new(x, -0.3, lf) * CFrame.Angles(0, math.pi / 2, 0), color = C.Navy, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "Clip", size = Vector3.new(0.13, 0.28, 0.08), offset = CFrame.new(x, 0.05, lf + 0.02), color = C.Silver, material = Enum.Material.Metal },
		{ name = "Tail", size = Vector3.new(0.08, 0.72, 0.06), offset = CFrame.new(x + 0.2, -0.85, lf - 0.02) * CFrame.Angles(0, 0, 0.12), color = C.Red, material = Enum.Material.Fabric },
		{ name = "Hook", size = Vector3.new(0.12, 0.18, 0.08), offset = CFrame.new(x + 0.24, -1.25, lf - 0.02), color = C.Silver, material = Enum.Material.Metal },
		{ name = "TreatBag", size = Vector3.new(0.44, 0.44, 0.28), offset = CFrame.new(l.X * 0.26, -0.22, l.Z * 0.5 + 0.15), color = hex("2E9E5B"), material = Enum.Material.Fabric },
		{ name = "TreatFlap", size = Vector3.new(0.46, 0.1, 0.3), offset = CFrame.new(l.X * 0.26, 0.02, l.Z * 0.5 + 0.15), color = hex("23794A"), material = Enum.Material.Fabric },
		{ name = "TreatSnap", size = Vector3.new(0.08, 0.08, 0.04), offset = CFrame.new(l.X * 0.26, -0.02, l.Z * 0.5 + 0.31), color = C.Gold, material = Enum.Material.Metal },
	})
end

local function assault(character: Model, _headBusy: boolean)
	local t = sizeOf(character, "UpperTorso")
	-- Толще бронежилета из оружейной (WeaponModels.vestSpecs): купленный прячется внутри и не мерцает
	local front = -t.Z * 0.5 - 0.17
	local back = t.Z * 0.5 + 0.17
	local stub: Stub = {
		{ name = "FrontPlate", size = Vector3.new(t.X * 0.98, t.Y * 0.88, 0.3), offset = CFrame.new(0, -t.Y * 0.04, front), color = C.Armor, material = Enum.Material.Fabric },
		{ name = "FrontBevel", size = Vector3.new(t.X * 0.82, t.Y * 0.14, 0.28), offset = CFrame.new(0, t.Y * 0.44, front + 0.01), color = C.Armor, material = Enum.Material.Fabric, wedge = true },
		{ name = "BackPlate", size = Vector3.new(t.X * 1.0, t.Y * 0.9, 0.3), offset = CFrame.new(0, -t.Y * 0.03, back), color = C.Armor, material = Enum.Material.Fabric },
		{ name = "BackBevel", size = Vector3.new(t.X * 0.84, t.Y * 0.14, 0.28), offset = CFrame.new(0, t.Y * 0.45, back - 0.01) * CFrame.Angles(0, math.pi, 0), color = C.Armor, material = Enum.Material.Fabric, wedge = true },
		{ name = "SideL", size = Vector3.new(0.18, t.Y * 0.56, t.Z * 1.36), offset = CFrame.new(-t.X * 0.5 - 0.08, -t.Y * 0.16, 0), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "SideR", size = Vector3.new(0.18, t.Y * 0.56, t.Z * 1.36), offset = CFrame.new(t.X * 0.5 + 0.08, -t.Y * 0.16, 0), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "CollarFront", size = Vector3.new(t.X * 0.62, 0.24, 0.16), offset = CFrame.new(0, t.Y * 0.5 + 0.04, -t.Z * 0.5 - 0.06), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "CollarBack", size = Vector3.new(t.X * 0.66, 0.3, 0.16), offset = CFrame.new(0, t.Y * 0.5 + 0.07, t.Z * 0.5 + 0.06), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "PadL", size = Vector3.new(t.X * 0.32, 0.24, t.Z * 1.22), offset = CFrame.new(-t.X * 0.42, t.Y * 0.5 + 0.1, 0) * CFrame.Angles(0, 0, 0.2), color = C.Armor, material = Enum.Material.Fabric },
		{ name = "PadR", size = Vector3.new(t.X * 0.32, 0.24, t.Z * 1.22), offset = CFrame.new(t.X * 0.42, t.Y * 0.5 + 0.1, 0) * CFrame.Angles(0, 0, -0.2), color = C.Armor, material = Enum.Material.Fabric },
		{ name = "PadTrimL", size = Vector3.new(t.X * 0.33, 0.06, t.Z * 1.24), offset = CFrame.new(-t.X * 0.42, t.Y * 0.5 + 0.02, 0) * CFrame.Angles(0, 0, 0.2), color = C.K9Yellow },
		{ name = "PadTrimR", size = Vector3.new(t.X * 0.33, 0.06, t.Z * 1.24), offset = CFrame.new(t.X * 0.42, t.Y * 0.5 + 0.02, 0) * CFrame.Angles(0, 0, -0.2), color = C.K9Yellow },
		{ name = "TrimFront", size = Vector3.new(t.X * 0.99, 0.08, 0.31), offset = CFrame.new(0, -t.Y * 0.47, front), color = C.K9Yellow },
		{ name = "TrimBack", size = Vector3.new(t.X * 1.01, 0.08, 0.31), offset = CFrame.new(0, -t.Y * 0.47, back), color = C.K9Yellow },
		{ name = "Badge", size = Vector3.new(0.36, 0.4, 0.05), offset = CFrame.new(-t.X * 0.28, t.Y * 0.2, front - 0.17), color = C.Gold, material = Enum.Material.Metal },
		{ name = "BadgeCore", size = Vector3.new(0.24, 0.26, 0.06), offset = CFrame.new(-t.X * 0.28, t.Y * 0.2, front - 0.18), color = C.NavyDark },
		{ name = "FrontPatch", size = Vector3.new(t.X * 0.34, t.Y * 0.14, 0.04), offset = CFrame.new(0, t.Y * 0.35, front - 0.16), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "Radio", size = Vector3.new(0.24, 0.4, 0.16), offset = CFrame.new(t.X * 0.28, t.Y * 0.2, front - 0.22), color = C.Black },
		{ name = "Antenna", size = Vector3.new(0.05, 0.44, 0.05), offset = CFrame.new(t.X * 0.33, t.Y * 0.5, front - 0.22), color = C.Black },
		{ name = "RadioLed", size = Vector3.new(0.05, 0.05, 0.04), offset = CFrame.new(t.X * 0.22, t.Y * 0.36, front - 0.22), color = hex("38F28A"), material = Enum.Material.Neon },
		{ name = "DragHandle", size = Vector3.new(t.X * 0.36, 0.09, 0.12), offset = CFrame.new(0, t.Y * 0.38, back + 0.18), color = C.ArmorDark, material = Enum.Material.Fabric },
		{ name = "BackLabel", size = Vector3.new(t.X * 0.86, t.Y * 0.28, 0.02), offset = CFrame.new(0, t.Y * 0.16, back + 0.16), color = C.Armor, material = Enum.Material.Fabric },
	}
	for index = -1, 1 do
		local x = index * t.X * 0.29
		table.insert(stub, { name = "Pouch", size = Vector3.new(t.X * 0.24, t.Y * 0.3, 0.22), offset = CFrame.new(x, -t.Y * 0.24, front - 0.25), color = C.ArmorDark, material = Enum.Material.Fabric })
		table.insert(stub, { name = "Flap", size = Vector3.new(t.X * 0.25, t.Y * 0.07, 0.23), offset = CFrame.new(x, -t.Y * 0.1, front - 0.255), color = C.Armor, material = Enum.Material.Fabric })
		table.insert(stub, { name = "Mag", size = Vector3.new(t.X * 0.14, t.Y * 0.08, 0.12), offset = CFrame.new(x, -t.Y * 0.04, front - 0.25), color = C.Black })
	end
	local vest = wear(character, "UpperTorso", "guard_assault_vest_01", stub)
	label(vest, "FrontPatch", Enum.NormalId.Front, "SECURITY", C.K9Yellow, 80)
	label(vest, "BackLabel", Enum.NormalId.Back, "SECURITY", C.White)

	-- Наколенники: чёрная подушка, фасочная стально-синяя чашка с заклёпками, ремешок
	for _, leg in { "LeftLowerLeg", "RightLowerLeg" } do
		local s = sizeOf(character, leg)
		local y = s.Y * 0.34
		wear(character, leg, "guard_assault_kneepad_01", {
			{ name = "Pad", size = Vector3.new(s.X * 0.88, s.Y * 0.35, 0.26), offset = CFrame.new(0, y, -s.Z * 0.5 - 0.06), color = C.Black, material = Enum.Material.Rubber },
			{ name = "Cap", size = Vector3.new(s.X * 0.64, s.Y * 0.24, 0.1), offset = CFrame.new(0, y + 0.02, -s.Z * 0.5 - 0.22), color = C.Armor },
			{ name = "RivetL", size = Vector3.new(0.06, 0.06, 0.04), offset = CFrame.new(-s.X * 0.24, y + 0.02, -s.Z * 0.5 - 0.26), color = C.Silver, material = Enum.Material.Metal },
			{ name = "RivetR", size = Vector3.new(0.06, 0.06, 0.04), offset = CFrame.new(s.X * 0.24, y + 0.02, -s.Z * 0.5 - 0.26), color = C.Silver, material = Enum.Material.Metal },
			{ name = "Strap", size = Vector3.new(s.X * 1.06, 0.1, s.Z * 1.06), offset = CFrame.new(0, y - s.Y * 0.1, 0), color = C.Black, material = Enum.Material.Fabric },
		})
	end
end

local CLASS_KITS: { [string]: (Model, boolean) -> () } = {
	[GameState.Role.Patrol] = patrol,
	[GameState.Role.Operator] = operator,
	[GameState.Role.Technician] = technician,
	[GameState.Role.DogHandler] = dogHandler,
	[GameState.Role.Assault] = assault,
}

---------------------------------------------------------------- переодевание

-- Снимает рубашку, ремень и костюм класса (значок и тело не трогает).
local function undress(character: Model)
	for _, child in character:GetChildren() do
		if child:GetAttribute(KIT_ATTR) then
			child:Destroy()
		end
	end
end

-- Рубашка, ремень и костюм класса role. Персонаж может быть и копией игрока (Фальшивый охранник).
function Uniform.dressClass(character: Model, role: string)
	undress(character)
	if not character:FindFirstChild("UpperTorso") then
		return -- не R15: на старом теле детали не встанут
	end
	shirt(character)
	if role ~= GameState.Role.Technician then
		belt(character) -- у техника вместо ремня пояс с инструментами
	end
	local kit = CLASS_KITS[role] or patrol
	kit(character, headIsBusy(character))
end

-- Значок охраны на груди.
function Uniform.badge(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:AddAccessory(ModelLibrary.accessory(MapSchema.Models.GuardBadge, BADGE_STUB, "BodyFrontAttachment"))
	end
end

-- Надевает форму на персонажа (после CharacterAppearanceLoaded, когда одежда уже пришла).
function Uniform.apply(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, child in character:GetChildren() do
		if (child:IsA("Accessory") and not isHeadAccessory(child)) or child:IsA("Clothing") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.TorsoColor3 = Config.Uniform.Torso
		bodyColors.LeftArmColor3 = Config.Uniform.Arms
		bodyColors.RightArmColor3 = Config.Uniform.Arms
		bodyColors.LeftLegColor3 = Config.Uniform.Legs
		bodyColors.RightLegColor3 = Config.Uniform.Legs
	end
	Uniform.badge(character)
	local player = Players:GetPlayerFromCharacter(character)
	Uniform.dressClass(character, if player then GameState.roleOf(player) else Config.Classes.Default)
end

-- Класс игрока поменялся (карточки в лобби или в хабе) — переодеть текущего персонажа.
-- Возвращает подключение: отключить, когда игрок вышел.
function Uniform.watch(player: Player): RBXScriptConnection
	return player:GetAttributeChangedSignal(GameState.PlayerAttr.Role):Connect(function()
		local character = player.Character
		if character and character.Parent and player:HasAppearanceLoaded() then
			Uniform.dressClass(character, GameState.roleOf(player))
		end
	end)
end

return Uniform
