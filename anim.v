module vgui

import math

// ═══════════════════════════════════════════════════════════
//  Anim — анимируемое число для виджетов (PROJECT.md, «Анимации»).
//
//  Виджет держит Anim вместо голого f32, в draw()/arrange() зовёт
//  `a.update(target, ctx)` и рисует по `a.value`; пока update возвращает
//  true, виджет просит следующий кадр (mark_anim_rect).
//
//  Два режима:
//  - .smooth — плавное следование за целью (экспоненциальное сближение):
//    цель можно менять хоть каждый кадр, движение не дёргается. Так
//    анимируются hover/press/focus/выбор.
//  - .tween — переход за duration_ms по кривой easing; смена цели
//    начинает новый переход от текущего значения.
//
//  Время берётся из кадра (`ctx.anim_dt`), а не «доля за кадр», поэтому
//  скорость не зависит от частоты кадров. Шаг — не больше одного за кадр
//  (`ctx.frame_no`): update можно звать и из arrange(), и из draw().
// ═══════════════════════════════════════════════════════════

// Номинальный кадр: шаг первого кадра после простоя и шаг вне Window.render
// (тесты, ручной RenderContext).
pub const anim_nominal_dt = f32(1000.0 / 60.0)

// Потолок шага: после подвисания (перетаскивание окна, тяжёлый кадр)
// анимация продолжается, а не перескакивает в конец.
pub const anim_max_dt = f32(100)

// Постоянные времени .smooth (мс до ~63% пути). Подобраны так, что при
// 60 fps движение совпадает с прежними «x += (цель - x) * k за кадр»:
// tau = -16.67 / ln(1 - k).
pub const anim_tau_focus = f32(84) // k = 0.18: фокус, появление
pub const anim_tau_hover = f32(75) // k = 0.2: наведение, разворот
pub const anim_tau_toggle = f32(58) // k = 0.25: отметка флажка/радио
pub const anim_tau_press = f32(47) // k = 0.3: нажатие

// AnimMode — закон движения Anim к цели (см. шапку файла).
pub enum AnimMode {
	smooth
	tween
}

// Easing — форма кривой режима .tween: как прогресс перехода (0..1)
// зависит от доли прошедшего времени (0..1). in_* — разгон, out_* —
// торможение к концу, in_out_* — и то и другое.
pub enum Easing {
	linear
	in_quad
	out_quad
	in_out_quad
	in_cubic
	out_cubic
	in_out_cubic
	out_back // с небольшим перелётом за цель
}

// ease — кривая: t в [0, 1] → прогресс (0 → 0, 1 → 1).
// t за пределами [0, 1] зажимается. Формулы — стандартные кривые
// (easings.net); у out_back результат в середине пути ненадолго
// превышает 1 — это и есть «перелёт» за цель.
pub fn ease(e Easing, t_ f32) f32 {
	t := clamp_f32(t_, 0, 1)
	return match e {
		.linear {
			t
		}
		.in_quad {
			t * t
		}
		.out_quad {
			1 - (1 - t) * (1 - t)
		}
		.in_out_quad {
			if t < 0.5 { 2 * t * t } else { 1 - (-2 * t + 2) * (-2 * t + 2) / 2 }
		}
		.in_cubic {
			t * t * t
		}
		.out_cubic {
			u := 1 - t
			1 - u * u * u
		}
		.in_out_cubic {
			if t < 0.5 {
				4 * t * t * t
			} else {
				u := -2 * t + 2
				1 - u * u * u / 2
			}
		}
		.out_back {
			// c1 = 1.70158 — классическая константа Пеннера: перелёт ~10%.
			c1 := f32(1.70158)
			c3 := c1 + 1
			u := t - 1
			1 + c3 * u * u * u + c1 * u * u
		}
	}
}

// Anim — значение `value`, движущееся к цели `goal`.
// Это value-структура: виджет хранит её полем и зовёт методы через `mut`.
// Значение по умолчанию (Anim{}) — .smooth с tau_hover, стоит в 0.
pub struct Anim {
pub mut:
	mode        AnimMode = .smooth
	tau_ms      f32      = anim_tau_hover // .smooth
	duration_ms f32      = 200            // .tween
	easing      Easing   = .out_cubic     // .tween
	// .smooth: ближе этого к цели — значение прилипает к ней, анимация
	// закончена. Для величин порядка 0..1.
	epsilon f32 = 0.005
	// Читать можно напрямую; менять — только через set_target/snap/update,
	// иначе собьётся состояние перехода.
	value f32 // текущее значение — по нему рисуют
	goal  f32 // цель
mut:
	from    f32 // .tween: откуда идёт переход
	elapsed f32 // .tween: мс от начала перехода
	// true, пока идёт переход. Нужен отдельно от value != goal: у .tween
	// он отмечает, что from/elapsed уже инициализированы для текущей цели.
	running bool
	// ctx.frame_no кадра, в котором был последний шаг: охрана
	// «не больше одного шага за кадр» в step().
	last_frame u64
}

// anim_smooth — следование за целью с постоянной времени tau_ms.
pub fn anim_smooth(tau_ms f32) Anim {
	return Anim{
		tau_ms: tau_ms
	}
}

// anim_tween — переход за duration_ms по кривой easing.
pub fn anim_tween(duration_ms f32, easing Easing) Anim {
	return Anim{
		mode:        .tween
		duration_ms: duration_ms
		easing:      easing
	}
}

// at — то же Anim, стоящее в покое на v (значение и цель).
pub fn (a Anim) at(v f32) Anim {
	mut r := a
	r.snap(v)
	return r
}

// set_target задаёт цель. .tween начинает новый переход от текущего
// значения; .smooth продолжает движение без рывка.
pub fn (mut a Anim) set_target(target f32) {
	if target == a.goal {
		return
	}
	a.goal = target
	if a.mode == .tween {
		a.running = false // следующий шаг начнёт переход заново
	}
}

// snap ставит значение и цель сразу, без анимации.
pub fn (mut a Anim) snap(v f32) {
	a.value = v
	a.goal = v
	a.running = false
}

// animating — значение ещё не дошло до цели.
pub fn (a &Anim) animating() bool {
	return a.running || a.value != a.goal
}

// update — set_target + шаг на время кадра. Возвращает animating():
// пока true, виджет просит следующий кадр.
pub fn (mut a Anim) update(target f32, ctx &RenderContext) bool {
	a.set_target(target)
	return a.step(ctx)
}

// step продвигает значение на ctx.anim_dt — не больше раза за кадр.
// Возвращает animating(). Повторный вызов в том же кадре (например,
// сначала из arrange(), потом из draw()) ничего не двигает.
pub fn (mut a Anim) step(ctx &RenderContext) bool {
	// frame_no == 0 — контекст без окна (тесты, ручной RenderContext):
	// кадров нет, поэтому шагаем на каждый вызов.
	if ctx.frame_no != 0 {
		if a.last_frame == ctx.frame_no {
			return a.animating()
		}
		a.last_frame = ctx.frame_no
	}
	a.advance(ctx.anim_dt)
	return a.animating()
}

// advance — шаг на dt мс (без учёта кадров; для тестов и своих часов).
pub fn (mut a Anim) advance(dt_ f32) {
	// Начало перехода: запоминаем точку старта (нужна .tween для lerp)
	// и обнуляем прошедшее время. Если уже стоим на цели — делать нечего.
	if !a.running {
		if a.value == a.goal {
			return
		}
		a.running = true
		a.from = a.value
		a.elapsed = 0
	}
	// Потолок шага: после долгой паузы анимация не перескакивает в конец.
	dt := clamp_f32(dt_, 0, anim_max_dt)
	match a.mode {
		.smooth {
			// Экспоненциальное сближение: за время dt проходим долю
			// k = 1 - e^(-dt/tau) оставшегося пути. Два шага по dt/2 дают
			// ровно то же, что один по dt, — отсюда независимость от fps.
			// tau <= 0 — мгновенный переход (k = 1).
			k := if a.tau_ms <= 0 { f32(1) } else { f32(1 - math.exp(-dt / a.tau_ms)) }
			a.value += (a.goal - a.value) * k
			if abs_f32(a.goal - a.value) < a.epsilon {
				a.value = a.goal
				a.running = false
			}
		}
		.tween {
			// Доля прошедшего времени t → прогресс по кривой easing →
			// интерполяция между from и goal. duration <= 0 — сразу в цель.
			a.elapsed += dt
			t := if a.duration_ms <= 0 { f32(1) } else { a.elapsed / a.duration_ms }
			if t >= 1 {
				a.value = a.goal
				a.running = false
			} else {
				a.value = lerp(a.from, a.goal, ease(a.easing, t))
			}
		}
	}
}
