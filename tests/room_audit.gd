extends SceneTree
## Проверка мебели всех комнат крупно: одна комната 9 м и одна 3 м, по очереди каждое назначение
## (и варианты очага, каюта корабля — только 9 м), всё включено, гаврики скрыты; снимок каждой
## комнаты отдельно
## (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/room_audit.gd -- <папка> [назначения через запятую]

var _main: Node
var _out := "user://"
var _f := 0
var _list := []
var _i := 0
var _t := 0
var _big: Project
var _small: Project

## [имя, назначение, вариант очага]
const ALL := [["home", 1, ""], ["storage", 2, ""], ["farm", 3, ""], ["dining", 4, ""], ["pump", 5, ""], ["vent", 6, ""],
	["lab", 7, ""], ["kiln", 8, ""], ["forge", 9, ""], ["generator", 10, ""], ["degas", 11, ""], ["granary", 12, ""],
	["hearth_stone", 13, "stone"], ["hearth_brick", 13, "brick"], ["hearth_gas", 13, "gas"], ["gas_gen", 14, ""],
	["oil_pump", 15, ""], ["oil_tank", 16, ""], ["refinery", 17, ""], ["diesel", 18, ""], ["enrichment", 21, ""],
	["teleport", 22, ""], ["ship", RoomType.SHIP, ""]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_list = ALL
	if args.size() > 1:
		var want := args[1].split(",")
		_list = ALL.filter(func(e: Array) -> bool: return e[0] in want)
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _setup(pr: Project, e: Array) -> void:
	var colony: Colony = _main.colony
	pr.purpose = e[1]
	pr.wear = 0.0
	pr.blocked = ""
	pr.burning = true
	pr.brick_stoves = e[2] == "brick" or e[2] == "gas"
	pr.gas_boiler = e[2] == "gas"
	pr.on_gas = e[2] == "gas"
	pr.held.clear()
	if pr.purpose == RoomType.OIL_TANK:
		pr.held["oil"] = int(colony.room_limit(pr, "oil") * 0.6)
	if pr.purpose == RoomType.STORAGE:
		pr.held = {"wood": 30, "stone": 20, "iron": 20, "coal": 15, "brick": 20}
	if pr.purpose == RoomType.GRANARY:
		pr.held = {"food": 30, "berries": 20, "fish": 10}
	if pr.purpose == RoomType.FARM:
		pr.farm_progress = RoomType.FARM_CYCLE * 0.8


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
		_big = colony.create_project(Project.Kind.ROOM, Rect2i(x0 + 1, s + 2, 9, 3), -1, "wood")
		_small = colony.create_project(Project.Kind.ROOM, Rect2i(x0 + 1, s + 5, 3, 3), -1, "wood")
		colony.advance_offline(60000.0)
		colony.drops.clear()
		_main.hud._log.visible = false
		_main.world_view.units_layer.visible = false
	if _f == 200:
		_main.set_process(false)
		for c in root.get_children():
			if c is LoadingScreen:
				c.queue_free()
	if _f < 210:
		return false
	colony.power_made = 100
	if _i >= _list.size() * 2:
		return true
	var e: Array = _list[_i / 2]
	var pr: Project = _big if _i % 2 == 0 else _small
	if pr == _small and e[1] == RoomType.SHIP:
		# Корабль всегда 9 м.
		_i += 1
		return false
	if _t == 0:
		_setup(_big, e)
		_setup(_small, e)
		# Мастер «за работой» в обеих — печи горят, станки крутятся (гавриков не видно).
		for j in mini(2, colony.units.size()):
			var u: Unit = colony.units[j]
			u.state = Unit.State.WORK
			u.task = Unit.Task.CRAFT
			u.project_id = (_big if j == 0 else _small).id
		_main.world_view.focus_cell(pr.rect.get_center())
		_main.camera.zoom = Vector2(4.2, 4.2) if pr == _big else Vector2(5.5, 5.5)
	_t += 1
	if _t == 6:
		var path := _out.path_join("%s_%d.png" % [e[0], pr.rect.size.x])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_t = 0
		_i += 1
	return false
