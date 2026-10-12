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
	if _frame == 40:
		_shot("surface")
		var c: Vector2i = _main._home + Vector2i(0, 25)
		_main.world_view.focus_cell(c)
		_main.camera.zoom = Vector2(0.8, 0.8)
	if _frame == 80:
		_shot("underground")
		_main.world_view.focus_cell(Vector2i(_main._home.x, 1200))
		_main.camera.zoom = Vector2(0.6, 0.6)
		_reveal_area(Vector2i(_main._home.x, 1200), 40, 50)
	if _frame == 120:
		_shot("deep_revealed")
		_main.world_view.focus_cell(Vector2i(0, -30000))
	if _frame == 150:
		_shot("stratosphere")
		return true
	return false


func _prepare_base() -> void:
	var dig: DigSystem = _main.dig
	var world: WorldData = _main.world
	var x0: int = _main._home.x
	# Шахта вниз и горизонтальные штреки.
	var s := world.gen.surface_y(x0)
	for d in range(0, 30):
		dig.add_order(Vector2i(x0, s + d))
		dig.add_order(Vector2i(x0 + 1, s + d))
	for level in [8, 16, 26]:
		for dx in range(2, 14):
			dig.add_order(Vector2i(x0 + dx, s + level))
			dig.add_order(Vector2i(x0 - dx + 1, s + level))
	dig.crews = 50
	dig.advance(1000000.0)
	dig.crews = 2
	for dx in range(14, 20):
		dig.add_order(Vector2i(x0 + dx, s + 16))
	_main.world_view.focus_cell(Vector2i(x0, s - 2))


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
