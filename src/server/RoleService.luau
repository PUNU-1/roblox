-- Игроки: классы (атрибут Role, блок 5), форма охраны, старт смены команды из круга START SHIFT,
-- перенос между лобби и залом, телефон оператора и пульт в диспетчерской (кто сейчас смотрит камеры),
-- скорость охранника (смотрит камеры, лежит, присел, рывок патруля).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))
local Uniform = require(script.Parent:WaitForChild("Uniform"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Phase = GameState.Phase

local RoleService = {}

local map: Instance
local consolePrompt: ProximityPrompt? = nil
local phoneProps: { [Player]: Instance } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local PHONE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Handle", size = Vector3.new(0.6, 1.1, 0.1), offset = CFrame.identity, color = Color3.fromHex("111111") },
	{ name = "Screen", size = Vector3.new(0.5, 0.9, 0.02), offset = CFrame.new(0, 0.05, -0.06), color = Color3.fromHex("3BC6C1"), material = Enum.Material.Neon },
}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Охранник лежит после удара Громилы (блок 3).
local function knockedNow(player: Player): boolean
	local untilTime = player:GetAttribute(PlayerAttr.KnockedUntil)
	return typeof(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow()
end

-- Патруль в рывке (блок 5, AbilityService): атрибут AbilityUntil ещё не прошёл.
local function sprintingNow(player: Player): boolean
	local untilTime = player:GetAttribute(PlayerAttr.AbilityUntil)
	return GameState.roleOf(player) == Role.Patrol and typeof(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow()
end

-- Скорость охранника по его состоянию (одно место на всё): смотрит камеры или сбит Громилой — стоит,
-- лежит без сил — ползёт, присел — идёт медленнее, в рывке — быстрее, иначе — обычный шаг и прыжок.
local function refreshMovement(player: Player)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local speed, jump = Config.Players.WalkSpeed, Config.Players.JumpHeight
	if player:GetAttribute(PlayerAttr.ViewingCameras) == true or knockedNow(player) then
		speed, jump = 0, 0
	elseif player:GetAttribute(PlayerAttr.Downed) == true then
		speed, jump = Config.Health.CrawlSpeed, 0
	elseif player:GetAttribute(PlayerAttr.Crouch) == true then
		speed, jump = Config.Stance.CrouchSpeed, 0
	elseif sprintingNow(player) then
		speed = Config.Classes.Patrol.SprintSpeed
	end
	humanoid.WalkSpeed = speed
	humanoid.JumpHeight = jump
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = false
end

local function removePhoneProp(player: Player)
	local prop = phoneProps[player]
	if prop then
		prop:Destroy()
		phoneProps[player] = nil
	end
end

local function addPhoneProp(player: Player)
	removePhoneProp(player)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local phone = ModelLibrary.build(MapSchema.Models.Phone, PHONE_STUB)
	ModelLibrary.weldTo(phone, hand, hand.CFrame * CFrame.new(0, -0.3, -0.3))
	phone.Parent = character
	phoneProps[player] = phone
end

local function markerCFrame(name: string): CFrame?
	local found = map:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found.CFrame
	end
	return nil
end

local function moveCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
end

local function spreadOffset(index: number): Vector3
	-- Ставим игроков рядом, но не друг в друга
	return Vector3.new(((index - 1) % 4) * 4 - 6, 0, math.floor((index - 1) / 4) * 4)
end

local function placeInHall(player: Player, index: number)
	local base = markerCFrame(MapSchema.PatrolSpawn)
	if base then
		moveCharacter(player, base + spreadOffset(index))
	end
end

local function placeInLobby(player: Player, index: number)
	local base = markerCFrame(MapSchema.LobbySpawn)
	if base then
		moveCharacter(player, base + Vector3.new(0, 3, 0) + spreadOffset(index))
	end
end

local function isRoundPhase(): boolean
	local phase = GameState.phase()
	return phase == Phase.Day or phase == Phase.Night
end

function RoleService.isSolo(): boolean
	return #Players:GetPlayers() == 1
end

function RoleService.isParticipant(player: Player): boolean
	return player:GetAttribute(PlayerAttr.InRound) == true
end

function RoleService.participants(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if RoleService.isParticipant(player) then
			table.insert(list, player)
		end
	end
	return list
end

function RoleService.isViewing(player: Player): boolean
	return player:GetAttribute(PlayerAttr.ViewingCameras) == true
end

-- Охранник лежит после удара Громилы (блок 3).
function RoleService.isKnocked(player: Player): boolean
	return knockedNow(player)
end

-- Здоровье кончилось: лежит и ползёт, пока друг не поднимет (блок 4, HealthService).
function RoleService.isDowned(player: Player): boolean
	return player:GetAttribute(PlayerAttr.Downed) == true
end

function RoleService.isReviving(player: Player): boolean
	return (tonumber(player:GetAttribute(PlayerAttr.ReviveTarget)) or 0) ~= 0
end

-- Охранник может действовать: на смене, не смотрит камеры, не сбит Громилой, не лежит без сил и не поднимает друга.
function RoleService.canAct(player: Player): boolean
	return RoleService.isParticipant(player) and not RoleService.isViewing(player) and not knockedNow(player)
		and not RoleService.isDowned(player) and not RoleService.isReviving(player)
end

-- Пересчитать скорость (после смены стойки, падения, подъёма).
RoleService.refreshMovement = refreshMovement

function RoleService.setViewing(player: Player, open: boolean, source: string?)
	if open == RoleService.isViewing(player) and (not open or player:GetAttribute(PlayerAttr.ViewSource) == source) then
		return
	end
	player:SetAttribute(PlayerAttr.ViewingCameras, open)
	player:SetAttribute(PlayerAttr.ViewSource, if open then source else "")
	refreshMovement(player)
	if open and source == "Phone" then
		addPhoneProp(player)
	else
		removePhoneProp(player)
	end
end

-- Звёздочки над головой сбитого охранника (кружатся у клиентов, Guards.client).
local function addStars(player: Player, seconds: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DizzyStars"
	billboard.Size = UDim2.fromScale(3, 1)
	billboard.StudsOffset = Vector3.new(0, Config.Knockdown.StarsHeight, 0)
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Stars"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "★  ★  ★"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("FFD23F")
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = head
	Debris:AddItem(billboard, seconds)
end

-- Громила сбил охранника с ног: он лежит seconds секунд (не ходит, не ловит, телефон закрывается),
-- потом встаёт сам. Как он падает и встаёт, рисуют клиенты (Guards.client) по атрибутам KnockedAt / KnockedUntil.
-- Возвращает false, если охранник уже лежит.
function RoleService.knockDown(player: Player, seconds: number): boolean
	if RoleService.isKnocked(player) or RoleService.isDowned(player) or not RoleService.isParticipant(player) then
		return false
	end
	local started = Workspace:GetServerTimeNow()
	player:SetAttribute(PlayerAttr.KnockedAt, started)
	player:SetAttribute(PlayerAttr.KnockedUntil, started + seconds)
	RoleService.setViewing(player, false)
	refreshMovement(player)
	addStars(player, seconds)
	task.delay(seconds + 0.05, function()
		if player.Parent and not RoleService.isKnocked(player) then
			refreshMovement(player)
		end
	end)
	return true
end

function RoleService.closeAllViews()
	for _, player in Players:GetPlayers() do
		RoleService.setViewing(player, false)
	end
end

function RoleService.canUsePhone(player: Player): boolean
	-- Телефон с камерами — умение только оператора, даже в одиночной игре (решение 59)
	return GameState.roleOf(player) == Role.Operator
end

-- Класс можно выбрать в лобби или пока игрок ждёт в комнате охраны (опоздавший). На смене класс не меняется
-- до конца забега (блок 5).
function RoleService.canChooseClass(player: Player): boolean
	return GameState.phase() == Phase.Lobby or not RoleService.isParticipant(player)
end

-- На смену идёт команда из круга START SHIFT (LobbyService.takeTeam). Остальные ждут в комнате охраны,
-- их пускают голосованием (VoteService).
function RoleService.startRound(team: { Player }): { Player }
	local list = {}
	for _, player in team do
		if #list >= Config.Players.Max then
			break
		end
		if player.Parent and not table.find(list, player) then
			player:SetAttribute(PlayerAttr.InRound, true)
			table.insert(list, player)
			placeInHall(player, #list)
		end
	end
	return list
end

-- Ночь начинается: вся охрана встаёт у Моны Лизы в центре (камеры и телефон закрываются).
function RoleService.gatherAtPainting()
	for index, player in RoleService.participants() do
		RoleService.setViewing(player, false)
		placeInHall(player, index)
	end
end

-- Опоздавший, которого пустили голосованием, входит в игру (с начала дня).
function RoleService.addToRound(player: Player)
	player:SetAttribute(PlayerAttr.InRound, true)
	player:SetAttribute(PlayerAttr.Money, 0)
	placeInHall(player, #RoleService.participants())
end

function RoleService.endRound()
	RoleService.closeAllViews()
	for index, player in Players:GetPlayers() do
		if RoleService.isParticipant(player) then
			placeInLobby(player, index)
		end
		player:SetAttribute(PlayerAttr.InRound, false)
	end
end

function RoleService.setConsoleEnabled(enabled: boolean)
	if consolePrompt then
		consolePrompt.Enabled = enabled
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- Группа столкновений охраны (туристы проходят сквозь охранников, воры — нет)
	ModelLibrary.setCollisionGroup(character, ModelLibrary.Groups.Guards)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = ModelLibrary.Groups.Guards
		end
	end)
	player:SetAttribute(PlayerAttr.ViewingCameras, false)
	player:SetAttribute(PlayerAttr.ViewSource, "")
	player:SetAttribute(PlayerAttr.KnockedUntil, 0) -- новый персонаж стоит на ногах
	phoneProps[player] = nil
	task.defer(refreshMovement, player) -- лежал без сил или присел — так и остаётся
	if RoleService.isParticipant(player) and isRoundPhase() then
		-- Погиб или упал во время смены — возвращаем в зал
		task.defer(function()
			if character.Parent then
				placeInHall(player, 1)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- вид от первого лица (решение 56)
	player.DevEnableMouseLock = false -- Shift — рывок патруля (блок 5), а не переключатель мыши Roblox
	player:SetAttribute(PlayerAttr.Role, Config.Classes.Default)
	player:SetAttribute(PlayerAttr.InRound, false)
	player:SetAttribute(PlayerAttr.ViewingCameras, false)
	player:SetAttribute(PlayerAttr.ViewSource, "")
	player:SetAttribute(PlayerAttr.Money, 0)

	connections[player] = {
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end),
		player.CharacterAppearanceLoaded:Connect(function(character)
			Uniform.apply(character) -- форма охраны, шапки и волосы остаются (решение 55)
		end),
	}
	GameState.set(GameState.Attr.Solo, RoleService.isSolo())
end

local function onPlayerRemoving(player: Player)
	removePhoneProp(player)
	local list = connections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[player] = nil
	end
	task.defer(function()
		GameState.set(GameState.Attr.Solo, RoleService.isSolo())
	end)
end

local function setupConsole()
	local console = map:FindFirstChild(MapSchema.ControlConsole, true)
	if not (console and console:IsA("BasePart")) then
		warn("[RoleService] Нет пульта ControlConsole на карте")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ConsolePrompt"
	prompt.ActionText = "Watch cameras"
	prompt.ObjectText = "Control console"
	prompt.KeyboardKeyCode = Config.Keys.Action
	prompt.HoldDuration = Config.Cameras.ConsoleHoldSeconds
	prompt.MaxActivationDistance = Config.Cameras.ConsolePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = console
	prompt.Triggered:Connect(function(player)
		if isRoundPhase() and RoleService.isParticipant(player) and not RoleService.isKnocked(player) and not RoleService.isDowned(player) then
			RoleService.setViewing(player, true, "Console")
		end
	end)
	consolePrompt = prompt
end

local function setupRemotes()
	-- Класс (блок 5): любой из Config.Classes.Order, только пока игрок не на смене
	Remotes.get(Remotes.Names.SetRole).OnServerEvent:Connect(function(player, role)
		-- Некупленный класс выбрать нельзя (этап 4, блок 1): владение — по сохранённому профилю
		if not RoleService.canChooseClass(player) or not GameState.classInfo(role) or not ProfileStore.owns(player, role) then
			return
		end
		player:SetAttribute(PlayerAttr.Role, role)
	end)

	Remotes.get(Remotes.Names.RequestCameras).OnServerEvent:Connect(function(player, open)
		if typeof(open) ~= "boolean" then
			return
		end
		if not open then
			RoleService.setViewing(player, false)
			return
		end
		if isRoundPhase() and RoleService.isParticipant(player) and RoleService.canUsePhone(player) and not RoleService.isKnocked(player)
			and not RoleService.isDowned(player)
		then
			local humanoid = getHumanoid(player)
			if humanoid and humanoid.Health > 0 then
				RoleService.setViewing(player, true, "Phone")
			end
		end
	end)
end

function RoleService.init(builtMap: Instance)
	map = builtMap
	setupConsole()
	setupRemotes()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		if player.Character then
			onCharacterAdded(player, player.Character)
			if player:HasAppearanceLoaded() then
				Uniform.apply(player.Character)
			end
		end
	end
end

return RoleService
