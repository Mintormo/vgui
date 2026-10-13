module vgui

import os

// Регрессионные снапшоты: несколько экранов-«галерей» с виджетами в светлой и
// тёмной теме сравниваются с эталонными PNG из testdata/snapshots/. Любая
// правка движка, сдвинувшая пиксели (раскладка, отступы, шрифты, цвета темы),
// роняет тест; рядом с эталоном появляется <имя>.actual.png - его можно
// открыть и сравнить глазами.
//
// Изменение намеренное - перезаписать эталоны и закоммитить их вместе с правкой:
//   VGUI_UPDATE_SNAPSHOTS=1 v -enable-globals test snapshot_test.v
//
// В сценах нет ничего, что зависит от времени или даты (спиннер, мигающий
// курсор, «сегодня» календаря): кадр обязан быть одинаковым при каждом запуске.
//
// Запуск: v -enable-globals test snapshot_test.v

const snapshot_dir = os.join_path(@VMODROOT, 'testdata', 'snapshots')

// snap рисует сцену build в окне w×h в обеих темах и сверяет с эталонами
// <name>_light.png / <name>_dark.png.
fn snap(name string, w int, h int, build fn () &Widget) ! {
	for theme_name, theme in {
		'light': light_theme()
		'dark':  dark_theme()
	} {
		mut t := new_test_ui(width: w, height: h, theme: theme)!
		t.add(build())
		t.redraw()
		t.match_snapshot(os.join_path(snapshot_dir, '${name}_${theme_name}.png')) or {
			t.close()
			return err
		}
		t.close()
	}
}

fn scene_controls() &Widget {
	mut col := create_vbox_fill()
	col.set_padding(12)
	col.set_spacing(8)
	col.add(label('Обычные элементы управления'))

	mut row1 := create_hbox_fill()
	row1.set_spacing(8)
	row1.add(button('Кнопка'))
	mut save := button('Сохранить')
	save.icon_name = 'save'
	row1.add(save)
	row1.add(badge_count(7))
	col.add(row1)

	mut row2 := create_hbox_fill()
	row2.set_spacing(12)
	mut cb := checkbox('Флажок')
	cb.set_checked(true)
	row2.add(cb)
	row2.add(checkbox('Выключен'))
	mut rb := radio_button('Выбор')
	rb.set_selected(true)
	row2.add(rb)
	mut ts := toggle_switch('Тумблер')
	ts.set_on(true)
	row2.add(ts)
	col.add(row2)

	col.add(slider_horizontal(0, 100, 35))
	mut pb := progress_bar()
	pb.set_percent(60)
	col.add(pb)

	mut row3 := create_hbox_fill()
	row3.set_spacing(8)
	mut ti := text_input('подсказка')
	ti.set_text('Текст в поле')
	row3.add(ti, flex: 1)
	row3.add(text_input('пустое поле'), flex: 1)
	col.add(row3)

	mut row4 := create_hbox_fill()
	row4.set_spacing(8)
	mut combo := combo_box()
	combo.add_icon_item('Москва', item_icon('map-pin'))
	combo.add_item('Казань')
	combo.set_selected(0)
	row4.add(combo, flex: 1)
	row4.add(spinbox(), flex: 1)
	col.add(row4)
	col.add(separator())
	return col
}

fn scene_lists() &Widget {
	mut lb := list_box()
	lb.add_column('Имя', 120)
	lb.add_column('Размер', 70)
	lb.add_row_texts(['README.md', '4 КБ'])
	lb.add_row_texts(['logo.png', '120 КБ'])
	lb.add_row_texts(['main.v', '12 КБ'])
	lb.set_row_icon(0, item_icon('file-text'))
	lb.set_row_icon(1, item_icon('image'))
	lb.set_row_icon(2, item_icon('file-code'))
	lb.set_selected(1)

	mut tv := tree_view()
	mut root := tree_node_with('проект', item_icon('folder'))
	mut src := tree_node_with('src', item_icon('folder'))
	src.add(tree_node_with('app.v', item_icon('file-code')))
	root.add(src)
	root.add(tree_node_with('notes.txt', item_icon('file-text')))
	tv.add_root(root)

	mut tbl := table_view()
	tbl.add_column('A', 60)
	tbl.add_column('B', 60)
	tbl.add_column('C', 60)
	tbl.add_row(['1', '2', '3'])
	tbl.add_row(['4', '5', '6'])

	mut top := create_hbox_fill()
	top.set_spacing(8)
	top.add(lb, flex: 1)
	top.add(tv, flex: 1)
	mut col := create_vbox_fill()
	col.set_padding(12)
	col.set_spacing(8)
	col.add(top, flex: 1)
	col.add(tbl, flex: 1)
	return col
}

fn scene_text() &Widget {
	mut ed := code_editor()
	ed.set_text('fn main() {\n\tprintln("привет")\n}\n')
	mut md := markdown_view()
	md.set_text('# Заголовок\n\nАбзац с **жирным** и `кодом`.\n\n- пункт один\n- пункт два\n')
	mut ta := text_area('заметки')
	ta.set_text('Многострочный\nтекст')
	mut col := create_vbox_fill()
	col.set_padding(12)
	col.set_spacing(8)
	col.add(ed, flex: 1)
	col.add(md, flex: 1)
	col.add(ta, flex: 1)
	return col
}

fn scene_containers() &Widget {
	mut tabs := tab_box()
	tabs.add_tab_icon('Главная', item_icon('house'), label('Содержимое вкладки'))
	tabs.add_tab('Вторая', label('Вторая'))

	mut acc := accordion_single()
	acc.add_section_expanded('Раскрыта', label('Текст секции'))
	acc.set_section_icon(0, item_icon('user'))
	acc.add_section('Свёрнута', label('скрыто'))

	mut pg := property_grid()
	pg.add_string('Имя', 'vgui')
	pg.add_int('Версия', 7)
	pg.add_bool('Включено', true)

	mut bc := breadcrumbs()
	bc.set_path_from_string('home/igor/projects', '/')

	mut row := create_hbox_fill()
	row.set_spacing(8)
	row.add(tabs, flex: 1)
	row.add(acc, flex: 1)
	mut col := create_vbox_fill()
	col.set_padding(12)
	col.set_spacing(8)
	col.add(bc)
	col.add(row, flex: 1)
	col.add(pg, flex: 1)
	return col
}

fn test_snapshot_controls() {
	snap('controls', 480, 360, scene_controls)!
}

fn test_snapshot_lists() {
	snap('lists', 480, 360, scene_lists)!
}

fn test_snapshot_text() {
	snap('text', 480, 420, scene_text)!
}

fn test_snapshot_containers() {
	snap('containers', 480, 380, scene_containers)!
}
