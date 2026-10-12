extends Node2D
## Точка входа: собирает мир, колонию, камеру, интерфейс; режимы стройки,
## сохранение и оффлайн-прогресс.

const AUTOSAVE_SEC := 30.0
## Сколько времени отсутствия засчитывается (стимул заходить регулярно).
const OFFLINE_CAP_SEC := 3.0 * 3600.0
const SPEEDS := [1.0, 10.0, 100.0]
const STATUS_INTERVAL := 0.2

var world: WorldData
var colony: Colony
var world_view: WorldView
var camera: CameraController
var hud: Hud
var mode := Hud.Mode.LOOK
var _sky: ColorRect
var _speed_idx := 0
var _autosave := 0.0
var _status_timer := 0.0
var _home := Vector2i.ZERO
var _paused_at := 0.0
var _drag_start := Vector2i.ZERO
var _pending := Rect2i()
var _pending_kind := 0
## Что показано в информационной панели: [вид, id] — чтобы обновлять текст.
var _info_target := []


func _ready() -> void:
	var data := SaveSystem.load_data()
	var seed_value := int(data["seed"]) if data.has("seed") else _new_seed()
	world = WorldData.new(WorldGen.new(seed_value))
	colony = Colony.new(world)
	_home = Vector2i(0, world.gen.surface_y(0))
	_build_scene()
	colony.event_logged.connect(hud.log_event)

	var start := _home + Vector2i(0, -3)
	if data.is_empty():
		colony.start_new(_home.x)
		hud.log_event("У вас 5 жителей, немного дерева и камня. Заложите тоннель или комнату, деревья и валуны отметьте в «Сборе».", "info")
	else:
		SaveSystem.apply(data, world, colony)
		var cam: Array = data.get("camera", [])
		if cam.size() == 2:
			start = Vector2i(int(cam[0]), int(cam[1]))
		_apply_offline(float(data.get("saved_at", 0.0)))
	world_view.focus_cell(start)
	_update_status()


func _new_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7FFFFFFF


func _build_scene() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	_sky = ColorRect.new()
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	_sky.material = mat
	sky_layer.add_child(_sky)

	camera = CameraController.new()
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)
	camera.make_current()

	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(world, colony, camera)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = Hud.new()
	ui_layer.add_child(hud)

	camera.tapped.connect(_on_tap)
	camera.painted.connect(_on_paint)
	camera.paint_ended.connect(_on_paint_end)
	camera.paint_cancelled.connect(_clear_preview)
	hud.mode_changed.connect(_set_mode)
	hud.home_pressed.connect(func() -> void: world_view.focus_cell(_home + Vector2i(0, -3)))
	hud.speed_pressed.connect(_cycle_speed)


func _process(delta: float) -> void:
	# Большие паузы (сворачивание) учитываются как оффлайн, а не через delta.
	var dt := minf(delta, 0.25)
	colony.update(dt * SPEEDS[_speed_idx])
	_update_sky()
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = STATUS_INTERVAL
		_update_status()
		_refresh_info()
	_autosave += delta
	if _autosave >= AUTOSAVE_SEC:
		_autosave = 0.0
		_save()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if world != null:
				_save()
				_paused_at = Time.get_unix_time_from_system()
		NOTIFICATION_APPLICATION_RESUMED:
			if world != null and _paused_at > 0.0:
				_apply_offline(_paused_at)
				_paused_at = 0.0
		NOTIFICATION_WM_CLOSE_REQUEST:
			if world != null:
				_save()


func _save() -> void:
	SaveSystem.save(world, colony, world_view.camera_cell())


func _apply_offline(since_unix: float) -> void:
	var away := Time.get_unix_time_from_system() - since_unix
	if since_unix <= 0.0 or away < 60.0:
		return
	var simulated := minf(away, OFFLINE_CAP_SEC)
	var inv_before := colony.inventory.duplicate()
	var built_before := _done_count()
	var dug := colony.advance_offline(simulated)
	var lines: PackedStringArray = ["Вас не было %s." % Fmt.duration(away)]
	if away > OFFLINE_CAP_SEC:
		lines.append("Жители работали первые %s — дальше им нужны ваши указания." % Fmt.duration(OFFLINE_CAP_SEC))
	var built := _done_count() - built_before
	if dug == 0 and built == 0 and inv_before == colony.inventory:
		lines.append("Работы стояли: нет заданий.")
	else:
		if dug > 0:
			lines.append("Выкопано клеток: %d." % dug)
		if built > 0:
			lines.append("Построено объектов: %d." % built)
		for k in colony.inventory:
			var gained: int = colony.inventory[k] - int(inv_before.get(k, 0))
			if gained > 0:
				lines.append("+%s %s" % [Fmt.int_spaced(gained), Mat.resource_name(k).to_lower()])
	hud.show_message("С возвращением!", "\n".join(lines))


func _done_count() -> int:
	var n := 0
	for p in colony.projects:
		if p.phase == Project.Phase.DONE:
			n += 1
	return n


func _cycle_speed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEEDS.size()
	hud.set_speed_text("×%d" % int(SPEEDS[_speed_idx]))


func _set_mode(m: int) -> void:
	mode = m
	camera.paint_mode = m == Hud.Mode.TUNNEL or m == Hud.Mode.ROOM
	_clear_preview()
	_select(null, null)


# --- Нажатия ---------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if mode == Hud.Mode.HARVEST:
		var x = _feature_near(c)
		if x == null:
			hud.log_event("Здесь нечего собирать — нажмите на дерево или валун.", "warning")
		else:
			colony.toggle_harvest(x)
		return
	var u := colony.unit_at(world_view.screen_to_world_cells(screen_pos))
	if u != null:
		_select(u, null)
		return
	var p := colony.project_at(c)
	if p != null:
		_select(null, p)
		return
	_select(null, null)
	hud.show_info(_cell_info(c))


## Столбец дерева/валуна рядом с нажатием (или null).
func _feature_near(c: Vector2i) -> Variant:
	for dx in [0, -1, 1]:
		var x: int = c.x + dx
		var f := world.feature_at(x)
		if f == WorldGen.FEATURE_NONE:
			continue
		var base := world.gen.surface_y(x) - 1
		var top := base - (world.gen.tree_height(x) + 1 if f == WorldGen.FEATURE_TREE else 1)
		if c.y >= top and c.y <= base + 1:
			return x
	return null


func _select(u: Unit, p: Project) -> void:
	world_view.units_layer.selected_unit = u.id if u != null else 0
	world_view.structures.selected_project = p.id if p != null else 0
	if u != null:
		_info_target = ["unit", u.id]
		hud.show_info(u.status_text())
	elif p != null:
		_info_target = ["project", p.id]
		_show_project(p)
	else:
		_info_target = []
		hud.hide_info()


func _show_project(p: Project) -> void:
	var actions := []
	if p.phase != Project.Phase.DONE:
		actions.append(["Продолжить" if p.paused else "Пауза", func() -> void:
			colony.set_paused(p, not p.paused)
			_show_project(p)])
		actions.append(["Отменить", func() -> void:
			colony.cancel_project(p)
			_select(null, null)])
	hud.show_info(_project_text(p), actions)


func _project_text(p: Project) -> String:
	var lines: PackedStringArray = [p.title() + " — " + ("на паузе" if p.paused else p.phase_name())]
	match p.phase:
		Project.Phase.DIG:
			lines.append("Этап 1 из 2: копка. Осталось клеток: %d" % colony.remaining_dig(p).size())
		Project.Phase.BUILD:
			var pct := int(100.0 * p.build_done / p.build_work()) if p.paid else 0
			lines.append("Этап 2 из 2: строительство %d%%" % pct)
	if p.phase != Project.Phase.DONE:
		lines.append("Материалы: " + _cost_text(p.cost()) + (" (оплачено)" if p.paid else ""))
	if not p.found.is_empty():
		var f: PackedStringArray = []
		for k in p.found:
			f.append("%s %d" % [Mat.resource_name(k).to_lower(), p.found[k]])
		lines.append("Найдено при копке: " + ", ".join(f))
	if not p.blocked.is_empty():
		lines.append("Внимание: " + p.blocked)
	return "\n".join(lines)


func _refresh_info() -> void:
	if _info_target.is_empty() or not hud.info_visible():
		return
	if _info_target[0] == "unit":
		for u in colony.units:
			if u.id == _info_target[1]:
				hud.update_info_text(u.status_text())
	elif _info_target[0] == "project":
		var p := colony.project_by_id(_info_target[1])
		if p == null:
			_select(null, null)
		else:
			hud.update_info_text(_project_text(p))


# --- Рамка стройки -------------------------------------------------------------------

func _on_paint(screen_pos: Vector2, first: bool) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if first:
		_drag_start = c
		hud.hide_info()
	var r := Rect2i(Vector2i(mini(c.x, _drag_start.x), mini(c.y, _drag_start.y)),
		(c - _drag_start).abs() + Vector2i.ONE)
	var kind := Project.Kind.ROOM if mode == Hud.Mode.ROOM else Project.Kind.TUNNEL
	var err := colony.validate(kind, r)
	var s := world_view.structures
	s.preview = r
	s.preview_ok = err.is_empty()
	s.preview_text = "%d×%d" % [r.size.x, r.size.y]


func _on_paint_end(_screen_pos: Vector2) -> void:
	var r := world_view.structures.preview
	if r.size == Vector2i.ZERO:
		return
	var kind := Project.Kind.ROOM if mode == Hud.Mode.ROOM else Project.Kind.TUNNEL
	var err := colony.validate(kind, r)
	if not err.is_empty():
		hud.log_event(err, "warning")
		_clear_preview()
		return
	_pending = r
	_pending_kind = kind
	var lines: PackedStringArray = ["%s %d×%d" % [Project.kind_name(kind), r.size.x, r.size.y]]
	lines.append("Материалы на 2-м этапе: " + _cost_text(Project.cost_for(kind, r)))
	lines.append("Сначала жители выкопают зону, потом построят.")
	hud.show_info("\n".join(lines), [
		["Построить", _confirm_pending],
		["Отмена", _clear_preview],
	])


func _confirm_pending() -> void:
	var p := colony.create_project(_pending_kind, _pending)
	_clear_preview()
	if p != null:
		hud.log_event("Заложено: %s" % p.title(), "info")


func _clear_preview() -> void:
	world_view.structures.preview = Rect2i()
	hud.hide_info()


func _cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		var have: int = colony.inventory.get(k, 0)
		parts.append("%s %d%s" % [Mat.resource_name(k).to_lower(), cost[k], "" if have >= cost[k] else " (есть %d)" % have])
	return ", ".join(parts)


# --- Информация -------------------------------------------------------------------

func _cell_info(c: Vector2i) -> String:
	var gen := world.gen
	var surf := gen.surface_y(c.x)
	var depth := c.y - surf
	var lines: PackedStringArray = []
	if depth < 0:
		lines.append("Высота %s м над уровнем моря · %s" % [Fmt.int_spaced(-c.y), gen.zone_name(c.x, c.y)])
	else:
		lines.append("Глубина %s м · %s" % [Fmt.int_spaced(depth), gen.zone_name(c.x, c.y)])
	if depth >= 0:
		if not world.is_revealed(c.x, c.y):
			lines.append("Неизвестно. Узнаем, когда раскопаем соседнюю клетку.")
		elif world.is_dug(c.x, c.y):
			lines.append("Выработка (раньше: %s)" % Mat.name_of(world.get_natural_mat(c.x, c.y)))
		else:
			var m := world.get_mat(c.x, c.y)
			lines.append(Mat.name_of(m))
			if Mat.is_diggable(m):
				lines.append("Плотность %s кг/м³ · прочность %s МПа · копать ~%s" % [
					Fmt.int_spaced(int(Mat.density(m))), str(Mat.strength(m)), Fmt.duration(colony.dig_time(c))])
	lines.append(_env_text(c))
	return "\n".join(lines)


func _env_text(c: Vector2i) -> String:
	var surf := world.gen.surface_y(c.x)
	return "%d °C · %d кПа · кислород %d%%" % [
		roundi(Env.temperature(c.y, surf)),
		roundi(Env.pressure(c.y, surf)),
		roundi(Env.oxygen_ratio(c.y, surf) * 100.0)]


func _update_status() -> void:
	var c := world_view.camera_cell()
	var surf := world.gen.surface_y(c.x)
	var depth := c.y - surf
	var where: String
	if depth < 0:
		where = "Высота %s м" % Fmt.int_spaced(-c.y)
	else:
		where = "Глубина %s м" % Fmt.int_spaced(depth)
	var busy := 0
	for u in colony.units:
		if u.task != Unit.Task.NONE:
			busy += 1
	var active := 0
	for p in colony.projects:
		if p.phase != Project.Phase.DONE:
			active += 1
	hud.set_status("%s · %s · %s\nЖители %d (заняты %d) · стройки %d" % [
		where, world.gen.zone_name(c.x, c.y), _env_text(c), colony.units.size(), busy, active])
	hud.set_resources(colony.inventory)


func _update_sky() -> void:
	var half_h := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var top_y := world_view.origin.y + (camera.position.y - half_h) / ChunkView.TILE
	var bottom_y := world_view.origin.y + (camera.position.y + half_h) / ChunkView.TILE
	var m := _sky.material as ShaderMaterial
	m.set_shader_parameter("alt_top", -top_y)
	m.set_shader_parameter("alt_bottom", -bottom_y)
