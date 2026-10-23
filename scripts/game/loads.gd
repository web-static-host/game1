class_name Loads
extends RefCounted
## Нагрузки на постройки:
## - вес: комната давит на те, что под ней (пропорционально опоре); стены держат
##   столько тонн на метр ширины, сколько позволяет материал, ветхие — меньше;
## - ветер: высокая наземная башня на узком основании опрокидывается;
## - бури изнашивают наземные постройки, землетрясения — всё, перегруженное рушится.
## Бури и землетрясения очень редки, бывают только при игроке (перед толчками земля дрожит)
## и отключаются галочкой «Стихийные бедствия» при создании новой игры.

## Масса стен и перекрытий на клетку комнаты, т.
const MASS := {"wood": 0.6, "stone": 2.2, "brick": 1.8, "iron": 1.2}
## Сколько тонн сверху держит метр ширины стен.
const BEARING := {"wood": 2.5, "stone": 28.0, "brick": 18.0, "iron": 40.0}
## Во сколько раз наземная башня может быть выше ширины основания.
const SLENDER := {"wood": 3.0, "stone": 6.0, "brick": 5.0, "iron": 10.0}
## Интервалы в секундах игры: буря — раз в 4–10 часов, землетрясение — раз в 12–30 часов.
const STORM_EVERY := Vector2(4.0 * 3600.0, 10.0 * 3600.0)
const STORM_LONG := Vector2(60.0, 120.0)
const QUAKE_EVERY := Vector2(12.0 * 3600.0, 30.0 * 3600.0)
const FORESHOCK := 20.0

var colony: Colony
var world: WorldData
## Нагрузка сверху на комнаты: id -> т (пересчитывается раз в секунду).
var loads := {}
var storm_t := 0.0
var storm_left := 0.0
var storm_power := 0
var quake_t := 0.0
var _foreshock_done := false
var _tick := 0.0
## Сколько секунд комната перегружена: id -> сек. Через минуту — рушится.
var overload_t := {}
const OVERLOAD_GRACE := 60.0
var _rng := RandomNumberGenerator.new()


func _init(p_colony: Colony) -> void:
	colony = p_colony
	world = p_colony.world
	_rng.seed = world.gen.world_seed + 4242
	storm_t = _rng.randf_range(STORM_EVERY.x, STORM_EVERY.y)
	quake_t = _rng.randf_range(QUAKE_EVERY.x, QUAKE_EVERY.y)


static func mass(p: Project) -> float:
	return MASS.get(p.material, 0.6) * p.area()


## Сколько тонн сверху держит комната (ветхая — меньше).
static func bearing(p: Project) -> float:
	return BEARING.get(p.material, 2.5) * p.rect.size.x * (1.0 - 0.4 * p.wear)


## Комнаты, которые несут вес (готовые и строящиеся сверху).
func _rooms(extra: Project) -> Array[Project]:
	var out: Array[Project] = []
	for p in colony.projects:
		if p.kind == Project.Kind.ROOM and p.phase != Project.Phase.DIG:
			out.append(p)
	if extra != null:
		out.append(extra)
	return out


## Вес сверху на каждую комнату: id -> т. extra — проверяемая будущая комната.
func compute(extra: Project = null) -> Dictionary:
	var rooms := _rooms(extra)
	# Сверху вниз: верхние передают вес нижним по ширине опоры.
	rooms.sort_custom(func(a: Project, b: Project) -> bool: return a.rect.position.y < b.rect.position.y)
	var out := {}
	for q in rooms:
		var total := mass(q) + float(out.get(q.id, 0.0))
		for p in rooms:
			if p == q or p.rect.position.y != q.rect.end.y:
				continue
			var overlap := mini(p.rect.end.x, q.rect.end.x) - maxi(p.rect.position.x, q.rect.position.x)
			if overlap > 0:
				out[p.id] = float(out.get(p.id, 0.0)) + total * overlap / q.rect.size.x
	return out


func load_on(p: Project) -> float:
	return float(loads.get(p.id, 0.0))


## Доля использованной прочности (больше 1 — не держит).
func utilization(p: Project, from: Dictionary = loads) -> float:
	if p.kind != Project.Kind.ROOM:
		return 0.0
	return float(from.get(p.id, 0.0)) / maxf(0.1, bearing(p))


## Почему нельзя поставить комнату r из материала mat (пусто — можно).
func room_error(r: Rect2i, mat: String) -> String:
	var tmp := Project.new()
	tmp.id = -1
	tmp.kind = Project.Kind.ROOM
	tmp.rect = r
	tmp.material = mat
	var predicted := compute(tmp)
	# Сама новая комната: если над ней уже стоят этажи, их вес ляжет на неё.
	if utilization(tmp, predicted) > 1.0:
		return "Эта комната не выдержит: сверху будет %d т, а стены из «%s» держат %d т — выберите материал прочнее" % [
			roundi(predicted[-1]), Project.MATERIALS.get(mat, ["?"])[0].to_lower(), roundi(bearing(tmp))]
	for p in colony.projects:
		if p.kind == Project.Kind.ROOM and utilization(p, predicted) > 1.0:
			return "%s не выдержит: сверху будет %d т, держит %d т — стройте легче или внизу прочнее" % [
				p.title(), roundi(predicted[p.id]), roundi(bearing(p))]
	var tower := tower_of(r, mat)
	if tower[0] > tower[1] * SLENDER.get(tower[2], 3.0):
		return "Башня %d м на основании %d м опрокинется от ветра (из «%s» — не выше %d м). Расширьте основание" % [
			tower[0], tower[1], Project.MATERIALS.get(tower[2], ["?"])[0].to_lower(), int(tower[1] * SLENDER.get(tower[2], 3.0))]
	return ""


## Наземная башня под комнатой r: [высота над землёй, ширина основания, материал основания].
func tower_of(r: Rect2i, mat: String) -> Array:
	var base_rect := r
	var base_mat := mat
	var guard := 0
	while guard < 200:
		guard += 1
		var below := colony.rooms_below(base_rect)
		if below.is_empty():
			break
		var best: Project = below[0]
		for b in below:
			if b.rect.size.x > best.rect.size.x:
				best = b
		base_rect = best.rect
		base_mat = best.material
	var ground := world.gen.surface_y(base_rect.get_center().x)
	var height := maxi(0, mini(ground, base_rect.end.y) - r.position.y)
	return [height, base_rect.size.x, base_mat]


## Скорость ветра на высоте h м над землёй, м/с (в бурю — сильнее).
func wind(h: float) -> float:
	var v := 6.0 * pow(1.0 + maxf(0.0, h) / 10.0, 0.3)
	return v * (1.0 + storm_power * 0.8) if storm_left > 0.0 else v


func update(dt: float) -> void:
	_tick += dt
	if _tick >= 1.0:
		_tick = 0.0
		loads = compute()
		_check_overload()
	if colony.disasters:
		_storms(dt)
		_quakes(dt)


## Перегруженная (например, обветшавшая) комната: предупреждение, через минуту — обрушение.
func _check_overload() -> void:
	for p: Project in colony.projects.duplicate():
		if not colony.projects.has(p) or p.kind != Project.Kind.ROOM:
			continue
		if utilization(p) <= 1.0:
			overload_t.erase(p.id)
			continue
		var t: float = overload_t.get(p.id, 0.0)
		if t == 0.0:
			colony._log("%s перегружена (%d т при допустимых %d т) и трещит! Разгрузите — снесите верхний этаж или отремонтируйте" % [
				p.title(), roundi(load_on(p)), roundi(bearing(p))], "danger")
		overload_t[p.id] = t + 1.0
		if t + 1.0 >= OVERLOAD_GRACE:
			overload_t.erase(p.id)
			colony.collapse(p, "не выдержала вес верхних этажей")
			loads = compute()


func _storms(dt: float) -> void:
	if storm_left > 0.0:
		storm_left -= dt
		for p in colony.projects:
			if p.phase != Project.Phase.DONE or colony.is_underground(p):
				continue
			var h := world.gen.surface_y(p.rect.get_center().x) - p.rect.position.y
			p.wear = minf(0.999, p.wear + dt / (Colony.YEAR * 0.25) * storm_power * (1.0 + maxf(0.0, h) / 10.0))
		if storm_left <= 0.0:
			colony._log("Буря стихла", "info")
		return
	storm_t -= dt
	if storm_t <= 0.0:
		storm_t = _rng.randf_range(STORM_EVERY.x, STORM_EVERY.y)
		storm_left = _rng.randf_range(STORM_LONG.x, STORM_LONG.y)
		storm_power = 1 + int(_rng.randf() * _rng.randf() * 3.0)
		colony._log("Буря: ветер до %d м/с — наземные постройки быстрее ветшают" % roundi(wind(10.0)), "warning")


func _quakes(dt: float) -> void:
	# Чем глубже колония, тем ближе к разломам: толчки чаще.
	quake_t -= dt * (1.0 + maxf(0.0, colony.deepest_y - colony.home.y) / 5000.0)
	if quake_t <= FORESHOCK and not _foreshock_done:
		_foreshock_done = true
		colony._log("Земля дрожит — возможны толчки. Уведите гавриков из шатких выработок", "warning")
	if quake_t > 0.0:
		return
	quake_t = _rng.randf_range(QUAKE_EVERY.x, QUAKE_EVERY.y)
	_foreshock_done = false
	quake(1 + int(_rng.randf() * _rng.randf() * 3.0))


## Землетрясение силой mag (1–3): износ, рушится перегруженное, сыпется порода.
func quake(mag: int) -> void:
	colony._log("ЗЕМЛЕТРЯСЕНИЕ, сила %d!" % mag, "danger")
	colony.quaked.emit(mag)
	loads = compute()
	for p: Project in colony.projects.duplicate():
		if not colony.projects.has(p):
			continue
		if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
			var u := utilization(p)
			p.wear = minf(0.999, p.wear + 0.02 * mag * (1.0 + u))
			if u * (1.0 + 0.15 * mag) > 1.0:
				colony.collapse(p, "не выдержала толчков")
	# Своды выработок на пределе прочности не выдерживают тряски.
	colony.quake_factor = 1.0 - 0.12 * mag
	var cells: Array[Vector2i] = []
	for p in colony.projects:
		var area := p.rect.grow(2)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				cells.append(Vector2i(x, y))
	colony.physics.check_area(cells)
	colony.quake_factor = 1.0
	loads = compute()


func to_dict() -> Dictionary:
	return {"storm_t": storm_t, "storm_left": storm_left, "storm_power": storm_power, "quake_t": quake_t}


func load_dict(d: Dictionary) -> void:
	storm_t = float(d.get("storm_t", storm_t))
	storm_left = float(d.get("storm_left", 0.0))
	storm_power = int(d.get("storm_power", 0))
	quake_t = float(d.get("quake_t", quake_t))
