module vgui

// Перевод интерфейса vgui - обёртка над подмодулем vgui.i18n (ядро на
// чистом V: каталог переводов, исходный и запасной языки, загрузчик
// таблиц, омонимы trc, формы числа pl по правилам CLDR). Здесь - строки
// самой vgui (ключи-идентификаторы 'btn.ok', en и ru), язык системы с
// учётом SDL и прежний API (vgui.tr, vgui.set_locale ...). Приложение
// может звать vgui.i18n напрямую - в том числе из своих модулей, которым
// нельзя зависеть от окон и SDL.
import vgui.i18n

pub const locale_en = 'en'
pub const locale_ru = 'ru'

// g_i18n_inited - встроенные словари (en/ru) уже загружены в каталог vgui.i18n; i18n_init() выполняется один раз. Только главный поток.
__global g_i18n_inited = false

// ─── Init (idempotent) ─────────────────────────────────

// i18n_init - строки vgui в каталог; локаль, если её ещё не выбрали
// явно, - язык системы. Зовётся сама из tr и set_locale.
pub fn i18n_init() {
	if g_i18n_inited {
		return
	}
	g_i18n_inited = true
	i18n_load_builtins()
	if !i18n.locale_set() {
		i18n.set_locale(detect_system_locale())
	}
}

// i18n_init_with_locale - то же, что set_locale (оставлено для обратной совместимости).
pub fn i18n_init_with_locale(locale string) {
	set_locale(locale)
}

// ─── System locale detection ───────────────────────────

// C-структура SDL_Locale (язык и страна) для разбора результата SDL_GetPreferredLocales.
@[typedef]
struct C.SDL_Locale {
	language &char
	country  &char
}

fn C.SDL_GetPreferredLocales(count &i32) &&C.SDL_Locale

// detect_system_locale - код языка системы ('uk', 'de'...): переменные
// окружения (LC_ALL, LC_MESSAGES, LANG, LANGUAGE - их уважают на Linux,
// и ими можно переопределить язык где угодно), затем предпочтения ОС
// через SDL (Windows и macOS - переменных там обычно нет); не нашлось -
// 'en'. Код может быть не из i18n.languages - проверяет приложение.
pub fn detect_system_locale() string {
	code := i18n.env_locale()
	if code != '' {
		return code
	}
	mut n := i32(0)
	list := C.SDL_GetPreferredLocales(&n)
	if list != unsafe { nil } {
		defer {
			C.SDL_free(list)
		}
		for i in 0 .. int(n) {
			loc := unsafe { list[i] }
			if loc == unsafe { nil } || loc.language == unsafe { nil } {
				continue
			}
			c := i18n.locale_code(unsafe { cstring_to_vstring(loc.language) })
			if c != '' {
				return c
			}
		}
	}
	return 'en'
}

// ─── Public API ────────────────────────────────────────

// set_locale явно выбирает язык интерфейса (например 'ru') и инициализирует встроенные строки. После явного выбора язык системы больше не определяется.
pub fn set_locale(locale string) {
	i18n.set_locale(locale)
	i18n_init()
}

// get_locale - текущий код языка.
pub fn get_locale() string {
	i18n_init()
	return i18n.locale()
}

// set_fallback_locale - язык, на который падает tr, если на текущем нет перевода ключа.
pub fn set_fallback_locale(locale string) {
	i18n_init()
	i18n.set_fallback(locale)
}

// set_source_locale - язык ключей-текстов в коде приложения (см.
// vgui.i18n); для него tr отдаёт сам ключ
pub fn set_source_locale(locale string) {
	i18n.set_source_locale(locale)
}

// set_translation_loader - откуда брать таблицы локалей приложения
// (код -> текст JSON {"ключ": "перевод"}); звать до set_locale
pub fn set_translation_loader(f i18n.Loader) {
	i18n.set_loader(f)
}

// tr - перевод по ключу ('btn.ok') на текущий язык; нет перевода - запасной язык, затем сам ключ.
pub fn tr(key string) string {
	i18n_init()
	return i18n.tr(key)
}

// Format with positional args: {0}, {1}, ...
// trf - tr с подстановкой позиционных аргументов вместо {0}, {1}, ... (например 'Удалить файл «{0}»?').
pub fn trf(key string, args ...string) string {
	i18n_init()
	return i18n.trf(key, ...args)
}

// trc - перевод омонима (ключ «контекст::строка»)
pub fn trc(ctx string, key string) string {
	i18n_init()
	return i18n.trc(ctx, key)
}

// pl - форма слова для числа n (формы через «|», правило языка)
pub fn pl(n i64, forms string) string {
	i18n_init()
	return i18n.pl(n, forms)
}

// plural_index - номер формы для числа n по правилу языка locale
pub fn plural_index(locale string, n i64) int {
	return i18n.plural_index(locale, n)
}

// tr_in - перевод на локаль locale, не меняя текущей
pub fn tr_in(locale string, key string) string {
	i18n_init()
	return i18n.tr_in(locale, key)
}

// add_translation / add_translations - добавить свои переводы (приложение может расширять и переопределять встроенные строки vgui).
pub fn add_translation(key string, locale string, value string) {
	i18n.add_translation(key, locale, value)
}

pub fn add_translations(locale string, pairs map[string]string) {
	i18n.add_translations(locale, pairs)
}

// add_translations_json - переводы на локаль из текста JSON
pub fn add_translations_json(locale string, text string) ! {
	i18n.add_translations_json(locale, text)!
}

// ─── Built-in dictionaries ─────────────────────────────

// i18n_load_builtins - встроенные строки самой vgui на en и ru (ключи по префиксам: btn.* общие кнопки, fd.* файловый
// диалог, dp.* календарь, cp.* выбор цвета, combo/table/imageview.* заглушки). Вызывается один раз из i18n_init.
// Не все ключи реально используются кодом: см. отчёт - часть виджетов пока содержит захардкоженные тексты.
fn i18n_load_builtins() {
	i18n.add_translations('en', {
		'btn.ok':                   'OK'
		'btn.cancel':               'Cancel'
		'btn.yes':                  'Yes'
		'btn.no':                   'No'
		'btn.save':                 'Save'
		'btn.open':                 'Open'
		'btn.close':                'Close'
		'btn.apply':                'Apply'
		'btn.delete':               'Delete'
		'btn.rename':               'Rename'
		'btn.select':               'Select'
		'btn.today':                'Today'
		'btn.new_folder':           'Add folder'
		'fd.title.open':            'Select file'
		'fd.title.save':            'Save file'
		'fd.title.folder':          'Select folder'
		'fd.ext_placeholder':       'Extension (e.g. *.rs)'
		'fd.sort.name_asc':         'Name A-Z'
		'fd.sort.name_desc':        'Name Z-A'
		'fd.sort.type':             'Type'
		'fd.sort.size_asc':         'Size ↑'
		'fd.sort.size_desc':        'Size ↓'
		'fd.confirm_delete_title':  'Confirm Delete'
		'fd.confirm_delete_file':   'Delete file "{0}"?'
		'fd.confirm_delete_folder': 'Delete folder "{0}"?'
		'fd.new_folder_name':       'New folder'
		'fd.ctx.new_folder':        'New Folder'
		'fd.ctx.rename':            'Rename'
		'fd.ctx.delete':            'Delete'
		'fd.ctx.delete_force':      'Delete (no confirm)'
		'fd.ctx.sort':              'Sort by'
		'fd.ctx.show_hidden':       'Show hidden files'
		'fd.btn.save':              'Save'
		'fd.btn.select':            'Select'
		'fd.btn.cancel':            'Cancel'
		'dp.title':                 'Select Date'
		'dp.month.1':               'January'
		'dp.month.2':               'February'
		'dp.month.3':               'March'
		'dp.month.4':               'April'
		'dp.month.5':               'May'
		'dp.month.6':               'June'
		'dp.month.7':               'July'
		'dp.month.8':               'August'
		'dp.month.9':               'September'
		'dp.month.10':              'October'
		'dp.month.11':              'November'
		'dp.month.12':              'December'
		'dp.day.mon':               'Mo'
		'dp.day.tue':               'Tu'
		'dp.day.wed':               'We'
		'dp.day.thu':               'Th'
		'dp.day.fri':               'Fr'
		'dp.day.sat':               'Sa'
		'dp.day.sun':               'Su'
		'cp.title':                 'Color Picker'
		'cp.old':                   'Old'
		'cp.new':                   'New'
		'cp.rgba':                  'RGB(A)'
		'cp.hsv':                   'HSV'
		'combo.placeholder':        '— select —'
		'table.empty':              '(no data)'
		'imageview.no_image':       '(no image)'
		'imageview.load_failed':    'Failed to load:'
	})
	i18n.add_translations('ru', {
		'btn.ok':                   'ОК'
		'btn.cancel':               'Отмена'
		'btn.yes':                  'Да'
		'btn.no':                   'Нет'
		'btn.save':                 'Сохранить'
		'btn.open':                 'Открыть'
		'btn.close':                'Закрыть'
		'btn.apply':                'Применить'
		'btn.delete':               'Удалить'
		'btn.rename':               'Переименовать'
		'btn.select':               'Выбрать'
		'btn.today':                'Сегодня'
		'btn.new_folder':           'Создать папку'
		'fd.title.open':            'Выбор файла'
		'fd.title.save':            'Сохранение файла'
		'fd.title.folder':          'Выбор папки'
		'fd.ext_placeholder':       'Расширение (например *.rs)'
		'fd.sort.name_asc':         'Имя А-Я'
		'fd.sort.name_desc':        'Имя Я-А'
		'fd.sort.type':             'Тип'
		'fd.sort.size_asc':         'Размер ↑'
		'fd.sort.size_desc':        'Размер ↓'
		'fd.confirm_delete_title':  'Подтверждение удаления'
		'fd.confirm_delete_file':   'Удалить файл «{0}»?'
		'fd.confirm_delete_folder': 'Удалить папку «{0}»?'
		'fd.new_folder_name':       'Новая папка'
		'fd.ctx.new_folder':        'Создать папку'
		'fd.ctx.rename':            'Переименовать'
		'fd.ctx.delete':            'Удалить'
		'fd.ctx.delete_force':      'Удалить без подтверждения'
		'fd.ctx.sort':              'Сортировка'
		'fd.ctx.show_hidden':       'Показывать скрытые файлы'
		'fd.btn.save':              'Сохранить'
		'fd.btn.select':            'Выбрать'
		'fd.btn.cancel':            'Отмена'
		'dp.title':                 'Выбор даты'
		'dp.month.1':               'Январь'
		'dp.month.2':               'Февраль'
		'dp.month.3':               'Март'
		'dp.month.4':               'Апрель'
		'dp.month.5':               'Май'
		'dp.month.6':               'Июнь'
		'dp.month.7':               'Июль'
		'dp.month.8':               'Август'
		'dp.month.9':               'Сентябрь'
		'dp.month.10':              'Октябрь'
		'dp.month.11':              'Ноябрь'
		'dp.month.12':              'Декабрь'
		'dp.day.mon':               'Пн'
		'dp.day.tue':               'Вт'
		'dp.day.wed':               'Ср'
		'dp.day.thu':               'Чт'
		'dp.day.fri':               'Пт'
		'dp.day.sat':               'Сб'
		'dp.day.sun':               'Вс'
		'cp.title':                 'Выбор цвета'
		'cp.old':                   'Было'
		'cp.new':                   'Стало'
		'cp.rgba':                  'RGB(A)'
		'cp.hsv':                   'HSV'
		'combo.placeholder':        '— выберите —'
		'table.empty':              '(нет данных)'
		'imageview.no_image':       '(нет изображения)'
		'imageview.load_failed':    'Не удалось загрузить:'
	})
}
