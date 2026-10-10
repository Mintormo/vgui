module vgui

// Icon без явного цвета рисуется цветом темы: поле color по умолчанию -
// Color{0, 0, 0, 0} (a == 0). У Color альфа по умолчанию 255, поэтому без
// явного значения иконка была непрозрачно-чёрной на любой теме.
fn test_icon_default_color_follows_theme() {
	ic := icon('house')
	assert ic.color.a == 0
	mut ic2 := icon('house')
	ic2.set_color(Color{10, 20, 30, 255})
	assert ic2.color == Color{10, 20, 30, 255}
}
