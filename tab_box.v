module vgui

// ═══════════════════════════════════════════════════════
// TabBox — tab container with configurable header side,
// single-line (with scroll) or multi-row layout
// ═══════════════════════════════════════════════════════

// Файл tab_box.v: виджет TabBox - контейнер со вкладками. Заголовок вкладок (полоса "header")
// может стоять с любой из четырёх сторон (TabPos), быть одной строкой с прокруткой (single_line)
// или переноситься на несколько рядов (multi_row). Показывается и раскладывается только
// содержимое активной вкладки: arrange() даёт bounds одному активному ребёнку, draw() рисует
// его же, события handle_event() отдаются ему же. Неактивные дети хранят устаревшие bounds
// и в hit-test не участвуют (см. HitTestable в widget_tree.v).
// Связи с библиотекой: фокус - FocusKind для TabBox в focus.v (register_tab_box / focus_tab_box,
// вкладки переключаются стрелками), цвета - eff_tab_* у Theme, анимация фокуса - Anim (anim.v),
// иконки вкладок - ItemIcon (item_icon.v). Тег типа kind_tab_box - widget_tag.v.

// TabDir - наследие старого API (было только горизонтальное/вертикальное расположение);
// оставлен для обратной совместимости, см. eff_pos(). В новом коде используйте TabPos.
pub enum TabDir {
	horizontal // legacy alias for pos = .top
	vertical   // legacy alias for pos = .left
}

// Сторона, с которой стоит полоса заголовков вкладок.
pub enum TabPos {
	top
	bottom
	left
	right
}

// Как заголовки размещаются вдоль основной оси: одной строкой (при нехватке места
// появляются кнопки прокрутки) или переносятся на новые ряды/колонки (прокрутки нет).
pub enum TabLayout {
	single_line
	multi_row
}

// Направление текста заголовка. vertical - текст повёрнут на -90 градусов (читается снизу вверх).
pub enum TabTextDir {
	horizontal
	vertical
}

// Сторона вкладки, на которой рисуется полоска-индикатор активной вкладки.
// auto - противоположная содержимому сторона (см. eff_indicator_pos()).
pub enum IndicatorPos {
	auto
	top
	bottom
	left
	right
}

// Одна вкладка: заголовок, иконка (ItemIcon{} - без иконки, см. item_icon.v), содержимое и флаг наведения
// мыши (обновляется в handle_event по mouse_move, используется в draw для подсветки).
struct TabEntry {
mut:
	title   string
	icon    ItemIcon
	widget  &Widget
	hovered bool
}

// Место заголовка вкладки в полосе: номер ряда (колонки для вертикальных), смещение вдоль
// основной оси от начала ряда и размер вдоль основной оси. Без учёта прокрутки.
struct TabPlacement {
	row    int
	offset f32
	size   f32
}

// Размер (по основной оси) каждой из двух кнопок прокрутки "<" и ">" в режиме single_line.
const tab_scroll_btn_sz = f32(22)

// Контейнер со вкладками. Поля bounds/active/tabs задают раскладку и состояние; focus_group -
// номер группы фокуса (Tab ходит внутри группы); поля Sizing/Indicator - внешний вид;
// Scroll - состояние прокрутки single_line (scroll_offset в пикселях вдоль основной оси,
// scroll_*_hov - наведение на кнопки прокрутки). Колбэки: on_change(индекс, заголовок) - после
// смены активной вкладки; on_close(индекс, заголовок) - ПЕРЕД удалением вкладки.
@[heap]
pub struct TabBox {
pub mut:
	type_tag int = kind_tab_box // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel       bool = true
	bounds      Rect
	tabs        []TabEntry
	active      int
	pos         TabPos     = .top
	dir         TabDir     = .horizontal // legacy; used only when pos==.top and dir==.vertical → .left
	layout      TabLayout  = .single_line
	text_dir    TabTextDir = .horizontal
	visible     bool       = true
	enabled     bool       = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focused     bool
	focus_anim  Anim = anim_role(.focus)
	focus_group int
	// Sizing
	// Высота заголовка вкладок: 0 - стандартная высота контрола темы
	// (Theme.control_height), не выше кнопки; tab_pad - поле по бокам
	tab_height f32
	tab_pad    f32 = 12
	gap        f32 = 1
	icon_size  f32 = 20
	icon_gap   f32 = 3
	// Indicator
	indicator_pos       IndicatorPos = .auto
	indicator_color     Color        = Color{0, 0, 0, 0}
	indicator_thickness f32          = 3
	indicator_pad       f32          = 4
	// Scroll (single_line mode)
	scroll_offset   f32
	scroll_speed    f32 = 40
	scroll_prev_hov bool
	scroll_next_hov bool
	// Callbacks
	on_change fn (int, string) = unsafe { nil }
	on_close  fn (int, string) = unsafe { nil } // fired BEFORE a tab is removed; return value ignored
}

// ─── Constructors ──────────────────────────────────────

// Фабрики: вкладки сверху (по умолчанию) / слева / снизу / справа / с произвольной стороны.
pub fn tab_box() &TabBox {
	return &TabBox{}
}

pub fn tab_box_vertical() &TabBox {
	return &TabBox{
		pos: .left
	}
}

pub fn tab_box_bottom() &TabBox {
	return &TabBox{
		pos: .bottom
	}
}

pub fn tab_box_right() &TabBox {
	return &TabBox{
		pos: .right
	}
}

pub fn tab_box_at(pos TabPos) &TabBox {
	return &TabBox{
		pos: pos
	}
}

// ─── Public API ────────────────────────────────────────

// Добавляет вкладку с текстовым заголовком. Активная вкладка не меняется (по умолчанию 0).
// Виджет хранится по указателю: контейнер не владеет им в смысле освобождения.
pub fn (mut tb TabBox) add_tab(title string, widget &Widget) {
	tb.tabs << TabEntry{
		title:  title
		widget: unsafe { widget }
	}
}

// Вкладка с иконкой и текстом (иконка над текстом).
pub fn (mut tb TabBox) add_tab_with_icon(title string, icon_path string, widget &Widget) {
	tb.tabs << TabEntry{
		title:  title
		icon:   item_icon_file(icon_path)
		widget: unsafe { widget }
	}
}

// Вкладка только с иконкой, без текста.
pub fn (mut tb TabBox) add_icon_tab(icon_path string, widget &Widget) {
	tb.tabs << TabEntry{
		icon:   item_icon_file(icon_path)
		widget: unsafe { widget }
	}
}

// Вкладка с иконкой любого вида (Lucide, файл, байты - item_icon.v) над текстом; title
// может быть пустым - тогда вкладка только с иконкой.
pub fn (mut tb TabBox) add_tab_icon(title string, ic ItemIcon, widget &Widget) {
	tb.tabs << TabEntry{
		title:  title
		icon:   ic
		widget: unsafe { widget }
	}
}

// Меняет иконку вкладки idx (ItemIcon{} - убрать); недопустимый индекс игнорируется.
pub fn (mut tb TabBox) set_tab_icon(idx int, ic ItemIcon) {
	if idx >= 0 && idx < tb.tabs.len {
		tb.tabs[idx].icon = ic
	}
}

// Делает активной вкладку idx. Недопустимый индекс игнорируется; on_change не вызывается
// (он вызывается только при смене пользователем и в close_*).
pub fn (mut tb TabBox) set_active(idx int) {
	if idx >= 0 && idx < tb.tabs.len {
		tb.active = idx
	}
}

pub fn (tb &TabBox) get_active() int {
	return tb.active
}

pub fn (tb &TabBox) get_active_title() string {
	if tb.active >= 0 && tb.active < tb.tabs.len {
		return tb.tabs[tb.active].title
	}
	return ''
}

// Вызывает on_change для текущей активной вкладки, если колбэк задан и индекс корректен.
fn (mut tb TabBox) fire_change() {
	if tb.on_change != unsafe { nil } && tb.active >= 0 && tb.active < tb.tabs.len {
		tb.on_change(tb.active, tb.tabs[tb.active].title)
	}
}

// ─── Geometry helpers ──────────────────────────────────

// Реальная сторона заголовка с учётом устаревшего поля dir.
fn (tb &TabBox) eff_pos() TabPos {
	// Back-compat: legacy `.vertical` dir with default `.top` pos → `.left`
	if tb.pos == .top && tb.dir == .vertical {
		return .left
	}
	return tb.pos
}

// std_tab_h - высота заголовка: заданная tab_height или стандартная
fn (tb &TabBox) std_tab_h(ctx &RenderContext) f32 {
	return if tb.tab_height > 0 { tb.tab_height } else { ctx.control_h() }
}

// true, если полоса заголовков горизонтальна (сверху/снизу): основная ось вкладок - X.
fn (tb &TabBox) is_horizontal() bool {
	p := tb.eff_pos()
	return p == .top || p == .bottom
}

fn (tb &TabBox) tab_has_icon(idx int) bool {
	return idx >= 0 && idx < tb.tabs.len && tb.tabs[idx].icon.is_set()
}

fn (tb &TabBox) tab_has_text(idx int) bool {
	return idx >= 0 && idx < tb.tabs.len && tb.tabs[idx].title.len > 0
}

// Высота содержимого заголовка вкладки idx: иконка + зазор + строка текста, либо что-то одно.
// Используется для горизонтальной полосы, где иконка стоит над текстом.
fn (tb &TabBox) tab_content_height(idx int, ctx &RenderContext) f32 {
	has_icon := tb.tab_has_icon(idx)
	has_text := tb.tab_has_text(idx)
	if has_icon && has_text {
		font := ctx.get_font_immut(.regular, 0)
		fh := ctx.font_height_of(font)
		return tb.icon_size + tb.icon_gap + fh
	} else if has_icon {
		return tb.icon_size
	} else if has_text {
		font := ctx.get_font_immut(.regular, 0)
		return ctx.font_height_of(font)
	}
	return f32(0)
}

// Размер текста заголовка вкладки idx обычным шрифтом (без поворота).
fn (tb &TabBox) tab_text_size(idx int, ctx &RenderContext) Vec2 {
	font := ctx.get_font_immut(.regular, 0)
	return ctx.measure_text_with_font(tb.tabs[idx].title, font)
}

// Main-axis size of a tab (width for horizontal pos, height for vertical pos)
// Для горизонтальной полосы с повёрнутым текстом ширина вкладки - высота строки шрифта
// (повёрнутый текст "стоит" вертикально); для вертикальной полосы с повёрнутым текстом
// высота вкладки - ширина текста. Иначе: ширина = max(текст, иконка) + поля, высота -
// по содержимому, но не меньше стандартной.
fn (tb &TabBox) tab_main_size(idx int, ctx &RenderContext) f32 {
	if tb.is_horizontal() {
		if tb.text_dir == .vertical {
			font := ctx.get_font_immut(.regular, 0)
			fh := ctx.font_height_of(font)
			return fh + tb.tab_pad * 2
		}
		font := ctx.get_font_immut(.regular, 0)
		mut w := f32(0)
		if tb.tab_has_text(idx) {
			w = ctx.measure_text_with_font(tb.tabs[idx].title, font).x
		}
		if tb.tab_has_icon(idx) {
			w = max_f32(w, tb.icon_size)
		}
		return w + tb.tab_pad * 2
	}
	if tb.text_dir == .vertical {
		sz := tb.tab_text_size(idx, ctx)
		return sz.x + tb.tab_pad * 2
	}
	ch := tb.tab_content_height(idx, ctx)
	return max_f32(tb.std_tab_h(ctx), ch + measure_pad_y * 2)
}

// Cross-axis size (height for horizontal pos, width for vertical pos)
// Для всей полосы берётся максимум по всем вкладкам, чтобы ряды были одинаковой толщины.
// Минимальная ширина колонки вертикальной полосы - 60 (магическая константа).
fn (tb &TabBox) tab_cross_size(ctx &RenderContext) f32 {
	if tb.is_horizontal() {
		if tb.text_dir == .vertical {
			font := ctx.get_font_immut(.regular, 0)
			mut max_tw := f32(0)
			for i in 0 .. tb.tabs.len {
				tw := ctx.measure_text_with_font(tb.tabs[i].title, font).x
				if tw > max_tw {
					max_tw = tw
				}
			}
			return max_tw + tb.tab_pad * 2
		}
		mut max_ch := f32(0)
		for i in 0 .. tb.tabs.len {
			ch := tb.tab_content_height(i, ctx)
			if ch > max_ch {
				max_ch = ch
			}
		}
		return max_f32(tb.std_tab_h(ctx), max_ch + measure_pad_y * 2)
	}
	// vertical pos: column width
	if tb.text_dir == .vertical {
		font := ctx.get_font_immut(.regular, 0)
		fh := ctx.font_height_of(font)
		return fh + tb.tab_pad * 2
	}
	font := ctx.get_font_immut(.regular, 0)
	mut max_w := f32(60)
	for i in 0 .. tb.tabs.len {
		mut w := f32(0)
		if tb.tab_has_text(i) {
			w = ctx.measure_text_with_font(tb.tabs[i].title, font).x
		}
		if tb.tab_has_icon(i) {
			w = max_f32(w, tb.icon_size)
		}
		cell := w + tb.tab_pad * 2
		if cell > max_w {
			max_w = cell
		}
	}
	return max_w
}

// ─── Layout computation ────────────────────────────────

// Returns placements and number of rows (horizontal) or columns (vertical)
// multi_row: вкладки укладываются в ряд, пока помещаются в доступную длину, иначе
// переносятся на следующий ряд (первая вкладка ряда принимается всегда, даже если она
// длиннее ряда). single_line: один ряд, вкладки подряд без переноса.
fn (tb &TabBox) compute_placements(ctx &RenderContext) ([]TabPlacement, int) {
	mut out := []TabPlacement{cap: tb.tabs.len}
	if tb.tabs.len == 0 {
		return out, 0
	}
	available_main := if tb.is_horizontal() { tb.bounds.w } else { tb.bounds.h }

	if tb.layout == .multi_row {
		mut row := 0
		mut offset := f32(0)
		for i in 0 .. tb.tabs.len {
			sz := tb.tab_main_size(i, ctx)
			if offset > 0 && offset + sz > available_main {
				row++
				offset = 0
			}
			out << TabPlacement{row, offset, sz}
			offset += sz
		}
		return out, row + 1
	}

	// single_line
	mut off := f32(0)
	for i in 0 .. tb.tabs.len {
		sz := tb.tab_main_size(i, ctx)
		out << TabPlacement{0, off, sz}
		off += sz
	}
	return out, 1
}

// Полная длина самого длинного ряда (максимальный конец вкладки вдоль основной оси).
fn (tb &TabBox) total_main(placements []TabPlacement) f32 {
	if placements.len == 0 {
		return 0
	}
	// Determine max end per row, sum... for single_line (1 row) just last.offset+size.
	// For multi_row we don't scroll, so this isn't used for overflow.
	mut max_end := f32(0)
	for p in placements {
		end := p.offset + p.size
		if end > max_end {
			max_end = end
		}
	}
	return max_end
}

// ─── Header/content rects ──────────────────────────────

// Прямоугольник всей полосы заголовков: прижат к выбранной стороне bounds, толщина =
// число рядов * толщина одного ряда.
fn (tb &TabBox) header_rect(ctx &RenderContext) Rect {
	_, rows := tb.compute_placements(ctx)
	cross := tb.tab_cross_size(ctx)
	hdr_size := f32(rows) * cross
	pos := tb.eff_pos()
	match pos {
		.top {
			return Rect{tb.bounds.x, tb.bounds.y, tb.bounds.w, hdr_size}
		}
		.bottom {
			return Rect{tb.bounds.x, tb.bounds.y + tb.bounds.h - hdr_size, tb.bounds.w, hdr_size}
		}
		.left {
			return Rect{tb.bounds.x, tb.bounds.y, hdr_size, tb.bounds.h}
		}
		.right {
			return Rect{tb.bounds.x + tb.bounds.w - hdr_size, tb.bounds.y, hdr_size, tb.bounds.h}
		}
	}
}

// Область содержимого: остаток bounds после полосы заголовков и зазора gap. Для bottom/right
// размер ограничен снизу нулём, чтобы не получить отрицательный Rect при очень малых bounds.
fn (tb &TabBox) content_rect(ctx &RenderContext) Rect {
	hr := tb.header_rect(ctx)
	pos := tb.eff_pos()
	match pos {
		.top {
			y := hr.y + hr.h + tb.gap
			return Rect{tb.bounds.x, y, tb.bounds.w, tb.bounds.h - hr.h - tb.gap}
		}
		.bottom {
			h := hr.y - tb.bounds.y - tb.gap
			return Rect{tb.bounds.x, tb.bounds.y, tb.bounds.w, max_f32(h, 0)}
		}
		.left {
			x := hr.x + hr.w + tb.gap
			return Rect{x, tb.bounds.y, tb.bounds.w - hr.w - tb.gap, tb.bounds.h}
		}
		.right {
			w := hr.x - tb.bounds.x - tb.gap
			return Rect{tb.bounds.x, tb.bounds.y, max_f32(w, 0), tb.bounds.h}
		}
	}
}

// ─── Scroll logic (single_line mode) ───────────────────

// Длина полосы заголовков вдоль основной оси (включая место под кнопки прокрутки).
fn (tb &TabBox) available_main(ctx &RenderContext) f32 {
	hr := tb.header_rect(ctx)
	return if tb.is_horizontal() { hr.w } else { hr.h }
}

fn (tb &TabBox) total_tabs_main(ctx &RenderContext) f32 {
	placements, _ := tb.compute_placements(ctx)
	return tb.total_main(placements)
}

// Прокрутка нужна только в single_line и только если вкладки не помещаются в полосу.
fn (tb &TabBox) needs_scroll(ctx &RenderContext) bool {
	if tb.layout != .single_line {
		return false
	}
	return tb.total_tabs_main(ctx) > tb.available_main(ctx)
}

// Максимальный scroll_offset: суммарная длина вкладок минус видимое окно (полоса без двух кнопок).
fn (tb &TabBox) max_scroll(ctx &RenderContext) f32 {
	avail := tb.available_main(ctx) - tab_scroll_btn_sz * 2
	total := tb.total_tabs_main(ctx)
	return max_f32(0, total - avail)
}

// Удерживает scroll_offset в [0, max_scroll]; зовётся перед отрисовкой и после каждой прокрутки
// (размеры могли измениться - ресайз окна, смена шрифта).
fn (mut tb TabBox) clamp_scroll(ctx &RenderContext) {
	tb.scroll_offset = clamp_f32(tb.scroll_offset, 0, tb.max_scroll(ctx))
}

// Кнопка прокрутки "назад" (левая/верхняя). Пустой Rect, если прокрутка не нужна.
fn (tb &TabBox) scroll_prev_rect(ctx &RenderContext) Rect {
	if !tb.needs_scroll(ctx) {
		return Rect{}
	}
	hr := tb.header_rect(ctx)
	cross := tb.tab_cross_size(ctx)
	if tb.is_horizontal() {
		return Rect{hr.x, hr.y, tab_scroll_btn_sz, cross}
	}
	return Rect{hr.x, hr.y, cross, tab_scroll_btn_sz}
}

// Кнопка прокрутки "вперёд" (правая/нижняя). Пустой Rect, если прокрутка не нужна.
fn (tb &TabBox) scroll_next_rect(ctx &RenderContext) Rect {
	if !tb.needs_scroll(ctx) {
		return Rect{}
	}
	hr := tb.header_rect(ctx)
	cross := tb.tab_cross_size(ctx)
	if tb.is_horizontal() {
		return Rect{hr.x + hr.w - tab_scroll_btn_sz, hr.y, tab_scroll_btn_sz, cross}
	}
	return Rect{hr.x, hr.y + hr.h - tab_scroll_btn_sz, cross, tab_scroll_btn_sz}
}

// Подкручивает полосу так, чтобы активная вкладка целиком попала в видимое окно
// (между кнопками прокрутки). Зовётся при смене активной вкладки кликом или клавишами.
fn (mut tb TabBox) ensure_active_visible(ctx &RenderContext) {
	if tb.layout != .single_line || !tb.needs_scroll(ctx) {
		return
	}
	if tb.active < 0 || tb.active >= tb.tabs.len {
		return
	}
	placements, _ := tb.compute_placements(ctx)
	p := placements[tb.active]
	avail := tb.available_main(ctx) - tab_scroll_btn_sz * 2
	if p.offset < tb.scroll_offset {
		tb.scroll_offset = p.offset
	}
	if p.offset + p.size > tb.scroll_offset + avail {
		tb.scroll_offset = p.offset + p.size - avail
	}
	tb.clamp_scroll(ctx)
}

// ─── Tab rect / hit test ───────────────────────────────

// Экранный прямоугольник заголовка вкладки idx: позиция из compute_placements плюс сдвиг
// под левую кнопку прокрутки (pad_start) минус прокрутка. Может выходить за видимую область -
// вызывающий код обрезает по header_content_rect().
fn (tb &TabBox) tab_rect(idx int, ctx &RenderContext) Rect {
	placements, _ := tb.compute_placements(ctx)
	if idx < 0 || idx >= placements.len {
		return Rect{}
	}
	p := placements[idx]
	hr := tb.header_rect(ctx)
	cross := tb.tab_cross_size(ctx)
	scroll := if tb.layout == .single_line { tb.scroll_offset } else { f32(0) }
	pad_start := if tb.needs_scroll(ctx) { tab_scroll_btn_sz } else { f32(0) }

	if tb.is_horizontal() {
		x := hr.x + pad_start + p.offset - scroll
		y := hr.y + f32(p.row) * cross
		return Rect{x, y, p.size, cross}
	}
	x := hr.x + f32(p.row) * cross
	y := hr.y + pad_start + p.offset - scroll
	return Rect{x, y, cross, p.size}
}

// Visible scroll area within the header (excluding scroll buttons)
// Если прокрутки нет, совпадает со всей полосой.
fn (tb &TabBox) header_content_rect(ctx &RenderContext) Rect {
	hr := tb.header_rect(ctx)
	if !tb.needs_scroll(ctx) {
		return hr
	}
	if tb.is_horizontal() {
		return Rect{hr.x + tab_scroll_btn_sz, hr.y, hr.w - tab_scroll_btn_sz * 2, hr.h}
	}
	return Rect{hr.x, hr.y + tab_scroll_btn_sz, hr.w, hr.h - tab_scroll_btn_sz * 2}
}

// Индекс вкладки под точкой (mx, my) или -1. Кнопки прокрутки вкладками не считаются, а
// вкладка, частично скрытая за краем видимой области, ловит клик только видимой частью.
fn (tb &TabBox) hit_tab(mx f32, my f32, ctx &RenderContext) int {
	if tb.needs_scroll(ctx) {
		if tb.scroll_prev_rect(ctx).contains(mx, my) {
			return -1
		}
		if tb.scroll_next_rect(ctx).contains(mx, my) {
			return -1
		}
	}
	visible := tb.header_content_rect(ctx)
	for i in 0 .. tb.tabs.len {
		r := tb.tab_rect(i, ctx)
		if r.contains(mx, my) && visible.intersects(r) {
			return i
		}
	}
	return -1
}

// ─── Effective indicator position ──────────────────────

// Сторона индикатора: заданная явно или (auto) противоположная содержимому.
fn (tb &TabBox) eff_indicator_pos() IndicatorPos {
	if tb.indicator_pos != .auto {
		return tb.indicator_pos
	}
	return match tb.eff_pos() {
		.top { IndicatorPos.bottom }
		.bottom { IndicatorPos.top }
		.left { IndicatorPos.right }
		.right { IndicatorPos.left }
	}
}

// Цвет индикатора: свой, если задан с ненулевой альфой, иначе из темы.
fn (tb &TabBox) eff_indicator_color(ctx &RenderContext) Color {
	if tb.indicator_color.a > 0 {
		return tb.indicator_color
	}
	return ctx.theme.eff_tab_indicator()
}

// ─── Drawing ───────────────────────────────────────────

// arrange раскладывает только активную вкладку: неактивные не рисуются и
// хранят устаревшие bounds (см. HitTestable в widget_tree.v).
pub fn (mut tb TabBox) arrange(mut ctx RenderContext) {
	if !tb.visible || tb.tabs.len == 0 {
		return
	}
	if tb.active >= 0 && tb.active < tb.tabs.len {
		arrange_child(mut tb.tabs[tb.active].widget, tb.content_rect(ctx), mut ctx)
	}
}

// Рисование. Порядок: регистрация в фокус-менеджере -> синхронизация флага focused -> анимация
// кольца фокуса -> фон полосы -> заголовки (с обрезкой по видимой области) -> разделитель ->
// кнопки прокрутки -> содержимое активной вкладки (в своей обрезке) -> индикатор. Индикатор
// рисуется последним, поверх содержимого, чтобы его не перекрывали границы потомков.
pub fn (mut tb TabBox) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(tb.enabled)
	if !tb.visible || tb.tabs.len == 0 {
		return
	}
	// Нет пересечения с областью перерисовки (dirty region) - рисовать нечего.
	if !ctx.is_in_clip(tb.bounds) {
		return
	}

	// Регистрируемся в фокус-менеджере при каждой отрисовке; выключенный виджет в Tab-обход не попадает.
	if en {
		ctx.focus.register_tab_box(&tb, tb.focus_group)
	} else {
		ctx.focus_block(&tb)
	}

	// Флаг focused в виджете - зеркало решения фокус-менеджера (его меняют Tab/клик).
	should_focus := ctx.focus.is_focused(unsafe { &tb })
	if tb.focused && !should_focus {
		tb.focused = false
	} else if !tb.focused && should_focus {
		tb.focused = true
	}

	target_focus := if tb.focused && en { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if tb.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('tabbox', tb.bounds.expanded(1))
	}

	// Clamp scroll before drawing
	tb.clamp_scroll(ctx)

	rad := ctx.theme.border_radius
	hr := tb.header_rect(ctx)

	// Header strip background
	ctx.fill_rounded_rect(hr, ctx.theme.eff_tab_strip_bg(), rad)

	// Clip tabs to visible header content area
	visible := tb.header_content_rect(ctx)
	ctx.push_clip(visible)

	for i in 0 .. tb.tabs.len {
		trk := tb.tab_rect(i, ctx)
		if !trk.intersects(visible) {
			continue
		}
		is_active := i == tb.active
		is_hovered := tb.tabs[i].hovered && en

		// Фон вкладки: активная > под мышью > прозрачная.
		tab_bg := if is_active {
			ctx.theme.eff_tab_active_bg()
		} else if is_hovered {
			ctx.theme.eff_tab_hover_bg()
		} else {
			color_transparent
		}

		if tab_bg.a > 0 {
			ctx.fill_rounded_rect(trk, tab_bg, rad)
		}

		if tb.focused && is_active {
			ctx.draw_focus_ring(trk, rad, tb.focus_anim.value)
		}

		tc := if !en {
			ctx.theme.eff_tab_disabled_text()
		} else if is_active {
			ctx.theme.eff_tab_active_text()
		} else {
			ctx.theme.eff_tab_inactive_text()
		}

		tb.draw_tab_content(i, trk, tc, mut ctx)
	}

	ctx.pop_clip()

	// Separator between header and content
	sep_c := ctx.theme.eff_tab_border()
	pos := tb.eff_pos()
	match pos {
		.top {
			ctx.fill_rect(Rect{tb.bounds.x, hr.y + hr.h, tb.bounds.w, 1}, sep_c)
		}
		.bottom {
			ctx.fill_rect(Rect{tb.bounds.x, hr.y - 1, tb.bounds.w, 1}, sep_c)
		}
		.left {
			ctx.fill_rect(Rect{hr.x + hr.w, tb.bounds.y, 1, tb.bounds.h}, sep_c)
		}
		.right {
			ctx.fill_rect(Rect{hr.x - 1, tb.bounds.y, 1, tb.bounds.h}, sep_c)
		}
	}

	// Scroll buttons (single-line, overflow)
	if tb.needs_scroll(ctx) {
		tb.draw_scroll_buttons(mut ctx)
	}

	// Content
	if tb.active >= 0 && tb.active < tb.tabs.len {
		cr := tb.content_rect(ctx)
		ctx.push_clip(cr)
		ctx.begin_disabled(tb.enabled)
		ctx.draw_child(mut tb.tabs[tb.active].widget)
		ctx.end_disabled(tb.enabled)
		ctx.pop_clip()
	}

	// Indicator on active tab (clipped to visible area)
	if tb.active >= 0 && tb.active < tb.tabs.len {
		trk := tb.tab_rect(tb.active, ctx)
		if trk.intersects(visible) {
			tb.draw_indicator(trk, visible, mut ctx)
		}
	}
}

// Рисует две кнопки прокрутки со стрелками-треугольниками. На краю (at_start/at_end, допуск 0.5 px)
// стрелка серая и подсветка наведения не показывается. as_ - полуразмер стрелки в px.
fn (tb &TabBox) draw_scroll_buttons(mut ctx RenderContext) {
	at_start := tb.scroll_offset <= 0.5
	at_end := tb.scroll_offset >= tb.max_scroll(ctx) - 0.5

	prev_r := tb.scroll_prev_rect(ctx)
	next_r := tb.scroll_next_rect(ctx)

	prev_bg := if tb.scroll_prev_hov && !at_start {
		ctx.theme.eff_tab_hover_bg()
	} else {
		ctx.theme.eff_tab_strip_bg()
	}
	next_bg := if tb.scroll_next_hov && !at_end {
		ctx.theme.eff_tab_hover_bg()
	} else {
		ctx.theme.eff_tab_strip_bg()
	}

	rad := max_f32(ctx.theme.border_radius - 1, 0)
	ctx.fill_rounded_rect(prev_r, prev_bg, rad)
	ctx.fill_rounded_rect(next_r, next_bg, rad)

	prev_c := if at_start {
		ctx.theme.eff_tab_disabled_text()
	} else {
		ctx.theme.eff_tab_active_text()
	}
	next_c := if at_end {
		ctx.theme.eff_tab_disabled_text()
	} else {
		ctx.theme.eff_tab_active_text()
	}

	as_ := f32(4)

	// Prev arrow
	pcx := prev_r.x + prev_r.w * 0.5
	pcy := prev_r.y + prev_r.h * 0.5
	if tb.is_horizontal() {
		ctx.fill_triangle(pcx - as_ * 0.5, pcy, pcx + as_ * 0.5, pcy - as_, pcx + as_ * 0.5, pcy +
			as_, prev_c)
	} else {
		ctx.fill_triangle(pcx, pcy - as_ * 0.5, pcx - as_, pcy + as_ * 0.5, pcx + as_, pcy +
			as_ * 0.5, prev_c)
	}

	// Next arrow
	ncx := next_r.x + next_r.w * 0.5
	ncy := next_r.y + next_r.h * 0.5
	if tb.is_horizontal() {
		ctx.fill_triangle(ncx + as_ * 0.5, ncy, ncx - as_ * 0.5, ncy - as_, ncx - as_ * 0.5, ncy +
			as_, next_c)
	} else {
		ctx.fill_triangle(ncx, ncy + as_ * 0.5, ncx - as_, ncy - as_ * 0.5, ncx + as_,
			ncy - as_ * 0.5, next_c)
	}

	// Border toward content side of each button
	ctx.fill_rect(Rect{prev_r.x + prev_r.w - 1, prev_r.y, 1, prev_r.h}, ctx.theme.eff_tab_border())
	ctx.fill_rect(Rect{next_r.x, next_r.y, 1, next_r.h}, ctx.theme.eff_tab_border())
}

// Рисует полоску-индикатор активной вкладки trk на выбранной стороне, обрезая по visible.
// Отступ pad по краям уменьшается (max_pad), если вкладка слишком мала для двух отступов
// и самой полоски - иначе ширина полоски ушла бы в отрицательные значения.
fn (tb &TabBox) draw_indicator(trk Rect, visible Rect, mut ctx RenderContext) {
	ic0 := tb.eff_indicator_color(ctx)
	ic := if ctx.is_enabled(tb.enabled) { ic0 } else { ctx.disabled_color(ic0) }
	thick := tb.indicator_thickness
	ipos := tb.eff_indicator_pos()

	max_pad := match ipos {
		.left, .right { max_f32(0, (trk.h - thick * 2) * 0.5 - 1) }
		.top, .bottom { max_f32(0, (trk.w - thick * 2) * 0.5 - 1) }
		.auto { tb.indicator_pad }
	}

	pad := min_f32(tb.indicator_pad, max_pad)

	ctx.push_clip(visible)
	match ipos {
		.bottom {
			ctx.fill_rect(Rect{trk.x + pad, trk.y + trk.h - thick, trk.w - pad * 2, thick}, ic)
		}
		.top {
			ctx.fill_rect(Rect{trk.x + pad, trk.y, trk.w - pad * 2, thick}, ic)
		}
		.left {
			ctx.fill_rect(Rect{trk.x, trk.y + pad, thick, trk.h - pad * 2}, ic)
		}
		.right {
			ctx.fill_rect(Rect{trk.x + trk.w - thick, trk.y + pad, thick, trk.h - pad * 2}, ic)
		}
		.auto {}
	}

	ctx.pop_clip()
}

// Рисует содержимое заголовка (иконку и/или текст) по центру прямоугольника вкладки trk
// цветом tc. Иконка + текст - столбиком (иконка сверху). Повёрнутый текст поддержан только
// для вкладок без иконки.
fn (tb &TabBox) draw_tab_content(idx int, trk Rect, tc Color, mut ctx RenderContext) {
	has_icon := tb.tab_has_icon(idx)
	has_text := tb.tab_has_text(idx)
	if !has_icon && !has_text {
		return
	}
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)

	if tb.text_dir == .vertical && has_text && !has_icon {
		cx := trk.x + trk.w * 0.5
		cy := trk.y + trk.h * 0.5
		ctx.draw_text_rotated_center(tb.tabs[idx].title, cx, cy, -90.0, tc, font)
		return
	}

	if has_icon && has_text {
		total_h := tb.icon_size + tb.icon_gap + fh
		start_y := trk.y + (trk.h - total_h) * 0.5
		ctx.draw_item_icon(tb.tabs[idx].icon, Rect{trk.x, start_y, trk.w, tb.icon_size},
			tb.icon_size, tc)
		tw := ctx.measure_text_with_font(tb.tabs[idx].title, font).x
		text_x := trk.x + (trk.w - tw) * 0.5
		text_y := start_y + tb.icon_size + tb.icon_gap
		ctx.draw_text_with_font(tb.tabs[idx].title, text_x, text_y, tc, font)
	} else if has_icon {
		ctx.draw_item_icon(tb.tabs[idx].icon, trk, tb.icon_size, tc)
	} else {
		tw := ctx.measure_text_with_font(tb.tabs[idx].title, font).x
		tx := trk.x + (trk.w - tw) * 0.5
		ty := trk.y + (trk.h - fh) * 0.5
		ctx.draw_text_with_font(tb.tabs[idx].title, tx, ty, tc, font)
	}
}

// ─── Events ────────────────────────────────────────────

// Сдвигает прокрутку на delta px и ограничивает диапазоном.
fn (mut tb TabBox) scroll_by(delta f32, ctx &RenderContext) {
	tb.scroll_offset += delta
	tb.clamp_scroll(ctx)
}

// Обработка событий. Порядок приоритета: клик по кнопкам прокрутки -> клик по вкладке (фокус +
// смена активной, on_change) -> колесо над полосой (если wheel и есть прокрутка) -> передача
// активному ребёнку -> собственные mouse_move (hover) и клавиши (когда в фокусе): стрелки
// (по основной оси), Home/End, Tab (переход фокуса), Escape (снять фокус). Возвращает true,
// если событие поглощено. Контекст берётся через app.get_active_ctx() и может быть nil - тогда
// геометрию посчитать нельзя и позиционные события пропускаются.
pub fn (mut tb TabBox) handle_event(event &GuiEvent, app &App) bool {
	if !tb.visible || !tb.enabled || tb.tabs.len == 0 {
		return false
	}
	ctx_ptr := app.get_active_ctx()

	// Scroll button clicks
	if event.typ == .mouse_down && event.mouse_btn == .left && unsafe { ctx_ptr != nil } {
		if tb.needs_scroll(ctx_ptr) {
			if tb.scroll_prev_rect(ctx_ptr).contains(event.mouse_x, event.mouse_y) {
				step := tb.available_main(ctx_ptr) * 0.5
				tb.scroll_by(-step, ctx_ptr)
				return true
			}
			if tb.scroll_next_rect(ctx_ptr).contains(event.mouse_x, event.mouse_y) {
				step := tb.available_main(ctx_ptr) * 0.5
				tb.scroll_by(step, ctx_ptr)
				return true
			}
		}
	}

	// Tab click
	if event.typ == .mouse_down && event.mouse_btn == .left && unsafe { ctx_ptr != nil } {
		idx := tb.hit_tab(event.mouse_x, event.mouse_y, ctx_ptr)
		if idx >= 0 {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.focus_tab_box(&tb, tb.focus_group)
			tb.focused = true
			if idx != tb.active {
				tb.active = idx
				tb.ensure_active_visible(ctx_ptr)
				tb.fire_change()
			}
			return true
		}
	}

	// Mouse wheel scroll over header
	// wheel=false: колесо отдаём наружу (например, ScrollBox), даже над полосой.
	if event.typ == .mouse_wheel && !tb.wheel {
		return false
	}
	if event.typ == .mouse_wheel && unsafe { ctx_ptr != nil } {
		mx := ctx_ptr.mouse_x
		my := ctx_ptr.mouse_y
		hr := tb.header_rect(ctx_ptr)
		if hr.contains(mx, my) && tb.needs_scroll(ctx_ptr) {
			delta := -event.wheel_y * tb.scroll_speed
			old := tb.scroll_offset
			tb.scroll_by(delta, ctx_ptr)
			if tb.scroll_offset != old {
				return true
			}
		}
	}

	// Delegate to active child
	if tb.active >= 0 && tb.active < tb.tabs.len {
		if tb.tabs[tb.active].widget.handle_event(event, app) {
			return true
		}
	}

	match event.typ {
		.mouse_move {
			if unsafe { ctx_ptr != nil } {
				for i in 0 .. tb.tabs.len {
					r := tb.tab_rect(i, ctx_ptr)
					vis := tb.header_content_rect(ctx_ptr)
					// Hover вкладки учитывает видимую область: скрытая под краем часть не подсвечивается.
					tb.tabs[i].hovered = r.contains(event.mouse_x, event.mouse_y)
						&& vis.intersects(r)
				}
				if tb.needs_scroll(ctx_ptr) {
					tb.scroll_prev_hov = tb.scroll_prev_rect(ctx_ptr).contains(event.mouse_x,
						event.mouse_y)
					tb.scroll_next_hov = tb.scroll_next_rect(ctx_ptr).contains(event.mouse_x,
						event.mouse_y)
				} else {
					tb.scroll_prev_hov = false
					tb.scroll_next_hov = false
				}
			} else {
				for i in 0 .. tb.tabs.len {
					tb.tabs[i].hovered = false
				}
			}
		}
		.key_down {
			if !tb.focused {
				return false
			}
			// Ось стрелок зависит от ориентации полосы.
			prev_key := if tb.is_horizontal() { sdl_k_left } else { sdl_k_up }
			next_key := if tb.is_horizontal() { sdl_k_right } else { sdl_k_down }

			match event.keycode {
				prev_key {
					if tb.active > 0 {
						tb.active -= 1
						if unsafe { ctx_ptr != nil } {
							tb.ensure_active_visible(ctx_ptr)
						}
						tb.fire_change()
					}
					return true
				}
				next_key {
					if tb.active < tb.tabs.len - 1 {
						tb.active += 1
						if unsafe { ctx_ptr != nil } {
							tb.ensure_active_visible(ctx_ptr)
						}
						tb.fire_change()
					}
					return true
				}
				sdl_k_home {
					tb.active = 0
					if unsafe { ctx_ptr != nil } {
						tb.ensure_active_visible(ctx_ptr)
					}
					tb.fire_change()
					return true
				}
				sdl_k_end {
					tb.active = tb.tabs.len - 1
					if unsafe { ctx_ptr != nil } {
						tb.ensure_active_visible(ctx_ptr)
					}
					tb.fire_change()
					return true
				}
				sdl_k_tab {
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.tab(event.shift())
					}
					return true
				}
				sdl_k_escape {
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.blur_current()
					}
					return true
				}
				else {}
			}
		}
		else {}
	}

	return false
}

// ─── Tab removal API ──────────────────────────────────

// Remove tab at index. Adjusts active index. Fires on_close
// before removal for each tab that is actually closed.
// Индекс активной вкладки: если закрыта вкладка левее активной - сдвигается вместе с ней
// (on_change не вызывается, активная та же); если закрыта активная - активной становится
// следующая на этом месте (или последняя), и on_change срабатывает. Последняя вкладка
// закрыта - active=0, scroll_offset=0. Содержимое закрытой вкладки НЕ уничтожается.
pub fn (mut tb TabBox) close_tab(idx int) {
	if idx < 0 || idx >= tb.tabs.len {
		return
	}
	if tb.on_close != unsafe { nil } {
		tb.on_close(idx, tb.tabs[idx].title)
	}
	tb.tabs.delete(idx)

	if tb.tabs.len == 0 {
		tb.active = 0
		tb.scroll_offset = 0
		return
	}
	if tb.active > idx {
		tb.active--
	} else if tb.active == idx {
		if tb.active >= tb.tabs.len {
			tb.active = tb.tabs.len - 1
		}
		tb.fire_change()
	}
}

// Close all tabs.
// on_close вызывается для каждой вкладки с конца; on_change не вызывается.
pub fn (mut tb TabBox) close_all_tabs() {
	for i := tb.tabs.len - 1; i >= 0; i-- {
		if tb.on_close != unsafe { nil } {
			tb.on_close(i, tb.tabs[i].title)
		}
	}
	tb.tabs.clear()
	tb.active = 0
	tb.scroll_offset = 0
}

// Close every tab except the one at `keep_idx`.
// Остаётся одна вкладка, она становится активной (индекс 0), всегда вызывается on_change.
pub fn (mut tb TabBox) close_other_tabs(keep_idx int) {
	if keep_idx < 0 || keep_idx >= tb.tabs.len {
		return
	}
	for i := tb.tabs.len - 1; i >= 0; i-- {
		if i == keep_idx {
			continue
		}
		if tb.on_close != unsafe { nil } {
			tb.on_close(i, tb.tabs[i].title)
		}
		tb.tabs.delete(i)
	}
	tb.active = 0
	tb.scroll_offset = 0
	tb.fire_change()
}

// Close all tabs with index < idx.
// Активный индекс сдвигается на число закрытых (с ограничением), on_change вызывается всегда.
pub fn (mut tb TabBox) close_tabs_before(idx int) {
	if idx <= 0 {
		return
	}
	cut := if idx > tb.tabs.len { tb.tabs.len } else { idx }
	for i := cut - 1; i >= 0; i-- {
		if tb.on_close != unsafe { nil } {
			tb.on_close(i, tb.tabs[i].title)
		}
		tb.tabs.delete(i)
	}
	if tb.tabs.len == 0 {
		tb.active = 0
	} else {
		tb.active = clamp_int(tb.active - cut, 0, tb.tabs.len - 1)
	}
	tb.scroll_offset = 0
	tb.fire_change()
}

// Close all tabs with index > idx.
// Отрицательный idx - закрыть все. Если активная вкладка была закрыта, активной становится idx.
pub fn (mut tb TabBox) close_tabs_after(idx int) {
	if idx < 0 {
		tb.close_all_tabs()
		return
	}
	if idx >= tb.tabs.len - 1 {
		return
	}
	for i := tb.tabs.len - 1; i > idx; i-- {
		if tb.on_close != unsafe { nil } {
			tb.on_close(i, tb.tabs[i].title)
		}
		tb.tabs.delete(i)
	}
	if tb.active > idx {
		tb.active = idx
		tb.fire_change()
	}
	tb.scroll_offset = 0
}
