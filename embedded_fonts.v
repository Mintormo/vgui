module vgui

// ─── Встроенные шрифты по умолчанию ──────────────────────
// Семейство Roboto (обычный, курсив, жирный курсив) и RobotoMono (обычный,
// жирный) вшиваются в бинарник при компиляции через `$embed_file`, поэтому
// библиотеке не нужны файлы шрифтов рядом с программой или `libvgui.so`.
//
// Кто пользуется:
// - сама библиотека - только Roboto Regular и RobotoMono Regular: это
//   запасной путь `open_font_for_role` (sdl3_fonts.v), когда у роли нет ни
//   своих байтов, ни пути к файлу. Жирный, курсив и жирный курсив при этом
//   не берутся отсюда, а синтезируются SDL3_ttf из базового шрифта
//   (load_style_font);
// - приложения - остальные начертания: их можно передать в FontConfig как
//   данные, чтобы курсив был настоящим, а не синтезированным. Python получает
//   те же байты через C-ABI-мост (vgui-capi, `vgui_embedded_*_font`).
//
// Все функции возвращают пару (указатель, длина) на данные внутри бинарника:
// память живёт весь процесс, освобождать и копировать её не нужно, и шрифт,
// открытый через SDL_IOFromConstMem поверх этих байтов, может жить сколько
// угодно. Отдельного Roboto Bold в наборе нет.

const embedded_regular_ttf = $embed_file('assets/fonts/Roboto-Regular.ttf')
const embedded_italic_ttf = $embed_file('assets/fonts/Roboto-Italic.ttf')
const embedded_bold_italic_ttf = $embed_file('assets/fonts/Roboto-BoldItalic.ttf')
const embedded_mono_ttf = $embed_file('assets/fonts/RobotoMono-Regular.ttf')
const embedded_mono_bold_ttf = $embed_file('assets/fonts/RobotoMono-Bold.ttf')

// embedded_regular_font - Roboto Regular - основной шрифт интерфейса.
pub fn embedded_regular_font() (voidptr, int) {
	return embedded_regular_ttf.data(), embedded_regular_ttf.len
}

// embedded_italic_font - Roboto Italic - курсив.
pub fn embedded_italic_font() (voidptr, int) {
	return embedded_italic_ttf.data(), embedded_italic_ttf.len
}

// embedded_bold_italic_font - Roboto Bold Italic - жирный курсив.
pub fn embedded_bold_italic_font() (voidptr, int) {
	return embedded_bold_italic_ttf.data(), embedded_bold_italic_ttf.len
}

// embedded_mono_font - RobotoMono Regular - моноширинная роль по умолчанию.
pub fn embedded_mono_font() (voidptr, int) {
	return embedded_mono_ttf.data(), embedded_mono_ttf.len
}

// embedded_mono_bold_font - RobotoMono Bold - жирный моноширинный.
pub fn embedded_mono_bold_font() (voidptr, int) {
	return embedded_mono_bold_ttf.data(), embedded_mono_bold_ttf.len
}
