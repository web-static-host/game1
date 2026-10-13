extends Node2D
## Превью нового оформления: мир в разрезе и интерфейс в мультяшном стиле
## (Brawl Stars / Clash Royale). sheet: 0 — лето, 1 — зима и темнота, 2 — интерфейс.

var sheet := 0
var winter := false

const INK := Color8(27, 31, 58)          # тёмно-синяя обводка интерфейса
const SKY_TOP := Color8(52, 156, 240)
const SKY_LOW := Color8(178, 228, 255)
const GRASS := Color8(118, 214, 66)
const GRASS_HI := Color8(176, 240, 96)
const GRASS_LO := Color8(62, 150, 48)
const SNOW := Color8(246, 250, 255)
const SNOW_LO := Color8(190, 212, 238)
const LAYERS := [
	# [низ слоя, цвет, светлый, тёмный]
	[420.0, Color8(176, 112, 66), Color8(204, 142, 88), Color8(128, 76, 46)],     # почва
	[540.0, Color8(214, 140, 78), Color8(236, 172, 104), Color8(160, 96, 52)],    # глина
	[700.0, Color8(132, 140, 164), Color8(166, 176, 198), Color8(92, 98, 124)],   # камень
	[2000.0, Color8(96, 88, 132), Color8(126, 118, 166), Color8(64, 58, 96)],    # гранит
]
const BACK := Color8(58, 40, 40)           # задняя стенка выработки
const TILE := 40.0

var _font: FontFile
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_font = FontFile.new()
	_font.load_dynamic_font("/usr/share/fonts/opentype/inter/Inter-Black.otf")


func _draw() -> void:
	var size := get_viewport_rect().size
	_rng.seed = 7
	match sheet:
		0:
			winter = false
			_scene(size)
		1:
			winter = true
			_scene(size)
		_:
			_ui_sheet(size)


# --- Мир ------------------------------------------------------------------------------------

func _sy(x: float) -> float:
	return 330.0 + 16.0 * sin(x / 260.0) + 9.0 * sin(x / 97.0 + 1.0)


func _layer_y(i: int, x: float) -> float:
	var y0: float = LAYERS[i][0]
	return y0 + 10.0 * sin(x / 140.0 + i * 1.7) + 6.0 * sin(x / 53.0 + i)


func _scene(size: Vector2) -> void:
	_sky(size)
	_hills(size)
	_ground(size)
	_ores()
	_pond()
	_underground(size)
	_trees()
	_surface_buildings()
	if winter:
		_snowfall(size)
	_creatures()
	_darkness()
	_hud(size)


func _sky(size: Vector2) -> void:
	var top := SKY_TOP if not winter else Color8(126, 164, 206)
	var low := SKY_LOW if not winter else Color8(222, 232, 242)
	_grad_rect(Rect2(Vector2.ZERO, Vector2(size.x, 420)), top, low)
	# Солнце.
	var sun := Vector2(size.x - 330, 120)
	for i in 6:
		draw_circle(sun, 120 - i * 16, Color(1, 0.95, 0.7, 0.07 if not winter else 0.05))
	draw_circle(sun, 46, Color8(255, 226, 96) if not winter else Color8(255, 246, 214))
	draw_circle(sun + Vector2(-12, -12), 18, Color(1, 1, 1, 0.35))
	# Облака.
	for c in [[Vector2(260, 110), 1.0], [Vector2(760, 70), 0.8], [Vector2(1250, 150), 1.15], [Vector2(1820, 220), 0.7]]:
		_cloud(c[0], c[1])


func _cloud(at: Vector2, k: float) -> void:
	var parts := [[Vector2(-60, 10), 34], [Vector2(-20, -12), 44], [Vector2(30, -4), 38], [Vector2(70, 12), 28], [Vector2(5, 16), 34]]
	var shade := Color8(196, 220, 246) if not winter else Color8(200, 208, 222)
	for p in parts:
		draw_circle(at + p[0] * k + Vector2(0, 8 * k), p[1] * k, shade)
	for p in parts:
		draw_circle(at + p[0] * k, p[1] * k, Color.WHITE)


func _hills(size: Vector2) -> void:
	var far := Color8(150, 210, 140) if not winter else Color8(214, 226, 238)
	var near := Color8(120, 196, 110) if not winter else Color8(232, 240, 248)
	for layer in [[far, 250.0, 0.0, 300.0], [near, 285.0, 2.0, 210.0]]:
		var pts := PackedVector2Array()
		var x := -20.0
		while x <= size.x + 20:
			pts.append(Vector2(x, layer[1] + 28.0 * sin(x / layer[3] + layer[2]) + 14.0 * sin(x / 70.0 + layer[2])))
			x += 20
		pts.append(Vector2(size.x + 20, 420))
		pts.append(Vector2(-20, 420))
		draw_colored_polygon(pts, layer[0])


func _ground(size: Vector2) -> void:
	# Слои снизу вверх: каждый — от своей волнистой кромки вниз до низа экрана.
	for i in LAYERS.size():
		var pts := PackedVector2Array()
		var x := -20.0
		while x <= size.x + 20:
			pts.append(Vector2(x, _sy(x) if i == 0 else _layer_y(i - 1, x)))
			x += 10
		pts.append(Vector2(size.x + 20, size.y + 20))
		pts.append(Vector2(-20, size.y + 20))
		draw_colored_polygon(pts, LAYERS[i][1])
		# Тёмная кромка по границе слоя.
		if i > 0:
			var edge := PackedVector2Array()
			x = -20.0
			while x <= size.x + 20:
				edge.append(Vector2(x, _layer_y(i - 1, x)))
				x += 10
			draw_polyline(edge, LAYERS[i][3], 5.0, true)
			_edge_highlight(edge, LAYERS[i][2])
		# Камешки в толще слоя.
		var top := 340.0 if i == 0 else float(LAYERS[i - 1][0])
		var bottom := minf(float(LAYERS[i][0]), size.y)
		for n in int((bottom - top) * size.x / 9000.0):
			var p := Vector2(_rng.randf_range(0, size.x), _rng.randf_range(top + 20, bottom - 10))
			if p.y < _sy(p.x) + 22:
				continue
			_pebble(p, _rng.randf_range(5, 13), LAYERS[i][3], LAYERS[i][2])
	# Трава (или снег) — толстая шапка с бликом и фестонами.
	var cap := PackedVector2Array()
	var lip := PackedVector2Array()
	var x2 := -20.0
	while x2 <= size.x + 20:
		cap.append(Vector2(x2, _sy(x2) - 4))
		x2 += 8
	for i in range(cap.size() - 1, -1, -1):
		var p := cap[i]
		lip.append(Vector2(p.x, p.y + 22 + 7.0 * absf(sin(p.x / 18.0))))
	var body := cap.duplicate()
	body.append_array(lip)
	var top_col := GRASS if not winter else SNOW
	var lo_col := GRASS_LO if not winter else SNOW_LO
	var hi_col := GRASS_HI if not winter else Color.WHITE
	var shadow := PackedVector2Array()
	for p in lip:
		shadow.append(p + Vector2(0, 6))
	var sh := cap.duplicate()
	sh.append_array(shadow)
	draw_colored_polygon(sh, lo_col)
	draw_colored_polygon(body, top_col)
	var hi := PackedVector2Array()
	for p in cap:
		hi.append(p + Vector2(0, 4))
	draw_polyline(hi, hi_col, 5.0, true)
	if not winter:
		# Пучки травы.
		for n in 140:
			var gx := _rng.randf_range(0, size.x)
			var gy := _sy(gx) - 3
			var hgt := _rng.randf_range(8, 16)
			draw_colored_polygon(PackedVector2Array([Vector2(gx - 4, gy), Vector2(gx + 4, gy), Vector2(gx + _rng.randf_range(-3, 3), gy - hgt)]),
				GRASS_HI if n % 2 else GRASS)


func _edge_highlight(edge: PackedVector2Array, col: Color) -> void:
	var hi := PackedVector2Array()
	for p in edge:
		hi.append(p + Vector2(0, 5))
	draw_polyline(hi, Color(col, 0.6), 3.0, true)


func _pebble(c: Vector2, r: float, dark: Color, light: Color) -> void:
	var pts := _blob(c, r, Vector2(1.25, 0.85))
	draw_colored_polygon(_shift(pts, Vector2(0, 2)), Color(dark, 0.9))
	draw_colored_polygon(pts, light.lerp(dark, 0.35))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 1, 1, 0.25))


func _ores() -> void:
	# Уголь, железо, медь, кристалл — кучками в толще.
	var kinds := [[Vector2(300, 620), Color8(44, 44, 54), Color8(110, 110, 128)], [Vector2(1500, 640), Color8(190, 104, 70), Color8(242, 170, 128)],
		[Vector2(1720, 720), Color8(66, 178, 146), Color8(150, 240, 210)], [Vector2(1800, 500), Color8(44, 44, 54), Color8(110, 110, 128)],
		[Vector2(420, 740), Color8(150, 92, 230), Color8(214, 176, 255)]]
	for k in kinds:
		for n in 6:
			var c: Vector2 = k[0] + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-22, 22))
			var r := _rng.randf_range(8, 15)
			var pts := _gem(c, r)
			draw_colored_polygon(_shift(pts, Vector2(0, 3)), Color(0, 0, 0, 0.3))
			draw_colored_polygon(pts, k[1])
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c]), k[2])
			draw_circle(c + Vector2(-r * 0.25, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.7))


func _pond() -> void:
	# Пруд слева с пристанью.
	var x0 := 40.0
	var x1 := 360.0
	var y := _sy(200) + 4
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(Vector2(lerpf(x0, x1, t), y + sin(t * PI) * 70.0))
	var water_hi := Color8(96, 196, 255) if not winter else Color8(214, 236, 252)
	var water_lo := Color8(40, 118, 214) if not winter else Color8(160, 196, 232)
	var poly := PackedVector2Array([Vector2(x0, y - 6)])
	poly.append_array(pts)
	poly.append(Vector2(x1, y - 6))
	var cols := PackedColorArray()
	for p in poly:
		cols.append(water_hi.lerp(water_lo, clampf((p.y - y) / 70.0, 0, 1)))
	draw_polygon(poly, cols)
	draw_polyline(poly, Color8(126, 82, 52), 6.0, true)
	if winter:
		# Лёд: блики-трещины.
		for i in 4:
			var a := Vector2(x0 + 50 + i * 70, y + 4)
			draw_line(a, a + Vector2(30, 14), Color(1, 1, 1, 0.8), 3.0, true)
	else:
		for i in 3:
			draw_line(Vector2(x0 + 60 + i * 80, y + 10), Vector2(x0 + 100 + i * 80, y + 10), Color(1, 1, 1, 0.55), 4.0, true)
	# Пристань.
	var px := x1 - 150
	var deck := Rect2(px, y - 16, 160, 14)
	for i in 3:
		_rect(Rect2(px + 12 + i * 60, y - 4, 10, 60), Color8(110, 70, 44))
	_rrect(deck, 4, Color8(186, 128, 78), Color8(110, 70, 44), 3.0)
	for i in 5:
		draw_line(Vector2(px + 32 * i + 10, y - 15), Vector2(px + 32 * i + 10, y - 3), Color8(140, 94, 58), 2.0)


func _underground(size: Vector2) -> void:
	var shaft := Rect2(900, _sy(920) + 10, 44, 420)
	var home := Rect2(944, 420, 300, 120)
	var tunnel := Rect2(560, 460, 340, 80)
	var farm := Rect2(600, 590, 300, 120)
	var lab := Rect2(944, 590, 300, 120)
	# Полости: задняя стенка, внутренняя тень сверху, кромка породы вокруг.
	for r in [shaft, home, tunnel, farm, lab]:
		_cavity(r)
	# Шахта: лестница и деревянная крепь.
	_ladder(Rect2(shaft.position.x + 6, shaft.position.y - 10, 32, shaft.size.y))
	# Тоннель влево: крепь — деревянные рамы.
	for i in 4:
		var fx := tunnel.position.x + 40 + i * 80
		_rect(Rect2(fx, tunnel.position.y, 10, tunnel.size.y), Color8(150, 98, 58))
		_rect(Rect2(fx - 10, tunnel.position.y, 30, 10), Color8(176, 116, 70))
	# Комнаты.
	_room_home(home)
	_room_farm(farm)
	_room_lab(lab)
	# Свет: солнце в шахте сверху, лампа в лаборатории (электричество), грибы фермы.
	_light(Vector2(shaft.get_center().x, shaft.position.y + 20), 140, Color(1, 0.95, 0.75, 0.22))
	_light(Vector2(lab.position.x + 150, lab.position.y + 18), 170, Color(1, 0.86, 0.45, 0.3))
	_lamp(Vector2(lab.position.x + 150, lab.position.y + 6))
	_light(Vector2(farm.get_center().x, farm.end.y - 30), 160, Color(0.55, 1.0, 0.7, 0.22))
	# Плашка стройки: заложенная комната с нехваткой дерева.
	var plan := Rect2(1258, 420, 300, 120)
	_dashed_rect(plan, Color(1, 0.86, 0.3), 6.0)
	_pill(Vector2(plan.get_center().x - 58, plan.position.y - 22), "3/6", "wood", Color8(214, 64, 52))
	_pill(Vector2(plan.get_center().x + 26, plan.position.y - 22), "8/8", "stone", Color8(62, 150, 70))


## Тьма поверх жителей: где нет света, всё тонет в синеватом мраке.
func _darkness() -> void:
	var dark := Color(0.03, 0.02, 0.1, 0.78)
	var tunnel := Rect2(560, 460, 340, 80).grow(2)
	# От шахты (свет солнца) к забою — темнее.
	var a := Color(dark, 0.0)
	draw_polygon(PackedVector2Array([tunnel.position, Vector2(tunnel.end.x, tunnel.position.y), tunnel.end, Vector2(tunnel.position.x, tunnel.end.y)]),
		PackedColorArray([dark, a, a, dark]))
	# Блеск глаз копателя в темноте.
	draw_circle(Vector2(660, 497), 3, Color(1, 1, 0.8, 0.9))
	_chip(Vector2(590, 420), "темно ×0,7", Color8(255, 196, 80))
	if winter:
		# Зима: генератор не построен — в жилой полумрак.
		var home := Rect2(944, 420, 300, 120)
		_rrect(home, 10, Color(0.03, 0.02, 0.1, 0.45), Color(0, 0, 0, 0), 0)
		_chip(Vector2(1110, 380), "холодно +4 °C", Color8(140, 200, 255))


func _cavity(r: Rect2) -> void:
	_rrect(r.grow(7), 14, Color8(70, 46, 38), Color(0, 0, 0, 0), 0)
	_grad_rect_r(r, BACK.lightened(0.08), BACK.darkened(0.25), 10)
	# Внутренняя тень сверху.
	_grad_rect_r(Rect2(r.position, Vector2(r.size.x, 18)), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 10)
	# Пол.
	_rrect(Rect2(r.position.x, r.end.y - 10, r.size.x, 10), 4, Color8(120, 82, 58), Color(0, 0, 0, 0), 0)


func _ladder(r: Rect2) -> void:
	var c := Color8(196, 140, 84)
	var d := Color8(120, 78, 44)
	for x in [r.position.x, r.end.x - 6]:
		_rect(Rect2(x + 1, r.position.y, 6, r.size.y), d)
		_rect(Rect2(x, r.position.y, 6, r.size.y), c)
	var y := r.position.y + 14
	while y < r.end.y:
		_rect(Rect2(r.position.x, y + 2, r.size.x, 5), d)
		_rect(Rect2(r.position.x, y, r.size.x, 5), c)
		y += 24


func _room_home(r: Rect2) -> void:
	# Стены — доски.
	for i in int(r.size.y / 20):
		var y := r.position.y + i * 20
		_rect(Rect2(r.position.x, y, r.size.x, 19), Color8(178, 122, 74) if i % 2 else Color8(190, 134, 84))
	_grad_rect_r(Rect2(r.position, Vector2(r.size.x, 22)), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0)
	_rect(Rect2(r.position.x, r.end.y - 12, r.size.x, 12), Color8(126, 80, 50))
	# Кровати с пухлыми одеялами.
	for i in 2:
		var b := Rect2(r.position.x + 30 + i * 140, r.end.y - 46, 100, 34)
		_rrect(Rect2(b.position + Vector2(0, 14), Vector2(b.size.x, 20)), 6, Color8(130, 84, 52), INK, 0)
		_rrect(Rect2(b.position + Vector2(4, 4), Vector2(30, 16)), 8, Color.WHITE, Color(0, 0, 0, 0), 0)
		_rrect(Rect2(b.position + Vector2(30, 0), Vector2(70, 24)), 10, [Color8(80, 150, 240), Color8(240, 100, 140)][i], Color(0, 0, 0, 0), 0)
		draw_line(b.position + Vector2(36, 6), b.position + Vector2(92, 6), Color(1, 1, 1, 0.4), 3.0)
	# Картина и полка.
	_rrect(Rect2(r.end.x - 70, r.position.y + 26, 44, 32), 4, Color8(120, 200, 255), Color8(110, 70, 44), 4)
	draw_circle(Vector2(r.end.x - 40, r.position.y + 36), 6, Color8(255, 226, 96))


func _room_farm(r: Rect2) -> void:
	# Грядки с грибами, светятся.
	for i in 3:
		var bed := Rect2(r.position.x + 18 + i * 94, r.end.y - 34, 80, 24)
		_rrect(bed, 6, Color8(108, 70, 46), Color8(70, 44, 30), 3)
		for j in 3:
			var c := bed.position + Vector2(14 + j * 26, 2)
			var col: Color = [Color8(255, 120, 90), Color8(255, 200, 80), Color8(150, 110, 255)][(i + j) % 3]
			_rect(Rect2(c.x - 3, c.y - 12, 6, 14), Color8(246, 236, 214))
			draw_circle(c + Vector2(0, -14), 13, Color(col, 0.25))
			_mushroom_cap(c + Vector2(0, -14), 11, col)
	# Трубы полива.
	_rect(Rect2(r.position.x + 10, r.position.y + 14, r.size.x - 20, 8), Color8(110, 130, 150))
	for i in 3:
		draw_circle(Vector2(r.position.x + 60 + i * 94, r.position.y + 26), 4, Color8(120, 210, 255))


func _mushroom_cap(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.8))
	draw_colored_polygon(pts, col)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.75))
	draw_circle(c + Vector2(r * 0.3, -r * 0.25), r * 0.13, Color(1, 1, 1, 0.6))


func _room_lab(r: Rect2) -> void:
	_rect(Rect2(r.position.x, r.end.y - 12, r.size.x, 12), Color8(90, 96, 120))
	# Стол с колбами.
	var t := Rect2(r.position.x + 40, r.end.y - 50, 150, 12)
	_rrect(t, 4, Color8(170, 176, 196), INK, 0)
	_rect(Rect2(t.position.x + 8, t.end.y, 8, 26), Color8(120, 126, 150))
	_rect(Rect2(t.end.x - 16, t.end.y, 8, 26), Color8(120, 126, 150))
	for i in 3:
		var c := Vector2(t.position.x + 30 + i * 46, t.position.y - 2)
		var col: Color = [Color8(110, 240, 140), Color8(120, 200, 255), Color8(255, 110, 200)][i]
		draw_circle(c + Vector2(0, -12), 13, Color8(220, 240, 255))
		draw_circle(c + Vector2(0, -10), 10, col)
		_rect(Rect2(c.x - 4, c.y - 34, 8, 14), Color8(220, 240, 255))
		draw_circle(c + Vector2(4, -40 - i * 4), 3, Color(col, 0.7))
	# Доска с формулой.
	_rrect(Rect2(r.end.x - 96, r.position.y + 24, 76, 50), 6, Color8(46, 92, 70), Color8(120, 82, 52), 4)
	_otext(Vector2(r.end.x - 90, r.position.y + 56), "E=mc²", 16, Color(1, 1, 1, 0.85), Color(0, 0, 0, 0), 0)


func _lamp(at: Vector2) -> void:
	draw_line(at + Vector2(0, -6), at, Color8(60, 60, 70), 3.0)
	draw_circle(at + Vector2(0, 8), 9, Color8(255, 236, 150))
	draw_circle(at + Vector2(-2, 6), 3, Color.WHITE)


func _light(c: Vector2, r: float, col: Color) -> void:
	# Плавное пятно: веер треугольников от яркого центра к прозрачному краю.
	var edge := Color(col, 0.0)
	var n := 40
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		draw_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			PackedColorArray([col, edge, edge]))


func _dark_gradient(r: Rect2, col: Color, from_right: bool) -> void:
	# Тьма гуще вдали от света.
	var a := Color(col, 0.0) if from_right else col
	var b := col
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([b, a, a, b]) if from_right else PackedColorArray([a, a, a, a]))


func _trees() -> void:
	for t in [[470, 1.0], [560, 1.25], [660, 0.9], [1360, 1.1], [1700, 1.3], [1830, 0.95], [1930, 1.15]]:
		_tree(Vector2(t[0], _sy(t[0]) - 2), t[1])
	for b in [760, 1460, 1610]:
		_bush(Vector2(b, _sy(b) - 2))
	_boulder(Vector2(820, _sy(820) - 2))


func _tree(at: Vector2, k: float) -> void:
	var h := 120.0 * k
	# Ствол с сужением.
	var trunk := PackedVector2Array([at + Vector2(-12 * k, 0), at + Vector2(12 * k, 0), at + Vector2(6 * k, -h), at + Vector2(-6 * k, -h)])
	draw_colored_polygon(_shift(trunk, Vector2(3, 0)), Color8(100, 62, 40))
	draw_colored_polygon(trunk, Color8(150, 96, 58))
	draw_line(at + Vector2(-3 * k, -10), at + Vector2(-2 * k, -h + 10), Color(1, 1, 1, 0.18), 3.0)
	var c := at + Vector2(0, -h)
	var leaf := Color8(78, 190, 72) if not winter else Color8(64, 128, 92)
	var leaf_d := Color8(46, 140, 56) if not winter else Color8(40, 92, 70)
	var leaf_h := Color8(150, 232, 92) if not winter else Color8(110, 170, 120)
	var parts := [[Vector2(-34, 6), 34], [Vector2(32, 8), 32], [Vector2(0, -22), 42], [Vector2(-14, 18), 30], [Vector2(18, 20), 30]]
	for p in parts:
		draw_circle(c + p[0] * k + Vector2(0, 7 * k), p[1] * k, leaf_d)
	for p in parts:
		draw_circle(c + p[0] * k, p[1] * k, leaf)
	for p in parts:
		draw_circle(c + p[0] * k + Vector2(-8, -10) * k, p[1] * k * 0.45, leaf_h)
	if winter:
		# Снежные шапки сверху.
		for p in parts:
			var top: Vector2 = c + p[0] * k + Vector2(0, -p[1] * k * 0.55)
			_ellipse(top, Vector2(p[1] * k * 0.75, p[1] * k * 0.35), SNOW)


func _bush(at: Vector2) -> void:
	var col := Color8(70, 176, 70) if not winter else Color8(70, 120, 92)
	for p in [[Vector2(-20, -16), 20], [Vector2(18, -16), 20], [Vector2(0, -28), 22]]:
		draw_circle(at + p[0] + Vector2(0, 5), p[1], col.darkened(0.25))
	for p in [[Vector2(-20, -16), 20], [Vector2(18, -16), 20], [Vector2(0, -28), 22]]:
		draw_circle(at + p[0], p[1], col)
	if winter:
		_ellipse(at + Vector2(0, -44), Vector2(22, 9), SNOW)
		return
	for b in [Vector2(-18, -22), Vector2(4, -36), Vector2(18, -14), Vector2(-4, -12), Vector2(26, -28)]:
		draw_circle(at + b, 6, Color8(232, 40, 70))
		draw_circle(at + b + Vector2(-2, -2), 2, Color(1, 1, 1, 0.8))


func _boulder(at: Vector2) -> void:
	var pts := _blob(at + Vector2(0, -22), 28, Vector2(1.3, 0.85))
	draw_colored_polygon(_shift(pts, Vector2(0, 5)), Color8(82, 88, 110))
	draw_colored_polygon(pts, Color8(150, 158, 182))
	draw_circle(at + Vector2(-12, -34), 8, Color(1, 1, 1, 0.3))
	if winter:
		_ellipse(at + Vector2(0, -44), Vector2(24, 8), SNOW)


func _surface_buildings() -> void:
	# Склад на поверхности: каменный, с ящиками.
	var x := 1060.0
	var g := _sy(x + 120) - 2
	var r := Rect2(x, g - 120, 240, 120)
	_rrect(r.grow(6), 12, Color8(92, 98, 124), Color(0, 0, 0, 0), 0)
	_grad_rect_r(r, Color8(84, 64, 56), Color8(60, 42, 38), 8)
	for i in 3:
		var cr := Rect2(r.position.x + 20 + i * 52, r.end.y - 44 - (14 if i == 1 else 0), 44, 40)
		_rrect(cr, 4, Color8(206, 150, 88), Color8(130, 84, 50), 3)
		draw_line(cr.position + Vector2(4, 4), cr.end - Vector2(4, 4), Color8(150, 98, 58), 3.0)
	# Мешки с едой (амбар рядом).
	for i in 2:
		_ellipse(Vector2(r.end.x - 46 + i * 22, r.end.y - 18), Vector2(14, 16), Color8(230, 206, 150))
	# Крыша.
	var roof := PackedVector2Array([r.position + Vector2(-22, 2), Vector2(r.get_center().x, r.position.y - 46), Vector2(r.end.x + 22, r.position.y + 2)])
	draw_colored_polygon(_shift(roof, Vector2(0, 6)), Color8(140, 40, 40))
	draw_colored_polygon(roof, Color8(222, 72, 62) if not winter else SNOW)
	if not winter:
		draw_line(roof[0] + Vector2(16, -6), roof[1] + Vector2(0, 10), Color(1, 1, 1, 0.35), 4.0)
	# Табличка.
	_rrect(Rect2(r.get_center().x - 42, r.position.y - 30, 84, 26), 8, Color8(255, 226, 120), INK, 3)
	_otext(Vector2(r.get_center().x - 42, r.position.y - 11), "СКЛАД", 15, INK, Color(0, 0, 0, 0), 0, 84)


func _creatures() -> void:
	var t := 0.6
	var list := [
		# [позиция ног, цвет, форма, глаза, поза]
		[Vector2(250, _sy(250) - 6), Color8(255, 210, 40), 2, 1, UnitLayer.POSES["fish"]],        # рыбак
		[Vector2(1000, _sy(1000)), Color8(230, 50, 60), 0, 1, UnitLayer.POSES["carry0"]],          # несёт дрова
		[Vector2(1420, _sy(1420)), Color8(40, 200, 90), 1, 2, UnitLayer.POSES["walk1"]],
		[Vector2(922, 560), Color8(60, 120, 255), 0, 1, UnitLayer.POSES["climb0"]],               # на лестнице
		[Vector2(660, 532), Color8(255, 130, 40), 2, 1, UnitLayer.POSES["work0"]],                # копает
		[Vector2(720, 700), Color8(170, 70, 230), 1, 1, UnitLayer.POSES["work2"]],                # ферма
		[Vector2(1020, 700), Color8(30, 200, 220), 0, 3, UnitLayer.POSES["work1"]],               # учёный
		[Vector2(1190, 530), Color8(250, 90, 170), 2, 1, UnitLayer.POSES["sleep"]],
	]
	var i := 0
	for c in list:
		var g := {"color": c[1], "shape": c[2], "eyes": c[3], "fingers": 4, "size": 0, "pattern": 0,
			"female": i % 2 == 1, "pose": c[4], "hair_color": Color8(60, 40, 30)}
		for k in Genetics.DOMINANT + Genetics.RECESSIVE:
			g[k] = false
		if i == 5:
			g["antennae"] = true
		if i == 6:
			g["glow"] = true
		if i == 7:
			# Спит — лёжа на кровати.
			# Спит сидя в кровати, укрывшись одеялом по пояс.
			g["color"] = Color8(255, 196, 60)
			CreatureArt.draw(self, Vector2(1172, 512), 42.0, g, t + i)
			_rrect(Rect2(1134, 494, 84, 28), 12, Color8(240, 100, 140), Color8(170, 60, 96), 3)
			draw_line(Vector2(1142, 501), Vector2(1210, 501), Color(1, 1, 1, 0.4), 3.0)
		else:
			CreatureArt.draw(self, c[0], 46.0, g, t + i)
		i += 1
	# Ноша: дрова над головой у красного.
	var head := Vector2(1000, _sy(1000) - 66)
	for j in 3:
		_rrect(Rect2(head.x - 24, head.y - 12 - j * 11, 48, 11), 5, Color8(176, 116, 70), Color8(110, 70, 44), 2)
	# Кирка у копающего.
	var hand := Vector2(668, 470)
	draw_line(hand, hand + Vector2(-26, 30), Color8(150, 98, 58), 5.0)
	draw_line(hand + Vector2(-14, -10), hand + Vector2(16, 8), Color8(170, 176, 196), 6.0)
	# Удочка у рыбака.
	var rod := Vector2(272, _sy(250) - 40)
	draw_line(rod, rod + Vector2(90, -70), Color8(140, 94, 58), 4.0)
	draw_line(rod + Vector2(90, -70), rod + Vector2(110, 60), Color(1, 1, 1, 0.8), 1.5)
	# Спящий: «Zzz».
	_otext(Vector2(1226, 486), "z", 20, Color.WHITE, INK, 5)
	_otext(Vector2(1240, 466), "Z", 26, Color.WHITE, INK, 5)
	# Выбранный житель: кольцо и плашка с именем.
	var sel := Vector2(1420, _sy(1420))
	_ellipse_line(sel + Vector2(0, 2), Vector2(34, 10), Color8(255, 220, 60), 4.0)
	_name_tag(sel + Vector2(0, -78), "Бубо", "строитель")


func _name_tag(at: Vector2, name: String, role: String) -> void:
	var w := 120.0
	var r := Rect2(at - Vector2(w / 2, 26), Vector2(w, 44))
	_bubble(r, Color.WHITE, INK)
	_otext(r.position + Vector2(0, 21), name, 18, INK, Color(0, 0, 0, 0), 0, w)
	_otext(r.position + Vector2(0, 38), role, 12, Color8(90, 100, 140), Color(0, 0, 0, 0), 0, w)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-9, 17), at + Vector2(9, 17), at + Vector2(0, 28)]), INK)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 15), at + Vector2(6, 15), at + Vector2(0, 23)]), Color.WHITE)


func _snowfall(size: Vector2) -> void:
	for i in 160:
		var p := Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, 420))
		if p.y > _sy(p.x):
			continue
		draw_circle(p, _rng.randf_range(2, 4.5), Color(1, 1, 1, 0.85))


# --- Интерфейс поверх мира ---------------------------------------------------------------

func _hud(size: Vector2) -> void:
	# Ресурсы.
	var items := [["people", "5"], ["food", "48" if not winter else "12"], ["berries", "16" if not winter else "0"], ["wood", "37"], ["stone", "22"]]
	var x := 28.0
	for it in items:
		x += _res_pill(Vector2(x, 26), it[0], it[1], winter and it[0] == "food") + 14
	# Дата и сезон.
	var badge := Rect2(size.x - 330, 22, 300, 56)
	_panel_dark(badge)
	_icon(Vector2(badge.position.x + 30, badge.get_center().y), "snow" if winter else "sun", 20)
	_otext(Vector2(badge.position.x + 58, badge.position.y + 26), "16 янв · зима" if winter else "12 мая · весна", 20, Color.WHITE, INK, 6)
	_otext(Vector2(badge.position.x + 58, badge.position.y + 48), "−8 °C · год 1" if winter else "+16 °C · год 1", 15, Color8(190, 220, 255), INK, 5)
	# Предупреждение зимой.
	if winter:
		var warn := Rect2(28, 96, 560, 50)
		_rrect(warn.grow(3), 16, INK, Color(0, 0, 0, 0), 0)
		_rrect(warn, 14, Color8(255, 196, 64), Color(0, 0, 0, 0), 0)
		_icon(Vector2(warn.position.x + 28, warn.get_center().y), "warn", 16)
		_otext(Vector2(warn.position.x + 52, warn.position.y + 32), "Еды на 4 дня! Нужна тёплая ферма", 19, INK, Color(0, 0, 0, 0), 0)
	# Нижнее меню.
	var y := size.y - 108
	_button(Rect2(28, y, 150, 90), "Стройка", "hammer", "yellow")
	var right := [["Жители", "people", "blue"], ["Наука", "flask", "blue"], ["К базе", "home", "blue"]]
	var bx := size.x - 28 - 4 * 120 - 3 * 12 - 250
	for b in right:
		_button(Rect2(bx, y, 120, 90), b[0], b[1], b[2])
		bx += 132
	# Скорость — переключатель.
	var seg := Rect2(bx, y + 8, 236, 74)
	_rrect(Rect2(seg.position + Vector2(0, 6), seg.size), 20, INK, Color(0, 0, 0, 0), 0)
	_rrect(seg, 20, Color8(48, 62, 110), INK, 4)
	for i in 3:
		var cell := Rect2(seg.position + Vector2(6 + i * 76, 6), Vector2(72, 56))
		if i == 0:
			_rrect(Rect2(cell.position + Vector2(0, 4), cell.size), 14, Color8(196, 120, 20), Color(0, 0, 0, 0), 0)
			_grad_rect_r(cell, Color8(255, 220, 80), Color8(255, 170, 40), 14)
		_otext(Vector2(cell.position.x, cell.position.y + 37), ["×1", "×10", "×20"][i], 22, Color.WHITE, INK, 6, cell.size.x)
	bx += 248
	_button(Rect2(bx, y, 100, 90), "", "menu", "blue")


func _res_pill(at: Vector2, icon: String, value: String, alarm := false) -> float:
	var w := 70.0 + value.length() * 14.0
	var r := Rect2(at + Vector2(18, 6), Vector2(w, 42))
	_rrect(Rect2(r.position + Vector2(0, 4), r.size), 21, Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0)
	_rrect(r, 21, Color8(30, 36, 70, 225) if not alarm else Color8(170, 40, 50, 235), INK, 3)
	_otext(Vector2(r.position.x + 40, r.position.y + 31), value, 24, Color.WHITE, INK, 6)
	# Значок в кружке, вылезает за край.
	var c := at + Vector2(22, 27)
	draw_circle(c + Vector2(0, 3), 25, INK)
	draw_circle(c, 25, INK)
	draw_circle(c, 21, Color8(255, 255, 255))
	draw_circle(c, 21, Color8(232, 240, 255))
	_icon(c, icon, 15)
	return w + 18


func _button(r: Rect2, label: String, icon: String, style: String) -> void:
	var top := Color8(86, 170, 255)
	var bottom := Color8(42, 110, 230)
	var lip := Color8(26, 70, 160)
	if style == "yellow":
		top = Color8(255, 222, 80)
		bottom = Color8(255, 168, 30)
		lip = Color8(196, 110, 10)
	elif style == "green":
		top = Color8(140, 236, 90)
		bottom = Color8(60, 190, 60)
		lip = Color8(30, 130, 40)
	elif style == "red":
		top = Color8(255, 110, 100)
		bottom = Color8(226, 54, 60)
		lip = Color8(150, 30, 40)
	_rrect(Rect2(r.position + Vector2(0, 8), r.size), 20, INK, Color(0, 0, 0, 0), 0)
	_rrect(Rect2(r.position + Vector2(0, 5), r.size), 20, lip, INK, 4)
	_grad_rect_r(r, top, bottom, 20)
	_rrect_line(r, 20, INK, 4)
	# Блик сверху.
	_rrect(Rect2(r.position + Vector2(10, 6), Vector2(r.size.x - 20, r.size.y * 0.28)), 12, Color(1, 1, 1, 0.28), Color(0, 0, 0, 0), 0)
	if label.is_empty():
		_icon(r.get_center(), icon, 24, true)
	else:
		_icon(r.get_center() + Vector2(0, -12), icon, 20, true)
		_otext(Vector2(r.position.x, r.end.y - 14), label, 17, Color.WHITE, INK, 6, r.size.x)


func _pill(at: Vector2, text: String, icon: String, col: Color) -> void:
	var r := Rect2(at, Vector2(86, 34))
	_rrect(Rect2(r.position + Vector2(0, 4), r.size), 17, INK, Color(0, 0, 0, 0), 0)
	_rrect(r, 17, col, INK, 3)
	draw_circle(r.position + Vector2(18, 17), 13, Color.WHITE)
	_icon(r.position + Vector2(18, 17), icon, 10)
	_otext(Vector2(r.position.x + 34, r.position.y + 25), text, 18, Color.WHITE, INK, 5)


func _panel_dark(r: Rect2) -> void:
	_rrect(Rect2(r.position + Vector2(0, 4), r.size), 18, Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0)
	_rrect(r, 18, Color8(30, 36, 70, 225), INK, 3)


# --- Лист интерфейса ---------------------------------------------------------------------

func _ui_sheet(size: Vector2) -> void:
	_grad_rect(Rect2(Vector2.ZERO, size), Color8(62, 120, 210), Color8(34, 64, 140))
	# Узор фона — ромбы, как в меню Clash Royale.
	for yy in range(0, int(size.y), 60):
		for xx in range(0, int(size.x), 60):
			if (xx / 60 + yy / 60) % 2 == 0:
				draw_colored_polygon(PackedVector2Array([Vector2(xx + 30, yy), Vector2(xx + 60, yy + 30), Vector2(xx + 30, yy + 60), Vector2(xx, yy + 30)]),
					Color(1, 1, 1, 0.04))
	_otext(Vector2(40, 64), "Интерфейс", 40, Color.WHITE, INK, 9)
	_unit_card(Rect2(40, 100, 620, 760))
	_room_card(Rect2(700, 100, 600, 520))
	_people_card(Rect2(1340, 100, 620, 520))
	# Кнопки.
	var bx := 700.0
	for b in [["Назначить", "people", "yellow"], ["Ремонт", "hammer", "green"], ["Снести", "close", "red"], ["Наука", "flask", "blue"]]:
		_button(Rect2(bx, 680, 170, 90), b[0], b[1], b[2])
		bx += 190
	var px := 1480.0
	for it in [["food", "48"], ["wood", "37"]]:
		px += _res_pill(Vector2(px, 690), it[0], it[1]) + 14
	_pill(Vector2(1500, 770), "3/6", "wood", Color8(214, 64, 52))
	_pill(Vector2(1610, 770), "8/8", "stone", Color8(62, 150, 70))


func _card_frame(r: Rect2, title: String, subtitle: String, header_col: Color) -> float:
	_rrect(Rect2(r.position + Vector2(0, 10), r.size), 26, Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0)
	_rrect(r, 26, INK, Color(0, 0, 0, 0), 0)
	var inner := r.grow(-5)
	_grad_rect_r(inner, Color8(238, 243, 252), Color8(214, 224, 242), 22)
	var head := Rect2(inner.position, Vector2(inner.size.x, 86))
	_grad_rect_r(head, header_col.lightened(0.15), header_col, 22)
	_rect(Rect2(head.position.x, head.end.y - 22, head.size.x, 22), header_col)
	_rect(Rect2(head.position.x, head.end.y, head.size.x, 4), INK)
	_otext(head.position + Vector2(24, 42), title, 32, Color.WHITE, INK, 8)
	_otext(head.position + Vector2(24, 72), subtitle, 18, Color8(255, 226, 120), INK, 6)
	# Крестик.
	var x := Rect2(head.end.x - 66, head.position.y + 14, 52, 52)
	_rrect(Rect2(x.position + Vector2(0, 4), x.size), 14, Color8(150, 30, 40), INK, 3)
	_grad_rect_r(x, Color8(255, 110, 100), Color8(226, 54, 60), 14)
	_rrect_line(x, 14, INK, 3)
	_icon(x.get_center(), "close", 14, true)
	return head.end.y + 14


func _unit_card(r: Rect2) -> void:
	var y := _card_frame(r, "Бубо", "♂ строитель · копает", Color8(52, 110, 220))
	# Портрет.
	var pr := Rect2(r.position.x + 24, y, 200, 200)
	_rrect(Rect2(pr.position + Vector2(0, 5), pr.size), 22, INK, Color(0, 0, 0, 0), 0)
	_grad_rect_r(pr, Color8(150, 220, 255), Color8(90, 170, 240), 22)
	_rrect_line(pr, 22, INK, 4)
	var g := {"color": Color8(40, 200, 90), "shape": 1, "eyes": 2, "fingers": 4, "size": 0, "pattern": 0, "female": false,
		"hair_color": Color8(60, 40, 30), "pose": UnitLayer.POSES["work1"]}
	for k in Genetics.DOMINANT + Genetics.RECESSIVE:
		g[k] = false
	CreatureArt.draw(self, pr.position + Vector2(100, 176), 104.0, g, 0.5)
	# Метки.
	var tx := pr.end.x + 20
	var tags := [["Возраст: 1 г. 4 мес. · 2-е поколение", INK], ["Характер: трудоголик", INK], ["МУТАНТ: 2 глаза", Color8(60, 130, 230)], ["Занятие: строитель", Color8(90, 100, 140)]]
	var ty := y + 26
	for tg in tags:
		_otext(Vector2(tx, ty), tg[0], 18, tg[1], Color(0, 0, 0, 0), 0)
		ty += 34
	_chip(Vector2(tx, ty - 6), "мёрзнет", Color8(120, 190, 255))
	_chip(Vector2(tx + 110, ty - 6), "в темноте ×0,7", Color8(255, 196, 80))
	y = pr.end.y + 24
	# Потребности.
	for b in [["Сытость", 0.32, Color8(255, 168, 40)], ["Бодрость", 0.78, Color8(90, 210, 70)], ["Здоровье", 1.0, Color8(90, 210, 70)]]:
		_bar(Rect2(r.position.x + 24, y, r.size.x - 48, 38), b[0], b[1], b[2])
		y += 50
	# Характеристики сеткой.
	_otext(Vector2(r.position.x + 24, y + 20), "Характеристики", 20, INK, Color(0, 0, 0, 0), 0)
	y += 34
	var stats := [["Сила", 1.2], ["Ловкость", 0.9], ["Интеллект", 1.4], ["Зрение", 1.5], ["Холод", 1.6], ["Жара", 0.8]]
	for i in stats.size():
		var cx := r.position.x + 24 + (i % 2) * ((r.size.x - 48) / 2 + 6)
		var cy := y + (i / 2) * 44
		var v: float = stats[i][1]
		_bar(Rect2(cx, cy, (r.size.x - 48) / 2 - 6, 34), stats[i][0], v / 2.0, Color8(90, 210, 70) if v >= 1.0 else Color8(255, 120, 90), "%d%%" % roundi(v * 100))
	y += 3 * 44 + 10
	var by := r.end.y - 104
	_button(Rect2(r.position.x + 24, by, 180, 80), "Отправить", "home", "yellow")
	_button(Rect2(r.position.x + 220, by, 180, 80), "Работа", "hammer", "blue")
	_button(Rect2(r.position.x + 416, by, 180, 80), "Жители", "people", "blue")


func _room_card(r: Rect2) -> void:
	var y := _card_frame(r, "Ферма 6×3", "готово · тепло", Color8(60, 160, 90))
	var x := r.position.x + 24
	_bar(Rect2(x, y, r.size.x - 48, 38), "Износ", 0.16, Color8(90, 210, 70), "16% · ещё 84 года")
	y += 50
	_bar(Rect2(x, y, r.size.x - 48, 38), "Урожай", 0.6, Color8(255, 196, 64), "60%")
	y += 56
	var cx := x
	for c in [["фермеров 2/3", Color8(120, 190, 255)], ["внутри +18 °C", Color8(255, 168, 120)], ["лежит: 6", Color8(150, 230, 120)]]:
		cx += _chip(Vector2(cx, y), c[0], c[1]) + 10
	y += 54
	_otext(Vector2(x, y + 18), "Работники", 20, INK, Color(0, 0, 0, 0), 0)
	y += 30
	for p in [["Мила", "подходит на 140%", Color8(170, 70, 230)], ["Зуро", "подходит на 96%", Color8(255, 210, 40)]]:
		_person_row(Rect2(x, y, r.size.x - 48, 70), p[0], p[1], p[2], "Снять", "red")
		y += 80


func _people_card(r: Rect2) -> void:
	var y := _card_frame(r, "Жители", "взрослых 8 · детей 2", Color8(52, 110, 220))
	var x := r.position.x + 24
	var cx := x
	for c in [["строят 3", Color8(255, 196, 64)], ["носят 2", Color8(120, 190, 255)], ["спят 1", Color8(200, 200, 230)]]:
		cx += _chip(Vector2(cx, y), c[0], c[1]) + 10
	y += 54
	_otext(Vector2(x, y + 18), "Строители — 2", 20, INK, Color(0, 0, 0, 0), 0)
	y += 30
	_person_row(Rect2(x, y, r.size.x - 48, 70), "Бубо", "копает", Color8(40, 200, 90), "Снять", "red")
	y += 80
	_otext(Vector2(x, y + 18), "Подсобные рабочие — 1", 20, INK, Color(0, 0, 0, 0), 0)
	y += 30
	_person_row(Rect2(x, y, r.size.x - 48, 70), "Тикаша", "носит дерево", Color8(250, 90, 170), "Снять", "red")
	y += 80
	_otext(Vector2(x, y + 18), "Свободные — 3", 20, INK, Color(0, 0, 0, 0), 0)
	y += 30
	_person_row(Rect2(x, y, r.size.x - 48, 70), "Пакос", "отдыхает", Color8(60, 120, 255), "Карточка", "blue")


func _person_row(r: Rect2, name: String, info: String, col: Color, btn: String, style: String) -> void:
	_rrect(r, 16, Color.WHITE, Color8(180, 194, 224), 3)
	var face := Rect2(r.position + Vector2(8, 8), Vector2(54, 54))
	_grad_rect_r(face, Color8(150, 220, 255), Color8(90, 170, 240), 12)
	_rrect_line(face, 12, INK, 3)
	var g := {"color": col, "shape": name.length() % 3, "eyes": 1, "fingers": 4, "size": 0, "pattern": 0, "female": false,
		"hair_color": Color8(60, 40, 30)}
	for k in Genetics.DOMINANT + Genetics.RECESSIVE:
		g[k] = false
	CreatureArt.draw(self, face.position + Vector2(27, 50), 30.0, g, 0.3)
	_otext(Vector2(r.position.x + 76, r.position.y + 32), name, 22, INK, Color(0, 0, 0, 0), 0)
	_otext(Vector2(r.position.x + 76, r.position.y + 56), info, 16, Color8(90, 100, 140), Color(0, 0, 0, 0), 0)
	var b := Rect2(r.end.x - 150, r.position.y + 10, 138, 48)
	var top: Color = Color8(255, 110, 100) if style == "red" else Color8(86, 170, 255)
	var bot: Color = Color8(226, 54, 60) if style == "red" else Color8(42, 110, 230)
	_rrect(Rect2(b.position + Vector2(0, 4), b.size), 14, top.darkened(0.45), INK, 3)
	_grad_rect_r(b, top, bot, 14)
	_rrect_line(b, 14, INK, 3)
	_otext(Vector2(b.position.x, b.position.y + 32), btn, 19, Color.WHITE, INK, 5, b.size.x)


func _bar(r: Rect2, label: String, v: float, col: Color, text := "") -> void:
	var lw := 130.0 if r.size.x > 300 else 110.0
	_otext(Vector2(r.position.x, r.position.y + 26), label, 18, INK, Color(0, 0, 0, 0), 0)
	var b := Rect2(r.position.x + lw, r.position.y + 4, r.size.x - lw, r.size.y - 8)
	_rrect(b, b.size.y / 2, Color8(54, 62, 100), INK, 3)
	if v > 0.01:
		var f := Rect2(b.position + Vector2(3, 3), Vector2(maxf(b.size.y, (b.size.x - 6) * clampf(v, 0, 1)), b.size.y - 6))
		_grad_rect_r(f, col.lightened(0.25), col.darkened(0.1), f.size.y / 2)
		_rrect(Rect2(f.position + Vector2(6, 3), Vector2(f.size.x - 12, f.size.y * 0.3)), 4, Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0)
	var tt := text if not text.is_empty() else "%d%%" % roundi(v * 100)
	_otext(Vector2(b.position.x, b.position.y + b.size.y * 0.72), tt, 16, Color.WHITE, INK, 5, b.size.x)


func _chip(at: Vector2, text: String, col: Color) -> float:
	var w := 26.0 + text.length() * 10.0
	var r := Rect2(at, Vector2(w, 36))
	_rrect(Rect2(r.position + Vector2(0, 3), r.size), 18, col.darkened(0.4), Color(0, 0, 0, 0), 0)
	_rrect(r, 18, col, INK, 3)
	_otext(Vector2(r.position.x, r.position.y + 25), text, 16, INK, Color(0, 0, 0, 0), 0, w)
	return w


# --- Значки -----------------------------------------------------------------------------

func _icon(c: Vector2, kind: String, s: float, white := false) -> void:
	var o := INK
	match kind:
		"people":
			var col := Color.WHITE if white else Color8(255, 150, 60)
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.42 + 3, o)
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.42, col)
			_rrect(Rect2(c + Vector2(-s * 0.7, -s * 0.05) - Vector2(3, 3), Vector2(s * 1.4 + 6, s * 0.9 + 6)), s * 0.4, o, Color(0, 0, 0, 0), 0)
			_rrect(Rect2(c + Vector2(-s * 0.7, -s * 0.05), Vector2(s * 1.4, s * 0.9)), s * 0.4, col, Color(0, 0, 0, 0), 0)
		"food":
			# Рыбка.
			var body := _blob(c + Vector2(-s * 0.15, 0), s * 0.6, Vector2(1.3, 0.75))
			var tail := PackedVector2Array([c + Vector2(s * 0.5, 0), c + Vector2(s * 0.95, -s * 0.45), c + Vector2(s * 0.95, s * 0.45)])
			draw_colored_polygon(tail, Color8(80, 150, 255))
			draw_colored_polygon(body, Color8(110, 180, 255))
			draw_circle(c + Vector2(-s * 0.5, -s * 0.1), s * 0.12, INK)
		"berries":
			for p in [Vector2(-0.35, 0.2), Vector2(0.35, 0.2), Vector2(0, -0.3)]:
				draw_circle(c + p * s, s * 0.38, Color8(150, 20, 50))
				draw_circle(c + p * s, s * 0.32, Color8(236, 40, 70))
				draw_circle(c + p * s + Vector2(-2, -2), s * 0.1, Color(1, 1, 1, 0.8))
		"wood":
			_rrect(Rect2(c - Vector2(s * 0.9, s * 0.45), Vector2(s * 1.8, s * 0.9)), s * 0.45, Color8(176, 116, 70), Color8(110, 70, 44), 2)
			draw_circle(c + Vector2(s * 0.5, 0), s * 0.36, Color8(240, 200, 140))
			draw_circle(c + Vector2(s * 0.5, 0), s * 0.15, Color8(200, 150, 96))
		"stone":
			var pts := _blob(c, s * 0.75, Vector2(1.2, 0.85))
			draw_colored_polygon(_shift(pts, Vector2(0, 2)), Color8(82, 88, 110))
			draw_colored_polygon(pts, Color8(160, 168, 190))
			draw_circle(c + Vector2(-s * 0.25, -s * 0.25), s * 0.2, Color(1, 1, 1, 0.4))
		"sun":
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.75, c + Vector2(cos(a), sin(a)) * s * 1.1, Color8(255, 210, 60), 4.0)
			draw_circle(c, s * 0.62, Color8(255, 210, 60))
			draw_circle(c + Vector2(-3, -3), s * 0.22, Color(1, 1, 1, 0.5))
		"snow":
			for i in 3:
				var a := PI * i / 3.0
				draw_line(c - Vector2(cos(a), sin(a)) * s, c + Vector2(cos(a), sin(a)) * s, Color8(200, 230, 255), 4.0)
			draw_circle(c, s * 0.25, Color.WHITE)
		"warn":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.8), c + Vector2(-s, s * 0.8)]), INK)
			_otext(Vector2(c.x - s, c.y + s * 0.6), "!", int(s * 1.3), Color8(255, 196, 64), Color(0, 0, 0, 0), 0, s * 2)
		"hammer":
			var col := Color.WHITE
			_rect_rot(c + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.3, s * 1.4), -0.7, o, 3)
			_rect_rot(c + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.3, s * 1.4), -0.7, col, 0)
			_rect_rot(c + Vector2(-s * 0.3, -s * 0.3), Vector2(s * 1.2, s * 0.55), -0.7, o, 3)
			_rect_rot(c + Vector2(-s * 0.3, -s * 0.3), Vector2(s * 1.2, s * 0.55), -0.7, col, 0)
		"flask":
			var pts := PackedVector2Array([c + Vector2(-s * 0.25, -s), c + Vector2(s * 0.25, -s), c + Vector2(s * 0.25, -s * 0.3),
				c + Vector2(s * 0.85, s * 0.8), c + Vector2(-s * 0.85, s * 0.8), c + Vector2(-s * 0.25, -s * 0.3)])
			draw_colored_polygon(_grow(pts, 3), o)
			draw_colored_polygon(pts, Color.WHITE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, s * 0.3), c + Vector2(s * 0.55, s * 0.3), c + Vector2(s * 0.8, s * 0.75), c + Vector2(-s * 0.8, s * 0.75)]), Color8(110, 240, 140))
		"home":
			var roof := PackedVector2Array([c + Vector2(-s, -s * 0.05), c + Vector2(0, -s), c + Vector2(s, -s * 0.05)])
			draw_colored_polygon(_grow(roof, 3), o)
			draw_colored_polygon(roof, Color.WHITE)
			_rrect(Rect2(c + Vector2(-s * 0.65, -s * 0.1), Vector2(s * 1.3, s * 0.95)), 3, Color.WHITE, o, 3)
			_rect(Rect2(c + Vector2(-s * 0.15, s * 0.3), Vector2(s * 0.3, s * 0.55)), o)
		"menu":
			for i in 3:
				_rrect(Rect2(c + Vector2(-s, -s * 0.7 + i * s * 0.6) - Vector2(2, 2), Vector2(s * 2 + 4, s * 0.32 + 4)), 4, o, Color(0, 0, 0, 0), 0)
				_rrect(Rect2(c + Vector2(-s, -s * 0.7 + i * s * 0.6), Vector2(s * 2, s * 0.32)), 3, Color.WHITE, Color(0, 0, 0, 0), 0)
		"close":
			draw_line(c + Vector2(-s, -s) * 0.8, c + Vector2(s, s) * 0.8, o, 9.0)
			draw_line(c + Vector2(s, -s) * 0.8, c + Vector2(-s, s) * 0.8, o, 9.0)
			draw_line(c + Vector2(-s, -s) * 0.8, c + Vector2(s, s) * 0.8, Color.WHITE, 5.0)
			draw_line(c + Vector2(s, -s) * 0.8, c + Vector2(-s, s) * 0.8, Color.WHITE, 5.0)


# --- Примитивы --------------------------------------------------------------------------

func _otext(pos: Vector2, text: String, fs: int, col: Color, outline: Color, ow: int, width := -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT
	if ow > 0:
		# Тень снизу и толстая обводка — «игровой» текст.
		draw_string_outline(_font, pos + Vector2(0, fs * 0.09), text, align, width, fs, ow, outline)
		draw_string(_font, pos + Vector2(0, fs * 0.09), text, align, width, fs, outline)
		draw_string_outline(_font, pos, text, align, width, fs, ow, outline)
	draw_string(_font, pos, text, align, width, fs, col)


func _rect(r: Rect2, col: Color) -> void:
	draw_rect(r, col)


func _rect_rot(c: Vector2, s: Vector2, a: float, col: Color, grow: float) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(c + (p * (s * 0.5 + Vector2(grow, grow))).rotated(a))
	draw_colored_polygon(pts, col)


func _rrect_pts(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for c in corners:
		for i in 7:
			var a: float = c[1] + PI * 0.5 * i / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _rrect(r: Rect2, rad: float, fill: Color, line: Color, lw: float) -> void:
	var pts := _rrect_pts(r, rad)
	draw_colored_polygon(pts, fill)
	if lw > 0:
		_rrect_line(r, rad, line, lw)


func _rrect_line(r: Rect2, rad: float, col: Color, lw: float) -> void:
	var pts := _rrect_pts(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, lw, true)


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _grad_rect_r(r: Rect2, top: Color, bottom: Color, rad: float) -> void:
	var pts := _rrect_pts(r, rad) if rad > 0 else PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0, 1)))
	draw_polygon(pts, cols)


func _bubble(r: Rect2, fill: Color, line: Color) -> void:
	_rrect(Rect2(r.position + Vector2(0, 4), r.size), 14, line, Color(0, 0, 0, 0), 0)
	_rrect(r, 14, fill, line, 3)


func _dashed_rect(r: Rect2, col: Color, lw: float) -> void:
	_rrect(r, 10, Color(col, 0.12), Color(0, 0, 0, 0), 0)
	var pts := _rrect_pts(r, 10)
	pts.append(pts[0])
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var len := a.distance_to(b)
		var t := 0.0
		while t < len:
			var on := fmod(acc + t, 28.0) < 16.0
			var nt := minf(len, t + 4.0)
			if on:
				draw_line(a.lerp(b, t / len), a.lerp(b, nt / len), col, lw)
			t = nt
		acc += len


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _ellipse_line(c: Vector2, r: Vector2, col: Color, lw: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, lw, true)


func _blob(c: Vector2, r: float, k := Vector2.ONE) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ph := _rng.randf() * TAU
	for i in 14:
		var a := TAU * i / 14.0
		var rr := r * (1.0 + 0.12 * sin(a * 3.0 + ph))
		pts.append(c + Vector2(cos(a) * rr * k.x, sin(a) * rr * k.y))
	return pts


func _gem(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ph := _rng.randf() * TAU
	for i in 6:
		var a := TAU * i / 6.0 + ph
		pts.append(c + Vector2(cos(a), sin(a)) * r * (0.85 + 0.3 * _rng.randf()))
	return pts


func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out


func _grow(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(pts, d, Geometry2D.JOIN_ROUND)
	return res[0] if not res.is_empty() else pts
