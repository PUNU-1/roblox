-- Окно в пиксельном стиле (этап 5, блок A, решение 75): тёмная панель с толстой пиксельной каймой (углы
-- ступеньками из квадратиков, без UICorner), заголовок пиксельным шрифтом, крестик — пиксельная иконка.
-- Общий модуль: хаб (CLASS SHOP, Classes, Gifts, How to play, Coming soon), позже — музей (блок D).
--
-- Открыто только одно окно за раз: открыл новое — прежнее закрылось. Меню Roblox (Esc) закрывает все окна.
-- На маленьком экране окно уменьшается целиком (UIScale). На телефоне (этап 8, блок Q) — по безопасной зоне экрана
-- (UI/Mobile.fitScale), затемнение закрывает и вырез, у крестика зона нажатия не меньше пальца (Config.Mobile.MinTouch).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))
local PixelButton = require(script.Parent:WaitForChild("PixelButton"))
local Mobile = require(script.Parent:WaitForChild("Mobile"))

local Colors = Theme.Colors

local PixelWindow = {}

export type Window = {
	gui: ScreenGui,
	overlay: Frame,
	panel: Frame, -- вся панель (координаты от левого верхнего угла каймы)
	content: Frame, -- место под заголовком внутри каймы
	title: TextLabel,
	inset: number, -- толщина каймы в пикселях
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	setTitle: (text: string) -> (),
}

export type Props = {
	name: string,
	title: string,
	width: number,
	height: number,
	displayOrder: number?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

local TITLE_H = 44 -- высота строки заголовка под каймой

local windows: { Window } = {}

-- Цвета каймы снаружи внутрь: чёрный контур, золото, тёмное золото, заливка
local function frameLayers(): { Color3 }
	return { PixelIcon.Outline, Colors.Gold, Color3.fromHex("8C6A1E"), Colors.Navy }
end

function PixelWindow.new(props: Props): Window
	local cell = Config.PixelUI.WindowCell
	local gui = Theme.screenGui(props.name, props.displayOrder or 5)

	-- Затемнение экрана: ловит нажатия, чтобы они не уходили в мир за окном
	-- На телефоне ScreenGui окна — в безопасной зоне, поэтому затемнение шире на 100 с каждой стороны (закрывает вырез)
	local overlay = Theme.new("Frame", {
		Name = "Overlay",
		Position = if Mobile.enabled then UDim2.fromOffset(-100, -100) else UDim2.new(),
		Size = if Mobile.enabled then UDim2.new(1, 200, 1, 200) else UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Dark,
		BackgroundTransparency = 0.4,
		Active = true,
		Visible = false,
		Parent = gui,
	})

	local panel = Theme.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.width, props.height),
		BackgroundTransparency = 1,
		Active = true,
		Parent = overlay,
	})
	local _, inset = PixelIcon.box(panel, cell, { layers = frameLayers(), shadow = true })
	local scale = Theme.new("UIScale", { Parent = panel })

	local title = Theme.pixelLabel({
		Name = "Title",
		Position = UDim2.fromOffset(inset + 10, inset + 8),
		Size = UDim2.new(1, -2 * inset - 80, 0, TITLE_H - 12),
		Text = props.title,
		TextColor3 = Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = panel,
	}, 24, 3)

	local content = Theme.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(inset, inset + TITLE_H),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset - TITLE_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = panel,
	})

	local openFlag = false
	local window: Window

	local closeHit: TextButton? = nil
	local function rescale()
		scale.Scale = Mobile.fitScale(props.width, props.height, gui.AbsoluteSize)
		local hit = closeHit
		if hit then
			local size = Mobile.touchSize(54, scale.Scale)
			hit.Size = UDim2.fromOffset(size, size)
		end
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local function close()
		if not openFlag then
			return
		end
		openFlag = false
		overlay.Visible = false
		if props.onClose then
			props.onClose()
		end
	end

	local function open()
		for _, other in windows do
			if other ~= window and other.isOpen() then
				other.close()
			end
		end
		local wasOpen = openFlag
		openFlag = true
		overlay.Visible = true
		if props.onOpen then
			props.onOpen()
		end
		if not wasOpen then
			rescale()
			local target = scale.Scale
			scale.Scale = target * 0.9
			TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		end
	end

	local closeButton = PixelButton.new({
		icon = "Close",
		name = "Close",
		cell = 3,
		zIndex = 4,
		parent = panel,
		onActivated = close,
	})
	closeButton.root.Position = UDim2.new(1, -inset - 54, 0, inset + 2)
	if Mobile.enabled then
		-- Невидимая зона нажатия вокруг крестика: после уменьшения окна крестик меньше пальца, а зона — нет
		local hit = Theme.new("TextButton", {
			Name = "CloseHit",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -inset - 27, 0, inset + 2 + 24),
			Size = UDim2.fromOffset(54, 54),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 3,
			Parent = panel,
		})
		hit.Activated:Connect(function()
			PixelButton.click()
			close()
		end)
		closeHit = hit
		rescale()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	end

	window = {
		gui = gui,
		overlay = overlay,
		panel = panel,
		content = content,
		title = title,
		inset = inset,
		open = open,
		close = close,
		toggle = function()
			if openFlag then
				close()
			else
				open()
			end
		end,
		isOpen = function(): boolean
			return openFlag
		end,
		setTitle = function(text: string)
			title.Text = text
		end,
	}
	table.insert(windows, window)
	return window
end

-- Открыто ли сейчас хоть одно окно.
function PixelWindow.anyOpen(): boolean
	for _, window in windows do
		if window.isOpen() then
			return true
		end
	end
	return false
end

function PixelWindow.closeAll()
	for _, window in windows do
		window.close()
	end
end

-- Пиксельная рамка для части окна (карточка, подтверждение): тёмная заливка, золотой контур.
function PixelWindow.box(parent: Instance, fill: Color3?, border: Color3?): number
	local _, inset = PixelIcon.box(parent, 3, { layers = { PixelIcon.Outline, border or Colors.Gold, fill or Colors.Navy }, shadow = true })
	return inset
end

GuiService.MenuOpened:Connect(PixelWindow.closeAll)

return PixelWindow
