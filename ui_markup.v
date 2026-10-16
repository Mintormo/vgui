module vgui

import os

// ═══════════════════════════════════════════════════════
// ui_markup — компактная разметка интерфейса (файлы .vui)
// ═══════════════════════════════════════════════════════
//
// Одна строка - один элемент, вложенность - отступом (пробелы):
//
//   vbox pad=12 gap=8
//     hbox
//       button "Сохранить" icon=save #save
//       spacer
//       toggle "Тёмная тема" #dark
//     hbox flex=1
//       tree #files flex=1
//       textarea #note flex=2 hint="Текст заметки"
//     label "Готово" #status
//
// Строка: тип, затем в любом порядке
//   "текст"    - строка в кавычках (экранирование \" \\ \n \t); у некоторых
//                элементов их несколько (ячейки строки list);
//   @ключ      - текст из перевода: tr('ключ');
//   #id        - имя, по которому код находит элемент: ui.get[Button]('save');
//   .класс     - класс для селекторов CSS (css.v); у виджета их может быть несколько;
//   ключ=знач  - свойство; значение - слово до пробела или "строка";
//   слово      - флаг, то же что слово=true (checked, bold, vertical...).
// Комментарий - // до конца строки (вне кавычек). Пустые строки пропускаются.
// Табуляция в отступе - ошибка: ширина таба неоднозначна.
//
// Свойства раскладки ребёнка vbox/hbox: flex, min, max, align
// (stretch|start|center|end) - как у box.add(w, flex:, min:, max:, align:).
//
// Обработчики событий в разметке НЕ пишутся: файл описывает только вид, а код
// находит элементы по #id и вешает колбэки - так имена функций не живут в
// строках, и опечатку ловит компилятор.
//
// Ошибки громкие: неизвестный тип, неизвестное или неприменимое свойство,
// лишний текст, дубль #id, неверный отступ - ошибка с номером строки, а не
// молчаливое «пропустить». Полный список элементов и свойств - PROJECT.md,
// «Разметка интерфейса (.vui)».

// Ui - построенный интерфейс: корень и элементы с #id. Хранит и объекты, на
// которые виджеты держат голые указатели (подсветка синтаксиса), - держите Ui
// живым, пока жив интерфейс.
@[heap]
pub struct Ui {
pub:
	root &Widget = unsafe { nil }
pub mut:
	widgets map[string]&Widget
	items   map[string]&MenuItem
	nodes   map[string]&TreeNode
mut:
	keep []voidptr
}

// get - элемент #id как виджет типа T: ui.get[Button]('save')!. Ошибка - нет
// такого id или у него другой тип.
pub fn (ui &Ui) get[T](id string) !&T {
	w := ui.widgets[id] or { return error('в разметке нет #${id}') }
	if w is T {
		return w
	}
	return error('#${id} - не ${T.name.all_after_last('.')}')
}

// widget - элемент #id как Widget (none - нет такого id).
pub fn (ui &Ui) widget(id string) ?&Widget {
	return ui.widgets[id] or { return none }
}

// root_ptr / widget_ptr - адрес структуры виджета (а не интерфейса Widget) для
// биндингов: по нему C-ABI и Python работают с виджетом как с созданным
// фабрикой (тип - по тегу, vgui_widget_tag). nil - нет такого id.
pub fn (ui &Ui) root_ptr() voidptr {
	return widget_object_addr(ui.root)
}

pub fn (ui &Ui) widget_ptr(id string) voidptr {
	w := ui.widgets[id] or { return unsafe { nil } }
	return widget_object_addr(w)
}

// item - пункт меню #id (item, check, submenu внутри menubar).
pub fn (ui &Ui) item(id string) ?&MenuItem {
	return ui.items[id] or { return none }
}

// node - узел дерева #id.
pub fn (ui &Ui) node(id string) ?&TreeNode {
	return ui.nodes[id] or { return none }
}

// ids - все #id разметки (виджеты, пункты меню, узлы), по алфавиту.
pub fn (ui &Ui) ids() []string {
	mut r := []string{}
	for k, _ in ui.widgets {
		r << k
	}
	for k, _ in ui.items {
		r << k
	}
	for k, _ in ui.nodes {
		r << k
	}
	r.sort()
	return r
}

// ui_parse строит интерфейс из текста разметки. name - имя источника для
// сообщений об ошибках ('файл.vui:12: ...').
pub fn ui_parse(src string, name string) !&Ui {
	mut root := ui_markup_tree(src, name)!
	mut b := UiBuilder{
		name: name
		ui:   &Ui{}
	}
	w := b.build(mut root)!
	b.finish(root)!
	return &Ui{
		...b.ui
		root: w
	}
}

// ui_load читает и строит файл разметки.
pub fn ui_load(path string) !&Ui {
	src := os.read_file(path) or { return error('не удалось прочитать ${path}: ${err}') }
	return ui_parse(src, path)
}

// ─── Разбор текста в дерево узлов ──────────────────────

@[heap]
struct UiNode {
mut:
	typ   string
	texts []string
	id    string
	// classes — `.класс` для селекторов CSS (css.v); classes_used - их забрал
	// виджет (build). Иначе finish() - ошибка: у пунктов меню, вкладок, ячеек
	// классов нет, как и #id.
	classes      []string
	classes_used bool
	props        map[string]string
	used         map[string]bool
	line         int
	indent       int
	children     []&UiNode
}

// ui_markup_tree разбирает текст в дерево узлов (ровно один корень).
fn ui_markup_tree(src string, name string) !&UiNode {
	mut roots := []&UiNode{}
	// стек открытых узлов: у каждого следующего отступ строго больше
	mut open_nodes := []&UiNode{}
	for i, raw in src.split_into_lines() {
		ln := i + 1
		mut indent := 0
		for indent < raw.len && (raw[indent] == ` ` || raw[indent] == `\t`) {
			if raw[indent] == `\t` {
				return error('${name}:${ln}: табуляция в отступе - используйте пробелы')
			}
			indent++
		}
		body := ui_strip_comment(raw[indent..]).trim_space()
		if body.len == 0 {
			continue
		}
		mut n := ui_parse_line(body, name, ln)!
		n.indent = indent
		// закрываем узлы не левее текущей строки; последний закрытый - сосед,
		// и его отступ обязан совпасть (иначе строка «между» уровнями)
		mut last_closed := -1
		for open_nodes.len > 0 && open_nodes.last().indent >= indent {
			last_closed = open_nodes.pop().indent
		}
		if last_closed >= 0 && last_closed != indent {
			return error('${name}:${ln}: отступ не совпадает ни с одним уровнем выше')
		}
		if open_nodes.len == 0 {
			roots << n
		} else {
			mut parent := open_nodes.last()
			parent.children << n
		}
		open_nodes << n
	}
	if roots.len == 0 {
		return error('${name}: разметка пуста')
	}
	if roots.len > 1 {
		return error('${name}:${roots[1].line}: корень должен быть один - оберните элементы в vbox')
	}
	return roots[0]
}

// ui_strip_comment отрезает // до конца строки (вне кавычек).
fn ui_strip_comment(s string) string {
	mut in_str := false
	mut i := 0
	for i < s.len {
		c := s[i]
		if in_str {
			if c == `\\` {
				i += 2
				continue
			}
			if c == `"` {
				in_str = false
			}
		} else if c == `"` {
			in_str = true
		} else if c == `/` && i + 1 < s.len && s[i + 1] == `/` {
			return s[..i]
		}
		i++
	}
	return s
}

// ui_read_string читает строку в кавычках с позиции i (на открывающей
// кавычке); возвращает текст и позицию после закрывающей.
fn ui_read_string(s string, start int, name string, ln int) !(string, int) {
	mut sb := []u8{}
	mut i := start + 1
	for i < s.len {
		c := s[i]
		if c == `\\` && i + 1 < s.len {
			sb << match s[i + 1] {
				`n` { `\n` }
				`t` { `\t` }
				else { s[i + 1] }
			}
			i += 2
			continue
		}
		if c == `"` {
			return sb.bytestr(), i + 1
		}
		sb << c
		i++
	}
	return error('${name}:${ln}: не закрыта кавычка')
}

// ui_parse_line разбирает одну строку: тип и токены.
fn ui_parse_line(s string, name string, ln int) !&UiNode {
	mut n := &UiNode{
		line: ln
	}
	mut i := 0
	mut first := true
	for i < s.len {
		if s[i] == ` ` {
			i++
			continue
		}
		if s[i] == `"` {
			if first {
				return error('${name}:${ln}: строка должна начинаться с типа элемента')
			}
			text, next := ui_read_string(s, i, name, ln)!
			n.texts << text
			i = next
			continue
		}
		// слово до пробела или '='
		mut j := i
		for j < s.len && s[j] != ` ` && s[j] != `=` {
			j++
		}
		word := s[i..j]
		if first {
			n.typ = word
			first = false
			if j < s.len && s[j] == `=` {
				return error('${name}:${ln}: строка должна начинаться с типа элемента')
			}
			i = j
			continue
		}
		if j < s.len && s[j] == `=` {
			if word.len == 0 {
				return error('${name}:${ln}: свойство без имени перед "="')
			}
			mut value := ''
			mut k := j + 1
			if k < s.len && s[k] == `"` {
				value, k = ui_read_string(s, k, name, ln)!
			} else {
				mut e := k
				for e < s.len && s[e] != ` ` {
					e++
				}
				value = s[k..e]
				k = e
			}
			if word in n.props {
				return error('${name}:${ln}: свойство ${word} указано дважды')
			}
			n.props[word] = value
			i = k
			continue
		}
		if word.starts_with('#') {
			if word.len == 1 {
				return error('${name}:${ln}: пустой #id')
			}
			if n.id.len > 0 {
				return error('${name}:${ln}: у элемента два #id')
			}
			n.id = word[1..]
		} else if word.starts_with('.') {
			if word.len == 1 || !word[1..].bytes().all(css_is_ident_char(it)) {
				return error('${name}:${ln}: ${word}: имя класса - буквы, цифры, - и _')
			}
			if word[1..] in n.classes {
				return error('${name}:${ln}: класс ${word} указан дважды')
			}
			n.classes << word[1..]
		} else if word.starts_with('@') {
			n.texts << tr(word[1..])
		} else {
			if word in n.props {
				return error('${name}:${ln}: свойство ${word} указано дважды')
			}
			n.props[word] = 'true'
		}
		i = j
	}
	return n
}

// ─── Строитель виджетов ────────────────────────────────

struct UiBuilder {
	name string
mut:
	ui &Ui
}

fn (b &UiBuilder) fail(n &UiNode, msg string) IError {
	return error('${b.name}:${n.line}: ${msg}')
}

// ── чтение свойств (отмечают свойство использованным) ──

fn (b &UiBuilder) has_prop(mut n UiNode, key string) bool {
	return key in n.props
}

fn (b &UiBuilder) prop_str(mut n UiNode, key string, def string) string {
	v := n.props[key] or { return def }
	n.used[key] = true
	return v
}

fn (b &UiBuilder) prop_num(mut n UiNode, key string, def f32) !f32 {
	v := n.props[key] or { return def }
	n.used[key] = true
	if !ui_is_number(v) {
		return b.fail(n, '${key}=${v}: ожидается число')
	}
	return v.f32()
}

fn (b &UiBuilder) prop_int(mut n UiNode, key string, def int) !int {
	v := n.props[key] or { return def }
	n.used[key] = true
	if !ui_is_number(v) || v.contains('.') {
		return b.fail(n, '${key}=${v}: ожидается целое число')
	}
	return v.int()
}

fn (b &UiBuilder) prop_flag(mut n UiNode, key string) !bool {
	v := n.props[key] or { return false }
	n.used[key] = true
	if v in ['true', 'yes', '1'] {
		return true
	}
	if v in ['false', 'no', '0'] {
		return false
	}
	return b.fail(n, '${key}=${v}: ожидается true или false')
}

// color - цвет #rrggbb[aa]; второй результат - задан ли он вообще.
fn (b &UiBuilder) prop_color(mut n UiNode, key string) !(Color, bool) {
	v := n.props[key] or { return Color{}, false }
	n.used[key] = true
	c := cp_parse_hex(v) or {
		return b.fail(n, '${key}=${v}: ожидается цвет #rrggbb или #rrggbbaa')
	}
	return c, true
}

// choice - значение из списка допустимых (ошибка перечисляет их).
fn (b &UiBuilder) prop_choice(mut n UiNode, key string, allowed []string, def string) !string {
	v := n.props[key] or { return def }
	n.used[key] = true
	if v !in allowed {
		return b.fail(n, '${key}=${v}: допустимо ${allowed.join('|')}')
	}
	return v
}

fn ui_is_number(s string) bool {
	if s.len == 0 {
		return false
	}
	mut digits := 0
	for i, c in s {
		if c >= `0` && c <= `9` {
			digits++
		} else if !(c == `.` || (c == `-` && i == 0)) {
			return false
		}
	}
	return digits > 0
}

// text - единственный текст элемента ('' - нет); больше одного - ошибка.
fn (b &UiBuilder) text(n &UiNode) !string {
	if n.texts.len > 1 {
		return b.fail(n, '${n.typ}: ожидается один текст, а их ${n.texts.len}')
	}
	return if n.texts.len == 1 { n.texts[0] } else { '' }
}

fn (b &UiBuilder) no_children(n &UiNode) ! {
	if n.children.len > 0 {
		return b.fail(n.children[0], 'у ${n.typ} не может быть вложенных элементов')
	}
}

// finish - проверка после сборки элемента: все свойства применены.
fn (b &UiBuilder) finish(n &UiNode) ! {
	if n.classes.len > 0 && !n.classes_used {
		return b.fail(n, '.${n.classes[0]}: класс неприменим к ${n.typ} - классы CSS бывают только у виджетов')
	}
	mut keys := n.props.keys()
	keys.sort()
	for k in keys {
		if k !in n.used {
			return b.fail(n, 'свойство ${k} неприменимо к ${n.typ}')
		}
	}
}

// register_id запоминает элемент с #id (дубли - ошибка).
fn (mut b UiBuilder) register_id(n &UiNode, w &Widget) ! {
	if n.id.len == 0 {
		return
	}
	if n.id in b.ui.widgets || n.id in b.ui.items || n.id in b.ui.nodes {
		return b.fail(n, '#${n.id} уже есть в разметке')
	}
	b.ui.widgets[n.id] = unsafe { w }
}

fn (mut b UiBuilder) register_item(n &UiNode, mi &MenuItem) ! {
	if n.id.len == 0 {
		return
	}
	if n.id in b.ui.widgets || n.id in b.ui.items || n.id in b.ui.nodes {
		return b.fail(n, '#${n.id} уже есть в разметке')
	}
	b.ui.items[n.id] = unsafe { mi }
}

fn (mut b UiBuilder) register_node(n &UiNode, tn &TreeNode) ! {
	if n.id.len == 0 {
		return
	}
	if n.id in b.ui.widgets || n.id in b.ui.items || n.id in b.ui.nodes {
		return b.fail(n, '#${n.id} уже есть в разметке')
	}
	b.ui.nodes[n.id] = unsafe { tn }
}

// build - виджет узла n и всего его поддерева. Свойства раскладки (flex...)
// читает родитель, он же зовёт finish(n).
fn (mut b UiBuilder) build(mut n UiNode) !&Widget {
	mut w := b.build_widget(mut n)!
	// disabled - у любого элемента (enabled.v); у контейнера гасит всё поддерево
	if b.prop_flag(mut n, 'disabled')! {
		set_widget_enabled(mut w, false)
	}
	// tooltip - у любого элемента (поле tooltip, показывает окно -
	// tooltip_manager.v); у контейнера - подсказка всей его площади
	if b.has_prop(mut n, 'tooltip') {
		if !set_widget_tooltip(mut w, b.prop_str(mut n, 'tooltip', '')) {
			return b.fail(n, 'tooltip: у ${n.typ} подсказки нет')
		}
	}
	b.register_id(n, w)!
	// #id и .классы - ещё и метки для селекторов CSS (css_apply.v)
	if n.id.len > 0 {
		set_css_id(mut w, n.id)
	}
	for cls in n.classes {
		add_css_class(mut w, cls)
	}
	n.classes_used = true
	return w
}

// build_widget - выбор строителя по типу. match - оператором с return в каждой
// ветке: match-выражение с `!` в ветках и интерфейсным результатом V
// компилирует в невалидный C (PROJECT.md, «Компилятор V»).
fn (mut b UiBuilder) build_widget(mut n UiNode) !&Widget {
	match n.typ {
		'vbox', 'hbox' { return b.build_box(mut n) }
		'panel' { return b.build_panel(mut n) }
		'scroll' { return b.build_scroll(mut n) }
		'grid' { return b.build_grid(mut n) }
		'split' { return b.build_split(mut n) }
		'tabs' { return b.build_tabs(mut n) }
		'accordion' { return b.build_accordion(mut n) }
		'menubar' { return b.build_menubar(mut n) }
		'combo' { return b.build_combo(mut n) }
		'list' { return b.build_list(mut n) }
		'tree' { return b.build_tree(mut n) }
		else { return b.build_leaf(mut n) }
	}
}

// build_child собирает ребёнка контейнера без свойств раскладки и проверяет его.
fn (mut b UiBuilder) build_child(mut c UiNode) !&Widget {
	w := b.build(mut c)!
	b.finish(c)!
	return w
}

// expect - вложенный элемент должен быть одного из типов (tab, item...).
fn (b &UiBuilder) expect(c &UiNode, parent string, allowed []string) ! {
	if c.typ !in allowed {
		return b.fail(c, 'внутри ${parent} допустимо только ${allowed.join(', ')}, а не ${c.typ}')
	}
}

// single_child - ровно один вложенный виджет (содержимое tab, section, panel).
fn (mut b UiBuilder) single_child(mut n UiNode) !&Widget {
	if n.children.len != 1 {
		return b.fail(n, '${n.typ}: нужен ровно один вложенный элемент, а их ${n.children.len}')
	}
	mut c := n.children[0]
	return b.build_child(mut c)!
}

// ── контейнеры ──

// build_box - vbox/hbox. Своё выравнивание детей поперёк оси - cross=, а
// align= у ребёнка - его место в родителе (как box.add(w, align:)).
fn (mut b UiBuilder) build_box(mut n UiNode) !&Widget {
	if n.texts.len > 0 {
		return b.fail(n, '${n.typ}: текст здесь неприменим')
	}
	pad := b.prop_num(mut n, 'pad', 0)!
	gap := b.prop_num(mut n, 'gap', -1)!
	cross := ui_cross_align(b.prop_choice(mut n, 'cross', ['stretch', 'start', 'center', 'end'],
		'stretch')!)
	bg, has_bg := b.prop_color(mut n, 'bg')!
	mut kids := []&Widget{}
	mut params := []LayoutParams{}
	for mut c in n.children {
		kids << b.build(mut c)!
		params << LayoutParams{
			flex:  b.prop_num(mut c, 'flex', 0)!
			min:   b.prop_num(mut c, 'min', 0)!
			max:   b.prop_num(mut c, 'max', size_unbounded)!
			align: if b.has_prop(mut c, 'align') {
				ui_cross_align(b.prop_choice(mut c, 'align', ['stretch', 'start', 'center', 'end'],
					'stretch')!)
			} else {
				CrossAlign.inherit
			}
		}
		b.finish(c)!
	}
	if n.typ == 'vbox' {
		mut vb := create_vbox_fill()
		for i, w in kids {
			vb.add(w, params[i])
		}
		vb.set_padding(pad)
		if gap >= 0 {
			vb.set_spacing(gap)
		}
		vb.set_cross_align(cross)
		if has_bg {
			vb.set_bg(bg)
		}
		return vb
	}
	mut hb := create_hbox_fill()
	for i, w in kids {
		hb.add(w, params[i])
	}
	hb.set_padding(pad)
	if gap >= 0 {
		hb.set_spacing(gap)
	}
	hb.set_cross_align(cross)
	if has_bg {
		hb.set_bg(bg)
	}
	return hb
}

fn ui_cross_align(s string) CrossAlign {
	return match s {
		'start' { .start }
		'center' { .center }
		'end' { .end }
		else { .stretch }
	}
}

fn (mut b UiBuilder) build_panel(mut n UiNode) !&Widget {
	mut p := panel()
	p.pad = b.prop_num(mut n, 'pad', p.pad)!
	p.radius = b.prop_num(mut n, 'radius', p.radius)!
	bg, has_bg := b.prop_color(mut n, 'bg')!
	if has_bg {
		p.bg = bg
	}
	border, has_border := b.prop_color(mut n, 'border')!
	if has_border {
		p.border = border
	}
	if n.children.len > 0 {
		p.set_child(b.single_child(mut n)!)
	}
	return p
}

fn (mut b UiBuilder) build_scroll(mut n UiNode) !&Widget {
	mut s := if b.prop_flag(mut n, 'horizontal')! { scroll_box_h(0) } else { scroll_box(0) }
	s.pad = b.prop_num(mut n, 'pad', s.pad)!
	s.spacing = b.prop_num(mut n, 'gap', s.spacing)!
	// fit - размер по содержимому (ScrollBox.fit_content: корень диалога «не больше экрана»)
	s.fit_content = b.prop_flag(mut n, 'fit')!
	for mut c in n.children {
		s.add(b.build_child(mut c)!)
	}
	return s
}

fn (mut b UiBuilder) build_grid(mut n UiNode) !&Widget {
	cols := b.prop_int(mut n, 'cols', 2)!
	if cols < 1 {
		return b.fail(n, 'cols должно быть не меньше 1')
	}
	gap := b.prop_num(mut n, 'gap', -1)!
	pad := b.prop_num(mut n, 'pad', -1)!
	// раскладка потоком слева направо: colspan занимает несколько клеток
	mut cells := []&Widget{}
	mut spans := []int{}
	for mut c in n.children {
		w := b.build(mut c)!
		span := b.prop_int(mut c, 'colspan', 1)!
		if span < 1 || span > cols {
			return b.fail(c, 'colspan=${span}: допустимо 1..${cols}')
		}
		b.finish(c)!
		cells << w
		spans << span
	}
	mut row, mut col := 0, 0
	mut places := [][]int{}
	for span in spans {
		if col + span > cols {
			row++
			col = 0
		}
		places << [row, col]
		col += span
		if col >= cols {
			row++
			col = 0
		}
	}
	rows := if col == 0 { row } else { row + 1 }
	mut g := create_grid(cols, max_int(rows, 1))
	if gap >= 0 {
		g.spacing_x = gap
		g.spacing_y = gap
	}
	if pad >= 0 {
		g.pad = pad
	}
	for i, w in cells {
		g.add_span(w, places[i][0], places[i][1], 1, spans[i])
	}
	return g
}

fn (mut b UiBuilder) build_split(mut n UiNode) !&Widget {
	mut s := if b.prop_flag(mut n, 'vertical')! {
		splitter_vertical()
	} else {
		splitter_horizontal()
	}
	ratio := b.prop_num(mut n, 'ratio', -1)!
	if n.children.len != 2 {
		return b.fail(n, 'split: нужно ровно два вложенных элемента, а их ${n.children.len}')
	}
	mut c0 := n.children[0]
	mut c1 := n.children[1]
	s.set_first(b.build_child(mut c0)!)
	s.set_second(b.build_child(mut c1)!)
	if ratio >= 0 {
		s.set_ratio(ratio)
	}
	// keep=first|second size=N - панель держит N px при изменении размера (Splitter.keep)
	keep := b.prop_choice(mut n, 'keep', ['ratio', 'first', 'second'], 'ratio')!
	if keep != 'ratio' {
		s.set_keep(if keep == 'first' { SplitKeep.first } else { SplitKeep.second }, b.prop_num(mut n,
			'size', 0)!)
	}
	return s
}

fn (mut b UiBuilder) build_tabs(mut n UiNode) !&Widget {
	pos := b.prop_choice(mut n, 'pos', ['top', 'bottom', 'left', 'right'], 'top')!
	mut tb := tab_box_at(match pos {
		'bottom' { TabPos.bottom }
		'left' { TabPos.left }
		'right' { TabPos.right }
		else { TabPos.top }
	})
	for mut c in n.children {
		b.expect(c, 'tabs', ['tab'])!
		title := b.text(c)!
		ic := b.prop_str(mut c, 'icon', '')
		content := b.single_child(mut c)!
		b.finish(c)!
		if c.id.len > 0 {
			return b.fail(c, '#id у tab не поддерживается - дайте #id её содержимому')
		}
		tb.add_tab_icon(title, item_icon(ic), content)
	}
	return tb
}

fn (mut b UiBuilder) build_accordion(mut n UiNode) !&Widget {
	mut a := if b.prop_flag(mut n, 'multi')! { accordion_multi() } else { accordion_single() }
	for mut c in n.children {
		b.expect(c, 'accordion', ['section'])!
		title := b.text(c)!
		ic := b.prop_str(mut c, 'icon', '')
		expanded := b.prop_flag(mut c, 'expanded')!
		content := b.single_child(mut c)!
		b.finish(c)!
		if c.id.len > 0 {
			return b.fail(c, '#id у section не поддерживается - дайте #id её содержимому')
		}
		if expanded {
			a.add_section_expanded(title, content)
		} else {
			a.add_section(title, content)
		}
		a.set_section_icon(a.sections.len - 1, item_icon(ic))
	}
	return a
}

// ── меню ──

fn (mut b UiBuilder) build_menubar(mut n UiNode) !&Widget {
	mut bar := menu_bar()
	for mut c in n.children {
		b.expect(c, 'menubar', ['menu'])!
		title := b.text(c)!
		items := b.menu_items(mut c)!
		b.finish(c)!
		bar.add_menu(title, items)
	}
	return bar
}

// menu_items - пункты внутри menu/submenu: item, check, submenu, separator.
fn (mut b UiBuilder) menu_items(mut n UiNode) ![]&MenuItem {
	mut items := []&MenuItem{}
	for mut c in n.children {
		b.expect(c, n.typ, ['item', 'check', 'submenu', 'separator'])!
		mut mi := match c.typ {
			'separator' {
				menu_separator()
			}
			'check' {
				menu_checkbox(b.text(c)!, b.prop_flag(mut c, 'checked')!)
			}
			'submenu' {
				mut sm := menu_submenu(b.text(c)!)
				for child in b.menu_items(mut c)! {
					sm.add(child)
				}
				sm
			}
			else {
				menu_action(b.text(c)!)
			}
		}
		if c.typ != 'submenu' && c.typ != 'separator' {
			b.no_children(c)!
		}
		if c.typ != 'separator' {
			mi.icon = item_icon(b.prop_str(mut c, 'icon', ''))
			mi.shortcut = b.prop_str(mut c, 'shortcut', '')
			mi.enabled = !b.prop_flag(mut c, 'disabled')!
		}
		b.finish(c)!
		b.register_item(c, mi)!
		items << mi
	}
	return items
}

// ── списки ──

fn (mut b UiBuilder) build_combo(mut n UiNode) !&Widget {
	mut cb := combo_box()
	cb.placeholder = b.prop_str(mut n, 'hint', '')
	selected := b.prop_int(mut n, 'selected', -1)!
	for mut c in n.children {
		b.expect(c, 'combo', ['item'])!
		b.no_children(c)!
		cb.add_icon_item(b.text(c)!, item_icon(b.prop_str(mut c, 'icon', '')))
		b.finish(c)!
		if c.id.len > 0 {
			return b.fail(c, '#id у пункта combo не поддерживается')
		}
	}
	if selected >= 0 {
		cb.set_selected(selected)
	}
	return cb
}

fn (mut b UiBuilder) build_list(mut n UiNode) !&Widget {
	mut lb := list_box()
	lb.multi_select = b.prop_flag(mut n, 'multi')!
	selected := b.prop_int(mut n, 'selected', -1)!
	for mut c in n.children {
		b.expect(c, 'list', ['column', 'item'])!
		b.no_children(c)!
		if c.id.len > 0 {
			return b.fail(c, '#id у ${c.typ} не поддерживается')
		}
		if c.typ == 'column' {
			if lb.rows.len > 0 {
				return b.fail(c, 'column должны идти до первого item')
			}
			lb.add_column_full(b.text(c)!, b.prop_num(mut c, 'width', 100)!, 0, b.prop_flag(mut c,
				'sortable')!, ui_text_align(b.prop_choice(mut c, 'align', ['left', 'center', 'right'],
				'left')!))
		} else {
			ic := item_icon(b.prop_str(mut c, 'icon', ''))
			if lb.columns.len == 0 {
				lb.add_item_icon(b.text(c)!, ic)
			} else {
				if c.texts.len > lb.columns.len {
					return b.fail(c, 'ячеек ${c.texts.len}, а колонок ${lb.columns.len}')
				}
				lb.add_row_texts(c.texts)
				lb.set_row_icon(lb.rows.len - 1, ic)
			}
		}
		b.finish(c)!
	}
	if selected >= 0 {
		lb.set_selected(selected)
	}
	return lb
}

fn (mut b UiBuilder) build_tree(mut n UiNode) !&Widget {
	mut tv := tree_view()
	for mut c in n.children {
		tv.add_root(b.tree_node(mut c)!)
	}
	return tv
}

fn (mut b UiBuilder) tree_node(mut n UiNode) !&TreeNode {
	b.expect(n, 'tree', ['node'])!
	mut tn := tree_node_with(b.text(n)!, item_icon(b.prop_str(mut n, 'icon', '')))
	tn.expanded = !b.prop_flag(mut n, 'collapsed')!
	for mut c in n.children {
		tn.add(b.tree_node(mut c)!)
	}
	b.finish(n)!
	b.register_node(n, tn)!
	return tn
}

// ── листовые элементы ──

fn (mut b UiBuilder) build_leaf(mut n UiNode) !&Widget {
	b.no_children(n)!
	text := b.text(n)!
	if text.len > 0 && n.typ in ['slider', 'progress', 'spinbox', 'separator', 'spacer'] {
		return b.fail(n, '${n.typ}: текст здесь неприменим')
	}
	match n.typ {
		'label' {
			mut l := label(text)
			l.font_size = b.prop_int(mut n, 'size', 0)!
			l.font_style = ui_font_style(b.prop_flag(mut n, 'bold')!, b.prop_flag(mut n, 'italic')!,
				b.prop_flag(mut n, 'mono')!)
			l.wrap = b.prop_flag(mut n, 'wrap')!
			l.align = ui_text_align(b.prop_choice(mut n, 'align', ['left', 'center', 'right'],
				'left')!)
			color, has_color := b.prop_color(mut n, 'color')!
			if has_color {
				l.color = color
			}
			return l
		}
		'button' {
			mut bt := button(text)
			bt.icon_name = b.prop_str(mut n, 'icon', '')
			bt.toggle = b.prop_flag(mut n, 'toggle')!
			bt.active = b.prop_flag(mut n, 'active')!
			bt.style = match b.prop_choice(mut n, 'style', ['normal', 'accent', 'outline', 'flat',
				'danger', 'success'], 'normal')! {
				'accent' { ButtonStyle.accent }
				'outline' { ButtonStyle.outline }
				'flat' { ButtonStyle.flat }
				'danger' { ButtonStyle.danger }
				'success' { ButtonStyle.success }
				else { ButtonStyle.normal }
			}
			return bt
		}
		'checkbox' {
			mut cb := checkbox(text)
			cb.checked = b.prop_flag(mut n, 'checked')!
			return cb
		}
		'radio' {
			mut rb := radio_button(text)
			rb.selected = b.prop_flag(mut n, 'checked')!
			rb.radio_group = b.prop_str(mut n, 'group', rb.radio_group)
			return rb
		}
		'shortcut' {
			// поле ввода сочетания (shortcut_input.v); текст - начальное сочетание
			return shortcut_input(text)
		}
		'toggle' {
			mut ts := toggle_switch(text)
			ts.on = b.prop_flag(mut n, 'on')!
			return ts
		}
		'slider' {
			lo := b.prop_num(mut n, 'min', 0)!
			hi := b.prop_num(mut n, 'max', 100)!
			v := b.prop_num(mut n, 'value', lo)!
			mut sl := if b.prop_flag(mut n, 'vertical')! {
				slider_vertical(lo, hi, v)
			} else {
				slider_horizontal(lo, hi, v)
			}
			sl.step = b.prop_num(mut n, 'step', sl.step)!
			sl.show_value = b.prop_flag(mut n, 'show_value')!
			return sl
		}
		'progress' {
			mut p := progress_bar()
			p.set_percent(b.prop_num(mut n, 'value', 0)!)
			return p
		}
		'spinbox' {
			mut sp := spinbox()
			sp.set_range(b.prop_int(mut n, 'min', 0)!, b.prop_int(mut n, 'max', 100)!)
			sp.set_step(b.prop_int(mut n, 'step', 1)!)
			sp.set_value(b.prop_int(mut n, 'value', 0)!)
			return sp
		}
		'input' {
			mut ti := text_input(b.prop_str(mut n, 'hint', ''))
			ti.set_text(text)
			ti.pw_mode = b.prop_flag(mut n, 'password')!
			ti.max_len = b.prop_int(mut n, 'max_len', ti.max_len)!
			return ti
		}
		'textarea' {
			mut ta := text_area(b.prop_str(mut n, 'hint', ''))
			ta.set_text(text)
			return ta
		}
		'code' {
			mut e := code_editor()
			e.set_text(text)
			e.readonly = b.prop_flag(mut n, 'readonly')!
			lang := b.prop_choice(mut n, 'lang', ['v', 'python'], '')!
			if lang.len > 0 {
				h := if lang == 'v' { v_highlighter() } else { python_highlighter() }
				// редактор держит голый указатель - держит подсветку Ui
				b.ui.keep << voidptr(h)
				e.set_highlighter(h)
			}
			return e
		}
		'markdown' {
			return markdown_view_with_text(text)
		}
		'separator' {
			mut sep := separator()
			if b.prop_flag(mut n, 'vertical')! {
				sep.dir = .vertical
			}
			return sep
		}
		'spacer' {
			return create_spacer()
		}
		'icon' {
			mut ic := icon(text)
			ic.size = b.prop_int(mut n, 'size', ic.size)!
			color, has_color := b.prop_color(mut n, 'color')!
			if has_color {
				ic.color = color
			}
			return ic
		}
		'badge' {
			mut bd := badge(text)
			bd.variant = match b.prop_choice(mut n, 'variant', ['info', 'success', 'warning', 'error',
				'neutral', 'accent'], 'info')! {
				'success' { BadgeVariant.success }
				'warning' { BadgeVariant.warning }
				'error' { BadgeVariant.error }
				'neutral' { BadgeVariant.neutral }
				'accent' { BadgeVariant.accent }
				else { BadgeVariant.info }
			}
			return bd
		}
		else {
			return b.fail(n, 'неизвестный элемент ${n.typ}')
		}
	}
}

fn ui_text_align(s string) TextAlign {
	return match s {
		'center' { .center }
		'right' { .right }
		else { .left }
	}
}

fn ui_font_style(bold bool, italic bool, mono bool) FontStyle {
	if mono {
		return if bold { .mono_bold } else { .mono }
	}
	if bold && italic {
		return .bold_italic
	}
	if bold {
		return .bold
	}
	if italic {
		return .italic
	}
	return .regular
}
