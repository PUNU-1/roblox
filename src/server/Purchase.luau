--!strict
-- Покупка одним удержанием F (решение 67): постаменты, двери залов, лазерная сетка, сигнализация
-- (потом — камеры и оружейная).
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

-- «Golden Vase — $120» или, если уже вкладывали, «Golden Vase — $40 / $120».
function Purchase.progressText(title: string, paid: number, price: number): string
	if paid > 0 then
		return ("%s — $%d / $%d"):format(title, paid, price)
	end
	return ("%s — $%d"):format(title, price)
end

-- Берёт у игрока деньги за покупку: остаток цены, если хватает, иначе всё, что есть.
-- part — где стоит покупка (проверка расстояния и звук кассы). Возвращает, сколько взяли (0 — ничего).
-- Фазу (день) проверяет сам сервис до вызова.
function Purchase.take(player: Player, part: BasePart, paid: number, price: number): number
	if not RoleService.isParticipant(player) then
		return 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	if (root.Position - part.Position).Magnitude > Config.Purchase.PromptDistance + Config.Catch.ServerDistanceSlack then
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
