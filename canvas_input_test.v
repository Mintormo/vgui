module vgui

// SDL-free checks of Canvas input mapping: mouse button codes in CanvasInputEvent
// and the default pan button. Getters exported to bindings are tested in vgui-capi.

fn test_mouse_btn_mapping() {
	assert mouse_btn_to_int(.left) == 1
	assert mouse_btn_to_int(.middle) == 2
	assert mouse_btn_to_int(.right) == 3
	assert mouse_btn_to_int(.none_) == 0
}

fn test_pan_button_default() {
	c := canvas(8, 8)
	// default pan mask = middle | right
	assert c.pan_buttons == cv_pan_middle | cv_pan_right
	assert c.wheel_zoom == true
	assert c.auto_fit == true
}
