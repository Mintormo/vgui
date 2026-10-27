module vgui

import os

// Снапшоты виджетов, которые раньше не снимались: содержимое модальных
// диалогов DatePicker и ColorPicker, Calendar и открытое контекстное меню.
//
// Календари зависят от даты («сегодня» подсвечено), поэтому дата подменяется
// (set_today_override, clock.v). Диалоги выбора даты и цвета крутят свой
// модальный цикл - в тесте показывается только их содержимое
// (dp_dialog_content / cp_dialog_content) в обычном окне TestUi: ровно то, что
// пользователь видит внутри диалога.
//
// Перезаписать эталоны: VGUI_UPDATE_SNAPSHOTS=1 v test snapshot_pickers_test.v

const pickers_snapshot_dir = os.join_path(@VMODROOT, 'testdata', 'snapshots')

// pickers_snap рисует сцену build в обеих темах и сверяет с эталонами
// <name>_light.png / <name>_dark.png. act (может быть nil) - действие
// пользователя перед снимком.
fn pickers_snap(name string, w int, h int, build fn () &Widget, act fn (mut t TestUi)) ! {
	set_today_override(2026, 10, 14)
	defer {
		set_today_override(0, 0, 0)
	}
	for theme_name, theme in {
		'light': light_theme()
		'dark':  dark_theme()
	} {
		mut t := new_test_ui(width: w, height: h, theme: theme)!
		t.add(build())
		if act != unsafe { nil } {
			act(mut t)
		}
		t.redraw()
		t.match_snapshot(os.join_path(pickers_snapshot_dir, '${name}_${theme_name}.png')) or {
			t.close()
			return err
		}
		t.close()
	}
}

fn scene_date_dialog() &Widget {
	mut state := &DpState{
		year:  2026
		month: 10
		day:   21
	}
	return dp_dialog_content(mut state)
}

fn scene_color_dialog() &Widget {
	initial := Color{40, 140, 220, 200}
	h, s, v := cp_rgb_to_hsv(initial.r, initial.g, initial.b)
	mut state := &CpState{
		original:   Color{220, 60, 40, 255}
		current:    initial
		hue:        h
		sat:        s
		val:        v
		alpha:      f32(initial.a) / 255.0
		show_alpha: true
	}
	return cp_dialog_content(mut state)
}

fn scene_calendar_and_fields() &Widget {
	mut cal := calendar_new()
	cal.set_date(2026, 10, 21)
	mut row := create_hbox_fill()
	row.set_spacing(8)
	row.add(date_picker_ymd(2026, 10, 21), flex: 1)
	row.add(color_picker_with_color(Color{40, 140, 220, 255}), flex: 1)
	mut col := create_vbox_fill()
	col.set_padding(8)
	col.set_spacing(8)
	col.add(row)
	col.add(cal, flex: 1)
	return col
}

fn test_snapshot_date_dialog() {
	pickers_snap('dialog_date', 300, 300, scene_date_dialog, unsafe { nil })!
}

fn test_snapshot_color_dialog() {
	pickers_snap('dialog_color', 480, 380, scene_color_dialog, unsafe { nil })!
}

fn test_snapshot_calendar() {
	pickers_snap('calendar', 320, 320, scene_calendar_and_fields, unsafe { nil })!
}

// Контекстное меню открывается настоящим правым кликом по цели (attach +
// add_widget - нужны оба, иначе ПКМ не ловится).
fn test_snapshot_context_menu() {
	pickers_snap('popup_context_menu', 320, 220, fn () &Widget {
		mut target := panel()
		return target
	}, fn (mut t TestUi) {
		target := t.win.widgets[0]
		mut cm := context_menu()
		cm.add(menu_action_lucide('Копировать', 'copy'))
		cm.add(menu_action('Вставить'))
		cm.add(menu_separator())
		cm.add(menu_checkbox('Перенос строк', true))
		mut sub := menu_submenu('Ещё')
		sub.add(menu_action('Пункт'))
		cm.add(sub)
		cm.attach(target)
		t.win.add_widget(cm)
		t.frame()
		t.right_click(40, 40)
		t.move(60, 52) // наведение на первый пункт
	})!
}
