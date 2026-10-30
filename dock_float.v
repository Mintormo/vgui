module vgui

// Файл dock_float.v: плавающие панели DockArea - панель (или несколько вкладками) в отдельном окне
// ОС, как в Visual Studio и Qt Advanced Docking. Остальное устройство области - dock_area.v.
//
// Устройство. Плавающее окно (DockFloat) - обычное окно ОС, корневой виджет которого - своя
// DockArea («область окна», float_owner - главная область). Поэтому внутри плавающего окна работает
// всё то же, что в главной области: вкладки, разбиения, перенос, закрытие. Главная область держит
// список своих плавающих окон (floats) и остаётся единственной точкой API: dock / show_panel /
// close_panel / is_open / save_layout видят и плавающие панели.
//
// Окно - служебное (Window.tool_owner = окно главной области): не держит приложение открытым и
// закрывается вместе с главным окном (App.update_running). Своего App у виджета нет - область
// узнаёт приложение и своё окно из контекста в arrange() (RenderContext.app/window). Создают и
// убирают окна только через app.post: область работает внутри цикла по app.windows (события,
// отрисовка), и менять этот список прямо там нельзя.
//
// Жесты:
//   - вкладку вытащили за пределы своего окна и отпустили не над другой областью - панель уплывает
//     в новое окно под курсором (из плавающего окна с одной панелью - окно просто переезжает);
//   - над областью другого окна (главного или плавающего) - предпросмотр рисует та область
//     (ext_drop), отпускание вставляет панель туда: так панель возвращают из плавающего окна;
//   - двойной щелчок по вкладке: в главной области - уплыть, в плавающем окне - вернуться на место,
//     откуда уплыла (запоминается в float_panel, как при закрытии);
//   - закрыли плавающее окно (крестик ОС) - его панели возвращаются в главную область.
// Перенос между окнами опирается на экранные координаты (dnd_to_screen / dnd_window_under, dnd.v);
// на Wayland окно своей позиции не знает - там работают двойной щелчок и закрытие окна.
//
// Содержимое панели при переезде меняет окно: всё, что виджет держит от окна, обязано это
// переживать. Текстуры картинок проверяют belongs_to(ctx) и перезагружаются (ImageView,
// ImageBackground, Canvas; кэши иконок и текста - у каждого окна свои); фокус-учёт и наведение
// пересобираются каждым кадром. Раздел PROJECT.md - «Docking: DockArea и DockPanel», «Плавающие
// панели».

// Размер плавающего окна по умолчанию (логические пиксели) и отступ от угла окна-владельца, если
// позиция не задана.
const dock_float_default_w = 420
const dock_float_default_h = 320
const dock_float_offset = 60

// DockFloat - плавающее окно главной области: своя область (area), окно ОС (nil - ещё не создано:
// ждёт app.post) и его геометрия (экранная позиция в пикселях, размер в логических единицах).
// Геометрию окно обновляет само (sync_geometry) - из неё сохраняется раскладка.
@[heap]
struct DockFloat {
mut:
	area     &DockArea = unsafe { nil }
	win      &Window   = unsafe { nil }
	x        int       = -1
	y        int       = -1
	w        int       = dock_float_default_w
	h        int       = dock_float_default_h
	creating bool // окно заказано через app.post, ещё не создано
	closing  bool // окно закрывается: повторно не закрывать и не наполнять
}

// DockFloatSpec - плавающее окно из строки раскладки: геометрия и раскладка его области (строка
// того же формата, что save_layout).
struct DockFloatSpec {
	x      int
	y      int
	w      int
	h      int
	layout string
}

// DockFloatAt - где открыть плавающее окно: экранная позиция в пикселях (-1 - рядом с углом
// окна-владельца) и размер в логических единицах (0 - по месту, которое панель занимала, иначе
// размер по умолчанию).
@[params]
pub struct DockFloatAt {
pub:
	x int = -1
	y int = -1
	w int
	h int
}

// ─── Публичный API (главная область) ───────────────────

// float_panel выносит панель в отдельное окно ОС. Окно появляется на следующем шаге цикла
// приложения (создаётся через app.post); до первой раскладки области (пока приложение неизвестно)
// - после неё. Место в области запоминается: dock_back и закрытие окна вернут панель туда.
pub fn (mut da DockArea) float_panel(p &DockPanel, at DockFloatAt) {
	mut root := da.root_area()
	if !root.allow_float {
		return
	}
	widget_changed()
	root.register(p)
	// Размер - по месту, которое панель занимала (содержимое группы с полосой вкладок)
	mut w, mut h := at.w, at.h
	if g := root.group_of(p) {
		if w <= 0 {
			w = int(g.rect.w)
		}
		if h <= 0 {
			h = int(g.rect.h)
		}
		root.remember_place(p)
	}
	root.take_from_float(p)
	root.detach_panel(p)
	root.reset_pointer_state()
	mut f := root.new_float(at.x, at.y, if w > 0 { w } else { dock_float_default_w }, if h > 0 {
		h
	} else {
		dock_float_default_h
	})
	f.area.dock(p, .center)
	root.ensure_float_windows()
	root.fire_change()
}

// dock_back возвращает плавающую панель в главную область - на место, откуда она уплыла (рядом
// с той же соседней панелью), а если соседа нет - в первую группу. Не плавающая - ничего.
pub fn (mut da DockArea) dock_back(p &DockPanel) {
	mut root := da.root_area()
	if !root.is_floating(p) {
		return
	}
	widget_changed()
	root.take_from_float(p)
	if near_panel := root.open_panel_by_id(p.restore_near) {
		root.dock(p, p.restore_side, target: near_panel, size: p.restore_size)
	} else {
		root.dock(p, .center)
	}
	root.fire_change()
}

// is_floating - панель открыта в плавающем окне.
pub fn (da &DockArea) is_floating(p &DockPanel) bool {
	return da.float_of(p) != none
}

// floating_panels - панели, открытые в плавающих окнах.
pub fn (da &DockArea) floating_panels() []&DockPanel {
	mut out := []&DockPanel{}
	for f in da.root_area().floats {
		for g in f.area.groups() {
			out << g.panels
		}
	}
	return out
}

// ─── Внутреннее: области и окна ────────────────────────

// root_area - главная область (у области плавающего окна - её владелец).
fn (da &DockArea) root_area() &DockArea {
	return if isnil(da.float_owner) { unsafe { da } } else { da.float_owner }
}

// float_of - плавающее окно, в котором открыта панель.
fn (da &DockArea) float_of(p &DockPanel) ?&DockFloat {
	for f in da.root_area().floats {
		if f.area.group_of(p) != none {
			return f
		}
	}
	return none
}

// new_float - плавающее окно (пока без окна ОС) с пустой областью; настройки области - как у главной.
fn (mut da DockArea) new_float(x int, y int, w int, h int) &DockFloat {
	area := &DockArea{
		float_owner: unsafe { da }
		bar_size:    da.bar_size
		min_pane:    da.min_pane
		tab_pad:     da.tab_pad
		allow_float: da.allow_float
		app:         da.app
	}
	f := &DockFloat{
		area: area
		x:    x
		y:    y
		w:    w
		h:    h
	}
	da.floats << f
	return f
}

// take_panel снимает панель с того места, где она открыта: со своего дерева, с дерева главной
// области (эта - область плавающего окна) или с другого плавающего окна (опустевшее закрывается).
// Перед вставкой панели в любое место (dock) - иначе она осталась бы открытой в двух окнах.
fn (mut da DockArea) take_panel(p &DockPanel) {
	if da.group_of(p) != none {
		da.detach_panel(p)
		return
	}
	mut root := da.root_area()
	if !dock_same(root, da) && root.group_of(p) != none {
		root.detach_panel(p)
		return
	}
	if f := root.float_of(p) {
		if !dock_same(f.area, da) {
			root.take_from_float(p)
		}
	}
}

// take_from_float снимает панель с плавающего окна; опустевшее окно закрывается.
fn (mut da DockArea) take_from_float(p &DockPanel) {
	mut root := da.root_area()
	mut f := root.float_of(p) or { return }
	f.area.detach_panel(p)
	f.area.reset_pointer_state()
	if f.area.panel_count() == 0 {
		root.close_float(mut f)
	}
}

// show_floating - сделать плавающую панель активной вкладкой и поднять её окно; false - панель не
// плавает.
fn (mut da DockArea) show_floating(p &DockPanel) bool {
	mut f := da.root_area().float_of(p) or { return false }
	if mut g := f.area.group_of(p) {
		g.active = dock_panel_index(g.panels, p)
	}
	if !isnil(f.win) {
		mut w := f.win
		w.raise()
	}
	return true
}

// learn_context - окно и приложение области из контекста (arrange). Главная область заодно
// заказывает окна ОС плавающим окнам, которым их ещё не завели (float_panel или load_layout до
// того, как приложение стало известно), и держит заголовки, тему и стили плавающих окон в
// согласии со своим окном.
fn (mut da DockArea) learn_context(ctx &RenderContext) {
	if !isnil(ctx.window) {
		da.own_win = ctx.window
	}
	if !isnil(ctx.app) {
		da.app = ctx.app
	}
	if !isnil(da.float_owner) {
		return
	}
	da.ensure_float_windows()
	da.sync_float_windows()
}

// ensure_float_windows заказывает окна ОС плавающим окнам, у которых их ещё нет (через app.post:
// область сейчас внутри цикла по окнам приложения).
fn (mut da DockArea) ensure_float_windows() {
	if isnil(da.app) || isnil(da.own_win) {
		return
	}
	for mut f in da.floats {
		if !isnil(f.win) || f.creating || f.closing {
			continue
		}
		f.creating = true
		// Захват - указателями: `mut x := da` скопировал бы структуру, и замыкание работало бы с
		// копией (адрес окна не совпал бы со списком floats)
		mut root := unsafe { &da }
		mut fl := unsafe { f }
		create := fn [mut root, mut fl] () {
			root.create_float_window(mut fl)
		}
		mut app := da.app
		app.post(create)
	}
}

// create_float_window - окно ОС плавающей панели (из app.post): служебное окно владельца, тема и
// стили - как у владельца, корневой виджет - область плавающего окна. Не создалось - панели
// возвращаются в главную область.
fn (mut da DockArea) create_float_window(mut f DockFloat) {
	f.creating = false
	if f.closing || isnil(da.app) || isnil(da.own_win) {
		return
	}
	owner := da.own_win
	mut x, mut y := f.x, f.y
	if x < 0 || y < 0 {
		ox, oy := owner.position()
		x, y = ox + dock_float_offset, oy + dock_float_offset
	}
	mut win := create_window(
		title:      f.area.float_title()
		width:      f.w
		height:     f.h
		x:          x
		y:          y
		min_width:  160
		min_height: 100
	) or {
		da.dock_float_panels_back(mut f)
		return
	}
	win.tool_owner = owner
	win.add_widget(f.area)
	mut root := unsafe { &da } // указатели, не копии (см. ensure_float_windows)
	mut fl := unsafe { &f }
	on_close := fn [mut root, mut fl] (mut _ Window) {
		root.on_float_closed(mut fl)
	}
	win.on_close = on_close
	mut app := da.app
	app.add_window(win)
	if owner.theme_explicit {
		win.set_theme(owner.unstyled_theme())
	}
	if owner.css_explicit {
		win.set_stylesheet(owner.stylesheet())
	}
	f.win = win
	f.x, f.y = x, y
	widget_changed()
}

// sync_float_windows - каждой раскладкой главной области: заголовок окна - активная панель, тема и
// стили - как у владельца (их могли сменить), геометрия запоминается (для save_layout).
fn (mut da DockArea) sync_float_windows() {
	owner := da.own_win
	for mut f in da.floats {
		if isnil(f.win) || f.closing {
			continue
		}
		mut win := f.win
		title := f.area.float_title()
		if win.config.title != title {
			win.set_title(title)
		}
		if !isnil(owner) {
			if owner.theme_explicit && dock_theme_differs(win.unstyled_theme(), owner.unstyled_theme()) {
				win.set_theme(owner.unstyled_theme())
			}
			if owner.css_explicit && voidptr(win.stylesheet()) != voidptr(owner.stylesheet()) {
				win.set_stylesheet(owner.stylesheet())
			}
		}
		f.x, f.y = win.position()
		f.w, f.h = win.config.width, win.config.height
	}
}

// dock_theme_differs - сменилась ли тема: сравниваются основные цвета (смена темы их всегда
// меняет), а не вся структура Theme (~1 КБ полей на каждую раскладку).
fn dock_theme_differs(a Theme, b Theme) bool {
	return a.bg != b.bg || a.surface != b.surface || a.text_primary != b.text_primary
		|| a.accent != b.accent || a.border != b.border
}

// float_title - заголовок плавающего окна: активная панель первой группы.
fn (da &DockArea) float_title() string {
	for g in da.groups() {
		if g.panels.len > 0 {
			return g.panels[g.active].title
		}
	}
	return ''
}

// on_float_closed - окно плавающей панели закрыли (крестик ОС, закрытие владельца или опустело):
// панели - в главную область, окно убирается из приложения на следующем шаге цикла.
fn (mut da DockArea) on_float_closed(mut f DockFloat) {
	if f.closing {
		return
	}
	f.closing = true
	da.dock_float_panels_back(mut f)
	da.forget_float(f)
	if isnil(f.win) || isnil(da.app) {
		return
	}
	mut win := f.win
	f.win = unsafe { nil }
	mut app := da.app
	remove := fn [mut app, mut win] () {
		app.remove_window(win)
		win.cleanup()
	}
	app.post(remove)
	da.fire_change()
}

// close_float - закрыть плавающее окно кодом (опустело): дальше - как крестиком ОС.
fn (mut da DockArea) close_float(mut f DockFloat) {
	if f.closing {
		return
	}
	if isnil(f.win) {
		// окна ещё нет (заказано или приложение неизвестно) - просто забыть
		f.closing = true
		da.dock_float_panels_back(mut f)
		da.forget_float(f)
		return
	}
	mut win := f.win
	win.close() // on_close -> on_float_closed
}

// dock_float_panels_back - все панели плавающего окна - в главную область, на запомненные места.
fn (mut da DockArea) dock_float_panels_back(mut f DockFloat) {
	mut panels := []&DockPanel{}
	for g in f.area.groups() {
		panels << g.panels
	}
	for p in panels {
		f.area.detach_panel(p)
		if near_panel := da.open_panel_by_id(p.restore_near) {
			da.dock(p, p.restore_side, target: near_panel, size: p.restore_size)
		} else {
			da.dock(p, .center)
		}
	}
	f.area.root = unsafe { nil }
	f.area.reset_pointer_state()
}

// forget_float - убрать окно из списка главной области.
fn (mut da DockArea) forget_float(f &DockFloat) {
	for i, g in da.floats {
		if dock_same(g, f) {
			da.floats.delete(i)
			return
		}
	}
}

// ─── Перенос между окнами ──────────────────────────────

// track_ext_target - переносимая вкладка за пределами своей области: найти область в окне под
// курсором (главную или плавающую, кроме своей) и показать в ней предпросмотр сброса.
fn (mut da DockArea) track_ext_target(p &DockPanel, x f32, y f32) {
	target, lx, ly := da.area_under(x, y)
	if isnil(target) {
		da.set_ext_target(unsafe { nil }, DockDrop{})
		return
	}
	mut t := unsafe { target }
	da.set_ext_target(t, t.compute_drop(p, lx, ly))
}

// set_ext_target - сменить область-цель в другом окне: у прежней предпросмотр гасится.
fn (mut da DockArea) set_ext_target(target &DockArea, drop DockDrop) {
	if !isnil(da.ext_target) && !dock_same(da.ext_target, target) {
		mut old := da.ext_target
		old.ext_drop = DockDrop{}
	}
	da.ext_target = unsafe { target }
	if !isnil(target) {
		mut t := unsafe { target }
		t.ext_drop = drop
	}
	widget_changed() // предпросмотр рисует другое окно
}

// area_under - область (главная или плавающая, кроме этой) под точкой (x, y) окна этой области
// и точка в координатах её окна; nil - курсор не над областью.
fn (da &DockArea) area_under(x f32, y f32) (&DockArea, f32, f32) {
	if isnil(da.own_win) || isnil(da.app) {
		return unsafe { nil }, x, y
	}
	mut own := da.own_win
	win, lx, ly := dnd_window_under(mut own, x, y, da.app)
	if isnil(win) || dock_same(win, da.own_win) {
		return unsafe { nil }, x, y
	}
	root := da.root_area()
	mut candidates := [root]
	for f in root.floats {
		candidates << f.area
	}
	for c in candidates {
		if dock_same(c, da) || !dock_same(c.own_win, win) {
			continue
		}
		if c.bounds.contains(lx, ly) {
			return c, lx, ly
		}
	}
	return unsafe { nil }, x, y
}

// release_outside - вкладку отпустили за пределами своей области: в область другого окна, если
// курсор над ней; за пределами своего окна - в новое плавающее окно (из плавающего окна с одной
// панелью - окно переезжает под курсор); над своим окном вне области - ничего.
fn (mut da DockArea) release_outside(p &DockPanel, x f32, y f32) {
	target := da.ext_target
	drop := if isnil(target) { DockDrop{} } else { target.ext_drop }
	da.set_ext_target(unsafe { nil }, DockDrop{})
	da.reset_pointer_state()
	mut root := da.root_area()
	if !isnil(target) && drop.kind != .none {
		mut t := unsafe { target }
		da.move_panel_to(p, mut t, drop)
		return
	}
	if isnil(da.own_win) || dnd_window_contains(da.own_win, x, y) || !root.allow_float {
		return
	}
	sx, sy := dnd_to_screen(da.own_win, x, y)
	if !isnil(da.float_owner) && da.panel_count() == 1 {
		// Единственная панель плавающего окна - переносится само окно
		mut f := root.float_of(p) or { return }
		if !isnil(f.win) {
			mut w := f.win
			w.set_position(int(sx) - 20, int(sy) - 10)
		}
		return
	}
	root.float_panel(p, x: int(sx) - 20, y: int(sy) - 10)
}

// move_panel_to - перенести панель из этой области в область target другого окна на место drop.
fn (mut da DockArea) move_panel_to(p &DockPanel, mut target DockArea, drop DockDrop) {
	mut root := da.root_area()
	root.register(p)
	target.register(p)
	if isnil(da.float_owner) {
		// Из главной области в плавающее окно: запомнить место, как float_panel
		root.remember_place(p)
	}
	da.detach_panel(p)
	target.apply_drop(p, drop)
	// Плавающее окно, из которого ушла последняя панель, закрывается
	if !isnil(da.float_owner) && da.panel_count() == 0 {
		mut f := root.float_by_area(da) or { return }
		root.close_float(mut f)
	}
	root.fire_change()
}

// panel_count - сколько панелей открыто в дереве области.
fn (da &DockArea) panel_count() int {
	mut n := 0
	for g in da.groups() {
		n += g.panels.len
	}
	return n
}

// float_by_area - плавающее окно с этой областью.
fn (da &DockArea) float_by_area(area &DockArea) ?&DockFloat {
	for f in da.floats {
		if dock_same(f.area, area) {
			return f
		}
	}
	return none
}

// on_dbl_click - двойной щелчок по вкладке: из главной области - уплыть в окно у курсора, из
// плавающего окна - вернуться на место. Не по вкладке - false.
fn (mut da DockArea) on_dbl_click(x f32, y f32) bool {
	g := da.group_at(x, y)
	if isnil(g) {
		return false
	}
	idx := dock_tab_at(g, x, y)
	if idx < 0 || idx >= g.panels.len {
		return false
	}
	p := g.panels[idx]
	da.reset_pointer_state()
	mut root := da.root_area()
	if !isnil(da.float_owner) {
		root.dock_back(p)
		return true
	}
	if !root.allow_float {
		return false
	}
	mut sx, mut sy := f32(-1), f32(-1)
	if !isnil(da.own_win) {
		sx, sy = dnd_to_screen(da.own_win, x, y)
	}
	root.float_panel(p, x: int(sx) - 20, y: int(sy) - 10)
	return true
}

// draw_ext_drop - предпросмотр сброса панели, которую тянут из другого окна (ext_drop ставит
// переносящая область).
fn (da &DockArea) draw_ext_drop(mut ctx RenderContext) {
	if da.ext_drop.kind == .none {
		return
	}
	accent := ctx.theme.eff_tab_indicator()
	r := da.ext_drop.preview
	ctx.push_clip(da.bounds)
	if da.ext_drop.kind == .tab && r.w <= 3 {
		ctx.fill_rect(r, accent)
	} else {
		ctx.fill_rect(r, accent.with_alpha(60))
		ctx.draw_rect(r, accent)
	}
	ctx.pop_clip()
}

// ─── Раскладка с плавающими окнами ─────────────────────

// save_floats - хвост строки save_layout: по плавающему окну `+F(x,y,w,h)раскладка` (x, y -
// экранная позиция, w, h - размер; раскладка его области - тем же форматом).
fn (da &DockArea) save_floats() string {
	mut sb := []string{}
	for f in da.floats {
		if f.closing || isnil(f.area.root) {
			continue
		}
		inner := f.area.save_layout()
		if inner == '' {
			continue
		}
		sb << '+F(${f.x},${f.y},${f.w},${f.h})${inner}'
	}
	return sb.join('')
}

// split_float_specs - строка раскладки -> раскладка главной области и плавающие окна (`+F(...)`).
// Ошибка - битая запись окна.
fn dock_split_float_specs(text string) !(string, []DockFloatSpec) {
	parts := text.split('+F(')
	mut specs := []DockFloatSpec{}
	for part in parts[1..] {
		close := part.index(')') or { return error('dock layout: `+F(` without `)`') }
		nums := part[..close].split(',').map(it.trim_space())
		if nums.len != 4 || nums.any(!(it.len > 0 && (it[0].is_digit() || it[0] == `-`))) {
			return error('dock layout: bad float window `${part[..close]}`')
		}
		specs << DockFloatSpec{
			x:      nums[0].int()
			y:      nums[1].int()
			w:      nums[2].int()
			h:      nums[3].int()
			layout: part[close + 1..].trim_space()
		}
	}
	return parts[0].trim_space(), specs
}

// open_float_spec - плавающее окно из раскладки: панели ищутся по id среди известных главной
// области (как в load_layout); если ни одной не нашлось - окна нет.
fn (mut da DockArea) open_float_spec(spec DockFloatSpec) {
	mut f := da.new_float(spec.x, spec.y, if spec.w > 0 { spec.w } else { dock_float_default_w },
		if spec.h > 0 { spec.h } else { dock_float_default_h })
	// Область окна знает панели главной (поиск по id в разборе раскладки)
	f.area.panels = da.panels.clone()
	f.area.load_layout(spec.layout) or {}
	if isnil(f.area.root) {
		da.forget_float(f)
		return
	}
	// Панели окна уходят из главной области (разбор главной мог их открыть)
	for g in f.area.groups() {
		for p in g.panels {
			da.detach_panel(p)
		}
	}
}

// load_floats - плавающие окна из раскладки: прежние убираются (их панели раскладка расставит
// заново), новые открываются сразу; окна ОС им заказываются сейчас или - пока приложение
// неизвестно - при первой раскладке главной области (learn_context).
fn (mut da DockArea) load_floats(specs []DockFloatSpec) {
	for mut f in da.floats.clone() {
		f.closing = true
		f.area.root = unsafe { nil }
		if !isnil(f.win) && !isnil(da.app) {
			mut win := f.win
			f.win = unsafe { nil }
			mut app := da.app
			remove := fn [mut app, mut win] () {
				win.close()
				app.remove_window(win)
				win.cleanup()
			}
			app.post(remove)
		}
	}
	da.floats = []&DockFloat{}
	for spec in specs {
		da.open_float_spec(spec)
	}
	da.ensure_float_windows()
}
