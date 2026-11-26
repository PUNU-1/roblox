-- Окно CLASSES в хабе (этап 5, блок A, решение 75): те же 5 карточек классов (UI/ClassCards), что раньше всегда
-- висели внизу экрана. Открывается кнопкой CLASSES слева или клавишей C; пока окно открыто, работают клавиши 1–5.
-- Выбрал купленный класс — окно закрывается, сверху «Your class: Technician». Некупленный — открывается CLASS SHOP
-- на этом классе. Что можно, решает тот, кто создал окно (HubHUD: команда улетает — нельзя), и сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared:WaitForChild("GameState"))
local UI = script.Parent:WaitForChild("UI")
local ClassCards = require(UI:WaitForChild("ClassCards"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

local localPlayer = Players.LocalPlayer
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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
	cards = ClassCards.new(window.content, touchOnly, onChoose, true)
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
