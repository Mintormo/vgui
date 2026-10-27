module vgui

// ═══════════════════════════════════════════════════════
// Accordion — collapsible sections container
//
// Modes:
//   .single   — only one section open at a time (clicking
//                another closes the current one)
//   .multiple — any number of sections can be open/closed
//                independently
//
// Each section has a clickable header with title + arrow
// indicator, and a child widget shown when expanded.
//
// Usage (code):
//   mut acc := vgui.accordion()          // default: .single
//   acc.add_section('General', general_panel)
//   acc.add_section('Advanced', advanced_panel)
//   acc.sections[0].expanded = true      // open first
//
//   // or multi-mode:
//   mut acc2 := vgui.accordion_multi()
//   acc2.add_section('A', widget_a)
//   acc2.add_section('B', widget_b)
//
// Usage (YAML):
//   type: accordion
//   mode: single
//   header_height: 30
//   sections:
//     - title: General
//       expanded: true
//       child:
//         type: vbox
//         children: ...
//     - title: Advanced
//       child:
//         type: label
//         text: Hello
//
// Устройство:
//   - Accordion - контейнер без указателя на родителя; секции держит в
//     sections (виджет секции - &Widget).
//   - Раскрытие анимируется: у секции Anim `anim` (0 - свёрнута, 1 - развёрнута).
//     Шаг анимации делается в arrange() (а не в draw()), потому что от высоты
//     секций зависят bounds детей (PROJECT.md, "Фаза arrange").
//   - Высота содержимого секции: по умолчанию - "всё свободное место"
//     (section_child_height), при fit_content - по measure() содержимого
//     (PROJECT.md, "Accordion: высота секции по содержимому").
//   - Дочерние виджеты получают bounds ПОЛНОЙ высоты, а видимую часть
//     обрезает клип в draw() - так раскладка ребёнка не "дёргается" во время
//     анимации.
// ═══════════════════════════════════════════════════════

// AccordionMode - режим раскрытия секций.
pub enum AccordionMode {
	single   // only one section open at a time
	multiple // any number of sections can be open
}

// AccordionSection - одна секция: заголовок + дочерний виджет.
// Хранится по значению в Accordion.sections (копии при `sec := a.sections[i]`
// независимы, но widget - общий указатель).
struct AccordionSection {
mut:
	title    string
	icon     ItemIcon // иконка в заголовке между стрелкой и текстом (item_icon.v)
	expanded bool
	hovered  bool
	widget   &Widget = unsafe { nil }
	// Smooth animation for expand/collapse
	anim Anim = Anim{
		epsilon: 0.02
	}
	// fit_content: высота содержимого по measure() (снимается в arrange) -
	// для детей, чью высоту нельзя посчитать без ctx (не VBox/HBox)
	content_h f32
}

// Accordion - контейнер раскрывающихся секций. Цвета с альфой 0 означают
// "взять из темы" (см. eff_* ниже). scroll_y - собственная прокрутка колесом
// (не используется при fit_content, там прокручивает внешний ScrollBox).
@[heap]
pub struct Accordion {
pub mut:
	type_tag int = kind_accordion // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel    bool = true
	bounds   Rect
	sections []AccordionSection
	mode     AccordionMode = .single
	// fit_content - высота секции по её содержимому (VBox - сумма
	// фиксированных рядов, иначе measure()), а не «всё свободное место».
	// Нужен для .multiple: иначе каждая открытая секция занимает всю
	// высоту. В этом режиме аккордеон не прокручивается сам - кладите его
	// в ScrollBox: measure() и авто-высота ScrollBox отдают полную высоту.
	fit_content bool
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	// Appearance
	header_height f32 = 30
	header_pad    f32 = 8
	spacing       f32 = 1 // gap between sections
	pad           f32 // outer padding
	icon_size     f32 = 8 // arrow triangle size
	// размер иконки секции в заголовке и зазор до текста (не путать с icon_size - стрелкой)
	title_icon_size f32       = 16
	title_icon_gap  f32       = 6
	font_style      FontStyle = .bold
	font_size       int
	// Colors (0 = theme defaults)
	header_bg       Color = Color{0, 0, 0, 0}
	header_hover_bg Color = Color{0, 0, 0, 0}
	header_text     Color = Color{0, 0, 0, 0}
	content_bg      Color = Color{0, 0, 0, 0}
	border_color    Color = Color{0, 0, 0, 0}
	// Scroll support
	scroll_y     f32
	scroll_speed f32 = 30
	// Callback
	on_change fn (int, bool) = unsafe { nil } // (section_index, expanded)
	// Internal: шаг анимации делается в arrange() один раз за кадр.
	anim_frame u64 // ctx.frame_no последнего шага
	animating  bool
}

// ─── Constructors ──────────────────────────────────────

// accordion создаёт аккордеон в режиме .single (режим по умолчанию).
pub fn accordion() &Accordion {
	return &Accordion{}
}

// accordion_single - одновременно открыта максимум одна секция.
pub fn accordion_single() &Accordion {
	return &Accordion{
		mode: .single
	}
}

// accordion_multi - секции раскрываются независимо.
pub fn accordion_multi() &Accordion {
	return &Accordion{
		mode: .multiple
	}
}

// ─── Public API ────────────────────────────────────────

// add_section добавляет свёрнутую секцию. Ссылку на widget аккордеон хранит
// сам; владелец (Python-слой) обязан держать ребёнка живым.
pub fn (mut a Accordion) add_section(title string, widget &Widget) {
	a.sections << AccordionSection{
		title:  title
		widget: unsafe { widget }
	}
}

// set_section_icon задаёт иконку заголовка секции idx (ItemIcon{} - убрать);
// неверный индекс игнорируется.
pub fn (mut a Accordion) set_section_icon(idx int, ic ItemIcon) {
	widget_changed()
	if idx >= 0 && idx < a.sections.len {
		a.sections[idx].icon = ic
	}
}

// add_section_expanded добавляет секцию сразу раскрытой; в режиме .single
// предварительно сворачивает остальные. Anim новой секции стартует с 0,
// поэтому она "выезжает" анимацией.
pub fn (mut a Accordion) add_section_expanded(title string, widget &Widget) {
	// In single mode, collapse others first
	if a.mode == .single {
		for i in 0 .. a.sections.len {
			a.sections[i].expanded = false
		}
	}
	a.sections << AccordionSection{
		title:    title
		expanded: true
		widget:   unsafe { widget }
	}
}

pub fn (a &Accordion) get_section_count() int {
	return a.sections.len
}

pub fn (a &Accordion) is_expanded(idx int) bool {
	if idx >= 0 && idx < a.sections.len {
		return a.sections[idx].expanded
	}
	return false
}

// set_expanded раскрывает/сворачивает секцию программно (on_change НЕ зовётся).
// В .single раскрытие секции сворачивает остальные; индекс вне диапазона игнорируется.
pub fn (mut a Accordion) set_expanded(idx int, val bool) {
	widget_changed()
	if idx < 0 || idx >= a.sections.len {
		return
	}
	if val && a.mode == .single {
		for i in 0 .. a.sections.len {
			a.sections[i].expanded = i == idx
		}
	} else {
		a.sections[idx].expanded = val
	}
}

// toggle_section переключает секцию как по клику на заголовок и зовёт
// on_change(idx, expanded). В .single повторный клик по открытой секции
// сворачивает её (открытых секций может стать 0).
pub fn (mut a Accordion) toggle_section(idx int) {
	if idx < 0 || idx >= a.sections.len {
		return
	}
	if a.mode == .single {
		was_open := a.sections[idx].expanded
		for i in 0 .. a.sections.len {
			a.sections[i].expanded = false
		}
		if !was_open {
			a.sections[idx].expanded = true
		}
	} else {
		a.sections[idx].expanded = !a.sections[idx].expanded
	}
	if a.on_change != unsafe { nil } {
		a.on_change(idx, a.sections[idx].expanded)
	}
}

// expand_all раскрывает все секции (в .single ничего не делает); on_change не зовёт.
pub fn (mut a Accordion) expand_all() {
	if a.mode == .single {
		return
	}
	// no-op in single mode
	for i in 0 .. a.sections.len {
		a.sections[i].expanded = true
	}
}

// collapse_all сворачивает все секции; on_change не зовёт.
pub fn (mut a Accordion) collapse_all() {
	for i in 0 .. a.sections.len {
		a.sections[i].expanded = false
	}
}

// ─── Geometry ──────────────────────────────────────────

// Calculate total content height needed for all sections
fn (a &Accordion) total_content_height() f32 {
	if a.sections.len == 0 {
		return 0
	}
	mut h := a.pad * 2
	for i, sec in a.sections {
		h += a.header_height
		if sec.anim.value > 0.01 {
			child_h := a.child_height_at(i)
			h += child_h * sec.anim.value
		}
		if i < a.sections.len - 1 {
			h += a.spacing
		}
	}
	return h
}

// section_child_height - высота содержимого секции в режиме "всё свободное
// место": высота bounds минус заголовки, отступы и промежутки. Если остаток
// меньше 20 px, берётся запасное значение 60 (чтобы секция не схлопнулась).
fn (a &Accordion) section_child_height() f32 {
	// Use a fixed portion of available space per section, or the bounds height minus headers
	total_headers := f32(a.sections.len) * a.header_height + f32(a.sections.len - 1) * a.spacing +
		a.pad * 2
	avail := a.bounds.h - total_headers
	if avail < 20 {
		return 60
	}
	// minimum fallback
	return avail
}

// child_height_at - высота содержимого секции i: по содержимому при
// fit_content, иначе общая «всё свободное место».
fn (a &Accordion) child_height_at(i int) f32 {
	if !a.fit_content {
		return a.section_child_height()
	}
	sec := a.sections[i]
	if unsafe { sec.widget == nil } {
		return 0
	}
	return sec.content_h // measure() содержимого, снят в arrange()
}

// fit_height - полная высота при fit_content с содержимым секций из
// measure() (для measure() самого аккордеона: он бывает раньше arrange)
fn (a &Accordion) fit_height(ctx &RenderContext) f32 {
	if a.sections.len == 0 {
		return 0
	}
	mut h := a.pad * 2
	for i, sec in a.sections {
		h += a.header_height
		if sec.anim.value > 0.01 && unsafe { sec.widget != nil } {
			h += measure_widget(sec.widget, ctx).h * sec.anim.value
		}
		if i < a.sections.len - 1 {
			h += a.spacing
		}
	}
	return h
}

// area - прямоугольник, где аккордеон рисует и ловит события. При
// fit_content контент выходит за bounds (ScrollBox отдаёт ребёнку
// высоту видимой области), поэтому область - на всю высоту контента.
fn (a &Accordion) area() Rect {
	if !a.fit_content {
		return a.bounds
	}
	return Rect{a.bounds.x, a.bounds.y, a.bounds.w, max_f32(a.bounds.h, a.total_content_height())}
}

fn (a &Accordion) max_scroll() f32 {
	if a.fit_content {
		return 0 // прокручивает внешний ScrollBox
	}
	return max_f32(0, a.total_content_height() - a.bounds.h)
}

// hit_header - индекс секции, чей ЗАГОЛОВОК лежит под точкой (mx, my), или -1.
// Идёт по секциям сверху вниз, накапливая y так же, как draw() (с учётом
// анимированной высоты содержимого и scroll_y).
fn (a &Accordion) hit_header(mx f32, my f32) int {
	inner := a.bounds.shrunk(a.pad)
	mut y := inner.y - a.scroll_y
	for i, sec in a.sections {
		hr := Rect{inner.x, y, inner.w, a.header_height}
		if hr.contains(mx, my) {
			return i
		}
		y += a.header_height
		if sec.anim.value > 0.01 {
			y += a.child_height_at(i) * sec.anim.value
		}
		y += a.spacing
	}
	return -1
}

// ─── Effective colors ──────────────────────────────────

// eff_*: свой цвет виджета (если альфа > 0), иначе цвет из темы.
fn (a &Accordion) eff_header_bg(ctx &RenderContext) Color {
	if a.header_bg.a > 0 {
		return a.header_bg
	}
	return ctx.theme.eff_acc_header_bg()
}

fn (a &Accordion) eff_header_hover(ctx &RenderContext) Color {
	if a.header_hover_bg.a > 0 {
		return a.header_hover_bg
	}
	return ctx.theme.eff_acc_header_hover()
}

fn (a &Accordion) eff_header_text(ctx &RenderContext) Color {
	if a.header_text.a > 0 {
		return a.header_text
	}
	return ctx.theme.eff_acc_header_text()
}

fn (a &Accordion) eff_content_bg(ctx &RenderContext) Color {
	if a.content_bg.a > 0 {
		return a.content_bg
	}
	return ctx.theme.eff_acc_content_bg()
}

fn (a &Accordion) eff_border(ctx &RenderContext) Color {
	if a.border_color.a > 0 {
		return a.border_color
	}
	return ctx.theme.eff_acc_border()
}

// ─── Drawing ───────────────────────────────────────────

// arrange — шаг анимации разворачивания и bounds детей видимых секций.
//
// Шаг анимации живёт здесь, а не в draw(): позиция ребёнка зависит от anim
// всех секций выше, и шаг, сделанный в draw() уже ПОСЛЕ arrange, рисовал бы
// заголовки на шаг впереди разложенных детей. Шаг — ровно один за кадр
// (ctx.frame_no): arrange зовут ещё и перед событиями, и без этой проверки
// анимация ускорялась бы от движения мыши. Как и раньше, шаг идёт и в кадрах,
// где сам виджет не перерисовывается (partial), — значения сходятся к цели.
pub fn (mut a Accordion) arrange(mut ctx RenderContext) {
	if !a.visible || a.sections.len == 0 {
		return
	}
	if a.anim_frame != ctx.frame_no {
		a.anim_frame = ctx.frame_no
		a.animating = false
		for i in 0 .. a.sections.len {
			target := if a.sections[i].expanded { f32(1.0) } else { f32(0.0) }
			if a.sections[i].anim.update(target, ctx) {
				a.animating = true
			}
		}
	}

	a.scroll_y = clamp_f32(a.scroll_y, 0, a.max_scroll())

	// fit_content: высота содержимого секций - из measure()
	if a.fit_content {
		for i in 0 .. a.sections.len {
			w := a.sections[i].widget
			if unsafe { w != nil } {
				a.sections[i].content_h = measure_widget(w, ctx).h
			}
		}
	}

	// Та же геометрия, что у нарисованных секций в draw(). Ребёнку отдаётся
	// полная child_h (не анимированная), чтобы его раскладка не дёргалась;
	// видимую часть обрезает клип content_r в draw().
	inner := a.bounds.shrunk(a.pad)
	mut y := inner.y - a.scroll_y
	for i in 0 .. a.sections.len {
		sec := a.sections[i]
		child_h := a.child_height_at(i)
		y += a.header_height
		if sec.anim.value > 0.01 && unsafe { sec.widget != nil } {
			mut w := unsafe { sec.widget }
			arrange_child(mut w, Rect{inner.x, y, inner.w, child_h}, mut ctx)
			y += child_h * sec.anim.value
		}
		y += a.spacing
	}
}

// draw рисует заголовки (фон с hover, нижняя линия, треугольник-стрелка,
// название) и содержимое раскрытых секций. Содержимое рисуется под клипом
// content_r, высота которого равна анимированной доле полной высоты ребёнка.
// Секции целиком выше/ниже видимой области пропускаются. bounds детей здесь
// НЕ выставляются - это сделал arrange().
pub fn (mut a Accordion) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(a.enabled)
	if !a.visible || a.sections.len == 0 {
		return
	}
	// Mark animation if any section is mid-transition (the step itself is in
	// arrange()). Goes through mark_anim_rect (not a raw
	// ctx.needs_animation = true write) so the dirty tracker actually
	// schedules a redraw for the NEXT frame — under dirty-region rendering, a
	// frame with an empty dirty region skips the widget tree entirely (see
	// Window.render()'s skip_draw). Placement above the is_in_clip early
	// return is cosmetic: mark_anim_rect re-checks is_in_clip itself.
	area := a.area()
	if a.animating {
		ctx.mark_anim_rect('accordion', area)
	}

	if !ctx.is_in_clip(area) {
		return
	}

	rad := ctx.theme.border_radius
	inner := a.bounds.shrunk(a.pad)

	// Clamp scroll
	ms := a.max_scroll()
	a.scroll_y = clamp_f32(a.scroll_y, 0, ms)

	ctx.push_clip(area)

	font := ctx.get_font(a.font_style, a.font_size)
	fh := ctx.font_height_of(font)
	hdr_bg := a.eff_header_bg(ctx)
	hdr_hover := a.eff_header_hover(ctx)
	hdr_tc := a.eff_header_text(ctx)
	content_bg := a.eff_content_bg(ctx)
	border_c := a.eff_border(ctx)

	mut y := inner.y - a.scroll_y

	for i in 0 .. a.sections.len {
		sec := a.sections[i]
		child_h := a.child_height_at(i)
		expanded_h := child_h * sec.anim.value

		// Total section height
		section_h := a.header_height + expanded_h

		// Skip if entirely above viewport
		if y + section_h < area.y {
			y += section_h + a.spacing
			continue
		}
		// Stop if entirely below viewport
		if y > area.y + area.h {
			break
		}

		// ── Header ──
		hr := Rect{inner.x, y, inner.w, a.header_height}
		bg := if sec.hovered && en { hdr_hover } else { hdr_bg }
		ctx.fill_rounded_rect(hr, bg, if sec.anim.value > 0.01 { f32(0) } else { rad * 0.5 })

		// Border bottom on header (or around whole section)
		ctx.fill_rect(Rect{hr.x, hr.y + hr.h - 1, hr.w, 1}, border_c)

		// Arrow indicator
		arrow_x := hr.x + a.header_pad
		arrow_cy := hr.y + hr.h * 0.5
		as_ := a.icon_size * 0.5
		arrow_c := if en { ctx.theme.eff_acc_arrow() } else { ctx.theme.text_disabled }

		if sec.anim.value > 0.5 {
			// Down arrow (expanded)
			ctx.fill_triangle(arrow_x, arrow_cy - as_ * 0.4, arrow_x + as_ * 2,
				arrow_cy - as_ * 0.4, arrow_x + as_, arrow_cy + as_ * 0.6, arrow_c)
		} else {
			// Right arrow (collapsed)
			ctx.fill_triangle(arrow_x + as_ * 0.2, arrow_cy - as_, arrow_x + as_ * 0.2, arrow_cy +
				as_, arrow_x + as_ * 1.4, arrow_cy, arrow_c)
		}

		// Title text
		mut text_x := arrow_x + a.icon_size + a.header_pad
		text_y := hr.y + (a.header_height - fh) * 0.5
		tc := if en { hdr_tc } else { ctx.theme.text_disabled }
		if sec.icon.is_set() {
			ctx.draw_item_icon(sec.icon, Rect{text_x, hr.y, a.title_icon_size, hr.h},
				a.title_icon_size, tc)
			text_x += a.title_icon_size + a.title_icon_gap
		}
		ctx.draw_text_with_font(sec.title, text_x, text_y, tc, font)

		y += a.header_height

		// ── Content area (animated) ──
		if sec.anim.value > 0.01 && unsafe { sec.widget != nil } {
			content_r := Rect{inner.x, y, inner.w, expanded_h}

			// Background
			ctx.fill_rect(content_r, content_bg)

			// Clip to animated height
			ctx.push_clip(content_r)

			// Bounds (full child_h, not animated) were set in arrange()
			mut w := unsafe { sec.widget }
			ctx.begin_disabled(a.enabled)
			ctx.draw_child(mut w)
			ctx.end_disabled(a.enabled)

			ctx.pop_clip()

			y += expanded_h
		}

		y += a.spacing
	}

	ctx.pop_clip()
}

// ─── Events ────────────────────────────────────────────

// handle_event: hover по заголовкам, клик по заголовку (toggle_section),
// колесо (собственная прокрутка, если wheel). События, не поглощённые самим
// аккордеоном, отдаются детям раскрытых секций (anim > 0.5, т.е. уже
// практически развёрнутых). Порядок: сначала собственная обработка, потом дети.
pub fn (mut a Accordion) handle_event(event &GuiEvent, app &App) bool {
	if !a.visible || !a.enabled || a.sections.len == 0 {
		return false
	}

	match event.typ {
		.mouse_leave {
			// курсор ушёл с виджета (event_route.v) - как движение за его пределы
			for i in 0 .. a.sections.len {
				a.sections[i].hovered = false
			}
		}
		.mouse_move {
			in_bounds := a.area().contains(event.mouse_x, event.mouse_y)
			for i in 0 .. a.sections.len {
				a.sections[i].hovered = false
			}
			if in_bounds {
				idx := a.hit_header(event.mouse_x, event.mouse_y)
				if idx >= 0 {
					a.sections[idx].hovered = true
				}
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && a.area().contains(event.mouse_x, event.mouse_y) {
				idx := a.hit_header(event.mouse_x, event.mouse_y)
				if idx >= 0 {
					a.toggle_section(idx)
					return true
				}
			}
		}
		.mouse_wheel {
			if !a.wheel {
				return false
			}
			ctx_ptr := app.get_active_ctx()
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if a.bounds.contains(mx, my) {
				old := a.scroll_y
				a.scroll_y -= event.wheel_y * a.scroll_speed
				a.scroll_y = clamp_f32(a.scroll_y, 0, a.max_scroll())
				if a.scroll_y != old {
					return true
				}
			}
		}
		else {}
	}

	// Содержимому секций события доставляет окно по маршруту (event_route.v;
	// раскрытые секции - hit_children).
	return false
}
