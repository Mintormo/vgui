module vgui

// Бокс измеряет ребёнка с явным min: (LayoutParams) по зажатому размеру - так же, как потом его
// раскладывает. Раньше `add(w, min: 80)` у виджета с естественной высотой 32 просил у родителя
// 32, а получал 80 и вылезал на соседей (общий Sparkline примера 65 залезал под вкладки).
fn test_box_measure_respects_child_min() {
	mut t := new_test_ui(width: 300, height: 300)!
	mut inner := create_vbox_fill()
	inner.set_padding(0)
	inner.set_spacing(0)
	mut s := sparkline() // естественная высота 32
	inner.add(s, min: 80)
	mut below := label('под ним')
	mut root := create_vbox_fill()
	root.set_padding(0)
	root.set_spacing(0)
	root.add(inner)
	root.add(below)
	t.add(root)
	assert inner.measure(t.win.ctx).h >= 80
	assert s.bounds.h == 80
	// соседа ниже не перекрывает
	assert below.bounds.y >= s.bounds.y + s.bounds.h
	t.close()
}
