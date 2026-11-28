-- Игры в хабе, пока ждёшь команду (этап 8, блок P, решение 100). Только для удовольствия: без наград —
-- награды за тир и полосу можно накрутить. Рекорды — на табло этого сервера (не сохраняются).
--  • Тир: F у игрушечного пистолета — 30 сек стрельбы (стреляет один игрок, остальные ждут). Мишени
--    поднимаются случайно (не больше MaxUp сразу) и опускаются сами. Клиент (HubGames.client) шлёт номер
--    мишени, в которую попал (Remote RangeShot); сервер проверяет, что стреляет этот игрок, мишень поднята,
--    стрелок у стойки и не стреляет чаще ShotCooldown. Попадание — мишень сразу опускается, +1.
--  • Полоса препятствий: касание START — время пошло (атрибут CourseStartedAt), касание FINISH — время забега
--    (CourseLast) и, если лучше, рекорд сервера на табло. Упал — снова на старт, время с начала.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerAttr = GameState.PlayerAttr
local RangeSettings = Config.Hub.Range
local CourseSettings = Config.Hub.Course

local HubGames = {}

type Target = { model: Model, up: CFrame, down: CFrame, isUp: boolean, downAt: number }

local targets: { Target } = {}
local rangeShooter: Player? = nil
local rangeEndsAt = 0
local rangeBest = { name = "", score = -1 }
local lastShot: { [Player]: number } = {}
local gunPart: BasePart? = nil
local rangeLabel: TextLabel? = nil
local courseLabel: TextLabel? = nil
local courseBest = { name = "", seconds = math.huge }
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function labelOf(part: Instance?): TextLabel?
	local label = part and part:FindFirstChild("Text", true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

---------------------------------------------------------------- тир

local function setTarget(target: Target, up: boolean)
	target.isUp = up
	target.model:PivotTo(if up then target.up else target.down)
	if up then
		target.downAt = now() + random:NextNumber(RangeSettings.UpMin, RangeSettings.UpMax)
	end
end

local function refreshRangeBoard()
	local label = rangeLabel
	if not label then
		return
	end
	local lines = { "SHOOTING RANGE" }
	local shooter = rangeShooter
	if shooter then
		table.insert(lines, ("%s: %d HITS • %dS"):format(shooter.DisplayName, tonumber(shooter:GetAttribute(PlayerAttr.RangeScore)) or 0, math.max(0, math.ceil(rangeEndsAt - now()))))
	else
		table.insert(lines, "Press F at the toy pistol • 30 sec")
	end
	if rangeBest.score >= 0 then
		table.insert(lines, ("BEST: %s — %d"):format(rangeBest.name, rangeBest.score))
	end
	label.Text = table.concat(lines, "\n")
end

local function endRange()
	local shooter = rangeShooter
	rangeShooter = nil
	rangeEndsAt = 0
	for _, target in targets do
		setTarget(target, false)
	end
	if shooter and shooter.Parent then
		local score = tonumber(shooter:GetAttribute(PlayerAttr.RangeScore)) or 0
		if score > rangeBest.score then
			rangeBest = { name = shooter.DisplayName, score = score }
		end
		shooter:SetAttribute(PlayerAttr.RangeUntil, 0)
	end
	if gunPart then
		local prompt = gunPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end
	refreshRangeBoard()
end

local function startRange(player: Player)
	if rangeShooter or not player.Character then
		return
	end
	rangeShooter = player
	rangeEndsAt = now() + RangeSettings.Seconds
	player:SetAttribute(PlayerAttr.RangeScore, 0)
	player:SetAttribute(PlayerAttr.RangeUntil, rangeEndsAt)
	if gunPart then
		local prompt = gunPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end
	refreshRangeBoard()
	task.spawn(function()
		local nextPop = now() + 0.6
		while rangeShooter == player and player.Parent and now() < rangeEndsAt do
			local time = now()
			local upCount = 0
			for _, target in targets do
				if target.isUp and time >= target.downAt then
					setTarget(target, false)
				end
				if target.isUp then
					upCount += 1
				end
			end
			if time >= nextPop and upCount < RangeSettings.MaxUp then
				local downs = {}
				for _, target in targets do
					if not target.isUp then
						table.insert(downs, target)
					end
				end
				if #downs > 0 then
					setTarget(downs[random:NextInteger(1, #downs)], true)
				end
				nextPop = time + RangeSettings.PopEvery
			end
			refreshRangeBoard()
			task.wait(0.1)
		end
		if rangeShooter == player then
			endRange()
		end
	end)
end

local function onShot(player: Player, index: any)
	if typeof(index) ~= "number" or index ~= math.floor(index) or player ~= rangeShooter or now() >= rangeEndsAt then
		return
	end
	local target = targets[index]
	if not target or not target.isUp then
		return
	end
	local time = now()
	if time - (lastShot[player] or 0) < RangeSettings.ShotCooldown then
		return
	end
	lastShot[player] = time
	-- Стрелок стоит у стойки, а не бегает по тиру
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local gun = gunPart
	if not (root and root:IsA("BasePart")) or not gun or (root.Position - gun.Position).Magnitude > RangeSettings.MaxDistance then
		return
	end
	setTarget(target, false)
	player:SetAttribute(PlayerAttr.RangeScore, (tonumber(player:GetAttribute(PlayerAttr.RangeScore)) or 0) + 1)
	refreshRangeBoard()
end

local function setupRange(folder: Instance)
	for _, child in folder:GetChildren() do
		local index = child:GetAttribute("Index")
		if child:IsA("Model") and typeof(index) == "number" and string.sub(child.Name, 1, #MapSchema.RangeTargetPrefix) == MapSchema.RangeTargetPrefix then
			local up = child:GetPivot()
			-- Лежит: щит повёрнут на петле назад, к стене
			local target: Target = { model = child, up = up, down = up * CFrame.Angles(math.rad(88), 0, 0), isUp = false, downAt = 0 }
			targets[index] = target
			setTarget(target, false)
		end
	end
	local gun = folder:FindFirstChild(MapSchema.RangeGun)
	if gun and gun:IsA("BasePart") then
		gunPart = gun
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RangePrompt"
		prompt.ActionText = "Start range"
		prompt.ObjectText = "Toy pistol • 30 sec"
		prompt.KeyboardKeyCode = Config.Keys.Action
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = RangeSettings.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = gun
		prompt.Triggered:Connect(startRange)
	end
	rangeLabel = labelOf(folder:FindFirstChild(MapSchema.RangeBoard))
	Remotes.get(Remotes.Names.RangeShot).OnServerEvent:Connect(onShot)
	refreshRangeBoard()
end

---------------------------------------------------------------- полоса препятствий

local function refreshCourseBoard()
	local label = courseLabel
	if not label then
		return
	end
	if courseBest.seconds < math.huge then
		label.Text = ("OBSTACLE COURSE\nBEST: %s — %.1fs"):format(courseBest.name, courseBest.seconds)
	else
		label.Text = "OBSTACLE COURSE\nStep on START, run to FINISH"
	end
end

local function setupCourse(folder: Instance)
	local start = folder:FindFirstChild(MapSchema.CourseStart)
	local finish = folder:FindFirstChild(MapSchema.CourseFinish)
	courseLabel = labelOf(folder:FindFirstChild(MapSchema.CourseBoard))
	if start and start:IsA("BasePart") then
		start.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player then
				player:SetAttribute(PlayerAttr.CourseStartedAt, now()) -- пока стоит на старте, время всё сначала
			end
		end)
	end
	if finish and finish:IsA("BasePart") then
		finish.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			local started = player and tonumber(player:GetAttribute(PlayerAttr.CourseStartedAt)) or 0
			if not player or started <= 0 then
				return
			end
			player:SetAttribute(PlayerAttr.CourseStartedAt, 0)
			local seconds = now() - started
			if seconds < CourseSettings.MinSeconds or seconds > CourseSettings.MaxSeconds then
				return
			end
			player:SetAttribute(PlayerAttr.CourseLast, math.floor(seconds * 10 + 0.5) / 10)
			if seconds < courseBest.seconds then
				courseBest = { name = player.DisplayName, seconds = seconds }
				refreshCourseBoard()
			end
		end)
	end
	refreshCourseBoard()
end

function HubGames.init(map: Instance)
	local folder = map:FindFirstChild(MapSchema.HubGames)
	if not folder then
		warn("[HubGames] Нет папки HubGames на карте хаба")
		return
	end
	setupRange(folder)
	setupCourse(folder)
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
		if player == rangeShooter then
			endRange()
		end
	end)
end

return HubGames
