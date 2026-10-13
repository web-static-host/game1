extends Node2D
## Лист превью жителей (рисует CreatureArt). Какой лист — в sheet.

var sheet := 0
var t := 0.8

const CARD := Color(1, 1, 1, 0.82)
const INK := Color(0.16, 0.11, 0.2)
const S := CreatureArt.Shape


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([Color8(120, 200, 255), Color8(120, 200, 255), Color8(190, 235, 255), Color8(190, 235, 255)]))
	if sheet == 0:
		_sheet_hero(size)
	else:
		_sheet_mixing(size)


func _text(pos: Vector2, text: String, fs: int, col := INK, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT
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


## Три формы в одном стиле: треугольник (утверждён), круг, квадрат.
func _sheet_hero(size: Vector2) -> void:
	_text(Vector2(0, 50), "ЖИТЕЛИ · три формы", 38, Color.WHITE, size.x)
	var card := Rect2(24, 76, size.x - 48, size.y - 92)
	_card(card)
	var units := [
		[{"shape": S.TRIANGLE, "color": Color8(70, 130, 255), "eyes": 1, "fingers": 4, "mood": 1.0}, "Треугольник"],
		[{"shape": S.ROUND, "color": Color8(255, 150, 40), "eyes": 1, "fingers": 4, "mood": 1.0}, "Круг"],
		[{"shape": S.SQUARE, "color": Color8(80, 200, 90), "eyes": 1, "fingers": 4, "mood": 1.0}, "Квадрат"],
	]
	for i in units.size():
		var cx := card.position.x + card.size.x * (i + 0.5) / units.size()
		CreatureArt.draw(self, Vector2(cx, card.end.y - 80), 190, units[i][0], t)
		_text(Vector2(cx - 120, card.end.y - 30), units[i][1], 24, INK, 240)


## Смешивание цвета у детей: было (RGB) и стало (по кругу оттенков).
func _sheet_mixing(size: Vector2) -> void:
	_text(Vector2(0, 50), "СМЕШИВАНИЕ ЦВЕТА у детей", 38, Color.WHITE, size.x)
	var pairs := [[Color8(255, 140, 40), Color8(60, 110, 255)], [Color8(255, 60, 70), Color8(80, 210, 70)], [Color8(255, 220, 40), Color8(170, 70, 230)]]
	var card := Rect2(24, 76, size.x - 48, size.y - 92)
	_card(card)
	var cols := 7
	var cw := (card.size.x - 140) / cols
	var x0 := card.position.x + 140
	_text(Vector2(x0, card.position.y + 34), "мама", 16, Color(0.4, 0.35, 0.45), cw)
	_text(Vector2(x0 + cw * 6, card.position.y + 34), "папа", 16, Color(0.4, 0.35, 0.45), cw)
	_text(Vector2(x0 + cw * 1, card.position.y + 34), "дети: 30% · 50% · 70% папы — было (RGB) и стало", 16, Color(0.4, 0.35, 0.45), cw * 5)
	var rh := (card.size.y - 50) / 6.0
	for pi in pairs.size():
		var a: Color = pairs[pi][0]
		var b: Color = pairs[pi][1]
		for mode in 2:
			var row := pi * 2 + mode
			var fy := card.position.y + 50 + rh * (row + 1) - 8
			_text(Vector2(card.position.x + 14, fy - rh * 0.3), "было" if mode == 0 else "стало", 18,
				Color(0.55, 0.5, 0.6) if mode == 0 else Color(0.2, 0.6, 0.35))
			var colors: Array[Color] = [a]
			for k in [0.3, 0.5, 0.7]:
				colors.append(a.lerp(b, k) if mode == 0 else CreatureArt.mix(a, b, k))
			colors.append(b)
			var slots := [0, 2, 3, 4, 6]
			for i in colors.size():
				var cx: float = x0 + cw * (slots[i] + 0.5)
				CreatureArt.draw(self, Vector2(cx, fy), 50, {"shape": S.TRIANGLE, "color": colors[i], "eyes": 1, "fingers": 3, "mood": 0.8}, t)
		draw_line(Vector2(card.position.x + 14, card.position.y + 50 + rh * (pi * 2 + 2) + 4),
			Vector2(card.end.x - 14, card.position.y + 50 + rh * (pi * 2 + 2) + 4), Color(0.4, 0.35, 0.45, 0.15), 2)
