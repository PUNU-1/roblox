-- План «Клещи» (Pincer): две группы входят одновременно через противоположные двери.

local Pincer = {}

Pincer.name = "Pincer"
Pincer.allowLure = true

function Pincer.canRun(_ctx: any, api: any): boolean
	return api.entranceCount() >= 2
end

function Pincer.start(ctx: any, api: any)
	local first = api.entrance()
	if not first then
		ctx.done = true
		return
	end
	local second = api.farthestFrom(first.Position, { first }) or first
	local firstGroup = math.ceil(ctx.size / 2)
	for index = 1, ctx.size do
		local entrance = if index <= firstGroup then first else second
		-- Обе группы входят в одну и ту же секунду, внутри группы — почти вплотную
		local delay = if index <= firstGroup then (index - 1) * 0.6 else (index - firstGroup - 1) * 0.6
		api.spawn(ctx, { kind = api.pickKind(ctx, true), entrance = entrance }, delay)
	end
	ctx.done = true
end

return Pincer
