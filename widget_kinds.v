module vgui

// Константы kind виджетов - номер типа, который биндинги передают вместе с
// указателем на виджет (C-ABI, vgui-capi). Первое поле каждой структуры
// виджета - `type_tag int = kind_<name>` (см. widget_tag.v). Номера - часть
// ABI: не перенумеровывайте занятые, новые берите следующими по порядку.
//
// Использование: `type_tag int = kind_<name>` в структуре виджета (widget_tag.v);
// ветки vgui_get_kind() / vgui_resolve_widget() / vgui_destroy() в vgui-capi;
// на стороне Python те же числа лежат в `_kind` классов vguipy (должны совпадать).
// Нумерация шла по мере появления виджетов (1-4 базовые, дальше по истории), поэтому
// порядок не отражает смысловых групп. Не виджеты-Widget, а вспомогательные типы
// (MenuItem=29, Property=34, TreeNode=37) тоже имеют kind: их добавляют во владельца.
pub const kind_label = 1
pub const kind_button = 2
pub const kind_vbox = 3
pub const kind_hbox = 4
pub const kind_panel = 5
pub const kind_spacer = 6
pub const kind_text_input = 7
pub const kind_check_box = 8
pub const kind_slider = 9
pub const kind_progress_bar = 10
pub const kind_separator = 11
pub const kind_toggle_switch = 12
pub const kind_spinner = 13
pub const kind_radio_button = 14
pub const kind_spinbox = 15
pub const kind_combo_box = 16
pub const kind_image_view = 17
pub const kind_list_box = 18
pub const kind_tab_box = 19
pub const kind_accordion = 20
pub const kind_notification = 21
pub const kind_breadcrumbs = 22
pub const kind_color_picker = 23
pub const kind_date_picker = 24
pub const kind_splitter = 25
pub const kind_code_editor = 26
pub const kind_markdown_view = 27
pub const kind_menu_button = 28
pub const kind_menu_item = 29
pub const kind_context_menu = 30
pub const kind_menu_bar = 31
pub const kind_plot_view = 32
pub const kind_property_grid = 33
pub const kind_property = 34
pub const kind_table_view = 35
pub const kind_tree_view = 36
pub const kind_tree_node = 37
pub const kind_notification_manager = 38
pub const kind_stack = 39
pub const kind_centered = 40
pub const kind_window_title_drag = 41
pub const kind_scroll_box = 42
pub const kind_text_area = 43
pub const kind_badge = 44
pub const kind_calendar = 45
pub const kind_tooltip = 46
pub const kind_grid = 47
pub const kind_drop_zone = 48
pub const kind_image_background = 49
pub const kind_canvas = 50
pub const kind_icon = 51
pub const kind_curve_editor = 52
pub const kind_shortcut_input = 53
pub const kind_dock_area = 54
