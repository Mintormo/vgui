module main

import vgui

// Авто-раскладка: размеры берутся из самих виджетов, в разметке
// их нет совсем.
//
// add(widget)           - естественный размер: кнопка под свой
//                         текст, метка под строку; поле ввода,
//                         ползунок, список растут в свободное место;
// add(widget, flex: n)  - доля свободного места;
// add(widget, min: .., max: .., align: ..) - ограничения и
//                         выравнивание поперёк оси.
//
// Кнопки не подгоняются на глаз: у каждой своя ширина, и при смене
// языка или размера шрифта они подстроятся сами.

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Авто-раскладка (measure)')!

	// ─── Строка 1: иконка + метка + кнопка ───────────────
	//
	// Иконка и метка занимают ровно столько, сколько просят,
	// Spacer съедает остаток, кнопка прижата вправо.
	mut ic := vgui.icon('info')
	ic.set_size(20)

	mut row1 := vgui.create_hbox_fill()
	row1.set_spacing(8)
	row1.set_cross_align(.center) // по вертикали — по центру, а не на всю высоту
	row1.add(ic)
	row1.add(vgui.label('add(w): ширина по содержимому'))
	row1.add(vgui.create_spacer(), flex: 1)
	row1.add(vgui.button('Кнопка'))

	// ─── Строка 2: кнопки разной длины ───────────────────
	//
	// Каждая получает свою ширину; min - нижняя граница, чтобы
	// короткие подписи не выглядели куцыми.
	mut row2 := vgui.create_hbox_fill()
	row2.set_spacing(8)
	row2.set_cross_align(.center)
	for text in ['ОК', 'Отмена', 'Сохранить как…',
		'Применить ко всем'] {
		row2.add(vgui.button(text), min: 90)
	}
	row2.add(vgui.create_spacer(), flex: 1)

	// ─── Строка 3: выравнивание поперёк оси ──────────────
	//
	// Высоту ряда задаёт самый высокий сосед (метка в три строки),
	// кнопки встают по-разному.
	mut row3 := vgui.create_hbox_fill()
	row3.set_spacing(8)
	row3.add(vgui.label('align:\nвыравнивание\nпоперёк оси'))
	row3.add(vgui.button('start'), align: .start)
	row3.add(vgui.button('center'), align: .center)
	row3.add(vgui.button('end'), align: .end)
	row3.add(vgui.button('stretch'), align: .stretch)
	row3.add(vgui.create_spacer(), flex: 1)

	// ─── Форма на сетке с авто-колонкой ──────────────────
	//
	// Колонка подписей сжимается до самой длинной подписи,
	// поля ввода забирают всё остальное — без ручного
	// подбора ширины.
	mut form := vgui.create_grid(2, 3)
	form.set_spacing(8, 8)
	form.set_col_auto(0)
	form.set_col_weight(1, 1)
	labels := ['Имя:', 'Электронная почта:', 'Комментарий:']
	for i, text in labels {
		mut l := vgui.label(text)
		l.valign = .middle
		form.add(l, i, 0)
		form.add(vgui.text_input(''), i, 1)
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(row1)
	root.add(vgui.hseparator())
	root.add(row2)
	root.add(row3)
	root.add(vgui.hseparator())
	root.add(form)
	root.add(vgui.create_spacer(), flex: 1)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
