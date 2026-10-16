module vgui

import math
import os
import strconv

// ═══════════════════════════════════════════════════════
// PlotView — function plot widget with axes, grid,
// scroll-by-drag, zoom and scrollbars.
//
// Features:
//   - Pan by left mouse drag (cursor changes to "move")
//   - Wheel = vertical scroll, Shift+wheel = horizontal,
//     Ctrl+wheel = zoom (cursor-centered)
//   - Scrollbars on right and bottom edges (draggable)
//   - Multiple functions can be plotted in different colors
//   - Auto-computed "nice" major/minor grid steps + labels
//   - Auto-extending viewport — graph re-samples on the fly
//
// Usage:
//   mut pv := vgui.plot_view()
//   pv.add_function(fn (x f32) f32 { return math.sinf(x) },
//                   vgui.Color{80, 200, 255, 255})
//   pv.add_function(fn (x f32) f32 { return x * x * 0.1 },
//                   vgui.Color{255, 140, 80, 255})
//   pv.set_range(-10, 10, -5, 5)
// ═══════════════════════════════════════════════════════

// PlotFunc — функция y = f(x) для серии-функции. Может вернуть NaN/±Inf: такие точки разрывают линию (не рисуются).
pub type PlotFunc = fn (x f32) f32

// PlotSeriesKind — вид серии: function (кривая по формуле, сэмплируется по пикселям), points (ломаная по точкам, опционально с маркерами), scatter (только точки).
pub enum PlotSeriesKind {
	function // y = f(x), sampled per pixel
	points   // array of (x, y) points, connected by lines
	scatter  // array of (x, y) points, dots only (no lines)
}

// PlotPoint — точка данных в координатах графика (не экрана).
pub struct PlotPoint {
pub mut:
	x f32
	y f32
}

// PlotSeries — одна серия данных (кривая/ломаная/облако). Приватна: создаётся через
// add_function*/add_points*/add_scatter*. Для function используется func, для
// остальных — points (копия данных). name - подпись серии в легенде (draw_legend);
// серия без имени в легенду не попадает.
struct PlotSeries {
mut:
	kind         PlotSeriesKind = .function
	func         PlotFunc       = unsafe { nil }
	points       []PlotPoint // used for .points and .scatter
	color        Color
	thickness    f32  = 2
	visible      bool = true
	name         string
	point_size   f32 = 4 // marker radius for .scatter / points markers
	show_markers bool // for .points: draw dots on each vertex
}

// Константы PlotView: plot_virtual_range — на сколько единиц (±) полосы прокрутки
// считают «весь мир» графика (раздвигается, если вид вышел за него); plot_sb_w —
// толщина полос прокрутки; plot_axis_pad_l/b — поля слева/снизу под подписи осей;
// plot_min_span/max_span — допустимая ширина/высота видимой области по каждой оси.
const plot_virtual_range = f32(1000.0)
const plot_sb_w = f32(12)
const plot_axis_pad_l = f32(48)
const plot_axis_pad_b = f32(24)
const plot_min_span = f32(0.001)
const plot_max_span = f32(1_000_000.0)

// PlotView — график функций и наборов точек: сетка, оси с подписями, перетаскивание
// мышью, колесо (прокрутка/зум) и полосы прокрутки. События ловит только когда
// курсор над виджетом (hovered); в фокус-учёте не участвует, поэтому горячие клавиши
// (Home, Ctrl+/-/0) работают при наведении мыши, а не при фокусе.
//
// Система координат: видимая область — прямоугольник (view_x, view_y, view_w, view_h)
// в координатах данных (view_y — НИЖНЯЯ граница, ось Y направлена вверх);
// соответствие экрану даёт plot_rect() (область внутри полей) и пары px/py
// (данные -> экран) и plot_x/plot_y (экран -> данные). Серии рисуются с клипом по
// plot_rect. Размер — measure() в layout_measure.v.
@[heap]
pub struct PlotView {
pub mut:
	type_tag int = kind_plot_view // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel   bool = true
	bounds  Rect
	visible bool = true
	enabled bool = true
	tooltip string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	hovered bool
	// Viewport in plot-space coordinates
	// view_x/view_y — левый и нижний край видимой области, view_w/view_h — её размеры (в единицах данных)
	view_x f32 = -10.0
	view_y f32 = -5.0
	view_w f32 = 20.0
	view_h f32 = 10.0
	// Appearance
	bg_color         Color = Color{0, 0, 0, 0}
	axis_color       Color = Color{0, 0, 0, 0}
	grid_major_color Color = Color{0, 0, 0, 0}
	grid_minor_color Color = Color{0, 0, 0, 0}
	label_color      Color = Color{0, 0, 0, 0}
	border_color     Color = Color{0, 0, 0, 0}
	show_grid        bool  = true
	show_minor_grid  bool  = true
	show_labels      bool  = true
	show_axes        bool  = true
	show_scrollbars  bool  = true
	// Легенда: подписи именованных серий (add_*_named) в правом верхнем углу графика.
	show_legend bool = true
	// Series
	// серии в порядке добавления (поздние рисуются поверх)
	series []PlotSeries
	// Pan drag state
	// панорамирование мышью: panning — идёт перетаскивание, pan_start_* — позиция мыши и вид в момент нажатия (вид считается от них, а не накапливается по дельтам)
	panning      bool
	pan_start_mx f32
	pan_start_my f32
	pan_start_vx f32
	pan_start_vy f32
	// Scrollbar drag state
	// перетаскивание ползунков: *_dragging — идёт, sb_drag_start — координата мыши, sb_drag_start_val — значение вида в момент нажатия
	vsb_dragging      bool
	hsb_dragging      bool
	vsb_hovered       bool
	hsb_hovered       bool
	sb_drag_start     f32
	sb_drag_start_val f32
	// Scroll/zoom speed
	scroll_speed f32 = 30.0
	zoom_speed   f32 = 0.15
}

// ─── Constructors ──────────────────────────────────────

// plot_view создаёт график с видом x -10..10, y -5..5.
pub fn plot_view() &PlotView {
	return &PlotView{}
}

// ─── Public API ────────────────────────────────────────

// add_function добавляет кривую y = f(x) заданного цвета (толщина 2).
pub fn (mut p PlotView) add_function(f PlotFunc, color Color) {
	p.series << PlotSeries{
		func:  f
		color: color
	}
}

// add_function_named — то же с именем серии.
pub fn (mut p PlotView) add_function_named(name string, f PlotFunc, color Color) {
	p.series << PlotSeries{
		func:  f
		color: color
		name:  name
	}
}

// add_function_thick — кривая с заданной толщиной (при толщине > 4 рисуется медленным путём по сегментам).
pub fn (mut p PlotView) add_function_thick(f PlotFunc, color Color, thickness f32) {
	p.series << PlotSeries{
		func:      f
		color:     color
		thickness: thickness
	}
}

// clear_functions удаляет ВСЕ серии (не только функции, но и точки).
pub fn (mut p PlotView) clear_functions() {
	p.series.clear()
}

// ─── Point series API ──────────────────────────────────

// Add a connected line plot from an array of (x,y) points.
pub fn (mut p PlotView) add_points(points []PlotPoint, color Color) {
	p.series << PlotSeries{
		kind:   .points
		points: points.clone()
		color:  color
	}
}

// add_points_named / add_points_thick — варианты add_points с именем / толщиной линии. Данные копируются.
pub fn (mut p PlotView) add_points_named(name string, points []PlotPoint, color Color) {
	p.series << PlotSeries{
		kind:   .points
		points: points.clone()
		color:  color
		name:   name
	}
}

pub fn (mut p PlotView) add_points_thick(points []PlotPoint, color Color, thickness f32) {
	p.series << PlotSeries{
		kind:      .points
		points:    points.clone()
		color:     color
		thickness: thickness
	}
}

// Same as add_points but also draws a circular marker at each point.
pub fn (mut p PlotView) add_points_with_markers(points []PlotPoint, color Color, marker_size f32) {
	p.series << PlotSeries{
		kind:         .points
		points:       points.clone()
		color:        color
		point_size:   marker_size
		show_markers: true
	}
}

// Add scatter plot — only dots, no connecting lines.
pub fn (mut p PlotView) add_scatter(points []PlotPoint, color Color) {
	p.series << PlotSeries{
		kind:   .scatter
		points: points.clone()
		color:  color
	}
}

// add_scatter_sized — облако точек с заданным радиусом маркера.
pub fn (mut p PlotView) add_scatter_sized(points []PlotPoint, color Color, marker_size f32) {
	p.series << PlotSeries{
		kind:       .scatter
		points:     points.clone()
		color:      color
		point_size: marker_size
	}
}

// Convenience: build points from parallel xs/ys arrays.
pub fn make_points(xs []f32, ys []f32) []PlotPoint {
	n := if xs.len < ys.len { xs.len } else { ys.len }
	mut out := []PlotPoint{cap: n}
	for i in 0 .. n {
		out << PlotPoint{xs[i], ys[i]}
	}
	return out
}

// Convenience: build points from ys only (x = 0, 1, 2, ...).
pub fn make_points_y(ys []f32) []PlotPoint {
	mut out := []PlotPoint{cap: ys.len}
	for i, y in ys {
		out << PlotPoint{f32(i), y}
	}
	return out
}

// Auto-fit viewport to encompass all points in all series.
// fit_to_data подгоняет вид под все точки серий points/scatter с запасом 5% с каждой
// стороны (функции игнорируются, у них нет конечного набора). Точки с NaN/Inf по Y
// пропускаются (по X проверки нет). Нет данных — вид не меняется.
pub fn (mut p PlotView) fit_to_data() {
	mut has_data := false
	mut xmin := f32(0)
	mut xmax := f32(0)
	mut ymin := f32(0)
	mut ymax := f32(0)
	for s in p.series {
		if s.kind == .function {
			continue
		}
		for pt in s.points {
			if math.is_nan(f64(pt.y)) || math.is_inf(f64(pt.y), 0) {
				continue
			}
			if !has_data {
				xmin = pt.x
				xmax = pt.x
				ymin = pt.y
				ymax = pt.y
				has_data = true
			} else {
				if pt.x < xmin {
					xmin = pt.x
				}
				if pt.x > xmax {
					xmax = pt.x
				}
				if pt.y < ymin {
					ymin = pt.y
				}
				if pt.y > ymax {
					ymax = pt.y
				}
			}
		}
	}
	if !has_data {
		return
	}
	// Add 5% padding
	dx := max_f32(xmax - xmin, 0.001)
	dy := max_f32(ymax - ymin, 0.001)
	p.set_range(xmin - dx * 0.05, xmax + dx * 0.05, ymin - dy * 0.05, ymax + dy * 0.05)
}

// set_range задаёт видимую область по границам. Ось, у которой max <= min, не меняется;
// размер обрезается до [plot_min_span, plot_max_span].
pub fn (mut p PlotView) set_range(xmin f32, xmax f32, ymin f32, ymax f32) {
	if xmax > xmin {
		p.view_x = xmin
		p.view_w = clamp_f32(xmax - xmin, plot_min_span, plot_max_span)
	}
	if ymax > ymin {
		p.view_y = ymin
		p.view_h = clamp_f32(ymax - ymin, plot_min_span, plot_max_span)
	}
}

// get_range возвращает (xmin, xmax, ymin, ymax) текущей видимой области.
pub fn (p &PlotView) get_range() (f32, f32, f32, f32) {
	return p.view_x, p.view_x + p.view_w, p.view_y, p.view_y + p.view_h
}

// reset_view возвращает вид по умолчанию (x -10..10, y -5..5).
pub fn (mut p PlotView) reset_view() {
	p.view_x = -10.0
	p.view_y = -5.0
	p.view_w = 20.0
	p.view_h = 10.0
}

// Сеттеры/геттеры цветов. Цвет с a == 0 означает «взять из темы» (eff_* ниже).
// ─── Color setters ─────────────────────────────────────

pub fn (mut p PlotView) set_bg_color(c Color) {
	p.bg_color = c
}

pub fn (mut p PlotView) set_axis_color(c Color) {
	p.axis_color = c
}

pub fn (mut p PlotView) set_grid_color(major Color, minor Color) {
	p.grid_major_color = major
	p.grid_minor_color = minor
}

pub fn (mut p PlotView) set_grid_major_color(c Color) {
	p.grid_major_color = c
}

pub fn (mut p PlotView) set_grid_minor_color(c Color) {
	p.grid_minor_color = c
}

pub fn (mut p PlotView) set_label_color(c Color) {
	p.label_color = c
}

pub fn (mut p PlotView) set_border_color(c Color) {
	p.border_color = c
}

pub fn (p &PlotView) get_bg_color() Color {
	return p.bg_color
}

pub fn (p &PlotView) get_axis_color() Color {
	return p.axis_color
}

pub fn (p &PlotView) get_grid_major_color() Color {
	return p.grid_major_color
}

pub fn (p &PlotView) get_grid_minor_color() Color {
	return p.grid_minor_color
}

pub fn (p &PlotView) get_label_color() Color {
	return p.label_color
}

pub fn (p &PlotView) get_border_color() Color {
	return p.border_color
}

// ─── Effective colors ──────────────────────────────────

// Эффективные цвета: свой цвет виджета (a > 0), иначе цвет plot_* темы (если задан), иначе подходящий общий цвет темы.
// ─── Effective colors (theme-aware) ────────────────────

fn (p &PlotView) eff_bg(ctx &RenderContext) Color {
	if p.bg_color.a > 0 {
		return p.bg_color
	}
	if ctx.theme.plot_bg.a > 0 {
		return ctx.theme.plot_bg
	}
	return ctx.theme.input_bg
}

fn (p &PlotView) eff_axis(ctx &RenderContext) Color {
	if p.axis_color.a > 0 {
		return p.axis_color
	}
	if ctx.theme.plot_axis.a > 0 {
		return ctx.theme.plot_axis
	}
	return ctx.theme.text_primary
}

fn (p &PlotView) eff_grid_major(ctx &RenderContext) Color {
	if p.grid_major_color.a > 0 {
		return p.grid_major_color
	}
	if ctx.theme.plot_grid_major.a > 0 {
		return ctx.theme.plot_grid_major
	}
	return ctx.theme.border
}

fn (p &PlotView) eff_grid_minor(ctx &RenderContext) Color {
	if p.grid_minor_color.a > 0 {
		return p.grid_minor_color
	}
	if ctx.theme.plot_grid_minor.a > 0 {
		return ctx.theme.plot_grid_minor
	}
	return ctx.theme.border.with_alpha(50)
}

fn (p &PlotView) eff_label(ctx &RenderContext) Color {
	if p.label_color.a > 0 {
		return p.label_color
	}
	if ctx.theme.plot_label.a > 0 {
		return ctx.theme.plot_label
	}
	return ctx.theme.text_secondary
}

fn (p &PlotView) eff_border(ctx &RenderContext) Color {
	if p.border_color.a > 0 {
		return p.border_color
	}
	if ctx.theme.plot_border.a > 0 {
		return ctx.theme.plot_border
	}
	return ctx.theme.input_border
}

// ─── Geometry ──────────────────────────────────────────

// plot_rect — область самого графика внутри bounds: слева и снизу поля под подписи
// осей (если show_labels), справа/снизу место под полосы прокрутки; минимум 20x20.
fn (p &PlotView) plot_rect() Rect {
	sbw := if p.show_scrollbars { plot_sb_w } else { f32(0) }
	pad_l := if p.show_labels { plot_axis_pad_l } else { f32(6) }
	pad_b := if p.show_labels { plot_axis_pad_b } else { f32(6) }
	return Rect{
		x: p.bounds.x + pad_l
		y: p.bounds.y + 6
		w: max_f32(p.bounds.w - pad_l - sbw - 6, 20)
		h: max_f32(p.bounds.h - pad_b - sbw - 6, 20)
	}
}

// px/py переводят координаты данных в экранные внутри plot_rect (Y инвертируется: экран растёт вниз); plot_x/plot_y делают обратное преобразование.
fn (p &PlotView) px(x f32, pr Rect) f32 {
	return pr.x + ((x - p.view_x) / p.view_w) * pr.w
}

fn (p &PlotView) py(y f32, pr Rect) f32 {
	return pr.y + pr.h - ((y - p.view_y) / p.view_h) * pr.h
}

fn (p &PlotView) plot_x(sx f32, pr Rect) f32 {
	return p.view_x + ((sx - pr.x) / pr.w) * p.view_w
}

fn (p &PlotView) plot_y(sy f32, pr Rect) f32 {
	return p.view_y + ((pr.y + pr.h - sy) / pr.h) * p.view_h
}

// ─── Nice grid step ───────────────────────────────────

// nice_step подбирает «красивый» шаг сетки (1, 2, 5 или 10 · 10^n) так, чтобы на
// диапазоне range было примерно target_count делений. Берётся грубый шаг
// range/target_count, раскладывается на мантиссу и степень десяти, мантисса
// округляется до ближайшего из 1/2/5/10 по порогам 1.5/3/7.
fn nice_step(range f32, target_count int) f32 {
	if range <= 0 || target_count <= 0 {
		return 1.0
	}
	rough := range / f32(target_count)
	exp := f32(math.floor(f64(math.log10(f64(rough)))))
	pow10 := f32(math.powf(10.0, exp))
	frac := rough / pow10
	nice := if frac < 1.5 {
		f32(1.0)
	} else if frac < 3.0 {
		f32(2.0)
	} else if frac < 7.0 {
		f32(5.0)
	} else {
		f32(10.0)
	}
	return nice * pow10
}

// format_tick форматирует подпись деления: значения, близкие к нулю (меньше 0.1% шага), дают '0'; для шага >= 1 — целое с округлением; для дробного шага — столько знаков, сколько нужно, чтобы различались деления (до 6).
fn format_tick(v f32, step f32) string {
	if abs_f32(v) < step * 0.001 {
		return '0'
	}
	if step >= 1.0 {
		if v >= 0 {
			return '${int(v + 0.5)}'
		}
		return '${int(v - 0.5)}'
	}
	mut decimals := 0
	mut s := step
	for s < 1.0 && decimals < 6 {
		s *= 10
		decimals++
	}
	return slider_format_f32(v, decimals)
}

// ─── Virtual bounds (for scrollbars) ───────────────────

// virtual_bounds возвращает границы «всего мира» для полос прокрутки: ±plot_virtual_range,
// расширенные, если вид вышел за них (так ползунок всегда в пределах дорожки).
fn (p &PlotView) virtual_bounds() (f32, f32, f32, f32) {
	mut xmin := f32(-plot_virtual_range)
	mut xmax := f32(plot_virtual_range)
	mut ymin := f32(-plot_virtual_range)
	mut ymax := f32(plot_virtual_range)
	if p.view_x < xmin {
		xmin = p.view_x
	}
	if p.view_x + p.view_w > xmax {
		xmax = p.view_x + p.view_w
	}
	if p.view_y < ymin {
		ymin = p.view_y
	}
	if p.view_y + p.view_h > ymax {
		ymax = p.view_y + p.view_h
	}
	return xmin, xmax, ymin, ymax
}

// hsb_rect / vsb_rect — дорожки горизонтальной и вертикальной полос прокрутки (пустой Rect, если show_scrollbars = false).
fn (p &PlotView) hsb_rect() Rect {
	if !p.show_scrollbars {
		return Rect{}
	}
	pr := p.plot_rect()
	return Rect{pr.x, p.bounds.y + p.bounds.h - plot_sb_w - 3, pr.w, plot_sb_w}
}

fn (p &PlotView) vsb_rect() Rect {
	if !p.show_scrollbars {
		return Rect{}
	}
	pr := p.plot_rect()
	return Rect{p.bounds.x + p.bounds.w - plot_sb_w - 3, pr.y, plot_sb_w, pr.h}
}

// hsb_thumb_rect / vsb_thumb_rect — ползунки: длина пропорциональна доле видимой области в «мире» (не короче 24 px), положение — по view_x (для вертикальной — по ВЕРХНЕЙ границе вида, потому что вверху дорожки ymax). Пустой Rect, если вид не меньше «мира».
fn (p &PlotView) hsb_thumb_rect() Rect {
	track := p.hsb_rect()
	if track.w <= 0 {
		return Rect{}
	}
	xmin, xmax, _, _ := p.virtual_bounds()
	vrange := xmax - xmin
	if vrange <= p.view_w {
		return Rect{}
	}
	thumb_w := max_f32(24, track.w * (p.view_w / vrange))
	ratio := clamp_f32((p.view_x - xmin) / (vrange - p.view_w), 0, 1)
	return Rect{
		x: track.x + ratio * (track.w - thumb_w)
		y: track.y + 2
		w: thumb_w
		h: track.h - 4
	}
}

fn (p &PlotView) vsb_thumb_rect() Rect {
	track := p.vsb_rect()
	if track.h <= 0 {
		return Rect{}
	}
	_, _, ymin, ymax := p.virtual_bounds()
	vrange := ymax - ymin
	if vrange <= p.view_h {
		return Rect{}
	}
	thumb_h := max_f32(24, track.h * (p.view_h / vrange))
	view_top := p.view_y + p.view_h
	ratio := clamp_f32((ymax - view_top) / (vrange - p.view_h), 0, 1)
	return Rect{
		x: track.x + 2
		y: track.y + ratio * (track.h - thumb_h)
		w: track.w - 4
		h: thumb_h
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw: фон и рамка, затем в клипе plot_rect — сетка, оси и все видимые серии; вне клипа — подписи осей и полосы прокрутки.
pub fn (mut p PlotView) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(p.enabled)
	if !p.visible {
		return
	}
	if !ctx.is_in_clip(p.bounds) {
		return
	}

	defer {
		if !en {
			ctx.draw_disabled_veil(p.bounds, ctx.theme.border_radius)
		}
	}
	rad := ctx.theme.border_radius
	ctx.fill_rounded_rect(p.bounds, p.eff_bg(ctx), rad)
	ctx.draw_rounded_rect(p.bounds, p.eff_border(ctx), rad)

	pr := p.plot_rect()
	if pr.w < 20 || pr.h < 20 {
		return
	}

	ctx.push_clip(pr)

	if p.show_grid {
		p.draw_grid(pr, mut ctx)
	}
	if p.show_axes {
		p.draw_axes(pr, mut ctx)
	}

	for s in p.series {
		if !s.visible {
			continue
		}
		match s.kind {
			.function {
				if unsafe { s.func != nil } {
					p.draw_series(s, pr, mut ctx)
				}
			}
			.points, .scatter {
				if s.points.len > 0 {
					p.draw_series(s, pr, mut ctx)
				}
			}
		}
	}

	if p.show_legend {
		p.draw_legend(pr, mut ctx)
	}

	ctx.pop_clip()

	if p.show_labels {
		p.draw_labels(pr, mut ctx)
	}
	if p.show_scrollbars {
		p.draw_scrollbars(mut ctx)
	}
}

// draw_legend рисует легенду в правом верхнем углу области графика: для каждой видимой
// серии с именем - образец цвета и имя. Нет ни одной именованной серии - ничего не
// рисуется. Фон - цвет фона графика, рамка - цвет рамки виджета.
fn (p &PlotView) draw_legend(pr Rect, mut ctx RenderContext) {
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	mut names := []string{}
	mut colors := []Color{}
	mut max_w := f32(0)
	for s in p.series {
		if !s.visible || s.name.len == 0 {
			continue
		}
		names << s.name
		colors << s.color
		max_w = max_f32(max_w, ctx.measure_text_with_font(s.name, font).x)
	}
	if names.len == 0 {
		return
	}
	pad := f32(6)
	swatch := f32(14)
	row_h := fh + 4
	box := Rect{
		x: pr.x + pr.w - (pad * 3 + swatch + max_w) - 8
		y: pr.y + 8
		w: pad * 3 + swatch + max_w
		h: pad * 2 + row_h * f32(names.len)
	}
	ctx.fill_rounded_rect(box, p.eff_bg(ctx).with_alpha(230), 4)
	ctx.draw_rounded_rect(box, p.eff_border(ctx), 4)
	for i, name in names {
		row_y := box.y + pad + row_h * f32(i)
		ctx.fill_rect(Rect{box.x + pad, row_y + (row_h - 3) * 0.5, swatch, 3}, colors[i])
		ctx.draw_text_with_font(name, box.x + pad * 2 + swatch, row_y + (row_h - fh) * 0.5,
			p.eff_label(ctx), font)
	}
}

// draw_grid рисует сетку: основные линии через nice_step (≈10 по X, ≈8 по Y) и по 4
// промежуточные между ними (шаг/5). Линии привязываются к сетке ФИЗИЧЕСКИХ пикселей
// и имеют толщину в один физический пиксель (pw), иначе на дробном ui_scale линии
// получались бы разной толщины.
fn (p &PlotView) draw_grid(pr Rect, mut ctx RenderContext) {
	gc_major := p.eff_grid_major(ctx)
	gc_minor := p.eff_grid_minor(ctx)

	step_x := nice_step(p.view_w, 10)
	step_y := nice_step(p.view_h, 8)
	minor_x := step_x / 5.0
	minor_y := step_y / 5.0

	// One physical pixel expressed in logical units — keeps grid lines
	// visually uniform at fractional ui_scale (e.g. 1.25).
	s := ctx.dpi_scale * ctx.ui_scale
	pw := if s > 0 { f32(1.0) / s } else { f32(1.0) }

	// Vertical lines
	x_start := f32(math.floor(f64(p.view_x / step_x))) * step_x
	mut x := x_start
	for x <= p.view_x + p.view_w + step_x * 0.5 {
		sx := p.px(x, pr)
		if sx >= pr.x && sx <= pr.x + pr.w {
			snx := if s > 0 { f32(math.round(f64(sx) * f64(s))) / s } else { sx }
			ctx.fill_rect(Rect{snx, pr.y, pw, pr.h}, gc_major)
		}
		if p.show_minor_grid && minor_x > 0 {
			for i in 1 .. 5 {
				mx := x + minor_x * f32(i)
				smx := p.px(mx, pr)
				if smx >= pr.x && smx <= pr.x + pr.w {
					snx := if s > 0 { f32(math.round(f64(smx) * f64(s))) / s } else { smx }
					ctx.fill_rect(Rect{snx, pr.y, pw, pr.h}, gc_minor)
				}
			}
		}
		x += step_x
	}

	// Horizontal lines
	y_start := f32(math.floor(f64(p.view_y / step_y))) * step_y
	mut y := y_start
	for y <= p.view_y + p.view_h + step_y * 0.5 {
		sy := p.py(y, pr)
		if sy >= pr.y && sy <= pr.y + pr.h {
			sny := if s > 0 { f32(math.round(f64(sy) * f64(s))) / s } else { sy }
			ctx.fill_rect(Rect{pr.x, sny, pr.w, pw}, gc_major)
		}
		if p.show_minor_grid && minor_y > 0 {
			for i in 1 .. 5 {
				my := y + minor_y * f32(i)
				smy := p.py(my, pr)
				if smy >= pr.y && smy <= pr.y + pr.h {
					sny := if s > 0 { f32(math.round(f64(smy) * f64(s))) / s } else { smy }
					ctx.fill_rect(Rect{pr.x, sny, pr.w, pw}, gc_minor)
				}
			}
		}
		y += step_y
	}
}

// draw_axes рисует линии осей (y = 0 и x = 0), если они попадают в видимую область; толщина 2 физических пикселя.
fn (p &PlotView) draw_axes(pr Rect, mut ctx RenderContext) {
	ac := p.eff_axis(ctx)
	s := ctx.dpi_scale * ctx.ui_scale
	pw := if s > 0 { f32(1.0) / s } else { f32(1.0) }
	// X axis (y = 0)
	if p.view_y <= 0 && p.view_y + p.view_h >= 0 {
		sy := p.py(0, pr)
		sny := if s > 0 { f32(math.round(f64(sy) * f64(s))) / s } else { sy }
		ctx.fill_rect(Rect{pr.x, sny - pw, pr.w, pw * 2}, ac)
	}
	// Y axis (x = 0)
	if p.view_x <= 0 && p.view_x + p.view_w >= 0 {
		sx := p.px(0, pr)
		snx := if s > 0 { f32(math.round(f64(sx) * f64(s))) / s } else { sx }
		ctx.fill_rect(Rect{snx - pw, pr.y, pw * 2, pr.h}, ac)
	}
}

// draw_series выбирает способ рисования по виду серии.
fn (p &PlotView) draw_series(s PlotSeries, pr Rect, mut ctx RenderContext) {
	match s.kind {
		.function { p.draw_series_function(s, pr, mut ctx) }
		.points { p.draw_series_points(s, pr, mut ctx) }
		.scatter { p.draw_series_scatter(s, pr, mut ctx) }
	}
}

// draw_series_function сэмплирует f по одному отсчёту на пиксель ширины и рисует ломаную.
// Значения NaN/Inf и точки дальше 10 высот графика по вертикали разрывают линию:
// накопленный участок дорисовывается, новый начинается заново (иначе SDL получил бы
// огромные координаты у асимптот, вроде tan). Толщина <= 4 — быстрый путь:
// один вызов SDL_RenderLines на участок (render_lines_thick); больше — по отрезкам.
fn (p &PlotView) draw_series_function(s PlotSeries, pr Rect, mut ctx RenderContext) {
	if unsafe { s.func == nil } {
		return
	}

	// 1 sample per pixel is enough for a smooth curve
	samples := int(pr.w) + 1
	if samples < 2 {
		return
	}

	dx := p.view_w / f32(samples)
	thick := s.thickness
	y_margin := pr.h * 10.0

	if thick <= 4.0 {
		// Fast path: batch all points, use multi-pass for thickness
		mut pts := []C.SDL_FPoint{cap: samples + 1}
		C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)
		C.SDL_SetRenderDrawColor(ctx.renderer, s.color.r, s.color.g, s.color.b, s.color.a)

		for i in 0 .. samples + 1 {
			x := p.view_x + f32(i) * dx
			y := s.func(x)

			if math.is_nan(f64(y)) || math.is_inf(f64(y), 0) {
				if pts.len >= 2 {
					p.render_lines_thick(ctx.renderer, pts, thick)
				}
				pts.clear()
				continue
			}

			sy := p.py(y, pr)
			if sy < pr.y - y_margin || sy > pr.y + pr.h + y_margin {
				if pts.len >= 2 {
					p.render_lines_thick(ctx.renderer, pts, thick)
				}
				pts.clear()
				continue
			}

			pts << C.SDL_FPoint{p.px(x, pr), sy}
		}
		if pts.len >= 2 {
			p.render_lines_thick(ctx.renderer, pts, thick)
		}
	} else {
		// Thick lines: fallback to per-segment (rarely used)
		half_thick := thick * 0.5
		mut prev_sx := f32(0)
		mut prev_sy := f32(0)
		mut prev_valid := false

		for i in 0 .. samples + 1 {
			x := p.view_x + f32(i) * dx
			y := s.func(x)

			if math.is_nan(f64(y)) || math.is_inf(f64(y), 0) {
				prev_valid = false
				continue
			}

			sx := p.px(x, pr)
			sy := p.py(y, pr)
			valid := sy >= pr.y - y_margin && sy <= pr.y + pr.h + y_margin

			if prev_valid && valid {
				ctx.draw_line_thick(prev_sx, prev_sy, sx, sy, u8(thick + 0.5), s.color)
				ctx.fill_circle(sx, sy, half_thick, s.color)
			}

			prev_sx = sx
			prev_sy = sy
			prev_valid = valid
		}
	}
}

// render_lines_thick draws a polyline with integer pixel thickness using
// offset passes of SDL_RenderLines — no per-segment SDL calls.
fn (p &PlotView) render_lines_thick(renderer voidptr, pts []C.SDL_FPoint, thick f32) {
	passes := int(thick + 0.5)
	half := f32(passes - 1) * 0.5
	if passes <= 1 {
		C.SDL_RenderLines(renderer, pts.data, pts.len)
		return
	}
	mut shifted := []C.SDL_FPoint{len: pts.len}
	for dy in 0 .. passes {
		offset := f32(dy) - half
		for i, pt in pts {
			shifted[i] = C.SDL_FPoint{pt.x, pt.y + offset}
		}
		C.SDL_RenderLines(renderer, shifted.data, shifted.len)
	}
	for dx in 0 .. passes {
		offset := f32(dx) - half
		for i, pt in pts {
			shifted[i] = C.SDL_FPoint{pt.x + offset, pt.y}
		}
		C.SDL_RenderLines(renderer, shifted.data, shifted.len)
	}
}

// draw_series_points рисует ломаную по точкам (точки с NaN/Inf и далеко за областью разрывают линию) и поверх — маркеры, если show_markers.
fn (p &PlotView) draw_series_points(s PlotSeries, pr Rect, mut ctx RenderContext) {
	if s.points.len == 0 {
		return
	}

	thick := s.thickness
	half_thick := thick * 0.5
	y_margin := pr.h * 10.0
	x_margin := pr.w * 10.0

	mut prev_sx := f32(0)
	mut prev_sy := f32(0)
	mut prev_valid := false

	for pt in s.points {
		if math.is_nan(f64(pt.y)) || math.is_inf(f64(pt.y), 0) || math.is_nan(f64(pt.x))
			|| math.is_inf(f64(pt.x), 0) {
			prev_valid = false
			continue
		}
		sx := p.px(pt.x, pr)
		sy := p.py(pt.y, pr)
		valid := sy >= pr.y - y_margin && sy <= pr.y + pr.h + y_margin && sx >= pr.x - x_margin
			&& sx <= pr.x + pr.w + x_margin

		if prev_valid && valid {
			if thick <= 1.0 {
				ctx.draw_line(prev_sx, prev_sy, sx, sy, s.color)
			} else {
				ctx.draw_line_thick(prev_sx, prev_sy, sx, sy, u8(thick + 0.5), s.color)
				ctx.fill_circle(sx, sy, half_thick, s.color)
			}
		}
		prev_sx = sx
		prev_sy = sy
		prev_valid = valid
	}

	// Draw markers on top of the line
	if s.show_markers {
		marker_r := if s.point_size > 0 { s.point_size } else { f32(4) }
		for pt in s.points {
			if math.is_nan(f64(pt.y)) || math.is_inf(f64(pt.y), 0) {
				continue
			}
			sx := p.px(pt.x, pr)
			sy := p.py(pt.y, pr)
			if sy < pr.y - marker_r || sy > pr.y + pr.h + marker_r {
				continue
			}
			if sx < pr.x - marker_r || sx > pr.x + pr.w + marker_r {
				continue
			}
			ctx.fill_circle(sx, sy, marker_r, s.color)
		}
	}
}

// draw_series_scatter рисует только маркеры (радиус point_size, по умолчанию 3); точки целиком за пределами области пропускаются.
fn (p &PlotView) draw_series_scatter(s PlotSeries, pr Rect, mut ctx RenderContext) {
	if s.points.len == 0 {
		return
	}
	marker_r := if s.point_size > 0 { s.point_size } else { f32(3) }

	for pt in s.points {
		if math.is_nan(f64(pt.y)) || math.is_inf(f64(pt.y), 0) || math.is_nan(f64(pt.x))
			|| math.is_inf(f64(pt.x), 0) {
			continue
		}
		sx := p.px(pt.x, pr)
		sy := p.py(pt.y, pr)
		if sy < pr.y - marker_r || sy > pr.y + pr.h + marker_r {
			continue
		}
		if sx < pr.x - marker_r || sx > pr.x + pr.w + marker_r {
			continue
		}
		ctx.fill_circle(sx, sy, marker_r, s.color)
	}
}

// draw_labels рисует подписи делений осей по тем же nice_step, что и сетка: по X — под графиком по центру деления, по Y — слева от графика, по вертикали по центру линии.
fn (p &PlotView) draw_labels(pr Rect, mut ctx RenderContext) {
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	lc := p.eff_label(ctx)

	step_x := nice_step(p.view_w, 10)
	step_y := nice_step(p.view_h, 8)

	// X labels below plot
	x_start := f32(math.floor(f64(p.view_x / step_x))) * step_x
	mut x := x_start
	for x <= p.view_x + p.view_w + step_x * 0.5 {
		sx := p.px(x, pr)
		if sx >= pr.x - 20 && sx <= pr.x + pr.w + 20 {
			lbl := format_tick(x, step_x)
			lw := ctx.measure_text_with_font(lbl, font).x
			lx := sx - lw * 0.5
			ly := pr.y + pr.h + 6
			ctx.draw_text_with_font(lbl, lx, ly, lc, font)
		}
		x += step_x
	}

	// Y labels left of plot
	y_start := f32(math.floor(f64(p.view_y / step_y))) * step_y
	mut y := y_start
	for y <= p.view_y + p.view_h + step_y * 0.5 {
		sy := p.py(y, pr)
		if sy >= pr.y - 10 && sy <= pr.y + pr.h + 10 {
			lbl := format_tick(y, step_y)
			lw := ctx.measure_text_with_font(lbl, font).x
			lx := pr.x - lw - 8
			ly := sy - fh * 0.5
			ctx.draw_text_with_font(lbl, lx, ly, lc, font)
		}
		y += step_y
	}
}

// draw_scrollbars рисует дорожки и ползунки (цвет зависит от перетаскивания/наведения).
fn (p &PlotView) draw_scrollbars(mut ctx RenderContext) {
	// Horizontal
	htrack := p.hsb_rect()
	if htrack.w > 0 {
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(htrack, ctx.theme.scrollbar_bg, 3)
		}
		hthumb := p.hsb_thumb_rect()
		if hthumb.w > 0 {
			hc := if p.hsb_dragging {
				ctx.theme.scrollbar_drag
			} else if p.hsb_hovered {
				ctx.theme.scrollbar_hover
			} else {
				ctx.theme.scrollbar_thumb
			}
			ctx.fill_rounded_rect(hthumb, hc, 3)
		}
	}

	// Vertical
	vtrack := p.vsb_rect()
	if vtrack.h > 0 {
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(vtrack, ctx.theme.scrollbar_bg, 3)
		}
		vthumb := p.vsb_thumb_rect()
		if vthumb.h > 0 {
			vc := if p.vsb_dragging {
				ctx.theme.scrollbar_drag
			} else if p.vsb_hovered {
				ctx.theme.scrollbar_hover
			} else {
				ctx.theme.scrollbar_thumb
			}
			ctx.fill_rounded_rect(vthumb, vc, 3)
		}
	}
}

// ─── Zoom centered on a screen point ───────────────────

// zoom_at масштабирует вид в factor раз (>1 — приблизить) так, чтобы точка данных под
// курсором (screen_x, screen_y) осталась на месте: сначала запоминается её координата и
// относительное положение в области (fx, fy), затем новый размер и новое начало
// подбираются от неё.
fn (mut p PlotView) zoom_at(screen_x f32, screen_y f32, factor f32) {
	pr := p.plot_rect()
	if pr.w <= 0 || pr.h <= 0 {
		return
	}

	cx := p.plot_x(screen_x, pr)
	cy := p.plot_y(screen_y, pr)

	new_w := clamp_f32(p.view_w / factor, plot_min_span, plot_max_span)
	new_h := clamp_f32(p.view_h / factor, plot_min_span, plot_max_span)

	fx := (screen_x - pr.x) / pr.w
	fy := (pr.y + pr.h - screen_y) / pr.h

	p.view_w = new_w
	p.view_h = new_h
	p.view_x = cx - fx * new_w
	p.view_y = cy - fy * new_h
}

// ─── Events ────────────────────────────────────────────

// handle_event. Состояния обрабатываются по приоритету: идущее панорамирование и
// перетаскивание полос поглощают ВСЕ события до отпускания левой кнопки; иначе —
// наведение, нажатие (ползунок -> клик по дорожке = прыжок на 90% вида -> начало
// панорамирования в области графика), колесо (Ctrl — зум к курсору, Shift —
// горизонтальная прокрутка, иначе вертикальная; отключается полем wheel) и клавиши
// при наведении (Home и Ctrl+0 — сброс, Ctrl+'+'/'-' — зум к центру).
pub fn (mut p PlotView) handle_event(event &GuiEvent, app &App) bool {
	if !p.visible || !p.enabled {
		return false
	}

	// ── Pan drag in progress ──
	if p.panning {
		match event.typ {
			.mouse_move {
				pr := p.plot_rect()
				if pr.w > 0 && pr.h > 0 {
					dx_px := event.mouse_x - p.pan_start_mx
					dy_px := event.mouse_y - p.pan_start_my
					dx_plot := (dx_px / pr.w) * p.view_w
					dy_plot := (dy_px / pr.h) * p.view_h
					p.view_x = p.pan_start_vx - dx_plot
					p.view_y = p.pan_start_vy + dy_plot // screen Y inverted
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					p.panning = false
					set_cursor(sdl_system_cursor_arrow)
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Horizontal scrollbar drag ──
	if p.hsb_dragging {
		match event.typ {
			.mouse_move {
				track := p.hsb_rect()
				if track.w <= 0 {
					return true
				}
				xmin, xmax, _, _ := p.virtual_bounds()
				vrange := xmax - xmin
				if vrange <= p.view_w {
					return true
				}
				thumb_w := max_f32(24, track.w * (p.view_w / vrange))
				drag_range := track.w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - p.sb_drag_start
				ratio_delta := dx / drag_range
				new_x := p.sb_drag_start_val + ratio_delta * (vrange - p.view_w)
				p.view_x = clamp_f32(new_x, xmin, xmax - p.view_w)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					p.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Vertical scrollbar drag ──
	if p.vsb_dragging {
		match event.typ {
			.mouse_move {
				track := p.vsb_rect()
				if track.h <= 0 {
					return true
				}
				_, _, ymin, ymax := p.virtual_bounds()
				vrange := ymax - ymin
				if vrange <= p.view_h {
					return true
				}
				thumb_h := max_f32(24, track.h * (p.view_h / vrange))
				drag_range := track.h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - p.sb_drag_start
				ratio_delta := dy / drag_range
				// Vertical scrollbar: top = ymax, bottom = ymin
				new_view_top := p.sb_drag_start_val - ratio_delta * (vrange - p.view_h)
				new_y := new_view_top - p.view_h
				p.view_y = clamp_f32(new_y, ymin, ymax - p.view_h)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					p.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			p.hovered = p.bounds.contains(event.mouse_x, event.mouse_y)
			// Scrollbar hover
			if p.show_scrollbars && p.hovered {
				ht := p.hsb_rect()
				vt := p.vsb_rect()
				p.hsb_hovered = ht.w > 0 && ht.contains(event.mouse_x, event.mouse_y)
				p.vsb_hovered = vt.h > 0 && vt.contains(event.mouse_x, event.mouse_y)
			} else {
				p.hsb_hovered = false
				p.vsb_hovered = false
			}
		}
		.mouse_down {
			if event.mouse_btn != .left || !p.hovered {
				return false
			}

			// Try scrollbars first
			if p.show_scrollbars {
				// Horizontal thumb
				hthumb := p.hsb_thumb_rect()
				if hthumb.w > 0 && hthumb.contains(event.mouse_x, event.mouse_y) {
					p.hsb_dragging = true
					p.sb_drag_start = event.mouse_x
					p.sb_drag_start_val = p.view_x
					return true
				}
				// Horizontal track (page jump)
				htrack := p.hsb_rect()
				if htrack.w > 0 && htrack.contains(event.mouse_x, event.mouse_y) {
					if event.mouse_x < hthumb.x {
						p.view_x -= p.view_w * 0.9
					} else {
						p.view_x += p.view_w * 0.9
					}
					xmin, xmax, _, _ := p.virtual_bounds()
					p.view_x = clamp_f32(p.view_x, xmin, xmax - p.view_w)
					return true
				}
				// Vertical thumb
				vthumb := p.vsb_thumb_rect()
				if vthumb.h > 0 && vthumb.contains(event.mouse_x, event.mouse_y) {
					p.vsb_dragging = true
					p.sb_drag_start = event.mouse_y
					p.sb_drag_start_val = p.view_y + p.view_h // view_top
					return true
				}
				// Vertical track (page jump)
				vtrack := p.vsb_rect()
				if vtrack.h > 0 && vtrack.contains(event.mouse_x, event.mouse_y) {
					if event.mouse_y < vthumb.y {
						p.view_y += p.view_h * 0.9
					} else {
						p.view_y -= p.view_h * 0.9
					}
					_, _, ymin, ymax := p.virtual_bounds()
					p.view_y = clamp_f32(p.view_y, ymin, ymax - p.view_h)
					return true
				}
			}

			// Begin pan drag inside plot area
			pr := p.plot_rect()
			if pr.contains(event.mouse_x, event.mouse_y) {
				p.panning = true
				p.pan_start_mx = event.mouse_x
				p.pan_start_my = event.mouse_y
				p.pan_start_vx = p.view_x
				p.pan_start_vy = p.view_y
				set_cursor(sdl_system_cursor_sizeall)
				return true
			}
		}
		.mouse_wheel {
			if !p.wheel {
				return false
			}
			if !p.hovered {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			pr := p.plot_rect()
			if !pr.contains(mx, my) {
				return false
			}

			if event.ctrl() {
				// Zoom centered on cursor
				factor := if event.wheel_y > 0 {
					f32(1.0) + p.zoom_speed
				} else {
					f32(1.0) / (f32(1.0) + p.zoom_speed)
				}
				p.zoom_at(mx, my, factor)
				return true
			}

			if event.shift() {
				// Horizontal scroll
				delta_plot := (p.scroll_speed / pr.w) * p.view_w * event.wheel_y
				p.view_x -= delta_plot
				xmin, xmax, _, _ := p.virtual_bounds()
				p.view_x = clamp_f32(p.view_x, xmin, xmax - p.view_w)
				return true
			}

			// Vertical scroll (wheel up → view moves up in plot space)
			delta_plot := (p.scroll_speed / pr.h) * p.view_h * event.wheel_y
			p.view_y += delta_plot
			_, _, ymin, ymax := p.virtual_bounds()
			p.view_y = clamp_f32(p.view_y, ymin, ymax - p.view_h)
			return true
		}
		.key_down {
			if !p.hovered {
				return false
			}
			match event.keycode {
				sdl_k_home {
					p.reset_view()
					return true
				}
				int(`+`), int(`=`) {
					if event.ctrl() {
						pr := p.plot_rect()
						p.zoom_at(pr.x + pr.w * 0.5, pr.y + pr.h * 0.5, 1.0 + p.zoom_speed)
						return true
					}
				}
				int(`-`) {
					if event.ctrl() {
						pr := p.plot_rect()
						p.zoom_at(pr.x + pr.w * 0.5, pr.y + pr.h * 0.5, 1.0 / (1.0 + p.zoom_speed))
						return true
					}
				}
				int(`0`) {
					if event.ctrl() {
						p.reset_view()
						return true
					}
				}
				else {}
			}
		}
		else {}
	}

	return false
}

// ─── CSV loading ──────────────────────────────────────

// Parse CSV text into [](x, y) points.
//
// Parameters:
//   text         — raw CSV content
//   delimiter    — field separator (e.g. ",", ";", "\t", "|", " ").
//                  If empty, auto-detected among , ; \t | from the first data line.
//   has_header   — if true, the first non-empty line is skipped
//   x_col, y_col — zero-based column indices for X and Y
//
// Behavior:
//   - blank lines are skipped
//   - lines starting with '#' are treated as comments
//   - rows where X or Y cannot be parsed as f32 are skipped silently
pub fn parse_csv_points(text string, delimiter string, has_header bool, x_col int, y_col int) []PlotPoint {
	if text.len == 0 {
		return []
	}
	normalized := text.replace('\r\n', '\n').replace('\r', '\n')
	raw_lines := normalized.split('\n')

	// Collect non-empty, non-comment lines
	mut lines := []string{cap: raw_lines.len}
	for rl in raw_lines {
		l := rl.trim_space()
		if l.len == 0 || l.starts_with('#') {
			continue
		}
		lines << l
	}
	if lines.len == 0 {
		return []
	}

	// Auto-detect delimiter if not given
	delim := if delimiter.len > 0 {
		delimiter
	} else {
		csv_detect_delimiter(lines[0])
	}

	mut out := []PlotPoint{cap: lines.len}
	mut start := 0
	if has_header && lines.len > 0 {
		start = 1
	}
	for i in start .. lines.len {
		cols := lines[i].split(delim)
		if x_col < 0 || y_col < 0 || x_col >= cols.len || y_col >= cols.len {
			continue
		}
		xs := cols[x_col].trim_space()
		ys := cols[y_col].trim_space()
		if xs.len == 0 || ys.len == 0 {
			continue
		}
		// Accept both '.' and ',' as decimal separator when the delimiter is not ','
		fx := csv_parse_number(xs, delim)
		fy := csv_parse_number(ys, delim)
		if math.is_nan(f64(fx)) || math.is_nan(f64(fy)) {
			continue
		}
		out << PlotPoint{fx, fy}
	}
	return out
}

// csv_detect_delimiter выбирает из , ; \t | тот символ, которого больше в первой строке; нет ни одного — пробел.
fn csv_detect_delimiter(line string) string {
	candidates := [',', ';', '\t', '|']
	mut best := ','
	mut best_count := 0
	for c in candidates {
		cnt := line.count(c)
		if cnt > best_count {
			best_count = cnt
			best = c
		}
	}
	if best_count == 0 {
		return ' '
	}
	return best
}

// csv_parse_number разбирает число; если разделитель полей не запятая, запятая считается
// десятичной ('1,5' -> 1.5); пробелы и кавычки по краям снимаются.
// Нечисловое поле (заголовок, «n/a», пусто) даёт NaN, и строка пропускается: раньше
// String.f32() возвращал для него 0, и в серию попадала ложная точка (0, 0).
fn csv_parse_number(s string, delim string) f32 {
	// If ',' is not the field separator, allow it as decimal separator
	t := (if delim != ',' { s.replace(',', '.') } else { s }).trim_space().trim('"')
	if t.len == 0 {
		return f32(math.nan())
	}
	v := strconv.atof64(t) or { return f32(math.nan()) }
	return f32(v)
}

// Load a connected-line series from a CSV file.
// add_points_from_csv читает CSV-файл и добавляет ломаную; возвращает число прочитанных точек. Ошибка чтения файла пробрасывается (!int).
pub fn (mut p PlotView) add_points_from_csv(path string, delimiter string, has_header bool, x_col int, y_col int, color Color) !int {
	text := os.read_file(path)!
	pts := parse_csv_points(text, delimiter, has_header, x_col, y_col)
	p.add_points(pts, color)
	return pts.len
}

// Load a connected-line series with a legend name.
pub fn (mut p PlotView) add_points_from_csv_named(path string, name string, delimiter string, has_header bool, x_col int, y_col int, color Color) !int {
	text := os.read_file(path)!
	pts := parse_csv_points(text, delimiter, has_header, x_col, y_col)
	p.add_points_named(name, pts, color)
	return pts.len
}

// Load a scatter series (dots only) from a CSV file.
pub fn (mut p PlotView) add_scatter_from_csv(path string, delimiter string, has_header bool, x_col int, y_col int, color Color, marker_size f32) !int {
	text := os.read_file(path)!
	pts := parse_csv_points(text, delimiter, has_header, x_col, y_col)
	if marker_size > 0 {
		p.add_scatter_sized(pts, color, marker_size)
	} else {
		p.add_scatter(pts, color)
	}
	return pts.len
}
