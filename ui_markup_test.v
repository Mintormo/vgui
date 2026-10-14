module vgui

// Тесты разметки интерфейса (ui_markup.v): разбор, сборка виджетов, #id,
// свойства раскладки, громкие ошибки с номером строки и живой интерфейс
// через testkit (клик по кнопке из разметки доходит до колбэка из кода).
//
// Запуск: v -enable-globals test ui_markup_test.v

const notes_ui = '
// окно заметок
vbox pad=12 gap=8
  menubar
    menu "Файл"
      item "Открыть" icon=folder-open shortcut=Ctrl+O #open
      check "Перенос строк" checked #wrap
      separator
      submenu "Экспорт"
        item "PDF" #pdf
  hbox cross=center
    button "Сохранить" icon=save style=accent #save
    spacer flex=1
    toggle "Тёмная тема" #dark
  hbox flex=1
    tree #files flex=1
      node "проект" icon=folder #proj
        node "main.v" icon=file-code
        node "docs" collapsed
          node "readme.md"
    textarea "черновик" #note flex=2 hint="Текст заметки"
  label "Готово" #status color=#336699 bold
'

fn test_parse_builds_tree_and_ids() {
	ui := ui_parse(notes_ui, 'notes.vui')!
	root := ui.root
	assert root is VBox
	mut save := ui.get[Button]('save')!
	assert save.text == 'Сохранить'
	assert save.icon_name == 'save'
	assert save.style == .accent
	note := ui.get[TextArea]('note')!
	assert note.get_text() == 'черновик'
	assert note.placeholder == 'Текст заметки'
	status := ui.get[Label]('status')!
	assert status.color == Color{0x33, 0x66, 0x99, 255}
	assert status.font_style == .bold
	// пункты меню и узлы дерева - свои словари
	open := ui.item('open') or { panic('нет #open') }
	assert open.shortcut == 'Ctrl+O'
	assert open.icon.name == 'folder-open'
	wrap := ui.item('wrap') or { panic('нет #wrap') }
	assert wrap.checked
	assert ui.item('pdf') != none
	proj := ui.node('proj') or { panic('нет #proj') }
	assert proj.children.len == 2
	assert !proj.children[1].expanded
	// неверный тип - ошибка, а не молчаливое приведение
	ui.get[Label]('save') or { assert err.msg().contains('не Label') }
	ui.get[Label]('nope') or { assert err.msg().contains('нет #nope') }
	assert ui.ids() == ['dark', 'files', 'note', 'open', 'pdf', 'proj', 'save', 'status', 'wrap']
}

fn test_layout_params_reach_box() {
	ui := ui_parse('hbox gap=4\n  label "a" flex=2 min=10 max=90 align=center\n  label "b"\n',
		't')!
	root := ui.root
	if root is HBox {
		e := root.box.children[0]
		assert e.flex == 2 && e.min_main == 10 && e.max_main == 90 && e.own_cross
		assert e.cross == .center
		assert root.box.children[1].flex == 0
		assert root.box.spacing == 4
	} else {
		assert false, 'корень не HBox'
	}
}

fn test_grid_flows_with_colspan() {
	ui := ui_parse('grid cols=2\n  label "a" colspan=2\n  label "b"\n  label "c"\n', 't')!
	root := ui.root
	if root is GridLayout {
		assert root.cols == 2 && root.rows == 2
		assert root.cells.len == 3
		assert root.cells[0].col_span == 2
		assert root.cells[2].row == 1 && root.cells[2].col == 1
	} else {
		assert false, 'корень не GridLayout'
	}
}

fn test_list_columns_and_combo_items() {
	ui := ui_parse('vbox
  list #files selected=1
    column "Имя" width=120
    column "Размер" width=60 align=right
    item "a.txt" "1 КБ" icon=file
    item "b.png" "2 КБ"
  combo #city hint="Город" selected=0
    item "Москва" icon=map-pin
    item "Казань"
', 't')!
	lb := ui.get[ListBox]('files')!
	assert lb.columns.len == 2 && lb.rows.len == 2
	assert lb.rows[0].cells[1].text == '1 КБ'
	assert lb.rows[0].icon.name == 'file'
	assert lb.selected == 1
	cb := ui.get[ComboBox]('city')!
	assert cb.entries.len == 2 && cb.selected == 0
	assert cb.entries[0].icon.name == 'map-pin'
}

fn test_strings_comments_and_translation() {
	ui := ui_parse('label "кавычка \\" и // не комментарий" #l // а это комментарий\n', 't')!
	l := ui.get[Label]('l')!
	assert l.text == 'кавычка " и // не комментарий'
	ui2 := ui_parse('label @btn.ok #ok\n', 't')!
	assert ui2.get[Label]('ok')!.text == tr('btn.ok')
}

// Ошибки - с именем источника и номером строки.
fn test_errors_are_loud() {
	cases := {
		'vbox\n  buton "x"\n':                    't:2: неизвестный элемент buton'
		'vbox\n  label "x" colr=#fff\n':          't:2: свойство colr неприменимо к label'
		'label "x" flex=1\n':                     't:1: свойство flex неприменимо к label'
		'vbox\n  label "a" #x\n  label "b" #x\n': 't:3: #x уже есть в разметке'
		'vbox\n    label "a"\n  label "b"\n':     't:3: отступ не совпадает'
		'vbox\n\tlabel "a"\n':                    't:2: табуляция в отступе'
		'label "a"\nlabel "b"\n':                 't:2: корень должен быть один'
		'label "a" "b"\n':                        't:1: label: ожидается один текст'
		'label "a\n':                             't:1: не закрыта кавычка'
		'slider value=abc\n':                     't:1: value=abc: ожидается число'
		'button "a" style=fancy\n':               't:1: style=fancy: допустимо'
		'label "a"\n  label "b"\n':               't:2: у label не может быть вложенных'
		'tabs\n  label "a"\n':                    't:2: внутри tabs допустимо только tab'
		'split\n  label "a"\n':                   't:1: split: нужно ровно два'
		'label "a" disabled=maybe\n':             't:1: disabled=maybe: ожидается true или false'
		'':                                       't: разметка пуста'
	}
	for src, want in cases {
		ui_parse(src, 't') or {
			assert err.msg().starts_with(want), '${src.replace('\n', '|')} -> ${err.msg()}'
			continue
		}
		assert false, 'ошибка не замечена: ${src.replace('\n', '|')}'
	}
}

@[heap]
struct UiMarkupClicks {
mut:
	n int
}

// Живой интерфейс: колбэк из кода по #id срабатывает на клик через testkit.
fn test_markup_ui_is_live() {
	mut t := new_test_ui(width: 360, height: 240)!
	defer {
		t.close()
	}
	ui := ui_parse(notes_ui, 'notes.vui')!
	mut clicks := &UiMarkupClicks{}
	mut save := ui.get[Button]('save')!
	save.on_click = fn [mut clicks] () {
		clicks.n++
	}
	t.add(ui.root)
	t.click_widget(save)
	assert clicks.n == 1
	mut note := ui.get[TextArea]('note')!
	t.click_widget(note)
	t.type_text('!')
	assert note.get_text().contains('!')
}
