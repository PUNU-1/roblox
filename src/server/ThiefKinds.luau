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
	local bodyPart = model:FindFirstChild(partName)
	if not (bodyPart and bodyPart:IsA("BasePart")) then
		return nil
	end
	local prop = ModelLibrary.build(name, stub)
	prop:PivotTo(bodyPart.CFrame * offset)
	ModelLibrary.forEachPart(prop, function(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		local weld = Instance.new("Weld")
		weld.Name = "PropWeld"
		weld.Part0 = bodyPart
		weld.Part1 = part
		weld.C0 = bodyPart.CFrame:ToObjectSpace(part.CFrame)
		weld.Parent = part
	end)
	prop.Parent = model
	return prop
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

local BUILDERS: { [string]: () -> Model? } = {
	Pickpocket = function()
		return pickpocket(Config.ThiefTypes.Pickpocket.Color)
	end,
	Breaker = function()
		return pickpocket(Config.ThiefTypes.Breaker.Color)
	end,
	Brute = brute,
	Shadow = shadow,
}

-- Модель вора этого вида (ещё не в мире). nil — если Roblox не смог собрать персонажа.
function ThiefKinds.build(kind: string): Model?
	local builder = BUILDERS[kind] or BUILDERS.Pickpocket
	local model = builder()
	if model then
		model.Name = "Thief"
		model:SetAttribute(GameState.ThiefAttr.Kind, kind)
	end
	return model
end

return ThiefKinds
