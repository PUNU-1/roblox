-- Ставит модель из ReplicatedStorage/Models по имени.
-- Если друг ещё не сделал модель, ставит заглушку из блоков с тем же именем.
-- Договорённость: origin модели (pivot) внизу по центру, перед модели смотрит в -Z.
-- Скрипты внутри моделей запрещены: если они там есть, удаляем их и пишем предупреждение.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type StubPart = {
	size: Vector3,
	offset: CFrame, -- относительно origin модели (для аксессуара — относительно Handle)
	color: Color3,
	material: Enum.Material?,
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
}

local ModelLibrary = {}

local function findTemplate(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Models")
	return folder and folder:FindFirstChild(name)
end

local function stripScripts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			warn(("[ModelLibrary] В модели %s был скрипт %s — удалён. В моделях скриптов быть не должно."):format(root.Name, descendant.Name))
			descendant:Destroy()
		end
	end
end

local function forEachPart(root: Instance, callback: (BasePart) -> ())
	if root:IsA("BasePart") then
		callback(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end
ModelLibrary.forEachPart = forEachPart

local function newStubPart(spec: StubPart, index: number): Part
	local part = Instance.new("Part")
	part.Name = spec.name or ("Stub" .. index)
	part.Size = spec.size
	part.CFrame = spec.offset
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	if spec.shape then
		part.Shape = spec.shape
	end
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildStub(name: string, parts: { StubPart }): Model
	local model = Instance.new("Model")
	model.Name = name
	for index, spec in parts do
		newStubPart(spec, index).Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

-- Модель друга или заглушка, ещё нигде не стоит и не закреплена.
function ModelLibrary.build(name: string, stubParts: { StubPart }): PVInstance
	local template = findTemplate(name)
	local instance: PVInstance
	if template and template:IsA("PVInstance") then
		instance = (template:Clone() :: any) :: PVInstance
		stripScripts(instance)
	else
		instance = buildStub(name, stubParts)
	end
	instance.Name = name
	return instance
end

-- Ставит закреплённую модель в мир.
function ModelLibrary.place(name: string, pivot: CFrame, stubParts: { StubPart }, parent: Instance): PVInstance
	local instance = ModelLibrary.build(name, stubParts)
	forEachPart(instance, function(part)
		part.Anchored = true
	end)
	instance:PivotTo(pivot)
	instance.Parent = parent
	return instance
end

-- Аксессуар друга или заглушка. Первая деталь заглушки становится Handle,
-- остальные привариваются к ней. attachmentName — к какой точке тела крепится.
function ModelLibrary.accessory(name: string, stubParts: { StubPart }, attachmentName: string): Accessory
	local template = findTemplate(name)
	local accessory: Accessory
	if template and template:IsA("Accessory") then
		accessory = template:Clone()
		stripScripts(accessory)
	else
		accessory = Instance.new("Accessory")
		local handle: Part? = nil
		for index, spec in stubParts do
			local part = newStubPart(spec, index)
			if not handle then
				part.Name = "Handle"
				part.CFrame = CFrame.identity
				part.Parent = accessory
				handle = part
				local attachment = Instance.new("Attachment")
				attachment.Name = attachmentName
				attachment.Parent = part
			else
				part.CFrame = spec.offset
				part.Parent = handle
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	accessory.Name = name
	forEachPart(accessory, function(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end)
	return accessory
end

-- Приваривает модель к детали персонажа: модель встаёт в cframe и двигается вместе с ней.
function ModelLibrary.weldTo(instance: PVInstance, target: BasePart, cframe: CFrame)
	instance:PivotTo(cframe)
	forEachPart(instance, function(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "CarryWeld"
		weld.Part0 = target
		weld.Part1 = part
		weld.Parent = part
	end)
end

return ModelLibrary
