-- Оформление интерфейса: цвета, шрифт и помощники для создания элементов.
-- Весь интерфейс собирается кодом, чтобы его не надо было рисовать в Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Theme = {}

Theme.Colors = {
	Navy = Color3.fromHex("1E2A44"),
	NavyLight = Color3.fromHex("2E4170"),
	Marble = Color3.fromHex("E8DCC4"),
	Gold = Color3.fromHex("D4A93A"),
	Red = Color3.fromHex("C8343A"),
	Turquoise = Color3.fromHex("3BC6C1"),
	Dark = Color3.fromHex("151821"),
	White = Color3.fromHex("FFFFFF"),
	Gray = Color3.fromHex("8A93A6"),
	Green = Color3.fromHex("3FB56B"),
	Diamond = Config.Diamonds.Color, -- алмазы 💎 (этап 4, блок 1)
}

Theme.Font = Enum.Font.FredokaOne
Theme.BodyFont = Enum.Font.GothamBold

-- Пиксельный шрифт (этап 5, блок A): Press Start 2P из шрифтов Roblox, если не вышло — Arcade.
-- Ставится в FontFace (а не Font). Лучше всего смотрится размером, кратным 8.
local okFont, pixelFont = pcall(Font.new, Config.PixelUI.Font)
Theme.PixelFont = if okFont then pixelFont else Font.fromEnum(Enum.Font.Arcade)

-- Реалистичный стиль в музее (Config.PixelUI.Real): хаб узнаём по его скрипту HubHUD рядом с папкой UI.
-- В музее пиксельный шрифт заменяется гладким жирным, обводка надписей — скруглённая.
local clientFolder = script.Parent.Parent
local inHub = clientFolder ~= nil and clientFolder:FindFirstChild("HubHUD") ~= nil
Theme.Realistic = Config.PixelUI.Real.Enabled and not inHub
if Theme.Realistic then
	local okReal, realFont = pcall(Font.new, Config.PixelUI.Real.Font, Enum.FontWeight.Heavy)
	Theme.PixelFont = if okReal then realFont else Font.fromEnum(Enum.Font.GothamBlack)
end
local STROKE_JOIN = if Theme.Realistic then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter

-- Надпись пиксельным шрифтом: белая с чёрной обводкой у самого текста (UIStroke на тексте, не на рамке).
-- size — размер в пикселях (TextScaled не используем: пиксели должны быть ровными).
function Theme.pixelLabel(props: { [string]: any }, size: number?, strokeThickness: number?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = Theme.PixelFont,
		TextColor3 = Theme.Colors.White,
		TextSize = size or 16,
		TextScaled = false,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	local label = Theme.new("TextLabel", defaults)
	Theme.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = strokeThickness or math.max(1, math.floor((size or 16) / 8)),
		LineJoinMode = STROKE_JOIN,
		Parent = label,
	})
	return label
end

-- Играет ли игрок пальцем (телефон, планшет без мыши) — тогда вместо клавиш кнопки на экране (этап 5, блок D).
-- Раньше везде было «TouchEnabled and not KeyboardEnabled», но многие Android-телефоны говорят KeyboardEnabled = true
-- (экранная клавиатура): тогда кнопки ContextActionService не появлялись, а кнопки F у предметов нельзя было нажать пальцем.
-- Теперь: PreferredInput (новое свойство Roblox: Touch / KeyboardAndMouse / Gamepad), если его нет — «есть касание, нет мыши».
function Theme.touchOnly(): boolean
	local UserInputService = game:GetService("UserInputService")
	local ok, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(preferred) == "EnumItem" then
		return preferred.Name == "Touch"
	end
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Переводит готовые надписи на пиксельный шрифт (этап 5, блок D: деньги, таймер, здоровье, патроны в музее).
-- Надпись остаётся TextScaled; если у неё ещё нет обводки — добавляется чёрная.
function Theme.pixelize(...: TextLabel)
	for _, label in { ... } do
		label.FontFace = Theme.PixelFont
		if not label:FindFirstChildOfClass("UIStroke") then
			Theme.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, LineJoinMode = STROKE_JOIN, Parent = label })
		end
	end
end

-- В пиксельном шрифте нет «•», длинного тире, многоточия и 💎 — заменяем на то, что в нём есть.
function Theme.pixelText(text: string): string
	return (text:gsub("•", "|"):gsub("—", "-"):gsub("…", "..."):gsub("’", "'"):gsub("💎 ?", ""))
end

-- Создаёт элемент: Theme.new("Frame", { Size = ..., Parent = ... }, { дочерние элементы })
function Theme.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Theme.corner(radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Theme.stroke(color: Color3?, thickness: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or Theme.Colors.Gold,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return Theme.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

-- fullScreen — на весь экран и на телефоне (затемнения, переходы, рамка камер). Иначе на телефоне ScreenGui — в безопасной
-- зоне (этап 8, блок Q): вырез экрана и полоска «домой» ничего не закрывают. На компьютере — как раньше.
function Theme.screenGui(name: string, displayOrder: number?, fullScreen: boolean?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Theme.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
	})
	if not fullScreen and Theme.touchOnly() then
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- после IgnoreGuiInset: он сам меняет ScreenInsets
	end
	gui.Parent = playerGui
	return gui
end

-- Надписи TextScaled на телефоне не мельче Config.Mobile.MinTextSize (этап 8, блок Q); на компьютере — как раньше.
local touchCache: boolean? = nil
local function minTextSize(maxSize: number): number
	if touchCache == nil then
		touchCache = Theme.touchOnly()
	end
	return if touchCache then math.min(Config.Mobile.MinTextSize, maxSize) else 1
end

function Theme.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.White,
		TextScaled = true,
		Text = "",
	}
	for key, value in props do
		if key ~= "MaxTextSize" then -- это не свойство TextLabel, оно идёт в UITextSizeConstraint
			defaults[key] = value
		end
	end
	local label = Theme.new("TextLabel", defaults)
	local maxSize = props.MaxTextSize or 36
	Theme.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = minTextSize(maxSize), Parent = label })
	return label
end

function Theme.button(props: { [string]: any }): TextButton
	local defaults = {
		BackgroundColor3 = Theme.Colors.NavyLight,
		AutoButtonColor = true,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.White,
		TextScaled = true,
		Text = "",
	}
	for key, value in props do
		if key ~= "MaxTextSize" then
			defaults[key] = value
		end
	end
	local button = Theme.new("TextButton", defaults)
	Theme.corner(10).Parent = button
	local maxSize = props.MaxTextSize or 28
	Theme.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = minTextSize(maxSize), Parent = button })
	Theme.padding(6).Parent = button
	return button
end

-- 75 -> "1:15"
function Theme.formatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(total // 60, total % 60)
end

-- Часы ночи: вся ночь (от 2 до 5 минут игры) = с 00:00 до 06:00. fraction — GameState.nightProgress().
function Theme.nightClock(fraction: number): string
	fraction = math.clamp(fraction, 0, 1)
	local hours = Config.Clock.StartHour + fraction * (Config.Clock.EndHour - Config.Clock.StartHour)
	local hour = math.floor(hours)
	local minute = math.floor((hours - hour) * 60)
	return ("%02d:%02d"):format(hour, minute)
end

-- Привязывает клиентский звук к SoundGroup "Effects" (чтобы ползунок Effects в настройках управлял и им).
function Theme.bindEffects(sound: Sound)
	local SoundService = game:GetService("SoundService")
	local existing = SoundService:FindFirstChild("Effects")
	if existing and existing:IsA("SoundGroup") then
		sound.SoundGroup = existing
		return
	end
	task.spawn(function()
		local group = SoundService:WaitForChild("Effects", 10)
		if group and group:IsA("SoundGroup") and sound.Parent then
			sound.SoundGroup = group
		end
	end)
end

return Theme
