module vgui

// Lucide icon font (ISC license, https://lucide.dev), embedded into libvgui
// at compile time so the Icon widget works without shipping a font file
// alongside the shared library. See icon_names.v for the name→codepoint map.

const embedded_icon_ttf = $embed_file('assets/lucide.ttf')

pub fn embedded_icon_font() (voidptr, int) {
	return embedded_icon_ttf.data(), embedded_icon_ttf.len
}
