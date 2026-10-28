module vgui

import math

// Файл rating.v: Rating - оценка звёздами (0..max), как в фотоальбомах, музыкальных плеерах и
// отзывах; и примитив рисования звезды RenderContext.fill_star (им пользуется и приложение -
// например, значки оценки на миниатюрах).
//
// Мышь: наведение показывает, какая оценка встанет (звёзды до курсора - цветом hover), щелчок
// ставит её; щелчок по уже стоящей оценке её снимает (allow_clear, как в Lightroom). Клавиши в
// фокусе: стрелки - на звезду меньше/больше, цифры 0..max - сразу оценка (focusable = false -
// фокуса нет, только мышь). readonly - только показ.
// on_change(value) - изменение пользователем; set_value кодом колбэк не вызывает (как у
// NumberField: оценка часто зеркалит модель приложения).
//
// Цвета - поля темы rating_on / rating_off / rating_hover (eff_rating_*: золотой, цвет рамок,
// золотой полупрозрачный); в CSS - `rating { color; off-color }`, `rating:hover { color }`.
// Рисование - только примитивы RenderContext (PROJECT.md, «Бэкенд рисования»).
// Тег типа kind_rating - widget_kinds.v.

// Rating - оценка звёздами. star_size - диаметр звезды (логические пиксели), gap - промежуток.
@[heap]
pub struct Rating {
pub mut:
	type_tag    int = kind_rating // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focused     bool
	focus_group int
	value       int
	max         int  = 5
	star_size   f32  = 18
	gap         f32  = 4
	allow_clear bool = true
	readonly    bool
	// focusable - щелчок даёт фокус (стрелки и цифры). false - только мышь: звёзды в панели
	// приложения, где стрелки и цифры - его собственные сочетания (листать кадры, ставить оценку)
	focusable bool = true
	on_change   fn (int) = unsafe { nil }
mut:
	hover      int  = -1 // оценка под курсором (1..max), -1 - курсор не над звёздами
	focus_anim Anim = Anim{
		role:    .focus
		epsilon: 0.02
	}
}

// rating создаёт оценку: rating(value: 3) или rating(max: 10).
@[params]
pub struct RatingConfig {
pub:
	value int
	max   int = 5
}

pub fn rating(cfg RatingConfig) &Rating {
	mut r := &Rating{
		max: if cfg.max > 0 { cfg.max } else { 5 }
	}
	r.value = clamp_int(cfg.value, 0, r.max)
	return r
}

// set_value - оценка кодом (зажимается в 0..max), колбэк не вызывается.
pub fn (mut r Rating) set_value(v int) {
	widget_changed()
	r.value = clamp_int(v, 0, r.max)
}

// change - оценка от пользователя: зажать, и если изменилась - on_change.
fn (mut r Rating) change(v int) {
	nv := clamp_int(v, 0, r.max)
	if nv == r.value {
		return
	}
	widget_changed()
	r.value = nv
	if !isnil(r.on_change) {
		r.on_change(nv)
	}
}

// star_rect - место звезды i (0..max-1): квадрат star_size, звёзды прижаты влево и по центру
// высоты.
fn (r &Rating) star_rect(i int) Rect {
	y := r.bounds.y + (r.bounds.h - r.star_size) * 0.5
	return Rect{r.bounds.x + f32(i) * (r.star_size + r.gap), y, r.star_size, r.star_size}
}

// star_at - оценка, которую поставил бы щелчок в точке (1..max); 0 - мимо звёзд. Промежуток
// между звёздами относится к левой звезде: курсор не «проваливается» между ними.
fn (r &Rating) star_at(x f32, y f32) int {
	if !r.bounds.contains(x, y) {
		return 0
	}
	slot := r.star_size + r.gap
	i := int((x - r.bounds.x) / slot)
	return if i >= 0 && i < r.max { i + 1 } else { 0 }
}

// ─── Рисование ─────────────────────────────────────────

pub fn (mut r Rating) draw(mut ctx RenderContext) {
	if !r.visible {
		return
	}
	en := ctx.is_enabled(r.enabled)
	interactive := en && !r.readonly
	if interactive && r.focusable {
		ctx.focus.register_rating(&r, r.focus_group)
	} else {
		ctx.focus_block(&r)
	}
	r.focused = ctx.focus.is_focused(&r)
	target := if r.focused && interactive { f32(1) } else { f32(0) }
	if r.focus_anim.update(target, ctx) {
		ctx.mark_anim_rect('rating', r.bounds.expanded(4))
	}
	on := ctx.theme.eff_rating_on()
	off := ctx.theme.eff_rating_off()
	hov := ctx.theme.eff_rating_hover()
	preview := if interactive && r.hover > 0 { r.hover } else { -1 }
	for i in 0 .. r.max {
		sr := r.star_rect(i)
		cx, cy := sr.x + sr.w * 0.5, sr.y + sr.h * 0.5
		mut c := if i < r.value { on } else { off }
		if preview > 0 {
			c = if i < preview { hov } else { off }
		}
		if !en {
			c = c.with_alpha(u8(int(c.a) / 2))
		}
		ctx.fill_star(cx, cy, sr.w * 0.5, c)
	}
	if r.max > 0 {
		last := r.star_rect(r.max - 1)
		ring := Rect{r.bounds.x, last.y, last.x + last.w - r.bounds.x, last.h}
		ctx.draw_focus_ring(ring.expanded(3), 4, r.focus_anim.value)
	}
}

// fill_star - залитая пятиконечная звезда с центром (cx, cy) и внешним радиусом radius (вершина
// вверх; внутренний радиус - 0.45 внешнего). Одним вызовом fill_triangles - десять треугольников
// от центра. Пригодна и для своих значков приложения (оценка на миниатюрах).
pub fn (mut ctx RenderContext) fill_star(cx f32, cy f32, radius f32, c Color) {
	inner := radius * 0.45
	mut pts := []Vec2{cap: 30}
	mut prev := Vec2{}
	for k in 0 .. 11 {
		a := f32(k % 10) * f32(math.pi) / 5 - f32(math.pi) / 2
		rr := if k % 2 == 0 { radius } else { inner }
		p := Vec2{cx + rr * math.cosf(a), cy + rr * math.sinf(a)}
		if k > 0 {
			pts << Vec2{cx, cy}
			pts << prev
			pts << p
		}
		prev = p
	}
	ctx.fill_triangles(pts, c)
}

// ─── События ───────────────────────────────────────────

pub fn (mut r Rating) handle_event(event &GuiEvent, app &App) bool {
	if !r.visible || r.readonly {
		return false
	}
	if !r.enabled && is_input_event(event) {
		r.hover = -1
		return false
	}
	match event.typ {
		.mouse_move {
			h := r.star_at(event.mouse_x, event.mouse_y)
			nh := if h > 0 { h } else { -1 }
			if nh != r.hover {
				r.hover = nh
				widget_changed()
			}
			return false
		}
		.mouse_leave {
			if r.hover != -1 {
				r.hover = -1
				widget_changed()
			}
			return false
		}
		.mouse_down {
			if event.mouse_btn != .left {
				return false
			}
			n := r.star_at(event.mouse_x, event.mouse_y)
			if n == 0 {
				return false
			}
			ctx_ptr := app.get_active_ctx()
			if !isnil(ctx_ptr) && r.focusable {
				mut ctx := unsafe { &RenderContext(ctx_ptr) }
				ctx.focus.focus_rating(&r, r.focus_group)
			}
			// Щелчок по стоящей оценке - снять её
			r.change(if r.allow_clear && n == r.value { 0 } else { n })
			return true
		}
		.key_down {
			if r.focused {
				return r.on_key(event)
			}
		}
		else {}
	}
	return false
}

// on_key - стрелки на звезду меньше/больше, цифры 0..max - сразу оценка.
fn (mut r Rating) on_key(event &GuiEvent) bool {
	k := event.keycode
	match k {
		sdl_k_right, sdl_k_up {
			r.change(r.value + 1)
			return true
		}
		sdl_k_left, sdl_k_down {
			r.change(r.value - 1)
			return true
		}
		else {}
	}
	digit := k - int(`0`)
	if digit >= 0 && digit <= 9 && digit <= r.max {
		r.change(digit)
		return true
	}
	return false
}
