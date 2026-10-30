class_name ResIcon
extends RefCounted
## Векторные значки ресурсов и кнопок. Рисуются на любом CanvasItem —
## и над стройками в мире, и в интерфейсе.

const COLORS := {
	"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.64, 0.64, 0.67), "clay": Color(0.74, 0.44, 0.3),
	"food": Color(0.9, 0.8, 0.62), "fish": Color(0.55, 0.72, 0.85), "meal": Color(0.85, 0.55, 0.25), "berries": Color(0.88, 0.22, 0.28), "coal": Color(0.2, 0.19, 0.18), "iron": Color(0.72, 0.36, 0.2),
	"copper": Color(0.28, 0.72, 0.6), "silver": Color(0.86, 0.89, 0.93), "gold": Color(0.97, 0.8, 0.24),
	"uranium": Color(0.55, 0.9, 0.32), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.93, 0.9, 0.92),
	"oil": Color(0.12, 0.1, 0.08), "limestone": Color(0.83, 0.8, 0.7),
	"brick": Color(0.72, 0.3, 0.22), "methane": Color(0.55, 0.8, 0.3),
	"diesel": Color(0.95, 0.65, 0.15),
	"iron_ore": Color(0.55, 0.3, 0.2), "copper_ore": Color(0.22, 0.55, 0.47), "silver_ore": Color(0.66, 0.68, 0.72),
	"gold_ore": Color(0.75, 0.62, 0.22), "uranium_ore": Color(0.42, 0.68, 0.26), "amethyst": Color(0.64, 0.3, 1.0),
	"soil": Color(0.42, 0.29, 0.18), "sand": Color(0.87, 0.77, 0.53), "gravel": Color(0.58, 0.55, 0.5),
}


static func color(key: String) -> Color:
	return COLORS.get(key, Color(0.6, 0.6, 0.6))


## Картинка значка (assets/icons/<key>.png, нарезка из art_src/icons) или null.
static var _tex := {}
static func texture(key: String) -> Texture2D:
	if not _tex.has(key):
		var path := "res://assets/icons/%s.png" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


## Значок ресурса key с центром c и радиусом r: картинка, а если её нет — рисунок кодом.
## ci — узел (CanvasItem) или сборщик сеток (MeshBatch): нужны только его draw_*.
static func draw(ci: Object, key: String, c: Vector2, r: float) -> void:
	var t := texture(key)
	if t != null:
		var h := Vector2(r, r) * 1.12
		ci.draw_texture_rect(t, Rect2(c - h, h * 2.0), false)
		return
	var col := color(key)
	var dark := col.darkened(0.4)
	match key:
		"wood":
			# Бревно: торец и кора.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.95, -r * 0.45), Vector2(r * 1.5, r * 0.9)), col)
			ci.draw_circle(c + Vector2(r * 0.55, 0), r * 0.48, col.lightened(0.35))
			ci.draw_arc(c + Vector2(r * 0.55, 0), r * 0.25, 0, TAU, 12, dark, maxf(1.0, r * 0.1))
			ci.draw_line(c + Vector2(-r * 0.8, -r * 0.1), c + Vector2(r * 0.2, -r * 0.1), dark, maxf(1.0, r * 0.1))
		"stone", "limestone", "coal", "salt", "iron_ore", "copper_ore", "silver_ore", "gold_ore", "uranium_ore", "amethyst":
			var pts := PackedVector2Array([
				c + Vector2(-r * 0.9, r * 0.55), c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(-r * 0.15, -r * 0.75),
				c + Vector2(r * 0.6, -r * 0.5), c + Vector2(r * 0.95, r * 0.15), c + Vector2(r * 0.6, r * 0.6)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.15, -r * 0.75), c + Vector2(r * 0.6, -r * 0.5), c + Vector2(r * 0.1, -r * 0.1),
				c + Vector2(-r * 0.5, -r * 0.2)]), col.lightened(0.25))
		"food":
			# Гриб: шляпка и ножка.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.1), Vector2(r * 0.4, r * 0.9)), Color(0.95, 0.92, 0.84))
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.9, r * 0.05), c + Vector2(-r * 0.7, -r * 0.5), c + Vector2(0, -r * 0.8),
				c + Vector2(r * 0.7, -r * 0.5), c + Vector2(r * 0.9, r * 0.05)]), Color(0.86, 0.36, 0.26))
			ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.4), r * 0.12, Color(1, 0.95, 0.88))
			ci.draw_circle(c + Vector2(r * 0.35, -r * 0.3), r * 0.1, Color(1, 0.95, 0.88))
		"meal":
			# Бургер: булка, котлета, салат, булка.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.9, -r * 0.15), c + Vector2(-r * 0.75, -r * 0.6), c + Vector2(0, -r * 0.85),
				c + Vector2(r * 0.75, -r * 0.6), c + Vector2(r * 0.9, -r * 0.15)]), Color(0.93, 0.66, 0.3))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.95, -r * 0.15), Vector2(r * 1.9, r * 0.22)), Color(0.45, 0.75, 0.3))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.9, r * 0.07), Vector2(r * 1.8, r * 0.3)), Color(0.45, 0.25, 0.15))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.85, r * 0.37), Vector2(r * 1.7, r * 0.33)), Color(0.9, 0.62, 0.28))
			for dx in [-0.4, 0.0, 0.4]:
				ci.draw_circle(c + Vector2(r * dx, -r * 0.55), r * 0.06, Color(1, 0.95, 0.8))
		"fish":
			# Рыба.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.9, 0), c + Vector2(-r * 0.2, -r * 0.5), c + Vector2(r * 0.45, -r * 0.3),
				c + Vector2(r * 0.45, r * 0.3), c + Vector2(-r * 0.2, r * 0.5)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.35, 0), c + Vector2(r * 0.95, -r * 0.45), c + Vector2(r * 0.95, r * 0.45)]), col.darkened(0.2))
			ci.draw_circle(c + Vector2(-r * 0.5, -r * 0.1), r * 0.1, Color(0.1, 0.1, 0.12))
		"berries":
			ci.draw_circle(c + Vector2(-r * 0.35, r * 0.2), r * 0.5, col)
			ci.draw_circle(c + Vector2(r * 0.4, r * 0.3), r * 0.45, col.darkened(0.1))
			ci.draw_circle(c + Vector2(-r * 0.5, 0.0), r * 0.15, col.lightened(0.5))
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.2), c + Vector2(r * 0.7, -r * 0.9), c + Vector2(r * 0.15, -r * 0.85)]),
				Color(0.35, 0.65, 0.3))
		"methane":
			# Баллон с газом.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.55), Vector2(r * 0.9, r * 1.45)), col)
			ci.draw_circle(c + Vector2(0, -r * 0.55), r * 0.45, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.15, -r * 1.05), Vector2(r * 0.3, r * 0.25)), col.darkened(0.4))
		"diesel":
			# Канистра.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.55), Vector2(r * 1.2, r * 1.4)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.55), Vector2(r * 1.2, r * 1.4)), dark, false, maxf(1.5, r * 0.12))
			ci.draw_rect(Rect2(c + Vector2(r * 0.05, -r * 0.85), Vector2(r * 0.35, r * 0.3)), dark)
			ci.draw_line(c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.4, r * 0.6), dark, maxf(1.5, r * 0.12))
		"clay", "brick":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.9, -r * 0.45), Vector2(r * 1.8, r * 0.9)), col)
			ci.draw_line(c + Vector2(-r * 0.9, 0), c + Vector2(r * 0.9, 0), dark, maxf(1.0, r * 0.1))
			ci.draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, 0), dark, maxf(1.0, r * 0.1))
		"soil", "sand", "gravel":
			var mound := PackedVector2Array()
			for i in 9:
				var a := PI + i * PI / 8.0
				mound.append(c + Vector2(cos(a) * r, r * 0.5 + sin(a) * r * 0.9))
			ci.draw_colored_polygon(mound, col)
		_:
			# Руды и прочее — огранённый камень.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.9), c + Vector2(r * 0.8, -r * 0.2), c + Vector2(0, r * 0.9),
				c + Vector2(-r * 0.8, -r * 0.2)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.9), c + Vector2(r * 0.8, -r * 0.2), c + Vector2(0, -r * 0.1)]), col.lightened(0.35))


## Значки кнопок: рисуются линиями цвета col в квадрате с центром c и радиусом r.
static func draw_glyph(ci: CanvasItem, name: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(2.0, r * 0.16)
	match name:
		"look":
			ci.draw_arc(c + Vector2(-r * 0.15, -r * 0.15), r * 0.5, 0, TAU, 24, col, w)
			ci.draw_line(c + Vector2(r * 0.22, r * 0.22), c + Vector2(r * 0.75, r * 0.75), col, w * 1.4)
		"build":
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.7), c + Vector2(r * 0.25, -r * 0.15), col, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.05, -r * 0.65), c + Vector2(r * 0.55, -r * 0.05), c + Vector2(r * 0.8, -r * 0.3),
				c + Vector2(r * 0.2, -r * 0.9)]), col)
		"harvest":
			# Топор.
			ci.draw_line(c + Vector2(-r * 0.55, r * 0.75), c + Vector2(r * 0.35, -r * 0.6), col, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.1, -r * 0.35), c + Vector2(r * 0.35, -r * 0.85), c + Vector2(r * 0.85, -r * 0.45),
				c + Vector2(r * 0.55, -r * 0.05)]), col)
		"home":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.8, -r * 0.05), c + Vector2(0, -r * 0.8), c + Vector2(r * 0.8, -r * 0.05)]), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.05), Vector2(r * 1.1, r * 0.8)), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.15, r * 0.3), Vector2(r * 0.3, r * 0.45)), col)
		"menu":
			for k in 3:
				var y := (k - 1) * r * 0.5
				ci.draw_line(c + Vector2(-r * 0.7, y), c + Vector2(r * 0.7, y), col, w * 1.1)
		"speed":
			for k in 2:
				var x := (k - 0.5) * r * 0.75
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(x - r * 0.4, -r * 0.55), c + Vector2(x + r * 0.35, 0), c + Vector2(x - r * 0.4, r * 0.55)]), col)
		"tunnel":
			ci.draw_arc(c + Vector2(0, r * 0.2), r * 0.6, PI, TAU, 16, col, w)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.2), c + Vector2(-r * 0.6, r * 0.75), col, w)
			ci.draw_line(c + Vector2(r * 0.6, r * 0.2), c + Vector2(r * 0.6, r * 0.75), col, w)
			ci.draw_line(c + Vector2(-r * 0.9, r * 0.75), c + Vector2(r * 0.9, r * 0.75), col, w)
		"mine":
			# Кирка над рамкой выработки.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.85, r * 0.15), Vector2(r * 1.7, r * 0.65)), col, false, w)
			ci.draw_line(c + Vector2(-r * 0.35, r * 0.05), c + Vector2(r * 0.35, -r * 0.75), col, w)
			ci.draw_arc(c + Vector2(r * 0.05, -r * 0.35), r * 0.55, -PI * 0.95, -PI * 0.15, 12, col, w * 1.2)
		"room":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.6), Vector2(r * 1.6, r * 1.3)), col, false, w)
			ci.draw_circle(c + Vector2(0, -r * 0.3), r * 0.13, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.3), Vector2(r * 0.5, r * 0.4)), col)
		"bridge":
			ci.draw_line(c + Vector2(-r * 0.9, -r * 0.1), c + Vector2(r * 0.9, -r * 0.1), col, w * 1.3)
			for k in 3:
				var x := (k - 1) * r * 0.6
				ci.draw_line(c + Vector2(x, -r * 0.1), c + Vector2(x, r * 0.45), col, w)
			for k in 2:
				var y := r * (0.55 + k * 0.25)
				ci.draw_line(c + Vector2(-r * 0.8, y), c + Vector2(r * 0.8, y), Color(col, 0.6), w * 0.7)
		"flask":
			ci.draw_line(c + Vector2(-r * 0.25, -r * 0.8), c + Vector2(r * 0.25, -r * 0.8), col, w)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.2, -r * 0.75), c + Vector2(r * 0.2, -r * 0.75), c + Vector2(r * 0.2, -r * 0.2),
				c + Vector2(r * 0.75, r * 0.75), c + Vector2(-r * 0.75, r * 0.75), c + Vector2(-r * 0.2, -r * 0.2)]), col)
		"power":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.15, -r * 0.9), c + Vector2(-r * 0.55, r * 0.1), c + Vector2(-r * 0.05, r * 0.1),
				c + Vector2(-r * 0.2, r * 0.9), c + Vector2(r * 0.55, -r * 0.15), c + Vector2(r * 0.05, -r * 0.15)]), col)
		"close":
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, r * 0.5), col, w)
			ci.draw_line(c + Vector2(r * 0.5, -r * 0.5), c + Vector2(-r * 0.5, r * 0.5), col, w)
		"people":
			ci.draw_circle(c + Vector2(0, -r * 0.45), r * 0.32, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.6, r * 0.8), c + Vector2(-r * 0.45, 0), c + Vector2(r * 0.45, 0), c + Vector2(r * 0.6, r * 0.8)]), col)
		"frost":
			# Снежинка: три оси с «веточками».
			for k in 3:
				var dir := Vector2.from_angle(PI / 2.0 + k * PI / 3.0)
				ci.draw_line(c - dir * r * 0.85, c + dir * r * 0.85, col, w)
				for s in [-1.0, 1.0]:
					var tip: Vector2 = c + dir * r * 0.55 * s
					ci.draw_line(tip, tip + (dir * s).rotated(0.8) * r * 0.3, col, w * 0.8)
					ci.draw_line(tip, tip + (dir * s).rotated(-0.8) * r * 0.3, col, w * 0.8)
		"planet":
			# Планета с кольцом.
			ci.draw_circle(c, r * 0.55, col)
			ci.draw_arc(c, r * 0.95, -0.35, PI - 0.35, 20, col, w)
			ci.draw_arc(c, r * 0.95, PI + 0.25, TAU - 0.55, 20, Color(col, 0.6), w * 0.8)
		"rocket":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.95), c + Vector2(r * 0.35, -r * 0.3),
				c + Vector2(r * 0.35, r * 0.55), c + Vector2(-r * 0.35, r * 0.55), c + Vector2(-r * 0.35, -r * 0.3)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.35, r * 0.15), c + Vector2(-r * 0.7, r * 0.8),
				c + Vector2(-r * 0.35, r * 0.55)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.35, r * 0.15), c + Vector2(r * 0.7, r * 0.8),
				c + Vector2(r * 0.35, r * 0.55)]), col)
		"drill":
			# Бур: корпус и винтовое сверло вниз.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.9), Vector2(r * 1.2, r * 0.7)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.2), c + Vector2(r * 0.4, -r * 0.2),
				c + Vector2(0, r * 0.95)]), col)
			for k in 3:
				var y := -r * 0.05 + k * r * 0.28
				ci.draw_line(c + Vector2(-r * 0.32 + k * r * 0.1, y), c + Vector2(r * 0.32 - k * r * 0.1, y + r * 0.12), Color(0.1, 0.1, 0.12), w * 0.7)
		"lift", "cargo_lift":
			# Шахта с кабиной и стрелками вверх-вниз; у грузового — ящик в кабине.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.9), Vector2(r * 1.5, r * 1.8)), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.15), Vector2(r * 0.9, r * 0.75)), col, name == "cargo_lift", w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.35), c + Vector2(0, -r * 0.7),
				c + Vector2(r * 0.3, -r * 0.35)]), col)
		"check", "check_off":
			# Квадрат галочки; включённая — с галкой.
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), col, false, w)
			if name == "check":
				ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.1, r * 0.4),
					c + Vector2(r * 0.55, -r * 0.45)]), col, w * 1.3)
		"repair":
			# Гаечный ключ: ручка по диагонали, на концах — головки с зевом.
			var d := Vector2(1, -1).normalized()
			ci.draw_line(c - d * r * 0.55, c + d * r * 0.45, col, w * 1.9)
			for s in [1.0, -1.0]:
				var head: Vector2 = c + d * r * 0.62 * s
				ci.draw_circle(head, r * 0.36, col)
				# Зев — вырез в головке, смотрит наружу.
				ci.draw_circle(head + d * r * 0.26 * s, r * 0.2, Color(0.08, 0.07, 0.06))
		"warning":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.85), c + Vector2(r * 0.9, r * 0.75), c + Vector2(-r * 0.9, r * 0.75)]), col)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), Color(0.1, 0.08, 0.05), w)
			ci.draw_circle(c + Vector2(0, r * 0.5), w * 0.6, Color(0.1, 0.08, 0.05))
