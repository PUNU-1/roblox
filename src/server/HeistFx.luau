-- Эффекты краж на карте (блок 3). Только то, что видно и слышно; решения принимает ThiefService.
--  • Витрины (prop_displaycase_01): вор пинает витрину — стекло трескается, Громила разбивает — осколки;
--    в обоих случаях тревога «GLASS ALARM — место!».
--  • Названия мест для надписей: атрибут Area у пола (MapBuilder).
--  • Всё, что воры оставили за ночь (трещины, осколки), убирается утром: HeistFx.resetForDay().

local Debris = game:GetService("Debris")
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

---------------------------------------------------------------- день и ночь

-- Утро: витрины целые, следы воров убраны.
function HeistFx.resetForDay()
	for _, case in cases do
		restoreCase(case)
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
end

return HeistFx
