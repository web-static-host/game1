extends SceneTree
## Снимки построек, нарисованных кодом: тоннели и шахты из разных материалов, лифты, бур, зонд,
## космодром с ракетой, корабль, телепорт (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/structure_preview.gd -- <папка>

var _main: Node
var _frame := 0
var _out := "user://"
var _x0 := 0
var _s := 0
var _t0 := 0
var _pad_focus := Vector2i.ZERO
var _shots_done := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _try(kind: int, r: Rect2i, mat := "wood") -> Project:
	var colony: Colony = _main.colony
	var p := colony.create_project(kind, r, -1, mat, false)
	if p == null:
		print("не построить ", kind, " ", r, " ", mat, ": ", colony.validate(kind, r, mat, false))
	return p


## Ровное место шириной w правее x (по поверхности) — левый край.
func _flat(x: int, w: int) -> int:
	var gen: WorldGen = _main.world.gen
	while x < _x0 + 200:
		var ok := true
		for i in w:
			if gen.surface_y(x + i) != gen.surface_y(x):
				ok = false
				break
		if ok:
			return x
		x += 1
	return x


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		var colony: Colony = _main.colony
		for k in Research.TECHS:
			if not k in colony.research.done:
				colony.research.done.append(k)
		for k in ["wood", "stone", "iron", "brick", "silver", "gold", "diamond", "copper", "coal", "uranium", "amethyst", "ruby", "diesel"]:
			colony.inventory[k] = 2000
			colony.known_resources[k] = true
		_x0 = _main._home.x + 3
		_s = _main.world.gen.surface_y(_x0)
		var T := Project.Kind.TUNNEL
		var x0 := _x0
		var s := _s
		_try(T, Rect2i(x0, s, 1, 16))
		# Тоннели вбок из разных материалов, шахта.
		_try(T, Rect2i(x0 + 1, s + 3, 7, 1), "wood")
		_try(T, Rect2i(x0 + 1, s + 6, 7, 1), "iron")
		_try(T, Rect2i(x0 + 1, s + 9, 7, 1), "gold")
		_try(Project.Kind.MINE, Rect2i(x0 + 1, s + 12, 8, 3), "iron")
		_try(Project.Kind.LIFT, Rect2i(x0 - 3, s, 2, 16), "iron")
		_try(Project.Kind.LIFT, Rect2i(x0 - 7, s, 3, 16), "silver")
		var xp := _flat(x0 + 10, 2)
		_try(Project.Kind.PROBE, Rect2i(xp, _main.world.gen.surface_y(xp) - 2, 2, 2), "iron")
		var d := _try(Project.Kind.DRILL, Rect2i(x0 + 10, s + 4, 3, 3), "iron")
		if d != null:
			d.drill_dir = Vector2i.RIGHT
		for u in colony.units:
			u.lifespan = 0.0
		colony.advance_offline(80000.0)
		for pr in colony.projects:
			pr.wear = 0.0
			# Для снимка лифты, бур и скважина — готовыми (без питания и копки).
			if pr.kind in [Project.Kind.LIFT, Project.Kind.DRILL, Project.Kind.PROBE]:
				pr.phase = Project.Phase.DONE
				pr.paid = true
		colony.drops.clear()
		# Знак ремонта: тоннель из железа и шахта — ветхие.
		for pr in colony.projects:
			if (pr.kind == Project.Kind.TUNNEL and pr.material == "iron") or pr.kind == Project.Kind.MINE:
				pr.wear = 0.75
		_main.hud._log.visible = false
		_main.world_view.light.visible = false
		_main.world_view.focus_cell(Vector2i(x0 + 3, s + 7))
		_main.camera.zoom = Vector2(1.6, 1.6)
	if _frame == 34:
		_shot("tunnels")
		_main.world_view.focus_cell(Vector2i(_x0 + 4, _s + 3))
		_main.camera.zoom = Vector2(2.2, 2.2)
	if _frame == 40:
		_shot("machines")
		# Наземные: космодром с ракетой, корабль, телепорт.
		var colony: Colony = _main.colony
		var R := Project.Kind.ROOM
		var xs := _flat(_x0 + 16, 9)
		var lp := _try(R, Rect2i(xs, _main.world.gen.surface_y(xs) - 3, 9, 3), "iron")
		var xh := _flat(xs + 13, 9)
		var sh := _try(R, Rect2i(xh, _main.world.gen.surface_y(xh) - 3, 9, 3), "iron")
		var xt := _flat(xh + 13, 3)
		var tp := _try(R, Rect2i(xt, _main.world.gen.surface_y(xt) - 3, 3, 3), "stone")
		colony.advance_offline(40000.0)
		if lp != null:
			lp.purpose = RoomType.LAUNCHPAD
			lp.rocket = "chem"
		if sh != null:
			sh.purpose = RoomType.SHIP
		if tp != null:
			tp.purpose = RoomType.TELEPORT
		_pad_focus = Vector2i(xs + 6, _main.world.gen.surface_y(xs) - 9)
		_main.world_view.focus_cell(Vector2i(xs + 6, _main.world.gen.surface_y(xs) - 7))
		_main.camera.zoom = Vector2(1.0, 1.0)
	if _frame == 60:
		_shot("launchpad")
		var colony: Colony = _main.colony
		for pr in colony.projects:
			if pr.purpose == RoomType.SHIP:
				_main.world_view.focus_cell(pr.rect.get_center() + Vector2i(4, -1))
		_main.camera.zoom = Vector2(1.4, 1.4)
	if _frame == 70:
		_shot("ship")
		# Старт: ракета пропадает со стола — слой показывает зажигание и подъём.
		for pr in _main.colony.projects:
			if pr.purpose == RoomType.LAUNCHPAD:
				pr.rocket = ""
		_main.world_view.focus_cell(_pad_focus)
		_main.camera.zoom = Vector2(0.9, 0.9)
		_t0 = Time.get_ticks_msec()
	if _frame > 70 and _shots_done < 3:
		var t := (Time.get_ticks_msec() - _t0) / 1000.0
		var at: float = [0.7, 2.2, 3.6][_shots_done]
		if t >= at:
			_shot("launch_%d" % _shots_done)
			_shots_done += 1
	if _shots_done >= 3:
		return true
	return false


func _shot(name: String) -> void:
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
