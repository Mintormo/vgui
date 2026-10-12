module vgui

import encoding.utf8
import strings

// ═══════════════════════════════════════════════════════
// Text encoding conversion utilities
//
// Supported encodings:
//   utf-8 (default, passthrough)
//   latin1 / iso-8859-1
//   cp1251 / windows-1251
//   cp1252 / windows-1252
//   koi8-r
//
// V strings are always UTF-8 internally. These functions
// convert between raw file bytes and V strings.
// ═══════════════════════════════════════════════════════

// TextEncoding - поддерживаемые кодировки текстовых файлов (используются редакторами текста при
// открытии/сохранении файлов). Внутри библиотеки текст всегда UTF-8; кодировка нужна только на границе
// «байты файла <-> строка V». Однобайтные кодировки описаны таблицами для байтов 0x80..0xFF ниже.
pub enum TextEncoding {
	utf8
	latin1 // ISO 8859-1
	cp1251 // Windows-1251 (Cyrillic)
	cp1252 // Windows-1252 (Western European)
	koi8r  // KOI8-R (Cyrillic)
}

// Parse encoding name string → enum
// parse_encoding разбирает имя кодировки (регистр, пробелы, '-' и '_' игнорируются: 'Windows-1251',
// 'win_1251' -> .cp1251). Неизвестное имя и пустая строка дают .utf8 (без ошибки).
pub fn parse_encoding(name string) TextEncoding {
	// Дефисы и подчёркивания убраны заранее, поэтому в ветках - только слитные формы.
	n := name.to_lower().trim_space().replace('-', '').replace('_', '')
	return match n {
		'utf8', '' { .utf8 }
		'latin1', 'iso88591' { .latin1 }
		'cp1251', 'windows1251', 'win1251' { .cp1251 }
		'cp1252', 'windows1252', 'win1252' { .cp1252 }
		'koi8r' { .koi8r }
		else { .utf8 }
	}
}

// encoding_name - каноническое имя кодировки (обратное к parse_encoding), например .koi8r -> 'koi8-r'.
pub fn encoding_name(enc TextEncoding) string {
	return match enc {
		.utf8 { 'utf-8' }
		.latin1 { 'latin1' }
		.cp1251 { 'cp1251' }
		.cp1252 { 'cp1252' }
		.koi8r { 'koi8-r' }
	}
}

// ─── Decode: raw bytes → UTF-8 string ──────────────────

// decode_bytes превращает сырые байты файла в UTF-8 строку V. Для .utf8 BOM (EF BB BF) в начале
// срезается, а битые последовательности заменяются на U+FFFD (utf8_sanitize): раньше они
// попадали в строку как есть, и разбор на руны и отрисовка получали невалидный UTF-8. Для однобайтных
// кодировок каждому байту сопоставляется символ по таблице. Пустой ввод даёт ''.
pub fn decode_bytes(data []u8, enc TextEncoding) string {
	if data.len == 0 {
		return ''
	}
	match enc {
		.utf8 { return utf8_sanitize(strip_bom(data.bytestr())) }
		.latin1 { return decode_single_byte(data, latin1_table) }
		.cp1251 { return decode_single_byte(data, cp1251_table) }
		.cp1252 { return decode_single_byte(data, cp1252_table) }
		.koi8r { return decode_single_byte(data, koi8r_table) }
	}
}

// ─── Encode: UTF-8 string → raw bytes ──────────────────

// encode_string - обратное преобразование: UTF-8 строка -> байты кодировки. Символы, которых нет в
// кодировке, заменяются на '?' - преобразование с потерями; когда потеря недопустима (сохранение
// файла), используйте encode_string_strict. BOM не добавляется. Пустой ввод даёт [].
pub fn encode_string(text string, enc TextEncoding) []u8 {
	if text.len == 0 {
		return []
	}
	match enc {
		.utf8 { return text.bytes() }
		.latin1 { return encode_single_byte(text, latin1_reverse) }
		.cp1251 { return encode_single_byte(text, cp1251_reverse) }
		.cp1252 { return encode_single_byte(text, cp1252_reverse) }
		.koi8r { return encode_single_byte(text, koi8r_reverse) }
	}
}

// encode_string_strict - как encode_string, но без потерь: none, если хоть один символ
// непредставим в кодировке (например, кириллица в latin1).
pub fn encode_string_strict(text string, enc TextEncoding) ?[]u8 {
	reverse := match enc {
		.utf8 { return text.bytes() }
		.latin1 { latin1_reverse }
		.cp1251 { cp1251_reverse }
		.cp1252 { cp1252_reverse }
		.koi8r { koi8r_reverse }
	}
	mut result := []u8{cap: text.len}
	for r in text.runes() {
		if r < 0x80 {
			result << u8(r)
		} else {
			result << reverse[r] or { return none }
		}
	}
	return result
}

// utf8_sanitize заменяет каждую битую последовательность UTF-8 на U+FFFD. Корректная строка
// (обычный случай) возвращается как есть после быстрой проверки.
fn utf8_sanitize(s string) string {
	if utf8.validate_str(s) {
		return s
	}
	mut out := strings.new_builder(s.len + 16)
	mut i := 0
	for i < s.len {
		n := utf8_valid_seq_len(s, i)
		if n > 0 {
			out.write_string(s[i..i + n])
			i += n
		} else {
			out.write_string('\uFFFD')
			i++
		}
	}
	return out.str()
}

// utf8_valid_seq_len - длина корректной UTF-8 последовательности, начинающейся в s[i], или 0:
// неверный ведущий байт, обрыв, неверный байт продолжения, избыточная (overlong) запись,
// суррогаты и значения больше U+10FFFF.
fn utf8_valid_seq_len(s string, i int) int {
	b0 := s[i]
	if b0 < 0x80 {
		return 1
	}
	n, min_cp := if b0 & 0xE0 == 0xC0 {
		2, u32(0x80)
	} else if b0 & 0xF0 == 0xE0 {
		3, u32(0x800)
	} else if b0 & 0xF8 == 0xF0 {
		4, u32(0x10000)
	} else {
		0, u32(0)
	}
	if n == 0 || i + n > s.len {
		return 0
	}
	mut cp := u32(b0) & (u32(0x7F) >> n)
	for k in 1 .. n {
		c := s[i + k]
		if c & 0xC0 != 0x80 {
			return 0
		}
		cp = (cp << 6) | u32(c & 0x3F)
	}
	if cp < min_cp || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
		return 0
	}
	return n
}

// ─── BOM handling ──────────────────────────────────────

// strip_bom срезает UTF-8 BOM (EF BB BF) в начале строки, если он есть.
fn strip_bom(s string) string {
	if s.len >= 3 && s[0] == 0xEF && s[1] == 0xBB && s[2] == 0xBF {
		return s[3..]
	}
	return s
}

// ─── Single-byte codec engine ──────────────────────────

// decode_single_byte - декодер однобайтной кодировки. Байты < 0x80 (ASCII) совпадают во всех
// поддерживаемых кодировках и копируются как есть; для остальных берётся table[b - 0x80]. Значение
// 0xFFFD в таблице (байт не определён в кодировке, напр. 0x98 в cp1251) попадает в результат как символ
// подстановки; индекс за пределами таблицы тоже даёт 0xFFFD.
fn decode_single_byte(data []u8, table []rune) string {
	mut result := []rune{cap: data.len}
	for b in data {
		if b < 0x80 {
			result << rune(b)
		} else {
			idx := int(b) - 0x80
			if idx < table.len {
				result << table[idx]
			} else {
				result << rune(0xFFFD) // replacement char
			}
		}
	}
	return result.string()
}

// encode_single_byte - обратный к decode_single_byte: ASCII как есть, остальное через карту reverse, неизвестное -> '?'.
fn encode_single_byte(text string, reverse map[rune]u8) []u8 {
	runes := text.runes()
	mut result := []u8{cap: runes.len}
	for r in runes {
		if r < 0x80 {
			result << u8(r)
		} else {
			b := reverse[r] or { u8(`?`) }
			result << b
		}
	}
	return result
}

// ─── Rune → byte reverse maps (built from tables) ─────

// build_reverse строит обратную карту «символ -> байт» из таблицы декодирования. Позиции с 0xFFFD
// пропускаются (это «дырки», а не настоящий символ). Если символ встречается дважды, побеждает
// последний индекс.
fn build_reverse(table []rune) map[rune]u8 {
	mut m := map[rune]u8{}
	for i, r in table {
		if r != 0xFFFD {
			m[r] = u8(i + 0x80)
		}
	}
	return m
}

// ═══════════════════════════════════════════════════════
// Encoding tables (0x80..0xFF → Unicode codepoint)
// ═══════════════════════════════════════════════════════

// Latin1 / ISO 8859-1: 0x80-0xFF maps directly to U+0080-U+00FF
// Таблицы ниже - константы на всё время работы: *_table (байт 0x80+i -> символ) и *_reverse (символ -> байт), вычисляются при инициализации модуля.
const latin1_table = build_latin1_table()

fn build_latin1_table() []rune {
	mut t := []rune{cap: 128}
	for i in 0 .. 128 {
		t << rune(0x80 + i)
	}
	return t
}

const latin1_reverse = build_reverse(latin1_table)

// Windows-1251 (Cyrillic)
// cp1251_table: 128 символов для байтов 0x80..0xFF, комментарии справа отмечают диапазоны по 8 байт; 0xFFFD - неопределённый байт 0x98.
const cp1251_table = [
	rune(0x0402),
	rune(0x0403),
	rune(0x201A),
	rune(0x0453),
	rune(0x201E),
	rune(0x2026),
	rune(0x2020),
	rune(0x2021), // 80-87
	rune(0x20AC),
	rune(0x2030),
	rune(0x0409),
	rune(0x2039),
	rune(0x040A),
	rune(0x040C),
	rune(0x040B),
	rune(0x040F), // 88-8F
	rune(0x0452),
	rune(0x2018),
	rune(0x2019),
	rune(0x201C),
	rune(0x201D),
	rune(0x2022),
	rune(0x2013),
	rune(0x2014), // 90-97
	rune(0xFFFD),
	rune(0x2122),
	rune(0x0459),
	rune(0x203A),
	rune(0x045A),
	rune(0x045C),
	rune(0x045B),
	rune(0x045F), // 98-9F
	rune(0x00A0),
	rune(0x040E),
	rune(0x045E),
	rune(0x0408),
	rune(0x00A4),
	rune(0x0490),
	rune(0x00A6),
	rune(0x00A7), // A0-A7
	rune(0x0401),
	rune(0x00A9),
	rune(0x0404),
	rune(0x00AB),
	rune(0x00AC),
	rune(0x00AD),
	rune(0x00AE),
	rune(0x0407), // A8-AF
	rune(0x00B0),
	rune(0x00B1),
	rune(0x0406),
	rune(0x0456),
	rune(0x0491),
	rune(0x00B5),
	rune(0x00B6),
	rune(0x00B7), // B0-B7
	rune(0x0451),
	rune(0x2116),
	rune(0x0454),
	rune(0x00BB),
	rune(0x0458),
	rune(0x0405),
	rune(0x0455),
	rune(0x0457), // B8-BF
	rune(0x0410),
	rune(0x0411),
	rune(0x0412),
	rune(0x0413),
	rune(0x0414),
	rune(0x0415),
	rune(0x0416),
	rune(0x0417), // C0-C7
	rune(0x0418),
	rune(0x0419),
	rune(0x041A),
	rune(0x041B),
	rune(0x041C),
	rune(0x041D),
	rune(0x041E),
	rune(0x041F), // C8-CF
	rune(0x0420),
	rune(0x0421),
	rune(0x0422),
	rune(0x0423),
	rune(0x0424),
	rune(0x0425),
	rune(0x0426),
	rune(0x0427), // D0-D7
	rune(0x0428),
	rune(0x0429),
	rune(0x042A),
	rune(0x042B),
	rune(0x042C),
	rune(0x042D),
	rune(0x042E),
	rune(0x042F), // D8-DF
	rune(0x0430),
	rune(0x0431),
	rune(0x0432),
	rune(0x0433),
	rune(0x0434),
	rune(0x0435),
	rune(0x0436),
	rune(0x0437), // E0-E7
	rune(0x0438),
	rune(0x0439),
	rune(0x043A),
	rune(0x043B),
	rune(0x043C),
	rune(0x043D),
	rune(0x043E),
	rune(0x043F), // E8-EF
	rune(0x0440),
	rune(0x0441),
	rune(0x0442),
	rune(0x0443),
	rune(0x0444),
	rune(0x0445),
	rune(0x0446),
	rune(0x0447), // F0-F7
	rune(0x0448),
	rune(0x0449),
	rune(0x044A),
	rune(0x044B),
	rune(0x044C),
	rune(0x044D),
	rune(0x044E),
	rune(0x044F), // F8-FF
]

const cp1251_reverse = build_reverse(cp1251_table)

// Windows-1252 (Western European)
// cp1252_table: 0xFFFD - неопределённые байты 0x81, 0x8D, 0x8F, 0x90, 0x9D. Дальше (0xA0..0xFF) совпадает с Latin-1.
const cp1252_table = [
	rune(0x20AC),
	rune(0xFFFD),
	rune(0x201A),
	rune(0x0192),
	rune(0x201E),
	rune(0x2026),
	rune(0x2020),
	rune(0x2021),
	rune(0x02C6),
	rune(0x2030),
	rune(0x0160),
	rune(0x2039),
	rune(0x0152),
	rune(0xFFFD),
	rune(0x017D),
	rune(0xFFFD),
	rune(0xFFFD),
	rune(0x2018),
	rune(0x2019),
	rune(0x201C),
	rune(0x201D),
	rune(0x2022),
	rune(0x2013),
	rune(0x2014),
	rune(0x02DC),
	rune(0x2122),
	rune(0x0161),
	rune(0x203A),
	rune(0x0153),
	rune(0xFFFD),
	rune(0x017E),
	rune(0x0178),
	rune(0x00A0),
	rune(0x00A1),
	rune(0x00A2),
	rune(0x00A3),
	rune(0x00A4),
	rune(0x00A5),
	rune(0x00A6),
	rune(0x00A7),
	rune(0x00A8),
	rune(0x00A9),
	rune(0x00AA),
	rune(0x00AB),
	rune(0x00AC),
	rune(0x00AD),
	rune(0x00AE),
	rune(0x00AF),
	rune(0x00B0),
	rune(0x00B1),
	rune(0x00B2),
	rune(0x00B3),
	rune(0x00B4),
	rune(0x00B5),
	rune(0x00B6),
	rune(0x00B7),
	rune(0x00B8),
	rune(0x00B9),
	rune(0x00BA),
	rune(0x00BB),
	rune(0x00BC),
	rune(0x00BD),
	rune(0x00BE),
	rune(0x00BF),
	rune(0x00C0),
	rune(0x00C1),
	rune(0x00C2),
	rune(0x00C3),
	rune(0x00C4),
	rune(0x00C5),
	rune(0x00C6),
	rune(0x00C7),
	rune(0x00C8),
	rune(0x00C9),
	rune(0x00CA),
	rune(0x00CB),
	rune(0x00CC),
	rune(0x00CD),
	rune(0x00CE),
	rune(0x00CF),
	rune(0x00D0),
	rune(0x00D1),
	rune(0x00D2),
	rune(0x00D3),
	rune(0x00D4),
	rune(0x00D5),
	rune(0x00D6),
	rune(0x00D7),
	rune(0x00D8),
	rune(0x00D9),
	rune(0x00DA),
	rune(0x00DB),
	rune(0x00DC),
	rune(0x00DD),
	rune(0x00DE),
	rune(0x00DF),
	rune(0x00E0),
	rune(0x00E1),
	rune(0x00E2),
	rune(0x00E3),
	rune(0x00E4),
	rune(0x00E5),
	rune(0x00E6),
	rune(0x00E7),
	rune(0x00E8),
	rune(0x00E9),
	rune(0x00EA),
	rune(0x00EB),
	rune(0x00EC),
	rune(0x00ED),
	rune(0x00EE),
	rune(0x00EF),
	rune(0x00F0),
	rune(0x00F1),
	rune(0x00F2),
	rune(0x00F3),
	rune(0x00F4),
	rune(0x00F5),
	rune(0x00F6),
	rune(0x00F7),
	rune(0x00F8),
	rune(0x00F9),
	rune(0x00FA),
	rune(0x00FB),
	rune(0x00FC),
	rune(0x00FD),
	rune(0x00FE),
	rune(0x00FF),
]

const cp1252_reverse = build_reverse(cp1252_table)

// KOI8-R (Russian Cyrillic)
// koi8r_table: псевдографика в 0x80..0xBF, кириллица в 0xC0..0xFF в «транслитерационном» порядке (юабцде...), поэтому не по алфавиту.
const koi8r_table = [
	rune(0x2500),
	rune(0x2502),
	rune(0x250C),
	rune(0x2510),
	rune(0x2514),
	rune(0x2518),
	rune(0x251C),
	rune(0x2524),
	rune(0x252C),
	rune(0x2534),
	rune(0x253C),
	rune(0x2580),
	rune(0x2584),
	rune(0x2588),
	rune(0x258C),
	rune(0x2590),
	rune(0x2591),
	rune(0x2592),
	rune(0x2593),
	rune(0x2320),
	rune(0x25A0),
	rune(0x2219),
	rune(0x221A),
	rune(0x2248),
	rune(0x2264),
	rune(0x2265),
	rune(0x00A0),
	rune(0x2321),
	rune(0x00B0),
	rune(0x00B2),
	rune(0x00B7),
	rune(0x00F7),
	rune(0x2550),
	rune(0x2551),
	rune(0x2552),
	rune(0x0451),
	rune(0x2553),
	rune(0x2554),
	rune(0x2555),
	rune(0x2556),
	rune(0x2557),
	rune(0x2558),
	rune(0x2559),
	rune(0x255A),
	rune(0x255B),
	rune(0x255C),
	rune(0x255D),
	rune(0x255E),
	rune(0x255F),
	rune(0x2560),
	rune(0x2561),
	rune(0x0401),
	rune(0x2562),
	rune(0x2563),
	rune(0x2564),
	rune(0x2565),
	rune(0x2566),
	rune(0x2567),
	rune(0x2568),
	rune(0x2569),
	rune(0x256A),
	rune(0x256B),
	rune(0x256C),
	rune(0x00A9),
	rune(0x044E),
	rune(0x0430),
	rune(0x0431),
	rune(0x0446),
	rune(0x0434),
	rune(0x0435),
	rune(0x0444),
	rune(0x0433),
	rune(0x0445),
	rune(0x0438),
	rune(0x0439),
	rune(0x043A),
	rune(0x043B),
	rune(0x043C),
	rune(0x043D),
	rune(0x043E),
	rune(0x043F),
	rune(0x044F),
	rune(0x0440),
	rune(0x0441),
	rune(0x0442),
	rune(0x0443),
	rune(0x0436),
	rune(0x0432),
	rune(0x044C),
	rune(0x044B),
	rune(0x0437),
	rune(0x0448),
	rune(0x044D),
	rune(0x0449),
	rune(0x0447),
	rune(0x044A),
	rune(0x042E),
	rune(0x0410),
	rune(0x0411),
	rune(0x0426),
	rune(0x0414),
	rune(0x0415),
	rune(0x0424),
	rune(0x0413),
	rune(0x0425),
	rune(0x0418),
	rune(0x0419),
	rune(0x041A),
	rune(0x041B),
	rune(0x041C),
	rune(0x041D),
	rune(0x041E),
	rune(0x041F),
	rune(0x042F),
	rune(0x0420),
	rune(0x0421),
	rune(0x0422),
	rune(0x0423),
	rune(0x0416),
	rune(0x0412),
	rune(0x042C),
	rune(0x042B),
	rune(0x0417),
	rune(0x0428),
	rune(0x042D),
	rune(0x0429),
	rune(0x0427),
	rune(0x042A),
]

const koi8r_reverse = build_reverse(koi8r_table)
