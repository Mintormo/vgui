module vgui

pub struct Rect {
pub mut:
	x f32
	y f32
	w f32
	h f32
}

pub fn (r Rect) contains(px f32, py f32) bool {
	return px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h
}

pub fn (r Rect) intersects(other Rect) bool {
	return r.x < other.x + other.w && r.x + r.w > other.x && r.y < other.y + other.h
		&& r.y + r.h > other.y
}

pub fn (r Rect) intersection(other Rect) Rect {
	x1 := max_f32(r.x, other.x)
	y1 := max_f32(r.y, other.y)
	x2 := min_f32(r.x + r.w, other.x + other.w)
	y2 := min_f32(r.y + r.h, other.y + other.h)
	if x2 <= x1 || y2 <= y1 {
		return Rect{0, 0, 0, 0}
	}
	return Rect{x1, y1, x2 - x1, y2 - y1}
}

pub fn (r Rect) expanded(pad f32) Rect {
	return Rect{r.x - pad, r.y - pad, r.w + pad * 2, r.h + pad * 2}
}

pub fn (r Rect) shrunk(pad f32) Rect {
	return Rect{r.x + pad, r.y + pad, r.w - pad * 2, r.h - pad * 2}
}

pub struct Color {
pub mut:
	r u8
	g u8
	b u8
	a u8 = 255
}

pub fn (c Color) with_alpha(a u8) Color {
	return Color{c.r, c.g, c.b, a}
}

pub fn (c Color) blend(other Color, t f32) Color {
	it := 1.0 - t
	return Color{
		r: u8(f32(c.r) * it + f32(other.r) * t)
		g: u8(f32(c.g) * it + f32(other.g) * t)
		b: u8(f32(c.b) * it + f32(other.b) * t)
		a: u8(f32(c.a) * it + f32(other.a) * t)
	}
}

pub fn (c Color) brighten(amount f32) Color {
	return Color{
		r: u8(min_f32(255, f32(c.r) + 255.0 * amount))
		g: u8(min_f32(255, f32(c.g) + 255.0 * amount))
		b: u8(min_f32(255, f32(c.b) + 255.0 * amount))
		a: c.a
	}
}

pub fn (c Color) darken(amount f32) Color {
	return Color{
		r: u8(max_f32(0, f32(c.r) - 255.0 * amount))
		g: u8(max_f32(0, f32(c.g) - 255.0 * amount))
		b: u8(max_f32(0, f32(c.b) - 255.0 * amount))
		a: c.a
	}
}

pub struct Vec2 {
pub mut:
	x f32
	y f32
}

pub fn max_f32(a f32, b f32) f32 {
	return if a > b { a } else { b }
}

pub fn min_f32(a f32, b f32) f32 {
	return if a < b { a } else { b }
}

pub fn abs_f32(v f32) f32 {
	return if v < 0 { -v } else { v }
}

pub fn clamp_f32(v f32, lo f32, hi f32) f32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

pub fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

pub fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

pub fn clamp_int(v int, lo int, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

pub fn abs_int(v int) int {
	return if v < 0 { -v } else { v }
}

pub fn lerp(a f32, b f32, t f32) f32 {
	return a + (b - a) * t
}

fn anim_running(current f32, target f32) bool {
	return abs_f32(current - target) > 0.005
}
