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
	SetRole = "SetRole", -- (role: string) выбор роли в лобби
	SetReady = "SetReady", -- (ready: boolean) кнопка READY
	RequestCameras = "RequestCameras", -- (open: boolean) открыть/закрыть телефон или пульт
	MarkThief = "MarkThief", -- (thief: Model) метка оператора на вора
	QuickPhrase = "QuickPhrase", -- (index: number) готовая фраза
	VoteCast = "VoteCast", -- (voteId: number, yes: boolean) голос за опоздавшего

	-- сервер -> клиенты
	PhraseShown = "PhraseShown", -- (userId: number, index: number)
	Banner = "Banner", -- (text: string, kind: string) крупная надпись вверху экрана
	NightResults = "NightResults", -- (results: table) экран итога
	VoteRequest = "VoteRequest", -- (voteId: number, name: string, seconds: number) пустить ли опоздавшего
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
