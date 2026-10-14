module vgui

import os

// ═══════════════════════════════════════════════════════
// css — таблицы стилей в синтаксисе CSS: разбор файла
// ═══════════════════════════════════════════════════════
//
// Здесь только разбор текста в Stylesheet и его проверка. Что значит каждое
// свойство (в какие поля Theme оно пишет) - css_props.v; как стили попадают
// на экран (подмена темы на время отрисовки поддерева) - css_apply.v.
// Подробно о модели - PROJECT.md, «Стили CSS».
//
//   :root        { --brand: #3b82f6; accent-color: var(--brand); border-radius: 8; }
//   button       { background: #eee; }
//   button:hover { background: #ddd; }
//   .danger      { background: #c33; color: #fff; }
//   #save        { accent-color: #2a2; }
//   .sidebar list:selected { background: var(--brand); }
//   menu         { background: #222; }
//
// Главная идея: CSS не вводит новый способ рисовать. Каждое свойство сводится к
// полям Theme (button:hover background -> button_hover), а правило, сработавшее на
// виджете, рисует его поддерево с изменённой копией темы. Поэтому:
//   - состояния (:hover, :pressed, :selected, :checked, :focus, :disabled) - не
//     проверка состояния во время отрисовки, а выбор другого поля темы; виджет
//     сам решает, когда каким цветом рисоваться (как и без CSS);
//   - «наследование» как в CSS получается само: тема действует на всё поддерево;
//   - раскладку стили не меняют (отступов, размеров, шрифтов в CSS нет) - measure()
//     от таблицы стилей не зависит, и смена стилей не требует новой раскладки.
//
// Селекторы: тип элемента (имена как в .vui: button, list, vbox...), `*`, `#id`,
// `.класс`, их сочетание (`button.danger#save`), потомок (пробел) и прямой
// ребёнок (`>`), список через запятую. Состояние - одно, только у последнего
// звена (`.bar button:hover`). Особые правила - «корневые»: `:root` и голые
// `menu`, `tooltip`, `notification`, `dropdown` (список ComboBox) меняют общую тему окна, потому что попапы и
// уведомления рисуются вне дерева виджетов (css_apply.v, css_base_theme).
//
// Значения: цвет (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba(), несколько имён),
// число (`8` или `8px`), var(--имя). Переменные объявляются только в `:root` и
// подставляются при разборе (одна область на весь файл, не каскадом по дереву).
// `--имя-поля-темы: значение` в любом правиле - прямой доступ к полю Theme
// (`--lb-row-alt-bg` -> lb_row_alt_bg) для того, у чего нет CSS-имени.
//
// Ошибки громкие, с местом, как в .vui: `style.css:12: свойство colr неизвестно
// для button`. Опечатка не должна молча превращаться в «стиль не сработал».

// Stylesheet — разобранная и проверенная таблица стилей. Неизменяема после
// разбора: окна держат на неё указатель и читают из разных кадров. Смена стилей -
// это новый Stylesheet (App.set_stylesheet / Window.set_stylesheet).
@[heap]
pub struct Stylesheet {
pub:
	name string // имя источника для сообщений (путь файла или имя, данное parse_stylesheet)
mut:
	// rules — правила для виджетов (селектор сопоставляется с деревом при отрисовке).
	rules []CssRule
	// root_rules — :root, menu, tooltip, notification: применяются к общей теме окна.
	root_rules []CssRule
	// vars — переменные из :root (без «--»), уже подставленные в значения.
	vars map[string]string
}

// CssRel — как звено селектора связано со звеном левее (ближе к корню дерева).
enum CssRel {
	descendant // `a b` - b где угодно внутри a
	child      // `a > b` - a прямой родитель b
}

// CssCompound — одно звено селектора: `button.danger#save`.
// kind == 0 - тип не задан (`*` или только классы/id).
struct CssCompound {
	kind    int
	id      string
	classes []string
mut:
	// rel — связь с ЛЕВЫМ соседом (предком); у самого левого звена не используется.
	rel CssRel
}

// CssSelector — звенья справа налево: parts[0] - сам виджет (субъект), дальше -
// его предки. pseudo - состояние субъекта ('' - без состояния).
struct CssSelector {
	parts  []CssCompound
	pseudo string
	text   string // исходный текст - для сообщений об ошибках
	// root_type — для корневого правила: 'root', 'menu', 'tooltip', 'notification'; иначе ''.
	root_type string
}

// CssValue — значение свойства, уже разобранное: цвет или число.
struct CssValue {
	is_color bool
	color    Color
	num      f32
	raw      string // текст значения после подстановки var() - для сообщений
}

// CssDecl — одно объявление `свойство: значение`.
struct CssDecl {
	prop  string
	value CssValue
	line  int
mut:
	// fields_by_kind[kind] — поля Theme, в которые объявление пишет на виджете
	// этого вида; посчитано один раз при разборе (css_compile_decl), чтобы
	// отрисовка не искала свойства в таблице на каждом кадре. Пусто - к этому
	// виду свойство неприменимо (виджет его молча не получает, как в CSS).
	fields_by_kind [][]string
	// root_fields — поля для корневого правила.
	root_fields []string
}

// CssRule — селектор (один - список через запятую разворачивается в несколько
// правил с общими объявлениями) и объявления.
struct CssRule {
	selector    CssSelector
	specificity int // id*10000 + (классы и состояние)*100 + типы
	order       int // номер в файле: при равной специфичности побеждает поздний
mut:
	decls []CssDecl
}

// load_stylesheet читает и разбирает CSS-файл. Ошибка - с именем файла и строкой.
pub fn load_stylesheet(path string) !&Stylesheet {
	text := os.read_file(path) or { return error('${path}: не удалось прочитать файл: ${err}') }
	return parse_stylesheet(text, path)
}

// parse_stylesheet разбирает CSS из строки. name - имя для сообщений об ошибках.
pub fn parse_stylesheet(text string, name string) !&Stylesheet {
	mut p := CssParser{
		src:  css_strip_comments(text)
		name: name
	}
	return p.parse()
}

// ─── Разбор ────────────────────────────────────────────

// CssParser — разбор «вручную» за один проход: сначала текст селектора до `{`,
// потом объявления до `}`. Комментарии /* */ уже заменены пробелами (с
// сохранением переводов строк), поэтому номера строк считаются по исходному тексту.
struct CssParser {
	src  string
	name string
mut:
	pos   int
	order int
}

// css_strip_comments заменяет /* ... */ пробелами, оставляя \n на месте -
// чтобы позиция в тексте давала прежний номер строки.
fn css_strip_comments(s string) string {
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if i + 1 < s.len && s[i] == `/` && s[i + 1] == `*` {
			out << ` `
			out << ` `
			i += 2
			for i < s.len && !(i + 1 < s.len && s[i] == `*` && s[i + 1] == `/`) {
				out << if s[i] == `\n` { `\n` } else { ` ` }
				i++
			}
			if i < s.len {
				out << ` `
				out << ` `
				i += 2
			}
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

// line_at — номер строки (с 1) для позиции в тексте.
fn (p &CssParser) line_at(pos int) int {
	mut line := 1
	for i := 0; i < pos && i < p.src.len; i++ {
		if p.src[i] == `\n` {
			line++
		}
	}
	return line
}

fn (p &CssParser) fail(pos int, msg string) IError {
	return error('${p.name}:${p.line_at(pos)}: ${msg}')
}

// parse — весь файл: последовательность блоков `селекторы { объявления }`.
// :root разбирается первым проходом, чтобы var() работал в правилах выше
// объявления переменной (в CSS порядок тоже не важен).
fn (mut p CssParser) parse() !&Stylesheet {
	blocks := p.split_blocks()!
	mut ss := &Stylesheet{
		name: p.name
	}
	// 1-й проход: переменные из :root
	for blk in blocks {
		if blk.selectors.trim_space() != ':root' {
			continue
		}
		// и свои переменные, и поля темы (--accent): var(--accent) тоже работает
		for d in p.split_decls(blk)! {
			if d.prop.starts_with('--') {
				ss.vars[d.prop[2..]] = d.value
			}
		}
	}
	// 2-й проход: правила
	for blk in blocks {
		raw_decls := p.split_decls(blk)!
		for sel_text in blk.selectors.split(',') {
			sel := p.parse_selector(sel_text.trim_space(), blk.sel_pos)!
			mut rule := CssRule{
				selector:    sel
				specificity: css_specificity(sel)
				order:       p.order
			}
			p.order++
			for rd in raw_decls {
				// пользовательская переменная в :root - уже учтена в vars
				if sel.root_type == 'root' && rd.prop.starts_with('--')
					&& !css_is_theme_field_prop(rd.prop) {
					continue
				}
				if rd.prop.starts_with('--') && !css_is_theme_field_prop(rd.prop) {
					return p.fail(rd.pos, '${rd.prop}: такого поля темы нет; свои переменные объявляйте в :root')
				}
				value_text := p.substitute_vars(ss, rd.value, rd.pos)!
				value := css_parse_value(value_text) or {
					return p.fail(rd.pos, '${rd.prop}: ${err.msg()}')
				}
				decl := css_compile_decl(sel, rd.prop, value, p.line_at(rd.pos)) or {
					return p.fail(rd.pos, err.msg())
				}
				rule.decls << decl
			}
			if sel.root_type.len > 0 {
				ss.root_rules << rule
			} else {
				ss.rules << rule
			}
		}
	}
	// порядок каскада - один раз здесь, а не на каждом кадре (css_apply.v)
	css_sort_rules(mut ss.rules)
	return ss
}

// CssBlock — сырой блок: текст селекторов и текст между { }.
struct CssBlock {
	selectors string
	body      string
	sel_pos   int // позиция начала селектора - для номеров строк
	body_pos  int
}

// CssRawDecl — объявление до разбора значения.
struct CssRawDecl {
	prop  string
	value string
	pos   int
}

fn (mut p CssParser) split_blocks() ![]CssBlock {
	mut blocks := []CssBlock{}
	mut i := 0
	s := p.src
	for {
		for i < s.len && s[i].is_space() {
			i++
		}
		if i >= s.len {
			break
		}
		start := i
		if s[i] == `@` {
			return p.fail(i, '@-правила (@media, @import...) не поддерживаются')
		}
		for i < s.len && s[i] != `{` && s[i] != `}` {
			i++
		}
		if i >= s.len || s[i] == `}` {
			return p.fail(start, 'ожидается { после селектора')
		}
		selectors := s[start..i].trim_space()
		if selectors.len == 0 {
			return p.fail(start, 'пустой селектор перед {')
		}
		i++
		body_start := i
		for i < s.len && s[i] != `}` {
			if s[i] == `{` {
				return p.fail(i, 'вложенные блоки { } не поддерживаются - не хватает } выше?')
			}
			i++
		}
		if i >= s.len {
			return p.fail(start, 'блок не закрыт: не хватает }')
		}
		blocks << CssBlock{
			selectors: selectors
			body:      s[body_start..i]
			sel_pos:   start
			body_pos:  body_start
		}
		i++
	}
	return blocks
}

// split_decls — `a: 1; b: 2` -> объявления. Пустые части (лишние `;`) допустимы.
fn (p &CssParser) split_decls(blk CssBlock) ![]CssRawDecl {
	mut out := []CssRawDecl{}
	mut seen := map[string]bool{}
	mut part_start := 0
	body := blk.body
	for i := 0; i <= body.len; i++ {
		if i < body.len && body[i] != `;` {
			continue
		}
		part := body[part_start..i]
		pos := blk.body_pos + part_start + (part.len - part.trim_left(' \t\r\n').len)
		part_start = i + 1
		t := part.trim_space()
		if t.len == 0 {
			continue
		}
		colon := t.index(':') or { return p.fail(pos, '${t}: ожидается «свойство: значение»') }
		prop := t[..colon].trim_space().to_lower()
		value := t[colon + 1..].trim_space()
		if prop.len == 0 {
			return p.fail(pos, 'свойство без имени перед «:»')
		}
		if value.len == 0 {
			return p.fail(pos, '${prop}: пустое значение')
		}
		if value.ends_with('!important') {
			return p.fail(pos, '${prop}: !important не поддерживается - порядок решает специфичность')
		}
		if prop in seen {
			return p.fail(pos, '${prop}: свойство указано в блоке дважды')
		}
		seen[prop] = true
		out << CssRawDecl{
			prop:  prop
			value: value
			pos:   pos
		}
	}
	return out
}

// substitute_vars заменяет var(--имя) значением переменной из :root.
// Вложенных var() в значениях переменных нет: они подставляются текстом.
fn (p &CssParser) substitute_vars(ss &Stylesheet, value string, pos int) !string {
	mut s := value
	for _ in 0 .. 16 {
		start := s.index('var(') or { return s }
		end := s.index_after(')', start) or { return p.fail(pos, '${value}: не закрыта скобка var(') }
		inner := s[start + 4..end].trim_space()
		if !inner.starts_with('--') {
			return p.fail(pos, '${value}: в var() нужно имя вида --имя')
		}
		name := inner[2..]
		v := ss.vars[name] or { return p.fail(pos, 'переменная --${name} не объявлена в :root') }
		s = s[..start] + v + s[end + 1..]
	}
	return p.fail(pos, '${value}: слишком глубокая подстановка var()')
}

// ─── Селекторы ─────────────────────────────────────────

// css_root_types — селекторы, меняющие общую тему окна (css_apply.v, css_base_theme).
const css_root_types = ['menu', 'tooltip', 'notification', 'dropdown']

// parse_selector — один селектор из списка через запятую.
fn (p &CssParser) parse_selector(text string, pos int) !CssSelector {
	if text.len == 0 {
		return p.fail(pos, 'пустой селектор в списке через запятую')
	}
	if text == ':root' {
		return CssSelector{
			text:      text
			root_type: 'root'
		}
	}
	// разбиение на звенья: пробелы - потомок, `>` - ребёнок
	mut words := []string{}
	mut rels := []CssRel{} // rels[i] - связь words[i] с words[i-1]
	mut cur := []u8{}
	mut pending := CssRel.descendant
	for ch in text.bytes() {
		if ch == ` ` || ch == `\t` || ch == `\n` || ch == `\r` || ch == `>` {
			if cur.len > 0 {
				words << cur.bytestr()
				rels << pending
				cur.clear()
				pending = .descendant
			}
			if ch == `>` {
				if words.len == 0 {
					return p.fail(pos, '${text}: «>» без левой части')
				}
				pending = .child
			}
			continue
		}
		cur << ch
	}
	if cur.len > 0 {
		words << cur.bytestr()
		rels << pending
	} else if pending == .child {
		return p.fail(pos, '${text}: «>» без правой части')
	}
	// звенья справа налево; состояние - только у последнего (субъекта)
	mut parts := []CssCompound{}
	mut pseudo := ''
	for i := words.len - 1; i >= 0; i-- {
		comp, ps := p.parse_compound(words[i], text, pos)!
		if ps.len > 0 {
			if i != words.len - 1 {
				return p.fail(pos, '${text}: состояние :${ps} допустимо только у последнего звена селектора')
			}
			pseudo = ps
		}
		mut c := comp
		// связь звена с левым соседом хранится у него самого
		c.rel = if i > 0 { rels[i] } else { CssRel.descendant }
		parts << c
	}
	if pseudo.len > 0 && pseudo !in css_pseudo_classes {
		return p.fail(pos, '${text}: состояние :${pseudo} неизвестно; допустимо :${css_pseudo_classes.join(', :')}')
	}
	// голые menu/tooltip/notification/dropdown - корневые правила
	if words.len == 1 && words[0].all_before(':') in css_root_types {
		root := words[0].all_before(':')
		return CssSelector{
			text:      text
			pseudo:    pseudo
			root_type: root
		}
	}
	for w in words {
		base := w.all_before(':').all_before('.').all_before('#')
		if base in css_root_types {
			return p.fail(pos, '${text}: ${base} - попап, он рисуется вне дерева окна; пишите просто «${base} { ... }» без классов и предков')
		}
	}
	return CssSelector{
		parts:  parts
		pseudo: pseudo
		text:   text
	}
}

// parse_compound — `button.a.b#id:hover` -> звено и состояние.
fn (p &CssParser) parse_compound(word string, full string, pos int) !(CssCompound, string) {
	mut i := 0
	// тип: до первого из . # :
	for i < word.len && word[i] != `.` && word[i] != `#` && word[i] != `:` {
		i++
	}
	typ := word[..i].to_lower()
	mut kind := 0
	if typ.len > 0 && typ != '*' {
		if typ in css_root_types {
			// проверит вызывающий (корневой селектор или ошибка с подсказкой)
			kind = 0
		} else {
			kind = css_kind_by_name[typ] or {
				return p.fail(pos, '${full}: неизвестный тип элемента ${typ}')
			}
		}
	}
	mut id := ''
	mut classes := []string{}
	mut pseudo := ''
	for i < word.len {
		sigil := word[i]
		i++
		start := i
		for i < word.len && css_is_ident_char(word[i]) {
			i++
		}
		name := word[start..i]
		if name.len == 0 {
			return p.fail(pos, '${full}: пустое имя после «${sigil.ascii_str()}»')
		}
		match sigil {
			`.` {
				classes << name
			}
			`#` {
				if id.len > 0 {
					return p.fail(pos, '${full}: два #id в одном звене')
				}
				id = name
			}
			`:` {
				if pseudo.len > 0 {
					return p.fail(pos, '${full}: два состояния в одном звене')
				}
				// :active - синоним :pressed, как привычнее по CSS
				pseudo = if name == 'active' { 'pressed' } else { name }
			}
			else {
				return p.fail(pos, '${full}: неожиданный символ «${sigil.ascii_str()}»')
			}
		}
	}
	return CssCompound{
		kind:    kind
		id:      id
		classes: classes
	}, pseudo
}

fn css_is_ident_char(c u8) bool {
	return c.is_letter() || c.is_digit() || c == `-` || c == `_`
}

// css_specificity — как в CSS: id важнее классов и состояний, те важнее типов.
fn css_specificity(sel CssSelector) int {
	mut ids := 0
	mut classes := if sel.pseudo.len > 0 { 1 } else { 0 }
	mut types := 0
	for c in sel.parts {
		if c.id.len > 0 {
			ids++
		}
		classes += c.classes.len
		if c.kind != 0 {
			types++
		}
	}
	return ids * 10000 + classes * 100 + types
}

// ─── Значения ──────────────────────────────────────────

// css_named_colors — небольшой набор имён; для остального - #hex.
const css_named_colors = {
	'black':  Color{0, 0, 0, 255}
	'white':  Color{255, 255, 255, 255}
	'red':    Color{255, 0, 0, 255}
	'green':  Color{0, 128, 0, 255}
	'blue':   Color{0, 0, 255, 255}
	'yellow': Color{255, 255, 0, 255}
	'orange': Color{255, 165, 0, 255}
	'purple': Color{128, 0, 128, 255}
	'gray':   Color{128, 128, 128, 255}
	'grey':   Color{128, 128, 128, 255}
	'silver': Color{192, 192, 192, 255}
}

// css_parse_value — цвет или число. Ошибка - текст без места (место добавит парсер).
fn css_parse_value(text string) !CssValue {
	t := text.trim_space().to_lower()
	if t == 'transparent' {
		return error('transparent: прозрачный цвет (альфа 0) тема читает как «не задано» - задайте цвет с альфой > 0')
	}
	if c := css_named_colors[t] {
		return CssValue{
			is_color: true
			color:    c
			raw:      text
		}
	}
	if t.starts_with('#') {
		c := css_parse_hex(t) or { return error('${text}: ожидается цвет #rgb, #rgba, #rrggbb или #rrggbbaa') }
		return css_color_value(c, text)!
	}
	if t.starts_with('rgb(') || t.starts_with('rgba(') {
		c := css_parse_rgb(t) or { return error('${text}: ожидается rgb(r, g, b) или rgba(r, g, b, a)') }
		return css_color_value(c, text)!
	}
	num_text := if t.ends_with('px') { t[..t.len - 2] } else { t }
	if num_text.len > 0 && (num_text[0].is_digit() || num_text[0] == `.` || num_text[0] == `-`) {
		n := num_text.f64()
		if n == 0 && num_text.trim('0.-').len > 0 {
			return error('${text}: не число')
		}
		return CssValue{
			num: f32(n)
			raw: text
		}
	}
	return error('${text}: ожидается цвет (#rrggbb, rgb(), имя) или число')
}

fn css_color_value(c Color, raw string) !CssValue {
	if c.a == 0 {
		return error('${raw}: прозрачный цвет (альфа 0) тема читает как «не задано» - задайте цвет с альфой > 0')
	}
	return CssValue{
		is_color: true
		color:    c
		raw:      raw
	}
}

// css_parse_hex — #rgb, #rgba (каждая цифра удваивается), #rrggbb, #rrggbbaa.
fn css_parse_hex(t string) ?Color {
	h := t[1..]
	for c in h {
		if !c.is_hex_digit() {
			return none
		}
	}
	if h.len == 3 || h.len == 4 {
		mut long := '#'
		for c in h {
			long += c.ascii_str().repeat(2)
		}
		return cp_parse_hex(long)
	}
	if h.len == 6 || h.len == 8 {
		return cp_parse_hex(t)
	}
	return none
}

// css_parse_rgb — rgb(r, g, b) и rgba(r, g, b, a); a - доля 0..1, как в CSS.
fn css_parse_rgb(t string) ?Color {
	open := t.index('(') or { return none }
	if !t.ends_with(')') {
		return none
	}
	parts := t[open + 1..t.len - 1].split(',').map(it.trim_space())
	if parts.len != 3 && parts.len != 4 {
		return none
	}
	mut ch := []u8{}
	for i in 0 .. 3 {
		if parts[i].len == 0 || !parts[i].bytes().all(it.is_digit()) {
			return none
		}
		v := parts[i].int()
		if v > 255 {
			return none
		}
		ch << u8(v)
	}
	mut a := u8(255)
	if parts.len == 4 {
		af := parts[3].f64()
		if af < 0 || af > 1 || (af == 0 && parts[3].trim('0.').len > 0) {
			return none
		}
		a = u8(af * 255 + 0.5)
	}
	return Color{ch[0], ch[1], ch[2], a}
}
