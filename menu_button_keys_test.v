module vgui

import os

// MenuButton: выбор пункта с клавиатуры (аудит 2026-10, 2.5). Enter шёл через
// общий menu_activate_hovered: пункт не становился активным действием, а флаг
// open кнопки оставался true (стрелка «открыта», следующий клик - закрытие).
//
// Нужно окно (шрифты для размеров попапа), под dummy-драйвером.
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test menu_button_keys_test.v

// Журнал выборов: замыкание V захватывает массив копией, поэтому - структура в куче.
struct MbPickLog {
mut:
	picked []string
}

fn test_enter_makes_item_active_and_closes() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'mb keys', width: 400, height: 300)!
	app.add_window(win)

	mut log := &MbPickLog{}
	mut mb := menu_button('Действие')
	mb.add(menu_action('Один'))
	mb.add(menu_separator())
	mb.add(menu_action('Два'))
	mb.on_select = fn [mut log] (idx int, text string) {
		log.picked << '${idx}:${text}'
	}
	mb.bounds = Rect{10, 10, 140, 28}
	mb.open_menu(mut win.ctx)
	assert mb.open && mb.state.open

	ev := win.ctx.overlay_ev
	assert ev != unsafe { nil }
	down := GuiEvent{
		typ:     .key_down
		keycode: sdl_k_down
	}
	ev(&down, app) // «Один»
	ev(&down, app) // «Два» (разделитель пропускается)
	ev(&GuiEvent{ typ: .key_down, keycode: sdl_k_return }, app)

	assert !mb.state.open
	assert !mb.open, 'open кнопки обязан сброситься вместе с меню'
	assert mb.active_idx == 1
	assert mb.text == 'Два'
	assert log.picked == ['1:Два']

	win.cleanup()
	app.cleanup()
}
