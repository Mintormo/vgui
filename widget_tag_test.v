module vgui

// Тег типа виджета (аудит 3.B), см. widget_tag.v.
//
// Тест защищает два инварианта разом:
//  1) у каждого типа виджета есть `type_tag` с верным значением по
//     умолчанию — забытое поле у нового виджета видно сразу;
//  2) поле объявлено ПЕРВЫМ, то есть лежит по смещению 0 и читается через
//     WidgetTagHeader, не зная типа. Если поле уедет вниз по структуре,
//     widget_type_tag вернёт чужие байты и тест упадёт.

struct TagCase {
	ptr  voidptr
	kind int
	name string
}

fn tag_cases() []TagCase {
	return [
		TagCase{voidptr(&Label{}), kind_label, 'Label'},
		TagCase{voidptr(&Button{}), kind_button, 'Button'},
		TagCase{voidptr(&VBox{}), kind_vbox, 'VBox'},
		TagCase{voidptr(&HBox{}), kind_hbox, 'HBox'},
		TagCase{voidptr(&Panel{}), kind_panel, 'Panel'},
		TagCase{voidptr(&Spacer{}), kind_spacer, 'Spacer'},
		TagCase{voidptr(&TextInput{}), kind_text_input, 'TextInput'},
		TagCase{voidptr(&CheckBox{}), kind_check_box, 'CheckBox'},
		TagCase{voidptr(&Slider{}), kind_slider, 'Slider'},
		TagCase{voidptr(&ProgressBar{}), kind_progress_bar, 'ProgressBar'},
		TagCase{voidptr(&Separator{}), kind_separator, 'Separator'},
		TagCase{voidptr(&ToggleSwitch{}), kind_toggle_switch, 'ToggleSwitch'},
		TagCase{voidptr(&Spinner{}), kind_spinner, 'Spinner'},
		TagCase{voidptr(&RadioButton{}), kind_radio_button, 'RadioButton'},
		TagCase{voidptr(&Spinbox{}), kind_spinbox, 'Spinbox'},
		TagCase{voidptr(&ComboBox{}), kind_combo_box, 'ComboBox'},
		TagCase{voidptr(&ImageView{}), kind_image_view, 'ImageView'},
		TagCase{voidptr(&ListBox{}), kind_list_box, 'ListBox'},
		TagCase{voidptr(&TabBox{}), kind_tab_box, 'TabBox'},
		TagCase{voidptr(&Accordion{}), kind_accordion, 'Accordion'},
		TagCase{voidptr(&Notification{}), kind_notification, 'Notification'},
		TagCase{voidptr(&Breadcrumbs{}), kind_breadcrumbs, 'Breadcrumbs'},
		TagCase{voidptr(&ColorPicker{}), kind_color_picker, 'ColorPicker'},
		TagCase{voidptr(&DatePicker{}), kind_date_picker, 'DatePicker'},
		TagCase{voidptr(&Splitter{}), kind_splitter, 'Splitter'},
		TagCase{voidptr(&DockArea{}), kind_dock_area, 'DockArea'},
		TagCase{voidptr(&CodeEditor{}), kind_code_editor, 'CodeEditor'},
		TagCase{voidptr(&MarkdownView{}), kind_markdown_view, 'MarkdownView'},
		TagCase{voidptr(&MenuButton{}), kind_menu_button, 'MenuButton'},
		TagCase{voidptr(&MenuItem{}), kind_menu_item, 'MenuItem'},
		TagCase{voidptr(&ContextMenu{}), kind_context_menu, 'ContextMenu'},
		TagCase{voidptr(&MenuBar{}), kind_menu_bar, 'MenuBar'},
		TagCase{voidptr(&PlotView{}), kind_plot_view, 'PlotView'},
		TagCase{voidptr(&PropertyGrid{}), kind_property_grid, 'PropertyGrid'},
		TagCase{voidptr(&Property{}), kind_property, 'Property'},
		TagCase{voidptr(&TableView{}), kind_table_view, 'TableView'},
		TagCase{voidptr(&TreeView{}), kind_tree_view, 'TreeView'},
		TagCase{voidptr(&TreeNode{}), kind_tree_node, 'TreeNode'},
		TagCase{voidptr(&NotificationManager{}), kind_notification_manager, 'NotificationManager'},
		TagCase{voidptr(&Stack{}), kind_stack, 'Stack'},
		TagCase{voidptr(&Centered{}), kind_centered, 'Centered'},
		TagCase{voidptr(&WindowTitleDrag{}), kind_window_title_drag, 'WindowTitleDrag'},
		TagCase{voidptr(&ScrollBox{}), kind_scroll_box, 'ScrollBox'},
		TagCase{voidptr(&TextArea{}), kind_text_area, 'TextArea'},
		TagCase{voidptr(&Badge{}), kind_badge, 'Badge'},
		TagCase{voidptr(&Calendar{}), kind_calendar, 'Calendar'},
		TagCase{voidptr(&Tooltip{}), kind_tooltip, 'Tooltip'},
		TagCase{voidptr(&GridLayout{}), kind_grid, 'GridLayout'},
		TagCase{voidptr(&DropZone{}), kind_drop_zone, 'DropZone'},
		TagCase{voidptr(&ImageBackground{}), kind_image_background, 'ImageBackground'},
		TagCase{voidptr(&Canvas{}), kind_canvas, 'Canvas'},
		TagCase{voidptr(&Icon{}), kind_icon, 'Icon'},
		TagCase{voidptr(&CurveEditor{}), kind_curve_editor, 'CurveEditor'},
		TagCase{voidptr(&ShortcutInput{}), kind_shortcut_input, 'ShortcutInput'},
	]
}

fn test_every_widget_carries_its_tag() {
	cases := tag_cases()
	assert cases.len == 54
	for c in cases {
		got := widget_type_tag(c.ptr)
		assert got == c.kind, '${c.name}: тег ${got}, ожидался ${c.kind}'
		assert widget_tag_matches(c.ptr, c.kind)
	}
}

fn test_tags_are_unique() {
	mut seen := map[int]string{}
	for c in tag_cases() {
		if prev := seen[c.kind] {
			assert false, 'kind ${c.kind} занят дважды: ${prev} и ${c.name}'
		}
		seen[c.kind] = c.name
	}
}

fn test_nil_has_no_tag() {
	assert widget_type_tag(unsafe { nil }) == 0
	assert !widget_tag_matches(unsafe { nil }, kind_label)
}

// Тег переживает реальные фабрики и мутацию полей: значение по умолчанию
// проставляется при создании, дальше его никто не трогает.
fn test_tag_survives_factories_and_mutation() {
	mut lbl := label('hello')
	assert widget_type_tag(voidptr(lbl)) == kind_label
	lbl.text = 'другой текст'
	lbl.bounds = Rect{1, 2, 3, 4}
	assert widget_type_tag(voidptr(lbl)) == kind_label

	mut box := create_vbox_fill()
	assert widget_type_tag(voidptr(box)) == kind_vbox
	box.add(lbl, flex: 1)
	assert widget_type_tag(voidptr(box)) == kind_vbox
	assert widget_type_tag(voidptr(lbl)) == kind_label
}
