class_name Colony
extends RefCounted
## Колония: гаврики, стройки, комнаты, склад.
## Гаврики сами разбирают работу: сначала потребности (сон, еда), потом работа
## по профессии, потом любая другая. Онлайн они ходят и работают по-настоящему
## (update), оффлайн — упрощённо (advance_offline).

signal event_logged(text: String, kind: String)
## Землетрясение (для тряски камеры).
signal quaked(magnitude: int)

const START_UNITS := 5
## Ресурсов на старте нет — их сначала нужно собрать.
const START_INVENTORY := {}
## Срубленное (не под стройку) дерево с такой вероятностью даёт поросль — лес восстанавливается.
const STUMP_REGROW := 0.6
const SUBSTEP := 0.2
const WALK_SPEED := 3.0
const CLIMB_SPEED := 1.6
const FALL_SPEED := 8.0
const OFFLINE_EFFICIENCY := 0.75
const OFFLINE_STEP := 30.0
const HARVEST_TIME := {WorldGen.FEATURE_TREE: 20.0, WorldGen.FEATURE_BOULDER: 25.0, WorldGen.FEATURE_BUSH: 10.0}
const DIRS4: Array[Vector2i] = WorldData.DIRS4
## Что говорит геолог, почуяв опасность рядом с забоем.
const HAZARD_TEXT := {
	"water": "Геолог: стена влажная — рядом вода. Дальше — риск затопления. Продолжить?",
	"magma": "Геолог: порода раскалена — рядом магма! Прорыв лавы — катастрофа. Продолжить?",
	"gas": "Геолог: пахнет газом — рядом метан. Нужна дегазация. Продолжить?",
	"methane": "Рядом газовый карман — из него в выработку идёт метан! Искра от кирки — взрыв. Работы стоят, пока газ не уйдёт (поможет дегазация). Продолжить на свой риск?",
	"methane_air": "Метан в выработке — тяжело дышать. Работы стоят, пока газ не уйдёт (поможет дегазация, противогазы). Продолжить на свой риск?",
}
## Ресурсы, о находке которых сообщаем сразу.
const NOTABLE := ["coal", "iron_ore", "copper_ore", "silver_ore", "gold_ore", "uranium_ore", "diamond", "salt", "oil"]

# Потребности (сек. реального времени): сытости хватает минут на 12. Сна нет — гаврики не
# устают (раньше во сне голод рос медленнее; теперь он всегда чуть медленнее — еды уходит столько же).
const SATIETY_DECAY := 100.0 / 600.0 * 0.85
## Раны и истощение заживают за 40 минут (с медициной — вдвое быстрее); пока гаврик
## отогревается в тепле — втрое быстрее (как раньше во сне).
const HEAL_TIME := 2400.0
## Ниже этого здоровья гаврик, которому холодно (или жарко), бросает дела и идёт греться.
const WARM_HEALTH := 60.0
## Греется, пока здоровье не станет таким (или не пройдёт WARM_MAX секунд).
const WARM_UNTIL := 90.0
const WARM_MAX := 300.0
## За сколько секунд полный голод убивает здорового гаврика (5 минут).
const STARVE_TIME := 300.0
const EAT_TIME := 6.0
const HUNGRY := 35.0
## Как долго фермер работает, прежде чем пересмотреть занятия.
const FARM_SHIFT := 60.0
# Семьи.
const SOCIAL_TICK := 20.0
## Беременность — месяц игрового времени.
const PREGNANCY_TIME := 20.0 * 30.0
# Растения и рыба.
const PLANT_TICK := 20.0
const OFFLINE_PLANT_TICK := 120.0
## Сколько секунд дерево растёт от саженца до взрослого.
const TREE_GROW_TIME := 3000.0
## Секунд на одну новую ягоду.
const BERRY_REGEN := 120.0
## Шанс за тик появиться саженцу на свободной траве — на каждое дерево рядом.
const TREE_SPREAD := 0.0015
const BUSH_SPREAD := 0.0004
## Шанс за тик, что ветер занесёт семя дерева на свободную траву вдали от деревьев.
const TREE_SEED := 0.00004
const SPREAD_RADIUS := 5
## Растения живут и распространяются в этой полосе вокруг базы.
const PLANT_AREA := 160
## Секунд на восстановление одной рыбы в озере.
const FISH_REGEN := 60.0
## Источник еды для задачи EAT: куст на поверхности.
const EAT_BUSH := -1
## Источник еды: еда, лежащая на земле.
const EAT_DROP := -2
## Сколько единиц ресурса гаврик уносит за раз.
const CARRY := 5
## Оффлайн одна ходка за материалами занимает столько секунд.
const OFFLINE_HAUL_TIME := 20.0
# Игровое время: сутки — 20 секунд, месяц — 10 минут, год — 2 часа игры.
const DAY := 20.0
## Смена дня и ночи (выключена; сна у гавриков нет).
const DAY_NIGHT := false
## Ночь: с 22:00 до 6:00.
const NIGHT_FROM := 22.0
const NIGHT_TO := 6.0
const MONTH := DAY * 30.0
const YEAR := MONTH * 12.0
const MONTH_NAMES := ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
## Игра начинается 1 марта — весной, чтобы успеть запастись к зиме.
const CALENDAR_START := MONTH * 2.0
enum Season { WINTER, SPRING, SUMMER, AUTUMN }
const SEASON_NAMES := ["зима", "весна", "лето", "осень"]
## Температура на поверхности в середине каждого месяца (январь … декабрь), °C; между — плавно.
const MONTH_TEMPS := [-8.0, -5.0, 8.0, 12.0, 16.0, 20.0, 23.0, 21.0, 15.0, 8.0, 1.0, -5.0]
## Тепло даёт только огонь: очаг и работающий генератор греют всё вокруг себя
## (от стен комнаты, дальность — RoomType.heat_zone). Без отопления в комнате так же
## холодно, как в земле вокруг.
const HEAT := 18.0
## Очаг горит, пока у него холоднее этого.
const HEARTH_ON_BELOW := 18.0
## Ферма растит грибы только в тепле.
const FARM_MIN_TEMP := 15.0
## Ниже этой температуры обычному гаврику холодно (синие и пушистые терпят больше).
const COLD := 0.0
## Зимой с пристани рыба ловится вдвое дольше, с берега и мостиков — никак (лёд).
const WINTER_FISH_SLOWDOWN := 2.0
## Сколько лет служит постройка до полного износа (на поверхности).
const WEAR_YEARS := {"wood": 20.0, "stone": 100.0, "brick": 70.0, "iron": 60.0}
## Под землёй сырость: дерево и металл изнашиваются быстрее, камню всё равно.
const WEAR_UNDERGROUND := {"wood": 0.6, "stone": 1.0, "brick": 0.9, "iron": 0.6}
## Предупреждения об износе.
const WEAR_WARN := [0.7, 0.9]
## Ресурсы, которые гаврики склада добывают сами: ресурс -> объект поверхности.
## −1 — еду (рыбу) не собирают с объектов, а ловят.
const GATHER_SOURCES := {"wood": WorldGen.FEATURE_TREE, "stone": WorldGen.FEATURE_BOULDER, "berries": WorldGen.FEATURE_BUSH, "fish": -1}
## Сытость за единицу: ягоды — лёгкий перекус, рыба и грибы с фермы — настоящая еда.
## Еда трёх видов: грибы с фермы (ключ "food" — так он назывался, когда еда была одна),
## рыба и ягоды. В строке ресурсов — одним значком (бургер).
const NUTRITION := {"food": 32.0, "fish": 32.0, "berries": 9.0}
## За один приём пищи съедают до стольких единиц, пока не наберут столько сытости.
const MEAL_UNITS := 4
const MEAL_GOAL := 60.0
## В столовой еда сытнее.
const DINING_BONUS := 1.5
## Норма запаса для нового склада.
const DEFAULT_TARGETS := {"wood": 40, "stone": 20, "fish": 30}

var world: WorldData
var pathing: Pathing
var physics: Physics
var elements: Elements
var loads: Loads
## Во время толчков своды держат меньше.
var quake_factor := 1.0
## Стихийные бедствия (бури, землетрясения) — выбирается при создании игры.
var disasters := true
var research := Research.new()
## Энергия: сколько дают генераторы, сколько берут потребители, доля обеспеченности 0..1.
var power_made := 0
var power_used := 0
var power_ratio := 1.0
## Идёт оффлайн-расчёт (без анимаций и гибели).
var offline := false
var units: Array[Unit] = []
var projects: Array[Project] = []
var inventory := {}
## Ресурсы, которые колония хоть раз получала (открывают материалы стройки).
var known_resources := {}
## Клетки готовых построек: Vector2i -> id проекта.
var interior := {}
## Клетки комнат, где ходят по полу (без колонны лестницы). Vector2i -> id проекта.
var room_cells := {}
## Занятые цели: ключ -> id гаврика.
var reserved := {}
## Прогресс копки клеток, сек: Vector2i -> float.
var dig_progress := {}
## Прогресс сбора: x -> float.
var harvest_progress := {}
var cells_dug := 0
var discovered := {}
var next_project_id := 1
var next_unit_id := 1
var rng := RandomNumberGenerator.new()
## Клетка базы на поверхности: возле неё кучи ресурсов и отвал.
var home := Vector2i.ZERO
var _social_t := 0.0
var _plant_t := 0.0
## Запас рыбы в озёрах: id озера -> количество.
var fish := {}
## Настил мостов и пристаней: Vector2i -> id проекта.
var deck := {}
var _climb_t := 0.0
## Кусты в полосе вокруг базы (обновляется при росте растений).
var _bushes: Array[int] = []
var _shore_progress := {}
## Разведанная часть мира: столбцы, куда доходили гаврики, и глубина/высота работ.
const EXPLORE_RADIUS := 30
## Поверхность у базы видна сразу на столько метров в обе стороны.
const START_VIEW := 60
var explored_min := 0
var explored_max := 0
var deepest_y := 0
var highest_y := 0
var _explore_t := 0.0
var _access_t := 0
var _full_warned := {}
## Игровое время с начала колонии, сек.
var game_time := 0.0
## Когда гаврик последний раз уходил из облака метана: id -> время игры.
var _fled := {}
## Знакомства: "id1,id2" -> сколько секунд провели рядом (с поправкой на общительность).
var acquaint := {}
## Когда последний раз сообщали о газовой тревоге на стройке: id -> время игры.
var _gas_logged := {}
const GAS_LOG_EVERY := 300.0
## Когда последний раз посылали гаврика на разведку за сырьём (время игры).
var _scout_at := -100.0
## Прогресс оффлайн-работ без своего места хранения (ходки за материалами, ремонт).
var _offline_progress := {}
## Добытое лежит там, где добыто, пока не унесут: клетка -> {ресурс: количество}.
var drops := {}
## Сколько всего добыто и сделано за игру: ресурс -> количество (для итогов).
var produced := {}
## Нормы запаса — общие для всех складов и амбаров: ресурс -> сколько держать.
var store_targets := {}


func _init(p_world: WorldData) -> void:
	world = p_world
	pathing = Pathing.new(world, interior, room_cells, deck)
	physics = Physics.new(self)
	elements = Elements.new(self)
	loads = Loads.new(self)
	rng.seed = world.gen.world_seed + 12345


# --- Начало игры ----------------------------------------------------------------

func start_new(home_x: int) -> void:
	inventory = START_INVENTORY.duplicate()

	home = Vector2i(home_x, world.gen.surface_y(home_x))
	explored_min = home_x - START_VIEW
	explored_max = home_x + START_VIEW
	deepest_y = home.y
	highest_y = home.y
	_refresh_bushes()
	var sexes := [Unit.Sex.MALE, Unit.Sex.FEMALE, Unit.Sex.MALE, Unit.Sex.FEMALE]
	sexes.append(rng.randi_range(0, 1))
	# Основатели — самые яркие и разные цвета: красный, синий, зелёный, жёлтый, фиолетовый.
	var hues := [0.0, 0.62, 0.33, 0.15, 0.8, 0.08, 0.5]
	for i in START_UNITS:
		var x := home_x - 2 + i
		var g := Genetics.founder(rng)
		g["female"] = sexes[i] == Unit.Sex.FEMALE
		var col := Color.from_hsv(hues[i % hues.size()], 1.0, 1.0)
		g["color"] = [col, col]
		var u := _new_unit(sexes[i], Vector2(x, world.gen.surface_y(x) - 1), g)
		u.age = Unit.CHILD_TIME + rng.randf_range(0.1, 0.8) * YEAR
		# Небольшие врождённые склонности.
		for k in u.skills:
			u.skills[k] = rng.randf_range(0.0, 200.0)
		u.energy = rng.randf_range(85.0, 100.0)
		u.satiety = rng.randf_range(80.0, 100.0)


func _new_unit(sex: int, pos: Vector2, genome := {}) -> Unit:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	if genome.is_empty():
		genome = Genetics.founder(rng)
		genome["female"] = sex == Unit.Sex.FEMALE
	u.set_genome(genome)
	u.lifespan = Unit.life_years * YEAR * u.stat("longevity") * rng.randf_range(0.85, 1.15)
	u.name = _free_name(u.sex)
	u.look = rng.randf()
	# Разнести проверки стихий по времени — от зерна мира, чтобы прогоны повторялись.
	u.env_t = fmod(float(u.id) * 0.618034, 1.0)
	u.pos = pos
	units.append(u)
	return u


## Своё имя из слогов, не занятое другими гавриками.
func _free_name(sex: int) -> String:
	var used := {}
	for u in units:
		used[u.name] = true
	for i in 50:
		var n := NameGen.make(rng, sex == Unit.Sex.FEMALE)
		if not used.has(n):
			return n
	return NameGen.make(rng, sex == Unit.Sex.FEMALE) + " %d" % next_unit_id


func unit_by_id(uid: int) -> Unit:
	for u in units:
		if u.id == uid:
			return u
	return null


func adults() -> int:
	var n := 0
	for u in units:
		if not u.child:
			n += 1
	return n


# --- Стройки --------------------------------------------------------------------

## Стройки по номеру: указатель пересобирается, когда меняется список.
var _by_id := {}
var _by_id_n := -1


func project_by_id(pid: int) -> Project:
	if _by_id_n != projects.size():
		_by_id.clear()
		for q in projects:
			_by_id[q.id] = q
		_by_id_n = projects.size()
	var p: Project = _by_id.get(pid)
	if p != null:
		return p
	# Список поменяли без смены длины (убрали одну, добавили другую) — ищем честно.
	for q in projects:
		if q.id == pid:
			_by_id_n = -1
			return q
	return null


## Игрок что-то поручил — гаврики без дела ищут работу сразу, а не через несколько секунд.
func wake_idle() -> void:
	for u in units:
		if u.state == Unit.State.IDLE:
			u.retry = 0.0
			u.idle_fails = 0
		elif u.task == Unit.Task.STROLL:
			_drop(u)


func project_at(c: Vector2i) -> Project:
	var found: Project = null
	for p in projects:
		if p.has_cell(c):
			# Мост и пристань могут лежать друг на друге — берём меньшую (пристань);
			# тоннели, шахты и лифты пересекаются — берём лифт.
			if found == null or (p.is_water_structure() and found.is_water_structure() and p.area() < found.area()) \
					or (p.kind == Project.Kind.LIFT and is_passage(found.kind)):
				found = p
			if not p.is_water_structure() and not is_passage(p.kind):
				return p
	return found


func unit_at(p: Vector2) -> Unit:
	# Только по самому гаврику — от ступней до макушки и по ширине тела (раньше круг
	# с центром над головой ловил касания выше гаврика: склад над ним было не выбрать).
	var best: Unit = null
	var best_d := INF
	for u in units:
		var h := 1.3 * (lerpf(0.5, 0.9, u.growth()) if u.child else 1.0)
		var foot := u.pos + Vector2(0.5, 1.0)
		if absf(p.x - foot.x) > 0.6 or p.y > foot.y + 0.1 or p.y < foot.y - h:
			continue
		var d := (foot - Vector2(0, h * 0.5)).distance_to(p)
		if d < best_d:
			best_d = d
			best = u
	return best


## Материалы стен, доступные колонии: дерево сразу, остальное — когда добыто.
func available_materials() -> Array[String]:
	var out: Array[String] = ["wood"]
	if known_resources.has("stone"):
		out.append("stone")
	if research.has("pottery"):
		out.append("brick")
	if research.has("steel_frame"):
		out.append("iron")
	return out


## Сколько гавриков могут одновременно пройти тоннелем (по его ширине).
static func tunnel_lanes(r: Rect2i) -> int:
	if r.size.y > r.size.x:
		return maxi(1, r.size.x)
	return maxi(1, r.size.y - 1)


func validate(kind: int, r: Rect2i, material := "wood", check_size := true) -> String:
	var err := Project.size_error(kind, r) if check_size else ""
	if not err.is_empty():
		return err
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var other := project_at(c)
			# Мост и пристань друг другу не мешают: пристань может начинаться под мостом.
			if other != null and other.is_water_structure() and (kind == Project.Kind.BRIDGE or kind == Project.Kind.PIER) \
					and other.kind != kind:
				continue
			# Тоннели, шахты и лифты пересекаются свободно; лифт по готовому тоннелю или
			# шахте забирает занятую часть себе.
			if other != null and is_passage(kind) and is_passage(other.kind):
				continue
			if other != null and not (kind == Project.Kind.ROOM and _room_fits_mine(r, other)):
				if other.kind == Project.Kind.MINE and kind == Project.Kind.ROOM:
					return "Комнату в шахте ставьте на всю её высоту, когда шахта готова"
				return "Пересекается с другой стройкой"
			if world.is_revealed(x, y) and Mat.is_fluid(world.get_mat(x, y)):
				return "В зоне стройки %s" % Mat.name_of(world.get_mat(x, y)).to_lower()
	if kind == Project.Kind.BRIDGE or kind == Project.Kind.PIER:
		return _water_structure_error(kind, r)
	if kind == Project.Kind.LIFT:
		var is_cargo := material == "cargo" or material == "cargo_drill"
		if not research.has("cargo_lifts" if is_cargo else "lifts"):
			return "Сначала изучите «%s»" % Research.tech_name("cargo_lifts" if is_cargo else "lifts")
		# Под бур-лифтом свой лифт не нужен: шахта его лифта сама дорастает за буром.
		if material != "cargo_drill":
			for d in projects:
				if d.kind == Project.Kind.DRILL and d.link_id != 0 and d.rect.position.x < r.end.x \
						and d.rect.end.x > r.position.x and r.end.y > d.rect.end.y and r.position.y >= d.rect.position.y:
					return "Под бур-лифтом лифт не нужен: прикажите бур-лифту бурить вниз — шахта его лифта дорастёт сама"
		if r.size.y > r.size.x and r.size.x != (3 if is_cargo else 2):
			return "Шахта %s лифта — %d м шириной" % ["грузового" if is_cargo else "пассажирского", 3 if is_cargo else 2]
	if kind == Project.Kind.DRILL and not research.has("drill_rig"):
		return "Сначала изучите «%s»" % Research.tech_name("drill_rig")
	if kind == Project.Kind.PROBE and not research.has("geoprobe"):
		return "Сначала изучите «%s»" % Research.tech_name("geoprobe")
	# Лифт бур-лифта стоит над буром — и над землёй тоже.
	if is_passage(kind) and kind != Project.Kind.DRILL and kind != Project.Kind.PROBE and material != "cargo_drill":
		for x in range(r.position.x, r.end.x):
			if r.position.y < world.gen.surface_y(x):
				return "%s — только под землёй. Над землёй стройте комнаты" % (
					{Project.Kind.TUNNEL: "Тоннели", Project.Kind.MINE: "Шахты"}.get(kind, "Лифты"))
	if kind == Project.Kind.DRILL or kind == Project.Kind.PROBE:
		# Бур и геоскважину ставят на землю, на пол хода или прямо в породу (место выкопают).
		for x in range(r.position.x, r.end.x):
			var below := Vector2i(x, r.end.y)
			if not (interior.has(below) or not world.is_revealed(below.x, below.y) or Mat.is_solid(world.get_mat(below.x, below.y))):
				return "%s не на что встать — нужен грунт или пол снизу" % ("Буру" if kind == Project.Kind.DRILL else "Геоскважине")
	if kind == Project.Kind.ROOM:
		# Каждая колонна комнаты должна на что-то опираться. Строящийся тоннель или шахта
		# снизу — тоже опора: их крепь станет полом (раньше над копающимся тоннелем склад
		# было не поставить, пока тот не докопан).
		for x in range(r.position.x, r.end.x):
			var below := Vector2i(x, r.end.y)
			var under := project_at(below)
			var ok := interior.has(below) or not world.is_revealed(below.x, below.y) \
				or Mat.is_solid(world.get_mat(below.x, below.y)) \
				or (under != null and (under.kind == Project.Kind.TUNNEL or under.kind == Project.Kind.MINE))
			if not ok:
				return "Комнате не на что опереться — нужен грунт или постройка снизу"
		var floors_err := _floors_error(r, material)
		if not floors_err.is_empty():
			return floors_err
		# Пролёт под землёй ограничен прочностью породы потолка: шире — нужна крепь,
		# втрое шире — не удержать ничем.
		var span := ceiling_span(r)
		if r.size.x > span[0] * 3:
			return "Потолок из породы «%s» не удержать даже с укреплением: здесь не шире %d м" % [
				Mat.name_of(span[1]).to_lower(), span[0] * 3]
	return ""


## Комнату можно поставить в готовую шахту — ровно на её высоту.
func _room_fits_mine(r: Rect2i, m: Project) -> bool:
	return m.kind == Project.Kind.MINE and m.phase == Project.Phase.DONE \
		and r.position.y == m.rect.position.y and r.end.y == m.rect.end.y


## Комната встаёт в шахту: шахта делится на куски слева и справа от комнаты.
func _carve_mines(r: Rect2i) -> void:
	for m in projects.duplicate():
		if m.kind != Project.Kind.MINE or not m.rect.intersects(r):
			continue
		projects.erase(m)
		_by_id_n = -1
		for c in m.cells():
			if r.has_point(c):
				interior.erase(c)
		var parts: Array[Rect2i] = []
		if r.position.x > m.rect.position.x:
			parts.append(Rect2i(m.rect.position.x, m.rect.position.y, r.position.x - m.rect.position.x, m.rect.size.y))
		if r.end.x < m.rect.end.x:
			parts.append(Rect2i(r.end.x, m.rect.position.y, m.rect.end.x - r.end.x, m.rect.size.y))
		for pr in parts:
			var q := Project.new()
			q.id = next_project_id
			next_project_id += 1
			q.kind = Project.Kind.MINE
			q.rect = pr
			q.phase = Project.Phase.DONE
			q.paid = true
			q.workers = m.workers
			q.wear = m.wear
			for i in q.slice_count():
				q.supported.append(i)
			projects.append(q)


## Лифт по готовому тоннелю или шахте: от них остаются куски вокруг лифта.
func _carve_passages(r: Rect2i) -> void:
	for m in projects.duplicate():
		if m.phase != Project.Phase.DONE or not (m.kind == Project.Kind.TUNNEL or m.kind == Project.Kind.MINE) \
				or not m.rect.intersects(r):
			continue
		projects.erase(m)
		_by_id_n = -1
		for c in m.cells():
			if r.has_point(c):
				interior.erase(c)
		# Остаток прямоугольника без r: полосы сверху, снизу, слева и справа.
		var parts: Array[Rect2i] = []
		var mr: Rect2i = m.rect
		var top := Rect2i(mr.position.x, mr.position.y, mr.size.x, r.position.y - mr.position.y)
		var bottom := Rect2i(mr.position.x, r.end.y, mr.size.x, mr.end.y - r.end.y)
		var y0 := maxi(mr.position.y, r.position.y)
		var y1 := mini(mr.end.y, r.end.y)
		var left := Rect2i(mr.position.x, y0, r.position.x - mr.position.x, y1 - y0)
		var right := Rect2i(r.end.x, y0, mr.end.x - r.end.x, y1 - y0)
		for pr in [top, bottom, left, right]:
			if pr.size.x > 0 and pr.size.y > 0:
				parts.append(pr)
		for pr in parts:
			# Мелкий обрезок (меньше человеческого роста) — просто выкопанная пустота.
			if m.kind == Project.Kind.TUNNEL and pr.size.y < 2:
				continue
			if m.kind == Project.Kind.MINE and pr.size.y != Project.MINE_HEIGHT:
				continue
			var q := Project.new()
			q.id = next_project_id
			next_project_id += 1
			q.kind = m.kind
			q.rect = pr
			q.phase = Project.Phase.DONE
			q.paid = true
			q.workers = m.workers
			q.wear = m.wear
			for i in q.slice_count():
				q.supported.append(i)
			projects.append(q)
			for c in q.cells():
				interior[c] = q.id


## [допустимый пролёт без крепи, самая слабая порода потолка] для комнаты r.
func ceiling_span(r: Rect2i) -> Array:
	var limit := 1 << 20
	var weakest := Mat.AIR
	for x in range(r.position.x, r.end.x):
		var cy := r.position.y - 1
		if cy < world.gen.surface_y(x):
			continue
		var m := world.get_mat(x, cy)
		if Mat.is_solid(m) and not Mat.is_loose(m) and not interior.has(Vector2i(x, cy)):
			var lim := span_limit(m, Vector2i(x, cy))
			if lim < limit:
				limit = lim
				weakest = m
	return [limit, weakest]


## Дерево на дополнительную крепь для комнаты r (0 — порода держит сама).
func support_needed(kind: int, r: Rect2i) -> int:
	if kind != Project.Kind.ROOM:
		return 0
	var span: Array = ceiling_span(r)
	return maxi(0, r.size.x - span[0]) * r.size.y


## Мостик и пристань для ряда, проведённого над озером: ряд привязывается к уровню
## воды, мостик тянется от берега до берега, пристань — от берега, где начали.
## Возвращает {"bridge": Rect2i, "pier": Rect2i} (пустой Rect2i — нельзя).
func water_rects(start_x: int, end_x: int) -> Dictionary:
	var out := {"bridge": Rect2i(), "pier": Rect2i()}
	var lake := {}
	for x in range(mini(start_x, end_x), maxi(start_x, end_x) + 1):
		lake = world.gen.lake_at(x)
		if not lake.is_empty():
			break
	if lake.is_empty():
		return out
	var span := world.gen.lake_water_span(lake)
	var row: int = int(lake["level"]) - 1
	var left := span.x - 1
	var right := span.y + 1
	if world.get_mat(left, row) != Mat.AIR:
		left += 1
	if world.get_mat(right, row) != Mat.AIR:
		right -= 1
	out["bridge"] = Rect2i(left, row, right - left + 1, 1)
	# Пристань: от ближайшего к началу берега, длиной как провели (3–10 м).
	# Если до того берега гаврикам не дойти — от другого.
	var length := clampi(absi(end_x - start_x) + 1, 3, 10)
	var l_pier := Rect2i(left, row, mini(length, right - left), 1)
	var rl := maxi(left + 1, right - length + 1)
	var r_pier := Rect2i(rl, row, right - rl + 1, 1)
	var near_left := absi(start_x - left) <= absi(start_x - right)
	out["pier"] = l_pier if near_left else r_pier
	if not can_reach(out["pier"]):
		var other := r_pier if near_left else l_pier
		if can_reach(other):
			out["pier"] = other
	return out


## Могут ли гаврики дойти до зоны. Карта достижимости — один общий обход сразу от всех
## взрослых (а не по обходу на каждого), обновляется раз в REACH_EVERY секунд игры.
const REACH_EVERY := 3.0
const REACH_CAP := 24000
var _reach_map := {}
var _reach_at := -INF
var _reach_key := []


func _refresh_reach() -> void:
	# Новые ходы, лестницы, готовые постройки — пересчёт сразу; иначе — по таймеру.
	var key := [pathing.climb_rev, interior.size(), room_cells.size(), deck.size(), units.size()]
	if game_time - _reach_at < REACH_EVERY and key == _reach_key and not _reach_map.is_empty():
		return
	_reach_at = game_time
	_reach_key = key
	var starts: Array[Vector2i] = []
	for u in units:
		if not u.child:
			starts.append(u.cell())
	_reach_map = pathing.explore_multi(starts, REACH_CAP)


func can_reach(r: Rect2i) -> bool:
	_refresh_reach()
	if _near_rect(r, _reach_map, true) != null:
		return true
	if _reach_map.size() < REACH_CAP:
		return false
	# В большой колонии обход обрывается раньше дальних мест — ищем путь прицельно
	# от ближайшего к зоне гаврика.
	var near: Unit = null
	var best := INF
	for u in units:
		var d := Vector2(u.cell()).distance_squared_to(Vector2(r.get_center()))
		if not u.child and d < best:
			best = d
			near = u
	if near == null:
		return false
	# Прицельный поиск недешёв: не чаще раза в FAR_GAP мс (пока ждём — не пугаем «нет доступа»).
	var now := Time.get_ticks_msec()
	if not offline and now - _far_at < FAR_GAP:
		return true
	_far_at = now
	var e := pathing.explore(near.cell())
	return _reach_far(near.cell(), r, e[0], e[1])


## --- Дальние стройки ------------------------------------------------------------------
## Обход гаврика ограничен (Pathing.MAX_NODES): в большой колонии глубокий забой в него не
## попадает, и стройка висела бы «Нет доступа». Тогда путь к ней ищут прицельно и дописывают
## в обход гаврика (вместе с клетками вокруг стройки). Неудачу помнят FAR_RETRY секунд.
const FAR_RETRY := 20.0
const FAR_GAP := 300
var _far_fail := {}
var _far_at := -100000


func _reach_far(start: Vector2i, r: Rect2i, parents: Dictionary, dist: Dictionary) -> bool:
	if _near_rect(r, dist, true) != null:
		return true
	if not Pathing.truncated(dist):
		return false
	var key := "%d,%d,%d,%d" % [r.position.x, r.position.y, r.size.x, r.size.y]
	if game_time - float(_far_fail.get(key, -INF)) < FAR_RETRY:
		return false
	var goals := {}
	var area := r.grow(1)
	area.size.y += 1
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if pathing.node(c):
				goals[c] = true
	return _extend_far(start, goals, key, parents, dist)


## Прицельный путь от start к любой из goals дописывается в обход гаврика (с клетками вокруг
## конца пути). Неудачу по ключу key помнят FAR_RETRY секунд.
func _extend_far(start: Vector2i, goals: Dictionary, key: String, parents: Dictionary, dist: Dictionary) -> bool:
	if game_time - float(_far_fail.get(key, -INF)) < FAR_RETRY:
		return false
	var path := pathing.find_path(start, goals)
	if path.is_empty():
		_far_fail[key] = game_time
		return false
	_far_fail.erase(key)
	var prev := start
	for c in path:
		if not parents.has(c):
			parents[c] = prev
			dist[c] = int(dist[prev]) + 1
		prev = c
	# Вокруг стройки — небольшой обход: чтобы подойти к любой её клетке.
	var local := pathing._explore(prev, 400)
	var base := int(dist[prev])
	for c in local[0]:
		if not parents.has(c):
			parents[c] = local[0][c]
			dist[c] = base + int(local[1][c])
	return true


## Раз в несколько секунд: до каких строек гаврикам не дойти — предупреждение.
func _check_access() -> void:
	for p in projects:
		var working := p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD \
			or p.phase == Project.Phase.EQUIP or p.repairing
		if p.paused or not working or workers_on(p) > 0 or p.bored_by > 0:
			continue
		var blocked_access := p.blocked.begins_with("Нет доступа")
		if not p.blocked.is_empty() and not blocked_access:
			continue
		if can_reach(p.rect):
			if blocked_access:
				p.blocked = ""
		elif not blocked_access:
			p.blocked = "Нет доступа — гаврики не могут дойти до стройки" if p.is_water_structure() \
				else "Нет доступа — проложите тоннель к стройке"
			_log("%s: %s" % [p.title(), p.blocked], "warning")


## Материал на складе есть, но склад отрезан (яма без лестницы, обвал): гаврики не могут
## его взять, и стройка молча стояла бы. Предупреждаем — игрок проложит путь.
const NO_SOURCE := "Склад недоступен"


func _check_sources() -> void:
	for p in projects:
		var had := p.blocked.begins_with(NO_SOURCE)
		if p.paused or (not had and not p.blocked.is_empty()):
			continue
		var cut: PackedStringArray = []
		var need := _needed_now(p, true)
		for k in need:
			if RoomType.PIPED.has(k) or int(p.delivered.get(k, 0)) + in_transit(p, k) >= int(need[k]):
				continue
			# Нет совсем — это «Не хватает», а не доступ.
			if inventory.get(k, 0) + drop_total(k) <= 0:
				continue
			if not _source_reachable(k, p):
				cut.append(Mat.resource_name(k).to_lower())
		if cut.is_empty():
			if had:
				p.blocked = ""
		else:
			var msg := "%s: %s лежит там, куда гаврикам не дойти — проложите путь (лестница, тоннель)" % [NO_SOURCE, ", ".join(cut)]
			if p.blocked != msg:
				p.blocked = msg
				_log("%s: %s" % [p.title(), msg], "warning")


## Может ли кто-то из тех, кто доходит до стройки p, дойти и до склада (или кучи) с ресурсом
## key. Общая карта достижимости тут не годится: гаврик по ту сторону трещины «достаёт» до
## склада, но не до стройки.
func _source_reachable(key: String, p: Project) -> bool:
	var near: Array = units.filter(func(u: Unit) -> bool: return not u.child)
	var mid := Vector2(p.rect.get_center())
	near.sort_custom(func(a: Unit, b: Unit) -> bool:
		return Vector2(a.cell()).distance_squared_to(mid) < Vector2(b.cell()).distance_squared_to(mid))
	var tried := 0
	for u: Unit in near:
		var e := pathing.explore(u.cell())
		var dist: Dictionary = e[1]
		if Pathing.truncated(dist):
			# Обход оборвался — не знаем наверняка, не пугаем.
			return true
		if _near_rect(p.rect, dist, true) == null:
			tried += 1
			if tried >= 6:
				break
			continue
		if inventory.get(key, 0) > 0 and _source_spot(key, dist) != null:
			return true
		for c: Vector2i in drops:
			if drop_amount(c, key) > 0 and _drop_stand(c, dist) != null:
				return true
		return false
	# До самой стройки никто не доходит — это «Нет доступа», а не склад.
	return true


## Старые сохранения: ключ и значение «metal» (сталь) → «iron» (железо), количества складываются.
static func steel_to_iron(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			var key = "iron" if str(k) == "metal" else k
			var val = steel_to_iron(v[k])
			if out.has(key) and (val is float or val is int) and (out[key] is float or out[key] is int):
				out[key] = out[key] + val
			else:
				out[key] = val
		return out
	if v is Array:
		var arr := []
		for e in v:
			arr.append(steel_to_iron(e))
		return arr
	if v is String and v == "metal":
		return "iron"
	return v


## Мост — над самой водой, от берега до берега; пристань — от берега в воду.
func _water_structure_error(kind: int, r: Rect2i) -> String:
	var over_water := 0
	for x in range(r.position.x, r.end.x):
		if world.get_mat(x, r.position.y) != Mat.AIR:
			return "Мост и пристань ставятся на воздух над водой"
		var below := world.get_mat(x, r.position.y + 1)
		if below == Mat.WATER:
			over_water += 1
		elif not Mat.is_solid(below):
			return "Под мостом должна быть вода или берег — проведите ряд прямо над водой"
	if over_water == 0:
		return "Мост и пристань строятся над водой"
	# Конец опирается на берег: под ним грунт или он упирается в крутой берег.
	var left := Mat.is_solid(world.get_mat(r.position.x, r.position.y + 1)) \
		or Mat.is_solid(world.get_mat(r.position.x - 1, r.position.y))
	var right := Mat.is_solid(world.get_mat(r.end.x - 1, r.position.y + 1)) \
		or Mat.is_solid(world.get_mat(r.end.x, r.position.y))
	if kind == Project.Kind.BRIDGE and not (left and right):
		return "Мост должен опираться на оба берега"
	if kind == Project.Kind.PIER and not (left or right):
		return "Пристань должна начинаться на берегу"
	return ""


## Наибольший пролёт без крепи для породы m на глубине клетки c.
func span_limit(m: int, c: Vector2i) -> int:
	var depth := c.y - world.gen.surface_y(c.x)
	var k := clampf(1.0 - depth / 8000.0, 0.4, 1.0) * quake_factor
	return maxi(2, roundi(Mat.max_span(m) * k))


## Комнаты прямо под зоной (по всей ширине).
func rooms_below(r: Rect2i) -> Array[Project]:
	var out: Array[Project] = []
	for x in range(r.position.x, r.end.x):
		var p := project_at(Vector2i(x, r.end.y))
		if p != null and p.kind == Project.Kind.ROOM and not out.has(p):
			out.append(p)
	return out


## Выдержат ли нижние этажи вес новой комнаты и не опрокинет ли башню ветер.
func _floors_error(r: Rect2i, material: String) -> String:
	for p in rooms_below(r):
		if p.phase != Project.Phase.DONE:
			return "Нижнее здание ещё не достроено или обустраивается"
	return loads.room_error(r, material)


## Пол комнаты ниже поверхности земли — без лестницы из неё не выбраться.
func _floor_below_surface(r: Rect2i) -> bool:
	var floor_y := r.end.y - 1
	for x in range(r.position.x - 1, r.end.x + 1):
		if floor_y >= world.gen.surface_y(x):
			return true
	return false


func workers_on(p: Project) -> int:
	# Носильщики — не рабочие стройки или мастерской: материалы и сырьё носят сверх мест.
	var n := 0
	for u in units:
		if u.project_id == p.id and u.task not in [Unit.Task.SLEEP, Unit.Task.EAT, Unit.Task.HAUL]:
			n += 1
	return n


## Столбцы объектов поверхности, которые пересекаются с зоной.
func features_in(r: Rect2i) -> Array[int]:
	var out: Array[int] = []
	for x in range(r.position.x - 1, r.end.x + 1):
		var f := world.feature_at(x)
		if f == WorldGen.FEATURE_NONE:
			continue
		var base := world.gen.surface_y(x) - 1
		var top := base - (world.gen.tree_height(x) if f == WorldGen.FEATURE_TREE else 0)
		var left := x - (1 if f == WorldGen.FEATURE_TREE else 0)
		var right := x + (1 if f == WorldGen.FEATURE_TREE else 0)
		if right >= r.position.x and left < r.end.x and base >= r.position.y and top < r.end.y:
			out.append(x)
	return out


func uncleared(p: Project) -> Array[int]:
	var out: Array[int] = []
	for x in p.clear_x:
		if world.feature_at(x) != WorldGen.FEATURE_NONE:
			out.append(x)
	return out


## Есть ли у зоны выход к открытому пространству или к другой стройке.
func has_access(r: Rect2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if world.is_open(x, y) or (not r.has_point(Vector2i(x, y)) and project_at(Vector2i(x, y)) != null):
				return true
	return false


func create_project(kind: int, r: Rect2i, workers := -1, material := "wood", check_size := true) -> Project:
	wake_idle()
	if not validate(kind, r, material, check_size).is_empty():
		return null
	if kind == Project.Kind.ROOM:
		_carve_mines(r)
	if kind == Project.Kind.LIFT:
		_carve_passages(r)
	var p := Project.new()
	p.id = next_project_id
	next_project_id += 1
	p.kind = kind
	p.rect = r
	p.material = material if kind == Project.Kind.ROOM else "wood"
	p.cargo = kind == Project.Kind.LIFT and (material == "cargo" or material == "cargo_drill")
	p.workers = workers if workers > 0 else Project.recommended_workers(kind, r, adults())
	p.ladder = kind == Project.Kind.ROOM and _floor_below_surface(r)
	p.support_wood = support_needed(kind, r)
	# Срезы, где есть порода: их копают по одному и сразу крепят.
	if kind == Project.Kind.ROOM or kind == Project.Kind.TUNNEL or kind == Project.Kind.MINE or kind == Project.Kind.LIFT:
		# Вертикальный ход — лестница по всей длине: через пещеру не копают, но лестницу ставят.
		var ladder_all := kind == Project.Kind.TUNNEL and p.vertical()
		for i in p.slice_count():
			for c in p.slice_cells(i):
				if ladder_all or Mat.is_solid(world.get_mat(c.x, c.y)):
					p.needs_support.append(i)
					break
	# Всё уже выкопано и закреплено (комната в готовой шахте) — крепь не нужна.
	if p.needs_support.is_empty():
		p.support_wood = 0
	# Деревья, кусты и валуны на месте стройки убираются на этапе 1 — как ресурс.
	# Мост и пристань не мешают деревьям (крона у берега — не помеха), их не рубят:
	# дальний берег до постройки моста всё равно не достать.
	for x in ([] if p.is_water_structure() else features_in(r)):
		p.clear_x.append(x)
		world.set_feature_mark(x, true)
	projects.append(p)
	# Надстройка: в нижнем здании автоматически строится лестница наверх.
	if kind == Project.Kind.ROOM:
		for lower in rooms_below(r):
			if not lower.ladder:
				add_ladder(lower)
	_check_phase(p)
	_rebuild_climb()
	return p


## Лестницы, которые придётся добавить при надстройке (для подсказки цены).
func ladders_needed(r: Rect2i) -> Array[Project]:
	var out: Array[Project] = []
	for lower in rooms_below(r):
		if not lower.ladder:
			out.append(lower)
	return out


func set_paused(p: Project, on: bool) -> void:
	wake_idle()
	p.paused = on
	if not on and not p.hazard_pending.is_empty():
		# Игрок решил копать дальше, несмотря на предупреждение геолога.
		p.hazard_ack.append(p.hazard_pending)
		p.hazard_pending = ""
		p.blocked = ""
	if not on:
		p.exposed_t = 0.0
	if not on and p.blocked.begins_with("В зоне"):
		_check_liquids(p)
	_log("%s: %s" % [p.title(), "пауза" if on else "работы возобновлены"], "info")


## Газовая тревога: бригада бросает работу, пока метан не уйдёт или игрок не прикажет продолжать.
## pocket — у газового кармана (взрывоопасно); иначе газа просто столько, что тяжело дышать.
func gas_stop(p: Project, pocket := true) -> void:
	p.paused = true
	p.hazard_pending = "methane"
	p.blocked = HAZARD_TEXT["methane" if pocket else "methane_air"]
	# Газ то копится, то уходит — не засыпаем сообщениями: о стройке не чаще раза в 5 минут.
	if game_time - float(_gas_logged.get(p.id, -1000.0)) > GAS_LOG_EVERY:
		_log("%s: %s" % [p.title(), p.blocked], "danger")
	_gas_logged[p.id] = game_time
	for u in units:
		if u.project_id == p.id:
			_drop(u)


## Гаврик почуял взрывоопасный метан и уходит к ближайшему чистому воздуху.
## Кто работает на стройке, где игрок велел продолжать в газе, — остаётся.
func flee_gas(u: Unit) -> void:
	if u.task == Unit.Task.GOTO or u.state == Unit.State.FALL or game_time - float(_fled.get(u.id, -100.0)) < 20.0:
		return
	var p := project_by_id(u.project_id)
	if p != null and p.hazard_ack.has("methane"):
		return
	_fled[u.id] = game_time
	var reach := pathing.explore(u.cell())
	var dist: Dictionary = reach[1]
	# Чистый воздух поближе — но на полу, а не на лестнице, и не туда, где уже стоят или
	# куда идут другие (раньше все сбегались в одну клетку на лестнице и запирали проход).
	var taken := {}
	for o in units:
		if o != u:
			taken[o.cell()] = int(taken.get(o.cell(), 0)) + 1
			if o.task == Unit.Task.GOTO:
				taken[o.target] = int(taken.get(o.target, 0)) + 1
	var best = null
	var best_d := 1 << 30
	for c: Vector2i in dist:
		var d: int = dist[c] + (8 if pathing.climbable(c) else 0) + 3 * int(taken.get(c, 0))
		if d < best_d and elements.gas_at(c) < Elements.GAS_CLEAR and elements.gas_at(c + Vector2i.UP) < Elements.GAS_CLEAR:
			best_d = d
			best = c
	if best == null or best == u.cell():
		return
	var from := u.cell()
	_drop(u)
	_start(u, Unit.Task.GOTO, best, best, 0, reach[0])
	# Где скопился газ — подсказываем (не чаще раза в 5 минут): там нужна дегазация.
	if game_time - _gas_hint_t > GAS_LOG_EVERY:
		_gas_hint_t = game_time
		_log("%s уходит из облака метана (глубина %s) — там метан копится: поставьте рядом дегазацию" % [u.name, _depth_text(from)], "warning")


func cancel_project(p: Project) -> void:
	wake_idle()
	# Ход, который сверлит бур, отменяют вместе с приказом буру.
	if p.bored_by > 0:
		var drill := project_by_id(p.bored_by)
		if drill != null and drilling(drill) and drill.bore_id == p.id:
			stop_drill(drill)
			return
	# Шахту и тоннель останавливают: готовые метры остаются; мост — построенная часть
	# остаётся пристанью у берега.
	if (p.kind == Project.Kind.MINE or p.kind == Project.Kind.TUNNEL) and p.phase == Project.Phase.DIG and mine_meters_done(p) > 0:
		stop_mine(p)
		return
	if p.kind == Project.Kind.BRIDGE and p.phase == Project.Phase.BUILD and bridge_meters_done(p) > 0:
		stop_bridge(p)
		return
	if drilling(p):
		stop_drill(p)
		return
	if p.phase == Project.Phase.EQUIP:
		cancel_equip(p)
		return
	if p.phase == Project.Phase.DONE:
		if p.repairing:
			_cancel_repair(p)
		return
	if p.paid:
		# Возвращаем неизрасходованную часть материалов.
		_refund(p.cost(), 1.0 - p.build_done / p.build_work())
	_return_delivered(p)
	# Бур-лифт — одна постройка: отменяют и бур, и его лифт.
	var partner: Project = project_by_id(p.link_id) if drill_lift_part(p) else null
	projects.erase(p)
	if partner != null and projects.has(partner) and partner.phase != Project.Phase.DONE:
		partner.link_id = 0
		cancel_project(partner)
	_by_id_n = -1
	for c in p.cells():
		room_cells.erase(c)
	_restore_water_overlaps(p)
	_rebuild_climb()
	# Кто стоял в рухнувшем или шёл через него — останавливается (и падает, если не на чем стоять).
	for u in units:
		var through := u.project_id == p.id or p.rect.grow(1).has_point(u.cell())
		for i in range(u.path_i, u.path.size()):
			if through:
				break
			through = p.rect.has_point(u.path[i])
		if through:
			_drop(u)
	_log("%s отменена" % p.title(), "info")
	physics.check_area(p.cells())


## Можно ли снести постройку (сверху ничего не стоит).
func demolish_error(p: Project) -> String:
	if drill_lift_part(p) and p.kind == Project.Kind.LIFT and project_by_id(p.link_id) != null:
		return demolish_error(project_by_id(p.link_id))
	if drilling(p):
		return "Бур сверлит — сначала остановите его"
	if p.phase != Project.Phase.DONE and p.phase != Project.Phase.EQUIP:
		return "Снести можно только готовую постройку — идущую стройку отмените"
	for q in projects:
		if q == p or q.kind != Project.Kind.ROOM:
			continue
		if q.rect.end.y == p.rect.position.y and q.rect.position.x < p.rect.end.x and q.rect.end.x > p.rect.position.x:
			return "Сначала снесите то, что стоит сверху"
	return ""


## Сносит готовую постройку: возвращает половину затраченных материалов.
func demolish(p: Project) -> bool:
	if not demolish_error(p).is_empty():
		return false
	# Бур-лифт сносят целиком: бур и его лифт.
	if drill_lift_part(p):
		var partner := project_by_id(p.link_id)
		if partner != null and projects.has(partner):
			partner.link_id = 0
			p.link_id = 0
			if partner.phase == Project.Phase.DONE or partner.phase == Project.Phase.EQUIP:
				demolish(partner)
			else:
				cancel_project(partner)
	var spent := p.cost()
	if p.purpose != RoomType.NONE:
		var eq := RoomType.equip_cost(p.purpose, p)
		for k in eq:
			spent[k] = spent.get(k, 0) + eq[k]
	_refund(spent, 0.5)
	_return_delivered(p)
	_release_beds(p)
	projects.erase(p)
	_by_id_n = -1
	for c in p.cells():
		room_cells.erase(c)
		interior.erase(c)
		deck.erase(c)
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_restore_water_overlaps(p)
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s снесена, возвращено: %s" % [p.title(), _cost_line(spent, 0.5)], "info")
	physics.check_area(p.cells())
	return true


func _cost_line(cost: Dictionary, part: float) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append("%s %d" % [Mat.resource_name(k).to_lower(), int(floor(cost[k] * part))])
	return ", ".join(parts)


func _refund(cost: Dictionary, part: float) -> void:
	for k in cost:
		_add(k, int(floor(cost[k] * part)))


## Принесённые, но не израсходованные материалы уносят обратно на склад.
func _return_delivered(p: Project) -> void:
	for k in p.delivered:
		_add(k, p.delivered[k])
	p.delivered.clear()


# --- Доставка материалов ------------------------------------------------------------

## Крепь — из дерева, а нет его — из железа: оно прочнее, на срез его вдвое меньше.
## Чем крепят следующий срез: что уже принесли, иначе дерево, если его хватает, иначе железо.
func support_key(p: Project) -> String:
	var wood := p.slice_wood()
	var iron := support_amount(p, "iron")
	if int(p.delivered.get("wood", 0)) >= wood:
		return "wood"
	if int(p.delivered.get("iron", 0)) >= iron:
		return "iron"
	if int(inventory.get("wood", 0)) + drop_total("wood") + int(p.delivered.get("wood", 0)) >= wood:
		return "wood"
	# Железная крепь — после «Железного каркаса».
	if research.has("steel_frame") and int(inventory.get("iron", 0)) + int(p.delivered.get("iron", 0)) >= iron:
		return "iron"
	return "wood"


## Сколько материала key на крепь одного среза.
static func support_amount(p: Project, key: String) -> int:
	return ceili(p.slice_wood() / 2.0) if key == "iron" else p.slice_wood()


## Сколько дерева ещё уйдёт на крепь незакреплённых срезов (в «деревянных» единицах).
func support_wood_left(p: Project) -> int:
	if p.phase != Project.Phase.DIG:
		return 0
	var n := 0
	for i in p.needs_support:
		if not p.supported.has(i) and not (p.support_paid and p.support_slice == i):
			n += 1
	return n * p.slice_wood()


## Материалы, которые нужно принести на стройку для оставшихся работ (всего).
## Пока копают, носят дерево на крепь и заодно материалы на строительство (и на
## обустройство, если комнату заложили сразу под назначение).
func required(p: Project) -> Dictionary:
	var out := {}
	match p.phase:
		Project.Phase.DIG:
			if not (p.kind == Project.Kind.DRILL and p.paid):
				out = p.cost().duplicate()
			var sw := support_wood_left(p)
			if sw > 0:
				var key := support_key(p)
				var n := sw if key == "wood" else ceili(sw / 2.0)
				out[key] = out.get(key, 0) + n
			var plan := plan_cost(p)
			for k in plan:
				out[k] = out.get(k, 0) + plan[k]
		Project.Phase.BUILD:
			if not p.paid:
				out = p.cost().duplicate()
			var plan := plan_cost(p)
			for k in plan:
				out[k] = out.get(k, 0) + plan[k]
		Project.Phase.EQUIP:
			if not p.equip_paid:
				out = RoomType.job_cost(p).duplicate()
				for k in RoomType.PIPED:
					out.erase(k)
		Project.Phase.DONE:
			if p.repairing and not p.repair_paid:
				out = p.repair_need.duplicate()
	return out


## Материалы обустройства комнаты, заложенной сразу под назначение: их носят с начала
## копки, чтобы после постройки обустройство не ждало (топливо идёт по трубам — его нет).
func plan_cost(p: Project) -> Dictionary:
	if p.kind != Project.Kind.ROOM or p.plan_purpose <= 0:
		return {}
	var out := RoomType.equip_cost(p.plan_purpose, p).duplicate()
	for k in RoomType.PIPED:
		out.erase(k)
	return out


## Сколько ресурса key несут (или идут брать) на стройку p.
func in_transit(p: Project, key: String) -> int:
	var n := 0
	for u in units:
		if u.task == Unit.Task.HAUL and u.project_id == p.id and u.carry_key == key and u.gather_room == 0:
			n += u.carry_amount
	return n


## Что ещё осталось принести (без учёта того, что уже несут).
func remaining(p: Project) -> Dictionary:
	var out := {}
	var req := required(p)
	for k in req:
		var left: int = req[k] - p.delivered.get(k, 0) - in_transit(p, k)
		if left > 0:
			out[k] = left
	return out


## Плашки над стройкой: [[ресурс, принесено, нужно, есть откуда носить], ...].
func supply_status(p: Project) -> Array:
	var out := []
	var req := required(p)
	var keys := req.keys()
	keys.sort()
	for k in keys:
		var have: int = mini(p.delivered.get(k, 0), req[k])
		if have >= req[k]:
			continue
		var source: bool = inventory.get(k, 0) > 0 or in_transit(p, k) > 0 or drop_total(k) > 0
		out.append([k, have, req[k], source])
	return out


## Материалы, которые нужны прямо сейчас (этап встал без них).
## min_only — только то, без чего стройка стоит прямо сейчас (крепь текущего среза): по нему
## судят «Не хватает» и «Склад недоступен».
func _needed_now(p: Project, min_only := false) -> Dictionary:
	match p.phase:
		Project.Phase.DIG:
			# Крепь на всю стройку несут сразу (а не по срезу: пока несли бревно на очередной
			# срез, копка стояла). На текущий срез — сколько ему нужно, остальное — вперёд.
			var i := slice_to_support(p)
			if min_only:
				if i >= 0 and not (p.support_paid and p.support_slice == i):
					var k := support_key(p)
					return {k: support_amount(p, k)}
				return {}
			var left := support_wood_left(p)
			if left <= 0:
				return {}
			var key := support_key(p)
			var per := support_amount(p, key)
			var n := ceili(float(left) / p.slice_wood()) * per
			if i < 0 and int(p.delivered.get(key, 0)) >= n:
				return {}
			return {key: n}
		Project.Phase.BUILD:
			return p.cost() if not p.paid else {}
		Project.Phase.EQUIP:
			return RoomType.job_cost(p) if not p.equip_paid else {}
		Project.Phase.DONE:
			return p.repair_need if p.repairing and not p.repair_paid else {}
	return {}


## Хватит ли ресурсов вообще: на складе + несут + уже на месте.
func _check_supply(p: Project) -> void:
	var need := _needed_now(p, true)
	var lacking: PackedStringArray = []
	for k in need:
		var have: int = p.delivered.get(k, 0) + in_transit(p, k) + inventory.get(k, 0) + drop_total(k)
		if have < need[k]:
			lacking.append("%s %d" % [Mat.resource_name(k).to_lower(), need[k] - have])
	if lacking.is_empty():
		if p.blocked.begins_with("Не хватает"):
			p.blocked = ""
		return
	var msg := "Не хватает: " + ", ".join(lacking)
	if p.blocked != msg:
		p.blocked = msg
		_log("%s ждёт материалы. %s" % [p.title(), msg], "warning")


# --- Бур ------------------------------------------------------------------------------
## Бур — машина 3×3. Её ставят (место выкапывают), собирают из железа и меди, а потом
## в карточке велят пройти n м вниз, влево или вправо: бур сам едет и сверлит ход 3 м
## шириной втрое быстрее гаврика (на энергии, после «Двигателей внутреннего сгорания» — и на
## дизеле). За ним остаётся тоннель (вниз) или ход как шахта (вбок), где можно ставить лифт
## и комнаты. Дошёл — стоит в конце хода и ждёт нового приказа.
const DRILL_POWER := 10
## На сколько секунд сверления хватает 1 дизеля.
const DRILL_DIESEL_TIME := 30.0
const DRILL_SPEED := 3.0
## Без породы впереди бур проезжает метр за столько секунд.
const DRILL_MOVE_TIME := 1.0
const DRILL_MAX := 64
## Обсадка хода: 1 железо на столько метров (берут со склада при приказе).
const DRILL_CASING_M := 4


func drill_speed(diesel := false) -> float:
	return DRILL_SPEED * dig_bonus() * (2.0 if research.has("diamond_bits") else 1.0) \
		* (1.0 if diesel else clampf(power_ratio, 0.0, 1.0))


## Бур сверлит (едет по приказу).
func drilling(p: Project) -> bool:
	return p.kind == Project.Kind.DRILL and p.phase == Project.Phase.DONE and p.drill_left > 0


## Бур работает на энергии: сверлит и не на паузе.
func _drill_active(p: Project) -> bool:
	return drilling(p) and not p.paused


## Клетки хода на n м от бура в сторону dir.
static func drill_path(p: Project, dir: Vector2i, n: int) -> Rect2i:
	var r := p.rect
	if dir == Vector2i.DOWN:
		return Rect2i(r.position.x, r.end.y, r.size.x, n)
	if dir == Vector2i.LEFT:
		return Rect2i(r.position.x - n, r.position.y, n, r.size.y)
	return Rect2i(r.end.x, r.position.y, n, r.size.y)


## Следующий срез перед буром (клетки, куда он въедет).
func drill_front(p: Project) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not drilling(p):
		return out
	var r := drill_path(p, p.drill_dir, 1)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


func _underground(r: Rect2i) -> bool:
	for x in range(r.position.x, r.end.x):
		if r.position.y < world.gen.surface_y(x):
			return false
	return true


## Железо на обсадку хода длиной n.
static func drill_casing(n: int) -> int:
	return ceili(n / float(DRILL_CASING_M))


func drill_error(p: Project, dir: Vector2i, n: int) -> String:
	if p.kind != Project.Kind.DRILL or p.phase != Project.Phase.DONE:
		return "Бур ещё не собран"
	if drilling(p):
		return "Бур уже сверлит — сначала остановите"
	if not [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].has(dir):
		return "Бур сверлит вниз, влево или вправо"
	if p.link_id != 0 and dir != Vector2i.DOWN:
		return "Бур-лифт сверлит только вниз — лифт идёт следом"
	if p.link_id != 0:
		var lift := drill_lift_of(p)
		if lift == null or lift.phase != Project.Phase.DONE:
			return "Сначала достройте лифт бур-лифта"
	if n < 1 or n > DRILL_MAX:
		return "За раз — от 1 до %d м" % DRILL_MAX
	var path := drill_path(p, dir, n)
	if not _underground(path):
		return "Бурить можно только под землёй"
	for c in Project.rect_cells(path):
		var other := project_at(c)
		if other != null and other != p and not is_passage(other.kind):
			return "На пути постройка: %s" % other.title()
		if world.is_revealed(c.x, c.y) and Mat.is_fluid(world.get_mat(c.x, c.y)):
			return "На пути %s" % Mat.name_of(world.get_mat(c.x, c.y)).to_lower()
	var iron := drill_casing(n)
	if int(inventory.get("iron", 0)) < iron:
		return "Нужно %d железа на обсадку хода (на складе %d)" % [iron, int(inventory.get("iron", 0))]
	return ""


# --- Бур-лифт ----------------------------------------------------------------------------
## Бур-лифт 3×5: внизу бур 3×3, над ним грузовой лифт 3×2. Бурит только вниз; шахта лифта
## растёт следом за буром, а всё, что он выкопал, ждёт кабину у нижнего конца — лифт сам
## везёт наверх и выгружает на склад вплотную к верху лифта (нет склада — кладёт у лифта).
static func drill_lift_parts(r: Rect2i) -> Array[Rect2i]:
	return [Rect2i(r.position.x, r.position.y + 2, 3, 3), Rect2i(r.position.x, r.position.y, 3, 2)]


func drill_lift_error(r: Rect2i) -> String:
	if not research.has("drill_lift"):
		return "Сначала изучите «%s»" % Research.tech_name("drill_lift")
	if r.size != Vector2i(3, 5):
		return "Бур-лифт — 3×5: внизу бур, вверху лифт"
	var parts := drill_lift_parts(r)
	var err := validate(Project.Kind.DRILL, parts[0])
	if not err.is_empty():
		return err
	return validate(Project.Kind.LIFT, parts[1], "cargo_drill", false)


func create_drill_lift(r: Rect2i, workers := -1) -> Project:
	if not drill_lift_error(r).is_empty():
		return null
	var parts := drill_lift_parts(r)
	var drill := create_project(Project.Kind.DRILL, parts[0], workers)
	if drill == null:
		return null
	var lift := create_project(Project.Kind.LIFT, parts[1], workers, "cargo_drill", false)
	if lift == null:
		cancel_project(drill)
		return null
	drill.link_id = lift.id
	lift.link_id = drill.id
	# Место под бур-лифт копают гаврики, крепь не нужна: стенки держит корпус машины.
	for q in [drill, lift]:
		q.supported.clear()
		for i in q.slice_count():
			q.supported.append(i)
		q.needs_support.clear()
	return drill


## Копает машина, а не кирка: готовый бур, ход, который он сверлит, и готовый бур-лифт
## (бур и его лифт). Газ ей безразличен. Место под бур и бур-лифт копают гаврики — тут газ
## их останавливает, как на любой стройке.
func is_machine(p: Project) -> bool:
	return p.bored_by > 0 or ((p.kind == Project.Kind.DRILL or drill_lift_part(p)) and p.phase != Project.Phase.DIG)


## Часть бур-лифта: его бур или его лифт.
func drill_lift_part(p: Project) -> bool:
	return p.link_id != 0 and (p.kind == Project.Kind.DRILL or p.kind == Project.Kind.LIFT)


## Лифт бур-лифта (или null).
func drill_lift_of(p: Project) -> Project:
	if p.kind != Project.Kind.DRILL or p.link_id == 0:
		return null
	var q := project_by_id(p.link_id)
	return q if q != null and q.kind == Project.Kind.LIFT else null


## Бур-лифт сдвинулся вниз: шахта лифта дорастает до бура, выкопанное — в кабину.
func _drill_lift_step(p: Project) -> void:
	var lift := drill_lift_of(p)
	if lift == null:
		return
	lift.rect.size.y = maxi(2, p.rect.position.y - lift.rect.position.y)
	_drill_lift_collect(p, lift)
	_rebuild_climb()


## Столб бур-лифта: шахта его лифта, сам бур и три ряда под ним (туда скатывается и
## падает добытое). Что там лежит — забирает кабина, гаврики это не носят.
static func drill_lift_area(drill: Project, lift: Project) -> Rect2i:
	return lift.rect.merge(drill.rect).grow_individual(0, 0, 0, 3)


## Всё, что лежит в столбе бур-лифта (добытое, выгруженное), — в кабину у нижнего конца:
## наверх её везёт лифт, гаврики это не таскают.
func _drill_lift_collect(drill: Project, lift: Project) -> void:
	var area := drill_lift_area(drill, lift)
	for c: Vector2i in drops.keys():
		if not area.has_point(c):
			continue
		for k in drops[c].keys():
			# Пустая порода не нужна — её кабина не возит.
			if RoomType.BULK.has(k):
				continue
			var n := drop_amount(c, k) - _claimed_drop(c, k)
			if n > 0:
				lift.lift_buf[1][k] = int(lift.lift_buf[1].get(k, 0)) + _take_drop(c, k, n)


## Клетка в столбе бур-лифта: лежащее там гаврики не носят — его везёт лифт.
func in_drill_lift(c: Vector2i) -> bool:
	# Столбы бур-лифтов — раз в секунду игры (спрашивают про каждую кучу).
	if game_time - _dl_rects_t >= 1.0 or _dl_rects_t > game_time:
		_dl_rects_t = game_time
		_dl_rects.clear()
		for p in projects:
			if p.kind == Project.Kind.LIFT and p.link_id != 0 and p.phase == Project.Phase.DONE:
				var d := project_by_id(p.link_id)
				if d != null:
					_dl_rects.append(drill_lift_area(d, p))
	for r in _dl_rects:
		if r.has_point(c):
			return true
	return false


## Приказ буру: пройти n м в сторону dir. Ход сразу размечается тоннелем или шахтой.
func start_drill(p: Project, dir: Vector2i, n: int) -> String:
	var err := drill_error(p, dir, n)
	if not err.is_empty():
		return err
	_remove("iron", drill_casing(n))
	var path := drill_path(p, dir, n)
	# Бур стоит под землёй — его место тоже становится частью хода.
	var r := path.merge(p.rect) if _underground(p.rect) else path
	var q := Project.new()
	q.id = next_project_id
	next_project_id += 1
	q.kind = Project.Kind.TUNNEL if dir == Vector2i.DOWN else Project.Kind.MINE
	q.rect = r
	q.workers = 0
	q.bored_by = p.id
	q.paid = true
	for i in q.slice_count():
		q.supported.append(i)
	projects.append(q)
	p.drill_dir = dir
	p.drill_left = n
	p.drill_t = 0.0
	p.bore_id = q.id
	p.bore_from = p.rect
	p.hazard_ack.clear()
	p.blocked = ""
	_rebuild_climb()
	_log("%s: сверлим %d м %s" % [p.title(), n, {Vector2i.DOWN: "вниз", Vector2i.LEFT: "влево", Vector2i.RIGHT: "вправо"}[dir]], "info")
	return ""


func _drills_tick(dt: float) -> void:
	_probes_tick(dt)
	_drill_sight_t += dt
	if _drill_sight_t >= 1.0:
		_drill_sight_t = 0.0
		_drill_sight()
	for p: Project in projects.duplicate():
		if not drilling(p) or p.paused:
			continue
		var bore := project_by_id(p.bore_id)
		# Без энергии дизельный бур идёт на дизеле из нефтехранилища.
		var on_diesel := false
		if not powered() or power_ratio <= 0.0:
			if research.has("combustion") and (p.fuel > 0.0 or _remove("diesel", 1) >= 1):
				if p.fuel <= 0.0:
					p.fuel += DRILL_DIESEL_TIME
				on_diesel = true
			else:
				if p.blocked.is_empty():
					p.blocked = "Нет энергии — бур стоит" + (" (и дизеля нет)" if research.has("combustion") else "")
				continue
		if p.blocked.begins_with("Нет энергии") or p.blocked.begins_with("Впереди"):
			p.blocked = ""
		var front := drill_front(p)
		var solid: Array[Vector2i] = []
		var stop := false
		for c in front:
			var m := world.get_mat(c.x, c.y)
			if world.is_revealed(c.x, c.y) and Mat.is_fluid(m):
				p.blocked = "Впереди %s — бур стоит. Остановите его или откачайте" % Mat.name_of(m).to_lower()
				stop = true
				break
			if Mat.is_solid(m):
				solid.append(c)
		if stop:
			continue
		for c in solid:
			if _hazard_stop(p, c):
				stop = true
				break
		if stop:
			continue
		if on_diesel:
			p.fuel = maxf(0.0, p.fuel - dt)
		p.drill_t += dt * (drill_speed(true) if on_diesel else drill_speed())
		var need := DRILL_MOVE_TIME * DRILL_SPEED
		for c in solid:
			need = maxf(need, dig_time(c))
		if p.drill_t < need:
			continue
		p.drill_t = 0.0
		for c in solid:
			_complete_dig(c, bore, null)
		_machine_dug(solid)
		p.rect.position += p.drill_dir
		_drill_lift_step(p)
		p.drill_left -= 1
		if p.drill_left <= 0:
			_end_bore(p, true)


## Бур дошёл (или его остановили): пройденная часть хода готова, бур ждёт приказа.
func _end_bore(p: Project, arrived: bool) -> void:
	var bore := project_by_id(p.bore_id)
	var total := p.drill_left + absi(p.rect.position.x - p.bore_from.position.x) + absi(p.rect.position.y - p.bore_from.position.y)
	var went := total - p.drill_left
	p.drill_left = 0
	p.drill_dir = Vector2i.ZERO
	p.bore_id = 0
	p.blocked = ""
	if bore == null:
		return
	var r := bore.rect.intersection(p.bore_from.merge(p.rect))
	var old := bore.cells()
	if went <= 0 or r.size.x <= 0 or r.size.y <= 0:
		projects.erase(bore)
		_by_id_n = -1
		_rebuild_climb()
		_log("%s: остановлен, не пройдя ни метра" % p.title(), "info")
		return
	if bore.phase != Project.Phase.DONE:
		bore.rect = r
		bore.supported.clear()
		for i in bore.slice_count():
			bore.supported.append(i)
		_finish_project(bore)
	_log("%s %s %d м%s — готов %s" % [p.title(), "прошёл" if arrived else "остановлен:", went,
		"" if arrived else " из %d" % total,
		"тоннель (можно ставить лифт)" if bore.kind == Project.Kind.TUNNEL else "ход (как шахта: можно ставить комнаты и лифт)"], "good")
	var cut: Array[Vector2i] = []
	for c in old:
		if not bore.has_cell(c):
			cut.append(c)
	physics.check_area(cut)


## Остановить бур: пройденная часть остаётся ходом, бур стоит, где остановился.
func stop_drill(p: Project) -> void:
	if drilling(p):
		_end_bore(p, false)


## Бур (и бур-лифт) видит породу вокруг себя на дальность геологоразведки — и ту, что
## под ним, ещё не пройденную (раньше открывалось только при копке, и после новой
## «Геологоразведки» под буром оставалось тёмное).
var _drill_sight_t := 0.0


func _drill_sight() -> void:
	var r := see_radius()
	for p in projects:
		if p.kind != Project.Kind.DRILL or p.phase != Project.Phase.DONE:
			continue
		var area := p.rect.grow(r)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				if world.reveal(x, y):
					_note_discovery(world.get_mat(x, y), Vector2i(x, y))
					world.dirty[WorldData.chunk_of(x, y)] = true


# --- Геоскважина -----------------------------------------------------------------------
## Геоскважина 2×2: из её середины зонд уходит вниз, вверх, влево или вправо и открывает
## породу полосой (ширина — два радиуса, от оси зонда), ничего не копая: смотреть, есть ли
## там что-нибудь. Длина и полоса — по уровню технологии; скорость — как у алмазного бура.
## [технология, длина зонда, радиус обзора]
const PROBE_LEVELS := [["geoprobe", 20, 1], ["geoprobe2", 40, 2], ["geoprobe3", 60, 3]]
const PROBE_POWER := 5


## [длина, радиус] по изученному (пусто — не изучено).
func probe_level() -> Array:
	var out := []
	for lv in PROBE_LEVELS:
		if research.has(lv[0]):
			out = [lv[1], lv[2]]
	return out


## Зонд идёт.
func probing(p: Project) -> bool:
	return p.kind == Project.Kind.PROBE and p.phase == Project.Phase.DONE and p.drill_left > 0


func probe_error(p: Project, dir: Vector2i) -> String:
	if p.kind != Project.Kind.PROBE or p.phase != Project.Phase.DONE:
		return "Геоскважина ещё не собрана"
	if probing(p):
		return "Зонд уже идёт — сначала остановите"
	if not [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT].has(dir):
		return "Зонд идёт вниз, вверх, влево или вправо"
	if probe_level().is_empty():
		return "Сначала изучите «%s»" % Research.tech_name("geoprobe")
	return ""


func start_probe(p: Project, dir: Vector2i) -> String:
	var err := probe_error(p, dir)
	if not err.is_empty():
		return err
	p.drill_dir = dir
	p.drill_left = int(probe_level()[0])
	p.probe_done = 0
	p.drill_t = 0.0
	p.blocked = ""
	_log("%s: зонд пошёл %s на %d м" % [p.title(), _dir_word(dir), p.drill_left], "info")
	return ""


static func _dir_word(dir: Vector2i) -> String:
	return {Vector2i.DOWN: "вниз", Vector2i.UP: "вверх", Vector2i.LEFT: "влево", Vector2i.RIGHT: "вправо"}.get(dir, "")


## Клетки полосы обзора на метре i от края скважины (0 — первый): ширина — два радиуса,
## отсчёт от оси зонда (середины скважины 2×2).
static func probe_band(p: Project, dir: Vector2i, i: int, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := p.rect
	if dir.x == 0:
		var y := r.end.y + i if dir == Vector2i.DOWN else r.position.y - 1 - i
		var mid := r.position.x + r.size.x / 2
		for x in range(mid - radius, mid + radius):
			out.append(Vector2i(x, y))
	else:
		var x := r.end.x + i if dir == Vector2i.RIGHT else r.position.x - 1 - i
		var mid := r.position.y + r.size.y / 2
		for y in range(mid - radius, mid + radius):
			out.append(Vector2i(x, y))
	return out


func _probes_tick(dt: float) -> void:
	for p: Project in projects:
		if not probing(p) or p.paused:
			continue
		if not powered() or power_ratio <= 0.0:
			if p.blocked.is_empty():
				p.blocked = "Нет энергии — зонд стоит"
			continue
		if p.blocked.begins_with("Нет энергии"):
			p.blocked = ""
		var lv := probe_level()
		# Ось зонда (по ней — время: порода твёрже — дольше); поверх земли зонд не идёт.
		var axis := probe_band(p, p.drill_dir, p.probe_done, 1)
		if axis.any(func(c: Vector2i) -> bool: return c.y < world.gen.surface_y(c.x)):
			_end_probe(p, "вышел к поверхности")
			continue
		# Как алмазный бур: вдвое быстрее обычного, на энергии.
		p.drill_t += dt * DRILL_SPEED * dig_bonus() * 2.0 * clampf(power_ratio, 0.0, 1.0)
		var need := DRILL_MOVE_TIME * DRILL_SPEED
		for c in axis:
			if Mat.is_solid(world.get_mat(c.x, c.y)):
				need = maxf(need, dig_time(c))
		if p.drill_t < need:
			continue
		p.drill_t = 0.0
		for c in probe_band(p, p.drill_dir, p.probe_done, int(lv[1])):
			if world.reveal(c.x, c.y):
				_note_discovery(world.get_mat(c.x, c.y), c)
				world.dirty[WorldData.chunk_of(c.x, c.y)] = true
		p.probe_done += 1
		p.drill_left -= 1
		if p.drill_left <= 0:
			_end_probe(p, "")


## Зонд дошёл (или его остановили): итог — что видно в полосе.
func _end_probe(p: Project, why: String) -> void:
	var dir := p.drill_dir
	var went := p.probe_done
	p.drill_left = 0
	p.blocked = ""
	var lv := probe_level()
	var found := {}
	for i in went:
		for c in probe_band(p, dir, i, int(lv[1]) if not lv.is_empty() else 1):
			var m := world.get_mat(c.x, c.y)
			var key := Mat.resource(m)
			var what := ""
			if NOTABLE.has(key) or Mat.is_ore(m):
				what = Mat.name_of(m).to_lower()
			elif Mat.is_fluid(m):
				what = Mat.name_of(m).to_lower()
			elif Mat.hazard(m) == Mat.Hazard.GAS:
				what = "газоносный пласт"
			if not what.is_empty():
				found[what] = int(found.get(what, 0)) + 1
	var parts: PackedStringArray = []
	for k in found:
		parts.append("%s ×%d" % [k, found[k]])
	_log("%s: зонд прошёл %d м %s%s. %s" % [p.title(), went, _dir_word(dir), (" (" + why + ")") if not why.is_empty() else "",
		("Найдено: " + ", ".join(parts)) if not parts.is_empty() else "Ничего ценного — пустая порода"], "good" if not parts.is_empty() else "info")


## Остановить зонд: открытое остаётся открытым.
func stop_probe(p: Project) -> void:
	if probing(p):
		_end_probe(p, "остановлен")


# --- Нефть ----------------------------------------------------------------------------
## Нефтекачалка на энергии раз в OIL_PUMP_TIME выкачивает ближайшую клетку нефтеносного
## пласта в радиусе: +OIL_PER_CELL_YIELD нефти в хранилище, пласт становится пустым сланцем.
const OIL_PUMP_TIME := 15.0
const OIL_PER_CELL_YIELD := 3


func _oil_tick(dt: float) -> void:
	for p in rooms_of(RoomType.OIL_PUMP):
		if p.paused:
			continue
		if not powered() or power_ratio <= 0.0:
			p.blocked = "Нет энергии — качалка стоит"
			continue
		var free := 0
		for t in rooms_of(RoomType.OIL_TANK):
			free += room_free(t, "oil")
		if free <= 0:
			p.blocked = "Нефтехранилище полно или его нет — качалка стоит"
			continue
		p.farm_progress += dt * power_ratio
		if p.farm_progress < OIL_PUMP_TIME:
			continue
		p.farm_progress = 0.0
		var cell = _nearest_oil(p)
		if cell == null:
			p.blocked = "Рядом нет нефти (качает на %d м)" % RoomType.effect_radius(p)
			continue
		p.blocked = ""
		world.set_material(cell.x, cell.y, Mat.SHALE)
		_add("oil", OIL_PER_CELL_YIELD)
		produced["oil"] = int(produced.get("oil", 0)) + OIL_PER_CELL_YIELD


## Ближайшая к нефтекачалке клетка нефтеносного пласта в её радиусе.
func _nearest_oil(p: Project) -> Variant:
	var c0 := p.rect.get_center()
	var rad := RoomType.effect_radius(p)
	var best = null
	var best_d := 1 << 30
	for y in range(c0.y - rad, c0.y + rad + 1):
		for x in range(c0.x - rad, c0.x + rad + 1):
			if world.get_mat(x, y) == Mat.OIL:
				var d := absi(x - c0.x) + absi(y - c0.y)
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best


# --- Лифты -----------------------------------------------------------------------------
## Пассажирский: кабина на 6 человек, ездит втрое быстрее пешехода, останавливается только
## там, где садятся и выходят, и ждёт тех, кто уже идёт к ней. Грузовой: копит груз у конца,
## везёт к другому; у склада вплотную сам разгружается и сам берёт материалы для строек.
const LIFT_CAP := 6
const CARGO_CAP := 40
const LIFT_POWER := 5
## Сколько кабина ждёт подходящих к остановке, сек.
const LIFT_WAIT := 6.0
## Сколько грузовой ждёт, пока наберётся груз, сек.
const CARGO_WAIT := 8.0
## Бездельник без дела ищет работу не реже, чем раз в столько секунд.
const IDLE_RETRY_MAX := 12.0
## После стольких неудачных поисков работы (около 10 с) бездельник идёт домой.
const IDLE_HOME_AFTER := 4
## Ехать на лифте, только если по шахте не меньше стольких метров.
const LIFT_MIN_RIDE := 3
## Кабину ждут не дольше стольких секунд — потом лезут по аварийной лестнице и минуту
## (LIFT_SKIP) лифтом не пользуются.
const LIFT_GIVE_UP := 20.0
const LIFT_SKIP := 60.0
var _cargo_check_t := 0.0
var _wear_acc := 0.0
var _gas_hint_t := -100000.0
var _dl_rects: Array[Rect2i] = []
var _dl_rects_t := -1000.0
var _power_acc := 0.0
var _climb_sig := 0


func lifts() -> Array[Project]:
	var out: Array[Project] = []
	for p in projects:
		if p.kind == Project.Kind.LIFT and p.phase == Project.Phase.DONE:
			out.append(p)
	return out


## Лифт работает: есть энергия и он не на паузе.
func lift_powered(p: Project) -> bool:
	return not p.paused and powered() and power_ratio > 0.0


func lift_speed(p: Project) -> float:
	var s := WALK_SPEED * 3.0 * (2.0 if research.has("fast_lifts") else 1.0)
	return s * clampf(power_ratio, 0.0, 1.0)


## Координата клетки вдоль шахты лифта.
func _lift_axis(p: Project, c: Vector2i) -> int:
	return c.y if p.lift_vertical() else c.x


## Ось концов шахты: [начало (верх/лево), конец (низ/право)].
func _lift_ends(p: Project) -> Array:
	if p.lift_vertical():
		return [p.rect.position.y, p.rect.end.y - 1]
	return [p.rect.position.x, p.rect.end.x - 1]


func _passenger_lift_at(c: Vector2i) -> Project:
	var p: Project = _lift_cells.get(c)
	if p != null and p.kind == Project.Kind.LIFT and p.phase == Project.Phase.DONE and p.has_cell(c):
		return p
	return null


## Гаврик подошёл к лифту: если ехать по шахте далеко — встаёт ждать кабину.
func _try_board(u: Unit) -> bool:
	var nxt: Vector2i = u.path[u.path_i]
	var p := _passenger_lift_at(nxt)
	if p == null or not lift_powered(p) or game_time < u.no_lift_until:
		return false
	var j := u.path_i
	while j + 1 < u.path.size() and p.has_cell(u.path[j + 1]):
		j += 1
	if absi(_lift_axis(p, u.path[j]) - _lift_axis(p, nxt)) < LIFT_MIN_RIDE:
		return false
	u.lift_id = p.id
	u.riding = false
	u.lift_wait = 0.0
	u.lift_board = u.path_i
	u.lift_exit = j
	return true


## Выйти из лифта (или перестать ждать): дальше пешком по своему пути.
func _leave_lift(u: Unit, at_exit: bool) -> void:
	if at_exit:
		u.pos = Vector2(u.path[u.lift_exit])
		u.path_i = u.lift_exit + 1
	u.lift_id = 0
	u.riding = false
	u.lift_wait = 0.0


func _lifts_tick(dt: float) -> void:
	_cargo_check_t += dt
	var check := _cargo_check_t >= 2.0
	if check:
		_cargo_check_t = 0.0
	for p in lifts():
		var ends := _lift_ends(p)
		if p.lift_pos == Project.LIFT_UNSET:
			p.lift_pos = float(ends[1])
		if p.cargo:
			if check:
				_cargo_autoload(p)
				# Бур-лифт: всё, что лежит в его столбе, — в кабину.
				if p.link_id != 0 and p.phase == Project.Phase.DONE:
					var d := project_by_id(p.link_id)
					if d != null:
						_drill_lift_collect(d, p)
			# Грузовой возит и людей (вдвое больше): пока есть пассажиры — сначала они.
			if not _passenger_tick(p, dt):
				_cargo_tick(p, dt, ends)
		else:
			_passenger_tick(p, dt)


## Сколько человек берёт кабина: грузовая — вдвое больше.
func lift_cap(p: Project) -> int:
	return LIFT_CAP * (2 if p.cargo else 1)


## Возит пассажиров. false — пассажиров нет (грузовой тогда возит груз).
func _passenger_tick(p: Project, dt: float) -> bool:
	var riders: Array[Unit] = []
	var waiting: Array[Unit] = []
	for u in units:
		if u.lift_id == p.id:
			if u.state != Unit.State.MOVE or u.path_i > u.lift_exit or u.lift_exit >= u.path.size():
				_leave_lift(u, false)
			elif u.riding:
				riders.append(u)
			else:
				u.lift_wait += dt
				if u.lift_wait > LIFT_GIVE_UP:
					# Не дождался — по аварийной лестнице пешком.
					_leave_lift(u, false)
					u.no_lift_until = game_time + LIFT_SKIP
				else:
					waiting.append(u)
	if not lift_powered(p):
		# Без энергии кабина стоит: едущие выходят на аварийную лестницу, ждущие идут пешком.
		for u in riders + waiting:
			_leave_lift(u, false)
		return false
	if p.cargo and riders.is_empty() and waiting.is_empty():
		# Грузовой без пассажиров — возит груз (ожидание погрузки у него своё).
		p.lift_dir = 0
		return false
	var cap := lift_cap(p)
	var here := roundi(p.lift_pos)
	if absf(p.lift_pos - here) < 0.05:
		p.lift_pos = float(here)
		var stopped := false
		for u in riders.duplicate():
			if _lift_axis(p, u.path[u.lift_exit]) == here:
				_leave_lift(u, true)
				riders.erase(u)
				stopped = true
		for u in waiting.duplicate():
			if riders.size() < cap and _lift_axis(p, u.path[u.lift_board]) == here:
				u.riding = true
				u.pos = Vector2(u.path[u.lift_board])
				waiting.erase(u)
				riders.append(u)
				stopped = true
		# Кто уже идёт к этой остановке — кабина его ждёт (недолго и если есть место).
		if (stopped or p.lift_dwell > 0.0) and riders.size() < cap and p.lift_dwell < LIFT_WAIT and _approaching(p, here):
			p.lift_dwell += dt
			return true
	# Остановки: где выходят и (пока есть места) где ждут. Кабина едет в одну сторону, пока по
	# пути есть остановки, и подбирает попутных — как настоящий лифт (раньше везла по одному,
	# а остальные часами стояли в шахте).
	var stops: Array[int] = []
	for u in riders:
		stops.append(_lift_axis(p, u.path[u.lift_exit]))
	if riders.size() < cap:
		for u in waiting:
			stops.append(_lift_axis(p, u.path[u.lift_board]))
	if stops.is_empty():
		p.lift_dwell = 0.0
		p.lift_dir = 0
		return false
	var target := _next_stop(p, stops)
	if absf(float(target) - p.lift_pos) > 0.01:
		p.lift_dwell = 0.0
		var step := lift_speed(p) * dt
		p.lift_pos = move_toward(p.lift_pos, float(target), step)
	for u in riders:
		var c: Vector2i = u.path[u.lift_board]
		u.pos = Vector2(c.x, p.lift_pos) if p.lift_vertical() else Vector2(p.lift_pos, c.y)
	return true


## Ближайшая остановка по ходу кабины; впереди пусто — разворот.
func _next_stop(p: Project, stops: Array[int]) -> int:
	for turn in 2:
		var best := INF
		var out := 0
		for a in stops:
			var d := float(a) - p.lift_pos
			if p.lift_dir != 0 and absf(d) > 0.01 and signf(d) != p.lift_dir:
				continue
			if absf(d) < best:
				best = absf(d)
				out = a
		if best < INF:
			if absf(float(out) - p.lift_pos) > 0.01:
				p.lift_dir = int(signf(float(out) - p.lift_pos))
			return out
		p.lift_dir = -p.lift_dir
	return stops[0]


## Кто-то идёт к остановке here этого лифта и вот-вот сядет.
func _approaching(p: Project, here: int) -> bool:
	for u in units:
		if u.lift_id != 0 or u.state != Unit.State.MOVE:
			continue
		for i in range(u.path_i, mini(u.path.size(), u.path_i + 8)):
			var c: Vector2i = u.path[i]
			if p.has_cell(c):
				if _lift_axis(p, c) == here:
					return true
				break
	return false


## Площадка у конца грузового лифта: где стоят, кладя груз, и куда он выгружает.
func lift_station(p: Project, end: int) -> Variant:
	var ends := _lift_ends(p)
	var slice := Rect2i(p.rect.position.x, ends[end], p.rect.size.x, 1) if p.lift_vertical() \
		else Rect2i(ends[end], p.rect.position.y, 1, p.rect.size.y)
	# У бур-лифта низ шахты — сам бур: выгруженное там кабина подбирала обратно наверх
	# (материалы ездили по кругу). Площадка — первый выход из шахты выше бура.
	var skip := Rect2i()
	if p.link_id != 0:
		var d := project_by_id(p.link_id)
		if d != null:
			skip = drill_lift_area(d, p)
	var best = null
	for c in _rect_cells(slice.grow(1)):
		if p.has_cell(c) or not pathing.node(c) or skip.has_point(c):
			continue
		if best == null or absi(_lift_axis(p, c) - ends[end]) < absi(_lift_axis(p, best) - ends[end]):
			best = c
	if best != null:
		return best
	# У самого конца выхода нет — ближайший выход вдоль шахты; рядом (в 6 м) выход в
	# комнату или на стройку лучше, чем в пустую пещеру по другую сторону шахты.
	var step := 1 if end == 0 else -1
	var fallback = null
	var until := 0
	for i in range(1, absi(ends[1] - ends[0]) + 1):
		if fallback != null and i > until:
			break
		var axis: int = ends[end] + i * step
		var sides := [Vector2i(p.rect.position.x - 1, axis), Vector2i(p.rect.end.x, axis)] if p.lift_vertical() \
			else [Vector2i(axis, p.rect.position.y - 1), Vector2i(axis, p.rect.end.y)]
		for c: Vector2i in sides:
			if not pathing.node(c) or skip.has_point(c):
				continue
			var q := project_at(c)
			if q != null and q != p and q.kind == Project.Kind.ROOM:
				return c
			if fallback == null:
				fallback = c
				until = i + 6
	return fallback


func _rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


## Склады и амбары вплотную к концу end грузового лифта.
func lift_stores(p: Project, end: int) -> Array[Project]:
	var ends := _lift_ends(p)
	var slice := Rect2i(p.rect.position.x, ends[end], p.rect.size.x, 1) if p.lift_vertical() \
		else Rect2i(ends[end], p.rect.position.y, 1, p.rect.size.y)
	var out: Array[Project] = []
	for room in store_rooms():
		if room.rect.intersects(slice.grow(1)) and store_staffed(room):
			out.append(room)
	return out


func _load_total(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _cargo_tick(p: Project, dt: float, ends: Array) -> void:
	if not lift_powered(p):
		return
	if p.lift_goal >= 0:
		# В пути к концу lift_goal; приехал — выгружает.
		p.lift_pos = move_toward(p.lift_pos, float(ends[p.lift_goal]), lift_speed(p) * dt)
		if absf(p.lift_pos - ends[p.lift_goal]) < 0.01:
			var arrived := p.lift_goal
			p.lift_pos = float(ends[arrived])
			p.lift_goal = -1
			p.lift_dwell = 0.0
			if not p.lift_load.is_empty():
				_cargo_unload(p, arrived)
		return
	var at := 0 if absf(p.lift_pos - ends[0]) <= absf(p.lift_pos - ends[1]) else 1
	if absf(p.lift_pos - ends[at]) > 0.01:
		# Отвезла людей и встала между концами — сначала к ближнему концу.
		p.lift_pos = move_toward(p.lift_pos, float(ends[at]), lift_speed(p) * dt)
		return
	p.lift_pos = float(ends[at])
	var other := 1 - at
	# Берёт то, что ждёт у этого конца.
	var buf: Dictionary = p.lift_buf[at]
	for k in buf.keys():
		var space := CARGO_CAP - _load_total(p.lift_load)
		if space <= 0:
			break
		var n := mini(space, int(buf[k]))
		p.lift_load[k] = int(p.lift_load.get(k, 0)) + n
		buf[k] = int(buf[k]) - n
		if buf[k] <= 0:
			buf.erase(k)
	var load_n := _load_total(p.lift_load)
	if load_n > 0:
		p.lift_dwell += dt
	# Едет, когда набралось полкабины, или подождав, или за грузом с того конца.
	if load_n >= CARGO_CAP / 2 or (load_n > 0 and p.lift_dwell >= CARGO_WAIT) \
			or (load_n == 0 and _load_total(p.lift_buf[other]) > 0):
		p.lift_goal = other
		p.lift_dwell = 0.0


func _cargo_unload(p: Project, end: int) -> void:
	var stores := lift_stores(p, end)
	var spot = lift_station(p, end)
	for k in p.lift_load.keys():
		var n := int(p.lift_load[k])
		# Стройкам у этого конца — сразу в стройку (раньше клал на площадку, а она могла
		# оказаться по другую сторону шахты — материалы лежали, гаврик ходил переносить).
		for q in projects:
			if n <= 0:
				break
			if q == p or not _needs_key(q, k) or not _lift_serves(p, 1 - end, q):
				continue
			var give := mini(n, int(required(q).get(k, 0)) - int(q.delivered.get(k, 0)))
			if give > 0:
				q.delivered[k] = int(q.delivered.get(k, 0)) + give
				n -= give
				_try_pay(q)
		for room in stores:
			if n <= 0:
				break
			if RoomType.stores(room, k):
				n -= _add(k, n, room)
		if n > 0:
			if spot != null:
				drop_item(spot, k, n)
			else:
				_add(k, n)
	p.lift_load.clear()


## Склад вплотную к концу грузового лифта: материалы для строек у другого конца
## лифт сам берёт со склада и везёт (их там разносят уже недалеко).
func _cargo_autoload(p: Project) -> void:
	if not lift_powered(p):
		return
	for e in 2:
		var stores := lift_stores(p, e)
		if stores.is_empty():
			continue
		var far = lift_station(p, 1 - e)
		if far == null:
			continue
		for q in projects:
			if q.paused or q == p or (q.phase == Project.Phase.DONE and not q.repairing) or q.blocked == UNDER_DRILL:
				continue
			if not _lift_serves(p, e, q):
				continue
			# Несущих издалека (со склада наверху, через лифты — минуты) не ждём: лифт
			# везёт сам, а кто ещё только идёт за этим на склад — свободен. Считаются только
			# те, кто разносит уже привезённое с площадки.
			var req := required(q)
			for k in req:
				var want: int = int(req[k]) - int(q.delivered.get(k, 0)) - drop_amount(far, k) \
					- int(p.lift_buf[e].get(k, 0)) - int(p.lift_load.get(k, 0))
				for u in units:
					if u.task == Unit.Task.HAUL and u.project_id == q.id and u.carry_key == k and u.gather_room == 0:
						if u.from_drop or u.haul_stage == 1:
							want -= u.carry_amount
				if want <= 0:
					continue
				var loaded := 0
				for room in stores:
					if want <= 0:
						break
					var got := _remove(k, mini(want, held_in(room, k)), room)
					if got > 0:
						p.lift_buf[e][k] = int(p.lift_buf[e].get(k, 0)) + got
						want -= got
						loaded += got
				if loaded > 0:
					for u in units:
						if u.task == Unit.Task.HAUL and u.project_id == q.id and u.carry_key == k \
								and not u.from_drop and u.haul_stage == 0 and u.gather_room == 0:
							_drop(u)


## Стройка q у дальнего от конца e края грузового лифта p (не дальше 25 м от его площадки и
## ближе, чем к этому концу): материалы ей лифт сам берёт со склада у конца e.
func _lift_serves(p: Project, e: int, q: Project) -> bool:
	var far = lift_station(p, 1 - e)
	if far == null:
		return false
	var d: Vector2i = q.rect.get_center() - (far as Vector2i)
	if absi(d.x) + absi(d.y) > 25:
		return false
	var near = lift_station(p, e)
	if near != null:
		var dn: Vector2i = q.rect.get_center() - (near as Vector2i)
		if absi(dn.x) + absi(dn.y) <= absi(d.x) + absi(d.y):
			return false
	return true


## Ресурс key стройке q довезёт грузовой лифт со склада у своего конца — со склада его
## руками не носят (раньше гаврик успевал унести дерево по лестнице раньше лифта).
func lift_feeds(q: Project, key: String) -> bool:
	for p in lifts():
		if not p.cargo or not lift_powered(p) or p == q:
			continue
		for e in 2:
			for room in lift_stores(p, e):
				if held_in(room, key) > 0 and _lift_serves(p, e, q):
					return true
	return false


## Куда выгоднее отнести груз с кучи: в грузовой лифт, если у другого его конца есть
## склад с местом и до лифта ближе, чем до склада. [площадка, лифт, конец] или null.
func _cargo_route(key: String, dist: Dictionary, direct_d: int, only: Project = null) -> Variant:
	var best = null
	var best_d := direct_d - 4
	for p in lifts():
		if not p.cargo or not lift_powered(p):
			continue
		for e in 2:
			var ok := false
			for room in lift_stores(p, 1 - e):
				if (only == null or room == only) and RoomType.stores(room, key) and room_free(room, key) > 0:
					ok = true
			if not ok:
				continue
			var st = lift_station(p, e)
			if st != null and dist.has(st) and dist[st] < best_d:
				best_d = dist[st]
				best = [st, p, e]
	return best


## Где можно лазить (pathing.ladders, pathing.sites): лестницы готовых построек и леса строек.
var _lift_cells := {}


## Путь лезет по лестнице, а рядом есть лифт под током (грузовой тоже возит людей) — ищем путь «по
## времени»: через лифт может быть быстрее, хоть и больше клеток (раньше ползли по лестнице
## мимо лифта, до которого внизу был тоннель).
const LIFT_ROUTE_CLIMB := 6


func _lift_route(start: Vector2i, goal: Vector2i, path: Array[Vector2i]) -> Array[Vector2i]:
	if _lift_cells.is_empty() or path.size() < LIFT_ROUTE_CLIMB:
		return path
	var climb := 0
	var prev := start
	for c in path:
		if c.x == prev.x and c.y != prev.y:
			climb += 1
		prev = c
	if climb < LIFT_ROUTE_CLIMB:
		return path
	var lift := {}
	for c: Vector2i in _lift_cells:
		if lift_powered(_lift_cells[c]):
			lift[c] = true
	if lift.is_empty():
		return path
	var fast := pathing.timed_path(start, goal, lift)
	return fast if not fast.is_empty() else path


## Всё, от чего зависят лестницы, леса и полы: порода, постройки и их стадии.
func _climb_signature() -> int:
	var a := [world.revision, interior.size(), room_cells.size(), deck.size(), projects.size()]
	for p in projects:
		a.append(p.id)
		a.append(p.phase)
		a.append(p.rect)
		a.append(p.ladder)
		a.append(p.equip_ladder)
		a.append(p.supported.size())
	return hash(a)


func _rebuild_climb() -> void:
	var lad := {}
	var site := {}
	for p in projects:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			for c in p.cells():
				site[c] = true
			if p.kind == Project.Kind.TUNNEL or p.kind == Project.Kind.MINE or p.kind == Project.Kind.LIFT:
				_scaffold_down(p, lad)
	for p in projects:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			continue
		match p.kind:
			Project.Kind.TUNNEL, Project.Kind.MINE, Project.Kind.LIFT:
				# Вертикальный тоннель — с лестницей; горизонтальный и шахта — только по полу.
				# В шахте лифта (и грузового тоже) — аварийная лестница: при нужде по ней лазают.
				if p.rect.size.y > p.rect.size.x or (p.kind == Project.Kind.LIFT and p.lift_vertical()):
					for c in p.cells():
						lad[c] = true
				# Шахта (горизонтальный ход) прямо под другой выработкой: пока копали, туда
				# вели леса; после — постоянная лестница, иначе внизу остались бы запертыми.
				if p.kind != Project.Kind.LIFT and p.rect.size.x >= p.rect.size.y:
					var top := p.rect.position.y - 1
					for x in range(p.rect.position.x, p.rect.end.x):
						var a := Vector2i(x, top)
						if interior.has(a) and interior[a] != p.id and not room_cells.has(a) and world.is_open(x, top):
							lad[a] = true
							for y in range(p.rect.position.y, p.rect.end.y):
								lad[Vector2i(x, y)] = true
							break
			Project.Kind.ROOM:
				for side in [-1, 1]:
					if edge_ladder(p, side, site):
						var x := p.rect.position.x if side < 0 else p.rect.end.x - 1
						for y in range(p.rect.position.y, p.rect.end.y):
							lad[Vector2i(x, y)] = true
	# Шахта над шахтой: верхний ряд нижней закреплён балками — по ним ходят, как по полу.
	var fl := {}
	for p in projects:
		if p.kind == Project.Kind.MINE and p.phase == Project.Phase.DONE:
			for x in range(p.rect.position.x, p.rect.end.x):
				var a := Vector2i(x, p.rect.position.y - 1)
				if interior.has(a) and interior[a] != p.id:
					fl[a] = true
		# Шахта и горизонтальный тоннель над пещерой: пол на крепи — из них не проваливаются.
		var flat := p.kind == Project.Kind.MINE or (p.kind == Project.Kind.TUNNEL and not p.vertical())
		if flat:
			for i in p.slice_count():
				if p.phase != Project.Phase.DONE and not p.supported.has(i):
					continue
				for c in p.slice_cells(i):
					if c.y == p.rect.end.y - 1 and not Mat.is_solid(world.get_mat(c.x, c.y + 1)):
						fl[c] = true
	# У построенной комнаты свой пол: под ней выкопали тоннель или осыпалась земля — по
	# комнате всё равно ходят (раньше пол печи над тоннелем «пропадал» и отрезал склад).
	for p in projects:
		if p.kind == Project.Kind.ROOM and (p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP):
			var y := p.rect.end.y - 1
			for x in range(p.rect.position.x, p.rect.end.x):
				if not Mat.is_solid(world.get_mat(x, y + 1)):
					fl[Vector2i(x, y)] = true
			# И крыша над стенами: стена держит, по ней ходят. Иначе комната в склоне
			# оставляла над стеной щель-обрыв, и жители по ту сторону оказывались отрезаны.
			for x in [p.rect.position.x, p.rect.end.x - 1]:
				var a := Vector2i(x, p.rect.position.y - 1)
				if world.is_open(a.x, a.y) and not interior.has(a) and not room_cells.has(a):
					fl[a] = true
	# Клетки лифтов (грузовой тоже возит людей): у какой клетки садиться в кабину.
	_lift_cells.clear()
	for p in projects:
		if p.kind == Project.Kind.LIFT and p.phase == Project.Phase.DONE:
			for c in p.cells():
				_lift_cells[c] = p
	if lad != pathing.ladders or site != pathing.sites or fl != pathing.floors:
		pathing.ladders.clear()
		pathing.ladders.merge(lad)
		pathing.sites.clear()
		pathing.sites.merge(site)
		pathing.floors.clear()
		pathing.floors.merge(fl)
		pathing.climb_rev += 1


## Леса стройки, начатой из готовой выработки (тоннель у свода шахты): от открытых клеток
## стройки — лестница вниз до пола той выработки, чтобы до забоя было долезть.
const SCAFFOLD_DEPTH := 4


func _scaffold_down(p: Project, lad: Dictionary) -> void:
	for c in p.cells():
		if not world.is_open(c.x, c.y) or not interior.has(c) and not interior.has(c + Vector2i.DOWN):
			continue
		if p.rect.has_point(c + Vector2i.DOWN) and not interior.has(c + Vector2i.DOWN):
			continue
		if interior.has(c):
			lad[c] = true
		var d := c + Vector2i.DOWN
		for i in SCAFFOLD_DEPTH:
			if not world.is_open(d.x, d.y) or not interior.has(d) or room_cells.has(d):
				break
			lad[d] = true
			d += Vector2i.DOWN


## Лестница у стены комнаты (side -1 — левой, 1 — правой): построенная (или строится),
## у стены в склоне (снаружи у пола порода, вверху открыто) или к постройке прямо над ней.
func edge_ladder(p: Project, side: int, site = null) -> bool:
	if site == null:
		site = pathing.sites
	if side < 0 and (p.ladder or p.equip_ladder):
		return true
	var xo := p.rect.position.x - 1 if side < 0 else p.rect.end.x
	if not world.is_open(xo, p.rect.end.y - 1) and world.is_open(xo, p.rect.position.y):
		return true
	var above := Vector2i(p.rect.position.x if side < 0 else p.rect.end.x - 1, p.rect.position.y - 1)
	return interior.has(above) or room_cells.has(above) or site.has(above)


## Пока комнату копают, в ней леса — по ним можно лазить. Потом ходят по полу;
## у заглублённой комнаты остаётся лестница у левой стены.
func _register_room(p: Project) -> void:
	if p.kind != Project.Kind.ROOM or p.phase == Project.Phase.DIG:
		return
	# Крайние столбцы — лестницы у стен: из комнаты в склоне всегда можно выбраться.
	for c in p.cells():
		if c.x != p.rect.position.x and c.x != p.rect.end.x - 1:
			room_cells[c] = p.id


## Клетка под закреплённым срезом идущей стройки.
func cell_supported(c: Vector2i) -> bool:
	var p := project_at(c)
	return p != null and (p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD) and p.cell_supported(c)


## Срезы, начатые и ещё не закреплённые (в них уже копают).
func active_slices(p: Project) -> Array[int]:
	var out: Array[int] = []
	for i in p.needs_support:
		if p.supported.has(i):
			continue
		for c in p.slice_cells(i):
			if reserved.has(c) or (world.is_open(c.x, c.y) and not world.get_mat(c.x, c.y) == Mat.WATER):
				out.append(i)
				break
	return out


## --- Продолжение выработок ------------------------------------------------------------
## Готовую шахту, тоннель или лифт продлевают на n м: рядом закладывается продолжение
## (копают, крепят, у лифта — тянут рельсы), а готовое сливается с исходной постройкой.
const EXTEND_MAX := 64


## Куда можно продлить: вертикальное — вниз, горизонтальное — влево и вправо.
static func extend_dirs(p: Project) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if p.kind != Project.Kind.MINE and p.kind != Project.Kind.TUNNEL and p.kind != Project.Kind.LIFT:
		return out
	# Шахта всегда горизонтальная (3 м в высоту) — даже короткая 2×3 продлевается вбок.
	if p.kind != Project.Kind.MINE and p.rect.size.y > p.rect.size.x:
		out.append(Vector2i.DOWN)
	else:
		out.append_array([Vector2i.LEFT, Vector2i.RIGHT])
	return out


static func extend_rect(p: Project, dir: Vector2i, n: int) -> Rect2i:
	var r := p.rect
	if dir == Vector2i.DOWN:
		return Rect2i(r.position.x, r.end.y, r.size.x, n)
	if dir == Vector2i.LEFT:
		return Rect2i(r.position.x - n, r.position.y, n, r.size.y)
	return Rect2i(r.end.x, r.position.y, n, r.size.y)


func extension_of(p: Project) -> Project:
	for q in projects:
		if q.extends_id == p.id and q.phase != Project.Phase.DONE:
			return q
	return null


func extend_error(p: Project, dir: Vector2i, n: int) -> String:
	if not extend_dirs(p).has(dir):
		return "Эту постройку так не продлить"
	if p.phase != Project.Phase.DONE:
		return "Сначала достройте"
	if extension_of(p) != null:
		return "Продолжение уже строится"
	if n < 1 or n > EXTEND_MAX:
		return "Продлить можно на 1–%d м за раз" % EXTEND_MAX
	return validate(p.kind, extend_rect(p, dir, n), "cargo" if p.cargo else "wood", false)


func extend_project(p: Project, dir: Vector2i, n: int) -> Project:
	if not extend_error(p, dir, n).is_empty():
		return null
	var q := create_project(p.kind, extend_rect(p, dir, n), p.workers, "cargo" if p.cargo else "wood", false)
	if q == null:
		return null
	q.extends_id = p.id
	_log("%s: продлеваем на %d м" % [p.title(), n], "info")
	return q


## Готовое продолжение сливается с исходной постройкой (если та цела и они вплотную).
func _merge_extension(q: Project) -> bool:
	var host := project_by_id(q.extends_id)
	if host == null or host.kind != q.kind or host.phase != Project.Phase.DONE:
		return false
	var merged := host.rect.merge(q.rect)
	if merged.get_area() != host.rect.get_area() + q.rect.get_area():
		return false
	_return_delivered(q)
	for u in units:
		if u.project_id == q.id:
			_drop(u)
	projects.erase(q)
	_by_id_n = -1
	host.rect = merged
	host.needs_support.clear()
	host.supported.clear()
	for i in host.slice_count():
		host.supported.append(i)
	for k in q.found:
		host.found[k] = int(host.found.get(k, 0)) + int(q.found[k])
	for c in host.cells():
		interior[c] = host.id
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	highest_y = mini(highest_y, host.rect.position.y)
	_rebuild_climb()
	_log("Продлено: %s" % host.title(), "good")
	if host.kind == Project.Kind.LIFT:
		_merge_lifts(host)
	return true


## Лифты встык (одного вида и сечения, по одной оси) соединяются в один: одна кабина
## на всю шахту. Кто ждал или ехал в убранной кабине, идёт дальше пешком; её груз выгружают.
func _merge_lifts(p: Project) -> void:
	var merged := true
	while merged:
		merged = false
		for q in projects:
			if q == p or q.kind != Project.Kind.LIFT or q.phase != Project.Phase.DONE or q.cargo != p.cargo \
					or q.lift_vertical() != p.lift_vertical() or q.repairing:
				continue
			var r := p.rect.merge(q.rect)
			var same := (r.size.x == p.rect.size.x and r.position.x == p.rect.position.x) if p.lift_vertical() \
				else (r.size.y == p.rect.size.y and r.position.y == p.rect.position.y)
			if not same or r.get_area() != p.rect.get_area() + q.rect.get_area():
				continue
			for u in units:
				if u.lift_id == q.id:
					_drop(u)
			var spill := q.lift_load.duplicate()
			for b in q.lift_buf:
				for k in b:
					spill[k] = int(spill.get(k, 0)) + int(b[k])
			for k in spill:
				drop_item(q.rect.get_center(), k, int(spill[k]))
			projects.erase(q)
			_by_id_n = -1
			p.rect = r
			p.wear = maxf(p.wear, q.wear)
			p.lift_goal = -1
			p.supported.clear()
			for i in p.slice_count():
				p.supported.append(i)
			for c in p.cells():
				interior[c] = p.id
			merged = true
			_log("Лифты соединены: %s" % p.title(), "good")
			break
	_rebuild_climb()


## --- Шахта: строится по метру -------------------------------------------------------

## Метр шахты готов: выкопан и, если нужно, закреплён.
func mine_meter_done(p: Project, i: int) -> bool:
	return slice_dug(p, i) and (not p.needs_support.has(i) or p.supported.has(i))


func mine_meters_done(p: Project) -> int:
	var n := 0
	for i in p.slice_count():
		if mine_meter_done(p, i):
			n += 1
	return n


## Остановить шахту: готовые метры (самый длинный сплошной участок) становятся готовой
## шахтой, остальное отменяется. Ничего не готово — стройка просто отменяется.
func stop_mine(p: Project) -> void:
	var best_a := -1
	var best_n := 0
	var a := -1
	for i in p.slice_count():
		if mine_meter_done(p, i):
			if a < 0:
				a = i
			if i - a + 1 > best_n:
				best_n = i - a + 1
				best_a = a
		else:
			a = -1
	if best_n == 0:
		cancel_project(p)
		return
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	# Крепь, за которую уже заплатили, но не поставили, — дерево обратно.
	if p.support_paid and not p.supported.has(p.support_slice):
		var mat := p.support_mat if not p.support_mat.is_empty() else "wood"
		p.delivered[mat] = int(p.delivered.get(mat, 0)) + support_amount(p, mat)
	p.support_slice = -1
	p.support_paid = false
	var old := p.cells()
	var total := p.slice_count()
	if p.vertical():
		# Вертикальный тоннель крепят по 2 ряда.
		p.rect = Rect2i(p.rect.position.x, p.rect.position.y + best_a * 2, p.rect.size.x,
			mini(best_n * 2, p.rect.size.y - best_a * 2))
	else:
		p.rect = Rect2i(p.rect.position.x + best_a, p.rect.position.y, best_n, p.rect.size.y)
	var ns: Array[int] = []
	var sp: Array[int] = []
	for i in p.needs_support:
		if i >= best_a and i < best_a + best_n:
			ns.append(i - best_a)
	for i in p.supported:
		if i >= best_a and i < best_a + best_n:
			sp.append(i - best_a)
	p.needs_support = ns
	p.supported = sp
	p.clear_x.clear()
	_finish_project(p)
	_log("%s остановлена: готово %d м из %d" % [p.title(), best_n, total], "info")
	var cut: Array[Vector2i] = []
	for c in old:
		if not p.has_cell(c):
			cut.append(c)
	physics.check_area(cut)


## Сколько метров моста уже построено (строят от берега ближе к базе).
func bridge_meters_done(p: Project) -> int:
	if p.kind != Project.Kind.BRIDGE or p.phase != Project.Phase.BUILD or not p.paid:
		return 0
	return mini(p.rect.size.x, floori(p.build_done / (p.build_work() / p.rect.size.x) + 0.001))


## Мост строят от этого края (true — от правого).
func bridge_from_right(p: Project) -> bool:
	return absi(p.rect.end.x - 1 - home.x) < absi(p.rect.position.x - home.x)


## Остановить мост: построенная часть у берега остаётся пристанью, дерево за
## непостроенное — обратно.
func stop_bridge(p: Project) -> void:
	var m := bridge_meters_done(p)
	var total := p.rect.size.x
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_refund(p.cost(), 1.0 - float(m) / total)
	var right := bridge_from_right(p)
	var old := p.cells()
	p.rect = Rect2i(p.rect.end.x - m if right else p.rect.position.x, p.rect.position.y, m, p.rect.size.y)
	p.kind = Project.Kind.PIER
	for c in old:
		if not p.has_cell(c):
			deck.erase(c)
	_finish_project(p)
	_log("Мост остановлен: готово %d м из %d — стоит пристанью у берега" % [m, total], "info")


## Срез выкопан целиком.
func slice_dug(p: Project, i: int) -> bool:
	for c in p.slice_cells(i):
		if Mat.is_solid(world.get_mat(c.x, c.y)):
			return false
	return true


## Выкопанный, но не закреплённый срез (ждёт крепь), иначе -1.
func slice_to_support(p: Project) -> int:
	if p.support_slice >= 0 and not p.supported.has(p.support_slice):
		return p.support_slice
	for i in active_slices(p):
		if slice_dug(p, i):
			return i
	return -1


## Ставит на крепь среза принесённое дерево. false — дерево ещё не принесли.
func _pay_support(p: Project, i: int) -> bool:
	if p.support_paid and p.support_slice == i:
		return true
	var mat := ""
	for k in ["wood", "iron"]:
		if int(p.delivered.get(k, 0)) >= support_amount(p, k):
			mat = k
			break
	if mat.is_empty():
		return false
	p.delivered[mat] -= support_amount(p, mat)
	if p.delivered[mat] <= 0:
		p.delivered.erase(mat)
	p.support_mat = mat
	p.support_slice = i
	p.support_paid = true
	p.support_progress = 0.0
	return true


func _finish_support(p: Project) -> void:
	p.supported.append(p.support_slice)
	p.support_slice = -1
	p.support_paid = false
	p.support_progress = 0.0
	for c in p.cells():
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	for u in units:
		if u.task == Unit.Task.SUPPORT and u.project_id == p.id:
			_drop(u)
		# Кто ждал у этой выработки — сразу за следующий срез.
		elif u.waiting_own and u.last_project == p.id and u.state == Unit.State.IDLE:
			u.retry = 0.0
	_check_phase(p)


## Клетки, которые можно копать сейчас: в начатом срезе, пока он не закреплён, а когда он
## выкопан и ждёт крепь — уже и в соседнем (раньше копатели стояли, пока ставят крепь, и
## уходили на другую работу; незакреплённых срезов — не больше двух).
func diggable_now(p: Project) -> Array[Vector2i]:
	var all := remaining_dig(p)
	var active := active_slices(p)
	if active.is_empty():
		return all
	var allowed := active.duplicate()
	if active.size() == 1 and slice_dug(p, active[0]):
		for j in [active[0] - 1, active[0] + 1]:
			if p.needs_support.has(j) and not p.supported.has(j):
				allowed.append(j)
	var out: Array[Vector2i] = []
	for c in all:
		if allowed.has(p.slice_of(c)) and not slice_dug(p, p.slice_of(c)):
			out.append(c)
	return out


func remaining_dig(p: Project) -> Array[Vector2i]:
	# Пока порода не менялась — тот же список (его спрашивают при каждом поиске работы).
	if p.dig_rev == world.revision and p.dig_rect == p.rect:
		return p.dig_left
	var out: Array[Vector2i] = []
	for c in p.cells():
		if Mat.is_solid(world.get_mat(c.x, c.y)):
			out.append(c)
	p.dig_rev = world.revision
	p.dig_rect = p.rect
	p.dig_left = out
	return out


## Базовое время копки клетки (для гаврика с навыком 1).
func dig_time(c: Vector2i) -> float:
	var m := world.get_mat(c.x, c.y)
	var t := Mat.hardness(m) * Env.heat_work_factor(world.gen.temperature(c.y, world.gen.surface_y(c.x)))
	# Порода с полезными ископаемыми добывается аккуратнее — дольше.
	if NOTABLE.has(Mat.resource(m)):
		t *= 1.4
	return t


func _check_phase(p: Project) -> void:
	if p.phase != Project.Phase.DIG:
		return
	_check_liquids(p)
	var all_supported := true
	for i in p.needs_support:
		if not p.supported.has(i):
			all_supported = false
	if remaining_dig(p).is_empty() and uncleared(p).is_empty() and all_supported:
		if p.kind == Project.Kind.MINE or p.kind == Project.Kind.TUNNEL:
			# Шахта и тоннель — без отделки: выкопаны и закреплены — готовы.
			var found: PackedStringArray = []
			for k in p.found:
				found.append("%s %d" % [Mat.resource_name(k), p.found[k]])
			if not found.is_empty():
				_log("%s: копка завершена. Найдено: %s" % [p.title(), ", ".join(found)], "good")
			_finish_project(p)
			return
		p.phase = Project.Phase.BUILD
		_register_room(p)
		var lines: PackedStringArray = []
		for k in p.found:
			lines.append("%s %d" % [Mat.resource_name(k), p.found[k]])
		if lines.is_empty():
			if not p.needs_support.is_empty():
				_log("%s: копка завершена, начинаем строительство" % p.title(), "info")
		else:
			_log("%s: копка завершена. Найдено: %s" % [p.title(), ", ".join(lines)], "good")
		_try_pay(p)


func _check_liquids(p: Project) -> void:
	for c in p.cells():
		if world.is_revealed(c.x, c.y) and Mat.is_fluid(world.get_mat(c.x, c.y)):
			p.paused = true
			p.blocked = "В зоне стройки %s — отмените или дождитесь насосов" % Mat.name_of(world.get_mat(c.x, c.y)).to_lower()
			return
	if p.blocked.begins_with("В зоне"):
		p.blocked = ""


## Начинает этап строительства, обустройства или ремонта, когда всё принесено.
func _try_pay(p: Project) -> void:
	var cost: Dictionary
	if p.phase == Project.Phase.BUILD and not p.paid:
		cost = p.cost()
	elif p.phase == Project.Phase.EQUIP and not p.equip_paid:
		cost = RoomType.job_cost(p)
	elif p.phase == Project.Phase.DONE and p.repairing and not p.repair_paid:
		cost = p.repair_need
	else:
		_check_supply(p)
		return
	# Топливо (дизель, метан, нефть) не носят — берут по трубам прямо из баков.
	for k in cost:
		var have: int = inventory.get(k, 0) if RoomType.PIPED.has(k) else p.delivered.get(k, 0)
		if have < cost[k]:
			_check_supply(p)
			return
	for k in cost:
		if RoomType.PIPED.has(k):
			_remove(k, cost[k])
			continue
		p.delivered[k] -= cost[k]
		if p.delivered[k] <= 0:
			p.delivered.erase(k)
	match p.phase:
		Project.Phase.BUILD:
			p.paid = true
			p.exposed_t = 0.0
		Project.Phase.EQUIP:
			p.equip_paid = true
		_:
			p.repair_paid = true
	p.blocked = ""


func _finish_project(p: Project) -> void:
	if p.extends_id > 0 and _merge_extension(p):
		return
	# Принесённое на обустройство остаётся в комнате, лишнее — на склад.
	var keep := plan_cost(p)
	for k in p.delivered.keys():
		var extra: int = int(p.delivered[k]) - int(keep.get(k, 0))
		if extra > 0:
			_add(k, extra)
			p.delivered[k] = int(p.delivered[k]) - extra
		if int(p.delivered[k]) <= 0:
			p.delivered.erase(k)
	p.phase = Project.Phase.DONE
	highest_y = mini(highest_y, p.rect.position.y)
	p.blocked = ""
	# Бур — машина, а не помещение: сквозь него ходят, он уезжает.
	for c in ([] as Array[Vector2i]) if p.kind == Project.Kind.DRILL or p.kind == Project.Kind.PROBE else p.cells():
		interior[c] = p.id
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_register_deck(p)
	_rebuild_climb()
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	if p.kind == Project.Kind.ROOM and p.plan_purpose > 0:
		# Комнату строили под назначение — сразу обустраивают.
		var t := p.plan_purpose
		p.plan_purpose = 0
		_log("Построено: %s — обустраиваем: %s" % [p.title(), RoomType.purpose_name(t)], "good")
		if not set_purpose(p, t):
			_return_delivered(p)
	elif p.kind == Project.Kind.ROOM:
		_return_delivered(p)
		_log("Построено: %s. Выберите назначение комнаты." % p.title(), "good")
	else:
		_return_delivered(p)
		_log("Построено: %s" % p.title(), "good")
	if p.kind == Project.Kind.LIFT:
		_merge_lifts(p)


## Убрали мост или пристань — общие с другой водной постройкой клетки снова её.
func _restore_water_overlaps(gone: Project) -> void:
	if not gone.is_water_structure() and not is_passage(gone.kind):
		return
	for q in projects:
		if q != gone and q.phase == Project.Phase.DONE and q.rect.intersects(gone.rect) \
				and (q.is_water_structure() or is_passage(q.kind)):
			for c in q.cells():
				interior[c] = q.id
			_register_deck(q)


## Проходы — тоннели, шахты и лифты: друг другу не мешают и могут пересекаться.
static func is_passage(kind: int) -> bool:
	return kind == Project.Kind.TUNNEL or kind == Project.Kind.MINE or kind == Project.Kind.LIFT or kind == Project.Kind.DRILL \
		or kind == Project.Kind.PROBE


func _register_deck(p: Project) -> void:
	if not p.is_water_structure() or p.phase != Project.Phase.DONE:
		return
	for c in p.cells():
		deck[c] = p.id
		room_cells[c] = p.id


## Какой-то стройке не хватает материалов, которых нет на складе.
func waiting_for_materials() -> bool:
	for p in projects:
		if not p.paused and p.blocked.begins_with("Не хватает"):
			return true
	return false


# --- Назначение комнат -------------------------------------------------------------

## Начинает обустройство готовой комнаты под назначение t.
func set_purpose(p: Project, t: int) -> bool:
	wake_idle()
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE or t == p.purpose:
		return false
	# Котлы и кирпичные печи — улучшения очага; второй раз их не ставят.
	if t == RoomType.HEARTH_GAS and not is_hearth_upgrade(p, t):
		return false
	if t == RoomType.HEARTH_BRICK and p.purpose == RoomType.HEARTH and not is_hearth_upgrade(p, t):
		return false
	if not research.has(RoomType.REQUIRES.get(t, "")):
		return false
	if p.purpose == RoomType.SHIP:
		return false
	if t == RoomType.LAUNCHPAD and not launchpad_error(p).is_empty():
		_log(launchpad_error(p), "warning")
		return false
	if is_hearth_upgrade(p, t):
		# Печи перекладывают кирпичом или ставят котлы: очаг остаётся очагом.
		p.equip_ladder = false
		p.equip_target = t
		p.equip_paid = false
		p.equip_done = 0.0
		p.phase = Project.Phase.EQUIP
		_log("%s: %s" % [p.title(), "ставим газовые котлы" if t == RoomType.HEARTH_GAS else "перекладываем печи кирпичом"], "info")
		_try_pay(p)
		return true
	_release_beds(p)
	p.equip_ladder = false
	p.equip_target = t
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	if t == RoomType.NONE:
		_finish_equip(p)
		return true
	_log("%s: обустройство под «%s»" % [p.title(), RoomType.purpose_name(t)], "info")
	_try_pay(p)
	return true


## Улучшение очага: каменные печи — до кирпичных, любые — газовыми котлами.
func is_hearth_upgrade(p: Project, t: int) -> bool:
	if p.purpose != RoomType.HEARTH:
		return false
	return (t == RoomType.HEARTH_BRICK and not p.brick_stoves) or (t == RoomType.HEARTH_GAS and not p.gas_boiler)


# --- Космос: космодром, ракета, экспедиции -----------------------------------------------

## Почему здесь нельзя космодром (пусто — можно): над ним должно быть открытое небо.
func launchpad_error(p: Project) -> String:
	if p.kind != Project.Kind.ROOM:
		return "Космодром — это комната на поверхности"
	for x in range(p.rect.position.x, p.rect.end.x):
		if p.rect.end.y - 1 >= world.gen.surface_y(x):
			return "Космодром — только на поверхности: пол выше земли"
		for y in range(p.rect.position.y - 14, p.rect.position.y):
			if not world.is_open(x, y) or project_at(Vector2i(x, y)) != null:
				return "Над космодромом нужно открытое небо (14 м) — для ракеты"
	return ""


## Начать сборку ракеты на космодроме (engine: "chem" или "nuclear"). Пусто — началась.
func start_rocket(p: Project, engine: String) -> String:
	wake_idle()
	if p.purpose != RoomType.LAUNCHPAD or p.phase != Project.Phase.DONE:
		return "Ракету собирают на готовом космодроме"
	if not p.rocket.is_empty():
		return "Ракета уже стоит на столе"
	if engine == "nuclear" and not research.has("nuclear_engine"):
		return "Сначала изучите «%s»" % Research.tech_name("nuclear_engine")
	var err := launchpad_error(p)
	if not err.is_empty():
		return err
	p.equip_rocket = engine
	p.equip_target = p.purpose
	p.equip_ladder = false
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	_log("%s: собираем ракету (%s двигатель)" % [p.title(), Planet.engine_name(engine)], "info")
	_try_pay(p)
	return ""


## Куда долетит ракета с этим двигателем.
static func rocket_reaches(engine: String, planet_id: String) -> bool:
	var need: String = Planet.data(planet_id)["engine"]
	return engine == "nuclear" or need == engine


## Отправить экспедицию: до 10 гавриков и до 200 груза (не топливо — его не возят).
## Возвращает полёт (словарь для Universe) или ошибку {"error": текст}.
func launch(p: Project, planet_id: String, crew: Array, cargo: Dictionary) -> Dictionary:
	if p.rocket.is_empty():
		return {"error": "Ракеты на столе нет"}
	if not rocket_reaches(p.rocket, planet_id):
		return {"error": "Для полёта на %s нужен %s двигатель" % [Planet.planet_name(planet_id), Planet.engine_name(Planet.data(planet_id)["engine"])]}
	if crew.size() > RoomType.SHIP_BEDS:
		return {"error": "В ракете — до %d гавриков" % RoomType.SHIP_BEDS}
	var total := 0
	for k in cargo:
		total += int(cargo[k])
		if RoomType.PIPED.has(k) or RoomType.BULK.has(k):
			return {"error": "%s в ракете не возят" % Mat.resource_name(k)}
		if int(inventory.get(k, 0)) < int(cargo[k]):
			return {"error": "Не хватает: %s" % Mat.resource_name(k).to_lower()}
	if total > RoomType.SHIP_HOLD:
		return {"error": "Груза — до %d" % RoomType.SHIP_HOLD}
	if crew.is_empty() and total == 0:
		return {"error": "Ракета пустая"}
	var crew_data := []
	for u: Unit in crew:
		if not units.has(u) or u.child:
			return {"error": "Лететь могут только взрослые гаврики колонии"}
	for u: Unit in crew:
		_drop(u)
		u.workplace = 0
		u.bed_room = 0
		crew_data.append(u.to_dict())
		units.erase(u)
	for o in units:
		if not units.has(unit_by_id(o.partner_id)):
			o.partner_id = 0
	for k in cargo:
		_remove(k, int(cargo[k]))
	p.rocket = ""
	_log("Старт! Экспедиция на %s: гавриков %d, груза %d. Лететь %d мес." % [Planet.planet_name(planet_id), crew_data.size(), total,
		int(Planet.data(planet_id)["travel"])], "good")
	return {"planet": planet_id, "crew": crew_data, "cargo": cargo.duplicate(), "research": research.done.duplicate(),
		"left": float(Planet.data(planet_id)["travel"]) * MONTH}


## Новая колония на планете: корабль садится на поверхность, экипаж и груз — в нём.
func start_planet(x: int, flight: Dictionary) -> void:
	home = Vector2i(x, world.gen.surface_y(x))
	explored_min = x - START_VIEW
	explored_max = x + START_VIEW
	deepest_y = home.y
	highest_y = home.y
	for k in flight.get("research", []):
		if not research.done.has(str(k)):
			research.done.append(str(k))
	receive_flight(flight)


## Прилетела ракета: корабль садится рядом с колонией (или на месте первой высадки),
## гаврики и груз — в корабле.
func receive_flight(flight: Dictionary) -> void:
	var ship := _land_ship()
	var ids := {}
	var arrived: Array[Unit] = []
	for d in flight.get("crew", []):
		var u := Unit.from_dict(d)
		ids[u.id] = next_unit_id
		u.id = next_unit_id
		next_unit_id += 1
		u.mother_id = 0
		u.father_id = 0
		u.task = Unit.Task.NONE
		u.state = Unit.State.IDLE
		u.path.clear()
		u.project_id = 0
		u.workplace = 0
		u.bed_room = 0
		u.pos = Vector2(RoomType.floor_start(ship) + arrived.size() % RoomType.usable_width(ship), ship.rect.end.y - 1)
		units.append(u)
		arrived.append(u)
	for u in arrived:
		u.partner_id = ids.get(u.partner_id, 0)
	for k in flight.get("cargo", {}):
		var n := int(flight["cargo"][k])
		var put := _add(k, n, ship)
		if put < n:
			_add(k, n - put)
	_log("Посадка на %s! Корабль — жильё на %d человек; прибыло гавриков %d. Копайте вниз прямо из корабля." % [
		Planet.planet_name(world.gen.planet_id), RoomType.SHIP_BEDS, arrived.size()], "good")


## Корабль садится на ровное место у базы: комната 9×3 на поверхности.
func _land_ship() -> Project:
	var x0 = null
	for k in 40:
		for sgn in [1, -1]:
			var x: int = home.x - 4 + sgn * k * 10
			var sx := world.gen.surface_y(x)
			var free := true
			for q in projects:
				if q.rect.intersects(Rect2i(x - 1, sx - 4, 11, 5)):
					free = false
			if free and _flat_at(x):
				x0 = x
				break
		if x0 != null:
			break
	if x0 == null:
		x0 = home.x - 4
	var s0 := world.gen.surface_y(x0)
	var p := Project.new()
	p.id = next_project_id
	next_project_id += 1
	p.kind = Project.Kind.ROOM
	p.rect = Rect2i(x0, s0 - 3, 9, 3)
	p.material = "iron"
	p.purpose = RoomType.SHIP
	p.phase = Project.Phase.DONE
	p.paid = true
	projects.append(p)
	# Под кораблём земля ровная: подсыпаем, где ниже.
	for x in range(p.rect.position.x, p.rect.end.x):
		var below := Vector2i(x, p.rect.end.y)
		if world.is_open(below.x, below.y):
			world.set_material(below.x, below.y, Mat.GRAVEL)
	for c in p.cells():
		if not world.is_open(c.x, c.y):
			world.set_material(c.x, c.y, Mat.AIR)
		interior[c] = p.id
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_register_room(p)
	_rebuild_climb()
	return p


func _flat_at(x: int) -> bool:
	var s := world.gen.surface_y(x)
	for dx in 9:
		if world.gen.surface_y(x + dx) != s:
			return false
	return true


## Почему нельзя перестроить стены комнаты из mat (пусто — можно).
func material_error(p: Project, mat: String) -> String:
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE:
		return "Перестраивать можно только готовую комнату"
	if mat == p.material:
		return "Стены уже из этого материала"
	if not available_materials().has(mat):
		return "Этот материал ещё не доступен"
	# Тяжелее стены — больше вес на нижние этажи; слабее — меньше держат верхние.
	var old := p.material
	p.material = mat
	var predicted := loads.compute()
	var err := ""
	for q in projects:
		if q.kind == Project.Kind.ROOM and loads.utilization(q, predicted) > 1.0:
			err = "%s не выдержит: сверху будет %d т, держит %d т" % [q.title(), roundi(predicted.get(q.id, 0.0)), roundi(Loads.bearing(q))]
			break
	p.material = old
	return err


## Перестроить стены готовой комнаты из другого материала (дерево → камень и т. п.).
## На время работ комната не работает; новые стены — без износа.
func change_material(p: Project, mat: String) -> bool:
	wake_idle()
	if not material_error(p, mat).is_empty():
		return false
	_release_beds(p)
	p.equip_ladder = false
	p.equip_material = mat
	p.equip_target = p.purpose
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	_log("%s: перестраиваем стены — %s" % [p.title(), Project.MATERIALS[mat][0].to_lower()], "info")
	_try_pay(p)
	return true


## Строит лестницу в готовой комнате (нужна для второго этажа и выхода наверх).
func add_ladder(p: Project) -> bool:
	wake_idle()
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE or p.ladder:
		return false
	p.equip_ladder = true
	p.equip_target = p.purpose
	p.equip_paid = false
	p.equip_done = 0.0
	p.phase = Project.Phase.EQUIP
	_log("%s: строим лестницу" % p.title(), "info")
	_try_pay(p)
	return true


func cancel_equip(p: Project) -> void:
	if p.phase != Project.Phase.EQUIP:
		return
	if p.equip_paid:
		_refund(RoomType.job_cost(p), 1.0 - p.equip_done / RoomType.job_work(p))
	_return_delivered(p)
	p.phase = Project.Phase.DONE
	if not p.equip_ladder and p.equip_material.is_empty() and p.equip_rocket.is_empty() and not is_hearth_upgrade(p, p.equip_target):
		p.purpose = RoomType.NONE
	p.equip_ladder = false
	p.equip_material = ""
	p.equip_rocket = ""
	p.blocked = ""
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s: обустройство отменено" % p.title(), "info")


func _finish_equip(p: Project) -> void:
	_return_delivered(p)
	p.phase = Project.Phase.DONE
	p.blocked = ""
	if not p.equip_rocket.is_empty():
		p.rocket = p.equip_rocket
		p.equip_rocket = ""
		for u in units:
			if u.project_id == p.id:
				_drop(u)
		_log("Ракета собрана (%s двигатель) — готова к старту! Нажмите на космодром → «Запустить»" % Planet.engine_name(p.rocket), "good")
		return
	if not p.equip_material.is_empty():
		p.material = p.equip_material
		p.equip_material = ""
		p.wear = 0.0
		p.wear_warned = 0
		for c in p.cells():
			world.dirty[WorldData.chunk_of(c.x, c.y)] = true
		for u in units:
			if u.project_id == p.id:
				_drop(u)
		_log("%s: стены перестроены — %s" % [p.title(), Project.MATERIALS[p.material][0].to_lower()], "good")
		return
	if p.equip_ladder:
		p.equip_ladder = false
		p.ladder = true
		_release_beds(p)
		for c in p.cells():
			if c.x == p.rect.position.x:
				room_cells.erase(c)
		for u in units:
			if u.project_id == p.id:
				_drop(u)
		_log("%s: лестница готова" % p.title(), "good")
		return
	if is_hearth_upgrade(p, p.equip_target):
		if p.equip_target == RoomType.HEARTH_GAS:
			p.gas_boiler = true
		else:
			p.brick_stoves = true
		for u in units:
			if u.project_id == p.id:
				_drop(u)
		_log("Готово: %s — %s (%s)" % [p.title(), "газовые котлы" if p.equip_target == RoomType.HEARTH_GAS else "печи кирпичные",
			RoomType.purpose_hint(p.equip_target)], "good")
		return
	p.brick_stoves = p.equip_target == RoomType.HEARTH_BRICK
	p.gas_boiler = false
	p.purpose = RoomType.base_type(p.equip_target)
	p.farm_progress = 0.0
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	if RoomType.is_store(p.purpose):
		_full_warned.clear()
		if p.gatherers <= 0:
			p.gatherers = 1
		# Нормы по умолчанию для того, что этот склад хранит (уже заданные не трогаем).
		var defaults := default_targets(p)
		for k in defaults:
			if not p.targets.has(k):
				p.targets[k] = defaults[k]
	if p.purpose != RoomType.NONE:
		_log("Готово: %s (%s)" % [p.title(), RoomType.purpose_hint(p.equip_target)], "good")


func rooms_of(t: int) -> Array[Project]:
	var out: Array[Project] = []
	for p in projects:
		if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == t:
			out.append(p)
	return out


## Все готовые генераторы: на дровах и угле и газовые.
func generators() -> Array[Project]:
	var out: Array[Project] = []
	for t in RoomType.GENERATORS:
		out.append_array(rooms_of(t))
	return out


func capacity(key: String) -> int:
	if RoomType.BULK.has(key):
		return 1 << 30
	return _base_cap(key) + storage_capacity(key)


## Вместимость складов для ресурса (без кучи на земле).
## Склады и амбары.
func store_rooms() -> Array[Project]:
	var out := rooms_of(RoomType.STORAGE)
	out.append_array(rooms_of(RoomType.GRANARY))
	out.append_array(rooms_of(RoomType.SHIP))
	return out


func storage_capacity(key: String) -> int:
	var c := 0
	for p in holders(key):
		c += room_cap(p, key)
	return c


## Сколько ресурса лежит в складах, сколько — у базы.
func stored_split(key: String) -> Vector2i:
	var have: int = inventory.get(key, 0)
	var pile := base_have(key)
	return Vector2i(have - pile, pile)


func set_store_filter(p: Project, keys: Array[String]) -> void:
	p.store_filter = keys
	_full_warned.clear()


## Галочка «хранить» у ресурса на складе или в амбаре.
func set_store_on(p: Project, key: String, on: bool) -> void:
	if on:
		p.store_off.erase(key)
		if not p.store_filter.is_empty() and not p.store_filter.has(key):
			p.store_filter.append(key)
	elif not p.store_off.has(key):
		p.store_off.append(key)
	_full_warned.clear()
	wake_idle()


## Предел хранения ресурса в складе: больше сюда не носят и не добывают.
## Сколько влезет — предела нет.
func set_store_limit(p: Project, key: String, n: int) -> void:
	if n >= room_cap(p, key):
		p.limits.erase(key)
	else:
		p.limits[key] = maxi(0, n)
		if int(p.targets.get(key, 0)) > n:
			p.targets[key] = maxi(0, n)
	_full_warned.clear()
	wake_idle()


## Сколько ресурса можно держать в комнате: вместимость или предел, заданный игроком.
func room_limit(p: Project, key: String) -> int:
	var c := room_cap(p, key)
	return mini(c, int(p.limits.get(key, c)))


func beds_total() -> int:
	var n := 0
	for p in bed_rooms():
		n += RoomType.beds(p)
	return n


## Где спят: жилые комнаты и корабли.
func bed_rooms() -> Array[Project]:
	var out := rooms_of(RoomType.HOME)
	out.append_array(rooms_of(RoomType.SHIP))
	return out


## Корабль, внутри которого клетка c (там воздух, тепло и свет), или null.
func ship_at(c: Vector2i) -> Project:
	for p in projects:
		if p.purpose == RoomType.SHIP and p.kind == Project.Kind.ROOM and p.rect.has_point(c):
			return p
	return null


func pregnant_count() -> int:
	var n := 0
	for u in units:
		if u.pregnancy >= 0.0:
			n += 1
	return n


## Клетка пола, где стоит кровать (index с 1).
static func bed_cell(p: Project, index: int) -> Vector2i:
	# В корабле койки в два яруса — места на полу повторяются.
	return Vector2i(RoomType.floor_start(p) + ((index - 1) * 2) % maxi(1, RoomType.usable_width(p)), p.rect.end.y - 1)


func _claim_bed(u: Unit) -> void:
	if u.bed_room != 0 and project_by_id(u.bed_room) != null:
		return
	u.bed_room = 0
	var taken := {}
	for o in units:
		if o.bed_room != 0:
			taken["%d:%d" % [o.bed_room, o.bed_index]] = true
	for p in bed_rooms():
		for i in range(1, RoomType.beds(p) + 1):
			if not taken.has("%d:%d" % [p.id, i]):
				u.bed_room = p.id
				u.bed_index = i
				return


func _release_beds(p: Project) -> void:
	for u in units:
		if u.bed_room == p.id:
			u.bed_room = 0
			u.bed_index = 0


## Сколько сытости в запасах (еда и ягоды).
func food_value() -> float:
	var v := 0.0
	for k in NUTRITION:
		v += inventory.get(k, 0) * NUTRITION[k]
	return v


func has_food() -> bool:
	return food_total() > 0


## Сколько еды всех видов на складах.
func food_total() -> int:
	var n := 0
	for k in RoomType.FOOD_KEYS:
		n += int(inventory.get(k, 0))
	return n


func food_low() -> bool:
	return food_value() < units.size() * MEAL_GOAL * 1.5


## Еды меньше, чем на полприёма каждому, — все силы на еду.
func food_critical() -> bool:
	return food_value() < units.size() * MEAL_GOAL * 0.5 and drop_total("food") + drop_total("fish") + drop_total("berries") == 0


## Приём пищи: сначала настоящая еда, потом ягоды; take(ключ, n) отдаёт, сколько взяли.
func _eat_from(u: Unit, take: Callable, bonus := 1.0) -> void:
	var gained := 0.0
	var eaten := 0
	# Растущий ребёнок насыщается вдвое хуже.
	var k_scale := bonus * (0.5 if u.child else 1.0)
	for key in RoomType.FOOD_KEYS:
		while eaten < MEAL_UNITS and gained < MEAL_GOAL and u.satiety < 100.0:
			if int(take.call(key, 1)) <= 0:
				break
			var add: float = NUTRITION[key] * k_scale
			u.satiety = minf(100.0, u.satiety + add)
			gained += add
			eaten += 1


func _take_store(key: String, n: int) -> int:
	return _remove(key, n)


## Без игрока гаврики берут и со склада, и с куч на земле (склада может не быть).
func _take_any(key: String, n: int) -> int:
	var t := _take_store(key, n)
	for c: Vector2i in drops.keys():
		if t >= n:
			break
		t += _take_drop(c, key, n - t)
	return t


func _have_any(key: String) -> int:
	return inventory.get(key, 0) + drop_total(key)


# --- Сбор ресурсов на поверхности -------------------------------------------------

## Пометить объект на сбор. Пустая строка — успех, иначе причина отказа.
func toggle_harvest(x: int) -> String:
	wake_idle()
	var f := world.feature_at(x)
	if f == WorldGen.FEATURE_NONE:
		return "Здесь нечего собирать"
	if f == WorldGen.FEATURE_TREE and world.growth(x) < 0.5 and not world.feature_marks.has(x):
		return "Дерево ещё молодое — пусть подрастёт"
	world.set_feature_mark(x, not world.feature_marks.has(x))
	return ""


## Что даёт объект сейчас: [ресурс, количество] — дерево по росту, куст по ягодам.
func feature_yield(x: int) -> Array:
	var y: Array = world.gen.kind_yield(world.feature_at(x), x)
	match world.feature_at(x):
		WorldGen.FEATURE_TREE:
			return ["wood", maxi(1, roundi(y[1] * world.growth(x)))]
		WorldGen.FEATURE_BUSH:
			return ["berries", floori(world.berries(x))]
		WorldGen.FEATURE_BOULDER:
			return y
	return ["", 0]


## Объект можно собирать прямо сейчас (у куста должны быть ягоды).
func harvestable(x: int) -> bool:
	var f := world.feature_at(x)
	if f == WorldGen.FEATURE_NONE:
		return false
	return f != WorldGen.FEATURE_BUSH or world.berries(x) >= 1.0 or _in_clearing(x)


func _in_clearing(x: int) -> bool:
	return _clearing_project(x) != null


## Стройка, на месте которой стоит объект x (его убирают при расчистке).
func _clearing_project(x: int) -> Project:
	for p in projects:
		if p.phase == Project.Phase.DIG and p.clear_x.has(x):
			return p
	return null


## room — склад, для которого гаврик добывал: добычу он несёт туда сам.
func _complete_harvest(x: int, u: Unit, room := 0) -> void:
	var y: Array = feature_yield(x)
	var kind := world.feature_at(x)
	harvest_progress.erase(x)
	if kind == WorldGen.FEATURE_BUSH and not _in_clearing(x):
		# Куст остаётся — ягоды отрастут. Отметка сбора тоже остаётся.
		world.set_berries(x, world.berries(x) - y[1])
	else:
		world.remove_feature(x)
		# Пень даёт поросль: лес у базы со временем отрастает (на месте стройки — нет).
		if kind == WorldGen.FEATURE_TREE and not _in_clearing(x) and rng.randf() < STUMP_REGROW:
			world.sprout(x, WorldGen.FEATURE_TREE)
	var site := _clearing_project(x)
	if room != 0 and offline and y[1] > 0:
		# Оффлайн работник склада сразу кладёт добытое в свой склад.
		var to := project_by_id(room)
		var put := _add(y[0], y[1], to) if to != null else 0
		if put < y[1]:
			drop_item(_ground_cell(x), y[0], y[1] - put)
	elif room != 0 and u != null and y[1] > 0:
		_carry_to(u, room, y[0], y[1])
	elif y[1] > 0:
		var before := drop_amount(_landing(_ground_cell(x)), y[0])
		drop_item(_ground_cell(x), y[0], y[1], site)
		# Кто добыл — тот и несёт на склад излишек, сколько унесёт (остальное подберут).
		# Строители и шахтёры не носят: добытое уносят работники складов и подсобные.
		if u != null and not offline and not builder_or_miner(u) and drop_amount(_landing(_ground_cell(x)), y[0]) > before:
			_pick_up(u, _landing(_ground_cell(x)), y[0])
		var fem := u != null and u.sex == Unit.Sex.FEMALE
		var what := "собрал ягоды"
		match kind:
			WorldGen.FEATURE_TREE:
				what = "срубила дерево" if fem else "срубил дерево"
			WorldGen.FEATURE_BOULDER:
				what = "разбила валун" if fem else "разбил валун"
			_:
				what = "собрала ягоды" if fem else "собрал ягоды"
		_log("%s %s: +%d %s" % [u.name if u != null else "Гаврики", what, y[1], Mat.resource_name(y[0]).to_lower()], "info")
	for p in projects:
		if p.phase == Project.Phase.DIG:
			_check_phase(p)


# --- Копка -----------------------------------------------------------------------

func _complete_dig(c: Vector2i, p: Project, u: Unit) -> void:
	var m := world.get_mat(c.x, c.y)
	dig_progress.erase(c)
	world.set_dug(c.x, c.y)
	cells_dug += 1
	deepest_y = maxi(deepest_y, c.y)
	var key := Mat.resource(m)
	if not key.is_empty():
		var amount := 1
		if Mat.is_ore(m):
			var depth := c.y - world.gen.surface_y(c.x)
			amount = 1 + int(WorldGen.hash01(c.x, c.y, 17) * (2.0 + depth / 250.0))
		drop_item(c, key, amount, p)
		if RoomType.RADIOACTIVE.has(key):
			irradiate(u)
		if p != null:
			p.found[key] = p.found.get(key, 0) + amount
		if NOTABLE.has(key):
			_log("%s %s: %s ×%d (глубина %s)" % [
				u.name if u != null else "Гаврики", "нашла" if u != null and u.sex == Unit.Sex.FEMALE else "нашёл",
				Mat.resource_name(key).to_lower(), amount, _depth_text(c)], "good")
	_note_discovery(m, c)
	# Дерево или валун над выкопанной клеткой падают.
	if c.y == world.gen.surface_y(c.x) and world.feature_at(c.x) != WorldGen.FEATURE_NONE:
		var y: Array = feature_yield(c.x)
		world.remove_feature(c.x)
		drop_item(_ground_cell(c.x), y[0], y[1], p)
	var hazards := {}
	for n in world.reveal_around(c.x, c.y, see_radius()):
		var nm := world.get_mat(n.x, n.y)
		_note_discovery(nm, n)
		if Mat.is_fluid(nm) and not hazards.has(nm):
			hazards[nm] = n
	for hm in hazards:
		_report_hazard(hm, hazards[hm])
	match Mat.hazard(m):
		Mat.Hazard.GAS:
			_log("Выброс метана на глубине %s! Нужна дегазация." % _depth_text(c), "danger")
			elements.release_gas(c)
		Mat.Hazard.WATER:
			_log("Из водоносного пласта сочится вода (глубина %s)." % _depth_text(c), "warning")
	elements.on_opened(c)
	physics.on_opened(c)
	for other in projects:
		if other.phase == Project.Phase.DIG:
			_check_phase(other)


func _report_hazard(m: int, c: Vector2i) -> void:
	if m == Mat.MAGMA:
		_log("КАТАСТРОФА: прорыв к магме на глубине %s! Температура %d °C." % [
			_depth_text(c), int(world.gen.temperature(c.y, world.gen.surface_y(c.x)))], "danger")
	else:
		_log("Вскрыта подземная полость с водой (глубина %s)." % _depth_text(c), "warning")


func _note_discovery(m: int, c: Vector2i) -> void:
	if discovered.has(m):
		return
	discovered[m] = true
	if Mat.is_ore(m) or m == Mat.ROCK_SALT or m == Mat.KIMBERLITE:
		_log("Новая находка: %s на глубине %s!" % [Mat.name_of(m), _depth_text(c)], "good")


# --- Физика: осыпи, обвалы, травмы ------------------------------------------------------

var _last_slide_ms := -100000


func on_slide(c: Vector2i, moved: int, m: int) -> void:
	# Осыпи частые — сообщаем не чаще раза в 5 секунд и не в оффлайне.
	var now := Time.get_ticks_msec()
	if offline or now - _last_slide_ms < 5000:
		return
	_last_slide_ms = now
	_log("Осыпь: %s засыпал выработку (%d м³, глубина %s)" % [Mat.name_of(m).to_lower(), moved, _depth_text(c)], "warning")


func on_collapse(c: Vector2i, span: int, limit: int, m: int) -> void:
	_log("ОБВАЛ на глубине %s: потолок из «%s» не выдержал пролёт %d м (держит %d м без укрепления)" % [
		_depth_text(c), Mat.name_of(m).to_lower(), span, limit], "danger")


## Порода упала из src в land: задевает гавриков по пути, засыпает стройку.
func on_cell_filled(src: Vector2i, land: Vector2i) -> void:
	dig_progress.erase(land)
	elements.on_opened(src)
	for u: Unit in units.duplicate():
		var c := u.cell()
		if c.x == land.x and (c == land or c + Vector2i(0, -1) == land or (c.y >= src.y and c.y <= land.y)):
			injure(u, 45.0, "придавило породой")
	var p := project_at(land)
	if p != null and p.phase == Project.Phase.BUILD:
		# Выработку засыпало — копать заново.
		p.phase = Project.Phase.DIG
		for cc in p.cells():
			room_cells.erase(cc)
		for u in units:
			if u.project_id == p.id:
				_drop(u)


func injure(u: Unit, dmg: float, why: String) -> void:
	if u.invulnerable():
		u.health = maxf(u.health, 1.0)
		return
	if u.ability("collapse_proof") == true and (why.contains("обвал") or why.contains("обломк") or why.contains("засыпало") or why.contains("обрушен")):
		_log("%s: %s — панцирь выдержал!" % [u.name, why], "good")
		return
	dmg /= maxf(0.3, u.stat("health"))
	u.health -= dmg
	if u.health > 0.0:
		_log("%s: %s, здоровье %d%%" % [u.name, why, roundi(u.health)], "danger")
		return
	if offline:
		# Пока игрока нет, гаврики не гибнут — только тяжело ранены.
		u.health = 1.0
		_log("%s: %s, тяжело ранен(а)" % [u.name, why], "danger")
		return
	_kill(u, why)


## Смерть от старости — тихо, без «погиб».
func _die_of_age(u: Unit) -> void:
	_kill(u, "", false)
	_log("%s %s от старости в %s, поколение %d" % [u.name, "умерла" if u.sex == Unit.Sex.FEMALE else "умер", u.age_text(), u.generation], "info")


func _kill(u: Unit, why: String, report := true) -> void:
	_drop(u)
	units.erase(u)
	for o in units:
		if o.partner_id == u.id:
			o.partner_id = 0
	for k in acquaint.keys():
		var ids: PackedStringArray = k.split(",")
		if int(ids[0]) == u.id or int(ids[1]) == u.id:
			acquaint.erase(k)
	if not report:
		return
	_log("%s погиб(ла): %s" % [u.name, why], "danger")


func _tick_exposure(dt: float) -> void:
	for p: Project in projects.duplicate():
		var idle := p.paused or p.blocked.begins_with("Не хватает")
		if (p.phase != Project.Phase.DIG and p.phase != Project.Phase.BUILD) or not idle:
			p.exposed_t = 0.0
			continue
		var before := p.exposed_t
		p.exposed_t += dt
		if before < Physics.GRACE * 0.5 and p.exposed_t >= Physics.GRACE * 0.5:
			_log("%s простаивает без укрепления — может обвалиться" % p.title(), "warning")
		if before < Physics.GRACE and p.exposed_t >= Physics.GRACE:
			physics.check_area(p.cells())


# --- Растения и рыба ---------------------------------------------------------------------

func lake_of(p: Project) -> Dictionary:
	return world.gen.lake_at(p.rect.get_center().x)


static func fish_max(lake: Dictionary) -> float:
	return clampf(float(lake.get("w", 4)) * 1.5, 6.0, 200.0)


## Сколько рыбы в озере (непотревоженное озеро — полное).
func fish_in(lake: Dictionary) -> float:
	if lake.is_empty():
		return 0.0
	return float(fish.get(int(lake["id"]), fish_max(lake)))


func fish_left(p: Project) -> float:
	return fish_in(lake_of(p))


func _catch_fish(p: Project, u: Unit) -> void:
	_catch_from(lake_of(p), u)


func _catch_from(lake: Dictionary, u: Unit) -> void:
	var left := fish_in(lake)
	if left < 1.0:
		return
	fish[int(lake["id"])] = left - 1.0
	if u != null and u.workplace == 0:
		# Свободный гаврик ловил от голода — съедает улов на месте, остаток оставляет на берегу.
		var catch := {"fish": 2}
		_eat_from(u, func(key: String, n: int) -> int:
			var t := mini(n, int(catch.get(key, 0)))
			if t > 0:
				catch[key] -= t
			return t)
		if catch["fish"] > 0:
			drop_item(u.cell(), "fish", catch["fish"])
	elif u != null:
		drop_item(u.cell(), "fish", 2)
		if not offline:
			_pick_up(u, _landing(u.cell()), "fish")
	else:
		_add("fish", 2)
		produced["fish"] = int(produced.get("fish", 0)) + 2
	if u != null and left - 1.0 < 1.0:
		_log("Рыба в озере кончилась — подождите, пока подрастёт новая", "warning")


## В новых мирах кусты разрастаются втрое реже.
func _bush_spread() -> float:
	return BUSH_SPREAD / 3.0 if world.gen.version >= 2 else BUSH_SPREAD


## Ягоды прямо с куста.
func _take_bush(x: int, key: String, n: int) -> int:
	if key != "berries" or world.feature_at(x) != WorldGen.FEATURE_BUSH:
		return 0
	var t := mini(n, floori(world.berries(x)))
	if t > 0:
		world.set_berries(x, world.berries(x) - t)
	return t


## Свободная трава, где может вырасти растение.
func _grass_free(x: int) -> bool:
	if absi(x - home.x) <= 8:
		return false
	var s := world.gen.surface_y(x)
	if absi(world.gen.surface_y(x - 1) - s) > 1 or absi(world.gen.surface_y(x + 1) - s) > 1:
		return false
	if world.gen.water_level(x) < s or world.is_dug(x, s) or world.get_mat(x, s) != Mat.TOPSOIL:
		return false
	return project_at(Vector2i(x, s - 1)) == null and project_at(Vector2i(x, s)) == null


func _refresh_bushes() -> void:
	_bushes.clear()
	for x in range(home.x - PLANT_AREA, home.x + PLANT_AREA + 1):
		if world.feature_at(x) == WorldGen.FEATURE_BUSH:
			_bushes.append(x)


func _plant_tick(dt: float) -> void:
	var tick := OFFLINE_PLANT_TICK if offline else PLANT_TICK
	_plant_t += dt
	while _plant_t >= tick:
		_plant_t -= tick
		grow_plants(tick)


## Рост деревьев, ягоды, новые растения рядом со старыми, восстановление рыбы.
func grow_plants(t: float) -> void:
	var k := t / PLANT_TICK
	# Зимой ягоды не растут и новые кусты не появляются.
	var winter := is_winter()
	var kinds := {}
	for x in range(home.x - PLANT_AREA - SPREAD_RADIUS, home.x + PLANT_AREA + SPREAD_RADIUS + 1):
		kinds[x] = world.feature_at(x)
	_bushes.clear()
	for x in range(home.x - PLANT_AREA, home.x + PLANT_AREA + 1):
		var f: int = kinds[x]
		if f == WorldGen.FEATURE_TREE:
			if world.growth(x) < 1.0:
				world.grow(x, t / TREE_GROW_TIME)
		elif f == WorldGen.FEATURE_BUSH:
			_bushes.append(x)
			if winter and world.berries(x) > 0.0:
				# Зимой ягоды осыпаются и мёрзнут: за пару недель на кустах пусто.
				world.set_berries(x, maxf(0.0, world.berries(x) - t * WorldData.BUSH_BERRIES / (MONTH * 0.5)))
			elif world.berries(x) < WorldData.BUSH_BERRIES and not winter:
				world.set_berries(x, minf(WorldData.BUSH_BERRIES, world.berries(x) + t / BERRY_REGEN))
		elif f == WorldGen.FEATURE_NONE:
			var trees := 0
			var bushes := 0
			for dx in range(-SPREAD_RADIUS, SPREAD_RADIUS + 1):
				var n: int = kinds.get(x + dx, 0)
				if n == WorldGen.FEATURE_TREE:
					trees += 1
				elif n == WorldGen.FEATURE_BUSH:
					bushes += 1
			var roll := rng.randf()
			if trees + bushes == 0:
				if roll < TREE_SEED * k and _grass_free(x):
					world.sprout(x, WorldGen.FEATURE_TREE)
					kinds[x] = WorldGen.FEATURE_TREE
				continue
			if roll < trees * TREE_SPREAD * k:
				if _grass_free(x):
					world.sprout(x, WorldGen.FEATURE_TREE)
					kinds[x] = WorldGen.FEATURE_TREE
			elif roll < (trees * TREE_SPREAD + bushes * _bush_spread()) * k and not winter:
				if _grass_free(x):
					world.sprout(x, WorldGen.FEATURE_BUSH)
					kinds[x] = WorldGen.FEATURE_BUSH
	for id in fish.keys():
		var lake := world.gen._lake_of_segment(int(id))
		fish[id] = minf(fish_max(lake), float(fish[id]) + t / FISH_REGEN)


# --- Жизнь: потребности, взросление, семьи ---------------------------------------------

const ENV_EVERY := 1.0


func _life_tick(dt: float, offline: bool) -> void:
	for u: Unit in units.duplicate():
		if not offline:
			# Стихии (вода, газ, жара, холод) — раз в секунду: урон тот же, считать в 5 раз реже.
			u.env_t += dt
			if u.env_t >= ENV_EVERY:
				elements.affect_unit(u, u.env_t)
				u.env_t = 0.0
				if not units.has(u):
					continue
		u.satiety = maxf(0.0, u.satiety - SATIETY_DECAY * dt * u.stat("appetite"))
		# Без еды здоровье тает: примерно за двое суток — смерть (без игрока — только истощение).
		if u.satiety <= 0.0 and not u.invulnerable():
			u.health -= dt * 100.0 / STARVE_TIME / maxf(0.3, u.stat("fasting"))
			if u.health < 50.0 and not u.starving_warned:
				u.starving_warned = true
				_log("%s %s от голода — срочно нужна еда!" % [u.name, "истощена" if u.sex == Unit.Sex.FEMALE else "истощён"], "danger")
			if u.health <= 0.0:
				if offline:
					u.health = 1.0
				else:
					_kill(u, "голод")
					continue
		elif u.satiety > 30.0:
			u.starving_warned = false
		u.energy = 100.0
		var heal := 100.0 / HEAL_TIME \
			* (3.0 if u.task == Unit.Task.WARM and u.state == Unit.State.WORK else 1.0)
		u.health = minf(100.0, u.health + dt * heal)
		if offline:
			# Оффлайн гаврики сами едят и спят по расписанию.
			if u.satiety < HUNGRY + 5.0 and _have_any("food") + _have_any("fish") + _have_any("berries") > 0:
				_eat_from(u, _take_any, DINING_BONUS if not rooms_of(RoomType.DINING).is_empty() else 1.0)
			elif u.satiety < HUNGRY + 5.0:
				for bx in _bushes:
					if world.feature_at(bx) == WorldGen.FEATURE_BUSH and world.berries(bx) >= 1.0:
						_eat_from(u, func(key: String, n: int) -> int: return _take_bush(bx, key, n))
						break
			u.energy = maxf(u.energy, 60.0)
		var was_elder := u.is_elder()
		u.age += dt
		if u.child:
			_apprentice(u, dt)
		if u.child and u.age >= Unit.CHILD_TIME:
			u.child = false
			_log("%s %s — теперь может работать" % [u.name, "выросла" if u.sex == Unit.Sex.FEMALE else "вырос"], "good")
		if not was_elder and u.is_elder():
			_log("%s %s — работает медленнее" % [u.name, "состарилась" if u.sex == Unit.Sex.FEMALE else "состарился"], "info")
		if u.lifespan > 0.0 and u.age >= u.lifespan:
			_die_of_age(u)
			continue
		if u.pregnancy >= 0.0:
			u.pregnancy += dt
			if u.pregnancy >= PREGNANCY_TIME:
				_birth(u)
	_social_t += dt
	while _social_t >= SOCIAL_TICK:
		_social_t -= SOCIAL_TICK
		_social()


func _social() -> void:
	_meet(SOCIAL_TICK)
	for u in units:
		u.calling = calling_of(u)
	if beds_total() == 0:
		return
	# Пары складываются только у знакомых — кто подолгу бывал рядом, — и когда есть где жить.
	for f in units:
		if f.child or f.sex != Unit.Sex.FEMALE or f.partner_id != 0 or f.mood() < 45.0:
			continue
		var best: Unit = null
		var best_v := ACQUAINT_PAIR
		for m in units:
			if m.child or m.sex != Unit.Sex.MALE or m.partner_id != 0 or m.mood() < 45.0:
				continue
			var v := acquaintance(f, m)
			if v >= best_v:
				best_v = v
				best = m
		if best != null and rng.randf() < 0.2:
			f.partner_id = best.id
			best.partner_id = f.id
			_log("%s и %s стали парой" % [f.name, best.name], "good")
	# Дети — только если есть свободная кровать и еда.
	for f in units:
		if f.child or f.is_elder() or f.sex != Unit.Sex.FEMALE or f.pregnancy >= 0.0 or f.partner_id == 0:
			continue
		var partner := unit_by_id(f.partner_id)
		if partner == null:
			f.partner_id = 0
			continue
		var free_beds := beds_total() - units.size() - pregnant_count()
		if free_beds <= 0 or food_value() < MEAL_GOAL * 2.0 or f.satiety < 40.0:
			continue
		if rng.randf() < 0.12 * sqrt(f.stat("fertility") * partner.stat("fertility")):
			f.pregnancy = 0.0
			_log("%s и %s ждут ребёнка!" % [f.name, partner.name], "good")


func _birth(mother: Unit) -> void:
	mother.pregnancy = -1.0
	var father := unit_by_id(mother.partner_id)
	# Гены: по копии от мамы и от папы, иногда мутация.
	var rad := mother.irradiated or (father != null and father.irradiated)
	var genome := Genetics.child(mother.genome, father.genome if father != null else mother.genome, rng, rad)
	var baby := _new_unit(Unit.Sex.MALE, mother.pos, genome)
	baby.child = true
	baby.age = 0.0
	baby.satiety = 80.0
	baby.energy = 80.0
	baby.mother_id = mother.id
	baby.mother_name = mother.name
	baby.generation = maxi(mother.generation, father.generation if father != null else 0) + 1
	if father != null:
		baby.father_id = father.id
		baby.father_name = father.name
	# Немного таланта от родителей.
	for k in baby.skills:
		var parent_xp: float = mother.skills[k] + (father.skills[k] if father != null else 0.0)
		baby.skills[k] = parent_xp * 0.1
	var who := "дочь" if baby.sex == Unit.Sex.FEMALE else "сын"
	var parents := mother.name + (" и " + father.name if father != null else "")
	_log("Родился ребёнок: %s (%s %s)" % [baby.name, who, parents], "good")
	if Genetics.is_super(genome):
		_log("Родился СУПЕР-ГАВРИК: %s — цвета лого, все характеристики вдвое выше!" % baby.name, "good")
	elif Genetics.is_mutant(genome):
		_log("%s — %s" % [baby.name, Genetics.mutation_text(genome).to_lower()], "good" if Genetics.rarity(genome) >= 2 else "info")


## Уран радиоактивен: кто его копает, носит или обогащает — облучён (один раз): живёт на
## 10% меньше, а дети его — всегда с мутацией.
const RADIATION_LIFE := 0.9


func irradiate(u: Unit) -> void:
	if u == null or u.irradiated:
		return
	u.irradiated = true
	if u.lifespan > 0.0:
		u.lifespan *= RADIATION_LIFE
	_log("%s %s ураном — проживёт на 10%% меньше, дети будут мутантами" % [u.name, "облучена" if u.sex == Unit.Sex.FEMALE else "облучён"], "warning")


# --- Места работы: игрок ставит конкретных гавриков (как в Fallout Shelter) ---------------

## Куда можно назначить гаврика: ферма, лаборатория, печь, кузница, склад, пристань.
func is_workplace(p: Project) -> bool:
	if p == null or p.phase != Project.Phase.DONE:
		return false
	if p.is_water_structure():
		return true
	return p.kind == Project.Kind.ROOM and p.purpose in [RoomType.FARM, RoomType.LAB, RoomType.KILN, RoomType.FORGE, RoomType.REFINERY, RoomType.ENRICHMENT,
		RoomType.STORAGE, RoomType.GRANARY]


func work_slots(p: Project) -> int:
	if p.is_water_structure():
		return p.fish_slots()
	return RoomType.farm_slots(p)


func assigned_to(p: Project) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.workplace == p.id:
			out.append(u)
	return out


## Работают на месте только назначенные игроком.
func _closed_for(u: Unit, p: Project) -> bool:
	return u.workplace != p.id


func assign_work(u: Unit, p: Project) -> String:
	wake_idle()
	if u.child:
		return "Дети не работают"
	if not is_workplace(p):
		return "Сюда нельзя назначить"
	if u.workplace == p.id:
		return ""
	if assigned_to(p).size() >= work_slots(p):
		return "Все места заняты (%d)" % work_slots(p)
	u.workplace = p.id
	u.profession = Unit.Prof.ANY
	u.calling = calling_of(u)
	if u.state != Unit.State.FALL and u.task != Unit.Task.SLEEP and u.task != Unit.Task.EAT:
		_drop(u)
	_log("%s теперь работает: %s" % [u.name, workplace_name(p)], "info")
	return ""


## Роль гаврика без места работы: свободный, строитель или подсобный рабочий.
func set_profession(u: Unit, prof: int) -> String:
	wake_idle()
	if u.child:
		return "Дети не работают"
	if u.profession == prof and u.workplace == 0:
		return ""
	unassign_work(u)
	u.profession = prof
	u.calling = calling_of(u)
	if u.state != Unit.State.FALL and u.task != Unit.Task.SLEEP and u.task != Unit.Task.EAT:
		_drop(u)
	if prof != Unit.Prof.ANY:
		_log("%s теперь %s" % [u.name, Unit.PROF_NAMES[prof].to_lower()], "info")
	return ""


## Кто чем занят: свободный, строитель, подсобный или место работы.
func role_name(u: Unit) -> String:
	if u.child:
		return "ребёнок"
	if u.workplace != 0:
		return workplace_name(project_by_id(u.workplace))
	return Unit.PROF_NAMES[u.profession]


func is_free(u: Unit) -> bool:
	return not u.child and u.workplace == 0 and u.profession == Unit.Prof.ANY


func unassign_work(u: Unit) -> void:
	wake_idle()
	if u.workplace == 0:
		return
	u.workplace = 0
	u.calling = calling_of(u)
	if u.state == Unit.State.WORK and u.task in [Unit.Task.FARM, Unit.Task.RESEARCH, Unit.Task.CRAFT, Unit.Task.FISH]:
		_drop(u)


func workplace_name(p: Project) -> String:
	if p == null:
		return "разнорабочий"
	if p.is_water_structure():
		return p.title()
	return RoomType.NAMES[p.purpose]


## Какая характеристика и навык важны на этом месте.
## Какие характеристики важны для работы: [главная, вторая]. Главная влияет полностью
## (150% — в полтора раза быстрее), вторая — наполовину.
const JOB_STATS := {
	Unit.Task.DIG: ["strength", "stamina"],
	Unit.Task.BUILD: ["agility", "strength"],
	Unit.Task.EQUIP: ["agility", "strength"],
	Unit.Task.SUPPORT: ["agility", "strength"],
	Unit.Task.REPAIR: ["agility", "strength"],
	Unit.Task.HARVEST: ["strength", "speed"],
	Unit.Task.FARM: ["agility", "stamina"],
	Unit.Task.FISH: ["agility", "vision"],
	Unit.Task.CRAFT: ["strength", "heat"],
	Unit.Task.RESEARCH: ["intellect", "learning"],
}
## Работа «по призванию» (характеристики подходят) и «не по душе»: навык растёт
## в 1,5 раза быстрее или вдвое медленнее, настроение лучше или хуже.
const CALLING_HI := 1.25
const CALLING_LO := 0.8
const CALLING_MOOD := 10.0


## Какую работу делают на этом месте (по ней — нужные характеристики).
func work_task(p: Project) -> int:
	if p.is_water_structure():
		return Unit.Task.FISH
	match p.purpose:
		RoomType.FARM:
			return Unit.Task.FARM
		RoomType.LAB:
			return Unit.Task.RESEARCH
		RoomType.KILN, RoomType.FORGE, RoomType.REFINERY, RoomType.ENRICHMENT:
			return Unit.Task.CRAFT
		RoomType.STORAGE:
			return Unit.Task.HARVEST
		RoomType.GRANARY:
			return Unit.Task.FISH
	return Unit.Task.BUILD


## Главная и вторая характеристики для места.
func work_stats(p: Project) -> Array:
	return JOB_STATS[work_task(p)]


func work_stat(p: Project) -> String:
	return work_stats(p)[0]


func work_skill(p: Project) -> String:
	if p.is_water_structure() or RoomType.is_store(p.purpose):
		return "gather"
	match p.purpose:
		RoomType.FARM:
			return "farm"
		RoomType.LAB:
			return "science"
	return "build"


## Насколько характеристики гаврика подходят для работы (1.0 — обычный).
func stat_fit(u: Unit, task: int) -> float:
	if u.genome.is_empty() or not JOB_STATS.has(task):
		return 1.0
	var st: Array = JOB_STATS[task]
	return maxf(0.3, u.stat(st[0]) * (1.0 + 0.5 * (u.stat(st[1]) - 1.0)))


## Основная работа гаврика: место работы или роль (строитель, шахтёр, подсобный); -1 — нет.
func job_task(u: Unit) -> int:
	if u.workplace != 0:
		var p := project_by_id(u.workplace)
		if p != null:
			return work_task(p)
	match u.profession:
		Unit.Prof.BUILDER:
			return Unit.Task.BUILD
		Unit.Prof.MINER:
			return Unit.Task.DIG
		Unit.Prof.HAULER:
			return Unit.Task.HARVEST
	return -1


## 1 — работа по призванию, -1 — не по душе, 0 — обычно (или нет своей работы).
func calling_of(u: Unit, task := -2) -> int:
	if task == -2:
		task = job_task(u)
	if task < 0 or u.child:
		return 0
	var f := stat_fit(u, task)
	return 1 if f >= CALLING_HI else (-1 if f <= CALLING_LO else 0)


## Насколько гаврик хорош на этом месте (1.0 — обычный).
func suitability(u: Unit, p: Project) -> float:
	return stat_fit(u, work_task(p)) * u.speed(work_skill(p)) * float(u.ability("work"))


## Работа на своём месте.
func _try_workplace(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var p := project_by_id(u.workplace)
	if not is_workplace(p):
		u.workplace = 0
		return false
	if p.paused:
		return false
	if p.is_water_structure():
		return _fish_at(u, p, parents, dist)
	match p.purpose:
		RoomType.FARM:
			return farm_warm(p) and _room_work_at(u, p, Unit.Task.FARM, parents, dist)
		RoomType.LAB:
			return not research.current.is_empty() and _room_work_at(u, p, Unit.Task.RESEARCH, parents, dist)
		RoomType.KILN, RoomType.FORGE, RoomType.REFINERY, RoomType.ENRICHMENT:
			# Нет сырья — мастер сам приносит его со склада в свою мастерскую.
			if has_inputs(p):
				return _room_work_at(u, p, Unit.Task.CRAFT, parents, dist)
			return _try_supply(u, p, parents, dist)
		RoomType.STORAGE, RoomType.GRANARY:
			# Работники склада и амбара: сначала шахты (крепь туда, добытое оттуда),
			# потом уносят на хранение то, что уже лежит (улов, урожай ферм, добытое),
			# рубят отмеченное игроком и только потом добывают новое до нормы.
			if p.purpose == RoomType.STORAGE and _try_mine_logistics(u, p, parents, dist):
				return true
			if _try_cleanup(u, parents, dist, p):
				return true
			if p.purpose == RoomType.STORAGE and _try_harvest(u, parents, dist):
				return true
			for k in storage_deficit(p):
				if _try_gather(u, k, p, parents, dist):
					return true
			return false
	return false


# --- Знакомства и пары -----------------------------------------------------------------

## Сколько нужно побыть рядом (секунд игры), чтобы стать парой.
const ACQUAINT_PAIR := 120.0
const ACQUAINT_NEAR := 5


static func _acq_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


func acquaintance(a: Unit, b: Unit) -> float:
	return acquaint.get(_acq_key(a.id, b.id), 0.0)


## Знакомство растёт, когда гаврики рядом. Быстро — у тех, кто работает на одном месте
## или на соседних, на одной стройке или живёт в одной комнате: так игрок сводит пары.
## Просто встречаясь где-то ещё, знакомятся медленно. Общительные — быстрее.
const ACQUAINT_TOGETHER := 1.5
const ACQUAINT_STRANGERS := 0.3


func _meet(dt: float) -> void:
	var adults := units.filter(func(u: Unit) -> bool: return not u.child)
	for i in adults.size():
		var a: Unit = adults[i]
		for j in range(i + 1, adults.size()):
			var b: Unit = adults[j]
			var d := a.cell() - b.cell()
			var together := works_together(a, b)
			var near := absi(d.x) <= ACQUAINT_NEAR + 3 and absi(d.y) <= 4 if together \
				else absi(d.x) <= ACQUAINT_NEAR and absi(d.y) <= 2
			if near:
				var key := _acq_key(a.id, b.id)
				acquaint[key] = acquaint.get(key, 0.0) + dt * (a.stat("charm") + b.stat("charm")) * 0.5 \
					* (ACQUAINT_TOGETHER if together else ACQUAINT_STRANGERS)


## Работают вместе (одно место или соседние комнаты, одна стройка) или живут в одной комнате.
func works_together(a: Unit, b: Unit) -> bool:
	if a.bed_room != 0 and a.bed_room == b.bed_room:
		return true
	if a.project_id != 0 and a.project_id == b.project_id and a.state == Unit.State.WORK and b.state == Unit.State.WORK:
		return true
	if a.workplace == 0 or b.workplace == 0:
		return false
	if a.workplace == b.workplace:
		return true
	var pa := project_by_id(a.workplace)
	var pb := project_by_id(b.workplace)
	return pa != null and pb != null and pa.rect.grow(1).intersects(pb.rect)


## Лучшие знакомые гаврика: [[гаврик, знакомство]].
func best_friends(u: Unit, n := 3) -> Array:
	var out := []
	for o in units:
		if o != u:
			var v := acquaintance(u, o)
			if v > 0.0:
				out.append([o, v])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return out.slice(0, n)


# --- Онлайн-симуляция -------------------------------------------------------------

func update(dt: float) -> void:
	var remaining := dt
	while remaining > 0.0:
		var step := minf(remaining, SUBSTEP)
		remaining -= step
		game_time += step
		pathing.tick(step)
		_climb_t += step
		if _climb_t >= 0.5:
			_climb_t = 0.0
			# Лестницы и леса пересобираем, только если что-то поменялось.
			var sig := _climb_signature()
			if sig != _climb_sig:
				_climb_sig = sig
				_rebuild_climb()
		for p in projects:
			if not p.paused:
				_try_pay(p)
		_tick_exposure(step)
		# Износ — медленный: считаем раз в секунду игры (обход всех построек дорогой).
		_wear_acc += step
		if _wear_acc >= 1.0:
			_wear_tick(_wear_acc)
			_wear_acc = 0.0
			_absorb_site_drops()
		# Энергия — дважды в секунду: итог тот же, считать дешевле. (Жизнь раз в секунду
		# пробовали — колонии в долгих прогонах вымирали; жизнь — на каждом подшаге.)
		_power_acc += step
		if _power_acc >= 0.5:
			_power_tick(_power_acc)
			_power_acc = 0.0
		_lifts_tick(step)
		_drills_tick(step)
		_oil_tick(step)
		_plant_tick(step)
		_season_tick()
		_life_tick(step, false)
		for u: Unit in units.duplicate():
			_update_unit(u, step)
	physics.update(dt)
	elements.update(dt)
	loads.update(dt)
	_explore_t += dt
	if _explore_t >= 1.0:
		_explore_t = 0.0
		_sync_held()
		explore()
		_priority_tick()
		_access_t += 1
		if _access_t >= 5:
			_access_t = 0
			_check_access()
			_check_sources()
			_check_under_drills()
			_settle_drops()
		# Воду откачали — затопленная стройка продолжается сама.
		for p in projects:
			if p.paused and p.blocked.begins_with("В зоне"):
				_check_liquids(p)
				if p.blocked.is_empty():
					p.paused = false
					_log("%s: вода ушла, работы продолжаются" % p.title(), "good")


## Гаврики открывают карту вокруг себя.
func explore() -> void:
	for u in units:
		explored_min = mini(explored_min, roundi(u.pos.x) - EXPLORE_RADIUS)
		explored_max = maxi(explored_max, roundi(u.pos.x) + EXPLORE_RADIUS)
		deepest_y = maxi(deepest_y, roundi(u.pos.y))
		highest_y = mini(highest_y, roundi(u.pos.y))


func is_explored(x: int) -> bool:
	return x >= explored_min and x <= explored_max


func _update_unit(u: Unit, dt: float) -> void:
	u.anim += dt
	_construction_recheck(u, dt)
	if u.state != Unit.State.SWIM and _head_in_water(u):
		_drop(u)
		_start_swim(u)
	match u.state:
		Unit.State.SWIM:
			if u.path_i >= u.path.size():
				u.state = Unit.State.IDLE
				if _head_in_water(u):
					_start_swim(u)
				return
			var next := Vector2(u.path[u.path_i])
			var delta := next - u.pos
			var step := CLIMB_SPEED * 0.8 * dt
			if delta.length() <= step:
				u.pos = next
				u.path_i += 1
			else:
				u.pos += delta.normalized() * step
		Unit.State.IDLE:
			if not pathing.standable(u.cell()):
				u.state = Unit.State.FALL
				u.fall_from = u.pos.y
				return
			u.retry -= dt
			if u.retry <= 0.0:
				if _assign(u):
					u.idle_fails = 0
				else:
					# Дела нет — ищем реже, чтобы толпа бездельников не грузила игру.
					u.idle_fails += 1
					# Ждёт следующей работы своей выработки — смотрит часто.
					# Новая стройка или приказ будят сразу (wake_idle); сама собой работа
					# появляется реже — долгие бездельники ищут раз в IDLE_RETRY_MAX с (поиск
					# пути дорогой: два десятка бездельников съедали половину расчёта игры).
					u.retry = 0.5 if u.waiting_own else minf(1.5 + 0.75 * u.idle_fails, IDLE_RETRY_MAX)
					# Давно без дела — идёт отдыхать домой, в свою спальню (раньше стоял толпой,
					# где кончил работу: у склада, в дегазации).
					var here := project_at(u.cell())
					var at_home := here != null and (here.id == u.bed_room or (u.bed_room == 0 and here.purpose == RoomType.HOME))
					if not offline and u.idle_fails == IDLE_HOME_AFTER and not u.waiting_own and not u.child and u.workplace == 0 \
							and not at_home and _stroll(u, true):
						pass
					# Бездельники не стоят толпой в одной точке и не торчат на лестнице (мешают
					# проходу) — расходятся по комнатам.
					elif not offline and u.state == Unit.State.IDLE:
						var on_ladder := pathing.climbable(u.cell()) and not u.waiting_own
						if (on_ladder or _crowded(u)) and not _stroll(u) and on_ladder:
							_off_ladder(u)
		Unit.State.FALL:
			u.pos.x = roundf(u.pos.x)
			var k := Vector2i(roundi(u.pos.x), floori(u.pos.y))
			if not pathing.passable(k):
				_unbury(u)
				return
			# Падает до первой опоры — сквозь породу не проваливается.
			var to_y := u.pos.y + FALL_SPEED * dt
			while k.y <= floori(to_y):
				# Падает в неизведанную пустоту — видит, что под ним (иначе «зависнет» над ней).
				if not world.is_revealed(k.x, k.y + 1):
					for n in world.reveal_around(k.x, k.y, 1):
						_note_discovery(world.get_mat(n.x, n.y), n)
				if pathing.standable(k) or not pathing.passable(k + Vector2i(0, 1)):
					_land(u, k)
					return
				k += Vector2i(0, 1)
			u.pos.y = to_y
		Unit.State.MOVE:
			if not _task_valid(u) or _needs_interrupt(u):
				_drop(u)
				return
			_move(u, dt)
		Unit.State.WORK:
			if not _task_valid(u) or _needs_interrupt(u):
				_drop(u)
				return
			# Ждать у своей стройки — STAY_TIME с конца работы, а не с начала (клетку твёрдой
			# породы копают дольше — докопав, сразу уходил домой, а копать звали других сверху).
			if u.project_id == u.last_project and u.task in [Unit.Task.DIG, Unit.Task.SUPPORT, Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.REPAIR]:
				u.last_work_t = game_time
			_work(u, dt)


## Рядом (в той же клетке) стоит другой гаврик без дела.
func _crowded(u: Unit) -> bool:
	for o in units:
		if o != u and o.state == Unit.State.IDLE and absf(o.pos.x - u.pos.x) < 0.8 and absf(o.pos.y - u.pos.y) < 0.5:
			return true
	return false


## Гаврик без дела отходит на свободное место: в свою спальню, а если до неё
## не дойти — в ближайшую комнату, где никто не стоит. home_only — только домой, хоть
## и далеко (давно без дела — идёт отдыхать).
func _stroll(u: Unit, home_only := false) -> bool:
	var reach := pathing.explore(u.cell())
	var dist: Dictionary = reach[1]
	var taken := {}
	for o in units:
		if o != u:
			taken[o.cell()] = true
			if o.task == Unit.Task.STROLL:
				taken[o.target] = true
	var home: Array[Vector2i] = []
	var near: Array[Vector2i] = []
	for p in projects:
		if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE:
			continue
		for x in range(RoomType.floor_start(p), p.rect.end.x):
			var c := Vector2i(x, p.rect.end.y - 1)
			if taken.has(c) or not dist.has(c) or c == u.cell() or pathing.climbable(c):
				continue
			# Своя спальня; кровати ещё нет — любой жилой дом.
			var mine := p.id == u.bed_room or (home_only and u.bed_room == 0 and p.purpose == RoomType.HOME)
			if mine and (dist[c] <= 80 or home_only):
				home.append(c)
			elif dist[c] <= 40 and not home_only:
				near.append(c)
	var pool := home if not home.is_empty() else near
	if pool.is_empty():
		return false
	var to: Vector2i = pool[rng.randi() % pool.size()]
	_start(u, Unit.Task.STROLL, to, to, 0, reach[0])
	return true


## Бездельник на лестнице, а свободной комнаты рядом нет — сходит с лестницы на ближайшее
## место, где можно стоять.
func _off_ladder(u: Unit) -> bool:
	var reach := pathing.explore(u.cell())
	var dist: Dictionary = reach[1]
	var taken := {}
	for o in units:
		if o != u:
			taken[o.cell()] = true
	var best = null
	for c: Vector2i in dist:
		if pathing.climbable(c) or taken.has(c) or (best != null and dist[c] >= dist[best]):
			continue
		best = c
	if best == null:
		return false
	_start(u, Unit.Task.STROLL, best, best, 0, reach[0])
	return true


## Приземление: с высоты больше 4 м — травма.
func _land(u: Unit, c: Vector2i) -> void:
	u.pos.y = c.y
	u.state = Unit.State.IDLE
	var height := c.y - u.fall_from
	if height > 4.0 and not offline:
		injure(u, (height - 4.0) * 12.0, "упал(а) с высоты %d м" % roundi(height))


## Гаврика засыпало породой: выбирается в ближайшую пустоту или гибнет.
func _unbury(u: Unit) -> void:
	var start := u.cell()
	for r in range(1, 6):
		for d in [Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, 0), Vector2i(-r, -r), Vector2i(r, -r), Vector2i(0, r)]:
			var c: Vector2i = start + d
			if pathing.passable(c) and pathing.passable(c + Vector2i(0, -1)):
				u.pos = Vector2(c)
				u.state = Unit.State.FALL
				u.fall_from = u.pos.y
				injure(u, 20.0, "засыпало породой — еле выбрался(лась)")
				return
	injure(u, 200.0, "засыпало породой")


func _head_in_water(u: Unit) -> bool:
	var h := u.cell() + Vector2i(0, -1)
	return world.get_mat(h.x, h.y) == Mat.WATER


## Гаврик под водой: плывёт к ближайшему месту, где можно встать и дышать.
func _start_swim(u: Unit) -> void:
	var start := u.cell()
	var parents := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var goal = null
	while head < queue.size() and queue.size() < 800:
		var c := queue[head]
		head += 1
		if c != start and pathing.node(c):
			goal = c
			break
		for d in DIRS4:
			var n: Vector2i = c + d
			if parents.has(n):
				continue
			var m := world.get_mat(n.x, n.y)
			if m == Mat.WATER or m == Mat.AIR:
				parents[n] = c
				queue.append(n)
	u.path.clear()
	u.path_i = 0
	u.state = Unit.State.SWIM
	if goal != null:
		u.path = Pathing.path_to(parents, goal)


## Сколько секунд разведчик осматривается на месте.
const SCOUT_WAIT := 15.0
const SCOUT_EVERY := 30.0


## Отправить гаврика в точку target (или как можно ближе к ней). Возвращает, куда он пойдёт.
func send_unit(u: Unit, target: Vector2i) -> Variant:
	var reach := pathing.explore(u.cell())
	var dist: Dictionary = reach[1]
	var best = null
	var best_d := INF
	for c: Vector2i in dist:
		var d: float = Vector2(c - target).length() + dist[c] * 0.01
		if d < best_d:
			best_d = d
			best = c
	if best == null or best == u.cell():
		return null
	_drop(u)
	_start(u, Unit.Task.GOTO, best, best, 0, reach[0])
	return best


## Затопило готовую постройку.
func on_flooded(p: Project, _c: Vector2i) -> void:
	elements._warn_once("flood%d" % p.id, "Затопило: %s! Нужна насосная (назначение комнаты)" % p.title(), "danger")


## Удобно ли гаврику в клетке: не холоднее и не жарче, чем он терпит.
func comfortable(u: Unit, c: Vector2i) -> bool:
	var t := elements.temperature(c)
	return t >= cold_limit(u) and t <= elements.heat_limit(u)


## Гаврик мёрзнет (или перегрелся) и уже заметно ослаб — пора в тепло.
func needs_warmth(u: Unit) -> bool:
	return u.health < WARM_HEALTH and not u.invulnerable() and not comfortable(u, u.cell())


## Ближайшее место, где гаврику не холодно и не жарко (с запасом 3 °C), — туда греться.
func _start_warm(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var best = null
	var best_d := 1 << 30
	var lo := cold_limit(u) + 3.0
	var hi := elements.heat_limit(u) - 3.0
	for c: Vector2i in dist:
		if dist[c] >= best_d:
			continue
		var t := elements.temperature(c)
		if t >= lo and t <= hi:
			best_d = dist[c]
			best = c
	if best == null:
		return false
	_drop(u)
	_start(u, Unit.Task.WARM, best, best, 0, parents)
	return true


## Совсем устал или голоден — бросает работу.
func _needs_interrupt(u: Unit) -> bool:
	if u.task == Unit.Task.SLEEP or u.task == Unit.Task.EAT or u.task == Unit.Task.WARM:
		return false
	return (u.satiety < 15.0 and has_food()) or needs_warmth(u)


## «Канаты и блоки» — по лестницам быстрее; «Рельсы» — с грузом по шахтам и горизонтальным
## тоннелям быстрее.
func _track_factor(u: Unit, climbing: bool) -> float:
	if climbing:
		return 1.5 if research.has("ropes") else 1.0
	if not research.has("rails") or u.carry_amount <= 0:
		return 1.0
	var pid: int = interior.get(u.cell(), 0)
	if pid == 0:
		return 1.0
	var p := project_by_id(pid)
	if p != null and (p.kind == Project.Kind.MINE or (p.kind == Project.Kind.TUNNEL and not p.vertical())):
		return 1.5
	return 1.0


## «Ученичество»: пока родитель работает, у ребёнка растёт навык этой работы.
const APPRENTICE_RATE := 0.15


func _apprentice(u: Unit, dt: float) -> void:
	if not research.has("apprentice"):
		return
	for pid in [u.mother_id, u.father_id]:
		if pid == 0:
			continue
		var parent := _unit_by_id(pid)
		if parent == null or parent.state != Unit.State.WORK:
			continue
		var skill := Unit.skill_for(parent.task)
		if not skill.is_empty():
			u.skills[skill] = float(u.skills.get(skill, 0.0)) + dt * APPRENTICE_RATE * u.stat("learning")


## Замедление в тесном тоннеле: поток ограничен его шириной.
var _occ := {}
var _occ_at := -1.0


func congestion(u: Unit) -> float:
	# Готовые ходы — по карте построек; перебор строек — только на лесах идущей стройки.
	var c := u.cell()
	var p: Project = null
	var pid: int = interior.get(c, 0)
	if pid != 0:
		p = project_by_id(pid)
	elif pathing.sites.has(c):
		p = project_at(c)
	if p == null or p.kind != Project.Kind.TUNNEL:
		return 1.0
	var vertical := p.rect.size.y > p.rect.size.x
	# Кто где стоит — раз за шаг, а не перебором всех гавриков для каждого идущего.
	if _occ_at != game_time:
		_occ_at = game_time
		_occ.clear()
		for o in units:
			var oc := o.cell()
			if not _occ.has(oc):
				_occ[oc] = []
			_occ[oc].append(o)
	var crowd := 1
	var r := p.rect
	var xs := range(r.position.x, r.end.x) if vertical else range(c.x - 2, c.x + 3)
	var ys := range(c.y - 2, c.y + 3) if vertical else range(r.position.y, r.end.y)
	for y in ys:
		for x in xs:
			var q := Vector2i(x, y)
			if not r.has_point(q) or not _occ.has(q):
				continue
			for o: Unit in _occ[q]:
				if o == u:
					continue
				var d := absf(o.pos.y - u.pos.y) if vertical else absf(o.pos.x - u.pos.x)
				if d <= 1.2:
					crowd += 1
	return minf(1.0, float(tunnel_lanes(p.rect)) / crowd)


func _move(u: Unit, dt: float) -> void:
	var budget := dt
	var jam := congestion(u)
	# В лифте: кабина везёт сама; у лифта — ждём кабину.
	if u.lift_id != 0:
		return
	while budget > 0.0 and u.path_i < u.path.size():
		if _try_board(u):
			return
		# Путь устарел (рухнуло, убрали лестницу) — останавливаемся и ищем заново.
		if not pathing.node(u.path[u.path_i]):
			_drop(u)
			return
		var next := Vector2(u.path[u.path_i])
		var delta := next - u.pos
		var climbing := absf(delta.y) > absf(delta.x)
		var spd := (CLIMB_SPEED if climbing else WALK_SPEED) * jam * u.move_factor() * _track_factor(u, climbing)
		if u.child:
			spd *= 0.8
		if world.get_mat(u.cell().x, u.cell().y) == Mat.WATER:
			spd *= 0.5 # плывут
		spd *= u.stat("speed") * (0.8 if u.is_elder() else 1.0)
		var dist := delta.length()
		if dist <= spd * budget:
			u.pos = next
			budget -= dist / spd
			u.path_i += 1
		else:
			u.pos += delta / dist * spd * budget
			budget = 0.0
		if absf(delta.x) > 0.01:
			u.facing = 1 if delta.x > 0 else -1
	if u.path_i >= u.path.size():
		u.state = Unit.State.WORK
		u.work_t = 0.0
		if u.takeover != 0:
			_arrive_takeover(u)
		if u.task == Unit.Task.DIG or u.task == Unit.Task.HARVEST:
			if u.target.x != u.cell().x:
				u.facing = 1 if u.target.x > u.cell().x else -1
		elif u.task == Unit.Task.FISH:
			# Рыбак смотрит на воду — к середине озера.
			var lake := _lake_near(u.cell().x)
			if not lake.is_empty():
				var span := world.gen.lake_water_span(lake)
				var mid := (span.x + span.y) * 0.5
				if absf(mid - u.pos.x) > 0.01:
					u.facing = 1 if mid > u.pos.x else -1


## Смягчённая характеристика: +30% силы — это +18% к скорости работы.
# --- Свет -----------------------------------------------------------------------------

## Под землёй темно: пока нет электричества, светит только солнце — сверху и в открытую шахту.
const DARK_WORK := 0.7
## Как глубоко солнце проникает в открытую сверху шахту.
const SUN_SHAFT := 8
## Светящийся гаврик освещает всё вокруг себя.
const GLOW_RADIUS := 4


## Светло ли в клетке: над землёй, в открытой шахте недалеко от неба, в комнате, где горит свет,
## у лампы на стройке, рядом со светящимся гавриком.
func is_lit(c: Vector2i) -> bool:
	if sunlit(c):
		return true
	if interior.has(c):
		var p := project_by_id(interior[c])
		if p != null and p.lit:
			return true
	for l in work_lamps:
		if l.distance_squared_to(c) <= LAMP_RADIUS * LAMP_RADIUS:
			return true
	for o in units:
		if o.ability("light") == true and o.cell().distance_squared_to(c) <= GLOW_RADIUS * GLOW_RADIUS:
			return true
	return false


## Солнце: над землёй и в открытой сверху шахте недалеко от неба.
func sunlit(c: Vector2i) -> bool:
	var surf := world.gen.surface_y(c.x)
	if c.y < surf:
		return true
	if c.y - surf < SUN_SHAFT:
		for y in range(surf, c.y):
			if Mat.is_solid(world.get_mat(c.x, y)):
				return false
		return true
	return false


## Свет от электричества: 1 единица энергии на лампочку. В комнате по лампочке на каждые 3 м,
## свет включается и выключается во всей комнате сразу. По умолчанию горит в комнатах ближе
## к генератору, пока хватает энергии. На стройке и в шахте — одна лампа там, где сейчас работают.
const LAMP_RADIUS := 3
var work_lamps: Array[Vector2i] = []


## Комната, где может гореть электрический свет (под землёй).
func lightable(p: Project) -> bool:
	return p.kind == Project.Kind.ROOM and (p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP) \
		and is_underground(p)


## Пересчитать свет сразу (после переключения в комнате).
func relight() -> void:
	_power_tick(0.0)


func _lights_tick() -> void:
	work_lamps.clear()
	for p in projects:
		p.lit = p.purpose == RoomType.SHIP and p.phase == Project.Phase.DONE
	if not powered():
		return
	# Включённые вручную горят всегда.
	var auto: Array[Project] = []
	for p in projects:
		if not lightable(p) or p.purpose == RoomType.SHIP:
			continue
		if p.light == 1:
			p.lit = true
			power_used += RoomType.blocks(p)
		elif p.light == -1:
			auto.append(p)
	# Лампы на стройках — по одной там, где сейчас работают (если там темно).
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing) or power_made - power_used < 1:
			continue
		for u in units:
			if u.project_id == p.id and u.state == Unit.State.WORK \
					and u.task in [Unit.Task.DIG, Unit.Task.BUILD, Unit.Task.SUPPORT, Unit.Task.EQUIP, Unit.Task.REPAIR] \
					and not sunlit(u.cell()):
				work_lamps.append(u.cell())
				power_used += 1
				break
	# Остальные комнаты — от ближних к генератору, пока хватает энергии (комната целиком).
	var gens := generators()
	var dist_of := func(p: Project) -> int:
		var best := 1 << 30
		for g in gens:
			var d := g.rect.get_center() - p.rect.get_center()
			best = mini(best, absi(d.x) + absi(d.y))
		return best
	auto.sort_custom(func(a: Project, b: Project) -> bool: return dist_of.call(a) < dist_of.call(b))
	for p in auto:
		var n := RoomType.blocks(p)
		if power_made - power_used >= n:
			p.lit = true
			power_used += n


## Множитель работы от освещения: в темноте медленнее, зоркие — меньше теряют;
## меланисты видят в темноте, а безглазым свет не нужен.
func light_factor(u: Unit) -> float:
	if u.genome.is_empty() or u.ability("night_vision") == true or Genetics.eyes_of(u.genome) == 0:
		return 1.0
	if is_lit(u.cell()):
		return 1.0
	return minf(1.0, DARK_WORK * soft(u.stat("vision")))


static func soft(v: float) -> float:
	return 1.0 + (v - 1.0) * 0.6


## Насколько быстро гаврик делает эту работу — от характеристик, умений и мутаций.
## Без глаз — всё очень медленно, но руду в тёмной глубине добывает вдвое быстрее.
func work_factor(u: Unit, task: int, c: Vector2i) -> float:
	if u.genome.is_empty():
		return 1.0
	var work: float = u.ability("work")
	var fit := stat_fit(u, task)
	match task:
		Unit.Task.DIG:
			var deep := c.y - world.gen.surface_y(c.x) > 10
			if deep and Mat.is_ore(world.get_mat(c.x, c.y)):
				work = maxf(work, 1.0) * u.ability("deep_mining")
			return fit * u.ability("dig") * work
		Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.SUPPORT:
			return fit * u.ability("build") * work
		Unit.Task.REPAIR:
			return fit * u.ability("repair") * work
	return fit * work


func _work(u: Unit, dt: float) -> void:
	var skill := Unit.skill_for(u.task)
	var rate := dt
	if not skill.is_empty():
		var before := u.level(skill)
		# По призванию навык растёт быстрее, не по душе — медленнее.
		var grow: float = [0.5, 1.0, 1.5][calling_of(u, u.task) + 1]
		u.skills[skill] += dt * u.stat("learning") * grow
		if u.level(skill) > before:
			_log("%s: навык «%s» вырос до %d" % [u.name, Unit.SKILL_NAMES[skill], u.level(skill)], "good")
		rate = dt * u.speed(skill) * u.need_factor() * work_factor(u, u.task, u.target) * u.age_factor() * light_factor(u)
	match u.task:
		Unit.Task.DIG:
			var c := u.target
			elements.spark(u.cell())
			dig_progress[c] = dig_progress.get(c, 0.0) + rate * dig_bonus()
			if dig_progress[c] >= dig_time(c):
				var p := project_by_id(u.project_id)
				_drop(u)
				_complete_dig(c, p, u)
				_continue_own(u)
		Unit.Task.BUILD:
			var p := project_by_id(u.project_id)
			p.build_done += rate * build_bonus()
			if p.build_done >= p.build_work():
				_finish_project(p)
		Unit.Task.EQUIP:
			var p := project_by_id(u.project_id)
			p.equip_done += rate
			if p.equip_done >= RoomType.job_work(p):
				_finish_equip(p)
		Unit.Task.HARVEST:
			var x := u.target.x
			harvest_progress[x] = harvest_progress.get(x, 0.0) + rate
			if harvest_progress[x] >= HARVEST_TIME.get(world.feature_at(x), 20.0):
				var room := u.gather_room
				_drop(u)
				_complete_harvest(x, u, room)
		Unit.Task.HAUL:
			if u.haul_stage == 0:
				_haul_pickup(u)
			else:
				_haul_deliver(u)
		Unit.Task.GOTO:
			u.work_t += dt
			if u.work_t >= SCOUT_WAIT:
				_drop(u)
		Unit.Task.STROLL:
			_drop(u)
		Unit.Task.WARM:
			u.work_t += dt
			if u.health >= WARM_UNTIL or u.work_t >= WARM_MAX or not comfortable(u, u.cell()):
				_drop(u)
		Unit.Task.REPAIR:
			var rp := project_by_id(u.project_id)
			rp.repair_done += rate * build_bonus()
			if rp.repair_done >= rp.repair_work:
				_finish_repair(rp)
		Unit.Task.CRAFT:
			var cp := project_by_id(u.project_id)
			if _mark_full(cp):
				_drop(u)
				return
			var cr := recipe(cp)
			if cr.is_empty():
				_drop(u)
				return
			if cp.purpose == RoomType.ENRICHMENT:
				irradiate(u)
			cp.farm_progress += rate * automation_bonus()
			if cp.farm_progress >= cr[2]:
				cp.farm_progress = 0.0
				_craft(cp)
			u.work_t += dt
			if u.work_t >= FARM_SHIFT:
				_drop(u)
		Unit.Task.RESEARCH:
			_research(rate * automation_bonus())
			u.work_t += dt
			if u.work_t >= FARM_SHIFT:
				_drop(u)
		Unit.Task.FARM:
			var p := project_by_id(u.project_id)
			if _mark_full(p):
				_drop(u)
				return
			p.farm_progress += rate * farm_bonus()
			while p.farm_progress >= RoomType.FARM_CYCLE:
				p.farm_progress -= RoomType.FARM_CYCLE
				_produce(p, "food", 1)
			u.work_t += dt
			if u.work_t >= FARM_SHIFT:
				_drop(u)
		Unit.Task.SLEEP:
			# Сна больше нет (старые сохранения): спящий сразу встаёт.
			_drop(u)
		Unit.Task.EAT:
			u.work_t += dt
			if u.work_t >= EAT_TIME:
				var bx := u.target.x
				var at := u.target
				if u.project_id == EAT_BUSH:
					_eat_from(u, func(key: String, n: int) -> int: return _take_bush(bx, key, n))
				elif u.project_id == EAT_DROP:
					_eat_from(u, func(key: String, n: int) -> int: return _take_drop(at, key, n))
				else:
					_eat_from(u, _take_store, DINING_BONUS if u.project_id != 0 else 1.0)
				_drop(u)
		Unit.Task.SUPPORT:
			var sp := project_by_id(u.project_id)
			sp.support_progress += rate
			if sp.support_progress >= sp.slice_work():
				_finish_support(sp)
				_continue_own(u)
		Unit.Task.FISH:
			u.work_t += rate
			if u.project_id == 0:
				if u.work_t >= SHORE_FISH_TIME:
					var lake := _lake_near(u.target.x)
					_drop(u)
					_catch_from(lake, u)
			else:
				var fp := project_by_id(u.project_id)
				if u.work_t >= fish_time(fp):
					_drop(u)
					_catch_fish(fp, u)


func _task_valid(u: Unit) -> bool:
	match u.task:
		Unit.Task.DIG, Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.FARM:
			var p := project_by_id(u.project_id)
			if p == null or p.paused:
				return false
			match u.task:
				Unit.Task.DIG:
					return p.phase == Project.Phase.DIG and Mat.is_solid(world.get_mat(u.target.x, u.target.y))
				Unit.Task.BUILD:
					return p.phase == Project.Phase.BUILD and p.paid
				Unit.Task.EQUIP:
					return p.phase == Project.Phase.EQUIP and p.equip_paid
				Unit.Task.FARM:
					return p.phase == Project.Phase.DONE and p.purpose == RoomType.FARM and farm_warm(p)
		Unit.Task.CRAFT:
			var cp := project_by_id(u.project_id)
			return cp != null and not cp.paused and cp.phase == Project.Phase.DONE and RoomType.RECIPES.has(cp.purpose) \
				and has_inputs(cp)
		Unit.Task.RESEARCH:
			var lp := project_by_id(u.project_id)
			return lp != null and not lp.paused and lp.phase == Project.Phase.DONE and lp.purpose == RoomType.LAB \
				and not research.current.is_empty()
		Unit.Task.HARVEST:
			if u.project_id != 0:
				var hp := project_by_id(u.project_id)
				if hp == null or hp.paused:
					return false
				# Расчистка стройки: убирают всё, что стоит на месте, даже не отмеченное
				# (деревце, выросшее из пня уже после закладки).
				if hp.clear_x.has(u.target.x):
					return harvestable(u.target.x)
			if u.gather_room != 0:
				var room := project_by_id(u.gather_room)
				return room != null and RoomType.is_store(room.purpose) and harvestable(u.target.x)
			return world.feature_marks.has(u.target.x) and harvestable(u.target.x)
		Unit.Task.HAUL:
			if u.haul_stage == 0 and u.from_drop and drop_amount(u.haul_src, u.carry_key) <= 0:
				return false
			if u.to_store or u.gather_room != 0:
				return true
			var tp := project_by_id(u.project_id)
			if tp == null or tp.paused:
				return false
			if u.haul_stage == 0:
				var wanted := _is_supply(tp) or not required(tp).is_empty()
				return (u.from_drop or inventory.get(u.carry_key, 0) > 0) and wanted
			return true
		Unit.Task.REPAIR:
			var rp := project_by_id(u.project_id)
			return rp != null and not rp.paused and rp.repairing and rp.repair_paid
		Unit.Task.EAT:
			if u.project_id == EAT_BUSH:
				return world.feature_at(u.target.x) == WorldGen.FEATURE_BUSH and world.berries(u.target.x) >= 1.0
			if u.project_id == EAT_DROP:
				return drop_amount(u.target, "food") + drop_amount(u.target, "fish") + drop_amount(u.target, "berries") > 0
			return true
		Unit.Task.FISH:
			if u.project_id == 0:
				return fish_in(_lake_near(u.target.x)) >= 1.0
			var fp := project_by_id(u.project_id)
			return fp != null and not fp.paused and fp.phase == Project.Phase.DONE and fish_left(fp) >= 1.0
		Unit.Task.SUPPORT:
			var sp := project_by_id(u.project_id)
			return sp != null and not sp.paused and sp.phase == Project.Phase.DIG and sp.support_paid and sp.support_slice >= 0
		Unit.Task.SLEEP, Unit.Task.GOTO, Unit.Task.STROLL, Unit.Task.WARM:
			return true
	return false


func _drop(u: Unit) -> void:
	var key = _reserve_key(u)
	if key != null and reserved.get(key) == u.id:
		reserved.erase(key)
	# Брошенный груз остаётся лежать, где гаврик его бросил.
	if u.task == Unit.Task.HAUL and u.haul_stage == 1 and u.carry_amount > 0:
		drop_item(u.cell(), u.carry_key, u.carry_amount)
	u.carry_key = ""
	u.carry_amount = 0
	u.haul_stage = 0
	u.gather_room = 0
	u.from_drop = false
	u.to_store = false
	u.lift_id = 0
	u.riding = false
	u.cargo_end = -1
	if u.takeover != 0:
		var o := _unit_by_id(u.takeover)
		if o != null and o.takeover_by == u.id:
			o.takeover_by = 0
		u.takeover = 0
	u.takeover_by = 0
	u.task = Unit.Task.NONE
	u.project_id = 0
	u.path.clear()
	u.path_i = 0
	u.work_t = 0.0
	if u.state != Unit.State.FALL:
		u.state = Unit.State.IDLE
	u.retry = 0.2


func _reserve_key(u: Unit) -> Variant:
	match u.task:
		Unit.Task.DIG:
			return u.target
		Unit.Task.SUPPORT:
			return "s%d" % u.project_id
		Unit.Task.HARVEST:
			return "h%d" % u.target.x
		Unit.Task.EAT:
			if u.project_id == EAT_BUSH:
				return "e%d" % u.target.x
		Unit.Task.FISH:
			if u.project_id == 0:
				return "f%d,%d" % [u.target.x, u.target.y]
	return null


## Порядок занятий гаврика: сначала его профессия, затем общая очередь.
## Порядок дел. Назначенный — сначала своё место работы. Остальное — только нужное
## колонии: стройки (копка, укрепление, стройка, доставка материалов) и сбор по нужде
## (не хватает материалов на стройку, нечего есть). Сами по себе свободные гаврики не
## рубят, не ловят рыбу, не фермерствуют и ничего не носят на хранение.
func _task_order(u: Unit) -> Array[String]:
	# need — добыть то, чего не хватает стройке: это тоже стройка, она важнее переноски.
	if u.workplace != 0:
		return ["workplace", "projects", "need", "haul"]
	if u.profession == Unit.Prof.HAULER:
		return ["haul", "projects", "need"]
	# Шахтёр — только шахты (копает, крепит, чинит), строитель — остальные стройки.
	if u.profession == Unit.Prof.MINER:
		return ["mines"]
	if u.profession == Unit.Prof.BUILDER:
		return ["builds", "projects", "need"]
	# Строители и свободные: сначала стройка, потом переноска.
	return ["projects", "need", "haul"]


## Ищет занятие для гаврика. true — назначено.
func _assign(u: Unit) -> bool:
	var reach := pathing.explore(u.cell())
	var parents: Dictionary = reach[0]
	var dist: Dictionary = reach[1]
	# Мёрзнет (или перегрелся) и уже ослаб — идёт в тепло (раньше отогревались во сне).
	if needs_warmth(u) and _start_warm(u, parents, dist):
		return true
	if u.satiety < HUNGRY:
		if has_food():
			_start_eat(u, parents, dist)
			return true
		# На складе пусто — ест то, что лежит на земле, или идёт искать ягоды.
		if _start_eat_drop(u, parents, dist) or _start_eat_bush(u, parents, dist):
			return true
		# Ягод нет — ловит рыбу себе и сразу съедает (впрок без указания не добывает).
		if not u.child and _try_fish(u, parents, dist):
			return true
	if u.child:
		return false
	var own := _own_project(u)
	u.waiting_own = false
	if own != null:
		if _try_project(u, own, parents, dist, has_crew(Unit.Prof.MINER), has_crew(Unit.Prof.BUILDER)):
			return true
		# Работа своей выработки сейчас у другого — ждём рядом (ищем снова скоро).
		u.idle_fails = 0
		u.waiting_own = true
		return false
	for kind in _task_order(u):
		match kind:
			"workplace":
				if _try_workplace(u, parents, dist):
					return true
			"harvest":
				if _try_harvest(u, parents, dist):
					return true
			"farm":
				if _try_farm(u, parents, dist):
					return true
			"craft":
				for t in RoomType.RECIPES:
					if _try_room_work(u, t, Unit.Task.CRAFT, parents, dist):
						return true
			"science":
				if not research.current.is_empty() and _try_room_work(u, RoomType.LAB, Unit.Task.RESEARCH, parents, dist):
					return true
			"fish":
				if _try_fish(u, parents, dist):
					return true
			"storage":
				if _try_storage(u, parents, dist):
					return true
			"cleanup":
				if _try_cleanup(u, parents, dist):
					return true
			"need":
				if _try_need(u, parents, dist):
					return true
			"haul":
				if _try_logistics(u, parents, dist):
					return true
			"projects":
				if _try_projects(u, parents, dist):
					return true
			"mines":
				if _try_projects(u, parents, dist, Project.Kind.MINE):
					return true
			"builds":
				if _try_projects(u, parents, dist, -1, Project.Kind.MINE):
					return true
	return _return_home(u, parents, dist)


## Ушёл далеко (на разведку, за кучей на краю карты) и дела рядом нет: работа ищется только
## в пределах обхода (Pathing.MAX_RADIUS), так что дальше от базы гаврик застрял бы навсегда.
## Идёт к базе — к самой близкой к ней клетке, куда может дойти.
const FAR_FROM_HOME := 60


## Сами по себе (сбор по нужде и до нормы склада, разведка, кучи для строек) гаврики не уходят
## от базы дальше HOME_RANGE: оттуда добытое уже не донести — обход не достаёт до склада, и
## гаврик бегал бы туда-обратно впустую.
const HOME_RANGE := Pathing.MAX_RADIUS - 20


func near_home(x: int) -> bool:
	return absi(x - home.x) <= HOME_RANGE


func _return_home(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var off := absi(u.cell().x - home.x)
	if off <= FAR_FROM_HOME:
		return false
	var best = null
	var best_off := off - 10
	for c: Vector2i in dist:
		var o := absi(c.x - home.x)
		if o < best_off or (o == best_off and best != null and dist[c] < dist[best]):
			best_off = o
			best = c
	if best == null:
		return false
	_start(u, Unit.Task.GOTO, best, best, 0, parents)
	return true


## Стройки: копка, расчистка, укрепление, стройка, обустройство, ремонт, доставка материалов.
## Назначенный строитель, если места заняты свободными, занимает место одного из них.
## only — только стройки этого вида, skip — кроме этого вида. Шахтёр вытесняет свободного
## из шахты, строитель — с остальных строек.
func _try_projects(u: Unit, parents: Dictionary, dist: Dictionary, only := -1, skip := -1) -> bool:
	var miners := has_crew(Unit.Prof.MINER)
	var builders := has_crew(Unit.Prof.BUILDER)
	for p in _projects_for(u, dist):
		if (only >= 0 and p.kind != only) or (skip >= 0 and p.kind == skip):
			continue
		if _try_project(u, p, parents, dist, miners, builders):
			return true
	return false


## Работа на одной стройке: копка, расчистка, укрепление, стройка, обустройство, ремонт, доставка.
func _try_project(u: Unit, p: Project, parents: Dictionary, dist: Dictionary, miners: bool, builders: bool) -> bool:
	if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
		return false
	# Ход, который сверлит бур, гаврики не копают (место под бур и бур-лифт — копают).
	if p.bored_by > 0:
		return false
	var mine := p.kind == Project.Kind.MINE
	var crew := _crew_ok(u, mine, miners, builders)
	# Своя бригада (строители, у шахты — шахтёры) идёт без ограничения мест; места в карточке —
	# для помощников. Помощник уступает клетку подошедшему строителю (см. _takeover).
	var own_crew := crew and builder_or_miner(u)
	if not own_crew and workers_on(p) >= p.workers:
		return false
	# Дальняя стройка (глубоко в большой колонии) — путь к ней ищут прицельно.
	_reach_far(u.cell(), p.rect, parents, dist)
	if crew:
		if p.phase == Project.Phase.DIG:
			if _try_harvest(u, parents, dist, uncleared(p), p.id) or _try_support(u, p, parents, dist) \
					or _try_dig(u, p, parents, dist):
				return true
		var task := Unit.Task.NONE
		match p.phase:
			Project.Phase.BUILD:
				task = Unit.Task.BUILD if p.paid else Unit.Task.NONE
			Project.Phase.EQUIP:
				task = Unit.Task.EQUIP if p.equip_paid else Unit.Task.NONE
			Project.Phase.DONE:
				task = Unit.Task.REPAIR if p.repair_paid else Unit.Task.NONE
		if task != Unit.Task.NONE and _try_build(u, p, task, parents, dist):
			return true
	# Строители и шахтёры материалы не носят — это работа складов и подсобных.
	# Строитель берёт сам только то, без чего его работа стоит прямо сейчас (дерево на крепь,
	# материалы на оплату этапа), и ровно столько; шахтёр — дерево на крепь своей шахты,
	# если нет свободных подсобных.
	if builder_or_miner(u):
		if crew and (u.profession == Unit.Prof.BUILDER or not free_hauler_exists()) \
				and _try_haul(u, p, parents, dist, true):
			return true
	elif (not mine or may_haul_mine(u)) and _try_haul(u, p, parents, dist):
		return true
	return false


## --- Своя стройка ------------------------------------------------------------------
## Кто копал или крепил, не бросает выработку, пока в ней есть работа: следующую клетку
## (или крепь среза) он ждёт рядом, а не уходит носить добытое — это дело других.
## Ждёт не дольше STAY_TIME с конца последней работы и не ждёт, если стройка стоит
## (пауза, тревога, нет дерева на крепь, все места заняты).
const STAY_TIME := 60.0


## Закончил клетку или крепь — сразу берёт следующую работу своей выработки, пока её
## не перехватил кто-то, кто просто стоял рядом.
func _continue_own(u: Unit) -> void:
	if u.task != Unit.Task.NONE or u.child or needs_warmth(u) or u.satiety < HUNGRY:
		return
	var own := _own_project(u)
	if own == null:
		return
	var reach := pathing.explore(u.cell())
	if _try_project(u, own, reach[0], reach[1], has_crew(Unit.Prof.MINER), has_crew(Unit.Prof.BUILDER)):
		u.idle_fails = 0


func _own_project(u: Unit) -> Project:
	if u.last_project == 0 or game_time - u.last_work_t > STAY_TIME:
		return null
	var p := project_by_id(u.last_project)
	if p == null or p.paused or p.phase != Project.Phase.DIG or not p.blocked.is_empty() or p.bored_by > 0:
		return null
	if not works_on(u, p) or (not builder_or_miner(u) and workers_on(p) >= p.workers):
		return null
	# Стройка с приоритетом важнее своей.
	for q in projects:
		if q.priority and q != p and priority_crew(u, q) and not q.paused:
			return null
	if remaining_dig(p).is_empty() and slice_to_support(p) < 0:
		return null
	var i := slice_to_support(p)
	if i >= 0 and not (p.support_paid and p.support_slice == i) and remaining_dig(p).is_empty():
		for k in ["wood", "iron"]:
			if int(p.delivered.get(k, 0)) >= support_amount(p, k):
				return p
		return null
	return p


## Кто копает и строит: шахтёр — только шахты, строитель — остальные стройки (шахты — только
## если шахтёров нет). Свободные и прочие помогают везде, где есть места; строитель и шахтёр
## на своей стройке вытесняют свободного.
func works_on(u: Unit, p: Project) -> bool:
	return _crew_ok(u, p.kind == Project.Kind.MINE, has_crew(Unit.Prof.MINER), has_crew(Unit.Prof.BUILDER))


static func _crew_ok(u: Unit, mine: bool, miners: bool, _builders: bool) -> bool:
	if u.workplace == 0:
		if u.profession == Unit.Prof.MINER:
			return mine
		if u.profession == Unit.Prof.BUILDER:
			return not mine or not miners
	return true


## Есть ли в колонии взрослый с этой профессией без места работы (строитель, шахтёр).
func has_crew(prof: int) -> bool:
	for o in units:
		if o.profession == prof and o.workplace == 0 and not o.child:
			return true
	return false


## Стройки по очереди для гаврика: сначала с приоритетом, потом та, где он только что
## работал (докапывает и крепит свою, а не бежит на первую в списке), потом остальные.
func _projects_for(u: Unit, dist: Dictionary = {}) -> Array[Project]:
	var last := project_by_id(u.last_project) if u.last_project != 0 else null
	var near := {}
	var out: Array[Project] = []
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
			continue
		out.append(p)
		var c = _near_rect(p.rect, dist) if not dist.is_empty() else null
		near[p.id] = dist[c] if c != null else 1 << 30
	# Приоритетные — первыми, потом своя, потом ближайшие: на работу идут те, кто рядом.
	out.sort_custom(func(a: Project, b: Project) -> bool:
		if a.priority != b.priority:
			return a.priority
		if (a == last) != (b == last):
			return a == last
		return near[a.id] < near[b.id])
	return out


## --- Приоритет стройки -------------------------------------------------------------
## Стройке, ремонту или шахте ставят приоритет: она первая в списке работ, и её бригада
## (строители, у шахты — шахтёры) бросает другие стройки и идёт сюда, сверх числа рабочих.
## Готово — приоритет снимается сам.
const PRIORITY_REDROP := 30.0
var _prio_dropped := {}


func priority_crew(u: Unit, p: Project) -> bool:
	return u.workplace == 0 and u.profession == (Unit.Prof.MINER if p.kind == Project.Kind.MINE else Unit.Prof.BUILDER)


func can_prioritize(p: Project) -> bool:
	return p.bored_by == 0 and (p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD
		or p.phase == Project.Phase.EQUIP or (p.phase == Project.Phase.DONE and p.repairing))


func set_priority(p: Project, on: bool) -> void:
	wake_idle()
	p.priority = on and can_prioritize(p)
	if p.priority:
		projects.erase(p)
		_by_id_n = -1
		projects.push_front(p)
		_log("%s: приоритет — бригада идёт сюда в первую очередь" % p.title(), "info")
	_priority_tick()


func _priority_tick() -> void:
	for p in projects:
		if not p.priority:
			continue
		if not can_prioritize(p):
			p.priority = false
			continue
		if p.paused or not p.blocked.is_empty():
			continue
		for u in units:
			if u.project_id == 0 or u.project_id == p.id or not priority_crew(u, p):
				continue
			var other := project_by_id(u.project_id)
			if other == null or other.priority:
				continue
			if game_time - float(_prio_dropped.get(u.id, -1000.0)) < PRIORITY_REDROP:
				continue
			_prio_dropped[u.id] = game_time
			_drop(u)


## Строитель или шахтёр (без места работы): только строят и копают, ничего не носят.
func builder_or_miner(u: Unit) -> bool:
	return u.workplace == 0 and (u.profession == Unit.Prof.BUILDER or u.profession == Unit.Prof.MINER)


## Есть ли подсобный рабочий без дела (тогда шахтёр сам не носит).
func free_hauler_exists() -> bool:
	for o in units:
		if o.workplace == 0 and o.profession == Unit.Prof.HAULER \
				and (o.task == Unit.Task.NONE or o.task == Unit.Task.STROLL):
			return true
	return false


## Кто носит в шахту и из шахты: работники складов и подсобные рабочие.
func mine_hauler(u: Unit) -> bool:
	if u.profession == Unit.Prof.HAULER and u.workplace == 0:
		return true
	var w := project_by_id(u.workplace)
	return w != null and w.purpose == RoomType.STORAGE


## Носить в шахту и из шахты: работники складов и подсобные, а если их в колонии нет —
## любой свободный (иначе добытое в шахте лежало бы вечно).
func may_haul_mine(u: Unit) -> bool:
	if mine_hauler(u):
		return true
	if builder_or_miner(u):
		return false
	for o in units:
		if not o.child and mine_hauler(o):
			return false
	return true


## Куча в шахте (или у её края).
func in_mine(c: Vector2i) -> bool:
	for p in projects:
		if p.kind == Project.Kind.MINE and p.rect.grow(1).has_point(c):
			return true
	return false


## Работник склада в первую очередь обслуживает шахты: несёт туда дерево на крепь
## и уносит добытое оттуда в свой склад.
func _try_mine_logistics(u: Unit, store: Project, parents: Dictionary, dist: Dictionary) -> bool:
	for m in projects:
		if m.kind == Project.Kind.MINE and m.phase == Project.Phase.DIG and not m.paused and _try_haul(u, m, parents, dist):
			return true
	return _try_cleanup(u, parents, dist, store, true)


func _start(u: Unit, task: int, target: Vector2i, stand: Vector2i, pid: int, parents: Dictionary) -> void:
	u.task = task
	u.target = target
	u.project_id = pid
	u.path = _lift_route(u.cell(), stand, Pathing.path_to(parents, stand))
	u.path_i = 0
	u.work_t = 0.0
	u.state = Unit.State.MOVE
	if pid != 0 and task in [Unit.Task.DIG, Unit.Task.SUPPORT, Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.REPAIR]:
		u.last_project = pid
		u.last_work_t = game_time
	var key = _reserve_key(u)
	if key != null:
		reserved[key] = u.id


func _start_eat(u: Unit, parents: Dictionary, dist: Dictionary) -> void:
	var best = null
	var best_d := 1 << 30
	var room_id := 0
	for p in rooms_of(RoomType.DINING):
		for x in range(RoomType.floor_start(p), p.rect.end.x):
			var c := Vector2i(x, p.rect.end.y - 1)
			if dist.has(c) and dist[c] < best_d:
				best_d = dist[c]
				best = c
				room_id = p.id
	# В столовую идут, только если она недалеко.
	if best != null and best_d < 80:
		_start(u, Unit.Task.EAT, best, best, room_id, parents)
	else:
		_start(u, Unit.Task.EAT, u.cell(), u.cell(), 0, parents)


func _start_eat_drop(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var best = null
	var best_c := Vector2i.ZERO
	var best_d := 1 << 30
	for c: Vector2i in drops:
		if drop_amount(c, "food") + drop_amount(c, "fish") + drop_amount(c, "berries") <= 0:
			continue
		var stand = _drop_stand(c, dist)
		if stand != null and dist[stand] < best_d:
			best_d = dist[stand]
			best = stand
			best_c = c
	if best == null:
		return false
	u.haul_src = best_c
	_start(u, Unit.Task.EAT, best_c, best, EAT_DROP, parents)
	return true


func _start_eat_bush(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var best_x = null
	var best_stand = null
	var best_d := 1 << 30
	for x in _bushes:
		if reserved.has("e%d" % x) or world.feature_at(x) != WorldGen.FEATURE_BUSH or world.berries(x) < 1.0:
			continue
		var base := Vector2i(x, world.gen.surface_y(x) - 1)
		for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
			if dist.has(stand) and dist[stand] < best_d:
				best_d = dist[stand]
				best_x = x
				best_stand = stand
	if best_x == null:
		return false
	_start(u, Unit.Task.EAT, Vector2i(best_x, world.gen.surface_y(best_x) - 1), best_stand, EAT_BUSH, parents)
	return true


## Места для рыбалки с берега: у кромки воды озёр возле базы.
const SHORE_FISH_TIME := 80.0


func shore_spots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_winter():
		return out # озёра подо льдом
	var k0 := floori(float(home.x - PLANT_AREA) / world.gen.lake_segment())
	var k1 := floori(float(home.x + PLANT_AREA) / world.gen.lake_segment())
	for k in range(k0 - 1, k1 + 2):
		var l := world.gen._lake_of_segment(k)
		if l.is_empty():
			continue
		var span := world.gen.lake_water_span(l)
		if span.x > span.y:
			continue
		var row: int = int(l["level"]) - 1
		for x in [span.x - 1, span.y + 1]:
			var c := Vector2i(x, mini(row, world.gen.surface_y(x) - 1))
			if absi(x - home.x) <= PLANT_AREA:
				out.append(c)
	return out


func _fish_at(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	if not p.is_water_structure() or p.phase != Project.Phase.DONE or p.paused or not can_fish_from(p):
		return false
	if workers_on(p) >= p.fish_slots() or fish_left(p) < 1.0:
		return false
	var best = null
	var best_d := 1 << 30
	for c in p.cells():
		if world.get_mat(c.x, c.y + 1) == Mat.WATER and dist.has(c) and dist[c] < best_d:
			best_d = dist[c]
			best = c
	if best != null:
		_start(u, Unit.Task.FISH, best + Vector2i(0, 1), best, p.id, parents)
		return true
	return false


func _try_fish(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	# Быстрее всего — с пристани, потом с мостика, медленнее всего — с берега.
	var structures := projects.filter(func(q: Project) -> bool: return q.is_water_structure())
	structures.sort_custom(func(a: Project, b: Project) -> bool: return a.fish_time() < b.fish_time())
	for p: Project in structures:
		if not _closed_for(u, p) and _fish_at(u, p, parents, dist):
			return true
	for spot in shore_spots():
		if reserved.has("f%d,%d" % [spot.x, spot.y]) or not dist.has(spot):
			continue
		var lake := _lake_near(spot.x)
		if fish_in(lake) < 1.0:
			continue
		_start(u, Unit.Task.FISH, spot, spot, 0, parents)
		return true
	return false


func _lake_near(x: int) -> Dictionary:
	for dx in [0, 1, -1, 2, -2]:
		var l := world.gen.lake_at(x + dx)
		if not l.is_empty():
			return l
	return {}


## Откуда гаврик может работать с клеткой c: стоя рядом (ноги или голова у клетки) или
## дотянувшись на клетку выше головы (под ней пусто — например, свод шахты над полом).
func _work_spot(c: Vector2i, dist: Dictionary) -> Array:
	var best := [null, 1 << 30]
	for d in DIRS4:
		var n := c + d
		for stand in [n, n + Vector2i(0, 1)]:
			if dist.has(stand) and dist[stand] < best[1]:
				best = [stand, dist[stand]]
		var reach := n + Vector2i(0, 2)
		if dist.has(reach) and dist[reach] < best[1] and pathing.passable(n) and pathing.passable(n + Vector2i(0, 1)):
			best = [reach, dist[reach]]
	return best


## Буры, под которыми (в их столбе, ниже них) есть клетки стройки p: бур-лифт (его дело —
## бурить вниз) и бур, который сейчас бурит. Под стоящим обычным буром копают сами.
func _drills_above(p: Project) -> Array[Project]:
	var out: Array[Project] = []
	for d in projects:
		if d.kind != Project.Kind.DRILL or not (d.link_id != 0 or drilling(d)):
			continue
		if d.rect.position.x < p.rect.end.x and d.rect.end.x > p.rect.position.x and p.rect.end.y > d.rect.end.y:
			out.append(d)
	return out


static func _under_drill(c: Vector2i, drills: Array[Project]) -> bool:
	for d in drills:
		if c.x >= d.rect.position.x and c.x < d.rect.end.x and c.y >= d.rect.end.y:
			return true
	return false


const UNDER_DRILL := "Под бур-лифтом: гаврики здесь не копают — этот столб пройдёт бур, когда вы прикажете ему бурить вниз (в карточке бур-лифта «↓ Вниз»). Лифт тут не нужен: шахта лифта бур-лифта дорастает за буром сама — такой лифт можно отменить, материалы вернутся"


## Стройка, которой осталось копать только под бур-лифтом, — пишем почему стоит.
func _check_under_drills() -> void:
	for p in projects:
		if p.phase != Project.Phase.DIG or p.paused or p.bored_by > 0:
			continue
		var had := p.blocked == UNDER_DRILL
		if not had and not p.blocked.is_empty():
			continue
		var drills := _drills_above(p)
		var left := remaining_dig(p)
		var all_under := not drills.is_empty() and not left.is_empty()
		if all_under:
			for c in left:
				if not _under_drill(c, drills):
					all_under = false
					break
		if all_under and not had:
			p.blocked = UNDER_DRILL
		elif not all_under and had:
			p.blocked = ""


## Бур прокопал клетки чужой стройки (лифт по ходу бура): срезы, выкопанные целиком, уже
## укреплены обсадкой бура — крепь там не нужна.
func _machine_dug(cells: Array) -> void:
	for q in projects:
		if q.phase != Project.Phase.DIG or q.bored_by > 0:
			continue
		for c in cells:
			if not q.has_cell(c):
				continue
			var i := q.slice_of(c)
			if slice_dug(q, i) and not q.supported.has(i):
				q.supported.append(i)
				_check_phase(q)


func _try_dig(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	var best_cell = null
	var best_stand = null
	var best_d := 1 << 30
	var any_free := false
	var now := diggable_now(p)
	# Под буром не копают: этот столб прокопает сам бур, когда пойдёт вниз.
	var drills := _drills_above(p)
	if not drills.is_empty():
		now = now.filter(func(c: Vector2i) -> bool: return not _under_drill(c, drills))
	for c in now:
		if reserved.has(c):
			continue
		any_free = true
		var spot := _work_spot(c, dist)
		if spot[0] != null and spot[1] < best_d:
			best_d = spot[1]
			best_cell = c
			best_stand = spot[0]
	# К начатому срезу не подойти (например, над головой порода, а сверху не прокопано) —
	# копаем доступную клетку соседнего среза, иначе стройка встанет навсегда.
	if best_cell == null and _dig_deadlock(now):
		for c in remaining_dig(p):
			if reserved.has(c) or now.has(c) or _under_drill(c, drills):
				continue
			any_free = true
			var spot := _work_spot(c, dist)
			if spot[0] != null and spot[1] < best_d:
				best_d = spot[1]
				best_cell = c
				best_stand = spot[0]
	# Свободных клеток нет, а строитель (шахтёр) к своей клетке ещё далеко идёт — помощник,
	# который ближе, копает её, пока тот не дойдёт (дойдёт — сменит).
	if best_cell == null and not builder_or_miner(u):
		for c in now:
			var o := _unit_by_id(int(reserved.get(c, 0)))
			if o == null or o.task != Unit.Task.DIG or o.state != Unit.State.MOVE or o.takeover != 0 \
					or not builder_or_miner(o):
				continue
			var spot := _work_spot(c, dist)
			if spot[0] != null and spot[1] + CREW_LEAD < o.path.size() - o.path_i and spot[1] < best_d:
				best_d = spot[1]
				best_cell = c
				best_stand = spot[0]
		if best_cell != null:
			var crew := _unit_by_id(int(reserved[best_cell]))
			_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
			crew.takeover = u.id
			u.takeover_by = crew.id
			return true
	# Свободных клеток нет: строитель (шахтёр) идёт к клетке, которую копает помощник, —
	# дойдёт и сменит его.
	var helper := 0
	if best_cell == null and builder_or_miner(u):
		for c in now:
			var o := _unit_by_id(int(reserved.get(c, 0)))
			if o == null or o.takeover_by != 0 or builder_or_miner(o) or o.task != Unit.Task.DIG:
				continue
			var spot := _work_spot(c, dist)
			if spot[0] != null and spot[1] < best_d:
				best_d = spot[1]
				best_cell = c
				best_stand = spot[0]
				helper = o.id
	# Свободных клеток нет, а забронировавший клетку ещё далеко идёт (например, спускается
	# с поверхности) — тот, кто стоит рядом, копает её сам, а дальний ищет другое дело
	# (раньше трое ждали у последней клетки, пока четвёртый минуту ехал к ней сверху).
	if best_cell == null:
		var far_one: Unit = null
		for c in now:
			var o := _unit_by_id(int(reserved.get(c, 0)))
			if o == null or o == u or o.task != Unit.Task.DIG or o.state != Unit.State.MOVE \
					or o.takeover != 0 or o.takeover_by != 0 or (builder_or_miner(o) and not builder_or_miner(u)):
				continue
			var spot := _work_spot(c, dist)
			if spot[0] != null and spot[1] + CREW_LEAD < o.path.size() - o.path_i and spot[1] < best_d:
				best_d = spot[1]
				best_cell = c
				best_stand = spot[0]
				far_one = o
		if far_one != null:
			_drop(far_one)
			_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
			return true
	if best_cell == null:
		# «Нет доступа» — только если к стройке вообще никто не подобрался.
		if any_free and workers_on(p) == 0 and p.blocked.is_empty():
			p.blocked = "Нет доступа — проложите тоннель к стройке"
		return false
	if p.blocked.begins_with("Нет доступа"):
		p.blocked = ""
	if helper == 0 and _hazard_stop(p, best_cell):
		return false
	_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
	_mark_takeover(u, helper)
	return true


## Тупик: начатый срез не докопать — к его клеткам не подойти никому (и их никто не копает).
func _dig_deadlock(now: Array[Vector2i]) -> bool:
	if now.is_empty():
		return false
	for c in now:
		if reserved.has(c):
			return false
	_refresh_reach()
	for c in now:
		if _work_spot(c, _reach_map)[0] != null:
			return false
	return true


## Геолог чует скрытую опасность рядом с забоем: бригада останавливается и ждёт решения.
## Накрывает ли клетку c работающая дегазация (квадрат её радиуса).
func degas_covers(c: Vector2i) -> bool:
	for p in rooms_of(RoomType.DEGAS):
		if p.paused:
			continue
		var center := p.rect.get_center()
		var dr := RoomType.effect_radius(p)
		if absi(c.x - center.x) <= dr and absi(c.y - center.y) <= dr:
			return true
	return false


## Вода опасна, только когда до неё клетка-две: о дальней геолог не тревожит (она видна на
## карте). Магму и газ он чует тем дальше, чем выше уровень геологии.
const WATER_WARN_RADIUS := 2


func _hazard_stop(p: Project, c: Vector2i) -> bool:
	var r := 2 + 2 * geology_level()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			# Уже вскрытое — не тревога; видимое, но ещё в толще породы — тревога.
			if world.is_dug(n.x, n.y):
				continue
			var kind := ""
			match world.get_mat(n.x, n.y):
				Mat.WATER:
					if maxi(absi(dx), absi(dy)) <= WATER_WARN_RADIUS:
						kind = "water"
				Mat.MAGMA:
					kind = "magma"
				Mat.GAS_POCKET:
					# Дегазация рядом — газ из вскрытого кармана она уберёт; в противогазах газ не
					# страшен — геолог не останавливает. Машине (бур, бур-лифт) газ безразличен:
					# искру даёт кирка.
					if not degas_covers(c) and not research.has("gas_masks") and not is_machine(p):
						kind = "gas"
			if kind.is_empty() or p.hazard_ack.has(kind):
				continue
			p.paused = true
			p.hazard_pending = kind
			p.blocked = HAZARD_TEXT[kind]
			_log("%s: %s" % [p.title(), p.blocked], "danger" if kind == "magma" else "warning")
			for u in units:
				if u.project_id == p.id:
					_drop(u)
			return true
	return false


## Крепь выкопанного среза: гаврик встаёт в срезе или рядом.
func _try_support(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	# Крепь среза ставит один гаврик; помощника сменяет подошедший строитель (шахтёр).
	var helper := 0
	if reserved.has("s%d" % p.id):
		var o := _unit_by_id(int(reserved["s%d" % p.id]))
		if not builder_or_miner(u) or o == null or o.takeover_by != 0 or builder_or_miner(o) or o.task != Unit.Task.SUPPORT:
			return false
		helper = o.id
	var i := slice_to_support(p)
	if i < 0 or not _pay_support(p, i):
		return false
	var best = null
	var best_d := 1 << 30
	for c in p.slice_cells(i):
		for stand in [c, c + Vector2i(-1, 0), c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]:
			if dist.has(stand) and dist[stand] < best_d:
				best_d = dist[stand]
				best = stand
	if best == null:
		return false
	_start(u, Unit.Task.SUPPORT, p.slice_cells(i)[0], best, p.id, parents)
	_mark_takeover(u, helper)
	return true


## Насколько ближе (шагов) должен быть помощник, чтобы начать вместо идущего строителя.
const CREW_LEAD := 6


## Строитель идёт сменить помощника helper (0 — никого): тот работает, пока смена не дойдёт.
func _mark_takeover(u: Unit, helper: int) -> void:
	u.takeover = helper
	var o := _unit_by_id(helper)
	if o != null:
		o.takeover_by = u.id
		# Место за помощником, пока смена в пути: его бросить нельзя (снимут с работы).
		var key = _reserve_key(o)
		if key != null:
			reserved[key] = o.id


## Смена дошла: помощник уступает работу и идёт искать другое дело.
func _arrive_takeover(u: Unit) -> void:
	var o := _unit_by_id(u.takeover)
	u.takeover = 0
	if o == null:
		return
	o.takeover_by = 0
	if o.task == u.task and o.project_id == u.project_id and (o.target == u.target or u.task == Unit.Task.SUPPORT):
		_drop(o)
	var key = _reserve_key(u)
	if key != null:
		reserved[key] = u.id


func _unit_by_id(uid: int) -> Unit:
	if uid == 0:
		return null
	for o in units:
		if o.id == uid:
			return o
	return null


func _try_build(u: Unit, p: Project, task: int, parents: Dictionary, dist: Dictionary) -> bool:
	var best = _near_rect(p.rect, dist)
	if best == null:
		return false
	_start(u, task, p.rect.get_center(), best, p.id, parents)
	return true


## Ближайшая доступная клетка в зоне или вплотную к ней (или null).
## reach — для копки: на клетку ниже обычного, дотягиваются до клетки над головой (см. _work_spot).
func _near_rect(r: Rect2i, dist: Dictionary, reach := false) -> Variant:
	var area := r.grow(1)
	if reach:
		area.size.y += 1
	var best = null
	var best_d := 1 << 30
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if dist.has(c) and dist[c] < best_d:
				best_d = dist[c]
				best = c
	return best



func _try_farm(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	return _try_room_work(u, RoomType.FARM, Unit.Task.FARM, parents, dist)


## Работа на месте в комнате: ферма, мастерская, лаборатория.
func _try_room_work(u: Unit, purpose: int, task: int, parents: Dictionary, dist: Dictionary) -> bool:
	for p in rooms_of(purpose):
		if _closed_for(u, p):
			continue
		if _mark_full(p):
			continue
		if task == Unit.Task.CRAFT and not has_inputs(p):
			continue
		if _room_work_at(u, p, task, parents, dist):
			return true
	return false


func _room_work_at(u: Unit, p: Project, task: int, parents: Dictionary, dist: Dictionary) -> bool:
	if p.paused or workers_on(p) >= RoomType.farm_slots(p):
		return false
	var best = null
	var best_d := 1 << 30
	for x in range(RoomType.floor_start(p), p.rect.end.x):
		var c := Vector2i(x, p.rect.end.y - 1)
		if dist.has(c) and dist[c] < best_d:
			best_d = dist[c]
			best = c
	if best != null:
		_start(u, task, best, best, p.id, parents)
		return true
	return false


## only — ограничить список столбцов (расчистка места под стройку pid).
func _try_harvest(u: Unit, parents: Dictionary, dist: Dictionary, only: Array = [], pid := 0) -> bool:
	if pid != 0 and only.is_empty():
		return false
	var best_x = null
	var best_stand = null
	var best_d := 1 << 30
	var want_food := food_low()
	for x in (only if not only.is_empty() else world.feature_marks.keys()):
		if reserved.has("h%d" % x) or not harvestable(x):
			continue
		var base := Vector2i(x, world.gen.surface_y(x) - 1)
		# При нехватке еды кусты с ягодами — в первую очередь.
		var bonus := -1000 if want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH else 0
		for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
			if dist.has(stand) and dist[stand] + bonus < best_d:
				best_d = dist[stand] + bonus
				best_x = x
				best_stand = stand
	if best_x == null:
		return false
	_start(u, Unit.Task.HARVEST, Vector2i(best_x, world.gen.surface_y(best_x) - 1), best_stand, pid, parents)
	return true


# --- Переноска материалов ---------------------------------------------------------------

func _ground_cell(x: int) -> Vector2i:
	return Vector2i(x, world.gen.surface_y(x) - 1)


## Где лежит ресурс: склады, кучи у базы, отвал пустой породы.
func _source_spots(key: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if RoomType.BULK.has(key):
		return _base_spots(3, 6)
	for room in holders(key):
		if held_in(room, key) > 0 and RoomType.is_store(room.purpose):
			for x in range(RoomType.floor_start(room), room.rect.end.x):
				out.append(Vector2i(x, room.rect.end.y - 1))
	if base_have(key) > 0 or out.is_empty():
		out.append_array(_base_spots(-8, -1))
	return out


## Где брать запас у базы (столбцы home.x + from … home.x + to - 1). У базы выкопали яму
## или застроили — земля уже не там, где была: берут с любой клетки этих столбцов, где можно
## стоять (пол комнаты, дно ямы, крыша), иначе запас у базы был бы недоступен.
const BASE_SPAN := 16


func _base_spots(from: int, to: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(from, to):
		var g := _ground_cell(home.x + dx)
		if pathing.node(g):
			out.append(g)
			continue
		for dy in range(1, BASE_SPAN):
			for c in [g + Vector2i(0, dy), g - Vector2i(0, dy)]:
				if pathing.node(c):
					out.append(c)
	if out.is_empty():
		for dx in range(from, to):
			out.append(_ground_cell(home.x + dx))
	return out


func _source_spot(key: String, dist: Dictionary) -> Variant:
	var best = null
	var best_d := 1 << 30
	for c in _source_spots(key):
		if dist.has(c) and dist[c] < best_d:
			best_d = dist[c]
			best = c
	return best


## Сколько ресурса уже обещано носильщикам, которые ещё не дошли до склада.
func _claimed(key: String) -> int:
	var n := 0
	for u in units:
		if u.task == Unit.Task.HAUL and u.haul_stage == 0 and u.carry_key == key and not u.from_drop:
			n += u.carry_amount
	return n


## Сколько из кучи на клетке c уже обещано носильщикам.
func _claimed_drop(c: Vector2i, key: String) -> int:
	var n := 0
	for u in units:
		if u.task == Unit.Task.HAUL and u.haul_stage == 0 and u.from_drop and u.haul_src == c and u.carry_key == key:
			n += u.carry_amount
	return n


# --- Добыча на земле ----------------------------------------------------------------------

## Добытое ложится там, где добыто (падает на пол). Пустая порода — сразу в отвал,
## оффлайн гаврики успевают всё перетаскать — сразу на склад.
## site — стройка, на которой добыто (расчистка, копка): что ей нужно, остаётся
## на месте и сразу идёт в её материалы; на склад уносят только излишек.
func drop_item(c: Vector2i, key: String, n: int, site: Project = null) -> void:
	if key.is_empty() or n <= 0:
		return
	produced[key] = int(produced.get(key, 0)) + n
	# Нефть из вскрытого пласта — сразу по трубам в хранилище (нет его — разлилась).
	if RoomType.PIPED.has(key):
		_add(key, n)
		return
	known_resources[key] = true
	if site != null:
		var use := mini(n, int(remaining(site).get(key, 0)))
		if use > 0:
			site.delivered[key] = site.delivered.get(key, 0) + use
			n -= use
			if n <= 0:
				return
	# Без игрока гаврики успевают донести — но только туда, где есть работник склада.
	if RoomType.BULK.has(key) or (offline and can_store(key)):
		_add(key, n)
		return
	var spot := _landing(c)
	if not drops.has(spot):
		drop_born[spot] = game_time
	var d: Dictionary = drops.get(spot, {})
	d[key] = int(d.get(key, 0)) + n
	drops[spot] = d


## Куда упадёт предмет из клетки c: до пола, настила или перекрытия.
func _landing(c: Vector2i) -> Vector2i:
	var k := c
	for i in 64:
		var below := k + Vector2i(0, 1)
		if deck.has(k) or not world.is_open(below.x, below.y):
			break
		if room_cells.has(below) and room_cells[below] != room_cells.get(k, -1):
			break
		k = below
	return k


## Когда на клетке появилась кучка (у загруженных из сохранения — «давно»).
var drop_born := {}
## Свежую маленькую кучку не несут сразу: ждут, пока рядом наберётся полная ноша,
## но не дольше DROP_WAIT секунд — иначе ходят на склад с одной штукой.
const DROP_WAIT := 45.0


func _worth_carrying(c: Vector2i, key: String, avail: int) -> bool:
	if avail >= carry_cap() or game_time - float(drop_born.get(c, -INF)) >= DROP_WAIT:
		return true
	var near := 0
	for dy in range(-PICK_RADIUS, PICK_RADIUS + 1):
		for dx in range(-PICK_RADIUS, PICK_RADIUS + 1):
			near += drop_amount(c + Vector2i(dx, dy), key)
	return near >= carry_cap()


func drop_amount(c: Vector2i, key: String) -> int:
	return int(drops.get(c, {}).get(key, 0))


## Материалы, что лежат на самой стройке или вплотную к ней (привёз лифт, выкопали тут
## же), сразу засчитываются ей — заносить их не нужно (раньше камень лежал у насосной,
## пока кто-нибудь не придёт его поднять).
func _absorb_site_drops() -> void:
	if drops.is_empty():
		return
	# Площадки грузовых лифтов: выгруженное там для стройки у этого конца — тоже её.
	var stations := []
	for l in lifts():
		if l.cargo and lift_powered(l):
			for e in 2:
				var st = lift_station(l, e)
				if st != null and drops.has(st):
					stations.append([st, l, e])
	for p in projects:
		if p.phase == Project.Phase.DONE and not p.repairing:
			continue
		var req := required(p)
		if req.is_empty():
			continue
		var area := p.rect.grow(1)
		var mine := {}
		for s3 in stations:
			if s3[1] != p and _lift_serves(s3[1], 1 - int(s3[2]), p):
				mine[s3[0]] = true
		var got := false
		for c: Vector2i in drops.keys():
			if not (area.has_point(c) or mine.has(c)) or in_drill_lift(c) or not drops.has(c):
				continue
			for k in drops[c].keys():
				var need: int = int(req.get(k, 0)) - int(p.delivered.get(k, 0))
				if need <= 0:
					continue
				var n := _take_drop(c, k, need)
				if n > 0:
					p.delivered[k] = int(p.delivered.get(k, 0)) + n
					got = true
				if not drops.has(c):
					break
		if got:
			_try_pay(p)


func _take_drop(c: Vector2i, key: String, n: int) -> int:
	var have := drop_amount(c, key)
	var take := mini(have, n)
	if take <= 0:
		return 0
	var d: Dictionary = drops[c]
	d[key] = have - take
	if d[key] <= 0:
		d.erase(key)
	if d.is_empty():
		drops.erase(c)
		drop_born.erase(c)
	return take


## Сколько ресурса лежит на земле по всему миру.
func drop_total(key: String) -> int:
	var n := 0
	for c in drops:
		n += int(drops[c].get(key, 0))
	return n


## Где встать, чтобы взять с кучи c.
func _drop_stand(c: Vector2i, dist: Dictionary) -> Variant:
	if dist.has(c):
		return c
	# Куча в щели, на уступе или над головой — дотягиваются с соседней клетки.
	for d in DROP_REACH:
		if dist.has(c + d):
			return c + d
	return null


const DROP_REACH := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-2, 0), Vector2i(2, 0)]


## Кучи, засыпанные породой (обвал, песок), переносятся на ближайшее открытое место
## над ними, а висящие в воздухе — падают на пол. Иначе их никто не достанет.
func _settle_drops() -> void:
	for c: Vector2i in drops.keys():
		var to := c
		if not world.is_open(c.x, c.y) and world.get_mat(c.x, c.y) != Mat.WATER:
			var found = null
			for dy in range(0, 12):
				for dx in [0, -1, 1, -2, 2]:
					var k := c + Vector2i(dx, -dy)
					if world.is_open(k.x, k.y):
						found = k
						break
				if found != null:
					break
			if found == null:
				continue
			to = found
		to = _landing(to)
		if to == c:
			continue
		var d: Dictionary = drops[c]
		drops.erase(c)
		var dest: Dictionary = drops.get(to, {})
		for k in d:
			dest[k] = int(dest.get(k, 0)) + int(d[k])
		drops[to] = dest


## Ближайший источник ресурса: [где встать, клетка кучи или null, сколько можно взять].
func _haul_source(key: String, dist: Dictionary, u: Unit = null, parents := {}) -> Array:
	var best := [null, null, 0]
	var best_d := 1 << 30
	var store: int = inventory.get(key, 0) - _claimed(key)
	if store > 0:
		var s = _source_spot(key, dist)
		if s == null and u != null and Pathing.truncated(dist):
			# Большая колония: склад дальше, чем достаёт обход гаврика, — путь к нему ищут прицельно.
			var goals := {}
			for c in _source_spots(key):
				if pathing.node(c):
					goals[c] = true
			if _extend_far(u.cell(), goals, "src " + key, parents, dist):
				s = _source_spot(key, dist)
		if s != null:
			best = [s, null, store]
			best_d = dist[s]
	for c: Vector2i in drops:
		var avail := drop_amount(c, key) - _claimed_drop(c, key)
		if avail <= 0 or not near_home(c.x) or in_drill_lift(c):
			continue
		var stand = _drop_stand(c, dist)
		if stand != null and dist[stand] < best_d:
			best_d = dist[stand]
			best = [stand, c, avail]
	return best


## Куда отнести ресурс на хранение: ближайший склад для него, иначе кучи у базы.
func _store_spot(key: String, dist: Dictionary) -> Variant:
	var t = _store_target(key, dist)
	return t[0] if t != null else null


## Ближайший склад с работником, куда влезет ресурс: [где встать, склад] или null.
## only — только этот склад.
func _store_target(key: String, dist: Dictionary, only: Project = null) -> Variant:
	var best = null
	var best_d := 1 << 30
	for room in ([only] if only != null else store_rooms()):
		if not RoomType.stores(room, key) or not store_staffed(room) or room_free(room, key) <= 0:
			continue
		var c = _room_stand(room, dist)
		if c != null and dist[c] < best_d:
			best_d = dist[c]
			best = [c, room]
	return best


## Ближайшая к гаврику клетка пола комнаты.
func _room_stand(room: Project, dist: Dictionary) -> Variant:
	var best = null
	for x in range(RoomType.floor_start(room), room.rect.end.x):
		var c := Vector2i(x, room.rect.end.y - 1)
		if dist.has(c) and (best == null or dist[c] < dist[best]):
			best = c
	return best


## Склад (амбар) принимает добро, пока он не на паузе — работник не нужен (работник склада
## сам добывает недостающее и в первую очередь разносит добытое).
func store_staffed(room: Project) -> bool:
	return room.purpose == RoomType.SHIP or not room.paused


## Есть ли куда нести ресурс: склад или амбар для него с назначенным работником.
func can_store(key: String) -> bool:
	for room in store_rooms():
		if RoomType.stores(room, key) and store_staffed(room):
			return true
	return false


## Стройке q ещё нужен ресурс key.
func _needs_key(q: Project, key: String) -> bool:
	if q.phase == Project.Phase.DONE and not q.repairing:
		return false
	return int(required(q).get(key, 0)) > int(q.delivered.get(key, 0))


## Куча ждёт стройку: лежит на стройке, которой этот ресурс нужен, или у площадки
## грузового лифта, который везёт его такой стройке.
func _awaited_drop(c: Vector2i, key: String) -> bool:
	var site := project_at(c)
	if site != null and _needs_key(site, key):
		return true
	for p in lifts():
		if not p.cargo:
			continue
		for e in 2:
			if lift_station(p, e) != c:
				continue
			for q in projects:
				if q != p and _needs_key(q, key) and _lift_serves(p, 1 - e, q):
					return true
	return false


## Свободный гаврик уносит лежащее на земле на склад (если там есть место).
func _try_cleanup(u: Unit, parents: Dictionary, dist: Dictionary, only: Project = null, mines_only := false) -> bool:
	var may_mine := may_haul_mine(u)
	var best = null
	var best_c := Vector2i.ZERO
	var best_k := ""
	var best_n := 0
	var best_d := 1 << 30
	var best_room: Project = null
	var best_lift_end := -1
	for c: Vector2i in drops:
		var stand = _drop_stand(c, dist)
		if stand == null or dist[stand] >= best_d or in_drill_lift(c):
			continue
		# Добытое в шахте уносят только работники складов и подсобные.
		var mined := in_mine(c)
		if (mines_only and not mined) or (mined and not may_mine):
			continue
		for k in drops[c]:
			# Работник склада носит стройматериалы, амбара — еду; на любой склад, где есть
			# работник и место.
			if only != null and not RoomType.same_kind(only, k):
				continue
			# Привезённое на стройку (лифтом к ней или прямо на неё) на склад не уносят.
			if _awaited_drop(c, k):
				continue
			var avail := drop_amount(c, k) - _claimed_drop(c, k)
			if avail <= 0 or not _worth_carrying(c, k, avail):
				continue
			var to = _store_target(k, dist, only)
			# До грузового лифта ближе, чем до склада, — несут в лифт (он довезёт до склада).
			var lift = _cargo_route(k, dist, dist[to[0]] if to != null else (1 << 30), only)
			if to == null and lift == null:
				continue
			# На почти полный склад по одной штуке не носят: ждут, пока освободится место
			# под всю ношу.
			if lift == null and room_free(to[1], k) < mini(carry_cap(), avail):
				continue
			best = stand
			best_c = c
			best_k = k
			best_lift_end = -1
			if lift != null:
				best_room = lift[1]
				best_lift_end = lift[2]
				best_n = mini(carry_cap(), avail)
			else:
				best_room = to[1]
				best_n = mini(carry_cap(), mini(avail, room_free(to[1], k)))
			best_d = dist[stand]
			break
	if best == null:
		return false
	# Что останется на куче — снова «свежее»: следующий не побежит за одной штукой.
	drop_born[best_c] = game_time
	u.carry_key = best_k
	u.carry_amount = best_n
	u.haul_stage = 0
	u.from_drop = true
	u.haul_src = best_c
	u.to_store = true
	u.cargo_end = best_lift_end
	_start(u, Unit.Task.HAUL, best, best, best_room.id, parents)
	return true


## Гаврик берёт ресурс с кучи c (рядом с ним) и несёт на склад.
func _pick_up(u: Unit, c: Vector2i, key: String) -> void:
	if not can_store(key):
		return
	var to = _store_target(key, pathing.explore(u.cell())[1])
	if to == null:
		return
	var n := mini(carry_cap(), mini(drop_amount(c, key), room_free(to[1], key)))
	if n <= 0:
		return
	_drop(u)
	u.task = Unit.Task.HAUL
	u.project_id = to[1].id
	u.carry_key = key
	u.carry_amount = n
	u.haul_stage = 0
	u.from_drop = true
	u.haul_src = c
	u.to_store = true
	u.path.clear()
	u.path_i = 0
	u.state = Unit.State.WORK


## Сколько ресурса уже несут на склад.
func _incoming(key: String) -> int:
	var n := 0
	for u in units:
		if u.task == Unit.Task.HAUL and u.carry_key == key and (u.to_store or u.gather_room != 0):
			n += u.carry_amount
	return n


func _try_haul(u: Unit, p: Project, parents: Dictionary, dist: Dictionary, now_only := false) -> bool:
	# Стройке под бур-лифтом материалы не носят, пока бур её не прошёл.
	if p.blocked == UNDER_DRILL:
		return false
	var left := remaining(p)
	if now_only:
		# Только то, что нужно прямо сейчас и ещё не принесено и не несут.
		var now := _needed_now(p)
		var rest := remaining(p)
		left = {}
		for k in now:
			var n: int = now[k] - int(p.delivered.get(k, 0)) - in_transit(p, k)
			if n > 0:
				# Раз уж пошёл — берёт на несколько срезов вперёд (полную ношу), а не одно бревно.
				left[k] = maxi(n, mini(carry_cap(), int(rest.get(k, 0))))
	if left.is_empty() or _near_rect(p.rect, dist) == null:
		return false
	# Сначала то, без чего стройка стоит прямо сейчас.
	var keys := left.keys()
	var now := _needed_now(p)
	keys.sort_custom(func(a: String, b: String) -> bool: return now.has(a) and not now.has(b))
	for k in keys:
		var src := _haul_source(k, dist, u, parents)
		if src[0] == null:
			continue
		# Со склада это привезёт лифт — несут только с площадки у стройки.
		if src[1] == null and lift_feeds(p, k):
			continue
		u.carry_key = k
		u.carry_amount = mini(carry_cap(), mini(left[k], src[2]))
		u.haul_stage = 0
		u.from_drop = src[1] != null
		u.haul_src = src[1] if src[1] != null else Vector2i.ZERO
		_start(u, Unit.Task.HAUL, src[0], src[0], p.id, parents)
		return true
	return false


# --- Подсобные рабочие: переноска -------------------------------------------------------

## Сколько циклов сырья держат в мастерской про запас.
const SUPPLY_CYCLES := 2
## Как часто свободный носильщик проверяет, не нужен ли он на стройке.
const RECHECK_TIME := 3.0


## Несут ли в эту постройку сырьё (готовая мастерская), а не материалы на стройку.
func _is_supply(p: Project) -> bool:
	return p.phase == Project.Phase.DONE and not p.repairing and RoomType.RECIPES.has(p.purpose)


## Переноска: материалы на стройки, сырьё в мастерские, продукция и добыча — на склад и в амбар.
func _try_logistics(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	# Сначала — крепь туда, где копка стоит без дерева: иначе копатель пойдёт за ним сам.
	for p in projects:
		if p.paused or p.phase != Project.Phase.DIG or _needed_now(p).is_empty():
			continue
		if p.kind == Project.Kind.MINE and not may_haul_mine(u):
			continue
		if _try_haul(u, p, parents, dist):
			return true
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
			continue
		if p.kind == Project.Kind.MINE and not may_haul_mine(u):
			continue
		if _try_haul(u, p, parents, dist):
			return true
	for p in projects:
		if _is_supply(p) and not p.paused and _try_supply(u, p, parents, dist):
			return true
	# Без склада и амбара добытое не копят — носить некуда.
	for room in store_rooms():
		if not room.paused and _try_cleanup(u, parents, dist, room):
			return true
	return false


## Сколько ресурса key уже несут в постройку p.
func _incoming_to(p: Project, key: String) -> int:
	var n := 0
	for o in units:
		if o.task == Unit.Task.HAUL and o.project_id == p.id and o.carry_key == key:
			n += o.carry_amount
	return n


## Подсобный несёт сырьё в мастерскую (запас на пару циклов).
func _try_supply(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	if _near_rect(p.rect, dist) == null:
		return false
	var r := recipe(p)
	if r.is_empty():
		return false
	var need: Dictionary = r[0]
	for k in need:
		if RoomType.PIPED.has(k):
			continue
		var want: int = need[k] * SUPPLY_CYCLES - p.stock.get(k, 0) - _incoming_to(p, k)
		if want <= 0:
			continue
		var src := _haul_source(k, dist, u, parents)
		if src[0] == null:
			continue
		u.carry_key = k
		u.carry_amount = mini(carry_cap(), mini(want, src[2]))
		u.haul_stage = 0
		u.from_drop = src[1] != null
		u.haul_src = src[1] if src[1] != null else Vector2i.ZERO
		u.to_store = false
		_start(u, Unit.Task.HAUL, src[0], src[0], p.id, parents)
		return true
	# Топливо про запас: уголь, если есть, иначе дрова.
	if RoomType.FUELED.has(p.purpose):
		var want := SUPPLY_CYCLES - fuel_have(p) - _incoming_to(p, "coal") * 2.0 - _incoming_to(p, "wood")
		if want > 0.0:
			for k in ["coal", "wood"]:
				var src := _haul_source(k, dist, u, parents)
				if src[0] == null:
					continue
				var units := ceili(want / float(RoomType.FUEL_VALUE[k]))
				u.carry_key = k
				u.carry_amount = mini(carry_cap(), mini(units, src[2]))
				u.haul_stage = 0
				u.from_drop = src[1] != null
				u.haul_src = src[1] if src[1] != null else Vector2i.ZERO
				u.to_store = false
				_start(u, Unit.Task.HAUL, src[0], src[0], p.id, parents)
				return true
	return false


## Есть ли стройка со свободным местом.
func _construction_open() -> bool:
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
			continue
		if workers_on(p) < p.workers:
			return true
	return false


## Свободный носит на склад или в мастерскую, а на стройке освободилось место — идёт туда:
## стройка важнее. Груз оставляет там, где стоял.
func _construction_recheck(u: Unit, dt: float) -> void:
	u.recheck_t -= dt
	if u.recheck_t > 0.0:
		return
	u.recheck_t = RECHECK_TIME
	if not is_free(u) or u.task != Unit.Task.HAUL or u.state != Unit.State.MOVE:
		return
	var cur := project_by_id(u.project_id)
	if cur != null and not _is_supply(cur):
		return # и так несёт на стройку
	if not _construction_open():
		return
	var saved := [u.task, u.target, u.project_id, u.path, u.path_i, u.state, u.carry_key, u.carry_amount,
		u.haul_stage, u.from_drop, u.haul_src, u.to_store, u.gather_room, u.work_t]
	var cell := u.cell()
	u.carry_amount = 0
	u.haul_stage = 0
	u.from_drop = false
	u.to_store = false
	u.gather_room = 0
	var reach := pathing.explore(cell)
	var old_task := u.task
	u.task = Unit.Task.NONE
	if _try_projects(u, reach[0], reach[1]):
		if saved[8] == 1 and saved[7] > 0:
			drop_item(cell, saved[6], saved[7])
		return
	u.task = old_task
	u.target = saved[1]
	u.project_id = saved[2]
	u.path = saved[3]
	u.path_i = saved[4]
	u.state = saved[5]
	u.carry_key = saved[6]
	u.carry_amount = saved[7]
	u.haul_stage = saved[8]
	u.from_drop = saved[9]
	u.haul_src = saved[10]
	u.to_store = saved[11]
	u.gather_room = saved[12]
	u.work_t = saved[13]


## Несёт с кучи на склад — заодно подбирает то же самое из соседних кучек (в 2 клетках),
## пока руки не полны: после копки добытое лежит кучками по 1–2, и носить по одной долго.
const PICK_RADIUS := 2


func _pick_nearby(u: Unit, have: int) -> int:
	if not u.to_store or u.cargo_end >= 0 or have <= 0:
		return 0
	var room := project_by_id(u.project_id)
	if room == null:
		return 0
	# Своя ходка уже учтена в «месте на складе» — добавляем её обратно.
	var want := mini(carry_cap(), room_free(room, u.carry_key) + u.carry_amount) - have
	var got := 0
	for dy in range(-PICK_RADIUS, PICK_RADIUS + 1):
		for dx in range(-PICK_RADIUS, PICK_RADIUS + 1):
			if want <= 0:
				return got
			var c := u.haul_src + Vector2i(dx, dy)
			if c == u.haul_src or not drops.has(c):
				continue
			var avail := drop_amount(c, u.carry_key) - _claimed_drop(c, u.carry_key)
			if avail <= 0:
				continue
			var n := _take_drop(c, u.carry_key, mini(avail, want))
			got += n
			want -= n
	return got


## Гаврик у склада или кучи: берёт ресурс и несёт к стройке или на склад.
func _haul_pickup(u: Unit) -> void:
	var p := project_by_id(u.project_id)
	if p == null and not u.to_store:
		_drop(u)
		return
	var take := 0
	if u.from_drop:
		take = _take_drop(u.haul_src, u.carry_key, u.carry_amount)
		take += _pick_nearby(u, take)
	else:
		# Берёт из того склада, у которого стоит; у базы — из запаса у базы.
		var from := store_at(u.cell())
		if from != null and held_in(from, u.carry_key) > 0:
			take = _remove(u.carry_key, u.carry_amount, from)
		else:
			take = _remove(u.carry_key, u.carry_amount)
	if take <= 0:
		_drop(u)
		return
	if RoomType.RADIOACTIVE.has(u.carry_key):
		irradiate(u)
	u.carry_amount = take
	u.haul_stage = 1
	var reach := pathing.explore(u.cell())
	var stand = null
	if u.to_store:
		# Несёт в тот склад, куда собирался; там уже нет места — в ближайший другой.
		if p != null and p.kind == Project.Kind.LIFT and u.cargo_end >= 0 and lift_powered(p):
			stand = lift_station(p, u.cargo_end)
			if stand != null and not reach[1].has(stand):
				stand = null
		elif p != null and RoomType.is_store(p.purpose) and store_staffed(p):
			stand = _room_stand(p, reach[1])
		if stand == null:
			var to = _store_target(u.carry_key, reach[1])
			if to != null:
				stand = to[0]
				u.project_id = to[1].id
	else:
		stand = _near_rect(p.rect, reach[1])
		if stand == null and _reach_far(u.cell(), p.rect, reach[0], reach[1]):
			stand = _near_rect(p.rect, reach[1], true)
	if stand == null:
		# Нести некуда — кладёт обратно.
		var back := u.carry_amount
		if u.from_drop:
			drop_item(u.cell(), u.carry_key, back)
		else:
			_add(u.carry_key, back)
		u.carry_amount = 0
		_drop(u)
		return
	u.path = _lift_route(u.cell(), stand, Pathing.path_to(reach[0], stand))
	u.path_i = 0
	u.state = Unit.State.MOVE


## Гаврик донёс груз: на стройку — в её запас, на склад — в общий.
func _haul_deliver(u: Unit) -> void:
	var p := project_by_id(u.project_id)
	var k := u.carry_key
	var n := u.carry_amount
	var to_storage := u.gather_room != 0 or u.to_store
	var spot := u.cell()
	var end := u.cargo_end
	u.carry_amount = 0
	_drop(u)
	if p != null and p.kind == Project.Kind.LIFT and to_storage and end >= 0:
		# Груз — в грузовой лифт: он довезёт до склада у другого конца.
		p.lift_buf[end][k] = int(p.lift_buf[end].get(k, 0)) + n
		return
	if to_storage or p == null:
		# В свой склад; не влезло — остаётся лежать здесь (подберут и отнесут в другой).
		var room: Project = p if p != null and RoomType.is_store(p.purpose) else store_at(spot)
		drop_item(spot, k, n - (_add(k, n, room) if room != null else _add(k, n)))
		return
	if _is_supply(p):
		p.stock[k] = p.stock.get(k, 0) + n
		return
	p.delivered[k] = p.delivered.get(k, 0) + n
	_try_pay(p)


## Гаврик с добычей идёт на склад room_id.
func _carry_to(u: Unit, room_id: int, key: String, amount: int) -> void:
	var room := project_by_id(room_id)
	var stand = null
	var reach := []
	if room != null:
		reach = pathing.explore(u.cell())
		stand = _near_rect(room.rect, reach[1])
	if stand == null:
		_add(key, amount)
		return
	u.task = Unit.Task.HAUL
	u.project_id = room_id
	u.gather_room = room_id
	u.carry_key = key
	u.carry_amount = amount
	u.haul_stage = 1
	u.path = _lift_route(u.cell(), stand, Pathing.path_to(reach[0], stand))
	u.path_i = 0
	u.work_t = 0.0
	u.state = Unit.State.MOVE


# --- Склад: гаврики сами добывают ресурсы до нормы -----------------------------------------

func gatherers_on(p: Project) -> int:
	var n := 0
	for u in units:
		if u.gather_room == p.id and u.task != Unit.Task.NONE:
			n += 1
	return n


## Ресурсы склада, которых меньше нормы (и есть куда положить).
## Чего не хватает до нормы — для работников склада (стройматериалы) или амбара (еда).
## У каждого склада свои нормы и своё содержимое: его работники добывают в него.
func storage_deficit(p: Project) -> Array[String]:
	var out: Array[String] = []
	for k in p.targets:
		if not GATHER_SOURCES.has(k) or not RoomType.stores(p, k):
			continue
		if held_in(p, k) < mini(int(p.targets[k]), room_limit(p, k)):
			out.append(k)
	# Чего не хватает сильнее (меньшая доля нормы) — в первую очередь: добыча чередуется,
	# а не идёт подряд одного ресурса.
	out.sort_custom(func(a: String, b: String) -> bool:
		return held_in(p, a) / float(maxi(1, p.targets[a])) < held_in(p, b) / float(maxi(1, p.targets[b])))
	return out


## Нормы по умолчанию для нового склада.
func default_targets(room: Project = null) -> Dictionary:
	var out := {}
	for k in DEFAULT_TARGETS:
		if room == null or RoomType.stores(room, k):
			out[k] = mini(DEFAULT_TARGETS[k], room_cap(room, k) if room != null else capacity(k))
	return out


func _try_storage(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	for room in store_rooms():
		if room.paused or room.gatherers <= 0 or gatherers_on(room) >= room.gatherers or _closed_for(u, room):
			continue
		for k in storage_deficit(room):
			if _try_gather(u, k, room, parents, dist):
				return true
	return false


## Подходит ли объект для добычи гавриками склада (метка игрока не нужна).
func _gather_ok(x: int, kind: int) -> bool:
	if world.feature_at(x) != kind or reserved.has("h%d" % x) or _in_clearing(x):
		return false
	match kind:
		WorldGen.FEATURE_TREE:
			# Молодые деревья не трогаем — пусть растут.
			return world.growth(x) >= 0.6
		WorldGen.FEATURE_BUSH:
			return world.berries(x) >= 1.0
	return true


func _try_gather(u: Unit, key: String, room: Project, parents: Dictionary, dist: Dictionary) -> bool:
	var kind: int = GATHER_SOURCES[key]
	if kind < 0:
		# Еда для склада — рыба.
		u.gather_room = room.id
		if _try_fish(u, parents, dist):
			return true
		u.gather_room = 0
		return false
	var ux := u.cell().x
	var best_x = null
	var best_stand = null
	var best_d := 1 << 30
	for x in range(maxi(explored_min, ux - Pathing.MAX_RADIUS), mini(explored_max, ux + Pathing.MAX_RADIUS) + 1):
		if not _gather_ok(x, kind) or not near_home(x):
			continue
		var base := _ground_cell(x)
		for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
			if dist.has(stand) and dist[stand] < best_d:
				best_d = dist[stand]
				best_x = x
				best_stand = stand
	if best_x == null:
		return _try_scout(u, parents, dist, key)
	u.gather_room = room.id
	_start(u, Unit.Task.HARVEST, _ground_cell(best_x), best_stand, 0, parents)
	return true


## Рядом не осталось чего добыть — гаврик идёт по поверхности к краю разведанного:
## дальше могут быть деревья, валуны и кусты. Не чаще раза в SCOUT_EVERY секунд.
func _try_scout(u: Unit, parents: Dictionary, dist: Dictionary, key: String) -> bool:
	if game_time - _scout_at < SCOUT_EVERY:
		return false
	var best = null
	var best_d := 1 << 30
	for c: Vector2i in dist:
		var s := world.gen.surface_y(c.x)
		if c.y >= s or c.y < s - 3 or (c.x < explored_max - 8 and c.x > explored_min + 8) or not near_home(c.x):
			continue
		if dist[c] < best_d:
			best_d = dist[c]
			best = c
	if best == null or best == u.cell():
		return false
	_scout_at = game_time
	_start(u, Unit.Task.GOTO, best, best, 0, parents)
	var what := {"wood": "деревьев", "stone": "валунов", "berries": "кустов", "clay": "глины"}
	_log("%s идёт на разведку: рядом не осталось %s" % [u.name, what.get(key, "сырья")], "info")
	return true


## Стройке не хватает дерева, камня или еды нет совсем — гаврики сами отмечают
## ближайшее дерево, валун или куст и добывают.
func _try_need(u: Unit, parents: Dictionary, dist: Dictionary) -> bool:
	var keys := {}
	for p in projects:
		if p.paused or not p.blocked.begins_with("Не хватает"):
			continue
		for k in _needed_now(p):
			if GATHER_SOURCES.has(k):
				keys[k] = true
	# Погасший очаг — тоже нужда: рубят дрова.
	if _hearth_starving():
		keys["wood"] = true
	for k in keys:
		var kind: int = GATHER_SOURCES[k]
		if kind < 0:
			continue
		# Уже помеченное на сбор — рубят его (раньше искали только непомеченное, и если всё
		# рядом уже помечено, а склада ещё нет — стройка вставала намертво).
		var marked: Array = world.feature_marks.keys().filter(func(x: int) -> bool:
			return world.feature_at(x) == kind and _gather_ok(x, kind) and near_home(x))
		if not marked.is_empty() and _try_harvest(u, parents, dist, marked):
			return true
		var ux := u.cell().x
		var best_x = null
		var best_d := 1 << 30
		for x in range(maxi(explored_min, ux - Pathing.MAX_RADIUS), mini(explored_max, ux + Pathing.MAX_RADIUS) + 1):
			if world.feature_marks.has(x) or not _gather_ok(x, kind) or not near_home(x):
				continue
			var base := _ground_cell(x)
			for stand in [base, base + Vector2i(-1, 0), base + Vector2i(1, 0)]:
				if dist.has(stand) and dist[stand] < best_d:
					best_d = dist[stand]
					best_x = x
		if best_x != null:
			world.set_feature_mark(best_x, true)
			return _try_harvest(u, parents, dist)
		if _try_scout(u, parents, dist, k):
			return true
	return false


## Есть ли что добыть для ресурса key (для подсказки «нечего добывать»).
func gather_source_exists(key: String) -> bool:
	if not GATHER_SOURCES.has(key):
		return false
	var kind: int = GATHER_SOURCES[key]
	if kind < 0:
		return not shore_spots().is_empty()
	for x in range(explored_min, explored_max + 1):
		if _gather_ok(x, kind):
			return true
	return false


# --- Износ и ремонт ------------------------------------------------------------------------

func wear_material(p: Project) -> String:
	return p.material if p.kind == Project.Kind.ROOM else "wood"


func is_underground(p: Project) -> bool:
	var c := p.rect.get_center()
	return c.y >= world.gen.surface_y(c.x)


## Сколько лет постройка служит от новой до разрушения.
func service_years(p: Project) -> float:
	var m := wear_material(p)
	var years: float = WEAR_YEARS.get(m, 20.0)
	if p.is_water_structure():
		years *= 0.75
	elif is_underground(p):
		years *= WEAR_UNDERGROUND.get(m, 1.0)
		# В жаре глубоких шахт дерево и металл портятся ещё быстрее.
		var c := p.rect.get_center()
		var t := world.gen.temperature(c.y, world.gen.surface_y(c.x))
		if m != "stone" and t > 40.0 and not research.has("heatproof"):
			years /= 1.0 + (t - 40.0) / 60.0
	# Кирпичные печи держат очаг вдвое дольше.
	if p.purpose == RoomType.HEARTH and p.brick_stoves:
		years *= 2.0
	return years


## Сколько лет осталось до разрушения.
func years_left(p: Project) -> float:
	return (1.0 - p.wear) * service_years(p)


func _wear_tick(dt: float) -> void:
	for p: Project in projects.duplicate():
		if not projects.has(p) or (p.phase != Project.Phase.DONE and p.phase != Project.Phase.EQUIP):
			continue
		if p.purpose == RoomType.SHIP:
			continue
		p.wear = minf(1.0, p.wear + dt / (service_years(p) * YEAR))
		for i in WEAR_WARN.size():
			if p.wear < WEAR_WARN[i] or p.wear_warned > i:
				continue
			p.wear_warned = i + 1
			if p.repairing:
				continue
			if i == 0:
				_log("%s: износ %d%% — пора ремонтировать (нажмите на постройку → «Ремонт»)" % [
					p.title(), roundi(WEAR_WARN[i] * 100)], "warning")
			else:
				_log("%s: износ %d%%! Скоро рухнет — срочно нужен ремонт" % [p.title(), roundi(WEAR_WARN[i] * 100)], "danger")
		if p.wear >= 1.0:
			if offline:
				# Без игрока ничего не рушится: постройка держится «на честном слове».
				p.wear = 0.999
			else:
				collapse(p, "износ 100%")


func repair_error(p: Project) -> String:
	if p.phase != Project.Phase.DONE:
		return "Ремонтировать можно только готовую постройку"
	if p.repairing:
		return "Ремонт уже идёт"
	if p.wear < 0.05:
		return "Ремонт пока не нужен"
	return ""


## Материалы на ремонт: часть стоимости постройки по износу.
func repair_cost(p: Project) -> Dictionary:
	var base := p.cost()
	if base.is_empty():
		base = {"wood": maxi(2, p.area() / 3)}
	var out := {}
	for k in base:
		out[k] = maxi(1, ceili(base[k] * p.wear * 0.6))
	return out


func start_repair(p: Project) -> bool:
	wake_idle()
	if not repair_error(p).is_empty():
		return false
	p.repairing = true
	p.repair_paid = false
	p.repair_done = 0.0
	p.repair_need = repair_cost(p)
	p.repair_work = maxf(10.0, p.build_work() * p.wear * 0.5)
	_log("%s: ремонт, нужно %s" % [p.title(), _cost_line(p.repair_need, 1.0)], "info")
	_try_pay(p)
	return true


func _finish_repair(p: Project) -> void:
	if p.move_dir != Vector2i.ZERO:
		_finish_move(p)
		return
	_return_delivered(p)
	p.repairing = false
	p.repair_paid = false
	p.repair_done = 0.0
	p.repair_need = {}
	p.wear = 0.0
	p.wear_warned = 0
	p.blocked = ""
	for u in units:
		if u.project_id == p.id and (u.task == Unit.Task.REPAIR or u.task == Unit.Task.HAUL):
			_drop(u)
	_log("%s: ремонт закончен, как новая" % p.title(), "good")


# --- Сдвиг комнаты ------------------------------------------------------------------------
## Готовую комнату сдвигают за раз вбок до её ширины (3, 6 или 9 м), вверх или вниз —
## до 3 м, если там нет других зданий. Это работа строителей (как ремонт) и половина стоимости стен; порода на
## новом месте выкапывается. Готовые тоннели и шахты на пути комната забирает себе —
## о них спрашивают («Продолжить?»).
const MOVE_DIRS := {Vector2i.LEFT: "влево", Vector2i.RIGHT: "вправо", Vector2i.UP: "вверх", Vector2i.DOWN: "вниз"}


## Насколько можно сдвинуть за раз: вбок — на ширину комнаты, вверх и вниз — на 3 м.
static func move_max(p: Project, dir: Vector2i) -> int:
	return p.rect.size.x if dir.y == 0 else 3


## [ошибка, предупреждение]: ошибка — нельзя; предупреждение — можно, но заденет ходы.
func move_check(p: Project, dir: Vector2i, n := 1) -> Array:
	if n < 1 or n > move_max(p, dir):
		return ["За раз — от 1 до %d м %s" % [move_max(p, dir), MOVE_DIRS.get(dir, "")], ""]
	if p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE:
		return ["Сдвинуть можно только готовую комнату", ""]
	if p.repairing:
		return ["Сначала дождитесь конца ремонта или сдвига", ""]
	if p.purpose == RoomType.SHIP or p.purpose == RoomType.LAUNCHPAD:
		return ["Это не сдвинуть", ""]
	var nr := Rect2i(p.rect.position + dir * n, p.rect.size)
	var hit: PackedStringArray = []
	for c in Project.rect_cells(nr):
		if p.rect.has_point(c):
			continue
		var other := project_at(c)
		if other != null and other != p:
			if (other.kind == Project.Kind.TUNNEL or other.kind == Project.Kind.MINE) and other.phase == Project.Phase.DONE:
				if not hit.has(other.title()):
					hit.append(other.title())
			else:
				return ["Мешает: %s" % other.title(), ""]
		if world.is_revealed(c.x, c.y) and Mat.is_fluid(world.get_mat(c.x, c.y)):
			return ["Там %s" % Mat.name_of(world.get_mat(c.x, c.y)).to_lower(), ""]
	# На этой комнате стоит другая — её сначала.
	for x in range(p.rect.position.x, p.rect.end.x):
		var above := project_at(Vector2i(x, p.rect.position.y - 1))
		if above != null and above.kind == Project.Kind.ROOM and above != p:
			return ["Сверху стоит %s — сдвиньте сначала её" % above.title(), ""]
	# На новом месте комнате есть на что опереться (освобождённое место — не опора).
	# Вверх — свой пол держит комнату, под ней останется пустота.
	for x in (range(nr.position.x, nr.end.x) if dir != Vector2i.UP else []):
		var below := Vector2i(x, nr.end.y)
		if p.rect.has_point(below):
			return ["Под комнатой на новом месте ничего не будет — некуда опереться", ""]
		if not (interior.has(below) or not world.is_revealed(below.x, below.y) or Mat.is_solid(world.get_mat(below.x, below.y))):
			return ["Комнате на новом месте не на что опереться", ""]
	var warn := ""
	if not hit.is_empty():
		warn = "Сдвиг заденет: %s. Эту часть займёт комната, остальное останется ходом. Продолжить?" % ", ".join(hit)
	return ["", warn]


## Материалы на сдвиг: половина стоимости стен.
func move_cost(p: Project) -> Dictionary:
	var out := {}
	var base := p.cost()
	for k in base:
		out[k] = maxi(1, ceili(base[k] * 0.5))
	if out.is_empty():
		out = {"wood": maxi(2, p.area() / 3)}
	return out


func start_move(p: Project, dir: Vector2i, n := 1) -> String:
	wake_idle()
	if not MOVE_DIRS.has(dir):
		return "Сдвиг — влево, вправо, вверх или вниз"
	var err: String = move_check(p, dir, n)[0]
	if not err.is_empty():
		return err
	p.move_dir = dir * n
	p.repairing = true
	p.repair_paid = false
	p.repair_done = 0.0
	p.repair_need = move_cost(p)
	# Работы — как на треть постройки, плюс копка породы на новом месте.
	var solid := 0
	for c in Project.rect_cells(Rect2i(p.rect.position + dir * n, p.rect.size)):
		if not p.rect.has_point(c) and Mat.is_solid(world.get_mat(c.x, c.y)):
			solid += 1
	p.repair_work = maxf(10.0, p.build_work() * 0.35 + solid * 4.0)
	_log("%s: сдвигаем на %d м %s, нужно %s" % [p.title(), n, MOVE_DIRS[dir], _cost_line(p.repair_need, 1.0)], "info")
	_try_pay(p)
	return ""


## Строители закончили: комната встаёт на новое место (порода выкопана, ходы под ней — её).
func _finish_move(p: Project) -> void:
	var dir := p.move_dir
	var old := p.rect
	var nr := Rect2i(old.position + dir, old.size)
	_return_delivered(p)
	p.repairing = false
	p.repair_paid = false
	p.repair_done = 0.0
	p.repair_need = {}
	p.move_dir = Vector2i.ZERO
	p.blocked = ""
	if not move_check_cells_ok(p, nr):
		_log("%s: сдвинуть не вышло — место занято" % p.title(), "warning")
		return
	_carve_passages(nr)
	for c in Project.rect_cells(nr):
		if not old.has_point(c) and Mat.is_solid(world.get_mat(c.x, c.y)):
			_complete_dig(c, null, null)
	for c in Project.rect_cells(old):
		room_cells.erase(c)
		if interior.get(c, 0) == p.id:
			interior.erase(c)
	# Кучи и гаврики внутри едут вместе с комнатой.
	var moved := {}
	for c: Vector2i in drops.keys():
		if old.has_point(c):
			moved[c + dir] = drops[c]
			drops.erase(c)
	for c in moved:
		drops[c] = moved[c]
	for u in units:
		if old.has_point(u.cell()):
			u.pos += Vector2(dir)
	p.rect = nr
	for c in Project.rect_cells(nr):
		interior[c] = p.id
		world.set_dug(c.x, c.y)
	_register_room(p)
	_rebuild_climb()
	# Клетки построек сменились местами (число то же) — пути и проверки клеток забываем целиком.
	pathing.clear_cache()
	loads.loads = loads.compute()
	for u in units:
		if u.project_id == p.id and (u.task == Unit.Task.REPAIR or u.task == Unit.Task.HAUL):
			_drop(u)
	_log("%s: сдвинута на %d м %s" % [p.title(), maxi(absi(dir.x), absi(dir.y)), MOVE_DIRS.get(Vector2i(signi(dir.x), signi(dir.y)), "")], "good")


## Новое место всё ещё свободно (пока сдвигали, рядом могли что-то заложить).
func move_check_cells_ok(p: Project, nr: Rect2i) -> bool:
	for c in Project.rect_cells(nr):
		var other := project_at(c)
		if other != null and other != p and not ((other.kind == Project.Kind.TUNNEL or other.kind == Project.Kind.MINE) and other.phase == Project.Phase.DONE):
			return false
	return true


func _cancel_repair(p: Project) -> void:
	p.move_dir = Vector2i.ZERO
	if p.repair_paid:
		_refund(p.repair_need, 1.0 - p.repair_done / maxf(1.0, p.repair_work))
	_return_delivered(p)
	p.repairing = false
	p.repair_paid = false
	p.repair_done = 0.0
	p.repair_need = {}
	p.blocked = ""
	for u in units:
		if u.project_id == p.id and (u.task == Unit.Task.REPAIR or u.task == Unit.Task.HAUL):
			_drop(u)
	_log("%s: ремонт отменён" % p.title(), "info")


## Постройка рухнула: всё, что в ней лежало, пропадает, кто был внутри — гибнет (кроме
## супер-гавриков), падают верхние этажи, порода может обвалиться. Дегазация взрывается.
func collapse(p: Project, why: String) -> void:
	if not projects.has(p):
		return
	_log("ОБРУШЕНИЕ: %s (%s)" % [p.title(), why], "danger")
	# Запасы, сырьё мастерской и привезённые материалы гибнут вместе с постройкой.
	var lost: PackedStringArray = []
	for k in p.held:
		var n := int(p.held[k])
		if n > 0:
			inventory[k] = maxi(0, int(inventory.get(k, 0)) - n)
			lost.append("%s %d" % [Mat.resource_name(k).to_lower(), n])
	p.held.clear()
	p.stock.clear()
	p.delivered.clear()
	if not lost.is_empty():
		_log("Под обломками пропало: %s" % ", ".join(lost), "danger")
	_release_beds(p)
	projects.erase(p)
	_by_id_n = -1
	for c in p.cells():
		room_cells.erase(c)
		interior.erase(c)
		deck.erase(c)
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_restore_water_overlaps(p)
	_rebuild_climb()
	for u: Unit in units.duplicate():
		var c := u.cell()
		if p.rect.has_point(c) or p.rect.has_point(c + Vector2i(0, -1)):
			if p.is_water_structure():
				# Настил рухнул в воду — гаврик выбирается на берег.
				_drop(u)
				u.pos = Vector2(_ground_cell(p.rect.position.x - 1))
				u.state = Unit.State.IDLE
				injure(u, 10.0, "упал в воду с рухнувшего настила")
			else:
				injure(u, 100000.0, "погиб(ла) под обломками")
			continue
		# Кто работал здесь или шёл через рухнувшее — останавливается и ищет путь заново.
		var through := u.project_id == p.id
		for i in range(u.path_i, u.path.size()):
			if through:
				break
			through = p.rect.has_point(u.path[i])
		if through:
			_drop(u)
	if p.kind == Project.Kind.ROOM:
		# Стены и перекрытия ложатся обломками на пол.
		var floor_y := p.rect.end.y - 1
		for x in range(p.rect.position.x, p.rect.end.x):
			if world.get_mat(x, floor_y) == Mat.AIR:
				world.set_material(x, floor_y, Mat.RUBBLE)
		for u in units:
			if u.cell().y == floor_y and p.rect.has_point(u.cell()):
				u.pos.y = floor_y - 1
	if p.kind == Project.Kind.ROOM and RoomType.EXPLOSIVE.has(p.purpose):
		_explode(p)
	# Этажи сверху теряют опору и тоже рушатся.
	for q: Project in projects.duplicate():
		if q.kind != Project.Kind.ROOM or q.rect.end.y != p.rect.position.y:
			continue
		if q.rect.position.x >= p.rect.end.x or q.rect.end.x <= p.rect.position.x:
			continue
		if not _room_supported(q):
			collapse(q, "рухнул нижний этаж")
	for c in p.cells():
		elements.on_opened(c)
	physics.check_area(p.cells())


## Взрыв рухнувшей дегазации: всё вокруг на 3, 6 или 9 м (по размеру комнаты) рушится,
## порода трескается в обломки, кто рядом — гибнет (кроме супер-гавриков).
func _explode(p: Project) -> void:
	var rad: int = [3, 6, 9][clampi(RoomType.blocks(p), 1, 3) - 1]
	var area := p.rect.grow(rad)
	_log("ВЗРЫВ: %s — разрушено всё вокруг на %d м" % [p.title(), rad], "danger")
	for u: Unit in units.duplicate():
		if area.has_point(u.cell()):
			injure(u, 100000.0, "погиб(ла) при взрыве")
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if p.rect.has_point(c) or y < world.gen.surface_y(x):
				continue
			var m := world.get_mat(x, y)
			if Mat.is_solid(m) and m != Mat.RUBBLE:
				world.set_material(x, y, Mat.RUBBLE)
				cells.append(c)
	for q: Project in projects.duplicate():
		if q.rect.intersects(area):
			collapse(q, "взрыв рядом")
	physics.check_area(cells)


func _room_supported(q: Project) -> bool:
	for x in range(q.rect.position.x, q.rect.end.x):
		var below := Vector2i(x, q.rect.end.y)
		if not interior.has(below) and not Mat.is_solid(world.get_mat(below.x, below.y)):
			return false
	return true


# --- Экономика: мастерские, наука, энергия --------------------------------------------

## Хватает ли сырья на цикл мастерской.
## Сколько сырья k есть у мастерской: принесённое; без игрока гаврики берут и со склада.
func _input_have(p: Project, k: String) -> int:
	# Нефть — по трубам прямо из хранилища.
	if RoomType.PIPED.has(k):
		return inventory.get(k, 0)
	return p.stock.get(k, 0) + (inventory.get(k, 0) if offline else 0)


## Рецепт мастерской сейчас: [сырьё, продукция, секунд]. У кузницы — по нормам (что ниже
## нормы и есть из чего); нечего делать — пусто.
func recipe(p: Project) -> Array:
	if p.purpose != RoomType.FORGE:
		return RoomType.RECIPES.get(p.purpose, [])
	var key := forge_pick(p)
	return RoomType.FORGE_RECIPES[key] if not key.is_empty() else []


## Что кузнице плавить: металл ниже нормы (меньше всего от нормы), сырьё для которого есть.
## Начатый цикл доводится до конца. Пересчёт — раз в секунду.
func forge_pick(p: Project) -> String:
	if p.targets.is_empty():
		p.targets = RoomType.FORGE_TARGETS.duplicate()
	if p.farm_progress > 0.0 and not p.forge_key.is_empty():
		return p.forge_key
	if game_time - p.forge_at < 1.0:
		return p.forge_key
	p.forge_at = game_time
	var best := ""
	var best_r := INF
	for k in RoomType.FORGE_RECIPES:
		var norm := int(p.targets.get(k, 0))
		if norm <= 0:
			continue
		var have := _have_any(k)
		if have >= norm:
			continue
		var ok := true
		var need: Dictionary = RoomType.FORGE_RECIPES[k][0]
		for i in need:
			if int(p.stock.get(i, 0)) + _have_any(i) < int(need[i]):
				ok = false
		if ok and float(have) / norm < best_r:
			best_r = float(have) / norm
			best = k
	p.forge_key = best
	return best


func has_inputs(p: Project) -> bool:
	var r := recipe(p)
	if r.is_empty():
		return false
	var need: Dictionary = r[0]
	for k in need:
		if _input_have(p, k) < need[k]:
			return false
	return not RoomType.FUELED.has(p.purpose) or fuel_have(p) >= 1.0


## На сколько циклов хватит топлива у мастерской: горящее + уголь и дрова в запасе печи.
func fuel_have(p: Project) -> float:
	var n := p.fuel
	for k in ["coal", "wood"]:
		n += _input_have(p, k) * float(RoomType.FUEL_VALUE[k])
	return n


## Подбросить топлива на цикл: сначала уголь, потом дрова.
func _burn_fuel(p: Project) -> void:
	if p.fuel < 1.0:
		for k in ["coal", "wood"]:
			if _input_have(p, k) >= 1:
				if p.stock.get(k, 0) >= 1:
					p.stock[k] -= 1
				else:
					_remove(k, 1)
				p.fuel += float(RoomType.FUEL_VALUE[k])
				break
	p.fuel = maxf(0.0, p.fuel - 1.0)


## Чего не хватает мастерской (пусто — всё есть).
func missing_inputs(p: Project) -> Dictionary:
	var out := {}
	var r := recipe(p)
	if r.is_empty():
		return out
	var need: Dictionary = r[0]
	for k in need:
		if _input_have(p, k) < need[k]:
			out[k] = need[k]
	if RoomType.FUELED.has(p.purpose) and fuel_have(p) < 1.0:
		out["wood"] = 1
	return out


## Готовая продукция: при игроке — кучей на полу мастерской (её уносят подсобные),
## без игрока — сразу на склад (если на нём есть работник).
## Производства (ферма, печь, кузница) держат готовое у себя — в ящиках у входа, не больше
## PRODUCE_CAP; дальше работа стоит, пока подсобные или работники склада не унесут.
const PRODUCE_CAP := 100
const FULL_TEXT := "Склад постройки полон (%d) — отнесите готовое в амбар или на склад"


## Ящики с готовым у входа в производство.
static func output_cell(p: Project) -> Vector2i:
	return Vector2i(RoomType.floor_start(p), p.rect.end.y - 1)


func is_producer(p: Project) -> bool:
	return p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and (p.purpose == RoomType.FARM \
		or (RoomType.RECIPES.has(p.purpose) and not RoomType.PIPED.has(RoomType.RECIPES[p.purpose][1].keys()[0])))


## Сколько готового лежит в ящиках производства.
func output_held(p: Project) -> int:
	var n := 0
	var d: Dictionary = drops.get(output_cell(p), {})
	for k in d:
		n += int(d[k])
	return n


func output_full(p: Project) -> bool:
	return is_producer(p) and output_held(p) >= PRODUCE_CAP


## Производство, чьи это ящики (клетка c), или null.
func producer_at(c: Vector2i) -> Project:
	for p in projects:
		if is_producer(p) and output_cell(p) == c:
			return p
	return null


## Отметка «склад постройки полон» появляется и снимается сама.
func _mark_full(p: Project) -> bool:
	var full := output_full(p)
	if full and p.blocked.is_empty():
		p.blocked = FULL_TEXT % PRODUCE_CAP
	elif not full and p.blocked.begins_with("Склад постройки полон"):
		p.blocked = ""
	return full


func _produce(p: Project, k: String, n: int) -> void:
	if RoomType.PIPED.has(k):
		produced[k] = int(produced.get(k, 0)) + n
		_add(k, n)
		return
	drop_item(output_cell(p), k, n)


func _craft(p: Project) -> void:
	if not has_inputs(p):
		return
	var r := recipe(p)
	for k in r[0]:
		var from_stock := mini(p.stock.get(k, 0), r[0][k])
		p.stock[k] = p.stock.get(k, 0) - from_stock
		_remove(k, r[0][k] - from_stock)
	if RoomType.FUELED.has(p.purpose):
		_burn_fuel(p)
	for k in r[1]:
		_produce(p, k, r[1][k])
	p.forge_at = -INF


## Уровень геологоразведки (0–4).
func geology_level() -> int:
	var n := 0
	for id in ["geology", "geology2", "geology3", "geology4"]:
		if research.has(id):
			n += 1
	return n


## На сколько клеток от выработок видно породу.
func see_radius() -> int:
	return 1 + geology_level()


## Новый уровень геологии — заново осматриваем все выработки.
func _reveal_known() -> void:
	var r := see_radius()
	for c in world.dug_cells():
		for n in world.reveal_around(c.x, c.y, r):
			_note_discovery(world.get_mat(n.x, n.y), n)
	for n in world.deepen_caves(r):
		_note_discovery(world.get_mat(n.x, n.y), n)


func _research(work: float) -> void:
	var lab_power := 1.0 + 0.5 * power_ratio if research.has("electricity") and power_made > 0 else 1.0
	var finished := research.add(work * Research.POINTS_PER_SEC * lab_power * (1.25 if research.has("nature") else 1.0))
	if finished.is_empty():
		return
	_log("Изучено: %s. %s" % [Research.tech_name(finished), Research.TECHS[finished][1]], "good")
	if finished.begins_with("geology"):
		_reveal_known()
	_log("Учёные ждут: выберите следующее исследование («Наука»)", "info")


## Есть ли энергия (изучено электричество и работает генератор).
func powered() -> bool:
	return research.has("electricity") and power_made > 0


func farm_bonus() -> float:
	var k := 1.25 if research.has("mushrooms") else 1.0
	return k * (1.0 + 0.5 * power_ratio if research.has("hydroponics") and powered() else 1.0)


func dig_bonus() -> float:
	return 1.5 if research.has("tools") else 1.0


func build_bonus() -> float:
	return 1.5 if research.has("scaffolding") else 1.0


func automation_bonus() -> float:
	return 1.5 if research.has("electronics") else 1.0


## Сколько гаврик уносит за раз.
func carry_cap() -> int:
	return 8 if research.has("carts") else CARRY


## Генераторы жгут уголь (или дрова) и дают энергию потребителям.
## Есть ли очаг, которому не хватает дров (тогда свободные идут рубить).
func _hearth_starving() -> bool:
	if _have_any("wood") > 0:
		return false
	var gas: bool = inventory.get("methane", 0) > 0
	var coal: bool = _have_any("coal") > 0
	for p in rooms_of(RoomType.HEARTH):
		if not p.paused and p.blocked.begins_with("Нет дров") and not (p.gas_boiler and gas) and not (p.brick_stoves and coal):
			return true
	return false


## Топливо в печи (по «полену» на печь): сначала уголь (за два полена), потом дрова —
## со склада, а нет — из кучи неподалёку (до 12 м). Возвращает, на сколько поленьев нашлось.
func _hearth_fuel(p: Project, need: int) -> int:
	var got := 0
	p.on_gas = false
	# Уголь жгут только кирпичные печи; каменные — только дрова.
	var kinds := ["coal", "wood"] if p.brick_stoves else ["wood"]
	# Газовый котёл: сначала метан от дегазации (печь сама метан не жжёт).
	if p.gas_boiler:
		kinds.push_front("methane")
	for k in kinds:
		var per := int(RoomType.FUEL_VALUE[k])
		var want := ceili(float(need - got) / per)
		if want <= 0:
			break
		var take := _remove(k, want)
		got += take * per
		var c := p.rect.get_center()
		for d: Vector2i in drops.keys():
			if got >= need:
				break
			if absi(d.x - c.x) <= 12 and absi(d.y - c.y) <= 12:
				var t := _take_drop(d, k, ceili(float(need - got) / per))
				take += t
				got += t * per
		if k == "methane" and take > 0:
			p.on_gas = true
	return got


## Нужен ли огонь: рядом с очагом (в зоне его тепла с запасом) есть гаврик или туда идёт,
## рядом ферма, которой без огня холодно, или кто-то в колонии замерзает (тогда разжигают
## все очаги — чтобы было, где согреться). Считается раз в HEARTH_CHECK секунд.
const HEARTH_CHECK := 1.0
var _hearth_need := {}
var _hearth_need_at := -INF


## Холодно ли у очага без огня.
func is_cold_at(p: Project) -> bool:
	var c := p.rect.get_center()
	return world.gen.temperature(c.y, world.gen.surface_y(c.x), season_delta()) < HEARTH_ON_BELOW


func hearth_needed(p: Project) -> bool:
	if game_time - _hearth_need_at >= HEARTH_CHECK:
		_hearth_need_at = game_time
		_hearth_need.clear()
		var freezing := false
		for u in units:
			if needs_warmth(u):
				freezing = true
				break
		for h in rooms_of(RoomType.HEARTH):
			_hearth_need[h.id] = freezing or _someone_near(h)
	return bool(_hearth_need.get(p.id, true))


func _someone_near(h: Project) -> bool:
	var area := h.rect.grow(RoomType.heat_zone(h, research.has("insulation")).y + 2)
	for u in units:
		if area.has_point(u.cell()):
			return true
		if u.state == Unit.State.MOVE and not u.path.is_empty() and area.has_point(u.path[-1]):
			return true
	for f in rooms_of(RoomType.FARM):
		var fc := f.rect.get_center()
		if f.rect.intersects(area) and world.gen.temperature(fc.y, world.gen.surface_y(fc.x), season_delta()) < FARM_MIN_TEMP:
			return true
	return false


## Очаги: жгут дрова, пока вокруг холодно и есть кого греть; без дров гаснут.
func _hearth_tick(dt: float) -> void:
	for p in rooms_of(RoomType.HEARTH):
		var was := p.burning
		p.burning = false
		if p.paused:
			continue
		# Холодно ли без огня (своё тепло не считаем) и греть ли кого-то: очаг горит только
		# по нужде, а недогоревшее полено ждёт следующего раза.
		var cold := is_cold_at(p) and hearth_needed(p)
		if not cold:
			# Потеплело — топить не нужно: «нет дров» больше не тревога (иначе все рубят лес).
			if p.blocked.begins_with("Нет дров"):
				p.blocked = ""
			continue
		if p.farm_progress <= 0.0:
			# Каждая печь жжёт своё полено; не хватило на все — горит меньше.
			var n := RoomType.stoves(p)
			var per_log := RoomType.HEARTH_FUEL_TIME * (RoomType.BRICK_STOVE_GAIN if p.brick_stoves else 1.0)
			p.farm_progress += per_log * _hearth_fuel(p, n) / n
		if p.farm_progress > 0.0:
			p.farm_progress -= dt
			p.burning = true
			if p.blocked.begins_with("Нет дров"):
				p.blocked = ""
		elif p.blocked.is_empty():
			p.blocked = "Нет дров и угля — очаг погас"
			_log("%s: %s" % [p.title(), p.blocked], "warning")
		if was != p.burning:
			elements._temp_memo.clear()


func _power_tick(dt: float) -> void:
	power_made = 0
	power_used = 0
	for p in generators():
		p.burning = false
		if p.paused:
			continue
		# Газовый жжёт только метан из баков дегазации, дизельный — дизель из нефтехранилища,
		# обычный — уголь, а без него дрова.
		var gas := p.purpose == RoomType.GAS_GEN
		var diesel := p.purpose == RoomType.DIESEL_GEN
		if p.farm_progress <= 0.0:
			if diesel:
				if _remove("diesel", 1) >= 1:
					p.farm_progress += RoomType.FUEL_TIME * 2.0
			elif gas:
				if _remove("methane", 1) >= 1:
					p.farm_progress += RoomType.FUEL_TIME
			elif _remove("coal", 1) >= 1:
				p.farm_progress += RoomType.FUEL_TIME
			elif inventory.get("wood", 0) >= 2:
				_remove("wood", 2)
				p.farm_progress += RoomType.FUEL_TIME
		if p.farm_progress > 0.0:
			p.farm_progress -= dt
			p.burning = true
			power_made += roundi(RoomType.POWER_MAKE * (1.5 if research.has("mechanics") else 1.0) * (1.5 if diesel else 1.0))
			if p.blocked.begins_with("Нет топлива") or p.blocked.begins_with("Нет метана") or p.blocked.begins_with("Нет дизеля"):
				p.blocked = ""
		elif p.blocked.is_empty():
			p.blocked = "Нет дизеля: нужен нефтезавод и топливо в нефтехранилище" if diesel else \
				("Нет метана: нужна дегазация с газом в баке" if gas else "Нет топлива: нужен уголь или дрова")
			_log("%s: %s" % [p.title(), p.blocked], "warning")
	_hearth_tick(dt)
	for p in lifts():
		if not p.paused:
			power_used += LIFT_POWER
	# Реактор корабля: свой ток, тепло, воздух и свет внутри.
	for p in rooms_of(RoomType.SHIP):
		power_made += RoomType.SHIP_POWER
		p.burning = true
	for p in projects:
		if _drill_active(p):
			power_used += DRILL_POWER
		elif probing(p) and not p.paused:
			power_used += PROBE_POWER
	for t in RoomType.POWER_USE:
		if t == RoomType.FARM and not research.has("hydroponics"):
			continue
		for p in rooms_of(t):
			if not p.paused:
				power_used += RoomType.POWER_USE[t]
	_lights_tick()
	power_ratio = 1.0 if power_used == 0 else minf(1.0, float(power_made) / power_used)


## Который час (0..24).
func hour() -> float:
	return fmod(game_time, DAY) / DAY * 24.0


func is_night() -> bool:
	if not DAY_NIGHT:
		return false
	var h := hour()
	return h >= NIGHT_FROM or h < NIGHT_TO


## Светло ли: 1 — день, 0 — ночь, плавно на рассвете (5–7) и закате (19–21).
func daylight() -> float:
	if not DAY_NIGHT:
		return 1.0
	var h := hour()
	if h < 5.0 or h >= 21.0:
		return 0.0
	if h < 7.0:
		return (h - 5.0) / 2.0
	if h >= 19.0:
		return 1.0 - (h - 19.0) / 2.0
	return 1.0


## Дата и время по игровому календарю: «12 мар · весна · 14:30 · год 1».
func date_text() -> String:
	var days := int((game_time + CALENDAR_START) / DAY)
	var head := "%d %s · %s" % [days % 30 + 1, MONTH_NAMES[(days % 360) / 30], SEASON_NAMES[season()]]
	var year := int(game_time / YEAR) + 1
	if not DAY_NIGHT:
		return "%s · год %d" % [head, year]
	var minutes := int(hour() * 60.0)
	return "%s · %02d:%02d · год %d" % [head, minutes / 60, minutes % 60 / 10 * 10, year]


# --- Времена года ---------------------------------------------------------------------

## Месяцы от 1 января, дробно (0..12): для плавной смены листвы.
func calendar_month() -> float:
	return fmod(game_time + CALENDAR_START, YEAR) / MONTH


## Месяц календаря: 0 — январь … 11 — декабрь.
func month() -> int:
	return int((game_time + CALENDAR_START) / MONTH) % 12


func season() -> int:
	return [Season.WINTER, Season.WINTER, Season.SPRING, Season.SPRING, Season.SPRING, Season.SUMMER,
		Season.SUMMER, Season.SUMMER, Season.AUTUMN, Season.AUTUMN, Season.AUTUMN, Season.WINTER][month()]


func is_winter() -> bool:
	return season() == Season.WINTER and world.gen.planet_id == "earth"


## Отклонение температуры на поверхности от Env.SURFACE_TEMP: холоднее всего в середине января.
func season_delta() -> float:
	var m := fmod(game_time + CALENDAR_START, YEAR) / MONTH - 0.5
	var i := floori(m)
	var a: float = MONTH_TEMPS[posmod(i, 12)]
	var b: float = MONTH_TEMPS[posmod(i + 1, 12)]
	return lerpf(a, b, m - i) - Env.SURFACE_TEMP


var _last_season := -1
var _last_month := -1


## Смена времён года — в журнал, с подсказкой, к чему готовиться.
func _season_tick() -> void:
	# На других планетах времён года нет.
	if world.gen.planet_id != "earth":
		return
	var m := month()
	if m == _last_month:
		return
	var first := _last_month < 0
	_last_month = m
	var sn := season()
	if sn != _last_season:
		_last_season = sn
		if not first:
			match sn:
				Season.WINTER:
					_log("Пришла зима: ягоды не растут, озёра замёрзли — рыба только с пристани, вдвое медленнее. Фермам и гаврикам нужно тепло — очаг", "warning")
				Season.SPRING:
					_log("Весна: снова растут ягоды, озёра оттаяли", "good")
				Season.SUMMER:
					_log("Лето — самое время запасать еду на зиму", "info")
	if m == 10 and not first and food_value() < winter_food_need():
		_log("Через месяц зима! Еды на зиму не хватит — запасите её в амбаре, поставьте очаг у фермы", "danger")


## Сколько сытости съест колония за зиму (три месяца).
func winter_food_need() -> float:
	return units.size() * SATIETY_DECAY * 0.8 * MONTH * 3.0


## Сколько осталось до зимы (0 — уже зима).
func time_to_winter() -> float:
	if is_winter():
		return 0.0
	var f := fmod(game_time + CALENDAR_START, YEAR)
	return MONTH * 11.0 - f


## Температура в комнате (по её середине).
func room_temp(p: Project) -> float:
	return elements.temperature(p.rect.get_center())


## Ниже какой температуры гаврику холодно: синим и пушистым — ниже, красным — выше.
static func cold_limit(u: Unit) -> float:
	return COLD - (u.stat("cold") - 1.0) * 30.0


## В жилом доме мороз: жильцы мёрзнут во сне (нужен очаг рядом).
func home_freezing(p: Project) -> bool:
	return p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and p.purpose == RoomType.HOME \
		and room_temp(p) < COLD


func farm_warm(p: Project) -> bool:
	return room_temp(p) >= FARM_MIN_TEMP


## Время улова с постройки с учётом зимы.
func fish_time(p: Project) -> float:
	return p.fish_time() * (WINTER_FISH_SLOWDOWN if is_winter() else 1.0)


## Можно ли ловить с этой постройки сейчас: зимой — только с пристани.
func can_fish_from(p: Project) -> bool:
	return not is_winter() or p.kind == Project.Kind.PIER


## Длительность в игровых сутках: «3 дн.», «8 ч».
static func game_span(seconds: float) -> String:
	var days := seconds / DAY
	if days >= 1.0:
		return "%d дн." % roundi(days)
	return "%d ч" % maxi(1, roundi(days * 24.0))


# --- Оффлайн-симуляция --------------------------------------------------------------

## Упрощённая модель: гаврики не ходят, а сразу работают с меньшей эффективностью
## (часть времени уходит на сон и еду). Возвращает число выкопанных клеток.
func advance_offline(dt: float) -> int:
	offline = true
	_sync_held()
	for u in units:
		_drop(u)
	# Пока игрока нет, гаврики перетаскивают добытое на склад.
	for c in drops:
		for k in drops[c]:
			_add(k, int(drops[c][k]))
	drops.clear()
	var dug_before := cells_dug
	var remaining := dt
	var guard := 200000
	while remaining > 0.001 and guard > 0:
		guard -= 1
		_gather_miss.clear()
		for p in projects:
			if not p.paused:
				_try_pay(p)
		# цель -> [вид, суммарная скорость, первый гаврик, проект]
		var jobs := {}
		var taken := {}
		for u in units:
			if u.child:
				continue
			var job := _offline_job(u, taken)
			if job.is_empty():
				continue
			var key = job[0]
			var skill := Unit.skill_for(job[1])
			var rate := u.speed(skill) * OFFLINE_EFFICIENCY * u.need_factor() * u.age_factor() \
				* work_factor(u, job[1], Vector2i.ZERO)
			if jobs.has(key):
				jobs[key][1] += rate
			else:
				jobs[key] = [job[1], rate, u, job[2]]
			u.task = job[1]
		var step := minf(remaining, OFFLINE_STEP)
		for key in jobs:
			step = minf(step, _offline_left(key, jobs[key]) / jobs[key][1])
		step = maxf(step, 0.0)
		remaining -= step
		game_time += step
		elements._temp_memo.clear()
		_tick_exposure(step)
		_wear_tick(step)
		_absorb_site_drops()
		_power_tick(step)
		_lifts_tick(step)
		_drills_tick(step)
		_oil_tick(step)
		_plant_tick(step)
		_season_tick()
		_life_tick(step, true)
		for u in units:
			if u.task != Unit.Task.NONE:
				var sk := Unit.skill_for(u.task)
				if not sk.is_empty():
					u.skills[sk] += step
				u.task = Unit.Task.NONE
		for key in jobs:
			var j: Array = jobs[key]
			match j[0]:
				Unit.Task.DIG:
					dig_progress[key] = dig_progress.get(key, 0.0) + j[1] * step
					if dig_progress[key] >= dig_time(key) - 0.001:
						_complete_dig(key, j[3], j[2])
				Unit.Task.BUILD:
					var p: Project = j[3]
					p.build_done += j[1] * step
					if p.build_done >= p.build_work() - 0.001:
						_finish_project(p)
				Unit.Task.EQUIP:
					var p: Project = j[3]
					p.equip_done += j[1] * step
					if p.equip_done >= RoomType.job_work(p) - 0.001:
						_finish_equip(p)
				Unit.Task.CRAFT:
					var p: Project = j[3]
					var cr := recipe(p)
					if cr.is_empty():
						continue
					p.farm_progress += j[1] * step
					var need: float = cr[2]
					while p.farm_progress >= need and has_inputs(p) and not output_full(p):
						p.farm_progress -= need
						_craft(p)
						p.forge_at = -INF
						cr = recipe(p)
						if cr.is_empty():
							break
						need = cr[2]
					p.farm_progress = minf(p.farm_progress, need)
				Unit.Task.RESEARCH:
					_research(j[1] * step)
				Unit.Task.FARM:
					var p: Project = j[3]
					p.farm_progress += j[1] * step * farm_bonus()
					while p.farm_progress >= RoomType.FARM_CYCLE:
						p.farm_progress -= RoomType.FARM_CYCLE
						_add("food", 1)
						produced["food"] = int(produced.get("food", 0)) + 1
				Unit.Task.SUPPORT:
					var p: Project = j[3]
					p.support_progress += j[1] * step
					if p.support_progress >= p.slice_work() - 0.001:
						_finish_support(p)
				Unit.Task.FISH:
					var p: Project = j[3]
					if p == null:
						# С берега: прогресс по месту ловли.
						var sx := int(String(key).substr(1).split(",")[0])
						var lake := _lake_near(sx)
						_shore_progress[key] = _shore_progress.get(key, 0.0) + j[1] * step
						while _shore_progress[key] >= SHORE_FISH_TIME and fish_in(lake) >= 1.0:
							_shore_progress[key] -= SHORE_FISH_TIME
							_catch_from(lake, null)
					else:
						# У пристаней прогресс улова хранится в farm_progress.
						p.farm_progress += j[1] * step
						while p.farm_progress >= fish_time(p) and fish_left(p) >= 1.0 and can_fish_from(p):
							p.farm_progress -= fish_time(p)
							_catch_fish(p, null)
				Unit.Task.HARVEST:
					var x: int = int(key.substr(1))
					harvest_progress[x] = harvest_progress.get(x, 0.0) + j[1] * step
					if harvest_progress[x] >= HARVEST_TIME.get(world.feature_at(x), 20.0) - 0.001:
						# Работник склада — добытое сразу в его склад (у расчистки j[3] — стройка).
						var gr: Project = j[3]
						var to_room := gr.id if gr != null and gr.kind == Project.Kind.ROOM and gr.phase == Project.Phase.DONE \
							and RoomType.is_store(gr.purpose) else 0
						_complete_harvest(x, j[2], to_room)
				Unit.Task.HAUL:
					_offline_progress[key] = _offline_progress.get(key, 0.0) + j[1] * step
					if _offline_progress[key] >= OFFLINE_HAUL_TIME - 0.001:
						_offline_progress.erase(key)
						_offline_deliver(j[3])
				Unit.Task.REPAIR:
					var p: Project = j[3]
					p.repair_done += j[1] * step
					if p.repair_done >= p.repair_work - 0.001:
						_finish_repair(p)
	offline = false
	return cells_dug - dug_before


func _offline_left(key: Variant, job: Array) -> float:
	match job[0]:
		Unit.Task.DIG:
			return dig_time(key) - dig_progress.get(key, 0.0)
		Unit.Task.BUILD:
			var p: Project = job[3]
			return p.build_work() - p.build_done
		Unit.Task.EQUIP:
			var p: Project = job[3]
			return RoomType.job_work(p) - p.equip_done
		Unit.Task.FARM, Unit.Task.FISH, Unit.Task.CRAFT, Unit.Task.RESEARCH:
			return OFFLINE_STEP
		Unit.Task.SUPPORT:
			var p: Project = job[3]
			return p.slice_work() - p.support_progress
		Unit.Task.HARVEST:
			var x: int = int(key.substr(1))
			return HARVEST_TIME.get(world.feature_at(x), 20.0) - harvest_progress.get(x, 0.0)
		Unit.Task.HAUL:
			return OFFLINE_HAUL_TIME - _offline_progress.get(key, 0.0)
		Unit.Task.REPAIR:
			var p: Project = job[3]
			return p.repair_work - p.repair_done
	return 0.0


## Оффлайн-ходка: приносит на стройку то, чего не хватает.
func _offline_deliver(p: Project) -> void:
	if not projects.has(p):
		return
	var left := remaining(p)
	for k in left:
		var n := _take_any(k, mini(carry_cap(), left[k]))
		if n <= 0:
			continue
		p.delivered[k] = p.delivered.get(k, 0) + n
		break
	_try_pay(p)


## Объект для добычи оффлайн; промахи по виду запоминаются на шаг расчёта.
var _gather_miss := {}


func _offline_gather_x(kind: int, taken: Dictionary) -> Variant:
	if kind < 0 or _gather_miss.has(kind):
		return null
	for x in range(maxi(explored_min, home.x - PLANT_AREA), mini(explored_max, home.x + PLANT_AREA) + 1):
		if not taken.has("h%d" % x) and _gather_ok(x, kind):
			return x
	_gather_miss[kind] = true
	return null


func _offline_can_haul(p: Project) -> bool:
	var left := remaining(p)
	for k in left:
		if _have_any(k) > 0:
			return true
	return false


## [ключ цели, вид задачи, проект] или [] если работы нет.
func _offline_job(u: Unit, taken: Dictionary) -> Array:
	for kind in _task_order(u):
		if kind == "workplace":
			var wp := _offline_workplace(u, taken)
			if not wp.is_empty():
				return wp
			continue
		if kind == "need":
			var nd := _offline_need(taken)
			if not nd.is_empty():
				return nd
			continue
		match kind:
			"harvest":
				var h := _offline_harvest(taken)
				if not h.is_empty():
					return h
			"farm":
				for p in rooms_of(RoomType.FARM):
					var slot := "w%d" % p.id
					if not p.paused and taken.get(slot, 0) < RoomType.farm_slots(p):
						taken[slot] = taken.get(slot, 0) + 1
						return ["f%d" % p.id, Unit.Task.FARM, p]
			"craft", "science":
				var kinds: Array = RoomType.RECIPES.keys() if kind == "craft" else [RoomType.LAB]
				for t in kinds:
					for p in rooms_of(t):
						var slot := "w%d" % p.id
						if p.paused or taken.get(slot, 0) >= RoomType.farm_slots(p):
							continue
						if kind == "craft" and not has_inputs(p):
							continue
						if kind == "science" and research.current.is_empty():
							continue
						taken[slot] = taken.get(slot, 0) + 1
						return ["c%d" % p.id, Unit.Task.CRAFT if kind == "craft" else Unit.Task.RESEARCH, p]
			"storage":
				for room in store_rooms():
					var gslot := "g%d" % room.id
					if room.paused or taken.get(gslot, 0) >= room.gatherers:
						continue
					for k in storage_deficit(room):
						var x = _offline_gather_x(GATHER_SOURCES[k], taken)
						if x != null:
							taken["h%d" % x] = true
							taken[gslot] = taken.get(gslot, 0) + 1
							return ["h%d" % x, Unit.Task.HARVEST, room]
			"fish":
				for p in projects:
					var slot := "w%d" % p.id
					if p.is_water_structure() and p.phase == Project.Phase.DONE and not p.paused \
							and taken.get(slot, 0) < p.fish_slots() and fish_left(p) >= 1.0:
						taken[slot] = taken.get(slot, 0) + 1
						return ["fish%d" % p.id, Unit.Task.FISH, p]
				for spot in shore_spots():
					var key := "f%d,%d" % [spot.x, spot.y]
					if not taken.has(key) and fish_in(_lake_near(spot.x)) >= 1.0:
						taken[key] = true
						return [key, Unit.Task.FISH, null]
			"dig", "build", "projects", "mines", "builds":
				for p in projects:
					var slot := "w%d" % p.id
					if p.paused or taken.get(slot, 0) >= p.workers:
						continue
					if p.phase == Project.Phase.DONE and not p.repairing:
						continue
					if p.bored_by > 0:
						continue
					if kind != "build" and p.phase == Project.Phase.DIG:
						for x in uncleared(p):
							if not taken.has("h%d" % x):
								taken["h%d" % x] = true
								taken[slot] = taken.get(slot, 0) + 1
								return ["h%d" % x, Unit.Task.HARVEST, p]
						var si := slice_to_support(p)
						if si >= 0 and _pay_support(p, si):
							taken[slot] = taken.get(slot, 0) + 1
							return ["sup%d" % p.id, Unit.Task.SUPPORT, p]
						if si < 0:
							for c in diggable_now(p):
								if taken.has(c):
									continue
								for d in DIRS4:
									if world.is_open(c.x + d.x, c.y + d.y):
										if _hazard_stop(p, c):
											return []
										taken[c] = true
										taken[slot] = taken.get(slot, 0) + 1
										return [c, Unit.Task.DIG, p]
					if kind == "dig":
						continue
					if p.phase == Project.Phase.BUILD and p.paid:
						taken[slot] = taken.get(slot, 0) + 1
						return ["b%d" % p.id, Unit.Task.BUILD, p]
					if p.phase == Project.Phase.EQUIP and p.equip_paid:
						taken[slot] = taken.get(slot, 0) + 1
						return ["e%d" % p.id, Unit.Task.EQUIP, p]
					if p.phase == Project.Phase.DONE and p.repair_paid:
						taken[slot] = taken.get(slot, 0) + 1
						return ["r%d" % p.id, Unit.Task.REPAIR, p]
					if _offline_can_haul(p):
						taken[slot] = taken.get(slot, 0) + 1
						return ["haul%d:%d" % [p.id, u.id], Unit.Task.HAUL, p]
	return []


## Оффлайн: сбор по нужде — стройке не хватает дерева или камня: сначала отмеченное
## игроком, потом ближайшее подходящее.
func _offline_need(taken: Dictionary) -> Array:
	var keys := {}
	for p in projects:
		if p.paused or not p.blocked.begins_with("Не хватает"):
			continue
		for k in _needed_now(p):
			if GATHER_SOURCES.has(k) and GATHER_SOURCES[k] >= 0:
				keys[k] = true
	if _hearth_starving():
		keys["wood"] = true
	if keys.is_empty():
		return []
	var h := _offline_harvest(taken)
	if not h.is_empty():
		return h
	for k in keys:
		var x = _offline_gather_x(GATHER_SOURCES[k], taken)
		if x != null:
			taken["h%d" % x] = true
			return ["h%d" % x, Unit.Task.HARVEST, null]
	return []


## Оффлайн: работа на своём месте (только назначенные).
func _offline_workplace(u: Unit, taken: Dictionary) -> Array:
	var p := project_by_id(u.workplace)
	if not is_workplace(p) or p.paused:
		return []
	var slot := "w%d" % p.id
	if p.is_water_structure():
		if taken.get(slot, 0) < p.fish_slots() and fish_left(p) >= 1.0 and can_fish_from(p):
			taken[slot] = taken.get(slot, 0) + 1
			return ["fish%d" % p.id, Unit.Task.FISH, p]
		return []
	match p.purpose:
		RoomType.FARM:
			if farm_warm(p):
				taken[slot] = taken.get(slot, 0) + 1
				return ["f%d" % p.id, Unit.Task.FARM, p]
		RoomType.LAB:
			if not research.current.is_empty():
				taken[slot] = taken.get(slot, 0) + 1
				return ["c%d" % p.id, Unit.Task.RESEARCH, p]
		RoomType.KILN, RoomType.FORGE, RoomType.REFINERY, RoomType.ENRICHMENT:
			if has_inputs(p):
				taken[slot] = taken.get(slot, 0) + 1
				return ["c%d" % p.id, Unit.Task.CRAFT, p]
		RoomType.STORAGE, RoomType.GRANARY:
			if p.purpose == RoomType.STORAGE:
				var h := _offline_harvest(taken)
				if not h.is_empty():
					return h
			for k in storage_deficit(p):
				var x = _offline_gather_x(GATHER_SOURCES[k], taken)
				if x != null:
					taken["h%d" % x] = true
					return ["h%d" % x, Unit.Task.HARVEST, p]
	return []


func _offline_harvest(taken: Dictionary) -> Array:
	var want_food := food_low()
	var pick = null
	for x in world.feature_marks:
		var key := "h%d" % x
		if taken.has(key) or not harvestable(x):
			continue
		if pick == null or (want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH):
			pick = x
			if want_food and world.feature_at(x) == WorldGen.FEATURE_BUSH:
				break
	if pick == null:
		return []
	taken["h%d" % pick] = true
	return ["h%d" % pick, Unit.Task.HARVEST, null]


# --- Вспомогательное ----------------------------------------------------------------

## Склады раздельные: у каждого склада и амбара своё содержимое (held), метан —
## в баках дегазации. inventory — итог по колонии: всё в комнатах плюс запас у базы
## (стартовые припасы и то, что не легло в комнаты, — до BASE_CAPACITY).

## Комнаты, где может лежать ресурс: метан — в дегазации, еда — в амбарах, остальное — на складах.
func holders(key: String) -> Array[Project]:
	if key == "methane":
		return rooms_of(RoomType.DEGAS)
	if key == "oil" or key == "diesel":
		return rooms_of(RoomType.OIL_TANK)
	var out: Array[Project] = []
	for p in store_rooms():
		if RoomType.stores(p, key):
			out.append(p)
	return out


## Сколько ресурса помещается в комнате p.
func room_cap(p: Project, key: String) -> int:
	if key == "methane":
		return RoomType.GAS_PER_CELL * RoomType.usable_width(p) if p.purpose == RoomType.DEGAS else 0
	if key == "oil" or key == "diesel":
		return RoomType.OIL_PER_CELL * RoomType.usable_width(p) if p.purpose == RoomType.OIL_TANK else 0
	if p.purpose == RoomType.SHIP:
		return 0 if RoomType.BULK.has(key) else RoomType.SHIP_HOLD
	if not RoomType.is_store(p.purpose) or not RoomType.stores(p, key) or RoomType.BULK.has(key):
		return 0
	var c := RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p)
	return roundi(c * 1.5) if research.has("shelving") else c


func held_in(p: Project, key: String) -> int:
	return int(p.held.get(key, 0))


## Сколько ещё влезет в комнату p (с учётом того, что туда уже несут).
func room_free(p: Project, key: String) -> int:
	return room_limit(p, key) - held_in(p, key) - _incoming_room(p, key)


func _incoming_room(p: Project, key: String) -> int:
	var n := 0
	for u in units:
		if u.task == Unit.Task.HAUL and u.project_id == p.id and u.carry_key == key and (u.to_store or u.gather_room != 0):
			n += u.carry_amount
	return n


## Сколько лежит у базы (не в комнатах).
func base_have(key: String) -> int:
	var n: int = inventory.get(key, 0)
	for p in holders(key):
		n -= held_in(p, key)
	return maxi(0, n)


func _base_cap(key: String) -> int:
	return 0 if RoomType.PIPED.has(key) else RoomType.BASE_CAPACITY


## Склад (амбар) в клетке c.
func store_at(c: Vector2i) -> Project:
	var p := project_at(c)
	if p != null and p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and RoomType.is_store(p.purpose):
		return p
	return null


## В комнатах не может лежать больше, чем всего есть (итог правят напрямую: тесты, старые сохранения).
func _clamp_held(key: String) -> void:
	var total: int = inventory.get(key, 0)
	var sum := 0
	var rooms: Array[Project] = []
	var hs := holders(key)
	for p in projects:
		if p.held.get(key, 0) > 0:
			if not hs.has(p):
				# Комнату снесли или переделали — её запас остаётся у базы.
				p.held.erase(key)
				continue
			sum += held_in(p, key)
			rooms.append(p)
	rooms.sort_custom(func(a: Project, b: Project) -> bool: return held_in(a, key) > held_in(b, key))
	for p in rooms:
		if sum <= total:
			break
		var cut := mini(held_in(p, key), sum - total)
		p.held[key] = held_in(p, key) - cut
		if p.held[key] <= 0:
			p.held.erase(key)
		sum -= cut


## Старые сохранения: запасы были общими. Нормы — каждому складу из общих, запасы
## раскладываем по складам (что не влезло — у базы), метан — в баки дегазации
## (не влезший улетучивается).
func _migrate_stores() -> void:
	for p in store_rooms():
		if p.targets.is_empty():
			for k in store_targets:
				if RoomType.stores(p, k):
					p.targets[k] = mini(int(store_targets[k]), room_cap(p, k))
	for k in inventory.keys():
		var extra := base_have(k) - _base_cap(k)
		if extra <= 0:
			continue
		var rooms := holders(k)
		for p in rooms:
			if extra <= 0:
				break
			var put := clampi(room_cap(p, k) - held_in(p, k), 0, extra)
			p.held[k] = held_in(p, k) + put
			extra -= put
		if RoomType.PIPED.has(k) and extra > 0:
			inventory[k] = int(inventory[k]) - extra


## До руды шахты давали готовый металл — в старом сохранении он становится рудой
## (1 к 1), её переплавляют в кузнице.
const OLD_METAL_ORE := {"iron": "iron_ore", "copper": "copper_ore", "silver": "silver_ore",
	"gold": "gold_ore", "uranium": "uranium_ore"}


func _migrate_ores() -> void:
	var swap := func(dict: Dictionary) -> void:
		for k in OLD_METAL_ORE:
			if dict.has(k):
				var ore: String = OLD_METAL_ORE[k]
				dict[ore] = int(dict.get(ore, 0)) + int(dict[k])
				dict.erase(k)
	swap.call(inventory)
	for k in OLD_METAL_ORE:
		if known_resources.has(k):
			known_resources[OLD_METAL_ORE[k]] = true
	for p in projects:
		swap.call(p.held)
		swap.call(p.lift_load)
	for c in drops:
		swap.call(drops[c])


func _sync_held() -> void:
	for k in inventory.keys():
		_clamp_held(k)
	for p in projects:
		for k in p.held.keys():
			if not inventory.has(k):
				p.held.erase(k)


## Берёт ресурс: из комнаты room (если указана), иначе сначала у базы, потом из складов.
## Возвращает, сколько взято.
func _remove(key: String, n: int, room: Project = null) -> int:
	var t := mini(n, int(inventory.get(key, 0)))
	if t <= 0:
		return 0
	if room != null:
		t = mini(t, held_in(room, key))
		room.held[key] = held_in(room, key) - t
		if room.held[key] <= 0:
			room.held.erase(key)
	inventory[key] = int(inventory.get(key, 0)) - t
	_clamp_held(key)
	return t


## Кладёт ресурс. В комнату room — только туда (остаток возвращается вызвавшему);
## без комнаты — в склады с работником (метан — в баки дегазации), потом к базе.
## Возвращает, сколько поместилось.
func _add(key: String, amount: int, room: Project = null) -> int:
	if key.is_empty() or amount <= 0:
		return 0
	known_resources[key] = true
	_clamp_held(key)
	if RoomType.BULK.has(key):
		# Пустая порода не копится — исчезает.
		inventory.erase(key)
		return amount
	var have: int = inventory.get(key, 0)
	var put := 0
	if room != null:
		put = clampi(room_limit(room, key) - held_in(room, key), 0, amount)
		room.held[key] = held_in(room, key) + put
	else:
		# Без работника на склад ничего не носят.
		for p in holders(key):
			if put >= amount:
				break
			if not RoomType.PIPED.has(key) and not store_staffed(p):
				continue
			var free := clampi(room_limit(p, key) - held_in(p, key), 0, amount - put)
			if free > 0:
				p.held[key] = held_in(p, key) + free
				put += free
		put += clampi(_base_cap(key) - base_have(key), 0, amount - put)
	inventory[key] = have + put
	var cap := capacity(key)
	if room != null:
		return put
	# Предупреждаем один раз на ресурс, пока не построят новый склад.
	if put < amount and not _full_warned.has(key) and not RoomType.PIPED.has(key):
		_full_warned[key] = true
		_log("Склад полон: %s (%d). Постройте склад, лишнее выбрасывается." % [Mat.resource_name(key).to_lower(), cap], "warning")
	return put


func _depth_text(c: Vector2i) -> String:
	return "%s м" % Fmt.int_spaced(c.y - world.gen.surface_y(c.x))


func _log(text: String, kind: String) -> void:
	event_logged.emit(text, kind)


# --- Сохранение -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var dp := []
	for c in dig_progress:
		dp.append([c.x, c.y, dig_progress[c]])
	var hp := []
	for x in harvest_progress:
		hp.append([x, harvest_progress[x]])
	var ps := []
	for p in projects:
		ps.append(p.to_dict())
	var us := []
	for u in units:
		us.append(u.to_dict())
	# Груз в руках гавриков сохраняем как запас склада.
	var inv := inventory.duplicate()
	for u in units:
		if u.task == Unit.Task.HAUL and u.haul_stage == 1 and u.carry_amount > 0:
			inv[u.carry_key] = inv.get(u.carry_key, 0) + u.carry_amount
	return {
		"game_time": game_time,
		"inventory": inv,
		"known_resources": known_resources.keys(),
		"cells_dug": cells_dug,
		"discovered": discovered.keys(),
		"dig_progress": dp,
		"harvest_progress": hp,
		"projects": ps,
		"units": us,
		"next_project_id": next_project_id,
		"next_unit_id": next_unit_id,
		"social_t": _social_t,
		"acquaint": acquaint,
		"home": [home.x, home.y],
		"plant_t": _plant_t,
		"explored": [explored_min, explored_max, deepest_y, highest_y],
		"fish": fish,
		"elements": elements.to_dict(),
		"drops": _drops_list(),
		"store_targets": store_targets,
		"stores_v": 1,
		"ores_v": 1,
		"life_v": 2,
		"steel_v": 1,
		"loads": loads.to_dict(),
		"disasters": disasters,
		"research": research.to_dict(),
	}


func _drops_list() -> Array:
	var out := []
	for c: Vector2i in drops:
		out.append([c.x, c.y, drops[c]])
	return out


func load_dict(d: Dictionary) -> void:
	# Стали больше нет — в старом сохранении она (на складах, в стенах, в крепи, в нормах) — железо.
	if int(d.get("steel_v", 0)) < 1:
		d = steel_to_iron(d)
	inventory.clear()
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		if not RoomType.BULK.has(k):
			inventory[k] = int(inv[k])
		known_resources[k] = true
	for k in d.get("known_resources", []):
		known_resources[str(k)] = true
	cells_dug = int(d.get("cells_dug", 0))
	game_time = float(d.get("game_time", 0.0))
	for m in d.get("discovered", []):
		discovered[int(m)] = true
	for e in d.get("dig_progress", []):
		dig_progress[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("harvest_progress", []):
		harvest_progress[int(e[0])] = float(e[1])
	store_targets.clear()
	var st: Dictionary = d.get("store_targets", {})
	for k in st:
		store_targets[str(k)] = int(st[k])
	# Раньше еду для склада ловили как «food» — теперь это рыба.
	if store_targets.has("food"):
		store_targets["fish"] = store_targets["food"]
		store_targets.erase("food")
	for pd in d.get("projects", []):
		var p := Project.from_dict(pd)
		projects.append(p)
		# Старые сохранения: нормы были у каждого склада — берём наибольшую.
		if not d.has("store_targets"):
			for k in p.targets:
				store_targets[k] = maxi(int(store_targets.get(k, 0)), int(p.targets[k]))
		_register_room(p)
		if (p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP) and p.kind != Project.Kind.DRILL and p.kind != Project.Kind.PROBE:
			for c in p.cells():
				interior[c] = p.id
		_register_deck(p)
	_rebuild_climb()
	for ud in d.get("units", []):
		var u := Unit.from_dict(ud)
		if u.genome.is_empty():
			# Старое сохранение: гаврикам — гены основателей, пол прежний.
			var g := Genetics.founder(rng)
			g["female"] = u.sex == Unit.Sex.FEMALE
			u.set_genome(g)
		units.append(u)
	next_project_id = int(d.get("next_project_id", projects.size() + 1))
	next_unit_id = int(d.get("next_unit_id", units.size() + 1))
	_social_t = float(d.get("social_t", 0.0))
	acquaint = d.get("acquaint", {}).duplicate()
	_plant_t = float(d.get("plant_t", 0.0))
	var ex: Array = d.get("explored", [])
	var fd: Dictionary = d.get("fish", {})
	for k in fd:
		fish[int(k)] = float(fd[k])
	var h: Array = d.get("home", [0, world.gen.surface_y(0)])
	home = Vector2i(int(h[0]), int(h[1]))
	if ex.size() == 4:
		explored_min = int(ex[0])
		explored_max = int(ex[1])
		deepest_y = int(ex[2])
		highest_y = int(ex[3])
	else:
		explored_min = home.x - EXPLORE_RADIUS
		explored_max = home.x + EXPLORE_RADIUS
		deepest_y = home.y
		highest_y = home.y
	elements.load_dict(d.get("elements", {}))
	for e in d.get("drops", []):
		var dc := Vector2i(int(e[0]), int(e[1]))
		var dd := {}
		for k in e[2]:
			dd[str(k)] = int(e[2][k])
		drops[dc] = dd
	loads.load_dict(d.get("loads", {}))
	disasters = bool(d.get("disasters", true))
	research.load_dict(d.get("research", {}))
	if int(d.get("stores_v", 0)) < 1:
		_migrate_stores()
	if int(d.get("ores_v", 0)) < 1:
		_migrate_ores()
	# Жили 3,5 года, потом 5, теперь 10 — сроки уже живущих растут так же.
	var life_v := int(d.get("life_v", 0))
	if life_v < 1:
		for u in units:
			u.lifespan *= 5.0 / 3.5
	if life_v < 2:
		for u in units:
			u.lifespan *= 2.0
	# Бур раньше был ходом во всю длину — теперь это машина 3×3: старый отменяется,
	# материалы возвращаются на склад.
	for p in projects.duplicate():
		if p.kind == Project.Kind.DRILL and p.rect.size != Vector2i(3, 3):
			cancel_project(p)
			_log("Бур переделан: теперь это машина 3×3, которой в карточке велят, куда и сколько сверлить. Старый бур убран, материалы вернулись — поставьте его заново.", "warning")
	loads.loads = loads.compute()
	# Стены открытых пещер — на дальность геологоразведки (старые сохранения).
	world.deepen_caves(see_radius())
	world.scan_deepest_seen()
	explore()
	_refresh_bushes()
