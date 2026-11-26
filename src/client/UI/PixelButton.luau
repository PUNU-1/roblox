-- Пиксельные кнопки (этап 5, блок A, решение 75). Общий модуль: хаб сейчас, кнопки музея — в блоке D.
--
-- PixelButton.new — кнопка-иконка: пиксельная иконка (PixelIcon) и под ней подпись пиксельным шрифтом.
--   Никакой рамки, фона и скругления: только иконка с тенью и белый текст с чёрной обводкой у самого текста.
--   Мышь над кнопкой — иконка подрастает и покачивается, нажали — сжимается, короткий клик.
--   Красная точка-уведомление в углу иконки (setDot) — например, «подарок можно забрать».
-- PixelButton.text — кнопка с текстом в пиксельной рамке (BUY, CLAIM, START, YES / NO): ступенчатые углы из
--   квадратиков, светлая полоска сверху и тёмная снизу.
--
-- Телефон: кнопки — TextButton с Active = true, нажатие ловится через Activated — оно срабатывает и от мыши, и от
-- пальца, и от геймпада. Поверх кнопок не должно быть невидимых Frame с Active = true (они съедают касание).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local Settings = Config.PixelUI

local PixelButton = {}

local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCE = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Один звук клика на всех
local clickSound: Sound? = nil
function PixelButton.click()
	if Settings.ClickSound == "" then
		return
	end
	local sound = clickSound
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "PixelClick"
		created.SoundId = Settings.ClickSound
		created.Volume = Settings.ClickVolume
		created.PlaybackSpeed = Settings.ClickSpeed
		created.Parent = SoundService
		clickSound = created
		sound = created
	end
	SoundService:PlayLocalSound(sound :: Sound)
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

---------------------------------------------------------------- кнопка-иконка

export type IconButton = {
	root: TextButton,
	setCell: (cell: number) -> (),
	setDot: (on: boolean) -> (),
	setLabel: (text: string) -> (),
	height: () -> number,
	width: () -> number,
}

export type IconProps = {
	icon: string,
	label: string?, -- подпись под иконкой (nil — без подписи, например крестик окна)
	key: string?, -- клавиша в уголке иконки ("B"); на телефоне не показывается
	cell: number?, -- пикселей на клетку (по умолчанию Config.PixelUI.Cell)
	name: string?,
	layoutOrder: number?,
	zIndex: number?,
	parent: Instance?,
	onActivated: () -> (),
}

-- Размер подписи для клетки cell: Press Start 2P ровный при чётных размерах, не меньше 8.
local function labelSize(cell: number): number
	return math.max(8, math.floor(cell * 2.75 / 2) * 2)
end

function PixelButton.new(props: IconProps): IconButton
	local cell = props.cell or Settings.Cell
	local z = props.zIndex or 2
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local root = Theme.new("TextButton", {
		Name = props.name or props.icon,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true, -- нажимается и пальцем
		Selectable = true,
		Text = "",
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = z,
	})

	-- Иконка в своём Frame: его масштаб и поворот — покачивание и сжатие, кнопка при этом не двигается
	local holder = Theme.new("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = root,
	})
	local scale = Theme.new("UIScale", { Parent = holder })
	local icon = PixelIcon.new(props.icon, true, z + 1)
	icon.Size = UDim2.fromScale(1, 1)
	icon.Parent = holder

	local label: TextLabel? = nil
	if props.label then
		label = Theme.pixelLabel({
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0),
			Text = props.label,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = z + 2,
			Parent = root,
		})
	end

	local keyLabel: TextLabel? = nil
	if props.key and not touchOnly then
		keyLabel = Theme.pixelLabel({
			Name = "Key",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1.05, 1.05),
			Text = props.key,
			TextColor3 = Color3.fromHex("FFE08A"),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			ZIndex = z + 3,
			Parent = holder,
		})
	end

	-- Красная точка-уведомление: прыгает в правом верхнем углу иконки
	local dot = PixelIcon.new("Dot", true, z + 4)
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.88, 0.12)
	dot.Visible = false
	dot.Parent = holder
	local dotTween = TweenService:Create(dot, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.fromScale(0.88, 0.04),
	})

	local currentCell = cell
	local function iconPixels(): number
		return 16 * currentCell
	end
	local function width(): number
		local w = iconPixels() + 2 * currentCell
		if label then
			w = math.max(w, 12 * labelSize(currentCell))
		end
		return w
	end
	local function height(): number
		local h = iconPixels() + currentCell -- тень
		if label then
			h += currentCell + labelSize(currentCell) + 4
		end
		return h
	end

	local function setCell(newCell: number)
		currentCell = math.max(1, math.floor(newCell))
		local px = iconPixels()
		root.Size = UDim2.fromOffset(width(), height())
		holder.Size = UDim2.fromOffset(px, px)
		holder.Position = UDim2.new(0.5, 0, 0, px / 2)
		local dotCell = math.max(2, currentCell - 2)
		dot.Size = UDim2.fromOffset(8 * dotCell, 8 * dotCell)
		if label then
			local size = labelSize(currentCell)
			label.TextSize = size
			label.Position = UDim2.new(0.5, 0, 0, px + currentCell * 2)
			label.Size = UDim2.new(1, 0, 0, size + 4)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = math.max(1, math.floor(size / 8))
			end
		end
		if keyLabel then
			local size = math.max(8, currentCell * 2)
			keyLabel.TextSize = size
			keyLabel.Size = UDim2.fromOffset(size * 2, size)
		end
	end
	setCell(cell)

	-- Наведение: подрастает и покачивается. Нажатие: сжимается.
	local hovered = false
	local pressed = false
	local rock: Tween? = nil
	local function settle()
		local target = if pressed then Settings.PressScale elseif hovered then Settings.HoverScale else 1
		TweenService:Create(scale, if pressed then QUICK else BOUNCE, { Scale = target }):Play()
	end
	local function startRock()
		if rock then
			return
		end
		holder.Rotation = -Settings.HoverRock
		local tween = TweenService:Create(holder, TweenInfo.new(Settings.RockSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Rotation = Settings.HoverRock,
		})
		rock = tween
		tween:Play()
	end
	local function stopRock()
		local tween = rock
		if tween then
			tween:Cancel()
			rock = nil
		end
		TweenService:Create(holder, QUICK, { Rotation = 0 }):Play()
	end

	root.MouseEnter:Connect(function()
		hovered = true
		startRock()
		settle()
	end)
	root.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		stopRock()
		settle()
	end)
	root.InputBegan:Connect(function(input)
		if isPress(input) then
			pressed = true
			settle()
		end
	end)
	root.InputEnded:Connect(function(input)
		if isPress(input) then
			pressed = false
			if input.UserInputType == Enum.UserInputType.Touch then
				hovered = false -- у пальца нет «наведения»
				stopRock()
			end
			settle()
		end
	end)
	root.Activated:Connect(function()
		PixelButton.click()
		props.onActivated()
	end)

	if props.parent then
		root.Parent = props.parent
	end

	return {
		root = root,
		setCell = setCell,
		setDot = function(on: boolean)
			if dot.Visible == on then
				return
			end
			dot.Visible = on
			if on then
				dotTween:Play()
			else
				dotTween:Cancel()
				dot.Position = UDim2.fromScale(0.88, 0.12)
			end
		end,
		setLabel = function(text: string)
			if label then
				label.Text = text
			end
		end,
		height = height,
		width = width,
	}
end

---------------------------------------------------------------- кнопка с текстом в пиксельной рамке

export type TextButtonObject = {
	root: TextButton,
	label: TextLabel,
	setText: (text: string) -> (),
	setColor: (fill: Color3, textColor: Color3?) -> (),
	setEnabled: (enabled: boolean) -> (),
	enabled: () -> boolean,
}

export type TextProps = {
	text: string,
	color: Color3?, -- заливка (по умолчанию золото)
	textColor: Color3?,
	textSize: number?,
	cell: number?, -- пикселей на клетку рамки (по умолчанию 3)
	name: string?,
	position: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	zIndex: number?,
	parent: Instance?,
	onActivated: () -> (),
}

function PixelButton.text(props: TextProps): TextButtonObject
	local cell = props.cell or 3
	local z = props.zIndex or 2
	local fill = props.color or Theme.Colors.Gold
	local root = Theme.new("TextButton", {
		Name = props.name or "PixelTextButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true, -- нажимается и пальцем
		Selectable = true,
		Text = "",
		AnchorPoint = props.anchor or Vector2.zero,
		Position = props.position or UDim2.new(),
		Size = props.size or UDim2.fromOffset(180, 48),
		ZIndex = z,
	})
	local scale = Theme.new("UIScale", { Parent = root })
	local box, inset = PixelIcon.box(root, cell, {
		layers = { PixelIcon.Outline, fill },
		bevel = true,
		shadow = true,
		zIndex = z,
	})
	local label = Theme.pixelLabel({
		Name = "Label",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset - cell),
		Text = props.text,
		TextColor3 = props.textColor or Theme.Colors.White,
		TextWrapped = true,
		ZIndex = z + 1,
		Parent = root,
	}, props.textSize or 16)

	local enabled = true
	local current = fill
	local function paint(color: Color3)
		PixelIcon.recolor(box, 2, color)
	end
	local hovered = false
	root.MouseEnter:Connect(function()
		hovered = true
		if enabled then
			paint(current:Lerp(Color3.new(1, 1, 1), 0.15))
		end
	end)
	root.MouseLeave:Connect(function()
		hovered = false
		paint(current)
		TweenService:Create(scale, QUICK, { Scale = 1 }):Play()
	end)
	root.InputBegan:Connect(function(input)
		if isPress(input) then
			TweenService:Create(scale, QUICK, { Scale = 0.94 }):Play()
		end
	end)
	root.InputEnded:Connect(function(input)
		if isPress(input) then
			TweenService:Create(scale, BOUNCE, { Scale = 1 }):Play()
		end
	end)
	-- Неактивную кнопку тоже можно нажать: тот, кто её создал, сам скажет, почему нельзя
	root.Activated:Connect(function()
		if enabled then
			PixelButton.click()
		end
		props.onActivated()
	end)

	if props.parent then
		root.Parent = props.parent
	end

	return {
		root = root,
		label = label,
		setText = function(text: string)
			label.Text = text
		end,
		setColor = function(color: Color3, textColor: Color3?)
			current = color
			paint(if hovered and enabled then color:Lerp(Color3.new(1, 1, 1), 0.15) else color)
			if textColor then
				label.TextColor3 = textColor
			end
		end,
		setEnabled = function(on: boolean)
			enabled = on
			label.TextTransparency = if on then 0 else 0.35
		end,
		enabled = function(): boolean
			return enabled
		end,
	}
end

return PixelButton
