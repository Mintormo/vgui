module vgui

// UI Builder (ui_builder.v): разбор YAML в дерево виджетов без окна и SDL.
//
// Запуск (из корня vgui): v -enable-globals test ui_builder_test.v

const ui_test_yaml = 'type: vbox
children:
  - type: label
    id: status
    text: "hi"
  - type: button
    id: ok
    text: "OK"
'

// get_<виджет> сверяет тег типа (аудит 2026-10, 1.9): id чужого типа даёт nil,
// а не слепое приведение указателя к неверной структуре.
fn test_typed_getters_check_widget_tag() {
	cb := UiCallbacks{}
	tree := load_ui_from_string(ui_test_yaml, &cb)!
	assert unsafe { tree.get_label('status') != nil }
	assert unsafe { tree.get_button('ok') != nil }
	assert unsafe { tree.get_button('status') == nil }
	assert unsafe { tree.get_slider('ok') == nil }
	assert unsafe { tree.get_label('missing') == nil }
	assert tree.get_label('status').text == 'hi'
}

const ui_events_yaml = 'type: vbox
children:
  - type: checkbox
    id: sub
    text: "Подписка"
    on_change: on_sub
  - type: accordion
    id: acc
    on_change: on_section
    sections:
      - title: "A"
        child:
          type: label
          text: "a"
'

// Журнал событий: замыкание V захватывает массив копией, поэтому - структура в куче.
struct UiEventLog {
mut:
	events []string
}

// on_change чекбокса - on_change_bool (аудит 2026-10, 2.2: в демо стоял on_click, и
// обработчик не срабатывал); on_change аккордеона - on_section_toggle (2.7: обработчик
// находился, но не сохранялся).
fn test_checkbox_and_accordion_handlers_are_bound() {
	mut log := &UiEventLog{}
	mut cb := UiCallbacks{}
	cb.on_change_bool('on_sub', fn [mut log] (on bool) {
		log.events << 'sub ${on}'
	})
	cb.on_section_toggle('on_section', fn [mut log] (idx int, expanded bool) {
		log.events << 'section ${idx} ${expanded}'
	})
	tree := load_ui_from_string(ui_events_yaml, &cb)!
	mut chk := tree.get_checkbox('sub')
	chk.toggle()
	mut acc := tree.get_accordion('acc')
	acc.toggle_section(0) // как клик по заголовку
	assert log.events == ['sub true', 'section 0 true']
}
