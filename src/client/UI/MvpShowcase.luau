--!strict
-- Витрина MVP в итоге ночи (этап 6, блок I3; этап 7, задание K2): ViewportFrame 260×300 с копией лучшего охранника
-- на мраморно-золотом пьедестале, золотой короной над головой, медленным вращением, подписью и позой через
-- Motor6D.Transform (радость с прыжками после пережитой ночи, грустное разведение руками на GAME OVER).
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
	show: (userId: number, displayName: string, arrests: number, gameOver: boolean?) -> (),
	hide: () -> (),
	destroy: () -> (),
}

type Joint = Motor6D | AnimationConstraint
type Pose = { [string]: CFrame }

local JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
}

local function R(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local function smooth(t: number): number
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end

local function collectJoints(character: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, desc in character:GetDescendants() do
		if (desc:IsA("Motor6D") or desc:IsA("AnimationConstraint")) and table.find(JOINTS, desc.Name) then
			joints[desc.Name] = desc
		end
	end
	return joints
end

local function applyPose(joints: { [string]: Joint }, pose: Pose)
	for name, joint in joints do
		local transform = pose[name] or CFrame.identity
		if joint:IsA("Motor6D") then
			joint.Transform = transform
		elseif joint:IsA("AnimationConstraint") then
			joint.Transform = transform
		end
	end
end

-- Радость пережитой ночи: подпрыгивает и весело машет поднятыми руками (цикл ~2 сек).
local function celebratePose(t: number): (Pose, number)
	local period = math.max(0.5, Settings.MvpCelebratePeriod)
	local p = (t % period) / period
	local rootY = 0
	local hipBend = 0
	local kneeBend = 0
	if p < 0.14 then
		local k = smooth(p / 0.14)
		rootY = -0.16 * k
		hipBend = 0.24 * k
		kneeBend = -0.45 * k
	elseif p < 0.60 then
		local air = math.sin((p - 0.14) / 0.46 * math.pi)
		rootY = Settings.MvpJumpHeight * air
		hipBend = 0.30 * air
		kneeBend = -0.55 * air
	elseif p < 0.78 then
		local land = math.sin((p - 0.60) / 0.18 * math.pi)
		rootY = -0.14 * land
		hipBend = 0.20 * land
		kneeBend = -0.38 * land
	end

	local wave = math.sin(p * math.pi * 4)
	local waveCos = math.cos(p * math.pi * 4)
	local sway = math.sin(p * math.pi * 2)

	local pose: Pose = {
		Root = CFrame.new(0, rootY, 0) * R(0, 0, 0.04 * sway),
		Waist = R(0.06 * math.max(0, rootY), 0.12 * sway, 0.05 * waveCos),
		Neck = R(0.14 + 0.06 * wave, 0.12 * sway, 0.06 * waveCos),
		LeftShoulder = R(2.78 + 0.20 * wave, 0, -0.38 - 0.20 * waveCos),
		RightShoulder = R(2.78 - 0.20 * wave, 0, 0.38 + 0.20 * waveCos),
		LeftElbow = R(0.35 + 0.22 * wave),
		RightElbow = R(0.35 - 0.22 * wave),
		LeftWrist = R(0, 0, -0.15 * waveCos),
		RightWrist = R(0, 0, 0.15 * waveCos),
		LeftHip = R(hipBend + 0.06 * sway, 0, -0.06),
		RightHip = R(hipBend - 0.06 * sway, 0, 0.06),
		LeftKnee = R(kneeBend),
		RightKnee = R(kneeBend),
		LeftAnkle = R(-hipBend - kneeBend * 0.5),
		RightAnkle = R(-hipBend - kneeBend * 0.5),
	}
	return pose, rootY
end

-- Грусть на GAME OVER: поникшая голова и разведённые в стороны руки.
local function sadPose(t: number): (Pose, number)
	local sway = math.sin(t * Settings.MvpSadSwaySpeed)
	local shrug = 0.5 + 0.5 * math.sin(t * Settings.MvpSadSwaySpeed * 1.25)
	local rootY = -0.08
	local pose: Pose = {
		Root = CFrame.new(0, rootY, 0),
		Waist = R(-0.18 - 0.03 * shrug, 0, 0.04 * sway),
		Neck = R(-0.36 - 0.05 * shrug, 0.22 * sway, 0.08 * sway),
		LeftShoulder = R(0.55 + 0.16 * shrug, -0.25, -0.78 - 0.18 * shrug),
		RightShoulder = R(0.55 + 0.16 * shrug, 0.25, 0.78 + 0.18 * shrug),
		LeftElbow = R(0.88 + 0.12 * shrug),
		RightElbow = R(0.88 + 0.12 * shrug),
		LeftWrist = R(0, 0, 0.35),
		RightWrist = R(0, 0, -0.35),
		LeftHip = R(0.10, 0, -0.04),
		RightHip = R(0.10, 0, 0.04),
		LeftKnee = R(-0.18),
		RightKnee = R(-0.18),
		LeftAnkle = R(0.08),
		RightAnkle = R(0.08),
	}
	return pose, rootY
end

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
			or desc:IsA("Animator")
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
		elseif desc:IsA("AnimationConstraint") then
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

	-- Фиксируем только корень, а части тела и аксессуары на суставах/сварках оставляем свободными для Motor6D.Transform.
	local connected: { [BasePart]: boolean } = {}
	if root and root:IsA("BasePart") then
		connected[root] = true
		local changed = true
		while changed do
			changed = false
			for _, desc in cloned:GetDescendants() do
				if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
					local p0 = desc.Part0
					local p1 = desc.Part1
					if p0 and p1 then
						if connected[p0] and not connected[p1] then
							connected[p1] = true
							changed = true
						elseif connected[p1] and not connected[p0] then
							connected[p0] = true
							changed = true
						end
					end
				elseif desc:IsA("AnimationConstraint") then
					local a0 = desc.Attachment0
					local a1 = desc.Attachment1
					local ap0 = if a0 then a0.Parent else nil
					local ap1 = if a1 then a1.Parent else nil
					if ap0 and ap1 and ap0:IsA("BasePart") and ap1:IsA("BasePart") then
						if connected[ap0] and not connected[ap1] then
							connected[ap1] = true
							changed = true
						elseif connected[ap1] and not connected[ap0] then
							connected[ap0] = true
							changed = true
						end
					end
				end
			end
		end
	end
	for _, desc in cloned:GetDescendants() do
		if desc:IsA("BasePart") then
			if root and desc == root then
				desc.Anchored = true
			elseif root and connected[desc] then
				desc.Anchored = false
			else
				desc.Anchored = true
			end
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

	local function show(userId: number, displayName: string, arrests: number, gameOver: boolean?)
		clearScene()
		caption.Text = formatLabel(displayName, arrests)
		frame.Visible = true
		local isGameOver = gameOver == true

		local scene = Instance.new("Model")
		scene.Name = "MvpScene"
		scene.Parent = world
		sceneModel = scene

		local pedestalTopY = buildPedestal(scene)
		local player = Players:GetPlayerByUserId(userId)
		local sourceChar = if player then player.Character else nil
		local crownBaseY = pedestalTopY + 0.8
		local clonedChar: Model? = nil
		if sourceChar then
			local charModel, computedCrownY = cloneCharacterOnPedestal(sourceChar, scene, pedestalTopY)
			clonedChar = charModel
			crownBaseY = computedCrownY
		end
		local joints = if clonedChar then collectJoints(clonedChar) else {}

		local crown = buildCrown(scene, crownBaseY)

		local boxCF, boxSize = scene:GetBoundingBox()
		local center = boxCF.Position
		local halfFov = math.rad(Settings.MvpFieldOfView / 2)
		local tanHalf = math.tan(halfFov)
		local aspect = vpW / vpH
		local distV = (boxSize.Y / 2) / tanHalf
		local distH = (math.max(boxSize.X, boxSize.Z) / 2) / (tanHalf * aspect)
		local distance = math.max(distV, distH) * Settings.MvpCameraMargin

		local angle = 0.35
		local elapsed = 0
		local function updatePose()
			local rot = CFrame.Angles(0, angle, 0)
			local dir = (rot * Vector3.new(0, 0.16, -1)).Unit
			camera.CFrame = CFrame.lookAt(center + dir * distance, center)
			viewport.LightDirection = (rot * Vector3.new(-0.45, -0.75, 0.75)).Unit
			local pose: Pose, rootY: number
			if isGameOver then
				pose, rootY = sadPose(elapsed)
			else
				pose, rootY = celebratePose(elapsed)
			end
			applyPose(joints, pose)
			local bob = math.sin(elapsed * Settings.MvpCrownFloatSpeed) * Settings.MvpCrownFloatAmplitude
			crown:PivotTo(CFrame.new(0, crownBaseY + bob + rootY, 0))
		end

		updatePose()
		spinConn = RunService.RenderStepped:Connect(function(dt: number)
			if not frame.Visible then
				return
			end
			local stepDt = math.min(dt, 0.1)
			angle += stepDt * Settings.MvpSpinSpeed
			elapsed += stepDt
			updatePose()
		end)
	end

	local function hide()
		frame.Visible = false
		clearScene()
	end

	local destroyConn: RBXScriptConnection? = frame.Destroying:Connect(clearScene)

	local function destroy()
		if destroyConn then
			destroyConn:Disconnect()
			destroyConn = nil
		end
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
