--!strict
-- Режим зрителя (этап 6, блок I1): пока охранник лежит без сил (Downed = true)
-- или ждёт в комнате охраны (Day / Night, InRound ~= true), можно смотреть глазами других охранников.
-- Кнопки ◀ / ▶ (Z / X) переключают игроков на смене, BACK (C) возвращает свой вид (чтобы ползти
-- или выбрать класс); кнопка SPECTATE (или Z / X) возвращает в режим зрителя.
-- При подъёме, входе в раунд, окончании смены или отсутствии других охранников камера
-- автоматически возвращается в вид от первого лица.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelButton = require(UI:WaitForChild("PixelButton"))

local Settings = Config.Spectate
local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()

local CYCLE_ACTION = "SpectateCycle"
local BACK_ACTION = "SpectateBack"

---------------------------------------------------------------- интерфейс

local gui: ScreenGui = Theme.screenGui("Spectate", 3)

local watchLabel: TextLabel = Theme.pixelLabel({
	Name = "Watching",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.new(0.8, 0, 0, 28),
	TextColor3 = Colors.Gold,
	Text = "",
	Visible = false,
	Parent = gui,
}, 16, 2)

local cell = Config.PixelUI.HudCell
local controlsBar: Frame = Theme.new("Frame", {
	Name = "Controls",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(300, 16 * cell + cell * 4 + 28),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
Theme.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = controlsBar,
})

local cycle: (step: number) -> ()
local goBack: () -> ()
local reenter: () -> ()

local prevButton = PixelButton.new({
	icon = "ArrowLeft",
	label = "PREV",
	key = "Z",
	cell = cell,
	width = 88,
	name = "Prev",
	layoutOrder = 1,
	parent = controlsBar,
	onActivated = function()
		cycle(-1)
	end,
})
local backButton = PixelButton.new({
	icon = "Close",
	label = "BACK",
	key = "C",
	cell = cell,
	width = 88,
	name = "Back",
	layoutOrder = 2,
	parent = controlsBar,
	onActivated = function()
		goBack()
	end,
})
local nextButton = PixelButton.new({
	icon = "ArrowRight",
	label = "NEXT",
	key = "X",
	cell = cell,
	width = 88,
	name = "Next",
	layoutOrder = 3,
	parent = controlsBar,
	onActivated = function()
		cycle(1)
	end,
})

-- Кнопка возврата в режим зрителя, если игрок нажал BACK (удобно на телефоне и ПК)
local reenterButton = PixelButton.new({
	icon = "Eye",
	label = "SPECTATE",
	key = "Z",
	cell = cell,
	width = 112,
	name = "Reenter",
	parent = gui,
	onActivated = function()
		reenter()
	end,
})
reenterButton.root.AnchorPoint = Vector2.new(1, 1)
reenterButton.root.Position = if touchOnly then UDim2.new(1, -200, 1, -106) else UDim2.new(1, -24, 1, -20)
reenterButton.root.Visible = false

-- Указатели на кнопки (чтобы luau-lsp не ругался на неиспользуемые переменные)
local _ = prevButton
local __ = backButton
local ___ = nextButton

---------------------------------------------------------------- состояние и цели

local spectating = false
local manualBack = false
local wasEligible = false
local currentTarget: Player? = nil

local savedCameraMode: Enum.CameraMode? = nil
local savedMinZoom: number? = nil
local savedMaxZoom: number? = nil

local cycleBound = false
local backBound = false

local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

local function isRoundPhase(): boolean
	local phase = GameState.phase()
	return phase == Phase.Day or phase == Phase.Night
end

local function isEligible(): boolean
	if not isRoundPhase() then
		return false
	end
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true then
		return false
	end
	local downed = localPlayer:GetAttribute(PlayerAttr.Downed) == true
	local inRound = localPlayer:GetAttribute(PlayerAttr.InRound) == true
	return downed or not inRound
end

local function targetHumanoid(player: Player?): Humanoid?
	if not player or not player.Parent then
		return nil
	end
	if player:GetAttribute(PlayerAttr.InRound) ~= true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function getTargets(): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and targetHumanoid(player) ~= nil then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	return list
end

---------------------------------------------------------------- камера и привязки

local function setBackBound(on: boolean)
	if on == backBound then
		return
	end
	backBound = on
	if on then
		-- Приоритет выше приседа (C) в Weapons.client, чтобы BACK всегда срабатывал в режиме зрителя
		ContextActionService:BindActionAtPriority(
			BACK_ACTION,
			function(_name: string, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					goBack()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 50,
			Settings.BackKey
		)
	else
		ContextActionService:UnbindAction(BACK_ACTION)
	end
end

local function setCycleBound(on: boolean)
	if on == cycleBound then
		return
	end
	cycleBound = on
	if on then
		ContextActionService:BindAction(
			CYCLE_ACTION,
			function(_name: string, state: Enum.UserInputState, input: InputObject)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				if input.KeyCode == Settings.PrevKey then
					cycle(-1)
					return Enum.ContextActionResult.Sink
				elseif input.KeyCode == Settings.NextKey then
					cycle(1)
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end,
			false,
			Settings.PrevKey,
			Settings.NextKey
		)
	else
		ContextActionService:UnbindAction(CYCLE_ACTION)
	end
end

local function applyCamera(target: Player)
	local humanoid = targetHumanoid(target)
	if not humanoid then
		return
	end
	if not savedCameraMode then
		savedCameraMode = localPlayer.CameraMode
		savedMinZoom = localPlayer.CameraMinZoomDistance
		savedMaxZoom = localPlayer.CameraMaxZoomDistance
	end
	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMinZoomDistance = Settings.MinZoom
	localPlayer.CameraMaxZoomDistance = Settings.MaxZoom

	local camera = Workspace.CurrentCamera
	if camera then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function stopSpectate()
	local wasSpectating = spectating
	spectating = false
	currentTarget = nil

	if localPlayer:GetAttribute(PlayerAttr.Spectating) == true then
		localPlayer:SetAttribute(PlayerAttr.Spectating, false)
	end

	watchLabel.Visible = false
	controlsBar.Visible = false
	setBackBound(false)

	if not wasSpectating and not savedCameraMode then
		return
	end

	localPlayer.CameraMinZoomDistance = savedMinZoom or 0.5
	localPlayer.CameraMaxZoomDistance = savedMaxZoom or 400
	localPlayer.CameraMode = savedCameraMode or Enum.CameraMode.LockFirstPerson
	savedCameraMode = nil
	savedMinZoom = nil
	savedMaxZoom = nil

	-- Если игрок перешёл в телефон/пульт камер, CameraController сам управляет камерой
	if localPlayer:GetAttribute(PlayerAttr.ViewingCameras) ~= true then
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
end

local function updateWatchLabelPosition()
	local raid = GameState.get(Attr.Raid) == true
	local inRound = localPlayer:GetAttribute(PlayerAttr.InRound) == true
	-- Во время налёта сверху висит плашка POLICE: 60 (Y = 64..126), опускаемся ниже
	local y = if raid and inRound then 132 else 64
	watchLabel.Position = UDim2.new(0.5, 0, 0, y)
end

local function refresh()
	local eligible = isEligible()
	if not eligible then
		wasEligible = false
		manualBack = false
		stopSpectate()
		reenterButton.root.Visible = false
		setCycleBound(false)
		return
	end

	if not wasEligible then
		wasEligible = true
		manualBack = false
	end

	local targets = getTargets()
	local hasTargets = #targets > 0
	setCycleBound(hasTargets)

	if not hasTargets then
		stopSpectate()
		reenterButton.root.Visible = false
		return
	end

	if manualBack then
		stopSpectate()
		reenterButton.root.Visible = true
		return
	end

	local chosen: Player? = nil
	if currentTarget and table.find(targets, currentTarget) then
		chosen = currentTarget
	else
		chosen = targets[1]
	end

	if not chosen then
		stopSpectate()
		reenterButton.root.Visible = false
		return
	end

	spectating = true
	currentTarget = chosen
	if localPlayer:GetAttribute(PlayerAttr.Spectating) ~= true then
		localPlayer:SetAttribute(PlayerAttr.Spectating, true)
	end

	applyCamera(chosen)
	updateWatchLabelPosition()
	watchLabel.Text = Theme.pixelText(("WATCHING: %s"):format(chosen.DisplayName))
	watchLabel.Visible = true
	controlsBar.Visible = true
	reenterButton.root.Visible = false
	setBackBound(true)
end

cycle = function(step: number)
	if not isEligible() then
		return
	end
	local targets = getTargets()
	if #targets == 0 then
		return
	end
	local returning = manualBack or not spectating
	manualBack = false
	if returning then
		if not currentTarget or not table.find(targets, currentTarget) then
			currentTarget = if step < 0 then targets[#targets] else targets[1]
		end
		refresh()
		return
	end
	if #targets == 1 then
		currentTarget = targets[1]
		refresh()
		return
	end
	local index = table.find(targets, currentTarget :: Player) or 1
	local nextIndex = ((index - 1 + step) % #targets) + 1
	currentTarget = targets[nextIndex]
	refresh()
end

goBack = function()
	if not spectating then
		return
	end
	manualBack = true
	stopSpectate()
	refresh()
end

reenter = function()
	if not isEligible() then
		return
	end
	manualBack = false
	refresh()
end

---------------------------------------------------------------- подписки и очистка

local function unwatchPlayer(player: Player)
	local list = playerConnections[player]
	if list then
		for _, conn in list do
			conn:Disconnect()
		end
		playerConnections[player] = nil
	end
end

local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end
	unwatchPlayer(player)
	local list: { RBXScriptConnection } = {}
	table.insert(list, player:GetAttributeChangedSignal(PlayerAttr.InRound):Connect(refresh))
	table.insert(list, player.CharacterAdded:Connect(function()
		task.defer(refresh)
	end))
	table.insert(list, player.CharacterRemoving:Connect(function()
		task.defer(refresh)
	end))
	playerConnections[player] = list
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
track(Players.PlayerAdded:Connect(function(player: Player)
	watchPlayer(player)
	refresh()
end))
track(Players.PlayerRemoving:Connect(function(player: Player)
	unwatchPlayer(player)
	if currentTarget == player then
		currentTarget = nil
	end
	task.defer(refresh)
end))

for _, attrName in { PlayerAttr.Downed, PlayerAttr.InRound, PlayerAttr.ViewingCameras } do
	track(localPlayer:GetAttributeChangedSignal(attrName):Connect(refresh))
end
for _, attrName in { Attr.Phase, Attr.Raid } do
	track(GameState.folder():GetAttributeChangedSignal(attrName):Connect(refresh))
end

track(localPlayer.CharacterAdded:Connect(function()
	task.defer(function()
		if spectating and currentTarget then
			applyCamera(currentTarget)
		end
	end)
end))

-- Периодическая проверка (если цель потеряла Humanoid или Roblox сбросил CameraSubject)
local accumulator = 0
track(RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < 0.2 then
		return
	end
	accumulator = 0
	if spectating then
		local humanoid = targetHumanoid(currentTarget)
		local camera = Workspace.CurrentCamera
		if not humanoid or not isEligible() then
			refresh()
		elseif camera and (camera.CameraSubject ~= humanoid or localPlayer.CameraMode ~= Enum.CameraMode.Classic) then
			applyCamera(currentTarget :: Player)
		end
	elseif wasEligible or isEligible() then
		refresh()
	end
end))

track(script.Destroying:Connect(function()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	for player in playerConnections do
		unwatchPlayer(player)
	end
	setCycleBound(false)
	setBackBound(false)
	stopSpectate()
	if gui.Parent then
		gui:Destroy()
	end
end))

refresh()
