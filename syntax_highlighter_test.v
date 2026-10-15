module vgui

// Блочные комментарии в подсветке (аудит 2026-10, 5.4): KeywordHighlighter учитывает
// /* ... */ через строки, Python-подсветчик '/*' комментарием не считает.
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
	assert t1.last().color == h.comment_color
	t2, in2 := h.tokenize_state('middle', in1)
	assert in2 && t2[0].color == h.comment_color
	t3, in3 := h.tokenize_state('end */ int b;', in2)
	assert !in3
	assert t3[0].text == 'end */' && t3[0].color == h.comment_color
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
	assert e.line_tokens(1, 'b')[0].color == h.comment_color
	toks := e.line_tokens(2, '*/ int x;')
	assert toks[0].color == h.comment_color
	assert toks.last().color != h.comment_color
	// правка текста сбрасывает состояния
	e.set_text('int a;\nb')
	assert e.line_tokens(1, 'b')[0].color != h.comment_color
}
