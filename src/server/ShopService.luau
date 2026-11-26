--!strict
-- Окно магазина в музее (этап 4, блок 1b): днём клавиша B, кнопка SHOP или касса SHOP у Моны Лизы.
-- Сервисы, у которых есть покупки (экспонаты, залы, защита, камеры, оружейная), регистрируют здесь свои товары:
-- название, описание, цену, 3D-картинку и как узнать, сколько вложено и куплено ли.
-- Для окна товары лежат в ReplicatedStorage.Shop.<вкладка>.<id> (атрибуты GameState.ShopAttr, модель Preview) —
-- окно (Shop.client) только читает их. Сколько вложено и куплено ли, сервер обновляет раз в Config.Shop.RefreshSeconds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))

local ShopAttr = GameState.ShopAttr
local Reply = GameState.ShopReply

local ShopService = {}

-- Состояние общего товара (залы, экспонаты, защита, камеры): у всех одно.
export type State = {
	paid: number, -- сколько уже вложили вскладчину
	owned: boolean, -- куплено (зал — открыт)
	missing: string?, -- почему сейчас нельзя купить, кроме денег и зала: «NO EXHIBIT»
	price: number?, -- цена сейчас, если она меняется (крылья дорожают с каждым купленным, этап 5, блок B)
}

export type Item = {
	category: string, -- вкладка (Config.Shop.Tabs)
	id: string, -- уникален во вкладке
	title: string,
	info: string, -- одна строка описания
	order: number, -- место во вкладке
	price: number,
	hall: string?, -- зал товара: пока закрыт — HALL CLOSED
	personal: string?, -- товар оружейной (Config.Armory.Goods): у каждого свой, что можно купить — GameState.armoryOffer
	preview: PVInstance?, -- модель для 3D-картинки (её забирает магазин)
	state: (() -> State)?, -- для общих товаров
	-- Покупка из окна (те же правила, что у кнопки F, без проверки расстояния): ответ — GameState.ShopReply и надпись.
	-- Фазу (день), «на смене» и «не лежит» ShopService уже проверил.
	buy: (player: Player) -> (string, string),
}

type Entry = {
	item: Item,
	folder: Configuration,
}

local entries: { [string]: Entry } = {}
local root: Folder? = nil
local refreshConnection: RBXScriptConnection? = nil
local lastBuy: { [Player]: number } = {}
local counterPrompt: ProximityPrompt? = nil -- кнопка F «Open shop» у кассы SHOP (MapBuilder)

local function key(category: string, id: string): string
	return category .. "/" .. id
end

local function shopRoot(): Folder
	local existing = root
	if existing then
		return existing
	end
	local found = ReplicatedStorage:FindFirstChild(GameState.ShopFolder)
	local folder: Folder
	if found and found:IsA("Folder") then
		folder = found
	else
		folder = Instance.new("Folder")
		folder.Name = GameState.ShopFolder
		folder.Parent = ReplicatedStorage
	end
	for _, category in Config.Shop.Tabs do
		if not folder:FindFirstChild(category) then
			local tab = Instance.new("Folder")
			tab.Name = category
			tab.Parent = folder
		end
	end
	root = folder
	return folder
end

-- 3D-картинка для окна: без кнопок, надписей, света, звуков и скриптов, всё закреплено и ни с чем не сталкивается.
-- Картинку окно ставит в ViewportFrame: надписи (SurfaceGui) и свет там всё равно не видны.
local function cleanPreview(model: PVInstance)
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("ProximityPrompt")
			or descendant:IsA("LayerCollector")
			or descendant:IsA("Light")
			or descendant:IsA("Sound")
			or descendant:IsA("LuaSourceContainer")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
		then
			descendant:Destroy()
		end
	end
	local parts: { BasePart } = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
end

local function refreshEntry(entry: Entry)
	local state = entry.item.state
	if not state then
		return
	end
	local current = state()
	local folder = entry.folder
	folder:SetAttribute(ShopAttr.Paid, math.floor(current.paid))
	folder:SetAttribute(ShopAttr.Owned, current.owned)
	folder:SetAttribute(ShopAttr.Missing, current.missing or "")
	if current.price then
		folder:SetAttribute(ShopAttr.Price, current.price)
	end
end

-- Добавить товар в окно магазина. Модель preview магазин забирает себе (не клонирует).
function ShopService.register(item: Item)
	assert(table.find(Config.Shop.Tabs, item.category), "[ShopService] Нет такой вкладки: " .. item.category)
	local id = key(item.category, item.id)
	assert(entries[id] == nil, "[ShopService] Товар уже есть: " .. id)
	local folder = Instance.new("Configuration")
	folder.Name = item.id
	folder:SetAttribute(ShopAttr.Title, item.title)
	folder:SetAttribute(ShopAttr.Info, item.info)
	folder:SetAttribute(ShopAttr.Order, item.order)
	folder:SetAttribute(ShopAttr.Price, item.price)
	folder:SetAttribute(ShopAttr.Hall, item.hall or "")
	folder:SetAttribute(ShopAttr.Item, item.personal or "")
	local preview = item.preview
	if preview then
		cleanPreview(preview)
		preview:PivotTo(CFrame.identity)
		preview.Name = "Preview"
		preview.Parent = folder
	end
	local entry: Entry = { item = item, folder = folder }
	entries[id] = entry
	refreshEntry(entry)
	folder.Parent = shopRoot():FindFirstChild(item.category)
end

-- Ответ «не вышло» с причиной.
function ShopService.fail(text: string): (string, string)
	return Reply.Fail, text
end

-- Ответ на покупку общего товара вскладчину: amount — сколько взяли у игрока, paid — сколько теперь вложено всего.
function ShopService.sharedResult(title: string, amount: number, paid: number, price: number): (string, string)
	if amount <= 0 then
		return Reply.Fail, "You have no money — tourists bring more every day"
	elseif paid >= price then
		return Reply.Bought, "Bought: " .. title
	end
	return Reply.PutIn, ("Put in $%d — %s $%d / $%d"):format(amount, title, paid, price)
end

-- Remote ShopBuy(category, id): проверяем аргументы, частоту, фазу и игрока, покупает сервис товара.
local function onBuy(player: Player, category: any, id: any)
	if typeof(category) ~= "string" or typeof(id) ~= "string" or #category > 32 or #id > 64 then
		return
	end
	local entry = entries[key(category, id)]
	if not entry then
		return
	end
	local replyRemote = Remotes.get(Remotes.Names.ShopReply)
	local function reply(kind: string, text: string)
		replyRemote:FireClient(player, kind, category, id, text)
	end
	local now = os.clock()
	if now - (lastBuy[player] or -math.huge) < Config.Shop.BuyCooldown then
		reply(Reply.Fail, "Slow down a little")
		return
	end
	lastBuy[player] = now
	if GameState.phase() ~= GameState.Phase.Day then
		reply(Reply.Fail, "Shop opens in the morning")
		return
	elseif not RoleService.isParticipant(player) then
		reply(Reply.Fail, "Only guards on shift can shop")
		return
	elseif RoleService.isDowned(player) then
		reply(Reply.Fail, "You can't shop while you're down")
		return
	end
	local kind, text = entry.item.buy(player)
	refreshEntry(entry)
	reply(kind, text)
end

-- Обновить для окна «сколько вложено / куплено» у всех общих товаров.
function ShopService.refresh()
	for _, entry in entries do
		refreshEntry(entry)
	end
end

-- Днём у кассы SHOP горит кнопка F «Open shop» (окно открывает клиент), ночью — нет.
function ShopService.setDayActive(active: boolean)
	if counterPrompt then
		counterPrompt.Enabled = active
	end
end

function ShopService.init(map: Instance)
	shopRoot()
	local counter = map:FindFirstChild(MapSchema.ShopCounter, true)
	local prompt = counter and counter:FindFirstChild(MapSchema.ShopPrompt, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		counterPrompt = prompt
	else
		warn("[ShopService] Нет кассы SHOP на карте")
	end
	if refreshConnection then
		return
	end
	Remotes.get(Remotes.Names.ShopBuy).OnServerEvent:Connect(onBuy)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
	local accumulator = 0
	refreshConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Config.Shop.RefreshSeconds then
			accumulator = 0
			ShopService.refresh()
		end
	end)
end

return ShopService
