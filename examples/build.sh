#!/bin/bash
# Сборка всех примеров из этой папки.
# Каждый файл NN_widget.v — самостоятельная программа, иллюстрирующая
# применение одного виджета vgui. Бинарники кладутся в examples/bin/.
#
# Модуль `vgui` компилятор V находит через ~/.vmodules/vgui (ссылка на корень
# проекта). Сборка идёт из корня проекта - родителя examples/: пути вида
# examples/NN.v и examples/bin/ ниже заданы относительно него.
#
# Аргумент - число параллельных сборок (по умолчанию nproc). Логи упавших
# сборок печатаются в конце; код выхода 1, если хоть один пример не собрался.
set -u

# Корень проекта - родитель examples/. Все вызовы v выполняем оттуда.
examples_dir="$(cd "$(dirname "$0")" && pwd)"
v_root="$(dirname "$examples_dir")"
cd "$v_root" || exit 1

jobs="${1:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p examples/bin

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

build_one() {
    local src="$1" name="$2"
    echo "Building $name..."
    if v -cc gcc "examples/$src" -o "examples/bin/$name" >"$tmpdir/$name.log" 2>&1; then
        echo 0 >"$tmpdir/$name.status"
    else
        echo 1 >"$tmpdir/$name.status"
    fi
}
export -f build_one
export tmpdir

tasks=()
for src in $(ls examples/*.v 2>/dev/null | xargs -n1 basename | sort); do
    tasks+=("$src|${src%.v}")
done

running=0
for task in "${tasks[@]}"; do
    IFS='|' read -r src name <<<"$task"
    build_one "$src" "$name" &
    running=$((running + 1))
    if [ "$running" -ge "$jobs" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done
wait

built=()
failed=()
for task in "${tasks[@]}"; do
    IFS='|' read -r src name <<<"$task"
    status="$(cat "$tmpdir/$name.status" 2>/dev/null || echo 1)"
    if [ "$status" = "0" ]; then
        built+=("$name")
    else
        echo "FAILED: $name"
        cat "$tmpdir/$name.log"
        failed+=("$name")
    fi
done

echo ""
echo "Собрано ${#built[@]} пример(ов)."

if [ ${#failed[@]} -gt 0 ]; then
    echo "Не собрано ${#failed[@]}: ${failed[*]}"
    exit 1
fi
