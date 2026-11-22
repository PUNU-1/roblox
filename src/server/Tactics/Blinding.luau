-- План «Ослепление» (Blinding): Взломщик входит через дверь без охраны и ломает камеры со своей стороны
-- (до Config.Plans.Blinding.Cameras ближайших к этой двери). Сразу после этого оттуда же идут Тени
-- (или обычные воры, если Тени ещё не приходят) — камеры этой стороны их уже не видят.

local Server = script.Parent.Parent
local CameraService = require(Server:WaitForChild("CameraService"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Settings = Config.Plans.Blinding

local Blinding = {}

Blinding.name = "Blinding"
Blinding.allowLure = false

-- Работающие камеры рядом с дверью, ближние первыми.
local function camerasNear(position: Vector3): { BasePart }
	local list = CameraService.workingNear(position, Settings.Radius)
	while #list > Settings.Cameras do
		table.remove(list)
	end
	return list
end

function Blinding.canRun(_ctx: any, api: any): boolean
	for _, entrance in api.entrances() do
		if #camerasNear(entrance.Position) > 0 then
			return true
		end
	end
	return false
end

function Blinding.start(ctx: any, api: any)
	-- Дверь без охраны, у которой есть что ломать
	local used = {}
	local door, cameras = nil, {}
	for _ = 1, 4 do
		local candidate = api.entrance(used)
		if not candidate then
			break
		end
		table.insert(used, candidate)
		local list = camerasNear(candidate.Position)
		if #list > 0 then
			door, cameras = candidate, list
			break
		end
	end
	if not door then
		door = api.entrance()
	end
	ctx.data.door = door
	ctx.data.breaker = api.spawn(ctx, { kind = "Breaker", entrance = door, task = "Camera", cameras = cameras })
	ctx.data.started = api.now()
end

function Blinding.update(ctx: any, api: any)
	local breaker = ctx.data.breaker
	if not (api.taskDone(breaker) or api.gone(breaker) or api.now() - ctx.data.started > Config.Waves.FollowTimeout) then
		return
	end
	-- Камеры сломаны: остальные воры волны входят через ту же дверь
	local kind = if api.unlocked("Shadow") then "Shadow" else nil
	for index = 2, ctx.size do
		api.spawn(ctx, { kind = kind or api.pickKind(ctx, true), entrance = ctx.data.door }, (index - 2) * 0.8)
	end
	ctx.done = true
end

return Blinding
