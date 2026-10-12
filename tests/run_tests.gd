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
	test_dig_and_reveal()
	test_order_rules()
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


func _find_solid_column(world: WorldData) -> int:
	for x in range(0, 400):
		var s := world.gen.surface_y(x)
		var ok := true
		for d in range(0, 12):
			if not Mat.is_diggable(world.get_mat(x, s + d)):
				ok = false
		if ok:
			return x
	return 0


func test_dig_and_reveal() -> void:
	var world := WorldData.new(WorldGen.new(99))
	var dig := DigSystem.new(world)
	var x := _find_solid_column(world)
	var s := world.gen.surface_y(x)
	check(not world.is_revealed(x, s + 3), "глубже поверхности — неизвестность")
	for d in range(0, 6):
		check(dig.add_order(Vector2i(x, s + d)), "заказ шахты, клетка %d" % d)
	dig.advance(100000.0)
	for d in range(0, 6):
		check(world.is_dug(x, s + d), "клетка %d выкопана" % d)
	check(world.is_revealed(x + 1, s + 3), "стены шахты открыты")
	check(not world.is_revealed(x + 3, s + 3), "дальше стен — по-прежнему неизвестно")
	check(dig.order.is_empty(), "очередь опустела")
	check(dig.cells_dug == 6 and not dig.inventory.is_empty(), "ресурсы добыты")


func test_order_rules() -> void:
	var world := WorldData.new(WorldGen.new(5))
	var dig := DigSystem.new(world)
	var s := world.gen.surface_y(0)
	check(not dig.add_order(Vector2i(0, s + 10)), "нельзя копать в толще без доступа")
	check(not dig.add_order(Vector2i(0, s - 3)), "нельзя копать воздух")
	check(dig.add_order(Vector2i(0, s)), "можно копать поверхность")
	check(dig.add_order(Vector2i(0, s + 1)), "можно продолжить цепочку заказов")
	dig.toggle_order(Vector2i(0, s + 1))
	check(not dig.has_job(Vector2i(0, s + 1)), "повторное нажатие отменяет заказ")


func test_save_roundtrip() -> void:
	var path := "user://test_save.json"
	var world := WorldData.new(WorldGen.new(4242))
	var dig := DigSystem.new(world)
	var x := _find_solid_column(world)
	var s := world.gen.surface_y(x)
	for d in range(0, 4):
		dig.add_order(Vector2i(x, s + d))
	dig.advance(100000.0)
	dig.add_order(Vector2i(x, s + 4))
	dig.advance(0.5)
	check(SaveSystem.save(world, dig, Vector2i(x, s), path), "сохранение записано")

	var data := SaveSystem.load_data(path)
	check(int(data.get("seed", 0)) == 4242, "seed сохранён")
	var world2 := WorldData.new(WorldGen.new(int(data["seed"])))
	var dig2 := DigSystem.new(world2)
	SaveSystem.apply(data, world2, dig2)
	for d in range(0, 4):
		check(world2.is_dug(x, s + d), "раскопка %d восстановлена" % d)
	check(dig2.inventory == dig.inventory, "склад восстановлен")
	check(dig2.has_job(Vector2i(x, s + 4)) and absf(dig2.progress[Vector2i(x, s + 4)] - 0.5) < 0.01, "очередь и прогресс восстановлены")
	# Изменения переживают выгрузку чанков из памяти.
	world2.evict_outside(Rect2i(1000, 1000, 1, 1))
	check(world2.chunks.is_empty() and world2.is_dug(x, s + 1), "выгрузка не теряет раскопки")
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
