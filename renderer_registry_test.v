module vgui

// Юнит-тест реестра живых рендереров (sdl3_window.v) и его ABA-защиты.
// SDL не трогаем — register/unregister работают с любыми ненулевыми
// указателями, поэтому используем фиктивные адреса.
//
// Запуск: v -enable-globals test vgui/renderer_registry_test.v

fn test_register_and_alive() {
	g_live_renderers = []LiveRenderer{}
	a := voidptr(0x1000)
	register_renderer(a)
	assert is_renderer_alive(a)
	gen := renderer_generation(a)
	assert gen != 0
	assert is_renderer_alive_gen(a, gen)
	unregister_renderer(a)
	assert !is_renderer_alive(a)
	assert renderer_generation(a) == 0
	assert !is_renderer_alive_gen(a, gen)
}

fn test_aba_address_reuse() {
	// Главный сценарий: новый рендерер получает адрес умершего.
	// Устаревший снимок (ptr, old_gen) обязан считаться мёртвым,
	// хотя голая проверка по указателю сказала бы "жив".
	g_live_renderers = []LiveRenderer{}
	a := voidptr(0x2000)
	register_renderer(a)
	old_gen := renderer_generation(a)
	unregister_renderer(a) // окно умерло
	register_renderer(a) // новый рендерер по тому же адресу
	new_gen := renderer_generation(a)
	assert new_gen != old_gen // поколения монотонны, не переиспользуются
	assert is_renderer_alive(a) // по указателю — "жив" (в этом и была дыра)
	assert !is_renderer_alive_gen(a, old_gen) // устаревший снимок — мёртв
	assert is_renderer_alive_gen(a, new_gen) // актуальный снимок — жив
	unregister_renderer(a)
}

fn test_nil_and_zero_gen() {
	g_live_renderers = []LiveRenderer{}
	assert !is_renderer_alive(unsafe { nil })
	assert renderer_generation(unsafe { nil }) == 0
	// gen == 0 — "снимок не делался": всегда мёртв, даже для живого рендерера
	a := voidptr(0x3000)
	register_renderer(a)
	assert !is_renderer_alive_gen(a, 0)
	unregister_renderer(a)
	// unregister незарегистрированного / nil — no-op
	unregister_renderer(a)
	unregister_renderer(unsafe { nil })
}

fn test_multiple_live_renderers() {
	g_live_renderers = []LiveRenderer{}
	a := voidptr(0x4000)
	b := voidptr(0x5000)
	register_renderer(a)
	register_renderer(b)
	gen_a := renderer_generation(a)
	gen_b := renderer_generation(b)
	assert gen_a != gen_b
	unregister_renderer(a)
	assert !is_renderer_alive_gen(a, gen_a)
	assert is_renderer_alive_gen(b, gen_b) // сосед не задет
	unregister_renderer(b)
	assert g_live_renderers.len == 0
}
