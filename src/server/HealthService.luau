-- Здоровье охраны (блок 4).
--  • У охранника 100 здоровья (MaxHealth), бронежилет даёт броню: урон сначала тратит броню, потом здоровье.
--    Само здоровье не восстанавливается — только аптечкой (WeaponService вызывает HealthService.heal).
--  • Здоровье кончилось — охранник лежит (Downed) и медленно ползёт: не стреляет, не ловит, не покупает,
--    телефон и пульт закрываются. Над ним кнопка «Revive»: друг держит F 10 сек — охранник встаёт с 50.
--    Никто не поднял — лежит до утра (утром встаёт с 50).
--  • Лежат все охранники смены — ночь проиграна (GameLoop спрашивает HealthService.allDown()).
-- Всё хранится в атрибутах игрока (Health, Armor, Downed…): клиенты по ним рисуют полоски и позы.
-- Урон бывает только ночью и только от грабителей (RobberService); сервер решает всё сам.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local PlayerAttr = GameState.PlayerAttr
local Settings = Config.Health

local HealthService = {}

-- Охранник упал без сил (player). WeaponService убирает у него оружие.
HealthService.Downed = Instance.new("BindableEvent")
-- Охранника подняли (player).
HealthService.Revived = Instance.new("BindableEvent")

local PROMPT_NAME = "RevivePrompt"
local holdStarted: { [Player]: { target: Player, at: number } } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local hurtRemote = Remotes.get(Remotes.Names.Hurt)
local bannerRemote = Remotes.get(Remotes.Names.Banner)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function HealthService.health(player: Player): number
	return tonumber(player:GetAttribute(PlayerAttr.Health)) or Settings.Max
end

function HealthService.maxHealth(player: Player): number
	return tonumber(player:GetAttribute(PlayerAttr.MaxHealth)) or Settings.Max
end

function HealthService.armor(player: Player): number
	return tonumber(player:GetAttribute(PlayerAttr.Armor)) or 0
end

function HealthService.isDowned(player: Player): boolean
	return RoleService.isDowned(player)
end

---------------------------------------------------------------- кнопка Revive

local function removePrompt(player: Player)
	local root = rootOf(player)
	local prompt = root and root:FindFirstChild(PROMPT_NAME)
	if prompt then
		prompt:Destroy()
	end
end

local function clearReviver(reviver: Player)
	local entry = holdStarted[reviver]
	holdStarted[reviver] = nil
	reviver:SetAttribute(PlayerAttr.ReviveTarget, 0)
	if entry and entry.target:GetAttribute(PlayerAttr.RevivedBy) == reviver.UserId then
		entry.target:SetAttribute(PlayerAttr.RevivedBy, 0)
		entry.target:SetAttribute(PlayerAttr.ReviveStartedAt, 0)
	end
end

-- Тот, кто поднимает, должен сам стоять на ногах и быть рядом.
local function canRevive(reviver: Player, target: Player): boolean
	if reviver == target or not RoleService.canAct(reviver) or not RoleService.isDowned(target) then
		return false
	end
	local a, b = rootOf(reviver), rootOf(target)
	if not (a and b) then
		return false
	end
	return (a.Position - b.Position).Magnitude <= Settings.ReviveDistance + Config.Catch.ServerDistanceSlack
end

local function revive(target: Player, reviver: Player?)
	if not RoleService.isDowned(target) then
		return
	end
	removePrompt(target)
	target:SetAttribute(PlayerAttr.Downed, false)
	target:SetAttribute(PlayerAttr.RevivedAt, now())
	target:SetAttribute(PlayerAttr.RevivedBy, 0)
	target:SetAttribute(PlayerAttr.ReviveStartedAt, 0)
	target:SetAttribute(PlayerAttr.Health, math.min(HealthService.maxHealth(target), Settings.ReviveHealth))
	RoleService.refreshMovement(target)
	local root = rootOf(target)
	if root then
		Audio.playOnce(Config.Sounds.GuardGetUp, root, Config.Sounds.GuardGetUpVolume)
	end
	if reviver then
		bannerRemote:FireAllClients(("%s IS BACK UP!"):format(string.upper(target.DisplayName)), "info")
	end
	HealthService.Revived:Fire(target)
end

local function addPrompt(target: Player)
	local root = rootOf(target)
	if not root or root:FindFirstChild(PROMPT_NAME) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Revive"
	prompt.ObjectText = target.DisplayName
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.HoldDuration = Settings.ReviveSeconds
	prompt.MaxActivationDistance = Settings.ReviveDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	-- Кто начал держать F: запоминаем время (сервер сам проверит, что держали все 10 сек),
	-- у поднимающего — поза «помогает встать», у лежащего — полоска
	prompt.PromptButtonHoldBegan:Connect(function(reviver)
		if not canRevive(reviver, target) then
			return
		end
		holdStarted[reviver] = { target = target, at = now() }
		reviver:SetAttribute(PlayerAttr.ReviveTarget, target.UserId)
		target:SetAttribute(PlayerAttr.RevivedBy, reviver.UserId)
		target:SetAttribute(PlayerAttr.ReviveStartedAt, now())
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver)
		clearReviver(reviver)
	end)
	prompt.Triggered:Connect(function(reviver)
		local entry = holdStarted[reviver]
		clearReviver(reviver)
		if not entry or entry.target ~= target or not canRevive(reviver, target) then
			return
		end
		if now() - entry.at < Settings.ReviveSeconds - Settings.ReviveSlack then
			return -- держали меньше 10 сек (клиенту не доверяем)
		end
		revive(target, reviver)
	end)
end

---------------------------------------------------------------- урон и лечение

local function burst(part: BasePart, color: Color3, count: number, speed: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(1, function()
		emitter:Destroy()
	end)
end

-- Пуля попала в бронежилет: голубые искры на груди (броня держит удар).
local function armorSpark(player: Player)
	local torso = player.Character and player.Character:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		burst(torso, Config.Weapons.ArmorSparkColor, 10, 10)
	end
end

-- Аптечка подействовала: зелёные искорки вокруг охранника и «+50», всплывает и тает (видят все).
function HealthService.healEffect(player: Player, amount: number)
	local character = player.Character
	local torso = character and character:FindFirstChild("UpperTorso")
	local head = character and character:FindFirstChild("Head")
	local color = Config.Weapons.Medkit.Color
	if torso and torso:IsA("BasePart") then
		burst(torso, color, 24, 6)
		Audio.playOnce(Config.Sounds.Heal, torso, Config.Sounds.HealVolume, nil, Config.Sounds.HealSpeed)
	end
	if head and head:IsA("BasePart") and amount > 0 then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "HealText"
		billboard.Size = UDim2.fromScale(3, 1.2)
		billboard.StudsOffset = Vector3.new(0, 1.6, 0)
		billboard.MaxDistance = 80
		billboard.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = ("+%d"):format(math.floor(amount))
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.Parent = billboard
		billboard.Parent = head
		task.spawn(function()
			for step = 1, 20 do
				task.wait(0.05)
				if not billboard.Parent then
					return
				end
				billboard.StudsOffset = Vector3.new(0, 1.6 + step * 0.06, 0)
				label.TextTransparency = math.max(0, (step - 10) / 10)
				label.TextStrokeTransparency = label.TextTransparency
			end
			billboard:Destroy()
		end)
	end
end

local function goDown(player: Player)
	player:SetAttribute(PlayerAttr.Health, 0)
	player:SetAttribute(PlayerAttr.Downed, true)
	player:SetAttribute(PlayerAttr.DownedAt, now())
	player:SetAttribute(PlayerAttr.KnockedUntil, 0) -- удар Громилы больше не важен: лежит без сил
	player:SetAttribute(PlayerAttr.Crouch, false)
	player:SetAttribute(PlayerAttr.Lean, 0)
	RoleService.setViewing(player, false)
	RoleService.refreshMovement(player)
	local root = rootOf(player)
	if root then
		Audio.playOnce(Config.Sounds.GuardDown, root, Config.Sounds.GuardDownVolume)
	end
	addPrompt(player)
	bannerRemote:FireAllClients(("%s IS DOWN!"):format(string.upper(player.DisplayName)), "danger")
	HealthService.Downed:Fire(player)
end

-- Урон охраннику (пуля или дубинка грабителя). from — откуда прилетело (край экрана вспыхнет с той стороны).
-- Сначала тратится броня, потом здоровье; кончилось здоровье — лежит. Возвращает true, если урон прошёл.
function HealthService.damage(player: Player, amount: number, from: Vector3?): boolean
	if amount <= 0 or GameState.phase() ~= GameState.Phase.Night then
		return false
	end
	if not RoleService.isParticipant(player) or RoleService.isDowned(player) or not rootOf(player) then
		return false
	end
	local armor = HealthService.armor(player)
	local absorbed = math.min(armor, amount)
	if absorbed > 0 then
		player:SetAttribute(PlayerAttr.Armor, armor - absorbed)
		armorSpark(player)
	end
	local left = amount - absorbed
	local health = math.max(0, HealthService.health(player) - left)
	player:SetAttribute(PlayerAttr.Health, health)
	hurtRemote:FireClient(player, from, amount)
	if health <= 0 then
		goDown(player)
	else
		local root = rootOf(player)
		if root then
			Audio.playOnce(Config.Sounds.Hurt, root, Config.Sounds.HurtVolume)
		end
	end
	return true
end

-- Лечение (аптечка). Лежащего аптечка не поднимает. Возвращает, сколько вылечили.
function HealthService.heal(player: Player, amount: number): number
	if RoleService.isDowned(player) then
		return 0
	end
	local health = HealthService.health(player)
	local healed = math.min(amount, HealthService.maxHealth(player) - health)
	if healed > 0 then
		player:SetAttribute(PlayerAttr.Health, health + healed)
	end
	return math.max(0, healed)
end

-- Бронежилет: броня до полной.
function HealthService.setArmor(player: Player, armor: number)
	player:SetAttribute(PlayerAttr.Armor, math.max(0, armor))
end

---------------------------------------------------------------- ночь, утро, забег

-- Лежат все охранники смены (и хотя бы один на смене есть) — ночь проиграна.
function HealthService.allDown(): boolean
	local participants = RoleService.participants()
	if #participants == 0 then
		return false
	end
	for _, player in participants do
		if not RoleService.isDowned(player) then
			return false
		end
	end
	return true
end

-- Утро: кто пролежал до утра, встаёт с ReviveHealth. Остальные остаются со своим здоровьем.
function HealthService.endNight()
	for _, player in Players:GetPlayers() do
		local reviver = holdStarted[player]
		if reviver then
			clearReviver(player)
		end
		if RoleService.isDowned(player) then
			revive(player, nil)
		end
	end
end

-- Полное здоровье, без брони и без «лежит» (новый забег или вошёл опоздавший).
local function resetPlayer(player: Player)
	if holdStarted[player] then
		clearReviver(player)
	end
	removePrompt(player)
	player:SetAttribute(PlayerAttr.MaxHealth, Settings.Max)
	player:SetAttribute(PlayerAttr.Health, Settings.Max)
	player:SetAttribute(PlayerAttr.Armor, 0)
	player:SetAttribute(PlayerAttr.Downed, false)
	player:SetAttribute(PlayerAttr.DownedAt, 0)
	player:SetAttribute(PlayerAttr.RevivedAt, 0)
	player:SetAttribute(PlayerAttr.ReviveTarget, 0)
	player:SetAttribute(PlayerAttr.RevivedBy, 0)
	player:SetAttribute(PlayerAttr.ReviveStartedAt, 0)
	player:SetAttribute(PlayerAttr.Crouch, false)
	player:SetAttribute(PlayerAttr.Lean, 0)
	RoleService.refreshMovement(player)
end
HealthService.resetPlayer = resetPlayer

local function onPlayerAdded(player: Player)
	resetPlayer(player)
	connections[player] = {
		-- Вошёл в забег (с начала или опоздавшим) или вышел из него — всё с нуля
		player:GetAttributeChangedSignal(PlayerAttr.InRound):Connect(function()
			resetPlayer(player)
		end),
		-- Новый персонаж, а охранник всё ещё лежит — кнопка Revive на новом персонаже
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			if RoleService.isDowned(player) then
				addPrompt(player)
			end
		end),
	}
end

local function onPlayerRemoving(player: Player)
	if holdStarted[player] then
		clearReviver(player)
	end
	-- Кого-то поднимали этим игроком — полоска у лежащего гаснет
	for reviver, entry in holdStarted do
		if entry.target == player then
			clearReviver(reviver)
		end
	end
	local list = connections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[player] = nil
	end
end

function HealthService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return HealthService
