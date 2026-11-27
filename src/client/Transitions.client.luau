--!strict
-- Красивые экранные переходы в музее (этап 6, блок J2, всё только на клиенте):
--   • День → ночь: затемнение при переносе к Моне Лизе (0.3 сек → 0.4 сек), синий ColorCorrectionEffect (2 сек,
--     потом плавно уходит), трясущийся заголовок «NIGHT N» и тревожный звук (SoundGroup Effects).
--   • Ночь → утро (ночь пережита): тёплая вспышка (ColorCorrectionEffect + золотое свечение) и «YOU SURVIVED NIGHT N».
--   • Перед телепортом в хаб (кнопка Lobby / таймаут GAME OVER / OnTeleport): плавное затемнение (0.3 сек) и возврат (0.4 сек) при сбое или в Studio.
--   • Кража Моны Лизы (PaintingStolen -> true): пульсирующая красная рамка по краям 1.5 сек и «THE MONA LISA IS STOLEN!».
-- Вид от первого лица не трогаем (CameraMode / CameraType / CameraSubject не меняются).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Phase = GameState.Phase
local Attr = GameState.Attr
local PlayerAttr = GameState.PlayerAttr
local Colors = Theme.Colors
local Cfg = Config.Transitions

local localPlayer = Players.LocalPlayer
local touchOnly = Theme.touchOnly()
local destroyed = false

---------------------------------------------------------------- экран, звук и цветокоррекция

local gui: ScreenGui = Theme.screenGui("Transitions", 15)
gui.IgnoreGuiInset = true

local colorEffect = Instance.new("ColorCorrectionEffect")
colorEffect.Name = "TransitionColor"
colorEffect.Brightness = 0
colorEffect.Contrast = 0
colorEffect.Saturation = 0
colorEffect.TintColor = Color3.new(1, 1, 1)
colorEffect.Enabled = false
colorEffect.Parent = Lighting

local nightSound: Sound? = nil
if Config.Sounds.NightStart ~= "" then
	local sound = Instance.new("Sound")
	sound.Name = "NightStartTransition"
	sound.SoundId = Config.Sounds.NightStart
	sound.Volume = Config.Sounds.NightStartVolume
	sound.PlaybackSpeed = Config.Sounds.NightStartSpeed
	sound.Parent = SoundService
	Theme.bindEffects(sound)
	nightSound = sound
end

-- Чёрная завеса затемнения (Active = false: никогда не перехватывает нажатия кнопок)
local fadeFrame: Frame = Theme.new("Frame", {
	Name = "BlackFade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	Selectable = false,
	ZIndex = 30,
	Parent = gui,
})

-- Тёплая вспышка рассвета (поверх сцены, Active = false)
local flashFrame: Frame = Theme.new("Frame", {
	Name = "WarmFlash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Cfg.MorningTintColor,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	Selectable = false,
	ZIndex = 12,
	Parent = gui,
})

-- Красная пульсирующая рамка по краям экрана при краже Моны Лизы
local function makeEdge(name: string, anchor: Vector2, pos: UDim2, size: UDim2, rotation: number): Frame
	local frame: Frame = Theme.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = pos,
		Size = size,
		BackgroundColor3 = Colors.Red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		ZIndex = 10,
		Parent = gui,
	})
	Theme.new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = frame,
	})
	return frame
end

local stolenEdges: { Frame } = {
	makeEdge("StolenTop", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, Cfg.StolenBorderWidth), 90),
	makeEdge("StolenBottom", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, Cfg.StolenBorderWidth), -90),
	makeEdge("StolenLeft", Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(Cfg.StolenBorderWidth * 0.75, 1), 0),
	makeEdge("StolenRight", Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(Cfg.StolenBorderWidth * 0.75, 1), 180),
}

-- Контейнеры заголовков
local function makeBanner(name: string, pos: UDim2, size: UDim2, textSize: number, color: Color3): (Frame, TextLabel, UIStroke?, UIScale)
	local holder: Frame = Theme.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = size,
		BackgroundTransparency = 1,
		Active = false,
		Selectable = false,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local scale: UIScale = Theme.new("UIScale", { Scale = 1, Parent = holder })
	local label = Theme.pixelLabel({
		Name = "Title",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = color,
		TextWrapped = true,
		Active = false,
		Selectable = false,
		ZIndex = 21,
		Parent = holder,
	}, textSize, math.max(2, textSize // 8))
	local stroke = label:FindFirstChildOfClass("UIStroke")
	return holder, label, stroke, scale
end

local centerTitleHolder, centerTitleLabel, centerTitleStroke, centerTitleScale = makeBanner(
	"CenterTransitionTitle",
	UDim2.fromScale(0.5, 0.34),
	UDim2.new(0.92, 0, 0, 120),
	if touchOnly then 28 else 44,
	Colors.Red
)

local morningHolder, morningLabel, morningStroke, morningScale = makeBanner(
	"MorningTransitionTitle",
	UDim2.new(0.5, 0, 0, 38), -- верх экрана, где в Phase.Results скрыт TopBar
	UDim2.new(0.66, 0, 0, 56),
	if touchOnly then 16 else 24,
	Colors.Gold
)

---------------------------------------------------------------- помощники анимаций и очистки

local connections: { RBXScriptConnection } = {}
local activeTweens: { [string]: Tween } = {}
local shakeConn: RBXScriptConnection? = nil
local borderConn: RBXScriptConnection? = nil

local function track(conn: RBXScriptConnection)
	table.insert(connections, conn)
end

local function cancelTween(slot: string)
	local current = activeTweens[slot]
	if current then
		current:Cancel()
		activeTweens[slot] = nil
	end
end

local function playTween(slot: string, target: Instance, info: TweenInfo, props: { [string]: any }): Tween
	cancelTween(slot)
	local tween = TweenService:Create(target, info, props)
	activeTweens[slot] = tween
	tween:Play()
	return tween
end

local function stopShake()
	if shakeConn then
		shakeConn:Disconnect()
		shakeConn = nil
	end
end

local function stopBorderPulse()
	if borderConn then
		borderConn:Disconnect()
		borderConn = nil
	end
	for _, frame in stolenEdges do
		frame.BackgroundTransparency = 1
	end
end

local function resetColorEffect()
	cancelTween("color")
	colorEffect.Enabled = false
	colorEffect.Brightness = 0
	colorEffect.Contrast = 0
	colorEffect.Saturation = 0
	colorEffect.TintColor = Color3.new(1, 1, 1)
end

---------------------------------------------------------------- затемнение

local fadeToken = 0
local teleportFaded = false

local function fadeInBlack()
	fadeToken += 1
	playTween("fade", fadeFrame, TweenInfo.new(Cfg.FadeInSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	})
end

local function fadeOutBlack()
	fadeToken += 1
	playTween("fade", fadeFrame, TweenInfo.new(Cfg.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
end

local function playBlackBlink()
	fadeToken += 1
	local token = fadeToken
	playTween("fade", fadeFrame, TweenInfo.new(Cfg.FadeInSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	})
	task.delay(Cfg.FadeInSeconds + Cfg.FadeHoldSeconds, function()
		if destroyed or fadeToken ~= token then
			return
		end
		playTween("fade", fadeFrame, TweenInfo.new(Cfg.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
	end)
end

local function startTeleportFade()
	if teleportFaded or destroyed then
		return
	end
	teleportFaded = true
	local tokenBefore = fadeToken + 1
	fadeInBlack()
	-- Если телепорт не удался или мы в Studio — не оставляем чёрный экран навсегда
	task.delay(Cfg.TeleportTimeoutSeconds, function()
		if not destroyed and teleportFaded and fadeToken == tokenBefore then
			teleportFaded = false
			fadeOutBlack()
		end
	end)
end

local function cancelTeleportFade()
	if not teleportFaded then
		return
	end
	teleportFaded = false
	fadeOutBlack()
end

---------------------------------------------------------------- трясущийся центральный заголовок

local centerTitleToken = 0

local function showShakingTitle(text: string, color: Color3, textSize: number, duration: number, shakeAmp: number, shakeDecay: number)
	centerTitleToken += 1
	local token = centerTitleToken
	stopShake()
	cancelTween("centerScale")
	cancelTween("centerText")
	cancelTween("centerStroke")

	centerTitleLabel.Text = Theme.pixelText(text)
	centerTitleLabel.TextColor3 = color
	centerTitleLabel.TextSize = textSize
	centerTitleLabel.TextTransparency = 0
	if centerTitleStroke then
		centerTitleStroke.Thickness = math.max(2, textSize // 8)
		centerTitleStroke.Transparency = 0
	end

	local basePos = UDim2.fromScale(0.5, 0.34)
	centerTitleHolder.Position = basePos
	centerTitleScale.Scale = 1.28
	centerTitleHolder.Visible = true

	playTween("centerScale", centerTitleScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})

	local startedAt = os.clock()
	shakeConn = RunService.RenderStepped:Connect(function()
		if destroyed or centerTitleToken ~= token then
			stopShake()
			return
		end
		local elapsed = os.clock() - startedAt
		if elapsed >= shakeDecay then
			centerTitleHolder.Position = basePos
			stopShake()
			return
		end
		local strength = shakeAmp * (1 - elapsed / shakeDecay)
		local ox = (math.random() * 2 - 1) * strength
		local oy = (math.random() * 2 - 1) * strength
		centerTitleHolder.Position = UDim2.new(0.5, math.round(ox), 0.34, math.round(oy))
	end)

	local fadeDuration = 0.4
	task.delay(math.max(0.1, duration - fadeDuration), function()
		if destroyed or centerTitleToken ~= token then
			return
		end
		stopShake()
		centerTitleHolder.Position = basePos
		playTween("centerText", centerTitleLabel, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		})
		if centerTitleStroke then
			playTween("centerStroke", centerTitleStroke, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
		end
		task.delay(fadeDuration, function()
			if not destroyed and centerTitleToken == token then
				centerTitleHolder.Visible = false
			end
		end)
	end)
end

---------------------------------------------------------------- день -> ночь

local colorToken = 0

local function playDayToNight(night: number)
	-- 1) Затемнение при переносе охранников к Моне Лизе
	local onShift = localPlayer:GetAttribute(PlayerAttr.InRound) == true
	if onShift then
		playBlackBlink()
	end

	-- 2) Синий оттенок через ColorCorrectionEffect: 2 сек до глубокого синего, потом плавно уходит
	colorToken += 1
	local token = colorToken
	resetColorEffect()
	colorEffect.Enabled = true
	playTween("color", colorEffect, TweenInfo.new(Cfg.NightTintInSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		TintColor = Cfg.NightTintColor,
		Brightness = Cfg.NightBrightness,
		Saturation = Cfg.NightSaturation,
		Contrast = Cfg.NightContrast,
	})
	task.delay(Cfg.NightTintInSeconds, function()
		if destroyed or colorToken ~= token then
			return
		end
		playTween("color", colorEffect, TweenInfo.new(Cfg.NightTintOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Saturation = 0,
			Contrast = 0,
		})
		task.delay(Cfg.NightTintOutSeconds, function()
			if not destroyed and colorToken == token then
				colorEffect.Enabled = false
			end
		end)
	end)

	-- 3) Звук и крупная трясущаяся надпись NIGHT N (после короткого затемнения, чтобы её было сразу видно)
	if nightSound then
		nightSound:Play()
	end
	local delayTitle = if onShift then Cfg.FadeInSeconds * 0.8 else 0
	task.delay(delayTitle, function()
		if destroyed or GameState.phase() ~= Phase.Night then
			return
		end
		showShakingTitle(
			("NIGHT %d"):format(math.max(1, night)),
			Colors.Red,
			if touchOnly then 30 else 48,
			Cfg.NightTitleSeconds,
			Cfg.NightShakeAmplitude,
			Cfg.NightShakeDecay
		)
	end)
end

---------------------------------------------------------------- ночь -> утро (ночь пережита)

local morningToken = 0

local function hideMorningTitle()
	morningToken += 1
	cancelTween("morningScale")
	cancelTween("morningText")
	cancelTween("morningStroke")
	morningHolder.Visible = false
end

local function playNightSurvived(night: number)
	-- Тёплая вспышка рассвета (ColorCorrectionEffect + лёгкая золотая вспышка)
	colorToken += 1
	local token = colorToken
	resetColorEffect()
	colorEffect.Enabled = true
	playTween("color", colorEffect, TweenInfo.new(Cfg.MorningFlashInSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = Cfg.MorningTintColor,
		Brightness = Cfg.MorningBrightness,
		Saturation = Cfg.MorningSaturation,
		Contrast = Cfg.MorningContrast,
	})
	task.delay(Cfg.MorningFlashInSeconds, function()
		if destroyed or colorToken ~= token then
			return
		end
		playTween("color", colorEffect, TweenInfo.new(Cfg.MorningFlashOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Saturation = 0,
			Contrast = 0,
		})
		task.delay(Cfg.MorningFlashOutSeconds, function()
			if not destroyed and colorToken == token then
				colorEffect.Enabled = false
			end
		end)
	end)

	cancelTween("flash")
	flashFrame.BackgroundTransparency = Cfg.MorningOverlayTransparency
	playTween("flash", flashFrame, TweenInfo.new(Cfg.MorningFlashOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})

	-- Крупная надпись «YOU SURVIVED NIGHT N» сверху экрана (над окном итога)
	morningToken += 1
	local mToken = morningToken
	cancelTween("morningScale")
	cancelTween("morningText")
	cancelTween("morningStroke")

	morningLabel.Text = Theme.pixelText(("YOU SURVIVED NIGHT %d"):format(math.max(1, night)))
	morningLabel.TextColor3 = Colors.Gold
	morningLabel.TextTransparency = 0
	if morningStroke then
		morningStroke.Transparency = 0
	end
	morningScale.Scale = 0.65
	morningHolder.Visible = true

	playTween("morningScale", morningScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})

	local fadeDuration = 0.45
	task.delay(math.max(0.2, Cfg.MorningTitleSeconds - fadeDuration), function()
		if destroyed or morningToken ~= mToken then
			return
		end
		playTween("morningText", morningLabel, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		})
		if morningStroke then
			playTween("morningStroke", morningStroke, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
		end
		task.delay(fadeDuration, function()
			if not destroyed and morningToken == mToken then
				morningHolder.Visible = false
			end
		end)
	end)
end

---------------------------------------------------------------- кража Моны Лизы

local stolenToken = 0

local function playPaintingStolen()
	stolenToken += 1
	local token = stolenToken
	stopBorderPulse()

	local startedAt = os.clock()
	borderConn = RunService.RenderStepped:Connect(function()
		if destroyed or stolenToken ~= token then
			stopBorderPulse()
			return
		end
		local elapsed = os.clock() - startedAt
		if elapsed >= Cfg.StolenPulseSeconds then
			stopBorderPulse()
			return
		end
		local pulse = 0.5 - 0.5 * math.cos(elapsed * Cfg.StolenPulseSpeed)
		local fadeOut = if elapsed > Cfg.StolenPulseSeconds * 0.72
			then (elapsed - Cfg.StolenPulseSeconds * 0.72) / (Cfg.StolenPulseSeconds * 0.28)
			else 0
		local baseAlpha = Cfg.StolenMaxTransparency - pulse * (Cfg.StolenMaxTransparency - Cfg.StolenMinTransparency)
		local alpha = math.clamp(baseAlpha + fadeOut * (1 - baseAlpha), 0, 1)
		for _, frame in stolenEdges do
			frame.BackgroundTransparency = alpha
		end
	end)

	showShakingTitle(
		"THE MONA LISA IS STOLEN!",
		Colors.Red,
		if touchOnly then 22 else 34,
		Cfg.StolenTitleSeconds,
		Cfg.StolenShakeAmplitude,
		Cfg.StolenShakeDecay
	)
end

---------------------------------------------------------------- подписки на события игры

local lastPhase = GameState.phase()
local lastStolen = GameState.get(Attr.PaintingStolen) == true

track(GameState.folder():GetAttributeChangedSignal(Attr.Phase):Connect(function()
	local phase = GameState.phase()
	if phase == lastPhase then
		return
	end
	local prev = lastPhase
	lastPhase = phase

	if phase == Phase.Night and prev == Phase.Day then
		local night = tonumber(GameState.get(Attr.NightNumber)) or 1
		playDayToNight(night)
	elseif phase ~= Phase.Results then
		hideMorningTitle()
		if prev == Phase.Results and teleportFaded then
			cancelTeleportFade()
		end
	end
end))

track(GameState.folder():GetAttributeChangedSignal(Attr.PaintingStolen):Connect(function()
	local stolen = GameState.get(Attr.PaintingStolen) == true
	if stolen and not lastStolen then
		playPaintingStolen()
	end
	lastStolen = stolen
end))

track(Remotes.get(Remotes.Names.NightResults).OnClientEvent:Connect(function(results)
	if typeof(results) ~= "table" then
		return
	end
	if results.survived == true and results.gameOver ~= true then
		local night = tonumber(results.night) or tonumber(GameState.get(Attr.NightNumber)) or 1
		playNightSurvived(night)
	end
end))

track(localPlayer:GetAttributeChangedSignal(PlayerAttr.EndChoice):Connect(function()
	local choice = localPlayer:GetAttribute(PlayerAttr.EndChoice)
	if choice == "Lobby" then
		startTeleportFade()
	elseif choice == "PlayAgain" and teleportFaded then
		cancelTeleportFade()
	end
end))

track(localPlayer.OnTeleport:Connect(function(state)
	if state == Enum.TeleportState.Failed then
		cancelTeleportFade()
	elseif state == Enum.TeleportState.RequestedFromServer
		or state == Enum.TeleportState.Started
		or state == Enum.TeleportState.WaitingForServer
		or state == Enum.TeleportState.InProgress
	then
		startTeleportFade()
	end
end))

track(TeleportService.TeleportInitFailed:Connect(function(player)
	if player == localPlayer then
		cancelTeleportFade()
	end
end))

track(Remotes.get(Remotes.Names.Banner).OnClientEvent:Connect(function(text)
	if typeof(text) == "string" and string.find(text, "Teleport", 1, true) ~= nil and teleportFaded then
		cancelTeleportFade()
	end
end))

---------------------------------------------------------------- очистка

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	stopShake()
	stopBorderPulse()
	for slot in activeTweens do
		cancelTween(slot)
	end
	if colorEffect.Parent then
		colorEffect:Destroy()
	end
	if nightSound and nightSound.Parent then
		nightSound:Destroy()
	end
	if gui.Parent then
		gui:Destroy()
	end
end

gui.Destroying:Connect(cleanup)
script.Destroying:Connect(cleanup)
