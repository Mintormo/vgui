#!/bin/bash

OUTPUT_FILE="all.txt"

> "$OUTPUT_FILE"

count=0

# Рекурсивный поиск .v файлов с помощью find
find . -name "*.v" -type f ! -name "$OUTPUT_FILE" | sort | while read -r file; do
    echo "========================================" >> "$OUTPUT_FILE"
    echo "// Файл: $file" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    count=$((count + 1))
    echo "Добавлен: $file"
done

echo "-----------------------------------"
echo "Готово! Результат сохранён в: $OUTPUT_FILE"
