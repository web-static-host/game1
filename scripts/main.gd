extends Node2D
## Точка входа: собирает мир, колонию, камеру, интерфейс; режимы стройки,
## сохранение и оффлайн-прогресс.

const AUTOSAVE_SEC := 30.0
## Сколько времени отсутствия засчитывается (стимул заходить регулярно).
const OFFLINE_CAP_SEC := 1.0 * 3600.0
const SPEEDS := [1.0, 2.0, 10.0, 20.0]
## Сколько миллисекунд кадра можно отдать симуляции.
const SIM_BUDGET_MS := 30.0
## Сколько стоит секунда игры (мс), скользящее среднее — по нему режем шаг.
## Сколько игровых секунд симулировать за кадр, чтобы уложиться в бюджет (подстраивается).
var _step_cap := 2.0
var _real_speed := 1.0
const STATUS_INTERVAL := 0.2

var world: WorldData
var colony: Colony
## Все миры (Земля и планеты) и полёты; на экране — мир _planet.
var universe := Universe.new()
var _planet := "earth"
var _cameras := {}
## Сборка экспедиции: космодром, планета, экипаж, груз.
var _launch := {}
var world_view: WorldView
var camera: CameraController
var hud: Hud
var mode := Hud.Mode.LOOK
var _sky: ColorRect
## Высота земли, к которой привязан фон (y клетки): самая низкая земля на экране, сглаженно.
var _sky_ground := NAN
var _night: CanvasModulate
var _speed_idx := 0
## Средняя цена секунды игры, мс (см. _process).
var _sim_cost := 0.0
var _autosave := 0.0
var _status_timer := 0.0
var _home := Vector2i.ZERO
var _paused_at := 0.0
## Игра в фоне: пока игрок вышел, гаврики работают (оффлайн-прогресс). По умолчанию — нет.
var _background := false
## Приложение свёрнуто — симуляция стоит.
var _away := false
var _restarting := false
## Мир (отдельная игра), в который играем; пусто — старый режим одного файла.
var _world_id := ""
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
## Ширина комнаты для установки и кого отправляем в точку.
var _room_w := 6
var _send_unit := 0


## Выбранный в карточке материал для перестройки стен: id комнаты -> материал.
## На сколько метров продлевать шахту, тоннель или лифт (кнопки «Продлить»).
var _extend_len := 5
## Фильтры в списках выбора гавриков: только без пары, только по призванию.
var _pick_filters := {"single": false, "calling": false}
## На сколько метров сверлить буром.
var _drill_len := 10
## Сдвиг комнаты: куда (0 ←, 1 →, 2 ↑, 3 ↓) и на сколько.
var _move_dir_i := 0
var _move_len := 3
const MOVE_DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _wall_choice := {}

func _ready() -> void:
	# Шрифт игры — и для подписей в мире (они берут шрифт по умолчанию).
	ThemeDB.fallback_font = Fonts.bold()
	ModelSprites.enabled = bool(Settings.get_value("models"))
	_background = bool(Settings.get_value("background"))
	# Что запускаем: мир и сохранение из меню; без меню (инструменты) — один файл, как раньше.
	_world_id = str(Worlds.launch.get("world", ""))
	var meta := Worlds.meta(_world_id) if not _world_id.is_empty() else {}
	var data := {}
	if _world_id.is_empty():
		data = SaveSystem.load_data()
	elif not str(Worlds.launch.get("save", "")).is_empty():
		data = Worlds.load_save(_world_id, Worlds.launch["save"])
	var seed_value := int(data["seed"]) if data.has("seed") else int(meta.get("seed", _new_seed()))
	# Старые сохранения (без версии генерации) — на первой версии, чтобы мир не изменился.
	var gen_version := int(data.get("gen", 1)) if data.has("seed") else WorldGen.LATEST
	world = WorldData.new(WorldGen.new(seed_value, gen_version))
	colony = Colony.new(world)
	_home = Vector2i(0, world.gen.surface_y(0))
	_build_scene()
	universe.base_seed = seed_value
	_hook(universe.add_world("earth", world, colony))
	universe.arrived.connect(_on_arrived)

	var start := _home + Vector2i(0, -3)
	if data.is_empty():
		colony.disasters = bool(meta.get("disasters", true))
		colony.start_new(_home.x)
		hud.log_event("У вас 5 гавриков и пустой склад. Начните со «Сбора»: кусты с ягодами — еда, деревья и валуны — дерево и камень.", "info")
	else:
		SaveSystem.apply(data, world, colony)
		var cam: Array = data.get("camera", [])
		if cam.size() == 2:
			start = Vector2i(int(cam[0]), int(cam[1]))
		var n0 := universe.worlds.size()
		universe.load_dict(data.get("universe", {}))
		for i in range(n0, universe.worlds.size()):
			_hook(universe.worlds[i])
		for k in data.get("cameras", {}):
			var cc: Array = data["cameras"][k]
			_cameras[str(k)] = Vector2i(int(cc[0]), int(cc[1]))
		# Время отсутствия засчитывается, только когда продолжают с автосохранения
		# (вышли и вернулись), а не когда загружают старое сохранение.
		if _world_id.is_empty() or bool(Worlds.launch.get("offline", false)):
			_apply_offline(float(data.get("saved_at", 0.0)))
	hud.world_id = _world_id
	world_view.focus_cell(start)
	_update_status()
	if data.get("active", "earth") != "earth":
		_switch_world(str(data["active"]))
	# Новый мир сразу получает автосохранение — он появится в «Продолжить».
	if data.is_empty() and not _world_id.is_empty():
		_save()


## Игру закрыли (любым способом) — сохраняем последнее состояние.
func _exit_tree() -> void:
	if world != null and bool(Settings.get_value("save_on_exit")):
		_save()


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
	# Слои фона (горы, лес, холмы, облака) — картинки из assets/background/.
	for n in ["mountains_1", "mountains_2", "forest_1", "forest_2", "hills_1", "hills_2", "clouds"]:
		mat.set_shader_parameter(n, load("res://assets/background/%s.png" % n))
	mat.set_shader_parameter("world_seed", float(world.gen.world_seed % 1000))
	_sky.material = mat
	sky_layer.add_child(_sky)

	_night = CanvasModulate.new()
	add_child(_night)
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
	hud.worlds_pressed.connect(_show_worlds)
	hud.food_pressed.connect(func() -> void:
		var parts: PackedStringArray = []
		for k in RoomType.FOOD_KEYS:
			parts.append("%s %d" % [Mat.resource_name(k).to_lower(), int(colony.inventory.get(k, 0))])
		hud.log_event("Еда: " + " · ".join(parts), "info"))
	hud.build_opened.connect(func() -> void: hud.set_build_rooms(_build_room_items(), _build_tool_locks()))
	hud.home_pressed.connect(func() -> void: world_view.focus_cell(_home + Vector2i(0, -3)))
	hud.speed_selected.connect(func(i: int) -> void: _speed_idx = i)
	hud.export_pressed.connect(_export_save)
	hud.log_pressed.connect(func(at: Vector2i) -> void: world_view.focus_cell(at))
	hud.save_requested.connect(func(sid: String, name: String) -> void:
		if _world_id.is_empty():
			_save()
			hud.log_event("Игра сохранена", "good")
			return
		hud.log_event("Сохранено: %s" % _save(true, sid, name), "good"))
	hud.load_requested.connect(_load_save)
	hud.exit_requested.connect(_exit_to_menu)
	hud.science_pressed.connect(_show_science)
	hud.people_pressed.connect(_show_people)
	hud.setting_changed.connect(_on_setting)
	hud.room_options_changed.connect(_on_room_options)


func _process(delta: float) -> void:
	# Большие паузы (сворачивание) учитываются как оффлайн, а не через delta.
	# Открыто меню — игра на паузе.
	var dt := 0.0 if _away or hud.menu_open() else minf(delta, 0.25)
	# Время идёт во всех мирах сразу; ракеты летят.
	var want: float = dt * SPEEDS[_speed_idx]
	# Симуляция не съедает кадр: если на большой колонии шаг дороже бюджета, игра идёт
	# медленнее заказанной скорости, но не замирает и не медленнее ×1. Шаг подстраивается
	# по факту: кадр уложился в бюджет — шаг растёт до заказанного, нет — уменьшается.
	# (Раньше делили время кадра на шаг: постоянная часть кадра на маленьком шаге раздувала
	# «стоимость секунды», шаг не рос — ×2 на телефоне шло как ×1.)
	var step := maxf(minf(want, _step_cap), minf(want, dt))
	# На ×10 и ×20 расчёту можно чуть больше времени кадра: кадров меньше, время быстрее.
	var budget := SIM_BUDGET_MS * (1.5 if SPEEDS[_speed_idx] >= 10.0 else 1.0)
	# Сколько на деле идёт время (большая колония на слабом телефоне не успевает за ×20).
	if dt > 0.0:
		_real_speed = lerpf(_real_speed, step / dt, 0.05)
	var t0 := Time.get_ticks_usec()
	for e in universe.worlds:
		(e["colony"] as Colony).update(step)
	universe.update(step)
	if step > 0.0:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		# Шаг — по средней цене секунды игры, а не по одному кадру: редкий долгий кадр (проверка
		# доступа, первый обход после стройки) раньше сбрасывал ускорение до ×1, и оно секунду
		# ползло обратно — на большой колонии ×20 так и не включалось.
		var per := ms / step
		_sim_cost = per if _sim_cost <= 0.0 else lerpf(_sim_cost, per, 0.15)
		_step_cap = clampf(budget / _sim_cost, dt, 2.0)
	_clamp_camera()
	if _shake > 0.0:
		_shake -= delta
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * minf(1.0, _shake)
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
	_update_sky(delta)
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = STATUS_INTERVAL
		# Колония на планете вымерла (и туда никто не летит) — мира больше нет.
		for gone in universe.prune_dead():
			hud.log_event("Колония на планете %s погибла. Нужна новая экспедиция и новый корабль." % Planet.planet_name(gone), "danger")
			if gone == _planet:
				_planet = "__gone"
				_switch_world("earth")
		_update_status()
		_refresh_info()
	# Автосохранение — раз в столько минут, сколько выбрано в настройках (0 — выключено).
	var every := int(Settings.get_value("autosave_min")) * 60.0 if _world_id.is_empty() == false else AUTOSAVE_SEC
	if every > 0.0 and not _away:
		_autosave += delta
		if _autosave >= every:
			_autosave = 0.0
			_save()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Свернули — игра на паузе (а с «Игрой в фоне» — посчитаем, сколько успели).
			# Сохраняемся: свёрнутую игру система может выгрузить.
			if world != null and not _away:
				_away = true
				if bool(Settings.get_value("save_on_exit")):
					_save()
				_paused_at = Time.get_unix_time_from_system()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if world != null and _away:
				_away = false
				if _paused_at > 0.0:
					_apply_offline(_paused_at)
				_paused_at = 0.0
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# «Назад» на Android: закрывает меню игры, а если его нет — сворачивает игру.
			if hud != null:
				hud.back_pressed()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if world != null and bool(Settings.get_value("save_on_exit")):
				_save()


## Настройку поменяли в меню игры.
func _on_setting(key: String, value: Variant) -> void:
	match key:
		"models":
			ModelSprites.enabled = bool(value)
			world_view.units_layer.refresh()
		"background":
			_background = bool(value)
		"autosave_min":
			_autosave = 0.0


## Выйти в главное меню (сохранившись, если так настроено).
func _exit_to_menu(save: bool) -> void:
	if save:
		_save()
	_restarting = true
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Загрузить другое сохранение этого мира: сцена собирается заново.
func _load_save(sid: String) -> void:
	_restarting = true
	Worlds.launch = {"world": _world_id, "save": sid, "offline": false}
	get_tree().reload_current_scene()


## Сохранить: в автосохранение мира или (manual) в сохранение игрока: в слот sid (пусто —
## новый) под названием name (пусто — «Сохранение N» или прежнее имя слота).
func _save(manual := false, sid := "", name := "") -> String:
	if _restarting:
		return ""
	_cameras[_planet] = world_view.camera_cell()
	var earth: Dictionary = universe.worlds[0]
	var data := SaveSystem.serialize(earth["world"], earth["colony"], _cameras.get("earth", world_view.camera_cell()))
	data["universe"] = universe.to_dict(_cameras)
	data["active"] = _planet
	var cams := {}
	for k in _cameras:
		cams[k] = [_cameras[k].x, _cameras[k].y]
	data["cameras"] = cams
	if _world_id.is_empty():
		SaveSystem.write(data)
		return ""
	var earth_colony: Colony = earth["colony"]
	var info := {"units": earth_colony.units.size(), "date": earth_colony.date_text().split(" · ")[-1],
		"depth": maxi(0, earth_colony.deepest_y - _home.y)}
	if manual:
		var ns := Worlds.new_save_id(_world_id)
		if not sid.is_empty():
			ns[0] = sid
		info["name"] = name if not name.is_empty() else ns[1]
		Worlds.write_save(_world_id, ns[0], data, info)
		return info["name"]
	info["name"] = "Автосохранение"
	Worlds.write_save(_world_id, Worlds.AUTO, data, info)
	return info["name"]


## Сохранение — файлом в «Загрузки» телефона: его можно прислать, чтобы разобрать ошибку.
func _export_save() -> void:
	_save()
	var data := SaveSystem.load_data(Worlds.save_path(_world_id, Worlds.AUTO)) if not _world_id.is_empty() else SaveSystem.load_data()
	var name := "gavriki_%s.json" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dirs := [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), OS.get_user_data_dir()]
	for d in dirs:
		if str(d).is_empty():
			continue
		var path := str(d).path_join(name)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(data))
			f.close()
			hud.show_message("Сохранение в файл", "Файл сохранён:\n%s\n\nЕго можно прислать (например, загрузить на GitHub рядом со скриншотами)." % path)
			return
	hud.show_message("Сохранение в файл", "Не удалось записать файл: нет доступа к памяти телефона.")


## События колонии — в журнал; с других планет — только важное, с названием планеты.
func _hook(e: Dictionary) -> void:
	var c: Colony = e["colony"]
	var planet: String = e["planet"]
	c.event_logged.connect(func(t: String, k: String) -> void:
		if c == colony:
			hud.log_event(t, k, c.log_at)
		elif k == "danger" or k == "good":
			hud.log_event("[%s] %s" % [Planet.planet_name(planet), t], k))
	c.quaked.connect(func(mag: int) -> void:
		if c == colony:
			_shake = 1.2 + mag * 0.8)


func _on_arrived(planet: String, c: Colony, new_world: bool) -> void:
	if new_world:
		_hook(universe.entry(planet))
	hud.log_event("Ракета долетела: %s! Откройте «Планеты», чтобы перейти туда." % Planet.planet_name(planet), "good")
	if new_world and c == colony:
		pass


## Перейти в мир планеты: экран, небо и журнал — его.
func _switch_world(planet: String) -> void:
	var e := universe.entry(planet)
	if e.is_empty() or planet == _planet:
		return
	_cameras[_planet] = world_view.camera_cell()
	_to_look()
	hud.close_overlays()
	remove_child(world_view)
	world_view.queue_free()
	world = e["world"]
	colony = e["colony"]
	_planet = planet
	_home = colony.home
	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(world, colony, camera)
	world_view.focus_cell(_cameras.get(planet, colony.home + Vector2i(0, -3)))
	_apply_planet_sky()
	_sky_ground = NAN
	_update_status()
	hud.log_event("%s: гавриков %d" % [Planet.planet_name(planet), colony.units.size()], "info")


## «Планеты»: где колонии и сколько в них гавриков, какие ракеты летят и когда сядут.
func _show_worlds() -> void:
	_info_target = []
	var items := []
	for e in universe.worlds:
		var c: Colony = e["colony"]
		var p: String = e["planet"]
		var here: bool = p == _planet
		var kids := c.units.filter(func(u: Unit) -> bool: return u.child).size()
		items.append({"name": Planet.planet_name(p) + (" — вы здесь" if here else ""),
			"info": "гавриков %d%s · %s" % [c.units.size(), (" (детей %d)" % kids) if kids > 0 else "",
				Planet.data(p)["desc"]],
			"button": "" if here else "Перейти", "pick": func() -> void:
				_switch_world(p)})
	for f in universe.flights:
		var days := int(ceilf(float(f["left"]) / Colony.DAY))
		var cargo := 0
		for k in f["cargo"]:
			cargo += int(f["cargo"][k])
		items.append({"name": "Летит: %s" % Planet.planet_name(f["planet"]),
			"info": "гавриков %d, груза %d · сядет через %d дн." % [f["crew"].size(), cargo, days]})
	hud.show_panel({"title": "Планеты", "subtitle": "время идёт на всех планетах сразу",
		"rows": [{"type": "text", "text": "Ракеты собирают на космодроме (технология «Ракета»): до 10 гавриков и 200 груза. Подбирайте экипаж под планету: на холодные — стойких к холоду (синих), на жаркие — к жаре (красных). Ошибётесь — колония может погибнуть, тогда нужна новая ракета."}],
		"controls": [{"type": "people", "label": "Колонии и полёты:", "items": items, "empty": ""}],
		"actions": [["Закрыть", func() -> void: hud.hide_info()]]})


## Космодром: что нужно на ракету и что есть.
func _rocket_rows(p: Project, rows: Array) -> void:
	if not p.rocket.is_empty():
		rows.append({"type": "text", "text": "Ракета на столе: %s двигатель — летит на %s. Нажмите «Запустить»: выберите планету, экипаж (до 10) и груз (до 200)." % [
			Planet.engine_name(p.rocket), ", ".join(Planet.ORDER.filter(func(id: String) -> bool: return Colony.rocket_reaches(p.rocket, id)).map(
				func(id: String) -> String: return Planet.planet_name(id)))]})
		return
	if p.phase == Project.Phase.EQUIP and not p.equip_rocket.is_empty():
		return
	for engine in ["chem", "nuclear"]:
		if engine == "nuclear" and not colony.research.has("nuclear_engine"):
			rows.append({"type": "text", "text": "Ядерная ракета (до Юпитера, Сатурна, Урана и Нептуна) — после «Ядерного двигателя»."})
			continue
		rows.append({"type": "resources", "label": "Ракета, %s двигатель:" % Planet.engine_name(engine), "items": _cost_items(RoomType.ROCKET_COST[engine])})
	var err := colony.launchpad_error(p)
	if not err.is_empty():
		rows.append({"type": "warning", "text": err})


## Запуск, шаг 1: куда лететь.
func _launch_pick_planet(pad: Project) -> void:
	_info_target = []
	_launch = {"pad": pad, "planet": "", "crew": [], "cargo": {}}
	var items := []
	for id in Planet.ORDER:
		var d := Planet.data(id)
		var ok := Colony.rocket_reaches(pad.rocket, id)
		var col := universe.entry(id)
		var info := "%s Лететь %d мес.%s" % [d["desc"], int(d["travel"]),
			(" · там колония: гавриков %d" % (col["colony"] as Colony).units.size()) if not col.is_empty() else ""]
		if not ok:
			info = "Нужен %s двигатель · %s" % [Planet.engine_name(d["engine"]), info]
		items.append({"name": d["name"], "info": info, "button": "Сюда" if ok else "", "pick": func() -> void:
			_launch["planet"] = id
			_launch_crew()})
	hud.show_panel({"title": "Запуск: куда лететь?", "subtitle": "ракета: %s двигатель" % Planet.engine_name(pad.rocket),
		"controls": [{"type": "people", "label": "Планеты:", "items": items, "empty": ""}],
		"actions": [["Назад", func() -> void: _show_project(pad)]]})


## Запуск, шаг 2: экипаж (до 10).
func _launch_crew() -> void:
	_info_target = []
	var crew: Array = _launch["crew"]
	var planet: String = _launch["planet"]
	var hot: bool = float(Planet.data(planet)["under"]) > 30.0
	var items := []
	for u in colony.units:
		if u.child:
			continue
		var on := crew.has(u)
		var stat := "жара" if hot else "холод"
		items.append({"looks": Genetics.looks(u.genome), "name": _name_sex(u),
			"info": "%s · %s %d%% · %s%s" % [_family_text(u), stat, roundi(u.stat("heat" if hot else "cold") * 100),
				colony.role_name(u).to_lower(), " · СУПЕР-ГАВРИК" if u.invulnerable() else ""],
			"button": "Убрать" if on else "Взять", "style": "danger" if on else "", "pick": func() -> void:
				if crew.has(u):
					crew.erase(u)
				elif crew.size() < RoomType.SHIP_BEDS:
					crew.append(u)
				else:
					hud.log_event("В ракете — до %d гавриков" % RoomType.SHIP_BEDS, "warning")
				_launch_crew()})
	hud.show_panel({"title": "Экипаж на %s: %d из %d" % [Planet.planet_name(planet), crew.size(), RoomType.SHIP_BEDS],
		"subtitle": Planet.data(planet)["desc"],
		"controls": [{"type": "people", "label": "Кто летит (важно: %s):" % ("стойкость к жаре" if hot else "стойкость к холоду"),
			"items": items, "empty": "Нет взрослых гавриков."}],
		"actions": [["Дальше: груз", _launch_cargo, "primary"], ["Назад", func() -> void: _launch_pick_planet(_launch["pad"])]]})


## Запуск, шаг 3: груз (до 200) — и старт.
func _launch_cargo() -> void:
	_info_target = []
	var cargo: Dictionary = _launch["cargo"]
	var controls := []
	var keys: Array = colony.inventory.keys()
	keys.sort()
	for k in keys:
		var have: int = colony.inventory[k]
		if have <= 0 or RoomType.PIPED.has(k) or RoomType.BULK.has(k):
			continue
		controls.append({"label": "%s (есть %d)" % [Mat.resource_name(k), have], "value": int(cargo.get(k, 0)), "min": 0,
			"max": mini(have, RoomType.SHIP_HOLD), "step": 10, "changed": func(v: int) -> void:
				cargo[k] = v
				hud.refresh_panel(_launch_cargo_spec())})
	var spec := _launch_cargo_spec()
	spec["controls"] = controls
	spec["controls_first"] = true
	spec["actions"] = [["Старт!", _do_launch, "primary"], ["Назад", _launch_crew]]
	hud.show_panel(spec)


func _launch_cargo_spec() -> Dictionary:
	var total := 0
	for k in _launch["cargo"]:
		total += int(_launch["cargo"][k])
	return {"title": "Груз: %d из %d" % [total, RoomType.SHIP_HOLD],
		"subtitle": "экипаж %d · на %s" % [_launch["crew"].size(), Planet.planet_name(_launch["planet"])],
		"rows": [{"type": "text", "text": "Растений и озёр там нет: еды хватит только привезённой и с ферм (на грядки нужно дерево). Для тепла — дерево или уголь для очагов. Корабль — жильё на 10, с воздухом, теплом и светом; копайте вниз прямо из него."}]}


func _do_launch() -> void:
	var cargo := {}
	for k in _launch["cargo"]:
		if int(_launch["cargo"][k]) > 0:
			cargo[k] = int(_launch["cargo"][k])
	var flight := colony.launch(_launch["pad"], _launch["planet"], _launch["crew"], cargo)
	if flight.has("error"):
		hud.log_event(flight["error"], "warning")
		return
	universe.send(flight)
	_launch = {}
	_show_worlds()


## Небо планеты: свой оттенок; на других планетах нет лесов, холмов с травой и облаков.
func _apply_planet_sky() -> void:
	var m := _sky.material as ShaderMaterial
	var earth := _planet == "earth"
	for n in ["forest_1", "forest_2", "hills_1", "hills_2", "clouds"]:
		m.set_shader_parameter(n, load("res://assets/background/%s.png" % n) if earth else _blank_tex())
	var tint: Color = Planet.data(_planet)["sky"]
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))


var _blank: ImageTexture
func _blank_tex() -> ImageTexture:
	if _blank == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_blank = ImageTexture.create_from_image(img)
	return _blank


func _apply_offline(since_unix: float) -> void:
	var away := Time.get_unix_time_from_system() - since_unix
	if since_unix <= 0.0 or away < 60.0 or not _background:
		return
	var simulated := minf(away, OFFLINE_CAP_SEC)
	var inv_before := colony.inventory.duplicate()
	var built_before := _done_count()
	var units_before := colony.units.size()
	var dug := colony.advance_offline(simulated)
	for e in universe.worlds:
		if e["colony"] != colony:
			(e["colony"] as Colony).advance_offline(simulated)
	universe.update(simulated)
	var lines: PackedStringArray = ["Вас не было %s." % Fmt.duration(away)]
	if away > OFFLINE_CAP_SEC:
		lines.append("Гаврики работали первые %s — дальше им нужны ваши указания." % Fmt.duration(OFFLINE_CAP_SEC))
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
		lines.append("Голодают гавриков: %d — нужна еда (ягоды, ферма)." % hungry)
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


func _set_mode(m: int, room_width := 0) -> void:
	mode = m
	if room_width > 0:
		_room_w = room_width
	camera.paint_mode = m in [Hud.Mode.TUNNEL, Hud.Mode.ROOM, Hud.Mode.BRIDGE, Hud.Mode.MINE, Hud.Mode.LIFT, Hud.Mode.CARGO_LIFT, Hud.Mode.DRILL, Hud.Mode.DRILL_LIFT, Hud.Mode.PROBE]
	_clear_preview()
	if m != Hud.Mode.SEND:
		_select(null, null)


## Разовый режим закончен — снова обычный осмотр.
func _to_look() -> void:
	hud.set_mode(Hud.Mode.LOOK)
	_set_mode(Hud.Mode.LOOK)


# --- Нажатия ---------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if mode == Hud.Mode.SEND:
		var su := colony.unit_by_id(_send_unit)
		_to_look()
		if su != null:
			var to = colony.send_unit(su, c)
			if to == null:
				hud.log_event("%s не может туда пройти" % su.name, "warning")
			else:
				hud.log_event("%s идёт на разведку" % su.name, "info")
				_select(su, null)
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
	hud.close_overlays()
	var fx = _feature_near(c)
	if fx != null and colony.is_explored(c.x):
		_show_feature(fx)
		return
	hud.show_panel(_cell_spec(c))


const FEATURE_ACTIONS := {
	WorldGen.FEATURE_TREE: ["Дерево", "Срубить", "Срубить все рядом"],
	WorldGen.FEATURE_BOULDER: ["Валун", "Разбить", "Разбить все рядом"],
	WorldGen.FEATURE_BUSH: ["Куст с ягодами", "Собрать ягоды", "Собрать со всех рядом"],
}
const NEAR_RADIUS := 15


## Карточка дерева, валуна или куста: что даст и кнопки сбора.
func _show_feature(x: int) -> void:
	var f := world.feature_at(x)
	var names: Array = FEATURE_ACTIONS[f]
	var marked := world.feature_marks.has(x)
	var rows := []
	match f:
		WorldGen.FEATURE_TREE:
			rows.append(_progress("Рост", world.growth(x)))
		WorldGen.FEATURE_BUSH:
			rows.append(_progress("Ягоды", world.berries(x) / WorldData.BUSH_BERRIES,
				"%d из %d" % [floori(world.berries(x)), int(WorldData.BUSH_BERRIES)], Color(0.85, 0.3, 0.35)))
			rows.append({"type": "text", "text": "Куст остаётся — ягоды отрастают."})
	var y: Array = colony.feature_yield(x)
	if y[1] > 0:
		rows.append({"type": "resources", "label": "Даст", "items": [[y[0], y[1], -1, true]]})
	rows.append({"type": "text", "text": "Добытое ляжет здесь же, гаврики отнесут его на склад."})
	var actions := [
		["Отменить" if marked else names[1], func() -> void:
			var err := colony.toggle_harvest(x)
			if not err.is_empty():
				hud.log_event(err, "warning")
			_show_feature(x), "" if marked else "primary"],
		[names[2], func() -> void:
			var n := 0
			for nx in range(x - NEAR_RADIUS, x + NEAR_RADIUS + 1):
				if world.feature_at(nx) == f and not world.feature_marks.has(nx) and colony.is_explored(nx) \
						and colony.toggle_harvest(nx).is_empty():
					n += 1
			hud.log_event("Отмечено на сбор: %d" % n, "info")
			_show_feature(x)],
	]
	hud.show_panel({"title": names[0], "subtitle": "отмечено на сбор" if marked else "", "rows": rows, "actions": actions})


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
	# Бур-лифт — одна постройка: касание по его лифту открывает бур-лифт.
	if p != null and p.kind == Project.Kind.LIFT and p.link_id != 0 and colony.project_by_id(p.link_id) != null:
		p = colony.project_by_id(p.link_id)
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
	var spec := _unit_spec(u)
	if not u.child:
		spec["actions"] = [["Отправить", func() -> void:
			_send_unit = u.id
			_set_mode(Hud.Mode.SEND)
			hud.hide_info()
			hud.set_hint("Нажмите на карте, куда отправить: %s" % u.name), "primary"],
			["Работа", func() -> void: _pick_workplace(u)],
			["Гаврики", _show_people]]
	hud.show_panel(spec)


## Выбор места работы для гаврика: где есть места и насколько он там хорош.
func _pick_workplace(u: Unit) -> void:
	# Список выбора не обновляем каждую секунду — иначе его перезапишет карточка.
	_info_target = []
	var items := []
	for role in [[Unit.Prof.BUILDER, "в первую очередь идёт на стройки: копает, строит, обустраивает, чинит; носит только то, без чего его работа стоит прямо сейчас"],
			[Unit.Prof.MINER, "сначала шахты: копает и крепит, дерево на крепь носит сам, если нет свободных подсобных; на других стройках только копает"],
			[Unit.Prof.HAULER, "в первую очередь носит: материалы на стройки, сырьё в мастерские, добычу и продукцию на склад"],
			[Unit.Prof.ANY, "стройка, если есть место, иначе переноска"]]:
		var prof: int = role[0]
		var here := u.workplace == 0 and u.profession == prof
		items.append({"name": Unit.PROF_NAMES[prof] + (" — сейчас" if here else ""), "info": role[1],
			"button": "Выбрать", "pick": func() -> void:
				colony.set_profession(u, prof)
				_show_unit(u)})
	var places := colony.projects.filter(func(p: Project) -> bool: return colony.is_workplace(p))
	places.sort_custom(func(a: Project, b: Project) -> bool: return colony.suitability(u, a) > colony.suitability(u, b))
	for p: Project in places:
		var taken := colony.assigned_to(p).size()
		var here := u.workplace == p.id
		items.append({"name": colony.workplace_name(p) + (" — здесь" if here else ""),
			"info": "мест %d/%d · подходит на %d%% · %s%s" % [taken, colony.work_slots(p), roundi(colony.suitability(u, p) * 100),
				_fit_text(u, colony.work_task(p)), _calling_text(u, colony.work_task(p))],
			"button": "Сюда", "pick": func() -> void:
				var err := colony.assign_work(u, p)
				if not err.is_empty():
					hud.log_event(err, "warning")
				_show_unit(u)})
	hud.show_panel({"title": "Работа: " + u.name, "subtitle": "сейчас: " + colony.role_name(u).to_lower(),
		"controls": [{"type": "people", "label": "Куда поставить (лучшие места — сверху):", "items": items,
			"empty": "Нет комнат для работы: ферма, лаборатория, печь, кузница, склад, пристань."}],
		"actions": [["Назад", func() -> void: _show_unit(u)]]})


static func _need_bar(label: String, v: float) -> Dictionary:
	var col := Color(0.45, 0.82, 0.4)
	if v < 25.0:
		col = Color(0.9, 0.3, 0.25)
	elif v < 50.0:
		col = Color(0.95, 0.65, 0.2)
	return {"type": "progress", "label": label, "value": v / 100.0, "color": col, "text": "%d%%" % roundi(v)}


func _unit_spec(u: Unit) -> Dictionary:
	var g := u.genome
	var who := "♂ мужчина" if u.sex == Unit.Sex.MALE else "♀ женщина"
	if u.child:
		who = "%s %s, вырастет через %s" % ["♂" if u.sex == Unit.Sex.MALE else "♀",
			"малыш" if u.age < Unit.CHILD_TIME * 0.5 else "подросток", Colony.game_span(Unit.CHILD_TIME - u.age)]
	var task: String = Unit.TASK_NAMES[u.task]
	if u.gather_room != 0:
		task += " для склада"
	var rows := []
	if not g.is_empty():
		var tags := []
		var age_line := "Возраст: %s · %d-е поколение" % [u.age_text(), u.generation]
		tags.append([age_line, Color.WHITE])
		if u.is_elder():
			tags.append(["Пожилой — работает и ходит медленнее, детей не будет", Color(1.0, 0.75, 0.5)])
		if u.irradiated:
			tags.append(["Облучён ураном — живёт на 10% меньше, дети будут мутантами", Color(0.6, 1.0, 0.35)])
		var pers: String = g.get("personality", "")
		if not pers.is_empty():
			tags.append(["Характер: " + pers, Color.WHITE])
		if Genetics.is_super(g):
			tags.append(["СУПЕР-ГАВРИК — все характеристики ×2, неуязвим: умирает только от старости", Color(0.3, 0.9, 0.85)])
		var mt := Genetics.mutation_text(g)
		if not mt.is_empty():
			var rarity_cols := [Color(0.6, 0.85, 0.6), Color(0.5, 0.75, 1.0), Color(0.8, 0.6, 1.0), Color(1.0, 0.8, 0.3)]
			tags.append([mt, rarity_cols[maxi(0, Genetics.rarity(g))]])
		var ab := Genetics.ability_text(g)
		if not ab.is_empty():
			tags.append(["Умеет: " + ab, Hud.MUTED])
		tags.append(["Занятие: " + colony.role_name(u).to_lower(), Hud.MUTED])
		if u.calling > 0:
			tags.append(["Работа по призванию: навык растёт быстрее, настроение лучше", Color(0.6, 0.9, 0.6)])
		elif u.calling < 0:
			tags.append(["Работа не по душе: навык растёт медленнее, настроение хуже", Color(1.0, 0.7, 0.45)])
		rows.append({"type": "portrait", "looks": Genetics.looks(g), "tags": tags})
	rows.append_array([_need_bar("Сытость", u.satiety), _need_bar("Настроение", u.mood())])
	if u.health < 99.5:
		rows.append(_need_bar("Здоровье", u.health))
	if u.task == Unit.Task.HAUL and u.carry_amount > 0:
		rows.append({"type": "resources", "label": "Несёт", "items": [[u.carry_key, u.carry_amount, -1, true]]})
	if not u.stats.is_empty():
		rows.append({"type": "section", "text": "Характеристики (100% — обычный гаврик)"})
		var items := []
		for k in Genetics.STATS:
			var v: float = u.stat(k)
			items.append([Genetics.STAT_NAMES[k], v, v >= 1.0 if k != "appetite" else v <= 1.0])
		rows.append({"type": "stats", "items": items})
	if not u.child:
		var skills := []
		for k in ["dig", "build", "gather", "farm", "science"]:
			skills.append(["", "%s %d" % [Unit.SKILL_NAMES[k], u.level(k)]])
		rows.append({"type": "chips", "label": "Навыки", "items": skills})
	# Семья и знакомые.
	var family := []
	if u.partner_id != 0:
		var partner := colony.unit_by_id(u.partner_id)
		if partner != null:
			family.append(["people", "пара: " + partner.name])
	if not u.mother_name.is_empty() or not u.father_name.is_empty():
		var parents: PackedStringArray = []
		for n in [u.mother_name, u.father_name]:
			if not n.is_empty():
				parents.append(n)
		family.append(["", "родители: " + " и ".join(parents)])
	var kids: PackedStringArray = []
	for o in colony.units:
		if o.mother_id == u.id or o.father_id == u.id:
			kids.append(o.name)
	if not kids.is_empty():
		family.append(["", "дети: " + ", ".join(kids)])
	if not u.child:
		var friends: PackedStringArray = []
		for f in colony.best_friends(u):
			friends.append("%s %d%%" % [f[0].name, roundi(minf(1.0, f[1] / Colony.ACQUAINT_PAIR) * 100)])
		if not friends.is_empty():
			family.append(["", "знакомые: " + ", ".join(friends)])
	if not family.is_empty():
		rows.append({"type": "chips", "label": "Семья", "items": family})
	var extra := [["home", "кровать есть" if u.bed_room != 0 else "нет кровати",
		Color.WHITE if u.bed_room != 0 else Color(1.0, 0.6, 0.5)]]
	if u.pregnancy >= 0.0:
		extra.append(["", "ждёт ребёнка", Color(1.0, 0.7, 0.8)])
	if u.child:
		extra.append(["", "ест вдвое больше"])
	if u.state == Unit.State.WORK and colony.light_factor(u) < 1.0:
		extra.append(["", "темно — работает медленнее (%d%%)" % roundi(colony.light_factor(u) * 100.0), Color(1.0, 0.8, 0.5)])
	var cold := Colony.cold_limit(u)
	if colony.elements.temperature(u.cell()) < cold:
		extra.append(["", "мёрзнет", Color(0.6, 0.8, 1.0)])
	rows.append({"type": "chips", "items": extra})
	return {"title": u.name, "subtitle": "%s · %s" % [who, task], "rows": rows}


## Сдвиг комнаты: куда и на сколько; рамка нового места — на карте.
func _show_move(p: Project) -> void:
	var dir: Vector2i = MOVE_DIRS[_move_dir_i]
	_move_len = clampi(_move_len, 1, Colony.move_max(p, dir))
	var nr := Rect2i(p.rect.position + dir * _move_len, p.rect.size)
	var check: Array = colony.move_check(p, dir, _move_len)
	var s := world_view.structures
	s.preview = nr
	s.preview_ok = (check[0] as String).is_empty()
	s.preview_text = "→ %d м" % _move_len
	var rows := []
	rows.append({"type": "text", "text": "Комнату сдвигают за раз вбок до её ширины (%d м), вверх и вниз — до 3 м. Работают строители, нужны материалы; порода на новом месте выкапывается. Всё внутри едет вместе с комнатой." % p.rect.size.x})
	rows.append({"type": "resources", "label": "Материалы", "items": _cost_items(colony.move_cost(p))})
	if not (check[0] as String).is_empty():
		rows.append({"type": "warning", "text": check[0]})
	elif not (check[1] as String).is_empty():
		rows.append({"type": "warning", "text": check[1]})
	var controls := [
		{"label": "Куда", "value": _move_dir_i, "min": 0, "max": 3, "options": ["← влево", "→ вправо", "↑ вверх", "↓ вниз"],
			"changed": func(v: int) -> void:
				_move_dir_i = v
				_show_move(p)},
		{"label": "На, м", "value": _move_len, "min": 1, "max": Colony.move_max(p, dir),
			"changed": func(v: int) -> void:
				_move_len = v
				_show_move(p)},
	]
	var go := func() -> void:
		var err := colony.start_move(p, dir, _move_len)
		if not err.is_empty():
			hud.log_event(err, "warning")
		world_view.structures.preview = Rect2i()
		_show_project(p)
	var actions := [["Сдвинуть", func() -> void:
		var c: Array = colony.move_check(p, dir, _move_len)
		if not (c[0] as String).is_empty():
			hud.log_event(c[0], "warning")
		elif not (c[1] as String).is_empty():
			hud.ask("Сдвиг комнаты", c[1], "Продолжить", go)
		else:
			go.call(), "primary"],
		["Назад", func() -> void:
			world_view.structures.preview = Rect2i()
			_show_project(p)]]
	hud.show_panel({"title": "Сдвинуть: %s" % p.title(), "subtitle": "", "rows": rows, "controls": controls,
		"controls_first": true, "actions": actions})


func _show_project(p: Project) -> void:
	var actions := []
	var controls := []
	if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD or p.phase == Project.Phase.EQUIP:
		actions.append(["Продолжить" if p.paused else "Пауза", func() -> void:
			colony.set_paused(p, not p.paused)
			_show_project(p)])
		if (p.kind == Project.Kind.MINE or p.kind == Project.Kind.TUNNEL or p.kind == Project.Kind.DRILL) and p.phase == Project.Phase.DIG \
				or p.kind == Project.Kind.BRIDGE and p.phase == Project.Phase.BUILD:
			# Шахту, тоннель и мост можно остановить в любой момент: готовые метры остаются.
			actions.append(["Остановить", func() -> void:
				colony.cancel_project(p)
				if colony.projects.has(p):
					_show_project(p)
				else:
					_select(null, null), "danger"])
		else:
			actions.append(["Отменить", func() -> void:
				colony.cancel_project(p)
				_select(null, null), "danger"])
		controls.append(_workers_stepper(p.workers, func(v: int) -> void: p.workers = v))
	if p.purpose == RoomType.FORGE and p.phase == Project.Phase.DONE:
		controls.append_array(_forge_controls(p))
	# Приоритет: бригада бросает другие стройки и идёт сюда.
	if colony.can_prioritize(p):
		actions.push_front(["Снять приоритет" if p.priority else "Приоритет", func() -> void:
			colony.set_priority(p, not p.priority)
			_show_project(p), "" if p.priority else "primary"])
	if p.phase == Project.Phase.DONE and p.paused:
		actions.append(["Продолжить", func() -> void:
			colony.set_paused(p, false)
			_show_project(p)])
	if p.kind == Project.Kind.ROOM and p.phase == Project.Phase.DONE and not p.repairing \
			and p.purpose != RoomType.SHIP and p.purpose != RoomType.LAUNCHPAD:
		actions.append(["Сдвинуть", func() -> void: _show_move(p)])
	if p.phase == Project.Phase.DONE:
		if p.repairing:
			controls.append(_workers_stepper(p.workers, func(v: int) -> void: p.workers = v))
			actions.append(["Отменить сдвиг" if p.move_dir != Vector2i.ZERO else "Отменить ремонт", func() -> void:
				colony.cancel_project(p)
				_show_project(p)])
		elif p.wear >= 0.05:
			actions.append(["Ремонт", func() -> void:
				if colony.start_repair(p):
					_show_project(p)
				else:
					hud.log_event(colony.repair_error(p), "warning"), "primary"])
		# Геоскважина: куда пустить зонд; идущий — пауза и остановка.
		if p.kind == Project.Kind.PROBE:
			if colony.probing(p):
				if not p.paused:
					actions.push_front(["Пауза", func() -> void:
						colony.set_paused(p, true)
						_show_project(p)])
				actions.push_front(["Остановить", func() -> void:
					colony.stop_probe(p)
					_show_project(p), "danger"])
			else:
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]:
					var label: String = {Vector2i.LEFT: "← Влево", Vector2i.DOWN: "↓ Вниз", Vector2i.UP: "↑ Вверх", Vector2i.RIGHT: "Вправо →"}[d]
					actions.push_front([label, func() -> void:
						var err := colony.start_probe(p, d)
						if not err.is_empty():
							hud.log_event(err, "warning")
						_show_project(p)])
		# Бур: куда и сколько сверлить; сверлящий — пауза и остановка.
		if p.kind == Project.Kind.DRILL:
			if colony.drilling(p):
				if not p.paused:
					actions.push_front(["Пауза", func() -> void:
						colony.set_paused(p, true)
						_show_project(p)])
				actions.push_front(["Остановить", func() -> void:
					colony.stop_drill(p)
					_show_project(p), "danger"])
			else:
				controls.append({"label": "Сверлить, м", "value": _drill_len, "min": 1, "max": Colony.DRILL_MAX,
					"changed": func(v: int) -> void: _drill_len = v})
				# Бур-лифт — только вниз: лифт идёт следом.
				for d: Vector2i in ([Vector2i.DOWN] if p.link_id != 0 else [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]):
					var label: String = {Vector2i.LEFT: "← Влево", Vector2i.DOWN: "↓ Вниз", Vector2i.RIGHT: "Вправо →"}[d]
					actions.push_front([label, func() -> void:
						var err := colony.start_drill(p, d, _drill_len)
						if not err.is_empty():
							hud.log_event(err, "warning")
						_show_project(p), "primary"])
		# Шахту, тоннель и лифт продлевают: продолжение копают и сливают с этой постройкой.
		var dirs := Colony.extend_dirs(p)
		if not dirs.is_empty() and not p.repairing:
			var ext := colony.extension_of(p)
			if ext != null:
				actions.append(["К продолжению", func() -> void: _select(null, ext)])
			else:
				controls.append({"label": "Продлить на, м", "value": _extend_len, "min": 1, "max": Colony.EXTEND_MAX,
					"changed": func(v: int) -> void: _extend_len = v})
				# push_front переворачивает порядок: идём справа налево, чтобы «← Продлить» встал слева.
				dirs.reverse()
				for d: Vector2i in dirs:
					var label: String = {Vector2i.LEFT: "← Продлить", Vector2i.DOWN: "Продлить ↓", Vector2i.RIGHT: "Продлить →"}[d]
					actions.push_front([label, func() -> void:
						var err := colony.extend_error(p, d, _extend_len)
						if not err.is_empty():
							hud.log_event(err, "warning")
							return
						var q := colony.extend_project(p, d, _extend_len)
						if q != null:
							_select(null, q), "primary"])
		if not colony.drilling(p):
			actions.append(["Снести", func() -> void:
				var err := colony.demolish_error(p)
				if not err.is_empty():
					hud.log_event(err, "warning")
					return
				colony.demolish(p)
				_select(null, null), "danger"])
	# Свет — во всей комнате сразу: включить, выключить или вернуть «сам».
	if colony.lightable(p) and colony.research.has("electricity"):
		if p.light != -1:
			actions.append(["Свет: сам", func() -> void:
				p.light = -1
				_show_project(p)])
		actions.append(["Выключить свет" if p.lit or p.light == 1 else "Включить свет", func() -> void:
			p.light = 0 if p.lit or p.light == 1 else 1
			colony.relight()
			_show_project(p)])
	var current := RoomType.current_purpose(p)
	var preview := {"v": maxi(current, 1)}
	if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM and p.purpose != RoomType.SHIP:
		if RoomType.is_store(p.purpose):
			controls.append(_storage_control(p))
		# Готовая комната: выбор назначения (только изученные).
		var purposes := []
		for t in range(1, RoomType.NAMES.size()):
			# Газовый генератор — в списке сразу за обычным.
			if t == RoomType.GAS_GEN:
				continue
			if colony.research.has(RoomType.REQUIRES.get(t, "")):
				purposes.append(t)
			if t == RoomType.GENERATOR and colony.research.has(RoomType.REQUIRES[RoomType.GAS_GEN]):
				purposes.append(RoomType.GAS_GEN)
			# Очаг — с каменными или (после обжига кирпича) кирпичными печами.
			if t == RoomType.HEARTH and colony.research.has(RoomType.REQUIRES[RoomType.HEARTH_BRICK]):
				purposes.append(RoomType.HEARTH_BRICK)
			# Газовые котлы ставят только на готовый очаг.
			if t == RoomType.HEARTH and p.purpose == RoomType.HEARTH and colony.research.has(RoomType.REQUIRES[RoomType.HEARTH_GAS]):
				purposes.append(RoomType.HEARTH_GAS)
		controls.append({
			"label": "Назначение", "value": maxi(0, purposes.find(preview["v"])), "min": 0, "max": purposes.size() - 1,
			"options": purposes.map(func(t: int) -> String: return RoomType.purpose_name(t)),
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
		# Космодром: собрать ракету, запустить готовую.
		if p.purpose == RoomType.LAUNCHPAD:
			if not p.rocket.is_empty():
				actions.push_front(["Запустить", func() -> void: _launch_pick_planet(p), "primary"])
			else:
				if colony.research.has("nuclear_engine"):
					actions.push_front(["Ядерная ракета", func() -> void:
						var err := colony.start_rocket(p, "nuclear")
						if not err.is_empty():
							hud.log_event(err, "warning")
						_show_project(p), "primary"])
				actions.push_front(["Собрать ракету", func() -> void:
					var err := colony.start_rocket(p, "chem")
					if not err.is_empty():
						hud.log_event(err, "warning")
					_show_project(p), "primary"])
		# Стены можно перестроить из другого материала (дерево → камень и т. п.).
		var mats := colony.available_materials()
		if mats.size() > 1:
			var cur_mat: String = _wall_choice.get(p.id, p.material)
			controls.append({"label": "Стены", "value": maxi(0, mats.find(cur_mat)), "min": 0, "max": mats.size() - 1,
				"options": mats.map(func(m: String) -> String: return Project.MATERIALS[m][0]),
				"changed": func(i: int) -> void:
					_wall_choice[p.id] = mats[i]
					hud.refresh_panel(_project_spec(p, preview["v"])),
			})
			actions.append(["Перестроить стены", func() -> void:
				var m: String = _wall_choice.get(p.id, p.material)
				var err := colony.material_error(p, m)
				if not err.is_empty():
					hud.log_event(err if m != p.material else "Выберите другой материал стен (переключатель «Стены»)", "warning")
				elif colony.change_material(p, m):
					_wall_choice.erase(p.id)
					_show_project(p)])
		# Каменный очаг можно переложить кирпичом.
		if colony.is_hearth_upgrade(p, RoomType.HEARTH_BRICK) and colony.research.has(RoomType.REQUIRES[RoomType.HEARTH_BRICK]):
			actions.push_front(["Кирпичные печи", func() -> void:
				if colony.set_purpose(p, RoomType.HEARTH_BRICK):
					_show_project(p), "primary"])
		# На очаг можно поставить кирпичные газовые котлы.
		if colony.is_hearth_upgrade(p, RoomType.HEARTH_GAS) and colony.research.has(RoomType.REQUIRES[RoomType.HEARTH_GAS]):
			actions.push_front(["Газовые котлы", func() -> void:
				if colony.set_purpose(p, RoomType.HEARTH_GAS):
					_show_project(p), "primary"])
	if colony.is_workplace(p):
		controls.push_front(_workers_list(p))
		actions.push_front(["Назначить", func() -> void: _pick_worker(p), "primary"])
	_info_target = ["project", p.id, preview["v"]]
	var spec := _project_spec(p, preview["v"])
	spec["actions"] = actions
	spec["controls"] = controls
	spec["controls_first"] = RoomType.is_store(p.purpose) and p.phase == Project.Phase.DONE
	hud.show_panel(spec)


## Имя с полом: «Анна ♀» — чтобы сразу видеть, кого с кем сводить.
func _name_sex(u: Unit) -> String:
	return "%s · %s" % [u.name, "жен." if u.sex == Unit.Sex.FEMALE else "муж."]


## Семейное положение: пара или без пары (дети, беременность).
func _family_text(u: Unit) -> String:
	if u.child:
		return "ребёнок"
	var partner := colony.unit_by_id(u.partner_id) if u.partner_id != 0 else null
	var out := ("пара: " + partner.name) if partner != null else ("без пары" if not u.is_elder() else "без пары (пожилой)")
	if u.pregnancy >= 0.0:
		out += ", ждёт ребёнка"
	return out


## Нужные для работы характеристики гаврика: «сила 130% + выносливость 90%».
func _fit_text(u: Unit, task: int) -> String:
	var st: Array = Colony.JOB_STATS.get(task, [])
	if st.is_empty():
		return ""
	return "%s %d%% + %s %d%%" % [Genetics.STAT_NAMES[st[0]].to_lower(), roundi(u.stat(st[0]) * 100),
		Genetics.STAT_NAMES[st[1]].to_lower(), roundi(u.stat(st[1]) * 100)]


func _calling_text(u: Unit, task: int) -> String:
	match colony.calling_of(u, task):
		1:
			return " · по призванию"
		-1:
			return " · не по душе"
	return ""


## «сила, выносливость (вполовину)».
func _job_stats_text(task: int) -> String:
	var st: Array = Colony.JOB_STATS.get(task, [])
	if st.is_empty():
		return ""
	return "%s, %s (вполовину)" % [Genetics.STAT_NAMES[st[0]].to_lower(), Genetics.STAT_NAMES[st[1]].to_lower()]


## Кто работает в комнате (назначенные игроком).
func _workers_list(p: Project) -> Dictionary:
	var items := []
	for u in colony.assigned_to(p):
		items.append({"looks": Genetics.looks(u.genome), "name": _name_sex(u),
			"info": _family_text(u) + " · подходит на %d%%%s · %s" % [roundi(colony.suitability(u, p) * 100), _calling_text(u, colony.work_task(p)), Unit.TASK_NAMES[u.task]],
			"button": "Снять", "style": "danger", "pick": func() -> void:
				colony.unassign_work(u)
				_show_project(p)})
	return {"type": "people", "label": "Работники %d/%d — работают только назначенные:" % [
		items.size(), colony.work_slots(p)], "items": items, "empty": "Никто не назначен."}


## Кого поставить в комнату: взрослые, лучшие для этой работы — сверху.
func _pick_worker(p: Project) -> void:
	# Список выбора не обновляем каждую секунду — иначе его перезапишет карточка.
	_info_target = []
	var items := []
	var cands := colony.units.filter(func(u: Unit) -> bool: return not u.child and u.workplace != p.id)
	# Сначала свободные, занятые (на работе, строители, шахтёры, подсобные) — ниже, с пометкой.
	cands.sort_custom(func(a: Unit, b: Unit) -> bool:
		if colony.is_free(a) != colony.is_free(b):
			return colony.is_free(a)
		return colony.suitability(a, p) > colony.suitability(b, p))
	var task := colony.work_task(p)
	cands = cands.filter(func(u: Unit) -> bool: return _pick_pass(u, task))
	for u: Unit in cands:
		var info := "подходит на %d%% · %s · навык %d%s" % [roundi(colony.suitability(u, p) * 100),
			_fit_text(u, task), u.level(colony.work_skill(p)), _calling_text(u, task)]
		var busy := not colony.is_free(u)
		if busy:
			info = "ЗАНЯТ: %s · %s" % [colony.role_name(u).to_lower(), info]
		items.append({"looks": Genetics.looks(u.genome), "name": _name_sex(u), "info": _family_text(u) + " · " + info,
			"button": "Забрать" if busy else "Назначить", "style": "danger" if busy else "",
			"pick": func() -> void:
				var err := colony.assign_work(u, p)
				if not err.is_empty():
					hud.log_event(err, "warning")
				_show_project(p)})
	hud.show_panel({"title": "Назначить: " + colony.workplace_name(p),
		"subtitle": "мест %d/%d · важно: %s" % [colony.assigned_to(p).size(), colony.work_slots(p), _job_stats_text(task)],
		"controls": [_pick_filter_control(func() -> void: _pick_worker(p)),
			{"type": "people", "label": "Лучшие для этой работы — сверху. Кто работает вместе или по соседству, быстрее становится парой:", "items": items,
			"empty": "Никто не подходит под фильтр." if _pick_filters.values().has(true) else "Все взрослые уже здесь."}],
		"actions": [["Назад", func() -> void: _show_project(p)]]})


## Переключатели фильтров над списком выбора гавриков (по умолчанию выключены).
func _pick_filter_control(refresh: Callable) -> Dictionary:
	return {"type": "checks", "label": "Показать только:", "items": [
		["single", "без пары", _pick_filters["single"]], ["calling", "по призванию", _pick_filters["calling"]]],
		"toggled": func(k: String, on: bool) -> void:
			_pick_filters[k] = on
			refresh.call()}


## Проходит ли гаврик включённые фильтры (для работы task).
func _pick_pass(u: Unit, task: int) -> bool:
	if _pick_filters["single"] and u.partner_id != 0:
		return false
	if _pick_filters["calling"] and colony.calling_of(u, task) != 1:
		return false
	return true


## Нормы запаса склада: сколько держать каждого ресурса.
## Склад и амбар: что хранить (галочки), сколько держать (предел) и до скольки добывать.
func _storage_control(p: Project) -> Dictionary:
	var keys: Array = []
	for k in Colony.GATHER_SOURCES:
		if RoomType.same_kind(p, k):
			keys.append(k)
	var known: Array = colony.known_resources.keys()
	known.sort()
	for k in known:
		if not keys.has(k) and not RoomType.BULK.has(k) and not RoomType.PIPED.has(k) and RoomType.same_kind(p, k):
			keys.append(k)
	var items := []
	for k in keys:
		var on := RoomType.stores(p, k)
		# Вместимость без галочки не считается — берём, какой она будет с галочкой.
		var cap := RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p)
		if colony.research.has("shelving"):
			cap = roundi(cap * 1.5)
		items.append({"key": k, "on": on, "held": colony.held_in(p, k), "cap": cap,
			"limit": mini(cap, int(p.limits.get(k, cap))),
			"target": int(p.targets.get(k, 0)) if Colony.GATHER_SOURCES.has(k) else -1})
	var total := 0
	for k in p.held:
		total += int(p.held[k])
	var cap0 := RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p)
	if colony.research.has("shelving"):
		cap0 = roundi(cap0 * 1.5)
	return {"type": "store", "label": "Вместимость: по %s каждого %s. Сейчас лежит всего %s.\nГалочка — хранить ли здесь этот ресурс:" % [
		Fmt.int_spaced(cap0), "вида еды" if p.purpose == RoomType.GRANARY else "ресурса", Fmt.int_spaced(total)],
		"items": items,
		"toggled": func(key: String, on: bool) -> void:
			colony.set_store_on(p, key, on)
			_show_project(p),
		"limit": func(key: String, v: int) -> void:
			colony.set_store_limit(p, key, v),
		"target": func(key: String, v: int) -> void:
			p.targets[key] = mini(v, colony.room_limit(p, key))
			colony.wake_idle()}


## Кузница: что плавит сейчас и нормы — сколько держать каждого металла (как на складе).
func _forge_rows(p: Project, rows: Array) -> void:
	var key := colony.forge_pick(p)
	rows.append({"type": "text", "text": "Из любой руды — 3 единицы металла. Плавит то, чего меньше всего до нормы и для чего есть руда. Нормы — ниже. Сейчас: %s." % (
		Mat.resource_name(key).to_lower() if not key.is_empty() else "ничего — всё по норме или нет руды")})


## Нормы кузницы — по ступеньке на каждый металл.
func _forge_controls(p: Project) -> Array:
	var controls := []
	for k in RoomType.FORGE_RECIPES:
		var src: String = RoomType.FORGE_RECIPES[k][0].keys()[0]
		controls.append({"label": "%s: есть %d, руды %d" % [Mat.resource_name(k), colony._have_any(k),
				colony._have_any(src) if src.ends_with("_ore") else colony._have_any("iron")],
			"value": int(p.targets.get(k, 0)), "min": 0, "max": 500, "step": 10,
			"changed": func(v: int) -> void:
				p.targets[k] = v
				p.forge_at = -INF
				colony.wake_idle()})
	return controls


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
				rows.append(_progress("Укрепление", float(p.supported.size()) / p.needs_support.size(),
					"%d из %d срезов" % [p.supported.size(), p.needs_support.size()], Color(0.75, 0.55, 0.3)))
			var clear := colony.uncleared(p).size()
			if clear > 0:
				rows.append({"type": "text", "text": "Сначала убрать с места стройки: %d (деревья, кусты, валуны)" % clear})
		Project.Phase.BUILD:
			rows.append(_progress("Строительство", p.build_done / p.build_work() if p.paid else 0.0))
		Project.Phase.EQUIP:
			var w := RoomType.job_work(p)
			var what: String = "Сборка ракеты" if not p.equip_rocket.is_empty() else "Лестница" if p.equip_ladder else ("Перестройка стен — " + Project.MATERIALS[p.equip_material][0].to_lower()
				if not p.equip_material.is_empty() else "Обустройство")
			rows.append(_progress(what, p.equip_done / w if p.equip_paid else 0.0))
	if p.repairing:
		rows.append(_progress("Ремонт", p.repair_done / maxf(1.0, p.repair_work) if p.repair_paid else 0.0))
	var supply := colony.supply_status(p)
	if not supply.is_empty():
		rows.append({"type": "resources", "label": "Материалы", "items": supply})
	if p.plan_purpose > 0 and p.phase != Project.Phase.DONE:
		rows.append({"type": "text", "text": "После постройки сразу обустроят: %s" % RoomType.purpose_name(p.plan_purpose)})
	var wall: String = _wall_choice.get(p.id, p.material)
	if p.phase == Project.Phase.DONE and wall != p.material:
		var wc := RoomType.material_cost(p, wall)
		var witems := []
		for k in wc:
			witems.append([k, colony.inventory.get(k, 0), wc[k], colony.inventory.get(k, 0) >= wc[k]])
		rows.append({"type": "resources", "label": "Перестроить стены — %s (%d с работы; на время работ комната не работает):" % [
			Project.MATERIALS[wall][0].to_lower(), roundi(RoomType.material_work(p, wall))], "items": witems})
		var werr := colony.material_error(p, wall)
		if not werr.is_empty():
			rows.append({"type": "warning", "text": werr})
	var chips := []
	if p.phase != Project.Phase.DONE or p.repairing:
		chips.append(["people", "рабочие %d/%d" % [colony.workers_on(p), p.workers]])
	if p.priority:
		chips.append(["", "приоритет: %s идут сюда первыми" % ("шахтёры" if p.kind == Project.Kind.MINE else "строители"), Color(1.0, 0.8, 0.4)])
	match p.kind:
		Project.Kind.ROOM:
			chips.append(["", "стены: " + p.material_name().to_lower()])
		Project.Kind.TUNNEL:
			chips.append(["", "потоков: %d" % Colony.tunnel_lanes(p.rect)])
			if p.phase == Project.Phase.DIG:
				var tdone := colony.mine_meters_done(p)
				var unit := "по 2 м" if p.vertical() else "м"
				rows.append(_progress("Готово", float(tdone) / maxf(1.0, p.slice_count()), "%d из %d (%s)" % [tdone, p.slice_count(), unit]))
				rows.append({"type": "text", "text": "Тоннель строится по метру: выкопан и закреплён — готов. «Остановить» — готовая часть остаётся тоннелем."})
		Project.Kind.BRIDGE when p.phase == Project.Phase.BUILD:
			var bdone := colony.bridge_meters_done(p)
			rows.append(_progress("Готово", float(bdone) / p.rect.size.x, "%d из %d м" % [bdone, p.rect.size.x]))
			rows.append({"type": "text", "text": "Мост строят по метру от берега. «Остановить» — построенная часть остаётся пристанью, дерево за остальное возвращается."})
		Project.Kind.PROBE:
			var lv := colony.probe_level()
			if colony.probing(p):
				var all: int = p.probe_done + p.drill_left
				rows.append(_progress("Зонд", float(p.probe_done) / maxf(1.0, all), "%d из %d м" % [p.probe_done, all], Color(0.6, 0.7, 0.8)))
			if not lv.is_empty():
				chips.append(["", "зонд до %d м" % lv[0]])
				chips.append(["", "полоса обзора %d м" % (int(lv[1]) * 2)])
			if p.phase == Project.Phase.DONE:
				chips.append(["power", "энергия: %s" % ("есть" if colony.powered() else "нет — зонд стоит")])
				rows.append({"type": "text", "text": "Зонд из середины скважины уходит вниз, вверх, влево или вправо и открывает породу полосой — ничего не копая: видно, есть ли там руда, вода, газ или магма. Длина и ширина полосы растут с «Геоскважиной II» и «III». Идёт со скоростью алмазного бура, на энергии. Что нашёл — в журнале."})
			else:
				rows.append({"type": "text", "text": "Место под скважину выкапывают, потом собирают вышку. Готовой скважиной командуют из её карточки: куда пустить зонд."})
		Project.Kind.DRILL:
			if p.link_id != 0:
				var lift := colony.drill_lift_of(p)
				var stores := colony.lift_stores(lift, 0) if lift != null and lift.phase == Project.Phase.DONE else []
				rows.append({"type": "text", "text": "Бур-лифт: бурит только вниз, шахта грузового лифта растёт следом, и всё добытое кабина сама везёт наверх. %s" % (
					"Выгружает на склад: %s." % stores[0].title() if not stores.is_empty() else "Склада у верха лифта нет — добытое ляжет у лифта, гаврики разнесут. Поставьте склад вплотную к верху лифта.")})
			if colony.drilling(p):
				var went := absi(p.rect.position.x - p.bore_from.position.x) + absi(p.rect.position.y - p.bore_from.position.y)
				var all := went + p.drill_left
				rows.append(_progress("Пройдено", float(went) / maxf(1.0, all), "%d из %d м" % [went, all], Color(0.6, 0.7, 0.8)))
			if p.link_id != 0:
				var lift := colony.drill_lift_of(p)
				if lift != null and lift.phase == Project.Phase.DONE:
					chips.append(["", "лифт %d м" % lift.rect.size.y])
					chips.append(["", "в кабине %d из %d" % [colony._load_total(lift.lift_load), Colony.CARGO_CAP]])
					var riders := colony.units.filter(func(o: Unit) -> bool: return o.lift_id == lift.id and o.riding).size()
					chips.append(["people", "людей %d из %d" % [riders, colony.lift_cap(lift)]])
			if colony.drilling(p):
				rows.append({"type": "text", "text": ("Бур идёт вниз, шахта лифта растёт следом, добытое кабина сама везёт наверх. " if p.link_id != 0 else "Бур едет и сверлит ход 3 м шириной втрое быстрее гаврика. Породу уносят гаврики. ") + "«Остановить» — пройденное остаётся ходом, бур стоит, где остановился."})
			if p.phase == Project.Phase.DONE and not colony.drilling(p):
				var diesel := colony.research.has("combustion")
				chips.append(["power", "энергия: %s" % ("есть" if colony.powered() else ("нет — на дизеле" if diesel else "нет — бур стоит"))])
				chips.append(["", "скорость ×%.1f от гаврика" % colony.drill_speed(true)])
				if p.link_id != 0:
					rows.append({"type": "text", "text": "Выберите, на сколько метров бурить вниз. Бур идёт сам, на энергии%s; обсадка — 1 железо на %d м со склада. Добытое кабина сама везёт наверх — гаврики его не носят. Перед газом, водой или магмой бур останавливается с тревогой. Вокруг бура видно породу на дальность геологоразведки." % [
						" или дизеле" if diesel else "", Colony.DRILL_CASING_M]})
				else:
					rows.append({"type": "text", "text": "Выберите, на сколько метров и куда сверлить. Бур сам едет и сверлит ход 3 м шириной втрое быстрее гаврика, на энергии%s. Обсадка хода — 1 железо на %d м, берётся со склада. Породу уносят гаврики. Перед газом, водой или магмой бур останавливается с тревогой. Ход вниз — тоннель, вбок — как шахта: можно ставить лифт и комнаты. «Остановить» — пройденное остаётся ходом." % [
						" или дизеле" if diesel else "", Colony.DRILL_CASING_M]})
			else:
				rows.append({"type": "text", "text": "Место под бур выкапывают, потом собирают машину. Готовым буром командуют из его карточки: куда и сколько сверлить."})
		Project.Kind.LIFT:
			chips.append(["", "по вертикали" if p.lift_vertical() else "по горизонтали"])
			if p.phase == Project.Phase.DONE:
				chips.append(["power", "энергия: %s" % ("есть" if colony.lift_powered(p) else "нет — кабина стоит")])
				chips.append(["", "скорость %.0f м/с (пешком %.0f)" % [colony.lift_speed(p), Colony.WALK_SPEED]])
			if p.cargo:
				var load := 0
				for k in p.lift_load:
					load += int(p.lift_load[k])
				chips.append(["", "в кабине %d из %d" % [load, Colony.CARGO_CAP]])
				var riders := colony.units.filter(func(o: Unit) -> bool: return o.lift_id == p.id and o.riding).size()
				chips.append(["people", "людей %d из %d" % [riders, colony.lift_cap(p)]])
				var names := ["верхнего" if p.lift_vertical() else "левого", "нижнего" if p.lift_vertical() else "правого"]
				for e in 2:
					var st := colony.lift_stores(p, e)
					rows.append({"type": "text", "text": "У %s конца: %s" % [names[e],
						("склад вплотную — разгрузка и погрузка сами" if not st.is_empty() else "склада нет — груз выгружается на площадку")]})
				rows.append({"type": "text", "text": "Возит грузы и людей (до %d человек — вдвое больше пассажирского; сначала людей, потом груз). Подсобные и работники складов несут добычу в лифт, если до него ближе, чем до склада; у склада вплотную к другому концу лифт разгружается сам. Материалы для строек у дальнего конца лифт сам берёт из склада у своего конца — со склада их туда руками не носят." % colony.lift_cap(p)})
			else:
				var riding := colony.units.filter(func(o: Unit) -> bool: return o.lift_id == p.id and o.riding).size()
				chips.append(["people", "в кабине %d из %d" % [riding, Colony.LIFT_CAP]])
				rows.append({"type": "text", "text": "Кабина на 6 человек ездит втрое быстрее пешехода и останавливается только там, где садятся и выходят; ждёт тех, кто уже идёт к ней. Без энергии стоит — по шахте лезут по аварийной лестнице."})
		Project.Kind.MINE:
			chips.append(["", "шахтёров %d" % colony.units.filter(func(o: Unit) -> bool: return o.workplace == 0 and o.profession == Unit.Prof.MINER).size()])
			if p.phase == Project.Phase.DONE:
				rows.append({"type": "text", "text": "Готовая шахта: здесь можно ставить комнаты на всю её высоту."})
			else:
				var done := colony.mine_meters_done(p)
				rows.append(_progress("Готово", float(done) / maxf(1.0, p.slice_count()), "%d из %d м" % [done, p.slice_count()]))
				rows.append({"type": "text", "text": "Шахта строится по метру: метр выкопан и закреплён — готов. «Остановить» — готовая часть остаётся шахтой. Шахтёры копают и ставят крепь; дерево на крепь носят работники складов (шахта у них в первую очередь) и подсобные, а если свободных подсобных нет — сами шахтёры. Добытое уносят склады и подсобные."})
		_:
			chips.append(["people", "рыбаков %d/%d" % [colony.workers_on(p), p.fish_slots()]])
			chips.append(["", "рыбы ~%d" % int(colony.fish_left(p))])
			if not colony.can_fish_from(p):
				rows.append({"type": "text", "text": "Зима: озеро подо льдом — ловить можно только с пристани."})
			elif colony.is_winter():
				chips.append(["", "зимой улов вдвое медленнее"])
	if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM:
		chips.append(["", "внутри %+d °C" % roundi(colony.room_temp(p))])
		# Готовое у производства — в его ящиках (до 100), пока подсобные не унесут.
		if colony.is_producer(p):
			var held := colony.output_held(p)
			rows.append(_progress("Готовое в ящиках", float(held) / Colony.PRODUCE_CAP, "%d из %d%s" % [held, Colony.PRODUCE_CAP,
				" — работа стоит, унесите в амбар или на склад" if held >= Colony.PRODUCE_CAP else ""],
				Color(1.0, 0.5, 0.4) if held >= Colony.PRODUCE_CAP else Color(0.6, 0.8, 0.5)))
		var lying := {}
		for c: Vector2i in colony.drops:
			if p.rect.has_point(c):
				for k in colony.drops[c]:
					lying[k] = lying.get(k, 0) + int(colony.drops[c][k])
		if not lying.is_empty():
			var items := []
			for k in lying:
				items.append([k, lying[k], -1, true])
			rows.append({"type": "resources", "label": "В ящиках" if colony.is_producer(p) else "Лежит на полу", "items": items})
		if not p.stock.is_empty() and RoomType.RECIPES.has(p.purpose):
			var st := []
			for k in p.stock:
				st.append([k, p.stock[k], -1, true])
			rows.append({"type": "resources", "label": "Сырьё в мастерской", "items": st})
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
				if colony.home_freezing(p):
					rows.append({"type": "warning", "text": "В доме мороз (%d °C) — жильцы мёрзнут во сне и могут погибнуть. Поставьте рядом очаг (греет от стен на 6–10 м)." % roundi(colony.room_temp(p))})
				var free := colony.beds_total() - colony.units.size() - colony.pregnant_count()
				chips.append(["people", "мест для детей в колонии: %d" % maxi(0, free)])
			RoomType.STORAGE, RoomType.GRANARY:
				chips.append(["people", "работников %d/%d" % [colony.assigned_to(p).size(), colony.work_slots(p)]])
				var held_total := 0
				for k in p.held:
					held_total += int(p.held[k])
				chips.append(["", "лежит всего %s · по %s мест каждому %s" % [Fmt.int_spaced(held_total),
					Fmt.int_spaced(roundi(RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p) * (1.5 if colony.research.has("shelving") else 1.0))),
					"виду еды" if p.purpose == RoomType.GRANARY else "ресурсу"]])
				if colony.assigned_to(p).is_empty():
					rows.append({"type": "text", "text": "Нет работника — сюда никто ничего не носит. Назначьте работника (кнопка «Работа» у гаврика)."})
				var lacking := colony.storage_deficit(p)
				if not colony.assigned_to(p).is_empty() and not lacking.is_empty():
					var names := lacking.map(func(k: String) -> String: return Mat.resource_name(k).to_lower())
					rows.append({"type": "text", "text": "Добывают до нормы: " + ", ".join(names)})
			RoomType.FARM:
				chips.append(["people", "фермеров %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
				if not colony.farm_warm(p):
					rows.append({"type": "text", "text": "Холодно (%d °C) — грибы растут от %d °C. Нужен очаг рядом (греет от стен на 6–10 м) или генератор." \
						% [roundi(colony.room_temp(p)), roundi(Colony.FARM_MIN_TEMP)]})
			RoomType.DINING:
				chips.append(["", "еда сытнее, настроение лучше"])
			RoomType.KILN, RoomType.FORGE, RoomType.REFINERY, RoomType.ENRICHMENT:
				var recipe: Array = colony.recipe(p)
				if p.purpose == RoomType.ENRICHMENT:
					rows.append({"type": "warning", "text": "Уран радиоактивен: мастер фабрики, носильщики урана и кто копает урановую руду облучаются — живут на 10% меньше, а их дети всегда рождаются с мутацией."})
				if p.purpose == RoomType.FORGE:
					_forge_rows(p, rows)
				if recipe.is_empty():
					recipe = RoomType.FORGE_RECIPES["iron"]
				if p.purpose == RoomType.REFINERY:
					rows.append({"type": "text", "text": "Нефть берёт по трубам из нефтехранилища, дизель туда же и отдаёт — носить ничего не надо. Нужны мастер и энергия."})
					if colony.rooms_of(RoomType.OIL_TANK).is_empty():
						rows.append({"type": "warning", "text": "Нет нефтехранилища — нефть и дизель хранить негде."})
				rows.append(_progress("Производство", p.farm_progress / recipe[2]))
				var items := []
				for k in recipe[0]:
					var have: int = colony.inventory.get(k, 0)
					items.append([k, have, recipe[0][k], have >= recipe[0][k]])
				rows.append({"type": "resources", "label": "Сырьё на цикл", "items": items})
				if RoomType.FUELED.has(p.purpose):
					var fuel := []
					for k in ["coal", "wood"]:
						fuel.append([k, colony.inventory.get(k, 0), -1, colony.inventory.get(k, 0) > 0])
					rows.append({"type": "resources", "label": "Топливо", "items": fuel})
					rows.append({"type": "text", "text": "На цикл обжига — 1 дерево или ½ угля (уголь берут первым). В печи топлива на %d цикл(ов)." % int(colony.fuel_have(p))})
				var out := []
				for k in recipe[1]:
					out.append([k, recipe[1][k], -1, true])
				rows.append({"type": "resources", "label": "Даёт", "items": out})
				chips.append(["people", "мастеров %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
			RoomType.LAB:
				chips.append(["people", "учёных %d/%d" % [colony.workers_on(p), RoomType.farm_slots(p)]])
				var minds := 0.0
				for w in colony.assigned_to(p):
					minds += w.stat("intellect") * w.speed("science")
				chips.append(["", "скорость науки %d%% (интеллект учёных)" % roundi(minds * 100.0)])
				if colony.assigned_to(p).is_empty():
					rows.append({"type": "warning", "text": "Нет учёных — назначьте гаврика («Назначить»): исследуют только назначенные, быстрее — умные."})
				var cur := colony.research.current
				if cur.is_empty():
					rows.append({"type": "text", "text": "Нечего изучать — выберите исследование («Наука»)."})
				else:
					rows.append(_progress(Research.tech_name(cur), colony.research.progress / colony.research.cost(cur)))
			RoomType.LAUNCHPAD:
				_rocket_rows(p, rows)
			RoomType.SHIP:
				chips.append(["home", "мест %d" % RoomType.SHIP_BEDS])
				chips.append(["power", "реактор: %d" % RoomType.SHIP_POWER])
				rows.append({"type": "text", "text": "Корабль — жильё на 10 человек: внутри воздух, тепло (+20 °C) и свет, трюм держит груз. Наружу на поверхность без воздуха не выйти — копайте тоннель вниз прямо из корабля."})
			RoomType.OIL_PUMP:
				chips.append(["", "качает на %d м вокруг" % RoomType.effect_radius(p)])
				var oil_cell = colony._nearest_oil(p)
				chips.append(["", "нефть рядом: %s" % ("есть" if oil_cell != null else "нет")])
				rows.append(_progress("Следующая порция", clampf(p.farm_progress / Colony.OIL_PUMP_TIME, 0.0, 1.0), "", Color(0.35, 0.3, 0.25)))
				rows.append({"type": "text", "text": "Раз в %d с выкачивает ближайшую клетку нефтеносного пласта (+%d нефти) по трубам в нефтехранилище. Нефть залегает глубже 200 м, в осадочных слоях. Нужна энергия." % [int(Colony.OIL_PUMP_TIME), Colony.OIL_PER_CELL_YIELD]})
			RoomType.OIL_TANK:
				for k in ["oil", "diesel"]:
					var tcap := colony.room_cap(p, k)
					rows.append(_progress(Mat.resource_name(k), float(colony.held_in(p, k)) / maxf(1.0, tcap),
						"%d из %d" % [colony.held_in(p, k), tcap], Color(0.25, 0.2, 0.15) if k == "oil" else Color(0.95, 0.65, 0.15)))
				rows.append({"type": "text", "text": "Нефть и дизельное топливо хранятся только здесь и идут по трубам. Если хранилище рухнет — взрыв: всё вокруг на 3, 6 или 9 м (по размеру)."})
			RoomType.GENERATOR, RoomType.GAS_GEN, RoomType.DIESEL_GEN:
				var gas := p.purpose == RoomType.GAS_GEN
				chips.append(["power", "даёт %d, колонии нужно %d" % [RoomType.POWER_MAKE, colony.power_used]])
				rows.append(_progress("Топливо", clampf(p.farm_progress / RoomType.FUEL_TIME, 0.0, 1.0),
					"%d с" % maxi(0, roundi(p.farm_progress)), Color(0.45, 0.7, 1.0) if gas else Color(0.95, 0.6, 0.2)))
				if p.purpose == RoomType.DIESEL_GEN:
					chips.append(["", "дизеля в хранилище: %d" % colony.inventory.get("diesel", 0)])
					rows.append({"type": "text", "text": "Жжёт 1 дизель за %d с по трубам из нефтехранилища и даёт в полтора раза больше энергии." % int(RoomType.FUEL_TIME * 2.0)})
				elif gas:
					chips.append(["", "метан в баках: %d" % colony.inventory.get("methane", 0)])
					rows.append({"type": "text", "text": "Жжёт 1 метан за %d с — по трубам из баков дегазации, носить ничего не надо. Уголь и дрова не берёт. Работая, греет всё вокруг (на 6 м от стен)." % int(RoomType.FUEL_TIME)})
					if colony.rooms_of(RoomType.DEGAS).is_empty():
						rows.append({"type": "warning", "text": "Нет дегазации — метана для генератора не будет."})
				else:
					rows.append({"type": "text", "text": "Жжёт 1 уголь или 2 дерева за %d с (сначала уголь). Метан не жжёт — для него нужен газовый генератор. Работая, греет всё вокруг (на 6 м от стен)." % int(RoomType.FUEL_TIME)})
				rows.append({"type": "text", "text": "Свет: лампочка на каждые 3 м комнаты, 1 ед. энергии каждая. Сам свет включается в комнатах ближе к генератору, пока хватает энергии; в любой комнате его можно включить или выключить (всю сразу). На стройке и в шахте — одна лампа там, где сейчас работают."})
			RoomType.DEGAS:
				var cap := colony.room_cap(p, "methane")
				rows.append(_progress("Метан в баке", float(colony.held_in(p, "methane")) / maxf(1.0, cap),
					"%d из %d" % [colony.held_in(p, "methane"), cap], Color(0.45, 0.7, 1.0)))
				rows.append({"type": "text", "text": "Газ хранится только здесь, в баке. По трубам его берут газовые генераторы и газовые котлы очагов. Бак полон — откачка останавливается: поставьте ещё одну дегазацию или жгите газ."})
			RoomType.HEARTH:
				chips.append(["", "горит" if p.burning else ("не горит — греть некого" if colony.is_cold_at(p) and not colony.hearth_needed(p) else "не горит")])
				var n := RoomType.stoves(p)
				var zone := RoomType.heat_zone(p, colony.research.has("insulation"))
				var per_log := RoomType.HEARTH_FUEL_TIME * (RoomType.BRICK_STOVE_GAIN if p.brick_stoves else 1.0)
				chips.append(["", "печей %d, %s%s" % [n, "кирпичные" if p.brick_stoves else "каменные", ", с котлами" if p.gas_boiler else ""]])
				if p.gas_boiler:
					chips.append(["", "на газу" if p.on_gas else "на дровах/угле"])
				rows.append({"type": "text", "text": "Каждая печь жжёт 1 дерево за %d с%s, пока вокруг холоднее %d °C и есть кого греть: рядом гаврик, ферма в холоде или кто-то в колонии замерзает. Иначе огонь гаснет, а недогоревшее ждёт. Греет от стен комнаты: в %d м — полное тепло (+%d °C), дальше слабее, до %d м. Жилые и ферму — ставьте рядом." \
					% [int(per_log), " (уголь — вдвое дольше, его берут первым)" if p.brick_stoves else " (каменные печи углём не топят — только дрова)", int(Colony.HEARTH_ON_BELOW), zone.x, int(Colony.HEAT), zone.y]})
				if p.gas_boiler:
					rows.append({"type": "text", "text": "Газовые котлы: первым жгут метан от дегазации (1 метан — как 3 дерева), на газу греют на 1–2 м дальше. Метан кончился — печи топят углём и дровами."})
				elif colony.research.has("gas_heating"):
					rows.append({"type": "text", "text": "Печь метан не жжёт. Поставьте кирпичные газовые котлы — тогда очаг будет топиться метаном от дегазации."})
				if not p.brick_stoves:
					rows.append({"type": "text", "text": "Кирпичные печи (после «Обжига кирпича»): дров в 1,5 раза меньше, греют в 1,5 раза дальше, служат вдвое дольше и топятся углём."})
		if RoomType.POWER_USE.has(p.purpose) and colony.research.has("electricity"):
			chips.append(["power", "энергия: %s" % ("есть" if colony.powered() and colony.power_ratio >= 0.99 else
				("не хватает" if colony.powered() else "нет"))])
		if colony.is_workplace(p) and colony.assigned_to(p).is_empty() \
				and p.purpose not in [RoomType.STORAGE, RoomType.GRANARY, RoomType.LAB]:
			rows.append({"type": "warning", "text": "Никто не работает — назначьте работника («Назначить»): здесь работают только назначенные."})
		if colony.lightable(p) and colony.research.has("electricity"):
			var n := RoomType.blocks(p)
			var state := "горит" if p.lit else ("выключен" if p.light == 0 else ("не хватает энергии" if colony.powered() else "нет генератора"))
			chips.append(["power", "свет: %s · %d ламп. = %d ед." % [state, n, n]])
		var radius := RoomType.effect_radius(p)
		if radius > 0:
			chips.append(["", "радиус %d м" % radius])
		var current := RoomType.current_purpose(p)
		if preview_purpose > 0 and preview_purpose != current:
			var cost := RoomType.equip_cost(preview_purpose, p)
			rows.append({"type": "text", "text": "«%s»: %s" % [RoomType.purpose_name(preview_purpose), RoomType.purpose_hint(preview_purpose)],
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


# --- Гаврики: кто чем занят, строители и подсобные -----------------------------------------

## Что гаврик делает прямо сейчас.
func _doing(u: Unit) -> String:
	var t: String = Unit.TASK_NAMES[u.task]
	if u.task == Unit.Task.HAUL and u.carry_amount > 0:
		t += " (%s)" % Mat.resource_name(u.carry_key).to_lower()
	return t


func _people_spec() -> Dictionary:
	var counts := {}
	var adults := 0
	for u in colony.units:
		if u.child:
			continue
		adults += 1
		var d: String = Unit.TASK_NAMES[u.task]
		counts[d] = counts.get(d, 0) + 1
	var chips := []
	for d in counts:
		chips.append(["", "%s: %d" % [d, counts[d]]])
	return {"title": "Гаврики", "subtitle": "взрослых %d · детей %d" % [adults, colony.units.size() - adults],
		"rows": [{"type": "chips", "label": "Сейчас", "items": chips},
			{"type": "text", "text": "Шахтёры работают только в шахтах, строители — на остальных стройках (в шахтах — только если шахтёров нет); на работу идут ближайшие. Свободные помогают везде, где есть места («Рабочих» в карточке — это места для помощников): пока строитель далеко, работает ближайший свободный, а когда строитель дойдёт — уступает ему. Гаврик докапывает свою стройку, а не бежит на другую. Строитель и шахтёр сами берут дерево на крепь полной ношей, только если его не принесли; добытое и материалы носят работники складов, подсобные и свободные — на любой склад, работник склада для этого не нужен."}]}


func _show_people() -> void:
	_select(null, null)
	hud.close_overlays()
	_info_target = ["people"]
	var spec := _people_spec()
	var groups := [["Строители", func(u: Unit) -> bool: return u.workplace == 0 and u.profession == Unit.Prof.BUILDER],
		["Шахтёры", func(u: Unit) -> bool: return u.workplace == 0 and u.profession == Unit.Prof.MINER],
		["Подсобные рабочие", func(u: Unit) -> bool: return u.workplace == 0 and u.profession == Unit.Prof.HAULER],
		["На местах работы", func(u: Unit) -> bool: return not u.child and u.workplace != 0],
		["Свободные", func(u: Unit) -> bool: return colony.is_free(u)],
		["Дети", func(u: Unit) -> bool: return u.child]]
	var controls := []
	for g in groups:
		var members := colony.units.filter(g[1])
		var items := []
		for u: Unit in members:
			var item := {"looks": Genetics.looks(u.genome), "name": _name_sex(u), "info": (_family_text(u) + " · " if not u.child else "") + _doing(u),
				"button": "Карточка", "pick": func() -> void: _select(u, null)}
			if u.workplace != 0:
				item["info"] = colony.role_name(u) + " · " + _doing(u)
			elif not u.child and not colony.is_free(u):
				item["button"] = "Снять"
				item["style"] = "danger"
				item["pick"] = func() -> void:
					colony.set_profession(u, Unit.Prof.ANY)
					_show_people()
			items.append(item)
		if g[0] != "Дети" or not items.is_empty():
			controls.append({"type": "people", "label": "%s — %d" % [g[0], items.size()], "items": items, "empty": "Никого."})
	spec["controls"] = controls
	spec["actions"] = [["+ Строитель", func() -> void: _pick_role(Unit.Prof.BUILDER), "primary"],
		["+ Шахтёр", func() -> void: _pick_role(Unit.Prof.MINER), "primary"],
		["+ Подсобный", func() -> void: _pick_role(Unit.Prof.HAULER), "primary"]]
	hud.show_panel(spec)


## Кого назначить строителем или подсобным: сначала свободные, лучшие — сверху.
func _pick_role(prof: int) -> void:
	_info_target = []
	var task: int = {Unit.Prof.BUILDER: Unit.Task.BUILD, Unit.Prof.MINER: Unit.Task.DIG}.get(prof, Unit.Task.HARVEST)
	var skill := "build" if prof == Unit.Prof.BUILDER else ("dig" if prof == Unit.Prof.MINER else "gather")
	var cands := colony.units.filter(func(o: Unit) -> bool:
		return not o.child and not (o.workplace == 0 and o.profession == prof))
	var score := func(o: Unit) -> float:
		return colony.stat_fit(o, task) * o.speed(skill) * float(o.ability("work")) + (1.0 if colony.is_free(o) else 0.0)
	cands = cands.filter(func(o: Unit) -> bool: return _pick_pass(o, task))
	cands.sort_custom(func(a: Unit, b: Unit) -> bool: return score.call(a) > score.call(b))
	var items := []
	for o: Unit in cands:
		var busy := not colony.is_free(o)
		items.append({"looks": Genetics.looks(o.genome), "name": _name_sex(o),
			"info": "%s%s · %s · %s · навык %d%s" % ["ЗАНЯТ: " if busy else "", _family_text(o), colony.role_name(o).to_lower(), _fit_text(o, task),
				o.level(skill), _calling_text(o, task)],
			"button": "Забрать" if busy else "Назначить", "style": "danger" if busy else "", "pick": func() -> void:
				colony.set_profession(o, prof)
				_show_people()})
	hud.show_panel({"title": "Назначить: " + Unit.PROF_NAMES[prof].to_lower(), "subtitle": "сначала свободные, лучшие — сверху",
		"controls": [_pick_filter_control(func() -> void: _pick_role(prof)),
			{"type": "people", "label": "Кого назначить:", "items": items,
			"empty": "Никто не подходит под фильтр." if _pick_filters.values().has(true) else "Некого назначить."}],
		"actions": [["Назад", _show_people]]})


## Наука: текущее исследование и дерево технологий.
func _show_science() -> void:
	_select(null, null)
	hud.close_overlays()
	_info_target = ["science"]
	hud.show_tech_tree(_science_tree_spec())


## Наука для дерева: шапка, прогресс и все исследования с требованиями.
func _science_tree_spec() -> Dictionary:
	var spec := _science_spec()
	var items := []
	for id in Research.TECHS:
		var it := _tech_item(id)
		it["id"] = id
		it["needs"] = Research.TECHS[id][3]
		it["branch"] = Research.branch_of(id)
		it["row"] = Research.TECHS[id][5]
		it["col"] = Research.TECHS[id][6]
		it["spent"] = int(colony.research.points(id))
		items.append(it)
	spec["items"] = items
	return spec


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
		desc = "Сначала: " + ", ".join(needs.map(func(n: String) -> String: return Research.tech_name(n))) + ".\n" + desc
	return {"name": Research.tech_name(id), "desc": desc, "cost": int(r.cost(id)), "state": state,
		"pick": func() -> void:
			r.start(id)
			_show_science()}


func _science_spec() -> Dictionary:
	var r := colony.research
	var rows := []
	if r.current.is_empty():
		rows.append({"type": "text", "text": "Выберите, что изучать. Изучают только назначенные в лабораторию учёные; чем выше интеллект — тем быстрее."})
	else:
		rows.append(_progress(Research.tech_name(r.current), r.progress / r.cost(r.current),
			"%d / %d" % [int(r.progress), int(r.cost(r.current))], Color(0.45, 0.7, 1.0)))
	var labs := colony.rooms_of(RoomType.LAB)
	var scientists := 0
	for p in labs:
		scientists += colony.workers_on(p)
	if labs.is_empty():
		rows.append({"type": "warning", "text": "Нет лаборатории — постройте комнату и выберите назначение «Лаборатория»."})
	return {"title": "Наука", "subtitle": "изучено %d из %d · лабораторий %d · учёных за работой %d" % [
		r.done.size(), Research.TECHS.size(), labs.size(), scientists], "rows": rows}


func _refresh_info() -> void:
	if _info_target.is_empty() or not hud.info_visible():
		return
	if _info_target[0] == "unit":
		var u := colony.unit_by_id(_info_target[1])
		if u != null:
			hud.refresh_panel(_unit_spec(u))
	elif _info_target[0] == "science":
		hud.refresh_tech_tree(_science_tree_spec())
	elif _info_target[0] == "people":
		hud.refresh_panel(_people_spec())
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
	if mode == Hud.Mode.ROOM:
		var placed := _room_rect(c)
		r = placed[0]
		err = placed[1]
	elif mode == Hud.Mode.BRIDGE:
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
	elif mode == Hud.Mode.TUNNEL:
		err = colony.validate(kind, r)
	elif mode == Hud.Mode.MINE:
		# Шахта — всегда 3 м: полоса тянется по горизонтали от места, где коснулись.
		r = Rect2i(r.position.x, _drag_start.y - 1, r.size.x, Project.MINE_HEIGHT)
		err = colony.validate(kind, r)
	elif mode == Hud.Mode.DRILL:
		# Бур — машина 3×3 под пальцем; сама прилипает к земле или полу рядом.
		r = Rect2i(c.x - 1, c.y - 1, 3, 3)
		err = colony.validate(kind, r)
		for dy in [1, -1, 2, -2]:
			if err.is_empty():
				break
			var rr := Rect2i(c.x - 1, c.y - 1 + dy, 3, 3)
			if colony.validate(kind, rr).is_empty():
				r = rr
				err = ""
	elif mode == Hud.Mode.PROBE:
		# Геоскважина 2×2 под пальцем; сама прилипает к земле или полу рядом.
		r = Rect2i(c.x, c.y - 1, 2, 2)
		err = colony.validate(kind, r)
		for dy in [1, -1, 2, -2]:
			if err.is_empty():
				break
			var rr := Rect2i(c.x, c.y - 1 + dy, 2, 2)
			if colony.validate(kind, rr).is_empty():
				r = rr
				err = ""
	elif mode == Hud.Mode.DRILL_LIFT:
		# Бур-лифт 3×5 под пальцем (палец — на буре); прилипает к земле или полу рядом.
		r = Rect2i(c.x - 1, c.y - 3, 3, 5)
		err = colony.drill_lift_error(r)
		for dy in [1, -1, 2, -2]:
			if err.is_empty():
				break
			var rr := Rect2i(c.x - 1, c.y - 3 + dy, 3, 5)
			if colony.drill_lift_error(rr).is_empty():
				r = rr
				err = ""
	elif mode == Hud.Mode.LIFT or mode == Hud.Mode.CARGO_LIFT:
		# Лифт — строго вертикально или строго горизонтально (ход 3 м).
		if absi(c.y - _drag_start.y) > absi(c.x - _drag_start.x):
			r = Rect2i(_drag_start.x, r.position.y, 3 if mode != Hud.Mode.LIFT else 2, r.size.y)
		else:
			r = Rect2i(r.position.x, _drag_start.y - 1, r.size.x, 3)
		err = colony.validate(kind, r, _lift_material())
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
	var err := colony.validate(kind, r, hud.room_material() if kind == Project.Kind.ROOM else _lift_material())
	if mode == Hud.Mode.DRILL_LIFT:
		err = colony.drill_lift_error(r)
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
	_pending_material = hud.room_material() if kind == Project.Kind.ROOM else _lift_material()
	if mode == Hud.Mode.DRILL_LIFT:
		_pending_material = "drill_lift"
	_show_pending()


## Поменяли размер или материал комнаты: рамка и карточка обновляются на месте.
func _on_room_options(width: int, material: String) -> void:
	_room_w = width
	_pending_material = material
	var s := world_view.structures
	if mode != Hud.Mode.ROOM or s.preview.size == Vector2i.ZERO:
		return
	var placed := _room_rect(s.preview.position + Vector2i(s.preview.size.x / 2, 1))
	s.preview = placed[0]
	s.preview_ok = (placed[1] as String).is_empty()
	s.preview_text = "%d×%d" % [s.preview.size.x, s.preview.size.y]
	if s.preview_ok:
		_pending = s.preview
		_pending_kind = Project.Kind.ROOM
		_pending_workers = Project.recommended_workers(_pending_kind, _pending, colony.adults())
		_show_pending()
	elif not s.preview_ok:
		hud.hide_info()


## Комната выбранного размера под пальцем; сама прилипает к земле или этажу рядом.
## Возвращает [рамка, ошибка (пусто — можно)].
func _room_rect(c: Vector2i) -> Array:
	var base := Rect2i(c.x - _room_w / 2, c.y - 1, _room_w, Project.ROOM_HEIGHT)
	# Касание в готовой шахте: комната встаёт ровно по её высоте и в её пределах,
	# а ошибка — настоящая причина (например, вес сверху), а не «сдвиг по высоте».
	var m := colony.project_at(c)
	if m != null and m.kind == Project.Kind.MINE and m.phase == Project.Phase.DONE:
		var x := base.position.x
		if _room_w <= m.rect.size.x:
			x = clampi(x, m.rect.position.x, m.rect.end.x - _room_w)
		var snapped := Rect2i(x, m.rect.position.y, _room_w, Project.ROOM_HEIGHT)
		return [snapped, colony.validate(Project.Kind.ROOM, snapped, hud.room_material())]
	for dy in [0, 1, -1, 2, -2, 3, -3]:
		var r := Rect2i(base.position + Vector2i(0, dy), base.size)
		if colony.validate(Project.Kind.ROOM, r, hud.room_material()).is_empty():
			return [r, ""]
	return [base, colony.validate(Project.Kind.ROOM, base, hud.room_material())]


func _mode_kind() -> int:
	match mode:
		Hud.Mode.ROOM:
			return Project.Kind.ROOM
		Hud.Mode.BRIDGE:
			return Project.Kind.BRIDGE
		Hud.Mode.MINE:
			return Project.Kind.MINE
		Hud.Mode.LIFT, Hud.Mode.CARGO_LIFT:
			return Project.Kind.LIFT
		Hud.Mode.DRILL, Hud.Mode.DRILL_LIFT:
			return Project.Kind.DRILL
		Hud.Mode.PROBE:
			return Project.Kind.PROBE
	return Project.Kind.TUNNEL


## Лифт передаёт «грузовой ли» через материал стройки.
func _lift_material() -> String:
	return "cargo" if mode == Hud.Mode.CARGO_LIFT else "wood"


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
	var spec := _pending_spec()
	spec["controls"] = controls
	spec["controls_first"] = true
	spec["actions"] = [["Построить", func() -> void:
		if _confirm_pending():
			_to_look(), "primary"], ["Отмена", _to_look]]
	hud.show_panel(spec)


func _pending_spec() -> Dictionary:
	var r := _pending
	var kind := _pending_kind
	var rows := []
	var cost := Project.lift_cost(r, _pending_material == "cargo") if kind == Project.Kind.LIFT \
		else (Project.drill_cost(r) if kind == Project.Kind.DRILL else Project.cost_for(kind, r, _pending_material))
	if _pending_material == "drill_lift":
		# Бур и кабина грузового лифта над ним.
		cost = Project.drill_cost(r).duplicate()
		var lc := Project.lift_cost(Rect2i(0, 0, 3, 2), true)
		for k in lc:
			cost[k] = int(cost.get(k, 0)) + int(lc[k])
	if not cost.is_empty():
		rows.append({"type": "resources", "label": "Материалы", "items": _cost_items(cost)})
	var chips := []
	if kind == Project.Kind.ROOM or kind == Project.Kind.TUNNEL or kind == Project.Kind.MINE:
		var sw := _support_estimate(kind, r)
		var have: int = colony.inventory.get("wood", 0)
		if sw > 0:
			# Нет дерева — крепь из железа (его вдвое меньше), после «Железного каркаса».
			var iron: int = colony.inventory.get("iron", 0)
			if have < sw and iron > 0 and colony.research.has("steel_frame"):
				rows.append({"type": "resources", "label": "Укрепление", "items": [["iron", iron, ceili(sw / 2.0), iron >= ceili(sw / 2.0)]]})
			else:
				rows.append({"type": "resources", "label": "Укрепление", "items": [["wood", have, sw, have >= sw]]})
	var support := colony.support_needed(kind, r)
	if support > 0:
		var span: Array = colony.ceiling_span(r)
		rows.append({"type": "text", "text": "Потолок из «%s» держит без опор %d м — укрепление усиленное" % [
			Mat.name_of(span[1]).to_lower(), span[0]]})
	for lower in colony.ladders_needed(r):
		rows.append({"type": "resources", "label": "Лестница внизу", "items": _cost_items(RoomType.ladder_cost(lower))})
	if kind == Project.Kind.ROOM:
		var tmp := Project.new()
		tmp.id = -1
		tmp.kind = kind
		tmp.rect = r
		tmp.material = _pending_material
		var predicted := colony.loads.compute(tmp)
		# Будущая нагрузка на саму комнату: вес этажей, которые уже стоят над ней.
		var own := colony.loads.utilization(tmp, predicted)
		rows.append(_progress("Нагрузка на неё", minf(own, 1.0), "%d т из %d т" % [
			roundi(float(predicted.get(-1, 0.0))), roundi(Loads.bearing(tmp))], _wear_color(own * 0.9)))
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
	if not chips.is_empty():
		rows.append({"type": "chips", "items": chips})
	if not colony.has_access(r):
		rows.append({"type": "warning", "text": "К зоне нет прохода — сначала проложите к ней тоннель."})
	elif not colony.can_reach(r):
		rows.append({"type": "warning", "text": "Гаврики не могут сюда дойти — стройка не начнётся."})
	var title := "%s %d×%d" % [("Грузовой лифт" if _pending_material == "cargo" else "Лифт") if kind == Project.Kind.LIFT
		else Project.kind_name(kind), r.size.x, r.size.y]
	if kind == Project.Kind.ROOM:
		var plan := hud.room_purpose()
		if plan > 0:
			title = "%s %d×%d" % [RoomType.purpose_name(plan), r.size.x, r.size.y]
			var tmp2 := Project.new()
			tmp2.kind = kind
			tmp2.rect = r
			var ec := RoomType.equip_cost(plan, tmp2)
			if not ec.is_empty():
				rows.insert(1 if not rows.is_empty() else 0, {"type": "resources", "label": "Обустройство (после постройки)", "items": _cost_items(ec)})
		title += " · " + Project.MATERIALS[_pending_material][0].to_lower()
	return {"title": title, "rows": rows}


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


## Картинки плиток меню стройки: назначение -> мебель.
const ROOM_PICS := {
	RoomType.NONE: "", RoomType.HOME: "home/bed_blue", RoomType.STORAGE: "storage/crate_wood",
	RoomType.GRANARY: "granary/basket_fish", RoomType.FARM: "farm/shoots_3", RoomType.DINING: "dining/table",
	RoomType.HEARTH: "hearth/stone_on", RoomType.HEARTH_BRICK: "hearth/brick_on", RoomType.LAB: "lab/microscope",
	RoomType.PUMP: "pump/pump_on", RoomType.VENT: "degas/compressor", RoomType.DEGAS: "degas/tank_2",
	RoomType.KILN: "kiln/kiln_on", RoomType.FORGE: "storage/crate_metal", RoomType.GENERATOR: "generator/coal_on",
	RoomType.GAS_GEN: "generator/gas_on", RoomType.OIL_PUMP: "pump/pump_on", RoomType.OIL_TANK: "degas/tank_3",
	RoomType.REFINERY: "lab/still", RoomType.DIESEL_GEN: "generator/coal_on", RoomType.ENRICHMENT: "lab/crystal",
}


## Неизученные инструменты стройки: режим -> почему нельзя.
func _build_tool_locks() -> Dictionary:
	var out := {}
	for pair in [[Hud.Mode.LIFT, "lifts"], [Hud.Mode.CARGO_LIFT, "cargo_lifts"], [Hud.Mode.DRILL, "drill_rig"], [Hud.Mode.DRILL_LIFT, "drill_lift"], [Hud.Mode.PROBE, "geoprobe"]]:
		if not colony.research.has(pair[1]):
			out[pair[0]] = "Сначала изучите «%s» (Наука)" % Research.tech_name(pair[1])
	return out


## Плитки комнат для меню стройки: все виды, неизученные — неактивные с подсказкой.
func _build_room_items() -> Array:
	var order := [RoomType.NONE, RoomType.HOME, RoomType.STORAGE, RoomType.GRANARY, RoomType.FARM, RoomType.DINING,
		RoomType.HEARTH, RoomType.HEARTH_BRICK, RoomType.LAB, RoomType.PUMP, RoomType.VENT, RoomType.DEGAS,
		RoomType.KILN, RoomType.FORGE, RoomType.GENERATOR, RoomType.GAS_GEN,
		RoomType.OIL_PUMP, RoomType.OIL_TANK, RoomType.REFINERY, RoomType.DIESEL_GEN, RoomType.ENRICHMENT, RoomType.LAUNCHPAD]
	var out := []
	for t in order:
		var need: String = RoomType.REQUIRES.get(t, "")
		var ok := colony.research.has(need)
		var nm := "Пустая" if t == RoomType.NONE else RoomType.purpose_name(t).replace("Очаг (каменные печи)", "Очаг").replace(
			"Очаг (кирпичные печи)", "Очаг кирпичный")
		nm = {"Нефтекачалка": "Нефте-\nкачалка", "Нефтехранилище": "Нефте-\nхранилище"}.get(nm, nm)
		var pic: String = ROOM_PICS.get(t, "")
		out.append({"id": t, "name": nm, "tex": "res://assets/furniture/%s.png" % pic if not pic.is_empty() else "",
			"glyph": "rocket" if t == RoomType.LAUNCHPAD else "room", "ok": ok, "why": "%s: сначала изучите «%s» (Наука)" % [nm, Research.tech_name(need)] if not ok else ""})
	return out


func _confirm_pending() -> bool:
	var drill_lift := _pending_material == "drill_lift"
	var err := colony.drill_lift_error(_pending) if drill_lift else colony.validate(_pending_kind, _pending, _pending_material)
	if not err.is_empty():
		hud.log_event(err, "warning")
		return false
	var p := colony.create_drill_lift(_pending, _pending_workers) if drill_lift \
		else colony.create_project(_pending_kind, _pending, _pending_workers, _pending_material)
	if p != null and _pending_kind == Project.Kind.ROOM:
		p.plan_purpose = hud.room_purpose()
	_clear_preview()
	if p != null:
		hud.log_event("Заложено: %s, рабочих: %d" % [p.title(), p.workers], "info")
	return p != null


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
				rows.append({"type": "text", "text": "Ягоды отрастают. Голодные гаврики едят прямо с куста."})
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
		roundi(world.gen.oxygen_ratio(c.y, surf) * 100.0)]
	var g := colony.elements.gas_at(c)
	if g >= Elements.GAS_MIN:
		t += " · метан %d%%%s" % [roundi(g * 100.0), " — взрывоопасно!" if g >= Elements.GAS_EXPLOSIVE else ""]
	return t


func _update_status() -> void:
	var c := world_view.camera_cell()
	var depth := c.y - world.gen.surface_y(c.x)
	var where := ("Высота %s м" % Fmt.int_spaced(-c.y)) if depth < 0 else ("Глубина %s м" % Fmt.int_spaced(depth))
	# Телефон не успевает за выбранной скоростью — показываем, с какой идёт на деле.
	var want: float = SPEEDS[_speed_idx]
	if want > 1.0 and _real_speed < want * 0.85:
		where += " · ×%d → ×%.0f" % [roundi(want), maxf(1.0, _real_speed)]
	hud.set_status(where)
	var hungry := 0
	for u in colony.units:
		if u.satiety < 25.0:
			hungry += 1
	hud.set_resources(colony.inventory, colony.units.size(), hungry, colony.power_made, colony.power_used,
		colony.research.has("electricity"))
	hud.set_room_materials(colony.available_materials())
	var space := universe.worlds.size() > 1 or not universe.flights.is_empty()
	for e in universe.worlds:
		space = space or (e["colony"] as Colony).research.has("rocketry")
	hud.set_worlds_visible(space)
	if _planet != "earth":
		var s := world.gen.surface_y(colony.home.x)
		hud.set_date("%s · %s · %+d °C снаружи" % [Planet.planet_name(_planet), colony.date_text().split(" · ")[0],
			roundi(world.gen.temperature(s - 1, s))], "")
	else:
		hud.set_date("%s · %+d °C" % [colony.date_text(), roundi(Env.SURFACE_TEMP + colony.season_delta())], _weather_icon())


## Камера не уходит дальше разведанного: по бокам — куда доходили гаврики,
## вниз — до самых глубоких работ или открытой породы, вверх — чуть выше самых высоких построек.
func _clamp_camera() -> void:
	var o := Vector2(world_view.origin)
	var t := ChunkView.TILE
	var min_x := (colony.explored_min - 4 - o.x) * t
	var max_x := (colony.explored_max + 5 - o.x) * t
	var min_y := (mini(colony.highest_y, colony.home.y) - 40 - o.y) * t
	# Вниз — и до самого глубокого открытого (зонд геоскважины, обзор бура, пещеры).
	var max_y := (maxi(maxi(colony.deepest_y, world.deepest_seen), colony.home.y) + 14 - o.y) * t
	camera.position = Vector2(clampf(camera.position.x, min_x, max_x), clampf(camera.position.y, min_y, max_y))


## Значок у даты. Погоды в игре пока нет — значок по времени суток и сезону
## (зимой идёт снег, как в SeasonFx); дождь, гроза и туман — на будущее.
func _weather_icon() -> String:
	if colony.daylight() < 0.3:
		return "moon"
	match colony.season():
		Colony.Season.WINTER:
			return "snow"
		Colony.Season.AUTUMN:
			return "cloud"
		Colony.Season.SPRING:
			return "sun_cloud"
	return "sun"


func _update_sky(delta := 0.0) -> void:
	var half_h := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var top_y := world_view.origin.y + (camera.position.y - half_h) / ChunkView.TILE
	var bottom_y := world_view.origin.y + (camera.position.y + half_h) / ChunkView.TILE
	var m := _sky.material as ShaderMaterial
	m.set_shader_parameter("alt_top", -top_y)
	m.set_shader_parameter("alt_bottom", -bottom_y)
	var light := colony.daylight()
	m.set_shader_parameter("daylight", light)
	m.set_shader_parameter("winter", 1.0 if colony.is_winter() else 0.0)
	m.set_shader_parameter("cam_x", world_view.origin.x + camera.position.x / ChunkView.TILE)
	m.set_shader_parameter("view_w", get_viewport_rect().size.x / camera.zoom.x / ChunkView.TILE)
	# Фон стоит на самой низкой земле в кадре (с запасом по краям), иначе там, где
	# поверхность ниже базы, под холмами пусто. Сдвиг плавный, чтобы фон не прыгал.
	var view_w: float = get_viewport_rect().size.x / camera.zoom.x / ChunkView.TILE
	var cx: float = world_view.origin.x + camera.position.x / ChunkView.TILE
	var low := world.gen.land_y(int(cx))
	var x := int(cx - view_w * 0.6)
	while x <= int(cx + view_w * 0.6):
		low = maxi(low, world.gen.land_y(x))
		x += 3
	if is_nan(_sky_ground) or delta <= 0.0:
		_sky_ground = low
	else:
		_sky_ground = lerpf(_sky_ground, low, 1.0 - exp(-delta * 1.5))
	m.set_shader_parameter("ground_alt", -_sky_ground)
	world_view.set_season(colony.is_winter(), colony.calendar_month())
	# Ночью мир чуть темнее.
	_night.color = Color(0.62, 0.66, 0.85).lerp(Color.WHITE, light)
