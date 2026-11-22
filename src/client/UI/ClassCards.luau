-- Карточки классов в лобби (блок 5): 5 карточек внизу экрана. На каждой — 3D-картинка класса в ViewportFrame
-- (кроссовок патруля, телефон с камерой, датчик движения, собака, бронежилет с автоматом), название, умение,
-- клавиша и сколько игроков уже выбрали этот класс. Выбранная карточка приподнята, в золотой рамке.
-- Выбор — клавишами 1–5 (их ловит HUD.client) или пальцем по карточке. Курсор не освобождается (решение 56).
-- Этап 4, блок 1: некупленный класс — серая карточка с замком и ценой в алмазах 💎 (GameState.ownsClass);
-- что делать при нажатии на неё (открыть магазин или подсказать), решает тот, кто создал карточки.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local ClassModels = require(Shared:WaitForChild("ClassModels"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local DogAnimator = require(script.Parent.Parent:WaitForChild("DogAnimator"))

local Colors = Theme.Colors
local Classes = Config.Classes

local ClassCards = {}

export type Cards = {
	frame: Frame,
	setVisible: (visible: boolean) -> (),
	refresh: (role: string) -> (),
}

local CARD_W, CARD_H, GAP, HEADER = 128, 200, 10, 34
local LIFT = 10 -- выбранная карточка приподнята на столько пикселей

-- Описание умения на карточке (числа — из Config).
local function infoText(role: string, touchOnly: boolean): string
	local function key(label: string): string
		return if touchOnly then "" else label .. ": "
	end
	local text = ""
	if role == "Patrol" then
		local p = Classes.Patrol
		text = ("%sdash at speed %d for %d s. Cooldown %d s."):format(key(p.KeyLabel), p.SprintSpeed, p.SprintSeconds, p.SprintCooldown)
	elseif role == "Operator" then
		text = key(Classes.Operator.KeyLabel) .. "phone with all cameras and marks. Can't move while looking."
	elseif role == "Technician" then
		local t = Classes.Technician
		text = ("%smotion sensor, %d per night: beeps when a thief walks by. Restarts cameras instantly."):format(key(t.KeyLabel), t.SensorsPerNight)
	elseif role == "DogHandler" then
		text = ("Your dog walks with you and barks at thieves within %d studs."):format(Classes.DogHandler.DogSenseRadius)
	elseif role == "Assault" then
		text = ("%d health instead of %d. Less weapon recoil."):format(Classes.Assault.AssaultHealth, Config.Health.Max)
	end
	return (string.gsub(text, "^%l", string.upper))
end

local function abilityLine(info: { [string]: any }, touchOnly: boolean): string
	local key = tostring(info.KeyLabel or "")
	if key == "" then
		return tostring(info.AbilityTitle) .. "  •  ALWAYS ON"
	elseif touchOnly then
		return tostring(info.AbilityTitle)
	end
	return ("%s  •  %s"):format(tostring(info.AbilityTitle), string.upper(key))
end

---------------------------------------------------------------- 3D-картинки

-- Собирает картинку класса: модель в контейнере с точкой привязки в начале координат (низ по центру).
-- У собаки ещё и скелет: на карточке она сидит, машет хвостом и гавкает (DogAnimator).
local function buildPicture(role: string): (Model, DogAnimator.Rig?)
	local container = Instance.new("Model")
	container.Name = "Picture"
	local rig: DogAnimator.Rig? = nil
	local function add(built: WeaponModels.Built, cframe: CFrame)
		built.model:PivotTo(cframe)
		built.model.Parent = container
	end
	if role == "Patrol" or role == "Operator" then
		add(ClassModels.icon(role), CFrame.identity)
	elseif role == "Technician" then
		add(ClassModels.sensor(), CFrame.identity)
	elseif role == "DogHandler" then
		local dog, pivots = ClassModels.dog()
		add(dog, CFrame.identity)
		local dogRig = DogAnimator.newRig(pivots)
		for _, part in dog.parts do
			DogAnimator.addPart(dogRig, part, part.CFrame) -- собака стоит в начале координат
		end
		rig = dogRig
	else
		-- Штурмовик: бронежилет охраны и автомат наискосок перед ним
		add(WeaponModels.fromSpecs("guard_vest_01", WeaponModels.vestSpecs(Vector3.new(2, 1.6, 1))), CFrame.new(0, 1.1, 0))
		add(WeaponModels.build("Rifle"), CFrame.new(-0.7, 0.65, -0.9) * CFrame.Angles(0, 0, 0.55) * CFrame.Angles(0, -math.pi / 2, 0))
	end
	-- Крутится вокруг своей середины (по полу), а не вокруг начала координат
	container.WorldPivot = CFrame.identity
	local boxCFrame = container:GetBoundingBox()
	container.WorldPivot = CFrame.new(boxCFrame.Position.X, 0, boxCFrame.Position.Z)
	return container, rig
end

-- Камера ViewportFrame смотрит на модель спереди-справа-сверху так, чтобы она поместилась целиком.
local function frameCamera(camera: Camera, model: Model)
	local boxCFrame, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	camera.FieldOfView = 34
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local direction = Vector3.new(0.55, 0.38, -1).Unit
	local center = boxCFrame.Position
	camera.CFrame = CFrame.lookAt(center + direction * distance, center)
end

---------------------------------------------------------------- карточки

type Card = {
	role: string,
	button: TextButton,
	stroke: UIStroke,
	ribbon: Frame,
	count: TextLabel,
	countFrame: Frame,
	model: Model,
	base: CFrame,
	rig: DogAnimator.Rig?,
	pose: DogAnimator.Pose,
	angle: number,
	selected: boolean,
	locked: boolean,
	lock: Frame,
	viewport: ViewportFrame,
	title: TextLabel,
}

function ClassCards.new(gui: ScreenGui, touchOnly: boolean, onChoose: (role: string) -> ()): Cards
	local order = Classes.Order
	local width = #order * CARD_W + (#order - 1) * GAP
	local panel = Theme.new("Frame", {
		Name = "ClassCards",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(width, CARD_H + HEADER + LIFT),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local scale = Theme.new("UIScale", { Parent = panel })
	local function rescale()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min((viewport.X - 24) / width, (viewport.Y * 0.42) / (CARD_H + HEADER + LIFT)), 0.45, 1)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local header = Theme.label({
		Size = UDim2.new(1, 0, 0, HEADER - 6),
		RichText = true,
		Text = if touchOnly
			then 'CHOOSE YOUR CLASS   <font color="#E8DCC4" size="16">tap a card</font>'
			else 'CHOOSE YOUR CLASS   <font color="#E8DCC4" size="16">keys 1–5</font>',
		TextColor3 = Colors.Gold,
		MaxTextSize = 26,
		Parent = panel,
	})
	Theme.new("UIStroke", { Color = Colors.Dark, Thickness = 2, Parent = header })

	local cards: { Card } = {}
	for index, role in order do
		local info = (Classes :: any)[role]
		local color: Color3 = info.Color
		local button = Theme.new("TextButton", {
			Name = role,
			Position = UDim2.fromOffset((index - 1) * (CARD_W + GAP), HEADER + LIFT),
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundColor3 = Colors.White,
			AutoButtonColor = false,
			Text = "",
			Parent = panel,
		}, {
			Theme.corner(14),
			Theme.new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color:Lerp(Colors.Navy, 0.55)),
					ColorSequenceKeypoint.new(0.55, Colors.Navy),
					ColorSequenceKeypoint.new(1, Colors.Dark),
				}),
			}),
		})
		local stroke = Theme.stroke(color, 2)
		stroke.Transparency = 0.35
		stroke.Parent = button

		-- Свет за картинкой
		Theme.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(98, 98),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.72,
			Parent = button,
		}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

		local viewport = Theme.new("ViewportFrame", {
			Name = "Picture",
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 0, 110),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 165),
			LightColor = Color3.fromRGB(255, 246, 230),
			LightDirection = Vector3.new(-0.6, -1, -0.8),
			ZIndex = 2,
			Parent = button,
		})
		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local model, rig = buildPicture(role)
		model.Parent = viewport
		frameCamera(camera, model)

		if not touchOnly then
			local badge = Theme.new("Frame", {
				Name = "Key",
				Position = UDim2.fromOffset(7, 7),
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Colors.Dark,
				BackgroundTransparency = 0.15,
				ZIndex = 3,
				Parent = button,
			}, { Theme.corner(7), Theme.stroke(Colors.Gold, 1.5) })
			Theme.label({ Size = UDim2.fromScale(1, 1), Text = tostring(index), TextColor3 = Colors.Gold, MaxTextSize = 18, ZIndex = 3, Parent = badge })
		end

		-- Сколько игроков уже выбрали этот класс
		local countFrame = Theme.new("Frame", {
			Name = "Picked",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -7, 0, 7),
			Size = UDim2.fromOffset(34, 22),
			BackgroundColor3 = Colors.Dark,
			BackgroundTransparency = 0.15,
			Visible = false,
			ZIndex = 3,
			Parent = button,
		}, { Theme.corner(11) })
		local count = Theme.label({ Size = UDim2.fromScale(1, 1), Font = Theme.BodyFont, MaxTextSize = 14, ZIndex = 3, Parent = countFrame })

		local title = Theme.label({
			Name = "Title",
			Position = UDim2.fromOffset(6, 112),
			Size = UDim2.new(1, -12, 0, 26),
			Text = string.upper(info.Title),
			MaxTextSize = 22,
			ZIndex = 2,
			Parent = button,
		})
		Theme.label({
			Name = "Ability",
			Position = UDim2.fromOffset(6, 138),
			Size = UDim2.new(1, -12, 0, 15),
			Font = Theme.BodyFont,
			Text = abilityLine(info, touchOnly),
			TextColor3 = color:Lerp(Colors.White, 0.25),
			MaxTextSize = 12,
			ZIndex = 2,
			Parent = button,
		})
		Theme.label({
			Name = "Info",
			Position = UDim2.fromOffset(7, 155),
			Size = UDim2.new(1, -14, 0, 40),
			Font = Theme.BodyFont,
			Text = infoText(role, touchOnly),
			TextColor3 = Colors.Marble,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 11,
			ZIndex = 2,
			Parent = button,
		})

		-- Лента «YOUR CLASS» над выбранной карточкой
		local ribbon = Theme.new("Frame", {
			Name = "Ribbon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(92, 20),
			BackgroundColor3 = Colors.Gold,
			Visible = false,
			ZIndex = 4,
			Parent = button,
		}, { Theme.corner(10) })
		Theme.label({ Size = UDim2.fromScale(1, 1), Text = "YOUR CLASS", TextColor3 = Colors.Navy, MaxTextSize = 13, ZIndex = 4, Parent = ribbon })

		-- Замок: класс ещё не куплен (цена в алмазах). Карточка темнее, картинка серая.
		local lock = Theme.new("Frame", {
			Name = "Lock",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colors.Dark,
			BackgroundTransparency = 0.42,
			Visible = false,
			ZIndex = 5,
			Parent = button,
		}, { Theme.corner(14) })
		Theme.label({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CARD_W / 2, 52),
			Size = UDim2.fromOffset(44, 44),
			Text = "🔒",
			MaxTextSize = 40,
			ZIndex = 6,
			Parent = lock,
		})
		local pricePill = Theme.new("Frame", {
			Name = "Price",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CARD_W / 2, 90),
			Size = UDim2.fromOffset(84, 24),
			BackgroundColor3 = Colors.Navy,
			ZIndex = 6,
			Parent = lock,
		}, { Theme.corner(12), Theme.stroke(Colors.Diamond, 1.5) })
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = ("💎 %d"):format(GameState.classPrice(role)),
			TextColor3 = Colors.Diamond,
			MaxTextSize = 16,
			ZIndex = 6,
			Parent = pricePill,
		})

		button.Activated:Connect(function()
			onChoose(role)
		end)

		table.insert(cards, {
			role = role,
			button = button,
			stroke = stroke,
			ribbon = ribbon,
			count = count,
			countFrame = countFrame,
			model = model,
			base = model.WorldPivot,
			rig = rig,
			pose = DogAnimator.newPose(),
			angle = (index - 1) * 0.8,
			selected = false,
			locked = false,
			lock = lock,
			viewport = viewport,
			title = title,
		})
	end

	local function refresh(myRole: string)
		local picked: { [string]: number } = {}
		for _, player in Players:GetPlayers() do
			local role = GameState.roleOf(player)
			picked[role] = (picked[role] or 0) + 1
		end
		for _, card in cards do
			local selected = card.role == myRole
			local locked = not GameState.ownsClass(Players.LocalPlayer, card.role)
			if locked ~= card.locked then
				card.locked = locked
				card.lock.Visible = locked
				card.viewport.ImageColor3 = if locked then Color3.fromRGB(120, 124, 135) else Color3.new(1, 1, 1)
				card.title.TextColor3 = if locked then Colors.Gray else Colors.White
			end
			local n = picked[card.role] or 0
			card.countFrame.Visible = n > 0
			card.count.Text = "×" .. n
			if selected ~= card.selected then
				card.selected = selected
				card.ribbon.Visible = selected
				card.stroke.Color = if selected then Colors.Gold else (Classes :: any)[card.role].Color
				card.stroke.Thickness = if selected then 3 else 2
				card.stroke.Transparency = if selected then 0 else 0.35
				local position = card.button.Position
				TweenService:Create(card.button, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(position.X.Offset, HEADER + (if selected then 0 else LIFT)),
				}):Play()
			end
		end
	end

	-- Картинки медленно крутятся (выбранная — быстрее), пока карточки видны
	RunService.RenderStepped:Connect(function(dt)
		if not panel.Visible then
			return
		end
		for _, card in cards do
			card.angle += dt * (if card.selected then 1.3 else 0.45)
			local rig = card.rig
			if rig then
				-- Собака: поворот вокруг середины и живая поза (детали ставит DogAnimator)
				DogAnimator.previewPose(card.pose, os.clock())
				DogAnimator.solve(rig, card.base * CFrame.Angles(0, card.angle, 0) * card.base:Inverse(), card.pose, false)
			else
				card.model:PivotTo(card.base * CFrame.Angles(0, card.angle, 0))
			end
		end
	end)

	return {
		frame = panel,
		setVisible = function(visible: boolean)
			panel.Visible = visible
		end,
		refresh = refresh,
	}
end

-- 3D-картинка класса и камера к ней — для кнопки умения (Abilities.client), витрины и окна магазина хаба.
ClassCards.picture = buildPicture
ClassCards.frameCamera = frameCamera
ClassCards.infoText = infoText
ClassCards.abilityLine = abilityLine

return ClassCards
