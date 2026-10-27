module vgui

// Файл spinner.v: Spinner - индикатор "идёт работа" (неопределённый прогресс). Три стиля
// (SpinnerStyle): дуга, бегущие точки, две противоположные дуги. Опциональная подпись
// text рисуется под индикатором. Это чисто декоративный виджет: событий не обрабатывает, фокуса
// не берёт. Пока spinning == true, он каждый кадр просит следующий кадр через mark_anim_rect
// (см. «Инвалидация и dirty regions» в PROJECT.md), а угол вращения вычисляется по
// абсолютному времени now_ms() (clock.v), а не по счётчику кадров - скорость не зависит от fps.
// Дуги строятся треугольниками (ctx.fill_triangles, sdl3_render.v), как и остальные примитивы.
// Тег типа kind_spinner - widget_tag.v.

import math

// Вид индикатора: arc - одна дуга ~270 градусов на кольце-фоне; dots - кольцо из точек,
// уменьшающихся и бледнеющих "хвостом"; dual - две дуги по ~120 градусов друг напротив друга.
pub enum SpinnerStyle {
	arc
	dots
	dual
}

// Индикатор загрузки. color/bg_color с нулевой альфой - брать цвета из темы. size - диаметр
// (0 - по bounds); thickness - толщина кольца; speed - обороты в секунду (для dots вдвое
// медленнее); dot_count/dot_size - параметры стиля dots. spinning == false - рисуется только
// неподвижное фоновое кольцо (и подпись), анимация не запрашивается.
pub struct Spinner {
pub mut:
	type_tag  int = kind_spinner // тег типа, см. widget_tag.v
	css       CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds    Rect
	visible   bool = true
	enabled   bool = true // false - приглушённые цвета (enabled.v)
	tooltip   string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd       &DragSpec    = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	spinning  bool         = true
	style     SpinnerStyle = .arc
	color     Color        = Color{0, 0, 0, 0}
	bg_color  Color        = Color{0, 0, 0, 0}
	size      f32
	thickness f32 = 3
	speed     f32 = 1.0
	text      string
	text_gap  f32 = 4
	dot_count int = 8
	dot_size  f32 = 3
}

pub fn spinner() &Spinner {
	return &Spinner{}
}

pub fn spinner_with_text(text string) &Spinner {
	return &Spinner{
		text: text
	}
}

// Включает/выключает вращение; окно перерисуется само (widget_changed), дальше
// при start() анимацию запрашивает draw().
pub fn (mut s Spinner) start() {
	widget_changed()
	s.spinning = true
}

pub fn (mut s Spinner) stop() {
	widget_changed()
	s.spinning = false
}

pub fn (s &Spinner) is_spinning() bool {
	return s.spinning
}

fn (s &Spinner) eff_color(ctx &RenderContext) Color {
	c := if s.color.a > 0 { s.color } else { ctx.theme.eff_spin_color() }
	return if ctx.is_enabled(s.enabled) { c } else { ctx.disabled_color(c) }
}

// Цвет фонового кольца: свой или цвет темы с прозрачностью 60 (кольцо должно быть бледным).
fn (s &Spinner) eff_bg_color(ctx &RenderContext) Color {
	if s.bg_color.a > 0 {
		return s.bg_color
	}
	return ctx.theme.eff_spin_bg().with_alpha(60)
}

// Возвращает (диаметр, центр x, центр y). Место под подпись (высота строки + зазор)
// вычитается из высоты bounds, индикатор центрируется в остатке. Диаметр без явного size -
// меньшая из ширины и оставшейся высоты, но не менее 4.
fn (s &Spinner) spinner_geometry(ctx &RenderContext) (f32, f32, f32) {
	mut text_h := f32(0)
	if s.text.len > 0 {
		font := ctx.get_font_immut(.regular, 0)
		text_h = ctx.font_height_of(font) + s.text_gap
	}

	avail_h := s.bounds.h - text_h

	diameter := if s.size > 0 {
		s.size
	} else {
		min_f32(s.bounds.w, max_f32(avail_h, 4))
	}

	cx := s.bounds.x + s.bounds.w * 0.5
	cy := s.bounds.y + avail_h * 0.5

	return diameter, cx, cy
}

// Текущий угол (радианы) = время в секундах * speed * 2*pi. Число 6.2831853 - 2*pi,
// встречается ниже в разных местах.
fn spinner_angle(speed f32) f32 {
	ms := now_ms()
	t := f32(ms) * 0.001 * speed
	return t * 6.2831853
}

// Рисование: если вращается - запрашивает следующий кадр и рисует выбранный стиль и подпись;
// если остановлен - только неподвижное кольцо (draw_static).
pub fn (mut s Spinner) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	// Mark animation needed if spinner is actually visible and spinning.
	// mark_anim_rect (not a raw ctx.needs_animation = true write) so the
	// dirty tracker actually schedules s's rect for the NEXT frame.
	// Standing here, above the is_in_clip early-return, is cosmetic:
	// mark_anim_rect re-checks is_in_clip(s.bounds) itself, so the order
	// changes nothing. What keeps the animation from freezing when a partial
	// frame misses this widget is the bbox invariant documented at
	// mark_anim_rect in render_context.v.
	if s.spinning {
		ctx.mark_anim_rect('spinner', s.bounds)
	}

	if !ctx.is_in_clip(s.bounds) {
		return
	}

	if !s.spinning {
		s.draw_static(mut ctx)
		return
	}

	match s.style {
		.arc { s.draw_arc(mut ctx) }
		.dots { s.draw_dots(mut ctx) }
		.dual { s.draw_dual(mut ctx) }
	}

	if s.text.len > 0 {
		s.draw_label(mut ctx)
	}
}

// Кольцо-фон + бегущая дуга длиной 4.712 рад (3*pi/2, то есть 270 градусов). Радиус - до середины
// толщины кольца, поэтому от диаметра вычитается thickness*2 и делится пополам.
// Если места не хватает (радиус < 1), ничего не рисуется.
fn (s &Spinner) draw_arc(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed)
	c := s.eff_color(ctx)
	bg := s.eff_bg_color(ctx)

	// Background: полное кольцо (spinner_draw_circle_arc; SDL2_gfx здесь больше не используется)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)
	// Foreground: spinning arc (~270°)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle, angle + 4.712, c)
}

// Две дуги по 2.094 рад (2*pi/3, 120 градусов), сдвинутые на pi (противоположные).
fn (s &Spinner) draw_dual(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed)
	c := s.eff_color(ctx)
	bg := s.eff_bg_color(ctx)

	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle, angle + 2.094, c)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle + 3.1416, angle + 3.1416 +
		2.094, c)
}

// count точек (минимум 3) по окружности. Индекс i определяет "хвост": чем больше i,
// тем точка меньше и прозрачнее (альфа убывает квадратично, радиус - линейно от 100% до 50%).
fn (s &Spinner) draw_dots(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.dot_size * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed * 0.5)
	c := s.eff_color(ctx)
	count := max_int(3, s.dot_count)

	for i in 0 .. count {
		t := f32(i) / f32(count)
		a := angle + t * 6.2831853
		dx := cx + radius * math.cosf(a)
		dy := cy + radius * math.sinf(a)

		fade := f32(count - i) / f32(count)
		alpha := u8(fade * fade * f32(c.a))
		dot_c := Color{c.r, c.g, c.b, alpha}
		dot_r := s.dot_size * (0.5 + fade * 0.5)

		ctx.fill_circle(dx, dy, dot_r, dot_c)
	}
}

// Состояние "остановлен": только фоновое кольцо и подпись.
fn (s &Spinner) draw_static(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	bg := s.eff_bg_color(ctx)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)

	if s.text.len > 0 {
		s.draw_label(mut ctx)
	}
}

// Подпись по центру внизу bounds (цвет - color спиннера, иначе text_secondary темы).
fn (s &Spinner) draw_label(mut ctx RenderContext) {
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	tw := ctx.measure_text_with_font(s.text, font).x

	tc := if !ctx.is_enabled(s.enabled) {
		ctx.theme.text_disabled
	} else if s.color.a > 0 {
		s.color
	} else {
		ctx.theme.text_secondary
	}

	tx := s.bounds.x + (s.bounds.w - tw) * 0.5
	ty := s.bounds.y + s.bounds.h - fh
	ctx.draw_text_with_font(s.text, tx, ty, tc, font)
}

// Рисует дугу-полосу толщиной thickness по окружности радиуса radius от угла start до end
// (радианы). Дуга разбивается на сегменты (минимум 48, плотнее на длинных дугах), каждый -
// трапеция между внутренним и внешним радиусами из двух треугольников. Ничего не рисует
// для прозрачного цвета или нулевой/отрицательной длины дуги.
fn spinner_draw_circle_arc(mut ctx RenderContext, cx f32, cy f32, radius f32, thickness f32, start f32, end f32, c Color) {
	if c.a == 0 || radius < 1 {
		return
	}

	arc_span := end - start
	if arc_span <= 0 {
		return
	}

	half_t := thickness * 0.5
	r_inner := max_f32(0.5, radius - half_t)
	r_outer := radius + half_t

	arc_len_px := r_outer * abs_f32(arc_span)
	segments := max_int(48, int(arc_len_px * 1.2))
	step := arc_span / f32(segments)

	// Дуга - лента трапеций между внутренним и внешним радиусом; набор
	// треугольников заливается одним вызовом (fill_triangles сам выставляет
	// blend mode - это важно для полупрозрачного кольца-фона, которое рисуется
	// этой же функцией).
	mut pts := []Vec2{cap: segments * 6}

	mut a0 := start
	mut ix0 := cx + r_inner * math.cosf(a0)
	mut iy0 := cy + r_inner * math.sinf(a0)
	mut ox0 := cx + r_outer * math.cosf(a0)
	mut oy0 := cy + r_outer * math.sinf(a0)

	for i in 1 .. segments + 1 {
		a1 := start + f32(i) * step
		ix1 := cx + r_inner * math.cosf(a1)
		iy1 := cy + r_inner * math.sinf(a1)
		ox1 := cx + r_outer * math.cosf(a1)
		oy1 := cy + r_outer * math.sinf(a1)

		// Trapezoid = 2 triangles: (ix0,iy0),(ox0,oy0),(ox1,oy1) and (ix0,iy0),(ox1,oy1),(ix1,iy1)
		pts << Vec2{ix0, iy0}
		pts << Vec2{ox0, oy0}
		pts << Vec2{ox1, oy1}
		pts << Vec2{ix0, iy0}
		pts << Vec2{ox1, oy1}
		pts << Vec2{ix1, iy1}

		ix0 = ix1
		iy0 = iy1
		ox0 = ox1
		oy0 = oy1
	}

	ctx.fill_triangles(pts, c)
}

// Спиннер событий не принимает - всегда false (события идут нижележащим виджетам).
pub fn (mut s Spinner) handle_event(event &GuiEvent, app &App) bool {
	return false
}
