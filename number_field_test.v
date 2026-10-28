module vgui

// Тесты NumberField (number_field.v) настоящим путём событий: протяжка (от точки нажатия, Shift -
// точнее, Ctrl - кратно шагу, зажим в границы), щелчок - ввод с клавиатуры (Enter, Esc, запятая,
// не число, щелчок мимо - применить), стрелки, set_value без колбэка, свой текст.

// NfLog - вызовы колбэков (в куче: замыкание V захватывает копию переменной).
@[heap]
struct NfLog {
mut:
	changes []f64
	commits []f64
}

// new_nf_ui - окно с полем (0..10, шаг 0.1, 8 px на шаг) и кнопкой под ним (щелчок мимо поля).
fn new_nf_ui() !(&TestUi, &NumberField, &NfLog, &Button) {
	mut t := new_test_ui(width: 300, height: 120)!
	mut nf := number_field(value: 5, min: 0, max: 10, step: 0.1, digits: 2)
	mut log := &NfLog{}
	nf.on_change = fn [mut log] (v f64) {
		log.changes << v
	}
	nf.on_commit = fn [mut log] (v f64) {
		log.commits << v
	}
	mut other := button('other')
	mut box := create_vbox_fill()
	box.add(nf)
	box.add(other)
	t.add(box)
	return t, nf, log, other
}

fn nf_center(nf &NumberField) (f32, f32) {
	return nf.bounds.x + nf.bounds.w * 0.5, nf.bounds.y + nf.bounds.h * 0.5
}

fn near(a f64, b f64) bool {
	d := a - b
	return d < 1e-9 && d > -1e-9
}

fn test_number_field_drag() {
	mut t, mut nf, log, _ := new_nf_ui()!
	x, y := nf_center(nf)
	// 40 px вправо = 5 шагов по 0.1
	t.drag(x, y, x + 40, y)
	assert near(nf.value, 5.5)
	assert log.changes.len > 1, 'значение меняется по ходу протяжки'
	assert log.commits.len == 1 && near(log.commits[0], 5.5)
	assert !nf.editing, 'протяжка - не ввод'
	// Влево далеко за границу - зажато в min
	t.drag(x, y, x - 1000, y)
	assert near(nf.value, 0)
	// Shift - в 10 раз точнее: 80 px = 1 шаг
	sim_drag(mut t.app, t.win, x, y, x + 80, y, 8, .left, sdl_kmod_shift)
	assert near(nf.value, 0.1)
	// Ctrl - кратно шагу (от 0.1 на 3.5 px ≈ 0.04 - округление до 0.1)
	nf.set_value(1.23)
	sim_drag(mut t.app, t.win, x, y, x + 12, y, 4, .left, sdl_kmod_ctrl)
	assert near(nf.value, 1.4)
	t.close()
}

fn test_number_field_click_to_type() {
	mut t, mut nf, log, other := new_nf_ui()!
	x, y := nf_center(nf)
	t.click(x, y)
	assert nf.editing
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('2,5')
	t.key(sdl_k_return, 0)
	assert !nf.editing && near(nf.value, 2.5)
	assert log.commits.last() == 2.5
	// Esc - без правки
	t.click(x, y)
	t.type_text('9')
	t.key(sdl_k_escape, 0)
	assert !nf.editing && near(nf.value, 2.5)
	// Не число - без правки
	t.click(x, y)
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('-')
	t.key(sdl_k_return, 0)
	assert near(nf.value, 2.5)
	// Вне границ - зажато; щелчок мимо поля применяет введённое
	t.click(x, y)
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('99')
	ox, oy := other.bounds.x + 5, other.bounds.y + 5
	t.click(ox, oy)
	t.frame()
	assert !nf.editing && near(nf.value, 10)
	t.close()
}

fn test_number_field_keys_set_value_and_format() {
	mut t, mut nf, log, _ := new_nf_ui()!
	x, y := nf_center(nf)
	t.click(x, y) // фокус (и ввод) ...
	t.key(sdl_k_escape, 0) // ... без ввода: фокус у поля
	t.key(sdl_k_right, 0)
	assert near(nf.value, 5.1)
	t.key(sdl_k_down, sdl_kmod_shift)
	assert near(nf.value, 5.09)
	// set_value кодом - без колбэков
	n := log.changes.len
	nf.set_value(3)
	assert log.changes.len == n
	assert nf.text() == '3.00' // показ - digits знаков; при вводе - без хвостовых нулей
	nf.format = fn (v f64) string {
		return '${v:.0f} K'
	}
	assert nf.text() == '3 K'
	nf.set_range(10, 0) // границы наоборот - меняются местами
	assert nf.min == 0 && nf.max == 10
	t.close()
}

// Разбор и текст ввода (перенесены из numedit_test.v vraw вместе с самим разбором).
fn test_number_field_parse_and_edit_text() {
	for s in ['', '-', '+', '1', '-1.5', '0,25', '.5', '12.'] {
		assert nf_number_prefix(s), s
	}
	for s in ['a', '1a', '1.2.3', '1,2.3', '--1', '1-', '5 K', '1e3'] {
		assert !nf_number_prefix(s), s
	}
	assert nf_parse('1.5')? == 1.5
	assert nf_parse('-0,75')? == -0.75
	assert nf_parse(' 5500 ')? == 5500
	assert nf_parse('+2')? == 2
	assert nf_parse('.5')? == 0.5
	for bad in ['', '-', '.', 'abc'] {
		assert nf_parse(bad) == none, bad
	}
	assert nf_edit_text(1.5, 2) == '1.5'
	assert nf_edit_text(2, 2) == '2'
	assert nf_edit_text(-0.70, 2) == '-0.7'
	assert nf_edit_text(-0.001, 2) == '0'
	assert nf_edit_text(42.6, 0) == '43'
}
