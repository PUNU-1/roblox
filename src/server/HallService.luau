-- 4 зала за деньги (Скульптуры, Динозавры, Драгоценности, Космос): закрыты заколоченными дверями с ценой.
-- Днём игрок подходит к двери и держит F: хватает денег — покупает зал сразу, нет — все его деньги
-- идут в полоску, остальное докладывают другие (Purchase.luau, у каждого свой кошелёк).
-- Набрали цену — доски падают, зал открыт: его камеры работают, туристы и воры идут к его экспонатам.
-- Этап 5, блок B: зал угла покупается, только когда открыто его крыло (GameState.HallWing), иначе — «WING CLOSED».
-- Двери входов открываются сами (DoorService).

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
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local ShopService = require(Server:WaitForChild("ShopService"))

local HallConfig = Config.Halls

local HallService = {}

type Door = {
	hall: string,
	price: number,
	title: string,
	paid: number,
	model: Model,
	template: Model, -- копия целой двери, чтобы заколотить её снова в новом забеге
	prompt: ProximityPrompt?,
}

local doors: { [string]: Door } = {}
local doorsFolder: Instance? = nil
local dayActive = false

local function hallSettings(hall: string): { Price: number, Title: string }?
	local settings = (HallConfig :: any)[hall]
	if typeof(settings) == "table" then
		return settings
	end
	return nil
end

-- Крыло, из которого вход в зал (этап 5, блок B), и открыто ли оно.
local function wingOf(door: Door): string?
	return (GameState.HallWing :: any)[door.hall]
end

local function wingOpen(door: Door): boolean
	local wing = wingOf(door)
	return wing == nil or GameState.isHallOpen(wing)
end

local function wingTitle(door: Door): string
	local wing = wingOf(door)
	return if wing then tostring((Config.Wings.Titles :: any)[wing] or wing) else "WING"
end

local function updateSign(door: Door)
	local sign = door.model:FindFirstChild(MapSchema.HallDoorSign, true)
	local gui = sign and sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = if door.paid > 0
			then ("%s\n$%d / $%d"):format(door.title, door.paid, door.price)
			else ("%s\n$%d"):format(door.title, door.price)
		if not wingOpen(door) then
			label.Text ..= "\nOPEN THE " .. wingTitle(door) .. " FIRST"
		end
	end
	if door.prompt then
		door.prompt.ObjectText = Purchase.progressText(door.title, door.paid, door.price)
		Purchase.setProgress(door.prompt, door.paid, door.price)
	end
end

local function refreshPrompt(door: Door)
	if door.prompt then
		door.prompt.Enabled = dayActive and not GameState.isHallOpen(door.hall) and wingOpen(door)
	end
end

local function openHall(door: Door)
	GameState.set(GameState.hallOpenAttr(door.hall), true)
	if door.prompt then
		door.prompt.Enabled = false
	end
	Remotes.get(Remotes.Names.Banner):FireAllClients(door.title .. " IS OPEN!", "info")
	local panel = door.model:FindFirstChild(MapSchema.HallDoorPanel)
	if panel and panel:IsA("BasePart") then
		Audio.playOnce(Config.Sounds.HallOpen, panel, Config.Sounds.HallOpenVolume)
	end
	-- Доски падают и тают
	local info = TweenInfo.new(HallConfig.BoardsFallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, part in door.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			TweenService:Create(part, info, {
				CFrame = part.CFrame * CFrame.new(0, -3, 0) * CFrame.Angles(math.rad(70), 0, 0),
				Transparency = 1,
			}):Play()
		end
	end
	local fallingModel = door.model
	task.delay(HallConfig.BoardsFallSeconds, function()
		if fallingModel.Parent and door.model == fallingModel then
			fallingModel.Parent = nil -- храним до нового забега (reset)
		end
	end)
end

-- Удержание F у двери (или покупка из окна магазина — fromShop, без проверки расстояния): остаток цены,
-- если хватает денег, иначе всё, что есть (Purchase.take). Возвращает, сколько взяли.
local function contribute(door: Door, player: Player, fromShop: boolean?): number
	if not dayActive or GameState.isHallOpen(door.hall) or not wingOpen(door) then
		return 0
	end
	local panel = door.model:FindFirstChild(MapSchema.HallDoorPanel)
	if not (panel and panel:IsA("BasePart")) then
		return 0
	end
	local amount = Purchase.take(player, panel, door.paid, door.price, fromShop)
	if amount <= 0 then
		return 0
	end
	door.paid += amount
	updateSign(door)
	if door.paid >= door.price then
		openHall(door)
	end
	return amount
end

local function attachPrompt(door: Door)
	local panel = door.model:FindFirstChild(MapSchema.HallDoorPanel)
	if not (panel and panel:IsA("BasePart")) then
		warn("[HallService] У двери нет щита", door.model:GetFullName())
		return
	end
	local prompt = Purchase.newPrompt(panel, "BuyPrompt", door.price)
	prompt.Triggered:Connect(function(player)
		contribute(door, player)
	end)
	door.prompt = prompt
end

-- Днём можно вкладывать деньги, ночью — нет.
function HallService.setDayActive(active: boolean)
	dayActive = active
	for _, door in doors do
		refreshPrompt(door)
	end
end

-- Новый забег: все залы снова заколочены, вложенные деньги обнуляются.
function HallService.reset()
	for _, door in doors do
		if door.model then
			door.model:Destroy()
		end
		door.model = door.template:Clone()
		door.model.Parent = doorsFolder
		door.paid = 0
		door.prompt = nil
		attachPrompt(door)
		GameState.set(GameState.hallOpenAttr(door.hall), false)
		updateSign(door)
		refreshPrompt(door)
	end
end

-- Зал в окне магазина (этап 4, блок 1b): сколько вложено и открыт ли. spots — сколько в нём постаментов.
local function registerInShop(door: Door, spots: number)
	ShopService.register({
		category = "Halls",
		id = door.hall,
		title = door.title,
		info = ("%d exhibit spots • more tourists"):format(spots),
		order = 10 + (table.find(GameState.PaidHalls, door.hall) or #GameState.PaidHalls + 1), -- после крыльев
		price = door.price,
		hall = wingOf(door), -- крыло закрыто — «WING CLOSED»
		preview = ExhibitService.hallPreview(door.hall),
		state = function(): ShopService.State
			return { paid = door.paid, owned = GameState.isHallOpen(door.hall) }
		end,
		buy = function(player: Player): (string, string)
			if GameState.isHallOpen(door.hall) then
				return ShopService.fail(door.title .. " is already open")
			elseif not wingOpen(door) then
				return ShopService.fail(("Open the %s first"):format(wingTitle(door)))
			end
			local amount = contribute(door, player, true)
			return ShopService.sharedResult(door.title, amount, door.paid, door.price)
		end,
	})
end

function HallService.init(map: Instance)
	GameState.set(GameState.hallOpenAttr(GameState.Hall.Main), true)
	doorsFolder = map:FindFirstChild(MapSchema.HallDoors)
	if doorsFolder then
		for _, model in doorsFolder:GetChildren() do
			local hall = model:GetAttribute("Hall")
			local settings = typeof(hall) == "string" and hallSettings(hall) or nil
			if model:IsA("Model") and typeof(hall) == "string" and settings then
				local door: Door = {
					hall = hall,
					price = settings.Price,
					title = settings.Title,
					paid = 0,
					model = model,
					template = model:Clone(),
					prompt = nil,
				}
				doors[hall] = door
				attachPrompt(door)
				GameState.set(GameState.hallOpenAttr(hall), false)
				updateSign(door)
			end
		end
	end
	-- Крыло купили или забег начался заново — у двери зала меняются надпись и кнопка
	GameState.folder().AttributeChanged:Connect(function(attr)
		if string.sub(attr, 1, #"HallOpen_Wing") == "HallOpen_Wing" then
			for _, door in doors do
				if not GameState.isHallOpen(door.hall) then
					updateSign(door)
					refreshPrompt(door)
				end
			end
		end
	end)
	local pedestals = map:FindFirstChild(MapSchema.Pedestals)
	for _, hall in GameState.PaidHalls do
		local door = doors[hall]
		if door then
			local spots = 0
			for _, pedestal in (if pedestals then pedestals:GetChildren() else {}) do
				if pedestal:GetAttribute("Hall") == hall then
					spots += 1
				end
			end
			registerInShop(door, spots)
		end
	end
end

return HallService
