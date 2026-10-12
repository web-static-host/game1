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
	test_room_purposes()
	test_needs_realtime()
	test_family()
	test_tunnel_throughput()
	test_professions()
	test_build_rules_v2()
	test_physics()
	test_nature()
	test_slices()
	test_lakes_and_fishing()
	test_hauling()
	test_storage_workers()
	test_wear_and_repair()
	test_calendar()
	test_elements()
	test_loads()
	test_economy()
	test_drops_and_scouting()
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
	colony.start_new(0)
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


func test_pause_and_materials() -> void:
	var colony := _new_colony(7)
	var w := colony.world
	colony.start_new(0)
	colony.inventory = {}
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	var p := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 4))
	colony.set_paused(p, true)
	check(colony.advance_offline(5000.0) == 0, "на паузе работы не идут")
	colony.set_paused(p, false)
	colony.advance_offline(5000.0)
	check(p.phase == Project.Phase.DIG and p.supported.is_empty(), "без дерева на крепь копка встала")
	check(p.blocked.begins_with("Не хватает: дерево"), "игрок видит, чего не хватает: " + p.blocked)
	check(not colony.supply_status(p).is_empty() and not colony.supply_status(p)[0][3], "плашка дерева красная — носить неоткуда")
	# Ищем дерево и отмечаем его на сбор.
	var tree := 0
	for tx in range(-200, 200):
		if w.feature_at(tx) == WorldGen.FEATURE_TREE:
			tree = tx
			break
	check(colony.toggle_harvest(tree).is_empty(), "дерево отмечено на сбор")
	colony.advance_offline(5000.0)
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE, "дерево срублено")
	check(p.phase == Project.Phase.DONE, "после сбора дерева стройка завершена")


func test_units_realtime() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	var x := _find_solid_column(w, 0)
	colony.start_new(x)
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
		check(colony.pathing.standable(u.cell()), "%s стоит на опоре" % u.name)
	# Сбор дерева онлайн.
	var tree := 0
	for tx in range(x - 60, x + 60):
		if w.feature_at(tx) == WorldGen.FEATURE_TREE:
			tree = tx
			break
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
		colony.start_new(0)
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
	colony.start_new(x)
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
func _colony_with_room(seed_value: int, purpose := -1, width := 6) -> Array:
	var colony := _new_colony(seed_value)
	var w := colony.world
	var x := _find_solid_column(w)
	colony.start_new(x)
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
	return [colony, room]


func test_room_materials() -> void:
	var colony := _new_colony(12)
	check(colony.available_materials() == ["wood"], "в начале доступно только дерево")
	colony._add("clay", 3)
	colony._add("stone", 3)
	check(colony.available_materials() == ["wood", "clay", "stone"], "глина и камень открываются после добычи")
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
	check(room.phase == Project.Phase.EQUIP and room.blocked.begins_with("Не хватает"), "без дерева склад не обустроить")
	colony.inventory = {"wood": 50, "food": 50}
	colony.advance_offline(3000.0)
	check(room.purpose == RoomType.STORAGE and room.phase == Project.Phase.DONE, "склад обустроен")
	check(colony.capacity("stone") > cap0, "склад увеличил вместимость")
	colony.inventory = {"stone": colony.capacity("stone") - 1}
	colony._add("stone", 10)
	check(colony.inventory["stone"] == colony.capacity("stone"), "лишнее сверх вместимости не помещается")

	var farm_res := _colony_with_room(22, RoomType.FARM)
	var fc: Colony = farm_res[0]
	var farm: Project = farm_res[1]
	check(farm.purpose == RoomType.FARM, "ферма обустроена")
	fc.inventory["food"] = 0
	var food0 := 0
	fc.advance_offline(1800.0)
	check(fc.inventory.get("food", 0) > food0, "ферма производит еду (%d → %d)" % [food0, fc.inventory.get("food", 0)])

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


func test_tunnel_throughput() -> void:
	check(Colony.tunnel_lanes(Rect2i(0, 0, 1, 10)) == 1, "шахта шириной 1 — один поток")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 3, 10)) == 3, "шахта шириной 3 — три потока")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 10, 2)) == 1, "штрек высотой 2 — один поток")
	check(Colony.tunnel_lanes(Rect2i(0, 0, 10, 3)) == 2, "штрек высотой 3 — два потока")
	var colony := _new_colony(26)
	var w := colony.world
	var x := _find_solid_column(w)
	colony.start_new(x)
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
	colony.start_new(0)
	var u := colony.units[0]
	u.profession = Unit.Prof.DIGGER
	check(colony._task_order(u)[0] == "dig", "копатель сначала копает")
	u.profession = Unit.Prof.FARMER
	check(colony._task_order(u)[0] == "farm", "фермер сначала идёт на ферму")
	var kid := colony._new_unit(Unit.Sex.FEMALE, Vector2.ZERO)
	kid.child = true
	check(colony.adults() == 5, "дети не считаются рабочими")


func test_build_rules_v2() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	colony.start_new(0)
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
	colony.start_new(0)
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
	colony3.start_new(x3)
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
	colony.start_new(x)
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
	colony.start_new(0)
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
	check(colony.drop_amount(colony._ground_cell(bush), "food") == 6, "ягоды лежат у куста")
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
	var row := level - 1
	var bridge_r := Rect2i(x0, row, x1 - x0 + 1, 1)
	check(colony.validate(Project.Kind.BRIDGE, bridge_r).is_empty(), "мостик от берега до берега: " + colony.validate(Project.Kind.BRIDGE, bridge_r))
	check(not colony.validate(Project.Kind.BRIDGE, Rect2i(x0, row - 3, x1 - x0 + 1, 1)).is_empty(), "мост в воздухе нельзя")
	check(not colony.validate(Project.Kind.BRIDGE, Rect2i(x0, row, 3, 1)).is_empty(), "мост, не дотянутый до берега, нельзя")
	check(colony.validate(Project.Kind.PIER, Rect2i(x0, row, 3, 1)).is_empty(), "пристань от берега в воду можно")
	colony.start_new(x0 - 3)
	colony.inventory = {"wood": 49, "stone": 20, "food": 0}
	var br := colony.create_project(Project.Kind.BRIDGE, bridge_r)
	colony.advance_offline(5000.0)
	check(br.phase == Project.Phase.DONE, "мостик построен")
	check(colony.pathing.standable(Vector2i(x0 + 2, row)), "по мостику можно ходить над водой")
	colony.inventory["food"] = 0
	colony.fish[int(lake["id"])] = Colony.fish_max(lake)
	var fish0 := colony.fish_in(lake)
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
	c2.start_new(x0 - 3)
	c2.inventory = {"food": 0}
	c2.fish.erase(int(lake["id"]))
	check(not c2.shore_spots().is_empty(), "есть места для рыбалки с берега")
	for u in c2.units:
		u.profession = Unit.Prof.GATHERER
	var tt := 0.0
	while tt < 600.0 and c2.inventory.get("food", 0) == 0:
		c2.update(1.0)
		tt += 1.0
	check(c2.inventory.get("food", 0) > 0, "с берега поймали рыбу (%.0f с)" % tt)
	# Разведка: жители открывают карту, где ходят.
	var ex := c2.explored_max
	c2.units[0].pos = Vector2(ex + 30, c2.units[0].pos.y)
	c2.explore()
	check(c2.explored_max >= ex + 30 and c2.is_explored(ex + 25), "карта открывается там, куда дошёл житель")


func test_save_roundtrip() -> void:
	var path := "user://test_save.json"
	var colony := _new_colony(4242)
	var w := colony.world
	colony.start_new(0)
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
	check(absf(Env.temperature(1000, 0) - 40.0) < 0.01, "1 км вглубь ≈ 40 °C")
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
	colony.start_new(0)
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
	check(partial, "плашки заполнялись постепенно")
	check(room.delivered.is_empty(), "лишнего на стройке не осталось")
	# Без ресурса на складе плашка красная.
	colony.inventory = {}
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
	check(not room.targets.is_empty() and room.gatherers > 0, "у склада есть нормы запаса и рабочие")
	colony.inventory = {}
	room.targets = {"wood": 15, "stone": 0, "food": 0}
	room.gatherers = 2
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
	colony.start_new(0)
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
	check(room.wear < 0.01 and not room.repairing, "дом отремонтирован")
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
	check(colony.date_text() == "1 янв · 00:00 · год 1", "календарь начинается с 1 января: " + colony.date_text())
	colony.game_time = Colony.YEAR + Colony.MONTH * 2 + Colony.DAY * 4 + Colony.DAY * 14.5 / 24.0
	check(colony.date_text() == "5 мар · 14:30 · год 2", "дата и время по игровым суткам: " + colony.date_text())
	check(not colony.is_night() and colony.daylight() == 1.0, "днём светло")
	colony.game_time = Colony.DAY * 23.0 / 24.0
	check(colony.is_night() and colony.daylight() == 0.0, "в 23:00 ночь")


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
	colony.start_new(0)
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
	gc.start_new(gx)
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


func test_loads() -> void:
	var colony := _new_colony(71)
	var w := colony.world
	colony.start_new(0)
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
	c2.start_new(0)
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
		u.profession = Unit.Prof.SCIENTIST
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
	check(lab.purpose == RoomType.KILN and colony.inventory.get("brick", 0) > 0, "печь обожгла кирпич (%d)" % colony.inventory.get("brick", 0))
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
	colony.start_new(x)
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
	# Разведка: житель идёт в указанную точку.
	var u := colony.units[0]
	var target := Vector2i(u.cell().x + 25, w.gen.surface_y(u.cell().x + 25) - 1)
	var to = colony.send_unit(u, target)
	check(to != null and u.task == Unit.Task.GOTO, "житель отправлен на разведку")
	var before := colony.explored_max
	for i in 120:
		colony.update(0.5)
	check(absi(u.cell().x - target.x) <= 2 or colony.explored_max > before, "житель дошёл и разведал округу")
