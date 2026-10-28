module vgui

// Тесты плавающих панелей DockArea (dock_float.v): вынос в окно и возврат кодом, двойным щелчком
// и жестом, закрытие плавающего окна и окна-владельца, сохранение и загрузка раскладки с
// плавающими окнами, перенос из плавающего окна обратно в главную область через экранные
// координаты, перезагрузка текстуры картинки в окне с другим рендерером.

// rect_center - середина прямоугольника (куда «кликнуть»).
fn rect_center(r Rect) (f32, f32) {
	return r.x + r.w * 0.5, r.y + r.h * 0.5
}

// new_dock_ui - окно 400x300 с областью на весь экран и панелями a, b (b справа от a); как в
// dock_area_test.v (каждый _test.v компилируется отдельно).
fn new_dock_ui() !(&TestUi, &DockArea, &DockPanel, &DockPanel) {
	mut t := new_test_ui(width: 400, height: 300)!
	mut da := dock_area()
	a := dock_panel('a', 'Alpha', label('A'))
	b := dock_panel('b', 'Beta', label('B'))
	da.add_panel(a)
	da.dock(b, .right, target: a)
	t.add(da)
	return t, da, a, b
}

// float_pump - шаг цикла приложения: события и app.post (там создаются и убираются плавающие
// окна), затем кадр (раскладка главной области заказывает окна).
fn float_pump(mut t TestUi) {
	for _ in 0 .. 3 {
		t.app.pump_events()
		t.app.render_all()
	}
}

// open_windows - открытые окна приложения.
fn open_windows(t &TestUi) []&Window {
	return t.app.windows.filter(it.open)
}

// float_win - окно ОС плавающей панели p.
fn float_win(da &DockArea, p &DockPanel) &Window {
	f := da.float_of(p) or { panic('панель не плавает') }
	assert !isnil(f.win), 'окно ещё не создано'
	return f.win
}

fn test_float_panel_and_dock_back() {
	mut t, mut da, a, b := new_dock_ui()!
	before := da.save_layout()
	da.float_panel(b)
	assert da.is_floating(b) && da.is_open(b) && !da.is_floating(a)
	assert da.save_layout().starts_with('[*a]+F(')
	float_pump(mut t)
	assert open_windows(t).len == 2
	w := float_win(da, b)
	assert w.tool_owner == t.win
	assert w.config.title == 'Beta'
	assert da.is_active(b)
	// Назад - на прежнее место; опустевшее окно убирается из приложения
	da.dock_back(b)
	assert !da.is_floating(b)
	assert da.save_layout() == before
	float_pump(mut t)
	assert t.app.windows.len == 1
	t.close()
}

fn test_float_window_close_returns_panels() {
	mut t, mut da, a, b := new_dock_ui()!
	da.float_panel(b)
	float_pump(mut t)
	mut w := float_win(da, b)
	w.close() // крестик ОС
	assert !da.is_floating(b) && da.is_open(b)
	float_pump(mut t)
	assert t.app.windows.len == 1
	_ = a
	t.close()
}

fn test_float_closes_with_owner_and_does_not_keep_app() {
	mut t, mut da, _, b := new_dock_ui()!
	da.float_panel(b)
	float_pump(mut t)
	mut fw := float_win(da, b)
	// Главное окно закрыли - служебное закрывается с ним, приложение не держит
	t.app.running = true
	t.win.close()
	t.app.update_running()
	assert !fw.open
	assert !t.app.running
	t.close()
}

fn test_float_layout_save_load() {
	mut t, mut da, a, b := new_dock_ui()!
	c := dock_panel('c', 'Gamma', label('C'))
	da.dock(c, .center, target: b)
	da.float_panel(b)
	float_pump(mut t)
	saved := da.save_layout()
	assert saved.contains('+F(') && saved.contains('[*b]')
	// Всё вернуть, затем загрузить: b снова в плавающем окне с той же геометрией
	da.dock_back(b)
	float_pump(mut t)
	assert t.app.windows.len == 1
	da.load_layout(saved)!
	assert da.is_floating(b) && !da.is_floating(a) && !da.is_floating(c)
	float_pump(mut t)
	assert open_windows(t).len == 2
	assert da.save_layout() == saved
	// Битый хвост - ошибка, раскладка прежняя
	if _ := da.load_layout('[*a]+F(1,2)[*b]') {
		assert false
	}
	assert da.is_floating(b)
	t.close()
}

fn test_float_by_double_click_and_back() {
	mut t, mut da, _, b := new_dock_ui()!
	gb := da.group_of(b) or { panic('b') }
	x, y := rect_center(gb.tab_rects[0])
	t.dbl_click(x, y)
	assert da.is_floating(b)
	float_pump(mut t)
	// Двойной щелчок по вкладке в плавающем окне - назад
	mut w := float_win(da, b)
	f := da.float_of(b) or { panic('f') }
	fg := f.area.group_of(b) or { panic('fg') }
	fx, fy := rect_center(fg.tab_rects[0])
	sim_click(mut t.app, w, fx, fy, .left, 1, 0)
	sim_click(mut t.app, w, fx, fy, .left, 2, 0)
	assert !da.is_floating(b) && da.is_open(b)
	t.close()
}

fn test_float_by_dragging_tab_out_of_window() {
	mut t, mut da, _, b := new_dock_ui()!
	gb := da.group_of(b) or { panic('b') }
	x, y := rect_center(gb.tab_rects[0])
	// Отпустили за пределами окна (захват мыши ведёт жест и там)
	t.drag(x, y, 600, -80)
	assert da.is_floating(b)
	float_pump(mut t)
	assert open_windows(t).len == 2
	t.close()
}

fn test_drag_from_float_back_into_main_area() {
	mut t, mut da, a, b := new_dock_ui()!
	t.win.set_position(0, 0)
	da.float_panel(b, x: 1000, y: 0)
	float_pump(mut t)
	mut w := float_win(da, b)
	wx, _ := w.position()
	if wx != 1000 {
		// Видеодрайвер не хранит позиции окон - экранных координат нет, перенос между окнами
		// проверить нельзя (как на Wayland)
		t.close()
		return
	}
	f := da.float_of(b) or { panic('f') }
	fg := f.area.group_of(b) or { panic('fg') }
	fx, fy := rect_center(fg.tab_rects[0])
	ga := da.group_of(a) or { panic('a') }
	// Точка главного окна (центр содержимого a) в координатах плавающего окна
	cx, cy := rect_center(ga.content)
	sim_drag(mut t.app, w, fx, fy, cx - 1000, cy, 8, .left, 0)
	assert !da.is_floating(b) && da.is_open(b)
	gb := da.group_of(b) or { panic('b') }
	assert dock_same(gb, ga), 'b - вкладкой в группу a'
	float_pump(mut t)
	assert t.app.windows.len == 1
	t.close()
}

// Картинка переехала в окно с другим рендерером - текстура загружается заново (belongs_to), а не
// рисуется чужой.
fn test_float_reloads_image_texture() {
	mut t := new_test_ui(width: 400, height: 300)!
	mut da := dock_area()
	a := dock_panel('a', 'Alpha', label('A'))
	mut iv := image_view_file('testdata/snapshots/dock_area.png')
	img := dock_panel('img', 'Image', iv)
	da.add_panel(a)
	da.dock(img, .right, target: a)
	t.add(da)
	t.frame()
	assert iv.texture.belongs_to(&t.win.ctx)
	da.float_panel(img)
	float_pump(mut t)
	w := float_win(da, img)
	assert iv.texture.belongs_to(&w.ctx), 'текстура - рендерера плавающего окна'
	t.close()
}

// dock() в область плавающего окна снимает панель с главной области: панель не бывает открыта
// в двух окнах сразу.
fn test_float_area_dock_takes_panel_from_main() {
	mut t, mut da, _, b := new_dock_ui()!
	c := dock_panel('c', 'Gamma', label('C'))
	da.dock(c, .center, target: b)
	da.float_panel(b)
	float_pump(mut t)
	f := da.float_of(b) or { panic('f') }
	mut fa := f.area
	fa.dock(c, .bottom, target: b)
	assert da.group_of(c) == none, 'c ушла из главной области'
	assert da.is_floating(c)
	t.close()
}
