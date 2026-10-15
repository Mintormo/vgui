module vgui

// Calendar (аудит 2026-10, 2.13): хит-тест по высоте шрифта кадра, drill_up без смены
// вида не шлёт on_view_change, клавиатура при фокусе. Без окна и SDL.
//
// Запуск (из корня vgui): v test calendar_test.v

struct CalLog {
mut:
	events []string
}

fn test_drill_up_fires_only_on_view_change() {
	mut c := calendar_new()
	mut log := &CalLog{}
	c.on_view_change = fn [mut log] (v CalendarView) {
		log.events << '${v}'
	}
	c.drill_up()
	c.drill_up() // уже годовой вид - события нет
	assert log.events == ['year']
}

// Хит-тест месяца берёт высоту шрифта последнего кадра: с крупным шрифтом точка,
// попадающая в строку дней недели, днём не считается.
fn test_hit_month_day_uses_frame_font_height() {
	mut c := calendar_new()
	c.year, c.month = 2026, 10
	c.bounds = Rect{0, 0, 280, 300}
	c.font_h = 30
	// 1 октября 2026 - четверг (колонка 3, x = 125). Строка дней недели теперь высотой
	// 38: точка на 30 px ниже шапки ещё в ней
	_, _, d := c.hit_month_day(125, cal_hdr_h + 30)
	assert d == 0
	_, _, d2 := c.hit_month_day(125, cal_hdr_h + 45)
	assert d2 > 0
}

fn test_keyboard_moves_and_selects() {
	mut c := calendar_new()
	c.year, c.month = 2026, 1
	c.focused = true
	mut log := &CalLog{}
	c.on_select = fn [mut log] (y int, m int, d int) {
		log.events << '${y}-${m}-${d}'
	}
	key := fn (code int) GuiEvent {
		return GuiEvent{
			typ:     .key_down
			keycode: code
		}
	}
	assert c.on_key(key(sdl_k_right)) // нет выбора - 1-е число
	assert c.sel_day == 1
	assert c.on_key(key(sdl_k_left)) // 31 декабря 2025
	assert c.sel_year == 2025 && c.sel_month == 12 && c.sel_day == 31
	assert c.year == 2025 && c.month == 12
	assert c.on_key(key(sdl_k_pagedown)) // 31 января 2026
	assert c.on_key(key(sdl_k_pagedown)) // 28 февраля 2026
	assert c.sel_month == 2 && c.sel_day == 28
	assert c.on_key(key(sdl_k_return))
	assert log.events == ['2026-2-28']
	assert !c.on_key(key(sdl_k_tab))
}
