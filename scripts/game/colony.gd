class_name Colony
extends RefCounted
## Колония: жители, стройки, склад. Жители сами разбирают работу по приоритетам:
## 1) сбор ресурсов, если стройка ждёт материалы; 2) стройки по порядку закладки;
## 3) остальной помеченный сбор.
## Онлайн жители ходят и работают по-настоящему (update), оффлайн — упрощённо (advance_offline).

signal event_logged(text: String, kind: String)

const START_UNITS := 5
const START_INVENTORY := {"wood": 20, "stone": 15}
const SUBSTEP := 0.2
const WALK_SPEED := 3.0
const CLIMB_SPEED := 1.6
const FALL_SPEED := 8.0
const OFFLINE_EFFICIENCY := 0.75
const HARVEST_TIME := {WorldGen.FEATURE_TREE: 20.0, WorldGen.FEATURE_BOULDER: 25.0}
const DIRS4: Array[Vector2i] = WorldData.DIRS4
## Ресурсы, о находке которых сообщаем сразу.
const NOTABLE := ["coal", "iron", "copper", "silver", "gold", "uranium", "diamond", "salt", "oil"]

var world: WorldData
var pathing: Pathing
var units: Array[Unit] = []
var projects: Array[Project] = []
var inventory := {}
## Клетки готовых построек: Vector2i -> id проекта.
var interior := {}
## Клетки всех комнат (и строящихся): Vector2i -> id проекта.
var room_cells := {}
## Занятые цели: ключ -> id жителя.
var reserved := {}
## Прогресс копки клеток, сек: Vector2i -> float.
var dig_progress := {}
## Прогресс сбора: x -> float.
var harvest_progress := {}
var cells_dug := 0
var discovered := {}
var next_project_id := 1
var next_unit_id := 1


func _init(p_world: WorldData) -> void:
	world = p_world
	pathing = Pathing.new(world, interior, room_cells)


# --- Начало игры ----------------------------------------------------------------

func start_new(home_x: int) -> void:
	inventory = START_INVENTORY.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = world.gen.world_seed
	var sexes := [Unit.Sex.MALE, Unit.Sex.FEMALE, Unit.Sex.MALE, Unit.Sex.FEMALE]
	sexes.append(rng.randi_range(0, 1))
	var used := {}
	for i in START_UNITS:
		var u := Unit.new()
		u.id = next_unit_id
		next_unit_id += 1
		u.sex = sexes[i]
		var names: Array = Unit.MALE_NAMES if u.sex == Unit.Sex.MALE else Unit.FEMALE_NAMES
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		while used.has(n):
			n = names[rng.randi_range(0, names.size() - 1)]
		used[n] = true
		u.name = n
		u.look = rng.randf()
		# Небольшие врождённые склонности.
		for k in u.skills:
			u.skills[k] = rng.randf_range(0.0, 200.0)
		var x := home_x - 2 + i
		u.pos = Vector2(x, world.gen.surface_y(x) - 1)
		units.append(u)


# --- Стройки --------------------------------------------------------------------

func project_by_id(pid: int) -> Project:
	for p in projects:
		if p.id == pid:
			return p
	return null


func project_at(c: Vector2i) -> Project:
	for p in projects:
		if p.has_cell(c):
			return p
	return null


func unit_at(p: Vector2) -> Unit:
	var best: Unit = null
	var best_d := 1.2
	for u in units:
		var d := (u.pos + Vector2(0, -0.5)).distance_to(p)
		if d < best_d:
			best_d = d
			best = u
	return best


func validate(kind: int, r: Rect2i) -> String:
	var err := Project.size_error(kind, r)
	if not err.is_empty():
		return err
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if project_at(c) != null:
				return "Пересекается с другой стройкой"
			if world.is_revealed(x, y) and Mat.is_fluid(world.get_mat(x, y)):
				return "В зоне стройки %s" % Mat.name_of(world.get_mat(x, y)).to_lower()
	if kind == Project.Kind.ROOM:
		# Каждая колонна комнаты должна на что-то опираться.
		for x in range(r.position.x, r.end.x):
			var below := Vector2i(x, r.end.y)
			var ok := interior.has(below) or not world.is_revealed(below.x, below.y) \
				or Mat.is_solid(world.get_mat(below.x, below.y))
			if not ok:
				return "Комнате не на что опереться — нужен грунт или постройка снизу"
	return ""


func create_project(kind: int, r: Rect2i) -> Project:
	if not validate(kind, r).is_empty():
		return null
	var p := Project.new()
	p.id = next_project_id
	next_project_id += 1
	p.kind = kind
	p.rect = r
	projects.append(p)
	_register_room(p)
	_check_phase(p)
	return p


func set_paused(p: Project, on: bool) -> void:
	p.paused = on
	if not on and p.blocked.begins_with("В зоне"):
		_check_liquids(p)
	_log("%s: %s" % [p.title(), "пауза" if on else "работы возобновлены"], "info")


func cancel_project(p: Project) -> void:
	if p.phase == Project.Phase.DONE:
		return
	if p.paid:
		# Возвращаем неизрасходованную часть материалов.
		var left := 1.0 - p.build_done / p.build_work()
		var refund := p.cost()
		for k in refund:
			_add(k, int(floor(refund[k] * left)))
	projects.erase(p)
	for c in p.cells():
		room_cells.erase(c)
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s отменена" % p.title(), "info")


func _register_room(p: Project) -> void:
	if p.kind == Project.Kind.ROOM:
		for c in p.cells():
			room_cells[c] = p.id


func remaining_dig(p: Project) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in p.cells():
		if Mat.is_solid(world.get_mat(c.x, c.y)):
			out.append(c)
	return out


## Базовое время копки клетки (для жителя с навыком 1).
func dig_time(c: Vector2i) -> float:
	var m := world.get_mat(c.x, c.y)
	var t := Mat.hardness(m) * Env.heat_work_factor(Env.temperature(c.y, world.gen.surface_y(c.x)))
	# Порода с полезными ископаемыми добывается аккуратнее — дольше.
	if NOTABLE.has(Mat.resource(m)):
		t *= 1.4
	return t


func _check_phase(p: Project) -> void:
	if p.phase != Project.Phase.DIG:
		return
	_check_liquids(p)
	if remaining_dig(p).is_empty():
		p.phase = Project.Phase.BUILD
		var lines: PackedStringArray = []
		for k in p.found:
			lines.append("%s %d" % [Mat.resource_name(k), p.found[k]])
		if lines.is_empty():
			_log("%s: копка завершена, начинаем строительство" % p.title(), "info")
		else:
			_log("%s: копка завершена. Найдено: %s" % [p.title(), ", ".join(lines)], "good")
		_try_pay(p)


func _check_liquids(p: Project) -> void:
	for c in p.cells():
		if world.is_revealed(c.x, c.y) and Mat.is_fluid(world.get_mat(c.x, c.y)):
			p.paused = true
			p.blocked = "В зоне стройки %s — отмените или дождитесь насосов" % Mat.name_of(world.get_mat(c.x, c.y)).to_lower()
			return
	if p.blocked.begins_with("В зоне"):
		p.blocked = ""


func _try_pay(p: Project) -> void:
	if p.paid or p.phase != Project.Phase.BUILD:
		return
	var cost := p.cost()
	var lacking: PackedStringArray = []
	for k in cost:
		var have: int = inventory.get(k, 0)
		if have < cost[k]:
			lacking.append("%s %d" % [Mat.resource_name(k).to_lower(), cost[k] - have])
	if not lacking.is_empty():
		var msg := "Не хватает: " + ", ".join(lacking)
		if p.blocked != msg:
			p.blocked = msg
			_log("%s ждёт материалы. %s" % [p.title(), msg], "warning")
		return
	for k in cost:
		inventory[k] -= cost[k]
	p.paid = true
	p.blocked = ""


func _finish_project(p: Project) -> void:
	p.phase = Project.Phase.DONE
	p.blocked = ""
	for c in p.cells():
		interior[c] = p.id
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("Построено: %s" % p.title(), "good")


func waiting_for_materials() -> bool:
	for p in projects:
		if p.phase == Project.Phase.BUILD and not p.paid and not p.paused:
			return true
	return false


# --- Сбор ресурсов на поверхности -------------------------------------------------

func toggle_harvest(x: int) -> bool:
	if world.feature_at(x) == WorldGen.FEATURE_NONE:
		return false
	world.set_feature_mark(x, not world.feature_marks.has(x))
	return true


func _complete_harvest(x: int, u: Unit) -> void:
	var y: Array = world.gen.feature_yield(x)
	var kind := world.feature_at(x)
	harvest_progress.erase(x)
	world.remove_feature(x)
	if y[1] > 0:
		_add(y[0], y[1])
		var what := "срубил дерево" if kind == WorldGen.FEATURE_TREE else "разбил валун"
		if u != null and u.sex == Unit.Sex.FEMALE:
			what = "срубила дерево" if kind == WorldGen.FEATURE_TREE else "разбила валун"
		_log("%s %s: +%d %s" % [u.name if u != null else "Жители", what, y[1], Mat.resource_name(y[0]).to_lower()], "info")


# --- Копка -----------------------------------------------------------------------

func _complete_dig(c: Vector2i, p: Project, u: Unit) -> void:
	var m := world.get_mat(c.x, c.y)
	dig_progress.erase(c)
	world.set_dug(c.x, c.y)
	cells_dug += 1
	var key := Mat.resource(m)
	if not key.is_empty():
		var amount := 1
		if Mat.is_ore(m):
			var depth := c.y - world.gen.surface_y(c.x)
			amount = 1 + int(WorldGen.hash01(c.x, c.y, 17) * (2.0 + depth / 250.0))
		_add(key, amount)
		if p != null:
			p.found[key] = p.found.get(key, 0) + amount
		if NOTABLE.has(key):
			_log("%s %s: %s ×%d (глубина %s)" % [
				u.name if u != null else "Жители", "нашла" if u != null and u.sex == Unit.Sex.FEMALE else "нашёл",
				Mat.resource_name(key).to_lower(), amount, _depth_text(c)], "good")
	_note_discovery(m, c)
	# Дерево или валун над выкопанной клеткой падают.
	if c.y == world.gen.surface_y(c.x) and world.feature_at(c.x) != WorldGen.FEATURE_NONE:
		var y: Array = world.gen.feature_yield(c.x)
		world.remove_feature(c.x)
		_add(y[0], y[1])
	var hazards := {}
	for n in world.reveal_around(c.x, c.y):
		var nm := world.get_mat(n.x, n.y)
		_note_discovery(nm, n)
		if Mat.is_fluid(nm) and not hazards.has(nm):
			hazards[nm] = n
	for hm in hazards:
		_report_hazard(hm, hazards[hm])
	match Mat.hazard(m):
		Mat.Hazard.GAS:
			_log("Выброс метана на глубине %s! Нужна вентиляция." % _depth_text(c), "danger")
		Mat.Hazard.WATER:
			_log("Из водоносного пласта сочится вода (глубина %s)." % _depth_text(c), "warning")
	for other in projects:
		if other.phase == Project.Phase.DIG:
			_check_phase(other)


func _report_hazard(m: int, c: Vector2i) -> void:
	if m == Mat.MAGMA:
		_log("КАТАСТРОФА: прорыв к магме на глубине %s! Температура %d °C." % [
			_depth_text(c), int(Env.temperature(c.y, world.gen.surface_y(c.x)))], "danger")
	else:
		_log("Вскрыта подземная полость с водой (глубина %s)." % _depth_text(c), "warning")


func _note_discovery(m: int, c: Vector2i) -> void:
	if discovered.has(m):
		return
	discovered[m] = true
	if Mat.is_ore(m) or m == Mat.ROCK_SALT or m == Mat.KIMBERLITE:
		_log("Новая находка: %s на глубине %s!" % [Mat.name_of(m), _depth_text(c)], "good")


# --- Онлайн-симуляция -------------------------------------------------------------

func update(dt: float) -> void:
	var remaining := dt
	while remaining > 0.0:
		var step := minf(remaining, SUBSTEP)
		remaining -= step
		for p in projects:
			if not p.paused:
				_try_pay(p)
		for u in units:
			_update_unit(u, step)


func _update_unit(u: Unit, dt: float) -> void:
	u.anim += dt
	match u.state:
		Unit.State.IDLE:
			if not pathing.standable(u.cell()):
				u.state = Unit.State.FALL
				return
			u.retry -= dt
			if u.retry <= 0.0 and not _assign(u):
				u.retry = 1.5
		Unit.State.FALL:
			u.pos.x = roundf(u.pos.x)
			u.pos.y += FALL_SPEED * dt
			var c := Vector2i(roundi(u.pos.x), floori(u.pos.y))
			if pathing.standable(c):
				u.pos.y = c.y
				u.state = Unit.State.IDLE
		Unit.State.MOVE:
			if not _task_valid(u):
				_drop(u)
				return
			_move(u, dt)
		Unit.State.WORK:
			if not _task_valid(u):
				_drop(u)
				return
			_work(u, dt)


func _move(u: Unit, dt: float) -> void:
	var budget := dt
	while budget > 0.0 and u.path_i < u.path.size():
		var next := Vector2(u.path[u.path_i])
		var delta := next - u.pos
		var spd := CLIMB_SPEED if absf(delta.y) > absf(delta.x) else WALK_SPEED
		var dist := delta.length()
		if dist <= spd * budget:
			u.pos = next
			budget -= dist / spd
			u.path_i += 1
		else:
			u.pos += delta / dist * spd * budget
			budget = 0.0
		if absf(delta.x) > 0.01:
			u.facing = 1 if delta.x > 0 else -1
	if u.path_i >= u.path.size():
		u.state = Unit.State.WORK
		if u.task == Unit.Task.DIG or u.task == Unit.Task.HARVEST:
			if u.target.x != u.cell().x:
				u.facing = 1 if u.target.x > u.cell().x else -1


func _work(u: Unit, dt: float) -> void:
	var skill := Unit.skill_for(u.task)
	var before := u.level(skill)
	u.skills[skill] += dt
	if u.level(skill) > before:
		_log("%s: навык «%s» вырос до %d" % [u.name, Unit.SKILL_NAMES[skill], u.level(skill)], "good")
	var rate := dt * u.speed(skill)
	match u.task:
		Unit.Task.DIG:
			var c := u.target
			dig_progress[c] = dig_progress.get(c, 0.0) + rate
			if dig_progress[c] >= dig_time(c):
				var p := project_by_id(u.project_id)
				_drop(u)
				_complete_dig(c, p, u)
		Unit.Task.BUILD:
			var p := project_by_id(u.project_id)
			p.build_done += rate
			if p.build_done >= p.build_work():
				_finish_project(p)
		Unit.Task.HARVEST:
			var x := u.target.x
			harvest_progress[x] = harvest_progress.get(x, 0.0) + rate
			if harvest_progress[x] >= HARVEST_TIME.get(world.feature_at(x), 20.0):
				_drop(u)
				_complete_harvest(x, u)


func _task_valid(u: Unit) -> bool:
	match u.task:
		Unit.Task.DIG, Unit.Task.BUILD:
			var p := project_by_id(u.project_id)
			if p == null or p.paused:
				return false
			if u.task == Unit.Task.DIG:
				return p.phase == Project.Phase.DIG and Mat.is_solid(world.get_mat(u.target.x, u.target.y))
			return p.phase == Project.Phase.BUILD and p.paid
		Unit.Task.HARVEST:
			return world.feature_marks.has(u.target.x) and world.feature_at(u.target.x) != WorldGen.FEATURE_NONE
	return false


func _drop(u: Unit) -> void:
	var key = _reserve_key(u)
	if key != null and reserved.get(key) == u.id:
		reserved.erase(key)
	u.task = Unit.Task.NONE
	u.project_id = 0
	u.path.clear()
	u.path_i = 0
	if u.state != Unit.State.FALL:
		u.state = Unit.State.IDLE
	u.retry = 0.2


func _reserve_key(u: Unit) -> Variant:
	match u.task:
		Unit.Task.DIG:
			return u.target
		Unit.Task.HARVEST:
			return "h%d" % u.target.x
	return null


## Ищет работу для жителя. true — работа назначена.
func _assign(u: Unit) -> bool:
	var reach := pathing.explore(u.cell())
	var parents: Dictionary = reach[0]
	var dist: Dictionary = reach[1]
	var harvest_first := waiting_for_materials()
	if harvest_first and _try_harvest(u, parents, dist):
		return true
	for p in projects:
		if p.paused:
			continue
		if p.phase == Project.Phase.DIG and _try_dig(u, p, parents, dist):
			return true
		if p.phase == Project.Phase.BUILD and p.paid and _try_build(u, p, parents, dist):
			return true
	if not harvest_first and _try_harvest(u, parents, dist):
		return true
	return false


func _start(u: Unit, task: int, target: Vector2i, stand: Vector2i, pid: int, parents: Dictionary) -> void:
	u.task = task
	u.target = target
	u.project_id = pid
	u.path = Pathing.path_to(parents, stand)
	u.path_i = 0
	u.state = Unit.State.MOVE
	var key = _reserve_key(u)
	if key != null:
		reserved[key] = u.id


## Откуда житель может работать с клеткой c: стоя рядом (ноги или голова у клетки).
func _work_spot(c: Vector2i, dist: Dictionary) -> Array:
	var best := [null, 1 << 30]
	for d in DIRS4:
		var n := c + d
		for stand in [n, n + Vector2i(0, 1)]:
			if dist.has(stand) and dist[stand] < best[1]:
				best = [stand, dist[stand]]
	return best


func _try_dig(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	var best_cell = null
	var best_stand = null
	var best_d := 1 << 30
	var any_free := false
	for c in remaining_dig(p):
		if reserved.has(c):
			continue
		any_free = true
		var spot := _work_spot(c, dist)
		if spot[0] != null and spot[1] < best_d:
			best_d = spot[1]
			best_cell = c
			best_stand = spot[0]
	if best_cell == null:
		# «Нет доступа» — только если к стройке вообще никто не подобрался.
		var someone_working := false
		for other in units:
			if other.project_id == p.id:
				someone_working = true
		if any_free and not someone_working and p.blocked.is_empty():
			p.blocked = "Нет доступа — проложите тоннель к стройке"
		return false
	if p.blocked.begins_with("Нет доступа"):
		p.blocked = ""
	_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
	return true


func _try_build(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	var area := p.rect.grow(1)
	var best = null
	var best_d := 1 << 30
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if dist.has(c) and dist[c] < best_d:
				best_d = dist[c]
				best = c
	if best == null:
		return false
	_start(u, Unit.Task.BUILD, p.rect.get_center(), best, p.id, parents)
	return true


func _try_harvest(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var best_x = null
	var best_stand = null
	var best_d := 1 << 30
	for x in world.feature_marks:
		if reserved.has("h%d" % x):
			continue
		var base := Vector2i(x, world.gen.surface_y(x) - 1)
		for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
			if dist.has(stand) and dist[stand] < best_d:
				best_d = dist[stand]
				best_x = x
				best_stand = stand
	if best_x == null:
		return false
	_start(u, Unit.Task.HARVEST, Vector2i(best_x, world.gen.surface_y(best_x) - 1), best_stand, 0, parents)
	return true


# --- Оффлайн-симуляция --------------------------------------------------------------

## Упрощённая модель: жители не ходят, а сразу работают с меньшей эффективностью.
## Возвращает число выкопанных клеток.
func advance_offline(dt: float) -> int:
	for u in units:
		_drop(u)
	var dug_before := cells_dug
	var remaining := dt
	var guard := 200000
	while remaining > 0.001 and guard > 0:
		guard -= 1
		for p in projects:
			if not p.paused:
				_try_pay(p)
		# цель -> [вид, суммарная скорость, первый житель, проект]
		var jobs := {}
		var taken := {}
		for u in units:
			var job := _offline_job(u, taken)
			if job.is_empty():
				continue
			var key = job[0]
			var skill := Unit.skill_for(job[1])
			var rate := u.speed(skill) * OFFLINE_EFFICIENCY
			if jobs.has(key):
				jobs[key][1] += rate
			else:
				jobs[key] = [job[1], rate, u, job[2]]
			u.task = job[1]
		if jobs.is_empty():
			break
		var step := remaining
		for key in jobs:
			step = minf(step, _offline_left(key, jobs[key]) / jobs[key][1])
		step = maxf(step, 0.0)
		remaining -= step
		for u in units:
			if u.task != Unit.Task.NONE:
				u.skills[Unit.skill_for(u.task)] += step
				u.task = Unit.Task.NONE
		for key in jobs:
			var j: Array = jobs[key]
			match j[0]:
				Unit.Task.DIG:
					dig_progress[key] = dig_progress.get(key, 0.0) + j[1] * step
					if dig_progress[key] >= dig_time(key) - 0.001:
						_complete_dig(key, j[3], j[2])
				Unit.Task.BUILD:
					var p: Project = j[3]
					p.build_done += j[1] * step
					if p.build_done >= p.build_work() - 0.001:
						_finish_project(p)
				Unit.Task.HARVEST:
					var x: int = int(key.substr(1))
					harvest_progress[x] = harvest_progress.get(x, 0.0) + j[1] * step
					if harvest_progress[x] >= HARVEST_TIME.get(world.feature_at(x), 20.0) - 0.001:
						_complete_harvest(x, j[2])
	return cells_dug - dug_before


func _offline_left(key: Variant, job: Array) -> float:
	match job[0]:
		Unit.Task.DIG:
			return dig_time(key) - dig_progress.get(key, 0.0)
		Unit.Task.BUILD:
			var p: Project = job[3]
			return p.build_work() - p.build_done
		Unit.Task.HARVEST:
			var x: int = int(key.substr(1))
			return HARVEST_TIME.get(world.feature_at(x), 20.0) - harvest_progress.get(x, 0.0)
	return 0.0


## [ключ цели, вид задачи, проект] или [] если работы нет.
func _offline_job(u: Unit, taken: Dictionary) -> Array:
	var harvest_first := waiting_for_materials()
	if harvest_first:
		var h := _offline_harvest(taken)
		if not h.is_empty():
			return h
	for p in projects:
		if p.paused:
			continue
		if p.phase == Project.Phase.DIG:
			for c in remaining_dig(p):
				if taken.has(c):
					continue
				for d in DIRS4:
					if world.is_open(c.x + d.x, c.y + d.y):
						taken[c] = true
						return [c, Unit.Task.DIG, p]
		elif p.phase == Project.Phase.BUILD and p.paid:
			return ["b%d" % p.id, Unit.Task.BUILD, p]
	if not harvest_first:
		return _offline_harvest(taken)
	return []


func _offline_harvest(taken: Dictionary) -> Array:
	for x in world.feature_marks:
		var key := "h%d" % x
		if not taken.has(key):
			taken[key] = true
			return [key, Unit.Task.HARVEST, null]
	return []


# --- Вспомогательное ----------------------------------------------------------------

func _add(key: String, amount: int) -> void:
	if key.is_empty() or amount <= 0:
		return
	inventory[key] = inventory.get(key, 0) + amount


func _depth_text(c: Vector2i) -> String:
	return "%s м" % Fmt.int_spaced(c.y - world.gen.surface_y(c.x))


func _log(text: String, kind: String) -> void:
	event_logged.emit(text, kind)


# --- Сохранение -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var dp := []
	for c in dig_progress:
		dp.append([c.x, c.y, dig_progress[c]])
	var hp := []
	for x in harvest_progress:
		hp.append([x, harvest_progress[x]])
	var ps := []
	for p in projects:
		ps.append(p.to_dict())
	var us := []
	for u in units:
		us.append(u.to_dict())
	return {
		"inventory": inventory,
		"cells_dug": cells_dug,
		"discovered": discovered.keys(),
		"dig_progress": dp,
		"harvest_progress": hp,
		"projects": ps,
		"units": us,
		"next_project_id": next_project_id,
		"next_unit_id": next_unit_id,
	}


func load_dict(d: Dictionary) -> void:
	inventory.clear()
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		inventory[k] = int(inv[k])
	cells_dug = int(d.get("cells_dug", 0))
	for m in d.get("discovered", []):
		discovered[int(m)] = true
	for e in d.get("dig_progress", []):
		dig_progress[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("harvest_progress", []):
		harvest_progress[int(e[0])] = float(e[1])
	for pd in d.get("projects", []):
		var p := Project.from_dict(pd)
		projects.append(p)
		_register_room(p)
		if p.phase == Project.Phase.DONE:
			for c in p.cells():
				interior[c] = p.id
	for ud in d.get("units", []):
		units.append(Unit.from_dict(ud))
	next_project_id = int(d.get("next_project_id", projects.size() + 1))
	next_unit_id = int(d.get("next_unit_id", units.size() + 1))
