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
	test_lakes_and_fishing()
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
	check(p.phase == Project.Phase.BUILD and not p.paid, "без дерева стройка ждёт материалы")
	check(p.blocked.begins_with("Не хватает"), "игрок видит, чего не хватает")
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
	while t < 1500.0 and w.feature_at(tree) != WorldGen.FEATURE_NONE:
		colony.update(1.0)
		t += 1.0
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE and colony.inventory["wood"] > wood, "житель дошёл и срубил дерево (%.0f с)" % t)


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
	p.kind = Project.Kind.TUNNEL
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
	var t := colony3.create_project(Project.Kind.TUNNEL, Rect2i(x3, s3, 1, 8))
	colony3.advance_offline(20000.0)
	check(t.phase == Project.Phase.DONE, "шахта построена")
	var wood := int(colony3.inventory.get("wood", 0))
	check(colony3.demolish(t), "шахта снесена")
	check(int(colony3.inventory.get("wood", 0)) == wood + t.cost()["wood"] / 2, "вернулась половина дерева")
	check(colony3.project_by_id(t.id) == null and not colony3.interior.has(Vector2i(x3, s3 + 2)), "постройки больше нет")


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
	check(colony.inventory.get("food", 0) == 6, "ягоды на складе")
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
	check(not colony.pathing.passable(Vector2i(x0 + 1, level)), "по воде не ходят")
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
	var fish0 := colony.fish_in(lake)
	colony.advance_offline(1800.0)
	check(colony.inventory.get("food", 0) > 0, "с мостика наловили рыбы (%d еды)" % colony.inventory.get("food", 0))
	check(colony.fish_in(lake) < fish0 + 0.01, "рыбы в озере стало меньше или столько же")
	colony.fish[int(lake["id"])] = 0.0
	colony.grow_plants(Colony.FISH_REGEN * 5)
	check(absf(colony.fish_in(lake) - 5.0) < 0.01, "рыба восстанавливается")


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
