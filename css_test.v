module vgui

import os

// Тесты стилей CSS (css.v, css_props.v, css_apply.v): разбор и громкие ошибки
// с номером строки, полнота таблицы свойств, каскад (специфичность и порядок),
// сопоставление селекторов с цепочкой предков и живая отрисовка через testkit -
// цвет пикселей действительно меняется, а тема после виджета восстанавливается.
//
// Запуск: SDL_VIDEODRIVER=dummy v test css_test.v

const red = Color{255, 0, 0, 255}
const green = Color{0, 255, 0, 255}
const blue = Color{0, 0, 255, 255}

// css_err — текст ошибки разбора (пусто - ошибки нет).
fn css_err(text string) string {
	parse_stylesheet(text, 't.css') or { return err.msg() }
	return ''
}

// ─── Разбор ────────────────────────────────────────────

fn test_parse_rules_and_values() {
	ss := parse_stylesheet('
		/* комментарий
		   на две строки */
		:root { --brand: #3b82f6; accent-color: var(--brand); border-radius: 8px; }
		button, .x { background: #f00; }
		.bar > list:selected { background: rgb(0, 0, 255); color: white; }
		menu:hover { background: #0f0a; }
	', 't.css')!
	assert ss.root_rules.len == 2
	assert ss.rules.len == 3
	assert ss.vars['brand'] == '#3b82f6'
	// .bar > list:selected: субъект - list, предок - .bar прямым родителем
	mut found := false
	for r in ss.rules {
		if r.selector.text == '.bar > list:selected' {
			found = true
			assert r.selector.parts.len == 2
			assert r.selector.parts[0].kind == kind_list_box
			assert r.selector.parts[0].rel == .child
			assert r.selector.parts[1].classes == ['bar']
			assert r.selector.pseudo == 'selected'
			assert r.decls[0].fields_by_kind[kind_list_box] == ['lb_row_selected']
			assert r.decls[0].value.color == blue
		}
	}
	assert found
	// #0f0a - короткая запись с альфой
	assert ss.root_rules[1].decls[0].value.color == Color{0, 255, 0, 170}
}

fn test_parse_errors_are_loud_with_line() {
	assert css_err('button { colr: red; }').contains('t.css:1: свойство colr неприменимо к button')
	assert css_err('\n\nbuton { color: red; }').contains('t.css:3:')
	assert css_err('buton { color: red; }').contains('неизвестный тип элемента buton')
	assert css_err('.a:hover button { color: red; }').contains('только у последнего звена')
	assert css_err('button:focused { color: red; }').contains('состояние :focused неизвестно')
	assert css_err('button { color: var(--nope); }').contains('--nope не объявлена')
	assert css_err('button { border-radius: red; }').contains('ожидается число')
	assert css_err('button { color: 5; }').contains('ожидается цвет')
	assert css_err('button { color: transparent; }').contains('альфа 0')
	assert css_err('button { color: #12345; }').contains('ожидается цвет #rgb')
	assert css_err('button { color: red !important; }').contains('!important')
	assert css_err('@media x { }').contains('@-правила')
	assert css_err('button { color: red; ').contains('не закрыт')
	assert css_err('button { color: red; color: blue }').contains('дважды')
	assert css_err('.x menu { color: red; }').contains('попап')
	assert css_err('button { --no-such-field: red; }').contains('такого поля темы нет')
	assert css_err('button:hover { --button-bg: red; }').contains('состояние')
	assert css_err('button { --control-height: 40; }').contains('только в :root')
	assert css_err(':root { --control-height: 40; }') == ''
	assert css_err('.x { header-colour: red; }').contains('неизвестно ни одному элементу')
	// подсказка перечисляет допустимые свойства
	assert css_err('slider { colr: red; }').contains('fill-color')
}

fn test_theme_field_escape_hatch() {
	ss := parse_stylesheet(':root { --lb-row-alt-bg: #010203; } list { --tv-grid: #040506; }',
		't.css')!
	t := css_base_theme(light_theme(), ss)
	assert t.lb_row_alt_bg == Color{1, 2, 3, 255}
	assert ss.rules[0].decls[0].fields_by_kind[kind_list_box] == ['tv_grid']
}

// Каждое поле из таблицы свойств существует в Theme - опечатка в таблице
// иначе всплыла бы только у того, кто напишет это свойство.
fn test_prop_table_fields_exist() {
	for key, fields in css_prop_table {
		for f in fields {
			// @padding/@gap/@margin/@width... - отступы и размеры виджета (CssBox), не поля Theme
			if f.starts_with('@') {
				assert f in [css_padding_field, css_gap_field, css_margin_field] || f in css_size_fields, '${key}: неизвестное поле ${f}'
				continue
			}
			assert css_theme_has_field(f), '${key}: в Theme нет поля ${f}'
		}
		owner := key.all_before(':')
		assert owner == '*' || owner == 'root' || owner in css_root_types
			|| owner in css_kind_by_name, '${key}: неизвестный тип ${owner}'
	}
	// у каждого типа из таблицы имён есть обратная запись
	for name, kind in css_kind_by_name {
		assert css_name_by_kind[kind] == name
	}
}

// ─── Каскад и селекторы ────────────────────────────────

fn test_rules_sorted_by_specificity_then_order() {
	ss := parse_stylesheet('
		#a { color: #000001; }
		.c.d { color: #000002; }
		button { color: #000003; }
		.c { color: #000004; }
		button.c { color: #000005; }
	', 't.css')!
	got := ss.rules.map(it.selector.text)
	assert got == ['button', '.c', 'button.c', '.c.d', '#a']
}

fn css_node(kind int, id string, classes []string) CssNode {
	return CssNode{
		kind: kind
		tags: CssTags{
			id:      id
			classes: classes
		}
	}
}

fn sel_of(text string) CssSelector {
	ss := parse_stylesheet('${text} { accent-color: red; }', 't.css') or { panic(err) }
	return ss.rules[0].selector
}

fn test_selector_matching() {
	// окно: vbox.sidebar > panel > hbox > button#ok.big
	stack := [css_node(kind_vbox, '', ['sidebar']), css_node(kind_panel, '', []),
		css_node(kind_hbox, '', []), css_node(kind_button, 'ok', ['big', 'x'])]
	assert css_selector_matches(sel_of('button'), stack)
	assert css_selector_matches(sel_of('*'), stack)
	assert css_selector_matches(sel_of('#ok'), stack)
	assert css_selector_matches(sel_of('button.big.x#ok'), stack)
	assert !css_selector_matches(sel_of('button.big.y'), stack)
	assert !css_selector_matches(sel_of('label'), stack)
	assert css_selector_matches(sel_of('.sidebar button'), stack)
	assert css_selector_matches(sel_of('.sidebar panel button'), stack)
	assert css_selector_matches(sel_of('hbox > button'), stack)
	assert !css_selector_matches(sel_of('panel > button'), stack)
	assert css_selector_matches(sel_of('.sidebar > panel button'), stack)
	assert !css_selector_matches(sel_of('.sidebar > hbox button'), stack)
	// состояние на сопоставление не влияет: это выбор поля темы
	assert css_selector_matches(sel_of('.sidebar button:hover'), stack)
	// с возвратом: первый найденный hbox не годится, годится следующий выше
	deep := [css_node(kind_vbox, '', ['a']), css_node(kind_hbox, '', []), css_node(kind_vbox, '', []),
		css_node(kind_hbox, '', []), css_node(kind_button, '', [])]
	assert css_selector_matches(sel_of('.a > hbox button'), deep)
}

// ─── Метки виджетов ────────────────────────────────────

fn test_css_tags_api() {
	mut b := button('ok')
	mut w := Widget(b)
	set_css_id(mut w, 'save')
	add_css_class(mut w, 'danger')
	add_css_class(mut w, 'danger')
	add_css_class(mut w, 'big')
	assert b.css.id == 'save'
	assert b.css.classes == ['danger', 'big']
	assert has_css_class(&w, 'big')
	remove_css_class(mut w, 'danger')
	assert b.css.classes == ['big']
	assert !has_css_class(&w, 'danger')
}

fn test_vui_classes_and_ids_become_css_tags() {
	ui := ui_parse('vbox .sidebar .dark\n  button "A" #save .danger\n', 't.vui')!
	root := ui.root
	assert css_tags_of(root).classes == ['sidebar', 'dark']
	save := ui.get[Button]('save')!
	assert save.css.id == 'save'
	assert save.css.classes == ['danger']
	// классы - только у виджетов
	ui_parse('tabs\n  tab "A" .x\n    label "a"\n', 't.vui') or {
		assert err.msg().contains('класс неприменим к tab')
		return
	}
	assert false
}

// ─── Живая отрисовка ───────────────────────────────────

// left_px — пиксель у левого края виджета посередине высоты: внутри фона, но
// мимо скругления углов и текста по центру.
fn left_px(f &Frame, r Rect) Color {
	return f.px(int(r.x) + 5, int(r.y + r.h / 2))
}

fn test_class_rule_colors_only_its_button() {
	mut t := new_test_ui(width: 300, height: 120)!
	defer {
		t.close()
	}
	mut box := create_vbox_fill()
	mut plain := button('plain')
	mut danger := button('danger')
	danger.css.classes = ['danger']
	box.add(plain)
	box.add(danger)
	t.app.set_stylesheet(parse_stylesheet('.danger { background: #ff0000; }', 't.css')!)
	t.add(box)
	t.frame()
	f := t.capture()
	assert left_px(f, danger.bounds) == red
	assert left_px(f, plain.bounds) != red
	// тема после отрисовки восстановлена
	assert t.win.ctx.theme.button_bg == light_theme().button_bg
	assert t.win.ctx.css_stack.len == 0
}

fn test_descendant_rule_and_id_beats_class() {
	mut t := new_test_ui(width: 300, height: 160)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut side := create_vbox_fill()
	side.css.classes = ['sidebar']
	mut inside := button('in')
	mut special := button('special')
	special.css.id = 'special'
	side.add(inside)
	side.add(special)
	mut outside := button('out')
	root.add(side)
	root.add(outside)
	t.app.set_stylesheet(parse_stylesheet('
		#special { background: #0000ff; }
		.sidebar button { background: #00ff00; }
	', 't.css')!)
	t.add(root)
	t.frame()
	f := t.capture()
	assert left_px(f, inside.bounds) == green
	assert left_px(f, special.bounds) == blue // #id специфичнее, хоть и выше в файле
	assert left_px(f, outside.bounds) != green
}

fn test_root_rules_and_container_fill() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut boxed := create_vbox_fill()
	boxed.css.classes = ['card']
	boxed.set_padding(10)
	boxed.add(label('x'))
	root.add(boxed, flex: 1)
	t.app.set_stylesheet(parse_stylesheet('
		:root { background: #0000ff; }
		.card { background: #00ff00; }
		menu { background: #ff0000; }
	', 't.css')!)
	t.add(root)
	t.frame()
	assert t.win.ctx.theme.bg == blue
	assert t.win.ctx.theme.menu_bg == red // корневые правила - в теме окна
	f := t.capture()
	// заливка vbox.card под детьми - в углу контейнера (там отступ, детей нет)
	assert f.px(int(boxed.box.bounds.x) + 2, int(boxed.box.bounds.y) + 2) == green
	// смена темы окна сохраняет корневые правила стилей (окно TestUi - с
	// явной темой, поэтому set_theme самого окна, а не приложения)
	t.win.set_theme(dark_theme())
	assert t.win.ctx.theme.bg == blue
	assert t.win.ctx.theme.text_primary == dark_theme().text_primary
	// снятие стилей возвращает тему как есть
	t.app.set_stylesheet(unsafe { nil })
	assert t.win.ctx.theme.bg == dark_theme().bg
}

fn test_window_nil_stylesheet_returns_to_app_stylesheet() {
	mut t := new_test_ui(width: 200, height: 80)!
	defer {
		t.close()
	}
	app_ss := parse_stylesheet(':root { background: #ff0000; }', 'app.css')!
	own_ss := parse_stylesheet(':root { background: #00ff00; }', 'own.css')!
	t.app.set_stylesheet(app_ss)
	t.win.set_stylesheet(own_ss)
	assert t.win.ctx.theme.bg == green
	// своя таблица: смена таблицы приложения окно не трогает, но запоминается
	app2 := parse_stylesheet(':root { background: #0000ff; }', 'app2.css')!
	t.app.set_stylesheet(app2)
	assert t.win.ctx.theme.bg == green
	// nil - назад к ТЕКУЩЕЙ таблице приложения, и окно снова ей следует
	t.win.set_stylesheet(unsafe { nil })
	assert t.win.ctx.stylesheet == app2
	assert t.win.ctx.theme.bg == blue
	t.app.set_stylesheet(app_ss)
	assert t.win.ctx.theme.bg == red
	// окно без стилей при стилях приложения - пустая таблица
	t.win.set_stylesheet(parse_stylesheet('', 'none')!)
	assert t.win.ctx.theme.bg == light_theme().bg
}

fn test_hot_reload_keeps_old_styles_on_error() {
	mut t := new_test_ui(width: 200, height: 80)!
	defer {
		t.close()
	}
	dir := os.join_path(os.temp_dir(), 'vgui_css_test_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'app.css')
	os.write_file(path, ':root { background: #ff0000; }')!
	t.app.load_stylesheet(path, true)!
	assert t.win.ctx.theme.bg == red
	// изменение файла: mtime с точностью до секунды, поэтому сбрасываем
	// запомненный, а не ждём секунду
	os.write_file(path, ':root { background: #00ff00; }')!
	t.app.css_mtime = 0
	t.app.css_next_check = 0
	assert t.app.poll_stylesheet()
	assert t.win.ctx.theme.bg == green
	// ошибка в файле - стили прежние, приложение живо
	os.write_file(path, ':root { background: nonsense; }')!
	t.app.css_mtime = 0
	t.app.css_next_check = 0
	assert !t.app.poll_stylesheet()
	assert t.win.ctx.theme.bg == green
}

// У каждого типа виджета есть поле `css` (CssTags) - иначе #id и классы
// селекторов к нему не применить. Проверка - при компиляции: структура без
// поля не приводится к CssTagged, и тест не соберётся. Список - тот же, что
// в widget_tag_test.v (все kind_*); новый виджет - добавить и сюда.
fn test_every_widget_type_has_css_tags() {
	tagged := [
		CssTagged(&Label{}),
		CssTagged(&Button{}),
		CssTagged(&VBox{}),
		CssTagged(&HBox{}),
		CssTagged(&Panel{}),
		CssTagged(&Spacer{}),
		CssTagged(&TextInput{}),
		CssTagged(&CheckBox{}),
		CssTagged(&Slider{}),
		CssTagged(&ProgressBar{}),
		CssTagged(&Separator{}),
		CssTagged(&ToggleSwitch{}),
		CssTagged(&Spinner{}),
		CssTagged(&RadioButton{}),
		CssTagged(&Spinbox{}),
		CssTagged(&ComboBox{}),
		CssTagged(&ImageView{}),
		CssTagged(&ListBox{}),
		CssTagged(&TabBox{}),
		CssTagged(&Accordion{}),
		CssTagged(&Notification{}),
		CssTagged(&Breadcrumbs{}),
		CssTagged(&ColorPicker{}),
		CssTagged(&DatePicker{}),
		CssTagged(&Splitter{}),
		CssTagged(&DockArea{}),
		CssTagged(&CodeEditor{}),
		CssTagged(&MarkdownView{}),
		CssTagged(&MenuButton{}),
		CssTagged(&MenuItem{}),
		CssTagged(&ContextMenu{}),
		CssTagged(&MenuBar{}),
		CssTagged(&PlotView{}),
		CssTagged(&PropertyGrid{}),
		CssTagged(&Property{}),
		CssTagged(&TableView{}),
		CssTagged(&TreeView{}),
		CssTagged(&TreeNode{}),
		CssTagged(&NotificationManager{}),
		CssTagged(&Stack{}),
		CssTagged(&Centered{}),
		CssTagged(&WindowTitleDrag{}),
		CssTagged(&ScrollBox{}),
		CssTagged(&TextArea{}),
		CssTagged(&Badge{}),
		CssTagged(&Calendar{}),
		CssTagged(&Tooltip{}),
		CssTagged(&GridLayout{}),
		CssTagged(&DropZone{}),
		CssTagged(&ImageBackground{}),
		CssTagged(&Canvas{}),
		CssTagged(&Icon{}),
		CssTagged(&CurveEditor{}),
		CssTagged(&ShortcutInput{}),
	]
	assert tagged.len == css_max_kind
}
