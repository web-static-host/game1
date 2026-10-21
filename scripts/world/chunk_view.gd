class_name ChunkView
extends Node2D
## Отрисовка одного чанка. Стиль — мультяшный векторный: сочные цвета, мягкий объём
## (светлый верх, тёмный низ), скруглённые края туннелей и рельефа, без пиксельной сетки.
## Перерисовывается только при изменении (Godot кэширует команды _draw).

const SIZE := ChunkData.SIZE
const TILE := 32.0
const ROUND := 11.0
## Толщина почвенного слоя вдоль сглаженной поверхности, в клетках (целый блок:
## полоска в полклетки читалась как непонятная полоса).
const SOIL_BAND := 1.0
## Насколько глубоко (в долях клетки) видна порода от края выработки — целая клетка.
const FADE := 1.0
const NEIGHBORS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0)]
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const GRASS := Color(0.46, 0.84, 0.26)
const GRASS_DARK := Color(0.3, 0.66, 0.2)
const GRASS_HI := Color(0.69, 0.94, 0.38)
const GRASS_LIP := Color(0.24, 0.55, 0.19)
const SNOW := Color(0.96, 0.98, 1.0)
const SNOW_DARK := Color(0.75, 0.83, 0.93)
## Зимой трава под снегом (меняет WorldView.set_season).
static var snow := false
## Время года для листвы: месяцы от 1 января (0..12), меняет WorldView.set_season.
static var season_m := 4.5
## Неразведанная земля — тёплый землистый тон, как на прототипе (поверх — общая фактура
## почвы): что внутри, не видно, пока не вскопают.
const FOG_TOP := Color(0.51, 0.3, 0.18)
const FOG_DEEP := Color(0.36, 0.21, 0.15)
const FOG_HOT := Color(0.4, 0.22, 0.15)
## Задняя стенка выработки — тёплая тёмная.
const BACK := Color(0.23, 0.16, 0.16)

## Текстуры земли (assets/ground/, из art_src/ground/prepare.py): серая фактура почвы,
## красим цветом породы. Средняя яркость текстуры — ROCK_MEAN, поэтому цвет делим на неё.
const ROCK_MEAN := 0.7
## Период текстуры породы в пикселях мира; чанк (1024 px) — ровно 2 периода,
## поэтому координаты текстуры можно брать прямо из локальных координат чанка.
const ROCK_PERIOD := 512.0
## Кромка травы/снега: ширина картинки в пикселях мира и доля высоты, где линия земли.
const EDGE_PERIOD := 1024.0 / 3.0
const GRASS_LINE := 0.51
const SNOW_LINE := 0.45
## Фактура земли (assets/ground/fog.png): и неразведанная, и открытая порода — разным цветом.
static var _rock_tex: Array = []
static var _grass_tex: Texture2D
static var _snow_tex: Texture2D

var world: WorldData
var chunk: ChunkData


func setup(p_world: WorldData, p_chunk: ChunkData) -> void:
	world = p_world
	chunk = p_chunk
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _rock_tex.is_empty():
		for n in ["fog"]:
			_rock_tex.append(_load("res://assets/ground/%s.png" % n))
		_grass_tex = _load("res://assets/ground/grass_edge.png")
		_snow_tex = _load("res://assets/ground/snow_edge.png")


static func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## Какой текстурой рисовать породу m. Полосатые пласты автору не понравились — открытая порода
## той же мягкой фактурой, что и неразведанная земля, только своим цветом.
static func rock_tex_of(_m: int) -> int:
	return FOG


## Неразведанная земля («туман»): одна фактура на весь мир (assets/ground/fog.png),
## не зависит от того, что внутри, — по ней ничего не угадать. Пока картинки нет — заливка.
## Пласты пород рисуем только на открытой породе (кайма, выработки).
const FOG := 0


static func _tinted(col: Color) -> Color:
	return Color(col.r / ROCK_MEAN, col.g / ROCK_MEAN, col.b / ROCK_MEAN, col.a)


## Клетка (или её часть) земли текстурой ti, подкрашенной в col. Нет картинки — заливка.
func _fill_rect(r: Rect2, col: Color, ti: int) -> void:
	var t: Texture2D = _rock_tex[ti] if ti >= 0 and ti < _rock_tex.size() else null
	if t == null:
		draw_rect(r, col)
		return
	var k := t.get_width() / ROCK_PERIOD
	var src := Rect2(fposmod(r.position.x, ROCK_PERIOD) * k, fposmod(r.position.y, ROCK_PERIOD) * k, r.size.x * k, r.size.y * k)
	draw_texture_rect_region(t, r, src, _tinted(col))


func _fill_poly(pts: PackedVector2Array, col: Color, ti: int) -> void:
	var t: Texture2D = _rock_tex[ti] if ti >= 0 and ti < _rock_tex.size() else null
	if t == null:
		draw_colored_polygon(pts, col)
		return
	var uvs := PackedVector2Array()
	for q in pts:
		uvs.append(q / ROCK_PERIOD)
	draw_colored_polygon(pts, _tinted(col), uvs, t)


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
	# Почти однотонно: заметные оттенки по клеткам дают «квадраты».
	return c.lightened((v - 0.5) * 0.02) if v >= 0.5 else c.darkened((0.5 - v) * 0.02)


static func rock_color(m: int, v: float) -> Color:
	var c := Mat.color(m)
	if Mat.is_ore(m):
		c = c.lerp(Color(0.35, 0.33, 0.33), 0.65).darkened(0.15)
	# Мультяшнее: сочнее и светлее природного.
	c = Color.from_hsv(c.h, minf(1.0, c.s * 1.25 + 0.04), minf(1.0, c.v * 1.12 + 0.05))
	return c.lightened((v - 0.5) * 0.12) if v >= 0.5 else c.darkened((0.5 - v) * 0.12)


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
		# Почва под травой — тем же тоном, что и земля ниже: первый блок не отличается от остальных.
		var soil := fog_color(0, gen.tint(x, surf))
		for ly in SIZE:
			var y := y0 + ly
			if y < surf:
				if chunk.mat[ChunkData.idx(lx, ly)] == Mat.WATER:
					_draw_water(lx, ly, x, y)
				if not line.is_zero_approx() and y + 1 > minf(line.x, line.z):
					var sr := Rect2(lx * TILE, ly * TILE, TILE, TILE)
					_draw_clipped(lx, ly, line, fog_color(0, gen.tint(x, y)), FOG)
					for poly in Geometry2D.intersect_polygons(_band_poly(lx, ly, line), _rect_poly(sr)):
						_fill_poly(poly, soil, FOG)
				continue # небо рисует фон
			var i := ChunkData.idx(lx, ly)
			var f := chunk.flags[i]
			var m := chunk.mat[i]
			var v := gen.tint(x, y)
			var r := Rect2(lx * TILE, ly * TILE, TILE, TILE)
			var depth := y - surf
			if y < band_to and f & ChunkData.F_DUG == 0 and Mat.is_solid(m):
				# Что под травой — неизвестно: видна только полоса почвы в полблока.
				_draw_clipped(lx, ly, line, fog_color(depth, v), FOG)
				var band := _band_poly(lx, ly, line)
				for poly in Geometry2D.intersect_polygons(band, _rect_poly(r)):
					_fill_poly(poly, soil, FOG)
				if f & ChunkData.F_REVEALED:
					# Вскрытая порода — тоже только ниже линии земли, иначе торчат углы.
					var clip := clip_below(lx * TILE, ly * TILE, TILE, _line_px(ly, line))
					if clip.is_empty():
						clip = PackedVector2Array([Vector2.ZERO]) # клетка целиком над землёй — каймы нет
					if clip.size() >= 3:
						_fill_poly(clip, rock_color(m, v), rock_tex_of(m))
				if y == surf:
					if gen.water_level(x) >= surf and gen.planet["plants"]:
						_draw_smooth_grass(lx, ly, line, x)
				continue
			if f & ChunkData.F_REVEALED == 0:
				_fill_rect(r, fog_color(depth, v), FOG)
				continue
			var dug := f & ChunkData.F_DUG != 0
			if dug or m == Mat.AIR or Mat.is_fluid(m):
				_draw_open_cell(lx, ly, r, m, dug, depth, v)
				if dug and f & ChunkData.F_FLUID:
					_draw_fluid(lx, ly, r, chunk.fluid[i])
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
	var host := _ore_host(lx, ly) if Mat.is_ore(m) else m
	if dug:
		back = rock_color(host, v).darkened(0.62).lerp(BACK, 0.5)
	else:
		back = fog_color(depth, v).darkened(0.55)
	_fill_rect(r, back, rock_tex_of(host) if dug else FOG)
	# Мягкая тень под потолком.
	if dug and not _is_open(lx, ly - 1):
		draw_polygon(_rect_poly(Rect2(r.position, Vector2(TILE, 12))),
			PackedColorArray([Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	if Mat.is_fluid(m) and not dug:
		_draw_fluid(lx, ly, r, m)
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
		_fill_poly(_corner_fill(r, corner), col, _solid_tex(sx, ly))


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


## Текстура клетки по тем же правилам, что и цвет в _solid_color (туман — без текстуры).
func _solid_tex(lx: int, ly: int) -> int:
	var f := _flags_at(lx, ly)
	if f < 0 or f & ChunkData.F_REVEALED == 0:
		return FOG
	return rock_tex_of(_mat_at(lx, ly))


func _draw_solid_cell(lx: int, ly: int, r: Rect2, m: int, v: float, x: int, y: int, surf: int) -> void:
	var host := _ore_host(lx, ly) if Mat.is_ore(m) else m
	var base := rock_color(host, v)
	var ti := rock_tex_of(host)
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
	# Открытая порода — целым блоком и одинаково, у выработки и дальше (геологоразведка);
	# выступ между выработками, открытый с двух сторон, — со скруглёнными углами.
	if mask == 0:
		_fill_rect(r, base, ti)
	else:
		_fill_poly(_rounded_rect(r, mask), base, ti)

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
		# Кристалл: шестигранник с гранью-бликом.
		var rad := 3.0 + hr * 3.5
		var gem := PackedVector2Array()
		var ph := WorldGen.hash01(x, y, 400 + k) * TAU
		for j in 6:
			var a := ph + TAU * j / 6.0
			gem.append(p + Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(gem, Color(col.darkened(0.2), col.a))
		draw_colored_polygon(PackedVector2Array([gem[0], gem[1], gem[2], p]), Color(col.lightened(0.25), col.a))
		draw_circle(p + Vector2(-rad * 0.3, -rad * 0.35), rad * 0.22, Color(1, 1, 1, 0.7 * col.a))


static func _grass() -> Color:
	return SNOW if snow else GRASS


func _draw_grass(r: Rect2, x: int, mask: int) -> void:
	var left := r.position.x + (ROUND * 0.6 if mask & 1 else 0.0)
	var right := r.end.x - (ROUND * 0.6 if mask & 2 else 0.0)
	var y := r.position.y
	_grass_cap([Vector2(left, y), Vector2(right, y)], x)


## Шапка травы (или снега) вдоль ломаной: толстая полоса, светлая кромка сверху,
## тёмные фестоны снизу и пучки травинок.
func _grass_cap(line: Array, x: int) -> void:
	var tex := _snow_tex if snow else _grass_tex
	if tex != null:
		_edge_strip(line, tex, SNOW_LINE if snow else GRASS_LINE)
		return
	var top := _grass()
	var lip := SNOW_DARK if snow else GRASS_LIP
	var hi := Color.WHITE if snow else GRASS_HI
	var upper := PackedVector2Array()
	for p: Vector2 in line:
		upper.append(p)
	# Фестоны: нижний край волной.
	var lower := PackedVector2Array()
	var n := 4
	for i in range(n, -1, -1):
		var t := float(i) / n
		var p := _along(line, t)
		lower.append(p + Vector2(0, 9.0 + 3.0 * absf(sin((x * n + i) * 1.7))))
	var shade := upper.duplicate()
	for p in lower:
		shade.append(p + Vector2(0, 3))
	draw_colored_polygon(shade, lip)
	var body := upper.duplicate()
	body.append_array(lower)
	draw_colored_polygon(body, top)
	var hl := PackedVector2Array()
	for p: Vector2 in line:
		hl.append(p + Vector2(0, 2.5))
	draw_polyline(hl, hi, 2.5)
	if snow:
		return
	for k in 4:
		var t := (k + 0.5) / 4.0
		var p := _along(line, t)
		var hgt := 5.0 + WorldGen.hash01(x, k, 400) * 7.0
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-3, 1), p + Vector2(3, 1),
			p + Vector2(WorldGen.hash01(x, k, 401) * 5.0 - 2.5, -hgt),
		]), GRASS_DARK if k % 2 else GRASS_HI)


## Кромка-картинка вдоль ломаной: линия земли на доле высоты at, по x — непрерывно
## по всему миру (координата от начала чанка + сам чанк), поэтому стыков нет.
func _edge_strip(line: Array, tex: Texture2D, at: float) -> void:
	var h := EDGE_PERIOD * tex.get_height() / tex.get_width()
	var up := Vector2(0, h * at)
	var down := Vector2(0, h * (1.0 - at))
	var base := fposmod(chunk.cx * SIZE * TILE, EDGE_PERIOD)
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var ua := (base + a.x) / EDGE_PERIOD
		var ub := ua + (b.x - a.x) / EDGE_PERIOD
		# v чуть внутри [0, 1]: при повторе текстуры верх не подмешивается к низу.
		draw_colored_polygon(PackedVector2Array([a - up, b - up, b + down, a + down]), Color.WHITE,
			PackedVector2Array([Vector2(ua, 0.004), Vector2(ub, 0.004), Vector2(ub, 0.996), Vector2(ua, 0.996)]), tex)


## Точка на ломаной по доле длины по x.
static func _along(line: Array, t: float) -> Vector2:
	var a: Vector2 = line[0]
	var b: Vector2 = line[line.size() - 1]
	var x := lerpf(a.x, b.x, t)
	for i in line.size() - 1:
		var p: Vector2 = line[i]
		var q: Vector2 = line[i + 1]
		if x <= q.x + 0.001:
			return p.lerp(q, clampf((x - p.x) / maxf(0.001, q.x - p.x), 0.0, 1.0))
	return b


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


const TRUNK := Color(0.59, 0.38, 0.23)
const TRUNK_DARK := Color(0.4, 0.25, 0.16)
const LEAF_SPRING := Color(0.62, 0.88, 0.32)
const LEAF_SUMMER := Color(0.31, 0.75, 0.28)
const LEAF_YELLOW := Color(0.98, 0.78, 0.2)
const LEAF_RED := Color(0.9, 0.33, 0.16)
const SPRUCE := Color(0.16, 0.5, 0.33)
const SPRUCE_LIGHT := Color(0.27, 0.64, 0.42)
const BOULDER := Color(0.6, 0.63, 0.72)
const MARK := Color(1.0, 0.82, 0.25)


## Ёлка или лиственное — у каждого места своё, навсегда.
static func is_spruce(x: int) -> bool:
	return WorldGen.hash01(x, 77, 0) < 0.35


## Листва лиственного дерева по времени года: [доля листвы 0..1, цвет].
## Весной листья распускаются, летом зелёные, осенью желтеют (местами краснеют)
## и опадают, зимой ветки голые. У каждого дерева чуть свой срок.
static func foliage(x: int) -> Array:
	var m := fposmod(season_m - (WorldGen.hash01(x, 78, 0) - 0.5) * 0.6, 12.0)
	var autumn := LEAF_RED if WorldGen.hash01(x, 79, 0) < 0.3 else LEAF_YELLOW.lerp(Color(0.95, 0.55, 0.15), WorldGen.hash01(x, 80, 0) * 0.5)
	if m < 2.5:
		return [0.0, LEAF_SPRING]
	if m < 3.5:
		return [lerpf(0.0, 0.35, m - 2.5), LEAF_SPRING]
	if m < 4.5:
		return [lerpf(0.35, 1.0, m - 3.5), LEAF_SPRING.lerp(LEAF_SUMMER, m - 3.5)]
	if m < 8.0:
		return [1.0, LEAF_SUMMER]
	if m < 9.0:
		return [1.0, LEAF_SUMMER.lerp(autumn, m - 8.0)]
	if m < 10.5:
		return [lerpf(1.0, 0.2, (m - 9.0) / 1.5), autumn]
	if m < 11.0:
		return [lerpf(0.2, 0.0, (m - 10.5) * 2.0), autumn.darkened(0.15)]
	return [0.0, autumn]


## foot — точка на земле под объектом.
func _draw_feature(f: int, x: int, foot: Vector2) -> void:
	var marked := world.feature_marks.has(x)
	var gen := world.gen
	if f == WorldGen.FEATURE_TREE:
		# Молодое дерево ниже и с маленькой кроной.
		var g := world.growth(x)
		var h := gen.tree_height(x) * TILE * (0.25 + 0.75 * g)
		var top := Vector2.ZERO
		if is_spruce(x):
			top = _draw_spruce(x, foot, h, g)
		else:
			top = _draw_leafy(x, foot, h, g)
		if marked:
			_draw_mark(top + Vector2(0, -TILE * 0.6))
	elif f == WorldGen.FEATURE_BOULDER:
		var w := TILE * (0.8 + WorldGen.hash01(x, 31, 0) * 0.5)
		var hh := TILE * (0.55 + WorldGen.hash01(x, 32, 0) * 0.3)
		var pts := PackedVector2Array()
		for k in 11:
			var a := PI + k * PI / 10.0
			var wob := 1.0 + 0.08 * sin(a * 3.0 + x)
			pts.append(foot + Vector2(cos(a) * w * 0.5 * wob, sin(a) * hh * wob))
		var shade := PackedVector2Array()
		for p in pts:
			shade.append(p + Vector2(0, 3))
		draw_colored_polygon(shade, BOULDER.darkened(0.35))
		draw_colored_polygon(pts, BOULDER)
		draw_circle(foot + Vector2(-w * 0.15, -hh * 0.62), hh * 0.24, BOULDER.lightened(0.3))
		if snow:
			_snow_cap(foot + Vector2(0, -hh * 0.92), w * 0.4, hh * 0.22)
		if marked:
			_draw_mark(foot + Vector2(0, -hh - TILE * 0.7))
	elif f == WorldGen.FEATURE_BUSH:
		var bw := TILE * (0.55 + WorldGen.hash01(x, 33, 0) * 0.2)
		var fol := foliage(x)
		var leaves: float = maxf(0.35, fol[0])
		var col: Color = fol[1] if fol[0] > 0.0 else Color(0.45, 0.4, 0.3)
		var parts := [Vector2(-0.55, -0.5), Vector2(0.55, -0.5), Vector2(0.0, -0.85)]
		for p in parts:
			draw_circle(foot + p * bw + Vector2(0, 3), bw * 0.58 * leaves, col.darkened(0.3))
		for p in parts:
			draw_circle(foot + p * bw, bw * 0.58 * leaves, col)
		draw_circle(foot + Vector2(-0.3, -1.0) * bw, bw * 0.22 * leaves, col.lightened(0.3))
		# Ягоды видно по количеству: съели — куст пустой, потом отрастают.
		for k in mini(6, floori(world.berries(x))):
			var bp := foot + Vector2((WorldGen.hash01(x, 40 + k, 0) - 0.5) * bw * 1.6, -bw * (0.3 + WorldGen.hash01(x, 50 + k, 0) * 0.7))
			draw_circle(bp, 3.6, Color(0.6, 0.06, 0.18))
			draw_circle(bp, 3.0, Color(0.92, 0.16, 0.27))
			draw_circle(bp + Vector2(-1, -1), 1.0, Color(1, 1, 1, 0.8))
		if snow:
			_snow_cap(foot + Vector2(0, -bw * 1.3 * leaves), bw * 0.6, bw * 0.2)
		if marked:
			_draw_mark(foot + Vector2(0, -bw * 1.6 - TILE * 0.4))


## Лиственное: ствол с сужением, крона из шаров (светлый верх, тёмный низ) или голые ветки.
## Возвращает верх кроны.
func _draw_leafy(x: int, foot: Vector2, h: float, g: float) -> Vector2:
	var lean := (WorldGen.hash01(x, 21, 0) - 0.5) * 8.0
	var tw := 5.0 + 2.0 * g
	var top := foot + Vector2(lean, -h * 0.72)
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-tw, 0), foot + Vector2(tw, 0),
		top + Vector2(tw * 0.5, 0), top + Vector2(-tw * 0.5, 0)]), TRUNK)
	draw_line(foot + Vector2(-tw * 0.3, -4), top + Vector2(-tw * 0.2, 4), Color(1, 1, 1, 0.15), 2.0)
	var r := TILE * (0.9 + WorldGen.hash01(x, 22, 0) * 0.5) * (0.35 + 0.65 * g)
	var fol := foliage(x)
	var leaves: float = fol[0]
	var col: Color = fol[1]
	# Ветки видны, пока листвы мало.
	if leaves < 0.7:
		var bc := Color(TRUNK_DARK, clampf((0.7 - leaves) * 2.5, 0.0, 1.0))
		for k in 4:
			var a := -PI * 0.5 + (k - 1.5) * 0.55 + (WorldGen.hash01(x, 90 + k, 0) - 0.5) * 0.3
			var from := top + Vector2(0, r * 0.25 - k * 3.0)
			var to := from + Vector2(cos(a), sin(a)) * r * (0.75 + WorldGen.hash01(x, 95 + k, 0) * 0.35)
			draw_line(from, to, bc, 3.0 if k % 3 == 0 else 2.0)
			var tw2 := to + Vector2(cos(a - 0.6), sin(a - 0.6)) * r * 0.3
			draw_line(from.lerp(to, 0.6), tw2, bc, 1.5)
			if snow and leaves <= 0.01:
				# Снег на ветках.
				draw_line(from + Vector2(0, -2), to + Vector2(0, -2), SNOW, 2.5)
				draw_circle(to + Vector2(0, -1.5), 2.2, SNOW)
	if leaves > 0.01:
		var parts := [[Vector2(-0.55, 0.15), 0.62], [Vector2(0.55, 0.2), 0.6], [Vector2(0.0, -0.4), 0.78], [Vector2(-0.25, 0.4), 0.55], [Vector2(0.3, 0.45), 0.55]]
		var shown := clampi(ceili(leaves * parts.size()), 1, parts.size())
		var k_r := 0.45 + 0.55 * leaves
		for i in shown:
			var p: Array = parts[i]
			draw_circle(top + (p[0] as Vector2) * r + Vector2(0, r * 0.14), r * float(p[1]) * k_r, col.darkened(0.28))
		for i in shown:
			var p: Array = parts[i]
			draw_circle(top + (p[0] as Vector2) * r, r * float(p[1]) * k_r, col)
		for i in shown:
			var p: Array = parts[i]
			draw_circle(top + (p[0] as Vector2) * r + Vector2(-0.2, -0.25) * r, r * float(p[1]) * k_r * 0.42, col.lightened(0.25))
	return top + Vector2(0, -r)


## Ёлка: ярусы-треугольники, светлый бок, зимой — снежные шапки.
func _draw_spruce(x: int, foot: Vector2, h: float, g: float) -> Vector2:
	var tw := 4.0 + 2.0 * g
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-tw, 0), foot + Vector2(tw, 0),
		foot + Vector2(tw * 0.6, -h * 0.3), foot + Vector2(-tw * 0.6, -h * 0.3)]), TRUNK)
	var w := TILE * (0.85 + WorldGen.hash01(x, 24, 0) * 0.3) * (0.4 + 0.6 * g)
	var tiers := 3 if g > 0.5 else 2
	var bottom := foot.y - h * 0.18
	var peak := foot.y - h * 1.05
	var step := (bottom - peak) / (tiers + 0.6)
	for i in tiers:
		var ty := bottom - i * step
		var hw := w * (1.0 - i * 0.24)
		var apex := Vector2(foot.x, ty - step * 1.55)
		var tri := PackedVector2Array([Vector2(foot.x - hw, ty), Vector2(foot.x + hw, ty), apex])
		var sh := PackedVector2Array([Vector2(foot.x - hw, ty + 3), Vector2(foot.x + hw, ty + 3), apex + Vector2(0, 3)])
		draw_colored_polygon(sh, SPRUCE.darkened(0.35))
		draw_colored_polygon(tri, SPRUCE)
		draw_colored_polygon(PackedVector2Array([Vector2(foot.x - hw, ty), Vector2(foot.x - hw * 0.15, ty), apex]), SPRUCE_LIGHT)
		if snow:
			# Снег лежит на ярусе сверху.
			draw_colored_polygon(PackedVector2Array([apex, apex.lerp(Vector2(foot.x - hw, ty), 0.45),
				apex.lerp(Vector2(foot.x - hw, ty), 0.45) + Vector2(hw * 0.25, 3), apex + Vector2(0, step * 0.35),
				apex.lerp(Vector2(foot.x + hw, ty), 0.45) + Vector2(-hw * 0.25, 3), apex.lerp(Vector2(foot.x + hw, ty), 0.45)]), SNOW)
	return Vector2(foot.x, peak)


## Снежная шапка — приплюснутый эллипс.
func _snow_cap(c: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var a := PI + k * PI / 13.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	for k in 5:
		var a := k * PI / 4.0
		pts.append(c + Vector2(cos(a) * rx * (1.0 - k * 0.0), sin(a) * ry * 0.35))
	draw_colored_polygon(pts, SNOW)


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
func _draw_clipped(lx: int, ly: int, line: Vector3, col: Color, ti: int) -> void:
	var pts := clip_below(lx * TILE, ly * TILE, TILE, _line_px(ly, line))
	if pts.size() >= 3:
		_fill_poly(pts, col, ti)


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
	var x0 := lx * TILE
	_grass_cap([Vector2(x0, l.x), Vector2(x0 + TILE * 0.5, l.y), Vector2(x0 + TILE, l.z)], x)


func _band_poly(lx: int, ly: int, line: Vector3) -> PackedVector2Array:
	var l := _line_px(ly, line)
	var d := SOIL_BAND * TILE
	var x0 := lx * TILE
	return PackedVector2Array([
		Vector2(x0, l.x), Vector2(x0 + TILE * 0.5, l.y), Vector2(x0 + TILE, l.z),
		Vector2(x0 + TILE, l.z + d), Vector2(x0 + TILE * 0.5, l.y + d), Vector2(x0, l.x + d)])


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Выработка или пещера (не небо).
func _is_hole(lx: int, ly: int) -> bool:
	var f := _flags_at(lx, ly)
	return f >= 0 and f & (ChunkData.F_DUG | ChunkData.F_CAVE) != 0 and _is_open(lx, ly)



const LAVA := Color(0.95, 0.38, 0.1)
const LAVA_HOT := Color(1.0, 0.82, 0.3)


## Вода или лава в выработке; у верхней кромки — светлая гладь.
func _draw_fluid(lx: int, ly: int, r: Rect2, m: int) -> void:
	var top := _mat_at(lx, ly - 1) != m
	if m == Mat.MAGMA:
		draw_rect(r, LAVA)
		var x := chunk.cx * SIZE + lx
		var y := chunk.cy * SIZE + ly
		for k in 3:
			var p := r.position + Vector2(4 + WorldGen.hash01(x, y, 500 + k) * (TILE - 8), 4 + WorldGen.hash01(x, y, 510 + k) * (TILE - 8))
			draw_circle(p, 2.5 + WorldGen.hash01(x, y, 520 + k) * 3.0, LAVA_HOT)
		if top:
			draw_rect(Rect2(r.position, Vector2(TILE, 5)), LAVA_HOT)
		return
	draw_rect(r, Mat.color(Mat.WATER).lightened(0.05))
	if top:
		draw_rect(Rect2(r.position, Vector2(TILE, 5)), WATER_TOP)


const WATER_DEEP := Color(0.22, 0.56, 0.92, 0.94)
const WATER_TOP := Color(0.55, 0.82, 1.0, 0.98)


## Вода озера. Верхний ряд — светлая гладь с бликами.
func _draw_water(lx: int, ly: int, x: int, y: int) -> void:
	var r := Rect2(lx * TILE, ly * TILE, TILE, TILE)
	var top := y == world.gen.water_level(x)
	var deep := WATER_DEEP.lerp(Color(0.12, 0.34, 0.72, 0.96), clampf((y - world.gen.water_level(x)) / 20.0, 0.0, 1.0))
	if snow:
		deep = Color(0.78, 0.88, 0.97) if top else deep.lerp(Color(0.6, 0.75, 0.9), 0.4)
	draw_rect(r, deep)
	if top:
		draw_rect(Rect2(r.position.x, r.position.y, TILE, 5), WATER_TOP if not snow else Color.WHITE)
		if snow:
			# Лёд: блики-трещины.
			if WorldGen.hash01(x, 3, 91) < 0.4:
				draw_line(Vector2(r.position.x + 6, r.position.y + 10), Vector2(r.position.x + 22, r.position.y + 18), Color(1, 1, 1, 0.8), 2.0)
			return
		if WorldGen.hash01(x, 3, 90) < 0.35:
			var bx := r.position.x + 6 + WorldGen.hash01(x, 4, 90) * 14
			draw_line(Vector2(bx, r.position.y + 9), Vector2(bx + 8, r.position.y + 9), Color(1, 1, 1, 0.35), 2.0)
