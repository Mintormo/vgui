module vgui

// ═══════════════════════════════════════════════════════
// DropZone — a rectangular target that accepts files/text
// dropped onto it from outside the application.
//
// A drop event carries window-relative coordinates (in ev.mouse_x/mouse_y).
// The zone consumes drop_file / drop_text only when those coordinates fall
// inside its bounds, so several zones can coexist and a window-level handler
// still gets any drop that misses every zone.
//
// While a drag hovers over the zone (drop_position) it highlights itself;
// drop_complete / drop_begin reset that state.
//
// Optionally the zone is *clickable*: when `click_to_browse` is set, a left
// click opens the native OS file-open dialog and feeds the chosen path(s) into `on_drop_file` — the same
// callback a real drop uses. So the zone becomes a dual-input target: drag a
// file in, or click to pick one.
// ═══════════════════════════════════════════════════════

// DropZone - прямоугольная цель для перетаскивания файлов/текста в окно (SDL3 drag-and-drop) с необязательным
// режимом «клик = выбрать файл». События drop_* приходят от окна (events.v); координаты курсора - в mouse_x/y.
// Колбэки: on_drop_file(path) - путь сброшенного (или выбранного кликом) файла, on_drop_text(text) - сброшенный
// текст. accept_files / accept_text отключают приём соответствующего вида. hovering - над зоной сейчас
// перетаскивание (подсветка), pressed - ЛКМ зажата внутри зоны в режиме click_to_browse.
// Все поля browse_* используются только при click_to_browse = true (см. dz_open_browse).
@[heap]
pub struct DropZone {
pub mut:
	type_tag     int = kind_drop_zone // тег типа, см. widget_tag.v
	css          CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds       Rect
	text         string = 'Перетащите файлы сюда'
	visible      bool   = true
	enabled      bool   = true // false - сбросы и клик не принимаются, вид приглушён (enabled.v)
	tooltip      string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd          &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	accept_files bool      = true
	accept_text  bool      = true
	hovering     bool // drag currently over the zone
	// Click-to-browse: a left click opens a file-open dialog.
	click_to_browse        bool
	browse_multi           bool // allow selecting several files
	browse_start_dir       string
	browse_filter_names    []string
	browse_filter_patterns []string
	pressed                bool // left button currently held inside the zone
	// path string for a dropped file, or text for dropped text
	on_drop_file fn (path string) = unsafe { nil }
	on_drop_text fn (text string) = unsafe { nil }
}

// drop_zone создаёт зону с подписью text (может быть многострочной, разделитель '\n').
pub fn drop_zone(text string) &DropZone {
	return &DropZone{
		text: text
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw рисует скруглённую панель (при подсветке - фон подмешан к акценту, рамка акцентная) и подпись по центру, строка за строкой.
pub fn (mut d DropZone) draw(mut ctx RenderContext) {
	if !d.visible {
		return
	}
	if !ctx.is_in_clip(d.bounds) {
		return
	}

	radius := ctx.theme.border_radius
	en := ctx.is_enabled(d.enabled)
	// Background and border brighten while a drag hovers over the zone, or
	// while a click-to-browse press is held.
	highlight := (d.hovering || d.pressed) && en
	bg := if highlight {
		mix_with_accent(ctx.theme.panel_bg, ctx.theme.accent, 0.18)
	} else {
		ctx.theme.panel_bg
	}
	border := if highlight { ctx.theme.accent } else { ctx.theme.border }

	ctx.fill_rounded_rect(d.bounds, bg, radius)
	ctx.draw_rounded_rect(d.bounds, border, radius)

	if d.text.len > 0 {
		// Подпись может быть в несколько строк («\n»): каждая - по центру
		font := ctx.get_font(.regular, 0)
		sz := measure_text_lines(ctx, d.text, font, 2)
		fh := ctx.font_height_of(font)
		fg := if !en {
			ctx.theme.text_disabled
		} else if highlight {
			ctx.theme.accent
		} else {
			ctx.theme.text_secondary
		}
		ctx.push_clip(d.bounds)
		mut ty := d.bounds.y + (d.bounds.h - sz.y) * 0.5
		for line in d.text.split('\n') {
			lw := ctx.measure_text_with_font(line, font).x
			ctx.draw_text_with_font(line, d.bounds.x + (d.bounds.w - lw) * 0.5, ty, fg, font)
			ty += fh + 2
		}
		ctx.pop_clip()
	}
}

// ─── Events ────────────────────────────────────────────

// handle_event обрабатывает два независимых потока событий.
// 1) Мышь (только если click_to_browse): нажатие и отпускание ЛКМ внутри зоны = клик, который открывает диалог выбора (dz_open_browse).
// 2) drop_*: drop_position подсвечивает зону, но НЕ поглощает событие (чтобы остальные зоны тоже его увидели);
//    drop_file / drop_text поглощаются (true) только если точка сброса внутри bounds и приём разрешён - иначе
//    событие уходит дальше, например в обработчик на уровне окна.
pub fn (mut d DropZone) handle_event(event &GuiEvent, app &App) bool {
	if !d.visible {
		return false
	}
	if !d.enabled {
		d.hovering = false
		d.pressed = false
		return false
	}
	match event.typ {
		.mouse_move {
			// Highlight on hover only when the zone is clickable.
			if d.click_to_browse {
				inside := d.bounds.contains(event.mouse_x, event.mouse_y)
				d.hovering = inside
				if !inside {
					d.pressed = false
				}
			}
		}
		.mouse_down {
			if d.click_to_browse && event.mouse_btn == .left
				&& d.bounds.contains(event.mouse_x, event.mouse_y) {
				d.pressed = true
				return true
			}
		}
		.mouse_up {
			if d.click_to_browse && event.mouse_btn == .left && d.pressed {
				d.pressed = false
				if d.bounds.contains(event.mouse_x, event.mouse_y) {
					dz_open_browse(mut d, app)
				}
				return true
			}
		}
		.drop_begin {
			// New drag started somewhere on the window; clear stale highlight.
			d.hovering = false
			return false
		}
		.drop_position {
			d.hovering = d.bounds.contains(event.mouse_x, event.mouse_y)
			// don't consume — other zones need to see it too
			return false
		}
		.drop_complete {
			d.hovering = false
			return false
		}
		.drop_file {
			if d.accept_files && d.bounds.contains(event.mouse_x, event.mouse_y) {
				d.hovering = false
				if d.on_drop_file != unsafe { nil } {
					d.on_drop_file(event.text)
				}
				return true
			}
			return false
		}
		.drop_text {
			if d.accept_text && d.bounds.contains(event.mouse_x, event.mouse_y) {
				d.hovering = false
				if d.on_drop_text != unsafe { nil } {
					d.on_drop_text(event.text)
				}
				return true
			}
			return false
		}
		else {
			return false
		}
	}
	return false
}

// dz_open_browse resolves the parent window from the active context (same
// approach as dp_open_dialog), runs a file-open dialog, and feeds each chosen
// path into on_drop_file — the click path reuses the drop callback.
fn dz_open_browse(mut d DropZone, app &App) {
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
		for dlg in app.dialogs {
			if dlg.is_open() && unsafe { &dlg.win.ctx == ctx_ptr } {
				parent = unsafe { &dlg.win }
				break
			}
		}
	}
	if unsafe { parent == nil } {
		return
	}

	mut mapp := unsafe { &App(app) }

	paths := native_open_files_dialog(parent, mut mapp, NativeFileDialogConfig{
		start_dir:       d.browse_start_dir
		allow_many:      d.browse_multi
		filter_names:    d.browse_filter_names
		filter_patterns: d.browse_filter_patterns
	})

	if d.on_drop_file != unsafe { nil } {
		for p in paths {
			d.on_drop_file(p)
		}
	}
}

// mix_with_accent blends base toward accent by t (0..1) — a cheap tint used
// to brighten the zone background on hover.
fn mix_with_accent(base Color, accent Color, t f32) Color {
	inv := 1.0 - t
	return Color{
		r: u8(f32(base.r) * inv + f32(accent.r) * t)
		g: u8(f32(base.g) * inv + f32(accent.g) * t)
		b: u8(f32(base.b) * inv + f32(accent.b) * t)
		a: 255
	}
}
