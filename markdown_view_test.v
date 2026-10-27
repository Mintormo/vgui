module vgui

import os

// MarkdownView: картинки и якоря (аудит 2026-10, 1.1 и 2.17).
//
// 1.1: кэш текстур картинок привязан к рендереру (Texture.belongs_to). cleanup() звал
// SDL_DestroyTexture без проверки, жив ли рендерер, - после закрытия окна это
// повторное освобождение; а кэш по голому пути отдавал текстуру чужого или уже
// мёртвого рендерера, если виджет переносили в другое окно.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test markdown_view_test.v

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
	assert tex1.is_valid()
	assert md.image_texture(md_test_image, win1.ctx).handle == tex1.handle

	// Другой рендерер (виджет перенесли в другое окно) - своя текстура,
	// запись кэша теперь принадлежит второму рендереру.
	tex2 := md.image_texture(md_test_image, win2.ctx)
	assert tex2.is_valid()
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

	// Нечитаемый файл - пустая текстура, кэш не засоряется.
	assert !md.image_texture('/nonexistent/image.png', win1.ctx).is_valid()
	assert md.image_cache.len == 0

	win1.cleanup()
	app.cleanup()
}

// Кэш размеров картинок читается и пишется по одному ключу (аудит 2026-10, 2.17).
fn test_image_path_is_shared_key() {
	mut md := markdown_view()
	md.base_dir = '/docs'
	assert md.image_path('img/a.png') == os.join_path('/docs', 'img/a.png')
	assert md.image_path('/abs/b.png') == '/abs/b.png'
}

// slug: буква не путается с дефисом по младшему байту руны (2.17).
fn test_heading_slug_keeps_unicode_letters() {
	assert md_heading_to_slug('Hello World') == 'hello-world'
	assert md_heading_to_slug('ĭ test') == 'ĭ-test'
	assert md_heading_to_slug('Привет, мир') == 'привет-мир'
}
