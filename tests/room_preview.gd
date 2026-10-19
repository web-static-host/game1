extends SceneTree
## Снимки комнат из разных материалов (дерево, кирпич-склад, металл, камень) — новые картинки и как было.
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/room_preview.gd -- <папка>

var _main: Node
var _frame := 0
var _out := "user://"


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
	if _frame == 5:
		var colony: Colony = _main.colony
		var world: WorldData = _main.world
		var x0: int = _main._home.x + 2
		var s := world.gen.surface_y(x0)
		colony.inventory = {"wood": 600, "stone": 300, "food": 200, "brick": 300, "metal": 300, "coal": 15, "gold": 10, "copper": 10,
			"salt": 10, "iron": 20, "diamond": 10, "uranium": 10, "clay": 15, "limestone": 15, "silver": 10}
		colony.known_resources = {"wood": true, "stone": true}
		# Геологоразведка II: порода видна на 3 клетки от выработок — проверить, что все открытые
		# клетки рисуются одинаково.
		colony.research.done.append_array(["geology", "geology2"])
		var T := Project.Kind.TUNNEL
		var R := Project.Kind.ROOM
		colony.create_project(T, Rect2i(x0, s, 1, 12))
		colony.create_project(R, Rect2i(x0 + 1, s + 2, 9, 3), -1, "wood")
		colony.create_project(R, Rect2i(x0 + 1, s + 5, 6, 3), -1, "brick")
		colony.create_project(R, Rect2i(x0 + 7, s + 5, 3, 3), -1, "metal")
		colony.create_project(R, Rect2i(x0 + 1, s + 8, 6, 3), -1, "stone")
		for u in colony.units:
			u.lifespan = 0.0
		colony.advance_offline(60000.0)
		colony.game_time = Colony.MONTH * 3.0
		for u in colony.units:
			u.health = 100.0
			u.satiety = 90.0
			u.energy = 90.0
		# Для превью: без износа, светло, жители сыты и стоят в комнатах.
		colony.drops.clear()    # кучки на полу мешают разглядеть обстановку
		for pr in colony.projects:
			pr.wear = 0.0
			# Обстановка-картинки: дерево и металл — жилые, кирпич и камень — склады.
			if pr.kind == R:
				pr.purpose = RoomType.STORAGE if pr.material in ["brick", "stone"] else RoomType.HOME
				# Склады одной ширины: кирпичный с лестницей, каменный без — должны выглядеть одинаково.
				if pr.material == "stone":
					pr.ladder = false
		_main.world_view.light.visible = false
		var spots := [Vector2(x0 + 3, s + 4), Vector2(x0 + 7, s + 4), Vector2(x0 + 3, s + 7), Vector2(x0 + 8, s + 7), Vector2(x0 + 4, s + 10)]
		for i in colony.units.size():
			var u: Unit = colony.units[i]
			u.pos = spots[i % spots.size()]
			u.path = []
			u.task = Unit.Task.NONE
			u.state = Unit.State.IDLE
		for i in 3:
			colony.update(0.1)
		# Запасы — после обновлений колонии (иначе ресурсов, которых нет на складе, не станет).
		for pr in colony.projects:
			if pr.kind == R and pr.purpose == RoomType.STORAGE:
				pr.held = {"brick": 30, "metal": 25, "stone": 20, "wood": 25, "coal": 15, "gold": 10, "copper": 10, "salt": 10} \
					if pr.material == "brick" else {"iron": 20, "diamond": 10, "uranium": 10, "clay": 15, "limestone": 15, "silver": 10}
		_main.hud._log.visible = false    # сообщения закрывают комнаты
		_main.world_view.focus_cell(Vector2i(x0 + 5, s + 7))
		_main.camera.zoom = Vector2(2.2, 2.2)
	if _frame == 40:
		_shot("room_new")
		for k in StructureLayer._room_tex.keys():
			StructureLayer._room_tex[k] = null
	if _frame == 44:
		_shot("room_old")
		return true
	return false


func _shot(name: String) -> void:
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
