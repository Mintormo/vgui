module vgui

// ═══════════════════════════════════════════════════════
// ImageBackground — lightweight image widget for backgrounds / logos.
//
// Unlike ImageView it has no zoom, pan, scrollbars or event handling: it just
// paints an image inside its bounds according to a display mode. It is meant
// for window backgrounds (Window.set_background_image), decorative banners and
// logos placed in a layout (or as the bottom layer of a Stack).
//
// Display modes:
//   .fit     — scale to fit bounds, preserve aspect, centered (whole image visible)
//   .fill    — scale to fill bounds, preserve aspect, centered (may crop) — "cover"
//   .stretch — fill bounds exactly, ignoring aspect
//   .tile    — repeat the image at native size to cover bounds
//   .center  — native size, centered (may crop)
//
// Texture lifetime mirrors ImageView: the texture is tied to its creating
// renderer and may only be SDL_DestroyTexture'd while that renderer is alive
// (generation-guarded — see the live-renderer registry in sdl3_window.v).
// ═══════════════════════════════════════════════════════

// BgMode - режим вписывания картинки в bounds (подробно в шапке файла): fit / fill ("cover") / stretch / tile / center.
pub enum BgMode {
	fit
	fill
	stretch
	tile
	center
}

// ImageBackground - пассивный виджет-картинка (kind_image_background). Источник - файл (path) ИЛИ байты (data);
// data приоритетнее. Текстура создаётся лениво в draw() (ensure_texture_loaded) и привязана к рендереру,
// на котором создана (Texture помнит рендерер и его поколение - защита от ABA, sdl3_texture.v).
// tex_path - для какого path загружена текстура; служебное значение '\x00reload' требует перезагрузки.
// bg_color (alpha > 0) - сплошная подложка под картинкой со скруглением corner_radius.
@[heap]
pub struct ImageBackground {
pub mut:
	type_tag      int = kind_image_background // тег типа, см. widget_tag.v
	css           CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds        Rect
	path          string
	mode          BgMode = .fill
	visible       bool   = true
	enabled       bool   = true // false - картинка приглушена вуалью (enabled.v)
	tooltip       string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd           &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	bg_color      Color     = Color{0, 0, 0, 0}
	corner_radius f32
	// Кэш текстуры (sdl3_texture.v; освобождается только при живом рендерере,
	// как у ImageView). Размер картинки - texture.w/texture.h.
	texture  Texture
	tex_path string
	// Raw image bytes (for data-backed backgrounds with no file on disk)
	data []u8
}

// ─── Constructors ──────────────────────────────────────

pub fn image_background() &ImageBackground {
	return &ImageBackground{}
}

pub fn image_background_file(path string) &ImageBackground {
	return &ImageBackground{
		path: path
	}
}

// image_background_data - картинка из байт в памяти (PNG/JPG и т.п.); байты копируются (.clone()), так как приходят из чужого кода (Python/ctypes) и хранятся дольше вызова.
pub fn image_background_data(data []u8) &ImageBackground {
	return &ImageBackground{
		data: data.clone()
	}
}

// ─── Public API ────────────────────────────────────────

// set_path меняет источник на файл: сбрасывает data и помечает текстуру устаревшей - перезагрузка будет при следующем draw(). Тот же путь игнорируется. Кадр не инвалидирует.
pub fn (mut ib ImageBackground) set_path(path string) {
	if ib.path != path {
		ib.path = path
		ib.data = []u8{}
		// Force a reload on the next draw.
		ib.tex_path = '\x00reload'
	}
}

// set_data меняет источник на байты (копия) и принудительно перезагружает текстуру при следующем draw().
pub fn (mut ib ImageBackground) set_data(data []u8) {
	ib.data = data.clone()
	ib.path = ''
	ib.tex_path = '\x00reload'
}

pub fn (mut ib ImageBackground) set_mode(mode BgMode) {
	ib.mode = mode
}

pub fn (mut ib ImageBackground) set_bg_color(c Color) {
	ib.bg_color = c
}

// ─── Texture management ────────────────────────────────

// ensure_texture_loaded лениво (пере)создаёт текстуру: нет источника или актуальная текстура уже есть - выход;
// иначе уничтожает старую (Texture.destroy сам проверяет, жив ли её рендерер) и грузит новую - из байт
// data, если они есть, иначе из файла path. При ошибке загрузки tex_path всё равно ставится, чтобы не
// повторять загрузку каждый кадр (картинка просто не рисуется).
fn (mut ib ImageBackground) ensure_texture_loaded(ctx &RenderContext) {
	has_source := ib.path.len > 0 || ib.data.len > 0
	if !has_source {
		return
	}
	// A loaded texture for the current source — nothing to do.
	if ib.texture.is_valid() && ib.tex_path == ib.path && ib.tex_path != '\x00reload' {
		return
	}
	ib.texture.destroy()
	ib.texture = if ib.data.len > 0 {
		ctx.texture_from_bytes(ib.data)
	} else {
		ctx.texture_from_file(ib.path)
	}
	ib.tex_path = ib.path
}

// destroy_texture освобождает текстуру (только если рендерер ещё жив) и сбрасывает tex_path, чтобы следующий draw() загрузил её заново. Вызывается при очистке окна.
pub fn (mut ib ImageBackground) destroy_texture() {
	ib.texture.destroy()
	ib.tex_path = ''
}

fn (ib &ImageBackground) has_texture() bool {
	return ib.texture.is_valid() && ib.texture.w > 0 && ib.texture.h > 0
}

// ─── Drawing ───────────────────────────────────────────

// draw: ленивая загрузка текстуры, подложка bg_color, затем картинка по режиму внутри клипа bounds.
// fit - масштаб min(bw/tw, bh/th); fill - max(...) (картинка перекрывает область и обрезается клипом);
// center - исходный размер; tile - сетка копий исходного размера от левого верхнего угла.
pub fn (mut ib ImageBackground) draw(mut ctx RenderContext) {
	if !ib.visible {
		return
	}
	if !ctx.is_in_clip(ib.bounds) {
		return
	}

	ib.ensure_texture_loaded(ctx)
	defer {
		if !ctx.is_enabled(ib.enabled) {
			ctx.draw_disabled_veil(ib.bounds, ib.corner_radius)
		}
	}

	// Optional solid background / fallback color.
	if ib.bg_color.a > 0 {
		ctx.fill_rounded_rect(ib.bounds, ib.bg_color, ib.corner_radius)
	}

	if !ib.has_texture() {
		return
	}

	b := ib.bounds
	tw := f32(ib.texture.w)
	th := f32(ib.texture.h)

	ctx.push_clip(b)
	match ib.mode {
		.stretch {
			ib.blit(mut ctx, b)
		}
		.fit {
			s := min_f32(b.w / tw, b.h / th)
			dw := tw * s
			dh := th * s
			ib.blit(mut ctx, Rect{b.x + (b.w - dw) * 0.5, b.y + (b.h - dh) * 0.5, dw, dh})
		}
		.fill {
			s := max_f32(b.w / tw, b.h / th)
			dw := tw * s
			dh := th * s
			ib.blit(mut ctx, Rect{b.x + (b.w - dw) * 0.5, b.y + (b.h - dh) * 0.5, dw, dh})
		}
		.center {
			ib.blit(mut ctx, Rect{b.x + (b.w - tw) * 0.5, b.y + (b.h - th) * 0.5, tw, th})
		}
		.tile {
			if tw > 0 && th > 0 {
				mut y := b.y
				for y < b.y + b.h {
					mut x := b.x
					for x < b.x + b.w {
						ib.blit(mut ctx, Rect{x, y, tw, th})
						x += tw
					}
					y += th
				}
			}
		}
	}
	ctx.pop_clip()
}

// blit - одна отрисовка всей текстуры в прямоугольник dst (координаты логические, масштаб рендера выставлен окном).
fn (ib &ImageBackground) blit(mut ctx RenderContext, dst Rect) {
	ctx.draw_texture(ib.texture, dst)
}

// ─── Events ────────────────────────────────────────────

// ImageBackground is passive: it never consumes events.
pub fn (mut ib ImageBackground) handle_event(event &GuiEvent, app &App) bool {
	return false
}
