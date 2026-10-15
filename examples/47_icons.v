module main

// Пример 47. Icon: иконки встроенного шрифта Lucide - сетка, размеры, цвета, иконка рядом с текстом.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/47_icons.v

import vgui

// Icon - glyphs from the embedded Lucide icon font (ISC license). Shows a
// grid of icons with labels, a few sizes/colors, and Icon next to text.
const icon_names_demo = [
	'home',
	'search',
	'settings',
	'user',
	'heart',
	'star',
	'bell',
	'mail',
	'calendar',
	'clock',
	'camera',
	'image',
	'file',
	'folder',
	'download',
	'upload',
	'trash-2',
	'edit',
	'copy',
	'check',
	'x',
	'plus',
	'minus',
	'arrow-up',
	'arrow-down',
	'arrow-left',
	'arrow-right',
	'chevron-down',
	'lock',
	'unlock',
	'eye',
	'eye-off',
	'wifi',
	'battery',
	'sun',
	'moon',
	'play',
	'pause',
	'volume-2',
	'music',
]

fn build_icon_cell(name string, size int) &vgui.VBox {
	mut cell := vgui.create_vbox_fill()
	cell.set_spacing(4)
	mut ic := vgui.icon(name)
	ic.size = size
	cell.add(ic)
	mut lbl := vgui.label(name)
	lbl.align = .center
	lbl.font_size = 11
	lbl.color = vgui.Color{160, 160, 160, 255}
	cell.add(lbl)
	return cell
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Icon - Lucide icon font demo')!

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)

	mut title := vgui.label('Lucide icon font demo (showing ${icon_names_demo.len} of the bundled set)')
	title.font_size = 14
	root.add(title)

	mut exists_row := vgui.create_hbox_fill()
	exists_row.set_spacing(8)
	exists_row.add(vgui.label("Icon.exists('check') = ${vgui.icon_exists('check')}"))
	exists_row.add(vgui.label("Icon.exists('no-such-icon') = ${vgui.icon_exists('no-such-icon')}"))
	root.add(exists_row)

	mut grid_scroll := vgui.scroll_box(0)
	mut grid_col := vgui.create_vbox_fill()
	grid_col.set_spacing(10)
	per_row := 10
	mut i := 0
	for i < icon_names_demo.len {
		mut row := vgui.create_hbox_fill()
		row.set_spacing(6)
		end := if i + per_row < icon_names_demo.len { i + per_row } else { icon_names_demo.len }
		for j in i .. end {
			row.add(build_icon_cell(icon_names_demo[j], 24))
		}
		row.add(vgui.create_spacer(), flex: 1)
		grid_col.add(row)
		i += per_row
	}
	grid_scroll.add(grid_col)
	root.add(grid_scroll, flex: 1)

	mut sizes_row := vgui.create_hbox_fill()
	sizes_row.set_spacing(14)
	sizes_row.add(vgui.label('Sizes:'))
	for sz in [12, 16, 24, 32, 48] {
		mut ic := vgui.icon('star')
		ic.size = sz
		sizes_row.add(ic)
	}
	root.add(sizes_row)

	mut colors_row := vgui.create_hbox_fill()
	colors_row.set_spacing(14)
	colors_row.add(vgui.label('Colors:'))
	colors := [
		vgui.Color{230, 90, 90, 255},
		vgui.Color{90, 200, 120, 255},
		vgui.Color{90, 160, 240, 255},
		vgui.Color{235, 175, 60, 255},
	]
	for c in colors {
		mut ic := vgui.icon('heart')
		ic.size = 24
		ic.color = c
		colors_row.add(ic)
	}
	root.add(colors_row)

	mut line_row := vgui.create_hbox_fill()
	line_row.set_spacing(6)
	mut bell_icon := vgui.icon('bell')
	bell_icon.size = 18
	line_row.add(bell_icon)
	line_row.add(vgui.label('You have 3 new notifications'))
	root.add(line_row)

	mut save_btn := vgui.button('Save')
	save_btn.icon_name = 'check'
	save_btn.style = .accent
	mut delete_btn := vgui.button('Delete')
	delete_btn.icon_name = 'trash-2'
	delete_btn.style = .danger
	mut settings_btn := vgui.button('')
	settings_btn.icon_name = 'settings'

	mut btn_row := vgui.create_hbox_fill()
	btn_row.set_spacing(10)
	btn_row.add(save_btn)
	btn_row.add(delete_btn)
	btn_row.add(settings_btn)
	root.add(btn_row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
