# scripts — проверка кода и сборка игры

Эти скрипты нужны всем, кто меняет код: Claude, Gemini, владельцу и другу.

## Что поставить один раз

1. **Git** (на Windows вместе с ним ставится Git Bash, в нём и запускай скрипты): https://git-scm.com
2. **Rojo 7.7 или новее**:
   - скачай с https://github.com/rojo-rbx/rojo/releases файл для своей системы (Windows — `rojo-…-windows-x86_64.zip`);
   - распакуй `rojo.exe` в папку, которая есть в PATH;
   - или поставь через Rokit / Aftman.
   - Проверка: `rojo --version`.
3. **luau-lsp**:
   - скачай с https://github.com/JohnnyMorganz/luau-lsp/releases файл для своей системы (Windows — `luau-lsp-win64.zip`);
   - распакуй в папку `scripts/.tools/` этого репозитория (она в `.gitignore`), или в любую папку из PATH, или укажи путь в переменной `LUAU_LSP`.
   - Проверка: `luau-lsp --version`.

Типы Roblox (`globalTypes.d.luau`) уже лежат здесь, скачивать их не нужно.

## Проверка кода — перед каждым push

```sh
sh scripts/check.sh
```

Успех — в конце три строки:

```
museum analyze exit: 0
hub analyze exit: 0
analyze exit: 0
```

Если выше есть строки с `TypeError` или `SyntaxError`, сначала исправь их, потом пушь. Временные файлы скрипт кладёт в `scripts/.build/`, их не коммитим.

## Собрать файлы игры для Studio

```sh
rojo build default.project.json -o NightMuseum.rbxl   # место Museum
rojo build hub.project.json -o Hub.rbxl               # место Hub (общее лобби)
```

Файлы `.rbxl` в git не кладём. У владельца они лежат рядом с репозиторием: `D:/Punhan/My files/museun/`. Публикует владелец: открывает файл в Studio → File → Publish to Roblox, а при закрытии нажимает «Не сохранять».
