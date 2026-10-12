class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.
## Сверху — ресурсы значками и дата, снизу — кнопки-значки и карточка выбранного.

signal mode_changed(mode: int)
signal home_pressed
signal speed_pressed
signal save_pressed
signal new_game_confirmed(disasters: bool)

enum Mode { LOOK, TUNNEL, ROOM, HARVEST, BRIDGE }

const MODE_NAMES := ["Осмотр", "Тоннель", "Комната", "Сбор", "Мост"]
const MODE_GLYPHS := ["look", "tunnel", "room", "harvest", "bridge"]
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
const PANEL_WIDTH := 620
## Высота верхней строки и нижнего меню (карточка помещается между ними).
const TOP_H := 70.0
const BAR_H := 102.0
const KIND_COLORS := {
	"info": Color(0.85, 0.88, 0.95),
	"good": Color(0.55, 0.95, 0.55),
	"warning": Color(1.0, 0.8, 0.35),
	"danger": Color(1.0, 0.4, 0.35),
}
const ACCENT := Color(0.98, 0.72, 0.25)
const MUTED := Color(0.7, 0.74, 0.82)
const RED := Color(0.86, 0.26, 0.24)

var _status: Label
var _date: Label
var _res_box: HBoxContainer
var _res_sig := ""
var _build_btn: IconButton
var _build_row: HBoxContainer
var _menu: PanelContainer
var _menu_new: Button
var _new_game: PanelContainer
var _disasters: CheckButton
var _log: VBoxContainer
var _info_panel: PanelContainer
var _title: Label
var _subtitle: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _controls: VBoxContainer
var _actions: HBoxContainer
var _mode_buttons: Array[IconButton] = []
var _btn_speed: IconButton
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
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_build_top(column)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_build_bottom(column)
	# Журнал, карточка и подменю — отдельными слоями, чтобы не сдвигать кнопки.
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	_log.position = Vector2(12, TOP_H)
	_log.size = Vector2(PANEL_WIDTH, 0)
	_build_panel()
	_build_dialog()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.07, 0.08, 0.11, 0.9), 16, 14))
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := _box(Color(0.17, 0.19, 0.25, 0.94), 14, 10)
		match state:
			"hover":
				sb.bg_color = Color(0.22, 0.25, 0.33, 0.96)
			"pressed", "hover_pressed":
				sb.bg_color = ACCENT
			"disabled":
				sb.bg_color = Color(0.14, 0.15, 0.19, 0.8)
			"focus":
				sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	return t


static func _box(col: Color, radius: int, pad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func _label(text: String, fs := 20, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Верх: ресурсы, дата, глубина, журнал -----------------------------------------------

func _build_top(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.1, 0.7), 12, 6))
	row.add_child(panel)
	_res_box = HBoxContainer.new()
	_res_box.add_theme_constant_override("separation", 14)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_res_box)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	_date = _outlined("", 19, Color(1, 1, 1, 0.9))
	_status = _outlined("", 17, Color(1, 1, 1, 0.75))
	var version := _outlined("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 14, Color(1, 1, 1, 0.5))
	for l in [_date, _status, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(l)


static func _outlined(text: String, fs: int, col: Color) -> Label:
	var l := _label(text, fs, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	return l


## Строка ресурсов: жители и запасы значками. Перестраивается только при изменениях.
func set_resources(inventory: Dictionary, people: int, hungry := 0) -> void:
	var keys: Array = ["food", "wood", "stone"]
	var rest := inventory.keys().filter(func(k: String) -> bool:
		return not keys.has(k) and not RoomType.BULK.has(k) and inventory[k] > 0)
	rest.sort()
	keys.append_array(rest)
	var sig := "%d/%d|" % [people, hungry]
	for k in keys:
		sig += "%s=%d," % [k, inventory.get(k, 0)]
	if sig == _res_sig:
		return
	_res_sig = sig
	for c in _res_box.get_children():
		c.queue_free()
	_res_box.add_child(_chip_plain("people", str(people) if hungry == 0 else "%d (голодают %d)" % [people, hungry],
		Color(1.0, 0.55, 0.5) if hungry > 0 else Color.WHITE))
	for k in keys:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(IconView.make(k, 24))
		item.add_child(_label(Fmt.int_spaced(inventory.get(k, 0)), 19, Color(0.97, 0.92, 0.75)))
		_res_box.add_child(item)


func _chip_plain(glyph: String, text: String, col: Color) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 4)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(IconView.make("", 22, glyph, col))
	item.add_child(_label(text, 19, col))
	return item


func set_date(text: String) -> void:
	_date.text = text


## Высотомер (глубина или высота камеры).
func set_status(text: String) -> void:
	_status.text = text


# --- Низ: карточка, подменю стройки, кнопки ------------------------------------------------

func _build_bottom(box: VBoxContainer) -> void:
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 8)
	_build_row.visible = false
	add_child(_build_row)
	_build_row.resized.connect(_place_build_row)
	resized.connect(_place_build_row)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	var group := ButtonGroup.new()
	_mode_buttons.resize(MODE_NAMES.size())
	# Подменю стройки стоит над кнопкой «Стройка».
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(104, 0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_row.add_child(indent)
	for i in MODE_NAMES.size():
		var b := IconButton.make(MODE_GLYPHS[i], MODE_NAMES[i])
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_mode.bind(i))
		_mode_buttons[i] = b
		if BUILD_MODES.has(i):
			_build_row.add_child(b)
	bar.add_child(_mode_buttons[Mode.LOOK])
	_build_btn = IconButton.make("build", "Стройка")
	_build_btn.toggle_mode = true
	_build_btn.toggled.connect(func(on: bool) -> void: _build_row.visible = on)
	bar.add_child(_build_btn)
	bar.add_child(_mode_buttons[Mode.HARVEST])
	_mode_buttons[Mode.LOOK].button_pressed = true
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var home := IconButton.make("home", "К базе")
	_btn_speed = IconButton.make("speed", "×1")
	var menu := IconButton.make("menu", "Меню")
	for b in [home, _btn_speed, menu]:
		bar.add_child(b)
	home.pressed.connect(func() -> void: home_pressed.emit())
	_btn_speed.pressed.connect(func() -> void: speed_pressed.emit())
	menu.pressed.connect(func() -> void:
		_new_game.visible = false
		_menu.visible = not _menu.visible)


func _place_build_row() -> void:
	_build_row.position = Vector2(10, size.y - BAR_H - _build_row.size.y + 2)


func _on_mode(i: int) -> void:
	hide_info()
	var building: bool = BUILD_MODES.has(i)
	_build_btn.set_pressed_no_signal(building)
	_build_btn.glyph = MODE_GLYPHS[i] if building else "build"
	_build_btn.set_caption(MODE_NAMES[i] if building else "Стройка")
	_build_btn.queue_redraw()
	_build_row.visible = false
	if not MODE_HINTS[i].is_empty():
		log_event(MODE_HINTS[i], "info")
	mode_changed.emit(i)


func set_mode(mode: int) -> void:
	_mode_buttons[mode].button_pressed = true


func set_speed_text(text: String) -> void:
	_btn_speed.set_caption(text)


# --- Карточка выбранного ---------------------------------------------------------------

func _build_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_info_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_info_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	_title = _label("", 26, Color.WHITE)
	_subtitle = _label("", 18, ACCENT)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	titles.add_child(_subtitle)
	var close := IconButton.make("close", "", 52, 52)
	close.pressed.connect(hide_info)
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	content.add_child(_body)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 8)
	content.add_child(_controls)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	v.add_child(_actions)


## Карточка: {"title", "subtitle", "rows": [...], "controls": [...], "actions": [[текст, Callable, стиль?]],
## "controls_first": переключатели над описанием}.
## Строки rows: {"type": "progress"|"resources"|"chips"|"text"|"warning"|"section", ...}.
## Управление controls: шаговые переключатели, галочки, нормы запаса (см. _build_control).
func show_panel(spec: Dictionary) -> void:
	_fill_header(spec)
	_fill_body(spec.get("rows", []))
	for c in _controls.get_children():
		c.queue_free()
	for st in spec.get("controls", []):
		_build_control(st)
	_controls.visible = not spec.get("controls", []).is_empty()
	# Переключатели можно поставить над описанием, чтобы не прятались под прокруткой.
	_body.get_parent().move_child(_controls, 0 if spec.get("controls_first", false) else 1)
	for c in _actions.get_children():
		c.queue_free()
	for a in spec.get("actions", []):
		var b := Button.new()
		b.text = a[0]
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var style: String = a[2] if a.size() > 2 else ""
		if style == "danger":
			b.add_theme_stylebox_override("normal", _box(Color(0.45, 0.14, 0.13, 0.95), 14, 10))
		elif style == "primary":
			b.add_theme_stylebox_override("normal", _box(Color(0.75, 0.52, 0.12, 0.95), 14, 10))
		var cb: Callable = a[1]
		b.pressed.connect(cb)
		_actions.add_child(b)
	_actions.visible = not spec.get("actions", []).is_empty()
	_info_panel.visible = true
	_fit_scroll.call_deferred()


## Обновляет заголовок и строки, не трогая кнопки и переключатели.
func refresh_panel(spec: Dictionary) -> void:
	_fill_header(spec)
	_fill_body(spec.get("rows", []))
	_fit_scroll.call_deferred()


func _fit_scroll() -> void:
	var content := _scroll.get_child(0) as Control
	if content == null:
		return
	var h := content.get_combined_minimum_size().y
	# Карточка не выше места между верхней строкой и меню: заголовок, кнопки, отступы — ~160.
	var max_h := get_viewport_rect().size.y - TOP_H - BAR_H - 175.0
	if _actions.visible:
		max_h -= 66.0
	_scroll.custom_minimum_size = Vector2(0, minf(h, maxf(140.0, max_h)))
	# Прижата к нижнему меню и растёт вверх.
	var ph := _info_panel.get_combined_minimum_size().y
	_info_panel.size = Vector2(PANEL_WIDTH, ph)
	_info_panel.position = Vector2(10, size.y - BAR_H - ph)


func _fill_header(spec: Dictionary) -> void:
	_title.text = spec.get("title", "")
	_subtitle.text = spec.get("subtitle", "")
	_subtitle.visible = not _subtitle.text.is_empty()
	_subtitle.add_theme_color_override("font_color", spec.get("accent", ACCENT))


func _fill_body(rows: Array) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for row in rows:
		var node := _row(row)
		if node != null:
			_body.add_child(node)
	_body.visible = _body.get_child_count() > 0


func _row(row: Dictionary) -> Control:
	match row.get("type", "text"):
		"section":
			return _label(row["text"], 16, MUTED)
		"text":
			var l := _label(row["text"], 17, row.get("color", MUTED))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
			return l
		"warning":
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", _box(Color(0.5, 0.2, 0.08, 0.85), 10, 8))
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			p.add_child(h)
			h.add_child(IconView.make("", 24, "warning", ACCENT))
			var l := _label(row["text"], 17, Color(1, 0.92, 0.8))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size = Vector2(PANEL_WIDTH - 90, 0)
			h.add_child(l)
			return p
		"progress":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			var l := _label(row["label"], 18, Color.WHITE)
			l.custom_minimum_size = Vector2(170, 0)
			h.add_child(l)
			h.add_child(BarView.make(row["value"], row.get("color", Color(0.45, 0.85, 0.4)), row.get("text", "")))
			return h
		"resources", "chips":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			if row.has("label"):
				var l := _label(row["label"], 18, Color.WHITE)
				l.custom_minimum_size = Vector2(170, 0)
				h.add_child(l)
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			h.add_child(flow)
			for item in row["items"]:
				flow.add_child(_chip(item, row["type"] == "resources"))
			return h
	return null


## Плашка: ресурс [ключ, есть, нужно (-1 — без «из»), хватает] или текст [значок, текст, цвет?].
func _chip(item: Array, resource: bool) -> Control:
	var p := PanelContainer.new()
	var ok := true
	if resource:
		ok = item.size() < 4 or item[3]
	p.add_theme_stylebox_override("panel", _box(Color(0.62, 0.16, 0.14, 0.9) if not ok else Color(1, 1, 1, 0.08), 10, 5))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	if resource:
		h.add_child(IconView.make(item[0], 24))
		var text := Fmt.int_spaced(item[1]) if item[2] < 0 else "%s/%s" % [Fmt.int_spaced(item[1]), Fmt.int_spaced(item[2])]
		h.add_child(_label(text, 18, Color.WHITE))
	else:
		var col: Color = item[2] if item.size() > 2 else Color.WHITE
		if not str(item[0]).is_empty():
			h.add_child(IconView.make("", 20, item[0], col))
		h.add_child(_label(item[1], 17, col))
	return p


## Переключатели:
##  {"label", "value", "min", "max", "changed": Callable(int), "options"?: Array, "step"?: int}
##  {"type": "checks", "label", "items": [[ключ, подпись, вкл]], "toggled": Callable(ключ, вкл)}
##  {"type": "targets", "label", "items": [[ключ, есть, норма, максимум, добывают]], "changed": Callable(ключ, норма)}
func _build_control(st: Dictionary) -> void:
	match st.get("type", ""):
		"checks":
			_build_checks(st)
		"targets":
			_build_targets(st)
		_:
			_build_stepper(st)


func _build_checks(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_controls.add_child(flow)
	var toggled: Callable = st["toggled"]
	for item in st["items"]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = item[1]
		b.button_pressed = item[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 18)
		var key: String = item[0]
		b.toggled.connect(func(on: bool) -> void: toggled.call(key, on))
		flow.add_child(b)


func _build_targets(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	var changed: Callable = st["changed"]
	for item in st["items"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_controls.add_child(row)
		row.add_child(IconView.make(item[0], 30))
		var name := _label("%s · есть %s" % [Mat.resource_name(item[0]), Fmt.int_spaced(item[1])], 18, Color.WHITE)
		if not item[4]:
			name.text += " (только копкой)"
			name.add_theme_color_override("font_color", MUTED)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var key: String = item[0]
		_stepper_widgets(row, int(item[2]), 0, int(item[3]), 10, [], func(v: int) -> void: changed.call(key, v))


func _build_stepper(st: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_controls.add_child(row)
	var label := _label(st["label"], 19, Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_stepper_widgets(row, int(st["value"]), int(st["min"]), int(st["max"]), int(st.get("step", 1)),
		st.get("options", []), st["changed"])


func _stepper_widgets(row: HBoxContainer, start: int, lo: int, hi: int, step: int, options: Array, changed: Callable) -> void:
	var value := _label("", 22 if not options.is_empty() else 26, Color.WHITE)
	value.custom_minimum_size = Vector2(160 if not options.is_empty() else 64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var minus := Button.new()
	minus.text = "−" if options.is_empty() else "<"
	minus.custom_minimum_size = Vector2(64, 50)
	minus.focus_mode = Control.FOCUS_NONE
	var plus := Button.new()
	plus.text = "+" if options.is_empty() else ">"
	plus.custom_minimum_size = Vector2(64, 50)
	plus.focus_mode = Control.FOCUS_NONE
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	var state := {"v": start}
	var refresh := func() -> void:
		value.text = str(options[state["v"]]) if not options.is_empty() else str(state["v"])
		minus.disabled = state["v"] <= lo
		plus.disabled = state["v"] >= hi
	refresh.call()
	minus.pressed.connect(func() -> void:
		state["v"] = maxi(lo, state["v"] - step)
		refresh.call()
		changed.call(state["v"]))
	plus.pressed.connect(func() -> void:
		state["v"] = mini(hi, state["v"] + step)
		refresh.call()
		changed.call(state["v"]))


## Простая карточка из текста (первая строка — заголовок).
func show_info(text: String, actions: Array = [], controls: Array = []) -> void:
	var lines := text.split("\n")
	var rows := []
	if lines.size() > 1:
		rows.append({"type": "text", "text": "\n".join(lines.slice(1))})
	show_panel({"title": lines[0], "rows": rows, "actions": actions, "controls": controls})


func hide_info() -> void:
	_info_panel.visible = false


func info_visible() -> bool:
	return _info_panel.visible


# --- Окна: сообщение и меню ---------------------------------------------------------------

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
	_dialog_title = _label("", 28, Color.WHITE)
	_dialog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_dialog_title)
	_dialog_text = _label("", 20, Color(0.9, 0.92, 0.96))
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(520, 0)
	v.add_child(_dialog_text)
	var ok := _menu_button(v, "Отлично")
	ok.pressed.connect(func() -> void: _dialog.visible = false)
	_build_menu(center)


func _build_menu(center: CenterContainer) -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.custom_minimum_size = Vector2(420, 0)
	center.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_menu.add_child(v)
	var title := _label("Меню", 28, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := _menu_button(v, "Продолжить")
	resume.pressed.connect(func() -> void: _menu.visible = false)
	var save := _menu_button(v, "Сохранить игру")
	save.pressed.connect(func() -> void:
		save_pressed.emit()
		_menu.visible = false)
	_menu_new = _menu_button(v, "Новая игра")
	_menu_new.pressed.connect(func() -> void:
		_menu.visible = false
		_new_game.visible = true)
	_build_new_game(center)


## Окно новой игры: настройки и подтверждение (текущий прогресс пропадёт).
func _build_new_game(center: CenterContainer) -> void:
	_new_game = PanelContainer.new()
	_new_game.visible = false
	_new_game.custom_minimum_size = Vector2(560, 0)
	center.add_child(_new_game)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_new_game.add_child(v)
	var title := _label("Новая игра", 28, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_disasters = CheckButton.new()
	_disasters.text = "Стихийные бедствия"
	_disasters.button_pressed = true
	_disasters.focus_mode = Control.FOCUS_NONE
	_disasters.add_theme_font_size_override("font_size", 22)
	v.add_child(_disasters)
	var hint := _label("Очень редкие бури (раз в 4–10 часов игры) и землетрясения (раз в 12–30 часов), с предупреждением и только пока вы в игре.", 17, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	v.add_child(hint)
	var warn := _label("Текущая колония будет удалена.", 18, Color(1.0, 0.6, 0.5))
	v.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var start := _menu_button(row, "Начать")
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.add_theme_stylebox_override("normal", _box(Color(0.75, 0.52, 0.12, 0.95), 14, 10))
	var cancel := _menu_button(row, "Отмена")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func() -> void:
		_new_game.visible = false
		new_game_confirmed.emit(_disasters.button_pressed))
	cancel.pressed.connect(func() -> void: _new_game.visible = false)


func _menu_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func show_message(title: String, text: String) -> void:
	_dialog_title.text = title
	_dialog_text.text = text
	_dialog.visible = true


func log_event(text: String, kind: String = "info") -> void:
	var l := _outlined(text, 19, KIND_COLORS.get(kind, Color.WHITE))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 6)
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
