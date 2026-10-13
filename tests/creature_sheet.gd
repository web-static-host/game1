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
	match sheet:
		0:
			_sheet_traits(size)
		1:
			_sheet_family(size)
		_:
			_sheet_colors(size)


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


const STAT_COLORS := {"vision": Color8(80, 170, 255), "strength": Color8(240, 90, 70), "agility": Color8(120, 200, 70),
	"intellect": Color8(170, 110, 240), "heat": Color8(255, 140, 30), "cold": Color8(60, 200, 230)}
const STAT_SHORT := {"vision": "Зрение", "strength": "Сила", "agility": "Ловк.", "intellect": "Интел.", "heat": "Жара", "cold": "Холод"}


func _genome(shape: int, col: Color, eyes := 1, fingers := 4, hair := false, fur := false, muts := [], female := false) -> Dictionary:
	return {"color": [col, col], "color_mix": 0.5, "shape": [shape, shape], "shape_pick": 0, "eyes": [eyes, eyes],
		"eyes_pick": 0, "fingers": [fingers, fingers], "hair": [hair, hair], "fur": [fur, fur], "mutations": muts, "female": female}


## Житель с подписью и полосками характеристик.
func _stat_unit(cx: float, foot_y: float, w: float, g: Dictionary, caption: String) -> void:
	CreatureArt.draw(self, Vector2(cx, foot_y), w, Genetics.looks(g), t)
	_text(Vector2(cx - 110, foot_y + 24), caption, 16, INK, 220)
	var mt := Genetics.mutation_text(g)
	if Genetics.is_super(g):
		mt = "СВЕРХЮНИТ ×2"
	if Genetics.eyes_of(g) == 0:
		mt = "Мутант: без глаз · медленный, руда в глубине ×2"
	if not mt.is_empty():
		_text(Vector2(cx - 110, foot_y + 42), mt, 13, Color(0.75, 0.2, 0.3), 220)
	var st := Genetics.stats(g)
	var y := foot_y + 54
	for k in Genetics.STATS:
		var v: float = st[k]
		_text(Vector2(cx - 98, y + 10), STAT_SHORT[k], 12, Color(0.35, 0.3, 0.4))
		var bar := Rect2(cx - 50, y + 1, 90, 9)
		draw_rect(bar, Color(0, 0, 0, 0.08))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v / 2.0, 0.0, 1.0), bar.size.y)), STAT_COLORS[k])
		draw_line(Vector2(bar.position.x + bar.size.x * 0.5, y), Vector2(bar.position.x + bar.size.x * 0.5, y + 11), Color(0, 0, 0, 0.25), 1)
		_text(Vector2(cx + 44, y + 10), "%d%%" % roundi(v * 100), 12, Color(0.35, 0.3, 0.4))
		y += 13


## Признаки, мутации и характеристики.
func _sheet_traits(size: Vector2) -> void:
	_text(Vector2(0, 40), "ПРИЗНАКИ, МУТАЦИИ, ХАРАКТЕРИСТИКИ", 30, Color.WHITE, size.x)
	var card := Rect2(16, 56, size.x - 32, size.y - 68)
	_card(card)
	var red := Color.from_hsv(0.0, 1.0, 1.0)
	var blue := Color.from_hsv(0.62, 1.0, 1.0)
	var yellow := Color.from_hsv(0.15, 1.0, 1.0)
	var units := [
		[_genome(S.TRIANGLE, red), "Треугольник, красный ♂"],
		[_genome(S.SQUARE, blue, 1, 4, false, false, [], true), "Квадрат, синий ♀"],
		[_genome(S.ROUND, yellow), "Круг, жёлтый ♂"],
		[_genome(S.ROUND, Color.from_hsv(0.33, 1.0, 1.0), 2, 4, false, false, [], true), "2 глаза ♀"],
		[_genome(S.SQUARE, Color.from_hsv(0.8, 1.0, 1.0), 3, 4, false, false, ["eyes"]), "3 глаза"],
		[_genome(S.TRIANGLE, Color.from_hsv(0.92, 1.0, 1.0), 0, 4, false, false, ["eyes"]), "Без глаз"],
		[_genome(S.TRIANGLE, Color.from_hsv(0.5, 1.0, 1.0), 1, 5, false, false, ["fingers"]), "5 пальцев"],
		[_genome(S.ROUND, Color.from_hsv(0.08, 1.0, 1.0), 2, 4, true, true, ["hair", "fur"], true), "Шерсть и волосы ♀"],
		[_genome(S.SQUARE, Color.from_hsv(0.6, 0.9, 1.0), 1, 4, false, true, ["fur"]), "Шерсть, синий"],
		[_genome(S.TRIANGLE, Color.from_hsv(0.75, 1.0, 1.0), 2, 4, true, false, ["hair"]), "Волосы"],
	]
	for i in units.size():
		var col := i % 5
		var row := i / 5
		var cx := card.position.x + card.size.x * (col + 0.5) / 5.0
		_stat_unit(cx, card.position.y + 180 + row * 330, 82, units[i][0], units[i][1])


## Семья по настоящей генетике: 4 основателя → 2 родителя → 6 детей.
func _sheet_family(size: Vector2) -> void:
	_text(Vector2(0, 40), "НАСЛЕДОВАНИЕ (считает Genetics)", 30, Color.WHITE, size.x)
	var card := Rect2(16, 56, size.x - 32, size.y - 68)
	_card(card)
	var rng := RandomNumberGenerator.new()
	var gp: Array = []
	var mom: Dictionary
	var dad: Dictionary
	var kids: Array = []
	# Подбираем семью, где есть и мутант, и «в бабушку» — чтобы показать всё.
	for seed in range(1, 5000):
		rng.seed = seed
		gp = [Genetics.founder(rng), Genetics.founder(rng), Genetics.founder(rng), Genetics.founder(rng)]
		mom = Genetics.child(gp[0], gp[1], rng)
		dad = Genetics.child(gp[2], gp[3], rng)
		if Genetics.is_mutant(mom) or Genetics.is_mutant(dad):
			continue
		kids.clear()
		for i in 6:
			kids.append(Genetics.child(mom, dad, rng))
		var mutants := kids.filter(func(k: Dictionary) -> bool: return Genetics.is_mutant(k)).size()
		var shapes := {}
		for k in kids:
			shapes[Genetics.shape_of(k)] = true
		if mutants == 1 and shapes.size() >= 2 and Genetics.shape_of(mom) != Genetics.shape_of(dad):
			break
	var lx := card.position.x
	var lw := card.size.x
	_text(Vector2(lx, card.position.y + 26), "бабушки и дедушки", 15, Color(0.4, 0.35, 0.45), lw)
	for i in 4:
		var x: float = lx + lw * [0.2, 0.36, 0.64, 0.8][i]
		CreatureArt.draw(self, Vector2(x, card.position.y + 120), 52, Genetics.looks(gp[i]), t)
	_small(lx + lw * 0.28, card.position.y + 300, 72, mom, "Мама")
	_small(lx + lw * 0.72, card.position.y + 300, 72, dad, "Папа")
	_text(Vector2(lx, card.position.y + 250), "+", 40, INK, lw)
	for i in kids.size():
		var k: Dictionary = kids[i]
		var mix := roundi(k["color_mix"] * 100)
		_small(lx + lw * (i + 0.5) / 6.0, card.position.y + 520, 70, k, "смесь %d/%d" % [100 - mix, mix])


func _small(cx: float, foot_y: float, w: float, g: Dictionary, caption: String) -> void:
	CreatureArt.draw(self, Vector2(cx, foot_y), w, Genetics.looks(g), t)
	_text(Vector2(cx - 100, foot_y + 24), caption, 15, INK, 200)
	var sub := Genetics.mutation_text(g)
	var hidden: PackedStringArray = []
	if Genetics.shape_of(g) != g["shape"][1 - g["shape_pick"]]:
		hidden.append("скрыт: " + Genetics.SHAPE_NAMES[g["shape"][1 - g["shape_pick"]]])
	if sub.is_empty() and not hidden.is_empty():
		sub = ", ".join(hidden)
	if not sub.is_empty():
		_text(Vector2(cx - 100, foot_y + 42), sub, 12, Color(0.75, 0.2, 0.3), 200)


## Яркие стартовые цвета и смешивание.
func _sheet_colors(size: Vector2) -> void:
	_text(Vector2(0, 40), "ЦВЕТА: старт и смешивание", 30, Color.WHITE, size.x)
	var card := Rect2(16, 56, size.x - 32, size.y - 68)
	_card(card)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_text(Vector2(card.position.x, card.position.y + 26), "основатели колонии — яркие цвета", 15, Color(0.4, 0.35, 0.45), card.size.x)
	for i in 10:
		var g := Genetics.founder(rng)
		g["shape"] = [i % 3, i % 3]
		CreatureArt.draw(self, Vector2(card.position.x + card.size.x * (i + 0.5) / 10.0, card.position.y + 130), 56, Genetics.looks(g), t)
	_text(Vector2(card.position.x, card.position.y + 178), "дети: смесь по кругу оттенков (мама · 25% · 50% · 75% · папа)", 15, Color(0.4, 0.35, 0.45), card.size.x)
	var pairs := [[Color.from_hsv(0.0, 1, 1), Color.from_hsv(0.62, 1, 1)], [Color.from_hsv(0.15, 1, 1), Color.from_hsv(0.8, 1, 1)],
		[Color.from_hsv(0.33, 1, 1), Color.from_hsv(0.92, 1, 1)]]
	for r in pairs.size():
		var a: Color = pairs[r][0]
		var b: Color = pairs[r][1]
		var y := card.position.y + 270 + r * 135
		var ks := [0.0, 0.25, 0.5, 0.75, 1.0]
		for i in ks.size():
			var c := CreatureArt.mix(a, b, ks[i])
			CreatureArt.draw(self, Vector2(card.position.x + card.size.x * (0.14 + i * 0.18), y), 56,
				{"color": c, "shape": S.TRIANGLE if r == 0 else (S.ROUND if r == 1 else S.SQUARE), "eyes": 1, "fingers": 4}, t)


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
