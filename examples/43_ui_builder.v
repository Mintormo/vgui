module main

// Пример 43. UI Builder: интерфейс из YAML-описания (load_ui_from_string) с привязкой колбэков по именам (UiCallbacks) и доступом к виджетам по id.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/43_ui_builder.v

import vgui

// Декларативное описание интерфейса на YAML. Виджеты, их свойства и
// компоновка задаются текстом; имена обработчиков (on_click, on_change...)
// связываются с V-функциями через UiCallbacks. Именованные виджеты (id)
// доступны в рантайме через методы tree.get_*("id").
const ui_yaml = '
type: vbox
spacing: 10
padding: 16
children:
  - type: label
    text: "UI Builder - декларативный интерфейс"
    font_style: bold
    font_size: 18

  - type: label
    id: status
    text: "Заполните форму и нажмите кнопку"

  - type: separator

  - type: text_input
    id: name_input
    placeholder: "Ваше имя..."
    on_change: on_name_change

  - type: checkbox
    text: "Подписаться на рассылку"
    on_change: on_subscribe

  - type: slider
    id: volume
    min: 0
    max: 100
    value: 50
    on_change: on_volume

  - type: spacer
    flex: 1

  - type: hbox
    spacing: 6
    children:
      - type: button
        text: "Сохранить"
        style: accent
        on_click: on_save
        flex: 1
      - type: button
        text: "Отмена"
        style: outline
        on_click: on_cancel
        flex: 1
'

// Колбэки привязываются к именам во время построения дерева, поэтому
// регистрируем их ДО load_ui_from_string. Чтобы они могли читать виджеты
// по id, замыкания захватывают указатель на heap-состояние, а само дерево
// присваивается в него уже после построения.
@[heap]
struct BuilderState {
mut:
	tree vgui.UiTree
}

fn (s &BuilderState) set_status(text string) {
	mut lbl := s.tree.get_label('status')
	if unsafe { lbl != nil } {
		lbl.text = text
	}
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'UI Builder - demo')!

	mut state := &BuilderState{
		tree: vgui.UiTree{}
	}

	mut cb := vgui.ui_callbacks()
	cb.on_change_string('on_name_change', fn [mut state] (text string) {
		state.set_status('Имя: ${text}')
	})
	// У чекбокса событие on_change с новым состоянием (не on_click).
	cb.on_change_bool('on_subscribe', fn [mut state] (on bool) {
		state.set_status(if on {
			'Подписка включена'
		} else {
			'Подписка выключена'
		})
	})
	cb.on_change_f32('on_volume', fn [mut state] (v f32) {
		state.set_status('Громкость: ${v:.0f}')
	})
	cb.on_click('on_save', fn [mut state] () {
		name := state.tree.get_text_input('name_input').get_text()
		vol := state.tree.get_slider('volume').get_value()
		state.set_status('Сохранено: "${name}", громкость ${vol:.0f}')
	})
	cb.on_click('on_cancel', fn [mut state] () {
		state.set_status('Отменено')
	})

	tree := vgui.load_ui_from_string(ui_yaml, &cb) or {
		eprintln('Ошибка разбора YAML: ${err}')
		return
	}
	state.tree = tree

	win.add_ui_tree(&tree)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
