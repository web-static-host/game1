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
	colony.inventory = Colony.START_INVENTORY.duplicate()
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
	var x := _find_solid_column(w)
	var s := w.gen.surface_y(x)
	check(not w.is_revealed(x, s + 3), "глубже поверхности — неизвестность")
	var shaft := colony.create_project(Project.Kind.TUNNEL, Rect2i(x, s, 1, 6))
	var room := colony.create_project(Project.Kind.ROOM, Rect2i(x + 1, s + 3, 4, 3))
	check(shaft != null and room != null, "стройки заложены")
	var wood_before: int = colony.inventory["wood"]
	var dug := colony.advance_offline(20000.0)
	check(dug == 6 + 12, "выкопаны шахта и комната (%d)" % dug)
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
	check(colony.toggle_harvest(tree), "дерево отмечено на сбор")
	colony.advance_offline(5000.0)
	check(w.feature_at(tree) == WorldGen.FEATURE_NONE, "дерево срублено")
	check(p.phase == Project.Phase.DONE, "после сбора дерева стройка завершена")


func test_units_realtime() -> void:
	var colony := _new_colony(31)
	var w := colony.world
	var x := _find_solid_column(w, 0)
	colony.start_new(x)
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


func test_save_roundtrip() -> void:
	var path := "user://test_save.json"
	var colony := _new_colony(4242)
	var w := colony.world
	colony.start_new(0)
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
