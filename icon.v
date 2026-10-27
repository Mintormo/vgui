module vgui

// ═══════════════════════════════════════════════════════
// Icon — draws a single glyph from the embedded Lucide icon font, centered
// in its bounds. Lightweight and passive (no zoom/pan/events), same spirit
// as ImageBackground. See sdl3_icon_font.v for the glyph rendering pipeline and
// icon_names.v for the name → codepoint map.
// ═══════════════════════════════════════════════════════
//
// Иконка - листовой виджет (kind_icon): раскладка берёт её размер из
// measure() (layout_measure.v), bounds выдаёт контейнер в arrange(), а draw()
// лишь просит RenderContext.draw_icon_glyph нарисовать глиф по центру bounds.
// Неизвестное имя иконки не ошибка: виджет просто ничего не рисует.
// Сеттеры кадр не инвалидируют (общее правило библиотеки) - в своём цикле
// после них зовите Window.invalidate*.

// Icon - состояние виджета-иконки. @[heap]: на виджет ссылаются по указателю
// из контейнеров, реестров capi и Python, поэтому он обязан жить в куче.
@[heap]
pub struct Icon {
pub mut:
	type_tag int = kind_icon // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	name     string // имя глифа Lucide (например "save"), см. icon_names.v
	size     int = 16 // размер глифа в логических пикселях (до умножения на ui_scale)
	// a == 0 - цвет темы (theme.text_primary). Значение по умолчанию задано
	// явно: у Color альфа по умолчанию 255, без него иконка была бы чёрной
	color   Color = Color{0, 0, 0, 0}
	visible bool  = true
	enabled bool  = true // false - глиф цветом text_disabled (enabled.v)
	tooltip string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd     &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
}

// ─── Constructors ──────────────────────────────────────

// icon создаёт иконку по имени Lucide с размером 16 и цветом темы.
pub fn icon(name string) &Icon {
	return &Icon{
		name: name
	}
}

// ─── Public API ────────────────────────────────────────

pub fn (mut ic Icon) set_name(name string) {
	ic.name = name
}

pub fn (mut ic Icon) set_size(size int) {
	ic.size = size
}

// set_color задаёт цвет глифа; Color с альфой 0 означает «цвет текста темы».
pub fn (mut ic Icon) set_color(c Color) {
	ic.color = c
}

// ─── Drawing ───────────────────────────────────────────

// draw рисует глиф по центру bounds. Ранние выходы: скрытая иконка, иконка
// вне текущего клипа (частичный кадр dirty regions) и неизвестное имя.
pub fn (mut ic Icon) draw(mut ctx RenderContext) {
	if !ic.visible {
		return
	}
	if !ctx.is_in_clip(ic.bounds) {
		return
	}
	codepoint, found := icon_codepoint(ic.name)
	if !found {
		return
	}
	// Альфа 0 - маркер «цвет не задан»: берём цвет текста текущей темы, чтобы
	// иконка автоматически перекрашивалась при смене светлой/тёмной темы.
	c := if !ctx.is_enabled(ic.enabled) {
		ctx.theme.text_disabled
	} else if ic.color.a > 0 {
		ic.color
	} else {
		ctx.theme.text_primary
	}
	ctx.draw_icon_glyph(codepoint, ic.bounds, ic.size, c)
}

// ─── Events ────────────────────────────────────────────

// Icon is passive: it never consumes events.
pub fn (mut ic Icon) handle_event(event &GuiEvent, app &App) bool {
	return false
}
