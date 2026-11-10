extends SceneTree
## Проверка мебели всех комнат крупно: три комнаты — 9, 6 и 3 м (все размеры, что можно
## заложить), по очереди каждое назначение (и варианты очага; корабль — только 9 м) из каждого
## материала стен; всё включено, гаврики, интерфейс и значки скрыты; снимок каждой комнаты
## отдельно — <назначение>_<материал>_<ширина>.png (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/room_audit.gd -- <папка> [назначения через запятую] [материалы через запятую]

var _main: Node
var _out := "user://"
var _f := 0
var _list := []
var _mats := MATS
var _i := 0
var _t := 0
var _rooms: Array[Project] = []

## [имя, назначение, вариант очага]
const ALL := [["home", 1, ""], ["storage", 2, ""], ["farm", 3, ""], ["dining", 4, ""], ["pump", 5, ""], ["vent", 6, ""],
	["lab", 7, ""], ["kiln", 8, ""], ["forge", 9, ""], ["generator", 10, ""], ["degas", 11, ""], ["granary", 12, ""],
	["hearth_stone", 13, "stone"], ["hearth_brick", 13, "brick"], ["hearth_gas", 13, "gas"], ["gas_gen", 14, ""],
	["oil_pump", 15, ""], ["oil_tank", 16, ""], ["refinery", 17, ""], ["diesel", 18, ""], ["enrichment", 21, ""],
	["teleport", 22, ""], ["ship", RoomType.SHIP, ""]]
const MATS := ["wood", "stone", "brick", "iron", "silver", "gold", "diamond"]
const WIDTHS := [9, 6, 3]
const ZOOM := {9: 4.2, 6: 5.5, 3: 5.5}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_list = ALL
	if args.size() > 1 and not args[1].is_empty():
		var want := args[1].split(",")
		_list = ALL.filter(func(e: Array) -> bool: return e[0] in want)
	if args.size() > 2:
		_mats = Array(args[2].split(","))
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _setup(pr: Project, e: Array, mat: String) -> void:
	var colony: Colony = _main.colony
	pr.purpose = e[1]
	pr.material = mat
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
		colony.create_project(Project.Kind.TUNNEL, Rect2i(x0, s, 1, 12))
		for j in WIDTHS.size():
			var spec := Rect2i(x0 + 1, s + 2 + j * 3, WIDTHS[j], 3)
			var pr := colony.create_project(Project.Kind.ROOM, spec, -1, "wood")
			if pr == null:
				print("не построить ", spec, ": ", colony.validate(Project.Kind.ROOM, spec, "wood", true))
				quit(1)
				return true
			_rooms.append(pr)
		colony.advance_offline(60000.0)
		colony.drops.clear()
		_main.hud.visible = false
		_main.world_view.units_layer.visible = false
	if _f == 200:
		_main.set_process(false)
		for c in root.get_children():
			if c is LoadingScreen:
				c.queue_free()
		if _main.world_view.structures._signs != null:
			_main.world_view.structures._signs.visible = false
	if _f < 210:
		return false
	colony.power_made = 100
	var per := _mats.size() * WIDTHS.size()
	if _i >= _list.size() * per:
		return true
	var e: Array = _list[_i / per]
	var mat: String = _mats[(_i % per) / WIDTHS.size()]
	var pr: Project = _rooms[_i % WIDTHS.size()]
	if e[1] == RoomType.SHIP and (pr.rect.size.x != 9 or mat != _mats[0]):
		# Корабль — всегда 9 м и своя обшивка.
		_i += 1
		return false
	if _t == 0:
		for q in _rooms:
			_setup(q, e, mat)
		# Мастер «за работой» в каждой — печи горят, станки крутятся (гавриков не видно).
		for j in mini(_rooms.size(), colony.units.size()):
			var u: Unit = colony.units[j]
			u.state = Unit.State.WORK
			u.task = Unit.Task.CRAFT
			u.project_id = _rooms[j].id
		_main.world_view.focus_cell(pr.rect.get_center())
		var z: float = ZOOM[pr.rect.size.x]
		_main.camera.zoom = Vector2(z, z)
		_main.world_view.structures._static_t = 0.0
	_t += 1
	if _t == 6:
		var path := _out.path_join("%s_%s_%d.png" % [e[0], mat, pr.rect.size.x])
		root.get_texture().get_image().save_png(path)
		_t = 0
		_i += 1
	return false
