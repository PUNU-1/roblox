-- Лазерная сетка. В подготовке отмеченные места светятся, игрок подходит и держит E —
-- из пола вырастают стойки с красными лучами. За ночь можно поставить 3 сетки из 5 мест.
-- Ночью вор, прошедший сквозь лучи, замедляется на 5 сек и подсвечивается для всех сквозь стены.
-- После срабатывания сетка перезаряжается.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local Server = script.Parent
local ModelLibrary = require(Server:WaitForChild("ModelLibrary"))
local RoleService = require(Server:WaitForChild("RoleService"))

local Laser = Config.Traps.LaserGrid
local EMITTER_HEIGHTS = { 1, 2.5, 4 } -- как в задании 4 для Gemini
local POST_OFFSET = 4 -- стойки в x = -4 и x = +4

local TrapService = {}

type Trap = {
	slot: BasePart,
	model: PVInstance,
	beams: { Beam },
	zone: Part,
	readyAt: number, -- когда сетка снова сработает
}

local slots: { BasePart } = {}
local prompts: { [BasePart]: ProximityPrompt } = {}
local traps: { [BasePart]: Trap } = {}
local placedFolder: Folder
local placedCount = 0
local checkConnection: RBXScriptConnection? = nil
local highlightTokens: { [Model]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setLasersLeft()
	GameState.set(GameState.Attr.LasersLeft, math.max(0, Laser.MaxPerNight - placedCount))
end

-- Заглушка, пока друг не сделал trap_laser_01: две стойки PostA/PostB с излучателями Emitter1-3.
local function buildStubLaser(): Model
	local model = Instance.new("Model")
	model.Name = MapSchema.Models.LaserGrid
	local dark = Color3.fromHex("2A2F3A")
	for _, side in { { "PostA", -1 }, { "PostB", 1 } } do
		local post = Instance.new("Model")
		post.Name = side[1] :: string
		local x = POST_OFFSET * (side[2] :: number)
		local function part(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = CFrame.new(position)
			p.Color = color
			p.Material = material
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = post
			return p
		end
		part("Base", Vector3.new(1, 0.3, 1), Vector3.new(x, 0.15, 0), dark, Enum.Material.Metal)
		part("Pole", Vector3.new(0.4, 5, 0.4), Vector3.new(x, 2.5, 0), dark, Enum.Material.Metal)
		part("Cap", Vector3.new(0.6, 0.3, 0.6), Vector3.new(x, 5.15, 0), Laser.BeamColor, Enum.Material.SmoothPlastic)
		for index, height in EMITTER_HEIGHTS do
			local emitter = part(
				"Emitter" .. index,
				Vector3.new(0.3, 0.3, 0.3),
				Vector3.new(x - 0.3 * (side[2] :: number), height, 0),
				Laser.BeamColor,
				Enum.Material.Neon
			)
			emitter.CanCollide = false
			local attachment = Instance.new("Attachment")
			attachment.Name = "Laser"
			attachment.Parent = emitter
		end
		post.Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

local function buildLaserModel(): PVInstance
	if ModelLibrary.has(MapSchema.Models.LaserGrid) then
		return ModelLibrary.build(MapSchema.Models.LaserGrid, {})
	end
	return buildStubLaser()
end

local function findLaserAttachment(model: Instance, postName: string, index: number): Attachment?
	local post = model:FindFirstChild(postName, true)
	local emitter = post and post:FindFirstChild("Emitter" .. index, true)
	local attachment = emitter and emitter:FindFirstChild("Laser")
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	return nil
end

local function setBeams(trap: Trap, enabled: boolean)
	for _, beam in trap.beams do
		beam.Enabled = enabled
	end
end

local function createBeams(model: PVInstance): { Beam }
	local beams = {}
	for index = 1, #EMITTER_HEIGHTS do
		local a = findLaserAttachment(model, "PostA", index)
		local b = findLaserAttachment(model, "PostB", index)
		if a and b then
			local beam = Instance.new("Beam")
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.Color = ColorSequence.new(Laser.BeamColor)
			beam.Width0 = Laser.BeamWidth
			beam.Width1 = Laser.BeamWidth
			beam.LightEmission = 1
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Parent = model
			table.insert(beams, beam)
		end
	end
	if #beams == 0 then
		warn("[TrapService] В модели сетки нет PostA/PostB с Emitter1-3 и Attachment Laser — лучей не будет")
	end
	return beams
end

local function refreshPrompts()
	local canPlace = GameState.phase() == GameState.Phase.Prep and placedCount < Laser.MaxPerNight
	for slot, prompt in prompts do
		prompt.Enabled = canPlace and traps[slot] == nil
	end
end

local function placeTrap(slot: BasePart)
	-- Сетка встаёт поперёк прохода: лучи вдоль длинной стороны отмеченного места
	local rotation = if slot.Size.Z > slot.Size.X then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity
	local target = CFrame.new(slot.Position.X, 0, slot.Position.Z) * rotation
	local start = target - Vector3.new(0, Laser.RiseDepth, 0)

	local model = buildLaserModel()
	ModelLibrary.forEachPart(model, function(part)
		part.Anchored = true
	end)
	model:PivotTo(start)
	model.Parent = placedFolder

	local length = math.max(slot.Size.X, slot.Size.Z)
	local zone = Instance.new("Part")
	zone.Name = "LaserZone"
	zone.Size = Vector3.new(length, Laser.ZoneHeight, Laser.ZoneThickness)
	-- Зона лежит внутри модели и поднимается вместе со стойками, поэтому ставим её
	-- от начальной (подземной) точки: после подъёма она окажется ровно на полу.
	zone.CFrame = start * CFrame.new(0, Laser.ZoneHeight / 2, 0)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = model

	local trap: Trap = { slot = slot, model = model, beams = {}, zone = zone, readyAt = 0 }
	traps[slot] = trap
	slot.Transparency = 1

	-- Стойки вырастают из пола
	local alpha = Instance.new("NumberValue")
	alpha.Changed:Connect(function(value)
		if model.Parent then
			model:PivotTo(start:Lerp(target, value))
		end
	end)
	local tween = TweenService:Create(alpha, TweenInfo.new(Laser.RiseSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
	tween.Completed:Once(function()
		alpha:Destroy()
		if model.Parent then
			model:PivotTo(target)
			trap.beams = createBeams(model)
		end
	end)
	tween:Play()
end

local function tryPlace(player: Player, slot: BasePart)
	if GameState.phase() ~= GameState.Phase.Prep or traps[slot] or placedCount >= Laser.MaxPerNight then
		return
	end
	if not RoleService.isParticipant(player) or RoleService.isViewing(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local maxDistance = Laser.PromptDistance + Config.Catch.ServerDistanceSlack
	if not (root and root:IsA("BasePart")) or (root.Position - slot.Position).Magnitude > maxDistance then
		return
	end
	placedCount += 1
	setLasersLeft()
	placeTrap(slot)
	refreshPrompts()
end

---------------------------------------------------------------- срабатывание

local function thiefFromPart(part: BasePart, thievesFolder: Instance): Model?
	local current: Instance? = part
	while current and current.Parent ~= thievesFolder do
		current = current.Parent
	end
	if current and current:IsA("Model") then
		return current
	end
	return nil
end

local function slowAndHighlight(thief: Model)
	thief:SetAttribute("SlowedUntil", now() + Laser.SlowSeconds)
	local highlight = thief:FindFirstChild("LaserHighlight")
	if not (highlight and highlight:IsA("Highlight")) then
		local created = Instance.new("Highlight")
		created.Name = "LaserHighlight"
		created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- видно сквозь стены
		created.FillColor = Config.Effects.SlowHighlightColor
		created.OutlineColor = Config.Effects.SlowHighlightColor
		created.FillTransparency = 0.5
		created.Parent = thief
	end
	local token = (highlightTokens[thief] or 0) + 1
	highlightTokens[thief] = token
	task.delay(Laser.SlowSeconds, function()
		if highlightTokens[thief] == token then
			highlightTokens[thief] = nil
			local existing = thief:FindFirstChild("LaserHighlight")
			if existing then
				existing:Destroy()
			end
		end
	end)
end

local function checkTraps()
	local thievesFolder = Workspace:FindFirstChild(MapSchema.Thieves)
	if not thievesFolder then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { thievesFolder }
	local time = now()
	for _, trap in traps do
		if time >= trap.readyAt and trap.model.Parent then
			setBeams(trap, true)
			local hit: { [Model]: boolean } = {}
			for _, part in Workspace:GetPartBoundsInBox(trap.zone.CFrame, trap.zone.Size, params) do
				local thief = thiefFromPart(part, thievesFolder)
				if thief and not hit[thief] then
					hit[thief] = true
					slowAndHighlight(thief)
				end
			end
			if next(hit) then
				trap.readyAt = time + Laser.RechargeSeconds
				setBeams(trap, false)
			end
		end
	end
end

---------------------------------------------------------------- фазы

local function showSlots(visible: boolean)
	for _, slot in slots do
		slot.Transparency = if visible and not traps[slot] then Laser.SlotGlowTransparency else 1
	end
end

function TrapService.beginPrep()
	TrapService.clear()
	placedCount = 0
	setLasersLeft()
	showSlots(true)
	refreshPrompts()
end

function TrapService.beginNight()
	showSlots(false)
	refreshPrompts()
	local accumulator = 0
	checkConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Laser.CheckSeconds then
			accumulator = 0
			checkTraps()
		end
	end)
end

function TrapService.clear()
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end
	for _, trap in traps do
		trap.model:Destroy()
	end
	table.clear(traps)
	table.clear(highlightTokens)
	placedCount = 0
	showSlots(false)
	refreshPrompts()
end

function TrapService.init(map: Instance)
	local existing = Workspace:FindFirstChild(MapSchema.PlacedTraps)
	if existing and existing:IsA("Folder") then
		placedFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = MapSchema.PlacedTraps
		created.Parent = Workspace
		placedFolder = created
	end

	local slotFolder = map:FindFirstChild(MapSchema.TrapSlots)
	if slotFolder then
		for _, child in slotFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(slots, child)
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "PlacePrompt"
				prompt.ActionText = "Place laser grid"
				prompt.ObjectText = "Trap spot"
				prompt.HoldDuration = Laser.PlaceHoldSeconds
				prompt.MaxActivationDistance = Laser.PromptDistance
				prompt.RequiresLineOfSight = false
				prompt.Enabled = false
				prompt.Parent = child
				prompt.Triggered:Connect(function(player)
					tryPlace(player, child)
				end)
				prompts[child] = prompt
			end
		end
	end
	showSlots(false)
end

return TrapService
