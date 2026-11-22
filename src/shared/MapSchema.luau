--!strict
-- Имена объектов карты в Workspace. Весь код ищет карту только через этот модуль.
-- Если владелец соберёт настоящую карту в Studio, она должна использовать эти же имена.

local MapSchema = {
	Root = "Map", -- Workspace.Map

	-- Папки внутри Map
	Geometry = "Geometry", -- стены, полы (полы с атрибутом Hall — по ним рисуется схема и гуляют туристы)
	Props = "Props", -- декор и видимые камеры
	Exhibits = "Exhibits", -- Мона Лиза
	Markers = "Markers", -- невидимые точки: спавны, место картины
	Entrances = "Entrances", -- 4 точки снаружи у дверей (South, West, North, East): тут появляются воры и туристы, сюда убегают
	CameraPoints = "CameraPoints", -- точки обзора камер Camera1..CameraN (атрибуты: GameState.CameraAttr)
	CameraSpots = "CameraSpots", -- места для камер: кронштейн и табличка CAMERA SPOT, где камеру покупают (CameraSpot1..N)
	Doors = "Doors", -- двери, которые открываются сами (модели с атрибутом Open, створки — модели с атрибутом SlideX)

	-- Отдельные объекты
	ControlConsole = "ControlConsole", -- пульт камер на балконе над Моной Лизой
	PaintingSpot = "PaintingSpot", -- где висит картина (для возврата)
	PaintingLight = "PaintingLight", -- подсветка картины
	PatrolSpawn = "PatrolSpawn", -- куда переносит охрану: перед Моной Лизой
	LobbySpawn = "LobbySpawn", -- SpawnLocation в комнате охраны
	StartCircle = "StartCircle", -- светящийся круг START SHIFT в лобби (прямо в Map): кто в нём — в команде
	Skylight = "Skylight", -- стеклянный потолок над центром (стекольщики режут его в блоке 3)
	Balcony = "Balcony", -- пол балкона над центром
	FuseBox = "FuseBox", -- щиток POWER в служебном коридоре (вор, который выключает свет, блок 3)
	ArmoryRack = "ArmoryRack", -- оружейная стойка: от неё ArmoryService ставит прилавок, стол и манекен (блок 4)
	CameraPlaque = "CameraPlaque", -- табличка под местом камеры: на ней кнопка покупки
	AreaAttribute = "Area", -- атрибут пола: название места для надписей («CENTER HALL», «SOUTH CORRIDOR»)

	-- Папки, которые появляются во время игры (прямо в Workspace)
	Thieves = "Thieves", -- воры
	Tourists = "Tourists", -- туристы днём
	HallDoors = "HallDoors", -- заколоченные двери в залы (модели с атрибутом Hall)
	HallDoorPanel = "Boards", -- деталь двери, которая загораживает проход
	HallDoorSign = "Sign", -- табличка с ценой и сбором денег
	Pedestals = "Pedestals", -- постаменты для экспонатов (атрибуты Hall и Slot)
	PlacedTraps = "PlacedTraps", -- поставленные лазерные сетки
	InstalledCameras = "InstalledCameras", -- модели купленных камер
	Dogs = "Dogs", -- собаки кинологов (блок 5)
	Sensors = "Sensors", -- датчики движения техников (блок 5)

	-- Имена моделей в ReplicatedStorage/Models (как в GEMINI.md)
	Models = {
		MonaLisa = "exhibit_monalisa_01",
		Camera = "camera_wall_01",
		LaserGrid = "trap_laser_01",
		ThiefMask = "thief_mask_01",
		Bench = "prop_bench_01",
		Barrier = "prop_barrier_01",
		Locker = "prop_locker_01",
		Handcuffs = "prop_handcuffs_01",
		GuardBadge = "guard_badge_01",
		Phone = "prop_phone_01",
		Pedestal = "prop_pedestal_01",
		-- блок 2: новый музей
		EntranceDoor = "prop_door_entrance_01", -- одна створка входной двери
		StaffDoor = "prop_door_staff_01", -- створка двери STAFF ONLY
		DisplayCase = "prop_displaycase_01", -- витрина-укрытие
		Reception = "prop_reception_01", -- стойка TICKETS во входном холле
		Chair = "prop_chair_01", -- кресло у пульта
		FuseBox = "prop_fusebox_01",
		WeaponRack = "prop_weaponrack_01",
		TRexSkeleton = "prop_skeleton_trex_01",
		LongneckSkeleton = "prop_skeleton_longneck_01",
		Planet = "prop_planet_01",
		Rocket = "prop_rocket_01",
		Fountain = "prop_fountain_01",
		Statue = "prop_statue_01",
		Palm = "prop_palm_01",
		Astronaut = "prop_astronaut_01",
		-- блок 3: снаряжение воров (GEMINI.md, «Новые модели блока 3»)
		BruteBeanie = "thief_brute_beanie_01",
		BruteGlove = "thief_brute_glove_01",
		BruteTankTop = "thief_brute_tanktop_01",
		ShadowHood = "thief_shadow_hood_01",
		ShadowHoodie = "thief_shadow_hoodie_01",
		MinerHelmet = "thief_miner_helmet_01",
		MinerMoustache = "thief_miner_moustache_01",
		MinerPickaxe = "thief_miner_pickaxe_01",
		MinerOveralls = "thief_miner_overalls_01",
		GlazierHelmet = "thief_glazier_helmet_01",
		GlazierHarness = "thief_glazier_harness_01",
		GlazierCutter = "thief_glazier_cutter_01",
		CutterCap = "thief_cutter_cap_01",
		CutterSnips = "thief_cutter_snips_01",
		CutterToolbelt = "thief_cutter_toolbelt_01",
		CutterStripes = "thief_cutter_stripes_01",
		Tripod = "prop_tripod_01",
		FloorHole = "prop_floorhole_01",
	},
}

return MapSchema
