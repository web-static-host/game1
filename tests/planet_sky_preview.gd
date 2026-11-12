extends SceneTree
## Снимки фона планеты: колония сразу на планете (как после прилёта), снимки у базы, левее,
## издали и ночью (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/planet_sky_preview.gd -- <папка> [планета]

var _main: Node
var _f := 0
var _out := "user://"
var _planet := "neptune"
## [кадр, сдвиг камеры по x в клетках, зум, ночь?, имя]
const SHOTS := [
	[430, 0, 1.0, false, "home"],
	[445, -80, 1.0, false, "west"],
	[460, 40, 0.55, false, "far"],
	[475, 0, 1.0, true, "night"],
	[490, 0, 1.0, false, "clean"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_planet = args[1]
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	# Сначала игра грузит Землю целиком, потом — прилёт и переход на планету.
	if _f == 200:
		# Экипаж — копии земных гавриков (без экипажа колония считается погибшей).
		var crew := []
		for u in _main.colony.units:
			crew.append(u.to_dict())
		_main.universe._arrive({"planet": _planet, "crew": crew})
		_main._switch_world(_planet)
	if _f == 400:
		for c in root.get_children():
			if c is LoadingScreen:
				c.queue_free()
		_main.hud._log.visible = false
	for s in SHOTS:
		if _f == s[0] - 8:
			var home: Vector2i = _main._home
			var x: int = home.x + s[1]
			_main.world_view.focus_cell(Vector2i(x, _main.world.gen.surface_y(x) - 5))
			_main.camera.zoom = Vector2(s[2], s[2])
			_main.colony.game_time = Colony.MONTH * 4.5 + (Colony.DAY * 0.5 if s[3] else 0.0)
		if _f == s[0] - 4 and s[4] == "clean":
			# Без дымки ядовитого газа — видно сами слои фона.
			for c in _main.world_view.get_children():
				if c is SeasonFx:
					c.visible = false
		if _f == s[0]:
			var path := _out.path_join("%s_%s.png" % [_planet, s[4]])
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	return _f > SHOTS[-1][0]
