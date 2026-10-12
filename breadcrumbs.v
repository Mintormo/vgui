// Файл: ./breadcrumbs.v
module vgui

// ═══════════════════════════════════════════════════════
// Breadcrumbs — navigation path widget
//
// Displays a clickable path of items separated by a
// configurable separator (default: "›"). Each item
// fires on_click(index, text) when clicked. The last
// item is rendered as the "current" location and is
// not clickable by default.
//
// Features:
//   - Clickable path segments with hover effect
//   - Configurable separator (text or icon)
//   - Auto-truncation with ellipsis for overflow
//   - Optional home icon for the first item
//   - Custom colors for normal / hover / current states
//
// Usage (code):
//   mut bc := vgui.breadcrumbs()
//   bc.add('Home')
//   bc.add('Documents')
//   bc.add('Projects')
//   bc.add('vgui')
//   bc.on_click = fn (idx int, text string) {
//       println('Clicked: ${idx} = ${text}')
//   }
//
// Usage (YAML):
//   type: breadcrumbs
//   separator: " / "
//   items:
//     - Home
//     - Documents
//     - Projects
//   on_click: nav_handler
//
// Устройство:
//   - items - исходный путь; segments - то, что реально видно на экране.
//     Segments пересчитываются в layout() при КАЖДОМ draw() (по bounds и
//     тексту). Каждый сегмент помнит свой индекс в items (item; -1 - многоточие),
//     поэтому после сворачивания (overflow) перевод индексов не нужен. Наведение
//     хранится отдельно (hover_seg): флаг внутри сегмента пропадал бы при
//     пересборке, и подсветка не рисовалась вовсе.
//   - Раскладка: размер задаёт контейнер (bounds), виджет сам измеряет текст
//     и сам обрезает/сворачивает путь под ширину. Фокуса и анимаций нет.
//   - Клики по сегментам -> on_click(индекс_в_items, текст). Последний
//     сегмент ("текущий") по умолчанию не кликабелен (current_clickable).
// ═══════════════════════════════════════════════════════

// Константы по умолчанию: разделитель, горизонтальный/вертикальный внутренний
// отступ, поля вокруг сегмента (расширяют зону hover/клика).
const bc_default_separator = ' › '
const bc_pad_h = f32(8)
const bc_pad_v = f32(4)
const bc_sep_pad = f32(2)

// BcSegment - один видимый на экране сегмент пути (или многоточие).
// x/w - абсолютная позиция и ширина текста, считаются в layout().
struct BcSegment {
mut:
	text string
	item int // индекс в items; -1 - многоточие
	// Computed during layout
	x f32
	w f32
	// True if truncated with ellipsis
	truncated bool
}

// Breadcrumbs - хлебные крошки. Цвета с альфой 0 = взять из темы (eff_*);
// bg_color/border_color по умолчанию прозрачные (т.е. фон и рамка не рисуются).
@[heap]
pub struct Breadcrumbs {
pub mut:
	type_tag int = kind_breadcrumbs // тег типа, см. widget_tag.v
	bounds   Rect
	items    []string
	visible  bool = true
	enabled  bool = true
	hovered  bool
	// Appearance
	separator         string    = bc_default_separator
	font_style        FontStyle = .regular
	font_size         int
	pad_h             f32 = bc_pad_h
	pad_v             f32 = bc_pad_v
	radius            f32 = -1 // <0 → use theme.border_radius
	current_clickable bool // if true, the last segment is also clickable
	// Colors (a=0 → use theme defaults)
	bg_color        Color = Color{0, 0, 0, 0}
	border_color    Color = Color{0, 0, 0, 0}
	text_color      Color = Color{0, 0, 0, 0}
	hover_color     Color = Color{0, 0, 0, 0}
	current_color   Color = Color{0, 0, 0, 0}
	separator_color Color = Color{0, 0, 0, 0}
	hover_bg_color  Color = Color{0, 0, 0, 0}
	// Internal layout (пересобирается в layout() каждый кадр)
	segments      []BcSegment
	sep_w         f32  // measured separator width
	overflow      bool // true when items don't fit
	hidden_before int  // сколько элементов скрыто под многоточием
	hover_seg     int = -1 // наведённый кликабельный сегмент (-1 - нет)
	// Callbacks
	on_click fn (int, string) = unsafe { nil }
}

// ─── Constructors ──────────────────────────────────────

// breadcrumbs создаёт пустой виджет (разделитель " › ").
pub fn breadcrumbs() &Breadcrumbs {
	return &Breadcrumbs{}
}

// breadcrumbs_with_items создаёт виджет с копией списка items.
pub fn breadcrumbs_with_items(items []string) &Breadcrumbs {
	return &Breadcrumbs{
		items: items.clone()
	}
}

// ─── Public API ────────────────────────────────────────

// add дописывает элемент в конец пути (то же, что push).
pub fn (mut bc Breadcrumbs) add(item string) {
	bc.items << item
}

// set_items заменяет путь копией items.
pub fn (mut bc Breadcrumbs) set_items(items []string) {
	bc.items = items.clone()
}

// clear удаляет все элементы и сбрасывает состояние раскладки.
pub fn (mut bc Breadcrumbs) clear() {
	bc.items.clear()
	bc.segments.clear()
	bc.hidden_before = 0
	bc.overflow = false
}

// get_items возвращает копию списка элементов.
pub fn (bc &Breadcrumbs) get_items() []string {
	return bc.items.clone()
}

pub fn (bc &Breadcrumbs) count() int {
	return bc.items.len
}

pub fn (mut bc Breadcrumbs) push(item string) {
	bc.items << item
}

// pop удаляет последний элемент (пустой путь - ничего не делает).
pub fn (mut bc Breadcrumbs) pop() {
	if bc.items.len > 0 {
		bc.items.delete(bc.items.len - 1)
	}
}

// set_path_from_string разбирает строку path по разделителю sep, обрезает
// пробелы по краям частей и отбрасывает пустые части. Прежний путь заменяется.
pub fn (mut bc Breadcrumbs) set_path_from_string(path string, sep string) {
	bc.items.clear()
	if path.len == 0 {
		return
	}
	parts := path.split(sep)
	for p in parts {
		t := p.trim_space()
		if t.len > 0 {
			bc.items << t
		}
	}
}

// get_path склеивает элементы через sep.
pub fn (bc &Breadcrumbs) get_path(sep string) string {
	return bc.items.join(sep)
}

// ─── Effective colors ──────────────────────────────────
// eff_*: свой цвет (альфа > 0) или цвет из темы; фон и рамка без своего цвета
// остаются прозрачными, радиус по умолчанию - половина радиуса темы (не меньше 3).

fn (bc &Breadcrumbs) eff_bg(_ &RenderContext) Color {
	if bc.bg_color.a > 0 {
		return bc.bg_color
	}
	return Color{0, 0, 0, 0}
}

fn (bc &Breadcrumbs) eff_border(_ &RenderContext) Color {
	if bc.border_color.a > 0 {
		return bc.border_color
	}
	return Color{0, 0, 0, 0}
}

fn (bc &Breadcrumbs) eff_text(ctx &RenderContext) Color {
	if bc.text_color.a > 0 {
		return bc.text_color
	}
	return ctx.theme.eff_brc_text()
}

fn (bc &Breadcrumbs) eff_hover(ctx &RenderContext) Color {
	if bc.hover_color.a > 0 {
		return bc.hover_color
	}
	return ctx.theme.accent
}

fn (bc &Breadcrumbs) eff_current(ctx &RenderContext) Color {
	if bc.current_color.a > 0 {
		return bc.current_color
	}
	return ctx.theme.eff_brc_active_text()
}

fn (bc &Breadcrumbs) eff_separator(ctx &RenderContext) Color {
	if bc.separator_color.a > 0 {
		return bc.separator_color
	}
	return ctx.theme.eff_brc_separator()
}

fn (bc &Breadcrumbs) eff_hover_bg(ctx &RenderContext) Color {
	if bc.hover_bg_color.a > 0 {
		return bc.hover_bg_color
	}
	return ctx.theme.eff_brc_hover_bg().with_alpha(80)
}

fn (bc &Breadcrumbs) eff_radius(ctx &RenderContext) f32 {
	if bc.radius >= 0 {
		return bc.radius
	}
	return max_f32(ctx.theme.border_radius * 0.5, 3)
}

// ─── Layout ────────────────────────────────────────────

// layout пересчитывает bc.segments под текущие bounds и items.
// Три случая:
//   1. всё помещается - сегменты идут подряд, между ними sep_w;
//   2. не помещается - overflow: справа как можно больше последних элементов, перед
//      ними многоточие "…", а слева - первый элемент (корень пути), если он влезает
//      вместе с последним: «Корень › … › родитель › текущий»;
//   3. не помещается даже многоточие + последний элемент целиком - последний
//      элемент усекается по ширине (bc_truncate_text), segments = [… , усечённый].
// Заполняет также hidden_before - сколько элементов скрыто под многоточием.
fn (mut bc Breadcrumbs) layout(ctx &RenderContext) {
	bc.segments.clear()
	bc.hidden_before = 0
	bc.overflow = false

	if bc.items.len == 0 {
		return
	}

	font := ctx.get_font_immut(bc.font_style, bc.font_size)
	bc.sep_w = ctx.measure_text_with_font(bc.separator, font).x

	avail_w := bc.bounds.w - bc.pad_h * 2
	if avail_w <= 0 {
		return
	}

	mut widths := []f32{cap: bc.items.len}
	mut total := f32(0)
	for i, item in bc.items {
		w := ctx.measure_text_with_font(item, font).x
		widths << w
		total += w
		if i < bc.items.len - 1 {
			total += bc.sep_w
		}
	}

	// Всё помещается.
	if total <= avail_w {
		mut x := bc.bounds.x + bc.pad_h
		for i, item in bc.items {
			bc.segments << BcSegment{
				text: item
				item: i
				x:    x
				w:    widths[i]
			}
			x += widths[i] + bc.sep_w
		}
		return
	}

	bc.overflow = true
	ellipsis := '…'
	ell_w := ctx.measure_text_with_font(ellipsis, font).x
	last_idx := bc.items.len - 1
	ell_part := ell_w + bc.sep_w

	// Последний элемент не влезает даже с одним многоточием - усекаем его.
	if ell_part + widths[last_idx] > avail_w {
		truncated := bc_truncate_text(ctx, bc.items[last_idx], avail_w - ell_part, font)
		bc.segments << BcSegment{
			text: ellipsis
			item: -1
			x:    bc.bounds.x + bc.pad_h
			w:    ell_w
		}
		bc.segments << BcSegment{
			text:      truncated
			item:      last_idx
			x:         bc.bounds.x + bc.pad_h + ell_part
			w:         ctx.measure_text_with_font(truncated, font).x
			truncated: true
		}
		bc.hidden_before = last_idx
		return
	}

	// Корень слева, если влезает вместе с многоточием и последним элементом.
	root_part := widths[0] + bc.sep_w
	show_root := last_idx > 1 && root_part + ell_part + widths[last_idx] <= avail_w
	used_left := if show_root { root_part + ell_part } else { ell_part }
	first_tail_min := if show_root { 1 } else { 0 }

	// Хвост: последний элемент и сколько влезет перед ним.
	mut first_tail := last_idx
	mut tail_w := widths[last_idx]
	for i := last_idx - 1; i > first_tail_min; i-- {
		add_w := widths[i] + bc.sep_w
		if used_left + tail_w + add_w > avail_w {
			break
		}
		tail_w += add_w
		first_tail = i
	}

	mut x := bc.bounds.x + bc.pad_h
	if show_root {
		bc.segments << BcSegment{
			text: bc.items[0]
			item: 0
			x:    x
			w:    widths[0]
		}
		x += root_part
	}
	bc.segments << BcSegment{
		text: ellipsis
		item: -1
		x:    x
		w:    ell_w
	}
	x += ell_part
	for i in first_tail .. bc.items.len {
		bc.segments << BcSegment{
			text: bc.items[i]
			item: i
			x:    x
			w:    widths[i]
		}
		x += widths[i] + bc.sep_w
	}
	bc.hidden_before = first_tail - (if show_root { 1 } else { 0 })
}

// Truncate text to fit max_w with ellipsis
// Бинарный поиск по числу рун (а не байт, чтобы не рвать UTF-8): наибольший
// префикс, который вместе с "…" влезает в max_w. Пустая строка при max_w <= 0.
fn bc_truncate_text(ctx &RenderContext, text string, max_w f32, font voidptr) string {
	if max_w <= 0 {
		return ''
	}
	tw := ctx.measure_text_with_font(text, font).x
	if tw <= max_w {
		return text
	}
	ellipsis := '…'
	ew := ctx.measure_text_with_font(ellipsis, font).x
	if ew >= max_w {
		return ellipsis
	}
	target := max_w - ew
	runes := text.runes()
	mut lo := 0
	mut hi := runes.len
	for lo < hi {
		mid := (lo + hi + 1) / 2
		sub := runes[..mid].string()
		sw := ctx.measure_text_with_font(sub, font).x
		if sw <= target {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	if lo == 0 {
		return ellipsis
	}
	return runes[..lo].string() + ellipsis
}

// segment_to_item_index - индекс в items видимого сегмента; -1 - многоточие или
// неверный индекс.
fn (bc &Breadcrumbs) segment_to_item_index(seg_idx int) int {
	if seg_idx < 0 || seg_idx >= bc.segments.len {
		return -1
	}
	return bc.segments[seg_idx].item
}

// ─── Drawing ───────────────────────────────────────────

// draw пересчитывает раскладку (layout) и рисует сегменты: подложка-"пилюля"
// под наведённым кликабельным сегментом, текст (цвет по приоритету: disabled >
// многоточие > hover > текущий > обычный) и разделитель после каждого сегмента,
// кроме последнего. Всё под клипом bounds.
pub fn (mut bc Breadcrumbs) draw(mut ctx RenderContext) {
	if !bc.visible || bc.items.len == 0 {
		return
	}
	if !ctx.is_in_clip(bc.bounds) {
		return
	}

	// Layout each frame (cheap — only on bounds/items change matters but
	// keeps it simple and correct on resize)
	bc.layout(ctx)

	rad := bc.eff_radius(ctx)

	// Background
	bg := bc.eff_bg(ctx)
	if bg.a > 0 {
		ctx.fill_rounded_rect(bc.bounds, bg, rad)
	}

	// Border
	border := bc.eff_border(ctx)
	if border.a > 0 {
		ctx.draw_rounded_rect(bc.bounds, border, rad)
	}

	if bc.segments.len == 0 {
		return
	}

	font := ctx.get_font(bc.font_style, bc.font_size)
	fh := ctx.font_height_of(font)

	tc_normal := bc.eff_text(ctx)
	tc_hover := bc.eff_hover(ctx)
	tc_current := bc.eff_current(ctx)
	tc_sep := bc.eff_separator(ctx)
	bg_hover := bc.eff_hover_bg(ctx)

	cy := bc.bounds.y + bc.bounds.h * 0.5
	ty := cy - fh * 0.5

	ctx.push_clip(bc.bounds)

	last_seg := bc.segments.len - 1

	for i in 0 .. bc.segments.len {
		seg := bc.segments[i]
		item_idx := bc.segment_to_item_index(i)
		is_last := i == last_seg
		is_current := is_last && item_idx == bc.items.len - 1
		is_ellipsis := item_idx < 0
		is_clickable := bc.is_item_clickable(item_idx)
		is_hovered := i == bc.hover_seg

		// Hover background pill
		if is_hovered && is_clickable && bc.enabled {
			pill_r := Rect{
				x: seg.x - bc_sep_pad
				y: cy - fh * 0.5 - bc.pad_v * 0.5
				w: seg.w + bc_sep_pad * 2
				h: fh + bc.pad_v
			}
			ctx.fill_rounded_rect(pill_r, bg_hover, max_f32(rad - 1, 2))
		}

		// Text color
		mut tc := tc_normal
		if !bc.enabled {
			tc = ctx.theme.text_disabled
		} else if is_ellipsis {
			tc = tc_sep
		} else if is_hovered && is_clickable {
			tc = tc_hover
		} else if is_current {
			tc = tc_current
		}

		ctx.draw_text_with_font(seg.text, seg.x, ty, tc, font)

		// Separator after this segment (but not after last)
		if i < last_seg {
			sep_x := seg.x + seg.w
			ctx.draw_text_with_font(bc.separator, sep_x, ty, tc_sep, font)
		}
	}

	ctx.pop_clip()
}

// is_item_clickable - можно ли кликнуть сегмент элемента item_idx: нельзя при
// disabled, для многоточия (-1) и для последнего элемента, если не включён
// current_clickable.
fn (bc &Breadcrumbs) is_item_clickable(item_idx int) bool {
	if !bc.enabled {
		return false
	}
	// Многоточие (item_idx -1) не кликабельно.
	if item_idx < 0 || item_idx >= bc.items.len {
		return false
	}
	// Last item (current) is clickable only if explicitly enabled
	if item_idx == bc.items.len - 1 && !bc.current_clickable {
		return false
	}
	return true
}

// ─── Hit testing ──────────────────────────────────────

// hit_segment - индекс сегмента под точкой или -1. По Y достаточно попасть в
// bounds; по X зона шире текста на bc_sep_pad с каждой стороны.
fn (bc &Breadcrumbs) hit_segment(mx f32, my f32) int {
	if my < bc.bounds.y || my > bc.bounds.y + bc.bounds.h {
		return -1
	}
	for i, seg in bc.segments {
		// Hit area extends slightly beyond text for easier clicking
		hx := seg.x - bc_sep_pad
		hw := seg.w + bc_sep_pad * 2
		if mx >= hx && mx < hx + hw {
			return i
		}
	}
	return -1
}

// ─── Events ────────────────────────────────────────────

// handle_event: mouse_move обновляет hovered сегментов и курсор (рука над
// кликабельным сегментом, стрелка иначе); левый mouse_down по кликабельному
// сегменту вызывает on_click(индекс в items, текст) и поглощает событие.
pub fn (mut bc Breadcrumbs) handle_event(event &GuiEvent, app &App) bool {
	if !bc.visible || !bc.enabled || bc.items.len == 0 {
		return false
	}

	match event.typ {
		.mouse_move {
			bc.hovered = bc.bounds.contains(event.mouse_x, event.mouse_y)
			bc.hover_seg = -1
			if bc.hovered {
				idx := bc.hit_segment(event.mouse_x, event.mouse_y)
				if idx >= 0 && bc.is_item_clickable(bc.segment_to_item_index(idx)) {
					bc.hover_seg = idx
				}
				// Кэширующий set_cursor: SDL_CreateSystemCursor на каждое движение
				// мыши создавал курсор заново и не освобождал его.
				set_cursor(if bc.hover_seg >= 0 {
					sdl_system_cursor_hand
				} else {
					sdl_system_cursor_arrow
				})
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && bc.bounds.contains(event.mouse_x, event.mouse_y) {
				idx := bc.hit_segment(event.mouse_x, event.mouse_y)
				if idx >= 0 {
					item_idx := bc.segment_to_item_index(idx)
					if bc.is_item_clickable(item_idx) {
						if bc.on_click != unsafe { nil } {
							bc.on_click(item_idx, bc.items[item_idx])
						}
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
