extends SceneTree
## Сравнение 3D-модели гаврика с рисованными (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/model_compare.gd -- <папка> [форма для листа: 0 — треугольник, 1 — квадрат, 2 — круг]
## Снимки: колония с моделью и без, лист поз «рисованный / 3D».

var _main: Node
var _frame := 0
var _out := "user://"
var _shape := CreatureArt.Shape.TRIANGLE


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_shape = int(args[1])
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		ModelSprites.enabled = true
		# Трое из пяти — треугольник, квадрат и круг с одним глазом (модель), двое — как выпали.
		var cols := [Color(0.95, 0.25, 0.2), Color(0.2, 0.45, 1.0), Color(1.0, 0.8, 0.1)]
		for i in 3:
			var u: Unit = _main.colony.units[i * 2]
			var g: Dictionary = u.genome.duplicate(true)
			g["shape"] = [i, i]
			g["eyes"] = [1, 1]
			g["color"] = [cols[i], cols[i]]
			u.set_genome(g)
		for u in _main.colony.units:
			var x: int = _main._home.x - 3 + _main.colony.units.find(u) * 2
			u.pos = Vector2(x, _main.world.gen.surface_y(x) - 1)
		_main.world_view.focus_cell(_main._home + Vector2i(0, -2))
		_main.camera.zoom = Vector2(2.2, 2.2)
	if _frame == 60:
		print("модель: ", ModelSprites.status)
		_shot("model_on")
		ModelSprites.enabled = false
		_main.world_view.units_layer.refresh()
	if _frame == 64:
		_shot("model_off")
		ModelSprites.enabled = true
		_main.world_view.units_layer.refresh()
		_main._select(_main.colony.units[0], null)
	if _frame == 70:
		_shot("model_card")
		_main._select(null, null)
		_build_sheet()
	if _frame == 76:
		_shot("model_sheet")
		return true
	return false


## Лист поз: сверху рисованный гаврик, снизу 3D-модель; справа — оба в размере игры.
func _build_sheet() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.7, 0.85)
	bg.size = Vector2(1280, 720)
	layer.add_child(bg)
	var poses := ["idle", "walk0", "walk2", "work0", "work2", "carry0", "climb0", "eat", "fish", "fall", "blink"]
	var looks := Genetics.looks(Genetics.founder(RandomNumberGenerator.new()))
	looks["shape"] = _shape
	looks["eyes"] = 1
	looks["color"] = Color(0.2, 0.45, 1.0)
	for i in poses.size():
		var x := 62.0 + i * 106.0
		var g := looks.duplicate()
		g["pose"] = UnitLayer.POSES[poses[i]]
		var pose: String = poses[i]
		_add(layer, func(ci: CanvasItem) -> void: CreatureArt.draw(ci, Vector2(x, 300), 60.0, g, 1.0))
		_add(layer, func(ci: CanvasItem) -> void: ModelSprites.draw_creature(ci, pose, Vector2(x, 610), 60.0, looks))
		_add(layer, func(ci: CanvasItem) -> void: ci.draw_string(ThemeDB.fallback_font, Vector2(x - 50, 345), pose, HORIZONTAL_ALIGNMENT_CENTER, 100, 18, Color.WHITE))
	_add(layer, func(ci: CanvasItem) -> void:
		ci.draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Рисованный (как было)", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		ci.draw_string(ThemeDB.fallback_font, Vector2(20, 400), "3D-модель", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE))


func _add(parent: Node, fn: Callable) -> void:
	var n := Node2D.new()
	n.draw.connect(func() -> void: fn.call(n))
	parent.add_child(n)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)
