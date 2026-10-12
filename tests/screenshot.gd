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
		_main.world_view.focus_cell(Vector2i(_main._home.x, 1200))
		_main.camera.zoom = Vector2(0.6, 0.6)
		_reveal_area(Vector2i(_main._home.x, 1200), 40, 50)
	if _frame == 360:
		_shot("deep_revealed")
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
	colony.create_project(T, Rect2i(x0, s, 1, 14))
	colony.create_project(R, Rect2i(x0 + 1, s + 3, 7, 3))
	colony.create_project(T, Rect2i(x0 - 9, s + 9, 9, 2))
	colony.create_project(R, Rect2i(x0 + 1, s + 10, 5, 4))
	colony.create_project(R, Rect2i(x0 + 8, s - 3, 6, 3))
	colony.advance_offline(100000.0)
	# Новая стройка в процессе — чтобы видеть жителей за работой.
	colony.create_project(T, Rect2i(x0 + 8, s + 4, 8, 2))
	for x in range(x0 - 30, x0 + 30):
		if world.feature_at(x) != WorldGen.FEATURE_NONE and (x % 2 == 0):
			world.set_feature_mark(x, true)
	for i in 40:
		colony.update(1.0)
	_main.world_view.focus_cell(Vector2i(x0 + 2, s - 2))
	_main.camera.zoom = Vector2(1.0, 1.0)


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
