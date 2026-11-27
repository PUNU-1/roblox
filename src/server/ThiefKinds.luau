-- Внешний вид воров (блок 3). Тело — стандартный персонаж Roblox из HumanoidDescription (цвета частей тела,
-- размеры), снаряжение — детали кодом (заглушки ModelLibrary: модель друга с тем же именем заменит заглушку).
-- Анимации — на клиентах (NpcAnimator), здесь только то, как вор выглядит.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local Uniform = require(Server:WaitForChild("Uniform"))

local ThiefKinds = {}

local SKIN = Color3.fromHex("F5CDA8")
local DARK = Color3.fromHex("111111")

-- Маска обычного вора: чёрный мешок на голову с прорезью для глаз.
local MASK_STUB: { ModelLibrary.StubPart } = {
	{ size = Vector3.new(1.3, 1.3, 1.3), offset = CFrame.identity, color = Config.Thief.Color, material = Enum.Material.Fabric },
	{ size = Vector3.new(1.0, 0.28, 0.05), offset = CFrame.new(0, 0.15, -0.66), color = SKIN },
	{ size = Vector3.new(0.16, 0.16, 0.04), offset = CFrame.new(-0.22, 0.15, -0.7), color = DARK },
	{ size = Vector3.new(0.16, 0.16, 0.04), offset = CFrame.new(0.22, 0.15, -0.7), color = DARK },
}

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
function ThiefKinds.attach(model: Model, partName: string, name: string, stub: { ModelLibrary.StubPart }, offset: CFrame): PVInstance?
	return ModelLibrary.attachTo(model, partName, name, stub, offset) -- общий помощник (им же одевает охрану Uniform)
end

---------------------------------------------------------------- виды

local function pickpocket(color: Color3): Model?
	local model = ThiefKinds.rig({ head = color, torso = color, arms = color, legs = color })
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and humanoid then
		humanoid:AddAccessory(ModelLibrary.accessory(MapSchema.Models.ThiefMask, MASK_STUB, "FaceCenterAttachment"))
	end
	return model
end

local function sizeOf(model: Model, partName: string): Vector3
	local part = model:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part.Size else Vector3.new(1, 1, 1)
end

local GOLD = Color3.fromHex("D4A93A")
local STEEL = Color3.fromHex("A9B0BC")

-- Громила: крупный, в белой майке (голые плечи и руки), чёрная шапка, красная бандана на лице,
-- хмурые брови, золотая цепь, кожаные перчатки с заклёпками.
local function brute(): Model?
	local info = Config.ThiefTypes.Brute
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Shirt, arms = info.Skin, legs = info.Pants, scale = info.Scale, width = info.Width })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	ThiefKinds.attach(model, "Head", MapSchema.Models.BruteBeanie, {
		{ name = "Beanie", size = Vector3.new(h.X * 1.1, h.Y * 0.85, h.Z * 1.1), offset = CFrame.new(0, h.Y * 0.24, 0.02), color = Color3.fromHex("1F1F24"), material = Enum.Material.Fabric, sphere = true },
		{ name = "Cuff", size = Vector3.new(h.X * 1.1, h.Y * 0.16, h.Z * 1.1), offset = CFrame.new(0, h.Y * 0.2, 0), color = Color3.fromHex("2A2A31"), material = Enum.Material.Fabric },
		{ name = "Bandana", size = Vector3.new(h.X * 1.06, h.Y * 0.34, h.Z * 1.06), offset = CFrame.new(0, -h.Y * 0.24, 0), color = Color3.fromHex("C8343A"), material = Enum.Material.Fabric },
		{ name = "BandanaTip", size = Vector3.new(h.X * 0.5, h.Y * 0.3, h.Z * 0.12), offset = CFrame.new(0, -h.Y * 0.48, -h.Z * 0.5) * CFrame.Angles(0, 0, math.rad(45)), color = Color3.fromHex("A82A30"), material = Enum.Material.Fabric },
		{ name = "Knot", size = Vector3.new(h.X * 0.22, h.Y * 0.2, h.Z * 0.2), offset = CFrame.new(0, -h.Y * 0.2, h.Z * 0.56), color = Color3.fromHex("A82A30"), material = Enum.Material.Fabric },
		{ name = "BrowL", size = Vector3.new(h.X * 0.3, h.Y * 0.07, 0.05), offset = CFrame.new(-h.X * 0.19, h.Y * 0.08, -h.Z * 0.51) * CFrame.Angles(0, 0, -0.35), color = Color3.fromHex("2A1A12") },
		{ name = "BrowR", size = Vector3.new(h.X * 0.3, h.Y * 0.07, 0.05), offset = CFrame.new(h.X * 0.19, h.Y * 0.08, -h.Z * 0.51) * CFrame.Angles(0, 0, 0.35), color = Color3.fromHex("2A1A12") },
	}, CFrame.identity)
	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.BruteTankTop, {
		-- Голая кожа над вырезом майки спереди и сзади и голые плечи: так белый торс читается как майка
		{ name = "NeckFront", size = Vector3.new(t.X * 0.42, t.Y * 0.2, 0.05), offset = CFrame.new(0, t.Y * 0.4, -t.Z * 0.51), color = info.Skin },
		{ name = "NeckBack", size = Vector3.new(t.X * 0.42, t.Y * 0.14, 0.05), offset = CFrame.new(0, t.Y * 0.43, t.Z * 0.51), color = info.Skin },
		{ name = "ShoulderL", size = Vector3.new(t.X * 0.17, 0.06, t.Z * 1.02), offset = CFrame.new(-t.X * 0.42, t.Y * 0.5 + 0.02, 0), color = info.Skin },
		{ name = "ShoulderR", size = Vector3.new(t.X * 0.17, 0.06, t.Z * 1.02), offset = CFrame.new(t.X * 0.42, t.Y * 0.5 + 0.02, 0), color = info.Skin },
		-- Золотая цепь «галочкой» и медальон
		{ name = "ChainL", size = Vector3.new(0.08, t.Y * 0.32, 0.06), offset = CFrame.new(-t.X * 0.1, t.Y * 0.2, -t.Z * 0.54) * CFrame.Angles(0, 0, -0.5), color = GOLD, material = Enum.Material.Metal },
		{ name = "ChainR", size = Vector3.new(0.08, t.Y * 0.32, 0.06), offset = CFrame.new(t.X * 0.1, t.Y * 0.2, -t.Z * 0.54) * CFrame.Angles(0, 0, 0.5), color = GOLD, material = Enum.Material.Metal },
		{ name = "Medal", size = Vector3.new(0.26, 0.26, 0.08), offset = CFrame.new(0, t.Y * 0.04, -t.Z * 0.55), color = GOLD, material = Enum.Material.Metal },
	}, CFrame.identity)
	local g = sizeOf(model, "LeftHand")
	local glove: { ModelLibrary.StubPart } = {
		{ name = "Glove", size = Vector3.new(g.X * 1.25, g.Y * 1.5, g.Z * 1.25), offset = CFrame.new(0, -g.Y * 0.05, 0), color = Color3.fromHex("3B2A20"), material = Enum.Material.Leather },
		{ name = "Cuff", size = Vector3.new(g.X * 1.32, g.Y * 0.45, g.Z * 1.32), offset = CFrame.new(0, g.Y * 0.62, 0), color = Color3.fromHex("1F1612"), material = Enum.Material.Leather },
	}
	for index = -1, 1 do
		table.insert(glove, { name = "Stud", size = Vector3.new(0.16, 0.16, 0.16), offset = CFrame.new(index * g.X * 0.32, -g.Y * 0.35, -g.Z * 0.64), color = STEEL, material = Enum.Material.Metal, shape = Enum.PartType.Ball })
	end
	ThiefKinds.attach(model, "LeftHand", MapSchema.Models.BruteGlove, glove, CFrame.identity)
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.BruteGlove, glove, CFrame.identity)
	return model
end

-- Тень: весь в тёмном (не совсем чёрном — в луче фонарика его видно), матовая ткань, глубокий капюшон,
-- лицо в тени, только тусклые глаза. Толстовка с карманом и шнурками.
local function shadow(): Model?
	local info = Config.ThiefTypes.Shadow
	local model = ThiefKinds.rig({ head = info.Color, torso = info.Hoodie, arms = info.Hoodie, legs = info.Color })
	if not model then
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Material = Enum.Material.Fabric -- матовый: не бликует в луче
			part.Reflectance = 0
		end
	end
	local h = sizeOf(model, "Head")
	ThiefKinds.attach(model, "Head", MapSchema.Models.ShadowHood, {
		{ name = "Hood", size = Vector3.new(h.X * 1.34, h.Y * 1.32, h.Z * 1.36), offset = CFrame.new(0, h.Y * 0.08, h.Z * 0.1), color = info.Hoodie, material = Enum.Material.Fabric, sphere = true },
		{ name = "Peak", size = Vector3.new(h.X * 0.9, h.Y * 0.22, h.Z * 0.42), offset = CFrame.new(0, h.Y * 0.5, -h.Z * 0.42), color = info.Hoodie, material = Enum.Material.Fabric, wedge = true },
		{ name = "FaceShadow", size = Vector3.new(h.X * 0.82, h.Y * 0.66, 0.06), offset = CFrame.new(0, -h.Y * 0.02, -h.Z * 0.6), color = Color3.fromHex("050507"), material = Enum.Material.Fabric },
		{ name = "EyeL", size = Vector3.new(h.X * 0.16, h.Y * 0.05, 0.04), offset = CFrame.new(-h.X * 0.17, h.Y * 0.06, -h.Z * 0.64), color = Color3.fromHex("6E7A8A") },
		{ name = "EyeR", size = Vector3.new(h.X * 0.16, h.Y * 0.05, 0.04), offset = CFrame.new(h.X * 0.17, h.Y * 0.06, -h.Z * 0.64), color = Color3.fromHex("6E7A8A") },
		{ name = "Drape", size = Vector3.new(h.X * 0.95, h.Y * 0.7, h.Z * 0.3), offset = CFrame.new(0, -h.Y * 0.38, h.Z * 0.5), color = info.Hoodie, material = Enum.Material.Fabric },
	}, CFrame.identity)
	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.ShadowHoodie, {
		{ name = "Pocket", size = Vector3.new(t.X * 0.62, t.Y * 0.28, 0.06), offset = CFrame.new(0, -t.Y * 0.28, -t.Z * 0.52), color = Color3.fromHex("17171D"), material = Enum.Material.Fabric },
		{ name = "CordL", size = Vector3.new(0.06, t.Y * 0.35, 0.05), offset = CFrame.new(-t.X * 0.08, t.Y * 0.2, -t.Z * 0.53), color = Color3.fromHex("3A3A44"), material = Enum.Material.Fabric },
		{ name = "CordR", size = Vector3.new(0.06, t.Y * 0.3, 0.05), offset = CFrame.new(t.X * 0.08, t.Y * 0.22, -t.Z * 0.53), color = Color3.fromHex("3A3A44"), material = Enum.Material.Fabric },
	}, CFrame.identity)
	return model
end

-- Шахтёр: синий комбинезон с лямками, жёлтая каска с фонарём (фонарь правда светит), пышные усы,
-- пятно грязи на щеке, кирка за спиной.
local function miner(): Model?
	local info = Config.ThiefTypes.Miner
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Overalls, arms = info.Shirt, legs = info.Overalls })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local yellowDark = Color3.fromHex("D9A91E")
	ThiefKinds.attach(model, "Head", MapSchema.Models.MinerHelmet, {
		{ name = "Dome", size = Vector3.new(h.X * 1.18, h.Y * 0.95, h.Z * 1.18), offset = CFrame.new(0, h.Y * 0.3, 0), color = info.Helmet, sphere = true },
		{ name = "Brim", size = Vector3.new(0.12, h.X * 1.5, h.Z * 1.5), offset = CFrame.new(0, h.Y * 0.2, -0.05) * CFrame.Angles(0, 0, math.pi / 2), color = yellowDark, shape = Enum.PartType.Cylinder },
		{ name = "Ridge", size = Vector3.new(0.2, h.Y * 0.16, h.Z * 1.0), offset = CFrame.new(0, h.Y * 0.74, 0), color = yellowDark },
		{ name = "LampHousing", size = Vector3.new(0.36, 0.44, 0.44), offset = CFrame.new(0, h.Y * 0.4, -h.Z * 0.6) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromHex("3A3F4B"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Lens", size = Vector3.new(0.05, 0.36, 0.36), offset = CFrame.new(0, h.Y * 0.4, -h.Z * 0.6 - 0.19) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromHex("FFF3C4"), material = Enum.Material.Neon, shape = Enum.PartType.Cylinder },
	}, CFrame.identity)
	ThiefKinds.attach(model, "Head", MapSchema.Models.MinerMoustache, {
		{ name = "MoustacheL", size = Vector3.new(h.X * 0.32, h.Y * 0.13, 0.14), offset = CFrame.new(-h.X * 0.15, -h.Y * 0.13, -h.Z * 0.52) * CFrame.Angles(0, 0, 0.28), color = Color3.fromHex("5A3A22"), material = Enum.Material.Fabric },
		{ name = "MoustacheR", size = Vector3.new(h.X * 0.32, h.Y * 0.13, 0.14), offset = CFrame.new(h.X * 0.15, -h.Y * 0.13, -h.Z * 0.52) * CFrame.Angles(0, 0, -0.28), color = Color3.fromHex("5A3A22"), material = Enum.Material.Fabric },
		{ name = "Dirt", size = Vector3.new(h.X * 0.18, h.Y * 0.1, 0.03), offset = CFrame.new(h.X * 0.3, h.Y * 0.0, -h.Z * 0.5), color = Color3.fromHex("8A6A50") },
	}, CFrame.identity)
	-- Свет фонаря: точка в голове, светит вперёд, куда смотрит голова
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
		{ name = "Bib", size = Vector3.new(t.X * 0.5, t.Y * 0.42, 0.06), offset = CFrame.new(0, t.Y * 0.02, -t.Z * 0.53), color = denimDark, material = Enum.Material.Fabric },
		{ name = "StrapFrontL", size = Vector3.new(0.22, t.Y * 1.0, 0.05), offset = CFrame.new(-t.X * 0.24, t.Y * 0.02, -t.Z * 0.54), color = denimDark, material = Enum.Material.Fabric },
		{ name = "StrapFrontR", size = Vector3.new(0.22, t.Y * 1.0, 0.05), offset = CFrame.new(t.X * 0.24, t.Y * 0.02, -t.Z * 0.54), color = denimDark, material = Enum.Material.Fabric },
		{ name = "StrapBack", size = Vector3.new(t.X * 0.6, t.Y * 0.9, 0.05), offset = CFrame.new(0, 0, t.Z * 0.53), color = denimDark, material = Enum.Material.Fabric },
		{ name = "ButtonL", size = Vector3.new(0.16, 0.16, 0.06), offset = CFrame.new(-t.X * 0.24, t.Y * 0.2, -t.Z * 0.57), color = info.Helmet, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "ButtonR", size = Vector3.new(0.16, 0.16, 0.06), offset = CFrame.new(t.X * 0.24, t.Y * 0.2, -t.Z * 0.57), color = info.Helmet, material = Enum.Material.Metal, shape = Enum.PartType.Ball },
	}, CFrame.identity)
	-- Кирка за спиной наискосок: ручка и железная голова с двумя загнутыми концами
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.MinerPickaxe, {
		{ name = "Handle", size = Vector3.new(0.2, 2.7, 0.2), offset = CFrame.identity, color = Color3.fromHex("7A5230"), material = Enum.Material.Wood },
		{ name = "Head", size = Vector3.new(1.0, 0.3, 0.26), offset = CFrame.new(0, 1.25, 0), color = Color3.fromHex("8A93A6"), material = Enum.Material.Metal },
		{ name = "PickL", size = Vector3.new(0.6, 0.2, 0.2), offset = CFrame.new(-0.7, 1.17, 0) * CFrame.Angles(0, 0, 0.3), color = Color3.fromHex("8A93A6"), material = Enum.Material.Metal },
		{ name = "PickR", size = Vector3.new(0.6, 0.2, 0.2), offset = CFrame.new(0.7, 1.17, 0) * CFrame.Angles(0, 0, -0.3), color = Color3.fromHex("8A93A6"), material = Enum.Material.Metal },
		{ name = "Grip", size = Vector3.new(0.24, 0.5, 0.24), offset = CFrame.new(0, -1.1, 0), color = Color3.fromHex("2B2F3A"), material = Enum.Material.Rubber },
	}, CFrame.new(0, 0, t.Z * 0.66) * CFrame.Angles(0, 0, 0.6))
	return model
end

-- Стекольщик: тёмный костюм, белый шлем альпиниста, очки и маска, оранжевая обвязка с карабинами,
-- моток верёвки на плече, в руке присоска-стеклорез.
local function glazier(): Model?
	local info = Config.ThiefTypes.Glazier
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Suit, arms = info.Suit, legs = info.Suit })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local strap = Color3.fromHex("2B2F3A")
	ThiefKinds.attach(model, "Head", MapSchema.Models.GlazierHelmet, {
		{ name = "Shell", size = Vector3.new(h.X * 1.15, h.Y * 0.9, h.Z * 1.15), offset = CFrame.new(0, h.Y * 0.3, 0), color = info.Helmet, sphere = true },
		{ name = "Vent", size = Vector3.new(h.X * 0.12, 0.06, h.Z * 0.6), offset = CFrame.new(-h.X * 0.18, h.Y * 0.73, 0), color = strap },
		{ name = "Vent", size = Vector3.new(h.X * 0.12, 0.06, h.Z * 0.6), offset = CFrame.new(h.X * 0.18, h.Y * 0.73, 0), color = strap },
		{ name = "StrapL", size = Vector3.new(0.06, h.Y * 0.7, 0.1), offset = CFrame.new(-h.X * 0.52, -h.Y * 0.08, 0), color = strap },
		{ name = "StrapR", size = Vector3.new(0.06, h.Y * 0.7, 0.1), offset = CFrame.new(h.X * 0.52, -h.Y * 0.08, 0), color = strap },
		{ name = "GoggleBand", size = Vector3.new(h.X * 1.07, h.Y * 0.14, h.Z * 1.07), offset = CFrame.new(0, h.Y * 0.1, 0), color = strap, material = Enum.Material.Fabric },
		{ name = "LensL", size = Vector3.new(h.X * 0.32, h.Y * 0.24, 0.1), offset = CFrame.new(-h.X * 0.2, h.Y * 0.1, -h.Z * 0.55), color = Color3.fromHex("3BC6C1"), material = Enum.Material.Glass, transparency = 0.15 },
		{ name = "LensR", size = Vector3.new(h.X * 0.32, h.Y * 0.24, 0.1), offset = CFrame.new(h.X * 0.2, h.Y * 0.1, -h.Z * 0.55), color = Color3.fromHex("3BC6C1"), material = Enum.Material.Glass, transparency = 0.15 },
		{ name = "Mask", size = Vector3.new(h.X * 1.04, h.Y * 0.32, h.Z * 1.04), offset = CFrame.new(0, -h.Y * 0.28, 0), color = Color3.fromHex("33373F"), material = Enum.Material.Fabric },
	}, CFrame.identity)
	local t = sizeOf(model, "UpperTorso")
	local steel = STEEL
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.GlazierHarness, {
		{ name = "StrapFL", size = Vector3.new(0.22, t.Y * 1.02, 0.06), offset = CFrame.new(-t.X * 0.22, 0, -t.Z * 0.53), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "StrapFR", size = Vector3.new(0.22, t.Y * 1.02, 0.06), offset = CFrame.new(t.X * 0.22, 0, -t.Z * 0.53), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "StrapBL", size = Vector3.new(0.22, t.Y * 1.02, 0.06), offset = CFrame.new(-t.X * 0.22, 0, t.Z * 0.53), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "StrapBR", size = Vector3.new(0.22, t.Y * 1.02, 0.06), offset = CFrame.new(t.X * 0.22, 0, t.Z * 0.53), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "Chest", size = Vector3.new(t.X * 0.7, 0.2, 0.06), offset = CFrame.new(0, t.Y * 0.14, -t.Z * 0.55), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "Belt", size = Vector3.new(t.X * 1.05, 0.24, t.Z * 1.08), offset = CFrame.new(0, -t.Y * 0.42, 0), color = info.Harness, material = Enum.Material.Fabric },
		{ name = "Buckle", size = Vector3.new(0.34, 0.3, 0.08), offset = CFrame.new(0, -t.Y * 0.42, -t.Z * 0.56), color = steel, material = Enum.Material.Metal },
		{ name = "Carabiner", size = Vector3.new(0.14, 0.32, 0.06), offset = CFrame.new(-t.X * 0.36, -t.Y * 0.56, -t.Z * 0.5), color = steel, material = Enum.Material.Metal },
		{ name = "Carabiner", size = Vector3.new(0.14, 0.32, 0.06), offset = CFrame.new(t.X * 0.36, -t.Y * 0.56, -t.Z * 0.5), color = steel, material = Enum.Material.Metal },
		{ name = "RopeCoil", size = Vector3.new(0.3, t.Y * 0.75, t.Y * 0.75), offset = CFrame.new(-t.X * 0.55, t.Y * 0.05, 0.05), color = Config.Heist.RopeColor, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
	}, CFrame.identity)
	local g = sizeOf(model, "RightHand")
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.GlazierCutter, {
		{ name = "Handle", size = Vector3.new(0.24, 0.7, 0.24), offset = CFrame.new(0, -g.Y * 0.5 - 0.25, 0), color = Color3.fromHex("5A6070"), material = Enum.Material.Metal },
		{ name = "Cup", size = Vector3.new(0.14, 0.85, 0.85), offset = CFrame.new(0, -g.Y * 0.5 - 0.66, 0) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromHex("C8343A"), material = Enum.Material.Rubber, shape = Enum.PartType.Cylinder },
		{ name = "Wheel", size = Vector3.new(0.05, 0.28, 0.28), offset = CFrame.new(0, -g.Y * 0.5 - 0.2, -0.22), color = steel, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	}, CFrame.identity)
	return model
end

-- Светорез: серый комбинезон со светоотражающей полосой, кепка козырьком назад, очки на лбу, маска,
-- пояс с инструментами, красные кусачки в руке.
local function cutter(): Model?
	local info = Config.ThiefTypes.Cutter
	local model = ThiefKinds.rig({ head = info.Skin, torso = info.Coverall, arms = info.Coverall, legs = info.Coverall })
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	ThiefKinds.attach(model, "Head", MapSchema.Models.CutterCap, {
		{ name = "Crown", size = Vector3.new(h.X * 1.1, h.Y * 0.62, h.Z * 1.1), offset = CFrame.new(0, h.Y * 0.32, 0), color = info.Cap, material = Enum.Material.Fabric, sphere = true },
		{ name = "Visor", size = Vector3.new(h.X * 0.8, 0.1, h.Z * 0.5), offset = CFrame.new(0, h.Y * 0.24, h.Z * 0.66), color = info.Cap, material = Enum.Material.Fabric },
		{ name = "Button", size = Vector3.new(0.14, 0.1, 0.14), offset = CFrame.new(0, h.Y * 0.64, 0), color = info.Stripe },
		{ name = "GoggleBand", size = Vector3.new(h.X * 1.06, h.Y * 0.12, h.Z * 1.06), offset = CFrame.new(0, h.Y * 0.16, 0), color = DARK, material = Enum.Material.Fabric },
		{ name = "LensL", size = Vector3.new(h.X * 0.28, h.Y * 0.2, 0.1), offset = CFrame.new(-h.X * 0.19, h.Y * 0.2, -h.Z * 0.55), color = Color3.fromHex("F28C28"), material = Enum.Material.Glass, transparency = 0.1 },
		{ name = "LensR", size = Vector3.new(h.X * 0.28, h.Y * 0.2, 0.1), offset = CFrame.new(h.X * 0.19, h.Y * 0.2, -h.Z * 0.55), color = Color3.fromHex("F28C28"), material = Enum.Material.Glass, transparency = 0.1 },
		{ name = "Mask", size = Vector3.new(h.X * 1.05, h.Y * 0.34, h.Z * 1.05), offset = CFrame.new(0, -h.Y * 0.26, 0), color = Color3.fromHex("5A6070"), material = Enum.Material.Fabric },
	}, CFrame.identity)
	local t = sizeOf(model, "UpperTorso")
	ThiefKinds.attach(model, "UpperTorso", MapSchema.Models.CutterStripes, {
		{ name = "Stripe", size = Vector3.new(t.X * 1.03, 0.2, t.Z * 1.05), offset = CFrame.new(0, -t.Y * 0.08, 0), color = info.Stripe },
		{ name = "Pocket", size = Vector3.new(t.X * 0.25, t.Y * 0.22, 0.06), offset = CFrame.new(t.X * 0.24, t.Y * 0.22, -t.Z * 0.53), color = Color3.fromHex("3A4250"), material = Enum.Material.Fabric },
		{ name = "Pen", size = Vector3.new(0.06, 0.3, 0.06), offset = CFrame.new(t.X * 0.3, t.Y * 0.36, -t.Z * 0.56), color = Color3.fromHex("C8343A") },
	}, CFrame.identity)
	local l = sizeOf(model, "LowerTorso")
	ThiefKinds.attach(model, "LowerTorso", MapSchema.Models.CutterToolbelt, {
		{ name = "Belt", size = Vector3.new(l.X * 1.06, math.max(0.3, l.Y * 0.9), l.Z * 1.08), offset = CFrame.identity, color = Color3.fromHex("6B4A2E"), material = Enum.Material.Leather },
		{ name = "PouchL", size = Vector3.new(0.5, 0.6, 0.35), offset = CFrame.new(-l.X * 0.36, -0.25, -l.Z * 0.52), color = Color3.fromHex("5A3E26"), material = Enum.Material.Leather },
		{ name = "PouchR", size = Vector3.new(0.45, 0.5, 0.35), offset = CFrame.new(l.X * 0.36, -0.2, -l.Z * 0.52), color = Color3.fromHex("5A3E26"), material = Enum.Material.Leather },
		{ name = "Screwdriver", size = Vector3.new(0.1, 0.5, 0.1), offset = CFrame.new(l.X * 0.3, 0.05, -l.Z * 0.62), color = info.Stripe },
		{ name = "Tape", size = Vector3.new(0.2, 0.45, 0.45), offset = CFrame.new(-l.X * 0.56, -0.1, 0.1), color = Color3.fromHex("2B2F3A"), shape = Enum.PartType.Cylinder },
	}, CFrame.identity)
	local g = sizeOf(model, "RightHand")
	ThiefKinds.attach(model, "RightHand", MapSchema.Models.CutterSnips, {
		{ name = "HandleL", size = Vector3.new(0.13, 0.7, 0.13), offset = CFrame.new(-0.08, -g.Y * 0.5 - 0.15, 0) * CFrame.Angles(0, 0, -0.12), color = Color3.fromHex("C8343A"), material = Enum.Material.Rubber },
		{ name = "HandleR", size = Vector3.new(0.13, 0.7, 0.13), offset = CFrame.new(0.08, -g.Y * 0.5 - 0.15, 0) * CFrame.Angles(0, 0, 0.12), color = Color3.fromHex("C8343A"), material = Enum.Material.Rubber },
		{ name = "Jaws", size = Vector3.new(0.16, 0.42, 0.1), offset = CFrame.new(0, -g.Y * 0.5 - 0.7, 0), color = STEEL, material = Enum.Material.Metal },
	}, CFrame.identity)
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
	-- Значок, рубашка, ремень и костюм того же класса, что у игрока (блок F1): копию не отличить по одежде
	Uniform.badge(model)
	Uniform.dressClass(model, if player then GameState.roleOf(player) else Config.Classes.Default)
	-- Фонарик из головы, как у охранников (FlashlightController рисует такие же у настоящих)
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
	Pickpocket = function()
		return pickpocket(Config.ThiefTypes.Pickpocket.Color)
	end,
	Breaker = function()
		return pickpocket(Config.ThiefTypes.Breaker.Color)
	end,
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
	end
	return model
end

return ThiefKinds
