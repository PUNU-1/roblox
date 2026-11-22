-- Голосование за опоздавшего (решение 52). Игрок зашёл, когда команда уже играет:
-- участникам приходит «Let <имя> join?». «Да» от половины или больше — он входит с ближайшего дня.
-- Иначе ждёт в комнате охраны до следующей игры. В игре не больше Config.Players.Max игроков.
-- Статус опоздавшего — атрибут игрока JoinStatus: Voting | Approved | Rejected | Full.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = script.Parent
local RoleService = require(Server:WaitForChild("RoleService"))

local VoteService = {}

type Vote = {
	id: number,
	candidate: Player,
	voters: { Player },
	answers: { [Player]: boolean },
}

local runActive = false
local autoApprove: ((Player) -> boolean)? = nil -- блок 6: своего из команды хаба пускаем без голосования
local queue: { Player } = {}
local current: Vote? = nil
local nextId = 0

local function setStatus(player: Player, status: string?)
	player:SetAttribute(GameState.PlayerAttr.JoinStatus, status)
end

local function full(): boolean
	local count = #RoleService.participants()
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(GameState.PlayerAttr.JoinStatus) == "Approved" then
			count += 1
		end
	end
	return count >= Config.Players.Max
end

local startNext: () -> ()

local function finish(vote: Vote)
	if current ~= vote then
		return
	end
	current = nil
	local yes = 0
	for _, voter in vote.voters do
		if vote.answers[voter] == true then
			yes += 1
		end
	end
	local candidate = vote.candidate
	if candidate.Parent then
		-- «Да» от половины или больше
		local approved = yes * 2 >= #vote.voters
		setStatus(candidate, if approved then "Approved" else "Rejected")
		local text = if approved
			then ("%s WILL JOIN TOMORROW"):format(string.upper(candidate.DisplayName))
			else ("%s WAS NOT LET IN"):format(string.upper(candidate.DisplayName))
		Remotes.get(Remotes.Names.Banner):FireAllClients(text, "info")
	end
	startNext()
end

startNext = function()
	if current or not runActive then
		return
	end
	while #queue > 0 do
		local candidate = table.remove(queue, 1) :: Player
		if candidate.Parent and not RoleService.isParticipant(candidate) then
			if full() then
				setStatus(candidate, "Full")
			else
				local voters = RoleService.participants()
				if #voters == 0 then
					return
				end
				nextId += 1
				local vote: Vote = { id = nextId, candidate = candidate, voters = voters, answers = {} }
				current = vote
				setStatus(candidate, "Voting")
				for _, voter in voters do
					Remotes.get(Remotes.Names.VoteRequest):FireClient(voter, vote.id, candidate.DisplayName, Config.Players.VoteSeconds)
				end
				task.delay(Config.Players.VoteSeconds, function()
					finish(vote)
				end)
				return
			end
		end
	end
end

local function onVote(player: Player, id: any, yes: any)
	local vote = current
	if not vote or typeof(id) ~= "number" or id ~= vote.id or typeof(yes) ~= "boolean" then
		return
	end
	if not table.find(vote.voters, player) or vote.answers[player] ~= nil then
		return
	end
	vote.answers[player] = yes
	local answered = 0
	for _ in vote.answers do
		answered += 1
	end
	if answered >= #vote.voters then
		finish(vote)
	end
end

-- GameLoop: забег начался / закончился.
function VoteService.setRunActive(active: boolean)
	runActive = active
	if active then
		-- Кто остался в комнате охраны при старте (больше 5 игроков), тоже в очереди:
		-- увидит «команда полная», а если кто-то уйдёт — команда проголосует за него
		for _, player in Players:GetPlayers() do
			if not RoleService.isParticipant(player) and not table.find(queue, player) then
				table.insert(queue, player)
			end
		end
		startNext()
	else
		current = nil
		table.clear(queue)
		for _, player in Players:GetPlayers() do
			setStatus(player, nil)
		end
	end
end

-- Начало дня: одобренные опоздавшие входят в игру. Возвращает, кого добавили.
function VoteService.admitApproved(): { Player }
	local admitted = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(GameState.PlayerAttr.JoinStatus) == "Approved" and #RoleService.participants() < Config.Players.Max then
			setStatus(player, nil)
			RoleService.addToRound(player)
			table.insert(admitted, player)
		end
	end
	return admitted
end

-- Блок 6 (HubLink): кого пускать без голосования — игрок своей команды из хаба, который долетел позже.
function VoteService.setAutoApprove(check: (Player) -> boolean)
	autoApprove = check
end

function VoteService.init()
	Remotes.get(Remotes.Names.VoteCast).OnServerEvent:Connect(onVote)
	Players.PlayerAdded:Connect(function(player)
		if runActive then
			local check = autoApprove
			if check and check(player) and not full() then
				-- Свой из хаба: входит с ближайшего дня, команда не голосует
				setStatus(player, "Approved")
				Remotes.get(Remotes.Names.Banner):FireAllClients(("%s WILL JOIN TOMORROW"):format(string.upper(player.DisplayName)), "info")
				return
			end
			table.insert(queue, player)
			startNext()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
		local vote = current
		if vote and vote.candidate == player then
			current = nil
			startNext()
		end
		-- Из команды ушёл игрок — освободилось место: голосуем за тех, кому сказали «команда полная»
		if runActive and RoleService.isParticipant(player) then
			task.defer(function()
				for _, waiting in Players:GetPlayers() do
					if waiting:GetAttribute(GameState.PlayerAttr.JoinStatus) == "Full" and not table.find(queue, waiting) then
						table.insert(queue, waiting)
					end
				end
				startNext()
			end)
		end
	end)
end

return VoteService
