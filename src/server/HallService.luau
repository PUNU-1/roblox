-- 4 зала за деньги (Скульптуры, Динозавры, Драгоценности, Космос): закрыты заколоченными дверями с ценой.
-- Днём игрок подходит к двери и держит F: хватает денег — покупает зал сразу, нет — все его деньги
-- идут в полоску, остальное докладывают другие (Purchase.luau, у каждого свой кошелёк).
-- Набрали цену — доски падают, зал открыт: его камеры работают, туристы и воры идут к его экспонатам.
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

local function updateSign(door: Door)
	local sign = door.model:FindFirstChild(MapSchema.HallDoorSign, true)
	local gui = sign and sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = if door.paid > 0
			then ("%s\n$%d / $%d"):format(door.title, door.paid, door.price)
			else ("%s\n$%d"):format(door.title, door.price)
	end
	if door.prompt then
		door.prompt.ObjectText = Purchase.progressText(door.title, door.paid, door.price)
		Purchase.setProgress(door.prompt, door.paid, door.price)
	end
end

local function refreshPrompt(door: Door)
	if door.prompt then
		door.prompt.Enabled = dayActive and not GameState.isHallOpen(door.hall)
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
	task.delay(HallConfig.BoardsFallSeconds, function()
		if door.model.Parent then
			door.model.Parent = nil -- храним до нового забега (reset)
		end
	end)
end

-- Удержание F у двери: остаток цены, если хватает денег, иначе всё, что есть (Purchase.take).
local function contribute(door: Door, player: Player)
	if not dayActive or GameState.isHallOpen(door.hall) then
		return
	end
	local panel = door.model:FindFirstChild(MapSchema.HallDoorPanel)
	if not (panel and panel:IsA("BasePart")) then
		return
	end
	local amount = Purchase.take(player, panel, door.paid, door.price)
	if amount <= 0 then
		return
	end
	door.paid += amount
	updateSign(door)
	if door.paid >= door.price then
		openHall(door)
	end
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
end

return HallService
