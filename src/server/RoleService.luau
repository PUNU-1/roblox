-- Игроки: роли, READY, форма охраны, перенос между лобби и залом,
-- телефон оператора и пульт в диспетчерской (кто сейчас смотрит камеры).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local PlayerAttr = GameState.PlayerAttr
local Role = GameState.Role
local Phase = GameState.Phase

local RoleService = {}

local map: Instance
local consolePrompt: ProximityPrompt? = nil
local phoneProps: { [Player]: Instance } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local BADGE_STUB: { ModelLibrary.StubPart } = {
	{ size = Vector3.new(0.45, 0.45, 0.08), offset = CFrame.identity, color = Color3.fromHex("D4A93A"), material = Enum.Material.Metal },
}

local PHONE_STUB: { ModelLibrary.StubPart } = {
	{ name = "Handle", size = Vector3.new(0.6, 1.1, 0.1), offset = CFrame.identity, color = Color3.fromHex("111111") },
	{ name = "Screen", size = Vector3.new(0.5, 0.9, 0.02), offset = CFrame.new(0, 0.05, -0.06), color = Color3.fromHex("3BC6C1"), material = Enum.Material.Neon },
}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setFrozen(player: Player, frozen: boolean)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = if frozen then 0 else Config.Players.WalkSpeed
	humanoid.JumpHeight = if frozen then 0 else Config.Players.JumpHeight
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

-- Всё, что носят на голове, остаётся (решение 55): шапки, волосы, очки, брови.
local HEAD_ACCESSORY_TYPES: { [Enum.AccessoryType]: boolean } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}
-- У старых аксессуаров тип бывает Unknown — тогда смотрим, к чему он крепится
local HEAD_ATTACHMENTS: { [string]: boolean } = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

local function isHeadAccessory(accessory: Accessory): boolean
	if HEAD_ACCESSORY_TYPES[accessory.AccessoryType] then
		return true
	end
	local handle = accessory:FindFirstChild("Handle")
	if handle then
		for _, child in handle:GetChildren() do
			if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
				return true
			end
		end
	end
	return false
end

-- Форма охраны: убираем свою одежду и аксессуары на теле, красим тело, надеваем значок.
-- Шапки и волосы игрока остаются.
local function applyUniform(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, child in character:GetChildren() do
		if (child:IsA("Accessory") and not isHeadAccessory(child)) or child:IsA("Clothing") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.TorsoColor3 = Config.Uniform.Torso
		bodyColors.LeftArmColor3 = Config.Uniform.Arms
		bodyColors.RightArmColor3 = Config.Uniform.Arms
		bodyColors.LeftLegColor3 = Config.Uniform.Legs
		bodyColors.RightLegColor3 = Config.Uniform.Legs
	end
	humanoid:AddAccessory(ModelLibrary.accessory(MapSchema.Models.GuardBadge, BADGE_STUB, "BodyFrontAttachment"))
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

function RoleService.setViewing(player: Player, open: boolean, source: string?)
	if open == RoleService.isViewing(player) and (not open or player:GetAttribute(PlayerAttr.ViewSource) == source) then
		return
	end
	player:SetAttribute(PlayerAttr.ViewingCameras, open)
	player:SetAttribute(PlayerAttr.ViewSource, if open then source else "")
	setFrozen(player, open)
	if open and source == "Phone" then
		addPhoneProp(player)
	else
		removePhoneProp(player)
	end
end

function RoleService.closeAllViews()
	for _, player in Players:GetPlayers() do
		RoleService.setViewing(player, false)
	end
end

function RoleService.canUsePhone(player: Player): boolean
	-- Телефон с камерами — умение только оператора, даже в одиночной игре (решение 59)
	return player:GetAttribute(PlayerAttr.Role) == Role.Operator
end

function RoleService.readyCounts(): (number, number)
	local ready, total = 0, 0
	for _, player in Players:GetPlayers() do
		total += 1
		if player:GetAttribute(PlayerAttr.Ready) == true then
			ready += 1
		end
	end
	return ready, total
end

function RoleService.resetReady()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(PlayerAttr.Ready, false)
	end
end

-- Все игроки на сервере идут на смену.
function RoleService.startRound(): { Player }
	local list = {}
	for index, player in Players:GetPlayers() do
		if index > Config.Players.Max then
			break -- лишние ждут в комнате охраны
		end
		player:SetAttribute(PlayerAttr.InRound, true)
		table.insert(list, player)
		placeInHall(player, index)
	end
	return list
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
		player:SetAttribute(PlayerAttr.Ready, false)
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
	phoneProps[player] = nil
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
	player:SetAttribute(PlayerAttr.Role, Role.Patrol)
	player:SetAttribute(PlayerAttr.Ready, false)
	player:SetAttribute(PlayerAttr.InRound, false)
	player:SetAttribute(PlayerAttr.ViewingCameras, false)
	player:SetAttribute(PlayerAttr.ViewSource, "")
	player:SetAttribute(PlayerAttr.Money, 0)

	connections[player] = {
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end),
		player.CharacterAppearanceLoaded:Connect(function(character)
			applyUniform(player, character)
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
	prompt.HoldDuration = Config.Cameras.ConsoleHoldSeconds
	prompt.MaxActivationDistance = Config.Cameras.ConsolePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = console
	prompt.Triggered:Connect(function(player)
		if isRoundPhase() and RoleService.isParticipant(player) then
			RoleService.setViewing(player, true, "Console")
		end
	end)
	consolePrompt = prompt
end

local function setupRemotes()
	Remotes.get(Remotes.Names.SetRole).OnServerEvent:Connect(function(player, role)
		if GameState.phase() ~= Phase.Lobby then
			return
		end
		if role ~= Role.Patrol and role ~= Role.Operator then
			return
		end
		player:SetAttribute(PlayerAttr.Role, role)
	end)

	Remotes.get(Remotes.Names.SetReady).OnServerEvent:Connect(function(player, ready)
		if GameState.phase() ~= Phase.Lobby or typeof(ready) ~= "boolean" then
			return
		end
		player:SetAttribute(PlayerAttr.Ready, ready)
	end)

	Remotes.get(Remotes.Names.RequestCameras).OnServerEvent:Connect(function(player, open)
		if typeof(open) ~= "boolean" then
			return
		end
		if not open then
			RoleService.setViewing(player, false)
			return
		end
		if isRoundPhase() and RoleService.isParticipant(player) and RoleService.canUsePhone(player) then
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
		end
	end
end

return RoleService
