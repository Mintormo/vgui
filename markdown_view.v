// Файл: ./markdown_view.v
module vgui

// ═══════════════════════════════════════════════════════
// MarkdownView - виджет просмотра (и простого редактирования) Markdown.
//
// Что в файле, по порядку:
//   1. типы данных: MarkdownMode, «inline-спаны» (MdSpan - кусок строки со стилем), блоки (MdBlock -
//      абзац, заголовок, код, элемент списка, цитата, hr, картинка, таблица), кэш раскладки
//      (MdLine / MdRenderSpan - уже разбитые по строкам и позиционированные куски текста);
//   2. структура MarkdownView и её публичный API (set_text/load_file/set_mode/зум шрифта ...);
//   3. «Effective colors» - eff_*(): цвет из поля виджета -> из темы -> запасной;
//   4. парсер: parse() режет текст на блоки (строчно, один проход), parse_inline_spans() разбирает
//      внутристрочную разметку (**жирный**, *курсив*, `код`, ~~зачёркнутый~~, [ссылки](url), ![картинки](url));
//   5. раскладка: layout() превращает блоки в MdLine с абсолютными (от начала документа) y и
//      относительными x; layout_spans() - перенос слов;
//   6. отрисовка: draw() и draw_* - рисует только видимые строки, наполняет списки областей для
//      мыши (links, copy_btns) заново каждый кадр;
//   7. события: handle_event (ссылки, кнопки «копировать» у блоков кода, прокрутка, зум Ctrl+колесо);
//   8. зум шрифта и cleanup() текстур картинок.
//
// Как это работает вместе (поток данных):
//   set_text(text) -> parse() заполняет blocks, dirty = true
//   draw() -> ensure_layout() (если dirty или изменилась ширина) -> layout() заполняет lines,
//             anchor_map, total_h/total_w -> цикл по видимым строкам.
// Если mode == .source, всё это не используется: рисуется и получает события вложенный CodeEditor
// (md.editor), а при возврате в .preview текст читается из редактора и разбирается заново.
//
// Связи с остальной библиотекой: measure() - layout_measure.v (константный scrollable_hint),
// тема - Theme.md_* (цвета), текст/шрифты - RenderContext, подсказка по ссылке - Tooltip через
// ctx.pending_tooltips, копирование - app.set_clipboard. Фокус-менеджером виджет не пользуется:
// клавиши принимаются, пока курсор мыши над виджетом (hovered).
//
// Поддерживается: ATX/Setext-заголовки, абзацы с жёстким переносом (два пробела или \ в конце),
// списки (- * + и 1.) с вложенностью по отступу и чекбоксами [ ]/[x], цитаты (с вложенностью >>),
// блоки кода (``` / ~~~ и с отступом), таблицы GFM, горизонтальная черта, картинки с расширением
// синтаксиса масштаба/выравнивания. Не поддерживается: вложенные блоки в списках/цитатах, HTML,
// ссылки-ссылки ([a][b]), форматирование внутри ячеек таблицы (рисуется plain-текст).
// ═══════════════════════════════════════════════════════
import os

// Режим виджета: preview - отрисованный Markdown; source - исходный текст в редакторе (CodeEditor).
pub enum MarkdownMode {
	preview
	source
}

// ─── Inline span types ─────────────────────────────────

// Вид inline-спана (куска текста внутри строки). hard_break - принудительный перенос строки внутри абзаца.
enum MdSpanKind {
	text
	bold
	italic
	bold_italic
	code
	link
	image
	strikethrough
	hard_break
}

// Inline-спан: text - содержимое (для code/strikethrough/bold... без разметки); url/alt - для link и image.
// Для image: image_scale - доля доступной ширины (0 = авто, 0.5 = 50%); image_img_align - выравнивание самой
// картинки, image_align - подписи (alt). Поле checked сейчас нигде не заполняется (чекбоксы хранятся в MdBlock).
struct MdSpan {
mut:
	kind            MdSpanKind
	text            string
	url             string
	alt             string
	checked         bool
	image_scale     f32     // 0 = auto, 0.5 = 50%, 1.0 = 100%
	image_align     MdAlign // caption alignment
	image_img_align MdAlign // image itself alignment (left/center/right)
}

// ─── Block element types ───────────────────────────────

// Вид блока верхнего уровня. empty_line - пустая строка исходника (даёт небольшой вертикальный зазор).
enum MdBlockKind {
	paragraph
	heading
	code_block
	list_item
	blockquote
	hr
	empty_line
	image_block
	table
}

// Ячейка таблицы GFM: разобранные спаны (при отрисовке пока склеиваются в plain-текст) и выравнивание колонки.
struct MdTableCell {
mut:
	spans []MdSpan
	align MdAlign
}

// Выравнивание (колонки таблицы, подписи или самой картинки).
enum MdAlign {
	left
	center
	right
}

// Блок документа - результат parse(). Используются не все поля сразу, а только относящиеся к kind:
//   heading: level (1-6), spans, anchor (GitHub-подобный slug для переходов по #якорю);
//   list_item: level (глубина вложенности = число пробелов / 2), ordered + list_index, is_checkbox/is_checked;
//   blockquote: quote_depth (число «>»); code_block: code_lang, code_text; image_block: image_*;
//   table: table_header, table_rows, table_aligns; paragraph: spans.
struct MdBlock {
mut:
	kind            MdBlockKind
	level           int
	ordered         bool
	list_index      int
	is_checked      bool
	is_checkbox     bool
	spans           []MdSpan
	code_lang       string
	code_text       string
	image_url       string
	image_alt       string
	image_scale     f32     // 0 = auto, 0.5 = 50%, 1.0 = 100%
	image_align     MdAlign // caption alignment
	image_img_align MdAlign // image itself alignment (left/center/right)
	caption_h       f32     // computed caption height (may be multi-line)
	// table fields
	table_header []MdTableCell
	table_rows   [][]MdTableCell
	table_aligns []MdAlign
	// blockquote nesting depth
	quote_depth int
	// heading anchor slug (GitHub-style)
	anchor string
}

// ─── Layout cache ──────────────────────────────────────

// Одна визуальная строка после раскладки. y - абсолютная координата от верха документа (без прокрутки);
// height - высота; block_idx - индекс блока-источника; is_first - первая строка блока (для списка: рисовать маркер;
// для таблицы: это строка заголовка); indent - отступ слева (список, цитата, код); prefix - маркер списка
// («•» или «N.»), задан только у первой строки элемента.
struct MdLine {
mut:
	y         f32
	height    f32
	block_idx int
	is_first  bool
	spans     []MdRenderSpan
	indent    f32
	prefix    string
}

// Позиционированный кусок текста внутри MdLine: x - смещение от левого края строки (без indent), w - ширина.
// Один слово/пробел = один спан. Флаги is_link/is_code/is_strike управляют подчёркиванием, фоном и перечёркиванием.
// Для картинок (is_image) text хранит alt, image_h - полная высота (картинка + подпись), caption_h - высота подписи.
struct MdRenderSpan {
mut:
	x               f32
	w               f32
	text            string
	color           Color
	font_style      FontStyle
	font_size       int
	is_link         bool
	link_url        string
	is_code         bool
	is_strike       bool
	hovered         bool
	is_image        bool
	image_url       string
	image_h         f32
	image_scale     f32
	image_align     MdAlign // caption alignment
	image_img_align MdAlign // image itself alignment
	caption_h       f32     // computed caption height (may be multi-line)
}

// Прямоугольник ссылки в ЭКРАННЫХ координатах (с учётом прокрутки); пересобирается каждым draw() и используется hit-test'ом мыши.
struct MdLinkHit {
mut:
	url string
	x   f32
	y   f32
	w   f32
	h   f32
}

// Область кнопки «копировать» у блока кода (экранные координаты, пересобирается в draw()); block_idx - какой блок копировать.
struct MdCopyBtnHit {
mut:
	block_idx int
	x         f32
	y         f32
	w         f32
	h         f32
}

// Кнопка копирования кода: размер, отступ от угла блока, сколько мс показывать галочку «скопировано».
const md_copy_btn_size = f32(22)
const md_copy_btn_margin = f32(6)
const md_copy_feedback_ms = u64(1200)

// Границы и шаг зума шрифта по умолчанию (Ctrl+колесо, Ctrl+=/-).
const md_default_font_min = 8
const md_default_font_max = 48
const md_default_font_step = 2

// Константы раскладки (px): pad - внутренний отступ виджета; *_gap - вертикальные зазоры; *_indent - сдвиги
// вложенных элементов; md_image_max_h - высота области под картинку, пока её реальный размер неизвестен;
// md_sb_w - толщина полос прокрутки; md_table_cell_pad_* - поля ячеек таблицы.
const md_default_pad = f32(12)
const md_line_gap = f32(4)
const md_paragraph_gap = f32(8)
const md_list_indent = f32(24)
const md_blockquote_indent = f32(16)
const md_blockquote_bar_w = f32(3)
const md_code_block_pad = f32(10)
const md_heading_gap_top = f32(12)
const md_heading_gap_bottom = f32(6)
const md_hr_height = f32(20)
const md_image_max_h = f32(400)
const md_image_caption_line_h = f32(20) // height of one caption line
const md_sb_w = f32(12)
const md_table_cell_pad_h = f32(8)
const md_table_cell_pad_v = f32(5)
const md_table_row_gap = f32(0)
const md_checkbox_size = f32(13)

// MarkdownView. Состояние:
//   text / blocks / lines - исходник, разобранные блоки, строки раскладки (кэш);
//   dirty + last_w - признаки «раскладку надо пересчитать» (изменился текст, шрифт или ширина окна);
//   total_h / total_w - размеры всего содержимого (total_w > 0 только если есть картинки с явным масштабом -
//     текст всегда переносится, поэтому горизонтальная прокрутка нужна лишь им);
//   scroll_x / scroll_y - прокрутка; vsb_* / hsb_* - состояние полос и их перетаскивания;
//   editor - вложенный CodeEditor для режима .source;
//   image_cache - SDL-текстуры картинок по разрешённому пути вместе с рендерером, которому они принадлежат
//     (см. MdImageTexture); image_size_cache - размеры в пикселях (для точной высоты картинок с масштабом
//     в раскладке);
//   links / copy_btns - области под мышь, заполняются в draw(); hovered_* - что под курсором;
//   anchor_map - slug заголовка -> y (для переходов по #якорям);
//   base_dir - каталог для относительных путей картинок и ссылок (выставляет load_file);
//   *_color - переопределения цветов (альфа 0 = взять из темы, см. eff_*);
//   on_link_click / on_navigate_md / on_link_hover - колбэки (см. handle_link_click);
//   font_size = 0 - размер по умолчанию контекста; base_font_size запоминается при первом зуме для Ctrl+0.
@[heap]
pub struct MarkdownView {
pub mut:
	type_tag int = kind_markdown_view // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel                 bool = true
	bounds                Rect
	visible               bool = true
	enabled               bool = true
	hovered               bool
	mode                  MarkdownMode = .preview
	text                  string
	blocks                []MdBlock
	lines                 []MdLine
	links                 []MdLinkHit
	total_h               f32
	total_w               f32
	dirty                 bool = true
	last_w                f32
	editor                &CodeEditor = unsafe { nil }
	image_cache           map[string]MdImageTexture
	image_size_cache      map[string][2]int // [w, h] in pixels
	scroll_y              f32
	scroll_x              f32
	scroll_speed          f32 = 40
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
	pad                   f32 = md_default_pad
	font_size             int
	font_style            FontStyle = .regular
	bg_color              Color     = Color{0, 0, 0, 0}
	text_color            Color     = Color{0, 0, 0, 0}
	heading_color         Color     = Color{0, 0, 0, 0}
	link_color            Color     = Color{0, 0, 0, 0}
	link_hover_color      Color     = Color{0, 0, 0, 0}
	code_bg_color         Color     = Color{0, 0, 0, 0}
	code_text_color       Color     = Color{0, 0, 0, 0}
	quote_bar_color       Color     = Color{0, 0, 0, 0}
	quote_text_color      Color     = Color{0, 0, 0, 0}
	hr_color              Color     = Color{0, 0, 0, 0}
	border_color          Color     = Color{0, 0, 0, 0}
	caption_color         Color     = Color{0, 0, 0, 0}
	table_border_color    Color     = Color{0, 0, 0, 0}
	table_header_bg_color Color     = Color{0, 0, 0, 0}
	hovered_link_idx      int       = -1
	hovered_link_url      string
	on_link_click         fn (string) = unsafe { nil }
	on_link_hover         fn (string) = unsafe { nil }
	on_navigate_md        fn (string) = unsafe { nil }
	link_tooltip_delay    u64         = 600
	link_hover_start      u64
	link_tooltip_showing  bool
	base_dir              string
	// anchor slug → y position (populated during layout)
	anchor_map map[string]f32
	// copy buttons for code blocks (populated during draw)
	copy_btns        []MdCopyBtnHit
	hovered_copy_idx int = -1
	copied_block_idx int = -1
	copied_at        u64
	// font zoom settings (Ctrl+= / Ctrl+- / Ctrl+0)
	min_font_size  int = md_default_font_min
	max_font_size  int = md_default_font_max
	font_size_step int = md_default_font_step
	base_font_size int = -1 // -1 = not yet captured; set on first zoom
}

// ─── Constructors ──────────────────────────────────────

// Объявление C.system - в этом файле не используется (возможно, остаток прежнего кода).
fn C.system(cmd &char) int

// open_system_browser открывает URL во внешней программе по умолчанию (SDL_OpenURL).
pub fn open_system_browser(url string) {
	C.SDL_OpenURL(url.str)
}

// markdown_view создаёт пустой виджет вместе с внутренним CodeEditor для режима .source (без номеров строк и миникарты).
pub fn markdown_view() &MarkdownView {
	mut md := &MarkdownView{}
	mut ce := code_editor()
	ce.show_line_numbers = false
	ce.show_minimap = false
	ce.font_style = .mono
	md.editor = ce
	return md
}

// resolve_url разрешает URL относительно base_dir.
// Для http/https/mailto — возвращает как есть.
// Для относительных путей — соединяет с base_dir.
// resolve_url приводит ссылку к рабочему виду: http(s), mailto, якорь (#...) и абсолютный путь остаются как есть;
// относительный путь соединяется с base_dir (если он задан).
fn (md &MarkdownView) resolve_url(url string) string {
	if url.starts_with('http://') || url.starts_with('https://') || url.starts_with('mailto:')
		|| url.starts_with('#') || os.is_abs_path(url) {
		return url
	}
	if md.base_dir.len > 0 {
		return os.join_path(md.base_dir, url)
	}
	return url
}

// md_heading_to_slug converts heading text to a GitHub-style anchor slug:
// lowercase, spaces→hyphens, only alphanumerics and hyphens kept.
// md_heading_to_slug строит slug заголовка по правилам GitHub: нижний регистр, пробелы/_/- -> '-', остальные ASCII-знаки
// отбрасываются, не-ASCII буквы (кириллица) сохраняются. Затем повторные '-' схлопываются и края обрезаются.
// Замечание: `u8(r)` усекает руну до младшего байта, поэтому редкие не-ASCII знаки, у которых младший байт совпал с
// пробелом/дефисом, превращаются в '-' (на кириллице и латинице не проявляется).
fn md_heading_to_slug(text string) string {
	mut s := ''
	for r in text.to_lower().runes() {
		c := r.str()
		// Сравнивается сама руна: раньше брался её младший байт (u8(r)), и буква
		// вроде U+012D (ĭ, младший байт 0x2D = '-') превращалась в дефис.
		if (r >= `a` && r <= `z`) || (r >= `0` && r <= `9`) {
			s += c
		} else if r == ` ` || r == `-` || r == `_` {
			s += '-'
		}
		// non-ASCII Unicode letters: include as-is (covers Cyrillic etc.)
		else if r > 127 {
			s += c
		}
	}
	// collapse consecutive hyphens
	for s.contains('--') {
		s = s.replace('--', '-')
	}
	return s.trim('-')
}

// scroll_to_anchor scrolls the view so the heading with the given slug is at the top.
// Returns true if the anchor was found.
// scroll_to_anchor прокручивает так, чтобы заголовок со slug был у верхнего края (не дальше max_scroll). false - якоря нет. Нужен готовый anchor_map, т.е. хотя бы одна раскладка.
pub fn (mut md MarkdownView) scroll_to_anchor(slug string) bool {
	if y := md.anchor_map[slug] {
		ms := md.max_scroll()
		md.scroll_y = if y < ms { y } else { ms }
		return true
	}
	return false
}

// handle_link_click: разрешает URL и решает, что делать.
// handle_link_click решает, что делать со ссылкой: #якорь - прокрутка; путь на .md/.markdown (не http) - on_navigate_md
// или, если колбэка нет, загрузка файла в этот же виджет (load_file); всё остальное - внешний браузер.
pub fn (mut md MarkdownView) handle_link_click(raw_url string) {
	url := md.resolve_url(raw_url)

	// Якорь внутри документа
	if url.starts_with('#') {
		md.scroll_to_anchor(url[1..])
		return
	}

	// Ссылка на .md файл
	if (url.ends_with('.md') || url.ends_with('.MD') || url.ends_with('.markdown'))
		&& !url.starts_with('http://') && !url.starts_with('https://') {
		if md.on_navigate_md != unsafe { nil } {
			md.on_navigate_md(url)
		} else {
			// Встроенный переход: загружаем файл прямо в этот виджет
			md.load_file(url)
		}
		return
	}

	open_system_browser(url)
}

pub fn markdown_view_with_text(text string) &MarkdownView {
	mut md := markdown_view()
	md.set_text(text)
	return md
}

// ─── Public API ────────────────────────────────────────

// set_text заменяет документ: разбирает заново, помечает раскладку устаревшей, сбрасывает прокрутку и кэш размеров картинок,
// синхронизирует редактор режима .source. Кадр не инвалидирует.
pub fn (mut md MarkdownView) set_text(text string) {
	md.text = text
	md.parse()
	md.dirty = true
	md.scroll_y = 0
	md.scroll_x = 0
	md.image_size_cache = map[string][2]int{}
	if unsafe { md.editor != nil } {
		mut ce := md.editor
		ce.set_text(text)
	}
}

// get_text - актуальный текст; в режиме .source берётся из редактора (там могут быть несохранённые правки).
pub fn (md &MarkdownView) get_text() string {
	if md.mode == .source && unsafe { md.editor != nil } {
		return md.editor.get_text()
	}
	return md.text
}

// load_file читает файл, запоминает его каталог как base_dir (для относительных картинок/ссылок) и вызывает set_text. false - не удалось прочитать.
pub fn (mut md MarkdownView) load_file(path string) bool {
	content := os.read_file(path) or { return false }
	md.base_dir = os.dir(path)
	md.set_text(content)
	return true
}

// save_file записывает get_text() в файл. false - ошибка записи.
pub fn (md &MarkdownView) save_file(path string) bool {
	text := md.get_text()
	os.write_file(path, text) or { return false }
	return true
}

// set_mode переключает режим. При возврате из .source в .preview текст забирается из редактора и разбирается заново (иначе правки не отобразятся).
pub fn (mut md MarkdownView) set_mode(mode MarkdownMode) {
	if md.mode == mode {
		return
	}
	if md.mode == .source && mode == .preview && unsafe { md.editor != nil } {
		md.text = md.editor.get_text()
		md.parse()
		md.dirty = true
	}
	md.mode = mode
}

pub fn (md &MarkdownView) get_mode() MarkdownMode {
	return md.mode
}

pub fn (mut md MarkdownView) toggle_mode() {
	new_mode := if md.mode == .preview { MarkdownMode.source } else { MarkdownMode.preview }
	md.set_mode(new_mode)
}

// ─── Effective colors ──────────────────────────────────

// eff_* (до конца блока) - «эффективный» цвет: своё поле виджета (альфа > 0), иначе цвет Theme.md_* (если задан), иначе
// производное от общих цветов темы. Так тема может красить Markdown, а приложение - переопределять отдельные цвета.
fn (md &MarkdownView) eff_bg(ctx &RenderContext) Color {
	if md.bg_color.a > 0 {
		return md.bg_color
	}
	return ctx.theme.input_bg
}

fn (md &MarkdownView) eff_text(ctx &RenderContext) Color {
	if md.text_color.a > 0 {
		return md.text_color
	}
	return ctx.theme.text_primary
}

fn (md &MarkdownView) eff_heading(ctx &RenderContext) Color {
	if md.heading_color.a > 0 {
		return md.heading_color
	}
	if ctx.theme.md_heading.a > 0 {
		return ctx.theme.md_heading
	}
	return ctx.theme.text_primary
}

fn (md &MarkdownView) eff_link(ctx &RenderContext) Color {
	if md.link_color.a > 0 {
		return md.link_color
	}
	if ctx.theme.md_link.a > 0 {
		return ctx.theme.md_link
	}
	return ctx.theme.accent
}

fn (md &MarkdownView) eff_link_hover(ctx &RenderContext) Color {
	if md.link_hover_color.a > 0 {
		return md.link_hover_color
	}
	if ctx.theme.md_link_hover.a > 0 {
		return ctx.theme.md_link_hover
	}
	return ctx.theme.accent.brighten(0.2)
}

fn (md &MarkdownView) eff_code_bg(ctx &RenderContext) Color {
	if md.code_bg_color.a > 0 {
		return md.code_bg_color
	}
	if ctx.theme.md_code_bg.a > 0 {
		return ctx.theme.md_code_bg
	}
	return ctx.theme.panel_bg
}

fn (md &MarkdownView) eff_code_text(ctx &RenderContext) Color {
	if md.code_text_color.a > 0 {
		return md.code_text_color
	}
	if ctx.theme.md_code_text.a > 0 {
		return ctx.theme.md_code_text
	}
	return Color{220, 180, 120, 255}
}

fn (md &MarkdownView) eff_quote_bar(ctx &RenderContext) Color {
	if md.quote_bar_color.a > 0 {
		return md.quote_bar_color
	}
	if ctx.theme.md_quote_bar.a > 0 {
		return ctx.theme.md_quote_bar
	}
	return ctx.theme.accent
}

fn (md &MarkdownView) eff_quote_text(ctx &RenderContext) Color {
	if md.quote_text_color.a > 0 {
		return md.quote_text_color
	}
	if ctx.theme.md_quote_text.a > 0 {
		return ctx.theme.md_quote_text
	}
	return ctx.theme.text_secondary
}

fn (md &MarkdownView) eff_hr(ctx &RenderContext) Color {
	if md.hr_color.a > 0 {
		return md.hr_color
	}
	if ctx.theme.md_hr.a > 0 {
		return ctx.theme.md_hr
	}
	// border color may be too dark; use a slightly brighter variant
	bc := ctx.theme.border
	if bc.a == 0 {
		return Color{120, 120, 120, 255}
	}
	return bc.brighten(0.3)
}

fn (md &MarkdownView) eff_border(ctx &RenderContext) Color {
	if md.border_color.a > 0 {
		return md.border_color
	}
	if ctx.theme.md_border.a > 0 {
		return ctx.theme.md_border
	}
	return ctx.theme.input_border
}

fn (md &MarkdownView) eff_caption(ctx &RenderContext) Color {
	if md.caption_color.a > 0 {
		return md.caption_color
	}
	if ctx.theme.md_caption.a > 0 {
		return ctx.theme.md_caption
	}
	return ctx.theme.text_secondary.with_alpha(180)
}

fn (md &MarkdownView) eff_table_border(ctx &RenderContext) Color {
	if md.table_border_color.a > 0 {
		return md.table_border_color
	}
	if ctx.theme.md_table_border.a > 0 {
		return ctx.theme.md_table_border
	}
	return ctx.theme.border
}

fn (md &MarkdownView) eff_table_header_bg(ctx &RenderContext) Color {
	if md.table_header_bg_color.a > 0 {
		return md.table_header_bg_color
	}
	if ctx.theme.md_table_header_bg.a > 0 {
		return ctx.theme.md_table_header_bg
	}
	return ctx.theme.panel_bg
}

// ═══════════════════════════════════════════════════════
// Markdown parser
//
// Парсер построчный: parse() идёт по строкам исходника и на каждой пробует варианты в фиксированном порядке
// (пустая строка -> hr -> ATX-заголовок -> Setext -> ограждённый код -> код с отступом -> цитата -> таблица -> маркированный
// список -> нумерованный -> одиночная картинка -> абзац). ПОРЯДОК ВАЖЕН: например, hr проверяется раньше Setext и
// списка (строка '---'), а код с отступом - раньше списка, но с исключением для строк, похожих на элемент списка.
// Абзац - «всё остальное»: собирает строки, пока не встретит начало другого блока.
// ═══════════════════════════════════════════════════════

// parse разбирает md.text в md.blocks (см. описание порядка проверок выше). Переводы строк нормализуются к '\n'. Пустой текст даёт пустой список блоков.
fn (mut md MarkdownView) parse() {
	md.blocks.clear()
	if md.text.len == 0 {
		return
	}

	normalized := md.text.replace('\r\n', '\n').replace('\r', '\n')
	raw_lines := normalized.split('\n')

	mut i := 0
	for i < raw_lines.len {
		line := raw_lines[i]
		trimmed := line.trim_space()

		if trimmed.len == 0 {
			md.blocks << MdBlock{
				kind: .empty_line
			}
			i++
			continue
		}

		if md_is_hr(trimmed) {
			md.blocks << MdBlock{
				kind: .hr
			}
			i++
			continue
		}

		// ATX headings: # H1 … ###### H6
		if trimmed.starts_with('#') {
			level, htext := md_parse_heading(trimmed)
			if level > 0 {
				md.blocks << MdBlock{
					kind:   .heading
					level:  level
					spans:  parse_inline_spans(htext)
					anchor: md_heading_to_slug(htext)
				}
				i++
				continue
			}
		}

		// Setext headings: line followed by === or ---
		if i + 1 < raw_lines.len {
			next := raw_lines[i + 1].trim_space()
			if trimmed.len > 0 && md_is_setext_h1(next) {
				md.blocks << MdBlock{
					kind:   .heading
					level:  1
					spans:  parse_inline_spans(trimmed)
					anchor: md_heading_to_slug(trimmed)
				}
				i += 2
				continue
			}
			if trimmed.len > 0 && md_is_setext_h2(next) {
				md.blocks << MdBlock{
					kind:   .heading
					level:  2
					spans:  parse_inline_spans(trimmed)
					anchor: md_heading_to_slug(trimmed)
				}
				i += 2
				continue
			}
		}

		// Fenced code block
		if trimmed.starts_with('```') || trimmed.starts_with('~~~') {
			fence := trimmed[..3]
			lang := trimmed[3..].trim_space()
			mut code_lines := []string{}
			i++
			for i < raw_lines.len {
				if raw_lines[i].trim_space().starts_with(fence) {
					i++
					break
				}
				code_lines << raw_lines[i]
				i++
			}
			md.blocks << MdBlock{
				kind:      .code_block
				code_lang: lang
				code_text: code_lines.join('\n')
			}
			continue
		}

		// Indented code block (4 spaces or 1 tab), but not if it's a list item
		if (line.starts_with('    ') || line.starts_with('\t')) && !md_is_unordered_list_item(line)
			&& !md_is_ordered_list_item(line) {
			mut code_lines := []string{}
			for i < raw_lines.len {
				cl := raw_lines[i]
				ct := cl.trim_space()
				if ct.len == 0 {
					code_lines << ''
					i++
					continue
				}
				if md_is_unordered_list_item(cl) || md_is_ordered_list_item(cl) {
					break
				}
				if cl.starts_with('    ') {
					code_lines << cl[4..]
					i++
					continue
				}
				if cl.starts_with('\t') {
					code_lines << cl[1..]
					i++
					continue
				}
				break
			}
			// strip trailing empty lines
			for code_lines.len > 0 && code_lines.last().trim_space().len == 0 {
				code_lines.pop()
			}
			if code_lines.len > 0 {
				md.blocks << MdBlock{
					kind:      .code_block
					code_lang: ''
					code_text: code_lines.join('\n')
				}
			}
			continue
		}

		// Цитата: подряд идущие строки с '>' склеиваются в ОДИН блок через пробел (переносы внутри цитаты не сохраняются); quote_depth - максимальное число '>' в блоке.
		// Blockquote (supports nesting via multiple > chars)
		if trimmed.starts_with('>') {
			mut quote_lines := []string{}
			mut depth := 0
			for i < raw_lines.len {
				ql := raw_lines[i].trim_space()
				if !ql.starts_with('>') {
					break
				}
				// count leading > chars to determine depth
				mut d := 0
				mut pos := 0
				for pos < ql.len && ql[pos] == `>` {
					d++
					pos++
					if pos < ql.len && ql[pos] == ` ` {
						pos++
					}
				}
				if d > depth {
					depth = d
				}
				stripped := ql[pos..]
				quote_lines << stripped
				i++
			}
			full_text := quote_lines.join(' ')
			md.blocks << MdBlock{
				kind:        .blockquote
				spans:       parse_inline_spans(full_text)
				quote_depth: depth
			}
			continue
		}

		// Таблица распознаётся парой строк: строка с '|' и сразу за ней строка-разделитель (|---|:--:|). Выравнивание колонок берётся из разделителя.
		// GFM table: detect | ... | ... pattern
		if md_is_table_row(trimmed) && i + 1 < raw_lines.len
			&& md_is_table_separator(raw_lines[i + 1].trim_space()) {
			header_cells := md_parse_table_row(trimmed)
			aligns := md_parse_table_aligns(raw_lines[i + 1].trim_space())
			i += 2

			mut table_header := []MdTableCell{}
			for ci, cell_text in header_cells {
				align := if ci < aligns.len { aligns[ci] } else { MdAlign.left }
				table_header << MdTableCell{
					spans: parse_inline_spans(cell_text)
					align: align
				}
			}

			mut table_rows := [][]MdTableCell{}
			for i < raw_lines.len {
				row_line := raw_lines[i].trim_space()
				if !md_is_table_row(row_line) {
					break
				}
				row_cells := md_parse_table_row(row_line)
				mut row := []MdTableCell{}
				for ci, cell_text in row_cells {
					align := if ci < aligns.len { aligns[ci] } else { MdAlign.left }
					row << MdTableCell{
						spans: parse_inline_spans(cell_text)
						align: align
					}
				}
				table_rows << row
				i++
			}

			md.blocks << MdBlock{
				kind:         .table
				table_header: table_header
				table_rows:   table_rows
				table_aligns: aligns
			}
			continue
		}

		// Глубина вложенности списка = число ведущих пробелов / 2 (таб = 4 пробела); '[ ]' / '[x]' после маркера превращают пункт в чекбокс.
		// Unordered list item (supports - * +), with checkbox
		if md_is_unordered_list_item(line) {
			indent_count := md_count_leading_spaces(line)
			depth := indent_count / 2
			content := line.trim_space()[2..].trim_space()
			mut is_checkbox := false
			mut is_checked := false
			mut item_content := content
			if content.starts_with('[ ] ') || content.starts_with('[x] ')
				|| content.starts_with('[X] ') {
				is_checkbox = true
				is_checked = content[1] == `x` || content[1] == `X`
				item_content = content[4..]
			}
			md.blocks << MdBlock{
				kind:        .list_item
				level:       depth
				ordered:     false
				is_checkbox: is_checkbox
				is_checked:  is_checked
				spans:       parse_inline_spans(item_content)
			}
			i++
			continue
		}

		// Ordered list item
		if num, content := md_parse_ordered_list_item(line) {
			indent_count := md_count_leading_spaces(line)
			depth := indent_count / 2
			md.blocks << MdBlock{
				kind:       .list_item
				level:      depth
				ordered:    true
				list_index: num
				spans:      parse_inline_spans(content)
			}
			i++
			continue
		}

		// Строка вида '![alt](url ...)' целиком - отдельный блок-картинка; такая же разметка в середине текста обрабатывается inline-парсером.
		// Standalone image
		if md_is_standalone_image(trimmed) {
			alt, url, scale, img_align, cap_align := md_parse_image(trimmed)
			md.blocks << MdBlock{
				kind:            .image_block
				image_alt:       alt
				image_url:       url
				image_scale:     scale
				image_img_align: img_align
				image_align:     cap_align
			}
			i++
			continue
		}

		// Абзац: набираем строки, пока очередная не является началом другого блока (список, заголовок, код, таблица, картинка, setext). Остальное см. parse_paragraph_lines.
		// Paragraph (with hard line break support)
		mut para_lines := []string{}
		for i < raw_lines.len {
			para_line := raw_lines[i]
			pt := para_line.trim_space()
			if pt.len == 0 {
				break
			}
			if pt.starts_with('#') || pt.starts_with('>') || pt.starts_with('```')
				|| pt.starts_with('~~~') || md_is_hr(pt) {
				break
			}
			if md_is_unordered_list_item(para_line) {
				break
			}
			if _, _ := md_parse_ordered_list_item(para_line) {
				break
			}
			if md_is_table_row(pt) {
				break
			}
			if para_line.starts_with('    ') || para_line.starts_with('\t') {
				break
			}
			if md_is_standalone_image(pt) {
				break
			}
			// Setext heading check
			if i + 1 < raw_lines.len {
				nxt := raw_lines[i + 1].trim_space()
				if md_is_setext_h1(nxt) || md_is_setext_h2(nxt) {
					break
				}
			}
			para_lines << para_line
			i++
		}
		if para_lines.len > 0 {
			spans := parse_paragraph_lines(para_lines)
			md.blocks << MdBlock{
				kind:  .paragraph
				spans: spans
			}
		}
	}
}

// parse_paragraph_lines handles hard line breaks within paragraphs
// parse_paragraph_lines склеивает строки абзаца в спаны: мягкий перенос - пробел; жёсткий (два пробела или '\\' в конце) - спан hard_break.
fn parse_paragraph_lines(lines []string) []MdSpan {
	mut all_spans := []MdSpan{}
	for li, line in lines {
		// Hard line break: trailing 2+ spaces or trailing backslash
		mut text := line
		mut hard_break := false
		if text.ends_with('\\') {
			hard_break = true
			text = text[..text.len - 1]
		} else if text.len >= 2 && text[text.len - 1] == ` ` && text[text.len - 2] == ` ` {
			hard_break = true
			text = text.trim_right(' ')
		}

		line_spans := parse_inline_spans(text.trim_space())
		all_spans << line_spans

		if hard_break && li < lines.len - 1 {
			all_spans << MdSpan{
				kind: .hard_break
			}
		} else if !hard_break && li < lines.len - 1 {
			// soft wrap: join with space
			all_spans << MdSpan{
				kind: .text
				text: ' '
			}
		}
	}
	return all_spans
}

// ─── Block parser helpers ──────────────────────────────

// md_is_hr: строка из >= 3 одинаковых '-', '*' или '_' (допускаются пробелы между ними).
fn md_is_hr(line string) bool {
	if line.len < 3 {
		return false
	}
	c := line[0]
	if c != `-` && c != `*` && c != `_` {
		return false
	}
	for ch in line.bytes() {
		if ch != c && ch != ` ` && ch != `\t` {
			return false
		}
	}
	mut count := 0
	for ch in line.bytes() {
		if ch == c {
			count++
		}
	}
	return count >= 3
}

// md_is_setext_h1/h2: строка-подчёркивание заголовка Setext ('===' для H1; '--' и длиннее для H2).
fn md_is_setext_h1(line string) bool {
	if line.len < 1 {
		return false
	}
	for ch in line.bytes() {
		if ch != `=` {
			return false
		}
	}
	return true
}

fn md_is_setext_h2(line string) bool {
	if line.len < 1 {
		return false
	}
	for ch in line.bytes() {
		if ch != `-` {
			return false
		}
	}
	return line.len >= 2
}

// md_parse_heading разбирает ATX-заголовок: (уровень 1..6, текст без закрывающих '#'). Уровень 0 - не заголовок (нет пробела после '#', больше 6 решёток).
fn md_parse_heading(line string) (int, string) {
	mut level := 0
	for level < line.len && line[level] == `#` {
		level++
	}
	if level == 0 || level > 6 {
		return 0, ''
	}
	if level >= line.len {
		return level, ''
	}
	if line[level] != ` ` {
		return 0, ''
	}
	// strip optional trailing #s
	mut text := line[level + 1..].trim_space()
	for text.ends_with('#') {
		text = text.trim_right('#').trim_space()
	}
	return level, text
}

// md_count_leading_spaces - ширина отступа в пробелах; таб считается за 4.
fn md_count_leading_spaces(line string) int {
	mut n := 0
	for ch in line.bytes() {
		if ch == ` ` {
			n++
		} else if ch == `\t` {
			n += 4
		} else {
			break
		}
	}
	return n
}

// md_is_unordered_list_item: маркер '-', '*' или '+' и пробел после него.
fn md_is_unordered_list_item(line string) bool {
	t := line.trim_space()
	if t.len < 2 {
		return false
	}
	c := t[0]
	if c != `-` && c != `*` && c != `+` {
		return false
	}
	return t[1] == ` `
}

// md_is_ordered_list_item: цифры, точка и пробел ('1. текст').
fn md_is_ordered_list_item(line string) bool {
	t := line.trim_space()
	if t.len < 3 {
		return false
	}
	mut i := 0
	for i < t.len && t[i] >= `0` && t[i] <= `9` {
		i++
	}
	if i == 0 || i >= t.len || t[i] != `.` {
		return false
	}
	return i + 1 < t.len && t[i + 1] == ` `
}

// md_parse_ordered_list_item возвращает (номер, текст) для элемента нумерованного списка или none.
fn md_parse_ordered_list_item(line string) ?(int, string) {
	t := line.trim_space()
	if t.len < 3 {
		return none
	}
	mut digits := ''
	mut i := 0
	for i < t.len && t[i] >= `0` && t[i] <= `9` {
		digits += t[i..i + 1]
		i++
	}
	if digits.len == 0 {
		return none
	}
	if i >= t.len || t[i] != `.` {
		return none
	}
	if i + 1 >= t.len || t[i + 1] != ` ` {
		return none
	}
	return digits.int(), t[i + 2..].trim_space()
}

// md_is_standalone_image: строка целиком является '![...](...)' (последняя ')' - в конце строки).
fn md_is_standalone_image(line string) bool {
	t := line.trim_space()
	if !t.starts_with('![') {
		return false
	}
	end := t.last_index(')') or { return false }
	return end == t.len - 1
}

// md_parse_image разбирает '![alt](url [=N% опции])' в (alt, url, масштаб, выравнивание картинки, выравнивание подписи). Некорректная разметка даёт пустой url.
fn md_parse_image(line string) (string, string, f32, MdAlign, MdAlign) {
	t := line.trim_space()
	bracket_end := t.index(']') or { return '', '', 0, MdAlign.left, MdAlign.left }
	if bracket_end < 2 {
		return '', '', 0, MdAlign.left, MdAlign.left
	}
	alt := t[2..bracket_end]
	if bracket_end + 1 >= t.len || t[bracket_end + 1] != `(` {
		return '', '', 0, MdAlign.left, MdAlign.left
	}
	url_end := t.last_index(')') or { return alt, '', 0, MdAlign.left, MdAlign.left }
	if url_end <= bracket_end + 2 {
		return alt, '', 0, MdAlign.left, MdAlign.left
	}
	raw := t[bracket_end + 2..url_end]
	url, scale, img_align, cap_align := md_split_url_scale(raw)
	return alt, url, scale, img_align, cap_align
}

// md_split_url_scale splits "path/img.png =50% center cap:right" into
// (url, scale, img_align, cap_align).
// Syntax after '%':
//   left / center / right           → image alignment (caption inherits same)
//   img:left / img:center / img:right  → image alignment only
//   cap:left / cap:center / cap:right  → caption alignment only
// Multiple tokens can be combined: "center cap:right"
// Returns scale=0, both aligns=.left if no size suffix present.
fn md_split_url_scale(raw string) (string, f32, MdAlign, MdAlign) {
	s := raw.trim_space()
	mut eq_pos := -1
	mut pct_end := -1
	for i := s.len - 1; i >= 1; i-- {
		if s[i] == `%` {
			mut j := i - 1
			for j >= 0 && s[j] >= `0` && s[j] <= `9` {
				j--
			}
			if j >= 0 && s[j] == `=` && (j == 0 || s[j - 1] == ` `) {
				eq_pos = j
				pct_end = i
				break
			}
		}
	}
	if eq_pos < 0 {
		return s, 0, MdAlign.left, MdAlign.left
	}
	url := s[..eq_pos].trim_space()
	pct_str := s[eq_pos + 1..pct_end]
	mut pct := pct_str.f32()
	if pct <= 0 {
		return url, 0, MdAlign.left, MdAlign.left
	}
	// Cap at 400% — larger images may simply fail to render.
	if pct > 400 {
		pct = 400
	}
	suffix := s[pct_end + 1..].trim_space().to_lower()
	mut img_align := MdAlign.left
	mut cap_align := MdAlign.left
	mut img_set := false
	for token in suffix.split(' ') {
		t := token.trim_space()
		if t.len == 0 {
			continue
		}
		if t.starts_with('img:') {
			img_align = md_parse_align(t[4..])
			img_set = true
		} else if t.starts_with('cap:') {
			cap_align = md_parse_align(t[4..])
		} else {
			// bare keyword (center/right/left) — image alignment only
			if !img_set { img_align = md_parse_align(t) }
		}
	}
	return url, pct / 100.0, img_align, cap_align
}

// md_parse_align: 'center' / 'right', всё остальное - left.
fn md_parse_align(s string) MdAlign {
	return match s {
		'center' { MdAlign.center }
		'right' { MdAlign.right }
		else { MdAlign.left }
	}
}

// ─── GFM Table helpers ─────────────────────────────────

// md_is_table_row: строка похожа на строку таблицы (начинается с '|' или содержит ' | '). Эвристика, поэтому обычный текст с ' | ' тоже подходит - но таблицей он станет только при следующей строке-разделителе.
fn md_is_table_row(line string) bool {
	return line.starts_with('|') || line.contains(' | ')
}

// md_is_table_separator: строка из '|', '-', ':' и пробелов, содержит '|' и '-'.
fn md_is_table_separator(line string) bool {
	if !line.contains('|') {
		return false
	}
	for ch in line.bytes() {
		if ch != `|` && ch != `-` && ch != `:` && ch != ` ` && ch != `\t` {
			return false
		}
	}
	return line.contains('-')
}

// md_parse_table_row режет строку таблицы по '|' (крайние '|' отбрасываются). Экранированный '\\|' в ячейке не поддерживается.
fn md_parse_table_row(line string) []string {
	mut cells := []string{}
	mut s := line.trim_space()
	if s.starts_with('|') {
		s = s[1..]
	}
	if s.ends_with('|') {
		s = s[..s.len - 1]
	}
	parts := s.split('|')
	for part in parts {
		cells << part.trim_space()
	}
	return cells
}

// md_parse_table_aligns: ':--:' - центр, '--:' - вправо, иначе влево.
fn md_parse_table_aligns(line string) []MdAlign {
	cells := md_parse_table_row(line)
	mut aligns := []MdAlign{}
	for cell in cells {
		c := cell.trim_space()
		left_colon := c.starts_with(':')
		right_colon := c.ends_with(':')
		if left_colon && right_colon {
			aligns << .center
		} else if right_colon {
			aligns << .right
		} else {
			aligns << .left
		}
	}
	return aligns
}

// ═══════════════════════════════════════════════════════
// Inline span parser
//
// parse_inline_spans() - ручной сканер по байтам с накопителем buf для обычного текста. На каждой позиции проверяются
// разметки в порядке приоритета: экранирование '\\x' -> картинка '![' -> ссылка '[' -> код (`` и `) -> ~~зачёркнутый~~ ->
// ***жирный курсив*** -> **жирный** -> *курсив*. Если закрывающий разделитель не найден (find_*_end вернул none),
// символ остаётся обычным текстом. Содержимое спанов НЕ разбирается рекурсивно: внутри **жирного** ссылки и код не работают.
// ═══════════════════════════════════════════════════════

// parse_inline_spans разбирает строку в []MdSpan (см. описание сканера выше).
fn parse_inline_spans(text string) []MdSpan {
	mut spans := []MdSpan{}
	if text.len == 0 {
		return spans
	}

	bytes := text.bytes()
	mut i := 0
	mut buf := ''

	for i < bytes.len {
		c := bytes[i]

		// Escape sequences
		if c == `\\` && i + 1 < bytes.len {
			next := bytes[i + 1]
			if next == `\\` || next == `*` || next == `_` || next == `\`` || next == `[`
				|| next == `]` || next == `(` || next == `)` || next == `~` || next == `!`
				|| next == `#` || next == `+` || next == `-` || next == `.` || next == `{`
				|| next == `}` || next == `|` || next == `>` {
				buf += text[i + 1..i + 2]
				i += 2
				continue
			}
		}

		if c == `!` && i + 1 < bytes.len && bytes[i + 1] == `[` {
			if end := find_image_end(text, i) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				alt, url, scale, img_align, cap_align := parse_image_at(text, i, end)
				spans << MdSpan{
					kind:            .image
					alt:             alt
					url:             url
					image_scale:     scale
					image_img_align: img_align
					image_align:     cap_align
				}
				i = end + 1
				continue
			}
		}

		if c == `[` {
			if end := find_link_end(text, i) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				link_text, url := parse_link_at(text, i, end)
				spans << MdSpan{
					kind: .link
					text: link_text
					url:  url
				}
				i = end + 1
				continue
			}
		}

		if c == `\`` {
			// Double backtick code span
			if i + 1 < bytes.len && bytes[i + 1] == `\`` {
				if end := find_double_code_end(text, i) {
					if buf.len > 0 {
						spans << MdSpan{
							kind: .text
							text: buf
						}
						buf = ''
					}
					code := text[i + 2..end].trim(' ')
					spans << MdSpan{
						kind: .code
						text: code
					}
					i = end + 2
					continue
				}
			}
			if end := find_code_end(text, i) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				code := text[i + 1..end]
				spans << MdSpan{
					kind: .code
					text: code
				}
				i = end + 1
				continue
			}
		}

		if c == `~` && i + 1 < bytes.len && bytes[i + 1] == `~` {
			if end := find_strike_end(text, i) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				inner := text[i + 2..end]
				spans << MdSpan{
					kind: .strikethrough
					text: inner
				}
				i = end + 2
				continue
			}
		}

		// Bold+italic ***text*** or ___text___
		if (c == `*` || c == `_`) && i + 2 < bytes.len && bytes[i + 1] == c && bytes[i + 2] == c {
			delim := text[i..i + 3]
			if end := find_delim_end(text, i + 3, delim) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				inner := text[i + 3..end]
				spans << MdSpan{
					kind: .bold_italic
					text: inner
				}
				i = end + 3
				continue
			}
		}

		// Bold **text** or __text__
		if (c == `*` || c == `_`) && i + 1 < bytes.len && bytes[i + 1] == c {
			delim := text[i..i + 2]
			if end := find_delim_end(text, i + 2, delim) {
				if buf.len > 0 {
					spans << MdSpan{
						kind: .text
						text: buf
					}
					buf = ''
				}
				inner := text[i + 2..end]
				spans << MdSpan{
					kind: .bold
					text: inner
				}
				i = end + 2
				continue
			}
		}

		// Курсив '_' открывается только в начале строки или после пробела - чтобы snake_case внутри слов не превращался в курсив ('*' работает везде).
		// Italic *text* or _text_  (underscore only between word boundaries)
		if c == `*` || c == `_` {
			ok := c == `*` || (c == `_` && (i == 0 || bytes[i - 1] == ` `))
			if ok {
				delim := text[i..i + 1]
				if end := find_delim_end(text, i + 1, delim) {
					if buf.len > 0 {
						spans << MdSpan{
							kind: .text
							text: buf
						}
						buf = ''
					}
					inner := text[i + 1..end]
					spans << MdSpan{
						kind: .italic
						text: inner
					}
					i = end + 1
					continue
				}
			}
		}

		buf += text[i..i + 1]
		i++
	}

	if buf.len > 0 {
		spans << MdSpan{
			kind: .text
			text: buf
		}
	}

	return spans
}

// find_link_end: от '[' по start ищет парную ']' с учётом вложенных скобок, затем требует '(' и ищет ближайшую ')'. Возвращает индекс ')' или none. Скобки внутри URL не поддерживаются.
fn find_link_end(text string, start int) ?int {
	mut depth := 0
	mut i := start
	for i < text.len {
		c := text[i]
		if c == `[` {
			depth++
		} else if c == `]` {
			depth--
			if depth == 0 {
				if i + 1 < text.len && text[i + 1] == `(` {
					mut j := i + 2
					for j < text.len && text[j] != `)` {
						j++
					}
					if j < text.len {
						return j
					}
				}
				return none
			}
		}
		i++
	}
	return none
}

// parse_link_at извлекает (текст, url) из '[текст](url)' по индексам [start, end].
fn parse_link_at(text string, start int, end int) (string, string) {
	bracket_end := text.index_after(']', start) or { return '', '' }
	link_text := text[start + 1..bracket_end]
	url := text[bracket_end + 2..end]
	return link_text, url
}

// find_image_end: как find_link_end, но для '![alt](url)' (старт сдвигается за '!').
fn find_image_end(text string, start int) ?int {
	return find_link_end(text, start + 1)
}

// parse_image_at: как md_parse_image, но для картинки внутри строки.
fn parse_image_at(text string, start int, end int) (string, string, f32, MdAlign, MdAlign) {
	bracket_end := text.index_after(']', start + 1) or {
		return '', '', 0, MdAlign.left, MdAlign.left
	}
	alt := text[start + 2..bracket_end]
	raw := text[bracket_end + 2..end]
	url, scale, img_align, cap_align := md_split_url_scale(raw)
	return alt, url, scale, img_align, cap_align
}

// find_code_end/find_double_code_end/find_strike_end: индекс закрывающего '`', '``' или '~~' либо none.
fn find_code_end(text string, start int) ?int {
	for i := start + 1; i < text.len; i++ {
		if text[i] == `\`` {
			return i
		}
	}
	return none
}

fn find_double_code_end(text string, start int) ?int {
	for i := start + 2; i < text.len - 1; i++ {
		if text[i] == `\`` && text[i + 1] == `\`` {
			return i
		}
	}
	return none
}

fn find_strike_end(text string, start int) ?int {
	for i := start + 2; i < text.len - 1; i++ {
		if text[i] == `~` && text[i + 1] == `~` {
			return i
		}
	}
	return none
}

// find_delim_end ищет закрывающий разделитель выделения (*, **, ***, _ ...). Пропускает позиции, где за разделителем стоит ещё такой же символ, чтобы '**' не принимался за закрытие '*'.
fn find_delim_end(text string, start int, delim string) ?int {
	dl := delim.len
	for i := start; i <= text.len - dl; i++ {
		if text[i..i + dl] == delim {
			if i + dl < text.len && text[i + dl] == delim[0] {
				continue
			}
			return i
		}
	}
	return none
}

// ─── Caption helpers ───────────────────────────────────

// md_caption_wrap splits text into lines that fit within max_w using the given font.
// md_caption_wrap переносит подпись картинки по словам под ширину max_w (шрифт font); возвращает строки.
fn md_caption_wrap(text string, ctx &RenderContext, font voidptr, max_w f32) []string {
	if text.len == 0 {
		return []
	}
	mut lines := []string{}
	mut words := text.split(' ')
	mut cur := ''
	for w in words {
		if w.len == 0 {
			continue
		}
		candidate := if cur.len > 0 { cur + ' ' + w } else { w }
		tw := ctx.measure_text_with_font(candidate, font).x
		if tw > max_w && cur.len > 0 {
			lines << cur
			cur = w
		} else {
			cur = candidate
		}
	}
	if cur.len > 0 {
		lines << cur
	}
	return lines
}

// md_caption_height returns the total height reserved for the caption (0 if no caption).
// md_caption_height - высота подписи: число строк * md_image_caption_line_h; 0, если подписи нет.
fn md_caption_height(text string, ctx &RenderContext, font voidptr, max_w f32) f32 {
	if text.len == 0 {
		return 0
	}
	lines := md_caption_wrap(text, ctx, font, max_w)
	n := if lines.len > 0 { lines.len } else { 1 }
	return f32(n) * md_image_caption_line_h
}

// ═══════════════════════════════════════════════════════
// Layout engine
//
// Раскладка нужна, чтобы не разбирать и не измерять текст каждый кадр: layout() один раз превращает blocks в плоский
// список lines (абсолютные y от верха документа), а draw() только отсекает невидимые строки по прокрутке и рисует.
// Пересчёт - при dirty (новый текст, смена шрифта, загрузка размера картинки) или смене ширины (ensure_layout).
// ═══════════════════════════════════════════════════════

// ensure_layout пересчитывает раскладку, только если она устарела: dirty, изменилась ширина w или строк ещё нет.
fn (mut md MarkdownView) ensure_layout(ctx &RenderContext, w f32) {
	if !md.dirty && md.last_w == w && md.lines.len > 0 {
		return
	}
	md.layout(ctx, w)
	md.dirty = false
	md.last_w = w
}

// layout превращает blocks в lines для ширины max_w. Доступная ширина avail_w = max_w - 2*pad - md_sb_w (место под полосу
// прокрутки резервируется всегда, чтобы появление полосы не меняло переносы). y накапливается сверху вниз: у каждого вида блока
// свои зазоры. Заодно заполняются anchor_map (y заголовков) и total_h/total_w. Для таблиц создаётся по одной строке на ряд
// (содержимое ячеек рисует draw_table_line, а не layout_spans); для блока кода - по строке на строку кода.
fn (mut md MarkdownView) layout(ctx &RenderContext, max_w f32) {
	md.lines.clear()
	md.links.clear()
	md.anchor_map = map[string]f32{}

	if md.blocks.len == 0 {
		md.total_h = 0
		return
	}

	font_r := ctx.get_font_immut(.regular, md.font_size)
	fh := ctx.font_height_of(font_r)

	avail_w := max_w - md.pad * 2 - md_sb_w
	if avail_w <= 0 {
		md.total_h = 0
		return
	}

	mut y := md.pad

	for bi, block in md.blocks {
		match block.kind {
			.empty_line {
				y += fh * 0.5
			}
			.hr {
				md.lines << MdLine{
					y:         y
					height:    md_hr_height
					block_idx: bi
				}
				y += md_hr_height
			}
			.heading {
				heading_size := md_heading_font_size(block.level, md.font_size)
				font_h := ctx.get_font_immut(.bold, heading_size)
				fh_h := ctx.font_height_of(font_h)
				if block.anchor.len > 0 && block.anchor !in md.anchor_map {
					md.anchor_map[block.anchor] = y
				}
				y += md_heading_gap_top
				mut rendered_lines := md.layout_spans(block.spans, ctx, avail_w, fh_h, font_h,
					.bold, heading_size, false, .heading)
				for mut ln in rendered_lines {
					ln.y = y
					ln.block_idx = bi
					md.lines << ln
					y += ln.height
				}
				y += md_heading_gap_bottom
				// Под H1/H2 рисуется линия (draw_heading_line) - резервируем под неё 6 px.
				// Heading underline for H1/H2 — account for separator height
				if block.level <= 2 {
					y += 6
				}
			}
			.paragraph {
				mut rendered_lines := md.layout_spans(block.spans, ctx, avail_w, fh, font_r,
					.regular, md.font_size, false, .paragraph)
				for mut ln in rendered_lines {
					ln.y = y
					ln.block_idx = bi
					md.lines << ln
					y += ln.height
				}
				y += md_paragraph_gap
			}
			.code_block {
				code_lines := block.code_text.split('\n')
				font_m := ctx.get_font_immut(.mono, md.font_size)
				fh_m := ctx.font_height_of(font_m)
				y += md_code_block_pad * 0.5
				for code_line in code_lines {
					mut ln := MdLine{
						y:         y
						height:    fh_m + 2
						block_idx: bi
						indent:    md_code_block_pad
					}
					if code_line.len > 0 {
						display_line := code_line.replace('\t', '    ')
						w := ctx.measure_text_with_font(display_line, font_m).x
						ln.spans << MdRenderSpan{
							x:          0
							w:          w
							text:       display_line
							color:      md.eff_code_text(ctx)
							font_style: .mono
							font_size:  md.font_size
							is_code:    true
						}
					}
					md.lines << ln
					y += ln.height
				}
				y += md_code_block_pad * 0.5
				y += md_paragraph_gap * 0.5
			}
			.list_item {
				indent := f32(block.level + 1) * md_list_indent
				prefix := if block.is_checkbox {
					''
				} else if block.ordered {
					'${block.list_index}.'
				} else {
					'•'
				}
				// checkbox takes extra space
				extra_indent := if block.is_checkbox { md_checkbox_size + 6 } else { f32(0) }
				mut rendered_lines := md.layout_spans(block.spans, ctx, avail_w - indent -
					extra_indent, fh, font_r, .regular, md.font_size, false, .list_item)
				for li, mut ln in rendered_lines {
					ln.y = y
					ln.block_idx = bi
					ln.indent = indent + extra_indent
					if li == 0 {
						ln.prefix = prefix
						ln.is_first = true
					}
					md.lines << ln
					y += ln.height
				}
			}
			.blockquote {
				quote_indent := f32(block.quote_depth) * (md_blockquote_indent +
					md_blockquote_bar_w + 4)
				mut rendered_lines := md.layout_spans(block.spans, ctx, avail_w - quote_indent, fh,
					font_r, .italic, md.font_size, true, .blockquote)
				for mut ln in rendered_lines {
					ln.y = y
					ln.block_idx = bi
					ln.indent = quote_indent
					md.lines << ln
					y += ln.height
				}
				y += md_paragraph_gap * 0.5
			}
			.image_block {
				cap_font := ctx.get_font_immut(.italic, md.font_size)
				target_w_l := if block.image_scale > 0 {
					avail_w * block.image_scale
				} else {
					avail_w
				}
				caption_h := md_caption_height(block.image_alt, ctx, cap_font, target_w_l)
				// Высота картинки: если задан масштаб и реальный размер уже известен (image_size_cache) - по пропорциям, иначе запас md_image_max_h. Размер узнаётся при первой отрисовке и тогда раскладка пересчитывается (dirty).
				// use real image dimensions if cached, else fall back to md_image_max_h
				img_area_h := if block.image_scale > 0 {
					if sz := md.image_size_cache[md.image_path(block.image_url)] {
						tw_l := f32(sz[0])
						th_l := f32(sz[1])
						if tw_l > 0 {
							target_w_l * th_l / tw_l
						} else {
							md_image_max_h
						}
					} else {
						md_image_max_h
					}
				} else {
					md_image_max_h
				}
				img_h := img_area_h + caption_h
				mut ln := MdLine{
					y:         y
					height:    img_h
					block_idx: bi
				}
				md.lines << ln
				y += img_h + md_paragraph_gap
			}
			.table {
				table_y := y
				ncols := if block.table_header.len > 0 { block.table_header.len } else { 1 }
				col_w := avail_w / f32(ncols)
				font_b := ctx.get_font_immut(.bold, md.font_size)
				fh_b := ctx.font_height_of(font_b)

				// Header row height
				header_h := fh_b + md_table_cell_pad_v * 2
				mut ln_header := MdLine{
					y:         y
					height:    header_h
					block_idx: bi
					is_first:  true
				}
				md.lines << ln_header
				y += header_h

				// Data rows
				for _ in block.table_rows {
					row_h := fh + md_table_cell_pad_v * 2
					mut ln_row := MdLine{
						y:         y
						height:    row_h
						block_idx: bi
					}
					md.lines << ln_row
					y += row_h
				}
				y += md_paragraph_gap
				// table_y и col_w вычислены, но не используются (заглушки от предупреждений компилятора; ширину колонок реально считает draw_table_line).
				_ = table_y
				_ = col_w
			}
		}
	}

	md.total_h = y + md.pad

	// total_w нужен только для горизонтальной прокрутки, а текст всегда переносится - поэтому он считается лишь по картинкам с явным масштабом.
	// compute total_w only from images with explicit scale — text always wraps, never triggers HSB
	mut max_content_w := f32(0)
	for ln in md.lines {
		if ln.block_idx >= 0 && ln.block_idx < md.blocks.len {
			blk := md.blocks[ln.block_idx]
			if blk.kind == .image_block && blk.image_scale > 0 {
				img_w := avail_w * blk.image_scale
				if img_w > max_content_w {
					max_content_w = img_w
				}
			}
		}
	}
	md.total_w = if max_content_w > 0 { max_content_w + md.pad * 2 } else { 0 }
}

// Контекст, в котором раскладываются спаны (абзац/заголовок/пункт/цитата). Сейчас используется для выбора цвета заголовка; md_span_font параметр игнорирует.
enum MdLayoutContext {
	paragraph
	heading
	list_item
	blockquote
}

// layout_spans раскладывает спаны блока по строкам шириной max_w (перенос слов). Возвращает []MdLine БЕЗ y/block_idx - их
// проставляет вызывающий layout(). Параметры: line_h - высота строки шрифта; default_style/default_size - базовый стиль
// (напр. .bold у заголовка, .italic у цитаты); is_quote - красить цветом цитаты; параметр `_ voidptr` не используется.
// Алгоритм: спан делится на слова и пробелы; слово, не помещающееся в остаток строки, переносит строку; слово шире целой
// строки режется по символам; ведущие пробелы в начале строки отбрасываются; картинка всегда занимает отдельную строку;
// hard_break завершает строку принудительно.
fn (md &MarkdownView) layout_spans(spans []MdSpan, ctx &RenderContext, max_w f32, line_h f32, _ voidptr, default_style FontStyle, default_size int, is_quote bool, lctx MdLayoutContext) []MdLine {
	mut result := []MdLine{}
	if spans.len == 0 {
		result << MdLine{
			height: line_h + md_line_gap
		}
		return result
	}

	mut current_line := MdLine{
		height: line_h + md_line_gap
	}
	mut current_x := f32(0)

	tc_default := if is_quote {
		md.eff_quote_text(ctx)
	} else if lctx == .heading {
		md.eff_heading(ctx)
	} else {
		md.eff_text(ctx)
	}

	for span in spans {
		if span.kind == .image {
			// Flush current line before image
			if current_line.spans.len > 0 {
				current_line.height = line_h + md_line_gap
				result << current_line
				current_line = MdLine{
					height: line_h + md_line_gap
				}
				current_x = 0
			}
			// img_w = fraction of available width; allow > max_w for upscale
			img_w := if span.image_scale > 0 { max_w * span.image_scale } else { max_w }
			cap_font := ctx.get_font_immut(.italic, default_size)
			caption_h := md_caption_height(span.alt, ctx, cap_font, img_w)
			img_area_h_l := if span.image_scale > 0 {
				if sz := md.image_size_cache[md.image_path(span.url)] {
					tw_l := f32(sz[0])
					th_l := f32(sz[1])
					if tw_l > 0 {
						img_w * th_l / tw_l
					} else {
						md_image_max_h
					}
				} else {
					md_image_max_h
				}
			} else {
				md_image_max_h
			}
			img_h := img_area_h_l + caption_h
			mut img_line := MdLine{
				height: img_h
			}
			img_line.spans << MdRenderSpan{
				x:               0
				w:               img_w
				is_image:        true
				image_url:       span.url
				image_h:         img_h
				image_scale:     span.image_scale
				image_align:     span.image_align
				image_img_align: span.image_img_align
				caption_h:       caption_h
				text:            span.alt
			}
			result << img_line
			current_line = MdLine{
				height: line_h + md_line_gap
			}
			current_x = 0
			continue
		}

		// Hard break: flush current line and start new one
		if span.kind == .hard_break {
			current_line.height = line_h + md_line_gap
			result << current_line
			current_line = MdLine{
				height: line_h + md_line_gap
			}
			current_x = 0
			continue
		}

		span_style, span_size := md_span_font(span, default_style, default_size, lctx)
		span_font := ctx.get_font_immut(span_style, span_size)

		mut span_color := tc_default
		mut is_link := false
		mut link_url := ''
		mut is_code_span := false
		mut is_strike := false

		match span.kind {
			.link {
				span_color = md.eff_link(ctx)
				is_link = true
				link_url = span.url
			}
			.code {
				span_color = md.eff_code_text(ctx)
				is_code_span = true
			}
			.strikethrough {
				is_strike = true
			}
			else {}
		}

		text := span.text
		if text.len == 0 {
			continue
		}

		// Делим на «слова» и одиночные пробелы (пробелы отдельными элементами, чтобы перенос не терял и не дублировал их).
		// Word-wrap: split into words, handle long words without spaces
		mut words := []string{}
		mut buf := ''
		for r in text.runes() {
			if r == ` ` {
				if buf.len > 0 {
					words << buf
					buf = ''
				}
				words << ' '
			} else {
				buf += r.str()
			}
		}
		if buf.len > 0 {
			words << buf
		}

		for word in words {
			if word.len == 0 {
				continue
			}
			ww := ctx.measure_text_with_font(word, span_font).x

			if word == ' ' && current_x == 0 {
				continue
			}

			if current_x + ww > max_w && current_x > 0 {
				current_line.height = line_h + md_line_gap
				result << current_line
				current_line = MdLine{
					height: line_h + md_line_gap
				}
				current_x = 0
				if word == ' ' {
					continue
				}
			}

			// Слово длиннее строки (длинный URL и т.п.) - режем по символам, иначе оно вылезло бы за правый край.
			// Long word that doesn't fit even on empty line: split char by char
			if ww > max_w && current_x == 0 && word != ' ' {
				mut char_buf := ''
				mut char_w := f32(0)
				for r in word.runes() {
					ch := r.str()
					cw := ctx.measure_text_with_font(ch, span_font).x
					if char_w + cw > max_w && char_buf.len > 0 {
						current_line.spans << MdRenderSpan{
							x:          current_x
							w:          char_w
							text:       char_buf
							color:      span_color
							font_style: span_style
							font_size:  span_size
							is_link:    is_link
							link_url:   link_url
							is_code:    is_code_span
							is_strike:  is_strike
						}
						current_line.height = line_h + md_line_gap
						result << current_line
						current_line = MdLine{
							height: line_h + md_line_gap
						}
						current_x = 0
						char_buf = ''
						char_w = 0
					}
					char_buf += ch
					char_w += cw
				}
				if char_buf.len > 0 {
					current_line.spans << MdRenderSpan{
						x:          current_x
						w:          char_w
						text:       char_buf
						color:      span_color
						font_style: span_style
						font_size:  span_size
						is_link:    is_link
						link_url:   link_url
						is_code:    is_code_span
						is_strike:  is_strike
					}
					current_x += char_w
				}
				continue
			}

			rs := MdRenderSpan{
				x:          current_x
				w:          ww
				text:       word
				color:      span_color
				font_style: span_style
				font_size:  span_size
				is_link:    is_link
				link_url:   link_url
				is_code:    is_code_span
				is_strike:  is_strike
			}
			current_line.spans << rs
			current_x += ww
		}
	}

	if current_line.spans.len > 0 || result.len == 0 {
		current_line.height = line_h + md_line_gap
		result << current_line
	}

	return result
}

// md_span_font выбирает стиль шрифта спана с учётом базового: жирный внутри курсива (цитата) = bold_italic и наоборот; код = mono. Размер возвращается без изменений.
fn md_span_font(span MdSpan, default_style FontStyle, default_size int, _ MdLayoutContext) (FontStyle, int) {
	mut style := default_style
	mut size := default_size

	match span.kind {
		.bold {
			if default_style == .italic {
				style = .bold_italic
			} else {
				style = .bold
			}
		}
		.italic {
			if default_style == .bold {
				style = .bold_italic
			} else {
				style = .italic
			}
		}
		.bold_italic {
			style = .bold_italic
		}
		.code {
			style = .mono
		}
		else {}
	}

	return style, size
}

// md_heading_font_size: размер заголовка = базовый (14, если 0) + прибавка по уровню (H1 +14 ... H6 +1).
fn md_heading_font_size(level int, base int) int {
	b := if base <= 0 { 14 } else { base }
	return match level {
		1 { b + 14 }
		2 { b + 10 }
		3 { b + 7 }
		4 { b + 4 }
		5 { b + 2 }
		6 { b + 1 }
		else { b }
	}
}

// ═══════════════════════════════════════════════════════
// Geometry
// ═══════════════════════════════════════════════════════

// Нужны ли полосы - считается совместно, т.к. появление одной уменьшает область и может вызвать вторую.
// Returns (has_vsb, has_hsb) — computed together to avoid circular dependency
fn (md &MarkdownView) sb_flags() (bool, bool) {
	// First pass: check without accounting for the other scrollbar
	vsb1 := md.total_h > md.bounds.h
	hsb1 := md.total_w > md.bounds.w
	// Second pass: if one scrollbar appears, it reduces space and may trigger the other
	vsb2 := if hsb1 { md.total_h > md.bounds.h - md_sb_w } else { vsb1 }
	hsb2 := if vsb1 { md.total_w > md.bounds.w - md_sb_w } else { hsb1 }
	return vsb2, hsb2
}

fn (md &MarkdownView) has_vsb() bool {
	vsb, _ := md.sb_flags()
	return vsb
}

fn (md &MarkdownView) has_hsb() bool {
	_, hsb := md.sb_flags()
	return hsb
}

// viewport - область содержимого: bounds минус места под видимые полосы.
fn (md &MarkdownView) viewport() Rect {
	vsb, hsb := md.sb_flags()
	mut w := md.bounds.w
	mut h := md.bounds.h
	if vsb {
		w -= md_sb_w
	}
	if hsb {
		h -= md_sb_w
	}
	return Rect{md.bounds.x, md.bounds.y, w, h}
}

fn (md &MarkdownView) max_scroll() f32 {
	return max_f32(0, md.total_h - md.viewport().h)
}

fn (md &MarkdownView) max_scroll_x() f32 {
	return max_f32(0, md.total_w - md.viewport().w)
}

// vsb_rects/hsb_rects: (дорожка, бегунок) полос прокрутки; пустые Rect, если полоса не нужна. Размер бегунка пропорционален видимой доле (не меньше 20 px).
fn (md &MarkdownView) vsb_rects() (Rect, Rect) {
	if !md.has_vsb() {
		return Rect{}, Rect{}
	}
	vp := md.viewport()
	track := Rect{
		x: md.bounds.x + md.bounds.w - md_sb_w
		y: md.bounds.y
		w: md_sb_w
		h: vp.h
	}
	thumb_h := max_f32(20, vp.h * (vp.h / md.total_h))
	ms := md.max_scroll()
	ratio := if ms > 0 { md.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 2
		y: track.y + ratio * (vp.h - thumb_h)
		w: md_sb_w - 4
		h: thumb_h
	}
	return track, thumb
}

fn (md &MarkdownView) hsb_rects() (Rect, Rect) {
	if !md.has_hsb() {
		return Rect{}, Rect{}
	}
	vp := md.viewport()
	track := Rect{
		x: md.bounds.x
		y: md.bounds.y + md.bounds.h - md_sb_w
		w: vp.w
		h: md_sb_w
	}
	thumb_w := max_f32(20, vp.w * (vp.w / md.total_w))
	ms := md.max_scroll_x()
	ratio := if ms > 0 { md.scroll_x / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vp.w - thumb_w)
		y: track.y + 2
		w: thumb_w
		h: md_sb_w - 4
	}
	return track, thumb
}

// ═══════════════════════════════════════════════════════
// Drawing
//
// Кадр: фон и рамка -> (режим .source: рисует CodeEditor и выходит) -> ensure_layout + clamp прокрутки -> проход по строкам,
// которые попадают в видимую область -> кнопки копирования поверх -> подсказка ссылки -> полосы прокрутки.
// Координаты на экране = bounds + pad + line.indent + span.x по x, bounds.y + line.y - scroll_y по y.
// ═══════════════════════════════════════════════════════

// draw рисует виджет (описание кадра выше). Побочные эффекты: пересобирает md.links и md.copy_btns (области под мышь), может поставить анимацию (mark_anim) для таймера подсказки и индикации «скопировано», добавляет Tooltip в ctx.pending_tooltips.
pub fn (mut md MarkdownView) draw(mut ctx RenderContext) {
	if !md.visible {
		return
	}
	if !ctx.is_in_clip(md.bounds) {
		return
	}

	rad := ctx.theme.border_radius

	bg := md.eff_bg(ctx)
	ctx.fill_rounded_rect(md.bounds, bg, rad)

	bc := md.eff_border(ctx)
	ctx.draw_rounded_rect(md.bounds, bc, rad)

	if md.mode == .source {
		if unsafe { md.editor != nil } {
			mut ce := md.editor
			ce.bounds = md.bounds.shrunk(2)
			ce.draw(mut ctx)
		}
		return
	}

	md.ensure_layout(ctx, md.bounds.w)
	md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
	md.scroll_x = clamp_f32(md.scroll_x, 0, md.max_scroll_x())

	vp := md.viewport()
	ctx.push_clip(vp)
	ox := -md.scroll_x // horizontal offset applied to all content x-coordinates

	md.links.clear()
	md.copy_btns.clear()

	// Фон блока кода рисуется один раз на весь блок (а не на каждую строку), поэтому сначала собираем его общий прямоугольник по строкам блока.
	// Pre-compute code block backgrounds (block_idx → Rect) — single O(lines) pass
	mut code_bg_rects := map[int]Rect{}
	for ln in md.lines {
		if ln.block_idx < 0 || ln.block_idx >= md.blocks.len {
			continue
		}
		if md.blocks[ln.block_idx].kind != .code_block {
			continue
		}
		bi := ln.block_idx
		pad_top := md_code_block_pad * 0.5
		if bi in code_bg_rects {
			mut r := code_bg_rects[bi]
			r.h += ln.height
			code_bg_rects[bi] = r
		} else {
			code_bg_rects[bi] = Rect{
				x: md.bounds.x + md.pad + ox
				y: md.bounds.y + ln.y - md.scroll_y - pad_top
				w: vp.w - md.pad * 2
				h: ln.height + md_code_block_pad
			}
		}
	}

	// block_line_start заполняется, но дальше в draw() не читается (остаток прежней реализации таблиц; таблицы ищут начало блока в draw_table_line).
	// Collect line indices per block for table rendering
	mut block_line_start := map[int]int{}
	for li, ln in md.lines {
		if ln.block_idx >= 0 && ln.block_idx !in block_line_start {
			block_line_start[ln.block_idx] = li
		}
	}

	// Track which code block backgrounds have already been drawn this frame
	mut drawn_code_bg := map[int]bool{}

	for li in 0 .. md.lines.len {
		mut line := unsafe { &md.lines[li] }
		ly := md.bounds.y + line.y - md.scroll_y
		if ly + line.height < md.bounds.y {
			continue
		}
		if ly > md.bounds.y + md.bounds.h {
			break
		}

		if line.block_idx < 0 || line.block_idx >= md.blocks.len {
			continue
		}
		block := md.blocks[line.block_idx]

		match block.kind {
			.hr {
				hr_y := ly + line.height * 0.5
				ctx.fill_rect(Rect{md.bounds.x + md.pad + ox, hr_y, vp.w - md.pad * 2, 2},
					md.eff_hr(ctx))
				continue
			}
			.heading {
				md.draw_heading_line(block, line, li, ly, ox, vp, mut ctx)
				continue
			}
			.code_block {
				// Draw the full block background once per block per frame
				if line.block_idx !in drawn_code_bg {
					if bg_r := code_bg_rects[line.block_idx] {
						ctx.fill_rounded_rect(bg_r, md.eff_code_bg(ctx), 4)
					}
					drawn_code_bg[line.block_idx] = true
				}
				// Clip code lines to the block background so long lines don't overflow
				if bg_r := code_bg_rects[line.block_idx] {
					ctx.push_clip(bg_r)
					md.draw_line_spans(line, ly, ox, mut ctx)
					ctx.pop_clip()
					// Register copy button hit-rect (drawing happens in a 2nd pass)
					btn_x := bg_r.x + bg_r.w - md_copy_btn_size - md_copy_btn_margin
					btn_y := bg_r.y + md_copy_btn_margin
					if !md.copy_btns.any(it.block_idx == line.block_idx) {
						md.copy_btns << MdCopyBtnHit{
							block_idx: line.block_idx
							x:         btn_x
							y:         btn_y
							w:         md_copy_btn_size
							h:         md_copy_btn_size
						}
					}
				} else {
					md.draw_line_spans(line, ly, ox, mut ctx)
				}
				continue
			}
			.blockquote {
				// Draw sidebar for each depth level
				for d in 1 .. (block.quote_depth + 1) {
					bar_x := md.bounds.x + md.pad + ox + f32(d -
						1) * (md_blockquote_indent + md_blockquote_bar_w + 4) + 2
					ctx.fill_rect(Rect{bar_x, ly, md_blockquote_bar_w, line.height},
						md.eff_quote_bar(ctx))
				}
			}
			.image_block {
				md.draw_image_block(block, ly, ox, vp, mut ctx)
				continue
			}
			.table {
				md.draw_table_line(block, line, li, ly, ox, vp, mut ctx)
				continue
			}
			.list_item {
				// Draw checkbox if needed
				if block.is_checkbox && line.is_first {
					cx := md.bounds.x + md.pad + ox + f32(block.level + 1) * md_list_indent
					cy := ly + (line.height - md_checkbox_size) * 0.5
					cb_rect := Rect{cx, cy, md_checkbox_size, md_checkbox_size}
					ctx.fill_rounded_rect(cb_rect, md.eff_code_bg(ctx), 2)
					ctx.draw_rounded_rect(cb_rect, md.eff_border(ctx), 2)
					if block.is_checked {
						// Draw checkmark
						check_col := ctx.theme.accent
						ctx.fill_rect(Rect{cx + 3, cy + md_checkbox_size * 0.5 - 1, md_checkbox_size - 6, 2},
							check_col)
						ctx.fill_rect(Rect{cx + 2, cy + md_checkbox_size * 0.5 - 3, 2, 5},
							check_col)
					}
				}
			}
			else {}
		}

		if line.prefix.len > 0 {
			font := ctx.get_font(.regular, md.font_size)
			fh := ctx.font_height_of(font)
			prefix_x := md.bounds.x + md.pad + ox + line.indent - md_list_indent + 4
			prefix_y := ly + (line.height - fh) * 0.5
			ctx.draw_text_with_font(line.prefix, prefix_x, prefix_y, md.eff_text(ctx), font)
		}

		md.draw_line_spans(line, ly, ox, mut ctx)
	}

	// Кнопки копирования рисуем вторым проходом, чтобы они лежали поверх текста кода.
	// Draw copy buttons for code blocks on top of code content
	md.draw_copy_buttons(mut ctx)

	ctx.pop_clip()

	// Подсказка с адресом ссылки появляется после link_tooltip_delay мс наведения: пока ждём, просим кадры (mark_anim), потом выдаём Tooltip.
	// Link tooltip: check delay timer and enqueue for rendering
	if md.hovered_link_url.len > 0 && md.link_hover_start > 0 {
		if !md.link_tooltip_showing {
			elapsed := C.SDL_GetTicks() - md.link_hover_start
			if elapsed >= md.link_tooltip_delay {
				md.link_tooltip_showing = true
			} else {
				ctx.mark_anim('md_link_tooltip')
			}
		}
		if md.link_tooltip_showing {
			mut tip := &Tooltip{
				text:      md.hovered_link_url
				delay_ms:  0
				wrap:      true
				max_width: 320
			}
			tip.showing = true
			ctx.pending_tooltips << tip
		}
	}

	if md.has_vsb() {
		track, thumb := md.vsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if md.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if md.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}

	if md.has_hsb() {
		track, thumb := md.hsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if md.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if md.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
}

// draw_copy_buttons рисует кнопки «копировать» у блоков кода: иконка из двух квадратов или галочка (md_copy_feedback_ms после клика). Список кнопок наполнил draw().
fn (mut md MarkdownView) draw_copy_buttons(mut ctx RenderContext) {
	if md.copy_btns.len == 0 {
		return
	}
	now := C.SDL_GetTicks()
	// Auto-clear "Copied" state after the feedback period
	if md.copied_block_idx >= 0 && now - md.copied_at > md_copy_feedback_ms {
		md.copied_block_idx = -1
	}
	if md.copied_block_idx >= 0 {
		ctx.mark_anim('md_copy_feedback')
	}

	text_color := md.eff_code_text(ctx)
	bg_base := ctx.theme.button_bg
	bg_hover := ctx.theme.accent_hover
	accent := ctx.theme.accent

	for i, btn in md.copy_btns {
		r := Rect{btn.x, btn.y, btn.w, btn.h}
		copied := btn.block_idx == md.copied_block_idx
		hovered := i == md.hovered_copy_idx

		bg := if copied {
			accent
		} else if hovered {
			bg_hover
		} else {
			Color{bg_base.r, bg_base.g, bg_base.b, 200}
		}
		ctx.fill_rounded_rect(r, bg, 4)
		ctx.draw_rounded_rect(r, md.eff_border(ctx), 4)

		fg := if copied { ctx.theme.accent_text } else { text_color }

		if copied {
			// Draw a checkmark
			cx := r.x + r.w * 0.5
			cy := r.y + r.h * 0.5
			ctx.draw_line_thick(cx - 4, cy, cx - 1, cy + 3, 2, fg)
			ctx.draw_line_thick(cx - 1, cy + 3, cx + 5, cy - 3, 2, fg)
		} else {
			// Draw two overlapping rectangles to suggest "copy" icon
			s := f32(8)
			off := f32(2)
			cx := r.x + r.w * 0.5
			cy := r.y + r.h * 0.5
			back := Rect{cx - s * 0.5 + off, cy - s * 0.5 - off, s, s}
			front := Rect{cx - s * 0.5 - off, cy - s * 0.5 + off, s, s}
			ctx.draw_rounded_rect(back, fg, 1)
			ctx.fill_rounded_rect(front, bg, 1)
			ctx.draw_rounded_rect(front, fg, 1)
		}
	}
}

// draw_heading_line рисует строку заголовка (цвет заголовка, ссылки в нём подчёркиваются и регистрируются в md.links); у H1/H2 после последней строки блока добавляет горизонтальную линию.
fn (mut md MarkdownView) draw_heading_line(block MdBlock, line &MdLine, li int, ly f32, ox f32, vp Rect, mut ctx RenderContext) {
	tc := md.eff_heading(ctx)

	for span in line.spans {
		font := ctx.get_font(span.font_style, span.font_size)
		fh := ctx.font_height_of(font)
		span_x := md.bounds.x + md.pad + ox + line.indent + span.x
		span_y := ly + (line.height - fh) * 0.5
		mut color := span.color
		if color.a == 0 {
			color = tc
		}
		if span.is_link && span.link_url == md.hovered_link_url {
			color = md.eff_link_hover(ctx)
		}
		ctx.draw_text_with_font(span.text, span_x, span_y, color, font)

		if span.is_link {
			ul_y := span_y + fh - 1
			ctx.fill_rect(Rect{span_x, ul_y, span.w, 1}, color)
			md.links << MdLinkHit{
				url: span.link_url
				x:   span_x
				y:   ly
				w:   span.w
				h:   line.height
			}
		}
	}

	// Underline rule for H1/H2
	if block.level <= 2 && line.is_first {
		is_last := li + 1 >= md.lines.len || md.lines[li + 1].block_idx != line.block_idx
		if is_last {
			rule_y := ly + line.height + 2
			rule_col := md.eff_hr(ctx)
			ctx.fill_rect(Rect{md.bounds.x + md.pad + ox, rule_y, vp.w - md.pad * 2, 1}, rule_col)
		}
	}
}

// draw_line_spans рисует спаны строки: фон у inline-кода, текст, подчёркивание ссылки (и регистрация MdLinkHit), перечёркивание, картинки (draw_inline_image).
fn (mut md MarkdownView) draw_line_spans(line &MdLine, ly f32, ox f32, mut ctx RenderContext) {
	for span in line.spans {
		span_x := md.bounds.x + md.pad + ox + line.indent + span.x

		if span.is_image {
			md.draw_inline_image(span, span_x, ly, line.height, mut ctx)
			continue
		}

		font := ctx.get_font(span.font_style, span.font_size)
		fh := ctx.font_height_of(font)
		span_y := ly + (line.height - fh) * 0.5

		if span.is_code {
			bg_r := Rect{span_x - 3, span_y - 1, span.w + 6, fh + 2}
			ctx.fill_rounded_rect(bg_r, md.eff_code_bg(ctx), 3)
		}

		mut color := span.color
		if span.is_link && span.link_url == md.hovered_link_url {
			color = md.eff_link_hover(ctx)
		}

		ctx.draw_text_with_font(span.text, span_x, span_y, color, font)

		if span.is_link {
			ul_y := span_y + fh - 1
			ctx.fill_rect(Rect{span_x, ul_y, span.w, 1}, color)
			md.links << MdLinkHit{
				url: span.link_url
				x:   span_x
				y:   ly
				w:   span.w
				h:   line.height
			}
		}

		if span.is_strike {
			st_y := span_y + fh * 0.5
			ctx.fill_rect(Rect{span_x, st_y, span.w, 1}, span.color)
		}
	}
}

// image_path - путь к файлу картинки: относительный url берётся от base_dir. Один ключ
// и для текстур, и для image_size_cache: раньше раскладка читала размеры по сырому url,
// а отрисовка записывала их по пути с base_dir, и при относительных путях высота
// картинки с масштабом оставалась приблизительной.
fn (md &MarkdownView) image_path(url string) string {
	if md.base_dir.len > 0 && !os.is_abs_path(url) {
		return os.join_path(md.base_dir, url)
	}
	return url
}

// MdImageTexture - текстура картинки в кэше вместе с рендерером, которому она принадлежит, и его
// поколением в реестре живых рендереров. Текстура SDL живёт не дольше своего рендерера: когда окно
// закрыто или рендерер пересоздан (сброс устройства Direct3D), SDL уже освободил её сам. Пара
// renderer + gen позволяет это распознать: повторный SDL_DestroyTexture был бы double free, а
// рисование такой текстурой на новом рендерере - обращение к освобождённой памяти. Поколение
// отсекает и новый рендерер, случайно оказавшийся по старому адресу (ABA).
struct MdImageTexture {
	tex      voidptr
	renderer voidptr
	gen      u64
}

// destroy освобождает текстуру, только если её рендерер ещё жив (иначе SDL уже сделал это сам).
fn (entry MdImageTexture) destroy() {
	if unsafe { entry.tex != nil } && is_renderer_alive_gen(entry.renderer, entry.gen) {
		C.SDL_DestroyTexture(entry.tex)
	}
}

// image_texture возвращает текстуру картинки по разрешённому пути для рендерера ctx, загружая её
// при первом обращении (nil - файл не прочитался). Запись кэша, созданная другим или уже мёртвым
// рендерером (виджет перенесли в другое окно, рендерер пересоздан), не используется: она
// освобождается (если её рендерер жив) и картинка загружается заново для текущего.
fn (mut md MarkdownView) image_texture(path string, ctx &RenderContext) voidptr {
	if cached := md.image_cache[path] {
		if cached.renderer == ctx.renderer && is_renderer_alive_gen(cached.renderer, cached.gen) {
			return cached.tex
		}
		cached.destroy()
		md.image_cache.delete(path)
	}
	surface := C.IMG_Load(path.str)
	if unsafe { surface == nil } {
		return unsafe { nil }
	}
	tex := C.SDL_CreateTextureFromSurface(ctx.renderer, surface)
	C.SDL_DestroySurface(surface)
	if unsafe { tex == nil } {
		return unsafe { nil }
	}
	C.SDL_SetTextureBlendMode(tex, sdl_blendmode_blend)
	md.image_cache[path] = MdImageTexture{
		tex:      tex
		renderer: ctx.renderer
		gen:      renderer_generation(ctx.renderer)
	}
	return tex
}

// draw_inline_image рисует картинку внутри абзаца (![...]() в тексте). Текстура создаётся лениво при первом показе и кэшируется
// по разрешённому пути (image_cache); размер запоминается в image_size_cache, и если задан масштаб - раскладка помечается
// dirty, чтобы высота строки стала точной. Нет файла - вместо картинки рисуется «[Image: ...]». Подпись переносится по словам
// под картинкой с выравниванием image_align.
fn (mut md MarkdownView) draw_inline_image(span MdRenderSpan, ix f32, ly f32, line_h f32, mut ctx RenderContext) {
	path := md.image_path(span.image_url)

	if !os.exists(path) {
		font := ctx.get_font(.italic, md.font_size)
		alt := if span.text.len > 0 {
			'[Image: ${span.text}]'
		} else {
			'[Image: ${span.image_url}]'
		}
		ctx.draw_text_with_font(alt, ix + 8, ly + 8, md.eff_text(ctx).with_alpha(180), font)
		return
	}

	tex := md.image_texture(path, ctx)

	if unsafe { tex == nil } {
		return
	}

	mut tw_f := f32(0)
	mut th_f := f32(0)
	C.SDL_GetTextureSize(tex, &tw_f, &th_f)
	tw := int(tw_f)
	th := int(th_f)
	if tw <= 0 || th <= 0 {
		return
	}

	// cache image dimensions for accurate layout; trigger re-layout on first load
	if _ := md.image_size_cache[path] {
	} else {
		md.image_size_cache[path] = [tw, th]!
		if span.image_scale > 0 {
			md.dirty = true
		}
	}

	caption_h := span.caption_h
	img_area_h := line_h - caption_h

	// span.w already accounts for image_scale (set in layout_spans)
	target_w := span.w
	mut dw := f32(tw)
	mut dh := f32(th)
	// scale to target width (up or down)
	if dw != target_w {
		sw := target_w / dw
		dw = target_w
		dh = dh * sw
	}
	// clamp height only when no explicit scale (auto-fit mode)
	if span.image_scale <= 0 && dh > img_area_h {
		sh := img_area_h / dh
		dh = img_area_h
		dw = dw * sh
	}

	dst := C.SDL_FRect{
		x: ix
		y: ly
		w: dw
		h: dh
	}
	C.SDL_RenderTexture(ctx.renderer, tex, unsafe { nil }, &dst)

	// Multi-line caption below the image
	if span.text.len > 0 && caption_h > 0 {
		font := ctx.get_font(.italic, md.font_size)
		fh := ctx.font_height_of(font)
		cap_lines := md_caption_wrap(span.text, ctx, font, dw)
		caption_color := md.eff_caption(ctx)
		for ci, cl in cap_lines {
			cap_y := ly + dh + f32(ci) * md_image_caption_line_h +
				(md_image_caption_line_h - fh) * 0.5
			tw_cap := ctx.measure_text_with_font(cl, font).x
			cap_x := match span.image_align {
				.center { ix + (dw - tw_cap) * 0.5 }
				.right { ix + dw - tw_cap }
				else { ix }
			}

			ctx.draw_text_with_font(cl, cap_x, cap_y, caption_color, font)
		}
	}
}

// draw_table_line рисует ОДНУ строку таблицы (layout создал по строке на ряд). Номер ряда определяется поиском первой строки блока;
// is_first - заголовок. Колонки одинаковой ширины (ширина поровну), текст ячеек - plain (md_spans_to_plain), выравнивание по
// table_aligns; границы рисуются как 1-px линии.
fn (mut md MarkdownView) draw_table_line(block MdBlock, line &MdLine, li int, ly f32, ox f32, vp Rect, mut ctx RenderContext) {
	ncols := if block.table_header.len > 0 { block.table_header.len } else { 1 }
	col_w := (vp.w - md.pad * 2) / f32(ncols)
	table_x := md.bounds.x + md.pad + ox
	border_col := md.eff_table_border(ctx)
	header_bg := md.eff_table_header_bg(ctx)

	// Determine row index within block
	mut row_idx := -1 // -1 = header
	mut cur_li := li
	// Find the first line of this block
	for cur_li > 0 && md.lines[cur_li - 1].block_idx == line.block_idx {
		cur_li--
	}
	row_idx = li - cur_li - 1 // 0 = first data row, -1 = header

	is_header := line.is_first

	// Row background
	if is_header {
		row_rect := Rect{table_x, ly, vp.w - md.pad * 2, line.height}
		ctx.fill_rect(row_rect, header_bg)
	}

	// Draw top border on first row
	if is_header {
		ctx.fill_rect(Rect{table_x, ly, vp.w - md.pad * 2, 1}, border_col)
	}

	// Draw cells
	cells := if is_header {
		block.table_header
	} else if row_idx >= 0 && row_idx < block.table_rows.len {
		block.table_rows[row_idx]
	} else {
		[]MdTableCell{}
	}

	font_style := if is_header { FontStyle.bold } else { FontStyle.regular }
	font := ctx.get_font(font_style, md.font_size)
	fh := ctx.font_height_of(font)
	text_col := md.eff_text(ctx)

	for ci in 0 .. ncols {
		cell_x := table_x + f32(ci) * col_w
		// Left border
		ctx.fill_rect(Rect{cell_x, ly, 1, line.height}, border_col)

		if ci < cells.len {
			cell := cells[ci]
			cell_text := md_spans_to_plain(cell.spans)
			tw := ctx.measure_text_with_font(cell_text, font).x
			mut tx := cell_x + md_table_cell_pad_h
			align := if ci < block.table_aligns.len { block.table_aligns[ci] } else { MdAlign.left }
			if align == .center {
				tx = cell_x + (col_w - tw) * 0.5
			} else if align == .right {
				tx = cell_x + col_w - tw - md_table_cell_pad_h
			}
			ty := ly + (line.height - fh) * 0.5
			ctx.draw_text_with_font(cell_text, tx, ty, text_col, font)
		}
	}
	// Right border
	right_x := table_x + f32(ncols) * col_w
	ctx.fill_rect(Rect{right_x, ly, 1, line.height}, border_col)
	// Bottom border
	ctx.fill_rect(Rect{table_x, ly + line.height - 1, vp.w - md.pad * 2, 1}, border_col)
	// Separator after header
	if is_header {
		ctx.fill_rect(Rect{table_x, ly + line.height - 1, vp.w - md.pad * 2, 2}, border_col)
	}
}

// md_spans_to_plain склеивает text всех спанов (форматирование теряется).
fn md_spans_to_plain(spans []MdSpan) string {
	mut s := ''
	for span in spans {
		s += span.text
	}
	return s
}

// draw_image_block рисует отдельный блок-картинку (логика как у draw_inline_image, но с выравниванием самой картинки image_img_align по ширине области и без reflow по строке). Высота области под картинку без масштаба - не больше md_image_max_h.
fn (mut md MarkdownView) draw_image_block(block MdBlock, ly f32, ox f32, vp Rect, mut ctx RenderContext) {
	avail_w_d := vp.w - md.pad * 2
	cap_font_d := ctx.get_font(.italic, md.font_size)
	// target_w for caption wrap: apply scale if set, else full avail
	target_w_d := if block.image_scale > 0 { avail_w_d * block.image_scale } else { avail_w_d }
	caption_h := md_caption_height(block.image_alt, ctx, cap_font_d, target_w_d)
	img_area_h := md_image_max_h

	path := md.image_path(block.image_url)

	if !os.exists(path) {
		font := ctx.get_font(.italic, md.font_size)
		alt := if block.image_alt.len > 0 {
			'[Image: ${block.image_alt}]'
		} else {
			'[Image: ${block.image_url}]'
		}
		ctx.draw_text_with_font(alt, md.bounds.x + md.pad + 8, ly + 8,
			md.eff_text(ctx).with_alpha(180), font)
		return
	}

	tex := md.image_texture(path, ctx)

	if unsafe { tex == nil } {
		return
	}

	mut tw_f2 := f32(0)
	mut th_f2 := f32(0)
	C.SDL_GetTextureSize(tex, &tw_f2, &th_f2)
	tw := int(tw_f2)
	th := int(th_f2)

	if tw <= 0 || th <= 0 {
		return
	}

	// cache image dimensions for accurate layout; trigger re-layout on first load
	if _ := md.image_size_cache[path] {
	} else {
		md.image_size_cache[path] = [tw, th]!
		if block.image_scale > 0 {
			md.dirty = true
		}
	}

	// image_scale > 0 means explicit percentage; 0 means fit to available width
	target_w := target_w_d
	mut dw := f32(tw)
	mut dh := f32(th)
	// scale to target width (up or down)
	if dw != target_w {
		s := target_w / dw
		dw = target_w
		dh = dh * s
	}
	// clamp height only when no explicit scale (auto-fit mode)
	if block.image_scale <= 0 && dh > img_area_h {
		s := img_area_h / dh
		dh = img_area_h
		dw = dw * s
	}

	base_x := md.bounds.x + md.pad + ox
	img_x := match block.image_img_align {
		.center { base_x + (avail_w_d - dw) * 0.5 }
		.right { base_x + avail_w_d - dw }
		else { base_x }
	}

	dst := C.SDL_FRect{
		x: img_x
		y: ly
		w: dw
		h: dh
	}
	C.SDL_RenderTexture(ctx.renderer, tex, unsafe { nil }, &dst)

	// Multi-line caption below the image
	if block.image_alt.len > 0 && caption_h > 0 {
		font := cap_font_d
		fh := ctx.font_height_of(font)
		cap_lines := md_caption_wrap(block.image_alt, ctx, font, dw)
		caption_color := md.eff_caption(ctx)
		for ci, cl in cap_lines {
			cap_y := ly + dh + f32(ci) * md_image_caption_line_h +
				(md_image_caption_line_h - fh) * 0.5
			tw_cap := ctx.measure_text_with_font(cl, font).x
			cap_x := match block.image_align {
				.center { img_x + (dw - tw_cap) * 0.5 }
				.right { img_x + dw - tw_cap }
				else { img_x }
			}

			ctx.draw_text_with_font(cl, cap_x, cap_y, caption_color, font)
		}
	}
}

// ═══════════════════════════════════════════════════════
// Events
// ═══════════════════════════════════════════════════════

// handle_event: true - событие поглощено. В режиме .source всё делегируется CodeEditor. В preview приоритет: перетаскивание бегунков
// (vsb/hsb) -> mouse_move (hover ссылок и кнопок копирования, курсор-«рука», колбэк on_link_hover, таймер подсказки) ->
// mouse_down (бегунки, кнопка копирования -> буфер обмена, ссылка -> on_link_click или handle_link_click; любой клик внутри
// виджета поглощается) -> колесо (Ctrl - зум шрифта, Shift/wheel_x - горизонтально, иначе вертикально) -> клавиши (Ctrl +/-/0,
// стрелки, PageUp/PageDown, Home/End; только при hovered). Hit-test идёт по спискам md.links / md.copy_btns предыдущего draw().
pub fn (mut md MarkdownView) handle_event(event &GuiEvent, app &App) bool {
	if !md.visible || !md.enabled {
		return false
	}

	if md.mode == .source {
		if unsafe { md.editor != nil } {
			mut ce := md.editor
			ce.bounds = md.bounds.shrunk(2)
			return ce.handle_event(event, app)
		}
		return false
	}

	if md.vsb_dragging {
		match event.typ {
			.mouse_move {
				vp_vsb := md.viewport()
				thumb_h := max_f32(20, vp_vsb.h * (vp_vsb.h / md.total_h))
				drag_range := vp_vsb.h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - md.vsb_drag_start_y
				ms := md.max_scroll()
				md.scroll_y = clamp_f32(md.vsb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					md.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	if md.hsb_dragging {
		match event.typ {
			.mouse_move {
				vp_hsb := md.viewport()
				thumb_w := max_f32(20, vp_hsb.w * (vp_hsb.w / md.total_w))
				drag_range := vp_hsb.w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - md.hsb_drag_start_x
				ms := md.max_scroll_x()
				md.scroll_x = clamp_f32(md.hsb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					md.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			md.hovered = md.bounds.contains(event.mouse_x, event.mouse_y)

			prev_url := md.hovered_link_url
			md.hovered_link_idx = -1
			md.hovered_link_url = ''
			md.hovered_copy_idx = -1
			if md.hovered {
				for i, btn in md.copy_btns {
					if event.mouse_x >= btn.x && event.mouse_x <= btn.x + btn.w
						&& event.mouse_y >= btn.y && event.mouse_y <= btn.y + btn.h {
						md.hovered_copy_idx = i
						break
					}
				}
				for i, link in md.links {
					if event.mouse_x >= link.x && event.mouse_x <= link.x + link.w
						&& event.mouse_y >= link.y && event.mouse_y <= link.y + link.h {
						md.hovered_link_idx = i
						md.hovered_link_url = link.url
						break
					}
				}
				if md.hovered_link_idx >= 0 || md.hovered_copy_idx >= 0 {
					cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_hand)
					C.SDL_SetCursor(cursor)
				} else {
					cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
					C.SDL_SetCursor(cursor)
				}

				if md.has_vsb() {
					track, _ := md.vsb_rects()
					md.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
				if md.has_hsb() {
					track, _ := md.hsb_rects()
					md.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
			} else {
				md.vsb_hovered = false
				md.hsb_hovered = false
			}

			// on_link_hover callback + tooltip timer
			if md.hovered_link_url != prev_url {
				if md.on_link_hover != unsafe { nil } {
					md.on_link_hover(md.hovered_link_url)
				}
				if md.hovered_link_url.len > 0 {
					md.link_hover_start = C.SDL_GetTicks()
					md.link_tooltip_showing = false
				} else {
					md.link_hover_start = 0
					md.link_tooltip_showing = false
				}
			}
			return md.hovered
		}
		.mouse_down {
			md.link_tooltip_showing = false
			if event.mouse_btn == .left && md.hovered {
				if md.has_vsb() {
					_, thumb := md.vsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						md.vsb_dragging = true
						md.vsb_drag_start_y = event.mouse_y
						md.vsb_drag_start_scroll = md.scroll_y
						return true
					}
				}
				if md.has_hsb() {
					_, thumb := md.hsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						md.hsb_dragging = true
						md.hsb_drag_start_x = event.mouse_x
						md.hsb_drag_start_scroll = md.scroll_x
						return true
					}
				}

				if md.hovered_copy_idx >= 0 && md.hovered_copy_idx < md.copy_btns.len {
					btn := md.copy_btns[md.hovered_copy_idx]
					if btn.block_idx >= 0 && btn.block_idx < md.blocks.len {
						app.set_clipboard(md.blocks[btn.block_idx].code_text)
						md.copied_block_idx = btn.block_idx
						md.copied_at = C.SDL_GetTicks()
					}
					return true
				}

				if md.hovered_link_idx >= 0 && md.hovered_link_idx < md.links.len {
					link := md.links[md.hovered_link_idx]
					url := md.resolve_url(link.url)
					if url.starts_with('#') {
						md.scroll_to_anchor(url[1..])
					} else if md.on_link_click != unsafe { nil } {
						md.on_link_click(link.url)
					} else {
						md.handle_link_click(link.url)
					}
					return true
				}
				return true
			}
		}
		.mouse_wheel {
			if !md.wheel {
				return false
			}
			if !md.hovered {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if !md.bounds.contains(mx, my) {
				return false
			}
			// Ctrl+wheel → font zoom
			if event.ctrl() && event.wheel_y != 0 {
				if unsafe { ctx_ptr != nil } {
					if event.wheel_y > 0 {
						return md.zoom_in_font(ctx_ptr)
					}
					return md.zoom_out_font(ctx_ptr)
				}
				return false
			}
			// horizontal scroll: Shift+wheel_y or wheel_x
			if event.wheel_x != 0 || (event.shift() && event.wheel_y != 0) {
				wheel := if event.wheel_x != 0 { event.wheel_x } else { -event.wheel_y }
				old_x := md.scroll_x
				md.scroll_x += wheel * md.scroll_speed
				md.scroll_x = clamp_f32(md.scroll_x, 0, md.max_scroll_x())
				if md.scroll_x != old_x {
					return true
				}
			}
			old := md.scroll_y
			md.scroll_y -= event.wheel_y * md.scroll_speed
			md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
			return md.scroll_y != old
		}
		.key_down {
			if !md.hovered {
				return false
			}
			if event.ctrl() {
				if event.keycode == int(`+`) || event.keycode == int(`=`) {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						return md.zoom_in_font(ctx_ptr)
					}
					return false
				}
				if event.keycode == int(`-`) {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						return md.zoom_out_font(ctx_ptr)
					}
					return false
				}
				if event.keycode == int(`0`) {
					return md.reset_font_size()
				}
			}
			match event.keycode {
				sdl_k_up {
					md.scroll_y -= md.scroll_speed
					md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
					return true
				}
				sdl_k_down {
					md.scroll_y += md.scroll_speed
					md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
					return true
				}
				sdl_k_left {
					md.scroll_x -= md.scroll_speed
					md.scroll_x = clamp_f32(md.scroll_x, 0, md.max_scroll_x())
					return true
				}
				sdl_k_right {
					md.scroll_x += md.scroll_speed
					md.scroll_x = clamp_f32(md.scroll_x, 0, md.max_scroll_x())
					return true
				}
				else {}
			}

			if tv_is_pageup_key(event.keycode, event.scancode) {
				md.scroll_y -= md.bounds.h * 0.9
				md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
				return true
			}
			if tv_is_pagedown_key(event.keycode, event.scancode) {
				md.scroll_y += md.bounds.h * 0.9
				md.scroll_y = clamp_f32(md.scroll_y, 0, md.max_scroll())
				return true
			}
			if is_home_key(event.keycode, event.scancode) {
				md.scroll_y = 0
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				md.scroll_y = md.max_scroll()
				return true
			}
		}
		else {}
	}

	return false
}

// ═══════════════════════════════════════════════════════
// Font zoom (Ctrl+= / Ctrl+- / Ctrl+0)
// ═══════════════════════════════════════════════════════

// resolve_font_size returns the concrete font size currently in use,
// materializing the context default when md.font_size == 0.
fn (md &MarkdownView) resolve_font_size(ctx &RenderContext) int {
	if md.font_size > 0 {
		return md.font_size
	}
	if ctx.fonts.size > 0 {
		return ctx.fonts.size
	}
	return 14
}

// capture_base_font_size remembers the original size on the first zoom action.
fn (mut md MarkdownView) capture_base_font_size(ctx &RenderContext) {
	if md.base_font_size <= 0 {
		md.base_font_size = md.resolve_font_size(ctx)
	}
}

// clamp_font_size clamps a size to the configured [min, max] range.
// clamp_font_size держит размер в [min_font_size, max_font_size] (с защитой от некорректных границ).
fn (md &MarkdownView) clamp_font_size(sz int) int {
	mut lo := md.min_font_size
	mut hi := md.max_font_size
	if lo < 1 { lo = 1 }
	if hi < lo { hi = lo }
	if sz < lo { return lo }
	if sz > hi { return hi }
	return sz
}

// zoom_in_font/zoom_out_font: шаг font_size_step от текущего (фактического) размера; true - размер изменился (раскладка помечается dirty). Первый вызов запоминает исходный размер для сброса.
pub fn (mut md MarkdownView) zoom_in_font(ctx &RenderContext) bool {
	md.capture_base_font_size(ctx)
	cur := md.resolve_font_size(ctx)
	step := if md.font_size_step > 0 { md.font_size_step } else { md_default_font_step }
	new_sz := md.clamp_font_size(cur + step)
	if new_sz == md.font_size {
		return false
	}
	md.font_size = new_sz
	md.dirty = true
	return true
}

pub fn (mut md MarkdownView) zoom_out_font(ctx &RenderContext) bool {
	md.capture_base_font_size(ctx)
	cur := md.resolve_font_size(ctx)
	step := if md.font_size_step > 0 { md.font_size_step } else { md_default_font_step }
	new_sz := md.clamp_font_size(cur - step)
	if new_sz == md.font_size {
		return false
	}
	md.font_size = new_sz
	md.dirty = true
	return true
}

// reset_font_size возвращает размер, запомненный при первом зуме (Ctrl+0); если зума не было - размер по умолчанию (0). true - что-то изменилось.
pub fn (mut md MarkdownView) reset_font_size() bool {
	if md.base_font_size <= 0 {
		// nothing to reset to — set 0 so the context default is used
		if md.font_size == 0 {
			return false
		}
		md.font_size = 0
		md.dirty = true
		return true
	}
	if md.font_size == md.base_font_size {
		return false
	}
	md.font_size = md.base_font_size
	md.dirty = true
	return true
}

// set_font_size: sz <= 0 - размер по умолчанию контекста; иначе размер зажимается в границы. Если исходный размер ещё не запомнен, запоминает его как базовый.
pub fn (mut md MarkdownView) set_font_size(sz int) {
	if sz <= 0 {
		md.font_size = 0
		md.dirty = true
		return
	}
	clamped := md.clamp_font_size(sz)
	if md.base_font_size <= 0 {
		md.base_font_size = clamped
	}
	if md.font_size != clamped {
		md.font_size = clamped
		md.dirty = true
	}
}

pub fn (md &MarkdownView) get_font_size() int {
	return md.font_size
}

// set_min_font_size/set_max_font_size/set_font_size_step: значения < 1 игнорируются; границы взаимно подтягиваются, текущий размер приводится в диапазон.
pub fn (mut md MarkdownView) set_min_font_size(sz int) {
	if sz < 1 {
		return
	}
	md.min_font_size = sz
	if md.max_font_size < md.min_font_size {
		md.max_font_size = md.min_font_size
	}
	if md.font_size > 0 {
		new_sz := md.clamp_font_size(md.font_size)
		if new_sz != md.font_size {
			md.font_size = new_sz
			md.dirty = true
		}
	}
}

pub fn (md &MarkdownView) get_min_font_size() int {
	return md.min_font_size
}

pub fn (mut md MarkdownView) set_max_font_size(sz int) {
	if sz < 1 {
		return
	}
	md.max_font_size = sz
	if md.min_font_size > md.max_font_size {
		md.min_font_size = md.max_font_size
	}
	if md.font_size > 0 {
		new_sz := md.clamp_font_size(md.font_size)
		if new_sz != md.font_size {
			md.font_size = new_sz
			md.dirty = true
		}
	}
}

pub fn (md &MarkdownView) get_max_font_size() int {
	return md.max_font_size
}

pub fn (mut md MarkdownView) set_font_size_step(step int) {
	if step < 1 {
		return
	}
	md.font_size_step = step
}

pub fn (md &MarkdownView) get_font_size_step() int {
	return md.font_size_step
}

// ═══════════════════════════════════════════════════════
// Cleanup
// ═══════════════════════════════════════════════════════

// cleanup освобождает SDL-текстуры картинок и кэши. Безопасна в любой момент teardown: текстура,
// чей рендерер уже уничтожен (SDL освободил её вместе с ним), повторно не освобождается -
// см. MdImageTexture и PROJECT.md, «Время жизни SDL-текстур». Повторный вызов ничего не делает.
// Мост (vgui_destroy) зовёт её при уничтожении виджета.
pub fn (mut md MarkdownView) cleanup() {
	for _, entry in md.image_cache {
		entry.destroy()
	}
	md.image_cache = map[string]MdImageTexture{}
	md.image_size_cache = map[string][2]int{}
}
