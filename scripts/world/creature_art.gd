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
##   super: bool — сверхюнит (цвет лого, сияние); mood: -1..1 — от грусти к радости.

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

	# Силуэт: туловище + руки от самого верха + ноги — одной заливкой.
	var parts: Array[PackedVector2Array] = [body]
	var fingers: int = g.get("fingers", 3)
	var sway := sin(t * 2.0) * w * 0.02
	for sx in [-1.0, 1.0]:
		parts.append_array(_arm_parts(shape, w, h, base, top, sx, fingers, sway * sx))
		parts.append_array(_leg_parts(shape, w, base, at, sx))
	var sil := _union(parts)

	if g.get("fur", false):
		var fur := _fur(sil, w * 0.045)
		ci.draw_colored_polygon(fur, col.darkened(0.25))

	var light := col.lightened(0.2)
	var dark := col.darkened(0.2)
	ci.draw_polygon(sil, _vgrad(sil, top, at.y, light, dark))
	# Тень по нижним краям и светлый кант по верхним — вместо обводки.
	for p in Geometry2D.clip_polygons(sil, _shift(sil, Vector2(-w * 0.012, -w * 0.035))):
		ci.draw_colored_polygon(p, Color(dark.darkened(0.25), 0.4))
	for p in Geometry2D.clip_polygons(sil, _shift(sil, Vector2(w * 0.01, w * 0.02))):
		ci.draw_colored_polygon(p, Color(light.lightened(0.4), 0.45))
	_highlight(ci, body, Vector2(base.x - w * 0.22, top + h * 0.16), w)

	if g.get("hair", false):
		_hair(ci, Vector2(base.x, top), w, g.get("hair_color", col.darkened(0.4)))

	var face_y := top + h * (0.36 if shape == Shape.TRIANGLE else 0.45)
	_face(ci, Vector2(base.x, face_y), w, g.get("eyes", 1), g.get("mood", 1.0), col, t)

	if is_super:
		_sparkles(ci, base + Vector2(0, -h * 0.5), w, t)


# --- Части тела ----------------------------------------------------------------------

static func _body(shape: int, w: float, h: float) -> PackedVector2Array:
	match shape:
		Shape.TRIANGLE:
			var tri := PackedVector2Array([Vector2(-w * 0.58, -h), Vector2(w * 0.58, -h), Vector2(0, w * 0.04)])
			return _rounded(tri, w * 0.15)
		Shape.SQUARE:
			return _rounded(_rect(Vector2(-w * 0.5, -h), Vector2(w, h)), w * 0.2)
		_:
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				pts.append(Vector2(cos(a) * w * 0.5, -h * 0.5 + sin(a) * h * 0.5))
			return pts


## Рука идёт от верхнего угла, свисает вдоль бока и кончается кистью с пальцами.
static func _arm_parts(shape: int, w: float, h: float, base: Vector2, top: float, sx: float, fingers: int, sway: float) -> Array[PackedVector2Array]:
	var shoulder_x := w * (0.38 if shape == Shape.TRIANGLE else 0.36)
	var p0 := Vector2(base.x + sx * shoulder_x, top + w * 0.12)
	var p1 := p0 + Vector2(sx * w * 0.24, 0.0)
	var p3 := Vector2(base.x + sx * w * 0.64 + sway, top + h * 0.7)
	var p2 := p3 + Vector2(sx * w * 0.03, -w * 0.26)
	var pts := _bezier(p0, p1, p2, p3, 16)
	var out: Array[PackedVector2Array] = [_tube(pts, w * 0.1, w * 0.078)]
	out.append_array(_hand(p3, (p3 - pts[pts.size() - 3]).normalized(), w, fingers, sx))
	return out


## Кисть: ладонь, растопыренные пальцы разной длины с загибом и большой палец.
static func _hand(c: Vector2, dir: Vector2, w: float, fingers: int, sx: float) -> Array[PackedVector2Array]:
	var palm := c + dir * w * 0.04
	var out: Array[PackedVector2Array] = [_circle(palm, w * 0.08, 24)]
	var spread := clampf(0.6 * (fingers - 1), 0.0, 2.6)
	var base_a := dir.angle()
	for i in fingers:
		var k := 0.0 if fingers == 1 else float(i) / (fingers - 1) - 0.5
		var a := base_a + k * spread
		# Пухлые пальцы: средние длиннее, кончики толще и чуть загнуты.
		var length := w * (0.17 - absf(k) * 0.05)
		var root := palm + Vector2.from_angle(a) * w * 0.06
		var mid := root + Vector2.from_angle(a) * length * 0.55
		var tip := mid + Vector2.from_angle(a - sx * 0.3) * length * 0.45
		out.append(_tube(PackedVector2Array([root, mid, tip]), w * 0.032, w * 0.046))
	# Большой палец — в сторону туловища.
	if fingers >= 2:
		var ta := base_a + sx * (spread * 0.5 + 0.75)
		var root := palm + Vector2.from_angle(ta) * w * 0.06
		var tip := root + Vector2.from_angle(ta - sx * 0.5) * w * 0.08
		out.append(_tube(PackedVector2Array([root, tip]), w * 0.036, w * 0.046))
	return out


static func _leg_parts(shape: int, w: float, base: Vector2, at: Vector2, sx: float) -> Array[PackedVector2Array]:
	var lx := base.x + sx * w * (0.11 if shape == Shape.TRIANGLE else 0.2)
	var hip := Vector2(lx, base.y - w * (0.1 if shape == Shape.TRIANGLE else 0.05))
	var ankle := Vector2(lx + sx * w * 0.02, at.y - w * 0.05)
	var foot := _rounded(_rect(Vector2(ankle.x - w * 0.07 + sx * w * 0.04, at.y - w * 0.085), Vector2(w * 0.17, w * 0.085)), w * 0.04)
	return [_tube(PackedVector2Array([hip, ankle]), w * 0.065, w * 0.055), foot]


static func _face(ci: CanvasItem, c: Vector2, w: float, eyes: int, mood: float, col: Color, t: float) -> void:
	var sizes: Array[float] = [0.0, 0.15, 0.115, 0.095]
	var er: float = w * sizes[clampi(eyes, 0, 3)]
	var spots: Array[Vector2] = []
	match eyes:
		1:
			spots = [c]
		2:
			spots = [c + Vector2(-w * 0.13, 0), c + Vector2(w * 0.13, 0)]
		3:
			spots = [c + Vector2(-w * 0.16, w * 0.02), c + Vector2(w * 0.16, w * 0.02), c + Vector2(0, -w * 0.12)]
	var ring := col.darkened(0.55)
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
		ci.draw_circle(pc, er * 0.56, Color(0.28, 0.2, 0.32))
		ci.draw_circle(pc, er * 0.38, PUPIL)
		ci.draw_circle(pc + Vector2(-er * 0.2, -er * 0.22), er * 0.17, Color.WHITE)
		ci.draw_circle(pc + Vector2(er * 0.17, er * 0.18), er * 0.07, Color(1, 1, 1, 0.8))
	if eyes > 0:
		var tilt := -mood * w * 0.025
		for p in spots:
			if eyes == 3 and p.y < c.y:
				continue
			var bw := er * 0.85
			var by := p.y - er * 1.4
			ci.draw_line(Vector2(p.x - bw, by + tilt), Vector2(p.x + bw, by - tilt), col.darkened(0.5), w * 0.034, true)
	# Рот.
	var my := c.y + (er if eyes > 0 else 0.0) + w * 0.075
	var mw := w * (0.12 if eyes > 0 else 0.17)
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
		_ellipse(ci, Vector2(c.x + sx * w * 0.24, my - w * 0.005), Vector2(w * 0.055, w * 0.03), Color(1.0, 0.4, 0.5, 0.3))


static func _hair(ci: CanvasItem, top: Vector2, w: float, col: Color) -> void:
	var polys: Array[PackedVector2Array] = []
	for i in 5:
		var k := (i - 2) / 2.0
		var bx := top.x + k * w * 0.12
		var root_y := top.y + w * 0.06
		var tip := Vector2(top.x + k * w * 0.26, top.y - w * (0.2 - absf(k) * 0.06))
		var mid := Vector2(bx + k * w * 0.03, top.y - w * 0.09)
		polys.append(_tube(PackedVector2Array([Vector2(bx, root_y), mid, tip]), w * 0.05, w * 0.012))
	var shape := _union(polys)
	ci.draw_polygon(shape, _vgrad(shape, top.y - w * 0.2, top.y + w * 0.06, col.lightened(0.3), col))


## Лохматый край: зубцы по контуру силуэта.
static func _fur(sil: PackedVector2Array, len: float) -> PackedVector2Array:
	var big: PackedVector2Array = Geometry2D.offset_polygon(sil, len * 0.5, Geometry2D.JOIN_ROUND)[0]
	var per := 0.0
	for i in big.size():
		per += big[i].distance_to(big[(i + 1) % big.size()])
	var n := int(per / (len * 1.3))
	var out := PackedVector2Array()
	for i in n:
		var p := _along(big, per * i / n)
		var q := _along(big, per * i / n + 1.0)
		var normal := (q - p).normalized().orthogonal()
		out.append(p - normal * (len if i % 2 == 0 else -len * 0.3))
	return out


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


static func _highlight(ci: CanvasItem, body: PackedVector2Array, c: Vector2, w: float) -> void:
	for p in Geometry2D.intersect_polygons(body, _ellipse_poly(c, Vector2(w * 0.14, w * 0.065), -0.35)):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.42))
	ci.draw_circle(c + Vector2(w * 0.17, -w * 0.03), w * 0.025, Color(1, 1, 1, 0.5))


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
	return Color.from_ok_hsl(h, s, l)


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
