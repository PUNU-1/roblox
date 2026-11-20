--!strict
-- Единый список всех RemoteEvent / RemoteFunction.
-- Сервер создаёт их при первом require, клиент ждёт появления.
-- Аргументы всегда проверяются на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	"PhaseChanged", -- сервер -> клиенты: смена фазы
	"ReadyChanged", -- клиент -> сервер: нажал «Готов»
	"RoleChosen", -- клиент -> сервер: выбор роли
	"SwitchCamera", -- клиент -> сервер: намерение переключить камеру
	"NightResults", -- сервер -> клиенты: итог ночи
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
