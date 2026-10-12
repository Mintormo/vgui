module vgui

import os

// ═══════════════════════════════════════════════════════
// YAML-like UI builder — loads widget trees from .yaml files
// Uses a built-in minimal YAML parser (V has no standard YAML lib)
// ═══════════════════════════════════════════════════════
//
// Декларативный конструктор интерфейса: дерево виджетов описывается текстом
// (YAML-подобным), а имена обработчиков в нём (`on_click: save`) связываются с
// V-функциями через UiCallbacks. Файл состоит из четырёх частей:
//
//   1. Публичные типы: HotkeyBinding, UiCallbacks (реестры обработчиков по
//      именам), UiTree (результат: корень, виджеты по id, горячие клавиши) и
//      геттеры UiTree.get_<виджет>(id).
//   2. Мини-парсер YAML: yaml_parse_lines -> YLine -> YParser -> дерево YNode.
//      Поддерживается только подмножество YAML: отступы, `ключ: значение`,
//      списки `- ...`, скаляры в кавычках; якорей, многострочных скаляров,
//      flow-стиля ({...}, [...]) и комментариев в конце строки НЕТ.
//   3. YamlBuilder: обход YNode и создание виджетов (build_<тип>); поле `type`
//      выбирает тип, остальные ключи - свойства. Незаданное свойство остаётся
//      значением по умолчанию самого виджета (проверка `> 0` / `.len > 0`).
//   4. Публичный API: load_ui_from_string / load_ui_from_file и удобные
//      add_ui_tree / apply_hotkeys для окна, диалога, VBox/HBox и App.
//
// Поток данных: текст -> yaml_parse -> YNode -> YamlBuilder.build_widget ->
// UiTree.root -> window.add_ui_tree(tree). Пример - examples/43_ui_builder.v.
//
// Ошибки в YAML молчаливы: неизвестный `type` превращается в Spacer, неизвестное
// имя обработчика просто не привязывается (разбор не падает). Исключение -
// корень документа не map и нечитаемый файл: load_ui_* вернут error.

// HotkeyBinding - пара «сочетание клавиш -> обработчик», прочитанная из секции
// `hotkeys:` YAML. Применяется через Window.apply_hotkeys / App.apply_hotkeys.
pub struct HotkeyBinding {
pub:
	shortcut string
	handler  fn () = unsafe { nil }
}

// ─── Callback registry ─────────────────────────────────
// Методы on_<вид>(name, handler) ниже просто кладут обработчик в
// соответствующую карту под именем name; повторная регистрация имени
// перезаписывает прежний обработчик.

// UiCallbacks - реестр обработчиков, на которые YAML ссылается по имени
// (`on_click: save` -> click_handlers['save']). Заполняется ДО загрузки YAML:
// builder берёт обработчик в момент создания виджета и сохраняет его в поле
// самого виджета, поэтому регистрация после load_ui_* уже не подействует.
// Какая карта используется, зависит от ключа и типа виджета, например:
//   click_handlers       - on_click кнопки, пункта меню;
//   change_bool_handlers - on_toggle кнопки/пункта меню, on_change чекбокса,
//                          радиокнопки и переключателя;
//   change_str_handlers  - on_change TextInput;
//   change_idx_handlers  - on_change ComboBox/TabBox (индекс, текст);
//   change_f32_handlers  - on_change Slider; change_int_handlers - SpinBox;
//   submit_handlers      - on_submit TextInput; select_handlers - ListBox,
//                          Breadcrumbs (on_click); dbl_click_handlers - ListBox;
//   hotkey_handlers      - on_press из секции hotkeys.
pub struct UiCallbacks {
pub mut:
	click_handlers       map[string]fn ()
	change_bool_handlers map[string]fn (bool)
	change_str_handlers  map[string]fn (string)
	change_idx_handlers  map[string]fn (int, string)
	change_f32_handlers  map[string]fn (f32)
	change_int_handlers  map[string]fn (int)
	submit_handlers      map[string]fn (string)
	select_handlers      map[string]fn (int, string)
	dbl_click_handlers   map[string]fn (int, string)
	hotkey_handlers      map[string]fn ()
}

pub fn (mut cb UiCallbacks) on_change_f32(name string, handler fn (f32)) {
	cb.change_f32_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_change_int(name string, handler fn (int)) {
	cb.change_int_handlers[name] = handler
}

// ui_callbacks создаёт пустой реестр обработчиков.
pub fn ui_callbacks() UiCallbacks {
	return UiCallbacks{}
}

pub fn (mut cb UiCallbacks) on_click(name string, handler fn ()) {
	cb.click_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_change_bool(name string, handler fn (bool)) {
	cb.change_bool_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_change_string(name string, handler fn (string)) {
	cb.change_str_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_change_index(name string, handler fn (int, string)) {
	cb.change_idx_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_submit(name string, handler fn (string)) {
	cb.submit_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_select(name string, handler fn (int, string)) {
	cb.select_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_dbl_click(name string, handler fn (int, string)) {
	cb.dbl_click_handlers[name] = handler
}

pub fn (mut cb UiCallbacks) on_hotkey(name string, handler fn ()) {
	cb.hotkey_handlers[name] = handler
}

// ─── Built result ──────────────────────────────────────

// UiTree - результат загрузки YAML.
//   root    - корень дерева виджетов (добавляется в окно через add_ui_tree);
//   widgets - все виджеты (и MenuItem/TreeNode), у которых в YAML есть `id`,
//             как сырые voidptr; типизированно достаются через get_<виджет>;
//   flex    - flex корневого узла YAML, нужен VBox/HBox.add_ui_tree;
//   hotkeys - привязки из секции `hotkeys:`.
// Виджеты принадлежит дереву: UiTree должен жить, пока они нужны.
pub struct UiTree {
pub mut:
	root    &Widget = unsafe { nil }
	widgets map[string]voidptr
	// Как дерево встаёт в VBox/HBox (add_ui_tree): без flex у
	// корня YAML - естественный размер из measure()
	flex    f32
	hotkeys []HotkeyBinding
}

// get_<виджет>(id) - типизированный доступ к виджету по id из YAML. Если id
// нет в YAML, возвращается nil-указатель (проверяйте `unsafe { w != nil }`).
// ВНИМАНИЕ: проверки типа нет - приведение voidptr к &T слепое (тег типа
// widget_tag.v здесь не сверяется), поэтому id должен принадлежать виджету
// именно запрошенного типа, иначе поведение не определено.
pub fn (t &UiTree) get_breadcrumbs(id string) &Breadcrumbs {
	p := t.widgets[id] or { return unsafe { &Breadcrumbs(nil) } }
	return unsafe { &Breadcrumbs(p) }
}

pub fn (t &UiTree) get_button(id string) &Button {
	p := t.widgets[id] or { return unsafe { &Button(nil) } }
	return unsafe { &Button(p) }
}

pub fn (t &UiTree) get_text_input(id string) &TextInput {
	p := t.widgets[id] or { return unsafe { &TextInput(nil) } }
	return unsafe { &TextInput(p) }
}

pub fn (t &UiTree) get_label(id string) &Label {
	p := t.widgets[id] or { return unsafe { &Label(nil) } }
	return unsafe { &Label(p) }
}

pub fn (t &UiTree) get_checkbox(id string) &CheckBox {
	p := t.widgets[id] or { return unsafe { &CheckBox(nil) } }
	return unsafe { &CheckBox(p) }
}

pub fn (t &UiTree) get_radio_button(id string) &RadioButton {
	p := t.widgets[id] or { return unsafe { &RadioButton(nil) } }
	return unsafe { &RadioButton(p) }
}

pub fn (t &UiTree) get_toggle_switch(id string) &ToggleSwitch {
	p := t.widgets[id] or { return unsafe { &ToggleSwitch(nil) } }
	return unsafe { &ToggleSwitch(p) }
}

pub fn (t &UiTree) get_combo_box(id string) &ComboBox {
	p := t.widgets[id] or { return unsafe { &ComboBox(nil) } }
	return unsafe { &ComboBox(p) }
}

pub fn (t &UiTree) get_list_box(id string) &ListBox {
	p := t.widgets[id] or { return unsafe { &ListBox(nil) } }
	return unsafe { &ListBox(p) }
}

pub fn (t &UiTree) get_tab_box(id string) &TabBox {
	p := t.widgets[id] or { return unsafe { &TabBox(nil) } }
	return unsafe { &TabBox(p) }
}

pub fn (t &UiTree) get_menu_bar(id string) &MenuBar {
	p := t.widgets[id] or { return unsafe { &MenuBar(nil) } }
	return unsafe { &MenuBar(p) }
}

pub fn (t &UiTree) get_menu_item(id string) &MenuItem {
	p := t.widgets[id] or { return unsafe { &MenuItem(nil) } }
	return unsafe { &MenuItem(p) }
}

pub fn (t &UiTree) get_context_menu(id string) &ContextMenu {
	p := t.widgets[id] or { return unsafe { &ContextMenu(nil) } }
	return unsafe { &ContextMenu(p) }
}

pub fn (t &UiTree) get_splitter(id string) &Splitter {
	p := t.widgets[id] or { return unsafe { &Splitter(nil) } }
	return unsafe { &Splitter(p) }
}

pub fn (t &UiTree) get_tree_view(id string) &TreeView {
	p := t.widgets[id] or { return unsafe { &TreeView(nil) } }
	return unsafe { &TreeView(p) }
}

pub fn (t &UiTree) get_spinner(id string) &Spinner {
	p := t.widgets[id] or { return unsafe { &Spinner(nil) } }
	return unsafe { &Spinner(p) }
}

pub fn (t &UiTree) get_tooltip(id string) &Tooltip {
	p := t.widgets[id] or { return unsafe { &Tooltip(nil) } }
	return unsafe { &Tooltip(p) }
}

pub fn (t &UiTree) get_code_editor(id string) &CodeEditor {
	p := t.widgets[id] or { return unsafe { &CodeEditor(nil) } }
	return unsafe { &CodeEditor(p) }
}

pub fn (t &UiTree) get_slider(id string) &Slider {
	p := t.widgets[id] or { return unsafe { &Slider(nil) } }
	return unsafe { &Slider(p) }
}

pub fn (t &UiTree) get_progress_bar(id string) &ProgressBar {
	p := t.widgets[id] or { return unsafe { &ProgressBar(nil) } }
	return unsafe { &ProgressBar(p) }
}

pub fn (t &UiTree) get_accordion(id string) &Accordion {
	p := t.widgets[id] or { return unsafe { &Accordion(nil) } }
	return unsafe { &Accordion(p) }
}

pub fn (t &UiTree) get_image_view(id string) &ImageView {
	p := t.widgets[id] or { return unsafe { &ImageView(nil) } }
	return unsafe { &ImageView(p) }
}

// ═══════════════════════════════════════════════════════
// Minimal YAML parser → YNode tree
// ═══════════════════════════════════════════════════════

// YNode represents a YAML node: scalar, map, or list
//
// Узел YAML-дерева. Вид определяется по заполненности полей (is_scalar /
// is_map / is_list), отдельного тега нет. Map хранится двумя параллельными
// срезами (map_keys[i] <-> map_values[i]) - порядок ключей сохраняется,
// дубликаты ключей не отсекаются (get вернёт первый). Пустой узел YNode{}
// одновременно «скаляр с пустой строкой» - им get() отвечает на отсутствующий ключ.
struct YNode {
mut:
	// Scalar value (leaf)
	val string
	// Map children (key → YNode)
	map_keys   []string
	map_values []YNode
	// List children
	list []YNode
}

fn (n &YNode) is_scalar() bool {
	return n.map_keys.len == 0 && n.list.len == 0
}

fn (n &YNode) is_map() bool {
	return n.map_keys.len > 0
}

fn (n &YNode) is_list() bool {
	return n.list.len > 0
}

// get возвращает значение ключа map-узла или пустой YNode{}, если ключа нет.
fn (n &YNode) get(key string) YNode {
	for i, k in n.map_keys {
		if k == key {
			return n.map_values[i]
		}
	}
	return YNode{}
}

// get_str - скалярное значение ключа ('' если ключа нет или это не скаляр).
fn (n &YNode) get_str(key string) string {
	child := n.get(key)
	return child.val
}

// has - есть ли ключ в map (отличает «ключ не задан» от «задан пустым»).
fn (n &YNode) has(key string) bool {
	for k in n.map_keys {
		if k == key {
			return true
		}
	}
	return false
}

// ─── YAML line representation ──────────────────────────

// YLine - одна значимая строка YAML после лексического разбора:
// отступ, признак элемента списка (`- `), ключ и значение (оба могут быть пустыми).
// raw хранится для отладки; парсер её не читает.
struct YLine {
	indent       int
	raw          string
	is_list_item bool
	key          string
	value        string
}

// yaml_count_indent считает отступ строки: пробел = 1, таб = 2. Таб - не
// «настоящий» YAML (там табы запрещены), здесь он терпится как два пробела.
fn yaml_count_indent(line string) int {
	mut n := 0
	for ch in line.bytes() {
		if ch == ` ` {
			n++
		} else if ch == `\t` {
			n += 2
		} else {
			break
		}
	}
	return n
}

// yaml_strip_quotes обрезает пробелы и одну пару внешних кавычек ('...' или "...").
// Экранирование внутри кавычек не обрабатывается: \" остаётся как есть.
fn yaml_strip_quotes(s string) string {
	t := s.trim_space()
	if t.len >= 2 {
		if (t[0] == `"` && t[t.len - 1] == `"`) || (t[0] == `'` && t[t.len - 1] == `'`) {
			return t[1..t.len - 1]
		}
	}
	return t
}

// yaml_parse_lines - лексер: режет текст на YLine. Пустые строки и строки,
// начинающиеся с `#`, выбрасываются; остальное делится на «- » / ключ / значение.
// Ключом считается всё до ПЕРВОГО двоеточия в строке (`colon > 0`), поэтому
// значения с двоеточием (`time: 12:30`) работают, а ключи с двоеточием - нет.
// Строка без двоеточия - скаляр (элемент `- value` или продолжение).
fn yaml_parse_lines(content string) []YLine {
	raw_lines := content.split('\n')
	mut result := []YLine{cap: raw_lines.len}
	for raw in raw_lines {
		trimmed := raw.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}
		indent := yaml_count_indent(raw)
		mut is_list := false
		mut work := trimmed

		if work.starts_with('- ') {
			is_list = true
			work = work[2..]
		} else if work == '-' {
			is_list = true
			work = ''
		}

		mut key := ''
		mut value := ''
		colon := work.index(':') or { -1 }
		if colon > 0 {
			key = work[..colon].trim_space()
			rest := work[colon + 1..].trim_space()
			value = yaml_strip_quotes(rest)
		} else if work.len > 0 {
			value = yaml_strip_quotes(work)
		}

		result << YLine{
			indent:       indent
			raw:          raw
			is_list_item: is_list
			key:          key
			value:        value
		}
	}
	return result
}

// ─── Recursive YAML tree builder ───────────────────────

// YParser - рекурсивный разбор плоского списка YLine в дерево YNode.
// pos - индекс следующей непрочитанной строки; методы parse_* двигают его
// вперёд. Структура блоков определяется только по отступам строк.
struct YParser {
mut:
	lines []YLine
	pos   int
}

// parse_value разбирает блок, начинающийся с текущей строки, и выбирает вид
// узла по ней: `- ...` -> список, строка с ключом -> map, иначе скаляр.
fn (mut p YParser) parse_value(parent_indent int) YNode {
	if p.pos >= p.lines.len {
		return YNode{}
	}

	// Check if next content is a list
	if p.lines[p.pos].is_list_item {
		return p.parse_list(parent_indent)
	}

	// Check if it's a map (has key)
	if p.lines[p.pos].key.len > 0 {
		return p.parse_map(parent_indent)
	}

	// Scalar
	line := p.lines[p.pos]
	p.pos++
	return YNode{
		val: line.value
	}
}

// parse_map читает пары `ключ: значение` с отступом min_indent. Если после
// `ключ:` значения нет, а следующая строка имеет больший отступ - это вложенный
// блок (parse_value), иначе значение пустое. Выход из цикла: строка с меньшим
// отступом, элемент списка на нашем уровне (он принадлежит родителю-списку)
// или более глубокая строка после первого ключа (её уже разобрал вложенный вызов).
fn (mut p YParser) parse_map(min_indent int) YNode {
	mut node := YNode{}

	for p.pos < p.lines.len {
		line := p.lines[p.pos]
		if line.indent < min_indent {
			break
		}
		if line.is_list_item && line.indent <= min_indent {
			break
		}
		if line.key.len == 0 {
			p.pos++
			continue
		}
		if line.indent > min_indent && node.map_keys.len > 0 {
			// This belongs to a child, not us
			break
		}

		key := line.key
		p.pos++

		if line.value.len > 0 {
			// Inline value
			node.map_keys << key
			node.map_values << YNode{
				val: line.value
			}
		} else {
			// Block value on next lines
			if p.pos < p.lines.len && p.lines[p.pos].indent > line.indent {
				child := p.parse_value(p.lines[p.pos].indent)
				node.map_keys << key
				node.map_values << child
			} else {
				node.map_keys << key
				node.map_values << YNode{}
			}
		}
	}
	return node
}

// parse_list читает элементы списка. Элемент `- key: val` - начало map-элемента:
// первая пара берётся из самой строки со «-», а остальные ключи этого map
// собираются из следующих строк с БОЛЬШИМ отступом (внутренний цикл ниже).
// Элемент `- scalar` даёт скалярный узел. Пустой элемент `-` без значения
// пропускается (в список не попадает).
fn (mut p YParser) parse_list(min_indent int) YNode {
	mut node := YNode{}

	for p.pos < p.lines.len {
		line := p.lines[p.pos]
		if line.indent < min_indent {
			break
		}
		if !line.is_list_item {
			break
		}

		// A list item: "- key: val" or "- val"
		p.pos++

		if line.key.len > 0 {
			// "- key: val" — start of a map item
			mut item := YNode{}
			item.map_keys << line.key
			if line.value.len > 0 {
				item.map_values << YNode{
					val: line.value
				}
			} else {
				if p.pos < p.lines.len && p.lines[p.pos].indent > line.indent {
					child := p.parse_value(p.lines[p.pos].indent)
					item.map_values << child
				} else {
					item.map_values << YNode{}
				}
			}

			// Continue reading map keys at deeper indent
			for p.pos < p.lines.len {
				next := p.lines[p.pos]
				if next.indent <= line.indent {
					break
				}
				if next.is_list_item {
					break
				}
				if next.key.len > 0 {
					item.map_keys << next.key
					p.pos++
					if next.value.len > 0 {
						item.map_values << YNode{
							val: next.value
						}
					} else {
						if p.pos < p.lines.len && p.lines[p.pos].indent > next.indent {
							child := p.parse_value(p.lines[p.pos].indent)
							item.map_values << child
						} else {
							item.map_values << YNode{}
						}
					}
				} else {
					p.pos++
				}
			}

			node.list << item
		} else if line.value.len > 0 {
			// "- scalar"
			node.list << YNode{
				val: line.value
			}
		}
	}
	return node
}

// yaml_parse - точка входа парсера: возвращает корневой узел или пустой YNode{},
// если в тексте нет значимых строк. Корень разбирается по отступу первой строки.
fn yaml_parse(content string) YNode {
	lines := yaml_parse_lines(content)
	if lines.len == 0 {
		return YNode{}
	}
	mut parser := YParser{
		lines: lines
		pos:   0
	}
	return parser.parse_value(lines[0].indent)
}

// ═══════════════════════════════════════════════════════
// YNode → Widget tree builder
// ═══════════════════════════════════════════════════════

// ─── Parse helpers ─────────────────────────────────────

// vui_parse_color разбирает цвет из YAML: `#RRGGBB` (alpha = 255) или
// `#RRGGBBAA` (`#` необязателен). Любая другая длина, в т.ч. пустая строка,
// даёт полностью прозрачный чёрный Color{0,0,0,0}. Неверные hex-цифры
// дают 0 в своём разряде (см. hex_to_u64), ошибки не сообщаются.
fn vui_parse_color(s string) Color {
	if s.len == 0 {
		return Color{0, 0, 0, 0}
	}
	hex := if s.starts_with('#') { s[1..] } else { s }
	if hex.len == 6 {
		v := u32(hex_to_u64(hex))
		return Color{
			r: u8((v >> 16) & 0xFF)
			g: u8((v >> 8) & 0xFF)
			b: u8(v & 0xFF)
			a: 255
		}
	}
	if hex.len == 8 {
		v := u32(hex_to_u64(hex))
		return Color{
			r: u8((v >> 24) & 0xFF)
			g: u8((v >> 16) & 0xFF)
			b: u8((v >> 8) & 0xFF)
			a: u8(v & 0xFF)
		}
	}
	return Color{0, 0, 0, 0}
}

// hex_to_u64 - ручной разбор hex-строки; недопустимый символ считается нулевой цифрой.
fn hex_to_u64(s string) u64 {
	mut r := u64(0)
	for ch in s.bytes() {
		mut d := u64(0)
		if ch >= `0` && ch <= `9` {
			d = u64(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			d = u64(ch - `a` + 10)
		} else if ch >= `A` && ch <= `F` {
			d = u64(ch - `A` + 10)
		}
		r = r * 16 + d
	}
	return r
}

// yn_* - типизированное чтение свойства узла n по ключу key. Отсутствующий
// ключ даёт нулевое значение типа (0 / '') или def у yn_bool, поэтому
// «не задано» и «задано нулём» различимы только через n.has(key).
// yn_bool: true для 'true' / '1' / 'yes', всё остальное (даже 'on') - false.
fn yn_str(n &YNode, key string) string {
	return n.get_str(key)
}

fn yn_f32(n &YNode, key string) f32 {
	s := n.get_str(key)
	if s.len == 0 {
		return 0
	}
	return s.f32()
}

fn yn_int(n &YNode, key string) int {
	s := n.get_str(key)
	if s.len == 0 {
		return 0
	}
	return s.int()
}

fn yn_bool(n &YNode, key string, def bool) bool {
	s := n.get_str(key)
	if s.len == 0 {
		return def
	}
	return s == 'true' || s == '1' || s == 'yes'
}

// yn_items читает список строк: YAML-список (`items:` + `- a`) либо
// строку через запятую (`items: a,b,c`; пробелы вокруг элементов не режутся).
fn yn_items(n &YNode, key string) []string {
	child := n.get(key)
	if child.is_list() {
		mut result := []string{cap: child.list.len}
		for item in child.list {
			result << item.val
		}
		return result
	}
	// Fallback: comma-separated string
	s := child.val
	if s.len == 0 {
		return []
	}
	return s.split(',')
}

// vui_parse_*: преобразование строки из YAML в enum. Неизвестное значение
// молча даёт значение по умолчанию (regular / left / top / normal).
fn vui_parse_font_style(s string) FontStyle {
	return match s {
		'bold' { FontStyle.bold }
		'italic' { FontStyle.italic }
		'bold_italic' { FontStyle.bold_italic }
		'mono' { FontStyle.mono }
		'mono_bold' { FontStyle.mono_bold }
		else { FontStyle.regular }
	}
}

fn vui_parse_text_align(s string) TextAlign {
	return match s {
		'center' { TextAlign.center }
		'right' { TextAlign.right }
		else { TextAlign.left }
	}
}

fn vui_parse_valign(s string) VAlign {
	return match s {
		'middle' { VAlign.middle }
		'bottom' { VAlign.bottom }
		else { VAlign.top }
	}
}

fn vui_parse_button_style(s string) ButtonStyle {
	return match s {
		'accent' { ButtonStyle.accent }
		'outline' { ButtonStyle.outline }
		'flat' { ButtonStyle.flat }
		'danger' { ButtonStyle.danger }
		'success' { ButtonStyle.success }
		else { ButtonStyle.normal }
	}
}

// ─── VuiChild ──────────────────────────────────────────

// VuiChild - построенный виджет вместе с параметрами раскладки, которые
// YAML задаёт на самом узле (flex/min/max/align). Родитель-контейнер
// применяет их при добавлении ребёнка (vui_child_params).
struct VuiChild {
mut:
	widget &Widget = unsafe { nil }
	flex   f32
	// Параметры раскладки (см. layout.v): без flex -
	// естественный размер из measure(); min/max - границы вдоль
	// главной оси, align - выравнивание поперёк неё.
	min   f32
	max   f32
	align CrossAlign = .inherit
}

// vui_parse_cross_align читает выравнивание из YAML:
// stretch (по умолчанию) | start | center | end.
fn vui_parse_cross_align(s string) CrossAlign {
	return match s {
		'start' { CrossAlign.start }
		'center' { CrossAlign.center }
		'end' { CrossAlign.end }
		'stretch' { CrossAlign.stretch }
		else { CrossAlign.inherit }
	}
}

// vui_child_params переводит параметры ребёнка в LayoutParams для box.add().
// Общая часть build_vbox/build_hbox. max == 0 в YAML значит «без ограничения»
// и превращается в size_unbounded.
fn vui_child_params(child VuiChild) LayoutParams {
	return LayoutParams{
		flex:  child.flex
		min:   child.min
		max:   if child.max > 0 { child.max } else { size_unbounded }
		align: child.align
	}
}

// ─── Builder ───────────────────────────────────────────

// YamlBuilder - состояние одной загрузки: cb - реестр обработчиков (только
// чтение), tree - накапливаемый результат (в первую очередь карта id -> виджет).
struct YamlBuilder {
mut:
	cb   &UiCallbacks
	tree UiTree
}

// build_widget строит виджет по узлу n и читает параметры раскладки
// flex/min/max/align, общие для любого типа (имеют смысл, если родитель - box).
fn (mut b YamlBuilder) build_widget(n &YNode) VuiChild {
	wtype := yn_str(n, 'type')
	flex := yn_f32(n, 'flex')
	min := yn_f32(n, 'min')
	max := yn_f32(n, 'max')
	align := vui_parse_cross_align(yn_str(n, 'align'))

	wgt := b.build_widget_by_type(wtype, n)

	return VuiChild{
		widget: wgt
		flex:   flex
		min:    min
		max:    max
		align:  align
	}
}

// build_widget_by_type - диспетчер по полю `type`. Контейнеры, spacer,
// separator и icon доступны всегда; остальные виджеты - только если включены
// в сборку (has_<виджет>() из features.v). Неизвестный или выключенный тип
// даёт Spacer, чтобы разметка не ломала раскладку.
// Не все виджеты библиотеки умеют строиться из YAML: нет, например, Grid,
// Table, Calendar, Canvas.
fn (mut b YamlBuilder) build_widget_by_type(wtype string, n &YNode) &Widget {
	// Core containers (always available)
	match wtype {
		'vbox' {
			return b.build_vbox(n)
		}
		'hbox' {
			return b.build_hbox(n)
		}
		'panel' {
			return b.build_panel(n)
		}
		'scroll_box' {
			return b.build_scroll_box(n)
		}
		'stack' {
			return b.build_stack(n)
		}
		'spacer' {
			s := create_spacer()
			b.reg(n, voidptr(s))
			return s
		}
		'separator' {
			return b.build_separator(n)
		}
		'icon' {
			return b.build_icon(n)
		}
		else {}
	}

	// Optional widgets — runtime check via features.v
	if wtype == 'label' && has_label() {
		return b.build_label(n)
	}
	if wtype == 'button' && has_button() {
		return b.build_button(n)
	}
	if wtype == 'text_input' && has_text_input() {
		return b.build_text_input(n)
	}
	if wtype == 'checkbox' && has_checkbox() {
		return b.build_checkbox(n)
	}
	if wtype == 'radio_button' && has_radio_button() {
		return b.build_radio_button(n)
	}
	if wtype == 'toggle_switch' && has_toggle_switch() {
		return b.build_toggle_switch(n)
	}
	if wtype == 'combo_box' && has_combo_box() {
		return b.build_combo_box(n)
	}
	if wtype == 'list_box' && has_list_box() {
		return b.build_list_box(n)
	}
	if wtype == 'tab_box' && has_tab_box() {
		return b.build_tab_box(n)
	}
	if wtype == 'menu_bar' && has_menu() {
		return b.build_menu_bar(n)
	}
	if wtype == 'splitter' && has_splitter() {
		return b.build_splitter(n)
	}
	if wtype == 'tree_view' && has_tree_view() {
		return b.build_tree_view(n)
	}
	if wtype == 'spinner' && has_spinner() {
		return b.build_spinner(n)
	}
	if wtype == 'tooltip' && has_tooltip() {
		return b.build_tooltip(n)
	}
	if wtype == 'code_editor' && has_code_editor() {
		return b.build_code_editor(n)
	}
	if wtype == 'slider' && has_slider() {
		return b.build_slider(n)
	}
	if wtype == 'progress_bar' && has_progress_bar() {
		return b.build_progress_bar(n)
	}
	if wtype == 'image_view' && has_image_view() {
		return b.build_image_view(n)
	}
	if wtype == 'accordion' && has_accordion() {
		return b.build_accordion(n)
	}
	if wtype == 'spinbox' && has_spinbox() {
		return b.build_spinbox(n)
	}
	if wtype == 'breadcrumbs' && has_breadcrumbs() {
		return b.build_breadcrumbs(n)
	}

	return create_spacer()
}

// build_children строит всех детей из списка `children:` узла n (в порядке
// записи); если ключа нет или это не список - пустой срез.
fn (mut b YamlBuilder) build_children(n &YNode) []VuiChild {
	children_node := n.get('children')
	if !children_node.is_list() {
		return []
	}
	mut result := []VuiChild{cap: children_node.list.len}
	for child_n in children_node.list {
		result << b.build_widget(&child_n)
	}
	return result
}

// reg запоминает виджет в tree.widgets под его `id` (если id задан).
// Повторный id перезаписывает предыдущий виджет без предупреждения.
fn (mut b YamlBuilder) reg(n &YNode, ptr voidptr) {
	id := yn_str(n, 'id')
	if id.len > 0 {
		b.tree.widgets[id] = ptr
	}
}

// ─── Widget builders ───────────────────────────────────
// build_<виджет>(n) - единая схема: создать виджет фабрикой, перенести из YAML
// заданные свойства (числовые, как правило, - только если > 0, строки и цвета - только если
// непустые, чтобы не затирать значения по умолчанию; флаги visible/enabled -
// по умолчанию true), привязать обработчики из UiCallbacks по имени
// (`h != nil` - неизвестное имя игнорируется), зарегистрировать id через reg
// и вернуть виджет. Контейнеры дополнительно строят детей рекурсивно.
// Ключи YAML совпадают с именами полей виджета (см. его struct), поэтому
// каждый ключ ниже отдельно не комментируется.

fn (mut b YamlBuilder) build_breadcrumbs(n &YNode) &Widget {
	mut bc := breadcrumbs()
	bc.visible = yn_bool(n, 'visible', true)
	bc.enabled = yn_bool(n, 'enabled', true)
	bc.current_clickable = yn_bool(n, 'current_clickable', false)

	sep := yn_str(n, 'separator')
	if sep.len > 0 {
		bc.separator = sep
	}
	fs := yn_str(n, 'font_style')
	if fs.len > 0 {
		bc.font_style = vui_parse_font_style(fs)
	}
	fsize := yn_int(n, 'font_size')
	if fsize > 0 {
		bc.font_size = fsize
	}
	ph := yn_f32(n, 'pad_h')
	if ph > 0 {
		bc.pad_h = ph
	}
	pv := yn_f32(n, 'pad_v')
	if pv > 0 {
		bc.pad_v = pv
	}
	rad := yn_f32(n, 'radius')
	if n.has('radius') {
		bc.radius = rad
	}

	// Colors
	bg := yn_str(n, 'bg_color')
	if bg.len > 0 {
		bc.bg_color = vui_parse_color(bg)
	}
	bd := yn_str(n, 'border_color')
	if bd.len > 0 {
		bc.border_color = vui_parse_color(bd)
	}
	tc := yn_str(n, 'text_color')
	if tc.len > 0 {
		bc.text_color = vui_parse_color(tc)
	}
	hc := yn_str(n, 'hover_color')
	if hc.len > 0 {
		bc.hover_color = vui_parse_color(hc)
	}
	cc := yn_str(n, 'current_color')
	if cc.len > 0 {
		bc.current_color = vui_parse_color(cc)
	}
	sc := yn_str(n, 'separator_color')
	if sc.len > 0 {
		bc.separator_color = vui_parse_color(sc)
	}
	hbg := yn_str(n, 'hover_bg_color')
	if hbg.len > 0 {
		bc.hover_bg_color = vui_parse_color(hbg)
	}

	// Items
	items := yn_items(n, 'items')
	if items.len > 0 {
		bc.set_items(items)
	}

	// Callback
	oc := yn_str(n, 'on_click')
	if oc.len > 0 {
		h := b.cb.select_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			bc.on_click = h
		}
	}

	b.reg(n, voidptr(bc))
	return bc
}

fn (mut b YamlBuilder) build_spinbox(n &YNode) &Widget {
	mut s := spinbox()
	s.visible = yn_bool(n, 'visible', true)
	s.enabled = yn_bool(n, 'enabled', true)
	s.focus_group = yn_int(n, 'focus_group')
	s.value = yn_int(n, 'value')
	s.min = yn_int(n, 'min')
	s.max = yn_int(n, 'max')
	step := yn_int(n, 'step')
	if step > 0 {
		s.step = step
	}
	s.prefix = yn_str(n, 'prefix')
	s.suffix = yn_str(n, 'suffix')
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_int_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			s.on_change = h
		}
	}
	b.reg(n, voidptr(s))
	return s
}

fn (mut b YamlBuilder) build_label(n &YNode) &Widget {
	mut l := label(yn_str(n, 'text'))
	l.font_style = vui_parse_font_style(yn_str(n, 'font_style'))
	fs := yn_int(n, 'font_size')
	if fs > 0 {
		l.font_size = fs
	}
	l.align = vui_parse_text_align(yn_str(n, 'align'))
	l.valign = vui_parse_valign(yn_str(n, 'valign'))
	c := yn_str(n, 'color')
	if c.len > 0 {
		l.color = vui_parse_color(c)
	}
	l.wrap = yn_bool(n, 'wrap', false)
	l.clip = yn_bool(n, 'clip', false)
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		l.pad = pad
	}
	lg := yn_f32(n, 'line_gap')
	if lg > 0 {
		l.line_gap = lg
	}
	l.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(l))
	return l
}

fn (mut b YamlBuilder) build_icon(n &YNode) &Widget {
	mut ic := icon(yn_str(n, 'name'))
	sz := yn_int(n, 'size')
	if sz > 0 {
		ic.size = sz
	}
	c := yn_str(n, 'color')
	if c.len > 0 {
		ic.color = vui_parse_color(c)
	}
	ic.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(ic))
	return ic
}

fn (mut b YamlBuilder) build_button(n &YNode) &Widget {
	mut btn := button(yn_str(n, 'text'))
	btn.style = vui_parse_button_style(yn_str(n, 'style'))
	btn.icon_text = yn_str(n, 'icon_text')
	btn.icon_path = yn_str(n, 'icon_path')
	btn.tooltip = yn_str(n, 'tooltip')
	btn.toggle = yn_bool(n, 'toggle', false)
	btn.active = yn_bool(n, 'active', false)
	icon_s := yn_f32(n, 'icon_size')
	if icon_s > 0 {
		btn.icon_size = icon_s
	}
	ig := yn_f32(n, 'icon_gap')
	if ig > 0 {
		btn.icon_gap = ig
	}
	rad := yn_f32(n, 'radius')
	if rad > 0 {
		btn.radius = rad
	}
	bw := yn_f32(n, 'border_width')
	if bw > 0 {
		btn.border_width = bw
	}
	btn.font_style = vui_parse_font_style(yn_str(n, 'font_style'))
	fs := yn_int(n, 'font_size')
	if fs > 0 {
		btn.font_size = fs
	}
	btn.visible = yn_bool(n, 'visible', true)
	btn.enabled = yn_bool(n, 'enabled', true)
	btn.focus_group = yn_int(n, 'focus_group')
	oc := yn_str(n, 'on_click')
	if oc.len > 0 {
		h := b.cb.click_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			btn.on_click = h
		}
	}
	ot := yn_str(n, 'on_toggle')
	if ot.len > 0 {
		h := b.cb.change_bool_handlers[ot] or { unsafe { nil } }
		if h != unsafe { nil } {
			btn.on_toggle = h
		}
	}
	b.reg(n, voidptr(btn))
	return btn
}

fn (mut b YamlBuilder) build_text_input(n &YNode) &Widget {
	mut ti := text_input(yn_str(n, 'placeholder'))
	ti.pw_mode = yn_bool(n, 'pw_mode', false)
	ml := yn_int(n, 'max_len')
	if ml > 0 {
		ti.max_len = ml
	}
	ti.visible = yn_bool(n, 'visible', true)
	ti.enabled = yn_bool(n, 'enabled', true)
	ti.focus_group = yn_int(n, 'focus_group')
	txt := yn_str(n, 'text')
	if txt.len > 0 {
		ti.set_text(txt)
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_str_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			ti.on_change = h
		}
	}
	os_name := yn_str(n, 'on_submit')
	if os_name.len > 0 {
		h := b.cb.submit_handlers[os_name] or { unsafe { nil } }
		if h != unsafe { nil } {
			ti.on_submit = h
		}
	}
	b.reg(n, voidptr(ti))
	return ti
}

fn (mut b YamlBuilder) build_checkbox(n &YNode) &Widget {
	mut c := checkbox(yn_str(n, 'text'))
	c.checked = yn_bool(n, 'checked', false)
	c.visible = yn_bool(n, 'visible', true)
	c.enabled = yn_bool(n, 'enabled', true)
	c.focus_group = yn_int(n, 'focus_group')
	bs := yn_f32(n, 'box_size')
	if bs > 0 {
		c.box_size = bs
	}
	g := yn_f32(n, 'gap')
	if g > 0 {
		c.gap = g
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_bool_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			c.on_change = h
		}
	}
	b.reg(n, voidptr(c))
	return c
}

fn (mut b YamlBuilder) build_radio_button(n &YNode) &Widget {
	mut rb := radio_button(yn_str(n, 'text'))
	rb.selected = yn_bool(n, 'selected', false)
	rb.visible = yn_bool(n, 'visible', true)
	rb.enabled = yn_bool(n, 'enabled', true)
	rb.focus_group = yn_int(n, 'focus_group')
	rg := yn_str(n, 'radio_group')
	if rg.len > 0 {
		rb.radio_group = rg
	}
	cs := yn_f32(n, 'circle_size')
	if cs > 0 {
		rb.circle_size = cs
	}
	g := yn_f32(n, 'gap')
	if g > 0 {
		rb.gap = g
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_bool_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			rb.on_change = h
		}
	}
	b.reg(n, voidptr(rb))
	return rb
}

fn (mut b YamlBuilder) build_toggle_switch(n &YNode) &Widget {
	mut ts := toggle_switch(yn_str(n, 'text'))
	ts.on = yn_bool(n, 'on', false)
	ts.visible = yn_bool(n, 'visible', true)
	ts.enabled = yn_bool(n, 'enabled', true)
	ts.focus_group = yn_int(n, 'focus_group')
	tw := yn_f32(n, 'track_w')
	if tw > 0 {
		ts.track_w = tw
	}
	th := yn_f32(n, 'track_h')
	if th > 0 {
		ts.track_h = th
	}
	g := yn_f32(n, 'gap')
	if g > 0 {
		ts.gap = g
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_bool_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			ts.on_change = h
		}
	}
	b.reg(n, voidptr(ts))
	return ts
}

fn (mut b YamlBuilder) build_combo_box(n &YNode) &Widget {
	mut c := combo_box()
	ph := yn_str(n, 'placeholder')
	if ph.len > 0 {
		c.placeholder = ph
	}
	c.visible = yn_bool(n, 'visible', true)
	c.enabled = yn_bool(n, 'enabled', true)
	c.focus_group = yn_int(n, 'focus_group')
	ih := yn_f32(n, 'item_height')
	if ih > 0 {
		c.item_height = ih
	}
	mv := yn_int(n, 'max_visible')
	if mv > 0 {
		c.max_visible = mv
	}
	items := yn_items(n, 'items')
	if items.len > 0 {
		c.add_items(items)
	}
	sel := yn_int(n, 'selected')
	if sel >= 0 && sel < c.items.len {
		c.selected = sel
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_idx_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			c.on_change = h
		}
	}
	b.reg(n, voidptr(c))
	return c
}

fn (mut b YamlBuilder) build_list_box(n &YNode) &Widget {
	mut lb := list_box()
	lb.visible = yn_bool(n, 'visible', true)
	lb.enabled = yn_bool(n, 'enabled', true)
	lb.focus_group = yn_int(n, 'focus_group')
	ih := yn_f32(n, 'item_height')
	if ih > 0 {
		lb.item_height = ih
	}
	ss := yn_f32(n, 'scroll_speed')
	if ss > 0 {
		lb.scroll_speed = ss
	}
	items := yn_items(n, 'items')
	if items.len > 0 {
		lb.add_items(items)
	}
	os_name := yn_str(n, 'on_select')
	if os_name.len > 0 {
		h := b.cb.select_handlers[os_name] or { unsafe { nil } }
		if h != unsafe { nil } {
			lb.on_select = h
		}
	}
	od := yn_str(n, 'on_dbl_click')
	if od.len > 0 {
		h := b.cb.dbl_click_handlers[od] or { unsafe { nil } }
		if h != unsafe { nil } {
			lb.on_dbl_click = h
		}
	}
	b.reg(n, voidptr(lb))
	return lb
}

// build_vbox/build_hbox: ключи spacing, padding, bg, cross_align и `children:`.
// Контейнер регистрируется ДО построения детей (id родителя не зависит от
// детей); параметры раскладки каждого ребёнка (flex/min/max/align) передаются
// в v.add(...) через vui_child_params.
fn (mut b YamlBuilder) build_vbox(n &YNode) &Widget {
	mut v := create_vbox_fill()
	s := yn_f32(n, 'spacing')
	if s > 0 {
		v.set_spacing(s)
	}
	pad := yn_f32(n, 'padding')
	if pad > 0 {
		v.set_padding(pad)
	}
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		v.set_bg(vui_parse_color(bg))
	}
	ca := vui_parse_cross_align(yn_str(n, 'cross_align'))
	if ca != .inherit {
		v.set_cross_align(ca)
	}
	b.reg(n, voidptr(v))
	children := b.build_children(n)
	for child in children {
		v.add(child.widget, vui_child_params(child))
	}
	return v
}

fn (mut b YamlBuilder) build_hbox(n &YNode) &Widget {
	mut h := create_hbox_fill()
	s := yn_f32(n, 'spacing')
	if s > 0 {
		h.set_spacing(s)
	}
	pad := yn_f32(n, 'padding')
	if pad > 0 {
		h.set_padding(pad)
	}
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		h.set_bg(vui_parse_color(bg))
	}
	ca := vui_parse_cross_align(yn_str(n, 'cross_align'))
	if ca != .inherit {
		h.set_cross_align(ca)
	}
	b.reg(n, voidptr(h))
	children := b.build_children(n)
	for child in children {
		h.add(child.widget, vui_child_params(child))
	}
	return h
}

// build_panel: ключи bg, border, radius, pad, visible и ребёнок (см. ниже).
fn (mut b YamlBuilder) build_panel(n &YNode) &Widget {
	mut pan := panel()
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		pan.bg = vui_parse_color(bg)
	}
	bd := yn_str(n, 'border')
	if bd.len > 0 {
		pan.border = vui_parse_color(bd)
	}
	rad := yn_f32(n, 'radius')
	if rad > 0 {
		pan.radius = rad
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		pan.pad = pad
	}
	pan.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(pan))
	// Panel держит ровно одного ребёнка: либо ключ `child:`, либо первый
	// элемент `children:` (остальные игнорируются).
	child_node := n.get('child')
	if child_node.is_map() {
		ch := b.build_widget(&child_node)
		pan.set_child(ch.widget)
	} else {
		children := b.build_children(n)
		if children.len > 0 {
			pan.set_child(children[0].widget)
		}
	}
	return pan
}

// build_scroll_box/build_stack: дети из `children:` добавляются без параметров
// раскладки (flex/min/max/align у них игнорируются).
fn (mut b YamlBuilder) build_scroll_box(n &YNode) &Widget {
	mut sb := scroll_box(yn_f32(n, 'content_h'))
	ss := yn_f32(n, 'scroll_speed')
	if ss > 0 {
		sb.scroll_speed = ss
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		sb.pad = pad
	}
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		sb.bg = vui_parse_color(bg)
	}
	sb.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(sb))
	children := b.build_children(n)
	for child in children {
		sb.add(child.widget)
	}
	return sb
}

fn (mut b YamlBuilder) build_stack(n &YNode) &Widget {
	mut st := stack()
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		st.bg = vui_parse_color(bg)
	}
	st.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(st))
	children := b.build_children(n)
	for child in children {
		st.add(child.widget)
	}
	return st
}

// build_tab_box: положение (`pos`, либо `dir: vertical` = слева),
// режим строки вкладок (`layout`), направление текста и список `tabs:`
// (title, icon, child). Вкладка без `child:` получает Spacer. Вариант
// добавления зависит от того, заданы ли title и icon.
fn (mut b YamlBuilder) build_tab_box(n &YNode) &Widget {
	mut tb := tab_box()
	if yn_str(n, 'dir') == 'vertical' {
		tb.pos = .left
	}
	match yn_str(n, 'pos') {
		'top' { tb.pos = .top }
		'bottom' { tb.pos = .bottom }
		'left' { tb.pos = .left }
		'right' { tb.pos = .right }
		else {}
	}

	match yn_str(n, 'layout') {
		'single_line', 'single' { tb.layout = .single_line }
		'multi_row', 'multi', 'wrap' { tb.layout = .multi_row }
		else {}
	}

	if yn_str(n, 'text_dir') == 'vertical' {
		tb.text_dir = .vertical
	}
	th := yn_f32(n, 'tab_height')
	if th > 0 {
		tb.tab_height = th
	}
	tp := yn_f32(n, 'tab_pad')
	if tp > 0 {
		tb.tab_pad = tp
	}
	icon_sz := yn_f32(n, 'icon_size')
	if icon_sz > 0 {
		tb.icon_size = icon_sz
	}
	ig := yn_f32(n, 'icon_gap')
	if ig > 0 {
		tb.icon_gap = ig
	}
	g := yn_f32(n, 'gap')
	if g > 0 {
		tb.gap = g
	}
	ind_t := yn_f32(n, 'indicator_thickness')
	if ind_t > 0 {
		tb.indicator_thickness = ind_t
	}
	ind_p := yn_f32(n, 'indicator_pad')
	if ind_p > 0 {
		tb.indicator_pad = ind_p
	}
	match yn_str(n, 'indicator_pos') {
		'top' { tb.indicator_pos = .top }
		'bottom' { tb.indicator_pos = .bottom }
		'left' { tb.indicator_pos = .left }
		'right' { tb.indicator_pos = .right }
		else {}
	}

	tb.visible = yn_bool(n, 'visible', true)
	tb.enabled = yn_bool(n, 'enabled', true)
	tb.focus_group = yn_int(n, 'focus_group')
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_idx_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			tb.on_change = h
		}
	}
	b.reg(n, voidptr(tb))

	// Parse tabs list
	tabs_node := n.get('tabs')
	if tabs_node.is_list() {
		for tab_n in tabs_node.list {
			title := yn_str(&tab_n, 'title')
			icon_path := yn_str(&tab_n, 'icon')

			// Child widget for this tab
			mut child_w := &Widget(create_spacer())
			child_node := tab_n.get('child')
			if child_node.is_map() {
				ch := b.build_widget(&child_node)
				child_w = ch.widget
			}

			if icon_path.len > 0 && title.len > 0 {
				tb.add_tab_with_icon(title, icon_path, child_w)
			} else if icon_path.len > 0 {
				tb.add_icon_tab(icon_path, child_w)
			} else {
				tb.add_tab(title, child_w)
			}
		}
	}

	return tb
}

// build_menu_items читает `items:` меню или подменю. Вид пункта задаёт `kind`:
// separator (допустимо и `type: separator`), checkbox, submenu; всё остальное -
// обычное действие (action). Подменю строится рекурсивно. Пункты - не Widget,
// но id регистрируется так же (в tree.widgets), чтобы получить get_menu_item(id).
fn (mut b YamlBuilder) build_menu_items(n &YNode) []&MenuItem {
	items_node := n.get('items')
	if !items_node.is_list() {
		return []
	}
	mut result := []&MenuItem{cap: items_node.list.len}
	for item_n in items_node.list {
		kind_str := yn_str(&item_n, 'kind')
		if kind_str == 'separator' || yn_str(&item_n, 'type') == 'separator' {
			result << menu_separator()
			continue
		}
		text := yn_str(&item_n, 'text')
		icon_path_str := yn_str(&item_n, 'icon')
		shortcut := yn_str(&item_n, 'shortcut')
		enabled := yn_bool(&item_n, 'enabled', true)

		if kind_str == 'checkbox' {
			mut mi := menu_checkbox(text, yn_bool(&item_n, 'checked', false))
			mi.icon_path = icon_path_str
			mi.shortcut = shortcut
			mi.enabled = enabled
			oc := yn_str(&item_n, 'on_toggle')
			if oc.len > 0 {
				h := b.cb.change_bool_handlers[oc] or { unsafe { nil } }
				if h != unsafe { nil } {
					mi.on_toggle = h
				}
			}
			// checkbox can also have on_click
			oc2 := yn_str(&item_n, 'on_click')
			if oc2.len > 0 {
				h2 := b.cb.click_handlers[oc2] or { unsafe { nil } }
				if h2 != unsafe { nil } {
					mi.on_click = h2
				}
			}
			id := yn_str(&item_n, 'id')
			if id.len > 0 {
				b.tree.widgets[id] = voidptr(mi)
			}
			result << mi
			continue
		}

		if kind_str == 'submenu' {
			mut mi := menu_submenu(text)
			mi.icon_path = icon_path_str
			mi.enabled = enabled
			// Recursively parse children
			children := b.build_menu_items(&item_n)
			for ch in children {
				mi.add(ch)
			}
			id := yn_str(&item_n, 'id')
			if id.len > 0 {
				b.tree.widgets[id] = voidptr(mi)
			}
			result << mi
			continue
		}

		// Default: action
		mut mi := if icon_path_str.len > 0 {
			menu_action_icon(text, icon_path_str)
		} else {
			menu_action(text)
		}
		mi.shortcut = shortcut
		mi.enabled = enabled
		oc := yn_str(&item_n, 'on_click')
		if oc.len > 0 {
			h := b.cb.click_handlers[oc] or { unsafe { nil } }
			if h != unsafe { nil } {
				mi.on_click = h
			}
		}
		id := yn_str(&item_n, 'id')
		if id.len > 0 {
			b.tree.widgets[id] = voidptr(mi)
		}
		result << mi
	}
	return result
}

// build_menu_bar: список `menus:` с title и `items:` каждого меню.
fn (mut b YamlBuilder) build_menu_bar(n &YNode) &Widget {
	mut mb := menu_bar()
	mb.visible = yn_bool(n, 'visible', true)
	mb.enabled = yn_bool(n, 'enabled', true)
	bh := yn_f32(n, 'bar_height')
	if bh > 0 {
		mb.bar_height = bh
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		mb.pad = pad
	}
	b.reg(n, voidptr(mb))

	// Parse menus list
	menus_node := n.get('menus')
	if menus_node.is_list() {
		for menu_n in menus_node.list {
			title := yn_str(&menu_n, 'title')
			items := b.build_menu_items(&menu_n)
			mb.add_menu(title, items)
		}
	}

	return mb
}

// build_splitter: направление `dir`, доля `ratio` (зажимается в 0..1; 0 -
// остаётся значение по умолчанию), минимумы панелей, полоса и два ребёнка
// под ключами `first:` и `second:` (не `children:`).
fn (mut b YamlBuilder) build_splitter(n &YNode) &Widget {
	mut sp := splitter(if yn_str(n, 'dir') == 'vertical' {
		SplitDir.vertical
	} else {
		SplitDir.horizontal
	})
	r := yn_f32(n, 'ratio')
	if r > 0 {
		sp.ratio = clamp_f32(r, 0.0, 1.0)
	}
	mf := yn_f32(n, 'min_first')
	if mf > 0 {
		sp.min_first = mf
	}
	ms := yn_f32(n, 'min_second')
	if ms > 0 {
		sp.min_second = ms
	}
	bs := yn_f32(n, 'bar_size')
	if bs > 0 {
		sp.bar_size = bs
	}
	bc := yn_str(n, 'bar_color')
	if bc.len > 0 {
		sp.bar_color = vui_parse_color(bc)
	}
	sp.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(sp))

	// First child
	first_node := n.get('first')
	if first_node.is_map() {
		ch := b.build_widget(&first_node)
		sp.set_first(ch.widget)
	}

	// Second child
	second_node := n.get('second')
	if second_node.is_map() {
		ch := b.build_widget(&second_node)
		sp.set_second(ch.widget)
	}

	return sp
}

fn (mut b YamlBuilder) build_separator(n &YNode) &Widget {
	mut s := separator()
	d := yn_str(n, 'dir')
	if d == 'horizontal' {
		s.dir = .horizontal
	} else if d == 'vertical' {
		s.dir = .vertical
	}
	t := yn_f32(n, 'thickness')
	if t > 0 {
		s.thickness = t
	}
	m := yn_f32(n, 'margin')
	if m > 0 {
		s.margin = m
	}
	c := yn_str(n, 'color')
	if c.len > 0 {
		s.color = vui_parse_color(c)
	}
	s.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(s))
	return s
}

// build_tree_view: настройки вида и пунктирные линии связей, корни из `roots:`.
fn (mut b YamlBuilder) build_tree_view(n &YNode) &Widget {
	mut tv := tree_view()
	tv.visible = yn_bool(n, 'visible', true)
	tv.enabled = yn_bool(n, 'enabled', true)
	tv.focus_group = yn_int(n, 'focus_group')
	ih := yn_f32(n, 'item_height')
	if ih > 0 {
		tv.item_height = ih
	}
	ind := yn_f32(n, 'indent')
	if ind > 0 {
		tv.indent = ind
	}
	is_ := yn_f32(n, 'icon_size')
	if is_ > 0 {
		tv.icon_size = is_
	}
	ig := yn_f32(n, 'icon_gap')
	if ig > 0 {
		tv.icon_gap = ig
	}
	ss := yn_f32(n, 'scroll_speed')
	if ss > 0 {
		tv.scroll_speed = ss
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		tv.pad = pad
	}
	tv.show_lines = yn_bool(n, 'show_lines', false)
	lc := yn_str(n, 'line_color')
	if lc.len > 0 {
		tv.line_color = vui_parse_color(lc)
	}
	ld := yn_f32(n, 'line_dash')
	if ld > 0 {
		tv.line_dash = ld
	}
	lgp := yn_f32(n, 'line_gap_px')
	if lgp > 0 {
		tv.line_gap_px = lgp
	}
	tv.line_solid = yn_bool(n, 'line_solid', false)
	b.reg(n, voidptr(tv))
	// Parse roots
	roots_node := n.get('roots')
	if roots_node.is_list() {
		for rn in roots_node.list {
			node := b.build_tree_node(&rn)
			if unsafe { node != nil } {
				tv.add_root(node)
			}
		}
	}
	return tv
}

// build_tree_node строит узел дерева (text, icon, expanded - по умолчанию true,
// цвета) и рекурсивно его `children:`. Как и пункты меню, узел - не Widget.
fn (mut b YamlBuilder) build_tree_node(n &YNode) &TreeNode {
	text := yn_str(n, 'text')
	icon_path := yn_str(n, 'icon')
	expanded := yn_bool(n, 'expanded', true)
	mut node := if icon_path.len > 0 { tree_node_icon(text, icon_path) } else { tree_node(text) }
	node.expanded = expanded
	tc := yn_str(n, 'text_color')
	if tc.len > 0 {
		node.text_color = vui_parse_color(tc)
	}
	bgc := yn_str(n, 'bg_color')
	if bgc.len > 0 {
		node.bg_color = vui_parse_color(bgc)
	}
	id := yn_str(n, 'id')
	if id.len > 0 {
		b.tree.widgets[id] = voidptr(node)
	}
	children_node := n.get('children')
	if children_node.is_list() {
		for cn in children_node.list {
			child := b.build_tree_node(&cn)
			if unsafe { child != nil } {
				node.add(child)
			}
		}
	}
	return node
}

// build_spinner: `style` - dots | dual (иначе arc), `spinning` по умолчанию true.
fn (mut b YamlBuilder) build_spinner(n &YNode) &Widget {
	mut sp := spinner()
	sp.visible = yn_bool(n, 'visible', true)
	sp.spinning = yn_bool(n, 'spinning', true)
	match yn_str(n, 'style') {
		'dots' { sp.style = .dots }
		'dual' { sp.style = .dual }
		else {} // .arc is default
	}

	c := yn_str(n, 'color')
	if c.len > 0 {
		sp.color = vui_parse_color(c)
	}
	bgc := yn_str(n, 'bg_color')
	if bgc.len > 0 {
		sp.bg_color = vui_parse_color(bgc)
	}
	sz := yn_f32(n, 'size')
	if sz > 0 {
		sp.size = sz
	}
	t := yn_f32(n, 'thickness')
	if t > 0 {
		sp.thickness = t
	}
	spd := yn_f32(n, 'speed')
	if spd > 0 {
		sp.speed = spd
	}
	sp.text = yn_str(n, 'text')
	tg := yn_f32(n, 'text_gap')
	if tg > 0 {
		sp.text_gap = tg
	}
	dc := yn_int(n, 'dot_count')
	if dc > 0 {
		sp.dot_count = dc
	}
	ds := yn_f32(n, 'dot_size')
	if ds > 0 {
		sp.dot_size = ds
	}
	b.reg(n, voidptr(sp))
	return sp
}

// build_tooltip: подсказка с текстом, задержкой появления `delay_ms` и переносом.
fn (mut b YamlBuilder) build_tooltip(n &YNode) &Widget {
	mut t := tooltip(yn_str(n, 'text'))
	d := yn_int(n, 'delay_ms')
	if d > 0 {
		t.delay_ms = u32(d)
	}
	t.wrap = yn_bool(n, 'wrap', true)
	mw := yn_f32(n, 'max_width')
	if mw > 0 {
		t.max_width = mw
	}
	c := yn_str(n, 'color')
	if c.len > 0 {
		t.text_color = vui_parse_color(c)
	}
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		t.bg = vui_parse_color(bg)
	}
	t.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(t))
	return t
}

fn (mut b YamlBuilder) build_code_editor(n &YNode) &Widget {
	mut ce := code_editor()
	ce.visible = yn_bool(n, 'visible', true)
	ce.enabled = yn_bool(n, 'enabled', true)
	ce.readonly = yn_bool(n, 'readonly', false)
	ce.show_line_numbers = yn_bool(n, 'show_line_numbers', true)
	ce.highlight_cur_line = yn_bool(n, 'highlight_cur_line', true)
	ce.focus_group = yn_int(n, 'focus_group')
	// `item_height` читается, но не применяется: ветка пуста (зарезервировано).
	ih := yn_f32(n, 'item_height')
	if ih > 0 {
		// unused but reserved
	}
	ts := yn_int(n, 'tab_size')
	if ts > 0 {
		ce.tab_size = ts
	}
	ss := yn_f32(n, 'scroll_speed')
	if ss > 0 {
		ce.scroll_speed = ss
	}
	fs := yn_str(n, 'font_style')
	if fs.len > 0 {
		ce.font_style = vui_parse_font_style(fs)
	}
	fsize := yn_int(n, 'font_size')
	if fsize > 0 {
		ce.font_size = fsize
	}
	text := yn_str(n, 'text')
	if text.len > 0 {
		ce.set_text(text)
	}
	file := yn_str(n, 'file')
	if file.len > 0 {
		ce.load_file(file)
	}
	bg := yn_str(n, 'bg')
	if bg.len > 0 {
		ce.bg_color = vui_parse_color(bg)
	}
	tc := yn_str(n, 'text_color')
	if tc.len > 0 {
		ce.text_color = vui_parse_color(tc)
	}
	// Подсветка синтаксиса: ключ `language` выбирает готовый подсветчик;
	// неизвестный язык - без подсветки.
	lang := yn_str(n, 'language')
	match lang {
		'v', 'vlang' { ce.set_highlighter(v_highlighter()) }
		'c', 'cpp', 'c++' { ce.set_highlighter(c_highlighter()) }
		'python', 'py' { ce.set_highlighter(python_highlighter()) }
		else {}
	}

	b.reg(n, voidptr(ce))
	return ce
}

// build_slider: `value` зажимается в [min, max] сразу при чтении, поэтому min и
// max читаются раньше него; max <= 0 в YAML оставляет max по умолчанию.
fn (mut b YamlBuilder) build_slider(n &YNode) &Widget {
	mut s := slider()
	if yn_str(n, 'dir') == 'vertical' {
		s.dir = .vertical
	}
	s.min = yn_f32(n, 'min')
	mx := yn_f32(n, 'max')
	if mx > 0 {
		s.max = mx
	}
	s.value = clamp_f32(yn_f32(n, 'value'), s.min, s.max)
	s.step = yn_f32(n, 'step')
	bs := yn_f32(n, 'big_step')
	if bs > 0 {
		s.big_step = bs
	}
	s.visible = yn_bool(n, 'visible', true)
	s.enabled = yn_bool(n, 'enabled', true)
	s.focus_group = yn_int(n, 'focus_group')
	s.show_value = yn_bool(n, 'show_value', false)
	vf := yn_str(n, 'value_format')
	if vf.len > 0 {
		s.value_format = vf
	}
	tt := yn_f32(n, 'track_thickness')
	if tt > 0 {
		s.track_thickness = tt
	}
	tsz := yn_f32(n, 'thumb_size')
	if tsz > 0 {
		s.thumb_size = tsz
	}
	tc := yn_str(n, 'track_color')
	if tc.len > 0 {
		s.track_color = vui_parse_color(tc)
	}
	fc := yn_str(n, 'fill_color')
	if fc.len > 0 {
		s.fill_color = vui_parse_color(fc)
	}
	thc := yn_str(n, 'thumb_color')
	if thc.len > 0 {
		s.thumb_color = vui_parse_color(thc)
	}
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_f32_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			s.on_change = h
		}
	}
	b.reg(n, voidptr(s))
	return s
}

// build_progress_bar: `value` зажимается в [0, 1]; `style: circular` - круговой.
// `radius` и `corner_radius` - разные поля (corner_radius применяется и при нуле).
fn (mut b YamlBuilder) build_progress_bar(n &YNode) &Widget {
	mut p := progress_bar()
	if yn_str(n, 'style') == 'circular' {
		p.style = .circular
	}
	p.value = clamp_f32(yn_f32(n, 'value'), 0, 1)
	p.indeterminate = yn_bool(n, 'indeterminate', false)
	p.show_text = yn_bool(n, 'show_text', false)
	tf := yn_str(n, 'text_format')
	if tf.len > 0 {
		p.text_format = tf
	}
	p.text = yn_str(n, 'text')
	th := yn_f32(n, 'thickness')
	if th > 0 {
		p.thickness = th
	}
	rad := yn_f32(n, 'radius')
	if n.has('corner_radius') {
		p.corner_radius = yn_f32(n, 'corner_radius')
	}
	if rad > 0 {
		p.radius = rad
	}
	sp := yn_f32(n, 'anim_speed')
	if sp > 0 {
		p.anim_speed = sp
	}
	bg := yn_str(n, 'bg_color')
	if bg.len > 0 {
		p.bg_color = vui_parse_color(bg)
	}
	fc := yn_str(n, 'fill_color')
	if fc.len > 0 {
		p.fill_color = vui_parse_color(fc)
	}
	tc := yn_str(n, 'text_color')
	if tc.len > 0 {
		p.text_color = vui_parse_color(tc)
	}
	p.visible = yn_bool(n, 'visible', true)
	b.reg(n, voidptr(p))
	return p
}

// build_image_view: `mode` - fit | fill | stretch | native | zoom, иначе
// режим по умолчанию; `zoom`/`zoom_speed` имеют смысл для режима zoom.
fn (mut b YamlBuilder) build_image_view(n &YNode) &Widget {
	mut iv := image_view()
	iv.path = yn_str(n, 'path')
	match yn_str(n, 'mode') {
		'fit' { iv.mode = .fit }
		'fill' { iv.mode = .fill }
		'stretch' { iv.mode = .stretch }
		'native' { iv.mode = .native }
		'zoom' { iv.mode = .zoom }
		else {}
	}

	z := yn_f32(n, 'zoom')
	if z > 0 {
		iv.zoom = z
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		iv.pad = pad
	}
	ss := yn_f32(n, 'scroll_speed')
	if ss > 0 {
		iv.scroll_speed = ss
	}
	zs := yn_f32(n, 'zoom_speed')
	if zs > 0 {
		iv.zoom_speed = zs
	}
	bg := yn_str(n, 'bg_color')
	if bg.len > 0 {
		iv.bg_color = vui_parse_color(bg)
	}
	bc := yn_str(n, 'border_color')
	if bc.len > 0 {
		iv.border_color = vui_parse_color(bc)
	}
	iv.visible = yn_bool(n, 'visible', true)
	iv.enabled = yn_bool(n, 'enabled', true)
	b.reg(n, voidptr(iv))
	return iv
}

// build_accordion: оформление заголовков и секции. Секция без `child:` получает Spacer.
fn (mut b YamlBuilder) build_accordion(n &YNode) &Widget {
	mut acc := accordion()
	match yn_str(n, 'mode') {
		'single' { acc.mode = .single }
		'multiple', 'multi' { acc.mode = .multiple }
		else {}
	}

	hh := yn_f32(n, 'header_height')
	if hh > 0 {
		acc.header_height = hh
	}
	hp := yn_f32(n, 'header_pad')
	if hp > 0 {
		acc.header_pad = hp
	}
	sp := yn_f32(n, 'spacing')
	if sp > 0 {
		acc.spacing = sp
	}
	pad := yn_f32(n, 'pad')
	if pad > 0 {
		acc.pad = pad
	}
	is_ := yn_f32(n, 'icon_size')
	if is_ > 0 {
		acc.icon_size = is_
	}
	fs := yn_str(n, 'font_style')
	if fs.len > 0 {
		acc.font_style = vui_parse_font_style(fs)
	}
	fsize := yn_int(n, 'font_size')
	if fsize > 0 {
		acc.font_size = fsize
	}
	hbg := yn_str(n, 'header_bg')
	if hbg.len > 0 {
		acc.header_bg = vui_parse_color(hbg)
	}
	hhbg := yn_str(n, 'header_hover_bg')
	if hhbg.len > 0 {
		acc.header_hover_bg = vui_parse_color(hhbg)
	}
	htc := yn_str(n, 'header_text')
	if htc.len > 0 {
		acc.header_text = vui_parse_color(htc)
	}
	cbg := yn_str(n, 'content_bg')
	if cbg.len > 0 {
		acc.content_bg = vui_parse_color(cbg)
	}
	bc := yn_str(n, 'border_color')
	if bc.len > 0 {
		acc.border_color = vui_parse_color(bc)
	}
	acc.visible = yn_bool(n, 'visible', true)
	acc.enabled = yn_bool(n, 'enabled', true)
	oc := yn_str(n, 'on_change')
	if oc.len > 0 {
		h := b.cb.change_idx_handlers[oc] or { unsafe { nil } }
		if h != unsafe { nil } {
			// Wrap fn(int, string) → fn(int, bool) by section index
			// For accordion we use change_bool_handlers pattern instead
			// (на деле ветка пуста: `on_change` аккордеона из YAML НЕ
			// привязывается - обработчик находится, но нигде не сохраняется)
		}
	}
	b.reg(n, voidptr(acc))

	// Секции `sections:` (title, expanded, child). Секция собирается напрямую
	// литералом AccordionSection; анимация раскрытия сразу ставится в
	// конечное значение (1.0 / 0.0) через .at(), т.е. без анимации при старте.
	sections_node := n.get('sections')
	if sections_node.is_list() {
		for sec_n in sections_node.list {
			title := yn_str(&sec_n, 'title')
			expanded := yn_bool(&sec_n, 'expanded', false)
			mut child_w := &Widget(create_spacer())
			child_node := sec_n.get('child')
			if child_node.is_map() {
				ch := b.build_widget(&child_node)
				child_w = ch.widget
			}
			acc.sections << AccordionSection{
				title:    title
				expanded: expanded
				anim:     Anim{
					epsilon: 0.02
				}.at(if expanded { f32(1.0) } else { f32(0.0) })
				widget:   child_w
			}
		}
	}

	return acc
}

// ─── Public API ────────────────────────────────────────

// load_ui_from_string строит дерево виджетов из YAML-текста.
// cb - реестр обработчиков, заполненный заранее (см. UiCallbacks); он должен
// пережить вызов, но дереву после построения не нужен: обработчики уже
// скопированы в поля виджетов.
// Ошибка возвращается только если корень документа не map. Корневой узел сам
// является виджетом (`type: vbox` и т.д.), а не обёрткой над ним.
// Пример YAML:
//   type: vbox
//   children:
//     - type: button
//       text: "OK"
//       on_click: ok
//   hotkeys:
//     - shortcut: "Ctrl+S"
//       on_press: save
pub fn load_ui_from_string(yaml_str string, cb &UiCallbacks) !UiTree {
	root := yaml_parse(yaml_str)
	if !root.is_map() {
		return error('YAML UI: root must be a mapping')
	}

	mut builder := YamlBuilder{
		cb:   unsafe { cb }
		tree: UiTree{}
	}

	ch := builder.build_widget(&root)
	builder.tree.root = ch.widget
	builder.tree.flex = ch.flex

	// ── Секция hotkeys ──
	// Лежит в корневом map рядом с `type`/`children` и сама виджетом не является.
	// Пара без shortcut, без on_press или с незарегистрированным именем
	// обработчика пропускается молча.
	hotkeys_node := root.get('hotkeys')
	if hotkeys_node.is_list() {
		for hk_n in hotkeys_node.list {
			shortcut := yn_str(&hk_n, 'shortcut')
			handler_name := yn_str(&hk_n, 'on_press')
			if shortcut.len > 0 && handler_name.len > 0 {
				h := cb.hotkey_handlers[handler_name] or { unsafe { nil } }
				if h != unsafe { nil } {
					builder.tree.hotkeys << HotkeyBinding{
						shortcut: shortcut
						handler:  h
					}
				}
			}
		}
	}

	return builder.tree
}

// load_ui_from_file читает файл целиком и строит дерево как load_ui_from_string.
// Ошибка чтения файла возвращается как error с путём и причиной.
pub fn load_ui_from_file(path string, cb &UiCallbacks) !UiTree {
	content := os.read_file(path) or { return error('Cannot read file: ${path}: ${err}') }
	return load_ui_from_string(content, cb)
}

// ─── Convenience: add UiTree root to Window ────────────

// Корень добавляется в окно через Window.add_widget (окно его не копирует и не
// освобождает). Если корень nil (дерево не строилось), вызов ничего не делает.
pub fn (mut w Window) add_ui_tree(tree &UiTree) {
	if unsafe { tree.root != nil } {
		w.add_widget(tree.root)
	}
}

// ─── Convenience: add UiTree root to Dialog ────────────

// То же для Dialog.
pub fn (mut d Dialog) add_ui_tree(tree &UiTree) {
	if unsafe { tree.root != nil } {
		d.add_widget(tree.root)
	}
}

// ─── Convenience: add UiTree as child to VBox ──────────

// Корень добавляется ребёнком VBox с flex из корня YAML (без flex - размер из measure()).
pub fn (mut v VBox) add_ui_tree(tree &UiTree) {
	if unsafe { tree.root != nil } {
		v.add(tree.root, flex: tree.flex)
	}
}

// ─── Convenience: add UiTree as child to HBox ──────────

// Корень добавляется ребёнком HBox с flex из корня YAML.
pub fn (mut h HBox) add_ui_tree(tree &UiTree) {
	if unsafe { tree.root != nil } {
		h.add(tree.root, flex: tree.flex)
	}
}

// ─── Apply hotkeys from UiTree to Window ───────────────

// Привязывает горячие клавиши окна (действуют, пока окно в фокусе).
// Вызывать после того, как окно создано; дерево на это не влияет.
pub fn (mut w Window) apply_hotkeys(tree &UiTree) {
	for hk in tree.hotkeys {
		w.bind_hotkey(hk.shortcut, hk.handler)
	}
}

// ─── Apply hotkeys from UiTree to App (global) ────────

// Привязывает глобальные горячие клавиши приложения (для всех окон).
pub fn (mut a App) apply_hotkeys(tree &UiTree) {
	for hk in tree.hotkeys {
		a.bind_hotkey(hk.shortcut, hk.handler)
	}
}
