extends SceneTree
## Нефтекачалка в работе: 9-метровая (три качалки) и 3-метровая, четыре снимка с шагом в
## четверть хода (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/pumpjack_preview.gd -- <папка> [кадров на ход]

var _main: Node
var _out := "user://"
var _f := 0
var _t0 := 0
var _shots := 0
var _rooms: Array[Project] = []
var _count := 4


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_count = int(args[1])
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	var colony: Colony = _main.colony
	if _f == 5:
		var x0: int = _main._home.x + 2
		var s: int = _main.world.gen.surface_y(x0)
		colony.research.done.append_array(["electricity", "oil_drilling", "steel_frame"])
		colony.inventory.merge({"wood": 900, "stone": 300, "iron": 200, "copper": 50}, true)
		colony.create_project(Project.Kind.TUNNEL, Rect2i(x0, s, 1, 9))
		for spec in [Rect2i(x0 + 1, s + 2, 9, 3), Rect2i(x0 + 1, s + 5, 3, 3)]:
			colony.create_project(Project.Kind.ROOM, spec, -1, "wood")
		colony.advance_offline(60000.0)
		for pr in colony.projects:
			if pr.kind == Project.Kind.ROOM:
				pr.purpose = RoomType.OIL_PUMP
				pr.wear = 0.0
				_rooms.append(pr)
		_main.hud._log.visible = false
		_main.world_view.focus_cell(Vector2i(x0 + 8, s + 3))
		_main.camera.zoom = Vector2(5.0, 5.0)
	if _f > 5:
		colony.power_made = 100
		for pr in _rooms:
			pr.blocked = ""
	# Загрузка закончилась — мир стоит (качалка рисуется сама), а качалка «работает».
	if _f == 200:
		_main.set_process(false)
		for c in root.get_children():
			if c is LoadingScreen:
				c.queue_free()
	if _f == 220:
		_t0 = Time.get_ticks_msec()
	if _f > 220 and _shots < _count and Time.get_ticks_msec() - _t0 >= _shots * StructureLayer.PJ_PERIOD * 1000.0 / _count:
		var path := _out.path_join("pumpjack_%d.png" % _shots)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_shots += 1
	return _shots >= _count
