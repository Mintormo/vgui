module vgui

// Файл node_body.v: своё содержимое в теле ноды - область под строками сокетов, которую рисует
// приложение (превью картинки, график сигнала, цвет результата).
//
// Место задаёт тип (NodeTypeDef.body_height, единицы холста) - высота модели его учитывает
// (content_height), поэтому карточка не бывает меньше. Если ноду растянуть по высоте, область
// растёт вместе с ней (превью удобно увеличивать). Рисует функция, повешенная на тип ноды:
// NodeEditor.set_body_painter(type_id, f). Она получает экранный прямоугольник области (уже с
// учётом зума и прокрутки) и рисует примитивами RenderContext - как и сам редактор, без SDL
// (PROJECT.md, «Бэкенд рисования»). Рисование обрезается по области. Ввода у области нет:
// нажатие по ней - как по телу ноды (выделить и тащить).
// Раздел PROJECT.md - «NodeEditor: редактор графа из нод», «Своё содержимое ноды».

// NodeBodyPainter - рисование области ноды: контекст, id ноды, прямоугольник области на экране.
pub type NodeBodyPainter = fn (mut ctx RenderContext, node int, r Rect)

// set_body_painter - рисовать область тела нод типа type_id функцией f (nil - убрать). Тип должен
// задавать body_height > 0, иначе места нет и функция не зовётся. Замыкание приложение передаёт
// через локальную переменную (обход vlang/v#28795, PROJECT.md, «Компилятор V»).
pub fn (mut ne NodeEditor) set_body_painter(type_id string, f NodeBodyPainter) {
	widget_changed()
	if isnil(f) {
		ne.body_painters.delete(type_id)
		return
	}
	ne.body_painters[type_id] = f
}

// body_rect - область тела ноды на холсте: от низа строк сокетов до нижнего поля карточки (с
// ростом карточки растёт и она). Пустой Rect - у типа нет места или нода свёрнута.
pub fn (ne &NodeEditor) body_rect(n &GraphNode) Rect {
	t := ne.graph.types[n.type_id] or { return Rect{} }
	if n.collapsed || t.body_height <= 0 {
		return Rect{}
	}
	top := ne_row_y(n, ne.graph.row_count(n))
	bottom := n.y + ne.graph.height_of(n) - ne_pad_bottom
	return Rect{n.x + ne_field_inset, top + 2, ne.graph.width_of(n) - ne_field_inset * 2, bottom -
		top - 2}
}

// draw_body - позвать функцию рисования области, обрезав её по области (и по самому редактору:
// push_clip пересекает с текущим отсечением).
fn (ne &NodeEditor) draw_body(n &GraphNode, mut ctx RenderContext) {
	painter := ne.body_painters[n.type_id] or { return }
	br := ne.body_rect(n)
	if br.w <= 0 || br.h <= 0 {
		return
	}
	r := ne.screen_rect(br)
	ctx.push_clip(r)
	painter(mut ctx, n.id, r)
	ctx.pop_clip()
}
