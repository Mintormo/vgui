module vgui

import os

// Кэш текстур картинок MarkdownView привязан к рендереру (MdImageTexture).
// Аудит 2026-10, 1.1: cleanup() звал SDL_DestroyTexture без проверки, жив ли
// рендерер, - после закрытия окна это повторное освобождение; а кэш по голому
// пути отдавал текстуру чужого или уже мёртвого рендерера, если виджет
// переносили в другое окно.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test markdown_texture_test.v

const md_test_image = os.join_path(@VMODROOT, 'assets', 'icons', 'home.png')

fn test_image_texture_is_bound_to_renderer() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win1 := create_window(title: 'md1', width: 200, height: 200)!
	mut win2 := create_window(title: 'md2', width: 200, height: 200)!
	app.add_window(win1)
	app.add_window(win2)
	mut md := markdown_view()

	// Повторное обращение с тем же рендерером - та же текстура из кэша.
	tex1 := md.image_texture(md_test_image, win1.ctx)
	assert tex1 != unsafe { nil }
	assert md.image_texture(md_test_image, win1.ctx) == tex1

	// Другой рендерер (виджет перенесли в другое окно) - своя текстура,
	// запись кэша теперь принадлежит второму рендереру.
	tex2 := md.image_texture(md_test_image, win2.ctx)
	assert tex2 != unsafe { nil }
	entry := md.image_cache[md_test_image] or { panic('нет записи в кэше') }
	assert entry.renderer == win2.ctx.renderer
	assert is_renderer_alive_gen(entry.renderer, entry.gen)

	// Окно закрыто: SDL освободил текстуру вместе с рендерером, запись
	// распознаётся как мёртвая, и cleanup её второй раз не освобождает.
	win2.cleanup()
	assert !is_renderer_alive_gen(entry.renderer, entry.gen)
	md.cleanup()
	assert md.image_cache.len == 0
	md.cleanup() // повторный вызов безопасен

	// Нечитаемый файл - nil, кэш не засоряется.
	assert md.image_texture('/nonexistent/image.png', win1.ctx) == unsafe { nil }
	assert md.image_cache.len == 0

	win1.cleanup()
	app.cleanup()
}
