--!strict
-- Модели классов (блок 5), общие для сервера и клиента:
--  • собака кинолога (prop_dog_01): сервер ставит модель, клиенты двигают её детали (DogAnimator);
--  • датчик движения техника (prop_sensor_01): сервер ставит, клиенты мигают лампочкой (Abilities.client);
--  • картинки карточек классов в лобби (ClassCards): кроссовок патруля, телефон и камера оператора.
-- Модель друга из ReplicatedStorage/Models с тем же именем сама заменяет модель Claude (WeaponModels.fromSpecs).
-- Точка привязки — низ по центру, «перед» смотрит в −Z, верх — +Y.
--
-- Кости собаки: имя детали начинается с названия кости и «_» (Body_Torso, Head_Nose, LegFL_Paw…).
-- Детали без такого начала двигаются вместе с туловищем. Точки вращения костей — DogBones;
-- в модели друга их можно задать Attachment с именами Bone_Head, Bone_Jaw, Bone_LegFL и т.д.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponModels = require(script.Parent:WaitForChild("WeaponModels"))

type Spec = WeaponModels.Spec
export type Built = WeaponModels.Built

local ClassModels = {}

ClassModels.Names = {
	Dog = "prop_dog_01",
	Sensor = "prop_sensor_01",
	IconPatrol = "icon_class_patrol_01",
	IconOperator = "icon_class_operator_01",
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (X) вдоль −Z
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вертикально

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

---------------------------------------------------------------- собака

local D = {
	Tan = hex("DF984B"), -- тёплая яркая рыжая шерсть
	TanLight = hex("F4C688"),
	Cream = hex("FFF0D4"), -- светлое брюхо, лапы, морда
	Saddle = hex("422C1F"), -- контрастная «попона» на спине
	Nose = hex("1A1414"),
	White = hex("FFFFFF"),
	Pupil = hex("161822"),
	Pink = hex("FF8CA0"),
	Collar = hex("E63946"),
	Gold = hex("F5C542"),
	Vest = hex("243B6B"), -- жилет K-9 в цвет формы охраны
	VestDark = hex("172647"),
	Yellow = hex("FFD036"),
}
ClassModels.DogColors = D

-- Лапа целиком (одна кость): бедро, голень, ступня. side: −1 — левая (−X), 1 — правая; front — передняя.
local function leg(bone: string, side: number, front: boolean): { Spec }
	local x = side * (if front then 0.38 else 0.42)
	if front then
		local z = -0.92
		return {
			{ name = bone .. "_Upper", size = Vector3.new(0.4, 0.8, 0.46), offset = at(x, 1.1, z), color = D.Tan, sphere = true },
			{ name = bone .. "_Lower", size = Vector3.new(0.3, 0.72, 0.32), offset = at(x, 0.5, z - 0.02), color = D.TanLight, sphere = true },
			{ name = bone .. "_Paw", size = Vector3.new(0.38, 0.26, 0.5), offset = at(x, 0.13, z - 0.1), color = D.Cream, sphere = true },
		}
	end
	local z = 0.95
	return {
		{ name = bone .. "_Thigh", size = Vector3.new(0.48, 0.92, 0.72), offset = at(x, 1.2, z), color = D.Tan, sphere = true },
		{ name = bone .. "_Lower", size = Vector3.new(0.3, 0.76, 0.34), offset = at(x, 0.52, z + 0.12) * CFrame.Angles(0.16, 0, 0), color = D.TanLight, sphere = true },
		{ name = bone .. "_Paw", size = Vector3.new(0.38, 0.26, 0.5), offset = at(x, 0.13, z + 0.04), color = D.Cream, sphere = true },
	}
end

-- Ухо: треугольник (клин, повёрнутый боком), прямой край — к середине головы, кончик чуть наружу.
local function ear(side: number): { Spec }
	local turn = CFrame.Angles(0, 0, -side * 0.25) * CFrame.Angles(0, -side * math.pi / 2, 0)
	return {
		{ name = "Head_Ear" .. (if side < 0 then "L" else "R"), size = Vector3.new(0.12, 0.62, 0.38), offset = at(side * 0.24, 3.05, -1.52) * turn, color = D.Tan, wedge = true },
		{ name = "Head_EarIn" .. (if side < 0 then "L" else "R"), size = Vector3.new(0.06, 0.42, 0.24), offset = at(side * 0.22, 2.99, -1.59) * turn, color = D.Pink, wedge = true },
	}
end

local function eye(side: number): { Spec }
	local s = if side < 0 then "L" else "R"
	local x = side * 0.21
	return {
		{ name = "Head_Eye" .. s, size = Vector3.new(0.2, 0.24, 0.12), offset = at(x, 2.7, -1.99), color = D.White, sphere = true },
		{ name = "Head_Pupil" .. s, size = Vector3.new(0.12, 0.15, 0.08), offset = at(x, 2.69, -2.04), color = D.Pupil, sphere = true },
		{ name = "Head_Shine" .. s, size = Vector3.new(0.05, 0.05, 0.05), offset = at(x + 0.03, 2.73, -2.08), color = D.White, shape = BALL, neon = true },
		{ name = "Head_Brow" .. s, size = Vector3.new(0.13, 0.07, 0.07), offset = at(x, 2.86, -1.93), color = D.Cream, sphere = true },
	}
end

local function joinSpecs(lists: { { Spec } }): { Spec }
	local all = {}
	for _, list in lists do
		for _, spec in list do
			table.insert(all, spec)
		end
	end
	return all
end

local DOG: { Spec } = joinSpecs({
	{
		-- туловище: овал, глубокая грудь, бёдра, тёмная «попона» на спине, светлое брюхо
		{ name = "Body_Torso", size = Vector3.new(1.15, 1.05, 2.3), offset = at(0, 1.58, 0.05), color = D.Tan, sphere = true },
		{ name = "Body_Chest", size = Vector3.new(1.12, 1.2, 1.05), offset = at(0, 1.52, -0.82), color = D.TanLight, sphere = true },
		{ name = "Body_Hips", size = Vector3.new(1.08, 1.02, 1.05), offset = at(0, 1.6, 0.85), color = D.Tan, sphere = true },
		{ name = "Body_Saddle", size = Vector3.new(0.98, 0.5, 1.9), offset = at(0, 1.95, 0.3), color = D.Saddle, sphere = true },
		{ name = "Body_Belly", size = Vector3.new(0.9, 0.55, 1.7), offset = at(0, 1.22, 0.05), color = D.Cream, sphere = true },
		-- шея и красный ошейник с золотым жетоном
		{ name = "Body_Neck", size = Vector3.new(0.72, 1.0, 0.72), offset = at(0, 2.0, -1.2) * CFrame.Angles(-0.45, 0, 0), color = D.Tan, sphere = true },
		{ name = "Body_Collar", size = Vector3.new(0.16, 0.86, 0.86), offset = at(0, 2.05, -1.22) * CFrame.Angles(-0.45, 0, 0) * ALONG_Y, color = D.Collar, shape = CYL },
		{ name = "Body_Tag", size = Vector3.new(0.2, 0.2, 0.2), offset = at(0, 1.84, -1.6), color = D.Gold, material = M.Metal, shape = BALL },
		-- жилет K-9: тёмно-синий, две жёлтые полосы, нашивки по бокам, ручка сверху
		{ name = "Body_Vest", size = Vector3.new(1.24, 1.16, 1.25), offset = at(0, 1.6, -0.3), color = D.Vest, material = M.Fabric, sphere = true },
		{ name = "Body_VestStripeA", size = Vector3.new(1.12, 1.05, 0.1), offset = at(0, 1.6, 0), color = D.Yellow, sphere = true },
		{ name = "Body_VestStripeB", size = Vector3.new(1.12, 1.05, 0.1), offset = at(0, 1.6, -0.6), color = D.Yellow, sphere = true },
		{ name = "Body_PatchL", size = Vector3.new(0.05, 0.42, 0.5), offset = at(-0.6, 1.66, -0.3), color = D.VestDark, material = M.Fabric },
		{ name = "Body_PatchR", size = Vector3.new(0.05, 0.42, 0.5), offset = at(0.6, 1.66, -0.3), color = D.VestDark, material = M.Fabric },
		{ name = "Body_Handle", size = Vector3.new(0.5, 0.1, 0.12), offset = at(0, 2.32, -0.3), color = D.VestDark },
		{ name = "Body_HandlePostL", size = Vector3.new(0.08, 0.16, 0.08), offset = at(-0.21, 2.23, -0.3), color = D.VestDark },
		{ name = "Body_HandlePostR", size = Vector3.new(0.08, 0.16, 0.08), offset = at(0.21, 2.23, -0.3), color = D.VestDark },
	},
	leg("LegFL", -1, true),
	leg("LegFR", 1, true),
	leg("LegBL", -1, false),
	leg("LegBR", 1, false),
	{
		-- голова: череп, тёмная шапочка, светлая морда, чёрный нос
		{ name = "Head_Skull", size = Vector3.new(0.86, 0.8, 0.92), offset = at(0, 2.58, -1.6), color = D.Tan, sphere = true },
		{ name = "Head_Cap", size = Vector3.new(0.72, 0.36, 0.66), offset = at(0, 2.84, -1.5), color = D.Saddle, sphere = true },
		{ name = "Head_Snout", size = Vector3.new(0.52, 0.44, 0.78), offset = at(0, 2.44, -2.05), color = D.Cream, sphere = true },
		{ name = "Head_Nose", size = Vector3.new(0.24, 0.17, 0.2), offset = at(0, 2.56, -2.42), color = D.Nose, sphere = true },
	},
	eye(-1),
	eye(1),
	ear(-1),
	ear(1),
	{
		-- нижняя челюсть с языком: открывается, когда собака лает
		{ name = "Jaw_Lower", size = Vector3.new(0.44, 0.2, 0.62), offset = at(0, 2.26, -2.05), color = D.Cream, sphere = true },
		{ name = "Jaw_Tongue", size = Vector3.new(0.24, 0.07, 0.42), offset = at(0, 2.33, -2.1), color = D.Pink, sphere = true },
		-- хвост из двух частей, кончик светлый
		{ name = "Tail1_Base", size = Vector3.new(0.26, 0.26, 0.8), offset = at(0, 2.11, 1.66) * CFrame.Angles(-0.55, 0, 0), color = D.Tan, sphere = true },
		{ name = "Tail2_Mid", size = Vector3.new(0.24, 0.24, 0.7), offset = at(0, 2.54, 2.16) * CFrame.Angles(-0.9, 0, 0), color = D.Saddle, sphere = true },
		{ name = "Tail2_Tip", size = Vector3.new(0.2, 0.2, 0.34), offset = at(0, 2.82, 2.38) * CFrame.Angles(-0.9, 0, 0), color = D.TanLight, sphere = true },
	},
})

export type Bone = { name: string, parent: string?, pivot: Vector3 }

-- Кости собаки по порядку (родитель раньше ребёнка). pivot — точка вращения в системе модели.
ClassModels.DogBones = {
	{ name = "Body", parent = nil, pivot = Vector3.new(0, 1.5, 0) },
	{ name = "Head", parent = "Body", pivot = Vector3.new(0, 2.32, -1.42) }, -- верх шеи
	{ name = "Jaw", parent = "Head", pivot = Vector3.new(0, 2.36, -1.8) }, -- шарнир челюсти
	{ name = "Tail1", parent = "Body", pivot = Vector3.new(0, 1.9, 1.32) }, -- корень хвоста
	{ name = "Tail2", parent = "Tail1", pivot = Vector3.new(0, 2.29, 1.96) },
	{ name = "LegFL", parent = "Body", pivot = Vector3.new(-0.38, 1.45, -0.92) }, -- плечи
	{ name = "LegFR", parent = "Body", pivot = Vector3.new(0.38, 1.45, -0.92) },
	{ name = "LegBL", parent = "Body", pivot = Vector3.new(-0.42, 1.5, 0.92) }, -- бёдра
	{ name = "LegBR", parent = "Body", pivot = Vector3.new(0.42, 1.5, 0.92) },
} :: { Bone }

local BONE_NAMES: { [string]: boolean } = {}
for _, bone in ClassModels.DogBones do
	BONE_NAMES[bone.name] = true
end

-- Кость детали: атрибут Bone или начало имени до «_»; иначе — туловище.
function ClassModels.boneOf(part: BasePart): string
	local attr = part:GetAttribute("Bone")
	if typeof(attr) == "string" and BONE_NAMES[attr] then
		return attr
	end
	local prefix = string.match(part.Name, "^(%w+)_")
	if prefix and BONE_NAMES[prefix] then
		return prefix
	end
	return "Body"
end

-- Нашивки K-9 на жилете (SurfaceGui видно в мире; в ViewportFrame карточки — нет).
local function labelDog(model: Model)
	for _, name in { "Body_PatchL", "Body_PatchR" } do
		local patch = model:FindFirstChild(name, true)
		if patch and patch:IsA("BasePart") then
			local gui = Instance.new("SurfaceGui")
			gui.Face = if name == "Body_PatchL" then Enum.NormalId.Left else Enum.NormalId.Right
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 80
			gui.LightInfluence = 1
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 0.7)
			label.Position = UDim2.fromScale(0, 0.15)
			label.Text = "K-9"
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = D.Yellow
			label.Parent = gui
			gui.Parent = patch
		end
	end
end

-- Собака: модель (своя или друга) и точки вращения костей (из Attachment Bone_* в модели друга, если есть).
function ClassModels.dog(): (Built, { [string]: Vector3 })
	local built = WeaponModels.fromSpecs(ClassModels.Names.Dog, DOG)
	local pivots: { [string]: Vector3 } = {}
	for _, bone in ClassModels.DogBones do
		pivots[bone.name] = bone.pivot
	end
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local template = folder and folder:FindFirstChild(ClassModels.Names.Dog)
	if template and template:IsA("Model") then
		local origin = template:GetPivot()
		for _, descendant in template:GetDescendants() do
			if descendant:IsA("Attachment") then
				local boneName = string.match(descendant.Name, "^Bone_(%w+)$")
				if boneName and BONE_NAMES[boneName] then
					pivots[boneName] = origin:PointToObjectSpace(descendant.WorldPosition)
				end
			end
		end
	else
		labelDog(built.model)
	end
	return built, pivots
end

---------------------------------------------------------------- датчик движения

local S = {
	Body = hex("F8FAFC"),
	Bezel = hex("2E3545"),
	Lens = hex("D8F3FF"),
	Steel = hex("8D9BB2"),
	SteelDark = hex("2E3545"),
	Rubber = hex("14171F"),
	Yellow = hex("FFD036"),
	Green = hex("38F28A"),
	Red = hex("FF3B4E"),
}

-- Нога треноги: цилиндр от ступни до втулки.
local function tripodLeg(index: number): { Spec }
	local angle = math.rad(90 + index * 120)
	local foot = Vector3.new(math.cos(angle) * 0.62, 0.08, math.sin(angle) * 0.62)
	local top = Vector3.new(math.cos(angle) * 0.07, 1.22, math.sin(angle) * 0.07)
	local length = (top - foot).Magnitude
	return {
		{ name = "Leg" .. index, size = Vector3.new(length, 0.08, 0.08), offset = CFrame.lookAt((foot + top) / 2, top) * ALONG_Z, color = S.Steel, material = M.Metal, shape = CYL },
		{ name = "Foot" .. index, size = Vector3.new(0.17, 0.17, 0.17), offset = CFrame.new(foot), color = S.Rubber, shape = BALL },
	}
end

local SENSOR: { Spec } = joinSpecs({
	tripodLeg(0),
	tripodLeg(1),
	tripodLeg(2),
	{
		{ name = "Hub", size = Vector3.new(0.26, 0.34, 0.34), offset = at(0, 1.27, 0) * ALONG_Y, color = S.SteelDark, material = M.Metal, shape = CYL },
		{ name = "Stripe", size = Vector3.new(0.08, 0.31, 0.31), offset = at(0, 1.43, 0) * ALONG_Y, color = S.Yellow, shape = CYL },
		{ name = "Mast", size = Vector3.new(0.62, 0.12, 0.12), offset = at(0, 1.72, 0) * ALONG_Y, color = S.Steel, material = M.Metal, shape = CYL },
		{ name = "Bracket", size = Vector3.new(0.34, 0.2, 0.32), offset = at(0, 2.0, 0.04), color = S.SteelDark, material = M.Metal },
		-- корпус: белая «капсула», тёмная рамка, матовая линза Френеля, лампочка, антенна
		{ name = "Housing", size = Vector3.new(0.96, 0.76, 0.62), offset = at(0, 2.32, 0), color = S.Body, sphere = true },
		{ name = "Bezel", size = Vector3.new(0.7, 0.52, 0.08), offset = at(0, 2.3, -0.27), color = S.Bezel },
		{ name = "Lens", size = Vector3.new(0.52, 0.4, 0.3), offset = at(0, 2.3, -0.31), color = S.Lens, material = M.Glass, transparency = 0.12, sphere = true },
		{ name = "Lamp", size = Vector3.new(0.14, 0.14, 0.14), offset = at(0.29, 2.52, -0.24), color = S.Green, shape = BALL, neon = true },
		{ name = "Antenna", size = Vector3.new(0.5, 0.05, 0.05), offset = at(-0.3, 2.85, 0.14) * ALONG_Y, color = S.Rubber, shape = CYL },
		{ name = "AntennaTip", size = Vector3.new(0.1, 0.1, 0.1), offset = at(-0.3, 3.11, 0.14), color = S.Red, shape = BALL },
		{ name = "Label", size = Vector3.new(0.5, 0.16, 0.04), offset = at(0, 2.32, 0.31), color = S.Yellow },
	},
})

-- Датчик движения на треноге. Лампочка — деталь Lamp (мигает у клиентов).
function ClassModels.sensor(): Built
	local built = WeaponModels.fromSpecs(ClassModels.Names.Sensor, SENSOR)
	local label = built.model:FindFirstChild("Label")
	if label and label:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = "MOTION"
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = S.Rubber
		text.Parent = gui
		gui.Parent = label
	end
	return built
end

---------------------------------------------------------------- картинки карточек

-- Кроссовок патруля с полосками скорости позади.
local SNEAKER: { Spec } = {
	{ name = "Sole", size = Vector3.new(1.0, 0.26, 2.3), offset = at(0, 0.13, 0.05), color = hex("F2F2EE") },
	{ name = "SoleToe", size = Vector3.new(1.0, 0.26, 0.7), offset = at(0, 0.13, -1.1), color = hex("F2F2EE"), sphere = true },
	{ name = "Tread", size = Vector3.new(1.02, 0.08, 2.6), offset = at(0, 0.04, -0.05), color = hex("2B2F3A") },
	{ name = "Upper", size = Vector3.new(0.94, 0.86, 1.9), offset = at(0, 0.62, 0.12), color = hex("1E2A44"), sphere = true },
	{ name = "Toe", size = Vector3.new(0.9, 0.56, 0.9), offset = at(0, 0.44, -0.78), color = hex("F2F2EE"), sphere = true },
	{ name = "Collar", size = Vector3.new(0.82, 0.3, 0.7), offset = at(0, 1.02, 0.55), color = hex("141C30"), sphere = true },
	{ name = "Tongue", size = Vector3.new(0.5, 0.5, 0.18), offset = at(0, 1.05, 0.1) * CFrame.Angles(-0.4, 0, 0), color = hex("2E4170") },
	{ name = "Lace1", size = Vector3.new(0.6, 0.06, 0.08), offset = at(0, 0.98, -0.12) * CFrame.Angles(-0.5, 0, 0), color = hex("FFFFFF") },
	{ name = "Lace2", size = Vector3.new(0.6, 0.06, 0.08), offset = at(0, 0.88, -0.32) * CFrame.Angles(-0.6, 0, 0), color = hex("FFFFFF") },
	{ name = "Lace3", size = Vector3.new(0.58, 0.06, 0.08), offset = at(0, 0.76, -0.5) * CFrame.Angles(-0.7, 0, 0), color = hex("FFFFFF") },
	{ name = "StripeL", size = Vector3.new(0.04, 0.16, 1.2), offset = at(-0.47, 0.55, 0.15) * CFrame.Angles(0.3, 0, 0), color = hex("D4A93A") },
	{ name = "StripeR", size = Vector3.new(0.04, 0.16, 1.2), offset = at(0.47, 0.55, 0.15) * CFrame.Angles(0.3, 0, 0), color = hex("D4A93A") },
	{ name = "Heel", size = Vector3.new(0.4, 0.4, 0.12), offset = at(0, 0.9, 1.04), color = hex("C8343A") },
	{ name = "Speed1", size = Vector3.new(0.1, 0.1, 1.6), offset = at(0, 0.95, 2.0), color = hex("3BC6C1"), neon = true },
	{ name = "Speed2", size = Vector3.new(0.1, 0.1, 1.1), offset = at(0, 0.6, 1.85), color = hex("3BC6C1"), neon = true },
	{ name = "Speed3", size = Vector3.new(0.1, 0.1, 1.4), offset = at(0, 0.28, 2.0), color = hex("3BC6C1"), neon = true },
}

-- Смартфон с картинкой камеры на экране и камера наблюдения на кронштейне.
local OPERATOR: { Spec } = {
	{ name = "Phone", size = Vector3.new(1.1, 2.0, 0.14), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12), color = hex("141518") },
	{ name = "Screen", size = Vector3.new(0.96, 1.76, 0.03), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12) * at(0, 0, -0.075), color = hex("3BC6C1"), neon = true },
	{ name = "ScreenCam", size = Vector3.new(0.5, 0.3, 0.02), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12) * at(-0.05, 0.25, -0.095), color = hex("1E2A44") },
	{ name = "ScreenLens", size = Vector3.new(0.02, 0.2, 0.2), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12) * at(0.27, 0.25, -0.095) * ALONG_Z, color = hex("1E2A44"), shape = CYL },
	{ name = "ScreenRec", size = Vector3.new(0.02, 0.1, 0.1), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12) * at(-0.32, 0.72, -0.095) * ALONG_Z, color = hex("FF3B3B"), shape = CYL, neon = true },
	{ name = "ScreenBar", size = Vector3.new(0.7, 0.08, 0.02), offset = at(-0.45, 1.0, 0) * CFrame.Angles(0, 0.25, 0.12) * at(0, -0.55, -0.095), color = hex("1E2A44") },
	{ name = "Mount", size = Vector3.new(0.3, 1.4, 0.3), offset = at(0.85, 2.0, 0.3), color = hex("3A3F4B"), material = M.Metal },
	{ name = "Swivel", size = Vector3.new(0.4, 0.4, 0.4), offset = at(0.85, 2.75, 0.3), color = hex("3A3F4B"), material = M.Metal, shape = BALL },
	{ name = "CamBody", size = Vector3.new(0.7, 0.6, 1.2), offset = at(0.85, 2.85, -0.25) * CFrame.Angles(-0.2, -0.35, 0), color = hex("DDE1E6") },
	{ name = "CamHood", size = Vector3.new(0.82, 0.1, 1.4), offset = at(0.85, 2.85, -0.25) * CFrame.Angles(-0.2, -0.35, 0) * at(0, 0.36, -0.1), color = hex("3A3F4B"), material = M.Metal },
	{ name = "CamLens", size = Vector3.new(0.2, 0.42, 0.42), offset = at(0.85, 2.85, -0.25) * CFrame.Angles(-0.2, -0.35, 0) * at(0, 0, -0.65) * ALONG_Z, color = hex("15181F"), shape = CYL },
	{ name = "CamLed", size = Vector3.new(0.1, 0.1, 0.1), offset = at(0.85, 2.85, -0.25) * CFrame.Angles(-0.2, -0.35, 0) * at(0.25, 0.18, -0.6), color = hex("FF3B3B"), shape = BALL, neon = true },
}

-- Картинка карточки класса: Patrol — кроссовок, Operator — телефон с камерой.
function ClassModels.icon(role: string): Built
	if role == "Operator" then
		return WeaponModels.fromSpecs(ClassModels.Names.IconOperator, OPERATOR)
	end
	return WeaponModels.fromSpecs(ClassModels.Names.IconPatrol, SNEAKER)
end

return ClassModels
