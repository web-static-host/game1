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


func _init(p_seed: int) -> void:
	world_seed = p_seed
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


func feature_at(x: int) -> int:
	var s := surface_y(x)
	if absi(surface_y(x - 1) - s) > 1 or absi(surface_y(x + 1) - s) > 1:
		return FEATURE_NONE
	var h := hash01(x, 7, world_seed + 11)
	if h < 0.12:
		return FEATURE_TREE
	if h < 0.17:
		return FEATURE_BOULDER
	return FEATURE_NONE


func tree_height(x: int) -> int:
	return 4 + int(hash01(x, 9, world_seed) * 4.0)


## Что даёт объект при сборе: [ключ ресурса, количество].
func feature_yield(x: int) -> Array:
	match feature_at(x):
		FEATURE_TREE:
			return ["wood", 3 + tree_height(x) / 2]
		FEATURE_BOULDER:
			return ["stone", 3 + int(hash01(x, 13, world_seed) * 4.0)]
	return ["", 0]


## Плавная вариация оттенка породы для отрисовки, 0..1.
func tint(x: int, y: int) -> float:
	return clampf(_n_tint.get_noise_2d(x, y) + 0.5, 0.0, 1.0)


## y первой твёрдой клетки в столбце x.
func surface_y(x: int) -> int:
	var h := _n_surface.get_noise_1d(x) * 45.0 + _n_hills.get_noise_1d(x) * 5.0
	return int(round(-h))


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
	return _n_kimberlite.get_noise_1d(x) > 0.62


func _water_table(x: int, surf: int) -> int:
	return surf + 30 + int(_n_water_table.get_noise_1d(x) * 20.0)


## Материал клетки (без учёта действий игрока).
func material_at(x: int, y: int) -> int:
	var surf := surface_y(x)
	return _cell(x, y, surf, _soil_depth(x), sed_base(x), _kimberlite_column(x), _water_table(x, surf))


func _soil_depth(x: int) -> int:
	return SOIL_MIN + int((_n_soil.get_noise_1d(x) + 1.0) * 1.5)


func _cell(x: int, y: int, surf: int, soil: int, sed: int, kimb: bool, water_table: int) -> int:
	var d := y - surf
	if d < 0:
		return Mat.AIR
	if d < soil:
		return Mat.TOPSOIL
	if d < SUBSOIL_BASE + soil * 2:
		var n := _n_sub.get_noise_2d(x, y * 2.0)
		if n < -0.15:
			return Mat.CLAY
		if n < 0.3:
			return Mat.SAND
		return Mat.GRAVEL
	if d > 12 and d < CAVE_MAX_DEPTH and _is_cave(x, y, d):
		# Полости ниже уровня грунтовых вод затоплены.
		if y > water_table and hash01(x >> 4, y >> 4, world_seed + 77) < 0.75:
			return Mat.WATER
		return Mat.AIR
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
		return Mat.DIAMOND if hash01(x, y, world_seed + 5) < 0.04 else Mat.KIMBERLITE

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
	if d < 220 and _n_aquifer.get_noise_2d(x * 0.1, wd) > 0.5:
		return Mat.AQUIFER
	if d > 150 and _n_salt.get_noise_2d(x * 0.3, wd * 0.6) > 0.6:
		return Mat.ROCK_SALT
	var band := _n_band.get_noise_2d(x * 0.08, wd)
	if band < -0.2:
		if d > 40 and _n_gas.get_noise_2d(x, y) > 0.62:
			return Mat.GAS_POCKET
		return Mat.SHALE
	if band < 0.18:
		if d > 200 and _n_gas.get_noise_2d(y, x) > 0.66:
			return Mat.OIL
		return Mat.SANDSTONE
	return Mat.LIMESTONE


## Рудные жилы: чем глубже, тем шире, чаще и ценнее.
func _ore(x: int, y: int, d: int) -> int:
	if d < 20:
		return Mat.AIR
	var richness := clampf(d / 3000.0, 0.0, 1.0)
	var w := 0.018 + 0.03 * richness
	if absf(_n_vein.get_noise_2d(x, y)) >= w:
		return Mat.AIR
	if _n_vein_region.get_noise_2d(x, y) < 0.15 - 0.45 * richness:
		return Mat.AIR
	var r := (_n_ore_type.get_noise_2d(x, y) + 1.0) * 0.5
	r = clampf(r + (hash01(x, y, world_seed + 3) - 0.5) * 0.1, 0.0, 0.999)
	var table: Array
	if d < 80:
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
		if y0 + SIZE <= surf:
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
