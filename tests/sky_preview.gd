extends SceneTree
## Снимки фона (горы, облака, лес, холмы с параллаксом) в разных местах карты и зимой.
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/sky_preview.gd -- <папка>

var _main: Node
var _frame := 0
var _out := "user://"
## [кадр, сдвиг камеры по x в клетках, зум, зима?, имя снимка]
const SHOTS := [
	[20, 0, 1.0, false, "sky_home"],
	[30, 70, 1.0, false, "sky_east"],
	[40, -160, 1.0, false, "sky_west"],
	[50, 30, 0.55, false, "sky_far"],
	[60, 0, 1.0, true, "sky_winter"],
	[70, "low", 0.8, true, "sky_low"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	for s in SHOTS:
		if _frame == s[0] - 6:
			var home: Vector2i = _main._home
			var x: int = home.x + s[1] if s[1] is int else _lowest_x(home.x)
			_main.world_view.focus_cell(Vector2i(x, _main.world.gen.surface_y(x) - 5))
			_main.camera.zoom = Vector2(s[2], s[2])
			_main.colony.game_time = Colony.YEAR - Colony.CALENDAR_START + Colony.MONTH * 0.5 if s[3] else Colony.MONTH * 4.5
		if _frame == s[0]:
			var path := _out.path_join(s[4] + ".png")
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	return _frame > SHOTS[-1][0]


## Где рядом с базой земля ниже всего — там фон должен опуститься вместе с ней.
func _lowest_x(x0: int) -> int:
	var best := x0
	for x in range(x0 - 200, x0 + 200):
		if _main.world.gen.land_y(x) > _main.world.gen.land_y(best):
			best = x
	return best
