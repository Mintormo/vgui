module vgui

// Менеджер подсказок окна (PROJECT.md, «Подсказки (поле tooltip)»).
//
// У каждого виджета есть поле `tooltip string` (интерфейс HasTooltip,
// widget_tree.v). Сами виджеты подсказку не рисуют и о ней не знают: её
// ведёт окно, по образцу Qt/GTK - один менеджер на окно, одна подсказка.
//
// Кто под курсором, решает тот же обход дерева, что и точечная перерисовка
// hover (Window.hit_at -> widget_tip_at): самый глубокий видимый виджет под
// точкой и ближайший к нему (он сам или предок) носитель непустого tooltip.
// Поэтому скрытые и свёрнутые виджеты (visible = false, слой Stack,
// неактивная вкладка TabBox, свёрнутая секция Accordion, строки ListBox за
// прокруткой) подсказок не дают - в отличие от отдельного виджета Tooltip,
// который смотрит на bounds своей цели, а они у скрытого виджета остаются
// старыми.
//
// Жизненный цикл:
//   - mouse_move (Window.invalidate_hover_change) -> tip_on_hover: сменился
//     владелец - таймер заново (due_at = сейчас + задержка);
//   - режим просмотра: если подсказка только что была показана (warm_until),
//     у следующего владельца она появляется сразу, без задержки;
//   - клик, колесо, клавиша (tip_on_event) прячут подсказку до смены
//     владельца (dismissed); уход мыши из окна и потеря фокуса сбрасывают всё;
//   - при открытом попапе (меню, список) и модальном диалоге подсказок нет,
//     при зажатой кнопке мыши (перетаскивание) - тоже;
//   - каждый кадр (tip_frame, начало Window.render) владелец проверяется
//     заново под неподвижным курсором: виджет могли скрыть или убрать кодом,
//     а текст - поменять (новое сочетание клавиш в подсказке);
//   - пора показать - tip_frame кладёт внутренний Tooltip в
//     ctx.pending_tooltips, рисует его окно поверх всего (tooltip_draw).
//
// Таймер без холостых кадров: пока подсказка ждёт, App.process_events спит не
// дольше, чем до её срока (App.tooltip_wait_ms), а pump_events сообщает «пора
// рисовать», когда срок наступил. Кадры во время ожидания не рисуются.
//
// Неактивность виджета подсказку не гасит (widget_at на enabled не смотрит):
// объяснить, почему элемент недоступен, - её обычная работа.

// tt_warm_ms - сколько после скрытия подсказки длится режим просмотра:
// следующая подсказка в это время появляется без задержки (как в Qt/Windows).
const tt_warm_ms = u64(500)

// TipManager - состояние подсказок одного окна (поле Window.tips).
// owner - сырой адрес владельца текущей подсказки (voidptr(&Widget)). Он
// НИКОГДА не разыменовывается, как и Window.hover_widget: виджет мог быть
// уничтожен между событиями. Текст берётся из свежего обхода дерева
// (hit_at), а owner служит только для сравнения «тот же или другой».
pub struct TipManager {
mut:
	owner      voidptr = unsafe { nil }
	text       string
	due_at     u64  // момент показа (мс часов tip_now); 0 - таймер не идёт
	showing    bool // подсказка сейчас показана
	dismissed  bool // спрятана кликом/клавишей: не показывать до смены владельца
	warm_until u64  // до этого момента новая подсказка - без задержки
	// рисовальщик: обычный Tooltip без цели, его кладёт в pending_tooltips
	// tip_frame (tooltip_draw берёт text и showing, позицию - у курсора)
	painter &Tooltip = unsafe { nil }
}

// tip_now - часы подсказок: часы интерфейса (now_ms, clock.v) или подмена теста (tip_clock_ms).
fn (w &Window) tip_now() u64 {
	if w.tip_clock_ms > 0 {
		return w.tip_clock_ms
	}
	return now_ms()
}

// hit_at - верхний (по z-порядку) видимый виджет под точкой и подсказка для
// неё (TipHit, см. widget_tip_at). Обход по верхнеуровневым виджетам окна с
// конца: последний добавленный рисуется поверх. Видимость корня проверяется
// здесь - widget_at смотрит только на детей.
fn (w &Window) hit_at(x f32, y f32) TipHit {
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root == nil } {
			continue
		}
		if !widget_is_visible(root) {
			continue
		}
		hit := widget_tip_at(root, x, y)
		if unsafe { hit.hit != nil } {
			return hit
		}
	}
	return TipHit{}
}

// tips_blocked - подсказок в окне сейчас быть не может: открыт попап
// (меню, выпадающий список - курсор работает с ним) или модальный диалог
// поверх окна (окно не принимает ввод).
fn (w &Window) tips_blocked() bool {
	return w.ctx.overlay_cb != unsafe { nil } || w.ctx.overlay_ev != unsafe { nil }
		|| w.has_modal_child
}

// tip_set_owner - курсор над подсказкой владельца owner с текстом text.
// Тот же владелец - обновить текст, таймер не трогать. Другой - спрятать
// показанную (и открыть режим просмотра), завести таймер заново: обычный
// - на tooltip_delay_ms, в режиме просмотра - «сейчас же».
fn (mut w Window) tip_set_owner(owner voidptr, text string, now u64) {
	mut m := &w.tips
	if owner == m.owner {
		m.text = text
		return
	}
	if m.showing {
		m.warm_until = now + tt_warm_ms
	}
	m.owner = owner
	m.text = text
	m.showing = false
	m.dismissed = false
	m.due_at = 0
	if owner == unsafe { nil } {
		return
	}
	m.due_at = if now < m.warm_until { now } else { now + u64(w.tooltip_delay_ms) }
	// due_at = 0 значит «таймер не идёт»: на часах, стоящих на нуле, срок
	// сдвигается на 1 мс
	if m.due_at == 0 {
		m.due_at = 1
	}
}

// tip_reset - забыть владельца совсем (уход мыши из окна, потеря фокуса,
// попап, перетаскивание). Режим просмотра тоже гаснет: следующая подсказка
// появится только после обычной задержки.
fn (mut w Window) tip_reset() {
	w.tips.owner = unsafe { nil }
	w.tips.text = ''
	w.tips.showing = false
	w.tips.dismissed = false
	w.tips.due_at = 0
	w.tips.warm_until = 0
}

// tip_on_hover - mouse_move: hit - свежий результат hit_at в точке курсора
// (его уже посчитал invalidate_hover_change). Зажатая кнопка мыши -
// перетаскивание (ползунок, выделение текста, панорама), подсказка ему мешает.
fn (mut w Window) tip_on_hover(hit TipHit, ev &GuiEvent) {
	if ev.mouse_buttons != 0 || w.tips_blocked() {
		w.tip_reset()
		return
	}
	w.tip_set_owner(voidptr(hit.owner), hit.text, w.tip_now())
}

// tip_on_event - прочие события окна (зовётся из dispatch_event_inner до
// раздачи виджетам и до оверлея: попап может событие поглотить).
// Клик, колесо, клавиша прячут подсказку до смены владельца: пользователь
// уже работает с виджетом (как в Qt). Колесо сдвигает содержимое - за ним
// идёт синтетический mouse_move, и если под курсором оказался другой
// владелец, его таймер начнётся заново.
fn (mut w Window) tip_on_event(ev &GuiEvent) {
	match ev.typ {
		.mouse_down, .mouse_dbl_click, .mouse_wheel, .key_down {
			if w.tips.owner != unsafe { nil } {
				w.tips.showing = false
				w.tips.dismissed = true
				w.tips.due_at = 0
				w.tips.warm_until = 0
			}
		}
		.window_focus_lost, .window_mouse_leave {
			w.tip_reset()
		}
		else {}
	}
}

// tip_frame - шаг подсказки в начале кадра (Window.render, до решения
// full/partial: показанная подсказка делает кадр полным). Владелец
// перепроверяется под неподвижным курсором - между событиями виджет могли
// скрыть, убрать или поменять ему текст. Когда срок настал, внутренний
// Tooltip встаёт в очередь pending_tooltips; рисует его окно после всех
// виджетов и оверлеев.
fn (mut w Window) tip_frame() {
	if w.tips.owner == unsafe { nil } {
		return
	}
	if w.tips_blocked() {
		w.tip_reset()
		return
	}
	now := w.tip_now()
	// Свежая раскладка: событие перед кадром могло переложить дерево
	// (переключение вкладки, скрытие панели) - искать по старым bounds нельзя.
	w.arrange_if_needed()
	hit := w.hit_at(w.ctx.mouse_x, w.ctx.mouse_y)
	w.tip_set_owner(voidptr(hit.owner), hit.text, now)
	mut m := &w.tips
	if m.owner == unsafe { nil } || m.dismissed || m.text.len == 0 {
		return
	}
	if !m.showing && now >= m.due_at {
		m.showing = true
	}
	if !m.showing {
		return
	}
	if m.painter == unsafe { nil } {
		m.painter = tooltip('')
	}
	m.painter.text = m.text
	m.painter.showing = true
	w.ctx.pending_tooltips << m.painter
}

// tip_wait_ms - через сколько мс подсказке этого окна пора показаться:
// -1 - ждать нечего (нет владельца, уже показана, спрятана, окно скрыто),
// 0 - срок уже настал. По нему App спит не дольше нужного.
fn (w &Window) tip_wait_ms() i64 {
	m := w.tips
	if !w.open || !w.visible || m.owner == unsafe { nil } || m.showing || m.dismissed
		|| m.due_at == 0 {
		return -1
	}
	now := w.tip_now()
	if now >= m.due_at {
		return 0
	}
	return i64(m.due_at - now)
}

// tooltip_wait_ms - ближайший срок подсказки по всем окнам и диалогам
// приложения (-1 - ни одна не ждёт). process_events ограничивает им сон в
// SDL_WaitEventTimeout, pump_events по нулю сообщает, что нужен кадр.
fn (app &App) tooltip_wait_ms() i64 {
	mut best := i64(-1)
	for w in app.windows {
		best = min_wait(best, w.tip_wait_ms())
	}
	for d in app.dialogs {
		if d.is_open() {
			best = min_wait(best, d.win.tip_wait_ms())
		}
	}
	return best
}

// min_wait - меньший из двух сроков, где -1 значит «нет срока».
fn min_wait(a i64, b i64) i64 {
	if a < 0 {
		return b
	}
	if b < 0 {
		return a
	}
	return if a < b { a } else { b }
}
