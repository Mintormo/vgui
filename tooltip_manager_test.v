module vgui

// Подсказки по полю tooltip (tooltip_manager.v): показ после задержки, режим
// просмотра, скрытие кликом/уходом/попапом, перепроверка владельца под
// неподвижным курсором, подсказка предка, прозрачные верхние слои (уведомления,
// отдельный Tooltip), сон цикла до срока подсказки, разметка .vui. Часы
// подсказок подменяются (Window.tip_clock_ms) - задержка не зависит от
// скорости машины.

// TipFixture - окно с рядом: две кнопки с подсказками и подпись без неё.
struct TipFixture {
mut:
	t   &TestUi
	a   &Button
	b   &Button
	c   &Label
	row &HBox
}

fn tip_fixture() TipFixture {
	mut t := new_test_ui(width: 320, height: 120) or { panic(err) }
	t.win.tip_clock_ms = 1000
	mut a := button('A')
	a.tooltip = 'Подсказка A'
	mut b := button('B')
	b.tooltip = 'Подсказка B'
	mut c := label('C')
	mut row := create_hbox_fill()
	row.add(a)
	row.add(b)
	row.add(c)
	row.add(create_spacer(), flex: 1)
	t.add(row)
	return TipFixture{
		t:   t
		a:   a
		b:   b
		c:   c
		row: row
	}
}

// tip_hover наводит курсор на середину виджета и рисует кадр.
fn tip_hover(mut t TestUi, w &Widget) {
	r := get_widget_bounds(w)
	t.move(r.x + r.w / 2, r.y + r.h / 2)
	t.frame()
}

// tip_wait сдвигает часы подсказок на ms и рисует кадр.
fn tip_wait(mut t TestUi, ms u64) {
	t.win.tip_clock_ms += ms
	t.frame()
}

// tip_shown - текст показанной подсказки окна ('' - не показана).
fn tip_shown(t &TestUi) string {
	if !t.win.tips.showing {
		return ''
	}
	return t.win.tips.text
}

fn test_tooltip_appears_after_delay_and_hides_on_leave() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	assert tip_shown(f.t) == '', 'до задержки подсказки нет'
	tip_wait(mut f.t, u64(f.t.win.tooltip_delay_ms) - 1)
	assert tip_shown(f.t) == ''
	tip_wait(mut f.t, 1)
	assert tip_shown(f.t) == 'Подсказка A'
	// кадр с подсказкой нарисовал её поверх всего (prev_overlayish)
	assert f.t.win.prev_overlayish
	tip_hover(mut f.t, f.c)
	assert tip_shown(f.t) == '', 'над подписью без подсказки - ничего'
}

fn test_tooltip_on_disabled_widget() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	f.a.enabled = false
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка A', 'неактивность подсказку не гасит'
}

fn test_tooltip_browse_mode_shows_next_at_once() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка A'
	// соседняя кнопка сразу после показанной подсказки - без задержки
	tip_hover(mut f.t, f.b)
	assert tip_shown(f.t) == 'Подсказка B'
	// режим просмотра проходит: пустое место, пауза, снова кнопка - задержка
	tip_hover(mut f.t, f.c)
	tip_wait(mut f.t, tt_warm_ms + 1)
	tip_hover(mut f.t, f.a)
	assert tip_shown(f.t) == '', 'после паузы - снова обычная задержка'
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка A'
}

fn test_tooltip_click_dismisses_until_owner_changes() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	f.t.click_widget(f.a)
	f.t.frame()
	assert tip_shown(f.t) == '', 'клик прячет подсказку'
	tip_wait(mut f.t, 5000)
	assert tip_shown(f.t) == '', 'и она не возвращается над тем же виджетом'
	tip_hover(mut f.t, f.b)
	assert tip_shown(f.t) == '', 'после клика режима просмотра нет'
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка B'
}

fn test_tooltip_key_and_mouse_leave_hide() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	f.t.key(sdl_k_tab, 0)
	f.t.frame()
	assert tip_shown(f.t) == '', 'клавиша прячет подсказку'

	tip_hover(mut f.t, f.b)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка B'
	f.t.win.dispatch_event_with_app(&GuiEvent{ typ: .window_mouse_leave }, f.t.app)
	f.t.frame()
	assert tip_shown(f.t) == '', 'уход мыши из окна прячет подсказку'
	assert f.t.win.tips.owner == unsafe { nil }
}

fn test_tooltip_follows_text_and_visibility_without_mouse_move() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	// текст меняется кодом (новое сочетание клавиш) - подсказка сразу новая
	f.a.tooltip = 'Новая'
	f.t.frame()
	assert tip_shown(f.t) == 'Новая'
	assert f.t.win.tips.painter.text == 'Новая'
	f.a.tooltip = ''
	f.t.frame()
	assert tip_shown(f.t) == '', 'пустой tooltip гасит подсказку'
	// виджет скрыт кодом под неподвижным курсором - подсказки над его
	// старым местом нет (у отдельного Tooltip она бы осталась). Без
	// владельца кадр дерево не обходит: вернувшийся текст подхватит первое
	// движение мыши
	f.a.tooltip = 'Подсказка A'
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == 'Подсказка A'
	f.a.visible = false
	f.t.win.invalidate_all()
	f.t.frame()
	// ряд переложился: на место A под курсор съехала B - и её подсказка сразу
	// (режим просмотра), а не подсказка исчезнувшей A
	assert tip_shown(f.t) == 'Подсказка B'
}

fn test_tooltip_of_ancestor_and_nearest_wins() {
	mut t := new_test_ui(width: 320, height: 120)!
	defer {
		t.close()
	}
	t.win.tip_clock_ms = 1000
	mut lb := label('Яркость')
	mut own := button('X')
	own.tooltip = 'Своя'
	mut row := create_hbox_fill()
	row.tooltip = 'Ряд'
	row.add(lb)
	row.add(own)
	row.add(create_spacer(), flex: 1)
	t.add(row)
	tip_hover(mut t, lb)
	tip_wait(mut t, 1000)
	assert tip_shown(t) == 'Ряд', 'подпись без подсказки - подсказка ряда'
	tip_hover(mut t, own)
	assert tip_shown(t) == 'Своя', 'своя подсказка ближе подсказки ряда'
}

fn test_tooltip_blocked_by_popup_and_drag() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	tip_hover(mut f.t, f.a)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) != ''
	// открыт попап (меню, список) - подсказок нет
	owner := voidptr(f.b)
	f.t.win.ctx.set_overlay(owner, fn (mut ctx RenderContext) {}, fn (ev &GuiEvent, app &App) bool {
		return false
	}, fn (mut ctx RenderContext) {})
	f.t.frame()
	assert tip_shown(f.t) == ''
	tip_hover(mut f.t, f.b)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == '', 'пока открыт попап, подсказка не ждёт'
	f.t.win.ctx.clear_overlay(owner)
	// перетаскивание (кнопка мыши зажата) - тоже
	r := f.a.bounds
	f.t.press(r.x + 2, r.y + 2)
	sim_push_motion(f.t.win, r.x + 6, r.y + 6, sim_button_mask(.left))
	sim_pump(mut f.t.app, 0)
	tip_wait(mut f.t, 1000)
	assert tip_shown(f.t) == ''
	f.t.release(r.x + 6, r.y + 6)
}

fn test_tooltip_ignores_transparent_top_layers() {
	// Как в vraw: корень, затем отдельный Tooltip и менеджер уведомлений -
	// Window.arrange растягивает их на весь экран, но курсор они не ловят
	mut t := new_test_ui(width: 320, height: 120)!
	defer {
		t.close()
	}
	t.win.tip_clock_ms = 1000
	mut b := button('B')
	b.tooltip = 'Под слоями'
	mut row := create_hbox_fill()
	row.add(b)
	row.add(create_spacer(), flex: 1)
	t.win.add_widget(row)
	mut lone := tooltip('отдельная')
	lone.attach(row)
	t.win.add_widget(lone)
	t.win.add_widget(notification_manager())
	t.frame()
	tip_hover(mut t, b)
	tip_wait(mut t, 1000)
	assert tip_shown(t) == 'Под слоями'
	// и точечная перерисовка hover видит кнопку, а не слой уведомлений
	hit := t.win.hit_at(b.bounds.x + 2, b.bounds.y + 2)
	assert widget_object_addr(hit.hit) == voidptr(b)
}

fn test_tooltip_wait_drives_the_loop() {
	mut f := tip_fixture()
	defer {
		f.t.close()
	}
	assert f.t.app.tooltip_wait_ms() == -1, 'нечего ждать'
	tip_hover(mut f.t, f.a)
	delay := i64(f.t.win.tooltip_delay_ms)
	assert f.t.app.tooltip_wait_ms() == delay
	f.t.win.tip_clock_ms += 200
	assert f.t.app.tooltip_wait_ms() == delay - 200
	f.t.win.tip_clock_ms += 1000
	assert f.t.app.tooltip_wait_ms() == 0
	// срок настал: pump_events просит кадр, хотя событий не было
	assert f.t.app.pump_events()
	f.t.frame()
	assert tip_shown(f.t) == 'Подсказка A'
	assert f.t.app.tooltip_wait_ms() == -1, 'показанная подсказка ничего не ждёт'
}

fn test_markup_tooltip_on_any_element() {
	ui := ui_parse('vbox tooltip="Колонка"\n  label "a" tooltip="Подпись"\n  button "b" tooltip="Кнопка"\n',
		't')!
	col := unsafe { &VBox(ui.root_ptr()) }
	assert col.tooltip == 'Колонка'
	assert widget_tooltip(col.child_widgets()[0]) == 'Подпись'
	assert widget_tooltip(col.child_widgets()[1]) == 'Кнопка'
}

// Поле tooltip есть у каждого виджета, кроме служебных слоёв (Tooltip,
// ContextMenu, Notification, NotificationManager) и не-виджетов (MenuItem,
// TreeNode, Property). Проверка - при компиляции: тип без поля не
// приводится к HasTooltip. Новый виджет - добавить и сюда.
fn test_every_widget_type_has_tooltip_field() {
	with_tip := [
		HasTooltip(&Label{}),
		HasTooltip(&Button{}),
		HasTooltip(&VBox{}),
		HasTooltip(&HBox{}),
		HasTooltip(&Panel{}),
		HasTooltip(&Spacer{}),
		HasTooltip(&TextInput{}),
		HasTooltip(&CheckBox{}),
		HasTooltip(&Slider{}),
		HasTooltip(&ProgressBar{}),
		HasTooltip(&Separator{}),
		HasTooltip(&ToggleSwitch{}),
		HasTooltip(&Spinner{}),
		HasTooltip(&RadioButton{}),
		HasTooltip(&Spinbox{}),
		HasTooltip(&ComboBox{}),
		HasTooltip(&ImageView{}),
		HasTooltip(&ListBox{}),
		HasTooltip(&TabBox{}),
		HasTooltip(&Accordion{}),
		HasTooltip(&Breadcrumbs{}),
		HasTooltip(&ColorPicker{}),
		HasTooltip(&DatePicker{}),
		HasTooltip(&Splitter{}),
		HasTooltip(&DockArea{}),
		HasTooltip(&NodeEditor{}),
		HasTooltip(&CodeEditor{}),
		HasTooltip(&MarkdownView{}),
		HasTooltip(&MenuButton{}),
		HasTooltip(&MenuBar{}),
		HasTooltip(&PlotView{}),
		HasTooltip(&PropertyGrid{}),
		HasTooltip(&TableView{}),
		HasTooltip(&TreeView{}),
		HasTooltip(&Stack{}),
		HasTooltip(&Centered{}),
		HasTooltip(&WindowTitleDrag{}),
		HasTooltip(&ScrollBox{}),
		HasTooltip(&TextArea{}),
		HasTooltip(&Badge{}),
		HasTooltip(&Calendar{}),
		HasTooltip(&GridLayout{}),
		HasTooltip(&DropZone{}),
		HasTooltip(&ImageBackground{}),
		HasTooltip(&Canvas{}),
		HasTooltip(&Icon{}),
		HasTooltip(&CurveEditor{}),
		HasTooltip(&ShortcutInput{}),
	]
	// все kind_* минус 7 служебных и не-виджетов (см. комментарий выше)
	assert with_tip.len == css_max_kind - 7
	mut w := Widget(&Tooltip{})
	assert !set_widget_tooltip(mut w, 'x'), 'у самого Tooltip поля нет'
}

// Скрытая вкладка TabBox: устаревшие bounds не дают подсказки (hit_children).
fn test_tooltip_skips_inactive_tab() {
	mut active_child := &Label{
		bounds: Rect{0, 0, 100, 100}
	}
	mut stale_child := &Label{
		bounds:  Rect{0, 0, 100, 100}
		tooltip: 'со скрытой вкладки'
	}
	mut tb := &TabBox{
		bounds: Rect{0, 0, 100, 100}
	}
	tb.tabs << TabEntry{
		widget: unsafe { active_child }
	}
	tb.tabs << TabEntry{
		widget: unsafe { stale_child }
	}
	tb.active = 0
	hit := widget_tip_at(Widget(tb), 10, 10)
	assert widget_object_addr(hit.hit) == voidptr(active_child)
	assert hit.owner == unsafe { nil }
}
