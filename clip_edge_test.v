module vgui

// Регрессия: частичная перерисовка стирала край соседнего виджета.
//
// Клип SDL шире клипа из clip_stack на clip_pad (clip_sdl_rect), и окно при
// частичной перерисовке очищает именно расширенную область. is_in_clip же
// проверял нерасширенный клип строгим пересечением: виджет, касающийся
// dirty-области краем, не перерисовывался, а его крайняя строка пикселей уже была
// стёрта. В примере 56 так пропадала нижняя рамка поля ввода при наведении на
// переключатель под ним.
//
// Запуск: SDL_VIDEODRIVER=dummy v test clip_edge_test.v

// Разметка - фрагмент примера 56, на котором баг воспроизводился (без CSS).
const clip_edge_vui = '
vbox pad=16 gap=12
  label "Стили CSS" size=20 bold
  vbox pad=14 gap=8
    label "Название"
    input "Мой проект"
    label "Описание"
    input hint="Пара слов о проекте"
    hbox gap=8
      checkbox "Публичный" checked
      spacer flex=1
      toggle "Тёмная тема" #tog
'

fn test_partial_repaint_does_not_erase_touching_neighbour_edge() {
	// Тёмная тема: у неё есть тень, и область перерисовки чекбокса и переключателя
	// раздута под неё (visual_margin) ровно на зазор gap=8 - её верх совпадает с
	// нижним краем поля «Описание».
	mut t := new_test_ui(width: 760, height: 360, theme: dark_theme())!
	defer {
		t.close()
	}
	ui := ui_parse(clip_edge_vui, 't.vui')!
	t.add(ui.root)
	// 1) анимация галочки чекбокса (checked) - частичные кадры его области
	t.settle(60)
	after_check := t.capture()
	t.redraw()
	assert after_check.diff(t.capture(), 8).count == 0, 'анимация чекбокса стёрла край поля'
	// 2) наведение на переключатель: первое движение мыши в окне - полный кадр,
	// поэтому сначала в сторону, затем на сам переключатель (частичный кадр)
	tog := ui.get[ToggleSwitch]('tog')!
	cx, cy := t.center_of(tog)
	t.move(cx - 60, cy)
	t.settle(60)
	t.move(cx, cy)
	t.settle(60)
	after_hover := t.capture()
	t.redraw()
	assert after_hover.diff(t.capture(), 8).count == 0, 'наведение стёрло край поля'
}
