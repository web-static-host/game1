extends Node2D
## Лист превью гавриков (рисует CreatureArt). Какой лист — в sheet.

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
			_sheet_mutations(size, 0)
		1:
			_sheet_mutations(size, 1)
		2:
			_sheet_stats(size)
		3:
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


const RARITY_COLORS := [Color8(110, 160, 110), Color8(70, 140, 235), Color8(165, 90, 230), Color8(230, 165, 20)]


## Основатель с заданной формой и цветом, затем — нужная мутация.
func _mutant(seed: int, shape: int, col: Color, kinds: Array, female := false, eyes := 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Genetics.founder(rng)
	g["shape"] = [shape, shape]
	g["color"] = [col, col]
	g["eyes"] = [eyes, eyes]
	g["female"] = female
	g["personality"] = ""
	for k in kinds:
		Genetics.mutate(g, rng, k)
	if kinds.has("eyes"):
		g["eyes"] = [eyes + 1, eyes + 1] # для показа — глаз стало больше
	if kinds.has("fingers"):
		g["fingers"] = [5, 5]
	if kinds.has("color"):
		g["color"] = [Color(0.45, 0.32, 0.6), Color(0.45, 0.32, 0.6)]
	return g


## Мутации с меткой редкости.
func _sheet_mutations(size: Vector2, part: int) -> void:
	var title: String = ["МУТАЦИИ · обычные и необычные", "МУТАЦИИ · редкие и очень редкие"][part]
	_text(Vector2(0, 40), title, 30, Color.WHITE, size.x)
	var card := Rect2(16, 56, size.x - 32, size.y - 68)
	_card(card)
	var hsv := func(h: float) -> Color: return Color.from_hsv(h, 1.0, 1.0)
	var items: Array = []
	if part == 0:
		items = [
			[_mutant(1, S.ROUND, hsv.call(0.6), ["color"]), "Новый цвет"],
			[_mutant(2, S.SQUARE, hsv.call(0.8), ["eyes"], false, 3), ""],
			[_mutant(3, S.ROUND, hsv.call(0.15), ["eyes"], true, 4), ""],
			[_mutant(4, S.TRIANGLE, hsv.call(0.5), ["fingers"]), ""],
			[_mutant(5, S.SQUARE, hsv.call(0.95), ["pattern"]), ""],
			[_mutant(6, S.ROUND, hsv.call(0.3), ["pattern"]), ""],
			[_mutant(7, S.TRIANGLE, hsv.call(0.75), ["hair"], true), ""],
			[_mutant(8, S.SQUARE, hsv.call(0.07), ["fur"]), ""],
			[_mutant(9, S.TRIANGLE, hsv.call(0.33), ["long_arms"]), ""],
			[_mutant(10, S.ROUND, hsv.call(0.9), [], true, 2), "Гаврик ♀ (ресницы)"],
		]
	else:
		items = [
			[_mutant(11, S.ROUND, hsv.call(0.12), ["antennae"]), ""],
			[_mutant(12, S.SQUARE, hsv.call(0.0), ["horn"]), ""],
			[_mutant(13, S.TRIANGLE, hsv.call(0.55), ["gills"]), ""],
			[_mutant(14, S.SQUARE, hsv.call(0.65), ["giant"]), ""],
			[_mutant(15, S.TRIANGLE, hsv.call(0.92), ["tiny"], true), ""],
			[_mutant(16, S.ROUND, hsv.call(0.18), ["glow"]), ""],
			[_mutant(17, S.ROUND, hsv.call(0.38), ["shell"]), ""],
			[_mutant(18, S.TRIANGLE, hsv.call(0.0), ["albino"], true), ""],
			[_mutant(19, S.SQUARE, hsv.call(0.0), ["melanist"]), ""],
			[_mutant(20, S.TRIANGLE, hsv.call(0.97), ["blind"]), ""],
		]
	for i in items.size():
		var col := i % 5
		var row := i / 5
		var cx := card.position.x + card.size.x * (col + 0.5) / 5.0
		var foot := card.position.y + 245 + row * 315
		var g: Dictionary = items[i][0]
		CreatureArt.draw(self, Vector2(cx, foot), 86, Genetics.looks(g), t)
		var caption: String = items[i][1]
		var r := Genetics.rarity(g)
		if caption.is_empty():
			caption = Genetics.mutation_text(g).trim_prefix("Мутант: ").split(" (")[0]
			caption = caption.substr(0, 1).to_upper() + caption.substr(1)
		_text(Vector2(cx - 120, foot + 30), caption, 18, INK, 240)
		if r >= 0:
			var tag: String = Genetics.RARITY_NAMES[r]
			var tw := tag.length() * 8.0 + 20.0
			var sb := StyleBoxFlat.new()
			sb.bg_color = RARITY_COLORS[r]
			sb.set_corner_radius_all(10)
			draw_style_box(sb, Rect2(cx - tw * 0.5, foot + 40, tw, 22))
			_text(Vector2(cx - 120, foot + 57), tag, 14, Color(1, 1, 1), 240)
		var ab := Genetics.ability_text(g)
		if not ab.is_empty():
			_text(Vector2(cx - 120, foot + 82), ab, 12, Color(0.4, 0.35, 0.45), 240)


## Характеристики четырёх гавриков: 14 полосок, характер и особенности.
func _sheet_stats(size: Vector2) -> void:
	_text(Vector2(0, 40), "ХАРАКТЕРИСТИКИ И ХАРАКТЕР", 30, Color.WHITE, size.x)
	var card := Rect2(16, 56, size.x - 32, size.y - 68)
	_card(card)
	var units := [
		[_mutant(31, S.TRIANGLE, Color.from_hsv(0.0, 1, 1), []), "трудоголик"],
		[_mutant(32, S.SQUARE, Color.from_hsv(0.66, 1, 1), ["fur"], true), "смельчак"],
		[_mutant(33, S.ROUND, Color.from_hsv(0.15, 1, 1), [], true, 2), "весельчак"],
		[_mutant(34, S.SQUARE, Color.from_hsv(0.33, 1, 1), ["giant"]), "обжора"],
	]
	for i in units.size():
		var g: Dictionary = units[i][0]
		g["personality"] = units[i][1]
		var cx := card.position.x + card.size.x * (i + 0.5) / units.size()
		CreatureArt.draw(self, Vector2(cx, card.position.y + 190), 80, Genetics.looks(g), t)
		var who := "♀" if g["female"] else "♂"
		_text(Vector2(cx - 150, card.position.y + 218), "%s · %s" % [who, g["personality"]], 18, INK, 300)
		var mt := Genetics.mutation_text(g)
		if not mt.is_empty():
			_text(Vector2(cx - 150, card.position.y + 238), mt, 13, Color(0.75, 0.2, 0.3), 300)
		var st := Genetics.stats(g)
		for j in Genetics.STATS.size():
			var k: String = Genetics.STATS[j]
			var y := card.position.y + 262 + j * 22
			var v: float = st[k]
			_text(Vector2(cx - 140, y + 12), Genetics.STAT_NAMES[k], 13, Color(0.35, 0.3, 0.4))
			var bar := Rect2(cx - 30, y + 3, 110, 10)
			draw_rect(bar, Color(0, 0, 0, 0.08))
			var good := v >= 1.0 if k != "appetite" else v <= 1.0
			var fill := Color8(110, 200, 90) if good else Color8(240, 120, 80)
			if absf(v - 1.0) < 0.01:
				fill = Color8(150, 160, 180)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v / 2.0, 0.0, 1.0), bar.size.y)), fill)
			draw_line(Vector2(bar.position.x + bar.size.x * 0.5, y + 1), Vector2(bar.position.x + bar.size.x * 0.5, y + 15), Color(0, 0, 0, 0.25), 1)
			_text(Vector2(cx + 86, y + 12), "%d%%" % roundi(v * 100), 13, Color(0.35, 0.3, 0.4))


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
