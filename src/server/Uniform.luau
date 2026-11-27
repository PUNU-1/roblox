-- Форма охраны (решения 12 и 55): убираем свою одежду и аксессуары на теле, красим тело в тёмно-синюю
-- форму, надеваем значок. Шапки, волосы, очки и брови игрока остаются.
-- Общая для музея (RoleService) и хаба (Hub.server, блок 6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local Uniform = {}

local BADGE_STUB: { ModelLibrary.StubPart } = {
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
	humanoid:AddAccessory(ModelLibrary.accessory(MapSchema.Models.GuardBadge, BADGE_STUB, "BodyFrontAttachment"))
end

return Uniform
