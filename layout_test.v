module vgui

// Юнит-тесты layout-системы (layout.v + BoxLayout в containers.v).
//
// SDL и шрифты не нужны: RenderContext создаётся пустым, а для
// проверок берутся виджеты, чей размер не зависит от шрифта
// (Icon — строго size×size, Spacer — expanding). Текстовые
// метрики без загруженного шрифта дают 0 и на геометрию
// распределения не влияют.
//
// Запуск: v -enable-globals test vgui/layout_test.v

fn empty_ctx() &RenderContext {
	return &RenderContext{
		screen_width:  800
		screen_height: 600
	}
}

// ─── distribute_main ───────────────────────────────────

fn test_distribute_pure_flex() {
	mut items := [
		LayoutItem{
			flex: 1
			max:  size_unbounded
		},
		LayoutItem{
			flex: 3
			max:  size_unbounded
		},
	]
	distribute_main(mut items, 100)
	assert items[0].result > 24.9 && items[0].result < 25.1
	assert items[1].result > 74.9 && items[1].result < 75.1
}

fn test_distribute_fixed_plus_flex() {
	mut items := [
		LayoutItem{
			base: 40
			min:  40
			max:  40
		},
		LayoutItem{
			flex: 1
			max:  size_unbounded
		},
	]
	distribute_main(mut items, 100)
	assert items[0].result == 40
	assert items[1].result > 59.9 && items[1].result < 60.1
}

fn test_distribute_respects_max() {
	// Ребёнок с потолком 30 не должен забрать свою половину (50):
	// излишек уходит соседу.
	mut items := [
		LayoutItem{
			flex: 1
			max:  30
		},
		LayoutItem{
			flex: 1
			max:  size_unbounded
		},
	]
	distribute_main(mut items, 100)
	assert items[0].result == 30
	assert items[1].result > 69.9 && items[1].result < 70.1
}

fn test_distribute_respects_min() {
	mut items := [
		LayoutItem{
			flex: 1
			min:  80
			max:  size_unbounded
		},
		LayoutItem{
			flex: 1
			max:  size_unbounded
		},
	]
	distribute_main(mut items, 100)
	assert items[0].result == 80
	assert items[1].result > 19.9 && items[1].result < 20.1
}

fn test_distribute_no_flex_keeps_base() {
	// Ни у кого нет веса — раздутое место не делится.
	mut items := [
		LayoutItem{
			base: 20
			max:  size_unbounded
		},
		LayoutItem{
			base: 30
			max:  size_unbounded
		},
	]
	distribute_main(mut items, 500)
	assert items[0].result == 20
	assert items[1].result == 30
}

// ─── Естественный размер + flex ────────────────────────

// Иконка - своего размера (по высоте ряда - по центру, не растягивается:
// фиксированный размер поперёк), flex - весь остаток
fn test_auto_plus_flex() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 300, 50}
	h.box.spacing = 0
	mut a := icon('a')
	a.size = 40
	mut b := create_spacer()
	h.add(a)
	h.add(b, flex: 1.0)
	h.box.layout(ctx)
	assert a.bounds == Rect{0, 5, 40, 40}
	assert b.bounds == Rect{40, 0, 260, 50}
}

fn test_legacy_padding_and_spacing() {
	mut ctx := empty_ctx()
	mut v := create_vbox_fill()
	v.box.bounds = Rect{0, 0, 100, 100}
	v.box.pad = 10
	v.box.spacing = 10
	mut a := create_spacer()
	mut b := create_spacer()
	v.add(a, flex: 1.0)
	v.add(b, flex: 1.0)
	v.box.layout(ctx)
	// inner = 80×80, минус 10 spacing → по 35 на ребёнка
	assert a.bounds == Rect{10, 10, 80, 35}
	assert b.bounds == Rect{10, 55, 80, 35}
}

// ─── add(w): естественный размер по умолчанию ──────────

fn test_add_natural_uses_widget_size() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 300, 40}
	h.box.spacing = 0
	mut ic := icon('star')
	ic.size = 24
	rest := icon('rest')
	h.add(ic)
	h.add(rest, flex: 1.0)
	h.box.layout(ctx)
	// Иконка получила ровно свои 24 px, остальное — соседу.
	assert ic.bounds.w == 24
	assert rest.bounds.x == 24
	assert rest.bounds.w == 276
}

fn test_auto_children_do_not_shrink_below_min() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 20, 40} // места меньше, чем нужно
	h.box.spacing = 0
	mut ic := icon('star')
	ic.size = 32
	h.add(ic)
	h.box.layout(ctx)
	// Icon объявляет min = max = 32 и не сжимается.
	assert ic.bounds.w == 32
}

// ─── LayoutParams: min/max/flex ───────────────────────

fn test_add_min_max() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 400, 40}
	h.box.spacing = 0
	mut a := icon('a')
	mut b := icon('b')
	h.add(a, flex: 1, max: 50)
	h.add(b, flex: 1)
	h.box.layout(ctx)
	assert a.bounds.w == 50
	assert b.bounds.w == 350
}

fn test_add_natural_with_min() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 400, 40}
	h.box.spacing = 0
	mut ic := icon('a')
	ic.size = 16
	h.add(ic, min: 80)
	h.add(icon('b'), flex: 1.0)
	h.box.layout(ctx)
	// min из LayoutParams сильнее measure().
	assert ic.bounds.w == 80
}

// ─── Поперечная ось ────────────────────────────────────

// Поперёк растягивается то, что может (список); фиксированное поперёк
// (иконка) встаёт в ряду по центру, в столбце - у левого края
fn test_cross_align_stretch_is_default() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 200, 80}
	mut lb := list_box()
	mut ic := icon('a')
	ic.size = 16
	h.add(lb, flex: 1.0)
	h.add(ic)
	h.box.layout(ctx)
	assert lb.bounds.h == 80
	assert ic.bounds.h == 16 && ic.bounds.y == 32
	mut v := create_vbox_fill()
	v.box.bounds = Rect{0, 0, 200, 80}
	mut ic2 := icon('b')
	ic2.size = 16
	v.add(ic2)
	v.box.layout(ctx)
	assert ic2.bounds.x == 0 && ic2.bounds.w == 16
}

fn test_cross_align_center() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 100, 80}
	h.set_cross_align(.center)
	mut ic := icon('a')
	ic.size = 16
	h.add(ic, flex: 1.0)
	h.box.layout(ctx)
	assert ic.bounds.h == 16
	assert ic.bounds.y == 32 // (80 - 16) / 2
}

fn test_cross_align_end_and_per_child_override() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 200, 80}
	h.box.spacing = 0
	h.set_cross_align(.end)
	mut a := icon('a')
	a.size = 20
	mut b := icon('b')
	b.size = 20
	h.add(a, flex: 1.0)
	h.add(b, flex: 1, align: .start)
	h.box.layout(ctx)
	assert a.bounds.y == 60 // 80 - 20, выравнивание контейнера
	assert b.bounds.y == 0 // индивидуальное выравнивание сильнее
}

// ─── measure у контейнеров ─────────────────────────────

fn test_vbox_content_size_sums_children() {
	mut ctx := empty_ctx()
	mut v := create_vbox_fill()
	v.box.spacing = 4
	v.box.pad = 8
	mut a := icon('a')
	a.size = 20
	mut b := icon('b')
	b.size = 30
	v.add(a)
	v.add(b)
	hint := v.measure(ctx)
	// высота: 20 + 4 + 30 + 8*2 = 70; ширина: max(20,30) + 16 = 46
	assert hint.h == 70
	assert hint.w == 46
}

fn test_content_size_counts_flex_children() {
	// Ребёнок с весом при раскладке стартует с нуля, но в
	// измерении содержимого его размер обязан учитываться —
	// иначе fit_to_content схлопнул бы окно.
	mut ctx := empty_ctx()
	mut v := create_vbox_fill()
	v.box.spacing = 0
	v.box.pad = 0
	mut a := icon('a')
	a.size = 40
	v.add(a, flex: 1.0)
	hint := v.measure(ctx)
	assert hint.h == 40
}

fn test_hbox_with_flex_child_is_expanding() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.add(icon('a'), flex: 1.0)
	hint := h.measure(ctx)
	assert hint.h_policy == .expanding
}

fn test_nested_container_measures_through() {
	mut ctx := empty_ctx()
	mut inner := create_hbox_fill()
	inner.box.spacing = 0
	inner.box.pad = 0
	mut a := icon('a')
	a.size = 10
	mut b := icon('b')
	b.size = 10
	inner.add(a)
	inner.add(b)

	mut outer := create_vbox_fill()
	outer.box.spacing = 0
	outer.box.pad = 0
	outer.add(inner)
	hint := outer.measure(ctx)
	assert hint.w == 20 // измерение прошло сквозь вложенный контейнер
}

// ─── measure_widget: запасной путь ─────────────────────

fn test_measure_widget_falls_back_to_bounds() {
	mut ctx := empty_ctx()
	// Notification не реализует Measurable — hint берётся из bounds.
	mut n := notification('test')
	n.bounds = Rect{0, 0, 111, 22}
	hint := measure_widget(n, ctx)
	assert hint.w == 111
	assert hint.h == 22
	assert hint.h_policy == .expanding
	assert !is_measurable(n)
}

fn test_measurable_detection() {
	mut ic := icon('a')
	assert is_measurable(ic)
	mut h := create_hbox_fill()
	assert is_measurable(h)
}

fn test_size_hint_clamped_is_consistent() {
	h := SizeHint{
		w:     10
		h:     10
		min_w: 50
		min_h: 50
		max_w: 20
		max_h: 20
	}.clamped()
	// max поднят до min, значение прижато к границе
	assert h.min_w == 50 && h.max_w == 50 && h.w == 50
	assert h.min_h == 50 && h.max_h == 50 && h.h == 50
}

// Regression: Notification не было в set_widget_bounds, из-за чего
// виджет получал bounds 0x0 и не рисовался (см. PROJECT.md, чек-лист
// «Добавление нового виджета» — запись в set_widget_bounds критична).
fn test_notification_receives_bounds() {
	mut n := &Notification{
		title:   't'
		message: 'm'
	}
	set_widget_bounds(mut n, Rect{
		x: 10
		y: 20
		w: 300
		h: 60
	})
	assert n.bounds.w == 300
	assert n.bounds.h == 60
	// get_widget_bounds — зеркало set_widget_bounds (fallback для measure)
	assert get_widget_bounds(n).w == 300
}

// ─── Растягиваемые по природе: растут от своего размера ──

// Ползунок (политика expanding) без параметров забирает свободное
// место - flex: 1 писать не нужно
fn test_auto_expanding_fills_rest() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.bounds = Rect{0, 0, 400, 40}
	h.box.spacing = 0
	mut ic := icon('a')
	ic.size = 24
	mut sl := slider_horizontal(0, 1, 0.5)
	h.add(ic)
	h.add(sl)
	h.box.layout(ctx)
	assert ic.bounds.w == 24
	assert sl.bounds.w == 376
}

// Два растущих: остаток сверх естественных размеров - поровну;
// места меньше - сжимаются, но не ниже своего min
fn test_auto_expanding_grow_and_shrink_from_base() {
	mut ctx := empty_ctx()
	mut h := create_hbox_fill()
	h.box.spacing = 0
	mut sl := slider_horizontal(0, 1, 0.5) // 160, min 40
	mut pb := progress_bar_linear() // 160, min 40
	pb.thickness = 6
	h.add(sl)
	h.add(pb, flex: 3) // явный вес: от нуля, втрое больше доли
	h.box.bounds = Rect{0, 0, 560, 40}
	h.box.layout(ctx)
	// sl: 160 + 1/4 остатка (560 - 160) = 260; pb: 0 + 3/4 * 400 = 300
	assert sl.bounds.w == 260
	assert pb.bounds.w == 300
	mut h2 := create_hbox_fill()
	h2.box.spacing = 0
	mut a := slider_horizontal(0, 1, 0.5)
	mut b := slider_horizontal(0, 1, 0.5)
	h2.add(a)
	h2.add(b)
	h2.box.bounds = Rect{0, 0, 200, 40}
	h2.box.layout(ctx)
	assert a.bounds.w == 100 && b.bounds.w == 100 // 160 + (200 - 320) / 2
	h2.box.bounds = Rect{0, 0, 50, 40}
	h2.box.layout(ctx)
	assert a.bounds.w == 40 && b.bounds.w == 40 // упёрлись в min
}

// Виджет без measure() в режиме по умолчанию занимает свободное место
fn test_auto_unmeasurable_fills() {
	mut ctx := empty_ctx()
	mut v := create_vbox_fill()
	v.box.bounds = Rect{0, 0, 100, 300}
	v.box.spacing = 0
	mut ic := icon('a')
	ic.size = 20
	mut n := notification('x')
	v.add(ic)
	v.add(n)
	v.box.layout(ctx)
	assert ic.bounds.h == 20
	assert n.bounds.h == 280
}

// Высота VBox без единого размера в разметке - сумма естественных
// высот детей (так её берут Accordion fit_content и ScrollBox)
fn test_vbox_natural_height_without_sizes() {
	mut ctx := empty_ctx()
	mut v := create_vbox_fill()
	v.box.spacing = 6
	v.box.pad = 8
	for sz in [16, 24, 32] {
		mut ic := icon('a')
		ic.size = sz
		v.add(ic)
	}
	assert v.measure(ctx).h == 16 + 24 + 32 + 2 * 6 + 2 * 8
	mut sb := scroll_box(0)
	sb.bounds = Rect{0, 0, 200, 50}
	sb.add(v)
	sb.update_eff_content_size(ctx)
	assert sb.eff_content_h == 16 + 24 + 32 + 2 * 6 + 2 * 8
	sb.bounds = Rect{0, 0, 200, 500}
	sb.update_eff_content_size(ctx)
	assert sb.eff_content_h == 500 // меньше видимой области - заполняет её
}

// ScrollBox с несколькими детьми (аудит 2026-10, раздел 6.4): раньше размер
// содержимого брался по первому ребёнку, а все дети ложились в один и тот же
// прямоугольник друг на друга. Теперь - стопка вдоль оси прокрутки.
fn test_scroll_box_stacks_several_children() {
	mut ctx := empty_ctx()
	mut sb := scroll_box(0)
	sb.spacing = 5
	sb.pad = 0
	sb.bounds = Rect{0, 0, 200, 50}
	mut icons := []&Icon{}
	for sz in [16, 24, 32] {
		mut ic := icon('a')
		ic.size = sz
		icons << ic
		sb.add(ic)
	}
	sb.arrange(mut ctx)
	assert sb.eff_content_h == 16 + 24 + 32 + 2 * 5
	assert sb.max_scroll() == sb.eff_content_h - 50
	assert icons[0].bounds.y == 0
	assert icons[1].bounds.y == 16 + 5
	assert icons[2].bounds.y == 16 + 5 + 24 + 5
	assert icons[2].bounds.h == 32
	// прокрутка сдвигает всю стопку
	sb.scroll_y = 10
	sb.arrange(mut ctx)
	assert icons[1].bounds.y == 16 + 5 - 10

	// горизонтальный - то же по ширине
	mut hb := scroll_box_h(0)
	hb.spacing = 2
	hb.pad = 0
	hb.bounds = Rect{0, 0, 30, 40}
	mut a := icon('a')
	a.size = 20
	mut b := icon('b')
	b.size = 20
	hb.add(a)
	hb.add(b)
	hb.arrange(mut ctx)
	assert hb.eff_content_w == 42
	assert b.bounds.x == 22
}
