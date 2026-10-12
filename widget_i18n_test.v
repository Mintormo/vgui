module vgui

// Тексты виджетов идут через перевод (аудит 2026-10, раздел 4): DatePicker,
// ComboBox, PropertyGrid. Без окна и SDL.
//
// Запуск (из корня vgui): v -enable-globals test widget_i18n_test.v

fn test_widget_texts_follow_locale() {
	set_locale('ru')
	assert dp_month_name(1) == 'Январь'
	assert dp_day_name(0) == 'Пн'
	assert combo_box().eff_placeholder() == '— выберите —'
	assert tr('pg.value') == 'Значение'
	set_locale('en')
	assert dp_month_name(12) == 'December'
	assert dp_day_name(6) == 'Su'
	assert combo_box().eff_placeholder() == '— select —'
	// Заданный текст подсказки перевод не трогает.
	mut cb := combo_box()
	cb.placeholder = 'Свой'
	assert cb.eff_placeholder() == 'Свой'
	assert dp_month_name(13) == '?'
}
