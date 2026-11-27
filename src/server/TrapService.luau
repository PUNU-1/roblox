-- Защита из магазина (решения 43 и 49). Покупается днём удержанием F (целиком или вскладчину,
-- Purchase.luau), держится до конца забега.
--  • Лазерная сетка вокруг выбранного экспоната (F у экспоната): вор подошёл — тревога,
--    вор замедляется и подсвечивается для всех сквозь стены, сетка гаснет на перезарядку.
--  • Сигнализация на Мону Лизу (F у щитка ALARM справа от картины): вор начал снимать картину — воет сирена.

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
local Audio = require(Server:WaitForChild("Audio"))
local Purchase = require(Server:WaitForChild("Purchase"))
local ShopService = require(Server:WaitForChild("ShopService"))
local ProgressService = require(Server:WaitForChild("ProgressService"))

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
local alarmPanel: BasePart? = nil
local alarmLamp: BasePart? = nil
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

-- Удержание F (или покупка из окна магазина — fromShop, без проверки расстояния): остаток цены, если хватает
-- денег, иначе всё, что есть (Purchase.take). Только днём.
local function takeContribution(player: Player, part: BasePart, paid: number, price: number, fromShop: boolean?): number
	if not dayActive then
		return 0
	end
	return Purchase.take(player, part, paid, price, fromShop)
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

-- Деталь-украшение, приваренная к месту (без столкновений): болты, ручки, полоски (этап 5, блок F2).
local function trimPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
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
		-- Этап 5, блок F2: тяжёлое основание, колпак сверху, тёмные линзы излучателей на высоте лучей
		local base = trimPart(model, "PostBase", Vector3.new(0.2, 0.8, 0.8), CFrame.new(corner + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromHex("1C1F26"), Enum.Material.Metal, Enum.PartType.Cylinder)
		base.CanQuery = false
		trimPart(model, "PostCap", Vector3.new(0.55, 0.25, 0.55), CFrame.new(corner + Vector3.new(0, Laser.PostHeight + 0.12, 0)), Color3.fromHex("1C1F26"), Enum.Material.Metal)
		trimPart(model, "PostTop", Vector3.new(0.22, 0.22, 0.22), CFrame.new(corner + Vector3.new(0, Laser.PostHeight + 0.32, 0)), Laser.BeamColor, Enum.Material.Neon, Enum.PartType.Ball)
		for _, height in Laser.BeamHeights do
			trimPart(model, "Lens", Vector3.new(0.18, 0.52, 0.52), CFrame.new(corner + Vector3.new(0, height, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromHex("3A0F12"), Enum.Material.Glass, Enum.PartType.Cylinder)
		end
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

local INACTIVE_STATES = {
	[GameState.ThiefAnim.Stunned] = true,
	[GameState.ThiefAnim.Surrender] = true,
	[GameState.ThiefAnim.Knockout] = true,
	[GameState.ThiefAnim.Arrest] = true,
}

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
				local animState = thief:GetAttribute(GameState.NpcAttr.AnimState)
				if
					thief:IsA("Model")
					and root
					and root:IsA("BasePart")
					and not root.Anchored
					and thief:GetAttribute(GameState.ThiefAttr.Surrendered) ~= true
					and not INACTIVE_STATES[animState]
				then
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
				Audio.alarm()
				bannerRemote:FireAllClients(("LASER ALARM: %s!"):format(string.upper(grid.exhibit.title)), "danger")
			end
		end
	end
end

local function refreshGridPrompt(grid: Grid)
	if grid.prompt then
		grid.prompt.Enabled = dayActive and grid.model == nil and GameState.isHallOpen(grid.exhibit.hall)
		grid.prompt.ObjectText = Purchase.progressText("Laser grid", grid.paid, Laser.Price)
		Purchase.setProgress(grid.prompt, grid.paid, Laser.Price)
	end
end

-- Вклад в сетку: кнопка F у экспоната или окно магазина (fromShop). Возвращает, сколько взяли.
local function contributeGrid(grid: Grid, player: Player, fromShop: boolean): number
	local part = anchorPart(grid.exhibit)
	if grid.model or not part or not GameState.isHallOpen(grid.exhibit.hall) then
		return 0
	end
	local amount = takeContribution(player, part, grid.paid, Laser.Price, fromShop)
	if amount > 0 then
		grid.paid += amount
		if grid.paid >= Laser.Price then
			ProgressService.teamBought(Purchase.backers(part), "Trap")
			buildFence(grid)
		end
		refreshGridPrompt(grid)
	end
	return amount
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
	local prompt = Purchase.newPrompt(part, "LaserPrompt", Laser.Price)
	prompt.Triggered:Connect(function(player)
		contributeGrid(grid, player, false)
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
		alarmPrompt.ObjectText = Purchase.progressText("Mona Lisa alarm", alarmPaid, Alarm.Price)
		Purchase.setProgress(alarmPrompt, alarmPaid, Alarm.Price)
	end
	if alarmLamp then
		alarmLamp.Color = if alarmOwned then Alarm.LampOnColor else Alarm.LampOffColor
	end
end

-- Щиток ALARM на стене справа от картины: у него своя кнопка F. На самой картине — кнопка сетки,
-- а Roblox на одну клавишу показывает только одну ближайшую кнопку: подошёл к щитку — видна его кнопка.
local function buildAlarmPanel(exhibit: ExhibitService.Exhibit): BasePart
	local panel = Instance.new("Part")
	panel.Name = "AlarmPanel"
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanTouch = false
	panel.CastShadow = false
	panel.Size = Alarm.PanelSize
	panel.Color = Alarm.PanelColor
	panel.Material = Enum.Material.Metal
	panel.CFrame = exhibit.home * CFrame.new(Alarm.PanelOffset)
	panel.Parent = securityFolder

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 60
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.95)
	label.Size = UDim2.fromScale(0.9, 0.3)
	label.Text = "ALARM"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("FFFFFF")
	label.Parent = gui

	-- Лампа сверху: тёмная, пока сигнализация не куплена, ярко-красная — когда куплена
	local lamp = Instance.new("Part")
	lamp.Name = "AlarmLamp"
	lamp.Shape = Enum.PartType.Ball
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanTouch = false
	lamp.CastShadow = false
	lamp.Material = Enum.Material.Neon
	lamp.Color = Alarm.LampOffColor
	local lampSize = Alarm.PanelSize.X * 0.45
	lamp.Size = Vector3.new(lampSize, lampSize, lampSize)
	lamp.CFrame = panel.CFrame * CFrame.new(0, Alarm.PanelSize.Y * 0.2, -Alarm.PanelSize.Z / 2)
	lamp.Parent = panel
	alarmLamp = lamp

	-- Этап 5, блок F2: рамка, кнопочная панель, болты по углам, сирена сверху и труба с проводами в стену
	local size = Alarm.PanelSize
	local dark = Color3.fromHex("1C1F26")
	local steel = Color3.fromHex("9AA6BC")
	trimPart(panel, "Bezel", Vector3.new(size.X + 0.2, size.Y + 0.2, size.Z * 0.6), panel.CFrame * CFrame.new(0, 0, size.Z * 0.3), dark, Enum.Material.Metal)
	trimPart(panel, "Keypad", Vector3.new(size.X * 0.55, size.Y * 0.2, 0.06), panel.CFrame * CFrame.new(0, -size.Y * 0.05, -size.Z / 2 - 0.03), dark, Enum.Material.Metal)
	for row = 0, 1 do
		for col = -1, 1 do
			trimPart(panel, "Key", Vector3.new(0.14, 0.1, 0.05), panel.CFrame * CFrame.new(col * 0.22, -size.Y * 0.02 - row * 0.16, -size.Z / 2 - 0.07), steel, Enum.Material.Metal)
		end
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			trimPart(panel, "Bolt", Vector3.new(0.12, 0.12, 0.12), panel.CFrame * CFrame.new(x * (size.X / 2 - 0.12), y * (size.Y / 2 - 0.12), -size.Z / 2), steel, Enum.Material.Metal, Enum.PartType.Ball)
		end
	end
	trimPart(panel, "SirenBase", Vector3.new(size.X * 0.7, 0.2, size.Z), panel.CFrame * CFrame.new(0, size.Y / 2 + 0.1, 0), dark, Enum.Material.Metal)
	trimPart(panel, "Siren", Vector3.new(0.5, size.X * 0.55, size.X * 0.55), panel.CFrame * CFrame.new(0, size.Y / 2 + 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), Alarm.LampOnColor, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.2
	trimPart(panel, "Conduit", Vector3.new(0.14, 2.4, 0.14), panel.CFrame * CFrame.new(size.X / 2 - 0.15, size.Y / 2 + 1.2, size.Z / 2 - 0.05), steel, Enum.Material.Metal)
	return panel
end

-- Вклад в сигнализацию: кнопка F у щитка или окно магазина (fromShop). Возвращает, сколько взяли.
local function contributeAlarm(player: Player, fromShop: boolean): number
	local part = alarmPanel
	if alarmOwned or not part then
		return 0
	end
	local amount = takeContribution(player, part, alarmPaid, Alarm.Price, fromShop)
	if amount > 0 then
		alarmPaid += amount
		if alarmPaid >= Alarm.Price then
			ProgressService.teamBought(Purchase.backers(part), "Trap")
			alarmOwned = true
			bannerRemote:FireAllClients("MONA LISA ALARM INSTALLED", "info")
		end
		refreshAlarmPrompt()
	end
	return amount
end

local function setupAlarm()
	for _, exhibit in ExhibitService.list() do
		if exhibit.isMain then
			local part = buildAlarmPanel(exhibit)
			alarmPanel = part
			local prompt = Purchase.newPrompt(part, "AlarmPrompt", Alarm.Price)
			prompt.Triggered:Connect(function(player)
				contributeAlarm(player, false)
			end)
			alarmPrompt = prompt
		end
	end
	refreshAlarmPrompt()
end

---------------------------------------------------------------- окно магазина (этап 4, блок 1b)

local PREVIEW_POST = Color3.fromHex("2A2F3A")

local function previewPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.Parent = model
	return part
end

-- 3D-картинка лазерной сетки: стойки и лучи вокруг экспоната (у Моны Лизы — перед картиной).
-- Лучи — тонкие неоновые детали: Beam в ViewportFrame не видно.
local function laserPreview(exhibitId: string, isMain: boolean): Model
	local model = Instance.new("Model")
	model.Name = "LaserPreview"
	local halfX, halfZ = Laser.FenceHalf, Laser.FenceHalf
	local centerZ = 0
	local exhibit = ExhibitService.preview(exhibitId)
	if isMain then
		halfX, halfZ = Laser.MainFenceWidth / 2, Laser.MainFenceDepth / 2
		centerZ = -halfZ -- картина на стене, сетка перед ней (перед — в −Z)
		exhibit:PivotTo(CFrame.new(0, 1.2, 0))
	end
	exhibit.Parent = model
	local corners = {
		Vector3.new(-halfX, 0, centerZ - halfZ),
		Vector3.new(halfX, 0, centerZ - halfZ),
		Vector3.new(halfX, 0, centerZ + halfZ),
		Vector3.new(-halfX, 0, centerZ + halfZ),
	}
	for index, corner in corners do
		previewPart(model, "Post", Vector3.new(0.4, Laser.PostHeight, 0.4), CFrame.new(corner + Vector3.new(0, Laser.PostHeight / 2, 0)), PREVIEW_POST, Enum.Material.Metal)
		local nextCorner = corners[index % #corners + 1]
		for _, height in Laser.BeamHeights do
			local a = corner + Vector3.new(0, height, 0)
			local b = nextCorner + Vector3.new(0, height, 0)
			previewPart(model, "Beam", Vector3.new(0.12, 0.12, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Laser.BeamColor, Enum.Material.Neon)
		end
	end
	return model
end

-- 3D-картинка сигнализации: щиток ALARM с красной лампой и сиреной на бархатной стенке.
local function alarmPreview(): Model
	local model = Instance.new("Model")
	model.Name = "AlarmPreview"
	local size = Alarm.PanelSize
	previewPart(model, "Wall", Vector3.new(size.X + 1.2, size.Y + 2.2, 0.2), CFrame.new(0, (size.Y + 2.2) / 2, 0.25), Color3.fromHex("5E1622"), Enum.Material.Fabric)
	previewPart(model, "Panel", size, CFrame.new(0, size.Y / 2 + 0.3, 0), Alarm.PanelColor, Enum.Material.Metal)
	local lampSize = size.X * 0.45
	local lamp = previewPart(model, "Lamp", Vector3.new(lampSize, lampSize, lampSize), CFrame.new(0, size.Y * 0.7 + 0.3, -size.Z / 2), Alarm.LampOnColor, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	local siren = previewPart(model, "Siren", Vector3.new(0.5, 1.1, 1.1), CFrame.new(0, size.Y + 1.2, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Alarm.LampOnColor, Enum.Material.Glass)
	siren.Shape = Enum.PartType.Cylinder
	siren.Transparency = 0.15
	previewPart(model, "SirenBase", Vector3.new(1.3, 0.25, 0.6), CFrame.new(0, size.Y + 0.75, -0.1), PREVIEW_POST, Enum.Material.Metal)
	return model
end

local function gridOf(exhibitId: string): Grid?
	for exhibit, grid in grids do
		if exhibit.id == exhibitId then
			return grid
		end
	end
	return nil
end

-- Сигнализация и лазерные сетки (у каждого экспоната своя) во вкладке Security. Камеры добавляет CameraService.
local function registerInShop()
	ShopService.register({
		category = "Security",
		id = "Alarm",
		title = "Mona Lisa Alarm",
		info = "Siren when a thief touches the painting",
		order = 1,
		price = Alarm.Price,
		preview = alarmPreview(),
		state = function(): ShopService.State
			return { paid = alarmPaid, owned = alarmOwned }
		end,
		buy = function(player: Player): (string, string)
			if alarmOwned then
				return ShopService.fail("The alarm is already installed")
			end
			local amount = contributeAlarm(player, true)
			return ShopService.sharedResult("Mona Lisa Alarm", amount, alarmPaid, Alarm.Price)
		end,
	})
	for index, entry in ExhibitService.catalog() do
		local id = entry.id
		ShopService.register({
			category = "Security",
			id = "Laser_" .. id,
			title = "Laser Grid",
			info = ("%s • slows thieves %d s"):format(entry.title, Laser.SlowSeconds),
			order = 1 + index,
			price = Laser.Price,
			hall = entry.hall,
			preview = laserPreview(id, id == ExhibitService.MainId),
			state = function(): ShopService.State
				local grid = gridOf(id)
				if not grid then
					return { paid = 0, owned = false, missing = "NO EXHIBIT" } -- экспонат ещё не куплен
				end
				return { paid = grid.paid, owned = grid.model ~= nil }
			end,
			buy = function(player: Player): (string, string)
				local grid = gridOf(id)
				if not grid then
					return ShopService.fail(("Buy the %s first — Exhibits tab"):format(entry.title))
				elseif grid.model then
					return ShopService.fail("This laser grid is already installed")
				elseif not GameState.isHallOpen(grid.exhibit.hall) then
					return ShopService.fail("Open the hall first — Halls tab")
				end
				local amount = contributeGrid(grid, player, true)
				return ShopService.sharedResult("Laser Grid — " .. entry.title, amount, grid.paid, Laser.Price)
			end,
		})
	end
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
	registerInShop()
	-- Сигнализация: вор начал снимать Мону Лизу
	ExhibitService.StealStarted.Event:Connect(function(exhibit: ExhibitService.Exhibit)
		if exhibit.isMain and alarmOwned then
			Audio.alarm()
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
