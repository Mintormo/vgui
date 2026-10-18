module vgui

// Миникарта холста без SDL: когда она есть, где стоит, куда переносит вид.

fn nav_canvas() &Canvas {
	mut c := canvas(400, 200)
	c.bounds = Rect{0, 0, 300, 200}
	c.navigator = true
	return c
}

fn test_nav_hidden_when_fit_or_off() {
	mut c := nav_canvas()
	// Вписано - всё и так видно
	assert c.nav_rect().w == 0
	c.set_zoom(2)
	assert c.nav_rect().w > 0
	c.navigator = false
	assert c.nav_rect().w == 0
	// Увеличено, но целиком помещается - не нужна
	c.navigator = true
	c.set_zoom(0.5)
	assert c.nav_rect().w == 0
}

fn test_nav_rect_aspect_and_corner() {
	mut c := nav_canvas()
	c.set_zoom(2)
	nr := c.nav_rect()
	vp := c.viewport()
	// Пропорции буфера 2:1; не больше половины видимой части
	assert nr.w <= vp.h * 0.5 + 0.01 && nr.w <= c.navigator_size
	assert nr.w > nr.h - 0.01 && nr.w < 2 * nr.h + 0.01
	// Правый нижний угол видимой части с отступом
	assert nr.x + nr.w <= vp.x + vp.w - cv_nav_margin + 0.01
	assert nr.y + nr.h <= vp.y + vp.h - cv_nav_margin + 0.01
}

fn test_nav_center_moves_view() {
	mut c := nav_canvas()
	c.set_zoom(2)
	nr := c.nav_rect()
	// Правый нижний угол миникарты - прокрутка до упора
	c.nav_center(nr.x + nr.w, nr.y + nr.h)
	ms_x, ms_y := c.max_scroll()
	assert c.scroll_x == ms_x && c.scroll_y == ms_y
	// Левый верхний - в начало
	c.nav_center(nr.x, nr.y)
	assert c.scroll_x == 0 && c.scroll_y == 0
	// Середина - середина буфера в центре видимой части
	c.nav_center(nr.x + nr.w / 2, nr.y + nr.h / 2)
	vp := c.viewport()
	assert c.scroll_x == 200 * 2 - vp.w / 2
}
