--!strict
-- Все числа игры живут здесь. В логике чисел быть не должно.
-- Числа баланса пока поставил Claude (помечены «баланс»). Друг предложит свои — см. TEAM_PLAN.md.

local Config = {
	Players = {
		Max = 5, -- больше игроков в одной игре не бывает (решение 52)
		VoteSeconds = 15, -- сколько длится голосование за опоздавшего
		WalkSpeed = 16, -- скорость патруля (стандарт Roblox)
		JumpHeight = 7.2, -- стандарт Roblox
	},

	Lobby = { -- круг START SHIFT в комнате охраны (блок B1): встал в круг — ты в команде
		-- В команде не больше Config.Players.Max (5) игроков
		CircleRadius = 6, -- стадов от центра круга до края (считаем по HumanoidRootPart)
		CircleHeight = 12, -- выше этого над кругом не считается (прыжок из команды не выкидывает)
		CountdownSeconds = 15, -- отсчёт, пока в круге хоть один игрок
		AllInSeconds = 5, -- если в круге все игроки сервера, отсчёт сокращается до стольки
		CheckSeconds = 0.2, -- как часто сервер проверяет, кто в круге
		Color = Color3.fromHex("3BC6C1"), -- круг ждёт игроков
		FullColor = Color3.fromHex("C8343A"), -- команда полная, а ты не в ней
		IdleColor = Color3.fromHex("4A5266"), -- команда на смене, круг не работает
		PulseSeconds = 1.2, -- круг мягко мерцает
		PulseTransparency = 0.45, -- насколько прозрачным становится на мерцании
		LightRange = 14, -- свет от круга на пол
		LightBrightness = 1.5,
		LabelHeight = 7, -- табличка «Team N/5» над кругом
		LabelMaxDistance = 90,
	},

	Phases = {
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
		Count = 6, -- по 2 камеры на зал, переключение цифрами 1-6
		StaticSeconds = 0.3, -- помеха при переключении
		FieldOfView = 80,
		Names = { "Mona Lisa", "Main Hall North", "Jewelry Window", "Jewelry Hall", "Sculpture Door", "Sculpture Hall" },
		NightSaturation = -1, -- ночью картинка чёрно-белая
		NightContrast = 0.25,
		NightExposure = 3.5, -- ночное видение: камеры видят в темноте (яркость картинки ×2^3.5)
		ConsoleHoldSeconds = 0.5, -- сколько держать E у пульта
		ConsolePromptDistance = 8,
		RepairHoldSeconds = 2, -- сколько держать F у пульта, чтобы перезапустить сломанные камеры
	},

	Difficulty = { -- каждая следующая ночь сложнее (решение 50)
		ExtraThievesPerNight = 1, -- баланс: на сколько воров больше каждую ночь
		SpeedGrowthPerNight = 0.04, -- баланс: воры быстрее на 4% каждую ночь
		MaxSpeedMultiplier = 1.3, -- но не быстрее, чем в 1,3 раза
		IntervalShrinkPerNight = 0.05, -- паузы между ворами короче на 5% каждую ночь
		MinIntervalMultiplier = 0.6,
	},

	CameraBreaker = { -- вор, который выключает камеру
		FromNight = 3, -- баланс: с какой ночи появляется
		Chance = 0.3, -- баланс: какая доля воров — взломщики
		BreakSeconds = 2, -- сколько ломает камеру
		StandInset = 3, -- встаёт под камерой, чуть ближе к середине зала
		Color = Color3.fromHex("5A1A1A"), -- тёмно-красный костюм, чтобы отличался
	},

	Halls = {
		Jewelry = { Price = 400, Title = "JEWELRY HALL" }, -- баланс: цена зала
		Sculptures = { Price = 600, Title = "SCULPTURE HALL" },
		ContributeStep = 50, -- сколько вкладывает одно удержание E (или сколько осталось денег)
		ContributeHoldSeconds = 0.5,
		PromptDistance = 10,
		BoardsFallSeconds = 1.2, -- доски падают, когда зал оплачен
	},

	Exhibits = {
		MonaLisaChance = 0.5, -- баланс: как часто вор идёт за Моной Лизой, если есть другие экспонаты
		PedestalHeight = 3.3, -- верх постамента
		HideDepth = 200, -- пока вор несёт копию экспоната, настоящий спрятан на столько стадов под картой
		-- Экспонат для каждого постамента (атрибут Slot у постамента)
		Slots = { "GoldVase", "AncientClock", "Necklace", "Crown", "Scepter", "Diamond", "Amphora", "Bust", "Statue", "Lion" },
		-- баланс: цена и привлекательность (сколько туристов добавляет за день)
		Kinds = {
			GoldVase = { Title = "Golden Vase", Price = 120, Appeal = 1 },
			AncientClock = { Title = "Ancient Clock", Price = 180, Appeal = 2 },
			Necklace = { Title = "Necklace", Price = 100, Appeal = 1 },
			Crown = { Title = "Crown", Price = 150, Appeal = 2 },
			Scepter = { Title = "Scepter", Price = 200, Appeal = 2 },
			Diamond = { Title = "Diamond", Price = 300, Appeal = 3 },
			Amphora = { Title = "Amphora", Price = 100, Appeal = 1 },
			Bust = { Title = "Bust", Price = 150, Appeal = 2 },
			Statue = { Title = "Statue", Price = 250, Appeal = 3 },
			Lion = { Title = "Stone Lion", Price = 300, Appeal = 3 },
		},
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
		PerNight = { 6, 8, 10, 12, 14 }, -- баланс: сколько воров в первую ночь при 1-5 игроках
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
		LaserGrid = { -- лазерная сетка вокруг экспоната (покупается в магазине, решение 43)
			Price = 150, -- баланс
			SlowSeconds = 5, -- замедление и подсветка вора
			RechargeSeconds = 10, -- баланс: перезарядка после срабатывания
			CheckSeconds = 0.1, -- как часто сетка проверяет воров
			TriggerRadius = 3.4, -- вор ближе этого к центру сетки — срабатывание
			FenceHalf = 2.6, -- половина стороны квадрата стоек вокруг постамента
			MainFenceWidth = 7, -- у Моны Лизы сетка перед картиной
			MainFenceDepth = 4,
			MainTriggerRadius = 4.2,
			PostHeight = 3,
			BeamHeights = { 1, 2.2 },
			BeamWidth = 0.15,
			BeamColor = Color3.fromHex("C8343A"),
			FlashSeconds = 0.25, -- при срабатывании лучи вспыхивают и гаснут на перезарядку
			FlashColor = Color3.fromHex("FFFFFF"),
			FlashWidth = 0.6,
		},
		Alarm = { -- сигнализация на Мону Лизу
			Price = 200, -- баланс
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
		WanderInset = 6, -- гуляет по открытым залам, не ближе этого к стенам
		LeaveBeforeNightSeconds = 10, -- за столько секунд до ночи музей закрывается: все туристы идут к выходу
		LeaveWalkSpeed = 11, -- к выходу идут быстрее, чтобы успеть до ночи
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

	-- Звуки. ВСЕ ВРЕМЕННЫЕ: подобрал Claude из открытой библиотеки Roblox (ProSoundEffects, DistrokidOfficial),
	-- владелец и друг заменят на свои (GEMINI.md, задание 18). Номер вставляется как "rbxassetid://НОМЕР".
	-- Пустая строка "" — звука нет.
	Sounds = {
		ThiefStep = "rbxasset://sounds/action_footsteps_plastic.mp3", -- ВРЕМЕННЫЙ: стандартные шаги Roblox
		Alarm = "rbxassetid://9125544264", -- ВРЕМЕННЫЙ: Elevator Alarm Bell (кража, лазерная сетка, сигнализация)
		NightMusic = "rbxassetid://131411533631277", -- ВРЕМЕННЫЙ: Sneaky Mischief (крадущаяся мультяшная музыка)
		DayMusic = "rbxassetid://79463407625396", -- ВРЕМЕННЫЙ: Easy Listening Positive Jazz (спокойный день)
		Arrest = "rbxassetid://9114763696", -- ВРЕМЕННЫЙ: Handcuff Movement 4 (наручники)
		Purchase = "rbxassetid://9113728042", -- ВРЕМЕННЫЙ: Cash Register 1 (вклад денег, билет туриста)
		HallOpen = "rbxassetid://9120805690", -- ВРЕМЕННЫЙ: Wood Break Door Cracks (доски падают)
		CameraBreak = "rbxassetid://9114277402", -- ВРЕМЕННЫЙ: Electric Zaps 6 (вор сломал камеру)
		CameraSwitch = "rbxassetid://9120484192", -- ВРЕМЕННЫЙ: Wall Light Switch (переключение камер, слышит только смотрящий)
		StepVolume = 0.6,
		StepRollOff = 30, -- шаги слышно только рядом
		EffectRollOff = 60, -- звуки у деталей (касса, доски, камера) слышно в этом радиусе
		MusicVolume = 0.3,
		AlarmVolume = 0.8,
		AlarmSeconds = 4, -- сирена обрывается через столько секунд
		ArrestVolume = 0.8,
		PurchaseVolume = 0.6,
		TicketVolume = 0.35, -- касса у входа, когда платит турист (туристов много — тише)
		HallOpenVolume = 0.9,
		CameraBreakVolume = 0.8,
		CameraSwitchVolume = 0.4,
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
		Lobby = { -- комната охраны перед первым днём: вечер
			ClockTime = 18,
			Brightness = 1.5,
			Ambient = Color3.fromRGB(130, 125, 120),
			OutdoorAmbient = Color3.fromRGB(140, 135, 130),
		},
		Day = { -- день: светло, туристы
			ClockTime = 14,
			Brightness = 2,
			Ambient = Color3.fromRGB(150, 150, 150),
			OutdoorAmbient = Color3.fromRGB(170, 170, 170),
		},
		Night = { -- ночью темно (решение 57): дежурные лампы, подсветка Моны Лизы и фонарики
			ClockTime = 0,
			Brightness = 0,
			Ambient = Color3.fromRGB(12, 13, 20), -- баланс: насколько темно (больше — светлее)
			OutdoorAmbient = Color3.fromRGB(12, 13, 20),
		},
		NightLamp = { -- тусклые синие дежурные лампы на стенах залов и в коридоре
			Range = 12,
			Brightness = 0.6,
			Color = Color3.fromRGB(120, 150, 255),
		},
		Chandelier = { -- люстры в залах, горят только днём
			Range = 36,
			Brightness = 1.3,
			Color = Color3.fromRGB(255, 226, 170),
		},
		LobbyLamp = { -- тёплая лампа в комнате охраны (опоздавшие ждут тут и ночью)
			Range = 30,
			Brightness = 1.2,
			Color = Color3.fromRGB(255, 220, 170),
		},
		PaintingLight = { -- мягкая подсветка Моны Лизы, чтобы её было видно
			Range = 18,
			Brightness = 1.2,
			Color = Color3.fromRGB(255, 225, 170),
		},
	},

	Flashlight = { -- фонарик охранника ночью (решение 57), горит всегда, пока ты на смене
		Range = 40, -- баланс: как далеко светит свой фонарик
		Angle = 45, -- ширина луча в градусах
		Brightness = 3,
		Color = Color3.fromRGB(255, 244, 214),
		OthersRange = 30, -- фонарики других охранников (свет из головы), без теней
		OthersBrightness = 2,
		HandOffset = CFrame.new(0.5, -0.4, 0), -- свой фонарик чуть правее и ниже глаз
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
