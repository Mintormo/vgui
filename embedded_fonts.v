module vgui

// Default fonts embedded into libvgui at compile time.
// Used when no explicit font path is given to init_fonts.

const embedded_regular_ttf = $embed_file('assets/fonts/Roboto-Regular.ttf')
const embedded_italic_ttf = $embed_file('assets/fonts/Roboto-Italic.ttf')
const embedded_bold_italic_ttf = $embed_file('assets/fonts/Roboto-BoldItalic.ttf')
const embedded_mono_ttf = $embed_file('assets/fonts/RobotoMono-Regular.ttf')
const embedded_mono_bold_ttf = $embed_file('assets/fonts/RobotoMono-Bold.ttf')

pub fn embedded_regular_font() (voidptr, int) {
	return embedded_regular_ttf.data(), embedded_regular_ttf.len
}

pub fn embedded_italic_font() (voidptr, int) {
	return embedded_italic_ttf.data(), embedded_italic_ttf.len
}

pub fn embedded_bold_italic_font() (voidptr, int) {
	return embedded_bold_italic_ttf.data(), embedded_bold_italic_ttf.len
}

pub fn embedded_mono_font() (voidptr, int) {
	return embedded_mono_ttf.data(), embedded_mono_ttf.len
}

pub fn embedded_mono_bold_font() (voidptr, int) {
	return embedded_mono_bold_ttf.data(), embedded_mono_bold_ttf.len
}
