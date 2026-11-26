-- Окно HOW TO PLAY в хабе (этап 5, блок A): 4 страницы-картинки, стрелки ◀ ▶ (и клавиши ← →).
-- Картинки — простые сцены из пиксельных иконок (UI/PixelIcon) и 3D-модели класса в ViewportFrame.
--  1. День: туристы приносят деньги, покупай экспонаты и крылья.
--  2. Ночь: воры входят через двери, держи F, чтобы арестовать.
--  3. Украли Мону Лизу — игра окончена.
--  4. Классы и алмазы.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local PixelButton = require(UI:WaitForChild("PixelButton"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))
local ClassCards = require(UI:WaitForChild("ClassCards"))

local Colors = Theme.Colors
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local HowToPlay = {}

-- Элемент сцены: иконка (over — вторая иконка поверх, например крестик), крупный текст или 3D-модель класса
type Element = { icon: string?, over: string?, text: string?, color: Color3?, class: string? }
type Page = { title: string, text: string, scene: { Element } }

local arrestKey = if touchOnly then "Hold the F button" else "Hold F"
local PAGES: { Page } = {
	{
		title = "DAY",
		text = "Tourists bring money. Buy exhibits and wings to get more tourists.",
		scene = { { icon = "Sun" }, { text = "+$", color = Colors.Gold }, { icon = "Painting" } },
	},
	{
		title = "NIGHT",
		text = "Thieves come through the doors. " .. arrestKey .. " near a thief to arrest.",
		scene = { { icon = "Moon" }, { icon = "Thief" }, { icon = "KeyF" } },
	},
	{
		title = "GAME OVER",
		text = "If thieves carry the Mona Lisa out - the game is over. Guard it!",
		scene = { { icon = "Thief" }, { text = ">", color = Colors.Red }, { icon = "Painting", over = "Close" } },
	},
	{
		title = "CLASSES & DIAMONDS",
		text = ("Survive nights (+%d) and arrest thieves (+%d) to earn diamonds. Spend them on classes in the SHOP."):format(
			Config.Diamonds.PerNight,
			Config.Diamonds.PerArrest
		),
		scene = { { icon = "Classes" }, { class = "Assault" }, { icon = "Diamond" } },
	},
}

local ICON_CELL = 6 -- иконка сцены 96 × 96

local window = PixelWindow.new({ name = "HowToPlay", title = "HOW TO PLAY", width = 760, height = 450 })
local content = window.content

local pageTitle = Theme.pixelLabel({
	Name = "PageTitle",
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(1, 0, 0, 24),
	TextColor3 = Colors.Turquoise,
	ZIndex = 3,
	Parent = content,
}, 16, 2)

local sceneFrame = Theme.new("Frame", {
	Name = "Scene",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 40),
	Size = UDim2.new(1, -150, 0, 150),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = content,
})

local pageText = Theme.pixelLabel({
	Name = "Text",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 206),
	Size = UDim2.new(1, -60, 0, 64),
	TextColor3 = Colors.Marble,
	TextWrapped = true,
	ZIndex = 3,
	Parent = content,
}, 12, 2)

local pageNumber = Theme.pixelLabel({
	Name = "Number",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(120, 16),
	TextColor3 = Colors.Gray,
	ZIndex = 3,
	Parent = content,
}, 12, 2)

-- Сцена страницы: элементы в ряд по центру
local spinning: { { model: Model, base: CFrame, angle: number } } = {}

local function buildScene(page: Page)
	sceneFrame:ClearAllChildren()
	table.clear(spinning)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 36),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sceneFrame,
	})
	for index, element in page.scene do
		if element.icon then
			local icon = PixelIcon.new(element.icon, true, 4)
			icon.Size = PixelIcon.size(element.icon, ICON_CELL)
			icon.LayoutOrder = index
			icon.Parent = sceneFrame
			if element.over then
				local over = PixelIcon.new(element.over, true, 6)
				over.AnchorPoint = Vector2.new(0.5, 0.5)
				over.Position = UDim2.fromScale(0.5, 0.5)
				over.Size = PixelIcon.size(element.over, ICON_CELL - 1)
				over.Parent = icon
			end
		elseif element.text then
			Theme.pixelLabel({
				Size = UDim2.fromOffset(96, 96),
				Text = element.text,
				TextColor3 = element.color or Colors.White,
				LayoutOrder = index,
				ZIndex = 4,
				Parent = sceneFrame,
			}, 48, 4)
		elseif element.class then
			local viewport = Theme.new("ViewportFrame", {
				Size = UDim2.fromOffset(140, 140),
				BackgroundTransparency = 1,
				Ambient = Color3.fromRGB(150, 150, 165),
				LightColor = Color3.fromRGB(255, 246, 230),
				LightDirection = Vector3.new(-0.6, -1, -0.8),
				LayoutOrder = index,
				ZIndex = 4,
				Parent = sceneFrame,
			})
			local camera = Instance.new("Camera")
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			local model = ClassCards.picture(element.class)
			model.Parent = viewport
			ClassCards.frameCamera(camera, model)
			table.insert(spinning, { model = model, base = model.WorldPivot, angle = 0 })
		end
	end
end

local current = 1

local function show(index: number)
	current = ((index - 1) % #PAGES) + 1
	local page = PAGES[current]
	pageTitle.Text = page.title
	pageText.Text = string.upper(page.text)
	pageNumber.Text = ("%d / %d"):format(current, #PAGES)
	buildScene(page)
end

local function arrow(icon: string, side: number, step: number)
	local button = PixelButton.new({
		icon = icon,
		name = icon,
		cell = 4,
		zIndex = 4,
		parent = content,
		onActivated = function()
			show(current + step)
		end,
	})
	button.root.AnchorPoint = Vector2.new(side, 0.5)
	button.root.Position = UDim2.new(side, if side == 0 then 4 else -4, 0, 40 + 75)
end
arrow("ArrowLeft", 0, -1)
arrow("ArrowRight", 1, 1)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not window.isOpen() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Left then
		show(current - 1)
	elseif input.KeyCode == Enum.KeyCode.Right then
		show(current + 1)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not window.isOpen() then
		return
	end
	for _, item in spinning do
		item.angle += dt * 0.8
		item.model:PivotTo(item.base * CFrame.Angles(0, item.angle, 0))
	end
end)

function HowToPlay.open()
	show(1)
	window.open()
end

function HowToPlay.toggle()
	if window.isOpen() then
		window.close()
	else
		HowToPlay.open()
	end
end

HowToPlay.close = window.close
HowToPlay.isOpen = window.isOpen

return HowToPlay
