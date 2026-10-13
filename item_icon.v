module vgui

// ═══════════════════════════════════════════════════════
// ItemIcon — иконка элемента внутри виджета: пункта меню, узла дерева,
// вкладки, строки списка, пункта ComboBox, секции Accordion, MenuButton.
// ═══════════════════════════════════════════════════════
//
// Один тип и один код отрисовки вместо копий по виджетам. Источник - один
// из трёх (приоритет при нескольких заданных - в этом порядке):
//   - name - глиф встроенного шрифта Lucide (icon_names.v), красится цветом;
//   - path - картинка из файла (png, svg, webp...), рисуется как есть;
//   - data - картинка из байтов (например, $embed_file), рисуется как есть.
// Пустая ItemIcon (ItemIcon{}) - «иконки нет»: виджет не рисует её и не
// резервирует под неё место. Неизвестное имя Lucide или непрочитанная
// картинка - тоже не ошибка: иконка просто не рисуется (место остаётся).
//
// Цвет: color с альфой 0 (по умолчанию) - цвет, который передал виджет
// (обычно цвет текста элемента: выделенного, неактивного...), так глиф
// перекрашивается вместе с темой и состоянием. На картинки цвет не влияет.
//
// Текстуры картинок живут в кэше окна (RenderContext.icon_cache: ключ - путь
// или «mem:<хэш>:<длина>» для байтов), глифы - в text_cache, как у Icon.
// Поэтому ItemIcon - простое значение без ресурсов: копируется свободно,
// освобождать нечего.

// ItemIcon - значение иконки элемента. Поля name/path/color можно менять
// напрямую; байты - только через item_icon_data (вместе с ними считается
// ключ кэша).
pub struct ItemIcon {
pub mut:
	name  string // имя глифа Lucide, например 'save'
	path  string // путь к файлу картинки
	color Color = Color{0, 0, 0, 0} // a == 0 - цвет от виджета (см. выше)
mut:
	data     []u8   // байты картинки (своя копия)
	data_key string // ключ кэша текстуры для data, см. item_icon_data
}

// ─── Constructors ──────────────────────────────────────

// item_icon - глиф Lucide по имени ('' - иконки нет).
pub fn item_icon(name string) ItemIcon {
	return ItemIcon{
		name: name
	}
}

// item_icon_file - картинка из файла ('' - иконки нет).
pub fn item_icon_file(path string) ItemIcon {
	return ItemIcon{
		path: path
	}
}

// item_icon_data - картинка из байтов (PNG, SVG...). Байты копируются: вызывающий
// (в том числе Python через ctypes) может освободить свой буфер сразу.
pub fn item_icon_data(data []u8) ItemIcon {
	if data.len == 0 {
		return ItemIcon{}
	}
	return ItemIcon{
		data:     data.clone()
		data_key: 'mem:${item_icon_hash(data)}:${data.len}'
	}
}

// item_icon_hash - FNV-1a по байтам картинки: одинаковые картинки делят одну
// текстуру, разные (почти наверняка) получают разные ключи.
fn item_icon_hash(data []u8) u64 {
	mut h := fnv1a_offset
	for b in data {
		h = (h ^ u64(b)) * fnv1a_prime
	}
	return h
}

// ─── Queries ───────────────────────────────────────────

// is_set - задан ли источник. Пустая иконка места не занимает.
pub fn (ic &ItemIcon) is_set() bool {
	return ic.name.len > 0 || ic.path.len > 0 || ic.data.len > 0
}

// with_color - та же иконка с другим цветом глифа (Color{} с a == 0 - цвет от виджета).
pub fn (ic ItemIcon) with_color(c Color) ItemIcon {
	mut r := ic
	r.color = c
	return r
}

// ─── Drawing ───────────────────────────────────────────

// draw_item_icon рисует иконку размером size×size (логические px) по центру
// прямоугольника r. fallback - цвет глифа, если у иконки свой цвет не задан.
// Пустая иконка, неизвестное имя и непрочитанная картинка ничего не рисуют.
pub fn (mut ctx RenderContext) draw_item_icon(ic &ItemIcon, r Rect, size f32, fallback Color) {
	if ic.name.len > 0 {
		codepoint, found := icon_codepoint(ic.name)
		if found {
			c := if ic.color.a > 0 { ic.color } else { fallback }
			ctx.draw_icon_glyph(codepoint, r, int(size), c)
		}
		return
	}
	tex := if ic.path.len > 0 {
		ctx.load_icon_texture(ic.path)
	} else if ic.data.len > 0 {
		ctx.load_icon_texture_data(ic.data_key, ic.data)
	} else {
		unsafe { nil }
	}
	if unsafe { tex == nil } {
		return
	}
	ctx.draw_icon(tex, r.x + (r.w - size) * 0.5, r.y + (r.h - size) * 0.5, size, size)
}
