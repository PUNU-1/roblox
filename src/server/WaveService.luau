-- Волны воров (блок 3). Решает, КОГДА и КАКИЕ воры приходят; как вор себя ведёт — ThiefService.
--  • Все воры ночи (ThiefService.countForNight) делятся на волны по 2–3 вора. Первая волна через 15–30 сек,
--    дальше паузы, к утру всё короче. Одновременно в музее не больше «игроки + 2»: лишние ждут в очереди.
--  • У каждой волны план (Tactics/*): кто, через какие двери, в каком порядке. Без плана — Tactics/Basic.
--  • Воры следят за охраной: двери и цели выбирают подальше от охранников; если вся охрана стоит у Моны Лизы,
--    первый вор волны шумит у витрины в стороне, остальные ждут во входном холле, пока охрана не уйдёт.
--  • Новый вид вора — надпись «NEW THIEF: …» в начале ночи, и он обязательно есть в первой волне.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ThiefService = require(Server:WaitForChild("ThiefService"))
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
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

type Wave = { at: number, size: number }

local random = Random.new()
local active = false
local thread: thread? = nil
local nightStart = 0
local nightNumber = 1
local playerCount = 1
local queue: { Handle } = {}
local running: { Ctx } = {}
local lureReadyAt = 0

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

-- Вид вора уже приходит в эту ночь.
local function unlocked(kind: string): boolean
	local info = typeInfo(kind)
	return info ~= nil and (Waves.TestUnlockAll or nightNumber >= info.FromNight)
end

-- Случайный открытый вид для обычного вора волны (чаще — у кого больше Weight).
-- doorOnly — только те, кто входит через дверь (без подкопа и крыши).
local function pickKind(ctx: Ctx, doorOnly: boolean?): string
	local forced = ctx.forceKind
	if forced and (not doorOnly or typeInfo(forced).Door ~= false) then
		ctx.forceKind = nil
		return forced
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
	if ctx.lure and options.task == nil and options.hold == nil then
		local lure = ctx.lureHandle
		if not lure then
			options.task = "Lure"
			local handle = enqueue(options, delay)
			ctx.lureHandle = handle
			return handle
		end
		options.target = options.target or "Main"
		options.hold = function()
			return lureDone(lure) and paintingClear()
		end
		options.holdTimeout = options.holdTimeout or Smart.HoldTimeout
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
		table.insert(waves, { at = at, size = size })
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

local function startWave(index: number, wave: Wave, forceKind: string?)
	local ctx = newCtx(index, wave.size, Basic :: any)
	ctx.forceKind = forceKind
	startPlan(Basic :: any, ctx)
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
		if info and info.FromNight == night and info.FromNight > 1 then
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
	local total = ThiefService.countForNight(playerCount, nightNumber)
	local waves = schedule(splitIntoWaves(total), nightLength)
	local fresh = newKinds(nightNumber)
	announce(fresh)
	thread = task.spawn(loop, waves, fresh)
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
