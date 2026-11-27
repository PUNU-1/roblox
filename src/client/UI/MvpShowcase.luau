--!strict
-- Витрина MVP в итоге ночи (этап 6, блок I3): ViewportFrame 260×300 с копией лучшего охранника
-- на мраморно-золотом пьедестале, золотой короной над головой, медленным вращением и подписью.
-- При закрытии окна итога отключает RenderStepped и уничтожает клон персонажа без утечек.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelWindow = require(script.Parent:WaitForChild("PixelWindow"))

local Colors = Theme.Colors
local Settings = Config.Results

local MvpShowcase = {}

export type Showcase = {
	frame: Frame,
	width: number,
	height: number,
	show: (userId: number, displayName: string, arrests: number) -> (),
	hide: () -> (),
	destroy: () -> (),
}

local BOX_PAD = 8
local HEADER_H = 22
local LABEL_H = 44
local CROWN_SPIKES = 6

local PALETTE = {
	Marble = Color3.fromHex("E8DCC4"),
	Gold = Color3.fromHex("D4A93A"),
	GoldGlow = Color3.fromHex("FFE066"),
	Navy = Color3.fromHex("1E2A44"),
	Red = Color3.fromHex("C8343A"),
	Turquoise = Color3.fromHex("3BC6C1"),
}

-- Вспомогательная функция создания неподвижной детали витрины без коллизий.
local function makePart(props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	reflectance: number?,
	parent: Instance,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Shape = props.shape or Enum.PartType.Block
	part.Reflectance = props.reflectance or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.parent
	return part
end

-- Пьедестал: ступенчатое тёмно-синее основание, золотая окантовка и мраморная колонна (верх на pedestalHeight).
local function buildPedestal(parent: Instance): number
	local pedestal = Instance.new("Model")
	pedestal.Name = "Pedestal"
	local topY = Settings.MvpPedestalHeight
	local upright = CFrame.Angles(0, 0, math.pi / 2)

	makePart({
		name = "BasePlinth",
		size = Vector3.new(4.2, 0.34, 4.2),
		cframe = CFrame.new(0, 0.17, 0),
		color = PALETTE.Navy,
		material = Enum.Material.SmoothPlastic,
		parent = pedestal,
	})
	makePart({
		name = "BaseGoldTrim",
		size = Vector3.new(3.9, 0.14, 3.9),
		cframe = CFrame.new(0, 0.41, 0),
		color = PALETTE.Gold,
		material = Enum.Material.Metal,
		reflectance = 0.25,
		parent = pedestal,
	})
	makePart({
		name = "MarbleColumn",
		size = Vector3.new(0.78, 3.1, 3.1),
		cframe = CFrame.new(0, 0.87, 0) * upright,
		color = PALETTE.Marble,
		material = Enum.Material.Marble,
		shape = Enum.PartType.Cylinder,
		parent = pedestal,
	})
	makePart({
		name = "TopGoldTrim",
		size = Vector3.new(0.16, 3.55, 3.55),
		cframe = CFrame.new(0, topY - 0.26, 0) * upright,
		color = PALETTE.Gold,
		material = Enum.Material.Metal,
		reflectance = 0.25,
		shape = Enum.PartType.Cylinder,
		parent = pedestal,
	})
	makePart({
		name = "TopMarbleDeck",
		size = Vector3.new(0.18, 3.35, 3.35),
		cframe = CFrame.new(0, topY - 0.09, 0) * upright,
		color = PALETTE.Marble,
		material = Enum.Material.Marble,
		shape = Enum.PartType.Cylinder,
		parent = pedestal,
	})
	-- Передняя табличка со звездой на основании (-Z)
	makePart({
		name = "FrontPlaque",
		size = Vector3.new(1.7, 0.24, 0.08),
		cframe = CFrame.new(0, 0.2, -2.12),
		color = PALETTE.Gold,
		material = Enum.Material.Metal,
		reflectance = 0.25,
		parent = pedestal,
	})
	makePart({
		name = "FrontGem",
		size = Vector3.new(0.18, 0.18, 0.1),
		cframe = CFrame.new(0, 0.2, -2.15) * CFrame.Angles(0, 0, math.rad(45)),
		color = PALETTE.Turquoise,
		material = Enum.Material.Neon,
		parent = pedestal,
	})

	pedestal.Parent = parent
	return topY
end

-- Золотая корона с зубцами, тёмно-синей шапкой и самоцветами. Возвращает модель и базовую высоту Y.
local function buildCrown(parent: Instance, baseY: number): Model
	local crown = Instance.new("Model")
	crown.Name = "MvpCrown"
	local upright = CFrame.Angles(0, 0, math.pi / 2)

	makePart({
		name = "CrownRim",
		size = Vector3.new(0.12, 1.46, 1.46),
		cframe = CFrame.new(0, baseY + 0.06, 0) * upright,
		color = PALETTE.Gold,
		material = Enum.Material.Metal,
		reflectance = 0.3,
		shape = Enum.PartType.Cylinder,
		parent = crown,
	})
	makePart({
		name = "CrownBand",
		size = Vector3.new(0.32, 1.32, 1.32),
		cframe = CFrame.new(0, baseY + 0.24, 0) * upright,
		color = PALETTE.Gold,
		material = Enum.Material.Metal,
		reflectance = 0.3,
		shape = Enum.PartType.Cylinder,
		parent = crown,
	})
	makePart({
		name = "CrownVelvet",
		size = Vector3.new(0.34, 1.08, 1.08),
		cframe = CFrame.new(0, baseY + 0.25, 0) * upright,
		color = PALETTE.Navy,
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Cylinder,
		parent = crown,
	})

	local radius = 0.6
	for i = 1, CROWN_SPIKES do
		local theta = (i - 1) * (math.pi * 2 / CROWN_SPIKES)
		local cx = math.sin(theta) * radius
		local cz = -math.cos(theta) * radius
		local rotY = CFrame.Angles(0, -theta, 0)

		makePart({
			name = "Spike" .. i,
			size = Vector3.new(0.24, 0.36, 0.14),
			cframe = CFrame.new(cx, baseY + 0.54, cz) * rotY,
			color = PALETTE.Gold,
			material = Enum.Material.Metal,
			reflectance = 0.3,
			parent = crown,
		})
		makePart({
			name = "TipPearl" .. i,
			size = Vector3.new(0.16, 0.16, 0.16),
			cframe = CFrame.new(cx, baseY + 0.74, cz),
			color = PALETTE.GoldGlow,
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			parent = crown,
		})
		if i % 2 == 1 then
			makePart({
				name = "BandGem" .. i,
				size = Vector3.new(0.14, 0.14, 0.14),
				cframe = CFrame.new(math.sin(theta) * (radius + 0.08), baseY + 0.24, -math.cos(theta) * (radius + 0.08)),
				color = if i == 1 then PALETTE.Red else PALETTE.Turquoise,
				material = Enum.Material.Neon,
				shape = Enum.PartType.Ball,
				parent = crown,
			})
		end
	end

	crown.WorldPivot = CFrame.new(0, baseY, 0)
	crown.Parent = parent
	return crown
end

-- Очищает клон персонажа от скриптов и лишних эффектов, ставит ногами на пьедестал и возвращает верх головы.
local function cloneCharacterOnPedestal(source: Model, parent: Instance, pedestalTopY: number): (Model?, number)
	local prevArch = source.Archivable
	source.Archivable = true
	local ok, cloned = pcall(source.Clone, source)
	source.Archivable = prevArch
	if not ok or not cloned or not cloned:IsA("Model") then
		return nil, pedestalTopY + 0.8
	end

	local toRemove: { Instance } = {}
	for _, desc in cloned:GetDescendants() do
		if desc:IsA("LuaSourceContainer")
			or desc:IsA("ForceField")
			or desc:IsA("ProximityPrompt")
			or desc:IsA("BillboardGui")
			or desc:IsA("SpotLight")
			or desc:IsA("PointLight")
			or desc:IsA("SurfaceLight")
			or desc:IsA("Sound")
			or desc:IsA("ParticleEmitter")
			or desc:IsA("Highlight")
		then
			table.insert(toRemove, desc)
		elseif desc:IsA("Motor6D") then
			desc.Transform = CFrame.identity
		elseif desc:IsA("Humanoid") then
			desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			desc.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			desc.PlatformStand = true
		elseif desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			desc.CastShadow = false
			desc.LocalTransparencyModifier = 0
		end
	end
	for _, inst in toRemove do
		inst:Destroy()
	end

	-- Выравниваем персонажа вертикально лицом в −Z
	local root = cloned:FindFirstChild("HumanoidRootPart")
		or cloned:FindFirstChild("UpperTorso")
		or cloned:FindFirstChild("Torso")
	if root and root:IsA("BasePart") then
		cloned.PrimaryPart = root
		cloned.WorldPivot = root.CFrame
		cloned:PivotTo(CFrame.new(0, 10, 0))
	end

	-- Ищем низ стоп, чтобы персонаж стоял ровно на верхней плите пьедестала
	local minFootY: number? = nil
	for _, footName in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local foot = cloned:FindFirstChild(footName)
		if foot and foot:IsA("BasePart") then
			local bottom = foot.Position.Y - foot.Size.Y / 2
			minFootY = if minFootY then math.min(minFootY, bottom) else bottom
		end
	end
	local footBottomY: number
	if minFootY then
		footBottomY = minFootY
	else
		local boxCF, boxSize = cloned:GetBoundingBox()
		footBottomY = boxCF.Position.Y - boxSize.Y / 2
	end

	cloned:PivotTo(cloned:GetPivot() + Vector3.new(0, pedestalTopY - footBottomY, 0))
	for _, desc in cloned:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	-- Верх головы с учётом волос, шапки или каски класса, но без огромных крыльев за спиной
	local head = cloned:FindFirstChild("Head")
	local headCenterY = if head and head:IsA("BasePart") then head.Position.Y else (pedestalTopY + 4.3)
	local headTopY = if head and head:IsA("BasePart") then head.Position.Y + head.Size.Y / 2 else (pedestalTopY + 4.9)
	for _, desc in cloned:GetDescendants() do
		if desc:IsA("BasePart") and desc.Transparency < 1 then
			local pos = desc.Position
			if math.abs(pos.X) < 1.4 and math.abs(pos.Z) < 1.4 and pos.Y >= headCenterY - 0.2 and desc.Size.Y < 4 then
				headTopY = math.max(headTopY, pos.Y + desc.Size.Y / 2)
			end
		end
	end

	cloned.Parent = parent
	return cloned, headTopY + Settings.MvpCrownGap
end

local function formatLabel(displayName: string, arrests: number): string
	local unit = if arrests == 1 then "arrest" else "arrests"
	return ("MVP — %s — %d %s"):format(displayName, arrests, unit)
end

-- Создаёт карточку витрины MVP и возвращает управление ею (show / hide / destroy).
function MvpShowcase.new(parent: Instance, zIndex: number?): Showcase
	local z = zIndex or 6
	local vpW = Settings.MvpWidth
	local vpH = Settings.MvpHeight
	local frameW = vpW + BOX_PAD * 2
	local frameH = HEADER_H + vpH + LABEL_H + BOX_PAD * 2 + 4

	local frame = Theme.new("Frame", {
		Name = "MvpShowcase",
		Size = UDim2.fromOffset(frameW, frameH),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	PixelWindow.box(frame, Colors.Dark, Colors.Gold)
	for _, child in frame:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = math.max(child.ZIndex, z)
		end
	end

	Theme.pixelLabel({
		Name = "MvpHeader",
		Position = UDim2.fromOffset(BOX_PAD, BOX_PAD),
		Size = UDim2.fromOffset(vpW, HEADER_H),
		Text = "NIGHT MVP",
		TextColor3 = Colors.Gold,
		ZIndex = z + 2,
		Parent = frame,
	}, 12, 2)

	-- Мягкая золотая подсветка позади тёмно-синей формы охранника
	Theme.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(BOX_PAD + vpW / 2, BOX_PAD + HEADER_H + vpH / 2),
		Size = UDim2.fromOffset(210, 210),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.82,
		ZIndex = z + 1,
		Parent = frame,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

	local viewport: ViewportFrame = Theme.new("ViewportFrame", {
		Name = "MvpViewport",
		Position = UDim2.fromOffset(BOX_PAD, BOX_PAD + HEADER_H),
		Size = UDim2.fromOffset(vpW, vpH),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(165, 165, 180),
		LightColor = Color3.fromRGB(255, 248, 232),
		LightDirection = Vector3.new(-0.45, -0.75, 0.75),
		ZIndex = z + 2,
		Parent = frame,
	})

	local world = Instance.new("WorldModel")
	world.Name = "MvpWorld"
	world.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = Settings.MvpFieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local caption = Theme.label({
		Name = "MvpCaption",
		Position = UDim2.fromOffset(BOX_PAD, BOX_PAD + HEADER_H + vpH + 2),
		Size = UDim2.fromOffset(vpW, LABEL_H),
		Font = Theme.BodyFont,
		TextColor3 = Colors.Gold,
		TextWrapped = true,
		MaxTextSize = 20,
		ZIndex = z + 2,
		Parent = frame,
	})
	Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = caption })

	local sceneModel: Model? = nil
	local spinConn: RBXScriptConnection? = nil

	local function clearScene()
		if spinConn then
			spinConn:Disconnect()
			spinConn = nil
		end
		if sceneModel then
			sceneModel:Destroy()
			sceneModel = nil
		end
	end

	local function show(userId: number, displayName: string, arrests: number)
		clearScene()
		caption.Text = formatLabel(displayName, arrests)
		frame.Visible = true

		local scene = Instance.new("Model")
		scene.Name = "MvpScene"
		scene.Parent = world
		sceneModel = scene

		local pedestalTopY = buildPedestal(scene)
		local player = Players:GetPlayerByUserId(userId)
		local sourceChar = if player then player.Character else nil
		local crownBaseY = pedestalTopY + 0.8
		if sourceChar then
			local _, computedCrownY = cloneCharacterOnPedestal(sourceChar, scene, pedestalTopY)
			crownBaseY = computedCrownY
		end

		local crown = buildCrown(scene, crownBaseY)

		local boxCF, boxSize = scene:GetBoundingBox()
		local center = boxCF.Position
		local halfFov = math.rad(Settings.MvpFieldOfView / 2)
		local tanHalf = math.tan(halfFov)
		local aspect = vpW / vpH
		local distV = (boxSize.Y / 2) / tanHalf
		local distH = (math.max(boxSize.X, boxSize.Z) / 2) / (tanHalf * aspect)
		local distance = math.max(distV, distH) * 1.15

		local angle = 0.35
		local elapsed = 0
		local function updatePose()
			local rot = CFrame.Angles(0, angle, 0)
			local dir = (rot * Vector3.new(0, 0.16, -1)).Unit
			camera.CFrame = CFrame.lookAt(center + dir * distance, center)
			viewport.LightDirection = (rot * Vector3.new(-0.45, -0.75, 0.75)).Unit
			local bob = math.sin(elapsed * Settings.MvpCrownFloatSpeed) * Settings.MvpCrownFloatAmplitude
			crown:PivotTo(CFrame.new(0, crownBaseY + bob, 0))
		end

		updatePose()
		spinConn = RunService.RenderStepped:Connect(function(dt: number)
			if not frame.Visible then
				return
			end
			angle += dt * Settings.MvpSpinSpeed
			elapsed += dt
			updatePose()
		end)
	end

	local function hide()
		frame.Visible = false
		clearScene()
	end

	local function destroy()
		hide()
		frame:Destroy()
	end

	return {
		frame = frame,
		width = frameW,
		height = frameH,
		show = show,
		hide = hide,
		destroy = destroy,
	}
end

return MvpShowcase
