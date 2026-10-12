class_name Colony
extends RefCounted
## Колония: жители, стройки, комнаты, склад.
## Жители сами разбирают работу: сначала потребности (сон, еда), потом работа
## по профессии, потом любая другая. Онлайн они ходят и работают по-настоящему
## (update), оффлайн — упрощённо (advance_offline).

signal event_logged(text: String, kind: String)

const START_UNITS := 5
## Ресурсов на старте нет — их сначала нужно собрать.
const START_INVENTORY := {}
const SUBSTEP := 0.2
const WALK_SPEED := 3.0
const CLIMB_SPEED := 1.6
const FALL_SPEED := 8.0
const OFFLINE_EFFICIENCY := 0.75
const OFFLINE_STEP := 30.0
const HARVEST_TIME := {WorldGen.FEATURE_TREE: 20.0, WorldGen.FEATURE_BOULDER: 25.0, WorldGen.FEATURE_BUSH: 10.0}
const DIRS4: Array[Vector2i] = WorldData.DIRS4
## Ресурсы, о находке которых сообщаем сразу.
const NOTABLE := ["coal", "iron", "copper", "silver", "gold", "uranium", "diamond", "salt", "oil"]

# Потребности (в секунду реального времени).
const SATIETY_DECAY := 100.0 / 1800.0
const ENERGY_DECAY := 100.0 / 2700.0
const SLEEP_BED := 100.0 / 360.0
const SLEEP_FLOOR := 100.0 / 720.0
const EAT_TIME := 6.0
const MEAL := 55.0
const MEAL_DINING := 100.0
const HUNGRY := 35.0
const TIRED := 20.0
## Как долго фермер работает, прежде чем пересмотреть занятия.
const FARM_SHIFT := 60.0
# Семьи.
const SOCIAL_TICK := 20.0
const PREGNANCY_TIME := 900.0

var world: WorldData
var pathing: Pathing
var units: Array[Unit] = []
var projects: Array[Project] = []
var inventory := {}
## Ресурсы, которые колония хоть раз получала (открывают материалы стройки).
var known_resources := {}
## Клетки готовых построек: Vector2i -> id проекта.
var interior := {}
## Клетки комнат, где ходят по полу (без колонны лестницы). Vector2i -> id проекта.
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
var rng := RandomNumberGenerator.new()
## Клетка базы на поверхности: возле неё кучи ресурсов и отвал.
var home := Vector2i.ZERO
var _social_t := 0.0
var _full_warned := {}


func _init(p_world: WorldData) -> void:
	world = p_world
	pathing = Pathing.new(world, interior, room_cells)
	rng.seed = world.gen.world_seed + 12345


# --- Начало игры ----------------------------------------------------------------

func start_new(home_x: int) -> void:
	inventory = START_INVENTORY.duplicate()
	home = Vector2i(home_x, world.gen.surface_y(home_x))
	var sexes := [Unit.Sex.MALE, Unit.Sex.FEMALE, Unit.Sex.MALE, Unit.Sex.FEMALE]
	sexes.append(rng.randi_range(0, 1))
	for i in START_UNITS:
		var x := home_x - 2 + i
		var u := _new_unit(sexes[i], Vector2(x, world.gen.surface_y(x) - 1))
		# Небольшие врождённые склонности.
		for k in u.skills:
			u.skills[k] = rng.randf_range(0.0, 200.0)
		u.energy = rng.randf_range(70.0, 100.0)
		u.satiety = rng.randf_range(65.0, 90.0)


func _new_unit(sex: int, pos: Vector2) -> Unit:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.sex = sex
	u.name = _free_name(sex)
	u.look = rng.randf()
	u.pos = pos
	units.append(u)
	return u


func _free_name(sex: int) -> String:
	var names: Array = Unit.MALE_NAMES if sex == Unit.Sex.MALE else Unit.FEMALE_NAMES
	var used := {}
	for u in units:
		used[u.name] = true
	var free := names.filter(func(n: String) -> bool: return not used.has(n))
	if not free.is_empty():
		return free[rng.randi_range(0, free.size() - 1)]
	var base: String = names[rng.randi_range(0, names.size() - 1)]
	var k := 2
	while used.has("%s %d" % [base, k]):
		k += 1
	return "%s %d" % [base, k]


func unit_by_id(uid: int) -> Unit:
	for u in units:
		if u.id == uid:
			return u
	return null


func adults() -> int:
	var n := 0
	for u in units:
		if not u.child:
			n += 1
	return n


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


## Материалы стен, доступные колонии: дерево сразу, остальное — когда добыто.
func available_materials() -> Array[String]:
	var out: Array[String] = ["wood"]
	for k in ["clay", "stone"]:
		if known_resources.has(k):
			out.append(k)
	return out


## Сколько жителей могут одновременно пройти тоннелем (по его ширине).
static func tunnel_lanes(r: Rect2i) -> int:
	if r.size.y > r.size.x:
		return maxi(1, r.size.x)
	return maxi(1, r.size.y - 1)


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
	if kind == Project.Kind.TUNNEL:
		for x in range(r.position.x, r.end.x):
			if r.position.y < world.gen.surface_y(x):
				return "Тоннели — только под землёй. Над землёй стройте комнаты"
	if kind == Project.Kind.ROOM:
		# Каждая колонна комнаты должна на что-то опираться.
		for x in range(r.position.x, r.end.x):
			var below := Vector2i(x, r.end.y)
			var ok := interior.has(below) or not world.is_revealed(below.x, below.y) \
				or Mat.is_solid(world.get_mat(below.x, below.y))
			if not ok:
				return "Комнате не на что опереться — нужен грунт или постройка снизу"
			# Второй этаж: в нижнем здании нужна лестница наверх.
			var lower := project_at(below)
			if lower != null and lower.kind == Project.Kind.ROOM and not lower.ladder:
				return "В нижнем здании нет лестницы — выберите его и нажмите «Лестница»"
	return ""


## Пол комнаты ниже поверхности земли — без лестницы из неё не выбраться.
func _floor_below_surface(r: Rect2i) -> bool:
	var floor_y := r.end.y - 1
	for x in range(r.position.x - 1, r.end.x + 1):
		if floor_y >= world.gen.surface_y(x):
			return true
	return false


func workers_on(p: Project) -> int:
	var n := 0
	for u in units:
		if u.project_id == p.id and u.task != Unit.Task.SLEEP and u.task != Unit.Task.EAT:
			n += 1
	return n


## Столбцы объектов поверхности, которые пересекаются с зоной.
func features_in(r: Rect2i) -> Array[int]:
	var out: Array[int] = []
	for x in range(r.position.x - 1, r.end.x + 1):
		var f := world.feature_at(x)
		if f == WorldGen.FEATURE_NONE:
			continue
		var base := world.gen.surface_y(x) - 1
		var top := base - (world.gen.tree_height(x) if f == WorldGen.FEATURE_TREE else 0)
		var left := x - (1 if f == WorldGen.FEATURE_TREE else 0)
		var right := x + (1 if f == WorldGen.FEATURE_TREE else 0)
		if right >= r.position.x and left < r.end.x and base >= r.position.y and top < r.end.y:
			out.append(x)
	return out


func uncleared(p: Project) -> Array[int]:
	var out: Array[int] = []
	for x in p.clear_x:
		if world.feature_at(x) != WorldGen.FEATURE_NONE:
			out.append(x)
	return out


## Есть ли у зоны выход к открытому пространству или к другой стройке.
func has_access(r: Rect2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if world.is_open(x, y) or (not r.has_point(Vector2i(x, y)) and project_at(Vector2i(x, y)) != null):
				return true
	return false


func create_project(kind: int, r: Rect2i, workers := -1, material := "wood") -> Project:
	if not validate(kind, r).is_empty():
		return null
	var p := Project.new()
	p.id = next_project_id
	next_project_id += 1
	p.kind = kind
	p.rect = r
	p.material = material if kind == Project.Kind.ROOM else "wood"
	p.workers = workers if workers > 0 else Project.recommended_workers(kind, r, adults())
	p.ladder = kind == Project.Kind.ROOM and _floor_below_surface(r)
	# Деревья, кусты и валуны на месте стройки убираются на этапе 1 — как ресурс.
	for x in features_in(r):
		p.clear_x.append(x)
		world.set_feature_mark(x, true)
	projects.append(p)
	_check_phase(p)
	return p


func set_paused(p: Project, on: bool) -> void:
	p.paused = on
	if not on and p.blocked.begins_with("В зоне"):
		_check_liquids(p)
	_log("%s: %s" % [p.title(), "пауза" if on else "работы возобновлены"], "info")


func cancel_project(p: Project) -> void:
	if p.phase == Project.Phase.EQUIP:
		cancel_equip(p)
		return
	if p.phase == Project.Phase.DONE:
		return
	if p.paid:
		# Возвращаем неизрасходованную часть материалов.
		_refund(p.cost(), 1.0 - p.build_done / p.build_work())
	projects.erase(p)
	for c in p.cells():
		room_cells.erase(c)
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s отменена" % p.title(), "info")


func _refund(cost: Dictionary, part: float) -> void:
	for k in cost:
		_add(k, int(floor(cost[k] * part)))


## Пока комнату копают, в ней леса — по ним можно лазить. Потом ходят по полу;
## у заглублённой комнаты остаётся лестница у левой стены.
func _register_room(p: Project) -> void:
	if p.kind != Project.Kind.ROOM or p.phase == Project.Phase.DIG:
		return
	for c in p.cells():
		if not (p.ladder and c.x == p.rect.position.x):
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
	if remaining_dig(p).is_empty() and uncleared(p).is_empty():
		p.phase = Project.Phase.BUILD
		_register_room(p)
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


## Списывает материалы этапа строительства или обустройства, если их хватает.
func _try_pay(p: Project) -> void:
	var cost: Dictionary
	if p.phase == Project.Phase.BUILD and not p.paid:
		cost = p.cost()
	elif p.phase == Project.Phase.EQUIP and not p.equip_paid:
		cost = RoomType.job_cost(p)
	else:
		return
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
	if p.phase == Project.Phase.BUILD:
		p.paid = true
	else:
		p.equip_paid = true
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
	if p.kind == Project.Kind.ROOM:
		_log("Построено: %s. Выберите назначение комнаты." % p.title(), "good")
	else:
		_log("Построено: %s" % p.title(), "good")


func waiting_for_materials() -> bool:
	for p in projects:
		if p.paused:
			continue
		if (p.phase == Project.Phase.BUILD and not p.paid) or (p.phase == Project.Phase.EQUIP and not p.equip_paid):
			return true
	return false


# --- Назначение комнат -------------------------------------------------------------

## Начинает обустройство готовой комнаты под назначение t.
func set_purpose(p: Project, t: int) -> bool:
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE or t == p.purpose:
		return false
	_release_beds(p)
	p.equip_ladder = false
	p.equip_target = t
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	if t == RoomType.NONE:
		_finish_equip(p)
		return true
	_log("%s: обустройство под «%s»" % [p.title(), RoomType.NAMES[t]], "info")
	_try_pay(p)
	return true


## Строит лестницу в готовой комнате (нужна для второго этажа и выхода наверх).
func add_ladder(p: Project) -> bool:
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE or p.ladder:
		return false
	p.equip_ladder = true
	p.equip_target = p.purpose
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	_log("%s: строим лестницу" % p.title(), "info")
	_try_pay(p)
	return true


func cancel_equip(p: Project) -> void:
	if p.phase != Project.Phase.EQUIP:
		return
	if p.equip_paid:
		_refund(RoomType.job_cost(p), 1.0 - p.equip_done / RoomType.job_work(p))
	p.phase = Project.Phase.DONE
	if not p.equip_ladder:
		p.purpose = RoomType.NONE
	p.equip_ladder = false
	p.blocked = ""
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s: обустройство отменено" % p.title(), "info")


func _finish_equip(p: Project) -> void:
	p.phase = Project.Phase.DONE
	p.blocked = ""
	if p.equip_ladder:
		p.equip_ladder = false
		p.ladder = true
		_release_beds(p)
		for c in p.cells():
			if c.x == p.rect.position.x:
				room_cells.erase(c)
		for u in units:
			if u.project_id == p.id:
				_drop(u)
		_log("%s: лестница готова" % p.title(), "good")
		return
	p.purpose = p.equip_target
	p.farm_progress = 0.0
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	if p.purpose == RoomType.STORAGE:
		_full_warned.clear()
	if p.purpose != RoomType.NONE:
		_log("Готово: %s (%s)" % [p.title(), RoomType.HINTS[p.purpose]], "good")


func rooms_of(t: int) -> Array[Project]:
	var out: Array[Project] = []
	for p in projects:
		if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == t:
			out.append(p)
	return out


func capacity(key: String) -> int:
	if RoomType.BULK.has(key):
		return 1 << 30
	return RoomType.BASE_CAPACITY + storage_capacity(key)


## Вместимость складов для ресурса (без кучи на земле).
func storage_capacity(key: String) -> int:
	var c := 0
	for p in rooms_of(RoomType.STORAGE):
		if RoomType.stores(p, key):
			c += RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p)
	return c


## Сколько ресурса лежит на складах, сколько — кучей на земле.
func stored_split(key: String) -> Vector2i:
	var have: int = inventory.get(key, 0)
	var inside := mini(have, storage_capacity(key))
	return Vector2i(inside, have - inside)


func set_store_filter(p: Project, keys: Array[String]) -> void:
	p.store_filter = keys
	_full_warned.clear()


func beds_total() -> int:
	var n := 0
	for p in rooms_of(RoomType.HOME):
		n += RoomType.beds(p)
	return n


func pregnant_count() -> int:
	var n := 0
	for u in units:
		if u.pregnancy >= 0.0:
			n += 1
	return n


## Клетка пола, где стоит кровать (index с 1).
static func bed_cell(p: Project, index: int) -> Vector2i:
	return Vector2i(RoomType.floor_start(p) + (index - 1) * 2, p.rect.end.y - 1)


func _claim_bed(u: Unit) -> void:
	if u.bed_room != 0 and project_by_id(u.bed_room) != null:
		return
	u.bed_room = 0
	var taken := {}
	for o in units:
		if o.bed_room != 0:
			taken["%d:%d" % [o.bed_room, o.bed_index]] = true
	for p in rooms_of(RoomType.HOME):
		for i in range(1, RoomType.beds(p) + 1):
			if not taken.has("%d:%d" % [p.id, i]):
				u.bed_room = p.id
				u.bed_index = i
				return


func _release_beds(p: Project) -> void:
	for u in units:
		if u.bed_room == p.id:
			u.bed_room = 0
			u.bed_index = 0


func food_low() -> bool:
	return inventory.get("food", 0) < units.size() * 3


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
		var fem := u != null and u.sex == Unit.Sex.FEMALE
		var what := "собрал ягоды"
		match kind:
			WorldGen.FEATURE_TREE:
				what = "срубила дерево" if fem else "срубил дерево"
			WorldGen.FEATURE_BOULDER:
				what = "разбила валун" if fem else "разбил валун"
			_:
				what = "собрала ягоды" if fem else "собрал ягоды"
		_log("%s %s: +%d %s" % [u.name if u != null else "Жители", what, y[1], Mat.resource_name(y[0]).to_lower()], "info")
	for p in projects:
		if p.phase == Project.Phase.DIG:
			_check_phase(p)


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


# --- Жизнь: потребности, взросление, семьи ---------------------------------------------

func _life_tick(dt: float, offline: bool) -> void:
	for u in units.duplicate():
		u.satiety = maxf(0.0, u.satiety - SATIETY_DECAY * dt)
		if u.task != Unit.Task.SLEEP:
			u.energy = maxf(0.0, u.energy - ENERGY_DECAY * dt)
		if offline:
			# Оффлайн жители сами едят и спят по расписанию.
			var portion := 2 if u.child else 1
			if u.satiety < HUNGRY + 5.0 and inventory.get("food", 0) >= portion:
				inventory["food"] -= portion
				u.satiety = minf(100.0, u.satiety + (MEAL_DINING if not rooms_of(RoomType.DINING).is_empty() else MEAL))
			u.energy = maxf(u.energy, 60.0)
		if u.child:
			u.age += dt
			if u.age >= Unit.CHILD_TIME:
				u.child = false
				_log("%s %s — теперь может работать" % [u.name, "выросла" if u.sex == Unit.Sex.FEMALE else "вырос"], "good")
		if u.pregnancy >= 0.0:
			u.pregnancy += dt
			if u.pregnancy >= PREGNANCY_TIME:
				_birth(u)
	_social_t += dt
	while _social_t >= SOCIAL_TICK:
		_social_t -= SOCIAL_TICK
		_social()


func _social() -> void:
	if beds_total() == 0:
		return
	# Пары складываются, когда есть где жить.
	for f in units:
		if f.child or f.sex != Unit.Sex.FEMALE or f.partner_id != 0 or f.mood() < 45.0:
			continue
		for m in units:
			if m.child or m.sex != Unit.Sex.MALE or m.partner_id != 0 or m.mood() < 45.0:
				continue
			if rng.randf() < 0.2:
				f.partner_id = m.id
				m.partner_id = f.id
				_log("%s и %s стали парой" % [f.name, m.name], "good")
			break
	# Дети — только если есть свободная кровать и еда.
	for f in units:
		if f.child or f.sex != Unit.Sex.FEMALE or f.pregnancy >= 0.0 or f.partner_id == 0:
			continue
		var partner := unit_by_id(f.partner_id)
		if partner == null:
			f.partner_id = 0
			continue
		var free_beds := beds_total() - units.size() - pregnant_count()
		if free_beds <= 0 or inventory.get("food", 0) < 3 or f.satiety < 40.0:
			continue
		if rng.randf() < 0.12:
			f.pregnancy = 0.0
			_log("%s и %s ждут ребёнка!" % [f.name, partner.name], "good")


func _birth(mother: Unit) -> void:
	mother.pregnancy = -1.0
	var father := unit_by_id(mother.partner_id)
	var baby := _new_unit(rng.randi_range(0, 1), mother.pos)
	baby.child = true
	baby.age = 0.0
	baby.satiety = 80.0
	baby.energy = 80.0
	# Немного таланта от родителей.
	for k in baby.skills:
		var parent_xp: float = mother.skills[k] + (father.skills[k] if father != null else 0.0)
		baby.skills[k] = parent_xp * 0.1
	var who := "дочь" if baby.sex == Unit.Sex.FEMALE else "сын"
	var parents := mother.name + (" и " + father.name if father != null else "")
	_log("Родился ребёнок: %s (%s %s)" % [baby.name, who, parents], "good")


# --- Онлайн-симуляция -------------------------------------------------------------

func update(dt: float) -> void:
	var remaining := dt
	while remaining > 0.0:
		var step := minf(remaining, SUBSTEP)
		remaining -= step
		for p in projects:
			if not p.paused:
				_try_pay(p)
		_life_tick(step, false)
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
			if not _task_valid(u) or _needs_interrupt(u):
				_drop(u)
				return
			_move(u, dt)
		Unit.State.WORK:
			if not _task_valid(u) or _needs_interrupt(u):
				_drop(u)
				return
			_work(u, dt)


## Совсем устал или голоден — бросает работу.
func _needs_interrupt(u: Unit) -> bool:
	if u.task == Unit.Task.SLEEP or u.task == Unit.Task.EAT:
		return false
	return u.energy < 10.0 or (u.satiety < 15.0 and inventory.get("food", 0) > 0)


## Замедление в тесном тоннеле: поток ограничен его шириной.
func congestion(u: Unit) -> float:
	var p := project_at(u.cell())
	if p == null or p.kind != Project.Kind.TUNNEL:
		return 1.0
	var vertical := p.rect.size.y > p.rect.size.x
	var crowd := 1
	for o in units:
		if o == u or not p.has_cell(o.cell()):
			continue
		var d := absf(o.pos.y - u.pos.y) if vertical else absf(o.pos.x - u.pos.x)
		if d <= 1.2:
			crowd += 1
	return minf(1.0, float(tunnel_lanes(p.rect)) / crowd)


func _move(u: Unit, dt: float) -> void:
	var budget := dt
	var jam := congestion(u)
	while budget > 0.0 and u.path_i < u.path.size():
		var next := Vector2(u.path[u.path_i])
		var delta := next - u.pos
		var spd := (CLIMB_SPEED if absf(delta.y) > absf(delta.x) else WALK_SPEED) * jam
		if u.child:
			spd *= 0.8
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
		u.work_t = 0.0
		if u.task == Unit.Task.DIG or u.task == Unit.Task.HARVEST:
			if u.target.x != u.cell().x:
				u.facing = 1 if u.target.x > u.cell().x else -1


func _work(u: Unit, dt: float) -> void:
	var skill := Unit.skill_for(u.task)
	var rate := dt
	if not skill.is_empty():
		var before := u.level(skill)
		u.skills[skill] += dt
		if u.level(skill) > before:
			_log("%s: навык «%s» вырос до %d" % [u.name, Unit.SKILL_NAMES[skill], u.level(skill)], "good")
		rate = dt * u.speed(skill) * u.need_factor()
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
		Unit.Task.EQUIP:
			var p := project_by_id(u.project_id)
			p.equip_done += rate
			if p.equip_done >= RoomType.job_work(p):
				_finish_equip(p)
		Unit.Task.HARVEST:
			var x := u.target.x
			harvest_progress[x] = harvest_progress.get(x, 0.0) + rate
			if harvest_progress[x] >= HARVEST_TIME.get(world.feature_at(x), 20.0):
				_drop(u)
				_complete_harvest(x, u)
		Unit.Task.FARM:
			var p := project_by_id(u.project_id)
			p.farm_progress += rate
			while p.farm_progress >= RoomType.FARM_CYCLE:
				p.farm_progress -= RoomType.FARM_CYCLE
				_add("food", 1)
			u.work_t += dt
			if u.work_t >= FARM_SHIFT:
				_drop(u)
		Unit.Task.SLEEP:
			u.energy = minf(100.0, u.energy + dt * (SLEEP_BED if u.project_id != 0 else SLEEP_FLOOR))
			if u.energy >= 100.0:
				_drop(u)
		Unit.Task.EAT:
			u.work_t += dt
			if u.work_t >= EAT_TIME:
				# Растущий ребёнок съедает вдвое больше.
				var portion := 2 if u.child else 1
				if inventory.get("food", 0) >= portion:
					inventory["food"] -= portion
					u.satiety = minf(100.0, u.satiety + (MEAL_DINING if u.project_id != 0 else MEAL))
				_drop(u)


func _task_valid(u: Unit) -> bool:
	match u.task:
		Unit.Task.DIG, Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.FARM:
			var p := project_by_id(u.project_id)
			if p == null or p.paused:
				return false
			match u.task:
				Unit.Task.DIG:
					return p.phase == Project.Phase.DIG and Mat.is_solid(world.get_mat(u.target.x, u.target.y))
				Unit.Task.BUILD:
					return p.phase == Project.Phase.BUILD and p.paid
				Unit.Task.EQUIP:
					return p.phase == Project.Phase.EQUIP and p.equip_paid
				Unit.Task.FARM:
					return p.phase == Project.Phase.DONE and p.purpose == RoomType.FARM
		Unit.Task.HARVEST:
			if u.project_id != 0:
				var hp := project_by_id(u.project_id)
				if hp == null or hp.paused:
					return false
			return world.feature_marks.has(u.target.x) and world.feature_at(u.target.x) != WorldGen.FEATURE_NONE
		Unit.Task.SLEEP, Unit.Task.EAT:
			return true
	return false


func _drop(u: Unit) -> void:
	var key = _reserve_key(u)
	if key != null and reserved.get(key) == u.id:
		reserved.erase(key)
	u.task = Unit.Task.NONE
	u.project_id = 0
	u.path.clear()
	u.path_i = 0
	u.work_t = 0.0
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


## Порядок занятий жителя: сначала его профессия, затем общая очередь.
func _task_order(u: Unit) -> Array[String]:
	var order: Array[String] = []
	match u.profession:
		Unit.Prof.DIGGER:
			order.append("dig")
		Unit.Prof.BUILDER:
			order.append("build")
		Unit.Prof.GATHERER:
			order.append("harvest")
		Unit.Prof.FARMER:
			order.append("farm")
	if food_low():
		order.append("farm")
	if waiting_for_materials() or food_low():
		order.append("harvest")
	order.append_array(["projects", "farm", "harvest"])
	return order


## Ищет занятие для жителя. true — назначено.
func _assign(u: Unit) -> bool:
	var reach := pathing.explore(u.cell())
	var parents: Dictionary = reach[0]
	var dist: Dictionary = reach[1]
	if u.energy < TIRED:
		_start_sleep(u, parents, dist)
		return true
	if u.satiety < HUNGRY and inventory.get("food", 0) > 0:
		_start_eat(u, parents, dist)
		return true
	if u.child:
		return false
	for kind in _task_order(u):
		match kind:
			"harvest":
				if _try_harvest(u, parents, dist):
					return true
			"farm":
				if _try_farm(u, parents, dist):
					return true
			"dig", "build", "projects":
				for p in projects:
					if p.paused or workers_on(p) >= p.workers:
						continue
					if kind != "build" and p.phase == Project.Phase.DIG:
						if _try_harvest(u, parents, dist, uncleared(p), p.id) or _try_dig(u, p, parents, dist):
							return true
					if kind != "dig" and p.phase == Project.Phase.BUILD and p.paid \
							and _try_build(u, p, Unit.Task.BUILD, parents, dist):
						return true
					if kind != "dig" and p.phase == Project.Phase.EQUIP and p.equip_paid \
							and _try_build(u, p, Unit.Task.EQUIP, parents, dist):
						return true
	return false


func _start(u: Unit, task: int, target: Vector2i, stand: Vector2i, pid: int, parents: Dictionary) -> void:
	u.task = task
	u.target = target
	u.project_id = pid
	u.path = Pathing.path_to(parents, stand)
	u.path_i = 0
	u.work_t = 0.0
	u.state = Unit.State.MOVE
	var key = _reserve_key(u)
	if key != null:
		reserved[key] = u.id


func _start_sleep(u: Unit, parents: Dictionary, dist: Dictionary) -> void:
	_claim_bed(u)
	var room := project_by_id(u.bed_room)
	if room != null:
		var bed := bed_cell(room, u.bed_index)
		if dist.has(bed):
			_start(u, Unit.Task.SLEEP, bed, bed, room.id, parents)
			return
	# Кровати нет или до неё не добраться — спит где стоит.
	_start(u, Unit.Task.SLEEP, u.cell(), u.cell(), 0, parents)


func _start_eat(u: Unit, parents: Dictionary, dist: Dictionary) -> void:
	var best = null
	var best_d := 1 << 30
	var room_id := 0
	for p in rooms_of(RoomType.DINING):
		for x in range(RoomType.floor_start(p), p.rect.end.x):
			var c := Vector2i(x, p.rect.end.y - 1)
			if dist.has(c) and dist[c] < best_d:
				best_d = dist[c]
				best = c
				room_id = p.id
	# В столовую идут, только если она недалеко.
	if best != null and best_d < 80:
		_start(u, Unit.Task.EAT, best, best, room_id, parents)
	else:
		_start(u, Unit.Task.EAT, u.cell(), u.cell(), 0, parents)


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
		if any_free and workers_on(p) == 0 and p.blocked.is_empty():
			p.blocked = "Нет доступа — проложите тоннель к стройке"
		return false
	if p.blocked.begins_with("Нет доступа"):
		p.blocked = ""
	_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
	return true


func _try_build(u: Unit, p: Project, task: int, parents: Dictionary, dist: Dictionary) -> bool:
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
	_start(u, task, p.rect.get_center(), best, p.id, parents)
	return true


func _try_farm(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	for p in rooms_of(RoomType.FARM):
		if p.paused or workers_on(p) >= RoomType.farm_slots(p):
			continue
		var best = null
		var best_d := 1 << 30
		for x in range(RoomType.floor_start(p), p.rect.end.x):
			var c := Vector2i(x, p.rect.end.y - 1)
			if dist.has(c) and dist[c] < best_d:
				best_d = dist[c]
				best = c
		if best != null:
			_start(u, Unit.Task.FARM, best, best, p.id, parents)
			return true
	return false


## only — ограничить список столбцов (расчистка места под стройку pid).
func _try_harvest(u: Unit, parents: Dictionary, dist: Dictionary, only: Array = [], pid := 0) -> bool:
	if pid != 0 and only.is_empty():
		return false
	var best_x = null
	var best_stand = null
	var best_d := 1 << 30
	var want_food := food_low()
	for x in (only if pid != 0 else world.feature_marks.keys()):
		if reserved.has("h%d" % x):
			continue
		var base := Vector2i(x, world.gen.surface_y(x) - 1)
		# При нехватке еды кусты с ягодами — в первую очередь.
		var bonus := -1000 if want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH else 0
		for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
			if dist.has(stand) and dist[stand] + bonus < best_d:
				best_d = dist[stand] + bonus
				best_x = x
				best_stand = stand
	if best_x == null:
		return false
	_start(u, Unit.Task.HARVEST, Vector2i(best_x, world.gen.surface_y(best_x) - 1), best_stand, pid, parents)
	return true


# --- Оффлайн-симуляция --------------------------------------------------------------

## Упрощённая модель: жители не ходят, а сразу работают с меньшей эффективностью
## (часть времени уходит на сон и еду). Возвращает число выкопанных клеток.
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
			if u.child:
				continue
			var job := _offline_job(u, taken)
			if job.is_empty():
				continue
			var key = job[0]
			var skill := Unit.skill_for(job[1])
			var rate := u.speed(skill) * OFFLINE_EFFICIENCY * u.need_factor()
			if jobs.has(key):
				jobs[key][1] += rate
			else:
				jobs[key] = [job[1], rate, u, job[2]]
			u.task = job[1]
		var step := minf(remaining, OFFLINE_STEP)
		for key in jobs:
			step = minf(step, _offline_left(key, jobs[key]) / jobs[key][1])
		step = maxf(step, 0.0)
		remaining -= step
		_life_tick(step, true)
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
				Unit.Task.EQUIP:
					var p: Project = j[3]
					p.equip_done += j[1] * step
					if p.equip_done >= RoomType.job_work(p) - 0.001:
						_finish_equip(p)
				Unit.Task.FARM:
					var p: Project = j[3]
					p.farm_progress += j[1] * step
					while p.farm_progress >= RoomType.FARM_CYCLE:
						p.farm_progress -= RoomType.FARM_CYCLE
						_add("food", 1)
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
		Unit.Task.EQUIP:
			var p: Project = job[3]
			return RoomType.job_work(p) - p.equip_done
		Unit.Task.FARM:
			return OFFLINE_STEP
		Unit.Task.HARVEST:
			var x: int = int(key.substr(1))
			return HARVEST_TIME.get(world.feature_at(x), 20.0) - harvest_progress.get(x, 0.0)
	return 0.0


## [ключ цели, вид задачи, проект] или [] если работы нет.
func _offline_job(u: Unit, taken: Dictionary) -> Array:
	for kind in _task_order(u):
		match kind:
			"harvest":
				var h := _offline_harvest(taken)
				if not h.is_empty():
					return h
			"farm":
				for p in rooms_of(RoomType.FARM):
					var slot := "w%d" % p.id
					if not p.paused and taken.get(slot, 0) < RoomType.farm_slots(p):
						taken[slot] = taken.get(slot, 0) + 1
						return ["f%d" % p.id, Unit.Task.FARM, p]
			"dig", "build", "projects":
				for p in projects:
					var slot := "w%d" % p.id
					if p.paused or taken.get(slot, 0) >= p.workers:
						continue
					if kind != "build" and p.phase == Project.Phase.DIG:
						for x in uncleared(p):
							if not taken.has("h%d" % x):
								taken["h%d" % x] = true
								taken[slot] = taken.get(slot, 0) + 1
								return ["h%d" % x, Unit.Task.HARVEST, p]
						for c in remaining_dig(p):
							if taken.has(c):
								continue
							for d in DIRS4:
								if world.is_open(c.x + d.x, c.y + d.y):
									taken[c] = true
									taken[slot] = taken.get(slot, 0) + 1
									return [c, Unit.Task.DIG, p]
					elif kind != "dig" and p.phase == Project.Phase.BUILD and p.paid:
						taken[slot] = taken.get(slot, 0) + 1
						return ["b%d" % p.id, Unit.Task.BUILD, p]
					elif kind != "dig" and p.phase == Project.Phase.EQUIP and p.equip_paid:
						taken[slot] = taken.get(slot, 0) + 1
						return ["e%d" % p.id, Unit.Task.EQUIP, p]
	return []


func _offline_harvest(taken: Dictionary) -> Array:
	var want_food := food_low()
	var pick = null
	for x in world.feature_marks:
		var key := "h%d" % x
		if taken.has(key):
			continue
		if pick == null or (want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH):
			pick = x
			if want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH:
				break
	if pick == null:
		return []
	taken["h%d" % pick] = true
	return ["h%d" % pick, Unit.Task.HARVEST, null]


# --- Вспомогательное ----------------------------------------------------------------

## Кладёт ресурс на склад с учётом вместимости. Возвращает, сколько поместилось.
func _add(key: String, amount: int) -> int:
	if key.is_empty() or amount <= 0:
		return 0
	known_resources[key] = true
	var have: int = inventory.get(key, 0)
	var cap := capacity(key)
	var put := clampi(cap - have, 0, amount)
	inventory[key] = have + put
	# Предупреждаем один раз на ресурс, пока не построят новый склад.
	if put < amount and not _full_warned.has(key):
		_full_warned[key] = true
		_log("Склад полон: %s (%d). Постройте склад, лишнее выбрасывается." % [Mat.resource_name(key).to_lower(), cap], "warning")
	return put


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
		"known_resources": known_resources.keys(),
		"cells_dug": cells_dug,
		"discovered": discovered.keys(),
		"dig_progress": dp,
		"harvest_progress": hp,
		"projects": ps,
		"units": us,
		"next_project_id": next_project_id,
		"next_unit_id": next_unit_id,
		"social_t": _social_t,
		"home": [home.x, home.y],
	}


func load_dict(d: Dictionary) -> void:
	inventory.clear()
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		inventory[k] = int(inv[k])
		known_resources[k] = true
	for k in d.get("known_resources", []):
		known_resources[str(k)] = true
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
		if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
			for c in p.cells():
				interior[c] = p.id
	for ud in d.get("units", []):
		units.append(Unit.from_dict(ud))
	next_project_id = int(d.get("next_project_id", projects.size() + 1))
	next_unit_id = int(d.get("next_unit_id", units.size() + 1))
	_social_t = float(d.get("social_t", 0.0))
	var h: Array = d.get("home", [0, world.gen.surface_y(0)])
	home = Vector2i(int(h[0]), int(h[1]))
