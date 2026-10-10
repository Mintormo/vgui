module vgui

// ═══════════════════════════════════════════════════════
// TreeView — hierarchical tree widget with icons,
// expand/collapse, keyboard navigation, dual scrollbars,
// selection modes, inline editing
// ═══════════════════════════════════════════════════════

@[heap]
pub struct TreeNode {
pub mut:
	type_tag  int = kind_tree_node // тег типа, см. widget_tag.v
	text      string
	icon_path string
	expanded  bool = true
	children  []&TreeNode
	parent    &TreeNode = unsafe { nil }
	// Per-node custom colors (a=0 means use default)
	text_color Color = Color{0, 0, 0, 0}
	bg_color   Color = Color{0, 0, 0, 0}
}

pub fn tree_node(text string) &TreeNode {
	return &TreeNode{
		text: text
	}
}

pub fn tree_node_icon(text string, icon_path string) &TreeNode {
	return &TreeNode{
		text:      text
		icon_path: icon_path
	}
}

pub fn (mut n TreeNode) add(child &TreeNode) {
	mut c := unsafe { child }
	c.parent = unsafe { n }
	n.children << unsafe { child }
}

pub fn (mut n TreeNode) add_child(text string) &TreeNode {
	c := tree_node(text)
	n.add(c)
	return c
}

pub fn (mut n TreeNode) add_child_icon(text string, icon_path string) &TreeNode {
	c := tree_node_icon(text, icon_path)
	n.add(c)
	return c
}

pub fn (mut n TreeNode) remove_at(idx int) {
	if idx >= 0 && idx < n.children.len {
		n.children.delete(idx)
	}
}

pub fn (mut n TreeNode) insert_at(idx int, child &TreeNode) {
	mut c := unsafe { child }
	c.parent = unsafe { n }
	if idx <= 0 {
		n.children.insert(0, unsafe { child })
	} else if idx >= n.children.len {
		n.children << unsafe { child }
	} else {
		n.children.insert(idx, unsafe { child })
	}
}

pub fn (n &TreeNode) has_children() bool {
	return n.children.len > 0
}

// ═══════════════════════════════════════════════════════
// Selection style
// ═══════════════════════════════════════════════════════

pub enum TreeSelectStyle {
	full_row
	text_rect
}

// ═══════════════════════════════════════════════════════
// TreeView widget
// ═══════════════════════════════════════════════════════

// Minimum width of inline edit field
const tv_min_edit_w = f32(60)
// Extra padding added to text width for edit field
const tv_edit_pad = f32(24)

const tv_max_edit_undo = 50

@[heap]
pub struct TreeView {
pub mut:
	type_tag int = kind_tree_view // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel       bool = true
	bounds      Rect
	roots       []&TreeNode
	selected    &TreeNode = unsafe { nil }
	visible     bool      = true
	enabled     bool      = true
	focused     bool
	hovered     bool
	focus_anim  Anim = anim_smooth(anim_tau_focus)
	focus_group int
	// Appearance
	select_style TreeSelectStyle = .full_row
	item_height  f32             = 22
	indent       f32             = 18
	icon_size    f32             = 16
	icon_gap     f32             = 4
	pad          f32             = 4
	scroll_speed f32             = 30
	editable     bool            = true
	// Guide lines (dotted hierarchy lines)
	show_lines  bool // if true, draw dotted guide lines
	line_color  Color = Color{0, 0, 0, 0} // 0 = theme.text_disabled with alpha
	line_dash   f32   = 2                 // dash segment length
	line_gap_px f32   = 2                 // gap between dashes
	line_solid  bool // if true, draw solid lines instead of dashed
	// Scroll
	scroll_x f32
	scroll_y f32
	// Callbacks
	on_select      fn (&vgui.TreeNode)                 = unsafe { nil }
	on_dbl_click   fn (&vgui.TreeNode)                 = unsafe { nil }
	on_expand      fn (&vgui.TreeNode, bool)           = unsafe { nil }
	on_edit_start  fn (&vgui.TreeNode)                 = unsafe { nil }
	on_edit_commit fn (&vgui.TreeNode, string, string) = unsafe { nil }
	on_edit_cancel fn (&vgui.TreeNode)                 = unsafe { nil }
	// Hover
	hover_node &TreeNode = unsafe { nil }
	// Inline editing state
	editing       bool
	edit_node     &TreeNode = unsafe { nil }
	edit_buf      []rune
	edit_cur      int
	edit_scroll_x f32
	edit_original string
	// Edit selection & undo
	edit_sel_a   int = -1
	edit_sel_b   int = -1
	edit_drag    bool
	edit_history UndoHistory[RuneSnap] = UndoHistory[RuneSnap]{
		limit: tv_max_edit_undo
	}
	// Scrollbar drag state (vertical)
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	// Scrollbar drag state (horizontal)
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
}

pub fn tree_view() &TreeView {
	return &TreeView{}
}

// ─── Public API ────────────────────────────────────────

pub fn (mut tv TreeView) add_root(node &TreeNode) {
	tv.roots << unsafe { node }
}

pub fn (mut tv TreeView) clear() {
	tv.cancel_edit()
	tv.roots.clear()
	tv.selected = unsafe { nil }
	tv.hover_node = unsafe { nil }
	tv.scroll_x = 0
	tv.scroll_y = 0
}

pub fn (tv &TreeView) get_selected() &TreeNode {
	return tv.selected
}

pub fn (tv &TreeView) get_selected_text() string {
	if unsafe { tv.selected != nil } {
		return tv.selected.text
	}
	return ''
}

pub fn (mut tv TreeView) set_selected(node &TreeNode) {
	tv.selected = unsafe { node }
}

pub fn (mut tv TreeView) set_item_text(node &TreeNode, text string) {
	mut n := unsafe { node }
	n.text = text
}

pub fn (mut tv TreeView) set_item_icon(node &TreeNode, icon_path string) {
	mut n := unsafe { node }
	n.icon_path = icon_path
}

pub fn (mut tv TreeView) expand_all() {
	for r in tv.roots {
		tv_set_expanded_recursive(r, true)
	}
}

pub fn (mut tv TreeView) collapse_all() {
	for r in tv.roots {
		tv_set_expanded_recursive(r, false)
	}
}

pub fn (tv &TreeView) is_editing() bool {
	return tv.editing
}

pub fn (tv &TreeView) get_edit_node() &TreeNode {
	return tv.edit_node
}

pub fn (mut tv TreeView) begin_edit(node &TreeNode) {
	if unsafe { node == nil } || !tv.editable {
		return
	}
	tv.editing = true
	tv.edit_node = unsafe { node }
	tv.edit_original = node.text
	tv.edit_buf = node.text.runes()
	tv.edit_cur = tv.edit_buf.len
	tv.edit_scroll_x = 0
	tv.edit_sel_a = -1
	tv.edit_sel_b = -1
	tv.edit_drag = false
	tv.edit_history.clear()
	if tv.on_edit_start != unsafe { nil } {
		tv.on_edit_start(node)
	}
}

pub fn (mut tv TreeView) commit_edit() {
	if !tv.editing {
		return
	}
	new_text := if tv.edit_buf.len > 0 { tv.edit_buf.string() } else { '' }
	old_text := tv.edit_original
	mut n := unsafe { tv.edit_node }
	n.text = new_text
	tv.editing = false
	if tv.on_edit_commit != unsafe { nil } {
		tv.on_edit_commit(tv.edit_node, old_text, new_text)
	}
	tv.edit_node = unsafe { nil }
}

pub fn (mut tv TreeView) cancel_edit() {
	if !tv.editing {
		return
	}
	mut n := unsafe { tv.edit_node }
	n.text = tv.edit_original
	node := tv.edit_node
	tv.editing = false
	tv.edit_node = unsafe { nil }
	if tv.on_edit_cancel != unsafe { nil } {
		tv.on_edit_cancel(node)
	}
}

fn tv_set_expanded_recursive(node &TreeNode, val bool) {
	mut n := unsafe { node }
	n.expanded = val
	for ch in n.children {
		tv_set_expanded_recursive(ch, val)
	}
}

// ─── Flat list of visible nodes ────────────────────────

struct FlatNode {
	node    &TreeNode
	depth   int
	is_last []bool // for each depth level: is ancestor the last child?
}

fn (tv &TreeView) build_flat() []FlatNode {
	mut result := []FlatNode{cap: 64}
	for r in tv.roots {
		tv_flatten(r, 0, mut result)
	}
	return result
}

fn tv_flatten(node &TreeNode, depth int, mut out []FlatNode) {
	tv_flatten_with_last(node, depth, []bool{}, mut out)
}

fn tv_flatten_with_last(node &TreeNode, depth int, parent_last []bool, mut out []FlatNode) {
	out << FlatNode{
		node:    node
		depth:   depth
		is_last: parent_last
	}
	if node.expanded {
		for ci, ch in node.children {
			mut child_last := parent_last.clone()
			child_last << (ci == node.children.len - 1)
			tv_flatten_with_last(ch, depth + 1, child_last, mut out)
		}
	}
}

// ─── Content size ──────────────────────────────────────

fn (tv &TreeView) content_size(ctx &RenderContext) (f32, f32) {
	flat := tv.build_flat()
	h := f32(flat.len) * tv.item_height
	font := ctx.get_font_immut(.regular, 0)
	mut max_w := f32(0)
	for fn_ in flat {
		x := tv.pad + f32(fn_.depth) * tv.indent + tv.indent
		tw := ctx.measure_text_with_font(fn_.node.text, font).x
		w := if fn_.node.icon_path.len > 0 {
			x + tv.icon_size + tv.icon_gap + tw + tv.pad
		} else {
			x + tw + tv.pad
		}
		if w > max_w {
			max_w = w
		}
	}
	return max_w, h
}

fn (tv &TreeView) inner_rect() Rect {
	return tv.bounds.shrunk(tv.pad)
}

fn (tv &TreeView) max_scroll_y(ctx &RenderContext) f32 {
	_, ch := tv.content_size(ctx)
	return max_f32(0, ch - tv.inner_rect().h)
}

fn (tv &TreeView) max_scroll_x(ctx &RenderContext) f32 {
	cw, _ := tv.content_size(ctx)
	return max_f32(0, cw - tv.inner_rect().w)
}

fn (tv &TreeView) has_vsb(ctx &RenderContext) bool {
	_, ch := tv.content_size(ctx)
	return ch > tv.inner_rect().h
}

fn (tv &TreeView) has_hsb(ctx &RenderContext) bool {
	cw, _ := tv.content_size(ctx)
	return cw > tv.inner_rect().w
}

// ─── Scrollbar geometry ────────────────────────────────

const tv_sb_w = f32(10)

fn (tv &TreeView) vsb_rects(ctx &RenderContext) (Rect, Rect) {
	inner := tv.inner_rect()
	_, ch := tv.content_size(ctx)
	vis_h := inner.h
	if ch <= vis_h {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: inner.x + inner.w - tv_sb_w
		y: inner.y
		w: tv_sb_w
		h: vis_h
	}
	thumb_h := max_f32(20, vis_h * (vis_h / ch))
	ms := tv.max_scroll_y(ctx)
	ratio := if ms > 0 { tv.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 1
		y: track.y + ratio * (vis_h - thumb_h)
		w: tv_sb_w - 2
		h: thumb_h
	}
	return track, thumb
}

fn (tv &TreeView) hsb_rects(ctx &RenderContext) (Rect, Rect) {
	inner := tv.inner_rect()
	cw, _ := tv.content_size(ctx)
	vis_w := inner.w - (if tv.has_vsb(ctx) { tv_sb_w } else { f32(0) })
	if cw <= vis_w {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: inner.x
		y: inner.y + inner.h - tv_sb_w
		w: vis_w
		h: tv_sb_w
	}
	thumb_w := max_f32(20, vis_w * (vis_w / cw))
	ms := tv.max_scroll_x(ctx)
	ratio := if ms > 0 { tv.scroll_x / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vis_w - thumb_w)
		y: track.y + 1
		w: thumb_w
		h: tv_sb_w - 2
	}
	return track, thumb
}

// ─── Hit test ──────────────────────────────────────────

fn (tv &TreeView) hit_node(my f32, ctx &RenderContext) (&TreeNode, int) {
	_ = ctx
	inner := tv.inner_rect()
	rel_y := my - inner.y + tv.scroll_y
	idx := int(rel_y / tv.item_height)
	flat := tv.build_flat()
	if idx >= 0 && idx < flat.len {
		return flat[idx].node, flat[idx].depth
	}
	return unsafe { &TreeNode(nil) }, 0
}

fn (tv &TreeView) hit_expand_btn(mx f32, my f32, ctx &RenderContext) &TreeNode {
	_ = ctx
	inner := tv.inner_rect()
	rel_y := my - inner.y + tv.scroll_y
	idx := int(rel_y / tv.item_height)
	flat := tv.build_flat()
	if idx < 0 || idx >= flat.len {
		return unsafe { nil }
	}
	fn_ := flat[idx]
	if !fn_.node.has_children() {
		return unsafe { nil }
	}
	arrow_x := inner.x + f32(fn_.depth) * tv.indent - tv.scroll_x
	arrow_w := tv.indent
	iy := inner.y + f32(idx) * tv.item_height - tv.scroll_y
	if mx >= arrow_x && mx < arrow_x + arrow_w && my >= iy && my < iy + tv.item_height {
		return fn_.node
	}
	return unsafe { nil }
}

fn (tv &TreeView) node_text_rect(fn_ FlatNode, idx int, ctx &RenderContext) Rect {
	inner := tv.inner_rect()
	font := ctx.get_font_immut(.regular, 0)
	fh := ctx.font_height_of(font)
	iy := inner.y + f32(idx) * tv.item_height - tv.scroll_y
	depth_x := inner.x + f32(fn_.depth) * tv.indent - tv.scroll_x
	text_x := depth_x + tv.indent
	tw := ctx.measure_text_with_font(fn_.node.text, font).x
	mut rx := text_x
	mut rw := tw
	if fn_.node.icon_path.len > 0 {
		rw = tv.icon_size + tv.icon_gap + tw
	}
	ty := iy + (tv.item_height - fh) * 0.5
	return Rect{rx - 2, ty - 1, rw + 4, fh + 2}
}

// ─── Keyboard helpers ──────────────────────────────────

fn (tv &TreeView) flat_index_of(node &TreeNode) int {
	flat := tv.build_flat()
	for i, fn_ in flat {
		if voidptr(fn_.node) == voidptr(node) {
			return i
		}
	}
	return -1
}

fn (mut tv TreeView) ensure_visible(ctx &RenderContext) {
	if unsafe { tv.selected == nil } {
		return
	}
	idx := tv.flat_index_of(tv.selected)
	if idx < 0 {
		return
	}
	inner := tv.inner_rect()
	item_top := f32(idx) * tv.item_height
	item_bot := item_top + tv.item_height
	if item_top < tv.scroll_y {
		tv.scroll_y = item_top
	}
	if item_bot > tv.scroll_y + inner.h {
		tv.scroll_y = item_bot - inner.h
	}
	tv.scroll_y = clamp_f32(tv.scroll_y, 0, tv.max_scroll_y(ctx))
}

fn (mut tv TreeView) fire_select() {
	if tv.on_select != unsafe { nil } && unsafe { tv.selected != nil } {
		tv.on_select(tv.selected)
	}
}

// ─── Edit selection helpers ────────────────────────────

fn (tv &TreeView) edit_has_sel() bool {
	return tv.edit_sel_a >= 0 && tv.edit_sel_b >= 0 && tv.edit_sel_a != tv.edit_sel_b
}

fn (tv &TreeView) edit_sel_lo() int {
	return min_int(tv.edit_sel_a, tv.edit_sel_b)
}

fn (tv &TreeView) edit_sel_hi() int {
	return max_int(tv.edit_sel_a, tv.edit_sel_b)
}

fn (mut tv TreeView) edit_clear_sel() {
	tv.edit_sel_a = -1
	tv.edit_sel_b = -1
}

fn (mut tv TreeView) edit_ensure_sel() {
	if tv.edit_sel_a < 0 {
		tv.edit_sel_a = tv.edit_cur
		tv.edit_sel_b = tv.edit_cur
	}
}

fn (tv &TreeView) edit_selected_text() string {
	if !tv.edit_has_sel() {
		return ''
	}
	lo := tv.edit_sel_lo()
	hi := tv.edit_sel_hi()
	if lo >= hi || lo < 0 || hi > tv.edit_buf.len {
		return ''
	}
	return tv.edit_buf[lo..hi].string()
}

// ─── Home/End key detection (same logic as text_input.v) ──

fn tv_is_home_key(keycode int, scancode int) bool {
	return keycode == sdl_k_home || keycode == sdl_k_kp_7 || scancode == sc_home
		|| scancode == sc_kp_7
}

fn tv_is_end_key(keycode int, scancode int) bool {
	return keycode == sdl_k_end || keycode == sdl_k_kp_1 || scancode == sc_end
		|| scancode == sc_kp_1
}

const sc_kp_9 = 97
const sc_kp_3 = 91

fn tv_is_pageup_key(keycode int, scancode int) bool {
	return keycode == sdl_k_pageup || keycode == sdl_k_kp_9 || scancode == sc_kp_9
}

fn tv_is_pagedown_key(keycode int, scancode int) bool {
	return keycode == sdl_k_pagedown || keycode == sdl_k_kp_3 || scancode == sc_kp_3
}

// ─── Edit undo/redo ────────────────────────────────────

fn (mut tv TreeView) edit_save_undo() {
	tv.edit_history.save(RuneSnap{
		buf: tv.edit_buf.clone()
		cur: tv.edit_cur
	})
}

fn (mut tv TreeView) edit_perform_undo() {
	entry := tv.edit_history.undo(RuneSnap{
		buf: tv.edit_buf.clone()
		cur: tv.edit_cur
	}) or { return }
	tv.edit_buf = entry.buf.clone()
	tv.edit_cur = clamp_int(entry.cur, 0, tv.edit_buf.len)
	tv.edit_clear_sel()
}

fn (mut tv TreeView) edit_perform_redo() {
	entry := tv.edit_history.redo(RuneSnap{
		buf: tv.edit_buf.clone()
		cur: tv.edit_cur
	}) or { return }
	tv.edit_buf = entry.buf.clone()
	tv.edit_cur = clamp_int(entry.cur, 0, tv.edit_buf.len)
	tv.edit_clear_sel()
}

// ─── Edit text operations ──────────────────────────────

fn (mut tv TreeView) edit_delete_sel() {
	if !tv.edit_has_sel() {
		return
	}
	lo := tv.edit_sel_lo()
	hi := tv.edit_sel_hi()
	mut out := []rune{cap: tv.edit_buf.len - (hi - lo)}
	for i in 0 .. lo {
		out << tv.edit_buf[i]
	}
	for i in hi .. tv.edit_buf.len {
		out << tv.edit_buf[i]
	}
	tv.edit_buf = out
	tv.edit_cur = lo
	tv.edit_clear_sel()
}

fn (mut tv TreeView) edit_insert(s string) {
	if s.len == 0 {
		return
	}
	tv.edit_save_undo()
	if tv.edit_has_sel() {
		tv.edit_delete_sel()
	}
	rr := s.runes()
	mut out := []rune{cap: tv.edit_buf.len + rr.len}
	for i in 0 .. tv.edit_cur {
		out << tv.edit_buf[i]
	}
	for r in rr {
		out << r
	}
	for i in tv.edit_cur .. tv.edit_buf.len {
		out << tv.edit_buf[i]
	}
	tv.edit_buf = out
	tv.edit_cur += rr.len
}

fn (mut tv TreeView) edit_fix_scroll(ctx &RenderContext, avail_w f32) {
	font := ctx.get_font_immut(.regular, 0)
	text_before := if tv.edit_cur > 0 && tv.edit_cur <= tv.edit_buf.len {
		tv.edit_buf[..tv.edit_cur].string()
	} else {
		''
	}
	cx := ctx.measure_text_with_font(text_before, font).x
	if cx - tv.edit_scroll_x > avail_w - 4 {
		tv.edit_scroll_x = cx - avail_w + 20
	}
	if cx - tv.edit_scroll_x < 0 {
		tv.edit_scroll_x = max_f32(0, cx - 20)
	}
	full := if tv.edit_buf.len > 0 { tv.edit_buf.string() } else { '' }
	fw := ctx.measure_text_with_font(full, font).x
	if fw <= avail_w {
		tv.edit_scroll_x = 0
	}
	if tv.edit_scroll_x < 0 {
		tv.edit_scroll_x = 0
	}
}

fn (tv &TreeView) calc_edit_width(ctx &RenderContext, content_x f32) f32 {
	font := ctx.get_font_immut(.regular, 0)
	text_w := if tv.edit_buf.len > 0 {
		ctx.measure_text_with_font(tv.edit_buf.string(), font).x
	} else {
		f32(0)
	}
	inner := tv.inner_rect()
	max_avail := inner.x + inner.w - content_x - 4
	desired := max_f32(tv_min_edit_w, text_w + tv_edit_pad)
	return min_f32(desired, max_f32(tv_min_edit_w, max_avail))
}

// ─── Guide lines drawing ───────────────────────────────

fn (tv &TreeView) draw_guide_lines(fn_ FlatNode, i int, inner Rect, mut ctx RenderContext) {
	lc := if tv.line_color.a > 0 {
		tv.line_color
	} else {
		ctx.theme.eff_tr_guide().with_alpha(60)
	}

	iy := inner.y + f32(i) * tv.item_height - tv.scroll_y
	mid_y := iy + tv.item_height * 0.5

	// For each depth level, draw vertical continuation line if ancestor is not last
	for d in 0 .. fn_.depth {
		lx := inner.x + f32(d) * tv.indent + tv.indent * 0.5 - tv.scroll_x
		if d < fn_.is_last.len && !fn_.is_last[d] {
			// Vertical dotted line for this depth column
			tv.draw_vdash(lx, iy, iy + tv.item_height, lc, mut ctx)
		}
	}

	// Horizontal branch from parent column to this node
	if fn_.depth > 0 {
		parent_lx := inner.x + f32(fn_.depth - 1) * tv.indent + tv.indent * 0.5 - tv.scroll_x
		node_lx := inner.x + f32(fn_.depth) * tv.indent - tv.scroll_x

		// Horizontal dash
		tv.draw_hdash(parent_lx, node_lx, mid_y, lc, mut ctx)

		// Vertical line from top of row to mid (or full height if not last)
		is_last_child := fn_.is_last.len > 0 && fn_.is_last[fn_.is_last.len - 1]
		vtop := iy
		vbot := if is_last_child { mid_y } else { iy + tv.item_height }
		tv.draw_vdash(parent_lx, vtop, vbot, lc, mut ctx)
	}
}

fn (tv &TreeView) draw_vdash(x f32, y1 f32, y2 f32, c Color, mut ctx RenderContext) {
	if tv.line_solid {
		ctx.fill_rect(Rect{x, y1, 1, y2 - y1}, c)
		return
	}
	dash := tv.line_dash
	gap := tv.line_gap_px
	step := dash + gap
	mut y := y1
	for y < y2 {
		end := min_f32(y + dash, y2)
		ctx.fill_rect(Rect{x, y, 1, end - y}, c)
		y += step
	}
}

fn (tv &TreeView) draw_hdash(x1 f32, x2 f32, y f32, c Color, mut ctx RenderContext) {
	if tv.line_solid {
		ctx.fill_rect(Rect{x1, y, x2 - x1, 1}, c)
		return
	}
	dash := tv.line_dash
	gap := tv.line_gap_px
	step := dash + gap
	mut x := x1
	for x < x2 {
		end := min_f32(x + dash, x2)
		ctx.fill_rect(Rect{x, y, end - x, 1}, c)
		x += step
	}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut tv TreeView) draw(mut ctx RenderContext) {
	if !tv.visible {
		return
	}
	if !ctx.is_in_clip(tv.bounds) {
		return
	}

	if tv.enabled {
		ctx.focus.register_tree_view(&tv, tv.focus_group)
	}
	should_focus := ctx.focus.is_focused(unsafe { &tv })
	if tv.focused && !should_focus {
		// Don't cancel edit if we're actively in editing mode —
		// the FocusManager may not be synced yet (e.g. after
		// a button click that programmatically started editing).
		if !tv.editing {
			tv.focused = false
			tv.cancel_edit()
		}
	} else if !tv.focused && should_focus {
		tv.focused = true
	}

	target_focus := if tv.focused && tv.enabled { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if tv.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('treeview', tv.bounds.expanded(1))
	}

	rad := ctx.theme.border_radius
	bg := if tv.enabled { ctx.theme.eff_tr_bg() } else { ctx.theme.eff_tr_bg().darken(0.05) }
	ctx.fill_rounded_rect(tv.bounds, bg, rad)
	bc := ctx.theme.eff_tr_border().blend(ctx.theme.input_focus, tv.focus_anim.value)
	ctx.draw_rounded_rect(tv.bounds, bc, rad)

	if tv.focus_anim.value > 0.05 {
		glow := ctx.theme.input_focus.with_alpha(u8(30.0 * tv.focus_anim.value))
		ctx.draw_rounded_rect(tv.bounds.expanded(1), glow, rad + 1)
	}

	tv.scroll_y = clamp_f32(tv.scroll_y, 0, tv.max_scroll_y(ctx))
	tv.scroll_x = clamp_f32(tv.scroll_x, 0, tv.max_scroll_x(ctx))

	inner := tv.inner_rect()
	ctx.push_clip(inner)

	flat := tv.build_flat()
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)

	for i, fn_ in flat {
		iy := inner.y + f32(i) * tv.item_height - tv.scroll_y
		if iy + tv.item_height < inner.y {
			continue
		}
		if iy > inner.y + inner.h {
			break
		}

		// ── Guide lines ──
		if tv.show_lines {
			tv.draw_guide_lines(fn_, i, inner, mut ctx)
		}

		depth_x := inner.x + f32(fn_.depth) * tv.indent - tv.scroll_x
		mut text_x := depth_x + tv.indent

		is_sel := voidptr(fn_.node) == voidptr(tv.selected)
		is_hov := voidptr(fn_.node) == voidptr(tv.hover_node)
		is_editing := tv.editing && voidptr(fn_.node) == voidptr(tv.edit_node)

		// ── Per-node background ──
		if fn_.node.bg_color.a > 0 && !is_sel && !is_editing {
			match tv.select_style {
				.full_row {
					item_w := inner.w + tv.scroll_x
					ctx.fill_rect(Rect{inner.x, iy, item_w, tv.item_height}, fn_.node.bg_color)
				}
				.text_rect {
					trk := tv.node_text_rect(fn_, i, ctx)
					ctx.fill_rounded_rect(trk, fn_.node.bg_color, 3)
				}
			}
		}

		// ── Selection highlight ──
		if is_sel && !is_editing {
			match tv.select_style {
				.full_row {
					item_w := inner.w + tv.scroll_x
					ctx.fill_rect(Rect{inner.x, iy, item_w, tv.item_height},
						ctx.theme.eff_tr_row_selected().with_alpha(180))
				}
				.text_rect {
					trk := tv.node_text_rect(fn_, i, ctx)
					ctx.fill_rounded_rect(trk, ctx.theme.eff_tr_row_selected().with_alpha(180), 3)
				}
			}
		} else if is_hov && !is_editing {
			match tv.select_style {
				.full_row {
					item_w := inner.w + tv.scroll_x
					ctx.fill_rect(Rect{inner.x, iy, item_w, tv.item_height},
						ctx.theme.eff_tr_row_hover().with_alpha(80))
				}
				.text_rect {
					trk := tv.node_text_rect(fn_, i, ctx)
					ctx.fill_rounded_rect(trk, ctx.theme.eff_tr_row_hover().with_alpha(60), 3)
				}
			}
		}

		// ── Expand/collapse arrow ──
		if fn_.node.has_children() {
			ac := ctx.theme.eff_tr_arrow()
			ax := depth_x + tv.indent * 0.5
			ay := iy + tv.item_height * 0.5
			as_ := f32(4)
			if fn_.node.expanded {
				ctx.fill_triangle(ax - as_, ay - as_ * 0.4, ax + as_, ay - as_ * 0.4, ax, ay +
					as_ * 0.6, ac)
			} else {
				ctx.fill_triangle(ax - as_ * 0.4, ay - as_, ax - as_ * 0.4, ay + as_,
					ax + as_ * 0.6, ay, ac)
			}
		}

		// ── Icon ──
		mut content_x := text_x
		if fn_.node.icon_path.len > 0 {
			icon_tex := ctx.load_icon_texture(fn_.node.icon_path)
			icon_y := iy + (tv.item_height - tv.icon_size) * 0.5
			ctx.draw_icon(icon_tex, text_x, icon_y, tv.icon_size, tv.icon_size)
			content_x = text_x + tv.icon_size + tv.icon_gap
		}

		// ── Text or edit field ──
		ty := iy + (tv.item_height - fh) * 0.5

		if is_editing {
			// Dynamic width edit field
			edit_w := tv.calc_edit_width(ctx, content_x)
			edit_r := Rect{content_x - 2, ty - 2, edit_w + 4, fh + 4}
			ctx.fill_rounded_rect(edit_r, ctx.theme.input_bg, 3)
			ctx.draw_rounded_rect(edit_r, ctx.theme.accent, 3)

			clip_w := edit_w
			ctx.push_clip(Rect{content_x, ty - 1, clip_w, fh + 2})

			tv.edit_fix_scroll(ctx, clip_w)

			// Selection highlight
			if tv.edit_has_sel() {
				lo := tv.edit_sel_lo()
				hi := tv.edit_sel_hi()
				lo_text := if lo > 0 && lo <= tv.edit_buf.len {
					tv.edit_buf[..lo].string()
				} else {
					''
				}
				hi_text := if hi > 0 && hi <= tv.edit_buf.len {
					tv.edit_buf[..hi].string()
				} else {
					''
				}
				x1 := ctx.measure_text_with_font(lo_text, font).x - tv.edit_scroll_x
				x2 := ctx.measure_text_with_font(hi_text, font).x - tv.edit_scroll_x
				sel_r := Rect{content_x + x1, ty - 1, x2 - x1, fh + 2}
				ctx.fill_rounded_rect(sel_r, ctx.theme.accent.with_alpha(80), 2)
			}

			edit_text := if tv.edit_buf.len > 0 { tv.edit_buf.string() } else { '' }
			ctx.draw_text_with_font(edit_text, content_x - tv.edit_scroll_x, ty,
				ctx.theme.text_primary, font)

			// Cursor
			ms := C.SDL_GetTicks()
			if ms % u64(1060) < 530 {
				text_before := if tv.edit_cur > 0 && tv.edit_cur <= tv.edit_buf.len {
					tv.edit_buf[..tv.edit_cur].string()
				} else {
					''
				}
				cx := ctx.measure_text_with_font(text_before, font).x - tv.edit_scroll_x
				ctx.fill_rect(Rect{content_x + cx, ty, 2, fh}, ctx.theme.accent)
			}
			ctx.pop_clip()
		} else {
			tc := if is_sel {
				ctx.theme.eff_tr_row_sel_text()
			} else if fn_.node.text_color.a > 0 {
				fn_.node.text_color
			} else {
				ctx.theme.eff_tr_row_text()
			}
			ctx.draw_text_with_font(fn_.node.text, content_x, ty, tc, font)
		}
	}

	ctx.pop_clip()

	// ── Scrollbars ──
	if tv.has_vsb(ctx) {
		track, thumb := tv.vsb_rects(ctx)
		tc := if tv.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if tv.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
	if tv.has_hsb(ctx) {
		track, thumb := tv.hsb_rects(ctx)
		tc := if tv.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if tv.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
}

// ─── Events ────────────────────────────────────────────

pub fn (mut tv TreeView) handle_event(event &GuiEvent, app &App) bool {
	if !tv.visible || !tv.enabled {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	// ── Sync focused state from FocusManager (needed for Tab navigation) ──
	if unsafe { ctx_ptr != nil } {
		should_focus := ctx_ptr.focus.is_focused(unsafe { &tv })
		if !tv.focused && should_focus {
			tv.focused = true
		} else if tv.focused && !should_focus {
			tv.focused = false
		}
	}

	if tv.editing {
		return tv.handle_edit_event(event, app, ctx_ptr)
	}
	if tv.vsb_dragging {
		return tv.handle_vsb_drag(event, ctx_ptr)
	}
	if tv.hsb_dragging {
		return tv.handle_hsb_drag(event, ctx_ptr)
	}

	match event.typ {
		.mouse_move {
			tv.hovered = tv.bounds.contains(event.mouse_x, event.mouse_y)
			if tv.hovered && unsafe { ctx_ptr != nil } {
				node, _ := tv.hit_node(event.mouse_y, ctx_ptr)
				tv.hover_node = node
				if tv.has_vsb(ctx_ptr) {
					track, _ := tv.vsb_rects(ctx_ptr)
					tv.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
				if tv.has_hsb(ctx_ptr) {
					track, _ := tv.hsb_rects(ctx_ptr)
					tv.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
			} else {
				tv.hover_node = unsafe { nil }
				tv.vsb_hovered = false
				tv.hsb_hovered = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && tv.hovered {
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_tree_view(&tv, tv.focus_group)
					tv.focused = true

					if tv.has_vsb(ctx_ptr) {
						_, thumb := tv.vsb_rects(ctx_ptr)
						if thumb.contains(event.mouse_x, event.mouse_y) {
							tv.vsb_dragging = true
							tv.vsb_drag_start_y = event.mouse_y
							tv.vsb_drag_start_scroll = tv.scroll_y
							return true
						}
					}

					if tv.has_hsb(ctx_ptr) {
						_, hthumb := tv.hsb_rects(ctx_ptr)
						if hthumb.contains(event.mouse_x, event.mouse_y) {
							tv.hsb_dragging = true
							tv.hsb_drag_start_x = event.mouse_x
							tv.hsb_drag_start_scroll = tv.scroll_x
							return true
						}
					}

					exp_node := tv.hit_expand_btn(event.mouse_x, event.mouse_y, ctx_ptr)
					if unsafe { exp_node != nil } {
						mut en := unsafe { exp_node }
						en.expanded = !en.expanded
						if tv.on_expand != unsafe { nil } {
							tv.on_expand(exp_node, en.expanded)
						}
						return true
					}

					node, _ := tv.hit_node(event.mouse_y, ctx_ptr)
					if unsafe { node != nil } {
						tv.selected = node
						tv.fire_select()
					}
				}
				return true
			}
			if tv.focused && !tv.hovered {
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.blur_current()
				}
				tv.focused = false
			}
		}
		.mouse_dbl_click {
			if tv.hovered && tv.focused && unsafe { ctx_ptr != nil } {
				node, _ := tv.hit_node(event.mouse_y, ctx_ptr)
				if unsafe { node != nil } {
					tv.selected = node
					exp_node := tv.hit_expand_btn(event.mouse_x, event.mouse_y, ctx_ptr)
					if unsafe { exp_node != nil } {
						mut en := unsafe { exp_node }
						en.expanded = !en.expanded
						if tv.on_expand != unsafe { nil } {
							tv.on_expand(exp_node, en.expanded)
						}
						return true
					}
					if tv.editable {
						tv.begin_edit(node)
					} else if node.has_children() {
						mut n := unsafe { node }
						n.expanded = !n.expanded
						if tv.on_expand != unsafe { nil } {
							tv.on_expand(node, n.expanded)
						}
					}
					if tv.on_dbl_click != unsafe { nil } {
						tv.on_dbl_click(node)
					}
				}
				return true
			}
		}
		.mouse_wheel {
			if !tv.wheel {
				return false
			}
			if !tv.focused {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if tv.bounds.contains(mx, my) && unsafe { ctx_ptr != nil } {
				if event.shift() {
					old := tv.scroll_x
					tv.scroll_x -= event.wheel_y * tv.scroll_speed
					tv.scroll_x = clamp_f32(tv.scroll_x, 0, tv.max_scroll_x(ctx_ptr))
					return tv.scroll_x != old
				}
				old := tv.scroll_y
				tv.scroll_y -= event.wheel_y * tv.scroll_speed
				tv.scroll_y = clamp_f32(tv.scroll_y, 0, tv.max_scroll_y(ctx_ptr))
				return tv.scroll_y != old
			}
		}
		.key_down {
			if !tv.focused {
				return false
			}
			return tv.handle_key(event, ctx_ptr)
		}
		else {}
	}

	return false
}

// ─── Inline edit event handler ─────────────────────────

fn (mut tv TreeView) handle_edit_event(event &GuiEvent, app &App, ctx_ptr &RenderContext) bool {
	match event.typ {
		.text_input {
			// Ignore text_input when Ctrl is held (Ctrl+V etc. handled via key_down)
			mod_state := C.SDL_GetModState()
			if (mod_state & sdl_kmod_ctrl) != 0 {
				return true
			}
			tv.edit_insert(event.text)
			return true
		}
		.key_down {
			c := event.ctrl()
			s := event.shift()

			// Home/End scancode
			if tv_is_home_key(event.keycode, event.scancode) {
				if s {
					tv.edit_ensure_sel()
				}
				tv.edit_cur = 0
				if s {
					tv.edit_sel_b = 0
				} else {
					tv.edit_clear_sel()
				}
				return true
			}
			if tv_is_end_key(event.keycode, event.scancode) {
				if s {
					tv.edit_ensure_sel()
				}
				tv.edit_cur = tv.edit_buf.len
				if s {
					tv.edit_sel_b = tv.edit_buf.len
				} else {
					tv.edit_clear_sel()
				}
				return true
			}

			match event.keycode {
				sdl_k_return {
					tv.commit_edit()
					return true
				}
				sdl_k_escape {
					tv.cancel_edit()
					return true
				}
				sdl_k_backspace {
					if tv.edit_has_sel() {
						tv.edit_save_undo()
						tv.edit_delete_sel()
					} else if tv.edit_cur > 0 {
						tv.edit_save_undo()
						mut out := []rune{cap: tv.edit_buf.len - 1}
						for i in 0 .. tv.edit_cur - 1 {
							out << tv.edit_buf[i]
						}
						for i in tv.edit_cur .. tv.edit_buf.len {
							out << tv.edit_buf[i]
						}
						tv.edit_buf = out
						tv.edit_cur--
					}
					return true
				}
				sdl_k_delete {
					if tv.edit_has_sel() {
						tv.edit_save_undo()
						tv.edit_delete_sel()
					} else if tv.edit_cur < tv.edit_buf.len {
						tv.edit_save_undo()
						mut out := []rune{cap: tv.edit_buf.len - 1}
						for i in 0 .. tv.edit_cur {
							out << tv.edit_buf[i]
						}
						for i in tv.edit_cur + 1 .. tv.edit_buf.len {
							out << tv.edit_buf[i]
						}
						tv.edit_buf = out
					}
					return true
				}
				sdl_k_left {
					if s {
						tv.edit_ensure_sel()
					}
					if !s && tv.edit_has_sel() {
						tv.edit_cur = tv.edit_sel_lo()
						tv.edit_clear_sel()
					} else {
						if tv.edit_cur > 0 {
							tv.edit_cur--
						}
						if s {
							tv.edit_sel_b = tv.edit_cur
						} else {
							tv.edit_clear_sel()
						}
					}
					return true
				}
				sdl_k_right {
					if s {
						tv.edit_ensure_sel()
					}
					if !s && tv.edit_has_sel() {
						tv.edit_cur = tv.edit_sel_hi()
						tv.edit_clear_sel()
					} else {
						if tv.edit_cur < tv.edit_buf.len {
							tv.edit_cur++
						}
						if s {
							tv.edit_sel_b = tv.edit_cur
						} else {
							tv.edit_clear_sel()
						}
					}
					return true
				}
				sdl_k_a {
					if c {
						tv.edit_sel_a = 0
						tv.edit_sel_b = tv.edit_buf.len
						tv.edit_cur = tv.edit_buf.len
						return true
					}
				}
				sdl_k_c {
					if c {
						if tv.edit_has_sel() {
							app.set_clipboard(tv.edit_selected_text())
						}
						return true
					}
				}
				sdl_k_x {
					if c {
						if tv.edit_has_sel() {
							app.set_clipboard(tv.edit_selected_text())
							tv.edit_save_undo()
							tv.edit_delete_sel()
						}
						return true
					}
				}
				sdl_k_v {
					if c {
						cl := app.get_clipboard()
						if cl.len > 0 {
							filtered := cl.replace('\n', ' ').replace('\r', '')
							tv.edit_insert(filtered)
						}
						return true
					}
				}
				sdl_k_z {
					if c && s {
						tv.edit_perform_redo()
						return true
					} else if c {
						tv.edit_perform_undo()
						return true
					}
				}
				sdl_k_insert {
					if c {
						// Ctrl+Insert = Copy
						if tv.edit_has_sel() {
							app.set_clipboard(tv.edit_selected_text())
						}
						return true
					} else if s {
						// Shift+Insert = Paste
						cl := app.get_clipboard()
						if cl.len > 0 {
							filtered := cl.replace('\n', ' ').replace('\r', '')
							tv.edit_insert(filtered)
						}
						return true
					}
				}
				sdl_k_tab {
					tv.commit_edit()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.tab(event.shift())
					}
					return true
				}
				else {}
			}

			return true
		}
		.mouse_down {
			if event.mouse_btn == .left {
				if tv.hovered && unsafe { ctx_ptr != nil } {
					node, _ := tv.hit_node(event.mouse_y, ctx_ptr)
					if unsafe { node != nil } && voidptr(node) == voidptr(tv.edit_node) {
						tv.edit_hit_cursor(event.mouse_x, ctx_ptr)
						tv.edit_sel_a = tv.edit_cur
						tv.edit_sel_b = tv.edit_cur
						tv.edit_drag = true
						return true
					}
				}
				tv.commit_edit()
				return false
			}
		}
		.mouse_move {
			if tv.edit_drag && unsafe { ctx_ptr != nil } {
				tv.edit_hit_cursor(event.mouse_x, ctx_ptr)
				tv.edit_sel_b = tv.edit_cur
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && tv.edit_drag {
				tv.edit_drag = false
				if tv.edit_sel_a == tv.edit_sel_b {
					tv.edit_clear_sel()
				}
				return true
			}
		}
		.mouse_dbl_click {
			if tv.hovered && unsafe { ctx_ptr != nil } {
				node, _ := tv.hit_node(event.mouse_y, ctx_ptr)
				if unsafe { node != nil } && voidptr(node) == voidptr(tv.edit_node) {
					// Select word at cursor
					tv.edit_select_word()
					return true
				}
			}
		}
		.mouse_wheel {
			if !tv.wheel {
				return false
			}
			if !tv.focused {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if tv.bounds.contains(mx, my) && unsafe { ctx_ptr != nil } {
				old := tv.scroll_y
				tv.scroll_y -= event.wheel_y * tv.scroll_speed
				tv.scroll_y = clamp_f32(tv.scroll_y, 0, tv.max_scroll_y(ctx_ptr))
				return tv.scroll_y != old
			}
		}
		else {}
	}

	return false
}

fn (mut tv TreeView) edit_select_word() {
	if tv.edit_buf.len == 0 {
		return
	}
	p := clamp_int(tv.edit_cur, 0, tv.edit_buf.len - 1)
	mut a := p
	mut b := p
	for a > 0 && is_word(tv.edit_buf[a - 1]) {
		a--
	}
	for b < tv.edit_buf.len && is_word(tv.edit_buf[b]) {
		b++
	}
	tv.edit_sel_a = a
	tv.edit_sel_b = b
	tv.edit_cur = b
}

fn (mut tv TreeView) edit_hit_cursor(mx f32, ctx_ptr &RenderContext) {
	if unsafe { ctx_ptr == nil } || unsafe { tv.edit_node == nil } {
		return
	}
	flat := tv.build_flat()
	inner := tv.inner_rect()
	font := ctx_ptr.get_font_immut(.regular, 0)

	for i, fn_ in flat {
		if fn_.node != unsafe { tv.edit_node } {
			continue
		}
		depth_x := inner.x + f32(fn_.depth) * tv.indent - tv.scroll_x
		mut content_x := depth_x + tv.indent
		if fn_.node.icon_path.len > 0 {
			content_x += tv.icon_size + tv.icon_gap
		}
		local_x := mx - content_x + tv.edit_scroll_x
		if local_x <= 0 {
			tv.edit_cur = 0
			return
		}
		mut best := 0
		mut best_d := abs_f32(local_x)
		for j := 1; j <= tv.edit_buf.len; j++ {
			w := ctx_ptr.measure_text_with_font(tv.edit_buf[..j].string(), font).x
			d := abs_f32(w - local_x)
			if d < best_d {
				best_d = d
				best = j
			}
		}
		tv.edit_cur = best
		_ = i
		return
	}
}

// ─── Keyboard navigation (non-edit mode) ───────────────

fn (mut tv TreeView) handle_key(event &GuiEvent, ctx_ptr &RenderContext) bool {
	flat := tv.build_flat()
	idx := if unsafe { tv.selected != nil } { tv.flat_index_of(tv.selected) } else { -1 }

	// Home/End via scancode (same fix as TextInput)
	if tv_is_home_key(event.keycode, event.scancode) {
		if flat.len > 0 {
			tv.selected = flat[0].node
			if unsafe { ctx_ptr != nil } {
				tv.ensure_visible(ctx_ptr)
			}
			tv.fire_select()
		}
		return true
	}
	if tv_is_end_key(event.keycode, event.scancode) {
		if flat.len > 0 {
			tv.selected = flat[flat.len - 1].node
			if unsafe { ctx_ptr != nil } {
				tv.ensure_visible(ctx_ptr)
			}
			tv.fire_select()
		}
		return true
	}

	if tv_is_pageup_key(event.keycode, event.scancode) {
		if flat.len > 0 {
			inner := tv.inner_rect()
			page := max_int(1, int(inner.h / tv.item_height))
			new_idx := if idx > 0 { max_int(0, idx - page) } else { 0 }
			tv.selected = flat[new_idx].node
			if unsafe { ctx_ptr != nil } {
				tv.ensure_visible(ctx_ptr)
			}
			tv.fire_select()
		}
		return true
	}
	if tv_is_pagedown_key(event.keycode, event.scancode) {
		if flat.len > 0 {
			inner := tv.inner_rect()
			page := max_int(1, int(inner.h / tv.item_height))
			cur_idx := if idx >= 0 { idx } else { 0 }
			new_idx := min_int(flat.len - 1, cur_idx + page)
			tv.selected = flat[new_idx].node
			if unsafe { ctx_ptr != nil } {
				tv.ensure_visible(ctx_ptr)
			}
			tv.fire_select()
		}
		return true
	}

	match event.keycode {
		sdl_k_up {
			if idx > 0 {
				tv.selected = flat[idx - 1].node
				if unsafe { ctx_ptr != nil } {
					tv.ensure_visible(ctx_ptr)
				}
				tv.fire_select()
			} else if idx < 0 && flat.len > 0 {
				tv.selected = flat[0].node
				if unsafe { ctx_ptr != nil } {
					tv.ensure_visible(ctx_ptr)
				}
				tv.fire_select()
			}
			return true
		}
		sdl_k_down {
			if idx >= 0 && idx < flat.len - 1 {
				tv.selected = flat[idx + 1].node
				if unsafe { ctx_ptr != nil } {
					tv.ensure_visible(ctx_ptr)
				}
				tv.fire_select()
			} else if idx < 0 && flat.len > 0 {
				tv.selected = flat[0].node
				if unsafe { ctx_ptr != nil } {
					tv.ensure_visible(ctx_ptr)
				}
				tv.fire_select()
			}
			return true
		}
		sdl_k_left {
			if unsafe { tv.selected != nil } {
				if tv.selected.expanded && tv.selected.has_children() {
					mut s := unsafe { tv.selected }
					s.expanded = false
					if tv.on_expand != unsafe { nil } {
						tv.on_expand(tv.selected, false)
					}
				} else if unsafe { tv.selected.parent != nil } {
					tv.selected = tv.selected.parent
					if unsafe { ctx_ptr != nil } {
						tv.ensure_visible(ctx_ptr)
					}
					tv.fire_select()
				}
			}
			return true
		}
		sdl_k_right {
			if unsafe { tv.selected != nil } && tv.selected.has_children() {
				if !tv.selected.expanded {
					mut s := unsafe { tv.selected }
					s.expanded = true
					if tv.on_expand != unsafe { nil } {
						tv.on_expand(tv.selected, true)
					}
				} else if tv.selected.children.len > 0 {
					tv.selected = tv.selected.children[0]
					if unsafe { ctx_ptr != nil } {
						tv.ensure_visible(ctx_ptr)
					}
					tv.fire_select()
				}
			}
			return true
		}
		sdl_k_return, sdl_k_space {
			if unsafe { tv.selected != nil } && tv.selected.has_children() {
				mut s := unsafe { tv.selected }
				s.expanded = !s.expanded
				if tv.on_expand != unsafe { nil } {
					tv.on_expand(tv.selected, s.expanded)
				}
			}
			return true
		}
		sdl_k_f2 {
			if tv.editable && unsafe { tv.selected != nil } {
				tv.begin_edit(tv.selected)
			}
			return false
		}
		sdl_k_tab {
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				ctx_mut.focus.tab(event.shift())
			}
			return true
		}
		sdl_k_escape {
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				ctx_mut.focus.blur_current()
			}
			return true
		}
		else {}
	}

	return false
}

// ─── Scrollbar drag handlers ───────────────────────────

fn (mut tv TreeView) handle_vsb_drag(event &GuiEvent, ctx_ptr &RenderContext) bool {
	match event.typ {
		.mouse_move {
			if unsafe { ctx_ptr == nil } {
				return true
			}
			track, _ := tv.vsb_rects(ctx_ptr)
			if track.h <= 0 {
				return true
			}
			_, ch := tv.content_size(ctx_ptr)
			vis_h := track.h
			thumb_h := max_f32(20, vis_h * (vis_h / ch))
			drag_range := vis_h - thumb_h
			if drag_range <= 0 {
				return true
			}
			dy := event.mouse_y - tv.vsb_drag_start_y
			ms := tv.max_scroll_y(ctx_ptr)
			tv.scroll_y = clamp_f32(tv.vsb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
			return true
		}
		.mouse_up {
			if event.mouse_btn == .left {
				tv.vsb_dragging = false
				return true
			}
		}
		else {}
	}

	return true
}

fn (mut tv TreeView) handle_hsb_drag(event &GuiEvent, ctx_ptr &RenderContext) bool {
	match event.typ {
		.mouse_move {
			if unsafe { ctx_ptr == nil } {
				return true
			}
			track, _ := tv.hsb_rects(ctx_ptr)
			if track.w <= 0 {
				return true
			}
			cw, _ := tv.content_size(ctx_ptr)
			vis_w := track.w
			thumb_w := max_f32(20, vis_w * (vis_w / cw))
			drag_range := vis_w - thumb_w
			if drag_range <= 0 {
				return true
			}
			dx := event.mouse_x - tv.hsb_drag_start_x
			ms := tv.max_scroll_x(ctx_ptr)
			tv.scroll_x = clamp_f32(tv.hsb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
			return true
		}
		.mouse_up {
			if event.mouse_btn == .left {
				tv.hsb_dragging = false
				return true
			}
		}
		else {}
	}

	return true
}
