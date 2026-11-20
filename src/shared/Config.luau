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
		DaySeconds = 90, -- день: туристы, покупки
		NightSeconds = 300, -- ночь: 5 минут
		ResultsSeconds = 10, -- экран итога, потом новый день или лобби
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
		HandcuffsOffset = Vector3.new(0.4, -0.2, 0.25), -- от левой кисти вора: между руками в позе ареста
	},

	Traps = {
		LaserGrid = {
			Enabled = false, -- до магазина сеток в игре нет (решение 43)
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
			FlashSeconds = 0.25, -- при срабатывании лучи вспыхивают и гаснут на перезарядку
			FlashColor = Color3.fromHex("FFFFFF"),
			FlashWidth = 0.6,
		},
	},

	Money = {
		PerThief = 50, -- баланс: долларов за пойманного вора, делятся поровну
		TicketPrice = 5, -- баланс: сколько платит турист за вход, делится поровну
	},

	Tourists = {
		BasePerDay = 8, -- баланс: туристов за день, когда в музее только Мона Лиза
		PerAppeal = 1, -- баланс: сколько туристов добавляет каждое очко привлекательности экспонатов
		MaxAlive = 8, -- одновременно в музее
		SpawnWindow = 0.7, -- приходят в первые 70% дня
		WalkSpeed = 7,
		VisitsMin = 2, -- сколько мест посмотрит
		VisitsMax = 4,
		AdmireMin = 3, -- сколько секунд смотрит на одно место
		AdmireMax = 6,
		PhotoChance = 0.4, -- как часто фотографирует
		ReachDistance = 3,
		WalkTimeout = 25, -- если турист застрял, через столько секунд идёт дальше
		UpdateSeconds = 0.2,
		WanderMin = Vector3.new(-42, 3, -28), -- где гуляет по залу, пока экспонатов мало
		WanderMax = Vector3.new(42, 3, 28),
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

	-- Анимации воров и туристов делаются кодом на клиенте (NpcAnimator.client.luau), в Roblox ничего не загружается.
	Animations = {
		BlendSpeed = 12, -- как быстро поза перетекает в новую (больше — резче)
		SneakStride = 0.5, -- радиан шага на стад пути: крадётся большими шагами
		RunStride = 0.62,
		StrollStride = 0.55, -- турист гуляет
		CullDistance = 160, -- дальше этого от камеры воров не анимируем
		StealLookSeconds = 1.0, -- кража: сначала оглядывается
		StealReachSeconds = 0.6, -- потом тянется к экспонату
		ArrestHandsUpSeconds = 0.3, -- арест: руки вверх
		ArrestCuffSeconds = 0.5, -- потом руки вперёд, в наручники
	},

	Lighting = {
		Day = { -- день: светло, туристы
			ClockTime = 14,
			Brightness = 2,
			Ambient = Color3.fromRGB(150, 150, 150),
			OutdoorAmbient = Color3.fromRGB(170, 170, 170),
		},
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

	Hints = {
		Rounds = 2, -- в скольких первых раундах игрок видит подсказки внизу экрана
	},

	Effects = {
		PoofSeconds = 0.4, -- облачко при аресте
		PoofSize = 6,
		MarkColor = Color3.fromHex("C8343A"),
		MarkStrokeColor = Color3.fromHex("FFFFFF"),
		MarkHeight = 4, -- стрелка метки над головой вора
		MarkSize = 70, -- размер стрелки в пикселях
		SlowHighlightColor = Color3.fromHex("C8343A"),
		BannerSeconds = 3,
		Spotted = { -- «!» над вором, который заметил охранника
			Seconds = 1.5,
			Height = 2.2, -- над центром головы, ниже стрелки метки
			Size = 1.6, -- в стадах
			MaxDistance = 100,
			Color = Color3.fromHex("FFD23F"),
		},
		Reward = { -- «+$50» над пойманным вором (размеры в стадах)
			Width = 3,
			Height = 1.2,
			StartHeight = 1.5, -- над центром головы
			EndHeight = 3.5, -- всплывает сюда, пока вор не исчез
			MaxDistance = 100,
			Color = Color3.fromHex("3FB56B"),
		},
		Tap = { -- круг на месте нажатия оператора (размеры в пикселях)
			Seconds = 0.45,
			StartSize = 16,
			EndSize = 70,
			TextSeconds = 0.9, -- сколько тает надпись «MARKED!»
		},
		StealBar = { -- полоска кражи над картиной (размеры в стадах)
			Width = 4,
			Height = 0.7,
			Gap = 1, -- над верхним краем рамы
			MaxDistance = 120, -- дальше не видно (камеры ближе)
		},
	},
}

return Config
