extends SceneTree
## Открыть сохранение игрока как в игре и посмотреть комнату: снимки и журнал того, что делают
## гаврики в ней (кадр, позиция, состояние, дело, поза на рисунке) — ищем, кто дёргается
## (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/save_watch.gd -- <сохранение.json> <папка> <назначение комнаты> [кадров]

var _main: Node
var _out := "user://"
var _purpose := RoomType.FARM
var _frames := 120
var _f := 0
var _room: Project


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var text := FileAccess.get_file_as_string(args[0])
	var f := FileAccess.open(SaveSystem.DEFAULT_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	if args.size() > 1:
		_out = args[1]
	if args.size() > 2:
		_purpose = int(args[2])
	if args.size() > 3:
		_frames = int(args[3])
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	var colony: Colony = _main.colony
	if _f == 60:
		for p in colony.projects:
			if p.kind == Project.Kind.ROOM and p.purpose == _purpose and p.phase == Project.Phase.DONE:
				var n := 0
				for u in colony.units:
					if p.rect.has_point(u.cell()):
						n += 1
				if _room == null or n > 0:
					_room = p
				if n >= 3:
					break
		if _room == null:
			print("нет такой комнаты")
			return true
		_main.world_view.focus_cell(_room.rect.get_center())
		_main.camera.zoom = Vector2(2.2, 2.2)
		_main.hud._log.visible = false
	if _f > 62 and _room != null:
		var layer: UnitLayer = _main.world_view.units_layer
		for u in colony.units:
			if _room.rect.grow(1).has_point(u.cell()):
				var node = layer._nodes.get(u.id)
				print("%d %s pos=(%.2f,%.2f) st=%d task=%d pose=%s spread=%.1f foot=%s" % [_f, u.name, u.pos.x, u.pos.y, u.state, u.task,
					node.pose if node != null else "-", layer._spread.get(u.id, 0.0), layer.foot_of(u)])
	if _f in [64, 64 + _frames / 2, 62 + _frames]:
		var path := _out.path_join("watch_%d.png" % _f)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	return _f > 62 + _frames
