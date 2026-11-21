-- Волна без плана (ночь 1, или когда ни один план не подходит): все воры волны сразу, каждый через свою
-- дверь без охраны. Если вся охрана у Моны Лизы, WaveService сам делает первого вора «шумным» (Lure),
-- а остальные ждут во входном холле, пока охрана не уйдёт от картины.

local Basic = {}

Basic.name = "Basic"
Basic.allowLure = true

function Basic.canRun(_ctx: any, _api: any): boolean
	return true
end

function Basic.start(ctx: any, api: any)
	local used = {}
	for index = 1, ctx.size do
		local entrance = api.entrance(used)
		if entrance then
			table.insert(used, entrance)
		end
		api.spawn(ctx, { kind = api.pickKind(ctx, true), entrance = entrance }, api.stagger(index))
	end
	ctx.done = true
end

return Basic
