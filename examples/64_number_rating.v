module main

// Пример 64. Числовое поле с протяжкой (NumberField, number_field.v) и оценка звёздами (Rating,
// rating.v).
//
// Что показано:
//   - поля значений как в Blender: тянуть мышью влево-вправо - значение меняется (Shift - точнее,
//     Ctrl - кратно шагу), щелчок без протяжки - ввод числа (Enter - применить, Esc - отмена);
//   - поле с подписью и полоской доли в границах, поле со своим текстом («5500 K»), стрелки в
//     фокусе меняют значение на шаг;
//   - поле зеркалит ползунок: ползунок двигает поле, поле - ползунок;
//   - оценка звёздами: наведение показывает, какая оценка встанет, щелчок ставит, повторный
//     щелчок снимает; в фокусе - стрелки и цифры 0..5.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/64_number_rating.v

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'NumberField and Rating - demo', width: 460, height: 0)!

	mut status := vgui.label('Drag a field or click it to type')

	mut rough := vgui.number_field(value: 0.35, min: 0, max: 1, step: 0.01, label: 'Roughness')
	rough.on_commit = fn [mut status] (v f64) {
		status.text = 'Roughness = ${v:.2f}'
	}

	mut temp := vgui.number_field(value: 5500, min: 2000, max: 12000, step: 50, digits: 0)
	temp.show_fill = false
	temp.align = .right
	temp.format = fn (v f64) string {
		return '${v:.0f} K'
	}

	// Поле и ползунок зеркалят друг друга: set_value поля колбэков не зовёт - петли нет
	mut exposure := vgui.number_field(value: 0, min: -5, max: 5, step: 0.05, label: 'Exposure')
	mut sl := vgui.slider_horizontal(-5, 5, 0)
	sl.on_change = fn [mut exposure] (v f32) {
		exposure.set_value(v)
	}
	exposure.on_change = fn [mut sl] (v f64) {
		sl.set_value(f32(v))
	}

	mut stars := vgui.rating(value: 3)
	stars.on_change = fn [mut status] (v int) {
		status.text = 'Rating: ${v}'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(12)
	root.set_spacing(8)
	root.add(rough)
	root.add(temp)
	root.add(exposure)
	root.add(sl)
	root.add(stars)
	root.add(status)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}
