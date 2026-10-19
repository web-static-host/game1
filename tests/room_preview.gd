extends SceneTree
## Снимки комнат из разных материалов: жилые, склады, амбары, фермы — новые картинки и как было.
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/room_preview.gd -- <папка> [2]
## С «2» — второй набор: очаги (камень, кирпич, газ), столовые, лаборатории.

var _main: Node
var _frame := 0
var _out := "user://"
var _set2 := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_set2 = args.size() > 1 and args[1] == "2"
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
		colony.research.done.append_array(["geology", "geology2", "electricity"])
		var T := Project.Kind.TUNNEL
		var R := Project.Kind.ROOM
		colony.create_project(T, Rect2i(x0, s, 1, 15))
		colony.create_project(R, Rect2i(x0 + 1, s + 2, 9, 3), -1, "wood")
		colony.create_project(R, Rect2i(x0 + 1, s + 5, 6, 3), -1, "brick")
		colony.create_project(R, Rect2i(x0 + 7, s + 5, 3, 3), -1, "metal")
		colony.create_project(R, Rect2i(x0 + 1, s + 8, 6, 3), -1, "stone")
		colony.create_project(R, Rect2i(x0 + 7, s + 8, 3, 3), -1, "wood")
		colony.create_project(R, Rect2i(x0 + 1, s + 11, 6, 3), -1, "wood")
		colony.create_project(R, Rect2i(x0 + 7, s + 11, 3, 3), -1, "brick")
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
			# Обстановка-картинки по месту комнаты: (ряд, слева?) → назначение.
			if pr.kind == R:
				var row := pr.rect.position.y - s
				var left := pr.rect.position.x == x0 + 1
				pr.purpose = {2: RoomType.HOME, 5: RoomType.STORAGE if left else RoomType.HOME,
					8: RoomType.STORAGE if left else RoomType.FARM, 11: RoomType.FARM if left else RoomType.GRANARY}[row]
				if _set2:
					pr.purpose = {2: RoomType.HEARTH, 5: RoomType.DINING if left else RoomType.LAB,
						8: RoomType.LAB if left else RoomType.HEARTH, 11: RoomType.HEARTH if left else RoomType.DINING}[row]
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
		_stage()
		_main.hud._log.visible = false    # сообщения закрывают комнаты
		_main.world_view.focus_cell(Vector2i(x0 + 5, s + 7))
		_main.camera.zoom = Vector2(2.2, 2.2)
	if _frame in [38, 44]:
		_stage()
	if _frame == 40:
		_shot("room_new")
		_main.world_view.focus_cell(Vector2i(_main._home.x + 7, _main.world.gen.surface_y(_main._home.x + 2) + 11))
	if _frame == 46:
		_shot("room_low")
		for k in StructureLayer._room_tex.keys():
			StructureLayer._room_tex[k] = null
	if _frame == 50:
		_shot("room_old")
		return true
	return false


func _shot(name: String) -> void:
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


## Запасы, рост грибов и энергия — игра идёт и меняет их, поэтому ставим перед каждым снимком.
func _stage() -> void:
	for pr in _main.colony.projects:
		if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.STORAGE:
			pr.held = {"brick": 30, "metal": 25, "stone": 20, "wood": 25, "coal": 15, "gold": 10, "copper": 10, "salt": 10} \
				if pr.material == "brick" else {"iron": 20, "diamond": 10, "uranium": 10, "clay": 15, "limestone": 15, "silver": 10}
		if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.GRANARY:
			pr.held = {"food": 30, "berries": 20}
		if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.FARM:
			pr.farm_progress = RoomType.FARM_CYCLE * (0.9 if pr.rect.size.x == 6 else 0.5)
	_main.colony.power_made = 10    # лампы на фермах горят
	# Очаги: 9 м — каменный, 3 м — кирпичный, 6 м — газовые котлы; горят все, кроме 3 м.
	for pr in _main.colony.projects:
		if pr.kind == Project.Kind.ROOM and pr.purpose == RoomType.HEARTH:
			pr.brick_stoves = pr.rect.size.x != 9
			pr.gas_boiler = pr.rect.size.x == 6
			pr.on_gas = pr.gas_boiler
			pr.burning = pr.rect.size.x != 3
