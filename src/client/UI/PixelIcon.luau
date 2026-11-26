-- Пиксельные иконки, нарисованные кодом (этап 5, блок A, решение 75). Общий модуль: хаб сейчас, музей — в блоке D.
--
-- Иконка — строки-картинка и палитра: каждая буква — клетка своего цвета, точка — пусто.
--   { rows = { "..KK..", ".KooK.", ... }, palette = { K = "1E1E2E", o = "F2C14E" } }
-- Модуль строит Frame из квадратиков без сглаживания (BorderSizePixel = 0). Соседние клетки одного цвета в строке
-- склеиваются в одну полоску — так Frame в несколько раз меньше. Клетки ставятся долями размера (Scale), поэтому
-- иконка занимает весь Frame, который ей дали: дай ему размер «число клеток × целое число пикселей» —
-- и клетки будут ровными (PixelIcon.size). Тень — та же иконка чёрным на 1 клетку вниз-вправо.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PixelIcon = {}

export type Icon = {
	rows: { string },
	palette: { [string]: string }, -- буква -> цвет в hex
}

-- Общие цвета
local OUTLINE = "141420"
local WHITE = "FFFFFF"
local GOLD = "F2C14E"
local GOLD_LIGHT = "FFE08A"
local GOLD_DARK = "B8862B"

local Icons: { [string]: Icon } = {}

-- Магазин: сумка с ручкой и белым ярлыком
Icons.Shop = {
	rows = {
		"................",
		".....KKKKKK.....",
		"....KK....KK....",
		"....K......K....",
		"....K......K....",
		"..KKKKKKKKKKKK..",
		"..KhhhhhhhhhhK..",
		"..KhoooooooodK..",
		"..KhoowwwwoodK..",
		"..KhoowwwwoodK..",
		"..KhoooooooodK..",
		"..KhoooooooodK..",
		"..KddddddddddK..",
		"..KKKKKKKKKKKK..",
		"................",
		"................",
	},
	palette = { K = OUTLINE, h = GOLD_LIGHT, o = GOLD, d = GOLD_DARK, w = WHITE },
}

-- Классы: щит со звездой
Icons.Classes = {
	rows = {
		"................",
		"..KKKKKKKKKKKK..",
		"..KlbbbbbbbbbK..",
		"..KlbbbYYbbbbK..",
		"..KlbbbYYbbbbK..",
		"..KlYYYYYYYYbK..",
		"..KlbYYYYYYbbK..",
		"..KlbbYYYYbbbK..",
		"..KlbYYbbYYbbK..",
		"..KlYYbbbbYYbK..",
		"...KlbbbbbbbK...",
		"....KlbbbbbK....",
		".....KlbbbK.....",
		"......KlbK......",
		".......KK.......",
		"................",
	},
	palette = { K = OUTLINE, b = "3B6FD8", l = "6E9BF0", Y = GOLD },
}

-- Как играть: книжка со знаком «?»
Icons.HowToPlay = {
	rows = {
		"................",
		"..KKKKKKKKKKKKK.",
		"..KdggggggggggK.",
		"..KdgggwwwwgggK.",
		"..KdggwwggwwggK.",
		"..KdggggggwwggK.",
		"..KdgggggwwgggK.",
		"..KdggggwwggggK.",
		"..KdggggwwggggK.",
		"..KdggggggggggK.",
		"..KdggggwwggggK.",
		"..KdggggggggggK.",
		"..KKKKKKKKKKKKK.",
		"..KpppppppppppK.",
		"..KKKKKKKKKKKKK.",
		"................",
	},
	palette = { K = OUTLINE, g = "2FA39E", d = "1E7471", w = WHITE, p = "F1E6CC" },
}

-- Подарок: коробка с бантом
Icons.Gift = {
	rows = {
		"................",
		"....KK....KK....",
		"...KrrK..KrrK...",
		"...KrrrKKrrrK...",
		".KKKKKKKKKKKKKK.",
		".KbbbbbrrbbbbbK.",
		".KKKKKKKKKKKKKK.",
		"..KbbbbrrbbbbK..",
		"..KbbbbrrbbbbK..",
		"..KbbbbrrbbbbK..",
		"..KbbbbrrbbbbK..",
		"..KbbbbrrbbbbK..",
		"..KddddrrddddK..",
		"..KKKKKKKKKKKK..",
		"................",
		"................",
	},
	palette = { K = OUTLINE, b = "D8434A", d = "A02C33", r = GOLD },
}

-- Группа: три человечка
Icons.Group = {
	rows = {
		"................",
		"................",
		"......KKKK......",
		".....KssssK.....",
		"..KK.KssssK.KK..",
		".KssKKssssKKssK.",
		".KssK.KKKK.KssK.",
		"..KK.KbbbbK.KK..",
		".KccKbbbbbbKccK.",
		"KccKbbbbbbbbKccK",
		"KccKbbbbbbbbKccK",
		"KccKbbbbbbbbKccK",
		"KKKKKKKKKKKKKKKK",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, s = "F5C9A0", b = "3BC6C1", c = "8E5BC2" },
}

-- Избранное: звезда
Icons.Favorite = {
	rows = {
		"................",
		".......KK.......",
		"......KhYK......",
		"......KhYK......",
		".....KhYYYK.....",
		"KKKKKKhYYYKKKKKK",
		"KhhhhhhYYYYYYYYK",
		".KhYYYYYYYYYYYK.",
		"..KYYYYYYYYYdK..",
		"...KYYYYYYYdK...",
		"...KYYYYYYYdK...",
		"..KYYYYKKYYYdK..",
		"..KYYYK..KYYdK..",
		".KYYK......KdYK.",
		".KKK........KKK.",
		"................",
	},
	palette = { K = OUTLINE, Y = GOLD, h = GOLD_LIGHT, d = GOLD_DARK },
}

-- Алмаз
Icons.Diamond = {
	rows = {
		"................",
		"................",
		"....KKKKKKKK....",
		"...KhhwhhhhcK...",
		"..KhhwhhhhcccK..",
		".KKKKKKKKKKKKKK.",
		".KhhhhhcccccddK.",
		"..KhhhhcccccdK..",
		"...KhhhccccdK...",
		"....KhhcccdK....",
		".....KhccdK.....",
		"......KcdK......",
		".......KK.......",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, h = "BDF4FF", c = "6FE3FF", d = "2FA8D0", w = WHITE },
}

-- Закрыть: крестик
Icons.Close = {
	rows = {
		"................",
		".KKK........KKK.",
		".KrrK......KrrK.",
		".KrrrK....KrrrK.",
		"..KrrrK..KrrrK..",
		"...KrrrKKrrrK...",
		"....KrrrrrrK....",
		".....KrrrrK.....",
		".....KrrrrK.....",
		"....KrrrrrrK....",
		"...KrrrKKrrrK...",
		"..KrrrK..KrrrK..",
		".KrrrK....KrrrK.",
		".KrrK......KrrK.",
		".KKK........KKK.",
		"................",
	},
	palette = { K = OUTLINE, r = "F05A5A" },
}

-- Галочка (забранный подарок)
Icons.Check = {
	rows = {
		"................",
		"................",
		"................",
		"............KKK.",
		"...........KggK.",
		"..........KggK..",
		".KKK.....KggK...",
		".KggK...KggK....",
		"..KggK.KggK.....",
		"...KggKggK......",
		"....KgggK.......",
		".....KgK........",
		"......K.........",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, g = "5BE07D" },
}

-- Стрелка вправо (страницы «Как играть»); влево — она же отражённая
Icons.ArrowRight = {
	rows = {
		"................",
		"................",
		".....KK.........",
		".....KwK........",
		".....KwwK.......",
		".....KwwwK......",
		".....KwwwwK.....",
		".....KwwwwwK....",
		".....KwwwwwK....",
		".....KwwwwK.....",
		".....KwwwK......",
		".....KwwK.......",
		".....KwK........",
		".....KK.........",
		"................",
		"................",
	},
	palette = { K = OUTLINE, w = WHITE },
}

-- Красная точка-уведомление 8 × 8
Icons.Dot = {
	rows = {
		"..KKKK..",
		".KrrrrK.",
		"KrwrrrrK",
		"KrrrrrrK",
		"KrrrrrrK",
		"KrrrrrrK",
		".KrrrrK.",
		"..KKKK..",
	},
	palette = { K = OUTLINE, r = "F03C3C", w = "FFB0B0" },
}

-- Для картинок «Как играть»: солнце, луна, картина, вор, клавиша F
Icons.Sun = {
	rows = {
		".......YY.......",
		"..Y....YY....Y..",
		"...Y........Y...",
		"......KKKK......",
		".....KhoooK.....",
		"....KhoooooK....",
		"YY..KooooooK..YY",
		"YY..KooooooK..YY",
		"....KoooooodK...",
		".....KoooodK....",
		"......KKKK......",
		"...Y........Y...",
		"..Y....YY....Y..",
		".......YY.......",
		"................",
		"................",
	},
	palette = { K = OUTLINE, Y = GOLD, o = "FFD23F", h = "FFF2A8", d = "E0A020" },
}

Icons.Moon = {
	rows = {
		"................",
		".....KKKK....w..",
		"...KKmmK........",
		"..KmmmK.........",
		".KmmmK......w...",
		".KmmK...........",
		"KmmmK...........",
		"KmmmK...........",
		"KmmmK.........K.",
		"KmmmmK.......KK.",
		".KmmmmKK...KKmK.",
		".KmmmmmmKKKmmK..",
		"..KKmmmmmmmmK...",
		"....KKKKKKKK....",
		"................",
		"................",
	},
	palette = { K = OUTLINE, m = "E8E2C8", w = WHITE },
}

Icons.Painting = {
	rows = {
		"................",
		".KKKKKKKKKKKKKK.",
		".KYYYYYYYYYYYYK.",
		".KYKKKKKKKKKKYK.",
		".KYKggggggggKYK.",
		".KYKgggKKgggKYK.",
		".KYKggKssKggKYK.",
		".KYKggKssKggKYK.",
		".KYKgggKKgggKYK.",
		".KYKggKbbKggKYK.",
		".KYKgKbbbbKgKYK.",
		".KYKKbbbbbbKKYK.",
		".KYKKKKKKKKKKYK.",
		".KYYYYYYYYYYYYK.",
		".KKKKKKKKKKKKKK.",
		"................",
	},
	palette = { K = OUTLINE, Y = GOLD, g = "6E8C5A", s = "E8B888", b = "4A3A2A" },
}

Icons.Thief = {
	rows = {
		"................",
		".....KKKKKK.....",
		"....KddddddK....",
		"...KddddddddK...",
		"...KKKKKKKKKK...",
		"...KssssssssK...",
		"...KKKKKKKKKK...",
		"...KKwKKKKwKK...",
		"...KKKKKKKKKK...",
		"...KssssssssK...",
		"....KssKKssK....",
		".....KssssK.....",
		"......KKKK......",
		"...KccccccccK...",
		"..KccccccccccK..",
		"..KKKKKKKKKKKK..",
	},
	palette = { K = OUTLINE, d = "3A3A4A", s = "E0A878", w = WHITE, c = "5A5A6E" },
}

Icons.KeyF = {
	rows = {
		"................",
		".KKKKKKKKKKKKKK.",
		".KwwwwwwwwwwwwK.",
		".KwwwKKKKKKwwwK.",
		".KwwwKKKKKKwwwK.",
		".KwwwKKwwwwwwwK.",
		".KwwwKKwwwwwwwK.",
		".KwwwKKKKKwwwwK.",
		".KwwwKKKKKwwwwK.",
		".KwwwKKwwwwwwwK.",
		".KwwwKKwwwwwwwK.",
		".KwwwKKwwwwwwwK.",
		".KggggggggggggK.",
		".KKKKKKKKKKKKKK.",
		"................",
		"................",
	},
	palette = { K = OUTLINE, w = "F1E6CC", g = "A89C84" },
}

-- Отражённая по горизонтали иконка
local function mirror(icon: Icon): Icon
	local rows = {}
	for index, row in icon.rows do
		rows[index] = string.reverse(row)
	end
	return { rows = rows, palette = icon.palette }
end

Icons.ArrowLeft = mirror(Icons.ArrowRight)

PixelIcon.Icons = Icons

local function resolve(icon: Icon | string): Icon
	if typeof(icon) == "string" then
		local found = Icons[icon]
		assert(found, "Нет такой пиксельной иконки: " .. icon)
		return found
	end
	return icon
end

-- Размер иконки в клетках (ширина, высота).
function PixelIcon.cells(icon: Icon | string): (number, number)
	local data = resolve(icon)
	local width = 0
	for _, row in data.rows do
		width = math.max(width, #row)
	end
	return width, #data.rows
end

-- Размер иконки в пикселях при клетке cell (целое число пикселей).
function PixelIcon.size(icon: Icon | string, cell: number): UDim2
	local w, h = PixelIcon.cells(icon)
	return UDim2.fromOffset(w * cell, h * cell)
end

-- Слой иконки: полоски одного цвета; color — если задан, все клетки этим цветом (для тени).
local function layer(data: Icon, name: string, color: Color3?, transparency: number, zIndex: number): Frame
	local w, h = PixelIcon.cells(data)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zIndex
	local colors: { [string]: Color3 } = {}
	for y, row in data.rows do
		local x = 1
		while x <= #row do
			local char = string.sub(row, x, x)
			local hex = data.palette[char]
			if char == "." or not hex then
				x += 1
			else
				-- Тень — одним цветом, поэтому склеиваем все закрашенные клетки подряд
				local run = 1
				while x + run <= #row do
					local nextChar = string.sub(row, x + run, x + run)
					if nextChar == "." or not data.palette[nextChar] or (color == nil and nextChar ~= char) then
						break
					end
					run += 1
				end
				local cellColor = color
				if not cellColor then
					cellColor = colors[char]
					if not cellColor then
						cellColor = Color3.fromHex(hex)
						colors[char] = cellColor
					end
				end
				local pixel = Instance.new("Frame")
				pixel.BorderSizePixel = 0
				pixel.BackgroundColor3 = cellColor :: Color3
				pixel.BackgroundTransparency = transparency
				pixel.Position = UDim2.fromScale((x - 1) / w, (y - 1) / h)
				pixel.Size = UDim2.fromScale(run / w, 1 / h)
				pixel.ZIndex = zIndex
				pixel.Parent = frame
				x += run
			end
		end
	end
	return frame
end

-- Новая иконка: Frame на весь размер, который ему дадут (по умолчанию — 4 пикселя на клетку).
-- В нём слой «Art» и, если shadow ~= false, слой «Shadow» на 1 клетку вниз-вправо (выходит за край Frame).
-- zIndex — ZIndex рисунка (тень на 1 ниже).
function PixelIcon.new(icon: Icon | string, shadow: boolean?, zIndex: number?): Frame
	local data = resolve(icon)
	local w, h = PixelIcon.cells(data)
	local z = zIndex or 2
	local root = Instance.new("Frame")
	root.Name = if typeof(icon) == "string" then icon .. "Icon" else "PixelIcon"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(w * 4, h * 4)
	root.ZIndex = z
	if shadow ~= false then
		local shade = layer(data, "Shadow", Color3.new(0, 0, 0), Config.PixelUI.ShadowTransparency, z - 1)
		shade.Position = UDim2.fromScale(1 / w, 1 / h)
		shade.Parent = root
	end
	layer(data, "Art", nil, 0, z).Parent = root
	return root
end

---------------------------------------------------------------- пиксельная рамка (окна, кнопки с текстом)

PixelIcon.Outline = Color3.fromHex(OUTLINE)

-- Прямоугольник со ступенчатыми углами (2 ступеньки по клетке) с отступом inset клеток от краёв parent.
-- Это 3 Frame: широкий, средний и высокий — вместе выглядят как пиксельный прямоугольник без UICorner.
local function stepped(parent: Instance, cell: number, inset: number, color: Color3, transparency: number, zIndex: number, name: string)
	for step = 0, 2 do
		local x = (inset + 2 - step) * cell
		local y = (inset + step) * cell
		local part = Instance.new("Frame")
		part.Name = name
		part.BorderSizePixel = 0
		part.BackgroundColor3 = color
		part.BackgroundTransparency = transparency
		part.Position = UDim2.fromOffset(x, y)
		part.Size = UDim2.new(1, -2 * x, 1, -2 * y)
		part.ZIndex = zIndex
		part.Parent = parent
	end
end

export type BoxOptions = {
	layers: { Color3 }, -- цвета слоёв снаружи внутрь, каждый — 1 клетка (последний — заливка)
	shadow: boolean?, -- тень на 1 клетку вниз-вправо
	bevel: boolean?, -- светлая полоска сверху и тёмная снизу внутри заливки (кнопки)
	zIndex: number?, -- ZIndex всей рамки среди соседей (по умолчанию 0 — под содержимым)
}

-- Пиксельная рамка на весь parent: снаружи внутрь слои по клетке, углы ступеньками. Возвращает Frame рамки и
-- отступ заливки от края в пикселях (содержимое ставь внутрь этого отступа).
function PixelIcon.box(parent: Instance, cell: number, options: BoxOptions): (Frame, number)
	local root = Instance.new("Frame")
	root.Name = "PixelBox"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = options.zIndex or 0
	if options.shadow then
		local shade = Instance.new("Frame")
		shade.Name = "Shadow"
		shade.BackgroundTransparency = 1
		shade.Position = UDim2.fromOffset(cell, cell)
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 1
		shade.Parent = root
		stepped(shade, cell, 0, Color3.new(0, 0, 0), Config.PixelUI.ShadowTransparency, 1, "Shade")
	end
	for index, color in options.layers do
		stepped(root, cell, index - 1, color, 0, index + 1, "Layer" .. index)
	end
	local inner = #options.layers - 1
	local fill = options.layers[#options.layers]
	if options.bevel and fill then
		local z = #options.layers + 2
		local x = (inner + 2) * cell
		local top = Instance.new("Frame")
		top.Name = "Light"
		top.BorderSizePixel = 0
		top.BackgroundColor3 = fill:Lerp(Color3.new(1, 1, 1), 0.3)
		top.Position = UDim2.fromOffset(x, inner * cell)
		top.Size = UDim2.new(1, -2 * x, 0, cell)
		top.ZIndex = z
		top.Parent = root
		local bottom = Instance.new("Frame")
		bottom.Name = "Dark"
		bottom.BorderSizePixel = 0
		bottom.BackgroundColor3 = fill:Lerp(Color3.new(0, 0, 0), 0.35)
		bottom.Position = UDim2.new(0, x, 1, -(inner + 1) * cell)
		bottom.Size = UDim2.new(1, -2 * x, 0, cell)
		bottom.ZIndex = z
		bottom.Parent = root
	end
	root.Parent = parent
	return root, (inner + 1) * cell
end

-- Перекрасить заливку рамки (кнопка поменяла цвет): последний слой и полоски bevel.
function PixelIcon.recolor(box: Frame, layerCount: number, fill: Color3)
	for _, part in box:GetChildren() do
		if part:IsA("Frame") then
			if part.Name == "Layer" .. layerCount then
				part.BackgroundColor3 = fill
			elseif part.Name == "Light" then
				part.BackgroundColor3 = fill:Lerp(Color3.new(1, 1, 1), 0.3)
			elseif part.Name == "Dark" then
				part.BackgroundColor3 = fill:Lerp(Color3.new(0, 0, 0), 0.35)
			end
		end
	end
end

return PixelIcon
