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

-- Стеклянный прилавок: тумба, бархат внутри, стеклянный короб с золотыми рёбрами. Низ по центру, перед — в −Z.
local CASE_W, CASE_D = 16, 2.6
local CASE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Cabinet", size = Vector3.new(CASE_W, 2.4, CASE_D), offset = CFrame.new(0, 1.2, 0), color = COLORS.Cabinet, material = M.Metal },
	{ name = "Kick", size = Vector3.new(CASE_W - 0.2, 0.3, CASE_D - 0.3), offset = CFrame.new(0, 0.15, 0.05), color = hex("1C1F26") },
	{ name = "Panel", size = Vector3.new(CASE_W - 0.6, 1.6, 0.06), offset = CFrame.new(0, 1.3, -CASE_D / 2 - 0.02), color = COLORS.CabinetTop, material = M.Metal },
	{ name = "Stripe", size = Vector3.new(CASE_W - 0.6, 0.12, 0.08), offset = CFrame.new(0, 2.25, -CASE_D / 2 - 0.03), color = COLORS.Trim, material = M.Metal },
	{ name = "Velvet", size = Vector3.new(CASE_W - 0.3, 0.1, CASE_D - 0.3), offset = CFrame.new(0, 2.45, 0), color = COLORS.Velvet, material = M.Fabric },
	{ name = "Glass", size = Vector3.new(CASE_W - 0.2, 1.05, CASE_D - 0.2), offset = CFrame.new(0, 2.95, 0), color = COLORS.Glass, material = M.Glass, transparency = 0.72 },
	{ name = "EdgeFL", size = Vector3.new(CASE_W, 0.08, 0.08), offset = CFrame.new(0, 3.48, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "EdgeBL", size = Vector3.new(CASE_W, 0.08, 0.08), offset = CFrame.new(0, 3.48, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "EdgeL", size = Vector3.new(0.08, 0.08, CASE_D), offset = CFrame.new(-CASE_W / 2 + 0.06, 3.48, 0), color = COLORS.Trim, material = M.Metal },
	{ name = "EdgeR", size = Vector3.new(0.08, 0.08, CASE_D), offset = CFrame.new(CASE_W / 2 - 0.06, 3.48, 0), color = COLORS.Trim, material = M.Metal },
	{ name = "PostFL", size = Vector3.new(0.08, 1.05, 0.08), offset = CFrame.new(-CASE_W / 2 + 0.06, 2.95, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "PostFR", size = Vector3.new(0.08, 1.05, 0.08), offset = CFrame.new(CASE_W / 2 - 0.06, 2.95, -CASE_D / 2 + 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "PostBL", size = Vector3.new(0.08, 1.05, 0.08), offset = CFrame.new(-CASE_W / 2 + 0.06, 2.95, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "PostBR", size = Vector3.new(0.08, 1.05, 0.08), offset = CFrame.new(CASE_W / 2 - 0.06, 2.95, CASE_D / 2 - 0.06), color = COLORS.Trim, material = M.Metal },
	{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(-5, 2.95, 0), color = COLORS.Trim, material = M.Metal },
	{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(-2.6, 2.95, 0), color = COLORS.Trim, material = M.Metal },
	{ name = "Divider", size = Vector3.new(0.06, 0.95, CASE_D - 0.3), offset = CFrame.new(2.6, 2.95, 0), color = COLORS.Trim, material = M.Metal },
	{ name = "Sign", size = Vector3.new(7, 0.6, 0.06), offset = CFrame.new(0, 1.1, -CASE_D / 2 - 0.06), color = COLORS.Red },
}

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

local TABLE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Top", size = Vector3.new(12, 0.25, 3), offset = CFrame.new(0, 2.9, 0), color = COLORS.Wood, material = M.Wood },
	{ name = "Edge", size = Vector3.new(12.1, 0.12, 3.1), offset = CFrame.new(0, 2.74, 0), color = COLORS.Steel, material = M.Metal },
	{ name = "Shelf", size = Vector3.new(11.4, 0.15, 2.6), offset = CFrame.new(0, 0.7, 0), color = COLORS.Steel, material = M.Metal },
	{ name = "Leg", size = Vector3.new(0.25, 2.8, 0.25), offset = CFrame.new(-5.8, 1.4, -1.35), color = COLORS.Steel, material = M.Metal },
	{ name = "Leg", size = Vector3.new(0.25, 2.8, 0.25), offset = CFrame.new(5.8, 1.4, -1.35), color = COLORS.Steel, material = M.Metal },
	{ name = "Leg", size = Vector3.new(0.25, 2.8, 0.25), offset = CFrame.new(-5.8, 1.4, 1.35), color = COLORS.Steel, material = M.Metal },
	{ name = "Leg", size = Vector3.new(0.25, 2.8, 0.25), offset = CFrame.new(5.8, 1.4, 1.35), color = COLORS.Steel, material = M.Metal },
	-- Ящики на нижней полке
	{ name = "Crate", size = Vector3.new(2.4, 1.1, 1.8), offset = CFrame.new(-3.5, 1.33, 0), color = hex("4B5A3A"), material = M.Wood },
	{ name = "Crate", size = Vector3.new(2.4, 1.1, 1.8), offset = CFrame.new(0, 1.33, 0), color = hex("5A4A2E"), material = M.Wood },
	{ name = "Crate", size = Vector3.new(2.4, 1.1, 1.8), offset = CFrame.new(3.5, 1.33, 0), color = hex("4B5A3A"), material = M.Wood },
}

-- Коробка патронов: ящик своего цвета, крышка, надпись калибра, патроны сверху. Низ по центру.
local AMMO_LOOK = {
	PistolAmmo = { name = "prop_ammo_pistol_01", color = hex("3F6B3A"), label = "9MM", round = hex("D9A441"), tip = hex("B87333"), shell = false },
	RifleAmmo = { name = "prop_ammo_rifle_01", color = hex("6B6B3A"), label = "5.56", round = hex("D9A441"), tip = hex("2B2F3A"), shell = false },
	ShotgunAmmo = { name = "prop_ammo_shotgun_01", color = hex("8A2A22"), label = "12 GA", round = hex("C8343A"), tip = hex("D9A441"), shell = true },
}

local function ammoBoxModel(item: string): PVInstance
	local look = AMMO_LOOK[item]
	local stub: { ModelLibrary.StubPart } = {
		{ name = "Box", size = Vector3.new(1.5, 0.7, 0.95), offset = CFrame.new(0, 0.35, 0), color = look.color, material = M.Metal },
		{ name = "Lid", size = Vector3.new(1.56, 0.12, 1.0), offset = CFrame.new(0, 0.76, 0), color = look.color:Lerp(Color3.new(1, 1, 1), 0.15), material = M.Metal },
		{ name = "Handle", size = Vector3.new(0.6, 0.08, 0.14), offset = CFrame.new(0, 0.86, 0), color = hex("2B2F3A") },
		{ name = "Label", size = Vector3.new(0.9, 0.36, 0.04), offset = CFrame.new(0, 0.38, -0.49), color = hex("F2EEE6") },
	}
	for index = 0, 3 do
		local x = -0.45 + index * 0.3
		if look.shell then
			table.insert(stub, { name = "Shell", size = Vector3.new(0.42, 0.16, 0.16), offset = CFrame.new(x, 1.03, 0.15) * CFrame.Angles(0, 0, math.pi / 2), color = look.round, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "Brass", size = Vector3.new(0.12, 0.17, 0.17), offset = CFrame.new(x, 0.88, 0.15) * CFrame.Angles(0, 0, math.pi / 2), color = look.tip, material = M.Metal, shape = Enum.PartType.Cylinder })
		else
			table.insert(stub, { name = "Case", size = Vector3.new(0.3, 0.1, 0.1), offset = CFrame.new(x, 0.97, 0.15) * CFrame.Angles(0, 0, math.pi / 2), color = look.round, material = M.Metal, shape = Enum.PartType.Cylinder })
			table.insert(stub, { name = "Tip", size = Vector3.new(0.11, 0.11, 0.11), offset = CFrame.new(x, 1.15, 0.15), color = look.tip, material = M.Metal, shape = Enum.PartType.Ball })
		end
	end
	local box = ModelLibrary.build(look.name, stub)
	local label = box:FindFirstChild("Label")
	if label and label:IsA("BasePart") then
		textCard(label, Enum.NormalId.Front, { { text = look.label, color = hex("1E2A44") } })
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
			display("Medkit", spot * CFrame.new(0, 0.95, 0))
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

local MANNEQUIN_STUB: { ModelLibrary.StubPart } = {
	{ name = "Base", size = Vector3.new(0.25, 2.2, 2.2), offset = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), color = hex("2B2F3A"), material = M.Metal, shape = Enum.PartType.Cylinder },
	{ name = "Pole", size = Vector3.new(2.7, 0.25, 0.25), offset = CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Steel, material = M.Metal, shape = Enum.PartType.Cylinder },
	{ name = "Hips", size = Vector3.new(1.9, 0.5, 1), offset = CFrame.new(0, 3.1, 0), color = COLORS.Mannequin },
	{ name = "Torso", size = Vector3.new(2, 1.6, 1), offset = CFrame.new(0, 4.15, 0), color = COLORS.Mannequin },
	{ name = "ShoulderL", size = Vector3.new(0.7, 0.7, 0.9), offset = CFrame.new(-1.05, 4.65, 0), color = COLORS.Mannequin, sphere = true },
	{ name = "ShoulderR", size = Vector3.new(0.7, 0.7, 0.9), offset = CFrame.new(1.05, 4.65, 0), color = COLORS.Mannequin, sphere = true },
	{ name = "Neck", size = Vector3.new(0.4, 0.5, 0.5), offset = CFrame.new(0, 5.15, 0) * CFrame.Angles(0, 0, math.pi / 2), color = COLORS.Mannequin, shape = Enum.PartType.Cylinder },
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
