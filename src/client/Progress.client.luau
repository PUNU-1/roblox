-- Прогресс в музее (этап 6, блок H1): надписи LEVEL UP, «Quest done! +20», новое достижение, «понравился класс?»
-- после пробного забега. Всё рисует общий модуль UI/ProgressFx (тот же, что в хабе), решает сервер.

local UI = script.Parent:WaitForChild("UI")
local ProgressFx = require(UI:WaitForChild("ProgressFx"))

ProgressFx.start()
