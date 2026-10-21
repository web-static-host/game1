class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.
## Сверху — ресурсы значками и дата, снизу — кнопки-значки и карточка выбранного.

## Выбран инструмент: режим и ширина комнаты (для комнат).
signal mode_changed(mode: int, room_width: int)
## Во время установки комнаты поменяли размер или материал.
signal room_options_changed(width: int, material: String)
signal home_pressed
## «Миры»: Земля, колонии на планетах, ракеты в полёте.
signal worlds_pressed
## Нажали на бургер в строке ресурсов — показать, сколько какой еды.
signal food_pressed
## Открыли меню стройки — main присылает плитки комнат (set_build_rooms).
signal build_opened
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
enum Mode { LOOK, TUNNEL, ROOM, BRIDGE, SEND, MINE, LIFT, CARGO_LIFT, DRILL }

## Инструменты «Стройки»: [режим, значок, подпись].
const TOOLS := [
	[Mode.TUNNEL, "tunnel", "Тоннель"],
	[Mode.MINE, "mine", "Шахта"],
	[Mode.BRIDGE, "bridge", "Мост"],
	[Mode.LIFT, "lift", "Лифт"],
	[Mode.CARGO_LIFT, "cargo_lift", "Грузовой лифт"],
	[Mode.DRILL, "drill", "Бур"],
]
## Плиток комнат в ряду меню стройки.
const ROOM_COLS := 10
const TOOL_HINTS := {
	Mode.TUNNEL: "Проведите пальцем рамку тоннеля. Карта — двумя пальцами",
	Mode.MINE: "Проведите пальцем вдоль шахты (всегда 3 м высотой). Карта — двумя пальцами",
	Mode.ROOM: "Выберите размер и материал, коснитесь карты. Карта — двумя пальцами",
	Mode.BRIDGE: "Проведите пальцем над озером",
	Mode.LIFT: "Проведите строго вверх-вниз (шахта 2 м) или вбок (ход 3 м). Можно по готовому тоннелю",
	Mode.CARGO_LIFT: "Проведите строго вверх-вниз (шахта 3 м) или вбок. Поставьте склад вплотную к концам",
	Mode.DRILL: "Коснитесь, где поставить бур (машина 3×3). Куда и сколько сверлить — в его карточке",
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
var _build_row: PanelContainer
var _room_grid: GridContainer
## Инструменты стройки: режим -> кнопка; почему недоступен (пусто — доступен).
var _tool_btns := {}
var _tool_lock := {}
## Под что строится комната из меню (0 — пустая, назначение потом).
var _room_purpose := 0
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
	_build_tree_panel()
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


var _worlds_btn: Control


## «Миры» — только когда есть куда лететь (изучено ракетостроение) или уже летали.
func set_worlds_visible(on: bool) -> void:
	if _worlds_btn != null and _worlds_btn.visible != on:
		_worlds_btn.visible = on


## Строка ресурсов: жители и запасы значками. Перестраивается только при изменениях.
func set_resources(inventory: Dictionary, people: int, hungry := 0, power_made := 0, power_used := 0, power_known := false) -> void:
	# Еда — одним бургером (сумма грибов, рыбы и ягод), остальное — по ресурсам.
	var keys: Array = ["wood", "stone"]
	var rest := inventory.keys().filter(func(k: String) -> bool:
		return not keys.has(k) and not RoomType.BULK.has(k) and not RoomType.FOOD_KEYS.has(k) and inventory[k] > 0)
	var food := 0
	for k in RoomType.FOOD_KEYS:
		food += int(inventory.get(k, 0))
	rest.sort()
	keys.append_array(rest)
	var sig := "%d/%d/%d/%d/%d|" % [people, hungry, power_made, power_used, food]
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
	# Бургер нажимается: всплывает, сколько грибов, рыбы и ягод.
	var meal := HBoxContainer.new()
	meal.add_theme_constant_override("separation", 4)
	meal.mouse_filter = Control.MOUSE_FILTER_STOP
	meal.add_child(IconView.make("meal", 24))
	meal.add_child(_label(Fmt.int_spaced(food), 19, Color(0.97, 0.92, 0.75)))
	meal.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			food_pressed.emit())
	_res_box.add_child(meal)
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
	# Меню «Стройки»: проходы сверху, ниже — все виды комнат (недоступные — серые).
	_build_row = PanelContainer.new()
	_build_row.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.94), 16, 12))
	_build_row.visible = false
	add_child(_build_row)
	_build_row.resized.connect(_place_build_row)
	resized.connect(_place_build_row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_build_row.add_child(col)
	col.add_child(_label("Проходы", 16, MUTED))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	col.add_child(tools)
	for t in TOOLS:
		var b := IconButton.make(t[1], t[2], 108, 76)
		b.pressed.connect(func() -> void:
			var why: String = _tool_lock.get(t[0], "")
			if not why.is_empty():
				log_event(why, "warning")
				return
			_room_purpose = 0
			_pick_tool(t[0], t[1], t[2]))
		_tool_btns[t[0]] = b
		tools.add_child(b)
	col.add_child(_label("Комнаты — выберите, что построить (сразу обустроят). Серые — ещё не изучены:", 16, MUTED))
	_room_grid = GridContainer.new()
	_room_grid.columns = ROOM_COLS
	_room_grid.add_theme_constant_override("h_separation", 8)
	_room_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(_room_grid)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
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
	var worlds := IconButton.make("planet", "Миры")
	worlds.pressed.connect(func() -> void: worlds_pressed.emit())
	worlds.visible = false
	_worlds_btn = worlds
	bar.add_child(worlds)
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
		build_opened.emit()
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


## Плитки комнат в меню стройки: [{"id", "name", "tex" (путь картинки) или "glyph", "ok", "why"}].
func set_build_rooms(items: Array, locks: Dictionary = {}) -> void:
	_tool_lock = locks
	for m in _tool_btns:
		(_tool_btns[m] as Control).modulate = Color(1, 1, 1, 0.4) if not str(locks.get(m, "")).is_empty() else Color.WHITE
	for c in _room_grid.get_children():
		_room_grid.remove_child(c)
		c.queue_free()
	for it in items:
		var ok: bool = it["ok"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 104)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", btn_box(Color(0.22, 0.24, 0.3) if ok else Color(0.15, 0.16, 0.19)))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var pic: Control
		var path: String = it.get("tex", "")
		if not path.is_empty() and ResourceLoader.exists(path):
			var tr := TextureRect.new()
			tr.texture = load(path)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(88, 54)
			pic = tr
		else:
			pic = IconView.make("", 44, it.get("glyph", "room"), Color.WHITE)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.modulate = Color.WHITE if ok else Color(0.4, 0.4, 0.45, 0.8)
		v.add_child(pic)
		var l := _label(it["name"], 14, Color.WHITE if ok else MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(96, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		var id: int = it["id"]
		var nm: String = it["name"]
		var why: String = it.get("why", "")
		b.pressed.connect(func() -> void:
			if not ok:
				log_event(why, "warning")
				return
			_room_purpose = id
			_pick_tool(Mode.ROOM, "room", nm))
		_room_grid.add_child(b)


## Под что строят комнату (0 — пустая).
func room_purpose() -> int:
	return _room_purpose


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
## Пока палец листает список — не обновляем (иначе прокрутку сбивает); место прокрутки сохраняем.
func refresh_panel(spec: Dictionary) -> void:
	if _scrolling():
		return
	var keep := _scroll.scroll_vertical
	_fill_header(spec)
	_fill_body(spec.get("rows", []))
	_fit_scroll.call_deferred()
	_scroll.set_deferred("scroll_vertical", keep)


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
		"store":
			_build_store(st)
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
		if not item.has("button") or str(item["button"]).is_empty():
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


## Склад: по ресурсу — галочка «хранить», предел «до» и (если его добывают) «добывать до».
##  {"type": "store", "label", "items": [{"key", "on", "held", "limit", "cap", "target" (-1 — не добывают)}],
##   "toggled": Callable(ключ, вкл), "limit": Callable(ключ, n), "target": Callable(ключ, n)}
func _build_store(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	for item in st["items"]:
		var key: String = item["key"]
		var on: bool = item["on"]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.06 if on else 0.02), 10, 6))
		_controls.add_child(p)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		p.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		# Кнопка-галочка: квадрат с галкой, значок и название ресурса.
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = on
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggled.connect(func(v: bool) -> void: st["toggled"].call(key, v))
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		for c: Control in [IconView.make("", 26, "check" if on else "check_off", Color.WHITE if on else MUTED),
				IconView.make(key, 28), _label(Mat.resource_name(key), 18, Color.WHITE if on else MUTED)]:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			inner.add_child(c)
		b.custom_minimum_size.x = 30 + 26 + 28 + 16 + 12 * Mat.resource_name(key).length()
		row.add_child(b)
		if not on:
			row.add_child(_label("не хранить", 16, MUTED))
			continue
		var cap: int = item["cap"]
		row.add_child(_label("сейчас %s из %s" % [Fmt.int_spaced(item["held"]), Fmt.int_spaced(cap)], 17, Color.WHITE))
		var set_target := Callable()
		var lim_row := _store_line(col, "Хранить не больше")
		_stepper_widgets(lim_row, int(item["limit"]), 0, cap, 10, [], func(v: int) -> void:
			st["limit"].call(key, v)
			if set_target.is_valid():
				set_target.call(mini(v, int(item["target"]))))
		if int(item["target"]) >= 0:
			set_target = _stepper_widgets(_store_line(col, "Работники склада добывают, пока меньше"), int(item["target"]), 0, cap, 10, [],
				func(v: int) -> void:
					item["target"] = v
					st["target"].call(key, v))


## Строка настройки ресурса на складе: подпись справа и место под переключатель.
func _store_line(col: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var l := _label(text, 16, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	return row


func _build_stepper(st: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_controls.add_child(row)
	var label := _label(st["label"], 19, Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_stepper_widgets(row, int(st["value"]), int(st["min"]), int(st["max"]), int(st.get("step", 1)),
		st.get("options", []), st["changed"])


## Возвращает, чем выставить значение снаружи (без вызова changed).
func _stepper_widgets(row: HBoxContainer, start: int, lo: int, hi: int, step: int, options: Array, changed: Callable) -> Callable:
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
	return func(v: int) -> void:
		state["v"] = clampi(v, lo, hi)
		refresh.call()


## Простая карточка из текста (первая строка — заголовок).
func show_info(text: String, actions: Array = [], controls: Array = []) -> void:
	var lines := text.split("\n")
	var rows := []
	if lines.size() > 1:
		rows.append({"type": "text", "text": "\n".join(lines.slice(1))})
	show_panel({"title": lines[0], "rows": rows, "actions": actions, "controls": controls})


func hide_info() -> void:
	_info_panel.visible = false
	if _tree_panel != null:
		_tree_panel.visible = false


func info_visible() -> bool:
	return _info_panel.visible or (_tree_panel != null and _tree_panel.visible)


# --- Прокрутка пальцем -----------------------------------------------------------------
## Касание в списке сначала ничего не нажимает: сдвинул палец больше чем на DRAG_DEADZONE —
## это прокрутка (с инерцией), отпустил на месте — обычное нажатие (кнопка срабатывает).
## Так список листается и там, где под пальцем кнопка.
const DRAG_DEADZONE := 20.0
var _press_event: InputEventMouseButton = null
var _press_region := ""
var _dragging := false
var _drag_prev := Vector2.ZERO
var _drag_t := 0
var _drag_vel := Vector2.ZERO
var _inertia_region := ""
var _replaying := false
var _panel_scroll_f := 0.0
## Последние точки пальца [позиция, мс] — по ним скорость для инерции.
var _drag_samples: Array = []


func _scrolling() -> bool:
	return _press_event != null or not _inertia_region.is_empty()


func _scroll_region_at(pos: Vector2) -> String:
	if _tree_panel != null and _tree_panel.visible and _tree_clip.get_global_rect().has_point(pos):
		return "tree"
	if _info_panel.visible and _scroll.get_global_rect().has_point(pos) \
			and _scroll.get_v_scroll_bar().max_value > _scroll.size.y + 1.0:
		return "panel"
	return ""


func _input(event: InputEvent) -> void:
	if _replaying:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var region := _scroll_region_at(event.position)
			_inertia_region = ""
			if region.is_empty():
				return
			_press_event = event.duplicate()
			_press_region = region
			_dragging = false
			_drag_prev = event.position
			_drag_t = Time.get_ticks_msec()
			_drag_vel = Vector2.ZERO
			_drag_samples = [[event.position, Time.get_ticks_msec()]]
			_panel_scroll_f = _scroll.scroll_vertical
			get_viewport().set_input_as_handled()
		elif _press_event != null:
			var press := _press_event
			_press_event = null
			get_viewport().set_input_as_handled()
			if _dragging:
				_drag_vel = _release_velocity()
				_inertia_region = _press_region if _drag_vel.length() > 30.0 else ""
			else:
				_replay_tap.call_deferred(press, event.duplicate())
	elif event is InputEventMouseMotion and _press_event != null:
		get_viewport().set_input_as_handled()
		if not _dragging and (event.position - _press_event.position).length() > DRAG_DEADZONE:
			_dragging = true
			_drag_prev = _press_event.position
		if _dragging:
			var d: Vector2 = event.position - _drag_prev
			_drag_prev = event.position
			_drag_samples.append([event.position, Time.get_ticks_msec()])
			if _drag_samples.size() > 12:
				_drag_samples.pop_front()
			_scroll_by(_press_region, -d)


## Скорость броска: по пути пальца за последние ~80 мс. Палец остановился — без инерции.
func _release_velocity() -> Vector2:
	if _drag_samples.size() < 2:
		return Vector2.ZERO
	var now := Time.get_ticks_msec()
	var last: Array = _drag_samples[-1]
	if now - int(last[1]) > 100:
		return Vector2.ZERO
	var first: Array = _drag_samples[0]
	for s in _drag_samples:
		if int(last[1]) - int(s[1]) <= 80:
			first = s
			break
	var dt := maxf(1.0 / 60.0, (int(last[1]) - int(first[1])) / 1000.0)
	return (-((last[0] as Vector2) - (first[0] as Vector2)) / dt).limit_length(2500.0)


## Нажатие без сдвига — передаём кнопкам как обычно. Координаты события уже пересчитаны
## под масштаб экрана — второй раз не пересчитываем (in_local_coords), иначе на телефоне
## нажатие уходит мимо кнопки.
func _replay_tap(press: InputEventMouseButton, release: InputEventMouseButton) -> void:
	_replaying = true
	get_viewport().push_input(press, true)
	get_viewport().push_input(release, true)
	_replaying = false


func _scroll_by(region: String, d: Vector2) -> void:
	if region == "panel":
		_panel_scroll_f = clampf(_panel_scroll_f + d.y, 0.0, maxf(0.0, _scroll.get_v_scroll_bar().max_value - _scroll.size.y))
		_scroll.scroll_vertical = int(_panel_scroll_f)
	elif region == "tree":
		_tree_pan -= d
		_clamp_tree_pan()


func _process(delta: float) -> void:
	if _inertia_region.is_empty():
		return
	if _drag_vel.length() < 30.0 or (_inertia_region == "panel" and not _info_panel.visible) \
			or (_inertia_region == "tree" and not _tree_panel.visible):
		_inertia_region = ""
		return
	_scroll_by(_inertia_region, _drag_vel * delta)
	_drag_vel *= pow(0.03, delta)


# --- Дерево исследований (горизонтальное) ------------------------------------------------
## Столбцы — ступени: слева то, что можно изучать сразу, правее — то, что требует изученного
## левее. Линии — что из чего следует. Нажатие на узел — описание и кнопка «Изучать».
const NODE_W := 220.0
const NODE_H := 64.0
const COL_GAP := 60.0
const ROW_GAP := 12.0
var _tree_panel: PanelContainer
var _tree_title: Label
var _tree_sub: Label
var _tree_rows: VBoxContainer
var _tree_clip: Control
var _tree_canvas: TreeCanvas
var _tree_detail: VBoxContainer
var _tree_pan := Vector2.ZERO
var _tree_items: Array = []
var _tree_selected := ""


class TreeCanvas extends Control:
	## [[от, до, цвет]] в координатах холста.
	var edges: Array = []

	func _draw() -> void:
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var mx := (a.x + b.x) * 0.5
			var pts := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				# Плавная «S»: горизонтально выходит из узла и горизонтально входит в следующий.
				var p := a.bezier_interpolate(Vector2(mx, a.y), Vector2(mx, b.y), b, t)
				pts.append(p)
			draw_polyline(pts, e[2], 3.0, true)


func _build_tree_panel() -> void:
	_tree_panel = PanelContainer.new()
	_tree_panel.visible = false
	# Непрозрачный фон — карта под деревом не мешает читать.
	var bg := _box(Color(PANEL_BG, 1.0), 18, 14)
	_tree_panel.add_theme_stylebox_override("panel", bg)
	add_child(_tree_panel)
	_tree_panel.visibility_changed.connect(func() -> void:
		if _log != null:
			_log.visible = not _tree_panel.visible and not _info_panel.visible)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_tree_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	_tree_title = _label("", 26, Color.WHITE)
	_tree_title.add_theme_font_override("font", Fonts.black())
	_tree_sub = _label("", 18, ACCENT)
	titles.add_child(_tree_title)
	titles.add_child(_tree_sub)
	var close := IconButton.make("close", "", 52, 52)
	close.pressed.connect(hide_info)
	head.add_child(close)
	_tree_rows = VBoxContainer.new()
	_tree_rows.add_theme_constant_override("separation", 4)
	v.add_child(_tree_rows)
	# Дерево слева, описание выбранного — справа (экран телефона невысокий).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_tree_clip = Control.new()
	_tree_clip.clip_contents = true
	_tree_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_clip.custom_minimum_size = Vector2(0, 120)
	body.add_child(_tree_clip)
	_tree_canvas = TreeCanvas.new()
	_tree_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_tree_clip.add_child(_tree_canvas)
	_tree_detail = VBoxContainer.new()
	_tree_detail.add_theme_constant_override("separation", 8)
	# Постоянная ширина: при выборе узла дерево не сжимается.
	_tree_detail.custom_minimum_size = Vector2(320, 0)
	body.add_child(_tree_detail)


## Дерево исследований: {"title", "subtitle", "rows", "items": [{"id", "name", "desc", "cost",
## "state": done|current|available|locked, "needs": [id], "pick": Callable}]}.
func show_tech_tree(spec: Dictionary) -> void:
	_menu.visible = false
	_new_game.visible = false
	_info_panel.visible = false
	var first := not _tree_panel.visible
	_tree_panel.visible = true
	_fill_tree(spec)
	_layout_tree_panel()
	if first:
		_focus_tree.call_deferred()


func refresh_tech_tree(spec: Dictionary) -> void:
	if _scrolling() or not _tree_panel.visible:
		return
	_fill_tree(spec)


func _layout_tree_panel() -> void:
	# Поверх строки ресурсов: на экране науки она не нужна, а место дереву нужно.
	var top := EDGE_TOP
	_tree_panel.position = Vector2(SIDE, top)
	_tree_panel.size = Vector2(size.x - SIDE * 2.0, size.y - BAR_H - top - 4.0)


func _fill_tree(spec: Dictionary) -> void:
	_tree_title.text = spec.get("title", "")
	_tree_sub.text = spec.get("subtitle", "")
	for c in _tree_rows.get_children():
		_tree_rows.remove_child(c)
		c.queue_free()
	for row in spec.get("rows", []):
		var node := _row(row)
		if node != null:
			if node is Label:
				(node as Label).custom_minimum_size = Vector2.ZERO
			_tree_rows.add_child(node)
	_tree_items = spec.get("items", [])
	# Узлы и кнопку «Изучать» пересобираем, только если что-то поменялось: иначе нажатие,
	# пришедшееся на ежесекундное обновление, теряется.
	var sig := _tree_signature()
	if sig != _tree_sig:
		_build_tree_nodes()


var _tree_sig := ""


func _tree_signature() -> String:
	var parts: PackedStringArray = [_tree_selected]
	for it in _tree_items:
		parts.append("%s:%s" % [it["id"], it["state"]])
	return ",".join(parts)


func _build_tree_nodes() -> void:
	_tree_sig = _tree_signature()
	# Ступень узла — длиннейшая цепочка требований до него.
	var by_id := {}
	for it in _tree_items:
		by_id[it["id"]] = it
	var tier := {}
	var tier_of := func(id: String, self_ref: Callable) -> int:
		if tier.has(id):
			return tier[id]
		var t := 0
		for n in by_id[id]["needs"]:
			if by_id.has(n):
				t = maxi(t, self_ref.call(n, self_ref) + 1)
		tier[id] = t
		return t
	var cols: Array = []
	for it in _tree_items:
		var t: int = tier_of.call(it["id"], tier_of)
		while cols.size() <= t:
			cols.append([])
		cols[t].append(it["id"])
	# В столбце — ближе к тем, из кого вырастает (по среднему ряду требований).
	var row_of := {}
	for ci in cols.size():
		var col: Array = cols[ci]
		if ci > 0:
			col.sort_custom(func(a: String, b: String) -> bool:
				return _avg_row(by_id[a]["needs"], row_of) < _avg_row(by_id[b]["needs"], row_of))
		for ri in col.size():
			row_of[col[ri]] = ri
	var pos := {}
	var max_rows := 0
	for ci in cols.size():
		max_rows = maxi(max_rows, cols[ci].size())
	for ci in cols.size():
		var col: Array = cols[ci]
		for ri in col.size():
			pos[col[ri]] = Vector2(ci * (NODE_W + COL_GAP), ri * (NODE_H + ROW_GAP))
	for c in _tree_canvas.get_children():
		_tree_canvas.remove_child(c)
		c.queue_free()
	var edges := []
	for it in _tree_items:
		var p: Vector2 = pos[it["id"]]
		for n in it["needs"]:
			if pos.has(n):
				var from: Vector2 = pos[n] + Vector2(NODE_W, NODE_H * 0.5)
				var done: bool = by_id[n]["state"] == "done"
				# Связи выбранного узла — ярко, остальные приглушены.
				var col := Color(0.45, 0.8, 0.5, 0.55) if done else Color(1, 1, 1, 0.14)
				if not _tree_selected.is_empty() and (it["id"] == _tree_selected or n == _tree_selected):
					col = ACCENT
				edges.append([from, p + Vector2(0, NODE_H * 0.5), col])
		_tree_canvas.add_child(_tree_node(it, p))
	_tree_canvas.edges = edges
	_tree_canvas.custom_minimum_size = Vector2(cols.size() * (NODE_W + COL_GAP) - COL_GAP, max_rows * (NODE_H + ROW_GAP) - ROW_GAP)
	_tree_canvas.size = _tree_canvas.custom_minimum_size
	_tree_canvas.queue_redraw()
	_clamp_tree_pan()
	_fill_tree_detail()


static func _avg_row(needs: Array, row_of: Dictionary) -> float:
	var s := 0.0
	var n := 0
	for id in needs:
		if row_of.has(id):
			s += row_of[id]
			n += 1
	return s / n if n > 0 else 0.0


func _tree_node(it: Dictionary, p: Vector2) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.position = p
	b.size = Vector2(NODE_W, NODE_H)
	b.custom_minimum_size = b.size
	b.clip_text = true
	b.text = "%s\n%d очков" % [it["name"], it["cost"]]
	b.add_theme_font_size_override("font_size", 16)
	# Узлы непрозрачные — линии под ними не просвечивают.
	var bg := Color(0.26, 0.22, 0.25)
	var fg := MUTED
	match it["state"]:
		"done":
			bg = Color(0.2, 0.42, 0.24)
			fg = Color.WHITE
		"current":
			bg = Color(0.2, 0.33, 0.6)
			fg = Color.WHITE
		"available":
			bg = Color(0.42, 0.31, 0.14)
			fg = Color.WHITE
	var sb := _box(bg, 12, 8)
	if it["id"] == _tree_selected:
		sb.border_color = ACCENT
		sb.set_border_width_all(3)
	elif it["state"] == "available":
		sb.border_color = ACCENT.darkened(0.3)
		sb.set_border_width_all(2)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, fg)
	var id: String = it["id"]
	b.set_meta("id", id)
	b.pressed.connect(func() -> void:
		_tree_selected = id
		_build_tree_nodes.call_deferred())
	return b


func _fill_tree_detail() -> void:
	for c in _tree_detail.get_children():
		_tree_detail.remove_child(c)
		c.queue_free()
	var sel = null
	for it in _tree_items:
		if it["id"] == _tree_selected:
			sel = it
	if sel == null:
		var hint := _label("Нажмите на исследование, чтобы прочитать и начать.\n\nЛистайте дерево пальцем: левее — основы, правее — то, что открывается после них.\n\nЗелёное — изучено, синее — изучается, с оранжевой рамкой — можно начать.", 16, MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(320, 0)
		_tree_detail.add_child(hint)
		return
	var t := _label("%s · %d очков" % [sel["name"], sel["cost"]], 20, Color.WHITE)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(320, 0)
	_tree_detail.add_child(t)
	var d := _label(sel["desc"], 16, MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(320, 0)
	_tree_detail.add_child(d)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(320, 54)
	b.add_theme_font_size_override("font_size", 18)
	match sel["state"]:
		"done":
			b.text = "Изучено"
			b.disabled = true
		"current":
			b.text = "Изучается"
			b.disabled = true
		"available":
			b.text = "Изучать"
			b.add_theme_stylebox_override("normal", btn_box(ACCENT))
			b.pressed.connect(sel["pick"])
		_:
			b.text = "Недоступно"
			b.disabled = true
	_tree_detail.add_child(b)


func _clamp_tree_pan() -> void:
	if _tree_canvas == null:
		return
	var view := _tree_clip.size
	var cs := _tree_canvas.size
	_tree_pan.x = clampf(_tree_pan.x, minf(0.0, view.x - cs.x - 20.0), 20.0)
	_tree_pan.y = clampf(_tree_pan.y, minf(0.0, view.y - cs.y - 20.0), 20.0)
	_tree_canvas.position = _tree_pan


## При открытии — показать «передний край»: что изучается или доступно, ближе к левому краю.
func _focus_tree() -> void:
	_layout_tree_panel()
	var target := Vector2(20, 20)
	var want := ""
	for it in _tree_items:
		if it["state"] == "current":
			want = it["id"]
	if want.is_empty():
		for it in _tree_items:
			if it["state"] == "available":
				want = it["id"]
				break
	for c in _tree_canvas.get_children():
		if c.get_meta("id", "") == want:
			# Столбец с ним — у левого края, сам узел — в верхней части видимого.
			target = Vector2(20, 12) - Vector2(c.position.x, maxf(0.0, c.position.y - NODE_H - ROW_GAP))
	_tree_pan = target
	_clamp_tree_pan()


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
	var bg_hint := _label("Включено — пока вас нет, жители работают (до 1 часа). Выключено — игра на паузе, пока вы не вернётесь.", 16, MUTED)
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
