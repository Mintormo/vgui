module vgui

import os

// Линтер «виджеты не зовут SDL напрямую» (PROJECT.md, «Бэкенд рисования:
// виджеты не зовут SDL напрямую»; план - docs/backend_abstraction.md, этап 7).
//
// Рисование, текстуры, шрифты, картинки и часы собраны за RenderContext и
// несколькими файлами бэкенда; окно, события, трей, нативные диалоги - это
// платформенный слой. Только этим файлам можно обращаться к C.SDL_* / C.TTF_* /
// C.IMG_*. Виджет, который снова позовёт SDL сам (SDL_GetTicks, своя текстура,
// SDL_RenderGeometry...), роняет тест с именем файла и строкой.
//
// Новому файлу бэкенда или платформы место в списке ниже - с пояснением, зачем
// ему SDL. Тестам (*_test.v) SDL можно: они проверяют и сам бэкенд.

// backend_files - файлы, которым разрешены прямые вызовы SDL/SDL_ttf/SDL_image.
const backend_files = [
	// бэкенд рисования
	'sdl3_bindings.v', // объявления C-функций и платформенные помощники (курсор, URL, модификаторы)
	'sdl3_render.v', // примитивы RenderContext
	'sdl3_fonts.v', // текст и кэш текстур текста
	'sdl3_icon_font.v', // шрифт иконок Lucide
	'sdl3_texture.v', // тип Texture
	'render_context.v', // общие помощники контекста (метрики шрифта)
	'font_cache.v', // общий кэш наборов шрифтов
	'image_io.v', // чтение/запись картинок в RGBA
	'image_export.v', // снимок кадра окна в файл
	'clock.v', // часы интерфейса
	// платформенный слой
	'sdl3_app.v',
	'sdl3_window.v',
	'sdl3_hdpi.v',
	'events.v',
	'borderless.v',
	'dnd.v',
	'tray.v',
	'native_file_dialog.v',
	'i18n.v', // язык системы
	'testkit.v', // симуляция ввода и захват кадра для тестов
]

fn test_widgets_do_not_call_sdl() {
	mut offenders := []string{}
	for path in os.glob(os.join_path(@VMODROOT, '*.v'))! {
		name := os.file_name(path)
		if name.ends_with('_test.v') || name in backend_files {
			continue
		}
		lines := os.read_lines(path)!
		for i, line in lines {
			code := line.all_before('//')
			if code.contains('C.SDL_') || code.contains('C.TTF_') || code.contains('C.IMG_') {
				offenders << '${name}:${i + 1}: ${line.trim_space()}'
			}
		}
	}
	if offenders.len > 0 {
		eprintln('Прямые вызовы SDL вне бэкенда (перенесите за RenderContext, см. PROJECT.md):')
		for o in offenders {
			eprintln('  ${o}')
		}
	}
	assert offenders.len == 0
}

// Список не должен устаревать: каждый файл из него существует.
fn test_backend_files_exist() {
	for name in backend_files {
		assert os.exists(os.join_path(@VMODROOT, name)), name
	}
}
