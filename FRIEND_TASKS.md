# FRIEND_TASKS.md — задания для друга (Gemini в обычном чате)

Обновлено 27.11.2026. Файл написал Claude по просьбе владельца. Здесь три части:

1. **Как работать.** Ты делаешь код и модели через Gemini в чате, без командной строки.
2. **Код:** блок I (режим зрителя, таблица статистики, экран MVP) и блок J (меню настроек, красивые переходы).
3. **Ремодель:** какие модели переделать, чтобы игра выглядела качественнее.

> **Подожди сигнала владельца.** Пока Claude доделывает блок H2 (коллекция, сундук после ночи, бонус друзей), код не трогай: иначе вы одновременно поменяете одни и те же файлы. Ремодель (часть 3) можно начинать сразу: она меняет только папку `assets/models/`.

---

## Часть 1. Как работать

### Что у тебя есть
- **Gemini** в обычном чате. Он не видит файлы сам: ты копируешь ему текст файлов.
- **Сайт GitHub** — репозиторий https://github.com/PUNU-1/roblox (владелец добавил тебя как соавтора).
- **Roblox Studio** — для моделей (Command Bar) и чтобы посмотреть игру.

### Как дать Gemini файл
1. Открой файл на GitHub, например `src/client/HUD.client.luau`.
2. Справа над текстом нажми **Copy raw file**, это значок копирования.
3. Вставь в чат и подпиши: «Это файл `src/client/HUD.client.luau`».

### Начало каждого чата с Gemini (для кода)
Вставь по порядку:
1. Этот файл целиком (`FRIEND_TASKS.md`, Copy raw file).
2. Строку: «Сделай задание I1» (или другое). Возьми номер задания ниже.
3. Файлы, которые указаны в задании в строке «Дай Gemini».

Попроси Gemini: **«Возвращай файл целиком, а не кусками. Ничего лишнего не меняй».**

### Как сохранить исправление на GitHub
- **Поменять файл:** открой файл → значок карандаша (**Edit**) → выдели всё (Ctrl+A) → вставь ответ Gemini → **Commit changes** → в сообщении коротко напиши, что сделал → **Commit changes**.
- **Новый файл:** открой нужную папку (например `src/client`) → **Add file** → **Create new file** → имя файла (например `Spectate.client.luau`) → вставь код → **Commit changes**.
- **Один пункт — один коммит.** Владелец и Claude тогда видят, что поменялось.

### Как проверить (делает владелец на своём компьютере)
После твоих коммитов владелец открывает PowerShell и выполняет команды по одной:
```
cd "D:\Punhan\My files\museun\roblox"
git pull
bash ../tools/check.sh
```
- В конце проверки должно быть `analyze exit: 0` три раза. Если нет — владелец присылает тебе текст ошибки, ты отдаёшь его Gemini.
- Потом владелец собирает файлы игры и публикует их в Roblox:
  ```
  rojo build default.project.json -o "D:/Punhan/My files/museun/NightMuseum.rbxl"
  rojo build hub.project.json -o "D:/Punhan/My files/museun/Hub.rbxl"
  ```
- Ошибка в игре: нажми **F9**, вкладка **Server** или **Client**, скопируй красные строки и отдай Gemini вместе с файлом, на который указывает ошибка.

### Правила кода (Gemini должен их соблюдать)
1. **Сервер решает всё важное:** деньги, алмазы, аресты, здоровье, сохранения. Клиент (файлы `.client.luau`) только показывает и отправляет просьбы через Remote. Клиенту не верим.
2. **Все числа** — в `src/shared/Config.luau`, а не внутри логики.
3. **Все Remote** — в `src/shared/Remotes.luau`. Сервер проверяет каждый аргумент: тип, диапазон, как часто приходит.
4. **Имена атрибутов** — в `src/shared/GameState.luau` (`GameState.PlayerAttr`, `GameState.Attr`). Новые атрибуты добавляй туда же.
5. **DataStore** — только через `ProfileStore.luau` и `UpdateAsync` в `pcall` с повтором. Смотри, как там уже сделаны алмазы и настройка обучения.
6. **Отключай события** (`:Disconnect()`), когда окно или объект пропадает.
7. **Весь текст в игре — на английском.**
8. **Стиль кнопок и окон — пиксельный, без рамок** (решение владельца). Готовые модули: `src/client/UI/PixelButton.luau`, `PixelIcon.luau`, `PixelWindow.luau`, `Theme.luau`. Дай их Gemini, пусть делает так же.
9. **В музее вид от первого лица** (`FirstPerson.client.luau`). Если меняешь камеру, потом верни как было.
10. **Каждое действие с клавишей должно работать и на телефоне:** кнопка на экране. Тип устройства определяет `Theme.touchOnly()`.

---

## Часть 2. Код

### I1. Режим зрителя

**Что это:** пока охранник лежит (здоровье кончилось) или ждёт в комнате охраны (опоздал и ждёт голосования), он может смотреть глазами других охранников, чтобы не скучать.

**Дай Gemini:** `src/client/FirstPerson.client.luau`, `src/shared/GameState.luau`, `src/client/UI/PixelButton.luau`, `src/client/UI/Theme.luau`, `src/client/Combat.client.luau` (там экран «ты лежишь»).

**Как сделать:**
1. Новый файл `src/client/Spectate.client.luau`.
2. Режим доступен, когда у своего игрока атрибут `Downed = true`, или когда фаза (`GameState.Attr.Phase`) — Day или Night, а `InRound ~= true` (игрок не на смене).
3. Внизу по центру — пиксельные кнопки **◀** и **▶** и клавиши **Z** / **X**. Они переключают камеру на следующего охранника: игрок с `InRound = true`, кроме себя. Сверху надпись `WATCHING: <ник>`.
4. Камера: `Camera.CameraSubject` — Humanoid того охранника, `player.CameraMode = Enum.CameraMode.Classic`, приближение 8–12 стадов (вид из-за плеча).
5. Кнопка **BACK** (клавиша **C**) возвращает свой вид: `CameraSubject` — свой Humanoid, `CameraMode = LockFirstPerson`. Лежащий может ползти только в своём виде.
6. Встал (`Downed = false`), начался забег (`InRound = true`) или охранников не осталось — режим выключается сам и камера возвращается.
7. Числа (приближение) — в `Config.Spectate`.

**Готово, когда:** лёг — появились ◀ ▶ BACK, камера переключается между друзьями, после подъёма вид снова от первого лица.

### I2. Таблица статистики

**Что это:** пока держишь клавишу **L** (Tab уже занят телефоном оператора) или кнопку **STATS** на экране, видна таблица команды.

**Дай Gemini:** `src/server/ScoreService.luau`, `src/server/HealthService.luau`, `src/shared/GameState.luau`, `src/client/UI/PixelWindow.luau`, `src/client/UI/PixelButton.luau`, `src/client/UI/Theme.luau`.

**Как сделать:**
1. **Сервер.**
   - В `GameState.PlayerAttr` добавь `NightArrests` и `RunRevives`.
   - `ScoreService`: при аресте (там, где уже растёт `RunArrests`) +1 к `NightArrests`. В начале каждой ночи `NightArrests = 0`, в начале забега `RunRevives = 0`.
   - `HealthService`: в функции `revive(target, reviver)` +1 к `RunRevives` у того, кто поднял.
2. **Клиент** — новый файл `src/client/Stats.client.luau`.
   - Пиксельное окно по центру, строка на каждого игрока на смене: ник, класс (`Role`), аресты за ночь / за забег (`NightArrests` / `RunArrests`), деньги (`Money`), поднял друзей (`RunRevives`), уровень (`Level`).
   - Себя выдели цветом.
   - Пока окно открыто, оно обновляется раз в 0,5 сек.
3. На телефоне — пиксельная кнопка STATS рядом с кнопкой SHOP. Окно открывается и закрывается нажатием.

**Готово, когда:** держишь L — видна таблица, числа растут после арестов.

### I3. Экран MVP в итоге ночи

**Что это:** в итоге ночи лучший охранник стоит на пьедестале — крутится его персонаж, сверху золотая корона и надпись `MVP — 7 arrests`. Это заменяет строку «★ BEST GUARD».

**Дай Gemini:** `src/client/HUD.client.luau` (экран итога: ищи `results.bestUserId` и `BEST GUARD`), `src/server/ScoreService.luau`, `src/client/UI/Theme.luau`.

**Как сделать:**
1. Сервер уже присылает `results.bestUserId`, лучшего по арестам. При равенстве арестов лучший — у кого больше `RunRevives` (ScoreService, после задания I2).
2. В экране итога — `ViewportFrame` 260 × 300.
   - Внутри копия персонажа MVP: `character.Archivable = true`, `character:Clone()`, у копии удалить скрипты.
   - Пьедестал — 2–3 детали, корона — несколько золотых деталей, всё делается кодом.
   - Медленно крутится (`RunService.RenderStepped`), камера смотрит на неё спереди.
   - Под ней пиксельным шрифтом `MVP — <ник> — 7 arrests`.
3. Если никто никого не арестовал — MVP не показывать.
4. Окно итога закрылось — копию удалить.

**Готово, когда:** в итоге ночи крутится персонаж лучшего охранника с короной.

### J1. Меню настроек

**Что это:** пиксельная кнопка-шестерёнка открывает окно настроек — в хабе (в столбике кнопок слева) и в музее (рядом с SHOP).

**Дай Gemini:** `src/server/ProfileStore.luau` (смотри, как сделана настройка обучения `tutorialOff`, Remote `SetTutorial`, атрибут `TutorialOff`), `src/shared/Remotes.luau`, `src/shared/GameState.luau`, `src/shared/Config.luau`, `src/server/Audio.luau`, `src/hub/client/HubHUD.client.luau`, `src/client/HUD.client.luau`, `src/client/UI/PixelWindow.luau`, `src/client/UI/PixelButton.luau`, `src/client/UI/PixelIcon.luau`.

**Настройки:**
1. **Music volume** и **Effects volume** — 0–100 %.
   - В `Audio.luau` на сервере создай в `SoundService` две группы, `SoundGroup` «Music» и «Effects». Каждому звуку ставь `SoundGroup`: музыке — Music, остальным — Effects.
   - Клиент меняет `SoundGroup.Volume` у себя: это слышит только он.
2. **Camera sensitivity** — 0,3–2,0. Меняется через `UserInputService.MouseDeltaSensitivity`.
3. **Graphics: High / Low** — Low нужен для слабых телефонов. На клиенте:
   - выключить `CastShadow` у мелких деталей (меньше 2 стадов);
   - выключить `ParticleEmitter`;
   - уменьшить `Atmosphere.Density`;
   - выключить `BloomEffect`.
4. **Tutorial: ON / OFF** — та же настройка, что уже есть в обучении (Remote `SetTutorial`).

**Сохранение:**
- Сделай как `tutorialOff`: поле `settings` в профиле, Remote `SaveSettings(music, effects, sensitivity, lowGraphics)`.
- Сервер проверяет типы и диапазоны и принимает не чаще раза в 2 сек.
- Игрок видит свои настройки атрибутами, клиент применяет их при входе.
- Ползунки сделай кнопками − / + с шагом 10 % (так проще на телефоне).

**Готово, когда:** звук тише или громче, графика Low убирает тени, после перезахода настройки остаются.

### J2. Красивые переходы

**Дай Gemini:** `src/client/HUD.client.luau`, `src/shared/GameState.luau` (атрибуты `Phase`, `PaintingStolen`), `src/client/FirstPerson.client.luau`, `src/client/UI/Theme.luau`.

**Что сделать** (новый файл `src/client/Transitions.client.luau`, всё только на клиенте):
1. **День → ночь** (фаза стала Night):
   - экран за 2 сек темнеет до синего (`ColorCorrectionEffect` в `Lighting` на клиенте, `TintColor` и `Brightness` через `TweenService`), потом эффект плавно уходит;
   - крупная надпись `NIGHT 3` с тряской и тревожным звуком из `Config.Sounds`.
2. **Ночь → утро** (после ночи началась фаза Results и ночь пережита): тёплая вспышка рассвета и надпись `YOU SURVIVED NIGHT 3`.
3. **Затемнение:** в начале ночи сервер переносит всех к Моне Лизе. Сделай чёрный экран: 0,3 сек до черноты, 0,4 сек обратно. То же — перед телепортом в хаб.
4. **Кража:** когда `PaintingStolen` стал `true`, у краёв экрана на 1,5 сек пульсирует красная рамка, звучит сирена (уже есть) и появляется надпись `THE MONA LISA IS STOLEN!`.
5. **Облёт камерой** в начале ночи — по желанию. Не больше 3 сек, любая клавиша пропускает, потом камера и `CameraMode` возвращаются как были. Если сомневаешься, не делай: можно сломать вид от первого лица.

**Готово, когда:** смена дня и ночи и кража выглядят как в настоящей игре, вид от первого лица не ломается.

---

## Часть 3. Ремодель — поднять качество моделей

Сейчас все модели строит код Claude из простых деталей. **Твоя модель с тем же именем сама заменяет модель Claude:** код её находит, ничего менять в коде не надо. Как делать модель (Command Bar, сохранить `.rbxmx`, загрузить в `assets/models/`), подробно написано в `GEMINI.md`, раздел «Для друга: как пользоваться этим файлом». Для ремодели вставляй Gemini **`GEMINI.md`**, а не этот файл, и пиши: «Сделай ремодель `<имя модели>` по `FRIEND_TASKS.md`, часть 3».

### Как посмотреть, как модель выглядит сейчас
1. Владелец присылает тебе свежий `NightMuseum.rbxl` (и `Hub.rbxl` для моделей хаба).
2. Открой его в Studio и нажми **Play**: карта и модели строятся кодом при запуске.
3. Найди модель в **Explorer → Workspace → Map**, выдели её → **Ctrl+C** → **Stop** → вставь в своё место для моделей → сделай скриншоты и отдай Gemini как образец.
4. **Размер и точку привязки оставь такими же.** Иначе модель встанет криво или будет мешать проходу.

### Правила ремодели
- **Точка привязки** (`WorldPivot`) — внизу по центру, «перед» смотрит в **−Z**.
- **Без скриптов внутри.** Скрипты код не возьмёт.
- **Детали:** мелкий предмет — 20–60, крупный (стенд, касса, скелет) — 80–200. Больше не надо: на телефонах будет тормозить.
- **Качество:**
  - скругления — из `Cylinder`, `Ball`, `WedgePart`, `CornerWedgePart`;
  - фаски — тонкими деталями по краям;
  - надписи — `SurfaceGui` с `TextLabel`;
  - светящиеся полоски — `Neon`;
  - стекло — `Glass` с прозрачностью 0,5–0,7;
  - металл — `Metal` или `DiamondPlate`;
  - дерево — `Wood` / `WoodPlanks`;
  - мягкое — `Fabric`.
- **Палитра** — как в `GEMINI.md` («Стиль»): тёмно-синий, бежевый мрамор, золото, красный, бирюза. Плюс свои цвета для экспоната. Модель должна читаться и в **чёрно-белом** ночном виде камер.
- **Вещи на персонаже** (`guard_*`, `thief_*`, `robber_*`, `tourist_*`) можно сохранять как **Accessory**: код наденет их сам. Очень мелкие вещи — без столкновений: `CanCollide = false`, `Massless = true`.
- **Оружие** (`weapon_*`) видно вблизи от первого лица — это самое важное по качеству. **Имена деталей `Slide`, `Mag`, `Pump`, `Screen` не менять:** их двигают анимации перезарядки и затвора.

### Что переделать — по важности

**1. Видно вблизи всё время (начни с этого):**
- `weapon_pistol_01`, `weapon_rifle_01`, `weapon_shotgun_01`, `weapon_taser_01` — оружие в руках;
- `exhibit_monalisa_01` — Мона Лиза в раме, главный предмет игры;
- экспонаты (полный список имён — в `GEMINI.md`, «План моделей»): `exhibit_trexskull_01`, `exhibit_rocketmodel_01`, `exhibit_astronauthelmet_01`, `exhibit_dinoegg_01`, `exhibit_raptorclaw_01`, `exhibit_dinotooth_01`, `exhibit_meteorite_01`, `exhibit_moonrock_01` и экспонаты центра, Скульптур и Драгоценностей;
- `prop_shopcounter_01` (касса SHOP), `prop_partition_01` (перегородка с картинами), `prop_displaycase_01` (витрина), `prop_pedestal_01` (постамент).

**2. Персонажи:**
- воры: `thief_mask_01`, `thief_pickpocket_*`, `thief_breaker_*`, `thief_brute_*`, `thief_shadow_*`, `thief_miner_*`, `thief_glazier_*`, `thief_cutter_*`;
- грабители: `robber_balaclava_01`, `robber_vest_01`, `robber_bag_01`, `robber_baton_01`;
- охрана: `guard_badge_01`, `guard_vest_01`, детали классов (`guard_patrol_*`, `guard_operator_*`, `guard_tech_*`, `guard_k9_*`, `guard_assault_*`);
- `prop_dog_01` (собака кинолога — **кости собаки не трогай**, правила в `GEMINI.md`).

**3. Музей:**
- `prop_bench_01`, `prop_planter_tree_01`, `prop_floorlamp_01`, `prop_statue_01`, `prop_fountain_01`;
- `prop_skeleton_trex_01`, `prop_skeleton_longneck_01`, `prop_planet_01`, `prop_rocket_01`, `prop_astronaut_01`;
- `prop_door_entrance_01`, `camera_wall_01`, `trap_laser_01`, `prop_fusebox_01`, `prop_barrier_01`;
- `prop_armory_case_01`, `prop_weaponrack_01`, `prop_mannequin_01`, `prop_supply_table_01`, `prop_medkit_01`, `prop_ammo_*`.

**4. Хаб (лобби):**
- `prop_classstand_01`, `prop_desk_01`, `prop_monitor_01`, `prop_locker_01`;
- `prop_trophy_01`, `prop_watercooler_01`, `prop_coffeemachine_01`, `prop_noticeboard_01`.

Загрузил модель — напиши владельцу её имя. Он соберёт игру и посмотрит, как она встала.
