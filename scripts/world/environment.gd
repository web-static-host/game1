class_name Env
extends RefCounted
## Условия среды: температура, давление, кислород.
## Опирается на реальные значения: геотермический градиент ~25 °C/км,
## стандартная атмосфера (ISA), барометрическая формула.

## Среднегодовая температура у поверхности: такой же она держится и в неглубокой земле.
const SURFACE_TEMP := 9.0
const GEOTHERMAL_GRADIENT := 0.025 # °C на метр
const SEA_PRESSURE := 101.325 # кПа
const SCALE_HEIGHT := 8434.0 # м
const O2_FRACTION := 0.2095
const KARMAN_LINE := 100000 # м — условная граница космоса


## Сезонные колебания затухают с глубиной: на 4 м — втрое слабее, глубже 15 м их почти нет.
const SEASON_DEPTH := 4.0


## Температура породы/воздуха, °C. depth > 0 — под землёй, altitude — над уровнем моря.
## season — отклонение от среднегодовой температуры на поверхности (зима < 0 < лето).
static func temperature(y: int, surf: int, season := 0.0) -> float:
	var depth := y - surf
	if depth >= 0:
		return SURFACE_TEMP + depth * GEOTHERMAL_GRADIENT + season * exp(-depth / SEASON_DEPTH)
	return air_temperature(-y) + season


## Стандартная атмосфера по высоте над уровнем моря, °C.
static func air_temperature(h: float) -> float:
	if h < 11000.0:
		return SURFACE_TEMP - 0.0065 * h
	if h < 20000.0:
		return -56.5
	if h < 47000.0:
		return -56.5 + (h - 20000.0) * (54.0 / 27000.0)
	if h < 51000.0:
		return -2.5
	if h < 85000.0:
		return -2.5 - (h - 51000.0) * (83.5 / 34000.0)
	# Термосфера: газ разрежен, «температура» растёт, но тепла не передаёт.
	return -86.0 + minf((h - 85000.0) * 0.02, 1500.0)


## Давление воздуха, кПа. В шахте давление растёт (столб воздуха над нами).
static func pressure(y: int, surf: int) -> float:
	var depth := y - surf
	if depth >= 0:
		var surface_p := SEA_PRESSURE * exp(surf / SCALE_HEIGHT)
		return surface_p * exp(depth / SCALE_HEIGHT)
	return SEA_PRESSURE * exp(y / SCALE_HEIGHT)


## Парциальное давление кислорода, кПа (норма ~21; ниже 16 — гипоксия, ниже 10 — опасно).
static func oxygen(y: int, surf: int) -> float:
	return pressure(y, surf) * O2_FRACTION


## Доля кислорода относительно уровня моря, 0..1+.
static func oxygen_ratio(y: int, surf: int) -> float:
	return oxygen(y, surf) / (SEA_PRESSURE * O2_FRACTION)


static func air_zone(h: int) -> String:
	if h < 8000:
		return "Тропосфера"
	if h < 11000:
		return "Тропосфера («зона смерти»)"
	if h < 50000:
		return "Стратосфера"
	if h < 85000:
		return "Мезосфера"
	if h < KARMAN_LINE:
		return "Термосфера"
	return "Космос"


## Множитель времени работ из-за жары (люди и техника работают медленнее).
static func heat_work_factor(temp: float) -> float:
	return 1.0 + maxf(0.0, temp - 30.0) / 15.0
