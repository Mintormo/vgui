module vgui

import os

// FileDialog: сортировка по размеру (аудит 2026-10, 3.4) - размер читается один раз
// на файл, порядок равных по размеру сохраняется.
//
// Запуск (из корня vgui): v -enable-globals test file_dialog_sort_test.v

fn test_sort_by_size_is_stable() {
	dir := os.join_path(os.temp_dir(), 'vgui_fd_sort_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	for name, size in {
		'a.txt': 30
		'b.txt': 10
		'c.txt': 30
		'd.txt': 20
	} {
		os.write_file(os.join_path(dir, name), 'x'.repeat(size))!
	}
	mut asc := ['a.txt', 'b.txt', 'c.txt', 'd.txt']
	fd_sort_files_by_size(mut asc, dir, false)
	assert asc == ['b.txt', 'd.txt', 'a.txt', 'c.txt']
	mut desc := ['a.txt', 'b.txt', 'c.txt', 'd.txt']
	fd_sort_files_by_size(mut desc, dir, true)
	assert desc == ['a.txt', 'c.txt', 'd.txt', 'b.txt']
}
