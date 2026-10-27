module vgui

// ═══════════════════════════════════════════════════════
// Notification — toast-style notification widget
//
// Types:
//   .info     — blue, informational message
//   .success  — green, success confirmation
//   .warning  — yellow/orange, warning
//   .error    — red, error message
//
// Features:
//   - Auto-dismiss after duration_ms (0 = manual close only)
//   - Smooth fade-in / fade-out animation
//   - Optional close button (×)
//   - Optional icon (built-in or custom file)
//   - Optional title + message body
//   - Click callback
//   - Slide-in animation from edge
// ═══════════════════════════════════════════════════════

// NotificationKind — тип уведомления: задаёт цвет акцента (полоса, значок, рамка) и вид встроенного значка.
pub enum NotificationKind {
	info
	success
	warning
	error
}

// NotificationAnim — как уведомление «влетает» и «улетает»: сдвиг с края (на 40 px) вместе с прозрачностью либо только fade. NotificationManager выбирает вариант по своей позиции.
pub enum NotificationAnim {
	slide_right
	slide_left
	slide_top
	slide_bottom
	fade
}

// Notification — одно toast-уведомление. Само не решает, где стоять: bounds ему
// выдаёт NotificationManager (layout_notifications) каждый кадр. Жизненный цикл:
// создано (created_at) -> show_anim 0..1 -> (по таймеру duration_ms, кнопке × или
// dismiss()) dismissing -> dismiss_anim 1..0 -> dismissed = true, on_dismiss;
// после этого менеджер убирает его из списка. Пока курсор над уведомлением,
// таймер автозакрытия сбрасывается (см. handle_event). Цвета с a == 0 — «по
// умолчанию для kind / из темы» (eff_*_color).
@[heap]
pub struct Notification {
pub mut:
	type_tag int = kind_notification // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	// Область, перерисованная по анимации в прошлом кадре (anim_area): если менеджер
	// сдвинул уведомление, старое место тоже нужно стереть.
	last_anim_area Rect
	kind           NotificationKind = .info
	title          string
	message        string
	icon_path      string
	visible        bool = true
	enabled        bool = true
	closable       bool = true
	hovered        bool
	close_hover    bool
	close_press    bool
	// Auto-dismiss
	// время жизни в мс до автозакрытия; 0 — только вручную. Ошибки (notification_error) живут дольше — 6000
	duration_ms u32 = 4000
	// отметка now_ms() старта таймера; сбрасывается при наведении и reset_timer
	created_at u64
	// dismissing — идёт анимация закрытия; dismissed — анимация закончена, виджет не рисуется и не принимает события
	dismissing bool
	dismissed  bool
	// Animation
	show_anim Anim = anim_role(.focus)
	// dismiss_anim идёт 1 -> 0 (стартует с 1: полностью видимо); show_anim идёт 0 -> 1. Видимость = произведение обоих
	dismiss_anim Anim = Anim{
		role:    .focus
		epsilon: 0.01
		value:   1
		goal:    1
	}
	anim_kind    NotificationAnim = .slide_right
	// Sizing
	pad        f32 = 12
	icon_size  f32 = 20
	icon_gap   f32 = 10
	close_size f32 = 16
	radius     f32 = -1
	// Custom colors (a=0 means use kind defaults)
	bg_color      Color = Color{0, 0, 0, 0}
	border_color  Color = Color{0, 0, 0, 0}
	accent_color  Color = Color{0, 0, 0, 0}
	title_color   Color = Color{0, 0, 0, 0}
	message_color Color = Color{0, 0, 0, 0}
	icon_color    Color = Color{0, 0, 0, 0}
	// Layout
	show_accent_stripe bool = true
	stripe_width       f32  = 4
	// Callbacks
	on_click   fn () = unsafe { nil }
	on_close   fn () = unsafe { nil }
	on_dismiss fn () = unsafe { nil }
}

// ─── Constructors ──────────────────────────────────────

// notification создаёт обычное (info) уведомление с текстом message. Таймер стартует в момент создания (при show() менеджер перезапускает его).
pub fn notification(message string) &Notification {
	return &Notification{
		message:    message
		created_at: now_ms()
	}
}

// notification_info — то же, но kind задан явно (.info).
pub fn notification_info(message string) &Notification {
	return &Notification{
		kind:       .info
		message:    message
		created_at: now_ms()
	}
}

// notification_success — уведомление об успехе (зелёное).
pub fn notification_success(message string) &Notification {
	return &Notification{
		kind:       .success
		message:    message
		created_at: now_ms()
	}
}

// notification_warning — предупреждение.
pub fn notification_warning(message string) &Notification {
	return &Notification{
		kind:       .warning
		message:    message
		created_at: now_ms()
	}
}

// notification_error — ошибка; живёт 6 с вместо 4 с.
pub fn notification_error(message string) &Notification {
	return &Notification{
		kind:        .error
		message:     message
		duration_ms: 6000
		created_at:  now_ms()
	}
}

// notification_with_title — уведомление заданного kind с жирным заголовком над текстом.
pub fn notification_with_title(kind NotificationKind, title string, message string) &Notification {
	return &Notification{
		kind:       kind
		title:      title
		message:    message
		created_at: now_ms()
	}
}

// ─── Public API ────────────────────────────────────────

// dismiss запускает анимацию закрытия (идемпотентно; для уже закрытого ничего не делает). on_dismiss вызовется по её окончании в draw().
pub fn (mut n Notification) dismiss() {
	if n.dismissed {
		return
	}
	n.dismissing = true
}

// is_dismissed: анимация закрытия завершена.
pub fn (n &Notification) is_dismissed() bool {
	return n.dismissed
}

// reset_timer перезапускает таймер автозакрытия и «оживляет» уже закрывающееся/закрытое уведомление (dismiss_anim мгновенно возвращается в 1).
pub fn (mut n Notification) reset_timer() {
	n.created_at = now_ms()
	n.dismissing = false
	n.dismissed = false
	n.dismiss_anim.snap(1)
}

// Цвета: собственный цвет, если задан (a > 0), иначе умолчание по kind (акцент: info/success/warning/error из темы) или цвет темы; рамка — акцент с alpha 120, значок — акцент.
// ─── Default colors per kind ───────────────────────────

fn (n &Notification) eff_accent_color(ctx &RenderContext) Color {
	if n.accent_color.a > 0 {
		return n.accent_color
	}
	return match n.kind {
		.info { ctx.theme.info }
		.success { ctx.theme.success }
		.warning { ctx.theme.warning }
		.error { ctx.theme.error_color }
	}
}

fn (n &Notification) eff_bg_color(ctx &RenderContext) Color {
	if n.bg_color.a > 0 {
		return n.bg_color
	}
	return ctx.theme.eff_notif_bg()
}

fn (n &Notification) eff_border_color(ctx &RenderContext) Color {
	if n.border_color.a > 0 {
		return n.border_color
	}
	return n.eff_accent_color(ctx).with_alpha(120)
}

fn (n &Notification) eff_title_color(ctx &RenderContext) Color {
	if n.title_color.a > 0 {
		return n.title_color
	}
	return ctx.theme.eff_notif_title()
}

fn (n &Notification) eff_message_color(ctx &RenderContext) Color {
	if n.message_color.a > 0 {
		return n.message_color
	}
	return ctx.theme.eff_notif_message()
}

fn (n &Notification) eff_icon_color(ctx &RenderContext) Color {
	if n.icon_color.a > 0 {
		return n.icon_color
	}
	return n.eff_accent_color(ctx)
}

fn (n &Notification) eff_radius(ctx &RenderContext) f32 {
	if n.radius >= 0 {
		return n.radius
	}
	return ctx.theme.border_radius
}

// ─── Geometry ──────────────────────────────────────────

// close_btn_rect — область кнопки × в правом верхнем углу (пустой Rect, если closable = false).
fn (n &Notification) close_btn_rect() Rect {
	if !n.closable {
		return Rect{}
	}
	cs := n.close_size
	return Rect{
		x: n.bounds.x + n.bounds.w - n.pad - cs
		y: n.bounds.y + n.pad
		w: cs
		h: cs
	}
}

// icon_rect — место значка: правее акцентной полосы и отступа, чуть ниже верхнего отступа (+2 px под выравнивание с первой строкой).
fn (n &Notification) icon_rect() Rect {
	stripe := if n.show_accent_stripe { n.stripe_width } else { f32(0) }
	return Rect{
		x: n.bounds.x + stripe + n.pad
		y: n.bounds.y + n.pad + 2
		w: n.icon_size
		h: n.icon_size
	}
}

// text_rect — область текста: между значком и кнопкой × (если есть), с отступами pad.
fn (n &Notification) text_rect() Rect {
	stripe := if n.show_accent_stripe { n.stripe_width } else { f32(0) }
	// Значок есть всегда: icon_path или встроенный по kind.
	icon_w := n.icon_size + n.icon_gap
	close_w := if n.closable { n.close_size + n.icon_gap } else { f32(0) }
	return Rect{
		x: n.bounds.x + stripe + n.pad + icon_w
		y: n.bounds.y + n.pad
		w: n.bounds.w - stripe - n.pad * 2 - icon_w - close_w
		h: n.bounds.h - n.pad * 2
	}
}

// ─── Animation offsets ─────────────────────────────────

// anim_offset — смещение (dx, dy) для анимации появления/исчезновения: t = show * dismiss;
// при t >= 0.999 смещения нет, иначе до 40 px от стороны, указанной anim_kind (для .fade — 0).
// anim_area - всё, что уведомление может закрасить за кадр анимации: bounds плюс
// наибольший сдвиг anim_offset (40) и тень темы.
fn (n &Notification) anim_area(ctx &RenderContext) Rect {
	return n.bounds.expanded(f32(40) + max_f32(ctx.theme.shadow_offset, 0) + 2)
}

fn (n &Notification) anim_offset() (f32, f32) {
	t := n.show_anim.value * n.dismiss_anim.value
	if t >= 0.999 {
		return f32(0), f32(0)
	}
	progress := 1.0 - t
	dist := f32(40) * progress
	return match n.anim_kind {
		.slide_right { dist, f32(0) }
		.slide_left { -dist, f32(0) }
		.slide_top { f32(0), -dist }
		.slide_bottom { f32(0), dist }
		.fade { f32(0), f32(0) }
	}
}

// anim_alpha — общая прозрачность 0..255 = show_anim * dismiss_anim; на неё домножаются все цвета в draw().
fn (n &Notification) anim_alpha() u8 {
	t := clamp_f32(n.show_anim.value * n.dismiss_anim.value, 0, 1)
	return u8(255.0 * t)
}

// ─── Built-in icon drawing ─────────────────────────────

// draw_builtin_icon рисует значок по kind примитивами: info — кружок с «i», success — кружок с галочкой, warning — треугольник с «!», error — кружок с крестом. Знак рисуется цветом поверхности темы (ctx.theme.surface), а не вырезается прозрачностью.
fn (n &Notification) draw_builtin_icon(r Rect, c Color, mut ctx RenderContext) {
	cx := r.x + r.w * 0.5
	cy := r.y + r.h * 0.5
	radius := r.w * 0.5

	match n.kind {
		.info {
			ctx.fill_circle(cx, cy, radius, c)
			ctx.fill_circle(cx, cy - radius * 0.45, radius * 0.13, ctx.theme.surface)
			bar_w := radius * 0.22
			bar_h := radius * 0.55
			ctx.fill_rect(Rect{cx - bar_w * 0.5, cy - radius * 0.1, bar_w, bar_h},
				ctx.theme.surface)
		}
		.success {
			ctx.fill_circle(cx, cy, radius, c)
			s := radius * 0.45
			cc := ctx.theme.surface
			ctx.draw_line_thick(cx - s, cy + s * 0.1, cx - s * 0.25, cy + s * 0.6, 2, cc)
			ctx.draw_line_thick(cx - s * 0.25, cy + s * 0.6, cx + s * 0.85, cy - s * 0.5, 2, cc)
		}
		.warning {
			tip_y := cy - radius * 0.85
			base_l_x := cx - radius * 0.95
			base_r_x := cx + radius * 0.95
			base_y := cy + radius * 0.7
			ctx.fill_triangle(cx, tip_y, base_l_x, base_y, base_r_x, base_y, c)
			bar_w := radius * 0.22
			bar_h := radius * 0.55
			ctx.fill_rect(Rect{cx - bar_w * 0.5, cy - radius * 0.25, bar_w, bar_h},
				ctx.theme.surface)
			ctx.fill_circle(cx, cy + radius * 0.4, radius * 0.13, ctx.theme.surface)
		}
		.error {
			ctx.fill_circle(cx, cy, radius, c)
			s := radius * 0.45
			cc := ctx.theme.surface
			ctx.draw_line_thick(cx - s, cy - s, cx + s, cy + s, 2, cc)
			ctx.draw_line_thick(cx + s, cy - s, cx - s, cy + s, 2, cc)
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw: (1) проверяет таймер автозакрытия, (2) шагает show_anim/dismiss_anim и по
// окончании закрытия ставит dismissed + on_dismiss, (3) пока идёт анимация или
// тикает таймер — заказывает следующий кадр только для своей области (anim_area:
// bounds с запасом на сдвиг анимации и тень) и прошлой области, а не всего окна
// (правило инвалидации из CLAUDE.md), (4) рисует тень, фон, рамку, акцентную полосу, значок,
// текст и ×. На время рисования n.bounds подменяется сдвинутым прямоугольником
// (anim_bounds), чтобы геометрические помощники (icon_rect и др.) учитывали
// смещение; в конце bounds возвращается.
pub fn (mut n Notification) draw(mut ctx RenderContext) {
	if !n.visible || n.dismissed {
		return
	}

	now := now_ms()

	// Auto-dismiss check
	if !n.dismissing && n.duration_ms > 0 {
		elapsed := now - n.created_at
		if elapsed >= n.duration_ms {
			n.dismissing = true
		}
	}

	// Show animation (ease-out)
	n.show_anim.update(1, ctx)

	// Dismiss animation
	if n.dismissing {
		if !n.dismiss_anim.update(0, ctx) {
			n.dismissed = true
			if n.on_dismiss != unsafe { nil } {
				n.on_dismiss()
			}
			return
		}
	}

	// Keep redrawing while: show anim running, dismiss anim running, or auto-dismiss timer active
	timer_active := !n.dismissing && n.duration_ms > 0
	if n.show_anim.animating() || n.dismissing || timer_active {
		area := n.anim_area(ctx)
		if n.last_anim_area.w > 0 && n.last_anim_area != area {
			ctx.mark_anim_rect('notification', n.last_anim_area)
		}
		ctx.mark_anim_rect('notification', area)
		n.last_anim_area = area
	}

	off_x, off_y := n.anim_offset()
	alpha := n.anim_alpha()
	if alpha == 0 {
		return
	}

	anim_bounds := Rect{
		x: n.bounds.x + off_x
		y: n.bounds.y + off_y
		w: n.bounds.w
		h: n.bounds.h
	}

	rad := n.eff_radius(ctx)
	// Неактивное уведомление (свой enabled или неактивный менеджер) - под вуалью
	defer {
		if !ctx.is_enabled(n.enabled) {
			ctx.draw_disabled_veil(anim_bounds, rad)
		}
	}
	bg := n.eff_bg_color(ctx).with_alpha(u8(int(n.eff_bg_color(ctx).a) * int(alpha) / 255))
	bc := n.eff_border_color(ctx).with_alpha(u8(int(n.eff_border_color(ctx).a) * int(alpha) / 255))
	accent := n.eff_accent_color(ctx).with_alpha(alpha)

	// Shadow
	if ctx.theme.shadow_offset > 0 && alpha > 100 {
		shadow_a := u8(int(ctx.theme.shadow_color.a) * int(alpha) / 255)
		shadow_c := ctx.theme.shadow_color.with_alpha(shadow_a)
		off := ctx.theme.shadow_offset + 1
		shadow_r := Rect{anim_bounds.x + off, anim_bounds.y + off, anim_bounds.w, anim_bounds.h}
		ctx.fill_rounded_rect(shadow_r, shadow_c, rad)
	}

	// Background
	ctx.fill_rounded_rect(anim_bounds, bg, rad)

	// Border
	ctx.draw_rounded_rect(anim_bounds, bc, rad)

	// Adjust internal bounds for drawing children with animation offset
	saved_bounds := n.bounds
	n.bounds = anim_bounds

	// Accent stripe (left side)
	if n.show_accent_stripe {
		// Outer clip: limit to notification bounds
		ctx.push_clip(anim_bounds)

		// Inner clip: limit strictly to stripe area
		stripe_clip := Rect{anim_bounds.x, anim_bounds.y, n.stripe_width, anim_bounds.h}
		ctx.push_clip(stripe_clip)

		// Draw rounded rect MUCH wider than needed.
		// Left corners use the same radius as the notification background,
		// so they align perfectly. Right corners are cut off by stripe_clip.
		safe_overflow := rad * 2 + 8
		ctx.fill_rounded_rect(Rect{anim_bounds.x, anim_bounds.y, n.stripe_width + safe_overflow, anim_bounds.h},
			accent, rad)

		ctx.pop_clip() // stripe_clip
		ctx.pop_clip() // anim_bounds
	}

	// Icon: файл icon_path или встроенный значок по kind.
	ir := n.icon_rect()
	if n.icon_path.len > 0 {
		tex := ctx.load_icon_texture(n.icon_path)
		ctx.draw_icon(tex, ir.x, ir.y, ir.w, ir.h)
	} else {
		n.draw_builtin_icon(ir, accent, mut ctx)
	}

	// Text (title + message)
	trk := n.text_rect()
	ctx.push_clip(trk)

	font_b := ctx.get_font(.bold, 0)
	font_r := ctx.get_font(.regular, 0)
	fh_b := ctx.font_height_of(font_b)
	fh_r := ctx.font_height_of(font_r)

	tc_title := n.eff_title_color(ctx).with_alpha(alpha)
	tc_msg := n.eff_message_color(ctx).with_alpha(alpha)

	mut y := trk.y
	if n.title.len > 0 {
		ctx.draw_text_with_font(n.title, trk.x, y, tc_title, font_b)
		y += fh_b + 2
	}
	if n.message.len > 0 {
		lines := wrap_text_notif(n.message, mut ctx, font_r, trk.w)
		for line in lines {
			if y + fh_r > trk.y + trk.h {
				break
			}
			ctx.draw_text_with_font(line, trk.x, y, tc_msg, font_r)
			y += fh_r + 2
		}
	}
	ctx.pop_clip()

	// Close button
	if n.closable {
		cr := n.close_btn_rect()
		if n.close_hover {
			hover_bg :=
				ctx.theme.button_hover.with_alpha(u8(int(ctx.theme.button_hover.a) * int(alpha) / 255))
			ctx.fill_rounded_rect(cr.expanded(2), hover_bg, 3)
		}
		cc := n.eff_message_color(ctx).with_alpha(alpha)
		s := cr.w * 0.35
		cx := cr.x + cr.w * 0.5
		cy := cr.y + cr.h * 0.5
		ctx.draw_line_thick(cx - s, cy - s, cx + s, cy + s, 2, cc)
		ctx.draw_line_thick(cx + s, cy - s, cx - s, cy + s, 2, cc)
	}

	n.bounds = saved_bounds
}

// ─── Word wrap helper ──────────────────────────────────

// wrap_text_notif переносит текст по словам под ширину max_w (измерение — реальным шрифтом).
// Абзацы разделяются '\n', пустой абзац даёт пустую строку. Слово шире строки не
// разрывается и вылезет за ширину (клип по text_rect его обрежет).
fn wrap_text_notif(text string, mut ctx RenderContext, font voidptr, max_w f32) []string {
	if text.len == 0 {
		return []
	}
	paragraphs := text.split('\n')
	mut result := []string{cap: paragraphs.len * 2}
	for p in paragraphs {
		if p.len == 0 {
			result << ''
			continue
		}
		words := p.split(' ')
		mut line := ''
		for word in words {
			test := if line.len == 0 { word } else { '${line} ${word}' }
			tw := ctx.measure_text_with_font(test, font).x
			if tw > max_w && line.len > 0 {
				result << line
				line = word
			} else {
				line = test
			}
		}
		if line.len > 0 {
			result << line
		}
	}
	return result
}

// ─── Events ────────────────────────────────────────────

// handle_event: наведение подсвечивает ×; нажатие на × запоминается (close_press),
// закрытие — по отпусканию на ×: on_close, затем dismiss(). Клик по телу вызывает
// on_click, только если он задан (иначе событие не поглощается). Пока курсор над
// уведомлением, created_at сбрасывается на каждое событие — таймер автозакрытия
// фактически приостановлен.
pub fn (mut n Notification) handle_event(event &GuiEvent, app &App) bool {
	if !n.visible || !n.enabled || n.dismissed {
		return false
	}

	match event.typ {
		.mouse_move {
			n.hovered = n.bounds.contains(event.mouse_x, event.mouse_y)
			if n.closable {
				cr := n.close_btn_rect()
				n.close_hover = cr.expanded(4).contains(event.mouse_x, event.mouse_y)
			}
		}
		.mouse_down {
			if event.mouse_btn == .left {
				if n.closable {
					cr := n.close_btn_rect()
					if cr.expanded(4).contains(event.mouse_x, event.mouse_y) {
						n.close_press = true
						return true
					}
				}
				if n.hovered && n.on_click != unsafe { nil } {
					n.on_click()
					return true
				}
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && n.close_press {
				n.close_press = false
				if n.closable {
					cr := n.close_btn_rect()
					if cr.expanded(4).contains(event.mouse_x, event.mouse_y) {
						if n.on_close != unsafe { nil } {
							n.on_close()
						}
						n.dismiss()
						return true
					}
				}
			}
		}
		else {}
	}

	if n.hovered && !n.dismissing && n.duration_ms > 0 {
		n.created_at = now_ms()
	}

	return false
}

// ═══════════════════════════════════════════════════════
// NotificationManager — stack of notifications with
// automatic positioning and removal
// ═══════════════════════════════════════════════════════

// NotificationPosition — угол/край окна, у которого менеджер выстраивает стопку уведомлений.
pub enum NotificationPosition {
	top_right
	top_left
	top_center
	bottom_right
	bottom_left
	bottom_center
}

// NotificationManager — стопка уведомлений в углу/у края окна. Добавляется в окно
// как виджет через win.add_widget(nm) (в контейнеры не кладётся). Каждый кадр
// убирает закрытые, раскладывает остальные столбиком (layout_notifications) и
// рисует; показывает не больше max_visible, остальные скрыты (visible = false)
// до освобождения места. Область — bounds, а если они пусты — screen_w/screen_h.
@[heap]
pub struct NotificationManager {
pub mut:
	type_tag      int = kind_notification_manager // тег типа, см. widget_tag.v
	css           CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds        Rect
	notifications []&Notification
	visible       bool                 = true
	enabled       bool                 = true // false - все уведомления неактивны (enabled.v)
	position      NotificationPosition = .top_right
	margin        f32                  = 12
	spacing       f32                  = 8
	notif_width   f32                  = 320
	notif_height  f32                  = 70
	max_visible   int                  = 5
	// Fallback screen size if bounds not provided.
	// Set these from your app on init/resize.
	// запасной размер области (меняется set_screen_size), когда bounds менеджера не заданы
	screen_w f32 = 1920
	screen_h f32 = 1080
}

// notification_manager создаёт менеджер с позицией top_right.
pub fn notification_manager() &NotificationManager {
	return &NotificationManager{}
}

// notification_manager_at — менеджер с заданной позицией.
pub fn notification_manager_at(pos NotificationPosition) &NotificationManager {
	return &NotificationManager{
		position: pos
	}
}

// Update fallback screen size (call on window resize)
// set_screen_size обновляет запасной размер области (звать при ресайзе окна, если bounds менеджера не выставляются).
pub fn (mut nm NotificationManager) set_screen_size(w f32, h f32) {
	nm.screen_w = w
	nm.screen_h = h
}

// ─── Public API ────────────────────────────────────────

// show добавляет уведомление в стопку: подбирает направление анимации под position менеджера и перезапускает таймер. Менеджер хранит ссылку на n (держит живым для GC).
pub fn (mut nm NotificationManager) show(n &Notification) {
	mut mn := unsafe { n }
	mn.anim_kind = match nm.position {
		.top_right, .bottom_right { NotificationAnim.slide_right }
		.top_left, .bottom_left { NotificationAnim.slide_left }
		.top_center { NotificationAnim.slide_top }
		.bottom_center { NotificationAnim.slide_bottom }
	}

	mn.created_at = now_ms()
	nm.notifications << unsafe { n }
}

// show_info / show_success / show_warning / show_error / show_with_title создают уведомление соответствующего вида, показывают его и возвращают (чтобы можно было назначить колбэки или закрыть вручную).
pub fn (mut nm NotificationManager) show_info(message string) &Notification {
	mut n := notification_info(message)
	nm.show(n)
	return n
}

pub fn (mut nm NotificationManager) show_success(message string) &Notification {
	mut n := notification_success(message)
	nm.show(n)
	return n
}

pub fn (mut nm NotificationManager) show_warning(message string) &Notification {
	mut n := notification_warning(message)
	nm.show(n)
	return n
}

pub fn (mut nm NotificationManager) show_error(message string) &Notification {
	mut n := notification_error(message)
	nm.show(n)
	return n
}

pub fn (mut nm NotificationManager) show_with_title(kind NotificationKind, title string, message string) &Notification {
	mut n := notification_with_title(kind, title, message)
	nm.show(n)
	return n
}

// clear плавно закрывает все уведомления (анимацией).
pub fn (mut nm NotificationManager) clear() {
	for mut n in nm.notifications {
		n.dismiss()
	}
}

// clear_immediate мгновенно убирает все уведомления из списка, без анимации и без on_dismiss.
pub fn (mut nm NotificationManager) clear_immediate() {
	nm.notifications.clear()
}

// count — сколько уведомлений в списке (включая закрывающиеся и скрытые сверх max_visible).
pub fn (nm &NotificationManager) count() int {
	return nm.notifications.len
}

// ─── Layout ────────────────────────────────────────────

// calc_height считает высоту уведомления при ширине notif_width: отступы + заголовок + перенесённые строки сообщения, но не меньше notif_height.
fn (nm &NotificationManager) calc_height(n &Notification, mut ctx RenderContext) f32 {
	font_b := ctx.get_font(.bold, 0)
	font_r := ctx.get_font(.regular, 0)
	fh_b := ctx.font_height_of(font_b)
	fh_r := ctx.font_height_of(font_r)

	stripe := if n.show_accent_stripe { n.stripe_width } else { f32(0) }
	// Значок есть всегда: icon_path или встроенный по kind.
	icon_w := n.icon_size + n.icon_gap
	close_w := if n.closable { n.close_size + n.icon_gap } else { f32(0) }
	text_w := nm.notif_width - stripe - n.pad * 2 - icon_w - close_w

	mut h := f32(n.pad * 2)
	if n.title.len > 0 {
		h += fh_b + 2
	}
	if n.message.len > 0 {
		lines := wrap_text_notif(n.message, mut ctx, font_r, text_w)
		ln := if lines.len > 0 { lines.len } else { 1 }
		h += f32(ln) * (fh_r + 2)
	}
	if h < nm.notif_height {
		h = nm.notif_height
	}
	return h
}

// layout_notifications выставляет bounds уведомлениям. Колонка: по краю (с margin)
// или по центру. Для верхних позиций стопка растёт вниз от верхнего края, для
// нижних — вверх от нижнего (самое старое уведомление у края). Сверх
// max_visible уведомления скрываются, закрытые пропускаются.
fn (mut nm NotificationManager) layout_notifications(mut ctx RenderContext) {
	// Determine anchor (use bounds, or fallback to screen size)
	mut area := nm.bounds
	if area.w <= 0 || area.h <= 0 {
		area = Rect{0, 0, nm.screen_w, nm.screen_h}
	}

	is_top := nm.position in [.top_right, .top_left, .top_center]
	is_left := nm.position in [.top_left, .bottom_left]
	is_center := nm.position in [.top_center, .bottom_center]

	col_x := if is_center {
		area.x + (area.w - nm.notif_width) * 0.5
	} else if is_left {
		area.x + nm.margin
	} else {
		area.x + area.w - nm.margin - nm.notif_width
	}

	mut cursor := if is_top { area.y + nm.margin } else { area.y + area.h - nm.margin }

	mut shown := 0
	if is_top {
		for mut n in nm.notifications {
			if n.dismissed {
				continue
			}
			if shown >= nm.max_visible {
				n.visible = false
				continue
			}
			n.visible = true
			h := nm.calc_height(n, mut ctx)
			n.bounds = Rect{col_x, cursor, nm.notif_width, h}
			cursor += h + nm.spacing
			shown++
		}
	} else {
		for mut n in nm.notifications {
			if n.dismissed {
				continue
			}
			if shown >= nm.max_visible {
				n.visible = false
				continue
			}
			n.visible = true
			h := nm.calc_height(n, mut ctx)
			cursor -= h
			n.bounds = Rect{col_x, cursor, nm.notif_width, h}
			cursor -= nm.spacing
			shown++
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw: удаляет закрытые уведомления, пересчитывает раскладку (каждый кадр, т.к. анимации и закрытия сдвигают соседей) и рисует видимые.
pub fn (mut nm NotificationManager) draw(mut ctx RenderContext) {
	if !nm.visible {
		return
	}

	// Remove fully dismissed notifications
	if nm.notifications.len > 0 {
		mut alive := []&Notification{cap: nm.notifications.len}
		for n in nm.notifications {
			if !n.dismissed {
				alive << n
			}
		}
		nm.notifications = alive
	}

	if nm.notifications.len == 0 {
		return
	}

	// Re-layout every frame (animations / dismissals shift positions)
	nm.layout_notifications(mut ctx)

	ctx.begin_disabled(nm.enabled)
	for mut n in nm.notifications {
		if n.visible {
			n.draw(mut ctx)
		}
	}
	ctx.end_disabled(nm.enabled)
}

// ─── Events ────────────────────────────────────────────

// handle_event пересылает событие уведомлениям с верхнего (последнего добавленного) к нижнему; останавливается на первом поглотившем.
pub fn (mut nm NotificationManager) handle_event(event &GuiEvent, app &App) bool {
	if !nm.visible || (!nm.enabled && is_input_event(event)) {
		return false
	}
	// Forward events to notifications, top of stack first
	for i := nm.notifications.len - 1; i >= 0; i-- {
		mut n := nm.notifications[i]
		if !n.visible || n.dismissed {
			continue
		}
		if n.handle_event(event, app) {
			return true
		}
	}
	return false
}
