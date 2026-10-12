class_name WorldData
extends RefCounted
## Хранилище мира: кэш чанков + изменения игрока.

const SIZE := ChunkData.SIZE
const SHIFT := ChunkData.SHIFT
const MASK := ChunkData.MASK
const MAX_CAVE_REVEAL := 4000
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var gen: WorldGen
## Vector2i(cx, cy) -> ChunkData
var chunks := {}
## Сохранённые флаги чанков, которые ещё не загружены: Vector2i -> PackedByteArray
var pending_flags := {}
## Сохранённые материалы изменённых чанков (осыпи, обвалы): Vector2i -> PackedByteArray
var pending_mats := {}
## Чанки, которые нужно перерисовать: Vector2i -> true
var dirty := {}
## Собранные объекты поверхности: x -> true
var removed_features := {}
## Объекты, помеченные игроком на сбор: x -> true
var feature_marks := {}
## Живые растения с состоянием: x -> {"t": вид, "g": рост 0..1, "b": ягоды}.
## Сгенерированные изначально растения — взрослые и с полным урожаем, пока их не тронули.
var plants := {}
const BUSH_BERRIES := 6.0


func _init(p_gen: WorldGen) -> void:
	gen = p_gen


static func chunk_of(x: int, y: int) -> Vector2i:
	return Vector2i(x >> SHIFT, y >> SHIFT)


func has_chunk(cx: int, cy: int) -> bool:
	return chunks.has(Vector2i(cx, cy))


func get_chunk(cx: int, cy: int) -> ChunkData:
	var key := Vector2i(cx, cy)
	var c: ChunkData = chunks.get(key)
	if c == null:
		c = gen.generate_chunk(cx, cy)
		if pending_flags.has(key):
			c.flags = pending_flags[key]
			c.modified = true
			pending_flags.erase(key)
		if pending_mats.has(key):
			c.mat = pending_mats[key]
			c.modified = true
			c.mat_modified = true
			pending_mats.erase(key)
		chunks[key] = c
	return c


func _chunk_at(x: int, y: int) -> ChunkData:
	return get_chunk(x >> SHIFT, y >> SHIFT)


func get_mat(x: int, y: int) -> int:
	return _chunk_at(x, y).effective(ChunkData.idx(x & MASK, y & MASK))


## Природный материал, даже если клетка уже выкопана.
func get_natural_mat(x: int, y: int) -> int:
	return _chunk_at(x, y).mat[ChunkData.idx(x & MASK, y & MASK)]


func get_flags(x: int, y: int) -> int:
	return _chunk_at(x, y).flags[ChunkData.idx(x & MASK, y & MASK)]


func is_revealed(x: int, y: int) -> bool:
	return get_flags(x, y) & ChunkData.F_REVEALED != 0


func is_dug(x: int, y: int) -> bool:
	return get_flags(x, y) & ChunkData.F_DUG != 0


## Свободное пространство, известное игроку (по нему могут ходить рабочие).
func is_open(x: int, y: int) -> bool:
	var c := _chunk_at(x, y)
	var i := ChunkData.idx(x & MASK, y & MASK)
	return c.flags[i] & ChunkData.F_REVEALED != 0 and c.effective(i) == Mat.AIR


func _set_flags(x: int, y: int, add: int) -> bool:
	var c := _chunk_at(x, y)
	var i := ChunkData.idx(x & MASK, y & MASK)
	var old := c.flags[i]
	if old & add == add:
		return false
	c.flags[i] = old | add
	c.modified = true
	_touch(x, y)
	return true


func _touch(x: int, y: int) -> void:
	var key := chunk_of(x, y)
	dirty[key] = true
	# Края клетки рисуются с учётом соседей — соседний чанк тоже обновляем.
	var lx := x & MASK
	var ly := y & MASK
	if lx == 0:
		dirty[key + Vector2i(-1, 0)] = true
	elif lx == MASK:
		dirty[key + Vector2i(1, 0)] = true
	if ly == 0:
		dirty[key + Vector2i(0, -1)] = true
	elif ly == MASK:
		dirty[key + Vector2i(0, 1)] = true


func feature_at(x: int) -> int:
	if plants.has(x):
		return int(plants[x]["t"])
	if removed_features.has(x):
		return WorldGen.FEATURE_NONE
	return gen.feature_at(x)


## Рост растения 0..1 (взрослое — 1).
func growth(x: int) -> float:
	return float(plants[x]["g"]) if plants.has(x) else 1.0


## Ягод на кусте сейчас.
func berries(x: int) -> float:
	return float(plants[x]["b"]) if plants.has(x) else BUSH_BERRIES


func _plant(x: int) -> Dictionary:
	if not plants.has(x):
		plants[x] = {"t": feature_at(x), "g": growth(x), "b": berries(x)}
	return plants[x]


func set_berries(x: int, b: float) -> void:
	var p := _plant(x)
	var before := floori(float(p["b"]))
	p["b"] = b
	if floori(b) != before:
		_touch_feature(x)


func grow(x: int, dg: float) -> void:
	var p := _plant(x)
	var before := floori(float(p["g"]) * 10.0)
	p["g"] = minf(1.0, float(p["g"]) + dg)
	if floori(float(p["g"]) * 10.0) != before:
		_touch_feature(x)


## Новое растение на свободной траве.
func sprout(x: int, kind: int) -> void:
	removed_features.erase(x)
	plants[x] = {"t": kind, "g": 0.05 if kind == WorldGen.FEATURE_TREE else 1.0, "b": 0.0}
	_touch_feature(x)


func remove_feature(x: int) -> void:
	removed_features[x] = true
	plants.erase(x)
	feature_marks.erase(x)
	_touch_feature(x)


func set_feature_mark(x: int, on: bool) -> void:
	if on:
		feature_marks[x] = true
	else:
		feature_marks.erase(x)
	_touch_feature(x)


func _touch_feature(x: int) -> void:
	var base := gen.surface_y(x) - 1
	for y in [base, base - 8]:
		dirty[chunk_of(x, y)] = true


func reveal(x: int, y: int) -> bool:
	return _set_flags(x, y, ChunkData.F_REVEALED)


## Кладёт материал в клетку (осыпь, обломки): клетка снова твёрдая и видимая.
func set_material(x: int, y: int, m: int) -> void:
	var c := _chunk_at(x, y)
	var i := ChunkData.idx(x & MASK, y & MASK)
	c.mat[i] = m
	c.flags[i] = (c.flags[i] & ~(ChunkData.F_DUG | ChunkData.F_CAVE)) | ChunkData.F_REVEALED
	c.modified = true
	c.mat_modified = true
	_touch(x, y)


func set_dug(x: int, y: int) -> void:
	_set_flags(x, y, ChunkData.F_DUG | ChunkData.F_REVEALED)


## Открывает 8 соседей клетки. Если вскрыта природная полость — открывает её целиком.
## Возвращает список впервые увиденных клеток [Vector2i].
func reveal_around(x: int, y: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var caves: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if reveal(nx, ny):
				found.append(Vector2i(nx, ny))
				if get_flags(nx, ny) & ChunkData.F_CAVE and get_mat(nx, ny) == Mat.AIR:
					caves.append(Vector2i(nx, ny))
	for start in caves:
		found.append_array(_flood_reveal_cave(start))
	return found


func _flood_reveal_cave(start: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size() and seen.size() < MAX_CAVE_REVEAL:
		var p := queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := Vector2i(p.x + dx, p.y + dy)
				if seen.has(n):
					continue
				seen[n] = true
				if reveal(n.x, n.y):
					found.append(n)
				# Распространяемся только по воздуху полости (вода видна, но в неё не заходим).
				if dx * dy == 0 and get_flags(n.x, n.y) & ChunkData.F_CAVE and get_mat(n.x, n.y) == Mat.AIR:
					queue.append(n)
	return found


## Выгружает немодифицированные чанки вне прямоугольника (в координатах чанков).
func evict_outside(keep: Rect2i) -> void:
	var drop: Array = []
	for key in chunks:
		if not keep.has_point(key):
			drop.append(key)
	for key in drop:
		var c: ChunkData = chunks[key]
		if c.modified:
			pending_flags[key] = c.flags
		if c.mat_modified:
			pending_mats[key] = c.mat
		chunks.erase(key)


## Изменённые материалы чанков (загруженные и нет): Vector2i -> PackedByteArray.
func modified_mats() -> Dictionary:
	var out := pending_mats.duplicate()
	for key in chunks:
		var c: ChunkData = chunks[key]
		if c.mat_modified:
			out[key] = c.mat
	return out


## Все изменённые чанки (загруженные и нет): Vector2i -> PackedByteArray флагов.
func modified_flags() -> Dictionary:
	var out := pending_flags.duplicate()
	for key in chunks:
		var c: ChunkData = chunks[key]
		if c.modified:
			out[key] = c.flags
	return out
