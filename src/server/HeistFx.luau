-- Эффекты краж на карте (блок 3). Только то, что видно и слышно; решения принимает ThiefService.
--  • Витрины (prop_displaycase_01): вор пинает витрину — стекло трескается, Громила разбивает — осколки;
--    в обоих случаях тревога «GLASS ALARM — место!».
--  • Подкоп Шахтёра: трещины, пыль и гул, потом дыра в полу с землёй и обломками плитки.
--  • Стекольщик: светящийся круг на стеклянном потолке, дыра в стекле, тренога с блоком, верёвка.
--  • Названия мест для надписей: атрибут Area у пола (MapBuilder).
--  • Всё, что воры оставили за ночь (трещины, осколки), убирается утром: HeistFx.resetForDay().

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local Audio = require(Server:WaitForChild("Audio"))
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))

local Heist = Config.Heist

local HeistFx = {}

export type Case = {
	model: Model,
	glass: BasePart?, -- стекло витрины
	stand: Vector3, -- где встаёт вор перед витриной
	area: string, -- название места для надписи
	hall: string, -- зал (витрины закрытого зала воры не трогают)
	cracked: boolean,
	broken: boolean,
	glassColor: Color3,
	glassTransparency: number,
	extras: { Instance }, -- трещины и обломки, которые убираются утром
}

local cases: { Case } = {}
local floorParams: RaycastParams? = nil
local bannerRemote = Remotes.get(Remotes.Names.Banner)

---------------------------------------------------------------- места

-- Название места и зал под точкой: смотрим на пол под ней (атрибуты Area и Hall у пола).
function HeistFx.areaAt(position: Vector3): (string?, string)
	local params = floorParams
	if not params then
		return nil, GameState.Hall.Main
	end
	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	local floor = result and result.Instance
	if not floor then
		return nil, GameState.Hall.Main
	end
	local area = floor:GetAttribute(MapSchema.AreaAttribute)
	local hall = floor:GetAttribute("Hall")
	return if typeof(area) == "string" then area else nil, if typeof(hall) == "string" then hall else GameState.Hall.Main
end

local function alarmBanner(position: Vector3)
	local area = HeistFx.areaAt(position)
	bannerRemote:FireAllClients(if area then ("GLASS ALARM — %s!"):format(area) else "GLASS ALARM!", "danger")
end

---------------------------------------------------------------- витрины

local function decor(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end
HeistFx.decor = decor

local function findGlass(model: Model): BasePart?
	local named = model:FindFirstChild("Glass", true)
	if named and named:IsA("BasePart") then
		return named
	end
	-- Модель друга: берём первую стеклянную деталь
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Material == Enum.Material.Glass then
			return descendant
		end
	end
	return nil
end

local function addCase(model: Model)
	local glass = findGlass(model)
	local pivot = model:GetPivot()
	local _, size = model:GetBoundingBox()
	local front = pivot.Position + pivot.LookVector * (size.Z / 2 + Heist.CaseStandOffset)
	local stand = Vector3.new(front.X, pivot.Position.Y + 3, front.Z)
	local area, hall = HeistFx.areaAt(stand)
	table.insert(cases, {
		model = model,
		glass = glass,
		stand = stand,
		area = area or "MUSEUM",
		hall = hall,
		cracked = false,
		broken = false,
		glassColor = if glass then glass.Color else Color3.new(1, 1, 1),
		glassTransparency = if glass then glass.Transparency else 0.75,
		extras = {},
	})
end

local function minDistance(position: Vector3, points: { Vector3 }): number
	local best = math.huge
	for _, point in points do
		local offset = point - position
		best = math.min(best, Vector3.new(offset.X, 0, offset.Z).Magnitude)
	end
	return best
end

-- Витрина подальше от охраны (в открытом зале, ещё целая) — туда идут шуметь.
function HeistFx.pickCase(guards: { Vector3 }, exclude: { Case }?): Case?
	local best, bestDistance = nil, -1
	for _, case in cases do
		if not case.broken and not case.cracked and case.model.Parent and GameState.isHallOpen(case.hall)
			and not (exclude and table.find(exclude, case))
		then
			-- Без охраны выбираем случайно, иначе — самую далёкую от охранников
			local distance = if #guards == 0 then math.random() else minDistance(case.stand, guards)
			if distance > bestDistance then
				best, bestDistance = case, distance
			end
		end
	end
	return best
end

-- Трещины звездой от точки удара на передней стороне стекла.
local function crackGlass(case: Case)
	local glass = case.glass
	if not glass then
		return
	end
	glass.Color = Heist.CrackedGlassColor
	glass.Transparency = Heist.CrackedGlassTransparency
	local face = glass.CFrame * CFrame.new(glass.Size.X * 0.15, -glass.Size.Y * 0.05, -glass.Size.Z / 2 - 0.03)
	local rays = { 0.3, 1.4, 2.3, 3.4, 4.4, 5.5 }
	for index, angle in rays do
		local length = 0.5 + (index % 3) * 0.25
		local spin = face * CFrame.Angles(0, 0, angle) * CFrame.new(length / 2, 0, 0)
		table.insert(case.extras, decor("Crack", Vector3.new(length, 0.05, 0.04), spin, Heist.CrackColor, Enum.Material.SmoothPlastic, case.model))
	end
	-- Кольцо вокруг точки удара
	for index = 0, 5 do
		local spin = face * CFrame.Angles(0, 0, index * math.pi / 3 + 0.5) * CFrame.new(0.32, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
		table.insert(case.extras, decor("Crack", Vector3.new(0.34, 0.04, 0.04), spin, Heist.CrackColor, Enum.Material.SmoothPlastic, case.model))
	end
end

-- Вор пнул витрину: стекло в трещинах, звон и тревога на весь музей с названием места.
function HeistFx.caseAlarm(case: Case)
	if case.cracked or case.broken then
		return
	end
	case.cracked = true
	crackGlass(case)
	local sounds = Config.Sounds
	Audio.playOnce(sounds.CaseBang, case.glass or case.model.PrimaryPart, sounds.CaseBangVolume, nil, sounds.CaseBangSpeed)
	Audio.alarm()
	alarmBanner(case.stand)
end

-- Осколок стекла: тонкий клин случайной формы.
local function shard(cframe: CFrame, color: Color3, anchored: boolean): BasePart
	local piece = Instance.new("WedgePart")
	piece.Name = "GlassShard"
	piece.Size = Vector3.new(math.random(15, 55) / 100, 0.05, math.random(15, 55) / 100)
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = Enum.Material.Glass
	piece.Transparency = 0.35
	piece.CastShadow = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Anchored = anchored
	piece.CanCollide = not anchored
	piece.Massless = true
	piece.CollisionGroup = ModelLibrary.Groups.Tourists -- падают на пол, но сквозь людей (группа без столкновений с людьми)
	return piece
end

-- Громила разбил витрину: стекло разлетается осколками, по краю рамы остаются зубцы, на полу — осколки
-- до утра. Звон, сирена и тревога с названием места.
function HeistFx.smashCase(case: Case)
	if case.broken then
		return
	end
	case.broken = true
	local glass = case.glass
	if glass then
		local size = glass.Size
		local front = glass.CFrame.LookVector -- перед витрины (к вору)
		for _ = 1, Heist.ShardCount do
			local offset = Vector3.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y, (math.random() - 0.5) * size.Z)
			local spin = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
			local piece = shard(glass.CFrame * CFrame.new(offset) * spin, case.glassColor, false)
			piece.Parent = Workspace
			local away = (front * (0.6 + math.random()) + Vector3.new((math.random() - 0.5) * 1.4, 0.5 + math.random(), (math.random() - 0.5) * 1.4))
			piece.AssemblyLinearVelocity = away.Unit * Heist.ShardSpeed * (0.5 + math.random() * 0.6)
			piece.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
			Debris:AddItem(piece, Heist.ShardSeconds)
		end
		-- Зубцы стекла по нижнему краю рамы
		for index = -2, 2 do
			local tooth = shard(glass.CFrame * CFrame.new(index * size.X * 0.2, -size.Y / 2 + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90 + index * 9)), case.glassColor, true)
			tooth.Size = Vector3.new(0.3 + math.random() * 0.35, 0.05, size.Z * 0.9)
			tooth.Parent = case.model
			table.insert(case.extras, tooth)
		end
		-- Осколки на полу перед витриной (лежат до утра)
		local floorY = case.stand.Y - 2.95
		for _ = 1, Heist.FloorShards do
			local point = case.stand + front * (math.random() - 0.7) * 1.5 + (glass.CFrame.RightVector * (math.random() - 0.5) * size.X * 1.2)
			local piece = shard(CFrame.new(point.X, floorY, point.Z) * CFrame.Angles(0, math.random() * 6.28, 0), case.glassColor, true)
			piece.Parent = case.model
			table.insert(case.extras, piece)
		end
		glass.Transparency = 1
		glass.CanCollide = false
	end
	local sounds = Config.Sounds
	Audio.playOnce(sounds.GlassSmash, case.glass or case.model.PrimaryPart, sounds.GlassSmashVolume, nil, sounds.GlassSmashSpeed)
	Audio.alarm()
	alarmBanner(case.stand)
end

local function restoreCase(case: Case)
	for _, extra in case.extras do
		extra:Destroy()
	end
	table.clear(case.extras)
	local glass = case.glass
	if glass then
		glass.Color = case.glassColor
		glass.Transparency = case.glassTransparency
		glass.CanCollide = true
	end
	case.cracked = false
	case.broken = false
end

---------------------------------------------------------------- пол и подкоп (Шахтёр)

local nightProps: { Instance } = {} -- дыры, тренога, верёвка: лежат до утра
local skylight: BasePart? = nil
local skylightCut: BasePart? = nil -- стекло с дырой (вместо целого)
local skylightTransparency = 0.6

local function remember(instance: Instance): Instance
	table.insert(nightProps, instance)
	return instance
end

-- Пол под точкой: точка на полу и сама деталь пола (nil — пола нет).
function HeistFx.floorAt(position: Vector3): (Vector3?, BasePart?)
	local params = floorParams
	if not params then
		return nil, nil
	end
	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	if not result then
		return nil, nil
	end
	return result.Position, result.Instance :: BasePart
end

-- Место, где проходу ничего не мешает (стены, постаменты, витрины).
local function isClear(point: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in { MapSchema.Thieves, MapSchema.Tourists } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- украшения без столкновений не мешают
	local parts = Workspace:GetPartBoundsInBox(CFrame.new(point + Vector3.new(0, 2.6, 0)), Vector3.new(3, 4, 3), params)
	return #parts == 0
end

-- Где Шахтёр вылезет: на полу около экспоната (stand — где встаёт вор, look — сам экспонат),
-- в свободном месте и подальше от охраны. nil — места нет.
function HeistFx.digPoint(stand: Vector3, look: Vector3, distance: number, guards: { Vector3 }): Vector3?
	local best, bestScore = nil, -math.huge
	local center = Vector3.new(look.X, stand.Y, look.Z)
	for index = 0, 11 do
		local angle = index * math.pi / 6
		local candidate = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		local floorPoint = HeistFx.floorAt(candidate)
		if floorPoint and math.abs(floorPoint.Y - (stand.Y - 3)) < 1.5 and isClear(floorPoint) then
			local score = minDistance(floorPoint, guards) + math.random()
			if score > bestScore then
				best, bestScore = floorPoint, score
			end
		end
	end
	if not best then
		best = HeistFx.floorAt(stand) -- всё занято: прямо там, где встаёт вор
	end
	return best
end

export type Hole = { point: Vector3, dust: ParticleEmitter?, model: Instance? }

local function dustEmitter(point: Vector3): ParticleEmitter
	local holder = decor("DigDust", Vector3.new(1, 0.2, 1), CFrame.new(point + Vector3.new(0, 0.2, 0)), Heist.DustColor, Enum.Material.SmoothPlastic, Workspace)
	holder.Transparency = 1
	remember(holder)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Heist.DustColor)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Drag = 2.5
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 30
	emitter.Parent = holder
	return emitter
end

-- Перед тем как вылезти, пол трескается: трещины, пыль, глухой гул. Возвращает дыру для openHole.
function HeistFx.crackFloor(point: Vector3): Hole
	local folder = Instance.new("Model")
	folder.Name = "MinerHole"
	folder.Parent = Workspace
	remember(folder)
	for index = 0, 6 do
		local angle = index * 0.9 + math.random() * 0.4
		local length = 1.6 + math.random() * 1.6
		local cframe = CFrame.new(point + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, angle, 0) * CFrame.new(length / 2 + 0.6, 0, 0)
		decor("FloorCrack", Vector3.new(length, 0.04, 0.12), cframe, Heist.HoleColor, Enum.Material.SmoothPlastic, folder)
	end
	local sounds = Config.Sounds
	local anchor = folder:FindFirstChildWhichIsA("BasePart")
	Audio.playOnce(sounds.Dig, anchor, sounds.DigVolume, nil, sounds.DigSpeed)
	return { point = point, dust = dustEmitter(point), model = folder }
end

-- Шахтёр вылезает: пол проваливается, вокруг кучи земли и обломки плитки, облако пыли. Дыра — до утра.
function HeistFx.openHole(hole: Hole)
	local point = hole.point
	local _, floor = HeistFx.floorAt(point)
	local tileColor = if floor then floor.Color else Color3.fromHex("C9BBA0")
	local tileMaterial = if floor then floor.Material else Enum.Material.SmoothPlastic
	local stub: { ModelLibrary.StubPart } = {
		{ name = "Hole", size = Vector3.new(0.06, 3.4, 3.4), offset = CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.pi / 2), color = Heist.HoleColor, shape = Enum.PartType.Cylinder, collide = false },
		{ name = "Rim", size = Vector3.new(0.05, 3.9, 3.9), offset = CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2), color = Heist.DirtColor, material = Enum.Material.Ground, shape = Enum.PartType.Cylinder, collide = false },
	}
	for index = 0, 5 do
		local angle = index * math.pi / 3 + math.random() * 0.4
		local radius = 2.1 + math.random() * 0.5
		local size = 0.7 + math.random() * 0.6
		table.insert(stub, {
			name = "Dirt",
			size = Vector3.new(size * 1.4, size * 0.7, size),
			offset = CFrame.new(math.cos(angle) * radius, size * 0.2, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			color = Heist.DirtColor,
			material = Enum.Material.Ground,
			sphere = true,
			collide = false,
		})
		local tileAngle = angle + 0.5
		table.insert(stub, {
			name = "Tile",
			size = Vector3.new(0.9 + math.random() * 0.5, 0.18, 0.8 + math.random() * 0.4),
			offset = CFrame.new(math.cos(tileAngle) * 2.9, 0.15, math.sin(tileAngle) * 2.9) * CFrame.Angles(math.random() * 0.5 - 0.25, tileAngle, math.random() * 0.6 - 0.3),
			color = tileColor,
			material = tileMaterial,
			collide = false,
		})
	end
	local model = ModelLibrary.place(MapSchema.Models.FloorHole, CFrame.new(point), stub, Workspace)
	ModelLibrary.forEachPart(model, function(part)
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
	end)
	remember(model)
	local dust = hole.dust
	if dust then
		dust.Rate = 160 -- облако пыли, когда он вылезает
		task.delay(0.7, function()
			dust.Rate = 0
		end)
	end
	local sounds = Config.Sounds
	Audio.playOnce(sounds.Dig, model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"), sounds.DigVolume, nil, sounds.DigSpeed * 1.3)
end

---------------------------------------------------------------- стеклянный потолок (Стекольщик)

export type Cut = {
	center: Vector3, -- центр дыры на верхней стороне стекла
	radius: number,
	segments: { BasePart }, -- светящийся след стеклореза
	union: BasePart?, -- стекло с дырой (считается заранее, пока он режет)
	pulley: Vector3, -- блок треноги: верх верёвки
	rope: BasePart?,
}

function HeistFx.skylight(): BasePart?
	return skylight
end

-- Верх стеклянного потолка (y) и проверка, что точка над стеклом не ближе margin к раме.
function HeistFx.skylightPoint(position: Vector3, margin: number): Vector3?
	local glass = skylight
	if not glass then
		return nil
	end
	local localPoint = glass.CFrame:PointToObjectSpace(position)
	local halfX = math.max(0, glass.Size.X / 2 - margin)
	local halfZ = math.max(0, glass.Size.Z / 2 - margin)
	local clamped = Vector3.new(math.clamp(localPoint.X, -halfX, halfX), glass.Size.Y / 2, math.clamp(localPoint.Z, -halfZ, halfZ))
	return glass.CFrame:PointToWorldSpace(clamped)
end

-- Стекольщик начал резать: по стеклу пойдёт светящийся круг; стекло с дырой считаем заранее.
function HeistFx.startCut(center: Vector3, radius: number): Cut
	local segments = {}
	local count = Heist.CutSegments
	local length = 2 * math.pi * radius / count * 1.1
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local cframe = CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0.04, math.sin(angle) * radius)) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		local segment = decor("CutLine", Vector3.new(length, 0.05, 0.1), cframe, Heist.CutLineColor, Enum.Material.Neon, Workspace)
		segment.Transparency = 1
		remember(segment)
		table.insert(segments, segment)
	end
	local cut: Cut = { center = center, radius = radius, segments = segments, union = nil, pulley = center + Vector3.new(0, Heist.PulleyHeight, 0), rope = nil }
	local glass = skylight
	if glass then
		task.spawn(function()
			local cutter = Instance.new("Part")
			cutter.Shape = Enum.PartType.Cylinder
			cutter.Size = Vector3.new(glass.Size.Y + 2, radius * 2, radius * 2)
			cutter.CFrame = CFrame.new(center.X, glass.Position.Y, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
			local ok, result = pcall(function()
				return glass:SubtractAsync({ cutter })
			end)
			cutter:Destroy()
			if ok and result then
				result.Name = "SkylightCut"
				result.Anchored = true
				result.UsePartColor = true
				result.Color = glass.Color
				result.Material = glass.Material
				result.Transparency = glass.Transparency
				result.CastShadow = false
				cut.union = result
			else
				warn("[HeistFx] Не получилось вырезать дыру в стекле:", result)
			end
		end)
	end
	return cut
end

-- Сколько круга уже прорезано (0..1).
function HeistFx.cutProgress(cut: Cut, fraction: number)
	local shown = math.floor(math.clamp(fraction, 0, 1) * #cut.segments + 0.5)
	for index, segment in cut.segments do
		segment.Transparency = if index <= shown then 0 else 1
	end
end

-- Круг прорезан: в стекле дыра, стеклянный диск отложен в сторону, над дырой тренога с блоком.
function HeistFx.finishCut(cut: Cut)
	for _, segment in cut.segments do
		segment.Transparency = 0
		segment.Color = Color3.fromHex("8C9AA6") -- край дыры
		segment.Material = Enum.Material.Metal
	end
	local glass = skylight
	if glass then
		local union = cut.union
		if union and not skylightCut then
			union.Parent = glass.Parent
			skylightCut = union
			glass.Transparency = 1
			glass.CanCollide = false
			glass.CanQuery = false
		end
		-- Вырезанный диск: приподнят и лежит на стекле рядом с дырой
		local disc = decor("GlassDisc", Vector3.new(glass.Size.Y, cut.radius * 2, cut.radius * 2), CFrame.new(cut.center + Vector3.new(cut.radius * 2 + 1.4, 0.2, 0)) * CFrame.Angles(0.1, 0, math.pi / 2), glass.Color, Enum.Material.Glass, Workspace)
		disc.Shape = Enum.PartType.Cylinder
		disc.Transparency = 0.45
		remember(disc)
	end
	-- Тренога: три ноги сходятся над дырой, наверху блок для верёвки
	local apex = Vector3.new(0, Heist.PulleyHeight + 0.3, 0)
	local stub: { ModelLibrary.StubPart } = {
		{ name = "Hub", size = Vector3.new(0.45, 0.45, 0.45), offset = CFrame.new(apex), color = Color3.fromHex("3A3F4B"), material = Enum.Material.Metal, shape = Enum.PartType.Ball },
		{ name = "Pulley", size = Vector3.new(0.18, 0.7, 0.7), offset = CFrame.new(apex - Vector3.new(0, 0.4, 0)), color = Color3.fromHex("C8343A"), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	}
	for index = 0, 2 do
		local angle = index * math.pi * 2 / 3
		local foot = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (cut.radius + 1)
		local middle = (foot + apex) / 2
		table.insert(stub, {
			name = "Leg",
			size = Vector3.new(0.16, (apex - foot).Magnitude, 0.16),
			offset = CFrame.lookAt(middle, apex) * CFrame.Angles(-math.pi / 2, 0, 0),
			color = Color3.fromHex("A9B0BC"),
			material = Enum.Material.Metal,
		})
		table.insert(stub, { name = "Foot", size = Vector3.new(0.4, 0.12, 0.4), offset = CFrame.new(foot + Vector3.new(0, 0.06, 0)), color = Color3.fromHex("2B2F3A"), material = Enum.Material.Rubber })
	end
	local tripod = ModelLibrary.place(MapSchema.Models.Tripod, CFrame.new(cut.center), stub, Workspace)
	ModelLibrary.forEachPart(tripod, function(part)
		part.CanCollide = false
		part.CanQuery = false
	end)
	remember(tripod)
end

-- Верёвка от блока треноги вниз до bottomY (до обвязки вора или до пола).
function HeistFx.setRope(cut: Cut, bottomY: number)
	local top = cut.pulley
	local length = math.max(0.2, top.Y - bottomY)
	local rope = cut.rope
	if not rope then
		local created = decor("GlazierRope", Vector3.new(Heist.RopeThickness, length, Heist.RopeThickness), CFrame.new(top), Heist.RopeColor, Enum.Material.Fabric, Workspace)
		remember(created)
		cut.rope = created
		rope = created
	end
	if rope then
		rope.Size = Vector3.new(Heist.RopeThickness, length, Heist.RopeThickness)
		rope.CFrame = CFrame.new(top.X, top.Y - length / 2, top.Z)
	end
end

---------------------------------------------------------------- день и ночь

-- Утро: витрины целые, следы воров (дыры в полу, тренога, верёвка, дыра в стекле) убраны.
-- Шокер (блок 4): искры по телу и звёздочки над головой у оглушённого вора или грабителя на seconds секунд.
function HeistFx.stunEffect(model: Model, seconds: number)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
	if torso and torso:IsA("BasePart") then
		local old = torso:FindFirstChild("StunSparks")
		if old then
			old:Destroy()
		end
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "StunSparks"
		sparks.Color = ColorSequence.new(Config.Weapons.Taser.Color, Color3.fromRGB(255, 255, 255))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(0.12, 0.3)
		sparks.Speed = NumberRange.new(4, 9)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 40
		sparks.Parent = torso
		task.delay(math.min(seconds, Config.Animations.StunTwitchSeconds), function()
			if sparks.Parent then
				sparks.Rate = 0
				Debris:AddItem(sparks, 0.5)
			end
		end)
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local old = head:FindFirstChild("StunStars")
		if old then
			old:Destroy()
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "StunStars"
		billboard.Size = UDim2.fromScale(3, 1)
		billboard.StudsOffset = Vector3.new(0, 1.6, 0)
		billboard.MaxDistance = 80
		billboard.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Stars"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "★ ⚡ ★"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromHex("FFD23F")
		label.TextStrokeTransparency = 0
		label.Parent = billboard
		billboard.Parent = head
		Debris:AddItem(billboard, seconds)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local shot = Config.Sounds.Shots.Taser
		Audio.playOnce(shot.Id, root, shot.Volume, 1.2, shot.Speed * 0.8)
	end
end

function HeistFx.resetForDay()
	for _, case in cases do
		restoreCase(case)
	end
	for _, instance in nightProps do
		instance:Destroy()
	end
	table.clear(nightProps)
	local cutGlass = skylightCut
	if cutGlass then
		cutGlass:Destroy()
		skylightCut = nil
	end
	local glass = skylight
	if glass then
		glass.Transparency = skylightTransparency
		glass.CanCollide = true
		glass.CanQuery = true
	end
end

function HeistFx.init(map: Instance)
	local geometry = map:FindFirstChild(MapSchema.Geometry)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { geometry or map }
	floorParams = params
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == MapSchema.Models.DisplayCase then
			addCase(descendant)
		end
	end
	if #cases == 0 then
		warn("[HeistFx] На карте нет витрин prop_displaycase_01 — воры не смогут шуметь")
	end
	local glass = map:FindFirstChild(MapSchema.Skylight, true)
	if glass and glass:IsA("BasePart") then
		skylight = glass
		skylightTransparency = glass.Transparency
	else
		warn("[HeistFx] На карте нет стеклянного потолка Skylight — Стекольщик будет входить через дверь")
	end
end

return HeistFx
