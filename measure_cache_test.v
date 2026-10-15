module vgui

// ═══════════════════════════════════════════════════════
// Кэш SizeHint (аудит 3.A, measure_cache.v)
//
// Проверяется то, на чём кэш стоит и чем он опасен:
//   - адрес объекта за интерфейсом Widget читается верно (на этом построен
//     ключ; если раскладка интерфейсов в V изменится, тест упадёт раньше,
//     чем кэш начнёт путать виджеты);
//   - внутри прохода повторное измерение отдаётся из кэша, поэтому каждый
//     виджет поддерева измеряется один раз;
//   - разные виджеты не склеиваются в одну запись;
//   - новый проход выкидывает старые записи, поэтому изменившийся размер
//     виден сразу;
//   - виджет без measure() не кэшируется (его hint — текущие bounds).
//
// Запуск: v test vgui/measure_cache_test.v (из v/)
// ═══════════════════════════════════════════════════════

fn measure_cache_ctx() &RenderContext {
	return &RenderContext{
		screen_width:  800
		screen_height: 600
	}
}

// Ключ кэша — адрес самого виджета, а не копии интерфейсной структуры.
fn test_widget_object_addr_is_the_widget() {
	lbl := label('hi')
	assert widget_object_addr(Widget(lbl)) == voidptr(lbl)
	// Копия интерфейсного значения обязана дать тот же адрес.
	arr := [Widget(lbl)]
	assert widget_object_addr(arr[0]) == voidptr(lbl)
	// Самопроверка кэша на этой сборке проходит — кэш включён.
	assert measure_cache_enabled()
}

// Внутри одного прохода второй запрос обслуживает кэш.
fn test_repeated_measure_inside_pass_hits_cache() {
	ctx := measure_cache_ctx()
	mut ic := icon('star')
	ic.size = 24
	measure_pass_enter()
	measure_cache_reset_counters()
	first := measure_widget(ic, ctx)
	second := measure_widget(ic, ctx)
	measure_pass_leave()
	calls, hits := measure_cache_counters()
	assert calls == 2
	assert hits == 1
	assert first.w == second.w
	assert first.h == second.h
}

// Вложенные контейнеры: ребёнка измеряют и content_size, и child_main_item,
// и так на каждом уровне. С кэшем на один вызов родителя приходится ровно
// одно измерение каждого виджета поддерева.
fn test_nested_box_measures_each_child_once() {
	ctx := measure_cache_ctx()
	mut inner := create_vbox_fill()
	mut a := icon('a')
	a.size = 16
	mut b := icon('b')
	b.size = 16
	inner.add(a)
	inner.add(b)

	mut outer := create_vbox_fill()
	mut c := icon('c')
	c.size = 16
	outer.add(inner)
	outer.add(c)

	measure_pass_begin()
	measure_cache_reset_counters()
	hint := measure_widget(outer, ctx)
	assert hint.w > 0

	// Поддерево — 5 виджетов (outer, inner, три иконки).
	assert measure_cache_len() == 5
	calls, hits := measure_cache_counters()
	assert calls - hits == 5
	assert hits > 0
}

// Разные виджеты не должны делить запись.
fn test_different_widgets_get_own_entries() {
	ctx := measure_cache_ctx()
	mut small := icon('a')
	small.size = 16
	mut big := icon('b')
	big.size = 48
	measure_pass_enter()
	hs := measure_widget(small, ctx)
	hb := measure_widget(big, ctx)
	measure_pass_leave()
	assert hs.w == 16
	assert hb.w == 48
	assert measure_cache_len() == 2
}

// Новый проход — новое измерение: изменённый размер виден сразу.
fn test_new_pass_drops_stale_hint() {
	ctx := measure_cache_ctx()
	mut ic := icon('a')
	ic.size = 16
	measure_pass_enter()
	before := measure_widget(ic, ctx)
	measure_pass_leave()
	ic.set_size(40)
	// Измерение с глубины 0 вне arrange открывает новый проход само,
	// поэтому старая запись не всплывает.
	after := measure_widget(ic, ctx)
	assert before.w == 16
	assert after.w == 40
}

// Виджет без measure() не кэшируется: его hint берётся из bounds,
// которые меняются прямо в проходе arrange.
fn test_non_measurable_is_not_cached() {
	ctx := measure_cache_ctx()
	mut n := notification('test')
	measure_pass_enter()
	n.bounds = Rect{0, 0, 10, 10}
	first := measure_widget(n, ctx)
	n.bounds = Rect{0, 0, 30, 30}
	second := measure_widget(n, ctx)
	measure_pass_leave()
	assert first.w == 10
	assert second.w == 30
	assert measure_cache_len() == 0
}
