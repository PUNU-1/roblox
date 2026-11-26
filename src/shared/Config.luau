--!strict
-- Все числа игры живут здесь. В логике чисел быть не должно.
-- Числа баланса пока поставил Claude (помечены «баланс»). Друг предложит свои — см. TEAM_PLAN.md.

-- Шаг обучения (этап 5, блок C): поля — в описании Config.Tutorial.
export type TutorialStep = {
	Text: string,
	TouchText: string?,
	Icon: string,
	Target: string?,
	Done: string,
	Seconds: number?,
	Role: string?,
}

local Config = {
	Keys = { -- клавиши (решение 67, блок 4)
		Action = Enum.KeyCode.F, -- все кнопки у предметов (ProximityPrompt): покупка, арест, пульт, поднять друга; геймпад — как было (X)
		Phrases = Enum.KeyCode.T, -- открыть список готовых фраз (пока он открыт — цифры)
		Reload = Enum.KeyCode.R, -- перезарядка
		LeanLeft = Enum.KeyCode.Q, -- наклон влево (держать)
		LeanRight = Enum.KeyCode.E, -- наклон вправо (держать)
		Crouch = Enum.KeyCode.C, -- присесть / встать
		Shop = Enum.KeyCode.B, -- окно магазина днём (этап 4, блок 1b)
		SkipTutorial = Enum.KeyCode.K, -- пропустить обучение в этом забеге (этап 5, блок C; на телефоне — кнопка SKIP)
		-- места с собой: 1 — основное (автомат или дробовик), 2 — пистолет, 3 — шокер, 4 — аптечка
		Slots = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four },
	},

	-- Классы (блок 5): у каждого своё умение. Выбирается в лобби (карточки, клавиши 1–5), до конца забега не меняется.
	-- Один класс могут взять сколько угодно игроков. Ability — какое умение (AbilityService), Keys — клавиши умения.
	Classes = {
		Order = { "Patrol", "Operator", "Technician", "DogHandler", "Assault" }, -- порядок карточек и клавиш 1–5
		Default = "Patrol", -- с этим классом все начинают (он бесплатный: Price = 0)
		-- Price — цена в алмазах 💎 в магазине хаба (решение 74, этап 4, блок 1). 0 — класс бесплатный, есть у всех.
		AbilitySlack = 0.2, -- умение может прийти на столько секунд раньше конца перезарядки (часы клиента и сервера чуть расходятся)
		Patrol = {
			Title = "Patrol",
			Price = 0, -- бесплатный, с ним все начинают
			Ability = "Dash", -- рывок
			AbilityTitle = "DASH",
			KeyLabel = "Shift",
			Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3 }, -- геймпад — нажать левый стик
			Color = Color3.fromHex("3BC6C1"),
			SprintSpeed = 24, -- баланс: скорость в рывке (обычная — Players.WalkSpeed 16)
			SprintSeconds = 3, -- сколько длится рывок
			SprintCooldown = 10, -- перезарядка, считается после конца рывка
			FovKick = 12, -- свой вид в рывке шире на столько градусов
		},
		Operator = {
			Title = "Operator",
			Price = 50, -- баланс: алмазов 💎 (~1–2 забега)
			Ability = "Phone", -- телефон с камерами (CameraController, RoleService)
			AbilityTitle = "CAMERA PHONE",
			KeyLabel = "Tab",
			Color = Color3.fromHex("6FA8FF"),
		},
		Technician = {
			Title = "Technician",
			Price = 150, -- баланс: алмазов 💎
			Ability = "Sensor", -- датчик движения
			AbilityTitle = "MOTION SENSOR",
			KeyLabel = "G",
			Keys = { Enum.KeyCode.G, Enum.KeyCode.ButtonY },
			Color = Color3.fromHex("F2C230"),
			SensorRadius = 12, -- баланс: вор ближе этого к датчику — писк у всей охраны
			SensorsPerNight = 1, -- сколько датчиков за ночь (ставить можно и днём; утром датчик убирается)
			PingSeconds = 4, -- стрелка и метка MOTION! держатся столько; пока вор рядом, писк повторяется так часто
			PlaceReach = 2, -- датчик встаёт на столько стадов перед ногами (если там нет стены)
			PlaceMinGap = 3, -- не ближе этого к другому датчику
			InstantCameraReset = true, -- рубильник CAMERA RESET срабатывает сразу, без удержания
		},
		DogHandler = {
			Title = "Dog Handler",
			Price = 250, -- баланс: алмазов 💎
			Ability = "Dog", -- собака ходит рядом и лает на воров (умение без клавиши)
			AbilityTitle = "K-9 DOG",
			KeyLabel = "",
			Color = Color3.fromHex("E8913A"),
			DogSenseRadius = 25, -- баланс: вор ближе этого к хозяину — собака лает и смотрит на него
			BarkCooldown = 3, -- лает не чаще
		},
		Assault = {
			Title = "Assault",
			Price = 400, -- баланс: алмазов 💎 (~10 забегов)
			Ability = "Tough", -- больше здоровья и меньше отдача (умение без клавиши)
			AbilityTitle = "TOUGH",
			KeyLabel = "",
			Color = Color3.fromHex("E0575B"),
			AssaultHealth = 125, -- баланс: здоровье Штурмовика (у остальных Health.Max)
			AssaultRecoil = 0.6, -- баланс: отдача оружия ×0.6
		},
		CheckSeconds = 0.2, -- как часто сервер проверяет датчики и собак
		-- Датчик движения (вид; поведение — AbilityService)
		Sensor = {
			RingColor = Color3.fromHex("3BC6C1"), -- круг на полу: докуда видит датчик
			RingTransparency = 0.82,
			RingSegments = 28, -- из скольких чёрточек круг
			AlarmColor = Color3.fromHex("FF3B3B"), -- вор рядом
			LampColor = Color3.fromHex("3FD17A"), -- лампочка мигает зелёным, пока всё тихо
			BlinkSeconds = 1.2, -- лампочка мигает раз в столько секунд
			DeploySeconds = 0.5, -- датчик раскладывается на полу
			ArrowRadius = 150, -- стрелка к датчику: на столько пикселей от центра экрана
			MarkerMaxDistance = 600, -- метка MOTION! над датчиком видна сквозь стены до стольки стадов
			Beeps = 3, -- писк: столько коротких сигналов
			BeepGap = 0.16,
		},
		-- Собака кинолога (вид и походка; что она чует, решает сервер)
		Dog = {
			FollowDistance = 4.5, -- идёт по следу хозяина на столько стадов позади
			SideOffset = 1.2, -- и чуть левее его следа
			TrailStep = 0.7, -- след хозяина запоминается каждые столько стадов
			MaxSpeed = 30, -- быстрее рывка патруля, чтобы не отставала
			Catchup = 5, -- чем дальше от своего места, тем быстрее бежит (скорость = расстояние × это)
			SnapDistance = 35, -- хозяин дальше этого (перенос к Моне Лизе, в лобби) — собака появляется рядом
			SitDelay = 1.5, -- хозяин стоит столько секунд — собака садится
			RunSpeed = 13, -- быстрее этого — бежит галопом, а не рысью
			TrotStride = 1.15, -- радиан шага на стад пути
			GallopStride = 0.75,
			BlendSpeed = 10, -- как быстро поза перетекает в новую
			BarkSeconds = 0.55, -- «гав-гав»: два гавка за столько секунд
			-- Сидит (под размеры модели prop_dog_01): перед поднят на SitPitch радиан вокруг задних лап,
			-- туловище ниже на SitDrop, задние лапы подогнуты вперёд на SitBackLegs
			SitPitch = 0.54,
			SitDrop = 0.95,
			SitBackLegs = 0.65,
			AlertHeight = 1.5, -- «!» над головой собаки
			AlertSize = 1.4,
			AlertMaxDistance = 140,
			CullDistance = 220, -- дальше этого от камеры собаку не анимируем (только двигаем)
		},
	},

	Health = { -- здоровье охраны (блок 4): само не лечится, только аптечкой
		Max = 100,
		ReviveSeconds = 10, -- сколько держать F у лежащего друга
		ReviveHealth = 50, -- с таким здоровьем встаёт (и утром, если пролежал до утра)
		ReviveDistance = 7, -- с какого расстояния видно кнопку Revive
		ReviveSlack = 0.6, -- сервер принимает подъём, если F держали не меньше ReviveSeconds минус столько
		CrawlSpeed = 3.5, -- лежащий охранник медленно ползёт
		FallSeconds = 0.5, -- падает (анимация)
		RiseSeconds = 0.8, -- встаёт после подъёма (анимация)
		CameraDrop = 2.6, -- свой вид, пока лежишь: камера ниже на столько стадов
		MarkerMaxDistance = 400, -- метка «REVIVE» над лежащим другом видна сквозь стены до стольки стадов
		HurtFlashSeconds = 0.45, -- край экрана со стороны попадания вспыхивает
	},

	-- Оружие игроков (блок 4). Цены — у товаров оружейной (Armory). Время — в секундах, урон — здоровья.
	Weapons = {
		-- Огнестрел (пистолет, автомат, дробовик) достаётся только во время налёта; шокер — всегда (ночью)
		Order = { "Rifle", "Shotgun", "Pistol", "Taser" },
		Taser = {
			Title = "TASER",
			Interval = 0.5,
			Range = 30, -- дальность выстрела
			StunThief = 10, -- обычный вор лежит столько секунд (его можно арестовать)
			StunRobber = 5, -- грабитель — меньше (решил Claude)
			Cooldown = 30, -- перезарядка
			Color = Color3.fromHex("6FD3FF"), -- провода и искры
		},
		Pistol = {
			Title = "PISTOL",
			Slot = 2,
			Damage = 15,
			Interval = 1, -- 1 выстрел в секунду
			MagSize = 12,
			StartReserve = 24, -- запасных патронов при покупке (2 магазина)
			MaxReserve = 72, -- больше не купить
			ReloadSeconds = 1.6,
			Range = 300,
			RecoilPitch = 2.2, -- отдача: градусов вверх за выстрел
			RecoilYaw = 0.6, -- и случайно вбок
		},
		Rifle = {
			Title = "RIFLE",
			Slot = 1,
			Damage = 10,
			Interval = 0.1, -- стреляет часто (10 в секунду), пока держишь кнопку
			Automatic = true,
			MagSize = 30,
			StartReserve = 60,
			MaxReserve = 150,
			ReloadSeconds = 2.2,
			Range = 300,
			RecoilPitch = 1.5, -- сильная отдача: очередь уводит прицел вверх
			RecoilYaw = 0.9,
		},
		Shotgun = {
			Title = "SHOTGUN",
			Slot = 1,
			Pellets = 8, -- дробин за выстрел
			Damage = 12, -- урон одной дробины вблизи
			FalloffStart = 8, -- до стольки стадов урон полный
			FalloffEnd = 35, -- дальше — только FalloffMin от урона
			FalloffMin = 0.25,
			Spread = 5, -- разлёт дроби в градусах
			Interval = 0.9,
			MagSize = 6,
			StartReserve = 12,
			MaxReserve = 36,
			ReloadSeconds = 3, -- медленная перезарядка
			Range = 70,
			RecoilPitch = 5,
			RecoilYaw = 1.2,
		},
		HeadMultiplier = 1.5, -- попадание в голову
		-- Проверки сервера (клиенту не доверяем)
		FireJitter = 0.12, -- выстрел может прийти на столько секунд раньше положенного (задержка сети неровная)
		OriginSlack = 6, -- точка выстрела не дальше стольки стадов от головы стрелка
		AimDot = 0, -- направление выстрела не дальше 90° от того, куда смотрит персонаж (по полу)
		-- Бронежилет и аптечка
		Vest = { Armor = 50 },
		Medkit = { Heal = 50, UseSeconds = 2, MaxCarry = 2, Color = Color3.fromHex("3FD17A") },
		ArmorSparkColor = Color3.fromHex("8FC8FF"), -- пуля попала в бронежилет
		TracerSeconds = 0.07, -- трассер пули виден столько
		TracerWidth = 0.08,
		TracerColor = Color3.fromHex("FFE7A0"),
		ImpactSeconds = 0.35, -- искры на месте попадания
		EquipSeconds = 0.3, -- достать оружие (анимация)
	},

	Armory = { -- оружейная (блок 4): всё личное, без складчины; хватает денег — Buy $X, нет — Need $X
		PromptDistance = 6, -- товары стоят рядом, поэтому кнопку видно только вблизи
		Goods = {
			-- Kind: Weapon — оружие, Ammo — магазин патронов к Weapon, Vest, Medkit
			Taser = { Title = "Taser", Price = 100, Kind = "Weapon" },
			Pistol = { Title = "Pistol", Price = 150, Kind = "Weapon" },
			Shotgun = { Title = "Shotgun", Price = 300, Kind = "Weapon" },
			Rifle = { Title = "Rifle", Price = 350, Kind = "Weapon" },
			Vest = { Title = "Body Armor", Price = 200, Kind = "Vest" },
			Medkit = { Title = "Medkit", Price = 50, Kind = "Medkit" },
			PistolAmmo = { Title = "Pistol Ammo", Price = 20, Kind = "Ammo", Weapon = "Pistol" },
			RifleAmmo = { Title = "Rifle Ammo", Price = 20, Kind = "Ammo", Weapon = "Rifle" },
			ShotgunAmmo = { Title = "Shotgun Shells", Price = 20, Kind = "Ammo", Weapon = "Shotgun" },
		},
	},

	Raid = { -- налёт (блок 4): вооружённые грабители вместо одной волны
		FromNight = 3, -- с этой ночи
		Chance = 1 / 3, -- шанс, что одна из волн ночи — налёт
		PerPlayer = 3, -- грабителей: игроки × 3
		GrabberShare = 1 / 3, -- доля хватальщиков (остальные — стрелки), не меньше 1
		Stagger = 0.5, -- грабители входят друг за другом через столько секунд
		PoliceSeconds = 60, -- полиция приезжает через столько
		SurrenderSeconds = 15, -- сдавшиеся стоят с поднятыми руками, потом их забирает полиция
		Title = "Armed Raid", -- в итоге ночи «Thieves used: …»
		PoliceLightRange = 22, -- мигалки у дверей, когда приехала полиция
		TestForce = false, -- ДЛЯ ПРОВЕРКИ: true — налёт в каждую ночь (с 1-й)
	},

	Robber = { -- грабители налёта (блок 4)
		Health = 100,
		WalkSpeed = 13, -- стрелки
		RunSpeed = 15, -- хватальщики без добычи
		CarrySpeed = 11, -- с добычей
		StunSeconds = 5, -- шокер (Weapons.Taser.StunRobber)
		KnockoutSeconds = 2.2, -- «убитый» лежит со звёздочками, потом исчезает в облачке
		UpdateSeconds = 0.1,
		-- Стрелки: шанс попадания бота по охраннику; на каждом следующем налёте забега выше
		Guns = {
			Pistol = { Chance = 0.4, Damage = 10, Interval = 1.1 },
			Rifle = { Chance = 0.25, Damage = 8, Interval = 0.14, Burst = 4, BurstPause = 1.3 },
		},
		ChanceGrowth = 0.05, -- +5% за каждый следующий налёт
		MaxChance = 0.65,
		RifleShare = 0.3, -- доля стрелков с автоматом на первом налёте
		RifleShareGrowth = 0.15, -- дальше больше
		ShootRange = 90, -- дальше не стреляют
		SightRange = 120, -- видят охранника (луч без стен)
		CrouchFactor = 0.55, -- присевший охранник: шанс ×
		CoverFactor = 0.5, -- охранник за укрытием (виден только верх): шанс ×
		SmokeFactor = 0.3, -- луч проходит через дым: шанс ×
		LeanFactor = 0.8, -- выглядывает из-за укрытия
		FarDistance = 45, -- дальше этого шанс ×FarFactor
		FarFactor = 0.7,
		MissSpread = 3, -- промах пролетает рядом с охранником (стадов)
		-- Укрытия: стрелок встаёт за витриной, колонной, банкеткой подальше от охраны
		CoverMinDistance = 18, -- от охранника до укрытия
		CoverMaxDistance = 60,
		CoverSearchRadius = 70, -- ищет укрытия не дальше этого от себя
		CoverGap = 1.6, -- встаёт так далеко от края укрытия
		CoverRescanSeconds = 6, -- как часто ищет новое укрытие
		PeekSeconds = 1.6, -- выглядывает и стреляет столько секунд, потом прячется
		HideSeconds = 1.2, -- столько сидит за укрытием
		-- Дымовые шашки: у каждого стрелка одна
		SmokeChance = 0.12, -- шанс в секунду кинуть, когда видит охрану
		SmokeRange = 32, -- кидает не дальше
		SmokeThrowSeconds = 0.7, -- замах и бросок
		SmokeFlightSeconds = 0.9, -- шашка летит
		SmokeRadius = 9, -- облако
		SmokeSeconds = 12, -- облако держится
		-- Дубинка (у хватальщиков; стрелки бьют, если охранник подошёл вплотную)
		BatonDamage = 20,
		BatonRange = 5,
		BatonWindup = 0.35,
		BatonSeconds = 0.8,
		BatonCooldown = 1.6,
		Colors = {
			Gunner = { Shirt = Color3.fromHex("3A4030"), Pants = Color3.fromHex("23262B"), Vest = Color3.fromHex("1E2124"), Mask = Color3.fromHex("141416") },
			Grabber = { Shirt = Color3.fromHex("5A4A3A"), Pants = Color3.fromHex("2B2F3A"), Vest = Color3.fromHex("8C7A5A"), Mask = Color3.fromHex("141416"), Stripe = Color3.fromHex("C8343A") },
			Skin = Color3.fromHex("E0AC82"),
		},
	},

	Stance = { -- присед (C) и наклоны (Q / E), блок 4
		CrouchSpeed = 8, -- присевший ходит медленнее
		CrouchDrop = 1.7, -- свой вид опускается на столько стадов
		LeanOffset = 1.5, -- свой вид сдвигается вбок на столько стадов (выглянуть из-за укрытия)
		LeanRoll = 0.21, -- и наклоняется (радианы, ~12°)
		BlendSpeed = 10, -- как быстро вид перетекает в новую стойку
	},

	Purchase = { -- покупка одним удержанием F (решение 67): хватает денег — покупаешь сразу, нет — всё в полоску
		HoldSeconds = 1, -- сколько держать F
		PromptDistance = 10, -- с какого расстояния видно кнопку покупки
	},

	-- Окно магазина в музее (этап 4, блок 1b): днём B, кнопка SHOP или касса SHOP у Моны Лизы. Покупает по тем же
	-- правилам, что кнопки F (Purchase), но без проверки расстояния. Цены — у самих товаров (Exhibits, Halls, Traps,
	-- Cameras, Armory).
	Shop = {
		Tabs = { "Exhibits", "Halls", "Security", "Weapons", "Gear" }, -- вкладки по порядку
		RefreshSeconds = 0.25, -- как часто сервер обновляет для окна «сколько вложено / куплено»
		BuyCooldown = 0.3, -- покупка из окна не чаще раза за столько секунд (защита от спама Remote)
		PopupSeconds = 2.5, -- надпись «Bought: Golden Vase»
		PreviewSpin = 0.45, -- 3D-картинки товаров крутятся (радиан в секунду)
		-- Касса SHOP у Моны Лизы (MapBuilder): где стоит и куда смотрит (по полу центра)
		CounterPosition = Vector3.new(14, 0, 18), -- внутри кольца перегородок, справа-спереди от картины
		CounterFacing = Vector3.new(4, 0, 34), -- смотрит на эту точку (к ковровой дорожке и южному входу)
		CounterPromptDistance = 9,
		CounterHoldSeconds = 0.25,
	},

	Players = {
		Max = 5, -- больше игроков в одной игре не бывает (решение 52)
		VoteSeconds = 15, -- сколько длится голосование за опоздавшего
		WalkSpeed = 16, -- скорость патруля (стандарт Roblox)
		JumpHeight = 7.2, -- стандарт Roblox
		FieldOfView = 70, -- свой вид (в рывке шире — Classes.Patrol.FovKick)
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

	-- Блок 6: два места одной игры. Номера мест сам находит server/PlaceFinder (этап 4, блок 0) — вписывать
	-- их не нужно. Два номера ниже — только запасной путь: берутся, если такое место есть в игре (или если
	-- Roblox не дал список мест). Можно оставить 0. Без второго места музей работает сам по себе со своим кругом.
	Places = {
		HubPlaceId = 104264244300759, -- место Hub (общее лобби): стартовое место игры «Guard The Museum»
		MuseumPlaceId = 120651563894118, -- место Museum (забег одной команды)
		LookupRetrySeconds = 30, -- Roblox не дал список мест — через столько секунд PlaceFinder спросит снова
		TicketSource = "NightGuardHub", -- метка в данных телепорта из хаба (музей принимает только такие)
		ReturnSource = "NightGuardMuseum", -- метка в данных телепорта из музея обратно в хаб
		TeleportRetries = 3, -- сколько раз пробовать ReserveServer и TeleportAsync
		RetryDelay = 2, -- секунд между попытками
	},

	Hub = { -- общее лобби (блок 6): 5 кругов на полу, на каждом своя команда
		Pads = 5, -- сколько кругов
		PadRadius = 6, -- стадов от центра круга до края (по HumanoidRootPart)
		PadHeight = 12, -- выше этого над кругом не считается (прыжок из команды не выкидывает)
		CountdownSeconds = 30, -- отсчёт от первого игрока в круге; создатель может нажать START раньше
		CheckSeconds = 0.2, -- как часто сервер проверяет, кто в кругах
		BlockedSeconds = 6, -- в Studio (телепорта нет) надпись висит столько, потом отсчёт сначала
		FailedSeconds = 5, -- телепорт не удался — надпись столько, потом отсчёт сначала
		LaunchTimeout = 20, -- команда не улетела за столько секунд — круг снова открыт
		Color = Color3.fromHex("3BC6C1"), -- круг ждёт игроков
		MineColor = Color3.fromHex("3FB56B"), -- твой круг
		FullColor = Color3.fromHex("C8343A"), -- команда полная, а ты не в ней
		FriendsColor = Color3.fromHex("8E5BC2"), -- Friends only, а ты не в команде
		LaunchColor = Color3.fromHex("FFD23F"), -- команда улетает
		BlockedColor = Color3.fromHex("4A5266"), -- телепорт не удался или не работает в Studio
		PulseSeconds = 1.2,
		PulseTransparency = 0.45,
		LightRange = 14,
		LightBrightness = 1.5,
		LabelHeight = 7.5, -- табличка над кругом
		LabelMaxDistance = 110,
		Lighting = { -- в комнате хаба всегда вечер, тёплый свет
			ClockTime = 18,
			Brightness = 1.5,
			Ambient = Color3.fromRGB(125, 122, 120),
			OutdoorAmbient = Color3.fromRGB(140, 135, 130),
		},
		CeilingLight = { -- светильники на потолке хаба
			Range = 26,
			Brightness = 1.1,
			Color = Color3.fromRGB(255, 232, 196),
		},
		MonitorLight = { -- голубой отсвет стены мониторов
			Range = 16,
			Brightness = 0.8,
			Color = Color3.fromRGB(120, 190, 255),
		},
		RecStepSeconds = 0.8, -- мигание REC на мониторах
		Camera = { -- этап 5, блок A: в хабе вид от третьего лица (в музее — от первого)
			MinZoom = 6, -- ближе камера к игроку не подходит
			MaxZoom = 20, -- дальше не отъезжает
		},
	},

	-- Алмазы 💎 (решение 74, этап 4, блок 1): даются за игру и сохраняются навсегда (server/ProfileStore, общий
	-- для хаба и музея). Тратятся на классы в магазине хаба (цены — Classes.<Name>.Price). Деньги забега ($) — отдельно.
	Diamonds = {
		PerNight = 10, -- баланс: каждому на смене за каждую пережитую ночь
		PerArrest = 1, -- баланс: за каждый свой арест (вор, сдавшийся или оглушённый грабитель)
		Store = "PlayerProfile_v1", -- DataStore профиля: ключ — UserId, данные { diamonds, ownedClasses }
		Retries = 3, -- попыток каждого запроса к DataStore (Retry)
		RetryDelay = 1.5, -- секунд между попытками (вторая — ×2)
		ReloadSeconds = 30, -- профиль не загрузился (сбой Roblox) — пробуем снова через столько
		LoadWaitSeconds = 15, -- музей ждёт профиль прилетевшего из хаба не дольше, чтобы проверить его класс
		CloseWaitSeconds = 25, -- сервер закрывается — ждём сохранения не дольше (Roblox даёт до 30 сек)
		Color = Color3.fromHex("6FE3FF"), -- цвет алмазов в интерфейсе
	},

	-- Пиксельный стиль интерфейса (этап 5, блок A, решение 75): UI/PixelIcon, UI/PixelButton, UI/PixelWindow.
	-- Хаб сейчас, кнопки музея — в блоке D.
	PixelUI = {
		Font = "rbxasset://fonts/families/PressStart2P.json", -- пиксельный шрифт Roblox; если его нет — Enum.Font.Arcade
		Cell = 4, -- пикселей на клетку иконки кнопки слева (иконка 16 × 16 клеток = 64 пикселя)
		MinCell = 2, -- на маленьком экране клетка меньше, но не меньше этого
		ShadowTransparency = 0.6, -- тень иконки: та же иконка чёрным на 1 клетку вниз-вправо
		HoverScale = 1.1, -- мышь над кнопкой — иконка подрастает
		PressScale = 0.88, -- нажали — сжимается
		HoverRock = 6, -- и покачивается на столько градусов в каждую сторону
		RockSeconds = 0.35, -- за столько секунд из стороны в сторону
		ClickSound = "rbxassetid://9120484192", -- ВРЕМЕННЫЙ: Wall Light Switch выше тоном — клик кнопки
		ClickVolume = 0.35,
		ClickSpeed = 1.8,
		WindowCell = 4, -- пикселей на клетку каймы окна
	},

	-- Ежедневные подарки в хабе (этап 5, блок A, решение 76): 7 дней подряд, пропустил день — снова с 1-го.
	-- День — номер дня по UTC (время сервера), хранится в профиле игрока (ProfileStore, PlayerProfile_v1).
	DailyGift = {
		Rewards = { 5, 10, 15, 20, 25, 30, 60 }, -- баланс: алмазы 💎 за 1-й … 7-й день подряд
		DaySeconds = 86400, -- длина дня (новый день — в 00:00 UTC)
	},

	-- Награды за группу и «Избранное» (этап 5, блок A): группы пока нет — кнопки показывают «Coming soon!».
	Rewards = {
		GroupId = 0, -- номер группы Roblox; владелец пришлёт — награду сделаем отдельно
	},

	Leaderboard = { -- доска рекордов в хабе (блок 6): топ команд по числу ночей
		Top = 10, -- сколько строк на доске
		MinNights = 1, -- записываем рекорд, если продержались хотя бы столько ночей
		AllTimeStore = "TeamNightsAllTime_v1", -- OrderedDataStore за всё время
		WeeklyStorePrefix = "TeamNightsWeek_v1_", -- + номер недели: своё хранилище на каждую неделю
		WeekOffsetSeconds = 345600, -- неделя начинается в понедельник 00:00 UTC (1.1.1970 был четверг)
		RefreshSeconds = 60, -- как часто хаб перечитывает доску
		Retries = 3, -- попыток каждого запроса к DataStore
		RetryDelay = 1.5,
	},

	GameOver = { -- конец забега в музее (блок 6): Play again / Lobby
		ChoiceSeconds = 20, -- ничего не нажал за столько — в лобби
		WaitTeamSeconds = 20, -- музей ждёт команду из хаба не дольше стольких секунд после первого игрока
	},

	Phases = { -- дни и ночи растут с каждым днём забега (решение 66)
		DayFirstSeconds = 45, -- 1-й день: туристы, покупки (этап 5, блок B, решение 77: было 30 — не успевали дойти до картины)
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
		FakeGuard = { -- Фальшивый охранник (только в плане Fake Guard): копия игрока в форме охраны
			Title = "FAKE GUARD",
			FromNight = 4,
			Weight = 0, -- обычной волной не приходит
			SpeedMul = 1,
			Door = true,
			NoFlee = true, -- ходит спокойно, не убегает
			WalkAnim = "Patrol",
			WalkSpeed = 11, -- спокойный шаг охранника (до кражи)
			WatchRadius = 30, -- крадёт, только когда ни один охранник ближе этого его не видит
		},
	},

	-- Планы воров (блок 3): с Waves.PlansFromNight у каждой волны маленький план. Порядок — для выбора.
	PlanOrder = { "Distraction", "Tunnel", "Blinding", "Pincer", "Decoy", "FakeGuard", "Blackout" },
	Plans = {
		-- Title — имя в итоге ночи «Thieves used: …»; FromNight — не раньше этой ночи;
		-- Needs — нужен этот вид вора (план приходит, когда вид уже открыт)
		Distraction = { Title = "Distraction", Needs = "Brute" }, -- Громила бьёт витрину, Стекольщик или тихий вор — к Моне Лизе
		Tunnel = { Title = "Tunnel", Needs = "Miner" }, -- Шахтёры вылезают из пола у разных экспонатов
		Blinding = { Title = "Blinding", Needs = "Breaker", Cameras = 2, Radius = 110 }, -- ломает до 2 камер со своей стороны
		Pincer = { Title = "Pincer", FromNight = 2 }, -- две группы через противоположные двери
		Decoy = { Title = "Decoy", FromNight = 2 }, -- шумный вор с дешёвым экспонатом, тихий — к Моне Лизе
		FakeGuard = { Title = "Fake Guard", FromNight = 4 }, -- копия игрока с его ником
		Blackout = { Title = "Blackout", Needs = "Cutter" }, -- Светорез вырубает свет, в темноте работают Тени
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
		PlansFromNight = 2, -- с этой ночи у каждой волны план (1-я ночь — просто волны)
		BigNightEvery = 3, -- каждая 3-я ночь большая: больше воров, в одной волне несколько планов
		BigNightExtraPerPlayer = 1, -- баланс: столько воров на игрока добавляет большая ночь
		BigWavePlans = 2, -- сколько планов сразу в большой волне
		BigWavePlansManyPlayers = 3, -- а если игроков не меньше ManyPlayers
		ManyPlayers = 3,
		FollowTimeout = 45, -- планы с сигналом (камеры сломаны, свет вырублен) пускают остальных воров не позже
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

	Wings = { -- крылья (этап 5, блок B, решение 77): коридор + входной холл стороны, вход переезжает в конец крыла
		Prices = { 100, 200, 300, 400 }, -- баланс: цена 1-го, 2-го, 3-го и 4-го купленного крыла (в любом порядке)
		Tourists = 4, -- баланс: +туристов в день за каждое открытое крыло
		Titles = { WingSouth = "SOUTH WING", WingWest = "WEST WING", WingNorth = "NORTH WING", WingEast = "EAST WING" },
		BoardsFallSeconds = 1.2, -- доски падают, когда крыло оплачено
	},

	Doors = { -- двери входов, двери центра и дверь STAFF ONLY открываются сами, когда рядом кто-то есть
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
		HoldSeconds = 1, -- удержание кнопки для ареста (и для Check ID)
		CheckIdCooldown = 3, -- Check ID на настоящем охраннике: кнопка гаснет на столько секунд
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
		-- блок 4: в Studio есть только несколько стандартных звуков, поэтому разные звуки — из одного с другой высотой тона
		Hurt = "rbxasset://sounds/ouch.ogg", -- ВРЕМЕННЫЙ: охранника задела пуля или дубинка
		GuardDown = "rbxasset://sounds/oof.ogg", -- ВРЕМЕННЫЙ: охранник упал без сил
		HurtVolume = 0.6,
		GuardDownVolume = 0.9,
		-- Выстрелы: ВРЕМЕННЫЕ — стандартный взрыв Roblox высоко тоном (короткий хлопок), шокер — Electric Zaps
		Shots = {
			Pistol = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.5, Speed = 2.4 },
			Rifle = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.38, Speed = 3 },
			Shotgun = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.7, Speed = 1.55 },
			Taser = { Id = "rbxassetid://9114277402", Volume = 0.6, Speed = 1.5 },
		},
		ShotRollOff = 160, -- выстрелы слышно далеко
		Click = "rbxasset://sounds/volume_slider.ogg", -- ВРЕМЕННЫЙ: щелчок — перезарядка, пустой магазин, попадание
		ReloadSpeed = 0.8,
		EmptySpeed = 1.7,
		HitSpeed = 2.3,
		ClickVolume = 0.7,
		Baton = "rbxasset://sounds/action_jump_land.mp3", -- ВРЕМЕННЫЙ: удар дубинкой
		BatonSpeed = 1.3,
		BatonVolume = 0.9,
		Smoke = "rbxasset://sounds/impact_water.mp3", -- ВРЕМЕННЫЙ: шипение дымовой шашки (вода ниже тоном)
		SmokeSpeed = 0.55,
		SmokeVolume = 0.8,
		RobberDown = "rbxasset://sounds/oof.ogg", -- ВРЕМЕННЫЙ: грабитель упал (ниже тоном)
		RobberDownSpeed = 0.75,
		PoliceSpeed = 0.75, -- сирена полиции — та же Alarm ниже тоном (ВРЕМЕННАЯ)
		Heal = "rbxasset://sounds/action_get_up.mp3", -- ВРЕМЕННЫЙ: аптечка подействовала
		HealVolume = 0.7,
		HealSpeed = 1.4,
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
		-- блок 5: классы (ВРЕМЕННЫЕ, из тех же стандартных звуков Roblox)
		Dash = "rbxasset://sounds/action_falling.ogg", -- ВРЕМЕННЫЙ: рывок — свист ветра (слышит сам игрок)
		DashVolume = 0.5,
		DashSpeed = 1.6,
		Bark = "rbxasset://sounds/oof.ogg", -- ВРЕМЕННЫЙ: лай собаки — классическое «oof» высоко тоном звучит как «гав»
		BarkVolume = 0.9,
		BarkSpeed = 1.75,
		BarkRollOff = 70,
		SensorBeep = "rbxasset://sounds/volume_slider.ogg", -- ВРЕМЕННЫЙ: писк датчика — щелчок высоко тоном, 3 раза
		SensorBeepVolume = 0.8,
		SensorBeepSpeed = 2.6,
		SensorPlace = "rbxasset://sounds/action_jump_land.mp3", -- ВРЕМЕННЫЙ: датчик поставили на пол
		SensorPlaceVolume = 0.6,
		SensorPlaceSpeed = 1.8,
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
		PatrolStride = 0.55, -- Фальшивый охранник: спокойный шаг
		-- блок 4
		StunFallSeconds = 0.3, -- шокер: вор падает на спину
		StunTwitchSeconds = 1.6, -- и столько дёргается
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

	-- Обучение со стрелками в каждом забеге (этап 5, блок C, решение 78; заменило подсказки новичку, решение 36).
	-- Показывает клиент (client/Tutorial): плашка шага сверху, шевроны по полу по пути PathfindingService, прыгающая
	-- стрелка над целью. Сервер только отмечает траты и аресты забега (атрибуты RunSpent, RunArrests) и хранит
	-- настройку «выключено» в профиле (ProfileStore, TutorialOff).
	--
	-- Шаг: Text (на телефоне — TouchText, если есть), Icon — пиксельная иконка справа, Target — куда показывают стрелки,
	-- Done — когда шаг выполнен, Seconds — шаг сам засчитывается через столько секунд (или, у Done = "Info", просто
	-- исчезает), Role — шаг только у этого класса.
	--   Target: MonaLisa | ShopCounter | FirstThief (первый вор 1-й ночи) | WingWall (ближайшая заколоченная стена
	--           крыла) | TaserSeller (оружейная, если открыто южное крыло, иначе касса SHOP)
	--   Done:   Near (ближе NearDistance к цели) | ShopOpened | Bought (любая покупка за забег) | PhoneOpened |
	--           SensorPlaced | ThiefSeen (вор уже в музее) | Arrested (свой арест за забег) | WingOpen (любое крыло
	--           открыто) | HasTaser | Info (без галочки)
	-- Уже сделанное засчитывается сразу. Части: Phase + Night — в какую фазу какой ночи (Night = GameState NightNumber).
	Tutorial = {
		NearDistance = 8, -- «подойди к Моне Лизе» — ближе этого (охрана появляется в ~13 от картины)
		MinStepSeconds = 2, -- шаг висит хотя бы столько, даже если уже сделан (успеть прочитать)
		NextDelay = 1, -- шаг выполнен: галочка, через столько секунд следующий
		CompleteSeconds = 4, -- «Tutorial complete!» висит столько
		ToggleCooldown = 2, -- сервер: менять настройку не чаще раза за столько секунд
		DoneSound = "rbxasset://sounds/electronicpingshort.wav", -- ВРЕМЕННЫЙ: стандартный звук Roblox — шаг выполнен
		DoneVolume = 0.6,
		Chevrons = { -- светящиеся шевроны по полу от игрока к цели (видит только сам игрок)
			Count = 12, -- сколько штук (пул)
			Spacing = 3.5, -- стадов между шевронами
			Speed = 5, -- плывут вперёд, стадов в секунду
			RepathSeconds = 0.5, -- путь пересчитывается так часто
			ArmLength = 1.4, -- длина одной палочки «>»
			ArmWidth = 0.35,
			Height = 0.15, -- над полом
			HideNear = 6, -- ближе к цели — шевронов нет
			Color = Color3.fromHex("FFD23F"),
			Transparency = 0.15,
			AgentRadius = 2, -- как у воров: путь не прижимается к стенам
		},
		Arrow = { -- большая прыгающая стрелка над целью, видна сквозь стены
			Cell = 4, -- пикселей на клетку пиксельной стрелки (16 клеток = 64 пикселя)
			Height = 7, -- стадов над целью
			ThiefHeight = 4, -- над вором — ниже (над серединой тела)
			Bounce = 1.2, -- прыгает на столько стадов
			BounceSeconds = 0.8, -- период прыжка
		},
		CompleteText = "Tutorial complete! Good luck, guard",
		SkippedText = "Tutorial skipped. Turn it on again: HOW TO PLAY in the lobby",
		Segments = {
			{
				Phase = "Day",
				Night = 1,
				Steps = ({
					{ Text = "Welcome, guard! Protect the Mona Lisa", Icon = "Painting", Target = "MonaLisa", Done = "Near" },
					{
						Text = "Tourists pay for tickets. Open the shop: press B",
						TouchText = "Tourists pay for tickets. Open the shop: tap SHOP",
						Icon = "Shop",
						Target = "ShopCounter",
						Done = "ShopOpened",
					},
					{ Text = "Buy a camera or an exhibit", Icon = "Shop", Done = "Bought", Seconds = 15 },
					{
						Role = "Operator",
						Text = "Press Tab - your phone shows the cameras",
						TouchText = "Tap the PHONE button - it shows the cameras",
						Icon = "Phone",
						Done = "PhoneOpened",
					},
					{
						Role = "Technician",
						Text = "Press G to place a motion sensor",
						TouchText = "Tap the SENSOR button to place a motion sensor",
						Icon = "Sensor",
						Done = "SensorPlaced",
					},
					{ Text = "Night is coming - stay near the Mona Lisa", Icon = "Moon", Target = "MonaLisa", Done = "Info" },
				} :: { TutorialStep }),
			},
			{
				Phase = "Night",
				Night = 1,
				Steps = ({
					{ Text = "Thieves come through the doors!", Icon = "Thief", Done = "ThiefSeen" },
					{
						Text = "Run to the thief and hold F to arrest him",
						TouchText = "Run to the thief and hold the Arrest button",
						Icon = "KeyF",
						Target = "FirstThief",
						Done = "Arrested",
					},
					{ Text = "Don't let them carry the Mona Lisa out!", Icon = "Painting", Done = "Info", Seconds = 6 },
				} :: { TutorialStep }),
			},
			{
				Phase = "Day",
				Night = 2,
				Steps = ({
					{
						Text = "Buy a wing - thieves will walk longer. Hold F at the boarded wall",
						TouchText = "Buy a wing - thieves will walk longer. Hold the button at the boarded wall",
						Icon = "Shop",
						Target = "WingWall",
						Done = "WingOpen",
					},
					{
						Text = "Buy a taser: press B, Weapons tab",
						TouchText = "Buy a taser: tap SHOP, Weapons tab",
						Icon = "Shop",
						Target = "TaserSeller",
						Done = "HasTaser",
					},
				} :: { TutorialStep }),
			},
		},
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
