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
var prof := {}


func _tm(key: String, from: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = prof.get(key, 0) + now - from
	return now


## Копия Colony.update с замером времени по частям.
func _update_profiled(dt: float) -> void:
	var c := colony
	var remaining := dt
	var t0 := Time.get_ticks_usec()
	while remaining > 0.0:
		var step := minf(remaining, Colony.SUBSTEP)
		remaining -= step
		c.game_time += step
		c.pathing.tick(step)
		for p in c.projects:
			if not p.paused:
				c._try_pay(p)
		t0 = _tm("pay", t0)
		c._tick_exposure(step)
		c._wear_tick(step)
		t0 = _tm("exposure+wear", t0)
		c._power_tick(step)
		c._plant_tick(step)
		t0 = _tm("power+plants", t0)
		c._life_tick(step, false)
		t0 = _tm("life", t0)
		for u: Unit in c.units.duplicate():
			var st := u.state
			c._update_unit(u, step)
			t0 = _tm("unit_st%d" % st, t0)
	c.physics.update(dt)
	t0 = _tm("physics", t0)
	c.elements.update(dt)
	t0 = _tm("elements", t0)
	c.loads.update(dt)
	t0 = _tm("loads", t0)
	c._explore_t += dt
	if c._explore_t >= 1.0:
		c._explore_t = 0.0
		c.explore()
		c._access_t += 1
		if c._access_t >= 5:
			c._access_t = 0
			c._check_access()
		for p in c.projects:
			if p.paused and p.blocked.begins_with("В зоне"):
				c._check_liquids(p)
				if p.blocked.is_empty():
					p.paused = false
	t0 = _tm("explore+access", t0)


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
	var profile := not OS.get_environment("PROFILE").is_empty()
	while t < minutes * 60.0:
		if profile:
			_update_profiled(0.5)
		else:
			colony.update(0.5)
		t += 0.5
		think += 0.5
		if think >= 5.0:
			think = 0.0
			var tb := Time.get_ticks_usec()
			_play()
			_tm("bot", tb)
			var dbg := OS.get_environment("DEBUG_FROM")
			if not dbg.is_empty() and t >= float(dbg) * 60.0 and int(t) % 20 == 0:
				_debug()
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
	if profile:
		var keys := prof.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return prof[a] > prof[b])
		print("\n--- Профиль (мс) ---")
		for k in keys:
			print("%-12s %8d" % [k, prof[k] / 1000])
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
	if not OS.get_environment("LOGALL").is_empty() and t >= float(OS.get_environment("LOGALL")) * 60.0:
		print("LOG %s %s" % [_time(), text])
	for pair in [["ОБВАЛ", "обвал"], ["Осыпь", "осыпь"], ["ОБРУШЕНИЕ", "обрушение постройки"], ["Буря:", "буря"],
			["ЗЕМЛЕТРЯСЕНИЕ", "землетрясение"], ["ВЗРЫВ", "взрыв метана"], ["Затопило", "затопление"],
			["лава течёт", "прорыв лавы"], ["сочится", "водоносный пласт"], ["Геолог", "предупреждение геолога"],
			["истощ", "истощение от голода"], ["перегружена", "перегрузка"], ["износ 70", "износ 70%"],
			["Склад полон", "склад полон"], ["Не хватает", "нехватка материалов"], ["Новая находка", "новая находка"],
			["Изучено", "исследование"], ["на разведку", "разведка за сырьём"], ["Метан в выработке", "газовая тревога"], ["Родился", "рождение"], ["стали парой", "пара"],
			["от старости", "смерть от старости"], ["мёрзнет", "мороз"], ["Через месяц зима", "мало еды к зиме"],
			["состарил", "старость"]]:
		if text.contains(pair[0]):
			events[pair[1]] = events.get(pair[1], 0) + 1
	if text.contains("погиб") or text.contains("от старости"):
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


func _debug() -> void:
	var farms := colony.rooms_of(RoomType.FARM)
	for f in farms:
		print("DBGF ферма %s темп %.1f тепло %s раб %s прогресс %.1f" % [f.rect, colony.room_temp(f), colony.farm_warm(f), colony.assigned_to(f).map(func(u: Unit) -> String: return "%s:%s" % [u.name, Unit.TASK_NAMES[u.task]]), f.farm_progress])
	for h in colony.projects:
		if farms.size() > 0 and absi(h.rect.get_center().y - farms[0].rect.get_center().y) <= 6 and h.kind == Project.Kind.ROOM:
			print("DBGF рядом %s %s фаза %s назн %d ждёт %d горит %s blocked «%s» paused %s" % [h.title(), h.rect, h.phase_name(), h.purpose, _pending_purpose.get(h.id, -1), h.burning, h.blocked, h.paused])
		if h.purpose == RoomType.HEARTH or _pending_purpose.get(h.id, -1) == RoomType.HEARTH:
			print("DBGF очаг %s фаза %s горит %s blocked «%s» дерево %d" % [h.rect, h.phase_name(), h.burning, h.blocked, colony.inventory.get("wood", 0)])
	print("DBG %s еда %s ягоды %s ферм %d на земле еды %d" % [_time(), colony.inventory.get("food", 0),
		colony.inventory.get("berries", 0), farms.size(), colony.drop_total("food") + colony.drop_total("berries")])
	for u in colony.units:
		var reach := colony.pathing.explore(u.cell())
		var to_farm = null
		for f in farms:
			to_farm = colony._near_rect(f.rect, reach[1])
		var xs: Array = reach[1].keys().map(func(c: Vector2i) -> int: return c.x)
		print("   %s %s %s st%d сыт %d бодр %d здор %d проф %d | до фермы %s, узлов %d, x %d..%d" % [u.name, u.cell(),
			Unit.TASK_NAMES[u.task], u.state, roundi(u.satiety), roundi(u.energy), roundi(u.health), u.profession,
			to_farm, reach[1].size(), xs.min(), xs.max()])
	for p in colony.projects:
		print("   стройка %s %s %s %s раб %d/%d" % [p.title(), p.rect, p.phase_name(), p.blocked, colony.workers_on(p), p.workers])
		if p.phase == Project.Phase.DIG:
			print("      копать %d, расчистка %s, укрепл: нужно %s оплачено %s срез %d, доступ %s" % [colony.diggable_now(p).size(), colony.uncleared(p),
				p.needs_support, p.support_paid, p.support_slice, colony.has_access(p.rect)])
			print("      принесено %s, осталось %s, нужно сейчас %s, req %s" % [p.delivered, colony.remaining(p), colony._needed_now(p), colony.required(p)])
	for u in colony.units:
		if u.task == Unit.Task.HAUL:
			print("   несёт %s: %s %d этап %d в %d склад %s src %s" % [u.name, u.carry_key, u.carry_amount, u.haul_stage, u.project_id, u.to_store, u.haul_src])


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
	inv.append("на полу еды %d" % (colony.drop_total("food") + colony.drop_total("berries")))
	var sci := 0
	for lab in colony.rooms_of(RoomType.LAB):
		sci += colony.assigned_to(lab).size()
	inv.append("учёных %d, изучают «%s» %.0f" % [sci, colony.research.current, colony.research.progress])
	var roles := {}
	for u in colony.units:
		var r := colony.role_name(u)
		roles[r] = roles.get(r, 0) + 1
	inv.append(str(roles))
	print("[%4d с] %s | жит %d (дети %d) кроватей %d | построек %d, строится %d | глубина %d м | наука %d/%d | без дела %d | %s" % [
		Time.get_ticks_msec() / 1000, _time(), colony.units.size(), colony.units.filter(func(u: Unit) -> bool: return u.child).size(), colony.beds_total(),
		done, colony.projects.size() - done, _depth(), colony.research.done.size(), Research.TECHS.size(), idle, ", ".join(inv)])


# --- Игрок -------------------------------------------------------------------------

func _busy() -> int:
	var n := 0
	for p in colony.projects:
		if p.phase != Project.Phase.DONE or p.repairing:
			n += 1
	return n


func _play() -> void:
	# IDLE=1 — игрок ничего не делает (проверка, что без игрока колония не выживает).
	if not OS.get_environment("IDLE").is_empty():
		return
	_answer_geologist()
	_finish_purposes()
	_repairs()
	_marks()
	_science()
	_professions()
	if _fix_shaft():
		return
	# Тепло ферме — важнее остальных строек.
	if _heat_farms():
		return
	if _busy() >= 2:
		return
	if _need_home():
		return
	if not _has_room(RoomType.STORAGE) and _surface_room(RoomType.STORAGE):
		return
	if not _has_room(RoomType.GRANARY) and _surface_room(RoomType.GRANARY):
		return
	if _shaft():
		return
	if _pier():
		return
	_more_storage()


## Шахту залило подземной водой или в ней метан: насосная или дегазация у верха
## вставшего тоннеля, куда можно дойти.
func _fix_shaft() -> bool:
	for p in colony.projects:
		if p.phase == Project.Phase.DONE or absi(p.rect.get_center().x - shaft_x) > 8:
			continue
		var want := -1
		if p.blocked.begins_with("В зоне"):
			want = RoomType.PUMP
		elif p.hazard_pending == "methane":
			want = RoomType.DEGAS
		if want < 0:
			continue
		for q in colony.projects:
			if _pending_purpose.get(q.id, -1) == want or (q.purpose == want and absi(q.rect.position.y - p.rect.position.y) < 15):
				return false
		var top := p.rect.position.y
		for rx in [shaft_x + 1, shaft_x - 6]:
			for dy in [0, 1, 2]:
				var room := Rect2i(rx, top - 3 + dy, 6, 3)
				var mat := _best_material()
				if colony.validate(Project.Kind.ROOM, room, mat).is_empty():
					var r := colony.create_project(Project.Kind.ROOM, room, -1, mat)
					if r != null:
						_pending_purpose[r.id] = want
						_act("насосная" if want == RoomType.PUMP else "дегазация")
						return true
	return false


## Осторожный игрок: рядом вода — копает дальше, газ или магма — бросает выработку
## и роет шахту в другом месте.
func _answer_geologist() -> void:
	if not OS.get_environment("RECKLESS").is_empty():
		# Беспечный игрок: на любое предупреждение — «продолжить».
		for p: Project in colony.projects:
			if p.paused and not p.hazard_pending.is_empty():
				events["беспечно: " + p.hazard_pending] = events.get("беспечно: " + p.hazard_pending, 0) + 1
				colony.set_paused(p, false)
		return
	for p: Project in colony.projects.duplicate():
		# Дегазацию в газе копают на свой риск — иначе её не построить.
		if p.paused and p.hazard_pending == "methane" and _pending_purpose.get(p.id, -1) == RoomType.DEGAS:
			_act("дегазация на свой риск")
			colony.set_paused(p, false)
			continue
		if not p.paused or p.hazard_pending.is_empty() or p.hazard_pending == "methane":
			continue
		_act("геолог")
		if p.hazard_pending == "water":
			events["геолог: вода, копаем дальше"] = events.get("геолог: вода, копаем дальше", 0) + 1
			colony.set_paused(p, false)
			continue
		events["геолог: %s, обходим" % p.hazard_pending] = events.get("геолог: %s, обходим" % p.hazard_pending, 0) + 1
		colony.cancel_project(p)
		_pending_purpose.erase(p.id)
		if p.kind == Project.Kind.TUNNEL and p.rect.position.x == shaft_x:
			# Новая шахта в стороне.
			shaft_x += 12 if (shaft_x - colony.home.x) % 24 == 3 else -24
			shaft_bottom = world.gen.surface_y(shaft_x)


## Построенные комнаты получают задуманное назначение.
func _finish_purposes() -> void:
	for p in colony.projects:
		if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM and p.purpose == RoomType.NONE \
				and _pending_purpose.has(p.id):
			if colony.set_purpose(p, _pending_purpose[p.id]):
				_act("назначение")
				var names := {RoomType.HOME: "дом", RoomType.STORAGE: "склад", RoomType.FARM: "ферма",
					RoomType.LAB: "лаборатория", RoomType.DINING: "столовая", RoomType.KILN: "печь",
					RoomType.GENERATOR: "генератор", RoomType.PUMP: "насосная", RoomType.DEGAS: "дегазация",
					RoomType.GRANARY: "амбар", RoomType.HEARTH: "очаг"}
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


## Как играл бы человек: на каждое место работы — по жителю (лучшему из свободных),
## один-два строителя и подсобных; остальные — свободные.
func _professions() -> void:
	var adults := colony.units.filter(func(u: Unit) -> bool: return not u.child)
	var free := adults.filter(func(u: Unit) -> bool: return colony.is_free(u))
	# Роли — в первую очередь, иначе все уйдут на места работы.
	var want_roles := {Unit.Prof.BUILDER: maxi(1, adults.size() / 5),
		Unit.Prof.HAULER: (adults.size() / 6) if not colony.store_rooms().is_empty() else 0}
	for prof in want_roles:
		var have := adults.filter(func(u: Unit) -> bool: return u.workplace == 0 and u.profession == prof).size()
		while have < want_roles[prof] and free.size() > 1:
			colony.set_profession(free.pop_back(), prof)
			have += 1
			_act("роль")
	# Места работы: еда — в первую очередь.
	var order := [RoomType.FARM, RoomType.LAB, RoomType.GRANARY, RoomType.STORAGE, RoomType.KILN, RoomType.FORGE]
	var places: Array[Project] = []
	for t in order:
		places.append_array(colony.rooms_of(t))
	for p in colony.projects:
		if p.is_water_structure() and p.phase == Project.Phase.DONE:
			places.insert(0, p)
	var keep_free := 1 if adults.size() < 10 else adults.size() / 4
	for p in places:
		# Склад и амбар — по одному работнику (склад — когда людей хватает), остальное — сколько мест.
		var slots := 1 if RoomType.is_store(p.purpose) else colony.work_slots(p)
		# Склад и амбар без работника не наполняются — по одному всегда.
		if p.purpose == RoomType.FARM:
			slots = mini(slots, 1 if adults.size() < 7 else 2)
		if p.purpose == RoomType.LAB and adults.size() < 8:
			slots = 1
		while colony.assigned_to(p).size() < slots and free.size() > keep_free:
			free.sort_custom(func(a: Unit, b: Unit) -> bool: return colony.suitability(a, p) < colony.suitability(b, p))
			if not colony.assign_work(free.pop_back(), p).is_empty():
				break
			_act("назначение")


func _best_material() -> String:
	var mats := colony.available_materials()
	for m in ["brick", "stone", "clay", "wood"]:
		if mats.has(m) and colony.inventory.get(m, 0) >= 12:
			return m
	return "wood"


## Холодной ферме — очаг вплотную (малая комната 3×3 сбоку на том же уровне).
func _heat_farms() -> bool:
	for farm in colony.rooms_of(RoomType.FARM):
		if colony.farm_warm(farm):
			continue
		var has_hearth := false
		for p in colony.projects:
			var hearth: bool = p.purpose == RoomType.HEARTH or _pending_purpose.get(p.id, -1) == RoomType.HEARTH
			if hearth and absi(p.rect.get_center().x - farm.rect.get_center().x) <= 6 and absi(p.rect.get_center().y - farm.rect.get_center().y) <= 3:
				has_hearth = true
		if has_hearth:
			continue
		var spots: Array[Rect2i] = []
		for dy in [0, -3, 3]:
			for rx in [farm.rect.end.x, farm.rect.end.x + 1, farm.rect.position.x - 3, farm.rect.position.x - 4, farm.rect.position.x + 1, farm.rect.end.x - 4]:
				spots.append(Rect2i(rx, farm.rect.position.y + dy, 3, 3))
		for r in spots:
			var hc := r.get_center()
			var fc := farm.rect.get_center()
			if maxi(absi(hc.x - fc.x), absi(hc.y - fc.y)) > 4:
				continue
			if colony.validate(Project.Kind.ROOM, r, "wood").is_empty():
				var p := colony.create_project(Project.Kind.ROOM, r, -1, "wood")
				if p != null:
					_pending_purpose[p.id] = RoomType.HEARTH
					_act("очаг")
					return true
	return false


## Есть ли (или строится) комната с таким назначением.
func _has_room(t: int) -> bool:
	if _pending_purpose.values().has(t):
		return true
	for p in colony.projects:
		if p.kind == Project.Kind.ROOM and p.purpose == t:
			return true
	return false


func _need_home() -> bool:
	if colony.beds_total() >= colony.units.size() + 1 or _pending_purpose.values().has(RoomType.HOME):
		return false
	for p in colony.projects:
		if p.purpose == RoomType.HOME and p.phase != Project.Phase.DONE:
			return false
	return _surface_room(RoomType.HOME)


## Комната 6×3 на земле у базы (ищем ровное место всё дальше).
func _surface_room(purpose: int) -> bool:
	var mat := _best_material()
	# Материалы не нужны заранее: заложенная стройка сама позовёт жителей добыть недостающее.
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
	var labs := 0
	for p in colony.projects:
		if p.purpose == RoomType.LAB or _pending_purpose.get(p.id, -1) == RoomType.LAB:
			labs += 1
	if colony.units.size() >= 9 and labs < 2 and not colony.research.current.is_empty():
		return RoomType.LAB
	if colony.research.has("bricks") and not has.call(RoomType.KILN) and colony.known_resources.has("clay"):
		return RoomType.KILN
	if colony.research.has("electricity") and not has.call(RoomType.GENERATOR) \
			and colony.inventory.get("copper", 0) >= 4 and colony.inventory.get("iron", 0) >= 4:
		return RoomType.GENERATOR
	if not colony.elements.gas.is_empty() and not has.call(RoomType.DEGAS):
		return RoomType.DEGAS
	return -1


func _pier() -> bool:
	for p in colony.projects:
		if p.is_water_structure():
			return false
	var lake := world.gen.lake_at(55)
	if lake.is_empty() or colony.units.size() < 6:
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
			_surface_room(RoomType.GRANARY if k == "food" else RoomType.STORAGE)
			return
