module vgui

// ─── Встроенный шрифт иконок Lucide ──────────────────────
// Шрифт иконок Lucide (лицензия ISC, https://lucide.dev) вшивается в бинарник
// при компиляции, чтобы виджет Icon работал без отдельного файла шрифта рядом
// с программой или `libvgui.so`. Соответствие «имя иконки -> кодовая точка» -
// в icon_names.v (генерируется из того же выпуска шрифта).

const embedded_icon_ttf = $embed_file('assets/lucide.ttf')

// embedded_icon_font возвращает (указатель, длина) байтов шрифта внутри
// бинарника: память живёт весь процесс, освобождать её не нужно.
pub fn embedded_icon_font() (voidptr, int) {
	return embedded_icon_ttf.data(), embedded_icon_ttf.len
}
