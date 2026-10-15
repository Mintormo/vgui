module main

// Пример 54. ItemIcon: иконки в меню, дереве, списке, вкладках, ComboBox, MenuButton и Accordion.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/54_item_icons.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ItemIcon - icons in menus, trees, lists, tabs')!

	mut status := vgui.label('Выберите что-нибудь')
	status.color = vgui.Color{180, 180, 180, 255}

	// ItemIcon - одно значение для всех владельцев: глиф Lucide по имени
	// (item_icon), картинка из файла (item_icon_file) или из байтов
	// (item_icon_data). Глиф без своего цвета красится цветом текста пункта.
	mut bar := vgui.menu_bar()
	mut m_new := vgui.menu_action_lucide('Новый', 'file-plus')
	m_new.on_click = fn [mut status] () {
		status.text = 'Файл -> Новый'
	}
	mut m_open := vgui.menu_action_lucide('Открыть...', 'folder-open')
	m_open.on_click = fn [mut status] () {
		status.text = 'Файл -> Открыть'
	}
	mut m_save := vgui.menu_action_lucide('Сохранить', 'save')
	m_save.shortcut = 'Ctrl+S'
	m_save.on_click = fn [mut status] () {
		status.text = 'Файл -> Сохранить'
	}
	// Свой цвет глифа - with_color
	mut m_del := vgui.menu_action('Удалить')
	m_del.set_icon(vgui.item_icon('trash-2').with_color(vgui.Color{230, 90, 90, 255}))
	bar.add_menu('Файл', [m_new, m_open, m_save, vgui.menu_separator(), m_del])

	// Дерево: папки и файлы
	mut tv := vgui.tree_view()
	mut project := vgui.tree_node_with('vgui', vgui.item_icon('folder'))
	mut src := vgui.tree_node_with('src', vgui.item_icon('folder'))
	src.add(vgui.tree_node_with('button.v', vgui.item_icon('file-code')))
	src.add(vgui.tree_node_with('item_icon.v', vgui.item_icon('file-code')))
	project.add(src)
	project.add(vgui.tree_node_with('README.md', vgui.item_icon('file-text')))
	project.add(vgui.tree_node_with('logo.png', vgui.item_icon('image')))
	tv.add_root(project)

	// Список: иконка слева от текста строки
	mut lb := vgui.list_box()
	for name, ic in {
		'Входящие':     'inbox'
		'Отправленные': 'send'
		'Черновики':    'file-pen'
		'Избранное':    'star'
		'Корзина':      'trash-2'
	} {
		lb.add_item_icon(name, vgui.item_icon(ic))
	}
	lb.on_select = fn [mut status] (_ int, text string) {
		status.text = 'Список: ${text}'
	}

	mut lists := vgui.create_hbox_fill()
	lists.set_spacing(12)
	lists.add(tv, flex: 1)
	lists.add(lb, flex: 1)

	// ComboBox: иконка и в выпадающем списке, и в закрытом поле
	mut theme_cb := vgui.combo_box()
	theme_cb.add_icon_item('Светлая', vgui.item_icon('sun'))
	theme_cb.add_icon_item('Тёмная', vgui.item_icon('moon'))
	theme_cb.add_icon_item('Как в системе', vgui.item_icon('monitor'))
	theme_cb.set_selected(1)

	// MenuButton со своей иконкой и иконками пунктов
	mut export := vgui.menu_button('Экспорт')
	export.set_icon(vgui.item_icon('download'))
	export.add(vgui.menu_action_lucide('PNG', 'image'))
	export.add(vgui.menu_action_lucide('PDF', 'file-text'))

	mut controls := vgui.create_hbox_fill()
	controls.set_spacing(12)
	controls.add(theme_cb)
	controls.add(export)

	// Вкладки: иконка над текстом; пустой заголовок - вкладка только с иконкой
	mut tabs := vgui.tab_box()
	tabs.add_tab_icon('Главная', vgui.item_icon('house'), vgui.label('Главная вкладка'))
	tabs.add_tab_icon('Настройки', vgui.item_icon('settings'), vgui.label('Настройки'))
	tabs.add_tab_icon('', vgui.item_icon('info'), vgui.label('Вкладка без текста'))

	// Accordion: иконка в заголовке секции
	mut acc := vgui.accordion_single()
	acc.add_section_expanded('Профиль', vgui.label('Имя, почта, аватар'))
	acc.set_section_icon(0, vgui.item_icon('user'))
	acc.add_section('Безопасность', vgui.label('Пароль и ключи'))
	acc.set_section_icon(1, vgui.item_icon('lock'))

	mut bottom := vgui.create_hbox_fill()
	bottom.set_spacing(12)
	bottom.add(tabs, flex: 1)
	bottom.add(acc, flex: 1)

	mut body := vgui.create_vbox_fill()
	body.set_padding(16)
	body.set_spacing(12)
	body.add(controls)
	body.add(lists, flex: 1)
	body.add(bottom, flex: 1)
	body.add(status)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.add(bar)
	root.add(body, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
