module vgui

// Файл stepper.v: Stepper - индикатор шагов пошагового процесса (мастера): ряд кружков с
// номерами, соединённых линиями, у каждого - название и необязательная подпись под ним.
// Как Stepper в Material/Ant Design или полоса этапов в программах вроде Helicon Focus.
//
// Модель - список шагов StepItem и номер текущего шага current. Состояние шага (StepState)
// и «текущий» - НЕЗАВИСИМЫ: текущий - где пользователь сейчас (кружок с ореолом, жирное
// название), состояние - что с шагом (сделан, требует внимания, ошибка, недоступен). Так
// текущий шаг может быть и «устаревшим» (warning), и «сделанным».
//
// Вид кружка по состоянию:
//   pending - кольцо цвета step_pending с номером (у текущего - заливка step_active);
//   done    - заливка step_done с галочкой;
//   warning - заливка warning с «!»;
//   error   - заливка error_color с крестиком;
//   locked  - бледное кольцо с замком, щелчок не принимается.
// Вместо номера можно показать значок Lucide (StepItem.icon). Необязательный шаг
// (optional) получает приписку «необязательно» (перевод tr('step.optional')) в подписи.
// Линия к следующему шагу - цвета step_line_done, если шаг сделан, иначе step_line.
//
// Мышь: щелчок по шагу (кружку или тексту) делает его текущим и зовёт on_change(индекс);
// по текущему и по недоступному (locked) шагу щелчок не срабатывает. Над кликабельным шагом -
// курсор «рука» и подсветка. set_current кодом колбэк не вызывает (как у Rating: виджет
// обычно зеркалит модель приложения). Клавиатурного фокуса нет намеренно (как у
// Breadcrumbs): у мастера свои сочетания «Далее/Назад» в приложении.
//
// Раскладка (layout, каждый кадр в draw - дёшево и верно при смене размера):
//   горизонтально - шаги прижаты к краям, свободное место делится поровну между линиями;
//     не влезает - сначала урезаются самые длинные тексты (с «…»), а если места под текст
//     не осталось совсем - видны одни кружки;
//   vertical - шаги столбиком, линия между кружками вертикальная, текст справа.
// Размеры: circle_size (0 - из темы, eff_step_circle_size, 24), connector_min - наименьшая
// длина линии между шагами. measure() - в layout_measure.v.
//
// Цвета и размер - поля темы step_* (eff_step_*: по умолчанию акцент, рамки, текст темы),
// в CSS - тип `stepper` (css_props.v; PROJECT.md, «Stepper»). Рисование - только примитивы
// RenderContext (PROJECT.md, «Бэкенд рисования»). Тег типа kind_stepper - widget_kinds.v.

// Отступы раскладки: кружок -> текст, линия -> соседние шаги, заголовок -> подпись.
const step_text_gap = f32(8)
const step_line_gap = f32(6)
const step_note_gap = f32(2)
// Меньше этой ширины текст шага не показывается вовсе (одни «…» бесполезны).
const step_min_text_w = f32(14)

// StepState - что с шагом. Не путать с «текущим» шагом (Stepper.current).
pub enum StepState {
	pending // ещё не сделан: номер в кольце
	done    // сделан: галочка на заливке
	warning // требует внимания (например, устарел после правок раньше): «!»
	error   // ошибка: крестик
	locked  // недоступен (не выполнены предыдущие): замок, щелчок не принимается
}

// StepItem - один шаг: название, подпись под ним (note, может быть пустой), состояние,
// признак необязательного шага и значок Lucide вместо номера (icon, "" - номер).
pub struct StepItem {
pub mut:
	title    string
	note     string
	state    StepState
	optional bool
	icon     string
}

// StepSlot - место шага на экране, пересчитывается в layout() каждый кадр.
struct StepSlot {
mut:
	cx      f32 // центр кружка
	cy      f32
	start_x f32    // левый край шага (кружок) и правый край его содержимого -
	end_x   f32    // от них отступают линии в горизонтальной раскладке
	tx      f32    // левый край текста
	ty      f32    // верх строки заголовка
	title   string // заголовок и подпись после усечения под ширину
	note    string
	hit     Rect // зона наведения и щелчка
}

// StepMetrics - вертикальные размеры шага, общие для measure() и layout(): высота строки
// заголовка и подписи, высота «линии кружка» (max кружка и заголовка) и всего блока шага.
struct StepMetrics {
	cs       f32 // диаметр кружка
	title_h  f32
	note_h   f32
	line_h   f32
	block_h  f32
	has_note bool
}

// Stepper - индикатор шагов. Цвета - из темы (поля step_*), размер кружка - circle_size или тема.
@[heap]
pub struct Stepper {
pub mut:
	type_tag      int = kind_stepper // тег типа, см. widget_tag.v
	css           CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds        Rect
	visible       bool = true
	enabled       bool = true
	tooltip       string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd           &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	steps         []StepItem
	current       int  // текущий шаг (0..steps.len-1)
	vertical      bool // шаги столбиком
	circle_size   f32  // диаметр кружка; 0 - из темы (eff_step_circle_size)
	connector_min f32      = 24           // наименьшая длина линии между шагами
	pad           f32      = 4            // внутренний отступ по краям виджета
	on_change     fn (int) = unsafe { nil } // щелчок по шагу: новый текущий шаг
mut:
	hover int = -1 // кликабельный шаг под курсором, -1 - нет
	slots []StepSlot
}

// StepperConfig - параметры stepper(): названия шагов, текущий шаг, вертикальная раскладка.
@[params]
pub struct StepperConfig {
pub:
	steps    []string
	current  int
	vertical bool
}

// stepper создаёт индикатор шагов: stepper(steps: ['Подготовка', 'Сборка', 'Экспорт']).
pub fn stepper(cfg StepperConfig) &Stepper {
	mut s := &Stepper{
		vertical: cfg.vertical
	}
	for title in cfg.steps {
		s.steps << StepItem{
			title: title
		}
	}
	s.current = clamp_int(cfg.current, 0, max_int(s.steps.len - 1, 0))
	return s
}

// StepConfig - необязательные свойства шага для add_step: add_step('Ретушь', optional: true).
@[params]
pub struct StepConfig {
pub:
	note     string
	state    StepState
	optional bool
	icon     string
}

// ─── Публичный API ─────────────────────────────────────

// add_step дописывает шаг в конец и возвращает его индекс.
pub fn (mut s Stepper) add_step(title string, cfg StepConfig) int {
	widget_changed()
	s.steps << StepItem{
		title:    title
		note:     cfg.note
		state:    cfg.state
		optional: cfg.optional
		icon:     cfg.icon
	}
	return s.steps.len - 1
}

// clear удаляет все шаги; текущий - 0.
pub fn (mut s Stepper) clear() {
	widget_changed()
	s.steps.clear()
	s.slots.clear()
	s.current = 0
	s.hover = -1
}

// count - число шагов.
pub fn (s &Stepper) count() int {
	return s.steps.len
}

// has_step - есть ли шаг с индексом i (сеттеры с неверным индексом молча ничего не делают).
fn (s &Stepper) has_step(i int) bool {
	return i >= 0 && i < s.steps.len
}

// set_current - текущий шаг кодом (зажимается в границы); колбэк не вызывается.
pub fn (mut s Stepper) set_current(i int) {
	widget_changed()
	s.current = clamp_int(i, 0, max_int(s.steps.len - 1, 0))
}

pub fn (s &Stepper) get_current() int {
	return s.current
}

pub fn (mut s Stepper) set_title(i int, title string) {
	widget_changed()
	if s.has_step(i) {
		s.steps[i].title = title
	}
}

// set_note - подпись под названием шага ("" - без подписи).
pub fn (mut s Stepper) set_note(i int, note string) {
	widget_changed()
	if s.has_step(i) {
		s.steps[i].note = note
	}
}

pub fn (mut s Stepper) set_state(i int, state StepState) {
	widget_changed()
	if s.has_step(i) {
		s.steps[i].state = state
	}
}

// state_of - состояние шага i (неверный индекс - pending).
pub fn (s &Stepper) state_of(i int) StepState {
	return if s.has_step(i) { s.steps[i].state } else { StepState.pending }
}

// set_optional - необязательный шаг: в подписи приписка «необязательно».
pub fn (mut s Stepper) set_optional(i int, optional bool) {
	widget_changed()
	if s.has_step(i) {
		s.steps[i].optional = optional
	}
}

// set_icon - значок Lucide вместо номера в кружке ("" - номер). На сделанном, «!» и ошибке
// значок состояния важнее и показывается он.
pub fn (mut s Stepper) set_icon(i int, name string) {
	widget_changed()
	if s.has_step(i) {
		s.steps[i].icon = name
	}
}

// is_clickable - можно ли щёлкнуть шаг i: виджет активен, шаг есть, он не текущий и не locked.
fn (s &Stepper) is_clickable(i int) bool {
	if !s.enabled || !s.has_step(i) || i == s.current {
		return false
	}
	return s.steps[i].state != .locked
}

// ─── Шрифты и размеры ──────────────────────────────────

// title_font - шрифт названия. Меряем всегда жирным: текущий шаг рисуется жирным, и ширина
// не должна прыгать при смене текущего.
fn step_title_font(ctx &RenderContext, bold bool) voidptr {
	return ctx.get_font_immut(if bold { FontStyle.bold } else { FontStyle.regular }, 0)
}

// step_note_font - подпись на 2 пункта мельче текста поддерева, но не мельче 8.
fn step_note_font(ctx &RenderContext) voidptr {
	return ctx.get_font_immut(.regular, max_int(ctx.default_font_size() - 2, 8))
}

// note_text - что написано под названием шага i: подпись и приписка «необязательно».
fn (s &Stepper) note_text(i int) string {
	st := s.steps[i]
	if !st.optional {
		return st.note
	}
	opt := tr('step.optional')
	return if st.note.len > 0 { '${st.note} · ${opt}' } else { opt }
}

// eff_circle - диаметр кружка: свой или из темы.
fn (s &Stepper) eff_circle(ctx &RenderContext) f32 {
	return if s.circle_size > 0 { s.circle_size } else { ctx.theme.eff_step_circle_size() }
}

// metrics - вертикальные размеры шага. Кружок центрирован по строке заголовка, подпись - под
// заголовком (может опускаться ниже кружка). Без подписей у всех шагов блок = линия кружка.
fn (s &Stepper) metrics(ctx &RenderContext) StepMetrics {
	cs := s.eff_circle(ctx)
	title_h := ctx.font_height_of(step_title_font(ctx, true))
	note_h := ctx.font_height_of(step_note_font(ctx))
	mut has_note := false
	for i in 0 .. s.steps.len {
		if s.note_text(i).len > 0 {
			has_note = true
			break
		}
	}
	line_h := max_f32(cs, title_h)
	// Низ подписи от верха блока: заголовок центрирован в линии кружка, подпись под ним.
	title_top := (line_h - title_h) * 0.5
	note_bottom := title_top + title_h + step_note_gap + note_h
	block_h := if has_note { max_f32(line_h, note_bottom) } else { line_h }
	return StepMetrics{
		cs:       cs
		title_h:  title_h
		note_h:   note_h
		line_h:   line_h
		block_h:  block_h
		has_note: has_note
	}
}

// text_width - ширина текста шага i без усечения: шире из названия (жирным) и подписи.
fn (s &Stepper) text_width(ctx &RenderContext, i int) f32 {
	tw := ctx.measure_text_with_font(s.steps[i].title, step_title_font(ctx, true)).x
	nw := ctx.measure_text_with_font(s.note_text(i), step_note_font(ctx)).x
	return max_f32(tw, nw)
}

// natural_size - желаемый размер без усечения (для measure): горизонтально - шаги с
// двойной наименьшей линией между ними, вертикально - столбик с наименьшими линиями.
// Второе значение - наименьшая ширина (горизонтально - одни кружки с линиями).
fn (s &Stepper) natural_size(ctx &RenderContext) (f32, f32, f32) {
	m := s.metrics(ctx)
	n := s.steps.len
	if n == 0 {
		return 0, 0, 0
	}
	gaps := f32(n - 1)
	if s.vertical {
		mut text_w := f32(0)
		for i in 0 .. n {
			text_w = max_f32(text_w, s.text_width(ctx, i))
		}
		w := m.cs + step_text_gap + text_w + s.pad * 2
		h := f32(n) * m.block_h + gaps * s.connector_min + s.pad * 2
		return w, h, m.cs + s.pad * 2
	}
	mut content := f32(0)
	for i in 0 .. n {
		content += m.cs + step_text_gap + s.text_width(ctx, i)
	}
	w := content + gaps * s.connector_min * 2 + s.pad * 2
	min_w := f32(n) * m.cs + gaps * s.connector_min + s.pad * 2
	return w, m.block_h + s.pad * 2, min_w
}

// ─── Раскладка ─────────────────────────────────────────

// layout пересчитывает slots под текущие bounds и шаги (вызывается из draw каждый кадр).
fn (mut s Stepper) layout(ctx &RenderContext) {
	s.slots.clear()
	if s.steps.len == 0 {
		return
	}
	m := s.metrics(ctx)
	if s.vertical {
		s.layout_vertical(ctx, m)
	} else {
		s.layout_horizontal(ctx, m)
	}
}

// layout_horizontal - шаги в ряд, прижаты к краям; свободное место поровну делят линии между
// шагами (не короче connector_min). Не влезает - урезаются САМЫЕ ДЛИННЫЕ тексты до общего
// потолка (step_text_cap), короткие остаются целиком: равные доли ширины резали бы и короткое
// «Сборка» рядом с длинной подписью соседа. Текст уже step_min_text_w не показывается вовсе, и в
// пределе видны одни кружки.
fn (mut s Stepper) layout_horizontal(ctx &RenderContext, m StepMetrics) {
	n := s.steps.len
	gaps := n - 1
	avail := s.bounds.w - s.pad * 2
	// Блок шагов центрирован по высоте виджета; кружок - по строке заголовка.
	top := s.bounds.y + (s.bounds.h - m.block_h) * 0.5
	cy := top + m.line_h * 0.5
	ty := cy - m.title_h * 0.5

	// Бюджет под текст: всё, кроме кружков, отступов до текста и наименьших линий.
	mut text_w := []f32{len: n}
	for i in 0 .. n {
		text_w[i] = s.text_width(ctx, i)
	}
	budget := avail - f32(n) * (m.cs + step_text_gap) - f32(gaps) * s.connector_min
	text_cap := step_text_cap(text_w, budget)

	// Ширина содержимого каждого шага после усечения и длина линий из остатка.
	mut content := []f32{len: n}
	mut used := f32(0)
	for i in 0 .. n {
		mut tw := min_f32(text_w[i], text_cap)
		if tw < step_min_text_w {
			tw = 0 // места под текст нет - один кружок
		}
		text_w[i] = tw
		content[i] = m.cs + (if tw > 0 { step_text_gap + tw } else { f32(0) })
		used += content[i]
	}
	line := if gaps > 0 { max_f32((avail - used) / f32(gaps), s.connector_min) } else { f32(0) }

	mut x := s.bounds.x + s.pad
	for i in 0 .. n {
		s.slots << s.make_slot(ctx, i, x, cy, ty, text_w[i], Rect{x - 2, s.bounds.y, content[i] + 4, s.bounds.h})
		s.slots[i].end_x = x + content[i]
		x += content[i] + line
	}
}

// step_text_cap - потолок ширины текста шага: наибольшее c, при котором сумма min(w_i, c) не
// больше budget («урезать сначала самые длинные»). Всё влезает - потолок равен самому длинному
// тексту (ничего не урезается); бюджета нет - 0.
fn step_text_cap(widths []f32, budget f32) f32 {
	if budget <= 0 || widths.len == 0 {
		return 0
	}
	mut sorted := widths.clone()
	sorted.sort()
	mut remaining := budget
	for k, w in sorted {
		// Этот текст и все длиннее делят остаток поровну; не влезает целиком - вот и потолок.
		sharing := f32(sorted.len - k)
		if w * sharing > remaining {
			return remaining / sharing
		}
		remaining -= w
	}
	return sorted[sorted.len - 1]
}

// layout_vertical - шаги столбиком сверху вниз, текст справа от кружка, строка шага - на всю
// ширину виджета (зона щелчка).
fn (mut s Stepper) layout_vertical(ctx &RenderContext, m StepMetrics) {
	text_avail := s.bounds.w - s.pad * 2 - m.cs - step_text_gap
	mut y := s.bounds.y + s.pad
	for i in 0 .. s.steps.len {
		cy := y + m.line_h * 0.5
		ty := cy - m.title_h * 0.5
		tw := if text_avail >= step_min_text_w { text_avail } else { f32(0) }
		s.slots << s.make_slot(ctx, i, s.bounds.x + s.pad, cy, ty, tw, Rect{s.bounds.x, y, s.bounds.w, m.block_h})
		s.slots[i].end_x = s.bounds.x + s.pad + m.cs
		y += m.block_h + s.connector_min
	}
}

// make_slot - место шага i: кружок от левого края x с центром на высоте cy, текст шириной
// tw (0 - без текста) с верхом заголовка ty; название и подпись усекаются под tw.
fn (s &Stepper) make_slot(ctx &RenderContext, i int, x f32, cy f32, ty f32, tw f32, hit Rect) StepSlot {
	cs := s.eff_circle(ctx)
	mut title := ''
	mut note := ''
	if tw > 0 {
		title = bc_truncate_text(ctx, s.steps[i].title, tw, step_title_font(ctx, true))
		note = bc_truncate_text(ctx, s.note_text(i), tw, step_note_font(ctx))
	}
	return StepSlot{
		cx:      x + cs * 0.5
		cy:      cy
		start_x: x
		tx:      x + cs + step_text_gap
		ty:      ty
		title:   title
		note:    note
		hit:     hit
	}
}

// ─── Рисование ─────────────────────────────────────────

// draw - раскладка, затем линии между шагами (под кружками), кружки и тексты.
pub fn (mut s Stepper) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(s.enabled)
	if !s.visible || s.steps.len == 0 || !ctx.is_in_clip(s.bounds) {
		return
	}
	// Текущий мог выйти за границы после удаления шагов - рисуем по зажатому.
	s.current = clamp_int(s.current, 0, s.steps.len - 1)
	s.layout(ctx)
	ctx.push_clip(s.bounds)
	for i in 0 .. s.slots.len - 1 {
		s.draw_connector(mut ctx, i, en)
	}
	for i in 0 .. s.slots.len {
		s.draw_circle(mut ctx, i, en)
		s.draw_text(mut ctx, i, en)
	}
	ctx.pop_clip()
}

// draw_connector - линия от шага i к шагу i+1: цвета «сделано», если шаг i сделан.
fn (s &Stepper) draw_connector(mut ctx RenderContext, i int, en bool) {
	a := s.slots[i]
	b := s.slots[i + 1]
	cs := s.eff_circle(ctx)
	mut c := if s.steps[i].state == .done {
		ctx.theme.eff_step_line_done()
	} else {
		ctx.theme.eff_step_line()
	}
	if !en {
		c = ctx.theme.text_disabled.with_alpha(120)
	}
	if s.vertical {
		y1 := a.cy + cs * 0.5 + step_line_gap
		y2 := b.cy - cs * 0.5 - step_line_gap
		if y2 > y1 {
			ctx.draw_line_thick(a.cx, y1, a.cx, y2, 2, c)
		}
		return
	}
	x1 := a.end_x + step_line_gap
	x2 := b.start_x - step_line_gap
	if x2 > x1 {
		ctx.draw_line_thick(x1, a.cy, x2, a.cy, 2, c)
	}
}

// draw_circle - кружок шага i: подсветка наведения, заливка или кольцо по состоянию, знак
// внутри (номер, значок, галочка, «!», крестик, замок) и ореол текущего шага.
fn (s &Stepper) draw_circle(mut ctx RenderContext, i int, en bool) {
	slot := s.slots[i]
	st := s.steps[i]
	r := s.eff_circle(ctx) * 0.5
	is_cur := i == s.current
	if !en {
		ctx.draw_circle(slot.cx, slot.cy, r, ctx.theme.text_disabled)
		s.draw_mark(mut ctx, i, ctx.theme.text_disabled)
		return
	}
	// Наведение - мягкий круг побольше под кружком.
	if i == s.hover && s.is_clickable(i) {
		ctx.fill_circle(slot.cx, slot.cy, r + 4, ctx.theme.eff_step_hover().with_alpha(45))
	}
	icon_c := ctx.theme.eff_step_icon()
	match st.state {
		.done {
			ctx.fill_circle(slot.cx, slot.cy, r, ctx.theme.eff_step_done())
			s.draw_mark(mut ctx, i, icon_c)
		}
		.warning {
			ctx.fill_circle(slot.cx, slot.cy, r, ctx.theme.warning)
			s.draw_mark(mut ctx, i, icon_c)
		}
		.error {
			ctx.fill_circle(slot.cx, slot.cy, r, ctx.theme.error_color)
			s.draw_mark(mut ctx, i, icon_c)
		}
		.locked {
			s.draw_ring(mut ctx, slot, r, ctx.theme.text_disabled)
			s.draw_mark(mut ctx, i, ctx.theme.text_disabled)
		}
		.pending {
			if is_cur {
				// «Вы здесь»: несделанный текущий шаг - заливка акцентом.
				ctx.fill_circle(slot.cx, slot.cy, r, ctx.theme.eff_step_active())
				s.draw_mark(mut ctx, i, icon_c)
			} else {
				s.draw_ring(mut ctx, slot, r, ctx.theme.eff_step_pending())
				s.draw_mark(mut ctx, i, ctx.theme.eff_step_note())
			}
		}
	}
	// Ореол текущего шага - два кольца акцентом поверх любого состояния.
	if is_cur {
		halo := ctx.theme.eff_step_active()
		ctx.draw_circle(slot.cx, slot.cy, r + 3, halo.with_alpha(150))
		ctx.draw_circle(slot.cx, slot.cy, r + 4, halo.with_alpha(70))
	}
}

// draw_ring - кольцо толщиной 2: draw_circle рисует контур в 1 логическую единицу.
fn (s &Stepper) draw_ring(mut ctx RenderContext, slot StepSlot, r f32, c Color) {
	ctx.draw_circle(slot.cx, slot.cy, r, c)
	ctx.draw_circle(slot.cx, slot.cy, r - 1, c)
}

// draw_mark - знак внутри кружка шага i цветом c: у done/warning/error/locked - значок
// состояния, иначе значок шага (icon) или его номер (с 1).
fn (s &Stepper) draw_mark(mut ctx RenderContext, i int, c Color) {
	slot := s.slots[i]
	cs := s.eff_circle(ctx)
	box := Rect{slot.cx - cs * 0.5, slot.cy - cs * 0.5, cs, cs}
	glyph := int(cs * 0.6)
	mark := match s.steps[i].state {
		.done { 'check' }
		.error { 'x' }
		.locked { 'lock' }
		.warning { '' } // «!» - текстом ниже: значок треугольника в кружке читается хуже
		.pending { s.steps[i].icon }
	}
	if mark.len > 0 {
		cp, ok := icon_codepoint(mark)
		if ok {
			ctx.draw_icon_glyph(cp, box, if s.steps[i].state == .locked {
				int(cs * 0.5)
			} else {
				glyph
			}, c)
			return
		}
	}
	text := if s.steps[i].state == .warning { '!' } else { '${i + 1}' }
	font := ctx.get_font(.bold, max_int(ctx.default_font_size() - 1, 8))
	sz := ctx.measure_text_with_font(text, font)
	ctx.draw_text_with_font(text, slot.cx - sz.x * 0.5, slot.cy - ctx.font_height_of(font) * 0.5, c, font)
}

// draw_text - название шага i (жирным у текущего) и подпись под ним. Цвет названия: недоступен -
// бледный, наведение - цвет наведения, текущий - step_title_current, сделанный - step_title,
// остальные - цвет подписи. Подпись у warning/error - цветом состояния.
fn (s &Stepper) draw_text(mut ctx RenderContext, i int, en bool) {
	slot := s.slots[i]
	if slot.title.len == 0 && slot.note.len == 0 {
		return
	}
	st := s.steps[i]
	is_cur := i == s.current
	th := ctx.theme
	title_c := if !en || st.state == .locked {
		th.text_disabled
	} else if i == s.hover && s.is_clickable(i) {
		th.eff_step_hover()
	} else if is_cur {
		th.eff_step_title_current()
	} else if st.state == .done {
		th.eff_step_title()
	} else {
		th.eff_step_note()
	}
	title_font := ctx.get_font(if is_cur { FontStyle.bold } else { FontStyle.regular }, 0)
	ctx.draw_text_with_font(slot.title, slot.tx, slot.ty, title_c, title_font)
	if slot.note.len == 0 {
		return
	}
	note_c := if !en || st.state == .locked {
		th.text_disabled
	} else if st.state == .warning {
		th.warning
	} else if st.state == .error {
		th.error_color
	} else {
		th.eff_step_note()
	}
	note_font := ctx.get_font(.regular, max_int(ctx.default_font_size() - 2, 8))
	title_h := ctx.font_height_of(step_title_font(ctx, true))
	ctx.draw_text_with_font(slot.note, slot.tx, slot.ty + title_h + step_note_gap, note_c, note_font)
}

// ─── Попадание и события ───────────────────────────────

// step_at - шаг под точкой (по зонам slots прошлого кадра) или -1.
fn (s &Stepper) step_at(x f32, y f32) int {
	for i, slot in s.slots {
		if slot.hit.contains(x, y) {
			return i
		}
	}
	return -1
}

// handle_event: наведение подсвечивает кликабельный шаг и меняет курсор на «руку»; левый
// щелчок по кликабельному шагу делает его текущим и зовёт on_change.
pub fn (mut s Stepper) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible {
		return false
	}
	if !s.enabled && is_input_event(event) {
		s.hover = -1
		return false
	}
	match event.typ {
		.mouse_move {
			idx := s.step_at(event.mouse_x, event.mouse_y)
			nh := if s.is_clickable(idx) { idx } else { -1 }
			if nh != s.hover {
				s.hover = nh
				widget_changed()
			}
			// Кэширующий set_cursor (sdl3_bindings.v): курсор не создаётся заново на каждое движение.
			set_cursor(if s.hover >= 0 { sdl_system_cursor_hand } else { sdl_system_cursor_arrow })
			return false
		}
		.mouse_leave {
			if s.hover != -1 {
				s.hover = -1
				widget_changed()
				set_cursor(sdl_system_cursor_arrow)
			}
			return false
		}
		.mouse_down {
			if event.mouse_btn != .left {
				return false
			}
			idx := s.step_at(event.mouse_x, event.mouse_y)
			if !s.is_clickable(idx) {
				return false
			}
			widget_changed()
			s.current = idx
			// Шаг стал текущим - он больше не кликабелен, подсветку снять сразу.
			s.hover = -1
			set_cursor(sdl_system_cursor_arrow)
			if !isnil(s.on_change) {
				s.on_change(idx)
			}
			return true
		}
		else {}
	}
	return false
}
