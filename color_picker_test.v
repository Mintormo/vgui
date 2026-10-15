module vgui

// ColorPicker: строгий разбор hex (аудит 2026-10, 2.10). Прежняя эвристика
// `c.a > 0 || text.contains('00')` принимала мусор, содержащий «00».
//
// Запуск (из корня vgui): v test color_picker_test.v

fn test_parse_hex_is_strict() {
	assert cp_parse_hex('#FF8000')? == Color{255, 128, 0, 255}
	assert cp_parse_hex('ff800080')? == Color{255, 128, 0, 128}
	assert cp_parse_hex('#00000000')? == Color{0, 0, 0, 0}
	if _ := cp_parse_hex('#00zz00') {
		assert false, 'не-hex символы'
	}
	if _ := cp_parse_hex('#1234') {
		assert false, 'неверная длина'
	}
	if _ := cp_parse_hex('') {
		assert false, 'пустая строка'
	}
}
