module vgui

// ═══════════════════════════════════════════════════════
// SyntaxHighlighter — token-based syntax coloring
// ═══════════════════════════════════════════════════════

pub struct SyntaxToken {
pub:
	text  string
	color Color
}

pub interface SyntaxHighlighter {
	tokenize(line string) []SyntaxToken
}

// ═══════════════════════════════════════════════════════
// Generic keyword-based highlighter
// ═══════════════════════════════════════════════════════

pub struct KeywordHighlighter {
pub mut:
	keywords      []string
	types         []string
	builtins      []string
	keyword_color Color  = Color{198, 120, 221, 255} // purple
	type_color    Color  = Color{230, 192, 123, 255} // yellow
	builtin_color Color  = Color{97, 175, 239, 255}  // blue
	string_color  Color  = Color{152, 195, 121, 255} // green
	comment_color Color  = Color{92, 99, 112, 255}   // gray
	number_color  Color  = Color{209, 154, 102, 255} // orange
	default_color Color  = Color{220, 220, 220, 255} // light gray
	line_comment  string = '//'
	block_start   string = '/*'
	block_end     string = '*/'
}

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
		string_color: Color{152, 195, 121, 255}
	}
}

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

pub fn (h &KeywordHighlighter) tokenize(line string) []SyntaxToken {
	mut tokens := []SyntaxToken{cap: 16}
	bytes := line.bytes()
	n := bytes.len
	mut i := 0

	for i < n {
		// Line comment
		if h.line_comment.len > 0 && i + h.line_comment.len <= n {
			if line[i..i + h.line_comment.len] == h.line_comment {
				tokens << SyntaxToken{
					text:  line[i..]
					color: h.comment_color
				}
				return tokens
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
			if word in h.keywords {
				color = h.keyword_color
			} else if word in h.types {
				color = h.type_color
			} else if word in h.builtins {
				color = h.builtin_color
			}

			tokens << SyntaxToken{
				text:  word
				color: color
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

	return tokens
}
