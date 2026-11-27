-- Окно COLLECTION в хабе (этап 6, блок H2, решение 86): карточки всех видов воров (с Фальшивым охранником),
-- 18 экспонатов и Моны Лизы. Вор открывается, когда игрок его арестовал; экспонат — когда вложил деньги в его
-- покупку; Мона Лиза — после первой пережитой ночи. Закрытые карточки — серый силуэт и «?».
-- Собрал всех воров или все экспонаты — алмазы (Config.Collection), их выдаёт сервер по сохранённым данным.
-- Окно только читает атрибут игрока Stats (JSON, Progress.decodeStats), пишет его сервер (ProfileStore).
-- Вкладки сверху: THIEVES и EXHIBITS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local Collection = {}

local WIDTH, HEIGHT = 760, 470
local TAB_H = 44
local GAP = 8

-- Силуэт закрытой карточки: все цвета иконки — тёмно-серые
local SILHOUETTE = "3A3F4E"
-- Цвет экспоната на иконке по залу (порядок Config.Exhibits.Slots: 2 в центре, по 4 в залах)
local HALL_COLORS = {
	{ count = 2, color = "F2C14E" }, -- центр: золото
	{ count = 4, color = "D9D2C3" }, -- скульптуры: мрамор
	{ count = 4, color = "C9B58A" }, -- динозавры: кость
	{ count = 4, color = "B07CFF" }, -- драгоценности
	{ count = 4, color = "6FA8FF" }, -- космос
}

local window = PixelWindow.new({ name = "Collection", title = "COLLECTION", width = WIDTH, height = HEIGHT })
local content = window.content

---------------------------------------------------------------- вкладки

type Card = { key: string, open: Frame, closed: Frame, title: TextLabel, note: TextLabel, question: TextLabel }
type Tab = { name: string, page: Frame, button: PixelButton.TextButtonObject, hint: TextLabel, cards: { Card } }
local tabs: { Tab } = {}
local current = 1

local function recolor(icon: PixelIcon.Icon, colors: { [string]: string }): PixelIcon.Icon
	local palette = table.clone(icon.palette)
	for letter, color in colors do
		palette[letter] = color
	end
	return { rows = icon.rows, palette = palette }
end

local function silhouette(icon: PixelIcon.Icon): PixelIcon.Icon
	local palette = {}
	for letter in icon.palette do
		palette[letter] = SILHOUETTE
	end
	palette.K = "141420"
	return { rows = icon.rows, palette = palette }
end

local refreshCurrent: () -> ()

local function selectTab(index: number)
	current = index
	for i, tab in tabs do
		local on = i == index
		tab.page.Visible = on
		tab.button.setColor(if on then Colors.Gold else Colors.NavyLight, if on then Colors.Navy else Colors.White)
	end
	refreshCurrent()
end

-- Вкладка с сеткой карточек. items — { key, icon (открытая), note (подсказка у закрытой) }.
local function addTab(name: string, columns: number, cardHeight: number, cell: number, items: { { key: string, icon: PixelIcon.Icon, note: string } })
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
	local hint = Theme.pixelLabel({
		Name = "Hint",
		Size = UDim2.new(1, 0, 0, 14),
		TextColor3 = Colors.Marble,
		ZIndex = 3,
		Parent = page,
	}, 8, 1)
	local cards: { Card } = {}
	for i, item in items do
		local column = (i - 1) % columns
		local row = (i - 1) // columns
		local frame = Theme.new("Frame", {
			Name = item.key,
			Position = UDim2.new(column / columns, GAP // 2, 0, 22 + row * (cardHeight + GAP)),
			Size = UDim2.new(1 / columns, -GAP, 0, cardHeight),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = page,
		})
		local inset = PixelWindow.box(frame, Colors.NavyLight, Colors.Gray)
		local iconSize = PixelIcon.size(item.icon, cell)
		local open = PixelIcon.new(item.icon, true, 5)
		open.AnchorPoint = Vector2.new(0.5, 0)
		open.Position = UDim2.new(0.5, 0, 0, inset + 4)
		open.Size = iconSize
		open.Parent = frame
		local closed = PixelIcon.new(silhouette(item.icon), false, 5)
		closed.AnchorPoint = open.AnchorPoint
		closed.Position = open.Position
		closed.Size = iconSize
		closed.Parent = frame
		local question = Theme.pixelLabel({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = open.Position,
			Size = iconSize,
			Text = "?",
			TextColor3 = Colors.Gray,
			ZIndex = 8,
			Parent = frame,
		}, if cell >= 4 then 32 else 24, 2)
		local top = inset + 4 + iconSize.Y.Offset + 4
		local title = Theme.pixelLabel({
			Position = UDim2.fromOffset(inset + 2, top),
			Size = UDim2.new(1, -2 * inset - 4, 0, 18),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 5,
			Parent = frame,
		}, 8, 1)
		local note = Theme.pixelLabel({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, inset + 2, 1, -inset - 2),
			Size = UDim2.new(1, -2 * inset - 4, 0, 8),
			TextColor3 = Colors.Gray,
			Text = item.note,
			ZIndex = 5,
			Parent = frame,
		}, 8, 1)
		table.insert(cards, { key = item.key, open = open, closed = closed, title = title, note = note, question = question })
	end
	table.insert(tabs, { name = name, page = page, button = button, hint = hint, cards = cards })
end

---------------------------------------------------------------- карточки

local thiefItems = {}
for _, kind in Config.Collection.Thieves do
	local info = (Config.ThiefTypes :: any)[kind]
	-- Чуть светлее цвета вида: чёрный карманник иначе сливается с контуром
	local color = if info and typeof(info.Color) == "Color3" then (info.Color :: Color3):Lerp(Color3.new(1, 1, 1), 0.2):ToHex() else "4A4A5A"
	-- Фальшивый охранник — в форме охраны (тёмно-синяя), остальные — цвета своего вида
	if kind == "FakeGuard" then
		color = "22305A"
	end
	local fromNight = if kind == "FakeGuard" then Config.Plans.FakeGuard.FromNight else (if info then info.FromNight else 1)
	table.insert(thiefItems, {
		key = kind,
		icon = recolor(PixelIcon.Icons.Thief, { d = color, c = color }),
		note = ("NIGHT %d+"):format(tonumber(fromNight) or 1),
	})
end
addTab("THIEVES", 4, 140, 4, thiefItems)

local exhibitItems = {}
do
	local slot = 0
	for _, group in HALL_COLORS do
		for _ = 1, group.count do
			slot += 1
			local key = Config.Exhibits.Slots[slot]
			if key then
				table.insert(exhibitItems, { key = key, icon = recolor(PixelIcon.Icons.Exhibit, { v = group.color }), note = "" })
			end
		end
	end
	table.insert(exhibitItems, { key = Config.Collection.MonaLisa, icon = PixelIcon.Icons.Painting, note = "" })
end
addTab("EXHIBITS", 7, 98, 3, exhibitItems)

---------------------------------------------------------------- обновление

refreshCurrent = function()
	local tab = tabs[current]
	if not (tab and window.isOpen()) then
		return
	end
	local status = localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
	local ready = status == ProfileStatus.Ready or status == ProfileStatus.Offline
	local data = Progress.decodeStats(localPlayer:GetAttribute(PlayerAttr.Stats))
	local isThieves = current == 1
	local opened = 0
	for _, card in tab.cards do
		local isOpen = ready and (if isThieves then data.kinds[card.key] == true else data.exhibits[card.key] == true)
		if isOpen then
			opened += 1
		end
		card.open.Visible = isOpen
		card.closed.Visible = not isOpen
		card.question.Visible = not isOpen
		card.title.Text = if isOpen then Progress.cardTitle((if isThieves then "Thief:" else "Exhibit:") .. card.key) else "???"
		card.title.TextColor3 = if isOpen then Colors.Gold else Colors.Gray
		if isThieves then
			card.note.Visible = not isOpen -- «NIGHT 3+» — с какой ночи приходит
		end
	end
	if not ready then
		tab.hint.Text = if status == ProfileStatus.Error then "COLLECTION IS UNAVAILABLE - TRYING AGAIN" else "LOADING..."
		return
	end
	local total = #tab.cards
	local reward = if isThieves then Config.Collection.ThievesDiamonds else Config.Collection.ExhibitsDiamonds
	local how = if isThieves then "ARREST A THIEF TO ADD IT" else "HELP BUY AN EXHIBIT IN THE MUSEUM TO ADD IT"
	local paid = if isThieves then data.colPaid.thieves == true else data.colPaid.exhibits == true
	if opened >= total or paid then
		tab.hint.Text = ("%s %d/%d - COMPLETE! +%d DIAMONDS RECEIVED"):format(tab.name, opened, total, reward)
	else
		tab.hint.Text = ("%s %d/%d - %s - ALL OF THEM: +%d DIAMONDS"):format(tab.name, opened, total, how, reward)
	end
	if status == ProfileStatus.Offline then
		tab.hint.Text ..= " (NOT SAVED IN STUDIO)"
	end
end

for _, name in { PlayerAttr.Stats, PlayerAttr.ProfileStatus } do
	localPlayer:GetAttributeChangedSignal(name):Connect(refreshCurrent)
end

function Collection.open(tabIndex: number?)
	window.open()
	selectTab(tabIndex or current)
end

function Collection.toggle()
	if window.isOpen() then
		window.close()
	else
		Collection.open(current)
	end
end

Collection.close = window.close
Collection.isOpen = window.isOpen

return Collection
