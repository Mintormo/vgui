module vgui

import os

// ═══════════════════════════════════════════════════════
// Тема приложения: окно и диалог без явной темы получают AppConfig.theme
// в add_window/add_dialog; App.set_theme меняет её у всех окон без своей
// темы; явная тема (WindowConfig.theme, Window.set_theme) не трогается.
//
// Запуск: v test vgui/theme_app_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

fn test_window_without_theme_follows_app() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app(theme: dark_theme())!
	mut plain := create_window(title: 'plain', width: 100, height: 100)!
	mut own := create_window(title: 'own', width: 100, height: 100, theme: light_theme())!
	assert !plain.theme_explicit
	assert own.theme_explicit
	app.add_window(plain)
	app.add_window(own)
	assert plain.ctx.theme.bg == dark_theme().bg
	assert own.ctx.theme.bg == light_theme().bg

	// Смена темы приложения - только окнам без своей темы
	app.set_theme(monokai_theme())
	assert plain.ctx.theme.bg == monokai_theme().bg
	assert own.ctx.theme.bg == light_theme().bg

	// set_theme окна делает тему явной
	plain.set_theme(light_theme())
	app.set_theme(dark_theme())
	assert plain.ctx.theme.bg == light_theme().bg

	plain.cleanup()
	own.cleanup()
	app.cleanup()
}

fn test_dialog_theme_parent_then_app() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app(theme: dark_theme())!
	mut parent := create_window(title: 'p', width: 200, height: 200, theme: monokai_theme())!
	app.add_window(parent)
	// Диалог с родителем без темы - тема родителя
	mut d1 := create_dialog(title: 'd1', parent: parent)!
	app.add_dialog(d1)
	assert d1.win.ctx.theme.bg == monokai_theme().bg
	// Без родителя - тема приложения
	mut d2 := create_dialog(title: 'd2')!
	app.add_dialog(d2)
	assert d2.win.ctx.theme.bg == dark_theme().bg
	d1.win.cleanup()
	d2.win.cleanup()
	parent.cleanup()
	app.cleanup()
}
