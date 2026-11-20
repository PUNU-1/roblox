--!strict
-- Все числа игры живут здесь. В логике чисел быть не должно.

local Config = {
	Players = {
		Max = 4,
	},

	Phases = {
		PrepSeconds = 60, -- подготовка: расстановка ловушек
		NightSeconds = 300, -- ночь: 5 минут
	},

	Cameras = {
		Count = 4, -- 3-4 точки, переключение цифрами 1-4
	},

	Thief = {
		StealSeconds = 3, -- сколько вор хватает экспонат
	},

	Traps = {
		LaserGrid = {
			SlowSeconds = 5, -- замедление и подсветка вора
		},
	},
}

return Config
