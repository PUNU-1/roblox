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
	ThiefOrder = { "Pickpocket", "Breaker" },
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
