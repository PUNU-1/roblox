--!strict
-- Единый список всех RemoteEvent.
-- Сервер создаёт их при первом require, клиент ждёт появления.
-- Аргументы от клиента сервер ВСЕГДА проверяет сам: клиенту не доверяем.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

local NAMES: { [string]: string } = {
	-- клиент -> сервер
	SetRole = "SetRole", -- (role: string) выбор класса в лобби (карточки или клавиши 1–5), блок 5
	RequestCameras = "RequestCameras", -- (open: boolean) открыть/закрыть телефон или пульт
	MarkThief = "MarkThief", -- (thief: Model) метка оператора на вора
	QuickPhrase = "QuickPhrase", -- (index: number) готовая фраза
	VoteCast = "VoteCast", -- (voteId: number, yes: boolean) голос за опоздавшего
	-- блок 4: оружие (всё проверяет WeaponService)
	Equip = "Equip", -- (slot: number) 1 — основное, 2 — пистолет, 3 — шокер, 4 — аптечка; то же место ещё раз — убрать
	Fire = "Fire", -- (weapon: string, origin: Vector3, direction: Vector3) выстрел: только направление, луч пускает сервер
	Reload = "Reload", -- () перезарядить оружие в руках
	UseMedkit = "UseMedkit", -- () аптечка в руках — лечиться
	SetStance = "SetStance", -- (crouch: boolean, lean: number) присед и наклон
	-- блок 5: умения классов (всё проверяет AbilityService)
	UseAbility = "UseAbility", -- (name: string) "Dash" — рывок патруля, "Sensor" — датчик техника
	-- блок 6: хаб и конец забега
	PadAction = "PadAction", -- (action: string, value: any) хаб, создатель круга: "Start" — старт сейчас, "FriendsOnly" (value: boolean)
	GameOverChoice = "GameOverChoice", -- (choice: string) музей, конец забега: "PlayAgain" | "Lobby"

	-- сервер -> клиенты
	PhraseShown = "PhraseShown", -- (userId: number, index: number)
	Banner = "Banner", -- (text: string, kind: string) крупная надпись вверху экрана
	NightResults = "NightResults", -- (results: table) экран итога
	VoteRequest = "VoteRequest", -- (voteId: number, name: string, seconds: number) пустить ли опоздавшего
	Hurt = "Hurt", -- (from: Vector3?, amount: number) охранника ранили: с какой стороны вспыхнуть краю экрана
	ShotFx = "ShotFx", -- (shooter: Instance, weapon: string, origin: Vector3, ends: { Vector3 }, hits: { boolean }) выстрел для картинки
	HitConfirm = "HitConfirm", -- (kind: string) стрелку: попал ("hit"), в голову ("head"), грабитель упал ("ko"), шокер ("stun")
}
Remotes.Names = NAMES

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.get(name: string): RemoteEvent
	local remote = folder:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "Нет такого RemoteEvent: " .. name)
	return remote
end

return Remotes
