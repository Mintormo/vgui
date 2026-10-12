module i18n

// Тесты ядра перевода vgui.i18n: правила форм числа по языкам, разбор имени
// локали в код языка и два вида ключей - тексты на исходном языке
// приложения (set_source_locale) и идентификаторы строк самой vgui
// (add_translations). Файлы переводов подставляет тестовый загрузчик
// demo_loader, диск и SDL не нужны.

// Правила форм числа: по примеру на каждую форму
fn test_plural_index() {
	for n, want in {
		1:   0
		3:   1
		5:   2
		11:  2
		21:  0
		22:  1
		112: 2
	} {
		assert plural_index('ru', n) == want
	}
	for n, want in {
		1:  0
		3:  1
		5:  2
		21: 2
		22: 1
		12: 2
	} {
		assert plural_index('pl', n) == want
	}
	for n, want in {
		1:  0
		4:  1
		5:  2
		21: 2
	} {
		assert plural_index('cs', n) == want
	}
	for n, want in {
		1:  0
		21: 0
		11: 2
		2:  1
		10: 2
		19: 2
	} {
		assert plural_index('lt', n) == want
	}
	for n, want in {
		0:  0
		10: 0
		15: 0
		1:  1
		21: 1
		11: 0
		2:  2
	} {
		assert plural_index('lv', n) == want
	}
	for n, want in {
		1:   0
		0:   1
		2:   1
		19:  1
		20:  2
		101: 1
	} {
		assert plural_index('ro', n) == want
	}
	for n, want in {
		1:   0
		101: 0
		2:   1
		3:   2
		4:   2
		5:   3
	} {
		assert plural_index('sl', n) == want
	}
	for n, want in {
		0: 0
		1: 0
		2: 1
	} {
		assert plural_index('fr', n) == want
	}
	for n, want in {
		1: 0
		0: 1
		2: 1
	} {
		assert plural_index('en', n) == want
	}
	assert plural_index('vi', 1) == 0
	assert plural_index('vi', 5) == 0
	assert plural_index('ru', -21) == 0
}

// Имя локали -> код языка
fn test_locale_code() {
	assert locale_code('uk_UA.UTF-8') == 'uk'
	assert locale_code('pt-BR') == 'pt'
	assert locale_code('de_DE@euro') == 'de'
	assert locale_code('no_NO') == 'nb'
	assert locale_code('nn') == 'nb'
	assert locale_code('fr:en') == 'fr'
	assert locale_code('C') == ''
	assert locale_code('C.UTF-8') == ''
	assert locale_code('POSIX') == ''
	assert locale_code('') == ''
	assert known('kk') && !known('xx')
	assert lang_name('de') == 'Deutsch'
	assert lang_name('xx') == ''
}

// Таблицы тестового приложения: ключи - русский текст, файлы отдаёт
// загрузчик
fn demo_loader(code string) string {
	return match code {
		'de' {
			'{"Кадр": "Bild", "кадр|кадра|кадров": "Bild|Bilder", "Кадр {0} из {1}": "Bild {0} von {1}", "ББ::Оттенок": "Tönung"}'
		}
		'en' {
			'{"Кадр": "Frame", "Только англ.": "English only", "кадр|кадра|кадров": "frame|frames"}'
		}
		'xx' { 'не json' }
		else { '' }
	}
}

// Ключи-тексты на русском: русский - как есть, перевод, запасной
// английский, сам ключ; подстановки; омонимы; формы числа; tr_in
fn test_source_keys() {
	set_loader(demo_loader)
	set_source_locale('ru')
	set_fallback('en')
	set_locale('ru')
	assert tr('Кадр') == 'Кадр'
	assert tr('Только англ.') == 'Только англ.'
	assert trf('Кадр {0} из {1}', '2', '5') == 'Кадр 2 из 5'
	assert trc('ББ', 'Оттенок') == 'Оттенок'
	assert pl(5, 'кадр|кадра|кадров') == 'кадров'
	assert pl(2, 'кадр|кадра|кадров') == 'кадра'
	// tr_in не меняет текущую локаль и не требует её загрузки
	assert tr_in('de', 'Кадр') == 'Bild'
	assert tr_in('de', 'Только англ.') == 'English only'
	assert tr_in('ru', 'Кадр') == 'Кадр'
	assert locale() == 'ru'

	set_locale('de')
	assert tr('Кадр') == 'Bild'
	assert tr('Только англ.') == 'English only'
	assert tr('Нигде') == 'Нигде'
	assert trf('Кадр {0} из {1}', '2', '5') == 'Bild 2 von 5'
	assert trc('ББ', 'Оттенок') == 'Tönung'
	assert trc('HSL', 'Оттенок') == 'Оттенок'
	assert pl(1, 'кадр|кадра|кадров') == 'Bild'
	assert pl(5, 'кадр|кадра|кадров') == 'Bilder'
	// без перевода - русские формы по русскому правилу
	assert pl(5, 'файл|файла|файлов') == 'файлов'
	assert tr_all(['Кадр', 'Нигде']) == ['Bild', 'Нигде']

	// испорченный файл - как нет перевода
	set_locale('xx')
	assert tr('Кадр') == 'Frame'
	set_locale('ru')
}

// Ключи-идентификаторы (строки самой vgui): исходного языка нет, перевод
// и на русский; add_translations_json
fn test_id_keys() {
	add_translations('en', {
		'btn.ok': 'OK'
	})
	add_translations('ru', {
		'btn.ok': 'ОК'
	})
	set_locale('ru')
	assert tr('btn.ok') == 'ОК'
	set_locale('de')
	assert tr('btn.ok') == 'OK'
	add_translations_json('de', '{"btn.ok": "Okay"}') or { panic(err) }
	assert tr('btn.ok') == 'Okay'
	add_translations_json('de', 'не json') or { return }
	assert false, 'испорченный JSON - ошибка'
}
