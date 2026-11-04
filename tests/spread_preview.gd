extends SceneTree
## Гаврики в одной комнате расходятся по ширине: все пятеро ставятся в одну точку 9-метрового
## очага; снимки сразу и через ~2 секунды (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/spread_preview.gd -- <папка>

var _main: Node
var _out := "user://"
var _f := 0
var _x0 := 0
var _s := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	var colony: Colony = _main.colony
	if _f == 5:
		_x0 = _main._home.x + 2
		_s = _main.world.gen.surface_y(_x0)
		colony.inventory["wood"] = 500
		colony.create_project(Project.Kind.TUNNEL, Rect2i(_x0, _s, 1, 6))
		colony.create_project(Project.Kind.ROOM, Rect2i(_x0 + 1, _s + 2, 9, 3), -1, "wood")
		colony.advance_offline(40000.0)
		for pr in colony.projects:
			if pr.kind == Project.Kind.ROOM:
				pr.purpose = RoomType.HEARTH
		_main.hud._log.visible = false
		_main.world_view.focus_cell(Vector2i(_x0 + 5, _s + 3))
		_main.camera.zoom = Vector2(2.4, 2.4)
	if _f >= 6 and _f < 200:
		for u in colony.units:
			u.pos = Vector2(_x0 + 4, _s + 4)
			u.path = []
			u.state = Unit.State.WORK
			u.task = Unit.Task.WARM
	if _f == 12:
		_shot("spread_start")
	if _f == 150:
		_shot("spread_end")
		return true
	return false


func _shot(name: String) -> void:
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
