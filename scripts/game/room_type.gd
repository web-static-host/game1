class_name RoomType
extends RefCounted
## Назначения комнат. Оборудование стоит ресурсов, его ставят жители.

enum { NONE, HOME, STORAGE, FARM, DINING, PUMP, VENT, LAB, KILN, FORGE, GENERATOR, DEGAS, GRANARY, HEARTH }

const NAMES := ["Без назначения", "Жилая", "Склад", "Ферма", "Столовая", "Насосная", "Вентиляция",
	"Лаборатория", "Печь", "Кузница", "Генератор", "Дегазация", "Амбар", "Очаг"]
## Еда хранится в амбаре, всё остальное — на складе.
const FOOD_KEYS := ["food", "berries"]
const HINTS := [
	"",
	"кровати: место для сна и для детей",
	"хранит ресурсы (кроме еды — она в амбаре)",
	"грибные грядки: производство еды",
	"еда в столовой сытнее и поднимает настроение",
	"откачивает воду вокруг (16 м)",
	"охлаждает воздух вокруг (20 м)",
	"учёные открывают технологии",
	"обжиг: 2 глины + 1 дерево → 2 кирпича",
	"плавка: 2 железа + 1 уголь → 1 сталь",
	"энергия: сжигает метан, уголь или дрова",
	"собирает метан вокруг (20 м) — топливо для генератора",
	"хранит еду: рыбу, урожай ферм, ягоды",
	"отопление: печи (по одной на 3 м) жгут дрова и греют от стен на 6–10 м",
]
## Назначения, которые нужно сначала изучить.
const REQUIRES := {KILN: "bricks", FORGE: "metallurgy", GENERATOR: "electricity", HEARTH_BRICK: "bricks"}
## Вариант обустройства «очаг с кирпичными печами» (в выборе назначения и при улучшении);
## готовая комната — HEARTH с brick_stoves.
const HEARTH_BRICK := 100
## Кирпичные печи против каменных: дров в 1.5 раза меньше, тепло в 1.5 раза дальше,
## очаг изнашивается вдвое медленнее.
const BRICK_STOVE_GAIN := 1.5
## Мастерские: [сырьё, продукция, секунд работы на цикл].
const RECIPES := {
	KILN: [{"clay": 2, "wood": 1}, {"brick": 2}, 20.0],
	FORGE: [{"iron": 2, "coal": 1}, {"metal": 1}, 30.0],
}
## Сколько энергии берут потребители и даёт генератор (условные единицы).
const POWER_USE := {PUMP: 5, VENT: 5, LAB: 5, FARM: 5}
const POWER_MAKE := 20
## На сколько секунд хватает 1 метана, 1 угля или 2 дров.
const FUEL_TIME := 40.0
## Очаг: на сколько секунд хватает 1 дерева (≈ 15 дров за игровой месяц).
const HEARTH_FUEL_TIME := 40.0
## Пока складов нет, ресурсы лежат кучами на земле у базы — немного.
const BASE_CAPACITY := 50
## Прибавка вместимости за клетку ширины склада (для разрешённых в нём ресурсов).
const CAPACITY_PER_CELL := 40
## Пустая порода из шахт: ссыпается в отвал, места на складе не занимает.
const BULK := ["soil", "sand", "gravel"]
## Сколько секунд работы фермера даёт 1 еду.
const FARM_CYCLE := 12.0


## Ширина пола без колонны с лестницей.
static func usable_width(p: Project) -> int:
	return p.rect.size.x - (1 if p.ladder else 0)


static func floor_start(p: Project) -> int:
	return p.rect.position.x + (1 if p.ladder else 0)


## Печей в очаге: по одной на 3 м ширины комнаты (1–3).
static func stoves(p: Project) -> int:
	return clampi(p.rect.size.x / 3, 1, 3)


## Очаг греет от стен комнаты: полное тепло в пределах full клеток, дальше слабеет до reach.
## Больше печей — греет дальше. Генератор греет как одна печь.
static func heat_zone(p: Project) -> Vector2i:
	var n := stoves(p) if p.purpose == HEARTH else 1
	var z := Vector2i(2 + n, 4 + 2 * n)
	if p.purpose == HEARTH and p.brick_stoves:
		z = Vector2i(roundi(z.x * BRICK_STOVE_GAIN), roundi(z.y * BRICK_STOVE_GAIN))
	return z


## Назначение без варианта (кирпичный очаг — это очаг).
static func base_type(t: int) -> int:
	return HEARTH if t == HEARTH_BRICK else t


static func purpose_name(t: int) -> String:
	match t:
		HEARTH:
			return "Очаг (каменные печи)"
		HEARTH_BRICK:
			return "Очаг (кирпичные печи)"
	return NAMES[t]


static func purpose_hint(t: int) -> String:
	if t == HEARTH_BRICK:
		return "отопление: кирпичные печи — дров в 1,5 раза меньше, греют в 1,5 раза дальше, служат вдвое дольше"
	return HINTS[t]


static func beds(p: Project) -> int:
	return maxi(1, usable_width(p) / 2)


static func farm_slots(p: Project) -> int:
	return maxi(1, usable_width(p) / 2)


static func equip_cost(t: int, p: Project) -> Dictionary:
	var w := usable_width(p)
	match t:
		HOME:
			return {"wood": 3 * beds(p)}
		STORAGE:
			return {"wood": 2 * w}
		FARM:
			# Грядки из досок; грибы заводятся сами.
			return {"wood": 2 * w + 2}
		DINING:
			return {"wood": 2 * w, "stone": 4}
		PUMP:
			return {"wood": 6, "stone": 8}
		VENT:
			return {"wood": 8, "stone": 4}
		LAB:
			return {"wood": 10, "stone": 6}
		KILN:
			return {"stone": 12, "clay": 6}
		FORGE:
			return {"stone": 10, "brick": 8}
		GENERATOR:
			return {"stone": 6, "copper": 4, "iron": 4}
		DEGAS:
			return {"wood": 8, "stone": 8}
		GRANARY:
			return {"wood": 2 * w}
		HEARTH:
			# Каменные печи — из того, что есть с самого начала.
			return {"stone": 8 * stoves(p)}
		HEARTH_BRICK:
			return {"brick": 6 * stoves(p)}
	return {}


static func equip_work(t: int, p: Project) -> float:
	return 6.0 * usable_width(p) if t != NONE else 0.0


static func ladder_cost(p: Project) -> Dictionary:
	return {"wood": p.rect.size.y * 2}


static func ladder_work(p: Project) -> float:
	return p.rect.size.y * 8.0


## Стоимость и объём текущего обустройства (назначение или лестница).
static func job_cost(p: Project) -> Dictionary:
	return ladder_cost(p) if p.equip_ladder else equip_cost(p.equip_target, p)


static func job_work(p: Project) -> float:
	return ladder_work(p) if p.equip_ladder else equip_work(p.equip_target, p)


## Склад — для стройматериалов, амбар — для еды (без учёта галочек «что хранить»).
static func same_kind(p: Project, key: String) -> bool:
	return FOOD_KEYS.has(key) == (p.purpose == GRANARY)


static func stores(p: Project, key: String) -> bool:
	if p.purpose == GRANARY:
		return FOOD_KEYS.has(key)
	if FOOD_KEYS.has(key):
		return false
	return p.store_filter.is_empty() or p.store_filter.has(key)


## Склад или амбар.
static func is_store(t: int) -> bool:
	return t == STORAGE or t == GRANARY
