-- Крылья музея (этап 5, блок B, решение 77). В начале забега открыт только центр: входы музея — 4 двери в его
-- стенах, за каждой тамбур, дальше заколоченная стена крыла (коридор + входной холл) с ценой.
-- Крыло покупается удержанием F у стены (Purchase.take, вскладчину) или в окне магазина (вкладка Halls, сверху).
-- Цена — по тому, сколько крыльев уже куплено: $100 / $200 / $300 / $400 (Config.Wings.Prices), в любом порядке.
-- Купили — доски падают, дверь центра этой стороны становится аркой (DoorService), вход этой стороны — наружная
-- дверь в конце крыла, работают камеры холла, можно купить зал угла, приходит больше туристов.
-- Открыто ли крыло — атрибут GameState «зал открыт» (HallOpen_WingSouth). Новый забег — все крылья снова закрыты.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local Audio = require(Server:WaitForChild("Audio"))
local Purchase = require(Server:WaitForChild("Purchase"))
local ShopService = require(Server:WaitForChild("ShopService"))
local ProgressService = require(Server:WaitForChild("ProgressService"))

local Settings = Config.Wings

local WingService = {}

type Wing = {
	id: string, -- WingSouth
	title: string, -- SOUTH WING
	paid: number,
	model: Model,
	template: Model, -- копия целой стены, чтобы заколотить её снова в новом забеге
	prompt: ProximityPrompt?,
}

local wings: { [string]: Wing } = {}
local wallsFolder: Instance? = nil
local entrances: { BasePart } = {}
local dayActive = false

function WingService.isOpen(id: string): boolean
	return GameState.isHallOpen(id)
end

-- Сколько крыльев уже куплено.
function WingService.openCount(): number
	local count = 0
	for _, id in GameState.WingOrder do
		if GameState.isHallOpen(id) then
			count += 1
		end
	end
	return count
end

-- Цена следующего крыла: дорожает с каждым купленным.
function WingService.price(): number
	local prices = Settings.Prices
	return prices[math.min(WingService.openCount() + 1, #prices)]
end

-- Входы музея сейчас: у закрытого крыла — дверь центра, у купленного — наружная дверь в конце крыла.
-- Отсюда приходят туристы, воры и грабители, сюда они убегают.
function WingService.entrances(): { BasePart }
	local list = {}
	for _, marker in entrances do
		if GameState.isEntranceOpen(marker) then
			table.insert(list, marker)
		end
	end
	return list
end

local function panelOf(wing: Wing): BasePart?
	local panel = wing.model:FindFirstChild(MapSchema.HallDoorPanel)
	return if panel and panel:IsA("BasePart") then panel else nil
end

local function updateSign(wing: Wing)
	local price = WingService.price()
	local sign = wing.model:FindFirstChild(MapSchema.HallDoorSign, true)
	local gui = sign and sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		local cost = if wing.paid > 0 then ("$%d / $%d"):format(wing.paid, price) else ("$%d"):format(price)
		label.Text = ("%s\n%s\nNEW ENTRANCE • MORE TOURISTS"):format(wing.title, cost)
	end
	if wing.prompt then
		wing.prompt.ObjectText = Purchase.progressText(wing.title, wing.paid, price)
		Purchase.setProgress(wing.prompt, wing.paid, price)
	end
end

local function refresh(wing: Wing)
	if wing.prompt then
		wing.prompt.Enabled = dayActive and not WingService.isOpen(wing.id)
	end
	if not WingService.isOpen(wing.id) then
		updateSign(wing)
	end
end

local function refreshAll()
	for _, wing in wings do
		refresh(wing)
	end
	ShopService.refresh()
end

local function openWing(wing: Wing)
	GameState.set(GameState.hallOpenAttr(wing.id), true)
	if wing.prompt then
		wing.prompt.Enabled = false
	end
	Remotes.get(Remotes.Names.Banner):FireAllClients(wing.title .. " IS OPEN!", "info")
	local panel = panelOf(wing)
	if panel then
		Audio.playOnce(Config.Sounds.HallOpen, panel, Config.Sounds.HallOpenVolume)
	end
	-- Доски падают и тают (как у залов)
	local info = TweenInfo.new(Settings.BoardsFallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, part in wing.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			TweenService:Create(part, info, {
				CFrame = part.CFrame * CFrame.new(0, -3, 0) * CFrame.Angles(math.rad(70), 0, 0),
				Transparency = 1,
			}):Play()
		end
	end
	local fallingModel = wing.model
	task.delay(Settings.BoardsFallSeconds, function()
		if fallingModel.Parent and wing.model == fallingModel then
			fallingModel.Parent = nil -- храним до нового забега (reset)
		end
	end)
	refreshAll() -- остальные крылья подорожали
end

-- Удержание F у стены (или покупка из окна магазина — fromShop, без проверки расстояния): остаток цены,
-- если хватает денег, иначе всё, что есть (Purchase.take). Возвращает, сколько взяли.
local function contribute(wing: Wing, player: Player, fromShop: boolean?): number
	if not dayActive or WingService.isOpen(wing.id) then
		return 0
	end
	local panel = panelOf(wing)
	if not panel then
		return 0
	end
	local price = WingService.price()
	local amount = 0
	if wing.paid < price then
		amount = Purchase.take(player, panel, wing.paid, price, fromShop)
		if amount <= 0 then
			return 0
		end
		wing.paid += amount
	end
	if wing.paid >= price then
		ProgressService.teamBought(Purchase.backers(panel), "Wing")
		openWing(wing)
	else
		updateSign(wing)
	end
	return amount
end

local function attachPrompt(wing: Wing)
	local panel = panelOf(wing)
	if not panel then
		warn("[WingService] У стены крыла нет щита", wing.model:GetFullName())
		return
	end
	local prompt = Purchase.newPrompt(panel, "BuyPrompt", WingService.price())
	prompt.Triggered:Connect(function(player)
		contribute(wing, player)
	end)
	wing.prompt = prompt
end

-- Днём можно вкладывать деньги, ночью — нет.
function WingService.setDayActive(active: boolean)
	dayActive = active
	for _, wing in wings do
		refresh(wing)
	end
end

-- Новый забег: все крылья снова заколочены, вложенные деньги обнуляются.
function WingService.reset()
	for _, wing in wings do
		GameState.set(GameState.hallOpenAttr(wing.id), false)
	end
	for _, wing in wings do
		if wing.model then
			wing.model:Destroy()
		end
		wing.model = wing.template:Clone()
		wing.model.Parent = wallsFolder
		wing.paid = 0
		wing.prompt = nil
		attachPrompt(wing)
		refresh(wing)
	end
end

-- Крыло в окне магазина (вкладка Halls, сверху, перед залами).
local function registerInShop(wing: Wing, order: number)
	local preview = wing.template:Clone()
	ShopService.register({
		category = "Halls",
		id = wing.id,
		title = wing.title,
		info = ("New entrance farther away • +%d tourists a day"):format(Settings.Tourists),
		order = order,
		price = WingService.price(),
		preview = preview,
		state = function(): ShopService.State
			return { paid = wing.paid, owned = WingService.isOpen(wing.id), price = WingService.price() }
		end,
		buy = function(player: Player): (string, string)
			if WingService.isOpen(wing.id) then
				return ShopService.fail(wing.title .. " is already open")
			end
			local price = WingService.price()
			local amount = contribute(wing, player, true)
			return ShopService.sharedResult(wing.title, amount, math.min(wing.paid, price), price)
		end,
	})
end

function WingService.init(map: Instance)
	local entranceFolder = map:FindFirstChild(MapSchema.Entrances)
	if entranceFolder then
		for _, child in entranceFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(entrances, child)
			end
		end
	end
	wallsFolder = map:FindFirstChild(MapSchema.WingDoors)
	for _, id in GameState.WingOrder do
		GameState.set(GameState.hallOpenAttr(id), false)
	end
	if wallsFolder then
		for _, model in wallsFolder:GetChildren() do
			local id = model:GetAttribute("Wing")
			if model:IsA("Model") and GameState.isWing(id) then
				local wing: Wing = {
					id = id,
					title = (Settings.Titles :: any)[id] or id,
					paid = 0,
					model = model,
					template = model:Clone(),
					prompt = nil,
				}
				wings[id] = wing
				attachPrompt(wing)
				refresh(wing)
			end
		end
	end
	-- Карта без стен крыльев (собрана в Studio по-старому): все крылья открыты, входы — как раньше
	if next(wings) == nil then
		for _, id in GameState.WingOrder do
			GameState.set(GameState.hallOpenAttr(id), true)
		end
	end
	for order, id in GameState.WingOrder do
		local wing = wings[id]
		if wing then
			registerInShop(wing, order)
		end
	end
	if #entrances == 0 then
		warn("[WingService] На карте нет входов")
	end
end

return WingService
