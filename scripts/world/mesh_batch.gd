class_name MeshBatch
extends RefCounted
## Собирает рисование (те же вызовы, что у CanvasItem: прямоугольники, многоугольники, круги,
## линии, куски текстур) в треугольники — по одной сетке на слой и текстуру. Кусок карты
## рисовался тысячами отдельных команд (сотни вызовов видеокарты на кусок каждый кадр); теперь —
## несколько готовых сеток, которые собираются только при изменении куска.
##
## Порядок: сначала слой (layer: вода −1, порода 0, деревья 1), внутри слоя — сначала
## текстура земли (fog), потом без текстуры, потом прочие текстуры (кромка травы); внутри
## группы — в порядке рисования.

var layer := 0
var fog: Texture2D
## Множитель цвета для группы с текстурой fog (цвета вершин хранятся в 8 битах и ярче 1 не
## бывают, а земля подкрашивается с усилением — его даём всей сетке).
var fog_modulate := Color(1, 1, 1, 1)
## Строгий порядок (слой построек: мебель-картинки перекрывают и перекрываются фигурами) —
## новая группа на каждую смену текстуры, без перестановок.
var strict := false
## Надписи — рисует движок: [имя метода CanvasItem, аргументы, номер группы, перед которой
## рисовать] (в строгом порядке — между сетками там же, где их рисовали; иначе — поверх всего).
var texts: Array = []
var _break := false
var _groups := {}
var _order: Array = []
const CIRCLE_SEGS := 16


## Нарисовать готовое на узле ci: сетки и надписи — в том порядке, в каком их рисовали.
func render(ci: CanvasItem, meshes: Array) -> void:
	var ti := 0
	for m in meshes:
		while ti < texts.size() and int(texts[ti][2]) <= int(m[3]):
			ci.callv(texts[ti][0], texts[ti][1])
			ti += 1
		ci.draw_mesh(m[0], m[1], Transform2D(), m[2])
	while ti < texts.size():
		ci.callv(texts[ti][0], texts[ti][1])
		ti += 1


func clear() -> void:
	_groups.clear()
	_order.clear()
	texts.clear()
	_break = false


func _group(tex: Texture2D) -> Array:
	if strict:
		if not _break and not _order.is_empty() and _order[-1][3] == tex:
			return _order[-1]
		_break = false
		var sg := [PackedVector2Array(), PackedColorArray(), PackedVector2Array(), tex, _order.size()]
		_order.append(sg)
		return sg
	var rank := 1 if tex == null else (0 if tex == fog else 2)
	var key := [layer, rank, tex]
	var g = _groups.get(key)
	if g == null:
		g = [PackedVector2Array(), PackedColorArray(), PackedVector2Array(), tex, layer * 10 + rank]
		_groups[key] = g
		_order.append(g)
	return g


func _tri(g: Array, a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var v: PackedVector2Array = g[0]
	var col: PackedColorArray = g[1]
	var uv: PackedVector2Array = g[2]
	v.append(a)
	v.append(b)
	v.append(c)
	col.append(ca)
	col.append(cb)
	col.append(cc)
	uv.append(ua)
	uv.append(ub)
	uv.append(uc)


func _quad(g: Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color,
		u0 := Vector2.ZERO, u1 := Vector2.ZERO, u2 := Vector2.ZERO, u3 := Vector2.ZERO) -> void:
	_tri(g, p0, p1, p2, col, col, col, u0, u1, u2)
	_tri(g, p0, p2, p3, col, col, col, u0, u2, u3)


func draw_rect(r: Rect2, color: Color, filled := true, width := -1.0) -> void:
	var g := _group(null)
	if filled:
		_quad(g, r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), color)
		return
	var w := maxf(1.0, width)
	var h := w * 0.5
	var a := r.position
	var b := r.end
	_quad(g, Vector2(a.x - h, a.y - h), Vector2(b.x + h, a.y - h), Vector2(b.x + h, a.y + h), Vector2(a.x - h, a.y + h), color)
	_quad(g, Vector2(a.x - h, b.y - h), Vector2(b.x + h, b.y - h), Vector2(b.x + h, b.y + h), Vector2(a.x - h, b.y + h), color)
	_quad(g, Vector2(a.x - h, a.y + h), Vector2(a.x + h, a.y + h), Vector2(a.x + h, b.y - h), Vector2(a.x - h, b.y - h), color)
	_quad(g, Vector2(b.x - h, a.y + h), Vector2(b.x + h, a.y + h), Vector2(b.x + h, b.y - h), Vector2(b.x - h, b.y - h), color)


func draw_texture_rect(tex: Texture2D, r: Rect2, _tile := false, modulate := Color.WHITE) -> void:
	if tex == null:
		return
	_quad(_group(tex), r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), modulate,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


func draw_dashed_line(from: Vector2, to: Vector2, color: Color, width := -1.0, dash := 2.0, _aligned := true, _antialiased := false) -> void:
	var len := from.distance_to(to)
	if len <= 0.0:
		return
	var d := (to - from) / len
	var t := 0.0
	while t < len:
		draw_line(from + d * t, from + d * minf(t + dash, len), color, width)
		t += dash * 2.0


func draw_string(font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font_size := 16, modulate := Color.WHITE) -> void:
	texts.append(["draw_string", [font, pos, text, alignment, width, font_size, modulate], _order.size()])
	_break = true


func draw_string_outline(font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font_size := 16, size := 1, modulate := Color.WHITE) -> void:
	texts.append(["draw_string_outline", [font, pos, text, alignment, width, font_size, size, modulate], _order.size()])
	_break = true


func draw_texture_rect_region(tex: Texture2D, r: Rect2, src: Rect2, modulate := Color.WHITE) -> void:
	var g := _group(tex)
	var sz := Vector2(tex.get_width(), tex.get_height())
	var u0 := src.position / sz
	var u1 := src.end / sz
	_quad(g, r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), modulate,
		u0, Vector2(u1.x, u0.y), u1, Vector2(u0.x, u1.y))


func draw_colored_polygon(points: PackedVector2Array, color: Color, uvs := PackedVector2Array(), texture: Texture2D = null) -> void:
	if points.size() < 3:
		return
	var g := _group(texture)
	var idx := _triangulate(points)
	var has_uv := uvs.size() == points.size()
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		if has_uv:
			_tri(g, points[a], points[b], points[c], color, color, color, uvs[a], uvs[b], uvs[c])
		else:
			_tri(g, points[a], points[b], points[c], color, color, color)


## Выпуклый многоугольник — веером, без разбиения движком (кристаллы, шестиугольники).
func draw_convex(points: PackedVector2Array, color: Color) -> void:
	var g := _group(null)
	for i in range(1, points.size() - 1):
		_tri(g, points[0], points[i], points[i + 1], color, color, color)


func draw_polygon(points: PackedVector2Array, colors: PackedColorArray) -> void:
	if points.size() < 3:
		return
	var g := _group(null)
	var idx := _triangulate(points)
	var one := colors.size() < points.size()
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		if one:
			_tri(g, points[a], points[b], points[c], colors[0], colors[0], colors[0])
		else:
			_tri(g, points[a], points[b], points[c], colors[a], colors[b], colors[c])


## Выпуклые (до четырёх вершин) — веером, сложные — разбиением движка.
static func _triangulate(points: PackedVector2Array) -> PackedInt32Array:
	if points.size() <= 4:
		var out := PackedInt32Array()
		for i in range(1, points.size() - 1):
			out.append(0)
			out.append(i)
			out.append(i + 1)
		return out
	var idx := Geometry2D.triangulate_polygon(points)
	if idx.is_empty():
		for i in range(1, points.size() - 1):
			idx.append(0)
			idx.append(i)
			idx.append(i + 1)
	return idx


func draw_circle(pos: Vector2, radius: float, color: Color) -> void:
	var g := _group(null)
	# Мелкие круги (блики, капли) — меньше сегментов: на глаз то же, треугольников вдвое-втрое меньше.
	var segs := 6 if radius < 2.5 else (10 if radius < 5.0 else (CIRCLE_SEGS if radius < 10.0 else 24))
	var prev := pos + Vector2(radius, 0)
	for i in range(1, segs + 1):
		var a := TAU * i / segs
		var p := pos + Vector2(cos(a), sin(a)) * radius
		_tri(g, pos, prev, p, color, color, color)
		prev = p


func draw_line(from: Vector2, to: Vector2, color: Color, width := -1.0, _antialiased := false) -> void:
	var d := to - from
	if d.length_squared() < 0.0001:
		return
	var n := d.orthogonal().normalized() * maxf(1.0, width) * 0.5
	_quad(_group(null), from - n, to - n, to + n, from + n, color)


func draw_polyline(points: PackedVector2Array, color: Color, width := -1.0, antialiased := false) -> void:
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], color, width, antialiased)


func draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width := -1.0, antialiased := false) -> void:
	var prev := center + Vector2(cos(start), sin(start)) * radius
	for i in range(1, point_count + 1):
		var a := lerpf(start, end, float(i) / point_count)
		var p := center + Vector2(cos(a), sin(a)) * radius
		draw_line(prev, p, color, width, antialiased)
		prev = p


## Готовые сетки по порядку рисования: [[сетка, текстура, множитель цвета, номер группы], ...]. Держите ссылку на результат,
## пока узел их рисует: освобождённая сетка пропадает с экрана.
func build() -> Array:
	var groups := _order.duplicate()
	if not strict:
		groups.sort_custom(func(a: Array, b: Array) -> bool: return int(a[4]) < int(b[4]))
	var out := []
	for g in groups:
		var v: PackedVector2Array = g[0]
		if v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = g[1]
		arrays[Mesh.ARRAY_TEX_UV] = g[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append([mesh, g[3], fog_modulate if g[3] == fog and fog != null else Color(1, 1, 1, 1), int(g[4])])
	return out
