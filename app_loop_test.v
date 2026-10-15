module vgui

// Бюджет кадра главного цикла по AppConfig.target_fps (аудит 2026-10, 2.3:
// настройка раньше не читалась, кадр был жёстко 16 мс). SDL не нужен.
//
// Запуск (из корня vgui): v test app_loop_test.v

fn test_frame_budget_follows_target_fps() {
	assert frame_budget_ms(60) == 16
	assert frame_budget_ms(30) == 33
	assert frame_budget_ms(120) == 8
	// вне 1..1000 - зажимается, без деления на ноль
	assert frame_budget_ms(0) == 1000
	assert frame_budget_ms(-5) == 1000
	assert frame_budget_ms(5000) == 1
}
