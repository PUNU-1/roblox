-- Кнопка «Меню» на телефоне (этап 8, блок Q, решение 102): одна круглая кнопка ☰ слева сверху, рядом с кнопками
-- Roblox (ScreenInsets = TopbarSafeInsets — свободная часть верхней полосы Roblox). Нажал — под ней панель
-- пиксельных кнопок: всё, что на компьютере висит отдельными кнопками (SHOP, STATS, SETTINGS, SAY, CROUCH…;
-- в хабе — столбик кнопок слева). Нажал пункт — панель закрылась и пункт сработал. Нажал мимо — закрылась.
-- Пункты добавляют сами скрипты (MobileMenu.add), у пункта может быть условие «виден сейчас», «бледный»,
-- «красная точка» и своя подпись. Кнопка ☰ видна, только когда виден хоть один пункт.
-- Только на телефоне: на компьютере add ничего не делает.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelButton = require(script.Parent:WaitForChild("PixelButton"))
local PixelWindow = require(script.Parent:WaitForChild("PixelWindow"))
local Mobile = require(script.Parent:WaitForChild("Mobile"))

local Settings = Config.Mobile
local Colors = Theme.Colors

local MobileMenu = {}

export type ItemProps = {
	id: string,
	icon: string,
	label: string,
	order: number?,
	onActivated: () -> (),
	visible: (() -> boolean)?, -- нет — виден всегда
	dim: (() -> boolean)?, -- сейчас не работает (подпись серая), нажатие всё равно вызывается
	dot: (() -> boolean)?, -- красная точка (и на кнопке ☰)
	text: (() -> string)?, -- своя подпись сейчас (CROUCH / STAND)
}

type Item = {
	props: ItemProps,
	button: PixelButton.IconButton,
	shownText: string,
}

local items: { Item } = {}
local hidden = false

local ITEM_CELL = 3
local GAP = 6
local PAD = 6

---------------------------------------------------------------- экран

local built = false
local menuButton: Mobile.RoundButton
local buttonGui: ScreenGui
local panelGui: ScreenGui
local dismiss: TextButton
local panel: Frame
local grid: Frame
local panelScale: UIScale
local inset = 0
local openFlag = false

local function visibleItems(): { Item }
	local list = {}
	for _, item in items do
		local check = item.props.visible
		if check == nil or check() then
			table.insert(list, item)
		end
	end
	return list
end

local function setOpen(open: boolean)
	if open == openFlag then
		return
	end
	openFlag = open
	panelGui.Enabled = open
end

local function layoutPanel()
	local list = visibleItems()
	for _, item in items do
		item.button.root.Visible = false
	end
	local count = #list
	if count == 0 then
		setOpen(false)
		return
	end
	local columns = math.min(Settings.MenuColumns, count)
	local rows = math.ceil(count / columns)
	local itemH = list[1].button.height()
	for index, item in list do
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		item.button.root.Position = UDim2.fromOffset(column * (Settings.MenuItemWidth + GAP), row * (itemH + GAP))
		item.button.root.Visible = true
	end
	local gridW = columns * Settings.MenuItemWidth + (columns - 1) * GAP
	local gridH = rows * itemH + (rows - 1) * GAP
	grid.Size = UDim2.fromOffset(gridW, gridH)
	local width, height = gridW + 2 * (inset + PAD), gridH + 2 * (inset + PAD)
	panel.Size = UDim2.fromOffset(width, height)

	-- Под кнопкой ☰ (координаты — разницей AbsolutePosition), но не за краем экрана
	local s = Mobile.scale()
	panelScale.Scale = s
	local area = panelGui.AbsoluteSize
	local origin = panelGui.AbsolutePosition
	local buttonRoot = menuButton.root
	local x = buttonRoot.AbsolutePosition.X - origin.X
	local y = buttonRoot.AbsolutePosition.Y + buttonRoot.AbsoluteSize.Y + 4 - origin.Y
	local margin = Settings.Margin * s
	x = math.clamp(x, margin, math.max(margin, area.X - width * s - margin))
	y = math.clamp(y, margin, math.max(margin, area.Y - height * s - margin))
	panel.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

local function refreshItems()
	for _, item in items do
		local props = item.props
		local textFn = props.text
		local text = if textFn then textFn() else props.label
		if text ~= item.shownText then
			item.shownText = text
			item.button.setLabel(text)
		end
		local label = item.button.label
		if label then
			local dimFn = props.dim
			label.TextColor3 = if dimFn and dimFn() then Colors.Gray else Colors.White
		end
		local dotFn = props.dot
		item.button.setDot(dotFn ~= nil and dotFn())
	end
end

local function placeButton()
	-- В свободной части верхней полосы Roblox; если её нет (полоса скрыта) — слева сверху под ней
	local s = Mobile.scale()
	local size = math.floor(Settings.MenuSize * s)
	local root = menuButton.root
	root.Size = UDim2.fromOffset(size, size)
	local height = buttonGui.AbsoluteSize.Y
	-- AbsoluteSize = 0 — Roblox ещё не разложил экран, проверим при следующем изменении
	if buttonGui.ScreenInsets == Enum.ScreenInsets.TopbarSafeInsets and height > 0 and (height < 30 or height > 120) then
		buttonGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end
	if buttonGui.ScreenInsets == Enum.ScreenInsets.TopbarSafeInsets then
		root.AnchorPoint = Vector2.new(0, 0.5)
		root.Position = UDim2.new(0, math.floor(Settings.Margin * s), 0.5, 0)
	else
		root.AnchorPoint = Vector2.new(0, 0)
		root.Position = UDim2.fromOffset(math.floor(Settings.Margin * s), 62)
	end
end

local function build()
	if built then
		return
	end
	built = true
	-- Кнопка — под окнами (5) и магазином (4): открытое окно закрывает её своим затемнением
	buttonGui = Theme.screenGui("MobileMenu", 3, true)
	buttonGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	menuButton = Mobile.roundButton({
		name = "MenuButton",
		icon = "Menu",
		parent = buttonGui,
		onActivated = function()
			if openFlag then
				setOpen(false)
			else
				PixelWindow.closeAll()
				layoutPanel()
				refreshItems()
				setOpen(visibleItems()[1] ~= nil)
			end
		end,
	})
	menuButton.root.Visible = false
	placeButton()
	buttonGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeButton)
	Mobile.bind(placeButton)

	panelGui = Theme.screenGui("MobileMenuPanel", 4)
	panelGui.Enabled = false
	-- Нажал мимо панели — закрыть (на весь экран и за вырезом)
	dismiss = Theme.new("TextButton", {
		Name = "Dismiss",
		Position = UDim2.fromOffset(-100, -100),
		Size = UDim2.new(1, 200, 1, 200),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.6,
		AutoButtonColor = false,
		Text = "",
		Parent = panelGui,
	})
	dismiss.Activated:Connect(function()
		setOpen(false)
	end)
	panel = Theme.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(200, 100),
		BackgroundTransparency = 1,
		Active = true,
		ZIndex = 2,
		Parent = panelGui,
	})
	panelScale = Theme.new("UIScale", { Parent = panel })
	inset = PixelWindow.box(panel, Colors.Navy, Colors.Gold)
	grid = Theme.new("Frame", {
		Name = "Grid",
		Position = UDim2.fromOffset(inset + PAD, inset + PAD),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = panel,
	})

	-- Раз в 0.25 сек: видна ли кнопка ☰, точка на ней, подписи и пункты открытой панели
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		local list = visibleItems()
		local show = not hidden and #list > 0
		menuButton.setVisible(show)
		local anyDot = false
		for _, item in list do
			local dotFn = item.props.dot
			if dotFn and dotFn() then
				anyDot = true
			end
		end
		menuButton.setDot(anyDot)
		if openFlag then
			if not show or PixelWindow.anyOpen() then
				setOpen(false)
			else
				layoutPanel()
				refreshItems()
			end
		end
	end)
end

---------------------------------------------------------------- для скриптов

function MobileMenu.add(props: ItemProps)
	if not Mobile.enabled then
		return
	end
	build()
	local button = PixelButton.new({
		icon = props.icon,
		label = props.label,
		cell = ITEM_CELL,
		width = Settings.MenuItemWidth,
		name = "Menu" .. props.id,
		zIndex = 4,
		parent = grid,
		onActivated = function()
			setOpen(false)
			props.onActivated()
		end,
	})
	button.root.Visible = false
	table.insert(items, { props = props, button = button, shownText = props.label })
	table.sort(items, function(a, b)
		return (a.props.order or 100) < (b.props.order or 100)
	end)
	if openFlag then
		layoutPanel()
	end
end

-- Спрятать кнопку ☰ совсем (хаб: команда улетает в музей).
function MobileMenu.setHidden(value: boolean)
	hidden = value
	if built and value then
		menuButton.setVisible(false)
		setOpen(false)
	end
end

function MobileMenu.close()
	if built then
		setOpen(false)
	end
end

function MobileMenu.isOpen(): boolean
	return openFlag
end

-- Правый край кнопки ☰ внутри ScreenGui gui (чтобы ставить что-то правее неё) и низ верхней полосы.
function MobileMenu.buttonBottom(gui: ScreenGui): number
	if not built then
		return 62
	end
	local root = menuButton.root
	return root.AbsolutePosition.Y + root.AbsoluteSize.Y - gui.AbsolutePosition.Y
end

return MobileMenu
