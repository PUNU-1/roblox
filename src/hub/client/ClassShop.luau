-- Магазин классов в хабе (этап 4, блок 1, решение 74): окно CLASS SHOP и модели на витрине.
--
-- Окно: клавиша B, кнопка SHOP под алмазами (HubHUD), F у подставки витрины или нажатие на серую карточку.
-- 5 больших карточек — крутящаяся 3D-модель класса, умение, описание с числами из Config, цена и кнопка
-- BUY 150 💎 / NEED 150 💎 / OWNED / FREE. Покупка — с подтверждением «Buy Technician for 150 💎?», потом Remote
-- BuyClass; сервер сам проверяет класс, цену и алмазы (ProfileStore) и отвечает ShopResult. Закрыть — B или крестик.
-- Этап 5, блок A: окно в пиксельном стиле (UI/PixelWindow), кнопки BUY / OWNED / YES / NO — пиксельные.
--
-- Витрина: сервер строит подставки (HubBuilder), клиент ставит на каждую модель класса (те же 3D-картинки, что на
-- карточках; собака сидит и машет хвостом) и пишет на табличке над ней название и цену или OWNED — у каждого своё.
-- Модуль один на клиента: его берут HubHUD (кнопка SHOP, клавиша B, серые карточки) и он сам (кнопки F витрины).

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
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ClassCards = require(UI:WaitForChild("ClassCards"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))
local DogAnimator = require(script.Parent:WaitForChild("DogAnimator"))

local Colors = Theme.Colors
local Classes = Config.Classes
local PlayerAttr = GameState.PlayerAttr
local ProfileStatus = GameState.ProfileStatus

local localPlayer = Players.LocalPlayer
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ClassShop = {}

local PANEL_W, PANEL_H = 920, 590
local CARD_W, CARD_H, GAP = 164, 404, 12
local CARD_TOP = 104

local function title(role: string): string
	local info = GameState.classInfo(role)
	return if info then tostring(info.Title) else role
end

local function diamondHex(): string
	return Colors.Diamond:ToHex()
end

---------------------------------------------------------------- окно

local onWindowClose: () -> ()
local onWindowOpen: () -> ()

local window = PixelWindow.new({
	name = "ClassShop",
	title = "CLASS SHOP",
	width = PANEL_W,
	height = PANEL_H,
	onOpen = function()
		onWindowOpen()
	end,
	onClose = function()
		onWindowClose()
	end,
})
local gui = window.gui
local panel = window.panel

-- Свои алмазы справа в заголовке, левее крестика
local walletIcon = PixelIcon.new("Diamond", true, 3)
walletIcon.AnchorPoint = Vector2.new(1, 0)
walletIcon.Position = UDim2.new(1, -window.inset - 72, 0, window.inset + 6)
walletIcon.Size = PixelIcon.size("Diamond", 2)
walletIcon.Parent = panel
local walletLabel = Theme.pixelLabel({
	Name = "Wallet",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -window.inset - 112, 0, window.inset + 14),
	Size = UDim2.fromOffset(160, 20),
	TextColor3 = Colors.Diamond,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 3,
	Parent = panel,
}, 16, 2)

local subLabel = Theme.label({
	Position = UDim2.fromOffset(28, 66),
	Size = UDim2.new(1, -56, 0, 22),
	Font = Theme.BodyFont,
	RichText = true,
	TextColor3 = Colors.Marble,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 17,
	Parent = panel,
})

-- Строка ответа внизу: «Technician unlocked!» или почему не вышло
local messageLabel = Theme.label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -window.inset - 6),
	Size = UDim2.new(1, -56, 0, 30),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 22,
	Parent = panel,
})
local messageToken = 0
local function showMessage(text: string, color: Color3)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color
	task.delay(5, function()
		if messageToken == token then
			messageLabel.Text = if touchOnly then "" else "B — close"
			messageLabel.TextColor3 = Colors.Gray
		end
	end)
end

---------------------------------------------------------------- карточки окна

type ShopCard = {
	role: string,
	frame: Frame,
	stroke: UIStroke,
	button: PixelButton.TextButtonObject,
	price: TextLabel,
	owned: Frame,
	lock: TextLabel,
	viewport: ViewportFrame,
	model: Model,
	base: CFrame,
	rig: DogAnimator.Rig?,
	pose: DogAnimator.Pose,
	angle: number,
}

local cards: { ShopCard } = {}
local focusRole: string? = nil -- карточка, на которой открыли окно (подставка витрины, серая карточка)
local buying: string? = nil -- ждём ответа сервера на покупку
local confirmRole: string? = nil

local confirmOpen: (role: string) -> ()

local cardsLeft = (PANEL_W - (#Classes.Order * CARD_W + (#Classes.Order - 1) * GAP)) / 2
for index, role in Classes.Order do
	local info = (Classes :: any)[role]
	local color: Color3 = info.Color
	local frame = Theme.new("Frame", {
		Name = role,
		Position = UDim2.fromOffset(cardsLeft + (index - 1) * (CARD_W + GAP), CARD_TOP),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Colors.White,
		Parent = panel,
	}, {
		Theme.corner(16),
		Theme.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color:Lerp(Colors.Navy, 0.5)),
				ColorSequenceKeypoint.new(0.5, Colors.Navy),
				ColorSequenceKeypoint.new(1, Colors.Dark),
			}),
		}),
	})
	local stroke = Theme.stroke(color, 2)
	stroke.Transparency = 0.3
	stroke.Parent = frame

	Theme.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(130, 130),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.74,
		Parent = frame,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

	local viewport = Theme.new("ViewportFrame", {
		Name = "Picture",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 156),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 165),
		LightColor = Color3.fromRGB(255, 246, 230),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 2,
		Parent = frame,
	})
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model, rig = ClassCards.picture(role)
	model.Parent = viewport
	ClassCards.frameCamera(camera, model)

	local lock = Theme.label({
		Name = "Lock",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		Text = "🔒",
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = frame,
	})
	local owned = Theme.new("Frame", {
		Name = "Owned",
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.fromOffset(78, 22),
		BackgroundColor3 = Colors.Green,
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	}, { Theme.corner(11) })
	Theme.label({ Size = UDim2.fromScale(1, 1), Text = "✔ OWNED", MaxTextSize = 13, ZIndex = 3, Parent = owned })

	Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(8, 162),
		Size = UDim2.new(1, -16, 0, 30),
		Text = string.upper(info.Title),
		MaxTextSize = 26,
		ZIndex = 2,
		Parent = frame,
	})
	Theme.label({
		Name = "Ability",
		Position = UDim2.fromOffset(8, 194),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Theme.BodyFont,
		Text = ClassCards.abilityLine(info, touchOnly),
		TextColor3 = color:Lerp(Colors.White, 0.25),
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = frame,
	})
	Theme.label({
		Name = "Info",
		Position = UDim2.fromOffset(10, 216),
		Size = UDim2.new(1, -20, 0, 76),
		Font = Theme.BodyFont,
		Text = ClassCards.infoText(role, touchOnly),
		TextColor3 = Colors.Marble,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = frame,
	})
	local price = Theme.label({
		Name = "Price",
		Position = UDim2.fromOffset(8, 298),
		Size = UDim2.new(1, -16, 0, 30),
		RichText = true,
		MaxTextSize = 26,
		ZIndex = 2,
		Parent = frame,
	})
	local button = PixelButton.text({
		name = "Buy",
		text = "",
		textSize = 12,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		size = UDim2.new(1, -16, 0, 52),
		zIndex = 3,
		parent = frame,
		onActivated = function()
			confirmOpen(role)
		end,
	})

	table.insert(cards, {
		role = role,
		frame = frame,
		stroke = stroke,
		button = button,
		price = price,
		owned = owned,
		lock = lock,
		viewport = viewport,
		model = model,
		base = model.WorldPivot,
		rig = rig,
		pose = DogAnimator.newPose(),
		angle = (index - 1) * 0.9,
	})
end

---------------------------------------------------------------- подтверждение

local confirm = Theme.new("Frame", {
	Name = "Confirm",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Dark,
	BackgroundTransparency = 0.3,
	Active = true,
	Visible = false,
	ZIndex = 20,
	Parent = panel,
})
local confirmBox = Theme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(480, 220),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 20,
	Parent = confirm,
})
PixelWindow.box(confirmBox)
local confirmText = Theme.label({
	Position = UDim2.fromOffset(20, 26),
	Size = UDim2.new(1, -40, 0, 64),
	RichText = true,
	TextWrapped = true,
	MaxTextSize = 32,
	ZIndex = 20,
	Parent = confirmBox,
})
local confirmHint = Theme.label({
	Position = UDim2.fromOffset(20, 92),
	Size = UDim2.new(1, -40, 0, 20),
	Font = Theme.BodyFont,
	TextColor3 = Colors.Marble,
	MaxTextSize = 15,
	ZIndex = 20,
	Parent = confirmBox,
})
local confirmYes: () -> ()
local confirmClose: () -> ()
PixelButton.text({
	name = "Yes",
	text = "YES",
	color = Colors.Green,
	position = UDim2.new(0, 24, 1, -80),
	size = UDim2.new(0.5, -36, 0, 56),
	zIndex = 21,
	parent = confirmBox,
	onActivated = function()
		confirmYes()
	end,
})
PixelButton.text({
	name = "No",
	text = "NO",
	color = Colors.NavyLight,
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -24, 1, -80),
	size = UDim2.new(0.5, -36, 0, 56),
	zIndex = 21,
	parent = confirmBox,
	onActivated = function()
		confirmClose()
	end,
})

-- Вспышка после покупки
local flash = Theme.new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.White,
	BackgroundTransparency = 1,
	ZIndex = 30,
	Parent = panel,
})
local unlockedLabel = Theme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(1, -40, 0, 80),
	TextColor3 = Colors.Gold,
	MaxTextSize = 64,
	Visible = false,
	ZIndex = 31,
	Parent = panel,
})
Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 3, Parent = unlockedLabel })

local purchaseSound = Instance.new("Sound")
purchaseSound.SoundId = Config.Sounds.Purchase
purchaseSound.Volume = Config.Sounds.PurchaseVolume
purchaseSound.Parent = gui

---------------------------------------------------------------- состояние

local function status(): any
	return localPlayer:GetAttribute(PlayerAttr.ProfileStatus)
end

-- Что написать на кнопке карточки и можно ли нажать
local function buttonState(role: string): (string, Color3, boolean)
	local cost = GameState.classPrice(role)
	if cost <= 0 then
		return "FREE", Colors.Green, false
	elseif GameState.ownsClass(localPlayer, role) then
		return "OWNED", Colors.Green, false
	elseif buying == role then
		return "BUYING...", Colors.NavyLight, false
	elseif status() ~= ProfileStatus.Ready then
		return "LOADING...", Colors.NavyLight, false
	elseif GameState.diamondsOf(localPlayer) >= cost then
		return ("BUY %d 💎"):format(cost), Colors.Gold, true
	end
	return ("NEED %d 💎"):format(cost), Colors.Gray, false
end

local function refresh()
	local state = status()
	walletLabel.Text = if state == ProfileStatus.Loading or state == nil then "..." else tostring(GameState.diamondsOf(localPlayer))
	local sub = "Earn diamonds by surviving nights and catching thieves"
	if state == ProfileStatus.Offline then
		sub ..= '   <font color="#E8913A">Studio: all classes are open, diamonds are not saved</font>'
	elseif state == ProfileStatus.Error then
		sub ..= '   <font color="#E0575B">Diamonds are unavailable — trying again</font>'
	end
	subLabel.Text = sub
	for _, card in cards do
		local text, color, enabled = buttonState(card.role)
		card.button.setText((string.gsub(text, " 💎", "")))
		card.button.setColor(color, if color == Colors.Gold then Colors.Navy else Colors.White)
		card.button.setEnabled(enabled or text == "OWNED" or text == "FREE")
		local cost = GameState.classPrice(card.role)
		local has = GameState.ownsClass(localPlayer, card.role)
		card.owned.Visible = has and cost > 0
		card.lock.Visible = not has
		card.viewport.ImageColor3 = if has then Color3.new(1, 1, 1) else Color3.fromRGB(175, 178, 188)
		card.price.Text = if cost <= 0
			then '<font color="#3FB56B">FREE</font>'
			else ('<font color="#%s">💎 %d</font>'):format(diamondHex(), cost)
		local focused = card.role == focusRole
		card.stroke.Color = if focused then Colors.Gold else (Classes :: any)[card.role].Color
		card.stroke.Thickness = if focused then 4 else 2
		card.stroke.Transparency = if focused then 0 else 0.3
	end
end

function confirmOpen(role: string)
	local _, _, enabled = buttonState(role)
	if not enabled then
		local cost = GameState.classPrice(role)
		if cost > 0 and not GameState.ownsClass(localPlayer, role) and status() == ProfileStatus.Ready then
			showMessage(("You need %d more 💎 — survive nights and catch thieves"):format(cost - GameState.diamondsOf(localPlayer)), Colors.Red)
		end
		return
	end
	confirmRole = role
	confirmText.Text = ('Buy <font color="#D4A93A">%s</font> for <font color="#%s">%d 💎</font>?'):format(title(role), diamondHex(), GameState.classPrice(role))
	confirmHint.Text = ("You have %d 💎. The class stays yours forever."):format(GameState.diamondsOf(localPlayer))
	confirm.Visible = true
end

function confirmClose()
	confirmRole = nil
	confirm.Visible = false
end

function confirmYes()
	local role = confirmRole
	confirmClose()
	if role and not buying then
		buying = role
		refresh()
		Remotes.get(Remotes.Names.BuyClass):FireServer(role)
		-- Сервер не ответил (сбой сети) — кнопку не держим вечно
		task.delay(15, function()
			if buying == role then
				buying = nil
				refresh()
			end
		end)
	end
end

local function celebrate(role: string)
	flash.BackgroundTransparency = 0.25
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	SoundService:PlayLocalSound(purchaseSound)
	unlockedLabel.Text = string.upper(title(role)) .. " UNLOCKED!"
	unlockedLabel.Visible = true
	unlockedLabel.Size = UDim2.new(1, -40, 0, 40)
	TweenService:Create(unlockedLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, -40, 0, 80) }):Play()
	local text = unlockedLabel.Text
	task.delay(2.2, function()
		if unlockedLabel.Text == text then
			unlockedLabel.Visible = false
		end
	end)
end

Remotes.get(Remotes.Names.ShopResult).OnClientEvent:Connect(function(ok, role, message)
	if typeof(role) ~= "string" then
		return
	end
	if buying == role then
		buying = nil
	end
	local text = if typeof(message) == "string" then message else ""
	if ok == true then
		celebrate(role)
		showMessage(text .. " It's now your class.", Colors.Green)
		-- Купил — сразу выбрал (сервер проверит, можно ли сейчас менять класс)
		Remotes.get(Remotes.Names.SetRole):FireServer(role)
	else
		showMessage(text, Colors.Red)
	end
	refresh()
end)

---------------------------------------------------------------- открыть / закрыть

function onWindowOpen()
	confirmClose()
	unlockedLabel.Visible = false
	messageLabel.Text = if touchOnly then "" else "B — close"
	messageLabel.TextColor3 = Colors.Gray
	refresh()
end

function onWindowClose()
	confirmClose()
end

function ClassShop.isOpen(): boolean
	return window.isOpen()
end

-- Открыть на классе role (его карточка — в золотой рамке, модель крутится быстрее). Другое окно закроется.
function ClassShop.open(role: string?)
	focusRole = if role and GameState.classInfo(role) then role else nil
	window.open()
	refresh()
end

function ClassShop.close()
	window.close()
end

function ClassShop.toggle()
	if window.isOpen() then
		window.close()
	else
		ClassShop.open(nil)
	end
end

for _, name in { PlayerAttr.Diamonds, PlayerAttr.OwnedClasses, PlayerAttr.ProfileStatus } do
	localPlayer:GetAttributeChangedSignal(name):Connect(function()
		if window.isOpen() then
			refresh()
		end
	end)
end

---------------------------------------------------------------- витрина CLASS SHOP

type Display = {
	role: string,
	top: BasePart,
	model: Model,
	base: CFrame,
	rig: DogAnimator.Rig?,
	pose: DogAnimator.Pose,
	angle: number,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
}

local displays: { Display } = {}
local DISPLAY_SIZE = 2.6 -- модель на подставке не больше стольких стадов (кроме собаки — она в настоящий рост)

local function refreshLabels()
	for _, display in displays do
		local cost = GameState.classPrice(display.role)
		if cost <= 0 then
			display.statusLabel.Text = '<font color="#3FB56B">FREE</font>'
		elseif GameState.ownsClass(localPlayer, display.role) then
			display.statusLabel.Text = '<font color="#3FB56B">✔ OWNED</font>'
		else
			display.statusLabel.Text = ('🔒 <font color="#%s">💎 %d</font>'):format(diamondHex(), cost)
		end
	end
end

local function buildDisplay(stand: Instance)
	local role = stand:GetAttribute("Class")
	if typeof(role) ~= "string" or not GameState.classInfo(role) then
		return
	end
	local top = stand:WaitForChild("Top", 10)
	local label = stand:WaitForChild("Label", 10)
	if not (top and top:IsA("BasePart") and label and label:IsA("BasePart")) then
		return
	end
	local model, rig = ClassCards.picture(role)
	if not rig then
		local _, size = model:GetBoundingBox()
		local biggest = math.max(size.X, size.Y, size.Z)
		if biggest > 0 then
			model:ScaleTo(DISPLAY_SIZE / biggest)
		end
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	model.Name = "ClassShopDisplay_" .. role
	model.Parent = Workspace

	-- Табличка: название класса и цена / OWNED (у каждого игрока своё)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 60
	surface.LightInfluence = 0
	surface.Parent = label
	local nameLabel = Theme.label({
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.48),
		Text = string.upper(title(role)),
		TextColor3 = Colors.Gold,
		MaxTextSize = 60,
		Parent = surface,
	})
	local statusLabel = Theme.label({
		Position = UDim2.fromScale(0.05, 0.56),
		Size = UDim2.fromScale(0.9, 0.36),
		RichText = true,
		MaxTextSize = 44,
		Parent = surface,
	})

	local prompt = top:WaitForChild("ShopPrompt", 10)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			ClassShop.open(role)
		end)
	end

	table.insert(displays, {
		role = role,
		top = top,
		model = model,
		base = model.WorldPivot,
		rig = rig,
		pose = DogAnimator.newPose(),
		angle = #displays * 1.1,
		nameLabel = nameLabel,
		statusLabel = statusLabel,
	})
	refreshLabels()
end

task.spawn(function()
	local map = Workspace:WaitForChild(MapSchema.Root)
	local folder = map:WaitForChild(MapSchema.ClassShop)
	for _, role in Classes.Order do
		local stand = folder:WaitForChild(MapSchema.ClassStandPrefix .. role, 20)
		if stand then
			buildDisplay(stand)
		end
	end
end)

for _, name in { PlayerAttr.OwnedClasses, PlayerAttr.ProfileStatus } do
	localPlayer:GetAttributeChangedSignal(name):Connect(refreshLabels)
end

---------------------------------------------------------------- каждый кадр: модели крутятся

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, display in displays do
		display.angle += dt * 0.6
		local surface = display.top.CFrame * CFrame.new(0, -display.top.Size.Y / 2, 0)
		local rig = display.rig
		if rig then
			DogAnimator.previewPose(display.pose, t + display.angle)
			DogAnimator.solve(rig, surface * CFrame.Angles(0, display.angle, 0) * display.base:Inverse(), display.pose, true)
		else
			display.model:PivotTo(surface * CFrame.Angles(0, display.angle, 0))
		end
	end
	if not window.isOpen() then
		return
	end
	for _, card in cards do
		local speed = if card.role == focusRole then 1.3 else 0.5
		card.angle += dt * speed
		local rig = card.rig
		if rig then
			DogAnimator.previewPose(card.pose, t)
			DogAnimator.solve(rig, card.base * CFrame.Angles(0, card.angle, 0) * card.base:Inverse(), card.pose, false)
		else
			card.model:PivotTo(card.base * CFrame.Angles(0, card.angle, 0))
		end
	end
end)

return ClassShop
