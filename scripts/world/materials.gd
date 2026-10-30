class_name Mat
extends RefCounted
## Каталог природных материалов мира.
## Id материала хранится в PackedByteArray чанка, поэтому id < 256.

enum {
	AIR,
	TOPSOIL,
	CLAY,
	SAND,
	GRAVEL,
	SANDSTONE,
	SHALE,
	LIMESTONE,
	COAL,
	AQUIFER,
	GRANITE,
	GNEISS,
	BASALT,
	IRON_ORE,
	COPPER_ORE,
	SILVER_ORE,
	GOLD_ORE,
	URANIUM_ORE,
	KIMBERLITE,
	DIAMOND,
	ROCK_SALT,
	WATER,
	GAS_POCKET,
	OIL,
	MAGMA,
	PERIDOTITE,
	RUBBLE,
	COUNT,
}

## Опасность, которая проявляется, когда материал вскрыт.
enum Hazard { NONE, WATER, GAS, OIL, MAGMA }

# name, color, hardness (сек. копания базовой бригадой), density (кг/м³),
# strength (прочность на сжатие, МПа), resource, ore (рисовать вкрапления), hazard
const _RAW := [
	["Воздух", "00000000", 0.0, 1, 0.0, "", false, Hazard.NONE],
	["Почва", "5b3f2a", 2.0, 1500, 0.05, "soil", false, Hazard.NONE],
	["Глина", "9c6b4e", 4.0, 1800, 0.2, "clay", false, Hazard.NONE],
	["Песок", "d8bf84", 3.0, 1600, 0.0, "sand", false, Hazard.NONE],
	["Гравий", "8d8478", 4.0, 1800, 0.0, "gravel", false, Hazard.NONE],
	["Песчаник", "c49a6c", 14.0, 2300, 40.0, "stone", false, Hazard.NONE],
	["Глинистый сланец", "5e5f66", 12.0, 2400, 30.0, "stone", false, Hazard.NONE],
	["Известняк", "cfc6b0", 18.0, 2500, 60.0, "limestone", false, Hazard.NONE],
	["Каменный уголь", "26231f", 10.0, 1350, 20.0, "coal", true, Hazard.NONE],
	["Водоносный песок", "7c8f96", 5.0, 2000, 0.0, "sand", false, Hazard.WATER],
	["Гранит", "b09a92", 55.0, 2700, 200.0, "stone", false, Hazard.NONE],
	["Гнейс", "807a80", 60.0, 2750, 180.0, "stone", false, Hazard.NONE],
	["Базальт", "3c3d42", 70.0, 3000, 250.0, "stone", false, Hazard.NONE],
	["Железная руда", "b0532f", 40.0, 4500, 150.0, "iron_ore", true, Hazard.NONE],
	["Медная руда", "3fae92", 40.0, 4200, 120.0, "copper_ore", true, Hazard.NONE],
	["Серебряная руда", "d6dde6", 45.0, 4800, 120.0, "silver_ore", true, Hazard.NONE],
	["Золотоносная руда", "f2c93a", 50.0, 3000, 150.0, "gold_ore", true, Hazard.NONE],
	["Урановая руда", "86e04f", 55.0, 6000, 150.0, "uranium_ore", true, Hazard.NONE],
	["Кимберлит", "4b5a4f", 45.0, 2900, 100.0, "stone", false, Hazard.NONE],
	["Кимберлит с алмазами", "bff3ff", 50.0, 3000, 100.0, "diamond", true, Hazard.NONE],
	["Каменная соль", "e8dfe6", 10.0, 2200, 25.0, "salt", false, Hazard.NONE],
	["Подземная вода", "2f6fb5", 0.0, 1000, 0.0, "", false, Hazard.WATER],
	["Газовый карман", "8a9a5b", 12.0, 2300, 20.0, "stone", false, Hazard.GAS],
	["Нефтеносный пласт", "0d0c0e", 12.0, 2300, 30.0, "oil", true, Hazard.OIL],
	["Магма", "ff5a1f", 0.0, 2700, 0.0, "", false, Hazard.MAGMA],
	["Перидотит (мантия)", "5f7a4a", 90.0, 3300, 300.0, "stone", false, Hazard.NONE],
	["Обломки породы", "6f6862", 6.0, 1900, 0.0, "stone", false, Hazard.NONE],
]

## Сыпучие породы: осыпаются в пустоту под собой, пролёт не держат.
const LOOSE := [SAND, GRAVEL, AQUIFER, RUBBLE]
## Наибольший пролёт выработки без крепи у поверхности, м (с глубиной меньше).
const SPAN := {
	TOPSOIL: 3, CLAY: 3, SANDSTONE: 5, SHALE: 4, LIMESTONE: 6, COAL: 3,
	GRANITE: 10, GNEISS: 9, BASALT: 12, IRON_ORE: 6, COPPER_ORE: 6, SILVER_ORE: 6, GOLD_ORE: 6,
	URANIUM_ORE: 6, KIMBERLITE: 5, DIAMOND: 5, ROCK_SALT: 6, GAS_POCKET: 3, OIL: 4, PERIDOTITE: 12,
}

const RESOURCE_NAMES := {
	"wood": "Дерево",
	"food": "Грибы",
	"fish": "Рыба",
	"berries": "Ягоды",
	"soil": "Грунт",
	"clay": "Глина",
	"sand": "Песок",
	"gravel": "Гравий",
	"stone": "Камень",
	"limestone": "Известняк",
	"coal": "Уголь",
	"iron_ore": "Железная руда",
	"copper_ore": "Медная руда",
	"silver_ore": "Серебряная руда",
	"gold_ore": "Золотая руда",
	"uranium_ore": "Урановая руда",
	"iron": "Железо",
	"copper": "Медь",
	"silver": "Серебро",
	"gold": "Золото",
	"uranium": "Уран",
	"diamond": "Алмазы",
	"salt": "Соль",
	"oil": "Нефть",
	"brick": "Кирпич",
	"methane": "Метан",
	"diesel": "Дизельное топливо",
}

static var _names: PackedStringArray
static var _colors: PackedColorArray
static var _hardness: PackedFloat32Array
static var _density: PackedFloat32Array
static var _strength: PackedFloat32Array
static var _resources: PackedStringArray
static var _ore: Array[bool] = []
static var _hazard: PackedInt32Array


static func _ensure() -> void:
	if not _ore.is_empty():
		return
	for row in _RAW:
		_names.append(row[0])
		_colors.append(Color.html(row[1]))
		_hardness.append(row[2])
		_density.append(row[3])
		_strength.append(row[4])
		_resources.append(row[5])
		_ore.append(row[6])
		_hazard.append(row[7])
	assert(_names.size() == COUNT, "Каталог материалов не совпадает с enum")


static func name_of(id: int) -> String:
	_ensure()
	return _names[id]


static func color(id: int) -> Color:
	_ensure()
	return _colors[id]


static func hardness(id: int) -> float:
	_ensure()
	return _hardness[id]


static func density(id: int) -> float:
	_ensure()
	return _density[id]


static func strength(id: int) -> float:
	_ensure()
	return _strength[id]


static func resource(id: int) -> String:
	_ensure()
	return _resources[id]


static func is_ore(id: int) -> bool:
	_ensure()
	return _ore[id]


static func hazard(id: int) -> int:
	_ensure()
	return _hazard[id]


static func is_loose(id: int) -> bool:
	return LOOSE.has(id)


static func max_span(id: int) -> int:
	return SPAN.get(id, 0)


static func is_fluid(id: int) -> bool:
	return id == WATER or id == MAGMA


static func is_solid(id: int) -> bool:
	return id != AIR and not is_fluid(id)


## Можно ли выкопать клетку (жидкости и воздух — нельзя).
static func is_diggable(id: int) -> bool:
	return is_solid(id)


static func resource_name(key: String) -> String:
	return RESOURCE_NAMES.get(key, key)
