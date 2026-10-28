module vgui

// Темы macOS (современные и старые): номера C API 11..14 отдают именно их,
// основные цвета непрозрачные, текст контрастен фону.
fn brightness_255(c Color) int {
	return (int(c.r) * 54 + int(c.g) * 183 + int(c.b) * 19) >> 8
}

fn test_macos_themes_contrast() {
	for th in [macos_theme(), macos_dark_theme(), mac_os_x_aqua_theme(), mac_os_9_platinum_theme()] {
		for c in [th.bg, th.surface, th.panel_bg, th.text_primary, th.accent, th.button_bg,
			th.input_bg] {
			assert c.a == 255
		}
		d := brightness_255(th.bg) - brightness_255(th.text_primary)
		assert d > 150 || d < -150, 'текст неконтрастен фону'
		// Текст на акцентной кнопке читается
		da := brightness_255(th.accent) - brightness_255(th.accent_text)
		assert da > 60 || da < -60
	}
}
