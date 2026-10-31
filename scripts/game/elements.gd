class_name Elements
extends RefCounted
## Стихии под землёй:
## - вода и лава текут клеточным автоматом: вниз, а вбок — если есть куда пролиться
##   или сверху давит столб; считаются только «активные» клетки у мест, где что-то поменялось;
## - лава вне очага остывает в базальт, с водой даёт камень и пар;
## - вскрытый водоносный пласт сочится водой; насосы откачивают воду;
## - метан из газовых карманов расходится по выработкам и поднимается вверх,
##   взрывается от искр; дегазация его собирает; газовая тревога останавливает работы;
## - жара: глубина + лава рядом, вентиляция охлаждает.
## Оффлайн стихии стоят: катастрофы без игрока не случаются.

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const SIDES: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WATER_STEP := 0.2
const LAVA_STEP := 0.8
const MAX_MOVES := 600
## Через сколько секунд без движения вытекшая лава застывает базальтом.
const LAVA_COOL := 90.0
## Как часто вскрытый водоносный пласт выпускает клетку воды.
const SPRING_TIME := 25.0
const PUMP_TIME := 2.0
## Насос не нашёл воды — следующий обзор зоны через столько секунд.
const PUMP_DRY_WAIT := 8.0
const GAS_STEP := 1.0
## Сколько метана отдаёт вскрытая клетка, всего и в секунду.
const SEEP_RESERVE := {Mat.GAS_POCKET: 40.0, Mat.COAL: 2.5}
const SEEP_RATE := 0.06
## Доля метана в зоне дегазации, которую она забирает за секунду.
const DEGAS_TAKE := 0.6
## Метана в одной клетке газового кармана.
const GAS_PER_POCKET := 3.0
const GAS_MIN := 0.01
## Взрывоопасная концентрация и удушье.
const GAS_EXPLOSIVE := 0.25
const GAS_CHOKE := 0.5
## Метан у стройки, при котором работы встают (ниже взрывоопасного), и «проветрено».
const GAS_ALARM := 0.15
const GAS_CLEAR := 0.05
const VENT_COOLING := 18.0
## Ниже этой температуры вентиляция не охлаждает: красным нормально, обычным — на пределе,
## синим (жару не переносят) — смертельно, пока нет «Климат-контроля».
const VENT_MIN_TEMP := 50.0
## Выше — гаврикам вредно (жара).
const HOT := 50.0
## Температура внутри корабля.
const SHIP_TEMP := 20.0
## Выше этой температуры огонь (сколько бы очагов ни было) не греет.
const FIRE_MAX_TEMP := 30.0

var colony: Colony
var world: WorldData
## Клетки с жидкостью, которые могут сдвинуться: Vector2i -> true.
var active := {}
## Сколько секунд вытекшая лава стоит без движения: Vector2i -> сек.
var lava_still := {}
## Вскрытые водоносные пласты: клетка -> таймер.
var springs := {}
## Вскрытые газовые карманы и угольные пласты сочатся метаном: клетка -> остаток газа.
var seeps := {}
## Сколько метана накопила дегазация (в доли единицы ресурса).
var _captured := 0.0
## Метан в открытых клетках: Vector2i -> доля (0..1+).
var gas := {}
## Вскрытые газовые карманы: клетка -> сколько секунд ещё помнить. Взрыв, остановка копки
## и бегство из газа — только рядом с ними: метан из угля и разошедшийся по ходам не взрывается.
var pockets := {}
const POCKET_RADIUS := 6
const POCKET_MEMORY := 1800.0
var _water_t := 0.0
var _lava_t := 0.0
var _gas_t := 0.0
var _pump_t := 0.0
var _rng := RandomNumberGenerator.new()
## Насос -> время игры, до которого он не ищет воду (вокруг было сухо).
var _pump_dry := {}
var _warned := {}
var _temp_memo := {}
var _temp_t := 0.0


func _init(p_colony: Colony) -> void:
	colony = p_colony
	world = p_colony.world
	_rng.seed = world.gen.world_seed + 777


func update(dt: float) -> void:
	_temp_t += dt
	if _temp_t >= 1.0:
		_temp_t = 0.0
		_temp_memo.clear()
	_water_t += dt
	while _water_t >= WATER_STEP:
		_water_t -= WATER_STEP
		_flow(Mat.WATER)
	_lava_t += dt
	while _lava_t >= LAVA_STEP:
		_lava_t -= LAVA_STEP
		_flow(Mat.MAGMA)
		_cool_lava(LAVA_STEP)
	_gas_t += dt
	while _gas_t >= GAS_STEP:
		_gas_t -= GAS_STEP
		_gas_tick()
	_settle_t += dt
	if _settle_t >= SETTLE_TIME:
		_settle_t = 0.0
		_settle()
	_pump_t += dt
	while _pump_t >= PUMP_TIME:
		_pump_t -= PUMP_TIME
		_pumps()
	for c in springs.keys():
		springs[c] += dt
		if springs[c] >= SPRING_TIME:
			springs[c] = 0.0
			_spring(c)


# --- Жидкости --------------------------------------------------------------------------

## Клетка c открылась: соседняя вода или лава может потечь, пласт — засочиться, газ — выйти.
func on_opened(c: Vector2i) -> void:
	for d in [UP, DOWN, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1)]:
		var n: Vector2i = c + d
		var m := world.get_mat(n.x, n.y)
		if Mat.is_fluid(m):
			active[n] = true
		elif m == Mat.AQUIFER and not springs.has(n):
			springs[n] = SPRING_TIME * 0.5
		elif SEEP_RESERVE.has(m) and not seeps.has(n):
			seeps[n] = SEEP_RESERVE[m]
		if m == Mat.GAS_POCKET:
			pockets[n] = POCKET_MEMORY


## Газовый карман вскрыт: метан выходит в выработку.
func release_gas(c: Vector2i) -> void:
	gas[c] = gas.get(c, 0.0) + GAS_PER_POCKET
	pockets[c] = POCKET_MEMORY


## Рядом вскрытый газовый карман (или пласт кармана ещё сочится).
func near_pocket(r: Rect2i) -> bool:
	var area := r.grow(POCKET_RADIUS)
	for c: Vector2i in pockets:
		if area.has_point(c):
			return true
	return false


func _accepts(c: Vector2i) -> bool:
	return world.get_mat(c.x, c.y) == Mat.AIR


func _flow(kind: int) -> void:
	var cells: Array = []
	var gone: Array = []
	for c in active:
		var m := world.get_mat(c.x, c.y)
		if m == kind:
			cells.append(c)
		elif m != Mat.WATER and m != Mat.MAGMA:
			gone.append(c)
	# Жидкость отсюда ушла (стекла, откачали, застыла) — клетку больше не перебираем (копились
	# тысячами и перебирались шесть раз в секунду вечно).
	for c in gone:
		active.erase(c)
	if cells.is_empty():
		return
	for c in cells:
		active.erase(c)
	# Снизу вверх: нижние клетки освобождают место верхним за один шаг.
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var moves := 0
	var level_seen := {}
	var levels := 0
	var level_bfs := 0
	for c: Vector2i in cells:
		if moves >= MAX_MOVES:
			active[c] = true
			continue
		if world.get_mat(c.x, c.y) != kind:
			continue
		var to = _target(c, kind)
		# Сообщающиеся сосуды: если водоёму, где лежит c, есть куда опуститься (пустая клетка
		# рядом с ним ниже его верха), верхняя вода уходит туда (раньше вода в тоннеле стояла
		# «горой» выше, чем в пещере, с которой он соединён).
		if to == null and kind == Mat.WATER and levels < LEVEL_MOVES and level_bfs < 2 and not level_seen.has(c) \
				and world.get_mat(c.x, c.y - 1) != Mat.WATER and colony.game_time >= float(_level_quiet.get(c, -1.0)):
			level_bfs += 1
			var pairs: Array = _level(c, level_seen, LEVEL_MOVES - levels)
			for pr in pairs:
				levels += 1
				moves += 1
				_move(pr[0], pr[1], kind)
			if not pairs.is_empty():
				active[c] = true
			continue
		if to == null:
			continue
		moves += 1
		_move(c, to, kind)


## Сколько клеток водоёма обходим, выравнивая уровень, и сколько капель переносим за шаг.
const LEVEL_CAP := 1200
const LEVEL_MOVES := 12
const LEVEL_QUIET := 5.0
var _level_quiet := {}


## Водоём, где лежит c: пары [верхняя вода, пустая клетка рядом с ним ниже неё] — самые
## верхние к самым нижним, не больше limit за раз (один обход на пачку). Пар нет — водоём
## ровный: его клетки — в seen и LEVEL_QUIET секунд не перепроверяем.
func _level(c: Vector2i, seen: Dictionary, limit: int) -> Array:
	var queue: Array[Vector2i] = [c]
	var body := {c: true}
	var frees := {}
	var head := 0
	while head < queue.size() and queue.size() < LEVEL_CAP:
		var w := queue[head]
		head += 1
		for d in DIRS4:
			var n := w + d
			if body.has(n):
				continue
			var m := world.get_mat(n.x, n.y)
			if m == Mat.WATER:
				body[n] = true
				queue.append(n)
			elif d != UP and not frees.has(n) and _accepts(n):
				frees[n] = true
	var out := []
	if not frees.is_empty():
		var low: Array = frees.keys()
		low.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
		var tops: Array = queue.filter(func(w: Vector2i) -> bool: return world.get_mat(w.x, w.y - 1) != Mat.WATER)
		tops.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
		for i in mini(limit, mini(low.size(), tops.size())):
			if low[i].y <= tops[i].y:
				break
			out.append([tops[i], low[i]])
	if out.is_empty():
		seen.merge(body)
		var until := colony.game_time + LEVEL_QUIET
		for b in body:
			_level_quiet[b] = until
		if _level_quiet.size() > 50000:
			_level_quiet.clear()
	return out


## Куда течь: вниз; вбок — если там можно пролиться ниже или сверху давит столб.
func _target(c: Vector2i, kind: int) -> Variant:
	if _accepts(c + DOWN):
		return c + DOWN
	var order: Array[Vector2i] = SIDES.duplicate()
	if _rng.randf() < 0.5:
		order.reverse()
	# Вода ищет нижнюю точку: течёт вбок, если по ряду дальше есть куда пролиться вниз
	# (иначе после откачки или на склоне пещеры она стояла бы лесенкой или стенкой).
	for d in order:
		if _drop_ahead(c, d):
			return c + d
	if world.get_mat(c.x, c.y - 1) == kind:
		for d in order:
			if _accepts(c + d):
				return c + d
	return null


## Подземная вода, застывшая лесенкой или стенкой (старые сохранения, вода у края откачки):
## понемногу обходим загруженные чанки и будим воду, у которой сбоку или снизу пусто.
const SETTLE_TIME := 0.5
const SETTLE_CHUNKS := 1
var _settle_t := 0.0
var _settle_keys: Array = []


func _settle() -> void:
	if _settle_keys.is_empty():
		_settle_keys = world.chunks.keys()
	for k in SETTLE_CHUNKS:
		if _settle_keys.is_empty():
			return
		var key: Vector2i = _settle_keys.pop_back()
		var ch: ChunkData = world.chunks.get(key)
		# Без воды в куске — пропускаем сразу (проверка всего куска — встроенная, быстрая).
		if ch == null or not (ch.mat.has(Mat.WATER) or (ch.has_fluid_overlay() and ch.fluid.has(Mat.WATER))):
			continue
		for i in ch.mat.size():
			if ch.effective(i) != Mat.WATER:
				continue
			var c := Vector2i(key.x * ChunkData.SIZE + (i & ChunkData.MASK), key.y * ChunkData.SIZE + (i >> ChunkData.SHIFT))
			if c.y <= world.gen.surface_y(c.x) or active.has(c):
				continue
			if _accepts(c + DOWN) or _accepts(c + SIDES[0]) or _accepts(c + SIDES[1]):
				active[c] = true


## Как далеко вода «видит» по ряду, куда можно стечь.
const FLOW_REACH := 24


## По ряду в сторону d — пустые клетки, и за ними (не дальше FLOW_REACH) есть куда упасть.
func _drop_ahead(c: Vector2i, d: Vector2i) -> bool:
	var t := c
	for i in FLOW_REACH:
		t += d
		if not _accepts(t):
			return false
		if _accepts(t + DOWN):
			return true
	return false


func _move(from: Vector2i, to: Vector2i, kind: int) -> void:
	world.clear_fluid(from.x, from.y)
	world.set_fluid(to.x, to.y, kind)
	if kind == Mat.MAGMA:
		lava_still.erase(from)
		lava_still[to] = 0.0
	# Сверху и сбоку жидкость может стечь в освободившуюся клетку.
	for d in [UP, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1)]:
		var n: Vector2i = from + d
		if Mat.is_fluid(world.get_mat(n.x, n.y)):
			active[n] = true
	active[to] = true
	# Пустота, откуда ушла жидкость, — для осыпей и сводов как свежая выработка.
	colony.physics.on_opened(from)
	_entered(to, kind)


## Жидкость пришла в клетку: реакции, постройки, гаврики.
func _entered(c: Vector2i, kind: int) -> void:
	for d in DIRS4:
		var n := c + d
		var m := world.get_mat(n.x, n.y)
		if kind == Mat.MAGMA and m == Mat.WATER:
			_quench(c, n)
			return
		if kind == Mat.WATER and m == Mat.MAGMA:
			_quench(n, c)
			return
	var pid: int = colony.interior.get(c, 0)
	if pid != 0:
		var p := colony.project_by_id(pid)
		if p != null:
			if kind == Mat.MAGMA:
				colony.collapse(p, "сгорела в лаве")
			else:
				colony.on_flooded(p, c)
	if kind == Mat.MAGMA:
		for u: Unit in colony.units.duplicate():
			var uc := u.cell()
			if uc == c or uc + UP == c:
				colony.injure(u, 200.0, "попал(а) в лаву")
		_warn_once("lava%d" % (c.y / 32), "КАТАСТРОФА: лава течёт в выработки на глубине %d м! Уходите, вода её остудит" % (
			c.y - world.gen.surface_y(c.x)), "danger", c)
	else:
		var p := colony.project_at(c)
		if p != null and (p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD):
			colony._check_liquids(p)


## Лава встретила воду: лава застывает камнем, вода уходит паром.
func _quench(lava: Vector2i, water: Vector2i) -> void:
	world.set_material(lava.x, lava.y, Mat.BASALT)
	lava_still.erase(lava)
	world.clear_fluid(water.x, water.y)
	colony.physics.on_opened(water)
	for d in DIRS4:
		for c in [lava + d, water + d]:
			if Mat.is_fluid(world.get_mat(c.x, c.y)):
				active[c] = true
	_warn_once("steam", "Лава встретила воду: шипит пар, лава застывает базальтом", "warning")


func _cool_lava(dt: float) -> void:
	for c in lava_still.keys():
		if world.get_mat(c.x, c.y) != Mat.MAGMA:
			lava_still.erase(c)
			continue
		if active.has(c):
			lava_still[c] = 0.0
			continue
		lava_still[c] += dt
		if lava_still[c] >= LAVA_COOL:
			lava_still.erase(c)
			world.set_material(c.x, c.y, Mat.BASALT)


## Водоносный пласт сочится в соседнюю пустую клетку (пока ей есть куда течь).
func _spring(c: Vector2i) -> void:
	if world.get_mat(c.x, c.y) != Mat.AQUIFER:
		springs.erase(c)
		return
	for d in [DOWN, Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = c + d
		if _accepts(n):
			world.set_fluid(n.x, n.y, Mat.WATER)
			active[n] = true
			_warn_once("spring%d,%d" % [c.x / 16, c.y / 16], "Водоносный пласт сочится водой (глубина %d м) — нужен насос" % (
				c.y - world.gen.surface_y(c.x)), "warning", c)
			return
	# Вокруг уже вода или порода — пласт затих.
	var open := false
	for d in DIRS4:
		var n := c + d
		if world.is_open(n.x, n.y) or world.get_mat(n.x, n.y) == Mat.WATER:
			open = true
	if not open:
		springs.erase(c)


## Насосы откачивают воду: по клетке с поверхности ближайшего затопления («Дренаж» — по две).
func _pumps() -> void:
	for i in (2 if colony.research.has("drainage") else 1):
		_pump_once()


func _pump_once() -> void:
	for p in colony.rooms_of(RoomType.PUMP):
		if p.paused:
			continue
		# Воды вокруг не было — смотрим снова не сразу: обзор зоны (до 81×81 клеток) дорогой.
		if float(_pump_dry.get(p.id, 0.0)) > colony.game_time:
			continue
		var center := p.rect.get_center()
		var best = null
		var best_d := 1 << 30
		var pr := RoomType.effect_radius(p)
		var surf := PackedInt32Array()
		for x in range(center.x - pr, center.x + pr + 1):
			surf.append(world.gen.surface_y(x))
		# Видимую воду, ближайшую к насосной (раньше — первую сверху, хоть и скрытую в
		# породе: насос минутами осушал невидимую полость, а пруд под ним стоял).
		# Смотрим только куски карты (32×32), где вода вообще есть, от ближних к дальним, и
		# останавливаемся, когда дальше ближе найденного не будет (раньше обходили квадрат до
		# 81×81 клеток — у сухой насосной кадр до 60 мс).
		var area := Rect2i(center - Vector2i(pr, pr), Vector2i(2 * pr + 1, 2 * pr + 1))
		var cand := []
		for ky in range(area.position.y >> ChunkData.SHIFT, ((area.end.y - 1) >> ChunkData.SHIFT) + 1):
			for kx in range(area.position.x >> ChunkData.SHIFT, ((area.end.x - 1) >> ChunkData.SHIFT) + 1):
				var ch: ChunkData = world.chunks.get(Vector2i(kx, ky))
				if ch == null or not (ch.mat.has(Mat.WATER) or (ch.has_fluid_overlay() and ch.fluid.has(Mat.WATER))):
					continue
				var r := Rect2i(kx << ChunkData.SHIFT, ky << ChunkData.SHIFT, ChunkData.SIZE, ChunkData.SIZE).intersection(area)
				var nx := clampi(center.x, r.position.x, r.end.x - 1)
				var ny := clampi(center.y, r.position.y, r.end.y - 1)
				cand.append([absi(nx - center.x) + absi(ny - center.y), r])
		cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for e in cand:
			if int(e[0]) >= best_d:
				break
			var r: Rect2i = e[1]
			# Только клетки с водой (их ищет движок, а не перебор всего куска 32×32), в том же
			# порядке — по рядам сверху вниз, в ряду слева направо.
			var base := Vector2i(r.position.x & ~ChunkData.MASK, r.position.y & ~ChunkData.MASK)
			for i in _water_idx(world.chunks[Vector2i(r.position.x >> ChunkData.SHIFT, r.position.y >> ChunkData.SHIFT)]):
				var x := base.x + (i & ChunkData.MASK)
				var y := base.y + (i >> ChunkData.SHIFT)
				if not r.has_point(Vector2i(x, y)):
					continue
				var d := absi(x - center.x) + absi(y - center.y)
				if d >= best_d or surf[x - center.x + pr] > y:
					continue # озёра на поверхности не откачиваем
				if world.get_mat(x, y - 1) != Mat.WATER and world.is_revealed(x, y):
					best_d = d
					best = Vector2i(x, y)
		if best == null:
			_pump_dry[p.id] = colony.game_time + PUMP_DRY_WAIT
		if best != null:
			world.clear_fluid(best.x, best.y)
			# С энергией насос качает вдвое быстрее.
			if colony.powered() and colony.power_ratio >= 0.5:
				var below: Vector2i = best + DOWN
				if world.get_mat(below.x, below.y) == Mat.WATER:
					world.clear_fluid(below.x, below.y)
			for d in DIRS4:
				var n: Vector2i = best + d
				if world.get_mat(n.x, n.y) == Mat.WATER:
					active[n] = true


## Номера клеток куска с водой (природной или натёкшей), по возрастанию.
func _water_idx(ch: ChunkData) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := ch.mat.find(Mat.WATER)
	while i != -1:
		if ch.flags[i] & ChunkData.F_DUG == 0:
			out.append(i)
		i = ch.mat.find(Mat.WATER, i + 1)
	if ch.has_fluid_overlay():
		var overlay := false
		i = ch.fluid.find(Mat.WATER)
		while i != -1:
			if ch.flags[i] & ChunkData.F_DUG and ch.flags[i] & ChunkData.F_FLUID:
				out.append(i)
				overlay = true
			i = ch.fluid.find(Mat.WATER, i + 1)
		if overlay:
			out.sort()
	return out


# --- Газ ------------------------------------------------------------------------------

func _open_for_gas(c: Vector2i) -> bool:
	return world.get_mat(c.x, c.y) == Mat.AIR


## Вскрытые пласты понемногу выпускают метан в соседнюю выработку.
func _seep_tick() -> void:
	for c: Vector2i in seeps.keys():
		var m := world.get_mat(c.x, c.y)
		if not SEEP_RESERVE.has(m) or seeps[c] <= 0.0:
			seeps.erase(c)
			continue
		var out = null
		for d in DIRS4:
			if _open_for_gas(c + d):
				out = c + d
				break
		if out == null:
			continue
		var amount := minf(SEEP_RATE * GAS_STEP, seeps[c])
		seeps[c] -= amount
		gas[out] = gas.get(out, 0.0) + amount


func _gas_tick() -> void:
	for c: Vector2i in pockets.keys():
		# Пока карман сочится — помним; выдохся — забываем через POCKET_MEMORY.
		if seeps.has(c) and world.get_mat(c.x, c.y) == Mat.GAS_POCKET:
			pockets[c] = POCKET_MEMORY
		else:
			pockets[c] -= GAS_STEP
			if pockets[c] <= 0.0:
				pockets.erase(c)
	_seep_tick()
	_gas_alarm()
	if gas.is_empty():
		return
	var next := {}
	# Проверки клеток и высота поверхности — по разу на шаг (раньше на каждую клетку газа
	# по шесть раз, с шумом рельефа: тысяча клеток метана стоила 20 мс в секунду).
	var open := {}
	var surf := {}
	# Самое частое в расчёте газа — без вызовов функций и временных массивов.
	for c: Vector2i in gas:
		var g: float = gas[c]
		var sy = surf.get(c.x)
		if sy == null:
			sy = world.gen.surface_y(c.x)
			surf[c.x] = sy
		# Над землёй газ уходит в небо.
		if c.y < int(sy):
			continue
		var o = open.get(c)
		if o == null:
			o = world.get_mat(c.x, c.y) == Mat.AIR
			open[c] = o
		if not o:
			continue
		# Соседи в порядке DIRS4; вверх — с весом 2 (метан легче воздуха: больше уходит вверх).
		var weights := 0.0
		var ok := [false, false, false, false]
		for k in 4:
			var n: Vector2i = c + DIRS4[k]
			var v = open.get(n)
			if v == null:
				v = world.get_mat(n.x, n.y) == Mat.AIR
				open[n] = v
			if v:
				ok[k] = true
				weights += 2.0 if n.y < c.y else 1.0
		if weights == 0.0:
			next[c] = next.get(c, 0.0) + g
			continue
		var keep := g * 0.4
		var share := g - keep
		next[c] = next.get(c, 0.0) + keep
		for k in 4:
			if ok[k]:
				var t: Vector2i = c + DIRS4[k]
				next[t] = next.get(t, 0.0) + share * (2.0 if t.y < c.y else 1.0) / weights
	# Дегазация собирает метан — это топливо для газового генератора и котлов.
	# Зоны дегазаций — один проход по облаку (раньше — по облаку на каждую дегазацию).
	var zones := []
	for p in colony.rooms_of(RoomType.DEGAS):
		if p.paused:
			continue
		# Бак полон — газ всё равно откачивают (выработки чистые), лишний выпускают наружу.
		var dr := RoomType.effect_radius(p)
		zones.append([Rect2i(p.rect.get_center() - Vector2i(dr, dr), Vector2i(dr * 2 + 1, dr * 2 + 1)), colony.room_free(p, "methane") > 0])
	if not zones.is_empty():
		var gain := 2.0 if colony.research.has("gas_collector") else 1.0
		for c: Vector2i in next:
			for z in zones:
				if (z[0] as Rect2i).has_point(c):
					var take: float = next[c] * DEGAS_TAKE
					next[c] -= take
					# «Газосборник» — вдвое больше метана с того же газа.
					if z[1]:
						_captured += take * gain
	while _captured >= 1.0:
		_captured -= 1.0
		colony._add("methane", 1)
	gas.clear()
	for c in next:
		if next[c] >= GAS_MIN:
			gas[c] = next[c]


func gas_at(c: Vector2i) -> float:
	return gas.get(c, 0.0)


## Больше всего метана в прямоугольнике.
func gas_in(r: Rect2i) -> float:
	var g := 0.0
	if gas.is_empty():
		return g
	# Длинная выработка (ствол лифта на сотни метров) — дешевле пройти по облаку газа.
	if r.get_area() > gas.size():
		for c: Vector2i in gas:
			if r.has_point(c):
				g = maxf(g, gas[c])
		return g
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g = maxf(g, gas.get(Vector2i(x, y), 0.0))
	return g


## Газовая тревога: где метана много, работы встают; ушёл газ — продолжают сами.
## Игрок может приказать работать в газе — тогда взрыв на его совести.
func _gas_alarm() -> void:
	for p: Project in colony.projects:
		if p.is_water_structure() or p.purpose == RoomType.DEGAS or p.purpose == RoomType.VENT:
			continue
		# Машина (бур, бур-лифт, ход бура) копает без искры — газ ей безразличен.
		if colony.is_machine(p):
			if p.hazard_pending == "methane":
				p.paused = false
				p.hazard_pending = ""
				p.blocked = ""
			continue
		var g := gas_in(p.rect.grow(1))
		# Искру даёт кирка: копка стоит уже при тревоге, а в противогазах — только в метановом
		# облаке (там искра взрывает). Готовые комнаты — когда газом опасно дышать.
		var masks := colony.research.has("gas_masks")
		var digging := p.phase == Project.Phase.DIG
		var stop_at := (GAS_EXPLOSIVE if masks else GAS_ALARM) if digging else GAS_CHOKE * (2.0 if masks else 1.0)
		# Взрыв — только у газового кармана. В остальном метане искра не страшна, но копка
		# встаёт, когда газа столько, что тяжело дышать (иначе он копился до удушья и
		# расходился по базе): без противогазов — с прежнего порога, в противогазах — у удушья.
		var pocket := near_pocket(p.rect)
		if digging and not pocket:
			stop_at = GAS_CHOKE * 2.0 * 0.8 if masks else GAS_EXPLOSIVE
		# Геолог чуял газ в породе, а дегазация рядом или есть противогазы — копают дальше сами.
		if p.hazard_pending == "gas" and p.paused and (masks or colony.degas_covers(p.rect.get_center())):
			p.hazard_ack.append("gas")
			p.hazard_pending = ""
			p.paused = false
			p.blocked = ""
			colony._log("%s: %s, работы продолжаются" % [p.title(), "в противогазах газ не страшен" if masks else "рядом дегазация — газ из породы она уберёт"], "info", p.rect.get_center())
			continue
		if p.hazard_pending == "methane":
			if g < (GAS_ALARM if masks else GAS_CLEAR) or (digging and not near_pocket(p.rect) and g < stop_at):
				p.paused = false
				p.hazard_pending = ""
				p.blocked = ""
				if colony.game_time - float(colony._gas_logged.get(p.id, -1000.0)) > Colony.GAS_LOG_EVERY:
					colony._log("%s: метан ушёл, работы возобновлены" % p.title(), "info", p.rect.get_center())
		elif p.hazard_ack.has("methane"):
			if g < GAS_CLEAR:
				p.hazard_ack.erase("methane")
		elif g >= stop_at and not p.paused:
			colony.gas_stop(p, pocket or not digging)


## Искра от кирки в облаке метана: взрыв.
func spark(c: Vector2i) -> void:
	var g := maxf(gas_at(c), gas_at(c + UP))
	if g < GAS_EXPLOSIVE or _rng.randf() > 0.02 or not near_pocket(Rect2i(c, Vector2i.ONE)):
		return
	explode(c)


func explode(c: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for y in range(c.y - 3, c.y + 4):
		for x in range(c.x - 3, c.x + 4):
			var n := Vector2i(x, y)
			gas.erase(n)
			cells.append(n)
	colony._log("ВЗРЫВ МЕТАНА на глубине %d м! Нужна дегазация" % (c.y - world.gen.surface_y(c.x)), "danger", c)
	for u: Unit in colony.units.duplicate():
		if u.cell().distance_to(c) <= 4.0:
			colony.injure(u, 55.0, "взрыв метана")
	var hit := {}
	for n in cells:
		if n.distance_to(c) > 2.5:
			continue
		var pid: int = colony.interior.get(n, 0)
		if pid != 0 and not hit.has(pid):
			hit[pid] = true
			var p := colony.project_by_id(pid)
			if p != null:
				colony.collapse(p, "разрушена взрывом")
	colony.physics.check_area(cells)


# --- Жара -------------------------------------------------------------------------------

## Температура в клетке: глубина, лава рядом, охлаждение вентиляцией.
## Запоминаем на секунду: гаврики стоят на месте, а считать дорого.
func temperature(c: Vector2i) -> float:
	var v = _temp_memo.get(c)
	if v == null:
		v = _temperature(c)
		_temp_memo[c] = v
	return v


## Что может гореть: готовые очаги, генераторы, корабль (и всё, что горит сейчас) — список
## обновляется вместе с памятью температур; горит ли — смотрим каждый раз (раньше на каждую
## клетку перебирались все постройки).
var _heat_src = null
const BURNERS := [RoomType.HEARTH, RoomType.SHIP]


func _heat_sources() -> Array:
	if _heat_src == null or _temp_memo.is_empty():
		_heat_src = []
		for p in colony.projects:
			if p.burning or (p.phase == Project.Phase.DONE and (BURNERS.has(p.purpose) or RoomType.GENERATORS.has(p.purpose))):
				_heat_src.append(p)
	return _heat_src


func _temperature(c: Vector2i) -> float:
	# В корабле климат держит его реактор.
	if colony.ship_at(c) != null:
		return SHIP_TEMP
	var t := world.gen.temperature(c.y, world.gen.surface_y(c.x), colony.season_delta())
	# Тепло — только от огня: горящий очаг или генератор греют всё вокруг. Несколько очагов
	# рядом складываются (два — вдвое теплее), но в жару не нагреют: огонь греет не выше +30 °C.
	var fire := 0.0
	for p: Project in _heat_sources():
		if not p.burning or p.phase != Project.Phase.DONE:
			continue
		# Расстояние от стен комнаты (внутри — 0): рядом полное тепло, дальше плавно слабеет.
		var r := p.rect
		var dx := maxi(0, maxi(r.position.x - c.x, c.x - (r.end.x - 1)))
		var dy := maxi(0, maxi(r.position.y - c.y, c.y - (r.end.y - 1)))
		var d := maxi(dx, dy)
		var zone := RoomType.heat_zone(p, colony.research.has("insulation"))
		if d <= zone.y:
			fire += Colony.HEAT * clampf(float(zone.y + 1 - d) / (zone.y + 1 - zone.x), 0.0, 1.0)
	if fire > 0.0:
		t = minf(t + fire, maxf(t, FIRE_MAX_TEMP))
	if c.y >= world.gen.surface_y(c.x) - 2:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if world.get_mat(c.x + dx, c.y + dy) == Mat.MAGMA:
					t = maxf(t, 1100.0 / (1.0 + Vector2(dx, dy).length() * 2.0))
	for p in colony.rooms_of(RoomType.VENT):
		var center := p.rect.get_center()
		var vr := RoomType.effect_radius(p)
		if absi(c.x - center.x) <= vr and absi(c.y - center.y) <= vr:
			# Вентиляция сбивает жару, но не ниже VENT_MIN_TEMP (раньше на Венере с «Климат-контролем»
			# в недрах уходило в минус, и фермы мёрзли).
			var cool := VENT_COOLING * (1.0 + colony.power_ratio if colony.powered() else 1.0) * (2.0 if colony.research.has("climate") else 1.0)
			t = maxf(t - cool, minf(t, VENT_MIN_TEMP))
			break
	return t


## Выше какой температуры гаврику жарко: красным — выше, с кондиционированием — на 15 °C.
func heat_limit(u: Unit) -> float:
	return HOT + (15.0 if colony.research.has("climate") else 0.0) + (u.stat("heat") - 1.0) * 30.0


## Воздействие стихий на гаврика за dt секунд.
func affect_unit(u: Unit, dt: float) -> void:
	# Супер-гаврику стихии не страшны — умирает только от старости.
	if u.invulnerable():
		return
	var c := u.cell()
	var head := c + UP
	if world.get_mat(head.x, head.y) == Mat.WATER:
		if u.ability("underwater") != true:
			u.health -= 6.0 * dt
		_hurt_check(u, "утонул(а)")
	var g := maxf(gas_at(c), gas_at(head))
	var choke := GAS_CHOKE * (2.0 if colony.research.has("gas_masks") else 1.0)
	# У газового кармана уходят от взрывоопасного метана; любой газ, которым уже трудно
	# дышать, — тоже покидают (иначе задыхались в метане из угля).
	if (g >= (GAS_ALARM if u.ability("flee_early") == true else GAS_EXPLOSIVE) and near_pocket(Rect2i(c, Vector2i.ONE))) \
			or g >= choke * 0.8:
		colony.flee_gas(u)
	if g >= choke:
		u.health -= 3.0 * dt
		_hurt_check(u, "задохнулся(лась) метаном")
	var t := temperature(c)
	var hot := heat_limit(u)
	if t > hot:
		u.health -= minf(20.0, (t - hot) / 8.0) * dt
		_warn_once("hot%d" % u.id, "%s: невыносимая жара (%d °C) — нужна вентиляция" % [u.name, roundi(t)], "warning", u.cell())
		_hurt_check(u, "погиб(ла) от жары")
	var cold := Colony.cold_limit(u)
	if t < cold:
		# −8 °C без тепла: около 0,2 здоровья в секунду — сон в холодном доме не спасает.
		u.health -= minf(2.0, (cold - t) / 40.0) * dt
		_warn_once("cold%d" % u.id, "%s мёрзнет (%d °C) — нужно тепло: очаг рядом" % [u.name, roundi(t)], "warning", u.cell())
		_hurt_check(u, "замёрз(ла)")
	var o2 := 1.0 if colony.ship_at(c) != null or colony.sky_clear(c.x) else world.gen.oxygen_ratio(c.y, world.gen.surface_y(c.x))
	if o2 < 0.55:
		u.health -= (0.55 - o2) * 10.0 * dt
		_hurt_check(u, "задохнулся(лась) на высоте")


func _hurt_check(u: Unit, why: String) -> void:
	if u.health <= 0.0:
		colony.injure(u, 1.0, why)


func _warn_once(key: String, text: String, kind: String, at: Variant = null) -> void:
	var now := Time.get_ticks_msec()
	if _warned.has(key) and now - int(_warned[key]) < 60000:
		return
	_warned[key] = now
	colony._log(text, kind, at)


# --- Сохранение -------------------------------------------------------------------------

static func _cells(d: Dictionary) -> Array:
	var out := []
	for c: Vector2i in d:
		out.append([c.x, c.y, d[c]])
	return out


func to_dict() -> Dictionary:
	return {"active": _cells(active), "lava": _cells(lava_still), "springs": _cells(springs), "gas": _cells(gas),
		"seeps": _cells(seeps), "pockets": _cells(pockets), "captured": _captured}


func load_dict(d: Dictionary) -> void:
	for e in d.get("active", []):
		active[Vector2i(int(e[0]), int(e[1]))] = true
	for e in d.get("lava", []):
		lava_still[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("springs", []):
		springs[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("gas", []):
		gas[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("seeps", []):
		seeps[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("pockets", []):
		pockets[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	# Старое сохранение: карманы, которые ещё сочатся, — из пластов.
	for c: Vector2i in seeps:
		if world.get_mat(c.x, c.y) == Mat.GAS_POCKET:
			pockets[c] = POCKET_MEMORY
	_captured = float(d.get("captured", 0.0))
