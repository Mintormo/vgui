module vgui

// ═══════════════════════════════════════════════════════
// Separator — visual divider line widget
//
// A thin line used inside VBox/HBox to separate groups
// of widgets. Can be horizontal or vertical, with
// customizable thickness, color and margin (inset from
// edges).
//
// In a VBox the separator is horizontal (stretches width).
// In an HBox the separator is vertical (stretches height).
// Direction is auto-detected from bounds aspect ratio,
// or can be forced via `dir`.
//
// Usage (code):
//   v.add(vgui.separator())        // 1px high
//   v.add(vgui.hseparator())       // явно горизонтальный (отступы - поле margin)
//   h.add(vgui.vseparator())
//
// Usage (YAML):
//   - type: separator
//   - type: separator
//     dir: horizontal   # horizontal | vertical, иначе auto
//     thickness: 1
//     margin: 4
//     color: "#3a3a3a"
// ═══════════════════════════════════════════════════════
//
// Связь с остальной библиотекой:
// - раскладка: Separator.measure() (layout_measure.v) заявляет толщину
//   линии и политику растяжения по длинной оси - горизонтальный тянется
//   по ширине (h_policy .expanding), вертикальный - по высоте; при .auto
//   направление решает контейнер, толщина заявлена минимумом по обеим осям;
// - bounds выдаёт контейнер в arrange() (Layouted - в widget_tree.v);
// - событий не обрабатывает и фокуса не принимает - чисто декоративный.

// SeparatorDir - ориентация линии. .auto разрешается в draw() по
// соотношению сторон bounds, т.е. по тому, как контейнер растянул виджет.
pub enum SeparatorDir {
	auto       // detect from bounds: wider → horizontal, taller → vertical
	horizontal // ─── line
	vertical   // │ line
}

// Separator - тонкая разделительная линия. Сам виджет занимает весь
// выданный ему прямоугольник bounds, а линия толщиной thickness рисуется
// по его центру поперёк и с отступом margin с обоих концов вдоль.
pub struct Separator {
pub mut:
	type_tag  int = kind_separator // тег типа, см. widget_tag.v
	bounds    Rect
	dir       SeparatorDir = .auto
	thickness f32          = 1
	color     Color        = Color{0, 0, 0, 0} // a == 0 -> цвет из темы (theme.eff_sep_color())
	margin    f32 // inset from edges (both sides)
	visible   bool = true
	enabled   bool = true // false - линия приглушена (enabled.v)
}

// ─── Constructors ──────────────────────────────────────

// Generic separator (auto direction)
pub fn separator() &Separator {
	return &Separator{}
}

// Explicitly horizontal separator (for VBox)
pub fn hseparator() &Separator {
	return &Separator{
		dir: .horizontal
	}
}

// Explicitly vertical separator (for HBox)
pub fn vseparator() &Separator {
	return &Separator{
		dir: .vertical
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw рисует линию в пределах s.bounds. Ничего не делает, если виджет
// скрыт или целиком вне текущего клипа (частичный кадр dirty regions).
// Если линия короче 2*margin (lw/lh <= 0), не рисуется ничего.
pub fn (mut s Separator) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if !ctx.is_in_clip(s.bounds) {
		return
	}

	// Прозрачный цвет (значение по умолчанию) означает «взять из темы» -
	// так разделитель следует за сменой светлой/тёмной темы.
	c0 := if s.color.a > 0 { s.color } else { ctx.theme.eff_sep_color() }
	c := if ctx.is_enabled(s.enabled) { c0 } else { ctx.disabled_color(c0) }

	// Разрешаем .auto: ширина >= высоты -> горизонтальная линия
	// (так растягивает VBox), иначе вертикальная (HBox).

	actual_dir := match s.dir {
		.horizontal {
			SeparatorDir.horizontal
		}
		.vertical {
			SeparatorDir.vertical
		}
		.auto {
			if s.bounds.w >= s.bounds.h {
				SeparatorDir.horizontal
			} else {
				SeparatorDir.vertical
			}
		}
	}

	match actual_dir {
		// .auto здесь недостижим (actual_dir уже разрешён выше), но match
		// в V обязан быть исчерпывающим.
		.horizontal, .auto {
			// Horizontal line centered vertically in bounds
			ly := s.bounds.y + (s.bounds.h - s.thickness) * 0.5
			lx := s.bounds.x + s.margin
			lw := s.bounds.w - s.margin * 2
			if lw > 0 {
				ctx.fill_rect(Rect{lx, ly, lw, s.thickness}, c)
			}
		}
		.vertical {
			// Vertical line centered horizontally in bounds
			lx := s.bounds.x + (s.bounds.w - s.thickness) * 0.5
			ly := s.bounds.y + s.margin
			lh := s.bounds.h - s.margin * 2
			if lh > 0 {
				ctx.fill_rect(Rect{lx, ly, s.thickness, lh}, c)
			}
		}
	}
}

// handle_event: разделитель не реагирует на ввод; false - событие не
// поглощено и идёт дальше.
pub fn (mut s Separator) handle_event(event &GuiEvent, app &App) bool {
	return false
}
