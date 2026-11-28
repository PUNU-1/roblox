-- Умная кнопка на телефоне (этап 8, блок Q, решение 102): одна большая круглая кнопка справа внизу, левее прыжка Roblox.
-- Сама становится тем, что сейчас можно сделать, по приоритету:
--   1) рядом подсказка ProximityPrompt (арест, ремонт камеры и щитка, подъём друга, покупка, рубильник, Check ID) —
--      кнопка делает её действие: удержание — prompt:InputHoldBegin() / InputHoldEnd(), полоска внизу круга.
--      Сами подсказки Roblox на телефоне спрятаны (Style = Custom), чтобы не было двух кнопок;
--   2) в руках огнестрел и идёт налёт — FIRE; 3) в руках шокер и ночь — TASER; 4) в руках аптечка — HEAL
--      (2–4 даёт Weapons.client через Mobile.setWeaponAction);
--   5) иначе кнопка бледная и ничего не делает.
-- Только на телефоне (Theme.touchOnly). Сервер проверяет всё, как при нажатии F или мыши.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Mobile = require(UI:WaitForChild("Mobile"))
local PixelWindow = require(UI:WaitForChild("PixelWindow"))

if not Mobile.enabled then
	return
end

local PlayerAttr = GameState.PlayerAttr
local localPlayer = Players.LocalPlayer

---------------------------------------------------------------- подсказки Roblox прячем, свои считаем

local function hidePrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end
for _, descendant in Workspace:GetDescendants() do
	hidePrompt(descendant)
end
Workspace.DescendantAdded:Connect(hidePrompt)

-- Подсказки, которые Roblox сейчас «показывает» этому игроку (расстояние, видимость, Enabled — решает Roblox)
local shown: { [ProximityPrompt]: boolean } = {}
ProximityPromptService.PromptShown:Connect(function(prompt)
	shown[prompt] = true
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	shown[prompt] = nil
end)

local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	elseif parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function nearestPrompt(): ProximityPrompt?
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local from = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil
	local best: ProximityPrompt? = nil
	local bestDistance = math.huge
	for prompt in shown do
		if not prompt.Parent or not prompt.Enabled then
			shown[prompt] = nil
			continue
		end
		local position = promptPosition(prompt)
		local distance = if from and position then (position - from).Magnitude else 0
		if distance < bestDistance then
			best = prompt
			bestDistance = distance
		end
	end
	return best
end

local function promptIcon(prompt: ProximityPrompt): string
	local text = string.lower(prompt.ActionText)
	for _, rule in Config.Mobile.PromptIcons do
		if string.find(text, rule.Word, 1, true) then
			return rule.Icon
		end
	end
	return "KeyF"
end

---------------------------------------------------------------- кнопка

local holdingPrompt: ProximityPrompt? = nil
local holdStarted = 0
local holdingAction: Mobile.Action? = nil
local current: ProximityPrompt | Mobile.Action | nil = nil

local function release()
	local prompt = holdingPrompt
	if prompt then
		holdingPrompt = nil
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
	local action = holdingAction
	if action then
		holdingAction = nil
		action.release()
	end
end

local function press()
	release()
	local target = current
	if typeof(target) == "Instance" then
		local prompt = target :: ProximityPrompt
		holdingPrompt = prompt
		holdStarted = os.clock()
		pcall(function()
			prompt:InputHoldBegin()
		end)
	elseif target ~= nil then
		local action = target :: Mobile.Action
		holdingAction = action
		action.press()
	end
end

local button = Mobile.roundButton({
	name = "SmartButton",
	slot = "Smart",
	onPress = press,
	onRelease = release,
})
button.root.Visible = false
button.setActive(false)

local function onShift(): boolean
	local phase = GameState.phase()
	return localPlayer:GetAttribute(PlayerAttr.InRound) == true and (phase == GameState.Phase.Day or phase == GameState.Phase.Night)
end

local function blocked(): boolean
	return localPlayer:GetAttribute(PlayerAttr.ViewingCameras) == true
		or localPlayer:GetAttribute(PlayerAttr.Spectating) == true
		or GameState.phase() == GameState.Phase.Results
		or PixelWindow.anyOpen()
end

RunService.Heartbeat:Connect(function()
	-- Удерживаемая подсказка пропала (вор убежал, друг встал) — отпускаем
	local holding = holdingPrompt
	if holding and (not shown[holding] or not holding.Enabled) then
		release()
	end

	local prompt = holdingPrompt or nearestPrompt()
	local action: Mobile.Action? = nil
	if not prompt then
		action = holdingAction or Mobile.weaponAction()
	end
	local hide = blocked()
	if hide then
		release()
		prompt, action = nil, nil
	end
	current = prompt or action

	button.setVisible(not hide and (onShift() or current ~= nil))
	if prompt then
		button.setActive(true)
		button.setIcon(promptIcon(prompt))
		button.setLabel(Theme.pixelText(string.upper(prompt.ActionText)))
		local duration = prompt.HoldDuration
		if holdingPrompt == prompt and duration > 0 then
			button.setProgress((os.clock() - holdStarted) / duration)
		else
			button.setProgress(nil)
		end
	elseif action then
		button.setActive(true)
		button.setIcon(action.icon)
		button.setLabel(action.label)
		button.setProgress(nil)
	else
		button.setActive(false)
		button.setIcon(nil)
		button.setLabel("")
		button.setProgress(nil)
	end
end)

localPlayer.CharacterAdded:Connect(function()
	release()
	table.clear(shown)
end)
