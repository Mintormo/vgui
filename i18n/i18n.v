// Перевод интерфейса - ядро на чистом V (без SDL): его можно импортировать
// и из модулей приложения, которым нельзя зависеть от окон (`import
// vgui.i18n`). Сама vgui (vgui.tr, vgui.set_locale ...) - обёртка над ним.
//
// Каталог: локаль -> {ключ: перевод}. Ключ - либо идентификатор
// ('btn.ok' - так строки самой vgui), либо сам текст на исходном языке
// кода, как в gettext: tr('Экспозиция') - код остаётся читаемым, а
// исходный язык не нужен отдельным файлом (set_source_locale('ru')).
//
// Поиск tr(key): текущая локаль -> ключ, если текущая и есть исходная ->
// запасная локаль (по умолчанию en) -> сам ключ.
//
// Таблицы приложение отдаёт загрузчиком (set_loader: код -> текст JSON
// {"ключ": "перевод"}; вшитые $embed_file файлы) - set_locale подгружает
// текущую и запасную; или добавляет сама (add_translations,
// add_translations_json).
//
// Потоки: set_locale, set_* и add_* - только из главного потока при
// запуске, до рабочих потоков; дальше каталог только читается, и tr, trf,
// trc, pl, tr_in можно звать из любых потоков.
// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module i18n

import os
import json2

// Lang - язык: код и самоназвание (для списка выбора языка)
pub struct Lang {
pub:
	code string
	name string
}

// languages - языки, для которых известны самоназвание и правило форм
// числа (plural_index). Порядок - как в списке выбора: русский,
// английский, дальше по алфавиту самоназваний.
pub const languages = [
	Lang{'ru', 'Русский'},
	Lang{'en', 'English'},
	Lang{'id', 'Bahasa Indonesia'},
	Lang{'cs', 'Čeština'},
	Lang{'da', 'Dansk'},
	Lang{'de', 'Deutsch'},
	Lang{'et', 'Eesti'},
	Lang{'es', 'Español'},
	Lang{'fr', 'Français'},
	Lang{'hr', 'Hrvatski'},
	Lang{'it', 'Italiano'},
	Lang{'lv', 'Latviešu'},
	Lang{'lt', 'Lietuvių'},
	Lang{'hu', 'Magyar'},
	Lang{'nl', 'Nederlands'},
	Lang{'nb', 'Norsk bokmål'},
	Lang{'pl', 'Polski'},
	Lang{'pt', 'Português (Brasil)'},
	Lang{'ro', 'Română'},
	Lang{'sk', 'Slovenčina'},
	Lang{'sl', 'Slovenščina'},
	Lang{'fi', 'Suomi'},
	Lang{'sv', 'Svenska'},
	Lang{'vi', 'Tiếng Việt'},
	Lang{'tr', 'Türkçe'},
	Lang{'el', 'Ελληνικά'},
	Lang{'be', 'Беларуская'},
	Lang{'bg', 'Български'},
	Lang{'kk', 'Қазақ тілі'},
	Lang{'sr', 'Српски'},
	Lang{'uk', 'Українська'},
]

// Loader - текст JSON перевода для локали ('' - нет такой)
pub type Loader = fn (code string) string

// Глобальное состояние модуля (только главный поток, без блокировок): текущая и запасная локали, исходный язык ключей,
// флаг явного выбора, каталог «локаль -> {ключ: перевод}», учёт загруженных загрузчиком локалей и сам загрузчик.
__global (
	g_tr_current  = 'en'
	g_tr_fallback = 'en'
	g_tr_source   = '' // язык ключей-текстов; '' - ключи-идентификаторы
	g_tr_set      = false // локаль выбрана явно (set_locale)
	g_tr_catalog  = map[string]map[string]string{}
	// локали, чьи файлы загрузчик уже отдал (переводы add_* - в том же
	// каталоге, но файл локали может прийти и после них)
	g_tr_loaded   = map[string]bool{}
	g_tr_loader   = Loader(unsafe { nil })
)

// known - есть ли язык в languages
pub fn known(code string) bool {
	return languages.any(it.code == code)
}

// lang_name - самоназвание языка ('' - неизвестен)
pub fn lang_name(code string) string {
	for l in languages {
		if l.code == code {
			return l.name
		}
	}
	return ''
}

// locale_code - код языка из имени локали: 'uk_UA.UTF-8' -> 'uk',
// 'pt-BR' -> 'pt', норвежские no/nn -> nb; '' - локаль не задана
// ('C', 'POSIX', пусто)
pub fn locale_code(s string) string {
	v := s.to_lower().trim_space()
	if v.len < 2 || v == 'c' || v.starts_with('c.') || v == 'posix' {
		return ''
	}
	code := v.all_before(':').all_before('.').all_before('@').all_before('_').all_before('-')
	if code.len < 2 {
		return ''
	}
	return if code in ['no', 'nn'] { 'nb' } else { code }
}

// env_locale - язык из переменных окружения LC_ALL, LC_MESSAGES, LANG,
// LANGUAGE (первая заданная); '' - не задан
pub fn env_locale() string {
	for key in ['LC_ALL', 'LC_MESSAGES', 'LANG', 'LANGUAGE'] {
		code := locale_code(os.getenv(key))
		if code != '' {
			return code
		}
	}
	return ''
}

// set_loader - откуда брать таблицы локалей (set_locale, tr_in)
pub fn set_loader(f Loader) {
	g_tr_loader = f
}

// set_source_locale - язык, на котором написаны ключи-тексты в коде:
// для него перевод не нужен, tr отдаёт сам ключ
pub fn set_source_locale(code string) {
	g_tr_source = code
}

pub fn source_locale() string {
	return g_tr_source
}

// set_fallback - запасная локаль, когда в текущей нет перевода
pub fn set_fallback(code string) {
	g_tr_fallback = code
	ensure_loaded(code)
}

pub fn fallback() string {
	return g_tr_fallback
}

// set_locale - текущая локаль; таблицы текущей и запасной - загрузчиком
// (если ещё не загружены)
pub fn set_locale(code string) {
	g_tr_current = code
	g_tr_set = true
	ensure_loaded(code)
	ensure_loaded(g_tr_fallback)
}

pub fn locale() string {
	return g_tr_current
}

// locale_set - локаль выбрана явно (set_locale), а не по умолчанию
pub fn locale_set() bool {
	return g_tr_set
}

// ensure_loaded - один раз за локаль просит загрузчик таблицу и вливает её в каталог. Исходный язык и пустой код пропускаются (перевод не нужен). Флаг g_tr_loaded ставится ДО загрузки, поэтому провал загрузки повторно не пробуется.
fn ensure_loaded(code string) {
	if code == '' || code == g_tr_source || g_tr_loaded[code] {
		return
	}
	g_tr_loaded[code] = true
	add_translations(code, load_table(code))
}

// load_table - таблица локали загрузчиком (пустая - нет загрузчика,
// файла или он испорчен); каталог не меняет
fn load_table(code string) map[string]string {
	if g_tr_loader == unsafe { nil } {
		return map[string]string{}
	}
	text := g_tr_loader(code)
	if text == '' {
		return map[string]string{}
	}
	return json2.decode[map[string]string](text) or { map[string]string{} }
}

// add_translation - перевод ключа key на локаль code
pub fn add_translation(key string, code string, value string) {
	if code !in g_tr_catalog {
		g_tr_catalog[code] = map[string]string{}
	}
	g_tr_catalog[code][key] = value
}

// add_translations - переводы на локаль code {ключ: перевод}
pub fn add_translations(code string, pairs map[string]string) {
	if pairs.len == 0 {
		return
	}
	if code !in g_tr_catalog {
		g_tr_catalog[code] = map[string]string{}
	}
	for k, v in pairs {
		g_tr_catalog[code][k] = v
	}
}

// add_translations_json - переводы на локаль code из текста JSON
// {"ключ": "перевод"}
pub fn add_translations_json(code string, text string) ! {
	add_translations(code, json2.decode[map[string]string](text)!)
}

// lookup - перевод key в таблице локали code ('' - нет)
fn lookup(code string, key string) string {
	if t := g_tr_catalog[code] {
		if v := t[key] {
			return v
		}
	}
	return ''
}

// tr - перевод key на текущую локаль
pub fn tr(key string) string {
	v := lookup(g_tr_current, key)
	if v != '' {
		return v
	}
	if g_tr_current == g_tr_source {
		return key
	}
	f := lookup(g_tr_fallback, key)
	return if f != '' { f } else { key }
}

// trc - перевод омонима: одна строка исходного языка, разные переводы
// («Оттенок» - Hue в HSL и Tint в балансе белого). Ключ перевода -
// «контекст::строка»; на исходном языке и без перевода - сама строка.
pub fn trc(ctx string, s string) string {
	key := ctx + '::' + s
	t := tr(key)
	return if t == key { s } else { t }
}

// trf - перевод с подстановками {0}, {1}...
pub fn trf(key string, args ...string) string {
	mut r := tr(key)
	for i, a in args {
		r = r.replace('{${i}}', a)
	}
	return r
}

// tr_all - перевод списка (названия пунктов из констант: константы V
// вычисляются до main, когда язык ещё не выбран, - переводить при показе)
pub fn tr_all(a []string) []string {
	return a.map(tr(it))
}

// tr_in - перевод key на локаль code, не меняя текущей (например,
// подпись о смене языка - сразу на выбранном). Незагруженная локаль
// читается загрузчиком без записи в каталог - можно из любого потока.
// Без перевода - запасная локаль, на исходном языке - сам ключ.
pub fn tr_in(code string, key string) string {
	if code == g_tr_source {
		return key
	}
	for c in [code, g_tr_fallback] {
		mut v := lookup(c, key)
		if v == '' && !g_tr_loaded[c] && c != g_tr_source {
			v = load_table(c)[key] or { '' }
		}
		if v != '' {
			return v
		}
	}
	return key
}

// pl - форма слова для числа n. forms - формы через «|» (ключ перевода,
// на исходном языке); перевод - формы своего языка через «|» в порядке
// plural_index. Перевода нет - формы и правило исходного языка (без
// него - текущего).
pub fn pl(n i64, forms string) string {
	t := tr(forms)
	code := if t == forms && g_tr_source != '' { g_tr_source } else { g_tr_current }
	f := t.split('|')
	i := plural_index(code, n)
	return f[if i < f.len { i } else { f.len - 1 }]
}

// plural_index - номер формы для числа n по правилу языка (CLDR, только
// целые). Порядок форм в переводе:
//   ru uk be sr hr          один | два-четыре | пять (21 - один, 11 - пять)
//   pl                      один | два-четыре | пять (21 - пять)
//   cs sk                   один | два-четыре | остальные
//   lt                      один (1, 21) | два-девять | остальные (11-19, 10, 20)
//   lv                      ноль (0, 10-20, 30) | один (1, 21) | остальные
//   ro                      один | мало (0, 2-19, 101-119) | остальные
//   sl                      один (1, 101) | два (2, 102) | три-четыре | остальные
//   fr pt                   один (0, 1) | остальные
//   vi id                   одна форма
//   остальные               один | остальные
pub fn plural_index(code string, n i64) int {
	a := if n < 0 { -n } else { n }
	m10 := a % 10
	m100 := a % 100
	return match code {
		'ru', 'uk', 'be', 'sr', 'hr' {
			if m10 == 1 && m100 != 11 {
				0
			} else if m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) {
				1
			} else {
				2
			}
		}
		'pl' {
			if a == 1 {
				0
			} else if m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) {
				1
			} else {
				2
			}
		}
		'cs', 'sk' {
			if a == 1 {
				0
			} else if a >= 2 && a <= 4 {
				1
			} else {
				2
			}
		}
		'lt' {
			if m10 == 1 && (m100 < 11 || m100 > 19) {
				0
			} else if m10 >= 2 && (m100 < 11 || m100 > 19) {
				1
			} else {
				2
			}
		}
		'lv' {
			if m10 == 0 || (m100 >= 11 && m100 <= 19) {
				0
			} else if m10 == 1 && m100 != 11 {
				1
			} else {
				2
			}
		}
		'ro' {
			if a == 1 {
				0
			} else if a == 0 || (m100 >= 1 && m100 <= 19) {
				1
			} else {
				2
			}
		}
		'sl' {
			if m100 == 1 {
				0
			} else if m100 == 2 {
				1
			} else if m100 == 3 || m100 == 4 {
				2
			} else {
				3
			}
		}
		'fr', 'pt' {
			if a <= 1 { 0 } else { 1 }
		}
		'vi', 'id' {
			0
		}
		else {
			if a == 1 { 0 } else { 1 }
		}
	}
}
