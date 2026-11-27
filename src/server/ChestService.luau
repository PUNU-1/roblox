-- Сундук после ночи (этап 6, блок H2, решение 86): каждому, кто пережил ночь на смене, на экране итога —
-- бесплатный сундук. Нажал — внутри случайно Chest.Low…High алмазов (чем дальше ночь, тем больше), с шансом
-- GoldChance — золотой сундук, награда × GoldMultiplier. ТОЛЬКО БЕСПЛАТНО, никогда за Robux: игроки — дети,
-- платные случайные награды — это азартные игры.
-- Случай считает сервер в момент выдачи (клиент только просит открыть). Не открыл до конца итога — алмазы
-- всё равно начисляются (сундук нельзя «потерять»). Алмазы — ProfileStore.addDiamonds (UpdateAsync в pcall).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local Settings = Config.Chest

local ChestService = {}

type Chest = { amount: number, gold: boolean }

local pending: { [Player]: Chest } = {}
local random = Random.new()
local resultRemote: RemoteEvent
local started = false

-- Сколько алмазов в сундуке после ночи night и золотой ли он. Только сервер.
local function roll(night: number): Chest
	local n = math.max(1, math.floor(night))
	local high = math.min(Settings.Max, Settings.HighStart + Settings.HighPerNight * (n - 1))
	local low = math.min(high, math.max(Settings.Min, Settings.LowStart + Settings.LowPerNight * (n - 1)))
	local amount = random:NextInteger(low, high)
	local gold = random:NextNumber() < Settings.GoldChance
	if gold then
		amount *= Settings.GoldMultiplier
	end
	return { amount = amount, gold = gold }
end

-- Отдать сундук: алмазы в профиль. shown — игрок нажал (ему ответ для анимации).
local function give(player: Player, shown: boolean)
	local chest = pending[player]
	if not chest then
		return
	end
	pending[player] = nil
	ProfileStore.addDiamonds(player, chest.amount)
	if shown and player.Parent then
		resultRemote:FireClient(player, chest.amount, chest.gold)
	end
end

function ChestService.init()
	if started then
		return
	end
	started = true
	resultRemote = Remotes.get(Remotes.Names.ChestResult)
	-- Аргументов нет: открыть можно только свой сундук, и только если он есть
	Remotes.get(Remotes.Names.OpenChest).OnServerEvent:Connect(function(player: Player)
		give(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		give(player, false) -- вышел, не открыв, — алмазы всё равно его (если профиль ещё в памяти)
		pending[player] = nil
	end)
end

-- Ночь пережита: сундук каждому, кто на смене. Возвращает userId (строкой) -> true — у кого есть сундук
-- (для экрана итога).
function ChestService.grantAll(players: { Player }, night: number): { [string]: boolean }
	local granted: { [string]: boolean } = {}
	for _, player in players do
		if player.Parent and player:GetAttribute(GameState.PlayerAttr.InRound) == true then
			give(player, false) -- прошлый не открыт (не должно быть) — сначала отдаём его
			pending[player] = roll(night)
			granted[tostring(player.UserId)] = true
		end
	end
	return granted
end

-- Итог кончился: неоткрытые сундуки открываются сами (алмазы начисляются без анимации).
function ChestService.flush()
	for player in pending do
		give(player, false)
	end
end

return ChestService
