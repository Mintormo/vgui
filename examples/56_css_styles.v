module main

// Пример 56. Стили CSS: вид окна - разметкой .vui (со .классами и #id), цвета -
// файлом 56_styles.css. Файл перечитывается сам при сохранении (hot-reload):
// запустите пример, правьте 56_styles.css - окно перерисуется.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/56_css_styles.v

import os
import vgui

// Разметка: .sidebar, .card, .danger - классы для селекторов CSS, #save - и
// имя для кода (ui.get), и селектор #save.
const layout_vui = '
hbox
  vbox .sidebar pad=10 gap=6 max=200
    label "Проекты" bold
    list #projects flex=1
      column "Имя"
      item "vgui"
      item "vraw"
      item "vguipy"
  vbox pad=16 gap=12 flex=1
    label "Стили CSS" size=20 bold
    vbox .card pad=14 gap=8
      label "Название"
      input "Мой проект" hint="Название проекта"
      label "Описание"
      input hint="Пара слов о проекте"
      hbox gap=8
        checkbox "Публичный" checked
        spacer flex=1
        toggle "Тёмная тема" #dark
    progress value=65
    hbox gap=8
      button "Удалить" .danger tooltip="Класс .danger"
      spacer flex=1
      button "Без стилей" #plain toggle
      button "Сохранить" #save tooltip="Селектор #save"
    label "Правьте examples/56_styles.css - окно обновится само" #hint
'

// Запасной вариант, если пример запущен не из репозитория (файла рядом нет):
// стили встроены в бинарник, но тогда без hot-reload.
const embedded_css = $embed_file('56_styles.css').to_string()

fn main() {
	mut app := vgui.create_app(theme: vgui.light_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'CSS styles - vgui demo', width: 760, height: 460)!
	ui := vgui.ui_parse(layout_vui, '56_css_styles.vui')!

	// Стили: файл рядом с исходником примера - со слежением за изменениями.
	css_path := os.join_path(os.dir(@FILE), '56_styles.css')
	if os.exists(css_path) {
		app.load_stylesheet(css_path, true)!
	} else {
		app.set_stylesheet(vgui.parse_stylesheet(embedded_css, '56_styles.css')!)
	}

	// Тёмная тема: корневые правила (:root) переживают смену темы - стили
	// накладываются на любую тему.
	mut dark := ui.get[vgui.ToggleSwitch]('dark')!
	dark.on_change = fn [mut app] (on bool) {
		app.set_theme(if on { vgui.dark_theme() } else { vgui.light_theme() })
	}
	// «Без стилей» - снять таблицу и вернуть (nil - стилей нет). Берём
	// текущую таблицу приложения: файл мог перечитаться после запуска.
	mut plain := ui.get[vgui.Button]('plain')!
	mut saved := &SavedStyles{}
	plain.on_toggle = fn [mut app, mut saved] (on bool) {
		if on {
			saved.ss = app.stylesheet
			app.set_stylesheet(unsafe { nil })
		} else {
			app.set_stylesheet(saved.ss)
		}
	}
	mut hint := ui.get[vgui.Label]('hint')!
	if !os.exists(css_path) {
		hint.text = 'Стили встроены в бинарник - hot-reload недоступен'
	}

	win.add_widget(ui.root)
	app.add_window(win)
	app.run()
}

// SavedStyles - таблица стилей, снятая кнопкой «Без стилей». Именованная
// структура, а не &struct{...}: указатель на анонимную структуру даёт невалидный C.
struct SavedStyles {
mut:
	ss &vgui.Stylesheet = unsafe { nil }
}
