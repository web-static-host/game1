class_name LightLayer
extends Node2D
## Темнота под землёй: выработки без света (солнце в шахте, электричество в комнатах,
## светящиеся гаврики — см. Colony.is_lit) тонут в синеватом полумраке поверх гавриков.
## Пересчёт раз в полсекунды — свет меняется медленно.

const TILE := ChunkView.TILE
const DARK := Color(0.03, 0.02, 0.1, 0.62)
const DIM := Color(0.03, 0.02, 0.1, 0.32)
const REFRESH := 0.5

var view: WorldView
var colony: Colony
var _t := 0.0
## [клетка, альфа-цвет] для отрисовки.
var _cells: Array = []
var _cam := Vector2.INF


func _process(delta: float) -> void:
	_t -= delta
	if colony == null:
		return
	# Камеру сдвинули заметно — пересчитать сразу, иначе раз в полсекунды.
	var moved := view.camera.position.distance_to(_cam) > TILE * 2.0
	if _t > 0.0 and not moved:
		return
	_cam = view.camera.position
	_t = REFRESH
	_rebuild()
	queue_redraw()


func _rebuild() -> void:
	_cells.clear()
	var world := colony.world
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var a := view.local_to_cell(view.camera.position - half) - Vector2i(1, 1)
	var b := view.local_to_cell(view.camera.position + half) + Vector2i(1, 1)
	var lit := {}
	var dark: Array[Vector2i] = []
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if y < world.gen.surface_y(x) or not world.is_revealed(x, y):
				continue
			if world.get_mat(x, y) != Mat.AIR and not world.is_dug(x, y):
				continue
			var c := Vector2i(x, y)
			if colony.is_lit(c):
				lit[c] = true
			else:
				dark.append(c)
	# У границы со светом — полумрак, дальше — тьма.
	for c in dark:
		var near := lit.has(c + Vector2i.LEFT) or lit.has(c + Vector2i.RIGHT) or lit.has(c + Vector2i.UP) or lit.has(c + Vector2i.DOWN)
		_cells.append([c, DIM if near else DARK])


func _draw() -> void:
	for e in _cells:
		draw_rect(Rect2(view.cell_to_local(e[0]), Vector2(TILE, TILE)), e[1])
