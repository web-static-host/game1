extends SceneTree
## Замер большой колонии: бот строит базу, затем гавриков доводят до N (по умолчанию 55)
## и меряют, сколько стоит шаг симуляции (0,5 с игры). Снимок колонии сохраняется в
## user://perf_<seed>_<N>.json — повторные замеры (после правок) начинаются с него сразу.
##   godot --headless --path . -s res://tests/perf_big_colony.gd -- <seed> <минут разгона> <N> <минут замера>
## Снимок годится и для замера кадров настоящей игры: tests/perf_fps.gd.
const BotPlayer := preload("res://tests/bot_player.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 555
	var warm := int(args[1]) if args.size() > 1 else 150
	var total := int(args[2]) if args.size() > 2 else 55
	var measure := int(args[3]) if args.size() > 3 else 20
	var snap := "user://perf_%d_%d.json" % [seed_value, total]
	var world: WorldData
	var c: Colony
	var bot
	var t := 0.0
	var think := 0.0
	var data := SaveSystem.load_data(snap)
	if not data.is_empty():
		world = WorldData.new(WorldGen.new(int(data["seed"]), int(data["gen"])))
		c = Colony.new(world)
		SaveSystem.apply(data, world, c)
		bot = BotPlayer.new(c)
		t = c.game_time
		print("снимок загружен: гавриков %d, строек %d" % [c.units.size(), c.projects.size()])
	else:
		world = WorldData.new(WorldGen.new(seed_value))
		c = Colony.new(world)
		c.start_new(0)
		bot = BotPlayer.new(c)
		while t < warm * 60.0:
			c.update(0.5)
			t += 0.5
			think += 0.5
			bot.t = t
			if think >= 5.0:
				think = 0.0
				bot.think()
		var adults := c.units.filter(func(u: Unit) -> bool: return not u.child)
		print("после разгона: гавриков %d (взрослых %d), строек %d, глубина %d" % [c.units.size(), adults.size(), c.projects.size(), c.deepest_y])
		while c.units.size() < total and not adults.is_empty():
			var src: Unit = adults[c.units.size() % adults.size()]
			var u := c._new_unit(c.rng.randi_range(0, 1), src.pos)
			u.age = Unit.CHILD_TIME + 0.3 * Colony.YEAR
			u.satiety = 90.0
		for u in c.units:
			u.lifespan = 0.0
		c.inventory["food"] = int(c.inventory.get("food", 0)) + 3000
		c.inventory["wood"] = int(c.inventory.get("wood", 0)) + 600
		c.inventory["stone"] = int(c.inventory.get("stone", 0)) + 300
		bot.t = t
		bot.think()
		for i in 120:
			c.update(0.5)
			t += 0.5
		SaveSystem.save(world, c, Vector2i.ZERO, snap)
		print("снимок сохранён")
	bot.t = t
	bot.think()
	# Замер.
	var costs: Array[float] = []
	var t_end := t + measure * 60.0
	while t < t_end:
		var t0 := Time.get_ticks_usec()
		c.update(0.5)
		costs.append((Time.get_ticks_usec() - t0) / 1000.0)
		t += 0.5
		think += 0.5
		bot.t = t
		if think >= 5.0:
			think = 0.0
			bot.think()
	var n := costs.size()
	var sorted := costs.duplicate()
	sorted.sort()
	var sum := 0.0
	for x in costs:
		sum += x
	print("гавриков %d, строек %d; шаг 0,5 с игры: средн %.1f мс, p50 %.1f, p95 %.1f, max %.1f" % [c.units.size(), c.projects.size(), sum / n, sorted[n / 2], sorted[int(n * 0.95)], sorted[-1]])
	print("секунда игры стоит %.0f мс (×20 без тормозов — если меньше 50)" % (sum / n * 2.0))
	quit()
