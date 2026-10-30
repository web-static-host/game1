class_name Pathing
extends RefCounted
## Передвижение гавриков в разрезе мира.
## - ходят по открытым клеткам, под ногами — опора, над головой — свободно;
## - в выкопанных клетках и готовых постройках есть лестницы: можно лезть вверх/вниз;
## - по рельефу шагают на ступеньку в 1 м, залезают на уступ в 2 м;
## - в озёра не заходят: водоём переходят только по мосту; подтопленную выработку
##   переплывают по поверхности (медленно); упавший в озеро выплывает к берегу.

## Обход ограничен числом клеток и расстоянием по горизонтали; по вертикали — без предела,
## чтобы с поверхности доходили до забоя на любой глубине (и обратно — к складу и в дом).
const MAX_NODES := 6000
const MAX_RADIUS := 140
const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)

var world: WorldData
## Клетки готовых построек: Vector2i -> id проекта (там есть пол и лестницы).
var interior: Dictionary
## Клетки комнат: в комнатах ходят по полу, лестниц там нет.
var room_cells: Dictionary
## Настил мостов и пристаней: по нему ходят над водой.
var deck: Dictionary
## Кэш обходов: старт -> [parents, dist]. Сбрасывается, когда меняется порода или постройки,
## и раз в CACHE_TIME секунд.
## Клетки с лестницей и клетки идущих строек (леса) — их ведёт колония.
var ladders := {}
var sites := {}
## Крепь шахты под ногами: шахта над шахтой — ходят по балкам нижней.
var floors := {}
## Меняется, когда меняются лестницы или леса: старые пути не годятся.
var climb_rev := 0
var _cache := {}
var _cache_key := []
var _cache_age := 0.0
## Запомненные node() и passable() клеток: изменённые клетки мира (world.changed) сбрасывают
## их точечно, постройки — целиком; на всякий случай — целиком раз в MEMO_TIME секунд.
var _node_memo := {}
var _pass_memo := {}
## Запомненные соседи клетки (neighbors) — сбрасываются так же; сосед зависит от клеток
## до 2 м вбок и 3 м вверх-вниз.
var _nbr_memo := {}
var _memo_age := 0.0
const CACHE_TIME := 8.0
const MEMO_TIME := 300.0


func _init(p_world: WorldData, p_interior: Dictionary, p_rooms: Dictionary, p_deck: Dictionary) -> void:
	world = p_world
	interior = p_interior
	room_cells = p_rooms
	deck = p_deck


## Можно находиться в клетке: пусто или вода (вброд).
func passable(c: Vector2i) -> bool:
	return world.is_open(c.x, c.y) or (world.get_mat(c.x, c.y) == Mat.WATER and world.is_revealed(c.x, c.y))


## Лазают только по лестницам: в вертикальных тоннелях, у стен комнат (ladders) и по лесам
## идущей стройки (sites — её пустые клетки, в том числе пещера на пути). По готовым шахтам, горизонтальным тоннелям
## и пустотам после обвала — только по полу.
func climbable(c: Vector2i) -> bool:
	if room_cells.has(c):
		return false
	if ladders.has(c):
		return true
	if interior.has(c):
		return false
	# Пустая клетка стройки — выкопанная или естественная пещера, через которую идёт ствол.
	return sites.has(c) and world.get_mat(c.x, c.y) == Mat.AIR


func solid(c: Vector2i) -> bool:
	return Mat.is_solid(world.get_mat(c.x, c.y))


## Можно стоять ногами в клетке (без учёта головы).
func standable(c: Vector2i) -> bool:
	if not passable(c):
		return false
	if deck.has(c) or floors.has(c):
		return true
	if world.get_mat(c.x, c.y) == Mat.WATER:
		# В озёра не заходят (вода выше земли) — водоём переходят только по мосту.
		if c.y < world.gen.surface_y(c.x):
			return false
		# Подтопленную выработку переплывают: тело в воде, голова над водой.
		if world.is_open(c.x, c.y - 1):
			return true
	var below := c + DOWN
	if solid(below) or climbable(c) or climbable(below):
		return true
	# Пол комнаты, стоящей на другой комнате: перекрытие держит.
	return room_cells.has(below) and room_cells[below] != room_cells.get(c, -1)


## Узел графа: можно стоять, голова не упирается и над водой.
func node(c: Vector2i) -> bool:
	# На безвоздушной планете на поверхность не выходят — только внутри построек.
	if world.gen.airless() and c.y < world.gen.surface_y(c.x) and not interior.has(c) and not room_cells.has(c):
		return false
	var h := c + UP
	return standable(c) and world.is_open(h.x, h.y)


func _node_m(c: Vector2i) -> bool:
	var v = _node_memo.get(c)
	if v == null:
		v = node(c)
		_node_memo[c] = v
	return v


func _pass_m(c: Vector2i) -> bool:
	var v = _pass_memo.get(c)
	if v == null:
		v = passable(c)
		_pass_memo[c] = v
	return v


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var memo = _nbr_memo.get(c)
	if memo != null:
		return memo
	var out := _neighbors(c)
	_nbr_memo[c] = out
	return out


func _neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# Сначала — вверх и вниз по лестнице: при равной длине пути лезут прямо, а не петляют.
	var on_ladder := climbable(c)
	var up := c + UP
	if on_ladder and _node_m(up):
		out.append(up)
	var down := c + DOWN
	if climbable(down) and _node_m(down):
		out.append(down)
	for dx in [-1, 1]:
		var side := c + Vector2i(dx, 0)
		if _node_m(side):
			out.append(side)
		else:
			var step_up := c + Vector2i(dx, -1)
			var ledge := c + Vector2i(dx, -2)
			if _pass_m(c + UP * 2) and _node_m(step_up):
				out.append(step_up)
			elif _pass_m(c + UP * 2) and _pass_m(c + UP * 3) and _node_m(ledge) and not climbable(ledge):
				# Уступ в 2 м — залезают (на лестницу так не прыгают: по ней лезут).
				out.append(ledge)
			var step_down := c + Vector2i(dx, 1)
			var drop := c + Vector2i(dx, 2)
			if _pass_m(side) and _node_m(step_down):
				out.append(step_down)
			elif not on_ladder and _pass_m(side) and _pass_m(side + DOWN) and _node_m(drop) and not climbable(drop):
				# Спрыгивают с уступа в 2 м (с лестницы и на лестницу — нет: по ней слезают).
				out.append(drop)
			# Щель в 1 клетку (осыпался песок, трещина) — перешагивают: иначе узкая трещина
			# отрезала бы полколонии.
			var over := c + Vector2i(dx * 2, 0)
			if not on_ladder and _pass_m(side) and _pass_m(side + UP) and not standable(side) and _node_m(over):
				out.append(over)
	return out


## Обход в ширину от start. Возвращает [parents: Dictionary, dist: Dictionary].
func explore(start: Vector2i) -> Array:
	sync()
	if _cache.has(start):
		return _cache[start]
	var out := _explore(start)
	_cache[start] = out
	return out


## Мир или постройки поменялись — забываем устаревшее (точечно, если менялась только порода).
func sync() -> void:
	_take_changes()
	var key := [world.revision, interior.size(), room_cells.size(), deck.size(), climb_rev]
	# Изменилась только порода (копают, течёт вода) или лестницы и леса — проверки клеток уже
	# сброшены рядом с изменёнными (forget), обходы не выбрасываем, а дообновляем на месте
	# (копают постоянно, и раньше кэш почти не работал: каждый поиск работы обходил колонию
	# заново). Комнаты и постройки — сбрасываем всё.
	var structural := _cache_key.size() != key.size() or key.slice(1, 4) != _cache_key.slice(1, 4)
	if structural:
		clear_cache()
	elif not _changed_cells.is_empty() or not _climb_cells.is_empty() or key[4] != _cache_key[4]:
		if _changed_cells.size() > PATCH_MAX or (key[4] != _cache_key[4] and _climb_cells.is_empty()):
			_cache.clear()
		else:
			_patch_cache()
	_changed_cells.clear()
	_climb_cells.clear()
	_cache_key = key


## Время идёт: старые обходы забываем.
func tick(dt: float) -> void:
	_cache_age += dt
	if _cache_age >= CACHE_TIME:
		_cache_age = 0.0
		# Обходы — заново; проверки клеток держим дольше: изменения мира сбрасывают их точечно.
		_cache.clear()
	_memo_age += dt
	if _memo_age >= MEMO_TIME:
		_memo_age = 0.0
		clear_cache()


## Клетки мира поменялись: проверки «можно стоять / пройти» рядом с ними забываем
## (клетка влияет на себя, на того, кто стоит над ней, и на голову того, кто под ней).
func _take_changes() -> void:
	if world.changed.is_empty():
		return
	if world.changed.size() >= 4096:
		_node_memo.clear()
		_pass_memo.clear()
		_nbr_memo.clear()
	else:
		for c in world.changed:
			_forget_cell(c)
	_changed_cells.append_array(world.changed)
	world.changed.clear()


## Лестницы, леса или настил поменялись в этих клетках: проверки рядом с ними забываем.
func forget(cells: Array) -> void:
	_climb_cells.append_array(cells)
	if cells.size() >= 4096:
		_node_memo.clear()
		_pass_memo.clear()
		_nbr_memo.clear()
		return
	for c in cells:
		_forget_cell(c)


func _forget_cell(c: Vector2i) -> void:
	for dy in [-1, 0, 1]:
		var n := c + Vector2i(0, dy)
		_node_memo.erase(n)
		_pass_memo.erase(n)
	if not _nbr_memo.is_empty():
		for dy in range(-3, 4):
			for dx in range(-2, 3):
				_nbr_memo.erase(c + Vector2i(dx, dy))


## --- Дообновление обходов ----------------------------------------------------------------
## Клетки, поменявшиеся с прошлой сверки: порода (копка, обвал) и лестницы/леса/полы.
var _changed_cells: Array = []
var _climb_cells: Array = []
## Больше изменений разом — проще обойти заново.
const PATCH_MAX := 400


## Сохранённые обходы правим на месте. Клетка рядом с изменением перестала быть узлом (вынули
## пол, засыпало, убрали лестницу) — обход выбрасываем: пути через неё больше нет. Иначе —
## дотягиваем расстояния от клеток обхода рядом с изменением: так в обход попадают только что
## открытые клетки и короткие пути через них (как при новом обходе).
func _patch_cache() -> void:
	if _cache.is_empty():
		return
	var zone := {}
	for c: Vector2i in _changed_cells + _climb_cells:
		for dy in range(-3, 4):
			for dx in range(-2, 3):
				zone[c + Vector2i(dx, dy)] = true
	var removed := {}
	for c: Vector2i in _climb_cells:
		removed[c] = true
	for start: Vector2i in _cache.keys():
		var entry: Array = _cache[start]
		var parents: Dictionary = entry[0]
		var dist: Dictionary = entry[1]
		var queue: Array[Vector2i] = []
		var broken := false
		for q: Vector2i in zone:
			if not dist.has(q):
				continue
			# Лестница или леса поменялись прямо в клетке обхода — пути через неё могли пропасть.
			if removed.has(q) or not _node_m(q):
				broken = true
				break
			queue.append(q)
		if broken or not node(start):
			_cache.erase(start)
			continue
		var lo := start.x - MAX_RADIUS
		var hi := start.x + MAX_RADIUS
		var head := 0
		while head < queue.size() and dist.size() < MAX_NODES:
			var c := queue[head]
			head += 1
			var d: int = dist[c] + 1
			for n: Vector2i in neighbors(c):
				if n.x < lo or n.x > hi:
					continue
				if dist.has(n) and int(dist[n]) <= d:
					continue
				parents[n] = c
				dist[n] = d
				queue.append(n)


func clear_cache() -> void:
	_cache.clear()
	_node_memo.clear()
	_pass_memo.clear()
	_nbr_memo.clear()


func _explore(start: Vector2i, cap := MAX_NODES) -> Array:
	sync()
	var parents := {start: start}
	var dist := {start: 0}
	if not node(start):
		return [parents, dist]
	var queue: Array[Vector2i] = [start]
	var head := 0
	var lo := start.x - MAX_RADIUS
	var hi := start.x + MAX_RADIUS
	# Самое горячее место игры: соседи — прямо из памяти, без лишних вызовов.
	while head < queue.size() and queue.size() < cap:
		var c: Vector2i = queue[head]
		head += 1
		var d: int = dist[c] + 1
		var nb = _nbr_memo.get(c)
		if nb == null:
			nb = neighbors(c)
		for n: Vector2i in nb:
			if dist.has(n) or n.x < lo or n.x > hi:
				continue
			parents[n] = c
			dist[n] = d
			queue.append(n)
	return [parents, dist]


## Обход сразу от многих стартов: куда может дойти хоть кто-то (без предела по горизонтали).
## Возвращает расстояние от ближайшего старта.
func explore_multi(starts: Array[Vector2i], cap: int) -> Dictionary:
	sync()
	var dist := {}
	var queue: Array[Vector2i] = []
	for st in starts:
		if not dist.has(st) and node(st):
			dist[st] = 0
			queue.append(st)
	var head := 0
	while head < queue.size() and queue.size() < cap:
		var c := queue[head]
		head += 1
		var d: int = dist[c] + 1
		for n in neighbors(c):
			if not dist.has(n):
				dist[n] = d
				queue.append(n)
	return dist


## Обход упёрся в предел: дальнее (глубокий забой в большой колонии) в него не попало.
static func truncated(dist: Dictionary) -> bool:
	return dist.size() >= MAX_NODES


## Прицельный поиск пути к любой из клеток goals (A*): для целей дальше, чем достаёт обход.
## Возвращает путь от старта (не включая его) до цели или пустой, если не нашёл за limit клеток.
func find_path(start: Vector2i, goals: Dictionary, limit := FAR_NODES) -> Array[Vector2i]:
	sync()
	var none: Array[Vector2i] = []
	if goals.is_empty() or not node(start):
		return none
	var box := Rect2i(goals.keys()[0], Vector2i.ONE)
	for g in goals:
		box = box.expand(g)
	box.size += Vector2i.ONE
	var parents := {start: start}
	var g_cost := {start: 0}
	# Двоичная куча: [оценка, клетка].
	var heap: Array = [[_h(start, box), start]]
	var closed := {}
	while not heap.is_empty() and closed.size() < limit:
		var c: Vector2i = _heap_pop(heap)[1]
		if closed.has(c):
			continue
		closed[c] = true
		if goals.has(c):
			return path_to(parents, c)
		var d: int = g_cost[c] + 1
		for n in neighbors(c):
			if closed.has(n) or (g_cost.has(n) and g_cost[n] <= d):
				continue
			g_cost[n] = d
			parents[n] = c
			_heap_push(heap, [d + _h(n, box), n])
	return none


## Сколько клеток перебирает прицельный поиск.
const FAR_NODES := 12000

## Путь «по времени», а не по числу клеток: по лестнице лезут медленно, в кабине лифта едут
## быстро (lift — клетки шахт пассажирских лифтов под током). Цены шага — в долях секунды:
## пешком 6, по лестнице 11, в кабине 2.
const COST_WALK := 6
const COST_CLIMB := 11
const COST_RIDE := 2


func timed_path(start: Vector2i, goal: Vector2i, lift: Dictionary, limit := 8000) -> Array[Vector2i]:
	sync()
	var none: Array[Vector2i] = []
	if not node(start) or not node(goal):
		return none
	var parents := {start: start}
	var g_cost := {start: 0}
	var heap: Array = [[_h(start, Rect2i(goal, Vector2i.ONE)) * COST_RIDE, start]]
	var closed := {}
	var box := Rect2i(goal, Vector2i.ONE)
	while not heap.is_empty() and closed.size() < limit:
		var c: Vector2i = _heap_pop(heap)[1]
		if closed.has(c):
			continue
		closed[c] = true
		if c == goal:
			return path_to(parents, c)
		for n in neighbors(c):
			if closed.has(n):
				continue
			var step := COST_WALK
			if n.x == c.x:
				step = COST_RIDE if lift.has(c) and lift.has(n) else COST_CLIMB
			var d: int = g_cost[c] + step
			if g_cost.has(n) and g_cost[n] <= d:
				continue
			g_cost[n] = d
			parents[n] = c
			_heap_push(heap, [d + _h(n, box) * COST_RIDE, n])
	return none


static func _h(c: Vector2i, box: Rect2i) -> int:
	var dx := maxi(0, maxi(box.position.x - c.x, c.x - (box.end.x - 1)))
	var dy := maxi(0, maxi(box.position.y - c.y, c.y - (box.end.y - 1)))
	return dx + dy


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var up := (i - 1) / 2
		if heap[up][0] <= item[0]:
			break
		heap[i] = heap[up]
		i = up
	heap[i] = item


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var r := l + 1
		var m := r if r < n and heap[r][0] < heap[l][0] else l
		if heap[m][0] >= last[0]:
			break
		heap[i] = heap[m]
		i = m
	heap[i] = last
	return top


## Путь от старта (не включая его) до target по результату explore().
static func path_to(parents: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not parents.has(target):
		return out
	var c := target
	while parents[c] != c:
		out.append(c)
		c = parents[c]
	out.reverse()
	return out
