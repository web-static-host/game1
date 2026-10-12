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
var _pending_workers := 1
var _pending_material := "wood"
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
		hud.log_event("У вас 5 жителей и пустой склад. Начните со «Сбора»: кусты с ягодами — еда, деревья и валуны — дерево и камень.", "info")
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
	var units_before := colony.units.size()
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
	var born := colony.units.size() - units_before
	if born > 0:
		lines.append("Родилось детей: %d!" % born)
	var hungry := 0
	for u in colony.units:
		if u.satiety < 25.0:
			hungry += 1
	if hungry > 0:
		lines.append("Голодают жителей: %d — нужна еда (ягоды, ферма)." % hungry)
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
		_show_unit(u)
	elif p != null:
		_info_target = ["project", p.id]
		_show_project(p)
	else:
		_info_target = []
		hud.hide_info()


func _show_unit(u: Unit) -> void:
	if u.child:
		hud.show_info(_unit_text(u))
		return
	hud.show_info(_unit_text(u), [], [{
		"label": "Профессия:", "value": u.profession, "min": 0, "max": Unit.PROF_NAMES.size() - 1,
		"options": Unit.PROF_NAMES,
		"changed": func(v: int) -> void:
			u.profession = v
			hud.update_info_text(_unit_text(u)),
	}])


func _unit_text(u: Unit) -> String:
	var t := u.status_text()
	if u.partner_id != 0:
		var partner := colony.unit_by_id(u.partner_id)
		if partner != null:
			t += "\nПара: " + partner.name
	return t


func _show_project(p: Project) -> void:
	var actions := []
	var controls := []
	if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD or p.phase == Project.Phase.EQUIP:
		actions.append(["Продолжить" if p.paused else "Пауза", func() -> void:
			colony.set_paused(p, not p.paused)
			_show_project(p)])
		actions.append(["Отменить", func() -> void:
			colony.cancel_project(p)
			_select(null, null)])
		controls.append(_workers_stepper(p.workers, func(v: int) -> void:
			p.workers = v
			hud.update_info_text(_project_text(p))))
	elif p.kind == Project.Kind.ROOM:
		if not p.ladder:
			actions.append(["Лестница", func() -> void:
				colony.add_ladder(p)
				_show_project(p)])
		if p.purpose == RoomType.STORAGE:
			controls.append(_storage_checks(p))
		# Готовая комната: выбор назначения.
		var choice := {"v": maxi(p.purpose, 1)}
		controls.append({
			"label": "Назначение:", "value": choice["v"], "min": 1, "max": RoomType.NAMES.size() - 1,
			"options": RoomType.NAMES,
			"changed": func(v: int) -> void:
				choice["v"] = v
				hud.update_info_text(_project_text(p, v)),
		})
		actions.append(["Обустроить", func() -> void:
			if colony.set_purpose(p, choice["v"]):
				_show_project(p)
			else:
				hud.log_event("Комната уже так обустроена", "info")])
	hud.show_info(_project_text(p, maxi(p.purpose, 1)), actions, controls)


## Галочки «что хранить на складе». Ничего не выбрано — хранит всё.
func _storage_checks(p: Project) -> Dictionary:
	var items := [["*", "Всё", p.store_filter.is_empty()]]
	var keys: Array = colony.known_resources.keys()
	keys.sort()
	for k in keys:
		if not RoomType.BULK.has(k):
			items.append([k, Mat.resource_name(k), p.store_filter.has(k)])
	return {"type": "checks", "label": "Хранить на складе:", "items": items,
		"toggled": func(key: String, on: bool) -> void:
			var f: Array[String] = p.store_filter.duplicate()
			if key == "*":
				f.clear()
			elif on and not f.has(key):
				f.append(key)
			elif not on:
				f.erase(key)
			colony.set_store_filter(p, f)
			_show_project(p)}


func _workers_stepper(value: int, changed: Callable) -> Dictionary:
	return {"label": "Рабочих:", "value": value, "min": 1, "max": maxi(1, colony.adults()), "changed": changed}


func _project_text(p: Project, preview_purpose := -1) -> String:
	var lines: PackedStringArray = [p.title() + " — " + ("на паузе" if p.paused else p.phase_name())]
	if p.kind == Project.Kind.ROOM:
		lines[0] += " · стены: " + p.material_name().to_lower()
	else:
		lines[0] += " · потоков: %d" % Colony.tunnel_lanes(p.rect)
	match p.phase:
		Project.Phase.DIG:
			lines.append("Этап 1 из 2: копка. Осталось клеток: %d" % colony.remaining_dig(p).size())
		Project.Phase.BUILD:
			var pct := int(100.0 * p.build_done / p.build_work()) if p.paid else 0
			lines.append("Этап 2 из 2: строительство %d%%" % pct)
		Project.Phase.EQUIP:
			var w := RoomType.job_work(p)
			var pct := int(100.0 * p.equip_done / w) if p.equip_paid else 0
			if p.equip_ladder:
				lines.append("Строится лестница: %d%%" % pct)
			else:
				lines.append("Обустройство под «%s»: %d%%" % [RoomType.NAMES[p.equip_target], pct])
			lines.append("Материалы: " + _cost_text(RoomType.job_cost(p)) + (" (оплачено)" if p.equip_paid else ""))
	if p.phase == Project.Phase.DIG and not colony.uncleared(p).is_empty():
		lines.append("Сначала убрать с места стройки: %d (деревья, кусты, валуны)" % colony.uncleared(p).size())
	if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
		lines.append("Материалы: " + _cost_text(p.cost()) + (" (оплачено)" if p.paid else ""))
	if p.phase != Project.Phase.DONE:
		lines.append("Сейчас работают: %d из %d" % [colony.workers_on(p), p.workers])
	elif p.kind == Project.Kind.ROOM:
		match p.purpose:
			RoomType.HOME:
				var used := 0
				for u in colony.units:
					if u.bed_room == p.id:
						used += 1
				lines.append("Кроватей: %d (по одной на жителя), занято: %d" % [RoomType.beds(p), used])
				var free := colony.beds_total() - colony.units.size() - colony.pregnant_count()
				lines.append("Свободных мест для детей во всей колонии: %d" % maxi(0, free))
				lines.append("Ребёнок рождается у пары, если есть свободная кровать, еда (от 3) и мама сыта; шанс ~12%% каждые 20 сек.")
			RoomType.STORAGE:
				lines.append("Вместимость: +%d каждого выбранного ресурса" % (RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p)))
			RoomType.FARM:
				lines.append("Фермеров: %d из %d мест" % [colony.workers_on(p), RoomType.farm_slots(p)])
			RoomType.DINING:
				lines.append("Еда здесь сытнее и поднимает настроение")
		if not p.ladder:
			lines.append("Лестницы нет: на эту комнату нельзя ставить второй этаж (%s)" % _cost_text(RoomType.ladder_cost(p)))
		if preview_purpose > 0 and preview_purpose != p.purpose:
			lines.append("Обустроить под «%s» (%s): %s" % [RoomType.NAMES[preview_purpose], RoomType.HINTS[preview_purpose],
				_cost_text(RoomType.equip_cost(preview_purpose, p))])
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
		var u := colony.unit_by_id(_info_target[1])
		if u != null:
			hud.update_info_text(_unit_text(u))
	elif _info_target[0] == "project":
		var p := colony.project_by_id(_info_target[1])
		if p == null:
			_select(null, null)
		elif p.phase != Project.Phase.DONE:
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
	_pending_workers = Project.recommended_workers(kind, r, colony.adults())
	_pending_material = "wood"
	_show_pending()


func _show_pending() -> void:
	var r := _pending
	var kind := _pending_kind
	var controls := [_workers_stepper(_pending_workers, func(v: int) -> void: _pending_workers = v)]
	if kind == Project.Kind.ROOM:
		var mats := colony.available_materials()
		var names: Array = mats.map(func(k: String) -> String: return Project.MATERIALS[k][0])
		controls.push_front({
			"label": "Материал стен:", "value": mats.find(_pending_material), "min": 0, "max": mats.size() - 1,
			"options": names,
			"changed": func(v: int) -> void:
				_pending_material = mats[v]
				hud.update_info_text(_pending_text()),
		})
	hud.show_info(_pending_text(), [
		["Построить", _confirm_pending],
		["Отмена", _clear_preview],
	], controls)


func _pending_text() -> String:
	var r := _pending
	var kind := _pending_kind
	var lines: PackedStringArray = ["%s %d×%d" % [Project.kind_name(kind), r.size.x, r.size.y]]
	lines.append("Материалы на 2-м этапе: " + _cost_text(Project.cost_for(kind, r, _pending_material)))
	if kind == Project.Kind.TUNNEL:
		var lanes := Colony.tunnel_lanes(r)
		lines.append("Пропускная способность: %d %s" % [lanes, "поток" if lanes == 1 else "потока"])
	elif colony.available_materials().size() == 1:
		lines.append("Глина и камень станут доступны, когда вы их добудете.")
	lines.append("Рекомендуется рабочих: %d" % Project.recommended_workers(kind, r, colony.adults()))
	if not colony.has_access(r):
		lines.append("Внимание: к зоне нет прохода — сначала проложите к ней тоннель.")
	return "\n".join(lines)


func _confirm_pending() -> void:
	var p := colony.create_project(_pending_kind, _pending, _pending_workers, _pending_material)
	_clear_preview()
	if p != null:
		hud.log_event("Заложено: %s, рабочих: %d" % [p.title(), p.workers], "info")


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
	var kids := 0
	var hungry := 0
	for u in colony.units:
		if u.child:
			kids += 1
		if u.satiety < 25.0:
			hungry += 1
	var active := 0
	for p in colony.projects:
		if p.phase != Project.Phase.DONE:
			active += 1
	var people := "Жители %d" % colony.units.size()
	if kids > 0:
		people += " (дети %d)" % kids
	var line2 := "%s · кроватей %d · стройки %d" % [people, colony.beds_total(), active]
	if hungry > 0:
		line2 += " · голодают: %d" % hungry
	hud.set_status("%s · %s · %s\n%s" % [where, world.gen.zone_name(c.x, c.y), _env_text(c), line2])
	hud.set_resources(colony.inventory)


func _update_sky() -> void:
	var half_h := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var top_y := world_view.origin.y + (camera.position.y - half_h) / ChunkView.TILE
	var bottom_y := world_view.origin.y + (camera.position.y + half_h) / ChunkView.TILE
	var m := _sky.material as ShaderMaterial
	m.set_shader_parameter("alt_top", -top_y)
	m.set_shader_parameter("alt_bottom", -bottom_y)
