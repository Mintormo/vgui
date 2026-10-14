module vgui

import os

// ═══════════════════════════════════════════════════════
// css_apply — как таблица стилей попадает на экран
// ═══════════════════════════════════════════════════════
//
// Разбор - css.v, значения свойств - css_props.v, модель целиком - PROJECT.md,
// «Стили CSS». Здесь:
//   1. метки виджета для селекторов: #id и классы (CssTags, поле `css` у каждого
//      виджета) и функции для них;
//   2. RenderContext.draw_child — отрисовка ребёнка с подменой темы. Контейнеры
//      рисуют детей через неё, а не через w.draw(): только так правило узнаёт
//      предков виджета (`.sidebar button`) - указателя на родителя у виджета нет
//      (PROJECT.md, «Дерево виджетов»), поэтому цепочка предков копится в
//      ctx.css_stack по ходу обхода сверху вниз;
//   3. корневые правила (:root, menu, tooltip...) — css_base_theme: они
//      вшиваются в саму тему окна, потому что попапы и уведомления рисуются
//      после дерева, когда подменённой темы уже нет;
//   4. установка таблицы окну/приложению и перезагрузка файла при изменении.
//
// Почему подмена темы, а не стили в каждом виджете: все виджеты уже берут
// цвета из ctx.theme (сотни мест), и копия темы с другими полями мгновенно
// работает для всех, без правки draw() у полусотни типов. Цена - копия Theme
// (~1 КБ) на каждый виджет, к которому подошло правило, за кадр.

// CssTags — метки виджета для селекторов: `#id` и `.классы`. Поле `css` есть у
// каждой структуры виджета; .vui заполняет его из `#id` и `.класс`, код - через
// set_css_id/add_css_class или прямым присваиванием (`btn.css.classes = [...]`).
pub struct CssTags {
pub mut:
	id      string
	classes []string
}

// CssTagged — «у виджета есть поле css». Интерфейс по полю: ему автоматически
// удовлетворяет любая структура с полем `css CssTags`, как HasVisibility -
// с полем visible (widget_tree.v).
//
// ВАЖНО: менять метки через интерфейс можно только присваиванием поля целиком
// (`w.css = tags`). `w.css.classes << x` через интерфейс компилируется, но
// пишет во временную копию массива, и изменение молча теряется (проверено на
// V 0137eb5) - поэтому функции ниже собирают новый CssTags и присваивают его.
pub interface CssTagged {
mut:
	css CssTags
}

// set_css_id задаёт виджету имя для селектора `#id`. Кадр не инвалидирует (как
// все сеттеры виджетов): в своём цикле - Window.invalidate_all().
pub fn set_css_id(mut w Widget, id string) {
	if mut w is CssTagged {
		mut tags := w.css
		tags.id = id
		w.css = tags
	}
}

// add_css_class добавляет класс (повторное добавление ничего не меняет).
pub fn add_css_class(mut w Widget, name string) {
	if mut w is CssTagged {
		if name in w.css.classes {
			return
		}
		mut tags := w.css
		mut classes := tags.classes.clone()
		classes << name
		tags.classes = classes
		w.css = tags
	}
}

// remove_css_class убирает класс (если его не было - ничего).
pub fn remove_css_class(mut w Widget, name string) {
	if mut w is CssTagged {
		mut tags := w.css
		tags.classes = tags.classes.filter(it != name)
		w.css = tags
	}
}

// has_css_class — есть ли у виджета класс.
pub fn has_css_class(w &Widget, name string) bool {
	if w is CssTagged {
		return name in w.css.classes
	}
	return false
}

// css_tags_of — метки виджета (пустые, если поля css у типа нет).
pub fn css_tags_of(w &Widget) CssTags {
	if w is CssTagged {
		return w.css
	}
	return CssTags{}
}

// CssNode — звено цепочки предков рисуемого виджета (ctx.css_stack).
struct CssNode {
	kind int
	tags CssTags
}

// ─── Отрисовка с подменой темы ─────────────────────────

// draw_child рисует ребёнка контейнера с учётом таблицы стилей окна. Без таблицы -
// просто w.draw(). Контейнеры обязаны рисовать детей через неё (иначе правила
// с предками, `.sidebar button`, не увидят этого контейнера в цепочке).
//
// Шаги: (1) виджет кладётся в ctx.css_stack - теперь он «текущий», а стек под ним -
// его предки; (2) ищется, подходит ли хоть одно правило; если нет - обычная
// отрисовка; (3) иначе тема сохраняется, все подошедшие правила по порядку
// каскада пишут свои поля в ctx.theme, и виджет со всем поддеревом рисуется уже
// с ней; (4) тема восстанавливается, виджет снимается со стека.
pub fn (mut ctx RenderContext) draw_child(mut w Widget) {
	if isnil(ctx.stylesheet) || ctx.stylesheet.rules.len == 0 {
		w.draw(mut ctx)
		return
	}
	kind := widget_type_tag(widget_object_addr(&w))
	ctx.css_stack << CssNode{
		kind: kind
		tags: css_tags_of(&w)
	}
	ss := ctx.stylesheet
	// (2) сначала только проверка - копию темы делаем, лишь если правило нашлось
	mut matched := false
	for rule in ss.rules {
		if css_selector_matches(rule.selector, ctx.css_stack) {
			matched = true
			break
		}
	}
	if !matched {
		w.draw(mut ctx)
		ctx.css_stack.pop()
		return
	}
	// (3) правила уже отсортированы по (специфичность, порядок в файле) -
	// css_sort_rules: применяем подряд, и более сильное пишет последним
	saved := ctx.theme
	mut fill := Color{}
	mut has_fill := false
	mut has_radius := false
	if kind > 0 && kind <= css_max_kind {
		for rule in ss.rules {
			if !css_selector_matches(rule.selector, ctx.css_stack) {
				continue
			}
			for d in rule.decls {
				for f in d.fields_by_kind[kind] {
					if f == css_fill_field {
						fill = d.value.color
						has_fill = true
						continue
					}
					if f == 'border_radius' {
						has_radius = true
					}
					// тип значения проверен при разборе (css_check_value) - ошибки не будет
					theme_set_field(mut ctx.theme, f, d.value) or {}
				}
			}
		}
	}
	// заливка контейнера без своего цвета в теме (vbox, grid...): под детьми.
	// Скругление - только если правило задало border-radius, иначе прямоугольник.
	if has_fill && w is Layouted {
		r := w.bounds_of()
		radius := if has_radius { ctx.theme.border_radius } else { f32(0) }
		ctx.fill_rounded_rect(r, fill, radius)
	}
	w.draw(mut ctx)
	// (4)
	ctx.theme = saved
	ctx.css_stack.pop()
}

// css_selector_matches — подходит ли селектор к вершине стека (стек - цепочка
// от корня окна до рисуемого виджета включительно).
fn css_selector_matches(sel &CssSelector, stack []CssNode) bool {
	if stack.len == 0 || sel.parts.len == 0 {
		return false
	}
	return css_match_at(sel, 0, stack, stack.len - 1)
}

// css_match_at — звено pi селектора на узле si стека, и рекурсивно остальные
// звенья на предках. Для «потомка» перебираются все предки (с возвратом: в
// `a > b c` первый найденный b может не иметь родителя a, а следующий - иметь).
fn css_match_at(sel &CssSelector, pi int, stack []CssNode, si int) bool {
	if !css_compound_matches(sel.parts[pi], stack[si]) {
		return false
	}
	if pi + 1 >= sel.parts.len {
		return true
	}
	if sel.parts[pi].rel == .child {
		return si > 0 && css_match_at(sel, pi + 1, stack, si - 1)
	}
	for j := si - 1; j >= 0; j-- {
		if css_match_at(sel, pi + 1, stack, j) {
			return true
		}
	}
	return false
}

fn css_compound_matches(c &CssCompound, n &CssNode) bool {
	if c.kind != 0 && c.kind != n.kind {
		return false
	}
	if c.id.len > 0 && c.id != n.tags.id {
		return false
	}
	for cls in c.classes {
		if cls !in n.tags.classes {
			return false
		}
	}
	return true
}

// css_sort_rules — порядок каскада: по специфичности, при равной - по месту в
// файле. Тогда при отрисовке правила применяются просто подряд.
fn css_sort_rules(mut rules []CssRule) {
	rules.sort_with_compare(fn (a &CssRule, b &CssRule) int {
		if a.specificity != b.specificity {
			return if a.specificity < b.specificity { -1 } else { 1 }
		}
		return if a.order < b.order {
			-1
		} else if a.order > b.order {
			1
		} else {
			0
		}
	})
}

// css_base_theme — тема окна с применёнными корневыми правилами (:root, menu,
// tooltip, notification, dropdown). nil-таблица - тема без изменений.
pub fn css_base_theme(theme Theme, ss &Stylesheet) Theme {
	mut t := theme
	if isnil(ss) {
		return t
	}
	for rule in ss.root_rules {
		for d in rule.decls {
			for f in d.root_fields {
				theme_set_field(mut t, f, d.value) or {}
			}
		}
	}
	return t
}

// ─── Окно и приложение ─────────────────────────────────

// set_stylesheet задаёт окну собственную таблицу стилей (nil - без стилей):
// после этого таблица приложения (App.set_stylesheet) его больше не меняет.
pub fn (mut w Window) set_stylesheet(ss &Stylesheet) {
	w.css_explicit = true
	w.apply_stylesheet(ss)
}

// apply_stylesheet ставит таблицу, не делая её явной - путь App.set_stylesheet.
// Тема окна пересобирается из исходной (без стилей, w.config.theme) - иначе
// корневые правила старой таблицы остались бы в ней навсегда.
fn (mut w Window) apply_stylesheet(ss &Stylesheet) {
	w.ctx.stylesheet = unsafe { ss }
	w.ctx.theme = css_base_theme(w.unstyled_theme(), ss)
	w.ctx.clear_text_cache()
	w.invalidate_all()
}

// unstyled_theme — тема окна без корневых правил CSS (заданная или светлая по умолчанию).
fn (w &Window) unstyled_theme() Theme {
	return w.config.theme or { light_theme() }
}

// stylesheet — текущая таблица стилей окна (nil - нет).
pub fn (w &Window) stylesheet() &Stylesheet {
	return w.ctx.stylesheet
}

// set_stylesheet задаёт таблицу стилей приложения: всем окнам и диалогам без
// своей таблицы и будущим (как App.set_theme). nil - убрать стили.
pub fn (mut app App) set_stylesheet(ss &Stylesheet) {
	app.stylesheet = unsafe { ss }
	for mut w in app.windows {
		if !w.css_explicit {
			w.apply_stylesheet(ss)
		}
	}
	for mut d in app.dialogs {
		if !d.win.css_explicit {
			d.win.apply_stylesheet(ss)
		}
	}
}

// load_stylesheet читает CSS-файл и делает его таблицей приложения. watch -
// следить за файлом: при изменении он перечитывается сам (раз в
// css_watch_interval_ms, в pump_events). Ошибка в изменённом файле не роняет
// приложение: печатается в stderr, а на экране остаются прежние стили.
pub fn (mut app App) load_stylesheet(path string, watch bool) ! {
	ss := load_stylesheet(path)!
	app.set_stylesheet(ss)
	app.css_path = if watch { path } else { '' }
	app.css_mtime = os.file_last_mod_unix(path)
}

// css_watch_interval_ms — как часто проверять файл стилей при watch.
const css_watch_interval_ms = u64(500)

// poll_stylesheet — перечитать файл стилей, если он изменился. Зовётся из
// pump_events; сама решает, пора ли проверять (stat раз в полсекунды, а не
// на каждой итерации цикла). true - стили сменились, нужен кадр.
fn (mut app App) poll_stylesheet() bool {
	if app.css_path.len == 0 {
		return false
	}
	now := C.SDL_GetTicks()
	if now < app.css_next_check {
		return false
	}
	app.css_next_check = now + css_watch_interval_ms
	mtime := os.file_last_mod_unix(app.css_path)
	if mtime == app.css_mtime {
		return false
	}
	app.css_mtime = mtime
	ss := load_stylesheet(app.css_path) or {
		eprintln('vgui: стили не перезагружены, остаются прежние: ${err.msg()}')
		return false
	}
	app.set_stylesheet(ss)
	return true
}
