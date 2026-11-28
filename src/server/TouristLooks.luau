-- Внешний вид туристов (этап 5, блок F1): тело — стандартный персонаж Roblox из HumanoidDescription,
-- одежда и вещи — детали кодом (ModelLibrary.attachTo: Weld с явным C0 к костям, суставы не трогаются,
-- поэтому NpcAnimator двигает туриста как раньше). Каждый турист собирается случайно: волосы или шляпа
-- (от солнца, кепка, панама), тёмные очки, футболка с надписью или рубашка с рукавами, рюкзак,
-- фотоаппарат на шее, сумка на поясе, кроссовки. Шансы — Config.Tourists.Looks.
-- Модель друга с тем же именем в ReplicatedStorage/Models заменяет заглушку (имена — GEMINI.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local TouristLooks = {}

type Stub = { ModelLibrary.StubPart }

local Looks = Config.Tourists.Looks
local random = Random.new()

local SKIN = { "F5CDA8", "E0AC7E", "C68642", "8D5524", "FFDBAC", "F1C27D" }
local SHIRTS = { "E74C3C", "3498DB", "2ECC71", "F1C40F", "9B59B6", "E67E22", "1ABC9C", "FF6F91", "FFFFFF", "7FDBFF", "B4E06C" }
local PANTS = { "34495E", "2C3E50", "5D4037", "1F3A60", "4A4A4A", "C2B280", "6D8BB5" }
local HAIR = { "2B1B10", "4A2E1A", "7A4A26", "C68A3E", "E6C27A", "1A1A1A", "8C8C8C", "B5462E" }
local BRIGHT = { "E63946", "FFB703", "219EBC", "2A9D8F", "8E44AD", "FF6F91", "F77F00", "3A86FF", "06D6A0" }
local PRINTS = { "I ♥ ART", "MUSEUM", "ART LOVER", "MONA FAN", "I ♥ MUSEUMS", "SMILE!" }

local WHITE = Color3.fromHex("F7F7F2")
local BLACK = Color3.fromHex("1A1A1E")

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

local function color(list: { string }): Color3
	return Color3.fromHex(pick(list))
end

local function chance(value: number): boolean
	return random:NextNumber() < value
end

local function sizeOf(model: Model, partName: string): Vector3
	local part = model:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part.Size else Vector3.new(1, 1, 1)
end

---------------------------------------------------------------- голова

local function hair(model: Model, h: Vector3, tint: Color3, ponytail: boolean)
	local stub: Stub = {
		{ name = "Top", size = Vector3.new(h.X * 1.08, h.Y * 0.6, h.Z * 1.1), offset = CFrame.new(0, h.Y * 0.28, h.Z * 0.04), color = tint, material = Enum.Material.Fabric, sphere = true },
		{ name = "Back", size = Vector3.new(h.X * 1.04, h.Y * 0.6, h.Z * 0.42), offset = CFrame.new(0, h.Y * 0.04, h.Z * 0.36), color = tint, material = Enum.Material.Fabric },
		{ name = "Fringe", size = Vector3.new(h.X * 0.8, h.Y * 0.12, 0.12), offset = CFrame.new(h.X * 0.06, h.Y * 0.36, -h.Z * 0.5) * CFrame.Angles(0, 0, -0.12), color = tint, material = Enum.Material.Fabric },
	}
	if ponytail then
		table.insert(stub, { name = "Tie", size = Vector3.new(0.16, 0.16, 0.16), offset = CFrame.new(0, h.Y * 0.1, h.Z * 0.6), color = pick({ Color3.fromHex("E63946"), Color3.fromHex("FFB703"), Color3.fromHex("3A86FF") }), shape = Enum.PartType.Ball })
		table.insert(stub, { name = "Ponytail", size = Vector3.new(h.X * 0.3, h.Y * 0.62, h.Z * 0.28), offset = CFrame.new(0, -h.Y * 0.2, h.Z * 0.68) * CFrame.Angles(0.25, 0, 0), color = tint, material = Enum.Material.Fabric, sphere = true })
	end
	ModelLibrary.attachTo(model, "Head", "tourist_hair_01", stub, CFrame.identity)
end

local function sunHat(model: Model, h: Vector3)
	local straw = Color3.fromHex("E8D18F")
	ModelLibrary.attachTo(model, "Head", "tourist_sunhat_01", {
		{ name = "Crown", size = Vector3.new(h.Y * 0.42, h.X * 0.98, h.X * 0.98), offset = CFrame.new(0, h.Y * 0.56, 0) * CFrame.Angles(0, 0, math.pi / 2), color = straw, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "Brim", size = Vector3.new(0.06, h.X * 2.0, h.X * 2.0), offset = CFrame.new(0, h.Y * 0.36, 0) * CFrame.Angles(0, 0, math.pi / 2), color = straw, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "Ribbon", size = Vector3.new(h.Y * 0.12, h.X * 1.0, h.X * 1.0), offset = CFrame.new(0, h.Y * 0.44, 0) * CFrame.Angles(0, 0, math.pi / 2), color = color(BRIGHT), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "Flower", size = Vector3.new(0.24, 0.24, 0.12), offset = CFrame.new(h.X * 0.42, h.Y * 0.46, -h.Z * 0.2), color = Color3.fromHex("FF6F91"), shape = Enum.PartType.Ball },
	}, CFrame.identity)
end

local function cap(model: Model, h: Vector3)
	local tint = color(BRIGHT)
	local backwards = chance(0.25)
	ModelLibrary.attachTo(model, "Head", "tourist_cap_01", {
		{ name = "Crown", size = Vector3.new(h.X * 1.08, h.Y * 0.62, h.Z * 1.08), offset = CFrame.new(0, h.Y * 0.3, 0), color = tint, material = Enum.Material.Fabric, sphere = true },
		{ name = "Visor", size = Vector3.new(h.X * 0.8, 0.08, h.Z * 0.55), offset = CFrame.new(0, h.Y * 0.16, -h.Z * 0.72), color = tint:Lerp(Color3.new(0, 0, 0), 0.2), material = Enum.Material.Fabric },
		{ name = "Button", size = Vector3.new(0.14, 0.08, 0.14), offset = CFrame.new(0, h.Y * 0.62, 0), color = WHITE },
		{ name = "Logo", size = Vector3.new(h.X * 0.26, h.Y * 0.18, 0.04), offset = CFrame.new(0, h.Y * 0.36, -h.Z * 0.53) * CFrame.Angles(-0.4, 0, 0), color = WHITE },
	}, if backwards then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
end

local function bucketHat(model: Model, h: Vector3)
	local tint = pick({ Color3.fromHex("C2B280"), Color3.fromHex("6D8BB5"), Color3.fromHex("F1F1E6"), Color3.fromHex("7BA05B") })
	ModelLibrary.attachTo(model, "Head", "tourist_buckethat_01", {
		{ name = "Crown", size = Vector3.new(h.Y * 0.5, h.X * 1.06, h.X * 1.06), offset = CFrame.new(0, h.Y * 0.48, 0) * CFrame.Angles(0, 0, math.pi / 2), color = tint, material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
		{ name = "Top", size = Vector3.new(h.X * 1.0, h.Y * 0.2, h.Z * 1.0), offset = CFrame.new(0, h.Y * 0.74, 0), color = tint, material = Enum.Material.Fabric, sphere = true },
		{ name = "Brim", size = Vector3.new(0.08, h.X * 1.5, h.X * 1.5), offset = CFrame.new(0, h.Y * 0.24, 0) * CFrame.Angles(0, 0, math.pi / 2), color = tint:Lerp(Color3.new(0, 0, 0), 0.12), material = Enum.Material.Fabric, shape = Enum.PartType.Cylinder },
	}, CFrame.identity)
end

local function sunglasses(model: Model, h: Vector3)
	local frame = pick({ BLACK, Color3.fromHex("E63946"), Color3.fromHex("FFFFFF"), Color3.fromHex("D4A93A") })
	local z = -h.Z * 0.55
	ModelLibrary.attachTo(model, "Head", "tourist_sunglasses_01", {
		{ name = "Bridge", size = Vector3.new(h.X * 0.78, 0.06, 0.05), offset = CFrame.new(0, h.Y * 0.14, z), color = frame },
		{ name = "LensL", size = Vector3.new(h.X * 0.28, h.Y * 0.17, 0.05), offset = CFrame.new(-h.X * 0.19, h.Y * 0.08, z - 0.01), color = Color3.fromHex("1C2430"), material = Enum.Material.Glass, transparency = 0.05 },
		{ name = "LensR", size = Vector3.new(h.X * 0.28, h.Y * 0.17, 0.05), offset = CFrame.new(h.X * 0.19, h.Y * 0.08, z - 0.01), color = Color3.fromHex("1C2430"), material = Enum.Material.Glass, transparency = 0.05 },
		{ name = "ArmL", size = Vector3.new(0.04, 0.05, h.Z * 0.62), offset = CFrame.new(-h.X * 0.46, h.Y * 0.12, -h.Z * 0.24), color = frame },
		{ name = "ArmR", size = Vector3.new(0.04, 0.05, h.Z * 0.62), offset = CFrame.new(h.X * 0.46, h.Y * 0.12, -h.Z * 0.24), color = frame },
	}, CFrame.identity)
end

---------------------------------------------------------------- тело

local function shirtPrint(model: Model, shirt: Color3)
	local t = sizeOf(model, "UpperTorso")
	local dark = (shirt.R + shirt.G + shirt.B) < 1.6
	local prop = ModelLibrary.attachTo(model, "UpperTorso", "tourist_shirtprint_01", {
		{ name = "Print", size = Vector3.new(t.X * 0.62, t.Y * 0.3, 0.03), offset = CFrame.new(0, t.Y * 0.08, -t.Z * 0.5 - 0.01), color = shirt },
	}, CFrame.identity)
	local part = prop and prop:FindFirstChild("Print")
	if not (part and part:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = pick(PRINTS)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = if dark then WHITE else Color3.fromHex("C8343A")
	label.Parent = gui
	gui.Parent = part
end

local function backpack(model: Model)
	local t = sizeOf(model, "UpperTorso")
	local tint = color(BRIGHT)
	local dark = tint:Lerp(Color3.new(0, 0, 0), 0.25)
	local back = t.Z * 0.5
	ModelLibrary.attachTo(model, "UpperTorso", "tourist_backpack_01", {
		{ name = "Body", size = Vector3.new(t.X * 0.62, t.Y * 0.78, 0.5), offset = CFrame.new(0, -t.Y * 0.02, back + 0.25), color = tint, material = Enum.Material.Fabric },
		{ name = "Top", size = Vector3.new(t.X * 0.62, 0.2, 0.5), offset = CFrame.new(0, t.Y * 0.4, back + 0.25), color = tint, material = Enum.Material.Fabric, sphere = true },
		{ name = "Pocket", size = Vector3.new(t.X * 0.46, t.Y * 0.3, 0.16), offset = CFrame.new(0, -t.Y * 0.2, back + 0.56), color = dark, material = Enum.Material.Fabric },
		{ name = "Zip", size = Vector3.new(t.X * 0.4, 0.04, 0.04), offset = CFrame.new(0, -t.Y * 0.06, back + 0.64), color = WHITE },
		{ name = "Bottle", size = Vector3.new(0.18, 0.42, 0.18), offset = CFrame.new(t.X * 0.36, -t.Y * 0.08, back + 0.25), color = Color3.fromHex("7FDBFF"), material = Enum.Material.Glass, transparency = 0.2 },
		{ name = "StrapL", size = Vector3.new(0.14, t.Y * 0.92, 0.05), offset = CFrame.new(-t.X * 0.24, 0, -t.Z * 0.53), color = dark, material = Enum.Material.Fabric },
		{ name = "StrapR", size = Vector3.new(0.14, t.Y * 0.92, 0.05), offset = CFrame.new(t.X * 0.24, 0, -t.Z * 0.53), color = dark, material = Enum.Material.Fabric },
		{ name = "StrapTopL", size = Vector3.new(0.14, 0.06, t.Z * 1.06), offset = CFrame.new(-t.X * 0.24, t.Y * 0.5 + 0.02, 0), color = dark, material = Enum.Material.Fabric },
		{ name = "StrapTopR", size = Vector3.new(0.14, 0.06, t.Z * 1.06), offset = CFrame.new(t.X * 0.24, t.Y * 0.5 + 0.02, 0), color = dark, material = Enum.Material.Fabric },
	}, CFrame.identity)
end

local function camera(model: Model)
	local t = sizeOf(model, "UpperTorso")
	local front = -t.Z * 0.5
	local strap = pick({ BLACK, Color3.fromHex("8B5A2B"), Color3.fromHex("E63946") })
	ModelLibrary.attachTo(model, "UpperTorso", "tourist_camera_01", {
		{ name = "StrapL", size = Vector3.new(0.06, t.Y * 0.5, 0.04), offset = CFrame.new(-t.X * 0.11, t.Y * 0.26, front - 0.03) * CFrame.Angles(0, 0, -0.35), color = strap, material = Enum.Material.Fabric },
		{ name = "StrapR", size = Vector3.new(0.06, t.Y * 0.5, 0.04), offset = CFrame.new(t.X * 0.11, t.Y * 0.26, front - 0.03) * CFrame.Angles(0, 0, 0.35), color = strap, material = Enum.Material.Fabric },
		{ name = "Body", size = Vector3.new(0.6, 0.38, 0.26), offset = CFrame.new(0, -t.Y * 0.04, front - 0.15), color = BLACK },
		{ name = "Grip", size = Vector3.new(0.14, 0.38, 0.3), offset = CFrame.new(0.26, -t.Y * 0.04, front - 0.17), color = Color3.fromHex("2E2E33"), material = Enum.Material.Leather },
		{ name = "Lens", size = Vector3.new(0.24, 0.3, 0.3), offset = CFrame.new(-0.04, -t.Y * 0.05, front - 0.38) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromHex("2E2E33"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "Glass", size = Vector3.new(0.03, 0.22, 0.22), offset = CFrame.new(-0.04, -t.Y * 0.05, front - 0.51) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromHex("5AA9E6"), material = Enum.Material.Glass, shape = Enum.PartType.Cylinder },
		{ name = "Flash", size = Vector3.new(0.18, 0.08, 0.1), offset = CFrame.new(-0.16, -t.Y * 0.04 + 0.22, front - 0.15), color = Color3.fromHex("C9CED6") },
		{ name = "Button", size = Vector3.new(0.08, 0.05, 0.08), offset = CFrame.new(0.2, -t.Y * 0.04 + 0.21, front - 0.15), color = Color3.fromHex("E63946") },
	}, CFrame.identity)
end

local function waistBag(model: Model)
	local l = sizeOf(model, "LowerTorso")
	local tint = color(BRIGHT)
	ModelLibrary.attachTo(model, "LowerTorso", "tourist_waistbag_01", {
		{ name = "Belt", size = Vector3.new(l.X * 1.05, 0.1, l.Z * 1.06), offset = CFrame.new(0, l.Y * 0.2, 0), color = BLACK, material = Enum.Material.Fabric },
		{ name = "Bag", size = Vector3.new(0.85, 0.36, 0.3), offset = CFrame.new(l.X * 0.08, l.Y * 0.05, -l.Z * 0.5 - 0.15), color = tint, material = Enum.Material.Fabric },
		{ name = "Zip", size = Vector3.new(0.7, 0.04, 0.04), offset = CFrame.new(l.X * 0.08, l.Y * 0.05 + 0.1, -l.Z * 0.5 - 0.3), color = WHITE },
	}, CFrame.identity)
end

local function shoes(model: Model)
	local tint = color(BRIGHT)
	for _, foot in { "LeftFoot", "RightFoot" } do
		local f = sizeOf(model, foot)
		ModelLibrary.attachTo(model, foot, "tourist_shoe_01", {
			{ name = "Sole", size = Vector3.new(f.X * 1.1, f.Y * 0.4, f.Z * 1.16), offset = CFrame.new(0, -f.Y * 0.32, -f.Z * 0.05), color = WHITE, material = Enum.Material.Rubber },
			{ name = "Upper", size = Vector3.new(f.X * 1.06, f.Y * 0.78, f.Z * 1.1), offset = CFrame.new(0, f.Y * 0.16, -f.Z * 0.03), color = tint },
			{ name = "Laces", size = Vector3.new(f.X * 0.42, 0.05, f.Z * 0.4), offset = CFrame.new(0, f.Y * 0.57, -f.Z * 0.18), color = WHITE, material = Enum.Material.Fabric },
		}, CFrame.identity)
	end
end

---------------------------------------------------------------- сборка

-- Новый турист (ещё не в мире): случайное тело, одежда и вещи. nil — если Roblox не смог собрать персонажа.
function TouristLooks.create(isChild: boolean?): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = color(SKIN)
	local shirt = color(SHIRTS)
	local sleeves = chance(Looks.SleevesChance)
	description.HeadColor = skin
	description.TorsoColor = shirt
	description.LeftArmColor = if sleeves then shirt else skin
	description.RightArmColor = if sleeves then shirt else skin
	description.LeftLegColor = color(PANTS)
	description.RightLegColor = description.LeftLegColor
	-- Чуть разный рост и сложение: толпа не из клонов
	description.HeightScale = if isChild then random:NextNumber(0.95, 1.04) else random:NextNumber(0.9, 1.08)
	description.WidthScale = random:NextNumber(0.92, 1.08)
	local model = ModelLibrary.createRig(description)
	description:Destroy()
	if not model then
		return nil
	end
	local h = sizeOf(model, "Head")
	local hatRoll = random:NextNumber()
	local hasHat = hatRoll < Looks.HatChance
	hair(model, h, color(HAIR), not hasHat and chance(Looks.PonytailChance))
	if hasHat then
		local kind = random:NextInteger(1, 3)
		if kind == 1 then
			sunHat(model, h)
		elseif kind == 2 then
			cap(model, h)
		else
			bucketHat(model, h)
		end
	end
	if not isChild and chance(Looks.GlassesChance) then
		sunglasses(model, h)
	end
	if chance(Looks.PrintChance) then
		shirtPrint(model, shirt:Lerp(Color3.new(1, 1, 1), 0.25))
	end
	if chance(Looks.BackpackChance) then
		backpack(model)
	end
	if chance(Looks.CameraChance) then
		camera(model)
	end
	if not isChild and chance(Looks.WaistBagChance) then
		waistBag(model)
	end
	shoes(model)
	if isChild then
		model:ScaleTo(Config.Tourists.ChildScale)
	end
	return model
end

return TouristLooks
