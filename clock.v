// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

import time

// ═══════════════════════════════════════════════════════
// Часы интерфейса — единственный источник «сейчас» для виджетов.
// ═══════════════════════════════════════════════════════
//
// Мигание курсора, вращение спиннера, таймеры уведомлений и подсказок, шаг
// анимаций — всё берёт время отсюда, а не из SDL_GetTicks напрямую
// (PROJECT.md, «Бэкенд рисования: виджеты не зовут SDL напрямую»). Так:
//   - виджеты не знают про SDL;
//   - время можно остановить или подменить в одном месте: тесты получают
//     детерминированный кадр (спиннер всегда под одним углом, курсор всегда
//     виден), а запись видео по кадрам — равномерное время.
//
// Подмена глобальная, а не на окно: часы нужны и вне draw() (конструкторы
// уведомлений, обработчики событий), где RenderContext под рукой нет. Окно
// всё равно одно на процесс в смысле потока (всё в главном потоке).

// g_clock_override_ms: > 0 — часы стоят на этом значении (мс), 0 — настоящее
// время SDL. __global не виден из _test.v — тесты ходят через
// set_clock_override / clear_clock_override. Только главный поток.
__global g_clock_override_ms = u64(0)

// now_ms — текущее время интерфейса в миллисекундах от старта SDL
// (монотонное). При подмене (set_clock_override) — подменённое значение.
pub fn now_ms() u64 {
	if g_clock_override_ms > 0 {
		return g_clock_override_ms
	}
	return C.SDL_GetTicks()
}

// set_clock_override останавливает часы интерфейса на ms (мс; 0 — снять
// подмену). Для тестов и покадровой записи: дальше время двигает только
// вызывающий — следующим set_clock_override или advance_clock.
pub fn set_clock_override(ms u64) {
	g_clock_override_ms = ms
}

// clear_clock_override возвращает настоящее время SDL.
pub fn clear_clock_override() {
	g_clock_override_ms = 0
}

// advance_clock сдвигает подменённые часы вперёд на ms. Без подмены — no-op:
// настоящее время сдвигать нечем.
pub fn advance_clock(ms u64) {
	if g_clock_override_ms > 0 {
		g_clock_override_ms += ms
	}
}

// now_ms — то же, что модульная now_ms(), для кода с контекстом под рукой
// (draw/arrange): ctx.now_ms() читается естественнее и оставляет место,
// чтобы часы со временем стали своими у окна.
pub fn (ctx &RenderContext) now_ms() u64 {
	return now_ms()
}

// g_today_override: год, месяц, день «сегодня» для календарей; год 0 - настоящая
// дата. Отдельно от g_clock_override_ms: тот - мс от старта SDL, а не дата.
__global g_today_override = [3]int{}

// today - сегодняшняя дата (год, месяц 1-12, день 1-31) по локальному времени
// или подменённая set_today_override. Её берут DatePicker и Calendar (подсветка
// «сегодня», кнопка «Сегодня»): иначе их снапшот менялся бы каждый день.
pub fn today() (int, int, int) {
	if g_today_override[0] > 0 {
		return g_today_override[0], g_today_override[1], g_today_override[2]
	}
	now := time.now()
	return now.year, now.month, now.day
}

// set_today_override задаёт «сегодня» для тестов (y <= 0 - снять подмену).
pub fn set_today_override(y int, m int, d int) {
	g_today_override = [y, m, d]!
}
