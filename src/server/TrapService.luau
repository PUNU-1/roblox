-- Защита из магазина (решения 43 и 49). Покупается днём вскладчину, держится до конца забега.
--  • Лазерная сетка вокруг выбранного экспоната (E у экспоната): вор подошёл — тревога,
--    вор замедляется и подсвечивается для всех сквозь стены, сетка гаснет на перезарядку.
--  • Сигнализация на Мону Лизу (F у картины): вор начал снимать картину — воет сирена.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local ExhibitService = require(Server:WaitForChild("ExhibitService"))
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local Laser = Config.Traps.LaserGrid
local Alarm = Config.Traps.Alarm

local TrapService = {}

type Grid = {
	exhibit: ExhibitService.Exhibit,
	paid: number,
	model: Model?, -- стойки и лучи, когда сетка куплена
	beams: { Beam },
	center: Vector3,
	readyAt: number,
	prompt: ProximityPrompt?,
}

local grids: { [ExhibitService.Exhibit]: Grid } = {}
local alarmPaid = 0
local alarmOwned = false
local alarmPrompt: ProximityPrompt? = nil
local dayActive = false
local checkConnection: RBXScriptConnection? = nil
local highlightTokens: { [Model]: number } = {}
local securityFolder: Folder

local bannerRemote = Remotes.get(Remotes.Names.Banner)

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Деталь экспоната, к которой крепим кнопки покупки.
local function anchorPart(exhibit: ExhibitService.Exhibit): BasePart?
	local model = exhibit.model
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Общая покупка вскладчину: сколько денег взяли у игрока (0 — ничего).
local function takeContribution(player: Player, part: BasePart, paid: number, price: number): number
	if not dayActive or not RoleService.isParticipant(player) then
		return 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	if (root.Position - part.Position).Magnitude > Config.Halls.PromptDistance + Config.Catch.ServerDistanceSlack then
		return 0
	end
	local money = tonumber(player:GetAttribute(GameState.PlayerAttr.Money)) or 0
	local amount = math.min(Config.Halls.ContributeStep, money, price - paid)
	if amount <= 0 then
		return 0
	end
	player:SetAttribute(GameState.PlayerAttr.Money, money - amount)
	return amount
end

local function newPrompt(part: BasePart, action: string, key: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = Config.Halls.ContributeHoldSeconds
	prompt.MaxActivationDistance = Config.Halls.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part
	return prompt
end

---------------------------------------------------------------- лазерная сетка

-- Квадрат стоек вокруг экспоната. У Моны Лизы — перед картиной (она висит на стене).
local function fenceCorners(exhibit: ExhibitService.Exhibit): (Vector3, { Vector3 })
	local home = exhibit.home
	local look = home.LookVector
	local front = Vector3.new(look.X, 0, look.Z)
	front = if front.Magnitude > 0.1 then front.Unit else Vector3.new(0, 0, -1)
	local right = front:Cross(Vector3.yAxis)
	local base = Vector3.new(home.Position.X, 0, home.Position.Z)
	local center, halfRight, halfFront
	if exhibit.isMain then
		center = base + front * Laser.MainFenceDepth / 2
		halfRight, halfFront = Laser.MainFenceWidth / 2, Laser.MainFenceDepth / 2
	else
		center = base
		halfRight, halfFront = Laser.FenceHalf, Laser.FenceHalf
	end
	local corners = {
		center - right * halfRight - front * halfFront,
		center + right * halfRight - front * halfFront,
		center + right * halfRight + front * halfFront,
		center - right * halfRight + front * halfFront,
	}
	return center, corners
end

local function buildFence(grid: Grid)
	local center, corners = fenceCorners(grid.exhibit)
	local model = Instance.new("Model")
	model.Name = "LaserFence"
	local attachments: { { Attachment } } = {}
	for index, corner in corners do
		local post = Instance.new("Part")
		post.Name = "Post" .. index
		post.Size = Vector3.new(0.4, Laser.PostHeight, 0.4)
		post.CFrame = CFrame.new(corner + Vector3.new(0, Laser.PostHeight / 2, 0))
		post.Color = Color3.fromHex("2A2F3A")
		post.Material = Enum.Material.Metal
		post.Anchored = true
		post.CanCollide = false
		post.Parent = model
		attachments[index] = {}
		for level, height in Laser.BeamHeights do
			local attachment = Instance.new("Attachment")
			attachment.Name = "Laser" .. level
			attachment.Position = Vector3.new(0, height - Laser.PostHeight / 2, 0)
			attachment.Parent = post
			attachments[index][level] = attachment
		end
	end
	local beams = {}
	for index = 1, #corners do
		local nextIndex = index % #corners + 1
		for level = 1, #Laser.BeamHeights do
			local beam = Instance.new("Beam")
			beam.Attachment0 = attachments[index][level]
			beam.Attachment1 = attachments[nextIndex][level]
			beam.Color = ColorSequence.new(Laser.BeamColor)
			beam.Width0 = Laser.BeamWidth
			beam.Width1 = Laser.BeamWidth
			beam.LightEmission = 1
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Parent = model
			table.insert(beams, beam)
		end
	end
	model.Parent = securityFolder
	grid.model = model
	grid.beams = beams
	grid.center = center
end

local function setBeams(grid: Grid, enabled: boolean)
	for _, beam in grid.beams do
		beam.Enabled = enabled
	end
end

-- Срабатывание: лучи вспыхивают белым и гаснут до конца перезарядки.
local function flashThenRecharge(grid: Grid)
	for _, beam in grid.beams do
		beam.Color = ColorSequence.new(Laser.FlashColor)
		beam.Width0 = Laser.FlashWidth
		beam.Width1 = Laser.FlashWidth
	end
	task.delay(Laser.FlashSeconds, function()
		for _, beam in grid.beams do
			beam.Color = ColorSequence.new(Laser.BeamColor)
			beam.Width0 = Laser.BeamWidth
			beam.Width1 = Laser.BeamWidth
		end
		setBeams(grid, false)
	end)
end

local function slowAndHighlight(thief: Model)
	thief:SetAttribute("SlowedUntil", now() + Laser.SlowSeconds)
	local highlight = thief:FindFirstChild("LaserHighlight")
	if not (highlight and highlight:IsA("Highlight")) then
		local created = Instance.new("Highlight")
		created.Name = "LaserHighlight"
		created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- видно сквозь стены
		created.FillColor = Config.Effects.SlowHighlightColor
		created.OutlineColor = Config.Effects.SlowHighlightColor
		created.FillTransparency = 0.5
		created.Parent = thief
	end
	local token = (highlightTokens[thief] or 0) + 1
	highlightTokens[thief] = token
	task.delay(Laser.SlowSeconds, function()
		if highlightTokens[thief] == token then
			highlightTokens[thief] = nil
			local existing = thief:FindFirstChild("LaserHighlight")
			if existing then
				existing:Destroy()
			end
		end
	end)
end

local function checkGrids()
	local thievesFolder = Workspace:FindFirstChild(MapSchema.Thieves)
	if not thievesFolder then
		return
	end
	local time = now()
	for _, grid in grids do
		if grid.model and time >= grid.readyAt then
			setBeams(grid, true)
			local radius = if grid.exhibit.isMain then Laser.MainTriggerRadius else Laser.TriggerRadius
			local tripped = false
			for _, thief in thievesFolder:GetChildren() do
				local root = thief:FindFirstChild("HumanoidRootPart")
				if thief:IsA("Model") and root and root:IsA("BasePart") and not root.Anchored then
					local offset = root.Position - grid.center
					if Vector3.new(offset.X, 0, offset.Z).Magnitude < radius then
						slowAndHighlight(thief)
						tripped = true
					end
				end
			end
			if tripped then
				grid.readyAt = time + Laser.RechargeSeconds
				flashThenRecharge(grid)
				Audio.playOnce(Config.Sounds.Alarm, nil, Config.Sounds.AlarmVolume)
				bannerRemote:FireAllClients(("LASER ALARM: %s!"):format(string.upper(grid.exhibit.title)), "danger")
			end
		end
	end
end

local function refreshGridPrompt(grid: Grid)
	if grid.prompt then
		grid.prompt.Enabled = dayActive and grid.model == nil and GameState.isHallOpen(grid.exhibit.hall)
		grid.prompt.ObjectText = ("Laser grid — $%d / $%d"):format(grid.paid, Laser.Price)
	end
end

local function ensureGrid(exhibit: ExhibitService.Exhibit): Grid?
	local existing = grids[exhibit]
	if existing then
		return existing
	end
	local part = anchorPart(exhibit)
	if not part then
		return nil
	end
	local grid: Grid = { exhibit = exhibit, paid = 0, model = nil, beams = {}, center = part.Position, readyAt = 0, prompt = nil }
	local prompt = newPrompt(part, ("Add $%d"):format(Config.Halls.ContributeStep), Enum.KeyCode.E)
	prompt.Name = "LaserPrompt"
	prompt.Triggered:Connect(function(player)
		if grid.model then
			return
		end
		local amount = takeContribution(player, part, grid.paid, Laser.Price)
		if amount > 0 then
			grid.paid += amount
			if grid.paid >= Laser.Price then
				buildFence(grid)
			end
			refreshGridPrompt(grid)
		end
	end)
	grid.prompt = prompt
	grids[exhibit] = grid
	refreshGridPrompt(grid)
	return grid
end

local function removeGrid(exhibit: ExhibitService.Exhibit)
	local grid = grids[exhibit]
	if not grid then
		return
	end
	if grid.model then
		grid.model:Destroy()
	end
	if grid.prompt then
		grid.prompt:Destroy()
	end
	grids[exhibit] = nil
end

---------------------------------------------------------------- сигнализация на Мону Лизу

local function refreshAlarmPrompt()
	if alarmPrompt then
		alarmPrompt.Enabled = dayActive and not alarmOwned
		alarmPrompt.ObjectText = ("Mona Lisa alarm — $%d / $%d"):format(alarmPaid, Alarm.Price)
	end
end

local function setupAlarm()
	for _, exhibit in ExhibitService.list() do
		if exhibit.isMain then
			local part = anchorPart(exhibit)
			if part then
				local prompt = newPrompt(part, ("Add $%d"):format(Config.Halls.ContributeStep), Enum.KeyCode.F)
				prompt.Name = "AlarmPrompt"
				prompt.UIOffset = Vector2.new(0, 90) -- ниже кнопки сетки, чтобы не наезжали
				prompt.Triggered:Connect(function(player)
					if alarmOwned then
						return
					end
					local amount = takeContribution(player, part, alarmPaid, Alarm.Price)
					if amount > 0 then
						alarmPaid += amount
						if alarmPaid >= Alarm.Price then
							alarmOwned = true
							bannerRemote:FireAllClients("MONA LISA ALARM INSTALLED", "info")
						end
						refreshAlarmPrompt()
					end
				end)
				alarmPrompt = prompt
			end
		end
	end
	refreshAlarmPrompt()
end

---------------------------------------------------------------- фазы

-- День: можно покупать защиту для всех экспонатов, что есть сейчас.
function TrapService.beginDay()
	dayActive = true
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end
	for _, exhibit in ExhibitService.list() do
		ensureGrid(exhibit)
	end
	for _, grid in grids do
		grid.readyAt = 0
		if grid.model then
			setBeams(grid, true)
		end
		refreshGridPrompt(grid)
	end
	refreshAlarmPrompt()
end

-- Ночь: покупать нельзя, сетки следят за ворами.
function TrapService.beginNight()
	dayActive = false
	for _, grid in grids do
		refreshGridPrompt(grid)
	end
	refreshAlarmPrompt()
	local accumulator = 0
	checkConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Laser.CheckSeconds then
			accumulator = 0
			checkGrids()
		end
	end)
end

-- Конец забега: вся купленная защита пропадает.
function TrapService.clear()
	dayActive = false
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end
	local list = {}
	for exhibit in grids do
		table.insert(list, exhibit)
	end
	for _, exhibit in list do
		removeGrid(exhibit)
	end
	table.clear(highlightTokens)
	alarmPaid = 0
	alarmOwned = false
	refreshAlarmPrompt()
end

function TrapService.init(_map: Instance)
	local existing = Workspace:FindFirstChild("Security")
	if existing and existing:IsA("Folder") then
		securityFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Security"
		created.Parent = Workspace
		securityFolder = created
	end
	setupAlarm()
	-- Сигнализация: вор начал снимать Мону Лизу
	ExhibitService.StealStarted.Event:Connect(function(exhibit: ExhibitService.Exhibit)
		if exhibit.isMain and alarmOwned then
			Audio.playOnce(Config.Sounds.Alarm, nil, Config.Sounds.AlarmVolume)
			bannerRemote:FireAllClients("ALARM: SOMEONE IS TOUCHING THE MONA LISA!", "danger")
		end
	end)
	-- Экспонат купили днём — сразу можно покупать ему сетку
	ExhibitService.Added.Event:Connect(function(exhibit: ExhibitService.Exhibit)
		if dayActive then
			ensureGrid(exhibit)
		end
	end)
	-- Экспонат унесли — его сетка пропадает вместе с ним
	ExhibitService.Lost.Event:Connect(function(exhibit: ExhibitService.Exhibit)
		removeGrid(exhibit)
	end)
end

return TrapService
