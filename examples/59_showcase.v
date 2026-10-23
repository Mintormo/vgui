module main

// Пример 59. Витрина: одно окно с меню, деревом, редактором кода, таблицей,
// графиком, кривой и основными элементами управления. По нему сняты
// скриншоты в README; подписи на английском.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/59_showcase.v          # тёмная тема
//   ~/soft/v/v run examples/59_showcase.v light    # светлая
//   ~/soft/v/v run examples/59_showcase.v aqua     # Mac OS X Aqua
// Тему можно сменить и на ходу - списком в правой колонке.
import math
import os
import vgui

const sample_code = "module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Hello')!
	mut btn := vgui.button('Click me')
	btn.on_click = fn () {
		println('clicked')
	}
	win.add_widget(btn)
	app.add_window(win)
	app.run()
}
"

fn f_sin(x f32) f32 {
	return f32(math.sin(x))
}

fn f_damped(x f32) f32 {
	return f32(math.cos(x * 2) * math.exp(-math.abs(x) / 4))
}

struct ThemeEntry {
	name  string
	icon  string
	theme vgui.Theme
}

fn showcase_themes() []ThemeEntry {
	return [
		ThemeEntry{'Dark', 'moon', vgui.dark_theme()},
		ThemeEntry{'Light', 'sun', vgui.light_theme()},
		ThemeEntry{'Mac OS X Aqua', 'droplet', vgui.mac_os_x_aqua_theme()},
		ThemeEntry{'Monokai', 'palette', vgui.monokai_theme()},
	]
}

// theme_index - тема из аргумента командной строки (dark, light, aqua, monokai)
fn theme_index() int {
	arg := if os.args.len > 1 { os.args[1] } else { '' }
	return match arg {
		'light' { 1 }
		'aqua' { 2 }
		'monokai' { 3 }
		else { 0 }
	}
}

// set_palette подбирает цвета подсветки под фон темы: палитра KeywordHighlighter
// по умолчанию рассчитана на тёмный фон, на светлом обычный текст не виден
fn set_palette(mut hl vgui.KeywordHighlighter, th vgui.Theme) {
	if int(th.bg.r) + int(th.bg.g) + int(th.bg.b) > 3 * 128 {
		hl.keyword_color = vgui.Color{166, 38, 164, 255}
		hl.type_color = vgui.Color{193, 132, 1, 255}
		hl.builtin_color = vgui.Color{64, 120, 242, 255}
		hl.string_color = vgui.Color{80, 161, 79, 255}
		hl.comment_color = vgui.Color{160, 161, 167, 255}
		hl.number_color = vgui.Color{152, 104, 1, 255}
		hl.default_color = vgui.Color{56, 58, 66, 255}
	} else {
		d := vgui.KeywordHighlighter{}
		hl.keyword_color = d.keyword_color
		hl.type_color = d.type_color
		hl.builtin_color = d.builtin_color
		hl.string_color = d.string_color
		hl.comment_color = d.comment_color
		hl.number_color = d.number_color
		hl.default_color = d.default_color
	}
}

// heading - заголовок группы в правой колонке
fn heading(text string) &vgui.Label {
	mut l := vgui.label(text)
	l.font_style = .bold
	return l
}

fn main() {
	themes := showcase_themes()
	start := theme_index()
	mut app := vgui.create_app(theme: themes[start].theme)!
	mut win := vgui.create_window(title: 'vgui showcase', width: 1280, height: 800)!

	mut status := vgui.label('Ready')

	// Меню
	mut bar := vgui.menu_bar()
	mut m_open := vgui.menu_action_lucide('Open...', 'folder-open')
	m_open.shortcut = 'Ctrl+O'
	mut m_save := vgui.menu_action_lucide('Save', 'save')
	m_save.shortcut = 'Ctrl+S'
	mut m_quit := vgui.menu_action('Quit')
	m_quit.on_click = fn [mut app] () {
		app.quit()
	}
	bar.add_menu('File', [vgui.menu_action_lucide('New', 'file-plus'), m_open, m_save,
		vgui.menu_separator(), m_quit])
	bar.add_menu('Edit', [vgui.menu_action_lucide('Undo', 'undo-2'),
		vgui.menu_action_lucide('Redo', 'redo-2')])
	bar.add_menu('View', [vgui.menu_action('Zoom in'), vgui.menu_action('Zoom out')])
	bar.add_menu('Help', [vgui.menu_action_lucide('About', 'info')])

	// Слева - дерево проекта
	mut tv := vgui.tree_view()
	mut project := vgui.tree_node_with('my_app', vgui.item_icon('folder'))
	mut src := vgui.tree_node_with('src', vgui.item_icon('folder'))
	src.add(vgui.tree_node_with('main.v', vgui.item_icon('file-code')))
	src.add(vgui.tree_node_with('window.v', vgui.item_icon('file-code')))
	src.add(vgui.tree_node_with('settings.v', vgui.item_icon('file-code')))
	project.add(src)
	mut assets := vgui.tree_node_with('assets', vgui.item_icon('folder'))
	assets.add(vgui.tree_node_with('logo.png', vgui.item_icon('image')))
	assets.add(vgui.tree_node_with('app.css', vgui.item_icon('palette')))
	project.add(assets)
	project.add(vgui.tree_node_with('README.md', vgui.item_icon('file-text')))
	project.add(vgui.tree_node_with('v.mod', vgui.item_icon('package')))
	tv.add_root(project)

	mut lb := vgui.list_box()
	for name, ic in {
		'Inbox':   'inbox'
		'Sent':    'send'
		'Drafts':  'file-pen'
		'Starred': 'star'
		'Trash':   'trash-2'
	} {
		lb.add_item_icon(name, vgui.item_icon(ic))
	}
	lb.on_select = fn [mut status] (_ int, text string) {
		status.text = 'Selected: ${text}'
	}

	mut left := vgui.create_vbox_fill()
	left.set_spacing(8)
	left.add(heading('Project'))
	left.add(tv, flex: 3)
	left.add(heading('Mail'))
	left.add(lb, flex: 2)

	// Середина - вкладки (код, таблица) и график
	mut hl := vgui.v_highlighter()
	set_palette(mut hl, themes[start].theme)
	mut ed := vgui.code_editor()
	ed.set_highlighter(hl)
	ed.set_text(sample_code)

	mut table := vgui.table_view()
	table.add_column('Name', 150)
	table.add_column('Kind', 120)
	table.add_column('Size', 90)
	table.add_row(['main.v', 'source', '2.1 KB'])
	table.add_row(['window.v', 'source', '5.8 KB'])
	table.add_row(['logo.png', 'image', '48 KB'])
	table.add_row(['app.css', 'stylesheet', '1.2 KB'])
	table.add_row(['README.md', 'text', '3.4 KB'])

	mut tabs := vgui.tab_box()
	tabs.add_tab_icon('Editor', vgui.item_icon('code'), ed)
	tabs.add_tab_icon('Table', vgui.item_icon('table'), table)

	mut plot := vgui.plot_view()
	plot.add_function_named('sin(x)', f_sin, vgui.Color{66, 165, 245, 255})
	plot.add_function_named('damped cos', f_damped, vgui.Color{255, 140, 40, 255})
	plot.set_range(-2 * math.pi, 2 * math.pi, -1.4, 1.4)

	mut middle := vgui.create_vbox_fill()
	middle.set_spacing(8)
	middle.add(tabs, flex: 3)
	middle.add(plot, flex: 2)

	// Справа - элементы управления
	mut theme_cb := vgui.combo_box()
	for th in themes {
		theme_cb.add_icon_item(th.name, vgui.item_icon(th.icon))
	}
	theme_cb.set_selected(start)
	theme_cb.on_change = fn [mut app, mut hl, themes, mut status] (idx int, name string) {
		set_palette(mut hl, themes[idx].theme)
		app.set_theme(themes[idx].theme)
		status.text = 'Theme: ${name}'
	}

	mut name := vgui.text_input('Search...')

	mut s_exp := vgui.slider_horizontal(-100, 100, 35)
	s_exp.show_value = true
	mut s_con := vgui.slider_horizontal(0, 100, 60)
	s_con.show_value = true

	mut sp := vgui.spinbox()
	sp.set_range(1, 100)
	sp.set_value(24)
	sp.set_suffix(' px')

	mut ts_wifi := vgui.toggle_switch('Auto save')
	ts_wifi.set_on(true)
	mut ts_sync := vgui.toggle_switch('Sync')

	mut cb1 := vgui.checkbox('Show grid')
	cb1.set_checked(true)
	mut cb2 := vgui.checkbox('Snap to pixels')

	mut r1 := vgui.radio_button('Small')
	r1.radio_group = 'size'
	mut r2 := vgui.radio_button('Medium')
	r2.radio_group = 'size'
	r2.selected = true
	mut r3 := vgui.radio_button('Large')
	r3.radio_group = 'size'
	mut radios := vgui.create_hbox_fill()
	radios.set_spacing(12)
	radios.add(r1)
	radios.add(r2)
	radios.add(r3)

	mut pb := vgui.progress_bar()
	pb.set_value(0.65)

	mut b_info := vgui.badge('INFO')
	b_info.variant = .info
	mut b_ok := vgui.badge('DONE')
	b_ok.variant = .success
	mut b_warn := vgui.badge('BETA')
	b_warn.variant = .warning
	mut badges := vgui.create_hbox_fill()
	badges.set_spacing(6)
	badges.add(b_info)
	badges.add(b_ok)
	badges.add(b_warn)
	badges.add(vgui.badge_count(7))

	mut ce := vgui.curve_editor()
	ce.set_points([vgui.CurvePoint{0, 0}, vgui.CurvePoint{0.25, 0.18}, vgui.CurvePoint{0.75, 0.86},
		vgui.CurvePoint{1, 1}])

	mut b_cancel := vgui.button('Cancel')
	b_cancel.style = .outline
	mut b_apply := vgui.button('Apply')
	b_apply.style = .accent
	b_apply.on_click = fn [mut status] () {
		status.text = 'Applied'
	}
	mut buttons := vgui.create_hbox_fill()
	buttons.set_spacing(8)
	buttons.add(b_cancel, flex: 1)
	buttons.add(b_apply, flex: 1)

	mut right := vgui.create_vbox_fill()
	right.set_spacing(8)
	right.add(heading('Settings'))
	right.add(theme_cb)
	right.add(name)
	right.add(vgui.label('Exposure'))
	right.add(s_exp)
	right.add(vgui.label('Contrast'))
	right.add(s_con)
	right.add(sp)
	right.add(ts_wifi)
	right.add(ts_sync)
	right.add(cb1)
	right.add(cb2)
	right.add(radios)
	right.add(pb)
	right.add(badges)
	right.add(ce, flex: 1)
	right.add(buttons)

	mut body := vgui.create_hbox_fill()
	body.set_padding(12)
	body.set_spacing(12)
	body.add(left, min: 200, max: 230)
	body.add(middle, flex: 1)
	body.add(right, min: 280, max: 300)

	mut root := vgui.create_vbox_fill()
	root.add(bar)
	root.add(body, flex: 1)
	mut foot := vgui.create_hbox_fill()
	foot.set_padding(6)
	foot.add(status)
	root.add(foot)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
