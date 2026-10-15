module main

// Пример 51. CurveEditor: редактор тональной кривой с гистограммой и "призраком" второй кривой.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/51_curve_editor.v

import vgui

// CurveEditor - редактор тональной кривой. Левая кнопка на точке -
// перетащить, на пустом месте - новая точка; правая на точке - удалить;
// двойной клик - сброс. Под кривой - гистограмма, рядом - «призрак»
// другой кривой. Подпись показывает значение кривой в середине (x = 0.5)
// и обновляется при отпускании.
fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'CurveEditor')!

	mut ce := vgui.curve_editor()
	mut hist := []f32{len: 64}
	for i in 0 .. 64 {
		t := f32(i) / 63.0
		hist[i] = 0.2 + 0.7 * t * (1 - t) * 4 * t // «гора» ближе к светам
	}
	ce.histogram = hist
	ce.add_ghost([vgui.CurvePoint{0, 0}, vgui.CurvePoint{0.5, 0.35}, vgui.CurvePoint{1, 1}],
		vgui.Color{220, 70, 70, 160})
	ce.set_points([vgui.CurvePoint{0, 0}, vgui.CurvePoint{0.25, 0.2}, vgui.CurvePoint{0.75, 0.85},
		vgui.CurvePoint{1, 1}])

	mut info := vgui.label('')
	info.text = 'y(0.5) = ${ce.value(0.5):.3f}'
	ce.on_release = fn [mut ce, mut info] () {
		info.text = 'y(0.5) = ${ce.value(0.5):.3f}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(12)
	root.set_spacing(8)
	root.add(ce, flex: 1)
	root.add(info)
	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
