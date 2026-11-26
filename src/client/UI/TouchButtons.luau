-- Кнопки на экране телефона (этап 5, блок D): умение, телефон оператора, присед, наклон, перезарядка, FIRE.
-- Раньше это были круглые кнопки ContextActionService. Теперь — пиксельные кнопки (UI/PixelButton) в своём
-- ScreenGui: в том же стиле, что весь интерфейс, и на месте, которое мы знаем (кнопки ContextActionService лежат
-- в TouchGui Roblox под нашими ScreenGui, и наши кнопки, оказавшиеся сверху, съедали касание).
-- Клавиши остаются на ContextActionService (без кнопки на экране), эти кнопки вызывают те же функции.
-- Места — Config.PixelUI.Touch.Positions, от правого нижнего угла экрана.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelButton = require(script.Parent:WaitForChild("PixelButton"))

local Settings = Config.PixelUI.Touch

local TouchButtons = {}

export type TouchButton = {
	button: PixelButton.IconButton,
	setVisible: (visible: boolean) -> (),
	setLabel: (text: string) -> (),
	setIcon: (icon: string) -> (),
}

export type Props = {
	place: string, -- ключ в Config.PixelUI.Touch.Positions
	icon: string,
	label: string,
	big: boolean?, -- FIRE — крупнее
	onActivated: (() -> ())?,
	onPress: (() -> ())?,
	onRelease: (() -> ())?,
}

local gui: ScreenGui? = nil
local function screen(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	-- DisplayOrder 3: над HUD и экраном камер (2), под окном магазина (4) и голосованием (5)
	local created = Theme.screenGui("TouchButtons", 3)
	gui = created
	return created
end

function TouchButtons.new(props: Props): TouchButton
	local cell = if props.big then Settings.FireCell else Settings.Cell
	local offset = Settings.Positions[props.place] or Vector2.new(200, 106)
	local button = PixelButton.new({
		icon = props.icon,
		label = props.label,
		cell = cell,
		width = 16 * cell + 2 * cell + 4,
		name = "Touch" .. props.place,
		zIndex = 2,
		onActivated = props.onActivated,
		onPress = props.onPress,
		onRelease = props.onRelease,
	})
	button.root.AnchorPoint = Vector2.new(1, 1)
	button.root.Position = UDim2.new(1, -offset.X, 1, -offset.Y)
	button.root.Visible = false
	button.root.Parent = screen()
	return {
		button = button,
		setVisible = function(visible: boolean)
			button.root.Visible = visible
		end,
		setLabel = button.setLabel,
		setIcon = button.setIcon,
	}
end

return TouchButtons
