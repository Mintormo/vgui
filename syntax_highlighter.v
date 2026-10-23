module vgui

// ═══════════════════════════════════════════════════════
// SyntaxHighlighter — token-based syntax coloring
// ═══════════════════════════════════════════════════════

// Файл syntax_highlighter.v: подсветка синтаксиса для CodeEditor и подобных виджетов. Подсветка
// построчная и без состояния: интерфейс SyntaxHighlighter превращает одну строку текста в список
// цветных кусков (SyntaxToken), которые конкатенируются обратно в исходную строку без потерь
// (пробелы и знаки тоже входят в токены). Единственная готовая реализация - KeywordHighlighter
// (ключевые слова/типы/встроенные функции + строки, числа, однострочные комментарии), для
// V, C и Python есть готовые фабрики. Свою подсветку можно подключить, реализовав интерфейс.
//
// Цвета и тема. Токен несёт вид (SyntaxKind) и, по желанию, свой цвет. Без своего цвета
// (альфа 0) виджет берёт цвет вида из палитры, подобранной под его фон
// (syntax_palette_for: на тёмном фоне - тёмная палитра, на светлом - светлая), а обычный
// текст рисует цветом текста темы. Поэтому подсветка следует за темой и её сменой на
// ходу. KeywordHighlighter по умолчанию своих цветов не задаёт; заданный *_color
// перекрывает палитру (как раньше).

// SyntaxKind - вид куска строки: по нему выбирается цвет из палитры.
pub enum SyntaxKind {
	plain // обычный текст, пробелы, знаки
	keyword
	type_name
	builtin
	string_lit
	comment
	number
}

// Кусок строки text. color - свой цвет куска; альфа 0 - «не задан», тогда цвет вида kind
// из палитры (resolve_color).
pub struct SyntaxToken {
pub:
	text  string
	color Color = Color{0, 0, 0, 0} // у Color альфа по умолчанию 255 - «не задан» явно
	kind  SyntaxKind
}

// resolve_color - цвет, которым рисовать токен: свой, если задан, иначе из палитры.
pub fn (t SyntaxToken) resolve_color(p &SyntaxPalette) Color {
	return if t.color.a > 0 { t.color } else { p.color_of(t.kind) }
}

// SyntaxPalette - цвета видов токенов (SyntaxKind) для одного фона.
pub struct SyntaxPalette {
pub mut:
	plain      Color
	keyword    Color
	type_name  Color
	builtin    Color
	string_lit Color
	comment    Color
	number     Color
}

// color_of - цвет вида kind.
pub fn (p &SyntaxPalette) color_of(kind SyntaxKind) Color {
	return match kind {
		.plain { p.plain }
		.keyword { p.keyword }
		.type_name { p.type_name }
		.builtin { p.builtin }
		.string_lit { p.string_lit }
		.comment { p.comment }
		.number { p.number }
	}
}

// syntax_palette_dark - палитра для тёмного фона (в духе One Dark; прежние цвета
// KeywordHighlighter по умолчанию).
pub fn syntax_palette_dark() SyntaxPalette {
	return SyntaxPalette{
		plain:      Color{220, 220, 220, 255} // light gray
		keyword:    Color{198, 120, 221, 255} // purple
		type_name:  Color{230, 192, 123, 255} // yellow
		builtin:    Color{97, 175, 239, 255}  // blue
		string_lit: Color{152, 195, 121, 255} // green
		comment:    Color{92, 99, 112, 255}   // gray
		number:     Color{209, 154, 102, 255} // orange
	}
}

// syntax_palette_light - палитра для светлого фона (в духе One Light): те же оттенки,
// но темнее, чтобы читались на белом.
pub fn syntax_palette_light() SyntaxPalette {
	return SyntaxPalette{
		plain:      Color{56, 58, 66, 255}
		keyword:    Color{166, 38, 164, 255}
		type_name:  Color{193, 132, 1, 255}
		builtin:    Color{64, 120, 242, 255}
		string_lit: Color{80, 161, 79, 255}
		comment:    Color{160, 161, 167, 255}
		number:     Color{152, 104, 1, 255}
	}
}

// syntax_palette_for - палитра под фон bg: светлый фон (относительная яркость по
// Rec. 709 больше половины) - светлая палитра, иначе тёмная. Фон, а не имя темы:
// так верный выбор получают и свои темы, и виджет с собственным bg_color.
pub fn syntax_palette_for(bg Color) SyntaxPalette {
	luma := 0.2126 * f32(bg.r) + 0.7152 * f32(bg.g) + 0.0722 * f32(bg.b)
	return if luma > 127.5 { syntax_palette_light() } else { syntax_palette_dark() }
}

// Разбор одной строки (без перевода строки) на токены. Реализация обязана вернуть токены, тексты
// которых в сумме дают ровно исходную строку (так делает KeywordHighlighter).
pub interface SyntaxHighlighter {
	tokenize(line string) []SyntaxToken
}

// ═══════════════════════════════════════════════════════
// Generic keyword-based highlighter
// ═══════════════════════════════════════════════════════

// Универсальный подсветчик по спискам слов. keywords/types/builtins - списки слов трёх
// категорий (всё остальное - обычный текст, default_color). *_color - свои цвета видов;
// по умолчанию не заданы (альфа 0), и цвет берётся из палитры под фон виджета
// (SyntaxPalette, см. шапку файла). line_comment - начало однострочного комментария (пустая
// строка - нет комментариев). block_start/block_end - границы блочного комментария (пустые -
// блочных нет). Блочный комментарий тянется через строки, поэтому учитывает его
// tokenize_state (состояние «внутри комментария» на входе и выходе строки); CodeEditor
// протягивает это состояние по строкам сам. Интерфейсный tokenize(line) считает, что строка
// начинается вне комментария.
pub struct KeywordHighlighter {
pub mut:
	keywords      []string
	types         []string
	builtins      []string
	keyword_color Color  = Color{0, 0, 0, 0}
	type_color    Color  = Color{0, 0, 0, 0}
	builtin_color Color  = Color{0, 0, 0, 0}
	string_color  Color  = Color{0, 0, 0, 0}
	comment_color Color  = Color{0, 0, 0, 0}
	number_color  Color  = Color{0, 0, 0, 0}
	default_color Color  = Color{0, 0, 0, 0}
	line_comment  string = '//'
	block_start   string = '/*'
	block_end     string = '*/'
}

// Готовые наборы для V, C и Python: слова, типы, встроенные функции и символ комментария.
// У C директивы препроцессора (#include...) заданы как "слова": '#' считается символом слова
// (см. kh_is_word_char), поэтому директива разбирается как единый идентификатор.
pub fn v_highlighter() &KeywordHighlighter {
	return &KeywordHighlighter{
		keywords:     ['fn', 'pub', 'mut', 'struct', 'enum', 'interface', 'module', 'import', 'return',
			'if', 'else', 'for', 'in', 'match', 'or', 'and', 'not', 'true', 'false', 'none', 'unsafe',
			'defer', 'go', 'spawn', 'const', 'type', 'union', 'asm', 'volatile', 'break', 'continue',
			'assert', 'lock', 'rlock', 'shared', 'select', 'as', 'is', 'isreftype', 'sizeof', 'typeof',
			'dump']
		types:        ['int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32', 'f64',
			'bool', 'string', 'rune', 'voidptr', 'byteptr', 'charptr', 'any']
		builtins:     ['println', 'print', 'eprintln', 'eprint', 'panic', 'exit', 'error']
		line_comment: '//'
	}
}

pub fn c_highlighter() &KeywordHighlighter {
	return &KeywordHighlighter{
		keywords:     ['auto', 'break', 'case', 'const', 'continue', 'default', 'do', 'else', 'enum',
			'extern', 'for', 'goto', 'if', 'inline', 'register', 'return', 'sizeof', 'static',
			'struct', 'switch', 'typedef', 'union', 'volatile', 'while', '#include', '#define',
			'#ifdef', '#ifndef', '#endif', '#pragma']
		types:        ['int', 'char', 'float', 'double', 'void', 'long', 'short', 'unsigned', 'signed',
			'size_t', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t', 'int8_t', 'int16_t', 'int32_t',
			'int64_t', 'bool', 'NULL']
		builtins:     ['printf', 'scanf', 'malloc', 'free', 'memcpy', 'memset', 'strlen', 'strcmp',
			'strcpy', 'fprintf', 'fopen', 'fclose']
		line_comment: '//'
	}
}

pub fn python_highlighter() &KeywordHighlighter {
	return &KeywordHighlighter{
		keywords:     ['def', 'class', 'import', 'from', 'return', 'if', 'elif', 'else', 'for',
			'while', 'break', 'continue', 'pass', 'try', 'except', 'finally', 'raise', 'with',
			'as', 'yield', 'lambda', 'and', 'or', 'not', 'in', 'is', 'True', 'False', 'None', 'global',
			'nonlocal', 'del', 'assert', 'async', 'await']
		types:        ['int', 'float', 'str', 'bool', 'list', 'dict', 'tuple', 'set', 'bytes',
			'object', 'type']
		builtins:     ['print', 'len', 'range', 'input', 'open', 'enumerate', 'zip', 'map', 'filter',
			'sorted', 'reversed', 'isinstance', 'hasattr', 'getattr', 'setattr', 'super', 'property']
		line_comment: '#'
		// В Python блочных комментариев нет (а '/*' - не начало комментария).
		block_start:  ''
		block_end:    ''
	}
}

// Символ идентификатора: латиница, цифры, '_', '#' и любой байт >= 0x80 (то есть не-ASCII
// символы UTF-8 считаются частью слова, чтобы не разрезать кириллицу в идентификаторах).
fn kh_is_word_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `#` || ch >= 0x80
}

fn kh_is_digit(ch u8) bool {
	return ch >= `0` && ch <= `9`
}

// Length of a UTF-8 sequence starting with byte `ch`. Returns 1 for invalid bytes
// so the tokenizer always advances and never slices a codepoint in half.
fn kh_utf8_seq_len(ch u8) int {
	if ch < 0x80 {
		return 1
	}
	if ch & 0xE0 == 0xC0 {
		return 2
	}
	if ch & 0xF0 == 0xE0 {
		return 3
	}
	if ch & 0xF8 == 0xF0 {
		return 4
	}
	return 1
}

// Однопроходный разбор строки слева направо. На каждом шаге проверяются по порядку: (1) начало
// однострочного комментария - остаток строки целиком становится токеном-комментарием и разбор
// завершается; (2) строковый литерал в ', " или ` - до закрывающей кавычки с пропуском
// экранированных символов (\x); незакрытая строка раскрашивается до конца строки; (3) число:
// десятичное с точкой, экспонентой и разделителем '_', либо шестнадцатеричное 0x...; (4) слово -
// классифицируется как keyword/type/builtin или обычное; (5) всё остальное (пробелы, знаки)
// - один символ UTF-8 цветом по умолчанию.
pub fn (h &KeywordHighlighter) tokenize(line string) []SyntaxToken {
	tokens, _ := h.tokenize_state(line, false)
	return tokens
}

// tokenize_state - tokenize с учётом блочного комментария: in_block - строка начинается
// внутри него. Возвращает токены и признак «строка закончилась внутри комментария»
// (передаётся следующей строке).
pub fn (h &KeywordHighlighter) tokenize_state(line string, in_block bool) ([]SyntaxToken, bool) {
	mut tokens := []SyntaxToken{cap: 16}
	bytes := line.bytes()
	n := bytes.len
	mut i := 0
	has_block := h.block_start.len > 0 && h.block_end.len > 0

	// Продолжение блочного комментария с прошлой строки.
	if in_block && has_block {
		end := line.index(h.block_end) or {
			if n > 0 {
				tokens << SyntaxToken{
					text:  line
					color: h.comment_color
					kind:  .comment
				}
			}
			return tokens, true
		}
		i = end + h.block_end.len
		tokens << SyntaxToken{
			text:  line[..i]
			color: h.comment_color
			kind:  .comment
		}
	}

	for i < n {
		// Block comment: до block_end на этой строке или до конца строки (тогда
		// комментарий продолжается на следующей).
		if has_block && i + h.block_start.len <= n
			&& line[i..i + h.block_start.len] == h.block_start {
			rest := line[i + h.block_start.len..]
			if pos := rest.index(h.block_end) {
				j := i + h.block_start.len + pos + h.block_end.len
				tokens << SyntaxToken{
					text:  line[i..j]
					color: h.comment_color
					kind:  .comment
				}
				i = j
				continue
			}
			tokens << SyntaxToken{
				text:  line[i..]
				color: h.comment_color
				kind:  .comment
			}
			return tokens, true
		}
		// Line comment
		if h.line_comment.len > 0 && i + h.line_comment.len <= n {
			if line[i..i + h.line_comment.len] == h.line_comment {
				tokens << SyntaxToken{
					text:  line[i..]
					color: h.comment_color
					kind:  .comment
				}
				return tokens, false
			}
		}

		ch := bytes[i]

		// String literals
		if ch == `'` || ch == `"` || ch == `\`` {
			quote := ch
			mut j := i + 1
			for j < n {
				if bytes[j] == `\\` && j + 1 < n {
					j += 2 // skip escaped char
					continue
				}
				if bytes[j] == quote {
					j += 1
					break
				}
				j += 1
			}
			tokens << SyntaxToken{
				text:  line[i..j]
				color: h.string_color
				kind:  .string_lit
			}
			i = j
			continue
		}

		// Numbers
		if kh_is_digit(ch) || (ch == `.` && i + 1 < n && kh_is_digit(bytes[i + 1])) {
			mut j := i
			mut has_dot := false
			mut has_x := false
			if ch == `0` && j + 1 < n && (bytes[j + 1] == `x` || bytes[j + 1] == `X`) {
				has_x = true
				j += 2
				for j < n && (kh_is_digit(bytes[j]) || (bytes[j] >= `a` && bytes[j] <= `f`)
					|| (bytes[j] >= `A` && bytes[j] <= `F`) || bytes[j] == `_`) {
					j++
				}
			} else {
				for j < n {
					b := bytes[j]
					if kh_is_digit(b) || b == `_` {
						j++
					} else if b == `.` && !has_dot && !has_x {
						has_dot = true
						j++
					} else if (b == `e` || b == `E`) && !has_x {
						j++
						if j < n && (bytes[j] == `+` || bytes[j] == `-`) {
							j++
						}
					} else {
						break
					}
				}
			}
			tokens << SyntaxToken{
				text:  line[i..j]
				color: h.number_color
				kind:  .number
			}
			i = j
			continue
		}

		// Identifier / keyword
		if kh_is_word_char(ch) {
			mut j := i
			for j < n && kh_is_word_char(bytes[j]) {
				j++
			}
			word := line[i..j]

			mut color := h.default_color
			mut kind := SyntaxKind.plain
			if word in h.keywords {
				color = h.keyword_color
				kind = .keyword
			} else if word in h.types {
				color = h.type_color
				kind = .type_name
			} else if word in h.builtins {
				color = h.builtin_color
				kind = .builtin
			}

			tokens << SyntaxToken{
				text:  word
				color: color
				kind:  kind
			}
			i = j
			continue
		}

		// Operator / punctuation / whitespace — advance one UTF-8 codepoint
		seq := kh_utf8_seq_len(ch)
		end := if i + seq <= n { i + seq } else { n }
		tokens << SyntaxToken{
			text:  line[i..end]
			color: h.default_color
		}
		i = end
	}

	return tokens, false
}
