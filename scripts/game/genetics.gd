class_name Genetics
extends RefCounted
## Генетика гавриков.
##
## Каждый признак — две копии гена: одна от матери, одна от отца. Ребёнку от каждого
## родителя достаётся одна случайная копия. Что видно (фенотип):
##   - цвет — смесь двух копий по кругу оттенков в своей пропорции (не всегда 50/50);
##   - форма, глаза, размер — одна из двух копий («сильная»), вторая скрыта и может
##     проявиться у внуков — «в бабушку»;
##   - пальцы — среднее двух копий;
##   - доминантные признаки видны, если есть хоть одна копия; рецессивные — только
##     если обе (иначе гаврик — скрытый носитель).
## Мутация — примерно в 1 рождении из 10, разной редкости; мутация наследуется.
## Характер (трудоголик, лентяй…) не наследуется — выпадает при рождении.
## Супер-гаврик — цвет рядом с градиентом лого: все характеристики 200%.

const MUTATION_CHANCE := 0.1
## Насколько близко к цвету лого нужно попасть, чтобы родился супер-гаврик (оттенок примерно 162°–202°).
const SUPER_RADIUS := 0.10
## Стартовые цвета основателей держатся подальше от бирюзы (супер-гаврики только выводятся).
const FOUNDER_GAP := 0.175

const SHAPE_NAMES := ["треугольник", "квадрат", "круг"]
## Цвета волос: тёмные доминируют над светлыми (видна копия с меньшим номером).
const HAIR_COLORS := [Color(0.13, 0.1, 0.12), Color(0.42, 0.24, 0.12), Color(0.92, 0.42, 0.12), Color(0.98, 0.84, 0.42), Color(0.93, 0.93, 0.95)]
const HAIR_NAMES := ["чёрные", "каштановые", "рыжие", "светлые", "седые"]

## Признаки «есть/нет»: доминантные видны при одной копии, рецессивные — при двух.
const DOMINANT := ["glow", "gills", "long_arms", "antennae", "horn"]
const RECESSIVE := ["hair", "fur", "shell", "albino", "melanist"]

## Мутации: вид -> [редкость 0..3, вес].
const MUTATIONS := {
	"color": [0, 10.0], "eyes": [0, 10.0], "fingers": [0, 10.0], "pattern": [0, 10.0],
	"hair": [1, 5.0], "fur": [1, 5.0], "shape": [1, 5.0], "long_arms": [1, 5.0],
	"antennae": [2, 2.0], "horn": [2, 2.0], "gills": [2, 2.0], "giant": [2, 2.0], "tiny": [2, 2.0],
	"glow": [3, 0.7], "shell": [3, 0.7], "albino": [3, 0.7], "melanist": [3, 0.7], "blind": [3, 0.7],
}
const RARITY_NAMES := ["обычная", "необычная", "редкая", "очень редкая"]
const MUTATION_NAMES := {"color": "цвет", "eyes": "глаза", "fingers": "пальцы", "pattern": "узор",
	"hair": "волосы", "fur": "шерсть", "shape": "форма", "long_arms": "длинные руки",
	"antennae": "усики", "horn": "рог", "gills": "жабры", "giant": "гигант", "tiny": "кроха",
	"glow": "светится", "shell": "панцирь", "albino": "альбинос", "melanist": "меланист", "blind": "без глаз"}

## Характер: не наследуется.
const PERSONALITIES := ["трудоголик", "лентяй", "обжора", "весельчак", "трус", "смельчак", "педант"]

const STATS := ["vision", "strength", "agility", "intellect", "heat", "cold", "stamina", "health",
	"appetite", "fasting", "speed", "learning", "fertility", "longevity", "charm"]
const STAT_NAMES := {"vision": "Зрение", "strength": "Сила", "agility": "Ловкость", "intellect": "Интеллект",
	"heat": "Жара", "cold": "Холод", "stamina": "Выносливость", "health": "Здоровье", "appetite": "Аппетит", "fasting": "Голодостойкость",
	"speed": "Скорость", "learning": "Обучаемость", "fertility": "Плодовитость", "longevity": "Долголетие",
	"charm": "Общительность"}

## Цвет как характер: эталонные цвета.
const RED := Color(1, 0, 0)
const ORANGE := Color(1, 0.5, 0)
const YELLOW := Color(1, 1, 0)
const GREEN := Color(0, 1, 0)
const BLUE := Color(0, 0, 1)
const PURPLE := Color(0.55, 0, 1)
const PINK := Color(1, 0.2, 0.6)


## Яркий стартовый цвет: полная насыщенность и яркость, любой оттенок, кроме бирюзы лого.
static func bright_color(rng: RandomNumberGenerator) -> Color:
	while true:
		var c := Color.from_hsv(rng.randf(), rng.randf_range(0.85, 1.0), 1.0)
		if CreatureArt.super_distance(c) > FOUNDER_GAP:
			return c
	return Color.RED


static func _pair(v: Variant) -> Array:
	return [v, v]


## Гаврик первого поколения: обе копии одинаковые, без скрытых генов и мутаций.
static func founder(rng: RandomNumberGenerator) -> Dictionary:
	var col := bright_color(rng)
	var g := {
		"color": _pair(col), "color_mix": 0.5,
		"shape": _pair(rng.randi_range(0, 2)), "shape_pick": 0,
		"eyes": _pair(2 if rng.randf() < 0.2 else 1), "eyes_pick": 0,
		"fingers": _pair(4),
		"size": _pair(0), "size_pick": 0,
		"pattern": _pair(0),
		"hair_color": [rng.randi() % HAIR_COLORS.size(), rng.randi() % HAIR_COLORS.size()],
		"female": rng.randf() < 0.5,
		"personality": _personality(rng),
		"mutations": [],
	}
	for k in DOMINANT + RECESSIVE:
		g[k] = _pair(false)
	return g


static func _personality(rng: RandomNumberGenerator) -> String:
	return PERSONALITIES[rng.randi() % PERSONALITIES.size()] if rng.randf() < 0.6 else ""


## Ребёнок двух родителей.
## irradiated — кто-то из родителей облучён ураном: мутация у ребёнка всегда, любая
## с одинаковой вероятностью (без учёта редкости).
static func child(mother: Dictionary, father: Dictionary, rng: RandomNumberGenerator, irradiated := false) -> Dictionary:
	var g := {"mutations": []}
	for gene in ["color", "shape", "eyes", "fingers", "size", "pattern", "hair_color"] + DOMINANT + RECESSIVE:
		var a: Array = mother[gene]
		var b: Array = father[gene]
		g[gene] = [a[rng.randi() % 2], b[rng.randi() % 2]]
	# Пропорция смеси цвета — от 15/85 до 85/15, чаще ближе к середине.
	g["color_mix"] = clampf(0.5 + (rng.randf() - rng.randf()) * 0.7, 0.15, 0.85)
	g["shape_pick"] = rng.randi() % 2
	g["eyes_pick"] = rng.randi() % 2
	g["size_pick"] = rng.randi() % 2
	g["female"] = rng.randf() < 0.5
	g["personality"] = _personality(rng)
	if irradiated:
		var kinds := MUTATIONS.keys()
		mutate(g, rng, kinds[rng.randi() % kinds.size()])
	elif rng.randf() < MUTATION_CHANCE:
		mutate(g, rng)
	return g


## Случайный вид мутации с учётом редкости.
static func roll_mutation(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in MUTATIONS:
		total += MUTATIONS[k][1]
	var r := rng.randf() * total
	for k in MUTATIONS:
		r -= MUTATIONS[k][1]
		if r <= 0.0:
			return k
	return "color"


## Мутация одного признака. Меняется видимая копия — мутант заметен сразу и передаёт
## мутацию дальше (рецессивную — пока носителем).
static func mutate(g: Dictionary, rng: RandomNumberGenerator, kind := "") -> void:
	if kind.is_empty():
		kind = roll_mutation(rng)
	match kind:
		"color":
			# Любой цвет, не только яркий: так можно попасть и в тона лого.
			g["color"] = _pair(Color(rng.randf(), rng.randf(), rng.randf()))
			g["color_mix"] = 0.5
		"eyes":
			# Глаз становится больше (иногда меньше): 3 → 4 → 5…
			var n := eyes_of(g)
			n = n - 1 if n > 1 and rng.randf() < 0.25 else n + 1
			g["eyes"] = _pair(maxi(1, n))
		"blind":
			g["eyes"] = _pair(0)
		"fingers":
			var f := fingers_of(g)
			f = f - 1 if f > 2 and rng.randf() < 0.25 else f + 1
			g["fingers"] = _pair(f)
		"pattern":
			g["pattern"] = _pair(1 + rng.randi() % 2)
		"shape":
			g["shape"][g["shape_pick"]] = (shape_of(g) + 1 + rng.randi() % 2) % 3
		"giant":
			g["size"] = _pair(1)
		"tiny":
			g["size"] = _pair(-1)
		"albino":
			g["albino"] = _pair(true)
			g["melanist"] = _pair(false)
		"melanist":
			g["melanist"] = _pair(true)
			g["albino"] = _pair(false)
		_:
			g[kind] = _pair(true)
	g["mutations"].append(kind)


# --- Сохранение ----------------------------------------------------------------------

const INT_GENES := ["shape", "eyes", "fingers", "size", "pattern", "hair_color"]


## Геном для JSON: цвета — массивами чисел.
static func to_save(g: Dictionary) -> Dictionary:
	var d := g.duplicate(true)
	var cols: Array = []
	for c: Color in g["color"]:
		cols.append([c.r, c.g, c.b])
	d["color"] = cols
	return d


## Геном из JSON: цвета обратно в Color, числа — целые, недостающие гены — по умолчанию.
static func from_save(d: Dictionary) -> Dictionary:
	var g := d.duplicate(true)
	var cols: Array = []
	for c in d.get("color", [[1, 0, 0], [1, 0, 0]]):
		cols.append(Color(float(c[0]), float(c[1]), float(c[2])))
	g["color"] = cols
	for k in INT_GENES:
		var a: Array = d.get(k, [0, 0] if k != "fingers" else [4, 4])
		g[k] = [int(a[0]), int(a[1])]
	for k in ["shape_pick", "eyes_pick", "size_pick"]:
		g[k] = int(d.get(k, 0))
	for k in DOMINANT + RECESSIVE:
		var a: Array = d.get(k, [false, false])
		g[k] = [bool(a[0]), bool(a[1])]
	g["color_mix"] = float(d.get("color_mix", 0.5))
	g["female"] = bool(d.get("female", false))
	g["personality"] = str(d.get("personality", ""))
	var muts: Array = []
	for m in d.get("mutations", []):
		muts.append(str(m))
	g["mutations"] = muts
	return g


# --- Что видно ----------------------------------------------------------------------

static func color_of(g: Dictionary) -> Color:
	return CreatureArt.mix(g["color"][0], g["color"][1], g["color_mix"])


static func shape_of(g: Dictionary) -> int:
	return g["shape"][g["shape_pick"]]


static func eyes_of(g: Dictionary) -> int:
	return g["eyes"][g["eyes_pick"]]


static func fingers_of(g: Dictionary) -> int:
	return roundi((g["fingers"][0] + g["fingers"][1]) * 0.5)


static func size_of(g: Dictionary) -> int:
	return g["size"][g["size_pick"]]


static func pattern_of(g: Dictionary) -> int:
	return maxi(g["pattern"][0], g["pattern"][1])


## Виден ли признак «есть/нет».
static func has(g: Dictionary, key: String) -> bool:
	var a: Array = g[key]
	return (a[0] or a[1]) if DOMINANT.has(key) else (a[0] and a[1])


static func is_super(g: Dictionary) -> bool:
	return not has(g, "albino") and not has(g, "melanist") and CreatureArt.super_distance(color_of(g)) < SUPER_RADIUS


static func is_mutant(g: Dictionary) -> bool:
	return not g["mutations"].is_empty()


## Самая редкая мутация гаврика (0..3) или -1.
static func rarity(g: Dictionary) -> int:
	var r := -1
	for m in g["mutations"]:
		r = maxi(r, MUTATIONS[m][0])
	return r


## Словарь для CreatureArt.draw.
static func looks(g: Dictionary) -> Dictionary:
	var col := color_of(g)
	var d := {"color": col, "shape": shape_of(g), "eyes": eyes_of(g), "fingers": fingers_of(g),
		"size": size_of(g), "pattern": pattern_of(g), "super": is_super(g),
		"hair_color": HAIR_COLORS[mini(g["hair_color"][0], g["hair_color"][1])], "female": g.get("female", false)}
	for k in DOMINANT + RECESSIVE:
		d[k] = has(g, k)
	return d


# --- Характеристики (1.0 = 100%) ---------------------------------------------------

static func stats(g: Dictionary) -> Dictionary:
	var s := {}
	for k in STATS:
		s[k] = 1.0
	var eyes := eyes_of(g)
	s["vision"] = 0.0 if eyes == 0 else 1.0 + 0.3 * (eyes - 1)
	s["intellect"] += 0.1 * maxi(0, eyes - 1)
	match shape_of(g):
		CreatureArt.Shape.TRIANGLE:
			s["agility"] += 0.2
			s["speed"] += 0.1
		CreatureArt.Shape.SQUARE:
			s["strength"] += 0.3
		CreatureArt.Shape.ROUND:
			s["intellect"] += 0.2
			s["stamina"] += 0.1
	s["agility"] += 0.12 * (fingers_of(g) - 4)
	# Цвет как характер.
	if not has(g, "albino") and not has(g, "melanist"):
		var col := color_of(g)
		s["heat"] += 0.6 * _near(col, RED)
		s["cold"] += 0.6 * _near(col, BLUE)
		# Синие — «холодные»: жару переносят хуже всех (в зоне вентиляции, где красным нормально, гибнут).
		s["heat"] -= 0.5 * _near(col, BLUE)
		s["health"] += 0.2 * _near(col, ORANGE)
		s["stamina"] += 0.25 * _near(col, YELLOW)
		# Зелёные мало едят и дольше живут без еды.
		s["appetite"] -= 0.25 * _near(col, GREEN)
		s["fasting"] += 0.8 * _near(col, GREEN)
		s["intellect"] += 0.2 * _near(col, PURPLE)
		s["charm"] += 0.2 * _near(col, PINK)
	if has(g, "fur"):
		s["cold"] += 0.4
		s["heat"] -= 0.2
		s["health"] += 0.1
	if has(g, "hair"):
		s["cold"] += 0.1
		s["charm"] += 0.1
	if has(g, "glow"):
		s["stamina"] -= 0.15
		s["longevity"] -= 0.2
	if has(g, "gills"):
		s["heat"] -= 0.2
	if has(g, "shell"):
		s["health"] += 0.4
		s["speed"] -= 0.3
		s["longevity"] += 0.3
	if has(g, "horn"):
		s["strength"] += 0.1
		s["charm"] -= 0.3
	if has(g, "albino"):
		s["intellect"] += 0.4
		s["heat"] -= 0.4
		s["longevity"] -= 0.1
	if has(g, "melanist"):
		# Чёрный: греется на солнце и не мёрзнет, но перегревается; видит в темноте.
		s["cold"] += 0.5
		s["heat"] -= 0.3
		s["strength"] += 0.1
	match size_of(g):
		1:
			s["strength"] *= 1.5
			s["health"] += 0.3
			s["appetite"] *= 2.0
			s["speed"] -= 0.2
			s["longevity"] -= 0.1
		-1:
			s["strength"] *= 0.6
			s["agility"] += 0.2
			s["speed"] += 0.3
			s["appetite"] *= 0.6
			s["health"] -= 0.2
			s["longevity"] += 0.1
	match g.get("personality", ""):
		"трудоголик":
			s["stamina"] -= 0.1
		"лентяй":
			s["stamina"] += 0.2
		"обжора":
			s["appetite"] *= 1.5
		"весельчак":
			s["charm"] += 0.3
		"трус":
			s["charm"] -= 0.1
		"смельчак":
			s["health"] -= 0.1
	if eyes == 0:
		s["speed"] *= 0.35
	s["learning"] = 1.0 + (s["intellect"] - 1.0) * 0.5
	s["fertility"] = 1.0 + (s["charm"] - 1.0) * 0.3
	if is_super(g):
		for k in s:
			if k != "appetite":
				s[k] *= 2.0
	for k in s:
		s[k] = maxf(0.0, s[k])
	return s


## Насколько цвет похож на эталон (0..1): по оттенку и насыщенности.
static func _near(c: Color, ref: Color) -> float:
	var d := absf(c.ok_hsl_h - ref.ok_hsl_h)
	d = minf(d, 1.0 - d)
	return c.ok_hsl_s * maxf(0.0, 1.0 - d / 0.08)


## Особые умения: множители работы и флаги.
static func abilities(g: Dictionary) -> Dictionary:
	var a := {"work": 1.0, "dig": 1.0, "build": 1.0, "repair": 1.0, "deep_mining": 1.0,
		"light": false, "underwater": false, "collapse_proof": false, "sense": false,
		"night_vision": false, "flee_early": false, "brave": false}
	if eyes_of(g) == 0:
		# Без глаз — всё оооочень медленно, но руду в тёмных глубинах добывает лучше всех.
		a["work"] = 0.3
		a["deep_mining"] = 2.0
	if has(g, "long_arms"):
		a["build"] = 1.3
		a["dig"] = 0.85
	if has(g, "horn"):
		a["dig"] *= 1.25
	if has(g, "melanist"):
		a["deep_mining"] *= 1.3
	a["light"] = has(g, "glow")
	a["underwater"] = has(g, "gills")
	a["collapse_proof"] = has(g, "shell")
	a["sense"] = has(g, "antennae")
	a["night_vision"] = has(g, "melanist")
	match g.get("personality", ""):
		"трудоголик":
			a["work"] *= 1.2
		"лентяй":
			a["work"] *= 0.8
		"педант":
			a["repair"] = 1.3
		"трус":
			a["flee_early"] = true
		"смельчак":
			a["brave"] = true
	if is_super(g):
		for k in ["work", "dig", "build", "repair", "deep_mining"]:
			a[k] *= 2.0
	return a


## Особенности одной строкой для карточки.
static func ability_text(g: Dictionary) -> String:
	var a := abilities(g)
	var out: PackedStringArray = []
	if eyes_of(g) == 0:
		out.append("всё делает медленно, руда в глубине ×2")
	if a["light"]:
		out.append("освещает шахту")
	if a["underwater"]:
		out.append("дышит под водой")
	if a["collapse_proof"]:
		out.append("переживёт обвал")
	if a["sense"]:
		out.append("чует газ и руду")
	if a["night_vision"]:
		out.append("видит в темноте, руда ×1.3")
	if a["build"] > 1.0:
		out.append("строит и носит быстрее")
	if has(g, "horn"):
		out.append("копает быстрее")
	return ", ".join(out)


## «Мутант: 4 глаза (обычная)».
static func mutation_text(g: Dictionary) -> String:
	if not is_mutant(g):
		return ""
	var parts: PackedStringArray = []
	for m in g["mutations"]:
		match m:
			"eyes":
				var n := eyes_of(g)
				parts.append("%d %s" % [n, "глаз" if n >= 5 else "глаза"])
			"fingers":
				var f := fingers_of(g)
				parts.append("%d %s" % [f, "пальцев" if f >= 5 else "пальца"])
			"pattern":
				parts.append("полосы" if pattern_of(g) == 1 else "пятна")
			_:
				parts.append(MUTATION_NAMES.get(m, m))
	return "Мутант: %s (%s)" % [", ".join(parts), RARITY_NAMES[rarity(g)]]
