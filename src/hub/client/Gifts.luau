-- Окно GIFTS в хабе (этап 5, блок A, решение 76): ежедневные подарки 7 дней подряд (Config.DailyGift.Rewards).
-- 7 клеток в ряд (DAY 1 … DAY 7): забранные — с галочкой, сегодняшняя светится. Кнопка CLAIM +15 или
-- «COME BACK IN 5H 12M». Забирает сервер (Remote ClaimGift → ProfileStore, внутри UpdateAsync), ответ — GiftResult.
-- Окно само не открывается: если подарок можно забрать, HubHUD рисует красную точку на кнопке GIFTS (canClaim).
-- В Studio без доступа к API — как алмазы: в памяти, надпись «Not saved in Studio».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus
local Rewards = Config.DailyGift.Rewards

local localPlayer = Players.LocalPlayer

local Gifts = {}

local CELL_W, CELL_H, GAP = 90, 134, 8

---------------------------------------------------------------- состояние подарка (по атрибутам профиля)

type State = {
	ready: boolean, -- профиль загружен (или Studio без API)
	canClaim: boolean,
	claimed: number, -- сколько клеток с галочкой
	today: number, -- какая клетка «сегодня» (1–7)
	secondsLeft: number, -- до следующего подарка, если сегодня уже забран
}

local function state(): State
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	local ready = status == ProfileStatus.Ready or status == ProfileStatus.Offline
	local now = Workspace:GetServerTimeNow()
	local day = GameState.dayNumber(now)
	local giftDay = tonumber(localPlayer:GetAttribute(PlayerAttr.GiftDay)) or 0
	local streak = tonumber(localPlayer:GetAttribute(PlayerAttr.GiftStreak)) or 0
	local can, nextStreak = GameState.giftNext(giftDay, streak, day)
	if can then
		return { ready = ready, canClaim = ready, claimed = nextStreak - 1, today = nextStreak, secondsLeft = 0 }
	end
	local left = (giftDay + 1) * Config.DailyGift.DaySeconds - now
	return { ready = ready, canClaim = false, claimed = streak, today = streak, secondsLeft = math.max(0, left) }
end

-- Можно ли сейчас забрать подарок (красная точка на кнопке GIFTS).
function Gifts.canClaim(): boolean
	return state().canClaim
end

---------------------------------------------------------------- окно

local window = PixelWindow.new({ name = "Gifts", title = "DAILY GIFTS", width = 760, height = 420 })
local content = window.content

Theme.pixelLabel({
	Name = "Hint",
	Position = UDim2.fromOffset(0, 2),
	Size = UDim2.new(1, 0, 0, 14),
	Text = "COME BACK EVERY DAY! MISS A DAY - START FROM DAY 1",
	TextColor3 = Colors.Marble,
	ZIndex = 3,
	Parent = content,
}, 8, 1)

type Cell = { frame: Frame, glow: Frame, check: Frame, title: TextLabel, reward: TextLabel, icon: Frame }
local cells: { Cell } = {}

local rowWidth = #Rewards * CELL_W + (#Rewards - 1) * GAP
local row = Theme.new("Frame", {
	Name = "Days",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 30),
	Size = UDim2.fromOffset(rowWidth, CELL_H),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = content,
})

for index, reward in Rewards do
	local big = index == #Rewards
	local frame = Theme.new("Frame", {
		Name = "Day" .. index,
		Position = UDim2.fromOffset((index - 1) * (CELL_W + GAP), 0),
		Size = UDim2.fromOffset(CELL_W, CELL_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = row,
	})
	-- Свечение сегодняшней клетки: золотая рамка чуть больше клетки, мигает
	local glow = Theme.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = -1, -- под рамкой клетки
		Parent = frame,
	})
	PixelIcon.box(glow, 3, { layers = { Color3.fromHex("FFE08A") }, zIndex = 0 })
	PixelWindow.box(frame, if big then Color3.fromHex("3A2A5A") else Colors.NavyLight, if big then Colors.Gold else Colors.Gray)
	local title = Theme.pixelLabel({
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 12),
		Text = "DAY " .. index,
		ZIndex = 4,
		Parent = frame,
	}, 12)
	local icon = PixelIcon.new(if big then "Gift" else "Diamond", true, 5)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 32)
	icon.Size = PixelIcon.size("Diamond", 3)
	icon.Parent = frame
	local rewardLabel = Theme.pixelLabel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "+" .. reward,
		TextColor3 = Colors.Diamond,
		ZIndex = 4,
		Parent = frame,
	}, 16)
	local check = PixelIcon.new("Check", true, 7)
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.new(0.5, 0, 0, 56)
	check.Size = PixelIcon.size("Check", 4)
	check.Visible = false
	check.Parent = frame
	table.insert(cells, { frame = frame, glow = glow, check = check, title = title, reward = rewardLabel, icon = icon })
end

local note = Theme.pixelLabel({
	Name = "Note",
	Position = UDim2.fromOffset(0, 30 + CELL_H + 14),
	Size = UDim2.new(1, 0, 0, 12),
	TextColor3 = Color3.fromHex("E8913A"),
	ZIndex = 3,
	Parent = content,
}, 8, 1)

local claimed: () -> ()
local claimButton = PixelButton.text({
	name = "Claim",
	text = "CLAIM",
	color = Colors.Green,
	textSize = 16,
	anchor = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 30 + CELL_H + 36),
	size = UDim2.fromOffset(360, 60),
	zIndex = 4,
	parent = content,
	onActivated = function()
		claimed()
	end,
})

local message = Theme.pixelLabel({
	Name = "Message",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.new(1, -20, 0, 14),
	TextColor3 = Colors.Marble,
	ZIndex = 3,
	Parent = content,
}, 12, 2)
local messageToken = 0
local function showMessage(text: string, color: Color3)
	messageToken += 1
	local token = messageToken
	message.Text = string.upper(text)
	message.TextColor3 = color
	task.delay(5, function()
		if messageToken == token then
			message.Text = ""
		end
	end)
end

local flash = Theme.new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.White,
	BackgroundTransparency = 1,
	ZIndex = 30,
	Parent = window.panel,
})
local purchaseSound = Instance.new("Sound")
purchaseSound.SoundId = Config.Sounds.Purchase
purchaseSound.Volume = Config.Sounds.PurchaseVolume
purchaseSound.Parent = window.gui
Theme.bindEffects(purchaseSound)

---------------------------------------------------------------- обновление

local waiting = false -- ждём ответа сервера

local function timeLeft(seconds: number): string
	local total = math.ceil(seconds)
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	if hours > 0 then
		return ("%dH %02dM"):format(hours, minutes)
	end
	return ("%dM %02dS"):format(minutes, total % 60)
end

local function refresh()
	local s = state()
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	for index, cell in cells do
		local done = index <= s.claimed
		local isToday = index == s.today
		cell.check.Visible = done
		cell.icon.Visible = not done
		cell.glow.Visible = isToday and not done
		cell.title.TextColor3 = if isToday then Colors.Gold else Colors.White
		cell.reward.TextTransparency = if done then 0.5 else 0
	end
	if waiting then
		claimButton.setText("CLAIMING...")
		claimButton.setColor(Colors.NavyLight)
		claimButton.setEnabled(false)
	elseif not s.ready then
		claimButton.setText(if status == ProfileStatus.Error then "GIFTS ARE UNAVAILABLE" else "LOADING...")
		claimButton.setColor(Colors.NavyLight)
		claimButton.setEnabled(false)
	elseif s.canClaim then
		claimButton.setText(("CLAIM +%d"):format(Rewards[s.today] or 0))
		claimButton.setColor(Colors.Green)
		claimButton.setEnabled(true)
	else
		claimButton.setText("COME BACK IN " .. timeLeft(s.secondsLeft))
		claimButton.setColor(Colors.Gray)
		claimButton.setEnabled(false)
	end
	note.Text = if status == ProfileStatus.Offline then "NOT SAVED IN STUDIO" else ""
end

function claimed()
	local s = state()
	if waiting or not s.canClaim then
		if s.ready and not s.canClaim then
			showMessage("Come back tomorrow for the next gift", Colors.Marble)
		end
		return
	end
	waiting = true
	refresh()
	Remotes.get(Remotes.Names.ClaimGift):FireServer()
	-- Сервер не ответил (сбой сети) — кнопку не держим вечно
	task.delay(15, function()
		if waiting then
			waiting = false
			refresh()
		end
	end)
end

Remotes.get(Remotes.Names.GiftResult).OnClientEvent:Connect(function(ok, reward, day, text)
	waiting = false
	if ok == true and typeof(reward) == "number" then
		flash.BackgroundTransparency = 0.3
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		SoundService:PlayLocalSound(purchaseSound)
		local cell = cells[tonumber(day) or 0]
		if cell then
			local scale = cell.frame:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", { Parent = cell.frame })
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		showMessage(("+%d diamonds!"):format(reward), Colors.Diamond)
	elseif typeof(text) == "string" then
		showMessage((string.gsub(text, " ?💎", "")), Colors.Red)
	end
	refresh()
end)

-- Пока окно открыто — отсчёт до следующего подарка и мигание сегодняшней клетки
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	if not window.isOpen() then
		return
	end
	local blink = (os.clock() % 0.8) < 0.5
	for _, cell in cells do
		cell.glow.BackgroundTransparency = 1
		local box = cell.glow:FindFirstChild("PixelBox")
		if box then
			for _, part in box:GetChildren() do
				if part:IsA("Frame") then
					part.BackgroundTransparency = if blink then 0 else 0.6
				end
			end
		end
	end
	accumulator += dt
	if accumulator >= 0.5 then
		accumulator = 0
		refresh()
	end
end)

for _, name in { PlayerAttr.GiftDay, PlayerAttr.GiftStreak, PlayerAttr.ProfileStatus } do
	localPlayer:GetAttributeChangedSignal(name):Connect(function()
		if window.isOpen() then
			refresh()
		end
	end)
end

function Gifts.open()
	refresh()
	window.open()
end

function Gifts.toggle()
	if window.isOpen() then
		window.close()
	else
		Gifts.open()
	end
end

Gifts.close = window.close
Gifts.isOpen = window.isOpen

return Gifts
