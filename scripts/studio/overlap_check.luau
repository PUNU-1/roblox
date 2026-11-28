-- Проверка «ничего не наезжает» (этап 8, блок N). Не часть игры: Rojo эту папку не собирает.
-- Как запустить: Studio → Play → вставить весь файл в MCP execute_luau (datamodel "Server")
-- или в командную строку Studio на стороне сервера. Карта строится при запуске (MapBuilder), поэтому в Edit
-- пустой Workspace.Map ничего не покажет.
--
-- Для каждой модели декора (Map.Props, Map.Exhibits, Map.Pedestals) берётся её рамка (GetBoundingBox),
-- чуть уменьшенная (Shrink), и Workspace:GetPartBoundsInBox ищет чужие детали внутри: другие модели,
-- стены и двери. Полы, ковры и плитка (тонкие детали ниже низа модели) не считаются.
-- Результат — список пар «модель — что задела». Пустой список — всё стоит ровно.
-- REGION: проверять только модели, чей центр внутри этого прямоугольника XZ (nil — вся карта).

local REGION: { minX: number, maxX: number, minZ: number, maxZ: number }? = { minX = -60, maxX = 60, minZ = -60, maxZ = 60 }
local SHRINK = 0.15 -- рамка меньше на столько с каждой стороны: касание — не пересечение
local FLOOR_SLACK = 0.25 -- деталь с верхом не выше низа модели + столько — пол, не пересечение

local Workspace = game:GetService("Workspace")
local map = Workspace:FindFirstChild("Map")
if not map then
	return "Нет Workspace.Map — запусти Play и выполняй на сервере"
end

-- Модель верхнего уровня в одной из папок декора, которой принадлежит деталь (или nil).
local folders = {}
for _, name in { "Props", "Exhibits", "Pedestals" } do
	local folder = map:FindFirstChild(name)
	if folder then
		folders[folder] = true
	end
end
local function ownerOf(part: Instance): Instance?
	local node: Instance? = part
	while node and node.Parent do
		if folders[node.Parent] then
			return node
		end
		node = node.Parent
	end
	return nil
end

local items = {}
for folder in folders do
	for _, child in folder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			local cframe, size
			if child:IsA("Model") then
				cframe, size = child:GetBoundingBox()
			else
				cframe, size = child.CFrame, child.Size
			end
			local p = cframe.Position
			if not REGION or (p.X >= REGION.minX and p.X <= REGION.maxX and p.Z >= REGION.minZ and p.Z <= REGION.maxZ) then
				table.insert(items, { instance = child, cframe = cframe, size = size })
			end
		end
	end
end

local params = OverlapParams.new()
params.RespectCanCollide = false
local seen = {}
local lines = {}
for _, item in items do
	local inner = Vector3.new(
		math.max(0.05, item.size.X - 2 * SHRINK),
		math.max(0.05, item.size.Y - 2 * SHRINK),
		math.max(0.05, item.size.Z - 2 * SHRINK)
	)
	params.FilterDescendantsInstances = { item.instance }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bottom = item.cframe.Position.Y - item.size.Y / 2
	for _, part in Workspace:GetPartBoundsInBox(item.cframe, inner, params) do
		local top = part.Position.Y + part.Size.Y / 2
		local isFloor = top <= bottom + FLOOR_SLACK
		local isMarker = part.Transparency >= 1 and not part.CanCollide
		local other = ownerOf(part)
		local isCharacter = part:FindFirstAncestorOfClass("Model") and part:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") ~= nil
		if not isFloor and not isMarker and not isCharacter and other ~= item.instance then
			local otherName = if other then other:GetFullName() else part:GetFullName()
			local key = item.instance:GetFullName() .. " | " .. otherName
			local back = otherName .. " | " .. item.instance:GetFullName()
			if not seen[key] and not seen[back] then
				seen[key] = true
				local p = item.cframe.Position
				table.insert(lines, ("%s (%.1f, %.1f)  ×  %s"):format(item.instance.Name, p.X, p.Z, otherName))
			end
		end
	end
end

if #lines == 0 then
	return ("Проверено моделей: %d. Пересечений нет."):format(#items)
end
return ("Проверено моделей: %d. Пересечений: %d\n%s"):format(#items, #lines, table.concat(lines, "\n"))
