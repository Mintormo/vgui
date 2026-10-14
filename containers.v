module vgui

// ═══════════════════════════════════════════════════════
// Layout containers — HBox, VBox, Stack, Panel,
// Spacer, ScrollBox, Centered
// ═══════════════════════════════════════════════════════
//
// Файл с базовыми контейнерами. Все они реализуют интерфейс Widget (draw/handle_event) и, где нужно,
// Arrangeable (arrange): bounds детям раздаются ТОЛЬКО в arrange() (фаза раскладки, раз за кадр
// перед draw), а не в draw(). Размеры детей контейнер узнаёт через measure_widget()
// (layout_measure.v); bounds выдаёт set_widget_bounds / arrange_child. HBox и VBox - тонкие
// обёртки над общим движком BoxLayout. Контейнеры не владеют детьми: remove/clear только
// отсоединяют указатель (освобождение - дело вызывающего, см. «Удаление детей из контейнеров»
// в PROJECT.md). События идут детям в обратном порядке (верхние по Z - первыми).
// Глобальные bounds-«fill» контейнеров: если родитель bounds не задал (w<=0 и h<=0),
// контейнер растягивается на весь экран окна (is_bounds_unset).

// ─── ChildEntry — widget + layout hints ────────────────

// SizeMode — как контейнер выбирает размер ребёнка вдоль
// главной оси (Layout: measure/arrange в PROJECT.md).
//
//   auto  — по умолчанию (add(w)): естественный размер из
//           measure(); виджет, растягиваемый по природе
//           (политика expanding: поле ввода, ползунок, список,
//           холст, распорка), растёт от него в свободное место;
//   flex  — add(w, flex: n): делёж свободного места по весу,
//           от нуля (как Expanded во Flutter).
// Режима «жёстко N пикселей» нет намеренно: размер - из
// содержимого, ограничения - min/max, расстояния - spacing/padding.
pub enum SizeMode {
	auto
	flex
}

// ChildEntry - запись о ребёнке контейнера: сам виджет плюс подсказки раскладки (из LayoutParams.to_entry).
//   flex  - вес при дележе свободного места (используется при mode == .flex)
//   mode  - как выбирается размер вдоль главной оси (SizeMode)
pub struct ChildEntry {
pub mut:
	widget &Widget
	flex   f32
	mode   SizeMode = .auto
	// Границы вдоль главной оси, заданные вызывающим кодом.
	// Перекрывают то, что вернул measure(): min_main = 0 и
	// max_main = size_unbounded означают «ограничения нет».
	min_main f32
	max_main f32 = size_unbounded
	// Индивидуальное выравнивание поперёк главной оси.
	// Если own_cross = false, действует cross_align контейнера.
	own_cross bool
	cross     CrossAlign = .stretch
}

// ─── Direction enum ────────────────────────────────────

// BoxDir - направление главной оси BoxLayout: HBox раскладывает по горизонтали, VBox по вертикали.
enum BoxDir {
	horizontal
	vertical
}

// ═══════════════════════════════════════════════════════
// BoxLayout — shared engine for HBox and VBox
// ═══════════════════════════════════════════════════════

// BoxLayout - общий движок раскладки HBox и VBox (в самих HBox/VBox лежит как поле box).
//   spacing - расстояние между соседними детьми; pad - внутренний отступ со всех сторон
//   bg / use_panel_bg - свой фон (alpha 0 = без фона) или фон панели темы
//   clip - обрезать рисование детей по bounds (ScrollBox отключает: disable_child_clip)
struct BoxLayout {
mut:
	bounds       Rect
	children     []ChildEntry
	dir          BoxDir
	spacing      f32 = 4
	pad          f32
	bg           Color = Color{0, 0, 0, 0}
	use_panel_bg bool
	visible      bool = true
	// enabled - отключает всё поддерево (enabled.v); у HBox/VBox/WindowTitleDrag флаг живёт здесь.
	enabled bool = true
	clip    bool = true
	// Выравнивание детей поперёк главной оси. stretch —
	// историческое поведение (ребёнок на всю ширину/высоту).
	cross_align CrossAlign = .stretch
}

// child_main_item собирает вход алгоритма распределения для
// одного ребёнка: желаемый размер вдоль главной оси, его
// границы и вес в дележе остатка.
fn (b &BoxLayout) child_main_item(c &ChildEntry, ctx &RenderContext, vertical bool) LayoutItem {
	// Вход distribute_main (layout_measure.v): base - желаемый размер, min/max - границы, flex - вес в дележе остатка.
	mut it := LayoutItem{
		max: size_unbounded
	}
	match c.mode {
		.auto {
			if !is_measurable(c.widget) {
				// Виджет без measure() размера не знает - занимает
				// свободное место, как раньше add(w, 1)
				it.flex = 1
			} else {
				hint := measure_widget(c.widget, ctx)
				pref, mn, mx, pol := hint.axis(vertical)
				it.base = pref
				it.min = mn
				it.max = mx
				if pol == .expanding {
					// Растягиваемый по природе - растёт от своего
					// размера в свободное место (и сжимается до min)
					it.flex = 1
				}
			}
		}
		.flex {
			// База 0 + вес: ровно старая семантика дележа.
			it.flex = max_f32(0, c.flex)
		}
	}
	// Явные границы вызывающего кода сильнее measure().
	if c.min_main > 0 {
		it.min = max_f32(it.min, c.min_main)
	}
	if c.max_main < size_unbounded {
		it.max = min_f32(it.max, c.max_main)
	}
	if it.max < it.min {
		it.max = it.min
	}
	return it
}

// layout — фаза arrange: раздаёт детям окончательные bounds.
//
// ctx нужен, чтобы измерить детей с mode = .auto и виджеты
// при выравнивании поперёк оси; для остальных случаев
// он не трогается.
fn (mut b BoxLayout) layout(ctx &RenderContext) {
	if b.children.len == 0 {
		return
	}

	inner := b.bounds.shrunk(b.pad)
	is_h := b.dir == .horizontal
	vertical_main := !is_h

	// Шаги: (1) вычесть из главной оси отступы и промежутки -> avail; (2) каждому ребёнку собрать LayoutItem
	// и поделить avail через distribute_main; (3) расставить детей подряд, поперёк выровнять по align.
	total_spacing := f32(b.children.len - 1) * b.spacing
	main_total := if is_h { inner.w } else { inner.h }
	avail := max_f32(0, main_total - total_spacing)

	mut items := []LayoutItem{cap: b.children.len}
	for c in b.children {
		items << b.child_main_item(c, ctx, vertical_main)
	}
	distribute_main(mut items, avail)

	cross_avail := if is_h { inner.h } else { inner.w }
	mut pos := if is_h { inner.x } else { inner.y }

	for i, c in b.children {
		sz := items[i].result

		// Поперечная ось: при stretch ребёнок занимает всё - кроме
		// виджетов фиксированного размера поперёк (флажок, бейдж,
		// метка в ряду): они не растягиваются, а встают по месту -
		// в ряду по центру высоты, в столбце у левого края.
		// align - личное выравнивание ребёнка (если задано) или общее выравнивание контейнера.
		mut align := if c.own_cross { c.cross } else { b.cross_align }
		mut cross_off := f32(0)
		mut cross_sz := cross_avail
		if is_measurable(c.widget) {
			hint := measure_widget(c.widget, ctx)
			pref, mn, mx, pol := hint.axis(is_h)
			if (align == .stretch || align == .inherit) && pol == .fixed && !c.own_cross {
				align = if is_h { CrossAlign.center } else { CrossAlign.start }
			}
			cross_off, cross_sz = align_cross(align, cross_avail, pref, mn, mx)
		}

		mut r := Rect{}
		if is_h {
			r = Rect{pos, inner.y + cross_off, sz, cross_sz}
		} else {
			r = Rect{inner.x + cross_off, pos, cross_sz, sz}
		}

		set_widget_bounds(mut b.children[i].widget, r)

		pos += sz
		if i < b.children.len - 1 {
			pos += b.spacing
		}
	}
}

// content_size — сколько места контейнер хочет под своё
// содержимое: вдоль главной оси суммирует детей, поперёк
// берёт максимум. Основа Measurable у HBox/VBox и
// авто-размера окна (fit_to_content).
fn (b &BoxLayout) content_size(ctx &RenderContext) SizeHint {
	is_h := b.dir == .horizontal
	if b.children.len == 0 {
		return SizeHint{
			w: b.pad * 2
			h: b.pad * 2
		}
	}

	mut main_pref := f32(0)
	mut main_min := f32(0)
	mut cross_pref := f32(0)
	mut cross_min := f32(0)
	mut main_expands := false
	mut cross_expands := false

	for c in b.children {
		hint := measure_widget(c.widget, ctx)
		if c.mode == .flex {
			// Ребёнок с весом при раскладке стартует с нуля,
			// но контейнер под него всё равно просит место:
			// иначе fit_to_content схлопнул бы окно.
			mp, mm, _, _ := hint.axis(!is_h)
			main_pref += max_f32(mp, c.min_main)
			main_min += max_f32(mm, c.min_main)
			main_expands = true
		} else {
			it := b.child_main_item(c, ctx, !is_h)
			main_pref += it.base
			main_min += it.min
		}

		cp, cm, _, cpol := hint.axis(is_h)
		cross_pref = max_f32(cross_pref, cp)
		cross_min = max_f32(cross_min, cm)
		// Распорка растягивает только вдоль своего контейнера: ряд с
		// распоркой не становится от неё «высоким»
		if cpol == .expanding && c.widget !is Spacer {
			cross_expands = true
		}
	}

	extra := f32(b.children.len - 1) * b.spacing + b.pad * 2
	main_pref += extra
	main_min += extra
	cross_pref += b.pad * 2
	cross_min += b.pad * 2

	main_policy := if main_expands { SizePolicy.expanding } else { SizePolicy.preferred }
	cross_policy := if cross_expands { SizePolicy.expanding } else { SizePolicy.preferred }

	if is_h {
		return SizeHint{
			w:        main_pref
			h:        cross_pref
			min_w:    main_min
			min_h:    cross_min
			h_policy: main_policy
			v_policy: cross_policy
		}
	}
	return SizeHint{
		w:        cross_pref
		h:        main_pref
		min_w:    cross_min
		min_h:    main_min
		h_policy: cross_policy
		v_policy: main_policy
	}
}

// arrange — layout() для своих детей плюс спуск в их поддеревья.
// layout() оставлен отдельным (без рекурсии): его зовут тесты раскладки.
fn (mut b BoxLayout) arrange(mut ctx RenderContext) {
	if !b.visible {
		return
	}
	b.layout(ctx)
	for i in 0 .. b.children.len {
		arrange_widget(mut b.children[i].widget, mut ctx)
	}
}

// draw_impl - общая отрисовка HBox/VBox: фон, затем дети внутри клипа (если clip). Ничего не раскладывает - bounds детей уже выданы arrange().
fn (mut b BoxLayout) draw_impl(mut ctx RenderContext) {
	if !b.visible {
		return
	}

	if b.use_panel_bg {
		ctx.fill_rect(b.bounds, ctx.theme.panel_bg)
	} else if b.bg.a > 0 {
		ctx.fill_rect(b.bounds, b.bg)
	}
	if b.clip {
		// Клип раздут на visual_margin(): виджеты рисуют тень ЗА своими
		// bounds (draw_shadow смещает её на shadow_offset и размывает на
		// shadow_blur наружу), а бокс обычно обтягивает детей вплотную —
		// клип строго по bounds срезал бы тень у крайнего ребёнка, чаще
		// всего снизу, куда тень и уходит по offset. Раздутие безопасно:
		// push_clip пересекает прямоугольник с родительским клипом, так что
		// содержимое ScrollBox по-прежнему не выходит за его viewport, а
		// сами виджеты клипают своё содержимое по собственным bounds.
		ctx.push_clip(b.bounds.expanded(ctx.visual_margin()))
	}
	ctx.begin_disabled(b.enabled)
	for mut c in b.children {
		c.widget.draw(mut ctx)
	}
	ctx.end_disabled(b.enabled)
	if b.clip {
		ctx.pop_clip()
	}
}

// event_impl - раздаёт событие детям с конца (последний добавленный - сверху); true, если кто-то поглотил.
fn (mut b BoxLayout) event_impl(event &GuiEvent, app &App) bool {
	if !b.visible || (!b.enabled && is_input_event(event)) {
		return false
	}
	for i := b.children.len - 1; i >= 0; i-- {
		if b.children[i].widget.handle_event(event, app) {
			return true
		}
	}
	return false
}

// remove_child drops the child whose pointer matches `target` from the
// children slice (by pointer identity). Returns true if something was
// removed. The child struct itself is not freed here — ownership of that
// stays with the caller (Python side decides whether to vgui_destroy it).
fn (mut b BoxLayout) remove_child(target voidptr) bool {
	if target == unsafe { nil } {
		return false
	}
	for i, c in b.children {
		if voidptr(c.widget) == target {
			b.children.delete(i)
			return true
		}
	}
	return false
}

// clear_children drops all children (without freeing their structs).
fn (mut b BoxLayout) clear_children() {
	b.children.clear()
}

// ═══════════════════════════════════════════════════════
// Helper: check if bounds were never assigned by a parent
// layout. A "fill" container starts with {0,0,0,0} and
// should expand to screen size only if no parent set its
// bounds. We detect this by checking w<=0 && h<=0
// (not position, because position (0,0) is valid).
// ═══════════════════════════════════════════════════════

fn is_bounds_unset(b Rect) bool {
	return b.w <= 0 && b.h <= 0
}

// ═══════════════════════════════════════════════════════
// HBox
// ═══════════════════════════════════════════════════════

// HBox - горизонтальный контейнер: дети слева направо. API: add / remove / clear / set_spacing / set_padding / set_bg / set_cross_align (все делегируют BoxLayout).
pub struct HBox {
pub mut:
	type_tag int = kind_hbox // тег типа, см. widget_tag.v
	box      BoxLayout
}

// create_hbox_fill создаёт HBox с неустановленными bounds: пока родитель их не задал, займёт весь экран окна.
pub fn create_hbox_fill() &HBox {
	return &HBox{
		box: BoxLayout{
			bounds: Rect{0, 0, 0, 0}
			dir:    .horizontal
		}
	}
}

// add добавляет ребёнка. Без параметров - естественный размер
// из measure() (кнопка - под свой текст, метка - под строку;
// поле ввода, ползунок, список растут в свободное место):
//
//   box.add(w)                 // по содержимому
//   box.add(w, flex: 1)        // доля свободного места
//   box.add(w, min: 80, max: 200, align: .center)
//
// См. LayoutParams.
pub fn (mut h HBox) add(widget &Widget, p LayoutParams) {
	h.box.children << p.to_entry(widget)
}

// set_cross_align задаёт выравнивание детей по вертикали
// (поперёк главной оси HBox).
pub fn (mut h HBox) set_cross_align(a CrossAlign) {
	h.box.cross_align = a
}

// remove отсоединяет ребёнка (по адресу); true, если он был найден. Виджет не освобождается.
pub fn (mut h HBox) remove(widget &Widget) bool {
	return h.box.remove_child(voidptr(widget))
}

pub fn (mut h HBox) clear() {
	h.box.clear_children()
}

pub fn (mut h HBox) set_spacing(s f32) {
	h.box.spacing = s
}

pub fn (mut h HBox) set_padding(p f32) {
	h.box.pad = p
}

pub fn (mut h HBox) set_bg(c Color) {
	h.box.bg = c
}

// set_panel_bg - рисовать фон цветом panel_bg текущей темы (вместо фиксированного set_bg).
pub fn (mut h HBox) set_panel_bg() {
	h.box.use_panel_bg = true
}

// arrange: если bounds никто не задал - берёт весь экран окна, затем раскладывает детей и спускается в их поддеревья.
pub fn (mut h HBox) arrange(mut ctx RenderContext) {
	if is_bounds_unset(h.box.bounds) {
		h.box.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	h.box.arrange(mut ctx)
}

pub fn (mut h HBox) draw(mut ctx RenderContext) {
	h.box.draw_impl(mut ctx)
}

// handle_event: при window_resize "корневой" контейнер (bounds не задан родителем) подгоняет размер под новое окно, затем раздаёт событие детям.
pub fn (mut h HBox) handle_event(event &GuiEvent, app &App) bool {
	if event.typ == .window_resize {
		if is_bounds_unset(h.box.bounds) {
			h.box.bounds.w = f32(event.win_w)
			h.box.bounds.h = f32(event.win_h)
		}
	}
	return h.box.event_impl(event, app)
}

// ═══════════════════════════════════════════════════════
// VBox
// ═══════════════════════════════════════════════════════

// VBox - вертикальный контейнер: дети сверху вниз. Устроен так же, как HBox (оба поверх BoxLayout), отличается только главной осью.
pub struct VBox {
pub mut:
	type_tag int = kind_vbox // тег типа, см. widget_tag.v
	box      BoxLayout
}

// create_vbox_fill - см. create_hbox_fill: bounds не заданы, пока их не выдаст родитель.
pub fn create_vbox_fill() &VBox {
	return &VBox{
		box: BoxLayout{
			bounds: Rect{0, 0, 0, 0}
			dir:    .vertical
		}
	}
}

// add добавляет ребёнка. Без параметров - естественный размер
// из measure() (кнопка - под свой текст, метка - под строку;
// поле ввода, ползунок, список растут в свободное место):
//
//   box.add(w)                 // по содержимому
//   box.add(w, flex: 1)        // доля свободного места
//   box.add(w, min: 80, max: 200, align: .center)
//
// См. LayoutParams.
pub fn (mut v VBox) add(widget &Widget, p LayoutParams) {
	v.box.children << p.to_entry(widget)
}

// set_cross_align задаёт выравнивание детей по горизонтали
// (поперёк главной оси VBox).
pub fn (mut v VBox) set_cross_align(a CrossAlign) {
	v.box.cross_align = a
}

// remove отсоединяет ребёнка по адресу (true, если найден); виджет не освобождается.
pub fn (mut v VBox) remove(widget &Widget) bool {
	return v.box.remove_child(voidptr(widget))
}

pub fn (mut v VBox) clear() {
	v.box.clear_children()
}

pub fn (mut v VBox) set_spacing(s f32) {
	v.box.spacing = s
}

pub fn (mut v VBox) set_padding(p f32) {
	v.box.pad = p
}

pub fn (mut v VBox) set_bg(c Color) {
	v.box.bg = c
}

pub fn (mut v VBox) set_panel_bg() {
	v.box.use_panel_bg = true
}

// arrange / handle_event - как у HBox (корневой контейнер растягивается на окно).
pub fn (mut v VBox) arrange(mut ctx RenderContext) {
	if is_bounds_unset(v.box.bounds) {
		v.box.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	v.box.arrange(mut ctx)
}

pub fn (mut v VBox) draw(mut ctx RenderContext) {
	v.box.draw_impl(mut ctx)
}

pub fn (mut v VBox) handle_event(event &GuiEvent, app &App) bool {
	if event.typ == .window_resize {
		if is_bounds_unset(v.box.bounds) {
			v.box.bounds.w = f32(event.win_w)
			v.box.bounds.h = f32(event.win_h)
		}
	}
	return v.box.event_impl(event, app)
}

// ═══════════════════════════════════════════════════════
// Panel — background + border + single child
// ═══════════════════════════════════════════════════════

// Panel - панель с фоном, рамкой и ОДНИМ ребёнком (set_child), у которого отступ pad от краёв.
// bg / border с alpha 0 означают «цвет из темы» (panel_bg / border); radius < 0 - радиус темы.
pub struct Panel {
pub mut:
	type_tag int = kind_panel // тег типа, см. widget_tag.v
	bounds   Rect
	bg       Color   = Color{0, 0, 0, 0}
	border   Color   = Color{0, 0, 0, 0}
	radius   f32     = -1
	pad      f32     = 8
	visible  bool    = true
	enabled  bool    = true // false - неактивно всё содержимое (enabled.v)
	child    &Widget = unsafe { nil }
}

// set_child назначает ребёнка (предыдущий просто забывается, не освобождается).
pub fn (mut p Panel) set_child(w &Widget) {
	p.child = unsafe { w }
}

// clear_child detaches the current child (no free — caller owns it).
pub fn (mut p Panel) clear_child() {
	p.child = unsafe { nil }
}

// arrange отдаёт ребёнку область панели минус pad.
pub fn (mut p Panel) arrange(mut ctx RenderContext) {
	if !p.visible || unsafe { p.child == nil } {
		return
	}
	arrange_child(mut p.child, p.bounds.shrunk(p.pad), mut ctx)
}

pub fn (mut p Panel) draw(mut ctx RenderContext) {
	if !p.visible {
		return
	}

	bg := if p.bg.a > 0 { p.bg } else { ctx.theme.panel_bg }
	bc := if p.border.a > 0 { p.border } else { ctx.theme.border }
	rad := if p.radius >= 0 { p.radius } else { ctx.theme.border_radius }

	ctx.fill_rounded_rect(p.bounds, bg, rad)
	if bc.a > 0 {
		ctx.draw_rounded_rect(p.bounds, bc, rad)
	}

	if unsafe { p.child != nil } {
		inner := p.bounds.shrunk(p.pad)
		// Как и у BoxLayout — клип раздут на visual_margin(), иначе padding
		// меньше вылета тени срезал бы тень ребёнка. Ограничено самой
		// панелью: за её рамку тень содержимого выходить не должна.
		ctx.push_clip(inner.expanded(ctx.visual_margin()).intersection(p.bounds))
		ctx.begin_disabled(p.enabled)
		p.child.draw(mut ctx)
		ctx.end_disabled(p.enabled)
		ctx.pop_clip()
	}
}

pub fn (mut p Panel) handle_event(event &GuiEvent, app &App) bool {
	if !p.visible || (!p.enabled && is_input_event(event)) {
		return false
	}
	if unsafe { p.child != nil } {
		return p.child.handle_event(event, app)
	}
	return false
}

// ═══════════════════════════════════════════════════════
// Stack — all children on top of each other
// ═══════════════════════════════════════════════════════

// Stack - дети накладываются друг на друга в общей области bounds (рисуются по порядку добавления, события идут с конца - верхнему слою первому).
pub struct Stack {
pub mut:
	type_tag int = kind_stack // тег типа, см. widget_tag.v
	bounds   Rect
	children []&Widget
	visible  bool  = true
	enabled  bool  = true // false - неактивны все слои (enabled.v)
	bg       Color = Color{0, 0, 0, 0}
}

pub fn (mut s Stack) add(w &Widget) {
	s.children << unsafe { w }
}

// remove отсоединяет ребёнка по адресу (true, если найден); без освобождения.
pub fn (mut s Stack) remove(target voidptr) bool {
	if target == unsafe { nil } {
		return false
	}
	for i, c in s.children {
		if voidptr(c) == target {
			s.children.delete(i)
			return true
		}
	}
	return false
}

pub fn (mut s Stack) clear() {
	s.children.clear()
}

// arrange: каждому ребёнку - вся область Stack; если bounds не заданы - весь экран.
pub fn (mut s Stack) arrange(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if is_bounds_unset(s.bounds) {
		s.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	for mut c in s.children {
		arrange_child(mut c, s.bounds, mut ctx)
	}
}

pub fn (mut s Stack) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if s.bg.a > 0 {
		ctx.fill_rect(s.bounds, s.bg)
	}
	ctx.begin_disabled(s.enabled)
	for mut c in s.children {
		c.draw(mut ctx)
	}
	ctx.end_disabled(s.enabled)
}

pub fn (mut s Stack) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible || (!s.enabled && is_input_event(event)) {
		return false
	}
	for i := s.children.len - 1; i >= 0; i-- {
		if s.children[i].handle_event(event, app) {
			return true
		}
	}
	return false
}

// ═══════════════════════════════════════════════════════
// Spacer
// ═══════════════════════════════════════════════════════

// Spacer - невидимая распорка: ничего не рисует и не обрабатывает, нужна только раскладке (растягивается политикой expanding).
pub struct Spacer {
pub mut:
	type_tag int = kind_spacer // тег типа, см. widget_tag.v
	bounds   Rect
	visible  bool = true
	enabled  bool = true // ни на что не влияет: флаг для единообразия set_enabled
}

// create_spacer - распорка: забирает свободное место (прижать
// кнопки вправо, вниз), как Spacer() в SwiftUI и Flutter. Промежутков
// фиксированной величины нет - расстояния задаёт контейнер
// (set_spacing, set_padding)
pub fn create_spacer() &Spacer {
	return &Spacer{}
}

pub fn (mut s Spacer) draw(mut ctx RenderContext) {
}

pub fn (mut s Spacer) handle_event(event &GuiEvent, app &App) bool {
	return false
}

// ═══════════════════════════════════════════════════════
// Centered — centers a child widget
// ═══════════════════════════════════════════════════════

// Centered - центрирует одного ребёнка фиксированного размера child_w x child_h внутри своих bounds.
pub struct Centered {
pub mut:
	type_tag int = kind_centered // тег типа, см. widget_tag.v
	bounds   Rect
	child_w  f32     = 200
	child_h  f32     = 40
	visible  bool    = true
	enabled  bool    = true // false - неактивен ребёнок (enabled.v)
	bg       Color   = Color{0, 0, 0, 0}
	child    &Widget = unsafe { nil }
}

// create_centered - bounds выдаст родитель; create_centered_fill - нулевые bounds, т.е. займёт окно, если родитель их не задаст.
pub fn create_centered(child_w f32, child_h f32) &Centered {
	return &Centered{
		child_w: child_w
		child_h: child_h
	}
}

pub fn create_centered_fill(child_w f32, child_h f32) &Centered {
	return &Centered{
		bounds:  Rect{0, 0, 0, 0}
		child_w: child_w
		child_h: child_h
	}
}

pub fn (mut c Centered) set_child(w &Widget) {
	c.child = unsafe { w }
}

// clear_child detaches the current child (no free — caller owns it).
pub fn (mut c Centered) clear_child() {
	c.child = unsafe { nil }
}

// arrange: ребёнок получает прямоугольник child_w x child_h по центру bounds (может быть отрицательное смещение, если bounds меньше ребёнка).
pub fn (mut c Centered) arrange(mut ctx RenderContext) {
	if !c.visible {
		return
	}
	if is_bounds_unset(c.bounds) {
		c.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	if unsafe { c.child != nil } {
		cx := c.bounds.x + (c.bounds.w - c.child_w) / 2.0
		cy := c.bounds.y + (c.bounds.h - c.child_h) / 2.0
		arrange_child(mut c.child, Rect{cx, cy, c.child_w, c.child_h}, mut ctx)
	}
}

pub fn (mut c Centered) draw(mut ctx RenderContext) {
	if !c.visible {
		return
	}
	if c.bg.a > 0 {
		ctx.fill_rect(c.bounds, c.bg)
	}
	if unsafe { c.child != nil } {
		ctx.begin_disabled(c.enabled)
		c.child.draw(mut ctx)
		ctx.end_disabled(c.enabled)
	}
}

pub fn (mut c Centered) handle_event(event &GuiEvent, app &App) bool {
	if !c.visible {
		return false
	}
	if event.typ == .window_resize {
		if is_bounds_unset(c.bounds) {
			c.bounds.w = f32(event.win_w)
			c.bounds.h = f32(event.win_h)
		}
	}
	if unsafe { c.child != nil } && (c.enabled || !is_input_event(event)) {
		return c.child.handle_event(event, app)
	}
	return false
}

// ═══════════════════════════════════════════════════════
// ScrollBox — scrollable container with draggable scrollbar
//
// Supports both vertical (.vertical) and horizontal (.horizontal) scroll.
//
// Детей может быть несколько: они идут стопкой вдоль оси прокрутки (как в
// VBox/HBox) через spacing, каждый - своего естественного размера из measure();
// единственный ребёнок, как и раньше, растягивается на всю область содержимого.
// If content_h/content_w <= 0 (or set to 0), the content size is the natural
// size of the stack (update_eff_content_size), but never less than the visible
// area. (Раньше размер считался вручную по типу ребёнка, теперь - единый
// measure(), см. «Layout: measure/arrange» в PROJECT.md.)
// ═══════════════════════════════════════════════════════

// ScrollDir - ось прокрутки ScrollBox.
pub enum ScrollDir {
	vertical
	horizontal
}

// ScrollBox - прокручиваемая область с полосой прокрутки. Дети раскладываются в "содержимое" (content_rect)
// размером eff_content_h/w, смещённое на scroll_y/x; рисование обрезается по viewport. Прокрутка: колесо,
// перетаскивание ползунка, клик по дорожке (страница). Полосу и цвета можно настроить (sb_*, нулевое
// значение/alpha 0 = взять из темы). eff_content_* - рабочий размер содержимого, обновляется в arrange().
pub struct ScrollBox {
pub mut:
	type_tag int = kind_scroll_box // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	// wheel        bool = true
	wheel        bool = true
	bounds       Rect
	dir          ScrollDir = .vertical
	content_h    f32 // user-specified content height (vertical mode); 0 = auto
	content_w    f32 // user-specified content width (horizontal mode); 0 = auto
	scroll_y     f32
	scroll_x     f32
	visible      bool  = true
	enabled      bool  = true // false - не прокручивается, содержимое неактивно (enabled.v)
	bg           Color = Color{0, 0, 0, 0}
	children     []&Widget
	scroll_speed f32 = 30
	pad          f32 = 2
	spacing      f32 = 4 // между детьми стопки (при одном ребёнке не используется)
	// ── Scrollbar customization ──
	sb_width             f32 // track width/height; 0 → 14
	sb_radius            f32 = -1 // corner radius; <0 → 3
	sb_min_thumb         f32 // minimum thumb size; 0 → 24
	sb_track_color       Color = Color{0, 0, 0, 0}
	sb_thumb_color       Color = Color{0, 0, 0, 0}
	sb_thumb_hover_color Color = Color{0, 0, 0, 0}
	sb_thumb_drag_color  Color = Color{0, 0, 0, 0}
	// ── Internal ──
	sb_dragging          bool
	sb_hovered           bool
	sb_drag_start_y      f32
	sb_drag_start_x      f32
	sb_drag_start_scroll f32
	hovered              bool
	eff_content_h        f32 // actual content height used for scrolling (vertical)
	eff_content_w        f32 // actual content width used for scrolling (horizontal)
	// размеры детей вдоль оси прокрутки (естественные, из measure()) -
	// считаются в update_eff_content_size, раздаются в arrange()
	child_sizes []f32
}

pub fn (mut s ScrollBox) add(w &Widget) {
	s.children << unsafe { w }
}

// remove отсоединяет ребёнка по адресу (true, если найден); без освобождения.
pub fn (mut s ScrollBox) remove(target voidptr) bool {
	if target == unsafe { nil } {
		return false
	}
	for i, c in s.children {
		if voidptr(c) == target {
			s.children.delete(i)
			return true
		}
	}
	return false
}

pub fn (mut s ScrollBox) clear() {
	s.children.clear()
}

// ── Размер содержимого: из measure() ребёнка ──

// update_eff_content_size - высота (ширина) прокручиваемого содержимого:
// заданная явно (content_h/content_w), иначе естественный размер стопки
// детей (сумма их measure() вдоль оси плюс spacing), но не меньше видимой
// области (меньшее содержимое просто заполняет её, прокрутки нет). Заодно
// запоминает размеры детей для arrange() (child_sizes).
fn (mut s ScrollBox) update_eff_content_size(ctx &RenderContext) {
	vertical := s.dir == .vertical
	s.child_sizes = []f32{cap: s.children.len}
	mut natural := f32(0)
	for i, c in s.children {
		hint := measure_widget(c, ctx)
		size := if vertical { hint.h } else { hint.w }
		s.child_sizes << size
		natural += size
		if i > 0 {
			natural += s.spacing
		}
	}
	if vertical {
		s.eff_content_h = if s.content_h > 0 {
			s.content_h
		} else {
			max_f32(natural, s.bounds.h)
		}
	} else {
		s.eff_content_w = if s.content_w > 0 {
			s.content_w
		} else {
			max_f32(natural, s.bounds.w)
		}
	}
}

// ── Effective scrollbar params ──

fn (s &ScrollBox) eff_sb_width() f32 {
	return if s.sb_width > 0 { s.sb_width } else { f32(14) }
}

fn (s &ScrollBox) eff_sb_radius() f32 {
	return if s.sb_radius >= 0 { s.sb_radius } else { f32(3) }
}

fn (s &ScrollBox) eff_sb_min_thumb() f32 {
	return if s.sb_min_thumb > 0 { s.sb_min_thumb } else { f32(24) }
}

fn (s &ScrollBox) eff_sb_track_color(ctx &RenderContext) Color {
	return if s.sb_track_color.a > 0 { s.sb_track_color } else { ctx.theme.scrollbar_bg }
}

fn (s &ScrollBox) eff_sb_thumb_color(ctx &RenderContext) Color {
	return if s.sb_thumb_color.a > 0 { s.sb_thumb_color } else { ctx.theme.scrollbar_thumb }
}

fn (s &ScrollBox) eff_sb_thumb_hover(ctx &RenderContext) Color {
	return if s.sb_thumb_hover_color.a > 0 {
		s.sb_thumb_hover_color
	} else {
		ctx.theme.scrollbar_hover
	}
}

fn (s &ScrollBox) eff_sb_thumb_drag(ctx &RenderContext) Color {
	return if s.sb_thumb_drag_color.a > 0 {
		s.sb_thumb_drag_color
	} else {
		ctx.theme.scrollbar_drag
	}
}

// has_scrollbar - полоса нужна, только если содержимое выше (шире) видимой области за вычетом pad.
fn (s &ScrollBox) has_scrollbar() bool {
	if s.dir == .vertical {
		return s.eff_content_h > s.bounds.h - s.pad * 2
	} else {
		return s.eff_content_w > s.bounds.w - s.pad * 2
	}
}

// max_scroll - максимум scroll_y (вертикаль) или scroll_x (горизонталь): содержимое минус видимая область, не меньше 0.
pub fn (s &ScrollBox) max_scroll() f32 {
	if s.dir == .vertical {
		return max_f32(0, s.eff_content_h - (s.bounds.h - s.pad * 2))
	} else {
		return max_f32(0, s.eff_content_w - (s.bounds.w - s.pad * 2))
	}
}

// content_rect - прямоугольник полного содержимого (без смещения прокрутки): ширина (высота) уменьшена на толщину полосы, если она показана; длина вдоль оси прокрутки равна eff_content_*.
fn (s &ScrollBox) content_rect() Rect {
	sbsz := if s.has_scrollbar() { s.eff_sb_width() } else { f32(0) }
	if s.dir == .vertical {
		return Rect{
			x: s.bounds.x + s.pad
			y: s.bounds.y + s.pad
			w: s.bounds.w - s.pad * 2 - sbsz
			h: s.eff_content_h
		}
	} else {
		return Rect{
			x: s.bounds.x + s.pad
			y: s.bounds.y + s.pad
			w: s.eff_content_w
			h: s.bounds.h - s.pad * 2 - sbsz
		}
	}
}

// scrollbar_rects - (дорожка, ползунок) для текущей оси; пустые Rect, если полоса не нужна.
// Длина ползунка пропорциональна видимой доле (но не меньше sb_min_thumb), положение - по доле прокрутки.
fn (s &ScrollBox) scrollbar_rects() (Rect, Rect) {
	if s.dir == .vertical {
		vis_h := s.bounds.h - s.pad * 2
		ch := s.eff_content_h
		if ch <= vis_h {
			return Rect{}, Rect{}
		}
		sbw := s.eff_sb_width()
		track := Rect{
			x: s.bounds.x + s.bounds.w - s.pad - sbw
			y: s.bounds.y + s.pad
			w: sbw
			h: vis_h
		}
		thumb_h := max_f32(s.eff_sb_min_thumb(), vis_h * (vis_h / ch))
		ms := s.max_scroll()
		ratio := if ms > 0 { s.scroll_y / ms } else { f32(0) }
		thumb_y := track.y + ratio * (vis_h - thumb_h)
		thumb := Rect{
			x: track.x + 2
			y: thumb_y
			w: sbw - 4
			h: thumb_h
		}
		return track, thumb
	} else {
		vis_w := s.bounds.w - s.pad * 2
		cw := s.eff_content_w
		if cw <= vis_w {
			return Rect{}, Rect{}
		}
		sbh := s.eff_sb_width()
		track := Rect{
			x: s.bounds.x + s.pad
			y: s.bounds.y + s.bounds.h - s.pad - sbh
			w: vis_w
			h: sbh
		}
		thumb_w := max_f32(s.eff_sb_min_thumb(), vis_w * (vis_w / cw))
		ms := s.max_scroll()
		ratio := if ms > 0 { s.scroll_x / ms } else { f32(0) }
		thumb_x := track.x + ratio * (vis_w - thumb_w)
		thumb := Rect{
			x: thumb_x
			y: track.y + 2
			w: thumb_w
			h: sbh - 4
		}
		return track, thumb
	}
}

// disable_child_clip - выключает собственный клип у дочернего VBox/HBox: обрезкой занимается ScrollBox, а клип бокса мог бы срезать содержимое при сдвиге.
fn disable_child_clip(mut w Widget) {
	if mut w is VBox {
		w.box.clip = false
	} else if mut w is HBox {
		w.box.clip = false
	}
}

// ───────────── Drawing ─────────────────────────────────

pub fn (mut s ScrollBox) arrange(mut ctx RenderContext) {
	if !s.visible {
		return
	}

	// Размер содержимого - из measure() детей
	s.update_eff_content_size(ctx)

	// Размер содержимого мог измениться - возвращаем прокрутку в допустимый диапазон.
	// Clamp scroll
	if s.dir == .vertical {
		s.scroll_y = clamp_f32(s.scroll_y, 0, s.max_scroll())
	} else {
		s.scroll_x = clamp_f32(s.scroll_x, 0, s.max_scroll())
	}

	// Layout children into content area, shifted by scroll offset. Один ребёнок
	// занимает всю область содержимого; несколько - стопкой, каждый своего
	// размера (child_sizes), поперёк оси - на всю ширину (высоту).
	cr := s.content_rect()
	single := s.children.len == 1
	mut pos := f32(0)
	for i, mut c in s.children {
		size := if single || i >= s.child_sizes.len {
			if s.dir == .vertical { cr.h } else { cr.w }
		} else {
			s.child_sizes[i]
		}
		child_r := if s.dir == .vertical {
			Rect{
				x: cr.x
				y: cr.y - s.scroll_y + pos
				w: cr.w
				h: size
			}
		} else {
			Rect{
				x: cr.x - s.scroll_x + pos
				y: cr.y
				w: size
				h: cr.h
			}
		}
		pos += size + s.spacing
		disable_child_clip(mut c)
		arrange_child(mut c, child_r, mut ctx)
	}
}

pub fn (mut s ScrollBox) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}

	if s.bg.a > 0 {
		ctx.fill_rect(s.bounds, s.bg)
	}

	// Clip to visible viewport
	sbsz := if s.has_scrollbar() { s.eff_sb_width() } else { f32(0) }
	viewport := if s.dir == .vertical {
		Rect{
			x: s.bounds.x + s.pad
			y: s.bounds.y + s.pad
			w: s.bounds.w - s.pad * 2
			h: s.bounds.h - s.pad * 2
		}
	} else {
		Rect{
			x: s.bounds.x + s.pad
			y: s.bounds.y + s.pad
			w: s.bounds.w - s.pad * 2
			h: s.bounds.h - s.pad * 2 - sbsz
		}
	}
	ctx.push_clip(viewport)

	ctx.begin_disabled(s.enabled)
	for mut c in s.children {
		c.draw(mut ctx)
	}
	ctx.end_disabled(s.enabled)

	ctx.pop_clip()

	// ── Scrollbar ──
	if s.has_scrollbar() {
		track, thumb := s.scrollbar_rects()
		sb_rad := s.eff_sb_radius()

		track_c := s.eff_sb_track_color(ctx)
		if track_c.a > 0 {
			ctx.fill_rounded_rect(track, track_c, sb_rad)
		}

		thumb_c := if !ctx.is_enabled(s.enabled) {
			ctx.disabled_color(s.eff_sb_thumb_color(ctx))
		} else if s.sb_dragging {
			s.eff_sb_thumb_drag(ctx)
		} else if s.sb_hovered {
			s.eff_sb_thumb_hover(ctx)
		} else {
			s.eff_sb_thumb_color(ctx)
		}
		ctx.fill_rounded_rect(thumb, thumb_c, sb_rad)
	}
}

// ───────────── Events ──────────────────────────────────

pub fn (mut s ScrollBox) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible {
		return false
	}
	if !s.enabled && is_input_event(event) {
		s.sb_dragging = false
		s.sb_hovered = false
		return false
	}

	if s.sb_dragging {
		match event.typ {
			.mouse_move {
				track, _ := s.scrollbar_rects()
				ms := s.max_scroll()
				if s.dir == .vertical {
					if track.h <= 0 {
						return true
					}
					ch := s.eff_content_h
					vis_h := track.h
					thumb_h := max_f32(s.eff_sb_min_thumb(), vis_h * (vis_h / ch))
					drag_range := vis_h - thumb_h
					if drag_range <= 0 {
						return true
					}
					dy := event.mouse_y - s.sb_drag_start_y
					s.scroll_y = clamp_f32(s.sb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
				} else {
					if track.w <= 0 {
						return true
					}
					cw := s.eff_content_w
					vis_w := track.w
					thumb_w := max_f32(s.eff_sb_min_thumb(), vis_w * (vis_w / cw))
					drag_range := vis_w - thumb_w
					if drag_range <= 0 {
						return true
					}
					dx := event.mouse_x - s.sb_drag_start_x
					s.scroll_x = clamp_f32(s.sb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					s.sb_dragging = false
					return true
				}
			}
			else {}
		}

		return true
	}

	// Для колеса позиция мыши берётся из активного контекста (в самом событии колеса координат мыши нет), иначе - из события.
	mx := if event.typ == .mouse_wheel {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			ctx_ptr.mouse_x
		} else {
			event.mouse_x
		}
	} else {
		event.mouse_x
	}
	my := if event.typ == .mouse_wheel {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			ctx_ptr.mouse_y
		} else {
			event.mouse_y
		}
	} else {
		event.mouse_y
	}

	s.hovered = s.bounds.contains(mx, my)

	// ── Scrollbar track/thumb interactions (non-wheel) ──
	match event.typ {
		.mouse_move {
			if s.hovered && s.has_scrollbar() {
				track, _ := s.scrollbar_rects()
				s.sb_hovered = track.contains(event.mouse_x, event.mouse_y)
			} else {
				s.sb_hovered = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && s.hovered && s.has_scrollbar() {
				track, thumb := s.scrollbar_rects()

				if thumb.contains(event.mouse_x, event.mouse_y) {
					s.sb_dragging = true
					s.sb_drag_start_y = event.mouse_y
					s.sb_drag_start_x = event.mouse_x
					s.sb_drag_start_scroll = if s.dir == .vertical {
						s.scroll_y
					} else {
						s.scroll_x
					}
					return true
				}

				if track.contains(event.mouse_x, event.mouse_y) {
					if s.dir == .vertical {
						vis_h := track.h
						if event.mouse_y < thumb.y {
							s.scroll_y = max_f32(0, s.scroll_y - vis_h)
						} else {
							s.scroll_y = min_f32(s.max_scroll(), s.scroll_y + vis_h)
						}
					} else {
						vis_w := track.w
						if event.mouse_x < thumb.x {
							s.scroll_x = max_f32(0, s.scroll_x - vis_w)
						} else {
							s.scroll_x = min_f32(s.max_scroll(), s.scroll_x + vis_w)
						}
					}
					return true
				}
			}
		}
		else {}
	}

	// ── Pass events to children FIRST ──
	for i := s.children.len - 1; i >= 0; i-- {
		if s.children[i].handle_event(event, app) {
			return true
		}
	}

	// ── ScrollBox own wheel scroll (only if children didn't handle it) ──
	if event.typ == .mouse_wheel && !s.wheel {
		return false
	}
	if event.typ == .mouse_wheel {
		if s.hovered {
			if s.dir == .vertical {
				old := s.scroll_y
				s.scroll_y -= event.wheel_y * s.scroll_speed
				s.scroll_y = clamp_f32(s.scroll_y, 0, s.max_scroll())
				if s.scroll_y != old {
					return true
				}
			} else {
				// Horizontal: use wheel_x if available, fallback to wheel_y
				delta := if event.wheel_x != 0 { event.wheel_x } else { -event.wheel_y }
				old := s.scroll_x
				s.scroll_x += delta * s.scroll_speed
				s.scroll_x = clamp_f32(s.scroll_x, 0, s.max_scroll())
				if s.scroll_x != old {
					return true
				}
			}
		}
	}

	return false
}

// ═══════════════════════════════════════════════════════
// set_widget_bounds — assigns bounds to any known widget
// ═══════════════════════════════════════════════════════

// Реализовано через интерфейс Layouted (widget_tree.v) — см.
// раздел «Дерево виджетов» в PROJECT.md. Неизвестный (не
// реализующий Layouted) виджет молча игнорируется, как и раньше.
fn set_widget_bounds(mut w Widget, r Rect) {
	if mut w is Layouted {
		w.set_bounds(r)
	}
}

// Фабрики: panel() / stack() - пустые контейнеры; scroll_box(content_h) - вертикальный, scroll_box_h(content_w) - горизонтальный (0 = размер из measure() ребёнка).
pub fn panel() &Panel {
	return &Panel{}
}

pub fn stack() &Stack {
	return &Stack{}
}

pub fn scroll_box(content_h f32) &ScrollBox {
	return &ScrollBox{
		dir:       .vertical
		content_h: content_h
	}
}

pub fn scroll_box_h(content_w f32) &ScrollBox {
	return &ScrollBox{
		dir:       .horizontal
		content_w: content_w
	}
}
