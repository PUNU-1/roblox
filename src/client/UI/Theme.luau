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
}

Theme.Font = Enum.Font.FredokaOne
Theme.BodyFont = Enum.Font.GothamBold

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

function Theme.screenGui(name: string, displayOrder: number?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return Theme.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = playerGui,
	})
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
	Theme.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 36, Parent = label })
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
	Theme.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 28, Parent = button })
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

return Theme
