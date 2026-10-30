extends SceneTree
## Набор замеров быстродействия на большой колонии (снимок игры: tests/fixtures/big_colony.json —
## ~60 гавриков, ~250 построек, ~1150 куч, глубокие шахты, бур, лифты, вода и газ).
##   godot --headless --path . -s res://tests/perf_suite.gd [-- быстро]
## Сценарии: та же колония, дополненная копиями взрослых до 200 и 400 гавриков; на ×1 (кадр
## 1/30 с) и на ×10 (шаг 1/3 с — ускоренная игра). Для каждого — мс расчёта на секунду игры,
## худший кадр и сколько кадров дольше 33 мс (рывки), а ещё — какую скорость выдержит кадр
## в 30 мс. В конце — цены отдельных операций (доступ к клетке, обход для поиска пути,
## поиск работы и т. п.).

const FIXTURE := "res://tests/fixtures/big_colony.json"
const FRAME_BUDGET_MS := 30.0
var quick := false


func _initialize() -> void:
	quick = OS.get_cmdline_user_args().has("быстро")
	print("Замеры быстродействия (%s)" % ("быстро" if quick else "полностью"))
	print("сценарий                       мс/с игры  худший кадр  кадров>33мс  ×макс при 30 мс/кадр")
	var cases := [[0, 1.0 / 30.0, "×1"], [0, 1.0 / 3.0, "×10"], [200, 1.0 / 30.0, "×1"], [200, 1.0 / 3.0, "×10"]]
	if not quick:
		cases.append([400, 1.0 / 3.0, "×10"])
	for cs in cases:
		_scenario(int(cs[0]), float(cs[1]), str(cs[2]))
	_micro()
	quit()


func _load(n: int) -> Colony:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var world := WorldData.new(WorldGen.new(int(data["seed"]), int(data.get("gen", 1))))
	var c := Colony.new(world)
	SaveSystem.apply(data, world, c)
	grow(c, n)
	return c


## Дополняет колонию копиями взрослых до n гавриков (свободные, без пары и места работы).
static func grow(c: Colony, n: int) -> void:
	var adults := c.units.filter(func(u: Unit) -> bool: return not u.child)
	var i := 0
	while c.units.size() < n:
		var src: Unit = adults[i % adults.size()]
		i += 1
		var d := src.to_dict()
		d["id"] = c.next_unit_id
		c.next_unit_id += 1
		d["name"] = "%s %d" % [src.name, i]
		d["partner_id"] = 0
		d["workplace"] = 0
		d["profession"] = Unit.Prof.ANY
		var u := Unit.from_dict(d)
		u.env_t = fmod(float(u.id) * 0.618034, 1.0)
		c.units.append(u)
		c._units_rev += 1


func _scenario(n: int, dt: float, speed: String) -> void:
	var c := _load(n)
	# Разгон: бездельники расходятся, кэши наполняются — меряем установившуюся игру.
	var warm := 10.0 if quick else 30.0
	var t := 0.0
	while t < warm:
		c.update(0.2)
		t += 0.2
	var span := 15.0 if quick else 40.0
	t = 0.0
	var worst := 0
	var over := 0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while t < span:
		var f0 := Time.get_ticks_usec()
		c.update(dt)
		var d := Time.get_ticks_usec() - f0
		worst = maxi(worst, d)
		if d > 33000:
			over += 1
		frames += 1
		t += dt
	var ms_per_s := (Time.get_ticks_usec() - t0) / 1000.0 / span
	# Сколько секунд игры в секунду влезет, если на расчёт кадра есть 30 мс при 60 кадрах.
	var max_speed := FRAME_BUDGET_MS * 60.0 / ms_per_s
	print("%-30s %9.1f  %8.1f мс  %5d из %-5d ×%.1f" % ["%d гавриков, %s" % [c.units.size(), speed], ms_per_s,
		worst / 1000.0, over, frames, max_speed])


func _bench(name: String, n: int, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	print("  %-34s %10.2f мкс" % [name, float(Time.get_ticks_usec() - t0) / n])


func _micro() -> void:
	print("Отдельные операции (200 гавриков):")
	var c := _load(200)
	var t := 0.0
	while t < 20.0:
		c.update(0.2)
		t += 0.2
	var u: Unit = c.units[0]
	var cell := u.cell()
	var w := c.world
	var pa := c.pathing
	var n := 20000
	_bench("клетка мира (get_mat)", n, func(): w.get_mat(cell.x, cell.y))
	_bench("можно ли стоять (pathing.node)", n, func(): pa.node(cell))
	_bench("постройка в клетке (project_at)", n, func(): c.project_at(cell))
	_bench("комнаты по назначению (rooms_of)", n, func(): c.rooms_of(RoomType.STORAGE))
	_bench("рабочие на стройке (workers_on)", 2000, func(): c.workers_on(c.projects[0]))
	_bench("освещена ли клетка (is_lit)", n, func(): c.is_lit(cell))
	_bench("температура (свежая)", 2000, func():
		c.elements._temp_memo.clear()
		c.elements.temperature(cell))
	_bench("обход для пути (тёплый)", 20, func(): pa._explore(cell))
	_bench("обход для пути (малый, 600)", 200, func(): pa._explore(cell, 600))
	var idle := c.units.filter(func(o: Unit) -> bool: return not o.child and o.task == Unit.Task.NONE)
	if not idle.is_empty():
		var k := [0]
		_bench("поиск работы (бездельник)", 40, func():
			var v: Unit = idle[k[0] % idle.size()]
			k[0] += 1
			if c._assign(v):
				c._drop(v)
				v.state = Unit.State.IDLE
				v.path.clear())
	var mover: Unit = null
	for o in c.units:
		if o.state == Unit.State.MOVE and o.path_i < o.path.size():
			mover = o
			break
	if mover != null:
		var saved := [mover.pos, mover.path_i, mover.state]
		_bench("шаг идущего гаврика (кадр)", 5000, func():
			c._update_unit(mover, 0.001)
			mover.pos = saved[0]
			mover.path_i = saved[1]
			mover.state = saved[2])
	_bench("вода и газ (шаг 0,2 с)", 50, func(): c.elements.update(0.2))
	_bench("жизнь гавриков (шаг 0,2 с)", 50, func(): c._life_tick(0.2, false))
