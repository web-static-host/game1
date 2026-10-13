class_name CreatureArt
extends RefCounted
## Мультяшные жители без головы: глаза и рот прямо на туловище.
## Стиль — как в Brawl Stars / Clash Royale: жирный тёмный контур, сочная заливка
## с переходом от светлого верха к тёмному низу, тень по нижнему краю, блик сверху.
##
## Внешность задаётся словарём:
##   color: Color — цвет тела; shape: Shape; eyes: 0..3; fingers: 1..7;
##   hair: bool — хохолок; fur: bool — шерсть; hair_color: Color (необязательно);
##   super: bool — сверхюнит (цвет лого, сияние); mood: -1..1 — от грусти к радости.

enum Shape { TRIANGLE, SQUARE, ROUND }

const OUTLINE := Color(0.11, 0.08, 0.16)
## Любимый цвет: градиент лого игры. Сверхюнит — цвет рядом с этим градиентом.
const SUPER_A := Color8(44, 214, 193)
const SUPER_B := Color8(9, 147, 179)


## Рисует жителя: at — точка между ступнями, w — ширина туловища в пикселях.
static func draw(ci: CanvasItem, at: Vector2, w: float, g: Dictionary, t := 0.0) -> void:
	var col: Color = g.get("color", Color(0.9, 0.4, 0.3))
	var shape: int = g.get("shape", Shape.ROUND)
	var is_super: bool = g.get("super", false)
	var ow := w * 0.055 # толщина контура
	var h := w * (1.05 if shape == Shape.TRIANGLE else 0.92)
	var leg := w * 0.16
	# Лёгкое дыхание: тело чуть сжимается и растягивается.
	var breathe := 1.0 + sin(t * 2.4) * 0.025
	var base := at + Vector2(0, -leg)
	var body := _body(shape, w, h * breathe)
	body = _shift(body, base)
	var top_y := base.y - h * breathe
	for p in body:
		top_y = minf(top_y, p.y)

	# Тень на земле.
	_ellipse(ci, at + Vector2(0, w * 0.02), Vector2(w * 0.55, w * 0.1), Color(0, 0, 0, 0.22))
	if is_super:
		_aura(ci, base + Vector2(0, -h * 0.5), w, t)

	# Ноги.
	for sx in [-1.0, 1.0]:
		var lx: float = at.x + sx * w * 0.2
		var leg_poly := _rounded(_rect(Vector2(lx - w * 0.08, base.y - w * 0.06), Vector2(w * 0.16, leg + w * 0.06)), w * 0.06)
		_outlined(ci, leg_poly, col.darkened(0.35), ow)
		var foot := _rounded(_rect(Vector2(lx - w * 0.11 + sx * w * 0.03, at.y - w * 0.07), Vector2(w * 0.22, w * 0.09)), w * 0.045)
		_outlined(ci, foot, col.darkened(0.45), ow)

	# Руки с пальцами — за туловищем.
	var fingers: int = g.get("fingers", 3)
	for sx in [-1.0, 1.0]:
		var shoulder := Vector2(base.x + sx * _half_width_at(shape, w, 0.45) * 0.92, base.y - h * 0.42)
		var hand := shoulder + Vector2(sx * w * 0.2, w * 0.16 + sin(t * 2.4 + sx) * w * 0.015)
		_arm(ci, shoulder, hand, w, col, ow, fingers, sx)

	# Шерсть: лохматый край вокруг тела.
	if g.get("fur", false):
		var fur := _fur(body, w * 0.07)
		_outlined(ci, fur, col.darkened(0.18), ow)

	# Туловище: контур, градиент, тень снизу, блики.
	_fill_outline(ci, body, ow)
	var light := col.lightened(0.22)
	var dark := col.darkened(0.18)
	if is_super:
		light = SUPER_A.lightened(0.1)
		dark = SUPER_B
	ci.draw_polygon(body, _vgrad(body, top_y, base.y, light, dark))
	var lit := _shift(body, Vector2(w * 0.03, -h * 0.09))
	for rim in Geometry2D.clip_polygons(body, lit):
		ci.draw_colored_polygon(rim, dark.darkened(0.25))
	_highlight(ci, body, base + Vector2(-w * 0.2, -h * 0.78), w)

	# Хохолок.
	if g.get("hair", false):
		_hair(ci, Vector2(base.x, top_y), w,
			g.get("hair_color", col.darkened(0.45)), ow, shape)

	# Лицо.
	var face_y := base.y - h * (0.42 if shape == Shape.TRIANGLE else 0.55)
	_face(ci, Vector2(base.x, face_y), w, g.get("eyes", 1), g.get("mood", 1.0), t)

	if is_super:
		_sparkles(ci, base + Vector2(0, -h * 0.5), w, t)


# --- Части тела ----------------------------------------------------------------------

static func _body(shape: int, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		Shape.TRIANGLE:
			pts = PackedVector2Array([Vector2(0, -h), Vector2(w * 0.56, 0), Vector2(-w * 0.56, 0)])
			return _rounded(pts, w * 0.16)
		Shape.SQUARE:
			pts = _rect(Vector2(-w * 0.5, -h), Vector2(w, h))
			return _rounded(pts, w * 0.2)
		_:
			for i in 48:
				var a := TAU * i / 48.0
				# Чуть шире внизу — устойчивый «колобок».
				var k := 1.0 + 0.06 * sin(a)
				pts.append(Vector2(cos(a) * w * 0.5 * k, -h * 0.5 + sin(a) * h * 0.5))
			return pts


## Полуширина тела на высоте frac (0 — низ, 1 — верх).
static func _half_width_at(shape: int, w: float, frac: float) -> float:
	match shape:
		Shape.TRIANGLE:
			return w * 0.5 * (1.0 - frac)
		Shape.SQUARE:
			return w * 0.5
		_:
			return w * 0.5 * sqrt(maxf(0.0, 1.0 - pow(frac * 2.0 - 1.0, 2.0)))


static func _arm(ci: CanvasItem, from: Vector2, to: Vector2, w: float, col: Color, ow: float, fingers: int, sx: float) -> void:
	var r := w * 0.065
	var dir := (to - from).normalized()
	var n := Vector2(-dir.y, dir.x) * r
	var arm := PackedVector2Array([from + n, to + n, to - n, from - n])
	_outlined(ci, _rounded(arm, r * 0.9), col.darkened(0.12), ow)
	# Ладонь и пальцы — общим контуром.
	var hr := w * 0.1
	var tips: Array[Vector2] = []
	var spread := clampf(0.42 * fingers, 0.5, 2.6)
	for i in fingers:
		var a := (0.0 if fingers == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (fingers - 1)))
		var base_a := atan2(dir.y, dir.x)
		tips.append(to + Vector2.from_angle(base_a + a) * hr * 1.05)
	for p in tips:
		ci.draw_circle(p, w * 0.042 + ow, OUTLINE)
	ci.draw_circle(to, hr + ow, OUTLINE)
	for p in tips:
		ci.draw_circle(p, w * 0.042, col.lightened(0.05))
	ci.draw_circle(to, hr, col.lightened(0.05))
	ci.draw_circle(to + Vector2(-hr * 0.3, -hr * 0.35), hr * 0.35, Color(1, 1, 1, 0.3))


static func _face(ci: CanvasItem, c: Vector2, w: float, eyes: int, mood: float, t: float) -> void:
	var sizes: Array[float] = [0.0, 0.2, 0.15, 0.12]
	var er: float = w * sizes[clampi(eyes, 0, 3)]
	var spots: Array[Vector2] = []
	match eyes:
		1:
			spots = [c]
		2:
			spots = [c + Vector2(-w * 0.17, 0), c + Vector2(w * 0.17, 0)]
		3:
			spots = [c + Vector2(-w * 0.2, w * 0.03), c + Vector2(w * 0.2, w * 0.03), c + Vector2(0, -w * 0.15)]
	# Моргание раз в несколько секунд.
	var blink := fmod(t, 3.7) < 0.12
	var look := Vector2(sin(t * 0.7) * 0.25, 0.1)
	for p in spots:
		ci.draw_circle(p, er + w * 0.04, OUTLINE)
		if blink:
			ci.draw_line(p + Vector2(-er * 0.8, 0), p + Vector2(er * 0.8, 0), Color.WHITE, w * 0.03)
			continue
		_ellipse(ci, p, Vector2(er, er * 1.08), Color.WHITE)
		ci.draw_circle(p + look * er * 0.45, er * 0.58, Color(0.16, 0.12, 0.2))
		ci.draw_circle(p + look * er * 0.45 + Vector2(-er * 0.2, -er * 0.25), er * 0.2, Color.WHITE)
		ci.draw_circle(p + look * er * 0.45 + Vector2(er * 0.18, er * 0.2), er * 0.08, Color(1, 1, 1, 0.8))
	# Брови.
	if eyes > 0:
		var brow_y := -er * 1.45 - w * 0.03
		var tilt := -mood * w * 0.035
		for p in spots:
			if eyes == 3 and p.y < c.y:
				continue
			var bw := er * 0.9
			ci.draw_line(p + Vector2(-bw, brow_y + tilt), p + Vector2(bw, brow_y - tilt), OUTLINE, w * 0.045, true)
	# Рот: открытая улыбка с языком и зубом.
	var my := c.y + (er if eyes > 0 else 0.0) + w * (0.12 if eyes != 3 else 0.13)
	var mw := w * (0.2 if eyes > 0 else 0.26)
	var mouth := PackedVector2Array()
	var smile := clampf(mood, -1.0, 1.0)
	for i in 17:
		var a := PI * i / 16.0
		mouth.append(Vector2(c.x - cos(a) * mw, my + sin(a) * mw * 0.75 * maxf(0.25, smile)))
	if smile < 0.0:
		mouth = _shift(_flip_y(mouth, my), Vector2(0, mw * 0.4))
	ci.draw_colored_polygon(Geometry2D.offset_polygon(mouth, w * 0.035, Geometry2D.JOIN_ROUND)[0], OUTLINE)
	ci.draw_colored_polygon(mouth, Color(0.45, 0.07, 0.14))
	var tongue := Geometry2D.intersect_polygons(mouth, _circle(Vector2(c.x + mw * 0.15, my + mw * 0.75), mw * 0.5, 20))
	for p in tongue:
		ci.draw_colored_polygon(p, Color(0.95, 0.42, 0.5))
	if smile > 0.0:
		var tooth := _rect(Vector2(c.x - mw * 0.45, my - w * 0.005), Vector2(mw * 0.36, mw * 0.24))
		ci.draw_colored_polygon(tooth, Color.WHITE)
	# Румянец.
	for sx in [-1.0, 1.0]:
		_ellipse(ci, Vector2(c.x + sx * w * 0.3, my - w * 0.02), Vector2(w * 0.07, w * 0.04), Color(1.0, 0.45, 0.5, 0.35))


static func _hair(ci: CanvasItem, top: Vector2, w: float, col: Color, ow: float, shape: int) -> void:
	# Пучок прядей, загнутых в стороны; корни — внутри тела.
	var spread := 0.09 if shape == Shape.TRIANGLE else 0.16
	var root_y := top.y + w * (0.1 if shape == Shape.TRIANGLE else 0.08)
	var polys: Array[PackedVector2Array] = []
	for i in 5:
		var k := (i - 2) / 2.0 # -1..1
		var bx := top.x + k * w * spread
		var tip := Vector2(top.x + k * w * (spread + 0.12), top.y - w * (0.22 - absf(k) * 0.07))
		var mid := Vector2(bx + k * w * 0.02, top.y - w * 0.08)
		var hw := w * 0.055
		polys.append(PackedVector2Array([Vector2(bx - hw, root_y), mid + Vector2(-hw * 0.7, 0), tip,
			mid + Vector2(hw * 0.7, 0), Vector2(bx + hw, root_y)]))
	for p in polys:
		ci.draw_colored_polygon(Geometry2D.offset_polygon(p, ow, Geometry2D.JOIN_ROUND)[0], OUTLINE)
	for p in polys:
		ci.draw_polygon(p, _vgrad(p, top.y - w * 0.22, root_y, col.lightened(0.3), col))


## Лохматый край: зубцы по контуру тела.
static func _fur(body: PackedVector2Array, len: float) -> PackedVector2Array:
	var big: PackedVector2Array = Geometry2D.offset_polygon(body, len * 0.5, Geometry2D.JOIN_ROUND)[0]
	var out := PackedVector2Array()
	var center := Vector2.ZERO
	for p in big:
		center += p
	center /= big.size()
	var per := 0.0
	for i in big.size():
		per += big[i].distance_to(big[(i + 1) % big.size()])
	var n := int(per / (len * 1.4))
	for i in n:
		var p := _along(big, per * i / n)
		var out_dir := (p - center).normalized()
		out.append(p + out_dir * (len if i % 2 == 0 else -len * 0.2))
	return out


static func _along(poly: PackedVector2Array, d: float) -> Vector2:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / maxf(l, 0.001))
		d -= l
	return poly[0]


static func _aura(ci: CanvasItem, c: Vector2, w: float, t: float) -> void:
	var pulse := 1.0 + sin(t * 3.0) * 0.05
	for i in 6:
		var k := 1.0 - i / 6.0
		ci.draw_circle(c, w * (0.95 - i * 0.08) * pulse, Color(SUPER_A, 0.07 + 0.03 * (1.0 - k)))
	# Лучи.
	for i in 12:
		var a := TAU * i / 12.0 + t * 0.3
		var p1 := c + Vector2.from_angle(a) * w * 0.45
		var p2 := c + Vector2.from_angle(a) * w * 1.05
		var side := Vector2.from_angle(a + PI * 0.5) * w * 0.05
		ci.draw_colored_polygon(PackedVector2Array([p1 - side, p2, p1 + side]), Color(1.0, 0.95, 0.6, 0.18))


static func _sparkles(ci: CanvasItem, c: Vector2, w: float, t: float) -> void:
	var spots := [Vector2(-0.62, -0.5), Vector2(0.66, -0.35), Vector2(0.5, 0.42), Vector2(-0.55, 0.3), Vector2(0.05, -0.9)]
	for i in spots.size():
		var s := (0.6 + 0.4 * sin(t * 4.0 + i * 1.7)) * w * 0.07
		_star(ci, c + spots[i] * w, s, Color(1.0, 0.97, 0.75))


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI * 0.5
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.3))
	ci.draw_colored_polygon(Geometry2D.offset_polygon(pts, r * 0.18, Geometry2D.JOIN_ROUND)[0], OUTLINE)
	ci.draw_colored_polygon(pts, col)


static func _highlight(ci: CanvasItem, body: PackedVector2Array, c: Vector2, w: float) -> void:
	var blob := _ellipse_poly(c, Vector2(w * 0.13, w * 0.08), -0.5)
	for p in Geometry2D.intersect_polygons(body, blob):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.5))
	ci.draw_circle(c + Vector2(w * 0.16, -w * 0.04), w * 0.03, Color(1, 1, 1, 0.55))


# --- Геометрия ------------------------------------------------------------------------

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


static func _fill_outline(ci: CanvasItem, poly: PackedVector2Array, ow: float) -> void:
	var o := Geometry2D.offset_polygon(poly, ow, Geometry2D.JOIN_ROUND)
	if not o.is_empty():
		ci.draw_colored_polygon(o[0], OUTLINE)


static func _outlined(ci: CanvasItem, poly: PackedVector2Array, col: Color, ow: float) -> void:
	_fill_outline(ci, poly, ow)
	ci.draw_colored_polygon(poly, col)


# --- Генетика цвета (для превью и будущего наследования) -----------------------------

## Насколько цвет близок к градиенту лого (0 — точно на нём).
static func super_distance(c: Color) -> float:
	var best := INF
	for i in 21:
		var g := SUPER_A.lerp(SUPER_B, i / 20.0)
		best = minf(best, Vector3(c.r - g.r, c.g - g.g, c.b - g.b).length())
	return best
