-- Надписи прогресса (этап 6, блок H1, решение 85). Общий модуль: хаб (HubHUD) и музей (Progress.client).
-- Слушает Remote ProgressEvent (решает и считает всё сервер, ProgressService):
--  • LevelUp — крупно по центру «LEVEL UP!», «LV 12», новое звание и «+60» с алмазом, пиксельное конфетти, звук;
--  • Quest — полоска «QUEST DONE! +20» с алмазом и текстом задания;
--  • Badge — полоска «ACHIEVEMENT!» с медалью;
--  • Newbie — полоска «WELCOME, GUARD! +40» и «1 FREE RUN WITH ANY CLASS»;
--  • TrialOver — полоска «LIKED TECHNICIAN?» и «GET IT IN THE LOBBY CLASS SHOP - 150»;
--  • Card — полоска «NEW IN COLLECTION!» и имя карточки (этап 6, блок H2);
--  • Collection — полоска «COLLECTION COMPLETE! +100» (этап 6, блок H2).
-- Полоски идут по очереди, по 3.5 сек.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Progress = require(Shared:WaitForChild("Progress"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))
local PixelWindow = require(script.Parent:WaitForChild("PixelWindow"))

local Colors = Theme.Colors

local ProgressFx = {}

local STRIP_SECONDS = 3.5
local LEVEL_SECONDS = 3

local started = false
local gui: ScreenGui
local sound: Sound
local touchOnly = false

---------------------------------------------------------------- конфетти

local function confetti()
	local colors = Config.Progress.Salute.Colors
	for _ = 1, 46 do
		local size = math.random(2, 4) * 3
		local piece = Theme.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, 0, -math.random(10, 120)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 3) * 90, -- пиксели — только прямые углы
			ZIndex = 30,
			Parent = gui,
		})
		local seconds = 1.6 + math.random() * 1.2
		local tween = TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1, 40),
		})
		tween:Play()
		task.delay(seconds, function()
			piece:Destroy()
		end)
	end
end

---------------------------------------------------------------- LEVEL UP

local levelToken = 0

local function showLevelUp(level: number, rank: string, diamonds: number)
	levelToken += 1
	local token = levelToken
	local old = gui:FindFirstChild("LevelUp")
	if old then
		old:Destroy()
	end
	local big = if touchOnly then 24 else 40
	local frame = Theme.new("Frame", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 180),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Parent = gui,
	})
	local scale = Theme.new("UIScale", { Scale = 0.3, Parent = frame })
	local labels: { TextLabel } = {}
	local function line(text: string, y: number, size: number, color: Color3)
		local label = Theme.pixelLabel({
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, size + 4),
			Text = text,
			TextColor3 = color,
			ZIndex = 26,
			Parent = frame,
		}, size, math.max(2, size // 8))
		table.insert(labels, label)
	end
	line("LEVEL UP!", 0, big, Colors.Gold)
	line(("LV %d"):format(level), big + 14, if touchOnly then 16 else 24, Colors.White)
	local y = big + 14 + (if touchOnly then 24 else 34)
	if rank ~= "" then
		local info = Progress.rankOf(level)
		line("NEW RANK: " .. rank, y, 16, info.Color)
		y += 26
	end
	if diamonds > 0 then
		local text = "+" .. diamonds
		local row = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(#text * 16 + 40, 32),
			BackgroundTransparency = 1,
			ZIndex = 26,
			Parent = frame,
		})
		local label = Theme.pixelLabel({
			Size = UDim2.new(1, -40, 1, 0),
			Text = text,
			TextColor3 = Colors.Diamond,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 26,
			Parent = row,
		}, 16, 2)
		table.insert(labels, label)
		local icon = PixelIcon.new("Diamond", true, 27)
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(1, 0, 0.5, 0)
		icon.Size = PixelIcon.size("Diamond", 2)
		icon.Parent = row
	end
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	confetti()
	SoundService:PlayLocalSound(sound)
	task.delay(LEVEL_SECONDS, function()
		if levelToken ~= token then
			return
		end
		for _, label in labels do
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
		task.delay(0.55, function()
			frame:Destroy()
		end)
	end)
end

---------------------------------------------------------------- полоски по очереди

type Strip = { icon: string, title: string, titleColor: Color3, text: string, diamonds: number? }
local queue: { Strip } = {}
local showing = false

local function showStrip(strip: Strip)
	local width = if touchOnly then 340 else 460
	local frame = Theme.new("Frame", {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.27, 0),
		Size = UDim2.fromOffset(width, 76),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = gui,
	})
	local inset = PixelWindow.box(frame, Colors.Navy, Colors.Gold)
	local icon = PixelIcon.new(strip.icon, true, 24)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, inset + 6, 0.5, 0)
	icon.Size = PixelIcon.size(strip.icon, 3)
	icon.Parent = frame
	local left = inset + 6 + 48 + 10
	local titleRow = Theme.new("Frame", {
		Position = UDim2.fromOffset(left, inset + 6),
		Size = UDim2.new(1, -left - inset - 6, 0, 20),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = frame,
	})
	local title = Theme.pixelLabel({
		Size = UDim2.new(1, 0, 1, 0),
		Text = strip.title,
		TextColor3 = strip.titleColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = titleRow,
	}, 16, 2)
	if strip.diamonds then
		-- Алмаз сразу за текстом (в пиксельном шрифте 💎 нет): ширина текста — по TextBounds
		local gem = PixelIcon.new("Diamond", false, 25)
		gem.AnchorPoint = Vector2.new(0, 0.5)
		gem.Size = PixelIcon.size("Diamond", 1)
		gem.Parent = titleRow
		local function place()
			gem.Position = UDim2.new(0, title.TextBounds.X + 6, 0.5, 0)
		end
		place()
		title:GetPropertyChangedSignal("TextBounds"):Connect(place)
	end
	Theme.pixelLabel({
		Position = UDim2.fromOffset(left, inset + 34),
		Size = UDim2.new(1, -left - inset - 6, 0, 24),
		Text = strip.text,
		TextColor3 = Colors.Marble,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 24,
		Parent = frame,
	}, 8, 1)
	local scale = Theme.new("UIScale", { Scale = 0.6, Parent = frame })
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	SoundService:PlayLocalSound(sound)
	task.wait(STRIP_SECONDS)
	TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
	task.wait(0.22)
	frame:Destroy()
end

local function pushStrip(strip: Strip)
	table.insert(queue, strip)
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			showStrip(table.remove(queue, 1) :: Strip)
		end
		showing = false
	end)
end

---------------------------------------------------------------- запуск

function ProgressFx.start()
	if started then
		return
	end
	started = true
	touchOnly = Theme.touchOnly()
	gui = Theme.screenGui("ProgressFx", 15, true)
	sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Purchase
	sound.Volume = Config.Sounds.PurchaseVolume
	sound.Parent = gui
	Theme.bindEffects(sound)
	Remotes.get(Remotes.Names.ProgressEvent).OnClientEvent:Connect(function(kind: any, a: any, b: any, c: any)
		if kind == "LevelUp" and typeof(a) == "number" then
			showLevelUp(a, if typeof(b) == "string" then b else "", if typeof(c) == "number" then c else 0)
		elseif kind == "Quest" and typeof(a) == "string" then
			local reward = if typeof(b) == "number" then b else 0
			pushStrip({ icon = "Quests", title = ("QUEST DONE! +%d"):format(reward), titleColor = Colors.Green, text = a, diamonds = reward })
		elseif kind == "Badge" and typeof(a) == "string" then
			pushStrip({ icon = "Medal", title = "ACHIEVEMENT!", titleColor = Colors.Gold, text = a })
		elseif kind == "Newbie" then
			local diamonds = if typeof(a) == "number" then a else 0
			local tries = if typeof(b) == "number" then b else 0
			pushStrip({
				icon = "Gift",
				title = ("WELCOME, GUARD! +%d"):format(diamonds),
				titleColor = Colors.Gold,
				text = if tries > 0
					then ("%d FREE RUN WITH ANY CLASS - OPEN CLASSES"):format(tries)
					else "EARN DIAMONDS BY SURVIVING NIGHTS",
				diamonds = diamonds,
			})
		elseif kind == "Card" and typeof(a) == "string" then
			pushStrip({
				icon = if b == "Exhibit" then "Painting" else "Thief",
				title = "NEW IN COLLECTION!",
				titleColor = Colors.Turquoise,
				text = a .. "! SEE IT IN THE LOBBY: COLLECTION",
				diamonds = nil,
			})
		elseif kind == "Collection" and typeof(a) == "string" then
			local diamonds = if typeof(b) == "number" then b else 0
			pushStrip({
				icon = "Collection",
				title = ("COLLECTION COMPLETE! +%d"):format(diamonds),
				titleColor = Colors.Gold,
				text = if a == "thieves" then "YOU CAUGHT EVERY KIND OF THIEF" else "EVERY EXHIBIT IS IN YOUR COLLECTION",
				diamonds = diamonds,
			})
		elseif kind == "TrialOver" and typeof(a) == "string" then
			local price = if typeof(b) == "number" then b else 0
			pushStrip({
				icon = "Classes",
				title = ("LIKED %s?"):format(string.upper(a)),
				titleColor = Colors.Gold,
				text = ("GET IT FOREVER IN THE LOBBY CLASS SHOP - %d"):format(price),
				diamonds = nil,
			})
		end
	end)
end

return ProgressFx
