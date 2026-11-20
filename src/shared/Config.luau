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

	Lighting = {
		Night = { -- первая ночь: снаружи темно, в зале свет включён
			ClockTime = 0,
			Brightness = 1,
			Ambient = Color3.fromRGB(150, 150, 165),
			OutdoorAmbient = Color3.fromRGB(150, 150, 165),
		},
		PaintingLight = { -- мягкая подсветка Моны Лизы, чтобы её было видно
			Range = 18,
			Brightness = 1.2,
			Color = Color3.fromRGB(255, 225, 170),
		},
	},
}

return Config
