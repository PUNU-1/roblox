-- План «Блэкаут» (Blackout): Светорез входит через дверь ближе к служебному коридору и вырубает у щитка
-- POWER свет и камеры во всём музее. Как только стало темно, входят Тени (или обычные воры).

local Server = script.Parent.Parent
local BlackoutService = require(Server:WaitForChild("BlackoutService"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Blackout = {}

Blackout.name = "Blackout"
Blackout.allowLure = false

function Blackout.canRun(_ctx: any, _api: any): boolean
	return not BlackoutService.isOut() and BlackoutService.standPoint() ~= nil
end

function Blackout.start(ctx: any, api: any)
	local fuse = BlackoutService.standPoint() :: Vector3
	local door = api.nearestTo(fuse)
	ctx.data.cutter = api.spawn(ctx, { kind = "Cutter", entrance = door })
	ctx.data.started = api.now()
end

function Blackout.update(ctx: any, api: any)
	local cutter = ctx.data.cutter
	if not (BlackoutService.isOut() or api.gone(cutter) or api.now() - ctx.data.started > Config.Waves.FollowTimeout) then
		return
	end
	-- Темно: в темноте работают Тени, каждая через свою дверь без охраны
	local used = {}
	for index = 2, ctx.size do
		local entrance = api.entrance(used)
		if entrance then
			table.insert(used, entrance)
		end
		local kind = if api.unlocked("Shadow") then "Shadow" else api.pickKind(ctx, true)
		api.spawn(ctx, { kind = kind, entrance = entrance }, api.stagger(index))
	end
	ctx.done = true
end

return Blackout
