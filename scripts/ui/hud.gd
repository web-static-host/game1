class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.

signal mode_changed(mode: int)
signal home_pressed
signal speed_pressed
signal save_pressed
signal new_game_confirmed

enum Mode { LOOK, TUNNEL, ROOM, HARVEST, BRIDGE }

const MODE_NAMES := ["Осмотр", "Тоннель", "Комната", "Сбор", "Мост"]
## Что входит в кнопку «Стройка».
const BUILD_MODES := [Mode.TUNNEL, Mode.ROOM, Mode.BRIDGE]
const MODE_HINTS := [
	"",
	"Тоннель: проведите пальцем рамку (высота от 2 м). Двумя пальцами — двигать карту.",
	"Комната: проведите пальцем рамку от 3×3 до 24×8. Двумя пальцами — двигать карту.",
	"Сбор: нажимайте на деревья, валуны и кусты. Кусты остаются — ягоды отрастают.",
	"Мост: проведите ряд прямо над водой — от берега до берега (мостик) или от берега в воду (пристань).",
]
const LOG_LINES := 4
const PANEL_WIDTH := 600
const KIND_COLORS := {
	"info": Color(0.85, 0.88, 0.95),
	"good": Color(0.55, 0.95, 0.55),
	"warning": Color(1.0, 0.8, 0.35),
	"danger": Color(1.0, 0.4, 0.35),
}

var _status: Label
var _resources: Label
var _build_btn: Button
var _build_row: HBoxContainer
var _menu: PanelContainer
var _menu_new: Button
var _new_armed := false
var _log: VBoxContainer
var _info_panel: PanelContainer
var _info_label: Label
var _info_buttons: HBoxContainer
var _info_stepper: VBoxContainer
var _mode_buttons: Array[Button] = []
var _btn_speed: Button
var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_text: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_build_top(column)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_build_bottom(column)
	_build_dialog()
	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", "dev"))
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	version.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	version.add_theme_constant_override("outline_size", 4)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.1, 0.8)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(10)
		match state:
			"normal", "disabled":
				sb.bg_color = Color(0.16, 0.18, 0.24, 0.92)
			"hover":
				sb.bg_color = Color(0.22, 0.25, 0.33, 0.95)
			"pressed", "hover_pressed":
				sb.bg_color = Color(0.85, 0.62, 0.18, 0.95)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	return t


func _build_top(column: VBoxContainer) -> void:
	# Одна короткая строка: жители и ресурсы. Остальное — в свойствах клетки/комнаты.
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(box)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.62)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	box.add_child(panel)
	_resources = Label.new()
	_resources.add_theme_font_size_override("font_size", 18)
	_resources.add_theme_color_override("font_color", Color(0.95, 0.88, 0.62))
	panel.add_child(_resources)
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	box.add_child(_log)


func _build_bottom(box: VBoxContainer) -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	box.add_child(_info_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_info_panel.add_child(v)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 20)
	v.add_child(_info_label)
	_info_stepper = VBoxContainer.new()
	_info_stepper.add_theme_constant_override("separation", 6)
	v.add_child(_info_stepper)
	_info_buttons = HBoxContainer.new()
	_info_buttons.add_theme_constant_override("separation", 8)
	v.add_child(_info_buttons)

	# Подменю «Стройка»: тоннель, комната, мост.
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 8)
	_build_row.visible = false
	box.add_child(_build_row)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	var group := ButtonGroup.new()
	_mode_buttons.resize(MODE_NAMES.size())
	for i in MODE_NAMES.size():
		var parent: Control = _build_row if BUILD_MODES.has(i) else bar
		var b := _button(parent, MODE_NAMES[i])
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_mode.bind(i))
		_mode_buttons[i] = b
		if i == Mode.LOOK:
			_build_btn = _button(bar, "Стройка")
			_build_btn.toggle_mode = true
			_build_btn.toggled.connect(func(on: bool) -> void: _build_row.visible = on)
	bar.move_child(_mode_buttons[Mode.HARVEST], bar.get_child_count() - 1)
	_mode_buttons[Mode.LOOK].button_pressed = true
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(12, 0)
	bar.add_child(sep)
	var home := _button(bar, "К базе")
	_btn_speed = _button(bar, "×1")
	var menu := _button(bar, "Меню")
	home.pressed.connect(func() -> void: home_pressed.emit())
	_btn_speed.pressed.connect(func() -> void: speed_pressed.emit())
	menu.pressed.connect(func() -> void:
		_new_armed = false
		_menu_new.text = "Новая игра"
		_menu.visible = not _menu.visible)


func _on_mode(i: int) -> void:
	hide_info()
	var building: bool = BUILD_MODES.has(i)
	_build_btn.set_pressed_no_signal(building)
	_build_btn.text = "Стройка: " + MODE_NAMES[i] if building else "Стройка"
	if not building:
		_build_row.visible = false
	if not MODE_HINTS[i].is_empty():
		log_event(MODE_HINTS[i], "info")
	mode_changed.emit(i)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 64)
	parent.add_child(b)
	return b


func _build_dialog() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_dialog = PanelContainer.new()
	_dialog.visible = false
	_dialog.custom_minimum_size = Vector2(560, 0)
	center.add_child(_dialog)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_dialog.add_child(v)
	_dialog_title = Label.new()
	_dialog_title.add_theme_font_size_override("font_size", 28)
	_dialog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_dialog_title)
	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(520, 0)
	v.add_child(_dialog_text)
	var ok := Button.new()
	ok.text = "Отлично"
	ok.custom_minimum_size = Vector2(0, 64)
	ok.pressed.connect(func() -> void: _dialog.visible = false)
	v.add_child(ok)
	_build_menu(center)


func _build_menu(center: CenterContainer) -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.custom_minimum_size = Vector2(420, 0)
	center.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_menu.add_child(v)
	var title := Label.new()
	title.text = "Меню"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	var resume := _menu_button(v, "Продолжить")
	resume.pressed.connect(func() -> void: _menu.visible = false)
	var save := _menu_button(v, "Сохранить игру")
	save.pressed.connect(func() -> void:
		save_pressed.emit()
		_menu.visible = false)
	_menu_new = _menu_button(v, "Новая игра")
	_menu_new.pressed.connect(func() -> void:
		if not _new_armed:
			_new_armed = true
			_menu_new.text = "Точно? Прогресс пропадёт — нажмите ещё раз"
			return
		_menu.visible = false
		new_game_confirmed.emit())


func _menu_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	parent.add_child(b)
	return b


func set_mode(mode: int) -> void:
	_mode_buttons[mode].button_pressed = true


func set_speed_text(text: String) -> void:
	_btn_speed.text = text


## Высотомер в правом верхнем углу (глубина или высота камеры).
func set_status(text: String) -> void:
	if _status == null:
		_status = Label.new()
		_status.add_theme_font_size_override("font_size", 17)
		_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_status.add_theme_constant_override("outline_size", 4)
		_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_status)
		_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		_status.position.y += 22
	_status.text = text
	_status.reset_size()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_status.position.y += 22


func set_resources(inventory: Dictionary, prefix := "") -> void:
	var parts: PackedStringArray = []
	if not prefix.is_empty():
		parts.append(prefix)
	# Дерево и камень — всегда первыми, это основа стройки.
	for k in ["food", "wood", "stone"]:
		parts.append("%s %s" % [Mat.resource_name(k), Fmt.int_spaced(inventory.get(k, 0))])
	var keys := inventory.keys()
	keys.sort()
	for k in keys:
		if not k in ["food", "wood", "stone"] and not RoomType.BULK.has(k) and inventory[k] > 0:
			parts.append("%s %s" % [Mat.resource_name(k), Fmt.int_spaced(inventory[k])])
	_resources.text = " · ".join(parts)


## Панель с описанием и кнопками. actions: [[текст, Callable], ...]
## controls: [{"label", "value", "min", "max", "changed": Callable(int), "options"?: Array}]
## — строки «Подпись: [−] значение [+]»; с options значение показывается текстом.
func show_info(text: String, actions: Array = [], controls: Array = []) -> void:
	_info_label.text = text
	for c in _info_stepper.get_children():
		c.queue_free()
	_info_stepper.visible = not controls.is_empty()
	for st in controls:
		_build_stepper(st)
	for c in _info_buttons.get_children():
		c.queue_free()
	for a in actions:
		var b := _button(_info_buttons, a[0])
		b.custom_minimum_size = Vector2(0, 56)
		var cb: Callable = a[1]
		b.pressed.connect(cb)
	_info_buttons.visible = not actions.is_empty()
	_info_panel.visible = true


## Набор галочек: {"type": "checks", "label", "items": [[ключ, подпись, вкл]], "toggled": Callable(ключ, вкл)}
func _build_checks(st: Dictionary) -> void:
	var label := Label.new()
	label.text = st["label"]
	_info_stepper.add_child(label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_info_stepper.add_child(flow)
	var toggled: Callable = st["toggled"]
	for item in st["items"]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = item[1]
		b.button_pressed = item[2]
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 19)
		var key: String = item[0]
		b.toggled.connect(func(on: bool) -> void: toggled.call(key, on))
		flow.add_child(b)


func _build_stepper(st: Dictionary) -> void:
	if st.get("type", "") == "checks":
		_build_checks(st)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_info_stepper.add_child(row)
	var label := Label.new()
	label.text = st["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var options: Array = st.get("options", [])
	var value := Label.new()
	value.custom_minimum_size = Vector2(150 if not options.is_empty() else 56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 22 if not options.is_empty() else 28)
	var minus := Button.new()
	minus.text = "−" if options.is_empty() else "<"
	minus.custom_minimum_size = Vector2(72, 52)
	var plus := Button.new()
	plus.text = "+" if options.is_empty() else ">"
	plus.custom_minimum_size = Vector2(72, 52)
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	var state := {"v": int(st["value"])}
	var refresh := func() -> void:
		value.text = str(options[state["v"]]) if not options.is_empty() else str(state["v"])
		minus.disabled = state["v"] <= int(st["min"])
		plus.disabled = state["v"] >= int(st["max"])
	refresh.call()
	var changed: Callable = st["changed"]
	minus.pressed.connect(func() -> void:
		state["v"] = maxi(int(st["min"]), state["v"] - 1)
		refresh.call()
		changed.call(state["v"]))
	plus.pressed.connect(func() -> void:
		state["v"] = mini(int(st["max"]), state["v"] + 1)
		refresh.call()
		changed.call(state["v"]))


func update_info_text(text: String) -> void:
	_info_label.text = text


func hide_info() -> void:
	_info_panel.visible = false


func info_visible() -> bool:
	return _info_panel.visible


func show_message(title: String, text: String) -> void:
	_dialog_title.text = title
	_dialog_text.text = text
	_dialog.visible = true


func log_event(text: String, kind: String = "info") -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", KIND_COLORS.get(kind, Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_child(l)
	while _log.get_child_count() > LOG_LINES:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(l) and l.get_parent() == _log:
			_log.remove_child(l)
			l.queue_free())
