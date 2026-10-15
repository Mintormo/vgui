module main

// Пример 42. i18n: переводы интерфейса, выбор языка и обновление подписей при смене локали.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/42_i18n.v

import vgui

// Хранит ссылки на виджеты, чьи подписи нужно обновлять при смене языка.
@[heap]
struct I18nState {
mut:
	title    &vgui.Label
	greeting &vgui.Label
	btn_save &vgui.Button
	btn_open &vgui.Button
	status   &vgui.Label
}

fn (mut s I18nState) retranslate() {
	// tr(key) возвращает перевод для текущей локали (с откатом на fallback).
	s.title.text = vgui.tr('app.title')
	s.greeting.text = vgui.tr('app.greeting')
	s.btn_save.text = vgui.tr('btn.save')
	s.btn_open.text = vgui.tr('btn.open')
	s.status.text = vgui.trf('status.locale', vgui.get_locale())
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'i18n - demo')!

	// Регистрируем переводы для каждой локали. {0} в trf подставляется аргументом.
	vgui.add_translations('ru', {
		'app.title':     'Интернационализация'
		'app.greeting':  'Привет, мир!'
		'btn.save':      'Сохранить'
		'btn.open':      'Открыть'
		'status.locale': 'Текущая локаль: {0}'
	})
	vgui.add_translations('en', {
		'app.title':     'Internationalization'
		'app.greeting':  'Hello, world!'
		'btn.save':      'Save'
		'btn.open':      'Open'
		'status.locale': 'Current locale: {0}'
	})
	vgui.add_translations('de', {
		'app.title':     'Internationalisierung'
		'app.greeting':  'Hallo, Welt!'
		'btn.save':      'Speichern'
		'btn.open':      'Öffnen'
		'status.locale': 'Aktuelle Sprache: {0}'
	})

	vgui.set_fallback_locale('en')
	vgui.set_locale('ru')

	mut title := vgui.label('')
	title.font_style = .bold
	title.font_size = 18

	mut greeting := vgui.label('')
	mut status := vgui.label('')
	status.color = vgui.Color{180, 180, 180, 255}

	mut btn_save := vgui.button('')
	btn_save.style = .accent
	mut btn_open := vgui.button('')

	mut state := &I18nState{
		title:    title
		greeting: greeting
		btn_save: btn_save
		btn_open: btn_open
		status:   status
	}

	// Переключатель языка
	mut lang := vgui.combo_box()
	lang.add_items(['Русский (ru)', 'English (en)', 'Deutsch (de)'])
	lang.set_selected(0)
	lang.on_change = fn [mut state] (idx int, _ string) {
		locale := match idx {
			1 { 'en' }
			2 { 'de' }
			else { 'ru' }
		}
		vgui.set_locale(locale)
		state.retranslate()
	}

	mut btn_row := vgui.create_hbox_fill()
	btn_row.set_spacing(6)
	btn_row.add(btn_save, flex: 1)
	btn_row.add(btn_open, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(title)
	root.add(greeting)
	root.add(vgui.hseparator())
	root.add(vgui.label('Язык / Language / Sprache:'))
	root.add(lang)
	root.add(btn_row)
	root.add(vgui.create_spacer(), flex: 1)
	root.add(status)

	// Первичное заполнение подписей текущей локалью
	state.retranslate()

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
