--!strict
-- Таблица статистики команды (этап 6, блок I2):
--   • ПК: держи L — таблица открыта, отпустил — закрылась (в чате и во время GAME OVER не мешает);
--   • Телефон (и клик): пиксельная кнопка STATS рядом с SHOP открывает и закрывает таблицу.
-- Показывает всех игроков на смене (InRound == true): ник, класс, аресты (ночь / забег),
-- деньги, поднятия товарищей и уровень со званием. Своя строка выделена цветом; пока окно открыто,
-- обновляется каждые Config.Stats.RefreshSeconds секунд.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Progress = require(Shared:WaitForChild("Progress"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))
local MobileMenu = require(UI:WaitForChild("MobileMenu"))

local Settings = Config.Stats
local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

local ROW_INSET = 9 -- толщина 3-слойной рамки (PixelIcon.box с cell = 3)
local COL_PAD = 6

type ColumnDef = {
	title: string,
	x: number,
	w: number,
	align: Enum.TextXAlignment,
}

local COLUMNS: { ColumnDef } = {
	{ title = "GUARD", x = 0.00, w = 0.25, align = Enum.TextXAlignment.Left },
	{ title = "CLASS", x = 0.25, w = 0.19, align = Enum.TextXAlignment.Left },
	{ title = "ARRESTS", x = 0.44, w = 0.15, align = Enum.TextXAlignment.Center },
	{ title = "MONEY", x = 0.59, w = 0.13, align = Enum.TextXAlignment.Center },
	{ title = "REVIVES", x = 0.72, w = 0.13, align = Enum.TextXAlignment.Center },
	{ title = "LEVEL", x = 0.85, w = 0.15, align = Enum.TextXAlignment.Center },
}

---------------------------------------------------------------- окно и кнопка

local holdOpen = false
local toggleOpen = false
local refresh: () -> ()
local window: PixelWindow.Window

window = PixelWindow.new({
	name = "Stats",
	title = "TEAM STATS",
	width = Settings.WindowWidth,
	height = Settings.WindowHeight,
	displayOrder = 4,
	onOpen = function()
		if refresh then
			refresh()
		end
	end,
	onClose = function()
		holdOpen = false
		toggleOpen = false
		local closeBtn = window.panel:FindFirstChild("Close")
		if closeBtn and closeBtn:IsA("TextButton") then
			closeBtn.Modal = false
		end
	end,
})

local buttonGui: ScreenGui = Theme.screenGui("StatsHud", 5)
local onStatsButton: () -> ()
local statsButton = PixelButton.new({
	icon = "Stats",
	label = "STATS",
	key = "L",
	cell = Config.PixelUI.HudCell,
	name = "StatsButton",
	parent = buttonGui,
	onActivated = function()
		onStatsButton()
	end,
})
statsButton.root.AnchorPoint = Vector2.new(1, 0)
statsButton.root.Position = UDim2.new(1, -(12 + statsButton.width() + Settings.ButtonGap), 0, 62)
statsButton.root.Visible = false
if touchOnly then
	-- Телефон (этап 8, блок Q): STATS — в «Меню»; видна ли — по statsButton.root.Visible, сама кнопка не на экране
	statsButton.root.Parent = nil
	MobileMenu.add({
		id = "Stats",
		icon = "Stats",
		label = "STATS",
		order = 2,
		visible = function()
			return statsButton.root.Visible
		end,
		onActivated = function()
			onStatsButton()
		end,
	})
end

---------------------------------------------------------------- таблица внутри окна

local content = window.content

-- Заголовки столбцов (отступ совпадает с внутренностью карточек строк)
local headerRow = Theme.new("Frame", {
	Name = "Headers",
	Position = UDim2.fromOffset(8 + ROW_INSET, 2),
	Size = UDim2.new(1, -2 * (8 + ROW_INSET), 0, 22),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = content,
})
for _, col in COLUMNS do
	Theme.pixelLabel({
		Name = col.title,
		Position = UDim2.new(col.x, COL_PAD, 0, 0),
		Size = UDim2.new(col.w, -2 * COL_PAD, 1, 0),
		Text = col.title,
		TextColor3 = Colors.Marble,
		TextXAlignment = col.align,
		ZIndex = 3,
		Parent = headerRow,
	}, 8, 1)
end

local listFrame: ScrollingFrame = Theme.new("ScrollingFrame", {
	Name = "Rows",
	Position = UDim2.fromOffset(8, 28),
	Size = UDim2.new(1, -16, 1, -54),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Colors.Gold,
	ZIndex = 3,
	Parent = content,
})
Theme.new("UIListLayout", {
	Padding = UDim.new(0, Settings.RowGap),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = listFrame,
})

local emptyLabel: TextLabel = Theme.pixelLabel({
	Name = "Empty",
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -54),
	Text = "NO GUARDS ON SHIFT",
	TextColor3 = Colors.Gray,
	Visible = false,
	ZIndex = 4,
	Parent = content,
}, 12, 2)

Theme.pixelLabel({
	Name = "Footer",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 8, 1, -2),
	Size = UDim2.new(1, -16, 0, 18),
	Text = if touchOnly then "Night / Run arrests   |   Tap X or STATS to close" else "Hold L to view   |   Night / Run arrests",
	TextColor3 = Colors.Gray,
	ZIndex = 3,
	Parent = content,
}, 8, 1)

---------------------------------------------------------------- строки игроков (пул)

type RowView = {
	frame: Frame,
	box: Frame,
	nameLabel: TextLabel,
	classLabel: TextLabel,
	arrestsLabel: TextLabel,
	moneyLabel: TextLabel,
	revivesLabel: TextLabel,
	levelLabel: TextLabel,
	rankLabel: TextLabel,
}
local rowViews: { RowView } = {}

local function cellLabel(parent: Frame, col: ColumnDef, size: number, color: Color3): TextLabel
	return Theme.pixelLabel({
		Position = UDim2.new(col.x, COL_PAD, 0, 0),
		Size = UDim2.new(col.w, -2 * COL_PAD, 1, 0),
		TextColor3 = color,
		TextXAlignment = col.align,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
		Parent = parent,
	}, size, 1)
end

local function ensureRow(index: number): RowView
	local existing = rowViews[index]
	if existing then
		return existing
	end
	local frame = Theme.new("Frame", {
		Name = "Guard" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, Settings.RowHeight),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = listFrame,
	})
	local box, inset = PixelIcon.box(frame, 3, {
		layers = { PixelIcon.Outline, Colors.Gray, Colors.Navy },
		shadow = true,
	})
	local inner = Theme.new("Frame", {
		Name = "Inner",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = frame,
	})
	local nameLabel = cellLabel(inner, COLUMNS[1], 10, Colors.White)
	local classLabel = cellLabel(inner, COLUMNS[2], 10, Colors.Marble)
	local arrestsLabel = cellLabel(inner, COLUMNS[3], 10, Colors.White)
	local moneyLabel = cellLabel(inner, COLUMNS[4], 10, Colors.Gold)
	local revivesLabel = cellLabel(inner, COLUMNS[5], 10, Colors.Green)

	local lvlCol = COLUMNS[6]
	local levelLabel = Theme.pixelLabel({
		Position = UDim2.new(lvlCol.x, COL_PAD, 0, 2),
		Size = UDim2.new(lvlCol.w, -2 * COL_PAD, 0, 14),
		TextColor3 = Colors.White,
		TextXAlignment = lvlCol.align,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
		Parent = inner,
	}, 10, 1)
	local rankLabel = Theme.pixelLabel({
		Position = UDim2.new(lvlCol.x, COL_PAD, 0, 19),
		Size = UDim2.new(lvlCol.w, -2 * COL_PAD, 0, 12),
		TextColor3 = Colors.Gray,
		TextXAlignment = lvlCol.align,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
		Parent = inner,
	}, 8, 1)

	local view: RowView = {
		frame = frame,
		box = box,
		nameLabel = nameLabel,
		classLabel = classLabel,
		arrestsLabel = arrestsLabel,
		moneyLabel = moneyLabel,
		revivesLabel = revivesLabel,
		levelLabel = levelLabel,
		rankLabel = rankLabel,
	}
	rowViews[index] = view
	return view
end

local function attrNum(player: Player, name: string): number
	return math.floor(tonumber(player:GetAttribute(name)) or 0)
end

refresh = function()
	local night = math.max(1, tonumber(GameState.get(Attr.NightNumber)) or 1)
	window.setTitle(("TEAM STATS - NIGHT %d"):format(night))

	local team: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(PlayerAttr.InRound) == true then
			table.insert(team, player)
		end
	end
	table.sort(team, function(a: Player, b: Player): boolean
		local aRun, bRun = attrNum(a, PlayerAttr.RunArrests), attrNum(b, PlayerAttr.RunArrests)
		if aRun ~= bRun then
			return aRun > bRun
		end
		local aNight, bNight = attrNum(a, PlayerAttr.NightArrests), attrNum(b, PlayerAttr.NightArrests)
		if aNight ~= bNight then
			return aNight > bNight
		end
		local aRev, bRev = attrNum(a, PlayerAttr.RunRevives), attrNum(b, PlayerAttr.RunRevives)
		if aRev ~= bRev then
			return aRev > bRev
		end
		local aMoney, bMoney = attrNum(a, PlayerAttr.Money), attrNum(b, PlayerAttr.Money)
		if aMoney ~= bMoney then
			return aMoney > bMoney
		end
		return a.UserId < b.UserId
	end)

	emptyLabel.Visible = #team == 0
	for index, player in team do
		local view = ensureRow(index)
		view.frame.Visible = true
		local isSelf = player == localPlayer
		PixelIcon.recolor(view.box, 2, if isSelf then Colors.Gold else Colors.Gray)
		PixelIcon.recolor(view.box, 3, if isSelf then Colors.NavyLight else Colors.Navy)

		view.nameLabel.Text = if isSelf then player.DisplayName .. " (YOU)" else player.DisplayName
		view.nameLabel.TextColor3 = if isSelf then Colors.Gold else Colors.White

		local role = GameState.roleOf(player)
		local info = GameState.classInfo(role)
		view.classLabel.Text = string.upper(if info then tostring(info.Title) else role)
		view.classLabel.TextColor3 = if info and typeof(info.Color) == "Color3" then info.Color else Colors.Marble

		local nightArrests = attrNum(player, PlayerAttr.NightArrests)
		local runArrests = attrNum(player, PlayerAttr.RunArrests)
		view.arrestsLabel.Text = ("%d / %d"):format(nightArrests, runArrests)

		view.moneyLabel.Text = ("$%d"):format(attrNum(player, PlayerAttr.Money))
		view.revivesLabel.Text = tostring(attrNum(player, PlayerAttr.RunRevives))

		local level = math.max(1, attrNum(player, PlayerAttr.Level))
		local rank = Progress.rankOf(level)
		view.levelLabel.Text = ("LV %d"):format(level)
		view.rankLabel.Text = rank.Name
		view.rankLabel.TextColor3 = rank.Color
	end

	for index = #team + 1, #rowViews do
		rowViews[index].frame.Visible = false
	end
end

---------------------------------------------------------------- управление (L и кнопка STATS)

local function canOpenNow(): boolean
	local phase = GameState.phase()
	if phase ~= Phase.Day and phase ~= Phase.Night then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.ShopOpen) == true then
		return false
	end
	return true
end

local function setCloseModal(freeCursor: boolean)
	local closeBtn = window.panel:FindFirstChild("Close")
	if closeBtn and closeBtn:IsA("TextButton") then
		closeBtn.Modal = freeCursor
	end
end

local function openForHold()
	if not canOpenNow() then
		return
	end
	holdOpen = true
	toggleOpen = false
	setCloseModal(false)
	window.open()
end

onStatsButton = function()
	if window.isOpen() then
		window.close()
		return
	end
	if not canOpenNow() then
		return
	end
	toggleOpen = true
	holdOpen = false
	setCloseModal(true)
	window.open()
end

local function updateButtonState()
	local allowed = canOpenNow()
	statsButton.root.Visible = allowed
	if allowed then
		local onShift = localPlayer:GetAttribute(PlayerAttr.InRound) == true
		local rightOffset = if onShift then 12 + statsButton.width() + Settings.ButtonGap else 12
		statsButton.root.Position = UDim2.new(1, -rightOffset, 0, 62)
	elseif window.isOpen() then
		window.close()
	end
end

---------------------------------------------------------------- события и очистка

local connections: { RBXScriptConnection } = {}
local function track(conn: RBXScriptConnection)
	table.insert(connections, conn)
end

track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if input.KeyCode == Settings.Key then
		openForHold()
	end
end))

track(UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Settings.Key and holdOpen then
		holdOpen = false
		if not toggleOpen then
			window.close()
		end
	end
end))

track(UserInputService.WindowFocusReleased:Connect(function()
	if holdOpen then
		holdOpen = false
		if not toggleOpen then
			window.close()
		end
	end
end))

track(GameState.folder():GetAttributeChangedSignal(Attr.Phase):Connect(updateButtonState))
track(localPlayer:GetAttributeChangedSignal(PlayerAttr.InRound):Connect(updateButtonState))
track(localPlayer:GetAttributeChangedSignal(PlayerAttr.ViewingCameras):Connect(updateButtonState))
track(localPlayer:GetAttributeChangedSignal(PlayerAttr.ShopOpen):Connect(updateButtonState))

local refreshTimer = 0
track(RunService.Heartbeat:Connect(function(dt: number)
	if not window.isOpen() then
		refreshTimer = 0
		return
	end
	refreshTimer += dt
	if refreshTimer >= Settings.RefreshSeconds then
		refreshTimer = 0
		refresh()
	end
end))

track(script.Destroying:Connect(function()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	window.close()
	if window.gui.Parent then
		window.gui:Destroy()
	end
	if buttonGui.Parent then
		buttonGui:Destroy()
	end
end))

updateButtonState()
