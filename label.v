module vgui

// ═══════════════════════════════════════════════════════
// Label - виджет статичного текста (одна строка или несколько с переносом по словам).
// Файл содержит три перечисления для текста (TextAlign, VAlign, FontStyle - они же
// используются и другими текстовыми виджетами), структуру Label, два конструктора и отрисовку.
//
// Связи с остальной библиотекой:
//   * раскладка: размер для контейнеров считает measure() в layout_measure.v (метод Label.measure),
//     bounds раздаёт контейнер в arrange(); Label сам bounds только читает (кроме режима draw_auto);
//   * события: Label не интерактивен, handle_event всегда возвращает false;
//   * фокуса и оверлеев у Label нет.
// Label — text display widget
// ═══════════════════════════════════════════════════════

// Горизонтальное выравнивание текста. В режиме draw_auto (bounds нулевого размера) .center/.right
// означают, что bounds.x - это центр/правый край текста; в draw_in_rect - выравнивание внутри bounds.
pub enum TextAlign {
	left
	center
	right
}

// Вертикальное выравнивание блока строк внутри bounds (используется только в draw_in_rect).
pub enum VAlign {
	top
	middle
	bottom
}

// Начертание шрифта. Реальный TTF_Font берётся у RenderContext.get_font(style, size) из общего
// кэша FontSet окна - виджеты шрифты сами не хранят (PROJECT.md, «Архитектура рендеринга»).
pub enum FontStyle {
	regular
	bold
	italic
	bold_italic
	mono
	mono_bold
}

// Label - статичный текст. Поля:
//   color      - цвет; Color{0,0,0,0} (альфа 0) означает «взять theme.text_primary» на момент отрисовки;
//   font_size  - размер шрифта; 0 - размер по умолчанию (решает ctx.get_font);
//   wrap       - переносить по словам по ширине bounds (за вычетом pad с обеих сторон);
//   clip       - обрезать рисование по bounds (push_clip);
//   pad        - отступ от краёв bounds, влияет на ширину переноса и на позицию .left/.top/.bottom;
//   line_gap   - дополнительный интервал между строками, px.
pub struct Label {
pub mut:
	type_tag   int = kind_label // тег типа, см. widget_tag.v
	css        CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds     Rect
	text       string
	color      Color     = Color{0, 0, 0, 0}
	align      TextAlign = .left
	valign     VAlign    = .top
	font_style FontStyle = .regular
	font_size  int
	visible    bool = true
	enabled    bool = true // false - текст цветом text_disabled (enabled.v)
	tooltip    string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd        &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	wrap       bool
	clip       bool
	pad        f32 = 4
	line_gap   f32 = 2
}

// ───────────── Конструкторы ────────────────────────────

// label создаёт Label без переноса: bounds нулевого размера - тогда текст рисуется «как есть»
// от точки bounds.x/y (draw_auto).
pub fn label(text string) &Label {
	return &Label{
		text: text
	}
}

// set_text меняет текст метки; окно перерисуется само (widget_changed) - в
// отличие от прямого присваивания поля text, после которого в своём цикле
// нужен Window.invalidate*.
pub fn (mut l Label) set_text(text string) {
	widget_changed()
	l.text = text
}

// For use inside containers, with wrap
// label_wrap - Label с переносом по словам и обрезкой по bounds; для вставки в контейнеры,
// которые сами задают размер.
pub fn label_wrap(text string) &Label {
	return &Label{
		text: text
		wrap: true
		clip: true
	}
}

// ───────────── Отрисовка ───────────────────────────────

// draw рисует Label. Два режима, выбираются по bounds:
//   * bounds.w и bounds.h > 0 - текст размещается внутри прямоугольника (draw_in_rect);
//   * иначе - «свободный» текст от точки bounds.x/y (draw_auto), который заодно записывает
//     измеренный размер обратно в bounds.
pub fn (mut l Label) draw(mut ctx RenderContext) {
	if !l.visible || l.text.len == 0 {
		return
	}
	if !ctx.is_in_clip(l.bounds) {
		return
	}

	color := if !ctx.is_enabled(l.enabled) {
		ctx.theme.text_disabled
	} else if l.color.a > 0 {
		l.color
	} else {
		ctx.theme.text_primary
	}
	has_rect := l.bounds.w > 0 && l.bounds.h > 0

	if has_rect {
		l.draw_in_rect(mut ctx, color)
	} else {
		l.draw_auto(mut ctx, color)
	}
}

// draw_auto - режим без прямоугольника: измеряет текст, записывает размер в l.bounds (побочный
// эффект - так вызывающий код узнаёт размер) и рисует одну строку; перенос здесь не работает.
// Для .center/.right bounds.x трактуется как якорь (центр/правый край), поэтому x сдвигается влево.
fn (mut l Label) draw_auto(mut ctx RenderContext, color Color) {
	font := ctx.get_font(l.font_style, l.font_size)
	sz := ctx.measure_text_with_font(l.text, font)
	l.bounds.w = sz.x
	l.bounds.h = sz.y

	x := match l.align {
		.left { l.bounds.x }
		.center { l.bounds.x - sz.x / 2.0 }
		.right { l.bounds.x - sz.x }
	}

	ctx.draw_text_with_font(l.text, x, l.bounds.y, color, font)
}

// draw_in_rect - режим с прямоугольником: делит текст на строки (wrap_lines), считает общую высоту
// блока, выравнивает по valign и рисует каждую строку с выравниванием по align.
// Строки вне bounds по вертикали пропускаются (отсечение до вызова отрисовки текста экономит
// рендер длинных текстов).
fn (mut l Label) draw_in_rect(mut ctx RenderContext, color Color) {
	if l.clip {
		ctx.push_clip(l.bounds)
	}

	font := ctx.get_font(l.font_style, l.font_size)
	fh := ctx.font_height_of(font)
	line_step := fh + l.line_gap

	// Область текста - bounds без отступов (свой pad или padding из CSS,
	// css_apply.v). При равных отступах центрирование в ней даёт то же, что
	// центрирование во всём bounds.
	inner := l.bounds.inset(ctx.css_pad_of(voidptr(&l), l.pad))
	wrap_w := inner.w
	lines := l.wrap_lines(ctx, font, wrap_w)

	// // Высота блока: n строк * шаг минус хвостовой line_gap (после последней строки зазора нет).
	total_h := if lines.len > 0 {
		f32(lines.len) * line_step - l.line_gap
	} else {
		f32(0)
	}

	// Вертикальное выравнивание внутри всего bounds
	mut y := match l.valign {
		.top { inner.y }
		.middle { inner.y + (inner.h - total_h) / 2.0 }
		.bottom { inner.y + inner.h - total_h }
	}

	content_x := inner.x

	for line in lines {
		// // y растёт на line_step даже у пропущенных строк, поэтому положение следующих не сбивается.
		// Рисуем строку, если она хотя бы частично видна
		if y + fh < l.bounds.y {
			y += line_step
			continue
		}
		if y > l.bounds.y + l.bounds.h {
			break
		}

		if line.len > 0 {
			lw := ctx.measure_text_with_font(line, font).x
			x := match l.align {
				.left { content_x }
				.center { inner.x + (inner.w - lw) / 2.0 }
				.right { inner.x + inner.w - lw }
			}

			ctx.draw_text_with_font(line, x, y, color, font)
		}

		y += line_step
	}

	if l.clip {
		ctx.pop_clip()
	}
}

// ───────────── Word-wrap ───────────────────────────────

// wrap_lines режет l.text на визуальные строки. Сначала по '\n' (абзацы; пустой абзац даёт пустую
// строку), затем при l.wrap && max_w > 0 - жадный перенос по пробелам: слово переносится, когда
// строка с ним шире max_w. Слово шире max_w само не разбивается и выходит за границу.
// Без wrap (или при max_w <= 0) возвращаются просто абзацы.
fn (l &Label) wrap_lines(ctx &RenderContext, font voidptr, max_w f32) []string {
	paragraphs := l.text.split('\n')
	mut result := []string{cap: paragraphs.len * 2}

	if !l.wrap || max_w <= 0 {
		for p in paragraphs {
			result << p
		}
		return result
	}

	for p in paragraphs {
		if p.len == 0 {
			result << ''
			continue
		}
		words := p.split(' ')
		mut line := ''
		for word in words {
			test := if line.len == 0 { word } else { '${line} ${word}' }
			tw := ctx.measure_text_with_font(test, font).x
			if tw > max_w && line.len > 0 {
				result << line
				line = word
			} else {
				line = test
			}
		}
		if line.len > 0 {
			result << line
		}
	}
	return result
}

// ───────────── События ─────────────────────────────────

// handle_event: Label не реагирует на события; false - «событие не поглощено».
pub fn (mut l Label) handle_event(event &GuiEvent, app &App) bool {
	return false
}
