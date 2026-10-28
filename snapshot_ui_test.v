module vgui

import os

// Снапшоты рендера с действиями: состояния наведения, нажатия и фокуса,
// открытые попапы, стили CSS. Дополняют галереи snapshot_test.v (там - сцены
// без ввода и HiDPI).
//
// Сцена описывается разметкой .vui (виджеты для действий находятся по #id), к ней
// по желанию - таблица стилей и действие пользователя (наведение, клик, Tab...).
// Перед сверкой с эталоном каждая сцена проходит ещё одну проверку: кадр,
// полученный ЧАСТИЧНЫМИ перерисовками после действия (как в живом окне, где
// перерисовываются только dirty-области), обязан совпадать с полной
// перерисовкой. Именно так ловятся баги вида «наведение стёрло рамку соседа»
// (PROJECT.md, «Инвалидация и dirty regions»): эталон, снятый полной
// перерисовкой, их бы не увидел. При расхождении рядом с эталоном кладётся
// <имя>.partial.png - кадр после частичных перерисовок.
//
// В сценах нет ничего, что зависит от времени: фокус в полях ввода (мигающий
// курсор) не используется, а у подсказки часы подменены (Window.tip_clock_ms).
//
// Перезаписать эталоны: VGUI_UPDATE_SNAPSHOTS=1 v test snapshot_ui_test.v

const ui_snapshot_dir = os.join_path(@VMODROOT, 'testdata', 'snapshots')

// UiSnap — одна сцена: разметка, размер окна, таблица стилей и действие.
struct UiSnap {
	name string
	vui  string
	w    int = 360
	h    int = 200
	css  string // текст таблицы стилей ('' - без стилей)
	// act - действие перед снимком (nil - без действия). Мышь до него уже стоит
	// в углу окна: первое движение мыши в окне даёт полный кадр, а проверить
	// нужно частичный.
	act fn (mut t TestUi, ui &Ui) = unsafe { nil }
}

// snap_ui рисует сцену в светлой и тёмной теме: разбор разметки, действие,
// проверка «частичные перерисовки = полная», сверка с эталоном <name>_<тема>.png.
fn snap_ui(s UiSnap) ! {
	for theme_name, theme in {
		'light': light_theme()
		'dark':  dark_theme()
	} {
		mut t := new_test_ui(width: s.w, height: s.h, theme: theme)!
		snap_ui_theme(mut t, s, theme_name) or {
			t.close()
			return err
		}
		t.close()
	}
}

fn snap_ui_theme(mut t TestUi, s UiSnap, theme_name string) ! {
	if s.css.len > 0 {
		t.app.set_stylesheet(parse_stylesheet(s.css, '${s.name}.css')!)
	}
	ui := ui_parse(s.vui, '${s.name}.vui')!
	t.add(ui.root)
	t.redraw()
	// мышь - в угол окна: дальше движения мыши дают частичные кадры
	t.move(1, 1)
	t.settle(120)
	if !isnil(s.act) {
		s.act(mut t, ui)
		t.settle(120)
	}
	path := os.join_path(ui_snapshot_dir, '${s.name}_${theme_name}.png')
	partial := t.capture()
	t.redraw()
	t.settle(120)
	full := t.capture()
	d := partial.diff(full, 0)
	if d.count > 0 {
		partial_path := path.replace('.png', '.partial.png')
		partial.save_png(partial_path) or {}
		return error('${s.name} (${theme_name}): кадр после частичных перерисовок отличается от полной перерисовки на ${d.count} пикс. (наибольшая разница ${d.max_delta}) - см. ${partial_path}')
	}
	match_frame_snapshot(&full, path, SnapshotOpts{})!
}

// center — центр виджета #id из разметки.
fn widget_center_by_id(t &TestUi, ui &Ui, id string) (f32, f32) {
	w := ui.widget(id) or { panic('в сцене нет #${id}') }
	return t.center_of(w)
}

// ─── Состояния: наведение, нажатие, фокус ───────────────

const states_vui = '
vbox pad=12 gap=10
  hbox gap=8
    button "Обычная" #plain
    button "Наведена" #hover
    button "Акцент" style=accent #accent
  input "Поле под кнопками" #field
  hbox gap=8
    checkbox "Флажок" checked #check
    spacer flex=1
    toggle "Тумблер" #toggle
'

fn test_snapshot_hover_button() {
	snap_ui(
		name: 'state_hover'
		vui:  states_vui
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'hover')
			t.move(x, y)
		}
	)!
}

// Подсказка по полю tooltip (tooltip_manager.v): наведение, срок по
// подменённым часам. Подсказка ряда видна над подписью без своей подсказки.
fn test_snapshot_tooltip() {
	snap_ui(
		name: 'tooltip'
		vui:  '
vbox pad=12 gap=10
  hbox gap=8 tooltip="Подсказка всего ряда"
    label "Яркость" #lbl
    button "Сохранить" tooltip="Сохранить снимок"
'
		act:  fn (mut t TestUi, ui &Ui) {
			t.win.tip_clock_ms = 1000
			x, y := widget_center_by_id(t, ui, 'lbl')
			t.move(x, y)
			t.frame()
			t.win.tip_clock_ms += 1000
			t.frame()
			assert t.win.tips.showing
		}
	)!
}

// Наведение на тумблер под полем ввода - тот самый случай, где частичная
// перерисовка стирала нижнюю рамку поля (clip_edge_test.v).
fn test_snapshot_hover_toggle_under_input() {
	snap_ui(
		name: 'state_hover_toggle'
		vui:  states_vui
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'toggle')
			t.move(x, y)
		}
	)!
}

fn test_snapshot_pressed_button() {
	snap_ui(
		name: 'state_pressed'
		vui:  states_vui
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'accent')
			t.move(x, y)
			t.press(x, y) // без отпускания: кнопка остаётся нажатой
		}
	)!
}

// Фокус с клавиатуры: клик в поле, затем Tab - фокус уходит на следующий
// виджет (флажок) с кольцом фокуса. Курсор поля после Tab не мигает в кадре.
// Сразу Tab не годится: без фокуса его никто не обрабатывает (ROADMAP,
// «Доступность»: полная навигация с клавиатуры).
fn test_snapshot_keyboard_focus() {
	snap_ui(
		name: 'state_focus'
		vui:  states_vui
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'field')
			t.click(x, y)
			t.move(1, 1)
			t.key(9, 0) // Tab
		}
	)!
}

const list_vui = '
vbox pad=12
  list #files flex=1 selected=1
    column "Имя" width=160
    column "Размер" width=80
    item "README.md" "4 КБ" icon=file-text
    item "logo.png" "120 КБ" icon=image
    item "main.v" "12 КБ" icon=file-code
'

// Наведённая строка списка рядом с выделенной.
fn test_snapshot_hover_list_row() {
	snap_ui(
		name: 'state_hover_row'
		vui:  list_vui
		h:    160
		act:  fn (mut t TestUi, ui &Ui) {
			w := ui.widget('files') or { panic('нет #files') }
			b := get_widget_bounds(w)
			// третья строка: под заголовком и двумя строками
			t.move(b.x + 60, b.y + b.h * 0.5 + 20)
		}
	)!
}

// ─── Открытые попапы ────────────────────────────────────

fn test_snapshot_combo_open() {
	snap_ui(
		name: 'popup_combo'
		vui:  '
vbox pad=12 gap=8
  hbox gap=8
    combo #city selected=1 min=180
      item "Москва" icon=map-pin
      item "Казань"
      item "Томилино"
    spacer flex=1
  label "Под выпадающим списком"
'
		h:    200
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'city')
			t.click(x, y)
		}
	)!
}

fn test_snapshot_menubar_open() {
	snap_ui(
		name: 'popup_menu'
		vui:  '
vbox
  menubar #bar
    menu "Файл"
      item "Открыть" icon=folder-open shortcut=Ctrl+O
      check "Перенос строк" checked
      separator
      submenu "Экспорт"
        item "PDF"
      item "Выход" disabled
    menu "Правка"
      item "Копировать"
  label "Содержимое окна" flex=1
'
		h:    220
		act:  fn (mut t TestUi, ui &Ui) {
			w := ui.widget('bar') or { panic('нет #bar') }
			b := get_widget_bounds(w)
			// первый пункт строки меню - «Файл» у левого края
			t.click(b.x + 20, b.y + b.h * 0.5)
		}
	)!
}

// ─── Стили CSS ──────────────────────────────────────────

// Галерея со стилями: корневые правила и переменные, класс, #id, правило с
// предком, состояние :hover (мышь на кнопке #save) и :selected у списка.
fn test_snapshot_css_styles() {
	snap_ui(
		name: 'css_styles'
		w:    420
		h:    240
		css:  '
:root { --brand: #7c3aed; accent-color: var(--brand); border-radius: 10; }
.side { background: #1f1b2e; color: #e9e4ff; }
.side list { background: #1f1b2e; color: #e9e4ff; border-color: #3b3355; header-background: #2d2742; header-color: #e9e4ff; }
.side list:selected { background: var(--brand); color: #ffffff; }
.card { background: rgba(124, 58, 237, 0.08); }
.danger { background: #dc2626; color: #ffffff; border-color: #b91c1c; }
#save { background: var(--brand); color: #ffffff; }
#save:hover { background: #a78bfa; }
toggle:checked { background: var(--brand); }
progress { fill-color: #16a34a; }
'
		vui:  '
hbox
  vbox .side pad=8 gap=6 max=150
    label "Проекты" bold
    list flex=1 selected=0
      column "Имя"
      item "vgui"
      item "vraw"
  vbox pad=12 gap=10 flex=1
    vbox .card pad=10 gap=8
      input "Поле в карточке"
      hbox gap=8
        checkbox "Флажок" checked
        spacer flex=1
        toggle "Вкл" on
    progress value=65
    hbox gap=8
      button "Удалить" .danger
      spacer flex=1
      button "Сохранить" #save
'
		act:  fn (mut t TestUi, ui &Ui) {
			x, y := widget_center_by_id(t, ui, 'save')
			t.move(x, y)
		}
	)!
}
