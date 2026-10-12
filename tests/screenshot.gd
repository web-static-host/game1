extends SceneTree
## Делает скриншоты игры для проверки внешнего вида (нужен дисплей, напр. xvfb-run).
##   xvfb-run godot --path . -s res://tests/screenshot.gd -- <папка>

var _main: Node
var _frame := 0
var _out := "user://"
var _shots := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	# Чистый мир для воспроизводимости.
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		_prepare_base()
	if _frame == 300:
		_shot("colony")
		var c: Vector2i = _main._home + Vector2i(4, 10)
		_main.world_view.focus_cell(c)
		_main.camera.zoom = Vector2(1.1, 1.1)
	if _frame == 330:
		_shot("underground")
		for pr in _main.colony.projects:
			if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.HOME:
				_main._select(null, pr)
	if _frame == 345:
		_shot("room_panel")
		_main._select(null, null)
		_main.world_view.focus_cell(Vector2i(_main._home.x, 1200))
		_main.camera.zoom = Vector2(0.6, 0.6)
		_reveal_area(Vector2i(_main._home.x, 1200), 40, 50)
	if _frame == 360:
		_shot("deep_revealed")
		# Окно подтверждения стройки с выбором рабочих.
		var h: Vector2i = _main._home
		_main.world_view.focus_cell(h + Vector2i(22, 2))
		_main.camera.zoom = Vector2(1.0, 1.0)
		_main.mode = Hud.Mode.ROOM
		var sy: int = _main.world.gen.surface_y(h.x + 24) + 2
		_main.world_view.structures.preview = Rect2i(h.x + 24, sy, 6, 3)
		_main._on_paint_end(Vector2.ZERO)
	if _frame == 390:
		_shot("confirm")
		_main._clear_preview()
		_prepare_lake()
	if _frame == 430:
		_shot("lake")
		return true
	return false


func _prepare_base() -> void:
	var colony: Colony = _main.colony
	var world: WorldData = _main.world
	var x0: int = _main._home.x + 3
	var s := world.gen.surface_y(x0)
	colony.inventory = {"wood": 200, "stone": 200}
	var T := Project.Kind.TUNNEL
	var R := Project.Kind.ROOM
	colony.inventory = {"wood": 300, "stone": 300, "clay": 100, "soil": 100, "food": 40}
	colony.known_resources = {"wood": true, "stone": true, "clay": true}
	colony.create_project(T, Rect2i(x0, s, 1, 14))
	var home := colony.create_project(R, Rect2i(x0 + 1, s + 3, 7, 3), -1, "wood")
	colony.create_project(T, Rect2i(x0 - 9, s + 9, 9, 3))
	var farm := colony.create_project(R, Rect2i(x0 + 1, s + 10, 7, 4), -1, "stone")
	var store := colony.create_project(R, Rect2i(x0 - 9, s + 5, 8, 3), -1, "clay")
	colony.advance_offline(100000.0)
	colony.inventory = {"wood": 300, "stone": 300, "clay": 100, "soil": 100, "food": 40}
	for pr in [[home, RoomType.HOME], [farm, RoomType.FARM], [store, RoomType.STORAGE]]:
		if pr[0] != null:
			colony.set_purpose(pr[0], pr[1])
	colony.advance_offline(5000.0)
	colony.inventory["food"] = 40
	colony.units[0].energy = 5.0
	# Новая стройка в процессе — чтобы видеть жителей за работой.
	colony.create_project(T, Rect2i(x0 + 8, s + 4, 8, 2))
	for x in range(x0 - 30, x0 + 30):
		if world.feature_at(x) != WorldGen.FEATURE_NONE and (x % 2 == 0):
			world.set_feature_mark(x, true)
	for i in 40:
		colony.update(1.0)
	_main.world_view.focus_cell(Vector2i(x0 + 2, s - 2))
	_main.camera.zoom = Vector2(1.0, 1.0)


## Озеро недалеко: мостик через него и пристань, рыбаки, молодые деревья.
func _prepare_lake() -> void:
	var colony: Colony = _main.colony
	var w: WorldData = _main.world
	var best := {}
	for k in range(-6, 6):
		var l := w.gen._lake_of_segment(k)
		if l.is_empty() or int(l["w"]) > 14 or int(l["w"]) < 6:
			continue
		best = l
		break
	if best.is_empty():
		return
	var level: int = best["level"]
	var xs := []
	for x in range(int(best["cx"]) - int(best["w"]), int(best["cx"]) + int(best["w"])):
		if w.gen.surface_y(x) > level:
			xs.append(x)
	if xs.size() < 3:
		return
	var x0: int = xs[0] - 1
	var x1: int = xs[xs.size() - 1] + 1
	colony.home = Vector2i(x0 - 6, w.gen.surface_y(x0 - 6))
	for u in colony.units:
		u.pos = Vector2(x0 - 4, w.gen.surface_y(x0 - 4) - 1)
	colony.inventory = {"wood": 49, "stone": 40, "food": 10}
	var br := colony.create_project(Project.Kind.BRIDGE, Rect2i(x0, level - 1, x1 - x0 + 1, 1))
	colony.advance_offline(4000.0)
	if br != null:
		colony.demolish(br)
	colony.inventory = {"wood": 49, "stone": 40, "food": 10}
	colony.create_project(Project.Kind.PIER, Rect2i(x0, level - 1, mini(6, x1 - x0), 1))
	colony.advance_offline(4000.0)
	for i in 30:
		colony.grow_plants(Colony.PLANT_TICK * 10)
	colony.inventory["food"] = 0
	for i in 60:
		colony.update(1.0)
	_main.world_view.focus_cell(Vector2i((x0 + x1) / 2, level - 3))
	_main.camera.zoom = Vector2(0.9, 0.9)


## Открывает область (как будто там уже всё разведано) — для просмотра геологии.
func _reveal_area(center: Vector2i, rx: int, ry: int) -> void:
	var world: WorldData = _main.world
	for y in range(center.y - ry, center.y + ry):
		for x in range(center.x - rx, center.x + rx):
			world.reveal(x, y)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("скриншот: ", path)
