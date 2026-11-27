-- Внешний вид воров (блок 3, ремодель R2). Тело — стандартный персонаж Roblox из HumanoidDescription
-- (цвета частей тела, размеры), снаряжение — детали кодом (заглушки ModelLibrary: модель друга с тем же именем
-- заменит заглушку). Все детали крепятся Weld с явным C0 к костям тела; анимации — на клиентах (NpcAnimator).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local Uniform = require(Server:WaitForChild("Uniform"))
local ProgressService = require(Server:WaitForChild("ProgressService"))

local ThiefKinds = {}

type StubPart = ModelLibrary.StubPart

local SKIN = Color3.fromHex("F5CDA8")
local DARK = Color3.fromHex("111111")
local WHITE = Color3.fromHex("F4F4F0")
local GOLD = Color3.fromHex("D4A93A")
local STEEL = Color3.fromHex("A9B0BC")
local STEEL_DARK = Color3.fromHex("3A414E")
local LEATHER = Color3.fromHex("6B4A2E")
local LEATHER_DARK = Color3.fromHex("462F1C")
local TURQUOISE = Color3.fromHex("3BC6C1")
local RED = Color3.fromHex("C8343A")
local MARBLE = Color3.fromHex("E8DCC4")
local NAVY = Color3.fromHex("1E2A44")

local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)

export type Look = {
	head: Color3,
	torso: Color3,
	arms: Color3,
	legs: Color3,
	scale: number?, -- общий размер (Громила крупнее)
	width: number?, -- шире в плечах
}

-- Персонаж из HumanoidDescription с цветами и размерами.
function ThiefKinds.rig(look: Look): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = look.head
	description.TorsoColor = look.torso
	description.LeftArmColor = look.arms
	description.RightArmColor = look.arms
	description.LeftLegColor = look.legs
	description.RightLegColor = look.legs
	local scale = look.scale or 1
	description.HeightScale = scale
	description.HeadScale = scale
	description.DepthScale = scale * (look.width or 1)
	description.WidthScale = scale * (look.width or 1)
	local model = ModelLibrary.createRig(description)
	description:Destroy()
	return model
end

-- Деталь снаряжения на части тела. offset — относительно центра этой части (для головы −Z — лицо,
-- для кисти −Y — к пальцам). Приваривается Weld с явным C0, поэтому держится, где бы ни стоял вор.
function ThiefKinds.attach(model: Model, partName: string, name: string, stub: { StubPart }, offset: CFrame): Instance?
	return ModelLibrary.attachTo(model, partName, name, stub, offset)
end

---------------------------------------------------------------- помощники деталей

local function sizeOf(model: Model, partName: string): Vector3
	local part = model:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part.Size else Vector3.new(1, 1, 1)
end

local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): StubPart
	return { name = name, size = size, offset = offset, color = color, material = material }
end

local function sphere(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): StubPart
	return { name = name, size = size, offset = offset, color = color, material = material, sphere = true }
end

local function cyl(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): StubPart
	return { name = name, size = size, offset = offset, color = color, material = material, shape = CYL }
end

local function ball(name: string, d: number, offset: CFrame, color: Color3, material: Enum.Material?): StubPart
	return { name = name, size = Vector3.new(d, d, d), offset = offset, color = color, material = material, shape = BALL }
end

local function wedge(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): StubPart
	return { name = name, size = size, offset = offset, color = color, material = material, wedge = true }
end

local function addSurfaceLabel(prop: Instance?, partName: string, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number?)
	local target = prop and prop:FindFirstChild(partName, true)
	if not (target and target:IsA("BasePart")) or target:FindFirstChildOfClass("SurfaceGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 60
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Parent = gui
	gui.Parent = target
end

-- Очки на маске/каске: тёмная оправа, тонированная подложка и стеклянные линзы (прозрачность 0.55).
local function addGoggles(stub: { StubPart }, h: Vector3, y: number, z: number, tint: Color3, frameColor: Color3)
	table.insert(stub, part("GoggleBand", Vector3.new(h.X * 1.1, h.Y * 0.12, h.Z * 1.1), CFrame.new(0, y, 0), DARK, M.Fabric))
	table.insert(stub, part("GoggleBridge", Vector3.new(h.X * 0.18, h.Y * 0.08, 0.09), CFrame.new(0, y + 0.02, z), frameColor, M.Rubber))
	for _, side in { -1, 1 } do
		local x = side * h.X * 0.2
		table.insert(stub, part("GoggleFrame", Vector3.new(h.X * 0.34, h.Y * 0.25, 0.12), CFrame.new(x, y + 0.02, z), frameColor, M.Rubber))
		table.insert(stub, part("GoggleTint", Vector3.new(h.X * 0.26, h.Y * 0.17, 0.04), CFrame.new(x, y + 0.02, z - 0.035), tint, M.SmoothPlastic))
		table.insert(stub, {
			name = if side < 0 then "LensL" else "LensR",
			size = Vector3.new(h.X * 0.28, h.Y * 0.19, 0.06),
			offset = CFrame.new(x, y + 0.02, z - 0.06),
			color = tint,
			material = M.Glass,
			transparency = 0.55,
		})
	end
end

-- Перчатки на обе кисти: облегающий корпус, защитная накладка на костяшки и манжета.
local function gloves(model: Model, name: string, color: Color3, material: Enum.Material?, knuckleColor: Color3?)
	local mat = material or M.Fabric
	local cuffColor = color:Lerp(Color3.new(0, 0, 0), 0.28)
	for _, hand in { "LeftHand", "RightHand" } do
		local g = sizeOf(model, hand)
		ThiefKinds.attach(model, hand, name, {
			part("Glove", Vector3.new(g.X * 1.16, g.Y * 1.28, g.Z * 1.16), CFrame.identity, color, mat),
			part("Cuff", Vector3.new(g.X * 1.24, g.Y * 0.42, g.Z * 1.24), CFrame.new(0, g.Y * 0.58, 0), cuffColor, mat),
			part("Knuckle", Vector3.new(g.X * 1.05, g.Y * 0.24, g.Z * 0.22), CFrame.new(0, -g.Y * 0.15, -g.Z * 0.54), knuckleColor or cuffColor, M.Rubber),
		}, CFrame.identity)
	end
end

-- Ботинки на обе ступни: верх, округлый носок, толстая подошва, шнуровка и манжета.
local function boots(model: Model, name: string, color: Color3, sole: Color3)
	for _, foot in { "LeftFoot", "RightFoot" } do
		local f = sizeOf(model, foot)
		ThiefKinds.attach(model, foot, name, {
			part("Boot", Vector3.new(f.X * 1.1, f.Y * 1.08, f.Z * 1.12), CFrame.new(0, f.Y * 0.06, -f.Z * 0.03), color, M.Leather),
			sphere("Toe", Vector3.new(f.X * 1.06, f.Y * 0.72, f.Z * 0.44), CFrame.new(0, -f.Y * 0.06, -f.Z * 0.46), color, M.Leather),
			part("Sole", Vector3.new(f.X * 1.16, f.Y * 0.34, f.Z * 1.22), CFrame.new(0, -f.Y * 0.36, -f.Z * 0.06), sole, M.Rubber),
			part("Laces", Vector3.new(f.X * 0.44, 0.06, f.Z * 0.38), CFrame.new(0, f.Y * 0.6, -f.Z * 0.18), sole, M.Fabric),
		}, CFrame.identity)
	end
end

-- Глаза в прорезях маски: белок и чуть скошенный зрачок.
local function eyes(stub: { StubPart }, h: Vector3, y: number, z: number)
	for _, side in { -1, 1 } do
		table.insert(stub, part("Eye", Vector3.new(h.X * 0.17, h.Y * 0.14, 0.04), CFrame.new(side * h.X * 0.18, y, z), WHITE))
		table.insert(stub, part("Pupil", Vector3.new(h.X * 0.08, h.Y * 0.09, 0.04), CFrame.new(side * h.X * 0.18 + h.X * 0.03, y - h.Y * 0.01, z - 0.02), DARK))
	end
end

---------------------------------------------------------------- виды воров

-- 1. Карманник: чёрная шапка с отворотом и пуговицей, маска-домино с завязками и хитрыми глазами,
-- полосатая кофта с воротником, диагональный ремень с пряжкой, вместительная сумка с эмблемой «$» и отмычки.
local function pickpocket(): Model?
	local color = Config.ThiefTypes.Pickpocket.Color
	local model = ThiefKinds.rig({ head = SKIN, torso = color, arms = color, legs = color })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local black = Color3.fromHex("0C0C0C")
	local mask: { StubPart } = {
		sphere("Beanie", Vector3.new(h.X * 1.12, h.Y * 0.8, h.Z * 1.12), CFrame.new(0, h.Y * 0.3, 0.02), color, M.Fabric),
		part("Cuff", Vector3.new(h.X * 1.15, h.Y * 0.2, h.Z * 1.15), CFrame.new(0, h.Y * 0.2, 0), Color3.fromHex("2A2E38"), M.Fabric),
		ball("CrownButton", 0.14, CFrame.new(0, h.Y * 0.71, 0.02), Color3.fromHex("2A2E38"), M.Fabric),
		part("Band", Vector3.new(h.X * 1.07, h.Y * 0.25, h.Z * 1.07), CFrame.new(0, h.Y * 0.02, 0), black, M.Fabric),
		wedge("MaskBridge", Vector3.new(h.X * 0.22, h.Y * 0.14, 0.12), CFrame.new(0, -h.Y * 0.06, -h.Z * 0.54) * CFrame.Angles(math.pi, 0, 0), black, M.Fabric),
		ball("Knot", 0.16, CFrame.new(0, h.Y * 0.02, h.Z * 0.56), black, M.Fabric),
		part("KnotL", Vector3.new(h.X * 0.11, h.Y * 0.32, 0.05), CFrame.new(-h.X * 0.11, -h.Y * 0.1, h.Z * 0.57) * CFrame.Angles(0, 0, 0.42), black, M.Fabric),
		part("KnotR", Vector3.new(h.X * 0.11, h.Y * 0.32, 0.05), CFrame.new(h.X * 0.11, -h.Y * 0.1, h.Z * 0.57) * CFrame.Angles(0, 0, -0.42), black, M.Fabric),
		part("BrowL", Vector3.new(h.X * 0.22, 0.04, 0.04), CFrame.new(-h.X * 0.18, h.Y * 0.14, -h.Z * 0.55) * CFrame.Angles(0, 0, -0.2), DARK),
		part("BrowR", Vector3.new(h.X * 0.22, 0.04, 0.04), CFrame.new(h.X * 0.18, h.Y * 0.14, -h.Z * 0.55) * CFrame.Angles(0, 0, 0.2), DARK),
		part("Grin", Vector3.new(h.X * 0.32, h.Y * 0.05, 0.04), CFrame.new(h.X * 0.04, -h.Y * 0.27, -h.Z * 0.5) * CFrame.Angles(0, 0, 0.14), Color3.fromHex("6A3A2A")),
	}
	eyes(mask, h, h.Y * 0.03, -h.Z * 0.55)
	ThiefKinds.attach(model, "Head", MapSchema.Models.ThiefMask, mask, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	local shirt: { StubPart } = {
		cyl("Collar", Vector3.new(0.18, t.X * 0.54, t.Z * 0.94), CFrame.new(0, t.Y * 0.5, 0) * ALONG_Y, Color3.fromHex("242428"), M.Fabric),
		part("Strap", Vector3.new(0.18, t.Y * 1.38, 0.06), CFrame.new(0, 0, -t.Z * 0.55) * CFrame.Angles(0, 0, 0.75), LEATHER, M.Leather),
		part("StrapBack", Vector3.new(0.18, t.Y * 1.38, 0.06), CFrame.new(0, 0, t.Z * 0.55) * CFrame.Angles(0, 0, -0.75), LEATHER, M.Leather),
		part("StrapPad", Vector3.new(0.26, 0.38, 0.09), CFrame.new(-t.X * 0.28, t.Y * 0.32, -t.Z * 0.56) * CFrame.Angles(0, 0, 0.75), LEATHER_DARK, M.Leather),
		part("StrapBuckle", Vector3.new(0.24, 0.14, 0.09), CFrame.new(t.X * 0.12, -t.Y * 0.14, -t.Z * 0.57) * CFrame.Angles(0, 0, 0.75), GOLD, M.Metal),
	}
	for index = 0, 3 do
		table.insert(shirt, part("Stripe", Vector3.new(t.X * 1.02, t.Y * 0.09, t.Z * 1.04), CFrame.new(0, t.Y * (0.32 - index * 0.22), 0), WHITE, M.Fabric))
	end
	ThiefKinds.attach(model, "UpperTorso", "thief_pickpocket_shirt_01", shirt, CFrame.identity)

	for _, arm in { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" } do
		local a = sizeOf(model, arm)
		ThiefKinds.attach(model, arm, "thief_pickpocket_sleeve_01", {
			part("Stripe", Vector3.new(a.X * 1.05, a.Y * 0.14, a.Z * 1.05), CFrame.new(0, a.Y * 0.18, 0), WHITE, M.Fabric),
			part("Stripe", Vector3.new(a.X * 1.05, a.Y * 0.14, a.Z * 1.05), CFrame.new(0, -a.Y * 0.22, 0), WHITE, M.Fabric),
		}, CFrame.identity)
	end

	local l = sizeOf(model, "LowerTorso")
	local bagX = l.X * 0.62
	local bagProp = ThiefKinds.attach(model, "LowerTorso", "thief_pickpocket_bag_01", {
		sphere("Bag", Vector3.new(0.46, 0.84, 0.96), CFrame.new(bagX, -0.26, 0.05), Color3.fromHex("9E7B4F"), M.Fabric),
		part("Flap", Vector3.new(0.48, 0.34, 0.94), CFrame.new(bagX + 0.02, 0.02, 0.05) * CFrame.Angles(0, 0, -0.06), LEATHER, M.Leather),
		part("Buckle", Vector3.new(0.08, 0.16, 0.22), CFrame.new(bagX + 0.26, -0.08, 0.05), GOLD, M.Metal),
		part("DollarBadge", Vector3.new(0.04, 0.32, 0.32), CFrame.new(bagX + 0.24, -0.34, 0.05), MARBLE, M.Fabric),
		part("LockPickLoop", Vector3.new(0.1, 0.18, 0.08), CFrame.new(-l.X * 0.26, 0.12, -l.Z * 0.56), LEATHER, M.Leather),
		cyl("Ring", Vector3.new(0.04, 0.22, 0.22), CFrame.new(-l.X * 0.26, 0.05, -l.Z * 0.59) * ALONG_Z, GOLD, M.Metal),
		part("Picks", Vector3.new(0.16, 0.36, 0.04), CFrame.new(-l.X * 0.29, -0.14, -l.Z * 0.58) * CFrame.Angles(0, 0, 0.12), STEEL, M.Metal),
		part("PickTension", Vector3.new(0.08, 0.3, 0.04), CFrame.new(-l.X * 0.2, -0.12, -l.Z * 0.58) * CFrame.Angles(0, 0, -0.15), GOLD, M.Metal),
	}, CFrame.identity)
	addSurfaceLabel(bagProp, "DollarBadge", Enum.NormalId.Right, "$", Color3.fromHex("2E9E5B"), 90)
	gloves(model, "thief_glove_01", Color3.fromHex("0E0E0E"), M.Leather)
	boots(model, "thief_boot_01", Color3.fromHex("1E1E1E"), Color3.fromHex("3A3A3A"))
	return model
end

-- 2. Взломщик: бордовая балаклава с прорезью и тактическими бирюзовыми очками на лбу,
-- тёмно-красный комбинезон на молнии с карманами и наплечниками, пояс с баллончиком и кусачками,
-- большая красная монтировка со стальным крюком-гвоздодёром.
local function breaker(): Model?
	local color = Config.ThiefTypes.Breaker.Color
	local model = ThiefKinds.rig({ head = SKIN, torso = color, arms = color, legs = color })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local dark = Color3.fromHex("461313")
	local mask: { StubPart } = {
		sphere("Balaclava", Vector3.new(h.X * 1.1, h.Y * 1.08, h.Z * 1.1), CFrame.new(0, h.Y * 0.02, 0), Color3.fromHex("2E0F12"), M.Fabric),
		cyl("NeckGaiter", Vector3.new(0.16, h.X * 0.96, h.Z * 0.96), CFrame.new(0, -h.Y * 0.48, 0) * ALONG_Y, dark, M.Fabric),
		part("EyeSlit", Vector3.new(h.X * 0.68, h.Y * 0.2, 0.05), CFrame.new(0, h.Y * 0.05, -h.Z * 0.53), SKIN),
		part("Seam", Vector3.new(0.06, h.Y * 0.55, h.Z * 0.92), CFrame.new(0, h.Y * 0.36, h.Z * 0.1), dark, M.Fabric),
	}
	eyes(mask, h, h.Y * 0.05, -h.Z * 0.56)
	addGoggles(mask, h, h.Y * 0.34, -h.Z * 0.54, TURQUOISE, STEEL_DARK)
	ThiefKinds.attach(model, "Head", "thief_breaker_mask_01", mask, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", "thief_breaker_suit_01", {
		part("Zip", Vector3.new(0.07, t.Y * 0.96, 0.05), CFrame.new(0, 0, -t.Z * 0.52), STEEL, M.Metal),
		part("ZipPull", Vector3.new(0.11, 0.16, 0.06), CFrame.new(0, t.Y * 0.28, -t.Z * 0.55), GOLD, M.Metal),
		part("PocketL", Vector3.new(t.X * 0.25, t.Y * 0.22, 0.07), CFrame.new(-t.X * 0.24, t.Y * 0.14, -t.Z * 0.52), dark, M.Fabric),
		part("PocketR", Vector3.new(t.X * 0.25, t.Y * 0.22, 0.07), CFrame.new(t.X * 0.24, t.Y * 0.14, -t.Z * 0.52), dark, M.Fabric),
		part("FlapL", Vector3.new(t.X * 0.26, t.Y * 0.07, 0.08), CFrame.new(-t.X * 0.24, t.Y * 0.27, -t.Z * 0.53), color, M.Fabric),
		part("FlapR", Vector3.new(t.X * 0.26, t.Y * 0.07, 0.08), CFrame.new(t.X * 0.24, t.Y * 0.27, -t.Z * 0.53), color, M.Fabric),
		part("Collar", Vector3.new(t.X * 0.54, 0.18, t.Z * 1.05), CFrame.new(0, t.Y * 0.5, 0), dark, M.Fabric),
		part("ShoulderPadL", Vector3.new(t.X * 0.24, 0.09, t.Z * 0.9), CFrame.new(-t.X * 0.42, t.Y * 0.5 + 0.02, 0), Color3.fromHex("2A1416"), M.Rubber),
		part("ShoulderPadR", Vector3.new(t.X * 0.24, 0.09, t.Z * 0.9), CFrame.new(t.X * 0.42, t.Y * 0.5 + 0.02, 0), Color3.fromHex("2A1416"), M.Rubber),
	}, CFrame.identity)

	local l = sizeOf(model, "LowerTorso")
	ThiefKinds.attach(model, "LowerTorso", "thief_breaker_belt_01", {
		part("Belt", Vector3.new(l.X * 1.07, math.max(0.28, l.Y * 0.65), l.Z * 1.09), CFrame.new(0, l.Y * 0.1, 0), DARK, M.Leather),
		part("Buckle", Vector3.new(0.32, 0.22, 0.08), CFrame.new(0, l.Y * 0.1, -l.Z * 0.56), STEEL, M.Metal),
		cyl("Spray", Vector3.new(0.56, 0.28, 0.28), CFrame.new(-l.X * 0.34, -0.22, -l.Z * 0.6) * ALONG_Y, Color3.fromHex("2E3545"), M.Metal),
		cyl("SprayBand", Vector3.new(0.14, 0.29, 0.29), CFrame.new(-l.X * 0.34, -0.22, -l.Z * 0.6) * ALONG_Y, WHITE, M.SmoothPlastic),
		part("SprayCap", Vector3.new(0.16, 0.14, 0.16), CFrame.new(-l.X * 0.34, 0.1, -l.Z * 0.6), Color3.fromHex("FF3B4E")),
		part("PliersL", Vector3.new(0.08, 0.48, 0.08), CFrame.new(l.X * 0.28, -0.22, -l.Z * 0.6) * CFrame.Angles(0, 0, -0.1), Color3.fromHex("F28C28"), M.Rubber),
		part("PliersR", Vector3.new(0.08, 0.48, 0.08), CFrame.new(l.X * 0.36, -0.22, -l.Z * 0.6) * CFrame.Angles(0, 0, 0.1), Color3.fromHex("F28C28"), M.Rubber),
		part("PliersHead", Vector3.new(0.18, 0.18, 0.09), CFrame.new(l.X * 0.32, 0.06, -l.Z * 0.6), STEEL, M.Metal),
	}, CFrame.identity)

	local g = sizeOf(model, "RightHand")
	local crowRed = Color3.fromHex("D7263D")
	ThiefKinds.attach(model, "RightHand", "thief_breaker_crowbar_01", {
		part("Bar", Vector3.new(0.16, 2.55, 0.16), CFrame.new(0, -g.Y * 0.5 - 0.2, 0), crowRed, M.Metal),
		part("Grip", Vector3.new(0.2, 0.62, 0.2), CFrame.new(0, -g.Y * 0.5, 0), DARK, M.Rubber),
		part("Hook", Vector3.new(0.16, 0.16, 0.56), CFrame.new(0, -g.Y * 0.5 - 1.44, -0.22), crowRed, M.Metal),
		wedge("HookBevel", Vector3.new(0.16, 0.22, 0.22), CFrame.new(0, -g.Y * 0.5 - 1.26, -0.38) * CFrame.Angles(math.pi, 0, 0), crowRed, M.Metal),
		wedge("ClawL", Vector3.new(0.08, 0.3, 0.12), CFrame.new(-0.07, -g.Y * 0.5 - 1.32, -0.5), STEEL, M.Metal),
		wedge("ClawR", Vector3.new(0.08, 0.3, 0.12), CFrame.new(0.07, -g.Y * 0.5 - 1.32, -0.5), STEEL, M.Metal),
		wedge("Tip", Vector3.new(0.22, 0.28, 0.08), CFrame.new(0, -g.Y * 0.5 + 1.14, 0.08) * CFrame.Angles(0.35, 0, 0), STEEL, M.Metal),
	}, CFrame.identity)

	gloves(model, "thief_glove_01", Color3.fromHex("0E0E0E"), M.Leather, STEEL_DARK)
	boots(model, "thief_breaker_boot_01", Color3.fromHex("2B1A12"), DARK)
	return model
end

-- 3. Громила: крупный и широкий, чёрная ребристая бини, красная бандана, хмурые брови,
-- белая майка с толстой золотой цепью и медальоном, кожаный пояс и перчатки с металлическими заклёпками.
local function brute(): Model?
	local info = Config.ThiefTypes.Brute
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Shirt, arms = info.Skin, legs = info.Pants, scale = info.Scale, width = info.Width })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	ThiefKinds.attach(model, "Head", MapSchema.Models.BruteBeanie, {
		sphere("Beanie", Vector3.new(h.X * 1.12, h.Y * 0.86, h.Z * 1.12), CFrame.new(0, h.Y * 0.26, 0.02), Color3.fromHex("1F1F24"), M.Fabric),
		part("Cuff", Vector3.new(h.X * 1.14, h.Y * 0.18, h.Z * 1.14), CFrame.new(0, h.Y * 0.2, 0), Color3.fromHex("2D2D36"), M.Fabric),
		part("Bandana", Vector3.new(h.X * 1.07, h.Y * 0.34, h.Z * 1.07), CFrame.new(0, -h.Y * 0.23, 0), RED, M.Fabric),
		wedge("BandanaBridge", Vector3.new(h.X * 0.42, h.Y * 0.14, 0.1), CFrame.new(0, -h.Y * 0.05, -h.Z * 0.54), RED, M.Fabric),
		part("BandanaTip", Vector3.new(h.X * 0.52, h.Y * 0.32, h.Z * 0.12), CFrame.new(0, -h.Y * 0.48, -h.Z * 0.5) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromHex("A82A30"), M.Fabric),
		ball("Knot", 0.24, CFrame.new(0, -h.Y * 0.2, h.Z * 0.56), Color3.fromHex("A82A30"), M.Fabric),
		part("TieL", Vector3.new(0.1, h.Y * 0.28, 0.05), CFrame.new(-h.X * 0.12, -h.Y * 0.32, h.Z * 0.58) * CFrame.Angles(0, 0, 0.35), RED, M.Fabric),
		part("TieR", Vector3.new(0.1, h.Y * 0.28, 0.05), CFrame.new(h.X * 0.12, -h.Y * 0.32, h.Z * 0.58) * CFrame.Angles(0, 0, -0.35), RED, M.Fabric),
		part("BrowL", Vector3.new(h.X * 0.32, h.Y * 0.08, 0.06), CFrame.new(-h.X * 0.19, h.Y * 0.09, -h.Z * 0.52) * CFrame.Angles(0, 0, -0.38), Color3.fromHex("2A1A12")),
		part("BrowR", Vector3.new(h.X * 0.32, h.Y * 0.08, 0.06), CFrame.new(h.X * 0.19, h.Y * 0.09, -h.Z * 0.52) * CFrame.Angles(0, 0, 0.38), Color3.fromHex("2A1A12")),
	}, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.BruteTankTop, {
		part("NeckFront", Vector3.new(t.X * 0.42, t.Y * 0.2, 0.05), CFrame.new(0, t.Y * 0.4, -t.Z * 0.51), info.Skin),
		part("NeckBack", Vector3.new(t.X * 0.42, t.Y * 0.14, 0.05), CFrame.new(0, t.Y * 0.43, t.Z * 0.51), info.Skin),
		part("ShoulderL", Vector3.new(t.X * 0.17, 0.06, t.Z * 1.02), CFrame.new(-t.X * 0.42, t.Y * 0.5 + 0.02, 0), info.Skin),
		part("ShoulderR", Vector3.new(t.X * 0.17, 0.06, t.Z * 1.02), CFrame.new(t.X * 0.42, t.Y * 0.5 + 0.02, 0), info.Skin),
		part("ChainL", Vector3.new(0.1, t.Y * 0.34, 0.07), CFrame.new(-t.X * 0.11, t.Y * 0.2, -t.Z * 0.55) * CFrame.Angles(0, 0, -0.5), GOLD, M.Metal),
		part("ChainR", Vector3.new(0.1, t.Y * 0.34, 0.07), CFrame.new(t.X * 0.11, t.Y * 0.2, -t.Z * 0.55) * CFrame.Angles(0, 0, 0.5), GOLD, M.Metal),
		part("Medal", Vector3.new(0.32, 0.32, 0.09), CFrame.new(0, t.Y * 0.04, -t.Z * 0.56) * CFrame.Angles(0, 0, math.rad(45)), GOLD, M.Metal),
		part("MedalGem", Vector3.new(0.16, 0.16, 0.1), CFrame.new(0, t.Y * 0.04, -t.Z * 0.57), RED, M.SmoothPlastic),
	}, CFrame.identity)

	local l = sizeOf(model, "LowerTorso")
	ThiefKinds.attach(model, "LowerTorso", "thief_brute_belt_01", {
		part("Belt", Vector3.new(l.X * 1.06, math.max(0.28, l.Y * 0.65), l.Z * 1.08), CFrame.new(0, l.Y * 0.14, 0), LEATHER_DARK, M.Leather),
		part("Buckle", Vector3.new(0.4, 0.28, 0.09), CFrame.new(0, l.Y * 0.14, -l.Z * 0.56), GOLD, M.Metal),
	}, CFrame.identity)

	local g = sizeOf(model, "LeftHand")
	local glove: { StubPart } = {
		part("Glove", Vector3.new(g.X * 1.25, g.Y * 1.48, g.Z * 1.25), CFrame.new(0, -g.Y * 0.04, 0), Color3.fromHex("3B2A20"), M.Leather),
		part("Cuff", Vector3.new(g.X * 1.32, g.Y * 0.45, g.Z * 1.32), CFrame.new(0, g.Y * 0.62, 0), Color3.fromHex("1F1612"), M.Leather),
		part("KnuckleBar", Vector3.new(g.X * 1.1, g.Y * 0.22, g.Z * 0.25), CFrame.new(0, -g.Y * 0.34, -g.Z * 0.56), Color3.fromHex("1F1612"), M.Leather),
	}
	for index = -1, 1 do
		table.insert(glove, ball("Stud", 0.17, CFrame.new(index * g.X * 0.34, -g.Y * 0.34, -g.Z * 0.66), STEEL, M.Metal))
	end
	ThiefKinds.attach(model, "LeftHand", MapSchema.Models.BruteGlove, glove, CFrame.identity)
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.BruteGlove, glove, CFrame.identity)
	boots(model, "thief_brute_boot_01", Color3.fromHex("3B2A20"), Color3.fromHex("1F1612"))
	return model
end

-- 4. Тень: матовая тёмная ткань (Reflectance = 0), острый капюшон с боковыми гранями,
-- тень на лице с узкими тусклыми глазами, толстовка с карманом-кенгуру, шнурками и нагрудным ремнём.
local function shadow(): Model?
	local info = Config.ThiefTypes.Shadow
	local model = ThiefKinds.rig({ head = info.Color, torso = info.Hoodie, arms = info.Hoodie, legs = info.Color })
	if not model then
		return nil
	end
	for _, bodyPart in model:GetDescendants() do
		if bodyPart:IsA("BasePart") and bodyPart.Name ~= "HumanoidRootPart" then
			bodyPart.Material = M.Fabric -- матовый: не бликует в луче фонарика
			bodyPart.Reflectance = 0
		end
	end
	local h = sizeOf(model, "Head")
	ThiefKinds.attach(model, "Head", MapSchema.Models.ShadowHood, {
		sphere("Hood", Vector3.new(h.X * 1.36, h.Y * 1.32, h.Z * 1.38), CFrame.new(0, h.Y * 0.08, h.Z * 0.1), info.Hoodie, M.Fabric),
		wedge("Peak", Vector3.new(h.X * 0.94, h.Y * 0.24, h.Z * 0.46), CFrame.new(0, h.Y * 0.52, -h.Z * 0.44), info.Hoodie, M.Fabric),
		wedge("CowlL", Vector3.new(0.18, h.Y * 0.85, h.Z * 0.44), CFrame.new(-h.X * 0.48, 0, -h.Z * 0.46), info.Hoodie, M.Fabric),
		wedge("CowlR", Vector3.new(0.18, h.Y * 0.85, h.Z * 0.44), CFrame.new(h.X * 0.48, 0, -h.Z * 0.46), info.Hoodie, M.Fabric),
		part("FaceShadow", Vector3.new(h.X * 0.82, h.Y * 0.66, 0.06), CFrame.new(0, -h.Y * 0.02, -h.Z * 0.6), Color3.fromHex("050507"), M.Fabric),
		part("EyeL", Vector3.new(h.X * 0.17, h.Y * 0.05, 0.04), CFrame.new(-h.X * 0.17, h.Y * 0.06, -h.Z * 0.64) * CFrame.Angles(0, 0, -0.14), Color3.fromHex("6E7A8A")),
		part("EyeR", Vector3.new(h.X * 0.17, h.Y * 0.05, 0.04), CFrame.new(h.X * 0.17, h.Y * 0.06, -h.Z * 0.64) * CFrame.Angles(0, 0, 0.14), Color3.fromHex("6E7A8A")),
		part("ScarfWrap", Vector3.new(h.X * 1.12, h.Y * 0.28, h.Z * 1.12), CFrame.new(0, -h.Y * 0.42, 0), Color3.fromHex("13131A"), M.Fabric),
		part("Drape", Vector3.new(h.X * 0.96, h.Y * 0.72, h.Z * 0.32), CFrame.new(0, -h.Y * 0.38, h.Z * 0.5), info.Hoodie, M.Fabric),
	}, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.ShadowHoodie, {
		part("Pocket", Vector3.new(t.X * 0.64, t.Y * 0.3, 0.07), CFrame.new(0, -t.Y * 0.28, -t.Z * 0.52), Color3.fromHex("17171D"), M.Fabric),
		part("PocketRimL", Vector3.new(0.06, t.Y * 0.24, 0.08), CFrame.new(-t.X * 0.31, -t.Y * 0.26, -t.Z * 0.53) * CFrame.Angles(0, 0, -0.25), Color3.fromHex("2B2B36"), M.Fabric),
		part("PocketRimR", Vector3.new(0.06, t.Y * 0.24, 0.08), CFrame.new(t.X * 0.31, -t.Y * 0.26, -t.Z * 0.53) * CFrame.Angles(0, 0, 0.25), Color3.fromHex("2B2B36"), M.Fabric),
		part("CordL", Vector3.new(0.06, t.Y * 0.36, 0.05), CFrame.new(-t.X * 0.08, t.Y * 0.2, -t.Z * 0.53), Color3.fromHex("3A3A44"), M.Fabric),
		part("CordR", Vector3.new(0.06, t.Y * 0.31, 0.05), CFrame.new(t.X * 0.08, t.Y * 0.22, -t.Z * 0.53), Color3.fromHex("3A3A44"), M.Fabric),
		part("ChestStrap", Vector3.new(0.14, t.Y * 1.24, 0.05), CFrame.new(0, 0, -t.Z * 0.54) * CFrame.Angles(0, 0, -0.7), Color3.fromHex("121218"), M.Fabric),
	}, CFrame.identity)

	gloves(model, "thief_shadow_glove_01", Color3.fromHex("15151B"), M.Fabric)
	for _, foot in { "LeftFoot", "RightFoot" } do
		local f = sizeOf(model, foot)
		ThiefKinds.attach(model, foot, "thief_shadow_shoe_01", {
			part("Shoe", Vector3.new(f.X * 1.08, f.Y * 1.0, f.Z * 1.12), CFrame.new(0, 0, -f.Z * 0.04), Color3.fromHex("121218"), M.Fabric),
		}, CFrame.identity)
	end
	return model
end

-- 5. Шахтёр: ребристая жёлтая каска с металлическим фонарём и проводом к батарее, пышные усы,
-- синий джинсовый комбинезон с X-лямками и карманом, кованая кирка за спиной.
local function miner(): Model?
	local info = Config.ThiefTypes.Miner
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Overalls, arms = info.Shirt, legs = info.Overalls })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local yellowDark = Color3.fromHex("D9A91E")
	ThiefKinds.attach(model, "Head", MapSchema.Models.MinerHelmet, {
		sphere("Dome", Vector3.new(h.X * 1.18, h.Y * 0.96, h.Z * 1.18), CFrame.new(0, h.Y * 0.3, 0), info.Helmet),
		cyl("Brim", Vector3.new(0.1, h.X * 1.48, h.Z * 1.48), CFrame.new(0, h.Y * 0.2, -0.04) * ALONG_Y, yellowDark),
		part("Visor", Vector3.new(h.X * 0.9, 0.08, h.Z * 0.42), CFrame.new(0, h.Y * 0.2, -h.Z * 0.68), info.Helmet),
		part("Ridge", Vector3.new(0.2, h.Y * 0.16, h.Z * 1.0), CFrame.new(0, h.Y * 0.75, 0), yellowDark),
		part("LampBracket", Vector3.new(0.28, 0.14, 0.16), CFrame.new(0, h.Y * 0.36, -h.Z * 0.52), STEEL_DARK, M.Metal),
		cyl("LampHousing", Vector3.new(0.38, 0.44, 0.44), CFrame.new(0, h.Y * 0.42, -h.Z * 0.62) * ALONG_Z, STEEL_DARK, M.Metal),
		cyl("LampBezel", Vector3.new(0.06, 0.48, 0.48), CFrame.new(0, h.Y * 0.42, -h.Z * 0.62 - 0.18) * ALONG_Z, STEEL, M.Metal),
		cyl("Lens", Vector3.new(0.05, 0.36, 0.36), CFrame.new(0, h.Y * 0.42, -h.Z * 0.62 - 0.2) * ALONG_Z, Color3.fromHex("FFF3C4"), M.Neon),
		part("Wire", Vector3.new(0.06, 0.06, h.Z * 1.05), CFrame.new(h.X * 0.42, h.Y * 0.38, 0), DARK, M.Rubber),
		part("BatteryClip", Vector3.new(0.28, 0.32, 0.14), CFrame.new(0, h.Y * 0.24, h.Z * 0.62), STEEL_DARK, M.Metal),
	}, CFrame.identity)

	local hair = Color3.fromHex("5A3A22")
	ThiefKinds.attach(model, "Head", MapSchema.Models.MinerMoustache, {
		sphere("MoustacheCenter", Vector3.new(h.X * 0.24, h.Y * 0.14, 0.16), CFrame.new(0, -h.Y * 0.1, -h.Z * 0.54), hair, M.Fabric),
		part("MoustacheL", Vector3.new(h.X * 0.32, h.Y * 0.13, 0.14), CFrame.new(-h.X * 0.16, -h.Y * 0.13, -h.Z * 0.53) * CFrame.Angles(0, 0, 0.28), hair, M.Fabric),
		part("MoustacheR", Vector3.new(h.X * 0.32, h.Y * 0.13, 0.14), CFrame.new(h.X * 0.16, -h.Y * 0.13, -h.Z * 0.53) * CFrame.Angles(0, 0, -0.28), hair, M.Fabric),
		ball("TipL", 0.13, CFrame.new(-h.X * 0.34, -h.Y * 0.17, -h.Z * 0.52), hair, M.Fabric),
		ball("TipR", 0.13, CFrame.new(h.X * 0.34, -h.Y * 0.17, -h.Z * 0.52), hair, M.Fabric),
		part("BrowL", Vector3.new(h.X * 0.24, 0.06, 0.06), CFrame.new(-h.X * 0.18, h.Y * 0.12, -h.Z * 0.52), hair, M.Fabric),
		part("BrowR", Vector3.new(h.X * 0.24, 0.06, 0.06), CFrame.new(h.X * 0.18, h.Y * 0.12, -h.Z * 0.52), hair, M.Fabric),
		part("Dirt", Vector3.new(h.X * 0.18, h.Y * 0.1, 0.03), CFrame.new(h.X * 0.3, 0, -h.Z * 0.5), Color3.fromHex("8A6A50")),
	}, CFrame.identity)

	-- Свет фонаря (Attachment MinerLamp + SpotLight сохраняем без изменений)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local lampPoint = Instance.new("Attachment")
		lampPoint.Name = "MinerLamp"
		lampPoint.CFrame = CFrame.new(0, h.Y * 0.4, -h.Z * 0.7)
		lampPoint.Parent = head
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Range = info.LampRange
		light.Brightness = info.LampBrightness
		light.Angle = info.LampAngle
		light.Color = Color3.fromHex("FFE7B0")
		light.Parent = lampPoint
	end

	local t = sizeOf(model, "UpperTorso")
	local denimDark = Color3.fromHex("23395F")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.MinerOveralls, {
		part("Bib", Vector3.new(t.X * 0.54, t.Y * 0.46, 0.06), CFrame.new(0, t.Y * 0.02, -t.Z * 0.53), denimDark, M.Fabric),
		part("BibPocket", Vector3.new(t.X * 0.32, t.Y * 0.2, 0.08), CFrame.new(0, -t.Y * 0.04, -t.Z * 0.55), info.Overalls, M.Fabric),
		part("StrapFrontL", Vector3.new(0.22, t.Y * 1.0, 0.06), CFrame.new(-t.X * 0.24, t.Y * 0.02, -t.Z * 0.54), denimDark, M.Fabric),
		part("StrapFrontR", Vector3.new(0.22, t.Y * 1.0, 0.06), CFrame.new(t.X * 0.24, t.Y * 0.02, -t.Z * 0.54), denimDark, M.Fabric),
		part("StrapBackL", Vector3.new(0.2, t.Y * 1.04, 0.05), CFrame.new(0, 0, t.Z * 0.53) * CFrame.Angles(0, 0, 0.45), denimDark, M.Fabric),
		part("StrapBackR", Vector3.new(0.2, t.Y * 1.04, 0.05), CFrame.new(0, 0, t.Z * 0.53) * CFrame.Angles(0, 0, -0.45), denimDark, M.Fabric),
		ball("ButtonL", 0.16, CFrame.new(-t.X * 0.24, t.Y * 0.22, -t.Z * 0.57), info.Helmet, M.Metal),
		ball("ButtonR", 0.16, CFrame.new(t.X * 0.24, t.Y * 0.22, -t.Z * 0.57), info.Helmet, M.Metal),
	}, CFrame.identity)

	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.MinerPickaxe, {
		part("Handle", Vector3.new(0.2, 2.75, 0.2), CFrame.identity, Color3.fromHex("7A5230"), M.Wood),
		part("Collar", Vector3.new(0.32, 0.36, 0.34), CFrame.new(0, 1.24, 0), STEEL_DARK, M.Metal),
		part("Head", Vector3.new(0.95, 0.28, 0.26), CFrame.new(0, 1.26, 0), STEEL, M.Metal),
		part("PickL", Vector3.new(0.55, 0.2, 0.18), CFrame.new(-0.68, 1.18, 0) * CFrame.Angles(0, 0, 0.3), STEEL, M.Metal),
		part("PickR", Vector3.new(0.55, 0.2, 0.18), CFrame.new(0.68, 1.18, 0) * CFrame.Angles(0, 0, -0.3), STEEL, M.Metal),
		wedge("PickTipL", Vector3.new(0.14, 0.18, 0.42), CFrame.new(-1.08, 1.02, 0) * CFrame.Angles(0, math.pi / 2, 0.42), STEEL, M.Metal),
		wedge("PickTipR", Vector3.new(0.14, 0.18, 0.42), CFrame.new(1.08, 1.02, 0) * CFrame.Angles(0, -math.pi / 2, -0.42), STEEL, M.Metal),
		part("Grip", Vector3.new(0.24, 0.55, 0.24), CFrame.new(0, -1.1, 0), Color3.fromHex("2B2F3A"), M.Rubber),
		part("Pommel", Vector3.new(0.26, 0.1, 0.26), CFrame.new(0, -1.4, 0), STEEL_DARK, M.Metal),
	}, CFrame.new(0, 0, t.Z * 0.66) * CFrame.Angles(0, 0, 0.6))

	gloves(model, "thief_miner_glove_01", Color3.fromHex("C9A46A"), M.Leather)
	boots(model, "thief_miner_boot_01", LEATHER, Color3.fromHex("2B1E14"))
	return model
end

-- 6. Стекольщик: белый альпинистский шлем со стеклянными очками и респиратором,
-- оранжевая страховочная обвязка с карабинами и бухтой верёвки, в руке присоска-стеклорез.
local function glazier(): Model?
	local info = Config.ThiefTypes.Glazier
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Suit, arms = info.Suit, legs = info.Suit })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local strap = Color3.fromHex("2B2F3A")
	local mask: { StubPart } = {
		sphere("Shell", Vector3.new(h.X * 1.16, h.Y * 0.92, h.Z * 1.16), CFrame.new(0, h.Y * 0.3, 0), info.Helmet),
		wedge("ShellTail", Vector3.new(h.X * 0.86, h.Y * 0.28, h.Z * 0.42), CFrame.new(0, h.Y * 0.24, h.Z * 0.52) * CFrame.Angles(0, math.pi, 0), info.Helmet),
		part("VentL", Vector3.new(h.X * 0.12, 0.06, h.Z * 0.62), CFrame.new(-h.X * 0.18, h.Y * 0.74, 0), strap),
		part("VentR", Vector3.new(h.X * 0.12, 0.06, h.Z * 0.62), CFrame.new(h.X * 0.18, h.Y * 0.74, 0), strap),
		part("StrapL", Vector3.new(0.06, h.Y * 0.72, 0.1), CFrame.new(-h.X * 0.53, -h.Y * 0.08, 0), strap, M.Fabric),
		part("StrapR", Vector3.new(0.06, h.Y * 0.72, 0.1), CFrame.new(h.X * 0.53, -h.Y * 0.08, 0), strap, M.Fabric),
		part("Mask", Vector3.new(h.X * 1.05, h.Y * 0.34, h.Z * 1.05), CFrame.new(0, -h.Y * 0.28, 0), Color3.fromHex("33373F"), M.Fabric),
		cyl("FilterL", Vector3.new(0.12, 0.24, 0.24), CFrame.new(-h.X * 0.24, -h.Y * 0.28, -h.Z * 0.56) * ALONG_Z, strap, M.Rubber),
		cyl("FilterR", Vector3.new(0.12, 0.24, 0.24), CFrame.new(h.X * 0.24, -h.Y * 0.28, -h.Z * 0.56) * ALONG_Z, strap, M.Rubber),
	}
	addGoggles(mask, h, h.Y * 0.1, -h.Z * 0.54, TURQUOISE, strap)
	ThiefKinds.attach(model, "Head", MapSchema.Models.GlazierHelmet, mask, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.GlazierHarness, {
		part("StrapFL", Vector3.new(0.22, t.Y * 1.02, 0.06), CFrame.new(-t.X * 0.22, 0, -t.Z * 0.53), info.Harness, M.Fabric),
		part("StrapFR", Vector3.new(0.22, t.Y * 1.02, 0.06), CFrame.new(t.X * 0.22, 0, -t.Z * 0.53), info.Harness, M.Fabric),
		part("StrapBL", Vector3.new(0.22, t.Y * 1.02, 0.06), CFrame.new(-t.X * 0.22, 0, t.Z * 0.53), info.Harness, M.Fabric),
		part("StrapBR", Vector3.new(0.22, t.Y * 1.02, 0.06), CFrame.new(t.X * 0.22, 0, t.Z * 0.53), info.Harness, M.Fabric),
		part("Chest", Vector3.new(t.X * 0.72, 0.2, 0.06), CFrame.new(0, t.Y * 0.14, -t.Z * 0.55), info.Harness, M.Fabric),
		part("ChestBuckle", Vector3.new(0.24, 0.22, 0.08), CFrame.new(0, t.Y * 0.14, -t.Z * 0.57), STEEL, M.Metal),
		part("Belt", Vector3.new(t.X * 1.05, 0.24, t.Z * 1.08), CFrame.new(0, -t.Y * 0.42, 0), info.Harness, M.Fabric),
		part("Buckle", Vector3.new(0.34, 0.3, 0.08), CFrame.new(0, -t.Y * 0.42, -t.Z * 0.56), STEEL, M.Metal),
		part("Carabiner", Vector3.new(0.14, 0.32, 0.06), CFrame.new(-t.X * 0.36, -t.Y * 0.56, -t.Z * 0.5), STEEL, M.Metal),
		part("Carabiner", Vector3.new(0.14, 0.32, 0.06), CFrame.new(t.X * 0.36, -t.Y * 0.56, -t.Z * 0.5), STEEL, M.Metal),
		cyl("Descender", Vector3.new(0.06, 0.28, 0.28), CFrame.new(t.X * 0.36, -t.Y * 0.74, -t.Z * 0.52) * ALONG_Z, GOLD, M.Metal),
		cyl("RopeCoil", Vector3.new(0.32, t.Y * 0.8, t.Y * 0.8), CFrame.new(-t.X * 0.56, t.Y * 0.04, 0.05), Config.Heist.RopeColor, M.Fabric),
		cyl("RopeCore", Vector3.new(0.34, t.Y * 0.36, t.Y * 0.36), CFrame.new(-t.X * 0.56, t.Y * 0.04, 0.05), info.Suit, M.Fabric),
	}, CFrame.identity)

	local g = sizeOf(model, "RightHand")
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.GlazierCutter, {
		cyl("Handle", Vector3.new(0.75, 0.22, 0.22), CFrame.new(0, -g.Y * 0.5 - 0.25, 0) * ALONG_Y, Color3.fromHex("5A6070"), M.Metal),
		cyl("Grip", Vector3.new(0.45, 0.25, 0.25), CFrame.new(0, -g.Y * 0.5 - 0.2, 0) * ALONG_Y, strap, M.Rubber),
		cyl("Cup", Vector3.new(0.15, 0.88, 0.88), CFrame.new(0, -g.Y * 0.5 - 0.68, 0) * ALONG_Y, RED, M.Rubber),
		cyl("CupRim", Vector3.new(0.05, 0.94, 0.94), CFrame.new(0, -g.Y * 0.5 - 0.74, 0) * ALONG_Y, Color3.fromHex("9A2228"), M.Rubber),
		part("Lever", Vector3.new(0.12, 0.28, 0.08), CFrame.new(0, -g.Y * 0.5 - 0.52, -0.22) * CFrame.Angles(0.5, 0, 0), GOLD, M.Metal),
		part("CutterArm", Vector3.new(0.1, 0.14, 0.36), CFrame.new(0, -g.Y * 0.5 - 0.15, -0.2), STEEL, M.Metal),
		cyl("Wheel", Vector3.new(0.05, 0.28, 0.28), CFrame.new(0, -g.Y * 0.5 - 0.15, -0.38), TURQUOISE, M.Metal),
	}, CFrame.identity)

	gloves(model, "thief_glazier_glove_01", strap, M.Leather)
	boots(model, "thief_glazier_boot_01", Color3.fromHex("33373F"), info.Harness)
	return model
end

-- 7. Светорез: кепка козырьком назад, янтарные защитные очки, маска, комбинезон со светоотражающей
-- полосой и нашивкой VOLT, тяжёлый пояс электрика с тестером и красные кусачки-болторез.
local function cutter(): Model?
	local info = Config.ThiefTypes.Cutter
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Coverall, arms = info.Coverall, legs = info.Coverall })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local mask: { StubPart } = {
		sphere("Crown", Vector3.new(h.X * 1.12, h.Y * 0.64, h.Z * 1.12), CFrame.new(0, h.Y * 0.32, 0), info.Cap, M.Fabric),
		part("Visor", Vector3.new(h.X * 0.82, 0.1, h.Z * 0.52), CFrame.new(0, h.Y * 0.24, h.Z * 0.68), info.Cap, M.Fabric),
		part("VisorTrim", Vector3.new(h.X * 0.84, 0.04, 0.08), CFrame.new(0, h.Y * 0.24, h.Z * 0.94), info.Stripe),
		part("Button", Vector3.new(0.14, 0.1, 0.14), CFrame.new(0, h.Y * 0.65, 0), info.Stripe),
		part("Mask", Vector3.new(h.X * 1.05, h.Y * 0.34, h.Z * 1.05), CFrame.new(0, -h.Y * 0.26, 0), Color3.fromHex("5A6070"), M.Fabric),
		part("NoseClip", Vector3.new(h.X * 0.26, 0.06, 0.06), CFrame.new(0, -h.Y * 0.1, -h.Z * 0.54), STEEL, M.Metal),
	}
	addGoggles(mask, h, h.Y * 0.2, -h.Z * 0.54, Color3.fromHex("F28C28"), DARK)
	ThiefKinds.attach(model, "Head", MapSchema.Models.CutterCap, mask, CFrame.identity)

	local t = sizeOf(model, "UpperTorso")
	local stripesProp = ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.CutterStripes, {
		part("Stripe", Vector3.new(t.X * 1.03, 0.22, t.Z * 1.05), CFrame.new(0, -t.Y * 0.08, 0), info.Stripe),
		part("StripeReflect", Vector3.new(t.X * 1.04, 0.07, t.Z * 1.06), CFrame.new(0, -t.Y * 0.08, 0), STEEL, M.Metal),
		part("Pocket", Vector3.new(t.X * 0.26, t.Y * 0.24, 0.06), CFrame.new(t.X * 0.24, t.Y * 0.22, -t.Z * 0.53), Color3.fromHex("3A4250"), M.Fabric),
		part("Pen", Vector3.new(0.06, 0.32, 0.06), CFrame.new(t.X * 0.3, t.Y * 0.36, -t.Z * 0.56), RED),
		part("VoltagePen", Vector3.new(0.06, 0.3, 0.06), CFrame.new(t.X * 0.18, t.Y * 0.35, -t.Z * 0.56), info.Stripe),
		part("BackPatch", Vector3.new(t.X * 0.65, t.Y * 0.24, 0.04), CFrame.new(0, t.Y * 0.22, t.Z * 0.52), NAVY, M.Fabric),
	}, CFrame.identity)
	addSurfaceLabel(stripesProp, "BackPatch", Enum.NormalId.Back, "VOLT", info.Stripe, 70)

	local l = sizeOf(model, "LowerTorso")
	ThiefKinds.attach(model, "LowerTorso", MapSchema.Models.CutterToolbelt, {
		part("Belt", Vector3.new(l.X * 1.06, math.max(0.3, l.Y * 0.9), l.Z * 1.08), CFrame.identity, LEATHER, M.Leather),
		part("Buckle", Vector3.new(0.32, 0.24, 0.08), CFrame.new(0, 0, -l.Z * 0.56), GOLD, M.Metal),
		part("PouchL", Vector3.new(0.5, 0.6, 0.35), CFrame.new(-l.X * 0.36, -0.25, -l.Z * 0.52), Color3.fromHex("5A3E26"), M.Leather),
		part("PouchR", Vector3.new(0.45, 0.5, 0.35), CFrame.new(l.X * 0.36, -0.2, -l.Z * 0.52), Color3.fromHex("5A3E26"), M.Leather),
		part("Screwdriver", Vector3.new(0.11, 0.52, 0.11), CFrame.new(l.X * 0.3, 0.05, -l.Z * 0.62), info.Stripe, M.Rubber),
		part("Tester", Vector3.new(0.28, 0.42, 0.16), CFrame.new(-l.X * 0.36, -0.04, -l.Z * 0.64), info.Stripe),
		part("TesterScreen", Vector3.new(0.2, 0.14, 0.03), CFrame.new(-l.X * 0.36, 0.06, -l.Z * 0.64 - 0.08), TURQUOISE, M.Neon),
		cyl("Tape", Vector3.new(0.2, 0.46, 0.46), CFrame.new(-l.X * 0.56, -0.1, 0.1), Color3.fromHex("2B2F3A")),
		cyl("TapeCore", Vector3.new(0.22, 0.2, 0.2), CFrame.new(-l.X * 0.56, -0.1, 0.1), MARBLE),
	}, CFrame.identity)

	local g = sizeOf(model, "RightHand")
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.CutterSnips, {
		part("HandleL", Vector3.new(0.14, 1.2, 0.14), CFrame.new(-0.13, -g.Y * 0.5 - 0.35, 0) * CFrame.Angles(0, 0, -0.1), RED, M.Rubber),
		part("HandleR", Vector3.new(0.14, 1.2, 0.14), CFrame.new(0.13, -g.Y * 0.5 - 0.35, 0) * CFrame.Angles(0, 0, 0.1), RED, M.Rubber),
		part("GripL", Vector3.new(0.18, 0.56, 0.18), CFrame.new(-0.17, -g.Y * 0.5 + 0.02, 0) * CFrame.Angles(0, 0, -0.1), DARK, M.Rubber),
		part("GripR", Vector3.new(0.18, 0.56, 0.18), CFrame.new(0.17, -g.Y * 0.5 + 0.02, 0) * CFrame.Angles(0, 0, 0.1), DARK, M.Rubber),
		part("Pivot", Vector3.new(0.32, 0.24, 0.22), CFrame.new(0, -g.Y * 0.5 - 1.0, 0), STEEL, M.Metal),
		cyl("Bolt", Vector3.new(0.25, 0.1, 0.1), CFrame.new(0, -g.Y * 0.5 - 1.0, 0) * ALONG_Z, GOLD, M.Metal),
		wedge("JawsL", Vector3.new(0.12, 0.55, 0.12), CFrame.new(-0.07, -g.Y * 0.5 - 1.36, 0) * CFrame.Angles(math.pi, -math.pi / 2, 0), STEEL, M.Metal),
		wedge("JawsR", Vector3.new(0.12, 0.55, 0.12), CFrame.new(0.07, -g.Y * 0.5 - 1.36, 0) * CFrame.Angles(math.pi, math.pi / 2, 0), STEEL, M.Metal),
	}, CFrame.identity)

	gloves(model, "thief_cutter_glove_01", Color3.fromHex("F28C28"), M.Rubber, DARK)
	boots(model, "thief_cutter_boot_01", Color3.fromHex("3A3F4B"), Color3.fromHex("141518"))
	return model
end

-- Всё, что носят на голове, у копии игрока остаётся (как у настоящих охранников, решение 55).
local HEAD_TYPES: { [Enum.AccessoryType]: boolean } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

-- Фальшивый охранник: аватар игрока (лицо, голова, шапки, волосы, рост) в тёмно-синей форме охраны,
-- со значком, костюмом его класса и фонариком — как настоящий охранник на смене.
local function fakeGuard(player: Player?): Model?
	local description: HumanoidDescription? = nil
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, result = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and result then
			description = result:Clone()
		end
	end
	local look = description or Instance.new("HumanoidDescription")
	local uniform = Config.Uniform
	look.TorsoColor = uniform.Torso
	look.LeftArmColor = uniform.Arms
	look.RightArmColor = uniform.Arms
	look.LeftLegColor = uniform.Legs
	look.RightLegColor = uniform.Legs
	look.Shirt = 0
	look.Pants = 0
	look.GraphicTShirt = 0
	look.NeckAccessory = ""
	look.ShouldersAccessory = ""
	look.FrontAccessory = ""
	look.BackAccessory = ""
	look.WaistAccessory = ""
	pcall(function()
		local keep = {}
		for _, accessory in look:GetAccessories(true) do
			if HEAD_TYPES[accessory.AccessoryType] then
				table.insert(keep, accessory)
			end
		end
		look:SetAccessories(keep, true)
	end)
	local model = ModelLibrary.createRig(look)
	look:Destroy()
	local rigHumanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not (model and rigHumanoid) then
		return model
	end
	Uniform.badge(model)
	Uniform.dressClass(model, if player then GameState.roleOf(player) else Config.Classes.Default)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local flashlight = Config.Flashlight
		local light = Instance.new("SpotLight")
		light.Name = "GuardFlashlight"
		light.Face = Enum.NormalId.Front
		light.Range = flashlight.OthersRange
		light.Angle = flashlight.Angle
		light.Brightness = flashlight.OthersBrightness
		light.Color = flashlight.Color
		light.Parent = head
	end
	return model
end

local BUILDERS: { [string]: () -> Model? } = {
	Pickpocket = pickpocket,
	Breaker = breaker,
	Brute = brute,
	Shadow = shadow,
	Miner = miner,
	Glazier = glazier,
	Cutter = cutter,
}

-- Модель вора этого вида (ещё не в мире). disguise — чьей копией будет Фальшивый охранник.
-- nil — если Roblox не смог собрать персонажа.
function ThiefKinds.build(kind: string, disguise: Player?): Model?
	local model
	if kind == "FakeGuard" then
		model = fakeGuard(disguise)
	else
		local builder = BUILDERS[kind] or BUILDERS.Pickpocket
		model = builder()
	end
	if model then
		model.Name = "Thief"
		model:SetAttribute(GameState.ThiefAttr.Kind, kind)
		if kind == "FakeGuard" and disguise then
			ProgressService.attachPlate(model, disguise) -- плашка «LV 7 GUARD» как у настоящего (этап 6, блок H1)
		end
	end
	return model
end

return ThiefKinds
