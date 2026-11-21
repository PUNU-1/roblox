--!strict
-- Все числа игры живут здесь. В логике чисел быть не должно.
-- Числа баланса пока поставил Claude (помечены «баланс»). Друг предложит свои — см. TEAM_PLAN.md.

local Config = {
	Keys = { -- клавиши (решение 67); Q / E / C пока свободны — под наклоны и присед (блок 4)
		Action = Enum.KeyCode.F, -- все кнопки у предметов (ProximityPrompt): покупка, арест, пульт; геймпад — как было (X)
		Phrases = Enum.KeyCode.T, -- открыть список готовых фраз (пока он открыт — цифры)
	},

	Purchase = { -- покупка одним удержанием F (решение 67): хватает денег — покупаешь сразу, нет — всё в полоску
		HoldSeconds = 1, -- сколько держать F
		PromptDistance = 10, -- с какого расстояния видно кнопку покупки
	},

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

	Phases = { -- дни и ночи растут с каждым днём забега (решение 66)
		DayFirstSeconds = 30, -- 1-й день: туристы, покупки
		DayGrowSeconds = 10, -- каждый следующий день длиннее на столько
		DayMaxSeconds = 60, -- но не длиннее
		NightFirstSeconds = 120, -- 1-я ночь: 2 минуты
		NightGrowSeconds = 30, -- каждая следующая ночь длиннее на столько
		NightMaxSeconds = 300, -- но не длиннее 5 минут
		ResultsSeconds = 10, -- экран итога, потом новый день или лобби
		TickSeconds = 0.25, -- как часто игровой цикл проверяет состояние
	},

	Clock = { -- часы ночи всегда идут 00:00 -> 06:00, как бы долго ни шла ночь
		StartHour = 0, -- ночь идёт с 00:00
		EndHour = 6, -- до 06:00
	},

	Cameras = { -- 12 мест для камер (блок 2): первая бесплатная, остальные покупаются
		Price = 50, -- баланс: цена одной камеры (удержание F у таблички CAMERA SPOT, можно вскладчину)
		FreeIndices = { 1 }, -- эти камеры работают сразу и бесплатно (1 — на Мону Лизу)
		InstallSeconds = 0.6, -- купленная камера плавно выезжает на кронштейн
		PlaqueColor = Color3.fromHex("D4A93A"), -- табличка CAMERA SPOT: место свободно
		PlaqueOwnedColor = Color3.fromHex("3FB56B"), -- камера куплена
		StaticSeconds = 0.3, -- помеха при переключении
		FieldOfView = 80,
		-- Имена по номерам (номер места = порядок в MapBuilder)
		Names = {
			"Mona Lisa",
			"Center Hall",
			"South Entrance",
			"West Entrance",
			"North Entrance",
			"East Entrance",
			"Sculpture Hall",
			"Dinosaur Hall",
			"Jewelry Hall",
			"Space Hall",
			"Jewelry Vault",
			"Space Rocket",
		},
		NightSaturation = -1, -- ночью картинка чёрно-белая
		NightContrast = 0.25,
		NightExposure = 3.5, -- ночное видение: камеры видят в темноте (яркость картинки ×2^3.5)
		ConsoleHoldSeconds = 0.5, -- сколько держать F у пульта
		ConsolePromptDistance = 8,
		RepairHoldSeconds = 2, -- сколько держать F у рубильника рядом с пультом, чтобы перезапустить сломанные камеры
		-- Рубильник «перезапуск камер» справа от пульта: у него своя кнопка F, на пульте — «Watch cameras»
		-- (на одну клавишу Roblox показывает одну ближайшую кнопку)
		ResetSwitchGap = 0.6, -- от правого края пульта
		ResetSwitchSize = Vector3.new(1.4, 3.2, 1.2),
		ResetSwitchColor = Color3.fromHex("2B2F3A"),
		ResetLampOffColor = Color3.fromHex("4A1C1E"), -- все камеры работают
		ResetLampOnColor = Color3.fromHex("FF3B3B"), -- есть сломанные: лампа горит, пора перезапускать
	},

	Difficulty = { -- каждая следующая ночь сложнее (решение 50); число воров — Thief.PerPlayer*
		SpeedGrowthPerNight = 0.04, -- баланс: воры быстрее на 4% каждую ночь
		MaxSpeedMultiplier = 1.3, -- но не быстрее, чем в 1,3 раза
	},

	-- Виды воров по порядку появления (блок 3): новый вид каждые 2 ночи, перед ночью надпись NEW THIEF
	ThiefOrder = { "Pickpocket", "Breaker", "Brute", "Shadow", "Miner", "Glazier", "Cutter" },
	ThiefTypes = {
		-- Title — имя в надписи NEW THIEF; FromNight — с какой ночи приходит (баланс);
		-- Weight — как часто попадается среди обычных воров волны; SpeedMul — скорость от обычного вора;
		-- Door = false — приходит не через дверь (подкоп, крыша), такого не ставят в «клещи» и т.п.
		Pickpocket = { -- обычный вор в маске
			Title = "PICKPOCKET",
			FromNight = 1,
			Weight = 3,
			SpeedMul = 1,
			Door = true,
			Color = Color3.fromHex("151515"), -- весь в чёрном
		},
		Breaker = { -- Взломщик: ломает ближайшую камеру, потом крадёт как обычный
			Title = "CAMERA BREAKER",
			FromNight = 3,
			Weight = 1.2,
			SpeedMul = 1,
			Door = true,
			Color = Color3.fromHex("5A1A1A"), -- тёмно-красный костюм, чтобы отличался
			BreakSeconds = 2, -- сколько ломает камеру (встаёт на полу под кронштейном камеры)
		},
		Brute = { -- Громила: большой и медленный, не убегает, бьёт охранника спереди, бьёт витрины
			Title = "BRUTE",
			FromNight = 5,
			Weight = 1,
			SpeedMul = 0.8, -- баланс: медленнее обычного вора
			Door = true,
			NoFlee = true, -- не убегает от охраны
			WalkAnim = "Stomp", -- тяжёлая походка (и когда бежит)
			RunAnim = "Stomp",
			Scale = 1.18, -- крупнее обычного вора
			Width = 1.22, -- и шире в плечах
			Skin = Color3.fromHex("D9A27A"),
			Shirt = Color3.fromHex("ECECEC"), -- белая майка
			Pants = Color3.fromHex("2F3B52"),
			PunchRange = 6, -- баланс: охранник ближе этого и спереди — получает удар
			PunchCone = 0.3, -- «спереди»: угол до ~72° от того, куда смотрит Громила
			PunchWindup = 0.4, -- замах (охранник успевает отпрыгнуть)
			PunchSeconds = 1, -- весь удар с возвратом
			PunchCooldown = 2.5, -- бьёт не чаще (поэтому вдвоём его можно взять)
			KnockSeconds = 3, -- баланс: охранник лежит столько секунд
			SmashChance = 0.4, -- баланс: как часто Громила без плана сначала разбивает витрину
			SmashSeconds = 2.2, -- сколько бьёт витрину (два удара)
		},
		Shadow = { -- Тень: весь в чёрном, шагов не слышно, в темноте почти не виден
			Title = "SHADOW",
			FromNight = 7,
			Weight = 1.5,
			SpeedMul = 1,
			Door = true,
			Silent = true,
			WalkAnim = "Prowl", -- крадётся на полусогнутых
			Color = Color3.fromHex("1C1C24"), -- не совсем чёрный: в луче фонарика его видно
			Hoodie = Color3.fromHex("202029"),
		},
		Miner = { -- Шахтёр: копает подкоп и вылезает из пола рядом с экспонатом
			Title = "MINER",
			FromNight = 9,
			Weight = 0.7,
			SpeedMul = 1,
			Door = false, -- приходит из-под пола
			Skin = Color3.fromHex("E8B48C"),
			Shirt = Color3.fromHex("6B7A8F"), -- рукава рубашки
			Overalls = Color3.fromHex("2E4A7D"), -- синий комбинезон
			Helmet = Color3.fromHex("F2C230"),
			DigSeconds = 60, -- баланс: сколько копает (не видно и не слышно)
			DigJitter = 8, -- ± случайно, чтобы шахтёры волны вылезали не в одну секунду
			CrackSeconds = 2.5, -- за столько секунд до появления пол трескается, гул и пыль
			EmergeSeconds = 1.8, -- вылезает из дыры
			EmergeDepth = 5.5, -- начинает вылезать с такой глубины под полом
			EmergeDistance = 6, -- дыра на таком расстоянии от экспоната
			LampRange = 18, -- фонарь на каске
			LampBrightness = 1.6,
			LampAngle = 50,
		},
		Glazier = { -- Стекольщик: режет стеклянный потолок центра и спускается на верёвке к Моне Лизе
			Title = "GLASS CUTTER",
			FromNight = 11,
			Weight = 0.5,
			SpeedMul = 1,
			Door = false, -- приходит по крыше
			NoFlee = true, -- раз уж спустился, идёт до конца
			Skin = Color3.fromHex("E8B48C"),
			Suit = Color3.fromHex("22262E"),
			Harness = Color3.fromHex("F28C28"),
			Helmet = Color3.fromHex("F2F4F7"),
			CutSeconds = 5, -- баланс: режет круг в стекле
			HoleRadius = 2, -- радиус дыры
			WaitMax = 30, -- баланс: ждёт на крыше, пока охрана отойдёт от места спуска, не дольше
			ClearRadius = 22, -- спускается, когда охраны ближе этого к месту спуска нет
			DescendSeconds = 4, -- спуск на верёвке
			ClimbSeconds = 7, -- баланс: подъём с добычей (снизу его ещё можно успеть арестовать)
			LandOffset = 2.5, -- приземляется перед экспонатом на столько дальше места вора
			SkylightMargin = 3, -- дыра не ближе этого к раме стеклянного потолка
		},
		Cutter = { -- Светорез: вырубает у щитка POWER свет и камеры во всём музее
			Title = "POWER CUTTER",
			FromNight = 13,
			Weight = 0.5,
			SpeedMul = 1,
			Door = true,
			Skin = Color3.fromHex("C98E66"),
			Coverall = Color3.fromHex("46505E"),
			Cap = Color3.fromHex("1E2A44"),
			Stripe = Color3.fromHex("F2C230"),
			WorkSeconds = 4, -- баланс: сколько возится у щитка
		},
	},

	Blackout = { -- блэкаут (Светорез): гаснут дежурные лампы, подсветка Моны Лизы и все камеры
		RestoreHoldSeconds = 2, -- сколько держать F у щитка POWER, чтобы вернуть свет
		PromptDistance = 8,
		Flickers = 4, -- перед тем как погаснуть, лампы мигают
		FlickerSeconds = 0.12,
		StandOffset = 2.6, -- Светорез встаёт перед щитком на столько стадов
		SparkColor = Color3.fromHex("FFD866"),
		LampOkColor = Color3.fromHex("3FB56B"), -- лампочка на щитке: свет есть
		LampOutColor = Color3.fromHex("FF3B3B"), -- свет вырубили
	},

	Knockdown = { -- охранник от удара Громилы падает на спину и встаёт (анимация — Guards.client)
		FallSeconds = 0.35, -- падает
		RiseSeconds = 0.7, -- встаёт в конце
		Tilt = 1.45, -- насколько заваливается назад (радианы: 1.57 — совсем плашмя)
		CameraDrop = 2.3, -- свой вид опускается к полу на столько стадов
		CameraPitch = 0.8, -- и смотрит в потолок
		CameraRoll = 0.3, -- и чуть набок
		StarsHeight = 2.4, -- звёздочки над головой
		StarsSpin = 240, -- градусов в секунду
	},

	Waves = { -- волны (блок 3): воры приходят группами по 2–3 сразу с разных сторон
		AverageGroup = 2.5, -- сколько воров в волне в среднем (по нему считается число волн); выходит 2–3
		MaxAliveExtra = 2, -- одновременно в музее не больше «игроки + 2»
		StaggerSeconds = 1.5, -- воры одной волны входят с разницей до стольки секунд
		FirstSpawnMin = 15, -- первая волна через 15-30 сек после начала ночи
		FirstSpawnMax = 30,
		LastSpawnBeforeEnd = 15, -- за столько секунд до 06:00 новые волны не начинаются
		-- Паузы между волнами: время от первой волны до (конец ночи − LastSpawnBeforeEnd) делится на все волны.
		-- В начале ночи пауза ×1.3 от средней, к утру ×0.7 — к утру волны чаще.
		GapMax = 50, -- баланс: пауза между волнами не длиннее
		GapStartScale = 1.3,
		GapEndScale = 0.7,
		GapJitter = 0.25, -- случайный разброс паузы ±25%
		UpdateSeconds = 0.25, -- как часто волны проверяют планы и очередь воров
		NewThiefBannerDelay = 3.5, -- надпись NEW THIEF через столько секунд после «NIGHT N»
		TestUnlockAll = false, -- ДЛЯ ПРОВЕРКИ: true — все виды воров и планы сразу с 1-й ночи
	},

	Smart = { -- воры следят за охраной (блок 3); сервер знает, где охранники
		EntranceGuardRadius = 45, -- охранник ближе этого к двери — через неё не входят (если есть другая)
		GuardedTargetRadius = 20, -- охранник ближе этого к экспонату — экспонат «под охраной», берут другой
		CrowdRadius = 26, -- охранники ближе этого к Моне Лизе считаются «у картины»
		CrowdShare = 0.75, -- если у картины столько охраны (доля), один вор волны шумит в стороне
		LureCooldown = 60, -- шумят не чаще раза в столько секунд
		LureSeconds = 1.8, -- столько вор пинает витрину
		ClearRadius = 30, -- ждущие воры идут к картине, когда охраны ближе этого к ней нет
		HoldInside = 19, -- ждут во входном холле: столько стадов за дверью
		HoldSpread = 6, -- разброс места ожидания вбок
		HoldTimeout = 30, -- ждут не дольше, потом идут всё равно
		CaseReach = 3, -- с какого расстояния вор пинает витрину
	},

	Heist = { -- эффекты краж на карте (HeistFx)
		CaseStandOffset = 1.6, -- вор встаёт перед витриной на столько стадов от её переда
		CrackColor = Color3.fromHex("1E222B"), -- трещины на стекле витрины
		CrackedGlassColor = Color3.fromHex("DCE8F0"), -- стекло в трещинах белеет
		CrackedGlassTransparency = 0.55,
		ShardCount = 16, -- осколков от разбитой витрины
		ShardSpeed = 16, -- как быстро разлетаются
		ShardSeconds = 5, -- летящие осколки исчезают через столько секунд (на полу остаются до утра)
		FloorShards = 7, -- осколков остаётся лежать на полу перед витриной
		DustColor = Color3.fromHex("A08A6A"), -- пыль из подкопа
		DirtColor = Color3.fromHex("6B4A2E"), -- земля вокруг дыры
		HoleColor = Color3.fromHex("140E0A"), -- сама дыра
		CutLineColor = Color3.fromHex("BFF6FF"), -- светящийся след стеклореза
		CutSegments = 24, -- из скольких кусочков круг на стекле
		RopeColor = Color3.fromHex("E8A33D"),
		RopeThickness = 0.14,
		PulleyHeight = 3.3, -- блок треноги над стеклом
	},

	Halls = { -- 4 зала по углам музея (решение 69): дороже зал — дороже экспонаты и больше туристов
		Sculptures = { Price = 300, Title = "SCULPTURE HALL" }, -- баланс: цена зала
		Dinosaurs = { Price = 450, Title = "DINOSAUR HALL" },
		Jewelry = { Price = 600, Title = "JEWELRY HALL" },
		Space = { Price = 800, Title = "SPACE HALL" },
		BoardsFallSeconds = 1.2, -- доски падают, когда зал оплачен
	},

	Doors = { -- 4 двери входов и дверь STAFF ONLY открываются сами, когда рядом кто-то есть
		OpenRadius = 11, -- стадов от середины двери (по полу): ближе — дверь открывается
		CloseDelay = 1.2, -- закрывается через столько секунд, как рядом никого
		CheckSeconds = 0.2, -- как часто сервер проверяет, есть ли кто рядом
		SlideSeconds = 0.6, -- створки плавно отъезжают за столько секунд (анимация у клиентов)
	},

	Exhibits = {
		MonaLisaChance = 0.5, -- баланс: как часто вор идёт за Моной Лизой, если есть другие экспонаты
		PedestalHeight = 3.3, -- верх постамента
		HideDepth = 200, -- пока вор несёт копию экспоната, настоящий спрятан на столько стадов под картой
		-- Экспонат для каждого постамента (атрибут Slot у постамента): 2 в центре и по 4 в каждом зале,
		-- в зале — по возрастанию цены. Порядок постаментов задаёт MapBuilder.
		Slots = {
			"GoldVase", "AncientClock", -- центр (рядом с Моной Лизой)
			"Amphora", "Bust", "Statue", "Lion", -- Скульптуры
			"DinoTooth", "RaptorClaw", "DinoEgg", "TRexSkull", -- Динозавры
			"Necklace", "Crown", "Scepter", "Diamond", -- Драгоценности
			"MoonRock", "Meteorite", "AstronautHelmet", "RocketModel", -- Космос
		},
		-- баланс: цена и привлекательность (сколько туристов добавляет за день, турист = $10).
		-- Дороже зал — дороже экспонаты и больше туристов.
		Kinds = {
			GoldVase = { Title = "Golden Vase", Price = 150, Appeal = 2 },
			AncientClock = { Title = "Ancient Clock", Price = 250, Appeal = 3 },
			Amphora = { Title = "Amphora", Price = 100, Appeal = 1 },
			Bust = { Title = "Bust", Price = 150, Appeal = 2 },
			Statue = { Title = "Statue", Price = 200, Appeal = 2 },
			Lion = { Title = "Stone Lion", Price = 250, Appeal = 3 },
			DinoTooth = { Title = "Dino Tooth", Price = 150, Appeal = 2 },
			RaptorClaw = { Title = "Raptor Claw", Price = 200, Appeal = 2 },
			DinoEgg = { Title = "Dino Egg", Price = 250, Appeal = 3 },
			TRexSkull = { Title = "T-Rex Skull", Price = 350, Appeal = 4 },
			Necklace = { Title = "Necklace", Price = 200, Appeal = 2 },
			Crown = { Title = "Crown", Price = 250, Appeal = 3 },
			Scepter = { Title = "Scepter", Price = 300, Appeal = 3 },
			Diamond = { Title = "Diamond", Price = 400, Appeal = 5 },
			MoonRock = { Title = "Moon Rock", Price = 250, Appeal = 3 },
			Meteorite = { Title = "Meteorite", Price = 300, Appeal = 3 },
			AstronautHelmet = { Title = "Astronaut Helmet", Price = 400, Appeal = 4 },
			RocketModel = { Title = "Rocket Model", Price = 500, Appeal = 5 },
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
		-- Сколько воров за ночь (решение 70): в 1-ю ночь 3 на каждого игрока,
		-- каждую следующую +1 на игрока, но только до 5-й ночи, дальше число не растёт
		PerPlayerFirstNight = 3,
		PerPlayerGrowth = 1,
		GrowUntilNight = 5,
		-- Как воры приходят (волны, сколько одновременно) — Config.Waves
		UpdateSeconds = 0.1, -- как часто обновляется поведение воров
		PathRecomputeSeconds = 0.6, -- как часто пересчитывается путь
		PathRecomputeDistance = 4, -- или если цель сдвинулась на столько стадов
		WaypointReachDistance = 2.5,
		StealReachDistance = 3, -- на каком расстоянии от картины можно начать кражу
		EscapeReachDistance = 4, -- на каком расстоянии от выхода вор считается сбежавшим
		StandOffset = 2.5, -- насколько перед картиной встаёт вор
		ArrestSeconds = 1.5, -- руки вверх -> наручники -> пуф
		Color = Color3.fromHex("151515"), -- маска вора
		LoudStepMultiplier = 2.5, -- приманка топает громче и слышно дальше
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
			-- Щиток ALARM на стене справа от картины (смотреть на картину), со своей кнопкой F:
			-- на самой картине кнопка лазерной сетки, а на одну клавишу Roblox показывает одну кнопку.
			-- Смещение — от низа рамы в системе картины: −X — вправо для зрителя, +Y — вверх.
			PanelOffset = Vector3.new(-5.5, 1, 0),
			PanelSize = Vector3.new(1.6, 2.2, 0.3),
			PanelColor = Color3.fromHex("3A3F4B"),
			LampOffColor = Color3.fromHex("4A1C1E"), -- сигнализация не куплена
			LampOnColor = Color3.fromHex("FF3B3B"), -- куплена
		},
	},

	Money = { -- решение 68: главный доход — туристы; за пережитую ночь денег нет
		PerArrest = 5, -- баланс: долларов за арест вора — только тому, кто арестовал
		TicketPrice = 10, -- баланс: сколько платит турист за вход, делится поровну
	},

	Tourists = {
		-- 15 туристов × $10 = ~$150 на команду в 1-й день с одной Моной Лизой (решение 68)
		BasePerDay = 15, -- баланс: туристов за день, когда в музее только Мона Лиза
		PerAppeal = 1, -- баланс: сколько туристов добавляет каждое очко привлекательности экспонатов
		MaxAlive = 16, -- одновременно в музее (в 1-й день все 15 должны успеть войти до закрытия)
		SpawnWindow = 0.8, -- приходят в первые 80% времени, пока музей открыт (день минус закрытие)
		WalkSpeed = 7,
		VisitsMin = 2, -- сколько мест посмотрит
		VisitsMax = 4,
		AdmireMin = 3, -- сколько секунд смотрит на одно место
		AdmireMax = 6,
		PhotoChance = 0.4, -- как часто фотографирует
		ReachDistance = 3,
		WalkTimeout = 45, -- если турист застрял, через столько секунд идёт дальше (музей большой: от двери до зала ~30 сек)
		UpdateSeconds = 0.2,
		WanderInset = 6, -- гуляет по открытым залам, не ближе этого к стенам
		LeaveBeforeNightSeconds = 10, -- за столько секунд до ночи музей закрывается: все туристы идут к выходу
		LeaveWalkSpeed = 13, -- к ближайшей двери идут быстрее, чтобы успеть до ночи
	},

	Comms = {
		MarkSeconds = 6, -- баланс: сколько висит метка оператора
		MarkCooldown = 1,
		MarkMaxDistance = 150, -- дальше этого от камеры метку поставить нельзя
		MarkTapRadius = 60, -- в пикселях: насколько можно промахнуться мимо вора на картинке с камеры
		PhraseCooldown = 2,
		PhraseShowSeconds = 5,
		Phrases = { -- двери музея — по сторонам света (блок 2)
			"Thief at the painting!",
			"Thief at the north door!",
			"Thief at the south door!",
			"Thief at the east door!",
			"Thief at the west door!",
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
		CaseBang = "rbxasset://sounds/action_jump_land.mp3", -- ВРЕМЕННЫЙ: стандартный звук Roblox — вор пинает витрину
		GlassSmash = "rbxasset://sounds/impact_explosion_03.mp3", -- ВРЕМЕННЫЙ: стандартный взрыв выше тоном — витрина разбита
		Punch = "rbxasset://sounds/action_jump_land.mp3", -- ВРЕМЕННЫЙ: удар Громилы
		GuardFall = "rbxasset://sounds/oof.ogg", -- ВРЕМЕННЫЙ: охранник падает (классическое «oof»)
		GuardGetUp = "rbxasset://sounds/action_get_up.mp3", -- ВРЕМЕННЫЙ: охранник встаёт
		Dig = "rbxasset://sounds/impact_explosion_03.mp3", -- ВРЕМЕННЫЙ: стандартный взрыв ниже тоном — гул подкопа
		GlassCut = "", -- стеклорез режет тихо (звука нет)
		Sparks = "rbxassetid://9114277402", -- ВРЕМЕННЫЙ: Electric Zaps 6 — искры у щитка, свет гаснет
		PowerOn = "rbxassetid://9120484192", -- ВРЕМЕННЫЙ: Wall Light Switch — свет вернули
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
		CaseBangVolume = 1,
		CaseBangSpeed = 1.5, -- выше тоном: звонкий удар по стеклу
		GlassSmashVolume = 0.6,
		GlassSmashSpeed = 1.9,
		PunchVolume = 1,
		PunchSpeed = 0.8, -- ниже тоном: тяжёлый удар
		GuardFallVolume = 0.8,
		GuardGetUpVolume = 0.6,
		DigVolume = 0.7,
		DigSpeed = 0.45, -- низкий гул
		SparksVolume = 0.8,
		PowerOnVolume = 0.8,
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
		KickPeriod = 0.9, -- вор пинает витрину: один пинок за столько секунд
		StompStride = 0.42, -- Громила: тяжёлые редкие шаги
		ProwlStride = 0.75, -- Тень: короткие частые шаги на полусогнутых
		PunchStrikeSeconds = 0.15, -- удар Громилы после замаха (замах — ThiefTypes.Brute.PunchWindup)
		SmashPeriod = 1.1, -- Громила бьёт витрину: один удар двумя руками за столько секунд
		ClimbPeriod = 0.8, -- Шахтёр вылезает из дыры, Стекольщик лезет по верёвке: перехват рук
		CutPeriod = 1.6, -- Стекольщик ведёт стеклорез по кругу
		WorkSnipSpeed = 14, -- Светорез щёлкает кусачками
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
		Reward = { -- «+$5» над пойманным вором (размеры в стадах)
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
