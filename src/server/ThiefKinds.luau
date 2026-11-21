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

local BUILDERS: { [string]: () -> Model? } = {
	Pickpocket = function()
		return pickpocket(Config.ThiefTypes.Pickpocket.Color)
	end,
	Breaker = function()
		return pickpocket(Config.ThiefTypes.Breaker.Color)
	end,
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
