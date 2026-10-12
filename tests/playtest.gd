extends SceneTree
## Плейтест: бот играет новую игру как человек несколько игровых суток и пишет отчёт —
## чем заняты жители, сытость и бодрость, еда, застрявшие и простаивающие, сообщения игры.
##   godot --headless --path . -s res://tests/playtest.gd -- <seed> <суток>

var colony: Colony
var world: WorldData
var logs: Array[String] = []
var _last_pos := {}
var _still := {}
var _anomalies := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 4242
	## Сколько минут реального времени играть.
	var days := int(args[1]) if args.size() > 1 else 30
	world = WorldData.new(WorldGen.new(seed_value))
	colony = Colony.new(world)
	colony.event_logged.connect(func(t: String, k: String) -> void:
		logs.append("[%s] %s%s" % [colony.date_text(), "" if k == "info" else k.to_upper() + ": ", t]))
	colony.start_new(0)
	var step := 0.5
	var t := 0.0
	var hour_t := 0.0
	var tasks := {}
	var plan := 0
	while t < days * 60.0:
		plan = _player(plan)
		colony.update(step)
		t += step
		hour_t += step
		for u in colony.units:
			var name: String = Unit.TASK_NAMES[u.task] if u.state != Unit.State.IDLE else "без дела"
			if u.state == Unit.State.FALL:
				name = "падает"
			if u.state == Unit.State.SWIM:
				name = "плывёт"
			tasks[name] = tasks.get(name, 0.0) + step
			_watch(u, step)
		if hour_t >= 120.0:
			hour_t = 0.0
			_report(tasks)
			tasks.clear()
	print("\n=== Сообщения игры ===")
	for l in logs:
		print(l)
	print("\n=== Подозрительное ===")
	for k in _anomalies:
		print(k, " ×", _anomalies[k])
	quit()


func _anomaly(text: String) -> void:
	_anomalies[text] = _anomalies.get(text, 0) + 1


## Житель долго стоит на месте не во сне и не за работой на месте — застрял?
func _watch(u: Unit, dt: float) -> void:
	var c := u.cell()
	if OS.get_environment("TRACE") == u.name and colony.game_time > Colony.DAY * 2.0 + Colony.DAY * 12.0 / 24.0 \
			and colony.game_time < Colony.DAY * 2.0 + Colony.DAY * 14.3 / 24.0 and int(colony.game_time * 2) % 4 == 0:
		var mats := []
		for dy in [-2, -1, 0, 1]:
			mats.append(Mat.name_of(world.get_mat(c.x, c.y + dy)))
		print("TRACE %s %s pos %s st%d %s hp %d path %d/%d %s" % [colony.date_text(), u.name, u.pos, u.state,
			Unit.TASK_NAMES[u.task], roundi(u.health), u.path_i, u.path.size(), mats])
	if _last_pos.get(u.id, Vector2i(1 << 20, 0)) == c and u.state == Unit.State.IDLE:
		_still[u.id] = _still.get(u.id, 0.0) + dt
		if _still[u.id] > Colony.DAY / 6.0:
			_anomaly("%s без дела дольше 4 ч на %s" % [u.name, c])
			_still[u.id] = 0.0
	else:
		_still[u.id] = 0.0
	_last_pos[u.id] = c
	if u.state == Unit.State.FALL and not colony.pathing.passable(c + Vector2i(0, 1)):
		_anomaly("%s «падает», упёршись в породу" % u.name)
	if u.task == Unit.Task.SLEEP and u.energy >= 100.0 and u.state == Unit.State.WORK:
		_anomaly("%s спит, хотя выспался" % u.name)


func _report(tasks: Dictionary) -> void:
	var sat := 0.0
	var en := 0.0
	var hp := 0.0
	for u in colony.units:
		sat += u.satiety
		en += u.energy
		hp += u.health
	var n := maxf(1, colony.units.size())
	var parts: PackedStringArray = []
	var keys := tasks.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return tasks[a] > tasks[b])
	var total := 0.0
	for k in tasks:
		total += tasks[k]
	for k in keys:
		parts.append("%s %d%%" % [k, roundi(tasks[k] * 100.0 / maxf(1.0, total))])
	var drops := 0
	for c in colony.drops:
		for k in colony.drops[c]:
			drops += int(colony.drops[c][k])
	var projects: PackedStringArray = []
	for p in colony.projects:
		if p.phase != Project.Phase.DONE or p.repairing:
			projects.append("%s:%s%s" % [p.title(), p.phase_name(), (" [" + p.blocked + "]") if not p.blocked.is_empty() else ""])
	print("[%d с] %s | жит %d сыт %d бодр %d здор %d | еда %d дер %d кам %d | на земле %d | %s" % [
		Time.get_ticks_msec() / 1000, colony.date_text(), colony.units.size(), roundi(sat / n), roundi(en / n), roundi(hp / n),
		colony.inventory.get("food", 0), colony.inventory.get("wood", 0), colony.inventory.get("stone", 0), drops,
		", ".join(parts)])
	if not projects.is_empty():
		print("    стройки: ", "; ".join(projects))
	for p in colony.projects:
		if not colony.required(p).is_empty():
			print("    нужно %s, принесено %s, осталось %s, склад %s, рабочих %d/%d, рамка %s, дом %s" % [colony.required(p), p.delivered,
				colony.remaining(p), colony.inventory, colony.workers_on(p), p.workers, p.rect, colony.home])
			for u in colony.units:
				var reach := colony.pathing.explore(u.cell())
				var src := colony._haul_source("wood", reach[1])
				print("      %s %s %s st%d pid%d carry %s×%d stage%d drop%s store%s | источник %s, к стройке %s" % [u.name, u.cell(),
					Unit.TASK_NAMES[u.task], u.state, u.project_id, u.carry_key, u.carry_amount, u.haul_stage, u.from_drop, u.to_store,
					src, colony._near_rect(p.rect, reach[1])])
	var by := {}
	for c in colony.drops:
		for k in colony.drops[c]:
			by[k] = by.get(k, 0) + int(colony.drops[c][k])
	if not by.is_empty():
		print("    на земле: ", by, " ёмкость еды ", colony.capacity("food"))


## Что делал бы игрок: сбор, дом, склад, шахта и ферма под землёй.
func _player(plan: int) -> int:
	match plan:
		0:
			# Отмечаем ближайшие деревья, валуны и кусты.
			var marked := 0
			for d in range(1, 60):
				for x in [colony.home.x - d, colony.home.x + d]:
					var f := world.feature_at(x)
					if f != WorldGen.FEATURE_NONE and marked < 12 and colony.toggle_harvest(x).is_empty():
						marked += 1
			return 1
		1:
			if colony.inventory.get("wood", 0) + colony.drop_total("wood") >= 12:
				var r = _place_room(6, colony.home.x + 6)
				if r != null:
					colony.create_project(Project.Kind.ROOM, r)
					return 2
		2:
			for p in colony.projects:
				if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == RoomType.NONE:
					colony.set_purpose(p, RoomType.HOME)
					return 3
		3:
			if colony.inventory.get("wood", 0) >= 15:
				var r = _place_room(6, colony.home.x - 14)
				if r != null:
					colony.create_project(Project.Kind.ROOM, r)
					return 4
		4:
			for p in colony.projects:
				if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == RoomType.NONE:
					colony.set_purpose(p, RoomType.STORAGE)
					return 5
		5:
			# Шахта у базы и подземная комната под ферму.
			var x := colony.home.x + 2
			var s := world.gen.surface_y(x)
			if colony.validate(Project.Kind.TUNNEL, Rect2i(x, s, 1, 8)).is_empty():
				colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 8))
				colony.create_project(Project.Kind.ROOM, Rect2i(x + 1, s + 5, 6, 3))
			return 6
		6:
			for p in colony.projects:
				if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == RoomType.NONE \
						and colony.is_underground(p):
					colony.set_purpose(p, RoomType.FARM)
					return 7
	return plan


## Комната ширины w на земле у столбца x (ищем ровное место рядом).
func _place_room(w: int, x: int) -> Variant:
	for dx in range(0, 40):
		for sx in [x + dx, x - dx]:
			var s := world.gen.surface_y(sx)
			var r := Rect2i(sx, s - 3, w, 3)
			if colony.validate(Project.Kind.ROOM, r).is_empty():
				return r
	return null
