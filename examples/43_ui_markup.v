module main

// Пример 43. Разметка интерфейса (.vui): вид окна - в файле 43_notes.vui,
// поведение - в коде, элементы находятся по #id.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/43_ui_markup.v

import vgui

// Разметка встраивается в бинарник: пример запускается из любого каталога.
// Читать файл с диска - vgui.ui_load(path).
const notes_vui = $embed_file('43_notes.vui').to_string()

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.light_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Notes - vui markup demo', width: 720, height: 480)!

	// Ошибка разметки (опечатка в типе или свойстве) - с номером строки.
	ui := vgui.ui_parse(notes_vui, '43_notes.vui')!

	// Элементы по #id - типизированно: неверный тип - ошибка, а не падение.
	mut status := ui.get[vgui.Label]('status')!
	mut text := ui.get[vgui.TextArea]('text')!
	mut notes := ui.get[vgui.ListBox]('notes')!

	mut save := ui.get[vgui.Button]('save')!
	save.on_click = fn [mut status, text] () {
		status.text = 'Сохранено: ${text.get_text().len} симв.'
	}
	notes.on_select = fn [mut text] (_ int, title string) {
		text.set_text('${title}\n\n')
	}
	mut dark := ui.get[vgui.ToggleSwitch]('dark')!
	dark.on_change = fn [mut app] (on bool) {
		app.set_theme(if on { vgui.dark_theme() } else { vgui.light_theme() })
	}
	// Пункты меню и узлы дерева - свои словари: ui.item / ui.node.
	if mut quit := ui.item('quit') {
		quit.on_click = fn [mut app] () {
			app.quit()
		}
	}

	// Корень разметки - обычный виджет.
	win.add_widget(ui.root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
