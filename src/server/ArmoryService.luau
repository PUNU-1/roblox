-- Оружейная (блок 4) в конце служебного коридора. Всё строится от оружейной стойки на стене (Map.Props.ArmoryRack):
--  • стеклянный прилавок-витрина: внутри на бархате шокер, пистолет, дробовик, автомат, перед каждым — ценник;
--  • стол с аптечкой и тремя коробками патронов (к пистолету, автомату, дробовику);
--  • манекен в бронежилете;
--  • на стене — то же оружие для красоты, над прилавком табличка «FIREARMS ONLY DURING A RAID».
-- Покупка — днём, удержанием F (Purchase): каждый покупает себе, без складчины. Кнопка, которая игроку не нужна
-- (уже есть, полная броня, патроны к оружию, которого нет), у него не видна (BuyPrompts.client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local Purchase = require(Server:WaitForChild("Purchase"))
local WeaponService = require(Server:WaitForChild("WeaponService"))
local HealthService = require(Server:WaitForChild("HealthService"))
local ShopService = require(Server:WaitForChild("ShopService"))

local Goods = Config.Armory.Goods

local ArmoryService = {}

local prompts: { ProximityPrompt } = {}
local buyParts: { [string]: BasePart } = {} -- товар → деталь с его кнопкой (звук кассы при покупке из окна)
local folder: Model

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local COLORS = {
	Cabinet = hex("2B2F3A"),
	CabinetTop = hex("3A3F4B"),
	Trim = hex("D4A93A"),
	Velvet = hex("7A1E2B"),
	Glass = hex("CFEFFF"),
	Wood = hex("6B4A2E"),
	Steel = hex("8A93A6"),
	Paper = hex("F2EEE6"),
	Navy = hex("1E2A44"),
	Red = hex("C8343A"),
	Mannequin = hex("D9C9B0"),
}

local M = Enum.Material

---------------------------------------------------------------- помощники

local function textCard(part: BasePart, face: Enum.NormalId, lines: { { text: string, color: Color3 } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = gui
	for index, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = index
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Text = line.text
		label.TextColor3 = line.color
		label.Parent = gui
	end
	gui.Parent = part
end

-- Ценник: тёмная карточка с золотой рамкой, имя товара и цена.
local function priceTag(cframe: CFrame, title: string, price: number)
	local card = ModelLibrary.place("prop_pricetag_01", cframe, {
		{ name = "Frame", size = Vector3.new(1.9, 0.75, 0.05), offset = CFrame.new(0, 0, 0.02), color = COLORS.Trim, material = M.Metal },
		{ name = "Card", size = Vector3.new(1.8, 0.65, 0.06), offset = CFrame.identity, color = COLORS.Navy },
	}, folder)
	local face = card:FindFirstChild("Card")
	if face and face:IsA("BasePart") then
		textCard(face, Enum.NormalId.Front, {
			{ text = string.upper(title), color = Color3.new(1, 1, 1) },
			{ text = ("$%d"):format(price), color = COLORS.Trim },
		})
	end
end

-- Личная покупка (кнопка F у товара или окно магазина — fromShop, без проверки расстояния): только днём, если
-- товар игроку нужен (GameState.armoryOffer) и хватает денег. true — куплено.
local function sell(player: Player, item: string, fromShop: boolean): boolean
	local good = (Goods :: any)[item]
	local part = buyParts[item]
	if not good or not part or GameState.phase() ~= GameState.Phase.Day then
		return false
	end
	local show = GameState.armoryOffer(player, item)
	if not show or not Purchase.takeFull(player, part, good.Price, fromShop) then
		return false
	end
	if good.Kind == "Weapon" then
		WeaponService.grantWeapon(player, item)
	elseif good.Kind == "Ammo" then
		WeaponService.grantAmmo(player, good.Weapon)
	elseif good.Kind == "Medkit" then
		WeaponService.grantMedkit(player)
	elseif good.Kind == "Vest" then
		HealthService.setArmor(player, Config.Weapons.Vest.Armor)
	end
	-- Анимация (этап 8, блок O): бронежилет надевает сразу, у стойки — тянется и берёт товар
	if good.Kind == "Vest" then
		GameState.setAction(player, "Vest", Config.Actions.VestSeconds)
	elseif not fromShop then
		GameState.setAction(player, "Buy", Config.Actions.BuySeconds)
	end
	return true
end

-- Невидимая деталь с кнопкой покупки над товаром.
local function buyPoint(item: string, position: Vector3)
	local good = (Goods :: any)[item]
	local part = Instance.new("Part")
	part.Name = "Buy_" .. item
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = folder
	local prompt = Purchase.newPersonalPrompt(part, "BuyPrompt_" .. item, good.Price, item)
	prompt.ObjectText = good.Title
	prompt.Triggered:Connect(function(player)
		sell(player, item, false)
	end)
	table.insert(prompts, prompt)
	buyParts[item] = part
end

local function display(kind: string, cframe: CFrame)
	local built = WeaponModels.build(kind)
	WeaponModels.anchor(built, cframe)
	built.model.Parent = folder
end

---------------------------------------------------------------- прилавок с оружием

-- Стеклянный прилавок (R3): тумба с дверцами, замком и подсветкой цоколя, бархат с ложементами,
-- внутренний светильник, стеклянный короб с золотыми рёбрами и табличка Sign (для textCard). Низ по центру, перед в −Z.
local CASE_W, CASE_D = 16, 2.6
local function buildCaseStub(): { ModelLibrary.StubPart }
	local darkMetal = hex("1C1F26")
	local brassDark = hex("B8892A")
	local list: { ModelLibrary.StubPart } = {
		{ name = "Cabinet", size = Vector3.new(CASE_W, 2.4, CASE_D), offset = CFrame.new(0, 1.2, 0), color = COLORS.Cabinet, material = M.Metal },
		{ name = "Kick", size = Vector3.new(CASE_W - 0.2, 0.3, CASE_D - 0.3), offset = CFrame.new(0, 0.15, 0.05), color = darkMetal },
		{ name = "ToeGlow", size = Vector3.new(CASE_W - 0.5, 0.05, 0.06), offset = CFrame.new(0, 0.3, -CASE_D / 2 + 0.08), color = COLORS.Red, material = M.Neon, collide = false },
		{ name = "Panel", size = Vector3.new(CASE_W - 0.6, 1.6, 0.06), offset = CFrame.new(0, 1.3, -CASE_D / 2 - 0.02), color = COLORS.CabinetTop, material = M.Metal },
		{ name = "Stripe", size = Vector3.new(CASE_W - 0.6, 0.12, 0.08), offset = CFrame.new(0, 2.25, -CASE_D / 2 - 0.03), color = COLORS.Trim, material = M.Metal },
		{ name = "WaistCap", size = Vector3.new(CASE_W + 0.12, 0.12, CASE_D + 0.12), offset = CFrame.new(0, 2.4, 0), color = brassDark, material = M.Metal, collide = false },
		{ name = "Velvet", size = Vector3.new(CASE_W - 0.3, 0.1, CASE_D - 0.3), offset = CFrame.new(0, 2.45, 0), color = COLORS.Velvet, material = M.Fabric },
		{ name = "Glass", size = Vector3.new(CASE_W - 0.2, 1.05, CASE_D - 0.2), offset = CFrame.new(0, 2.95, 0), color = COLORS.Glass, material = M.Glass, transparency = 0.65 },
		{ name = "LightBar", size = Vector3.new(CASE_W - 0.7, 0.05, 0.14), offset = CFrame.new(0, 3.41, 0), color = hex("FFE7B8"), material = M.Neon, collide = false },
		{ name = "EdgeFL", size = Vector3.new(CASE_W, 0.09, 0.09), offset = CFrame.new(0, 3.48, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "EdgeBL", size = Vector3.new(CASE_W, 0.09, 0.09), offset = CFrame.new(0, 3.48, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "EdgeL", size = Vector3.new(0.09, 0.09, CASE_D), offset = CFrame.new(-CASE_W / 2 + 0.06, 3.48, 0), color = COLORS.Trim, material = M.Metal },
		{ name = "EdgeR", size = Vector3.new(0.09, 0.09, CASE_D), offset = CFrame.new(CASE_W / 2 - 0.06, 3.48, 0), color = COLORS.Trim, material = M.Metal },
		{ name = "PostFL", size = Vector3.new(0.09, 1.05, 0.09), offset = CFrame.new(-CASE_W / 2 + 0.06, 2.95, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "PostFR", size = Vector3.new(0.09, 1.05, 0.09), offset = CFrame.new(CASE_W / 2 - 0.06, 2.95, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "PostBL", size = Vector3.new(0.09, 1.05, 0.09), offset = CFrame.new(-CASE_W / 2 + 0.06, 2.95, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "PostBR", size = Vector3.new(0.09, 1.05, 0.09), offset = CFrame.new(CASE_W / 2 - 0.06, 2.95, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
		{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(-5, 2.95, 0), color = COLORS.Trim, material = M.Metal },
		{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(-2.6, 2.95, 0), color = COLORS.Trim, material = M.Metal },
		{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(2.6, 2.95, 0), color = COLORS.Trim, material = M.Metal },
		{ name = "SignBezel", size = Vector3.new(7.24, 0.8, 0.06), offset = CFrame.new(0, 1.1, -CASE_D / 2 - 0.04), color = COLORS.Trim, material = M.Metal, collide = false },
		{ name = "Sign", size = Vector3.new(7, 0.6, 0.06), offset = CFrame.new(0, 1.1, -CASE_D / 2 - 0.08), color = COLORS.Red },
	}
	-- Дверцы тумбы с ручками сзади/спереди и боковые щитки
	for _, x in { -5.4, 5.4 } do
		table.insert(list, { name = "DoorPanel", size = Vector3.new(3.6, 1.28, 0.05), offset = CFrame.new(x, 1.15, -CASE_D / 2 - 0.04), color = darkMetal, material = M.Metal, collide = false })
		table.insert(list, { name = "DoorHandle", size = Vector3.new(0.5, 0.08, 0.08), offset = CFrame.new(x, 1.56, -CASE_D / 2 - 0.09), color = COLORS.Trim, material = M.Metal, collide = false })
	end
	for _, x in { -CASE_W / 2 - 0.02, CASE_W / 2 + 0.02 } do
		table.insert(list, { name = "SidePanel", size = Vector3.new(0.05, 1.6, CASE_D - 0.5), offset = CFrame.new(x, 1.3, 0), color = COLORS.CabinetTop, material = M.Metal, collide = false })
	end
	-- Угловые шары-колпачки и ложементы под каждый образец оружия
	for _, x in { -CASE_W / 2 + 0.06, CASE_W / 2 - 0.06 } do
		for _, z in { -CASE_D / 2 + 0.06, CASE_D / 2 - 0.06 } do
			table.insert(list, { name = "CornerCap", size = Vector3.new(0.18, 0.18, 0.18), offset = CFrame.new(x, 3.52, z), color = COLORS.Trim, material = M.Metal, shape = Enum.PartType.Ball, collide = false })
		end
	end
	for _, cradle in { { x = -6.3, w = 1.1 }, { x = -3.8, w = 1.2 }, { x = 0, w = 2.6 }, { x = 5.3, w = 2.6 } } do
		table.insert(list, { name = "Cradle", size = Vector3.new(cradle.w, 0.06, 0.8), offset = CFrame.new(cradle.x, 2.53, 0.1), color = brassDark, material = M.Metal, collide = false })
	end
	return list
end
local CASE_STUB: { ModelLibrary.StubPart } = buildCaseStub()

-- Что лежит в прилавке: место вдоль прилавка (x) и где у модели середина относительно рукояти (вдоль ствола).
local CASE_ITEMS = {
	{ item = "Taser", x = -6.3, center = 0.35 },
	{ item = "Pistol", x = -3.8, center = 0.35 },
	{ item = "Shotgun", x = 0, center = 0.8 },
	{ item = "Rifle", x = 5.3, center = 0.8 },
}

local function buildCase(rack: CFrame)
	local base = rack * CFrame.new(0, 0, -8.5)
	local case = ModelLibrary.place("prop_armory_case_01", base, CASE_STUB, folder)
	local sign = case:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		textCard(sign, Enum.NormalId.Front, { { text = "FIREARMS ONLY DURING A RAID", color = Color3.new(1, 1, 1) } })
	end
	for _, entry in CASE_ITEMS do
		local good = (Goods :: any)[entry.item]
		-- Лежит на боку на бархате, стволом влево вдоль прилавка
		local lie = base * CFrame.new(entry.x + entry.center, 2.66, 0.1) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		display(entry.item, lie)
		priceTag(base * CFrame.new(entry.x, 3.15, -CASE_D / 2 - 0.08) * CFrame.Angles(0.35, 0, 0), good.Title, good.Price)
		buyPoint(entry.item, (base * CFrame.new(entry.x, 3.4, 0)).Position)
	end
end

---------------------------------------------------------------- стол с патронами и аптечками

local function buildTableStub(): { ModelLibrary.StubPart }
	local darkSteel = hex("2B2F3A")
	local list: { ModelLibrary.StubPart } = {
		{ name = "Top", size = Vector3.new(12, 0.25, 3), offset = CFrame.new(0, 2.9, 0), color = COLORS.Wood, material = M.Wood },
		{ name = "Edge", size = Vector3.new(12.12, 0.14, 3.12), offset = CFrame.new(0, 2.74, 0), color = COLORS.Steel, material = M.Metal },
		{ name = "ApronF", size = Vector3.new(11.4, 0.22, 0.08), offset = CFrame.new(0, 2.58, -1.35), color = darkSteel, material = M.Metal, collide = false },
		{ name = "ApronB", size = Vector3.new(11.4, 0.22, 0.08), offset = CFrame.new(0, 2.58, 1.35), color = darkSteel, material = M.Metal, collide = false },
		{ name = "Shelf", size = Vector3.new(11.4, 0.15, 2.6), offset = CFrame.new(0, 0.7, 0), color = COLORS.Steel, material = M.Metal },
		{ name = "ShelfLipF", size = Vector3.new(11.4, 0.12, 0.06), offset = CFrame.new(0, 0.82, -1.27), color = darkSteel, material = M.Metal, collide = false },
		{ name = "ShelfLipB", size = Vector3.new(11.4, 0.12, 0.06), offset = CFrame.new(0, 0.82, 1.27), color = darkSteel, material = M.Metal, collide = false },
		{ name = "MatRoll", size = Vector3.new(1.8, 0.52, 0.52), offset = CFrame.new(4.9, 1.04, 0.4) * CFrame.Angles(0, math.rad(18), 0), color = COLORS.Navy, material = M.Fabric, shape = Enum.PartType.Cylinder, collide = false },
	}
	for _, x in { -5.8, 5.8 } do
		for _, z in { -1.35, 1.35 } do
			table.insert(list, { name = "Leg", size = Vector3.new(0.26, 2.78, 0.26), offset = CFrame.new(x, 1.39, z), color = COLORS.Steel, material = M.Metal })
			table.insert(list, { name = "Foot", size = Vector3.new(0.12, 0.4, 0.4), offset = CFrame.new(x, 0.06, z) * CFrame.Angles(0, 0, math.pi / 2), color = darkSteel, material = M.Rubber, shape = Enum.PartType.Cylinder, collide = false })
			table.insert(list, { name = "CornerBumper", size = Vector3.new(0.32, 0.28, 0.32), offset = CFrame.new(x * 1.015, 2.9, z * 1.03), color = darkSteel, material = M.Metal, collide = false })
		end
	end
	for _, x in { -5.45, 5.45 } do
		table.insert(list, { name = "Gusset", size = Vector3.new(0.16, 0.55, 0.55), offset = CFrame.new(x, 2.42, -1.15) * CFrame.Angles(0, math.rad(if x < 0 then 90 else -90), 0), color = darkSteel, material = M.Metal, wedge = true, collide = false })
	end
	-- Детализированные ящики на нижней полке с обвязкой и замками
	for index, x in { -3.6, -0.2, 3.1 } do
		local crateColor = if index == 2 then hex("5A4A2E") else hex("4B5A3A")
		local dark = crateColor:Lerp(Color3.new(0, 0, 0), 0.25)
		table.insert(list, { name = "Crate", size = Vector3.new(2.4, 1.08, 1.8), offset = CFrame.new(x, 1.32, 0), color = crateColor, material = M.Wood })
		table.insert(list, { name = "CrateLid", size = Vector3.new(2.48, 0.14, 1.88), offset = CFrame.new(x, 1.9, 0), color = dark, material = M.Wood, collide = false })
		table.insert(list, { name = "CrateBandL", size = Vector3.new(0.14, 1.12, 1.84), offset = CFrame.new(x - 0.85, 1.32, 0), color = darkSteel, material = M.Metal, collide = false })
		table.insert(list, { name = "CrateBandR", size = Vector3.new(0.14, 1.12, 1.84), offset = CFrame.new(x + 0.85, 1.32, 0), color = darkSteel, material = M.Metal, collide = false })
		table.insert(list, { name = "CrateClasp", size = Vector3.new(0.24, 0.28, 0.06), offset = CFrame.new(x, 1.72, -0.92), color = COLORS.Trim, material = M.Metal, collide = false })
	end
	return list
end
local TABLE_STUB: { ModelLibrary.StubPart } = buildTableStub()

-- Коробка патронов (R3): армейский ящик своего цвета с фасками крышки, уплотнителем, боковыми рёбрами,
-- петлями, рычагом-защёлкой с проволочным кольцом, ножками и откидной ручкой; Label / LabelBack сохранены.
local AMMO_LOOK = {
	PistolAmmo = { name = "prop_ammo_pistol_01", color = hex("3F6B3A"), label = "9MM", weapon = "PISTOL", round = hex("D9A441"), tip = hex("B87333"), shell = false },
	RifleAmmo = { name = "prop_ammo_rifle_01", color = hex("6B6B3A"), label = "5.56", weapon = "RIFLE", round = hex("D9A441"), tip = hex("2B2F3A"), shell = false },
	ShotgunAmmo = { name = "prop_ammo_shotgun_01", color = hex("8A2A22"), label = "12 GA", weapon = "SHOTGUN", round = hex("C8343A"), tip = hex("D9A441"), shell = true },
}

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вертикально

local function ammoBoxModel(item: string): PVInstance
	local look = AMMO_LOOK[item]
	local dark = look.color:Lerp(Color3.new(0, 0, 0), 0.24)
	local light = look.color:Lerp(Color3.new(1, 1, 1), 0.16)
	local darkMetal = hex("2B2F3A")
	local stub: { ModelLibrary.StubPart } = {
		{ name = "Box", size = Vector3.new(1.5, 0.68, 0.95), offset = CFrame.new(0, 0.36, 0), color = look.color, material = M.Metal },
		{ name = "Rib", size = Vector3.new(1.53, 0.05, 0.98), offset = CFrame.new(0, 0.16, 0), color = dark, material = M.Metal },
		{ name = "Rib", size = Vector3.new(1.53, 0.05, 0.98), offset = CFrame.new(0, 0.56, 0), color = dark, material = M.Metal },
		{ name = "Gasket", size = Vector3.new(1.54, 0.04, 0.99), offset = CFrame.new(0, 0.7, 0), color = hex("1C1F26"), material = M.Rubber },
		{ name = "Lid", size = Vector3.new(1.56, 0.1, 0.86), offset = CFrame.new(0, 0.77, 0), color = light, material = M.Metal },
		{ name = "LidBevelF", size = Vector3.new(1.56, 0.1, 0.08), offset = CFrame.new(0, 0.77, -0.47), color = light, material = M.Metal, wedge = true },
		{ name = "LidBevelB", size = Vector3.new(1.56, 0.1, 0.08), offset = CFrame.new(0, 0.77, 0.47) * CFrame.Angles(0, math.pi, 0), color = light, material = M.Metal, wedge = true },
		-- Рычаг-защёлка на правом боку
		{ name = "Latch", size = Vector3.new(0.05, 0.32, 0.22), offset = CFrame.new(0.77, 0.58, 0), color = COLORS.Steel, material = M.Metal },
		{ name = "LatchWire", size = Vector3.new(0.04, 0.12, 0.24), offset = CFrame.new(0.79, 0.44, 0), color = darkMetal, material = M.Metal },
		{ name = "LatchPivot", size = Vector3.new(0.08, 0.11, 0.11), offset = CFrame.new(0.79, 0.74, 0), color = darkMetal, material = M.Metal, shape = Enum.PartType.Cylinder },
		-- Петли сзади и откидная ручка сверху
		{ name = "HingeL", size = Vector3.new(0.18, 0.08, 0.08), offset = CFrame.new(-0.46, 0.71, 0.5), color = COLORS.Steel, material = M.Metal, shape = Enum.PartType.Cylinder },
		{ name = "HingeR", size = Vector3.new(0.18, 0.08, 0.08), offset = CFrame.new(0.46, 0.71, 0.5), color = COLORS.Steel, material = M.Metal, shape = Enum.PartType.Cylinder },
		{ name = "HandlePost", size = Vector3.new(0.06, 0.11, 0.06), offset = CFrame.new(-0.28, 0.87, 0), color = darkMetal, material = M.Metal },
		{ name = "HandlePost", size = Vector3.new(0.06, 0.11, 0.06), offset = CFrame.new(0.28, 0.87, 0), color = darkMetal, material = M.Metal },
		{ name = "Handle", size = Vector3.new(0.62, 0.07, 0.12), offset = CFrame.new(0, 0.94, 0), color = hex("1C1F26"), material = M.Rubber },
		-- Таблички спереди и сзади, лоток для патронов с бортиком
		{ name = "Label", size = Vector3.new(0.9, 0.36, 0.04), offset = CFrame.new(0, 0.38, -0.49), color = COLORS.Paper },
		{ name = "LabelBack", size = Vector3.new(0.9, 0.36, 0.04), offset = CFrame.new(0, 0.38, 0.49), color = COLORS.Paper },
		{ name = "Tray", size = Vector3.new(1.14, 0.06, 0.24), offset = CFrame.new(0, 0.85, 0.24), color = hex("C9A26B"), material = M.Cardboard },
		{ name = "TrayRim", size = Vector3.new(1.18, 0.05, 0.28), offset = CFrame.new(0, 0.83, 0.24), color = hex("9E7A48"), material = M.Cardboard },
	}
	for _, x in { -0.66, 0.66 } do
		for _, z in { -0.4, 0.4 } do
			table.insert(stub, { name = "CornerFoot", size = Vector3.new(0.14, 0.04, 0.14), offset = CFrame.new(x, 0.02, z), color = darkMetal, material = M.Rubber })
		end
	end
	for _, x in { -0.76, 0.76 } do
		table.insert(stub, { name = "SideRib", size = Vector3.new(0.03, 0.34, 0.46), offset = CFrame.new(x, 0.36, 0), color = dark, material = M.Metal })
	end
	-- Значок-патрон справа от таблички (спереди) и с другой стороны сзади
	for _, side in { { x = 0.6, z = -0.5 }, { x = -0.6, z = 0.5 } } do
		if look.shell then
			table.insert(stub, { name = "IconShell", size = Vector3.new(0.24, 0.13, 0.13), offset = CFrame.new(side.x, 0.4, side.z) * UPRIGHT, color = look.round, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "IconBase", size = Vector3.new(0.08, 0.135, 0.135), offset = CFrame.new(side.x, 0.24, side.z) * UPRIGHT, color = look.tip, material = M.Metal, shape = Enum.PartType.Cylinder })
		else
			table.insert(stub, { name = "IconCase", size = Vector3.new(0.22, 0.1, 0.1), offset = CFrame.new(side.x, 0.33, side.z) * UPRIGHT, color = look.round, material = M.Metal, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "IconTip", size = Vector3.new(0.1, 0.1, 0.1), offset = CFrame.new(side.x, 0.45, side.z), color = look.tip, material = M.Metal, shape = Enum.PartType.Ball })
		end
	end
	-- Патроны на лотке
	for index = 0, 3 do
		local x = -0.45 + index * 0.3
		if look.shell then
			table.insert(stub, { name = "Shell", size = Vector3.new(0.42, 0.16, 0.16), offset = CFrame.new(x, 1.09, 0.25) * UPRIGHT, color = look.round, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "Brass", size = Vector3.new(0.12, 0.17, 0.17), offset = CFrame.new(x, 0.94, 0.25) * UPRIGHT, color = look.tip, material = M.Metal, shape = Enum.PartType.Cylinder })
		else
			table.insert(stub, { name = "Case", size = Vector3.new(0.3, 0.1, 0.1), offset = CFrame.new(x, 1.03, 0.25) * UPRIGHT, color = look.round, material = M.Metal, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "Tip", size = Vector3.new(0.11, 0.11, 0.11), offset = CFrame.new(x, 1.2, 0.25), color = look.tip, material = M.Metal, shape = Enum.PartType.Ball })
		end
	end
	local box = ModelLibrary.build(look.name, stub)
	local lines = { { text = look.label, color = COLORS.Navy }, { text = look.weapon, color = dark } }
	local label = box:FindFirstChild("Label")
	if label and label:IsA("BasePart") then
		textCard(label, Enum.NormalId.Front, lines)
	end
	local labelBack = box:FindFirstChild("LabelBack")
	if labelBack and labelBack:IsA("BasePart") then
		textCard(labelBack, Enum.NormalId.Back, lines)
	end
	return box
end

local function ammoBox(item: string, cframe: CFrame)
	local box = ammoBoxModel(item)
	ModelLibrary.forEachPart(box, function(part)
		part.Anchored = true
	end)
	box:PivotTo(cframe)
	box.Parent = folder
end

local TABLE_ITEMS = {
	{ item = "Medkit", x = -4.5 },
	{ item = "PistolAmmo", x = -1.5 },
	{ item = "RifleAmmo", x = 1.5 },
	{ item = "ShotgunAmmo", x = 4.5 },
}

local function buildTable(rack: CFrame)
	local base = rack * CFrame.new(-2, 0, -19)
	ModelLibrary.place("prop_supply_table_01", base, TABLE_STUB, folder)
	local top = 3.03
	for _, entry in TABLE_ITEMS do
		local good = (Goods :: any)[entry.item]
		local spot = base * CFrame.new(entry.x, top, 0.2)
		if entry.item == "Medkit" then
			display("Medkit", spot * CFrame.new(0, 0.99, 0)) -- ножки аптечки на столе
		else
			ammoBox(entry.item, spot)
		end
		-- Ценники с обеих сторон стола: подойти можно и от двери, и от прилавка
		priceTag(base * CFrame.new(entry.x, 2.6, -1.62), good.Title, good.Price)
		priceTag(base * CFrame.new(entry.x, 2.6, 1.62) * CFrame.Angles(0, math.pi, 0), good.Title, good.Price)
		buyPoint(entry.item, (spot * CFrame.new(0, 0.9, 0)).Position)
	end
end

---------------------------------------------------------------- манекен в бронежилете

-- Манекен в бронежилете (R3): ступенчатое основание с золотой каймой, телескопическая стойка
-- с зажимом, талия и голова-болванка; Torso (2 × 1.6 × 1 на y = 4.15) сохранён под guard_vest_01.
local MANNEQUIN_STUB: { ModelLibrary.StubPart } = {
	{ name = "Base", size = Vector3.new(0.2, 2.2, 2.2), offset = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder },
	{ name = "BaseRing", size = Vector3.new(0.12, 1.65, 1.65), offset = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Trim, material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "PoleCollar", size = Vector3.new(0.24, 0.56, 0.56), offset = CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Steel, material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Pole", size = Vector3.new(2.6, 0.26, 0.26), offset = CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Steel, material = M.Metal, shape = Enum.PartType.Cylinder },
	{ name = "LockCollar", size = Vector3.new(0.2, 0.38, 0.38), offset = CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.pi / 2), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "ThumbScrew", size = Vector3.new(0.16, 0.08, 0.08), offset = CFrame.new(0.22, 1.55, 0), color = COLORS.Trim, material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Hips", size = Vector3.new(1.9, 0.48, 1), offset = CFrame.new(0, 3.08, 0), color = COLORS.Mannequin },
	{ name = "Waist", size = Vector3.new(1.7, 0.34, 0.9), offset = CFrame.new(0, 3.44, 0), color = hex("C8B79E"), collide = false },
	{ name = "Torso", size = Vector3.new(2, 1.6, 1), offset = CFrame.new(0, 4.15, 0), color = COLORS.Mannequin },
	{ name = "ShoulderRingL", size = Vector3.new(0.1, 0.66, 0.66), offset = CFrame.new(-0.98, 4.65, 0), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "ShoulderRingR", size = Vector3.new(0.1, 0.66, 0.66), offset = CFrame.new(0.98, 4.65, 0), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "ShoulderL", size = Vector3.new(0.68, 0.68, 0.88), offset = CFrame.new(-1.05, 4.65, 0), color = COLORS.Mannequin, sphere = true },
	{ name = "ShoulderR", size = Vector3.new(0.68, 0.68, 0.88), offset = CFrame.new(1.05, 4.65, 0), color = COLORS.Mannequin, sphere = true },
	{ name = "NeckCollar", size = Vector3.new(0.12, 0.72, 0.72), offset = CFrame.new(0, 4.98, 0) * CFrame.Angles(0, 0, math.pi / 2), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder, collide = false },
	{ name = "Neck", size = Vector3.new(0.45, 0.48, 0.48), offset = CFrame.new(0, 5.2, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Mannequin, shape = Enum.PartType.Cylinder },
	{ name = "Head", size = Vector3.new(0.86, 1.04, 0.94), offset = CFrame.new(0, 5.82, -0.02), color = COLORS.Mannequin, sphere = true, collide = false },
}

local function buildMannequin(rack: CFrame)
	local spot = (rack * CFrame.new(-12, 0, -3.5)).Position
	local base = CFrame.lookAt(spot, spot + Vector3.new(-1, 0, -1))
	ModelLibrary.place("prop_mannequin_01", base, MANNEQUIN_STUB, folder)
	local torso = Vector3.new(2, 1.6, 1)
	local vest = WeaponModels.fromSpecs("guard_vest_01", WeaponModels.vestSpecs(torso))
	WeaponModels.anchor(vest, base * CFrame.new(0, 4.15, 0))
	WeaponModels.labelVest(vest.model)
	vest.model.Parent = folder
	local good = Goods.Vest
	priceTag(base * CFrame.new(0, 2.2, -1.15), good.Title, good.Price)
	buyPoint("Vest", (base * CFrame.new(0, 3.6, 0)).Position)
end

---------------------------------------------------------------- оружие на стене (для красоты)

local function buildWall(rack: CFrame)
	-- Автомат сверху, дробовик ниже: лежат стволом влево, боком к комнате; пистолет и шокер на полке
	display("Rifle", rack * CFrame.new(0.8, 5.55, -0.5) * CFrame.Angles(0, math.pi / 2, 0))
	display("Shotgun", rack * CFrame.new(1.2, 3.6, -0.5) * CFrame.Angles(0, math.pi / 2, 0))
	display("Pistol", rack * CFrame.new(-2.2, 1.77, -0.6) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2))
	display("Taser", rack * CFrame.new(2.4, 1.77, -0.6) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2))
end

---------------------------------------------------------------- окно магазина (этап 4, блок 1b)

local Weapons = Config.Weapons

-- Товары оружейной во вкладках Weapons и Gear: категория, товар, одна строка описания (числа — из Config).
local SHOP_GOODS: { { category: string, item: string, info: string } } = {
	{ category = "Weapons", item = "Taser", info = ("Stuns a thief for %d s • works every night"):format(Weapons.Taser.StunThief) },
	{ category = "Weapons", item = "Pistol", info = ("%d damage • %d-round mag • raids only"):format(Weapons.Pistol.Damage, Weapons.Pistol.MagSize) },
	{ category = "Weapons", item = "Rifle", info = ("%d damage, full auto • %d-round mag • raids only"):format(Weapons.Rifle.Damage, Weapons.Rifle.MagSize) },
	{ category = "Weapons", item = "Shotgun", info = ("%d × %d damage up close • raids only"):format(Weapons.Shotgun.Pellets, Weapons.Shotgun.Damage) },
	{ category = "Weapons", item = "PistolAmmo", info = ("+%d rounds for your pistol"):format(Weapons.Pistol.MagSize) },
	{ category = "Weapons", item = "RifleAmmo", info = ("+%d rounds for your rifle"):format(Weapons.Rifle.MagSize) },
	{ category = "Weapons", item = "ShotgunAmmo", info = ("+%d shells for your shotgun"):format(Weapons.Shotgun.MagSize) },
	{ category = "Gear", item = "Vest", info = ("+%d armor • lost before health"):format(Weapons.Vest.Armor) },
	{ category = "Gear", item = "Medkit", info = ("+%d health in %d s • carry up to %d"):format(Weapons.Medkit.Heal, Weapons.Medkit.UseSeconds, Weapons.Medkit.MaxCarry) },
}

local function goodPreview(item: string): PVInstance
	local good = (Goods :: any)[item]
	if good.Kind == "Ammo" then
		return ammoBoxModel(item)
	elseif good.Kind == "Vest" then
		local vest = WeaponModels.fromSpecs("guard_vest_01", WeaponModels.vestSpecs(Vector3.new(2, 1.6, 1)))
		WeaponModels.labelVest(vest.model)
		return vest.model
	end
	return WeaponModels.build(item).model
end

-- Почему товар оружейной сейчас не купить (или nil — можно).
local function refusal(player: Player, item: string): string?
	local good = (Goods :: any)[item]
	local show = GameState.armoryOffer(player, item)
	if not show then
		if good.Kind == "Weapon" then
			return "You already have the " .. string.lower(good.Title)
		elseif good.Kind == "Ammo" and not GameState.hasWeapon(player, good.Weapon) then
			local weapon = (Config.Weapons :: any)[good.Weapon]
			return ("Buy the %s first"):format(if weapon then string.lower(tostring(weapon.Title)) else "weapon")
		end
		return "You can't carry more"
	end
	local money = math.floor(tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0)
	if money < good.Price then
		return ("You need $%d more — tourists bring money every day"):format(good.Price - money)
	end
	return nil
end

local function registerInShop()
	for order, entry in SHOP_GOODS do
		local good = (Goods :: any)[entry.item]
		ShopService.register({
			category = entry.category,
			id = entry.item,
			title = good.Title,
			info = entry.info,
			order = order,
			price = good.Price,
			personal = entry.item,
			preview = goodPreview(entry.item),
			buy = function(player: Player): (string, string)
				local reason = refusal(player, entry.item)
				if reason then
					return ShopService.fail(reason)
				elseif not sell(player, entry.item, true) then
					return ShopService.fail("Can't buy it right now")
				end
				return GameState.ShopReply.Bought, "Bought: " .. good.Title
			end,
		})
	end
end

---------------------------------------------------------------- снаружи

-- Покупать можно днём (вечером оружейная закрыта, как и всё остальное).
function ArmoryService.setDayActive(active: boolean)
	for _, prompt in prompts do
		Purchase.setOpen(prompt, active)
	end
end

function ArmoryService.init(map: Instance)
	local rack = map:FindFirstChild(MapSchema.ArmoryRack, true)
	if not (rack and rack:IsA("PVInstance")) then
		warn("[ArmoryService] Нет оружейной стойки ArmoryRack на карте")
		return
	end
	local props = map:FindFirstChild(MapSchema.Props) or map
	folder = Instance.new("Model")
	folder.Name = "Armory"
	folder.Parent = props
	local pivot = rack:GetPivot()
	buildCase(pivot)
	buildTable(pivot)
	buildMannequin(pivot)
	buildWall(pivot)
	registerInShop()
end

return ArmoryService
