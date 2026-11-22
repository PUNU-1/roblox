-- План «Приманка» (Decoy): шумный вор хватает дешёвый экспонат подальше от Моны Лизы и громко бежит.
-- Настоящий вор (Тень, если она уже приходит) ждёт у другой двери и, как только приманка схватила
-- экспонат, тихо идёт к Моне Лизе.

local Decoy = {}

Decoy.name = "Decoy"
Decoy.allowLure = false

function Decoy.canRun(_ctx: any, api: any): boolean
	return api.hasCheapExhibit() and api.entranceCount() >= 2
end

function Decoy.start(ctx: any, api: any)
	local decoyDoor = api.entrance()
	if not decoyDoor then
		ctx.done = true
		return
	end
	local decoy = api.spawn(ctx, { kind = "Pickpocket", entrance = decoyDoor, target = "Cheap", loud = true, noFlee = true })
	local quietDoor = api.farthestFrom(decoyDoor.Position, { decoyDoor })
	api.spawn(ctx, {
		kind = if api.unlocked("Shadow") then "Shadow" else "Pickpocket",
		entrance = quietDoor,
		target = "Main",
		silent = true,
		hold = function()
			return api.carrying(decoy) or api.gone(decoy)
		end,
		holdTimeout = 45,
	})
	local used = { decoyDoor }
	if quietDoor then
		table.insert(used, quietDoor)
	end
	for index = 3, ctx.size do
		api.spawn(ctx, { kind = api.pickKind(ctx, true), entrance = api.entrance(used) }, api.stagger(index))
	end
	ctx.done = true
end

return Decoy
