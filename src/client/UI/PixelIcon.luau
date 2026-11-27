-- Пиксельные иконки, нарисованные кодом (этап 5, блок A, решение 75). Общий модуль: хаб, обучение в музее (блок C),
-- кнопки музея — в блоке D.
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
local Theme = require(script.Parent:WaitForChild("Theme"))

-- Музей — реалистичный стиль (иконки-картинки, скруглённые рамки), хаб — пиксельный (Theme.Realistic)
local Realistic: boolean = Theme.Realistic
local Real = Config.PixelUI.Real
local realImage: (name: string) -> (string?, number)
local imageLayer: (root: Frame, name: string, image: string, rotation: number, zIndex: number) -> ImageLabel
local realDot: (root: Frame, zIndex: number) -> ()

local PixelIcon = {}
PixelIcon.Realistic = Realistic

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

-- Этап 5, блок C (обучение): большая стрелка вниз над целью, телефон оператора, датчик техника
Icons.ArrowDown = {
	rows = {
		".....KKKKKK.....",
		".....KyyyyK.....",
		".....KyyyyK.....",
		".....KyyyyK.....",
		".....KyyyyK.....",
		".....KyyyyK.....",
		".....KyyyyK.....",
		"KKKKKKyyyyKKKKKK",
		"KyyyyyyyyyyyyyyK",
		".KyyyyyyyyyyyyK.",
		"..KyyyyyyyyyyK..",
		"...KyyyyyyyyK...",
		"....KyyyyyyK....",
		".....KyyyyK.....",
		"......KyyK......",
		".......KK.......",
	},
	palette = { K = OUTLINE, y = "FFD23F" },
}

Icons.Phone = {
	rows = {
		"................",
		"....KKKKKKKK....",
		"...KddddddddK...",
		"...KdKKKKKKdK...",
		"...KdKbbbbKdK...",
		"...KdKbrbbKdK...",
		"...KdKbbbbKdK...",
		"...KdKbbbbKdK...",
		"...KdKKKKKKdK...",
		"...KddddddddK...",
		"...KdwdwdwddK...",
		"...KddddddddK...",
		"...KdwdwdwddK...",
		"...KddddddddK...",
		"....KKKKKKKK....",
		"................",
	},
	palette = { K = OUTLINE, d = "3A3A4A", b = "3BC6C1", r = "E04040", w = "C8C8D0" },
}

Icons.Sensor = {
	rows = {
		"................",
		"......KKKK......",
		"....KK....KK....",
		"...K..KKKK..K...",
		"..K..K....K..K..",
		".....K.KK.K.....",
		"......KrrK......",
		".....KKrrKK.....",
		".....KggggK.....",
		".....KggggK.....",
		".....KggggK.....",
		"....KggggggK....",
		"...KggggggggK...",
		"...KKKKKKKKKK...",
		"................",
		"................",
	},
	palette = { K = OUTLINE, r = "E04040", g = "8A93A6" },
}

-- Этап 5, блок D (кнопки музея): фразы, рывок, оружие, аптечка, патроны (перезарядка), присед, огонь.
-- Наклон — ArrowLeft / ArrowRight, телефон и датчик — выше.
Icons.Chat = {
	rows = {
		"................",
		"................",
		".KKKKKKKKKKKKKK.",
		"KwwwwwwwwwwwwwwK",
		"KwwwwwwwwwwwwwwK",
		"KwwbbwwbbwwbbwwK",
		"KwwbbwwbbwwbbwwK",
		"KwwwwwwwwwwwwwwK",
		"KggggggggggggggK",
		".KKKKKggKKKKKKK.",
		".....KgK........",
		"....KgK.........",
		"....KK..........",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, w = WHITE, g = "C8C8D0", b = "3BC6C1" },
}

Icons.Dash = {
	rows = {
		"................",
		"........KKKK....",
		".......KyyyK....",
		"......KyyyK.....",
		".....KyyyK......",
		"....KyyyKKKKK...",
		"...KyyyyyyyyK...",
		"...KKKKKyyyK....",
		".......KyyK.....",
		"......KyyK......",
		".....KyyK.......",
		"....KyyK........",
		"....KyK.........",
		"....KK..........",
		"................",
		"................",
	},
	palette = { K = OUTLINE, y = "FFD23F" },
}

Icons.Pistol = {
	rows = {
		"................",
		"................",
		"................",
		"..KKKKKKKKKKKKK.",
		"..KllllllllllllK",
		"..KddddddddddddK",
		"..KddddKKKKKKKK.",
		"..KddddKbK......",
		"..KddddKKK......",
		"..KbbbbK........",
		"..KbbbbK........",
		"..KbbbbK........",
		"..KKKKKK........",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, l = "B8BCC8", d = "6A6E7A", b = "6B4A2E" },
}

Icons.Rifle = {
	rows = {
		"................",
		"................",
		"................",
		"....KKKKKKKK....",
		"KKKKKddddddKKKKK",
		"KbbbKddddddddddK",
		"KbbbKddddddKKKKK",
		"KbbKKdKKdKKK....",
		"KKK.KdK.KdK.....",
		"....KdK.KdK.....",
		"....KKK.KdK.....",
		"........KKK.....",
		"................",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, d = "3A3E48", b = "6B4A2E" },
}

Icons.Shotgun = {
	rows = {
		"................",
		"................",
		"................",
		"................",
		"................",
		"KKKKKKKKKKKKKKKK",
		"KbbbbbKggggggggK",
		"KbbbbbKKKKKKKKKK",
		"KbbKKKKbbbbK....",
		"KbbK...KKKKK....",
		"KKKK............",
		"................",
		"................",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, b = "8B5A2B", g = "7A7E88" },
}

Icons.Taser = {
	rows = {
		"................",
		"................",
		"................",
		"..KKKKKKKKK.....",
		"..KyyyyyyyyKKK..",
		"..KyyyyyyyyKbK..",
		"..KyyyyyyyyKKK..",
		"..KyyyKKKKKK....",
		"..KdddK.........",
		"..KdddK.........",
		"..KdddK.........",
		"..KKKKK.........",
		"................",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, y = GOLD, d = "3A3A4A", b = "6FD3FF" },
}

Icons.Medkit = {
	rows = {
		"................",
		".....KKKKKK.....",
		"..KKKKKKKKKKKK..",
		"..KwwwwwwwwwwK..",
		"..KwwwwrrwwwwK..",
		"..KwwwwrrwwwwK..",
		"..KwwrrrrrrwwK..",
		"..KwwrrrrrrwwK..",
		"..KwwwwrrwwwwK..",
		"..KwwwwrrwwwwK..",
		"..KwwwwwwwwwwK..",
		"..KggggggggggK..",
		"..KKKKKKKKKKKK..",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, w = WHITE, r = "E04040", g = "C8C8D0" },
}

Icons.Reload = {
	rows = {
		"................",
		"................",
		"...KK...KK...KK.",
		"..KyyK.KyyK.KyyK",
		"..KyyK.KyyK.KyyK",
		"..KKKK.KKKK.KKKK",
		"..KooK.KooK.KooK",
		"..KooK.KooK.KooK",
		"..KooK.KooK.KooK",
		"..KooK.KooK.KooK",
		"..KooK.KooK.KooK",
		"..KddK.KddK.KddK",
		"..KKKK.KKKK.KKKK",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, y = "C87533", o = GOLD, d = GOLD_DARK },
}

Icons.Crouch = {
	rows = {
		"................",
		"..KK........KK..",
		"..KwK......KwK..",
		"...KwK....KwK...",
		"....KwK..KwK....",
		".....KwKKwK.....",
		"......KwwK......",
		".......KK.......",
		"..KK........KK..",
		"..KwK......KwK..",
		"...KwK....KwK...",
		"....KwK..KwK....",
		".....KwKKwK.....",
		"......KwwK......",
		".......KK.......",
		"................",
	},
	palette = { K = OUTLINE, w = WHITE },
}

Icons.Fire = {
	rows = {
		"................",
		"......KKKK......",
		"....KKrrrrKK....",
		"...KrrKKKKrrK...",
		"..KrrK....KrrK..",
		"..KrK..KK..KrK..",
		".KrrK.KrrK.KrrK.",
		".KrrK.KrrK.KrrK.",
		"..KrK..KK..KrK..",
		"..KrrK....KrrK..",
		"...KrrKKKKrrK...",
		"....KKrrrrKK....",
		"......KKKK......",
		"................",
		"................",
		"................",
	},
	palette = { K = OUTLINE, r = "FF4040" },
}

-- Этап 6, блок H1: задания (планшет со списком — две галочки и одно незаконченное) и достижение (медаль на ленте)
Icons.Quests = {
	rows = {
		"................",
		".....KKKKKK.....",
		"..KKKKyyyyKKKK..",
		"..KbbKKKKKKbbK..",
		"..KbwwwwwwwwbK..",
		"..KbwGGwkkkkbK..",
		"..KbwGGwwwwwbK..",
		"..KbwwwwwwwwbK..",
		"..KbwGGwkkkkbK..",
		"..KbwGGwwwwwbK..",
		"..KbwwwwwwwwbK..",
		"..KbwrrwkkkkbK..",
		"..KbwrrwwwwwbK..",
		"..KbwwwwwwwwbK..",
		"..KbbbbbbbbbbK..",
		"..KKKKKKKKKKKK..",
	},
	palette = { K = OUTLINE, y = GOLD, b = "8B5A2B", w = "F1E6CC", G = "3FB56B", k = "6B6255", r = "E0575B" },
}

Icons.Medal = {
	rows = {
		"................",
		"..KKK......KKK..",
		"..KrrK....KbbK..",
		"...KrrK..KbbK...",
		"....KrrKKbbK....",
		".....KrrbbK.....",
		".....KKKKKK.....",
		"....KyyyyyyK....",
		"...KyYYYYYYyK...",
		"...KyYyyyyYyK...",
		"...KyYyddyYyK...",
		"...KyYyddyYyK...",
		"...KyYyyyyYyK...",
		"...KyYYYYYYyK...",
		"....KyyyyyyK....",
		".....KKKKKK.....",
	},
	palette = { K = OUTLINE, r = "E0575B", b = "6FA8FF", y = GOLD, Y = GOLD_LIGHT, d = GOLD_DARK },
}

-- Этап 6, блок H2: коллекция (альбом с карточками: две открыты, одна закрыта) и экспонат на постаменте
-- (v — цвет экспоната, его перекрашивает окно COLLECTION)
Icons.Collection = {
	rows = {
		"................",
		".KKKKKKKKKKKKKK.",
		".KwwwwwKKwwwwwK.",
		".KwKKKwKKwKKKwK.",
		".KwKrKwKKwKyKwK.",
		".KwKrKwKKwKyKwK.",
		".KwKKKwKKwKKKwK.",
		".KwwwwwKKwwwwwK.",
		".KwKKKwKKwKKKwK.",
		".KwKgKwKKwKqKwK.",
		".KwKgKwKKwKqKwK.",
		".KwKKKwKKwKKKwK.",
		".KwwwwwKKwwwwwK.",
		".KbbbbbKKbbbbbK.",
		".KKKKKKKKKKKKKK.",
		"................",
	},
	palette = { K = OUTLINE, w = "F1E6CC", r = "E0575B", y = GOLD, g = "3FB56B", q = "566078", b = "8B5A2B" },
}

Icons.Exhibit = {
	rows = {
		"................",
		"......KKKK......",
		".....KvvvvK.....",
		"......KvvK......",
		".....KvvvvK.....",
		"....KvvhvvvK....",
		"....KvvhvvvK....",
		"....KvvvvvvK....",
		".....KvvvvK.....",
		"......KKKK......",
		"...KKKKKKKKKK...",
		"...KmmmmmmmmK...",
		"....KmmmmmmK....",
		"....KmmmmmmK....",
		"...KKKKKKKKKK...",
		"................",
	},
	palette = { K = OUTLINE, v = GOLD, h = WHITE, m = "E8DCC4" },
}

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

---------------------------------------------------------------- реалистичные иконки в музее (Config.PixelUI.Real)

-- Картинка для иконки: asset id и поворот (стрелки — одна картинка «вправо», повёрнутая). nil — картинки нет.
local ARROWS = { ArrowRight = 0, ArrowDown = 90, ArrowLeft = 180 }
function realImage(name: string): (string?, number)
	local key, rotation = name, 0
	if ARROWS[name] then
		key, rotation = "Arrow", ARROWS[name]
	end
	local id = Real.Images[key]
	if typeof(id) == "string" and id ~= "" then
		return id, rotation
	end
	return nil, 0
end

function imageLayer(root: Frame, name: string, image: string, rotation: number, zIndex: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Image = image
	label.ScaleType = Enum.ScaleType.Fit
	label.Rotation = rotation
	label.ZIndex = zIndex
	label.Parent = root
	return label
end

-- Красная точка-уведомление без картинки: круг с градиентом, бликом и тёмной обводкой.
function realDot(root: Frame, zIndex: number)
	local dot = Instance.new("Frame")
	dot.Name = "Art"
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.8, 0.8)
	dot.BackgroundColor3 = Color3.fromHex("F03C3C")
	dot.ZIndex = zIndex
	dot.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex("FF8A8A"), Color3.fromHex("B81E1E"))
	gradient.Rotation = 90
	gradient.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("5A0A0A")
	stroke.Thickness = 1.5
	stroke.Parent = dot
end

-- Новая иконка: Frame на весь размер, который ему дадут (по умолчанию — 4 пикселя на клетку).
-- В нём слой «Art» и, если shadow ~= false, слой «Shadow» на 1 клетку вниз-вправо (выходит за край Frame).
-- zIndex — ZIndex рисунка (тень на 1 ниже).
-- В музее (Theme.Realistic) иконка с картинкой в Config.PixelUI.Real.Images — реалистичная картинка (ImageLabel).
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
	if typeof(icon) == "string" and Realistic then
		if icon == "Dot" then
			realDot(root, z)
			return root
		end
		local image, rotation = realImage(icon)
		if image then
			if shadow ~= false then
				local shade = imageLayer(root, "Shadow", image, rotation, z - 1)
				shade.ImageColor3 = Color3.new(0, 0, 0)
				shade.ImageTransparency = Real.ShadowTransparency
				shade.Position = UDim2.fromScale(Real.ShadowOffset, Real.ShadowOffset)
			end
			imageLayer(root, "Art", image, rotation, z)
			return root
		end
	end
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
	if Realistic then
		-- Музей: один скруглённый прямоугольник вместо трёх ступенчатых
		local part = Instance.new("Frame")
		part.Name = name
		part.BorderSizePixel = 0
		part.BackgroundColor3 = color
		part.BackgroundTransparency = transparency
		part.Position = UDim2.fromOffset(inset * cell, inset * cell)
		part.Size = UDim2.new(1, -2 * inset * cell, 1, -2 * inset * cell)
		part.ZIndex = zIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, math.max(3, (4 - inset) * cell))
		corner.Parent = part
		part.Parent = parent
		return
	end
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
	if Realistic and fill then
		-- Музей: заливка с мягким градиентом сверху вниз (объём), у кнопок (bevel) — сильнее, с бликом сверху
		for _, part in root:GetChildren() do
			if part:IsA("Frame") and part.Name == "Layer" .. #options.layers then
				local gradient = Instance.new("UIGradient")
				gradient.Rotation = 90
				if options.bevel then
					gradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
						ColorSequenceKeypoint.new(0.45, Color3.fromRGB(225, 225, 225)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
					})
				else
					gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 195))
				end
				gradient.Parent = part
			end
		end
		if options.bevel then
			local gloss = Instance.new("Frame")
			gloss.Name = "Gloss"
			gloss.BorderSizePixel = 0
			gloss.BackgroundColor3 = Color3.new(1, 1, 1)
			gloss.BackgroundTransparency = 0.8
			gloss.Position = UDim2.fromOffset((inner + 1) * cell, (inner + 0.5) * cell)
			gloss.Size = UDim2.new(1, -2 * (inner + 1) * cell, 0.4, 0)
			gloss.ZIndex = #options.layers + 2
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, math.max(3, 2 * cell))
			corner.Parent = gloss
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new(0, 1)
			fade.Parent = gloss
			gloss.Parent = root
		end
		root.Parent = parent
		return root, (inner + 1) * cell
	end
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
