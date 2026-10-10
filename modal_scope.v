module vgui

// ─── Область модальности ───────────────────────────────────────────────
// Модальный диалог блокирует не всё приложение, а только своё дерево
// владения: родительское окно, его предков и остальные диалоги того же
// дерева. В многооконном приложении модальный диалог одного окна не
// должен гасить события второго, никак с ним не связанного (аудит 3.D).
//
// Логика вынесена в чистые функции над плоским списком (id окна, id
// родителя, признак активного модального блокера) — так её можно
// проверять тестами без SDL и окон (`modal_scope_test.v`).

// ModalScopeEntry — снимок одного диалога для разбора областей модальности.
struct ModalScopeEntry {
	// sdl_id окна самого диалога.
	wid u32
	// sdl_id окна-родителя; 0 — диалог создан без родителя.
	parent_id u32
	// true, если диалог сейчас открыт И модален, то есть является блокером.
	modal bool
}

// owner_root возвращает sdl_id корневого окна дерева владения, которому
// принадлежит `wid`. Для обычного окна это оно само, для диалога — окно,
// до которого доводит цепочка `parent_id`. Цепочка обходится с лимитом
// шагов, поэтому кольцо (диалог, ставший предком самого себя) не вешает
// обход, а просто обрывает его.
fn owner_root(entries []ModalScopeEntry, wid u32) u32 {
	mut cur := wid
	for _ in 0 .. entries.len + 1 {
		mut parent := u32(0)
		for e in entries {
			if e.wid == cur {
				parent = e.parent_id
				break
			}
		}
		if parent == 0 {
			return cur
		}
		cur = parent
	}
	return cur
}

// is_owned_by сообщает, лежит ли окно `wid` в поддереве окна `ancestor`
// (само окно предком себя не считается).
fn is_owned_by(entries []ModalScopeEntry, wid u32, ancestor u32) bool {
	mut cur := wid
	for _ in 0 .. entries.len + 1 {
		mut parent := u32(0)
		for e in entries {
			if e.wid == cur {
				parent = e.parent_id
				break
			}
		}
		if parent == 0 {
			return false
		}
		if parent == ancestor {
			return true
		}
		cur = parent
	}
	return false
}

// modal_blocker_index возвращает индекс диалога в `entries`, который должен
// перехватить событие окна `event_wid`, либо -1, если событие обрабатывается
// обычным путём. Диалоги просматриваются сверху вниз (с конца списка):
// выигрывает самый поздний подходящий модальный диалог.
fn modal_blocker_index(entries []ModalScopeEntry, event_wid u32) int {
	for i := entries.len - 1; i >= 0; i-- {
		e := entries[i]
		if !e.modal {
			continue
		}
		// Событие самого модального диалога — отдаём ему же.
		if e.wid == event_wid {
			return i
		}
		// Окно, открытое поверх модального диалога (например, его
		// собственный вложенный диалог), им не блокируется.
		if is_owned_by(entries, event_wid, e.wid) {
			continue
		}
		// Диалог без родителя модален для всего приложения — так вели
		// себя все модальные диалоги до появления областей модальности.
		if e.parent_id == 0 {
			return i
		}
		// Иначе блокируется только своё дерево владения.
		if owner_root(entries, event_wid) == owner_root(entries, e.wid) {
			return i
		}
	}
	return -1
}
