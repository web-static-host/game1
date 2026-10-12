class_name ResIcon
extends RefCounted
## Векторные значки ресурсов и кнопок. Рисуются на любом CanvasItem —
## и над стройками в мире, и в интерфейсе.

const COLORS := {
	"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.64, 0.64, 0.67), "clay": Color(0.74, 0.44, 0.3),
	"food": Color(0.88, 0.22, 0.28), "coal": Color(0.2, 0.19, 0.18), "iron": Color(0.72, 0.36, 0.2),
	"copper": Color(0.28, 0.72, 0.6), "silver": Color(0.86, 0.89, 0.93), "gold": Color(0.97, 0.8, 0.24),
	"uranium": Color(0.55, 0.9, 0.32), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.93, 0.9, 0.92),
	"oil": Color(0.12, 0.1, 0.08), "limestone": Color(0.83, 0.8, 0.7),
	"soil": Color(0.42, 0.29, 0.18), "sand": Color(0.87, 0.77, 0.53), "gravel": Color(0.58, 0.55, 0.5),
}


static func color(key: String) -> Color:
	return COLORS.get(key, Color(0.6, 0.6, 0.6))


## Значок ресурса key с центром c и радиусом r.
static func draw(ci: CanvasItem, key: String, c: Vector2, r: float) -> void:
	var col := color(key)
	var dark := col.darkened(0.4)
	match key:
		"wood":
			# Бревно: торец и кора.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.95, -r * 0.45), Vector2(r * 1.5, r * 0.9)), col)
			ci.draw_circle(c + Vector2(r * 0.55, 0), r * 0.48, col.lightened(0.35))
			ci.draw_arc(c + Vector2(r * 0.55, 0), r * 0.25, 0, TAU, 12, dark, maxf(1.0, r * 0.1))
			ci.draw_line(c + Vector2(-r * 0.8, -r * 0.1), c + Vector2(r * 0.2, -r * 0.1), dark, maxf(1.0, r * 0.1))
		"stone", "limestone", "coal", "salt":
			var pts := PackedVector2Array([
				c + Vector2(-r * 0.9, r * 0.55), c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(-r * 0.15, -r * 0.75),
				c + Vector2(r * 0.6, -r * 0.5), c + Vector2(r * 0.95, r * 0.15), c + Vector2(r * 0.6, r * 0.6)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.15, -r * 0.75), c + Vector2(r * 0.6, -r * 0.5), c + Vector2(r * 0.1, -r * 0.1),
				c + Vector2(-r * 0.5, -r * 0.2)]), col.lightened(0.25))
		"food":
			ci.draw_circle(c + Vector2(-r * 0.35, r * 0.2), r * 0.5, col)
			ci.draw_circle(c + Vector2(r * 0.4, r * 0.3), r * 0.45, col.darkened(0.1))
			ci.draw_circle(c + Vector2(-r * 0.5, 0.0), r * 0.15, col.lightened(0.5))
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.2), c + Vector2(r * 0.7, -r * 0.9), c + Vector2(r * 0.15, -r * 0.85)]),
				Color(0.35, 0.65, 0.3))
		"clay":
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
		"close":
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, r * 0.5), col, w)
			ci.draw_line(c + Vector2(r * 0.5, -r * 0.5), c + Vector2(-r * 0.5, r * 0.5), col, w)
		"people":
			ci.draw_circle(c + Vector2(0, -r * 0.45), r * 0.32, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.6, r * 0.8), c + Vector2(-r * 0.45, 0), c + Vector2(r * 0.45, 0), c + Vector2(r * 0.6, r * 0.8)]), col)
		"warning":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.85), c + Vector2(r * 0.9, r * 0.75), c + Vector2(-r * 0.9, r * 0.75)]), col)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), Color(0.1, 0.08, 0.05), w)
			ci.draw_circle(c + Vector2(0, r * 0.5), w * 0.6, Color(0.1, 0.08, 0.05))
