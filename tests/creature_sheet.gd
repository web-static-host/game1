extends Node2D
## Лист превью жителей (рисует CreatureArt). Какой лист — в sheet.

var sheet := 0
var t := 0.8

const BG_TOP := Color8(255, 214, 120)
const BG_BOTTOM := Color8(255, 160, 90)
const CARD := Color(1, 1, 1, 0.82)
const INK := Color(0.16, 0.11, 0.2)
const S := CreatureArt.Shape


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([Color8(120, 200, 255), Color8(120, 200, 255), Color8(190, 235, 255), Color8(190, 235, 255)]))
	if sheet == 0:
		_sheet_looks(size)
	else:
		_sheet_family(size)


func _text(pos: Vector2, text: String, fs: int, col := INK, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT
	# Обводка как в мобильных играх.
	if col == Color.WHITE:
		for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(0, 3)]:
			draw_string(font, pos + d, text, align, width, fs, INK)
	draw_string(font, pos, text, align, width, fs, col)


func _card(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(26)
	sb.border_color = Color(1, 1, 1)
	sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.15)
	sb.shadow_size = 10
	draw_style_box(sb, r)


func _unit(cx: float, foot_y: float, w: float, g: Dictionary, caption: String, sub := "") -> void:
	CreatureArt.draw(self, Vector2(cx, foot_y), w, g, t)
	_text(Vector2(cx - 100, foot_y + 34), caption, 20, INK, 200)
	if not sub.is_empty():
		_text(Vector2(cx - 100, foot_y + 58), sub, 16, Color(0.75, 0.2, 0.3), 200)


func _sheet_looks(size: Vector2) -> void:
	_text(Vector2(0, 50), "ЖИТЕЛИ · внешность", 38, Color.WHITE, size.x)
	var cols := 6
	var cw := (size.x - 80) / cols
	var rows := [
		[
			[{"shape": S.TRIANGLE, "color": Color8(255, 92, 70), "eyes": 1, "fingers": 3}, "Треугольник", "красный: жара"],
			[{"shape": S.SQUARE, "color": Color8(120, 210, 60), "eyes": 1, "fingers": 3}, "Квадрат", ""],
			[{"shape": S.ROUND, "color": Color8(70, 130, 255), "eyes": 1, "fingers": 3}, "Круг", "синий: холод"],
			[{"shape": S.ROUND, "color": Color8(255, 200, 40), "eyes": 2, "fingers": 3, "mood": 0.6}, "2 глаза", ""],
			[{"shape": S.SQUARE, "color": Color8(190, 90, 230), "eyes": 3, "fingers": 3}, "3 глаза", "мутант"],
			[{"shape": S.TRIANGLE, "color": Color8(255, 130, 190), "eyes": 0, "fingers": 3, "mood": 0.8}, "0 глаз", "мутант"],
		],
		[
			[{"shape": S.SQUARE, "color": Color8(240, 120, 40), "eyes": 1, "fingers": 2}, "2 пальца", ""],
			[{"shape": S.ROUND, "color": Color8(60, 190, 160), "eyes": 2, "fingers": 6, "mood": 0.5}, "6 пальцев", "мутант"],
			[{"shape": S.ROUND, "color": Color8(150, 110, 80), "eyes": 1, "fingers": 3, "fur": true}, "Шерсть", "мутант: тепло"],
			[{"shape": S.TRIANGLE, "color": Color8(110, 200, 255), "eyes": 2, "fingers": 3, "hair": true, "hair_color": Color8(255, 220, 60)}, "Хохолок", "мутант"],
			[{"shape": S.SQUARE, "color": Color8(230, 60, 90), "eyes": 2, "fingers": 4, "mood": -0.7}, "Грустный", "голод, усталость"],
			[{"shape": S.ROUND, "color": Color8(60, 60, 80), "eyes": 1, "fingers": 3, "fur": true, "hair": true, "hair_color": Color8(240, 240, 255)}, "Тёмный", "шерсть + хохолок"],
		],
	]
	var y0 := 70.0
	var rh := (size.y - y0 - 20) / rows.size()
	for r in rows.size():
		_card(Rect2(30, y0 + r * rh + 10, size.x - 60, rh - 20))
		for i in cols:
			var it: Array = rows[r][i]
			_unit(40 + cw * (i + 0.5), y0 + r * rh + rh - 92, 112, it[0], it[1], it[2])


func _mix(a: Color, b: Color, k: float) -> Color:
	return a.lerp(b, k)


func _sheet_family(size: Vector2) -> void:
	_text(Vector2(0, 50), "НАСЛЕДОВАНИЕ и СВЕРХЮНИТ", 38, Color.WHITE, size.x)
	var left := Rect2(24, 76, size.x * 0.62, size.y - 92)
	_card(left)
	var red := Color8(255, 80, 60)
	var blue := Color8(60, 120, 255)
	var green := Color8(90, 210, 80)
	var yellow := Color8(255, 210, 50)
	var lx := left.position.x
	var lw := left.size.x
	var y := func(f: float) -> float: return left.position.y + left.size.y * f
	_text(Vector2(lx, y.call(0.07)), "бабушки и дедушки", 18, Color(0.4, 0.35, 0.45), lw)
	var gp := [[red, S.TRIANGLE], [yellow, S.ROUND], [blue, S.SQUARE], [green, S.ROUND]]
	for i in 4:
		CreatureArt.draw(self, Vector2(lx + lw * (0.14 + i * 0.24), y.call(0.24)), 50, {"color": gp[i][0], "shape": gp[i][1], "eyes": 1, "fingers": 3, "mood": 0.4}, t)
	_arrow(Vector2(lx + lw * 0.26, y.call(0.27)), Vector2(lx + lw * 0.26, y.call(0.33)))
	_arrow(Vector2(lx + lw * 0.74, y.call(0.27)), Vector2(lx + lw * 0.74, y.call(0.33)))
	var mom := red.lerp(yellow, 0.35)
	var dad := blue.lerp(green, 0.3)
	_small_unit(lx + lw * 0.26, y.call(0.53), 72, {"color": mom, "shape": S.TRIANGLE, "eyes": 1, "fingers": 3}, "Мама", "")
	_small_unit(lx + lw * 0.74, y.call(0.53), 72, {"color": dad, "shape": S.SQUARE, "eyes": 2, "fingers": 3}, "Папа", "")
	_text(Vector2(lx, y.call(0.45)), "+", 48, INK, lw)
	_arrow(Vector2(lx + lw * 0.5, y.call(0.6)), Vector2(lx + lw * 0.5, y.call(0.67)))
	var kids := [
		[{"color": mom.lerp(dad, 0.3), "shape": S.TRIANGLE, "eyes": 1, "fingers": 3}, "смесь 70/30", ""],
		[{"color": mom.lerp(dad, 0.55), "shape": S.SQUARE, "eyes": 2, "fingers": 3, "mood": 0.7}, "смесь 45/55", ""],
		[{"color": green, "shape": S.ROUND, "eyes": 1, "fingers": 3}, "в дедушку", "скрытый ген"],
		[{"color": mom.lerp(dad, 0.5), "shape": S.SQUARE, "eyes": 3, "fingers": 3, "hair": true, "hair_color": Color8(255, 240, 120)}, "мутант", "3 глаза, хохолок"],
	]
	for i in kids.size():
		_small_unit(lx + lw * (0.13 + i * 0.247), y.call(0.85), 66, kids[i][0], kids[i][1], kids[i][2])
	# Сверхюнит.
	var right := Rect2(left.end.x + 20, 76, size.x - left.end.x - 44, size.y - 92)
	_card(right)
	var rc := right.position.x + right.size.x * 0.5
	_text(Vector2(right.position.x, right.position.y + 50), "СВЕРХЮНИТ", 30, Color8(9, 147, 179), right.size.x)
	CreatureArt.draw(self, Vector2(rc, right.position.y + right.size.y * 0.72), 140, {"super": true, "color": CreatureArt.SUPER_A, "shape": S.ROUND, "eyes": 2, "fingers": 4, "mood": 1.0}, t)
	_text(Vector2(right.position.x, right.end.y - 70), "цвет лого · всё ×2 (200%)", 18, INK, right.size.x)
	var bar := Rect2(rc - 110, right.end.y - 52, 220, 18)
	draw_polygon(PackedVector2Array([bar.position, Vector2(bar.end.x, bar.position.y), bar.end, Vector2(bar.position.x, bar.end.y)]),
		PackedColorArray([CreatureArt.SUPER_A, CreatureArt.SUPER_B, CreatureArt.SUPER_B, CreatureArt.SUPER_A]))
	_text(Vector2(right.position.x, right.end.y - 14), "#2CD6C1 → #0993B3", 16, Color(0.4, 0.35, 0.45), right.size.x)


func _small_unit(cx: float, foot_y: float, w: float, g: Dictionary, caption: String, sub: String) -> void:
	CreatureArt.draw(self, Vector2(cx, foot_y), w, g, t)
	_text(Vector2(cx - 90, foot_y + 28), caption, 18, INK, 180)
	if not sub.is_empty():
		_text(Vector2(cx - 90, foot_y + 48), sub, 15, Color(0.75, 0.2, 0.3), 180)


func _arrow(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, Color(0.4, 0.35, 0.45, 0.6), 4, true)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b + d * 6, b - d * 6 + n * 8, b - d * 6 - n * 8]), Color(0.4, 0.35, 0.45, 0.6))
