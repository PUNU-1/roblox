-- Ставит модель из ReplicatedStorage/Models по имени.
-- Если друг ещё не сделал модель, ставит заглушку из блоков с тем же именем.
-- Договорённость: origin модели (pivot) внизу по центру, перед модели смотрит в -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type StubPart = {
	size: Vector3,
	offset: CFrame, -- относительно origin модели
	color: Color3,
	material: Enum.Material?,
}

local ModelLibrary = {}

local function anchorAll(root: Instance)
	if root:IsA("BasePart") then
		root.Anchored = true
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function buildStub(name: string, parts: { StubPart }): Model
	local model = Instance.new("Model")
	model.Name = name
	for index, spec in parts do
		local part = Instance.new("Part")
		part.Name = "Stub" .. index
		part.Size = spec.size
		part.CFrame = spec.offset
		part.Color = spec.color
		part.Material = spec.material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

function ModelLibrary.place(name: string, pivot: CFrame, stubParts: { StubPart }, parent: Instance): PVInstance
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local template = folder and folder:FindFirstChild(name)

	local instance: PVInstance
	if template and template:IsA("PVInstance") then
		instance = (template:Clone() :: any) :: PVInstance
	else
		instance = buildStub(name, stubParts)
	end

	instance.Name = name
	anchorAll(instance)
	instance:PivotTo(pivot)
	instance.Parent = parent
	return instance
end

return ModelLibrary
