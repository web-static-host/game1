class_name Pathing
extends RefCounted
## Передвижение жителей в разрезе мира.
## - ходят по открытым клеткам, под ногами — опора, над головой — свободно;
## - в выкопанных клетках и готовых постройках есть лестницы: можно лезть вверх/вниз;
## - по рельефу шагают на ступеньку в 1 м.

const MAX_NODES := 3000
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


func _init(p_world: WorldData, p_interior: Dictionary, p_rooms: Dictionary, p_deck: Dictionary) -> void:
	world = p_world
	interior = p_interior
	room_cells = p_rooms
	deck = p_deck


func passable(c: Vector2i) -> bool:
	return world.is_open(c.x, c.y)


func climbable(c: Vector2i) -> bool:
	if room_cells.has(c):
		return false
	return interior.has(c) or (world.is_dug(c.x, c.y) and world.get_mat(c.x, c.y) == Mat.AIR)


func solid(c: Vector2i) -> bool:
	return Mat.is_solid(world.get_mat(c.x, c.y))


## Можно стоять ногами в клетке (без учёта головы).
func standable(c: Vector2i) -> bool:
	if not passable(c):
		return false
	if deck.has(c):
		return true
	var below := c + DOWN
	if solid(below) or climbable(c) or climbable(below):
		return true
	# Пол комнаты, стоящей на другой комнате: перекрытие держит.
	return room_cells.has(below) and room_cells[below] != room_cells.get(c, -1)


## Узел графа: можно стоять и голова не упирается.
func node(c: Vector2i) -> bool:
	return standable(c) and passable(c + UP)


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in [-1, 1]:
		var side := c + Vector2i(dx, 0)
		if node(side):
			out.append(side)
		else:
			var step_up := c + Vector2i(dx, -1)
			if passable(c + UP * 2) and node(step_up):
				out.append(step_up)
			var step_down := c + Vector2i(dx, 1)
			if passable(side) and node(step_down):
				out.append(step_down)
	var up := c + UP
	if climbable(c) and node(up):
		out.append(up)
	var down := c + DOWN
	if climbable(down) and node(down):
		out.append(down)
	return out


## Обход в ширину от start. Возвращает [parents: Dictionary, dist: Dictionary].
func explore(start: Vector2i) -> Array:
	var parents := {start: start}
	var dist := {start: 0}
	if not node(start):
		return [parents, dist]
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and queue.size() < MAX_NODES:
		var c := queue[head]
		head += 1
		var d: int = dist[c] + 1
		for n in neighbors(c):
			if parents.has(n):
				continue
			if absi(n.x - start.x) > MAX_RADIUS or absi(n.y - start.y) > MAX_RADIUS:
				continue
			parents[n] = c
			dist[n] = d
			queue.append(n)
	return [parents, dist]


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
