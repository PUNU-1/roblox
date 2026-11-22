-- Стена мониторов в хабе (блок 6): мигает красная точка REC и тикают часы на картинках камер.
-- Только украшение у этого игрока; сами экраны и картинки на них строит сервер (HubBuilder).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapSchema = require(Shared:WaitForChild("MapSchema"))

local map = Workspace:WaitForChild(MapSchema.Root)
local screens = map:WaitForChild(MapSchema.MonitorScreens)

type Feed = { dot: GuiObject?, rec: GuiObject?, clock: TextLabel? }

local feeds: { Feed } = {}

local function collect()
	table.clear(feeds)
	for _, screen in screens:GetChildren() do
		local gui = screen:FindFirstChildOfClass("SurfaceGui")
		local root = gui and gui:FindFirstChildOfClass("Frame")
		if root then
			local dot = root:FindFirstChild("RecDot")
			local rec = root:FindFirstChild("Rec")
			local clock = root:FindFirstChild("Clock")
			table.insert(feeds, {
				dot = if dot and dot:IsA("GuiObject") then dot else nil,
				rec = if rec and rec:IsA("GuiObject") then rec else nil,
				clock = if clock and clock:IsA("TextLabel") then clock else nil,
			})
		end
	end
end

-- Экраны приходят с сервера не сразу — подождём, пока появятся
task.wait(1)
collect()
screens.ChildAdded:Connect(function()
	task.defer(collect)
end)

local visible = true
while true do
	task.wait(Config.Hub.RecStepSeconds)
	visible = not visible
	local time = DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
	for _, feed in feeds do
		if feed.dot then
			feed.dot.Visible = visible
		end
		if feed.rec then
			feed.rec.Visible = visible
		end
		if feed.clock then
			feed.clock.Text = time
		end
	end
end
