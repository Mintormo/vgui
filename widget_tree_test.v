module vgui

// Юнит-тесты дерева виджетов (widget_tree.v).
//
// SDL и шрифты не нужны: конструктор-литералы `&Type{}` создают
// виджеты с нулевыми/дефолтными полями, а bounds_of/set_bounds
// не трогают рендерер.
//
// Главная ценность файла — по одной проверке на каждый из 51 типа,
// перечисленного в (бывших) get_widget_bounds/set_widget_bounds
// (см. счётчик в widget_tree.v). ВАЖНО: это НЕ самопроверяющийся
// механизм — в V нельзя перечислить все реализации интерфейса
// программно, поэтому новый тип виджета, для которого забыли
// добавить bounds_of/set_bounds в widget_tree.v, компилируется
// молча и просто не ломает ни один существующий тест здесь; список
// не следит сам за собой, а появление нового Widget-типа без своей
// test_layouted_* функции — сигнал ревьюеру, что список неполон
// (сверяйте с PROJECT.md "Константы _kind виджетов" при добавлении
// нового виджета).
//
// Запуск: v -enable-globals test vgui/widget_tree_test.v

// WalkCollector — вспомогательная куча для теста walk_widgets:
// closure-параметр cb принимает только (&Widget), поэтому
// собирать результат приходится через захваченный указатель
// (тот же паттерн, что и state-замыкания в color_picker.v).
struct WalkCollector {
mut:
	names []string
}

// ─── walk_widgets / widget_at на маленьком дереве ──────
//
//   VBox (0,0,200,200)
//     ├─ Label       bounds (0,0,200,50)
//     └─ HBox        bounds (0,50,200,150)
//          ├─ Button bounds (0,50,100,150)
//          └─ Button bounds (100,50,100,150)  ← "верхний" (последний)

fn test_walk_widgets_preorder() {
	mut lbl := &Label{
		bounds: Rect{0, 0, 200, 50}
	}
	mut btn1 := &Button{
		bounds: Rect{0, 50, 100, 150}
	}
	mut btn2 := &Button{
		bounds: Rect{100, 50, 100, 150}
	}
	mut inner := &HBox{}
	inner.box.bounds = Rect{0, 50, 200, 150}
	inner.box.children << ChildEntry{
		widget: unsafe { btn1 }
	}
	inner.box.children << ChildEntry{
		widget: unsafe { btn2 }
	}

	mut root := &VBox{}
	root.box.bounds = Rect{0, 0, 200, 200}
	root.box.children << ChildEntry{
		widget: unsafe { lbl }
	}
	root.box.children << ChildEntry{
		widget: unsafe { inner }
	}

	root_w := Widget(root)
	mut collector := &WalkCollector{}
	walk_widgets(root_w, fn [mut collector] (w &Widget) {
		if w is VBox {
			collector.names << 'vbox'
		} else if w is HBox {
			collector.names << 'hbox'
		} else if w is Label {
			collector.names << 'label'
		} else if w is Button {
			collector.names << 'button'
		}
	})
	assert collector.names == ['vbox', 'label', 'hbox', 'button', 'button']
}

fn test_widget_at_hit_test() {
	mut lbl := &Label{
		bounds: Rect{0, 0, 200, 50}
	}
	mut btn1 := &Button{
		bounds: Rect{0, 50, 100, 150}
	}
	mut btn2 := &Button{
		bounds: Rect{100, 50, 100, 150}
	}
	mut inner := &HBox{}
	inner.box.bounds = Rect{0, 50, 200, 150}
	inner.box.children << ChildEntry{
		widget: unsafe { btn1 }
	}
	inner.box.children << ChildEntry{
		widget: unsafe { btn2 }
	}

	mut root := &VBox{}
	root.box.bounds = Rect{0, 0, 200, 200}
	root.box.children << ChildEntry{
		widget: unsafe { lbl }
	}
	root.box.children << ChildEntry{
		widget: unsafe { inner }
	}

	root_w := Widget(root)

	// Точка в Label.
	hit1 := widget_at(root_w, 10, 10) or { panic('expected a hit') }
	assert hit1 is Label

	// Точка в первой кнопке.
	hit2 := widget_at(root_w, 10, 100) or { panic('expected a hit') }
	assert hit2 is Button
	assert (hit2 as Button).bounds.x == 0

	// Точка во второй кнопке (перекрытие проверяет z-порядок —
	// последний добавленный ребёнок выигрывает).
	hit3 := widget_at(root_w, 150, 100) or { panic('expected a hit') }
	assert hit3 is Button
	assert (hit3 as Button).bounds.x == 100

	// Точка вне всех bounds.
	miss := widget_at(root_w, 500, 500)
	assert miss == none
}

fn test_has_children_matches_child_widgets() {
	mut child := &Label{}
	mut p := &Panel{}
	p.set_child(child)
	pw := Widget(p)
	assert pw is HasChildren
	if pw is HasChildren {
		kids := pw.child_widgets()
		assert kids.len == 1
	}

	mut empty_p := &Panel{}
	epw := Widget(empty_p)
	assert epw is HasChildren
	if epw is HasChildren {
		assert epw.child_widgets().len == 0
	}
}

// ─── Layouted: bounds_of/set_bounds для каждого типа ───

fn test_layouted_hbox() {
	mut w := Widget(&HBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_vbox() {
	mut w := Widget(&VBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_panel() {
	mut w := Widget(&Panel{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_stack() {
	mut w := Widget(&Stack{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_spacer() {
	mut w := Widget(&Spacer{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_centered() {
	mut w := Widget(&Centered{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_scrollbox() {
	mut w := Widget(&ScrollBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_button() {
	mut w := Widget(&Button{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_label() {
	mut w := Widget(&Label{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_textinput() {
	mut w := Widget(&TextInput{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_listbox() {
	mut w := Widget(&ListBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_combobox() {
	mut w := Widget(&ComboBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_checkbox() {
	mut w := Widget(&CheckBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_radiobutton() {
	mut w := Widget(&RadioButton{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_toggleswitch() {
	mut w := Widget(&ToggleSwitch{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_tabbox() {
	mut w := Widget(&TabBox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_menubar() {
	mut w := Widget(&MenuBar{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_contextmenu() {
	mut w := Widget(&ContextMenu{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_splitter() {
	mut w := Widget(&Splitter{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_separator() {
	mut w := Widget(&Separator{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_treeview() {
	mut w := Widget(&TreeView{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_windowtitledrag() {
	mut w := Widget(&WindowTitleDrag{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_spinner() {
	mut w := Widget(&Spinner{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_tooltip() {
	mut w := Widget(&Tooltip{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_codeeditor() {
	mut w := Widget(&CodeEditor{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_slider() {
	mut w := Widget(&Slider{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_progressbar() {
	mut w := Widget(&ProgressBar{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_imageview() {
	mut w := Widget(&ImageView{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_menubutton() {
	mut w := Widget(&MenuButton{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_colorpicker() {
	mut w := Widget(&ColorPicker{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_datepicker() {
	mut w := Widget(&DatePicker{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_cparea() {
	mut w := Widget(&CpArea{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_dparea() {
	mut w := Widget(&DpArea{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_accordion() {
	mut w := Widget(&Accordion{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_tableview() {
	mut w := Widget(&TableView{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_plotview() {
	mut w := Widget(&PlotView{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_spinbox() {
	mut w := Widget(&Spinbox{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_propertygrid() {
	mut w := Widget(&PropertyGrid{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_breadcrumbs() {
	mut w := Widget(&Breadcrumbs{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_markdownview() {
	mut mv := &MarkdownView{}
	mv.dirty = false
	mut w := Widget(mv)
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
	assert mv.dirty == true
}

fn test_layouted_notificationmanager() {
	mut w := Widget(&NotificationManager{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_textarea() {
	mut w := Widget(&TextArea{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_badge() {
	mut w := Widget(&Badge{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_calendar() {
	mut w := Widget(&Calendar{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_gridlayout() {
	mut w := Widget(&GridLayout{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_dropzone() {
	mut w := Widget(&DropZone{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_imagebackground() {
	mut w := Widget(&ImageBackground{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_canvas() {
	mut w := Widget(&Canvas{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_icon() {
	mut w := Widget(&Icon{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_curve_editor() {
	mut w := Widget(&CurveEditor{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

fn test_layouted_notification() {
	mut w := Widget(&Notification{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

// CpPreview (color_picker.v) — унаследованный пропуск, найденный при
// ревью: без Layouted превью "Old/New" в диалоге цвета рисовалось
// в Rect{0,0,0,0} и было невидимо (см. комментарий у CpPreview
// в widget_tree.v).
fn test_layouted_cppreview() {
	mut w := Widget(&CpPreview{})
	r := Rect{5, 6, 7, 8}
	set_widget_bounds(mut w, r)
	assert get_widget_bounds(w) == r
}

// ─── HitTestable: TabBox/Accordion/ListBox ─────────────

fn test_hit_testable_tabbox_only_active_tab() {
	mut w1 := &Label{ text: 'active' }
	mut w2 := &Label{ text: 'inactive' }
	mut tb := &TabBox{}
	tb.tabs << TabEntry{
		widget: unsafe { w1 }
	}
	tb.tabs << TabEntry{
		widget: unsafe { w2 }
	}
	tb.active = 0
	tw := Widget(tb)
	assert tw is HitTestable
	if tw is HitTestable {
		kids := tw.hit_children()
		assert kids.len == 1
		assert (kids[0] as Label).text == 'active'
	}
}

fn test_hit_testable_accordion_only_expanded() {
	mut w1 := &Label{ text: 'collapsed' }
	mut w2 := &Label{ text: 'expanded' }
	mut acc := &Accordion{}
	acc.sections << AccordionSection{
		widget:   unsafe { w1 }
		expanded: false
	}
	acc.sections << AccordionSection{
		widget:   unsafe { w2 }
		expanded: true
	}
	aw := Widget(acc)
	assert aw is HitTestable
	if aw is HitTestable {
		kids := aw.hit_children()
		assert kids.len == 1
		assert (kids[0] as Label).text == 'expanded'
	}
}

// widget_at: клик мимо активной вкладки не должен попасть в
// виджет неактивной вкладки, даже если у того остались старые
// (совпадающие по координатам) bounds — регрессионный сценарий
// из ревью: открыть вкладку 1, переключиться на 0, кликнуть.
fn test_widget_at_skips_inactive_tab() {
	mut active_child := &Label{
		bounds: Rect{0, 0, 100, 100}
		text:   'active'
	}
	mut stale_child := &Label{
		bounds: Rect{0, 0, 100, 100} // устаревшие bounds от прошлого показа
		text:   'stale'
	}
	mut tb := &TabBox{
		bounds: Rect{0, 0, 100, 100}
	}
	tb.tabs << TabEntry{
		widget: unsafe { active_child }
	}
	tb.tabs << TabEntry{
		widget: unsafe { stale_child }
	}
	tb.active = 0

	tw := Widget(tb)
	hit := widget_at(tw, 10, 10) or { panic('expected a hit') }
	assert hit is Label
	assert (hit as Label).text == 'active'
}

fn test_widget_at_skips_invisible() {
	mut hidden := &Label{
		bounds:  Rect{0, 0, 100, 100}
		visible: false
	}
	mut root := &VBox{}
	root.box.bounds = Rect{0, 0, 100, 100}
	root.box.children << ChildEntry{
		widget: unsafe { hidden }
	}
	root_w := Widget(root)
	hit := widget_at(root_w, 10, 10) or { panic('expected a hit') }
	// Скрытый ребёнок пропущен — попадание уходит в сам VBox.
	assert hit is VBox
}

// widget_at: зеркало test_widget_at_skips_inactive_tab — если сделать
// активной вкладку 1 (не первую), клик должен попасть именно в её
// виджет. Без этого теста реализация «всегда возвращать tabs[0]»
// прошла бы предыдущий тест незамеченной.
fn test_widget_at_hits_active_tab_when_not_first() {
	mut tab0 := &Label{
		bounds: Rect{0, 0, 100, 100}
		text:   'tab0'
	}
	mut tab1 := &Label{
		bounds: Rect{0, 0, 100, 100}
		text:   'tab1'
	}
	mut tb := &TabBox{
		bounds: Rect{0, 0, 100, 100}
	}
	tb.tabs << TabEntry{
		widget: unsafe { tab0 }
	}
	tb.tabs << TabEntry{
		widget: unsafe { tab1 }
	}
	tb.active = 1

	tw := Widget(tb)
	hit := widget_at(tw, 10, 10) or { panic('expected a hit') }
	assert hit is Label
	assert (hit as Label).text == 'tab1'
}

// widget_at пропускает ребёнка с нулевым размером bounds (w<=0 или
// h<=0) — тот же признак «сейчас не нарисован», что и visible==false;
// попадание должно провалиться на родителя.
fn test_widget_at_skips_zero_bounds_widget() {
	mut zero := &Label{
		bounds: Rect{10, 10, 0, 0}
		text:   'zero'
	}
	mut root := &VBox{}
	root.box.bounds = Rect{0, 0, 100, 100}
	root.box.children << ChildEntry{
		widget: unsafe { zero }
	}
	root_w := Widget(root)
	hit := widget_at(root_w, 10, 10) or { panic('expected a hit') }
	assert hit is VBox
}

// Регрессия по ревью: HBox/VBox не покрыты полем-интерфейсом
// HasVisibility (их флаг лежит в box.visible, а не в топ-уровневом
// поле), поэтому widget_at требует явной проверки типа. Эти два
// теста ловят возврат к «просто HasVisibility и всё» — без явной
// проверки клик по скрытому боксу проваливался бы во вложенный
// видимый Label.
fn test_widget_at_skips_hidden_hbox_subtree() {
	mut child := &Label{
		bounds: Rect{0, 0, 50, 50}
		text:   'inside'
	}
	mut hidden_box := &HBox{}
	hidden_box.box.bounds = Rect{0, 0, 100, 100}
	hidden_box.box.visible = false
	hidden_box.box.children << ChildEntry{
		widget: unsafe { child }
	}

	mut root := &VBox{}
	root.box.bounds = Rect{0, 0, 100, 100}
	root.box.children << ChildEntry{
		widget: unsafe { hidden_box }
	}

	root_w := Widget(root)
	hit := widget_at(root_w, 10, 10) or { panic('expected a hit') }
	// Скрытый HBox пропущен целиком — попадание уходит в родительский VBox,
	// а не в видимый Label внутри скрытого HBox.
	assert hit is VBox
}

fn test_widget_at_skips_hidden_vbox_subtree() {
	mut child := &Label{
		bounds: Rect{0, 0, 50, 50}
		text:   'inside'
	}
	mut hidden_box := &VBox{}
	hidden_box.box.bounds = Rect{0, 0, 100, 100}
	hidden_box.box.visible = false
	hidden_box.box.children << ChildEntry{
		widget: unsafe { child }
	}

	mut root := &HBox{}
	root.box.bounds = Rect{0, 0, 100, 100}
	root.box.children << ChildEntry{
		widget: unsafe { hidden_box }
	}

	root_w := Widget(root)
	hit := widget_at(root_w, 10, 10) or { panic('expected a hit') }
	assert hit is HBox
}

// Потолок глубины (widget_tree_max_depth) на РЕАЛЬНОМ цикле владения
// A→B→A (не detach-по-ошибке, а буквальный self-referencing граф —
// то, от чего потолок и защищает). Без потолка walk_widgets_impl
// рекурсировал бы бесконечно и уронил бы стек; с потолком обход
// останавливается на depth == widget_tree_max_depth (последний cb
// вызывается ровно на этой глубине, глубже — нет), так что итоговое
// число вызовов детерминировано: widget_tree_max_depth + 1 (глубины
// 0..widget_tree_max_depth включительно).
fn test_walk_widgets_stops_at_depth_cap_on_real_cycle() {
	mut a := &VBox{}
	mut b := &VBox{}
	a.box.children << ChildEntry{
		widget: unsafe { b }
	}
	b.box.children << ChildEntry{
		widget: unsafe { a }
	}

	root_w := Widget(a)
	mut collector := &WalkCollector{}
	walk_widgets(root_w, fn [mut collector] (w &Widget) {
		collector.names << 'x'
	})
	assert collector.names.len == widget_tree_max_depth + 1
}

// ─── ListBox.hit_children(): диапазон видимых строк ────
//
// Регрессионные сценарии из ревью: формулы first/last в
// visible_row_range_v/_h — консервативный супернабор (см. коммент
// там же), и без дополнительной фильтрации по row_visible_v/_h
// hit_children() отдавал на одну строку/ячейку больше, чем реально
// красит draw() в этом кадре.

// Вертикальный режим, сценарий ревьюера: bounds {0,0,100,100}, 1
// колонка, 10 строк, scroll_y=0 → draw() красит строки 0..3
// (item_height=24), а старая реализация hit_children() отдавала
// 0..4 (лишняя, полностью съехавшая за vp.h строка 4).
fn test_list_box_hit_children_v_excludes_trailing_stale_row() {
	mut lb := &ListBox{
		bounds: Rect{0, 0, 100, 100}
	}
	lb.columns << LbColumn{
		width: 92
	}
	for i in 0 .. 10 {
		mut w := &Label{
			text: 'row${i}'
		}
		lb.rows << LbRow{
			cells: [LbCell{
				widget: unsafe { w }
			}]
		}
	}

	lw := Widget(lb)
	assert lw is HitTestable
	if lw is HitTestable {
		kids := lw.hit_children()
		assert kids.len == 4
		assert (kids[0] as Label).text == 'row0'
		assert (kids[3] as Label).text == 'row3'
	}
}

// Горизонтальный (filmstrip) режим, сценарий ревьюера: 5 строк,
// iw=120, vp.w=84 (bounds.w=92, pad=4) → draw() красит только h0,
// старая реализация hit_children() отдавала h0 и h1.
fn test_list_box_hit_children_h_excludes_trailing_stale_row() {
	mut lb := &ListBox{
		bounds:     Rect{0, 0, 92, 100}
		horizontal: true
		item_width: 120
	}
	for i in 0 .. 5 {
		mut w := &Label{
			text: 'h${i}'
		}
		lb.rows << LbRow{
			cells: [LbCell{
				widget: unsafe { w }
			}]
		}
	}

	lw := Widget(lb)
	assert lw is HitTestable
	if lw is HitTestable {
		kids := lw.hit_children()
		assert kids.len == 1
		assert (kids[0] as Label).text == 'h0'
	}
}

// Регрессия: 1 колонка, но 3 ячейки в строке (add_row_widgets создаёт
// max(columns.len, widgets.len) ячеек — см. list_box.v — так что это
// достижимо через публичный API без ручного конструирования LbRow).
// dispatch_to_row_widgets суммировал ширины колонок по индексу ячейки
// (`for k in 0 .. ci { cx += lb.columns[k].width }`), поэтому ci=2 при
// columns.len=1 читал lb.columns[1] и падал `index out of range`.
// Любое событие мыши должно просто пройти сквозь лишние ячейки, не
// уронив приложение.
//
// dispatch_to_row_widgets теперь клампит цикл по ячейкам к
// min(cells.len, columns.len) — тем же клампом, что уже использует
// hit_children() (widget_tree.v). Ячейка с ci >= columns.len не рисуется
// (draw() тоже ограничен columns.len) и получила бы вырожденный
// col_w=0/inner.w<0 из старого кода — событий она получать не должна.
// Поэтому событие теперь доходит только до w0 (единственная реальная
// колонка); w1/w2 — лишние ячейки без места в раскладке.
fn test_list_box_dispatch_v_survives_more_cells_than_columns() {
	mut lb := &ListBox{
		bounds: Rect{0, 0, 100, 100}
	}
	lb.add_column('Only', 92)

	mut w0 := &RecordingWidget{}
	mut w1 := &RecordingWidget{}
	mut w2 := &RecordingWidget{}
	lb.add_row_widgets([&Widget(w0), &Widget(w1), &Widget(w2)])
	assert lb.rows[0].cells.len == 3

	app := &App{}
	ev := GuiEvent{
		typ: .mouse_move
	}
	// Раньше здесь была паника; сейчас — просто обработка без падения,
	// и лишние ячейки (за пределами columns.len) событие не получают.
	handled := lb.dispatch_to_row_widgets(&ev, app)
	assert handled == false
	assert w0.handled_count == 1
	assert w1.handled_count == 0
	assert w2.handled_count == 0
}

// RecordingWidget — минимальный Widget, который только считает вызовы
// handle_event; используется ниже, чтобы напрямую проверить, каким
// строкам ListBox реально доставляет события (а не то, какие строки
// hit_children() СЧИТАЕТ видимыми — это разные пути с разной историей
// багов, см. test_list_box_dispatch_h_excludes_trailing_stale_row).
struct RecordingWidget {
mut:
	handled_count int
}

pub fn (mut w RecordingWidget) draw(mut ctx RenderContext) {}

pub fn (mut w RecordingWidget) handle_event(event &GuiEvent, app &App) bool {
	w.handled_count++
	return false
}

// Зеркало test_list_box_hit_children_h_excludes_trailing_stale_row, но
// по пути dispatch_to_row_widgets_h (события мыши), а не hit_children()
// (hit-testing). До этой правки dispatch_to_row_widgets_h не применял
// row_visible_h вовсе, поэтому row1 (входящий в консервативный диапазон
// visible_row_range_h, но реально невидимый) получал бы события мыши
// наравне с row0.
fn test_list_box_dispatch_h_excludes_trailing_stale_row() {
	mut lb := &ListBox{
		bounds:     Rect{0, 0, 92, 100}
		horizontal: true
		item_width: 120
	}
	mut recorders := []&RecordingWidget{}
	for _ in 0 .. 5 {
		mut w := &RecordingWidget{}
		recorders << w
		lb.rows << LbRow{
			cells: [LbCell{
				widget: unsafe { w }
			}]
		}
	}

	app := &App{}
	ev := GuiEvent{
		typ: .mouse_move
	}
	handled := lb.dispatch_to_row_widgets_h(&ev, app)
	assert handled == false // RecordingWidget.handle_event всегда возвращает false

	assert recorders[0].handled_count == 1
	for i in 1 .. 5 {
		assert recorders[i].handled_count == 0
	}
}

// Пустой список — hit_children() не должен паниковать ни в одном
// режиме (деление на item_height/eff_item_width защищено проверками
// <= 0, длина rows проверяется на каждом шаге).
fn test_list_box_hit_children_empty() {
	mut lb_v := &ListBox{
		bounds: Rect{0, 0, 100, 100}
	}
	lb_v.columns << LbColumn{
		width: 92
	}
	lw_v := Widget(lb_v)
	assert lw_v is HitTestable
	if lw_v is HitTestable {
		assert lw_v.hit_children().len == 0
	}

	mut lb_h := &ListBox{
		bounds:     Rect{0, 0, 92, 100}
		horizontal: true
	}
	lw_h := Widget(lb_h)
	assert lw_h is HitTestable
	if lw_h is HitTestable {
		assert lw_h.hit_children().len == 0
	}
}

// Скролл в конец (scroll_y == max_scroll()) — верхняя граница
// диапазона не должна вылезать за последнюю реальную строку и не
// должна пропускать её.
fn test_list_box_hit_children_v_scrolled_to_end() {
	mut lb := &ListBox{
		bounds: Rect{0, 0, 100, 100}
	}
	lb.columns << LbColumn{
		width: 92
	}
	for i in 0 .. 10 {
		mut w := &Label{
			text: 'row${i}'
		}
		lb.rows << LbRow{
			cells: [LbCell{
				widget: unsafe { w }
			}]
		}
	}
	lb.scroll_y = lb.max_scroll()

	lw := Widget(lb)
	assert lw is HitTestable
	if lw is HitTestable {
		kids := lw.hit_children()
		assert kids.len == 4
		assert (kids[0] as Label).text == 'row6'
		assert (kids[3] as Label).text == 'row9'
	}
}
