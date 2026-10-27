module vgui

// ═══════════════════════════════════════════════════════════
//  Timeline — анимация из приложения: несколько чисел по одной шкале
//  времени, с задержками и цепочками (PROJECT.md, «Анимации»).
// ═══════════════════════════════════════════════════════════
//
//  Anim (anim.v) — одно число внутри виджета, которое виджет сам шагает в
//  draw(). Timeline — для кода приложения: «за 300 мс сдвинуть разделитель
//  с 0.2 до 0.5, через 100 мс после начала за 200 мс проявить цвет, а
//  когда всё кончится — вызвать on_done». Каждая дорожка (TimelineTrack)
//  ведёт одно число от from до to за duration_ms после delay_ms и на каждом
//  кадре отдаёт значение колбэком on_value. Что делать со значением, решает
//  приложение: поставить ratio Splitter, процент ProgressBar, цвет панели...
//  Свойств «позиция» и «прозрачность» у виджетов нет намеренно (раскладка
//  без пикселей), поэтому анимируется любое число, а не фиксированный набор.
//
//  Играет App: app.play(tl) кладёт шкалу в app.timelines, render_all()
//  перед кадром двигает все шкалы на время с прошлого кадра (часы now_ms(),
//  clock.v) и, пока хоть одна идёт, просит кадры и перерисовывает окна
//  целиком: сеттеры виджетов кадр не инвалидируют (CLAUDE.md, «Инвалидация»),
//  а колбэк мог поменять что угодно.
//
//  Колбэки зовутся в главном потоке, из render_all(), до отрисовки кадра.

// TimelineTrack - одна дорожка шкалы: число от from до to за duration_ms,
// начиная через delay_ms после старта шкалы, по кривой easing.
pub struct TimelineTrack {
pub mut:
	delay_ms    f32
	duration_ms f32 = 200
	from        f32
	to          f32    = 1
	easing      Easing = .out_cubic
	// on_value получает значение на каждом кадре, пока дорожка идёт, и
	// последний раз - ровно to, когда она закончилась (даже если кадр
	// перескочил через конец).
	on_value fn (v f32) = unsafe { nil }
mut:
	finished bool // to уже отдано - больше колбэк не зовётся
}

// Timeline - набор дорожек на одной шкале. Создавать timeline(), наполнять
// add/then, запускать app.play(tl). Шкала одноразовая: после конца её
// можно запустить заново только app.play после rewind().
@[heap]
pub struct Timeline {
pub mut:
	tracks []TimelineTrack
	// on_done вызывается один раз, когда закончилась последняя дорожка
	// (не вызывается при stop()).
	on_done fn () = unsafe { nil }
	// loop - по окончании начать сначала (on_done тогда не вызывается).
	loop bool
mut:
	elapsed f32  // мс от старта шкалы
	playing bool // идёт (стоит в app.timelines)
	done    bool // закончилась или остановлена
}

// timeline создаёт пустую шкалу.
pub fn timeline() &Timeline {
	return &Timeline{}
}

// add добавляет дорожку: число от from до to за duration_ms, через delay_ms
// после старта шкалы. on_value получает значения. Возвращает шкалу - вызовы
// можно сцеплять: tl.add(...).add(...).
pub fn (mut tl Timeline) add(delay_ms f32, duration_ms f32, from f32, to f32, easing Easing, on_value fn (f32)) &Timeline {
	tl.tracks << TimelineTrack{
		delay_ms:    delay_ms
		duration_ms: duration_ms
		from:        from
		to:          to
		easing:      easing
		on_value:    on_value
	}
	return tl
}

// then - цепочка: дорожка начинается, когда закончатся все уже добавленные
// (плюс gap_ms паузы). Так «сначала A, потом B» записывается без подсчёта
// задержек вручную.
pub fn (mut tl Timeline) then(gap_ms f32, duration_ms f32, from f32, to f32, easing Easing, on_value fn (f32)) &Timeline {
	return tl.add(tl.total_ms() + gap_ms, duration_ms, from, to, easing, on_value)
}

// total_ms - длительность шкалы: конец самой поздней дорожки.
pub fn (tl &Timeline) total_ms() f32 {
	mut total := f32(0)
	for tr in tl.tracks {
		end := tr.delay_ms + max_f32(tr.duration_ms, 0)
		if end > total {
			total = end
		}
	}
	return total
}

// is_playing - шкала запущена и ещё не закончилась.
pub fn (tl &Timeline) is_playing() bool {
	return tl.playing && !tl.done
}

// rewind возвращает шкалу в начало (для повторного app.play).
pub fn (mut tl Timeline) rewind() {
	tl.elapsed = 0
	tl.done = false
	for mut tr in tl.tracks {
		tr.finished = false
	}
}

// stop останавливает шкалу: значения остаются, где были, on_done не
// вызывается. App уберёт её из списка на следующем кадре.
pub fn (mut tl Timeline) stop() {
	tl.done = true
}

// advance двигает шкалу на dt мс и раздаёт значения дорожкам. Возвращает
// true, пока шкала не закончилась. Публичная для тестов и своих часов
// (запись видео по кадрам): в приложении её зовёт App.
pub fn (mut tl Timeline) advance(dt f32) bool {
	if tl.done {
		return false
	}
	tl.elapsed += max_f32(dt, 0)
	mut all_finished := true
	for mut tr in tl.tracks {
		if tr.finished {
			continue
		}
		local := tl.elapsed - tr.delay_ms
		if local < 0 {
			// дорожка ещё не началась - значение не трогаем
			all_finished = false
			continue
		}
		t := if tr.duration_ms <= 0 { f32(1) } else { local / tr.duration_ms }
		if t >= 1 {
			tr.finished = true
			emit_track_value(tr, tr.to)
		} else {
			all_finished = false
			emit_track_value(tr, lerp(tr.from, tr.to, ease(tr.easing, t)))
		}
	}
	if !all_finished {
		return true
	}
	if tl.loop && tl.tracks.len > 0 {
		tl.rewind()
		return true
	}
	tl.done = true
	if tl.on_done != unsafe { nil } {
		tl.on_done()
	}
	return false
}

// emit_track_value зовёт колбэк дорожки, если он задан.
fn emit_track_value(tr &TimelineTrack, v f32) {
	if tr.on_value != unsafe { nil } {
		tr.on_value(v)
	}
}

// ─── Проигрывание через App ───────────────────────────────

// play запускает шкалу: с ближайшего кадра render_all() двигает её по
// часам интерфейса. Повторный play той же идущей шкалы - no-op;
// закончившуюся шкалу перед повтором нужно rewind().
pub fn (mut app App) play(tl &Timeline) {
	mut t := unsafe { tl }
	if t.playing && !t.done {
		return
	}
	t.playing = true
	t.done = false
	app.timelines << t
	// Первый шаг - от этого момента, а не от прошлого кадра (он мог быть
	// секунды назад, и анимация перепрыгнула бы через начало).
	app.timeline_last_ms = now_ms()
}

// step_timelines - шаг всех идущих шкал перед кадром (зовёт render_all).
// Время шага - с прошлого шага по now_ms(), не больше anim_max_dt (после
// подвисания анимация продолжается, а не прыгает в конец). Пока хоть одна
// шкала шла, все окна перерисовываются целиком: колбэки могли поменять
// любые виджеты, а сеттеры кадр не инвалидируют.
fn (mut app App) step_timelines() {
	if app.timelines.len == 0 {
		return
	}
	frame_ms := now_ms()
	dt := if frame_ms >= app.timeline_last_ms {
		clamp_f32(f32(frame_ms - app.timeline_last_ms), 0, anim_max_dt)
	} else {
		f32(0)
	}
	app.timeline_last_ms = frame_ms
	mut alive := []&Timeline{cap: app.timelines.len}
	for mut tl in app.timelines {
		if tl.advance(dt) {
			alive << tl
		} else {
			tl.playing = false
		}
	}
	app.timelines = alive
	app.invalidate_all_windows()
}

// animate - короткая запись для одного числа: шкала из одной дорожки,
// сразу запущенная. Возвращает её (можно stop()).
pub fn (mut app App) animate(duration_ms f32, from f32, to f32, easing Easing, on_value fn (f32)) &Timeline {
	mut tl := timeline()
	tl.add(0, duration_ms, from, to, easing, on_value)
	app.play(tl)
	return tl
}

// ─── Темп анимаций виджетов ───────────────────────────────

// set_anim_timing задаёт темп переходов встроенных виджетов (AnimTiming,
// anim.v) окну: тема окна остаётся прежней, меняется только её поле anim.
// Кадр не инвалидирует - новый темп действует со следующего шага анимаций.
pub fn (mut w Window) set_anim_timing(t AnimTiming) {
	// config.theme - необязательная (none - тема приложения): правим, только если задана.
	if theme := w.config.theme {
		mut own := theme
		own.anim = t
		w.config.theme = own
	}
	w.ctx.theme.anim = t
}

// set_anim_timing - то же для всего приложения: тема по умолчанию для будущих
// окон и все открытые окна и диалоги, в том числе со своей темой (темп - это
// настройка пользователя, например «уменьшить движение», а не часть вида).
pub fn (mut app App) set_anim_timing(t AnimTiming) {
	app.config.theme.anim = t
	for mut w in app.windows {
		w.set_anim_timing(t)
	}
	for mut d in app.dialogs {
		d.win.set_anim_timing(t)
	}
}
