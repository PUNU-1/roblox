-- Блэкаут (блок 3, Светорез). Вор у щитка POWER в служебном коридоре вырубает свет:
--  • лампы мигают и гаснут: все дежурные лампы (атрибут NightLamp) и подсветка Моны Лизы;
--  • все камеры показывают «NO POWER» (атрибут GameState.Blackout, CameraService.isWorking);
--  • лампочка на щитке краснеет, у щитка появляется кнопка «Restore power» (держать F).
-- Свет возвращается, когда кто-то удержит F у щитка, или утром. Фонарики охраны работают и в блэкаут.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))
local Audio = require(Server:WaitForChild("Audio"))

local Settings = Config.Blackout

local BlackoutService = {}

type Lamp = { part: BasePart, lights: { Light }, material: Enum.Material }

local lamps: { Lamp } = {}
local fuseBox: PVInstance? = nil
local fusePart: BasePart? = nil -- деталь щитка с кнопкой и искрами
local fuseLamp: BasePart? = nil
local prompt: ProximityPrompt? = nil
local flickerToken = 0
local holdStarted: { [Player]: number } = {}

local bannerRemote = Remotes.get(Remotes.Names.Banner)

function BlackoutService.isOut(): boolean
	return GameState.get(GameState.Attr.Blackout) == true
end

local function setLights(on: boolean)
	for _, lamp in lamps do
		if lamp.part.Parent then
			lamp.part.Material = if on then lamp.material else Enum.Material.SmoothPlastic
			for _, light in lamp.lights do
				light.Enabled = on
			end
		end
	end
end

local function setFuseLamp(out: boolean)
	if fuseLamp then
		fuseLamp.Color = if out then Settings.LampOutColor else Settings.LampOkColor
	end
end

-- Где встаёт Светорез: перед щитком. nil — щитка на карте нет.
function BlackoutService.standPoint(): Vector3?
	local box = fuseBox
	if not box or not GameState.isHallOpen(box:GetAttribute("Hall")) then
		return nil -- щиток в закрытом крыле (служебный коридор открывается вместе с южным крылом, этап 5, блок B)
	end
	local pivot = box:GetPivot()
	local front = pivot.Position + pivot.LookVector * Settings.StandOffset
	return Vector3.new(front.X, pivot.Position.Y + 3, front.Z)
end

-- Куда смотрит Светорез, пока работает.
function BlackoutService.lookPoint(): Vector3?
	return if fuseBox then fuseBox:GetPivot().Position else nil
end

-- Искры из щитка (пока Светорез возится с проводами), треск.
function BlackoutService.sparks(seconds: number)
	local part = fusePart
	if not part then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sparks"
	attachment.Parent = part
	attachment.WorldPosition = part.Position + (if fuseBox then fuseBox:GetPivot().LookVector else Vector3.zero) * (part.Size.Z / 2 + 0.1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Settings.SparkColor, Color3.fromHex("FF8A3D"))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(0.18, 0)
	emitter.Lifetime = NumberRange.new(0.25, 0.6)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 45
	emitter.Parent = attachment
	local flash = Instance.new("PointLight")
	flash.Color = Settings.SparkColor
	flash.Range = 10
	flash.Brightness = 2
	flash.Parent = attachment
	local sounds = Config.Sounds
	Audio.playOnce(sounds.Sparks, part, sounds.SparksVolume)
	task.spawn(function()
		local started = os.clock()
		while attachment.Parent and os.clock() - started < seconds do
			flash.Enabled = math.random() < 0.6 -- свет от искр дрожит
			task.wait(0.07)
		end
		attachment:Destroy()
	end)
end

-- Светорез вырубил свет: лампы мигают и гаснут, камеры — «NO POWER». false — света уже нет.
function BlackoutService.cut(): boolean
	if BlackoutService.isOut() then
		return false
	end
	GameState.set(GameState.Attr.Blackout, true)
	setFuseLamp(true)
	if prompt then
		prompt.Enabled = true
	end
	local sounds = Config.Sounds
	Audio.playOnce(sounds.Sparks, nil, sounds.SparksVolume, nil, 0.6)
	bannerRemote:FireAllClients("THE POWER IS OUT!", "danger")
	flickerToken += 1
	local token = flickerToken
	task.spawn(function()
		for index = 1, Settings.Flickers * 2 do
			if flickerToken ~= token or not BlackoutService.isOut() then
				return
			end
			setLights(index % 2 == 0)
			task.wait(Settings.FlickerSeconds * (1 + math.random()))
		end
		if flickerToken == token and BlackoutService.isOut() then
			setLights(false)
		end
	end)
	return true
end

-- Свет снова есть. announce — показать надпись (утром не показываем).
function BlackoutService.restore(announce: boolean)
	flickerToken += 1
	table.clear(holdStarted)
	local wasOut = BlackoutService.isOut()
	GameState.set(GameState.Attr.Blackout, false)
	setLights(true)
	setFuseLamp(false)
	if prompt then
		prompt.Enabled = false
	end
	if wasOut and announce then
		local sounds = Config.Sounds
		Audio.playOnce(sounds.PowerOn, nil, sounds.PowerOnVolume)
		bannerRemote:FireAllClients("THE POWER IS BACK!", "info")
	end
end

-- Утро или конец забега: свет есть, тихо.
function BlackoutService.reset()
	BlackoutService.restore(false)
end

local function onRestore(player: Player)
	if not BlackoutService.isOut() or GameState.phase() ~= GameState.Phase.Night then
		return
	end
	if not RoleService.canAct(player) then
		return
	end
	local started = holdStarted[player]
	holdStarted[player] = nil
	-- Начало удержания не дошло до сервера — пускаем, как раньше; дошло — проверяем время
	if started and Workspace:GetServerTimeNow() - started < Settings.RestoreHoldSeconds - 0.35 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local part = fusePart
	if not (root and root:IsA("BasePart") and part) then
		return
	end
	if (root.Position - part.Position).Magnitude > Settings.PromptDistance + Config.Catch.ServerDistanceSlack then
		return
	end
	BlackoutService.restore(true)
end

function BlackoutService.init(map: Instance)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("NightLamp") == true then
			local lights = {}
			for _, child in descendant:GetChildren() do
				if child:IsA("Light") then
					table.insert(lights, child)
				end
			end
			table.insert(lamps, { part = descendant, lights = lights, material = descendant.Material })
		end
	end
	-- Подсветка Моны Лизы тоже гаснет: в темноте у картины видно только фонарики
	local paintingLight = map:FindFirstChild(MapSchema.PaintingLight, true)
	if paintingLight and paintingLight:IsA("BasePart") then
		local lights = {}
		for _, child in paintingLight:GetChildren() do
			if child:IsA("Light") then
				table.insert(lights, child)
			end
		end
		table.insert(lamps, { part = paintingLight, lights = lights, material = paintingLight.Material })
	end

	local box = map:FindFirstChild(MapSchema.FuseBox, true)
	if box and box:IsA("PVInstance") then
		fuseBox = box
		local cabinet = box:FindFirstChild("Cabinet", true) or box:FindFirstChildWhichIsA("BasePart", true)
		if cabinet and cabinet:IsA("BasePart") then
			fusePart = cabinet
		end
		local lamp = box:FindFirstChild("Lamp", true)
		if lamp and lamp:IsA("BasePart") then
			fuseLamp = lamp
		end
	else
		warn("[BlackoutService] На карте нет щитка FuseBox — Светорез будет красть как обычный вор")
	end
	local part = fusePart
	if part then
		local created = Instance.new("ProximityPrompt")
		created.Name = "RestorePowerPrompt"
		created.ActionText = "Restore power"
		created.ObjectText = "POWER"
		created.KeyboardKeyCode = Config.Keys.Action
		created.HoldDuration = Settings.RestoreHoldSeconds
		created.MaxActivationDistance = Settings.PromptDistance
		created.RequiresLineOfSight = false
		created.Enabled = false
		created.Parent = part
		created.PromptButtonHoldBegan:Connect(function(player)
			if RoleService.canAct(player) then
				holdStarted[player] = Workspace:GetServerTimeNow()
			end
		end)
		created.PromptButtonHoldEnded:Connect(function(player)
			-- «Отпустил» может прийти раньше Triggered: стираем не сразу
			local started = holdStarted[player]
			task.delay(0.5, function()
				if started and holdStarted[player] == started then
					holdStarted[player] = nil
				end
			end)
		end)
		created.Triggered:Connect(onRestore)
		prompt = created
	end
	Players.PlayerRemoving:Connect(function(player)
		holdStarted[player] = nil
	end)
	GameState.set(GameState.Attr.Blackout, false)
	setFuseLamp(false)
end

return BlackoutService
