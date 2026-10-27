module vgui

// Timeline (timeline.v) и переходы темы (AnimTiming, anim.v).
//
// Шкала проверяется двумя путями: напрямую через advance (точные значения
// дорожек, задержки, цепочки, loop) и через App (play -> render_all при
// остановленных часах интерфейса, clock.v) - так видно, что приложение само
// двигает шкалу и просит кадры, пока она идёт.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test timeline_test.v

struct TlLog {
mut:
	a    []f32
	b    []f32
	done int
}

fn test_tracks_delay_and_end_value() {
	mut log := &TlLog{}
	mut tl := timeline()
	tl.add(0, 100, 0, 10, .linear, fn [mut log] (v f32) {
		log.a << v
	})
	tl.add(50, 100, 1, 0, .linear, fn [mut log] (v f32) {
		log.b << v
	})
	tl.on_done = fn [mut log] () {
		log.done++
	}
	assert tl.total_ms() == 150

	assert tl.advance(25)
	assert log.a == [f32(2.5)]
	assert log.b.len == 0, 'дорожка с задержкой ещё не началась'

	assert tl.advance(50) // 75 мс
	assert log.a.last() == 7.5
	assert log.b == [f32(0.75)]

	// Кадр перескочил через конец первой дорожки - она отдаёт ровно to и замолкает.
	assert tl.advance(50) // 125 мс
	assert log.a.last() == 10
	n := log.a.len
	assert tl.advance(10) // 135 мс
	assert log.a.len == n

	assert !tl.advance(100) // конец
	assert log.b.last() == 0
	assert log.done == 1
	assert !tl.advance(10), 'закончившаяся шкала стоит'
	assert log.done == 1
}

fn test_then_chains_after_existing() {
	mut log := &TlLog{}
	mut tl := timeline()
	tl.add(0, 100, 0, 1, .linear, fn [mut log] (v f32) {
		log.a << v
	})
	tl.then(20, 50, 0, 1, .linear, fn [mut log] (v f32) {
		log.b << v
	})
	assert tl.tracks[1].delay_ms == 120
	assert tl.total_ms() == 170
	tl.advance(110)
	assert log.b.len == 0
	tl.advance(35) // 145 мс: вторая дорожка на половине
	assert log.b == [f32(0.5)]
}

fn test_loop_and_stop() {
	mut log := &TlLog{}
	mut tl := timeline()
	tl.loop = true
	tl.add(0, 100, 0, 1, .linear, fn [mut log] (v f32) {
		log.a << v
	})
	tl.on_done = fn [mut log] () {
		log.done++
	}
	assert tl.advance(100) // конец круга - начинается заново
	assert tl.advance(50)
	assert log.a.last() == 0.5
	tl.stop()
	assert !tl.advance(50)
	assert log.done == 0, 'stop и loop не зовут on_done'
}

// App: play -> render_all двигает шкалу по часам интерфейса, пока она идёт,
// приложение просит кадры; по концу шкала уходит из app.timelines.
fn test_app_plays_timeline() {
	set_clock_override(10_000)
	defer {
		clear_clock_override()
	}
	mut t := new_test_ui(width: 100, height: 60)!
	defer {
		t.close()
	}
	mut log := &TlLog{}
	tl := t.app.animate(200, 0, 100, .linear, fn [mut log] (v f32) {
		log.a << v
	})
	assert tl.is_playing()
	assert t.app.needs_animation_now()

	advance_clock(50)
	t.app.render_all()
	assert log.a.last() == 25

	advance_clock(500) // шаг не больше anim_max_dt (100 мс)
	t.app.render_all()
	assert log.a.last() == 75

	advance_clock(100)
	t.app.render_all()
	assert log.a.last() == 100
	assert !tl.is_playing()
	assert t.app.timelines.len == 0
	assert !t.app.needs_animation_now()
}

// Темп темы: роль берёт tau из theme.anim в момент шага, speed 0 выключает
// анимации (сразу в цель), speed 2 - вдвое быстрее.
fn test_theme_anim_timing() {
	mut ctx := RenderContext{}
	assert ctx.theme.anim.speed == 1
	mut a := anim_role(.hover)
	a.update(1, ctx)
	normal := a.value

	ctx.theme.anim.hover_ms = anim_tau_hover / 2
	mut fast := anim_role(.hover)
	fast.update(1, ctx)
	assert fast.value > normal, 'меньшая постоянная времени в теме - быстрее'

	ctx.theme.anim = AnimTiming{
		speed: 0
	}
	mut off := anim_role(.press)
	assert !off.update(1, ctx)
	assert off.value == 1, 'speed 0 - без анимации'

	// Своё Anim (.custom) не берёт tau из темы, но speed действует.
	ctx.theme.anim = AnimTiming{
		hover_ms: 1
		speed:    2
	}
	mut own := anim_smooth(anim_tau_hover)
	own.update(1, ctx)
	mut ref := anim_smooth(anim_tau_hover)
	ref.set_target(1)
	ref.advance(anim_nominal_dt * 2)
	assert own.value == ref.value
}
