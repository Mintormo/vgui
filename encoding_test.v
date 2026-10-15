module vgui

// Кодировки (аудит 2026-10, 5.1): битый UTF-8 при чтении заменяется на U+FFFD, строгое
// кодирование не теряет символы молча, имена кодировок с дефисами разбираются.
//
// Запуск (из корня vgui): v test encoding_test.v

fn test_utf8_decode_sanitizes() {
	assert decode_bytes('привет'.bytes(), .utf8) == 'привет'
	assert decode_bytes([u8(0xEF), 0xBB, 0xBF, `a`], .utf8) == 'a'
	bad := [u8(`a`), 0xFF, `b`, 0xD0] // 0xFF - не ведущий байт, 0xD0 - обрыв
	assert decode_bytes(bad, .utf8) == 'a�b�'
	overlong := [u8(0xC0), 0xAF]
	assert decode_bytes(overlong, .utf8) == '��'
}

fn test_strict_encoding() {
	assert encode_string_strict('abc', .latin1)? == 'abc'.bytes()
	assert encode_string_strict('Ж', .cp1251)? == [u8(0xC6)]
	if _ := encode_string_strict('Ж', .latin1) {
		assert false, 'кириллица в latin1 непредставима'
	}
	assert encode_string('Ж', .latin1) == [u8(`?`)] // прежнее поведение с потерями
}

fn test_parse_encoding_names() {
	assert parse_encoding('UTF-8') == .utf8
	assert parse_encoding('ISO-8859-1') == .latin1
	assert parse_encoding('Windows-1251') == .cp1251
	assert parse_encoding('koi8-r') == .koi8r
	assert parse_encoding('unknown') == .utf8
}
