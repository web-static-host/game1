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
var _restarting := false
## Варианты постройки над водой: [[вид, рамка], ...].
var _water_options := []
var _drag_start := Vector2i.ZERO
var _pending := Rect2i()
var _pending_kind := 0
var _pending_workers := 1
var _pending_material := "wood"
## Что показано в информационной панели: [вид, id] — чтобы обновлять текст.
var _info_target := []
## Тряска камеры при землетрясении, сек.
var _shake := 0.0


func _ready() -> void:
	var data := SaveSystem.load_data()
	var seed_value := int(data["seed"]) if data.has("seed") else _new_seed()
	world = WorldData.new(WorldGen.new(seed_value))
	colony = Colony.new(world)
	_home = Vector2i(0, world.gen.surface_y(0))
	_build_scene()
	colony.event_logged.connect(hud.log_event)
	colony.quaked.connect(func(mag: int) -> void: _shake = 1.2 + mag * 0.8)

	var start := _home + Vector2i(0, -3)
	if data.is_empty():
		colony.disasters = _new_game_settings().get("disasters", true)
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
	hud.save_pressed.connect(func() -> void:
		_save()
		hud.log_event("Игра сохранена", "good"))
	hud.new_game_confirmed.connect(_new_game)
	hud.science_pressed.connect(_show_science)


func _process(delta: float) -> void:
	# Большие паузы (сворачивание) учитываются как оффлайн, а не через delta.
	var dt := minf(delta, 0.25)
	colony.update(dt * SPEEDS[_speed_idx])
	_clamp_camera()
	if _shake > 0.0:
		_shake -= delta
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * minf(1.0, _shake)
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
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


const NEW_GAME_PATH := "user://new_game.json"


## Настройки новой игры, выбранные в меню (читаются один раз).
func _new_game_settings() -> Dictionary:
	if not FileAccess.file_exists(NEW_GAME_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(NEW_GAME_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NEW_GAME_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _new_game(disasters: bool) -> void:
	var f := FileAccess.open(NEW_GAME_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"disasters": disasters}))
		f.close()
	_restarting = true
	if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
	get_tree().reload_current_scene()


func _save() -> void:
	if _restarting:
		return
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
	var worn := 0
	for p in colony.projects:
		if p.wear >= Colony.WEAR_WARN[0] and not p.repairing:
			worn += 1
	if worn > 0:
		lines.append("Ветшают построек: %d — нужен ремонт, иначе рухнут." % worn)
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
	camera.paint_mode = m == Hud.Mode.TUNNEL or m == Hud.Mode.ROOM or m == Hud.Mode.BRIDGE
	_clear_preview()
	_select(null, null)


# --- Нажатия ---------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if mode == Hud.Mode.HARVEST:
		var x = _feature_near(c)
		if not colony.is_explored(c.x):
			hud.log_event("Туда ещё никто не ходил", "warning")
			return
		if x == null:
			hud.log_event("Здесь нечего собирать — нажмите на дерево, валун или куст.", "warning")
		else:
			var err := colony.toggle_harvest(x)
			if not err.is_empty():
				hud.log_event(err, "warning")
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
	hud.show_panel(_cell_spec(c))


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
		_show_project(p)
	else:
		_info_target = []
		hud.hide_info()


func _show_unit(u: Unit) -> void:
	var controls := []
	if not u.child:
		controls.append({
			"label": "Профессия", "value": u.profession, "min": 0, "max": Unit.PROF_NAMES.size() - 1,
			"options": Unit.PROF_NAMES,
			"changed": func(v: int) -> void: u.profession = v,
		})
	var spec := _unit_spec(u)
	spec["controls"] = controls
	hud.show_panel(spec)


static func _need_bar(label: String, v: float) -> Dictionary:
	var col := Color(0.45, 0.82, 0.4)
	if v < 25.0:
		col = Color(0.9, 0.3, 0.25)
	elif v < 50.0:
		col = Color(0.95, 0.65, 0.2)
	return {"type": "progress", "label": label, "value": v / 100.0, "color": col, "text": "%d%%" % roundi(v)}


func _unit_spec(u: Unit) -> Dictionary:
	var who := "мужчина" if u.sex == Unit.Sex.MALE else "женщина"
	if u.child:
		who = "%s, вырастет через %s" % ["малыш" if u.age < Unit.CHILD_TIME * 0.5 else "подросток",
			Fmt.duration(Unit.CHILD_TIME - u.age)]
	var task: String = Unit.TASK_NAMES[u.task]
	if u.gather_room != 0:
		task += " для склада"
	var rows := [_need_bar("Сытость", u.satiety), _need_bar("Бодрость", u.energy), _need_bar("Настроение", u.mood())]
	if u.health < 99.5:
		rows.append(_need_bar("Здоровье", u.health))
	if u.task == Unit.Task.HAUL and u.carry_amount > 0:
		rows.append({"type": "resources", "label": "Несёт", "items": [[u.carry_key, u.carry_amount, -1, true]]})
	if not u.child:
		var skills := []
		for k in ["dig", "build", "gather", "farm", "science"]:
			skills.append(["", "%s %d" % [Unit.SKILL_NAMES[k], u.level(k)]])
		rows.append({"type": "chips", "label": "Навыки", "items": skills})
	var extra := [["home", "кровать есть" if u.bed_room != 0 else "нет кровати",
		Color.WHITE if u.bed_room != 0 else Color(1.0, 0.6, 0.5)]]
	if u.partner_id != 0:
		var partner := colony.unit_by_id(u.partner_id)
		if partner != null:
			extra.append(["people", "пара: " + partner.name])
	if u.pregnancy >= 0.0:
		extra.append(["", "ждёт ребёнка", Color(1.0, 0.7, 0.8)])
	if u.child:
		extra.append(["", "ест вдвое больше"])
	rows.append({"type": "chips", "items": extra})
	return {"title": u.name, "subtitle": "%s · %s" % [who, task], "rows": rows}


func _show_project(p: Project) -> void:
	var actions := []
	var controls := []
	if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD or p.phase == Project.Phase.EQUIP:
		actions.append(["Продолжить" if p.paused else "Пауза", func() -> void:
			colony.set_paused(p, not p.paused)
			_show_project(p)])
		actions.append(["Отменить", func() -> void:
			colony.cancel_project(p)
			_select(null, null), "danger"])
		controls.append(_workers_stepper(p.workers, func(v: int) -> void: p.workers = v))
	if p.phase == Project.Phase.DONE:
		if p.repairing:
			controls.append(_workers_stepper(p.workers, func(v: int) -> void: p.workers = v))
			actions.append(["Отменить ремонт", func() -> void:
				colony.cancel_project(p)
				_show_project(p)])
		elif p.wear >= 0.05:
			actions.append(["Ремонт", func() -> void:
				if colony.start_repair(p):
					_show_project(p)
				else:
					hud.log_event(colony.repair_error(p), "warning"), "primary"])
		actions.append(["Снести", func() -> void:
			var err := colony.demolish_error(p)
			if not err.is_empty():
				hud.log_event(err, "warning")
				return
			colony.demolish(p)
			_select(null, null), "danger"])
	var preview := {"v": maxi(p.purpose, 1)}
	if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM:
		if p.purpose == RoomType.STORAGE:
			controls.append({"label": "Работников склада", "value": p.gatherers, "min": 0, "max": maxi(1, colony.adults()),
				"changed": func(v: int) -> void: p.gatherers = v})
			controls.append(_storage_targets(p))
			controls.append(_storage_checks(p))
		# Готовая комната: выбор назначения (только изученные).
		var purposes := []
		for t in range(1, RoomType.NAMES.size()):
			if colony.research.has(RoomType.REQUIRES.get(t, "")):
				purposes.append(t)
		controls.append({
			"label": "Назначение", "value": maxi(0, purposes.find(preview["v"])), "min": 0, "max": purposes.size() - 1,
			"options": purposes.map(func(t: int) -> String: return RoomType.NAMES[t]),
			"changed": func(i: int) -> void:
				preview["v"] = purposes[i]
				_info_target = ["project", p.id, purposes[i]]
				hud.refresh_panel(_project_spec(p, purposes[i])),
		})
		actions.push_front(["Обустроить", func() -> void:
			if colony.set_purpose(p, preview["v"]):
				_show_project(p)
			else:
				hud.log_event("Комната уже так обустроена", "info")])
	_info_target = ["project", p.id, preview["v"]]
	var spec := _project_spec(p, preview["v"])
	spec["actions"] = actions
	spec["controls"] = controls
	spec["controls_first"] = p.purpose == RoomType.STORAGE and p.phase == Project.Phase.DONE
	hud.show_panel(spec)


## Нормы запаса склада: сколько держать каждого ресурса.
func _storage_targets(p: Project) -> Dictionary:
	var items := []
	var keys: Array = Colony.GATHER_SOURCES.keys()
	for k in colony.known_resources:
		if not keys.has(k) and not RoomType.BULK.has(k):
			keys.append(k)
	for k in keys:
		if not RoomType.stores(p, k):
			continue
		items.append([k, colony.inventory.get(k, 0), int(p.targets.get(k, 0)), colony.capacity(k),
			Colony.GATHER_SOURCES.has(k)])
	return {"type": "targets", "label": "Держать в запасе (работники склада добывают до нормы):", "items": items,
		"changed": func(key: String, v: int) -> void: p.targets[key] = v}


## Галочки «что хранить на складе». Ничего не выбрано — хранит всё.
func _storage_checks(p: Project) -> Dictionary:
	var items := [["*", "Всё", p.store_filter.is_empty()]]
	var keys: Array = colony.known_resources.keys()
	keys.sort()
	for k in keys:
		if not RoomType.BULK.has(k):
			items.append([k, Mat.resource_name(k), p.store_filter.has(k)])
	return {"type": "checks", "label": "Что хранить на складе:", "items": items,
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
	return {"label": "Рабочих", "value": value, "min": 1, "max": maxi(1, colony.adults()), "changed": changed}


static func _progress(label: String, v: float, text := "", col := Color(0.45, 0.82, 0.4)) -> Dictionary:
	return {"type": "progress", "label": label, "value": v, "text": text if not text.is_empty() else "%d%%" % roundi(v * 100.0), "color": col}


## Цвет износа: зелёный → оранжевый → красный.
static func _wear_color(w: float) -> Color:
	if w >= Colony.WEAR_WARN[1]:
		return Color(0.9, 0.28, 0.24)
	if w >= Colony.WEAR_WARN[0]:
		return Color(0.95, 0.62, 0.2)
	return Color(0.5, 0.75, 0.45)


func _project_spec(p: Project, preview_purpose := -1) -> Dictionary:
	var rows := []
	var sub := "на паузе" if p.paused else p.phase_name()
	var accent := Hud.ACCENT
	match p.phase:
		Project.Phase.DIG:
			var left := colony.remaining_dig(p).size()
			rows.append(_progress("Копка", 1.0 - float(left) / p.area(), "осталось %d клеток" % left))
			if not p.needs_support.is_empty():
				rows.append(_progress("Крепь", float(p.supported.size()) / p.needs_support.size(),
					"%d из %d срезов" % [p.supported.size(), p.needs_support.size()], Color(0.75, 0.55, 0.3)))
			var clear := colony.uncleared(p).size()
			if clear > 0:
				rows.append({"type": "text", "text": "Сначала убрать с места стройки: %d (деревья, кусты, валуны)" % clear})
		Project.Phase.BUILD:
			rows.append(_progress("Строительство", p.build_done / p.build_work() if p.paid else 0.0))
		Project.Phase.EQUIP:
			var w := RoomType.job_work(p)
			rows.append(_progress("Лестница" if p.equip_ladder else "Обустройство", p.equip_done / w if p.equip_paid else 0.0))
	if p.repairing:
		rows.append(_progress("Ремонт", p.repair_done / maxf(1.0, p.repair_work) if p.repair_paid else 0.0))
	var supply := colony.supply_status(p)
	if not supply.is_empty():
		rows.append({"type": "resources", "label": "Материалы", "items": supply})
	var chips := []
	if p.phase != Project.Phase.DONE or p.repairing:
		chips.append(["people", "рабочие %d/%d" % [colony.workers_on(p), p.workers]])
	match p.kind:
		Project.Kind.ROOM:
			chips.append(["", "стены: " + p.material_name().to_lower()])
		Project.Kind.TUNNEL:
			chips.append(["", "потоков: %d" % Colony.tunnel_lanes(p.rect)])
		_:
			chips.append(["people", "рыбаков %d/%d" % [colony.workers_on(p), p.fish_slots()]])
			chips.append(["", "рыбы ~%d" % int(colony.fish_left(p))])
	if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
		rows.append(_progress("Износ", p.wear, "%d%% · ещё ~%s" % [roundi(p.wear * 100.0), _years(colony.years_left(p))],
			_wear_color(p.wear)))
		if p.kind == Project.Kind.ROOM:
			var util := colony.loads.utilization(p)
			rows.append(_progress("Нагрузка", minf(util, 1.0), "%d т из %d т" % [roundi(colony.loads.load_on(p)),
				roundi(Loads.bearing(p))], _wear_color(util * 0.9)))
			if not colony.is_underground(p):
				var tower := colony.loads.tower_of(p.rect, p.material)
				chips.append(["", "ветер %d м/с" % roundi(colony.loads.wind(tower[0]))])
	if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM:
		match p.purpose:
			RoomType.HOME:
				var used := 0
				for u in colony.units:
					if u.bed_room == p.id:
						used += 1
				chips.append(["home", "кроватей %d, занято %d" % [RoomType.beds(p), used]])
				var free := colony.beds_total() - colony.units.size() - colony.pregnant_count()
				chips.append(["people", "мест для детей в колонии: %d" % maxi(0, free)])
			RoomType.STORAGE:
				chips.append(["people", "работников %d/%d" % [colony.gatherers_on(p), p.gatherers]])
				chips.append(["", "+%d места каждому ресурсу" % (RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p))])
				var lacking := colony.storage_deficit(p)
				if p.gatherers > 0 and not lacking.is_empty():
					var names := lacking.map(func(k: String) -> String: return Mat.resource_name(k).to_lower())
					rows.append({"type": "text", "text": "Добывают до нормы: " + ", ".join(names)})
			RoomType.FARM:
				chips.append(["people", "фермеров %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
			RoomType.DINING:
				chips.append(["", "еда сытнее, настроение лучше"])
			RoomType.KILN, RoomType.FORGE:
				var recipe: Array = RoomType.RECIPES[p.purpose]
				rows.append(_progress("Производство", p.farm_progress / recipe[2]))
				var items := []
				for k in recipe[0]:
					var have: int = colony.inventory.get(k, 0)
					items.append([k, have, recipe[0][k], have >= recipe[0][k]])
				rows.append({"type": "resources", "label": "Сырьё на цикл", "items": items})
				var out := []
				for k in recipe[1]:
					out.append([k, recipe[1][k], -1, true])
				rows.append({"type": "resources", "label": "Даёт", "items": out})
				chips.append(["people", "мастеров %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
			RoomType.LAB:
				chips.append(["people", "учёных %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
				var cur := colony.research.current
				if cur.is_empty():
					rows.append({"type": "text", "text": "Нечего изучать — выберите исследование («Наука»)."})
				else:
					rows.append(_progress(Research.tech_name(cur), colony.research.progress / colony.research.cost(cur)))
			RoomType.GENERATOR:
				chips.append(["power", "даёт %d, колонии нужно %d" % [RoomType.POWER_MAKE, colony.power_used]])
				rows.append(_progress("Топливо", clampf(p.farm_progress / RoomType.FUEL_TIME, 0.0, 1.0),
					"%d с" % maxi(0, roundi(p.farm_progress)), Color(0.95, 0.6, 0.2)))
				rows.append({"type": "text", "text": "Жжёт 1 уголь (или 2 дерева) за %d с." % int(RoomType.FUEL_TIME)})
		if RoomType.POWER_USE.has(p.purpose) and colony.research.has("electricity"):
			chips.append(["power", "энергия: %s" % ("есть" if colony.powered() and colony.power_ratio >= 0.99 else
				("не хватает" if colony.powered() else "нет"))])
		if preview_purpose > 0 and preview_purpose != p.purpose:
			var cost := RoomType.equip_cost(preview_purpose, p)
			rows.append({"type": "text", "text": "«%s»: %s" % [RoomType.NAMES[preview_purpose], RoomType.HINTS[preview_purpose]],
				"color": Color.WHITE})
			if not cost.is_empty():
				rows.append({"type": "resources", "label": "Обустройство", "items": _cost_items(cost)})
	rows.append({"type": "chips", "items": chips})
	if not p.found.is_empty():
		var found := []
		for k in p.found:
			found.append([k, p.found[k], -1, true])
		rows.append({"type": "resources", "label": "Найдено", "items": found})
	rows.append({"type": "text", "text": "Условия: " + _env_text(p.rect.get_center())})
	if not p.blocked.is_empty():
		rows.append({"type": "warning", "text": p.blocked})
		accent = Color(1.0, 0.5, 0.4)
	elif p.wear >= Colony.WEAR_WARN[0] and not p.repairing:
		rows.append({"type": "warning", "text": "Постройка ветшает — отремонтируйте, иначе она рухнет."})
	return {"title": p.title(), "subtitle": sub, "accent": accent, "rows": rows}


static func _years(y: float) -> String:
	if y >= 1.0:
		return "%d %s" % [roundi(y), _plural(roundi(y), "год", "года", "лет")]
	return "%d мес." % maxi(1, roundi(y * 12.0))


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m := n % 100
	if m >= 11 and m <= 14:
		return many
	match n % 10:
		1:
			return one
		2, 3, 4:
			return few
	return many


## Плашки стоимости: [ресурс, есть на складе, нужно, хватает].
func _cost_items(cost: Dictionary) -> Array:
	var out := []
	for k in cost:
		var have: int = colony.inventory.get(k, 0)
		out.append([k, have, cost[k], have >= cost[k]])
	return out


## Наука: текущее исследование и дерево технологий.
func _show_science() -> void:
	_select(null, null)
	_info_target = ["science"]
	var spec := _science_spec()
	var techs := []
	for id in Research.TECHS:
		techs.append(id)
	spec["controls"] = [{"type": "techs", "items": techs.map(func(id: String) -> Dictionary: return _tech_item(id))}]
	hud.show_panel(spec)


func _tech_item(id: String) -> Dictionary:
	var r := colony.research
	var state := "locked"
	if r.has(id):
		state = "done"
	elif r.current == id:
		state = "current"
	elif r.available(id):
		state = "available"
	var needs: Array = Research.TECHS[id][3]
	var desc: String = Research.TECHS[id][1]
	if state == "locked":
		desc = "Сначала: " + ", ".join(needs.map(func(n: String) -> String: return Research.tech_name(n))) + ". " + desc
	return {"name": Research.tech_name(id), "desc": desc, "cost": int(r.cost(id)), "state": state,
		"pick": func() -> void:
			r.start(id)
			_show_science()}


func _science_spec() -> Dictionary:
	var r := colony.research
	var rows := []
	if r.current.is_empty():
		rows.append({"type": "text", "text": "Выберите, что изучать. Очки дают учёные в лаборатории (назначение комнаты)."})
	else:
		rows.append(_progress(Research.tech_name(r.current), r.progress / r.cost(r.current),
			"%d / %d" % [int(r.progress), int(r.cost(r.current))], Color(0.45, 0.7, 1.0)))
	var labs := colony.rooms_of(RoomType.LAB)
	var scientists := 0
	for p in labs:
		scientists += colony.workers_on(p)
	rows.append({"type": "chips", "items": [["", "лабораторий: %d" % labs.size()], ["people", "учёных за работой: %d" % scientists]]})
	if labs.is_empty():
		rows.append({"type": "warning", "text": "Нет лаборатории — постройте комнату и выберите назначение «Лаборатория»."})
	return {"title": "Наука", "subtitle": "изучено %d из %d" % [r.done.size(), Research.TECHS.size()], "rows": rows}


func _refresh_info() -> void:
	if _info_target.is_empty() or not hud.info_visible():
		return
	if _info_target[0] == "unit":
		var u := colony.unit_by_id(_info_target[1])
		if u != null:
			hud.refresh_panel(_unit_spec(u))
	elif _info_target[0] == "science":
		hud.refresh_panel(_science_spec())
	elif _info_target[0] == "project":
		var p := colony.project_by_id(_info_target[1])
		if p == null:
			_select(null, null)
		else:
			hud.refresh_panel(_project_spec(p, _info_target[2]))


# --- Рамка стройки -------------------------------------------------------------------

func _on_paint(screen_pos: Vector2, first: bool) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if first:
		_drag_start = c
		hud.hide_info()
	var r := Rect2i(Vector2i(mini(c.x, _drag_start.x), mini(c.y, _drag_start.y)),
		(c - _drag_start).abs() + Vector2i.ONE)
	var kind := _mode_kind()
	var err := ""
	if mode == Hud.Mode.BRIDGE:
		# Над водой ряд сам привязывается к уровню воды и тянется до берега.
		_water_options = []
		var w := colony.water_rects(_drag_start.x, c.x)
		for k in [Project.Kind.BRIDGE, Project.Kind.PIER]:
			var wr: Rect2i = w["bridge" if k == Project.Kind.BRIDGE else "pier"]
			if wr.size != Vector2i.ZERO and colony.validate(k, wr).is_empty():
				_water_options.append([k, wr])
		if _water_options.is_empty():
			r = Rect2i(r.position.x, _drag_start.y, r.size.x, 1)
			err = "Проведите пальцем над озером"
		else:
			# Длинный жест через воду — мостик, короткий от берега — пристань.
			var pick: Array = _water_options[0]
			if _water_options.size() > 1 and absi(c.x - _drag_start.x) + 1 < (pick[1] as Rect2i).size.x * 0.6:
				pick = _water_options[1]
			kind = pick[0]
			r = pick[1]
	else:
		err = colony.validate(kind, r)
	var s := world_view.structures
	s.preview = r
	s.preview_ok = err.is_empty()
	s.preview_text = "%d×%d" % [r.size.x, r.size.y] if mode != Hud.Mode.BRIDGE else \
		("%s %d м" % [Project.kind_name(kind), r.size.x] if err.is_empty() else err)


func _on_paint_end(_screen_pos: Vector2) -> void:
	var r := world_view.structures.preview
	if r.size == Vector2i.ZERO:
		return
	var kind := _mode_kind()
	var err := colony.validate(kind, r)
	if mode == Hud.Mode.BRIDGE:
		err = "Мостик и пристань строятся над озером" if _water_options.is_empty() else ""
		for o in _water_options:
			if o[1] == r:
				kind = o[0]
	if not err.is_empty():
		hud.log_event(err, "warning")
		_clear_preview()
		return
	_pending = r
	_pending_kind = kind
	_pending_workers = Project.recommended_workers(kind, r, colony.adults())
	_pending_material = "wood"
	_show_pending()


func _mode_kind() -> int:
	match mode:
		Hud.Mode.ROOM:
			return Project.Kind.ROOM
		Hud.Mode.BRIDGE:
			return Project.Kind.BRIDGE
	return Project.Kind.TUNNEL


func _show_pending() -> void:
	var r := _pending
	var kind := _pending_kind
	var controls := [_workers_stepper(_pending_workers, func(v: int) -> void: _pending_workers = v)]
	if kind == Project.Kind.BRIDGE or kind == Project.Kind.PIER:
		var opts := []
		var idx := 0
		for i in _water_options.size():
			opts.append(Project.kind_name(_water_options[i][0]))
			if _water_options[i][0] == kind:
				idx = i
		if opts.size() > 1:
			controls.push_front({
				"label": "Постройка", "value": idx, "min": 0, "max": opts.size() - 1,
				"options": opts,
				"changed": func(v: int) -> void:
					_pending_kind = _water_options[v][0]
					_pending = _water_options[v][1]
					world_view.structures.preview = _pending
					hud.refresh_panel(_pending_spec()),
			})
	if kind == Project.Kind.ROOM:
		var mats := colony.available_materials()
		var names: Array = mats.map(func(k: String) -> String: return Project.MATERIALS[k][0])
		controls.push_front({
			"label": "Материал стен", "value": mats.find(_pending_material), "min": 0, "max": mats.size() - 1,
			"options": names,
			"changed": func(v: int) -> void:
				_pending_material = mats[v]
				hud.refresh_panel(_pending_spec()),
		})
	var spec := _pending_spec()
	spec["controls"] = controls
	spec["controls_first"] = true
	spec["actions"] = [["Построить", _confirm_pending, "primary"], ["Отмена", _clear_preview]]
	hud.show_panel(spec)


func _pending_spec() -> Dictionary:
	var r := _pending
	var kind := _pending_kind
	var rows := []
	var cost := Project.cost_for(kind, r, _pending_material)
	if not cost.is_empty():
		rows.append({"type": "resources", "label": "Материалы", "items": _cost_items(cost)})
	var chips := []
	if kind == Project.Kind.ROOM or kind == Project.Kind.TUNNEL:
		var sw := _support_estimate(kind, r)
		var have: int = colony.inventory.get("wood", 0)
		rows.append({"type": "resources", "label": "Крепь по ходу", "items": [["wood", have, sw, have >= sw]]})
	var support := colony.support_needed(kind, r)
	if support > 0:
		var span: Array = colony.ceiling_span(r)
		rows.append({"type": "text", "text": "Потолок из «%s» держит без опор %d м — крепь усиленная" % [
			Mat.name_of(span[1]).to_lower(), span[0]]})
	for lower in colony.ladders_needed(r):
		rows.append({"type": "resources", "label": "Лестница внизу", "items": _cost_items(RoomType.ladder_cost(lower))})
	if kind == Project.Kind.ROOM and not colony.rooms_below(r).is_empty():
		var tmp := Project.new()
		tmp.id = -1
		tmp.kind = kind
		tmp.rect = r
		tmp.material = _pending_material
		var predicted := colony.loads.compute(tmp)
		for lower in colony.rooms_below(r):
			var util := colony.loads.utilization(lower, predicted)
			rows.append(_progress("Нагрузка внизу", minf(util, 1.0), "%s: %d%%" % [lower.title(), roundi(util * 100.0)],
				_wear_color(util * 0.9)))
	if kind == Project.Kind.ROOM and r.position.y < world.gen.surface_y(r.get_center().x):
		var tower := colony.loads.tower_of(r, _pending_material)
		var limit := int(tower[1] * Loads.SLENDER.get(tower[2], 3.0))
		chips.append(["", "башня %d м из %d возможных" % [tower[0], limit]])
	var verr := colony.validate(kind, r, _pending_material)
	if not verr.is_empty():
		rows.append({"type": "warning", "text": verr})
	if kind == Project.Kind.TUNNEL:
		var lanes := Colony.tunnel_lanes(r)
		chips.append(["people", "%d %s" % [lanes, "поток" if lanes == 1 else "потока"]])
	if kind == Project.Kind.BRIDGE or kind == Project.Kind.PIER:
		var tmp := Project.new()
		tmp.kind = kind
		tmp.rect = r
		var lake := world.gen.lake_at(r.get_center().x)
		chips.append(["people", "рыбаков до %d" % tmp.fish_slots()])
		chips.append(["", "улов раз в %d с" % int(tmp.fish_time())])
		chips.append(["", "рыбы ~%d" % int(colony.fish_in(lake))])
	chips.append(["people", "рекомендуется рабочих: %d" % Project.recommended_workers(kind, r, colony.adults())])
	rows.append({"type": "chips", "items": chips})
	if kind == Project.Kind.ROOM and colony.available_materials().size() == 1:
		rows.append({"type": "text", "text": "Глина и камень станут доступны, когда вы их добудете."})
	rows.append({"type": "text", "text": "Материалы жители принесут сами. Без крепи и работ дольше 3 мин — риск обвала."})
	if not colony.has_access(r):
		rows.append({"type": "warning", "text": "К зоне нет прохода — сначала проложите к ней тоннель."})
	return {"title": "%s %d×%d" % [Project.kind_name(kind), r.size.x, r.size.y], "subtitle": "новая стройка", "rows": rows}


## Сколько дерева уйдёт на крепь по срезам (оценка до закладки).
func _support_estimate(kind: int, r: Rect2i) -> int:
	var tmp := Project.new()
	tmp.kind = kind
	tmp.rect = r
	tmp.support_wood = colony.support_needed(kind, r)
	var n := 0
	for i in tmp.slice_count():
		for c in tmp.slice_cells(i):
			if Mat.is_solid(world.get_mat(c.x, c.y)):
				n += 1
				break
	tmp.needs_support.resize(n)
	return tmp.slice_wood() * n


func _confirm_pending() -> void:
	var err := colony.validate(_pending_kind, _pending, _pending_material)
	if not err.is_empty():
		hud.log_event(err, "warning")
		return
	var p := colony.create_project(_pending_kind, _pending, _pending_workers, _pending_material)
	_clear_preview()
	if p != null:
		hud.log_event("Заложено: %s, рабочих: %d" % [p.title(), p.workers], "info")


func _clear_preview() -> void:
	world_view.structures.preview = Rect2i()
	hud.hide_info()


# --- Информация -------------------------------------------------------------------

func _cell_spec(c: Vector2i) -> Dictionary:
	var gen := world.gen
	var surf := gen.surface_y(c.x)
	var depth := c.y - surf
	var rows := []
	var title := gen.zone_name(c.x, c.y)
	var sub := ("высота %s м" % Fmt.int_spaced(-c.y)) if depth < 0 else ("глубина %s м" % Fmt.int_spaced(depth))
	if depth < 0 and world.get_mat(c.x, c.y) == Mat.WATER:
		var lake := gen.lake_at(c.x)
		title = "Озеро"
		rows.append({"type": "chips", "items": [["", "ширина ~%d м" % (int(lake.get("w", 0)) * 2)],
			["", "рыбы ~%d из %d" % [int(colony.fish_in(lake)), int(Colony.fish_max(lake))]]]})
		rows.append({"type": "text", "text": "Рыбу не видно. Для рыбалки постройте мостик или пристань («Стройка» → «Мост»), с берега ловят медленнее."})
	var f := world.feature_at(c.x)
	if depth < 0 and depth >= -8 and f != WorldGen.FEATURE_NONE:
		match f:
			WorldGen.FEATURE_TREE:
				title = "Дерево"
				rows.append(_progress("Рост", world.growth(c.x)))
				rows.append({"type": "resources", "label": "Даст", "items": [["wood", colony.feature_yield(c.x)[1], -1, true]]})
			WorldGen.FEATURE_BUSH:
				title = "Куст с ягодами"
				rows.append(_progress("Ягоды", world.berries(c.x) / WorldData.BUSH_BERRIES,
					"%d из %d" % [floori(world.berries(c.x)), int(WorldData.BUSH_BERRIES)], Color(0.85, 0.3, 0.35)))
				rows.append({"type": "text", "text": "Ягоды отрастают. Голодные жители едят прямо с куста."})
			WorldGen.FEATURE_BOULDER:
				title = "Валун"
				rows.append({"type": "resources", "label": "Даст", "items": [["stone", colony.feature_yield(c.x)[1], -1, true]]})
	if depth >= 0:
		if not world.is_revealed(c.x, c.y):
			title = "Неизвестно"
			rows.append({"type": "text", "text": "Что здесь, узнаем, когда раскопаем соседнюю клетку."})
		elif world.is_dug(c.x, c.y):
			title = "Выработка"
			rows.append({"type": "text", "text": "Раньше здесь был(а): " + Mat.name_of(world.get_natural_mat(c.x, c.y)).to_lower()})
		else:
			var m := world.get_mat(c.x, c.y)
			title = Mat.name_of(m)
			if Mat.is_diggable(m):
				var key := Mat.resource(m)
				if not key.is_empty():
					rows.append({"type": "resources", "label": "Добыча", "items": [[key, 1, -1, true]]})
				rows.append({"type": "chips", "items": [
					["", "%s кг/м³" % Fmt.int_spaced(int(Mat.density(m)))],
					["", "прочность %s МПа" % str(Mat.strength(m))],
					["", "копать ~" + Fmt.duration(colony.dig_time(c))]]})
	rows.append({"type": "text", "text": _env_text(c)})
	return {"title": title, "subtitle": sub, "rows": rows}


func _env_text(c: Vector2i) -> String:
	var surf := world.gen.surface_y(c.x)
	var t := "%d °C · %d кПа · кислород %d%%" % [
		roundi(colony.elements.temperature(c)),
		roundi(Env.pressure(c.y, surf)),
		roundi(Env.oxygen_ratio(c.y, surf) * 100.0)]
	var g := colony.elements.gas_at(c)
	if g >= Elements.GAS_MIN:
		t += " · метан %d%%%s" % [roundi(g * 100.0), " — взрывоопасно!" if g >= Elements.GAS_EXPLOSIVE else ""]
	return t


func _update_status() -> void:
	var c := world_view.camera_cell()
	var depth := c.y - world.gen.surface_y(c.x)
	hud.set_status(("Высота %s м" % Fmt.int_spaced(-c.y)) if depth < 0 else ("Глубина %s м" % Fmt.int_spaced(depth)))
	var hungry := 0
	for u in colony.units:
		if u.satiety < 25.0:
			hungry += 1
	hud.set_resources(colony.inventory, colony.units.size(), hungry, colony.power_made, colony.power_used,
		colony.research.has("electricity"))
	hud.set_date(colony.date_text())


## Камера не уходит дальше разведанного: по бокам — куда доходили жители,
## вниз — до самых глубоких работ, вверх — чуть выше самых высоких построек.
func _clamp_camera() -> void:
	var o := Vector2(world_view.origin)
	var t := ChunkView.TILE
	var min_x := (colony.explored_min - 4 - o.x) * t
	var max_x := (colony.explored_max + 5 - o.x) * t
	var min_y := (mini(colony.highest_y, colony.home.y) - 40 - o.y) * t
	var max_y := (maxi(colony.deepest_y, colony.home.y) + 14 - o.y) * t
	camera.position = Vector2(clampf(camera.position.x, min_x, max_x), clampf(camera.position.y, min_y, max_y))


func _update_sky() -> void:
	var half_h := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var top_y := world_view.origin.y + (camera.position.y - half_h) / ChunkView.TILE
	var bottom_y := world_view.origin.y + (camera.position.y + half_h) / ChunkView.TILE
	var m := _sky.material as ShaderMaterial
	m.set_shader_parameter("alt_top", -top_y)
	m.set_shader_parameter("alt_bottom", -bottom_y)
