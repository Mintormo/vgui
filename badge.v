module vgui

// ═══════════════════════════════════════════════════════
// Badge — small status/count label with colored pill background
//
// Supports:
//   - text or numeric count display
//   - preset color variants (info, success, warning, error, neutral)
//   - custom bg/fg colors
//   - optional dot mode (no text, just a colored circle)
//
// Badge - чисто отображающий виджет: не фокусируется, события не обрабатывает
// (handle_event всегда false), поэтому в фокус-учёт (focus.v) не регистрируется
// и анимаций не имеет - mark_anim не нужен. Размер даёт preferred_size()
// (его использует measure() из layout_measure.v при раскладке), положение
// bounds выставляет контейнер в arrange() (через Layouted, widget_tree.v).
// ═══════════════════════════════════════════════════════

// BadgeVariant - готовая цветовая схема значка; цвета берутся из активной темы
// в resolve_colors(), так что значок следует за сменой темы.

pub enum BadgeVariant {
	info
	success
	warning
	error
	neutral
	accent
}

// Badge - значок-"пилюля" с текстом/числом или точка-индикатор (dot_mode).
// Поля bg/fg с альфой 0 означают "не задано": вместо них действует variant.
@[heap]
pub struct Badge {
pub mut:
	type_tag int = kind_badge // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	text     string
	variant  BadgeVariant = .info
	bg       Color        = Color{0, 0, 0, 0} // custom override; zero = use variant
	fg       Color        = Color{0, 0, 0, 0} // custom override; zero = auto
	dot_mode bool // show only a colored dot, no text
	visible  bool = true
	enabled  bool = true // false - приглушённые цвета (enabled.v)
	tooltip  string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	pad_x    f32 = 7
	pad_y    f32 = 3
}

// badge создаёт значок с произвольным текстом (вариант .info).
pub fn badge(text string) &Badge {
	return &Badge{
		text: text
	}
}

// badge_count - значок с числом n (просто text = n.str(); без "99+" и т.п.).
pub fn badge_count(n int) &Badge {
	return &Badge{
		text: n.str()
	}
}

// badge_dot - значок-точка без текста (круг 10x10 по preferred_size).
pub fn badge_dot() &Badge {
	return &Badge{
		dot_mode: true
	}
}

// ─── Size hint (for auto-sizing in containers) ─────────

// preferred_size - желаемый размер (w, h): для точки - 10x10, для текста -
// размер текста плюс pad_x/pad_y с каждой стороны; ширина не меньше высоты,
// чтобы короткий текст ("1") давал круг, а не вытянутую по вертикали пилюлю.
pub fn (b &Badge) preferred_size(ctx &RenderContext) (f32, f32) {
	if b.dot_mode {
		d := f32(10)
		return d, d
	}
	font := ctx.get_font_immut(.regular, 0)
	sz := ctx.measure_text_with_font(b.text, font)
	w := sz.x + b.pad_x * 2
	h := sz.y + b.pad_y * 2
	return max_f32(w, h), h // keep pill at least as wide as it is tall
}

// ─── Drawing ───────────────────────────────────────────

// draw рисует значок в bounds: в dot_mode - круг по меньшей стороне, иначе
// скруглённый прямоугольник (радиус = полвысоты, т.е. пилюля) и по центру текст.
// Текст обрезается по bounds, если контейнер выделил места меньше желаемого.
pub fn (mut b Badge) draw(mut ctx RenderContext) {
	if !b.visible {
		return
	}
	if !ctx.is_in_clip(b.bounds) {
		return
	}

	mut bg, mut fg := b.resolve_colors(ctx)
	if !ctx.is_enabled(b.enabled) {
		bg = ctx.disabled_color(bg)
		fg = ctx.disabled_color(fg)
	}

	if b.dot_mode {
		r := min_f32(b.bounds.w, b.bounds.h) * 0.5
		cx := b.bounds.x + b.bounds.w * 0.5
		cy := b.bounds.y + b.bounds.h * 0.5
		ctx.fill_circle(cx, cy, r, bg)
		return
	}

	radius := b.bounds.h * 0.5
	ctx.fill_rounded_rect(b.bounds, bg, radius)

	if b.text.len > 0 {
		font := ctx.get_font(.regular, 0)
		sz := ctx.measure_text_with_font(b.text, font)
		tx := b.bounds.x + (b.bounds.w - sz.x) * 0.5
		ty := b.bounds.y + (b.bounds.h - sz.y) * 0.5
		ctx.push_clip(b.bounds)
		ctx.draw_text_with_font(b.text, tx, ty, fg, font)
		ctx.pop_clip()
	}
}

// resolve_colors возвращает пару (фон, цвет текста). Приоритет: явный bg
// (с автоматическим белым текстом, если fg не задан) > цвета варианта из темы
// (с заменой текста на fg, если он задан).
fn (b &Badge) resolve_colors(ctx &RenderContext) (Color, Color) {
	// Custom overrides take priority
	if b.bg.a > 0 {
		auto_fg := if b.fg.a > 0 { b.fg } else { color_white }
		return b.bg, auto_fg
	}

	bg := match b.variant {
		.info { ctx.theme.accent }
		.success { ctx.theme.success }
		.warning { ctx.theme.warning }
		.error { ctx.theme.error_color }
		.neutral { ctx.theme.button_bg }
		.accent { ctx.theme.accent }
	}
	fg := match b.variant {
		.info { ctx.theme.accent_text }
		.success { color_white }
		.warning { color_white }
		.error { color_white }
		.neutral { ctx.theme.text_primary }
		.accent { ctx.theme.accent_text }
	}

	if b.fg.a > 0 {
		return bg, b.fg
	}
	return bg, fg
}

// handle_event: значок не интерактивен, событие никогда не поглощается.
pub fn (mut b Badge) handle_event(event &GuiEvent, app &App) bool {
	return false
}
