class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.
## Сверху — ресурсы значками и дата, снизу — кнопки-значки и карточка выбранного.

## Выбран инструмент: режим и ширина комнаты (для комнат).
signal mode_changed(mode: int, room_width: int)
## Во время установки комнаты поменяли размер или материал.
signal room_options_changed(width: int, material: String)
signal home_pressed
## Выбрана скорость игры: номер кнопки (×1, ×10, ×20).
signal speed_selected(index: int)
signal science_pressed
signal people_pressed
signal save_pressed
signal new_game_confirmed(disasters: bool)
signal models_toggled(on: bool)
signal background_toggled(on: bool)

## LOOK — обычный режим: нажатие показывает то, что под пальцем, и действия с ним.
## Остальные — разовые: после «Построить», «Отмены» или выбора точки возвращаемся в LOOK.
enum Mode { LOOK, TUNNEL, ROOM, BRIDGE, SEND }

## Инструменты «Стройки»: [режим, значок, подпись].
const TOOLS := [
	[Mode.TUNNEL, "tunnel", "Тоннель"],
	[Mode.ROOM, "room", "Комната"],
	[Mode.BRIDGE, "bridge", "Мост"],
]
const TOOL_HINTS := {
	Mode.TUNNEL: "Проведите пальцем рамку тоннеля. Карта — двумя пальцами",
	Mode.ROOM: "Выберите размер и материал, коснитесь карты. Карта — двумя пальцами",
	Mode.BRIDGE: "Проведите пальцем над озером",
}
const ROOM_SIZES := [[3, "Малая 3×3"], [6, "Средняя 6×3"], [9, "Большая 9×3"]]
const SPEED_NAMES := ["×1", "×2", "×10", "×20"]
## Отступы от краёв экрана (скруглённые углы, вырезы камеры).
const SIDE := 34.0
const EDGE_TOP := 14.0
const EDGE_BOTTOM := 12.0
const LOG_LINES := 4
const PANEL_WIDTH := 620
## Высота верхней строки и нижнего меню (карточка помещается между ними).
const TOP_H := 86.0
const BAR_H := 102.0
const KIND_COLORS := {
	"info": Color(0.85, 0.88, 0.95),
	"good": Color(0.55, 0.95, 0.55),
	"warning": Color(1.0, 0.8, 0.35),
	"danger": Color(1.0, 0.4, 0.35),
}
const ACCENT := Color(0.96, 0.65, 0.16)
const MUTED := Color(0.78, 0.72, 0.68)
const RED := Color(0.89, 0.36, 0.29)
## Оформление: тёплые тёмные панели, кнопки с «бортиком» снизу (тон того же цвета).
const PANEL_BG := Color(0.17, 0.13, 0.16, 0.93)
const TOP_BG := Color(0.17, 0.13, 0.16, 0.8)
const BTN := Color(0.36, 0.41, 0.52)
const GREEN := Color(0.3, 0.72, 0.38)

var _status: Label
var _date: Label
var _weather: TextureRect
var _weather_name := ""
var _res_box: HBoxContainer
var _res_sig := ""
var _build_btn: IconButton
var _build_row: HBoxContainer
var _menu: PanelContainer
var _menu_new: Button
var _models_hint: Label
var _background: CheckButton
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
var _hint: Label
var _hint_cancel: Button
## Полоска выбора комнаты: размеры и материалы.
var _room_strip: HBoxContainer
var _room_w := 6
var _room_mat := "wood"
var _room_mats: Array = ["wood"]

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
	margin.add_theme_constant_override("margin_left", int(SIDE))
	margin.add_theme_constant_override("margin_right", int(SIDE))
	margin.add_theme_constant_override("margin_top", int(EDGE_TOP))
	margin.add_theme_constant_override("margin_bottom", int(EDGE_BOTTOM))
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
	_log.position = Vector2(SIDE, TOP_H)
	_log.size = Vector2(PANEL_WIDTH, 0)
	_build_hint()
	_build_panel()
	_build_dialog()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.bold()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, 18, 14))
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := btn_box(BTN)
		match state:
			"hover":
				sb = btn_box(BTN.lightened(0.1))
			"pressed", "hover_pressed":
				sb = btn_box(ACCENT, true)
			"disabled":
				sb = btn_box(Color(BTN.darkened(0.3), 0.8))
			"focus":
				sb.draw_center = false
				sb.set_border_width_all(0)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))
	return t


static func _box(col: Color, radius: int, pad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


## Кнопка: заливка, снизу — бортик темнее (объём), края тоном того же цвета.
## pressed — бортик тоньше, будто кнопку вдавили.
static func btn_box(col: Color, pressed := false) -> StyleBoxFlat:
	var sb := _box(col, 16, 10)
	sb.border_color = col.darkened(0.32)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 3 if pressed else 6
	sb.content_margin_bottom = 12
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
	panel.add_theme_stylebox_override("panel", _box(TOP_BG, 16, 10))
	row.add_child(panel)
	_res_box = HBoxContainer.new()
	_res_box.add_theme_constant_override("separation", 14)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_res_box)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	var date_panel := PanelContainer.new()
	date_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_panel.add_theme_stylebox_override("panel", _box(TOP_BG, 16, 10))
	date_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(date_panel)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 0)
	date_panel.add_child(right)
	_date = _label("", 19, Color.WHITE)
	_date.add_theme_font_override("font", Fonts.black())
	_status = _label("", 16, MUTED)
	var version := _label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 13, Color(1, 1, 1, 0.4))
	# Строка даты: значок погоды слева от текста.
	var date_row := HBoxContainer.new()
	date_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_row.alignment = BoxContainer.ALIGNMENT_END
	date_row.add_theme_constant_override("separation", 6)
	_weather = TextureRect.new()
	_weather.custom_minimum_size = Vector2(28, 28)
	_weather.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weather.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weather.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather.visible = false
	date_row.add_child(_weather)
	date_row.add_child(_date)
	right.add_child(date_row)
	for l in [_date, _status, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if l != _date:
			right.add_child(l)


static func _outlined(text: String, fs: int, col: Color) -> Label:
	var l := _label(text, fs, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	return l


## Строка ресурсов: жители и запасы значками. Перестраивается только при изменениях.
func set_resources(inventory: Dictionary, people: int, hungry := 0, power_made := 0, power_used := 0, power_known := false) -> void:
	var keys: Array = ["food", "berries", "wood", "stone"]
	var rest := inventory.keys().filter(func(k: String) -> bool:
		return not keys.has(k) and not RoomType.BULK.has(k) and inventory[k] > 0)
	rest.sort()
	keys.append_array(rest)
	var sig := "%d/%d/%d/%d|" % [people, hungry, power_made, power_used]
	for k in keys:
		sig += "%s=%d," % [k, inventory.get(k, 0)]
	if sig == _res_sig:
		return
	_res_sig = sig
	for c in _res_box.get_children():
		c.queue_free()
	_res_box.add_child(_chip_plain("people", str(people) if hungry == 0 else "%d (голодают %d)" % [people, hungry],
		Color(1.0, 0.55, 0.5) if hungry > 0 else Color.WHITE))
	if power_known and (power_made > 0 or power_used > 0):
		_res_box.add_child(_chip_plain("power", "%d/%d" % [power_made, power_used],
			Color(1.0, 0.85, 0.3) if power_made >= power_used else Color(1.0, 0.55, 0.5)))
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
	# Житель и молния — картинками, если они есть; иначе значок кодом в цвет текста.
	item.add_child(IconView.make(glyph, 24) if ResIcon.texture(glyph) != null else IconView.make("", 22, glyph, col))
	item.add_child(_label(text, 19, col))
	return item


## Дата и значок погоды (имя картинки assets/icons/weather_<weather>.png).
func set_date(text: String, weather := "") -> void:
	_date.text = text
	if weather != _weather_name:
		_weather_name = weather
		_weather.texture = ResIcon.texture("weather_" + weather) if not weather.is_empty() else null
		_weather.visible = _weather.texture != null


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
	# Подменю «Стройки»: инструменты; после выбора — разовый режим установки.
	for t in TOOLS:
		var b := IconButton.make(t[1], t[2], 108, 80)
		b.pressed.connect(func() -> void: _pick_tool(t[0], t[1], t[2]))
		_build_row.add_child(b)
	_build_btn = IconButton.make("build", "Стройка")
	_build_btn.toggle_mode = true
	# Главная кнопка — оранжевая.
	_build_btn.add_theme_stylebox_override("normal", btn_box(ACCENT))
	_build_btn.add_theme_stylebox_override("hover", btn_box(ACCENT.lightened(0.08)))
	_build_btn.add_theme_stylebox_override("pressed", btn_box(ACCENT.darkened(0.18), true))
	_build_btn.toggled.connect(_on_build_toggled)
	bar.add_child(_build_btn)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var people := IconButton.make("people", "Жители")
	people.pressed.connect(func() -> void: people_pressed.emit())
	bar.add_child(people)
	var science := IconButton.make("flask", "Наука")
	science.pressed.connect(func() -> void: science_pressed.emit())
	bar.add_child(science)
	var home := IconButton.make("home", "К базе")
	bar.add_child(home)
	# Скорость — переключатель в одной панели.
	var seg := PanelContainer.new()
	seg.add_theme_stylebox_override("panel", _box(TOP_BG, 18, 6))
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(seg)
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 4)
	seg.add_child(seg_row)
	var speeds := ButtonGroup.new()
	var flat := _box(Color(0, 0, 0, 0), 14, 6)
	for i in SPEED_NAMES.size():
		var b := Button.new()
		b.text = SPEED_NAMES[i]
		b.custom_minimum_size = Vector2(64, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = speeds
		b.button_pressed = i == 0
		b.add_theme_font_override("font", Fonts.black())
		b.add_theme_font_size_override("font_size", 22)
		for st in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(st, flat)
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, btn_box(ACCENT, true))
		b.pressed.connect(func() -> void: speed_selected.emit(i))
		seg_row.add_child(b)
	var menu := IconButton.make("menu", "Меню")
	bar.add_child(menu)
	home.pressed.connect(func() -> void: home_pressed.emit())
	menu.pressed.connect(func() -> void:
		var open := not _menu.visible
		close_overlays()
		_models_hint.text = "Треугольные одноглазые без мутаций — из 3D-модели, остальные рисованные. Модель: %s." % ModelSprites.status
		_menu.visible = open)


func _place_build_row() -> void:
	_build_row.position = Vector2(SIDE, size.y - BAR_H - _build_row.size.y + 2)


var _placing := false


## «Стройка»: открыть инструменты; во время установки — отменить её.
func _on_build_toggled(on: bool) -> void:
	if _placing:
		set_mode(Mode.LOOK)
		mode_changed.emit(Mode.LOOK, 0)
		return
	if on:
		close_overlays()
	_build_row.visible = on


## Открыто только одно окно: карточка, меню, подменю стройки или новая игра.
func close_overlays() -> void:
	hide_info()
	_menu.visible = false
	_new_game.visible = false
	if not _placing:
		_build_row.visible = false
		_build_btn.set_pressed_no_signal(false)


func _pick_tool(mode: int, glyph: String, caption: String) -> void:
	hide_info()
	_build_row.visible = false
	_placing = true
	_build_btn.set_pressed_no_signal(true)
	_build_btn.glyph = glyph
	_build_btn.set_caption(caption)
	set_hint(TOOL_HINTS.get(mode, ""))
	_show_room_strip(mode == Mode.ROOM)
	mode_changed.emit(mode, _room_w if mode == Mode.ROOM else 0)


## Материалы стен, доступные колонии (для полоски выбора комнаты).
func set_room_materials(mats: Array) -> void:
	_room_mats = mats
	if not _room_mats.has(_room_mat):
		_room_mat = "wood"


func room_material() -> String:
	return _room_mat


## Полоска под подсказкой: размер комнаты и материал стен — выбираются до установки.
func _show_room_strip(on: bool) -> void:
	for c in _room_strip.get_children():
		_room_strip.remove_child(c)
		c.queue_free()
	_room_strip.visible = on
	if not on:
		return
	var sizes := ButtonGroup.new()
	for s in ROOM_SIZES:
		var b := IconButton.make("room", s[1], 120, 72)
		b.toggle_mode = true
		b.button_group = sizes
		b.button_pressed = s[0] == _room_w
		b.pressed.connect(func() -> void:
			_room_w = s[0]
			room_options_changed.emit(_room_w, _room_mat))
		_room_strip.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	_room_strip.add_child(gap)
	var mats := ButtonGroup.new()
	for m in _room_mats:
		var b := IconButton.make("", Project.MATERIALS[m][0], 96, 72)
		b.res_key = m
		b.toggle_mode = true
		b.button_group = mats
		b.button_pressed = m == _room_mat
		b.pressed.connect(func() -> void:
			_room_mat = m
			room_options_changed.emit(_room_w, _room_mat))
		_room_strip.add_child(b)
	_place_hint.call_deferred()


## Вернуть нижнее меню в обычный вид (после стройки или отмены).
func set_mode(mode: int) -> void:
	if mode != Mode.LOOK:
		return
	_placing = false
	_build_row.visible = false
	_build_btn.set_pressed_no_signal(false)
	_build_btn.glyph = "build"
	_build_btn.set_caption("Стройка")
	set_hint("")
	_show_room_strip(false)


## Подсказка сверху по центру — что сейчас делать (с кнопкой «Отмена»).
func _build_hint() -> void:
	var box := HBoxContainer.new()
	box.name = "Hint"
	box.add_theme_constant_override("separation", 10)
	box.visible = false
	add_child(box)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 16, 10))
	box.add_child(panel)
	_hint = _label("", 19, Color.WHITE)
	panel.add_child(_hint)
	_hint_cancel = Button.new()
	_hint_cancel.text = "Отмена"
	_hint_cancel.focus_mode = Control.FOCUS_NONE
	_hint_cancel.custom_minimum_size = Vector2(120, 48)
	_hint_cancel.pressed.connect(func() -> void:
		set_mode(Mode.LOOK)
		mode_changed.emit(Mode.LOOK, 0))
	box.add_child(_hint_cancel)
	_room_strip = HBoxContainer.new()
	_room_strip.add_theme_constant_override("separation", 6)
	_room_strip.visible = false
	add_child(_room_strip)


func set_hint(text: String) -> void:
	var box := _hint.get_parent().get_parent() as Control
	_hint.text = text
	box.visible = not text.is_empty()
	_place_hint()


func _place_hint() -> void:
	var box := _hint.get_parent().get_parent() as Control
	box.reset_size()
	box.position = Vector2((size.x - box.size.x) * 0.5, TOP_H + 18)
	_room_strip.reset_size()
	_room_strip.position = Vector2((size.x - _room_strip.size.x) * 0.5, box.position.y + box.size.y + 8)


## Сколько места сверху занято подсказкой и полоской выбора.
func _top_limit() -> float:
	var top := TOP_H
	var box := _hint.get_parent().get_parent() as Control
	if box.visible:
		top = box.position.y + box.size.y + 8.0
	if _room_strip.visible:
		top = _room_strip.position.y + _room_strip.size.y + 8.0
	return top





# --- Карточка выбранного ---------------------------------------------------------------

func _build_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_info_panel)
	# Лента событий в том же углу — пока открыта карточка, прячем её.
	_info_panel.visibility_changed.connect(func() -> void:
		if _log != null:
			_log.visible = not _info_panel.visible)
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
	_title.add_theme_font_override("font", Fonts.black())
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
## Строки rows: {"type": "progress"|"resources"|"chips"|"text"|"warning"|"section"|"portrait"|"stats", ...}.
## Управление controls: шаговые переключатели, галочки, нормы запаса (см. _build_control).
func show_panel(spec: Dictionary) -> void:
	_menu.visible = false
	_new_game.visible = false
	if not _placing:
		_build_row.visible = false
		_build_btn.set_pressed_no_signal(false)
	_fill_header(spec)
	_fill_body(spec.get("rows", []))
	# Старое убираем сразу, а не в конце кадра — иначе карточка меряет себя вместе с ним.
	for c in _controls.get_children():
		_controls.remove_child(c)
		c.queue_free()
	for st in spec.get("controls", []):
		_build_control(st)
	_controls.visible = not spec.get("controls", []).is_empty()
	# Переключатели можно поставить над описанием, чтобы не прятались под прокруткой.
	_body.get_parent().move_child(_controls, 0 if spec.get("controls_first", false) else 1)
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for a in spec.get("actions", []):
		var b := Button.new()
		b.text = a[0]
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var style: String = a[2] if a.size() > 2 else ""
		if style == "danger":
			b.add_theme_stylebox_override("normal", btn_box(RED))
		elif style == "primary":
			b.add_theme_stylebox_override("normal", btn_box(ACCENT))
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
	# Сколько занимает карточка без прокручиваемой части (заголовок, кнопки, отступы).
	_scroll.custom_minimum_size = Vector2.ZERO
	var overhead := _info_panel.get_combined_minimum_size().y
	# Карточка помещается между верхом (строка ресурсов, подсказка) и нижним меню.
	var avail := size.y - BAR_H - _top_limit() - 4.0
	_scroll.custom_minimum_size = Vector2(0, clampf(h, 0.0, maxf(100.0, avail - overhead)))
	var ph := _info_panel.get_combined_minimum_size().y
	_info_panel.size = Vector2(PANEL_WIDTH, ph)
	_info_panel.position = Vector2(SIDE, size.y - BAR_H - ph)


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
		"portrait":
			# Портрет жителя и плашки рядом (пол, характер, мутации).
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			h.add_child(PortraitView.make(row["looks"], 150, 74))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 6)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(col)
			for tag in row.get("tags", []):
				var l := _label(tag[0], 17, tag[1] if tag.size() > 1 else Color.WHITE)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(PANEL_WIDTH - 220, 0)
				col.add_child(l)
			return h
		"stats":
			# Характеристики двумя столбцами: подпись и полоска (100% — середина).
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 4)
			for item in row["items"]:
				var cell := HBoxContainer.new()
				cell.add_theme_constant_override("separation", 6)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var l := _label(item[0], 15, MUTED)
				l.custom_minimum_size = Vector2(118, 0)
				cell.add_child(l)
				var v: float = item[1]
				var good: bool = item[2]
				var c := Color(0.45, 0.8, 0.4) if good else Color(0.92, 0.45, 0.3)
				if absf(v - 1.0) < 0.01:
					c = Color(0.55, 0.6, 0.7)
				var bar := BarView.make(v / 2.0, c, "%d%%" % roundi(v * 100.0))
				bar.custom_minimum_size = Vector2(130, 22)
				cell.add_child(bar)
				grid.add_child(cell)
			return grid
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
		"techs":
			_build_techs(st)
		"people":
			_build_people(st)
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


## Список жителей с кнопкой: {"type": "people", "label", "empty"?, "items": [{"looks", "name", "info",
## "button"?, "pick": Callable, "style"?}]} — назначить на работу и т. п.
func _build_people(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	if st["items"].is_empty() and st.has("empty"):
		_controls.add_child(_label(st["empty"], 16, MUTED))
	for item in st["items"]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.06), 10, 6))
		_controls.add_child(p)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		p.add_child(row)
		if item.has("looks"):
			row.add_child(PortraitView.make(item["looks"], 56, 28))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		col.add_child(_label(item["name"], 19, Color.WHITE))
		var info := _label(item.get("info", ""), 15, MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(PANEL_WIDTH - 300, 0)
		col.add_child(info)
		if not item.has("button"):
			continue
		var b := Button.new()
		b.text = item["button"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 50)
		b.add_theme_font_size_override("font_size", 18)
		if item.get("style", "") == "danger":
			b.add_theme_stylebox_override("normal", btn_box(RED))
		b.pressed.connect(item["pick"])
		row.add_child(b)


## Дерево технологий: название, что даёт, цена и кнопка «Изучать».
func _build_techs(st: Dictionary) -> void:
	for item in st["items"]:
		var p := PanelContainer.new()
		var bg := Color(1, 1, 1, 0.06)
		match item["state"]:
			"done":
				bg = Color(0.2, 0.45, 0.25, 0.6)
			"current":
				bg = Color(0.2, 0.35, 0.6, 0.7)
		p.add_theme_stylebox_override("panel", _box(bg, 10, 8))
		_controls.add_child(p)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		p.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var title := _label("%s · %d очков" % [item["name"], item["cost"]], 19,
			Color.WHITE if item["state"] != "locked" else MUTED)
		col.add_child(title)
		var desc := _label(item["desc"], 16, MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PANEL_WIDTH - 220, 0)
		col.add_child(desc)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 50)
		b.add_theme_font_size_override("font_size", 18)
		match item["state"]:
			"done":
				b.text = "Изучено"
				b.disabled = true
			"current":
				b.text = "Изучается"
				b.disabled = true
			"available":
				b.text = "Изучать"
				b.pressed.connect(item["pick"])
			_:
				b.text = "Недоступно"
				b.disabled = true
		row.add_child(b)


func _build_targets(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	var changed: Callable = st["changed"]
	for item in st["items"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_controls.add_child(row)
		row.add_child(IconView.make(item[0], 30))
		var name := _label("%s · %s из %s" % [Mat.resource_name(item[0]), Fmt.int_spaced(item[1]), Fmt.int_spaced(item[3])], 18, Color.WHITE)
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
	_dialog_title.add_theme_font_override("font", Fonts.black())
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
	_background = CheckButton.new()
	_background.text = "Игра в фоне"
	_background.focus_mode = Control.FOCUS_NONE
	_background.add_theme_font_size_override("font_size", 22)
	_background.toggled.connect(func(on: bool) -> void: background_toggled.emit(on))
	v.add_child(_background)
	var bg_hint := _label("Включено — пока вас нет, жители работают (до 3 часов). Выключено — игра на паузе, пока вы не вернётесь.", 16, MUTED)
	bg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg_hint.custom_minimum_size = Vector2(380, 0)
	v.add_child(bg_hint)
	var models := CheckButton.new()
	models.text = "3D-модель жителей"
	models.button_pressed = ModelSprites.enabled
	models.focus_mode = Control.FOCUS_NONE
	models.add_theme_font_size_override("font_size", 22)
	models.toggled.connect(func(on: bool) -> void: models_toggled.emit(on))
	v.add_child(models)
	_models_hint = _label("", 16, MUTED)
	_models_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_models_hint.custom_minimum_size = Vector2(380, 0)
	v.add_child(_models_hint)
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
	start.add_theme_stylebox_override("normal", btn_box(ACCENT))
	var cancel := _menu_button(row, "Отмена")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func() -> void:
		_new_game.visible = false
		new_game_confirmed.emit(_disasters.button_pressed))
	cancel.pressed.connect(func() -> void: _new_game.visible = false)


## Положение переключателя «Игра в фоне» (из настроек).
func set_background(on: bool) -> void:
	_background.set_pressed_no_signal(on)


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
	# Строка журнала на полупрозрачной подложке — читается и на небе, и на земле.
	var l := PanelContainer.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := _box(Color(TOP_BG, 0.62), 10, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	l.add_theme_stylebox_override("panel", sb)
	var t := _label(text, 18, KIND_COLORS.get(kind, Color.WHITE))
	if Fonts.bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > PANEL_WIDTH - 24:
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(PANEL_WIDTH - 24, 0)
	l.add_child(t)
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
