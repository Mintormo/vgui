module vgui

// ═══════════════════════════════════════════════════════
// PropertyGrid — two-column property editor widget
//
// Features:
//   - Hierarchical groups (collapsible)
//   - Inline editing (Enter / F2 / double-click)
//   - Built-in dialogs for color, date, file/folder properties
//   - Color-typed cells show their value as background
//   - Keyboard navigation:
//       Up / Down       — move selection
//       Left  on group  — collapse
//       Right on group  — expand
//       Left  on leaf   — jump to parent group (if any)
//       Right on leaf   — no-op
//       Home / End      — first / last visible row
//       Enter / F2      — start editing (or toggle bool / group)
//       Escape          — cancel editing
//   - Splitter between Property/Value columns (drag)
//   - Vertical scroll (mouse wheel + scrollbar)
//   - Registered in FocusManager → participates in Tab chain
// ═══════════════════════════════════════════════════════

pub enum PropertyKind {
	group
	string_val
	int_val
	float_val
	bool_val
	color_val
	date_val
	file_path
	folder_path
	choice
}

@[heap]
pub struct Property {
pub mut:
	type_tag   int = kind_property // тег типа, см. widget_tag.v
	name       string
	kind       PropertyKind
	str_val    string
	int_val    int
	float_val  f32
	bool_val   bool
	color_val  Color
	year       int
	month      int
	day        int
	choices    []string
	choice_idx int
	children   []&Property
	expanded   bool      = true
	parent     &Property = unsafe { nil }
	user_data  voidptr   = unsafe { nil }
	hovered    bool
	readonly   bool
}

// ─── Property constructors ─────────────────────────────

pub fn property_string(name string, value string) &Property {
	return &Property{
		name:    name
		kind:    .string_val
		str_val: value
	}
}

pub fn property_int(name string, value int) &Property {
	return &Property{
		name:    name
		kind:    .int_val
		int_val: value
	}
}

pub fn property_float(name string, value f32) &Property {
	return &Property{
		name:      name
		kind:      .float_val
		float_val: value
	}
}

pub fn property_bool(name string, value bool) &Property {
	return &Property{
		name:     name
		kind:     .bool_val
		bool_val: value
	}
}

pub fn property_color(name string, value Color) &Property {
	return &Property{
		name:      name
		kind:      .color_val
		color_val: value
	}
}

pub fn property_date(name string, year int, month int, day int) &Property {
	return &Property{
		name:  name
		kind:  .date_val
		year:  year
		month: month
		day:   day
	}
}

pub fn property_file_path(name string, path string) &Property {
	return &Property{
		name:    name
		kind:    .file_path
		str_val: path
	}
}

pub fn property_folder_path(name string, path string) &Property {
	return &Property{
		name:    name
		kind:    .folder_path
		str_val: path
	}
}

pub fn property_choice(name string, choices []string, selected int) &Property {
	return &Property{
		name:       name
		kind:       .choice
		choices:    choices.clone()
		choice_idx: selected
	}
}

pub fn property_group(name string) &Property {
	return &Property{
		name:     name
		kind:     .group
		expanded: true
	}
}

// ─── Property hierarchy methods ────────────────────────

pub fn (mut p Property) add(child &Property) {
	mut c := unsafe { child }
	c.parent = unsafe { p }
	p.children << unsafe { child }
}

pub fn (mut p Property) add_string(name string, value string) &Property {
	c := property_string(name, value)
	p.add(c)
	return c
}

pub fn (mut p Property) add_int(name string, value int) &Property {
	c := property_int(name, value)
	p.add(c)
	return c
}

pub fn (mut p Property) add_float(name string, value f32) &Property {
	c := property_float(name, value)
	p.add(c)
	return c
}

pub fn (mut p Property) add_bool(name string, value bool) &Property {
	c := property_bool(name, value)
	p.add(c)
	return c
}

pub fn (mut p Property) add_color(name string, value Color) &Property {
	c := property_color(name, value)
	p.add(c)
	return c
}

pub fn (mut p Property) add_date(name string, year int, month int, day int) &Property {
	c := property_date(name, year, month, day)
	p.add(c)
	return c
}

pub fn (mut p Property) add_file_path(name string, path string) &Property {
	c := property_file_path(name, path)
	p.add(c)
	return c
}

pub fn (mut p Property) add_folder_path(name string, path string) &Property {
	c := property_folder_path(name, path)
	p.add(c)
	return c
}

pub fn (mut p Property) add_choice(name string, choices []string, selected int) &Property {
	c := property_choice(name, choices, selected)
	p.add(c)
	return c
}

pub fn (mut p Property) add_group(name string) &Property {
	c := property_group(name)
	p.add(c)
	return c
}

// ═══════════════════════════════════════════════════════
// PropertyGrid widget
// ═══════════════════════════════════════════════════════

const pg_default_split = f32(0.4)
const pg_min_col_width = f32(50)
const pg_splitter_width = f32(6)
const pg_row_height = f32(26)
const pg_indent = f32(16)
const pg_arrow_size = f32(10)
const pg_pad_h = f32(6)
const pg_btn_size = f32(20)
const pg_sb_w = f32(12)

@[heap]
pub struct PropertyGrid {
pub mut:
	type_tag int = kind_property_grid // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel                 bool = true
	bounds                Rect
	roots                 []&Property
	visible               bool = true
	enabled               bool = true
	hovered               bool
	focused               bool
	focus_anim            Anim = anim_smooth(anim_tau_focus)
	focus_group           int
	selected              &Property = unsafe { nil }
	split_ratio           f32       = pg_default_split
	row_height            f32       = pg_row_height
	pad                   f32       = 2
	header_height         f32       = 24
	show_header           bool      = true
	scroll_y              f32
	scroll_speed          f32 = 30
	splitter_dragging     bool
	splitter_hovered      bool
	editing               bool
	edit_prop             &Property  = unsafe { nil }
	edit_text_input       &TextInput = unsafe { nil }
	edit_combo            &ComboBox  = unsafe { nil }
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	app_ref               &App           = unsafe { nil }
	bg_color              Color          = Color{0, 0, 0, 0}
	header_bg             Color          = Color{0, 0, 0, 0}
	header_text           Color          = Color{0, 0, 0, 0}
	row_bg_even           Color          = Color{0, 0, 0, 0}
	row_bg_odd            Color          = Color{0, 0, 0, 0}
	row_text              Color          = Color{0, 0, 0, 0}
	row_hover_bg          Color          = Color{0, 0, 0, 0}
	row_sel_bg            Color          = Color{0, 0, 0, 0}
	grid_color            Color          = Color{0, 0, 0, 0}
	splitter_color        Color          = Color{0, 0, 0, 0}
	group_bg              Color          = Color{0, 0, 0, 0}
	on_change             fn (&Property) = unsafe { nil }
}

pub fn property_grid() &PropertyGrid {
	return &PropertyGrid{}
}

// ─── Public API ────────────────────────────────────────

pub fn (mut pg PropertyGrid) set_app(app &App) {
	pg.app_ref = unsafe { app }
}

pub fn (mut pg PropertyGrid) add(prop &Property) {
	pg.roots << unsafe { prop }
}

pub fn (mut pg PropertyGrid) add_string(name string, value string) &Property {
	p := property_string(name, value)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_int(name string, value int) &Property {
	p := property_int(name, value)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_float(name string, value f32) &Property {
	p := property_float(name, value)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_bool(name string, value bool) &Property {
	p := property_bool(name, value)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_color(name string, value Color) &Property {
	p := property_color(name, value)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_date(name string, year int, month int, day int) &Property {
	p := property_date(name, year, month, day)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_file_path(name string, path string) &Property {
	p := property_file_path(name, path)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_folder_path(name string, path string) &Property {
	p := property_folder_path(name, path)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_choice(name string, choices []string, selected int) &Property {
	p := property_choice(name, choices, selected)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) add_group(name string) &Property {
	p := property_group(name)
	pg.add(p)
	return p
}

pub fn (mut pg PropertyGrid) clear() {
	pg.cancel_edit()
	pg.roots.clear()
	pg.selected = unsafe { nil }
	pg.scroll_y = 0
}

pub fn (pg &PropertyGrid) find(name string) &Property {
	for r in pg.roots {
		if found := pg_find_recursive(r, name) {
			return found
		}
	}
	return unsafe { nil }
}

fn pg_find_recursive(p &Property, name string) ?&Property {
	if p.name == name {
		return unsafe { p }
	}
	for ch in p.children {
		if found := pg_find_recursive(ch, name) {
			return found
		}
	}
	return none
}

// ─── Get/Set values by name ────────────────────────────

pub fn (pg &PropertyGrid) get_string(name string) string {
	p := pg.find(name)
	if unsafe { p == nil } {
		return ''
	}
	return p.str_val
}

pub fn (pg &PropertyGrid) get_int(name string) int {
	p := pg.find(name)
	if unsafe { p == nil } {
		return 0
	}
	return p.int_val
}

pub fn (pg &PropertyGrid) get_float(name string) f32 {
	p := pg.find(name)
	if unsafe { p == nil } {
		return 0
	}
	return p.float_val
}

pub fn (pg &PropertyGrid) get_bool(name string) bool {
	p := pg.find(name)
	if unsafe { p == nil } {
		return false
	}
	return p.bool_val
}

pub fn (pg &PropertyGrid) get_color(name string) Color {
	p := pg.find(name)
	if unsafe { p == nil } {
		return Color{}
	}
	return p.color_val
}

pub fn (pg &PropertyGrid) get_date(name string) (int, int, int) {
	p := pg.find(name)
	if unsafe { p == nil } {
		return 0, 0, 0
	}
	return p.year, p.month, p.day
}

pub fn (pg &PropertyGrid) get_choice(name string) int {
	p := pg.find(name)
	if unsafe { p == nil } {
		return -1
	}
	return p.choice_idx
}

pub fn (mut pg PropertyGrid) set_string(name string, value string) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.str_val = value
	}
}

pub fn (mut pg PropertyGrid) set_int(name string, value int) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.int_val = value
	}
}

pub fn (mut pg PropertyGrid) set_float(name string, value f32) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.float_val = value
	}
}

pub fn (mut pg PropertyGrid) set_bool(name string, value bool) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.bool_val = value
	}
}

pub fn (mut pg PropertyGrid) set_color(name string, value Color) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.color_val = value
	}
}

pub fn (mut pg PropertyGrid) set_date(name string, year int, month int, day int) {
	mut p := pg.find(name)
	if unsafe { p != nil } {
		p.year = year
		p.month = month
		p.day = day
	}
}

// ─── Editing helpers ───────────────────────────────────

fn (mut pg PropertyGrid) cancel_edit() {
	if pg.editing && unsafe { pg.edit_text_input != nil } {
		mut ti := pg.edit_text_input
		ti.focused = false
	}
	pg.editing = false
	pg.edit_prop = unsafe { nil }
	pg.edit_text_input = unsafe { nil }
	pg.edit_combo = unsafe { nil }
}

fn (mut pg PropertyGrid) commit_edit() {
	if !pg.editing {
		return
	}
	if unsafe { pg.edit_prop != nil } && unsafe { pg.edit_text_input != nil } {
		mut p := unsafe { pg.edit_prop }
		new_text := pg.edit_text_input.get_text()
		match p.kind {
			.string_val, .file_path, .folder_path {
				p.str_val = new_text
			}
			.int_val {
				p.int_val = new_text.int()
			}
			.float_val {
				p.float_val = new_text.f32()
			}
			else {}
		}

		if pg.on_change != unsafe { nil } {
			pg.on_change(pg.edit_prop)
		}
	}
	pg.cancel_edit()
}

fn (pg &PropertyGrid) editor_rect() Rect {
	if !pg.editing || unsafe { pg.edit_prop == nil } {
		return Rect{}
	}
	flat := pg.build_flat()
	mut idx := -1
	for i, row in flat {
		if row.prop == pg.edit_prop {
			idx = i
			break
		}
	}
	if idx < 0 {
		return Rect{}
	}
	dr := pg.data_rect()
	row_y := dr.y + f32(idx) * pg.row_height - pg.scroll_y
	sx := pg.split_x()
	return Rect{sx + 1, row_y + 1, dr.x + dr.w - sx - 2, pg.row_height - 2}
}

fn (pg &PropertyGrid) editor_rect_for(prop &Property) Rect {
	flat := pg.build_flat()
	mut idx := -1
	for i, row in flat {
		if row.prop == prop {
			idx = i
			break
		}
	}
	if idx < 0 {
		return Rect{}
	}
	dr := pg.data_rect()
	row_y := dr.y + f32(idx) * pg.row_height - pg.scroll_y
	sx := pg.split_x()
	return Rect{sx + 1, row_y + 1, dr.x + dr.w - sx - 2, pg.row_height - 2}
}

// ─── Find App reference ────────────────────────────────

fn (pg &PropertyGrid) find_app(active_app &App) &App {
	if unsafe { active_app != nil } {
		return unsafe { active_app }
	}
	if unsafe { pg.app_ref != nil } {
		return pg.app_ref
	}
	return unsafe { nil }
}

// ─── Open dialogs for special property types ──────────

fn (mut pg PropertyGrid) open_color_dialog(prop &Property, app &App) {
	if unsafe { app == nil } {
		return
	}
	mut p := unsafe { prop }

	// Find parent window
	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return
	}
	mut parent := unsafe { &Window(nil) }
	for w in app.windows {
		if w.open && unsafe { &w.ctx == ctx_ptr } {
			parent = unsafe { w }
			break
		}
	}
	if unsafe { parent == nil } {
		for d in app.dialogs {
			if d.is_open() && unsafe { &d.win.ctx == ctx_ptr } {
				parent = unsafe { &d.win }
				break
			}
		}
	}
	if unsafe { parent == nil } {
		return
	}

	mut mapp := unsafe { &App(app) }
	chosen, confirmed := color_dialog(parent, mut mapp, ColorDialogConfig{ color: p.color_val })
	if confirmed {
		p.color_val = chosen
		if pg.on_change != unsafe { nil } {
			pg.on_change(p)
		}
	}
}

fn (mut pg PropertyGrid) open_date_dialog(prop &Property, app &App) {
	if unsafe { app == nil } {
		return
	}
	mut p := unsafe { prop }

	// Use DatePicker's internal dialog
	mut dp := date_picker_ymd(p.year, p.month, p.day)
	dp.on_change = fn [mut pg, mut p] (y int, m int, d int) {
		p.year = y
		p.month = m
		p.day = d
		if pg.on_change != unsafe { nil } {
			pg.on_change(p)
		}
	}
	dp_open_dialog(mut dp, app)
}

fn (mut pg PropertyGrid) open_file_dialog(prop &Property, app &App) {
	if unsafe { app == nil } {
		return
	}
	mut p := unsafe { prop }

	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return
	}
	mut parent := unsafe { &Window(nil) }
	for w in app.windows {
		if w.open && unsafe { &w.ctx == ctx_ptr } {
			parent = unsafe { w }
			break
		}
	}
	if unsafe { parent == nil } {
		for d in app.dialogs {
			if d.is_open() && unsafe { &d.win.ctx == ctx_ptr } {
				parent = unsafe { &d.win }
				break
			}
		}
	}
	if unsafe { parent == nil } {
		return
	}

	mut mapp := unsafe { &App(app) }
	result := open_file_dialog(parent, mut mapp, FileDialogConfig{
		start_dir: p.str_val
		mode:      .open
	})
	if result.len > 0 {
		p.str_val = result
		if pg.on_change != unsafe { nil } {
			pg.on_change(p)
		}
	}
}

fn (mut pg PropertyGrid) open_folder_dialog(prop &Property, app &App) {
	if unsafe { app == nil } {
		return
	}
	mut p := unsafe { prop }

	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return
	}
	mut parent := unsafe { &Window(nil) }
	for w in app.windows {
		if w.open && unsafe { &w.ctx == ctx_ptr } {
			parent = unsafe { w }
			break
		}
	}
	if unsafe { parent == nil } {
		for d in app.dialogs {
			if d.is_open() && unsafe { &d.win.ctx == ctx_ptr } {
				parent = unsafe { &d.win }
				break
			}
		}
	}
	if unsafe { parent == nil } {
		return
	}

	mut mapp := unsafe { &App(app) }
	result := select_folder_dialog(parent, mut mapp, FileDialogConfig{
		start_dir: p.str_val
		mode:      .folder
	})
	if result.len > 0 {
		p.str_val = result
		if pg.on_change != unsafe { nil } {
			pg.on_change(p)
		}
	}
}

// Begin editing a property. For special types (color, date, file, folder)
// opens a corresponding dialog instead of inline edit.
fn (mut pg PropertyGrid) begin_edit(prop &Property, app &App) {
	if unsafe { prop == nil } {
		return
	}
	if prop.kind == .group || prop.kind == .bool_val || prop.readonly {
		return
	}

	// Special types: open dialogs instead of inline editor
	match prop.kind {
		.color_val {
			pg.open_color_dialog(prop, app)
			return
		}
		.date_val {
			pg.open_date_dialog(prop, app)
			return
		}
		.file_path {
			pg.open_file_dialog(prop, app)
			return
		}
		.folder_path {
			pg.open_folder_dialog(prop, app)
			return
		}
		else {}
	}

	pg.cancel_edit()
	pg.editing = true
	pg.edit_prop = unsafe { prop }
	mut ti := text_input('')
	ti.pad = 3
	ti.set_text(pg_format_value(prop))
	ti.focus_group = pg.focus_group
	ti.sel_a = 0
	ti.sel_b = ti.buf.len
	ti.cur = ti.buf.len
	ti.bounds = pg.editor_rect_for(prop)
	pg.edit_text_input = ti

	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr != nil } {
		mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
		ctx_mut.focus.focus_text_input(ti, pg.focus_group)
	}
	ti.focused = true
}

// ─── Flatten visible properties ────────────────────────

struct PgFlatRow {
	prop  &Property
	depth int
}

fn (pg &PropertyGrid) build_flat() []PgFlatRow {
	mut result := []PgFlatRow{cap: 32}
	for r in pg.roots {
		pg_flatten(r, 0, mut result)
	}
	return result
}

fn pg_flatten(p &Property, depth int, mut out []PgFlatRow) {
	out << PgFlatRow{
		prop:  p
		depth: depth
	}
	if p.kind == .group && p.expanded {
		for ch in p.children {
			pg_flatten(ch, depth + 1, mut out)
		}
	}
}

// ─── Geometry ──────────────────────────────────────────

fn (pg &PropertyGrid) inner_rect() Rect {
	return pg.bounds.shrunk(pg.pad)
}

fn (pg &PropertyGrid) header_rect() Rect {
	if !pg.show_header {
		return Rect{}
	}
	inner := pg.inner_rect()
	return Rect{inner.x, inner.y, inner.w, pg.header_height}
}

fn (pg &PropertyGrid) data_rect() Rect {
	inner := pg.inner_rect()
	hdr_h := if pg.show_header { pg.header_height } else { f32(0) }
	mut w := inner.w
	if pg.has_vsb() {
		w -= pg_sb_w
	}
	return Rect{inner.x, inner.y + hdr_h, w, inner.h - hdr_h}
}

fn (pg &PropertyGrid) total_height() f32 {
	flat := pg.build_flat()
	return f32(flat.len) * pg.row_height
}

fn (pg &PropertyGrid) max_scroll() f32 {
	dr := pg.data_rect()
	return max_f32(0, pg.total_height() - dr.h)
}

fn (pg &PropertyGrid) has_vsb() bool {
	inner := pg.inner_rect()
	hdr_h := if pg.show_header { pg.header_height } else { f32(0) }
	return pg.total_height() > inner.h - hdr_h
}

fn (pg &PropertyGrid) split_x() f32 {
	inner := pg.inner_rect()
	mut data_w := inner.w
	if pg.has_vsb() {
		data_w -= pg_sb_w
	}
	return inner.x + clamp_f32(data_w * pg.split_ratio, pg_min_col_width, data_w - pg_min_col_width)
}

fn (pg &PropertyGrid) splitter_rect() Rect {
	inner := pg.inner_rect()
	sx := pg.split_x()
	return Rect{sx - pg_splitter_width * 0.5, inner.y, pg_splitter_width, inner.h}
}

fn (pg &PropertyGrid) vsb_rects() (Rect, Rect) {
	if !pg.has_vsb() {
		return Rect{}, Rect{}
	}
	dr := pg.data_rect()
	inner := pg.inner_rect()
	track := Rect{
		x: inner.x + inner.w - pg_sb_w
		y: dr.y
		w: pg_sb_w
		h: dr.h
	}
	ch := pg.total_height()
	thumb_h := max_f32(20, dr.h * (dr.h / ch))
	ms := pg.max_scroll()
	ratio := if ms > 0 { pg.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 1
		y: track.y + ratio * (dr.h - thumb_h)
		w: pg_sb_w - 2
		h: thumb_h
	}
	return track, thumb
}

// ─── Hit testing ───────────────────────────────────────

fn (pg &PropertyGrid) hit_row(my f32) int {
	dr := pg.data_rect()
	if my < dr.y || my > dr.y + dr.h {
		return -1
	}
	rel_y := my - dr.y + pg.scroll_y
	idx := int(rel_y / pg.row_height)
	flat := pg.build_flat()
	if idx >= 0 && idx < flat.len {
		return idx
	}
	return -1
}

fn (pg &PropertyGrid) hit_arrow(mx f32, my f32) int {
	idx := pg.hit_row(my)
	if idx < 0 {
		return -1
	}
	flat := pg.build_flat()
	row := flat[idx]
	if row.prop.kind != .group {
		return -1
	}
	dr := pg.data_rect()
	row_y := dr.y + f32(idx) * pg.row_height - pg.scroll_y
	arrow_x := dr.x + f32(row.depth) * pg_indent + 2
	if mx >= arrow_x && mx < arrow_x + pg_arrow_size + 4 && my >= row_y
		&& my < row_y + pg.row_height {
		return idx
	}
	return -1
}

fn (pg &PropertyGrid) row_rect(idx int) Rect {
	dr := pg.data_rect()
	return Rect{dr.x, dr.y + f32(idx) * pg.row_height - pg.scroll_y, dr.w, pg.row_height}
}

// Hit test for the value column area (right of splitter, within row)
fn (pg &PropertyGrid) hit_value_area(mx f32, my f32) int {
	idx := pg.hit_row(my)
	if idx < 0 {
		return -1
	}
	sx := pg.split_x()
	if mx < sx {
		return -1
	}
	return idx
}

// ─── Format value ──────────────────────────────────────

fn pg_format_value(p &Property) string {
	return match p.kind {
		.group {
			''
		}
		.string_val {
			p.str_val
		}
		.int_val {
			'${p.int_val}'
		}
		.float_val {
			slider_format_f32(p.float_val, 2)
		}
		.bool_val {
			if p.bool_val {
				'true'
			} else {
				'false'
			}
		}
		.color_val {
			'#${cp_hex2(p.color_val.r)}${cp_hex2(p.color_val.g)}${cp_hex2(p.color_val.b)}'
		}
		.date_val {
			'${p.year}-${dp_pad2(p.month)}-${dp_pad2(p.day)}'
		}
		.file_path, .folder_path {
			p.str_val
		}
		.choice {
			if p.choice_idx >= 0 && p.choice_idx < p.choices.len {
				p.choices[p.choice_idx]
			} else {
				''
			}
		}
	}
}

// ─── Effective colors ──────────────────────────────────

fn (pg &PropertyGrid) eff_bg(ctx &RenderContext) Color {
	if pg.bg_color.a > 0 {
		return pg.bg_color
	}
	return ctx.theme.eff_pg_row_bg()
}

fn (pg &PropertyGrid) eff_header_bg(ctx &RenderContext) Color {
	if pg.header_bg.a > 0 {
		return pg.header_bg
	}
	return ctx.theme.eff_pg_header_bg()
}

fn (pg &PropertyGrid) eff_header_text(ctx &RenderContext) Color {
	if pg.header_text.a > 0 {
		return pg.header_text
	}
	return ctx.theme.eff_pg_header_text()
}

fn (pg &PropertyGrid) eff_row_bg(ctx &RenderContext, idx int) Color {
	is_even := idx % 2 == 0
	if is_even && pg.row_bg_even.a > 0 {
		return pg.row_bg_even
	}
	if !is_even && pg.row_bg_odd.a > 0 {
		return pg.row_bg_odd
	}
	if is_even {
		return ctx.theme.eff_pg_row_bg()
	}
	return ctx.theme.eff_pg_row_alt_bg()
}

fn (pg &PropertyGrid) eff_row_text(ctx &RenderContext) Color {
	if pg.row_text.a > 0 {
		return pg.row_text
	}
	return ctx.theme.eff_pg_row_text()
}

fn (pg &PropertyGrid) eff_row_hover_bg(ctx &RenderContext) Color {
	if pg.row_hover_bg.a > 0 {
		return pg.row_hover_bg
	}
	return ctx.theme.eff_pg_row_hover()
}

fn (pg &PropertyGrid) eff_row_sel_bg(ctx &RenderContext) Color {
	if pg.row_sel_bg.a > 0 {
		return pg.row_sel_bg
	}
	return ctx.theme.eff_pg_row_selected()
}

fn (pg &PropertyGrid) eff_grid_color(ctx &RenderContext) Color {
	if pg.grid_color.a > 0 {
		return pg.grid_color
	}
	return ctx.theme.eff_pg_grid()
}

fn (pg &PropertyGrid) eff_splitter_color(ctx &RenderContext) Color {
	if pg.splitter_color.a > 0 {
		return pg.splitter_color
	}
	return ctx.theme.eff_pg_grid()
}

fn (pg &PropertyGrid) eff_group_bg(ctx &RenderContext) Color {
	if pg.group_bg.a > 0 {
		return pg.group_bg
	}
	return ctx.theme.eff_pg_header_bg()
}

// ─── Helpers for keyboard navigation ───────────────────

fn (pg &PropertyGrid) flat_index_of(prop &Property) int {
	flat := pg.build_flat()
	for i, row in flat {
		if row.prop == prop {
			return i
		}
	}
	return -1
}

fn (mut pg PropertyGrid) ensure_visible() {
	if unsafe { pg.selected == nil } {
		return
	}
	idx := pg.flat_index_of(pg.selected)
	if idx < 0 {
		return
	}
	dr := pg.data_rect()
	item_top := f32(idx) * pg.row_height
	item_bot := item_top + pg.row_height
	if item_top < pg.scroll_y {
		pg.scroll_y = item_top
	}
	if item_bot > pg.scroll_y + dr.h {
		pg.scroll_y = item_bot - dr.h
	}
	pg.scroll_y = clamp_f32(pg.scroll_y, 0, pg.max_scroll())
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut pg PropertyGrid) draw(mut ctx RenderContext) {
	if !pg.visible {
		return
	}
	if !ctx.is_in_clip(pg.bounds) {
		return
	}

	// Register self in FocusManager so PropertyGrid is part of Tab chain
	if pg.enabled {
		ctx.focus.register_property_grid(&pg, pg.focus_group)
	}

	// Sync focused state with FocusManager (but don't override
	// when actively editing — TextInput owns focus then)
	if !pg.editing {
		should_focus := ctx.focus.is_focused(unsafe { &pg })
		if pg.focused && !should_focus {
			pg.focused = false
		} else if !pg.focused && should_focus {
			pg.focused = true
		}
	}

	target_focus := if pg.focused && pg.enabled { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if pg.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('propertygrid', pg.bounds.expanded(1))
	}

	pg.scroll_y = clamp_f32(pg.scroll_y, 0, pg.max_scroll())

	// Background + border
	ctx.fill_rect(pg.bounds, pg.eff_bg(ctx))
	bc := ctx.theme.input_border.blend(ctx.theme.input_focus, pg.focus_anim.value)
	ctx.draw_rect(pg.bounds, bc)

	if pg.focus_anim.value > 0.05 {
		glow := ctx.theme.input_focus.with_alpha(u8(30.0 * pg.focus_anim.value))
		ctx.draw_rect(pg.bounds.expanded(1), glow)
	}

	font := ctx.get_font(.regular, 0)
	font_b := ctx.get_font(.bold, 0)
	fh := ctx.font_height_of(font)

	// Header
	if pg.show_header {
		hr := pg.header_rect()
		ctx.fill_rect(hr, pg.eff_header_bg(ctx))
		ctx.draw_line(hr.x, hr.y + hr.h, hr.x + hr.w, hr.y + hr.h, pg.eff_grid_color(ctx))
		ty := hr.y + (hr.h - fh) * 0.5
		sx := pg.split_x()
		ctx.push_clip(Rect{hr.x, hr.y, sx - hr.x, hr.h})
		ctx.draw_text_with_font('Property', hr.x + pg_pad_h, ty, pg.eff_header_text(ctx), font_b)
		ctx.pop_clip()
		ctx.push_clip(Rect{sx, hr.y, hr.x + hr.w - sx, hr.h})
		ctx.draw_text_with_font('Value', sx + pg_pad_h, ty, pg.eff_header_text(ctx), font_b)
		ctx.pop_clip()
	}

	dr := pg.data_rect()
	ctx.push_clip(dr)

	flat := pg.build_flat()
	sx := pg.split_x()

	for i, row in flat {
		row_y := dr.y + f32(i) * pg.row_height - pg.scroll_y
		if row_y + pg.row_height < dr.y || row_y > dr.y + dr.h {
			continue
		}
		is_group := row.prop.kind == .group
		is_selected := unsafe { pg.selected != nil } && pg.selected == row.prop

		// Row background
		mut row_bg := pg.eff_row_bg(ctx, i)
		if is_group {
			row_bg = pg.eff_group_bg(ctx)
		}
		row_rect := Rect{dr.x, row_y, dr.w, pg.row_height}
		ctx.fill_rect(row_rect, row_bg)
		if row.prop.hovered {
			ctx.fill_rect(row_rect, pg.eff_row_hover_bg(ctx))
		}
		if is_selected {
			ctx.fill_rect(row_rect, pg.eff_row_sel_bg(ctx))
		}

		// Name column
		row_tc := pg.eff_row_text(ctx)
		name_x := dr.x + f32(row.depth) * pg_indent + pg_pad_h + if is_group {
			pg_arrow_size + 4
		} else {
			f32(0)
		}

		// Group expand/collapse arrow
		if is_group {
			ax := dr.x + f32(row.depth) * pg_indent + 2
			ay := row_y + (pg.row_height - pg_arrow_size) * 0.5
			if row.prop.expanded {
				ctx.fill_triangle(ax, ay, ax + pg_arrow_size, ay, ax + pg_arrow_size * 0.5, ay +
					pg_arrow_size, row_tc)
			} else {
				ctx.fill_triangle(ax, ay, ax, ay + pg_arrow_size, ax + pg_arrow_size, ay +
					pg_arrow_size * 0.5, row_tc)
			}
		}

		name_clip := Rect{dr.x, row_y, sx - dr.x, pg.row_height}
		ctx.push_clip(name_clip)
		ty := row_y + (pg.row_height - fh) * 0.5
		if is_group {
			ctx.draw_text_with_font(row.prop.name, name_x, ty, row_tc, font_b)
		} else {
			ctx.draw_text_with_font(row.prop.name, name_x, ty, row_tc, font)
		}
		ctx.pop_clip()

		// Value column (skip when actively editing this row)
		is_editing_this := pg.editing && pg.edit_prop == row.prop
		if !is_group && !is_editing_this {
			val_clip := Rect{sx, row_y, dr.x + dr.w - sx, pg.row_height}
			ctx.push_clip(val_clip)

			// Special rendering for color: show swatch + hex
			if row.prop.kind == .color_val {
				swatch_w := f32(28)
				swatch_h := pg.row_height - 8
				swatch_r := Rect{sx + pg_pad_h, row_y + 4, swatch_w, swatch_h}
				ctx.fill_rounded_rect(swatch_r, row.prop.color_val, 3)
				ctx.draw_rounded_rect(swatch_r, ctx.theme.border, 3)
				hex := pg_format_value(row.prop)
				ctx.draw_text_with_font(hex, sx + pg_pad_h + swatch_w + 6, ty, row_tc, font)
			} else if row.prop.kind == .bool_val {
				// Render checkbox-like indicator
				cb_sz := f32(14)
				cb_r := Rect{sx + pg_pad_h, row_y + (pg.row_height - cb_sz) * 0.5, cb_sz, cb_sz}
				cb_bg := if row.prop.bool_val { ctx.theme.accent } else { ctx.theme.input_bg }
				ctx.fill_rounded_rect(cb_r, cb_bg, 2)
				ctx.draw_rounded_rect(cb_r, ctx.theme.input_border, 2)
				if row.prop.bool_val {
					cx := cb_r.x + cb_r.w * 0.5
					cy := cb_r.y + cb_r.h * 0.5
					s := cb_r.w * 0.3
					ctx.draw_line_thick(cx - s, cy, cx - s * 0.3, cy + s * 0.7, 2,
						ctx.theme.accent_text)
					ctx.draw_line_thick(cx - s * 0.3, cy + s * 0.7, cx + s, cy - s * 0.5, 2,
						ctx.theme.accent_text)
				}
				lbl := if row.prop.bool_val { 'true' } else { 'false' }
				ctx.draw_text_with_font(lbl, sx + pg_pad_h + cb_sz + 6, ty, row_tc, font)
			} else {
				val_text := pg_format_value(row.prop)
				ctx.draw_text_with_font(val_text, sx + pg_pad_h, ty, row_tc, font)
			}

			ctx.pop_clip()
		}

		// Row separator
		ctx.draw_line(dr.x, row_y + pg.row_height, dr.x + dr.w, row_y + pg.row_height,
			pg.eff_grid_color(ctx))
	}

	ctx.pop_clip()

	// Vertical splitter line (drawn after data clip pop, so visible everywhere)
	splitter_full := Rect{sx, pg.bounds.y + pg.pad, 1, pg.bounds.h - pg.pad * 2}
	splitter_c := if pg.splitter_dragging {
		ctx.theme.accent
	} else if pg.splitter_hovered {
		ctx.theme.accent.with_alpha(180)
	} else {
		pg.eff_splitter_color(ctx)
	}
	ctx.fill_rect(splitter_full, splitter_c)

	// Scrollbar
	if pg.has_vsb() {
		track, thumb := pg.vsb_rects()
		ctx.fill_rect(track, ctx.theme.panel_bg)
		ctx.fill_rect(thumb, ctx.theme.border)
	}

	// Active editor on top
	if pg.editing && unsafe { pg.edit_text_input != nil } {
		mut ti := pg.edit_text_input
		ti.bounds = pg.editor_rect()
		ti.draw(mut ctx)
	}
}

fn (pg &PropertyGrid) point_in_active_editor(mx f32, my f32) bool {
	if !pg.editing {
		return false
	}
	if unsafe { pg.edit_text_input != nil } {
		b := pg.edit_text_input.bounds
		return mx >= b.x && mx < b.x + b.w && my >= b.y && my < b.y + b.h
	}
	return false
}

// ─── Event handling ────────────────────────────────────

pub fn (mut pg PropertyGrid) handle_event(event &GuiEvent, app &App) bool {
	if !pg.visible || !pg.enabled {
		return false
	}

	// ── Active inline editor takes priority ──
	if pg.editing && unsafe { pg.edit_text_input != nil } {
		mut ti := pg.edit_text_input
		ti.bounds = pg.editor_rect()

		// Handle Enter/Escape ourselves BEFORE forwarding
		if event.typ == .key_down {
			if event.keycode == sdl_k_return {
				pg.commit_edit()
				// Restore PropertyGrid focus
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_property_grid(&pg, pg.focus_group)
					pg.focused = true
				}
				return true
			}
			if event.keycode == sdl_k_escape {
				pg.cancel_edit()
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_property_grid(&pg, pg.focus_group)
					pg.focused = true
				}
				return true
			}
		}

		// Click outside editor → commit and fall through to normal handling
		if event.typ == .mouse_down {
			if !pg.point_in_active_editor(event.mouse_x, event.mouse_y) {
				pg.commit_edit()
				// Fall through (don't return)
			} else {
				ti.handle_event(event, app)
				return true
			}
		} else {
			// Forward all other events to editor (text_input, mouse_move, key_down for chars)
			if ti.handle_event(event, app) {
				return true
			}
			// Eat key/text events to prevent navigation while editing
			if event.typ == .key_down || event.typ == .text_input {
				return true
			}
		}
	}

	// ── Splitter drag in progress ──
	if pg.splitter_dragging {
		match event.typ {
			.mouse_move {
				inner := pg.inner_rect()
				mut data_w := inner.w
				if pg.has_vsb() {
					data_w -= pg_sb_w
				}
				rel := event.mouse_x - inner.x
				if data_w > 0 {
					new_ratio := clamp_f32(rel / data_w, pg_min_col_width / data_w,
						(data_w - pg_min_col_width) / data_w)
					pg.split_ratio = new_ratio
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					pg.splitter_dragging = false
					cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
					C.SDL_SetCursor(cursor)
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Scrollbar drag in progress ──
	if pg.vsb_dragging {
		match event.typ {
			.mouse_move {
				dr := pg.data_rect()
				_, thumb := pg.vsb_rects()
				dy := event.mouse_y - pg.vsb_drag_start_y
				travel := dr.h - thumb.h
				if travel > 0 {
					pg.scroll_y = clamp_f32(pg.vsb_drag_start_scroll + dy * pg.max_scroll() / travel,
						0, pg.max_scroll())
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					pg.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_down {
			mx := event.mouse_x
			my := event.mouse_y
			if !pg.bounds.contains(mx, my) {
				return false
			}

			// Take focus
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				ctx_mut.focus.focus_property_grid(&pg, pg.focus_group)
			}
			pg.focused = true

			// Splitter hit (works in header + data area)
			sr := pg.splitter_rect()
			if sr.contains(mx, my) {
				pg.splitter_dragging = true
				return true
			}

			// Scrollbar hit
			if pg.has_vsb() {
				_, thumb := pg.vsb_rects()
				if thumb.contains(mx, my) {
					pg.vsb_dragging = true
					pg.vsb_drag_start_y = my
					pg.vsb_drag_start_scroll = pg.scroll_y
					return true
				}
			}

			// Arrow toggle (group expand/collapse)
			ar := pg.hit_arrow(mx, my)
			if ar >= 0 {
				flat := pg.build_flat()
				mut p := unsafe { flat[ar].prop }
				p.expanded = !p.expanded
				return true
			}

			// Row click
			idx := pg.hit_row(my)
			if idx >= 0 {
				flat := pg.build_flat()
				row := flat[idx]
				pg.selected = unsafe { row.prop }

				if row.prop.kind == .group {
					return true
				}

				sx := pg.split_x()
				if mx >= sx {
					// Click in value column.
					// bool_val toggles by single click (стандартное поведение чекбокса).
					// color/date/file/folder открываются ТОЛЬКО по двойному клику —
					// здесь мы не обрабатываем эти типы, чтобы не блокировать dbl_click.
					if row.prop.kind == .bool_val {
						mut p := unsafe { row.prop }
						p.bool_val = !p.bool_val
						if pg.on_change != unsafe { nil } {
							pg.on_change(row.prop)
						}
						return true
					}
				}
				return true
			}
		}
		.mouse_dbl_click {
			mx := event.mouse_x
			my := event.mouse_y
			if !pg.bounds.contains(mx, my) {
				return false
			}
			idx := pg.hit_row(my)
			if idx >= 0 {
				flat := pg.build_flat()
				row := flat[idx]
				pg.selected = unsafe { row.prop }

				if row.prop.kind == .group {
					mut p := unsafe { row.prop }
					p.expanded = !p.expanded
					return true
				}
				if row.prop.kind == .bool_val {
					mut p := unsafe { row.prop }
					p.bool_val = !p.bool_val
					if pg.on_change != unsafe { nil } {
						pg.on_change(row.prop)
					}
					return true
				}
				// Start editing — passes app for FocusManager registration
				// or opens dialog for special types
				pg.begin_edit(row.prop, app)
				return true
			}
		}
		.mouse_up {
			pg.splitter_dragging = false
			pg.vsb_dragging = false
		}
		.mouse_move {
			mx := event.mouse_x
			my := event.mouse_y

			// Reset hover states
			pg.splitter_hovered = false
			for r in pg.roots {
				pg_clear_hover(r)
			}

			if !pg.bounds.contains(mx, my) {
				return false
			}

			// Splitter hover → cursor
			pg.splitter_hovered = pg.splitter_rect().contains(mx, my)
			if pg.splitter_hovered {
				cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_sizewe)
				C.SDL_SetCursor(cursor)
			} else {
				cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
				C.SDL_SetCursor(cursor)
			}

			// Row hover
			idx := pg.hit_row(my)
			if idx >= 0 {
				flat := pg.build_flat()
				mut p := unsafe { flat[idx].prop }
				p.hovered = true
			}
		}
		.mouse_wheel {
			if !pg.wheel {
				return false
			}
			ctx_ptr := app.get_active_ctx()
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if pg.bounds.contains(mx, my) {
				old := pg.scroll_y
				pg.scroll_y = clamp_f32(pg.scroll_y - f32(event.wheel_y) * pg.scroll_speed, 0,
					pg.max_scroll())
				return pg.scroll_y != old
			}
		}
		.key_down {
			if !pg.focused {
				return false
			}

			// F2 / Enter — start editing or toggle
			if event.keycode == sdl_k_f2 || event.keycode == sdl_k_return {
				if unsafe { pg.selected != nil } {
					if pg.selected.kind == .bool_val {
						mut p := unsafe { pg.selected }
						p.bool_val = !p.bool_val
						if pg.on_change != unsafe { nil } {
							pg.on_change(pg.selected)
						}
					} else if pg.selected.kind == .group {
						mut p := unsafe { pg.selected }
						p.expanded = !p.expanded
					} else {
						pg.begin_edit(pg.selected, app)
					}
					return true
				}
			}

			// ── Left key ──
			//   on group     → collapse (or jump to parent if already collapsed)
			//   on leaf      → jump to parent group
			if event.keycode == sdl_k_left {
				if unsafe { pg.selected != nil } {
					if pg.selected.kind == .group && pg.selected.expanded {
						mut p := unsafe { pg.selected }
						p.expanded = false
						pg.ensure_visible()
					} else if unsafe { pg.selected.parent != nil } {
						pg.selected = pg.selected.parent
						pg.ensure_visible()
					}
				}
				return true
			}

			// ── Right key ──
			//   on collapsed group  → expand
			//   on expanded group   → move to first child
			if event.keycode == sdl_k_right {
				if unsafe { pg.selected != nil } && pg.selected.kind == .group {
					if !pg.selected.expanded {
						mut p := unsafe { pg.selected }
						p.expanded = true
						pg.ensure_visible()
					} else if pg.selected.children.len > 0 {
						pg.selected = pg.selected.children[0]
						pg.ensure_visible()
					}
				}
				return true
			}

			// Up / Down navigation
			if event.keycode == sdl_k_up || event.keycode == sdl_k_down {
				flat := pg.build_flat()
				if flat.len == 0 {
					return false
				}
				mut cur := -1
				if unsafe { pg.selected != nil } {
					for i, row in flat {
						if row.prop == pg.selected {
							cur = i
							break
						}
					}
				}
				if event.keycode == sdl_k_up {
					cur = if cur <= 0 { 0 } else { cur - 1 }
				} else {
					cur = if cur < 0 {
						0
					} else if cur >= flat.len - 1 {
						flat.len - 1
					} else {
						cur + 1
					}
				}
				pg.selected = unsafe { flat[cur].prop }
				pg.ensure_visible()
				return true
			}

			// Home / End
			if event.keycode == sdl_k_home {
				flat := pg.build_flat()
				if flat.len > 0 {
					pg.selected = unsafe { flat[0].prop }
					pg.ensure_visible()
				}
				return true
			}
			if event.keycode == sdl_k_end {
				flat := pg.build_flat()
				if flat.len > 0 {
					pg.selected = unsafe { flat[flat.len - 1].prop }
					pg.ensure_visible()
				}
				return true
			}

			// Tab — pass to FocusManager
			if event.keycode == sdl_k_tab {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.tab(event.shift())
				}
				return true
			}
		}
		else {}
	}

	return false
}

fn pg_clear_hover(p &Property) {
	mut mp := unsafe { p }
	mp.hovered = false
	for ch in p.children {
		pg_clear_hover(ch)
	}
}
