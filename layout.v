module vgui

// ═══════════════════════════════════════════════════════
// Layout core — measure/arrange
//
// Размер ребёнка берётся из содержимого: виджет сообщает
// контейнеру «мне нужно 137 px под этот текст», а
// контейнер раздаёт место (add(w), add(w, flex:)).
// Здесь - фаза измерения.
//
// Схема двухпроходная, как в Qt/WPF:
//
//   1. measure  — виджет сообщает SizeHint: желаемый
//                 размер, минимум, максимум и политику
//                 растяжения по каждой оси;
//   2. arrange  — контейнер раздаёт детям окончательные
//                 bounds (существующий set_widget_bounds).
//
// Обратная совместимость: интерфейс Widget не меняется.
// Измерение подключается опциональным интерфейсом
// Measurable, и виджет, который его не реализует,
// продолжает работать как раньше (см. measure_widget).
// ═══════════════════════════════════════════════════════

// Верхняя граница размера: «ограничения нет». Не max(f32),
// чтобы арифметика (сложение вложенных max) не давала inf.
pub const size_unbounded = f32(1.0e9)

// Дефолты измерения для управляющих элементов. Виджеты,
// у которых нет собственных полей отступов, считают
// желаемый размер от них.
pub const measure_pad_x = f32(14)
pub const measure_pad_y = f32(6)
pub const measure_min_control_h = f32(30)

// control_h - стандартная высота контрола по теме окна
// (Theme.control_height; не задана - measure_min_control_h)
pub fn (ctx &RenderContext) control_h() f32 {
	return if ctx.theme.control_height > 0 {
		ctx.theme.control_height
	} else {
		measure_min_control_h
	}
}

// SizePolicy — что виджет делает с местом сверх желаемого.
//
//   fixed     — не растягивается и не сжимается (Separator,
//               Icon, Badge);
//   preferred — хочет свой размер, но переживёт растяжение;
//   expanding — активно забирает всё лишнее место
//               (ScrollBox, TextArea, списки).
pub enum SizePolicy {
	fixed
	preferred
	expanding
}

// SizeHint — результат измерения виджета в логических
// пикселях. w/h — желаемый размер, min/max — жёсткие
// границы, которые контейнер обязан соблюдать.
pub struct SizeHint {
pub mut:
	w        f32
	h        f32
	min_w    f32
	min_h    f32
	max_w    f32        = size_unbounded
	max_h    f32        = size_unbounded
	h_policy SizePolicy = .preferred
	v_policy SizePolicy = .preferred
	// css_w / css_h — ограничения по оси заданы таблицей стилей (width,
	// min-width...; css_apply_size). Их уважает и ребёнок с весом в
	// hbox/vbox (child_main_item), который свой hint по главной оси не берёт.
	css_w bool
	css_h bool
}

// clamped приводит hint к самосогласованному виду:
// min ≤ w ≤ max по обеим осям. Вызывается на выходе
// measure_widget, поэтому конкретным виджетам следить
// за согласованностью не нужно.
pub fn (h SizeHint) clamped() SizeHint {
	mut r := h
	if r.max_w < r.min_w {
		r.max_w = r.min_w
	}
	if r.max_h < r.min_h {
		r.max_h = r.min_h
	}
	r.w = clamp_f32(r.w, r.min_w, r.max_w)
	r.h = clamp_f32(r.h, r.min_h, r.max_h)
	return r
}

// axis — проекция hint на одну ось контейнера: возвращает
// (желаемый размер, min, max, политика) вдоль вертикали
// (vertical = true, для VBox) или горизонтали (для HBox).
// Позволяет писать алгоритм раскладки один раз для обеих осей.
fn (h SizeHint) axis(vertical bool) (f32, f32, f32, SizePolicy) {
	if vertical {
		return h.h, h.min_h, h.max_h, h.v_policy
	}
	return h.w, h.min_w, h.max_w, h.h_policy
}

// Measurable — опциональный интерфейс. Виджет, который его
// реализует, участвует в авто-размещении (add(w),
// окна по содержимому, fit_to_content, дорожки GridLayout).
//
// Метод намеренно константный: измерение не должно менять
// состояние виджета — иначе layout начнёт зависеть
// от порядка вызовов.
pub interface Measurable {
	measure(ctx &RenderContext) SizeHint
}

// measure_widget — единая точка измерения любого виджета.
//
// Если виджет реализует Measurable — берём его hint.
// Если нет — деградируем к текущим bounds: виджет получает
// то, что у него уже есть, и помечается как expanding,
// чтобы старые раскладки вели себя как раньше.
// Результат Measurable-виджета кэшируется на один проход измерения
// (measure_cache.v): контейнеры спрашивают одного и того же ребёнка
// по нескольку раз за проход, а для вложенных контейнеров это
// множится с глубиной.
pub fn measure_widget(w &Widget, ctx &RenderContext) SizeHint {
	// Адрес — ключ кэша. Снимается до проверки на Measurable: внутри
	// `if w is Measurable` V сужает тип w, и &Widget из него не получить.
	addr := widget_object_addr(w)
	// Таблица стилей с шрифтом/отступами (css_apply.v): измерять виджет надо
	// с теми же шрифтом и padding, с какими он будет нарисован. Метки - тоже
	// до сужения типа.
	css_active := ctx.css_layout_active()
	css_tags := if css_active { css_tags_of(w) } else { CssTags{} }
	if w is Measurable {
		g_measure_calls++
		// Измерение вне arrange открывает свой проход, поэтому hint
		// из прошлого кадра сюда не попадает.
		if g_measure_depth == 0 && ctx.arrange_depth == 0 {
			measure_pass_begin()
		}
		mut key := u64(0)
		if measure_cache_enabled() {
			key = u64(addr)
			if e := g_measure_cache[key] {
				if e.pass == g_measure_pass {
					g_measure_hits++
					return e.hint
				}
			}
		}

		if g_measure_depth > widget_tree_max_depth {
			// Цикл в дереве (A -> B -> A) или безумная вложенность:
			// как arrange_widget - дальше не спускаемся
			return SizeHint{}
		}
		g_measure_depth++
		mut hint := SizeHint{}
		if css_active {
			// measure() получает неизменяемый контекст, но шрифт и отступы
			// текущего виджета живут в нём: меняем на время вызова и сразу
			// возвращаем (для вызывающего measure остаётся чистым, как
			// get_font_immut)
			mut c := unsafe { &RenderContext(ctx) }
			saved := c.css_enter_layout(addr, css_tags)
			hint = w.measure(ctx)
			// размеры из CSS (width, min-width...) - поверх того, что
			// виджет попросил сам
			if c.css_box.has_size && c.css_box.owner == addr {
				hint = css_apply_size(hint, &c.css_box)
			}
			hint = hint.clamped()
			c.css_leave_layout(saved)
		} else {
			hint = w.measure(ctx).clamped()
		}
		g_measure_depth--

		if key != 0 {
			g_measure_cache[key] = MeasureCacheEntry{
				pass: g_measure_pass
				hint: hint
			}
		}
		return hint
	}
	// Деградация к текущим bounds не кэшируется: bounds меняются
	// в том же проходе arrange.
	b := get_widget_bounds(w)
	return SizeHint{
		w:        b.w
		h:        b.h
		h_policy: .expanding
		v_policy: .expanding
	}
}

// is_measurable сообщает, умеет ли виджет измеряться сам.
// Нужно контейнерам, чтобы отличить «hint от виджета»
// от «hint, восстановленного из bounds».
pub fn is_measurable(w &Widget) bool {
	return w is Measurable
}

// ═══════════════════════════════════════════════════════
// Раздача места вдоль главной оси
// ═══════════════════════════════════════════════════════

// LayoutItem — вход алгоритма распределения. Контейнер
// заполняет его из ChildEntry + SizeHint, а distribute_main
// возвращает окончательные размеры.
struct LayoutItem {
mut:
	base    f32  // желаемый размер
	min     f32  // нижняя граница вдоль оси (из hint и LayoutParams.min)
	max     f32  // верхняя граница вдоль оси (size_unbounded = нет)
	flex    f32  // 0 = не участвует в дележе остатка
	result  f32  // выход: окончательный размер вдоль главной оси
	settled bool // размер уже упёрся в min/max, дележу не подлежит
}

// distribute_main раздаёт `avail` пикселей между items.
//
// Порядок: элементы без flex сразу получают свой base (зажатый
// в min/max) и больше не меняются. Flex-элементы стартуют со
// своего base (у add(w, flex:) он 0, у растягиваемых по природе
// авто-детей - естественный размер) и делят остаток (avail - Σ
// нефлексовых - Σ их base, может быть и меньше нуля - тогда
// сжимаются) пропорционально весам. Элемент, упёршийся в min или
// max, фиксируется, и его доля переразделяется между оставшимися -
// поэтому нужен цикл, а не один проход.
//
// Пример: avail = 300, items = [A base 100 без flex, B flex 1 base 0,
// C flex 1 base 0 max 50]. A сразу получает 100; остаток 200 делится
// пополам, но C упирается в max 50 и фиксируется; на втором круге B
// получает 300 - 100 - 50 = 150.
//
// Результат пишется в items[i].result; сумма результатов может не
// совпасть с avail, если все упёрлись в границы (контейнер тогда
// оставляет пустое место или вылезает за край - это его дело).
fn distribute_main(mut items []LayoutItem, avail f32) {
	if items.len == 0 {
		return
	}
	// Шаг 1: нефлексовые фиксируются сразу, флексовые стартуют с базы.
	for mut it in items {
		if it.flex <= 0 {
			it.result = clamp_f32(it.base, it.min, it.max)
			it.settled = true
		} else {
			it.result = it.base
			it.settled = false
		}
	}

	// Шаг 2: итеративный делёж остатка между ещё не зафиксированными.
	// Не больше items.len итераций: каждый проход либо
	// фиксирует хотя бы один упёршийся элемент, либо
	// раскладка уже сошлась.
	for _ in 0 .. items.len + 1 {
		mut settled_sum := f32(0)
		mut free_flex := f32(0)
		mut base_sum := f32(0)
		for it in items {
			if it.settled {
				settled_sum += it.result
			} else {
				free_flex += it.flex
				base_sum += it.base
			}
		}
		if free_flex <= 0 {
			break
		}
		// Остаток сверх естественных размеров растущих детей (у
		// add(w, flex:) база 0); меньше нуля - они сжимаются к min
		free_space := avail - settled_sum - base_sum

		mut clamped_any := false
		for mut it in items {
			if it.settled {
				continue
			}
			want := it.base + free_space * (it.flex / free_flex)
			got := clamp_f32(want, it.min, it.max)
			it.result = got
			if abs_f32(got - want) > 0.01 {
				// Упёрся в границу — дальше не участвует,
				// его доля переразделяется остальными.
				it.settled = true
				clamped_any = true
			}
		}
		if !clamped_any {
			break
		}
	}
}

// ═══════════════════════════════════════════════════════
// Выравнивание по поперечной оси
// ═══════════════════════════════════════════════════════

// CrossAlign — как ребёнок располагается поперёк главной
// оси контейнера.
//
// stretch — историческое поведение vgui: ребёнок занимает
// всю поперечную ширину. Остаётся значением по умолчанию,
// чтобы существующие раскладки не поехали.
pub enum CrossAlign {
	stretch
	start
	center
	end
	// inherit используется только в LayoutParams: «взять
	// выравнивание контейнера». Как значение самого
	// контейнера равнозначно stretch.
	inherit
}

// align_cross возвращает (смещение, размер) ребёнка на
// поперечной оси внутри отрезка [0, avail].
//
// stretch/inherit - размер = вся доступная ширина (в пределах
// min/max ребёнка), смещение 0. Остальные режимы берут желаемый
// размер pref, но не больше avail, и сдвигают его к началу,
// центру или концу. Смещение не бывает отрицательным: если min
// ребёнка больше avail, он вылезет за конец, а не за начало.
fn align_cross(a CrossAlign, avail f32, pref f32, min f32, max f32) (f32, f32) {
	if a == .stretch || a == .inherit {
		return 0, clamp_f32(avail, min, max)
	}
	size := clamp_f32(min_f32(pref, avail), min, max)
	off := match a {
		.center { max_f32(0, (avail - size) * 0.5) }
		.end { max_f32(0, avail - size) }
		else { f32(0) }
	}
	return off, size
}

// ═══════════════════════════════════════════════════════
// LayoutParams — параметры добавления ребёнка
// ═══════════════════════════════════════════════════════

// LayoutParams описывает, как контейнер должен обойтись
// с ребёнком. Параметры HBox.add/VBox.add:
//
//   box.add(button)                         // по содержимому
//   box.add(button, min: 80)
//   box.add(list, flex: 2, min: 120, align: .center)
//
// Режим: flex > 0 → .flex, иначе .auto (естественный размер
// из measure()). Жёсткого размера нет: min/max - ограничения.
@[params]
pub struct LayoutParams {
pub:
	// 0 - естественный размер (SizeMode.auto); flex > 0 - доля
	// свободного места
	flex f32
	// Границы вдоль главной оси; 0 и size_unbounded = «нет».
	min f32
	max f32 = size_unbounded
	// Выравнивание поперёк оси; inherit = как у контейнера.
	align CrossAlign = .inherit
}

// to_entry переводит параметры в ChildEntry контейнера.
// own_cross запоминает, задал ли ребёнок своё выравнивание
// (иначе контейнер подставит своё cross_align при раскладке).
pub fn (p LayoutParams) to_entry(widget &Widget) ChildEntry {
	mode := if p.flex > 0 { SizeMode.flex } else { SizeMode.auto }
	return ChildEntry{
		widget:    unsafe { widget }
		flex:      if mode == .flex { p.flex } else { f32(0) }
		mode:      mode
		min_main:  p.min
		max_main:  p.max
		own_cross: p.align != .inherit
		cross:     p.align
	}
}

// ═══════════════════════════════════════════════════════
// Утилиты (clamp_f32/abs_f32/min_f32/max_f32 — в types.v)
// ═══════════════════════════════════════════════════════

// measure_text_lines измеряет многострочный текст (\n)
// заданным шрифтом: ширина — по самой длинной строке,
// высота — сумма строк с зазором line_gap.
//
// Пустой текст и пустые строки внутри него всё равно занимают
// высоту строки шрифта: иначе метка без текста схлопнулась бы
// в 0 и при появлении текста раскладка «прыгала» бы.
fn measure_text_lines(ctx &RenderContext, text string, font voidptr, line_gap f32) Vec2 {
	if text.len == 0 {
		return Vec2{0, ctx.font_height_of(font)}
	}
	if !text.contains('\n') {
		return ctx.measure_text_with_font(text, font)
	}
	lines := text.split('\n')
	mut w := f32(0)
	mut h := f32(0)
	for i, line in lines {
		sz := ctx.measure_text_with_font(line, font)
		lh := if line.len == 0 { ctx.font_height_of(font) } else { sz.y }
		w = max_f32(w, sz.x)
		h += lh
		if i < lines.len - 1 {
			h += line_gap
		}
	}
	return Vec2{w, h}
}

// get_widget_bounds — обратная сторона set_widget_bounds:
// читает текущие bounds любого известного виджета.
// Нужна measure_widget как запасной путь для виджетов,
// не реализующих Measurable.
//
// Реализовано через интерфейс Layouted (widget_tree.v) —
// см. раздел «Дерево виджетов» в PROJECT.md. Неизвестный
// (не реализующий Layouted) виджет молча даёт нулевой Rect,
// как и раньше.
pub fn get_widget_bounds(w &Widget) Rect {
	if w is Layouted {
		return w.bounds_of()
	}
	return Rect{0, 0, 0, 0}
}
