module vgui

// ═══════════════════════════════════════════════════════
// css_props — что значит каждое CSS-свойство: в какие поля Theme оно пишет
// ═══════════════════════════════════════════════════════
//
// Часть подсистемы стилей (css.v - разбор, css_apply.v - применение; модель -
// PROJECT.md, «Стили CSS»). Здесь три вещи:
//   1. имена типов элементов в селекторах (те же, что в .vui) <-> kind_* виджетов;
//   2. таблица css_prop_table: «тип:состояние/свойство» -> поля Theme;
//   3. запись значения в поле Theme по его имени (через $for по полям структуры),
//      с проверкой типа: цвет в поле Color, число в f32/int.
//
// Поиск свойства (css_lookup_fields): сначала строка своего типа элемента
// (`button:hover/background`), затем общая для всех (`*:hover/background`). Так
// `color` у метки - это text_primary (общая строка), а у вкладок - tab_inactive_text
// (своя строка перекрывает общую).
//
// Одно свойство может писать в несколько полей. Например, `background` у кнопки
// пишет и button_bg, и accent: кнопка со style=accent рисуется акцентным цветом,
// и без этого `.x { background }` на такой кнопке не сработал бы. Побочного
// эффекта нет: изменённая тема действует только на поддерево самой кнопки.
//
// Добавить свойство - строка в css_prop_table (тест css_test.v проверяет, что все
// поля из таблицы существуют в Theme) и строка в таблице PROJECT.md, «Стили CSS».

// css_kind_by_name — типы элементов в селекторах. Имена как в .vui, где элемент
// там есть; для остальных - короткое имя виджета без подчёркиваний.
const css_kind_by_name = {
	'label':        kind_label
	'button':       kind_button
	'vbox':         kind_vbox
	'hbox':         kind_hbox
	'panel':        kind_panel
	'spacer':       kind_spacer
	'input':        kind_text_input
	'checkbox':     kind_check_box
	'slider':       kind_slider
	'progress':     kind_progress_bar
	'separator':    kind_separator
	'toggle':       kind_toggle_switch
	'spinner':      kind_spinner
	'radio':        kind_radio_button
	'spinbox':      kind_spinbox
	'combo':        kind_combo_box
	'image':        kind_image_view
	'list':         kind_list_box
	'tabs':         kind_tab_box
	'accordion':    kind_accordion
	'breadcrumbs':  kind_breadcrumbs
	'colorpicker':  kind_color_picker
	'datepicker':   kind_date_picker
	'split':        kind_splitter
	'code':         kind_code_editor
	'markdown':     kind_markdown_view
	'menubutton':   kind_menu_button
	'menubar':      kind_menu_bar
	'plot':         kind_plot_view
	'propertygrid': kind_property_grid
	'table':        kind_table_view
	'tree':         kind_tree_view
	'stack':        kind_stack
	'centered':     kind_centered
	'scroll':       kind_scroll_box
	'textarea':     kind_text_area
	'badge':        kind_badge
	'calendar':     kind_calendar
	'grid':         kind_grid
	'dropzone':     kind_drop_zone
	'canvas':       kind_canvas
	'icon':         kind_icon
	'curve':        kind_curve_editor
	'shortcut':     kind_shortcut_input
}

// css_max_kind — наибольший kind_* (размер массивов fields_by_kind).
const css_max_kind = kind_shortcut_input

// css_name_by_kind — обратная таблица: kind -> имя типа (пусто - в CSS нет имени).
const css_name_by_kind = css_build_name_by_kind()

fn css_build_name_by_kind() []string {
	mut names := []string{len: css_max_kind + 1}
	for name, kind in css_kind_by_name {
		names[kind] = name
	}
	return names
}

// css_pseudo_classes — допустимые состояния. :active - синоним :pressed
// (нормализуется при разборе, css.v parse_compound).
const css_pseudo_classes = ['hover', 'pressed', 'focus', 'selected', 'checked', 'disabled']

// css_fill_containers — контейнеры без своего цвета фона в теме: `background` у
// них не поле Theme, а заливка прямоугольника перед отрисовкой (css_apply.v).
const css_fill_containers = ['vbox', 'hbox', 'grid', 'scroll', 'stack', 'centered']

// css_fill_field — особое «поле» для заливки контейнера (не поле Theme).
const css_fill_field = '@fill'

// css_padding_field / css_gap_field — особые «поля» отступов: не поля Theme
// (не наследуются поддеревом, как и в CSS), а CssBox текущего виджета
// (css_apply.v): его читают measure/arrange/draw самого виджета.
const css_padding_field = '@padding'
const css_gap_field = '@gap'

// css_layout_fields — поля, от которых зависит раскладка: объявление с ними
// применяют и measure/arrange/события (CssDecl.layout), а не только draw.
const css_layout_fields = ['font_size', 'font_bold', 'font_italic', 'font_mono', css_padding_field,
	css_gap_field]

// css_font_keywords — допустимые слова свойств font-weight/-style/-family:
// поле Theme -> слово -> включить начертание (true) или снять заданное выше (false).
const css_font_keywords = {
	'font_bold':   {
		'bold':   true
		'normal': false
	}
	'font_italic': {
		'italic':  true
		'oblique': true
		'normal':  false
	}
	'font_mono':   {
		'monospace':  true
		'mono':       true
		'sans-serif': false
		'sans':       false
		'normal':     false
	}
}

// css_prop_table — «тип:состояние/свойство» -> поля Theme. Тип `*` - общая
// строка для всех; `root` - только для `:root`; menu/tooltip/notification/
// dropdown - корневые правила для попапов (css.v, css_root_types).
const css_prop_table = {
	// ── общие для любого элемента ──
	'*:/color':                          ['text_primary']
	'*:disabled/color':                  ['text_disabled']
	'*:/secondary-color':                ['text_secondary']
	'*:/placeholder-color':              ['text_hint']
	'*:/accent-color':                   ['accent']
	'*:hover/accent-color':              ['accent_hover']
	'*:pressed/accent-color':            ['accent_pressed']
	'*:/accent-text-color':              ['accent_text']
	'*:/border-radius':                  ['border_radius']
	'*:/focus-ring-color':               ['focus_ring_color']
	'*:/focus-ring-width':               ['focus_ring_width']
	'*:/scrollbar-color':                ['scrollbar_thumb']
	'*:hover/scrollbar-color':           ['scrollbar_hover']
	'*:pressed/scrollbar-color':         ['scrollbar_drag']
	'*:/scrollbar-track-color':          ['scrollbar_bg']
	'*:/success-color':                  ['success']
	'*:/warning-color':                  ['warning']
	'*:/error-color':                    ['error_color']
	'*:/info-color':                     ['info']
	'*:/shadow-color':                   ['shadow_color']
	// шрифт - у любого элемента и в :root (наследуется поддеревом)
	'*:/font-size':                      ['font_size']
	'*:/font-weight':                    ['font_bold']
	'*:/font-style':                     ['font_italic']
	'*:/font-family':                    ['font_mono']
	// ── :root — общая тема окна ──
	'root:/background':                  ['bg']
	'root:/surface-color':               ['surface']
	'root:/panel-background':            ['panel_bg']
	'root:/border-color':                ['border']
	'root:/input-background':            ['input_bg']
	'root:/input-border-color':          ['input_border']
	'root:/modal-backdrop-color':        ['modal_backdrop_color']
	// ── кнопки ──
	'button:/background':                ['button_bg', 'accent', 'error_color', 'success']
	'button:hover/background':           ['button_hover', 'accent_hover']
	'button:pressed/background':         ['button_pressed', 'accent_pressed']
	'button:disabled/background':        ['button_disabled_bg']
	'button:/color':                     ['button_text', 'accent_text', 'text_primary']
	'button:/border-color':              ['button_border']
	'button:disabled/border-color':      ['button_disabled_border']
	'menubutton:/background':            ['button_bg', 'accent']
	'menubutton:hover/background':       ['button_hover', 'accent_hover']
	'menubutton:pressed/background':     ['button_pressed', 'accent_pressed']
	'menubutton:/color':                 ['button_text', 'accent_text', 'text_primary']
	'menubutton:/border-color':          ['button_border']
	// ── поля ввода ──
	'input:/background':                 ['input_bg']
	'input:/border-color':               ['input_border']
	'input:focus/border-color':          ['input_focus']
	'textarea:/background':              ['input_bg']
	'textarea:/border-color':            ['input_border']
	'textarea:focus/border-color':       ['input_focus']
	'spinbox:/background':               ['spinbox_bg', 'input_bg']
	'spinbox:/border-color':             ['spinbox_border', 'input_border']
	'spinbox:/color':                    ['spinbox_text', 'text_primary']
	'spinbox:/button-background':        ['spinbox_btn_bg']
	'spinbox:hover/button-background':   ['spinbox_btn_hover']
	'code:/background':                  ['ce_bg']
	'code:/border-color':                ['ce_border']
	'code:/color':                       ['ce_text']
	'code:/gutter-background':           ['ce_gutter_bg']
	'code:/gutter-color':                ['ce_gutter_text']
	'code:/current-line-background':     ['ce_cur_line']
	'code:/selection-background':        ['ce_selection']
	'code:/caret-color':                 ['ce_cursor']
	'combo:/background':                 ['cb_bg']
	'combo:/border-color':               ['cb_border']
	'combo:/color':                      ['cb_text']
	'combo:/arrow-color':                ['cb_arrow']
	// ── переключатели и шкалы ──
	'checkbox:/background':              ['chk_bg']
	'checkbox:checked/background':       ['chk_bg_checked']
	'checkbox:/border-color':            ['chk_border']
	'checkbox:/mark-color':              ['chk_mark']
	'radio:/background':                 ['rad_bg']
	'radio:/border-color':               ['rad_border']
	'radio:/mark-color':                 ['rad_dot']
	'toggle:/background':                ['tog_track_off']
	'toggle:checked/background':         ['tog_track_on']
	'toggle:/thumb-color':               ['tog_thumb']
	'slider:/background':                ['slider_track']
	'slider:/track-color':               ['slider_track']
	'slider:/fill-color':                ['slider_fill']
	'slider:/thumb-color':               ['slider_thumb']
	'slider:/tick-color':                ['slider_tick']
	'progress:/background':              ['prog_track']
	'progress:/fill-color':              ['prog_fill']
	'progress:/color':                   ['prog_text']
	'spinner:/color':                    ['spin_color']
	'spinner:/background':               ['spin_bg']
	// ── списки, таблицы, деревья ──
	'list:/background':                  ['lb_bg', 'lb_row_bg']
	'list:/alt-row-background':          ['lb_row_alt_bg']
	'list:/border-color':                ['lb_border']
	'list:/color':                       ['lb_row_text']
	'list:/grid-color':                  ['lb_grid']
	'list:/header-background':           ['lb_header_bg']
	'list:/header-color':                ['lb_header_text']
	'list:/header-border-color':         ['lb_header_border']
	'list:hover/background':             ['lb_row_hover']
	'list:selected/background':          ['lb_row_selected']
	'list:selected/color':               ['lb_row_sel_text']
	'table:/background':                 ['tv_bg', 'tv_row_bg']
	'table:/alt-row-background':         ['tv_row_alt_bg']
	'table:/border-color':               ['tv_border']
	'table:/color':                      ['tv_row_text']
	'table:/grid-color':                 ['tv_grid']
	'table:/header-background':          ['tv_header_bg']
	'table:/header-color':               ['tv_header_text']
	'table:/header-border-color':        ['tv_header_border']
	'table:/rownum-background':          ['tv_rownum_bg']
	'table:/rownum-color':               ['tv_rownum_text']
	'table:/current-line-background':    ['cur_line_bg']
	'table:hover/background':            ['tv_row_hover']
	'table:selected/background':         ['tv_row_selected']
	'table:selected/color':              ['tv_row_sel_text']
	'tree:/background':                  ['tr_bg']
	'tree:/border-color':                ['tr_border']
	'tree:/color':                       ['tr_row_text']
	'tree:/guide-color':                 ['tr_guide']
	'tree:/arrow-color':                 ['tr_arrow']
	'tree:hover/background':             ['tr_row_hover']
	'tree:selected/background':          ['tr_row_selected']
	'tree:selected/color':               ['tr_row_sel_text']
	'propertygrid:/background':          ['pg_bg', 'pg_row_bg']
	'propertygrid:/alt-row-background':  ['pg_row_alt_bg']
	'propertygrid:/border-color':        ['pg_border']
	'propertygrid:/color':               ['pg_row_text']
	'propertygrid:/grid-color':          ['pg_grid']
	'propertygrid:/header-background':   ['pg_header_bg']
	'propertygrid:/header-color':        ['pg_header_text']
	'propertygrid:/group-background':    ['pg_group_bg']
	'propertygrid:/group-color':         ['pg_group_text']
	'propertygrid:/splitter-color':      ['pg_splitter']
	'propertygrid:hover/background':     ['pg_row_hover']
	'propertygrid:selected/background':  ['pg_row_selected']
	'propertygrid:selected/color':       ['pg_row_sel_text']
	// ── отступы: padding - внутренний отступ, gap - между детьми ──
	'vbox:/padding':                     [css_padding_field]
	'hbox:/padding':                     [css_padding_field]
	'grid:/padding':                     [css_padding_field]
	'panel:/padding':                    [css_padding_field]
	'button:/padding':                   [css_padding_field]
	'label:/padding':                    [css_padding_field]
	'vbox:/gap':                         [css_gap_field]
	'hbox:/gap':                         [css_gap_field]
	'grid:/gap':                         [css_gap_field]
	// ── контейнеры ──
	'panel:/background':                 ['panel_bg']
	'panel:/border-color':               ['border']
	'tabs:/background':                  ['tab_bg']
	'tabs:/strip-background':            ['tab_strip_bg']
	'tabs:/tab-background':              ['tab_inactive_bg']
	'tabs:hover/tab-background':         ['tab_hover_bg']
	'tabs:selected/tab-background':      ['tab_active_bg']
	'tabs:/color':                       ['tab_inactive_text']
	'tabs:selected/color':               ['tab_active_text']
	'tabs:disabled/color':               ['tab_disabled_text']
	'tabs:/border-color':                ['tab_border']
	'tabs:/indicator-color':             ['tab_indicator']
	'accordion:/background':             ['acc_content_bg']
	'accordion:/header-background':      ['acc_header_bg']
	'accordion:hover/header-background': ['acc_header_hover']
	'accordion:/header-color':           ['acc_header_text']
	'accordion:/border-color':           ['acc_border']
	'accordion:/arrow-color':            ['acc_arrow']
	'split:/handle-color':               ['splitter_handle']
	'split:hover/handle-color':          ['splitter_hover']
	'menubar:/background':               ['menubar_bg']
	'menubar:/color':                    ['menubar_item_text']
	'menubar:hover/background':          ['menubar_item_hover']
	'menubar:pressed/background':        ['menubar_item_active']
	// ── прочее ──
	'separator:/color':                  ['sep_color']
	'breadcrumbs:/color':                ['brc_text']
	'breadcrumbs:selected/color':        ['brc_active_text']
	'breadcrumbs:hover/background':      ['brc_hover_bg']
	'breadcrumbs:/separator-color':      ['brc_separator']
	'plot:/background':                  ['plot_bg']
	'plot:/axis-color':                  ['plot_axis']
	'plot:/grid-color':                  ['plot_grid_major']
	'plot:/minor-grid-color':            ['plot_grid_minor']
	'plot:/color':                       ['plot_label']
	'plot:/border-color':                ['plot_border']
	'markdown:/heading-color':           ['md_heading']
	'markdown:/link-color':              ['md_link']
	'markdown:hover/link-color':         ['md_link_hover']
	'markdown:/code-background':         ['md_code_bg']
	'markdown:/code-color':              ['md_code_text']
	'markdown:/quote-bar-color':         ['md_quote_bar']
	'markdown:/quote-color':             ['md_quote_text']
	'markdown:/hr-color':                ['md_hr']
	'markdown:/border-color':            ['md_border']
	'markdown:/caption-color':           ['md_caption']
	'markdown:/table-border-color':      ['md_table_border']
	'markdown:/table-header-background': ['md_table_header_bg']
	// ── попапы: только корневые правила (рисуются вне дерева окна) ──
	'menu:/background':                  ['menu_bg']
	'menu:/border-color':                ['menu_border']
	'menu:/color':                       ['menu_item_text']
	'menu:hover/background':             ['menu_item_hover']
	'menu:hover/color':                  ['menu_item_sel_text']
	'menu:/separator-color':             ['menu_separator']
	'menu:/shortcut-color':              ['menu_shortcut_text']
	'tooltip:/background':               ['tooltip_bg']
	'tooltip:/border-color':             ['tooltip_border']
	'tooltip:/color':                    ['tooltip_text']
	'notification:/background':          ['notif_bg']
	'notification:/border-color':        ['notif_border']
	'notification:/title-color':         ['notif_title']
	'notification:/color':               ['notif_message']
	'dropdown:/background':              ['cb_dropdown_bg']
	'dropdown:/border-color':            ['cb_dropdown_border']
	'dropdown:/color':                   ['cb_item_text']
	'dropdown:hover/background':         ['cb_item_hover']
	'dropdown:selected/background':      ['cb_item_selected']
	'dropdown:selected/color':           ['cb_item_sel_text']
}

// css_is_theme_field_prop — `--имя` ссылается на поле Theme (`--lb-row-bg` -> lb_row_bg)?
fn css_is_theme_field_prop(prop string) bool {
	return prop.starts_with('--') && css_theme_has_field(css_field_of_prop(prop))
}

// css_field_of_prop — `--lb-row-bg` -> `lb_row_bg`.
fn css_field_of_prop(prop string) string {
	return prop[2..].replace('-', '_')
}

// css_lookup_fields — поля Theme для свойства на элементе типа typ (имя из
// css_kind_by_name, 'root' или тип попапа) в состоянии pseudo. Пусто -
// свойство здесь неприменимо. Общая строка `*` действует для обычных типов и
// для :root, но не для попапов: `menu { border-radius }` поменял бы радиус всем.
fn css_lookup_fields(typ string, pseudo string, prop string) []string {
	if prop.starts_with('--') {
		return if css_is_theme_field_prop(prop) { [css_field_of_prop(prop)] } else { []string{} }
	}
	if typ in css_fill_containers && pseudo == '' && prop == 'background' {
		return [css_fill_field]
	}
	if fields := css_prop_table['${typ}:${pseudo}/${prop}'] {
		return fields
	}
	if typ in css_root_types {
		return []string{}
	}
	return css_prop_table['*:${pseudo}/${prop}'] or { []string{} }
}

// css_props_for — список свойств, допустимых для типа в состоянии (для подсказки
// в сообщении об ошибке).
fn css_props_for(typ string, pseudo string) []string {
	mut out := []string{}
	for key, _ in css_prop_table {
		owner := key.all_before(':')
		if owner != typ && !(owner == '*' && typ !in css_root_types) {
			continue
		}
		if key.all_after(':').all_before('/') != pseudo {
			continue
		}
		prop := key.all_after('/')
		if prop !in out {
			out << prop
		}
	}
	if typ in css_fill_containers && pseudo == '' {
		out << 'background'
	}
	out.sort()
	return out
}

// css_compile_decl — объявление с заранее найденными полями для каждого вида
// виджета (CssDecl.fields_by_kind) и проверкой: свойство применимо хоть к
// чему-то, подходящему под селектор, и значение подходит по типу полю.
fn css_compile_decl(sel CssSelector, prop string, value CssValue, line int) !CssDecl {
	mut d := CssDecl{
		prop:  prop
		value: value
		line:  line
	}
	state := if sel.pseudo.len > 0 { ':${sel.pseudo}' } else { '' }
	// у прямого поля темы состояние выбирается самим именем (--button-hover),
	// `:hover { --button-bg }` молча писал бы button_bg - лучше ошибка
	if prop.starts_with('--') && state.len > 0 {
		return error('${prop}: у поля темы состояние ${state} не действует - выберите поле нужного состояния (например --button-hover)')
	}
	if sel.root_type.len > 0 {
		d.root_fields = css_lookup_fields(sel.root_type, sel.pseudo, prop)
		if d.root_fields.len == 0 {
			name := if sel.root_type == 'root' { ':root' } else { sel.root_type }
			return error('свойство ${prop} неприменимо к ${name}${state}; допустимо: ${css_props_for(sel.root_type, sel.pseudo).join(', ')}')
		}
		css_check_value(d.root_fields, prop, value)!
		return d
	}
	// высота контролов влияет на measure(), а раскладка от правил по дереву не
	// зависит (они действуют только на время draw) - поэтому только в :root
	if css_field_of_prop(prop) == 'control_height' {
		return error('${prop}: высота контролов влияет на раскладку - задавайте её только в :root')
	}
	subject_kind := sel.parts[0].kind
	d.fields_by_kind = [][]string{len: css_max_kind + 1}
	mut any_kind := false
	for kind in 1 .. css_max_kind + 1 {
		name := css_name_by_kind[kind]
		if name.len == 0 || (subject_kind != 0 && kind != subject_kind) {
			continue
		}
		fields := css_lookup_fields(name, sel.pseudo, prop)
		if fields.len > 0 {
			d.fields_by_kind[kind] = fields
			css_check_value(fields, prop, value)!
			any_kind = true
			if fields.any(it in css_layout_fields) {
				d.layout = true
			}
		}
	}
	if !any_kind {
		if subject_kind != 0 {
			name := css_name_by_kind[subject_kind]
			return error('свойство ${prop} неприменимо к ${name}${state}; допустимо: ${css_props_for(name, sel.pseudo).join(', ')}')
		}
		return error('свойство ${prop}${if state.len > 0 {
			' в состоянии ' + state
		} else {
			''
		}} неизвестно ни одному элементу')
	}
	return d
}

// css_check_value — значение подходит по типу всем полям (пробная запись в
// черновую тему: проверка та же, что при настоящем применении).
fn css_check_value(fields []string, prop string, value CssValue) ! {
	mut scratch := Theme{}
	mut box := CssBox{}
	for f in fields {
		if f == css_fill_field {
			if !value.is_color {
				return error('${prop}: ожидается цвет, а не ${value.raw}')
			}
			continue
		}
		css_write_field(mut scratch, mut box, f, value) or { return error('${prop}: ${err.msg()}') }
	}
}

// css_write_field — запись значения объявления: в поле Theme (обычные поля и
// начертания шрифта) или в отступы текущего виджета (@padding, @gap). Ошибка -
// значение не подходит полю (проверяется при разборе, при отрисовке её уже
// не бывает). @fill сюда не приходит - заливку рисует draw_child.
fn css_write_field(mut t Theme, mut box CssBox, field string, v CssValue) ! {
	match field {
		css_padding_field {
			// как в CSS: 1 число - все стороны, 2 - верх/низ и лево/право,
			// 3 - верх, лево/право, низ, 4 - верх, право, низ, лево
			n := v.nums
			if n.len == 0 || n.len > 4 || n.any(it < 0) {
				return error('ожидается от 1 до 4 неотрицательных чисел (верх право низ лево), а не ${v.raw}')
			}
			box.pad = match n.len {
				1 { CssInsets{n[0], n[0], n[0], n[0]} }
				2 { CssInsets{n[0], n[1], n[0], n[1]} }
				3 { CssInsets{n[0], n[1], n[2], n[1]} }
				else { CssInsets{n[0], n[1], n[2], n[3]} }
			}
			box.has_pad = true
		}
		css_gap_field {
			// `gap: 8` - между строками и колонками, `gap: 8 16` - строки, колонки
			n := v.nums
			if n.len == 0 || n.len > 2 || n.any(it < 0) {
				return error('ожидается 1 или 2 неотрицательных числа (строки колонки), а не ${v.raw}')
			}
			box.gap_row = n[0]
			box.gap_col = if n.len == 2 { n[1] } else { n[0] }
			box.has_gap = true
		}
		'font_bold', 'font_italic', 'font_mono' {
			// без копии карты: значение ищется прямо в константе
			on := css_font_keywords[field][v.word] or {
				words := css_font_keywords[field].clone()
				mut allowed := words.keys()
				allowed.sort()
				return error('ожидается одно из: ${allowed.join(', ')}, а не ${v.raw}')
			}
			match field {
				'font_bold' { t.font_bold = on }
				'font_italic' { t.font_italic = on }
				else { t.font_mono = on }
			}
		}
		'font_size' {
			if v.nums.len != 1 || v.num <= 0 {
				return error('ожидается положительное число, а не ${v.raw}')
			}
			t.font_size = v.num
		}
		else {
			theme_set_field(mut t, field, v)!
		}
	}
}

// css_theme_has_field — есть ли в Theme поле с таким именем.
fn css_theme_has_field(name string) bool {
	$for f in Theme.fields {
		if f.name == name {
			return true
		}
	}
	return false
}

// theme_set_field записывает значение в поле Theme по имени. Цвет - только в
// поле Color, число - в f32/int. Ошибка - поля нет или тип не тот.
fn theme_set_field(mut t Theme, field string, v CssValue) ! {
	$for f in Theme.fields {
		if f.name == field {
			$if f.typ is Color {
				if !v.is_color {
					return error('ожидается цвет, а не ${v.raw}')
				}
				t.$(f.name) = v.color
				return
			} $else $if f.typ is f32 {
				// цвет, слово или несколько чисел (`4 8`) - не одно число
				if v.nums.len != 1 {
					return error('ожидается число, а не ${v.raw}')
				}
				t.$(f.name) = v.num
				return
			} $else $if f.typ is int {
				if v.nums.len != 1 {
					return error('ожидается число, а не ${v.raw}')
				}
				t.$(f.name) = int(v.num)
				return
			} $else {
				return error('поле ${field} нельзя задать из CSS')
			}
		}
	}
	return error('в теме нет поля ${field}')
}
