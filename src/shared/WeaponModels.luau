--!strict
-- Модели оружия и снаряжения (блок 4), общие для сервера и клиента:
--  • сервер приваривает их к персонажу (в руке, в кобуре, на спине, бронежилет) и ставит в оружейной;
--  • клиент ставит те же модели у камеры — руки и оружие от первого лица.
-- Модель друга из ReplicatedStorage/Models с тем же именем сама заменяет модель Claude.
-- Договорённость: точка привязки оружия — рукоять (где её держит кисть), ствол смотрит в −Z, верх — +Y.
-- Части с именем Mag / Slide / Pump двигаются в анимациях (перезарядка, затвор, помпа),
-- Muzzle — конец ствола (вспышка и трассер), Support — где держит левая рука.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponModels = {}

export type Spec = {
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
	wedge: boolean?,
	sphere: boolean?,
	neon: boolean?,
}

export type Built = {
	model: Model,
	root: BasePart, -- невидимая деталь в точке привязки, к ней приварено всё остальное
	parts: { BasePart },
	offsets: { CFrame }, -- где каждая деталь относительно root
	muzzle: CFrame, -- конец ствола относительно root
	support: CFrame, -- где левая рука относительно root
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local C = {
	Polymer = hex("2B2F3A"),
	PolymerDark = hex("1C1F26"),
	Steel = hex("3A3F4B"),
	SteelLight = hex("6E7686"),
	Black = hex("141518"),
	Yellow = hex("F2C230"),
	Wood = hex("8A5A2B"),
	WoodDark = hex("5E3A1C"),
	Brass = hex("D9A441"),
	Red = hex("C8343A"),
	White = hex("F2F2EE"),
	Turquoise = hex("3BC6C1"),
	Electric = hex("6FD3FF"),
	Navy = hex("1E2A44"),
	NavyDark = hex("141C30"),
	Gold = hex("D4A93A"),
}
WeaponModels.Colors = C

local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (X) вдоль ствола
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вертикально

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

---------------------------------------------------------------- оружие

-- Шокер: жёлтый корпус, чёрная рукоять, картридж с двумя электродами, экранчик заряда сзади, лазерная точка.
local TASER: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.24, 0.56, 0.3), offset = at(0, -0.1, 0.04) * CFrame.Angles(0.22, 0, 0), color = C.PolymerDark, material = M.Fabric },
	{ name = "Body", size = Vector3.new(0.28, 0.32, 0.78), offset = at(0, 0.3, -0.24), color = C.Yellow },
	{ name = "Rail", size = Vector3.new(0.29, 0.06, 0.78), offset = at(0, 0.48, -0.24), color = C.Black },
	{ name = "Stripe", size = Vector3.new(0.29, 0.07, 0.36), offset = at(0, 0.24, -0.06) * CFrame.Angles(-0.4, 0, 0), color = C.Black },
	{ name = "Cartridge", size = Vector3.new(0.3, 0.3, 0.24), offset = at(0, 0.3, -0.74), color = C.Polymer },
	{ name = "ProngL", size = Vector3.new(0.05, 0.08, 0.08), offset = at(-0.07, 0.3, -0.87) * ALONG_Z, color = C.Electric, shape = CYL, neon = true },
	{ name = "ProngR", size = Vector3.new(0.05, 0.08, 0.08), offset = at(0.07, 0.3, -0.87) * ALONG_Z, color = C.Electric, shape = CYL, neon = true },
	{ name = "Screen", size = Vector3.new(0.18, 0.13, 0.02), offset = at(0, 0.33, 0.155), color = C.Turquoise, neon = true },
	{ name = "Laser", size = Vector3.new(0.07, 0.07, 0.07), offset = at(0, 0.16, -0.6), color = C.Red, shape = BALL, neon = true },
	{ name = "Guard", size = Vector3.new(0.06, 0.04, 0.32), offset = at(0, 0.04, -0.2), color = C.Black },
	{ name = "GuardFront", size = Vector3.new(0.06, 0.16, 0.04), offset = at(0, 0.1, -0.36), color = C.Black },
	{ name = "Trigger", size = Vector3.new(0.04, 0.12, 0.04), offset = at(0, 0.11, -0.18), color = C.Yellow },
}

-- Пистолет: тёмный затвор с насечками, рукоять с накладками, магазин, мушка и целик.
local PISTOL: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.22, 0.56, 0.3), offset = at(0, -0.1, 0.05) * CFrame.Angles(0.22, 0, 0), color = C.Polymer },
	{ name = "GripPanel", size = Vector3.new(0.24, 0.38, 0.22), offset = at(0, -0.12, 0.06) * CFrame.Angles(0.22, 0, 0), color = C.PolymerDark, material = M.Fabric },
	{ name = "Mag", size = Vector3.new(0.18, 0.5, 0.24), offset = at(0, -0.18, 0.08) * CFrame.Angles(0.22, 0, 0), color = C.Black },
	{ name = "Mag", size = Vector3.new(0.23, 0.06, 0.3), offset = at(0, -0.43, 0.14) * CFrame.Angles(0.22, 0, 0), color = C.Polymer },
	{ name = "Frame", size = Vector3.new(0.2, 0.16, 0.84), offset = at(0, 0.2, -0.27), color = C.Polymer },
	{ name = "Guard", size = Vector3.new(0.06, 0.04, 0.3), offset = at(0, 0.05, -0.2), color = C.Polymer },
	{ name = "GuardFront", size = Vector3.new(0.06, 0.14, 0.04), offset = at(0, 0.11, -0.35), color = C.Polymer },
	{ name = "Trigger", size = Vector3.new(0.04, 0.11, 0.04), offset = at(0, 0.12, -0.17), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.23, 0.2, 1.0), offset = at(0, 0.37, -0.3), color = C.Steel, material = M.Metal },
	{ name = "Slide", size = Vector3.new(0.24, 0.15, 0.03), offset = at(0, 0.37, 0.07), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.24, 0.15, 0.03), offset = at(0, 0.37, 0.13), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.24, 0.15, 0.03), offset = at(0, 0.37, 0.01), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.035, 0.06, 0.05), offset = at(0, 0.5, -0.74), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.14, 0.06, 0.05), offset = at(0, 0.5, 0.13), color = C.Black },
	{ name = "Slide", size = Vector3.new(0.02, 0.025, 0.025), offset = at(0, 0.53, -0.765), color = C.White, neon = true },
	{ name = "Barrel", size = Vector3.new(0.1, 0.12, 0.12), offset = at(0, 0.37, -0.82) * ALONG_Z, color = C.Black, shape = CYL },
	{ name = "Accent", size = Vector3.new(0.235, 0.025, 0.55), offset = at(0, 0.29, -0.42), color = C.Gold, material = M.Metal },
}

-- Помповый дробовик: деревянные приклад и цевьё (помпа), длинный ствол, трубка магазина, патроны на боку.
local SHOTGUN: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.22, 0.48, 0.34), offset = at(0, -0.06, 0.08) * CFrame.Angles(0.35, 0, 0), color = C.Wood, material = M.Wood },
	{ name = "Stock", size = Vector3.new(0.25, 0.4, 1.1), offset = at(0, 0.1, 0.82) * CFrame.Angles(-0.08, 0, 0), color = C.Wood, material = M.Wood },
	{ name = "Butt", size = Vector3.new(0.27, 0.52, 0.09), offset = at(0, 0.06, 1.39) * CFrame.Angles(-0.08, 0, 0), color = C.Black, material = M.Rubber },
	{ name = "Receiver", size = Vector3.new(0.3, 0.38, 0.9), offset = at(0, 0.32, -0.34), color = C.Steel, material = M.Metal },
	{ name = "Port", size = Vector3.new(0.02, 0.14, 0.34), offset = at(0.155, 0.36, -0.3), color = C.Black },
	{ name = "Barrel", size = Vector3.new(2.2, 0.16, 0.16), offset = at(0, 0.43, -1.9) * ALONG_Z, color = C.SteelLight, material = M.Metal, shape = CYL },
	{ name = "Tube", size = Vector3.new(1.7, 0.14, 0.14), offset = at(0, 0.24, -1.62) * ALONG_Z, color = C.Steel, material = M.Metal, shape = CYL },
	{ name = "Pump", size = Vector3.new(0.3, 0.26, 0.8), offset = at(0, 0.24, -1.42), color = C.Wood, material = M.Wood },
	{ name = "Pump", size = Vector3.new(0.31, 0.27, 0.04), offset = at(0, 0.24, -1.2), color = C.WoodDark, material = M.Wood },
	{ name = "Pump", size = Vector3.new(0.31, 0.27, 0.04), offset = at(0, 0.24, -1.42), color = C.WoodDark, material = M.Wood },
	{ name = "Pump", size = Vector3.new(0.31, 0.27, 0.04), offset = at(0, 0.24, -1.64), color = C.WoodDark, material = M.Wood },
	{ name = "Cap", size = Vector3.new(0.08, 0.17, 0.17), offset = at(0, 0.24, -2.49) * ALONG_Z, color = C.Black, shape = CYL },
	{ name = "Bead", size = Vector3.new(0.07, 0.07, 0.07), offset = at(0, 0.53, -2.95), color = C.Brass, material = M.Metal, shape = BALL },
	{ name = "Guard", size = Vector3.new(0.06, 0.04, 0.32), offset = at(0, 0.07, -0.18), color = C.Steel },
	{ name = "Trigger", size = Vector3.new(0.04, 0.12, 0.04), offset = at(0, 0.14, -0.16), color = C.Black },
	{ name = "Shell", size = Vector3.new(0.3, 0.12, 0.12), offset = at(0.17, 0.34, -0.12) * ALONG_Y, color = C.Red, shape = CYL },
	{ name = "Shell", size = Vector3.new(0.3, 0.12, 0.12), offset = at(0.17, 0.34, -0.28) * ALONG_Y, color = C.Red, shape = CYL },
	{ name = "Shell", size = Vector3.new(0.3, 0.12, 0.12), offset = at(0.17, 0.34, -0.44) * ALONG_Y, color = C.Red, shape = CYL },
	{ name = "ShellCaps", size = Vector3.new(0.06, 0.13, 0.42), offset = at(0.17, 0.2, -0.28), color = C.Brass, material = M.Metal },
}

-- Автомат: ствольная коробка, цевьё с планками, коллиматор, изогнутый магазин, складной приклад.
local RIFLE: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.22, 0.5, 0.28), offset = at(0, -0.06, 0.05) * CFrame.Angles(0.3, 0, 0), color = C.Polymer },
	{ name = "Receiver", size = Vector3.new(0.3, 0.36, 1.2), offset = at(0, 0.32, -0.36), color = C.Steel, material = M.Metal },
	{ name = "Port", size = Vector3.new(0.02, 0.12, 0.26), offset = at(0.155, 0.36, -0.3), color = C.Black },
	{ name = "Handguard", size = Vector3.new(0.34, 0.32, 1.0), offset = at(0, 0.33, -1.42), color = C.Polymer },
	{ name = "RailL", size = Vector3.new(0.02, 0.05, 0.9), offset = at(-0.175, 0.37, -1.42), color = C.Black },
	{ name = "RailR", size = Vector3.new(0.02, 0.05, 0.9), offset = at(0.175, 0.37, -1.42), color = C.Black },
	{ name = "RailTop", size = Vector3.new(0.16, 0.04, 1.9), offset = at(0, 0.51, -0.95), color = C.Black },
	{ name = "Barrel", size = Vector3.new(0.7, 0.14, 0.14), offset = at(0, 0.36, -2.25) * ALONG_Z, color = C.Black, material = M.Metal, shape = CYL },
	{ name = "Brake", size = Vector3.new(0.22, 0.2, 0.2), offset = at(0, 0.36, -2.66) * ALONG_Z, color = C.Steel, material = M.Metal, shape = CYL },
	{ name = "SightPost", size = Vector3.new(0.06, 0.28, 0.08), offset = at(0, 0.66, -1.8), color = C.Black },
	{ name = "SightRing", size = Vector3.new(0.22, 0.06, 0.08), offset = at(0, 0.78, -1.8), color = C.Black },
	{ name = "Optic", size = Vector3.new(0.24, 0.24, 0.5), offset = at(0, 0.68, -0.42), color = C.PolymerDark },
	{ name = "OpticMount", size = Vector3.new(0.18, 0.1, 0.3), offset = at(0, 0.53, -0.42), color = C.Black },
	{ name = "Lens", size = Vector3.new(0.18, 0.18, 0.02), offset = at(0, 0.68, -0.68), color = hex("FF7A7A"), material = M.Glass, transparency = 0.35 },
	{ name = "Dot", size = Vector3.new(0.03, 0.03, 0.01), offset = at(0, 0.68, -0.69), color = C.Red, neon = true },
	{ name = "Mag", size = Vector3.new(0.2, 0.46, 0.3), offset = at(0, -0.02, -0.62) * CFrame.Angles(-0.12, 0, 0), color = C.Black },
	{ name = "Mag", size = Vector3.new(0.2, 0.36, 0.3), offset = at(0, -0.36, -0.7) * CFrame.Angles(-0.3, 0, 0), color = C.Black },
	{ name = "Mag", size = Vector3.new(0.22, 0.05, 0.32), offset = at(0, -0.55, -0.76) * CFrame.Angles(-0.3, 0, 0), color = C.Polymer },
	{ name = "Stock", size = Vector3.new(0.22, 0.32, 0.86), offset = at(0, 0.24, 0.64), color = C.Polymer },
	{ name = "StockPad", size = Vector3.new(0.25, 0.52, 0.1), offset = at(0, 0.16, 1.1), color = C.Black, material = M.Rubber },
	{ name = "Slide", size = Vector3.new(0.16, 0.06, 0.14), offset = at(0, 0.51, 0.16), color = C.Black },
	{ name = "Guard", size = Vector3.new(0.06, 0.04, 0.32), offset = at(0, 0.07, -0.18), color = C.Polymer },
	{ name = "Trigger", size = Vector3.new(0.04, 0.12, 0.04), offset = at(0, 0.14, -0.16), color = C.Black },
	{ name = "Accent", size = Vector3.new(0.31, 0.04, 0.5), offset = at(0, 0.2, -1.42), color = C.Gold, material = M.Metal },
}

-- Аптечка: белый чемоданчик с красными крестами, ручка сверху (точка привязки — ручка).
local MEDKIT: { Spec } = {
	{ name = "Case", size = Vector3.new(1.2, 0.8, 0.45), offset = at(0, -0.55, 0), color = C.White },
	{ name = "Rim", size = Vector3.new(1.24, 0.06, 0.49), offset = at(0, -0.36, 0), color = hex("C9CED6") },
	{ name = "CrossH", size = Vector3.new(0.46, 0.14, 0.47), offset = at(0, -0.58, 0), color = C.Red },
	{ name = "CrossV", size = Vector3.new(0.14, 0.46, 0.47), offset = at(0, -0.58, 0), color = C.Red },
	{ name = "Handle", size = Vector3.new(0.5, 0.08, 0.1), offset = at(0, 0, 0), color = C.Polymer },
	{ name = "PostL", size = Vector3.new(0.08, 0.16, 0.1), offset = at(-0.21, -0.08, 0), color = C.Polymer },
	{ name = "PostR", size = Vector3.new(0.08, 0.16, 0.1), offset = at(0.21, -0.08, 0), color = C.Polymer },
	{ name = "LatchL", size = Vector3.new(0.1, 0.08, 0.04), offset = at(-0.4, -0.33, -0.24), color = C.Gold, material = M.Metal },
	{ name = "LatchR", size = Vector3.new(0.1, 0.08, 0.04), offset = at(0.4, -0.33, -0.24), color = C.Gold, material = M.Metal },
}

-- Дубинка грабителя: резиновая с ручкой-темляком (точка привязки — рукоять, бьющий конец в −Z).
local BATON: { Spec } = {
	{ name = "Grip", size = Vector3.new(0.5, 0.18, 0.18), offset = at(0, 0, 0) * ALONG_Z, color = C.Black, material = M.Rubber, shape = CYL },
	{ name = "Rod", size = Vector3.new(1.7, 0.14, 0.14), offset = at(0, 0, -1.05) * ALONG_Z, color = C.PolymerDark, material = M.Rubber, shape = CYL },
	{ name = "Tip", size = Vector3.new(0.16, 0.16, 0.16), offset = at(0, 0, -1.9), color = C.PolymerDark, material = M.Rubber, shape = BALL },
	{ name = "Side", size = Vector3.new(0.4, 0.1, 0.1), offset = at(0, 0, -0.35) * CFrame.Angles(0, 0, math.pi / 2), color = C.Black, material = M.Rubber, shape = CYL },
	{ name = "Pommel", size = Vector3.new(0.08, 0.22, 0.22), offset = at(0, 0, 0.27) * ALONG_Z, color = C.Steel, material = M.Metal, shape = CYL },
}

-- Дымовая шашка: зелёно-серая банка с кольцом и рычагом.
local SMOKE: { Spec } = {
	{ name = "Can", size = Vector3.new(0.62, 0.36, 0.36), offset = at(0, 0, 0) * ALONG_Y, color = hex("5A6B4A"), shape = CYL },
	{ name = "Band", size = Vector3.new(0.12, 0.37, 0.37), offset = at(0, 0.12, 0) * ALONG_Y, color = C.Yellow, shape = CYL },
	{ name = "Top", size = Vector3.new(0.08, 0.26, 0.26), offset = at(0, 0.34, 0) * ALONG_Y, color = C.SteelLight, material = M.Metal, shape = CYL },
	{ name = "Lever", size = Vector3.new(0.06, 0.4, 0.08), offset = at(0.15, 0.18, 0), color = C.SteelLight, material = M.Metal },
	{ name = "Ring", size = Vector3.new(0.03, 0.16, 0.16), offset = at(-0.12, 0.42, 0), color = C.SteelLight, material = M.Metal, shape = CYL },
}

type Info = { specs: { Spec }, muzzle: CFrame, support: CFrame }

WeaponModels.Names = {
	Taser = "weapon_taser_01",
	Pistol = "weapon_pistol_01",
	Shotgun = "weapon_shotgun_01",
	Rifle = "weapon_rifle_01",
	Medkit = "prop_medkit_01",
	Baton = "robber_baton_01",
	Smoke = "prop_smoke_grenade_01",
}

local INFO: { [string]: Info } = {
	Taser = { specs = TASER, muzzle = at(0, 0.3, -0.9), support = at(-0.12, -0.12, 0.08) },
	Pistol = { specs = PISTOL, muzzle = at(0, 0.37, -0.9), support = at(-0.12, -0.12, 0.08) },
	Shotgun = { specs = SHOTGUN, muzzle = at(0, 0.43, -3.02), support = at(0, 0.08, -1.42) },
	Rifle = { specs = RIFLE, muzzle = at(0, 0.36, -2.78), support = at(0, 0.14, -1.45) },
	Medkit = { specs = MEDKIT, muzzle = at(0, -0.55, -0.3), support = at(-0.55, -0.55, 0) },
	Baton = { specs = BATON, muzzle = at(0, 0, -1.9), support = at(0, 0, 0) },
	Smoke = { specs = SMOKE, muzzle = at(0, 0.4, 0), support = at(0, 0, 0) },
}

---------------------------------------------------------------- сборка

local function newPart(spec: Spec, index: number): BasePart
	local part: BasePart
	if spec.wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if spec.shape then
			block.Shape = spec.shape
		end
		part = block
	end
	part.Name = spec.name or ("Part" .. index)
	part.Size = spec.size
	part.CFrame = spec.offset
	part.Color = spec.color
	part.Material = if spec.neon then Enum.Material.Neon else (spec.material or Enum.Material.SmoothPlastic)
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	return part
end

local function quiet(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Модель по своим деталям (specs) с невидимым корнем в точке привязки. Модель друга с тем же именем — вместо неё.
function WeaponModels.fromSpecs(name: string, specs: { Spec }, muzzle: CFrame?, support: CFrame?): Built
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.CFrame = CFrame.identity
	quiet(root)
	root.Parent = model
	model.PrimaryPart = root
	local parts, offsets = {}, {}
	local muzzleOffset = muzzle or CFrame.identity
	local supportOffset = support or CFrame.identity
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		local copy = template:Clone()
		local pivot = copy:GetPivot()
		for _, descendant in copy:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then
				descendant:Destroy() -- скриптов в моделях быть не должно
			elseif descendant:IsA("BasePart") then
				table.insert(parts, descendant)
				table.insert(offsets, pivot:ToObjectSpace(descendant.CFrame))
			elseif descendant:IsA("Attachment") and descendant.Name == "Muzzle" then
				muzzleOffset = pivot:ToObjectSpace(descendant.WorldCFrame)
			elseif descendant:IsA("Attachment") and descendant.Name == "Support" then
				supportOffset = pivot:ToObjectSpace(descendant.WorldCFrame)
			end
		end
		for index, part in parts do
			part.CFrame = offsets[index]
			part.Parent = model
		end
		copy:Destroy()
	else
		for index, spec in specs do
			local part = newPart(spec, index)
			table.insert(parts, part)
			table.insert(offsets, spec.offset)
			part.Parent = model
		end
	end
	for _, part in parts do
		quiet(part)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Muzzle"
	attachment.CFrame = muzzleOffset
	attachment.Parent = root
	model.WorldPivot = CFrame.identity
	return { model = model, root = root, parts = parts, offsets = offsets, muzzle = muzzleOffset, support = supportOffset }
end

-- Оружие или снаряжение по короткому имени: Taser, Pistol, Shotgun, Rifle, Medkit, Baton, Smoke.
function WeaponModels.build(kind: string): Built
	local info = INFO[kind] or INFO.Pistol
	return WeaponModels.fromSpecs(WeaponModels.Names[kind] or kind, info.specs, info.muzzle, info.support)
end

-- Приварить собранную модель к детали персонажа: модель встаёт в cframe (в мире) и двигается вместе с частью тела.
-- Weld с явным C0: так модель держится там, где её поставили, как бы ни двигалась часть тела.
function WeaponModels.weld(built: Built, toPart: BasePart, cframe: CFrame)
	for index, part in built.parts do
		part.CFrame = cframe * built.offsets[index]
		local weld = Instance.new("Weld")
		weld.Name = "GearWeld"
		weld.Part0 = built.root
		weld.Part1 = part
		weld.C0 = built.offsets[index]
		weld.Parent = part
	end
	built.root.CFrame = cframe
	local weld = Instance.new("Weld")
	weld.Name = "GearWeld"
	weld.Part0 = toPart
	weld.Part1 = built.root
	weld.C0 = toPart.CFrame:ToObjectSpace(cframe)
	weld.Parent = built.root
end

-- Закрепить модель в мире (оружейная): всё закреплено, стоит в cframe.
function WeaponModels.anchor(built: Built, cframe: CFrame)
	built.root.Anchored = true
	built.root.CFrame = cframe
	for index, part in built.parts do
		part.Anchored = true
		part.CFrame = cframe * built.offsets[index]
	end
end

---------------------------------------------------------------- бронежилет охраны

-- Детали бронежилета для верхней части туловища размером t (точка привязки — центр туловища).
-- Тёмные пластины спереди и сзади, плечевые лямки, боковые ремни, подсумки, рация и значок.
function WeaponModels.vestSpecs(t: Vector3): { Spec }
	local front = -t.Z * 0.5 - 0.1
	local back = t.Z * 0.5 + 0.1
	local plate = C.NavyDark
	local strap = hex("0E1322")
	return {
		{ name = "FrontPlate", size = Vector3.new(t.X * 0.86, t.Y * 0.84, 0.2), offset = at(0, -t.Y * 0.04, front), color = plate, material = M.Fabric },
		{ name = "BackPlate", size = Vector3.new(t.X * 0.88, t.Y * 0.86, 0.2), offset = at(0, -t.Y * 0.03, back), color = plate, material = M.Fabric },
		{ name = "StrapL", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.24), offset = at(-t.X * 0.27, t.Y * 0.47, 0), color = strap, material = M.Fabric },
		{ name = "StrapR", size = Vector3.new(t.X * 0.2, 0.14, t.Z * 1.24), offset = at(t.X * 0.27, t.Y * 0.47, 0), color = strap, material = M.Fabric },
		{ name = "SideL", size = Vector3.new(0.12, t.Y * 0.42, t.Z * 1.2), offset = at(-t.X * 0.5 - 0.04, -t.Y * 0.18, 0), color = strap, material = M.Fabric },
		{ name = "SideR", size = Vector3.new(0.12, t.Y * 0.42, t.Z * 1.2), offset = at(t.X * 0.5 + 0.04, -t.Y * 0.18, 0), color = strap, material = M.Fabric },
		{ name = "PouchL", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(-t.X * 0.27, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "PouchM", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(0, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "PouchR", size = Vector3.new(t.X * 0.22, t.Y * 0.26, 0.18), offset = at(t.X * 0.27, -t.Y * 0.26, front - 0.17), color = strap, material = M.Fabric },
		{ name = "Radio", size = Vector3.new(0.22, 0.34, 0.14), offset = at(t.X * 0.26, t.Y * 0.16, front - 0.16), color = C.Black },
		{ name = "Antenna", size = Vector3.new(0.04, 0.36, 0.04), offset = at(t.X * 0.31, t.Y * 0.4, front - 0.16), color = C.Black },
		{ name = "Badge", size = Vector3.new(0.34, 0.34, 0.05), offset = at(-t.X * 0.25, t.Y * 0.16, front - 0.12), color = C.Gold, material = M.Metal },
		{ name = "Stripe", size = Vector3.new(t.X * 0.88, 0.07, 0.21), offset = at(0, t.Y * 0.02, back + 0.005), color = hex("F2C230") },
	}
end

-- Надпись SECURITY на спине бронежилета (у детали BackPlate).
function WeaponModels.labelVest(model: Instance)
	local back = model:FindFirstChild("BackPlate", true)
	if not (back and back:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.32)
	label.Position = UDim2.fromScale(0, 0.12)
	label.Text = "SECURITY"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = hex("F2C230")
	label.Parent = gui
	gui.Parent = back
end

return WeaponModels
