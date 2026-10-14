module vgui

// Неактивное состояние виджетов (PROJECT.md, «Неактивное состояние (enabled)»).
//
// У каждого виджета есть поле `enabled bool = true` (у HBox/VBox/WindowTitleDrag -
// `box.enabled`). Действует оно двумя путями:
//
// - Свой флаг: виджет не реагирует на ввод, выпадает из Tab-обхода и рисуется
//   приглушённо.
// - Наследование: отключённый контейнер не передаёт события детям, а детей
//   рисует между begin_disabled/end_disabled. Указателя на родителя у виджета
//   нет (намеренно), поэтому «отключён ли предок» виджет узнаёт только из
//   ctx.disabled_depth во время draw() - через ctx.is_enabled(own).
//
// Правило для draw(): один раз взять `en := ctx.is_enabled(w.enabled)` и дальше
// везде использовать `en`, а не поле. Focusable-виджет регистрируется в
// фокус-учёте только при `en`, иначе зовёт ctx.focus_block(&w) - иначе
// виджет в отключённом контейнере оставался бы в Tab-цикле.

// HasEnabled - поле-интерфейс (как HasVisibility): ему удовлетворяет любой тип
// с полем верхнего уровня `enabled bool`.
pub interface HasEnabled {
mut:
	enabled bool
}

// set_widget_enabled включает/отключает любой виджет. false - у типа нет флага
// (таких во встроенных виджетах не осталось; страховка для чужих типов).
pub fn set_widget_enabled(mut w Widget, en bool) bool {
	if mut w is HBox {
		w.box.enabled = en
		return true
	}
	if mut w is VBox {
		w.box.enabled = en
		return true
	}
	if mut w is WindowTitleDrag {
		w.box.enabled = en
		return true
	}
	if mut w is HasEnabled {
		w.enabled = en
		return true
	}
	return false
}

// widget_enabled - собственный флаг виджета (без учёта предков). Тип без флага
// считается включённым.
pub fn widget_enabled(w &Widget) bool {
	if w is HBox {
		return w.box.enabled
	}
	if w is VBox {
		return w.box.enabled
	}
	if w is WindowTitleDrag {
		return w.box.enabled
	}
	if w is HasEnabled {
		return w.enabled
	}
	return true
}

// is_enabled - действующее состояние виджета в draw(): свой флаг и ни одного
// отключённого предка.
pub fn (ctx &RenderContext) is_enabled(own bool) bool {
	return own && ctx.disabled_depth == 0
}

// begin_disabled / end_disabled обрамляют рисование детей контейнера: при
// own == false всё поддерево рисуется неактивным. Зовутся парой с тем же own.
pub fn (mut ctx RenderContext) begin_disabled(own bool) {
	if !own {
		ctx.disabled_depth++
	}
}

pub fn (mut ctx RenderContext) end_disabled(own bool) {
	if !own && ctx.disabled_depth > 0 {
		ctx.disabled_depth--
	}
}

// focus_block - неактивный focusable-виджет: запись (если есть) выпадает из
// Tab-обхода, фокус с неё снимается. Снимает блок следующая регистрация.
pub fn (mut ctx RenderContext) focus_block(ptr voidptr) {
	ctx.focus.set_blocked(ptr, true)
}

// disabled_veil_alpha - плотность вуали поверх неактивного виджета.
const disabled_veil_alpha = u8(140)

// disabled_image_alpha - прозрачность картинок (иконки элементов) неактивного элемента.
const disabled_image_alpha = u8(100)

// draw_disabled_veil приглушает уже нарисованный виджет: полупрозрачная
// заливка цветом фона окна поверх bounds. Для виджетов со сложным содержимым
// (картинка, график, холст, таблица), которым поштучная перекраска не годится.
// Простые контролы перекрашиваются цветами темы (text_disabled,
// button_disabled_*), вуаль им не нужна.
pub fn (mut ctx RenderContext) draw_disabled_veil(r Rect, radius f32) {
	if r.w <= 0 || r.h <= 0 {
		return
	}
	c := ctx.theme.bg.with_alpha(disabled_veil_alpha)
	if radius > 0 {
		ctx.fill_rounded_rect(r, c, radius)
	} else {
		ctx.fill_rect(r, c)
	}
}

// disabled_color - цвет c, приглушённый для неактивного состояния: наполовину
// к фону окна. Для акцентных заливок (прогресс, бейдж), где text_disabled
// потерял бы смысл цвета.
pub fn (ctx &RenderContext) disabled_color(c Color) Color {
	return c.blend(ctx.theme.bg.with_alpha(c.a), 0.55)
}

// is_input_event - ввод пользователя (клавиатура, текст, мышь, drag-and-drop).
// Отключённый контейнер такие события детям не передаёт; служебные события
// окна (resize, фокус окна, сворачивание) идут насквозь - по ним дети следят
// за размером и состоянием окна независимо от enabled.
pub fn is_input_event(e &GuiEvent) bool {
	return match e.typ {
		.key_down, .key_up, .text_input, .mouse_down, .mouse_up, .mouse_move, .mouse_wheel,
		.mouse_dbl_click, .drop_begin, .drop_file, .drop_text, .drop_position, .drop_complete {
			true
		}
		else {
			false
		}
	}
}
