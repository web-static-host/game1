class_name WorldGen
extends RefCounted
## Детерминированная генерация мира из seed.
## Любую клетку можно получить в любой момент — поэтому мир бесконечен,
## а в сохранение попадают только изменённые игроком чанки.
##
## Система координат: x вправо, y вниз, 1 клетка = 1 м, y = 0 — уровень моря.

const SIZE := ChunkData.SIZE

## Глубины (м) — ориентиры по реальной геологии континентальной коры.
const SOIL_MIN := 1
const SUBSOIL_BASE := 6
const SED_BASE := 250 # средняя граница осадочного чехла
const BASALT_START := 4000 # нижняя кора постепенно становится основной (базальт/габбро)
const BASALT_FULL := 15000
const MAGMA_START := 1500 # редкие магматические очаги
const MANTLE_DEPTH := 35000 # граница Мохоровичича
const CAVE_MAX_DEPTH := 10000 # глубже полости схлопываются под давлением

var world_seed: int
## Планета (Planet.DATA): Земля или другая — свои температура, воздух, недра.
var planet_id := "earth"
var planet: Dictionary = {}
## Версия генерации: старые сохранения продолжают на своей, чтобы мир не поменялся под ними.
## 2 — кусты в 3 раза реже, озёра в 1,5 раза чаще; 3 — деревьев вдвое больше;
## 4 — озёра ещё чаще и одно — недалеко от базы; 5 — серебро, золото и алмазы чаще
## (кимберлитовые трубки — примерно в 20–400 м от базы), но реже железа и меди;
## 6 — подземная вода в полостях ровная (уровень общий на участок, без «стенок»),
## на дне подземных вод часто золото.
const LATEST := 6
var version := LATEST
var _lake_segment := 400
var _bush_share := 0.08
var _tree_share := 0.12
var _lake_chance := 0.75
var _home_clear := 60
## Насколько ниже порог кимберлитовых трубок и какая доля алмазов в них (версия 5 — чаще).
var _kimb_shift := 0.0
var _diamond_share := 0.04

var _n_surface: FastNoiseLite
var _n_hills: FastNoiseLite
var _n_soil: FastNoiseLite
var _n_sub: FastNoiseLite
var _n_sed_base: FastNoiseLite
var _n_warp: FastNoiseLite
var _n_band: FastNoiseLite
var _n_coal: FastNoiseLite
var _n_aquifer: FastNoiseLite
var _n_salt: FastNoiseLite
var _n_gas: FastNoiseLite
var _n_crystal: FastNoiseLite
var _n_cave: FastNoiseLite
var _n_cave_region: FastNoiseLite
var _n_water_table: FastNoiseLite
var _n_vein: FastNoiseLite
var _n_vein_region: FastNoiseLite
var _n_ore_type: FastNoiseLite
var _n_kimberlite: FastNoiseLite
var _n_magma: FastNoiseLite
var _n_tint: FastNoiseLite


func _init(p_seed: int, p_version := LATEST, p_planet := "earth") -> void:
	world_seed = p_seed
	version = p_version
	planet_id = p_planet
	planet = Planet.data(p_planet)
	if version >= 2:
		_lake_segment = 267
		_bush_share = 0.08 / 3.0
	if version >= 3:
		_tree_share = 0.24
	if version >= 4:
		_lake_segment = 160
		_lake_chance = 0.85
		_home_clear = 30
	if version >= 5:
		_kimb_shift = 0.22
		_diamond_share = 0.08
	_n_surface = _noise(1, 0.0025, 4)
	_n_hills = _noise(2, 0.03, 2)
	_n_soil = _noise(3, 0.05, 1)
	_n_sub = _noise(4, 0.06, 2)
	_n_sed_base = _noise(5, 0.004, 2)
	_n_warp = _noise(6, 0.02, 2)
	_n_band = _noise(7, 0.03, 3)
	_n_coal = _noise(8, 0.05, 2)
	_n_aquifer = _noise(9, 0.03, 2)
	_n_salt = _noise(10, 0.02, 2)
	_n_gas = _noise(11, 0.06, 1)
	_n_crystal = _noise(12, 0.015, 3)
	_n_cave = _noise(13, 0.012, 2)
	_n_cave_region = _noise(14, 0.008, 1)
	_n_water_table = _noise(15, 0.01, 1)
	_n_vein = _noise(16, 0.011, 2)
	_n_vein_region = _noise(17, 0.01, 1)
	_n_ore_type = _noise(18, 0.006, 1)
	_n_kimberlite = _noise(19, 0.02, 1)
	_n_magma = _noise(20, 0.012, 2)
	_n_tint = _noise(21, 0.07, 2)


func _noise(offset: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = (world_seed * 31 + offset * 7919) & 0x7FFFFFFF
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


## Быстрый детерминированный хэш клетки → [0, 1).
static func hash01(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0


## Объекты на поверхности (стоят на клетке над землёй).
const FEATURE_NONE := 0
const FEATURE_TREE := 1
const FEATURE_BOULDER := 2
const FEATURE_BUSH := 3


func feature_at(x: int) -> int:
	if not planet["plants"]:
		# На других планетах ни деревьев, ни кустов, ни валунов на поверхности.
		return FEATURE_NONE
	var s := surface_y(x)
	if absi(surface_y(x - 1) - s) > 1 or absi(surface_y(x + 1) - s) > 1:
		return FEATURE_NONE
	if water_level(x) < s:
		return FEATURE_NONE
	var h := hash01(x, 7, world_seed + 11)
	if h < _tree_share:
		return FEATURE_TREE
	if h < _tree_share + 0.05:
		return FEATURE_BOULDER
	if h < _tree_share + 0.05 + _bush_share:
		return FEATURE_BUSH
	return FEATURE_NONE


func tree_height(x: int) -> int:
	return 4 + int(hash01(x, 9, world_seed) * 4.0)


## Что даёт объект при сборе: [ключ ресурса, количество].
func feature_yield(x: int) -> Array:
	return kind_yield(feature_at(x), x)


## Что даёт объект вида kind в столбце x (и выросший позже из саженца).
func kind_yield(kind: int, x: int) -> Array:
	match kind:
		FEATURE_TREE:
			return ["wood", 3 + tree_height(x) / 2]
		FEATURE_BOULDER:
			return ["stone", 3 + int(hash01(x, 13, world_seed) * 4.0)]
		FEATURE_BUSH:
			return ["berries", 6]
	return ["", 0]


## Плавная вариация оттенка породы для отрисовки, 0..1.
func tint(x: int, y: int) -> float:
	return clampf(_n_tint.get_noise_2d(x, y) + 0.5, 0.0, 1.0)


## y первой твёрдой клетки в столбце x.
func _base_surface(x: int) -> int:
	var h := _n_surface.get_noise_1d(x) * 45.0 + _n_hills.get_noise_1d(x) * 5.0
	return int(round(-h))


## Уровень земли в столбце x без озёр (у озера — уровень воды).
func land_y(x: int) -> int:
	return _base_surface(x)


## y первой твёрдой клетки в столбце x (у озера — его дно).
func surface_y(x: int) -> int:
	var b := _base_surface(x)
	var l := lake_at(x)
	if l.is_empty():
		return b
	var t := float(x - int(l["cx"])) / float(l["w"])
	return b + int(round(float(l["depth"]) * (1.0 - t * t)))


# --- Водоёмы --------------------------------------------------------------------

## Мир разбит на отрезки; в отрезке может быть одно озеро: лужа, пруд или огромное.
const LAKE_SEGMENT := 400
## Возле стартовой базы озёр нет, чтобы не отрезать её водой.
const LAKE_HOME_CLEAR := 60
var _lakes := {}


func _lake_of_segment(k: int) -> Dictionary:
	if not planet["lakes"]:
		return {}
	if _lakes.has(k):
		return _lakes[k]
	var d := {}
	var s := world_seed + 31
	if version >= 4 and k == 0:
		# Пруд недалеко от базы — чтобы было где рыбачить с самого начала.
		var hw := 6 + int(hash01(k, 3, s) * 6.0)
		var hcx := 50 + int(hash01(k, 5, s) * 15.0)
		var hlevel := maxi(_base_surface(hcx - hw), _base_surface(hcx + hw))
		d = {"id": k, "cx": hcx, "w": hw, "depth": 2 + int(hash01(k, 4, s) * 3.0), "level": hlevel}
		_lakes[k] = d
		return d
	if hash01(k, 1, s) < _lake_chance:
		var r := hash01(k, 2, s)
		var w: int
		var depth: int
		if r < 0.55:
			w = 4 + int(hash01(k, 3, s) * 8.0)
			depth = 2 + int(hash01(k, 4, s) * 3.0)
		elif r < 0.88:
			w = 15 + int(hash01(k, 3, s) * 25.0)
			depth = 4 + int(hash01(k, 4, s) * 6.0)
		else:
			w = 60 + int(hash01(k, 3, s) * 90.0)
			depth = 10 + int(hash01(k, 4, s) * 20.0)
		var cx := k * _lake_segment + int(hash01(k, 5, s) * _lake_segment)
		if absi(cx) - w > _home_clear:
			var level := maxi(_base_surface(cx - w), _base_surface(cx + w))
			d = {"id": k, "cx": cx, "w": w, "depth": depth, "level": level}
	_lakes[k] = d
	return d


## Озеро, которому принадлежит столбец x (или пустой словарь).
func lake_at(x: int) -> Dictionary:
	var k := floori(float(x) / _lake_segment)
	for kk in [k, k - 1, k + 1]:
		var d := _lake_of_segment(kk)
		if not d.is_empty() and absi(x - int(d["cx"])) < int(d["w"]):
			return d
	return {}


## Столбцы с водой у озера: [первый, последний] (кэшируется).
func lake_water_span(l: Dictionary) -> Vector2i:
	if l.has("a"):
		return Vector2i(int(l["a"]), int(l["b"]))
	var level: int = l["level"]
	var a := 1 << 30
	var b := -(1 << 30)
	for x in range(int(l["cx"]) - int(l["w"]), int(l["cx"]) + int(l["w"]) + 1):
		if surface_y(x) > level:
			a = mini(a, x)
			b = maxi(b, x)
	l["a"] = a
	l["b"] = b
	return Vector2i(a, b)


func lake_segment() -> int:
	return _lake_segment


## y верхней клетки воды в столбце (вода — от неё до дна), иначе очень большое число.
func water_level(x: int) -> int:
	var l := lake_at(x)
	return int(l["level"]) if not l.is_empty() else (1 << 30)


## Сглаженная линия поверхности (для отрисовки): ломаная через центры столбцов.
## fx — координата в клетках (дробная), результат — y верха земли в клетках.
func surface_smooth(fx: float) -> float:
	var c := fx - 0.5
	var i := floori(c)
	return lerpf(surface_y(i), surface_y(i + 1), c - i)


## Глубина (м) нижней границы осадочного чехла в столбце x.
func sed_base(x: int) -> int:
	return SED_BASE + int(_n_sed_base.get_noise_1d(x) * 160.0)


func _kimberlite_column(x: int) -> bool:
	return _n_kimberlite.get_noise_1d(x) > float(planet["kimberlite"]) - _kimb_shift


## Температура клетки, °C: на Земле — по Env (времена года, высота); на других планетах
## холод или жар поверхности за несколько метров сменяется температурой недр.
func temperature(y: int, surf: int, season := 0.0) -> float:
	if planet_id == "earth":
		return Env.temperature(y, surf, season)
	var depth := y - surf
	if depth < 0:
		return planet["surf"]
	var t: float = planet["under"] + (float(planet["surf"]) - float(planet["under"])) * exp(-depth / Planet.SKIN)
	return t + depth * Env.GEOTHERMAL_GRADIENT


## Чем дышать (1 — как на Земле у моря). На безвоздушной планете под землёй держится
## воздух корабля, а на поверхности дышать нечем.
func oxygen_ratio(y: int, surf: int) -> float:
	if planet["air"]:
		return Env.oxygen_ratio(y, surf)
	return 1.0 if y >= surf else 0.0


## На поверхности этой планеты не выжить (нет воздуха).
func airless() -> bool:
	return not planet["air"]


func _water_table(x: int, surf: int) -> int:
	if version >= 6:
		# Ровный уровень на участок в WATER_SEG м: вода в пещере не стоит наклонно.
		var xc := (x >> WATER_SEG_SHIFT << WATER_SEG_SHIFT) + (1 << WATER_SEG_SHIFT >> 1)
		return surface_y(xc) + 30 + int(_n_water_table.get_noise_1d(xc) * 20.0)
	return surf + 30 + int(_n_water_table.get_noise_1d(x) * 20.0)


## Ширина участка с общим уровнем подземных вод: 2^6 = 64 м.
const WATER_SEG_SHIFT := 6
## Доля клеток породы на дне подземных вод, где лежит золото.
const GOLD_UNDER_WATER := 0.4


## Затоплена ли полость в клетке (версия 6: всё ниже уровня грунтовых вод).
func _flooded_cave(x: int, y: int, surf: int, water_table: int) -> bool:
	var d := y - surf
	return planet["lakes"] and y > water_table and d > 12 and d < CAVE_MAX_DEPTH and _is_cave(x, y, d)


## Материал клетки (без учёта действий игрока).
func material_at(x: int, y: int) -> int:
	var surf := surface_y(x)
	if y < surf:
		return Mat.WATER if y >= water_level(x) else Mat.AIR
	return _cell(x, y, surf, _soil_depth(x), sed_base(x), _kimberlite_column(x), _water_table(x, surf))


func _soil_depth(x: int) -> int:
	return SOIL_MIN + int((_n_soil.get_noise_1d(x) + 1.0) * 1.5)


func _cell(x: int, y: int, surf: int, soil: int, sed: int, kimb: bool, water_table: int) -> int:
	var d := y - surf
	if d < 0:
		return Mat.AIR
	if d < 4 and water_level(x) < surf:
		# Дно озера — в основном песок, местами глина.
		return Mat.SAND if hash01(x, y, world_seed + 8) < 0.8 else Mat.CLAY
	if d < soil:
		# Без растений почвы нет — сверху песок и щебень (реголит).
		return Mat.TOPSOIL if planet["plants"] else (Mat.SAND if hash01(x, y, world_seed + 3) < 0.6 else Mat.GRAVEL)
	if d < SUBSOIL_BASE + soil * 2:
		var n := _n_sub.get_noise_2d(x, y * 2.0)
		if n < -0.15:
			return Mat.CLAY
		if n < 0.3:
			return Mat.SAND
		return Mat.GRAVEL
	if d > 12 and d < CAVE_MAX_DEPTH and _is_cave(x, y, d):
		# Полости ниже уровня грунтовых вод затоплены.
		if version >= 6:
			return Mat.WATER if planet["lakes"] and y > water_table else Mat.AIR
		if planet["lakes"] and y > water_table and hash01(x >> 4, y >> 4, world_seed + 77) < 0.75:
			return Mat.WATER
		return Mat.AIR
	# Дно подземных вод: вода веками намывала золото — прямо под водой.
	if version >= 6 and y > water_table + 1 and hash01(x, y, world_seed + 91) < GOLD_UNDER_WATER \
			and _flooded_cave(x, y - 1, surf, water_table):
		return Mat.GOLD_ORE
	return _rock(x, y, d, sed, kimb)


func _is_cave(x: int, y: int, d: int) -> bool:
	var region := _n_cave_region.get_noise_2d(x, y)
	if region < 0.08:
		return false
	var w := 0.045 if d < 3000 else 0.025
	return absf(_n_cave.get_noise_2d(x, y * 1.4)) < w * minf(1.0, (region - 0.08) * 6.0)


func _rock(x: int, y: int, d: int, sed: int, kimb: bool) -> int:
	var wd := d + _n_warp.get_noise_2d(x, y) * (6.0 + d * 0.01)

	if d > MANTLE_DEPTH + _n_warp.get_noise_1d(x) * 800.0:
		if _is_magma(x, y, d):
			return Mat.MAGMA
		return Mat.PERIDOTITE

	if kimb and d > 120:
		# На Уране алмазные дожди: в трубках алмазов куда больше.
		var share := _diamond_share if float(planet["kimberlite"]) >= 0.5 else 0.3
		return Mat.DIAMOND if hash01(x, y, world_seed + 5) < share else Mat.KIMBERLITE

	var ore := _ore(x, y, d)
	if ore != Mat.AIR:
		return ore

	if wd < sed:
		return _sedimentary(x, y, d, wd)

	if d >= MAGMA_START and _is_magma(x, y, d):
		return Mat.MAGMA
	var t := clampf(float(d - BASALT_START) / float(BASALT_FULL - BASALT_START), 0.0, 1.0)
	if t > 0.0 and hash01(x >> 3, y >> 3, world_seed + 9) < t:
		return Mat.BASALT
	return Mat.GNEISS if _n_crystal.get_noise_2d(x, y) > 0.2 else Mat.GRANITE


func _sedimentary(x: int, y: int, d: int, wd: float) -> int:
	# Слоистость: шум сильно растянут по горизонтали → пласты.
	if d > 15 and absf(_n_coal.get_noise_2d(x * 0.05, wd)) < 0.035:
		return Mat.COAL
	# Водоносного песка больше нет (убран из игры): на его месте — обычные пласты.
	if d > 150 and _n_salt.get_noise_2d(x * 0.3, wd * 0.6) > 0.6:
		return Mat.ROCK_SALT
	var band := _n_band.get_noise_2d(x * 0.08, wd)
	if band < -0.2:
		if d > 40 and _n_gas.get_noise_2d(x, y) > float(planet["gas"]):
			return Mat.GAS_POCKET
		return Mat.SHALE
	if band < 0.18:
		if d > int(planet["oil_depth"]) and _n_gas.get_noise_2d(y, x) > float(planet["oil"]):
			return Mat.OIL
		return Mat.SANDSTONE
	return Mat.LIMESTONE


## Рудные жилы: чем глубже, тем шире, чаще и ценнее.
func _ore(x: int, y: int, d: int) -> int:
	if d < 20:
		return Mat.AIR
	var richness := clampf(d / 3000.0, 0.0, 1.0)
	var w := (0.018 + 0.03 * richness) * float(planet["ore"])
	if absf(_n_vein.get_noise_2d(x, y)) >= w:
		return Mat.AIR
	if _n_vein_region.get_noise_2d(x, y) < 0.15 - 0.45 * richness:
		return Mat.AIR
	var r := (_n_ore_type.get_noise_2d(x, y) + 1.0) * 0.5
	r = clampf(r + (hash01(x, y, world_seed + 3) - 0.5) * 0.1, 0.0, 0.999)
	# Аметист — только на Меркурии, Венере и Марсе, очень редко: глубже 150 м, участками
	# рудных жил (кусками 4×4 — одна из ~25).
	var xen := float(planet.get("amethyst", 0.0))
	if xen > 0.0 and d > 150 and hash01(x >> 2, y >> 2, world_seed + 57) < xen:
		return Mat.AMETHYST
	var table: Array = planet["ores"]
	if table.is_empty() and version >= 5:
		return _ore_v5(x, y, d, r)
	if not table.is_empty():
		pass
	elif d < 80:
		table = [[0.8, Mat.IRON_ORE], [1.0, Mat.COPPER_ORE]]
	elif d < 300:
		table = [[0.5, Mat.IRON_ORE], [0.85, Mat.COPPER_ORE], [0.95, Mat.SILVER_ORE], [1.0, Mat.GOLD_ORE]]
	elif d < 1000:
		table = [[0.35, Mat.IRON_ORE], [0.65, Mat.COPPER_ORE], [0.8, Mat.SILVER_ORE], [0.92, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]]
	else:
		table = [[0.25, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.65, Mat.SILVER_ORE], [0.83, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]]
	for entry in table:
		if r < entry[0]:
			return entry[1]
	return Mat.IRON_ORE


## Версия 5: редкие металлы — участками жилы по 8×8 м с заданной долей (шум типа руды
## почти не доходит до краёв, и золото раньше почти не встречалось). Остальное — железо и медь.
func _ore_v5(x: int, y: int, d: int, r: float) -> int:
	var h := hash01(x >> 3, y >> 3, world_seed + 31)
	var rare: Array
	if d < 80:
		rare = [[0.04, Mat.SILVER_ORE]]
	elif d < 300:
		rare = [[0.08, Mat.GOLD_ORE], [0.2, Mat.SILVER_ORE]]
	elif d < 1000:
		rare = [[0.08, Mat.URANIUM_ORE], [0.19, Mat.GOLD_ORE], [0.33, Mat.SILVER_ORE]]
	else:
		rare = [[0.12, Mat.URANIUM_ORE], [0.25, Mat.GOLD_ORE], [0.4, Mat.SILVER_ORE]]
	for e in rare:
		if h < e[0]:
			return e[1]
	return Mat.IRON_ORE if r < (0.78 if d < 80 else 0.55) else Mat.COPPER_ORE


func _is_magma(x: int, y: int, d: int) -> bool:
	var t := clampf(float(d - MAGMA_START) / float(MANTLE_DEPTH - MAGMA_START), 0.0, 1.0)
	var threshold := lerpf(0.78, 0.35, t)
	return _n_magma.get_noise_2d(x, y) > threshold


## Название геологической/атмосферной зоны для клетки.
func zone_name(x: int, y: int) -> String:
	var surf := surface_y(x)
	var d := y - surf
	if d < 0:
		return Env.air_zone(-y)
	if d < _soil_depth(x):
		return "Почвенный слой"
	if d < SUBSOIL_BASE + 6:
		return "Рыхлые отложения"
	if d < sed_base(x):
		return "Осадочный чехол"
	if d < BASALT_START:
		return "Верхняя кора (гранит)"
	if d < MANTLE_DEPTH:
		return "Нижняя кора (базальт)"
	return "Верхняя мантия"


## Заполняет чанк. Флаги видимости: игрок видит небо и поверхность земли.
func generate_chunk(cx: int, cy: int) -> ChunkData:
	var c := ChunkData.new(cx, cy)
	var x0 := cx * SIZE
	var y0 := cy * SIZE
	var mat := c.mat
	var flags := c.flags
	for lx in SIZE:
		var x := x0 + lx
		var surf := surface_y(x)
		var surf_l := surface_y(x - 1)
		var surf_r := surface_y(x + 1)
		var wl := water_level(x)
		if y0 + SIZE <= surf and y0 + SIZE <= wl:
			# Весь столбец — открытое небо.
			for ly in SIZE:
				flags[ChunkData.idx(lx, ly)] = ChunkData.F_REVEALED
			continue
		var soil := _soil_depth(x)
		var sed := sed_base(x)
		var kimb := _kimberlite_column(x)
		var wt := _water_table(x, surf)
		for ly in SIZE:
			var y := y0 + ly
			var i := ChunkData.idx(lx, ly)
			if y < surf:
				flags[i] = ChunkData.F_REVEALED
				if y >= wl:
					mat[i] = Mat.WATER
				continue
			var m := _cell(x, y, surf, soil, sed, kimb, wt)
			mat[i] = m
			var f := 0
			if m == Mat.AIR or m == Mat.WATER:
				f = ChunkData.F_CAVE
			# Поверхность земли (в т.ч. склоны) видна сразу.
			if y == surf or y < surf_l or y < surf_r:
				f |= ChunkData.F_REVEALED
			flags[i] = f
	return c
