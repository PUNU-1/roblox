-- Ставит модель из ReplicatedStorage/Models по имени.
-- Если друг ещё не сделал модель, ставит заглушку из блоков с тем же именем.
-- Договорённость: origin модели (pivot) внизу по центру, перед модели смотрит в -Z.
-- Скрипты внутри моделей запрещены: если они там есть, удаляем их и пишем предупреждение.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type StubPart = {
	size: Vector3,
	offset: CFrame, -- относительно origin модели (для аксессуара — относительно Handle)
	color: Color3,
	material: Enum.Material?,
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
	wedge: boolean?, -- клин (WedgePart): скос от верхнего заднего ребра к нижнему переднему
	cornerWedge: boolean?, -- угловой клин (CornerWedgePart) для фасок и угловых скосов
	sphere: boolean?, -- овал: шар, растянутый по размеру детали (SpecialMesh), для яиц, шлемов, планет
	collide: boolean?, -- false — сквозь деталь можно пройти (мелкие украшения)
	reflectance: number?, -- блеск поверхности (если не задан — подбирается по материалу)
}

local MATERIAL_REFLECTANCE: { [Enum.Material]: number } = {
	[Enum.Material.Metal] = 0.25,
	[Enum.Material.Glass] = 0.22,
	[Enum.Material.Marble] = 0.08,
	[Enum.Material.SmoothPlastic] = 0.04,
}

local ModelLibrary = {}

local function findTemplate(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Models")
	return folder and folder:FindFirstChild(name)
end

-- Есть ли готовая модель друга с таким именем.
function ModelLibrary.has(name: string): boolean
	return findTemplate(name) ~= nil
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

local function newStubPart(spec: StubPart, index: number): BasePart
	local part: BasePart
	if spec.wedge then
		part = Instance.new("WedgePart")
	elseif spec.cornerWedge then
		part = Instance.new("CornerWedgePart")
	else
		local block = Instance.new("Part")
		if spec.shape then
			block.Shape = spec.shape
		end
		part = block
	end
	part.Name = spec.name or ("Stub" .. index)
	part.Size = spec.size
	part.CFrame = spec.offset
	part.Color = spec.color
	local mat = spec.material or Enum.Material.SmoothPlastic
	part.Material = mat
	part.Reflectance = if spec.reflectance ~= nil then spec.reflectance else (MATERIAL_REFLECTANCE[mat] or 0)
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.collide == false then
		part.CanCollide = false
		part.CanTouch = false
	end
	if spec.sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
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
		local handle: BasePart? = nil
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
				-- Weld с явным C0, а не WeldConstraint: WeldConstraint запоминает положение деталей,
				-- когда аксессуар попадает в мир, а к этому времени Handle уже перенесён на голову
				local weld = Instance.new("Weld")
				weld.Part0 = handle
				weld.Part1 = part
				weld.C0 = spec.offset
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

-- Новые персонажи Roblox соединены суставами AnimationConstraint. Их положение приходит с сервера
-- вместе с физикой, и клиентская анимация (NpcAnimator) на них не держится. Меняем их на
-- классические Motor6D: у Motor6D свойство Transform локальное, каждый клиент двигает его сам.
local function useMotorJoints(model: Model)
	for _, joint in model:GetDescendants() do
		if joint:IsA("AnimationConstraint") then
			local a0, a1 = joint.Attachment0, joint.Attachment1
			local part0 = a0 and a0.Parent
			local part1 = a1 and a1.Parent
			if a0 and a1 and part0 and part0:IsA("BasePart") and part1 and part1:IsA("BasePart") then
				local motor = Instance.new("Motor6D")
				motor.Name = joint.Name
				motor.Part0 = part0
				motor.Part1 = part1
				motor.C0 = a0.CFrame
				motor.C1 = a1.CFrame
				motor.Parent = part1
				joint:Destroy()
			end
		end
	end
end

-- Персонаж-NPC (вор, турист) из HumanoidDescription, с суставами Motor6D. nil — если Roblox не смог.
function ModelLibrary.createRig(description: HumanoidDescription): Model?
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[ModelLibrary] Не удалось создать персонажа:", result)
		return nil
	end
	useMotorJoints(result)
	return result
end

-- Группы столкновений. Туристы проходят сквозь всех людей (иначе двое на одной дорожке
-- упираются лбами и лезут друг на друга вверх), воры — сквозь других воров.
-- Охранник и вор сталкиваются: воры загораживают охране путь.
ModelLibrary.Groups = {
	Guards = "Guards",
	Thieves = "Thieves",
	Tourists = "Tourists",
}

function ModelLibrary.setupCollisionGroups()
	for _, name in ModelLibrary.Groups do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	local groups = ModelLibrary.Groups
	PhysicsService:CollisionGroupSetCollidable(groups.Tourists, groups.Tourists, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Tourists, groups.Guards, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Tourists, groups.Thieves, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Thieves, groups.Thieves, false)
end

function ModelLibrary.setCollisionGroup(root: Instance, group: string)
	forEachPart(root, function(part)
		part.CollisionGroup = group
	end)
end

-- Деталь одежды или снаряжения на часть тела персонажа (вор, турист, охранник). offset — относительно центра
-- этой части (для головы −Z — лицо, для кисти −Y — к пальцам). Каждая деталь приваривается Weld с явным C0
-- (не WeldConstraint: тот запоминает положение в момент входа в workspace), поэтому держится, где бы ни стоял
-- персонаж, и двигается вместе с костью: суставы Motor6D не трогаются. nil — если такой части тела нет.
-- Если друг сделал эту вещь как Accessory (со своим Attachment в Handle), она надевается через AddAccessory.
function ModelLibrary.attachTo(model: Model, partName: string, name: string, stub: { StubPart }, offset: CFrame): Instance?
	local bodyPart = model:FindFirstChild(partName)
	if not (bodyPart and bodyPart:IsA("BasePart")) then
		return nil
	end
	local template = findTemplate(name)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if template and template:IsA("Accessory") and humanoid then
		local accessory = ModelLibrary.accessory(name, stub, "")
		humanoid:AddAccessory(accessory)
		return accessory
	end
	local prop = ModelLibrary.build(name, stub)
	prop:PivotTo(bodyPart.CFrame * offset)
	forEachPart(prop, function(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		local weld = Instance.new("Weld")
		weld.Name = "PropWeld"
		weld.Part0 = bodyPart
		weld.Part1 = part
		weld.C0 = bodyPart.CFrame:ToObjectSpace(part.CFrame)
		weld.Parent = part
	end)
	prop.Parent = model
	return prop
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
