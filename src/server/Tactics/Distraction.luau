-- План «Отвлечение» (Distraction): Громила разбивает витрину вдали от охраны (сирена, GLASS ALARM — место).
-- Пока охрана бежит туда, к Моне Лизе идёт второй вор: Стекольщик спускается с крыши, а если он ещё
-- не приходит — тихий вор (Тень или Карманник) через дверь на другой стороне. Оба ждут, пока витрина разбита.

local Server = script.Parent.Parent
local HeistFx = require(Server:WaitForChild("HeistFx"))

local Distraction = {}

Distraction.name = "Distraction"
Distraction.allowLure = false

function Distraction.canRun(_ctx: any, api: any): boolean
	return HeistFx.pickCase(api.guards()) ~= nil
end

function Distraction.start(ctx: any, api: any)
	local case = HeistFx.pickCase(api.guards())
	local bruteDoor = if case then api.nearestTo(case.stand) else api.entrance()
	local brute = api.spawn(ctx, { kind = "Brute", entrance = bruteDoor, task = "Smash", noFlee = true })
	local function smashed(): boolean
		return api.taskDone(brute)
	end
	local used = {}
	if bruteDoor then
		table.insert(used, bruteDoor)
	end
	if api.unlocked("Glazier") and HeistFx.skylight() then
		-- Стекольщик режет стекло сразу, а спускается, когда витрина разбита и у картины пусто
		api.spawn(ctx, { kind = "Glazier", target = "Main", hold = smashed })
	else
		local quietDoor = if bruteDoor then api.farthestFrom(bruteDoor.Position, used) else api.entrance(used)
		if quietDoor then
			table.insert(used, quietDoor)
		end
		api.spawn(ctx, {
			kind = if api.unlocked("Shadow") then "Shadow" else "Pickpocket",
			entrance = quietDoor,
			target = "Main",
			silent = true,
			hold = function()
				return smashed() and api.paintingClear()
			end,
			holdTimeout = 40,
		})
	end
	for index = 3, ctx.size do
		local entrance = api.entrance(used)
		if entrance then
			table.insert(used, entrance)
		end
		api.spawn(ctx, { kind = api.pickKind(ctx, true), entrance = entrance }, api.stagger(index))
	end
	ctx.done = true
end

return Distraction
