module vgui

// ═══════════════════════════════════════════════════════
// Feature flags for conditional widget inclusion
//
// By default ALL widgets are enabled.
// To disable a widget, compile with -d flag:
//
//   v -d vgui_no_checkbox -d vgui_no_radio_button .
//
// ─── Available flags (full list) ───────────────────────
//
// Basic input widgets:
//   -d vgui_no_button
//   -d vgui_no_label
//   -d vgui_no_text_input
//   -d vgui_no_checkbox
//   -d vgui_no_radio_button
//   -d vgui_no_toggle_switch
//   -d vgui_no_slider
//   -d vgui_no_spinbox
//   -d vgui_no_progress_bar
//   -d vgui_no_spinner
//
// Selection widgets:
//   -d vgui_no_combo_box
//   -d vgui_no_list_box
//   -d vgui_no_tree_view
//   -d vgui_no_table_view
//
// Layout widgets:
//   -d vgui_no_tab_box
//   -d vgui_no_scroll_box
//   -d vgui_no_splitter
//   -d vgui_no_separator
//   -d vgui_no_accordion
//
// Menu / navigation:
//   -d vgui_no_menu
//   -d vgui_no_menu_button
//   -d vgui_no_breadcrumbs
//
// Dialogs / pickers:
//   -d vgui_no_color_picker
//   -d vgui_no_date_picker
//   -d vgui_no_file_dialog
//
// Display widgets:
//   -d vgui_no_image_view
//   -d vgui_no_markdown_view
//   -d vgui_no_code_editor
//   -d vgui_no_plot_view
//   -d vgui_no_property_grid
//   -d vgui_no_tooltip
//   -d vgui_no_notification
//
// Window features:
//   -d vgui_no_window_title_drag
//   -d vgui_no_borderless
//   -d vgui_no_image_export
//
// Subsystems:
//   -d vgui_no_ui_builder
//   -d vgui_no_syntax_highlighter
//   -d vgui_no_encoding
//   -d vgui_no_i18n
//   -d vgui_no_hotkeys
//
// Core widgets (always included, cannot be disabled):
//   HBox, VBox, Panel, Stack, Spacer, Centered, ScrollBox base
//   FocusManager, Theme, RenderContext, Color, Rect
// ═══════════════════════════════════════════════════════

// Как это работает на самом деле: каждый флаг -d vgui_no_<имя> лишь меняет результат функции
// has_<имя>() ниже ($if <флаг> ? {...} - проверка на этапе компиляции, константа true/false).
// Сам код виджетов из сборки НЕ исключается - все исходники модуля компилируются всегда.
// Флаги используются там, где код явно спрашивает has_*() (например, ui_builder.v при создании
// виджета по имени типа) и в print_enabled_features(). Остальная библиотека на них не смотрит.
// Все has_*() ниже однотипны: true, если флаг отключения не задан.

// ─── Basic input widgets ───────────────────────────────

pub fn has_button() bool {
	return $if vgui_no_button ? { false } $else { true }
}

pub fn has_label() bool {
	return $if vgui_no_label ? { false } $else { true }
}

pub fn has_text_input() bool {
	return $if vgui_no_text_input ? { false } $else { true }
}

pub fn has_checkbox() bool {
	return $if vgui_no_checkbox ? { false } $else { true }
}

pub fn has_radio_button() bool {
	return $if vgui_no_radio_button ? { false } $else { true }
}

pub fn has_toggle_switch() bool {
	return $if vgui_no_toggle_switch ? { false } $else { true }
}

pub fn has_slider() bool {
	return $if vgui_no_slider ? { false } $else { true }
}

pub fn has_spinbox() bool {
	return $if vgui_no_spinbox ? { false } $else { true }
}

pub fn has_progress_bar() bool {
	return $if vgui_no_progress_bar ? { false } $else { true }
}

pub fn has_spinner() bool {
	return $if vgui_no_spinner ? { false } $else { true }
}

// ─── Selection widgets ─────────────────────────────────

pub fn has_combo_box() bool {
	return $if vgui_no_combo_box ? { false } $else { true }
}

pub fn has_list_box() bool {
	return $if vgui_no_list_box ? { false } $else { true }
}

pub fn has_tree_view() bool {
	return $if vgui_no_tree_view ? { false } $else { true }
}

pub fn has_table_view() bool {
	return $if vgui_no_table_view ? { false } $else { true }
}

// ─── Layout widgets ────────────────────────────────────

pub fn has_tab_box() bool {
	return $if vgui_no_tab_box ? { false } $else { true }
}

pub fn has_scroll_box() bool {
	return $if vgui_no_scroll_box ? { false } $else { true }
}

pub fn has_splitter() bool {
	return $if vgui_no_splitter ? { false } $else { true }
}

pub fn has_separator() bool {
	return $if vgui_no_separator ? { false } $else { true }
}

pub fn has_accordion() bool {
	return $if vgui_no_accordion ? { false } $else { true }
}

// ─── Menu / navigation ─────────────────────────────────

pub fn has_menu() bool {
	return $if vgui_no_menu ? { false } $else { true }
}

pub fn has_menu_button() bool {
	return $if vgui_no_menu_button ? { false } $else { true }
}

pub fn has_breadcrumbs() bool {
	return $if vgui_no_breadcrumbs ? { false } $else { true }
}

// ─── Dialogs / pickers ─────────────────────────────────

pub fn has_color_picker() bool {
	return $if vgui_no_color_picker ? { false } $else { true }
}

pub fn has_date_picker() bool {
	return $if vgui_no_date_picker ? { false } $else { true }
}

pub fn has_file_dialog() bool {
	return $if vgui_no_file_dialog ? { false } $else { true }
}

// ─── Display widgets ───────────────────────────────────

pub fn has_image_view() bool {
	return $if vgui_no_image_view ? { false } $else { true }
}

pub fn has_markdown_view() bool {
	return $if vgui_no_markdown_view ? { false } $else { true }
}

pub fn has_code_editor() bool {
	return $if vgui_no_code_editor ? { false } $else { true }
}

pub fn has_plot_view() bool {
	return $if vgui_no_plot_view ? { false } $else { true }
}

pub fn has_property_grid() bool {
	return $if vgui_no_property_grid ? { false } $else { true }
}

pub fn has_tooltip() bool {
	return $if vgui_no_tooltip ? { false } $else { true }
}

pub fn has_notification() bool {
	return $if vgui_no_notification ? { false } $else { true }
}

// ─── Window features ───────────────────────────────────

pub fn has_window_title_drag() bool {
	return $if vgui_no_window_title_drag ? { false } $else { true }
}

pub fn has_borderless() bool {
	return $if vgui_no_borderless ? { false } $else { true }
}

pub fn has_image_export() bool {
	return $if vgui_no_image_export ? { false } $else { true }
}

// ─── Subsystems ────────────────────────────────────────

pub fn has_ui_builder() bool {
	return $if vgui_no_ui_builder ? { false } $else { true }
}

pub fn has_syntax_highlighter() bool {
	return $if vgui_no_syntax_highlighter ? { false } $else { true }
}

pub fn has_encoding() bool {
	return $if vgui_no_encoding ? { false } $else { true }
}

pub fn has_i18n() bool {
	return $if vgui_no_i18n ? { false } $else { true }
}

pub fn has_hotkeys() bool {
	return $if vgui_no_hotkeys ? { false } $else { true }
}

// ─── Diagnostic helper ─────────────────────────────────

// print_enabled_features печатает в stdout список включённых возможностей (для отладки сборки).
pub fn print_enabled_features() {
	println('vgui enabled features:')
	if has_button() { println('  ✓ button') }
	if has_label() { println('  ✓ label') }
	if has_text_input() { println('  ✓ text_input') }
	if has_checkbox() { println('  ✓ checkbox') }
	if has_radio_button() { println('  ✓ radio_button') }
	if has_toggle_switch() { println('  ✓ toggle_switch') }
	if has_slider() { println('  ✓ slider') }
	if has_spinbox() { println('  ✓ spinbox') }
	if has_progress_bar() { println('  ✓ progress_bar') }
	if has_spinner() { println('  ✓ spinner') }
	if has_combo_box() { println('  ✓ combo_box') }
	if has_list_box() { println('  ✓ list_box') }
	if has_tree_view() { println('  ✓ tree_view') }
	if has_table_view() { println('  ✓ table_view') }
	if has_tab_box() { println('  ✓ tab_box') }
	if has_scroll_box() { println('  ✓ scroll_box') }
	if has_splitter() { println('  ✓ splitter') }
	if has_separator() { println('  ✓ separator') }
	if has_accordion() { println('  ✓ accordion') }
	if has_menu() { println('  ✓ menu') }
	if has_menu_button() { println('  ✓ menu_button') }
	if has_breadcrumbs() { println('  ✓ breadcrumbs') }
	if has_color_picker() { println('  ✓ color_picker') }
	if has_date_picker() { println('  ✓ date_picker') }
	if has_file_dialog() { println('  ✓ file_dialog') }
	if has_image_view() { println('  ✓ image_view') }
	if has_markdown_view() { println('  ✓ markdown_view') }
	if has_code_editor() { println('  ✓ code_editor') }
	if has_plot_view() { println('  ✓ plot_view') }
	if has_property_grid() { println('  ✓ property_grid') }
	if has_tooltip() { println('  ✓ tooltip') }
	if has_notification() { println('  ✓ notification') }
	if has_window_title_drag() { println('  ✓ window_title_drag') }
	if has_borderless() { println('  ✓ borderless') }
	if has_image_export() { println('  ✓ image_export') }
	if has_ui_builder() { println('  ✓ ui_builder') }
	if has_syntax_highlighter() { println('  ✓ syntax_highlighter') }
	if has_encoding() { println('  ✓ encoding') }
	if has_i18n() { println('  ✓ i18n') }
	if has_hotkeys() { println('  ✓ hotkeys') }
}
