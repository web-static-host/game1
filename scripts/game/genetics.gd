class_name Genetics
extends RefCounted
## Генетика жителей.
##
## Каждый признак — две копии гена: одна от матери, одна от отца. Ребёнку от каждого
## родителя достаётся одна случайная копия. Видно (фенотип):
##   - цвет — смесь двух копий по кругу оттенков в своей пропорции (не всегда 50/50);
##   - форма тела и глаза — одна из двух копий («сильная»); вторая скрыта и может
##     проявиться у внуков — «в бабушку»;
##   - пальцы — среднее двух копий;
##   - волосы и шерсть — только если обе копии их несут (иначе житель — скрытый носитель).
## Мутация — примерно в 1 рождении из 10: меняется один признак, мутация наследуется.
## Сверхюнит — цвет рядом с градиентом лого: все характеристики 200%.

const MUTATION_CHANCE := 0.1
## Насколько близко к цвету лого нужно попасть, чтобы родился сверхюнит.
const SUPER_RADIUS := 0.07

const SHAPE_NAMES := ["треугольник", "квадрат", "круг"]
const STAT_NAMES := {"vision": "Зрение", "strength": "Сила", "agility": "Ловкость", "intellect": "Интеллект",
	"heat": "Жара", "cold": "Холод"}
const STATS := ["vision", "strength", "agility", "intellect", "heat", "cold"]
const MUTATION_NAMES := {"color": "цвет", "eyes": "глаза", "fingers": "пальцы", "hair": "волосы", "fur": "шерсть", "shape": "форма"}


## Яркий стартовый цвет: полная насыщенность и яркость, любой оттенок, кроме бирюзы лого
## (сверхюнит не должен выпасть сразу).
static func bright_color(rng: RandomNumberGenerator) -> Color:
	while true:
		var c := Color.from_hsv(rng.randf(), rng.randf_range(0.85, 1.0), 1.0)
		if CreatureArt.super_distance(c) > SUPER_RADIUS * 2.5:
			return c
	return Color.RED


## Новый житель первого поколения: обе копии одинаковые, без скрытых генов.
static func founder(rng: RandomNumberGenerator) -> Dictionary:
	var col := bright_color(rng)
	var shape := rng.randi_range(0, 2)
	var eyes := 2 if rng.randf() < 0.2 else 1
	return {
		"color": [col, col], "color_mix": 0.5,
		"shape": [shape, shape], "shape_pick": 0,
		"eyes": [eyes, eyes], "eyes_pick": 0,
		"fingers": [4, 4],
		"hair": [false, false], "fur": [false, false],
		"mutations": [],
	}


## Ребёнок двух родителей. Вероятность мутации — MUTATION_CHANCE.
static func child(mother: Dictionary, father: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var g := {"mutations": []}
	for gene in ["color", "shape", "eyes", "fingers", "hair", "fur"]:
		var a: Array = mother[gene]
		var b: Array = father[gene]
		g[gene] = [a[rng.randi() % 2], b[rng.randi() % 2]]
	# Пропорция смеси цвета — своя у каждого: от 15/85 до 85/15, чаще ближе к середине.
	g["color_mix"] = clampf(0.5 + (rng.randf() - rng.randf()) * 0.7, 0.15, 0.85)
	g["shape_pick"] = rng.randi() % 2
	g["eyes_pick"] = rng.randi() % 2
	if rng.randf() < MUTATION_CHANCE:
		mutate(g, rng)
	return g


## Мутация одного признака. Меняется копия, которая видна, — мутант заметен сразу
## и передаёт мутацию дальше.
static func mutate(g: Dictionary, rng: RandomNumberGenerator, kind := "") -> void:
	if kind.is_empty():
		kind = ["color", "eyes", "fingers", "hair", "fur", "shape"][rng.randi() % 6]
	match kind:
		"color":
			# Мутация цвета — любой цвет, не только яркий: так можно попасть и в тона лого.
			var c := Color(rng.randf(), rng.randf(), rng.randf())
			g["color"] = [c, c]
			g["color_mix"] = 0.5
		"eyes":
			var e: int = [0, 2, 2, 3][rng.randi() % 4]
			g["eyes"][g["eyes_pick"]] = e
		"fingers":
			var f: int = [2, 3, 5, 6][rng.randi() % 4]
			g["fingers"] = [f, f]
		"hair":
			g["hair"] = [true, true]
		"fur":
			g["fur"] = [true, true]
		"shape":
			var now := shape_of(g)
			g["shape"][g["shape_pick"]] = (now + 1 + rng.randi() % 2) % 3
	g["mutations"].append(kind)


# --- Что видно ----------------------------------------------------------------------

static func color_of(g: Dictionary) -> Color:
	return CreatureArt.mix(g["color"][0], g["color"][1], g["color_mix"])


static func shape_of(g: Dictionary) -> int:
	return g["shape"][g["shape_pick"]]


static func eyes_of(g: Dictionary) -> int:
	return g["eyes"][g["eyes_pick"]]


static func fingers_of(g: Dictionary) -> int:
	return roundi((g["fingers"][0] + g["fingers"][1]) * 0.5)


static func has_hair(g: Dictionary) -> bool:
	return g["hair"][0] and g["hair"][1]


static func has_fur(g: Dictionary) -> bool:
	return g["fur"][0] and g["fur"][1]


static func is_super(g: Dictionary) -> bool:
	return CreatureArt.super_distance(color_of(g)) < SUPER_RADIUS


static func is_mutant(g: Dictionary) -> bool:
	return not g["mutations"].is_empty()


## Словарь для CreatureArt.draw.
static func looks(g: Dictionary) -> Dictionary:
	var col := color_of(g)
	return {"color": col, "shape": shape_of(g), "eyes": eyes_of(g), "fingers": fingers_of(g),
		"hair": has_hair(g), "fur": has_fur(g), "super": is_super(g),
		"hair_color": col.darkened(0.35)}


# --- Характеристики (1.0 = 100%) ---------------------------------------------------

## Зрение — от глаз; сила, ловкость, интеллект — от формы, пальцев и глаз;
## стойкость к жаре — у красных и тёплых, к холоду — у синих; шерсть греет.
static func stats(g: Dictionary) -> Dictionary:
	var s := {"vision": 1.0, "strength": 1.0, "agility": 1.0, "intellect": 1.0, "heat": 1.0, "cold": 1.0}
	var eyes := eyes_of(g)
	s["vision"] = [0.3, 1.0, 1.3, 1.6][clampi(eyes, 0, 3)]
	s["intellect"] += 0.1 * maxi(0, eyes - 1)
	match shape_of(g):
		CreatureArt.Shape.TRIANGLE:
			s["agility"] += 0.2
		CreatureArt.Shape.SQUARE:
			s["strength"] += 0.3
		CreatureArt.Shape.ROUND:
			s["intellect"] += 0.2
	s["agility"] += 0.12 * (fingers_of(g) - 4)
	var col := color_of(g)
	var h := col.ok_hsl_h
	var sat := col.ok_hsl_s
	# Оттенок: красный около 0.08 по кругу OKHSL, синий около 0.73.
	s["heat"] += 0.6 * sat * maxf(0.0, 1.0 - _hue_dist(h, 0.08) / 0.2)
	s["cold"] += 0.6 * sat * maxf(0.0, 1.0 - _hue_dist(h, 0.73) / 0.2)
	if has_fur(g):
		s["cold"] += 0.4
		s["heat"] -= 0.2
	if has_hair(g):
		s["cold"] += 0.1
	if is_super(g):
		for k in s:
			s[k] *= 2.0
	return s


static func _hue_dist(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)


## Строка для карточки: «Мутант: 3 глаза».
static func mutation_text(g: Dictionary) -> String:
	if not is_mutant(g):
		return ""
	var parts: PackedStringArray = []
	for m in g["mutations"]:
		match m:
			"eyes":
				parts.append("%d %s" % [eyes_of(g), ["глаз", "глаз", "глаза", "глаза"][clampi(eyes_of(g), 0, 3)]])
			"fingers":
				parts.append("%d пальцев" % fingers_of(g) if fingers_of(g) >= 5 else "%d пальца" % fingers_of(g))
			_:
				parts.append(MUTATION_NAMES.get(m, m))
	return "Мутант: " + ", ".join(parts)
