-- Мона Лиза: висит на стене, её снимает вор, несёт над головой, после ареста она возвращается.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))
local ModelLibrary = require(script.Parent:WaitForChild("ModelLibrary"))

local PaintingService = {}

local painting: PVInstance? = nil
local wallCFrame = CFrame.identity
local carrier: Model? = nil
local stealer: Model? = nil
local originalCollide: { [BasePart]: boolean } = {}

function PaintingService.init(map: Instance)
	local exhibits = map:FindFirstChild(MapSchema.Exhibits)
	local spot = map:FindFirstChild(MapSchema.PaintingSpot, true)
	if exhibits then
		local found = exhibits:FindFirstChild(MapSchema.Models.MonaLisa)
		if found and found:IsA("PVInstance") then
			painting = found
			ModelLibrary.forEachPart(found, function(part)
				originalCollide[part] = part.CanCollide
			end)
		end
	end
	if spot and spot:IsA("BasePart") then
		wallCFrame = spot.CFrame
	elseif painting then
		wallCFrame = painting:GetPivot()
	end
	if not painting then
		warn("[PaintingService] На карте нет Моны Лизы")
	end
	GameState.set(GameState.Attr.PaintingStolen, false)
end

-- Точка перед картиной, куда подходит вор.
function PaintingService.standPosition(): Vector3
	local position = wallCFrame.Position + wallCFrame.LookVector * Config.Thief.StandOffset
	return Vector3.new(position.X, 3, position.Z)
end

function PaintingService.wallPosition(): Vector3
	return wallCFrame.Position
end

function PaintingService.isOnWall(): boolean
	return carrier == nil
end

function PaintingService.getCarrier(): Model?
	return carrier
end

function PaintingService.getStealer(): Model?
	return stealer
end

-- Только один вор может снимать картину за раз.
function PaintingService.tryStartSteal(thief: Model): boolean
	if carrier or (stealer and stealer ~= thief and stealer.Parent) then
		return false
	end
	stealer = thief
	return true
end

function PaintingService.cancelSteal(thief: Model)
	if stealer == thief then
		stealer = nil
	end
end

-- Вор снял картину: она прилипает над его головой.
function PaintingService.take(thief: Model): boolean
	local head = thief:FindFirstChild("Head")
	if not (painting and head and head:IsA("BasePart")) or carrier then
		return false
	end
	stealer = nil
	carrier = thief
	local offset = Config.Painting.CarryOffset
	-- Картина остаётся в папке Exhibits (чтобы не пропала вместе с вором), но приварена к его голове
	ModelLibrary.weldTo(painting, head, head.CFrame * CFrame.new(offset.X, offset.Y, offset.Z))
	GameState.set(GameState.Attr.PaintingStolen, true)
	return true
end

-- Картина возвращается на стену (после ареста вора или в начале ночи).
function PaintingService.returnToWall()
	stealer = nil
	carrier = nil
	if not painting then
		return
	end
	ModelLibrary.forEachPart(painting, function(part)
		for _, child in part:GetChildren() do
			if child:IsA("WeldConstraint") and child.Name == "CarryWeld" then
				child:Destroy()
			end
		end
		part.Anchored = true
		part.Massless = false
		part.CanCollide = if originalCollide[part] ~= nil then originalCollide[part] else true
		part.CanQuery = true
		part.CanTouch = true
	end)
	painting:PivotTo(wallCFrame)
	GameState.set(GameState.Attr.PaintingStolen, false)
end

return PaintingService
