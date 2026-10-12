class_name RoomType
extends RefCounted
## Назначения комнат. Оборудование стоит ресурсов, его ставят жители.

enum { NONE, HOME, STORAGE, FARM, DINING }

const NAMES := ["Без назначения", "Жилая", "Склад", "Ферма", "Столовая"]
const HINTS := [
	"",
	"кровати: место для сна и для детей",
	"больше места для ресурсов",
	"грибные грядки: производство еды",
	"еда в столовой сытнее и поднимает настроение",
]
## Базовая вместимость склада на каждый ресурс и прибавка за клетку ширины склада.
const BASE_CAPACITY := 100
const CAPACITY_PER_CELL := 40
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
			return {"soil": 3 * w, "wood": 4}
		DINING:
			return {"wood": 2 * w, "stone": 4}
	return {}


static func equip_work(t: int, p: Project) -> float:
	return 6.0 * usable_width(p) if t != NONE else 0.0
