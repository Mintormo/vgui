module vgui

// ═══════════════════════════════════════════════════════
// WindowTitleDrag — container widget that enables
// window dragging when the user clicks and drags
// on empty space within its bounds.
//
// Double-click on empty space toggles maximize/restore.
//
// Child widgets (labels, spacers) are placed inside.
// Buttons should be placed OUTSIDE (in the parent HBox).
//
// Multiple WindowTitleDrag widgets can exist in a window.
// Each registers its bounds as a draggable region for
// SDL's hit-test callback.
// ═══════════════════════════════════════════════════════
//
// Файл нужен для безрамочных окон со своим заголовком (examples/46_borderless_window.v;
// сама механика перетаскивания - borderless.v). Сам виджет перетаскиванием не занимается:
// в draw() он лишь сообщает окну свой прямоугольник (ctx.pending_drag_rects и
// ctx.pending_titlebar_rects), а Window после отрисовки кадра регистрирует эти прямоугольники
// в borderless-хит-тесте SDL. Всё остальное (раскладка, отрисовка и события детей) делегируется
// внутреннему BoxLayout, как у HBox/VBox. Для hit-testing/обхода дерева тип описан в
// widget_tree.v (bounds_of/set_bounds/child_widgets).

// WindowTitleDrag - строка-заголовок: BoxLayout (горизонтальный по умолчанию) + флаг видимости.
// ВНИМАНИЕ: `visible` здесь - собственное поле виджета; одноимённое box.visible внутри
// BoxLayout - отдельное (см. HasVisibility в widget_tree.v).
pub struct WindowTitleDrag {
pub mut:
	type_tag int = kind_window_title_drag // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	tooltip  string  // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	box      BoxLayout
	visible  bool = true
}

// ─── Constructors ──────────────────────────────────────

// window_title_drag создаёт горизонтальную строку заголовка (дети идут слева направо).
// Нулевые bounds = «не заданы»: при первом arrange() растянутся на весь экран окна.
pub fn window_title_drag() &WindowTitleDrag {
	return &WindowTitleDrag{
		box: BoxLayout{
			bounds:  Rect{0, 0, 0, 0}
			dir:     .horizontal
			spacing: 0
			pad:     0
		}
	}
}

// window_title_drag_vertical - то же, но дети идут сверху вниз (вертикальная полоса заголовка).
pub fn window_title_drag_vertical() &WindowTitleDrag {
	return &WindowTitleDrag{
		box: BoxLayout{
			bounds:  Rect{0, 0, 0, 0}
			dir:     .vertical
			spacing: 0
			pad:     0
		}
	}
}

// ─── Public API (same as HBox) ─────────────────────────

// add - как HBox.add: без параметров естественный размер,
// flex: n - доля свободного места
pub fn (mut d WindowTitleDrag) add(widget &Widget, p LayoutParams) {
	d.box.children << p.to_entry(widget)
}

pub fn (mut d WindowTitleDrag) set_spacing(s f32) {
	d.box.spacing = s
}

pub fn (mut d WindowTitleDrag) set_padding(p f32) {
	d.box.pad = p
}

pub fn (mut d WindowTitleDrag) set_bg(c Color) {
	d.box.bg = c
}

pub fn (mut d WindowTitleDrag) set_panel_bg() {
	d.box.use_panel_bg = true
}

// ─── Drawing ───────────────────────────────────────────

// arrange раскладывает детей внутри box. Если bounds ещё не выданы
// родителем (is_bounds_unset), занимает весь экран окна.
pub fn (mut d WindowTitleDrag) arrange(mut ctx RenderContext) {
	if !d.visible {
		return
	}
	if is_bounds_unset(d.box.bounds) {
		d.box.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	d.box.arrange(mut ctx)
}

// draw сообщает окну свою область для хит-теста и рисует детей. Список pending_* окно
// очищает каждый кадр перед отрисовкой виджетов, поэтому регистрация делается заново в
// каждом draw(). Скрытый виджет не регистрируется - перетаскивать за него нельзя.
pub fn (mut d WindowTitleDrag) draw(mut ctx RenderContext) {
	if !d.visible {
		return
	}

	// Register our bounds as a drag rect for the borderless hit-test.
	// Неактивная строка (box.enabled, enabled.v) окно не перетаскивает.
	if ctx.is_enabled(d.box.enabled) {
		ctx.pending_drag_rects << d.box.bounds
		// Also register for double-click detection (covers the full titlebar strip).
		ctx.pending_titlebar_rects << d.box.bounds
	}

	d.box.draw_impl(mut ctx)
}

// ─── Events ────────────────────────────────────────────

// handle_event отдаёт событие детям (кнопки управления окном внутри строки работают);
// возвращает true, только если его обработал ребёнок.
pub fn (mut d WindowTitleDrag) handle_event(event &GuiEvent, app &App) bool {
	if !d.visible {
		return false
	}

	// Let children handle first
	if d.box.event_impl(event, app) {
		return true
	}

	// We don't handle drag ourselves — SDL hit-test does it.
	// Double-click maximize/restore is handled in sdl2_app.v process_events
	// (файла sdl2_app.v в репозитории больше нет: двойной щелчок обрабатывает
	// borderless.v - borderless_check_dbl_click)
	// because SDL hit-test intercepts clicks in drag zones before they reach widgets.
	return false
}
