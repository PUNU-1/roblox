--!strict
-- Все числа игры живут здесь. В логике чисел быть не должно.
-- Числа баланса пока поставил Claude (помечены «баланс»). Друг предложит свои — см. TEAM_PLAN.md.

local Config = {
	Players = {
		Max = 4,
		WalkSpeed = 16, -- скорость патруля (стандарт Roblox)
		JumpHeight = 7.2, -- стандарт Roblox
	},

	Phases = {
		LobbyCountdownSeconds = 30, -- отсчёт после первого READY
		PrepSeconds = 60, -- подготовка: расстановка ловушек
		NightSeconds = 300, -- ночь: 5 минут
		ResultsSeconds = 10, -- экран итога, потом лобби
		TickSeconds = 0.25, -- как часто игровой цикл проверяет состояние
	},

	Clock = {
		StartHour = 0, -- ночь идёт с 00:00
		EndHour = 6, -- до 06:00
	},

	Cameras = {
		Count = 4, -- 3-4 точки, переключение цифрами 1-4
		StaticSeconds = 0.3, -- помеха при переключении
		FieldOfView = 80,
		Names = { "West Door", "South Hatch", "North Corridor", "East Window" },
		NightSaturation = -1, -- ночью картинка чёрно-белая
		NightContrast = 0.15,
		ConsoleHoldSeconds = 0.5, -- сколько держать E у пульта
		ConsolePromptDistance = 8,
	},

	Thief = {
		StealSeconds = 3, -- сколько вор снимает картину
		SneakSpeed = 12, -- баланс: пока крадётся к картине
		RunSpeed = 15, -- баланс: убегает без картины (патруль 16)
		CarrySpeed = 11, -- баланс: бежит с картиной
		SlowMultiplier = 0.5, -- во сколько раз медленнее после лазерной сетки
		FleeRadius = 12, -- баланс: на каком расстоянии замечает охранника
		FleeSeconds = 3, -- сколько убегает, прежде чем снова пойти к картине
		FleeDistance = 20, -- насколько далеко пытается отбежать
		BlockDistance = 6, -- где встаёт загораживать: столько стадов от несущего в сторону охранника
		PerNight = { 6, 8, 10, 12 }, -- баланс: сколько воров за ночь при 1/2/3/4 игроках
		MaxAliveExtra = 1, -- одновременно в зале не больше «игроки + 1»
		FirstSpawnMin = 15, -- первый вор через 15-30 сек после начала ночи
		FirstSpawnMax = 30,
		IntervalStart = 40, -- баланс: пауза между ворами в начале ночи
		IntervalEnd = 15, -- баланс: и в конце ночи
		IntervalJitter = 0.3, -- случайный разброс паузы ±30%
		UpdateSeconds = 0.1, -- как часто обновляется поведение воров
		PathRecomputeSeconds = 0.6, -- как часто пересчитывается путь
		PathRecomputeDistance = 4, -- или если цель сдвинулась на столько стадов
		WaypointReachDistance = 2.5,
		StealReachDistance = 3, -- на каком расстоянии от картины можно начать кражу
		EscapeReachDistance = 4, -- на каком расстоянии от выхода вор считается сбежавшим
		StandOffset = 2.5, -- насколько перед картиной встаёт вор
		ArrestSeconds = 1.5, -- руки вверх -> наручники -> пуф
		Color = Color3.fromHex("151515"), -- вор весь в чёрном
	},

	Painting = {
		CarryOffset = Vector3.new(0, 0.8, 0.3), -- где картина относительно головы вора
	},

	Catch = {
		HoldSeconds = 1, -- удержание кнопки для ареста
		MaxDistance = 8, -- дальше подсказка пропадает, удержание сбрасывается
		ServerDistanceSlack = 3, -- запас на задержку сети при проверке на сервере
		HandcuffsOffset = Vector3.new(0, 2, 0), -- наручники над головой (руки вора подняты)
	},

	Traps = {
		LaserGrid = {
			MaxPerNight = 3, -- 3 сетки из 5 мест
			PlaceHoldSeconds = 1, -- сколько держать E, чтобы поставить
			PromptDistance = 10,
			RiseSeconds = 0.6, -- стойки вырастают из пола
			RiseDepth = 6,
			SlowSeconds = 5, -- замедление и подсветка вора
			RechargeSeconds = 10, -- баланс: перезарядка после срабатывания
			CheckSeconds = 0.1, -- как часто сетка проверяет, не прошёл ли вор
			BeamWidth = 0.15,
			BeamColor = Color3.fromHex("C8343A"),
			ZoneHeight = 5, -- высота невидимой зоны срабатывания
			ZoneThickness = 1.5,
			SlotGlowTransparency = 0.4, -- как светятся места в подготовке
		},
	},

	Money = {
		PerThief = 50, -- баланс: долларов за пойманного вора, делятся поровну
	},

	Comms = {
		MarkSeconds = 6, -- баланс: сколько висит метка оператора
		MarkCooldown = 1,
		MarkMaxDistance = 150, -- дальше этого от камеры метку поставить нельзя
		MarkTapRadius = 60, -- в пикселях: насколько можно промахнуться мимо вора на картинке с камеры
		PhraseCooldown = 2,
		PhraseShowSeconds = 5,
		Phrases = {
			"Thief at the painting!",
			"Thief at the door!",
			"Thief at the window!",
			"Thief at the hatch!",
			"I'm coming!",
			"Help me!",
		},
	},

	Uniform = {
		Torso = Color3.fromHex("1E2A44"), -- тёмно-синяя форма
		Arms = Color3.fromHex("1E2A44"),
		Legs = Color3.fromHex("2A2F3A"),
	},

	-- Номера звуков. 0 — звука пока нет (друг подберёт, задание 18).
	Sounds = {
		ThiefStep = 0,
		Alarm = 0,
		NightMusic = 0,
		Arrest = 0,
		StepVolume = 0.6,
		StepRollOff = 30, -- шаги слышно только рядом
		MusicVolume = 0.3,
		AlarmVolume = 0.8,
		ArrestVolume = 0.8,
	},

	-- Номера анимаций. Стандартные анимации Roblox можно использовать в любой игре.
	-- Анимации от Gemini (задания 14-17) владелец загрузит и впишет сюда; 0 — пока нет.
	Animations = {
		Walk = 507777826, -- стандартная ходьба R15
		Run = 507767714, -- стандартный бег R15
		ThiefSneak = 0,
		ThiefSteal = 0,
		ThiefCarry = 0,
		ThiefArrest = 0,
		RunSpeedThreshold = 13, -- быстрее этого играет бег, медленнее — ходьба
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

	Effects = {
		PoofSeconds = 0.4, -- облачко при аресте
		PoofSize = 6,
		MarkColor = Color3.fromHex("C8343A"),
		MarkHeight = 4, -- стрелка метки над головой вора
		MarkSize = 70, -- размер стрелки в пикселях
		SlowHighlightColor = Color3.fromHex("C8343A"),
		BannerSeconds = 3,
	},
}

return Config
