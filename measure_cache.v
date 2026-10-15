// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════
// Кэш SizeHint на один проход измерения (аудит 3.A)
// ═══════════════════════════════════════════════════════
//
// measure() чист и дёшев по отдельности, но зовут его много: BoxLayout
// в content_size() спрашивает ребёнка, а потом ещё раз в child_main_item()
// для .auto и в layout() при cross_align != .stretch. Для вложенных
// контейнеров это удваивается на каждом уровне — измерение поддерева
// растёт как 2^глубина, и каждое обращение к Label/Button идёт в метрики
// TTF.
//
// Кэш живёт ровно один проход (pass) и хранится по адресу самого объекта
// за интерфейсом Widget:
//
//   * проход открывает Window.arrange() — все измерения одного arrange
//     видят один кэш;
//   * любое измерение вне arrange (fit_to_content, capi, тесты, свой
//     цикл) открывает собственный проход, поэтому устаревший hint
//     из прошлого кадра не всплывает никогда. Инвалидация «по тексту,
//     шрифту и теме» при таком сроке жизни не нужна: внутри одного
//     прохода ничего из этого не меняется.
//
// Кэшируются только виджеты, реализующие Measurable. Деградация
// «hint из текущих bounds» (measure_widget для остальных) не кэшируется
// намеренно: bounds меняются прямо в проходе arrange.

// MeasureCacheEntry — измерение виджета и проход, в котором оно снято.
// Запись с чужим pass считается отсутствующей (clear() на границе прохода
// и так её убирает — сверка pass оставлена как страховка).
struct MeasureCacheEntry {
	pass u64
	hint SizeHint
}

__global g_measure_cache map[u64]MeasureCacheEntry
__global g_measure_pass = u64(1)

// Глубина рекурсии measure_widget: нужна, чтобы отличить измерение
// «с нуля» (глубина 0 вне arrange — открываем новый проход) от
// вложенного (контейнер измеряет детей — проход уже открыт).
__global g_measure_depth = 0

// Счётчики для тестов и диагностики: сколько измерений запрошено
// и сколько из них отдал кэш.
__global g_measure_calls = u64(0)
__global g_measure_hits = u64(0)

// 0 — самопроверка ещё не делалась, 1 — кэш работает, -1 — выключен.
__global g_measure_cache_ok = 0

// widget_object_addr — адрес объекта, лежащего за интерфейсным значением
// Widget. Нужен как ключ кэша: интерфейсная «толстая» структура копируется
// при каждой передаче и живёт по разным адресам, а адрес самого виджета
// один и тот же.
//
// V не даёт читать `w._object` как значение. Приведение интерфейса к
// указателю на структуру компиляторы понимают по-разному: старый (0.5.2)
// снимает обёртку и отдаёт _object, новый честно даёт адрес самой обёртки.
// Поэтому читаем указатель прямо из обёртки: _object у обоих лежит в ней
// первым полем (смещение 0). Через voidptr - иначе старый компилятор снова
// снимет обёртку. Предположение проверяет measure_cache_enabled(): если
// оно однажды перестанет быть верным, кэш просто выключится.
fn widget_object_addr(w &Widget) voidptr {
	unsafe {
		// По шагам намеренно: и `voidptr(&WidgetTagHeader(w))`, и
		// `*&voidptr(w)` одним выражением компиляторы разворачивают по-своему.
		raw := voidptr(w)
		slot := &voidptr(raw)
		return *slot
	}
}

// measure_cache_enabled — разовая самопроверка раскладки интерфейса:
// адрес, полученный через widget_object_addr, обязан совпасть с адресом
// заведомо известного виджета. Не совпал — кэш выключается, и всё
// работает как до него (медленнее, но верно).
fn measure_cache_enabled() bool {
	if g_measure_cache_ok == 0 {
		probe := &Label{}
		g_measure_cache_ok = if widget_object_addr(Widget(probe)) == voidptr(probe) {
			1
		} else {
			-1
		}
	}
	return g_measure_cache_ok == 1
}

// measure_pass_begin открывает новый проход измерения: старые записи
// больше не видны. Зовётся из Window.arrange() и из measure_widget()
// для измерений вне arrange.
pub fn measure_pass_begin() {
	g_measure_pass++
	g_measure_cache.clear()
}

// measure_pass_enter / measure_pass_leave — объявить серию измерений одним
// проходом: measure_widget внутри неё не открывает новых проходов, даже если
// зовётся с верхнего уровня (вне arrange). Так измеряет корни окна
// Window.measure_content() — иначе каждый корень открывал бы свой проход.
pub fn measure_pass_enter() {
	measure_pass_begin()
	g_measure_depth++
}

// measure_pass_leave закрывает серию, открытую measure_pass_enter.
//
// Вызовы обязаны быть парными: enter поднимает g_measure_depth, и пока
// leave не опустил его обратно, measure_widget считает любое измерение
// вложенным и не открывает новый проход (кэш остаётся от enter).
// leave не уходит ниже нуля - лишний вызов безвреден.
pub fn measure_pass_leave() {
	if g_measure_depth > 0 {
		g_measure_depth--
	}
}

// measure_cache_counters — (запросов, попаданий). Аксессор: __global
// модуля не виден из _test.v.
pub fn measure_cache_counters() (u64, u64) {
	return g_measure_calls, g_measure_hits
}

// measure_cache_len — сколько виджетов измерено в текущем проходе.
pub fn measure_cache_len() int {
	return g_measure_cache.len
}

// measure_cache_reset_counters — обнуление счётчиков (для тестов).
pub fn measure_cache_reset_counters() {
	g_measure_calls = 0
	g_measure_hits = 0
}
