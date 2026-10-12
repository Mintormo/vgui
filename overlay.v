module vgui

// Оверлей попапа окна (выпадающий список ComboBox, ContextMenu, MenuBar,
// MenuButton): ОДИН слот на RenderContext, и у слота есть владелец — адрес
// виджета, открывшего попап. Почему не стек и что легко сломать — PROJECT.md,
// «Оверлеи попапов».
//
// Писать в overlay_cb/overlay_ev напрямую нельзя: у такой записи нет
// владельца, поэтому её не закроет ни чужой попап, ни vgui_destroy.

// set_overlay ставит попап owner в слот окна.
//
// Если слот занят ДРУГИМ владельцем, его попап сначала закрывается его же
// close-хуком: иначе он остался бы в состоянии open = true, но без отрисовки
// и без событий. Слот освобождается ДО вызова хука, поэтому clear_overlay
// внутри хука видит пустой слот и ничего не трогает. Повторная установка тем
// же владельцем (MenuBar переключает пункт, подменю) хук не зовёт.
pub fn (mut ctx RenderContext) set_overlay(owner voidptr, draw fn (mut RenderContext), ev fn (&GuiEvent, &App) bool, close fn (mut RenderContext)) {
	if ctx.overlay_owner != unsafe { nil } && ctx.overlay_owner != owner {
		prev_close := ctx.overlay_close
		ctx.reset_overlay_slot()
		if prev_close != unsafe { nil } {
			prev_close(mut ctx)
		}
	}
	ctx.overlay_owner = owner
	ctx.overlay_cb = draw
	ctx.overlay_ev = ev
	ctx.overlay_close = close
}

// clear_overlay освобождает слот, только если он принадлежит owner.
// Закрытие попапа, который уже вытеснен другим (или ни разу не открывался —
// owner nil), не должно стирать чужой оверлей.
pub fn (mut ctx RenderContext) clear_overlay(owner voidptr) {
	if owner == unsafe { nil } || ctx.overlay_owner != owner {
		return
	}
	ctx.reset_overlay_slot()
}

// reset_overlay_slot обнуляет все четыре поля слота разом, без вызова
// close-хука и без проверки владельца. Внутренний помощник: снаружи слот
// освобождают только через clear_overlay (с проверкой владельца) или
// release_overlay (при уничтожении виджета). Кадр не инвалидирует —
// это забота вызывающего.
fn (mut ctx RenderContext) reset_overlay_slot() {
	ctx.overlay_owner = unsafe { nil }
	ctx.overlay_cb = unsafe { nil }
	ctx.overlay_ev = unsafe { nil }
	ctx.overlay_close = unsafe { nil }
}

// release_overlay снимает оверлей виджета ptr во ВСЕХ окнах и диалогах
// приложения. Вызывается из vgui_destroy (через
// capi_release_overlay_everywhere), обход по окнам — по той же причине, что у
// unregister_focus: указателя на родителя у виджета нет.
//
// Замыкания в слоте держат указатель на виджет: без снятия раскрытый список
// уничтоженного ComboBox рисовался бы каждый кадр и пинил структуру для
// Boehm-GC. close-хук здесь НЕ зовётся — он пишет в поля виджета, чья
// структура уходит. Окно инвалидируется, а prev_overlayish делает следующий
// кадр полным, так что попап стирается в том же кадре.
pub fn (mut app App) release_overlay(ptr voidptr) {
	if ptr == unsafe { nil } {
		return
	}
	for mut w in app.windows {
		if w.ctx.overlay_owner == ptr {
			w.ctx.reset_overlay_slot()
			w.ctx.invalidate_all()
		}
	}
	for mut d in app.dialogs {
		if d.win.ctx.overlay_owner == ptr {
			d.win.ctx.reset_overlay_slot()
			d.win.ctx.invalidate_all()
		}
	}
}
