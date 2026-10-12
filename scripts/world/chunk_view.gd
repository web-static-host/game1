class_name ChunkView
extends Node2D
## Отрисовка одного чанка. Стиль — плоский векторный: скруглённые края туннелей
## и рельефа, вкрапления руды, без пиксельной сетки.
## Перерисовывается только при изменении (Godot кэширует команды _draw).

const SIZE := ChunkData.SIZE
const TILE := 32.0
const ROUND := 11.0
## Толщина почвенного слоя вдоль сглаженной поверхности, в клетках.
const SOIL_BAND := 1.4
## Насколько глубоко (в долях клетки) видна порода от края выработки.
const FADE := 0.6
const NEIGHBORS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0)]
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const GRASS := Color(0.36, 0.62, 0.27)
const GRASS_DARK := Color(0.27, 0.5, 0.22)
## Неразведанная земля — приглушённый землистый тон (не чернота), чтобы переход
## к разведанной породе был мягким, а не «свечением».
const FOG_TOP := Color(0.33, 0.27, 0.22)
const FOG_DEEP := Color(0.27, 0.25, 0.26)
const FOG_HOT := Color(0.36, 0.2, 0.14)

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
	return c.lightened((v - 0.5) * 0.08) if v >= 0.5 else c.darkened((0.5 - v) * 0.08)


## Цвет породы с яркостью, подтянутой к окружающей земле: у выработки виден
## оттенок породы, но без «свечения» светлых пород на тёмном фоне.
static func match_luma(base: Color, fog: Color) -> Color:
	var lb := base.get_luminance()
	if lb <= 0.001:
		return base
	var k := lerpf(1.0, fog.get_luminance() * 1.15 / lb, 0.75)
	return Color(clampf(base.r * k, 0, 1), clampf(base.g * k, 0, 1), clampf(base.b * k, 0, 1), base.a)


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
		# Плавный рельеф: верх земли — ломаная через центры столбцов, а не ступеньки.
		var line := _surface_line(x, surf)
		var band_to := ceili(maxf(line.x, line.z) + SOIL_BAND) if not line.is_zero_approx() else surf
		var soil := rock_color(Mat.TOPSOIL, gen.tint(x, surf))
		for ly in SIZE:
			var y := y0 + ly
			if y < surf:
				if not line.is_zero_approx() and y + 1 > minf(line.x, line.z):
					_draw_clipped(lx, ly, line, soil)
				continue # небо рисует фон
			var i := ChunkData.idx(lx, ly)
			var f := chunk.flags[i]
			var m := chunk.mat[i]
			var v := gen.tint(x, y)
			var r := Rect2(lx * TILE, ly * TILE, TILE, TILE)
			var depth := y - surf
			if y < band_to and f & ChunkData.F_DUG == 0 and Mat.is_solid(m):
				var col := rock_color(m, v) if f & ChunkData.F_REVEALED else fog_color(depth, v)
				_draw_clipped(lx, ly, line, col)
				# Почвенный слой постоянной толщины вдоль поверхности скрывает ступеньки.
				var band := _band_poly(lx, ly, line)
				for poly in Geometry2D.intersect_polygons(band, _rect_poly(r)):
					draw_colored_polygon(poly, soil)
				if y == surf:
					_draw_smooth_grass(lx, ly, line, x)
				continue
			if f & ChunkData.F_REVEALED == 0:
				draw_rect(r, fog_color(depth, v))
				continue
			var dug := f & ChunkData.F_DUG != 0
			if dug or m == Mat.AIR or m == Mat.WATER:
				_draw_open_cell(lx, ly, r, m, dug, depth, v)
				continue
			_draw_solid_cell(lx, ly, r, m, v, x, y, surf)
	# Деревья и валуны — после рельефа, чтобы рисоваться поверх.
	for lx in SIZE:
		var x := x0 + lx
		var base := gen.surface_y(x) - 1
		if base < y0 or base >= y0 + SIZE:
			continue
		var f := world.feature_at(x)
		if f != WorldGen.FEATURE_NONE:
			_draw_feature(f, x, Vector2(lx * TILE + TILE * 0.5, (base - y0 + 1) * TILE))


func _draw_open_cell(lx: int, ly: int, r: Rect2, m: int, dug: bool, depth: int, v: float) -> void:
	# Задняя стена: тёмный вариант породы.
	var back: Color
	if dug:
		back = rock_color(_ore_host(lx, ly) if Mat.is_ore(m) else m, v).darkened(0.72)
	else:
		back = fog_color(depth, v).darkened(0.55)
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
	# Под землёй порода видна только у самой выработки и плавно уходит в темноту.
	var faded := mask == 0
	var fog := fog_color(y - surf, v)
	if faded:
		draw_rect(r, fog)
		_fade_edges(lx, ly, r, match_luma(base, fog), open_l, open_r, open_u, open_d)
	elif mask == 0:
		draw_rect(r, base)
	else:
		# Выступ между выработками: приглушённый, как и остальная порода у края.
		var pts := _rounded_rect(r, mask)
		draw_colored_polygon(pts, fog)
		draw_colored_polygon(pts, Color(match_luma(base, fog), 0.45))

	# Тени по краям, обращённым к пустоте.
	var shade := base.darkened(0.28)
	if open_l and mask & 9 == 0:
		draw_rect(Rect2(r.position.x, r.position.y, 3, TILE), shade)
	if open_r and mask & 6 == 0:
		draw_rect(Rect2(r.end.x - 3, r.position.y, 3, TILE), shade)
	if open_d and mask & 12 == 0:
		draw_rect(Rect2(r.position.x, r.end.y - 3, TILE, 3), shade)

	if Mat.is_ore(m):
		_draw_ore(r, m, x, y, [open_l, open_r, open_u, open_d] if faded else [])
	elif m == Mat.MAGMA:
		draw_circle(r.get_center(), TILE * 0.3, Color(1.0, 0.85, 0.3, 0.8))

	if m == Mat.TOPSOIL and y == surf and open_u:
		_draw_grass(r, x, mask)


## open_sides: [лево, право, верх, низ] — вкрапления видны только у открытых сторон.
func _draw_ore(r: Rect2, m: int, x: int, y: int, open_sides: Array = []) -> void:
	var base_col := Mat.color(m)
	for k in 5:
		var hx := WorldGen.hash01(x, y, 100 + k)
		var hy := WorldGen.hash01(x, y, 200 + k)
		var hr := WorldGen.hash01(x, y, 300 + k)
		var p := r.position + Vector2(5 + hx * (TILE - 10), 5 + hy * (TILE - 10))
		var col := base_col
		if not open_sides.is_empty():
			var d := TILE
			var local := p - r.position
			if open_sides[0]:
				d = minf(d, local.x)
			if open_sides[1]:
				d = minf(d, TILE - local.x)
			if open_sides[2]:
				d = minf(d, local.y)
			if open_sides[3]:
				d = minf(d, TILE - local.y)
			col.a = clampf(1.0 - d / (FADE * TILE), 0.0, 1.0)
			if col.a <= 0.05:
				continue
		draw_circle(p, 2.5 + hr * 4.0, Color(col.darkened(0.25), col.a))
		draw_circle(p, 1.5 + hr * 3.5, col)
		draw_circle(p - Vector2(1, 1), 1.0 + hr, Color(col.lightened(0.4), col.a))


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


const TRUNK := Color(0.42, 0.29, 0.18)
const LEAVES := Color(0.24, 0.52, 0.24)
const LEAVES_LIGHT := Color(0.33, 0.63, 0.3)
const BOULDER := Color(0.55, 0.53, 0.52)
const MARK := Color(1.0, 0.82, 0.25)


## foot — точка на земле под объектом.
func _draw_feature(f: int, x: int, foot: Vector2) -> void:
	var marked := world.feature_marks.has(x)
	var gen := world.gen
	if f == WorldGen.FEATURE_TREE:
		var h := gen.tree_height(x) * TILE
		var lean := (WorldGen.hash01(x, 21, 0) - 0.5) * 8.0
		draw_colored_polygon(PackedVector2Array([
			foot + Vector2(-5, 0), foot + Vector2(5, 0),
			foot + Vector2(3 + lean, -h * 0.75), foot + Vector2(-3 + lean, -h * 0.75)]), TRUNK)
		var top := foot + Vector2(lean, -h * 0.75)
		var r := TILE * (0.9 + WorldGen.hash01(x, 22, 0) * 0.5)
		for k in 5:
			var a := k * TAU / 5.0 + WorldGen.hash01(x, 23 + k, 0)
			draw_circle(top + Vector2(cos(a), sin(a) * 0.7) * r * 0.7, r * 0.75, LEAVES)
		draw_circle(top + Vector2(-r * 0.2, -r * 0.3), r * 0.6, LEAVES_LIGHT)
		if marked:
			_draw_mark(top + Vector2(0, -r * 1.6))
	elif f == WorldGen.FEATURE_BOULDER:
		var w := TILE * (0.8 + WorldGen.hash01(x, 31, 0) * 0.5)
		var hh := TILE * (0.55 + WorldGen.hash01(x, 32, 0) * 0.3)
		var pts := PackedVector2Array()
		for k in 9:
			var a := PI + k * PI / 8.0
			pts.append(foot + Vector2(cos(a) * w * 0.5, sin(a) * hh))
		draw_colored_polygon(pts, BOULDER)
		draw_circle(foot + Vector2(-w * 0.15, -hh * 0.6), hh * 0.25, BOULDER.lightened(0.2))
		if marked:
			_draw_mark(foot + Vector2(0, -hh - TILE * 0.7))
	elif f == WorldGen.FEATURE_BUSH:
		var bw := TILE * (0.55 + WorldGen.hash01(x, 33, 0) * 0.2)
		for k in 3:
			draw_circle(foot + Vector2((k - 1) * bw * 0.55, -bw * 0.55 - (k % 2) * 4.0), bw * 0.55, LEAVES if k != 1 else LEAVES_LIGHT)
		for k in 5:
			var bp := foot + Vector2((WorldGen.hash01(x, 40 + k, 0) - 0.5) * bw * 1.6, -bw * (0.3 + WorldGen.hash01(x, 50 + k, 0) * 0.8))
			draw_circle(bp, 3.0, Color(0.85, 0.15, 0.25))
		if marked:
			_draw_mark(foot + Vector2(0, -bw * 1.6 - TILE * 0.4))


## Значок «собрать»: жёлтый кружок со стрелкой вниз.
func _draw_mark(p: Vector2) -> void:
	draw_circle(p, 11, Color(0, 0, 0, 0.5))
	draw_circle(p, 9, MARK)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -3), p + Vector2(5, -3), p + Vector2(0, 5)]), Color(0.2, 0.15, 0.05))



## Линия поверхности над столбцом x в клетках: (левый край, центр, правый край).
## Нулевой вектор — сглаживание не нужно (поверхность раскопана).
func _surface_line(x: int, surf: int) -> Vector3:
	var top := world.get_flags(x, surf) if world.has_chunk(x >> ChunkData.SHIFT, surf >> ChunkData.SHIFT) else 0
	if top & ChunkData.F_DUG:
		return Vector3.ZERO
	var gen := world.gen
	return Vector3((gen.surface_y(x - 1) + surf) * 0.5, surf, (surf + gen.surface_y(x + 1)) * 0.5)


## Рисует часть клетки ниже линии поверхности.
func _draw_clipped(lx: int, ly: int, line: Vector3, col: Color) -> void:
	var pts := clip_below(lx * TILE, ly * TILE, TILE, _line_px(ly, line))
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)


## Линия в пикселях чанка относительно строки ly: y-координаты (лево, центр, право).
func _line_px(ly: int, line: Vector3) -> Vector3:
	var y0 := chunk.cy * SIZE
	return (line - Vector3(y0, y0, y0)) * TILE


## Полигон: квадрат клетки, обрезанный сверху ломаной (x0,l.x)-(xm,l.y)-(x1,l.z).
static func clip_below(x0: float, top: float, size: float, l: Vector3) -> PackedVector2Array:
	var bottom := top + size
	var xs := [x0, x0 + size * 0.5, x0 + size]
	var ls := [l.x, l.y, l.z]
	var upper: Array[Vector2] = []
	for seg in 2:
		var a := Vector2(xs[seg], ls[seg])
		var b := Vector2(xs[seg + 1], ls[seg + 1])
		var pts: Array[Vector2] = [a]
		if not is_equal_approx(a.y, b.y):
			var ts: Array[float] = []
			for yy in [top, bottom]:
				var t: float = (yy - a.y) / (b.y - a.y)
				if t > 0.0 and t < 1.0:
					ts.append(t)
			ts.sort()
			for t in ts:
				pts.append(a.lerp(b, t))
		pts.append(b)
		for p in pts:
			upper.append(Vector2(p.x, clampf(p.y, top, bottom)))
	var all_bottom := true
	for p in upper:
		if p.y < bottom - 0.01:
			all_bottom = false
	if all_bottom:
		return PackedVector2Array()
	var poly := PackedVector2Array()
	for p in upper:
		if poly.is_empty() or not poly[poly.size() - 1].is_equal_approx(p):
			poly.append(p)
	var br := Vector2(x0 + size, bottom)
	var bl := Vector2(x0, bottom)
	if not poly[poly.size() - 1].is_equal_approx(br):
		poly.append(br)
	if not poly[0].is_equal_approx(bl):
		poly.append(bl)
	return poly


func _draw_smooth_grass(lx: int, ly: int, line: Vector3, x: int) -> void:
	var l := _line_px(ly, line)
	var xs := [lx * TILE, lx * TILE + TILE * 0.5, lx * TILE + TILE]
	var ys := [l.x, l.y, l.z]
	draw_colored_polygon(PackedVector2Array([
		Vector2(xs[0], ys[0]), Vector2(xs[1], ys[1]), Vector2(xs[2], ys[2]),
		Vector2(xs[2], ys[2] + 6), Vector2(xs[1], ys[1] + 6), Vector2(xs[0], ys[0] + 6)]), GRASS)
	for k in 4:
		var t := (k + 0.5) / 4.0
		var bx: float = lerpf(xs[0], xs[2], t)
		var by: float = lerpf(ys[0], ys[1], t * 2.0) if t < 0.5 else lerpf(ys[1], ys[2], t * 2.0 - 1.0)
		var hgt := 4.0 + WorldGen.hash01(x, k, 400) * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx - 3, by + 1), Vector2(bx + 3, by + 1),
			Vector2(bx + WorldGen.hash01(x, k, 401) * 4.0 - 2.0, by - hgt),
		]), GRASS_DARK if k % 2 else GRASS)


func _band_poly(lx: int, ly: int, line: Vector3) -> PackedVector2Array:
	var l := _line_px(ly, line)
	var d := SOIL_BAND * TILE
	var x0 := lx * TILE
	return PackedVector2Array([
		Vector2(x0, l.x), Vector2(x0 + TILE * 0.5, l.y), Vector2(x0 + TILE, l.z),
		Vector2(x0 + TILE, l.z + d), Vector2(x0 + TILE * 0.5, l.y + d), Vector2(x0, l.x + d)])


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Градиент от цвета породы у открытой стороны к темноте вглубь.
func _fade_edges(lx: int, ly: int, r: Rect2, base: Color, l: bool, rt: bool, u: bool, d: bool) -> void:
	var f := FADE * TILE
	var clear := Color(base, 0.0)
	var p := r.position
	var e := r.end
	if l:
		draw_polygon(PackedVector2Array([p, Vector2(p.x + f, p.y), Vector2(p.x + f, e.y), Vector2(p.x, e.y)]),
			PackedColorArray([base, clear, clear, base]))
	if rt:
		draw_polygon(PackedVector2Array([Vector2(e.x - f, p.y), Vector2(e.x, p.y), e, Vector2(e.x - f, e.y)]),
			PackedColorArray([clear, base, base, clear]))
	if u:
		draw_polygon(PackedVector2Array([p, Vector2(e.x, p.y), Vector2(e.x, p.y + f), Vector2(p.x, p.y + f)]),
			PackedColorArray([base, base, clear, clear]))
	if d:
		draw_polygon(PackedVector2Array([Vector2(p.x, e.y - f), Vector2(e.x, e.y - f), e, Vector2(p.x, e.y)]),
			PackedColorArray([clear, clear, base, base]))
	# Открыт только угол по диагонали — веер из угла.
	for c: Vector2i in CORNERS:
		var side_x := l if c.x < 0 else rt
		var side_y := u if c.y < 0 else d
		if side_x or side_y or not _is_open(lx + c.x, ly + c.y):
			continue
		var corner := Vector2(p.x if c.x < 0 else e.x, p.y if c.y < 0 else e.y)
		draw_polygon(PackedVector2Array([corner, corner + Vector2(-c.x * f, 0), corner + Vector2(0, -c.y * f)]),
			PackedColorArray([base, clear, clear]))
