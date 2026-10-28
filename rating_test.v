module vgui

// Тесты Rating (rating.v) настоящим путём событий: щелчок ставит оценку, повторный по той же
// снимает (allow_clear), предпросмотр под курсором, клавиши, readonly, set_value без колбэка; вид -
// снапшот (звёзды fill_star).

@[heap]
struct RatingLog {
mut:
	values []int
}

fn new_rating_ui() !(&TestUi, &Rating, &RatingLog) {
	mut t := new_test_ui(width: 200, height: 60)!
	mut r := rating(value: 2)
	mut log := &RatingLog{}
	r.on_change = fn [mut log] (v int) {
		log.values << v
	}
	mut box := create_vbox_fill()
	box.add(r)
	t.add(box)
	return t, r, log
}

// star_center - середина звезды i (0..max-1)
fn star_center(r &Rating, i int) (f32, f32) {
	sr := r.star_rect(i)
	return sr.x + sr.w * 0.5, sr.y + sr.h * 0.5
}

fn test_rating_click_and_clear() {
	mut t, mut r, log := new_rating_ui()!
	x, y := star_center(r, 3)
	t.click(x, y)
	assert r.value == 4 && log.values == [4]
	t.click(x, y) // та же оценка - снять
	assert r.value == 0
	r.allow_clear = false
	t.click(x, y)
	t.click(x, y)
	assert r.value == 4
	t.close()
}

fn test_rating_hover_preview_and_keys() {
	mut t, mut r, log := new_rating_ui()!
	x, y := star_center(r, 4)
	t.move(x, y)
	assert r.hover == 5
	t.move(x, y + 100)
	t.move(1, 59) // мимо звёзд
	assert r.hover == -1
	// Фокус щелчком, дальше клавиши
	cx, cy := star_center(r, 0)
	t.click(cx, cy)
	assert r.value == 1
	t.key(sdl_k_right, 0)
	assert r.value == 2
	t.key(`5`, 0)
	assert r.value == 5
	t.key(`9`, 0) // больше max - не оценка
	assert r.value == 5
	t.key(`0`, 0)
	assert r.value == 0
	n := log.values.len
	r.set_value(3)
	assert log.values.len == n, 'set_value - без колбэка'
	// focusable = false - щелчок ставит оценку, но фокус не берёт: клавиши - не ей
	r.focusable = false
	t.key(sdl_k_escape, 0)
	cx2, cy2 := star_center(r, 1)
	t.click(cx2, cy2)
	assert r.value == 2
	t.frame()
	t.key(sdl_k_right, 0)
	assert r.value == 2, 'стрелка - не звёздам без фокуса'
	r.focusable = true
	// readonly - щелчок ничего не меняет
	r.readonly = true
	t.click(cx, cy)
	assert r.value == 2
	t.close()
}

fn test_rating_snapshot() {
	mut t := new_test_ui(width: 140, height: 40, theme: dark_theme())!
	mut r := rating(value: 3)
	mut box := create_vbox_fill()
	box.add(r)
	t.add(box)
	t.redraw()
	t.match_snapshot('testdata/snapshots/rating.png', SnapshotOpts{})!
	t.close()
}
