class_name CreatureArt
extends RefCounted
## Мультяшные жители без головы: глаза и рот прямо на туловище.
## Стиль — как в Brawl Stars / Clash Royale, но без чёрной обводки: тело, руки и ноги —
## один сплошной силуэт одного цвета; объём даёт переход от светлого верха к тёмному низу,
## тень по нижним краям, светлый кант по верхним и блик.
##
## Внешность задаётся словарём:
##   color: Color — цвет тела; shape: Shape; eyes: 0..3; fingers: 1..7;
##   hair: bool — хохолок; fur: bool — шерсть; hair_color: Color (необязательно);
##   super: bool — сверхюнит (цвет лого, сияние); mood: -1..1 — от грусти к радости;
##   мутации: glow — светится, gills — жабры, shell — панцирь, long_arms — длинные руки,
##   antennae — усики, horn — рог, size: 1 гигант / -1 кроха, albino — альбинос,
##   pattern: 1 полосы / 2 пятна, melanist — чёрный.

## TRIANGLE — перевёрнутый: широкий верх, острие внизу.
enum Shape { TRIANGLE, SQUARE, ROUND }

## Любимый цвет: градиент лого игры. Сверхюнит — цвет рядом с этим градиентом.
const SUPER_A := Color8(44, 214, 193)
const SUPER_B := Color8(9, 147, 179)
const PUPIL := Color(0.13, 0.1, 0.18)


## Рисует жителя: at — точка на земле между ступнями, w — ширина туловища в пикселях.
static func draw(ci: CanvasItem, at: Vector2, w: float, g: Dictionary, t := 0.0) -> void:
	var col: Color = g.get("color", Color(0.9, 0.4, 0.3))
	var shape: int = g.get("shape", Shape.TRIANGLE)
	var is_super: bool = g.get("super", false)
	if is_super:
		col = SUPER_A.lerp(SUPER_B, 0.45)
	var albino: bool = g.get("albino", false)
	var iris := Color(0.28, 0.2, 0.32)
	if albino:
		col = Color(0.97, 0.94, 0.93)
		iris = Color(0.85, 0.35, 0.45)
	if g.get("melanist", false):
		# Меланист — чёрный, с янтарными глазами.
		col = Color(0.16, 0.15, 0.19)
		iris = Color(0.95, 0.7, 0.15)
	match int(g.get("size", 0)):
		1:
			w *= 1.25
		-1:
			w *= 0.72
	var leg := w * 0.2
	var breathe := 1.0 + sin(t * 2.4) * 0.02
	var h := w * (0.95 if shape == Shape.TRIANGLE else 0.9) * breathe
	var base := at + Vector2(0, -leg) # низ туловища
	var body := _shift(_body(shape, w, h), base)
	var top := base.y - h
	for p in body:
		top = minf(top, p.y)

	# Тень на земле.
	_ellipse(ci, at + Vector2(0, w * 0.015), Vector2(w * 0.5, w * 0.08), Color(0, 0, 0, 0.2))
	if is_super:
		_aura(ci, base + Vector2(0, -h * 0.5), w, t)
	if g.get("glow", false):
		# Светится: мягкое свечение вокруг.
		for i in 7:
			ci.draw_circle(base + Vector2(0, -h * 0.5), w * (1.05 - i * 0.09), Color(col.lightened(0.6), 0.06))
	if g.get("shell", false):
		_shell(ci, body, w, col)

	# Силуэт: туловище + руки от самого верха + ноги — одной заливкой.
	# Сначала туловище, руки и ноги сливаем и сглаживаем стыки (подмышки, пах) —
	# контур идёт одной плавной линией, без порожков. Потом добавляем кисти.
	var parts: Array[PackedVector2Array] = [body]
	var hands: Array[PackedVector2Array] = []
	var fingers: int = g.get("fingers", 4)
	var sway := sin(t * 2.0) * w * 0.02
	for sx in [-1.0, 1.0]:
		var arm := _arm_parts(shape, w, h, base, top, sx, fingers, sway * sx, g.get("long_arms", false))
		# Ладонь сглаживаем вместе с рукой — запястье без впадины; пальцы — потом.
		parts.append(arm[0])
		parts.append(arm[1])
		hands.append_array(arm.slice(2))
		parts.append_array(_leg_parts(shape, w, base, at, sx))
	# Сильное сглаживание: плечи, подмышки и бёдра — плавные дуги без ступенек.
	# Оно же заливает просвет между ногами — его вырезаем аркой.
	var core := _union(parts)
	var open := _open(core, w * 0.03)
	if _drawable(open):
		core = open
	# Треугольнику — сильное сглаживание; у широких круга и квадрата руки ближе к бокам,
	# сильное слепило бы их с туловищем.
	var smooth_core := _smooth(core, w * (0.1 if shape == Shape.TRIANGLE else 0.05))
	if _drawable(smooth_core):
		core = smooth_core
		var gap := _crotch(shape, w, base, at)
		var cut := _largest(Geometry2D.clip_polygons(core, gap))
		if _drawable(cut):
			core = cut
	hands.push_front(core)
	var sil := _union(hands)
	var smooth_sil := _smooth(sil, w * 0.01)
	if _drawable(smooth_sil):
		sil = smooth_sil

	if g.get("fur", false):
		# Пушистый край: кружки по контуру туловища, рук и ног — мягкое «облачко».
		_fur(ci, core, w * 0.04, top, at.y, col)

	var light := col.lightened(0.2)
	var dark := col.darkened(0.2)
	ci.draw_polygon(sil, _vgrad(sil, top, at.y, light, dark))
	# Тень по нижним краям и светлый кант по верхним — вместо обводки.
	for p in Geometry2D.clip_polygons(sil, _shift(sil, Vector2(0, -w * 0.035))):
		if _drawable(p):
			ci.draw_colored_polygon(p, Color(dark.darkened(0.2), 0.3))
	for p in Geometry2D.clip_polygons(sil, _shift(sil, Vector2(0, w * 0.02))):
		if _drawable(p):
			ci.draw_colored_polygon(p, Color(light.lightened(0.4), 0.3))

	match int(g.get("pattern", 0)):
		1:
			_stripes(ci, body, base, top, w, h, col)
		2:
			_spots(ci, body, base, top, w, h, col)
	if g.get("gills", false):
		_gills(ci, body, base, top, w, h, col)
	if g.get("glow", false):
		for p in Geometry2D.intersect_polygons(body, _ellipse_poly(Vector2(base.x, top + h * 0.45), Vector2(w * 0.35, h * 0.4))):
			ci.draw_colored_polygon(p, Color(1, 1, 0.85, 0.18))
	if g.get("fur", false):
		# Несколько прядок на теле — фактура шерсти.
		for k in [Vector2(-0.22, 0.6), Vector2(0.24, 0.55), Vector2(-0.1, 0.8), Vector2(0.14, 0.82), Vector2(0.3, 0.3), Vector2(-0.3, 0.32)]:
			var pc := Vector2(base.x + k.x * w, top + k.y * h)
			if Geometry2D.is_point_in_polygon(pc, body):
				var tuft := PackedVector2Array([pc + Vector2(-w * 0.03, -w * 0.02), pc + Vector2(0, w * 0.025), pc + Vector2(w * 0.03, -w * 0.02)])
				ci.draw_polyline(tuft, col.darkened(0.22), w * 0.014, true)
	if g.get("hair", false):
		_hair(ci, body, Vector2(base.x, top), w, h, g.get("hair_color", col.darkened(0.4)))

	if g.get("horn", false):
		_horn(ci, Vector2(base.x, top), w)
	if g.get("antennae", false):
		_antennae(ci, Vector2(base.x, top), w, col, t)

	var face_y := top + h * (0.36 if shape == Shape.TRIANGLE else 0.45)
	_face(ci, Vector2(base.x, face_y), w, g.get("eyes", 1), g.get("mood", 1.0), col, t, iris, g.get("female", false))
	if g.get("glow", false):
		for i in 6:
			var a := TAU * i / 6.0 + t * 0.5
			ci.draw_circle(base + Vector2(0, -h * 0.5) + Vector2(cos(a) * w * 0.7, sin(a) * h * 0.6), w * 0.018, Color(1, 1, 0.8, 0.7))

	if is_super:
		_sparkles(ci, base + Vector2(0, -h * 0.5), w, t)


# --- Части тела ----------------------------------------------------------------------

static func _body(shape: int, w: float, h: float) -> PackedVector2Array:
	match shape:
		Shape.TRIANGLE:
			var tri := PackedVector2Array([Vector2(-w * 0.58, -h), Vector2(w * 0.58, -h), Vector2(0, w * 0.04)])
			return _rounded(tri, w * 0.15)
		Shape.SQUARE:
			return _rounded(_rect(Vector2(-w * 0.35, -h), Vector2(w * 0.7, h)), w * 0.16)
		_:
			# Круг: сверху — плоская грань со скруглёнными углами, снизу — полукруг.
			var r := w * 0.4
			var pts := PackedVector2Array([Vector2(-r, -h), Vector2(r, -h)])
			for i in 33:
				var a := PI * i / 32.0
				pts.append(Vector2(cos(a) * r, -r + sin(a) * r))
			return _rounded(pts, w * 0.17)


## Рука идёт от верхнего угла, свисает вдоль бока и кончается кистью с пальцами.
static func _arm_parts(shape: int, w: float, h: float, base: Vector2, top: float, sx: float, fingers: int, sway: float, long := false) -> Array[PackedVector2Array]:
	var r0 := w * 0.1
	var p0: Vector2
	var p1: Vector2
	var p3: Vector2
	match shape:
		Shape.ROUND, Shape.SQUARE:
			# Верх руки — продолжение верхней грани.
			var half := w * (0.4 if shape == Shape.ROUND else 0.35)
			p0 = Vector2(base.x + sx * (half - w * 0.18), top + r0)
			p1 = p0 + Vector2(sx * w * 0.36, 0.0)
			p3 = Vector2(base.x + sx * (half + w * 0.3) + sway, top + h * 0.78)
		_:
			# Верх руки идёт ровно по верхней линии туловища — плечо без бугорка.
			p0 = Vector2(base.x + sx * w * 0.3, top + r0)
			p1 = p0 + Vector2(sx * w * 0.3, 0.0)
			p3 = Vector2(base.x + sx * w * 0.64 + sway, top + h * 0.7)
	if long:
		# Длинные руки — почти до земли.
		p3 += Vector2(sx * w * 0.08, h * 0.32)
	var p2 := p3 + Vector2(sx * w * 0.03, -w * 0.26)
	var pts := _bezier(p0, p1, p2, p3, 16)
	var out: Array[PackedVector2Array] = [_tube(pts, r0, w * 0.078)]
	out.append_array(_hand(p3, (p3 - pts[pts.size() - 3]).normalized(), w, fingers, sx))
	return out


## Кисть: ладонь, растопыренные пальцы разной длины с загибом и большой палец.
static func _hand(c: Vector2, dir: Vector2, w: float, fingers: int, _sx: float) -> Array[PackedVector2Array]:
	var palm := c + dir * w * 0.03
	var out: Array[PackedVector2Array] = [_circle(palm, w * 0.08, 24)]
	# Одинаковые прямые пальцы ровным веером, без большого.
	# До пяти пальцев — тот же шаг веера, что у четырёх; больше — веер шире, пальцы тоньше.
	var step := 0.5 if fingers <= 5 else 2.4 / (fingers - 1)
	var r := w * 0.026 * (1.0 if fingers <= 5 else 5.0 / fingers)
	var base_a := dir.angle()
	for i in fingers:
		var a := base_a + (float(i) - (fingers - 1) * 0.5) * step
		out.append(_tube(PackedVector2Array([palm, palm + Vector2.from_angle(a) * w * 0.21]), r, r * 0.96))
	return out


## Просвет между ногами: арка от паха до земли.
static func _crotch(shape: int, w: float, base: Vector2, at: Vector2) -> PackedVector2Array:
	var top_half := w * 0.045
	var bottom_half := w * (0.075 if shape == Shape.TRIANGLE else 0.16)
	var cy := base.y - w * (0.07 if shape == Shape.TRIANGLE else -0.03) + top_half
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(Vector2(base.x + cos(a) * top_half, cy + sin(a) * top_half))
	pts.append(Vector2(base.x + bottom_half, at.y + w * 0.05))
	pts.append(Vector2(base.x - bottom_half, at.y + w * 0.05))
	return pts


static func _leg_parts(shape: int, w: float, base: Vector2, at: Vector2, sx: float) -> Array[PackedVector2Array]:
	var lx := base.x + sx * w * (0.11 if shape == Shape.TRIANGLE else 0.2)
	var hip := Vector2(lx, base.y - w * (0.1 if shape == Shape.TRIANGLE else 0.05))
	var ankle := Vector2(lx + sx * w * 0.02, at.y - w * 0.05)
	var foot := _rounded(_rect(Vector2(ankle.x - w * 0.085 + sx * w * 0.04, at.y - w * 0.085), Vector2(w * 0.17, w * 0.085)), w * 0.04)
	return [_tube(PackedVector2Array([hip, ankle]), w * 0.065, w * 0.055), foot]


## Где глаза и какого размера: 1 — по центру, 2 — в ряд, 3 — треугольником,
## больше — рядами (по два или по три).
static func eye_layout(c: Vector2, w: float, n: int) -> Array:
	var spots: Array[Vector2] = []
	match n:
		0:
			return [spots, 0.0]
		1:
			spots = [c]
			return [spots, w * 0.12]
		2:
			spots = [c + Vector2(-w * 0.13, 0), c + Vector2(w * 0.13, 0)]
			return [spots, w * 0.095]
		3:
			spots = [c + Vector2(-w * 0.16, w * 0.02), c + Vector2(w * 0.16, w * 0.02), c + Vector2(0, -w * 0.12)]
			return [spots, w * 0.08]
	var per_row := 3 if n > 4 else 2
	var rows := ceili(float(n) / per_row)
	var er := w * (0.07 if n <= 4 else 0.058 if rows <= 2 else 0.048)
	var dx := er * 2.5
	var dy := er * 2.6
	var left := n
	for r in rows:
		var in_row := mini(per_row, left)
		left -= in_row
		for i in in_row:
			spots.append(c + Vector2((i - (in_row - 1) * 0.5) * dx, (r - (rows - 1) * 0.5) * dy - er * 0.3))
	return [spots, er]


static func _face(ci: CanvasItem, c: Vector2, w: float, eyes: int, mood: float, col: Color, t: float, iris := Color(0.28, 0.2, 0.32), female := false) -> void:
	var layout := eye_layout(c, w, eyes)
	var spots: Array[Vector2] = layout[0]
	var er: float = layout[1]
	var ring := col.darkened(0.55) if col.get_luminance() > 0.2 else Color(0.05, 0.04, 0.06)
	var blink := fmod(t, 3.7) < 0.12
	var look := Vector2(sin(t * 0.7) * 0.25, 0.08)
	for p in spots:
		ci.draw_circle(p, er + w * 0.016, ring)
		if blink:
			ci.draw_circle(p, er, col.darkened(0.1))
			ci.draw_line(p + Vector2(-er * 0.8, er * 0.1), p + Vector2(er * 0.8, er * 0.1), ring, w * 0.022, true)
			continue
		_ellipse(ci, p, Vector2(er, er * 1.05), Color.WHITE)
		# Верхнее веко цвета тела — взгляд живее.
		var lid := Geometry2D.intersect_polygons(_ellipse_poly(p, Vector2(er, er * 1.05)),
			_ellipse_poly(p + Vector2(0, -er * 1.25), Vector2(er * 1.3, er * 0.55)))
		for l in lid:
			ci.draw_colored_polygon(l, col.darkened(0.08))
		var pc := p + look * er * 0.45
		ci.draw_circle(pc, er * 0.56, iris)
		if female:
			# Ресницы — короткие, у внешних уголков глаза, загнуты наружу (до брови не достают).
			var sides: Array[float] = [-1.0, 1.0]
			if spots.size() >= 2 and p.x < c.x - 1.0:
				sides = [-1.0]
			elif spots.size() >= 2 and p.x > c.x + 1.0:
				sides = [1.0]
			for sx in sides:
				for k: float in [0.25, 0.6]:
					var a := -k if sx > 0.0 else PI + k
					var from := p + Vector2(cos(a) * er, sin(a) * er * 1.05)
					var dir := Vector2(sx * 0.9, -0.55 - k * 0.5).normalized()
					var tip := from + dir * er * 0.42
					ci.draw_polyline(_bezier(from, from + dir * er * 0.2, tip + Vector2(0, er * 0.05), tip, 5), ring, maxf(1.0, er * 0.12), true)
		ci.draw_circle(pc, er * 0.38, PUPIL)
		ci.draw_circle(pc + Vector2(-er * 0.2, -er * 0.22), er * 0.17, Color.WHITE)
		ci.draw_circle(pc + Vector2(er * 0.17, er * 0.18), er * 0.07, Color(1, 1, 1, 0.8))
	if eyes > 0:
		var tilt := -mood * w * 0.02
		for p in spots:
			var bw := er * 0.85
			var by := p.y - er * 1.4
			ci.draw_line(Vector2(p.x - bw, by + tilt), Vector2(p.x + bw, by - tilt), col.darkened(0.5), w * 0.028, true)
	# Рот — под нижним глазом.
	var low := c.y
	for p in spots:
		low = maxf(low, p.y)
	var my := low + (er if eyes > 0 else 0.0) + w * 0.06
	var mw := w * (0.095 if eyes > 0 else 0.14)
	var smile := clampf(mood, -1.0, 1.0)
	var mouth := PackedVector2Array()
	for i in 17:
		var a := PI * i / 16.0
		mouth.append(Vector2(c.x - cos(a) * mw, my + sin(a) * mw * 0.8 * maxf(0.25, absf(smile))))
	if smile < 0.0:
		mouth = _shift(_flip_y(mouth, my), Vector2(0, mw * 0.45))
	ci.draw_colored_polygon(mouth, Color(0.36, 0.06, 0.12))
	for p in Geometry2D.intersect_polygons(mouth, _circle(Vector2(c.x + mw * 0.15, my + mw * 0.8), mw * 0.5, 20)):
		ci.draw_colored_polygon(p, Color(0.95, 0.42, 0.5))
	if smile > 0.0:
		ci.draw_colored_polygon(_rect(Vector2(c.x - mw * 0.42, my), Vector2(mw * 0.34, mw * 0.24)), Color.WHITE)
	for sx in [-1.0, 1.0]:
		_ellipse(ci, Vector2(c.x + sx * w * 0.2, my - w * 0.005), Vector2(w * 0.045, w * 0.025), Color(1.0, 0.4, 0.5, 0.3))


## Волосы: пышная шевелюра своего цвета — объём над макушкой с вихрами, чёлка короче
## посередине, по бокам длинные пряди; светлые блики прядей и тень от чёлки на теле.
static func _hair(ci: CanvasItem, body: PackedVector2Array, top: Vector2, w: float, h: float, col: Color) -> void:
	var hw := 0.0
	for p in body:
		if p.y < top.y + w * 0.16:
			hw = maxf(hw, absf(p.x - top.x))
	hw += w * 0.05
	var pts := PackedVector2Array()
	# Верх: пышный купол с вихрами.
	for i in 33:
		var k := float(i) / 32.0 * 2.0 - 1.0
		var dome := sqrt(maxf(0.0, 1.0 - k * k))
		var tuft := pow(absf(sin(PI * (k + 1.0) * 2.5)), 3.0) * w * 0.045
		pts.append(Vector2(top.x + k * hw, top.y + w * 0.12 - dome * w * 0.26 - tuft * dome))
	# Низ: пряди справа налево — посередине чёлка короче, по бокам пряди длинные.
	var locks := 9
	for i in range(locks * 2, -1, -1):
		var k := float(i) / (locks * 2) * 2.0 - 1.0
		var tip := i % 2 == 1
		var len := w * (0.1 + 0.26 * pow(absf(k), 3.0))
		pts.append(Vector2(top.x + k * hw * (1.02 if tip else 0.98), top.y + (len if tip else len * 0.5)))
	var shape := _rounded(pts, w * 0.01)
	# Тень от шевелюры на теле.
	for p in Geometry2D.intersect_polygons(body, _shift(shape, Vector2(0, w * 0.025))):
		ci.draw_colored_polygon(p, Color(0, 0, 0, 0.18))
	ci.draw_polygon(shape, _vgrad(shape, top.y - w * 0.15, top.y + w * 0.3, col.lightened(0.25), col.darkened(0.2)))
	# Светлые пряди.
	for i in range(1, locks * 2, 2):
		var k := float(i) / (locks * 2) * 2.0 - 1.0
		var len := w * (0.1 + 0.26 * pow(absf(k), 3.0))
		var tip := Vector2(top.x + k * hw * 0.98, top.y + len - w * 0.03)
		var root := Vector2(top.x + k * hw * 0.55, top.y - w * 0.09)
		ci.draw_polyline(_bezier(root, root + Vector2(k * w * 0.05, w * 0.02), tip + Vector2(0, -w * 0.06), tip, 10),
			Color(col.lightened(0.45), 0.55), w * 0.012, true)
	# Блик на макушке.
	var arc := PackedVector2Array()
	for i in 11:
		var a := PI * 1.15 + PI * 0.4 * i / 10.0
		arc.append(top + Vector2(cos(a) * hw * 0.7, w * 0.05 + sin(a) * w * 0.16))
	ci.draw_polyline(arc, Color(1, 1, 1, 0.5), w * 0.024, true)


## Панцирь за спиной: выглядывает над макушкой и по бокам, с пластинами.
static func _shell(ci: CanvasItem, body: PackedVector2Array, w: float, col: Color) -> void:
	var big := _largest(Geometry2D.offset_polygon(body, w * 0.09, Geometry2D.JOIN_ROUND))
	if big.is_empty():
		return
	var shell_col := Color(0.55, 0.42, 0.25).lerp(col, 0.15)
	ci.draw_polygon(big, _vgrad(big, big[0].y - w, big[0].y + w, shell_col.lightened(0.2), shell_col.darkened(0.3)))
	var b := Rect2(big[0], Vector2.ZERO)
	for p in big:
		b = b.expand(p)
	# Пластины — шестиугольники по краю панциря.
	var y := b.position.y + w * 0.06
	while y < b.end.y:
		var x := b.position.x + w * 0.06
		while x < b.end.x:
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(Vector2(x, y) + Vector2.from_angle(TAU * i / 6.0) * w * 0.06)
			if Geometry2D.is_point_in_polygon(Vector2(x, y), big):
				ci.draw_polyline(hex + PackedVector2Array([hex[0]]), shell_col.darkened(0.45), w * 0.012, true)
			x += w * 0.11
		y += w * 0.1


static func _stripes(ci: CanvasItem, body: PackedVector2Array, base: Vector2, top: float, w: float, h: float, col: Color) -> void:
	for i in 4:
		var y := top + h * (0.18 + i * 0.22)
		var band := PackedVector2Array()
		for j in 13:
			band.append(Vector2(base.x - w + w * 2.0 * j / 12.0, y + sin(j * 0.9) * w * 0.02))
		for j in range(12, -1, -1):
			band.append(Vector2(base.x - w + w * 2.0 * j / 12.0, y + w * 0.055 + sin(j * 0.9) * w * 0.02))
		for p in Geometry2D.intersect_polygons(body, band):
			ci.draw_colored_polygon(p, Color(col.darkened(0.4), 0.45))


static func _spots(ci: CanvasItem, body: PackedVector2Array, base: Vector2, top: float, w: float, h: float, col: Color) -> void:
	for k in [Vector3(-0.3, 0.25, 0.06), Vector3(0.28, 0.2, 0.05), Vector3(-0.18, 0.72, 0.07), Vector3(0.2, 0.68, 0.055),
			Vector3(0.0, 0.88, 0.04), Vector3(-0.38, 0.5, 0.035), Vector3(0.36, 0.48, 0.04)]:
		for p in Geometry2D.intersect_polygons(body, _circle(Vector2(base.x + k.x * w, top + k.y * h), k.z * w, 16)):
			ci.draw_colored_polygon(p, Color(col.darkened(0.4), 0.5))


## Жабры: три изогнутые щели на каждом боку.
static func _gills(ci: CanvasItem, body: PackedVector2Array, base: Vector2, top: float, w: float, h: float, col: Color) -> void:
	for sx in [-1.0, 1.0]:
		for i in 3:
			var c := Vector2(base.x + sx * w * 0.24, top + h * (0.52 + i * 0.09))
			if not Geometry2D.is_point_in_polygon(c, body):
				continue
			var arc := PackedVector2Array()
			for j in 7:
				var a := -0.9 + 1.8 * j / 6.0
				arc.append(c + Vector2(-sx * cos(a) * w * 0.03, sin(a) * w * 0.045))
			ci.draw_polyline(arc, col.darkened(0.45), w * 0.016, true)


## Рог: изогнутый конус на макушке с кольцами.
static func _horn(ci: CanvasItem, top: Vector2, w: float) -> void:
	var tip := top + Vector2(w * 0.04, -w * 0.24)
	var pts := PackedVector2Array([top + Vector2(-w * 0.07, w * 0.04), top + Vector2(-w * 0.04, -w * 0.12), tip,
		top + Vector2(w * 0.05, -w * 0.1), top + Vector2(w * 0.07, w * 0.04)])
	var horn := _rounded(pts, w * 0.012)
	var ivory := Color(0.98, 0.93, 0.8)
	ci.draw_polygon(horn, _vgrad(horn, tip.y, top.y, ivory, ivory.darkened(0.25)))
	for i in 3:
		var y := top.y - w * (0.02 + i * 0.06)
		var half := w * (0.065 - i * 0.017)
		ci.draw_line(Vector2(top.x - half, y), Vector2(top.x + half, y + w * 0.01), ivory.darkened(0.35), w * 0.01, true)


## Усики-антенны с шариками на концах.
static func _antennae(ci: CanvasItem, top: Vector2, w: float, col: Color, t: float) -> void:
	for sx in [-1.0, 1.0]:
		var root := top + Vector2(sx * w * 0.12, w * 0.03)
		var tip := root + Vector2(sx * w * 0.12 + sin(t * 2.0 + sx) * w * 0.02, -w * 0.26)
		var curve := _bezier(root, root + Vector2(0, -w * 0.15), tip + Vector2(-sx * w * 0.1, 0), tip, 12)
		ci.draw_polyline(curve, col.darkened(0.15), w * 0.03, true)
		ci.draw_circle(tip, w * 0.05, col.lightened(0.35))
		ci.draw_circle(tip + Vector2(-w * 0.015, -w * 0.015), w * 0.016, Color(1, 1, 1, 0.6))


## Пушистый край: кружки вдоль контура, цвет — как у тела на этой высоте, чуть темнее.
static func _fur(ci: CanvasItem, sil: PackedVector2Array, r: float, y0: float, y1: float, col: Color) -> void:
	var per := 0.0
	for i in sil.size():
		per += sil[i].distance_to(sil[(i + 1) % sil.size()])
	var n := int(per / (r * 1.1))
	for i in n:
		var p := _along(sil, per * i / n)
		var k := clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)
		ci.draw_circle(p, r * (0.8 + 0.25 * sin(i * 2.3)), col.lightened(0.1).lerp(col.darkened(0.3), k))


static func _aura(ci: CanvasItem, c: Vector2, w: float, t: float) -> void:
	var pulse := 1.0 + sin(t * 3.0) * 0.05
	for i in 6:
		ci.draw_circle(c, w * (1.0 - i * 0.09) * pulse, Color(SUPER_A, 0.08))
	for i in 12:
		var a := TAU * i / 12.0 + t * 0.3
		var p1 := c + Vector2.from_angle(a) * w * 0.45
		var p2 := c + Vector2.from_angle(a) * w * 1.1
		var side := Vector2.from_angle(a + PI * 0.5) * w * 0.05
		ci.draw_colored_polygon(PackedVector2Array([p1 - side, p2, p1 + side]), Color(1.0, 0.95, 0.6, 0.16))


static func _sparkles(ci: CanvasItem, c: Vector2, w: float, t: float) -> void:
	var spots := [Vector2(-0.7, -0.55), Vector2(0.72, -0.4), Vector2(0.6, 0.45), Vector2(-0.62, 0.35), Vector2(0.05, -0.95)]
	for i in spots.size():
		var s := (0.6 + 0.4 * sin(t * 4.0 + i * 1.7)) * w * 0.07
		var pts := PackedVector2Array()
		for j in 8:
			var a := TAU * j / 8.0 - PI * 0.5
			pts.append(c + spots[i] * w + Vector2.from_angle(a) * (s if j % 2 == 0 else s * 0.3))
		ci.draw_colored_polygon(pts, Color(1.0, 0.97, 0.75))


# --- Цвет ---------------------------------------------------------------------------

## Смешивание цветов «как у живых»: по кругу оттенков (OKHSL), а не в RGB —
## дети остаются яркими: красный + синий → фиолетовый, а не бурый.
static func mix(a: Color, b: Color, k: float) -> Color:
	var ha := a.ok_hsl_h
	var hb := b.ok_hsl_h
	# Серый почти без оттенка — берём оттенок второго родителя.
	if a.ok_hsl_s < 0.08:
		ha = hb
	if b.ok_hsl_s < 0.08:
		hb = ha
	var dh := fposmod(hb - ha + 0.5, 1.0) - 0.5
	var h := fposmod(ha + dh * k, 1.0)
	var s := maxf(lerpf(a.ok_hsl_s, b.ok_hsl_s, k), maxf(a.ok_hsl_s, b.ok_hsl_s) * 0.92)
	var l := lerpf(a.ok_hsl_l, b.ok_hsl_l, k)
	var c := Color.from_ok_hsl(h, s, l)
	# Насыщенность и яркость не ниже, чем у родителей: у ярких родителей — яркие дети,
	# без пастели и «горчицы».
	return Color.from_hsv(c.h, maxf(c.s, lerpf(a.s, b.s, k)), maxf(c.v, lerpf(a.v, b.v, k)))


## Насколько цвет близок к градиенту лого (0 — точно на нём).
static func super_distance(c: Color) -> float:
	var best := INF
	for i in 21:
		var g := SUPER_A.lerp(SUPER_B, i / 20.0)
		best = minf(best, Vector3(c.r - g.r, c.g - g.g, c.b - g.b).length())
	return best


# --- Геометрия ------------------------------------------------------------------------

static func _union(parts: Array[PackedVector2Array]) -> PackedVector2Array:
	var acc: PackedVector2Array = parts[0]
	for i in range(1, parts.size()):
		var merged := Geometry2D.merge_polygons(acc, parts[i])
		var best := acc
		var best_area := -1.0
		for m in merged:
			if Geometry2D.is_polygon_clockwise(m):
				continue # дырка
			var area := _area(m)
			if area > best_area:
				best_area = area
				best = m
		acc = best
	return acc


## Сглаживание вогнутых углов (морфологическое «закрытие»): раздуть и сжать обратно.
## Стыки рук и ног с туловищем становятся плавными, выпуклые края не меняются.
static func _smooth(poly: PackedVector2Array, r: float) -> PackedVector2Array:
	var grown := _largest(Geometry2D.offset_polygon(poly, r, Geometry2D.JOIN_ROUND))
	if grown.is_empty():
		return poly
	var back := _largest(Geometry2D.offset_polygon(grown, -r, Geometry2D.JOIN_ROUND))
	return back if not back.is_empty() else poly


## «Открытие»: сжать и раздуть обратно — срезает мелкие выпуклые бугорки.
static func _open(poly: PackedVector2Array, r: float) -> PackedVector2Array:
	var shrunk := _largest(Geometry2D.offset_polygon(poly, -r, Geometry2D.JOIN_ROUND))
	if shrunk.is_empty():
		return poly
	var back := _largest(Geometry2D.offset_polygon(shrunk, r, Geometry2D.JOIN_ROUND))
	return back if not back.is_empty() else poly


## Можно ли залить многоугольник (не вырожден после сглаживания).
static func _drawable(p: PackedVector2Array) -> bool:
	return p.size() >= 3 and not Geometry2D.triangulate_polygon(p).is_empty()


static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for p: PackedVector2Array in polys:
		if Geometry2D.is_polygon_clockwise(p):
			continue
		var a := _area(p)
		if a > best_area:
			best_area = a
			best = p
	return best


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return absf(s) * 0.5


static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(p0.bezier_interpolate(p1, p2, p3, float(i) / n))
	return out


## Трубка по ломаной: толщина от r0 к r1, концы скруглены.
static func _tube(pts: PackedVector2Array, r0: float, r1: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var r := lerpf(r0, r1, float(i) / maxf(1.0, n - 1))
		var nrm := d.orthogonal() * r
		left.append(pts[i] + nrm)
		right.append(pts[i] - nrm)
	var poly := left
	var rev := right.duplicate()
	rev.reverse()
	poly.append_array(rev)
	var out := Geometry2D.merge_polygons(poly, _circle(pts[0], r0, 16))
	var shape: PackedVector2Array = out[0] if not out.is_empty() else poly
	out = Geometry2D.merge_polygons(shape, _circle(pts[n - 1], r1, 16))
	return out[0] if not out.is_empty() else shape


static func _along(poly: PackedVector2Array, d: float) -> Vector2:
	d = fposmod(d, 1e9)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / maxf(l, 0.001))
		d -= l
	return poly[0]


static func _rect(pos: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)])


static func _rounded(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	var inner := Geometry2D.offset_polygon(pts, -r)
	if inner.is_empty():
		return pts
	var out := Geometry2D.offset_polygon(inner[0], r, Geometry2D.JOIN_ROUND)
	return out[0] if not out.is_empty() else pts


static func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out


static func _flip_y(pts: PackedVector2Array, y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, 2.0 * y - p.y))
	return out


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	return _ellipse_poly(c, Vector2(r, r), 0.0, n)


static func _ellipse_poly(c: Vector2, r: Vector2, rot := 0.0, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	return pts


static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(_ellipse_poly(c, r), col)


static func _vgrad(pts: PackedVector2Array, y0: float, y1: float, top: Color, bottom: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	return cols
