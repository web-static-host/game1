class_name Colony
extends RefCounted
## Колония: жители, стройки, комнаты, склад.
## Жители сами разбирают работу: сначала потребности (сон, еда), потом работа
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
	"methane": "Метан в выработке! Искра от кирки — взрыв. Работы стоят, пока газ не уйдёт (поможет дегазация). Продолжить на свой риск?",
}
## Ресурсы, о находке которых сообщаем сразу.
const NOTABLE := ["coal", "iron", "copper", "silver", "gold", "uranium", "diamond", "salt", "oil"]

# Потребности (сек. реального времени): сытости хватает минут на 10, бодрости — тоже;
# спят по усталости (смена дня и ночи пока выключена). Во сне голод растёт медленнее.
const SATIETY_DECAY := 100.0 / 600.0
const ENERGY_DECAY := 100.0 / 600.0
const SLEEP_BED := 100.0 / 150.0
const SLEEP_FLOOR := 100.0 / 240.0
## Ночью ложатся спать, если бодрость ниже этого (при смене дня и ночи).
const NIGHT_SLEEP := 85.0
## Просыпаются, выспавшись до этого.
const WAKE := 100.0
## За сколько секунд полный голод убивает здорового жителя (5 минут).
const STARVE_TIME := 300.0
const EAT_TIME := 6.0
const HUNGRY := 35.0
const TIRED := 25.0
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
## Сколько единиц ресурса житель уносит за раз.
const CARRY := 5
## Оффлайн одна ходка за материалами занимает столько секунд.
const OFFLINE_HAUL_TIME := 20.0
# Игровое время: сутки — 20 секунд, месяц — 10 минут, год — 2 часа игры.
const DAY := 20.0
## Смена дня и ночи (пока выключена: спят по усталости).
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
## Ниже этой температуры обычному жителю холодно (синие и пушистые терпят больше).
const COLD := 0.0
## Зимой с пристани рыба ловится вдвое дольше, с берега и мостиков — никак (лёд).
const WINTER_FISH_SLOWDOWN := 2.0
## Сколько лет служит постройка до полного износа (на поверхности).
const WEAR_YEARS := {"wood": 20.0, "stone": 100.0, "brick": 70.0, "metal": 60.0}
## Под землёй сырость: дерево и металл изнашиваются быстрее, камню всё равно.
const WEAR_UNDERGROUND := {"wood": 0.6, "stone": 1.0, "brick": 0.9, "metal": 0.6}
## Предупреждения об износе.
const WEAR_WARN := [0.7, 0.9]
## Ресурсы, которые жители склада добывают сами: ресурс -> объект поверхности.
## −1 — еду (рыбу) не собирают с объектов, а ловят.
const GATHER_SOURCES := {"wood": WorldGen.FEATURE_TREE, "stone": WorldGen.FEATURE_BOULDER, "berries": WorldGen.FEATURE_BUSH, "food": -1}
## Сытость за единицу: ягоды — лёгкий перекус, рыба и грибы с фермы — настоящая еда.
const NUTRITION := {"food": 32.0, "berries": 9.0}
## За один приём пищи съедают до стольких единиц, пока не наберут столько сытости.
const MEAL_UNITS := 4
const MEAL_GOAL := 60.0
## В столовой еда сытнее.
const DINING_BONUS := 1.5
## Норма запаса для нового склада.
const DEFAULT_TARGETS := {"wood": 40, "stone": 20, "food": 30}

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
## Занятые цели: ключ -> id жителя.
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
## Разведанная часть мира: столбцы, куда доходили жители, и глубина/высота работ.
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
## Когда житель последний раз уходил из облака метана: id -> время игры.
var _fled := {}
## Знакомства: "id1,id2" -> сколько секунд провели рядом (с поправкой на общительность).
var acquaint := {}
## Когда последний раз сообщали о газовой тревоге на стройке: id -> время игры.
var _gas_logged := {}
const GAS_LOG_EVERY := 300.0
## Когда последний раз посылали жителя на разведку за сырьём (время игры).
var _scout_at := -100.0
## Прогресс оффлайн-работ без своего места хранения (ходки за материалами, ремонт).
var _offline_progress := {}
## Добытое лежит там, где добыто, пока не унесут: клетка -> {ресурс: количество}.
var drops := {}
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
	u.lifespan = Unit.LIFESPAN * u.stat("longevity") * rng.randf_range(0.85, 1.15)
	u.name = _free_name(u.sex)
	u.look = rng.randf()
	u.pos = pos
	units.append(u)
	return u


## Своё имя из слогов, не занятое другими жителями.
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

func project_by_id(pid: int) -> Project:
	for p in projects:
		if p.id == pid:
			return p
	return null


## Игрок что-то поручил — жители без дела ищут работу сразу, а не через несколько секунд.
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
			# Мост и пристань могут лежать друг на друге — берём меньшую (пристань).
			if found == null or (p.is_water_structure() and found.is_water_structure() and p.area() < found.area()):
				found = p
			if not p.is_water_structure():
				return p
	return found


func unit_at(p: Vector2) -> Unit:
	var best: Unit = null
	var best_d := 1.2
	for u in units:
		var d := (u.pos + Vector2(0, -0.5)).distance_to(p)
		if d < best_d:
			best_d = d
			best = u
	return best


## Материалы стен, доступные колонии: дерево сразу, остальное — когда добыто.
func available_materials() -> Array[String]:
	var out: Array[String] = ["wood"]
	if known_resources.has("stone"):
		out.append("stone")
	if research.has("bricks"):
		out.append("brick")
	if research.has("metallurgy"):
		out.append("metal")
	return out


## Сколько жителей могут одновременно пройти тоннелем (по его ширине).
static func tunnel_lanes(r: Rect2i) -> int:
	if r.size.y > r.size.x:
		return maxi(1, r.size.x)
	return maxi(1, r.size.y - 1)


func validate(kind: int, r: Rect2i, material := "wood") -> String:
	var err := Project.size_error(kind, r)
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
			if other != null and not (kind == Project.Kind.ROOM and _room_fits_mine(r, other)):
				if other.kind == Project.Kind.MINE and kind == Project.Kind.ROOM:
					return "Комнату в шахте ставьте на всю её высоту, когда шахта готова"
				return "Пересекается с другой стройкой"
			if world.is_revealed(x, y) and Mat.is_fluid(world.get_mat(x, y)):
				return "В зоне стройки %s" % Mat.name_of(world.get_mat(x, y)).to_lower()
	if kind == Project.Kind.BRIDGE or kind == Project.Kind.PIER:
		return _water_structure_error(kind, r)
	if kind == Project.Kind.TUNNEL or kind == Project.Kind.MINE:
		for x in range(r.position.x, r.end.x):
			if r.position.y < world.gen.surface_y(x):
				return "%s — только под землёй. Над землёй стройте комнаты" % ("Тоннели" if kind == Project.Kind.TUNNEL else "Шахты")
	if kind == Project.Kind.ROOM:
		# Каждая колонна комнаты должна на что-то опираться.
		for x in range(r.position.x, r.end.x):
			var below := Vector2i(x, r.end.y)
			var ok := interior.has(below) or not world.is_revealed(below.x, below.y) \
				or Mat.is_solid(world.get_mat(below.x, below.y))
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
	# Если до того берега жителям не дойти — от другого.
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


## Могут ли жители дойти до зоны (обход от каждого взрослого, кэш на полсекунды).
var _reach_cache: Array = []
var _reach_at := -100000


func can_reach(r: Rect2i) -> bool:
	var now := Time.get_ticks_msec()
	if now - _reach_at > 500 or _reach_cache.is_empty() or offline:
		_reach_cache.clear()
		_reach_at = now
		var seen := {}
		for u in units:
			if u.child or seen.has(u.cell()):
				continue
			seen[u.cell()] = true
			_reach_cache.append(pathing.explore(u.cell())[1])
	for dist in _reach_cache:
		if _near_rect(r, dist) != null:
			return true
	return false


## Раз в несколько секунд: до каких строек жителям не дойти — предупреждение.
func _check_access() -> void:
	for p in projects:
		var working := p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD \
			or p.phase == Project.Phase.EQUIP or p.repairing
		if p.paused or not working or workers_on(p) > 0:
			continue
		var blocked_access := p.blocked.begins_with("Нет доступа")
		if not p.blocked.is_empty() and not blocked_access:
			continue
		if can_reach(p.rect):
			if blocked_access:
				p.blocked = ""
		elif not blocked_access:
			p.blocked = "Нет доступа — жители не могут дойти до стройки" if p.is_water_structure() \
				else "Нет доступа — проложите тоннель к стройке"
			_log("%s: %s" % [p.title(), p.blocked], "warning")


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


func create_project(kind: int, r: Rect2i, workers := -1, material := "wood") -> Project:
	wake_idle()
	if not validate(kind, r, material).is_empty():
		return null
	if kind == Project.Kind.ROOM:
		_carve_mines(r)
	var p := Project.new()
	p.id = next_project_id
	next_project_id += 1
	p.kind = kind
	p.rect = r
	p.material = material if kind == Project.Kind.ROOM else "wood"
	p.workers = workers if workers > 0 else Project.recommended_workers(kind, r, adults())
	p.ladder = kind == Project.Kind.ROOM and _floor_below_surface(r)
	p.support_wood = support_needed(kind, r)
	# Срезы, где есть порода: их копают по одному и сразу крепят.
	if kind == Project.Kind.ROOM or kind == Project.Kind.TUNNEL or kind == Project.Kind.MINE:
		for i in p.slice_count():
			for c in p.slice_cells(i):
				if Mat.is_solid(world.get_mat(c.x, c.y)):
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
func gas_stop(p: Project) -> void:
	p.paused = true
	p.hazard_pending = "methane"
	p.blocked = HAZARD_TEXT["methane"]
	# Газ то копится, то уходит — не засыпаем сообщениями: о стройке не чаще раза в 5 минут.
	if game_time - float(_gas_logged.get(p.id, -1000.0)) > GAS_LOG_EVERY:
		_log("%s: %s" % [p.title(), p.blocked], "danger")
	_gas_logged[p.id] = game_time
	for u in units:
		if u.project_id == p.id:
			_drop(u)


## Житель почуял взрывоопасный метан и уходит к ближайшему чистому воздуху.
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
	var best = null
	var best_d := 1 << 30
	for c: Vector2i in dist:
		if dist[c] < best_d and elements.gas_at(c) < Elements.GAS_CLEAR and elements.gas_at(c + Vector2i.UP) < Elements.GAS_CLEAR:
			best_d = dist[c]
			best = c
	if best == null or best == u.cell():
		return
	_drop(u)
	_start(u, Unit.Task.GOTO, best, best, 0, reach[0])
	elements._warn_once("flee", "%s уходит из облака метана" % u.name, "warning")


func cancel_project(p: Project) -> void:
	wake_idle()
	if p.kind == Project.Kind.MINE and p.phase == Project.Phase.DIG and mine_meters_done(p) > 0:
		stop_mine(p)
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
	projects.erase(p)
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
	var spent := p.cost()
	if p.purpose != RoomType.NONE:
		var eq := RoomType.equip_cost(p.purpose, p)
		for k in eq:
			spent[k] = spent.get(k, 0) + eq[k]
	_refund(spent, 0.5)
	_return_delivered(p)
	_release_beds(p)
	projects.erase(p)
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

## Сколько дерева ещё уйдёт на крепь незакреплённых срезов.
func support_wood_left(p: Project) -> int:
	if p.phase != Project.Phase.DIG:
		return 0
	var n := 0
	for i in p.needs_support:
		if not p.supported.has(i) and not (p.support_paid and p.support_slice == i):
			n += 1
	return n * p.slice_wood()


## Материалы, которые нужно принести на стройку для оставшихся работ (всего).
## Пока копают, носят дерево на крепь и заодно материалы на строительство.
func required(p: Project) -> Dictionary:
	var out := {}
	match p.phase:
		Project.Phase.DIG:
			out = p.cost().duplicate()
			var sw := support_wood_left(p)
			if sw > 0:
				out["wood"] = out.get("wood", 0) + sw
		Project.Phase.BUILD:
			if not p.paid:
				out = p.cost().duplicate()
		Project.Phase.EQUIP:
			if not p.equip_paid:
				out = RoomType.job_cost(p).duplicate()
		Project.Phase.DONE:
			if p.repairing and not p.repair_paid:
				out = p.repair_need.duplicate()
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
func _needed_now(p: Project) -> Dictionary:
	match p.phase:
		Project.Phase.DIG:
			var i := slice_to_support(p)
			if i >= 0 and not (p.support_paid and p.support_slice == i):
				return {"wood": p.slice_wood()}
			return {}
		Project.Phase.BUILD:
			return p.cost() if not p.paid else {}
		Project.Phase.EQUIP:
			return RoomType.job_cost(p) if not p.equip_paid else {}
		Project.Phase.DONE:
			return p.repair_need if p.repairing and not p.repair_paid else {}
	return {}


## Хватит ли ресурсов вообще: на складе + несут + уже на месте.
func _check_supply(p: Project) -> void:
	var need := _needed_now(p)
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


## Где можно лазить (pathing.ladders, pathing.sites): лестницы готовых построек и леса строек.
func _rebuild_climb() -> void:
	var lad := {}
	var site := {}
	for p in projects:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			for c in p.cells():
				site[c] = true
	for p in projects:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			continue
		match p.kind:
			Project.Kind.TUNNEL, Project.Kind.MINE:
				# Вертикальный тоннель — с лестницей; горизонтальный и шахта — только по полу.
				if p.rect.size.y > p.rect.size.x:
					for c in p.cells():
						lad[c] = true
			Project.Kind.ROOM:
				for side in [-1, 1]:
					if edge_ladder(p, side, site):
						var x := p.rect.position.x if side < 0 else p.rect.end.x - 1
						for y in range(p.rect.position.y, p.rect.end.y):
							lad[Vector2i(x, y)] = true
	if lad != pathing.ladders or site != pathing.sites:
		pathing.ladders.clear()
		pathing.ladders.merge(lad)
		pathing.sites.clear()
		pathing.sites.merge(site)
		pathing.climb_rev += 1


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
		p.delivered["wood"] = int(p.delivered.get("wood", 0)) + p.slice_wood()
	p.support_slice = -1
	p.support_paid = false
	var old := p.cells()
	var total := p.slice_count()
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
	var need := p.slice_wood()
	if p.delivered.get("wood", 0) < need:
		return false
	p.delivered["wood"] -= need
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
	_check_phase(p)


## Клетки, которые можно копать сейчас: только в начатом срезе, пока он не закреплён.
func diggable_now(p: Project) -> Array[Vector2i]:
	var all := remaining_dig(p)
	var active := active_slices(p)
	if active.is_empty():
		return all
	var out: Array[Vector2i] = []
	for c in all:
		if active.has(p.slice_of(c)) and not slice_dug(p, p.slice_of(c)):
			out.append(c)
	return out


func remaining_dig(p: Project) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in p.cells():
		if Mat.is_solid(world.get_mat(c.x, c.y)):
			out.append(c)
	return out


## Базовое время копки клетки (для жителя с навыком 1).
func dig_time(c: Vector2i) -> float:
	var m := world.get_mat(c.x, c.y)
	var t := Mat.hardness(m) * Env.heat_work_factor(Env.temperature(c.y, world.gen.surface_y(c.x)))
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
		if p.kind == Project.Kind.MINE:
			# Шахта — без отделки: выкопана и закреплена — готова.
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
	for k in cost:
		if p.delivered.get(k, 0) < cost[k]:
			_check_supply(p)
			return
	for k in cost:
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
	_return_delivered(p)
	p.phase = Project.Phase.DONE
	highest_y = mini(highest_y, p.rect.position.y)
	p.blocked = ""
	for c in p.cells():
		interior[c] = p.id
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_register_deck(p)
	_rebuild_climb()
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	if p.kind == Project.Kind.ROOM:
		_log("Построено: %s. Выберите назначение комнаты." % p.title(), "good")
	else:
		_log("Построено: %s" % p.title(), "good")


## Убрали мост или пристань — общие с другой водной постройкой клетки снова её.
func _restore_water_overlaps(gone: Project) -> void:
	if not gone.is_water_structure():
		return
	for q in projects:
		if q != gone and q.is_water_structure() and q.phase == Project.Phase.DONE and q.rect.intersects(gone.rect):
			for c in q.cells():
				interior[c] = q.id
			_register_deck(q)


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
	_log("%s: обустройство под «%s»" % [p.title(), RoomType.NAMES[t]], "info")
	_try_pay(p)
	return true


## Улучшение очага: каменные печи — до кирпичных, любые — газовыми котлами.
func is_hearth_upgrade(p: Project, t: int) -> bool:
	if p.purpose != RoomType.HEARTH:
		return false
	return (t == RoomType.HEARTH_BRICK and not p.brick_stoves) or (t == RoomType.HEARTH_GAS and not p.gas_boiler)


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
	if not p.equip_ladder and p.equip_material.is_empty() and not is_hearth_upgrade(p, p.equip_target):
		p.purpose = RoomType.NONE
	p.equip_ladder = false
	p.equip_material = ""
	p.blocked = ""
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	_log("%s: обустройство отменено" % p.title(), "info")


func _finish_equip(p: Project) -> void:
	_return_delivered(p)
	p.phase = Project.Phase.DONE
	p.blocked = ""
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
	for p in rooms_of(RoomType.HOME):
		n += RoomType.beds(p)
	return n


func pregnant_count() -> int:
	var n := 0
	for u in units:
		if u.pregnancy >= 0.0:
			n += 1
	return n


## Клетка пола, где стоит кровать (index с 1).
static func bed_cell(p: Project, index: int) -> Vector2i:
	return Vector2i(RoomType.floor_start(p) + (index - 1) * 2, p.rect.end.y - 1)


func _claim_bed(u: Unit) -> void:
	if u.bed_room != 0 and project_by_id(u.bed_room) != null:
		return
	u.bed_room = 0
	var taken := {}
	for o in units:
		if o.bed_room != 0:
			taken["%d:%d" % [o.bed_room, o.bed_index]] = true
	for p in rooms_of(RoomType.HOME):
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
	return inventory.get("food", 0) + inventory.get("berries", 0) > 0


func food_low() -> bool:
	return food_value() < units.size() * MEAL_GOAL * 1.5


## Еды меньше, чем на полприёма каждому, — все силы на еду.
func food_critical() -> bool:
	return food_value() < units.size() * MEAL_GOAL * 0.5 and drop_total("food") + drop_total("berries") == 0


## Приём пищи: сначала настоящая еда, потом ягоды; take(ключ, n) отдаёт, сколько взяли.
func _eat_from(u: Unit, take: Callable, bonus := 1.0) -> void:
	var gained := 0.0
	var eaten := 0
	# Растущий ребёнок насыщается вдвое хуже.
	var k_scale := bonus * (0.5 if u.child else 1.0)
	for key in ["food", "berries"]:
		while eaten < MEAL_UNITS and gained < MEAL_GOAL and u.satiety < 100.0:
			if int(take.call(key, 1)) <= 0:
				break
			var add: float = NUTRITION[key] * k_scale
			u.satiety = minf(100.0, u.satiety + add)
			gained += add
			eaten += 1


func _take_store(key: String, n: int) -> int:
	return _remove(key, n)


## Без игрока жители берут и со склада, и с куч на земле (склада может не быть).
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


## room — склад, для которого житель добывал: добычу он несёт туда сам.
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
		_log("%s %s: +%d %s" % [u.name if u != null else "Жители", what, y[1], Mat.resource_name(y[0]).to_lower()], "info")
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
		if p != null:
			p.found[key] = p.found.get(key, 0) + amount
		if NOTABLE.has(key):
			_log("%s %s: %s ×%d (глубина %s)" % [
				u.name if u != null else "Жители", "нашла" if u != null and u.sex == Unit.Sex.FEMALE else "нашёл",
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
			_depth_text(c), int(Env.temperature(c.y, world.gen.surface_y(c.x)))], "danger")
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


## Порода упала из src в land: задевает жителей по пути, засыпает стройку.
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
	if u.ability("collapse_proof") == true and (why.contains("обвал") or why.contains("обломк") or why.contains("засыпало") or why.contains("обрушен")):
		_log("%s: %s — панцирь выдержал!" % [u.name, why], "good")
		return
	dmg /= maxf(0.3, u.stat("health"))
	u.health -= dmg
	if u.health > 0.0:
		_log("%s: %s, здоровье %d%%" % [u.name, why, roundi(u.health)], "danger")
		return
	if offline:
		# Пока игрока нет, жители не гибнут — только тяжело ранены.
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
		# Свободный житель ловил от голода — съедает улов на месте, остаток оставляет на берегу.
		var catch := {"food": 2}
		_eat_from(u, func(key: String, n: int) -> int:
			var t := mini(n, int(catch.get(key, 0)))
			if t > 0:
				catch[key] -= t
			return t)
		if catch["food"] > 0:
			drop_item(u.cell(), "food", catch["food"])
	elif u != null:
		drop_item(u.cell(), "food", 2)
		if not offline:
			_pick_up(u, _landing(u.cell()), "food")
	else:
		_add("food", 2)
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

func _life_tick(dt: float, offline: bool) -> void:
	for u: Unit in units.duplicate():
		if not offline:
			elements.affect_unit(u, dt)
			if not units.has(u):
				continue
		var asleep := u.task == Unit.Task.SLEEP and u.state == Unit.State.WORK
		u.satiety = maxf(0.0, u.satiety - SATIETY_DECAY * dt * (0.4 if asleep else 1.0) * u.stat("appetite"))
		# Без еды здоровье тает: примерно за двое суток — смерть (без игрока — только истощение).
		if u.satiety <= 0.0:
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
		if u.task != Unit.Task.SLEEP:
			u.energy = maxf(0.0, u.energy - ENERGY_DECAY * dt / maxf(0.3, u.stat("stamina")))
		var heal := (100.0 / 1200.0 if u.task == Unit.Task.SLEEP else 100.0 / 3600.0) * (2.0 if research.has("medicine") else 1.0)
		u.health = minf(100.0, u.health + dt * heal)
		if offline:
			# Оффлайн жители сами едят и спят по расписанию.
			if u.satiety < HUNGRY + 5.0 and _have_any("food") + _have_any("berries") > 0:
				_eat_from(u, _take_any, DINING_BONUS if not rooms_of(RoomType.DINING).is_empty() else 1.0)
			elif u.satiety < HUNGRY + 5.0:
				for bx in _bushes:
					if world.feature_at(bx) == WorldGen.FEATURE_BUSH and world.berries(bx) >= 1.0:
						_eat_from(u, func(key: String, n: int) -> int: return _take_bush(bx, key, n))
						break
			u.energy = maxf(u.energy, 60.0)
		var was_elder := u.is_elder()
		u.age += dt
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
	var genome := Genetics.child(mother.genome, father.genome if father != null else mother.genome, rng)
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
		_log("Родился СВЕРХЮНИТ: %s — цвета лого, все характеристики вдвое выше!" % baby.name, "good")
	elif Genetics.is_mutant(genome):
		_log("%s — %s" % [baby.name, Genetics.mutation_text(genome).to_lower()], "good" if Genetics.rarity(genome) >= 2 else "info")


# --- Места работы: игрок ставит конкретных жителей (как в Fallout Shelter) ---------------

## Куда можно назначить жителя: ферма, лаборатория, печь, кузница, склад, пристань.
func is_workplace(p: Project) -> bool:
	if p == null or p.phase != Project.Phase.DONE:
		return false
	if p.is_water_structure():
		return true
	return p.kind == Project.Kind.ROOM and p.purpose in [RoomType.FARM, RoomType.LAB, RoomType.KILN, RoomType.FORGE,
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


## Роль жителя без места работы: свободный, строитель или подсобный рабочий.
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
		RoomType.KILN, RoomType.FORGE:
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


## Насколько характеристики жителя подходят для работы (1.0 — обычный).
func stat_fit(u: Unit, task: int) -> float:
	if u.genome.is_empty() or not JOB_STATS.has(task):
		return 1.0
	var st: Array = JOB_STATS[task]
	return maxf(0.3, u.stat(st[0]) * (1.0 + 0.5 * (u.stat(st[1]) - 1.0)))


## Основная работа жителя: место работы или роль (строитель, шахтёр, подсобный); -1 — нет.
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


## Насколько житель хорош на этом месте (1.0 — обычный).
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
		RoomType.KILN, RoomType.FORGE:
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


## Знакомство растёт, когда жители рядом. Быстро — у тех, кто работает на одном месте
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


## Лучшие знакомые жителя: [[житель, знакомство]].
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
			_rebuild_climb()
		for p in projects:
			if not p.paused:
				_try_pay(p)
		_tick_exposure(step)
		_wear_tick(step)
		_power_tick(step)
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
		_access_t += 1
		if _access_t >= 5:
			_access_t = 0
			_check_access()
			_settle_drops()
		# Воду откачали — затопленная стройка продолжается сама.
		for p in projects:
			if p.paused and p.blocked.begins_with("В зоне"):
				_check_liquids(p)
				if p.blocked.is_empty():
					p.paused = false
					_log("%s: вода ушла, работы продолжаются" % p.title(), "good")


## Жители открывают карту вокруг себя.
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
					u.retry = minf(1.5 + 0.75 * u.idle_fails, 5.0)
					# Бездельники не стоят толпой в одной точке — расходятся по комнатам.
					if not offline and u.state == Unit.State.IDLE and _crowded(u):
						_stroll(u)
		Unit.State.FALL:
			u.pos.x = roundf(u.pos.x)
			var k := Vector2i(roundi(u.pos.x), floori(u.pos.y))
			if not pathing.passable(k):
				_unbury(u)
				return
			# Падает до первой опоры — сквозь породу не проваливается.
			var to_y := u.pos.y + FALL_SPEED * dt
			while k.y <= floori(to_y):
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
			_work(u, dt)


## Рядом (в той же клетке) стоит другой житель без дела.
func _crowded(u: Unit) -> bool:
	for o in units:
		if o != u and o.state == Unit.State.IDLE and absf(o.pos.x - u.pos.x) < 0.8 and absf(o.pos.y - u.pos.y) < 0.5:
			return true
	return false


## Житель без дела отходит на свободное место: в свою спальню, а если до неё
## не дойти — в ближайшую комнату, где никто не стоит.
func _stroll(u: Unit) -> bool:
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
			if taken.has(c) or not dist.has(c) or c == u.cell():
				continue
			if p.id == u.bed_room and dist[c] <= 80:
				home.append(c)
			elif dist[c] <= 40:
				near.append(c)
	var pool := home if not home.is_empty() else near
	if pool.is_empty():
		return false
	var to: Vector2i = pool[rng.randi() % pool.size()]
	_start(u, Unit.Task.STROLL, to, to, 0, reach[0])
	return true


## Приземление: с высоты больше 4 м — травма.
func _land(u: Unit, c: Vector2i) -> void:
	u.pos.y = c.y
	u.state = Unit.State.IDLE
	var height := c.y - u.fall_from
	if height > 4.0 and not offline:
		injure(u, (height - 4.0) * 12.0, "упал(а) с высоты %d м" % roundi(height))


## Жителя засыпало породой: выбирается в ближайшую пустоту или гибнет.
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


## Житель под водой: плывёт к ближайшему месту, где можно встать и дышать.
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


## Отправить жителя в точку target (или как можно ближе к ней). Возвращает, куда он пойдёт.
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


## Совсем устал или голоден — бросает работу.
func _needs_interrupt(u: Unit) -> bool:
	if u.task == Unit.Task.SLEEP or u.task == Unit.Task.EAT:
		return false
	return u.energy < 10.0 or (u.satiety < 15.0 and has_food())


## Замедление в тесном тоннеле: поток ограничен его шириной.
func congestion(u: Unit) -> float:
	var p := project_at(u.cell())
	if p == null or p.kind != Project.Kind.TUNNEL:
		return 1.0
	var vertical := p.rect.size.y > p.rect.size.x
	var crowd := 1
	for o in units:
		if o == u or not p.has_cell(o.cell()):
			continue
		var d := absf(o.pos.y - u.pos.y) if vertical else absf(o.pos.x - u.pos.x)
		if d <= 1.2:
			crowd += 1
	return minf(1.0, float(tunnel_lanes(p.rect)) / crowd)


func _move(u: Unit, dt: float) -> void:
	var budget := dt
	var jam := congestion(u)
	while budget > 0.0 and u.path_i < u.path.size():
		# Путь устарел (рухнуло, убрали лестницу) — останавливаемся и ищем заново.
		if not pathing.node(u.path[u.path_i]):
			_drop(u)
			return
		var next := Vector2(u.path[u.path_i])
		var delta := next - u.pos
		var spd := (CLIMB_SPEED if absf(delta.y) > absf(delta.x) else WALK_SPEED) * jam * u.move_factor()
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
		if u.task == Unit.Task.DIG or u.task == Unit.Task.HARVEST:
			if u.target.x != u.cell().x:
				u.facing = 1 if u.target.x > u.cell().x else -1


## Смягчённая характеристика: +30% силы — это +18% к скорости работы.
# --- Свет -----------------------------------------------------------------------------

## Под землёй темно: пока нет электричества, светит только солнце — сверху и в открытую шахту.
const DARK_WORK := 0.7
## Как глубоко солнце проникает в открытую сверху шахту.
const SUN_SHAFT := 8
## Светящийся житель освещает всё вокруг себя.
const GLOW_RADIUS := 4


## Светло ли в клетке: над землёй, в открытой шахте недалеко от неба, в комнате, где горит свет,
## у лампы на стройке, рядом со светящимся жителем.
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
		p.lit = false
	if not powered():
		return
	# Включённые вручную горят всегда.
	var auto: Array[Project] = []
	for p in projects:
		if not lightable(p):
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


## Насколько быстро житель делает эту работу — от характеристик, умений и мутаций.
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
		u.skills[skill] += dt * (2.0 if research.has("education") else 1.0) * u.stat("learning") * grow
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
		Unit.Task.REPAIR:
			var rp := project_by_id(u.project_id)
			rp.repair_done += rate * build_bonus()
			if rp.repair_done >= rp.repair_work:
				_finish_repair(rp)
		Unit.Task.CRAFT:
			var cp := project_by_id(u.project_id)
			cp.farm_progress += rate * automation_bonus()
			if cp.farm_progress >= RoomType.RECIPES[cp.purpose][2]:
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
			p.farm_progress += rate * farm_bonus()
			while p.farm_progress >= RoomType.FARM_CYCLE:
				p.farm_progress -= RoomType.FARM_CYCLE
				_produce(p, "food", 1)
			u.work_t += dt
			if u.work_t >= FARM_SHIFT:
				_drop(u)
		Unit.Task.SLEEP:
			u.energy = minf(100.0, u.energy + dt * (SLEEP_BED if u.project_id != 0 else SLEEP_FLOOR))
			# Ночью спят до утра, днём — пока не отдохнут.
			if not is_night() and u.energy >= WAKE:
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
				return drop_amount(u.target, "food") + drop_amount(u.target, "berries") > 0
			return true
		Unit.Task.FISH:
			if u.project_id == 0:
				return fish_in(_lake_near(u.target.x)) >= 1.0
			var fp := project_by_id(u.project_id)
			return fp != null and not fp.paused and fp.phase == Project.Phase.DONE and fish_left(fp) >= 1.0
		Unit.Task.SUPPORT:
			var sp := project_by_id(u.project_id)
			return sp != null and not sp.paused and sp.phase == Project.Phase.DIG and sp.support_paid and sp.support_slice >= 0
		Unit.Task.SLEEP, Unit.Task.GOTO, Unit.Task.STROLL:
			return true
	return false


func _drop(u: Unit) -> void:
	var key = _reserve_key(u)
	if key != null and reserved.get(key) == u.id:
		reserved.erase(key)
	# Брошенный груз остаётся лежать, где житель его бросил.
	if u.task == Unit.Task.HAUL and u.haul_stage == 1 and u.carry_amount > 0:
		drop_item(u.cell(), u.carry_key, u.carry_amount)
	u.carry_key = ""
	u.carry_amount = 0
	u.haul_stage = 0
	u.gather_room = 0
	u.from_drop = false
	u.to_store = false
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
		Unit.Task.HARVEST:
			return "h%d" % u.target.x
		Unit.Task.EAT:
			if u.project_id == EAT_BUSH:
				return "e%d" % u.target.x
		Unit.Task.FISH:
			if u.project_id == 0:
				return "f%d,%d" % [u.target.x, u.target.y]
	return null


## Порядок занятий жителя: сначала его профессия, затем общая очередь.
## Порядок дел. Назначенный — сначала своё место работы. Остальное — только нужное
## колонии: стройки (копка, укрепление, стройка, доставка материалов) и сбор по нужде
## (не хватает материалов на стройку, нечего есть). Сами по себе свободные жители не
## рубят, не ловят рыбу, не фермерствуют и ничего не носят на хранение.
func _task_order(u: Unit) -> Array[String]:
	# need — добыть то, чего не хватает стройке: это тоже стройка, она важнее переноски.
	if u.workplace != 0:
		return ["workplace", "projects", "need", "haul"]
	if u.profession == Unit.Prof.HAULER:
		return ["haul", "projects", "need"]
	# Шахтёры — сначала в шахты, строители — сначала на остальные стройки.
	# Шахтёр только копает: сначала шахты, потом копка на других стройках.
	if u.profession == Unit.Prof.MINER:
		return ["mines", "projects"]
	if u.profession == Unit.Prof.BUILDER:
		return ["builds", "projects", "need"]
	# Строители и свободные: сначала стройка, потом переноска.
	return ["projects", "need", "haul"]


## Ищет занятие для жителя. true — назначено.
func _assign(u: Unit) -> bool:
	var reach := pathing.explore(u.cell())
	var parents: Dictionary = reach[0]
	var dist: Dictionary = reach[1]
	if u.energy < TIRED or (is_night() and u.energy < NIGHT_SLEEP):
		_start_sleep(u, parents, dist)
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
	return false


## Стройки: копка, расчистка, укрепление, стройка, обустройство, ремонт, доставка материалов.
## Назначенный строитель, если места заняты свободными, занимает место одного из них.
## only — только стройки этого вида, skip — кроме этого вида. Шахтёр вытесняет свободного
## из шахты, строитель — с остальных строек.
func _try_projects(u: Unit, parents: Dictionary, dist: Dictionary, only := -1, skip := -1) -> bool:
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
			continue
		if (only >= 0 and p.kind != only) or (skip >= 0 and p.kind == skip):
			continue
		var mine := p.kind == Project.Kind.MINE
		var priority := (u.profession == Unit.Prof.MINER and mine) or (u.profession == Unit.Prof.BUILDER and not mine)
		if workers_on(p) >= p.workers and not (priority and _bump_free_worker(p)):
			continue
		# Шахтёр в шахте копает и ставит крепь, а дерево на крепь носит сам, только если
		# нет свободных подсобных. На других стройках — только копает.
		if u.profession == Unit.Prof.MINER and u.workplace == 0:
			if p.phase == Project.Phase.DIG:
				if mine and _try_support(u, p, parents, dist):
					return true
				if _try_dig(u, p, parents, dist):
					return true
			if mine and not free_hauler_exists() and _try_haul(u, p, parents, dist, true):
				return true
			continue
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
		# материалы на оплату этапа), и ровно столько.
		if builder_or_miner(u):
			if u.profession == Unit.Prof.BUILDER and _try_haul(u, p, parents, dist, true):
				return true
		elif (not mine or mine_hauler(u)) and _try_haul(u, p, parents, dist):
			return true
	return false


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
	u.path = Pathing.path_to(parents, stand)
	u.path_i = 0
	u.work_t = 0.0
	u.state = Unit.State.MOVE
	var key = _reserve_key(u)
	if key != null:
		reserved[key] = u.id


func _start_sleep(u: Unit, parents: Dictionary, dist: Dictionary) -> void:
	_claim_bed(u)
	var room := project_by_id(u.bed_room)
	if room != null:
		var bed := bed_cell(room, u.bed_index)
		if dist.has(bed):
			_start(u, Unit.Task.SLEEP, bed, bed, room.id, parents)
			return
	# Кровати нет или до неё не добраться — спит где стоит.
	_start(u, Unit.Task.SLEEP, u.cell(), u.cell(), 0, parents)


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
		if drop_amount(c, "food") + drop_amount(c, "berries") <= 0:
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


## Откуда житель может работать с клеткой c: стоя рядом (ноги или голова у клетки).
func _work_spot(c: Vector2i, dist: Dictionary) -> Array:
	var best := [null, 1 << 30]
	for d in DIRS4:
		var n := c + d
		for stand in [n, n + Vector2i(0, 1)]:
			if dist.has(stand) and dist[stand] < best[1]:
				best = [stand, dist[stand]]
	return best


func _try_dig(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
	var best_cell = null
	var best_stand = null
	var best_d := 1 << 30
	var any_free := false
	var now := diggable_now(p)
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
			if reserved.has(c) or now.has(c):
				continue
			any_free = true
			var spot := _work_spot(c, dist)
			if spot[0] != null and spot[1] < best_d:
				best_d = spot[1]
				best_cell = c
				best_stand = spot[0]
	if best_cell == null:
		# «Нет доступа» — только если к стройке вообще никто не подобрался.
		if any_free and workers_on(p) == 0 and p.blocked.is_empty():
			p.blocked = "Нет доступа — проложите тоннель к стройке"
		return false
	if p.blocked.begins_with("Нет доступа"):
		p.blocked = ""
	if _hazard_stop(p, best_cell):
		return false
	_start(u, Unit.Task.DIG, best_cell, best_stand, p.id, parents)
	return true


## Тупик: начатый срез не докопать — к его клеткам не подойти никому (и их никто не копает).
func _dig_deadlock(now: Array[Vector2i]) -> bool:
	if now.is_empty():
		return false
	for c in now:
		if reserved.has(c):
			return false
	for c in now:
		can_reach(Rect2i(c, Vector2i.ONE))
		for dist in _reach_cache:
			if _work_spot(c, dist)[0] != null:
				return false
	return true


## Геолог чует скрытую опасность рядом с забоем: бригада останавливается и ждёт решения.
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
					kind = "water"
				Mat.MAGMA:
					kind = "magma"
				Mat.GAS_POCKET:
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


## Крепь выкопанного среза: житель встаёт в срезе или рядом.
func _try_support(u: Unit, p: Project, parents: Dictionary, dist: Dictionary) -> bool:
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
	return true


func _try_build(u: Unit, p: Project, task: int, parents: Dictionary, dist: Dictionary) -> bool:
	var best = _near_rect(p.rect, dist)
	if best == null:
		return false
	_start(u, task, p.rect.get_center(), best, p.id, parents)
	return true


## Ближайшая доступная клетка в зоне или вплотную к ней (или null).
func _near_rect(r: Rect2i, dist: Dictionary) -> Variant:
	var area := r.grow(1)
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
	for x in (only if pid != 0 else world.feature_marks.keys()):
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
		for dx in range(3, 6):
			out.append(_ground_cell(home.x + dx))
		return out
	for room in holders(key):
		if held_in(room, key) > 0 and RoomType.is_store(room.purpose):
			for x in range(RoomType.floor_start(room), room.rect.end.x):
				out.append(Vector2i(x, room.rect.end.y - 1))
	if base_have(key) > 0 or out.is_empty():
		for dx in range(-8, -1):
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
## оффлайн жители успевают всё перетаскать — сразу на склад.
## site — стройка, на которой добыто (расчистка, копка): что ей нужно, остаётся
## на месте и сразу идёт в её материалы; на склад уносят только излишек.
func drop_item(c: Vector2i, key: String, n: int, site: Project = null) -> void:
	if key.is_empty() or n <= 0:
		return
	known_resources[key] = true
	if site != null:
		var use := mini(n, int(remaining(site).get(key, 0)))
		if use > 0:
			site.delivered[key] = site.delivered.get(key, 0) + use
			n -= use
			if n <= 0:
				return
	# Без игрока жители успевают донести — но только туда, где есть работник склада.
	if RoomType.BULK.has(key) or (offline and can_store(key)):
		_add(key, n)
		return
	var spot := _landing(c)
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


func drop_amount(c: Vector2i, key: String) -> int:
	return int(drops.get(c, {}).get(key, 0))


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
func _haul_source(key: String, dist: Dictionary) -> Array:
	var best := [null, null, 0]
	var best_d := 1 << 30
	var store: int = inventory.get(key, 0) - _claimed(key)
	if store > 0:
		var s = _source_spot(key, dist)
		if s != null:
			best = [s, null, store]
			best_d = dist[s]
	for c: Vector2i in drops:
		var avail := drop_amount(c, key) - _claimed_drop(c, key)
		if avail <= 0:
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


## Ближайшая к жителю клетка пола комнаты.
func _room_stand(room: Project, dist: Dictionary) -> Variant:
	var best = null
	for x in range(RoomType.floor_start(room), room.rect.end.x):
		var c := Vector2i(x, room.rect.end.y - 1)
		if dist.has(c) and (best == null or dist[c] < dist[best]):
			best = c
	return best


## Склад (амбар) принимает добро, только когда на него назначен работник.
func store_staffed(room: Project) -> bool:
	return not room.paused and not assigned_to(room).is_empty()


## Есть ли куда нести ресурс: склад или амбар для него с назначенным работником.
func can_store(key: String) -> bool:
	for room in store_rooms():
		if RoomType.stores(room, key) and store_staffed(room):
			return true
	return false


## Свободный житель уносит лежащее на земле на склад (если там есть место).
func _try_cleanup(u: Unit, parents: Dictionary, dist: Dictionary, only: Project = null, mines_only := false) -> bool:
	var may_mine := mine_hauler(u)
	var best = null
	var best_c := Vector2i.ZERO
	var best_k := ""
	var best_n := 0
	var best_d := 1 << 30
	var best_room: Project = null
	for c: Vector2i in drops:
		var stand = _drop_stand(c, dist)
		if stand == null or dist[stand] >= best_d:
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
			var avail := drop_amount(c, k) - _claimed_drop(c, k)
			if avail <= 0:
				continue
			var to = _store_target(k, dist, only)
			if to == null:
				continue
			best = stand
			best_c = c
			best_k = k
			best_room = to[1]
			best_n = mini(carry_cap(), mini(avail, room_free(to[1], k)))
			best_d = dist[stand]
			break
	if best == null:
		return false
	u.carry_key = best_k
	u.carry_amount = best_n
	u.haul_stage = 0
	u.from_drop = true
	u.haul_src = best_c
	u.to_store = true
	_start(u, Unit.Task.HAUL, best, best, best_room.id, parents)
	return true


## Житель берёт ресурс с кучи c (рядом с ним) и несёт на склад.
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
	var left := remaining(p)
	if now_only:
		# Только то, что нужно прямо сейчас и ещё не принесено и не несут.
		var now := _needed_now(p)
		left = {}
		for k in now:
			var n: int = now[k] - int(p.delivered.get(k, 0)) - in_transit(p, k)
			if n > 0:
				left[k] = n
	if left.is_empty() or _near_rect(p.rect, dist) == null:
		return false
	# Сначала то, без чего стройка стоит прямо сейчас.
	var keys := left.keys()
	var now := _needed_now(p)
	keys.sort_custom(func(a: String, b: String) -> bool: return now.has(a) and not now.has(b))
	for k in keys:
		var src := _haul_source(k, dist)
		if src[0] == null:
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
	for p in projects:
		if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
			continue
		if p.kind == Project.Kind.MINE and not mine_hauler(u):
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
	var need: Dictionary = RoomType.RECIPES[p.purpose][0]
	for k in need:
		var want: int = need[k] * SUPPLY_CYCLES - p.stock.get(k, 0) - _incoming_to(p, k)
		if want <= 0:
			continue
		var src := _haul_source(k, dist)
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
				var src := _haul_source(k, dist)
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


## Строитель пришёл, а все места на стройке заняты свободными — один из них уступает.
func _bump_free_worker(p: Project) -> bool:
	for o in units:
		if o.project_id == p.id and is_free(o) and o.task not in [Unit.Task.SLEEP, Unit.Task.EAT, Unit.Task.HAUL]:
			_drop(o)
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


## Житель у склада или кучи: берёт ресурс и несёт к стройке или на склад.
func _haul_pickup(u: Unit) -> void:
	var p := project_by_id(u.project_id)
	if p == null and not u.to_store:
		_drop(u)
		return
	var take := 0
	if u.from_drop:
		take = _take_drop(u.haul_src, u.carry_key, u.carry_amount)
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
	u.carry_amount = take
	u.haul_stage = 1
	var reach := pathing.explore(u.cell())
	var stand = null
	if u.to_store:
		# Несёт в тот склад, куда собирался; там уже нет места — в ближайший другой.
		if p != null and RoomType.is_store(p.purpose) and store_staffed(p):
			stand = _room_stand(p, reach[1])
		if stand == null:
			var to = _store_target(u.carry_key, reach[1])
			if to != null:
				stand = to[0]
				u.project_id = to[1].id
	else:
		stand = _near_rect(p.rect, reach[1])
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
	u.path = Pathing.path_to(reach[0], stand)
	u.path_i = 0
	u.state = Unit.State.MOVE


## Житель донёс груз: на стройку — в её запас, на склад — в общий.
func _haul_deliver(u: Unit) -> void:
	var p := project_by_id(u.project_id)
	var k := u.carry_key
	var n := u.carry_amount
	var to_storage := u.gather_room != 0 or u.to_store
	var spot := u.cell()
	u.carry_amount = 0
	_drop(u)
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


## Житель с добычей идёт на склад room_id.
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
	u.path = Pathing.path_to(reach[0], stand)
	u.path_i = 0
	u.work_t = 0.0
	u.state = Unit.State.MOVE


# --- Склад: жители сами добывают ресурсы до нормы -----------------------------------------

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


## Подходит ли объект для добычи жителями склада (метка игрока не нужна).
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
		if not _gather_ok(x, kind):
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


## Рядом не осталось чего добыть — житель идёт по поверхности к краю разведанного:
## дальше могут быть деревья, валуны и кусты. Не чаще раза в SCOUT_EVERY секунд.
func _try_scout(u: Unit, parents: Dictionary, dist: Dictionary, key: String) -> bool:
	if game_time - _scout_at < SCOUT_EVERY:
		return false
	var best = null
	var best_d := 1 << 30
	for c: Vector2i in dist:
		var s := world.gen.surface_y(c.x)
		if c.y >= s or c.y < s - 3 or (c.x < explored_max - 8 and c.x > explored_min + 8):
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


## Стройке не хватает дерева, камня или еды нет совсем — жители сами отмечают
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
		var ux := u.cell().x
		var best_x = null
		var best_d := 1 << 30
		for x in range(maxi(explored_min, ux - Pathing.MAX_RADIUS), mini(explored_max, ux + Pathing.MAX_RADIUS) + 1):
			if world.feature_marks.has(x) or not _gather_ok(x, kind):
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
		var t := Env.temperature(c.y, world.gen.surface_y(c.x))
		if m != "stone" and t > 40.0:
			years /= 1.0 + (t - 40.0) / 60.0
	if research.has("maintenance"):
		years /= 0.7
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


func _cancel_repair(p: Project) -> void:
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


## Постройка рухнула: обломки, травмы, падают верхние этажи, порода может обвалиться.
func collapse(p: Project, why: String) -> void:
	if not projects.has(p):
		return
	_log("ОБРУШЕНИЕ: %s (%s)" % [p.title(), why], "danger")
	_return_delivered(p)
	_release_beds(p)
	projects.erase(p)
	for c in p.cells():
		room_cells.erase(c)
		interior.erase(c)
		deck.erase(c)
		world.dirty[WorldData.chunk_of(c.x, c.y)] = true
	_restore_water_overlaps(p)
	for u in units:
		if u.project_id == p.id:
			_drop(u)
	for u: Unit in units.duplicate():
		var c := u.cell()
		if not (p.rect.has_point(c) or p.rect.has_point(c + Vector2i(0, -1))):
			continue
		if p.is_water_structure():
			# Настил рухнул в воду — житель выбирается на берег.
			u.pos = Vector2(_ground_cell(p.rect.position.x - 1))
			u.state = Unit.State.IDLE
			injure(u, 10.0, "упал в воду с рухнувшего настила")
			continue
		injure(u, 40.0, "завалило обломками")
	if p.kind == Project.Kind.ROOM:
		# Стены и перекрытия ложатся обломками на пол.
		var floor_y := p.rect.end.y - 1
		for x in range(p.rect.position.x, p.rect.end.x):
			if world.get_mat(x, floor_y) == Mat.AIR:
				world.set_material(x, floor_y, Mat.RUBBLE)
		for u in units:
			if u.cell().y == floor_y and p.rect.has_point(u.cell()):
				u.pos.y = floor_y - 1
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


func _room_supported(q: Project) -> bool:
	for x in range(q.rect.position.x, q.rect.end.x):
		var below := Vector2i(x, q.rect.end.y)
		if not interior.has(below) and not Mat.is_solid(world.get_mat(below.x, below.y)):
			return false
	return true


# --- Экономика: мастерские, наука, энергия --------------------------------------------

## Хватает ли сырья на цикл мастерской.
## Сколько сырья k есть у мастерской: принесённое; без игрока жители берут и со склада.
func _input_have(p: Project, k: String) -> int:
	return p.stock.get(k, 0) + (inventory.get(k, 0) if offline else 0)


func has_inputs(p: Project) -> bool:
	if not RoomType.RECIPES.has(p.purpose):
		return false
	var need: Dictionary = RoomType.RECIPES[p.purpose][0]
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
	if not RoomType.RECIPES.has(p.purpose):
		return out
	var need: Dictionary = RoomType.RECIPES[p.purpose][0]
	for k in need:
		if _input_have(p, k) < need[k]:
			out[k] = need[k]
	if RoomType.FUELED.has(p.purpose) and fuel_have(p) < 1.0:
		out["wood"] = 1
	return out


## Готовая продукция: при игроке — кучей на полу мастерской (её уносят подсобные),
## без игрока — сразу на склад (если на нём есть работник).
func _produce(p: Project, k: String, n: int) -> void:
	drop_item(Vector2i(RoomType.floor_start(p), p.rect.end.y - 1), k, n)


func _craft(p: Project) -> void:
	if not has_inputs(p):
		return
	var recipe: Array = RoomType.RECIPES[p.purpose]
	for k in recipe[0]:
		var from_stock := mini(p.stock.get(k, 0), recipe[0][k])
		p.stock[k] = p.stock.get(k, 0) - from_stock
		_remove(k, recipe[0][k] - from_stock)
	if RoomType.FUELED.has(p.purpose):
		_burn_fuel(p)
	for k in recipe[1]:
		_produce(p, k, recipe[1][k])


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


func _research(work: float) -> void:
	var lab_power := 1.0 + 0.5 * power_ratio if research.has("electricity") and power_made > 0 else 1.0
	var finished := research.add(work * Research.POINTS_PER_SEC * lab_power)
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
	var k := 1.25 if research.has("agronomy") else 1.0
	return k * (1.0 + 0.5 * power_ratio if research.has("hydroponics") and powered() else 1.0)


func dig_bonus() -> float:
	if research.has("deep_drilling"):
		return 2.0
	return 1.5 if research.has("drilling") else 1.0


func build_bonus() -> float:
	return 1.5 if research.has("carpentry") else 1.0


func automation_bonus() -> float:
	return 1.5 if research.has("automation") else 1.0


## Сколько житель уносит за раз.
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


## Очаги: жгут дрова, пока вокруг холодно; без дров гаснут.
func _hearth_tick(dt: float) -> void:
	for p in rooms_of(RoomType.HEARTH):
		var was := p.burning
		p.burning = false
		if p.paused:
			continue
		# Холодно ли без огня (своё тепло не считаем).
		var c := p.rect.get_center()
		var cold := Env.temperature(c.y, world.gen.surface_y(c.x), season_delta()) < HEARTH_ON_BELOW
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
		# Газовый жжёт только метан из баков дегазации, обычный — уголь, а без него дрова.
		var gas := p.purpose == RoomType.GAS_GEN
		if p.farm_progress <= 0.0:
			if gas:
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
			power_made += roundi(RoomType.POWER_MAKE * (1.5 if research.has("steam") else 1.0))
			if p.blocked.begins_with("Нет топлива") or p.blocked.begins_with("Нет метана"):
				p.blocked = ""
		elif p.blocked.is_empty():
			p.blocked = "Нет метана: нужна дегазация с газом в баке" if gas else "Нет топлива: нужен уголь или дрова"
			_log("%s: %s" % [p.title(), p.blocked], "warning")
	_hearth_tick(dt)
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
	return season() == Season.WINTER


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
					_log("Пришла зима: ягоды не растут, озёра замёрзли — рыба только с пристани, вдвое медленнее. Фермам и жителям нужно тепло — очаг", "warning")
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


## Ниже какой температуры жителю холодно: синим и пушистым — ниже, красным — выше.
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

## Упрощённая модель: жители не ходят, а сразу работают с меньшей эффективностью
## (часть времени уходит на сон и еду). Возвращает число выкопанных клеток.
func advance_offline(dt: float) -> int:
	offline = true
	_sync_held()
	for u in units:
		_drop(u)
	# Пока игрока нет, жители перетаскивают добытое на склад.
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
		# цель -> [вид, суммарная скорость, первый житель, проект]
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
		_power_tick(step)
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
					p.farm_progress += j[1] * step
					var need: float = RoomType.RECIPES[p.purpose][2]
					while p.farm_progress >= need and has_inputs(p):
						p.farm_progress -= need
						_craft(p)
					p.farm_progress = minf(p.farm_progress, need)
				Unit.Task.RESEARCH:
					_research(j[1] * step)
				Unit.Task.FARM:
					var p: Project = j[3]
					p.farm_progress += j[1] * step * farm_bonus()
					while p.farm_progress >= RoomType.FARM_CYCLE:
						p.farm_progress -= RoomType.FARM_CYCLE
						_add("food", 1)
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
		RoomType.KILN, RoomType.FORGE:
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
	var out: Array[Project] = []
	for p in store_rooms():
		if RoomType.stores(p, key):
			out.append(p)
	return out


## Сколько ресурса помещается в комнате p.
func room_cap(p: Project, key: String) -> int:
	if key == "methane":
		return RoomType.GAS_PER_CELL * RoomType.usable_width(p) if p.purpose == RoomType.DEGAS else 0
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
	return 0 if key == "methane" else RoomType.BASE_CAPACITY


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
		if k == "methane" and extra > 0:
			inventory[k] = int(inventory[k]) - extra


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
			if key != "methane" and not store_staffed(p):
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
	if put < amount and not _full_warned.has(key) and key != "methane":
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
	# Груз в руках жителей сохраняем как запас склада.
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
	for pd in d.get("projects", []):
		var p := Project.from_dict(pd)
		projects.append(p)
		# Старые сохранения: нормы были у каждого склада — берём наибольшую.
		if not d.has("store_targets"):
			for k in p.targets:
				store_targets[k] = maxi(int(store_targets.get(k, 0)), int(p.targets[k]))
		_register_room(p)
		if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
			for c in p.cells():
				interior[c] = p.id
		_register_deck(p)
	_rebuild_climb()
	for ud in d.get("units", []):
		var u := Unit.from_dict(ud)
		if u.genome.is_empty():
			# Старое сохранение: жителям — гены основателей, пол прежний.
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
	loads.loads = loads.compute()
	explore()
	_refresh_bushes()
