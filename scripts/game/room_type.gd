class_name RoomType
extends RefCounted
## Назначения комнат. Оборудование стоит ресурсов, его ставят гаврики.

enum { NONE, HOME, STORAGE, FARM, DINING, PUMP, VENT, LAB, KILN, FORGE, GENERATOR, DEGAS, GRANARY, HEARTH, GAS_GEN,
	OIL_PUMP, OIL_TANK, REFINERY, DIESEL_GEN, SHIP, LAUNCHPAD, ENRICHMENT }

const NAMES := ["Без назначения", "Жилая", "Склад", "Ферма", "Столовая", "Насосная", "Вентиляция",
	"Лаборатория", "Печь", "Кузница", "Генератор", "Дегазация", "Амбар", "Очаг", "Газовый генератор",
	"Нефтекачалка", "Нефтехранилище", "Нефтезавод", "Дизельный генератор",
	"Корабль", "Космодром", "Обогатительная фабрика"]
## Еда хранится в амбаре, всё остальное — на складе.
## Еда: грибы с фермы ("food" — ключ с тех пор, как еда была одна), рыба и ягоды.
const FOOD_KEYS := ["food", "fish", "berries"]
const HINTS := [
	"",
	"кровати: место для сна и для детей",
	"хранит ресурсы (кроме еды — она в амбаре)",
	"грибные грядки: производство еды",
	"еда в столовой сытнее и поднимает настроение",
	"откачивает воду вокруг (10, 20 или 40 м — чем больше комната, тем дальше)",
	"охлаждает воздух вокруг (20 м)",
	"учёные открывают технологии",
	"обжиг: 2 глины + топливо (1 дерево или ½ угля) → 2 кирпича",
	"плавка: 1 руда → 2 металла (железо, медь, серебро, золото; уран — только на обогатительной фабрике)",
	"энергия: сжигает уголь или дрова",
	"собирает метан вокруг (10, 20 или 40 м — чем больше комната, тем дальше) в свой бак — топливо для газового генератора",
	"хранит еду: рыбу, урожай ферм, ягоды",
	"отопление: печи (по одной на 3 м) жгут дрова (кирпичные — и уголь) и греют от стен на 6–10 м",
	"энергия: сжигает метан из баков дегазации",
	"тянет нефть из пластов вокруг (10, 20 или 40 м — по размеру комнаты) по трубам в нефтехранилище; нужна энергия",
	"хранит нефть и дизельное топливо (только здесь, по трубам); если рухнет — взрыв вокруг",
	"мастер перегоняет нефть в дизельное топливо: 2 нефти → 1 дизель (по трубам из хранилища и обратно)",
	"энергия: сжигает дизельное топливо — мощнее и вдвое дольше на единице",
	"приземлившийся корабль: жильё на 10 человек, воздух, тепло, свет и трюм с грузом",
	"стартовый стол на поверхности: здесь собирают ракету и отправляют экспедицию на другую планету",
	"обогащение урана: 1 урановая руда → 2 урана; нужна энергия. Уран радиоактивен: кто с ним работает, живёт на 10% меньше, а его дети — всегда мутанты",
]
## Взрываются при обрушении (бак газа; потом — хранилище нефти).
const EXPLOSIVE := [DEGAS, OIL_TANK]
## Назначения, которые нужно сначала изучить.
const REQUIRES := {KILN: "pottery", FORGE: "smelting", GENERATOR: "electricity", GAS_GEN: "chemistry", OIL_PUMP: "oil_drilling", OIL_TANK: "oil_drilling",
	REFINERY: "refining", DIESEL_GEN: "combustion", LAUNCHPAD: "rocketry", ENRICHMENT: "nuclear", SHIP: "_ship", HEARTH_BRICK: "pottery", HEARTH_GAS: "gas_heating"}
## Вариант обустройства «очаг с кирпичными печами» (в выборе назначения и при улучшении);
## готовая комната — HEARTH с brick_stoves.
const HEARTH_BRICK := 100
## Улучшение очага: кирпичные газовые котлы над печами (готовая комната — HEARTH с gas_boiler).
## Только котёл жжёт метан; без метана печи под ним топят углём и дровами.
const HEARTH_GAS := 101
## Кирпичные печи против каменных: дров в 1.5 раза меньше, тепло в 1.5 раза дальше,
## очаг изнашивается вдвое медленнее.
const BRICK_STOVE_GAIN := 1.5
## Мастерские, которым нужно топливо: 1 на цикл обжига (уголь или дрова).
const FUELED := [KILN]
## Топливо: на сколько «поленьев» хватает единицы. Уголь горит вдвое дольше и идёт первым.
const FUEL_VALUE := {"methane": 3.0, "coal": 2.0, "wood": 1.0}
## Мастерские: [сырьё, продукция, секунд работы на цикл].
const RECIPES := {
	KILN: [{"clay": 2}, {"brick": 2}, 20.0],
	FORGE: [{"iron_ore": 1}, {"iron": 3}, 20.0],
	REFINERY: [{"oil": 2}, {"diesel": 1}, 20.0],
	ENRICHMENT: [{"uranium_ore": 1}, {"uranium": 2}, 40.0],
}
## Кузница: из любой руды (кроме урановой) — 3 единицы готового металла.
## Что плавить, решают нормы в карточке кузницы: держать столько-то каждого металла.
const FORGE_RECIPES := {
	"iron": [{"iron_ore": 1}, {"iron": 2}, 20.0],
	"copper": [{"copper_ore": 1}, {"copper": 2}, 20.0],
	"silver": [{"silver_ore": 1}, {"silver": 2}, 25.0],
	"gold": [{"gold_ore": 1}, {"gold": 2}, 25.0],
}
## Нормы кузницы по умолчанию.
const FORGE_TARGETS := {"iron": 40, "copper": 20, "silver": 0, "gold": 0}
## Радиоактивное: кто копает, носит или обогащает — облучается.
const RADIOACTIVE := ["uranium_ore", "uranium"]
const ORES := ["iron_ore", "copper_ore", "silver_ore", "gold_ore", "uranium_ore"]

## Генераторы: на дровах и угле или на метане.
const GENERATORS := [GENERATOR, GAS_GEN, DIESEL_GEN]
## Корабль: сколько в нём спальных мест, сколько каждого груза держит трюм, сколько энергии
## даёт его реактор (воздух, тепло и свет внутри — всегда).
const SHIP_BEDS := 10
const SHIP_HOLD := 200
const SHIP_POWER := 20
## Ракета: материалы на сборку (топливо — по трубам из баков) и время сборки.
const ROCKET_COST := {
	"chem": {"iron": 110, "copper": 40, "gold": 10, "silver": 10, "diamond": 4, "diesel": 60},
	"nuclear": {"iron": 150, "copper": 50, "gold": 20, "silver": 20, "diamond": 8, "uranium": 20, "amethyst": 12},
}
const ROCKET_WORK := 600.0
## Жидкое и газ: хранятся только в баках (метан — в дегазации, нефть и дизель — в
## нефтехранилище) и идут по трубам — их не носят.
const PIPED := ["methane", "oil", "diesel"]
## Нефтехранилище: сколько нефти (и отдельно дизеля) держит на метр ширины.
const OIL_PER_CELL := 40
## Сколько энергии берут потребители и даёт генератор (условные единицы).
const POWER_USE := {PUMP: 5, VENT: 5, LAB: 5, FARM: 5, OIL_PUMP: 10, REFINERY: 10, ENRICHMENT: 10}
const POWER_MAKE := 20
## На сколько секунд хватает 1 метана, 1 угля или 2 дров.
const FUEL_TIME := 40.0
## Очаг: на сколько секунд хватает 1 дерева (≈ 15 дров за игровой месяц).
const HEARTH_FUEL_TIME := 40.0
## Пока складов нет, ресурсы лежат кучами на земле у базы — немного.
const BASE_CAPACITY := 50
## Прибавка вместимости за клетку ширины склада (для разрешённых в нём ресурсов).
const CAPACITY_PER_CELL := 40
## Бак дегазации: сколько метана держит на метр ширины комнаты (газ хранят только там).
const GAS_PER_CELL := 40
## Пустая порода и ненужное (известняк, соль): не копится и не хранится — просто исчезает.
const BULK := ["soil", "sand", "gravel", "limestone", "salt"]
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
## Больше печей — греет дальше. Генератор (любой) греет как одна печь.
## insulated — изучена «Теплоизоляция»: очаг греет вдвое дальше.
static func heat_zone(p: Project, insulated := false) -> Vector2i:
	if p.purpose == SHIP:
		return Vector2i(3, 6)
	var n := stoves(p) if p.purpose == HEARTH else 1
	var z := Vector2i(2 + n, 4 + 2 * n)
	if p.purpose == HEARTH and p.brick_stoves:
		z = Vector2i(roundi(z.x * BRICK_STOVE_GAIN), roundi(z.y * BRICK_STOVE_GAIN))
	# Котёл на газу жарче.
	if p.purpose == HEARTH and p.gas_boiler and p.on_gas:
		z += Vector2i(1, 2)
	if insulated and p.purpose == HEARTH:
		z *= 2
	return z


## Сколько «блоков» по 3 м в комнате: столько в ней лампочек (и единиц энергии на свет).
static func blocks(p: Project) -> int:
	return maxi(1, ceili(p.rect.size.x / 3.0))


## Радиус действия комнаты в клетках от её центра (0 — нет): насос, вентиляция, дегазация
## (у насоса, дегазации и нефтекачалки — по размеру: 3 м — 10, 6 м — 20, 9 м — 40).
static func effect_radius(p: Project) -> int:
	match p.purpose:
		VENT:
			return 20
		PUMP, DEGAS, OIL_PUMP:
			# 3 м — 10, 6 м — 20, 9 м — 40.
			return [10, 20, 40][clampi(blocks(p), 1, 3) - 1]
	return 0


## Назначение без варианта (кирпичный очаг — это очаг).
static func base_type(t: int) -> int:
	return HEARTH if t == HEARTH_BRICK or t == HEARTH_GAS else t


## Как обустроена комната сейчас (для очага — с вариантом печей).
static func current_purpose(p: Project) -> int:
	if p.purpose == HEARTH and p.gas_boiler:
		return HEARTH_GAS
	if p.purpose == HEARTH and p.brick_stoves:
		return HEARTH_BRICK
	return p.purpose


static func purpose_name(t: int) -> String:
	match t:
		HEARTH:
			return "Очаг (каменные печи)"
		HEARTH_BRICK:
			return "Очаг (кирпичные печи)"
		HEARTH_GAS:
			return "Очаг (газовые котлы)"
	return NAMES[t]


static func purpose_hint(t: int) -> String:
	if t == HEARTH_GAS:
		return "кирпичные котлы над печами жгут метан от дегазации (1 метан — как 3 дерева) и греют на 1–2 м дальше; без метана печи топят углём и дровами"
	if t == HEARTH_BRICK:
		return "отопление: кирпичные печи — дров в 1,5 раза меньше, греют в 1,5 раза дальше, служат вдвое дольше, топятся и углём"
	return HINTS[t]


static func beds(p: Project) -> int:
	if p.purpose == SHIP:
		return SHIP_BEDS
	# Золотая спальня — просторная: кроватей вдвое больше.
	return maxi(1, roundi(usable_width(p) / 2 * p.bonus()))


static func farm_slots(p: Project) -> int:
	return maxi(1, usable_width(p) / 2)


## Какой супер-материал подходит назначению — только из него комната работает лучше:
## серебро — электрика (генераторы, лаборатория, насос, вентиляция, дегазация, нефтекачалка),
## золото — жильё, еда и хранение, алмаз — резка и обработка.
const SUPER_MAT := {
	GENERATOR: "silver", GAS_GEN: "silver", DIESEL_GEN: "silver", LAB: "silver", PUMP: "silver",
	VENT: "silver", DEGAS: "silver", OIL_PUMP: "silver",
	HOME: "gold", DINING: "gold", FARM: "gold", STORAGE: "gold", GRANARY: "gold", OIL_TANK: "gold", LAUNCHPAD: "gold",
	FORGE: "diamond", KILN: "diamond", REFINERY: "diamond", ENRICHMENT: "diamond",
}
## Что даёт супер-материал назначению (для описаний).
const SUPER_EFFECT := {
	GENERATOR: "энергии ×%s", GAS_GEN: "энергии ×%s", DIESEL_GEN: "энергии ×%s", LAB: "наука ×%s",
	PUMP: "откачка ×%s", VENT: "охлаждение ×%s", DEGAS: "сбор метана ×%s", OIL_PUMP: "добыча нефти ×%s",
	HOME: "кроватей ×%s", DINING: "еда сытнее ×%s", FARM: "урожай ×%s", STORAGE: "вместимость ×%s",
	GRANARY: "вместимость ×%s", OIL_TANK: "вместимость ×%s", LAUNCHPAD: "ракету собирают ×%s быстрее",
	FORGE: "плавка ×%s", KILN: "обжиг ×%s", REFINERY: "перегонка ×%s", ENRICHMENT: "обогащение ×%s",
}


## Супер-материал, из которого постройка работает лучше ("" — никакой).
static func super_material(p: Project) -> String:
	match p.kind:
		Project.Kind.DRILL:
			return "diamond"
		Project.Kind.TUNNEL, Project.Kind.MINE:
			return "gold"
		Project.Kind.LIFT:
			return "silver"
		Project.Kind.ROOM:
			return SUPER_MAT.get(p.purpose, "")
	return ""


## Из чего мебель и лестницы: у деревянной комнаты — дерево, у остальных — из каркаса
## (камень, кирпич, железо; у супер-комнаты — железо), если не выбрали дерево.
static func furnish_material(p: Project) -> String:
	if p.kind != Project.Kind.ROOM or p.material == "wood" or p.furnish_wood:
		return "wood"
	return Project.frame_of(p.material)


## Дерево в стоимости заменяется материалом мебели комнаты.
static func _furnished(cost: Dictionary, p: Project) -> Dictionary:
	var m := furnish_material(p)
	if m == "wood" or not cost.has("wood"):
		return cost
	var out := cost.duplicate()
	out[m] = int(out.get(m, 0)) + int(out["wood"])
	out.erase("wood")
	return out


static func equip_cost(t: int, p: Project) -> Dictionary:
	return _furnished(_equip_cost(t, p), p)


static func _equip_cost(t: int, p: Project) -> Dictionary:
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
		GENERATOR, GAS_GEN:
			return {"stone": 6, "copper": 4, "iron": 4}
		OIL_PUMP:
			return {"iron": 8, "copper": 4, "stone": 6}
		OIL_TANK:
			return {"iron": 4 * blocks(p), "stone": 6}
		REFINERY:
			return {"iron": 12, "copper": 6, "brick": 8}
		ENRICHMENT:
			return {"iron": 12, "copper": 8, "brick": 10}
		DIESEL_GEN:
			return {"iron": 14, "copper": 6}
		LAUNCHPAD:
			return {"stone": 40, "brick": 20, "iron": 20}
		DEGAS:
			return {"wood": 8, "stone": 8}
		GRANARY:
			return {"wood": 2 * w}
		HEARTH:
			# Каменные печи — из того, что есть с самого начала.
			return {"stone": 8 * stoves(p)}
		HEARTH_BRICK:
			return {"brick": 6 * stoves(p)}
		HEARTH_GAS:
			return {"brick": 4 * stoves(p)}
	return {}


static func equip_work(t: int, p: Project) -> float:
	return 6.0 * usable_width(p) if t != NONE else 0.0


static func ladder_cost(p: Project) -> Dictionary:
	return _furnished({"wood": p.rect.size.y * 2}, p)


static func ladder_work(p: Project) -> float:
	return p.rect.size.y * 8.0


## Стоимость и объём текущего обустройства (назначение или лестница).
static func job_cost(p: Project) -> Dictionary:
	if not p.equip_rocket.is_empty():
		return ROCKET_COST[p.equip_rocket]
	if not p.equip_material.is_empty():
		return material_cost(p, p.equip_material)
	return ladder_cost(p) if p.equip_ladder else equip_cost(p.equip_target, p)


static func job_work(p: Project) -> float:
	if not p.equip_rocket.is_empty():
		return ROCKET_WORK
	if not p.equip_material.is_empty():
		return material_work(p, p.equip_material)
	return ladder_work(p) if p.equip_ladder else equip_work(p.equip_target, p)


## Перестройка стен готовой комнаты из материала mat: как новые стены, работы — 70%.
static func material_cost(p: Project, mat: String) -> Dictionary:
	return Project.cost_for(Project.Kind.ROOM, p.rect, mat)


static func material_work(p: Project, mat: String) -> float:
	return Project.work_for(Project.Kind.ROOM, p.rect, mat) * 0.7


## Склад — для стройматериалов, амбар — для еды (без учёта галочек «что хранить»).
static func same_kind(p: Project, key: String) -> bool:
	if p.purpose == SHIP:
		return true
	return FOOD_KEYS.has(key) == (p.purpose == GRANARY)


static func stores(p: Project, key: String) -> bool:
	if PIPED.has(key):
		return p.purpose == SHIP and not p.store_off.has(key)
	if p.store_off.has(key):
		return false
	if p.purpose == SHIP:
		return true
	if p.purpose == GRANARY:
		return FOOD_KEYS.has(key)
	if FOOD_KEYS.has(key):
		return false
	return p.store_filter.is_empty() or p.store_filter.has(key)


## Склад или амбар.
static func is_store(t: int) -> bool:
	return t == STORAGE or t == GRANARY or t == SHIP
