module vgui

import os

// Notification: анимация и таймер автозакрытия будят только область уведомления, а не
// всё окно (аудит 2026-10, 3.5; правило mark_anim_rect из CLAUDE.md).
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test notification_dirty_test.v

fn test_notification_marks_only_its_area() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'toast', width: 800, height: 600)!
	app.add_window(win)
	mut n := notification_info('Сохранено')
	n.bounds = Rect{500, 500, 260, 60}
	win.ctx.dirty.clear()
	win.ctx.needs_animation = false
	n.draw(mut win.ctx)
	assert win.ctx.needs_animation, 'таймер автозакрытия просит следующий кадр'
	assert !win.ctx.dirty.full, 'не всё окно'
	r := win.ctx.dirty.union_rect()
	assert r.w < 800 && r.h < 600
	assert r.x <= 500 && r.y <= 500

	win.cleanup()
	app.cleanup()
}
