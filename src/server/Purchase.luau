--!strict
-- Покупка одним удержанием F (решение 67): постаменты, двери залов, лазерная сетка, сигнализация, камеры,
-- оружейная. Те же правила — у окна магазина (этап 4, блок 1b, ShopService), только без проверки расстояния.
--  • Хватает денег на остаток цены — платишь остаток и покупаешь сразу сам.
--  • Не хватает — все твои деньги идут в полоску, остальное докладывают другие (складчина).
-- Сколько взять, считает сервер: клиент только держит кнопку.
-- Текст на кнопке («Buy $300» / «Put in $120») каждому игроку пишет его клиент (BuyPrompts.client)
-- по атрибутам кнопки (цена, сколько уже вложено) и своим деньгам: у всех он разный.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local BuyPrompt = GameState.BuyPrompt

local Purchase = {}

-- Сколько уже вложено и сколько стоит: клиент по ним пишет текст на кнопке.
function Purchase.setProgress(prompt: ProximityPrompt, paid: number, price: number)
	prompt:SetAttribute(BuyPrompt.Price, price)
	prompt:SetAttribute(BuyPrompt.Paid, paid)
end

-- Кнопка покупки на детали part. Включает её сам сервис (днём, когда покупать можно).
function Purchase.newPrompt(part: BasePart, name: string, price: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	-- Запасной текст. Сервер его больше не меняет, иначе он затрёт текст, который пишет клиент.
	prompt.ActionText = ("Buy $%d"):format(price)
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.HoldDuration = Config.Purchase.HoldSeconds
	prompt.MaxActivationDistance = Config.Purchase.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	Purchase.setProgress(prompt, 0, price)
	prompt:AddTag(BuyPrompt.Tag)
	prompt.Parent = part
	return prompt
end

-- Блок 4: личная покупка в оружейной (без складчины). Кнопка одна на всех, но видна ли она игроку
-- и что на ней написано («Buy $150», «Swap $300», «Need $150»), решает его клиент по своим вещам
-- (GameState.armoryOffer). item — товар из Config.Armory.Goods.
function Purchase.newPersonalPrompt(part: BasePart, name: string, price: number, item: string): ProximityPrompt
	local prompt = Purchase.newPrompt(part, name, price)
	prompt.MaxActivationDistance = Config.Armory.PromptDistance
	prompt:SetAttribute(BuyPrompt.Item, item)
	prompt:SetAttribute(BuyPrompt.Open, false)
	return prompt
end

-- Можно ли сейчас покупать (днём). Для личных кнопок клиент ещё прячет ту, что ему не нужна.
function Purchase.setOpen(prompt: ProximityPrompt, open: boolean)
	prompt:SetAttribute(BuyPrompt.Open, open)
	prompt.Enabled = open
end

-- Игрок может сейчас платить: на смене, не лежит, есть персонаж. maxDistance — проверка расстояния до part
-- (кнопка F); nil — без проверки (окно магазина, этап 4, блок 1b).
local function canPay(player: Player, part: BasePart, maxDistance: number?): boolean
	if not RoleService.isParticipant(player) or RoleService.isDowned(player) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	if maxDistance and (root.Position - part.Position).Magnitude > maxDistance then
		return false
	end
	return true
end

-- Берёт у игрока полную цену личной покупки. false — денег не хватает, далеко или игрок не на смене.
-- fromShop — покупка из окна магазина: без проверки расстояния.
function Purchase.takeFull(player: Player, part: BasePart, price: number, fromShop: boolean?): boolean
	local maxDistance = if fromShop then nil else Config.Armory.PromptDistance + Config.Catch.ServerDistanceSlack
	if not canPay(player, part, maxDistance) then
		return false
	end
	local money = math.floor(tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0)
	if money < price then
		return false
	end
	player:SetAttribute(GameState.PlayerAttr.Money, money - price)
	Audio.purchase(part)
	return true
end

-- «Golden Vase — $120» или, если уже вкладывали, «Golden Vase — $40 / $120».
function Purchase.progressText(title: string, paid: number, price: number): string
	if paid > 0 then
		return ("%s — $%d / $%d"):format(title, paid, price)
	end
	return ("%s — $%d"):format(title, price)
end

-- Берёт у игрока деньги за покупку: остаток цены, если хватает, иначе всё, что есть.
-- part — где стоит покупка (проверка расстояния и звук кассы). Возвращает, сколько взяли (0 — ничего).
-- Фазу (день) проверяет сам сервис до вызова. fromShop — покупка из окна магазина: без проверки расстояния.
function Purchase.take(player: Player, part: BasePart, paid: number, price: number, fromShop: boolean?): number
	local maxDistance = if fromShop then nil else Config.Purchase.PromptDistance + Config.Catch.ServerDistanceSlack
	if not canPay(player, part, maxDistance) then
		return 0
	end
	local money = math.floor(tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0)
	local amount = math.min(money, price - paid)
	if amount <= 0 then
		return 0
	end
	player:SetAttribute(GameState.PlayerAttr.Money, money - amount)
	Audio.purchase(part)
	return amount
end

return Purchase
