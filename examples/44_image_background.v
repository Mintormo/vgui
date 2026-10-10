module main

import os
import vgui

// ImageBackground - фон окна + размещаемый виджет (логотип/баннер).
fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'ImageBackground - demo')!

	icons := os.join_path(os.dir(@FILE), '..', 'assets', 'icons')

	// 1) Фон ОКНА: рисуется позади всех виджетов и заполняет окно.
	//    Маленькую иконку замостим (.tile) - получится узорный фон.
	win.set_background_image(os.join_path(icons, 'IMG_1663.jpg'))
	win.set_background_mode(.fill)

	mut mode_label := vgui.label('Режим фона окна: Tile')
	mode_label.color = vgui.Color{230, 230, 230, 255}

	// Переключатель режимов фона окна. idx захватывается mut и сохраняется
	// между вызовами замыкания.
	mut idx := 0
	mut btn_mode := vgui.button('Сменить режим фона')
	btn_mode.on_click = fn [mut win, mut mode_label, mut idx] () {
		idx = (idx + 1) % 5
		name := match idx {
			0 {
				win.set_background_mode(.tile)
				'Tile'
			}
			1 {
				win.set_background_mode(.fill)
				'Fill (cover)'
			}
			2 {
				win.set_background_mode(.fit)
				'Fit'
			}
			3 {
				win.set_background_mode(.center)
				'Center'
			}
			else {
				win.set_background_mode(.stretch)
				'Stretch'
			}
		}
		mode_label.text = 'Режим фона окна: ${name}'
	}

	// 2) ImageBackground как ВИДЖЕТ в layout - баннер/логотип.
	//    bg_color задаёт подложку, .fit вписывает картинку целиком.
	mut banner := vgui.image_background_file(os.join_path(icons, 'IMG_1663.jpg'))
	banner.mode = .fill
	banner.bg_color = vgui.Color{40, 44, 52, 230}

	mut hint := vgui.label('Виджеты рисуются поверх фонового изображения окна')
	hint.color = vgui.Color{180, 180, 180, 255}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(banner) // ImageBackground-баннер сверху
	root.add(mode_label)
	root.add(hint)
	root.add(btn_mode)
	root.add(vgui.create_spacer(), flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
