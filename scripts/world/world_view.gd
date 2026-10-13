class_name WorldView
extends Node2D
## Показывает мир вокруг камеры: создаёт/удаляет ChunkView, генерирует чанки
## с ограничением по времени на кадр и сдвигает начало координат (origin shifting),
## чтобы float-координаты не теряли точность на огромных глубинах и высотах.

const TILE := ChunkView.TILE
const SIZE := ChunkData.SIZE
const CHUNK_PX := TILE * SIZE
const MARGIN := 1
const SHIFT_DISTANCE := 16 * CHUNK_PX
const GEN_BUDGET_USEC := 6000

var world: WorldData
var colony: Colony
var camera: Camera2D
var structures: StructureLayer
var units_layer: UnitLayer
var fog: FogLayer
## Клетка мира, находящаяся в локальной точке (0, 0).
var origin := Vector2i.ZERO
var _views := {}


func setup(p_world: WorldData, p_colony: Colony, p_camera: Camera2D) -> void:
	world = p_world
	colony = p_colony
	camera = p_camera
	structures = StructureLayer.new()
	structures.view = self
	structures.colony = colony
	structures.z_index = 5
	add_child(structures)
	units_layer = UnitLayer.new()
	units_layer.view = self
	units_layer.colony = colony
	units_layer.z_index = 10
	add_child(units_layer)
	fog = FogLayer.new()
	fog.view = self
	fog.colony = colony
	fog.z_index = 20
	add_child(fog)


func cell_to_local(c: Vector2i) -> Vector2:
	return Vector2(c - origin) * TILE


func local_to_cell(p: Vector2) -> Vector2i:
	return origin + Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var local := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return local_to_cell(to_local(local))


## Точка экрана в координатах мира (в клетках, дробно).
func screen_to_world_cells(screen_pos: Vector2) -> Vector2:
	var local := to_local(get_viewport().get_canvas_transform().affine_inverse() * screen_pos)
	return Vector2(origin) + local / TILE


## Клетка мира в центре экрана.
func camera_cell() -> Vector2i:
	return local_to_cell(camera.position)


## Переносит камеру к клетке мира.
func focus_cell(c: Vector2i) -> void:
	origin = Vector2i(c.x >> 5 << 5, c.y >> 5 << 5)
	camera.position = cell_to_local(c) + Vector2(TILE, TILE) * 0.5
	_reposition_all()


func _process(_delta: float) -> void:
	if world == null:
		return
	_shift_origin_if_needed()
	_update_chunks()
	_redraw_dirty()


func _shift_origin_if_needed() -> void:
	var p := camera.position
	if absf(p.x) < SHIFT_DISTANCE and absf(p.y) < SHIFT_DISTANCE:
		return
	var shift := Vector2i(floori(p.x / CHUNK_PX), floori(p.y / CHUNK_PX)) * SIZE
	origin += shift
	camera.position -= Vector2(shift) * TILE
	_reposition_all()


func _reposition_all() -> void:
	for key in _views:
		_views[key].position = cell_to_local(key * SIZE)


func visible_chunk_rect() -> Rect2i:
	var half := get_viewport_rect().size * 0.5 / camera.zoom
	var a := local_to_cell(camera.position - half)
	var b := local_to_cell(camera.position + half)
	var ca := WorldData.chunk_of(a.x, a.y) - Vector2i(MARGIN, MARGIN)
	var cb := WorldData.chunk_of(b.x, b.y) + Vector2i(MARGIN, MARGIN)
	return Rect2i(ca, cb - ca + Vector2i.ONE)


func _update_chunks() -> void:
	var rect := visible_chunk_rect()
	# Удаляем далёкие представления.
	var keep := rect.grow(1)
	for key in _views.keys():
		if not keep.has_point(key):
			_views[key].queue_free()
			_views.erase(key)
	# Создаём недостающие, ближайшие к центру — первыми, в пределах бюджета времени.
	var center := WorldData.chunk_of(camera_cell().x, camera_cell().y)
	var missing: Array[Vector2i] = []
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var key := Vector2i(cx, cy)
			if not _views.has(key):
				missing.append(key)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	var start := Time.get_ticks_usec()
	for key in missing:
		if Time.get_ticks_usec() - start > GEN_BUDGET_USEC and not _views.is_empty():
			break
		var c := world.get_chunk(key.x, key.y)
		var v := ChunkView.new()
		v.setup(world, c)
		v.position = cell_to_local(key * SIZE)
		add_child(v)
		_views[key] = v
		# Соседям нужно дорисовать общие края.
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _views.has(key + d):
				world.dirty[key + d] = true
	# Держим в памяти чанки с запасом вокруг экрана.
	if world.chunks.size() > 1500:
		world.evict_outside(rect.grow(8))


## Снег на траве: перерисовать все видимые куски при смене сезона.
func set_snow(on: bool) -> void:
	if ChunkView.snow == on:
		return
	ChunkView.snow = on
	for key in _views:
		_views[key].queue_redraw()


func _redraw_dirty() -> void:
	if world.dirty.is_empty():
		return
	for key in world.dirty:
		var v: ChunkView = _views.get(key)
		if v != null:
			v.queue_redraw()
	world.dirty.clear()
