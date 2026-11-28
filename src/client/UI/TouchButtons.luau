-- Круглые кнопки справа на телефоне (этап 5, блок D; этап 8, блок Q — раскладка «одна умная кнопка»).
-- Справа одновременно не больше 4 круглых кнопок: умная (SmartButton.client), оружие (колесо, Weapons.client),
-- маленькая R (Weapons.client) и умение класса или телефон оператора (Abilities.client, CameraController.client).
-- Места считает UI/Mobile от кнопки прыжка Roblox: "Smart", "Wheel", "Reload", "Ability". Всё остальное — в «Меню».
-- Клавиши остаются на ContextActionService (без кнопки на экране), эти кнопки вызывают те же функции.

local Mobile = require(script.Parent:WaitForChild("Mobile"))

local TouchButtons = {}

export type TouchButton = {
	root: TextButton,
	setVisible: (visible: boolean) -> (),
	setLabel: (text: string) -> (),
	setIcon: (icon: string?) -> (),
	setActive: (active: boolean) -> (),
	setColor: (color: Color3) -> (),
}

export type Props = {
	place: string, -- место: "Wheel" | "Reload" | "Ability" (UI/Mobile)
	icon: string,
	label: string,
	onActivated: (() -> ())?,
	onPress: (() -> ())?,
	onRelease: (() -> ())?,
}

function TouchButtons.new(props: Props): TouchButton
	local round = Mobile.roundButton({
		name = "Touch" .. props.place,
		icon = props.icon,
		label = props.label,
		slot = props.place,
		onActivated = props.onActivated,
		onPress = props.onPress,
		onRelease = props.onRelease,
	})
	round.root.Visible = false
	return {
		root = round.root,
		setVisible = round.setVisible,
		setLabel = round.setLabel,
		setIcon = round.setIcon,
		setActive = round.setActive,
		setColor = round.setColor,
	}
end

return TouchButtons
