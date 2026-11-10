extends SceneTree
## Анимация мебели крупно: комната 9 м и 3 м с одним назначением, всё включено (горит, есть
## энергия, мастер за работой), серия кадров за секунду с лишним (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/anim_preview.gd -- <папка> <назначение> [кадров]

var _main: Node
var _out := "user://"
var _purpose := RoomType.HEARTH
var _count := 12
var _f := 0
var _t0 := 0
var _shots := 0
var _rooms: Array[Project] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_purpose = int(args[1])
	if args.size() > 2:
		_count = int(args[2])
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
		for k in Research.TECHS:
			if not k in colony.research.done:
				colony.research.done.append(k)
		colony.inventory.merge({"wood": 900, "stone": 300, "iron": 200, "copper": 50, "brick": 200}, true)
		colony.create_project(Project.Kind.TUNNEL, Rect2i(x0, s, 1, 9))
		for spec in [Rect2i(x0 + 1, s + 2, 9, 3), Rect2i(x0 + 1, s + 5, 3, 3)]:
			if colony.create_project(Project.Kind.ROOM, spec, -1, "wood") == null:
				print("не построить ", spec, ": ", colony.validate(Project.Kind.ROOM, spec, "wood", true))
		colony.advance_offline(60000.0)
		for pr in colony.projects:
			if pr.kind == Project.Kind.ROOM:
				pr.purpose = _purpose
				pr.wear = 0.0
				_rooms.append(pr)
		_main.hud._log.visible = false
		_main.world_view.focus_cell(Vector2i(x0 + 5, s + 3))
		_main.camera.zoom = Vector2(3.6, 3.6)
	if _f > 5:
		colony.power_made = 100
		for i in _rooms.size():
			var pr := _rooms[i]
			pr.blocked = ""
			if pr.purpose == RoomType.OIL_TANK:
				pr.held["oil"] = int(colony.room_limit(pr, "oil") * 0.6)
			pr.burning = true
			pr.on_gas = false
			# Мастер за работой (печь и горн горят, пока работают).
			if i < colony.units.size():
				var u: Unit = colony.units[i]
				u.state = Unit.State.WORK
				u.task = Unit.Task.CRAFT
				u.project_id = pr.id
				u.pos = Vector2(pr.rect.end.x - 1, pr.rect.end.y - 1)
				u.path = []
	if _f == 200:
		_main.set_process(false)
		for c in root.get_children():
			if c is LoadingScreen:
				c.queue_free()
	if _f == 220:
		_t0 = Time.get_ticks_msec()
	if _f > 220 and _shots < _count and Time.get_ticks_msec() - _t0 >= _shots * 1200.0 / _count:
		var path := _out.path_join("anim_%02d.png" % _shots)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_shots += 1
	return _shots >= _count
