class_name DigSystem
extends RefCounted
## Очередь раскопок. Бригады копают параллельно; симуляция идёт и оффлайн
## (advance() вызывается с прошедшим временем при входе в игру).

signal event_logged(text: String, kind: String)

const DIRS4: Array[Vector2i] = WorldData.DIRS4

var world: WorldData
var crews := 2
## Порядок заказов.
var order: Array[Vector2i] = []
## Vector2i -> затраченное время, сек.
var progress := {}
var inventory := {}
var cells_dug := 0
## Типы материалов, которые игрок уже находил (для сообщений о первой находке).
var discovered := {}


func _init(p_world: WorldData) -> void:
	world = p_world


func has_job(c: Vector2i) -> bool:
	return progress.has(c)


## Можно ли поставить клетку в очередь: она твёрдая (или ещё неизвестна)
## и примыкает к открытому пространству или к уже заказанной клетке.
func can_order(c: Vector2i) -> bool:
	if progress.has(c):
		return false
	if world.is_revealed(c.x, c.y) and not Mat.is_diggable(world.get_mat(c.x, c.y)):
		return false
	for d in DIRS4:
		var n := c + d
		if progress.has(n) or world.is_open(n.x, n.y):
			return true
	return false


func add_order(c: Vector2i) -> bool:
	if not can_order(c):
		return false
	order.append(c)
	progress[c] = 0.0
	return true


func cancel_order(c: Vector2i) -> void:
	if progress.erase(c):
		order.erase(c)


func toggle_order(c: Vector2i) -> void:
	if progress.has(c):
		cancel_order(c)
	else:
		add_order(c)


func is_workable(c: Vector2i) -> bool:
	for d in DIRS4:
		var n := c + d
		if world.is_open(n.x, n.y):
			return true
	return false


func dig_time(c: Vector2i) -> float:
	var m := world.get_mat(c.x, c.y)
	var temp := Env.temperature(c.y, world.gen.surface_y(c.x))
	return Mat.hardness(m) * Env.heat_work_factor(temp)


## Клетки, над которыми бригады работают прямо сейчас.
func active_jobs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in order:
		if out.size() >= crews:
			break
		if is_workable(c):
			out.append(c)
	return out


## Продвигает работы на dt секунд. Возвращает число выкопанных клеток.
func advance(dt: float) -> int:
	var done := 0
	var remaining := dt
	var guard := 100000
	while remaining > 0.0 and guard > 0:
		guard -= 1
		var active := active_jobs()
		if active.is_empty():
			break
		var step := remaining
		var needs := {}
		for c in active:
			needs[c] = dig_time(c)
			step = minf(step, needs[c] - progress[c])
		step = maxf(step, 0.0)
		remaining -= step
		for c in active:
			progress[c] += step
			if progress[c] >= needs[c] - 0.0001:
				_complete(c)
				done += 1
	return done


func _complete(c: Vector2i) -> void:
	var m := world.get_mat(c.x, c.y)
	cancel_order(c)
	world.set_dug(c.x, c.y)
	cells_dug += 1
	_add_resource(m, c)
	_note_discovery(m, c)
	var hazards := {}
	for n in world.reveal_around(c.x, c.y):
		var nm := world.get_mat(n.x, n.y)
		_note_discovery(nm, n)
		if (nm == Mat.WATER or nm == Mat.MAGMA) and not hazards.has(nm):
			hazards[nm] = n
	for hm in hazards:
		_check_hazard(hm, hazards[hm])
	# Заказы, оказавшиеся на жидкости, отменяются.
	for job in order.duplicate():
		if world.is_revealed(job.x, job.y) and not Mat.is_diggable(world.get_mat(job.x, job.y)):
			cancel_order(job)
	match Mat.hazard(m):
		Mat.Hazard.GAS:
			_log("Выброс метана на глубине %s! Нужна вентиляция." % _depth_text(c), "danger")
		Mat.Hazard.WATER:
			_log("Из водоносного пласта сочится вода (глубина %s)." % _depth_text(c), "warning")
		Mat.Hazard.OIL:
			_log("Вскрыт нефтеносный пласт на глубине %s." % _depth_text(c), "info")


func _add_resource(m: int, c: Vector2i) -> void:
	var key := Mat.resource(m)
	if key.is_empty():
		return
	var amount := 1
	if Mat.is_ore(m):
		# Богатство руды растёт с глубиной.
		var depth := c.y - world.gen.surface_y(c.x)
		amount = 1 + int(WorldGen.hash01(c.x, c.y, 17) * (2.0 + depth / 250.0))
	inventory[key] = inventory.get(key, 0) + amount


func _note_discovery(m: int, c: Vector2i) -> void:
	if discovered.has(m):
		return
	discovered[m] = true
	if Mat.is_ore(m) or m == Mat.ROCK_SALT or m == Mat.KIMBERLITE:
		_log("Новая находка: %s на глубине %s!" % [Mat.name_of(m), _depth_text(c)], "good")


func _check_hazard(m: int, c: Vector2i) -> void:
	match m:
		Mat.WATER:
			_log("Вскрыта подземная полость с водой (глубина %s)." % _depth_text(c), "warning")
		Mat.MAGMA:
			_log("КАТАСТРОФА: прорыв к магме на глубине %s! Температура %d °C." % [
				_depth_text(c), int(Env.temperature(c.y, world.gen.surface_y(c.x)))], "danger")


func _depth_text(c: Vector2i) -> String:
	return "%s м" % Fmt.int_spaced(c.y - world.gen.surface_y(c.x))


func _log(text: String, kind: String) -> void:
	event_logged.emit(text, kind)
