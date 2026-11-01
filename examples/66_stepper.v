module main

// Пример 66. Индикатор шагов (Stepper, stepper.v) - пошаговый мастер.
//
// Что показано:
//   - горизонтальный индикатор над содержимым и вертикальный сбоку - оба отражают одну модель;
//   - состояния шагов: сделан (галочка), требует внимания (warning - «настройки изменились,
//     нужно пересобрать»), недоступен (locked - замок, пока не выполнен предыдущий шаг),
//     необязательный шаг (ретушь можно пропустить);
//   - подписи под названиями (note) - что сделано на шаге;
//   - щелчок по шагу переходит к нему (on_change); по недоступному - нельзя;
//   - кнопки «Назад» / «Далее» меняют текущий шаг кодом (set_current колбэк не вызывает);
//   - стилизация CSS (тип `stepper`) и смена темы на ходу.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/66_stepper.v

import vgui

// Стили для переключателя «Свой стиль»: зелёные сделанные шаги, фиолетовый текущий, кружки
// крупнее. Свойства - PROJECT.md, «Stepper».
const custom_css = '
stepper { done-color: #2fa66a; done-line-color: #2fa66a; circle-size: 30; note-color: #8a8f98 }
stepper:selected { background: #8e5cf0; color: #8e5cf0 }
stepper:hover { color: #2fa66a }
'

// Номера шагов мастера.
const step_prepare = 0
const step_build = 1
const step_retouch = 2
const step_export = 3

// Wizard - модель мастера (что уже сделано) и виджеты, которые её показывают. @[heap]: на неё
// ссылаются замыкания колбэков.
@[heap]
struct Wizard {
mut:
	prepared  bool
	built     bool
	stale     bool // настройки изменились после сборки - сборка устарела
	retouched bool
	exported  bool
	variants  int
	top       &vgui.Stepper = unsafe { nil }
	side      &vgui.Stepper = unsafe { nil }
	body      &vgui.Label   = unsafe { nil }
	next      &vgui.Button  = unsafe { nil }
	back      &vgui.Button  = unsafe { nil }
}

// apply_states - состояния и подписи шагов из модели в индикатор s.
fn (w &Wizard) apply_states(mut s vgui.Stepper) {
	s.set_state(step_prepare, if w.prepared { .done } else { .pending })
	s.set_note(step_prepare, if w.prepared { '12 кадров выровнено' } else { '' })

	build_state := if !w.prepared {
		vgui.StepState.locked
	} else if w.built && w.stale {
		vgui.StepState.warning
	} else if w.built {
		vgui.StepState.done
	} else {
		vgui.StepState.pending
	}
	s.set_state(step_build, build_state)
	s.set_note(step_build, if w.stale {
		'настройки изменены'
	} else if w.built {
		'вариантов: ${w.variants}'
	} else {
		''
	})

	locked_until_built := if w.built { vgui.StepState.pending } else { vgui.StepState.locked }
	s.set_state(step_retouch, if w.retouched { .done } else { locked_until_built })
	s.set_note(step_retouch, if w.retouched { '3 мазка' } else { '' })
	s.set_state(step_export, if w.exported { .done } else { locked_until_built })
	s.set_note(step_export, if w.exported { 'stack.tif' } else { '' })
}

// refresh - оба индикатора, текст шага и кнопки по модели и текущему шагу cur.
fn (mut w Wizard) refresh(cur int) {
	w.apply_states(mut w.top)
	w.apply_states(mut w.side)
	w.top.set_current(cur)
	w.side.set_current(cur)
	w.body.set_text(match cur {
		step_prepare {
			'Подготовка: выберите кадры и выровняйте их. Делается один раз - потом сборка идёт быстро.'
		}
		step_build {
			'Сборка: склейка выровненных кадров в результат. Поменяйте настройки и соберите снова, чтобы сравнить.'
		}
		step_retouch {
			'Ретушь (необязательно): закрасьте размытые места из самого резкого кадра.'
		}
		else {
			'Экспорт: сохраните результат в файл (TIFF 16 бит или JPEG).'
		}
	})
	w.next.text = match cur {
		step_prepare { 'Выровнять кадры' }
		step_build {
			if w.built && !w.stale { 'Далее: ретушь' } else { 'Собрать' }
		}
		step_retouch {
			if w.retouched {
				'Далее: экспорт'
			} else {
				'Пропустить ретушь'
			}
		}
		else { 'Сохранить файл' }
	}
	w.back.enabled = cur > 0
}

// on_next - главная кнопка: выполнить действие текущего шага или перейти к следующему.
fn (mut w Wizard) on_next() {
	cur := w.top.get_current()
	match cur {
		step_prepare {
			w.prepared = true
			w.refresh(step_build)
		}
		step_build {
			if w.built && !w.stale {
				w.refresh(step_retouch)
			} else {
				w.built = true
				w.stale = false
				w.variants++
				w.refresh(step_build)
			}
		}
		step_retouch {
			w.refresh(step_export)
		}
		else {
			w.exported = true
			w.refresh(step_export)
		}
	}
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Stepper - пример', width: 820, height: 380)!

	// Индикаторы: горизонтальный строится кодом, вертикальный - тот же набор шагов.
	mut top := vgui.stepper(
		steps: ['Подготовка', 'Сборка', 'Ретушь', 'Экспорт']
	)
	top.set_optional(step_retouch, true)
	mut side := vgui.stepper(
		steps:    ['Подготовка', 'Сборка', 'Ретушь', 'Экспорт']
		vertical: true
	)
	side.set_optional(step_retouch, true)

	mut body := vgui.label('')
	body.wrap = true
	mut back := vgui.button('Назад')
	mut next := vgui.button('Далее')
	next.style = .accent
	mut change := vgui.button('Изменить настройки')
	change.tooltip = 'Помечает сборку устаревшей (состояние warning)'
	mut retouch := vgui.button('Сделать мазок')
	mut w := &Wizard{
		top:  top
		side: side
		body: body
		next: next
		back: back
	}

	// Щелчок по шагу индикатора - перейти к нему (недоступные шаги виджет сам не пускает).
	top.on_change = fn [mut w] (i int) {
		w.refresh(i)
	}
	side.on_change = fn [mut w] (i int) {
		w.refresh(i)
	}
	next.on_click = fn [mut w] () {
		w.on_next()
	}
	back.on_click = fn [mut w] () {
		w.refresh(w.top.get_current() - 1)
	}
	change.on_click = fn [mut w] () {
		if w.built {
			w.stale = true
			w.exported = false
		}
		w.refresh(w.top.get_current())
	}
	retouch.on_click = fn [mut w] () {
		if w.built {
			w.retouched = true
			w.exported = false
		}
		w.refresh(w.top.get_current())
	}

	// Оформление: своя таблица стилей и тема.
	mut styled := vgui.toggle_switch('Свой стиль (CSS)')
	styled.on_change = fn [mut app] (on bool) {
		if on {
			app.set_stylesheet(vgui.parse_stylesheet(custom_css, 'stepper.css') or { panic(err) })
		} else {
			app.set_stylesheet(unsafe { nil })
		}
	}
	mut light := vgui.toggle_switch('Светлая тема')
	light.on_change = fn [mut app] (on bool) {
		app.set_theme(if on { vgui.light_theme() } else { vgui.dark_theme() })
	}

	// Раскладка: сверху индикатор, ниже - вертикальный индикатор слева и содержимое шага справа.
	mut buttons := vgui.create_hbox_fill()
	buttons.set_spacing(8)
	buttons.add(back)
	buttons.add(vgui.create_spacer(), flex: 1)
	buttons.add(change)
	buttons.add(retouch)
	buttons.add(next)

	mut content := vgui.create_vbox_fill()
	content.set_spacing(12)
	content.add(body)
	content.add(vgui.create_spacer(), flex: 1)
	content.add(styled)
	content.add(light)
	content.add(buttons)

	mut middle := vgui.create_hbox_fill()
	middle.set_spacing(16)
	middle.add(side)
	middle.add(vgui.separator())
	middle.add(content, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(14)
	root.set_spacing(12)
	root.add(top)
	root.add(vgui.hseparator())
	root.add(middle, flex: 1)

	w.refresh(step_prepare)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}
