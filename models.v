// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════════
//  Реактивные данные: Observable и модели для списков, таблиц, деревьев
//  (PROJECT.md, «Реактивные данные: Observable и модели»).
// ═══════════════════════════════════════════════════════════
//
//  Связь «данные -> виджет» раньше была ручной: поменял данные - сам
//  обнови виджет и сам попроси перерисовку окна (сеттеры кадр не
//  инвалидируют). Здесь два инструмента:
//
//  - Observable[T] - одно значение с подписчиками. bind(f) сразу зовёт f с
//    текущим значением и потом с каждым новым: `title.bind(fn [mut lbl] (s
//    string) { lbl.text = s })`.
//  - Модели (TableModel, TreeModel) - данные таблицы или дерева, которые
//    вид (ListBox, TableView, TreeView) читает сам: set_model(m). Вид не
//    копирует строки - таблица и список работают поверх виртуального режима
//    (PROJECT.md, «Виртуальный режим ListBox и TableView») и спрашивают у
//    модели только видимые ячейки. Изменение модели видно по её версии.
//
//  Перерисовка. Модели и Observable не знают своих окон (указателя на окно у
//  виджета нет намеренно). Поэтому любое изменение ставит глобальный флаг
//  «данные изменились» (notify_data_changed), а App перед кадром
//  перерисовывает все окна и просит кадр, пока флаг стоит (render_all,
//  needs_animation_now). Так изменение из обработчика события или из
//  app.post() видно на ближайшем кадре без единого invalidate.
//
//  Всё - в главном потоке (как и весь vgui): из фоновых потоков менять
//  данные через app.post().

// g_data_changed - данные какой-то модели или Observable изменились с
// прошлого кадра. Ставит notify_data_changed, снимает App.render_all.
__global g_data_changed = false

// notify_data_changed - «данные изменились, перерисуйте окна»: App
// перерисует все окна на ближайшем кадре. Зовут модели и Observable; своей
// модели (TableModel/TreeModel без ModelBase) звать её самой.
pub fn notify_data_changed() {
	g_data_changed = true
}

// g_quiet_changes > 0 — идёт отрисовка, раскладка или измерение окна: сеттеры,
// которые виджеты зовут сами по ходу draw()/arrange(), кадр не просят (иначе
// каждый кадр заказывал бы следующий и приложение перерисовывалось бы без
// конца). Ставят Window.render/arrange/measure_content.
__global g_quiet_changes = 0

// widget_changed — «вид виджета изменился» из его сеттера (инвалидация в
// сеттерах, PROJECT.md «Инвалидация и dirty regions»): App перерисует окна на
// ближайшем кадре, как после изменения модели. Звать вручную не нужно: зовут
// публичные set_* виджетов. Внутри отрисовки и раскладки ничего не делает
// (g_quiet_changes). Прямое присваивание поля (`label.text = ...`) сеттером
// не является - после него в своём цикле по-прежнему нужен invalidate.
pub fn widget_changed() {
	if g_quiet_changes == 0 {
		g_data_changed = true
	}
}

// take_data_changed возвращает флаг и снимает его (App.render_all).
fn take_data_changed() bool {
	changed := g_data_changed
	g_data_changed = false
	return changed
}

// ─── Observable ─────────────────────────────────────────

// ObserverEntry - подписчик Observable: id для отписки и колбэк.
struct ObserverEntry[T] {
	id u64
	f  fn (T) = unsafe { nil }
}

// Observable - значение с подписчиками. Создавать observable(v); читать
// get(), менять set(v) - подписчики получают новое значение (только если
// оно изменилось).
@[heap]
pub struct Observable[T] {
mut:
	value     T
	observers []ObserverEntry[T]
	next_id   u64 = 1
}

// observable создаёт наблюдаемое значение с начальным v.
pub fn observable[T](v T) &Observable[T] {
	return &Observable[T]{
		value: v
	}
}

// get - текущее значение.
pub fn (o &Observable[T]) get() T {
	return o.value
}

// set меняет значение. Равное текущему - ничего не происходит (нет лишних
// уведомлений и кадров). Иначе подписчики вызываются по порядку подписки и
// окна перерисовываются на ближайшем кадре.
pub fn (mut o Observable[T]) set(v T) {
	if o.value == v {
		return
	}
	o.value = v
	// Копия списка: подписчик может отписаться (или подписать другого)
	// прямо из колбэка - обход не должен от этого сбиться.
	observers := o.observers.clone()
	for entry in observers {
		entry.f(v)
	}
	notify_data_changed()
}

// subscribe - f(новое значение) на каждое изменение. Возвращает id для
// unsubscribe. Текущее значение не передаётся - для этого bind.
pub fn (mut o Observable[T]) subscribe(f fn (T)) u64 {
	id := o.next_id
	o.next_id++
	o.observers << ObserverEntry[T]{
		id: id
		f:  f
	}
	return id
}

// bind - subscribe, но f сразу получает и текущее значение: так виджет,
// привязанный к данным, с первого кадра показывает верное.
pub fn (mut o Observable[T]) bind(f fn (T)) u64 {
	id := o.subscribe(f)
	f(o.value)
	return id
}

// unsubscribe снимает подписчика по id (неизвестный id - no-op).
pub fn (mut o Observable[T]) unsubscribe(id u64) {
	for i, entry in o.observers {
		if entry.id == id {
			o.observers.delete(i)
			return
		}
	}
}

// ─── Модели ─────────────────────────────────────────────

// ModelBase - счётчик версий для своих моделей: встраивается в структуру
// модели (`struct MyModel { vgui.ModelBase ... }`) и даёт ей version() и
// changed(). Вид сравнивает версию с запомненной и, если она другая,
// перечитывает число строк (таблица, список) или перестраивает узлы (дерево).
pub struct ModelBase {
mut:
	ver u64
}

// version - номер изменения модели (растёт на каждом changed()).
pub fn (m &ModelBase) version() u64 {
	return m.ver
}

// changed - «данные модели изменились»: новая версия и перерисовка окон.
// Своя модель зовёт его после каждой правки данных.
pub fn (mut m ModelBase) changed() {
	m.ver++
	notify_data_changed()
}

// TableModel - данные для ListBox и TableView: число строк и текст ячейки.
// Методы зовутся из draw() главного потока на каждом кадре и только для
// видимых строк - должны быть быстрыми и не менять модель. version() -
// номер изменения (ModelBase): по нему вид узнаёт, что число строк могло
// поменяться.
pub interface TableModel {
	row_count() int
	cell_text(row int, col int) string
	version() u64
}

// TreeModel - данные для TreeView. Узел задаётся строковым id (путь файла,
// ключ БД...), корни - дети id ''. Вид строит узлы, проходя child_ids от
// корней; при новой version() перестраивает их, сохраняя раскрытие и выбор
// по id. item_text - подпись узла.
pub interface TreeModel {
	child_ids(parent string) []string
	item_text(id string) string
	version() u64
}

// RowsModel - готовая модель-таблица: строки из ячеек-строк. Подходит и
// ListBox (одна колонка или несколько), и TableView. Каждая правка - новая
// версия и перерисовка окон, обновлять виджет вручную не нужно.
@[heap]
pub struct RowsModel {
	ModelBase
mut:
	rows [][]string
}

// rows_model создаёт модель с начальными строками (копия).
pub fn rows_model(rows [][]string) &RowsModel {
	return &RowsModel{
		rows: rows.clone()
	}
}

// row_count - число строк (TableModel).
pub fn (m &RowsModel) row_count() int {
	return m.rows.len
}

// cell_text - текст ячейки (TableModel); вне диапазона - ''.
pub fn (m &RowsModel) cell_text(row int, col int) string {
	if row < 0 || row >= m.rows.len {
		return ''
	}
	r := m.rows[row]
	if col < 0 || col >= r.len {
		return ''
	}
	return r[col]
}

// row - копия строки (вне диапазона - пустая).
pub fn (m &RowsModel) row(i int) []string {
	if i < 0 || i >= m.rows.len {
		return []string{}
	}
	return m.rows[i].clone()
}

// append добавляет строку в конец.
pub fn (mut m RowsModel) append(row []string) {
	m.rows << row.clone()
	m.changed()
}

// insert вставляет строку перед i (i зажимается в 0..row_count()).
pub fn (mut m RowsModel) insert(i int, row []string) {
	m.rows.insert(clamp_int(i, 0, m.rows.len), row.clone())
	m.changed()
}

// remove удаляет строку i (вне диапазона - no-op).
pub fn (mut m RowsModel) remove(i int) {
	if i < 0 || i >= m.rows.len {
		return
	}
	m.rows.delete(i)
	m.changed()
}

// set_row заменяет строку i (вне диапазона - no-op).
pub fn (mut m RowsModel) set_row(i int, row []string) {
	if i < 0 || i >= m.rows.len {
		return
	}
	m.rows[i] = row.clone()
	m.changed()
}

// set_cell меняет одну ячейку; строка короче col дополняется пустыми.
pub fn (mut m RowsModel) set_cell(row int, col int, text string) {
	if row < 0 || row >= m.rows.len || col < 0 {
		return
	}
	for m.rows[row].len <= col {
		m.rows[row] << ''
	}
	m.rows[row][col] = text
	m.changed()
}

// set_rows заменяет все строки (копия).
pub fn (mut m RowsModel) set_rows(rows [][]string) {
	m.rows = rows.clone()
	m.changed()
}

// clear удаляет все строки.
pub fn (mut m RowsModel) clear() {
	m.rows.clear()
	m.changed()
}
