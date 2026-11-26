-- Вид от первого лица (решение 56). Режим LockFirstPerson ставится в трёх местах, чтобы точно сработал:
-- StarterPlayer (default.project.json), сервер (RoleService) и здесь, у самого игрока.
-- Ещё здесь:
--  • прицел в центре экрана вместо стрелки мыши;
--  • подсказки «Hold F» не перехватывают мышь (иначе камера перестаёт поворачиваться,
--    когда подсказка оказывается в центре экрана).
-- Там, где нужна мышь (список фраз, экран камер), курсор освобождают кнопки с Modal = true.
-- В лобби курсор не освобождается: до круга START SHIFT надо дойти, роль — клавишами 1 / 2.
--
-- Телефон (этап 5, блок D). Владелец проверил на телефоне: кнопки видно, а нажатия не работают. Причины:
--  1) LockFirstPerson запирает «мышь» в центре экрана (MouseBehavior = LockCenter) и на телефоне тоже.
--     Касание кнопок на экране при этом может засчитываться в центре экрана, а не под пальцем.
--     Лечится так же, как список фраз: пока на экране видна кнопка с Modal = true, курсор свободен.
--     На телефоне такая невидимая кнопка висит всегда (камеру там крутят пальцем, мышь не нужна).
--  2) Телефон определялся как «TouchEnabled and not KeyboardEnabled», а многие Android-телефоны говорят
--     KeyboardEnabled = true. Тогда здесь подсказкам F отключалось нажатие пальцем (ClickablePrompt = false),
--     а кнопки ContextActionService не создавались. Теперь — Theme.touchOnly().

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

local CROSSHAIR = "rbxasset://textures/MouseLockedCursor.png" -- встроенная картинка Roblox, загружать не нужно

-- С клавиатурой подсказки нажимают клавишей, мышью по ним кликать не нужно.
-- На телефоне подсказку нажимают пальцем — там нажатие пальцем включено всегда.
local touchOnly = Theme.touchOnly()

local function fixPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.ClickablePrompt = touchOnly
	end
end

if touchOnly then
	-- Невидимая кнопка с Modal = true: пока она на экране, Roblox не запирает курсор в центре,
	-- и касание попадает в кнопку под пальцем. Сама касаний не ловит (Active = false, размер 0).
	local gui = Theme.screenGui("TouchUnlock", 0)
	Theme.new("TextButton", {
		Name = "Unlock",
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Active = false,
		Selectable = false,
		AutoButtonColor = false,
		Modal = true,
		Parent = gui,
	})
end

for _, descendant in Workspace:GetDescendants() do
	fixPrompt(descendant)
end
Workspace.DescendantAdded:Connect(fixPrompt)

-- Прицел, пока мышь заперта в центре; обычная стрелка, когда курсор свободен
local currentIcon: string? = nil
RunService.RenderStepped:Connect(function()
	local icon = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then CROSSHAIR else ""
	if icon ~= currentIcon then
		currentIcon = icon
		UserInputService.MouseIcon = icon
	end
end)
