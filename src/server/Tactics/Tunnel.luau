-- План «Подкоп» (Tunnel): все воры волны — Шахтёры. Они копают под полом и вылезают у разных экспонатов
-- (каждый выбирает экспонат, у которого ещё никто не копает, подальше от охраны).

local Tunnel = {}

Tunnel.name = "Tunnel"
Tunnel.allowLure = false

function Tunnel.canRun(_ctx: any, _api: any): boolean
	return true
end

function Tunnel.start(ctx: any, api: any)
	for index = 1, ctx.size do
		api.spawn(ctx, { kind = "Miner" }, api.stagger(index))
	end
	ctx.done = true
end

return Tunnel
