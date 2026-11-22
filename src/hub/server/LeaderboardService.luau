-- Доска рекордов в хабе (блок 6): две доски на восточной стене — топ-10 команд по числу ночей за всё время
-- и за эту неделю. Данные — RecordStore (OrderedDataStore, pcall с повтором), имена — UserService одним
-- запросом на всех. Доску рисует сервер (SurfaceGui на детали), клиентам ничего слать не нужно.
-- В Studio без доступа к API доска пишет «Leaderboard unavailable in Studio» и больше не спрашивает.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local RecordStore = require(script.Parent:WaitForChild("RecordStore"))

local Settings = Config.Leaderboard
local hex = Color3.fromHex

local NAVY = hex("1E2A44")
local DARK = hex("141B2E")
local GOLD = hex("D4A93A")
local MARBLE = hex("E8DCC4")
local MEDALS = { hex("F2C230"), hex("C9CED6"), hex("CD8A4A") } -- золото, серебро, бронза

local LeaderboardService = {}

type Row = { frame: Frame, medal: Frame, rank: TextLabel, names: TextLabel, nights: TextLabel }
type Board = { scope: string, rows: { Row }, status: TextLabel }

local boards: { Board } = {}
local nameCache: { [number]: string } = {}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

local function frame(parent: Instance, position: UDim2, size: UDim2, color: Color3, zIndex: number): Frame
	local f = Instance.new("Frame")
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	return f
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- Рисует пустую доску: заголовок, шапка таблицы, 10 строк, надпись поверх (загрузка, ошибка, пусто).
local function buildBoard(part: BasePart, scope: string, title: string, footer: string): Board
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local root = frame(gui, UDim2.new(), UDim2.fromScale(1, 1), DARK, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(NAVY, DARK)
	gradient.Parent = root

	label(root, { Text = title, TextColor3 = GOLD, Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.92, 0.11), ZIndex = 2 })
	label(root, {
		Text = "TOP TEAMS BY NIGHTS SURVIVED",
		TextColor3 = MARBLE,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.1, 0.13),
		Size = UDim2.fromScale(0.8, 0.045),
		ZIndex = 2,
	})
	frame(root, UDim2.fromScale(0.04, 0.19), UDim2.fromScale(0.92, 0.006), GOLD, 2)
	-- Шапка таблицы
	label(root, { Text = "#", TextColor3 = GOLD, Position = UDim2.fromScale(0.05, 0.205), Size = UDim2.fromScale(0.08, 0.045), ZIndex = 2 })
	label(root, {
		Text = "TEAM",
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.16, 0.205),
		Size = UDim2.fromScale(0.5, 0.045),
		ZIndex = 2,
	})
	label(root, { Text = "NIGHTS", TextColor3 = GOLD, Position = UDim2.fromScale(0.76, 0.205), Size = UDim2.fromScale(0.18, 0.045), ZIndex = 2 })

	local rows: { Row } = {}
	local top, rowH = 0.26, 0.066
	for index = 1, Settings.Top do
		local y = top + (index - 1) * rowH
		local rowFrame = frame(root, UDim2.fromScale(0.04, y), UDim2.fromScale(0.92, rowH - 0.008), if index % 2 == 0 then NAVY else DARK, 2)
		rowFrame.BackgroundTransparency = 0.2
		corner(rowFrame, UDim.new(0.25, 0))
		local medal = frame(rowFrame, UDim2.fromScale(0.015, 0.1), UDim2.fromScale(0.07, 0.8), MEDALS[index] or NAVY, 3)
		corner(medal, UDim.new(0.5, 0))
		medal.Visible = index <= 3
		local rank = label(rowFrame, {
			Text = tostring(index),
			TextColor3 = if index <= 3 then NAVY else MARBLE,
			Position = UDim2.fromScale(0.015, 0.12),
			Size = UDim2.fromScale(0.07, 0.76),
			ZIndex = 4,
		})
		local names = label(rowFrame, {
			Text = "",
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.13, 0.15),
			Size = UDim2.fromScale(0.62, 0.7),
			ZIndex = 4,
		})
		local nights = label(rowFrame, {
			Text = "",
			TextColor3 = GOLD,
			Position = UDim2.fromScale(0.78, 0.1),
			Size = UDim2.fromScale(0.18, 0.8),
			ZIndex = 4,
		})
		table.insert(rows, { frame = rowFrame, medal = medal, rank = rank, names = names, nights = nights })
	end
	label(root, {
		Text = footer,
		TextColor3 = hex("8A93A6"),
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.1, 0.935),
		Size = UDim2.fromScale(0.8, 0.04),
		ZIndex = 2,
	})
	local status = label(root, {
		Text = "Loading...",
		TextColor3 = MARBLE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.84, 0.09),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = NAVY,
		ZIndex = 6,
	})
	corner(status, UDim.new(0.3, 0))
	return { scope = scope, rows = rows, status = status }
end

-- Имена игроков (DisplayName) одним запросом на всех, кого ещё не знаем.
local function fetchNames(userIds: { number })
	local unknown = {}
	for _, id in userIds do
		if not nameCache[id] and not table.find(unknown, id) then
			table.insert(unknown, id)
		end
	end
	if #unknown == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, unknown)
	if not ok or typeof(infos) ~= "table" then
		warn("[LeaderboardService] Не удалось получить имена игроков: " .. tostring(infos))
		return
	end
	for _, info in infos do
		if typeof(info) == "table" and typeof(info.Id) == "number" then
			nameCache[info.Id] = tostring(info.DisplayName or info.Username or "Guard")
		end
	end
end

local function showStatus(board: Board, text: string?)
	board.status.Visible = text ~= nil
	if text then
		board.status.Text = text
	end
end

-- Перечитывает обе доски. false — хранилище недоступно.
local function refresh(): boolean
	local allOk = true
	for _, board in boards do
		local entries, err = RecordStore.top(board.scope, Settings.Top)
		if not entries then
			allOk = false
			if not RunService:IsStudio() then
				warn(("[LeaderboardService] Доска %s недоступна: %s"):format(board.scope, tostring(err)))
			end
			showStatus(board, if RunService:IsStudio() then "Leaderboard unavailable in Studio" else "Leaderboard unavailable — try again later")
			for _, row in board.rows do
				row.names.Text = ""
				row.nights.Text = ""
			end
			continue
		end
		local ids = {}
		for _, entry in entries do
			for _, id in entry.userIds do
				table.insert(ids, id)
			end
		end
		fetchNames(ids)
		for index, row in board.rows do
			local entry = entries[index]
			if entry then
				local names = {}
				for _, id in entry.userIds do
					table.insert(names, nameCache[id] or "Guard")
				end
				row.names.Text = table.concat(names, ", ")
				row.nights.Text = tostring(entry.nights)
			else
				row.names.Text = ""
				row.nights.Text = ""
			end
		end
		showStatus(board, if #entries == 0 then "No records yet — be the first team!" else nil)
	end
	return allOk
end

function LeaderboardService.init(map: Instance)
	for _, spec in {
		{ name = MapSchema.LeaderboardAllTime, scope = "AllTime", title = "ALL TIME", footer = "Every museum shift ever" },
		{ name = MapSchema.LeaderboardWeekly, scope = "Weekly", title = "THIS WEEK", footer = "Starts over every Monday" },
	} do
		local part = map:FindFirstChild(spec.name, true)
		if part and part:IsA("BasePart") then
			table.insert(boards, buildBoard(part, spec.scope, spec.title, spec.footer))
		else
			warn("[LeaderboardService] Нет доски " .. spec.name)
		end
	end
	task.spawn(function()
		while true do
			local ok = refresh()
			if not ok and RunService:IsStudio() then
				break -- в Studio без доступа к API ответ не изменится; надпись уже на доске
			end
			task.wait(Settings.RefreshSeconds)
		end
	end)
end

return LeaderboardService
