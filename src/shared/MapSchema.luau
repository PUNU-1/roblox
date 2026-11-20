--!strict
-- Имена объектов карты в Workspace. Весь код ищет карту только через этот модуль.
-- Если владелец соберёт настоящую карту в Studio, она должна использовать эти же имена.

local MapSchema = {
	Root = "Map", -- Workspace.Map

	-- Папки внутри Map
	Geometry = "Geometry", -- стены, полы
	Props = "Props", -- декор и видимые камеры
	Exhibits = "Exhibits", -- Мона Лиза
	Markers = "Markers", -- невидимые точки: спавны, место картины
	ThiefEntrances = "ThiefEntrances", -- входы воров (они же выходы)
	CameraPoints = "CameraPoints", -- точки обзора камер Camera1..CameraN
	TrapSlots = "TrapSlots", -- отмеченные места для лазерных сеток Slot1..SlotN

	-- Отдельные объекты
	ControlConsole = "ControlConsole", -- пульт камер в диспетчерской
	PaintingSpot = "PaintingSpot", -- где висит картина (для возврата)
	PaintingLight = "PaintingLight", -- подсветка картины
	PatrolSpawn = "PatrolSpawn", -- куда переносит игроков в начале подготовки
	LobbySpawn = "LobbySpawn", -- SpawnLocation в комнате охраны

	-- Папки, которые появляются во время игры (прямо в Workspace)
	Thieves = "Thieves", -- воры
	Tourists = "Tourists", -- туристы днём
	HallDoors = "HallDoors", -- заколоченные двери в боковые залы (модели с атрибутом Hall)
	HallDoorPanel = "Boards", -- деталь двери, которая загораживает проход
	HallDoorSign = "Sign", -- табличка с ценой и сбором денег
	Pedestals = "Pedestals", -- постаменты для экспонатов (атрибуты Hall и Slot)
	FrontDoor = "FrontDoor", -- главная дверь для туристов: днём открыта, ночью закрыта
	TouristEntrance = "TouristEntrance", -- откуда приходят и куда уходят туристы
	PlacedTraps = "PlacedTraps", -- поставленные лазерные сетки

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
		GuardCap = "guard_cap_01",
		GuardBadge = "guard_badge_01",
		Phone = "prop_phone_01",
		Pedestal = "prop_pedestal_01",
	},
}

return MapSchema
