#!/bin/sh
# Проверка кода игры для всех (Claude, Gemini, владелец, друг): сборка Rojo + проверка типов luau-lsp
# для музея (default.project.json) и хаба (hub.project.json).
#
# Запуск из любой папки:   sh scripts/check.sh      (Windows — в Git Bash)
# Успех: в конце три строки "museum analyze exit: 0", "hub analyze exit: 0", "analyze exit: 0" и нет строк с ошибками.
#
# Нужны программы (как поставить — scripts/README.md):
#   rojo      — в PATH (версия 7.7 или новее)
#   luau-lsp  — в PATH, или в scripts/.tools/ (luau-lsp или luau-lsp.exe), или путь в переменной LUAU_LSP
# Типы Roblox лежат в репозитории: scripts/globalTypes.d.luau.

DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$DIR/.." && pwd)
BUILD="$DIR/.build"
mkdir -p "$BUILD"
cd "$REPO" || exit 1

if ! command -v rojo >/dev/null 2>&1; then
	echo "rojo не найден в PATH — см. scripts/README.md"
	exit 1
fi

LSP="${LUAU_LSP:-}"
if [ -z "$LSP" ]; then
	if command -v luau-lsp >/dev/null 2>&1; then
		LSP=luau-lsp
	elif [ -x "$DIR/.tools/luau-lsp.exe" ]; then
		LSP="$DIR/.tools/luau-lsp.exe"
	elif [ -x "$DIR/.tools/luau-lsp" ]; then
		LSP="$DIR/.tools/luau-lsp"
	else
		echo "luau-lsp не найден — см. scripts/README.md"
		exit 1
	fi
fi
DEFS="--definitions=$DIR/globalTypes.d.luau"

# Музей: src/server, src/client, src/shared
rojo build default.project.json -o "$BUILD/museum.rbxlx" 2>&1 | tail -1
rojo sourcemap default.project.json -o "$BUILD/sourcemap.json" 2>&1 | grep -v '^$'
"$LSP" analyze "$DEFS" --sourcemap="$BUILD/sourcemap.json" --no-strict-dm-types src/server src/client src/shared > "$BUILD/analyze.log" 2>&1
CODE=$?
grep -v "didChangeWatchedFiles\|Loading definitions" "$BUILD/analyze.log"
echo "museum analyze exit: $CODE"

# Хаб: src/hub (общие модули подключены в hub.project.json)
rojo build hub.project.json -o "$BUILD/hub.rbxlx" 2>&1 | tail -1
rojo sourcemap hub.project.json -o "$BUILD/hub-sourcemap.json" 2>&1 | grep -v '^$'
"$LSP" analyze "$DEFS" --sourcemap="$BUILD/hub-sourcemap.json" --no-strict-dm-types src/hub > "$BUILD/hub-analyze.log" 2>&1
HCODE=$?
grep -v "didChangeWatchedFiles\|Loading definitions" "$BUILD/hub-analyze.log"
echo "hub analyze exit: $HCODE"

echo "analyze exit: $((CODE | HCODE))"
