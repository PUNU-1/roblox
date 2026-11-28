-- Окно магазина в музее (этап 4, блок 1b): днём клавиша B, кнопка SHOP под деньгами или касса SHOP у Моны Лизы.
-- Вкладки Exhibits, Halls, Security, Weapons, Gear. Карточка товара: крутящаяся 3D-картинка (модель Preview, её
-- кладёт сервер), название, строка описания, цена и кнопка BUY $X / PUT IN $X / NEED $X / OWNED / HALL CLOSED / WING CLOSED.
-- Товары и их состояние сервер кладёт в ReplicatedStorage.Shop (ShopService), окно только читает и шлёт намерение
-- ShopBuy(category, id); всё решает сервер (те же правила, что у кнопок F). Ответ — ShopReply: «Bought: Golden Vase».
-- Пока окно открыто, курсор свободен (Modal). Закрыть — B, Esc (меню Roblox) или крестик. Ночью окно закрыто.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Mobile = require(UI:WaitForChild("Mobile"))
local ClassCards = require(UI:WaitForChild("ClassCards"))
local PixelButton = require(UI:WaitForChild("PixelButton"))

local Colors = Theme.Colors
local Phase = GameState.Phase
local PlayerAttr = GameState.PlayerAttr
local ShopAttr = GameState.ShopAttr
local ShopReply = GameState.ShopReply
local ShopConfig = Config.Shop

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

-- На телефоне (этап 8, блок Q) окно ниже: карточки и так прокручиваются, а низкое окно меньше уменьшается по высоте
local PANEL_W, PANEL_H = 960, if touchOnly then 440 else 640
local CARD_W, CARD_H, GAP = 168, 236, 12
local GRID_TOP = 152

-- Вкладки: подпись, цвет и строка под заголовком
local TAB_LOOK: { [string]: { title: string, color: Color3, sub: string } } = {
	Exhibits = { title = "EXHIBITS", color = Colors.Gold, sub = "Exhibits bring more tourists — and more money every day" },
	Halls = { title = "HALLS", color = Colors.Marble, sub = "A wing moves its entrance farther and brings tourists. A hall opens from its wing" },
	Security = { title = "SECURITY", color = Colors.Turquoise, sub = "Laser grids slow thieves down, cameras show where they are" },
	Weapons = { title = "WEAPONS", color = Colors.Red, sub = "Personal: every guard buys their own. Firearms work only during a raid" },
	Gear = { title = "GEAR", color = Colors.Green, sub = "Personal: every guard buys their own" },
}
local SHARED_SUB = "Money comes from tourists. Shared items (halls, exhibits, cameras) can be paid together"

local function money(): number
	return math.floor(tonumber(localPlayer:GetAttribute(PlayerAttr.Money)) or 0)
end

---------------------------------------------------------------- кнопка SHOP, подсказка, «Bought: …»

local gui = Theme.screenGui("Shop", 4)

-- Под деньгами справа вверху (на телефоне тоже). Пиксельная, без рамки и фона, как кнопки хаба (этап 5, блок D).
local toggle: () -> ()
local shopButton = PixelButton.new({
	icon = "Shop",
	label = "SHOP",
	key = "B",
	cell = Config.PixelUI.HudCell,
	name = "ShopButton",
	parent = gui,
	onActivated = function()
		toggle()
	end,
})
shopButton.root.AnchorPoint = Vector2.new(1, 0)
shopButton.root.Position = UDim2.new(1, -12, 0, 62)
shopButton.root.Visible = false

-- Короткая надпись внизу экрана: «Shop opens in the morning»
local toast = Theme.label({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -72),
	Size = UDim2.new(0.6, 0, 0, 34),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 22,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = toast })
local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(ShopConfig.PopupSeconds, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

-- «Bought: Golden Vase» — над окном, видна и после закрытия
local popup = Theme.label({
	Name = "Popup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.2),
	Size = UDim2.new(0.8, 0, 0, 64),
	TextColor3 = Colors.Gold,
	MaxTextSize = 52,
	Visible = false,
	ZIndex = 40,
	Parent = gui,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = popup })
local popupToken = 0
local function showPopup(text: string, color: Color3)
	popupToken += 1
	local token = popupToken
	popup.Text = text
	popup.TextColor3 = color
	popup.Visible = true
	popup.Size = UDim2.new(0.8, 0, 0, 36)
	TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.8, 0, 0, 64) }):Play()
	task.delay(ShopConfig.PopupSeconds, function()
		if popupToken == token then
			popup.Visible = false
		end
	end)
end

local purchaseSound = Instance.new("Sound")
purchaseSound.SoundId = Config.Sounds.Purchase
purchaseSound.Volume = Config.Sounds.PurchaseVolume
purchaseSound.Parent = gui
Theme.bindEffects(purchaseSound)

---------------------------------------------------------------- окно

local overlay = Theme.new("Frame", {
	Name = "Shop",
	Position = if touchOnly then UDim2.fromOffset(-100, -100) else UDim2.new(), -- телефон: закрывает и вырез экрана
	Size = if touchOnly then UDim2.new(1, 200, 1, 200) else UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.45,
	Active = true, -- клики мимо окна не уходят в игру (стрельба)
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})

local panel = Theme.new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundColor3 = Colors.Navy,
	Active = true,
	ClipsDescendants = true,
	ZIndex = 10,
	Parent = overlay,
}, {
	Theme.corner(20),
	Theme.stroke(Colors.Gold, 3),
	Theme.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Colors.Navy, Colors.Dark) }),
})
local panelScale = Theme.new("UIScale", { Parent = panel })
local function rescale()
	panelScale.Scale = Mobile.fitScale(PANEL_W, PANEL_H, gui.AbsoluteSize)
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

local header = Theme.label({
	Position = UDim2.fromOffset(28, 14),
	Size = UDim2.fromOffset(380, 50),
	Text = "🛒 MUSEUM SHOP",
	TextColor3 = Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 44,
	ZIndex = 11,
	Parent = panel,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = header })

-- На телефоне крестик крупнее: после уменьшения окна (около 0.68) он всё равно не меньше пальца
local CLOSE_SIZE = if touchOnly then 66 else 48
local walletPill = Theme.new("Frame", {
	Name = "Wallet",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -(36 + CLOSE_SIZE), 0, 18),
	Size = UDim2.fromOffset(170, 44),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.2,
	ZIndex = 11,
	Parent = panel,
}, { Theme.corner(22), Theme.stroke(Colors.Gold, 2), Theme.padding(6) })
local walletLabel = Theme.label({ Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Gold, MaxTextSize = 28, ZIndex = 11, Parent = walletPill })

local closeButton = Theme.button({
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, if touchOnly then 10 else 18),
	Size = UDim2.fromOffset(CLOSE_SIZE, if touchOnly then 66 else 44),
	BackgroundColor3 = Colors.Red,
	Text = "✕",
	MaxTextSize = 26,
	Modal = true, -- курсор свободен, пока окно открыто
	ZIndex = 11,
	Parent = panel,
})

local subLabel = Theme.label({
	Position = UDim2.fromOffset(28, 66),
	Size = UDim2.new(1, -56, 0, 22),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 16,
	ZIndex = 11,
	Parent = panel,
})

-- Строка внизу: «B — close» или почему покупка не вышла
local messageLabel = Theme.label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(1, -56, 0, 26),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Gray,
	MaxTextSize = 20,
	ZIndex = 11,
	Parent = panel,
})
local DEFAULT_MESSAGE = if touchOnly then "" else "B — close"
local messageToken = 0
local function showMessage(text: string, color: Color3)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color
	task.delay(4, function()
		if messageToken == token then
			messageLabel.Text = DEFAULT_MESSAGE
			messageLabel.TextColor3 = Colors.Gray
		end
	end)
end

---------------------------------------------------------------- вкладки

local currentTab = ShopConfig.Tabs[1]
local tabButtons: { [string]: TextButton } = {}
local tabPages: { [string]: ScrollingFrame } = {}
local selectTab: (name: string) -> ()

local TAB_W, TAB_GAP = 168, 12
for index, name in ShopConfig.Tabs do
	local look = TAB_LOOK[name]
	local button = Theme.button({
		Name = "Tab" .. name,
		Position = UDim2.fromOffset(24 + (index - 1) * (TAB_W + TAB_GAP), 100),
		Size = UDim2.fromOffset(TAB_W, 42),
		Text = look.title,
		MaxTextSize = 22,
		ZIndex = 11,
		Parent = panel,
	})
	local stroke = Theme.stroke(look.color, 2)
	stroke.Parent = button
	button.Activated:Connect(function()
		selectTab(name)
	end)
	tabButtons[name] = button

	local page = Theme.new("ScrollingFrame", {
		Name = "Page" .. name,
		Position = UDim2.fromOffset(24, GRID_TOP),
		Size = UDim2.new(1, -40, 1, -GRID_TOP - 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Colors.Gold,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		ZIndex = 11,
		Parent = panel,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_W, CARD_H),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirectionMaxCells = 5,
		}),
		Theme.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }),
	})
	tabPages[name] = page
end

---------------------------------------------------------------- карточки

type Card = {
	category: string,
	id: string,
	key: string,
	folder: Configuration,
	frame: Frame,
	stroke: UIStroke,
	viewport: ViewportFrame,
	model: Model?,
	base: CFrame,
	angle: number,
	badge: Frame,
	badgeLabel: TextLabel,
	price: TextLabel,
	bar: Frame,
	barFill: Frame,
	button: TextButton,
}

local cards: { [string]: Card } = {}
local pending: { [string]: number } = {} -- ждём ответа сервера на покупку: до какого времени (os.clock)
local dirty = true

local function attrNumber(card: Card, attr: string): number
	return tonumber(card.folder:GetAttribute(attr)) or 0
end

local function attrTextOf(folder: Instance, attr: string): string
	local value = folder:GetAttribute(attr)
	return if typeof(value) == "string" then value else ""
end

local function attrText(card: Card, attr: string): string
	return attrTextOf(card.folder, attr)
end

-- Что написать на кнопке, каким цветом и купит ли нажатие. owned — уже куплено (зелёная плашка), dim — сейчас не
-- купить (картинка темнее).
type ButtonState = { text: string, color: Color3, enabled: boolean, owned: boolean, dim: boolean }

local function personalState(card: Card, item: string): ButtonState
	local good = (Config.Armory.Goods :: any)[item]
	local price = attrNumber(card, ShopAttr.Price)
	local show, action = GameState.armoryOffer(localPlayer, item)
	if not show then
		if good and good.Kind == "Weapon" then
			return { text = "OWNED", color = Colors.Green, enabled = false, owned = true, dim = false }
		elseif good and good.Kind == "Ammo" and not GameState.hasWeapon(localPlayer, good.Weapon) then
			local weapon = (Config.Weapons :: any)[good.Weapon]
			return { text = "NO " .. (if weapon then tostring(weapon.Title) else "WEAPON"), color = Colors.Gray, enabled = false, owned = false, dim = true }
		end
		return { text = "FULL", color = Colors.Green, enabled = false, owned = false, dim = false }
	end
	if money() >= price then
		return { text = ("%s $%d"):format(string.upper(action), price), color = Colors.Gold, enabled = true, owned = false, dim = false }
	end
	return { text = ("NEED $%d"):format(price), color = Colors.Gray, enabled = false, owned = false, dim = false }
end

local function sharedState(card: Card): ButtonState
	if card.folder:GetAttribute(ShopAttr.Owned) == true then
		return { text = if card.category == "Halls" then "OPEN" else "OWNED", color = Colors.Green, enabled = false, owned = true, dim = false }
	end
	local hall = attrText(card, ShopAttr.Hall)
	if hall ~= "" and not GameState.isHallOpen(hall) then
		local closed = if GameState.isWing(hall) then "WING CLOSED" else "HALL CLOSED"
		return { text = closed, color = Colors.Gray, enabled = false, owned = false, dim = true }
	end
	local missing = attrText(card, ShopAttr.Missing)
	if missing ~= "" then
		return { text = missing, color = Colors.Gray, enabled = false, owned = false, dim = true }
	end
	local remaining = attrNumber(card, ShopAttr.Price) - attrNumber(card, ShopAttr.Paid)
	local cash = money()
	local text = string.upper(GameState.buyActionText(remaining, cash))
	if cash >= remaining then
		return { text = text, color = Colors.Gold, enabled = true, owned = false, dim = false }
	elseif cash > 0 then
		return { text = text, color = Colors.Turquoise, enabled = true, owned = false, dim = false }
	end
	return { text = text, color = Colors.Gray, enabled = false, owned = false, dim = false }
end

local function cardState(card: Card): ButtonState
	if (pending[card.key] or 0) > os.clock() then
		return { text = "BUYING...", color = Colors.NavyLight, enabled = false, owned = false, dim = false }
	end
	local item = attrText(card, ShopAttr.Item)
	if item ~= "" then
		return personalState(card, item)
	end
	return sharedState(card)
end

local function refreshCard(card: Card)
	local state = cardState(card)
	local button = card.button
	button.Text = state.text
	button.BackgroundColor3 = state.color
	button.TextColor3 = if state.color == Colors.Gold or state.color == Colors.Turquoise then Colors.Navy else Colors.White
	button.AutoButtonColor = state.enabled
	button.BackgroundTransparency = if state.enabled or state.owned then 0 else 0.3
	card.badge.Visible = state.owned
	card.badgeLabel.Text = if card.category == "Halls" then "✔ OPEN" else "✔ OWNED"
	card.viewport.ImageColor3 = if state.dim then Color3.fromRGB(120, 124, 138) else Color3.new(1, 1, 1)

	local price = attrNumber(card, ShopAttr.Price)
	local paid = if attrText(card, ShopAttr.Item) == "" then attrNumber(card, ShopAttr.Paid) else 0
	local progress = paid > 0 and paid < price and not state.owned
	card.price.Text = if progress then ("$%d / $%d"):format(paid, price) else ("$%d"):format(price)
	card.price.TextColor3 = if state.owned then Colors.Gray else Colors.Gold
	card.bar.Visible = progress
	card.barFill.Size = UDim2.fromScale(math.clamp(if price > 0 then paid / price else 0, 0, 1), 1)
end

local function refresh()
	dirty = false
	walletLabel.Text = ("$%d"):format(money())
	local look = TAB_LOOK[currentTab]
	subLabel.Text = if currentTab == "Weapons" or currentTab == "Gear" then look.sub else SHARED_SUB .. "   •   " .. look.sub
	for name, button in tabButtons do
		local selected = name == currentTab
		button.BackgroundColor3 = if selected then TAB_LOOK[name].color else Colors.NavyLight
		button.TextColor3 = if selected then Colors.Navy else Colors.White
	end
	for _, card in cards do
		if card.category == currentTab then
			refreshCard(card)
		end
	end
end

-- Нажатие на кнопку карточки: купить, а если нельзя — сказать почему
local function press(card: Card)
	local state = cardState(card)
	if state.enabled then
		pending[card.key] = os.clock() + 3 -- сервер не ответил (сбой сети) — кнопку не держим вечно
		dirty = true
		Remotes.get(Remotes.Names.ShopBuy):FireServer(card.category, card.id)
		return
	end
	if state.owned or state.text == "BUYING..." then
		return
	end
	if state.text == "HALL CLOSED" or state.text == "WING CLOSED" then
		local hall = attrText(card, ShopAttr.Hall)
		local settings = (Config.Halls :: any)[hall]
		local title = if settings then tostring(settings.Title) else (Config.Wings.Titles :: any)[hall]
		showMessage(("Open the %s first — Halls tab"):format(if title then tostring(title) else "hall"), Colors.Red)
	elseif state.text == "NO EXHIBIT" then
		showMessage("Buy this exhibit first — Exhibits tab", Colors.Red)
	elseif string.sub(state.text, 1, 3) == "NO " then
		showMessage("Buy the weapon first", Colors.Red)
	elseif state.text == "FULL" then
		showMessage("You can't carry more", Colors.Gray)
	else
		local item = attrText(card, ShopAttr.Item)
		local need = attrNumber(card, ShopAttr.Price) - (if item == "" then attrNumber(card, ShopAttr.Paid) else 0) - money()
		showMessage(("You need $%d more — tourists bring money every day"):format(math.max(0, need)), Colors.Red)
	end
end

-- 3D-картинка: копия модели Preview, крутится вокруг своей середины по полу
local function buildPicture(card: Card)
	if card.model then
		return
	end
	local preview = card.folder:FindFirstChild("Preview")
	if not (preview and preview:IsA("PVInstance")) then
		return
	end
	local container = Instance.new("Model")
	container.Name = "Picture"
	preview:Clone().Parent = container
	container.WorldPivot = CFrame.identity
	local boxCFrame, size = container:GetBoundingBox()
	if size.Magnitude < 0.001 then
		container:Destroy()
		return
	end
	container.WorldPivot = CFrame.new(boxCFrame.Position.X, boxCFrame.Position.Y - size.Y / 2, boxCFrame.Position.Z)
	container.Parent = card.viewport
	local camera = card.viewport.CurrentCamera
	if camera then
		ClassCards.frameCamera(camera, container)
	end
	card.model = container
	card.base = container.WorldPivot
end

local function addCard(category: string, folder: Instance)
	if not folder:IsA("Configuration") then
		return
	end
	local key = category .. "/" .. folder.Name
	if cards[key] then
		return
	end
	local page = tabPages[category]
	if not page then
		return
	end
	local color = TAB_LOOK[category].color
	local frame = Theme.new("Frame", {
		Name = folder.Name,
		LayoutOrder = tonumber(folder:GetAttribute(ShopAttr.Order)) or 0,
		BackgroundColor3 = Colors.White,
		ZIndex = 12,
		Parent = page,
	}, {
		Theme.corner(14),
		Theme.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color:Lerp(Colors.Navy, 0.62)),
				ColorSequenceKeypoint.new(0.5, Colors.Navy),
				ColorSequenceKeypoint.new(1, Colors.Dark),
			}),
		}),
	})
	local stroke = Theme.stroke(color, 2)
	stroke.Transparency = 0.45
	stroke.Parent = frame

	Theme.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.8,
		ZIndex = 12,
		Parent = frame,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

	local viewport = Theme.new("ViewportFrame", {
		Name = "Picture",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 108),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 165),
		LightColor = Color3.fromRGB(255, 246, 230),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 13,
		Parent = frame,
	})
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local badge = Theme.new("Frame", {
		Name = "Owned",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(78, 22),
		BackgroundColor3 = Colors.Green,
		Visible = false,
		ZIndex = 14,
		Parent = frame,
	}, { Theme.corner(11) })
	local badgeLabel = Theme.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 13, ZIndex = 14, Parent = badge })

	Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(8, 112),
		Size = UDim2.new(1, -16, 0, 24),
		Text = string.upper(attrTextOf(folder, ShopAttr.Title)),
		MaxTextSize = 20,
		ZIndex = 13,
		Parent = frame,
	})
	Theme.label({
		Name = "Info",
		Position = UDim2.fromOffset(8, 137),
		Size = UDim2.new(1, -16, 0, 28),
		Font = Theme.BodyFont,
		Text = attrTextOf(folder, ShopAttr.Info),
		TextColor3 = Colors.Marble,
		TextWrapped = true,
		MaxTextSize = 12,
		ZIndex = 13,
		Parent = frame,
	})
	local price = Theme.label({
		Name = "Price",
		Position = UDim2.fromOffset(8, 166),
		Size = UDim2.new(1, -16, 0, 22),
		TextColor3 = Colors.Gold,
		MaxTextSize = 20,
		ZIndex = 13,
		Parent = frame,
	})
	local bar = Theme.new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(18, 189),
		Size = UDim2.new(1, -36, 0, 5),
		BackgroundColor3 = Colors.Dark,
		Visible = false,
		ZIndex = 13,
		Parent = frame,
	}, { Theme.corner(3) })
	local barFill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Turquoise,
		ZIndex = 13,
		Parent = bar,
	}, { Theme.corner(3) })
	local button = Theme.button({
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 34),
		MaxTextSize = 18,
		ZIndex = 13,
		Parent = frame,
	})

	local card: Card = {
		category = category,
		id = folder.Name,
		key = key,
		folder = folder,
		frame = frame,
		stroke = stroke,
		viewport = viewport,
		model = nil,
		base = CFrame.identity,
		-- Оружие лежит стволом вперёд: сначала поворачиваем боком
		angle = if category == "Weapons" then 1.2 else (tonumber(folder:GetAttribute(ShopAttr.Order)) or 0) * 0.7,
		badge = badge,
		badgeLabel = badgeLabel,
		price = price,
		bar = bar,
		barFill = barFill,
		button = button,
	}
	cards[key] = card
	buildPicture(card)
	if not card.model then
		local retryScheduled = false
		local conn: RBXScriptConnection?
		conn = folder.DescendantAdded:Connect(function()
			if card.model then
				if conn then
					conn:Disconnect()
					conn = nil
				end
				return
			end
			if retryScheduled then
				return
			end
			retryScheduled = true
			task.defer(function()
				retryScheduled = false
				if not folder.Parent or card.model then
					if conn then
						conn:Disconnect()
						conn = nil
					end
					return
				end
				buildPicture(card)
				if card.model and conn then
					conn:Disconnect()
					conn = nil
				end
			end)
		end)
		folder.Destroying:Once(function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end)
	end
	button.Activated:Connect(function()
		press(card)
	end)
	folder.AttributeChanged:Connect(function()
		dirty = true
	end)
	refreshCard(card)
end

task.spawn(function()
	local root = ReplicatedStorage:WaitForChild(GameState.ShopFolder)
	for _, category in ShopConfig.Tabs do
		local tab = root:WaitForChild(category)
		tab.ChildAdded:Connect(function(child)
			addCard(category, child)
		end)
		for _, child in tab:GetChildren() do
			addCard(category, child)
		end
	end
end)

---------------------------------------------------------------- открыть / закрыть

local openFlag = false

-- Можно ли сейчас открыть магазин; если нет — почему
local function canShop(): (boolean, string)
	if localPlayer:GetAttribute(PlayerAttr.InRound) ~= true then
		return false, "The shop opens when your shift starts"
	elseif GameState.phase() ~= Phase.Day then
		return false, "Shop opens in the morning"
	elseif localPlayer:GetAttribute(PlayerAttr.Downed) == true then
		return false, "You can't shop while you're down"
	elseif localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		return false, if touchOnly then "Close the cameras first" else "Close the cameras first (Tab)"
	end
	return true, ""
end

function selectTab(name: string)
	if not tabPages[name] then
		return
	end
	currentTab = name
	for tab, page in tabPages do
		page.Visible = tab == name
	end
	tabPages[name].CanvasPosition = Vector2.zero
	refresh()
end

local function open()
	local ok, reason = canShop()
	if not ok then
		showToast(reason)
		return
	end
	openFlag = true
	overlay.Visible = true
	localPlayer:SetAttribute(GameState.PlayerAttr.ShopOpen, true) -- только у себя: обучение засчитывает шаг (блок C)
	messageLabel.Text = DEFAULT_MESSAGE
	messageLabel.TextColor3 = Colors.Gray
	selectTab(currentTab)
	rescale()
	local target = panelScale.Scale
	panelScale.Scale = target * 0.92
	TweenService:Create(panelScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

local function close()
	if not openFlag then
		return
	end
	openFlag = false
	overlay.Visible = false
	localPlayer:SetAttribute(GameState.PlayerAttr.ShopOpen, false)
	rescale()
end

toggle = function()
	if openFlag then
		close()
	else
		open()
	end
end

closeButton.Activated:Connect(close)

-- Касса SHOP у Моны Лизы: F «Open shop» (днём кнопку включает сервер)
task.spawn(function()
	local map = Workspace:WaitForChild(MapSchema.Root)
	local props = map:WaitForChild(MapSchema.Props)
	local counter = props:WaitForChild(MapSchema.ShopCounter, 60)
	if not counter then
		return
	end
	local function hook(item: Instance)
		if item:IsA("ProximityPrompt") and item.Name == MapSchema.ShopPrompt then
			item.Triggered:Connect(function()
				open()
			end)
		end
	end
	counter.DescendantAdded:Connect(hook)
	for _, item in counter:GetDescendants() do
		hook(item)
	end
end)
-- Esc открывает меню Roblox (его не перехватить) — окно магазина при этом закрывается
GuiService.MenuOpened:Connect(close)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Keys.Shop then
		toggle()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		close()
	end
end)

---------------------------------------------------------------- ответ сервера

Remotes.get(Remotes.Names.ShopReply).OnClientEvent:Connect(function(kind, category, id, text)
	if typeof(category) == "string" and typeof(id) == "string" then
		pending[category .. "/" .. id] = nil
	end
	local message = if typeof(text) == "string" then text else ""
	if kind == ShopReply.Bought then
		SoundService:PlayLocalSound(purchaseSound)
		showPopup(message, Colors.Gold)
	elseif kind == ShopReply.PutIn then
		SoundService:PlayLocalSound(purchaseSound)
		showPopup(message, Colors.Turquoise)
	elseif openFlag then
		showMessage(message, Colors.Red)
	else
		showToast(message)
	end
	dirty = true
end)

---------------------------------------------------------------- обновление

-- Деньги, оружие, броня, аптечки или открытый зал поменялись — кнопки заново
localPlayer.AttributeChanged:Connect(function()
	dirty = true
end)
GameState.folder().AttributeChanged:Connect(function()
	dirty = true
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.15 then
		return
	end
	accumulator = 0
	-- Кнопка SHOP: видна, пока игрок на смене; серая, когда магазин закрыт (ночью — «Shop opens in the morning»)
	local onShift = localPlayer:GetAttribute(PlayerAttr.InRound) == true
	shopButton.root.Visible = onShift
	local available = canShop()
	local shopLabel = shopButton.label
	if shopLabel then
		shopLabel.TextColor3 = if available then Colors.White else Colors.Gray
	end
	if openFlag and not available then
		close()
	elseif openFlag then
		dirty = true -- раз в 0.15 сек: «BUYING...» без ответа сервера гаснет сама
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not openFlag then
		return
	end
	if dirty then
		refresh()
	end
	for _, card in cards do
		local model = card.model
		if model and card.category == currentTab then
			card.angle += dt * ShopConfig.PreviewSpin
			model:PivotTo(card.base * CFrame.Angles(0, card.angle, 0))
		end
	end
end)
