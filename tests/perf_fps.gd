extends SceneTree
## Кадры настоящей игры на снимке большой колонии (см. tests/perf_big_colony.gd):
## по 300 кадров на ×1 и на ×20 — время кадра и сколько секунд игры прошло.
##   xvfb-run godot --path . -s res://tests/perf_fps.gd -- user://perf_555_55.json
## Сохранение игры (user://save.json) при этом заменяется снимком.

const PHASE := 300
var frames := 0
var main: Node
var marks: Array[float] = []
var last := 0
var gt0 := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var snap: String = args[0] if args.size() > 0 else "user://perf_555_55.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(snap))
	if typeof(data) != TYPE_DICTIONARY:
		print("нет снимка ", snap, " — сначала запустите tests/perf_big_colony.gd")
		quit()
		return
	# Без оффлайн-прогресса: как будто вышли только что.
	data["saved_at"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SaveSystem.DEFAULT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	change_scene_to_file("res://scenes/main.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	frames += 1
	var now := Time.get_ticks_usec()
	if frames == 30:
		main = current_scene
		var col: Colony = main.colony
		main.world_view.focus_cell(col.units[col.units.size() / 2].cell())
		main._speed_idx = 0
		gt0 = col.game_time
	if frames > 30:
		marks.append((now - last) / 1000.0)
	last = now
	if frames == 30 + PHASE:
		_report("×1")
		main._speed_idx = 3
	elif frames == 30 + PHASE * 2:
		_report("×20")
		quit()


func _report(name: String) -> void:
	var s := marks.duplicate()
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	var col: Colony = main.colony
	print("%s: гавриков %d, кадр средн %.1f мс (≈%.0f fps), p95 %.1f, max %.1f; игра шла ×%.1f" % [name, col.units.size(),
		sum / s.size(), 1000.0 / (sum / s.size()), s[int(s.size() * 0.95)], s[-1], (col.game_time - gt0) / (sum / 1000.0)])
	marks.clear()
	gt0 = col.game_time
