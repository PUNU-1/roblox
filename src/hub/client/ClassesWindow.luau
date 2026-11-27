-- Окно CLASSES в хабе (этап 5, блок A, решение 75): те же 5 карточек классов (UI/ClassCards), что раньше всегда
-- висели внизу экрана. Открывается кнопкой CLASSES слева или клавишей C; пока окно открыто, работают клавиши 1–5.
-- Выбрал купленный класс — окно закрывается, сверху «Your class: Technician». Некупленный — открывается CLASS SHOP
-- на этом классе. Что можно, решает тот, кто создал окно (HubHUD: команда улетает — нельзя), и сервер.
-- Этап 6, блок H1: у новичка на некупленных карточках «TRY FREE (1)» — нажал, и этот класс летит с ним в музей
-- на один забег (бесплатный забег тратит музей, проверяя профиль).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ClassCards = require(UI:WaitForChild("ClassCards"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

local ClassesWindow = {}

local cards: ClassCards.Cards? = nil

local window = PixelWindow.new({
	name = "ClassesWindow",
	title = "CLASSES",
	width = 760,
	height = 390,
	onOpen = function()
		local current = cards
		if current then
			current.refresh(GameState.roleOf(localPlayer))
			current.setVisible(true)
		end
	end,
	onClose = function()
		local current = cards
		if current then
			current.setVisible(false) -- картинки не крутятся, пока окно закрыто
		end
	end,
})

-- onChoose — что делать при выборе карточки (клавиша 1–5 или нажатие); окно закрывает тот, кто выбрал.
function ClassesWindow.init(onChoose: (role: string) -> ())
	cards = ClassCards.new(window.content, touchOnly, onChoose, true, true) -- в хабе — «TRY FREE (1)» (этап 6, блок H1)
end

function ClassesWindow.refresh()
	local current = cards
	if current and window.isOpen() then
		current.refresh(GameState.roleOf(localPlayer))
	end
end

ClassesWindow.open = window.open
ClassesWindow.close = window.close
ClassesWindow.toggle = window.toggle
ClassesWindow.isOpen = window.isOpen

return ClassesWindow
