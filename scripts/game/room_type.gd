class_name RoomType
extends RefCounted
## Назначения комнат. Оборудование стоит ресурсов, его ставят жители.

enum { NONE, HOME, STORAGE, FARM, DINING, PUMP, VENT, LAB, KILN, FORGE, GENERATOR, DEGAS }

const NAMES := ["Без назначения", "Жилая", "Склад", "Ферма", "Столовая", "Насосная", "Вентиляция",
	"Лаборатория", "Печь", "Кузница", "Генератор", "Дегазация"]
const HINTS := [
	"",
	"кровати: место для сна и для детей",
	"больше места для ресурсов",
	"грибные грядки: производство еды",
	"еда в столовой сытнее и поднимает настроение",
	"откачивает воду вокруг (16 м)",
	"охлаждает воздух вокруг (20 м)",
	"учёные открывают технологии",
	"обжиг: 2 глины + 1 дерево → 2 кирпича",
	"плавка: 2 железа + 1 уголь → 1 сталь",
	"энергия: сжигает метан, уголь или дрова",
	"собирает метан вокруг (20 м) — топливо для генератора",
]
## Назначения, которые нужно сначала изучить.
const REQUIRES := {KILN: "bricks", FORGE: "metallurgy", GENERATOR: "electricity"}
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


static func stores(p: Project, key: String) -> bool:
	return p.store_filter.is_empty() or p.store_filter.has(key)
