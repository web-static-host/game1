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
		_main.hud._build_btn.button_pressed = true
		for pr in _main.colony.projects:
			if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.STORAGE:
				_main._select(null, pr)
	if _frame == 315:
		_shot("storage_panel")
		_main.hud._build_btn.button_pressed = false
		_main._select(_main.colony.units[1], null)
	if _frame == 325:
		_shot("unit_panel")
		_main._select(null, null)
		for x in range(_main._home.x - 30, _main._home.x + 30):
			if _main.world.feature_at(x) == WorldGen.FEATURE_TREE:
				_main._show_feature(x)
				break
	if _frame == 328:
		_shot("feature")
		_main.hud.hide_info()
		_main.hud._pick_tool(Hud.Mode.ROOM, "room", "Комната")
		var at: Vector2 = _main.get_viewport().get_visible_rect().size * 0.5 + Vector2(120, 20)
		_main._on_paint(at, true)
		_main._on_paint_end(at)
	if _frame == 332:
		_shot("placing")
		_main._to_look()
		var c: Vector2i = _main._home + Vector2i(4, 10)
		_main.world_view.focus_cell(c)
		_main.camera.zoom = Vector2(1.1, 1.1)
	if _frame == 335:
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
		_prepare_elements()
	if _frame == 470:
		_shot("elements")
		_main.hud._new_game.visible = true
	if _frame == 480:
		_shot("new_game")
		_main.hud._new_game.visible = false
		_main.colony.research.done.append("bricks")
		_main.colony.research.start("electricity")
		_main.colony.research.progress = 25.0
		_main._show_science()
	if _frame == 490:
		_shot("science")
		_main.hud.hide_info()
		for pr in _main.colony.projects:
			if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.FARM:
				_main.colony.assign_work(_main.colony.units[0], pr)
				_main._select(null, pr)
				break
	if _frame == 500:
		_shot("farm_panel")
		for pr in _main.colony.projects:
			if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.FARM:
				_main._pick_worker(pr)
				break
	if _frame == 510:
		_shot("pick_worker")
		_main._pick_partner(_main.colony.units[1])
	if _frame == 520:
		_shot("pick_partner")
		return true
	return false


## Подземелье со стихиями: затопленный штрек, лава, облако метана.
func _prepare_elements() -> void:
	var colony: Colony = _main.colony
	var w: WorldData = _main.world
	var o := Vector2i(_main._home.x + 60, w.gen.surface_y(_main._home.x + 60) + 30)
	for y in range(o.y - 2, o.y + 14):
		for x in range(o.x - 2, o.x + 34):
			w.set_material(x, y, Mat.GRANITE)
	for y in range(o.y, o.y + 10):
		w.set_dug(o.x + 3, y)
	for x in range(o.x + 3, o.x + 30):
		for y in [o.y + 8, o.y + 9]:
			w.set_dug(x, y)
	for y in range(o.y, o.y + 4):
		for x in range(o.x + 20, o.x + 28):
			w.set_dug(x, y)
	for y in range(o.y + 4, o.y + 8):
		w.set_dug(o.x + 24, y)
	for x in range(o.x + 4, o.x + 14):
		w.set_fluid(x, o.y + 9, Mat.WATER)
		colony.elements.active[Vector2i(x, o.y + 9)] = true
	for x in range(o.x + 21, o.x + 24):
		w.set_fluid(x, o.y + 3, Mat.MAGMA)
		colony.elements.active[Vector2i(x, o.y + 3)] = true
	for i in 6:
		colony.elements.release_gas(Vector2i(o.x + 3, o.y + 6 - i))
	for i in 8:
		colony.elements.update(0.5)
	colony.explored_max = maxi(colony.explored_max, o.x + 50)
	colony.deepest_y = maxi(colony.deepest_y, o.y + 20)
	_main.world_view.focus_cell(o + Vector2i(15, 5))
	_main.camera.zoom = Vector2(0.9, 0.9)


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
	var farm := colony.create_project(R, Rect2i(x0 + 1, s + 10, 7, 3), -1, "stone")
	var store := colony.create_project(R, Rect2i(x0 - 9, s + 6, 8, 3), -1, "clay")
	for u in colony.units:
		u.lifespan = 0.0 # для снимков — без старения
	colony.advance_offline(100000.0)
	colony.game_time = 0.0
	colony.inventory = {"wood": 300, "stone": 300, "clay": 100, "soil": 100, "food": 40}
	for pr in [[home, RoomType.HOME], [farm, RoomType.FARM], [store, RoomType.STORAGE]]:
		if pr[0] != null:
			colony.set_purpose(pr[0], pr[1])
	colony.advance_offline(5000.0)
	colony.inventory["food"] = 40
	colony.units[0].energy = 5.0
	# Новая стройка в процессе — чтобы видеть жителей за работой.
	colony.create_project(T, Rect2i(x0 + 8, s + 4, 8, 2))
	# Наземный дом, на который носят материалы (камня нет — плашка красная).
	colony.inventory = {"wood": 30, "food": 40}
	var gx := x0 + 14
	while world.gen.surface_y(gx) != world.gen.surface_y(gx + 5) or world.gen.surface_y(gx) != world.gen.surface_y(gx + 2):
		gx += 1
	colony.create_project(R, Rect2i(gx, world.gen.surface_y(gx) - 3, 5, 3), 2, "stone")
	if home != null:
		home.wear = 0.82
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
