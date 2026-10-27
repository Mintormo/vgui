module vgui

// Шрифты, отступы и размеры из CSS (PROJECT.md, «Стили CSS», «Шрифты,
// отступы и размеры»): разбор font-*/padding/gap/width... и их ошибок, и что одни и те же правила видят
// измерение, раскладка, отрисовка и события - размеры виджета считаются тем
// шрифтом, которым он нарисован, а клик в поле ввода ставит курсор по нему же.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test css_layout_test.v

// css_err — текст ошибки разбора (пусто - разобралось).
fn css_err(src string) string {
	parse_stylesheet(src, 't.css') or { return err.msg() }
	return ''
}

fn test_parse_font_and_spacing_values() {
	ss := parse_stylesheet('
		.a { font-size: 20px; font-weight: bold; font-style: italic; font-family: monospace; }
		.b { padding: 4 8; gap: 6 12; }
		button { color: #ff0000; }
	', 't.css')!
	assert ss.has_layout, 'шрифт и отступы - правила раскладки'
	a := ss.rules.filter(it.selector.text == '.a')[0]
	assert a.decls.all(it.layout)
	assert a.decls[0].value.num == 20
	assert a.decls[1].value.word == 'bold'
	b := ss.rules.filter(it.selector.text == '.b')[0]
	assert b.decls[0].value.nums == [f32(4), 8]
	assert b.decls[0].fields_by_kind[kind_vbox] == [css_padding_field]
	assert b.decls[0].fields_by_kind[kind_text_input].len == 0, 'у поля ввода padding нет'
	// только цвета - раскладке таблица не нужна
	colors := parse_stylesheet('button { color: #ff0000; } :root { font-size: 18; }', 't.css')!
	assert !colors.has_layout, ':root шрифт вшивается в тему окна, а не в правила по дереву'
	assert css_base_theme(light_theme(), colors).font_size == 18
}

fn test_font_and_spacing_errors() {
	assert css_err('.a { font-weight: heavy; }').contains('ожидается одно из: bold, normal')
	assert css_err('.a { font-size: bold; }').contains('положительное число')
	assert css_err('.a { font-size: 0; }').contains('положительное число')
	assert css_err('vbox { padding: 1 2 3 4 5; }').contains('от 1 до 4')
	assert css_err('vbox { padding: -2; }').contains('неотрицательных')
	assert css_err('grid { gap: 1 2 3; }').contains('1 или 2')
	assert css_err('input { padding: 4; }').contains('неприменимо к input')
	assert css_err(':root { padding: 4; }').contains('неприменимо к :root')
	assert css_err('menu { font-size: 20; }').contains('неприменимо к menu')
	// несколько чисел и слова полям темы не подходят
	assert css_err('.a { border-radius: 4 8; }').contains('ожидается число')
	assert css_err('.a { color: blah; }').contains('ожидается цвет')
	assert css_err('.a { font-size: 8pt; }').contains('не число')
}

// css_font_style добавляет начертание к выбранному виджетом и не снимает его.
fn test_css_font_style_adds_traits() {
	mut t := light_theme()
	assert css_font_style(.bold, t) == .bold
	t.font_bold = true
	assert css_font_style(.regular, t) == .bold
	assert css_font_style(.italic, t) == .bold_italic
	assert css_font_style(.mono, t) == .mono_bold
	t.font_bold = false
	t.font_mono = true
	t.font_italic = true
	assert css_font_style(.bold, t) == .mono_bold, 'у моно курсива нет'
}

// Размер текста из CSS: метка внутри .big мерится и раскладывается крупным
// шрифтом (выше и шире), соседняя снаружи - шрифтом окна; font-weight: normal
// ниже снимает жирность, заданную выше.
fn test_font_size_and_weight_reach_layout() {
	mut t := new_test_ui(width: 400, height: 300)!
	defer {
		t.close()
	}
	// Ряды - hbox: в нём метка получает свою ширину по тексту (в vbox её
	// растянуло бы на всю ширину)
	mut root := create_vbox_fill()
	mut plain_row := create_hbox_fill()
	mut plain := label('Hello world')
	plain_row.add(plain)
	mut big_box := create_hbox_fill()
	big_box.css.classes = ['big']
	mut big := label('Hello world')
	big_box.add(big)
	mut bold_box := create_hbox_fill()
	bold_box.css.classes = ['b']
	mut bold := label('Hello world')
	mut unbold := label('Hello world')
	unbold.css.classes = ['n']
	bold_box.add(bold)
	bold_box.add(unbold)
	root.add(plain_row)
	root.add(big_box)
	root.add(bold_box)
	t.app.set_stylesheet(parse_stylesheet('
		.big { font-size: 30; }
		.b { font-weight: bold; }
		.b .n { font-weight: normal; }
	', 't.css')!)
	t.add(root)
	t.frame()
	assert big.bounds.h > plain.bounds.h + 8, 'крупный шрифт - выше'
	assert big_box.box.bounds.h >= big.bounds.h, 'контейнер мерил ребёнка тем же шрифтом'
	assert bold.bounds.h == plain.bounds.h
	// жирная строка шире; normal возвращает обычную (равна метке снаружи)
	// (ширина метки без wrap - ровно по тексту)
	assert bold.bounds.w > plain.bounds.w
	assert unbold.bounds.w == plain.bounds.w
	// после обхода стили не остались в теме окна
	assert t.win.ctx.theme.font_size == 0 && !t.win.ctx.theme.font_bold
	assert t.win.ctx.css_stack.len == 0
}

// padding и gap у vbox/hbox/grid/panel/button/label: геометрия детей.
fn test_padding_and_gap_in_containers() {
	mut t := new_test_ui(width: 400, height: 400)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut card := create_vbox_fill()
	card.css.classes = ['card']
	mut a := label('a')
	mut b := label('b')
	// вложенный vbox без класса: padding родителя на него не переходит
	mut inner := create_vbox_fill()
	mut c := label('c')
	inner.add(c)
	card.add(a)
	card.add(b)
	card.add(inner)
	mut row := create_hbox_fill()
	row.css.classes = ['row']
	mut x := label('x')
	mut y := label('y')
	row.add(x)
	row.add(y)
	// кнопки - в ряду, где у них своя ширина
	mut btn_row := create_hbox_fill()
	mut btn := button('OK')
	btn.css.classes = ['wide']
	mut plain_btn := button('OK')
	btn_row.add(btn)
	btn_row.add(plain_btn)
	mut grid := create_grid(2, 1)
	grid.css.classes = ['g']
	mut g0 := label('0')
	mut g1 := label('1')
	grid.add(g0, 0, 0)
	grid.add(g1, 0, 1)
	mut pan := panel()
	pan.css.classes = ['p']
	mut pl := label('p')
	pan.set_child(pl)
	root.add(card)
	root.add(row)
	root.add(btn_row)
	root.add(grid)
	root.add(pan)
	t.app.set_stylesheet(parse_stylesheet('
		.card { padding: 10 20; gap: 15; }
		.row { gap: 3 25; }
		.wide { padding: 0 40; }
		.g { padding: 7; gap: 0 11; }
		.p { padding: 2 4 6 9; }
	', 't.css')!)
	t.add(root)
	t.frame()
	cb := card.box.bounds
	assert a.bounds.x == cb.x + 20 && a.bounds.y == cb.y + 10
	assert b.bounds.y - (a.bounds.y + a.bounds.h) == 15, 'gap между строками vbox'
	assert c.bounds.x == inner.box.bounds.x, 'вложенный vbox - без padding родителя'
	assert cb.h == 10 + a.bounds.h + 15 + b.bounds.h + 15 + inner.box.bounds.h + 10
	assert y.bounds.x - (x.bounds.x + x.bounds.w) == 25, 'у hbox gap - колонки (второе число)'
	assert btn.bounds.w - plain_btn.bounds.w == 80 - 2 * measure_pad_x
	gb := grid.bounds
	assert g0.bounds.x == gb.x + 7 && g0.bounds.y == gb.y + 7
	assert g1.bounds.x - (g0.bounds.x + g0.bounds.w) == 11
	assert pl.bounds.x == pan.bounds.x + 9 && pl.bounds.y == pan.bounds.y + 2
	assert pan.bounds.h == pl.bounds.h + 8
	// снятие стилей - свои отступы
	t.app.set_stylesheet(unsafe { nil })
	t.frame()
	assert a.bounds.x == card.box.bounds.x
}

// Событие видит тот же шрифт, что и отрисовка: поле ввода в .code рисуется
// моноширинным, и клик ставит курсор по ширине моноширинного текста.
fn test_event_uses_css_font() {
	mut t := new_test_ui(width: 400, height: 120)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	root.css.classes = ['code']
	mut input := text_input('')
	input.set_text('iiiiiiiiiiWWWWW')
	root.add(input)
	t.app.set_stylesheet(parse_stylesheet('.code { font-family: monospace; }', 't.css')!)
	t.add(root)
	t.frame()
	mono := t.win.ctx.get_font(.mono, input.fit_font_size())
	x := input.bounds.x + input.pad + t.win.ctx.measure_text_with_font('iiiiiiiiii', mono).x
	t.click(x, input.bounds.y + input.bounds.h / 2)
	assert input.cur == 10, 'курсор - по моноширинному шрифту, а не по обычному (${input.cur})'
	assert t.win.ctx.css_stack.len == 0 && !t.win.ctx.theme.font_mono
}

fn test_size_errors() {
	assert css_err('.a { width: -5; }').contains('неотрицательное')
	assert css_err('.a { min-width: 10 20; }').contains('одно неотрицательное')
	assert css_err(':root { width: 100; }').contains('неприменимо к :root')
	assert css_err('menu { max-height: 100; }').contains('неприменимо к menu')
	assert css_err(':root { color: #fff; } .a { width: 10px; height: 0; }') == ''
}

// width/height фиксируют размер, min-/max- ограничивают: у виджета по
// содержимому, у растягиваемого и у ребёнка с весом (flex) в vbox/hbox.
fn test_sizes_limit_layout() {
	mut t := new_test_ui(width: 500, height: 500)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut row := create_hbox_fill()
	mut fixed_btn := button('OK')
	fixed_btn.css.classes = ['w150']
	mut wide_lbl := label('x')
	wide_lbl.css.classes = ['min100']
	mut narrow_btn := button('A rather long caption')
	narrow_btn.css.classes = ['max60']
	row.add(fixed_btn)
	row.add(wide_lbl)
	row.add(narrow_btn)
	mut tall_btn := button('Tall')
	tall_btn.css.classes = ['h50']
	// растягиваемый список с весом - но не выше 90
	mut short_list := list_box()
	short_list.css.classes = ['short']
	mut rest := list_box()
	root.add(row)
	root.add(tall_btn)
	root.add(short_list, flex: 1)
	root.add(rest, flex: 1)
	t.app.set_stylesheet(parse_stylesheet('
		.w150 { width: 150; }
		.min100 { min-width: 100; }
		.max60 { max-width: 60; }
		.h50 { height: 50; min-height: 70; }
		.short { max-height: 90; }
	', 't.css')!)
	t.add(root)
	t.frame()
	assert fixed_btn.bounds.w == 150
	assert wide_lbl.bounds.w == 100
	assert narrow_btn.bounds.w == 60
	assert tall_btn.bounds.h == 70, 'min-height сильнее height, как в CSS'
	assert short_list.bounds.h == 90, 'max-height сильнее веса flex'
	assert rest.bounds.h > 90, 'остаток достался соседу с весом'
	// без стилей - снова по содержимому и весу
	t.app.set_stylesheet(unsafe { nil })
	t.frame()
	assert fixed_btn.bounds.w != 150
	assert short_list.bounds.h == rest.bounds.h
}

fn test_margin_errors() {
	assert css_err('.a { margin: -4; }').contains('неотрицательных')
	assert css_err('.a { margin: 1 2 3 4 5; }').contains('от 1 до 4')
	assert css_err(':root { margin: 4; }').contains('неприменимо к :root')
	assert css_err('input { margin: 4 8; } .x { margin: 0; }') == '', 'margin есть у любого виджета'
}

// margin: место вокруг виджета. Контейнер отводит его вместе с отступом
// (measure), а виджет получает прямоугольник без него - в vbox и hbox (по
// обеим осям), в grid, у ребёнка panel (arrange_child).
fn test_margin_in_containers() {
	mut t := new_test_ui(width: 500, height: 500)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	root.set_spacing(0)
	mut a := button('A')
	mut b := button('B')
	b.css.classes = ['m']
	mut c := button('C')
	root.add(a)
	root.add(b)
	root.add(c)
	mut row := create_hbox_fill()
	row.set_spacing(0)
	mut x := label('x')
	mut y := label('y')
	y.css.classes = ['side']
	row.add(x)
	row.add(y)
	root.add(row)
	mut grid := create_grid(2, 1)
	grid.set_spacing(0, 0)
	mut g0 := label('0')
	mut g1 := label('1')
	g1.css.classes = ['side']
	grid.add(g0, 0, 0)
	grid.add(g1, 0, 1)
	root.add(grid)
	mut pan := panel()
	pan.pad = 0
	mut inner := label('in')
	inner.css.classes = ['m']
	pan.set_child(inner)
	root.add(pan)
	t.app.set_stylesheet(parse_stylesheet('
		.m { margin: 10 20 30 40; }
		.side { margin: 0 0 0 15; }
	', 't.css')!)
	t.add(root)
	t.frame()
	// vbox: сверху 10, снизу 30 до следующего; поперёк - слева 40, справа 20
	assert b.bounds.y - (a.bounds.y + a.bounds.h) == 10
	assert c.bounds.y - (b.bounds.y + b.bounds.h) == 30
	rb := root.box.bounds
	assert b.bounds.x == rb.x + 40
	assert b.bounds.x + b.bounds.w == rb.x + rb.w - 20
	assert b.bounds.h == a.bounds.h, 'margin не меняет размер самого виджета'
	// hbox и grid: отступ слева
	assert y.bounds.x - (x.bounds.x + x.bounds.w) == 15
	assert g1.bounds.x - (g0.bounds.x + g0.bounds.w) == 15
	// panel: ребёнок со своим margin, панель выросла на него
	assert inner.bounds.x == pan.bounds.x + 40 && inner.bounds.y == pan.bounds.y + 10
	assert pan.bounds.h == inner.bounds.h + 40
	// без стилей - вплотную
	t.app.set_stylesheet(unsafe { nil })
	t.frame()
	assert b.bounds.y == a.bounds.y + a.bounds.h
}
