module vgui

// ═══════════════════════════════════════════════════════
// Theme system
// ═══════════════════════════════════════════════════════

// Шапка файла.
// Theme - единая палитра и параметры оформления всего GUI. Окно держит один
// Theme (ctx.theme), каждый виджет при отрисовке берёт цвета из него. Файл
// состоит из трёх частей: (1) структура Theme; (2) методы eff_* - «эффективные»
// цвета с запасными значениями; (3) фабрики готовых тем (dark_theme(),
// light_theme(), win11_theme(), macos_theme() и т.д.), каждая возвращает новый Theme.
//
// Двухуровневая модель цветов:
//   1. ядро - базовые цвета (bg, surface, panel_bg, border, text_*, accent*,
//      button_*, input_*, scrollbar_*) заданы в каждой теме обязательно;
//   2. переопределения по виджетам (lb_*, tv_*, tr_*, cb_*, ... md_*) - необязательны.
//      Нулевое значение Color{0, 0, 0, 0} (альфа == 0) означает «не задано»: виджет
//      обращается к eff_<виджет>_<часть>(), и тот подставляет подходящий
//      цвет из ядра (например, фон ListBox -> input_bg, цвет выделения -> accent).
// Поэтому тема может задать только ядро, а переопределения добавлять точечно там, где
// универсальный запасной цвет выглядит плохо (светлые темы Windows/KDE/GTK, где
// заголовки таблиц и чередование строк подкрашены отдельно).
//
// Следствие: цвет с альфой 0 нельзя использовать как «намеренно прозрачный» в
// переопределении - он всегда читается как «не задано».
//
// Не-цветовые параметры: border_radius (скругление всех виджетов; у «плоских»
// тем 0), control_height (стандартная высота контролов для measure()), тень
// (shadow_color/offset/layers/blur - offset == 0 отключает тень), кольцо фокуса
// (focus_ring_*) и цвет подложки модальных диалогов (modal_backdrop_color).
pub struct Theme {
pub mut:
	// ── Core ──────────────────────────────────────────
	bg       Color
	surface  Color
	panel_bg Color
	border   Color
	// ── Text ──────────────────────────────────────────
	text_primary   Color
	text_secondary Color
	text_disabled  Color
	text_hint      Color
	// ── Accent ────────────────────────────────────────
	accent         Color
	accent_hover   Color
	accent_pressed Color
	accent_text    Color
	// ── Semantic ──────────────────────────────────────
	success     Color
	warning     Color
	error_color Color
	info        Color
	// ── Button ────────────────────────────────────────
	button_bg              Color
	button_hover           Color
	button_pressed         Color
	button_text            Color
	button_border          Color
	button_disabled_bg     Color
	button_disabled_border Color
	// ── Input / TextInput ─────────────────────────────
	input_bg     Color
	input_border Color
	input_focus  Color
	// ── Scrollbar ─────────────────────────────────────
	scrollbar_bg    Color
	scrollbar_thumb Color
	scrollbar_hover Color
	scrollbar_drag  Color
	// ── Shape / Shadow ────────────────────────────────
	border_radius f32 = 6.0
	// Стандартная высота контролов (кнопка, поле ввода, список,
	// счётчик) - её берёт measure(), поэтому в разметке высоту
	// задавать не нужно (Layout: measure/arrange в PROJECT.md)
	control_height f32 = 30.0
	shadow_color   Color
	shadow_offset  f32 = 0.0
	shadow_layers  int = 4   // number of blur layers
	shadow_blur    f32 = 0.0 // max expansion of the outer layer (logical px)
	// ── Focus ring ────────────────────────────────────
	// a=0 → inherit accent.brighten(0.3) via eff_focus_ring_color()
	focus_ring_color Color = Color{0, 0, 0, 0}
	focus_ring_width f32   = 2.0
	focus_ring_inset f32   = 2.0
	// ── Modal backdrop ────────────────────────────────
	modal_backdrop_color Color = Color{0, 0, 0, 90}

	// ══════════════════════════════════════════════════
	// Per-widget overrides  (a=0 → inherit from core)
	// ══════════════════════════════════════════════════
	// ── ListBox ───────────────────────────────────────
	// Блок «Per-widget overrides» (до конца структуры): для каждого виджета набор
	// необязательных цветов с префиксом-сокращением (lb - ListBox, tv - TableView,
	// tr - TreeView, cb - ComboBox, pg - PropertyGrid, tab - TabBox, acc - Accordion,
	// menu/menubar, tooltip, notif - Notification, slider, prog - ProgressBar, chk -
	// CheckBox, rad - RadioButton, tog - ToggleSwitch, spin - Spinner, spinbox, ce -
	// CodeEditor, brc - Breadcrumbs, sep, splitter, plot, md - MarkdownView).
	// По умолчанию все равны Color{0, 0, 0, 0} = «не задано». Запасные значения для
	// каждого - в соответствующем eff_*() ниже.
	lb_bg            Color = Color{0, 0, 0, 0}
	lb_border        Color = Color{0, 0, 0, 0}
	lb_header_bg     Color = Color{0, 0, 0, 0}
	lb_header_text   Color = Color{0, 0, 0, 0}
	lb_header_border Color = Color{0, 0, 0, 0}
	lb_row_bg        Color = Color{0, 0, 0, 0}
	lb_row_alt_bg    Color = Color{0, 0, 0, 0}
	lb_row_hover     Color = Color{0, 0, 0, 0}
	lb_row_selected  Color = Color{0, 0, 0, 0}
	lb_row_text      Color = Color{0, 0, 0, 0}
	lb_row_sel_text  Color = Color{0, 0, 0, 0}
	lb_grid          Color = Color{0, 0, 0, 0}

	// ── TableView ─────────────────────────────────────
	tv_bg            Color = Color{0, 0, 0, 0}
	tv_border        Color = Color{0, 0, 0, 0}
	tv_header_bg     Color = Color{0, 0, 0, 0}
	tv_header_text   Color = Color{0, 0, 0, 0}
	tv_header_border Color = Color{0, 0, 0, 0}
	tv_row_bg        Color = Color{0, 0, 0, 0}
	tv_row_alt_bg    Color = Color{0, 0, 0, 0}
	tv_row_hover     Color = Color{0, 0, 0, 0}
	tv_row_selected  Color = Color{0, 0, 0, 0}
	tv_row_text      Color = Color{0, 0, 0, 0}
	tv_row_sel_text  Color = Color{0, 0, 0, 0}
	tv_grid          Color = Color{0, 0, 0, 0}
	tv_rownum_bg     Color = Color{0, 0, 0, 0}
	tv_rownum_text   Color = Color{0, 0, 0, 0}

	// ── TreeView ──────────────────────────────────────
	tr_bg           Color = Color{0, 0, 0, 0}
	tr_border       Color = Color{0, 0, 0, 0}
	tr_row_hover    Color = Color{0, 0, 0, 0}
	tr_row_selected Color = Color{0, 0, 0, 0}
	tr_row_text     Color = Color{0, 0, 0, 0}
	tr_row_sel_text Color = Color{0, 0, 0, 0}
	tr_guide        Color = Color{0, 0, 0, 0}
	tr_arrow        Color = Color{0, 0, 0, 0}

	// ── ComboBox ──────────────────────────────────────
	cb_bg              Color = Color{0, 0, 0, 0}
	cb_border          Color = Color{0, 0, 0, 0}
	cb_text            Color = Color{0, 0, 0, 0}
	cb_arrow           Color = Color{0, 0, 0, 0}
	cb_dropdown_bg     Color = Color{0, 0, 0, 0}
	cb_dropdown_border Color = Color{0, 0, 0, 0}
	cb_item_hover      Color = Color{0, 0, 0, 0}
	cb_item_selected   Color = Color{0, 0, 0, 0}
	cb_item_text       Color = Color{0, 0, 0, 0}
	cb_item_sel_text   Color = Color{0, 0, 0, 0}

	// ── PropertyGrid ──────────────────────────────────
	pg_bg           Color = Color{0, 0, 0, 0}
	pg_border       Color = Color{0, 0, 0, 0}
	pg_header_bg    Color = Color{0, 0, 0, 0}
	pg_header_text  Color = Color{0, 0, 0, 0}
	pg_row_bg       Color = Color{0, 0, 0, 0}
	pg_row_alt_bg   Color = Color{0, 0, 0, 0}
	pg_row_hover    Color = Color{0, 0, 0, 0}
	pg_row_selected Color = Color{0, 0, 0, 0}
	pg_row_text     Color = Color{0, 0, 0, 0}
	pg_row_sel_text Color = Color{0, 0, 0, 0}
	pg_group_bg     Color = Color{0, 0, 0, 0}
	pg_group_text   Color = Color{0, 0, 0, 0}
	pg_grid         Color = Color{0, 0, 0, 0}
	pg_splitter     Color = Color{0, 0, 0, 0}

	// ── TabBox ────────────────────────────────────────
	tab_bg            Color = Color{0, 0, 0, 0}
	tab_strip_bg      Color = Color{0, 0, 0, 0}
	tab_active_bg     Color = Color{0, 0, 0, 0}
	tab_inactive_bg   Color = Color{0, 0, 0, 0}
	tab_hover_bg      Color = Color{0, 0, 0, 0}
	tab_active_text   Color = Color{0, 0, 0, 0}
	tab_inactive_text Color = Color{0, 0, 0, 0}
	tab_disabled_text Color = Color{0, 0, 0, 0}
	tab_border        Color = Color{0, 0, 0, 0}
	tab_indicator     Color = Color{0, 0, 0, 0}

	// ── Accordion ─────────────────────────────────────
	acc_header_bg    Color = Color{0, 0, 0, 0}
	acc_header_hover Color = Color{0, 0, 0, 0}
	acc_header_text  Color = Color{0, 0, 0, 0}
	acc_content_bg   Color = Color{0, 0, 0, 0}
	acc_border       Color = Color{0, 0, 0, 0}
	acc_arrow        Color = Color{0, 0, 0, 0}

	// ── Menu / MenuBar ────────────────────────────────
	menu_bg             Color = Color{0, 0, 0, 0}
	menu_border         Color = Color{0, 0, 0, 0}
	menu_item_hover     Color = Color{0, 0, 0, 0}
	menu_item_text      Color = Color{0, 0, 0, 0}
	menu_item_sel_text  Color = Color{0, 0, 0, 0}
	menu_separator      Color = Color{0, 0, 0, 0}
	menu_shortcut_text  Color = Color{0, 0, 0, 0}
	menubar_bg          Color = Color{0, 0, 0, 0}
	menubar_item_hover  Color = Color{0, 0, 0, 0}
	menubar_item_active Color = Color{0, 0, 0, 0}
	menubar_item_text   Color = Color{0, 0, 0, 0}

	// ── Tooltip ───────────────────────────────────────
	tooltip_bg     Color = Color{0, 0, 0, 0}
	tooltip_border Color = Color{0, 0, 0, 0}
	tooltip_text   Color = Color{0, 0, 0, 0}

	// ── Notification ──────────────────────────────────
	notif_bg      Color = Color{0, 0, 0, 0}
	notif_border  Color = Color{0, 0, 0, 0}
	notif_title   Color = Color{0, 0, 0, 0}
	notif_message Color = Color{0, 0, 0, 0}

	// ── Slider ────────────────────────────────────────
	slider_track Color = Color{0, 0, 0, 0}
	slider_fill  Color = Color{0, 0, 0, 0}
	slider_thumb Color = Color{0, 0, 0, 0}
	slider_tick  Color = Color{0, 0, 0, 0}

	// ── ProgressBar ───────────────────────────────────
	prog_track Color = Color{0, 0, 0, 0}
	prog_fill  Color = Color{0, 0, 0, 0}
	prog_text  Color = Color{0, 0, 0, 0}

	// ── CheckBox ──────────────────────────────────────
	chk_bg         Color = Color{0, 0, 0, 0}
	chk_bg_checked Color = Color{0, 0, 0, 0}
	chk_border     Color = Color{0, 0, 0, 0}
	chk_mark       Color = Color{0, 0, 0, 0}

	// ── RadioButton ───────────────────────────────────
	rad_bg     Color = Color{0, 0, 0, 0}
	rad_border Color = Color{0, 0, 0, 0}
	rad_dot    Color = Color{0, 0, 0, 0}

	// ── ToggleSwitch ──────────────────────────────────
	tog_track_off Color = Color{0, 0, 0, 0}
	tog_track_on  Color = Color{0, 0, 0, 0}
	tog_thumb     Color = Color{0, 0, 0, 0}

	// ── Spinner ───────────────────────────────────────
	spin_color Color = Color{0, 0, 0, 0}
	spin_bg    Color = Color{0, 0, 0, 0}

	// ── SpinBox ───────────────────────────────────────
	spinbox_bg        Color = Color{0, 0, 0, 0}
	spinbox_border    Color = Color{0, 0, 0, 0}
	spinbox_btn_bg    Color = Color{0, 0, 0, 0}
	spinbox_btn_hover Color = Color{0, 0, 0, 0}
	spinbox_text      Color = Color{0, 0, 0, 0}

	// ── CodeEditor ────────────────────────────────────
	ce_bg          Color = Color{0, 0, 0, 0}
	ce_border      Color = Color{0, 0, 0, 0}
	ce_gutter_bg   Color = Color{0, 0, 0, 0}
	ce_gutter_text Color = Color{0, 0, 0, 0}
	ce_text        Color = Color{0, 0, 0, 0}
	ce_cur_line    Color = Color{0, 0, 0, 0}
	ce_selection   Color = Color{0, 0, 0, 0}
	ce_cursor      Color = Color{0, 0, 0, 0}

	// ── Breadcrumbs ───────────────────────────────────
	brc_text        Color = Color{0, 0, 0, 0}
	brc_active_text Color = Color{0, 0, 0, 0}
	brc_hover_bg    Color = Color{0, 0, 0, 0}
	brc_separator   Color = Color{0, 0, 0, 0}

	// ── Separator ─────────────────────────────────────
	sep_color Color = Color{0, 0, 0, 0}

	// ── Splitter ──────────────────────────────────────
	splitter_handle Color = Color{0, 0, 0, 0}
	splitter_hover  Color = Color{0, 0, 0, 0}

	// ── Editor: current line (CodeEditor, TableView) ──
	// a=0 means auto-compute from surface
	cur_line_bg Color = Color{0, 0, 0, 0}

	// ── Plot widget ───────────────────────────────────
	// a=0 means "auto"
	plot_bg         Color = Color{0, 0, 0, 0}
	plot_axis       Color = Color{0, 0, 0, 0}
	plot_grid_major Color = Color{0, 0, 0, 0}
	plot_grid_minor Color = Color{0, 0, 0, 0}
	plot_label      Color = Color{0, 0, 0, 0}
	plot_border     Color = Color{0, 0, 0, 0}

	// ── MarkdownView ──────────────────────────────────
	// a=0 means "use default fallback"
	md_heading         Color = Color{0, 0, 0, 0}
	md_link            Color = Color{0, 0, 0, 0}
	md_link_hover      Color = Color{0, 0, 0, 0}
	md_code_bg         Color = Color{0, 0, 0, 0}
	md_code_text       Color = Color{0, 0, 0, 0}
	md_quote_bar       Color = Color{0, 0, 0, 0}
	md_quote_text      Color = Color{0, 0, 0, 0}
	md_hr              Color = Color{0, 0, 0, 0}
	md_border          Color = Color{0, 0, 0, 0}
	md_caption         Color = Color{0, 0, 0, 0}
	md_table_border    Color = Color{0, 0, 0, 0}
	md_table_header_bg Color = Color{0, 0, 0, 0}
}

// Группа методов eff_<виджет>_<часть>(): для каждого необязательного цвета возвращают
// значение, заданное в теме (альфа > 0), иначе запасной цвет из ядра. Все методы
// однотипны (помечены @[inline]), поэтому комментируется группа, а не каждый
// метод. Типичные запасные значения по смыслу цвета:
//   фон списков/полей/редакторов  -> input_bg;      их рамка -> input_border;
//   фон заголовков/полос          -> panel_bg;      разделители, сетка -> border;
//   фон выпадающих меню/подсказок -> surface;
//   подсветка наведения           -> button_hover;  выделенная строка/пункт -> accent;
//   текст на выделении            -> accent_text;   основной текст -> text_primary;
//   вторичный текст, стрелки      -> text_secondary; направляющие/неактивное -> text_disabled.
// Исключения с вычислением: eff_tab_active_bg (bg, подмешано 6% text_primary),
// eff_ce_selection (accent с альфой 80), eff_*_row_alt_bg (запасной - основной цвет
// строки, т.е. без чередования), eff_focus_ring_color (accent.brighten(0.3)).
// Замечание: eff_tv_bg() и eff_tv_border() для TableView в текущем коде table.v не
// используются (фон берётся из eff_tv_row_bg(), рамка - из input_border).
// ─── eff_* helpers ────────────────────────────────────────────────────────
// Each returns the widget-specific override if set (a>0), else the core fallback.

// ── ListBox ──
@[inline]
pub fn (t &Theme) eff_lb_bg() Color {
	return if t.lb_bg.a > 0 { t.lb_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_lb_border() Color {
	return if t.lb_border.a > 0 { t.lb_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_lb_header_bg() Color {
	return if t.lb_header_bg.a > 0 { t.lb_header_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_lb_header_text() Color {
	return if t.lb_header_text.a > 0 { t.lb_header_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_lb_header_border() Color {
	return if t.lb_header_border.a > 0 { t.lb_header_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_lb_row_bg() Color {
	return if t.lb_row_bg.a > 0 { t.lb_row_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_lb_row_alt_bg() Color {
	return if t.lb_row_alt_bg.a > 0 { t.lb_row_alt_bg } else { t.eff_lb_row_bg() }
}

@[inline]
pub fn (t &Theme) eff_lb_row_hover() Color {
	return if t.lb_row_hover.a > 0 { t.lb_row_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_lb_row_selected() Color {
	return if t.lb_row_selected.a > 0 { t.lb_row_selected } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_lb_row_text() Color {
	return if t.lb_row_text.a > 0 { t.lb_row_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_lb_row_sel_text() Color {
	return if t.lb_row_sel_text.a > 0 { t.lb_row_sel_text } else { t.accent_text }
}

@[inline]
pub fn (t &Theme) eff_lb_grid() Color {
	return if t.lb_grid.a > 0 { t.lb_grid } else { t.border }
}

// ── TableView ──
@[inline]
pub fn (t &Theme) eff_tv_bg() Color {
	return if t.tv_bg.a > 0 { t.tv_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_tv_border() Color {
	return if t.tv_border.a > 0 { t.tv_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_tv_header_bg() Color {
	return if t.tv_header_bg.a > 0 { t.tv_header_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_tv_header_text() Color {
	return if t.tv_header_text.a > 0 { t.tv_header_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_tv_header_border() Color {
	return if t.tv_header_border.a > 0 { t.tv_header_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_tv_row_bg() Color {
	return if t.tv_row_bg.a > 0 { t.tv_row_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_tv_row_alt_bg() Color {
	return if t.tv_row_alt_bg.a > 0 { t.tv_row_alt_bg } else { t.eff_tv_row_bg() }
}

@[inline]
pub fn (t &Theme) eff_tv_row_hover() Color {
	return if t.tv_row_hover.a > 0 { t.tv_row_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_tv_row_selected() Color {
	return if t.tv_row_selected.a > 0 { t.tv_row_selected } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_tv_row_text() Color {
	return if t.tv_row_text.a > 0 { t.tv_row_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_tv_row_sel_text() Color {
	return if t.tv_row_sel_text.a > 0 { t.tv_row_sel_text } else { t.accent_text }
}

@[inline]
pub fn (t &Theme) eff_tv_grid() Color {
	return if t.tv_grid.a > 0 { t.tv_grid } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_tv_rownum_bg() Color {
	return if t.tv_rownum_bg.a > 0 { t.tv_rownum_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_tv_rownum_text() Color {
	return if t.tv_rownum_text.a > 0 { t.tv_rownum_text } else { t.text_secondary }
}

// ── TreeView ──
@[inline]
pub fn (t &Theme) eff_tr_bg() Color {
	return if t.tr_bg.a > 0 { t.tr_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_tr_border() Color {
	return if t.tr_border.a > 0 { t.tr_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_tr_row_hover() Color {
	return if t.tr_row_hover.a > 0 { t.tr_row_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_tr_row_selected() Color {
	return if t.tr_row_selected.a > 0 { t.tr_row_selected } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_tr_row_text() Color {
	return if t.tr_row_text.a > 0 { t.tr_row_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_tr_row_sel_text() Color {
	return if t.tr_row_sel_text.a > 0 { t.tr_row_sel_text } else { t.accent_text }
}

@[inline]
pub fn (t &Theme) eff_tr_guide() Color {
	return if t.tr_guide.a > 0 { t.tr_guide } else { t.text_disabled }
}

@[inline]
pub fn (t &Theme) eff_tr_arrow() Color {
	return if t.tr_arrow.a > 0 { t.tr_arrow } else { t.text_secondary }
}

// ── ComboBox ──
@[inline]
pub fn (t &Theme) eff_cb_bg() Color {
	return if t.cb_bg.a > 0 { t.cb_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_cb_border() Color {
	return if t.cb_border.a > 0 { t.cb_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_cb_text() Color {
	return if t.cb_text.a > 0 { t.cb_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_cb_arrow() Color {
	return if t.cb_arrow.a > 0 { t.cb_arrow } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_cb_dropdown_bg() Color {
	return if t.cb_dropdown_bg.a > 0 { t.cb_dropdown_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_cb_dropdown_border() Color {
	return if t.cb_dropdown_border.a > 0 { t.cb_dropdown_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_cb_item_hover() Color {
	return if t.cb_item_hover.a > 0 { t.cb_item_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_cb_item_selected() Color {
	return if t.cb_item_selected.a > 0 { t.cb_item_selected } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_cb_item_text() Color {
	return if t.cb_item_text.a > 0 { t.cb_item_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_cb_item_sel_text() Color {
	return if t.cb_item_sel_text.a > 0 { t.cb_item_sel_text } else { t.accent_text }
}

// ── PropertyGrid ──
@[inline]
pub fn (t &Theme) eff_pg_bg() Color {
	return if t.pg_bg.a > 0 { t.pg_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_pg_border() Color {
	return if t.pg_border.a > 0 { t.pg_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_pg_header_bg() Color {
	return if t.pg_header_bg.a > 0 { t.pg_header_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_pg_header_text() Color {
	return if t.pg_header_text.a > 0 { t.pg_header_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_pg_row_bg() Color {
	return if t.pg_row_bg.a > 0 { t.pg_row_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_pg_row_alt_bg() Color {
	return if t.pg_row_alt_bg.a > 0 { t.pg_row_alt_bg } else { t.eff_pg_row_bg() }
}

@[inline]
pub fn (t &Theme) eff_pg_row_hover() Color {
	return if t.pg_row_hover.a > 0 { t.pg_row_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_pg_row_selected() Color {
	return if t.pg_row_selected.a > 0 { t.pg_row_selected } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_pg_row_text() Color {
	return if t.pg_row_text.a > 0 { t.pg_row_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_pg_row_sel_text() Color {
	return if t.pg_row_sel_text.a > 0 { t.pg_row_sel_text } else { t.accent_text }
}

@[inline]
pub fn (t &Theme) eff_pg_group_bg() Color {
	return if t.pg_group_bg.a > 0 { t.pg_group_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_pg_group_text() Color {
	return if t.pg_group_text.a > 0 { t.pg_group_text } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_pg_grid() Color {
	return if t.pg_grid.a > 0 { t.pg_grid } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_pg_splitter() Color {
	return if t.pg_splitter.a > 0 { t.pg_splitter } else { t.border }
}

// ── TabBox ──
@[inline]
pub fn (t &Theme) eff_tab_bg() Color {
	return if t.tab_bg.a > 0 { t.tab_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_tab_strip_bg() Color {
	return if t.tab_strip_bg.a > 0 { t.tab_strip_bg } else { t.bg }
}

@[inline]
pub fn (t &Theme) eff_tab_active_bg() Color {
	return if t.tab_active_bg.a > 0 { t.tab_active_bg } else { t.bg.blend(t.text_primary, 0.06) }
}

@[inline]
pub fn (t &Theme) eff_tab_inactive_bg() Color {
	return if t.tab_inactive_bg.a > 0 { t.tab_inactive_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_tab_hover_bg() Color {
	return if t.tab_hover_bg.a > 0 { t.tab_hover_bg } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_tab_active_text() Color {
	return if t.tab_active_text.a > 0 { t.tab_active_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_tab_inactive_text() Color {
	return if t.tab_inactive_text.a > 0 { t.tab_inactive_text } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_tab_disabled_text() Color {
	return if t.tab_disabled_text.a > 0 { t.tab_disabled_text } else { t.text_disabled }
}

@[inline]
pub fn (t &Theme) eff_tab_border() Color {
	return if t.tab_border.a > 0 { t.tab_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_tab_indicator() Color {
	return if t.tab_indicator.a > 0 { t.tab_indicator } else { t.accent }
}

// ── Accordion ──
@[inline]
pub fn (t &Theme) eff_acc_header_bg() Color {
	return if t.acc_header_bg.a > 0 { t.acc_header_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_acc_header_hover() Color {
	return if t.acc_header_hover.a > 0 { t.acc_header_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_acc_header_text() Color {
	return if t.acc_header_text.a > 0 { t.acc_header_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_acc_content_bg() Color {
	return if t.acc_content_bg.a > 0 { t.acc_content_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_acc_border() Color {
	return if t.acc_border.a > 0 { t.acc_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_acc_arrow() Color {
	return if t.acc_arrow.a > 0 { t.acc_arrow } else { t.text_secondary }
}

// ── Menu ──
@[inline]
pub fn (t &Theme) eff_menu_bg() Color {
	return if t.menu_bg.a > 0 { t.menu_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_menu_border() Color {
	return if t.menu_border.a > 0 { t.menu_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_menu_item_hover() Color {
	return if t.menu_item_hover.a > 0 { t.menu_item_hover } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_menu_item_text() Color {
	return if t.menu_item_text.a > 0 { t.menu_item_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_menu_item_sel_text() Color {
	return if t.menu_item_sel_text.a > 0 { t.menu_item_sel_text } else { t.accent_text }
}

@[inline]
pub fn (t &Theme) eff_menu_separator() Color {
	return if t.menu_separator.a > 0 { t.menu_separator } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_menu_shortcut_text() Color {
	return if t.menu_shortcut_text.a > 0 { t.menu_shortcut_text } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_menubar_bg() Color {
	return if t.menubar_bg.a > 0 { t.menubar_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_menubar_item_hover() Color {
	return if t.menubar_item_hover.a > 0 { t.menubar_item_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_menubar_item_active() Color {
	return if t.menubar_item_active.a > 0 { t.menubar_item_active } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_menubar_item_text() Color {
	return if t.menubar_item_text.a > 0 { t.menubar_item_text } else { t.text_primary }
}

// ── Tooltip ──
@[inline]
pub fn (t &Theme) eff_tooltip_bg() Color {
	return if t.tooltip_bg.a > 0 { t.tooltip_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_tooltip_border() Color {
	return if t.tooltip_border.a > 0 { t.tooltip_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_tooltip_text() Color {
	return if t.tooltip_text.a > 0 { t.tooltip_text } else { t.text_primary }
}

// ── Notification ──
@[inline]
pub fn (t &Theme) eff_notif_bg() Color {
	return if t.notif_bg.a > 0 { t.notif_bg } else { t.surface }
}

@[inline]
pub fn (t &Theme) eff_notif_border() Color {
	return if t.notif_border.a > 0 { t.notif_border } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_notif_title() Color {
	return if t.notif_title.a > 0 { t.notif_title } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_notif_message() Color {
	return if t.notif_message.a > 0 { t.notif_message } else { t.text_secondary }
}

// ── Slider ──
@[inline]
pub fn (t &Theme) eff_slider_track() Color {
	return if t.slider_track.a > 0 { t.slider_track } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_slider_fill() Color {
	return if t.slider_fill.a > 0 { t.slider_fill } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_slider_thumb() Color {
	return if t.slider_thumb.a > 0 { t.slider_thumb } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_slider_tick() Color {
	return if t.slider_tick.a > 0 { t.slider_tick } else { t.text_secondary }
}

// ── ProgressBar ──
@[inline]
pub fn (t &Theme) eff_prog_track() Color {
	return if t.prog_track.a > 0 { t.prog_track } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_prog_fill() Color {
	return if t.prog_fill.a > 0 { t.prog_fill } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_prog_text() Color {
	return if t.prog_text.a > 0 { t.prog_text } else { t.text_primary }
}

// ── CheckBox ──
@[inline]
pub fn (t &Theme) eff_chk_bg() Color {
	return if t.chk_bg.a > 0 { t.chk_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_chk_bg_checked() Color {
	return if t.chk_bg_checked.a > 0 { t.chk_bg_checked } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_chk_border() Color {
	return if t.chk_border.a > 0 { t.chk_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_chk_mark() Color {
	return if t.chk_mark.a > 0 { t.chk_mark } else { t.accent_text }
}

// ── RadioButton ──
@[inline]
pub fn (t &Theme) eff_rad_bg() Color {
	return if t.rad_bg.a > 0 { t.rad_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_rad_border() Color {
	return if t.rad_border.a > 0 { t.rad_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_rad_dot() Color {
	return if t.rad_dot.a > 0 { t.rad_dot } else { t.accent }
}

// ── ToggleSwitch ──
@[inline]
pub fn (t &Theme) eff_tog_track_off() Color {
	return if t.tog_track_off.a > 0 { t.tog_track_off } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_tog_track_on() Color {
	return if t.tog_track_on.a > 0 { t.tog_track_on } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_tog_thumb() Color {
	return if t.tog_thumb.a > 0 { t.tog_thumb } else { t.accent_text }
}

// ── Spinner ──
@[inline]
pub fn (t &Theme) eff_spin_color() Color {
	return if t.spin_color.a > 0 { t.spin_color } else { t.accent }
}

@[inline]
pub fn (t &Theme) eff_spin_bg() Color {
	return if t.spin_bg.a > 0 { t.spin_bg } else { t.border }
}

// ── SpinBox ──
@[inline]
pub fn (t &Theme) eff_spinbox_bg() Color {
	return if t.spinbox_bg.a > 0 { t.spinbox_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_spinbox_border() Color {
	return if t.spinbox_border.a > 0 { t.spinbox_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_spinbox_btn_bg() Color {
	return if t.spinbox_btn_bg.a > 0 { t.spinbox_btn_bg } else { t.button_bg }
}

@[inline]
pub fn (t &Theme) eff_spinbox_btn_hover() Color {
	return if t.spinbox_btn_hover.a > 0 { t.spinbox_btn_hover } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_spinbox_text() Color {
	return if t.spinbox_text.a > 0 { t.spinbox_text } else { t.text_primary }
}

// ── CodeEditor ──
@[inline]
pub fn (t &Theme) eff_ce_bg() Color {
	return if t.ce_bg.a > 0 { t.ce_bg } else { t.input_bg }
}

@[inline]
pub fn (t &Theme) eff_ce_border() Color {
	return if t.ce_border.a > 0 { t.ce_border } else { t.input_border }
}

@[inline]
pub fn (t &Theme) eff_ce_gutter_bg() Color {
	return if t.ce_gutter_bg.a > 0 { t.ce_gutter_bg } else { t.panel_bg }
}

@[inline]
pub fn (t &Theme) eff_ce_gutter_text() Color {
	return if t.ce_gutter_text.a > 0 { t.ce_gutter_text } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_ce_text() Color {
	return if t.ce_text.a > 0 { t.ce_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_ce_cur_line() Color {
	return if t.ce_cur_line.a > 0 { t.ce_cur_line } else { t.cur_line_bg }
}

@[inline]
pub fn (t &Theme) eff_ce_selection() Color {
	return if t.ce_selection.a > 0 { t.ce_selection } else { t.accent.with_alpha(80) }
}

@[inline]
pub fn (t &Theme) eff_ce_cursor() Color {
	return if t.ce_cursor.a > 0 { t.ce_cursor } else { t.accent }
}

// ── Breadcrumbs ──
@[inline]
pub fn (t &Theme) eff_brc_text() Color {
	return if t.brc_text.a > 0 { t.brc_text } else { t.text_secondary }
}

@[inline]
pub fn (t &Theme) eff_brc_active_text() Color {
	return if t.brc_active_text.a > 0 { t.brc_active_text } else { t.text_primary }
}

@[inline]
pub fn (t &Theme) eff_brc_hover_bg() Color {
	return if t.brc_hover_bg.a > 0 { t.brc_hover_bg } else { t.button_hover }
}

@[inline]
pub fn (t &Theme) eff_brc_separator() Color {
	return if t.brc_separator.a > 0 { t.brc_separator } else { t.text_disabled }
}

// ── Separator ──
@[inline]
pub fn (t &Theme) eff_sep_color() Color {
	return if t.sep_color.a > 0 { t.sep_color } else { t.border }
}

// ── Splitter ──
@[inline]
pub fn (t &Theme) eff_splitter_handle() Color {
	return if t.splitter_handle.a > 0 { t.splitter_handle } else { t.border }
}

@[inline]
pub fn (t &Theme) eff_splitter_hover() Color {
	return if t.splitter_hover.a > 0 { t.splitter_hover } else { t.accent }
}

// ── Focus ring ──
@[inline]
pub fn (t &Theme) eff_focus_ring_color() Color {
	return if t.focus_ring_color.a > 0 { t.focus_ring_color } else { t.accent.brighten(0.3) }
}

// ═══════════════════════════════════════════════════════
// VS Code Dark
// ═══════════════════════════════════════════════════════

// Фабрики тем. Каждая возвращает полностью заполненное ядро и при необходимости
// отдельные переопределения. Правила, общие для всех:
//   - возвращается новый Theme по значению: изменение копии на другие окна не влияет;
//   - shadow_offset == 0 - плоская тема без теней; border_radius == 0 - острые углы;
//   - plot_* заданы в каждой теме, т.к. у графиков нет универсальных запасных цветов;
//   - в тёмных темах переопределений по виджетам почти нет (запасные цвета
//     ядра там и так подходят), в светлых - добавлены для контраста заголовков,
//     сетки и чередования строк.
// Тема dark_theme - «VS Code Dark»: тёмно-серый фон, синий акцент (0,122,204), радиус 6.
pub fn dark_theme() Theme {
	return Theme{
		bg:                     Color{30, 30, 30, 255}
		surface:                Color{42, 42, 42, 255}
		panel_bg:               Color{37, 37, 38, 255}
		border:                 Color{58, 58, 58, 255}
		text_primary:           Color{220, 220, 220, 255}
		text_secondary:         Color{160, 160, 160, 255}
		text_disabled:          Color{100, 100, 100, 255}
		text_hint:              Color{120, 120, 120, 255}
		accent:                 Color{0, 122, 204, 255}
		accent_hover:           Color{28, 141, 214, 255}
		accent_pressed:         Color{0, 102, 180, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{72, 199, 142, 255}
		warning:                Color{255, 183, 77, 255}
		error_color:            Color{244, 67, 54, 255}
		info:                   Color{66, 165, 245, 255}
		button_bg:              Color{60, 60, 60, 255}
		button_hover:           Color{70, 70, 70, 255}
		button_pressed:         Color{50, 50, 50, 255}
		button_text:            Color{220, 220, 220, 255}
		button_border:          Color{58, 58, 58, 255}
		button_disabled_bg:     Color{45, 45, 45, 255}
		button_disabled_border: Color{50, 50, 50, 255}
		input_bg:               Color{50, 50, 50, 255}
		input_border:           Color{70, 70, 70, 255}
		input_focus:            Color{0, 122, 204, 255}
		scrollbar_bg:           Color{37, 37, 38, 255}
		scrollbar_thumb:        Color{90, 93, 100, 255}
		scrollbar_hover:        Color{130, 135, 144, 255}
		scrollbar_drag:         Color{160, 165, 175, 255}
		cur_line_bg:            Color{62, 62, 66, 255}
		shadow_color:           Color{0, 0, 0, 90}
		border_radius:          6.0
		shadow_offset:          2.0
		shadow_blur:            5.0
		shadow_layers:          4
		plot_bg:                Color{24, 24, 26, 255}
		plot_axis:              Color{200, 200, 200, 255}
		plot_grid_major:        Color{60, 60, 66, 255}
		plot_grid_minor:        Color{45, 45, 50, 255}
		plot_label:             Color{180, 180, 185, 255}
		plot_border:            Color{70, 70, 75, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Generic Light  — improved contrast
// ═══════════════════════════════════════════════════════

// Светлая нейтральная тема с повышенным контрастом; много точечных переопределений
// (заголовки списков/таблиц/PropertyGrid, чередование строк, подсказки жёлтые).
pub fn light_theme() Theme {
	return Theme{
		bg:                     Color{240, 240, 240, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{228, 228, 228, 255}
		border:                 Color{160, 160, 165, 255}
		text_primary:           Color{15, 15, 15, 255}
		text_secondary:         Color{65, 65, 70, 255}
		text_disabled:          Color{155, 155, 160, 255}
		text_hint:              Color{125, 125, 130, 255}
		accent:                 Color{0, 95, 190, 255}
		accent_hover:           Color{0, 115, 210, 255}
		accent_pressed:         Color{0, 75, 165, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{25, 130, 50, 255}
		warning:                Color{185, 115, 0, 255}
		error_color:            Color{190, 30, 45, 255}
		info:                   Color{0, 95, 190, 255}
		button_bg:              Color{218, 218, 218, 255}
		button_hover:           Color{200, 200, 200, 255}
		button_pressed:         Color{180, 180, 180, 255}
		button_text:            Color{15, 15, 15, 255}
		button_border:          Color{150, 150, 155, 255}
		button_disabled_bg:     Color{225, 225, 225, 255}
		button_disabled_border: Color{185, 185, 185, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{155, 155, 160, 255}
		input_focus:            Color{0, 95, 190, 255}
		scrollbar_bg:           Color{215, 215, 215, 255}
		scrollbar_thumb:        Color{130, 132, 140, 255}
		scrollbar_hover:        Color{95, 97, 105, 255}
		scrollbar_drag:         Color{65, 67, 75, 255}
		cur_line_bg:            Color{215, 230, 250, 255}
		shadow_color:           Color{0, 0, 0, 45}
		border_radius:          6.0
		shadow_offset:          2.0
		shadow_blur:            6.0
		shadow_layers:          4
		plot_bg:                Color{252, 252, 252, 255}
		plot_axis:              Color{25, 25, 25, 255}
		plot_grid_major:        Color{175, 175, 180, 255}
		plot_grid_minor:        Color{210, 210, 215, 255}
		plot_label:             Color{55, 55, 60, 255}
		plot_border:            Color{155, 155, 160, 255}
		lb_header_bg:           Color{205, 205, 208, 255}
		lb_header_text:         Color{15, 15, 15, 255}
		lb_header_border:       Color{155, 155, 160, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{242, 242, 246, 255}
		lb_row_hover:           Color{205, 225, 248, 255}
		lb_grid:                Color{190, 190, 195, 255}
		tv_header_bg:           Color{205, 205, 208, 255}
		tv_header_text:         Color{15, 15, 15, 255}
		tv_header_border:       Color{155, 155, 160, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{242, 242, 246, 255}
		tv_row_hover:           Color{205, 225, 248, 255}
		tv_grid:                Color{190, 190, 195, 255}
		tv_rownum_bg:           Color{218, 218, 218, 255}
		tv_rownum_text:         Color{75, 75, 80, 255}
		pg_header_bg:           Color{205, 205, 208, 255}
		pg_header_text:         Color{15, 15, 15, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{242, 242, 246, 255}
		pg_row_hover:           Color{205, 225, 248, 255}
		pg_group_bg:            Color{218, 218, 222, 255}
		pg_group_text:          Color{40, 40, 45, 255}
		pg_grid:                Color{190, 190, 195, 255}
		tab_inactive_bg:        Color{202, 202, 202, 255}
		tab_active_text:        Color{15, 15, 15, 255}
		tab_inactive_text:      Color{70, 70, 75, 255}
		tab_border:             Color{155, 155, 160, 255}
		acc_header_bg:          Color{218, 218, 218, 255}
		acc_header_hover:       Color{200, 200, 200, 255}
		acc_content_bg:         Color{248, 248, 248, 255}
		acc_border:             Color{160, 160, 165, 255}
		menu_bg:                Color{252, 252, 252, 255}
		menu_border:            Color{160, 160, 165, 255}
		menubar_bg:             Color{228, 228, 228, 255}
		tooltip_bg:             Color{255, 255, 220, 255}
		tooltip_border:         Color{155, 150, 100, 255}
		tooltip_text:           Color{15, 15, 15, 255}
		notif_bg:               Color{252, 252, 252, 255}
		notif_border:           Color{160, 160, 165, 255}
		slider_track:           Color{175, 175, 180, 255}
		prog_track:             Color{195, 195, 200, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Monokai
// ═══════════════════════════════════════════════════════

// Monokai: тёмно-оливковый фон, салатовый акцент (166,226,46), без теней.
pub fn monokai_theme() Theme {
	return Theme{
		bg:                     Color{39, 40, 34, 255}
		surface:                Color{49, 50, 44, 255}
		panel_bg:               Color{44, 45, 39, 255}
		border:                 Color{70, 71, 65, 255}
		text_primary:           Color{248, 248, 242, 255}
		text_secondary:         Color{190, 190, 180, 255}
		text_disabled:          Color{117, 113, 94, 255}
		text_hint:              Color{117, 113, 94, 255}
		accent:                 Color{166, 226, 46, 255}
		accent_hover:           Color{180, 235, 70, 255}
		accent_pressed:         Color{140, 200, 30, 255}
		accent_text:            Color{39, 40, 34, 255}
		success:                Color{166, 226, 46, 255}
		warning:                Color{230, 219, 116, 255}
		error_color:            Color{249, 38, 114, 255}
		info:                   Color{102, 217, 239, 255}
		button_bg:              Color{60, 61, 55, 255}
		button_hover:           Color{75, 76, 70, 255}
		button_pressed:         Color{50, 51, 45, 255}
		button_text:            Color{248, 248, 242, 255}
		button_border:          Color{70, 71, 65, 255}
		button_disabled_bg:     Color{50, 51, 45, 255}
		button_disabled_border: Color{60, 61, 55, 255}
		input_bg:               Color{49, 50, 44, 255}
		input_border:           Color{75, 76, 70, 255}
		input_focus:            Color{166, 226, 46, 255}
		scrollbar_bg:           Color{44, 45, 39, 255}
		scrollbar_thumb:        Color{95, 96, 85, 255}
		scrollbar_hover:        Color{135, 136, 120, 255}
		scrollbar_drag:         Color{166, 226, 46, 200}
		cur_line_bg:            Color{62, 63, 56, 255}
		shadow_color:           Color{0, 0, 0, 80}
		border_radius:          6.0
		shadow_offset:          0.0
		plot_bg:                Color{39, 40, 34, 255}
		plot_axis:              Color{248, 248, 242, 255}
		plot_grid_major:        Color{75, 76, 65, 255}
		plot_grid_minor:        Color{55, 56, 50, 255}
		plot_label:             Color{200, 200, 190, 255}
		plot_border:            Color{80, 81, 75, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Windows 10 — flat Segoe UI style, sharp corners
// ═══════════════════════════════════════════════════════

// Windows 10: плоская, острые углы (радиус 0), без теней, синий акцент (0,120,215).
pub fn win10_theme() Theme {
	return Theme{
		bg:                     Color{240, 240, 240, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{240, 240, 240, 255}
		border:                 Color{173, 173, 173, 255}
		text_primary:           Color{0, 0, 0, 255}
		text_secondary:         Color{90, 90, 90, 255}
		text_disabled:          Color{160, 160, 160, 255}
		text_hint:              Color{136, 136, 136, 255}
		accent:                 Color{0, 120, 215, 255}
		accent_hover:           Color{23, 135, 225, 255}
		accent_pressed:         Color{0, 100, 190, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{16, 124, 16, 255}
		warning:                Color{247, 181, 56, 255}
		error_color:            Color{232, 17, 35, 255}
		info:                   Color{0, 120, 215, 255}
		button_bg:              Color{225, 225, 225, 255}
		button_hover:           Color{229, 241, 251, 255}
		button_pressed:         Color{204, 228, 247, 255}
		button_text:            Color{0, 0, 0, 255}
		button_border:          Color{173, 173, 173, 255}
		button_disabled_bg:     Color{204, 204, 204, 255}
		button_disabled_border: Color{191, 191, 191, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{122, 122, 122, 255}
		input_focus:            Color{0, 120, 215, 255}
		scrollbar_bg:           Color{232, 232, 232, 255}
		scrollbar_thumb:        Color{166, 166, 166, 255}
		scrollbar_hover:        Color{120, 120, 120, 255}
		scrollbar_drag:         Color{90, 90, 90, 255}
		cur_line_bg:            Color{228, 236, 248, 255}
		shadow_color:           Color{0, 0, 0, 0}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{255, 255, 255, 255}
		plot_axis:              Color{0, 0, 0, 255}
		plot_grid_major:        Color{200, 200, 200, 255}
		plot_grid_minor:        Color{230, 230, 230, 255}
		plot_label:             Color{60, 60, 60, 255}
		plot_border:            Color{173, 173, 173, 255}
		// Per-widget overrides
		lb_header_bg:           Color{225, 225, 225, 255}
		lb_header_border:       Color{145, 145, 145, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{246, 246, 250, 255}
		lb_row_hover:           Color{229, 241, 251, 255}
		lb_grid:                Color{210, 210, 210, 255}
		tv_header_bg:           Color{225, 225, 225, 255}
		tv_header_border:       Color{145, 145, 145, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{246, 246, 250, 255}
		tv_row_hover:           Color{229, 241, 251, 255}
		tv_grid:                Color{210, 210, 210, 255}
		tv_rownum_bg:           Color{232, 232, 232, 255}
		pg_header_bg:           Color{225, 225, 225, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{246, 246, 250, 255}
		pg_row_hover:           Color{229, 241, 251, 255}
		pg_group_bg:            Color{232, 232, 232, 255}
		pg_grid:                Color{210, 210, 210, 255}
		tooltip_bg:             Color{255, 255, 225, 255}
		tooltip_border:         Color{140, 140, 100, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Windows 10 Dark — dark mode variant
// ═══════════════════════════════════════════════════════

// Тёмный вариант Windows 10: тот же акцент, острые углы, без теней.
pub fn win10_dark_theme() Theme {
	return Theme{
		bg:                     Color{32, 32, 32, 255}
		surface:                Color{43, 43, 43, 255}
		panel_bg:               Color{37, 37, 37, 255}
		border:                 Color{60, 60, 60, 255}
		text_primary:           Color{255, 255, 255, 255}
		text_secondary:         Color{180, 180, 180, 255}
		text_disabled:          Color{110, 110, 110, 255}
		text_hint:              Color{130, 130, 130, 255}
		accent:                 Color{0, 120, 215, 255}
		accent_hover:           Color{23, 135, 225, 255}
		accent_pressed:         Color{0, 100, 190, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{16, 124, 16, 255}
		warning:                Color{247, 181, 56, 255}
		error_color:            Color{232, 17, 35, 255}
		info:                   Color{0, 120, 215, 255}
		button_bg:              Color{55, 55, 55, 255}
		button_hover:           Color{66, 66, 66, 255}
		button_pressed:         Color{44, 44, 44, 255}
		button_text:            Color{255, 255, 255, 255}
		button_border:          Color{80, 80, 80, 255}
		button_disabled_bg:     Color{45, 45, 45, 255}
		button_disabled_border: Color{55, 55, 55, 255}
		input_bg:               Color{43, 43, 43, 255}
		input_border:           Color{80, 80, 80, 255}
		input_focus:            Color{0, 120, 215, 255}
		scrollbar_bg:           Color{35, 35, 35, 255}
		scrollbar_thumb:        Color{90, 90, 95, 255}
		scrollbar_hover:        Color{130, 130, 138, 255}
		scrollbar_drag:         Color{165, 165, 175, 255}
		cur_line_bg:            Color{55, 55, 60, 255}
		shadow_color:           Color{0, 0, 0, 0}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{28, 28, 28, 255}
		plot_axis:              Color{240, 240, 240, 255}
		plot_grid_major:        Color{60, 60, 60, 255}
		plot_grid_minor:        Color{45, 45, 45, 255}
		plot_label:             Color{190, 190, 190, 255}
		plot_border:            Color{80, 80, 80, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Windows 11 — Mica/Acrylic feel, rounded, lighter
// ═══════════════════════════════════════════════════════

// Windows 11 (стиль Mica): светлая, мягкие серые поверхности, акцент (0,95,184).
// В коде border_radius и shadow_offset заданы 0 - то есть углы острые, несмотря на
// пометку «rounded» в заголовке блока выше.
pub fn win11_theme() Theme {
	return Theme{
		bg:                     Color{243, 243, 243, 255}
		surface:                Color{251, 251, 251, 255}
		panel_bg:               Color{238, 238, 238, 255}
		border:                 Color{209, 209, 209, 255}
		text_primary:           Color{28, 28, 28, 255}
		text_secondary:         Color{96, 96, 96, 255}
		text_disabled:          Color{172, 172, 172, 255}
		text_hint:              Color{140, 140, 140, 255}
		accent:                 Color{0, 95, 184, 255}
		accent_hover:           Color{0, 107, 206, 255}
		accent_pressed:         Color{0, 82, 163, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{15, 123, 15, 255}
		warning:                Color{157, 93, 0, 255}
		error_color:            Color{196, 43, 28, 255}
		info:                   Color{0, 95, 184, 255}
		button_bg:              Color{251, 251, 251, 255}
		button_hover:           Color{238, 238, 238, 255}
		button_pressed:         Color{225, 225, 225, 255}
		button_text:            Color{28, 28, 28, 255}
		button_border:          Color{195, 195, 195, 255}
		button_disabled_bg:     Color{243, 243, 243, 255}
		button_disabled_border: Color{220, 220, 220, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{170, 170, 170, 255}
		input_focus:            Color{0, 95, 184, 255}
		scrollbar_bg:           Color{230, 230, 230, 255}
		scrollbar_thumb:        Color{155, 155, 160, 255}
		scrollbar_hover:        Color{115, 115, 122, 255}
		scrollbar_drag:         Color{80, 80, 90, 255}
		cur_line_bg:            Color{225, 235, 250, 255}
		shadow_color:           Color{0, 0, 0, 18}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{253, 253, 253, 255}
		plot_axis:              Color{28, 28, 28, 255}
		plot_grid_major:        Color{215, 215, 220, 255}
		plot_grid_minor:        Color{238, 238, 242, 255}
		plot_label:             Color{80, 80, 85, 255}
		plot_border:            Color{195, 195, 200, 255}
		// Per-widget overrides for better contrast
		lb_header_bg:           Color{222, 222, 222, 255}
		lb_header_text:         Color{28, 28, 28, 255}
		lb_header_border:       Color{185, 185, 185, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{245, 245, 248, 255}
		lb_row_hover:           Color{215, 230, 248, 255}
		lb_grid:                Color{205, 205, 205, 255}
		tv_header_bg:           Color{222, 222, 222, 255}
		tv_header_text:         Color{28, 28, 28, 255}
		tv_header_border:       Color{185, 185, 185, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{245, 245, 248, 255}
		tv_row_hover:           Color{215, 230, 248, 255}
		tv_grid:                Color{205, 205, 205, 255}
		tv_rownum_bg:           Color{232, 232, 232, 255}
		pg_header_bg:           Color{222, 222, 222, 255}
		pg_header_text:         Color{28, 28, 28, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{245, 245, 248, 255}
		pg_row_hover:           Color{215, 230, 248, 255}
		pg_group_bg:            Color{230, 230, 234, 255}
		pg_group_text:          Color{50, 50, 50, 255}
		pg_grid:                Color{205, 205, 205, 255}
		tab_inactive_bg:        Color{222, 222, 222, 255}
		tab_active_text:        Color{28, 28, 28, 255}
		tab_inactive_text:      Color{96, 96, 96, 255}
		tab_border:             Color{195, 195, 195, 255}
		menu_bg:                Color{252, 252, 252, 255}
		menu_border:            Color{185, 185, 185, 255}
		menubar_bg:             Color{238, 238, 238, 255}
		tooltip_bg:             Color{252, 252, 240, 255}
		tooltip_border:         Color{180, 180, 155, 255}
		tooltip_text:           Color{28, 28, 28, 255}
		slider_track:           Color{195, 195, 195, 255}
		prog_track:             Color{210, 210, 210, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Windows 11 Dark — dark Mica variant
// ═══════════════════════════════════════════════════════

// Тёмный вариант Windows 11: светло-голубой акцент (96,205,255), острые углы.
pub fn win11_dark_theme() Theme {
	return Theme{
		bg:                     Color{32, 32, 32, 255}
		surface:                Color{40, 40, 40, 255}
		panel_bg:               Color{36, 36, 36, 255}
		border:                 Color{56, 56, 56, 255}
		text_primary:           Color{255, 255, 255, 255}
		text_secondary:         Color{175, 175, 175, 255}
		text_disabled:          Color{100, 100, 100, 255}
		text_hint:              Color{120, 120, 120, 255}
		accent:                 Color{96, 205, 255, 255}
		accent_hover:           Color{118, 214, 255, 255}
		accent_pressed:         Color{76, 194, 255, 255}
		accent_text:            Color{0, 0, 0, 255}
		success:                Color{108, 203, 95, 255}
		warning:                Color{252, 225, 0, 255}
		error_color:            Color{255, 153, 164, 255}
		info:                   Color{96, 205, 255, 255}
		button_bg:              Color{48, 48, 48, 255}
		button_hover:           Color{58, 58, 58, 255}
		button_pressed:         Color{40, 40, 40, 255}
		button_text:            Color{255, 255, 255, 255}
		button_border:          Color{72, 72, 72, 255}
		button_disabled_bg:     Color{42, 42, 42, 255}
		button_disabled_border: Color{52, 52, 52, 255}
		input_bg:               Color{30, 30, 30, 255}
		input_border:           Color{72, 72, 72, 255}
		input_focus:            Color{96, 205, 255, 255}
		scrollbar_bg:           Color{30, 30, 32, 255}
		scrollbar_thumb:        Color{80, 82, 90, 255}
		scrollbar_hover:        Color{115, 118, 128, 255}
		scrollbar_drag:         Color{150, 155, 168, 255}
		cur_line_bg:            Color{50, 52, 58, 255}
		shadow_color:           Color{0, 0, 0, 40}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{26, 26, 28, 255}
		plot_axis:              Color{230, 230, 235, 255}
		plot_grid_major:        Color{58, 58, 62, 255}
		plot_grid_minor:        Color{42, 42, 46, 255}
		plot_label:             Color{170, 170, 180, 255}
		plot_border:            Color{72, 72, 78, 255}
	}
}

// ═══════════════════════════════════════════════════════
// KDE Breeze Light — Plasma 5/6 default light
// ═══════════════════════════════════════════════════════

// KDE Breeze (светлая): голубой акцент Plasma (61,174,233), радиус 6, без теней.
pub fn kde_breeze_theme() Theme {
	return Theme{
		bg:                     Color{239, 240, 241, 255}
		surface:                Color{252, 252, 252, 255}
		panel_bg:               Color{239, 240, 241, 255}
		border:                 Color{188, 190, 191, 255}
		text_primary:           Color{35, 38, 41, 255}
		text_secondary:         Color{99, 104, 109, 255}
		text_disabled:          Color{163, 168, 173, 255}
		text_hint:              Color{136, 140, 144, 255}
		accent:                 Color{61, 174, 233, 255}
		accent_hover:           Color{77, 186, 241, 255}
		accent_pressed:         Color{47, 160, 219, 255}
		accent_text:            Color{252, 252, 252, 255}
		success:                Color{39, 174, 96, 255}
		warning:                Color{246, 116, 0, 255}
		error_color:            Color{218, 68, 83, 255}
		info:                   Color{61, 174, 233, 255}
		button_bg:              Color{245, 245, 245, 255}
		button_hover:           Color{232, 234, 236, 255}
		button_pressed:         Color{218, 220, 224, 255}
		button_text:            Color{35, 38, 41, 255}
		button_border:          Color{170, 172, 174, 255}
		button_disabled_bg:     Color{239, 240, 241, 255}
		button_disabled_border: Color{200, 202, 204, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{170, 172, 174, 255}
		input_focus:            Color{61, 174, 233, 255}
		scrollbar_bg:           Color{228, 230, 232, 255}
		scrollbar_thumb:        Color{150, 155, 162, 255}
		scrollbar_hover:        Color{105, 112, 120, 255}
		scrollbar_drag:         Color{61, 174, 233, 200}
		cur_line_bg:            Color{220, 235, 250, 255}
		shadow_color:           Color{0, 0, 0, 25}
		border_radius:          6.0
		shadow_offset:          0.0
		plot_bg:                Color{252, 252, 252, 255}
		plot_axis:              Color{35, 38, 41, 255}
		plot_grid_major:        Color{200, 205, 210, 255}
		plot_grid_minor:        Color{228, 232, 236, 255}
		plot_label:             Color{80, 85, 90, 255}
		plot_border:            Color{188, 190, 191, 255}
		// Per-widget overrides for better contrast
		lb_header_bg:           Color{218, 220, 222, 255}
		lb_header_text:         Color{35, 38, 41, 255}
		lb_header_border:       Color{165, 168, 172, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{245, 246, 248, 255}
		lb_row_hover:           Color{208, 228, 244, 255}
		lb_grid:                Color{205, 208, 212, 255}
		tv_header_bg:           Color{218, 220, 222, 255}
		tv_header_text:         Color{35, 38, 41, 255}
		tv_header_border:       Color{165, 168, 172, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{245, 246, 248, 255}
		tv_row_hover:           Color{208, 228, 244, 255}
		tv_grid:                Color{205, 208, 212, 255}
		tv_rownum_bg:           Color{228, 230, 232, 255}
		pg_header_bg:           Color{218, 220, 222, 255}
		pg_header_text:         Color{35, 38, 41, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{245, 246, 248, 255}
		pg_row_hover:           Color{208, 228, 244, 255}
		pg_group_bg:            Color{228, 230, 234, 255}
		pg_group_text:          Color{60, 65, 70, 255}
		pg_grid:                Color{205, 208, 212, 255}
		tab_inactive_bg:        Color{218, 220, 222, 255}
		tab_active_text:        Color{35, 38, 41, 255}
		tab_inactive_text:      Color{99, 104, 109, 255}
		tab_border:             Color{175, 178, 182, 255}
		menu_bg:                Color{252, 252, 252, 255}
		menu_border:            Color{175, 178, 182, 255}
		menubar_bg:             Color{239, 240, 241, 255}
		tooltip_bg:             Color{255, 255, 220, 255}
		tooltip_border:         Color{165, 165, 120, 255}
		tooltip_text:           Color{35, 38, 41, 255}
		slider_track:           Color{188, 190, 192, 255}
		prog_track:             Color{205, 208, 212, 255}
	}
}

// ═══════════════════════════════════════════════════════
// KDE Breeze Dark — Plasma dark variant
// ═══════════════════════════════════════════════════════

// KDE Breeze (тёмная): тот же акцент; радиус скругления здесь 0, в отличие от светлого варианта (6).
pub fn kde_breeze_dark_theme() Theme {
	return Theme{
		bg:                     Color{49, 54, 59, 255}
		surface:                Color{35, 38, 41, 255}
		panel_bg:               Color{42, 46, 50, 255}
		border:                 Color{72, 77, 82, 255}
		text_primary:           Color{239, 240, 241, 255}
		text_secondary:         Color{163, 168, 173, 255}
		text_disabled:          Color{99, 104, 109, 255}
		text_hint:              Color{120, 125, 130, 255}
		accent:                 Color{61, 174, 233, 255}
		accent_hover:           Color{77, 186, 241, 255}
		accent_pressed:         Color{47, 160, 219, 255}
		accent_text:            Color{252, 252, 252, 255}
		success:                Color{39, 174, 96, 255}
		warning:                Color{246, 116, 0, 255}
		error_color:            Color{218, 68, 83, 255}
		info:                   Color{61, 174, 233, 255}
		button_bg:              Color{52, 57, 62, 255}
		button_hover:           Color{62, 67, 72, 255}
		button_pressed:         Color{42, 47, 52, 255}
		button_text:            Color{239, 240, 241, 255}
		button_border:          Color{72, 77, 82, 255}
		button_disabled_bg:     Color{42, 46, 50, 255}
		button_disabled_border: Color{58, 63, 68, 255}
		input_bg:               Color{35, 38, 41, 255}
		input_border:           Color{72, 77, 82, 255}
		input_focus:            Color{61, 174, 233, 255}
		scrollbar_bg:           Color{38, 42, 46, 255}
		scrollbar_thumb:        Color{80, 88, 96, 255}
		scrollbar_hover:        Color{110, 120, 132, 255}
		scrollbar_drag:         Color{61, 174, 233, 200}
		cur_line_bg:            Color{44, 50, 58, 255}
		shadow_color:           Color{0, 0, 0, 60}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{31, 34, 37, 255}
		plot_axis:              Color{239, 240, 241, 255}
		plot_grid_major:        Color{72, 77, 82, 255}
		plot_grid_minor:        Color{52, 56, 60, 255}
		plot_label:             Color{175, 180, 185, 255}
		plot_border:            Color{82, 87, 92, 255}
	}
}

// ═══════════════════════════════════════════════════════
// GTK Adwaita Light — GNOME default
// ═══════════════════════════════════════════════════════

// GTK/GNOME Adwaita (светлая): синий акцент (53,132,228), радиус 6, без теней.
pub fn gtk_adwaita_theme() Theme {
	return Theme{
		bg:                     Color{250, 250, 250, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{242, 242, 242, 255}
		border:                 Color{205, 205, 205, 255}
		text_primary:           Color{46, 46, 46, 255}
		text_secondary:         Color{105, 104, 110, 255}
		text_disabled:          Color{170, 170, 170, 255}
		text_hint:              Color{145, 145, 145, 255}
		accent:                 Color{53, 132, 228, 255}
		accent_hover:           Color{70, 145, 237, 255}
		accent_pressed:         Color{36, 114, 209, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{38, 162, 105, 255}
		warning:                Color{229, 165, 10, 255}
		error_color:            Color{224, 27, 36, 255}
		info:                   Color{53, 132, 228, 255}
		button_bg:              Color{248, 248, 248, 255}
		button_hover:           Color{236, 236, 236, 255}
		button_pressed:         Color{218, 218, 218, 255}
		button_text:            Color{46, 46, 46, 255}
		button_border:          Color{185, 185, 185, 255}
		button_disabled_bg:     Color{242, 242, 242, 255}
		button_disabled_border: Color{218, 218, 218, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{185, 185, 185, 255}
		input_focus:            Color{53, 132, 228, 255}
		scrollbar_bg:           Color{235, 235, 235, 255}
		scrollbar_thumb:        Color{148, 148, 155, 255}
		scrollbar_hover:        Color{102, 102, 112, 255}
		scrollbar_drag:         Color{53, 132, 228, 200}
		cur_line_bg:            Color{225, 238, 252, 255}
		shadow_color:           Color{0, 0, 0, 15}
		border_radius:          6.0
		shadow_offset:          0.0
		plot_bg:                Color{253, 253, 253, 255}
		plot_axis:              Color{46, 46, 46, 255}
		plot_grid_major:        Color{215, 215, 215, 255}
		plot_grid_minor:        Color{236, 236, 236, 255}
		plot_label:             Color{100, 100, 105, 255}
		plot_border:            Color{205, 205, 205, 255}
		// Per-widget overrides for better contrast
		lb_header_bg:           Color{225, 225, 225, 255}
		lb_header_text:         Color{46, 46, 46, 255}
		lb_header_border:       Color{180, 180, 180, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{246, 246, 250, 255}
		lb_row_hover:           Color{212, 230, 248, 255}
		lb_grid:                Color{208, 208, 208, 255}
		tv_header_bg:           Color{225, 225, 225, 255}
		tv_header_text:         Color{46, 46, 46, 255}
		tv_header_border:       Color{180, 180, 180, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{246, 246, 250, 255}
		tv_row_hover:           Color{212, 230, 248, 255}
		tv_grid:                Color{208, 208, 208, 255}
		tv_rownum_bg:           Color{232, 232, 232, 255}
		pg_header_bg:           Color{225, 225, 225, 255}
		pg_header_text:         Color{46, 46, 46, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{246, 246, 250, 255}
		pg_row_hover:           Color{212, 230, 248, 255}
		pg_group_bg:            Color{230, 230, 234, 255}
		pg_group_text:          Color{60, 60, 65, 255}
		pg_grid:                Color{208, 208, 208, 255}
		tab_inactive_bg:        Color{220, 220, 220, 255}
		tab_active_text:        Color{46, 46, 46, 255}
		tab_inactive_text:      Color{105, 104, 110, 255}
		tab_border:             Color{188, 188, 188, 255}
		menu_bg:                Color{252, 252, 252, 255}
		menu_border:            Color{185, 185, 185, 255}
		menubar_bg:             Color{242, 242, 242, 255}
		tooltip_bg:             Color{255, 255, 225, 255}
		tooltip_border:         Color{170, 170, 125, 255}
		tooltip_text:           Color{46, 46, 46, 255}
		slider_track:           Color{195, 195, 195, 255}
		prog_track:             Color{210, 210, 210, 255}
	}
}

// ═══════════════════════════════════════════════════════
// GTK Adwaita Dark — GNOME dark variant
// ═══════════════════════════════════════════════════════

// GTK/GNOME Adwaita (тёмная): акцент (120,174,237); радиус 0, в отличие от светлого варианта (6).
pub fn gtk_adwaita_dark_theme() Theme {
	return Theme{
		bg:                     Color{36, 36, 36, 255}
		surface:                Color{48, 48, 48, 255}
		panel_bg:               Color{42, 42, 42, 255}
		border:                 Color{70, 70, 70, 255}
		text_primary:           Color{255, 255, 255, 255}
		text_secondary:         Color{172, 172, 172, 255}
		text_disabled:          Color{105, 105, 105, 255}
		text_hint:              Color{128, 128, 128, 255}
		accent:                 Color{120, 174, 237, 255}
		accent_hover:           Color{140, 188, 244, 255}
		accent_pressed:         Color{100, 160, 225, 255}
		accent_text:            Color{0, 0, 0, 255}
		success:                Color{87, 227, 137, 255}
		warning:                Color{248, 228, 92, 255}
		error_color:            Color{255, 123, 99, 255}
		info:                   Color{120, 174, 237, 255}
		button_bg:              Color{58, 58, 58, 255}
		button_hover:           Color{68, 68, 68, 255}
		button_pressed:         Color{48, 48, 48, 255}
		button_text:            Color{255, 255, 255, 255}
		button_border:          Color{78, 78, 78, 255}
		button_disabled_bg:     Color{42, 42, 42, 255}
		button_disabled_border: Color{58, 58, 58, 255}
		input_bg:               Color{30, 30, 30, 255}
		input_border:           Color{70, 70, 70, 255}
		input_focus:            Color{120, 174, 237, 255}
		scrollbar_bg:           Color{32, 32, 32, 255}
		scrollbar_thumb:        Color{90, 92, 98, 255}
		scrollbar_hover:        Color{130, 134, 142, 255}
		scrollbar_drag:         Color{120, 174, 237, 200}
		cur_line_bg:            Color{48, 54, 64, 255}
		shadow_color:           Color{0, 0, 0, 50}
		border_radius:          0.0
		shadow_offset:          0.0
		plot_bg:                Color{32, 32, 32, 255}
		plot_axis:              Color{245, 245, 245, 255}
		plot_grid_major:        Color{70, 70, 70, 255}
		plot_grid_minor:        Color{50, 50, 50, 255}
		plot_label:             Color{180, 180, 180, 255}
		plot_border:            Color{80, 80, 80, 255}
	}
}

// ═══════════════════════════════════════════════════════
// macOS Light — современный macOS (Big Sur — Sonoma), системная палитра
// Apple: фон окна, systemBlue, системные зелёный/оранжевый/красный,
// серые подписи, скругления. Плоско: vgui без материалов и размытия.
// ═══════════════════════════════════════════════════════

// Современный macOS (светлая): systemBlue (0,122,255), радиус 6, лёгкая тень (offset 1).
pub fn macos_theme() Theme {
	return Theme{
		bg:                     Color{236, 236, 236, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{229, 229, 231, 255}
		border:                 Color{208, 208, 210, 255}
		text_primary:           Color{29, 29, 31, 255}
		text_secondary:         Color{110, 110, 115, 255}
		text_disabled:          Color{180, 180, 185, 255}
		text_hint:              Color{142, 142, 147, 255}
		accent:                 Color{0, 122, 255, 255}
		accent_hover:           Color{26, 136, 255, 255}
		accent_pressed:         Color{0, 100, 214, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{52, 199, 89, 255}
		warning:                Color{255, 149, 0, 255}
		error_color:            Color{255, 59, 48, 255}
		info:                   Color{0, 122, 255, 255}
		button_bg:              Color{255, 255, 255, 255}
		button_hover:           Color{246, 246, 246, 255}
		button_pressed:         Color{224, 224, 226, 255}
		button_text:            Color{29, 29, 31, 255}
		button_border:          Color{196, 196, 199, 255}
		button_disabled_bg:     Color{246, 246, 246, 255}
		button_disabled_border: Color{222, 222, 224, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{196, 196, 199, 255}
		input_focus:            Color{0, 122, 255, 255}
		scrollbar_bg:           Color{240, 240, 240, 255}
		scrollbar_thumb:        Color{194, 194, 196, 255}
		scrollbar_hover:        Color{158, 158, 162, 255}
		scrollbar_drag:         Color{128, 128, 133, 255}
		cur_line_bg:            Color{232, 242, 255, 255}
		shadow_color:           Color{0, 0, 0, 30}
		border_radius:          6.0
		shadow_offset:          1.0
		plot_bg:                Color{255, 255, 255, 255}
		plot_axis:              Color{29, 29, 31, 255}
		plot_grid_major:        Color{218, 218, 220, 255}
		plot_grid_minor:        Color{238, 238, 240, 255}
		plot_label:             Color{110, 110, 115, 255}
		plot_border:            Color{208, 208, 210, 255}
		// Списки и таблицы: белый фон, чередование строк как в Finder
		lb_header_bg:           Color{246, 246, 246, 255}
		lb_header_text:         Color{29, 29, 31, 255}
		lb_header_border:       Color{214, 214, 216, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{244, 245, 245, 255}
		lb_row_hover:           Color{228, 238, 252, 255}
		lb_grid:                Color{226, 226, 228, 255}
		tv_header_bg:           Color{246, 246, 246, 255}
		tv_header_text:         Color{29, 29, 31, 255}
		tv_header_border:       Color{214, 214, 216, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{244, 245, 245, 255}
		tv_row_hover:           Color{228, 238, 252, 255}
		tv_grid:                Color{226, 226, 228, 255}
		tv_rownum_bg:           Color{240, 240, 240, 255}
		pg_header_bg:           Color{246, 246, 246, 255}
		pg_header_text:         Color{29, 29, 31, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{244, 245, 245, 255}
		pg_row_hover:           Color{228, 238, 252, 255}
		pg_group_bg:            Color{236, 236, 238, 255}
		pg_group_text:          Color{60, 60, 67, 255}
		pg_grid:                Color{226, 226, 228, 255}
		tab_inactive_bg:        Color{226, 226, 228, 255}
		tab_active_text:        Color{29, 29, 31, 255}
		tab_inactive_text:      Color{110, 110, 115, 255}
		tab_border:             Color{204, 204, 206, 255}
		menu_bg:                Color{246, 246, 246, 255}
		menu_border:            Color{204, 204, 206, 255}
		menubar_bg:             Color{236, 236, 236, 255}
		tooltip_bg:             Color{250, 250, 250, 255}
		tooltip_border:         Color{200, 200, 202, 255}
		tooltip_text:           Color{29, 29, 31, 255}
		slider_track:           Color{210, 210, 213, 255}
		prog_track:             Color{220, 220, 223, 255}
	}
}

// ═══════════════════════════════════════════════════════
// macOS Dark — современный macOS, тёмное оформление (Dark Aqua):
// systemBlue тёмного режима, системные цвета тёмной палитры
// ═══════════════════════════════════════════════════════

// Тёмный macOS (Dark Aqua): systemBlue тёмного режима (10,132,255), радиус 6.
pub fn macos_dark_theme() Theme {
	return Theme{
		bg:                     Color{50, 50, 52, 255}
		surface:                Color{58, 58, 60, 255}
		panel_bg:               Color{44, 44, 46, 255}
		border:                 Color{66, 66, 69, 255}
		text_primary:           Color{236, 236, 240, 255}
		text_secondary:         Color{152, 152, 157, 255}
		text_disabled:          Color{99, 99, 102, 255}
		text_hint:              Color{128, 128, 133, 255}
		accent:                 Color{10, 132, 255, 255}
		accent_hover:           Color{52, 153, 255, 255}
		accent_pressed:         Color{0, 112, 224, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{48, 209, 88, 255}
		warning:                Color{255, 159, 10, 255}
		error_color:            Color{255, 69, 58, 255}
		info:                   Color{10, 132, 255, 255}
		button_bg:              Color{84, 84, 88, 255}
		button_hover:           Color{96, 96, 100, 255}
		button_pressed:         Color{70, 70, 74, 255}
		button_text:            Color{236, 236, 240, 255}
		button_border:          Color{96, 96, 100, 255}
		button_disabled_bg:     Color{58, 58, 60, 255}
		button_disabled_border: Color{68, 68, 71, 255}
		input_bg:               Color{30, 30, 30, 255}
		input_border:           Color{76, 76, 80, 255}
		input_focus:            Color{10, 132, 255, 255}
		scrollbar_bg:           Color{42, 42, 44, 255}
		scrollbar_thumb:        Color{104, 104, 108, 255}
		scrollbar_hover:        Color{134, 134, 139, 255}
		scrollbar_drag:         Color{164, 164, 170, 255}
		cur_line_bg:            Color{40, 54, 74, 255}
		shadow_color:           Color{0, 0, 0, 70}
		border_radius:          6.0
		shadow_offset:          1.0
		plot_bg:                Color{30, 30, 30, 255}
		plot_axis:              Color{236, 236, 240, 255}
		plot_grid_major:        Color{68, 68, 72, 255}
		plot_grid_minor:        Color{46, 46, 49, 255}
		plot_label:             Color{152, 152, 157, 255}
		plot_border:            Color{80, 80, 84, 255}
		menu_bg:                Color{44, 44, 46, 255}
		menu_border:            Color{72, 72, 76, 255}
		menubar_bg:             Color{40, 40, 42, 255}
		tooltip_bg:             Color{58, 58, 60, 255}
		tooltip_border:         Color{80, 80, 84, 255}
		tooltip_text:           Color{236, 236, 240, 255}
		slider_track:           Color{84, 84, 88, 255}
		prog_track:             Color{70, 70, 74, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Mac OS X Aqua — классическая Mac OS X (10.0 — 10.9): светлый серый
// фон окон, голубой «аква»-акцент и голубые ползунки прокрутки,
// голубое чередование строк списков (как в старом iTunes), жёлтые
// подсказки. Гелевые кнопки и полосатый фон - плоскими цветами.
// ═══════════════════════════════════════════════════════

// Ретро-тема Mac OS X Aqua (10.0-10.9): светло-серый фон, голубая гамма, радиус 8.
pub fn mac_os_x_aqua_theme() Theme {
	return Theme{
		bg:                     Color{232, 232, 232, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{222, 222, 222, 255}
		border:                 Color{150, 150, 150, 255}
		text_primary:           Color{0, 0, 0, 255}
		text_secondary:         Color{76, 76, 76, 255}
		text_disabled:          Color{156, 156, 156, 255}
		text_hint:              Color{128, 128, 128, 255}
		accent:                 Color{56, 117, 215, 255}
		accent_hover:           Color{84, 142, 230, 255}
		accent_pressed:         Color{28, 88, 190, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{60, 160, 60, 255}
		warning:                Color{232, 160, 0, 255}
		error_color:            Color{214, 40, 40, 255}
		info:                   Color{56, 117, 215, 255}
		button_bg:              Color{246, 246, 246, 255}
		button_hover:           Color{226, 236, 252, 255}
		button_pressed:         Color{168, 200, 245, 255}
		button_text:            Color{0, 0, 0, 255}
		button_border:          Color{140, 140, 140, 255}
		button_disabled_bg:     Color{240, 240, 240, 255}
		button_disabled_border: Color{190, 190, 190, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{140, 140, 140, 255}
		input_focus:            Color{110, 160, 235, 255}
		scrollbar_bg:           Color{226, 226, 226, 255}
		scrollbar_thumb:        Color{110, 158, 230, 255}
		scrollbar_hover:        Color{80, 136, 222, 255}
		scrollbar_drag:         Color{50, 110, 210, 255}
		cur_line_bg:            Color{214, 228, 250, 255}
		shadow_color:           Color{0, 0, 0, 40}
		border_radius:          8.0
		shadow_offset:          1.0
		plot_bg:                Color{255, 255, 255, 255}
		plot_axis:              Color{0, 0, 0, 255}
		plot_grid_major:        Color{205, 205, 205, 255}
		plot_grid_minor:        Color{232, 232, 232, 255}
		plot_label:             Color{76, 76, 76, 255}
		plot_border:            Color{150, 150, 150, 255}
		lb_header_bg:           Color{236, 236, 236, 255}
		lb_header_text:         Color{0, 0, 0, 255}
		lb_header_border:       Color{160, 160, 160, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{237, 243, 254, 255}
		lb_row_hover:           Color{210, 225, 250, 255}
		lb_grid:                Color{214, 214, 214, 255}
		tv_header_bg:           Color{236, 236, 236, 255}
		tv_header_text:         Color{0, 0, 0, 255}
		tv_header_border:       Color{160, 160, 160, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{237, 243, 254, 255}
		tv_row_hover:           Color{210, 225, 250, 255}
		tv_grid:                Color{214, 214, 214, 255}
		tv_rownum_bg:           Color{236, 236, 236, 255}
		pg_header_bg:           Color{236, 236, 236, 255}
		pg_header_text:         Color{0, 0, 0, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{237, 243, 254, 255}
		pg_row_hover:           Color{210, 225, 250, 255}
		pg_group_bg:            Color{222, 222, 222, 255}
		pg_group_text:          Color{40, 40, 40, 255}
		pg_grid:                Color{214, 214, 214, 255}
		tab_inactive_bg:        Color{214, 214, 214, 255}
		tab_active_text:        Color{0, 0, 0, 255}
		tab_inactive_text:      Color{76, 76, 76, 255}
		tab_border:             Color{150, 150, 150, 255}
		menu_bg:                Color{248, 248, 248, 255}
		menu_border:            Color{160, 160, 160, 255}
		menubar_bg:             Color{240, 240, 240, 255}
		tooltip_bg:             Color{255, 255, 199, 255}
		tooltip_border:         Color{170, 170, 120, 255}
		tooltip_text:           Color{0, 0, 0, 255}
		slider_track:           Color{190, 190, 190, 255}
		prog_track:             Color{214, 214, 214, 255}
	}
}

// ═══════════════════════════════════════════════════════
// Mac OS 9 Platinum — Mac OS 8/9: платиново-серый (#DDDDDD) фон, чёрные
// рамки кнопок, лавандовые ползунки прокрутки и выделение (#CCCCFF),
// сине-фиолетовый акцент, жёлтые подсказки Balloon Help, малые
// скругления.
// ═══════════════════════════════════════════════════════

// Ретро-тема Mac OS 9 Platinum: платиново-серая, лавандовое выделение, чёрные рамки, радиус 3.
pub fn mac_os_9_platinum_theme() Theme {
	return Theme{
		bg:                     Color{221, 221, 221, 255}
		surface:                Color{255, 255, 255, 255}
		panel_bg:               Color{204, 204, 204, 255}
		border:                 Color{102, 102, 102, 255}
		text_primary:           Color{0, 0, 0, 255}
		text_secondary:         Color{68, 68, 68, 255}
		text_disabled:          Color{153, 153, 153, 255}
		text_hint:              Color{119, 119, 119, 255}
		accent:                 Color{99, 99, 206, 255}
		accent_hover:           Color{122, 122, 222, 255}
		accent_pressed:         Color{76, 76, 180, 255}
		accent_text:            Color{255, 255, 255, 255}
		success:                Color{0, 136, 0, 255}
		warning:                Color{204, 136, 0, 255}
		error_color:            Color{204, 0, 0, 255}
		info:                   Color{99, 99, 206, 255}
		button_bg:              Color{238, 238, 238, 255}
		button_hover:           Color{248, 248, 248, 255}
		button_pressed:         Color{170, 170, 170, 255}
		button_text:            Color{0, 0, 0, 255}
		button_border:          Color{34, 34, 34, 255}
		button_disabled_bg:     Color{221, 221, 221, 255}
		button_disabled_border: Color{153, 153, 153, 255}
		input_bg:               Color{255, 255, 255, 255}
		input_border:           Color{102, 102, 102, 255}
		input_focus:            Color{99, 99, 206, 255}
		scrollbar_bg:           Color{187, 187, 187, 255}
		scrollbar_thumb:        Color{204, 204, 255, 255}
		scrollbar_hover:        Color{170, 170, 238, 255}
		scrollbar_drag:         Color{136, 136, 221, 255}
		cur_line_bg:            Color{221, 221, 255, 255}
		shadow_color:           Color{0, 0, 0, 60}
		border_radius:          3.0
		shadow_offset:          1.0
		plot_bg:                Color{255, 255, 255, 255}
		plot_axis:              Color{0, 0, 0, 255}
		plot_grid_major:        Color{187, 187, 187, 255}
		plot_grid_minor:        Color{221, 221, 221, 255}
		plot_label:             Color{68, 68, 68, 255}
		plot_border:            Color{102, 102, 102, 255}
		lb_header_bg:           Color{221, 221, 221, 255}
		lb_header_text:         Color{0, 0, 0, 255}
		lb_header_border:       Color{102, 102, 102, 255}
		lb_row_bg:              Color{255, 255, 255, 255}
		lb_row_alt_bg:          Color{255, 255, 255, 255}
		lb_row_hover:           Color{221, 221, 255, 255}
		lb_grid:                Color{204, 204, 204, 255}
		tv_header_bg:           Color{221, 221, 221, 255}
		tv_header_text:         Color{0, 0, 0, 255}
		tv_header_border:       Color{102, 102, 102, 255}
		tv_row_bg:              Color{255, 255, 255, 255}
		tv_row_alt_bg:          Color{255, 255, 255, 255}
		tv_row_hover:           Color{221, 221, 255, 255}
		tv_grid:                Color{204, 204, 204, 255}
		tv_rownum_bg:           Color{221, 221, 221, 255}
		pg_header_bg:           Color{221, 221, 221, 255}
		pg_header_text:         Color{0, 0, 0, 255}
		pg_row_bg:              Color{255, 255, 255, 255}
		pg_row_alt_bg:          Color{255, 255, 255, 255}
		pg_row_hover:           Color{221, 221, 255, 255}
		pg_group_bg:            Color{204, 204, 204, 255}
		pg_group_text:          Color{0, 0, 0, 255}
		pg_grid:                Color{204, 204, 204, 255}
		tab_inactive_bg:        Color{187, 187, 187, 255}
		tab_active_text:        Color{0, 0, 0, 255}
		tab_inactive_text:      Color{68, 68, 68, 255}
		tab_border:             Color{102, 102, 102, 255}
		menu_bg:                Color{238, 238, 238, 255}
		menu_border:            Color{0, 0, 0, 255}
		menubar_bg:             Color{238, 238, 238, 255}
		tooltip_bg:             Color{255, 255, 204, 255}
		tooltip_border:         Color{0, 0, 0, 255}
		tooltip_text:           Color{0, 0, 0, 255}
		slider_track:           Color{170, 170, 170, 255}
		prog_track:             Color{187, 187, 187, 255}
	}
}
