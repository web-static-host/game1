extends SceneTree
## Лист концептов гавриков: 4 вида, у каждого самец и самка.
##   xvfb-run godot --path . -s res://tests/concepts.gd -- <файл.png>

var _frame := 0
var _out := "user://concepts.png"


class Sheet extends Node2D:
	const NAMES := ["Кротоны", "Камешки", "Грибли", "Саламандры"]
	const NOTES := [
		"землекопы, бархатная шерсть,\nлапы-лопаты, плохо видят на свету",
		"живые камни с кристаллами,\nкрепкие и медленные, цвет = порода",
		"грибной народец, любят сырость\nи темноту, светятся в шахтах",
		"огнеупорные ящерки,\nне боятся жары у магмы",
	]

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1600, 900), Color(0.12, 0.13, 0.17))
		var font := ThemeDB.fallback_font
		for i in 4:
			var cx := 200.0 + i * 400.0
			draw_rect(Rect2(cx - 185, 30, 370, 840), Color(0.17, 0.19, 0.25))
			draw_string(font, Vector2(cx - 180, 90), NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, 360, 40, Color(1, 0.85, 0.5))
			var lines: PackedStringArray = NOTES[i].split("\n")
			for k in lines.size():
				draw_string(font, Vector2(cx - 180, 770 + k * 30), lines[k], HORIZONTAL_ALIGNMENT_CENTER, 360, 18, Color(0.85, 0.88, 0.95))
			for sex in 2:
				var foot := Vector2(cx - 85 + sex * 170, 600)
				draw_set_transform(foot, 0.0, Vector2(3.4, 3.4))
				match i:
					0: _mole(sex)
					1: _rock(sex)
					2: _shroom(sex)
					3: _sala(sex)
				draw_set_transform(Vector2.ZERO)
				draw_string(font, foot + Vector2(-60, 60), "самка" if sex else "самец", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(0.7, 0.72, 0.8))

	func _eye(p: Vector2, r: float) -> void:
		draw_circle(p, r, Color.WHITE)
		draw_circle(p + Vector2(r * 0.25, 0), r * 0.55, Color(0.1, 0.08, 0.1))
		draw_circle(p + Vector2(r * 0.4, -r * 0.3), r * 0.2, Color.WHITE)

	func _bow(p: Vector2, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(-6, -4), p + Vector2(-6, 4)]), col)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(6, -4), p + Vector2(6, 4)]), col)
		draw_circle(p, 1.8, col.darkened(0.2))

	# Кротон: пухлое тело, большие розовые лапы, нос-пятачок, каска.
	func _mole(sex: int) -> void:
		var fur := Color(0.36, 0.3, 0.36) if sex == 0 else Color(0.45, 0.36, 0.4)
		var paw := Color(0.95, 0.66, 0.7)
		draw_circle(Vector2(-6, -2), 4, paw)
		draw_circle(Vector2(6, -2), 4, paw)
		draw_colored_polygon(_ellipse(Vector2(0, -18), 15, 18), fur)
		draw_colored_polygon(_ellipse(Vector2(0, -14), 9, 11), fur.lightened(0.25))
		draw_colored_polygon(_ellipse(Vector2(15, -18), 6, 4), paw)
		draw_colored_polygon(_ellipse(Vector2(-15, -18), 6, 4), paw)
		for k in 3:
			draw_line(Vector2(19, -20 + k * 2), Vector2(23, -21 + k * 2.5), Color(0.95, 0.9, 0.85), 1.0)
		draw_circle(Vector2(0, -30), 3.5, paw.darkened(0.1))
		draw_circle(Vector2(-5, -34), 1.4, Color(0.05, 0.05, 0.05))
		draw_circle(Vector2(5, -34), 1.4, Color(0.05, 0.05, 0.05))
		draw_arc(Vector2(0, -30), 13, PI + 0.25, TAU - 0.25, 16, Color(1, 0.78, 0.15), 5.0)
		draw_circle(Vector2(0, -41), 2.5, Color(1, 0.95, 0.6))
		if sex == 1:
			_bow(Vector2(11, -38), Color(0.9, 0.3, 0.45))

	# Камешек: угловатое каменное тело, кристаллы, светящиеся глаза.
	func _rock(sex: int) -> void:
		var stone := Color(0.55, 0.52, 0.5) if sex == 0 else Color(0.66, 0.56, 0.54)
		var cry := Color(0.45, 0.85, 0.95) if sex == 0 else Color(0.85, 0.5, 0.9)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(-4, -8), Vector2(-1, 0)]), stone.darkened(0.2))
		draw_colored_polygon(PackedVector2Array([Vector2(1, 0), Vector2(4, -8), Vector2(7, 0)]), stone.darkened(0.2))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-14, -8), Vector2(-16, -26), Vector2(-9, -42), Vector2(6, -45),
			Vector2(15, -32), Vector2(14, -10), Vector2(6, -5), Vector2(-6, -5)]), stone)
		draw_colored_polygon(PackedVector2Array([Vector2(-9, -42), Vector2(6, -45), Vector2(0, -36)]), stone.lightened(0.15))
		for k in 3:
			var b := Vector2(-6 + k * 7, -42 - (k % 2) * 3)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-3, 2), b + Vector2(0, -9 - k * 2), b + Vector2(3, 2)]), cry)
		draw_circle(Vector2(-4, -27), 3, cry.lightened(0.4))
		draw_circle(Vector2(6, -27), 3, cry.lightened(0.4))
		draw_line(Vector2(-3, -18), Vector2(5, -18), stone.darkened(0.4), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(-18, -26), Vector2(-22, -14), Vector2(-14, -16)]), stone.darkened(0.1))
		draw_colored_polygon(PackedVector2Array([Vector2(16, -26), Vector2(21, -14), Vector2(13, -16)]), stone.darkened(0.1))

	# Грибль: шляпка, тонкая ножка-тело, светящиеся точки.
	func _shroom(sex: int) -> void:
		var cap := Color(0.78, 0.25, 0.22) if sex == 0 else Color(0.55, 0.35, 0.75)
		var stem := Color(0.95, 0.9, 0.8)
		draw_line(Vector2(-3, 0), Vector2(-3, -10), stem.darkened(0.2), 3.0)
		draw_line(Vector2(3, 0), Vector2(3, -10), stem.darkened(0.2), 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, -9), Vector2(7, -9), Vector2(5, -30), Vector2(-5, -30)]), stem)
		draw_line(Vector2(-6, -22), Vector2(-12, -14), stem, 2.5)
		draw_line(Vector2(6, -22), Vector2(12, -14), stem, 2.5)
		var pts := PackedVector2Array()
		for k in 17:
			var a := PI + k * PI / 16.0
			pts.append(Vector2(cos(a) * 20, -30 + sin(a) * 16))
		draw_colored_polygon(pts, cap)
		for p in [Vector2(-10, -38), Vector2(3, -42), Vector2(11, -34), Vector2(-3, -33)]:
			draw_circle(p, 2.6, Color(1, 1, 0.85))
		_eye(Vector2(-2.5, -24), 2.2)
		_eye(Vector2(3.5, -24), 2.2)
		if sex == 1:
			draw_circle(Vector2(-4, -19), 1.4, Color(1, 0.6, 0.65, 0.8))
			draw_circle(Vector2(5, -19), 1.4, Color(1, 0.6, 0.65, 0.8))

	# Саламандра: прямоходящая ящерка с хвостом и гребнем.
	func _sala(sex: int) -> void:
		var skin := Color(0.95, 0.45, 0.2) if sex == 0 else Color(0.95, 0.3, 0.4)
		var belly := Color(1.0, 0.85, 0.5)
		draw_polyline(PackedVector2Array([Vector2(-6, -8), Vector2(-14, -4), Vector2(-20, -8), Vector2(-22, -14)]), skin, 4.0)
		draw_line(Vector2(-3, 0), Vector2(-3, -10), skin.darkened(0.15), 4.0)
		draw_line(Vector2(4, 0), Vector2(4, -10), skin.darkened(0.15), 4.0)
		draw_colored_polygon(_ellipse(Vector2(0, -19), 9, 13), skin)
		draw_colored_polygon(_ellipse(Vector2(1.5, -17), 5, 9), belly)
		draw_colored_polygon(_ellipse(Vector2(2, -36), 10, 8), skin)
		for k in 4:
			var b := Vector2(-8 + k * 3.5, -42 + k * 0.3)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-2, 2), b + Vector2(0, -5), b + Vector2(2, 2)]), skin.darkened(0.25))
		_eye(Vector2(5, -38), 3.0)
		draw_arc(Vector2(7, -33), 3, 0.2, PI - 0.4, 6, Color(0.3, 0.1, 0.05), 1.2)
		draw_line(Vector2(6, -24), Vector2(12, -18), skin, 3.0)
		for p in [Vector2(-4, -26), Vector2(-6, -16), Vector2(-3, -10)]:
			draw_circle(p, 1.2, skin.darkened(0.3))
		if sex == 1:
			_bow(Vector2(-4, -44), Color(0.3, 0.75, 0.9))

	func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 24:
			var a := k * TAU / 24.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	root.add_child(Sheet.new())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 5:
		root.get_texture().get_image().save_png(_out)
		print("лист: ", _out)
		return true
	return false
