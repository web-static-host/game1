extends SceneTree
## Долгая игра ботом-«вовлечённым игроком»: строит дома под растущую семью, склад, ферму,
## пристань, копает шахту вглубь с комнатами по бокам, ведёт науку, ставит мастерские,
## чинит, отвечает геологу. Пишет вехи, срезы каждые 10 минут и «пустые» отрезки,
## когда игроку нечего делать и ничего не происходит.
##   godot --headless --path . -s res://tests/longplay.gd -- <seed> <минут>

var colony: Colony
var world: WorldData
var t := 0.0
var milestones: Array[String] = []
var _seen := {}
var events := {}
var actions: Array[float] = []
var last_news := 0.0
var quiet: Array[String] = []
var shaft_x := 0
var shaft_bottom := 0
var side := 1
var _pending_purpose := {}
var deaths: Array[String] = []
var births := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 4242
	var minutes := int(args[1]) if args.size() > 1 else 240
	world = WorldData.new(WorldGen.new(seed_value))
	colony = Colony.new(world)
	colony.event_logged.connect(_on_log)
	colony.start_new(0)
	shaft_x = colony.home.x + 3
	shaft_bottom = world.gen.surface_y(shaft_x)
	var next_slice := 600.0
	var think := 0.0
	print("=== Мир %d, %d минут игры ===" % [seed_value, minutes])
	while t < minutes * 60.0:
		colony.update(0.5)
		t += 0.5
		think += 0.5
		if think >= 5.0:
			think = 0.0
			_play()
		if t >= next_slice:
			next_slice += 600.0
			_slice()
		if t - last_news > 900.0:
			quiet.append("%s: 15 мин без новостей (жит %d, глубина %d м)" % [_time(), colony.units.size(), _depth()])
			last_news = t
	print("\n--- Вехи ---")
	for m in milestones:
		print(m)
	print("\n--- События ---")
	for k in events:
		print("%s ×%d" % [k, events[k]])
	print("\n--- Затишья ---")
	for q in quiet:
		print(q)
	print("\n--- Смерти ---")
	for d in deaths:
		print(d)
	print("\nДействий игрока: %d (%.1f в минуту), рождений: %d" % [actions.size(), actions.size() / (t / 60.0), births])
	quit()


func _time() -> String:
	return "%3d мин (%s)" % [int(t / 60.0), colony.date_text()]


func _depth() -> int:
	return maxi(0, colony.deepest_y - colony.home.y)


func _milestone(key: String, text: String) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	milestones.append("%s  %s" % [_time(), text])
	last_news = t


func _act(_what: String) -> void:
	actions.append(t)
	last_news = t


func _on_log(text: String, kind: String) -> void:
	for pair in [["ОБВАЛ", "обвал"], ["Осыпь", "осыпь"], ["ОБРУШЕНИЕ", "обрушение постройки"], ["Буря:", "буря"],
			["ЗЕМЛЕТРЯСЕНИЕ", "землетрясение"], ["ВЗРЫВ", "взрыв метана"], ["Затопило", "затопление"],
			["лава течёт", "прорыв лавы"], ["сочится", "водоносный пласт"], ["Геолог", "предупреждение геолога"],
			["истощ", "истощение от голода"], ["перегружена", "перегрузка"], ["износ 70", "износ 70%"],
			["Склад полон", "склад полон"], ["Не хватает", "нехватка материалов"], ["Новая находка", "новая находка"],
			["Изучено", "исследование"], ["Родился", "рождение"], ["стали парой", "пара"]]:
		if text.contains(pair[0]):
			events[pair[1]] = events.get(pair[1], 0) + 1
	if text.contains("погиб"):
		deaths.append("%s  %s" % [_time(), text])
	if text.contains("Родился"):
		births += 1
		_milestone("child%d" % births if births <= 3 else "child", "Родился ребёнок №%d" % births)
	if text.contains("Новая находка"):
		_milestone(text, text)
	if text.contains("Изучено"):
		_milestone(text, text.split(".")[0])
	if kind == "danger" or kind == "good":
		last_news = t


func _slice() -> void:
	var idle := 0
	for u in colony.units:
		if u.state == Unit.State.IDLE and u.task == Unit.Task.NONE:
			idle += 1
	var keys := ["food", "berries", "wood", "stone", "clay", "coal", "iron", "copper", "brick", "metal", "methane"]
	var inv: PackedStringArray = []
	for k in keys:
		if colony.inventory.get(k, 0) > 0:
			inv.append("%s %d" % [k, colony.inventory[k]])
	var done := 0
	for p in colony.projects:
		if p.phase == Project.Phase.DONE:
			done += 1
	print("%s | жит %d (дети %d) кроватей %d | построек %d, строится %d | глубина %d м | наука %d/%d | без дела %d | %s" % [
		_time(), colony.units.size(), colony.units.filter(func(u: Unit) -> bool: return u.child).size(), colony.beds_total(),
		done, colony.projects.size() - done, _depth(), colony.research.done.size(), Research.TECHS.size(), idle, ", ".join(inv)])


# --- Игрок -------------------------------------------------------------------------

func _busy() -> int:
	var n := 0
	for p in colony.projects:
		if p.phase != Project.Phase.DONE or p.repairing:
			n += 1
	return n


func _play() -> void:
	_answer_geologist()
	_finish_purposes()
	_repairs()
	_marks()
	_science()
	_professions()
	if _busy() >= 2:
		return
	if _need_home():
		return
	if colony.rooms_of(RoomType.STORAGE).is_empty() and _surface_room(RoomType.STORAGE):
		return
	if _shaft():
		return
	if _pier():
		return
	_more_storage()


func _answer_geologist() -> void:
	for p in colony.projects:
		if p.paused and not p.hazard_pending.is_empty():
			events["геолог: продолжили"] = events.get("геолог: продолжили", 0) + 1
			colony.set_paused(p, false)
			_act("геолог")


## Построенные комнаты получают задуманное назначение.
func _finish_purposes() -> void:
	for p in colony.projects:
		if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM and p.purpose == RoomType.NONE \
				and _pending_purpose.has(p.id):
			if colony.set_purpose(p, _pending_purpose[p.id]):
				_act("назначение")
				var names := {RoomType.HOME: "дом", RoomType.STORAGE: "склад", RoomType.FARM: "ферма",
					RoomType.LAB: "лаборатория", RoomType.DINING: "столовая", RoomType.KILN: "печь",
					RoomType.GENERATOR: "генератор", RoomType.PUMP: "насосная", RoomType.DEGAS: "дегазация"}
				_milestone("purpose%d" % _pending_purpose[p.id], "Первая комната: %s" % names.get(_pending_purpose[p.id], "?"))
			_pending_purpose.erase(p.id)


func _repairs() -> void:
	for p in colony.projects:
		if p.wear >= 0.7 and colony.repair_error(p).is_empty():
			colony.start_repair(p)
			_act("ремонт")
			_milestone("repair", "Первый ремонт")


func _marks() -> void:
	if colony.inventory.get("wood", 0) > 60 or world.feature_marks.size() >= 6:
		return
	var n := 0
	for d in range(1, colony.explored_max - colony.home.x):
		for x in [colony.home.x + d, colony.home.x - d]:
			if n < 6 and world.feature_at(x) == WorldGen.FEATURE_TREE and not world.feature_marks.has(x) \
					and colony.is_explored(x) and colony.toggle_harvest(x).is_empty():
				n += 1
	if n > 0:
		_act("сбор")


func _science() -> void:
	if colony.rooms_of(RoomType.LAB).is_empty() or not colony.research.current.is_empty():
		return
	for id in Research.TECHS:
		if colony.research.start(id):
			_act("наука")
			return


func _professions() -> void:
	var farms := colony.rooms_of(RoomType.FARM).size()
	var labs := colony.rooms_of(RoomType.LAB).size()
	var want := {Unit.Prof.FARMER: farms, Unit.Prof.SCIENTIST: labs}
	for prof in want:
		var have := colony.units.filter(func(u: Unit) -> bool: return u.profession == prof).size()
		for u in colony.units:
			if have >= want[prof]:
				break
			if not u.child and u.profession == Unit.Prof.ANY:
				u.profession = prof
				have += 1
				_act("профессия")


func _best_material() -> String:
	var mats := colony.available_materials()
	for m in ["brick", "stone", "clay", "wood"]:
		if mats.has(m) and colony.inventory.get(m, 0) >= 12:
			return m
	return "wood"


func _need_home() -> bool:
	if colony.beds_total() >= colony.units.size() + 1:
		return false
	return _surface_room(RoomType.HOME)


## Комната 6×3 на земле у базы (ищем ровное место всё дальше).
func _surface_room(purpose: int) -> bool:
	var mat := _best_material()
	var cost := Project.cost_for(Project.Kind.ROOM, Rect2i(0, 0, 6, 3), mat)
	for k in cost:
		if colony.inventory.get(k, 0) + colony.drop_total(k) < cost[k]:
			return false
	for d in range(0, 60):
		for sx in [colony.home.x - 8 - d, colony.home.x + 6 + d]:
			if absi(sx - shaft_x) < 8 and sx <= shaft_x + 7:
				continue
			var s := world.gen.surface_y(sx)
			# На крышу готовой комнаты — второй этаж, иначе на землю.
			var r := Rect2i(sx, s - 3, 6, 3)
			if colony.validate(Project.Kind.ROOM, r, mat).is_empty():
				var p := colony.create_project(Project.Kind.ROOM, r, -1, mat)
				if p != null:
					_pending_purpose[p.id] = purpose
					_act("стройка")
					return true
	return false


## Шахта вниз по 10 м и комната сбоку на каждом уровне: ферма, лаборатория, столовая, мастерские.
func _shaft() -> bool:
	var s := world.gen.surface_y(shaft_x)
	if colony.inventory.get("wood", 0) < 15:
		return false
	var want := _next_underground()
	if want < 0 and shaft_bottom - s > 200:
		return false
	var top := shaft_bottom
	var r := Rect2i(shaft_x, top, 1, 10)
	if colony.validate(Project.Kind.TUNNEL, r).is_empty():
		if colony.create_project(Project.Kind.TUNNEL, r, 2) != null:
			shaft_bottom = top + 10
			_act("шахта")
	if want >= 0:
		var floor_y := shaft_bottom - 1
		var rx := shaft_x + 1 if side > 0 else shaft_x - 6
		var room := Rect2i(rx, floor_y - 2, 6, 3)
		var mat := _best_material()
		if colony.validate(Project.Kind.ROOM, room, mat).is_empty():
			var p := colony.create_project(Project.Kind.ROOM, room, -1, mat)
			if p != null:
				_pending_purpose[p.id] = want
				side = -side
				_act("подземная комната")
				return true
	var depth := shaft_bottom - s
	for d in [50, 100, 200, 500, 1000]:
		if depth >= d:
			_milestone("depth%d" % d, "Шахта заложена до %d м" % d)
	return true


## Что строить под землёй дальше.
func _next_underground() -> int:
	var has := func(t: int) -> bool:
		for p in colony.projects:
			if p.kind == Project.Kind.ROOM and (p.purpose == t or _pending_purpose.values().has(t)):
				return true
		return false
	if not has.call(RoomType.FARM):
		return RoomType.FARM
	if not has.call(RoomType.LAB):
		return RoomType.LAB
	if colony.units.size() >= 7 and colony.rooms_of(RoomType.FARM).size() < colony.units.size() / 5:
		return RoomType.FARM
	if not has.call(RoomType.DINING):
		return RoomType.DINING
	if colony.research.has("bricks") and not has.call(RoomType.KILN) and colony.known_resources.has("clay"):
		return RoomType.KILN
	if colony.research.has("electricity") and not has.call(RoomType.GENERATOR) \
			and colony.inventory.get("copper", 0) >= 4 and colony.inventory.get("iron", 0) >= 4:
		return RoomType.GENERATOR
	if not colony.elements.gas.is_empty() and not has.call(RoomType.DEGAS):
		return RoomType.DEGAS
	for p in colony.projects:
		if p.blocked.begins_with("В зоне") and not has.call(RoomType.PUMP):
			return RoomType.PUMP
	return -1


func _pier() -> bool:
	for p in colony.projects:
		if p.is_water_structure():
			return false
	var lake := world.gen.lake_at(55)
	if lake.is_empty() or colony.inventory.get("wood", 0) < 25 or colony.inventory.get("stone", 0) < 4:
		return false
	var span := world.gen.lake_water_span(lake)
	var r: Rect2i = colony.water_rects(span.x, span.x + 5)["pier"]
	if r.size.x > 0 and colony.validate(Project.Kind.PIER, r).is_empty():
		if colony.create_project(Project.Kind.PIER, r, 1) != null:
			_act("пристань")
			_milestone("pier", "Заложена пристань")
			return true
	return false


func _more_storage() -> void:
	for k in ["wood", "stone", "food"]:
		if colony.inventory.get(k, 0) >= colony.capacity(k) - 5:
			_milestone("full", "Склад впервые забит (%s)" % k)
			_surface_room(RoomType.STORAGE)
			return
