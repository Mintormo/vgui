module main

// Пример 61. Реактивные данные: Observable и модель-таблица RowsModel.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/61_data_binding.v

import vgui

// Таблица и список показывают одну модель RowsModel (set_model): добавили или
// удалили строку в модели - оба вида обновились сами, без invalidate и без
// копирования строк в виджеты. Подпись над таблицей привязана к Observable
// (bind): счётчик строк меняется в одном месте, подпись - следом.
//
// Как пользоваться:
//   1. данные - в модели (RowsModel или своя структура с vgui.ModelBase);
//   2. вид - widget.set_model(model);
//   3. правки - методами модели (append/remove/set_cell... или changed()).

fn main() {
	mut app := vgui.create_app()!
	mut win := vgui.create_window(title: 'Data binding - models', width: 560, height: 400)!

	mut people := vgui.rows_model([['Анна', '34'], ['Борис', '41'], ['Вера', '29']])
	mut count := vgui.observable(people.row_count())

	mut caption := vgui.label('')
	count.bind(fn [mut caption] (n int) {
		caption.text = 'Строк в модели: ${n}'
	})

	mut table := vgui.table_view()
	table.add_column('Имя', 160)
	table.add_column('Возраст', 80)
	table.set_model(people)

	mut list := vgui.list_box()
	list.set_model(people)

	mut name_input := vgui.text_input('Имя')
	mut add_btn := vgui.button('Добавить')
	add_btn.on_click = fn [mut people, mut count, mut name_input] () {
		name := name_input.get_text().trim_space()
		if name.len == 0 {
			return
		}
		people.append([name, '-'])
		count.set(people.row_count())
		name_input.set_text('')
	}
	mut del_btn := vgui.button('Удалить первую')
	del_btn.on_click = fn [mut people, mut count] () {
		people.remove(0)
		count.set(people.row_count())
	}

	mut controls := vgui.create_hbox_fill()
	controls.set_spacing(8)
	controls.add(name_input, flex: 1)
	controls.add(add_btn)
	controls.add(del_btn)

	mut views := vgui.create_hbox_fill()
	views.set_spacing(8)
	views.add(table, flex: 2)
	views.add(list, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(12)
	root.set_spacing(8)
	root.add(caption)
	root.add(views, flex: 1)
	root.add(controls)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}
