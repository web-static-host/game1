class_name Pathing
extends RefCounted
## Передвижение жителей в разрезе мира.
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
## и раз в CACHE_TIME секунд (вода течёт, это не отслеживаем).
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
## Запомненные node() и passable() клеток — живут столько же, сколько кэш обходов.
var _node_memo := {}
var _pass_memo := {}
const CACHE_TIME := 2.0


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
	var out: Array[Vector2i] = []
	for dx in [-1, 1]:
		var side := c + Vector2i(dx, 0)
		if _node_m(side):
			out.append(side)
		else:
			var step_up := c + Vector2i(dx, -1)
			if _pass_m(c + UP * 2) and _node_m(step_up):
				out.append(step_up)
			elif _pass_m(c + UP * 2) and _pass_m(c + UP * 3) and _node_m(c + Vector2i(dx, -2)):
				# Уступ в 2 м — залезают.
				out.append(c + Vector2i(dx, -2))
			var step_down := c + Vector2i(dx, 1)
			if _pass_m(side) and _node_m(step_down):
				out.append(step_down)
			elif _pass_m(side) and _pass_m(side + DOWN) and _node_m(c + Vector2i(dx, 2)):
				# Спрыгивают с уступа в 2 м.
				out.append(c + Vector2i(dx, 2))
	var up := c + UP
	if climbable(c) and _node_m(up):
		out.append(up)
	var down := c + DOWN
	if climbable(down) and _node_m(down):
		out.append(down)
	return out


## Обход в ширину от start. Возвращает [parents: Dictionary, dist: Dictionary].
func explore(start: Vector2i) -> Array:
	var key := [world.revision, interior.size(), room_cells.size(), deck.size(), climb_rev]
	if key != _cache_key:
		clear_cache()
		_cache_key = key
	if _cache.has(start):
		return _cache[start]
	var out := _explore(start)
	_cache[start] = out
	return out


## Время идёт: старые обходы забываем.
func tick(dt: float) -> void:
	_cache_age += dt
	if _cache_age >= CACHE_TIME:
		_cache_age = 0.0
		clear_cache()


func clear_cache() -> void:
	_cache.clear()
	_node_memo.clear()
	_pass_memo.clear()


func _explore(start: Vector2i, cap := MAX_NODES) -> Array:
	var parents := {start: start}
	var dist := {start: 0}
	if not node(start):
		return [parents, dist]
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and queue.size() < cap:
		var c := queue[head]
		head += 1
		var d: int = dist[c] + 1
		for n in neighbors(c):
			if parents.has(n):
				continue
			if absi(n.x - start.x) > MAX_RADIUS:
				continue
			parents[n] = c
			dist[n] = d
			queue.append(n)
	return [parents, dist]


## Обход упёрся в предел: дальнее (глубокий забой в большой колонии) в него не попало.
static func truncated(dist: Dictionary) -> bool:
	return dist.size() >= MAX_NODES


## Прицельный поиск пути к любой из клеток goals (A*): для целей дальше, чем достаёт обход.
## Возвращает путь от старта (не включая его) до цели или пустой, если не нашёл за limit клеток.
func find_path(start: Vector2i, goals: Dictionary, limit := FAR_NODES) -> Array[Vector2i]:
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
	var seen := 0
	while not heap.is_empty() and seen < limit:
		var c: Vector2i = _heap_pop(heap)[1]
		seen += 1
		if goals.has(c):
			return path_to(parents, c)
		var d: int = g_cost[c] + 1
		for n in neighbors(c):
			if g_cost.has(n) and g_cost[n] <= d:
				continue
			g_cost[n] = d
			parents[n] = c
			_heap_push(heap, [d + _h(n, box), n])
	return none


## Сколько клеток перебирает прицельный поиск.
const FAR_NODES := 12000


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
