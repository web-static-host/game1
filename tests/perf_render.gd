extends SceneTree
## Замер отрисовки настоящей игры на снимке большой колонии (tests/fixtures/big_colony.json):
## время кадра и сколько вызовов видеокарты, объектов и треугольников уходит за кадр — у базы,
## в глубине и на ×10; потом — без каждого слоя по очереди (видно, кто сколько стоит).
## Нужен дисплей:  xvfb-run godot --path . --resolution 1280x720 -s res://tests/perf_render.gd
## (Без видеокарты время кадра — программная отрисовка; на телефоне важнее число вызовов.)

const PHASE := 120
var frames := 0
var main: Node
var marks: Array[float] = []
var calls: Array[float] = []
var objs: Array[float] = []
var prims: Array[float] = []
var last := 0
var step := 0
var tests := []


func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/big_colony.json"))
	data["saved_at"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SaveSystem.DEFAULT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	change_scene_to_file("res://scenes/main.tscn")
	process_frame.connect(_tick)


func _chunks(v: bool) -> void:
	for k in main.world_view._views:
		main.world_view._views[k].visible = v


func _tick() -> void:
	frames += 1
	var now := Time.get_ticks_usec()
	if frames == 30:
		main = current_scene
		main._speed_idx = 0
		var wv = main.world_view
		var home: Vector2i = main.colony.home
		tests = [
			["у базы, ×1", func(): wv.focus_cell(home + Vector2i(0, -3)), func(): pass],
			["в глубине, ×1", func(): wv.focus_cell(home + Vector2i(0, 120)), func(): wv.focus_cell(home + Vector2i(0, -3))],
			["у базы, ×10", func(): main._speed_idx = 2, func(): main._speed_idx = 0],
			["без кусков карты", func(): _chunks(false), func(): _chunks(true)],
			["без построек", func(): wv.structures.visible = false, func(): wv.structures.visible = true],
			["без гавриков", func(): wv.units_layer.visible = false, func(): wv.units_layer.visible = true],
			["без темноты", func(): wv.light.visible = false, func(): wv.light.visible = true],
			["без интерфейса", func(): main.hud.visible = false, func(): main.hud.visible = true],
		]
		print("сцена                  кадр, мс   вызовов  объектов  треугольников")
	if frames > 40:
		marks.append((now - last) / 1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	last = now
	if frames >= 30 and (frames - 30) % PHASE == 0:
		if step > 0:
			var t: Array = tests[step - 1]
			print("%-22s %8.1f %9d %9d %13d" % [t[0], _avg(marks), _avg(calls), _avg(objs), _avg(prims)])
			t[2].call()
		if step >= tests.size():
			quit()
			return
		tests[step][1].call()
		marks.clear()
		calls.clear()
		objs.clear()
		prims.clear()
		step += 1


func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxi(1, a.size())
