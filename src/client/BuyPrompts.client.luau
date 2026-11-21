--!strict
-- Текст на кнопках покупки (решение 67): каждый видит, что будет, если удержать F, по своим деньгам —
-- «Buy $300» (хватает на остаток цены) или «Put in $120» (все деньги идут в полоску складчины).
-- Сервер ставит на кнопку цену и сколько уже вложено (Purchase.luau) и сам решает, сколько взять;
-- клиент только меняет надпись у себя.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameState"))

local BuyPrompt = GameState.BuyPrompt
local localPlayer = Players.LocalPlayer

local tracked: { [ProximityPrompt]: RBXScriptConnection } = {}

local function refresh(prompt: ProximityPrompt)
	local price = tonumber(prompt:GetAttribute(BuyPrompt.Price)) or 0
	local paid = tonumber(prompt:GetAttribute(BuyPrompt.Paid)) or 0
	local money = tonumber(localPlayer:GetAttribute(GameState.PlayerAttr.Money)) or 0
	prompt.ActionText = GameState.buyActionText(price - paid, money)
end

local function track(instance: Instance)
	if not instance:IsA("ProximityPrompt") or tracked[instance] then
		return
	end
	refresh(instance)
	tracked[instance] = instance.AttributeChanged:Connect(function()
		refresh(instance)
	end)
end

local function untrack(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local connection = tracked[instance]
	if connection then
		connection:Disconnect()
		tracked[instance] = nil
	end
end

CollectionService:GetInstanceAddedSignal(BuyPrompt.Tag):Connect(track)
CollectionService:GetInstanceRemovedSignal(BuyPrompt.Tag):Connect(untrack)
for _, instance in CollectionService:GetTagged(BuyPrompt.Tag) do
	track(instance)
end

localPlayer:GetAttributeChangedSignal(GameState.PlayerAttr.Money):Connect(function()
	for prompt in tracked do
		refresh(prompt)
	end
end)
