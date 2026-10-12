module main

// Пример 53. Anim: анимируемое число для своих виджетов (tween, easing, smooth).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/53_animation.v

import vgui

// Anim - анимируемое число для своих виджетов. Каждая строка - свой
// виджет EaseTrack: точка бежит по дорожке за 900 мс по своей кривой
// (.tween + Easing), а подсветка дорожки при наведении - .smooth.
// Кнопка «Туда-обратно» меняет цель всех точек.
//
// Как пользоваться Anim в своём виджете:
//   1. держать поле `Anim` вместо f32;
//   2. в draw() звать `a.update(цель, ctx)` и рисовать по `a.value`;
//   3. пока update вернула true - просить кадр: ctx.mark_anim_rect(...).

@[heap]
struct EaseTrack {
mut:
	bounds  vgui.Rect
	name    string
	pos     vgui.Anim
	glow    vgui.Anim = vgui.anim_smooth(vgui.anim_tau_hover)
	target  f32
	hovered bool
}

fn ease_track(name string, easing vgui.Easing) &EaseTrack {
	return &EaseTrack{
		name: name
		pos:  vgui.anim_tween(900, easing)
	}
}

// measure - строка фиксированной высоты, растягивается в ширину.
fn (t &EaseTrack) measure(_ &vgui.RenderContext) vgui.SizeHint {
	return vgui.SizeHint{
		w:        360
		h:        34
		min_w:    200
		min_h:    34
		max_h:    34
		h_policy: .expanding
		v_policy: .fixed
	}
}

fn (t &EaseTrack) bounds_of() vgui.Rect {
	return t.bounds
}

fn (mut t EaseTrack) set_bounds(r vgui.Rect) {
	t.bounds = r
}

fn (mut t EaseTrack) handle_event(ev &vgui.GuiEvent, _ &vgui.App) bool {
	if ev.typ == .mouse_move {
		t.hovered = t.bounds.contains(ev.mouse_x, ev.mouse_y)
	}
	return false
}

fn (mut t EaseTrack) draw(mut ctx vgui.RenderContext) {
	mut animating := t.pos.update(t.target, ctx)
	animating = t.glow.update(if t.hovered { f32(1) } else { f32(0) }, ctx) || animating
	if animating {
		ctx.mark_anim_rect('ease_track', t.bounds)
	}

	label_w := f32(110)
	ctx.draw_text(t.name, t.bounds.x, t.bounds.y + 8, ctx.theme.text_primary)
	track := vgui.Rect{t.bounds.x + label_w, t.bounds.y + 13, t.bounds.w - label_w - 12, 8}
	track_c := ctx.theme.button_bg.blend(ctx.theme.accent.with_alpha(90), t.glow.value)
	ctx.fill_rounded_rect(track, track_c, 4)
	// out_back перелетает за 1 - точка выходит за край дорожки, так задумано
	x := track.x + track.w * t.pos.value
	ctx.fill_circle(x, track.y + 4, 9, ctx.theme.accent)
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Anim - easing')!

	mut tracks := []&EaseTrack{}
	for e in [vgui.Easing.linear, .in_quad, .out_quad, .in_out_quad, .in_cubic, .out_cubic,
		.in_out_cubic, .out_back] {
		tracks << ease_track(e.str(), e)
	}

	mut btn := vgui.button('Туда-обратно')
	btn.on_click = fn [mut tracks, mut win] () {
		for mut t in tracks {
			t.target = 1 - t.target
		}
		win.invalidate_all() // сеттеры кадр не просят - запустить анимацию
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(6)
	for t in tracks {
		root.add(t)
	}
	root.add(btn, align: .start)
	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
