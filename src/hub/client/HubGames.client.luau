-- Игры в хабе на экране (этап 8, блок P): тир и полоса препятствий. Только картинка и намерения — счёт и время
-- решает сервер (HubGames). Без наград.
--  • Тир: пока стреляешь ты (атрибут RangeUntil), клик мышью или касание экрана — выстрел: луч из камеры
--    через точку на экране; попал в поднятую мишень — Remote RangeShot с её номером. Трассер от правой руки.
--    Сверху — «RANGE: 7 HITS • 18S», в конце — итог.
--  • Полоса препятствий: пока бежишь (CourseStartedAt), сверху — секундомер; на финише — «TIME: 12.4S».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local PlayerAttr = GameState.PlayerAttr
local localPlayer = Players.LocalPlayer
local shotRemote = Remotes.get(Remotes.Names.RangeShot)

local gui = Theme.screenGui("HubGames", 3)
local status = Theme.pixelLabel({
	Name = "GameStatus",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 146), -- под рекордом друга (HubHUD)
	Size = UDim2.new(0, 420, 0, 34),
	TextColor3 = Theme.Colors.Gold,
	Visible = false,
	Parent = gui,
}, 24)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function number(attr: string): number
	return tonumber(localPlayer:GetAttribute(attr)) or 0
end

local resultText = ""
local resultUntil = 0

local function showResult(text: string)
	resultText = text
	resultUntil = os.clock() + 3
end

---------------------------------------------------------------- тир

local function shooting(): boolean
	return number(PlayerAttr.RangeUntil) > now()
end

local function targetsFolder(): Instance?
	local map = Workspace:FindFirstChild(MapSchema.Root)
	return map and map:FindFirstChild(MapSchema.HubGames)
end

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "ToyTracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromHex("FFB13B")
	beam.Size = Vector3.new(0.08, 0.08, length)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = Workspace
	Debris:AddItem(beam, 0.08)
end

local function shootAt(screen: Vector2)
	local camera = Workspace.CurrentCamera
	local folder = targetsFolder()
	if not camera or not folder then
		return
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character or Instance.new("Folder") }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
	local hand = localPlayer.Character and localPlayer.Character:FindFirstChild("RightHand")
	local from = if hand and hand:IsA("BasePart") then hand.Position else ray.Origin
	tracer(from, if result then result.Position else ray.Origin + ray.Direction * 60)
	local hit = result and result.Instance
	local target = hit and hit.Name == "Face" and hit:FindFirstAncestorOfClass("Model")
	local index = target and target:GetAttribute("Index")
	if target and target.Parent == folder and typeof(index) == "number" then
		shotRemote:FireServer(index)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not shooting() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		shootAt(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

local wasShooting = false
localPlayer:GetAttributeChangedSignal(PlayerAttr.RangeUntil):Connect(function()
	local active = shooting()
	if wasShooting and not active then
		showResult(("RANGE: %d HITS!"):format(number(PlayerAttr.RangeScore)))
	end
	wasShooting = active
end)

---------------------------------------------------------------- полоса препятствий

localPlayer:GetAttributeChangedSignal(PlayerAttr.CourseLast):Connect(function()
	local seconds = number(PlayerAttr.CourseLast)
	if seconds > 0 then
		showResult(("TIME: %.1fS"):format(seconds))
	end
end)

---------------------------------------------------------------- надпись сверху

RunService.RenderStepped:Connect(function()
	local text = ""
	if shooting() then
		text = ("RANGE: %d HITS • %dS"):format(number(PlayerAttr.RangeScore), math.max(0, math.ceil(number(PlayerAttr.RangeUntil) - now())))
	elseif os.clock() < resultUntil then
		text = resultText
	else
		local started = number(PlayerAttr.CourseStartedAt)
		if started > 0 and now() - started <= Config.Hub.Course.MaxSeconds then
			text = ("COURSE: %.1fS"):format(now() - started)
		end
	end
	status.Visible = text ~= ""
	if text ~= "" then
		status.Text = text
	end
end)
