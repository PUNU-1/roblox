-- Вид от первого лица (решение 56). Режим LockFirstPerson ставится в трёх местах, чтобы точно сработал:
-- StarterPlayer (default.project.json), сервер (RoleService) и здесь, у самого игрока.
-- Ещё здесь:
--  • прицел в центре экрана вместо стрелки мыши;
--  • подсказки «Hold E» не перехватывают мышь (иначе камера перестаёт поворачиваться,
--    когда подсказка оказывается в центре экрана).
-- Там, где нужна мышь (лобби, список фраз, экран камер), курсор освобождают кнопки с Modal = true.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

local CROSSHAIR = "rbxasset://textures/MouseLockedCursor.png" -- встроенная картинка Roblox, загружать не нужно

-- С клавиатурой подсказки нажимают клавишей, мышью по ним кликать не нужно.
-- На телефоне подсказку нажимают пальцем — там всё оставляем как есть.
local keyboardPlayer = UserInputService.KeyboardEnabled or not UserInputService.TouchEnabled

local function fixPrompt(instance: Instance)
	if keyboardPlayer and instance:IsA("ProximityPrompt") then
		instance.ClickablePrompt = false
	end
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
