class_name UiStyle
extends RefCounted
## Стиль интерфейса (окна, плитки-кнопки, плашки разделов): тёмно-синие окна со светлой каймой,
## кнопки — объёмные плитки с вертикальным градиентом, светлым кантом сверху и тёмным бортиком
## снизу. Картинки рисуются кодом один раз (9-патч: углы не тянутся, середина тянется вместе
## с градиентом) и кэшируются.

## Цвета.
const WINDOW_TOP := Color(0.12, 0.16, 0.27)
const WINDOW_BOTTOM := Color(0.07, 0.1, 0.18)
const WINDOW_EDGE := Color(0.3, 0.38, 0.56)
const TILE := Color(0.17, 0.23, 0.38)
const BLUE := Color(0.2, 0.45, 0.88)
const ORANGE := Color(0.96, 0.6, 0.16)
const INSET := Color(0.06, 0.08, 0.14, 0.85)

static var _cache := {}


## Окно (карточка, меню, окно стройки).
static func window(radius := 22, pad := 14.0, alpha := 0.96) -> StyleBoxTexture:
	return _cached(["win", radius, alpha], func() -> Image:
		return _paint(radius, Color(WINDOW_TOP, alpha), Color(WINDOW_BOTTOM, alpha), Color(WINDOW_EDGE, 0.9), 2, 0.07, 0, Color()), radius, pad)


## Плитка-кнопка цвета col. pressed — вдавлена: темнее, бортик снизу тоньше.
static func tile(col: Color, pressed := false, radius := 14, pad := 10.0) -> StyleBoxTexture:
	var top := col.lightened(0.12)
	var bottom := col.darkened(0.28)
	var lip := 5
	if pressed:
		top = col.darkened(0.02)
		bottom = col.darkened(0.26)
		lip = 2
	var edge := Color(col.lightened(0.45), 0.75 * col.a)
	var sb := _cached(["tile", col.to_html(), pressed, radius], func() -> Image:
		return _paint(radius, top, bottom, edge, 2, 0.16 if not pressed else 0.05, lip, col.darkened(0.55)), radius, pad)
	sb.content_margin_bottom = pad + (lip - 1)
	return sb


## Плашка-заголовок раздела (синяя, оранжевая…).
static func banner(col: Color, radius := 16, pad := 12.0) -> StyleBoxTexture:
	return _cached(["banner", col.to_html(), radius], func() -> Image:
		return _paint(radius, col.lightened(0.18), col.darkened(0.22), Color(col.lightened(0.55), 0.9), 2, 0.22, 3, col.darkened(0.5)), radius, pad)


## Тёмная подложка раздела с каймой цвета раздела.
static func section(col: Color, radius := 16, pad := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = INSET
	sb.border_color = Color(col, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb


## Плоская подложка (строки, чипы, полоски) — без градиента, с тонкой каймой.
static func flat(col: Color, radius := 12, pad := 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	if col.a > 0.0:
		sb.border_color = Color(1, 1, 1, minf(0.12, col.a * 1.5)) if col.a < 0.5 else Color(col.lightened(0.3), 0.6)
		sb.set_border_width_all(1)
	return sb


static func _cached(key: Array, paint: Callable, radius: int, pad: float) -> StyleBoxTexture:
	var k := str(key)
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(paint.call())
	var sb := StyleBoxTexture.new()
	sb.texture = _cache[k]
	var m := float(radius + 4)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.set_content_margin_all(pad)
	return sb


## Скруглённый прямоугольник: вертикальный градиент top→bottom, кайма edge толщиной bw,
## светлая полоска сверху внутри (shine — её яркость), снизу бортик lip пикселей цвета lip_col.
static func _paint(radius: int, top: Color, bottom: Color, edge: Color, bw: int, shine: float, lip: int, lip_col: Color) -> Image:
	var h := radius * 2 + 40
	var w := radius * 2 + 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := float(radius)
	for y in h:
		var t := float(y) / (h - 1)
		var base := top.lerp(bottom, t)
		for x in w:
			var d := _sdf(x + 0.5, y + 0.5, w, h, r)
			if d > 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var cov := clampf(0.5 - d, 0.0, 1.0)
			var c := base
			# Бортик снизу: та же форма, приподнятая на lip — что ниже неё, то бортик.
			if lip > 0 and _sdf(x + 0.5, y + 0.5 + lip, w, h, r) > 0.0:
				c = lip_col
			elif shine > 0.0 and y < radius * 0.9 and d < -bw - 1:
				# Блик сверху — мягко гаснет вниз.
				c = c.lerp(Color.WHITE, shine * (1.0 - float(y) / (radius * 0.9)))
			if d > -bw:
				var k := clampf(d + bw, 0.0, 1.0)
				c = c.lerp(Color(edge, 1.0), edge.a * k)
			c.a *= cov
			img.set_pixel(x, y, c)
	return img


static func _sdf(px: float, py: float, w: int, h: int, r: float) -> float:
	var qx := absf(px - w * 0.5) - (w * 0.5 - r)
	var qy := absf(py - h * 0.5) - (h * 0.5 - r)
	return Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
