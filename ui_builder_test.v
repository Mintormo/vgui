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
