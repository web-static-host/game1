class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.

signal mode_changed(dig_mode: bool)
signal home_pressed
signal speed_pressed

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
var _log: VBoxContainer
var _cell_panel: PanelContainer
var _cell_label: Label
var _btn_look: Button
var _btn_dig: Button
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


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.1, 0.78)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(10)
		match state:
			"normal", "disabled":
				sb.bg_color = Color(0.16, 0.18, 0.24, 0.92)
			"hover":
				sb.bg_color = Color(0.22, 0.25, 0.33, 0.95)
			"pressed":
				sb.bg_color = Color(0.85, 0.62, 0.18, 0.95)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	return t


func _build_top(column: VBoxContainer) -> void:
	# Горизонтальный экран: информация — колонкой слева, мир остаётся виден.
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	column.add_child(box)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(panel)
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	_status = Label.new()
	inner.add_child(_status)
	_resources = Label.new()
	_resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resources.add_theme_font_size_override("font_size", 19)
	_resources.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	inner.add_child(_resources)

	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_log)


func _build_bottom(box: VBoxContainer) -> void:

	_cell_panel = PanelContainer.new()
	_cell_panel.visible = false
	_cell_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cell_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	box.add_child(_cell_panel)
	_cell_label = Label.new()
	_cell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cell_label.add_theme_font_size_override("font_size", 20)
	_cell_panel.add_child(_cell_label)
	_cell_panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and e.pressed or e is InputEventMouseButton and e.pressed:
			_cell_panel.visible = false)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	bar.custom_minimum_size = Vector2(760, 0)
	box.add_child(bar)
	_btn_look = _button(bar, "Осмотр")
	_btn_dig = _button(bar, "Копать")
	var home := _button(bar, "К базе")
	_btn_speed = _button(bar, "×1")
	_btn_look.toggle_mode = true
	_btn_dig.toggle_mode = true
	_btn_look.button_pressed = true
	var group := ButtonGroup.new()
	_btn_look.button_group = group
	_btn_dig.button_group = group
	_btn_look.pressed.connect(func() -> void: mode_changed.emit(false))
	_btn_dig.pressed.connect(func() -> void:
		_cell_panel.visible = false
		mode_changed.emit(true))
	home.pressed.connect(func() -> void: home_pressed.emit())
	_btn_speed.pressed.connect(func() -> void: speed_pressed.emit())


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


func set_dig_mode(on: bool) -> void:
	_btn_dig.button_pressed = on
	_btn_look.button_pressed = not on


func set_speed_text(text: String) -> void:
	_btn_speed.text = text


func set_status(text: String) -> void:
	_status.text = text


func set_resources(inventory: Dictionary) -> void:
	if inventory.is_empty():
		_resources.text = "Склад пуст"
		return
	var parts: PackedStringArray = []
	var keys := inventory.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %s" % [Mat.resource_name(k), Fmt.int_spaced(inventory[k])])
	_resources.text = " · ".join(parts)


func show_cell(text: String) -> void:
	_cell_label.text = text
	_cell_panel.visible = true


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
