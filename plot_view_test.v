module vgui

import math

// PlotView: разбор CSV (аудит 2026-10, 2.20). Нечисловое поле давало 0 вместо NaN, и
// строка с текстом становилась ложной точкой (0, 0). Без окна и SDL.
//
// Запуск (из корня vgui): v -enable-globals test plot_view_test.v

fn test_csv_number_parsing() {
	assert csv_parse_number('1.5', ',') == f32(1.5)
	assert csv_parse_number(' 2,5 ', ';') == f32(2.5)
	assert csv_parse_number('"3"', ',') == f32(3)
	assert math.is_nan(f64(csv_parse_number('n/a', ',')))
	assert math.is_nan(f64(csv_parse_number('', ',')))
}

fn test_csv_skips_non_numeric_rows() {
	text := 'x,y\n1,2\nbad,row\n3,4\n'
	pts := parse_csv_points(text, ',', false, 0, 1) // заголовок не объявлен - тоже пропуск
	assert pts.len == 2
	assert pts[1].x == 3 && pts[1].y == 4
}
