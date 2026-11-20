-- Игровой цикл: Lobby → Prep → Night → Results.
-- Пока только строит карту-заглушку. Фазы — следующий шаг.

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

MapBuilder.build()
