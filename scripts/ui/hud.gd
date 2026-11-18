class_name Hud
extends Control
## Интерфейс поверх мира. Строится кодом, чтобы легко менять раскладку.
## Сверху — ресурсы значками и дата, снизу — кнопки-значки и карточка выбранного.

## Выбран инструмент: режим и ширина комнаты (для комнат).
signal mode_changed(mode: int, room_width: int)
## Во время установки комнаты поменяли размер или материал.
signal room_options_changed(width: int, material: String)
## Выбрали материал тоннеля, шахты, лифта или бура.
signal tool_material_changed(mode: int, material: String)
signal home_pressed
## «Планеты»: Земля, колонии на планетах, ракеты в полёте.
signal worlds_pressed
## Нажали на бургер в строке ресурсов — показать, сколько какой еды.
signal food_pressed
## Открыли меню стройки — main присылает плитки комнат (set_build_rooms).
signal build_opened
## Выбрана скорость игры: номер кнопки (×1, ×10, ×20).
signal speed_selected(index: int)
signal science_pressed
signal people_pressed
## Кнопка «Постройки»: список всех построек.
signal objects_pressed
## Карточку закрыли крестиком.
signal info_closed
## Сохранить: sid — слот для перезаписи (пусто — новый), name — название (пусто — как было).
signal save_requested(sid: String, name: String)
## Нажали на строку журнала, у которой есть место (клетка): камера — туда.
signal log_pressed(at: Vector2i)
## Выгрузить сохранение файлом в «Загрузки» (прислать разработчику).
signal export_pressed
signal load_requested(sid: String)
## Выйти в главное меню; save — сохраниться перед выходом.
signal exit_requested(save: bool)
signal setting_changed(key: String, value: Variant)

## LOOK — обычный режим: нажатие показывает то, что под пальцем, и действия с ним.
## Остальные — разовые: после «Построить», «Отмены» или выбора точки возвращаемся в LOOK.
enum Mode { LOOK, TUNNEL, ROOM, BRIDGE, SEND, MINE, LIFT, CARGO_LIFT, DRILL, DRILL_LIFT, PROBE }

## Инструменты «Стройки»: [режим, значок, подпись].
const TOOLS := [
	[Mode.TUNNEL, "tunnel", "Тоннель"],
	[Mode.MINE, "mine", "Шахта"],
	[Mode.BRIDGE, "bridge", "Мост"],
	[Mode.LIFT, "lift", "Лифт"],
	[Mode.CARGO_LIFT, "cargo_lift", "Грузовой лифт"],
	[Mode.DRILL, "drill", "Бур"],
	[Mode.DRILL_LIFT, "drill", "Бур-лифт"],
	[Mode.PROBE, "drill", "Геоскважина"],
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
	Mode.DRILL_LIFT: "Коснитесь, где поставить бур (лифт — позади него). Куда бурить — выберете в карточке, потом не сменить",
	Mode.PROBE: "Коснитесь, где поставить геоскважину (2×2). Куда пустить зонд — в её карточке",
}
## Ключ карточки постройки (BuildInfo) у проходов.
const TOOL_INFO := {Mode.TUNNEL: "tunnel", Mode.MINE: "mine", Mode.BRIDGE: "bridge", Mode.LIFT: "lift",
	Mode.CARGO_LIFT: "cargo_lift", Mode.DRILL: "drill", Mode.DRILL_LIFT: "drill_lift", Mode.PROBE: "probe", Mode.ROOM: "room"}
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
const ACCENT := Color("FB923C")
const MUTED := Color(0.78, 0.72, 0.68)
const RED := Color(0.89, 0.36, 0.29)
## Оформление: тёплые тёмные панели, кнопки с «бортиком» снизу (тон того же цвета).
const PANEL_BG := Color(0.06, 0.16, 0.2, 0.95)
const TOP_BG := Color(0.05, 0.13, 0.17, 0.82)
const BTN := UiStyle.TILE
const GREEN := Color(0.3, 0.72, 0.38)

var _status: Label
var _date: Label
var _weather: TextureRect
var _weather_name := ""
## Значки ресурсов: не помещаются в строку — переносятся во вторую (раньше строка
## раздвигала весь интерфейс шире экрана: дата и кнопки скорости уходили за край).
var _res_box: HFlowContainer
var _top_panel: PanelContainer
var _date_panel: PanelContainer
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
var _menu_load: Button
## Окно поверх меню: «Загрузить», «Настройки», «Выйти в меню».
var _sub: PanelContainer
var _sub_box: VBoxContainer
## Мир, в который играем (его сохранения — в «Загрузить»); пусто — без миров.
var world_id := ""
var _log: VBoxContainer
var _info_panel: PanelContainer
var _title: Label
var _subtitle: Label
var _scroll: ScrollContainer
var _objects_btn: IconButton
## Какое окно открыто в карточке (чтобы при перестройке того же окна не сбрасывать прокрутку).
var _panel_id := ""
## Ширина правой части карточки (в обычной карточке — вся карточка).
var _pw := float(PANEL_WIDTH)
## Карточка комнаты: широкое окно в два столбца (превью и показатели слева, работники справа).
var _room_mode := false
var _room_left: VBoxContainer
var _head_chips: HBoxContainer
var _head_tex: TextureRect
var _preview_vp: SubViewport
var _preview_cam: Camera2D
var _preview_box: SubViewportContainer
## Мир, из которого показывать превью комнаты (задаёт main: свой World2D).
var room_world: World2D
var _body: VBoxContainer
var _controls: VBoxContainer
var _actions: HFlowContainer
var _hint: Label
var _hint_cancel: Button
## Полоска выбора комнаты: размеры и материалы.
var _room_strip: HBoxContainer
var _room_w := 6
var _room_mat := "wood"
var _room_mats: Array = ["wood"]
## Материалы для остальных построек: режим -> [ключи] и выбранный ключ.
var _tool_mats := {}
var _tool_mat := {}

var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_text: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = make_theme()
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
	# Лента событий — под всеми окнами (стройка, карточки, меню): открытое окно её закрывает,
	# а не она его.
	move_child(_log, 0)
	# Справа, под датой: слева — карточка и кнопка стройки.
	_log.position = Vector2(size.x - SIDE - PANEL_WIDTH, TOP_H)
	_log.size = Vector2(PANEL_WIDTH, 0)
	_build_hint()
	_build_panel()
	_build_tree_panel()
	_build_dialog()


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.bold()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", UiStyle.window(22, 14))
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb := btn_box(BTN)
		match state:
			"hover":
				sb = btn_box(BTN.lightened(0.1))
			"pressed", "hover_pressed":
				sb = btn_box(ACCENT, true)
			"disabled":
				sb = btn_box(Color(BTN.darkened(0.3), 0.8))
		t.set_stylebox(state, "Button", sb)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))
	return t


## Окно (карточка, меню, верхние плашки) — тёмно-синее со светлой каймой.
static func _win(radius := 22, pad := 14.0, alpha := 0.96) -> StyleBox:
	return UiStyle.window(radius, pad, alpha)


static func _box(col: Color, radius: int, pad: float) -> StyleBoxFlat:
	return UiStyle.flat(col, radius, pad)


static func _box_plain(col: Color, radius: int, pad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


## Кнопка — объёмная плитка цвета col (градиент, светлый кант, бортик снизу); pressed — вдавлена.
static func btn_box(col: Color, pressed := false) -> StyleBox:
	# Главные (оранжевые) кнопки — оранжевым градиентом по диагонали.
	if col.is_equal_approx(ACCENT):
		return UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 16, 10, pressed, false)
	return UiStyle.tile(col, pressed)


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
	panel.add_theme_stylebox_override("panel", _win(18, 10, 0.86))
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(panel)
	_top_panel = panel
	_res_box = HFlowContainer.new()
	_res_box.add_theme_constant_override("h_separation", 14)
	_res_box.add_theme_constant_override("v_separation", 6)
	_res_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_res_box)
	resized.connect(_fit_top)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	var date_panel := PanelContainer.new()
	date_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_panel.add_theme_stylebox_override("panel", _win(18, 10, 0.86))
	date_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(date_panel)
	_date_panel = date_panel
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
	# Погода, высота и версия на верхней плашке не нужны — только дата (подписи остаются
	# скрытыми: их обновляет игра).
	for l in [_date, _status, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.visible = false


static func _outlined(text: String, fs: int, col: Color) -> Label:
	var l := _label(text, fs, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	return l


var _worlds_btn: Control


## «Планеты» — только когда есть куда лететь (изучено ракетостроение) или уже летали.
func set_worlds_visible(on: bool) -> void:
	if _worlds_btn != null and _worlds_btn.visible != on:
		_worlds_btn.visible = on


## Строка ресурсов: гаврики и запасы значками. Перестраивается только при изменениях.
func set_resources(inventory: Dictionary, people: int, hungry := 0, power_made := 0, power_used := 0, power_known := false) -> void:
	_last_inventory = inventory
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
		# Ресурс нажимается: где его искать (глубина, порода, что рядом).
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.add_child(IconView.make(k, 24))
		item.add_child(_label(Fmt.int_spaced(inventory.get(k, 0)), 19, Color(0.97, 0.92, 0.75)))
		var key: String = k
		item.gui_input.connect(func(e: InputEvent) -> void:
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				show_message(Mat.resource_name(key), ResourceHints.text(key)))
		_res_box.add_child(item)
	# «?» — справочник: где искать любой ресурс, даже которого ещё нет.
	var help := PanelContainer.new()
	help.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.16), 14, 2))
	help.custom_minimum_size = Vector2(30, 28)
	var q := _label("?", 20, Color.WHITE)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_child(q)
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	help.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_open_resources(true))
	_res_box.add_child(help)
	_fit_top.call_deferred()


## Ширина строки ресурсов — не больше, чем осталось до даты: лишние значки уходят во
## вторую строку, а журнал, подсказка и карточка опускаются под неё.
func _fit_top() -> void:
	if _res_box == null or _date_panel == null:
		return
	var natural := 0.0
	var n := 0
	for c in _res_box.get_children():
		if c.is_queued_for_deletion():
			continue
		natural += (c as Control).get_combined_minimum_size().x
		n += 1
	natural += 14.0 * maxi(0, n - 1)
	var avail := size.x - SIDE * 2.0 - _date_panel.get_combined_minimum_size().x - 12.0 - 20.0
	_res_box.custom_minimum_size.x = maxf(200.0, minf(natural, avail))
	if _log != null:
		_log.position = Vector2(size.x - SIDE - PANEL_WIDTH, _top_h())
	if _hint != null and _hint.is_visible_in_tree():
		_place_hint()


## Где кончается верхняя строка (в одну строку ресурсов — как раньше, TOP_H).
func _top_h() -> float:
	if _top_panel == null:
		return TOP_H
	return maxf(TOP_H, _top_panel.position.y + EDGE_TOP + _top_panel.size.y - 12.0)


func _chip_plain(glyph: String, text: String, col: Color) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 4)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Гаврик и молния — картинками, если они есть; иначе значок кодом в цвет текста.
	item.add_child(IconView.make(glyph, 24) if ResIcon.texture(glyph) != null else IconView.make("", 22, glyph, col))
	item.add_child(_label(text, 19, col))
	return item


## Дата и значок погоды (имя картинки assets/icons/weather_<weather>.png).
func set_date(text: String, weather := "") -> void:
	_date.text = text
	if weather != _weather_name:
		_weather_name = weather
		_weather.texture = ResIcon.texture("weather_" + weather) if not weather.is_empty() else null
		_weather.visible = false


## Высотомер (глубина или высота камеры).
func set_status(text: String) -> void:
	_status.text = text


# --- Низ: карточка, подменю стройки, кнопки ------------------------------------------------

func _build_bottom(box: VBoxContainer) -> void:
	# Окно «Строительство»: шапка с каской и крестиком, ниже два раздела — проходы (синяя
	# плашка) и комнаты (оранжевая); недоступное — серое.
	_build_row = PanelContainer.new()
	_build_row.add_theme_stylebox_override("panel", _win(24, 12))
	_build_row.visible = false
	add_child(_build_row)
	_build_row.resized.connect(_place_build_row)
	resized.connect(_place_build_row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_build_row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	head.add_child(IconView.make("", 40, "helmet", ACCENT))
	var title := _label("Строительство", 28, Color.WHITE)
	title.add_theme_font_override("font", Fonts.black())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var close := IconButton.make("close", "", 44, 44)
	close.pressed.connect(func() -> void: _build_btn.button_pressed = false)
	head.add_child(close)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	col.add_child(_section("build", "ПРОХОДЫ И ШАХТЫ", "Создавайте проходы, шахты и буровые конструкции", UiStyle.TEAL_A, tools, UiStyle.TEAL_B))
	for t in TOOLS:
		var b := IconButton.make(t[1], t[2], 112, 60)
		b.pressed.connect(func() -> void:
			var why: String = _tool_lock.get(t[0], "")
			if not why.is_empty():
				log_event(why, "warning")
				return
			_room_purpose = 0
			_pick_tool(t[0], t[1], t[2]))
		_tool_btns[t[0]] = b
		tools.add_child(b)
	_room_grid = GridContainer.new()
	_room_grid.columns = ROOM_COLS
	_room_grid.add_theme_constant_override("h_separation", 8)
	_room_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(_section("home", "КОМНАТЫ", "Стройте жилые, производственные и исследовательские комнаты", UiStyle.ORANGE_A, _room_grid, UiStyle.ORANGE_B))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	_build_btn = IconButton.make("build", "Стройка")
	_build_btn.toggle_mode = true
	# Главная кнопка — оранжевая.
	_build_btn.add_theme_stylebox_override("normal", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 16, 10, false, false))
	_build_btn.add_theme_stylebox_override("hover", UiStyle.grad(UiStyle.ORANGE_A.lightened(0.08), UiStyle.ORANGE_B.lightened(0.08), 16, 10, false, false))
	_build_btn.add_theme_stylebox_override("pressed", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 16, 10, true, false))
	_build_btn.toggled.connect(_on_build_toggled)
	bar.add_child(_build_btn)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var people := IconButton.make("people", "Гаврики")
	people.pressed.connect(func() -> void: people_pressed.emit())
	bar.add_child(people)
	var objects := IconButton.make("room", "Постройки")
	objects.pressed.connect(func() -> void: objects_pressed.emit())
	_objects_btn = objects
	bar.add_child(objects)
	var science := IconButton.make("flask", "Наука")
	science.pressed.connect(func() -> void: science_pressed.emit())
	bar.add_child(science)
	var worlds := IconButton.make("planet", "Планеты")
	worlds.pressed.connect(func() -> void: worlds_pressed.emit())
	worlds.visible = false
	_worlds_btn = worlds
	bar.add_child(worlds)
	var home := IconButton.make("home", "К базе")
	bar.add_child(home)
	# Скорость — переключатель в одной панели.
	var seg := PanelContainer.new()
	seg.add_theme_stylebox_override("panel", _win(18, 6, 0.86))
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
		# Поля у нажатой — как у обычной: иначе «×20» не влезала и показывалась «×2».
		var on := UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 14, 8, true, false)
		on.content_margin_left = 6
		on.content_margin_right = 6
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, on)
		b.pressed.connect(func() -> void: speed_selected.emit(i))
		seg_row.add_child(b)
	var menu := IconButton.make("menu", "Меню")
	bar.add_child(menu)
	home.pressed.connect(func() -> void: home_pressed.emit())
	menu.pressed.connect(func() -> void:
		var open := not _menu.visible and not _sub.visible
		close_overlays()
		_menu_load.visible = not world_id.is_empty()
		_menu.visible = open)


## Раздел окна: цветная плашка (значок, заголовок, черта, пояснение) над тёмной подложкой
## с каймой того же цвета, в ней — content.
func _section(glyph: String, title: String, text: String, tint: Color, content: Control, tint_b := Color(0, 0, 0, 0)) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.grad(tint, tint_b, 16, 7) if tint_b.a > 0.0 else UiStyle.banner(tint, 16, 7))
	bar.z_index = 1
	box.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	row.add_child(IconView.make("", 30, glyph, Color.WHITE))
	var t := _label(title, 24, Color.WHITE)
	t.add_theme_font_override("font", Fonts.black())
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	t.add_theme_constant_override("shadow_offset_y", 2)
	row.add_child(t)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.55)
	line.custom_minimum_size = Vector2(2, 30)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var d := _label(text, 17, Color(1, 1, 1, 0.92))
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(d)
	var body := PanelContainer.new()
	var sb := UiStyle.section(tint, 16, 8)
	sb.content_margin_top = 13
	body.add_theme_stylebox_override("panel", sb)
	body.add_child(content)
	box.add_child(body)
	return box


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
	_sub.visible = false
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
	if mode != Mode.ROOM:
		_show_tool_strip(mode)
	_show_build_info(BuildInfo.card(TOOL_INFO.get(mode, ""), _room_purpose))
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
		b.custom_minimum_size = Vector2(106, 88)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", btn_box(BTN if ok else BTN.darkened(0.35)))
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
			tr.custom_minimum_size = Vector2(84, 40)
			pic = tr
		else:
			pic = IconView.make("", 44, it.get("glyph", "room"), Color.WHITE)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.modulate = Color.WHITE if ok else Color(0.4, 0.4, 0.45, 0.8)
		v.add_child(pic)
		# Слово длиннее плитки («Обогатительная») — шрифт мельче, без переноса посреди слова.
		var lfs := 13
		for word in String(it["name"]).replace("-", "- ").split(" "):
			while lfs > 10 and Fonts.bold().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x > 96:
				lfs -= 1
		var l := _label(it["name"], lfs, Color.WHITE if ok else MUTED)
		l.add_theme_constant_override("line_spacing", -4)
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


## Материалы, доступные для тоннеля, шахты, лифтов и бура: {режим: [ключи]}.
func set_tool_materials(mats: Dictionary) -> void:
	_tool_mats = mats
	for m in _tool_mat.keys():
		if not (_tool_mats.get(m, []) as Array).has(_tool_mat[m]):
			_tool_mat.erase(m)


## Выбранный материал постройки режима mode ("wood" — обычный).
func tool_material(mode: int) -> String:
	return str(_tool_mat.get(mode, "wood"))


## Полоска выбора материала (если есть из чего выбирать): тоннель, шахта, лифт, бур.
func _show_tool_strip(mode: int) -> void:
	for c in _room_strip.get_children():
		_room_strip.remove_child(c)
		c.queue_free()
	var mats: Array = _tool_mats.get(mode, [])
	_room_strip.visible = mats.size() > 1
	if mats.size() <= 1:
		return
	var group := ButtonGroup.new()
	var cur := tool_material(mode)
	for m in mats:
		var nm: String = Project.MATERIALS[m][0] if m != "wood" or mode in [Mode.TUNNEL, Mode.MINE] else "Обычный"
		var b := IconButton.make("", nm, 96, 72)
		if m != "wood" or mode in [Mode.TUNNEL, Mode.MINE]:
			b.res_key = m
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m == cur
		b.pressed.connect(func() -> void:
			_tool_mat[mode] = m
			tool_material_changed.emit(mode, m))
		_room_strip.add_child(b)
	_place_hint.call_deferred()


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
	# Супер-материал — только тот, что подходит выбранному назначению.
	var shown := _room_mats.filter(func(m: String) -> bool:
		return not Project.SUPER.has(m) or _room_purpose <= 0 or RoomType.SUPER_MAT.get(_room_purpose, "") == m)
	if not shown.has(_room_mat):
		_room_mat = "wood"
	for m in shown:
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
	_show_build_info([])


## --- Карточка постройки в меню стройки ------------------------------------------------
## Справа: что это, куда ставить, как работает, кто работает (пока выбираете место).
var _build_info: PanelContainer
var _build_info_box: VBoxContainer
const BUILD_INFO_W := 460


func _show_build_info(card: Array) -> void:
	if _build_info == null:
		_build_info = PanelContainer.new()
		_build_info.add_theme_stylebox_override("panel", _win(20, 12))
		_build_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_build_info)
		_build_info_box = VBoxContainer.new()
		_build_info_box.add_theme_constant_override("separation", 6)
		_build_info.add_child(_build_info_box)
	for c in _build_info_box.get_children():
		_build_info_box.remove_child(c)
		c.queue_free()
	_build_info.visible = not card.is_empty()
	if _log != null:
		_log.visible = card.is_empty() and not _info_panel.visible
	if card.is_empty():
		return
	_build_info_box.add_child(_label(card[0], 22, ACCENT))
	for line: String in card[1]:
		var l := _label(line, 17, Color(0.9, 0.92, 0.96))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(BUILD_INFO_W - 24, 0)
		_build_info_box.add_child(l)
	_build_info.reset_size()
	_build_info.position = Vector2(size.x - SIDE - BUILD_INFO_W, _top_limit())
	_build_info.size.x = BUILD_INFO_W
	_place_hint.call_deferred()


## Подсказка сверху по центру — что сейчас делать (с кнопкой «Отмена»).
func _build_hint() -> void:
	var box := HBoxContainer.new()
	box.name = "Hint"
	box.add_theme_constant_override("separation", 10)
	box.visible = false
	add_child(box)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _win(20, 10))
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
	box.position = Vector2((size.x - box.size.x) * 0.5, _top_h() + 18)
	_room_strip.reset_size()
	_room_strip.position = Vector2((size.x - _room_strip.size.x) * 0.5, box.position.y + box.size.y + 8)
	if _build_info != null and _build_info.visible:
		_build_info.position = Vector2(size.x - SIDE - BUILD_INFO_W, _top_limit())


## Сколько места сверху занято подсказкой и полоской выбора.
func _top_limit() -> float:
	var top := _top_h()
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
	add_child(_info_panel)
	# Лента событий в том же углу — пока открыта карточка, прячем её.
	_info_panel.visibility_changed.connect(func() -> void:
		if _log != null:
			_log.visible = not _info_panel.visible)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_info_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	# Значок окна в цветной плитке слева от заголовка (как каска у «Строительства»).
	_head_icon_bg = PanelContainer.new()
	_head_icon_bg.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 14, 4, false, false))
	_head_icon_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_head_icon_bg)
	_head_icon = IconView.make("", 38, "room", Color.WHITE)
	_head_icon_bg.add_child(_head_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	_title = _label("", 26, Color.WHITE)
	_title.add_theme_font_override("font", Fonts.black())
	_subtitle = _label("", 18, ACCENT)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Ширина — сразу вся строка (без кнопки закрытия): иначе при коротком заголовке («Планеты»)
	# подпись в первый расчёт переносилась по букве, карточка вытягивалась на весь экран и пустела.
	_subtitle.custom_minimum_size = Vector2(PANEL_WIDTH - 40 - 64 - 66, 0)
	# Название и рядом кнопка «Описание» (у карточки комнаты): длинное описание — отдельным окном.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	titles.add_child(title_row)
	title_row.add_child(_title)
	_desc_btn = Button.new()
	_desc_btn.text = "Описание"
	_desc_btn.focus_mode = Control.FOCUS_NONE
	_desc_btn.custom_minimum_size = Vector2(0, 40)
	_desc_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_desc_btn.add_theme_font_size_override("font_size", 17)
	var dsb := UiStyle.flat(Color(1, 1, 1, 0.08), 12, 8)
	dsb.content_margin_left = 16
	dsb.content_margin_right = 16
	dsb.border_color = Color(UiStyle.TEAL_A, 0.8)
	dsb.set_border_width_all(2)
	_desc_btn.add_theme_stylebox_override("normal", dsb)
	_desc_btn.add_theme_stylebox_override("hover", dsb)
	_desc_btn.add_theme_stylebox_override("pressed", UiStyle.flat(Color(1, 1, 1, 0.16), 12, 8))
	_desc_btn.visible = false
	_desc_btn.pressed.connect(_show_room_desc)
	title_row.add_child(_desc_btn)
	titles.add_child(_subtitle)
	# Карточка комнаты: картинка комнаты вместо значка и плашки в шапке (размер, золото, статус).
	_head_tex = TextureRect.new()
	_head_tex.custom_minimum_size = Vector2(64, 52)
	_head_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_head_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_head_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_head_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_tex.visible = false
	head.add_child(_head_tex)
	head.move_child(_head_tex, 1)
	_head_chips = HBoxContainer.new()
	_head_chips.add_theme_constant_override("separation", 10)
	_head_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_chips.visible = false
	head.add_child(_head_chips)
	var close := IconButton.make("close", "", 52, 52)
	close.pressed.connect(func() -> void:
		hide_info()
		info_closed.emit())
	head.add_child(close)
	_mid = HBoxContainer.new()
	_mid.add_theme_constant_override("separation", 14)
	v.add_child(_mid)
	# Карточка комнаты — три колонки постоянной ширины: слева превью и условия, в середине
	# показатели, материал и настройки, справа — работники (прокручиваются только они).
	_room_left = VBoxContainer.new()
	_room_left.add_theme_constant_override("separation", 10)
	_room_left.visible = false
	_mid.add_child(_room_left)
	var colb := VBoxContainer.new()
	colb.add_theme_constant_override("separation", 10)
	colb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mid.add_child(colb)
	_room_top = VBoxContainer.new()
	_room_top.add_theme_constant_override("separation", 10)
	_room_top.visible = false
	colb.add_child(_room_top)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colb.add_child(_scroll)
	_build_room_right()
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
	# Кнопки — в строку, не влезают — переносятся (в карточке комнаты их много).
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	v.add_child(_actions)


## Карточка: {"title", "subtitle", "rows": [...], "controls": [...], "actions": [[текст, Callable, стиль?]],
## "controls_first": переключатели над описанием}.
## Строки rows: {"type": "progress"|"resources"|"chips"|"text"|"warning"|"section"|"portrait"|"stats", ...}.
## Управление controls: шаговые переключатели, галочки, нормы запаса (см. _build_control).
func show_panel(spec: Dictionary) -> void:
	_menu.visible = false
	_sub.visible = false
	if not _placing:
		_build_row.visible = false
		_build_btn.set_pressed_no_signal(false)
	# Та же карточка заново (после нажатия в ней) — прокрутка остаётся; другая — с начала.
	# Опознаём по "id", если он есть (заголовок со счётчиком — «Экипаж: 3 из 10» — меняется
	# от нажатия в списке, а это то же окно), иначе по заголовку.
	var pid := str(spec.get("id", spec.get("title", "")))
	var same := _info_panel.visible and pid == _panel_id
	_panel_id = pid
	_set_room_mode(spec)
	_fill_header(spec)
	_fill_rows(spec)
	# Старое убираем сразу, а не в конце кадра — иначе карточка меряет себя вместе с ним.
	for c in _controls.get_children():
		_controls.remove_child(c)
		c.queue_free()
	if _room_mode:
		_build_room_workers(spec["room"])
	for st in spec.get("controls", []):
		# Работников карточка комнаты показывает своим списком.
		if _room_mode and st.get("type", "") == "people":
			continue
		_build_control(st)
	_controls.visible = _controls.get_child_count() > 0
	# Переключатели можно поставить над описанием, чтобы не прятались под прокруткой.
	_body.get_parent().move_child(_controls, 0 if spec.get("controls_first", false) or _room_mode else 1)
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	var acts: Array = spec.get("actions", []).duplicate()
	if _room_mode:
		# Назначают из списка справа («Свободно»); «Ремонт» и «Снести» — справа в ряду.
		if int(spec["room"].get("slots", 0)) > 0:
			acts = acts.filter(func(a: Array) -> bool: return a[0] != "Назначить")
		var tail := acts.filter(func(a: Array) -> bool: return a[0] == "Ремонт" or a[0] == "Снести")
		acts = acts.filter(func(a: Array) -> bool: return not tail.has(a))
		tail.sort_custom(func(a: Array, _b: Array) -> bool: return a[0] == "Ремонт")
		acts.append_array(tail)
	for a in acts:
		var b := _action_button(a)
		var cb: Callable = a[1]
		b.pressed.connect(cb)
		_actions.add_child(b)
	if _room_mode:
		_fit_actions_row()
	_actions.visible = not spec.get("actions", []).is_empty()
	if _tree_panel != null:
		_tree_panel.visible = false
	_info_panel.visible = true
	_fit_scroll.call_deferred()
	# Новая карточка — с начала, а не прокрученной, как была прежняя.
	if not same:
		_inertia_region = ""
		_scroll.scroll_vertical = 0
		_panel_scroll_f = 0.0


func panel_scroll() -> int:
	return _scroll.scroll_vertical


## Прокрутить карточку на место (когда она уже разложена — через кадр).
func set_panel_scroll(v: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = v
	_panel_scroll_f = float(_scroll.scroll_vertical)


## Обновляет заголовок и строки, не трогая кнопки и переключатели.
## Пока палец листает список — не обновляем (иначе прокрутку сбивает); место прокрутки сохраняем.
func refresh_panel(spec: Dictionary) -> void:
	if _scrolling():
		return
	var keep := _scroll.scroll_vertical
	_set_room_mode(spec)
	_fill_header(spec)
	_fill_rows(spec)
	if _room_mode:
		# Список работников обновляется вместе с текстом (состояние, «работает»/«отдыхает»).
		_build_room_workers(spec["room"])
	_fit_scroll.call_deferred()
	_scroll.set_deferred("scroll_vertical", keep)


func _fit_scroll() -> void:
	var content := _scroll.get_child(0) as Control
	if content == null:
		return
	var h := content.get_combined_minimum_size().y
	# Сколько занимает карточка без прокручиваемой части (заголовок, кнопки, отступы).
	_scroll.custom_minimum_size = Vector2.ZERO
	_mid.custom_minimum_size = Vector2.ZERO
	var overhead := _info_panel.get_combined_minimum_size().y
	# Карточка помещается между верхом (строка ресурсов, подсказка) и нижним меню.
	var avail := size.y - BAR_H - _top_limit() - 4.0
	_scroll.custom_minimum_size = Vector2(0, clampf(h, 0.0, maxf(100.0, avail - overhead)))
	var ph := _info_panel.get_combined_minimum_size().y
	if _room_mode:
		# Карточка комнаты — всегда одного размера: во всю ширину и до верхней строки.
		# Колонки заполняют высоту, лишнее не растягивает их, а обрезается.
		_scroll.custom_minimum_size = Vector2.ZERO
		var over := _info_panel.get_combined_minimum_size().y - _mid.get_combined_minimum_size().y
		_mid.custom_minimum_size = Vector2(0, maxf(220.0, avail - over))
		ph = _info_panel.get_combined_minimum_size().y
	var pw := size.x - SIDE * 2.0
	if _room_mode and not _room_right.visible:
		# Без работников — карточка уже на ширину их колонки, середина не растягивается.
		pw -= float(_room_cols(true)[1]) + 14.0
	_info_panel.size = Vector2(pw if _room_mode else float(PANEL_WIDTH), ph)
	_info_panel.position = Vector2(SIDE, size.y - BAR_H - ph)


## Значок окна по заголовку (если в spec нет "icon").
const HEAD_ICONS := [["Гаврик", "people"], ["Работа", "people"], ["Назначить", "people"], ["Экипаж", "people"],
	["Родословная", "people"], ["Постройк", "room"], ["Тип построек", "room"], ["Сдвинуть", "room"], ["Наука", "flask"],
	["Планет", "planet"], ["Запуск", "rocket"], ["Груз", "room"]]
var _head_icon: IconView
var _head_icon_bg: PanelContainer


func _head_chip(text: String, sb: StyleBox, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 18, col)
	l.add_theme_font_override("font", Fonts.black())
	p.add_child(l)
	return p


func _fill_header(spec: Dictionary) -> void:
	var t: String = spec.get("title", "")
	var glyph: String = spec.get("icon", "")
	if glyph.is_empty():
		for hi in HEAD_ICONS:
			if t.begins_with(hi[0]):
				glyph = hi[1]
				break
	_head_icon_bg.visible = not glyph.is_empty() and not spec.has("room")
	_head_icon.glyph = glyph
	var room: Dictionary = spec.get("room", {})
	var tex_path: String = room.get("tex", "")
	_head_tex.texture = load(tex_path) if not tex_path.is_empty() and ResourceLoader.exists(tex_path) else null
	_head_tex.visible = _head_tex.texture != null
	if not room.is_empty() and _head_tex.texture == null:
		_head_icon_bg.visible = true
		if room.has("glyph"):
			_head_icon.glyph = room["glyph"]
	for c in _head_chips.get_children():
		_head_chips.remove_child(c)
		c.queue_free()
	if not room.is_empty():
		_head_chips.add_child(_head_chip(room.get("size", ""), UiStyle.flat(Color(1, 1, 1, 0.1), 12, 6), Color.WHITE))
		var status: Array = room.get("status", [])
		if not status.is_empty():
			var col: Color = {"bad": RED, "good": GREEN, "warn": ACCENT}.get(status[1], BTN)
			_head_chips.add_child(_head_chip(status[0], btn_box(col), Color.WHITE))
	_head_icon.queue_redraw()
	var acc: Color = spec.get("accent", ACCENT)
	_head_icon_bg.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 14, 4, false, false)
		if acc.is_equal_approx(ACCENT) else UiStyle.tile(acc, false, 14, 4))
	_title.text = spec.get("title", "")
	_desc_btn.visible = false
	_subtitle.text = spec.get("subtitle", "")
	_subtitle.visible = not _subtitle.text.is_empty()
	if not room.is_empty():
		# Размер — плашкой рядом, статус — плашкой: в заголовке и подписи не повторяем.
		_title.text = _title.text.replace(" " + str(room.get("size", "")), "")
		# «Лифт 8 м» — метры тоже в плитках.
		var rx := RegEx.create_from_string(" \\d+ м$")
		_title.text = rx.sub(_title.text, "")
		_subtitle.visible = false
	_subtitle.add_theme_color_override("font_color", spec.get("accent", ACCENT))


## Описание комнаты (справка) — по кнопке «Описание» в шапке.
var _desc_btn: Button
var _room_desc: Array = []
var _room_desc_title := ""
## Готовые разделы описания [заголовок, значок, [строки]] (у гаврика).
var _room_desc_sections: Array = []


## Описание — по разделам, внутри — пунктами по предложению (не сплошной текст).
const DESC_SECTIONS := [["Назначение", "room"], ["Как работает", "build"], ["Свет", "power"], ["Материал стен", "store"]]


func _desc_section(t: String, first: bool) -> String:
	if first:
		return "Назначение"
	if t.begins_with("Свет:"):
		return "Свет"
	if t.contains("подходит для") or t.contains("супер-постройк"):
		return "Материал стен"
	return "Как работает"


## Текст на пункты: по концу предложения, если дальше — заглавная буква или «.
static func _sentences(t: String) -> Array:
	var re := RegEx.create_from_string("(?<=[.!?])\\s+(?=[А-ЯЁA-Z«])")
	var out := []
	var at := 0
	for m in re.search_all(t):
		out.append(t.substr(at, m.get_start() - at).strip_edges())
		at = m.get_end()
	out.append(t.substr(at).strip_edges())
	return out.filter(func(x: String) -> bool: return not x.is_empty())


func _show_room_desc() -> void:
	var v := _overlay(_room_desc_title + " — описание")
	var w := minf(size.x - 160.0, 820.0)
	var groups := {}
	var order := DESC_SECTIONS.duplicate()
	for sd: Array in _room_desc_sections:
		order.append([sd[0], sd[1]])
		groups[sd[0]] = sd[2]
	for i in _room_desc.size():
		var t: String = _room_desc[i]
		var sec := _desc_section(t, i == 0)
		if not groups.has(sec):
			groups[sec] = []
		for line: String in _sentences(t):
			groups[sec].append(line.left(1).to_upper() + line.substr(1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	for sd in order:
		if not groups.has(sd[0]):
			continue
		var sec := VBoxContainer.new()
		sec.add_theme_constant_override("separation", 6)
		box.add_child(sec)
		var hh := HBoxContainer.new()
		hh.add_theme_constant_override("separation", 8)
		sec.add_child(hh)
		hh.add_child(IconView.make("", 22, sd[1], UiStyle.TEAL_A))
		var hl := _label(sd[0], 19, UiStyle.TEAL_A)
		hl.add_theme_font_override("font", Fonts.black())
		hh.add_child(hl)
		for line: String in groups[sd[0]]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			sec.add_child(row)
			var dot := Panel.new()
			dot.add_theme_stylebox_override("panel", UiStyle.flat(Color(ACCENT, 0.9), 4, 0))
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var dw := MarginContainer.new()
			dw.add_theme_constant_override("margin_top", 9)
			dw.add_theme_constant_override("margin_left", 6)
			dw.add_child(dot)
			row.add_child(dw)
			var l := _label(line, 17, Color(0.9, 0.93, 0.96))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(w - 50.0, 0)
			row.add_child(l)
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(box)
	v.add_child(_choice_scroll)
	var sc := _choice_scroll
	var fit := func() -> void:
		if is_instance_valid(sc):
			sc.custom_minimum_size = Vector2(w, minf(box.get_combined_minimum_size().y, size.y - 200.0))
	box.minimum_size_changed.connect(fit)
	fit.call()


# --- Карточка комнаты (широкая, по прототипу) ---------------------------------------------

var _mid: HBoxContainer
var _room_top: VBoxContainer
var _room_right: VBoxContainer
var _workers_head: Label
var _workers_scroll: ScrollContainer
var _workers_list: VBoxContainer
var _preview_frame: PanelContainer
var _preview_mask: Control
var _preview_hole := Rect2()
const PREVIEW_R := 12
## Размер превью комнаты (от ширины левой колонки).
var _pv := Vector2(290, 150)


## Ширины колонок карточки комнаты [слева, справа, середина] — от ширины экрана, не от текста.
func _room_cols(with_right: bool) -> Array:
	var total := size.x - SIDE * 2.0 - 28.0
	var a := clampf(total * 0.27, 300.0, 430.0)
	var c := clampf(total * 0.29, 320.0, 450.0) if with_right else 0.0
	return [a, c, total - a - (c + 14.0 if with_right else 0.0) - 14.0]


func _set_room_mode(spec: Dictionary) -> void:
	_room_mode = spec.has("room")
	var room: Dictionary = spec.get("room", {})
	_room_left.visible = _room_mode
	_room_top.visible = _room_mode
	_head_chips.visible = _room_mode
	_room_right.visible = _room_mode and (int(room.get("slots", 0)) > 0 or not room.get("side_title", "").is_empty())
	var cols := _room_cols(true)
	_pw = (float(cols[2]) - 18.0) if _room_mode else float(PANEL_WIDTH)
	_room_left.custom_minimum_size = Vector2(cols[0], 0)
	_room_right.custom_minimum_size = Vector2(cols[1], 0)
	_pv = Vector2(floorf(cols[0]) - 8.0, floorf(cols[0] * 0.5))
	_subtitle.custom_minimum_size = Vector2(0 if _room_mode else PANEL_WIDTH - 40 - 64 - 66, 0)
	if _preview_vp != null:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _room_mode else SubViewport.UPDATE_DISABLED


## Строки карточки: в карточке комнаты главное — в показатели и колонки, остальное — в середину.
func _fill_rows(spec: Dictionary) -> void:
	var rows: Array = spec.get("rows", [])
	if not _room_mode:
		_fill_body(rows)
		return
	var room: Dictionary = spec["room"]
	var warns := []
	var tiles := []
	var conds := []
	var rest := []
	var desc := []
	if not str(room.get("desc", "")).is_empty():
		desc.append(str(room["desc"]))
	for row: Dictionary in rows:
		var t: String = row.get("type", "text")
		var label: String = row.get("label", "")
		if row.get("super", false) or label == "Найдено":
			continue   # супер-материал — в блоке «Материал стен»; находки в карточке не нужны
		if t == "warning":
			warns.append(row)
		elif t == "progress" and room.get("site", false):
			# Стройка: весь ход работ — плитками (копка, укрепление, стройка).
			tiles.append([{"Копка": "mine", "Укрепление": "repair"}.get(label, "build"), label, row])
		elif t == "text" and not row.get("info", false) and not str(row.get("text", "")).begins_with("Условия: "):
			desc.append(str(row["text"]))   # справка — в окно «Описание»
		elif t == "progress" and label == "Износ":
			tiles.append(["repair", "Износ", row])
		elif t == "progress" and label == "Нагрузка":
			tiles.append(["room", "Нагрузка", row])
		elif t == "progress" and label == "Готовое в ящиках":
			tiles.push_front(["store", "Склад", row])
		elif t == "progress" and not tiles.any(func(x: Array) -> bool: return x[0] == "build"):
			tiles.push_front(["build", {"Производство": "Цикл"}.get(label, label), row])
		elif t == "chips" and not row.has("label") and conds.is_empty():
			conds = row["items"]
		elif t == "text" and str(row.get("text", "")).begins_with("Условия: "):
			for part in str(row["text"]).trim_prefix("Условия: ").split(" · "):
				conds.push_front(["", part])
		else:
			rest.append(row)
	# Свои плитки постройки (у шахт и тоннелей — длина, глубина) — первыми.
	var extra: Array = room.get("tiles", [])
	tiles = extra + tiles
	conds = room.get("conds", []) + conds
	# Материал стен — своим блоком, поэтому из условий его убираем.
	conds = conds.filter(func(it: Array) -> bool: return not str(it[1]).begins_with("стены:"))
	_fill_body(rest)
	if room.has("portrait"):
		# Гаврик: проблемы — под портретом слева, середина — только характеристики.
		_build_room_left(room, conds, warns)
		_build_room_top(room, [], [])
	else:
		_build_room_left(room, conds)
		_build_room_top(room, warns, tiles)
	_room_desc = desc
	_room_desc_title = _title.text
	_room_desc_sections = room.get("desc_sections", [])
	_desc_btn.visible = not desc.is_empty() or not _room_desc_sections.is_empty()


## Панель постоянного размера: содержимое не растягивает её, лишнее обрезается снизу.
func _clip_panel(sb: StyleBox, child: Control, pad := 10.0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.clip_contents = true
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	child.set_anchors_preset(Control.PRESET_TOP_WIDE)
	child.offset_left = pad
	child.offset_right = -pad
	child.offset_top = pad
	return p


## Слева: превью комнаты и под ним условия.
func _build_room_left(room: Dictionary, conds: Array, warns: Array = []) -> void:
	_ensure_preview()
	for c in _room_left.get_children():
		if c != _preview_frame:
			_room_left.remove_child(c)
			c.queue_free()
	if room.has("portrait"):
		# Гаврик: квадратный портрет слева, справа от него — сытость, настроение, здоровье;
		# под ними — проблемы.
		_preview_frame.visible = false
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		_room_left.add_child(top)
		_room_left.move_child(top, 0)
		var pp := PanelContainer.new()
		pp.add_theme_stylebox_override("panel", UiStyle.section(UiStyle.TEAL_A, 14, 4))
		pp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var ps := floorf(_room_left.custom_minimum_size.x * 0.4)
		pp.add_child(PortraitView.make(room["portrait"], ps, ps * 0.6))
		top.add_child(pp)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 6)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_child(nv)
		for n: Dictionary in room.get("needs", []):
			var lh := HBoxContainer.new()
			nv.add_child(lh)
			var ln := _label(n["label"], 16, Color.WHITE)
			ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lh.add_child(ln)
			var lv := _label(n["text"], 16, Color.WHITE)
			lv.add_theme_font_override("font", Fonts.black())
			lh.add_child(lv)
			var bar := BarView.make(float(n["value"]), n["color"], "")
			bar.custom_minimum_size = Vector2(0, 12)
			nv.add_child(bar)
		var at := 1
		for w: Dictionary in warns:
			var wp := PanelContainer.new()
			wp.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 12, 6, false))
			var wh := HBoxContainer.new()
			wh.add_theme_constant_override("separation", 8)
			wp.add_child(wh)
			wh.add_child(IconView.make("", 24, "warning", Color(1, 0.95, 0.4)))
			var wl := _label(w["text"], 14, Color.WHITE)
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.max_lines_visible = 2
			wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			wl.custom_minimum_size = Vector2(_room_left.custom_minimum_size.x - 60.0, 0)
			wh.add_child(wl)
			_room_left.add_child(wp)
			_room_left.move_child(wp, at)
			at += 1
	else:
		_preview_frame.visible = true
	# Превью — по пропорциям комнаты (без пустых полос): во всю ширину колонки, но не выше
	# 0,6 ширины; узкая высокая комната — уже по ширине, по центру.
	var r: Rect2 = room.get("preview", Rect2())
	var colw := _room_left.custom_minimum_size.x
	if room.get("context", false) and r.size.x > 0.0 and r.size.y > 0.0:
		# Шахта, тоннель: превью во всю колонку (вертикальному — выше), вокруг видно породу.
		_pv = Vector2(colw, floorf(colw * (0.6 if r.size.y > r.size.x else 1.0 / 3.0)))
		var want := _pv.x / _pv.y
		if r.size.x / r.size.y < want:
			r = r.grow_individual((r.size.y * want - r.size.x) * 0.5, 0, (r.size.y * want - r.size.x) * 0.5, 0)
		else:
			r = r.grow_individual(0, (r.size.x / want - r.size.y) * 0.5, 0, (r.size.x / want - r.size.y) * 0.5)
	elif r.size.x > 0.0 and r.size.y > 0.0:
		# Высота у всех комнат одна (как у широкой 9×3), ширина — по пропорциям комнаты.
		var asp := r.size.x / r.size.y
		var h := floorf(colw / 3.0)
		_pv = Vector2(minf(colw, floorf(h * asp)), h)
		if _pv.x >= colw - 0.5:
			_pv.y = floorf(colw / asp)
	_preview_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_box.custom_minimum_size = _pv
	_preview_vp.size = Vector2i(_pv)
	_aim_preview(r)
	if conds.is_empty():
		return
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cv.add_child(_label(room.get("conds_title", "Условия в комнате"), 17, Color.WHITE))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	cv.add_child(flow)
	for it in conds:
		# Длинную плашку делим по « · », иначе она шире колонки.
		var parts := str(it[1]).split(" · ") if str(it[1]).length() > 30 else PackedStringArray([str(it[1])])
		for i in parts.size():
			var c: Array = it.duplicate()
			c[0] = it[0] if i == 0 else ""
			c[1] = parts[i]
			flow.add_child(_chip(c, false))
	_room_left.add_child(_clip_panel(_box(Color(1, 1, 1, 0.04), 14, 10), cv))


## Середина сверху: тревога, плитки показателей, материал стен.
func _build_room_top(room: Dictionary, warns: Array, tiles: Array) -> void:
	for c in _room_top.get_children():
		_room_top.remove_child(c)
		c.queue_free()
	# Все проблемы — сразу на виду, оранжевыми плашками.
	for warn: Dictionary in warns:
		var wp := PanelContainer.new()
		wp.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 14, 8, false))
		var wh := HBoxContainer.new()
		wh.add_theme_constant_override("separation", 10)
		wp.add_child(wh)
		wh.add_child(IconView.make("", 30, "warning", Color(1, 0.95, 0.4)))
		var wl := _label(warn["text"], 15, Color.WHITE)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.max_lines_visible = 2
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.custom_minimum_size = Vector2(_pw - 60.0, 0)
		wh.add_child(wl)
		_room_top.add_child(wp)
	if not tiles.is_empty():
		var tr := HBoxContainer.new()
		tr.add_theme_constant_override("separation", 8)
		_room_top.add_child(tr)
		for t in tiles:
			tr.add_child(_room_tile(t[0], t[1], t[2]))
	var mat: String = room.get("material", "")
	if not mat.is_empty():
		_room_top.add_child(_room_material(room))


## Блок «Материал стен»: какой материал и что он даёт (супер-материал — выделен золотом).
func _room_material(room: Dictionary) -> Control:
	var bonus: String = room.get("bonus", "")
	var sb := UiStyle.flat(Color(1, 1, 1, 0.05), 14, 8)
	if not bonus.is_empty():
		sb = UiStyle.flat(Color(0.35, 0.27, 0.05, 0.9), 14, 8)
		sb.border_color = Color(0.95, 0.75, 0.25)
		sb.set_border_width_all(2)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var key: String = room.get("mat_key", "")
	h.add_child(IconView.make(key, 34) if ResIcon.texture(key) != null else IconView.make("", 30, room.get("mat_glyph", "room"), Color(0.75, 0.95, 0.95)))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	h.add_child(tv)
	tv.add_child(_label(room.get("mat_label", "Материал стен"), 14, MUTED))
	var nm := _label(room["material"], 19, Color.WHITE)
	nm.add_theme_font_override("font", Fonts.black())
	tv.add_child(nm)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", -2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(rv)
	if bonus.is_empty():
		var nb := _label(room.get("mat_hint", "без особых свойств"), 15, MUTED)
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nb.clip_text = true
		rv.add_child(nb)
	else:
		var sl := _label("супер-постройка", 14, Color(0.95, 0.78, 0.35))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rv.add_child(sl)
		var bl := _label(bonus, 20, Color(1, 0.88, 0.45))
		bl.add_theme_font_override("font", Fonts.black())
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bl.clip_text = true
		rv.add_child(bl)
	return p


## Плитка показателя: значок, подпись, значение, полоска.
func _room_tile(glyph: String, title: String, row: Dictionary) -> Control:
	var p := PanelContainer.new()
	var full: bool = float(row.get("value", 0.0)) >= 0.999 and title == "Склад"
	p.add_theme_stylebox_override("panel", UiStyle.flat(Color(0.55, 0.18, 0.12, 0.85) if full else Color(1, 1, 1, 0.06), 14, 8))
	# Все плитки одной ширины, текст не растягивает: не влез — обрезается.
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	p.clip_contents = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	h.add_child(IconView.make("", 22, "room" if glyph == "store" else glyph, Color(0.75, 0.95, 0.95)))
	var tl := _label(title, 15, Color.WHITE)
	tl.clip_text = true
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	var val := _label(str(row.get("text", "")).split(" · ")[0].split(" — ")[0], 18, Color.WHITE)
	val.add_theme_font_override("font", Fonts.black())
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.clip_text = true
	v.add_child(val)
	if float(row.get("value", 0.0)) >= 0.0:
		var bar := BarView.make(float(row.get("value", 0.0)), row.get("color", Color(0.3, 0.85, 0.45)), "")
		bar.custom_minimum_size = Vector2(0, 12)
		v.add_child(bar)
	return p


## Живое превью комнаты: тот же мир, своя камера (рисуется, пока открыта карточка).
func _ensure_preview() -> void:
	if _preview_box != null:
		return
	_preview_box = SubViewportContainer.new()
	_preview_box.stretch = true
	_preview_box.custom_minimum_size = Vector2(290, 150)
	_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(290, 150)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_preview_box.add_child(_preview_vp)
	_preview_cam = Camera2D.new()
	_preview_vp.add_child(_preview_cam)
	_preview_cam.make_current()
	# Видна только сама комната, углы скруглены (шейдер), обводка — по тем же скруглённым
	# углам поверх картинки: ничего не торчит из-под рамки.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/round_preview.gdshader")
	_preview_box.material = mat
	_preview_frame = PanelContainer.new()
	_preview_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_frame.add_child(_preview_box)
	_preview_mask = Control.new()
	_preview_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = Color(UiStyle.TEAL_A, 0.85)
	border.set_border_width_all(2)
	border.set_corner_radius_all(PREVIEW_R)
	border.anti_aliasing = true
	_preview_mask.draw.connect(func() -> void:
		_preview_mask.draw_style_box(border, _preview_hole))
	_preview_frame.add_child(_preview_mask)
	_room_left.add_child(_preview_frame)


func _aim_preview(r: Rect2) -> void:
	if room_world != null and _preview_vp.world_2d != room_world:
		_preview_vp.world_2d = room_world
	if r.size.x <= 0.0:
		return
	_preview_cam.position = r.get_center()
	# Комната — на всё превью (с маленьким полем), вокруг — маска.
	var z := minf(_pv.x / r.size.x, _pv.y / r.size.y)
	_preview_cam.zoom = Vector2(z, z)
	var hs := (r.size * z).min(_pv)
	_preview_hole = Rect2((_pv - hs) * 0.5, hs)
	var mat := _preview_box.material as ShaderMaterial
	mat.set_shader_parameter("box_size", _pv)
	mat.set_shader_parameter("hole", Vector4(_preview_hole.position.x, _preview_hole.position.y, _preview_hole.size.x, _preview_hole.size.y))
	mat.set_shader_parameter("radius", float(PREVIEW_R))
	_preview_mask.queue_redraw()


## Правая колонка карточки комнаты: шапка «Работники N / M» и под ней свой список с прокруткой.
func _build_room_right() -> void:
	_room_right = VBoxContainer.new()
	_room_right.add_theme_constant_override("separation", 8)
	_room_right.visible = false
	_mid.add_child(_room_right)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.TEAL_A, UiStyle.TEAL_B, 14, 8))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	head.add_child(hh)
	hh.add_child(IconView.make("", 26, "people", Color.WHITE))
	_workers_head = _label("", 20, Color.WHITE)
	_workers_head.add_theme_font_override("font", Fonts.black())
	hh.add_child(_workers_head)
	_room_right.add_child(head)
	_workers_scroll = ScrollContainer.new()
	_workers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_right.add_child(_workers_scroll)
	_workers_list = VBoxContainer.new()
	_workers_list.add_theme_constant_override("separation", 6)
	_workers_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workers_scroll.add_child(_workers_list)


func _build_room_workers(room: Dictionary) -> void:
	for c in _workers_list.get_children():
		_workers_list.remove_child(c)
		c.queue_free()
	var slots: int = room.get("slots", 0)
	var side: String = room.get("side_title", "")
	if not side.is_empty():
		# Свой список (у гаврика — семья) без свободных мест.
		_workers_head.text = "%s   %d" % [side, room["workers"].size()]
		for w: Dictionary in room["workers"]:
			_workers_list.add_child(_room_worker(w))
		if room["workers"].is_empty():
			var el := _label(room.get("side_empty", "Пока никого."), 17, MUTED)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			el.custom_minimum_size = Vector2(_room_right.custom_minimum_size.x - 10.0, 0)
			_workers_list.add_child(el)
		return
	if slots <= 0:
		return
	_workers_head.text = "Работники   %d / %d" % [room["workers"].size(), slots]
	for w: Dictionary in room["workers"]:
		_workers_list.add_child(_room_worker(w))
	for i in maxi(0, slots - room["workers"].size()):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_stylebox_override("normal", UiStyle.flat(Color(1, 1, 1, 0.04), 12, 6))
		b.add_theme_stylebox_override("hover", UiStyle.flat(Color(1, 1, 1, 0.08), 12, 6))
		b.add_theme_stylebox_override("pressed", UiStyle.flat(Color(1, 1, 1, 0.1), 12, 6))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		h.add_theme_constant_override("separation", 12)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var plus := _label("+", 30, Color(1, 1, 1, 0.8))
		plus.custom_minimum_size = Vector2(46, 0)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(plus)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(_label("Свободно", 18, Color.WHITE))
		tv.add_child(_label("Назначьте гаврика", 14, MUTED))
		var cb: Callable = room.get("assign", Callable())
		if cb.is_valid():
			b.pressed.connect(cb)
		_workers_list.add_child(b)


func _room_worker(w: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_stylebox_override("normal", UiStyle.flat(Color(1, 1, 1, 0.07), 12, 6))
	b.add_theme_stylebox_override("hover", UiStyle.flat(Color(1, 1, 1, 0.1), 12, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.flat(Color(1, 1, 1, 0.12), 12, 6))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(PortraitView.make(w.get("looks", {}), 58, 34))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var nm := _label(w["name"], 19, Color.WHITE)
	nm.add_theme_font_override("font", Fonts.black())
	nm.clip_text = true
	tv.add_child(nm)
	var sub := _label(w.get("sub", ""), 14, MUTED)
	sub.clip_text = true
	tv.add_child(sub)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rv)
	var st := PanelContainer.new()
	var working: bool = w.get("working", false)
	st.add_theme_stylebox_override("panel", UiStyle.flat(Color(0.18, 0.62, 0.3) if working else Color(0.35, 0.42, 0.5), 10, 4))
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl := _label(w.get("state", ""), 14, Color.WHITE)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(sl)
	rv.add_child(st)
	if w.has("pct"):
		var pct := _label("⚡ %d%%" % int(w["pct"]), 16, Color(1, 0.85, 0.35))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rv.add_child(pct)
	var cb: Callable = w.get("open", Callable())
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Карточка комнаты: все кнопки — в один ряд. Не влезают — ужимаем (и шрифт помельче).
func _fit_actions_row() -> void:
	var avail := size.x - SIDE * 2.0 - 28.0
	if _room_mode and not _room_right.visible:
		avail -= float(_room_cols(true)[1]) + 14.0
	var bs := _actions.get_children()
	var sum := 8.0 * maxf(0.0, bs.size() - 1.0)
	for b: Control in bs:
		sum += b.custom_minimum_size.x
	if sum <= avail:
		return
	var k := (avail - 8.0 * (bs.size() - 1)) / (sum - 8.0 * (bs.size() - 1))
	for b: Control in bs:
		b.custom_minimum_size.x = floorf(b.custom_minimum_size.x * k)
		for l in b.find_children("*", "Label", true, false):
			l.add_theme_font_size_override("font_size", 14)


## Кнопка действия карточки: значок по смыслу, цвет — зелёный «Назначить», красный «Снести»…
const ACCENT_DOT := Color(1.0, 0.62, 0.2)
const ACTION_ICONS := [["Изменить", "build"], ["Отменить", "close"], ["Остановить", "close"], ["Пауза", "speed"],
	["Продолжить", "speed"], ["Снять приоритет", "warning"], ["Разобрать завал", "mine"], ["Отправить", "look"], ["Работа", "build"], ["Родословная", "people"], ["Гаврики", "people"], ["Продлить", "bridge"], ["Сверлить", "build"], ["Назначить", "people"], ["Обустроить", "build"], ["Сдвинуть", "bridge"], ["Свет", "power"],
	["Включить свет", "power"], ["Выключить свет", "power"], ["Перестроить", "room"], ["Снести", "close"], ["Ремонт", "repair"],
	["Пауза", "speed"], ["Продолжить", "speed"], ["Приоритет", "warning"], ["Собрать ракету", "rocket"], ["Запустить", "rocket"]]
func _action_button(a: Array) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var text: String = a[0]
	var style: String = a[2] if a.size() > 2 else ""
	if style == "danger" or text == "Снести":
		b.add_theme_stylebox_override("normal", btn_box(RED))
		b.add_theme_stylebox_override("hover", btn_box(RED.lightened(0.08)))
	elif text == "Назначить":
		b.add_theme_stylebox_override("normal", btn_box(GREEN))
		b.add_theme_stylebox_override("hover", btn_box(GREEN.lightened(0.08)))
	elif style == "primary":
		b.add_theme_stylebox_override("normal", btn_box(ACCENT))
		b.add_theme_stylebox_override("hover", btn_box(ACCENT))
	var glyph := ""
	if _room_mode:
		for ai in ACTION_ICONS:
			if text.begins_with(ai[0]):
				glyph = ai[1]
				break
	if glyph.is_empty():
		b.text = text
		return b
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	# Помельче, чтобы все кнопки комнаты встали в один ряд.
	h.add_child(IconView.make("", 22, glyph, Color.WHITE))
	h.add_child(_label(text, 16, Color.WHITE))
	if a.size() > 3 and a[3] == "dot":
		# Есть что улучшить — оранжевая точка на кнопке.
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UiStyle.flat(ACCENT_DOT, 6, 0))
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
	b.custom_minimum_size = Vector2(Fonts.bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 50, 56)
	return b


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
			l.custom_minimum_size = Vector2(_pw - 40, 0)
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
			l.custom_minimum_size = Vector2(_pw - 90, 0)
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
			# Портрет гаврика и плашки рядом (пол, характер, мутации).
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
				l.custom_minimum_size = Vector2(_pw - 220, 0)
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
				l.custom_minimum_size = Vector2(134, 0)
				l.clip_text = true
				cell.add_child(l)
				var v: float = item[1]
				var good: bool = item[2]
				var c := Color(0.45, 0.8, 0.4) if good else Color(0.92, 0.45, 0.3)
				if absf(v - 1.0) < 0.01:
					c = Color(0.55, 0.6, 0.7)
				var bar := BarView.make(v / 2.0, c, "%d%%" % roundi(v * 100.0))
				# Полоска тянется на остаток ячейки (в узкой колонке не распирает карточку).
				bar.custom_minimum_size = Vector2(70, 22)
				bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		"select":
			_build_select(st)
		_:
			_build_stepper(st)


## Ключ на кнопке «Постройки»: что-то требует ремонта.
func set_repair_badge(on: bool) -> void:
	if _objects_btn != null:
		_objects_btn.set_badge("repair" if on else "")


## Выбор из списка: {"type": "select", "label", "text": что выбрано, "pressed": Callable} —
## кнопка «текст ▾», по нажатию открывается окно выбора (обычный выпадающий список на касании
## сразу выбирал пункт под пальцем).
func _build_select(st: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_controls.add_child(row)
	row.add_child(_label(st["label"], 18, Color.WHITE))
	var b := Button.new()
	b.text = "%s  ▾" % st["text"]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(st["pressed"])
	row.add_child(b)


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


## Список гавриков с кнопкой: {"type": "people", "label", "empty"?, "items": [{"looks", "name", "info",
## "button"?, "pick": Callable, "style"?}]} — назначить на работу и т. п.
func _build_people(st: Dictionary) -> void:
	_controls.add_child(_label(st["label"], 16, MUTED))
	if st["items"].is_empty() and st.has("empty"):
		_controls.add_child(_label(st["empty"], 16, MUTED))
	for item in st["items"]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.06), 10, 6))
		_controls.add_child(p)
		# Нажали на гаврика (не на кнопку) — его карточка; при прокрутке не срабатывает.
		if item.has("open"):
			var open: Callable = item["open"]
			var press := {"at": Vector2.INF}
			p.mouse_filter = Control.MOUSE_FILTER_PASS
			p.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
					if ev.pressed:
						press["at"] = ev.global_position
					elif press["at"] != Vector2.INF and ev.global_position.distance_to(press["at"]) < DRAG_DEADZONE:
						press["at"] = Vector2.INF
						open.call())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		p.add_child(row)
		if item.has("looks"):
			row.add_child(PortraitView.make(item["looks"], 56, 28))
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		col.add_child(_label(item["name"], 19, Color.WHITE))
		var info := _label(item.get("info", ""), 15, MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(_pw - 300, 0)
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
		elif item.get("style", "") == "primary":
			b.add_theme_stylebox_override("normal", btn_box(ACCENT))
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
		desc.custom_minimum_size = Vector2(_pw - 220, 0)
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
	var head := _label(st["label"], 16, MUTED)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.add_child(head)
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
		# «?» — где искать этот ресурс.
		var hint := Button.new()
		hint.text = "?"
		hint.focus_mode = Control.FOCUS_NONE
		hint.custom_minimum_size = Vector2(50, 50)
		hint.pressed.connect(func() -> void: show_message(Mat.resource_name(key), ResourceHints.text(key)))
		row.add_child(hint)
		if not on:
			row.add_child(_label("не хранить", 16, MUTED))
			continue
		var cap: int = item["cap"]
		var now := _label("сейчас %s из %s" % [Fmt.int_spaced(item["held"]), Fmt.int_spaced(cap)], 17, Color.WHITE)
		# Переносится, если колонка узкая (карточка комнаты).
		now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		now.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(now)
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
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	return row


func _build_stepper(st: Dictionary) -> void:
	if _room_mode:
		_build_room_stepper(st)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_controls.add_child(row)
	var label := _label(st["label"], 19, Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_stepper_widgets(row, int(st["value"]), int(st["min"]), int(st["max"]), int(st.get("step", 1)),
		st.get("options", []), st["changed"])


## Карточка комнаты: переключатели — маленькими ячейками в один ряд (подпись сверху).
func _build_room_stepper(st: Dictionary) -> void:
	var line: HBoxContainer = null
	for c in _controls.get_children():
		if c.has_meta("steps"):
			line = c
	if line == null:
		line = HBoxContainer.new()
		line.set_meta("steps", true)
		line.add_theme_constant_override("separation", 12)
		_controls.add_child(line)
		_controls.move_child(line, 0)
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	# Ячейка постоянной ширины: «−», значение, «+» рядом, а не по краям середины.
	cell.custom_minimum_size = Vector2(240, 0)
	line.add_child(cell)
	var l := _label(st["label"], 14, MUTED)
	l.clip_text = true
	cell.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	cell.add_child(row)
	_stepper_widgets(row, int(st["value"]), int(st["min"]), int(st["max"]), int(st.get("step", 1)),
		st.get("options", []), st["changed"])
	for c: Control in row.get_children():
		if c is Button:
			c.custom_minimum_size = Vector2(46, 44)
		elif c is Label:
			c.custom_minimum_size = Vector2(0, 0)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.clip_text = true
			c.add_theme_font_size_override("font_size", 18)


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
	# Зажал «−»/«+» — значение бежит само, всё быстрее (см. _hold_tick).
	for b: Button in [minus, plus]:
		b.set_meta("repeat", true)
		_repeat_buttons.append(b)
		b.button_down.connect(func() -> void: _hold_start(b))
		b.button_up.connect(func() -> void: _hold_end())
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
	close_choice()
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
## Прокрутка окна поверх меню (если в нём список).
var _sub_scroll: ScrollContainer
## Последние точки пальца [позиция, мс] — по ним скорость для инерции.
var _drag_samples: Array = []


func _scrolling() -> bool:
	return _press_event != null or not _inertia_region.is_empty()


func _scroll_region_at(pos: Vector2) -> String:
	if _choice != null:
		if is_instance_valid(_choice_scroll) and _choice_scroll.get_global_rect().has_point(pos) \
				and _choice_scroll.get_v_scroll_bar().max_value > _choice_scroll.size.y + 1.0:
			return "choice"
		return ""
	if _tree_panel != null and _tree_panel.visible and _tree_clip.get_global_rect().has_point(pos):
		return "tree"
	# Окно поверх меню (справочник, сохранения, настройки) — выше карточки.
	if _sub.visible and is_instance_valid(_sub_scroll) and _sub_scroll.is_visible_in_tree() \
			and _sub_scroll.get_global_rect().has_point(pos) \
			and _sub_scroll.get_v_scroll_bar().max_value > _sub_scroll.size.y + 1.0:
		return "sub"
	if _info_panel.visible and _room_right.visible and _workers_scroll.get_global_rect().has_point(pos) \
			and _workers_scroll.get_v_scroll_bar().max_value > _workers_scroll.size.y + 1.0:
		return "workers"
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
			_panel_scroll_f = _region_scroll(region).scroll_vertical if _region_scroll(region) != null else 0.0
			var rb := _repeat_button_at(event.position)
			if rb != null:
				_hold_start(rb)
			get_viewport().set_input_as_handled()
		elif _press_event != null:
			var press := _press_event
			_press_event = null
			get_viewport().set_input_as_handled()
			var held := _hold_fired
			_hold_end()
			_hold_fired = false
			if _dragging:
				_drag_vel = _release_velocity()
				_inertia_region = _press_region if _drag_vel.length() > 30.0 else ""
			elif not held:
				_replay_tap.call_deferred(press, event.duplicate())
	elif event is InputEventMouseMotion and _press_event != null:
		get_viewport().set_input_as_handled()
		if not _dragging and (event.position - _press_event.position).length() > DRAG_DEADZONE:
			_dragging = true
			_hold_end()
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


func _region_scroll(region: String) -> ScrollContainer:
	match region:
		"sub":
			return _sub_scroll
		"workers":
			return _workers_scroll
		"choice":
			return _choice_scroll if is_instance_valid(_choice_scroll) else null
		"panel":
			return _scroll
	return null


func _scroll_by(region: String, d: Vector2) -> void:
	if region == "panel" or region == "sub" or region == "workers" or region == "choice":
		var sc := _region_scroll(region)
		if not is_instance_valid(sc):
			return
		_panel_scroll_f = clampf(_panel_scroll_f + d.y, 0.0, maxf(0.0, sc.get_v_scroll_bar().max_value - sc.size.y))
		sc.scroll_vertical = int(_panel_scroll_f)
	elif region == "tree":
		_tree_pan -= d
		_clamp_tree_pan()


## --- Зажатие «−»/«+» ---------------------------------------------------------------------
## Держишь кнопку степпера дольше HOLD_DELAY — она сама нажимается снова и снова, всё чаще.
const HOLD_DELAY := 0.4
var _repeat_buttons: Array[Button] = []
var _hold_btn: Button = null
var _hold_t := 0.0
var _hold_next := 0.0
var _hold_count := 0
## В карточке нажатие откладывается до отпускания (прокрутка пальцем): если кнопку уже
## «назажимали», отпускание её второй раз не нажимает.
var _hold_fired := false


func _hold_start(b: Button) -> void:
	_hold_btn = b
	_hold_t = 0.0
	_hold_next = HOLD_DELAY
	_hold_count = 0
	_hold_fired = false


func _hold_end() -> void:
	_hold_btn = null


## Кнопка-повторялка под точкой (в карточке нажатие перехвачено прокруткой).
func _repeat_button_at(pos: Vector2) -> Button:
	_repeat_buttons = _repeat_buttons.filter(func(b: Button) -> bool: return is_instance_valid(b))
	for b in _repeat_buttons:
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(pos):
			return b
	return null


func _hold_tick(delta: float) -> void:
	if _hold_btn == null:
		return
	if not is_instance_valid(_hold_btn) or not _hold_btn.is_visible_in_tree() or _hold_btn.disabled:
		_hold_btn = null
		return
	_hold_t += delta
	while _hold_t >= _hold_next:
		_hold_count += 1
		_hold_fired = true
		_hold_btn.pressed.emit()
		# Быстрее с каждым шагом: 0,15 с → 0,03 с.
		_hold_next += maxf(0.03, 0.15 - 0.01 * _hold_count)
		if _hold_btn == null or _hold_btn.disabled:
			break


func _process(delta: float) -> void:
	# Лента событий — только когда не открыто ни одно окно: окна она не перекрывает и сама
	# из-под них не торчит.
	if _log != null:
		_log.visible = not (_info_panel.visible or _tree_panel.visible or _build_row.visible or _menu.visible \
			or _sub.visible or _dialog.visible or _choice != null or tool_open() or (_build_info != null and _build_info.visible))
	_hold_tick(delta)
	if _inertia_region.is_empty():
		return
	if _drag_vel.length() < 30.0 or ((_inertia_region == "panel" or _inertia_region == "workers") and not _info_panel.visible) \
			or (_inertia_region == "sub" and not _sub.visible) \
			or (_inertia_region == "choice" and _choice == null) \
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
var _tree_icon: IconView
var _tree_sub: Label
var _tree_rows: VBoxContainer
var _tree_clip: Control
var _tree_canvas: TreeCanvas
var _tree_detail: VBoxContainer
var _tree_pan := Vector2.ZERO
var _tree_items: Array = []
var _tree_selected := ""


# --- Родословная деревом -----------------------------------------------------------------
## Снизу — сам гаврик, над ним родители, выше их родители… От родителя к ребёнку — стрелка
## (от мамы — розовая, от папы — голубая). Карточка: портрет (виден цвет и мутации), рамка
## цвета гаврика, имя, цвет словами, мутации, жив ли. Дерево двигают пальцем, как науку.
const FAM_W := 262.0
const FAM_H := 118.0
const FAM_GAP_X := 18.0
const FAM_GAP_Y := 40.0
var _family := false


## {"title", "subtitle", "actions": [[подпись, Callable, стиль?]], "nodes": [{"g" поколение (0 —
## сам), "i" место в поколении (мама i*2, папа i*2+1 у ребёнка i), "name", "lines": [строки],
## "color": Color?, "color_word", "looks"?, "dim", "pick": Callable?}]}.
func show_family_tree(spec: Dictionary) -> void:
	_menu.visible = false
	_sub.visible = false
	_info_panel.visible = false
	_family = true
	_tree_sig = ""
	_tree_panel.visible = true
	_tree_detail.visible = false
	_tree_title.text = spec.get("title", "")
	_tree_icon.glyph = "people" if _tree_title.text.begins_with("Родословная") else "flask"
	_tree_icon.queue_redraw()
	_tree_sub.text = spec.get("subtitle", "")
	for c in _tree_rows.get_children():
		_tree_rows.remove_child(c)
		c.queue_free()
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	for a in spec.get("actions", []):
		var b := Button.new()
		b.text = a[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 18)
		var col := ACCENT if a.size() > 2 and a[2] == "primary" else Color(0.36, 0.4, 0.5)
		b.add_theme_stylebox_override("normal", btn_box(col))
		b.add_theme_stylebox_override("hover", btn_box(col))
		b.add_theme_stylebox_override("pressed", btn_box(col, true))
		var cb: Callable = a[1]
		b.pressed.connect(func() -> void: cb.call())
		acts.add_child(b)
	# Масштаб: всё дерево целиком — «−», крупнее — «+».
	for z in [["−", 0.8], ["+", 1.25]]:
		var zb := Button.new()
		zb.text = z[0]
		zb.focus_mode = Control.FOCUS_NONE
		zb.custom_minimum_size = Vector2(60, 52)
		zb.add_theme_font_size_override("font_size", 24)
		zb.add_theme_stylebox_override("normal", btn_box(Color(0.36, 0.4, 0.5)))
		zb.add_theme_stylebox_override("pressed", btn_box(Color(0.36, 0.4, 0.5), true))
		var f: float = z[1]
		zb.pressed.connect(func() -> void: _zoom_family(f))
		acts.add_child(zb)
	_tree_rows.add_child(acts)
	for c in _tree_canvas.get_children():
		_tree_canvas.remove_child(c)
		c.queue_free()
	_tree_canvas.edges = []
	_tree_canvas.lines = []
	_tree_canvas.bands = []
	var nodes: Array = spec.get("nodes", [])
	var top := 0
	var have := {}
	for n in nodes:
		top = maxi(top, int(n["g"]))
		have[Vector2i(n["g"], n["i"])] = true
	# Плотная раскладка: у кого нет известных родителей — следующее свободное место в ряду
	# «листьев», ребёнок — посередине между родителями (пустых мест под неизвестных нет).
	var slot_x := {}
	var next_slot := [0]
	var place := func(k: Vector2i, self_ref: Callable) -> float:
		var xs: Array[float] = []
		for side in 2:
			var pk := Vector2i(k.x + 1, k.y * 2 + side)
			if have.has(pk):
				xs.append(self_ref.call(pk, self_ref))
		var x: float
		if xs.is_empty():
			x = float(next_slot[0])
			next_slot[0] += 1
		else:
			x = (xs[0] + xs[xs.size() - 1]) * 0.5
		slot_x[k] = x
		return x
	place.call(Vector2i(0, 0), place)
	var width := maxf(1.0, float(next_slot[0])) * (FAM_W + FAM_GAP_X) - FAM_GAP_X
	var pos := {}
	for n in nodes:
		var k := Vector2i(n["g"], n["i"])
		pos[k] = Vector2(float(slot_x.get(k, 0.0)) * (FAM_W + FAM_GAP_X), (top - int(n["g"])) * (FAM_H + FAM_GAP_Y))
	var arrows := []
	for n in nodes:
		var g: int = n["g"]
		var i: int = n["i"]
		if g == 0:
			continue
		var child := Vector2i(g - 1, i >> 1)
		if not pos.has(child):
			continue
		var a: Vector2 = pos[Vector2i(g, i)] + Vector2(FAM_W * 0.5, FAM_H)
		var b: Vector2 = pos[child] + Vector2(FAM_W * 0.5, 0)
		arrows.append([a, b, Color(1.0, 0.6, 0.78) if i % 2 == 0 else Color(0.5, 0.72, 1.0)])
	_tree_canvas.arrows = arrows
	for n in nodes:
		_tree_canvas.add_child(_family_card(n, pos[Vector2i(n["g"], n["i"])]))
	_tree_canvas.custom_minimum_size = Vector2(width, (top + 1) * (FAM_H + FAM_GAP_Y) - FAM_GAP_Y)
	_tree_canvas.size = _tree_canvas.custom_minimum_size
	_tree_canvas.queue_redraw()
	_layout_tree_panel()
	# В натуральную величину: внизу сам гаврик, над ним родители, бабушки и дедушки; кто выше —
	# листают вверх или уменьшают масштаб «−».
	var view := _family_view()
	# Масштаб — чтобы влезли все до бабушек и дедушек (по ширине и высоте), не крупнее 1.
	var x0 := INF
	var x1 := -INF
	for k in pos:
		if k.x <= 2:
			x0 = minf(x0, pos[k].x)
			x1 = maxf(x1, pos[k].x + FAM_W)
	var rows := mini(top, 2) + 1
	var sc := minf(1.0, minf(view.x / maxf(1.0, x1 - x0 + 20.0), (view.y - 12.0) / (rows * (FAM_H + FAM_GAP_Y) - FAM_GAP_Y)))
	sc = maxf(sc, 0.35)
	_tree_canvas.scale = Vector2(sc, sc)
	# Ряд бабушек и дедушек — у верхнего края (а при малом дереве — всё дерево у нижнего).
	var y := view.y - _tree_canvas.size.y * sc - 10.0
	if top >= 2:
		y = 6.0 - (top - 2) * (FAM_H + FAM_GAP_Y) * sc
	_tree_pan = Vector2(view.x * 0.5 - (x0 + x1) * 0.5 * sc, y)
	_clamp_tree_pan()


func _family_view() -> Vector2:
	var view := _tree_clip.size
	if view.x < 10.0:
		view = Vector2(size.x - SIDE * 2.0 - 30.0, size.y - BAR_H - 200.0)
	return view


## Масштаб дерева родословной вокруг середины видимого.
func _zoom_family(f: float) -> void:
	var view := _family_view()
	var old := _tree_canvas.scale.x
	var sc := clampf(old * f, 0.2, 1.4)
	var mid := view * 0.5
	var at := (mid - _tree_pan) / old
	_tree_canvas.scale = Vector2(sc, sc)
	_tree_pan = mid - at * sc
	_clamp_tree_pan()


func _family_card(n: Dictionary, p: Vector2) -> Control:
	var card := PanelContainer.new()
	card.position = p
	card.size = Vector2(FAM_W, FAM_H)
	card.custom_minimum_size = card.size
	var border: Color = n.get("color", Color(0.45, 0.42, 0.45))
	var sb := _box_plain(Color(0.16, 0.2, 0.32), 12, 7)
	sb.border_color = border
	sb.set_border_width_all(5 if int(n["g"]) == 0 else 4)
	card.add_theme_stylebox_override("panel", sb)
	if n.get("dim", false):
		card.modulate = Color(1, 1, 1, 0.78)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	if n.has("looks"):
		row.add_child(PortraitView.make(n["looks"], 84, 42))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	# Цвет виден по портрету и рамке — словами не пишем. Умерший — значок гроба у имени.
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 6)
	nr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nr)
	var name := _label(n.get("name", ""), 16, Color.WHITE)
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(name)
	if n.get("dead", false):
		var coffin := CoffinIcon.new()
		coffin.custom_minimum_size = Vector2(20, 28)
		coffin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nr.add_child(coffin)
	for line in n.get("lines", []):
		var l := _label(str(line), 13, MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(FAM_W - 118.0 if n.has("looks") else FAM_W - 30.0, 0)
		col.add_child(l)
	for c in [card, row, col]:
		for k in c.get_children():
			if k is Control:
				(k as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n.has("pick"):
		var pick: Callable = n["pick"]
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				pick.call())
	return card


## Гроб: шестиугольник тёмного дерева с крестом.
class CoffinIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w * 0.3, 0), Vector2(w * 0.7, 0), Vector2(w, h * 0.28),
			Vector2(w * 0.78, h), Vector2(w * 0.22, h), Vector2(0, h * 0.28)])
		draw_colored_polygon(pts, Color(0.42, 0.27, 0.16))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.2, 0.12, 0.07), 1.5)
		var cx := w * 0.5
		draw_line(Vector2(cx, h * 0.18), Vector2(cx, h * 0.72), Color(0.92, 0.85, 0.6), 2.0)
		draw_line(Vector2(cx - w * 0.22, h * 0.36), Vector2(cx + w * 0.22, h * 0.36), Color(0.92, 0.85, 0.6), 2.0)


class TreeCanvas extends Control:
	## [[от, до, цвет]] — стрелки родословной (сверху вниз, от родителя к ребёнку).
	var arrows: Array = []
	## [[от, до, цвет]] в координатах холста (старое дерево без раскладки — плавные «S»).
	var edges: Array = []
	## [[точки ломаной, цвет]] — связи по раскладке веток.
	var lines: Array = []
	## [[Rect2, цвет, название]] — полосы веток.
	var bands: Array = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for b in bands:
			var r: Rect2 = b[0]
			var col: Color = b[1]
			draw_rect(r, Color(col, 0.13))
			draw_rect(Rect2(r.position, Vector2(5, r.size.y)), col)
			# Название ветки — вертикально у левого края полосы.
			var name: String = b[2]
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_set_transform(Vector2(r.position.x + 30, r.position.y + r.size.y * 0.5 + w * 0.5), -PI * 0.5)
			draw_string(font, Vector2.ZERO, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			draw_set_transform(Vector2.ZERO)
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
		for ar in arrows:
			var a: Vector2 = ar[0]
			var b: Vector2 = ar[1]
			var col: Color = ar[2]
			var mid := (a.y + b.y) * 0.5
			var pts := PackedVector2Array()
			for i in 17:
				pts.append(a.bezier_interpolate(Vector2(a.x, mid), Vector2(b.x, mid), b - Vector2(0, 12), i / 16.0))
			draw_polyline(pts, col, 4.0, true)
			draw_colored_polygon(PackedVector2Array([b, b + Vector2(-10, -14), b + Vector2(10, -14)]), col)
		for l in lines:
			var pts: PackedVector2Array = l[0]
			var col: Color = l[1]
			draw_polyline(pts, col, 3.0, true)
			var tip := pts[pts.size() - 1]
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-10, -7), tip + Vector2(-10, 7)]), col)


func _build_tree_panel() -> void:
	_tree_panel = PanelContainer.new()
	_tree_panel.visible = false
	# Непрозрачный фон — карта под деревом не мешает читать.
	var bg := _win(22, 14, 1.0)
	_tree_panel.add_theme_stylebox_override("panel", bg)
	add_child(_tree_panel)
	_tree_panel.visibility_changed.connect(func() -> void:
		if _log != null:
			_log.visible = not _tree_panel.visible and not _info_panel.visible)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_tree_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 14, 4, false, false))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ib)
	_tree_icon = IconView.make("", 38, "flask", Color.WHITE)
	ib.add_child(_tree_icon)
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
	_family = false
	_tree_canvas.scale = Vector2.ONE
	_tree_detail.visible = true
	_menu.visible = false
	_sub.visible = false
	_info_panel.visible = false
	var first := not _tree_panel.visible
	_tree_panel.visible = true
	_fill_tree(spec)
	_layout_tree_panel()
	if first:
		_focus_tree.call_deferred()


func refresh_tech_tree(spec: Dictionary) -> void:
	if _scrolling() or not _tree_panel.visible or _family:
		return
	_fill_tree(spec)


func _layout_tree_panel() -> void:
	# Поверх строки ресурсов: на экране науки она не нужна, а место дереву нужно.
	var top := EDGE_TOP
	_tree_panel.position = Vector2(SIDE, top)
	_tree_panel.size = Vector2(size.x - SIDE * 2.0, size.y - BAR_H - top - 4.0)


func _fill_tree(spec: Dictionary) -> void:
	_tree_title.text = spec.get("title", "")
	_tree_icon.glyph = "people" if _tree_title.text.begins_with("Родословная") else "flask"
	_tree_icon.queue_redraw()
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
	_tree_canvas.lines = []
	_tree_canvas.bands = []
	_tree_canvas.arrows = []
	if not _tree_items.is_empty() and _tree_items[0].has("row"):
		_build_branch_tree(by_id)
		return
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


## Ветки — полосы сверху вниз; у узла своя клетка (ряд, колонка) из Research. Связи — ломаными
## по промежуткам между узлами: из узла вправо, вниз или вверх в промежутке, в узел слева.
const BAND_PAD := 40.0
const BRANCH_COLORS := {"Наука": Color(0.43, 0.7, 1.0), "Транспорт": Color(0.47, 0.8, 0.51),
	"Добыча": Color(0.84, 0.47, 0.35), "Строительство": Color(0.96, 0.65, 0.16)}


func _build_branch_tree(by_id: Dictionary) -> void:
	var pos := {}
	var cells := {}
	var max_c := 0
	var max_r := 0
	var band_rows := {}
	for it in _tree_items:
		var r: int = it["row"]
		var c: int = it["col"]
		pos[it["id"]] = Vector2(BAND_PAD + c * (NODE_W + COL_GAP), r * (NODE_H + ROW_GAP * 2.0))
		cells[Vector2i(r, c)] = it["id"]
		max_c = maxi(max_c, c)
		max_r = maxi(max_r, r)
		var br: String = it["branch"]
		var span: Vector2i = band_rows.get(br, Vector2i(r, r))
		band_rows[br] = Vector2i(mini(span.x, r), maxi(span.y, r))
	var width := BAND_PAD + (max_c + 1) * (NODE_W + COL_GAP)
	for br in band_rows:
		var span: Vector2i = band_rows[br]
		var top := span.x * (NODE_H + ROW_GAP * 2.0) - ROW_GAP * 0.8
		var bottom := span.y * (NODE_H + ROW_GAP * 2.0) + NODE_H + ROW_GAP * 0.8
		_tree_canvas.bands.append([Rect2(0, top, width, bottom - top), BRANCH_COLORS.get(br, MUTED), br])
	var lanes := {}
	for it in _tree_items:
		var needs: Array = it["needs"]
		for k in needs.size():
			var n: String = needs[k]
			if not pos.has(n):
				continue
			var a: Dictionary = by_id[n]
			var src: Vector2 = pos[n] + Vector2(NODE_W, NODE_H * 0.5)
			var dst: Vector2 = pos[it["id"]] + Vector2(0, NODE_H * 0.5 + (0.0 if needs.size() == 1 else (-12.0 if k == 0 else 12.0)))
			var col: Color = BRANCH_COLORS.get(a["branch"], MUTED)
			col = Color(col, 0.95 if a["state"] == "done" else 0.5)
			if not _tree_selected.is_empty() and (it["id"] == _tree_selected or n == _tree_selected):
				col = ACCENT
			var pts := PackedVector2Array()
			if a["row"] == it["row"] and needs.size() == 1:
				pts = PackedVector2Array([src, dst])
			else:
				# Ряд источника между узлами занят — поворачиваем сразу за источником.
				var blocked := false
				for c in range(int(a["col"]) + 1, int(it["col"])):
					if cells.has(Vector2i(a["row"], c)):
						blocked = true
				var g := (src.x + COL_GAP * 0.5) if blocked else (dst.x - COL_GAP * 0.5)
				g += _lane(lanes, roundi(g), src.y, dst.y, n)
				pts = PackedVector2Array([src, Vector2(g, src.y), Vector2(g, dst.y), dst])
			_tree_canvas.lines.append([pts, col])
	for it in _tree_items:
		_tree_canvas.add_child(_tree_node(it, pos[it["id"]]))
	_tree_canvas.custom_minimum_size = Vector2(width, (max_r + 1) * (NODE_H + ROW_GAP * 2.0))
	_tree_canvas.size = _tree_canvas.custom_minimum_size
	_tree_canvas.queue_redraw()
	_clamp_tree_pan()
	_fill_tree_detail()


## Сдвиг вертикали в промежутке, чтобы связи разных узлов не сливались.
static func _lane(lanes: Dictionary, g: int, y1: float, y2: float, src: String) -> float:
	var lo := minf(y1, y2)
	var hi := maxf(y1, y2)
	for o in [0.0, -10.0, 10.0, -20.0, 20.0]:
		var ok := true
		for e in lanes.get(g, []):
			if e[3] == o and e[2] != src and not (hi < e[0] - 4.0 or lo > e[1] + 4.0):
				ok = false
				break
		if ok:
			var l: Array = lanes.get(g, [])
			l.append([lo, hi, src, o])
			lanes[g] = l
			return o
	return 0.0


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
	var spent: int = it.get("spent", 0)
	b.text = "%s\n%s" % [it["name"], ("на паузе %d / %d" % [spent, it["cost"]]) if spent > 0 and it["state"] != "current" else "%d очков" % it["cost"]]
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
	var sb := _box_plain(bg, 12, 8)
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
		var hint := _label("Нажмите на исследование, чтобы прочитать и начать.\n\nЛистайте дерево пальцем: левее — основы, правее — то, что открывается после них.\n\nЗелёное — изучено, синее — изучается, с оранжевой рамкой — можно начать. Переключились на другое — начатое ставится на паузу, очки не пропадают.", 16, MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(320, 0)
		_tree_detail.add_child(hint)
		return
	var head := "%s · %d очков" % [sel["name"], sel["cost"]]
	if sel.has("branch"):
		head = "%s\n%s" % [head, sel["branch"]]
	var t := _label(head, 20, Color.WHITE)
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
			var spent: int = sel.get("spent", 0)
			b.text = ("Продолжить (%d / %d)" % [spent, sel["cost"]]) if spent > 0 else "Изучать"
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
	var cs := _tree_canvas.size * _tree_canvas.scale
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
	var dt := _window_title("")
	_dialog_title = dt.get_child(0)
	v.add_child(dt)
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
	v.add_child(_window_title("Меню"))
	var resume := _menu_button(v, "Продолжить")
	resume.pressed.connect(func() -> void: _menu.visible = false)
	var save := _menu_button(v, "Сохранить")
	save.pressed.connect(_open_save)
	_menu_load = _menu_button(v, "Загрузить")
	_menu_load.pressed.connect(_open_load)
	var settings := _menu_button(v, "Настройки")
	settings.pressed.connect(_open_settings)
	var res_help := _menu_button(v, "Ресурсы: где искать")
	res_help.pressed.connect(func() -> void: _open_resources(false))
	var export := _menu_button(v, "Сохранение в файл")
	export.pressed.connect(func() -> void:
		_menu.visible = false
		export_pressed.emit())
	var quit := _menu_button(v, "Выйти в меню")
	quit.pressed.connect(_ask_exit)
	_sub = PanelContainer.new()
	_sub.visible = false
	_sub.custom_minimum_size = Vector2(640, 0)
	center.add_child(_sub)
	_sub_box = VBoxContainer.new()
	_sub_box.add_theme_constant_override("separation", 12)
	_sub.add_child(_sub_box)


## Окно поверх меню: заголовок, содержимое (с прокруткой) и кнопки внизу.
func _open_sub(title: String, body: Control, buttons: Array) -> void:
	for c in _sub_box.get_children():
		_sub_box.remove_child(c)
		c.queue_free()
	_sub_box.add_child(_window_title(title))
	if body != null:
		var sc := ScrollContainer.new()
		# Высота — по содержимому (короткий вопрос — без пустого места), не выше 340.
		var cap := minf(340.0, size.y - 250.0)
		sc.custom_minimum_size = Vector2(0, minf(cap, body.get_combined_minimum_size().y))
		body.minimum_size_changed.connect(func() -> void:
			if is_instance_valid(sc) and is_instance_valid(body):
				sc.custom_minimum_size.y = minf(cap, body.get_combined_minimum_size().y))
		# Листается пальцем так же, как карточка (см. _input).
		_sub_scroll = sc
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(body)
		_sub_box.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sub_box.add_child(row)
	for bt in buttons:
		var b := _menu_button(row, bt[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bt.size() > 2:
			b.add_theme_stylebox_override("normal", btn_box(bt[2]))
		b.pressed.connect(bt[1])
	_menu.visible = false
	_sub.visible = true


func _back_to_menu() -> void:
	_sub.visible = false
	_menu.visible = true


## «Сохранить»: название и новый слот или перезапись своего (как в других играх).
func _open_save() -> void:
	if world_id.is_empty():
		_menu.visible = false
		save_requested.emit("", "")
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(_label("Название", 18, MUTED))
	var edit := LineEdit.new()
	edit.text = Worlds.new_save_id(world_id)[1]
	edit.max_length = 40
	edit.select_all_on_focus = true
	edit.custom_minimum_size = Vector2(0, 58)
	edit.add_theme_font_size_override("font_size", 22)
	body.add_child(edit)
	var fresh := _menu_button(body, "Новое сохранение")
	fresh.add_theme_stylebox_override("normal", btn_box(GREEN))
	var done := func(sid: String, name: String) -> void:
		_sub.visible = false
		edit.release_focus()
		save_requested.emit(sid, name)
	fresh.pressed.connect(func() -> void: done.call("", edit.text.strip_edges()))
	var hint := _label("Или перезаписать своё (название — из поля, если его меняли):", 16, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	body.add_child(hint)
	var sv := SavesView.new()
	sv.save_mode = true
	sv.show_world(world_id)
	var start_name := edit.text
	sv.slot_chosen.connect(func(sid: String, old_name: String) -> void:
		var typed := edit.text.strip_edges()
		done.call(sid, typed if not typed.is_empty() and typed != start_name else old_name))
	body.add_child(sv)
	_open_sub("Сохранить", body, [["Назад", _back_to_menu]])


func _open_load() -> void:
	var sv := SavesView.new()
	sv.show_world(world_id)
	sv.load_requested.connect(func(sid: String) -> void:
		_sub.visible = false
		load_requested.emit(sid))
	_open_sub("Загрузить", sv, [["Назад", _back_to_menu]])
	var warn := _label("Несохранённый прогресс пропадёт — сначала «Сохранить», если он нужен.", 16, MUTED)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(600, 0)
	_sub_box.add_child(warn)
	_sub_box.move_child(warn, 1)


## Справочник ресурсов: все ресурсы игры; нажали — под ним подсказка, где искать.
## standalone — открыт с верхней панели (закрывается целиком), иначе — из меню.
var _last_inventory := {}
var _sub_standalone := false


## Вопрос «Продолжить?» поверх игры: да — on_yes, иначе ничего.
func ask(title: String, text: String, yes_label: String, on_yes: Callable) -> void:
	var l := _label(text, 20, Color(0.9, 0.92, 0.96))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	var close := func() -> void:
		_sub_standalone = false
		_sub.visible = false
	_open_sub(title, l, [[yes_label, func() -> void:
		close.call()
		on_yes.call(), GREEN], ["Отмена", close]])
	_sub_standalone = true


func _open_resources(standalone: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for key: String in ResourceHints.keys():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var name := _label(Mat.resource_name(key), 19, Color.WHITE)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var have := int(_last_inventory.get(key, 0))
		for c: Control in [IconView.make(key, 30), name, _label("есть %s" % Fmt.int_spaced(have) if have > 0 else "", 17, MUTED)]:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(c)
		box.add_child(b)
		var hint := _label(ResourceHints.text(key), 17, Color(0.9, 0.92, 0.96))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(560, 0)
		hint.visible = false
		box.add_child(hint)
		b.pressed.connect(func() -> void: hint.visible = not hint.visible)
	_sub_standalone = standalone
	var close := func() -> void:
		_sub_standalone = false
		_sub.visible = false
	_open_sub("Ресурсы: где искать", box, [["Закрыть", close]] if standalone else [["Назад", _back_to_menu]])


func _open_settings() -> void:
	var box := VBoxContainer.new()
	var sv := SettingsView.new()
	sv.changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))
	box.add_child(sv)
	var st := _label("3D-модель: %s." % ModelSprites.status, 15, MUTED)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(SettingsView.HINT_W, 0)
	box.add_child(st)
	_open_sub("Настройки", box, [["Назад", _back_to_menu]])


## Выйти в главное меню: с сохранением при выходе — сразу, без него — спросить.
func _ask_exit() -> void:
	if bool(Settings.get_value("save_on_exit")):
		_menu.visible = false
		exit_requested.emit(true)
		return
	var text := _label("Сохранение при выходе выключено. Сохранить игру перед выходом?", 20, Color(0.9, 0.92, 0.96))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(600, 0)
	_open_sub("Выйти в меню", null, [
		["Сохранить и выйти", func() -> void:
			_sub.visible = false
			exit_requested.emit(true), GREEN],
		["Без сохранения", func() -> void:
			_sub.visible = false
			exit_requested.emit(false), RED],
		["Отмена", _back_to_menu]])
	_sub_box.add_child(text)
	_sub_box.move_child(text, 1)


## «Назад» на телефоне: закрыть верхнее окно, а если ничего не открыто — открыть меню.
func back_pressed() -> void:
	# «Назад» меню не открывает (меню — только кнопкой): закрывает открытое меню, иначе
	# игра сворачивается.
	if _sub.visible and _sub_standalone:
		_sub_standalone = false
		_sub.visible = false
	elif _sub.visible:
		_back_to_menu()
	elif _menu.visible:
		_menu.visible = false
	else:
		AppWindow.minimize()


## Открыто меню игры — время стоит.
func menu_open() -> bool:
	return _menu.visible or _sub.visible


## Значки кнопок меню и окон из него.
const MENU_ICONS := {"Продолжить": "speed", "Сохранить": "check", "Загрузить": "menu", "Настройки": "build",
	"Ресурсы: где искать": "look", "Сохранение в файл": "room", "Выйти в меню": "close", "Назад": "close",
	"Отмена": "close", "Новое сохранение": "check", "Отлично": "check"}


## Кнопка меню: значок слева от текста (если есть), текст по центру.
func _menu_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 60)
	b.focus_mode = Control.FOCUS_NONE
	var glyph: String = MENU_ICONS.get(text, "")
	if glyph.is_empty():
		b.text = text
	else:
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		h.add_child(IconView.make("", 24, glyph, Color.WHITE))
		var l := _label(text, 20, Color.WHITE)
		h.add_child(l)
		b.set_meta("label", l)
	parent.add_child(b)
	return b


## Заголовок окна (меню, сохранения, сообщение): крупные буквы и оранжевая черта под ними.
func _window_title(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var t := _label(text, 26, Color.WHITE)
	t.add_theme_font_override("font", Fonts.black())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var line := ColorRect.new()
	line.color = UiStyle.ORANGE_A
	line.custom_minimum_size = Vector2(56, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(line)
	return box


# --- Мини-окно выбора (назначение комнаты, материал стен) ---------------------------------
var _choice: Control
var _choice_scroll: ScrollContainer


## Окно выбора поверх карточки: плитки вариантов. options: [{"text", "icon"? (ключ ресурса),
## "tex"? (картинка), "sub"? (строка под названием), "cost"? ([ключ, есть, нужно, хватает]),
## "error"? (почему нельзя — красным), "current"? (выбрано сейчас)}]. Нажал — on_pick(номер).
func show_choice(title: String, options: Array, on_pick: Callable) -> void:
	var v := _overlay(title)
	var cell_w := CHOICE_W
	var cols := clampi(int((size.x - 160.0) / (cell_w + 10.0)), 2, 5)
	cols = mini(cols, maxi(1, options.size()))
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(grid)
	v.add_child(_choice_scroll)
	for i in options.size():
		grid.add_child(_choice_option(options[i], cell_w, func() -> void:
			close_choice()
			on_pick.call(i)))
	# Высота — по содержимому (перенос текста считается не сразу — следим), но не выше
	# экрана: дальше — прокрутка.
	var sc := _choice_scroll
	var fit := func() -> void:
		if is_instance_valid(sc):
			sc.custom_minimum_size = Vector2(cols * cell_w + (cols - 1) * 10.0,
				minf(grid.get_combined_minimum_size().y, size.y - 190.0))
	grid.minimum_size_changed.connect(fit)
	fit.call()


## Окно с вкладками («Изменить»: назначение, стены, улучшения). tabs: [{"name", "hint",
## "options" (как у show_choice), "on_pick": Callable(номер), "wide": карточки шире, с описанием}].
var _tabs: Array = []
var _tabs_bar: HBoxContainer
var _tabs_hint: Label
var _tabs_grid: GridContainer


func show_tabs(title: String, tabs: Array, start := 0) -> void:
	_tabs = tabs
	var v := _overlay(title)
	_tabs_bar = HBoxContainer.new()
	_tabs_bar.add_theme_constant_override("separation", 8)
	v.add_child(_tabs_bar)
	_tabs_hint = _label("", 16, MUTED)
	_tabs_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tabs_hint)
	_tabs_grid = GridContainer.new()
	_tabs_grid.add_theme_constant_override("h_separation", 10)
	_tabs_grid.add_theme_constant_override("v_separation", 10)
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(_tabs_grid)
	v.add_child(_choice_scroll)
	var sc := _choice_scroll
	var grid := _tabs_grid
	grid.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(sc):
			sc.custom_minimum_size.y = minf(grid.get_combined_minimum_size().y, size.y - 260.0))
	_tabs_open(clampi(start, 0, tabs.size() - 1))


func _tabs_open(ti: int) -> void:
	var w := minf(size.x - 160.0, 5.0 * (CHOICE_W + 10.0) - 10.0)
	for c in _tabs_bar.get_children():
		_tabs_bar.remove_child(c)
		c.queue_free()
	for i in _tabs.size():
		var b := Button.new()
		b.text = _tabs[i]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 48)
		b.add_theme_font_size_override("font_size", 19)
		var on := i == ti
		b.add_theme_stylebox_override("normal", btn_box(ACCENT) if on else UiStyle.flat(Color(1, 1, 1, 0.08), 12, 8))
		b.add_theme_stylebox_override("hover", btn_box(ACCENT) if on else UiStyle.flat(Color(1, 1, 1, 0.13), 12, 8))
		b.add_theme_stylebox_override("pressed", btn_box(ACCENT))
		var k := i
		b.pressed.connect(func() -> void: _tabs_open(k))
		_tabs_bar.add_child(b)
	var tab: Dictionary = _tabs[ti]
	_tabs_hint.text = tab.get("hint", "")
	_tabs_hint.custom_minimum_size = Vector2(w, 0)
	_tabs_hint.visible = not _tabs_hint.text.is_empty()
	for c in _tabs_grid.get_children():
		_tabs_grid.remove_child(c)
		c.queue_free()
	var wide: bool = tab.get("wide", false)
	var cw := (w - 10.0) * 0.5 if wide else CHOICE_W
	var cols := maxi(1, int((w + 10.0) / (cw + 10.0)))
	_tabs_grid.columns = cols
	var opts: Array = tab["options"]
	var pick: Callable = tab["on_pick"]
	for i in opts.size():
		var k := i
		_tabs_grid.add_child(_choice_option(opts[i], cw, func() -> void:
			close_choice()
			pick.call(k), CHOICE_H + (60.0 if wide else 0.0)))
	if opts.is_empty():
		_tabs_grid.add_child(_label(tab.get("empty", "Здесь пока нечего выбрать."), 17, MUTED))
	_choice_scroll.custom_minimum_size = Vector2(w, minf(_tabs_grid.get_combined_minimum_size().y, size.y - 260.0))
	_choice_scroll.scroll_vertical = 0


# --- Окно-список («Гаврики», «Постройки»): вкладки сверху, ряды карточек двумя столбцами ---
var _list_spec := {}
var _list_tab := 0
var _list_grid: GridContainer


## spec: {"title", "subtitle", "desc": [[раздел, значок, [строки]]], "tabs": [{"name", "items",
## "empty", "filters"?: [[ключ, подпись, вкл]], "on_filter"?: Callable(ключ, вкл)}],
## "actions": [[текст, Callable, стиль]]}. Ряд: {"looks"|"glyph"|"tex", "name", "info",
## "warn"?: красным, "button"?, "style"?, "pick"?, "open"}.
func show_list(spec: Dictionary, start_tab := -1) -> void:
	var keep := 0
	if _choice != null and _choice.get_meta("list", "") == spec["title"] and is_instance_valid(_choice_scroll):
		keep = _choice_scroll.scroll_vertical
	_list_spec = spec
	if start_tab >= 0:
		_list_tab = start_tab
	_list_tab = clampi(_list_tab, 0, spec["tabs"].size() - 1)
	var v := _overlay(spec["title"], spec.get("subtitle", ""))
	_choice.set_meta("list", spec["title"])
	var w := minf(size.x - 120.0, 1240.0)
	# «Описание» — справка (если есть).
	var desc: Array = spec.get("desc", [])
	if not desc.is_empty():
		var db := Button.new()
		db.text = "Описание"
		db.focus_mode = Control.FOCUS_NONE
		db.custom_minimum_size = Vector2(0, 40)
		db.add_theme_font_size_override("font_size", 17)
		db.add_theme_stylebox_override("normal", _desc_btn.get_theme_stylebox("normal"))
		db.add_theme_stylebox_override("hover", _desc_btn.get_theme_stylebox("hover"))
		db.pressed.connect(func() -> void:
			_room_desc = []
			_room_desc_sections = desc
			_room_desc_title = spec["title"]
			_show_room_desc())
		var head: HBoxContainer = v.get_child(0)
		head.add_child(db)
		head.move_child(db, 1)
	# Вкладки.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 8)
	v.add_child(bar)
	for i in spec["tabs"].size():
		var t: Dictionary = spec["tabs"][i]
		var b := Button.new()
		b.text = "%s  %d" % [t["name"], t["items"].size()] if not t.get("no_count", false) else t["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 17)
		var on: bool = i == _list_tab
		var nsb := btn_box(ACCENT) if on else UiStyle.flat(Color(1, 1, 1, 0.08), 12, 8)
		nsb.content_margin_left = 16
		nsb.content_margin_right = 16
		b.add_theme_stylebox_override("normal", nsb)
		b.add_theme_stylebox_override("hover", nsb)
		b.add_theme_stylebox_override("pressed", btn_box(ACCENT))
		var k: int = i
		b.pressed.connect(func() -> void:
			if _list_spec.has("on_tab"):
				_list_spec["on_tab"].call(k)
			show_list(_list_spec, k))
		bar.add_child(b)
	var tab: Dictionary = spec["tabs"][_list_tab]
	# Фильтры вкладки — переключателями.
	var filters: Array = tab.get("filters", [])
	if not filters.is_empty():
		var fr := HFlowContainer.new()
		fr.add_theme_constant_override("h_separation", 6)
		fr.add_theme_constant_override("v_separation", 6)
		v.add_child(fr)
		fr.add_child(_label("Показать:", 16, MUTED))
		for f in filters:
			var fb := Button.new()
			fb.text = f[1]
			fb.toggle_mode = true
			fb.button_pressed = f[2]
			fb.focus_mode = Control.FOCUS_NONE
			fb.custom_minimum_size = Vector2(0, 40)
			fb.add_theme_font_size_override("font_size", 15)
			var fsb := UiStyle.flat(Color(0.98, 0.57, 0.24, 0.35) if f[2] else Color(1, 1, 1, 0.06), 10, 6)
			fsb.content_margin_left = 12
			fsb.content_margin_right = 12
			if f[2]:
				fsb.border_color = ACCENT
				fsb.set_border_width_all(2)
			fb.add_theme_stylebox_override("normal", fsb)
			fb.add_theme_stylebox_override("hover", fsb)
			fb.add_theme_stylebox_override("pressed", fsb)
			var key: String = f[0]
			var cb: Callable = tab["on_filter"]
			fb.toggled.connect(func(x: bool) -> void: cb.call(key, x))
			fr.add_child(fb)
	# Ряды.
	var cols := 2 if w > 900.0 else 1
	var cw := (w - 10.0 * (cols - 1)) / cols
	_list_grid = GridContainer.new()
	_list_grid.columns = cols
	_list_grid.add_theme_constant_override("h_separation", 10)
	_list_grid.add_theme_constant_override("v_separation", 8)
	var items: Array = tab["items"]
	for it: Dictionary in items:
		_list_grid.add_child(_list_row(it, cw))
	if items.is_empty():
		_list_grid.add_child(_label(tab.get("empty", "Пусто."), 17, MUTED))
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(_list_grid)
	_choice_scroll.custom_minimum_size = Vector2(w, maxf(160.0, size.y - 330.0 - (50.0 if not filters.is_empty() else 0.0)))
	v.add_child(_choice_scroll)
	# Кнопки внизу.
	var acts: Array = spec.get("actions", [])
	if not acts.is_empty():
		var ar := HBoxContainer.new()
		ar.add_theme_constant_override("separation", 8)
		v.add_child(ar)
		for a in acts:
			var b := _action_button(a)
			b.pressed.connect(a[1])
			ar.add_child(b)
	if keep > 0:
		var sc := _choice_scroll
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_vertical = keep


func _list_row(it: Dictionary, w: float) -> Control:
	var p := PanelContainer.new()
	var warn: bool = not str(it.get("warn", "")).is_empty()
	var sb := UiStyle.flat(Color(1, 1, 1, 0.06), 12, 8)
	if warn:
		sb.border_color = Color(1, 0.45, 0.35, 0.8)
		sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, 76)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if it.has("open"):
		var open: Callable = it["open"]
		var press := {"at": Vector2.INF}
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					press["at"] = ev.global_position
				elif press["at"] != Vector2.INF and ev.global_position.distance_to(press["at"]) < DRAG_DEADZONE:
					press["at"] = Vector2.INF
					open.call())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(h)
	if it.has("looks"):
		h.add_child(PortraitView.make(it["looks"], 58, 34))
	else:
		var ib := PanelContainer.new()
		ib.add_theme_stylebox_override("panel", UiStyle.flat(Color(1, 1, 1, 0.06), 10, 4))
		ib.custom_minimum_size = Vector2(58, 58)
		ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		ib.add_child(cc)
		var tex: String = it.get("tex", "")
		if not str(it.get("icon_key", "")).is_empty():
			cc.add_child(IconView.make(it["icon_key"], 40))
		elif not tex.is_empty() and ResourceLoader.exists(tex):
			var tr := TextureRect.new()
			tr.texture = load(tex)
			tr.custom_minimum_size = Vector2(52, 52)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cc.add_child(tr)
		else:
			cc.add_child(IconView.make("", 34, it.get("glyph", "room"), Color(0.75, 0.95, 0.95)))
		h.add_child(ib)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(col)
	var nm := _label(it["name"], 18, Color.WHITE)
	nm.add_theme_font_override("font", Fonts.black())
	nm.clip_text = true
	col.add_child(nm)
	if warn:
		var wl := _label(it["warn"], 14, Color(1, 0.6, 0.5))
		wl.clip_text = true
		col.add_child(wl)
	var info := _label(it.get("info", ""), 14, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.max_lines_visible = 1 if warn else 2
	info.custom_minimum_size = Vector2(w - 110.0 - (150.0 if it.has("button") else 0.0) - 78.0 * it.get("buttons", []).size(), 0)
	col.add_child(info)
	# Несколько кнопок в ряду (груз: «−10», «+10»).
	for bt in it.get("buttons", []):
		var bb := Button.new()
		bb.text = bt[0]
		bb.focus_mode = Control.FOCUS_NONE
		bb.custom_minimum_size = Vector2(70, 48)
		bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bb.add_theme_font_size_override("font_size", 18)
		bb.disabled = bt.size() > 2 and bt[2] == "off"
		bb.pressed.connect(bt[1])
		h.add_child(bb)
	if it.has("button") and not str(it["button"]).is_empty():
		var b := Button.new()
		b.text = it["button"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 48)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 16)
		match it.get("style", ""):
			"danger":
				b.add_theme_stylebox_override("normal", btn_box(RED))
			"primary":
				b.add_theme_stylebox_override("normal", btn_box(GREEN))
		b.pressed.connect(it["pick"])
		h.add_child(b)
	return p


## Окно выбора гаврика поверх карточки (карточка под ним остаётся открытой).
## spec: {"title", "subtitle", "checks": [[ключ, подпись, вкл]], "toggled": Callable(ключ, вкл),
## "items": [{"looks", "name", "info", "button", "style", "pick"}], "empty"}. Повторный вызов
## с тем же заголовком — обновление: прокрутка остаётся на месте.
func show_people_pick(spec: Dictionary) -> void:
	var keep := 0
	if _choice != null and _choice.get_meta("title", "") == spec["title"] and is_instance_valid(_choice_scroll):
		keep = _choice_scroll.scroll_vertical
	var v := _overlay(spec["title"], spec.get("subtitle", ""), spec.get("back", Callable()))
	var w := minf(size.x - 140.0, 920.0)
	var checks: Array = spec.get("checks", [])
	if not checks.is_empty():
		var cr := HFlowContainer.new()
		cr.add_theme_constant_override("h_separation", 8)
		cr.add_theme_constant_override("v_separation", 8)
		v.add_child(cr)
		for ck in checks:
			var key: String = ck[0]
			var on: bool = ck[2]
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.button_pressed = on
			b.custom_minimum_size = Vector2(0, 46)
			b.add_theme_font_size_override("font_size", 17)
			b.text = str(ck[1])
			b.add_theme_stylebox_override("normal", btn_box(ACCENT) if on else UiStyle.flat(Color(1, 1, 1, 0.08), 12, 8))
			b.add_theme_stylebox_override("pressed", btn_box(ACCENT))
			b.add_theme_stylebox_override("hover", btn_box(ACCENT) if on else UiStyle.flat(Color(1, 1, 1, 0.12), 12, 8))
			var tg: Callable = spec["toggled"]
			b.toggled.connect(func(x: bool) -> void: tg.call(key, x))
			cr.add_child(b)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.custom_minimum_size = Vector2(w, maxf(200.0, size.y - 300.0))
	_choice_scroll.add_child(list)
	v.add_child(_choice_scroll)
	var items: Array = spec.get("items", [])
	if items.is_empty():
		list.add_child(_label(spec.get("empty", ""), 17, MUTED))
	for it: Dictionary in items:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiStyle.flat(Color(1, 1, 1, 0.06), 12, 8))
		list.add_child(p)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		p.add_child(row)
		row.add_child(PortraitView.make(it.get("looks", {}), 60, 34))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var nm := _label(it["name"], 19, Color.WHITE)
		nm.add_theme_font_override("font", Fonts.black())
		col.add_child(nm)
		var info := _label(it.get("info", ""), 15, MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(w - 260.0, 0)
		col.add_child(info)
		var b := Button.new()
		b.text = it.get("button", "Назначить")
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 52)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", btn_box(RED if it.get("style", "") == "danger" else GREEN))
		b.add_theme_stylebox_override("hover", btn_box((RED if it.get("style", "") == "danger" else GREEN).lightened(0.08)))
		b.pressed.connect(it["pick"])
		row.add_child(b)
	_choice.set_meta("title", spec["title"])
	if keep > 0:
		var sc := _choice_scroll
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_vertical = keep


## Затемнение и окно по центру поверх всего: заголовок (и подпись), крестик. Возвращает, куда
## класть содержимое.
func _overlay(title: String, subtitle := "", on_close := Callable()) -> VBoxContainer:
	if _choice != null:
		_choice.queue_free()
	_choice = Control.new()
	_choice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_choice)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close_choice())
	_choice.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice.add_child(center)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", _win())
	center.add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	win.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var t := _label(title, 24, Color.WHITE)
	t.add_theme_font_override("font", Fonts.black())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var close := IconButton.make("close", "", 48, 48)
	close.pressed.connect(on_close if on_close.is_valid() else close_choice)
	head.add_child(close)
	if not subtitle.is_empty():
		var st := _label(subtitle, 16, ACCENT)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(minf(size.x - 160.0, 900.0), 0)
		v.add_child(st)
	return v


# --- Мини-меню действия на карте (сдвиг комнаты, продление, бур) -------------------------
var _tool: PanelContainer


## Небольшая панель внизу по центру, карта над ней видна: рамка нового места — на карте.
## spec: {"title", "icon", "dirs": [подписи], "dir": номер, "on_dir": Callable(номер),
## "len", "len_min", "len_max", "on_len": Callable(n), "cost": [[ключ, есть, нужно, хватает]],
## "info", "warn", "ok", "on_ok": Callable, "on_cancel": Callable}
func show_tool(spec: Dictionary) -> void:
	if _tool == null:
		_tool = PanelContainer.new()
		_tool.add_theme_stylebox_override("panel", _win())
		_tool.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_tool)
	for c in _tool.get_children():
		_tool.remove_child(c)
		c.queue_free()
	var w := TOOL_W - 28.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_tool.add_child(v)
	# Шапка: значок, название, крестик.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", UiStyle.grad(UiStyle.ORANGE_A, UiStyle.ORANGE_B, 12, 4, false, false))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ib.add_child(IconView.make("", 26, spec.get("icon", "room"), Color.WHITE))
	head.add_child(ib)
	var t := _label(spec["title"], 19, Color.WHITE)
	t.add_theme_font_override("font", Fonts.black())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 110.0, 0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var close := IconButton.make("close", "", 44, 44)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(spec["on_cancel"])
	head.add_child(close)
	# Направление — ромбом: вверх сверху, влево и вправо по бокам, вниз снизу.
	var vecs: Array = spec.get("dir_vecs", [])
	if not vecs.is_empty():
		var gc := CenterContainer.new()
		v.add_child(gc)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 2)
		gc.add_child(grid)
		var cells := {Vector2i(1, 0): Vector2i.UP, Vector2i(0, 1): Vector2i.LEFT, Vector2i(2, 1): Vector2i.RIGHT, Vector2i(1, 2): Vector2i.DOWN}
		for y in 3:
			for x in 3:
				var cell := Vector2i(x, y)
				if not cells.has(cell):
					var gap := Control.new()
					gap.custom_minimum_size = Vector2(56, 46)
					gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
					grid.add_child(gap)
					continue
				var dv: Vector2i = cells[cell]
				var idx := vecs.find(dv)
				var b := Button.new()
				b.text = {Vector2i.UP: "↑", Vector2i.LEFT: "←", Vector2i.RIGHT: "→", Vector2i.DOWN: "↓"}[dv]
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(56, 46)
				b.add_theme_font_size_override("font_size", 26)
				var on: bool = idx >= 0 and idx == int(spec.get("dir", 0))
				b.add_theme_stylebox_override("normal", btn_box(ACCENT) if on else btn_box(BTN))
				b.add_theme_stylebox_override("hover", btn_box(ACCENT) if on else btn_box(BTN.lightened(0.08)))
				b.disabled = idx < 0
				if idx < 0:
					b.modulate = Color(1, 1, 1, 0.3)
				var cb: Callable = spec["on_dir"]
				b.pressed.connect(func() -> void: cb.call(idx))
				grid.add_child(b)
	# «Выбрать на карте»: вокруг постройки — стрелки, их тянут пальцем.
	if spec.has("on_pick"):
		var pk := Button.new()
		pk.text = "Выбрать на карте"
		pk.focus_mode = Control.FOCUS_NONE
		pk.custom_minimum_size = Vector2(0, 46)
		pk.add_theme_font_size_override("font_size", 17)
		var pon: bool = spec.get("pick", false)
		pk.add_theme_stylebox_override("normal", btn_box(GREEN) if pon else btn_box(BTN))
		pk.add_theme_stylebox_override("hover", btn_box(GREEN) if pon else btn_box(BTN.lightened(0.08)))
		pk.pressed.connect(spec["on_pick"])
		v.add_child(pk)
	# На сколько.
	if spec.has("len"):
		var lh := HBoxContainer.new()
		lh.add_theme_constant_override("separation", 6)
		lh.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(lh)
		var n: int = spec["len"]
		var lo: int = spec.get("len_min", 1)
		var hi: int = maxi(lo, int(spec.get("len_max", 1)))
		var on_len: Callable = spec["on_len"]
		for k in [-1, 1]:
			var b := Button.new()
			b.text = "−" if k < 0 else "+"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(52, 46)
			b.add_theme_font_size_override("font_size", 24)
			b.disabled = (n <= lo) if k < 0 else (n >= hi)
			b.pressed.connect(func() -> void: on_len.call(clampi(n + k, lo, hi)))
			lh.add_child(b)
			if k < 0:
				var val := _label("%d м" % n, 24, Color.WHITE)
				val.add_theme_font_override("font", Fonts.black())
				val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				val.custom_minimum_size = Vector2(90, 0)
				val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				lh.add_child(val)
	# Цена.
	var cf := HFlowContainer.new()
	cf.add_theme_constant_override("h_separation", 6)
	cf.add_theme_constant_override("v_separation", 6)
	cf.visible = not spec.get("no_cost", false)
	v.add_child(cf)
	cf.add_child(_label("Нужно:", 16, MUTED))
	var cost: Array = spec.get("cost", [])
	for it in cost:
		cf.add_child(_chip(it, true))
	if cost.is_empty():
		cf.add_child(_label("ничего", 16, Color.WHITE))
	# Пояснение или почему нельзя.
	var warn: String = spec.get("warn", "")
	var blocked: bool = spec.get("blocked", not warn.is_empty())
	var txt := _label(warn if not warn.is_empty() else str(spec.get("info", "")), 14,
		(Color(1, 0.5, 0.45) if blocked else Color(1, 0.8, 0.45)) if not warn.is_empty() else MUTED)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(w, 0)
	txt.visible = not txt.text.is_empty()
	v.add_child(txt)
	# Кнопки — в ряд: «Отмена» и главная.
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 8)
	v.add_child(br)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 50)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(spec["on_cancel"])
	br.add_child(cancel)
	var ok := Button.new()
	ok.text = spec.get("ok", "Готово")
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(0, 50)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.add_theme_font_size_override("font_size", 18)
	ok.add_theme_stylebox_override("normal", btn_box(BTN if blocked else ACCENT))
	ok.add_theme_stylebox_override("hover", btn_box(BTN if blocked else ACCENT))
	ok.pressed.connect(spec["on_ok"])
	br.add_child(ok)
	_tool.visible = true
	_tool.custom_minimum_size = Vector2(TOOL_W, 0)
	_place_tool.call_deferred()


## Ширина мини-меню справа.
const TOOL_W := 320.0


func _place_tool() -> void:
	if _tool == null:
		return
	_tool.size = _tool.get_combined_minimum_size()
	var top := _top_limit()
	var bottom := size.y - BAR_H - 6.0
	# По центру между верхней строкой и нижним меню; не влезает — прижато к верху.
	_tool.position = Vector2(size.x - SIDE - _tool.size.x, clampf((top + bottom - _tool.size.y) * 0.5, top, maxf(top, bottom - _tool.size.y)))


## Часть экрана, свободная от мини-меню (слева от него, между верхней строкой и нижним меню).
func tool_free_rect() -> Rect2:
	var top := _top_limit()
	return Rect2(0.0, top, size.x - TOOL_W - SIDE * 2.0, size.y - BAR_H - top)


func hide_tool() -> void:
	if _tool != null:
		_tool.visible = false


func tool_open() -> bool:
	return _tool != null and _tool.visible


func close_choice() -> void:
	if _choice != null:
		_choice.queue_free()
		_choice = null


## Карточка варианта — все одного размера, всё по центру: картинка, название (до двух строк),
## цена одной строкой, внизу — пометка («сейчас», супер-свойство или почему нельзя).
const CHOICE_W := 236.0
const CHOICE_H := 212.0


func _choice_option(o: Dictionary, w: float, cb: Callable, h := CHOICE_H) -> PanelContainer:
	var b := PanelContainer.new()
	var cur: bool = o.get("current", false)
	var normal: StyleBox
	if cur:
		normal = UiStyle.flat(Color(0.98, 0.57, 0.24, 0.22), 16, 8)
		normal.border_color = ACCENT
		normal.set_border_width_all(3)
	else:
		normal = UiStyle.flat(Color(1, 1, 1, 0.07), 16, 8)
	b.add_theme_stylebox_override("panel", normal)
	b.custom_minimum_size = Vector2(w, h)
	b.clip_contents = true
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				b.add_theme_stylebox_override("panel", UiStyle.flat(Color(1, 1, 1, 0.18), 16, 8))
			else:
				b.add_theme_stylebox_override("panel", normal)
				if Rect2(Vector2.ZERO, b.size).has_point(e.position):
					cb.call())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	# Картинка — в рамке постоянной высоты.
	var pic := CenterContainer.new()
	pic.custom_minimum_size = Vector2(0, 56)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var tex: String = o.get("tex", "")
	if not tex.is_empty() and ResourceLoader.exists(tex):
		var tr := TextureRect.new()
		tr.texture = load(tex)
		tr.custom_minimum_size = Vector2(76, 54)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_child(tr)
	elif not str(o.get("icon", "")).is_empty():
		pic.add_child(IconView.make(o["icon"], 46))
	elif not str(o.get("glyph", "")).is_empty():
		pic.add_child(IconView.make("", 42, o["glyph"], Color(0.75, 0.95, 0.95)))
	else:
		pic.add_child(IconView.make("", 40, "room", Color(0.75, 0.95, 0.95)))
	# Название — до двух строк, место под него всегда одинаковое.
	var nm := _label(o["text"], 18, Color.WHITE)
	nm.add_theme_font_override("font", Fonts.black())
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.max_lines_visible = 2
	nm.custom_minimum_size = Vector2(w - 16.0, 46)
	v.add_child(nm)
	# Что даёт (у улучшений) — несколько строк под названием.
	var desc: String = o.get("desc", "")
	if not desc.is_empty():
		var dl := _label(desc, 15, Color(0.85, 0.9, 0.94))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.max_lines_visible = 4
		dl.custom_minimum_size = Vector2(w - 16.0, 84)
		v.add_child(dl)
	# Цена — одной строкой по центру.
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.custom_minimum_size = Vector2(0, 32)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cost_row)
	var cost: Array = o.get("cost", [])
	for it in cost:
		cost_row.add_child(_mini_chip(it))
	if cost.is_empty() and not cur and not o.get("no_cost", false):
		cost_row.add_child(_label("бесплатно", 15, MUTED))
	cost_row.visible = not (cost.is_empty() and o.get("no_cost", false))
	# Пометка внизу.
	var note: String = o.get("error", "")
	var note_col := Color(1, 0.55, 0.5)
	if note.is_empty():
		note = "сейчас" if cur else ""
		note_col = Color(1, 0.75, 0.45)
		var sub: String = o.get("sub", "")
		if not sub.is_empty():
			note = sub
			note_col = Color(1, 0.88, 0.45)
	# Пометка — до двух строк, переносится, не обрезается.
	var nl := _label(note, 15, note_col)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.max_lines_visible = 2
	nl.custom_minimum_size = Vector2(w - 16.0, 40)
	v.add_child(nl)
	return b


## Маленькая плашка цены: значок и «есть/нужно» (не хватает — красная).
func _mini_chip(item: Array) -> Control:
	var p := PanelContainer.new()
	var ok: bool = item.size() < 4 or item[3]
	p.add_theme_stylebox_override("panel", _box(Color(0.62, 0.16, 0.14, 0.9) if not ok else Color(1, 1, 1, 0.08), 8, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(IconView.make(item[0], 22))
	h.add_child(_label(str(item[2]) if ok else "%s/%s" % [Fmt.int_spaced(item[1]), Fmt.int_spaced(item[2])], 16, Color.WHITE))
	return p


func show_message(title: String, text: String) -> void:
	_dialog_title.text = title
	_dialog_text.text = text
	_dialog.visible = true


func log_event(text: String, kind: String = "info", at: Variant = null) -> void:
	# Строка журнала на полупрозрачной подложке — читается и на небе, и на земле. Есть место —
	# строку можно нажать: камера перейдёт туда (метка «›» в конце).
	var l := PanelContainer.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE if at == null else Control.MOUSE_FILTER_STOP
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	if at != null:
		text += "  ›"
		var cell: Vector2i = at
		l.gui_input.connect(func(e: InputEvent) -> void:
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
					or (e is InputEventScreenTouch and e.pressed):
				l.accept_event()
				log_pressed.emit(cell))
	var sb := _box_plain(Color(TOP_BG, 0.62), 10, 4)
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
