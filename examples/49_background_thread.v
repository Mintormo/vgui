module main

// Пример 49. Фоновый поток (app.post) и собственный цикл событий вместо app.run() (pump_events / render_all).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/49_background_thread.v

import time
import vgui

// Фоновый поток и свой цикл событий - app.post / pump_events / render_all.
//
// vgui однопоточна: виджеты, окна и колбэки живут в том потоке, который
// создал App. Из рабочего потока легально вызывать РОВНО ОДНУ функцию -
// app.post(f): она кладёт замыкание в потокобезопасный канал, будит цикл
// событий, и замыкание выполняется уже в главном потоке между обработкой
// событий и рендером.
//
// Второй сюжет примера - свой цикл вместо app.run(). Он нужен, когда между
// кадрами надо делать что-то своё: pump_events() - это ровно та часть
// итерации run(), что предшествует рендеру (события + post + трей).

// Состояние, общее для главного и фонового потока. Трогать поля отсюда
// можно только в главном потоке: фоновый лишь читает свои копии и шлёт
// результат через app.post.
@[heap]
struct Work {
mut:
	running bool
	status  &vgui.Label       = unsafe { nil }
	result  &vgui.Label       = unsafe { nil }
	bar     &vgui.ProgressBar = unsafe { nil }
}

// finish вызывается уже в ГЛАВНОМ потоке - тут можно всё.
fn (mut w Work) finish(acc i64) {
	w.status.text = 'Готово'
	w.result.text = 'Сумма квадратов 1..40 = ${acc}'
	w.running = false
}

// heavy_work крутится в ФОНОВОМ потоке: тут нельзя трогать виджеты.
fn heavy_work(app &vgui.App, work &Work) {
	mut a := unsafe { app }
	mut w := unsafe { work }
	total := 40
	mut acc := i64(0)
	for i := 1; i <= total; i++ {
		time.sleep(50 * time.millisecond) // изображаем долгую работу
		acc += i64(i) * i64(i)
		// Захватываем значения ПО ЗНАЧЕНИЮ (i, total): замыкание выполнится
		// позже, когда поток уже уйдёт дальше.
		a.post(fn [mut w, i, total] () {
			w.bar.set_value(f32(i) / f32(total))
			w.status.text = 'Считаю... шаг ${i} из ${total}'
		})
	}
	a.post(fn [mut w, acc] () {
		w.finish(acc)
	})
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Фоновый поток - app.post()')!

	mut status := vgui.label('Нажмите «Посчитать» - работа пойдёт в фоне')
	mut result := vgui.label('')
	result.color = vgui.Color{72, 199, 142, 255}
	mut bar := vgui.progress_bar()
	bar.show_text = true

	mut work := &Work{
		status: status
		result: result
		bar:    bar
	}

	mut start := vgui.button('Посчитать')
	start.on_click = fn [mut app, mut work] () {
		if work.running {
			return
		}
		work.running = true
		work.result.text = ''
		work.bar.set_value(0.0)
		work.status.text = 'Запущено...'
		spawn heavy_work(app, work)
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(8)
	row.set_padding(0)
	row.add(start)
	row.add(vgui.create_spacer(), flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(bar)
	root.add(result)
	root.add(row)
	root.add(vgui.create_spacer(), flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	app.add_window(win)

	// Свой цикл вместо app.run(). pump_events() при простое блокируется не
	// дольше 100 мс, так что CPU не жжётся.
	for app.running {
		app.pump_events()
		app.render_all()
		app.update_running()
	}
	app.cleanup()
}
