module vgui

// ═══════════════════════════════════════════════════════
// Реализации Measurable для встроенных виджетов
//
// Собраны в одном файле намеренно: измерение — это единая
// политика («сколько места просит контрол»), и держать её
// рядом удобнее, чем размазывать по сорока файлам виджетов.
// Отрисовка при этом остаётся там, где была.
//
// Соглашение: measure() ничего не меняет в виджете и
// не трогает renderer — только шрифтовые метрики. Поэтому
// его можно звать сколько угодно раз за кадр и до первой
// отрисовки.
// ═══════════════════════════════════════════════════════

// ─── Текст и метки ─────────────────────────────────────

// label_wrap_pref_w - желаемая ширина метки с переносом (~55 знаков)
const label_wrap_pref_w = f32(400)

pub fn (l &Label) measure(ctx &RenderContext) SizeHint {
	if !l.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(l.font_style, l.font_size)
	mut sz := measure_text_lines(ctx, l.text, font, l.line_gap)
	if l.wrap {
		// Высота по ширине: перенос в ширину, которую метка получила в
		// прошлом проходе (сменилась - Window.arrange пройдёт ещё раз), до
		// первой раскладки - в желаемую ширину
		ww := if l.bounds.w > l.pad * 2 {
			l.bounds.w - l.pad * 2
		} else {
			min_f32(sz.x, label_wrap_pref_w)
		}
		lines := l.wrap_lines(ctx, font, ww)
		sz.y = f32(lines.len) * (ctx.font_height_of(font) + l.line_gap) - l.line_gap
	}
	// При wrap ширина — пожелание, а не требование: текст
	// переносится, поэтому min_w отпускаем в 0, а желаемая - удобная
	// для чтения строка (не шире label_wrap_pref_w): окно «по
	// содержимому» не вытягивается в одну длинную строку
	min_w := if l.wrap { f32(0) } else { sz.x + l.pad * 2 }
	pref_w := if l.wrap { min_f32(sz.x, label_wrap_pref_w) } else { sz.x }
	return SizeHint{
		w:        pref_w + l.pad * 2
		h:        sz.y + l.pad * 2
		min_w:    min_w
		min_h:    sz.y + l.pad * 2
		v_policy: .fixed
	}
}

// ─── Кнопки ────────────────────────────────────────────

// button_content_size — общий расчёт для Button и MenuButton:
// иконка + зазор + текст.
fn button_content_size(ctx &RenderContext, text string, font_style FontStyle, font_size int, has_icon bool, icon_size f32, icon_gap f32) (f32, f32) {
	font := ctx.get_font_immut(font_style, font_size)
	sz := ctx.measure_text_with_font(text, font)
	mut w := sz.x
	mut h := max_f32(sz.y, ctx.font_height_of(font))
	if has_icon {
		w += icon_size
		h = max_f32(h, icon_size)
		if text.len > 0 {
			w += icon_gap
		}
	}
	return w, h
}

pub fn (b &Button) measure(ctx &RenderContext) SizeHint {
	if !b.visible {
		return SizeHint{}
	}
	has_icon := b.icon_name != '' || b.icon_path != ''
	mut cw, ch := button_content_size(ctx, b.text, b.font_style, b.font_size, has_icon,
		b.icon_size, b.icon_gap)
	if b.icon_text != '' && b.text.len > 0 {
		// Старый текстовый префикс-иконка рисуется как часть строки.
		icon_font := ctx.get_font_immut(b.font_style, b.font_size)
		cw += ctx.measure_text_with_font(b.icon_text + ' ', icon_font).x
	}
	if has_icon && b.text.len == 0 && b.icon_text == '' {
		// Кнопка-значок - квадрат вокруг значка, без полей под текст
		side := b.icon_size + measure_pad_y * 2
		return SizeHint{
			w:        side
			h:        side
			min_w:    side
			min_h:    side
			h_policy: .fixed
			v_policy: .fixed
		}
	}
	h := max_f32(ctx.control_h(), ch + measure_pad_y * 2)
	return SizeHint{
		w:        cw + measure_pad_x * 2
		h:        h
		min_w:    cw + measure_pad_y * 2
		min_h:    h
		v_policy: .fixed
	}
}

pub fn (mb &MenuButton) measure(ctx &RenderContext) SizeHint {
	if !mb.visible {
		return SizeHint{}
	}
	text := if mb.text != '' { mb.text } else { mb.placeholder }
	cw, ch := button_content_size(ctx, text, mb.font_style, mb.font_size, mb.icon_path != '',
		mb.icon_size, mb.icon_gap)
	// Плюс зона стрелки справа.
	arrow_w := f32(22)
	h := max_f32(ctx.control_h(), ch + measure_pad_y * 2)
	return SizeHint{
		w:        cw + measure_pad_x * 2 + arrow_w
		h:        h
		min_w:    cw + arrow_w
		min_h:    h
		v_policy: .fixed
	}
}

// ─── Переключатели ─────────────────────────────────────

// labeled_control_size — «индикатор + зазор + подпись»,
// общая форма чекбокса, радиокнопки и тумблера.
fn labeled_control_size(ctx &RenderContext, text string, ind_w f32, ind_h f32, gap f32) SizeHint {
	font := ctx.get_font_immut(.regular, 0)
	sz := ctx.measure_text_with_font(text, font)
	mut w := ind_w
	if text.len > 0 {
		w += gap + sz.x
	}
	// Высота строки - стандартная высота контрола (как у кнопки и поля
	// ввода): флажки в столбце не слипаются и ровно стоят рядом с ними
	h := max_f32(ctx.control_h(), max_f32(ind_h, sz.y))
	return SizeHint{
		w:        w
		h:        h
		min_w:    w
		min_h:    h
		h_policy: .fixed
		v_policy: .fixed
	}
}

pub fn (cb &CheckBox) measure(ctx &RenderContext) SizeHint {
	if !cb.visible {
		return SizeHint{}
	}
	return labeled_control_size(ctx, cb.text, cb.box_size, cb.box_size, cb.gap)
}

pub fn (rb &RadioButton) measure(ctx &RenderContext) SizeHint {
	if !rb.visible {
		return SizeHint{}
	}
	return labeled_control_size(ctx, rb.text, rb.circle_size, rb.circle_size, rb.gap)
}

pub fn (ts &ToggleSwitch) measure(ctx &RenderContext) SizeHint {
	if !ts.visible {
		return SizeHint{}
	}
	return labeled_control_size(ctx, ts.text, ts.track_w, ts.track_h, ts.gap)
}

// ─── Поля ввода ────────────────────────────────────────

pub fn (ti &TextInput) measure(ctx &RenderContext) SizeHint {
	if !ti.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(.regular, 0)
	h := max_f32(ctx.control_h(), ctx.font_height_of(font) + ti.pad * 2)
	if ti.chars > 0 {
		// Ширина под chars символов (по «0» - цифра средней ширины)
		w := ctx.measure_text_with_font('0'.repeat(ti.chars), font).x + ti.pad * 2
		return SizeHint{
			w:        w
			h:        h
			min_w:    w
			min_h:    h
			h_policy: .preferred
			v_policy: .fixed
		}
	}
	// Ширина поля ввода не выводится из содержимого: поле
	// заполняет отведённое место, а под текст скроллится.
	return SizeHint{
		w:        180
		h:        h
		min_w:    60
		min_h:    h
		h_policy: .expanding
		v_policy: .fixed
	}
}

pub fn (sb &Spinbox) measure(ctx &RenderContext) SizeHint {
	if !sb.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(.regular, 0)
	// Ширина под самое длинное значение диапазона + префикс,
	// суффикс и две кнопки-стрелки.
	longest := sb.prefix + sb.max.str() + sb.suffix
	tw := ctx.measure_text_with_font(longest, font).x
	buttons_w := f32(44)
	h := max_f32(ctx.control_h(), ctx.font_height_of(font) + measure_pad_y * 2)
	w := tw + buttons_w + measure_pad_x
	return SizeHint{
		w:        w
		h:        h
		min_w:    w
		min_h:    h
		v_policy: .fixed
	}
}

pub fn (cb &ComboBox) measure(ctx &RenderContext) SizeHint {
	if !cb.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(.regular, 0)
	mut widest := ctx.measure_text_with_font(cb.placeholder, font).x
	for item in cb.items {
		widest = max_f32(widest, ctx.measure_text_with_font(item, font).x)
	}
	arrow_w := f32(24)
	h := max_f32(ctx.control_h(), max_f32(cb.item_height, ctx.font_height_of(font) +
		cb.pad * 2))
	return SizeHint{
		w:        widest + cb.pad * 2 + arrow_w
		h:        h
		min_w:    80
		min_h:    h
		v_policy: .fixed
	}
}

// ─── Мелкие декоративные виджеты ───────────────────────

pub fn (ce &CurveEditor) measure(ctx &RenderContext) SizeHint {
	if !ce.visible {
		return SizeHint{}
	}
	return SizeHint{
		w:        200
		h:        200
		min_w:    80
		min_h:    80
		h_policy: .expanding
		v_policy: .expanding
	}
}

pub fn (ic &Icon) measure(ctx &RenderContext) SizeHint {
	if !ic.visible {
		return SizeHint{}
	}
	s := f32(ic.size)
	return SizeHint{
		w:        s
		h:        s
		min_w:    s
		min_h:    s
		max_w:    s
		max_h:    s
		h_policy: .fixed
		v_policy: .fixed
	}
}

pub fn (b &Badge) measure(ctx &RenderContext) SizeHint {
	if !b.visible {
		return SizeHint{}
	}
	w, h := b.preferred_size(ctx)
	return SizeHint{
		w:        w
		h:        h
		min_w:    w
		min_h:    h
		max_w:    w
		max_h:    h
		h_policy: .fixed
		v_policy: .fixed
	}
}

pub fn (s &Separator) measure(ctx &RenderContext) SizeHint {
	if !s.visible {
		return SizeHint{}
	}
	t := max_f32(1, s.thickness)
	return match s.dir {
		.horizontal {
			SizeHint{
				w:        t
				h:        t
				min_h:    t
				max_h:    t
				h_policy: .expanding
				v_policy: .fixed
			}
		}
		.vertical {
			SizeHint{
				w:        t
				h:        t
				min_w:    t
				max_w:    t
				h_policy: .fixed
				v_policy: .expanding
			}
		}
		// .auto — направление решает контейнер, поэтому
		// толщина заявлена как минимум по обеим осям.
		else {
			SizeHint{
				w:     t
				h:     t
				min_w: t
				min_h: t
			}
		}
	}
}

pub fn (sp &Spinner) measure(ctx &RenderContext) SizeHint {
	if !sp.visible {
		return SizeHint{}
	}
	d := if sp.size > 0 { sp.size } else { f32(24) }
	mut w := d
	mut h := d
	if sp.text != '' {
		font := ctx.get_font_immut(.regular, 0)
		sz := ctx.measure_text_with_font(sp.text, font)
		w += sp.text_gap + sz.x
		h = max_f32(h, sz.y)
	}
	return SizeHint{
		w:        w
		h:        h
		min_w:    w
		min_h:    h
		h_policy: .fixed
		v_policy: .fixed
	}
}

pub fn (pb &ProgressBar) measure(ctx &RenderContext) SizeHint {
	if !pb.visible {
		return SizeHint{}
	}
	if pb.style == .circular {
		d := if pb.radius > 0 { pb.radius * 2 } else { f32(48) }
		return SizeHint{
			w:        d
			h:        d
			min_w:    d
			min_h:    d
			h_policy: .fixed
			v_policy: .fixed
		}
	}
	// С текстом - полоса выше строки (text_bar_h)
	h := max_f32(pb.text_bar_h(ctx), 4)
	return SizeHint{
		w:        160
		h:        h
		min_w:    40
		min_h:    h
		max_h:    h
		h_policy: .expanding
		v_policy: .fixed
	}
}

pub fn (s &Slider) measure(ctx &RenderContext) SizeHint {
	if !s.visible {
		return SizeHint{}
	}
	thick := max_f32(s.thumb_size, s.track_thickness) + 4
	if s.dir == .vertical {
		return SizeHint{
			w:        thick
			h:        120
			min_w:    thick
			max_w:    thick
			min_h:    40
			h_policy: .fixed
			v_policy: .expanding
		}
	}
	return SizeHint{
		w:        160
		h:        thick
		min_w:    40
		min_h:    thick
		max_h:    thick
		h_policy: .expanding
		v_policy: .fixed
	}
}

pub fn (bc &Breadcrumbs) measure(ctx &RenderContext) SizeHint {
	if !bc.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(bc.font_style, bc.font_size)
	sep_w := ctx.measure_text_with_font(bc.separator, font).x
	mut w := f32(0)
	for i, item in bc.items {
		w += ctx.measure_text_with_font(item, font).x + bc.pad_h * 2
		if i < bc.items.len - 1 {
			w += sep_w + bc.pad_h
		}
	}
	h := ctx.font_height_of(font) + bc.pad_v * 2
	return SizeHint{
		w:        w
		h:        h
		min_w:    min_f32(w, 60)
		min_h:    h
		max_h:    h
		h_policy: .preferred
		v_policy: .fixed
	}
}

// ─── Крупные виджеты с прокруткой ──────────────────────
//
// Их размер содержимым не определяется: они заполняют то,
// что дал контейнер, и прокручивают внутри. Поэтому hint —
// это разумный минимум плюс политика expanding.

fn scrollable_hint(min_w f32, min_h f32, pref_w f32, pref_h f32) SizeHint {
	return SizeHint{
		w:        pref_w
		h:        pref_h
		min_w:    min_w
		min_h:    min_h
		h_policy: .expanding
		v_policy: .expanding
	}
}

pub fn (ta &TextArea) measure(ctx &RenderContext) SizeHint {
	font := ctx.get_font_immut(.mono, 0)
	line_h := ctx.font_height_of(font)
	return scrollable_hint(120, line_h * 3 + ta.pad * 2, 240, line_h * 6 + ta.pad * 2)
}

pub fn (ce &CodeEditor) measure(ctx &RenderContext) SizeHint {
	line_h := ctx.mono_font_height()
	return scrollable_hint(200, line_h * 4, 480, line_h * 12)
}

pub fn (lb &ListBox) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(120, 60, 240, 180)
}

pub fn (tv &TreeView) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(140, 80, 260, 220)
}

pub fn (t &TableView) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(180, 80, 400, 240)
}

pub fn (mv &MarkdownView) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(200, 100, 480, 320)
}

pub fn (pv &PlotView) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(160, 120, 360, 240)
}

pub fn (pg &PropertyGrid) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(180, 80, 320, 240)
}

pub fn (iv &ImageView) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(80, 60, 320, 240)
}

// Холст с растяжкой (индикатор: гистограмма, градиент) - желаемый
// размер его буфера, растягивается по ширине; изображение с зумом -
// растягивается во всё место
pub fn (c &Canvas) measure(ctx &RenderContext) SizeHint {
	if c.stretch && c.width > 0 && c.height > 0 {
		return SizeHint{
			w:        f32(c.width)
			h:        f32(c.height)
			min_w:    32
			min_h:    16
			h_policy: .expanding
		}
	}
	return scrollable_hint(64, 64, 320, 240)
}

// TabBox: заголовок вкладок плюс самое большое содержимое (вкладки
// переключаются - место нужно под любую), политики - от содержимого
pub fn (tb &TabBox) measure(ctx &RenderContext) SizeHint {
	mut c := SizeHint{}
	for t in tb.tabs {
		if unsafe { t.widget == nil } {
			continue
		}
		m := measure_widget(t.widget, ctx)
		c.w = max_f32(c.w, m.w)
		c.h = max_f32(c.h, m.h)
		c.min_w = max_f32(c.min_w, m.min_w)
		c.min_h = max_f32(c.min_h, m.min_h)
		if m.h_policy == .expanding {
			c.h_policy = .expanding
		}
		if m.v_policy == .expanding {
			c.v_policy = .expanding
		}
	}
	hdr := tb.tab_cross_size(ctx) + tb.gap
	if tb.is_horizontal() {
		c.h += hdr
		c.min_h += hdr
	} else {
		c.w += hdr
		c.min_w += hdr
	}
	return c
}

pub fn (a &Accordion) measure(ctx &RenderContext) SizeHint {
	if a.fit_content {
		// Полная высота контента: прокрутку даёт внешний ScrollBox
		h := a.fit_height(ctx)
		return SizeHint{
			w:        160
			h:        h
			min_w:    80
			min_h:    h
			h_policy: .expanding
		}
	}
	return scrollable_hint(160, 80, 320, 240)
}

// ─── Контейнеры ────────────────────────────────────────

pub fn (h &HBox) measure(ctx &RenderContext) SizeHint {
	return h.box.content_size(ctx)
}

pub fn (v &VBox) measure(ctx &RenderContext) SizeHint {
	return v.box.content_size(ctx)
}

pub fn (d &WindowTitleDrag) measure(ctx &RenderContext) SizeHint {
	return d.box.content_size(ctx)
}

pub fn (s &Spacer) measure(ctx &RenderContext) SizeHint {
	return SizeHint{
		h_policy: .expanding
		v_policy: .expanding
	}
}

pub fn (p &Panel) measure(ctx &RenderContext) SizeHint {
	if p.child == unsafe { nil } {
		return SizeHint{
			w: p.pad * 2
			h: p.pad * 2
		}
	}
	c := measure_widget(p.child, ctx)
	// Панель - контейнер: растягивается, даже если внутри метка
	// фиксированной высоты (fixed ребёнка - не её)
	return SizeHint{
		w:        c.w + p.pad * 2
		h:        c.h + p.pad * 2
		min_w:    c.min_w + p.pad * 2
		min_h:    c.min_h + p.pad * 2
		h_policy: if c.h_policy == .expanding { SizePolicy.expanding } else { SizePolicy.preferred }
		v_policy: if c.v_policy == .expanding { SizePolicy.expanding } else { SizePolicy.preferred }
	}
}

pub fn (c &Centered) measure(ctx &RenderContext) SizeHint {
	// Centered задаёт ребёнку фиксированный размер, поэтому
	// его собственный hint — этот размер и есть.
	return SizeHint{
		w:        c.child_w
		h:        c.child_h
		min_w:    c.child_w
		min_h:    c.child_h
		h_policy: .expanding
		v_policy: .expanding
	}
}

pub fn (s &Stack) measure(ctx &RenderContext) SizeHint {
	mut r := SizeHint{
		h_policy: .preferred
		v_policy: .preferred
	}
	for child in s.children {
		c := measure_widget(child, ctx)
		r.w = max_f32(r.w, c.w)
		r.h = max_f32(r.h, c.h)
		r.min_w = max_f32(r.min_w, c.min_w)
		r.min_h = max_f32(r.min_h, c.min_h)
		if c.h_policy == .expanding {
			r.h_policy = .expanding
		}
		if c.v_policy == .expanding {
			r.v_policy = .expanding
		}
	}
	return r
}

pub fn (s &ScrollBox) measure(ctx &RenderContext) SizeHint {
	// Прокрутка по своей оси — expanding; поперёк —
	// размер содержимого, чтобы не появлялась вторая полоса.
	mut cross_pref := f32(0)
	mut cross_min := f32(0)
	for child in s.children {
		c := measure_widget(child, ctx)
		if s.dir == .vertical {
			cross_pref = max_f32(cross_pref, c.w)
			cross_min = max_f32(cross_min, c.min_w)
		} else {
			cross_pref = max_f32(cross_pref, c.h)
			cross_min = max_f32(cross_min, c.min_h)
		}
	}
	sb := f32(16) // место под полосу прокрутки
	if s.dir == .vertical {
		return SizeHint{
			w:        cross_pref + s.pad * 2 + sb
			h:        160
			min_w:    cross_min + s.pad * 2
			min_h:    40
			v_policy: .expanding
		}
	}
	return SizeHint{
		w:        160
		h:        cross_pref + s.pad * 2 + sb
		min_w:    40
		min_h:    cross_min + s.pad * 2
		h_policy: .expanding
	}
}

pub fn (g &GridLayout) measure(ctx &RenderContext) SizeHint {
	if g.cells.len == 0 {
		return SizeHint{
			w: g.pad * 2
			h: g.pad * 2
		}
	}
	mut col_w := []f32{len: g.cols}
	mut row_h := []f32{len: g.rows}
	for cell in g.cells {
		if cell.row < 0 || cell.row >= g.rows || cell.col < 0 || cell.col >= g.cols {
			continue
		}
		c := measure_widget(cell.widget, ctx)
		// Ячейку со span учитываем только в первой колонке/строке
		// пропорционально — грубо, но без ложных «широких» колонок.
		w_share := c.w / f32(max_f32(1, cell.col_span))
		h_share := c.h / f32(max_f32(1, cell.row_span))
		col_w[cell.col] = max_f32(col_w[cell.col], w_share)
		row_h[cell.row] = max_f32(row_h[cell.row], h_share)
	}
	mut w := g.pad * 2 + f32(g.cols - 1) * g.spacing_x
	mut h := g.pad * 2 + f32(g.rows - 1) * g.spacing_y
	for v in col_w {
		w += v
	}
	for v in row_h {
		h += v
	}
	// Есть дорожки с весом - сетка растягивается по этой оси
	mut hp := SizePolicy.preferred
	mut vp := SizePolicy.preferred
	for wt in g.col_weights {
		if wt > 0 {
			hp = .expanding
		}
	}
	for wt in g.row_weights {
		if wt > 0 {
			vp = .expanding
		}
	}
	return SizeHint{
		w:        w
		h:        h
		min_w:    w
		min_h:    h
		h_policy: hp
		v_policy: vp
	}
}

// ─── Прочие виджеты ────────────────────────────────────

// Полоса меню: своя высота, по ширине - на всю строку
pub fn (mb &MenuBar) measure(ctx &RenderContext) SizeHint {
	if !mb.visible {
		return SizeHint{}
	}
	font := ctx.get_font_immut(.regular, 0)
	h := max_f32(mb.bar_height, ctx.font_height_of(font) + 8)
	return SizeHint{
		w:        200
		h:        h
		min_h:    h
		max_h:    h
		h_policy: .expanding
		v_policy: .fixed
	}
}

// Область приёма: растягивается, но не уже своей подписи
pub fn (dz &DropZone) measure(ctx &RenderContext) SizeHint {
	font := ctx.get_font_immut(.regular, 0)
	sz := measure_text_lines(ctx, dz.text, font, 2)
	return scrollable_hint(sz.x + 32, sz.y + 32, max_f32(320, sz.x + 48), max_f32(160, sz.y + 48))
}

pub fn (sp &Splitter) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(160, 100, 480, 320)
}

pub fn (c &Calendar) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(220, 200, 280, 260)
}

pub fn (ib &ImageBackground) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(64, 64, 320, 240)
}

// Кнопки выбора даты и цвета - высотой стандартного контрола
pub fn (dp &DatePicker) measure(ctx &RenderContext) SizeHint {
	return SizeHint{
		w:        160
		h:        ctx.control_h()
		min_w:    100
		min_h:    ctx.control_h()
		v_policy: .fixed
	}
}

pub fn (cp &ColorPicker) measure(ctx &RenderContext) SizeHint {
	return SizeHint{
		w:        120
		h:        ctx.control_h()
		min_w:    60
		min_h:    ctx.control_h()
		v_policy: .fixed
	}
}

// Поле насыщенности/яркости с полосами оттенка (и прозрачности) в
// диалоге выбора цвета: квадрат под палитру, растягивается
pub fn (a &CpArea) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(200, 180, 340, 312)
}

// Образцы «Old | New» диалога выбора цвета: каждая половина вмещает
// свою подпись (отступ 4 с двух сторон), высота - стандартного контрола
pub fn (p &CpPreview) measure(ctx &RenderContext) SizeHint {
	font := ctx.get_font_immut(.regular, 0)
	half := max_f32(ctx.measure_text_with_font('Old', font).x, ctx.measure_text_with_font('New',
		font).x) + 8
	h := ctx.control_h()
	return SizeHint{
		w:        half * 2
		h:        h
		min_w:    half * 2
		min_h:    h
		h_policy: .fixed
		v_policy: .fixed
	}
}

// Календарь диалога выбора даты: сетка дней месяца
pub fn (a &DpArea) measure(ctx &RenderContext) SizeHint {
	return scrollable_hint(220, 200, 280, 250)
}
