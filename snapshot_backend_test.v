module vgui

import os

// Снапшоты виджетов, которые рисуют в обход простых примитивов RenderContext:
// свои текстуры (Canvas, ImageView, ImageBackground, картинки MarkdownView,
// иконки-файлы), ломаные (PlotView). Это страховочная сетка для переноса
// SDL-вызовов за RenderContext (docs/backend_abstraction.md): рефакторинг
// обязан давать кадр пиксель в пиксель, эталоны при нём не перезаписываются.
//
// Помощник snap/snap_scaled и каталог эталонов - в snapshot_test.v не видны
// (каждый _test.v компилируется отдельно), поэтому здесь своя короткая копия.
//
// Запуск: v test snapshot_backend_test.v

const backend_snapshot_dir = os.join_path(@VMODROOT, 'testdata', 'snapshots')

const backend_icon_home = os.join_path(@VMODROOT, 'assets', 'icons', 'home.png')

const backend_icon_user = os.join_path(@VMODROOT, 'assets', 'icons', 'user.png')

// backend_snap рисует сцену build в окне w×h при масштабе scale в обеих темах
// и сверяет с эталонами <name>_light.png / <name>_dark.png.
fn backend_snap(name string, w int, h int, scale f32, build fn () &Widget) ! {
	for theme_name, theme in {
		'light': light_theme()
		'dark':  dark_theme()
	} {
		mut t := new_test_ui(width: w, height: h, theme: theme, ui_scale: scale)!
		t.add(build())
		t.redraw()
		t.match_snapshot(os.join_path(backend_snapshot_dir, '${name}_${theme_name}.png')) or {
			t.close()
			return err
		}
		t.close()
	}
}

// scene_canvas - холст с примитивами, нарисованными в его пиксельный буфер
// (текстура холста обновляется из буфера при рисовании).
fn scene_canvas() &Widget {
	mut c := canvas(64, 48)
	c.fill(Color{240, 240, 230, 255})
	c.fill_rect(4, 4, 20, 12, Color{200, 40, 40, 255})
	c.draw_rect(30, 4, 28, 18, Color{20, 90, 200, 255})
	c.draw_line(0, 47, 63, 20, Color{30, 150, 60, 255})
	c.fill_circle(16, 34, 9, Color{240, 170, 20, 255})
	c.draw_circle(44, 34, 10, Color{120, 40, 160, 255})
	c.set_pixel(62, 46, Color{0, 0, 0, 255})
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.add(c, flex: 1)
	return col
}

// scene_plot - графики функций разной толщины, точки с маркерами и рассеяние
// в фиксированном диапазоне (fit_to_data не нужен - диапазон задан явно).
fn scene_plot() &Widget {
	mut p := plot_view()
	p.add_function(fn (x f32) f32 {
		return x * x * 0.25
	}, Color{200, 50, 50, 255})
	p.add_function_thick(fn (x f32) f32 {
		return 2.0 - x * 0.5
	}, Color{40, 110, 210, 255}, 3)
	p.add_points_with_markers(make_points([f32(-3), -1, 0, 1, 3], [f32(1), -1, 0.5, 2, -2]),
		Color{30, 150, 60, 255}, 6)
	p.add_scatter(make_points([f32(-2), -1.5, 2.5], [f32(-3), 3, 1]), Color{160, 60, 170, 255})
	p.set_range(-4, 4, -4, 4)
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.add(p, flex: 1)
	return col
}

// scene_images - картинка из файла в ImageView, фон-картинка, иконки-файлы
// (ItemIcon в списке и icon_path у кнопки - кэш иконок RenderContext).
fn scene_images() &Widget {
	mut iv := image_view_file(backend_icon_home)
	mut bg := image_background_file(backend_icon_user)
	mut lb := list_box()
	lb.add_item('дом')
	lb.add_item('пользователь')
	lb.set_row_icon(0, item_icon_file(backend_icon_home))
	lb.set_row_icon(1, item_icon_file(backend_icon_user))
	mut btn := button('Иконка')
	btn.icon_path = backend_icon_user
	mut row := create_hbox_fill()
	row.set_spacing(8)
	row.add(iv, flex: 1)
	row.add(bg, flex: 1)
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.set_spacing(8)
	col.add(row, flex: 1)
	col.add(lb, flex: 1)
	col.add(btn)
	return col
}

// scene_markdown_image - markdown с картинкой (своя текстура MarkdownView).
fn scene_markdown_image() &Widget {
	mut md := markdown_view()
	md.set_text('# Картинка\n\nТекст до картинки.\n\n![дом](${backend_icon_home})\n\nТекст после.\n')
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.add(md, flex: 1)
	return col
}

fn test_snapshot_canvas() {
	backend_snap('canvas', 240, 200, 1, scene_canvas)!
	backend_snap('canvas_x125', 240, 200, 1.25, scene_canvas)!
}

fn test_snapshot_plot() {
	backend_snap('plot', 320, 240, 1, scene_plot)!
	backend_snap('plot_x125', 320, 240, 1.25, scene_plot)!
	backend_snap('plot_x2', 320, 240, 2, scene_plot)!
}

fn test_snapshot_images() {
	backend_snap('images', 320, 300, 1, scene_images)!
	backend_snap('images_x2', 320, 300, 2, scene_images)!
}

fn test_snapshot_markdown_image() {
	backend_snap('markdown_image', 320, 240, 1, scene_markdown_image)!
}

// scene_spinners - все стили Spinner и «бегущие» индикаторы ProgressBar. Они
// зависят от времени, поэтому снимаются при остановленных часах интерфейса
// (set_clock_override, clock.v): угол и фаза одинаковы при каждом запуске.
fn scene_spinners() &Widget {
	mut row := create_hbox_fill()
	row.set_spacing(12)
	for style in [SpinnerStyle.arc, .dots, .dual] {
		mut s := spinner_with_text('ждём')
		s.style = style
		s.size = 40
		row.add(s, flex: 1)
	}
	mut circ := progress_circular()
	circ.indeterminate = true
	row.add(circ, flex: 1)
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.set_spacing(8)
	col.add(row, flex: 1)
	col.add(progress_indeterminate())
	return col
}

fn test_snapshot_spinners() {
	set_clock_override(12345)
	defer {
		clear_clock_override()
	}
	backend_snap('spinners', 320, 140, 1, scene_spinners)!
	backend_snap('spinners_x125', 320, 140, 1.25, scene_spinners)!
}
