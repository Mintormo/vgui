module vgui

// Тесты Stepper (stepper.v) настоящим путём событий: щелчок по шагу делает его текущим и зовёт
// on_change, по текущему и недоступному (locked) - нет; наведение; set_current без колбэка;
// раскладка (прижатие к краям, усечение текста при нехватке места, вертикальная); measure;
// вид - снапшоты горизонтального и вертикального индикатора.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test stepper_test.v

@[heap]
struct StepLog {
mut:
	picks []int
}

// new_stepper_ui - окно с индикатором из четырёх шагов: сделан, текущий, необязательный, недоступный.
fn new_stepper_ui(width int) !(&TestUi, &Stepper, &StepLog) {
	mut t := new_test_ui(width: width, height: 80)!
	mut s := stepper(steps: ['Prepare', 'Build', 'Retouch', 'Export'], current: 1)
	s.set_state(0, .done)
	s.set_optional(2, true)
	s.set_state(3, .locked)
	mut log := &StepLog{}
	s.on_change = fn [mut log] (i int) {
		log.picks << i
	}
	mut box := create_vbox_fill()
	box.add(s)
	t.add(box)
	t.redraw()
	return t, s, log
}

// step_center - центр кружка шага i (по раскладке последнего кадра).
fn step_center(s &Stepper, i int) (f32, f32) {
	return s.slots[i].cx, s.slots[i].cy
}

fn test_stepper_click_selects_step() {
	mut t, mut s, log := new_stepper_ui(600)!
	// Щелчок по сделанному шагу - текущий 0, колбэк с индексом
	x, y := step_center(s, 0)
	t.click(x, y)
	assert s.get_current() == 0 && log.picks == [0]
	// Повторный щелчок по текущему - ничего
	t.click(x, y)
	assert log.picks == [0]
	// Недоступный шаг не кликается
	lx, ly := step_center(s, 3)
	t.click(lx, ly)
	assert s.get_current() == 0 && log.picks == [0]
	// Щелчок по тексту шага (не кружку) тоже выбирает его
	t.frame()
	t.click(s.slots[2].tx + 4, s.slots[2].ty + 4)
	assert s.get_current() == 2 && log.picks == [0, 2]
	// set_current - без колбэка, зажимается в границы
	s.set_current(99)
	assert s.get_current() == 3 && log.picks == [0, 2]
	// Неактивный виджет щелчки не принимает
	s.set_current(1)
	s.enabled = false
	t.frame()
	t.click(x, y)
	assert s.get_current() == 1
	t.close()
}

fn test_stepper_hover() {
	mut t, mut s, _ := new_stepper_ui(600)!
	x, y := step_center(s, 0)
	t.move(x, y)
	assert s.hover == 0
	// Текущий и недоступный шаги не подсвечиваются
	cx, cy := step_center(s, 1)
	t.move(cx, cy)
	assert s.hover == -1
	lx, ly := step_center(s, 3)
	t.move(lx, ly)
	assert s.hover == -1
	t.move(x, y)
	assert s.hover == 0
	t.move(x, 79) // ниже виджета (он fixed по высоте)
	assert s.hover == -1
	t.close()
}

fn test_stepper_layout_horizontal() {
	mut t, mut s, _ := new_stepper_ui(600)!
	// Всё влезает: первый шаг у левого края, последний - у правого, текст целиком
	assert s.slots.len == 4
	assert s.slots[0].start_x == s.bounds.x + s.pad
	assert abs_f32(s.slots[3].end_x - (s.bounds.x + s.bounds.w - s.pad)) < 0.5
	assert s.slots[1].title == 'Build'
	assert s.slots[2].note == tr('step.optional')
	// Шаги идут слева направо, линии между ними не короче connector_min
	for i in 0 .. 3 {
		assert s.slots[i + 1].start_x - s.slots[i].end_x >= s.connector_min - 0.5
	}
	t.close()
	// Узко: урезаются самые длинные тексты, короткие остаются целиком; совсем узко - одни кружки
	mut t2, mut s2, _ := new_stepper_ui(400)!
	assert s2.slots[1].title == 'Build', 'короткое название не урезается'
	mut cut := false
	for slot in s2.slots {
		cut = cut || slot.title.ends_with('…') || slot.note.ends_with('…')
	}
	assert cut, 'самый длинный текст урезан'
	t2.close()
	mut t3, mut s3, _ := new_stepper_ui(170)!
	for slot in s3.slots {
		assert slot.title == ''
	}
	t3.close()
}

fn test_stepper_vertical_and_measure() {
	mut t := new_test_ui(width: 240, height: 300)!
	mut s := stepper(steps: ['One', 'Two', 'Three'], vertical: true)
	mut box := create_vbox_fill()
	box.add(s)
	t.add(box)
	t.redraw()
	// Столбиком: кружки на одной вертикали, сверху вниз, расстояние - блок + линия
	assert s.slots[0].cx == s.slots[1].cx && s.slots[1].cx == s.slots[2].cx
	assert s.slots[0].cy < s.slots[1].cy && s.slots[1].cy < s.slots[2].cy
	hint := s.measure(t.win.ctx)
	assert hint.v_policy == .fixed && hint.h > 3 * s.eff_circle(t.win.ctx)
	// Горизонтальный: высота фиксирована, наименьшая ширина - кружки с линиями
	s.vertical = false
	h2 := s.measure(t.win.ctx)
	assert h2.v_policy == .fixed && h2.min_w < h2.w
	// Пустой индикатор рисуется без падений, шаги добавляются
	s.clear()
	t.redraw()
	assert s.count() == 0
	idx := s.add_step('Only', note: 'n', state: .error)
	assert idx == 0 && s.state_of(0) == .error && s.state_of(5) == .pending
	t.redraw()
	t.close()
}

fn test_stepper_snapshots() {
	// Приписка «необязательно» переводится - снапшот не должен зависеть от языка системы.
	old_locale := get_locale()
	set_locale('en')
	defer {
		set_locale(old_locale)
	}
	mut t := new_test_ui(width: 560, height: 60, theme: dark_theme())!
	mut s := stepper(steps: ['Prepare', 'Build', 'Retouch', 'Export'], current: 1)
	s.set_state(0, .done)
	s.set_note(0, '12 frames')
	s.set_state(1, .warning)
	s.set_note(1, 'settings changed')
	s.set_optional(2, true)
	s.set_state(3, .locked)
	mut box := create_vbox_fill()
	box.add(s)
	t.add(box)
	t.redraw()
	t.match_snapshot('testdata/snapshots/stepper.png', SnapshotOpts{})!
	t.close()

	mut tv := new_test_ui(width: 200, height: 200, theme: light_theme())!
	mut v := stepper(steps: ['Account', 'Payment', 'Done'], current: 2, vertical: true)
	v.set_state(0, .done)
	v.set_state(1, .error)
	v.set_note(1, 'card declined')
	mut vb := create_vbox_fill()
	vb.add(v)
	tv.add(vb)
	tv.redraw()
	tv.match_snapshot('testdata/snapshots/stepper_vertical.png', SnapshotOpts{})!
	tv.close()
}

// Потолок ширины текста: урезаются только самые длинные, всё влезает - потолок = самый длинный.
fn test_step_text_cap() {
	assert step_text_cap([f32(10), 20, 30], 100) == 30
	assert step_text_cap([f32(10), 20, 30], 50) == 20 // 10 + 20 + 20
	assert step_text_cap([f32(10), 40, 40], 50) == 20 // 10 + 20 + 20
	assert step_text_cap([f32(10), 20], 0) == 0
}
