module vgui

// ═══════════════════════════════════════════════════════
// Predefined colors
// ═══════════════════════════════════════════════════════

// Именованные базовые цвета (RGBA, 0..255). Это удобные константы для кода
// приложений и примеров; виджеты берут цвета в основном из темы (`Theme`,
// theme.v), отсюда — разве что color_transparent как «нет заливки». Порядок полей Color — r, g, b, a; a = 0 —
// полностью прозрачный.

pub const color_transparent = Color{0, 0, 0, 0}
pub const color_white = Color{255, 255, 255, 255}
pub const color_black = Color{0, 0, 0, 255}
pub const color_red = Color{255, 0, 0, 255}
pub const color_green = Color{0, 255, 0, 255}
pub const color_blue = Color{0, 0, 255, 255}
pub const color_yellow = Color{255, 255, 0, 255}
pub const color_cyan = Color{0, 255, 255, 255}
pub const color_magenta = Color{255, 0, 255, 255}
pub const color_gray = Color{128, 128, 128, 255}
pub const color_dark_gray = Color{64, 64, 64, 255}
pub const color_light_gray = Color{192, 192, 192, 255}
