-- Телефон (этап 8, блок Q, решения 102–103): общая раскладка экрана, только при Theme.touchOnly().
-- На компьютере модуль ничего не создаёт (Mobile.enabled = false), а fitScale считает окна как раньше.
--
--   * Масштаб — от высоты экрана: опорный экран 667 × 375 (Config.Mobile.RefHeight), кнопки и отступы умножаются.
--   * Места кнопок справа внизу считаются от кнопки прыжка Roblox (PlayerGui.TouchGui.TouchControlFrame.JumpButton),
--     чтобы на неё ничего не налезало: левее прыжка — умная кнопка, над ней — кнопка оружия; над прыжком — маленькая R
--     и выше умение класса. Слева внизу (Config.Mobile.JoystickZone) — джойстик Roblox, туда ничего не ставим.
--   * Свои ScreenGui на телефоне — в безопасной зоне (ScreenInsets = DeviceSafeInsets, Theme.screenGui): вырез экрана
--     ничего не закрывает. Координаты считаем разницей AbsolutePosition — так не важно, как Roblox считает отступы.
--   * Mobile.roundButton — круглая кнопка с пиксельной иконкой и подписью внутри (умная, оружие, R, умение).
-- Модуль один на клиента: его подключают разные LocalScript, и все видят одни и те же места.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))
local PixelButton = require(script.Parent:WaitForChild("PixelButton"))

local Settings = Config.Mobile
local Colors = Theme.Colors

local Mobile = {}
Mobile.enabled = Theme.touchOnly()

export type Slot = { center: Vector2, size: number }

local changedEvent = Instance.new("BindableEvent")

---------------------------------------------------------------- масштаб

function Mobile.viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Масштаб кнопок телефона от высоты экрана (1 на экране высотой 375).
function Mobile.scale(): number
	return math.clamp(Mobile.viewport().Y / Settings.RefHeight, Settings.MinScale, Settings.MaxScale)
end

-- Масштаб окна под экран. На компьютере — как было всегда (отступ 12 с каждой стороны, от 0.4 до 1).
-- На телефоне — по безопасной зоне (area — AbsoluteSize своего ScreenGui) с маленьким отступом: окно и так закрывает игру.
function Mobile.fitScale(width: number, height: number, area: Vector2?): number
	local viewport = Mobile.viewport()
	if not Mobile.enabled then
		return math.clamp(math.min((viewport.X - 24) / width, (viewport.Y - 24) / height), 0.4, 1)
	end
	local size = if area and area.X > 0 and area.Y > 0 then area else viewport
	local margin = 2 * Settings.WindowMargin
	return math.clamp(math.min((size.X - margin) / width, (size.Y - margin) / height), 0.3, 1)
end

-- Крестик и другие кнопки окна: какой размер дать до масштаба окна, чтобы после него было не меньше пальца.
function Mobile.touchSize(base: number, windowScale: number): number
	if not Mobile.enabled then
		return base
	end
	return math.max(base, math.ceil(Settings.MinTouch / math.max(windowScale, 0.3)))
end

---------------------------------------------------------------- свой ScreenGui кнопок

local controlsGui: ScreenGui? = nil
local root: Frame? = nil

-- ScreenGui кнопок телефона и Frame на весь экран внутри (от него считаются места).
-- DisplayOrder 3: над HUD (1) и оружием (2), под магазином (4) и окнами (5).
function Mobile.gui(): (ScreenGui, Frame)
	local gui = controlsGui
	local frame = root
	if gui and frame and gui.Parent then
		return gui, frame
	end
	local created = Theme.screenGui("MobileControls", 3)
	local createdRoot = Theme.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = created,
	})
	controlsGui = created
	root = createdRoot
	createdRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		Mobile.refresh()
	end)
	return created, createdRoot
end

---------------------------------------------------------------- места кнопок

local function jumpButton(): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
end

local slots: { [string]: Slot } = {}

local function compute()
	local _, frame = Mobile.gui()
	local rootPos, rootSize = frame.AbsolutePosition, frame.AbsoluteSize
	if rootSize.X <= 0 or rootSize.Y <= 0 then
		rootSize = Mobile.viewport()
	end
	local s = Mobile.scale()
	local margin = Settings.Margin * s
	local gap = Settings.Gap * s

	-- Прыжок Roblox: читаем, где он на самом деле; нет — как ставит его Roblox (маленький экран — 70 у угла)
	local jumpPos, jumpSize
	local jump = jumpButton()
	if jump and jump.AbsoluteSize.X > 0 then
		jumpPos = jump.AbsolutePosition - rootPos
		jumpSize = jump.AbsoluteSize
	else
		local small = math.min(rootSize.X, rootSize.Y) <= 500
		local size = if small then 70 else 120
		jumpSize = Vector2.new(size, size)
		jumpPos = if small then Vector2.new(rootSize.X - 95, rootSize.Y - 90) else Vector2.new(rootSize.X - 170, rootSize.Y - 210)
	end
	-- Прыжок мог оказаться за краем зоны (вырез экрана) — держим внутри
	jumpPos = Vector2.new(math.clamp(jumpPos.X, 0, math.max(0, rootSize.X - jumpSize.X)), math.clamp(jumpPos.Y, 0, math.max(0, rootSize.Y - jumpSize.Y)))

	local smart = Settings.SmartSize * s
	local bottom = math.min(jumpPos.Y + jumpSize.Y, rootSize.Y - margin)
	local smartCenter = Vector2.new(jumpPos.X - gap - smart / 2, bottom - smart / 2)
	slots.Smart = { center = smartCenter, size = smart }

	local wheel = Settings.WheelSize * s
	slots.Wheel = { center = Vector2.new(smartCenter.X, smartCenter.Y - smart / 2 - gap - wheel / 2), size = wheel }

	-- Над прыжком: R, выше — умение. Правый край — не дальше отступа от края экрана.
	local reload = Settings.ReloadSize * s
	local ability = Settings.AbilitySize * s
	local columnX = math.min(jumpPos.X + jumpSize.X / 2, rootSize.X - margin - ability / 2)
	local reloadCenter = Vector2.new(columnX, jumpPos.Y - gap - reload / 2)
	slots.Reload = { center = reloadCenter, size = reload }
	slots.Ability = { center = Vector2.new(columnX, reloadCenter.Y - reload / 2 - gap - ability / 2), size = ability }
end

-- Место кнопки: "Smart" | "Wheel" | "Reload" | "Ability" (центр и диаметр в пикселях внутри Mobile.gui()).
function Mobile.slot(name: string): Slot
	if next(slots) == nil then
		compute()
	end
	return slots[name] or { center = Vector2.zero, size = 0 }
end

-- Левая граница кнопок справа и правая граница зоны джойстика (между ними внизу по центру — полоска здоровья).
function Mobile.bottomGap(): (number, number)
	local _, frame = Mobile.gui()
	local width = frame.AbsoluteSize.X
	if width <= 0 then
		width = Mobile.viewport().X
	end
	local smart = Mobile.slot("Smart")
	return width * Settings.JoystickZone.X, smart.center.X - smart.size / 2
end

-- Пересчитать места и сообщить всем (экран повернули, появилась кнопка прыжка).
function Mobile.refresh()
	if not Mobile.enabled then
		return
	end
	compute()
	changedEvent:Fire()
end

-- fn вызывается сразу и после каждого пересчёта мест. Возвращает подключение (отключи, если кнопка уничтожена).
function Mobile.bind(fn: () -> ()): RBXScriptConnection
	fn()
	return changedEvent.Event:Connect(fn)
end

-- Поставить объект в место name (центр, квадрат диаметра места).
function Mobile.place(object: GuiObject, name: string): RBXScriptConnection
	return Mobile.bind(function()
		local slot = Mobile.slot(name)
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromOffset(math.floor(slot.center.X), math.floor(slot.center.Y))
		object.Size = UDim2.fromOffset(math.floor(slot.size), math.floor(slot.size))
	end)
end

-- Следим за экраном и кнопкой прыжка (TouchGui появляется не сразу и пересоздаётся)
local watched: GuiObject? = nil
local watchConns: { RBXScriptConnection } = {}
local function watchJump()
	local jump = jumpButton()
	if jump == watched then
		return
	end
	for _, conn in watchConns do
		conn:Disconnect()
	end
	table.clear(watchConns)
	watched = jump
	if jump then
		table.insert(watchConns, jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(Mobile.refresh))
		table.insert(watchConns, jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(Mobile.refresh))
		table.insert(watchConns, jump.Destroying:Connect(function()
			task.defer(watchJump)
		end))
	end
	Mobile.refresh()
end

if Mobile.enabled then
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		playerGui.DescendantAdded:Connect(function(instance)
			if instance.Name == "JumpButton" or instance.Name == "TouchGui" then
				task.defer(watchJump)
			end
		end)
		watchJump()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(Mobile.refresh)
		end
	end)
end

---------------------------------------------------------------- круглая кнопка

export type RoundButton = {
	root: TextButton,
	setIcon: (icon: string?) -> (),
	setLabel: (text: string) -> (),
	setVisible: (visible: boolean) -> (),
	setActive: (active: boolean) -> (), -- false — бледная, нажатия ничего не делают
	setProgress: (fraction: number?) -> (), -- полоска удержания внизу круга (nil — нет)
	setDot: (on: boolean) -> (),
	destroy: () -> (),
}

export type RoundProps = {
	name: string,
	icon: string?,
	label: string?,
	slot: string?, -- место справа (Mobile.slot); без него — сам ставь root.Position и root.Size
	parent: Instance?,
	color: Color3?, -- обводка круга
	onActivated: (() -> ())?,
	-- Для «держать» (умная кнопка, огонь): нажали / отпустили — даже если палец ушёл с кнопки
	onPress: (() -> ())?,
	onRelease: (() -> ())?,
}

function Mobile.roundButton(props: RoundProps): RoundButton
	local parent = props.parent
	if not parent then
		local _, frame = Mobile.gui()
		parent = frame
	end
	local color = props.color or Colors.Gold
	local button = Theme.new("TextButton", {
		Name = props.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Colors.Navy,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Active = true,
		Text = "",
		ZIndex = 2,
		Parent = parent,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local stroke = Theme.stroke(color, 2)
	stroke.Parent = button
	local scale = Theme.new("UIScale", { Parent = button })

	-- Иконка — в верхней части круга, подпись — внизу внутри круга (снаружи она налезла бы на соседнюю кнопку)
	local iconHolder = Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = button,
	}, { Theme.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	local label = Theme.pixelLabel({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(0.86, 0.17),
		TextScaled = true,
		ZIndex = 4,
		Parent = button,
	}, 10, 1)
	Theme.new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 12, Parent = label })

	local barBack = Theme.new("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.fromScale(0.5, 0.06),
		BackgroundColor3 = Colors.Dark,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = button,
	})
	local barFill = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Green,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = barBack,
	})

	local dot = PixelIcon.new("Dot", true, 6)
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.85, 0.15)
	dot.Size = UDim2.fromScale(0.26, 0.26)
	dot.Visible = false
	dot.Parent = button

	local currentIcon: string? = nil
	local function setIcon(icon: string?)
		if icon == currentIcon then
			return
		end
		currentIcon = icon
		iconHolder:ClearAllChildren()
		Theme.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = iconHolder })
		if icon and PixelIcon.Icons[icon] then
			local picture = PixelIcon.new(icon, true, 3)
			picture.Size = UDim2.fromScale(1, 1)
			picture.Parent = iconHolder
		end
	end
	setIcon(props.icon)
	label.Text = props.label or ""
	label.Visible = label.Text ~= ""
	iconHolder.Position = UDim2.fromScale(0.5, if label.Visible then 0.42 else 0.5)

	local active = true
	local function setActive(on: boolean)
		active = on
		button.BackgroundTransparency = if on then 0.3 else 0.7
		stroke.Color = if on then color else Colors.Gray
		stroke.Transparency = if on then 0 else 0.4
		iconHolder.Visible = on and currentIcon ~= nil
	end

	-- Нажатие: сжимается; «держать» — до отпускания пальца где угодно
	local holding: InputObject? = nil
	local function release()
		if holding then
			holding = nil
			local onRelease = props.onRelease
			if onRelease then
				onRelease()
			end
		end
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, button.InputBegan:Connect(function(input)
		local press = input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
		if not press or not active then
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = Config.PixelUI.PressScale }):Play()
		local onPress = props.onPress
		if onPress and not holding then
			holding = input
			PixelButton.click()
			onPress()
			local watch: RBXScriptConnection? = nil
			watch = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					if watch then
						watch:Disconnect()
					end
					if holding == input then
						release()
					end
				end
			end)
		end
	end))
	table.insert(conns, button.InputEnded:Connect(function(input)
		if holding == input then
			release()
		elseif input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end
	end))
	table.insert(conns, button.Activated:Connect(function()
		local onActivated = props.onActivated
		if onActivated and active then
			PixelButton.click()
			onActivated()
		end
	end))
	table.insert(conns, button:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Visible then
			release()
		end
	end))
	local slotName = props.slot
	if slotName then
		table.insert(conns, Mobile.place(button, slotName))
	end

	return {
		root = button,
		setIcon = function(icon: string?)
			setIcon(icon)
			iconHolder.Visible = active and currentIcon ~= nil
		end,
		setLabel = function(text: string)
			if label.Text ~= text then
				label.Text = text
			end
			local show = text ~= ""
			label.Visible = show
			iconHolder.Position = UDim2.fromScale(0.5, if show then 0.42 else 0.5)
		end,
		setVisible = function(visible: boolean)
			button.Visible = visible
		end,
		setActive = setActive,
		setProgress = function(fraction: number?)
			barBack.Visible = fraction ~= nil
			if fraction then
				barFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			end
		end,
		setDot = function(on: boolean)
			dot.Visible = on
		end,
		destroy = function()
			for _, conn in conns do
				conn:Disconnect()
			end
			button:Destroy()
		end,
	}
end

return Mobile
