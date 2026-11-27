-- Окно QUESTS в хабе (этап 6, блок H1, решение 85): 3 ежедневных задания с полосками прогресса и наградой.
-- Задания выбирает, считает и сохраняет сервер (ProgressService → ProfileStore, день — по UTC, как у подарков);
-- окно только читает атрибут игрока Quests (JSON, Progress.decodeQuests). Выполненное — с галочкой, награда
-- уже начислена; незаконченные видны с полосками («2/6»). Новые задания — через «5H 12M».
-- Вкладки сверху: QUESTS и BADGES (достижения).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Progress = require(Shared:WaitForChild("Progress"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus

local localPlayer = Players.LocalPlayer

local Quests = {}

local WIDTH, HEIGHT = 760, 470
local TAB_H = 44
local ROW_H, ROW_GAP = 84, 10

local window = PixelWindow.new({ name = "Quests", title = "QUESTS", width = WIDTH, height = HEIGHT })
local content = window.content

---------------------------------------------------------------- вкладки

type Tab = { name: string, page: Frame, button: PixelButton.TextButtonObject, refresh: () -> () }
local tabs: { Tab } = {}
local current = 1

local function selectTab(index: number)
	current = index
	for i, tab in tabs do
		local on = i == index
		tab.page.Visible = on
		tab.button.setColor(if on then Colors.Gold else Colors.NavyLight, if on then Colors.Navy else Colors.White)
	end
	window.setTitle(tabs[index].name)
	tabs[index].refresh()
end

local function addTab(name: string, refresh: (page: Frame) -> ()): Frame
	local index = #tabs + 1
	local page = Theme.new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(0, TAB_H + 8),
		Size = UDim2.new(1, 0, 1, -TAB_H - 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = content,
	})
	local button = PixelButton.text({
		name = name .. "Tab",
		text = name,
		textSize = 12,
		color = Colors.NavyLight,
		position = UDim2.fromOffset((index - 1) * 186, 0),
		size = UDim2.fromOffset(176, TAB_H),
		zIndex = 4,
		parent = content,
		onActivated = function()
			selectTab(index)
		end,
	})
	table.insert(tabs, {
		name = name,
		page = page,
		button = button,
		refresh = function()
			refresh(page)
		end,
	})
	return page
end

---------------------------------------------------------------- вкладка QUESTS

local function timeLeft(seconds: number): string
	local total = math.ceil(seconds)
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	if hours > 0 then
		return ("%dH %02dM"):format(hours, minutes)
	end
	return ("%dM %02dS"):format(minutes, total % 60)
end

type Row = {
	frame: Frame,
	icon: Frame,
	check: Frame,
	text: TextLabel,
	fill: Frame,
	count: TextLabel,
	reward: TextLabel,
	gem: Frame,
}
local rows: { Row } = {}
local questHint: TextLabel
local questNote: TextLabel

local questPage = addTab("QUESTS", function()
	-- заполняется ниже (refreshQuests)
end)

questHint = Theme.pixelLabel({
	Name = "Hint",
	Size = UDim2.new(1, 0, 0, 14),
	TextColor3 = Colors.Marble,
	ZIndex = 3,
	Parent = questPage,
}, 8, 1)

for index = 1, Config.Quests.PerDay do
	local frame = Theme.new("Frame", {
		Name = "Quest" .. index,
		Position = UDim2.fromOffset(8, 24 + (index - 1) * (ROW_H + ROW_GAP)),
		Size = UDim2.new(1, -16, 0, ROW_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = questPage,
	})
	local inset = PixelWindow.box(frame, Colors.NavyLight, Colors.Gray)
	local icon = PixelIcon.new("Quests", true, 5)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, inset + 8, 0.5, 0)
	icon.Size = PixelIcon.size("Quests", 3)
	icon.Parent = frame
	local check = PixelIcon.new("Check", true, 6)
	check.AnchorPoint = Vector2.new(0, 0.5)
	check.Position = UDim2.new(0, inset + 8, 0.5, 0)
	check.Size = PixelIcon.size("Check", 3)
	check.Visible = false
	check.Parent = frame
	local left = inset + 8 + 48 + 14
	local text = Theme.pixelLabel({
		Position = UDim2.fromOffset(left, inset + 8),
		Size = UDim2.new(1, -left - 150, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 5,
		Parent = frame,
	}, 12, 2)
	local track = Theme.new("Frame", {
		Position = UDim2.fromOffset(left, inset + 36),
		Size = UDim2.new(1, -left - 150, 0, 16),
		BackgroundColor3 = Colors.Dark,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = frame,
	})
	local fill = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = track,
	})
	local count = Theme.pixelLabel({ Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = track }, 8, 1)
	local reward = Theme.pixelLabel({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -inset - 48, 0.5, 0),
		Size = UDim2.fromOffset(90, 20),
		TextColor3 = Colors.Diamond,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = frame,
	}, 16, 2)
	local gem = PixelIcon.new("Diamond", true, 5)
	gem.AnchorPoint = Vector2.new(1, 0.5)
	gem.Position = UDim2.new(1, -inset - 10, 0.5, 0)
	gem.Size = PixelIcon.size("Diamond", 2)
	gem.Parent = frame
	table.insert(rows, { frame = frame, icon = icon, check = check, text = text, fill = fill, count = count, reward = reward, gem = gem })
end

questNote = Theme.pixelLabel({
	Name = "Note",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -4),
	Size = UDim2.new(1, -20, 0, 12),
	TextColor3 = Colors.Marble,
	TextWrapped = true,
	ZIndex = 3,
	Parent = questPage,
}, 8, 1)

local function refreshQuests()
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	local ready = status == ProfileStatus.Ready or status == ProfileStatus.Offline
	local now = Workspace:GetServerTimeNow()
	local today = GameState.dayNumber(now)
	local day, list = Progress.decodeQuests(localPlayer:GetAttribute(PlayerAttr.Quests))
	local fresh = ready and day == today and #list > 0
	if not ready then
		questHint.Text = if status == ProfileStatus.Error then "QUESTS ARE UNAVAILABLE - TRYING AGAIN" else "LOADING..."
	elseif not fresh then
		questHint.Text = "NEW QUESTS ARE COMING..."
	else
		local left = (today + 1) * Config.DailyGift.DaySeconds - now
		questHint.Text = "NEW QUESTS IN " .. timeLeft(math.max(0, left)) .. " - PLAY IN THE MUSEUM TO FINISH THEM"
	end
	for index, row in rows do
		local quest = if fresh then list[index] else nil
		row.frame.Visible = quest ~= nil
		if quest then
			row.text.Text = Progress.questText(quest)
			row.text.TextColor3 = if quest.d then Colors.Green else Colors.White
			row.icon.Visible = not quest.d
			row.check.Visible = quest.d
			row.fill.Size = UDim2.fromScale(math.clamp(quest.p / math.max(1, quest.g), 0, 1), 1)
			row.fill.BackgroundColor3 = if quest.d then Colors.Green else Colors.Gold
			row.count.Text = if quest.d then "DONE!" else ("%d/%d"):format(quest.p, quest.g)
			row.reward.Text = "+" .. quest.r
			row.reward.TextTransparency = if quest.d then 0.5 else 0
		end
	end
	questNote.Text = if status == ProfileStatus.Offline then "NOT SAVED IN STUDIO" else "REWARDS ARE ADDED AT ONCE WHEN A QUEST IS DONE"
end
tabs[1].refresh = refreshQuests

---------------------------------------------------------------- вкладка BADGES

-- 9 достижений сеткой 3 × 3: медаль (серая, пока не получено), название, условие и «3/5» или DONE.
-- Счётчики — атрибут Stats (JSON, Progress.decodeStats). Значок Roblox выдаёт сервер, если владелец вписал номер.
local BADGE_COLUMNS, BADGE_GAP, BADGE_H = 3, 10, 98

type BadgeCard = { id: string, frame: Frame, icon: Frame, lockIcon: Frame, title: TextLabel, count: TextLabel }
local badgeCards: { BadgeCard } = {}
local badgeHint: TextLabel

local badgePage = addTab("BADGES", function() end)

badgeHint = Theme.pixelLabel({
	Name = "Hint",
	Size = UDim2.new(1, 0, 0, 14),
	TextColor3 = Colors.Marble,
	ZIndex = 3,
	Parent = badgePage,
}, 8, 1)

for index, id in Config.Badges.Order do
	local info = (Config.Badges :: any)[id]
	local column = (index - 1) % BADGE_COLUMNS
	local row = (index - 1) // BADGE_COLUMNS
	local frame = Theme.new("Frame", {
		Name = id,
		Position = UDim2.new(column / BADGE_COLUMNS, 4 + column * 2, 0, 22 + row * (BADGE_H + BADGE_GAP)),
		Size = UDim2.new(1 / BADGE_COLUMNS, -BADGE_GAP, 0, BADGE_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = badgePage,
	})
	local inset = PixelWindow.box(frame, Colors.NavyLight, Colors.Gray)
	local icon = PixelIcon.new("Medal", true, 5)
	icon.Position = UDim2.fromOffset(inset + 6, inset + 8)
	icon.Size = PixelIcon.size("Medal", 2)
	icon.Parent = frame
	-- Не получено — та же медаль тёмным силуэтом
	local lockIcon = PixelIcon.new({ rows = PixelIcon.Icons.Medal.rows, palette = { K = "141420", r = "3A3F4E", b = "3A3F4E", y = "4A5063", Y = "566078", d = "3A3F4E" } }, false, 5)
	lockIcon.Position = icon.Position
	lockIcon.Size = icon.Size
	lockIcon.Parent = frame
	local left = inset + 6 + 32 + 8
	local title = Theme.pixelLabel({
		Position = UDim2.fromOffset(left, inset + 8),
		Size = UDim2.new(1, -left - inset - 4, 0, 10),
		Text = tostring(info.Title),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, 8, 1)
	Theme.pixelLabel({
		Position = UDim2.fromOffset(left, inset + 24),
		Size = UDim2.new(1, -left - inset - 4, 0, 30),
		Text = string.upper(tostring(info.Text)),
		TextColor3 = Colors.Marble,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
		Parent = frame,
	}, 8, 1)
	local count = Theme.pixelLabel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, left, 1, -inset - 6),
		Size = UDim2.new(1, -left - inset - 4, 0, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, 8, 1)
	table.insert(badgeCards, { id = id, frame = frame, icon = icon, lockIcon = lockIcon, title = title, count = count })
end

local function refreshBadges()
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	local ready = status == ProfileStatus.Ready or status == ProfileStatus.Offline
	local data = Progress.decodeStats(localPlayer:GetAttribute(PlayerAttr.Stats))
	local earned = 0
	for _, card in badgeCards do
		local done = ready and data.badges[card.id] == true
		if done then
			earned += 1
		end
		local have, goal = Progress.badgeProgress(card.id, data)
		card.icon.Visible = done
		card.lockIcon.Visible = not done
		card.title.TextColor3 = if done then Colors.Gold else Colors.White
		card.count.Text = if done then "DONE!" elseif ready then ("%d/%d"):format(have, goal) else "..."
		card.count.TextColor3 = if done then Colors.Green else Colors.Diamond
	end
	if not ready then
		badgeHint.Text = if status == ProfileStatus.Error then "BADGES ARE UNAVAILABLE - TRYING AGAIN" else "LOADING..."
	else
		badgeHint.Text = ("BADGES %d/%d"):format(earned, #badgeCards)
			.. (if status == ProfileStatus.Offline then " - NOT SAVED IN STUDIO" else "")
	end
end
tabs[#tabs].refresh = refreshBadges

---------------------------------------------------------------- обновление

local function refreshCurrent()
	local tab = tabs[current]
	if tab and window.isOpen() then
		tab.refresh()
	end
end

for _, name in { PlayerAttr.Quests, PlayerAttr.Stats, PlayerAttr.ProfileStatus } do
	localPlayer:GetAttributeChangedSignal(name):Connect(refreshCurrent)
end

-- Пока окно открыто — отсчёт до новых заданий
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	if not window.isOpen() then
		return
	end
	accumulator += dt
	if accumulator >= 1 then
		accumulator = 0
		refreshCurrent()
	end
end)

function Quests.open(tabIndex: number?)
	window.open()
	selectTab(tabIndex or 1)
end

function Quests.toggle()
	if window.isOpen() then
		window.close()
	else
		Quests.open(current)
	end
end

Quests.close = window.close
Quests.isOpen = window.isOpen

return Quests
