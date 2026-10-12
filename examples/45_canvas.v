module main

// Пример 45. Canvas: растровый редактор (кисть, ластик, пипетка, заливка, линия, прямоугольник) поверх единого колбэка on_input.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/45_canvas.v

import vgui
import math

// Canvas - полноценный набор инструментов поверх ОДНОГО колбэка on_input.
//
// on_input(ev &CanvasInputEvent) - единый богатый поток ввода: указатель
// down/move/up, hover, enter/leave, колесо и клавиши, каждое событие несёт
// модификаторы (shift/ctrl/alt), кнопку мыши и счётчик кликов. Этого достаточно
// для инструментов любого растрового редактора.
//
// Демонстрируется:
//   * кисть/карандаш/ластик/пипетка/заливка/линия/прямоугольник через on_input;
//   * левая кнопка - основной цвет, правая - вторичный (панорама снята с правой
//     через set_pan_buttons(cv_pan_middle), правая приходит в on_input);
//   * Shift зажимает фигуры (линия -> 45°, прямоугольник -> квадрат);
//   * клавиатура (холст в фокусе): 1..7 - инструмент, [ ] - размер, X - обмен
//     цветов, Esc - отмена текущей фигуры;
//   * колесо: Ctrl+колесо - масштаб, колесо - размер кисти (встроенный зум
//     выключен через set_wheel_zoom(false));
//   * hover показывает координату и цвет под курсором.

// Коды клавиш SDL для печатных символов совпадают с ASCII.
const k_esc = 27
const k_lbracket = 91
const k_rbracket = 93
const k_x_key = 120

// Состояние редактора - в одной именованной структуре (CLAUDE.md: анонимные
// структуры с указателями ломают C-кодоген, поэтому всегда именованные).
struct EditorState {
mut:
	tool      int // 0 кисть, 1 карандаш, 2 ластик, 3 пипетка, 4 заливка, 5 линия, 6 прямоуг.
	primary   vgui.Color = vgui.Color{33, 33, 33, 255}
	secondary vgui.Color = vgui.Color{255, 255, 255, 255}
	brush     int        = 4
	snap      []u8 // снимок холста для фигур
	x0        int
	y0        int
	drawing   bool
}

struct Pt {
	x int
	y int
}

// flood_fill - заливка области через прямой доступ к пикселям.
fn flood_fill(mut c vgui.Canvas, sx int, sy int, col vgui.Color) {
	w := c.width
	h := c.height
	if sx < 0 || sy < 0 || sx >= w || sy >= h {
		return
	}
	start := c.get_pixel(sx, sy)
	if start == col {
		return
	}
	mut stack := []Pt{}
	stack << Pt{sx, sy}
	for stack.len > 0 {
		p := stack.pop()
		if p.x < 0 || p.y < 0 || p.x >= w || p.y >= h {
			continue
		}
		if c.get_pixel(p.x, p.y) != start {
			continue
		}
		c.set_pixel(p.x, p.y, col)
		stack << Pt{p.x + 1, p.y}
		stack << Pt{p.x - 1, p.y}
		stack << Pt{p.x, p.y + 1}
		stack << Pt{p.x, p.y - 1}
	}
}

// constrain_line зажимает линию к ближайшему углу, кратному 45°.
fn constrain_line(x0 int, y0 int, x int, y int) (int, int) {
	dx := x - x0
	dy := y - y0
	if dx == 0 && dy == 0 {
		return x, y
	}
	step := math.pi / 4.0
	ang := math.round(math.atan2(f64(dy), f64(dx)) / step) * step
	dist := math.hypot(f64(dx), f64(dy))
	return x0 + int(math.round(math.cos(ang) * dist)), y0 + int(math.round(math.sin(ang) * dist))
}

// constrain_square зажимает прямоугольник в квадрат по большей стороне.
fn constrain_square(x0 int, y0 int, x int, y int) (int, int) {
	side := if vgui.abs_int(x - x0) > vgui.abs_int(y - y0) {
		vgui.abs_int(x - x0)
	} else {
		vgui.abs_int(y - y0)
	}
	sx := if x >= x0 { 1 } else { -1 }
	sy := if y >= y0 { 1 } else { -1 }
	return x0 + sx * side, y0 + sy * side
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Canvas - набор инструментов')!

	w := 360
	h := 260
	bg := vgui.Color{255, 255, 255, 255}

	mut canvas := vgui.canvas(w, h)
	canvas.fill(bg)
	// Правую кнопку отдаём инструменту (вторичный цвет): панорама - только средней.
	canvas.set_pan_buttons(vgui.cv_pan_middle)
	// Колесо отдаём инструменту: Ctrl+колесо масштабирует, колесо - размер кисти.
	canvas.set_wheel_zoom(false)

	mut st := &EditorState{}

	mut status := vgui.label('Инструмент: Кисть. Холст ${w}x${h}')
	status.color = vgui.Color{180, 180, 180, 255}

	tool_names := ['Кисть', 'Карандаш', 'Ластик', 'Пипетка', 'Заливка',
		'Линия', 'Прямоуг.']

	// ─── панель инструментов (кнопки нужны замыканию on_input для подсветки) ───
	mut tools_row := vgui.create_hbox_fill()
	tools_row.set_spacing(4)
	mut tool_buttons := []&vgui.Button{}
	for tname in tool_names {
		mut tb := vgui.button(tname)
		tb.style = .outline
		tools_row.add(tb, flex: 1)
		tool_buttons << tb
	}

	mut size_label := vgui.label('Размер: 4')
	mut size_slider := vgui.slider_horizontal(1, 20, 4)
	size_slider.step = 1

	// ─── единый обработчик ввода ───
	canvas.on_input = fn [mut canvas, mut status, mut st, bg, mut size_label, mut size_slider, mut tool_buttons, tool_names] (ev &vgui.CanvasInputEvent) {
		// цвет: правая кнопка (3) рисует вторичным, иначе основным
		col := if ev.button == 3 { st.secondary } else { st.primary }
		x := ev.x
		y := ev.y

		match ev.kind {
			.hover {
				if ev.in_image {
					p := canvas.get_pixel(x, y)
					status.text = '(${x}, ${y})  цвет (${p.r}, ${p.g}, ${p.b})'
				}
				return
			}
			.wheel {
				if ev.ctrl {
					if ev.wheel_y > 0 {
						canvas.zoom_in()
					} else {
						canvas.zoom_out()
					}
					status.text = 'Масштаб: ${int(canvas.get_zoom() * 100)}%'
				} else {
					mut nb := st.brush + (if ev.wheel_y > 0 { 1 } else { -1 })
					nb = if nb < 1 {
						1
					} else if nb > 20 {
						20
					} else {
						nb
					}
					st.brush = nb
					size_label.text = 'Размер: ${nb}'
					size_slider.value = f32(nb)
				}
				return
			}
			.key_down {
				kc := ev.keycode
				if kc >= 49 && kc <= 55 { // '1'..'7' - выбор инструмента
					st.tool = kc - 49
					for j in 0 .. tool_buttons.len {
						tool_buttons[j].style = if j == st.tool { .accent } else { .outline }
					}
					status.text = 'Инструмент: ${tool_names[st.tool]}'
				} else if kc == k_lbracket || kc == k_rbracket {
					mut nb := st.brush + (if kc == k_rbracket { 1 } else { -1 })
					nb = if nb < 1 {
						1
					} else if nb > 20 {
						20
					} else {
						nb
					}
					st.brush = nb
					size_label.text = 'Размер: ${nb}'
					size_slider.value = f32(nb)
				} else if kc == k_x_key {
					tmp := st.primary
					st.primary = st.secondary
					st.secondary = tmp
					status.text = 'Цвета: основной (${st.primary.r},${st.primary.g},${st.primary.b})  вторичный (${st.secondary.r},${st.secondary.g},${st.secondary.b})'
				} else if kc == k_esc && st.drawing && st.tool >= 5 {
					if st.snap.len == canvas.pixels.len && st.snap.len > 0 {
						copy(mut canvas.pixels, st.snap)
						canvas.mark_dirty()
					}
					st.drawing = false
					status.text = 'Фигура отменена'
				}
				return
			}
			else {}
		}

		// дальше - только указатель down/move/up
		if ev.kind != .pointer_down && ev.kind != .pointer_move && ev.kind != .pointer_up {
			return
		}

		match st.tool {
			0 { // кисть
				if ev.kind != .pointer_up {
					canvas.fill_circle(x, y, st.brush, col)
				}
			}
			1 { // карандаш
				if ev.kind != .pointer_up {
					canvas.set_pixel(x, y, col)
				}
			}
			2 { // ластик
				if ev.kind != .pointer_up {
					canvas.fill_circle(x, y, st.brush, bg)
				}
			}
			3 { // пипетка
				if ev.kind == .pointer_down {
					picked := canvas.get_pixel(x, y)
					if ev.button == 3 {
						st.secondary = picked
					} else {
						st.primary = picked
					}
					status.text = 'Цвет: (${picked.r}, ${picked.g}, ${picked.b})'
				}
			}
			4 { // заливка
				if ev.kind == .pointer_down {
					flood_fill(mut canvas, x, y, col)
				}
			}
			else { // линия (5), прямоугольник (6) - с резиновой нитью
				if ev.kind == .pointer_down {
					st.snap = canvas.pixels.clone()
					st.x0 = x
					st.y0 = y
					st.drawing = true
				} else {
					if st.snap.len == canvas.pixels.len && st.snap.len > 0 {
						copy(mut canvas.pixels, st.snap)
						canvas.mark_dirty()
					}
					mut ex := x
					mut ey := y
					if st.tool == 5 {
						if ev.shift {
							ex, ey = constrain_line(st.x0, st.y0, x, y)
						}
						canvas.draw_line(st.x0, st.y0, ex, ey, col)
					} else {
						if ev.shift {
							ex, ey = constrain_square(st.x0, st.y0, x, y)
						}
						rx := if st.x0 < ex { st.x0 } else { ex }
						ry := if st.y0 < ey { st.y0 } else { ey }
						canvas.draw_rect(rx, ry, vgui.abs_int(ex - st.x0) + 1, vgui.abs_int(ey - st.y0) + 1,
							col)
					}
					if ev.kind == .pointer_up {
						st.drawing = false
					}
				}
			}
		}
	}

	// клик по кнопке инструмента (дублирует клавиши 1..7)
	for i in 0 .. tool_names.len {
		mut tb := tool_buttons[i]
		tname := tool_names[i]
		tb.on_click = fn [mut st, mut status, mut tool_buttons, i, tname] () {
			st.tool = i
			for j in 0 .. tool_buttons.len {
				tool_buttons[j].style = if j == i { .accent } else { .outline }
			}
			status.text = 'Инструмент: ${tname}'
		}
	}
	tool_buttons[0].style = .accent // кисть активна по умолчанию

	// ─── палитра цветов (задаёт основной цвет) ───
	palette_names := ['Чёрный', 'Красный', 'Зелёный', 'Синий', 'Белый']
	palette_cols := [vgui.Color{33, 33, 33, 255}, vgui.Color{229, 57, 53, 255},
		vgui.Color{67, 160, 71, 255}, vgui.Color{30, 136, 229, 255}, vgui.Color{255, 255, 255, 255}]
	mut palette := vgui.create_hbox_fill()
	palette.set_spacing(4)
	for i, pname in palette_names {
		pcol := palette_cols[i]
		mut pb := vgui.button(pname)
		pb.on_click = fn [mut st, mut status, pcol, pname] () {
			st.primary = pcol
			status.text = 'Основной цвет: ${pname}'
		}
		palette.add(pb, flex: 1)
	}

	// ─── размер кисти ───
	size_slider.on_change = fn [mut st, mut size_label] (v f32) {
		st.brush = int(v)
		size_label.text = 'Размер: ${st.brush}'
	}
	mut size_row := vgui.create_hbox_fill()
	size_row.set_spacing(8)
	size_row.add(size_label)
	size_row.add(size_slider, flex: 1)

	// ─── действия ───
	mut b_clear := vgui.button('Очистить')
	b_clear.style = .outline
	b_clear.on_click = fn [mut canvas, mut status, bg] () {
		canvas.fill(bg)
		status.text = 'Холст очищен'
	}

	mut b_invert := vgui.button('Инвертировать')
	b_invert.on_click = fn [mut canvas, mut status] () {
		for i := 0; i < canvas.pixels.len; i += 4 {
			canvas.pixels[i] = u8(255 - canvas.pixels[i])
			canvas.pixels[i + 1] = u8(255 - canvas.pixels[i + 1])
			canvas.pixels[i + 2] = u8(255 - canvas.pixels[i + 2])
		}
		canvas.mark_dirty()
		status.text = 'Инвертировано (${canvas.pixels.len} байт)'
	}

	filter_names := ['Изображения', 'Все файлы']
	filter_patterns := ['png;jpg;jpeg;webp;gif;bmp;tiff', '*']

	mut b_load := vgui.button('Загрузить...')
	b_load.on_click = fn [mut canvas, mut status, mut app, win, filter_names, filter_patterns] () {
		path := vgui.native_open_file_dialog(win, mut app, vgui.NativeFileDialogConfig{
			filter_names:    filter_names
			filter_patterns: filter_patterns
		})
		if path.len == 0 {
			return
		}
		if canvas.load_file(path) {
			status.text = 'Загружено: ${path} (${canvas.width}x${canvas.height})'
		} else {
			status.text = 'Не удалось загрузить: ${path}'
		}
	}

	mut b_save := vgui.button('Сохранить...')
	b_save.on_click = fn [mut canvas, mut status, mut app, win, filter_names, filter_patterns] () {
		path := vgui.native_save_file_dialog(win, mut app, vgui.NativeFileDialogConfig{
			default_name:    'canvas.png'
			filter_names:    filter_names
			filter_patterns: filter_patterns
		})
		if path.len == 0 {
			return
		}
		if canvas.save_file(path) {
			status.text = 'Сохранено: ${path}'
		} else {
			status.text = 'Не удалось сохранить: ${path} (tiff не поддерживается на запись)'
		}
	}

	mut actions := vgui.create_hbox_fill()
	actions.set_spacing(6)
	actions.add(b_clear, flex: 1)
	actions.add(b_invert, flex: 1)
	actions.add(b_load, flex: 1)
	actions.add(b_save, flex: 1)

	// ─── навигация (зум/панорама) ───
	mut b_fit := vgui.button('Вписать')
	b_fit.style = .outline
	b_fit.on_click = fn [mut canvas, mut status] () {
		canvas.fit_to_view()
		status.text = 'Масштаб: ${int(canvas.get_zoom() * 100)}% (холст ${canvas.width}x${canvas.height})'
	}
	mut b_zin := vgui.button('Увеличить (+)')
	b_zin.style = .outline
	b_zin.on_click = fn [mut canvas, mut status] () {
		canvas.zoom_in()
		status.text = 'Масштаб: ${int(canvas.get_zoom() * 100)}% (холст ${canvas.width}x${canvas.height})'
	}
	mut b_zout := vgui.button('Уменьшить (-)')
	b_zout.style = .outline
	b_zout.on_click = fn [mut canvas, mut status] () {
		canvas.zoom_out()
		status.text = 'Масштаб: ${int(canvas.get_zoom() * 100)}% (холст ${canvas.width}x${canvas.height})'
	}
	mut b_100 := vgui.button('1:1')
	b_100.style = .outline
	b_100.on_click = fn [mut canvas, mut status] () {
		canvas.set_zoom(1.0)
		status.text = 'Масштаб: ${int(canvas.get_zoom() * 100)}% (холст ${canvas.width}x${canvas.height})'
	}
	mut nav := vgui.create_hbox_fill()
	nav.set_spacing(6)
	nav.add(b_fit, flex: 1)
	nav.add(b_zin, flex: 1)
	nav.add(b_zout, flex: 1)
	nav.add(b_100, flex: 1)

	mut hint1 := vgui.label('ЛКМ - основной цвет, ПКМ - вторичный, Shift - ровные фигуры')
	hint1.color = vgui.Color{140, 140, 140, 255}
	mut hint2 := vgui.label('1-7 инструменты, [ ] размер, X обмен, Ctrl+колесо масштаб, средняя кнопка - панорама')
	hint2.color = vgui.Color{120, 120, 120, 255}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(14)
	root.set_spacing(8)
	root.add(status)
	root.add(canvas, flex: 1)
	root.add(tools_row)
	root.add(palette)
	root.add(size_row)
	root.add(actions)
	root.add(nav)
	root.add(hint1)
	root.add(hint2)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
