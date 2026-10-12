extends Node2D
## Точка входа: собирает мир, камеру, интерфейс; сохранение и оффлайн-прогресс.

const AUTOSAVE_SEC := 30.0
## Сколько времени отсутствия засчитывается (стимул заходить регулярно).
const OFFLINE_CAP_SEC := 8.0 * 3600.0
const SPEEDS := [1.0, 10.0, 100.0]
const STATUS_INTERVAL := 0.2

var world: WorldData
var dig: DigSystem
var world_view: WorldView
var camera: CameraController
var hud: Hud
var _sky: ColorRect
var _speed_idx := 0
var _autosave := 0.0
var _status_timer := 0.0
var _home := Vector2i.ZERO
var _erasing := false
var _paused_at := 0.0


func _ready() -> void:
	var data := SaveSystem.load_data()
	var seed_value := int(data["seed"]) if data.has("seed") else _new_seed()
	world = WorldData.new(WorldGen.new(seed_value))
	dig = DigSystem.new(world)
	_home = Vector2i(0, world.gen.surface_y(0))
	_build_scene()
	dig.event_logged.connect(hud.log_event)

	var start := _home + Vector2i(0, -4)
	if data.is_empty():
		hud.log_event("Нажмите «Копать» и проведите пальцем по земле. Двумя пальцами — двигать и масштабировать.", "info")
	else:
		SaveSystem.apply(data, world, dig)
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
	camera.zoom = Vector2(1.2, 1.2)
	add_child(camera)
	camera.make_current()

	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(world, dig, camera)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = Hud.new()
	ui_layer.add_child(hud)

	camera.tapped.connect(_on_tap)
	camera.painted.connect(_on_paint)
	hud.mode_changed.connect(func(on: bool) -> void: camera.paint_mode = on)
	hud.home_pressed.connect(func() -> void: world_view.focus_cell(_home + Vector2i(0, -4)))
	hud.speed_pressed.connect(_cycle_speed)


func _process(delta: float) -> void:
	# Большие паузы (сворачивание) учитываются как оффлайн, а не через delta.
	var dt := minf(delta, 0.25)
	dig.advance(dt * SPEEDS[_speed_idx])
	_update_sky()
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = STATUS_INTERVAL
		_update_status()
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
	SaveSystem.save(world, dig, world_view.camera_cell())


func _apply_offline(since_unix: float) -> void:
	var away := Time.get_unix_time_from_system() - since_unix
	if since_unix <= 0.0 or away < 60.0:
		return
	var simulated := minf(away, OFFLINE_CAP_SEC)
	var inv_before := dig.inventory.duplicate()
	var dug := dig.advance(simulated)
	var lines: PackedStringArray = ["Вас не было %s." % Fmt.duration(away)]
	if away > OFFLINE_CAP_SEC:
		lines.append("Бригады работали первые %s — дальше им нужны ваши указания." % Fmt.duration(OFFLINE_CAP_SEC))
	if dug == 0:
		lines.append("Работы стояли: очередь раскопок пуста.")
	else:
		lines.append("Выкопано клеток: %d." % dug)
		for k in dig.inventory:
			var gained: int = dig.inventory[k] - int(inv_before.get(k, 0))
			if gained > 0:
				lines.append("+%s %s" % [Fmt.int_spaced(gained), Mat.resource_name(k)])
	hud.show_message("С возвращением!", "\n".join(lines))


func _cycle_speed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEEDS.size()
	hud.set_speed_text("×%d" % int(SPEEDS[_speed_idx]))


func _on_tap(screen_pos: Vector2) -> void:
	hud.show_cell(_cell_info(world_view.screen_to_cell(screen_pos)))


func _on_paint(screen_pos: Vector2, first: bool) -> void:
	var c := world_view.screen_to_cell(screen_pos)
	if first:
		_erasing = dig.has_job(c)
	if _erasing:
		dig.cancel_order(c)
	else:
		dig.add_order(c)


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
				lines.append("Плотность %s кг/м³ · прочность %s МПа" % [
					Fmt.int_spaced(int(Mat.density(m))), str(Mat.strength(m))])
				lines.append("Время проходки: %s" % Fmt.duration(dig.dig_time(c)))
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
	var jobs := "очередь: %d" % dig.order.size() if not dig.order.is_empty() else "бригады свободны"
	hud.set_status("%s · %s\n%s\nВыкопано %s · %s" % [
		where, world.gen.zone_name(c.x, c.y), _env_text(c), Fmt.int_spaced(dig.cells_dug), jobs])
	hud.set_resources(dig.inventory)


func _update_sky() -> void:
	var half_h := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var top_y := world_view.origin.y + (camera.position.y - half_h) / ChunkView.TILE
	var bottom_y := world_view.origin.y + (camera.position.y + half_h) / ChunkView.TILE
	var m := _sky.material as ShaderMaterial
	m.set_shader_parameter("alt_top", -top_y)
	m.set_shader_parameter("alt_bottom", -bottom_y)
