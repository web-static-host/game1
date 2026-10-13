extends Node2D
## Превью нового оформления: мир в разрезе и интерфейс в мультяшном стиле
## (Brawl Stars / Clash Royale). sheet: 0 — лето, 1 — зима и темнота, 2 — интерфейс.

var sheet := 0
var winter := false

const INK := Color8(58, 44, 38)          # тёмно-коричневый текст (как «чернила»)
const MUTED := Color8(140, 118, 100)
const PAPER := Color8(255, 248, 236)     # панели — светлая «глина/бумага»
const PAPER_EDGE := Color8(218, 196, 166)
const HUD_BG := Color8(44, 34, 40, 205)  # тёмная подложка над миром
const FOG_TOP := Color8(110, 86, 70)     # неразведанная земля: порода не видна
const FOG_DEEP := Color8(78, 66, 72)
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
		_:
			winter = true
			_scene(size)


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
	# Неразведанная земля — однотонная, темнее с глубиной: что внутри, не видно, пока не вскопают.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var x := -20.0
	while x <= size.x + 20:
		pts.append(Vector2(x, _sy(x)))
		cols.append(FOG_TOP)
		x += 10
	pts.append(Vector2(size.x + 20, size.y + 20))
	cols.append(FOG_DEEP)
	pts.append(Vector2(-20, size.y + 20))
	cols.append(FOG_DEEP)
	draw_polygon(pts, cols)
	# Лёгкая фактура без намёка на породу.
	for n in 120:
		var p := Vector2(_rng.randf_range(0, size.x), _rng.randf_range(360, size.y))
		if p.y < _sy(p.x) + 26:
			continue
		_ellipse(p, Vector2(_rng.randf_range(10, 26), _rng.randf_range(3, 6)), Color(0, 0, 0, 0.06))
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
	# Находка у забоя: уголь в вскрытой кайме.
	for n in 5:
		var c := Vector2(548 + _rng.randf_range(-6, 6), 470 + n * 14 + _rng.randf_range(-3, 3))
		var pts := _gem(c, _rng.randf_range(6, 9))
		draw_colored_polygon(pts, Color8(44, 44, 54))
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c]), Color8(110, 110, 128))
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


## Слой породы на глубине y (что увидят вокруг выработки).
func _layer_at(x: float, y: float) -> int:
	for i in LAYERS.size():
		if y < _layer_y(i, x):
			return i
	return LAYERS.size() - 1


func _cavity(r: Rect2) -> void:
	# Кайма вскрытой породы (полблока) — её настоящий цвет и камешки.
	var rim := r.grow(20)
	var steps := 4
	for i in steps:
		var band := Rect2(rim.position.x, rim.position.y + rim.size.y * i / steps, rim.size.x, rim.size.y / steps + 1)
		var li := _layer_at(band.get_center().x, band.get_center().y)
		_rect_clip(band, rim, 22, LAYERS[li][1])
	for n in int(rim.size.x * rim.size.y / 900.0):
		var p := Vector2(_rng.randf_range(rim.position.x + 6, rim.end.x - 6), _rng.randf_range(rim.position.y + 6, rim.end.y - 6))
		if r.grow(4).has_point(p):
			continue
		var li := _layer_at(p.x, p.y)
		_pebble(p, _rng.randf_range(3, 7), LAYERS[li][3], LAYERS[li][2])
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
	# Склад на поверхности — комната 6×3 из камня, как в игре; внутри ящики.
	var x := 1060.0
	var g := _sy(x + 120) - 2
	var r := Rect2(x, g - 120, 240, 120)
	_rrect(r.grow(8), 12, Color8(150, 158, 182), Color8(92, 98, 124), 3)
	for i in 6:
		for j in 2:
			var bx := r.position.x - 8 + i * 43 + (20 if j == 1 else 0)
			if bx > r.end.x - 30:
				continue
			_rrect(Rect2(bx, r.position.y - 8 + j * 4, 40, 4), 2, Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0)
	_grad_rect_r(r, Color8(84, 64, 56), Color8(60, 42, 38), 8)
	for i in 3:
		var cr := Rect2(r.position.x + 20 + i * 52, r.end.y - 44 - (14 if i == 1 else 0), 44, 40)
		_rrect(cr, 4, Color8(206, 150, 88), Color8(130, 84, 50), 3)
		draw_line(cr.position + Vector2(4, 4), cr.end - Vector2(4, 4), Color8(150, 98, 58), 3.0)
	for i in 2:
		_ellipse(Vector2(r.end.x - 46 + i * 22, r.end.y - 18), Vector2(14, 16), Color8(230, 206, 150))
	if winter:
		_rrect(Rect2(r.position.x - 10, r.position.y - 16, r.size.x + 20, 12), 6, SNOW, Color(0, 0, 0, 0), 0)


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
	_stext(Vector2(1226, 486), "z", 20, Color.WHITE)
	_stext(Vector2(1240, 466), "Z", 26, Color.WHITE)
	# Выбранный житель: кольцо и плашка с именем.
	var sel := Vector2(1420, _sy(1420))
	_ellipse_line(sel + Vector2(0, 2), Vector2(34, 10), Color8(255, 220, 60), 4.0)
	_name_tag(sel + Vector2(0, -78), "Бубо", "строитель")


func _snowfall(size: Vector2) -> void:
	for i in 160:
		var p := Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, 420))
		if p.y > _sy(p.x):
			continue
		draw_circle(p, _rng.randf_range(2, 4.5), Color(1, 1, 1, 0.85))


# --- Интерфейс поверх мира ---------------------------------------------------------------
# Свой стиль: тёплые панели, обводка тоном того же цвета, мягкая тень снизу, без глянца.

func _hud(size: Vector2) -> void:
	# Ресурсы — одна полоса.
	var items := [["people", "5"], ["food", "48" if not winter else "12"], ["berries", "16" if not winter else "0"], ["wood", "37"], ["stone", "22"]]
	var bar := Rect2(24, 20, 30 + items.size() * 104, 58)
	_soft_panel(bar, HUD_BG, Color(0, 0, 0, 0.25))
	var x := bar.position.x + 18
	for it in items:
		_icon(Vector2(x + 16, bar.get_center().y), it[0], 14)
		_stext(Vector2(x + 38, bar.position.y + 39), it[1], 24, Color.WHITE)
		x += 104
	# Дата и сезон.
	var badge := Rect2(size.x - 300, 20, 276, 58)
	_soft_panel(badge, HUD_BG, Color(0, 0, 0, 0.25))
	_icon(Vector2(badge.position.x + 30, badge.get_center().y), "snow" if winter else "sun", 15)
	_stext(Vector2(badge.position.x + 56, badge.position.y + 27), "16 янв · зима" if winter else "12 мая · весна", 20, Color.WHITE)
	_stext(Vector2(badge.position.x + 56, badge.position.y + 49), "−8 °C · год 1" if winter else "+16 °C · год 1", 15, Color8(230, 214, 196))
	# Журнал событий — строки под ресурсами, как в игре.
	var lines := [["Новая находка: каменный уголь на глубине 9 м!", Color8(150, 236, 120)], ["Бубо: навык «Стройка» вырос до 3", Color.WHITE]]
	if winter:
		lines = [["Пришла зима: ягоды не растут, озёра замёрзли", Color8(255, 206, 110)], ["Хяклил мёрзнет (−8 °C) — нужно тепло", Color8(255, 206, 110)]]
	var ly := 108.0
	for l in lines:
		var w := _font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		_rrect(Rect2(20, ly - 22, w + 22, 30), 10, Color(HUD_BG, 0.6), Color(0, 0, 0, 0), 0)
		_stext(Vector2(31, ly), l[0], 19, l[1])
		ly += 36
	# Нижнее меню.
	var y := size.y - 104
	_button(Rect2(24, y, 150, 84), "Стройка", "hammer", "amber")
	var right := [["Жители", "people"], ["Наука", "flask"], ["К базе", "home"]]
	var bx := size.x - 24 - 3 * 124 - 250 - 100 - 24
	for b in right:
		_button(Rect2(bx, y, 116, 84), b[0], b[1], "slate")
		bx += 124
	# Скорость — сегменты в одной панели.
	var seg := Rect2(bx, y + 6, 242, 72)
	_soft_panel(seg, HUD_BG, Color(0, 0, 0, 0.25))
	for i in 3:
		var cell := Rect2(seg.position + Vector2(6 + i * 77, 6), Vector2(73, 60))
		if i == 0:
			_soft_panel(cell, Color8(245, 170, 50), Color8(190, 118, 20))
		_stext(Vector2(cell.position.x, cell.position.y + 39), ["×1", "×10", "×20"][i], 22, Color.WHITE, cell.size.x)
	bx += 250
	_button(Rect2(bx, y, 92, 84), "", "menu", "slate")


func _soft_panel(r: Rect2, fill: Color, shade: Color) -> void:
	_rrect(Rect2(r.position + Vector2(0, 4), r.size), 18, shade, Color(0, 0, 0, 0), 0)
	_rrect(r, 18, fill, Color(0, 0, 0, 0), 0)


func _button(r: Rect2, label: String, icon: String, style: String) -> void:
	var col := Color8(92, 104, 132)       # «сланец» — обычные разделы
	if style == "amber":
		col = Color8(245, 165, 40)
	elif style == "green":
		col = Color8(76, 184, 96)
	elif style == "red":
		col = Color8(226, 91, 75)
	var shade := col.darkened(0.3)
	_rrect(Rect2(r.position + Vector2(0, 6), r.size), 18, Color(shade, 0.9), Color(0, 0, 0, 0), 0)
	_rrect(r, 18, col, shade, 2.5)
	if label.is_empty():
		_icon(r.get_center(), icon, 18, true)
	else:
		_icon(r.get_center() + Vector2(0, -12), icon, 15, true)
		_stext(Vector2(r.position.x, r.end.y - 14), label, 16, Color.WHITE, r.size.x)


## Плашка нехватки над стройкой: значок, «есть/надо»; красная — взять негде.
func _pill(at: Vector2, text: String, icon: String, col: Color) -> void:
	var r := Rect2(at, Vector2(86, 32))
	_rrect(Rect2(r.position + Vector2(0, 3), r.size), 16, col.darkened(0.35), Color(0, 0, 0, 0), 0)
	_rrect(r, 16, col, col.darkened(0.3), 2)
	_icon(r.position + Vector2(18, 16), icon, 9)
	_stext(Vector2(r.position.x + 34, r.position.y + 23), text, 17, Color.WHITE)


func _name_tag(at: Vector2, name: String, role: String) -> void:
	var w := 112.0
	var r := Rect2(at - Vector2(w / 2, 26), Vector2(w, 44))
	_rrect(Rect2(r.position + Vector2(0, 3), r.size), 14, Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0)
	_rrect(r, 14, PAPER, PAPER_EDGE, 2)
	_otext(r.position + Vector2(0, 21), name, 17, INK, Color(0, 0, 0, 0), 0, w)
	_otext(r.position + Vector2(0, 37), role, 12, MUTED, Color(0, 0, 0, 0), 0, w)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-7, 17), at + Vector2(7, 17), at + Vector2(0, 26)]), PAPER)


## Текст с мягкой тенью (без толстой обводки).
func _stext(pos: Vector2, text: String, fs: int, col: Color, width := -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(_font, pos + Vector2(0, 2), text, align, width, fs, Color(0, 0, 0, 0.35))
	draw_string(_font, pos, text, align, width, fs, col)


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


## Прямоугольник со скруглением, обрезанный по внешней фигуре (полосы каймы).
func _rect_clip(band: Rect2, outer: Rect2, rad: float, col: Color) -> void:
	var a := _rrect_pts(outer, rad)
	var b := PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
	for poly in Geometry2D.intersect_polygons(a, b):
		draw_colored_polygon(poly, col)


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
