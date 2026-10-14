extends Node2D
## Точка входа: собирает мир, колонию, камеру, интерфейс; режимы стройки,
## сохранение и оффлайн-прогресс.

const AUTOSAVE_SEC := 30.0
## Сколько времени отсутствия засчитывается (стимул заходить регулярно).
const OFFLINE_CAP_SEC := 3.0 * 3600.0
const SPEEDS := [1.0, 2.0, 10.0, 20.0]
const STATUS_INTERVAL := 0.2

var world: WorldData
var colony: Colony
var world_view: WorldView
var camera: CameraController
var hud: Hud
var mode := Hud.Mode.LOOK
var _sky: ColorRect
## Высота земли, к которой привязан фон (y клетки): самая низкая земля на экране, сглаженно.
var _sky_ground := NAN
var _night: CanvasModulate
var _speed_idx := 0
var _autosave := 0.0
var _status_timer := 0.0
var _home := Vector2i.ZERO
var _paused_at := 0.0
## Игра в фоне: пока игрок вышел, жители работают (оффлайн-прогресс). По умолчанию — нет.
var _background := false
## Приложение свёрнуто — симуляция стоит.
var _away := false
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
## Ширина комнаты для установки и кого отправляем в точку.
var _room_w := 6
var _send_unit := 0


func _ready() -> void:
	# Шрифт игры — и для подписей в мире (они берут шрифт по умолчанию).
	ThemeDB.fallback_font = Fonts.bold()
	ModelSprites.enabled = bool(_settings().get("models", true))
	_background = bool(_settings().get("background", false))
	var data := SaveSystem.load_data()
	var seed_value := int(data["seed"]) if data.has("seed") else _new_seed()
	# Старые сохранения (без версии генерации) — на первой версии, чтобы мир не изменился.
	var gen_version := int(data.get("gen", 1)) if data.has("seed") else WorldGen.LATEST
	world = WorldData.new(WorldGen.new(seed_value, gen_version))
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


## Игру закрыли (любым способом) — сохраняем последнее состояние.
func _exit_tree() -> void:
	if world != null:
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
	hud.home_pressed.connect(func() -> void: world_view.focus_cell(_home + Vector2i(0, -3)))
	hud.speed_selected.connect(func(i: int) -> void: _speed_idx = i)
	hud.save_pressed.connect(func() -> void:
		_save()
		hud.log_event("Игра сохранена", "good"))
	hud.new_game_confirmed.connect(_new_game)
	hud.science_pressed.connect(_show_science)
	hud.people_pressed.connect(_show_people)
	hud.models_toggled.connect(func(on: bool) -> void:
		ModelSprites.enabled = on
		_save_setting("models", on)
		world_view.units_layer.refresh())
	hud.set_background(_background)
	hud.background_toggled.connect(func(on: bool) -> void:
		_background = on
		_save_setting("background", on))
	hud.room_options_changed.connect(_on_room_options)


func _process(delta: float) -> void:
	# Большие паузы (сворачивание) учитываются как оффлайн, а не через delta.
	var dt := 0.0 if _away else minf(delta, 0.25)
	colony.update(dt * SPEEDS[_speed_idx])
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
		_update_status()
		_refresh_info()
	_autosave += delta
	if _autosave >= AUTOSAVE_SEC:
		_autosave = 0.0
		_save()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Вышли из игры — она на паузе (а с «Игрой в фоне» — посчитаем, сколько успели).
			if world != null and not _away:
				_away = true
				_save()
				_paused_at = Time.get_unix_time_from_system()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if world != null and _away:
				_away = false
				if _paused_at > 0.0:
					_apply_offline(_paused_at)
				_paused_at = 0.0
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			# «Назад» на Android закрывает игру сразу — сохраняем в этот момент.
			if world != null:
				_save()


const NEW_GAME_PATH := "user://new_game.json"
const SETTINGS_PATH := "user://settings.json"


func _save_setting(key: String, value: Variant) -> void:
	var d := _settings()
	d[key] = value
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


## Настройки игры (не колонии): переживают новую игру.
func _settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


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
	if since_unix <= 0.0 or away < 60.0 or not _background:
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


func _set_mode(m: int, room_width := 0) -> void:
	mode = m
	if room_width > 0:
		_room_w = room_width
	camera.paint_mode = m == Hud.Mode.TUNNEL or m == Hud.Mode.ROOM or m == Hud.Mode.BRIDGE
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
	rows.append({"type": "text", "text": "Добытое ляжет здесь же, жители отнесут его на склад."})
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
			["Жители", _show_people]]
	hud.show_panel(spec)


## Выбор места работы для жителя: где есть места и насколько он там хорош.
func _pick_workplace(u: Unit) -> void:
	# Список выбора не обновляем каждую секунду — иначе его перезапишет карточка.
	_info_target = []
	var items := []
	for role in [[Unit.Prof.BUILDER, "в первую очередь идёт на стройки: копает, строит, обустраивает, чинит"],
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
			"info": "мест %d/%d · подходит на %d%% (%s)" % [taken, colony.work_slots(p), roundi(colony.suitability(u, p) * 100),
				Genetics.STAT_NAMES[colony.work_stat(p)].to_lower()],
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
		var pers: String = g.get("personality", "")
		if not pers.is_empty():
			tags.append(["Характер: " + pers, Color.WHITE])
		if Genetics.is_super(g):
			tags.append(["СВЕРХЮНИТ — все характеристики ×2", Color(0.3, 0.9, 0.85)])
		var mt := Genetics.mutation_text(g)
		if not mt.is_empty():
			var rarity_cols := [Color(0.6, 0.85, 0.6), Color(0.5, 0.75, 1.0), Color(0.8, 0.6, 1.0), Color(1.0, 0.8, 0.3)]
			tags.append([mt, rarity_cols[maxi(0, Genetics.rarity(g))]])
		var ab := Genetics.ability_text(g)
		if not ab.is_empty():
			tags.append(["Умеет: " + ab, Hud.MUTED])
		tags.append(["Занятие: " + colony.role_name(u).to_lower(), Hud.MUTED])
		rows.append({"type": "portrait", "looks": Genetics.looks(g), "tags": tags})
	rows.append_array([_need_bar("Сытость", u.satiety), _need_bar("Бодрость", u.energy), _need_bar("Настроение", u.mood())])
	if u.health < 99.5:
		rows.append(_need_bar("Здоровье", u.health))
	if u.task == Unit.Task.HAUL and u.carry_amount > 0:
		rows.append({"type": "resources", "label": "Несёт", "items": [[u.carry_key, u.carry_amount, -1, true]]})
	if not u.stats.is_empty():
		rows.append({"type": "section", "text": "Характеристики (100% — обычный житель)"})
		var items := []
		for k in Genetics.STATS:
			var v: float = u.stats[k]
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
	if p.phase == Project.Phase.DONE and p.paused:
		actions.append(["Продолжить", func() -> void:
			colony.set_paused(p, false)
			_show_project(p)])
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
		if RoomType.is_store(p.purpose):
			controls.append(_storage_targets(p))
			if p.purpose == RoomType.STORAGE:
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
	if colony.is_workplace(p):
		controls.push_front(_workers_list(p))
		actions.push_front(["Назначить", func() -> void: _pick_worker(p), "primary"])
	_info_target = ["project", p.id, preview["v"]]
	var spec := _project_spec(p, preview["v"])
	spec["actions"] = actions
	spec["controls"] = controls
	spec["controls_first"] = RoomType.is_store(p.purpose) and p.phase == Project.Phase.DONE
	hud.show_panel(spec)


## Кто работает в комнате (назначенные игроком).
func _workers_list(p: Project) -> Dictionary:
	var items := []
	for u in colony.assigned_to(p):
		items.append({"looks": Genetics.looks(u.genome), "name": u.name,
			"info": "подходит на %d%% · %s" % [roundi(colony.suitability(u, p) * 100), Unit.TASK_NAMES[u.task]],
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
	cands.sort_custom(func(a: Unit, b: Unit) -> bool: return colony.suitability(a, p) > colony.suitability(b, p))
	var stat := colony.work_stat(p)
	for u: Unit in cands:
		var info := "подходит на %d%% · %s %d%% · навык %d" % [roundi(colony.suitability(u, p) * 100),
			Genetics.STAT_NAMES[stat].to_lower(), roundi(u.stat(stat) * 100), u.level(colony.work_skill(p))]
		if u.workplace != 0:
			info += " · сейчас: " + colony.workplace_name(colony.project_by_id(u.workplace))
		items.append({"looks": Genetics.looks(u.genome), "name": u.name, "info": info, "button": "Назначить",
			"pick": func() -> void:
				var err := colony.assign_work(u, p)
				if not err.is_empty():
					hud.log_event(err, "warning")
				_show_project(p)})
	hud.show_panel({"title": "Назначить: " + colony.workplace_name(p),
		"subtitle": "мест %d/%d · важно: %s" % [colony.assigned_to(p).size(), colony.work_slots(p), Genetics.STAT_NAMES[stat].to_lower()],
		"controls": [{"type": "people", "label": "Лучшие для этой работы — сверху:", "items": items, "empty": "Все взрослые уже здесь."}],
		"actions": [["Назад", func() -> void: _show_project(p)]]})


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
	return {"type": "targets", "label": "Держать в запасе (назначенные работники добывают до нормы):", "items": items,
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
				rows.append(_progress("Укрепление", float(p.supported.size()) / p.needs_support.size(),
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
			if not colony.can_fish_from(p):
				rows.append({"type": "text", "text": "Зима: озеро подо льдом — ловить можно только с пристани."})
			elif colony.is_winter():
				chips.append(["", "зимой улов вдвое медленнее"])
	if p.phase == Project.Phase.DONE and p.kind == Project.Kind.ROOM:
		chips.append(["", "внутри %+d °C" % roundi(colony.room_temp(p))])
		# Продукция и урожай лежат на полу, пока подсобные не унесут их на склад или в амбар.
		var lying := {}
		for c: Vector2i in colony.drops:
			if p.rect.has_point(c):
				for k in colony.drops[c]:
					lying[k] = lying.get(k, 0) + int(colony.drops[c][k])
		if not lying.is_empty():
			var items := []
			for k in lying:
				items.append([k, lying[k], -1, true])
			rows.append({"type": "resources", "label": "Лежит на полу", "items": items})
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
				var free := colony.beds_total() - colony.units.size() - colony.pregnant_count()
				chips.append(["people", "мест для детей в колонии: %d" % maxi(0, free)])
			RoomType.STORAGE, RoomType.GRANARY:
				chips.append(["people", "работников %d/%d" % [colony.assigned_to(p).size(), colony.work_slots(p)]])
				chips.append(["", "+%d места каждому %s" % [RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p),
					"виду еды" if p.purpose == RoomType.GRANARY else "ресурсу"]])
				if colony.assigned_to(p).is_empty():
					rows.append({"type": "text", "text": "Нет работника — сюда никто ничего не носит. Назначьте работника (кнопка «Работа» у жителя)."})
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
				var minds := 0.0
				for w in colony.assigned_to(p):
					minds += w.stat("intellect") * w.speed("science")
				chips.append(["", "скорость науки %d%% (интеллект учёных)" % roundi(minds * 100.0)])
				if colony.assigned_to(p).is_empty():
					rows.append({"type": "warning", "text": "Нет учёных — назначьте жителя («Назначить»): исследуют только назначенные, быстрее — умные."})
				var cur := colony.research.current
				if cur.is_empty():
					rows.append({"type": "text", "text": "Нечего изучать — выберите исследование («Наука»)."})
				else:
					rows.append(_progress(Research.tech_name(cur), colony.research.progress / colony.research.cost(cur)))
			RoomType.GENERATOR:
				chips.append(["power", "даёт %d, колонии нужно %d" % [RoomType.POWER_MAKE, colony.power_used]])
				rows.append(_progress("Топливо", clampf(p.farm_progress / RoomType.FUEL_TIME, 0.0, 1.0),
					"%d с" % maxi(0, roundi(p.farm_progress)), Color(0.95, 0.6, 0.2)))
				rows.append({"type": "text", "text": "Жжёт 1 метан, 1 уголь или 2 дерева за %d с (сначала метан). Работая, греет всё вокруг (на 6 м от стен)." % int(RoomType.FUEL_TIME)})
			RoomType.HEARTH:
				chips.append(["", "горит" if p.burning else "не горит"])
				var n := RoomType.stoves(p)
				var zone := RoomType.heat_zone(p)
				chips.append(["", "печей %d" % n])
				rows.append({"type": "text", "text": "Каждая печь жжёт 1 дерево за %d с, пока вокруг холоднее %d °C. Греет от стен комнаты: в %d м — полное тепло (+%d °C), дальше слабее, до %d м. Жилые и ферму — ставьте рядом." \
					% [int(RoomType.HEARTH_FUEL_TIME), int(Colony.HEARTH_ON_BELOW), zone.x, int(Colony.HEAT), zone.y]})
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


# --- Жители: кто чем занят, строители и подсобные -----------------------------------------

## Что житель делает прямо сейчас.
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
	return {"title": "Жители", "subtitle": "взрослых %d · детей %d" % [adults, colony.units.size() - adults],
		"rows": [{"type": "chips", "label": "Сейчас", "items": chips},
			{"type": "text", "text": "На стройку первыми идут строители, потом свободные. Носят первыми подсобные, потом свободные — но свободный бросит ношу, если на стройке есть место."}]}


func _show_people() -> void:
	_select(null, null)
	hud.close_overlays()
	_info_target = ["people"]
	var spec := _people_spec()
	var groups := [["Строители", func(u: Unit) -> bool: return u.workplace == 0 and u.profession == Unit.Prof.BUILDER],
		["Подсобные рабочие", func(u: Unit) -> bool: return u.workplace == 0 and u.profession == Unit.Prof.HAULER],
		["На местах работы", func(u: Unit) -> bool: return not u.child and u.workplace != 0],
		["Свободные", func(u: Unit) -> bool: return colony.is_free(u)],
		["Дети", func(u: Unit) -> bool: return u.child]]
	var controls := []
	for g in groups:
		var members := colony.units.filter(g[1])
		var items := []
		for u: Unit in members:
			var item := {"looks": Genetics.looks(u.genome), "name": u.name, "info": _doing(u),
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
		["+ Подсобный", func() -> void: _pick_role(Unit.Prof.HAULER), "primary"]]
	hud.show_panel(spec)


## Кого назначить строителем или подсобным: сначала свободные, лучшие — сверху.
func _pick_role(prof: int) -> void:
	_info_target = []
	var stat := "agility" if prof == Unit.Prof.BUILDER else "strength"
	var skill := "build" if prof == Unit.Prof.BUILDER else "gather"
	var cands := colony.units.filter(func(o: Unit) -> bool:
		return not o.child and not (o.workplace == 0 and o.profession == prof))
	var score := func(o: Unit) -> float:
		return Colony.soft(o.stat(stat)) * o.speed(skill) * float(o.ability("work")) + (1.0 if colony.is_free(o) else 0.0)
	cands.sort_custom(func(a: Unit, b: Unit) -> bool: return score.call(a) > score.call(b))
	var items := []
	for o: Unit in cands:
		items.append({"looks": Genetics.looks(o.genome), "name": o.name,
			"info": "%s · %s %d%% · навык %d" % [colony.role_name(o).to_lower(), Genetics.STAT_NAMES[stat].to_lower(),
				roundi(o.stat(stat) * 100), o.level(skill)],
			"button": "Назначить", "pick": func() -> void:
				colony.set_profession(o, prof)
				_show_people()})
	hud.show_panel({"title": "Назначить: " + Unit.PROF_NAMES[prof].to_lower(), "subtitle": "сначала свободные, лучшие — сверху",
		"controls": [{"type": "people", "label": "Кого назначить:", "items": items, "empty": "Некого назначить."}],
		"actions": [["Назад", _show_people]]})


## Наука: текущее исследование и дерево технологий.
func _show_science() -> void:
	_select(null, null)
	hud.close_overlays()
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
		rows.append({"type": "text", "text": "Выберите, что изучать. Изучают только назначенные в лабораторию учёные; чем выше интеллект — тем быстрее."})
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
	_pending_material = hud.room_material() if kind == Project.Kind.ROOM else "wood"
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
	if hud.info_visible() and s.preview_ok:
		_pending = s.preview
		_show_pending()
	elif not s.preview_ok:
		hud.hide_info()


## Комната выбранного размера под пальцем; сама прилипает к земле или этажу рядом.
## Возвращает [рамка, ошибка (пусто — можно)].
func _room_rect(c: Vector2i) -> Array:
	var base := Rect2i(c.x - _room_w / 2, c.y - 1, _room_w, Project.ROOM_HEIGHT)
	for dy in [0, 1, -1, 2, -2, 3, -3]:
		var r := Rect2i(base.position + Vector2i(0, dy), base.size)
		if colony.validate(Project.Kind.ROOM, r).is_empty():
			return [r, ""]
	return [base, colony.validate(Project.Kind.ROOM, base)]


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
	var cost := Project.cost_for(kind, r, _pending_material)
	if not cost.is_empty():
		rows.append({"type": "resources", "label": "Материалы", "items": _cost_items(cost)})
	var chips := []
	if kind == Project.Kind.ROOM or kind == Project.Kind.TUNNEL:
		var sw := _support_estimate(kind, r)
		var have: int = colony.inventory.get("wood", 0)
		if sw > 0:
			rows.append({"type": "resources", "label": "Укрепление", "items": [["wood", have, sw, have >= sw]]})
	var support := colony.support_needed(kind, r)
	if support > 0:
		var span: Array = colony.ceiling_span(r)
		rows.append({"type": "text", "text": "Потолок из «%s» держит без опор %d м — укрепление усиленное" % [
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
	if not chips.is_empty():
		rows.append({"type": "chips", "items": chips})
	if not colony.has_access(r):
		rows.append({"type": "warning", "text": "К зоне нет прохода — сначала проложите к ней тоннель."})
	elif not colony.can_reach(r):
		rows.append({"type": "warning", "text": "Жители не могут сюда дойти — стройка не начнётся."})
	var title := "%s %d×%d" % [Project.kind_name(kind), r.size.x, r.size.y]
	if kind == Project.Kind.ROOM:
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


func _confirm_pending() -> bool:
	var err := colony.validate(_pending_kind, _pending, _pending_material)
	if not err.is_empty():
		hud.log_event(err, "warning")
		return false
	var p := colony.create_project(_pending_kind, _pending, _pending_workers, _pending_material)
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
	hud.set_room_materials(colony.available_materials())
	hud.set_date("%s · %+d °C" % [colony.date_text(), roundi(Env.SURFACE_TEMP + colony.season_delta())], _weather_icon())


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
