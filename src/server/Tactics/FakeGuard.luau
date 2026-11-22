-- План «Фальшивый охранник» (Fake Guard): вор одет точно как один из игроков смены (его аватар и форма
-- охраны, его ник над головой, фонарик). Ходит спокойно, не убегает и крадёт, когда рядом никто не смотрит.
-- Остальные воры волны входят через другие двери. Отличить его можно кнопкой Check ID (CatchService).

local FakeGuard = {}

FakeGuard.name = "FakeGuard"
FakeGuard.allowLure = true

function FakeGuard.canRun(_ctx: any, api: any): boolean
	return api.randomGuardPlayer() ~= nil
end

function FakeGuard.start(ctx: any, api: any)
	local player = api.randomGuardPlayer()
	local door = api.entrance()
	if player and door then
		api.spawn(ctx, { kind = "FakeGuard", disguise = player, entrance = door, noFlee = true })
	end
	local used = {}
	if door then
		table.insert(used, door)
	end
	for index = 2, ctx.size do
		local entrance = api.entrance(used)
		if entrance then
			table.insert(used, entrance)
		end
		api.spawn(ctx, { kind = api.pickKind(ctx, true), entrance = entrance }, api.stagger(index))
	end
	ctx.done = true
end

return FakeGuard
