extends RefCounted
## Бот-«вовлечённый игрок» для одной колонии (на Земле или на планете): строит, копает,
## ведёт науку, назначает работу, отвечает геологу; копит вехи, события и смерти для отчёта.
## Используется в tests/longplay.gd (долгая игра) и tests/planet_trial.gd (высадка на планеты).

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
## Сколько секунд стройка стоит с «Нет доступа» и места, где бот такую уже бросил.
var _stuck := {}
var _bad_rects: Array[Rect2i] = []
var deaths: Array[String] = []
var births := 0


## Планета колонии ("earth", "mars", ...).
var planet := "earth"


func _init(c: Colony) -> void:
	colony = c
	world = c.world
	colony.event_logged.connect(_on_log)
	planet = world.gen.planet_id
	var ship := _ship()
	# На планете шахта идёт прямо из корабля вниз.
	shaft_x = ship.rect.position.x + 4 if ship != null else colony.home.x + 3
	shaft_bottom = ship.rect.end.y if ship != null else world.gen.surface_y(shaft_x)


func _ship() -> Project:
	for p in colony.projects:
		if p.purpose == RoomType.SHIP:
			return p
	return null


## Название мира для отчёта.
func world_name() -> String:
	return Planet.planet_name(planet)


## Раз в 5 секунд игры: ход игрока и учёт «затиший».
func think() -> void:
	_play()
	if t - last_news > 900.0:
		quiet.append("%s: 15 мин без новостей (жит %d, глубина %d м)" % [_time(), colony.units.size(), _depth()])
		last_news = t


## Итоговый отчёт по колонии.
func report() -> void:
	print("\n=========== %s ===========" % world_name().to_upper())
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
	_summary()
	print("\nДействий игрока: %d (%.1f в минуту), рождений: %d" % [actions.size(), actions.size() / maxf(1.0, t / 60.0), births])


## Подробный итог: что добыто, какие жители, сверхюниты, где колонии.
func _summary() -> void:
	print("\n--- Добыто и сделано за игру ---")
	var keys: Array = colony.produced.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return colony.produced[a] > colony.produced[b])
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %d" % [Mat.resource_name(k).to_lower(), colony.produced[k]])
	print(", ".join(parts) if not parts.is_empty() else "ничего")
	var inv: PackedStringArray = []
	for k in colony.inventory:
		if int(colony.inventory[k]) > 0:
			inv.append("%s %d" % [Mat.resource_name(k).to_lower(), colony.inventory[k]])
	print("В запасе: %s" % (", ".join(inv) if not inv.is_empty() else "пусто"))
	print("\n--- Жители (%d, детей %d) ---" % [colony.units.size(), colony.units.filter(func(u: Unit) -> bool: return u.child).size()])
	var cols := {}
	var shapes := {}
	var supers := 0
	var mutants := 0
	var shape_names := ["треугольные", "квадратные", "круглые"]
	for u in colony.units:
		if u.genome.is_empty():
			continue
		var cn := _color_name(u.genome)
		cols[cn] = int(cols.get(cn, 0)) + 1
		var sh: String = shape_names[Genetics.shape_of(u.genome)]
		shapes[sh] = int(shapes.get(sh, 0)) + 1
		if Genetics.is_super(u.genome):
			supers += 1
		if Genetics.is_mutant(u.genome):
			mutants += 1
	var cl: PackedStringArray = []
	var ck: Array = cols.keys()
	ck.sort_custom(func(a: String, b: String) -> bool: return cols[a] > cols[b])
	for k in ck:
		cl.append("%s %d" % [k, cols[k]])
	print("Цвета: %s" % ", ".join(cl))
	var sl: PackedStringArray = []
	for k in shapes:
		sl.append("%s %d" % [k, shapes[k]])
	print("Формы: %s" % ", ".join(sl))
	print("Сверхюниты (бирюзовые): %d · мутанты: %d" % [supers, mutants])
	print("Мир: %s" % world_name())


## Цвет жителя словами: ближайший из основных.
func _color_name(g: Dictionary) -> String:
	if Genetics.has(g, "albino"):
		return "альбиносы"
	if Genetics.has(g, "melanist"):
		return "чёрные"
	if Genetics.is_super(g):
		return "бирюзовые"
	var c := Genetics.color_of(g)
	var names := {"красные": Genetics.RED, "оранжевые": Genetics.ORANGE, "жёлтые": Genetics.YELLOW,
		"зелёные": Genetics.GREEN, "синие": Genetics.BLUE, "фиолетовые": Genetics.PURPLE, "розовые": Genetics.PINK,
		"голубые": Color(0, 0.8, 1)}
	var best := ""
	var best_d := INF
	for n in names:
		var d := absf(c.h - (names[n] as Color).h)
		d = minf(d, 1.0 - d)
		if d < best_d:
			best_d = d
			best = n
	return best


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
	for st in colony.store_rooms():
		print("DBGS %s %s раб %s нормы %s лежит %s дефицит %s" % [st.title(), st.rect, colony.assigned_to(st).map(func(u: Unit) -> String: return "%s:%s st%d" % [u.name, Unit.TASK_NAMES[u.task], u.state]), st.targets, st.held, colony.storage_deficit(st)])
	print("DBGF берег %s рыба %s" % [colony.shore_spots(), colony.fish])
	print("DBG %s еда %s ягоды %s ферм %d на земле еды %d" % [_time(), colony.inventory.get("food", 0),
		colony.inventory.get("berries", 0), farms.size(), colony.drop_total("food") + colony.drop_total("berries")])
	if not OS.get_environment("DEBUG_COLD").is_empty():
		for h in colony.rooms_of(RoomType.HEARTH):
			print("DBGH очаг %s горит %s blocked «%s» прогресс %.0f" % [h.rect, h.burning, h.blocked, h.farm_progress])
		for hm in colony.rooms_of(RoomType.HOME):
			print("DBGH дом %s темп %.1f" % [hm.rect, colony.room_temp(hm)])
		for u in colony.units:
			print("DBGU %s %s %s st%d здор %d темп %.1f предел %.1f" % [u.name, u.cell(), Unit.TASK_NAMES[u.task], u.state, roundi(u.health), colony.elements.temperature(u.cell()), Colony.cold_limit(u)])
		return
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
	var keys := ["food", "berries", "wood", "stone", "clay", "coal", "iron", "copper", "brick", "metal", "methane",
		"silver", "gold", "diamond", "uranium", "oil", "diesel"]
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
	print("[%4d с] %s%s | жит %d (дети %d) кроватей %d | построек %d, строится %d | глубина %d м | наука %d/%d | без дела %d | %s" % [
		Time.get_ticks_msec() / 1000, "" if planet == "earth" else "[%s] " % world_name(), _time(), colony.units.size(), colony.units.filter(func(u: Unit) -> bool: return u.child).size(), colony.beds_total(),
		done, colony.projects.size() - done, _depth(), colony.research.done.size(), Research.TECHS.size(), idle, ", ".join(inv)])


# --- Игрок -------------------------------------------------------------------------

func _busy() -> int:
	var n := 0
	for p in colony.projects:
		# Шахты копают шахтёры — стройкам они не мешают.
		if p.kind != Project.Kind.MINE and (p.phase != Project.Phase.DONE or p.repairing):
			n += 1
	return n


func _play() -> void:
	# IDLE=1 — игрок ничего не делает (проверка, что без игрока колония не выживает).
	if not OS.get_environment("IDLE").is_empty():
		return
	if planet != "earth":
		_play_planet()
		return
	_answer_geologist()
	_drop_stuck()
	_finish_purposes()
	_repairs()
	_marks()
	_science()
	_professions()
	if _fix_shaft():
		return
	if _fix_gas():
		return
	# К зиме — очаг у жилых домов (иначе замёрзнут).
	if _heat_homes():
		return
	# Лес у базы на исходе, а за прудом есть — мост, пока есть из чего строить.
	if _bridge():
		return
	# Тепло ферме — важнее остальных строек.
	if _heat_farms():
		return
	if _space_program():
		return
	_mine_program()
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


## На планете всё под землёй: воздуха снаружи нет, деревьев нет — дерево только из груза,
## поэтому бот строит только нужное. Шахта идёт из корабля вниз, комнаты — у шахты:
## ферма, дома, когда кроватей в корабле не хватает, лаборатория, склады; холодным
## фермам и домам — очаги.
func _play_planet() -> void:
	_answer_geologist()
	_drop_stuck()
	_finish_purposes()
	_repairs()
	_science()
	_professions()
	if _fix_shaft():
		return
	if _fix_gas():
		return
	if _heat_farms():
		return
	if _heat_rooms(colony.rooms_of(RoomType.HOME), Colony.COLD + 2.0):
		return
	if _busy() >= 2:
		return
	_shaft()


## Озёра не переплывают: если пруд отрезает округу — мост на другой берег (до двух мостов),
## как сделал бы игрок, когда у базы кончается лес и ягоды.
func _bridge() -> bool:
	var bridges := colony.projects.filter(func(q: Project) -> bool: return q.kind == Project.Kind.BRIDGE)
	if bridges.size() >= 2 or _trees_reachable() >= 6:
		return false
	var best := Rect2i()
	var best_d := 1 << 30
	for k in range(-6, 7):
		var l := world.gen._lake_of_segment(k)
		if l.is_empty():
			continue
		var sp := world.gen.lake_water_span(l)
		if sp.x > sp.y:
			continue
		var r := Rect2i(sp.x - 1, int(l["level"]) - 1, sp.y - sp.x + 3, 1)
		if bridges.any(func(q: Project) -> bool: return q.rect.intersects(r)):
			continue
		var d := mini(absi(sp.x - colony.home.x), absi(sp.y - colony.home.x))
		if d < best_d and colony.validate(Project.Kind.BRIDGE, r).is_empty():
			best = r
			best_d = d
	if best_d > 90:
		return false
	if colony.inventory.get("wood", 0) + colony.drop_total("wood") < Project.cost_for(Project.Kind.BRIDGE, best)["wood"]:
		return false
	if colony.create_project(Project.Kind.BRIDGE, best) != null:
		_act("мост")
		return true
	return false


## Сколько взрослых деревьев можно срубить, не переходя воду.
func _trees_reachable() -> int:
	var u: Unit = colony.units[0] if not colony.units.is_empty() else null
	if u == null:
		return 0
	var dist: Dictionary = colony.pathing.explore(u.cell())[1]
	var n := 0
	for x in range(colony.home.x - 90, colony.home.x + 91):
		if world.feature_at(x) == WorldGen.FEATURE_TREE and world.growth(x) >= 0.5:
			var g := world.gen.surface_y(x) - 1
			if dist.has(Vector2i(x - 1, g)) or dist.has(Vector2i(x + 1, g)) or dist.has(Vector2i(x, g)):
				n += 1
	return n


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
		# Дегазацию ставят выше, где газа нет (её радиус 15 м накроет выработку).
		for up in [0, 3, 6, 9, 12]:
			for rx in [shaft_x + 1, shaft_x - 6]:
				var room := Rect2i(rx, top - 3 - up, 6, 3)
				var mat := _best_material()
				if want == RoomType.DEGAS and colony.elements.gas_in(room.grow(2)) >= Elements.GAS_CLEAR:
					continue
				if colony.validate(Project.Kind.ROOM, room, mat).is_empty():
					var r := colony.create_project(Project.Kind.ROOM, room, -1, mat)
					if r != null:
						_pending_purpose[r.id] = want
						_act("насосная" if want == RoomType.PUMP else "дегазация")
						return true
	return false


## Метан остановил постройку (ферму, очаг, стройку) — дегазация рядом, где газа нет.
func _fix_gas() -> bool:
	for p in colony.projects:
		if p.hazard_pending != "methane":
			continue
		var c := p.rect.get_center()
		var covered := false
		for q in colony.projects.duplicate():
			var degas: bool = q.purpose == RoomType.DEGAS or _pending_purpose.get(q.id, -1) == RoomType.DEGAS
			if not degas or maxi(absi(q.rect.get_center().x - c.x), absi(q.rect.get_center().y - c.y)) > [10, 20, 40][clampi(RoomType.blocks(q), 1, 3) - 1] - 1:
				continue
			# Недостроенную дегазацию, которую саму остановил газ, переносят в чистое место.
			if q.phase != Project.Phase.DONE and q.hazard_pending == "methane":
				colony.cancel_project(q)
				_pending_purpose.erase(q.id)
				_act("перенос дегазации")
				continue
			covered = true
		if not OS.get_environment("DEBUG_GAS").is_empty():
			print("GAS %s %s covered %s" % [_time(), p.title(), covered])
		if covered:
			continue
		var mat := _best_material()
		# Большая дегазация (радиус 20 м) на земле над выработкой: наверху газа нет, стройке не мешает.
		# На безвоздушной планете на поверхность не выйти — только под землёй.
		for d in ([] if world.gen.airless() else [0, 6, -6, 12, -12]):
			var sx: int = c.x + d - 4
			var top := Rect2i(sx, world.gen.surface_y(sx) - 3, 9, 3)
			if maxi(absi(top.get_center().x - c.x), absi(top.get_center().y - c.y)) > 19:
				continue
			if colony.validate(Project.Kind.ROOM, top, mat).is_empty():
				var tr := colony.create_project(Project.Kind.ROOM, top, -1, mat)
				if tr != null:
					_pending_purpose[tr.id] = RoomType.DEGAS
					_act("дегазация над выработкой")
					return true
		for dy in [0, -3, 3, -6, 6, -9]:
			for rx in [p.rect.end.x, p.rect.end.x + 1, p.rect.position.x - 6, p.rect.position.x - 7, shaft_x + 1, shaft_x - 6]:
				var room := Rect2i(rx, p.rect.end.y - 3 + dy, 6, 3)
				if colony.elements.gas_in(room.grow(1)) >= Elements.GAS_CLEAR:
					continue
				if not OS.get_environment("DEBUG_GAS").is_empty():
					print("   try %s: %s" % [room, colony.validate(Project.Kind.ROOM, room, mat)])
				if colony.validate(Project.Kind.ROOM, room, mat).is_empty():
					var r := colony.create_project(Project.Kind.ROOM, room, -1, mat)
					if r != null:
						_pending_purpose[r.id] = RoomType.DEGAS
						_act("дегазация от метана")
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
					RoomType.GENERATOR: "генератор", RoomType.GAS_GEN: "газовый генератор", RoomType.PUMP: "насосная", RoomType.DEGAS: "дегазация",
					RoomType.GRANARY: "амбар", RoomType.HEARTH: "очаг", RoomType.HEARTH_BRICK: "очаг с кирпичными печами",
					RoomType.FORGE: "кузница", RoomType.OIL_PUMP: "нефтекачалка", RoomType.OIL_TANK: "нефтехранилище",
					RoomType.REFINERY: "нефтезавод", RoomType.LAUNCHPAD: "космодром"}
				_milestone("purpose%d" % _pending_purpose[p.id], "Первая комната: %s" % names.get(_pending_purpose[p.id], "?"))
			_pending_purpose.erase(p.id)


## Как сделал бы игрок: очаг, к которому жителям не подойти (например, на крыше
## подземной фермы), через пару минут отменяет и больше на это место не ставит.
## (Комнаты у шахты ждут тоннеля — их не трогаем.)
func _drop_stuck() -> void:
	for p in colony.projects.duplicate():
		if _pending_purpose.get(p.id, -1) != RoomType.HEARTH or p.phase == Project.Phase.DONE or not p.blocked.begins_with("Нет доступа"):
			_stuck.erase(p.id)
			continue
		_stuck[p.id] = _stuck.get(p.id, 0.0) + 5.0
		if _stuck[p.id] >= 120.0:
			_bad_rects.append(p.rect)
			colony.cancel_project(p)
			_pending_purpose.erase(p.id)
			_stuck.erase(p.id)
			_act("отмена недоступной стройки")


## Очаг — готовый, обустраиваемый (пока ставят печи, назначение ещё не задано) или в планах.
func _is_hearth(p: Project) -> bool:
	return p.purpose == RoomType.HEARTH or [RoomType.HEARTH, RoomType.HEARTH_BRICK].has(_pending_purpose.get(p.id, -1)) \
		or (p.phase == Project.Phase.EQUIP and [RoomType.HEARTH, RoomType.HEARTH_BRICK].has(p.equip_target))


func _bad_spot(r: Rect2i) -> bool:
	for b in _bad_rects:
		if b.intersects(r):
			return true
	return false


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
	# Сначала — цепочка к ракете, потом остальное.
	for id in ROCKET_PATH + Research.TECHS.keys():
		if colony.research.start(id):
			_act("наука")
			return


## Как играл бы человек: на каждое место работы — по жителю (лучшему из свободных),
## один-два строителя и подсобных; остальные — свободные.
func _professions() -> void:
	var adults := colony.units.filter(func(u: Unit) -> bool: return not u.child)
	var free := adults.filter(func(u: Unit) -> bool: return colony.is_free(u))
	# Роли — в первую очередь, иначе все уйдут на места работы.
	var mining := colony.projects.any(func(q: Project) -> bool: return q.kind == Project.Kind.MINE and q.phase == Project.Phase.DIG)
	var want_roles := {Unit.Prof.BUILDER: maxi(1, adults.size() / 5),
		Unit.Prof.HAULER: (adults.size() / 6) if not colony.store_rooms().is_empty() else 0,
		Unit.Prof.MINER: (2 if adults.size() < 15 else 3) if mining else 0}
	for prof in want_roles:
		var have := adults.filter(func(u: Unit) -> bool: return u.workplace == 0 and u.profession == prof).size()
		while have < want_roles[prof] and free.size() > 1:
			colony.set_profession(free.pop_back(), prof)
			have += 1
			_act("роль")
	# Места работы: еда — в первую очередь.
	# Еда, наука, хранение; рыбалка с мостков — когда людей хватает (зимой подо льдом).
	var order := [RoomType.FARM, RoomType.LAB, RoomType.GRANARY, RoomType.STORAGE, RoomType.KILN, RoomType.FORGE, RoomType.REFINERY]
	var places: Array[Project] = []
	for t in order:
		places.append_array(colony.rooms_of(t))
	# Кузница переводит железо в сталь, пока стали меньше нужного (железо нужно и само).
	for f in colony.rooms_of(RoomType.FORGE):
		if colony.inventory.get("metal", 0) >= 55 or colony.inventory.get("iron", 0) < 20:
			for u in colony.assigned_to(f):
				colony.unassign_work(u)
			places.erase(f)
	for p in colony.projects:
		if p.is_water_structure() and p.phase == Project.Phase.DONE and (colony.can_fish_from(p) or p.kind == Project.Kind.PIER):
			places.append(p)
	# Свободные нужны на стройки и подноску, но не в ущерб еде и науке.
	var keep_free := 0 if adults.size() < 8 else adults.size() / 5
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
	# На планете дерево только из груза — стены из камня (его выкапывают сами).
	if planet != "earth" and mats.has("stone"):
		return "stone"
	for m in ["brick", "stone", "clay", "wood"]:
		if mats.has(m) and colony.inventory.get(m, 0) >= 12:
			return m
	return "wood"


## Холодной ферме — очаг вплотную (малая комната 3×3 сбоку на том же уровне).
func _heat_farms() -> bool:
	return _heat_rooms(colony.rooms_of(RoomType.FARM), Colony.FARM_MIN_TEMP)


## Холодным комнатам (температура ниже need) — очаг вплотную, если рядом его ещё нет.
func _heat_rooms(rooms: Array, need: float) -> bool:
	for farm in rooms:
		if colony.room_temp(farm) >= need:
			continue
		# Очаги рядом складываются: если готовые горят, а всё ещё холодно — ещё один (до трёх).
		var near := 0
		var waiting := false
		for p in colony.projects:
			var hearth := _is_hearth(p)
			if hearth and absi(p.rect.get_center().x - farm.rect.get_center().x) <= 6 and absi(p.rect.get_center().y - farm.rect.get_center().y) <= 3:
				near += 1
				if p.phase != Project.Phase.DONE or not p.burning:
					waiting = true
		# На планете сразу два очага (одного не хватит), третий — если всё ещё холодно.
		if near >= (3 if planet != "earth" else 1) or (waiting and not (planet != "earth" and near < 2)):
			continue
		var spots: Array[Rect2i] = []
		for dy in [0, -3, 3]:
			for rx in [farm.rect.end.x, farm.rect.end.x + 1, farm.rect.position.x - 3, farm.rect.position.x - 4,
					farm.rect.end.x + 3, farm.rect.position.x - 6, farm.rect.position.x + 1, farm.rect.end.x - 4]:
				spots.append(Rect2i(rx, farm.rect.position.y + dy, 3, 3))
		for r in spots:
			var hc := r.get_center()
			var fc: Vector2i = farm.rect.get_center()
			if maxi(absi(hc.x - fc.x), absi(hc.y - fc.y)) > 7 or _bad_spot(r):
				continue
			var hm := "wood" if planet == "earth" else _best_material()
			if colony.validate(Project.Kind.ROOM, r, hm).is_empty():
				var p := colony.create_project(Project.Kind.ROOM, r, -1, hm)
				if p != null:
					# Кирпичные печи жгут и уголь (на планете дров нет — только из груза).
					var brick: bool = planet != "earth" and colony.research.has("bricks") and colony.inventory.get("brick", 0) >= 6
					_pending_purpose[p.id] = RoomType.HEARTH_BRICK if brick else RoomType.HEARTH
					_act("очаг")
					return true
	return false


## Жилые дома без очага рядом — малая комната-очаг вплотную (на земле или вторым этажом).
func _heat_homes() -> bool:
	# Утепляются к осени: летом тепло, а камень на очаг нужнее для шахты.
	if colony.time_to_winter() > Colony.MONTH * 3.0:
		return false
	for home in colony.rooms_of(RoomType.HOME):
		var warm := false
		for p in colony.projects:
			var hearth := _is_hearth(p)
			if hearth and absi(p.rect.get_center().x - home.rect.get_center().x) <= 7 and absi(p.rect.get_center().y - home.rect.get_center().y) <= 4:
				warm = true
		if warm:
			continue
		for r in [Rect2i(home.rect.end.x, home.rect.position.y, 3, 3), Rect2i(home.rect.position.x - 3, home.rect.position.y, 3, 3),
				Rect2i(home.rect.position.x, home.rect.position.y - 3, 3, 3), Rect2i(home.rect.end.x - 3, home.rect.position.y - 3, 3, 3)]:
			if _bad_spot(r):
				continue
			if colony.validate(Project.Kind.ROOM, r, "wood").is_empty():
				var q := colony.create_project(Project.Kind.ROOM, r, -1, "wood")
				if q != null:
					_pending_purpose[q.id] = RoomType.HEARTH
					_act("очаг у дома")
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
	# Ствол на Земле — до 230 м (нефть лежит глубже 200 м).
	if want < 0 and (shaft_bottom - s > 230 or planet != "earth"):
		return false
	var top := shaft_bottom
	var r := Rect2i(shaft_x, top, 1, 10)
	if colony.validate(Project.Kind.TUNNEL, r).is_empty():
		if colony.create_project(Project.Kind.TUNNEL, r, 2) != null:
			shaft_bottom = top + 10
			_act("шахта")
	# На планете верхние метры под кораблём — в холоде или жаре поверхности: комнаты глубже 15 м.
	if planet != "earth" and shaft_bottom - s < 16:
		return true
	if want >= 0:
		var floor_y := shaft_bottom - 1
		# Нефтекачалка — 9 м (качает на 40 м вокруг), остальное — 6 м.
		var rw := 9 if want == RoomType.OIL_PUMP else 6
		var rx := shaft_x + 1 if side > 0 else shaft_x - rw
		var room := Rect2i(rx, floor_y - 2, rw, 3)
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
	if planet != "earth":
		var homes_building := _pending_purpose.values().has(RoomType.HOME)
		if not homes_building and colony.beds_total() < colony.units.size() + 2:
			return RoomType.HOME
		if colony.units.size() >= 6 and colony.rooms_of(RoomType.FARM).size() < (colony.units.size() + 4) / 6:
			return RoomType.FARM
		for k in ["stone", "food"]:
			if colony.inventory.get(k, 0) >= colony.capacity(k) - 10 and not _pending_purpose.values().has(RoomType.STORAGE) \
					and not _pending_purpose.values().has(RoomType.GRANARY):
				return RoomType.GRANARY if k == "food" else RoomType.STORAGE
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
	if colony.units.size() >= 9 and labs < clampi(colony.units.size() / 5, 2, 4) and not colony.research.current.is_empty():
		return RoomType.LAB
	if colony.research.has("bricks") and not has.call(RoomType.KILN) and colony.known_resources.has("clay"):
		return RoomType.KILN
	if colony.research.has("electricity") and not has.call(RoomType.GENERATOR) \
			and colony.inventory.get("copper", 0) >= 4 and colony.inventory.get("iron", 0) >= 4:
		return RoomType.GENERATOR
	if planet == "earth":
		var prod := _production_room(has)
		if prod >= 0:
			return prod
	if not colony.elements.gas.is_empty() and not has.call(RoomType.DEGAS):
		return RoomType.DEGAS
	if colony.research.has("electricity") and has.call(RoomType.DEGAS) and not has.call(RoomType.GAS_GEN) \
			and colony.inventory.get("methane", 0) >= 20 \
			and colony.inventory.get("copper", 0) >= 4 and colony.inventory.get("iron", 0) >= 4:
		return RoomType.GAS_GEN
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


# --- Путь к ракете (Земля) ------------------------------------------------------------
## Цепочка исследований до ракетостроения — в первую очередь.
const ROCKET_PATH := ["agronomy", "electricity", "bricks", "geology", "carts", "metallurgy", "medicine", "geology2",
	"drilling", "education", "steam", "drill_rig", "automation", "oil_drilling", "refining", "combustion", "rocketry"]
## Уровни разведочных шахт (м от поверхности): по 40 м в обе стороны от ствола.
const EXPLORE_LEVELS := [30, 55, 80, 105, 130, 155, 185, 215]
## Куда лететь (задаёт запускающий скрипт) и как отправить ракету: on_launch(flight).
var target_planet := "mars"
var on_launch: Callable
var launched := 0
var _scan_t := -1000.0
var _explored := {}
var _ext := {}


## Чего ещё не хватает на ракету, космодром и мастерские (сверх того, что на складе).
func rocket_need() -> Dictionary:
	var want := {"iron": 80 + 30, "metal": 30 + 20, "copper": 40 + 12, "gold": 10, "silver": 10, "diamond": 4, "brick": 36}
	var out := {}
	for k in want:
		var left: int = int(want[k]) - int(colony.inventory.get(k, 0))
		if left > 0:
			out[k] = left
	# Сталь куют из железа: на нехватку стали — вдвое больше железа.
	if out.has("metal"):
		out["iron"] = int(out.get("iron", 0)) + 2 * int(out["metal"])
	return out


## Мастерские на пути к ракете: печь, кузница, нефть, завод, генераторы.
func _production_room(has: Callable) -> int:
	if colony.research.has("metallurgy") and has.call(RoomType.KILN) and not has.call(RoomType.FORGE) \
			and colony.inventory.get("brick", 0) >= 8:
		return RoomType.FORGE
	if colony.research.has("electricity") and colony.power_used > colony.power_made \
			and colony.rooms_of(RoomType.GENERATOR).size() < 4 and colony.inventory.get("copper", 0) >= 4 \
			and colony.inventory.get("iron", 0) >= 4 and not _pending_purpose.values().has(RoomType.GENERATOR):
		return RoomType.GENERATOR
	var depth := shaft_bottom - world.gen.surface_y(shaft_x)
	if colony.research.has("oil_drilling") and depth >= 205 and not has.call(RoomType.OIL_PUMP):
		return RoomType.OIL_PUMP
	if has.call(RoomType.OIL_PUMP) and not has.call(RoomType.OIL_TANK):
		return RoomType.OIL_TANK
	if colony.research.has("refining") and has.call(RoomType.OIL_TANK) and not has.call(RoomType.REFINERY):
		return RoomType.REFINERY
	return -1


## Шахты за рудой: видимая жила нужного металла (или кимберлит, если нужны алмазы) —
## шахта от ствола к ней; не видно — разведочные шахты на уровнях ствола.
func _mine_program() -> bool:
	if colony.units.size() < 8 or t - _scan_t < 30.0:
		return false
	_scan_t = t
	var active := colony.projects.filter(func(q: Project) -> bool: return q.kind == Project.Kind.MINE and q.phase == Project.Phase.DIG)
	if active.size() >= 2:
		return false
	var need := rocket_need()
	if need.is_empty():
		return false
	var target = _find_ore(need)
	if target != null and _mine_to(target):
		return true
	return _explore_mine(need.has("diamond"))


func _find_ore(need: Dictionary) -> Variant:
	var want := []
	for k in ["diamond", "gold", "silver", "copper", "iron"]:
		if need.has(k):
			want.append(k)
	var best = null
	var best_score := 1 << 30
	for x in range(shaft_x - 100, shaft_x + 101):
		var s := world.gen.surface_y(x)
		for y in range(s + 20, shaft_bottom - 1):
			if not world.is_revealed(x, y) or world.is_dug(x, y):
				continue
			var m := world.get_mat(x, y)
			var key := Mat.resource(m)
			if m == Mat.KIMBERLITE:
				key = "diamond"
			var rank := want.find(key)
			if rank < 0:
				continue
			var score := absi(x - shaft_x) + rank * 30
			if score < best_score:
				best_score = score
				best = Vector2i(x, y)
	return best


## Шахта от ствола до клетки c (не длиннее 64 м за раз).
func _mine_to(c: Vector2i) -> bool:
	for y0 in [c.y - 1, c.y - 2, c.y]:
		if y0 + 3 > shaft_bottom:
			continue
		var r: Rect2i
		if c.x > shaft_x:
			r = Rect2i(shaft_x + 1, y0, mini(c.x - shaft_x, 64), 3)
		else:
			var len := mini(shaft_x - c.x, 64)
			r = Rect2i(shaft_x - len, y0, len, 3)
		if r.size.x < 2:
			continue
		if colony.validate(Project.Kind.MINE, r).is_empty() and colony.create_project(Project.Kind.MINE, r, 3) != null:
			_act("шахта к руде")
			return true
	return false


## Разведочные шахты по 40 м в обе стороны; когда уровни пройдены, а алмазов нет —
## глубокие разведочные шахты продлевают дальше в стороны (до 250 м).
func _explore_mine(diamonds: bool) -> bool:
	var s := world.gen.surface_y(shaft_x)
	for d in EXPLORE_LEVELS:
		for sd in [1, -1]:
			var key := "%d:%d" % [d, sd]
			if _explored.has(key):
				continue
			if s + d + 3 > shaft_bottom:
				return false
			_explored[key] = true
			for dy in [0, 3, -3, 5]:
				var y0: int = s + d + dy
				var r := Rect2i(shaft_x + 1, y0, 40, 3) if sd > 0 else Rect2i(shaft_x - 40, y0, 40, 3)
				if colony.validate(Project.Kind.MINE, r).is_empty() and colony.create_project(Project.Kind.MINE, r, 3) != null:
					_act("разведочная шахта")
					return true
	if not diamonds:
		return false
	for m in colony.projects:
		if m.kind != Project.Kind.MINE or m.phase != Project.Phase.DONE or m.rect.position.y < s + 120:
			continue
		var far := m.rect.end.x - shaft_x if m.rect.position.x > shaft_x else shaft_x - m.rect.position.x
		if far >= 250 or int(_ext.get(m.id, 0)) >= 8:
			continue
		var dir := Vector2i.RIGHT if m.rect.position.x > shaft_x else Vector2i.LEFT
		if colony.extend_error(m, dir, 30).is_empty() and colony.extend_project(m, dir, 30) != null:
			_ext[m.id] = int(_ext.get(m.id, 0)) + 1
			_act("разведка дальше")
			return true
	return false


## Космодром на поверхности, сборка ракеты, запуск экспедиции.
func _space_program() -> bool:
	if planet != "earth" or not colony.research.has("rocketry"):
		return false
	var pad: Project = null
	for p in colony.projects:
		if p.purpose == RoomType.LAUNCHPAD or _pending_purpose.get(p.id, -1) == RoomType.LAUNCHPAD \
				or (p.phase == Project.Phase.EQUIP and p.equip_target == RoomType.LAUNCHPAD):
			pad = p
	if pad == null:
		return _launchpad()
	if pad.purpose != RoomType.LAUNCHPAD or pad.phase != Project.Phase.DONE:
		return false
	if pad.rocket.is_empty():
		if pad.equip_rocket.is_empty() and pad.phase == Project.Phase.DONE:
			var err := colony.start_rocket(pad, "chem")
			if err.is_empty():
				_milestone("rocket_start", "Начали собирать ракету")
				_act("ракета")
			return err.is_empty()
		return false
	return _launch(pad)


func _launchpad() -> bool:
	var mat := _best_material()
	for d in range(0, 80):
		for sx in [colony.home.x - 12 - d, colony.home.x + 10 + d]:
			var s := world.gen.surface_y(sx)
			var r := Rect2i(sx, s - 3, 6, 3)
			var sky := true
			for x in range(r.position.x, r.end.x):
				for y in range(r.position.y - 14, r.position.y):
					if not world.is_open(x, y) or colony.project_at(Vector2i(x, y)) != null:
						sky = false
			if sky and colony.validate(Project.Kind.ROOM, r, mat).is_empty():
				var p := colony.create_project(Project.Kind.ROOM, r, -1, mat)
				if p != null:
					_pending_purpose[p.id] = RoomType.LAUNCHPAD
					_milestone("pad", "Заложен космодром")
					_act("космодром")
					return true
	return false


## Экипаж — до 10 взрослых, лучше всего переносящих планету (парами), груз — что нужно там.
func _launch(pad: Project) -> bool:
	var temp: float = Planet.data(target_planet)["under"]
	var stat := "cold" if temp < 5.0 else "heat"
	var adults := colony.units.filter(func(u: Unit) -> bool: return not u.child and not u.is_elder())
	if adults.size() < 12:
		return false
	adults.sort_custom(func(a: Unit, b: Unit) -> bool: return a.stat(stat) > b.stat(stat))
	var crew: Array = []
	for u in adults:
		if crew.size() >= RoomType.SHIP_BEDS:
			break
		if crew.has(u):
			continue
		crew.append(u)
		var partner := colony.unit_by_id(u.partner_id)
		if partner != null and not partner.child and crew.size() < RoomType.SHIP_BEDS and not crew.has(partner):
			crew.append(partner)
	var cargo := {}
	var total := 0
	for pair in [["wood", 100], ["food", 60], ["metal", 30], ["coal", 10]]:
		var n := mini(int(pair[1]), int(colony.inventory.get(pair[0], 0)))
		n = mini(n, RoomType.SHIP_HOLD - total)
		if n > 0:
			cargo[pair[0]] = n
			total += n
	var flight := colony.launch(pad, target_planet, crew, cargo)
	if flight.has("error"):
		return false
	launched += 1
	_milestone("launch%d" % launched, "СТАРТ ракеты на %s: жителей %d, груз %s" % [Planet.planet_name(target_planet), crew.size(), cargo])
	if on_launch.is_valid():
		on_launch.call(flight)
	return true
