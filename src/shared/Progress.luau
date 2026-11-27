--!strict
-- Прогресс игрока (этап 6, блок H1, решение 85): опыт, уровни и звания, ежедневные задания, достижения, пробный
-- забег новичка. Только данные и правила — без DataStore: сохраняет server/ProfileStore (внутри UpdateAsync, тем же
-- Progress.apply), начисляет server/ProgressService, показывают клиенты (по атрибутам игрока).
--
-- Данные в профиле (PlayerProfile_v1), все поля необязательные — старые профили без них читаются:
--   xp = 1234, levelPaid = 7 (до какого уровня уже выданы алмазы),
--   questDay = 20419, quests = { { k = "Arrest", g = 6, r = 25, p = 2, d = false, c = "Operator"? }, ... },
--   stats = { nights = 12, arrests = 40, revives = 3, runs = 5, raids = 1, wingsRun = 2 },
--   kinds = { Pickpocket = true, ... }, badges = { FirstArrest = true, ... }, freeTries = 1,
--   exhibits = { Diamond = true, MonaLisa = true, ... }, colPaid = { thieves = true, exhibits = true } (этап 6, блок H2:
--   коллекция — kinds теперь и с FakeGuard; colPaid — за какую полную коллекцию алмазы уже выданы)

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent:WaitForChild("Config"))

local Settings = Config.Progress

local Progress = {}

export type Quest = {
	k: string, -- вид задания (Config.Quests.List[].Kind)
	g: number, -- цель
	r: number, -- награда в алмазах
	c: string?, -- класс (задание PlayClass)
	p: number, -- сколько сделано
	d: boolean, -- выполнено (награда выдана)
}

export type Data = {
	xp: number,
	levelPaid: number,
	questDay: number,
	quests: { Quest },
	stats: { [string]: number },
	kinds: { [string]: boolean },
	badges: { [string]: boolean },
	freeTries: number,
	exhibits: { [string]: boolean }, -- карточки экспонатов коллекции (этап 6, блок H2)
	colPaid: { [string]: boolean }, -- "thieves" / "exhibits": алмазы за полную коллекцию выданы
}

-- Что произошло и ещё не записано (копится в ProfileStore, уходит одним UpdateAsync).
export type Delta = {
	xp: number,
	questDay: number, -- день, к которому относится quest (другой день — счётчики отбрасываются)
	quest: { [string]: number }, -- ключ задания (Progress.questKey) -> сколько
	stats: { [string]: number }, -- прибавить
	best: { [string]: number }, -- взять наибольшее
	kinds: { [string]: boolean },
	exhibits: { [string]: boolean }, -- экспонаты, в покупку которых игрок вложил деньги (коллекция)
}

export type Events = {
	levels: { number }, -- новые уровни
	ranks: { string }, -- новые звания
	quests: { Quest }, -- выполненные задания
	badges: { string }, -- новые достижения
	cards: { string }, -- новые карточки коллекции: "Thief:Shadow", "Exhibit:Diamond"
	collections: { string }, -- собрана вся коллекция: "thieves" / "exhibits" (алмазы — в diamonds)
	diamonds: number, -- сколько алмазов за всё это
}

local STAT_NAMES = { "nights", "arrests", "revives", "runs", "raids", "wingsRun" }

---------------------------------------------------------------- уровни и звания

-- Сколько опыта нужно, чтобы с уровня level перейти на следующий.
function Progress.xpToNext(level: number): number
	return math.max(1, math.floor(Settings.LevelBase * level ^ Settings.LevelPower))
end

-- Уровень по всему опыту; сколько опыта набрано на этом уровне и сколько нужно до следующего.
function Progress.levelOf(xp: number): (number, number, number)
	local level, rest = 1, math.max(0, xp)
	while level < Settings.MaxLevel do
		local need = Progress.xpToNext(level)
		if rest < need then
			return level, rest, need
		end
		rest -= need
		level += 1
	end
	return level, 0, 0
end

-- Звание для уровня: { Name, Level, Color } и его номер.
function Progress.rankOf(level: number): ({ Name: string, Level: number, Color: Color3 }, number)
	local ranks = Settings.Ranks
	local index = 1
	for i, rank in ranks do
		if level >= rank.Level then
			index = i
		end
	end
	return ranks[index], index
end

-- Звание, которое начинается ровно с этого уровня (nil — новое звание не даётся).
local function rankStartingAt(level: number): { Name: string, Level: number, Color: Color3 }?
	for i, rank in Settings.Ranks do
		if i > 1 and rank.Level == level then
			return rank
		end
	end
	return nil
end

---------------------------------------------------------------- коллекция (этап 6, блок H2)

-- Карточки экспонатов по порядку: 18 экспонатов постаментов, последней — Мона Лиза.
function Progress.collectionExhibits(): { string }
	local list = table.clone(Config.Exhibits.Slots)
	table.insert(list, Config.Collection.MonaLisa)
	return list
end

-- Имя карточки для игрока: "Thief:Shadow" → "SHADOW", "Exhibit:Diamond" → "DIAMOND".
function Progress.cardTitle(card: string): string
	local group, id = string.match(card, "^(%a+):(.+)$")
	if group == "Thief" and id then
		local info = (Config.ThiefTypes :: any)[id]
		return string.upper(if info then tostring(info.Title) else id)
	elseif group == "Exhibit" and id then
		if id == Config.Collection.MonaLisa then
			return string.upper(Config.Collection.MonaLisaTitle)
		end
		local info = (Config.Exhibits.Kinds :: any)[id]
		return string.upper(if info then tostring(info.Title) else id)
	end
	return string.upper(card)
end

-- Сколько карточек открыто: воры (открыто, всего) и экспонаты (открыто, всего).
function Progress.collectionCount(data: Data): (number, number, number, number)
	local thieves, exhibits = 0, 0
	for _, kind in Config.Collection.Thieves do
		if data.kinds[kind] then
			thieves += 1
		end
	end
	local list = Progress.collectionExhibits()
	for _, id in list do
		if data.exhibits[id] then
			exhibits += 1
		end
	end
	return thieves, #Config.Collection.Thieves, exhibits, #list
end

---------------------------------------------------------------- данные

function Progress.newData(): Data
	return {
		xp = 0,
		levelPaid = 1,
		questDay = 0,
		quests = {},
		stats = {},
		kinds = {},
		badges = {},
		freeTries = 0,
		exhibits = {},
		colPaid = {},
	}
end

function Progress.newDelta(): Delta
	return { xp = 0, questDay = 0, quest = {}, stats = {}, best = {}, kinds = {}, exhibits = {} }
end

local function questInfo(kind: any): { [string]: any }?
	for _, info in Config.Quests.List do
		if info.Kind == kind then
			return info
		end
	end
	return nil
end

local function count(value: any, max: number?): number
	local n = math.max(0, math.floor(tonumber(value) or 0))
	return if max then math.min(n, max) else n
end

-- Сохранённые поля → Data. Чужое и сломанное отбрасывается; чего нет (старый профиль) — по умолчанию.
function Progress.clean(raw: any): Data
	local data = Progress.newData()
	if typeof(raw) ~= "table" then
		return data
	end
	data.xp = count(raw.xp)
	local level = Progress.levelOf(data.xp)
	-- Старый профиль без levelPaid: за уже набранные уровни алмазы не выдаём задним числом
	data.levelPaid = if raw.levelPaid == nil then level else math.clamp(count(raw.levelPaid), 1, Settings.MaxLevel)
	data.questDay = count(raw.questDay)
	if typeof(raw.quests) == "table" then
		for _, q in raw.quests do
			if typeof(q) == "table" and #data.quests < Config.Quests.PerDay then
				local info = questInfo(q.k)
				if info then
					local goal = math.max(1, count(q.g, 999))
					table.insert(data.quests, {
						k = info.Kind,
						g = goal,
						r = count(q.r, 1000),
						c = if typeof(q.c) == "string" and (Config.Classes :: any)[q.c] then q.c else nil,
						p = count(q.p, goal),
						d = q.d == true,
					})
				end
			end
		end
	end
	if typeof(raw.stats) == "table" then
		for _, name in STAT_NAMES do
			data.stats[name] = count(raw.stats[name])
		end
	end
	if typeof(raw.kinds) == "table" then
		for _, kind in Config.Collection.Thieves do
			if raw.kinds[kind] == true then
				data.kinds[kind] = true
			end
		end
	end
	if typeof(raw.exhibits) == "table" then
		for _, id in Progress.collectionExhibits() do
			if raw.exhibits[id] == true then
				data.exhibits[id] = true
			end
		end
	end
	-- Мону Лизу охраняют, а не покупают: старый профиль с пережитыми ночами видит её сразу
	if (data.stats.nights or 0) >= Config.Collection.MonaLisaNights then
		data.exhibits[Config.Collection.MonaLisa] = true
	end
	if typeof(raw.colPaid) == "table" then
		for _, name in { "thieves", "exhibits" } do
			if raw.colPaid[name] == true then
				data.colPaid[name] = true
			end
		end
	end
	if typeof(raw.badges) == "table" then
		for _, id in Config.Badges.Order do
			if raw.badges[id] == true then
				data.badges[id] = true
			end
		end
	end
	data.freeTries = count(raw.freeTries, 10)
	return data
end

-- Data → то, что пишется в DataStore (только строки-ключи, числа, boolean).
function Progress.pack(data: Data): { [string]: any }
	local quests = {}
	for _, q in data.quests do
		table.insert(quests, { k = q.k, g = q.g, r = q.r, c = q.c, p = q.p, d = q.d })
	end
	local stats, kinds, badges, exhibits, colPaid = {}, {}, {}, {}, {}
	for name, value in data.stats do
		stats[name] = value
	end
	for kind in data.kinds do
		kinds[kind] = true
	end
	for id in data.badges do
		badges[id] = true
	end
	for id in data.exhibits do
		exhibits[id] = true
	end
	for name in data.colPaid do
		colPaid[name] = true
	end
	return {
		xp = data.xp,
		levelPaid = data.levelPaid,
		questDay = data.questDay,
		quests = quests,
		stats = stats,
		kinds = kinds,
		badges = badges,
		freeTries = data.freeTries,
		exhibits = exhibits,
		colPaid = colPaid,
	}
end

function Progress.copy(data: Data): Data
	return Progress.clean(Progress.pack(data))
end

---------------------------------------------------------------- задания

-- Ключ задания для счётчиков: "Arrest", у задания за класс — "PlayClass:Operator".
function Progress.questKey(q: Quest): string
	return if q.c then q.k .. ":" .. q.c else q.k
end

-- 3 задания на день. Зерно — игрок и день, поэтому на всех серверах одинаково (если купленные классы те же).
-- owned — купленные классы по порядку (для задания «сыграй за класс»).
local function generate(userId: number, day: number, owned: { string }): { Quest }
	local rng = Random.new(userId * 1013 + day)
	local pool = table.clone(Config.Quests.List)
	local result: { Quest } = {}
	while #result < Config.Quests.PerDay and #pool > 0 do
		local info = table.remove(pool, rng:NextInteger(1, #pool)) :: any
		local tier = rng:NextInteger(1, #info.Goals)
		local q: Quest = { k = info.Kind, g = info.Goals[tier], r = info.Rewards[tier], p = 0, d = false }
		if info.Kind == "PlayClass" then
			q.c = owned[rng:NextInteger(1, math.max(1, #owned))] or Config.Classes.Default
		end
		table.insert(result, q)
	end
	return result
end

-- Начался новый день — новые задания (вчерашние незаконченные пропадают).
function Progress.rollQuests(data: Data, userId: number, today: number, owned: { string }): boolean
	if data.questDay == today and #data.quests > 0 then
		return false
	end
	data.questDay = today
	data.quests = generate(userId, today, owned)
	return true
end

-- Текст задания для игрока: «ARREST 6 THIEVES», «PLAY A NIGHT AS OPERATOR».
function Progress.questText(q: Quest): string
	local info = questInfo(q.k)
	if not info then
		return string.upper(q.k)
	end
	local className = ""
	if q.c then
		local classInfo = (Config.Classes :: any)[q.c]
		className = string.upper(if classInfo then tostring(classInfo.Title) else q.c)
	end
	if q.g == 1 then
		return (string.format(info.TextOne, className))
	end
	if q.c then
		return (string.format(info.Text, q.g, className))
	end
	return (string.format(info.Text, q.g))
end

---------------------------------------------------------------- достижения

-- Сколько сделано и сколько нужно для достижения.
function Progress.badgeProgress(id: string, data: Data): (number, number)
	local info = (Config.Badges :: any)[id]
	if typeof(info) ~= "table" then
		return 0, 1
	end
	if info.Stat == "kinds" then
		local have = 0
		for _, kind in Config.Collection.Thieves do
			if data.kinds[kind] then
				have += 1
			end
		end
		local goal = if (info.Goal or 0) > 0 then info.Goal else #Config.Collection.Thieves
		return math.min(have, goal), goal
	end
	local goal = math.max(1, info.Goal or 1)
	return math.min(data.stats[info.Stat] or 0, goal), goal
end

---------------------------------------------------------------- применение

-- Применяет то, что произошло (delta), к данным: опыт и уровни, задания, счётчики, достижения.
-- Возвращает события и сколько за них алмазов (их прибавляет вызывающий). today — номер дня UTC.
-- Один и тот же код — в памяти сервера (показать сразу) и внутри UpdateAsync (сохранить по сохранённому).
function Progress.apply(data: Data, delta: Delta, today: number, userId: number, owned: { string }): Events
	local events: Events = { levels = {}, ranks = {}, quests = {}, badges = {}, cards = {}, collections = {}, diamonds = 0 }
	-- Опыт и уровни
	if delta.xp > 0 then
		data.xp += delta.xp
	end
	local level = Progress.levelOf(data.xp)
	if level > data.levelPaid then
		for newLevel = data.levelPaid + 1, level do
			table.insert(events.levels, newLevel)
			events.diamonds += Settings.LevelDiamonds
			local rank = rankStartingAt(newLevel)
			if rank then
				table.insert(events.ranks, rank.Name)
				events.diamonds += Settings.RankDiamonds
			end
		end
		data.levelPaid = level
	end
	-- Задания (сначала новый день, если начался)
	Progress.rollQuests(data, userId, today, owned)
	if delta.questDay == today then
		for _, q in data.quests do
			local n = delta.quest[Progress.questKey(q)]
			if not q.d and n and n > 0 then
				q.p = math.min(q.g, q.p + n)
				if q.p >= q.g then
					q.d = true
					events.diamonds += q.r
					table.insert(events.quests, q)
				end
			end
		end
	end
	-- Счётчики и виды воров
	for name, n in delta.stats do
		data.stats[name] = (data.stats[name] or 0) + n
	end
	for name, n in delta.best do
		data.stats[name] = math.max(data.stats[name] or 0, n)
	end
	-- Коллекция (этап 6, блок H2): новые карточки воров и экспонатов, Мона Лиза после первой пережитой ночи
	for _, kind in Config.Collection.Thieves do
		if delta.kinds[kind] and not data.kinds[kind] then
			data.kinds[kind] = true
			table.insert(events.cards, "Thief:" .. kind)
		end
	end
	local monaLisa = Config.Collection.MonaLisa
	for _, id in Progress.collectionExhibits() do
		local earned = delta.exhibits[id] == true
			or (id == monaLisa and (data.stats.nights or 0) >= Config.Collection.MonaLisaNights)
		if earned and not data.exhibits[id] then
			data.exhibits[id] = true
			table.insert(events.cards, "Exhibit:" .. id)
		end
	end
	local thieves, thievesTotal, exhibits, exhibitsTotal = Progress.collectionCount(data)
	if thieves >= thievesTotal and not data.colPaid.thieves then
		data.colPaid.thieves = true
		events.diamonds += Config.Collection.ThievesDiamonds
		table.insert(events.collections, "thieves")
	end
	if exhibits >= exhibitsTotal and not data.colPaid.exhibits then
		data.colPaid.exhibits = true
		events.diamonds += Config.Collection.ExhibitsDiamonds
		table.insert(events.collections, "exhibits")
	end
	-- Достижения
	for _, id in Config.Badges.Order do
		if not data.badges[id] then
			local have, goal = Progress.badgeProgress(id, data)
			if have >= goal then
				data.badges[id] = true
				table.insert(events.badges, id)
			end
		end
	end
	return events
end

-- Есть ли в delta что-то, что надо записать.
function Progress.isEmpty(delta: Delta): boolean
	return delta.xp == 0 and next(delta.quest) == nil and next(delta.stats) == nil and next(delta.best) == nil
		and next(delta.kinds) == nil and next(delta.exhibits) == nil
end

function Progress.copyDelta(delta: Delta): Delta
	return {
		xp = delta.xp,
		questDay = delta.questDay,
		quest = table.clone(delta.quest),
		stats = table.clone(delta.stats),
		best = table.clone(delta.best),
		kinds = table.clone(delta.kinds),
		exhibits = table.clone(delta.exhibits),
	}
end

-- Прибавить новое (delta) к ещё не записанному (into). Счётчики заданий другого дня отбрасываются.
function Progress.merge(into: Delta, delta: Delta)
	into.xp += delta.xp
	if next(delta.quest) ~= nil then
		if into.questDay ~= delta.questDay then
			into.questDay = delta.questDay
			table.clear(into.quest)
		end
		for key, n in delta.quest do
			into.quest[key] = (into.quest[key] or 0) + n
		end
	end
	for name, n in delta.stats do
		into.stats[name] = (into.stats[name] or 0) + n
	end
	for name, n in delta.best do
		into.best[name] = math.max(into.best[name] or 0, n)
	end
	for kind in delta.kinds do
		into.kinds[kind] = true
	end
	for id in delta.exhibits do
		into.exhibits[id] = true
	end
end

-- Записанное (sent) убрать из ещё не записанного (pending): то, что пришло за время запроса, остаётся.
function Progress.subtract(pending: Delta, sent: Delta)
	pending.xp -= sent.xp
	if pending.questDay == sent.questDay then
		for key, n in sent.quest do
			local left = (pending.quest[key] or 0) - n
			if left > 0 then
				pending.quest[key] = left
			else
				pending.quest[key] = nil
			end
		end
	end
	for name, n in sent.stats do
		local left = (pending.stats[name] or 0) - n
		if left > 0 then
			pending.stats[name] = left
		else
			pending.stats[name] = nil
		end
	end
	for name, n in sent.best do
		if (pending.best[name] or 0) <= n then
			pending.best[name] = nil
		end
	end
	for kind in sent.kinds do
		pending.kinds[kind] = nil
	end
	for id in sent.exhibits do
		pending.exhibits[id] = nil
	end
end

---------------------------------------------------------------- ближайшая награда (этап 6, блок H2)

export type Goal = {
	kind: string, -- "Class" | "Level" | "Quest"
	icon: string, -- пиксельная иконка (UI/PixelIcon)
	text: string, -- надпись на полоске: «38/150 TO TECHNICIAN»
	near: string, -- крупно на GAME OVER: «112 MORE TO TECHNICIAN»
	have: number,
	need: number,
	fraction: number, -- 0..1
	ready: boolean, -- уже можно забрать (класс по карману)
}

-- Самая близкая награда: класс за алмазы, следующий уровень или задание дня. Выбирается та, где пройдено больше
-- всего (доля). Класс, на который уже хватает алмазов, — сразу он. quests — задания СЕГОДНЯШНЕГО дня (вчерашние не
-- передавать); owns(role) — куплен ли класс. Одинаково у клиента (по атрибутам) и сервера.
function Progress.nearestGoal(xp: number, quests: { Quest }, diamonds: number, owns: (role: string) -> boolean): Goal?
	local best: Goal? = nil
	local function consider(goal: Goal)
		if not best or goal.fraction > (best :: Goal).fraction then
			best = goal
		end
	end
	-- Класс: самый дешёвый некупленный (у него доля больше всех); хватает — «можно купить»
	for _, role in Config.Classes.Order do
		local info = (Config.Classes :: any)[role]
		local price = math.max(0, tonumber(info and info.Price) or 0)
		if price > 0 and not owns(role) then
			local title = string.upper(tostring(info.Title))
			if diamonds >= price then
				return {
					kind = "Class",
					icon = "Diamond",
					text = ("%s IS READY - BUY IT IN THE SHOP!"):format(title),
					near = ("YOU CAN BUY %s NOW!"):format(title),
					have = price,
					need = price,
					fraction = 1,
					ready = true,
				}
			end
			consider({
				kind = "Class",
				icon = "Diamond",
				text = ("%d/%d TO %s"):format(diamonds, price, title),
				near = ("%d MORE TO %s"):format(price - diamonds, title),
				have = diamonds,
				need = price,
				fraction = diamonds / price,
				ready = false,
			})
			break
		end
	end
	-- Задание дня: незаконченное, где сделано больше всего
	for _, q in quests do
		if not q.d and q.g > 0 then
			local fraction = q.p / q.g
			if not best or fraction > (best :: Goal).fraction then
				consider({
					kind = "Quest",
					icon = "Quests",
					text = ("QUEST %d/%d: %s"):format(q.p, q.g, Progress.questText(q)),
					near = if q.g - q.p <= 2
						then ("QUEST ALMOST DONE: %d/%d"):format(q.p, q.g)
						else ("QUEST: %d/%d %s"):format(q.p, q.g, Progress.questText(q)),
					have = q.p,
					need = q.g,
					fraction = fraction,
					ready = false,
				})
			end
		end
	end
	-- Следующий уровень
	local level, have, need = Progress.levelOf(xp)
	if need > 0 then
		consider({
			kind = "Level",
			icon = "Medal",
			text = ("LV %d > %d: %d/%d XP"):format(level, level + 1, have, need),
			near = ("%d XP TO LEVEL %d"):format(need - have, level + 1),
			have = have,
			need = need,
			fraction = have / need,
			ready = false,
		})
	end
	return best
end

---------------------------------------------------------------- для атрибутов игрока

-- Задания → строка JSON для атрибута Quests (атрибут не может быть таблицей).
function Progress.encodeQuests(data: Data): string
	local list = {}
	for _, q in data.quests do
		table.insert(list, { k = q.k, g = q.g, r = q.r, c = q.c, p = q.p, d = q.d })
	end
	return HttpService:JSONEncode({ day = data.questDay, list = list })
end

-- Атрибут Quests → день и задания (клиент). Сломанное — пусто.
function Progress.decodeQuests(text: any): (number, { Quest })
	if typeof(text) ~= "string" or text == "" then
		return 0, {}
	end
	local ok, raw = pcall(HttpService.JSONDecode, HttpService, text)
	if not ok or typeof(raw) ~= "table" then
		return 0, {}
	end
	local data = Progress.clean({ questDay = raw.day, quests = raw.list })
	return data.questDay, data.quests
end

-- Счётчики, виды воров, экспонаты коллекции и достижения → JSON для атрибута Stats (окна достижений и коллекции).
function Progress.encodeStats(data: Data): string
	local packed = Progress.pack(data)
	return HttpService:JSONEncode({
		stats = packed.stats,
		kinds = packed.kinds,
		badges = packed.badges,
		exhibits = packed.exhibits,
		colPaid = packed.colPaid,
	})
end

function Progress.decodeStats(text: any): Data
	if typeof(text) ~= "string" or text == "" then
		return Progress.newData()
	end
	local ok, raw = pcall(HttpService.JSONDecode, HttpService, text)
	if not ok or typeof(raw) ~= "table" then
		return Progress.newData()
	end
	return Progress.clean(raw)
end

return Progress
