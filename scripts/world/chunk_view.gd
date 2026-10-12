class_name ChunkView
extends Node2D
## Отрисовка одного чанка. Стиль — плоский векторный: скруглённые края туннелей
## и рельефа, вкрапления руды, без пиксельной сетки.
## Перерисовывается только при изменении (Godot кэширует команды _draw).

const SIZE := ChunkData.SIZE
const TILE := 32.0
const ROUND := 11.0
const NEIGHBORS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0)]
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const GRASS := Color(0.36, 0.62, 0.27)
const GRASS_DARK := Color(0.27, 0.5, 0.22)
const FOG_TOP := Color(0.17, 0.14, 0.12)
const FOG_DEEP := Color(0.1, 0.08, 0.09)
const FOG_HOT := Color(0.2, 0.08, 0.05)

var world: WorldData
var chunk: ChunkData


func setup(p_world: WorldData, p_chunk: ChunkData) -> void:
	world = p_world
	chunk = p_chunk


## Флаги и материал клетки по локальным координатам (могут выходить за чанк).
## Возвращает -1, если соседний чанк не загружен.
func _flags_at(lx: int, ly: int) -> int:
	if lx >= 0 and lx < SIZE and ly >= 0 and ly < SIZE:
		return chunk.flags[ChunkData.idx(lx, ly)]
	var x := chunk.cx * SIZE + lx
	var y := chunk.cy * SIZE + ly
	if not world.has_chunk(x >> ChunkData.SHIFT, y >> ChunkData.SHIFT):
		return -1
	return world.get_flags(x, y)


func _mat_at(lx: int, ly: int) -> int:
	if lx >= 0 and lx < SIZE and ly >= 0 and ly < SIZE:
		return chunk.effective(ChunkData.idx(lx, ly))
	return world.get_mat(chunk.cx * SIZE + lx, chunk.cy * SIZE + ly)


func _is_open(lx: int, ly: int) -> bool:
	var f := _flags_at(lx, ly)
	if f < 0 or f & ChunkData.F_REVEALED == 0:
		return false
	return _mat_at(lx, ly) == Mat.AIR


static func fog_color(depth: int, v: float) -> Color:
	var c := FOG_TOP.lerp(FOG_DEEP, clampf(depth / 1500.0, 0.0, 1.0))
	if depth > 3000:
		c = c.lerp(FOG_HOT, clampf((depth - 3000) / 30000.0, 0.0, 0.8))
	return c.lightened((v - 0.5) * 0.03)


static func rock_color(m: int, v: float) -> Color:
	var c := Mat.color(m)
	if Mat.is_ore(m):
		c = c.lerp(Color(0.35, 0.33, 0.33), 0.65).darkened(0.15)
	return c.lightened((v - 0.5) * 0.14) if v >= 0.5 else c.darkened((0.5 - v) * 0.14)


## Для руды фон — окружающая порода, а сама руда рисуется вкраплениями.
func _ore_host(lx: int, ly: int) -> int:
	for d: Vector2i in NEIGHBORS:
		var f := _flags_at(lx + d.x, ly + d.y)
		if f < 0 or f & ChunkData.F_DUG:
			continue
		var m := _mat_at(lx + d.x, ly + d.y)
		if Mat.is_solid(m) and not Mat.is_ore(m):
			return m
	return Mat.GRANITE


## Цвет «стены», которую видно сквозь клетку (для заливки скруглённых углов).
func _solid_color(lx: int, ly: int) -> Color:
	var x := chunk.cx * SIZE + lx
	var y := chunk.cy * SIZE + ly
	var v := world.gen.tint(x, y)
	var f := _flags_at(lx, ly)
	var depth := y - world.gen.surface_y(x)
	if f < 0 or f & ChunkData.F_REVEALED == 0:
		return fog_color(depth, v)
	return rock_color(_mat_at(lx, ly), v)


func _draw() -> void:
	if chunk == null:
		return
	var gen := world.gen
	var x0 := chunk.cx * SIZE
	var y0 := chunk.cy * SIZE
	for lx in SIZE:
		var x := x0 + lx
		var surf := gen.surface_y(x)
		for ly in SIZE:
			var y := y0 + ly
			if y < surf:
				continue # небо рисует фон
			var i := ChunkData.idx(lx, ly)
			var f := chunk.flags[i]
			var m := chunk.mat[i]
			var v := gen.tint(x, y)
			var r := Rect2(lx * TILE, ly * TILE, TILE, TILE)
			var depth := y - surf
			if f & ChunkData.F_REVEALED == 0:
				draw_rect(r, fog_color(depth, v))
				continue
			var dug := f & ChunkData.F_DUG != 0
			if dug or m == Mat.AIR or m == Mat.WATER:
				_draw_open_cell(lx, ly, r, m, dug, depth, v)
				continue
			_draw_solid_cell(lx, ly, r, m, v, x, y, surf)


func _draw_open_cell(lx: int, ly: int, r: Rect2, m: int, dug: bool, depth: int, v: float) -> void:
	# Задняя стена: тёмный вариант породы.
	var back: Color
	if dug:
		back = rock_color(_ore_host(lx, ly) if Mat.is_ore(m) else m, v).darkened(0.62)
	else:
		back = fog_color(depth, v).darkened(0.25)
	draw_rect(r, back)
	if m == Mat.WATER and not dug:
		var w := Mat.color(Mat.WATER).lightened((v - 0.5) * 0.08)
		draw_rect(r, w)
		return
	# Скругляем внутренние углы туннеля.
	for corner: Vector2i in CORNERS:
		var sx := lx + corner.x
		var sy := ly + corner.y
		if _is_open(sx, ly) or _is_open(lx, sy):
			continue
		if _flags_at(sx, ly) < 0 or _flags_at(lx, sy) < 0:
			continue
		var col := _solid_color(sx, ly)
		draw_colored_polygon(_corner_fill(r, corner), col)


## Полигон «ушка» в углу клетки, снаружи четверти окружности радиуса ROUND.
static func _corner_fill(r: Rect2, corner: Vector2i) -> PackedVector2Array:
	var cx := r.position.x if corner.x < 0 else r.end.x
	var cy := r.position.y if corner.y < 0 else r.end.y
	var center := Vector2(cx - corner.x * ROUND, cy - corner.y * ROUND)
	var pts := PackedVector2Array([Vector2(cx, cy)])
	var steps := 5
	for s in steps + 1:
		var t := float(s) / steps * PI * 0.5
		pts.append(center + Vector2(corner.x * cos(t), corner.y * sin(t)) * ROUND)
	return pts


func _draw_solid_cell(lx: int, ly: int, r: Rect2, m: int, v: float, x: int, y: int, surf: int) -> void:
	var base := rock_color(_ore_host(lx, ly) if Mat.is_ore(m) else m, v)
	var open_l := _is_open(lx - 1, ly)
	var open_r := _is_open(lx + 1, ly)
	var open_u := _is_open(lx, ly - 1)
	var open_d := _is_open(lx, ly + 1)
	# Внешние углы скругляем, если с двух сторон пустота.
	var mask := 0
	if open_u and open_l:
		mask |= 1
	if open_u and open_r:
		mask |= 2
	if open_d and open_r:
		mask |= 4
	if open_d and open_l:
		mask |= 8
	if mask == 0:
		draw_rect(r, base)
	else:
		draw_colored_polygon(_rounded_rect(r, mask), base)

	# Тени по краям, обращённым к пустоте.
	var shade := base.darkened(0.28)
	if open_l and mask & 9 == 0:
		draw_rect(Rect2(r.position.x, r.position.y, 3, TILE), shade)
	if open_r and mask & 6 == 0:
		draw_rect(Rect2(r.end.x - 3, r.position.y, 3, TILE), shade)
	if open_d and mask & 12 == 0:
		draw_rect(Rect2(r.position.x, r.end.y - 3, TILE, 3), shade)

	if Mat.is_ore(m):
		_draw_ore(r, m, x, y)
	elif m == Mat.MAGMA:
		draw_circle(r.get_center(), TILE * 0.3, Color(1.0, 0.85, 0.3, 0.8))

	if m == Mat.TOPSOIL and y == surf and open_u:
		_draw_grass(r, x, mask)


func _draw_ore(r: Rect2, m: int, x: int, y: int) -> void:
	var col := Mat.color(m)
	for k in 5:
		var hx := WorldGen.hash01(x, y, 100 + k)
		var hy := WorldGen.hash01(x, y, 200 + k)
		var hr := WorldGen.hash01(x, y, 300 + k)
		var p := r.position + Vector2(5 + hx * (TILE - 10), 5 + hy * (TILE - 10))
		draw_circle(p, 2.5 + hr * 4.0, col.darkened(0.25))
		draw_circle(p, 1.5 + hr * 3.5, col)
		draw_circle(p - Vector2(1, 1), 1.0 + hr, col.lightened(0.4))


func _draw_grass(r: Rect2, x: int, mask: int) -> void:
	var left := r.position.x + (ROUND * 0.6 if mask & 1 else 0.0)
	var right := r.end.x - (ROUND * 0.6 if mask & 2 else 0.0)
	draw_rect(Rect2(left, r.position.y, right - left, 6), GRASS)
	for k in 4:
		var bx := left + (right - left) * (k + 0.5) / 4.0
		var hgt := 4.0 + WorldGen.hash01(x, k, 400) * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx - 3, r.position.y + 1),
			Vector2(bx + 3, r.position.y + 1),
			Vector2(bx + WorldGen.hash01(x, k, 401) * 4.0 - 2.0, r.position.y - hgt),
		]), GRASS_DARK if k % 2 else GRASS)


## Прямоугольник со скруглёнными углами по маске (1=лв, 2=пв, 4=пн, 8=лн).
static func _rounded_rect(r: Rect2, mask: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[r.position, Vector2(1, 1), PI, 1],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 1), PI * 1.5, 2],
		[r.end, Vector2(-1, -1), 0.0, 4],
		[Vector2(r.position.x, r.end.y), Vector2(1, -1), PI * 0.5, 8],
	]
	for c in corners:
		var p: Vector2 = c[0]
		if mask & c[3] == 0:
			pts.append(p)
			continue
		var center: Vector2 = p + c[1] * ROUND
		var a0: float = c[2]
		for s in 6:
			var t := a0 + float(s) / 5.0 * PI * 0.5
			pts.append(center + Vector2(cos(t), sin(t)) * ROUND)
	return pts
