module vgui

// Блочные комментарии в подсветке (аудит 2026-10, 5.4): KeywordHighlighter учитывает
// /* ... */ через строки, Python-подсветчик '/*' комментарием не считает.
// Цвета под тему (23.10.2026): токен несёт вид (kind), без своего цвета цвет берётся из
// палитры под фон - на светлом фоне обычный текст раньше был светло-серым и не читался.
//
// Запуск (из корня vgui): v test syntax_highlighter_test.v

fn joined(tokens []SyntaxToken) string {
	return tokens.map(it.text).join('')
}

fn test_block_comment_spans_lines() {
	h := c_highlighter()
	t1, in1 := h.tokenize_state('int a; /* start', false)
	assert in1
	assert joined(t1) == 'int a; /* start'
	assert t1.last().kind == .comment
	t2, in2 := h.tokenize_state('middle', in1)
	assert in2 && t2[0].kind == .comment
	t3, in3 := h.tokenize_state('end */ int b;', in2)
	assert !in3
	assert t3[0].text == 'end */' && t3[0].kind == .comment
	assert joined(t3) == 'end */ int b;'
	// внутри строкового литерала - не комментарий
	_, in4 := h.tokenize_state('s = "/*";', false)
	assert !in4
	// однострочный блок
	t5, in5 := h.tokenize_state('a /* x */ b', false)
	assert !in5 && joined(t5) == 'a /* x */ b'
}

fn test_python_has_no_block_comments() {
	h := python_highlighter()
	_, in_block := h.tokenize_state('x = 1 /* 2', false)
	assert !in_block
}

fn test_code_editor_carries_state() {
	mut e := code_editor()
	h := c_highlighter()
	e.set_highlighter(h)
	e.set_text('/* a\nb\n*/ int x;')
	assert e.line_tokens(1, 'b')[0].kind == .comment
	toks := e.line_tokens(2, '*/ int x;')
	assert toks[0].kind == .comment
	assert toks.last().kind != .comment
	// правка текста сбрасывает состояния
	e.set_text('int a;\nb')
	assert e.line_tokens(1, 'b')[0].kind != .comment
}

fn test_token_kinds() {
	h := v_highlighter()
	toks := h.tokenize("fn f(n int) { println('x') } // c 1")
	kinds := toks.filter(it.text.trim_space() != '').map('${it.text}:${it.kind}')
	assert 'fn:keyword' in kinds
	assert 'int:type_name' in kinds
	assert 'println:builtin' in kinds
	assert "'x':string_lit" in kinds
	assert '// c 1:comment' in kinds
	assert 'f:plain' in kinds
	assert '1' !in kinds.map(it.all_before(':')) // число внутри комментария - часть комментария
	n := h.tokenize('x := 42')
	assert n.last().kind == .number
}

// Палитра выбирается по яркости фона, свой цвет токена её перекрывает.
fn test_palette_follows_background() {
	dark := syntax_palette_for(Color{30, 30, 30, 255})
	light := syntax_palette_for(Color{255, 255, 255, 255})
	assert dark.keyword == syntax_palette_dark().keyword
	assert light.keyword == syntax_palette_light().keyword
	// обычный текст светлой палитры тёмный, тёмной - светлый
	assert light.plain.r < 128 && dark.plain.r > 128
	// по умолчанию KeywordHighlighter своих цветов не задаёт
	h := v_highlighter()
	tok := h.tokenize('fn')[0]
	assert tok.color.a == 0
	assert tok.resolve_color(light) == light.keyword
	assert tok.resolve_color(dark) == dark.keyword
	// заданный цвет вида перекрывает палитру
	mut h2 := v_highlighter()
	h2.keyword_color = Color{1, 2, 3, 255}
	assert h2.tokenize('fn')[0].resolve_color(light) == Color{1, 2, 3, 255}
}

// Редактор берёт палитру под свой фон, обычный текст - цветом текста темы.
fn test_code_editor_palette() {
	mut ctx := RenderContext{
		theme: light_theme()
	}
	e := code_editor()
	pal := e.syntax_palette(ctx)
	assert pal.keyword == syntax_palette_light().keyword
	assert pal.plain == ctx.theme.eff_ce_text()
	ctx.theme = dark_theme()
	assert e.syntax_palette(ctx).keyword == syntax_palette_dark().keyword
}
