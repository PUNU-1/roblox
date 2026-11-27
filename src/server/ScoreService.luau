-- Счёт ночи: кто сколько поймал, деньги, лучший охранник, данные для экрана итога.
-- Деньги (решение 68): билеты туристов делятся поровну, арест — $5 сразу тому, кто арестовал,
-- за пережитую ночь денег нет. Деньги живут только в атрибуте Player.Money и обнуляются в начале забега.
-- Алмазы 💎 (этап 4, блок 1): в итоге каждой ночи +10 за пережитую ночь (тем, кто на смене) и +1 за каждый свой
-- арест (Config.Diamonds). Они не обнуляются — ProfileStore сразу сохраняет их навсегда.
-- Этап 6, блок H2: в команде есть друг по Roblox — алмазы за ночь +25 % (FriendService, дружба проверяется заранее).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))
local FriendService = require(script.Parent:WaitForChild("FriendService"))

local ScoreService = {}

local catchesByUser: { [number]: number } = {}
local arrestMoneyByUser: { [number]: number } = {} -- сколько каждый заработал арестами за ночь
local participantIds: { number } = {}
local caughtTotal = 0
local spawnedTotal = 0
local incomePool = 0 -- остаток дохода, который ещё не поделился поровну
local dayTickets = 0
local diamondsRun: { [number]: number } = {} -- сколько алмазов каждый получил за этот забег

export type Results = {
	survived: boolean,
	caught: number,
	total: number,
	earnings: { [string]: number }, -- userId (строкой) -> доллары за аресты этой ночью
	catches: { [string]: number }, -- userId (строкой) -> поймано
	wallets: { [string]: number }, -- userId (строкой) -> сколько денег у игрока сейчас
	bestUserId: number, -- 0 — никто никого не поймал
	bestCatches: number?, -- сколько арестов у лучшего охранника за ночь (этап 6, блок I3)
	bestName: string?, -- DisplayName лучшего охранника (если выйдет до показа итога)
	night: number?, -- какая это была ночь
	gameOver: boolean?, -- Мону Лизу вынесли, забег окончен
	nightsSurvived: number?, -- сколько ночей продержались за этот забег
	best: number?, -- рекорд сервера
	tickets: number?, -- сколько заплатили туристы за день перед этой ночью
	plans: { string }?, -- какие планы были у воров этой ночью (блок 3)
	diamonds: { [string]: number }, -- userId (строкой) -> алмазы за эту ночь (этап 4, блок 1)
	diamondsRun: { [string]: number }, -- userId (строкой) -> алмазы за весь забег
	diamondsSaved: boolean, -- false — Studio без доступа к API: алмазы не сохраняются
	friendsBonus: { [string]: number }, -- userId (строкой) -> сколько алмазов из них — бонус за друга (этап 6, блок H2)
	chests: { [string]: boolean }?, -- userId (строкой) -> true: у игрока сундук после ночи (этап 6, блок H2, ChestService)
	personalBest: { [string]: number }?, -- GAME OVER: userId (строкой) -> личный рекорд до этого забега (этап 6, блок H2)
}

-- Новый забег: всё с нуля, деньги тоже.
function ScoreService.beginRun(participants: { Player })
	for _, player in participants do
		player:SetAttribute(GameState.PlayerAttr.Money, 0)
		-- Обучение (этап 5, блок C): траты и аресты считаются заново каждый забег
		player:SetAttribute(GameState.PlayerAttr.RunSpent, 0)
		player:SetAttribute(GameState.PlayerAttr.RunArrests, 0)
		player:SetAttribute(GameState.PlayerAttr.NightArrests, 0)
		player:SetAttribute(GameState.PlayerAttr.RunRevives, 0)
	end
	incomePool = 0
	table.clear(diamondsRun)
	ProgressService.runStarted(participants) -- забеги для достижения Night Owl (этап 6, блок H1)
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
		player:SetAttribute(GameState.PlayerAttr.NightArrests, 0)
	end
	FriendService.warm(participants) -- бонус за друга (этап 6, блок H2): к итогу ночи ответ Roblox уже придёт
	GameState.set(GameState.Attr.Caught, 0)
	GameState.set(GameState.Attr.ThievesSpawned, 0)
end

function ScoreService.addSpawned()
	spawnedTotal += 1
	GameState.set(GameState.Attr.ThievesSpawned, spawnedTotal)
end

-- Арест: деньги сразу и только тому, кто арестовал (решение 68). kind — вид вора (опыт, задание, достижение).
function ScoreService.addCatch(player: Player, kind: any)
	caughtTotal += 1
	catchesByUser[player.UserId] = (catchesByUser[player.UserId] or 0) + 1
	local reward = Config.Money.PerArrest
	arrestMoneyByUser[player.UserId] = (arrestMoneyByUser[player.UserId] or 0) + reward
	player:SetAttribute(GameState.PlayerAttr.Money, (tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0) + reward)
	player:SetAttribute(GameState.PlayerAttr.RunArrests, (tonumber(player:GetAttribute(GameState.PlayerAttr.RunArrests)) or 0) + 1)
	player:SetAttribute(GameState.PlayerAttr.NightArrests, (tonumber(player:GetAttribute(GameState.PlayerAttr.NightArrests)) or 0) + 1)
	GameState.set(GameState.Attr.Caught, caughtTotal)
	ProgressService.arrest(player, kind) -- опыт, задание «арестуй», достижения (этап 6, блок H1)
end

-- Грабителя остановили без ареста (убит или его забрала полиция, блок 4): считается пойманным, денег нет.
function ScoreService.addStopped()
	caughtTotal += 1
	GameState.set(GameState.Attr.Caught, caughtTotal)
end

-- Итог ночи: кто сколько поймал и заработал арестами, сколько денег у каждого. Денег за ночь нет.
-- Алмазы: пережили ночь — PerNight каждому, кто ещё на смене; плюс PerArrest за каждый свой арест.
-- Опыт и задания за ночь (этап 6, блок H1) — тоже только тем, кто на смене. raided — этой ночью был налёт.
function ScoreService.finish(survived: boolean, raided: boolean?): Results
	local earnings: { [string]: number } = {}
	local catches: { [string]: number } = {}
	local wallets: { [string]: number } = {}
	local diamonds: { [string]: number } = {}
	local runDiamonds: { [string]: number } = {}
	local friendsBonus: { [string]: number } = {}
	local bestUserId, bestCount, bestRevives = 0, 0, -1
	local bestName: string? = nil
	-- Кто сейчас на смене (бонус за друга — только если друг тоже на смене)
	local team: { Player } = {}
	for _, userId in participantIds do
		local player = Players:GetPlayerByUserId(userId)
		if player and player:GetAttribute(GameState.PlayerAttr.InRound) == true then
			table.insert(team, player)
		end
	end
	for _, userId in participantIds do
		local key = tostring(userId)
		earnings[key] = arrestMoneyByUser[userId] or 0
		local caught = catchesByUser[userId] or 0
		catches[key] = caught
		local player = Players:GetPlayerByUserId(userId)
		local revives = if player then tonumber(player:GetAttribute(GameState.PlayerAttr.RunRevives)) or 0 else 0
		-- Лучший охранник: больше арестов за ночь, при равенстве — больше поднятий товарищей (этап 6, блок I3)
		if caught > 0 and (caught > bestCount or (caught == bestCount and revives > bestRevives)) then
			bestUserId, bestCount, bestRevives = userId, caught, revives
			bestName = if player then player.DisplayName else nil
		end
		wallets[key] = if player then tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0 else 0
		-- Алмазы — только тем, кто ещё на сервере и на смене
		local award = 0
		if player and player:GetAttribute(GameState.PlayerAttr.InRound) == true then
			award = caught * Config.Diamonds.PerArrest + (if survived then Config.Diamonds.PerNight else 0)
			if award > 0 and FriendService.hasFriendIn(player, team) then
				local bonus = math.ceil(award * Config.Diamonds.FriendsBonus)
				award += bonus
				friendsBonus[key] = bonus
			end
			if award > 0 then
				ProfileStore.addDiamonds(player, award)
			end
			ProgressService.nightEnded(player, survived, raided == true)
		end
		diamondsRun[userId] = (diamondsRun[userId] or 0) + award
		diamonds[key] = award
		runDiamonds[key] = diamondsRun[userId]
	end

	return {
		survived = survived,
		caught = caughtTotal,
		total = spawnedTotal,
		earnings = earnings,
		catches = catches,
		wallets = wallets,
		bestUserId = bestUserId,
		bestCatches = bestCount,
		bestName = bestName,
		tickets = dayTickets,
		diamonds = diamonds,
		diamondsRun = runDiamonds,
		diamondsSaved = not ProfileStore.isOffline(),
		friendsBonus = friendsBonus,
	}
end

return ScoreService
