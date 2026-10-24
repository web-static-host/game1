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
## Полуширина ствола: 0 — ствол в 1 м, 1 — ход бура в 3 м (комнаты ставятся за ним).
var shaft_half := 0
var side := 1
## Сколько раз ствол начинали заново в стороне (вода, лава впереди).
var _shaft_moves := 0
## Супер-гаврики и мутанты за всю игру (id).
var _ever_super := {}
var _ever_mutant := {}
var _pending_purpose := {}
## Сколько секунд стройка стоит с «Нет доступа» и места, где бот такую уже бросил.
var _stuck := {}
## Сколько секунд стройка ждёт материалов (id -> с).
var _short := {}
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
	# Продолжение из сохранения: ствол уже есть — копаем дальше самый глубокий, а не
	# начинаем новый с поверхности (там всё застроено, и бот переставал углубляться).
	if ship == null:
		for p in colony.projects:
			if p.kind == Project.Kind.TUNNEL and p.rect.size.y > p.rect.size.x and p.rect.end.y > shaft_bottom:
				shaft_x = p.rect.position.x
				shaft_bottom = p.rect.end.y


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
	# Кто рождался за всю игру (в итоге видны только живые).
	for u in colony.units:
		if not u.genome.is_empty():
			if Genetics.is_super(u.genome):
				_ever_super[u.id] = true
			if Genetics.is_mutant(u.genome):
				_ever_mutant[u.id] = true
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


## Подробный итог: что добыто, какие гаврики, супер-гаврики, где колонии.
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
	print("\n--- Гаврики (%d, детей %d) ---" % [colony.units.size(), colony.units.filter(func(u: Unit) -> bool: return u.child).size()])
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
	print("Супер-гаврики (бирюзовые): %d · мутанты: %d (живые сейчас); за всю игру — супер %d, мутантов %d" % [supers, mutants, _ever_super.size(), _ever_mutant.size()])
	print("Мир: %s" % world_name())


## Цвет гаврика словами: ближайший из основных.
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
	var keys := ["food", "fish", "berries", "wood", "stone", "clay", "coal", "iron", "copper", "brick", "methane",
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
		# Шахты копают шахтёры — стройкам они не мешают. Стройка, которая давно ждёт
		# материалов, — не занятость (иначе бот годами ничего не строил).
		if p.kind != Project.Kind.MINE and (p.phase != Project.Phase.DONE or p.repairing) \
				and float(_short.get(p.id, 0.0)) < 900.0 and not p.blocked.begins_with("Нет доступа"):
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
	# Начало игры: склад, амбар, лаборатория, мост, ферма и два дома — потом всё остальное.
	if _opening():
		return
	# Лес у базы на исходе, а за прудом есть — мост, пока есть из чего строить.
	if _bridge():
		return
	# Тепло ферме — важнее остальных строек.
	if _heat_farms():
		return
	if _space_program():
		return
	if _clay_mine():
		return
	if _drill_program() or _lift_program():
		return
	_mine_program()
	# Ствол углубляют всегда, когда прежний отрезок докопан, — не ждут, пока стройки
	# наверху закончатся (иначе на руду для ракеты не выйти никогда).
	if _deepen():
		return
	# Амбар (без него еда не копится на зиму) и дома (без кроватей нет детей) — вне очереди:
	# в «classic» колонии вымирали в первую зиму, пока бот ждал конца других строек.
	if not _has_room(RoomType.GRANARY) and not _pending_purpose.values().has(RoomType.GRANARY) \
			and _surface_room(RoomType.GRANARY):
		return
	if _need_home():
		return
	# Ферма и лаборатория — вне очереди: без них колония не живёт и не учится (лабораторию
	# мог разрушить обвал, а строек всегда много).
	var core := _next_underground()
	if (core == RoomType.FARM or core == RoomType.LAB) and _shaft():
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
func _bridge(opening := false) -> bool:
	var bridges := colony.projects.filter(func(q: Project) -> bool: return q.kind == Project.Kind.BRIDGE)
	if bridges.size() >= 2 or (not opening and _trees_reachable() >= 6):
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
	if best_d > 90 or best.size.x <= 0:
		return false
	# В начале игры мост закладывают сразу: дерево добудут, пока строится.
	if not opening and colony.inventory.get("wood", 0) + colony.drop_total("wood") < Project.cost_for(Project.Kind.BRIDGE, best)["wood"]:
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
			if colony.validate(Project.Kind.ROOM, top, mat).is_empty() and colony.can_reach(top):
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
				# Только туда, куда можно подойти: иначе дегазация висит «Нет доступа».
				if colony.validate(Project.Kind.ROOM, room, mat).is_empty() and colony.can_reach(room) and not _bad_spot(room):
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


## Как сделал бы игрок: стройку, к которой гаврикам не подойти (например, очаг на крыше
## подземной фермы или дегазацию в конце шахты), отменяет и больше на это место не ставит.
func _drop_stuck() -> void:
	# Задуманное для стройки, которой больше нет (отменили, рухнула), забываем — иначе
	# бот «помнит» лабораторию и новую не строит.
	for id in _pending_purpose.keys():
		if colony.project_by_id(id) == null:
			_pending_purpose.erase(id)
	# Ждёт материалов полчаса и больше (нет кирпича, железа) — отменяем, построим потом.
	for p in colony.projects.duplicate():
		if p.blocked.begins_with("Не хватает") and p.phase != Project.Phase.DONE:
			_short[p.id] = float(_short.get(p.id, 0.0)) + 5.0
			if _short[p.id] >= 1800.0 and (_pending_purpose.has(p.id) or p.kind == Project.Kind.ROOM):
				colony.cancel_project(p)
				_pending_purpose.erase(p.id)
				_short.erase(p.id)
				events["отмена: давно нет материалов"] = events.get("отмена: давно нет материалов", 0) + 1
		else:
			_short.erase(p.id)
	for p in colony.projects.duplicate():
		# Комнаты и отрезки у ствола ждут, пока до них докопают, — их бросают не сразу.
		var at_shaft: bool = p.rect.position.x == shaft_x + 1 or p.rect.end.x == shaft_x or p.rect.position.x == shaft_x
		var mine_work: bool = p.kind == Project.Kind.TUNNEL or p.kind == Project.Kind.MINE
		if (not _pending_purpose.has(p.id) and not mine_work) or p.phase == Project.Phase.DONE or not p.blocked.begins_with("Нет доступа"):
			_stuck.erase(p.id)
			continue
		_stuck[p.id] = _stuck.get(p.id, 0.0) + 5.0
		# Очаг бросают через 2 минуты, остальное — через 4, у ствола — через 10 (ствол
		# оборвался — копают новый рядом).
		var limit := 600.0 if at_shaft or mine_work else (120.0 if _is_hearth(p) else 240.0)
		if _stuck[p.id] >= limit:
			if p.kind == Project.Kind.TUNNEL and p.rect.position.x == shaft_x:
				_shaft_moves += 1
				var step := 9 * _shaft_moves
				shaft_x = colony.home.x + 3 + (step if _shaft_moves % 2 == 1 else -step)
				shaft_bottom = world.gen.surface_y(shaft_x)
				events["ствол оборвался — новый"] = events.get("ствол оборвался — новый", 0) + 1
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


## Как играл бы человек: на каждое место работы — по гаврику (лучшему из свободных),
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
	# Кузница плавит руду в металл и железо в сталь — по нормам (под ракету и стройки).
	for f in colony.rooms_of(RoomType.FORGE):
		f.targets = {"iron": 230, "copper": 60, "silver": 12, "gold": 12, "uranium": 22}
	for p in colony.projects:
		if p.is_water_structure() and p.phase == Project.Phase.DONE and (colony.can_fish_from(p) or p.kind == Project.Kind.PIER):
			places.append(p)
	# Ферма и лаборатория без работника, а свободных нет — снимаем со склада или амбара
	# (без еды и науки колония не выживет, а склад подождёт).
	for t in [RoomType.FARM, RoomType.LAB]:
		for p in colony.rooms_of(t):
			if not colony.assigned_to(p).is_empty() or free.size() > 0:
				continue
			for st in colony.store_rooms():
				var w: Array = colony.assigned_to(st)
				if not w.is_empty():
					colony.unassign_work(w[0])
					free.append(w[0])
					_act("перевод на ферму/в лабораторию")
					break
	var unstaffed_core := func() -> bool:
		for t in [RoomType.FARM, RoomType.LAB]:
			for q in colony.rooms_of(t):
				if colony.assigned_to(q).is_empty():
					return true
		return false
	# Лаборатория без учёного, а свободных нет — берём с мостков (рыбалка), складов или
	# фермы, где больше одного (раньше наука стояла годами).
	for lab in colony.rooms_of(RoomType.LAB):
		if not colony.assigned_to(lab).is_empty() or free.size() > 0 or not _base_reaches(lab):
			continue
		var donor: Unit = null
		for p in colony.projects:
			if donor != null:
				break
			var pw: Array = colony.assigned_to(p)
			if pw.is_empty():
				continue
			if p.is_water_structure() or RoomType.is_store(p.purpose) or (p.purpose == RoomType.FARM and pw.size() > 1):
				donor = pw[-1]
		if donor != null:
			colony.unassign_work(donor)
			free.append(donor)
			_act("в лабораторию")
	# Свободные нужны на стройки и подноску, но не в ущерб еде и науке.
	var keep_free := 0 if adults.size() < 8 else adults.size() / 5
	# Сначала по одному на каждую ферму и лабораторию, потом — остальные места.
	for p in places:
		if (p.purpose == RoomType.FARM or p.purpose == RoomType.LAB) and colony.assigned_to(p).is_empty() and not free.is_empty():
			free.sort_custom(func(a: Unit, b: Unit) -> bool: return colony.suitability(a, p) < colony.suitability(b, p))
			if colony.assign_work(free.pop_back(), p).is_empty():
				_act("назначение")
	for p in places:
		# Пока ферма или лаборатория без работника — на склады не назначаем.
		if RoomType.is_store(p.purpose) and adults.size() < 8 and unstaffed_core.call():
			continue
		# Склад и амбар — по одному работнику (склад — когда людей хватает), остальное — сколько мест.
		var slots := 1 if RoomType.is_store(p.purpose) else colony.work_slots(p)
		# Склад и амбар без работника не наполняются — по одному всегда.
		if p.purpose == RoomType.FARM:
			slots = mini(slots, 1) if adults.size() < 7 and not _winter_short() else slots
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
					var brick: bool = planet != "earth" and colony.research.has("pottery") and colony.inventory.get("brick", 0) >= 6
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


## Начало игры, как у толкового игрока: склад и амбар средние, лаборатория малая, мост
## через пруд, ферма большая и два больших дома — чтобы сразу пошли дети; потом очаг
## (ферме и домам). Шаги идут по порядку, одновременно строится не больше двух.
const OPENING := [[RoomType.STORAGE, 6], [RoomType.GRANARY, 6], [RoomType.LAB, 3], [-1, 0],
	[RoomType.FARM, 9], [RoomType.HOME, 9], [RoomType.HOME, 9]]
var _opening_skip := {}
var opening_done := false
## Как играет бот: "classic" — строит по нужде; "opening" — сначала стартовый набор (OPENING).
var style := "classic"


func _opening() -> bool:
	if style != "opening" or opening_done or planet != "earth":
		return false
	# Ферме нужно тепло (+15 °C): на поверхности так только летом, под землёй ~+10 °C —
	# поэтому к готовой ферме сразу очаг, иначе грибы не растут и к зиме голод.
	if _heat_farms():
		return true
	var building := 0
	var have := {}
	for p in colony.projects:
		var purpose: int = _pending_purpose.get(p.id, p.purpose)
		# Пока обустраивают — назначения ещё нет, но комната уже под него.
		if purpose == RoomType.NONE and p.phase == Project.Phase.EQUIP:
			purpose = RoomType.base_type(p.equip_target)
		if p.kind != Project.Kind.ROOM or purpose == RoomType.NONE:
			continue
		var key := "%d,%d" % [purpose, p.rect.size.x]
		have[key] = int(have.get(key, 0)) + 1
		if p.phase != Project.Phase.DONE and p.phase != Project.Phase.EQUIP:
			building += 1
	var used := {}
	for i in OPENING.size():
		var step: Array = OPENING[i]
		if _opening_skip.has(i):
			continue
		if step[0] < 0:
			if colony.projects.any(func(q: Project) -> bool: return q.kind == Project.Kind.BRIDGE):
				continue
			if building >= 2:
				return true
			if not _bridge(true):
				_opening_skip[i] = true
			return true
		var key := "%d,%d" % [step[0], step[1]]
		used[key] = int(used.get(key, 0)) + 1
		if int(have.get(key, 0)) >= int(used[key]):
			continue
		if building >= 2:
			return true
		if not _surface_room(step[0], step[1]):
			_opening_skip[i] = true
		return true
	opening_done = true
	_milestone("opening", "Начало обустроено: склад, амбар, лаборатория, ферма, два дома")
	return false


## Комната на земле у базы (ищем ровное место всё дальше).
func _surface_room(purpose: int, width := 6) -> bool:
	var mat := _best_material()
	# Материалы не нужны заранее: заложенная стройка сама позовёт гавриков добыть недостающее.
	for d in range(0, 60):
		for sx in [colony.home.x - 8 - d, colony.home.x + 6 + d]:
			if absi(sx - shaft_x) < 8 and sx <= shaft_x + 7:
				continue
			var s := world.gen.surface_y(sx)
			# На крышу готовой комнаты — второй этаж, иначе на землю.
			var r := Rect2i(sx, s - 3, width, 3)
			# Как игрок: не ставит туда, куда гаврикам не дойти (за обрывом).
			if not _bad_spot(r) and colony.validate(Project.Kind.ROOM, r, mat).is_empty() and colony.can_reach(r):
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
	# Ствол на Земле идёт вглубь без предела, пока есть чем крепить; на планете — только под комнаты.
	if want < 0 and planet != "earth":
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
		# Нефтекачалка — 9 м (качает на 40 м вокруг); когда людей много — большие лаборатории
		# (учат быстрее) и фермы; остальное — 6 м.
		var big := colony.units.size() >= 12 and (want == RoomType.LAB or want == RoomType.FARM)
		var rw := 9 if want == RoomType.OIL_PUMP or big else 6
		var rx := shaft_x + 1 + shaft_half if side > 0 else shaft_x - rw - shaft_half
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


## Следующие 10 м ствола, когда прежний отрезок докопан. Впереди подземная вода или лава —
## ствол начинают заново в стороне (вода — затопленные пещеры, они местные).
func _deepen() -> bool:
	if planet != "earth":
		return false
	# Сначала — чтобы колония встала на ноги: люди, ферма, лаборатория, еда к зиме.
	if colony.units.size() < 8 or colony.rooms_of(RoomType.FARM).is_empty() or _winter_short():
		return false
	for p in colony.projects:
		if p.kind == Project.Kind.TUNNEL and p.rect.position.x == shaft_x and p.phase != Project.Phase.DONE:
			return false
	var r := Rect2i(shaft_x, shaft_bottom, 1, 10)
	var err := colony.validate(Project.Kind.TUNNEL, r)
	if err.is_empty():
		if colony.create_project(Project.Kind.TUNNEL, r, 2) != null:
			shaft_bottom += 10
			_act("шахта глубже")
			var depth := shaft_bottom - world.gen.surface_y(shaft_x)
			for d in [50, 100, 200, 500, 1000]:
				if depth >= d:
					_milestone("depth%d" % d, "Шахта заложена до %d м" % d)
			return true
		return false
	# Упёрся в воду или лаву — или новый ствол на поверхности не встаёт (застроено) — в сторону.
	if (err.begins_with("В зоне стройки") or shaft_bottom == world.gen.surface_y(shaft_x)) and _shaft_moves < 16:
		events["ствол перенесён: " + err.split(" —")[0]] = events.get("ствол перенесён: " + err.split(" —")[0], 0) + 1
		_shaft_moves += 1
		var step := 9 * _shaft_moves
		shaft_x = colony.home.x + 3 + (step if _shaft_moves % 2 == 1 else -step)
		shaft_bottom = world.gen.surface_y(shaft_x)
		_act("новый ствол")
		return true
	return false


## Можно ли дойти до постройки от базы (колонию бывает разрезает обвалом).
func _base_reaches(p: Project) -> bool:
	var e := colony.pathing.explore(colony._ground_cell(colony.home.x))
	if Pathing.truncated(e[1]):
		return colony.can_reach(p.rect)
	return colony._near_rect(p.rect, e[1], true) != null or colony._reach_far(colony._ground_cell(colony.home.x), p.rect, e[0], e[1])


## Что строить под землёй дальше.
func _next_underground() -> int:
	var has := func(t: int) -> bool:
		if _pending_purpose.values().has(t):
			return true
		for p in colony.projects:
			# Ферма и лаборатория, до которых от базы не дойти, — как нет.
			if p.kind == Project.Kind.ROOM and p.purpose == t \
					and (not (t == RoomType.LAB or t == RoomType.FARM) or _base_reaches(p)):
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
	# Ферма на каждые четыре рта (зимой фермы под очагом еле справляются) и ещё одна,
	# если к зиме запаса мало.
	var farms := colony.rooms_of(RoomType.FARM).size()
	if colony.units.size() >= 7 and farms < (colony.units.size() + 3) / 4:
		return RoomType.FARM
	if _winter_short() and farms < colony.units.size() / 2 and not _pending_purpose.values().has(RoomType.FARM):
		return RoomType.FARM
	if not has.call(RoomType.DINING):
		return RoomType.DINING
	var labs := 0
	for p in colony.projects:
		if p.purpose == RoomType.LAB or _pending_purpose.get(p.id, -1) == RoomType.LAB:
			labs += 1
	if colony.units.size() >= 9 and labs < clampi(colony.units.size() / 5, 2, 4) and not colony.research.current.is_empty():
		return RoomType.LAB
	# Большая лаборатория (9 м) — когда людей хватает: технологии идут быстрее.
	if colony.units.size() >= 12 and not colony.research.current.is_empty() \
			and not colony.rooms_of(RoomType.LAB).any(func(q: Project) -> bool: return q.rect.size.x >= 9) \
			and not _pending_purpose.values().has(RoomType.LAB):
		return RoomType.LAB
	if colony.research.has("pottery") and not has.call(RoomType.KILN) and colony.known_resources.has("clay"):
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
	if colony.research.has("chemistry") and has.call(RoomType.DEGAS) and not has.call(RoomType.GAS_GEN) \
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
const ROCKET_PATH := ["mushrooms", "pottery", "geology", "carts", "apprentice", "smelting", "nature", "electricity",
	"scaffolding", "tools", "gas_masks", "gas_collector", "gas_heating", "geology2", "rails", "drill_rig",
	"mechanics", "oil_drilling", "refining", "combustion", "rocketry"]
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
	var want := {"iron": 110 + 30 + 20, "copper": 40 + 12, "gold": 10, "silver": 10, "diamond": 4, "brick": 36}
	var out := {}
	for k in want:
		# Руда — это будущий металл: 1 руда в кузнице — 3 металла.
		var left: int = int(want[k]) - int(colony.inventory.get(k, 0)) - 3 * int(colony.inventory.get(k + "_ore", 0))
		if left > 0:
			out[k] = left
	return out


## Мастерские на пути к ракете: печь, кузница, нефть, завод, генераторы.
func _production_room(has: Callable) -> int:
	if colony.research.has("smelting") and has.call(RoomType.KILN) and not has.call(RoomType.FORGE) \
			and colony.inventory.get("brick", 0) >= 8:
		return RoomType.FORGE
	if colony.research.has("electricity") and colony.power_used > colony.power_made \
			and colony.rooms_of(RoomType.GENERATOR).size() < 4 and colony.inventory.get("copper", 0) >= 4 \
			and colony.inventory.get("iron", 0) >= 4 and not _pending_purpose.values().has(RoomType.GENERATOR):
		return RoomType.GENERATOR
	var depth := shaft_bottom - world.gen.surface_y(shaft_x)
	# Каждые 60 м — склад у ствола: добытое не таскают наверх.
	if depth >= 50 and not _store_near(shaft_bottom, 60):
		return RoomType.STORAGE
	if colony.research.has("oil_drilling") and depth >= 205 and not has.call(RoomType.OIL_PUMP):
		return RoomType.OIL_PUMP
	if has.call(RoomType.OIL_PUMP) and not has.call(RoomType.OIL_TANK):
		return RoomType.OIL_TANK
	if colony.research.has("refining") and has.call(RoomType.OIL_TANK) and not has.call(RoomType.REFINERY):
		return RoomType.REFINERY
	return -1


## Есть ли склад (готовый или строящийся) у ствола не выше чем на rows от уровня y.
func _store_near(y: int, rows: int) -> bool:
	for p in colony.projects:
		var store: bool = p.purpose == RoomType.STORAGE or _pending_purpose.get(p.id, -1) == RoomType.STORAGE
		if store and absi(p.rect.get_center().x - shaft_x) <= 12 and y - p.rect.position.y >= 0 and y - p.rect.position.y <= rows:
			return true
	return false


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
			# Шахты дают руду («iron_ore»), а нужен металл («iron») — ищем руду нужного металла.
			var key := Mat.resource(m).trim_suffix("_ore")
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


## Запаса еды до весны не хватит: к зиме (за 3 месяца) и всю зиму еды должно быть на
## ~3 месяца вперёд.
func _winter_short() -> bool:
	var to_winter := colony.time_to_winter()
	if to_winter > Colony.MONTH * 4.0 and not colony.is_winter():
		return false
	return colony.food_value() < colony.units.size() * WINTER_FOOD


## Еды на гаврика на зиму (в «порциях» food_value).
const WINTER_FOOD := 60.0


## Буровая установка: ставится у дна ствола и сверлит вниз по 30 м — так ствол уходит
## глубже втрое быстрее, а широкий ход годится и под лифт.
var _drill_id := 0


func _drill_program() -> bool:
	if planet != "earth" or not colony.research.has("drill_rig") or not colony.powered():
		return false
	var drill := colony.project_by_id(_drill_id) if _drill_id != 0 else null
	if drill == null:
		_drill_id = 0
		if colony.inventory.get("iron", 0) < 6:
			return false
		for dx in [1, -3]:
			var r := Rect2i(shaft_x + dx, shaft_bottom - 3, 3, 3)
			if colony.validate(Project.Kind.DRILL, r).is_empty():
				var p := colony.create_project(Project.Kind.DRILL, r, 2)
				if p != null:
					_drill_id = p.id
					_act("бур")
					_milestone("drill", "Поставлен бур")
					return true
		return false
	if drill.phase != Project.Phase.DONE or colony.drilling(drill):
		return false
	var n := 30
	if colony.drill_error(drill, Vector2i.DOWN, n).is_empty():
		colony.start_drill(drill, Vector2i.DOWN, n)
		_act("бурение")
		# Новый ствол — ход бура: в него ставят комнаты и лифты.
		shaft_x = drill.rect.position.x + 1
		shaft_half = 1
		shaft_bottom = drill.rect.end.y + n
		_milestone("drilled", "Бур пошёл вниз")
		return true
	return false


## Пассажирский лифт от поверхности до дна ствола (рядом со стволом), когда шахта глубокая.
var _lift_done := false


func _lift_program() -> bool:
	if planet != "earth" or _lift_done or not colony.research.has("lifts") or not colony.powered():
		return false
	var s := world.gen.surface_y(shaft_x)
	if shaft_bottom - s < 50 or colony.inventory.get("iron", 0) < 8 or colony.inventory.get("copper", 0) < 4:
		return false
	for dx in [-2, 2, -3, 3]:
		var x: int = shaft_x + dx
		var r := Rect2i(x, world.gen.surface_y(x), 2, shaft_bottom - world.gen.surface_y(x))
		if colony.validate(Project.Kind.LIFT, r, "wood").is_empty() and colony.create_project(Project.Kind.LIFT, r, 2) != null:
			_lift_done = true
			_act("лифт")
			_milestone("lift", "Заложен лифт до дна ствола")
			return true
	return false


## Глина нужна на кирпич (печь → кузница → металл → ракета). Не нашли её — неглубокая
## шахта в подпочве у ствола, по одной в каждую сторону.
var _clay_tries := 0


func _clay_mine() -> bool:
	# Глина нужна, когда дело дошло до кузницы (плавка руды) — не раньше фермы и лаборатории.
	if planet != "earth" or colony.known_resources.has("clay") or _clay_tries >= 2 or colony.units.size() < 8 \
			or not colony.research.has("smelting"):
		return false
	var s := world.gen.surface_y(shaft_x)
	if shaft_bottom < s + 10:
		return false
	var sd := 1 if _clay_tries == 0 else -1
	_clay_tries += 1
	for d in [5, 7, 4, 8]:
		var r := Rect2i(shaft_x + 1, s + d, 20, 3) if sd > 0 else Rect2i(shaft_x - 20, s + d, 20, 3)
		if colony.validate(Project.Kind.MINE, r).is_empty() and colony.create_project(Project.Kind.MINE, r, 3) != null:
			_act("шахта за глиной")
			_milestone("clay_mine", "Шахта за глиной")
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
	var plan := [["wood", 60], ["food", 90], ["brick", 24], ["iron", 26]] if stat == "cold" \
		else [["wood", 70], ["food", 100], ["iron", 30]]
	for pair in plan:
		# Еду берут любую: грибы, рыбу, ягоды.
		var keys: Array = RoomType.FOOD_KEYS if pair[0] == "food" else [pair[0]]
		var want: int = int(pair[1])
		for k in keys:
			var n := mini(want, int(colony.inventory.get(k, 0)))
			n = mini(n, RoomType.SHIP_HOLD - total)
			if n > 0:
				cargo[k] = int(cargo.get(k, 0)) + n
				total += n
				want -= n
	var flight := colony.launch(pad, target_planet, crew, cargo)
	if flight.has("error"):
		return false
	launched += 1
	_milestone("launch%d" % launched, "СТАРТ ракеты на %s: гавриков %d, груз %s" % [Planet.planet_name(target_planet), crew.size(), cargo])
	if on_launch.is_valid():
		on_launch.call(flight)
	return true
