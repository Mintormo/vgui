module vgui

import os

// ═══════════════════════════════════════════════════════
// css_apply — как таблица стилей попадает на экран
// ═══════════════════════════════════════════════════════
//
// Разбор - css.v, значения свойств - css_props.v, модель целиком - PROJECT.md,
// «Стили CSS». Здесь:
//   1. метки виджета для селекторов: #id и классы (CssTags, поле `css` у каждого
//      виджета) и функции для них;
//   2. RenderContext.draw_child — отрисовка ребёнка с подменой темы. Контейнеры
//      рисуют детей через неё, а не через w.draw(): только так правило узнаёт
//      предков виджета (`.sidebar button`) - указателя на родителя у виджета нет
//      (PROJECT.md, «Дерево виджетов»), поэтому цепочка предков копится в
//      ctx.css_stack по ходу обхода сверху вниз;
//   3. корневые правила (:root, menu, tooltip...) — css_base_theme: они
//      вшиваются в саму тему окна, потому что попапы и уведомления рисуются
//      после дерева, когда подменённой темы уже нет;
//   4. установка таблицы окну/приложению и перезагрузка файла при изменении.
//
// Почему подмена темы, а не стили в каждом виджете: все виджеты уже берут
// цвета из ctx.theme (сотни мест), и копия темы с другими полями мгновенно
// работает для всех, без правки draw() у полусотни типов. Цена - копия Theme
// (~1 КБ) на каждый виджет, к которому подошло правило, за кадр.

// CssTags — метки виджета для селекторов: `#id` и `.классы`. Поле `css` есть у
// каждой структуры виджета; .vui заполняет его из `#id` и `.класс`, код - через
// set_css_id/add_css_class или прямым присваиванием (`btn.css.classes = [...]`).
pub struct CssTags {
pub mut:
	id      string
	classes []string
}

// CssTagged — «у виджета есть поле css». Интерфейс по полю: ему автоматически
// удовлетворяет любая структура с полем `css CssTags`, как HasVisibility -
// с полем visible (widget_tree.v).
//
// ВАЖНО: менять метки через интерфейс можно только присваиванием поля целиком
// (`w.css = tags`). `w.css.classes << x` через интерфейс компилируется, но
// пишет во временную копию массива, и изменение молча теряется (проверено на
// V 0137eb5) - поэтому функции ниже собирают новый CssTags и присваивают его.
pub interface CssTagged {
mut:
	css CssTags
}

// set_css_id задаёт виджету имя для селектора `#id`. Кадр не инвалидирует (как
// все сеттеры виджетов): в своём цикле - Window.invalidate_all().
pub fn set_css_id(mut w Widget, id string) {
	if mut w is CssTagged {
		mut tags := w.css
		tags.id = id
		w.css = tags
	}
}

// add_css_class добавляет класс (повторное добавление ничего не меняет).
pub fn add_css_class(mut w Widget, name string) {
	if mut w is CssTagged {
		if name in w.css.classes {
			return
		}
		mut tags := w.css
		mut classes := tags.classes.clone()
		classes << name
		tags.classes = classes
		w.css = tags
	}
}

// remove_css_class убирает класс (если его не было - ничего).
pub fn remove_css_class(mut w Widget, name string) {
	if mut w is CssTagged {
		mut tags := w.css
		tags.classes = tags.classes.filter(it != name)
		w.css = tags
	}
}

// has_css_class — есть ли у виджета класс.
pub fn has_css_class(w &Widget, name string) bool {
	if w is CssTagged {
		return name in w.css.classes
	}
	return false
}

// css_tags_of — метки виджета (пустые, если поля css у типа нет).
pub fn css_tags_of(w &Widget) CssTags {
	if w is CssTagged {
		return w.css
	}
	return CssTags{}
}

// CssNode — звено цепочки предков рисуемого виджета (ctx.css_stack).
struct CssNode {
	kind int
	tags CssTags
}

// ─── Отступы виджета из CSS ────────────────────────────

// CssInsets — отступы по четырём сторонам (padding из CSS).
struct CssInsets {
	top    f32
	right  f32
	bottom f32
	left   f32
}

// css_insets_all — одинаковый отступ со всех сторон (свой pad виджета).
fn css_insets_all(p f32) CssInsets {
	return CssInsets{p, p, p, p}
}

// horizontal / vertical — сумма отступов по оси (лево+право, верх+низ).
fn (i CssInsets) horizontal() f32 {
	return i.left + i.right
}

fn (i CssInsets) vertical() f32 {
	return i.top + i.bottom
}

// inset — прямоугольник r без отступов i (не меньше нуля по каждой оси).
fn (r Rect) inset(i CssInsets) Rect {
	return Rect{r.x + i.left, r.y + i.top, max_f32(0, r.w - i.horizontal()), max_f32(0,
		r.h - i.vertical())}
}

// CssBox — padding и gap, заданные таблицей стилей ТЕКУЩЕМУ виджету: тому,
// который сейчас рисуется, измеряется, раскладывается или получает событие
// (ctx.css_box). В отличие от шрифта и цветов, отступы не наследуются - у
// каждого виджета свои (как в CSS), поэтому они лежат не в Theme, а здесь и
// сбрасываются при входе в каждый виджет.
//
// owner — адрес виджета, которому отступы заданы. Виджет читает их через
// ctx.css_pad_of(себя, ...): так внутренняя часть составного виджета (метка,
// нарисованная им напрямую, мимо draw_child) не возьмёт отступы владельца.
struct CssBox {
mut:
	owner   voidptr
	kind    int
	has_pad bool
	pad     CssInsets
	has_gap bool
	gap_row f32
	gap_col f32
	// размеры (width, min-width...): -1 - не заданы; применяет measure_widget
	// (css_apply_size)
	has_size bool
	width    f32 = -1
	height   f32 = -1
	min_w    f32 = -1
	max_w    f32 = -1
	min_h    f32 = -1
	max_h    f32 = -1
}

// css_apply_size накладывает размеры из CSS на SizeHint виджета (зовёт
// measure_widget, пока текущий виджет - этот). Порядок как в CSS: width
// фиксирует размер (min = max = width), max- ограничивает сверху, min-
// побеждает max-. Ось с размерами из CSS помечается (css_w/css_h): их
// уважает и ребёнок с весом (flex) в hbox/vbox, у которого свой hint
// вдоль главной оси иначе не учитывается.
fn css_apply_size(h SizeHint, b &CssBox) SizeHint {
	mut r := h
	r.w, r.min_w, r.max_w, r.css_w = css_limit_axis(r.w, r.min_w, r.max_w, b.width, b.min_w,
		b.max_w)
	r.h, r.min_h, r.max_h, r.css_h = css_limit_axis(r.h, r.min_h, r.max_h, b.height, b.min_h,
		b.max_h)
	if b.width >= 0 {
		r.h_policy = .fixed
	}
	if b.height >= 0 {
		r.v_policy = .fixed
	}
	return r
}

// css_limit_axis — одна ось: (желаемый, min, max, задано ли из CSS).
fn css_limit_axis(pref f32, mn f32, mx f32, fixed f32, css_min f32, css_max f32) (f32, f32, f32, bool) {
	if fixed < 0 && css_min < 0 && css_max < 0 {
		return pref, mn, mx, false
	}
	mut p := pref
	mut lo := mn
	mut hi := mx
	if fixed >= 0 {
		p, lo, hi = fixed, fixed, fixed
	}
	if css_max >= 0 {
		hi = min_f32(hi, css_max)
		lo = min_f32(lo, css_max)
	}
	if css_min >= 0 {
		lo = max_f32(lo, css_min)
		hi = max_f32(hi, lo)
	}
	return clamp_f32(p, lo, hi), lo, hi, true
}

// css_pad_of — внутренний отступ виджета owner: из CSS, если таблица задала
// его именно этому виджету, иначе свой равномерный pad.
fn (ctx &RenderContext) css_pad_of(owner voidptr, pad f32) CssInsets {
	if ctx.css_box.has_pad && ctx.css_box.owner == owner {
		return ctx.css_box.pad
	}
	return css_insets_all(pad)
}

// css_pad_xy_of — как css_pad_of, но свой отступ разный по осям (кнопка:
// measure_pad_x слева/справа, measure_pad_y сверху/снизу).
fn (ctx &RenderContext) css_pad_xy_of(owner voidptr, pad_x f32, pad_y f32) CssInsets {
	if ctx.css_box.has_pad && ctx.css_box.owner == owner {
		return ctx.css_box.pad
	}
	return CssInsets{pad_y, pad_x, pad_y, pad_x}
}

// css_gap_of — промежутки между детьми виджета owner (строки, колонки): из CSS
// или свои row/col.
fn (ctx &RenderContext) css_gap_of(owner voidptr, row f32, col f32) (f32, f32) {
	if ctx.css_box.has_gap && ctx.css_box.owner == owner {
		return ctx.css_box.gap_row, ctx.css_box.gap_col
	}
	return row, col
}

// css_box_owner_of — адрес виджета, которому принадлежит BoxLayout: сам
// BoxLayout лежит полем `box` внутри HBox/VBox, и его адрес не равен адресу
// виджета, который видят селекторы. Отступы текущего виджета относятся к
// этому BoxLayout, только если текущий виджет - HBox/VBox и b - его поле box.
fn (ctx &RenderContext) css_box_owner_of(b &BoxLayout) voidptr {
	o := ctx.css_box.owner
	if isnil(o) {
		return unsafe { nil }
	}
	match ctx.css_box.kind {
		kind_hbox {
			h := unsafe { &HBox(o) }
			if voidptr(&h.box) == voidptr(b) {
				return o
			}
		}
		kind_vbox {
			v := unsafe { &VBox(o) }
			if voidptr(&v.box) == voidptr(b) {
				return o
			}
		}
		else {}
	}
	return unsafe { nil }
}

// ─── Вход в виджет: подмена темы и отступов ────────────
//
// Таблица стилей действует на виджет в четырёх обходах дерева: отрисовка
// (draw_child), измерение (measure_widget), раскладка (arrange_widget) и
// события (event_child). Отрисовка применяет все подошедшие правила; три
// остальных - только объявления, от которых зависят размеры и геометрия
// текста (шрифт, padding, gap - CssDecl.layout), и только если такие в
// таблице вообще есть (Stylesheet.has_layout). Иначе раскладка с шрифтом
// 20 и отрисовка с шрифтом 15 разошлись бы, а клик в поле ввода ставил бы
// курсор по чужому шрифту.
//
// Цепочка предков для селекторов копится в ctx.css_stack: вход кладёт
// виджет на стек, выход возвращает стек к прежней длине. Поэтому все четыре
// обхода обязаны идти от родителя к ребёнку через эти обёртки - измерение
// ребёнка внутри measure()/arrange() родителя так и устроено.

// CssLayoutSaved — что вернуть при выходе из виджета (css_leave_layout).
struct CssLayoutSaved {
	stack_len   int
	font_size   f32
	font_bold   bool
	font_italic bool
	font_mono   bool
	box         CssBox
}

// css_layout_active — нужна ли обходам раскладки и событий таблица стилей.
fn (ctx &RenderContext) css_layout_active() bool {
	return !isnil(ctx.stylesheet) && ctx.stylesheet.has_layout
}

// css_enter_layout — вход в виджет для measure/arrange/событий: виджет на
// стек предков, отступы предыдущего виджета сброшены, затем подошедшие
// правила пишут шрифт (в ctx.theme, наследуется детьми) и отступы (в
// ctx.css_box, только этому виджету). Пару ей - css_leave_layout.
//
// Принимает адрес виджета и его метки, а не &Widget: measure_widget зовёт её
// внутри `if w is Measurable`, где w уже сужен до интерфейса Measurable.
fn (mut ctx RenderContext) css_enter_layout(addr voidptr, tags CssTags) CssLayoutSaved {
	saved := CssLayoutSaved{
		stack_len:   ctx.css_stack.len
		font_size:   ctx.theme.font_size
		font_bold:   ctx.theme.font_bold
		font_italic: ctx.theme.font_italic
		font_mono:   ctx.theme.font_mono
		box:         ctx.css_box
	}
	kind := widget_type_tag(addr)
	ctx.css_stack << CssNode{
		kind: kind
		tags: tags
	}
	ctx.css_box = CssBox{}
	if kind <= 0 || kind > css_max_kind {
		return saved
	}
	ss := ctx.stylesheet
	for rule in ss.rules {
		if !rule.decls.any(it.layout) || !css_selector_matches(rule.selector, ctx.css_stack) {
			continue
		}
		for d in rule.decls {
			if !d.layout {
				continue
			}
			for f in d.fields_by_kind[kind] {
				css_write_field(mut ctx.theme, mut ctx.css_box, f, d.value) or {}
			}
		}
	}
	if ctx.css_box.has_pad || ctx.css_box.has_gap || ctx.css_box.has_size {
		ctx.css_box.owner = addr
		ctx.css_box.kind = kind
	}
	return saved
}

// css_leave_layout — выход из виджета: шрифт и отступы родителя обратно,
// стек - к прежней длине (не pop: обход мог прерваться посреди поддерева).
fn (mut ctx RenderContext) css_leave_layout(s CssLayoutSaved) {
	ctx.theme.font_size = s.font_size
	ctx.theme.font_bold = s.font_bold
	ctx.theme.font_italic = s.font_italic
	ctx.theme.font_mono = s.font_mono
	ctx.css_box = s.box
	if ctx.css_stack.len > s.stack_len {
		ctx.css_stack.trim(s.stack_len)
	}
}

// CssTraversalSaved — состояние стилей окна на момент, когда начался новый
// обход дерева с корня (Window.css_begin_traversal).
struct CssTraversalSaved {
	stack []CssNode
	theme Theme
	box   CssBox
	busy  bool
}

// css_begin_traversal — новый обход с корней окна (кадр, раскладка, измерение
// содержимого) начинается с чистого состояния: пустой стек предков, тема окна,
// отступов нет. Обычно оно и так чистое (проверка - и выход, без копий). Не
// чистое - если обход начался посреди другого: обработчик клика (внутри
// event_child, с подменённым шрифтом кнопки) открыл модальный диалог, и его
// цикл перерисовывает и это окно. Состояние прерванного обхода сохраняется и
// возвращается в css_end_traversal.
//
// Метод неизменяемого окна (его зовёт и measure_content): меняются только поля
// стилей контекста, и css_end_traversal их возвращает.
fn (w &Window) css_begin_traversal() CssTraversalSaved {
	if w.ctx.css_stack.len == 0 && isnil(w.ctx.css_box.owner) {
		return CssTraversalSaved{}
	}
	mut ctx := unsafe { &RenderContext(&w.ctx) }
	saved := CssTraversalSaved{
		stack: ctx.css_stack.clone()
		theme: ctx.theme
		box:   ctx.css_box
		busy:  true
	}
	ctx.css_stack = []CssNode{}
	ctx.theme = w.styled_theme()
	ctx.css_box = CssBox{}
	return saved
}

// css_end_traversal — вернуть состояние прерванного обхода (если был).
fn (w &Window) css_end_traversal(s CssTraversalSaved) {
	if !s.busy {
		return
	}
	mut ctx := unsafe { &RenderContext(&w.ctx) }
	ctx.css_stack = s.stack
	ctx.theme = s.theme
	ctx.css_box = s.box
}

// event_child передаёт событие ребёнку контейнера с учётом таблицы стилей
// (шрифт и отступы ребёнка - как при отрисовке). Контейнеры, рисующие детей
// через draw_child, раздают им события через неё. Без правил о шрифте и
// отступах - просто w.handle_event().
//
// Контекст - окна, которое сейчас обрабатывает событие (app.active_ctx; его
// же виджеты берут в handle_event для измерения текста). Его поля шрифта и
// отступов меняются на время вызова, как в measure_widget.
pub fn event_child(mut w Widget, ev &GuiEvent, app &App) bool {
	if isnil(app) || isnil(app.active_ctx) || !app.active_ctx.css_layout_active() {
		return w.handle_event(ev, app)
	}
	mut ctx := unsafe { &RenderContext(app.active_ctx) }
	saved := ctx.css_enter_layout(widget_object_addr(&w), css_tags_of(&w))
	handled := w.handle_event(ev, app)
	ctx.css_leave_layout(saved)
	return handled
}

// ─── Отрисовка с подменой темы ─────────────────────────

// draw_child рисует ребёнка контейнера с учётом таблицы стилей окна. Без таблицы -
// просто w.draw(). Контейнеры обязаны рисовать детей через неё (иначе правила
// с предками, `.sidebar button`, не увидят этого контейнера в цепочке).
//
// Шаги: (1) виджет кладётся в ctx.css_stack - теперь он «текущий», а стек под ним -
// его предки; отступы родителя (ctx.css_box) сбрасываются - они не наследуются;
// (2) ищется, подходит ли хоть одно правило; если нет - обычная отрисовка;
// (3) иначе тема сохраняется, все подошедшие правила по порядку каскада пишут
// свои поля в ctx.theme (padding/gap - в ctx.css_box), и виджет со всем
// поддеревом рисуется уже с ней; (4) тема, отступы и стек восстанавливаются.
pub fn (mut ctx RenderContext) draw_child(mut w Widget) {
	if isnil(ctx.stylesheet) || ctx.stylesheet.rules.len == 0 {
		w.draw(mut ctx)
		return
	}
	addr := widget_object_addr(&w)
	kind := widget_type_tag(addr)
	stack_len := ctx.css_stack.len
	saved_box := ctx.css_box
	ctx.css_stack << CssNode{
		kind: kind
		tags: css_tags_of(&w)
	}
	ctx.css_box = CssBox{}
	ss := ctx.stylesheet
	// (2) сначала только проверка - копию темы делаем, лишь если правило нашлось
	mut matched := false
	for rule in ss.rules {
		if css_selector_matches(rule.selector, ctx.css_stack) {
			matched = true
			break
		}
	}
	if !matched {
		w.draw(mut ctx)
		ctx.css_box = saved_box
		ctx.css_stack.trim(stack_len)
		return
	}
	// (3) правила уже отсортированы по (специфичность, порядок в файле) -
	// css_sort_rules: применяем подряд, и более сильное пишет последним
	saved := ctx.theme
	mut fill := Color{}
	mut has_fill := false
	mut has_radius := false
	if kind > 0 && kind <= css_max_kind {
		for rule in ss.rules {
			if !css_selector_matches(rule.selector, ctx.css_stack) {
				continue
			}
			for d in rule.decls {
				for f in d.fields_by_kind[kind] {
					if f == css_fill_field {
						fill = d.value.color
						has_fill = true
						continue
					}
					if f == 'border_radius' {
						has_radius = true
					}
					// тип значения проверен при разборе (css_check_value) - ошибки не будет
					css_write_field(mut ctx.theme, mut ctx.css_box, f, d.value) or {}
				}
			}
		}
	}
	if ctx.css_box.has_pad || ctx.css_box.has_gap || ctx.css_box.has_size {
		ctx.css_box.owner = addr
		ctx.css_box.kind = kind
	}
	// заливка контейнера без своего цвета в теме (vbox, grid...): под детьми.
	// Скругление - только если правило задало border-radius, иначе прямоугольник.
	if has_fill && w is Layouted {
		r := w.bounds_of()
		radius := if has_radius { ctx.theme.border_radius } else { f32(0) }
		ctx.fill_rounded_rect(r, fill, radius)
	}
	w.draw(mut ctx)
	// (4)
	ctx.theme = saved
	ctx.css_box = saved_box
	ctx.css_stack.trim(stack_len)
}

// css_selector_matches — подходит ли селектор к вершине стека (стек - цепочка
// от корня окна до рисуемого виджета включительно).
fn css_selector_matches(sel &CssSelector, stack []CssNode) bool {
	if stack.len == 0 || sel.parts.len == 0 {
		return false
	}
	return css_match_at(sel, 0, stack, stack.len - 1)
}

// css_match_at — звено pi селектора на узле si стека, и рекурсивно остальные
// звенья на предках. Для «потомка» перебираются все предки (с возвратом: в
// `a > b c` первый найденный b может не иметь родителя a, а следующий - иметь).
fn css_match_at(sel &CssSelector, pi int, stack []CssNode, si int) bool {
	if !css_compound_matches(sel.parts[pi], stack[si]) {
		return false
	}
	if pi + 1 >= sel.parts.len {
		return true
	}
	if sel.parts[pi].rel == .child {
		return si > 0 && css_match_at(sel, pi + 1, stack, si - 1)
	}
	for j := si - 1; j >= 0; j-- {
		if css_match_at(sel, pi + 1, stack, j) {
			return true
		}
	}
	return false
}

fn css_compound_matches(c &CssCompound, n &CssNode) bool {
	if c.kind != 0 && c.kind != n.kind {
		return false
	}
	if c.id.len > 0 && c.id != n.tags.id {
		return false
	}
	for cls in c.classes {
		if cls !in n.tags.classes {
			return false
		}
	}
	return true
}

// css_sort_rules — порядок каскада: по специфичности, при равной - по месту в
// файле. Тогда при отрисовке правила применяются просто подряд.
fn css_sort_rules(mut rules []CssRule) {
	rules.sort_with_compare(fn (a &CssRule, b &CssRule) int {
		if a.specificity != b.specificity {
			return if a.specificity < b.specificity { -1 } else { 1 }
		}
		return if a.order < b.order {
			-1
		} else if a.order > b.order {
			1
		} else {
			0
		}
	})
}

// css_base_theme — тема окна с применёнными корневыми правилами (:root, menu,
// tooltip, notification, dropdown). nil-таблица - тема без изменений.
pub fn css_base_theme(theme Theme, ss &Stylesheet) Theme {
	mut t := theme
	if isnil(ss) {
		return t
	}
	// отступов у корневых правил нет (padding/gap к :root неприменимы),
	// CssBox здесь только для единой записи через css_write_field
	mut box := CssBox{}
	for rule in ss.root_rules {
		for d in rule.decls {
			for f in d.root_fields {
				css_write_field(mut t, mut box, f, d.value) or {}
			}
		}
	}
	return t
}

// ─── Окно и приложение ─────────────────────────────────

// set_stylesheet задаёт окну собственную таблицу стилей: после этого таблица
// приложения (App.set_stylesheet) его больше не меняет. nil - снять свою таблицу
// и вернуться к таблице приложения (w.app_stylesheet; у приложения её нет -
// окно без стилей). Окно совсем без стилей при стилях у приложения - пустая
// таблица: set_stylesheet(parse_stylesheet('', 'none')!).
pub fn (mut w Window) set_stylesheet(ss &Stylesheet) {
	if isnil(ss) {
		w.css_explicit = false
		w.apply_stylesheet(w.app_stylesheet)
		return
	}
	w.css_explicit = true
	w.apply_stylesheet(ss)
}

// apply_stylesheet ставит таблицу, не делая её явной - путь App.set_stylesheet.
// Тема окна пересобирается из исходной (без стилей, w.config.theme) - иначе
// корневые правила старой таблицы остались бы в ней навсегда.
fn (mut w Window) apply_stylesheet(ss &Stylesheet) {
	w.ctx.stylesheet = unsafe { ss }
	w.ctx.theme = css_base_theme(w.unstyled_theme(), ss)
	w.ctx.clear_text_cache()
	w.invalidate_all()
}

// unstyled_theme — тема окна без корневых правил CSS (заданная или светлая по умолчанию).
fn (w &Window) unstyled_theme() Theme {
	return w.config.theme or { light_theme() }
}

// styled_theme — тема окна вместе с корневыми правилами таблицы стилей: та,
// что стоит в ctx.theme вне обходов дерева (apply_stylesheet). Нужна
// css_begin_traversal, чтобы начать обход с чистой темы.
fn (w &Window) styled_theme() Theme {
	return css_base_theme(w.unstyled_theme(), w.ctx.stylesheet)
}

// stylesheet — текущая таблица стилей окна (nil - нет).
pub fn (w &Window) stylesheet() &Stylesheet {
	return w.ctx.stylesheet
}

// set_stylesheet задаёт таблицу стилей приложения: всем окнам и диалогам без
// своей таблицы и будущим (как App.set_theme). nil - убрать стили.
//
// Таблица запоминается и в окнах СО своей таблицей (app_stylesheet): указателя
// на App у окна нет, а Window.set_stylesheet(nil) должен вернуть окно именно к
// текущей таблице приложения.
pub fn (mut app App) set_stylesheet(ss &Stylesheet) {
	app.stylesheet = unsafe { ss }
	for mut w in app.windows {
		w.follow_app_stylesheet(ss)
	}
	for mut d in app.dialogs {
		d.win.follow_app_stylesheet(ss)
	}
}

// follow_app_stylesheet - окно узнаёт таблицу приложения (add_window/add_dialog,
// App.set_stylesheet) и применяет её, если своей таблицы у окна нет.
fn (mut w Window) follow_app_stylesheet(ss &Stylesheet) {
	w.app_stylesheet = unsafe { ss }
	if !w.css_explicit {
		w.apply_stylesheet(ss)
	}
}

// load_stylesheet читает CSS-файл и делает его таблицей приложения. watch -
// следить за файлом: при изменении он перечитывается сам (раз в
// css_watch_interval_ms, в pump_events). Ошибка в изменённом файле не роняет
// приложение: печатается в stderr, а на экране остаются прежние стили.
pub fn (mut app App) load_stylesheet(path string, watch bool) ! {
	ss := load_stylesheet(path)!
	app.set_stylesheet(ss)
	app.css_path = if watch { path } else { '' }
	app.css_mtime = os.file_last_mod_unix(path)
}

// css_watch_interval_ms — как часто проверять файл стилей при watch.
const css_watch_interval_ms = u64(500)

// poll_stylesheet — перечитать файл стилей, если он изменился. Зовётся из
// pump_events; сама решает, пора ли проверять (stat раз в полсекунды, а не
// на каждой итерации цикла). true - стили сменились, нужен кадр.
fn (mut app App) poll_stylesheet() bool {
	if app.css_path.len == 0 {
		return false
	}
	now := now_ms()
	if now < app.css_next_check {
		return false
	}
	app.css_next_check = now + css_watch_interval_ms
	mtime := os.file_last_mod_unix(app.css_path)
	if mtime == app.css_mtime {
		return false
	}
	app.css_mtime = mtime
	ss := load_stylesheet(app.css_path) or {
		eprintln('vgui: стили не перезагружены, остаются прежние: ${err.msg()}')
		return false
	}
	app.set_stylesheet(ss)
	return true
}
