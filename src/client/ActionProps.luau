-- Вещи в руках для анимаций действий (этап 8, блок O): отвёртка, наручники, бинт, патрон дробовика, бронежилет.
-- Только картинка на клиенте: от первого лица (Weapons.client) — детали у камеры, у других (Guards.client) —
-- модель, приваренная к кисти. Что делает охранник, решает сервер (атрибуты Action, HealUntil, ReloadUntil).

local ActionProps = {}

export type Spec = { size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, cylinder: boolean? }

local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- цилиндр Roblox лежит вдоль X: поворачиваем вдоль Z
local STEEL = Color3.fromHex("B8C2CF")
local CLOTH = Color3.fromHex("F4F1EA")
local NAVY = Color3.fromHex("1E2A44")

-- Детали каждой вещи. «Перед» вещи — −Z (отвёртка жалом вперёд).
ActionProps.Specs = {
	Screwdriver = {
		{ size = Vector3.new(0.42, 0.17, 0.17), offset = CFrame.new(0, 0, -0.12) * ALONG_Z, color = Color3.fromHex("F2C230"), cylinder = true },
		{ size = Vector3.new(0.08, 0.19, 0.19), offset = CFrame.new(0, 0, -0.3) * ALONG_Z, color = Color3.fromHex("1A1B1F"), material = Enum.Material.Rubber, cylinder = true },
		{ size = Vector3.new(0.42, 0.05, 0.05), offset = CFrame.new(0, 0, -0.52) * ALONG_Z, color = STEEL, material = Enum.Material.Metal, cylinder = true },
	},
	Cuffs = {
		{ size = Vector3.new(0.05, 0.32, 0.32), offset = CFrame.new(-0.2, 0, 0), color = STEEL, material = Enum.Material.Metal, cylinder = true },
		{ size = Vector3.new(0.05, 0.32, 0.32), offset = CFrame.new(0.2, 0, 0), color = STEEL, material = Enum.Material.Metal, cylinder = true },
		{ size = Vector3.new(0.12, 0.2, 0.2), offset = CFrame.new(-0.2, 0, 0), color = Color3.fromHex("2A2D33"), material = Enum.Material.Metal, cylinder = true },
		{ size = Vector3.new(0.12, 0.2, 0.2), offset = CFrame.new(0.2, 0, 0), color = Color3.fromHex("2A2D33"), material = Enum.Material.Metal, cylinder = true },
		{ size = Vector3.new(0.24, 0.04, 0.04), offset = CFrame.new(0, -0.14, 0), color = STEEL, material = Enum.Material.Metal },
	},
	Bandage = {
		{ size = Vector3.new(0.26, 0.22, 0.22), offset = CFrame.identity, color = CLOTH, material = Enum.Material.Fabric, cylinder = true },
		{ size = Vector3.new(0.2, 0.03, 0.34), offset = CFrame.new(0, -0.1, 0.16), color = CLOTH, material = Enum.Material.Fabric },
	},
	Shell = {
		{ size = Vector3.new(0.3, 0.12, 0.12), offset = ALONG_Z, color = Color3.fromHex("C8322E"), cylinder = true },
		{ size = Vector3.new(0.07, 0.13, 0.13), offset = CFrame.new(0, 0, 0.17) * ALONG_Z, color = Color3.fromHex("D4A93A"), material = Enum.Material.Metal, cylinder = true },
	},
	Vest = {
		{ size = Vector3.new(1.5, 1.1, 0.16), offset = CFrame.identity, color = NAVY, material = Enum.Material.Fabric },
		{ size = Vector3.new(1.52, 0.16, 0.18), offset = CFrame.new(0, 0.1, 0), color = Color3.fromHex("F2C230"), material = Enum.Material.Fabric },
		{ size = Vector3.new(0.5, 0.3, 0.2), offset = CFrame.new(0, 0.62, 0), color = NAVY, material = Enum.Material.Fabric },
	},
} :: { [string]: { Spec } }

-- Где вещь у кисти персонажа R15 (у кисти −Y — к пальцам): отвёртка жалом от пальцев, наручники свисают.
ActionProps.HandOffsets = {
	Screwdriver = CFrame.new(0, -0.2, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
	Cuffs = CFrame.new(0, -0.35, -0.1),
	Bandage = CFrame.new(0, -0.3, 0),
} :: { [string]: CFrame }

-- Какой кистью держит (остальные — правой).
ActionProps.LeftHanded = { Bandage = true } :: { [string]: boolean }

-- Одна деталь вещи. anchored — для деталей у камеры; иначе без массы и столкновений (приваривается к кисти).
function ActionProps.part(spec: Spec, anchored: boolean): Part
	local part = Instance.new("Part")
	part.Name = "ActionProp"
	if spec.cylinder then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Size = spec.size
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Вещь в руке другого охранника: детали приварены к кисти Weld с явным C0. nil — нет такой кисти или вещи.
function ActionProps.attach(character: Model, kind: string): Model?
	local specs = ActionProps.Specs[kind]
	local handOffset = ActionProps.HandOffsets[kind]
	local hand = character:FindFirstChild(if ActionProps.LeftHanded[kind] then "LeftHand" else "RightHand")
	if not specs or not handOffset or not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "ActionProp_" .. kind
	for _, spec in specs do
		local part = ActionProps.part(spec, false)
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = part
		weld.C0 = handOffset * spec.offset
		weld.Parent = part
		part.CFrame = hand.CFrame * weld.C0
		part.Parent = model
	end
	model.Parent = character
	return model
end

return ActionProps
