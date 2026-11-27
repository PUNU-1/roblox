--!strict
-- Окно настроек и применение настроек на клиенте (этап 6, блок J1, общий модуль для хаба и музея):
--   • Music volume (0–100%, шаг 10%) → SoundService.Music.Volume
--   • Effects volume (0–100%, шаг 10%) → SoundService.Effects.Volume
--   • Camera sensitivity (0.3–2.0, шаг 0.1) → UserInputService.MouseDeltaSensitivity
--   • Graphics (HIGH / LOW) → тени у деталей < 2 стадов, ParticleEmitter, Atmosphere.Density, BloomEffect
--   • Tutorial (ON / OFF) → Remote SetTutorial (атрибут TutorialOff)
-- Всё сохраняется в профиле через Remote SaveSettings (клиент объединяет быстрые нажатия, сервер проверяет лимит 2 сек).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))
local PixelButton = require(script.Parent:WaitForChild("PixelButton"))
local PixelWindow = require(script.Parent:WaitForChild("PixelWindow"))

local SettingsCfg = Config.Settings
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors

local localPlayer = Players.LocalPlayer

local SettingsWindow = {}

type SettingsState = {
	music: number,
	effects: number,
	sensitivity: number,
	lowGraphics: boolean,
}

local function snap(value: any, minVal: number, maxVal: number, step: number, fallback: number): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	local clamped = math.clamp(value, minVal, maxVal)
	local snapped = math.round(clamped / step) * step
	return math.clamp(math.round(snapped * 100) / 100, minVal, maxVal)
end

local current: SettingsState = {
	music = SettingsCfg.DefaultMusic,
	effects = SettingsCfg.DefaultEffects,
	sensitivity = SettingsCfg.DefaultSensitivity,
	lowGraphics = SettingsCfg.DefaultLowGraphics,
}

local started = false
local saveDirty = false
local flushScheduled = false
local lastSentAt = 0
local lastLocalEditAt = 0
local connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection)
	table.insert(connections, conn)
end

---------------------------------------------------------------- графика Low / High

local lowActive = false
local savedShadows: { [BasePart]: boolean } = {}
local savedParticles: { [ParticleEmitter]: boolean } = {}
local savedBloom: { [BloomEffect]: boolean } = {}
local savedAtmosphere: { [Atmosphere]: number } = {}
local atmoConns: { [Atmosphere]: RBXScriptConnection } = {}
local wsDescConn: RBXScriptConnection? = nil
local wsRemConn: RBXScriptConnection? = nil
local ltDescConn: RBXScriptConnection? = nil
local ltRemConn: RBXScriptConnection? = nil

local function lowDensityFor(orig: number): number
	return math.min(orig, SettingsCfg.LowAtmosphereDensity)
end

local function isSmallPart(part: BasePart): boolean
	local s = part.Size
	return math.max(s.X, s.Y, s.Z) < SettingsCfg.ShadowSizeThreshold
end

local function applyWorkspaceItem(inst: Instance)
	if inst:IsA("BasePart") then
		if isSmallPart(inst) and savedShadows[inst] == nil then
			savedShadows[inst] = inst.CastShadow
			inst.CastShadow = false
		end
	elseif inst:IsA("ParticleEmitter") then
		if savedParticles[inst] == nil then
			savedParticles[inst] = inst.Enabled
			inst.Enabled = false
		end
	end
end

local function watchAtmosphere(atmo: Atmosphere)
	if savedAtmosphere[atmo] ~= nil then
		return
	end
	savedAtmosphere[atmo] = atmo.Density
	local target = lowDensityFor(atmo.Density)
	if math.abs(atmo.Density - target) > 0.001 then
		atmo.Density = target
	end
	atmoConns[atmo] = atmo:GetPropertyChangedSignal("Density"):Connect(function()
		if not lowActive then
			return
		end
		local orig = savedAtmosphere[atmo]
		if orig == nil then
			return
		end
		local expected = lowDensityFor(orig)
		if math.abs(atmo.Density - expected) > 0.001 then
			-- Сервер поменял плотность тумана (смена фазы день/ночь): запоминаем новое исходное значение
			savedAtmosphere[atmo] = atmo.Density
			atmo.Density = lowDensityFor(atmo.Density)
		end
	end)
end

local function applyLightingItem(inst: Instance)
	if inst:IsA("BloomEffect") then
		if savedBloom[inst] == nil then
			savedBloom[inst] = inst.Enabled
			inst.Enabled = false
		end
	elseif inst:IsA("Atmosphere") then
		watchAtmosphere(inst)
	end
end

local function disconnectGraphicsWatchers()
	if wsDescConn then
		wsDescConn:Disconnect()
		wsDescConn = nil
	end
	if wsRemConn then
		wsRemConn:Disconnect()
		wsRemConn = nil
	end
	if ltDescConn then
		ltDescConn:Disconnect()
		ltDescConn = nil
	end
	if ltRemConn then
		ltRemConn:Disconnect()
		ltRemConn = nil
	end
	for _, conn in atmoConns do
		conn:Disconnect()
	end
	table.clear(atmoConns)
end

local function setLowGraphics(enabled: boolean)
	if enabled == lowActive then
		return
	end
	lowActive = enabled
	if enabled then
		for _, desc in Workspace:GetDescendants() do
			applyWorkspaceItem(desc)
		end
		for _, desc in Lighting:GetDescendants() do
			applyLightingItem(desc)
		end
		wsDescConn = Workspace.DescendantAdded:Connect(applyWorkspaceItem)
		wsRemConn = Workspace.DescendantRemoving:Connect(function(inst)
			if (inst:IsA("BasePart") and savedShadows[inst] ~= nil) or (inst:IsA("ParticleEmitter") and savedParticles[inst] ~= nil) then
				task.defer(function()
					if not inst.Parent then
						if inst:IsA("BasePart") then
							savedShadows[inst] = nil
						elseif inst:IsA("ParticleEmitter") then
							savedParticles[inst] = nil
						end
					end
				end)
			end
		end)
		ltDescConn = Lighting.DescendantAdded:Connect(applyLightingItem)
		ltRemConn = Lighting.DescendantRemoving:Connect(function(inst: Instance)
			if inst:IsA("BloomEffect") then
				local bloom = inst
				task.defer(function()
					if not bloom.Parent then
						savedBloom[bloom] = nil
					end
				end)
			elseif inst:IsA("Atmosphere") then
				local atmo = inst
				task.defer(function()
					if not atmo.Parent then
						if atmoConns[atmo] then
							atmoConns[atmo]:Disconnect()
							atmoConns[atmo] = nil
						end
						savedAtmosphere[atmo] = nil
					end
				end)
			end
		end)
	else
		disconnectGraphicsWatchers()
		for part, origShadow in savedShadows do
			if part.Parent then
				part.CastShadow = origShadow
			end
		end
		table.clear(savedShadows)
		for emitter, origEnabled in savedParticles do
			if emitter.Parent then
				emitter.Enabled = origEnabled
			end
		end
		table.clear(savedParticles)
		for bloom, origEnabled in savedBloom do
			if bloom.Parent then
				bloom.Enabled = origEnabled
			end
		end
		table.clear(savedBloom)
		for atmo, origDensity in savedAtmosphere do
			if atmo.Parent then
				atmo.Density = origDensity
			end
		end
		table.clear(savedAtmosphere)
	end
end

---------------------------------------------------------------- применение всех настроек

local function applySoundVolumes()
	local musicGroup = SoundService:FindFirstChild("Music")
	if musicGroup and musicGroup:IsA("SoundGroup") then
		musicGroup.Volume = current.music
	end
	local effectsGroup = SoundService:FindFirstChild("Effects")
	if effectsGroup and effectsGroup:IsA("SoundGroup") then
		effectsGroup.Volume = current.effects
	end
end

local function applyAll()
	applySoundVolumes()
	UserInputService.MouseDeltaSensitivity = current.sensitivity
	setLowGraphics(current.lowGraphics)
end

local function readAttributesIntoState()
	local m = localPlayer:GetAttribute(PlayerAttr.SettingMusic)
	local e = localPlayer:GetAttribute(PlayerAttr.SettingEffects)
	local s = localPlayer:GetAttribute(PlayerAttr.SettingSensitivity)
	local g = localPlayer:GetAttribute(PlayerAttr.SettingLowGraphics)
	current.music = snap(m, SettingsCfg.MinMusic, SettingsCfg.MaxMusic, SettingsCfg.VolumeStep, SettingsCfg.DefaultMusic)
	current.effects = snap(e, SettingsCfg.MinEffects, SettingsCfg.MaxEffects, SettingsCfg.VolumeStep, SettingsCfg.DefaultEffects)
	current.sensitivity = snap(s, SettingsCfg.MinSensitivity, SettingsCfg.MaxSensitivity, SettingsCfg.SensitivityStep, SettingsCfg.DefaultSensitivity)
	current.lowGraphics = if typeof(g) == "boolean" then g else SettingsCfg.DefaultLowGraphics
end

---------------------------------------------------------------- сохранение на сервер (защита от спама)

local function scheduleFlush()
	if flushScheduled then
		return
	end
	flushScheduled = true
	task.spawn(function()
		while saveDirty do
			local now = os.clock()
			local waitDebounce = math.max(0, (lastLocalEditAt + 0.35) - now)
			local waitCooldown = math.max(0, (lastSentAt + SettingsCfg.SaveCooldown + 0.05) - now)
			local waitTime = math.max(waitDebounce, waitCooldown)
			if waitTime > 0 then
				task.wait(waitTime)
			else
				saveDirty = false
				lastSentAt = os.clock()
				Remotes.get(Remotes.Names.SaveSettings):FireServer(
					current.music,
					current.effects,
					current.sensitivity,
					current.lowGraphics
				)
			end
		end
		flushScheduled = false
	end)
end

local function commitChange()
	applyAll()
	saveDirty = true
	lastLocalEditAt = os.clock()
	scheduleFlush()
end

---------------------------------------------------------------- окно настроек (PixelWindow)

local refreshUI: () -> ()
local window: PixelWindow.Window

window = PixelWindow.new({
	name = "Settings",
	title = "SETTINGS",
	width = SettingsCfg.WindowWidth,
	height = SettingsCfg.WindowHeight,
	displayOrder = 6,
	onOpen = function()
		local closeBtn = window.panel:FindFirstChild("Close")
		if closeBtn and closeBtn:IsA("TextButton") then
			closeBtn.Modal = true
		end
		if refreshUI then
			refreshUI()
		end
	end,
	onClose = function()
		local closeBtn = window.panel:FindFirstChild("Close")
		if closeBtn and closeBtn:IsA("TextButton") then
			closeBtn.Modal = false
		end
	end,
})

local content = window.content
local ROW_W = SettingsCfg.WindowWidth - 2 * window.inset - 20
local ROW_H = 52
local ROW_GAP = 8

local function createRow(index: number, titleText: string): Frame
	local row = Theme.new("Frame", {
		Name = "Row" .. index,
		Position = UDim2.fromOffset(10, 8 + (index - 1) * (ROW_H + ROW_GAP)),
		Size = UDim2.fromOffset(ROW_W, ROW_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = content,
	})
	local _, inset = PixelIcon.box(row, 2, {
		layers = { PixelIcon.Outline, Colors.NavyLight },
		shadow = false,
		zIndex = 3,
	})
	Theme.pixelLabel({
		Name = "Label",
		Position = UDim2.fromOffset(inset + 12, 0),
		Size = UDim2.new(0, 230, 1, 0),
		Text = titleText,
		TextColor3 = Colors.Marble,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = row,
	}, 12, 1)
	return row
end

local function createStepperRow(
	index: number,
	titleText: string,
	onStep: (delta: number) -> ()
): (TextLabel, PixelButton.TextButtonObject, PixelButton.TextButtonObject)
	local row = createRow(index, titleText)
	local rightPad = 14
	local btnW, btnH = 44, 38
	local valW = 86

	local plusBtn = PixelButton.text({
		name = "Plus",
		text = "+",
		color = Colors.Navy,
		textSize = 16,
		cell = 2,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -rightPad, 0.5, 0),
		size = UDim2.fromOffset(btnW, btnH),
		zIndex = 5,
		parent = row,
		onActivated = function()
			onStep(1)
		end,
	})
	local valueLabel = Theme.pixelLabel({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(rightPad + btnW + 6), 0.5, 0),
		Size = UDim2.fromOffset(valW, btnH),
		Text = "",
		TextColor3 = Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Parent = row,
	}, 12, 2)
	local minusBtn = PixelButton.text({
		name = "Minus",
		text = "-",
		color = Colors.Navy,
		textSize = 16,
		cell = 2,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -(rightPad + btnW + 6 + valW + 6), 0.5, 0),
		size = UDim2.fromOffset(btnW, btnH),
		zIndex = 5,
		parent = row,
		onActivated = function()
			onStep(-1)
		end,
	})
	return valueLabel, minusBtn, plusBtn
end

local function createToggleRow(index: number, titleText: string, onToggle: () -> ()): PixelButton.TextButtonObject
	local row = createRow(index, titleText)
	return PixelButton.text({
		name = "Toggle",
		text = "",
		color = Colors.Green,
		textSize = 12,
		cell = 2,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -14, 0.5, 0),
		size = UDim2.fromOffset(186, 38),
		zIndex = 5,
		parent = row,
		onActivated = onToggle,
	})
end

local musicValue, musicMinus, musicPlus = createStepperRow(1, "MUSIC VOLUME", function(dir)
	local nextVal = snap(current.music + dir * SettingsCfg.VolumeStep, SettingsCfg.MinMusic, SettingsCfg.MaxMusic, SettingsCfg.VolumeStep, current.music)
	if nextVal ~= current.music then
		current.music = nextVal
		commitChange()
		refreshUI()
	end
end)

local effectsValue, effectsMinus, effectsPlus = createStepperRow(2, "EFFECTS VOLUME", function(dir)
	local nextVal = snap(current.effects + dir * SettingsCfg.VolumeStep, SettingsCfg.MinEffects, SettingsCfg.MaxEffects, SettingsCfg.VolumeStep, current.effects)
	if nextVal ~= current.effects then
		current.effects = nextVal
		commitChange()
		refreshUI()
	end
end)

local sensValue, sensMinus, sensPlus = createStepperRow(3, "SENSITIVITY", function(dir)
	local nextVal = snap(current.sensitivity + dir * SettingsCfg.SensitivityStep, SettingsCfg.MinSensitivity, SettingsCfg.MaxSensitivity, SettingsCfg.SensitivityStep, current.sensitivity)
	if nextVal ~= current.sensitivity then
		current.sensitivity = nextVal
		commitChange()
		refreshUI()
	end
end)

local graphicsBtn = createToggleRow(4, "GRAPHICS", function()
	current.lowGraphics = not current.lowGraphics
	commitChange()
	refreshUI()
end)

local tutorialBtn = createToggleRow(5, "TUTORIAL", function()
	local off = localPlayer:GetAttribute(PlayerAttr.TutorialOff) == true
	Remotes.get(Remotes.Names.SetTutorial):FireServer(off)
end)

Theme.pixelLabel({
	Name = "Footer",
	Position = UDim2.fromOffset(10, 8 + 5 * (ROW_H + ROW_GAP)),
	Size = UDim2.fromOffset(ROW_W, 24),
	Text = "SAVED TO YOUR PROFILE  |  LOW GRAPHICS BOOSTS FPS",
	TextColor3 = Colors.Gray,
	ZIndex = 4,
	Parent = content,
}, 8, 1)

refreshUI = function()
	musicValue.Text = ("%d%%"):format(math.round(current.music * 100))
	musicMinus.setEnabled(current.music > SettingsCfg.MinMusic + 0.001)
	musicPlus.setEnabled(current.music < SettingsCfg.MaxMusic - 0.001)

	effectsValue.Text = ("%d%%"):format(math.round(current.effects * 100))
	effectsMinus.setEnabled(current.effects > SettingsCfg.MinEffects + 0.001)
	effectsPlus.setEnabled(current.effects < SettingsCfg.MaxEffects - 0.001)

	sensValue.Text = ("%.1f"):format(current.sensitivity)
	sensMinus.setEnabled(current.sensitivity > SettingsCfg.MinSensitivity + 0.001)
	sensPlus.setEnabled(current.sensitivity < SettingsCfg.MaxSensitivity - 0.001)

	graphicsBtn.setText(if current.lowGraphics then "LOW" else "HIGH")
	graphicsBtn.setColor(if current.lowGraphics then Colors.Gold else Colors.Turquoise)

	local tutOff = localPlayer:GetAttribute(PlayerAttr.TutorialOff) == true
	tutorialBtn.setText(if tutOff then "OFF" else "ON")
	tutorialBtn.setColor(if tutOff then Colors.Gray else Colors.Green)
end

---------------------------------------------------------------- запуск и очистка

local function onAttributeReplicated()
	if saveDirty or flushScheduled then
		return
	end
	readAttributesIntoState()
	applyAll()
	if window.isOpen() then
		refreshUI()
	end
end

function SettingsWindow.start()
	if started then
		return
	end
	started = true
	readAttributesIntoState()
	applyAll()
	refreshUI()

	for _, attrName in {
		PlayerAttr.SettingMusic,
		PlayerAttr.SettingEffects,
		PlayerAttr.SettingSensitivity,
		PlayerAttr.SettingLowGraphics,
	} do
		track(localPlayer:GetAttributeChangedSignal(attrName):Connect(onAttributeReplicated))
	end
	track(localPlayer:GetAttributeChangedSignal(PlayerAttr.TutorialOff):Connect(function()
		if window.isOpen() then
			refreshUI()
		end
	end))
	track(SoundService.ChildAdded:Connect(function(child)
		if child:IsA("SoundGroup") and (child.Name == "Music" or child.Name == "Effects") then
			applySoundVolumes()
		end
	end))
	track(window.gui.Destroying:Connect(function()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		setLowGraphics(false)
	end))
end

SettingsWindow.open = window.open
SettingsWindow.close = window.close
SettingsWindow.toggle = window.toggle
SettingsWindow.isOpen = window.isOpen

return SettingsWindow
