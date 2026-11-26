-- Волны воров (блок 3). Решает, КОГДА и КАКИЕ воры приходят; как вор себя ведёт — ThiefService.
--  • Все воры ночи (ThiefService.countForNight) делятся на волны по 2–3 вора. Первая волна через 15–30 сек,
--    дальше паузы, к утру всё короче. Одновременно в музее не больше «игроки + 2»: лишние ждут в очереди.
--  • С 2-й ночи у каждой волны план (Tactics/*): кто, через какие двери, в каком порядке. Ночь 1 и
--    первая волна ночи нового вида — без плана (Tactics/Basic). Каждая 3-я ночь большая: +1 вор на игрока,
--    в средней волне сразу 2–3 плана. О плане игра молчит, только итог ночи: «Thieves used: …».
--  • Воры следят за охраной: двери и цели выбирают подальше от охранников; если вся охрана стоит у Моны Лизы,
--    первый вор волны шумит у витрины в стороне, остальные ждут во входном холле, пока охрана не уйдёт.
--  • Новый вид вора — надпись «NEW THIEF: …» в начале ночи, и он обязательно есть в первой волне.
--  • Налёт (блок 4): с 3-й ночи с шансом 1 из 3 одна из волн — вооружённые грабители (RobberService) вместо воров.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ThiefService = require(Server:WaitForChild("ThiefService"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local RoleService = require(Server:WaitForChild("RoleService"))
local RobberService = require(Server:WaitForChild("RobberService"))
local BlackoutService = require(Server:WaitForChild("BlackoutService"))
local Tactics = Server:WaitForChild("Tactics")
local Basic = require(Tactics:WaitForChild("Basic"))

local Waves = Config.Waves
local Smart = Config.Smart

local WaveService = {}

-- Вор в очереди на вход (или уже вошедший).
export type Handle = {
	options: ThiefService.Options,
	model: Model?, -- модель, когда вор вошёл
	spawned: boolean, -- очередь до него дошла (model может быть nil, если вор не собрался)
	notBefore: number, -- не входить раньше этого времени
}

-- Состояние одной волны (одного плана в волне). Планы хранят своё в data.
export type Ctx = {
	night: number,
	size: number, -- сколько воров у этого плана
	players: number,
	wave: number,
	planName: string,
	data: { [string]: any },
	done: boolean, -- план больше ничего не будет делать
	forceKind: string?, -- новый вид этой ночи: первый вор волны будет им
	lure: boolean, -- охрана столпилась у картины: первый вор шумит, остальные ждут
	lureHandle: Handle?,
}

type Plan = {
	name: string,
	allowLure: boolean?,
	canRun: (Ctx, any) -> boolean,
	start: (Ctx, any) -> (),
	update: ((Ctx, any) -> ())?,
}

type Wave = { at: number, size: number, plans: number } -- plans — сколько планов сразу (большая волна — 2–3)

local random = Random.new()
local active = false
local thread: thread? = nil
local nightStart = 0
local nightNumber = 1
local playerCount = 1
local queue: { Handle } = {}
local running: { Ctx } = {}
local lureReadyAt = 0
local usedPlans: { string } = {} -- названия планов этой ночи для итога («Thieves used: …»)
local lastPlan: string? = nil
local raidWave: number? = nil -- какая волна этой ночи — налёт (блок 4)

local bannerRemote = Remotes.get(Remotes.Names.Banner)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flatDistance(a: Vector3, b: Vector3): number
	local offset = a - b
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

---------------------------------------------------------------- виды воров

local function typeInfo(kind: string): any
	return (Config.ThiefTypes :: any)[kind]
end

-- Светорезу нужен щиток POWER в служебном коридоре, а тот открывается вместе с южным крылом (этап 5, блок B):
-- пока крыло закрыто, Светорез не приходит (и его план Blackout — тоже).
local function available(kind: string): boolean
	if kind == "Cutter" then
		return BlackoutService.standPoint() ~= nil
	end
	return true
end

-- Вид вора уже приходит в эту ночь.
local function unlocked(kind: string): boolean
	local info = typeInfo(kind)
	return info ~= nil and (Waves.TestUnlockAll or nightNumber >= info.FromNight) and available(kind)
end

-- Случайный открытый вид для обычного вора волны (чаще — у кого больше Weight).
-- doorOnly — только те, кто входит через дверь (без подкопа и крыши).
local function pickKind(ctx: Ctx, doorOnly: boolean?): string
	local forced = ctx.forceKind
	if forced then
		ctx.forceKind = nil
		return forced -- новый вид ночи дебютирует, даже если приходит не через дверь
	end
	local total = 0
	local pool = {}
	for _, kind in Config.ThiefOrder do
		local info = typeInfo(kind)
		if info and unlocked(kind) and (not doorOnly or info.Door ~= false) then
			table.insert(pool, kind)
			total += info.Weight
		end
	end
	local roll = random:NextNumber() * total
	for _, kind in pool do
		roll -= typeInfo(kind).Weight
		if roll <= 0 then
			return kind
		end
	end
	return "Pickpocket"
end

---------------------------------------------------------------- охрана и картина

local function guards(): { Vector3 }
	return ThiefService.guardPositions()
end

local function paintingPosition(): Vector3?
	local main = ExhibitService.main()
	return if main then main.home.Position else nil
end

-- Охрана столпилась у Моны Лизы: у картины не меньше CrowdShare всех охранников.
local function crowded(): boolean
	local painting = paintingPosition()
	local list = guards()
	if not painting or #list == 0 then
		return false
	end
	local near = 0
	for _, guard in list do
		if flatDistance(guard, painting) <= Smart.CrowdRadius then
			near += 1
		end
	end
	return near / #list >= Smart.CrowdShare
end

-- Рядом с Моной Лизой никого из охраны.
local function paintingClear(): boolean
	local painting = paintingPosition()
	if not painting then
		return true
	end
	for _, guard in guards() do
		if flatDistance(guard, painting) <= Smart.ClearRadius then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- очередь воров

local function enqueue(options: ThiefService.Options, delay: number?): Handle
	local handle: Handle = { options = options, model = nil, spawned = false, notBefore = now() + (delay or 0) }
	table.insert(queue, handle)
	return handle
end

-- Вор-шумовик своё сделал (или его уже нет, или он так и не вошёл).
local function lureDone(handle: Handle): boolean
	return handle.spawned and (handle.model == nil or ThiefService.taskDone(handle.model))
end

-- Впускаем воров по очереди, пока в музее есть место.
local function processQueue()
	local maxAlive = playerCount + Waves.MaxAliveExtra
	local time = now()
	local index = 1
	while index <= #queue and active do
		local handle = queue[index]
		if time < handle.notBefore then
			index += 1
		elseif ThiefService.aliveCount() >= maxAlive then
			break
		else
			table.remove(queue, index)
			handle.model = ThiefService.spawnSpecial(handle.options)
			handle.spawned = true
		end
	end
end

---------------------------------------------------------------- помощники для планов (api)

local Api = {}

-- Поставить вора в очередь. delay — через сколько секунд он может войти.
-- Если охрана столпилась у картины, первый вор волны идёт шуметь, остальные ждут у входа.
function Api.spawn(ctx: Ctx, options: ThiefService.Options, delay: number?): Handle
	options.plan = options.plan or ctx.planName
	if ctx.lure and options.task == nil and options.hold == nil and options.disguise == nil then
		local kind = options.kind or "Pickpocket"
		local info = typeInfo(kind)
		local nonDoor = info ~= nil and info.Door == false
		local canBeLure = not nonDoor and kind ~= "Breaker" and kind ~= "Cutter"
		local lure = ctx.lureHandle
		if not lure then
			if canBeLure then
				options.task = "Lure"
				local handle = enqueue(options, delay)
				ctx.lureHandle = handle
				return handle
			end
		elseif not nonDoor then
			options.target = options.target or "Main"
			options.hold = function()
				return lureDone(lure) and paintingClear()
			end
			options.holdTimeout = options.holdTimeout or Smart.HoldTimeout
		end
	end
	return enqueue(options, delay)
end

Api.pickKind = pickKind
Api.unlocked = unlocked
Api.guards = guards
Api.crowded = crowded
Api.paintingClear = paintingClear
Api.now = now

-- Небольшой разнобой: воры одной волны входят не в одну секунду.
function Api.stagger(index: number): number
	return if index <= 1 then 0 else random:NextNumber(0.3, Waves.StaggerSeconds) * (index - 1)
end

-- Дверь без охраны (exclude — уже занятые волной).
function Api.entrance(exclude: { BasePart }?): BasePart?
	return ThiefService.pickEntrance(exclude)
end

-- Дверь дальше всех от точки (exclude — какие не брать).
function Api.farthestFrom(position: Vector3, exclude: { BasePart }?): BasePart?
	local best, bestDistance = nil, -1
	for _, entrance in ThiefService.entrances() do
		if not (exclude and table.find(exclude, entrance)) then
			local distance = flatDistance(entrance.Position, position)
			if distance > bestDistance then
				best, bestDistance = entrance, distance
			end
		end
	end
	return best
end

-- Дверь ближе всех к точке.
function Api.nearestTo(position: Vector3, exclude: { BasePart }?): BasePart?
	local best, bestDistance = nil, math.huge
	for _, entrance in ThiefService.entrances() do
		if not (exclude and table.find(exclude, entrance)) then
			local distance = flatDistance(entrance.Position, position)
			if distance < bestDistance then
				best, bestDistance = entrance, distance
			end
		end
	end
	return best
end

-- Открытые двери музея.
function Api.entrances(): { BasePart }
	return ThiefService.entrances()
end

function Api.entranceCount(): number
	return #ThiefService.entrances()
end

-- Есть дешёвый экспонат, который можно схватить (для приманки).
function Api.hasCheapExhibit(): boolean
	return ExhibitService.pickTarget(nil, "Cheap", guards()) ~= nil
end

-- Случайный игрок смены с персонажем (его копией оденется Фальшивый охранник).
function Api.randomGuardPlayer(): Player?
	local list = {}
	for _, player in RoleService.participants() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return if #list > 0 then list[random:NextInteger(1, #list)] else nil
end

-- Вор уже вошёл и его больше нет (пойман, сбежал) — или так и не смог войти.
function Api.gone(handle: Handle): boolean
	return handle.spawned and (handle.model == nil or ThiefService.isGone(handle.model))
end

function Api.taskDone(handle: Handle): boolean
	return handle.spawned and (handle.model == nil or ThiefService.taskDone(handle.model))
end

function Api.carrying(handle: Handle): boolean
	return ThiefService.isCarrying(handle.model)
end

---------------------------------------------------------------- волны

-- Все воры ночи по волнам: в среднем AverageGroup в волне, не меньше 2 волн, порядок размеров случайный.
local function splitIntoWaves(total: number): { number }
	if total <= 0 then
		return {}
	end
	local count = math.ceil(total / Waves.AverageGroup)
	if total >= 3 then
		count = math.max(count, 2)
	end
	local sizes = {}
	local base = math.floor(total / count)
	local extra = total - base * count
	for index = 1, count do
		table.insert(sizes, base + (if index <= extra then 1 else 0))
	end
	for index = #sizes, 2, -1 do
		local other = random:NextInteger(1, index)
		sizes[index], sizes[other] = sizes[other], sizes[index]
	end
	return sizes
end

-- Когда начинается каждая волна (секунды от начала ночи).
local function schedule(sizes: { number }, nightLength: number): { Wave }
	-- (plans у всех волн — 1; большую волну делает bigWave)
	local waves: { Wave } = {}
	local first = random:NextNumber(Waves.FirstSpawnMin, Waves.FirstSpawnMax)
	local last = math.max(first, nightLength - Waves.LastSpawnBeforeEnd)
	local count = #sizes
	local gap = if count > 1 then math.min(Waves.GapMax, (last - first) / (count - 1)) else 0
	local at = first
	for index, size in sizes do
		if index > 1 then
			local fraction = if count > 2 then (index - 2) / (count - 2) else 0
			local scale = Waves.GapStartScale + (Waves.GapEndScale - Waves.GapStartScale) * fraction
			local jitter = 1 + Waves.GapJitter * (random:NextNumber() * 2 - 1)
			at = math.min(last, at + gap * scale * jitter)
		end
		table.insert(waves, { at = at, size = size, plans = 1 })
	end
	return waves
end

local function newCtx(wave: number, size: number, plan: Plan): Ctx
	return {
		night = nightNumber,
		size = size,
		players = playerCount,
		wave = wave,
		planName = plan.name,
		data = {},
		done = false,
		forceKind = nil,
		lure = false,
		lureHandle = nil,
	}
end

local function startPlan(plan: Plan, ctx: Ctx)
	if plan.allowLure ~= false and now() >= lureReadyAt and crowded() then
		ctx.lure = true
		lureReadyAt = now() + Smart.LureCooldown
	end
	plan.start(ctx, Api)
	if not ctx.done then
		table.insert(running, ctx)
	end
end

local plansByName: { [string]: Plan } = { Basic = Basic :: any }
for _, name in Config.PlanOrder do
	plansByName[name] = require(Tactics:WaitForChild(name)) :: any
end

-- План уже может прийти этой ночью: не раньше своей ночи и только с открытым видом вора.
local function planAllowed(name: string): boolean
	local info = (Config.Plans :: any)[name]
	if not info then
		return false
	end
	if Waves.TestUnlockAll then
		return true
	end
	if info.FromNight and nightNumber < info.FromNight then
		return false
	end
	return info.Needs == nil or unlocked(info.Needs)
end

-- count разных планов для волны (случайно, по возможности не тот же, что у прошлой волны).
local function choosePlans(count: number, size: number, wave: number): { Plan }
	local candidates: { Plan } = {}
	for _, name in Config.PlanOrder do
		local plan = plansByName[name]
		if plan and planAllowed(name) and plan.canRun(newCtx(wave, size, plan), Api) then
			table.insert(candidates, plan)
		end
	end
	if #candidates > count and lastPlan then
		for index, plan in candidates do
			if plan.name == lastPlan then
				table.remove(candidates, index)
				break
			end
		end
	end
	local chosen: { Plan } = {}
	while #chosen < count and #candidates > 0 do
		local picked = table.remove(candidates, random:NextInteger(1, #candidates))
		if picked then
			table.insert(chosen, picked)
		end
	end
	return chosen
end

local function rememberPlan(plan: Plan)
	lastPlan = plan.name
	local info = (Config.Plans :: any)[plan.name]
	if info and not table.find(usedPlans, info.Title) then
		table.insert(usedPlans, info.Title)
	end
end

-- Волна: ночь 1 и дебют нового вида — без плана; иначе 1 план (большая волна — 2–3 плана, воры делятся).
local function startWave(index: number, wave: Wave, forceKind: string?)
	if index == raidWave then
		-- Налёт вместо воров этой волны: игроки × 3 вооружённых грабителя через одну дверь
		RobberService.startRaid(playerCount)
		if not table.find(usedPlans, Config.Raid.Title) then
			table.insert(usedPlans, Config.Raid.Title)
		end
		return
	end
	local plans: { Plan } = {}
	if not forceKind and (Waves.TestUnlockAll or nightNumber >= Waves.PlansFromNight) then
		plans = choosePlans(wave.plans, wave.size, index)
	end
	if #plans == 0 then
		local ctx = newCtx(index, wave.size, Basic :: any)
		ctx.forceKind = forceKind
		startPlan(Basic :: any, ctx)
		return
	end
	local left = wave.size
	for number, plan in plans do
		local share = if number == #plans then left else math.max(2, math.floor(wave.size / #plans))
		share = math.min(share, left)
		left -= share
		if share > 0 then
			rememberPlan(plan)
			startPlan(plan, newCtx(index, share, plan))
		end
	end
end

-- Большая ночь: волны в середине ночи сливаются в одну, где сразу несколько планов.
local function bigWave(waves: { Wave }): { Wave }
	local count = if playerCount >= Waves.ManyPlayers then Waves.BigWavePlansManyPlayers else Waves.BigWavePlans
	count = math.min(count, #waves)
	if count < 2 then
		return waves
	end
	local first = math.clamp(math.ceil(#waves / 2) - math.floor((count - 1) / 2), 1, #waves - count + 1)
	local merged: Wave = { at = waves[first].at, size = 0, plans = count }
	local result: { Wave } = {}
	for index, wave in waves do
		if index >= first and index < first + count then
			merged.size += wave.size
			if index == first then
				table.insert(result, merged)
			end
		else
			table.insert(result, wave)
		end
	end
	return result
end

local function updatePlans()
	for index = #running, 1, -1 do
		local ctx = running[index]
		local plan = plansByName[ctx.planName]
		if plan and plan.update and not ctx.done then
			plan.update(ctx, Api)
		end
		if ctx.done or not plan then
			table.remove(running, index)
		end
	end
end

-- Новые виды воров этой ночи (надпись NEW THIEF).
local function newKinds(night: number): { string }
	local list = {}
	if Waves.TestUnlockAll then
		return list
	end
	for _, kind in Config.ThiefOrder do
		local info = typeInfo(kind)
		if info and info.FromNight == night and info.FromNight > 1 and available(kind) then
			table.insert(list, kind)
		end
	end
	return list
end

local function announce(kinds: { string })
	for index, kind in kinds do
		task.delay(Waves.NewThiefBannerDelay + (index - 1) * (Config.Effects.BannerSeconds + 0.3), function()
			if active then
				bannerRemote:FireAllClients(("NEW THIEF: %s"):format(typeInfo(kind).Title), "danger")
			end
		end)
	end
end

local function loop(waves: { Wave }, fresh: { string })
	local nextWave = 1
	while active do
		local elapsed = now() - nightStart
		while nextWave <= #waves and elapsed >= waves[nextWave].at do
			startWave(nextWave, waves[nextWave], if nextWave == 1 then fresh[1] else nil)
			nextWave += 1
		end
		updatePlans()
		processQueue()
		task.wait(Waves.UpdateSeconds)
	end
end

-- Начало ночи: сколько воров, волны, кто новый. Вызывать после ThiefService.beginNight.
function WaveService.beginNight(players: number, night: number, nightLength: number)
	WaveService.endNight()
	active = true
	nightStart = now()
	nightNumber = math.max(1, night)
	playerCount = math.max(1, players)
	lureReadyAt = 0
	lastPlan = nil
	table.clear(usedPlans)
	local total = ThiefService.countForNight(playerCount, nightNumber)
	local big = nightNumber % Waves.BigNightEvery == 0 and (Waves.TestUnlockAll or nightNumber >= Waves.PlansFromNight)
	if big then
		total += playerCount * Waves.BigNightExtraPerPlayer -- большая ночь: больше воров
	end
	local waves = schedule(splitIntoWaves(total), nightLength)
	if big then
		waves = bigWave(waves)
	end
	-- Налёт: с Raid.FromNight с шансом Raid.Chance одна из волн (не первая, если можно, и не под самое утро)
	raidWave = nil
	local raid = Config.Raid
	local raidNight = Waves.TestUnlockAll or nightNumber >= raid.FromNight
	if #waves > 0 and (raid.TestForce or (raidNight and random:NextNumber() < raid.Chance)) then
		local last = math.max(1, math.ceil(#waves * 0.6))
		local first = if #waves >= 2 and not raid.TestForce then 2 else 1
		raidWave = random:NextInteger(first, math.max(first, last))
	end
	local fresh = newKinds(nightNumber)
	if raidWave == 1 and #fresh > 0 then
		raidWave = if #waves >= 2 then 2 else nil -- первая волна — дебют нового вора
	end
	announce(fresh)
	thread = task.spawn(loop, waves, fresh)
end

-- Какие планы были у воров этой ночью (для строки «Thieves used: …» в итоге ночи).
function WaveService.usedPlans(): { string }
	return table.clone(usedPlans)
end

function WaveService.endNight()
	active = false
	if thread then
		pcall(task.cancel, thread)
		thread = nil
	end
	table.clear(queue)
	table.clear(running)
end

return WaveService
