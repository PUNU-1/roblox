-- Счёт ночи: кто сколько поймал, деньги, лучший охранник, данные для экрана итога.
-- Деньги (решение 68): билеты туристов делятся поровну, арест — $5 сразу тому, кто арестовал,
-- за пережитую ночь денег нет. Деньги живут только в атрибуте Player.Money и обнуляются в начале забега.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))

local ScoreService = {}

local catchesByUser: { [number]: number } = {}
local arrestMoneyByUser: { [number]: number } = {} -- сколько каждый заработал арестами за ночь
local participantIds: { number } = {}
local caughtTotal = 0
local spawnedTotal = 0
local incomePool = 0 -- остаток дохода, который ещё не поделился поровну
local dayTickets = 0

export type Results = {
	survived: boolean,
	caught: number,
	total: number,
	earnings: { [string]: number }, -- userId (строкой) -> доллары за аресты этой ночью
	catches: { [string]: number }, -- userId (строкой) -> поймано
	wallets: { [string]: number }, -- userId (строкой) -> сколько денег у игрока сейчас
	bestUserId: number, -- 0 — никто никого не поймал
	night: number?, -- какая это была ночь
	gameOver: boolean?, -- Мону Лизу вынесли, забег окончен
	nightsSurvived: number?, -- сколько ночей продержались за этот забег
	best: number?, -- рекорд сервера
	tickets: number?, -- сколько заплатили туристы за день перед этой ночью
	plans: { string }?, -- какие планы были у воров этой ночью (блок 3)
}

-- Новый забег: всё с нуля, деньги тоже.
function ScoreService.beginRun(participants: { Player })
	for _, player in participants do
		player:SetAttribute(GameState.PlayerAttr.Money, 0)
	end
	incomePool = 0
end

function ScoreService.beginDay()
	dayTickets = 0
end

-- Доход (например, билет туриста) делится поровну между игроками забега.
-- Остаток, который не делится нацело, копится до следующего раза.
function ScoreService.addIncome(amount: number)
	dayTickets += amount
	incomePool += amount
	local players = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(GameState.PlayerAttr.InRound) == true then
			table.insert(players, player)
		end
	end
	if #players == 0 then
		return
	end
	local share = math.floor(incomePool / #players)
	if share <= 0 then
		return
	end
	incomePool -= share * #players
	for _, player in players do
		player:SetAttribute(GameState.PlayerAttr.Money, (player:GetAttribute(GameState.PlayerAttr.Money) or 0) + share)
	end
end

function ScoreService.beginNight(participants: { Player })
	table.clear(catchesByUser)
	table.clear(arrestMoneyByUser)
	table.clear(participantIds)
	caughtTotal = 0
	spawnedTotal = 0
	for _, player in participants do
		table.insert(participantIds, player.UserId)
		catchesByUser[player.UserId] = 0
		arrestMoneyByUser[player.UserId] = 0
	end
	GameState.set(GameState.Attr.Caught, 0)
	GameState.set(GameState.Attr.ThievesSpawned, 0)
end

function ScoreService.addSpawned()
	spawnedTotal += 1
	GameState.set(GameState.Attr.ThievesSpawned, spawnedTotal)
end

-- Арест: деньги сразу и только тому, кто арестовал (решение 68).
function ScoreService.addCatch(player: Player)
	caughtTotal += 1
	catchesByUser[player.UserId] = (catchesByUser[player.UserId] or 0) + 1
	local reward = Config.Money.PerArrest
	arrestMoneyByUser[player.UserId] = (arrestMoneyByUser[player.UserId] or 0) + reward
	player:SetAttribute(GameState.PlayerAttr.Money, (tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0) + reward)
	GameState.set(GameState.Attr.Caught, caughtTotal)
end

-- Итог ночи: кто сколько поймал и заработал арестами, сколько денег у каждого. Денег за ночь нет.
function ScoreService.finish(survived: boolean): Results
	local earnings: { [string]: number } = {}
	local catches: { [string]: number } = {}
	local wallets: { [string]: number } = {}
	local bestUserId, bestCount = 0, 0
	for _, userId in participantIds do
		local key = tostring(userId)
		earnings[key] = arrestMoneyByUser[userId] or 0
		local caught = catchesByUser[userId] or 0
		catches[key] = caught
		if caught > bestCount then
			bestUserId, bestCount = userId, caught
		end
		local player = Players:GetPlayerByUserId(userId)
		wallets[key] = if player then tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0 else 0
	end

	return {
		survived = survived,
		caught = caughtTotal,
		total = spawnedTotal,
		earnings = earnings,
		catches = catches,
		wallets = wallets,
		bestUserId = bestUserId,
		tickets = dayTickets,
	}
end

return ScoreService
