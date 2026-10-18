extends SceneTree
## Автотесты логики мира. Запуск:
##   godot --headless --path . -s res://tests/run_tests.gd

var _failed := 0
var _passed := 0


func _initialize() -> void:
	test_hash_range()
	test_generation_deterministic()
	test_surface_and_layers()
	test_deep_geology()
	test_project_rules()
	test_offline_build()
	test_pause_and_materials()
	test_units_realtime()
	test_room_from_surface_realtime()
	test_workers_and_ladder()
	test_room_materials()
	test_site_keeps_yield()
	test_new_room_load()
	test_mine()
	test_geology_levels()
	test_room_purposes()
	test_needs_realtime()
	test_family()
	test_aging()
	test_tunnel_throughput()
	test_professions()
	test_roles()
	test_build_rules_v2()
	test_physics()
	test_nature()
	test_slices()
	test_lakes_and_fishing()
	test_hauling()
	test_storage_workers()
	test_wear_and_repair()
	test_calendar()
	test_seasons()
	test_darkness()
	test_elements()
	test_gas_alarm()
	test_scouting()
	test_tech_tree()
	test_genetics()
	test_residents()
	test_loads()
	test_economy()
	test_drops_and_scouting()
	test_food_balance()
	test_build_priority()
	test_idle_spread()
	test_buried_drop()
	test_separate_stores()
	test_mine_meters()
	test_lights()
	test_save_roundtrip()
	test_environment()
	test_generation_speed()
	print("\nИтого: %d пройдено, %d провалено" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("ПРОВАЛ: " + what)


func test_hash_range() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 2000:
		var h := WorldGen.hash01(i * 7 - 5000, -i * 13, 42)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	check(lo >= 0.0 and hi < 1.0 and hi - lo > 0.9, "hash01 в [0,1) и хорошо распределён")


func test_generation_deterministic() -> void:
	var a := WorldGen.new(12345).generate_chunk(3, 5)
	var b := WorldGen.new(12345).generate_chunk(3, 5)
	var c := WorldGen.new(54321).generate_chunk(3, 5)
	check(a.mat == b.mat and a.flags == b.flags, "одинаковый seed → одинаковый чанк")
	check(a.mat != c.mat, "разный seed → разный чанк")
	# Отрицательные координаты и огромные расстояния.
	var far := WorldGen.new(1).generate_chunk(-100000, 2000)
	check(far.mat.size() == 1024, "дальний чанк генерируется")


func test_surface_and_layers() -> void:
	var gen := WorldGen.new(777)
	for x in [-5000, -37, 0, 1, 999, 123456]:
		var s := gen.surface_y(x)
		if gen.water_level(x) < s:
			continue # в озере над дном вода, дно — песок
		check(gen.material_at(x, s - 1) == Mat.AIR, "над поверхностью воздух (x=%d)" % x)
		check(gen.material_at(x, s) == Mat.TOPSOIL, "на поверхности почва (x=%d)" % x)
		check(absi(s) < 80, "рельеф в разумных пределах (x=%d, y=%d)" % [x, s])
	var c := gen.generate_chunk(0, gen.surface_y(0) >> 5)
	var lx := 0
	var s0 := gen.surface_y(0)
	var i := ChunkData.idx(lx, s0 & 31)
	check(c.flags[i] & ChunkData.F_REVEALED != 0, "поверхность видна сразу")


func _histogram(gen: WorldGen, depth: int, width: int, height: int) -> Dictionary:
	var h := {}
	for x in range(0, width):
		var s := gen.surface_y(x * 3)
		for dy in range(0, height):
			var m := gen.material_at(x * 3, s + depth + dy)
			h[m] = h.get(m, 0) + 1
	return h


func test_deep_geology() -> void:
	var gen := WorldGen.new(2024)
	var shallow := _histogram(gen, 30, 200, 40)
	var mid := _histogram(gen, 1200, 200, 40)
	var deep := _histogram(gen, 20000, 200, 40)
	var sed := 0
	for m in [Mat.SANDSTONE, Mat.SHALE, Mat.LIMESTONE, Mat.COAL, Mat.AQUIFER]:
		sed += shallow.get(m, 0)
	check(sed > 4000, "на 30 м — осадочные породы (%d)" % sed)
	check(mid.get(Mat.GRANITE, 0) + mid.get(Mat.GNEISS, 0) > 4000, "на 1.2 км — гранит/гнейс")
	check(deep.get(Mat.BASALT, 0) > 2000, "на 20 км много базальта (%d)" % deep.get(Mat.BASALT, 0))
	check(not shallow.has(Mat.MAGMA) and not mid.has(Mat.MAGMA), "магмы нет на малых глубинах")
	var ores_shallow := 0
	var ores_mid := 0
	for m in [Mat.IRON_ORE, Mat.COPPER_ORE, Mat.SILVER_ORE, Mat.GOLD_ORE, Mat.URANIUM_ORE]:
		ores_shallow += shallow.get(m, 0)
		ores_mid += mid.get(m, 0)
	check(ores_mid > ores_shallow, "глубже руды больше (%d > %d)" % [ores_mid, ores_shallow])
	var kinds_mid := 0
	for m in [Mat.IRON_ORE, Mat.COPPER_ORE, Mat.SILVER_ORE, Mat.GOLD_ORE, Mat.URANIUM_ORE]:
		if mid.get(m, 0) > 0:
			kinds_mid += 1
	check(kinds_mid >= 3, "глубже руды разнообразнее (%d видов)" % kinds_mid)
	var mantle := _histogram(gen, 40000, 100, 20)
	check(mantle.get(Mat.PERIDOTITE, 0) + mantle.get(Mat.MAGMA, 0) == 2000, "на 40 км — мантия")
	print("  руда 30 м: %d, 1.2 км: %d; базальт 20 км: %d; магма 40 км: %d" % [
		ores_shallow, ores_mid, deep.get(Mat.BASALT, 0), mantle.get(Mat.MAGMA, 0)])


func _find_solid_column(world: WorldData, from := 0) -> int:
	for x in range(from, from + 400):
		var s := world.gen.surface_y(x)
		var ok := world.gen.feature_at(x) == WorldGen.FEATURE_NONE
		for d in range(0, 14):
			for dx in range(0, 6):
				if not Mat.is_diggable(world.get_mat(x + dx, s + d)):
					ok = false
		if ok:
			return x
	return from


func _new_colony(seed_value: int) -> Colony:
	var world := WorldData.new(WorldGen.new(seed_value))
	var colony := Colony.new(world)
	colony.inventory = {"wood": 20, "stone": 15}
	return colony


func test_project_rules() -> void:
	var colony := _new_colony(5)
	var w := colony.world
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	var T := Project.Kind.TUNNEL
	var R := Project.Kind.ROOM
	check(not colony.validate(T, Rect2i(x, s, 5, 1)).is_empty(), "тоннель высотой 1 м запрещён")
	check(colony.validate(T, Rect2i(x, s, 1, 6)).is_empty(), "шахта 1×6 разрешена")
	check(colony.validate(T, Rect2i(x, s, 8, 2)).is_empty(), "штрек 8×2 разрешён")
	check(not colony.validate(T, Rect2i(x, s, 5, 5)).is_empty(), "тоннель 5×5 — это уже комната")
	check(not colony.validate(R, Rect2i(x, s, 2, 2)).is_empty(), "комната 2×2 слишком мала")
	check(colony.validate(R, Rect2i(x, s - 3, 4, 3)).is_empty(), "комната на земле разрешена")
	check(not colony.validate(R, Rect2i(x, s - 20, 4, 3)).is_empty(), "висящая в воздухе комната запрещена")
	colony.create_project(T, Rect2i(x, s, 1, 6))
	check(not colony.validate(R, Rect2i(x - 1, s + 2, 4, 3)).is_empty(), "стройки не пересекаются")


func test_offline_build() -> void:
	var colony := _new_colony(99)
	var w := colony.world
	_start(colony, 0)
	check(colony.inventory.is_empty(), "на старте склад пуст")
	colony.inventory = {"wood": 20, "stone": 15}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	check(not w.is_revealed(x, s + 3), "глубже поверхности — неизвестность")
	var shaft := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 6))
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(x + 1, s + 3, 4, 3))
	check(shaft != null and room != null, "стройки заложены")
	var wood_before: int = colony.inventory["wood"]
	var dug := colony.advance_offline(20000.0)
	check(dug >= 6 + 12, "выкопаны шахта и комната, с учётом осыпей (%d)" % dug)
	check(shaft.phase == Project.Phase.DONE and room.phase == Project.Phase.DONE, "обе стройки завершены")
	check(colony.inventory["wood"] < wood_before + 20, "дерево потрачено на стройку")
	check(not room.found.is_empty(), "при копке найдены ресурсы")
	check(colony.interior.has(Vector2i(x + 2, s + 4)), "клетки комнаты стали интерьером")
	check(w.is_revealed(x + 5, s + 4), "стены комнаты открыты")
	check(not w.is_revealed(x + 8, s + 4), "дальше стен — по-прежнему неизвестно")
	# Подтопленная выработка — не озеро: до воды доходят и плывут по её поверхности.
	w.set_fluid(x, s + 4, Mat.WATER)
	w.set_fluid(x, s + 5, Mat.WATER)
	colony.pathing.clear_cache()
	var down := Pathing.path_to(colony.pathing.explore(Vector2i(x, s))[0], Vector2i(x, s + 4))
	check(not down.is_empty(), "в подтопленной шахте доплывают до воды")


func test_pause_and_materials() -> void:
	var colony := _new_colony(7)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	var p := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 4))
	colony.set_paused(p, true)
	check(colony.advance_offline(5000.0) == 0, "на паузе работы не идут")
	colony.set_paused(p, false)
	# Дерева нет — жители рубят по нужде: сначала отмеченное игроком.
	var tree := 0
	for d in range(0, 200):
		if w.feature_at(colony.home.x + d) == WorldGen.FEATURE_TREE:
			tree = colony.home.x + d
			break
		if w.feature_at(colony.home.x - d) == WorldGen.FEATURE_TREE:
			tree = colony.home.x - d
			break
	check(colony.toggle_harvest(tree).is_empty(), "дерево отмечено на сбор")
	colony.advance_offline(5000.0)
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE or colony.inventory.get("wood", 0) + colony.drop_total("wood") > 0, "дерево срублено по нужде стройки")
	check(p.phase == Project.Phase.DONE, "дерево пошло на укрепление — стройка завершена")


func test_units_realtime() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	var x := _find_solid_column(w, 0)
	_start(colony, x)
	colony.inventory = {"wood": 20, "stone": 15}
	var s := w.gen.surface_y(x)
	var shaft := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 5))
	var drift := colony.create_project(Project.Kind.TUNNEL, Rect2i(x + 1, s + 3, 4, 2))
	var t := 0.0
	while t < 3000.0 and drift.phase != Project.Phase.DONE:
		colony.update(1.0)
		t += 1.0
	check(shaft.phase == Project.Phase.DONE, "жители выкопали и укрепили шахту")
	check(drift.phase == Project.Phase.DONE, "жители прошли по шахте и сделали штрек (%.0f с)" % t)
	var below := 0
	for u in colony.units:
		if u.pos.y > s:
			below += 1
	check(below > 0, "жители спустились под землю")
	for u in colony.units:
		if u.state == Unit.State.MOVE:
			continue # идущий может быть посреди шага или вброд
		check(colony.pathing.standable(u.cell()), "%s стоит на опоре (%s %s st%d)" % [u.name, u.cell(), Unit.TASK_NAMES[u.task], u.state])
	# Сбор дерева онлайн.
	var tree := 0
	for tx in range(x - 60, x + 60):
		if w.feature_at(tx) == WorldGen.FEATURE_TREE:
			tree = tx
			break
	# Рубят отмеченное и носят на склад только работники склада.
	var store := _fake_room(colony, RoomType.STORAGE, x - 10)
	check(colony.assign_work(colony.units[0], store).is_empty(), "житель назначен на склад")
	colony.toggle_harvest(tree)
	var wood: int = colony.inventory.get("wood", 0)
	t = 0.0
	var on_ground := false
	while t < 1500.0 and w.feature_at(tree) != WorldGen.FEATURE_NONE:
		colony.update(0.2)
		t += 0.2
		if colony.drop_amount(colony._ground_cell(tree), "wood") > 0:
			on_ground = true
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE and on_ground, "житель срубил дерево, дрова лежат на месте рубки (%.0f с)" % t)
	t = 0.0
	while t < 1500.0 and (colony.inventory.get("wood", 0) <= wood or colony.drop_total("wood") > 0):
		colony.update(1.0)
		t += 1.0
	check(colony.drop_total("wood") == 0 and colony.inventory.get("wood", 0) > wood, "дрова отнесли на склад (%.0f с)" % t)


func test_room_from_surface_realtime() -> void:
	# Раньше жители выкапывали верхний ряд комнаты и не могли спуститься внутрь.
	for seed_value in [1, 2, 4]:
		var colony := _new_colony(seed_value * 1000 + 6)
		var w := colony.world
		_start(colony, 0)
		colony.inventory = {"wood": 40, "stone": 30}
		var s := w.gen.surface_y(4)
		var room := colony.create_project(Project.Kind.ROOM, Rect2i(3, s, 6, 3))
		var t := 0.0
		while t < 2000.0 and room.phase != Project.Phase.DONE:
			colony.update(0.2)
			t += 0.2
		check(room.phase == Project.Phase.DONE, "комната с поверхности построена (seed %d, %.0f с)" % [seed_value, t])
		# Тоннель вбок от пола готовой комнаты.
		var drift := colony.create_project(Project.Kind.TUNNEL, Rect2i(9, s + 1, 5, 2))
		check(drift != null, "тоннель из комнаты заложен")
		if drift == null:
			continue
		t = 0.0
		while t < 2000.0 and drift.phase != Project.Phase.DONE:
			colony.update(0.2)
			t += 0.2
		check(drift.phase == Project.Phase.DONE, "жители вышли из комнаты и прокопали тоннель (seed %d)" % seed_value)
	check(not _new_colony(3).has_access(Rect2i(0, 50, 4, 2)), "у зоны в толще породы нет доступа")


func test_workers_and_ladder() -> void:
	var colony := _new_colony(77)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	colony.inventory = {"wood": 50, "stone": 50}
	var s := w.gen.surface_y(x)
	check(Project.recommended_workers(Project.Kind.TUNNEL, Rect2i(0, 0, 1, 6), 5) == 1, "на шахту 1×6 рекомендуется 1 рабочий")
	check(Project.recommended_workers(Project.Kind.ROOM, Rect2i(0, 0, 8, 4), 5) == 4, "на комнату 8×4 — 4 рабочих")
	check(Project.recommended_workers(Project.Kind.ROOM, Rect2i(0, 0, 24, 8), 5) == 5, "не больше, чем жителей")
	var p := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 3, 8), 2)
	var max_seen := 0
	for i in 300:
		colony.update(0.5)
		max_seen = maxi(max_seen, colony.workers_on(p))
	check(max_seen == 2, "на стройке не больше выбранных 2 рабочих (было %d)" % max_seen)
	var sunk := colony.create_project(Project.Kind.ROOM, Rect2i(x + 3, s + 4, 4, 3))
	check(sunk != null and sunk.ladder, "у подземной комнаты есть лестница")
	var ground := 0
	for tx in range(x + 20, x + 200):
		var ts := w.gen.surface_y(tx)
		var flat := true
		for dx in range(-1, 5):
			if w.gen.surface_y(tx + dx) != ts:
				flat = false
		if flat:
			ground = tx
			break
	var house := colony.create_project(Project.Kind.ROOM, Rect2i(ground, w.gen.surface_y(ground) - 3, 4, 3))
	check(house != null and not house.ladder, "у наземного дома лестницы нет")


## Готовая подземная комната от шахты: возвращает [colony, room].
## Готовая комната на поверхности без стен — для проверок работы на месте.
## Очаг вплотную к комнате room (для опытов с теплом).
func _hearth(colony: Colony, room: Project) -> Project:
	var p := Project.new()
	p.id = 990
	p.kind = Project.Kind.ROOM
	p.phase = Project.Phase.DONE
	p.purpose = RoomType.HEARTH
	p.rect = Rect2i(room.rect.end.x, room.rect.position.y, 3, 3)
	p.targets = {}
	colony.projects.append(p)
	return p


func _fake_room(colony: Colony, purpose: int, x: int, width := 4) -> Project:
	var p := Project.new()
	p.id = 900 + purpose
	p.kind = Project.Kind.ROOM
	p.phase = Project.Phase.DONE
	p.purpose = purpose
	var sy := colony.world.gen.surface_y(x)
	p.rect = Rect2i(x, sy - 3, width, 3)
	p.targets = {}
	colony.projects.append(p)
	return p


## Новая колония для теста: старение выключено, чтобы долгие прогоны не упирались в срок жизни
## (его проверяет test_aging).
func _start(colony: Colony, x: int) -> void:
	colony.start_new(x)
	for u in colony.units:
		u.lifespan = 0.0


func _colony_with_room(seed_value: int, purpose := -1, width := 6) -> Array:
	var colony := _new_colony(seed_value)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	colony.inventory = {"wood": 55, "stone": 55, "soil": 55, "clay": 55}
	var s := w.gen.surface_y(x)
	colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 6))
	var rr := Rect2i(x + 1, s + 3, width, 3)
	var err := colony.validate(Project.Kind.ROOM, rr)
	if not err.is_empty():
		printerr("  комната не заложена: ", err)
	var room := colony.create_project(Project.Kind.ROOM, rr)
	colony.advance_offline(30000.0)
	if purpose >= 0:
		colony.inventory = {"wood": 55, "stone": 55, "soil": 55, "food": 50}
		colony.set_purpose(room, purpose)
		colony.advance_offline(5000.0)
	# Свободные жители сами еду не добывают — после долгой подготовки накормим и подлечим.
	colony.inventory["food"] = maxi(50, colony.inventory.get("food", 0))
	for u in colony.units:
		u.satiety = 100.0
		u.energy = 100.0
		u.health = 100.0
	return [colony, room]


## Срубленное и выкопанное на стройке остаётся на ней: идёт в её материалы, а не на склад.
func test_site_keeps_yield() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 0, "stone": 0}
	var tree := 0
	for tx in range(-300, 300):
		if w.feature_at(tx) == WorldGen.FEATURE_TREE and w.gen.surface_y(tx - 2) == w.gen.surface_y(tx) \
				and w.gen.surface_y(tx + 3) == w.gen.surface_y(tx):
			tree = tx
			break
	var ts := w.gen.surface_y(tree)
	var house := colony.create_project(Project.Kind.ROOM, Rect2i(tree - 1, ts - 3, 3, 3))
	check(house != null and house.clear_x.has(tree), "дерево на месте дома — в расчистке")
	var got: int = colony.feature_yield(tree)[1]
	var need: int = colony.remaining(house).get("wood", 0)
	colony._complete_harvest(tree, colony.units[0])
	check(house.delivered.get("wood", 0) == mini(got, need), "срубленное дерево сразу пошло на этот дом (%d из %d)" % [house.delivered.get("wood", 0), got])
	check(colony.inventory.get("wood", 0) == 0, "на склад дерево не понесли")
	check(colony.drop_total("wood") == maxi(0, got - need), "на земле — только излишек")
	check(colony.units[0].task != Unit.Task.HAUL or got > need, "рубщик не тащит дерево на склад")


## Шахта: 3 м высотой, только под землёй, с крепью; шахтёры идут первыми; на её месте —
## комната (шахта делится).
func test_mine() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 80, "stone": 60, "food": 200}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	var M := Project.Kind.MINE
	check(not colony.validate(M, Rect2i(x + 1, s + 3, 8, 2)).is_empty(), "шахта не 3 м высотой — нельзя")
	check(not colony.validate(M, Rect2i(x + 1, s - 3, 8, 3)).is_empty(), "шахта над землёй — нельзя")
	colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 6))
	var mine := colony.create_project(M, Rect2i(x + 1, s + 3, 9, 3))
	check(mine != null and mine.needs_support.size() > 0, "шахта заложена и требует крепи")
	var miner: Unit = colony.units[0]
	colony.set_profession(miner, Unit.Prof.MINER)
	colony.advance_offline(20000.0)
	check(mine.phase == Project.Phase.DONE, "шахта прокопана и закреплена")
	# Комната — только на всю высоту шахты; шахта делится на куски по бокам.
	check(not colony.validate(Project.Kind.ROOM, Rect2i(x + 3, s + 2, 3, 3)).is_empty(), "комната со сдвигом по высоте — нельзя")
	var room_r := Rect2i(x + 4, s + 3, 3, 3)
	check(colony.validate(Project.Kind.ROOM, room_r, "wood").is_empty(), "комната в готовой шахте — можно: " + colony.validate(Project.Kind.ROOM, room_r, "wood"))
	var room := colony.create_project(Project.Kind.ROOM, room_r, -1, "wood")
	var pieces := colony.projects.filter(func(q: Project) -> bool: return q.kind == M)
	check(room != null and not colony.projects.has(mine) and pieces.size() == 2, "шахта поделилась на два куска (%d)" % pieces.size())
	colony.advance_offline(20000.0)
	check(room.phase == Project.Phase.DONE, "комната в шахте построена без копки")
	var saved := Project.from_dict(pieces[0].to_dict())
	check(saved.kind == M, "шахта сохраняется")


## Геологоразведка: каждый уровень — на клетку дальше видно породу от выработок.
func test_geology_levels() -> void:
	var colony := _new_colony(5)
	var w := colony.world
	# Выработка в прочной породе (сыпучая сразу осыплется в выкопанное).
	var c := Vector2i.ZERO
	for xx in range(0, 300):
		var cc := Vector2i(xx, w.gen.surface_y(xx) + 30)
		var firm := true
		for dy in range(-2, 2):
			var m := w.get_mat(cc.x, cc.y + dy)
			if not Mat.is_solid(m) or Mat.is_loose(m) or Mat.is_fluid(m):
				firm = false
		if firm:
			c = cc
			break
	var x := c.x
	var s := c.y - 30
	check(colony.see_radius() == 1, "без геологии видно на 1 клетку")
	colony._complete_dig(c, null, null)
	check(w.is_revealed(c.x + 1, c.y) and not w.is_revealed(c.x + 2, c.y), "у выработки видна только соседняя клетка")
	colony.research.done.append("geology")
	colony._reveal_known()
	check(colony.see_radius() == 2 and w.is_revealed(c.x + 2, c.y) and not w.is_revealed(c.x + 3, c.y),
		"геология I: видно на 2 клетки, и старые выработки осмотрены заново")
	colony.research.done.append("geology2")
	var c2 := Vector2i(x, s + 27)
	colony._complete_dig(c2, null, null)
	check(w.is_revealed(c2.x + 3, c2.y) and not w.is_revealed(c2.x + 4, c2.y), "геология II: новая выработка — на 3 клетки")
	check(Research.TECHS["geology4"][3] == ["geology3"], "уровни геологии идут цепочкой до IV")


## Под готовым этажом новая комната несёт его вес: лёгкая не выдержит каменный верх.
func test_new_room_load() -> void:
	var colony := _new_colony(12)
	var w := colony.world
	var x := _flat_x(w, 0)
	var s := w.gen.surface_y(x)
	var top := Project.new()
	top.id = 777
	top.kind = Project.Kind.ROOM
	top.phase = Project.Phase.DONE
	top.material = "stone"
	top.rect = Rect2i(x, s - 3, 6, 3)
	colony.projects.append(top)
	colony.loads.loads = colony.loads.compute()
	var below := Rect2i(x, s, 6, 3)
	var err := colony.loads.room_error(below, "wood")
	check(err.begins_with("Эта комната не выдержит"), "деревянная под каменной не выдержит: " + err)
	check(colony.loads.room_error(below, "stone").is_empty(), "каменная под каменной выдержит")


func test_room_materials() -> void:
	var colony := _new_colony(12)
	check(colony.available_materials() == ["wood"], "в начале доступно только дерево")
	colony._add("clay", 3)
	colony._add("stone", 3)
	check(colony.available_materials() == ["wood", "stone"], "камень открывается после добычи, глина — не материал стен")
	var r := Rect2i(0, 0, 6, 3)
	check(Project.cost_for(Project.Kind.ROOM, r, "stone").has("stone"), "каменная комната требует камень")
	check(not Project.cost_for(Project.Kind.ROOM, r, "wood").has("stone"), "деревянная — без камня")
	check(Project.work_for(Project.Kind.ROOM, r, "stone") > Project.work_for(Project.Kind.ROOM, r, "wood"), "камень строить дольше")


func test_room_purposes() -> void:
	var res := _colony_with_room(21)
	var colony: Colony = res[0]
	var room: Project = res[1]
	check(room.phase == Project.Phase.DONE and room.purpose == RoomType.NONE, "комната построена без назначения")
	var cap0 := colony.capacity("stone")
	colony.inventory = {}
	check(colony.set_purpose(room, RoomType.STORAGE), "назначение выбрано")
	colony.advance_offline(3000.0)
	check(room.phase == Project.Phase.EQUIP or room.phase == Project.Phase.DONE, "склад обустраивают (дерево рубят по нужде)")
	colony.inventory = {"wood": 50, "food": 50}
	colony.advance_offline(3000.0)
	check(room.purpose == RoomType.STORAGE and room.phase == Project.Phase.DONE, "склад обустроен")
	check(colony.capacity("stone") > cap0, "склад увеличил вместимость")
	colony.assign_work(colony.units[0], room)
	colony.inventory = {}
	colony._add("stone", colony.capacity("stone") + 10)
	check(colony.inventory["stone"] == colony.capacity("stone") and colony.held_in(room, "stone") == colony.room_cap(room, "stone"),
		"лишнее сверх вместимости не помещается, склад полон")

	# Очаг: каменный сразу; после обжига кирпича печи перекладывают кирпичом.
	var hres := _colony_with_room(23)
	var hcol: Colony = hres[0]
	var hroom: Project = hres[1]
	hcol.inventory = {"stone": 60, "wood": 30, "food": 60}
	check(hcol.set_purpose(hroom, RoomType.HEARTH), "каменный очаг — без исследований")
	hcol.advance_offline(3000.0)
	check(hroom.purpose == RoomType.HEARTH and not hroom.brick_stoves, "каменный очаг готов")
	check(not hcol.set_purpose(hroom, RoomType.HEARTH_BRICK), "без обжига кирпича улучшить нельзя")
	hcol.research.done.append("bricks")
	hcol.inventory["brick"] = 40
	check(hcol.set_purpose(hroom, RoomType.HEARTH_BRICK), "улучшение до кирпичных печей начато")
	hcol.cancel_project(hroom)
	check(hroom.purpose == RoomType.HEARTH and hroom.phase == Project.Phase.DONE, "отмена улучшения оставляет каменный очаг")
	hcol.inventory["brick"] = 40
	check(hcol.set_purpose(hroom, RoomType.HEARTH_BRICK), "улучшение снова начато")
	hcol.advance_offline(3000.0)
	check(hroom.purpose == RoomType.HEARTH and hroom.brick_stoves and hroom.phase == Project.Phase.DONE, "печи кирпичные")
	check(not hcol.set_purpose(hroom, RoomType.HEARTH_BRICK), "дважды не улучшают")
	var saved := Project.from_dict(hroom.to_dict())
	check(saved.brick_stoves, "кирпичные печи сохраняются")
	# Газовые котлы — железное улучшение очага после «Газового отопления»; кирпич остаётся.
	hcol.inventory["iron"] = 40
	check(not hcol.set_purpose(hroom, RoomType.HEARTH_GAS), "без «Газового отопления» котлы не ставят")
	hcol.research.done.append("gas_heating")
	check(hcol.set_purpose(hroom, RoomType.HEARTH_GAS), "ставим газовые котлы")
	hcol.advance_offline(3000.0)
	check(hroom.purpose == RoomType.HEARTH and hroom.gas_boiler and hroom.brick_stoves and hroom.phase == Project.Phase.DONE,
		"котлы стоят, печи остались кирпичными")
	check(RoomType.current_purpose(hroom) == RoomType.HEARTH_GAS and not hcol.set_purpose(hroom, RoomType.HEARTH_GAS), "котлы дважды не ставят")
	check(Project.from_dict(hroom.to_dict()).gas_boiler, "котлы сохраняются")
	var hroom2: Project = _colony_with_room(9, RoomType.NONE)[1]
	check(not hcol.set_purpose(hroom2, RoomType.HEARTH_GAS), "котёл — только на готовый очаг")

	var farm_res := _colony_with_room(22, RoomType.FARM)
	var fc: Colony = farm_res[0]
	var farm: Project = farm_res[1]
	check(farm.purpose == RoomType.FARM, "ферма обустроена")
	check(fc.assign_work(fc.units[0], farm).is_empty(), "фермер назначен")
	fc.inventory["food"] = 0
	var food0 := 0
	fc.advance_offline(600.0)
	check(fc.inventory.get("food", 0) == 0 and not fc.farm_warm(farm), "под землёй без огня ферма мёрзнет (%.0f °C)" % fc.room_temp(farm))
	_hearth(fc, farm)
	fc.inventory["wood"] = 50
	fc.advance_offline(1800.0)
	check(fc.inventory.get("food", 0) > food0, "с очагом ферма производит еду (%d → %d)" % [food0, fc.inventory.get("food", 0)])
	check(fc.inventory.get("wood", 0) < 50, "очаг жжёт дрова")

	var home_res := _colony_with_room(23, RoomType.HOME)
	var hc: Colony = home_res[0]
	check(hc.beds_total() == 2, "в заглублённой жилой 6×3 две кровати — у стены лестница (%d)" % hc.beds_total())


func test_needs_realtime() -> void:
	var res := _colony_with_room(24, RoomType.HOME)
	var colony: Colony = res[0]
	var u: Unit = colony.units[0]
	colony.inventory["food"] = 10
	u.satiety = 20.0
	var t := 0.0
	while t < 60.0 and u.satiety < 50.0:
		colony.update(0.5)
		t += 0.5
	check(u.satiety >= 50.0 and colony.inventory["food"] < 10, "голодный житель поел (%.0f с)" % t)
	u.energy = 5.0
	t = 0.0
	var slept_in_bed := false
	while t < 900.0 and u.energy < 99.0:
		colony.update(0.5)
		t += 0.5
		if u.task == Unit.Task.SLEEP and u.state == Unit.State.WORK and u.project_id != 0:
			slept_in_bed = true
	check(u.energy >= 99.0, "уставший житель выспался (%.0f с)" % t)
	check(slept_in_bed, "спал в кровати")


func test_family() -> void:
	var res := _colony_with_room(25, RoomType.HOME, 8)
	var colony: Colony = res[0]
	# Второй дом на поверхности — чтобы кроватей было больше, чем жителей.
	var w := colony.world
	var hx := 0
	for tx in range(40, 400):
		var ts := w.gen.surface_y(tx)
		var flat := true
		for dx in range(-1, 10):
			if w.gen.surface_y(tx + dx) != ts:
				flat = false
		if flat:
			hx = tx
			break
	colony.inventory = {"wood": 50, "stone": 50, "food": 50}
	var house_rect := Rect2i(hx, w.gen.surface_y(hx) - 3, 8, 3)
	var house_err := colony.validate(Project.Kind.ROOM, house_rect)
	check(house_err.is_empty(), "дом на поверхности можно заложить: " + house_err)
	var house := colony.create_project(Project.Kind.ROOM, house_rect)
	colony.advance_offline(8000.0)
	colony.inventory = {"wood": 50, "stone": 50, "food": 50}
	colony.set_purpose(house, RoomType.HOME)
	colony.advance_offline(3000.0)
	check(colony.beds_total() >= 7, "кроватей больше, чем жителей (%d)" % colony.beds_total())
	var before := colony.units.size()
	var pairs := 0
	for i in 20:
		colony.inventory["food"] = 100
		colony.advance_offline(600.0)
	for u in colony.units:
		if u.partner_id != 0:
			pairs += 1
	check(pairs >= 2, "сложились пары (%d)" % pairs)
	check(colony.units.size() > Colony.START_UNITS, "родились дети (%d → %d)" % [Colony.START_UNITS, colony.units.size()])
	check(colony.units.size() <= colony.beds_total(), "жителей не больше, чем кроватей")
	var kid: Unit = colony.units[colony.units.size() - 1]
	for i in 6:
		colony.inventory["food"] = 100
		colony.advance_offline(600.0)
	check(not kid.child, "ребёнок вырос")


func test_aging() -> void:
	var colony := _new_colony(31)
	var x := _find_solid_column(colony.world)
	colony.start_new(x)
	var u: Unit = colony.units[0]
	check(u.lifespan > Unit.LIFESPAN * 0.5, "у жителя есть срок жизни (%.0f с)" % u.lifespan)
	check(not u.is_elder() and u.age >= Unit.CHILD_TIME, "основатели — взрослые, не старики")
	u.age = u.lifespan * Unit.ELDER_AT - 0.1
	colony.update(0.5)
	check(u.is_elder() and u.age_factor() < 1.0, "житель состарился и работает медленнее")
	var mother: Unit = null
	var father: Unit = null
	for o in colony.units:
		if o.sex == Unit.Sex.FEMALE and mother == null:
			mother = o
		elif o.sex == Unit.Sex.MALE and o != u and father == null:
			father = o
	mother.partner_id = father.id
	father.generation = 3
	colony._birth(mother)
	var baby: Unit = colony.units[colony.units.size() - 1]
	check(baby.child and baby.generation == 4, "ребёнок — следующее поколение (%d)" % baby.generation)
	var n := colony.units.size()
	var log: Array[String] = []
	colony.event_logged.connect(func(text: String, _kind: String) -> void: log.append(text))
	u.age = u.lifespan - 0.1
	colony.update(0.5)
	check(colony.units.size() == n - 1 and not colony.units.has(u), "старик умер от старости")
	check(log.any(func(t: String) -> bool: return "от старости" in t), "в журнале — смерть от старости")


func test_tunnel_throughput() -> void:
	check(Colony.tunnel_lanes(Rect2i(0, 0, 1, 10)) == 1, "шахта шириной 1 — один поток")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 3, 10)) == 3, "шахта шириной 3 — три потока")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 10, 2)) == 1, "штрек высотой 2 — один поток")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 10, 3)) == 2, "штрек высотой 3 — два потока")
	var colony := _new_colony(26)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	var s := w.gen.surface_y(x)
	var narrow := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 8))
	var wide := colony.create_project(Project.Kind.TUNNEL, Rect2i(x + 2, s, 3, 8))
	var a := colony.units[0]
	var b := colony.units[1]
	a.pos = Vector2(x, s + 3)
	b.pos = Vector2(x, s + 4)
	check(is_equal_approx(colony.congestion(a), 0.5), "двое в узкой шахте мешают друг другу")
	a.pos = Vector2(x + 2, s + 3)
	b.pos = Vector2(x + 3, s + 4)
	check(is_equal_approx(colony.congestion(a), 1.0), "в широкой шахте расходятся свободно")


func test_professions() -> void:
	var colony := _new_colony(27)
	_start(colony, 0)
	colony.inventory["food"] = 200
	var u := colony.units[0]
	u.profession = Unit.Prof.BUILDER
	check(colony._task_order(u)[0] == "builds", "строитель сначала идёт на стройку (не в шахту)")
	u.profession = Unit.Prof.MINER
	check(colony._task_order(u)[0] == "mines", "шахтёр сначала идёт в шахту")
	u.profession = Unit.Prof.BUILDER
	u.profession = Unit.Prof.HAULER
	check(colony._task_order(u)[0] == "haul", "подсобный сначала носит")
	u.profession = Unit.Prof.ANY
	check(colony._task_order(u) == ["projects", "need", "haul"], "свободный: стройка (и добыча для неё), потом переноска")
	u.profession = Unit.Prof.ANY
	u.workplace = 999
	check(colony._task_order(u)[0] == "workplace", "назначенный сначала идёт на своё место работы")
	u.workplace = 0
	check(not colony._task_order(u).has("farm") and not colony._task_order(u).has("fish"), "свободные сами не фермерствуют и не рыбачат")
	var kid := colony._new_unit(Unit.Sex.FEMALE, Vector2.ZERO)
	kid.child = true
	check(colony.adults() == 5, "дети не считаются рабочими")


func test_roles() -> void:
	var colony := _new_colony(28)
	var w := colony.world
	var x := _flat_x(w, _find_solid_column(w))
	_start(colony, x)
	colony.inventory = {"food": 200, "wood": 40, "clay": 40, "stone": 40}
	for u in colony.units:
		u.pos = Vector2(x + 1, w.gen.surface_y(x + 1) - 1)
	var s := w.gen.surface_y(x)
	# Строитель вытесняет свободного со стройки.
	var p := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 12), 1)
	var t := 0.0
	while t < 60.0 and colony.workers_on(p) == 0:
		colony.update(0.5)
		t += 0.5
	var first: Unit = null
	for u in colony.units:
		if u.project_id == p.id and u.task != Unit.Task.HAUL:
			first = u
	check(first != null and colony.is_free(first), "на стройку пошёл свободный")
	var builder: Unit = null
	for u in colony.units:
		if u != first:
			builder = u
			break
	check(colony.set_profession(builder, Unit.Prof.BUILDER).is_empty(), "назначен строитель")
	t = 0.0
	while t < 30.0 and not (builder.project_id == p.id and builder.task != Unit.Task.HAUL):
		colony.update(0.5)
		t += 0.5
	check(builder.project_id == p.id and builder.task != Unit.Task.HAUL and colony.workers_on(p) <= 1,
		"строитель занял место свободного (%.0f с)" % t)
	colony.projects.erase(p)
	for u in colony.units:
		colony._drop(u)
	# Подсобный несёт сырьё в печь, а продукция ложится кучей в мастерской.
	var kiln := _fake_room(colony, RoomType.KILN, x + 3)
	var hauler: Unit = colony.units[2]
	colony.set_profession(hauler, Unit.Prof.HAULER)
	check(colony._task_order(hauler)[0] == "haul" and colony.role_name(hauler) == "Подсобный рабочий", "подсобный рабочий назначен")
	t = 0.0
	while t < 120.0 and kiln.stock.get("clay", 0) == 0:
		colony.update(0.5)
		t += 0.5
	check(kiln.stock.get("clay", 0) > 0, "в печь принесли глину (%.0f с)" % t)
	kiln.stock = {"clay": 2, "wood": 1}
	colony._craft(kiln)
	check(kiln.stock.get("clay", 0) == 0 and colony.drop_total("brick") == 2, "кирпич лежит в мастерской, глина из запаса печи")
	# Печь для кирпича топят углём (вдвое дольше дров, берут первым) или дровами.
	kiln.stock = {"clay": 4, "coal": 1}
	kiln.fuel = 0.0
	colony.drops.clear()
	check(colony.has_inputs(kiln), "глина есть, топливо — уголь")
	colony._craft(kiln)
	check(kiln.stock.get("coal", 0) == 0 and is_equal_approx(kiln.fuel, 1.0), "1 уголь — на два обжига (остался ещё один)")
	colony._craft(kiln)
	check(colony.drop_total("brick") == 4 and kiln.fuel < 0.01, "на одном угле — два обжига, 4 кирпича")
	check(not colony.has_inputs(kiln) and colony.missing_inputs(kiln).has("wood"), "без топлива печь стоит")
	kiln.stock = {"clay": 2, "wood": 1, "coal": 1}
	colony._craft(kiln)
	check(kiln.stock.get("wood", 0) == 1 and kiln.stock.get("coal", 0) == 0, "уголь сжигают раньше дров")
	kiln.stock = {}
	kiln.fuel = 0.0
	colony.drops.clear()
	# Мастер печи без подсобных сам носит сырьё в свою печь и обжигает кирпич.
	colony.set_profession(hauler, Unit.Prof.ANY)
	for u in colony.units:
		colony._drop(u)
		u.workplace = 0
	kiln.stock = {}
	colony.drops.clear()
	colony.inventory["clay"] = 10
	colony.inventory["wood"] = 10
	var master: Unit = colony.units[1]
	check(colony.assign_work(master, kiln).is_empty(), "мастер назначен в печь")
	var fetched := false
	t = 0.0
	while t < 300.0 and colony.drop_total("brick") == 0:
		colony.update(0.5)
		t += 0.5
		if master.task == Unit.Task.HAUL and master.project_id == kiln.id:
			fetched = true
	check(fetched and colony.drop_total("brick") > 0, "мастер сам принёс глину и обжёг кирпич (%.0f с)" % t)
	colony.unassign_work(master)
	colony.projects.erase(kiln)
	for u in colony.units:
		colony._drop(u)
	colony.drops.clear()
	# Свободный носильщик бросает ношу, если на стройке освободилось место.
	var free: Unit = colony.units[3]
	colony.set_profession(free, Unit.Prof.ANY)
	var p2 := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 12), 2)
	for u in colony.units:
		if u != free:
			u.task = Unit.Task.SLEEP
			u.state = Unit.State.WORK
	free.task = Unit.Task.HAUL
	free.state = Unit.State.MOVE
	free.to_store = true
	free.haul_stage = 1
	free.carry_key = "stone"
	free.carry_amount = 3
	free.recheck_t = 0.0
	colony._construction_recheck(free, 0.1)
	check(free.task != Unit.Task.HAUL or free.project_id == p2.id, "свободный ушёл со склада на стройку")
	check(colony.drop_total("stone") == 3, "ношу оставил на месте")
	var hauler2: Unit = colony.units[4]
	colony.set_profession(hauler2, Unit.Prof.HAULER)
	hauler2.task = Unit.Task.HAUL
	hauler2.state = Unit.State.MOVE
	hauler2.to_store = true
	hauler2.recheck_t = 0.0
	colony._construction_recheck(hauler2, 0.1)
	check(hauler2.task == Unit.Task.HAUL and hauler2.to_store, "подсобный продолжает носить")
	# Наука: только назначенные, скорость — прямо от интеллекта.
	var smart: Unit = colony.units[0]
	smart.stats["intellect"] = 2.0
	var plain: Unit = colony.units[1]
	plain.stats["intellect"] = 1.0
	var k := colony.work_factor(smart, Unit.Task.RESEARCH, Vector2i.ZERO) / colony.work_factor(plain, Unit.Task.RESEARCH, Vector2i.ZERO)
	check(absf(k - 2.0 * float(smart.ability("work")) / float(plain.ability("work"))) < 0.01,
		"вдвое умнее — изучает вдвое быстрее (%.2f)" % k)
	check(not colony._task_order(plain).has("science"), "свободные сами не исследуют")


func test_build_rules_v2() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 30, "stone": 30}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	check(not colony.validate(Project.Kind.TUNNEL, Rect2i(x, s - 3, 1, 6)).is_empty(), "тоннель над землёй запрещён")
	check(colony.validate(Project.Kind.TUNNEL, Rect2i(x, s, 1, 6)).is_empty(), "тоннель от поверхности вниз разрешён")
	# Дерево на месте комнаты срубается на этапе 1 и даёт дерево.
	var tree := 0
	for tx in range(-300, 300):
		if w.feature_at(tx) == WorldGen.FEATURE_TREE and w.gen.surface_y(tx - 2) == w.gen.surface_y(tx) \
				and w.gen.surface_y(tx + 3) == w.gen.surface_y(tx):
			tree = tx
			break
	var ts := w.gen.surface_y(tree)
	var house := colony.create_project(Project.Kind.ROOM, Rect2i(tree - 1, ts - 3, 4, 3))
	check(house != null and house.clear_x.has(tree), "дерево попало в расчистку стройки")
	var wood_before: int = colony.inventory["wood"]
	colony.advance_offline(20000.0)
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE, "дерево на месте стройки срублено")
	check(house.phase == Project.Phase.DONE, "дом построен после расчистки")
	check(colony.known_resources.has("wood") and colony.inventory["wood"] > wood_before - house.cost()["wood"], "срубленное дерево пошло в запас")
	# Второй этаж — только с лестницей в нижнем.
	var upper := Rect2i(tree - 1, ts - 6, 4, 3)
	check(colony.ladders_needed(upper) == [house], "для второго этажа нужна лестница внизу")
	colony.inventory = {"wood": 40, "stone": 40}
	var top := colony.create_project(Project.Kind.ROOM, upper)
	check(top != null and house.phase == Project.Phase.EQUIP and house.equip_ladder, "лестница в нижнем здании заложена автоматически")
	colony.advance_offline(8000.0)
	check(house.ladder and top.phase == Project.Phase.DONE, "лестница и второй этаж построены")
	check(not colony.validate(Project.Kind.ROOM, Rect2i(tree - 1, ts - 9, 4, 3)).is_empty(), "на деревянный дом третий этаж нельзя")
	check(not colony.validate(Project.Kind.ROOM, Rect2i(tree + 3, ts - 6, 4, 3)).is_empty(), "висящий второй этаж нельзя")
	# Отвал не ограничен, склад хранит выбранное.
	colony._add("sand", 5000)
	check(colony.inventory["sand"] == 5000, "песок уходит в отвал без лимита")
	var stone_cap := colony.capacity("stone")
	colony.inventory["stone"] = 0
	colony._add("stone", 500)
	check(colony.inventory["stone"] == stone_cap, "камень без склада ограничен кучей на земле")
	# Ребёнок ест вдвое больше.
	var kid := colony._new_unit(Unit.Sex.MALE, colony.units[0].pos)
	kid.child = true
	for o in colony.units:
		o.satiety = 100.0
	kid.satiety = 10.0
	colony.inventory["food"] = 10
	for i in 40:
		colony.update(0.5)
	check(colony.inventory["food"] == 8 or kid.satiety > 50.0 and colony.inventory["food"] <= 8, "ребёнок съел двойную порцию")


## Глубокий участок гранита, где можно «вырезать» сценарий руками.
func _granite_spot(colony: Colony) -> Vector2i:
	var w := colony.world
	for x in range(0, 2000, 7):
		var y := w.gen.surface_y(x) + 1500
		var ok := true
		for dy in range(-6, 4):
			for dx in range(-8, 9):
				var m := w.get_mat(x + dx, y + dy)
				if m != Mat.GRANITE and m != Mat.GNEISS:
					ok = false
		if ok:
			return Vector2i(x, y)
	return Vector2i(0, 1500)


func test_physics() -> void:
	var colony := _new_colony(41)
	var w := colony.world
	var c := _granite_spot(colony)
	# Сыпучее: песок над выкопанной клеткой осыпается вниз.
	w.set_material(c.x, c.y - 2, Mat.SAND)
	w.set_dug(c.x, c.y)
	w.set_dug(c.x, c.y + 1)
	w.set_dug(c.x, c.y - 1)
	colony.physics.on_opened(c + Vector2i(0, -1))
	check(w.get_mat(c.x, c.y + 1) == Mat.SAND, "песок осыпался на дно выработки")
	check(w.is_open(c.x, c.y - 2), "на месте песка — пустота")
	# Готовая постройка защищает: песок не сыплется в укреплённую клетку.
	var d := c + Vector2i(4, 0)
	w.set_material(d.x, d.y - 1, Mat.SAND)
	w.set_dug(d.x, d.y)
	colony.interior[d] = 999
	colony.physics.on_opened(d)
	check(w.get_mat(d.x, d.y - 1) == Mat.SAND and w.is_open(d.x, d.y), "крепь держит сыпучий грунт")
	colony.interior.erase(d)
	# Пролёт: под глиняным потолком пустота 7 м без крепи — обвал.
	var e := c + Vector2i(-8, 6)
	for x in range(e.x, e.x + 7):
		w.set_material(x, e.y - 1, Mat.CLAY)
		w.set_dug(x, e.y)
		w.set_dug(x, e.y + 1)
	check(colony.physics.check_span(Vector2i(e.x + 3, e.y + 1)), "широкий пролёт под глиной обрушился")
	var rubble := 0
	for x in range(e.x, e.x + 7):
		if w.get_mat(x, e.y + 1) == Mat.RUBBLE:
			rubble += 1
	check(rubble == 7, "выработку засыпало обломками (%d)" % rubble)
	# Узкий пролёт в граните держится.
	var f := c + Vector2i(6, -4)
	for x in range(f.x, f.x + 4):
		w.set_dug(x, f.y)
	check(not colony.physics.check_span(Vector2i(f.x + 1, f.y)), "4 м в граните держатся без крепи")
	# Обломки ранят жителя.
	_start(colony, 0)
	var u := colony.units[0]
	var g := c + Vector2i(-3, -4)
	w.set_material(g.x, g.y - 1, Mat.GRAVEL)
	w.set_dug(g.x, g.y)
	w.set_dug(g.x, g.y + 1)
	u.pos = Vector2(g.x, g.y)
	colony.physics.on_opened(g)
	check(u.health < 100.0, "житель ранен осыпью (%.0f)" % u.health)
	# Простой стройки без крепи → обвал.
	var colony2 := _new_colony(42)
	colony2.inventory = {}
	var c2 := _granite_spot(colony2)
	var w2 := colony2.world
	for x in range(c2.x - 6, c2.x + 6):
		w2.set_material(x, c2.y - 1, Mat.CLAY)
		w2.set_dug(x, c2.y)
		w2.set_dug(x, c2.y + 1)
	var p := Project.new()
	p.id = 77
	p.kind = Project.Kind.ROOM
	p.rect = Rect2i(c2.x - 6, c2.y, 12, 2)
	p.phase = Project.Phase.BUILD
	colony2.projects.append(p)
	colony2.update(10.0)
	check(w2.is_open(c2.x, c2.y + 1), "пока стройка недолго ждёт материалы — держится")
	colony2.update(Physics.GRACE + 5.0)
	check(not w2.is_open(c2.x, c2.y + 1) and p.phase == Project.Phase.DIG, "долгий простой без крепи — обвал, копать заново")
	# Снос: возвращается половина.
	var colony3 := _new_colony(43)
	var w3 := colony3.world
	var x3 := _find_solid_column(w3)
	_start(colony3, x3)
	colony3.inventory = {"wood": 40, "stone": 40}
	var s3 := w3.gen.surface_y(x3)
	var t := colony3.create_project(Project.Kind.ROOM, Rect2i(x3, s3 - 3, 4, 3))
	colony3.advance_offline(20000.0)
	check(t != null and t.phase == Project.Phase.DONE, "дом построен")
	var wood := int(colony3.inventory.get("wood", 0))
	check(colony3.demolish(t), "дом снесён")
	check(int(colony3.inventory.get("wood", 0)) == wood + t.cost()["wood"] / 2, "вернулась половина дерева")
	check(colony3.project_by_id(t.id) == null and not colony3.interior.has(Vector2i(x3 + 1, s3 - 2)), "постройки больше нет")


func test_slices() -> void:
	var colony := _new_colony(61)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	colony.inventory = {"wood": 40}
	var s := w.gen.surface_y(x)
	var shaft := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 4))
	colony.advance_offline(20000.0)
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(x + 1, s + 1, 5, 3))
	check(room.needs_support.size() == 5, "у подземной комнаты 5 срезов под крепь")
	var max_open := 0
	var t := 0.0
	while t < 4000.0 and room.phase == Project.Phase.DIG:
		colony.update(1.0)
		t += 1.0
		var open_unsupported := 0
		for i in room.needs_support:
			if not room.supported.has(i):
				for c in room.slice_cells(i):
					if w.is_open(c.x, c.y):
						open_unsupported += 1
						break
		max_open = maxi(max_open, open_unsupported)
	check(room.phase != Project.Phase.DIG, "комнату выкопали срез за срезом (%.0f с)" % t)
	check(max_open <= 1, "одновременно открыт не больше одного незакреплённого среза (%d)" % max_open)
	check(room.supported.size() == 5, "все срезы закреплены")
	check(colony.inventory.get("wood", 0) < 40 - 4, "крепь стоила дерева")


func test_nature() -> void:
	var colony := _new_colony(51)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {}
	# Ягоды: сбор забирает ягоды, куст остаётся, ягоды отрастают.
	var bush := 0
	for x in range(-150, 150):
		if w.feature_at(x) == WorldGen.FEATURE_BUSH:
			bush = x
			break
	check(w.berries(bush) == WorldData.BUSH_BERRIES, "у нетронутого куста полный урожай")
	colony._complete_harvest(bush, null)
	check(w.feature_at(bush) == WorldGen.FEATURE_BUSH and w.berries(bush) < 1.0, "куст остался без ягод")
	check(colony.drop_amount(colony._ground_cell(bush), "berries") == 6, "ягоды лежат у куста")
	colony.grow_plants(Colony.BERRY_REGEN * 3)
	check(w.berries(bush) >= 2.9, "ягоды отрастают (%.1f)" % w.berries(bush))
	# Голодный житель при пустом складе ест ягоды с куста.
	colony.inventory = {}
	w.set_berries(bush, 6.0)
	colony._refresh_bushes()
	var u := colony.units[0]
	u.satiety = 10.0
	var t := 0.0
	while t < 200.0 and u.satiety < 40.0:
		colony.update(0.5)
		t += 0.5
	check(u.satiety >= 40.0, "голодный житель нашёл куст и поел (%.0f с)" % t)
	# Деревья: растут медленно, новые появляются рядом со старыми.
	var trees_before := 0
	for x in range(colony.home.x - 160, colony.home.x + 160):
		if w.feature_at(x) == WorldGen.FEATURE_TREE:
			trees_before += 1
	for i in 200:
		colony.grow_plants(Colony.PLANT_TICK * 6)
	var trees_after := 0
	var saplings := 0
	var bad := 0
	for x in range(colony.home.x - 160, colony.home.x + 160):
		if w.feature_at(x) == WorldGen.FEATURE_TREE:
			trees_after += 1
			if w.plants.has(x):
				saplings += 1
				var near := 0
				for dx in range(-Colony.SPREAD_RADIUS, Colony.SPREAD_RADIUS + 1):
					if dx != 0 and w.feature_at(x + dx) == WorldGen.FEATURE_TREE:
						near += 1
				if near == 0:
					bad += 1
	check(trees_after > trees_before, "лес разрастается (%d → %d)" % [trees_before, trees_after])
	check(bad == 0, "новые деревья появляются только рядом с другими")
	# Саженец растёт медленно и сначала даёт мало дерева.
	var sx := 0
	for x in w.plants:
		if int(w.plants[x]["t"]) == WorldGen.FEATURE_TREE:
			sx = x
	w.plants[sx]["g"] = 0.1
	check(not colony.toggle_harvest(sx).is_empty(), "молодое дерево рубить нельзя")
	colony.grow_plants(Colony.TREE_GROW_TIME * 0.5)
	check(absf(w.growth(sx) - 0.6) < 0.05, "дерево подросло (%.2f)" % w.growth(sx))


## Ищет озеро с водой: [озеро, x левого берега, x правого берега].
func _find_lake(w: WorldData) -> Array:
	for k in range(-40, 40):
		var l := w.gen._lake_of_segment(k)
		if l.is_empty():
			continue
		var level: int = l["level"]
		var xs := []
		for x in range(int(l["cx"]) - int(l["w"]), int(l["cx"]) + int(l["w"])):
			if w.gen.surface_y(x) > level:
				xs.append(x)
		if xs.size() >= 4 and xs.size() <= 30:
			return [l, xs[0] - 1, xs[xs.size() - 1] + 1]
	return []


func test_lakes_and_fishing() -> void:
	var colony := _new_colony(52)
	var w := colony.world
	var found := _find_lake(w)
	check(not found.is_empty(), "в мире есть озёра")
	if found.is_empty():
		return
	var lake: Dictionary = found[0]
	var level: int = lake["level"]
	var x0: int = found[1]
	var x1: int = found[2]
	check(w.get_mat(x0 + 1, level) == Mat.WATER, "в озере вода")
	check(w.feature_at(x0 + 1) == WorldGen.FEATURE_NONE, "в воде не растут деревья")
	var deep := x0
	for x in range(x0, x1 + 1):
		if w.gen.surface_y(x) > w.gen.surface_y(deep):
			deep = x
	check(not colony.pathing.node(Vector2i(deep, level - 1)), "по водной глади не бегают")
	if w.gen.surface_y(deep) - level >= 2:
		check(not colony.pathing.node(Vector2i(deep, level)), "по глубокой воде не ходят")
	# Через озеро без моста не идут.
	var shore_l := Vector2i(x0 - 1, w.gen.surface_y(x0 - 1) - 1)
	var shore_r := Vector2i(x1 + 1, w.gen.surface_y(x1 + 1) - 1)
	var walk := Pathing.path_to(colony.pathing.explore(shore_l)[0], shore_r)
	var wet := walk.filter(func(c: Vector2i) -> bool: return w.get_mat(c.x, c.y) == Mat.WATER)
	check(wet.is_empty(), "через озеро не идут — ни вплавь, ни вброд (%d клеток в воде)" % wet.size())
	var row := level - 1
	var bridge_r := Rect2i(x0, row, x1 - x0 + 1, 1)
	check(colony.validate(Project.Kind.BRIDGE, bridge_r).is_empty(), "мостик от берега до берега: " + colony.validate(Project.Kind.BRIDGE, bridge_r))
	check(not colony.validate(Project.Kind.BRIDGE, Rect2i(x0, row - 3, x1 - x0 + 1, 1)).is_empty(), "мост в воздухе нельзя")
	check(not colony.validate(Project.Kind.BRIDGE, Rect2i(x0, row, 3, 1)).is_empty(), "мост, не дотянутый до берега, нельзя")
	check(colony.validate(Project.Kind.PIER, Rect2i(x0, row, 3, 1)).is_empty(), "пристань от берега в воду можно")
	_start(colony, x0 - 3)
	colony.inventory = {"wood": 49, "stone": 20, "food": 0}
	var br := colony.create_project(Project.Kind.BRIDGE, bridge_r)
	check(br != null and br.clear_x.is_empty(), "мосту расчистка не нужна — дерево на дальнем берегу не держит стройку")
	colony.advance_offline(5000.0)
	check(br.phase == Project.Phase.DONE, "мостик построен")
	check(colony.pathing.standable(Vector2i(x0 + 2, row)), "по мостику можно ходить над водой")
	colony.inventory["food"] = 0
	check(colony.assign_work(colony.units[0], br).is_empty(), "рыбак назначен на мостик")
	colony.fish[int(lake["id"])] = Colony.fish_max(lake)
	var fish0 := colony.fish_in(lake)
	colony.game_time = 0.0 # весна: озеро не замёрзло
	colony.advance_offline(1800.0)
	check(colony.fish_in(lake) < fish0, "с мостика наловили рыбы (в озере %d → %d)" % [int(fish0), int(colony.fish_in(lake))])
	check(colony.fish_in(lake) < fish0 + 0.01, "рыбы в озере стало меньше или столько же")
	colony.fish[int(lake["id"])] = 0.0
	colony.grow_plants(Colony.FISH_REGEN * 5)
	check(absf(colony.fish_in(lake) - 5.0) < 0.01, "рыба восстанавливается")
	# Привязка мостика: ряд, проведённый над озером, становится мостиком от берега до берега.
	var fresh := _new_colony(52)
	var wr := fresh.water_rects(x0 + 2, x0 + 4)
	var b: Rect2i = wr["bridge"]
	check(b.position.y == row and fresh.validate(Project.Kind.BRIDGE, b).is_empty() \
		and fresh.validate(Project.Kind.PIER, wr["pier"]).is_empty(), "над водой предлагаются мостик и пристань")
	check(b.size.x >= x1 - x0 - 1, "мостик дотягивается до берегов (%d)" % b.size.x)
	# Рыбалка с берега — без построек.
	var c2 := _new_colony(52)
	_start(c2, x0 - 3)
	c2.inventory = {"food": 0}
	c2.fish.erase(int(lake["id"]))
	check(not c2.shore_spots().is_empty(), "есть места для рыбалки с берега")
	var tt := 0.0
	var fish_full := c2.fish_in(lake)
	for i in 300:
		c2.update(1.0)
	check(c2.fish_in(lake) >= fish_full - 0.01 and c2.inventory.get("food", 0) == 0, "сытые свободные жители рыбу сами не ловят")
	for u in c2.units:
		u.satiety = 10.0
	for bx in c2._bushes:
		c2.world.set_berries(bx, 0.0)
	while tt < 600.0 and c2.fish_in(lake) >= fish_full - 0.01:
		c2.update(1.0)
		tt += 1.0
	check(c2.fish_in(lake) < fish_full, "голодные поймали рыбу с берега (%.0f с)" % tt)
	check(c2.inventory.get("food", 0) == 0, "улов съели сразу, а не понесли впрок")
	# Разведка: жители открывают карту, где ходят.
	var ex := c2.explored_max
	c2.units[0].pos = Vector2(ex + 30, c2.units[0].pos.y)
	c2.explore()
	check(c2.explored_max >= ex + 30 and c2.is_explored(ex + 25), "карта открывается там, куда дошёл житель")


func test_save_roundtrip() -> void:
	var path := "user://test_save.json"
	var colony := _new_colony(4242)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 20, "stone": 15}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 4))
	colony.advance_offline(20000.0)
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(x + 1, s + 1, 3, 3))
	room.paused = true
	w.set_feature_mark(x - 3, true)
	check(SaveSystem.save(w, colony, Vector2i(x, s), path), "сохранение записано")

	var data := SaveSystem.load_data(path)
	check(int(data.get("seed", 0)) == 4242, "seed сохранён")
	var w2 := WorldData.new(WorldGen.new(int(data["seed"])))
	var c2 := Colony.new(w2)
	SaveSystem.apply(data, w2, c2)
	for d in range(0, 4):
		check(w2.is_dug(x, s + d), "раскопка %d восстановлена" % d)
	check(c2.inventory == colony.inventory, "склад восстановлен")
	check(c2.units.size() == 5 and c2.units[0].name == colony.units[0].name, "жители восстановлены")
	check(c2.projects.size() == 2 and c2.projects[1].paused, "стройки и пауза восстановлены")
	check(c2.interior.has(Vector2i(x, s + 1)), "готовые постройки восстановлены")
	check(w2.feature_marks.has(x - 3), "отметки сбора восстановлены")
	check(absf(c2.units[0].satiety - colony.units[0].satiety) < 0.001 and c2.units[0].profession == colony.units[0].profession,
		"потребности и профессии восстановлены (%f / %f)" % [c2.units[0].satiety, colony.units[0].satiety])
	w2.evict_outside(Rect2i(1000, 1000, 1, 1))
	check(w2.chunks.is_empty() and w2.is_dug(x, s + 1), "выгрузка не теряет раскопки")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_environment() -> void:
	check(absf(Env.temperature(1000, 0) - 34.0) < 0.01, "1 км вглубь ≈ 34 °C (9 °C у поверхности + 25 °C/км)")
	check(Env.temperature(-11000, 0) < -55.0, "11 км вверх ≈ -56 °C")
	var o2 := Env.oxygen_ratio(-8000, 0)
	check(o2 > 0.3 and o2 < 0.45, "на 8 км кислорода ~38%% (%.2f)" % o2)
	check(Env.oxygen_ratio(-100000, 0) < 0.0001, "в космосе кислорода нет")
	check(Env.air_zone(150000) == "Космос", "выше 100 км — космос")


func test_generation_speed() -> void:
	var gen := WorldGen.new(7)
	var t := Time.get_ticks_usec()
	for i in 20:
		gen.generate_chunk(i, 10 + i)
	var per_chunk := (Time.get_ticks_usec() - t) / 20000.0
	print("  генерация: %.2f мс/чанк" % per_chunk)
	check(per_chunk < 50.0, "генерация чанка быстрее 50 мс на ПК")


## Ровная площадка шириной 6 м на поверхности (без озёр) правее x0.
func _flat_x(w: WorldData, x0: int) -> int:
	for tx in range(x0, x0 + 400):
		var ts := w.gen.surface_y(tx)
		var flat := true
		for dx in range(-1, 6):
			if w.gen.surface_y(tx + dx) != ts or w.gen.water_level(tx + dx) < ts:
				flat = false
		if flat:
			return tx
	return x0


func test_hauling() -> void:
	var colony := _new_colony(41)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 30, "stone": 20}
	var gx := _flat_x(w, 8)
	# Один рабочий — носит по очереди, плашка растёт постепенно.
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(gx, w.gen.surface_y(gx) - 3, 4, 3), 1)
	check(room != null, "дом на земле заложен")
	if room == null:
		return
	var st := colony.supply_status(room)
	check(not st.is_empty() and st[0][1] == 0 and st[0][3], "плашки: сначала 0 из N, на складе ресурс есть")
	var max_carry := 0
	var partial := false
	var t := 0.0
	while t < 2000.0 and room.phase != Project.Phase.DONE:
		colony.update(0.5)
		t += 0.5
		for u in colony.units:
			if u.task == Unit.Task.HAUL and u.haul_stage == 1:
				max_carry = maxi(max_carry, u.carry_amount)
		for e in colony.supply_status(room):
			if e[1] > 0 and e[1] < e[2]:
				partial = true
	check(room.phase == Project.Phase.DONE, "материалы принесли, дом построен (%.0f с)" % t)
	check(max_carry > 0 and max_carry <= Colony.CARRY, "жители носили материалы по %d" % max_carry)
	# Носильщиков может быть сколько угодно, но каждый несёт не больше CARRY — значит, ходили не раз.
	var total := 0
	for k in room.cost():
		total += room.cost()[k]
	check(partial or total > max_carry, "материалы носили частями")
	check(room.delivered.is_empty(), "лишнего на стройке не осталось")
	# Без ресурса на складе плашка красная.
	colony.inventory = {}
	colony.drops.clear()
	var gx2 := _flat_x(w, gx + 8)
	var shed := colony.create_project(Project.Kind.ROOM, Rect2i(gx2, w.gen.surface_y(gx2) - 3, 3, 3))
	if shed != null:
		colony.update(1.0)
		var red := false
		for e in colony.supply_status(shed):
			if not e[3]:
				red = true
		check(red, "нет ресурса нигде — плашка красная")


func test_storage_workers() -> void:
	var res := _colony_with_room(24, RoomType.STORAGE)
	var colony: Colony = res[0]
	var room: Project = res[1]
	check(room.purpose == RoomType.STORAGE, "склад обустроен")
	# Без работника на склад не носят: добро лежит, где упало.
	for u in colony.units:
		u.workplace = 0
	colony.inventory = {}
	colony.drops.clear()
	var pile := Vector2i(roundi(colony.units[0].pos.x), roundi(colony.units[0].pos.y))
	colony.drop_item(pile, "wood", 6)
	for i in 120:
		colony.update(0.5)
	check(colony.inventory.get("wood", 0) == 0 and colony.drop_total("wood") == 6, "без работника склада дерево никто не понёс")
	check(not colony.can_store("wood"), "складу без работника некуда принимать")
	colony.drops.clear()
	check(not room.targets.is_empty() and room.gatherers > 0, "у склада свои нормы запаса и рабочие")
	colony.inventory = {}
	room.targets = {"wood": 15, "stone": 0}
	colony.assign_work(colony.units[0], room)
	colony.assign_work(colony.units[1], room)
	var carried := false
	var t := 0.0
	while t < 3000.0 and colony.inventory.get("wood", 0) < 15:
		colony.update(0.5)
		t += 0.5
		for u in colony.units:
			if u.task == Unit.Task.HAUL and u.gather_room == room.id:
				carried = true
	check(colony.inventory.get("wood", 0) >= 15, "работники склада сами нарубили дерева до нормы (%.0f с)" % t)
	check(carried, "добычу несли на склад")
	for i in 1200:
		colony.update(0.5)
	check(colony.inventory.get("wood", 0) < 15 + 12, "выше нормы не добывают (%d)" % colony.inventory.get("wood", 0))
	colony.inventory = {}
	room.targets = {"stone": 10}
	colony.advance_offline(3000.0)
	check(colony.inventory.get("stone", 0) > 0, "оффлайн склад тоже пополняется")


func test_wear_and_repair() -> void:
	var colony := _new_colony(52)
	var w := colony.world
	_start(colony, 0)
	colony.inventory = {"wood": 80, "stone": 40}
	var logs := []
	colony.event_logged.connect(func(text: String, _k: String) -> void: logs.append(text))
	var gx := _flat_x(w, 8)
	var s := w.gen.surface_y(gx)
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(gx, s - 3, 4, 3))
	colony.advance_offline(4000.0)
	check(room.phase == Project.Phase.DONE, "деревянный дом построен")
	check(absf(colony.service_years(room) - 20.0) < 0.01, "дерево на поверхности служит 20 лет")
	var deep := Project.new()
	deep.kind = Project.Kind.ROOM
	deep.rect = Rect2i(gx, s + 6, 4, 3)
	deep.material = "wood"
	var wood_under := colony.service_years(deep)
	deep.material = "stone"
	check(wood_under < 20.0 and wood_under > 5.0, "под землёй дерево изнашивается быстрее (%.0f лет)" % wood_under)
	check(absf(colony.service_years(deep) - 100.0) < 0.01, "камню всё равно, где стоять")
	room.wear = 0.69
	colony._wear_tick(Colony.YEAR * 0.5)
	check(logs.any(func(l: String) -> bool: return l.contains("износ 70%")), "предупреждение об износе")
	var wood0: int = colony.inventory.get("wood", 0)
	check(colony.start_repair(room), "ремонт начат")
	colony.advance_offline(3000.0)
	check(room.wear < 0.05 and not room.repairing, "дом отремонтирован (износ %d%%)" % roundi(room.wear * 100.0))
	check(colony.inventory.get("wood", 0) < wood0, "на ремонт ушло дерево")
	# Оффлайн не рушится.
	room.wear = 0.995
	colony.offline = true
	colony._wear_tick(Colony.YEAR)
	colony.offline = false
	check(colony.projects.has(room) and room.wear < 1.0, "без игрока постройка не рушится")
	# Второй этаж и обрушение от ветхости.
	colony.inventory = {"wood": 80, "stone": 40}
	room.wear = 0.0
	var upper := colony.create_project(Project.Kind.ROOM, Rect2i(gx, s - 6, 4, 3))
	check(upper != null, "второй этаж заложен")
	colony.advance_offline(6000.0)
	check(upper != null and upper.phase == Project.Phase.DONE and room.ladder, "второй этаж достроен, внизу лестница")
	room.wear = 0.9999
	colony._wear_tick(Colony.YEAR)
	check(not colony.projects.has(room), "ветхий дом рухнул")
	check(not colony.projects.has(upper), "второй этаж рухнул вместе с ним")
	check(w.get_mat(gx + 1, s - 1) == Mat.RUBBLE, "на месте дома обломки")


func test_calendar() -> void:
	var colony := _new_colony(1)
	check(colony.date_text() == "1 мар · весна · год 1", "игра начинается весной, 1 марта: " + colony.date_text())
	colony.game_time = Colony.YEAR + Colony.MONTH * 2 + Colony.DAY * 4 + Colony.DAY * 0.5
	check(colony.date_text() == "5 мая · весна · год 2", "дата по игровым суткам: " + colony.date_text())
	check(Colony.DAY_NIGHT or (not colony.is_night() and colony.daylight() == 1.0), "без смены дня и ночи всегда светло")
	check(absf(Colony.PREGNANCY_TIME - Colony.MONTH) < 0.01, "беременность — месяц")


func test_seasons() -> void:
	var res := _colony_with_room(26, RoomType.FARM)
	var colony: Colony = res[0]
	var farm: Project = res[1]
	var w := colony.world
	colony.game_time = 0.0
	check(colony.season() == Colony.Season.SPRING and not colony.is_winter(), "игра начинается весной")
	check(colony.time_to_winter() > Colony.MONTH * 8.0, "до зимы больше восьми месяцев (%s)" % Colony.game_span(colony.time_to_winter()))
	var x := farm.rect.position.x - 6
	var top := Vector2i(x, w.gen.surface_y(x) - 1)
	var spring_top := colony.elements._temperature(top)
	# Середина января.
	colony.game_time = Colony.YEAR - Colony.CALENDAR_START + Colony.MONTH * 0.5
	colony.elements._temp_memo.clear()
	check(colony.is_winter(), "январь — зима: " + colony.date_text())
	var winter_top := colony.elements._temperature(top)
	var deep := colony.elements._temperature(Vector2i(x, w.gen.surface_y(x) + 12))
	check(winter_top < 0.0 and winter_top < spring_top, "зимой на поверхности мороз (%.0f °C, весной %.0f °C)" % [winter_top, spring_top])
	check(deep > winter_top and deep > 0.0 and deep < 15.0, "на глубине 12 м зимой прохладно, но не мороз (%.0f °C)" % deep)
	check(colony.shore_spots().is_empty(), "зимой с берега не порыбачить — лёд")
	check(not colony.farm_warm(farm), "подземная ферма зимой без огня холодная (%.0f °C)" % colony.room_temp(farm))
	var hearth := _hearth(colony, farm)
	# Очаг топят сначала углём: 1 уголь — как два полена.
	colony.inventory["coal"] = 3
	colony.inventory["wood"] = 5
	check(colony._hearth_fuel(hearth, 1) == 2 and colony.inventory["coal"] == 2 and colony.inventory["wood"] == 5,
		"очаг взял уголь (за два полена), дрова не тронул")
	colony.inventory["coal"] = 0
	check(colony._hearth_fuel(hearth, 1) == 1 and colony.inventory["wood"] == 4, "угля нет — горят дрова")
	# Печь сама метан не жжёт (даже после «Газового отопления»); с газовым котлом — первым и греет дальше.
	colony.inventory["methane"] = 2
	colony.research.done.append("gas_heating")
	colony._hearth_fuel(hearth, 1)
	check(colony.inventory["methane"] == 2 and not hearth.on_gas, "печь без котла метан не жжёт")
	var zone_wood := RoomType.heat_zone(hearth)
	hearth.gas_boiler = true
	check(colony._hearth_fuel(hearth, 1) == 3 and colony.inventory["methane"] == 1 and colony.inventory["wood"] == 3 and hearth.on_gas,
		"на газу: очаг взял метан (как 3 полена), дрова не тронул")
	var zone_gas := RoomType.heat_zone(hearth)
	check(zone_gas.x > zone_wood.x and zone_gas.y > zone_wood.y, "на газу греет дальше (%s → %s)" % [zone_wood, zone_gas])
	colony.inventory["methane"] = 0
	colony._hearth_fuel(hearth, 1)
	check(not hearth.on_gas, "метан кончился — снова на дровах")
	hearth.gas_boiler = false
	colony.research.done.erase("gas_heating")
	# Погасший без дров очаг летом не держит тревогу «нет дров» (иначе все рубят лес).
	var hr0 := hearth.rect
	hearth.rect = Rect2i(x, w.gen.surface_y(x) - 3, 3, 3)
	colony.game_time = Colony.MONTH * 4.5
	colony.inventory["wood"] = 0
	hearth.blocked = "Нет дров — очаг погас"
	colony._hearth_tick(1.0)
	check(hearth.blocked.is_empty() and not colony._hearth_starving(), "летом на поверхности тревога «нет дров» снимается")
	hearth.rect = hr0
	hearth.blocked = "Нет дров — очаг погас"
	colony.inventory["wood"] = 5
	check(not colony._hearth_starving(), "дрова есть — очаг не «голодает»")
	colony.game_time = Colony.YEAR - Colony.CALENDAR_START + Colony.MONTH * 0.5
	colony.elements._temp_memo.clear()
	colony.inventory["wood"] = 20
	colony._hearth_tick(1.0)
	colony.elements._temp_memo.clear()
	check(hearth.burning and colony.farm_warm(farm), "очаг рядом — ферме тепло (%.0f °C)" % colony.room_temp(farm))
	# Тепло считается от стен очага: у стены и в 3 м от неё — полное, большой очаг греет дальше.
	var hr := hearth.rect
	var base_t := Env.temperature(hr.position.y + 1, w.gen.surface_y(hr.end.x + 3), colony.season_delta())
	var at3 := colony.elements._temperature(Vector2i(hr.end.x + 2, hr.position.y + 1))
	check(at3 >= base_t + Colony.HEAT - 0.5, "в 3 м от стены очага — полное тепло (%.0f °C)" % at3)
	var far := Vector2i(hr.end.x + 7, hr.position.y + 1)
	var far_small := colony.elements._temperature(far) - Env.temperature(far.y, w.gen.surface_y(far.x), colony.season_delta())
	hearth.rect = Rect2i(hr.position.x, hr.position.y, 9, 3)
	colony.elements._temp_memo.clear()
	check(RoomType.stoves(hearth) == 3, "в очаге 9 м — три печи")
	var far_big := colony.elements._temperature(far + Vector2i(6, 0)) - Env.temperature(far.y, w.gen.surface_y(far.x + 6), colony.season_delta())
	check(far_small < 0.5 and far_big > 0.5, "малый очаг в 7 м от стены не греет, большой — греет (%.1f / %.1f)" % [far_small, far_big])
	var hc := RoomType.equip_cost(RoomType.HEARTH, hearth)
	check(hc.get("stone", 0) == 24 and not hc.has("brick"), "три каменные печи — 24 камня (%s)" % str(hc))
	check(RoomType.equip_cost(RoomType.HEARTH_BRICK, hearth).get("brick", 0) == 18, "три кирпичные — 18 кирпичей")
	check(not RoomType.REQUIRES.has(RoomType.HEARTH) and RoomType.REQUIRES[RoomType.HEARTH_BRICK] == "bricks",
		"каменный очаг — сразу, кирпичный — после обжига кирпича")
	# Кирпичные печи: тепло дальше в 1.5 раза, служат вдвое дольше.
	var stone_zone := RoomType.heat_zone(hearth)
	var stone_years := colony.service_years(hearth)
	hearth.brick_stoves = true
	var brick_zone := RoomType.heat_zone(hearth)
	check(brick_zone.y > stone_zone.y and brick_zone.x > stone_zone.x, "кирпичные печи греют дальше (%s → %s)" % [stone_zone, brick_zone])
	check(is_equal_approx(colony.service_years(hearth), stone_years * 2.0), "кирпичный очаг служит вдвое дольше")
	hearth.brick_stoves = false
	hearth.rect = hr
	colony.projects.erase(hearth)
	colony.elements._temp_memo.clear()
	var cold_farm := _fake_room(colony, RoomType.FARM, x - 8)
	check(not colony.farm_warm(cold_farm), "ферма на поверхности зимой замерзает (%.0f °C)" % colony.room_temp(cold_farm))
	colony.projects.erase(cold_farm)
	# Ягоды зимой не растут.
	var bx := -1
	for b in colony._bushes:
		bx = b
		break
	if bx >= 0:
		w.set_berries(bx, 0.0)
		colony.grow_plants(Colony.MONTH)
		check(w.berries(bx) < 0.01, "зимой ягоды не растут")
		colony.game_time = 0.0
		colony.grow_plants(Colony.MONTH)
		check(w.berries(bx) > 0.5, "весной ягоды снова растут")
	# Зимой с пристани ловят вдвое дольше, с мостика — никак.
	var pier := Project.new()
	pier.kind = Project.Kind.PIER
	var bridge := Project.new()
	bridge.kind = Project.Kind.BRIDGE
	colony.game_time = Colony.YEAR - Colony.CALENDAR_START + Colony.MONTH * 0.5
	check(colony.fish_time(pier) == pier.fish_time() * 2.0 and colony.can_fish_from(pier), "зимой с пристани ловят вдвое дольше")
	check(not colony.can_fish_from(bridge), "зимой с мостика не ловят")
	# Холод: синий терпит больше красного; на морозе здоровье тает.
	var u: Unit = colony.units[0]
	u.health = 100.0
	u.pos = Vector2(top.x, top.y)
	colony.elements.affect_unit(u, 10.0)
	check(u.health < 100.0 or u.stat("cold") > 1.3, "на морозе житель мёрзнет (%.1f)" % u.health)
	check(colony.winter_food_need() > 0.0, "колония знает, сколько еды нужно на зиму")


func test_darkness() -> void:
	var colony := _new_colony(33)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	var s := w.gen.surface_y(x)
	check(colony.is_lit(Vector2i(x, s - 1)), "над землёй светло")
	check(not colony.is_lit(Vector2i(x, s + 5)), "в толще земли темно")
	for y in range(s, s + 5):
		w.set_material(x, y, Mat.AIR)
	check(colony.is_lit(Vector2i(x, s + 4)), "в открытую шахту светит солнце")
	check(not colony.is_lit(Vector2i(x, s + 30)), "глубоко под шахтой темно")
	var u: Unit = colony.units[0]
	var g := u.genome.duplicate(true)
	g["eyes"] = [1, 1]
	g["melanist"] = [false, false]
	g["glow"] = [false, false]
	u.set_genome(g)
	for o in colony.units:
		if o != u:
			o.pos = Vector2(x + 200, s - 1)
	u.pos = Vector2(x + 3, s + 20)
	check(colony.light_factor(u) < 1.0, "в темноте работают медленнее (%.2f)" % colony.light_factor(u))
	var glow := colony.units[1]
	var gg := glow.genome.duplicate(true)
	gg["glow"] = [true, true]
	glow.set_genome(gg)
	glow.pos = u.pos + Vector2(2, 0)
	check(colony.light_factor(u) == 1.0, "светящийся житель освещает соседей")
	glow.pos = Vector2(x + 200, s - 1)
	g["melanist"] = [true, true]
	u.set_genome(g)
	check(colony.light_factor(u) == 1.0, "меланист видит в темноте")
	g["melanist"] = [false, false]
	g["eyes"] = [0, 0]
	u.set_genome(g)
	check(colony.light_factor(u) == 1.0, "безглазому свет не нужен")


## Сплошной гранитный блок w×h с левым верхним углом o (для опытов со стихиями).
func _granite_box(w: WorldData, o: Vector2i, size: Vector2i) -> void:
	for y in range(o.y, o.y + size.y):
		for x in range(o.x, o.x + size.x):
			w.set_material(x, y, Mat.GRANITE)


func _dig_cells(w: WorldData, cells: Array) -> void:
	for c in cells:
		w.set_dug(c.x, c.y)


func _count(w: WorldData, r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.get_mat(x, y) == m:
				n += 1
	return n


func test_elements() -> void:
	var colony := _new_colony(61)
	var w := colony.world
	_start(colony, 0)
	var el := colony.elements
	var o := Vector2i(300, w.gen.surface_y(300) + 40)
	_granite_box(w, o, Vector2i(30, 20))
	# Шахта 1×6 и штрек 8×1 внизу; две клетки воды наверху шахты.
	var shaft := []
	for dy in 6:
		shaft.append(o + Vector2i(2, 2 + dy))
	var drift := []
	for dx in range(3, 11):
		drift.append(o + Vector2i(dx, 7))
	_dig_cells(w, shaft + drift)
	w.set_fluid(o.x + 2, o.y + 2, Mat.WATER)
	w.set_fluid(o.x + 2, o.y + 3, Mat.WATER)
	check(w.get_mat(o.x + 2, o.y + 2) == Mat.WATER and w.is_dug(o.x + 2, o.y + 2), "вода в выработке хранится поверх неё")
	el.active[o + Vector2i(2, 2)] = true
	el.active[o + Vector2i(2, 3)] = true
	for i in 100:
		el.update(0.2)
	check(_count(w, Rect2i(o.x + 2, o.y + 2, 1, 5), Mat.WATER) == 0, "вода стекла вниз по шахте")
	check(_count(w, Rect2i(o.x + 2, o.y + 7, 9, 1), Mat.WATER) == 2, "и растеклась по дну штрека (воды не прибавилось)")
	check(w.get_mat(o.x + 2, o.y + 2) == Mat.AIR and w.is_dug(o.x + 2, o.y + 2), "вода ушла — выработка снова пустая")
	# Насос откачивает воду.
	var pump := Project.new()
	pump.id = 900
	pump.kind = Project.Kind.ROOM
	pump.phase = Project.Phase.DONE
	pump.purpose = RoomType.PUMP
	pump.rect = Rect2i(o.x + 12, o.y + 5, 3, 3)
	colony.projects.append(pump)
	for i in 10:
		el.update(1.0)
	check(_count(w, Rect2i(o.x, o.y, 30, 20), Mat.WATER) == 0, "насосная откачала воду")
	colony.projects.erase(pump)
	# Лава стекает и застывает базальтом.
	w.set_fluid(o.x + 2, o.y + 2, Mat.MAGMA)
	el.active[o + Vector2i(2, 2)] = true
	for i in 20:
		el.update(0.8)
	check(_count(w, Rect2i(o.x + 2, o.y + 2, 1, 5), Mat.MAGMA) == 0 and _count(w, Rect2i(o.x + 2, o.y + 7, 9, 1), Mat.MAGMA) == 1,
		"лава стекла вниз")
	check(el.temperature(o + Vector2i(4, 7)) > 200.0, "рядом с лавой жарко")
	for i in 130:
		el.update(1.0)
	check(_count(w, Rect2i(o.x + 2, o.y + 7, 9, 1), Mat.MAGMA) == 0 and _count(w, Rect2i(o.x + 2, o.y + 7, 9, 1), Mat.BASALT) == 1,
		"вытекшая лава застыла базальтом")
	# Лава и вода: камень и пар.
	var a := o + Vector2i(6, 7)
	var b := o + Vector2i(7, 7)
	w.set_fluid(a.x, a.y, Mat.MAGMA)
	w.set_fluid(b.x, b.y, Mat.WATER)
	el._entered(a, Mat.MAGMA)
	check(w.get_mat(a.x, a.y) == Mat.BASALT and w.get_mat(b.x, b.y) == Mat.AIR, "лава с водой: базальт и пар")
	# Метан расходится и поднимается, вентиляция выводит.
	el.release_gas(o + Vector2i(2, 6))
	for i in 5:
		el.update(1.0)
	check(el.gas_at(o + Vector2i(2, 4)) > 0.0, "метан поднялся по шахте")
	var u := colony.units[0]
	u.pos = Vector2(o + Vector2i(2, 6))
	u.health = 100.0
	el.explode(o + Vector2i(2, 6))
	check(u.health < 100.0, "взрыв метана ранит жителя рядом")
	check(el.gas_at(o + Vector2i(2, 6)) == 0.0, "газ выгорел при взрыве")
	el.release_gas(o + Vector2i(2, 5))
	var vent := Project.new()
	vent.id = 901
	vent.kind = Project.Kind.ROOM
	vent.phase = Project.Phase.DONE
	vent.purpose = RoomType.DEGAS
	vent.rect = Rect2i(o.x + 12, o.y + 5, 3, 3)
	check(RoomType.effect_radius(vent) == 10, "малая дегазация (3 м) — радиус 10")
	vent.rect = Rect2i(o.x + 12, o.y + 5, 6, 3)
	check(RoomType.effect_radius(vent) == 15, "средняя (6 м) — радиус 15")
	vent.rect = Rect2i(o.x + 12, o.y + 5, 9, 3)
	check(RoomType.effect_radius(vent) == 20, "большая (9 м) — радиус 20")
	colony.projects.append(vent)
	for i in 20:
		el.update(1.0)
	var total := 0.0
	for c in el.gas:
		total += el.gas[c]
	check(total < 0.1, "дегазация собрала метан из выработок (%.2f)" % total)
	check(colony.inventory.get("methane", 0) >= 1, "метан стал топливом (%d)" % colony.inventory.get("methane", 0))
	colony.projects.erase(vent)
	# Житель под водой всплывает туда, где можно дышать.
	for c in [o + Vector2i(2, 6), o + Vector2i(2, 5), o + Vector2i(2, 4)]:
		w.set_fluid(c.x, c.y, Mat.WATER)
	u.pos = Vector2(o + Vector2i(2, 6))
	u.health = 100.0
	u.state = Unit.State.IDLE
	for i in 60:
		colony._update_unit(u, 0.2)
	check(not colony._head_in_water(u) and u.health > 0.0, "житель выплыл из затопленной шахты")
	# Сохранение воды в выработках.
	var data := SaveSystem.serialize(w, colony, Vector2i.ZERO)
	var w2 := WorldData.new(WorldGen.new(61))
	var c2 := Colony.new(w2)
	SaveSystem.apply(JSON.parse_string(JSON.stringify(data)), w2, c2)
	check(w2.get_mat(o.x + 2, o.y + 5) == Mat.WATER and w2.is_dug(o.x + 2, o.y + 5), "вода в выработке сохраняется")
	# Геолог чует воду рядом с забоем и останавливает бригаду.
	var gc := _new_colony(62)
	var gw := gc.world
	var gx := _find_solid_column(gw)
	_start(gc, gx)
	gc.inventory = {"wood": 40}
	var gs := gw.gen.surface_y(gx)
	gw.set_fluid(gx, gs + 6, Mat.WATER)
	gw.set_fluid(gx + 1, gs + 6, Mat.WATER)
	var gp := gc.create_project(Project.Kind.TUNNEL, Rect2i(gx, gs, 1, 5))
	for i in 600:
		gc.update(0.5)
		if gp.paused:
			break
	check(gp.paused and gp.hazard_pending == "water" and gp.blocked.begins_with("Геолог"), "геолог предупредил о воде: " + gp.blocked)
	gc.set_paused(gp, false)
	check(not gp.paused and gp.hazard_ack.has("water"), "игрок разрешил копать дальше")


## Газовая тревога: метан у стройки останавливает работы, жители уходят из облака,
## игрок может приказать продолжать; газ ушёл — работы идут сами.
func test_gas_alarm() -> void:
	var colony := _new_colony(63)
	var w := colony.world
	_start(colony, 0)
	var el := colony.elements
	var o := Vector2i(300, w.gen.surface_y(300) + 40)
	_granite_box(w, o, Vector2i(40, 12))
	var cells := []
	for y in range(o.y + 2, o.y + 5):
		for x in range(o.x + 2, o.x + 36):
			cells.append(Vector2i(x, y))
	_dig_cells(w, cells)
	var room := Project.new()
	room.id = 950
	room.kind = Project.Kind.ROOM
	room.phase = Project.Phase.DONE
	room.purpose = RoomType.FARM
	room.rect = Rect2i(o.x + 2, o.y + 2, 6, 3)
	colony.projects.append(room)
	el.gas[o + Vector2i(4, 3)] = 0.3
	el.gas[o + Vector2i(4, 4)] = 0.3
	el._gas_alarm()
	check(not room.paused, "готовая ферма в метане работает: искру даёт только кирка")
	room.phase = Project.Phase.DIG
	room.purpose = RoomType.NONE
	el._gas_alarm()
	check(room.paused and room.hazard_pending == "methane", "метан у копки — работы остановлены")
	var u := colony.units[0]
	u.pos = Vector2(o + Vector2i(4, 4))
	u.state = Unit.State.IDLE
	u.task = Unit.Task.NONE
	el.affect_unit(u, 0.1)
	check(u.task == Unit.Task.GOTO and el.gas_at(u.target) < Elements.GAS_CLEAR, "житель уходит из облака метана")
	colony.set_paused(room, false)
	el._gas_alarm()
	check(not room.paused and room.hazard_ack.has("methane"), "игрок приказал работать в газе — тревога молчит")
	el.gas.clear()
	el._gas_alarm()
	check(not room.hazard_ack.has("methane"), "газ ушёл — тревога снова на страже")
	el.gas[o + Vector2i(4, 3)] = 0.3
	el._gas_alarm()
	el.gas.clear()
	el._gas_alarm()
	check(not room.paused and room.hazard_pending.is_empty(), "метан ушёл — работы возобновились сами")
	colony.projects.erase(room)


## Рядом нечего рубить — житель идёт к краю разведанного, карта раскрывается дальше.
func test_scouting() -> void:
	var colony := _new_colony(64)
	_start(colony, 0)
	var u := colony.units[0]
	var reach := colony.pathing.explore(u.cell())
	var before := colony.explored_max - colony.explored_min
	check(colony._try_scout(u, reach[0], reach[1], "wood"), "житель пошёл на разведку")
	check(u.task == Unit.Task.GOTO and (u.target.x >= colony.explored_max - 8 or u.target.x <= colony.explored_min + 8),
		"идёт к краю разведанного")
	check(not colony._try_scout(colony.units[1], reach[0], reach[1], "wood"), "разведчиков не шлют толпой")
	for i in 200:
		colony.update(0.5)
	check(colony.explored_max - colony.explored_min > before, "разведанное расширилось (%d → %d)" % [before, colony.explored_max - colony.explored_min])


## Дерево наук: все требования существуют, всё изучается по порядку, эффекты работают.
func test_tech_tree() -> void:
	var r := Research.new()
	for id in Research.TECHS:
		for need in Research.TECHS[id][3]:
			check(Research.TECHS.has(need), "%s требует существующую %s" % [id, need])
	var colony := _new_colony(65)
	_start(colony, 0)
	var cap := colony.storage_capacity("wood")
	var dig := colony.dig_bonus()
	r = colony.research
	var guard := 0
	while r.done.size() < Research.TECHS.size() and guard < 100:
		guard += 1
		if r.current.is_empty():
			for id in Research.TECHS:
				if r.start(id):
					break
		r.add(10000.0)
	check(r.done.size() == Research.TECHS.size(), "все %d технологий можно изучить (%d)" % [Research.TECHS.size(), r.done.size()])
	check(colony.dig_bonus() == 2.0 and dig == 1.0, "глубинное бурение: копка вдвое быстрее")
	check(colony.carry_cap() == 8 and colony.build_bonus() == 1.5 and colony.automation_bonus() == 1.5, "тачки, плотники, автоматика")
	check(colony.farm_bonus() >= 1.25, "агрономия прибавила урожай")
	check(cap == 0 or colony.storage_capacity("wood") > cap, "стеллажи расширили склады")


## Генетика: яркие основатели, наследование копий, мутации ~1/10, сверхюнит по цвету лого.
func test_genetics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bright := true
	for i in 50:
		var c := Genetics.color_of(Genetics.founder(rng))
		bright = bright and c.v >= 0.99 and c.s >= 0.84
	check(bright, "основатели — максимально яркие цвета")
	var mom := Genetics.founder(rng)
	var dad := Genetics.founder(rng)
	var mutants := 0
	var from_parents := true
	for i in 2000:
		var k := Genetics.child(mom, dad, rng)
		if Genetics.is_mutant(k):
			mutants += 1
		elif not (k["shape"][0] == mom["shape"][0] and k["shape"][1] == dad["shape"][0]):
			from_parents = false
	check(from_parents, "копии генов — по одной от каждого родителя")
	check(mutants > 140 and mutants < 260, "мутации примерно в 1 из 10 рождений (%d из 2000)" % mutants)
	var kid := Genetics.child(mom, dad, rng)
	check(Genetics.color_of(kid).v >= 0.95, "дети ярких родителей — яркие")
	var logo := Genetics.founder(rng)
	logo["color"] = [CreatureArt.SUPER_A, CreatureArt.SUPER_B]
	check(Genetics.is_super(logo) and Genetics.stats(logo)["vision"] >= 2.0, "цвет лого — сверхюнит, характеристики ×2")
	var m := Genetics.founder(rng)
	Genetics.mutate(m, rng, "eyes")
	check(Genetics.is_mutant(m) and Genetics.mutation_text(m).begins_with("Мутант"), "мутант помечен: " + Genetics.mutation_text(m))
	var hairy := Genetics.founder(rng)
	hairy["hair"] = [true, false]
	check(not Genetics.has(hairy, "hair"), "волосы видны, только если обе копии их несут")
	var many := Genetics.founder(rng)
	many["eyes"] = [3, 3]
	for i in 3:
		Genetics.mutate(many, rng, "eyes")
	check(Genetics.eyes_of(many) >= 3, "глаз может стать больше трёх (%d)" % Genetics.eyes_of(many))
	var counts := {}
	for i in 20000:
		var k := Genetics.roll_mutation(rng)
		var r: int = Genetics.MUTATIONS[k][0]
		counts[r] = counts.get(r, 0) + 1
	check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3], "мутации разной редкости: %s" % counts)
	var melan := Genetics.founder(rng)
	Genetics.mutate(melan, rng, "melanist")
	check(Genetics.has(melan, "melanist") and Genetics.stats(melan)["cold"] > 1.3, "меланист — чёрный, не мёрзнет")


## Жители: гены и имена при рождении, сохранение генов, места работы, знакомства, сватовство.
func test_residents() -> void:
	var colony := _new_colony(66)
	_start(colony, 0)
	var u := colony.units[0]
	check(not u.genome.is_empty() and not u.stats.is_empty(), "у жителя есть гены и характеристики")
	var names := {}
	for o in colony.units:
		names[o.name] = true
	check(names.size() == colony.units.size(), "имена разные: %s" % ", ".join(names.keys()))
	# Сохранение генов.
	var data := SaveSystem.serialize(colony.world, colony, Vector2i.ZERO)
	var c2 := Colony.new(WorldData.new(WorldGen.new(66)))
	SaveSystem.apply(JSON.parse_string(JSON.stringify(data)), c2.world, c2)
	var u2 := c2.unit_by_id(u.id)
	check(u2 != null and Genetics.color_of(u2.genome).is_equal_approx(Genetics.color_of(u.genome))
		and Genetics.shape_of(u2.genome) == Genetics.shape_of(u.genome), "гены сохраняются и загружаются")
	# Рождение: гены от родителей.
	var mom: Unit = colony.units.filter(func(o: Unit) -> bool: return o.sex == Unit.Sex.FEMALE)[0]
	var dad: Unit = colony.units.filter(func(o: Unit) -> bool: return o.sex == Unit.Sex.MALE)[0]
	mom.partner_id = dad.id
	dad.partner_id = mom.id
	colony._birth(mom)
	var baby: Unit = colony.units[-1]
	check(baby.mother_id == mom.id and baby.father_id == dad.id and not baby.genome.is_empty(), "ребёнок знает родителей, гены от них")
	# Место работы.
	var farm := Project.new()
	farm.id = 990
	farm.kind = Project.Kind.ROOM
	farm.phase = Project.Phase.DONE
	farm.purpose = RoomType.FARM
	farm.rect = Rect2i(5, colony.world.gen.surface_y(5) - 3, 6, 3)
	colony.projects.append(farm)
	var worker := colony.units[2]
	check(colony.assign_work(worker, farm).is_empty() and worker.workplace == farm.id, "житель назначен на ферму")
	check(colony._closed_for(colony.units[3], farm) and not colony._closed_for(worker, farm), "на ферме работают только назначенные")
	check(not colony.assign_work(baby, farm).is_empty(), "детей не назначить")
	colony.unassign_work(worker)
	check(worker.workplace == 0 and colony._closed_for(worker, farm), "снят — на ферме работают только назначенные")
	check(colony.suitability(worker, farm) > 0.0, "подсказка, насколько подходит")
	colony.projects.erase(farm)
	# Склад и амбар: еда — только в амбаре.
	var st := _fake_room(colony, RoomType.STORAGE, 20)
	var gr := _fake_room(colony, RoomType.GRANARY, 30)
	check(RoomType.stores(gr, "food") and RoomType.stores(gr, "berries") and not RoomType.stores(gr, "wood"), "амбар хранит только еду")
	check(RoomType.stores(st, "wood") and not RoomType.stores(st, "food"), "склад хранит ресурсы, но не еду")
	check(colony.storage_capacity("food") > 0 and colony.storage_capacity("wood") > 0, "вместимость: еда — амбар, дерево — склад")
	colony.projects.erase(st)
	colony.projects.erase(gr)
	# Знакомство: рядом — растёт.
	var a := colony.units[0]
	var b := colony.units[1]
	var far := colony.units[3]
	colony.acquaint.clear()
	a.pos = Vector2(0, 0)
	b.pos = Vector2(2, 0)
	far.pos = Vector2(40, 0)
	colony._meet(30.0)
	check(colony.acquaintance(a, b) > 0.0, "рядом — знакомятся")
	check(colony.acquaintance(a, far) == 0.0, "далеко — не знакомятся")


func test_loads() -> void:
	var colony := _new_colony(71)
	var w := colony.world
	_start(colony, 0)
	var gx := _flat_x(w, 10)
	var s := w.gen.surface_y(gx)
	colony.inventory = {"wood": 50, "stone": 50}
	colony.known_resources = {"wood": true, "stone": true}
	var base := colony.create_project(Project.Kind.ROOM, Rect2i(gx, s - 3, 5, 3), -1, "stone")
	colony.advance_offline(6000.0)
	check(base != null and base.phase == Project.Phase.DONE, "каменное основание построено")
	# Лёгкие деревянные этажи на каменном основании: можно больше, чем раньше разрешалось.
	var floors: Array[Project] = [base]
	for i in 4:
		colony.inventory = {"wood": 60, "stone": 60}
		var r := Rect2i(gx, s - 6 - i * 3, 5, 3)
		var err := colony.validate(Project.Kind.ROOM, r, "wood")
		if not err.is_empty():
			check(i >= 1, "на камень встаёт хотя бы 2 деревянных этажа: " + err)
			break
		var f := colony.create_project(Project.Kind.ROOM, r, -1, "wood")
		colony.advance_offline(6000.0)
		floors.append(f)
	var top: Project = floors[floors.size() - 1]
	var err2 := colony.validate(Project.Kind.ROOM, Rect2i(gx, top.rect.position.y - 3, 5, 3), "wood")
	check(not err2.is_empty(), "дальше не пускает вес или ветер: " + err2)
	colony.loads.loads = colony.loads.compute()
	check(colony.loads.utilization(base) > 0.0 and colony.loads.utilization(base) <= 1.0, "основание нагружено, но держит")
	check(colony.loads.load_on(base) > colony.loads.load_on(floors[1]), "нижнему тяжелее, чем верхним")
	# Тонкая башня опрокидывается ветром.
	var tower := colony.loads.tower_of(Rect2i(gx, top.rect.position.y - 3, 5, 3), "wood")
	check(tower[0] == s - top.rect.position.y + 3 and tower[1] == 5 and tower[2] == "stone",
		"высота башни — от земли, основание — нижний этаж (%d м, %d м)" % [tower[0], tower[1]])
	# Обветшавший и перегруженный этаж трещит и рушится через минуту.
	var lower: Project = floors[1] if floors.size() > 2 else base
	lower.wear = 0.99
	var logs := []
	colony.event_logged.connect(func(t: String, _k: String) -> void: logs.append(t))
	for p in colony.projects:
		if p != lower:
			p.wear = 0.0
	var over := colony.loads.utilization(lower, colony.loads.compute()) > 1.0
	if over:
		for i in 70:
			colony.loads.update(1.0)
		check(logs.any(func(t: String) -> bool: return t.contains("перегружена")), "сначала предупреждение о перегрузке")
		check(not colony.projects.has(lower), "перегруженный этаж рухнул")
	# Землетрясение изнашивает постройки.
	var c2 := _new_colony(72)
	_start(c2, 0)
	c2.inventory = {"wood": 50}
	var gx2 := _flat_x(c2.world, 10)
	var hut := c2.create_project(Project.Kind.ROOM, Rect2i(gx2, c2.world.gen.surface_y(gx2) - 3, 4, 3))
	c2.advance_offline(4000.0)
	var w0 := hut.wear
	var mags := []
	c2.quaked.connect(func(m: int) -> void: mags.append(m))
	c2.loads.quake(2)
	check(hut.wear > w0 + 0.03 and mags == [2], "землетрясение изнашивает и трясёт камеру")
	# Буря изнашивает наземные постройки.
	var w1 := hut.wear
	c2.loads.storm_t = 0.0
	for i in 60:
		c2.loads.update(1.0)
	check(c2.loads.storm_left > 0.0 or hut.wear > w1, "началась буря")
	check(hut.wear > w1, "в бурю наземный дом ветшает быстрее")
	# Без стихийных бедствий ни бурь, ни землетрясений.
	c2.disasters = false
	c2.loads.storm_left = 0.0
	c2.loads.storm_t = 0.0
	c2.loads.quake_t = 0.0
	mags.clear()
	for i in 30:
		c2.loads.update(1.0)
	check(c2.loads.storm_left <= 0.0 and mags.is_empty(), "галочка «Стихийные бедствия» выключает бури и землетрясения")
	check(Loads.STORM_EVERY.x >= 3600.0 * 4 and Loads.QUAKE_EVERY.x >= 3600.0 * 12, "бедствия очень редкие")


func test_economy() -> void:
	var res := _colony_with_room(81, RoomType.LAB)
	var colony: Colony = res[0]
	var lab: Project = res[1]
	check(lab.purpose == RoomType.LAB, "лаборатория обустроена")
	check(not colony.set_purpose(lab, RoomType.KILN), "печь нельзя без исследования")
	check(not colony.available_materials().has("brick"), "кирпичных стен пока нет")
	check(colony.research.start("bricks"), "начали изучать обжиг кирпича")
	check(not colony.research.available("metallurgy"), "металлургия — только после кирпича")
	for u in colony.units:
		colony.assign_work(u, lab)
	check(colony.assigned_to(lab).size() == colony.work_slots(lab), "учёные назначены по числу мест")
	var t := 0.0
	while t < 2000.0 and not colony.research.has("bricks"):
		colony.update(1.0)
		t += 1.0
	check(colony.research.has("bricks"), "учёные изучили обжиг кирпича (%.0f с)" % t)
	check(colony.available_materials().has("brick"), "открылись кирпичные стены")
	check(colony.research.available("metallurgy"), "открылась металлургия")
	# Печь делает кирпич (оффлайн тоже).
	colony.inventory = {"wood": 40, "stone": 40, "clay": 40, "food": 50}
	check(colony.set_purpose(lab, RoomType.KILN), "лабораторию переделали в печь")
	colony.advance_offline(3000.0)
	var bricks: int = colony.inventory.get("brick", 0) + colony.drop_total("brick")
	check(lab.purpose == RoomType.KILN and bricks > 0, "печь обожгла кирпич (%d)" % bricks)
	check(colony.inventory.get("clay", 40) < 40, "на кирпич ушла глина")
	# Генератор жжёт уголь и даёт энергию.
	colony.research.done.append("electricity")
	colony.inventory = {"wood": 40, "stone": 40, "copper": 10, "iron": 10, "coal": 3, "food": 50}
	check(colony.set_purpose(lab, RoomType.GENERATOR), "печь переделали в генератор")
	colony.advance_offline(3000.0)
	check(lab.purpose == RoomType.GENERATOR, "генератор готов")
	colony.inventory["coal"] = 2
	colony._power_tick(1.0)
	check(colony.power_made == RoomType.POWER_MAKE and colony.powered(), "генератор даёт энергию")
	colony._power_tick(RoomType.FUEL_TIME * 3.0)
	colony._power_tick(1.0)
	colony._power_tick(RoomType.FUEL_TIME * 3.0)
	colony._power_tick(1.0)
	check(colony.inventory.get("coal", 0) == 0, "уголь сгорел")
	# Бурение ускоряет копку.
	var before := colony.dig_bonus()
	colony.research.done.append("drilling")
	check(colony.dig_bonus() > before, "бурение ускоряет копку")
	# Сохранение науки.
	var d := colony.to_dict()
	var c2 := Colony.new(WorldData.new(WorldGen.new(81)))
	c2.load_dict(JSON.parse_string(JSON.stringify(d)))
	check(c2.research.has("bricks") and c2.research.has("drilling"), "исследования сохраняются")


func test_drops_and_scouting() -> void:
	# Новые миры: кустов втрое меньше, озёр в полтора раза больше; старые сохранения — по-старому.
	var old := WorldGen.new(5, 1)
	var neu := WorldGen.new(5)
	var bushes := [0, 0]
	for x in range(-3000, 3000):
		if old.feature_at(x) == WorldGen.FEATURE_BUSH:
			bushes[0] += 1
		if neu.feature_at(x) == WorldGen.FEATURE_BUSH:
			bushes[1] += 1
	check(bushes[1] * 2 < bushes[0], "кустов стало втрое меньше (%d → %d)" % bushes)
	var lakes := [0, 0]
	for k in range(-60, 60):
		if not old._lake_of_segment(k).is_empty():
			lakes[0] += 1
	for k in range(-90, 90):
		if not neu._lake_of_segment(k).is_empty():
			lakes[1] += 1
	check(lakes[1] > lakes[0] * 1.3, "озёр на тот же участок больше (%d → %d)" % lakes)
	# Комнаты — только 3 м в высоту.
	check(not Project.size_error(Project.Kind.ROOM, Rect2i(0, 0, 6, 4)).is_empty(), "комната 6×4 нельзя — только 3 м")
	check(Project.size_error(Project.Kind.ROOM, Rect2i(0, 0, 9, 3)).is_empty(), "комната 9×3 можно")
	# Камень из шахты ложится в выработке, его подбирают для стройки.
	var colony := _new_colony(91)
	var w := colony.world
	var x := _find_solid_column(w)
	_start(colony, x)
	colony.inventory = {"wood": 30}
	var s := w.gen.surface_y(x)
	var shaft := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 8))
	var t := 0.0
	var dropped := false
	while t < 3000.0 and shaft.phase != Project.Phase.DONE:
		colony.update(0.5)
		t += 0.5
		for c in colony.drops:
			if c.x == x and c.y > s:
				dropped = true
	check(shaft.phase == Project.Phase.DONE, "шахта выкопана")
	check(dropped, "добытая порода падала на дно шахты")
	# Оффлайн жители перетаскивают всё лежащее на склад.
	colony.drop_item(Vector2i(x, s - 1), "stone", 4)
	var st: int = colony.inventory.get("stone", 0)
	colony.advance_offline(120.0)
	check(colony.drops.is_empty() and colony.inventory.get("stone", 0) >= st + 4, "оффлайн всё лежащее унесли на склад")
	# Стройка берёт материалы прямо из кучи.
	colony.inventory = {}
	var gx := _flat_x(w, x + 10)
	colony.drop_item(Vector2i(gx - 2, w.gen.surface_y(gx - 2) - 1), "wood", 30)
	var hut := colony.create_project(Project.Kind.ROOM, Rect2i(gx, w.gen.surface_y(gx) - 3, 3, 3))
	colony.update(0.5)
	check(hut != null and colony.supply_status(hut).all(func(e: Array) -> bool: return e[3]), "дерево в куче считается — плашки не красные")
	t = 0.0
	while t < 2000.0 and hut != null and hut.phase != Project.Phase.DONE:
		colony.update(0.5)
		t += 0.5
	check(hut != null and hut.phase == Project.Phase.DONE, "дом построен из дерева, лежавшего на земле (%.0f с)" % t)
	# Разведка: житель идёт в указанную точку (сытый — голодный сначала пошёл бы за едой).
	var u := colony.units[0]
	u.satiety = 100.0
	u.energy = 100.0
	var target := Vector2i(u.cell().x + 25, w.gen.surface_y(u.cell().x + 25) - 1)
	var to = colony.send_unit(u, target)
	check(to != null and u.task == Unit.Task.GOTO, "житель отправлен на разведку")
	var before := colony.explored_max
	for i in 120:
		colony.update(0.5)
	check(absi(u.cell().x - target.x) <= 2 or colony.explored_max > before, "житель дошёл и разведал округу")


func test_food_balance() -> void:
	var colony := _new_colony(95)
	_start(colony, 0)
	var u := colony.units[0]
	# Ягоды — перекус, рыба и грибы — еда, в столовой сытнее.
	colony.inventory = {"berries": 10}
	u.satiety = 20.0
	colony._eat_from(u, colony._take_store)
	var after_berries := u.satiety
	colony.inventory = {"food": 10}
	u.satiety = 20.0
	colony._eat_from(u, colony._take_store)
	var after_food := u.satiety
	colony.inventory = {"food": 10}
	u.satiety = 20.0
	colony._eat_from(u, colony._take_store, Colony.DINING_BONUS)
	check(after_berries - 20.0 < 40.0, "ягоды насыщают слабо (+%d)" % roundi(after_berries - 20.0))
	check(after_food > after_berries, "рыба сытнее ягод (+%d)" % roundi(after_food - 20.0))
	check(u.satiety > after_food or u.satiety >= 99.0, "в столовой сытнее")
	check(colony.feature_yield(0)[0] in ["", "wood", "stone", "berries"], "куст даёт ягоды, а не еду")
	# У новой базы рядом есть пруд.
	var g := WorldGen.new(95)
	var pond := g.lake_at(55)
	check(not pond.is_empty() and absi(int(pond["cx"])) - int(pond["w"]) > 30, "недалеко от базы есть пруд")
	check(colony.explored_max >= Colony.START_VIEW, "поверхность у базы видна далеко")


func test_build_priority() -> void:
	var colony := _new_colony(4242)
	var world := colony.world
	_start(colony, 0)
	# Как у игрока: много отмеченного на сбор и мало еды — стройка всё равно идёт.
	for d in range(1, 60):
		for x in [d, -d]:
			if world.feature_at(x) != WorldGen.FEATURE_NONE:
				colony.toggle_harvest(x)
	var lake := world.gen.lake_at(55)
	var span := world.gen.lake_water_span(lake)
	# Жест начат у дальнего берега — пристань всё равно встаёт у того, куда можно дойти.
	var r: Rect2i = colony.water_rects(span.y, span.y - 4)["pier"]
	check(colony.can_reach(r), "пристань ставится к берегу, до которого можно дойти")
	colony.inventory = {"wood": 40, "stone": 10, "food": 4}
	var p := colony.create_project(Project.Kind.PIER, r, 1)
	var t := 0.0
	while t < 600.0 and p.phase != Project.Phase.DONE:
		colony.update(0.5)
		t += 0.5
	check(p.phase == Project.Phase.DONE, "пристань с одним рабочим построена, хотя дел полно (%.0f с)" % t)
	# Недоступная стройка: предупреждение.
	var far := Rect2i(span.y - 1, int(lake["level"]) - 1, 3, 1)
	if not colony.can_reach(far) and colony.validate(Project.Kind.PIER, far).is_empty():
		var q := colony.create_project(Project.Kind.PIER, far, 1)
		for i in 20:
			colony.update(0.5)
		check(q.blocked.begins_with("Нет доступа"), "до недоступной стройки — предупреждение: " + q.blocked)


func test_idle_spread() -> void:
	# Бездельники не стоят толпой в одной клетке: один отходит на свободное место в комнате.
	var res := _colony_with_room(31)
	var colony: Colony = res[0]
	var room: Project = res[1]
	check(room.phase == Project.Phase.DONE, "комната для прогулки готова")
	var a: Unit = colony.units[0]
	var b: Unit = colony.units[1]
	var spot := Vector2(RoomType.floor_start(room), room.rect.end.y - 1)
	for u in [a, b]:
		colony._drop(u)
		u.pos = spot
		u.state = Unit.State.IDLE
	check(colony._crowded(a), "двое в одной клетке — толпа")
	check(colony._stroll(a) and a.task == Unit.Task.STROLL and a.target != b.cell(), "один отходит в сторону (%s)" % a.target)
	for i in 400:
		colony._update_unit(a, 0.05)
		if a.task != Unit.Task.STROLL:
			break
	check(a.cell() != b.cell() and not colony._crowded(b), "разошлись: %s и %s" % [a.cell(), b.cell()])


func test_buried_drop() -> void:
	# Засыпанную породой кучу выносит наверх, и её уносят на склад.
	var res := _colony_with_room(24, RoomType.STORAGE)
	var colony: Colony = res[0]
	var room: Project = res[1]
	colony.assign_work(colony.units[0], room)
	colony.store_targets = {}
	colony.drops.clear()
	var u: Unit = colony.units[1]
	var at := Vector2i(roundi(u.pos.x), roundi(u.pos.y) + 1)
	check(not colony.world.is_open(at.x, at.y), "клетка под ногами — порода")
	colony.drops[at] = {"clay": 5}
	colony._settle_drops()
	check(colony.drop_amount(at, "clay") == 0 and colony.drop_total("clay") == 5, "кучу вынесло из породы")
	for i in 600:
		colony.update(0.5)
	check(colony.drop_total("clay") == 0, "глину унесли на склад (на земле %d)" % colony.drop_total("clay"))


func test_separate_stores() -> void:
	# У каждого склада своё содержимое, нормы и работники; метан — только в баке дегазации.
	var res := _colony_with_room(24, RoomType.STORAGE)
	var colony: Colony = res[0]
	var a: Project = res[1]
	var rb := Rect2i(a.rect.end.x, a.rect.position.y, 6, 3)
	colony.inventory = {"wood": 80, "stone": 80, "food": 50}
	var err := colony.validate(Project.Kind.ROOM, rb)
	check(err.is_empty(), "второй склад можно поставить рядом: " + err)
	var b := colony.create_project(Project.Kind.ROOM, rb)
	colony.advance_offline(20000.0)
	colony.inventory = {"wood": 80, "stone": 80, "food": 50}
	colony.set_purpose(b, RoomType.STORAGE)
	colony.advance_offline(5000.0)
	check(b.purpose == RoomType.STORAGE, "второй склад готов")
	for u in colony.units:
		u.workplace = 0
		u.satiety = 100.0
		u.energy = 100.0
		u.health = 100.0
	colony.assign_work(colony.units[0], a)
	colony.assign_work(colony.units[1], b)
	colony.inventory = {"food": 50}
	colony.drops.clear()
	colony._sync_held()
	a.targets = {"wood": 10}
	b.targets = {}
	var t := 0.0
	while t < 3000.0 and colony.held_in(a, "wood") < 10:
		colony.update(0.5)
		t += 0.5
	check(colony.held_in(a, "wood") >= 10, "работник склада А нарубил в свой склад (%d)" % colony.held_in(a, "wood"))
	check(colony.held_in(b, "wood") == 0, "в склад Б с пустыми нормами дерево не попало")
	check(colony.inventory.get("wood", 0) >= colony.held_in(a, "wood"), "итог колонии — сумма складов")
	# Положить в конкретный склад и взять именно из него.
	colony._add("stone", 7, b)
	check(colony.held_in(b, "stone") == 7 and colony.held_in(a, "stone") == 0, "камень лежит только в складе Б")
	check(colony._remove("stone", 3, b) == 3 and colony.held_in(b, "stone") == 4, "взяли из склада Б")
	check(colony._remove("stone", 10, a) == 0, "из склада А камня не взять — там его нет")
	# Метан: без дегазации хранить негде; с ней — в бак до его вместимости.
	check(colony._add("methane", 5) == 0, "без дегазации метан хранить негде")
	colony.inventory = {"wood": 80, "stone": 80, "food": 50}
	colony._sync_held()
	check(colony.set_purpose(b, RoomType.DEGAS), "склад Б переделываем в дегазацию")
	colony.advance_offline(5000.0)
	check(b.purpose == RoomType.DEGAS, "дегазация готова")
	var cap := colony.room_cap(b, "methane")
	check(cap > 0 and colony._add("methane", cap + 50) == cap and colony.held_in(b, "methane") == cap,
		"метан — в баке дегазации, лишнее не помещается (%d)" % cap)
	check(colony.room_cap(a, "methane") == 0 and colony.held_in(a, "methane") == 0, "на складе метан не хранится")
	colony._remove("methane", 10)
	check(colony.held_in(b, "methane") == cap - 10 and colony.inventory["methane"] == cap - 10, "генератор берёт газ из бака")
	# Старое сохранение: общий запас раскладывается по складам, метан — в бак (лишний улетает).
	var d := colony.to_dict()
	d.erase("stores_v")
	d["inventory"]["methane"] = cap + 500
	d["inventory"]["wood"] = 300
	for pd in d["projects"]:
		pd.erase("held")
	var loaded := Colony.new(colony.world)
	loaded.load_dict(d)
	var la := loaded.project_by_id(a.id)
	var lb := loaded.project_by_id(b.id)
	check(loaded.held_in(lb, "methane") == cap and loaded.inventory["methane"] == cap, "старое сохранение: метан в баке, лишний улетучился")
	check(loaded.held_in(la, "wood") == mini(300 - RoomType.BASE_CAPACITY, loaded.room_cap(la, "wood")) and loaded.inventory["wood"] == 300,
		"старое сохранение: дерево разложено по складу (в складе %d, у базы %d)" % [loaded.held_in(la, "wood"), loaded.base_have("wood")])


func test_mine_meters() -> void:
	# Шахта строится по метру; «Остановить» — готовая часть остаётся шахтой.
	# Шахтёр только копает, крепь и добытое носит работник склада.
	var res := _colony_with_room(24, RoomType.STORAGE)
	var colony: Colony = res[0]
	var store: Project = res[1]
	var x := store.rect.position.x - 1
	var s := colony.world.gen.surface_y(x)
	for u in colony.units:
		u.workplace = 0
		u.satiety = 100.0
		u.energy = 100.0
	var keeper: Unit = colony.units[0]
	var miner: Unit = colony.units[1]
	colony.assign_work(keeper, store)
	colony.set_profession(miner, Unit.Prof.MINER)
	colony.inventory = {"wood": 60, "food": 50}
	colony._sync_held()
	var r := Rect2i(x - 9, s + 3, 9, 3)
	var err := colony.validate(Project.Kind.MINE, r)
	check(err.is_empty(), "шахта у тоннеля: " + err)
	var mine := colony.create_project(Project.Kind.MINE, r)
	check(mine != null, "шахта заложена")
	if mine == null:
		return
	check(colony.mine_hauler(keeper) and not colony.mine_hauler(miner), "носят работники склада, шахтёр — нет")
	var miner_carried := false
	var keeper_hauled := false
	var t := 0.0
	while t < 6000.0 and colony.mine_meters_done(mine) < 3 and mine.phase == Project.Phase.DIG:
		colony.update(0.5)
		t += 0.5
		if miner.task in [Unit.Task.HAUL, Unit.Task.SUPPORT, Unit.Task.BUILD]:
			miner_carried = true
		if keeper.task == Unit.Task.HAUL and keeper.project_id == mine.id:
			keeper_hauled = true
	var done := colony.mine_meters_done(mine)
	check(done >= 3, "шахта копается по метру: готово %d м за %.0f с" % [done, t])
	check(not miner_carried, "шахтёр не носил и не крепил — только копал")
	check(keeper_hauled, "работник склада носил в шахту дерево на крепь")
	colony.cancel_project(mine)
	check(colony.projects.has(mine) and mine.phase == Project.Phase.DONE and mine.rect.size.x >= 3 and mine.rect.size.x < 9,
		"остановили: готовая часть осталась шахтой (%d м)" % mine.rect.size.x)
	for i in mine.slice_count():
		check(colony.slice_dug(mine, i), "метр %d остановленной шахты выкопан" % i)


func test_lights() -> void:
	# Свет: 1 ед. энергии на 3 м комнаты; сам горит в ближних к генератору, пока хватает;
	# в комнате включают и выключают целиком; на стройке — одна лампа там, где работают.
	var res := _colony_with_room(24)
	var colony: Colony = res[0]
	var room: Project = res[1]
	colony.research.done.append("electricity")
	check(colony.lightable(room) and RoomType.blocks(room) == 2, "комната 6 м под землёй — 2 лампочки")
	var gen := Project.new()
	gen.id = 950
	gen.kind = Project.Kind.ROOM
	gen.phase = Project.Phase.DONE
	gen.purpose = RoomType.GENERATOR
	gen.rect = Rect2i(room.rect.end.x + 30, room.rect.position.y, 3, 3)
	colony.projects.append(gen)
	colony.inventory = {"coal": 10}
	colony._power_tick(0.1)
	check(colony.powered() and room.lit, "генератор работает — в комнате сам загорелся свет")
	check(colony.power_used >= RoomType.blocks(room), "свет расходует энергию (%d)" % colony.power_used)
	var c := Vector2i(room.rect.position.x + 2, room.rect.end.y - 1)
	check(colony.is_lit(c), "в комнате со светом светло")
	room.light = 0
	colony._power_tick(0.1)
	check(not room.lit and not colony.is_lit(c), "выключили — в комнате темно")
	room.light = 1
	colony._power_tick(0.1)
	check(room.lit, "включили вручную — горит")
	# Дальняя комната не загорается, если энергии не хватает: свет всей комнатой.
	room.light = -1
	var far := Project.new()
	far.id = 951
	far.kind = Project.Kind.ROOM
	far.phase = Project.Phase.DONE
	far.rect = Rect2i(room.rect.position.x - 200, room.rect.position.y, 9, 3)
	colony.projects.append(far)
	var near := Project.new()
	near.id = 952
	near.kind = Project.Kind.ROOM
	near.phase = Project.Phase.DONE
	near.rect = Rect2i(gen.rect.position.x - 9, gen.rect.position.y + 3, 9, 3)
	colony.projects.append(near)
	colony._power_tick(0.1)
	var budget := colony.power_made
	check(near.lit, "ближняя к генератору комната горит")
	check(colony.power_used <= budget, "сам свет не берёт больше, чем есть (%d из %d)" % [colony.power_used, budget])
	# Лампа на стройке — там, где житель работает.
	var u: Unit = colony.units[0]
	var site := Project.new()
	site.id = 953
	site.kind = Project.Kind.TUNNEL
	site.phase = Project.Phase.DIG
	site.rect = Rect2i(room.rect.position.x - 50, room.rect.position.y + 20, 1, 3)
	colony.projects.append(site)
	u.project_id = site.id
	u.state = Unit.State.WORK
	u.task = Unit.Task.DIG
	u.pos = Vector2(site.rect.position)
	room.light = 0
	near.light = 0
	far.light = 0
	colony._power_tick(0.1)
	check(colony.work_lamps.size() == 1 and colony.work_lamps[0] == u.cell(), "на стройке горит одна лампа у работника")
	check(colony.is_lit(u.cell()), "у лампы светло")
