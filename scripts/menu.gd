extends Control
## Главное меню — с него начинается игра: «Продолжить» (последнее сохранение), «Миры»
## (каждый мир — отдельная игра со своими сохранениями), «Настройки».

const GAME_SCENE := "res://scenes/main.tscn"
const BG := Color(0.16, 0.08, 0.04)
const PANEL_W := 640.0
const LIST_H := 330.0

var _content: VBoxContainer
var _logo: TextureRect
## Стек экранов: [имя, параметр] — «Назад» возвращает на предыдущий.
var _stack: Array = []


func _ready() -> void:
	ThemeDB.fallback_font = Fonts.bold()
	theme = Hud.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Worlds.migrate_legacy()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	add_child(row)
	# Логотип — только на главном экране меню.
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/logo/logo.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(300, 300)
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_logo)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	panel.add_child(_content)
	_open("root")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _open(screen: String, arg := "") -> void:
	_stack.append([screen, arg])
	_show()


func _back() -> void:
	if _stack.size() <= 1:
		# «Назад» на главном экране сворачивает игру, а не закрывает её.
		AppWindow.minimize()
		return
	_stack.pop_back()
	_show()


func _show() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var top: Array = _stack[-1]
	_logo.visible = top[0] == "root"
	match top[0]:
		"root":
			_root()
		"worlds":
			_worlds()
		"world":
			_world(top[1])
		"new":
			_new_world()
		"settings":
			_settings()


func _title(text: String) -> void:
	var t := Hud._label(text, 30, Color.WHITE)
	t.add_theme_font_override("font", Fonts.black())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(t)


func _button(parent: Control, text: String, cb: Callable, col := Hud.BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
	if col != Hud.BTN:
		b.add_theme_stylebox_override("normal", Hud.btn_box(col))
		b.add_theme_stylebox_override("hover", Hud.btn_box(col.lightened(0.1)))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _scroll() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, LIST_H)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


# --- Экраны ------------------------------------------------------------------------------

func _root() -> void:
	_title("Гаврики")
	var last := Worlds.latest()
	if not last.is_empty():
		_button(_content, "Продолжить", func() -> void:
			_play(last["world"], last["id"], last["id"] == Worlds.AUTO), Hud.ACCENT)
		var info := Hud._label("%s · %s" % [last.get("world_name", ""), SavesView.info_line(last)], 17, Hud.MUTED)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(info)
	else:
		_button(_content, "Новая игра", func() -> void: _open("new"), Hud.ACCENT)
	_button(_content, "Миры", func() -> void: _open("worlds"))
	_button(_content, "Настройки", func() -> void: _open("settings"))
	if OS.get_name() != "Android":
		_button(_content, "Выход", func() -> void: get_tree().quit())


func _worlds() -> void:
	_title("Миры")
	var hint := Hud._label("Каждый мир — отдельная игра со своими сохранениями.", 17, Hud.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)
	_button(_content, "+ Новый мир", func() -> void: _open("new"), Hud.GREEN)
	var list := _scroll()
	var worlds := Worlds.list()
	if worlds.is_empty():
		list.add_child(Hud._label("Миров пока нет — создайте первый.", 18, Hud.MUTED))
	for m in worlds:
		var wid: String = m["id"]
		var saves := Worlds.saves(wid)
		var parts: PackedStringArray = []
		if not saves.is_empty():
			var s: Dictionary = saves[0]
			parts.append("гавриков %d" % int(s.get("units", 0)))
			if not str(s.get("date", "")).is_empty():
				parts.append(str(s["date"]))
		parts.append("играли " + Worlds.when(float(m.get("played", 0))))
		var info := " · ".join(parts)
		var b := _button(list, "%s\n%s" % [m.get("name", "Мир"), info], func() -> void: _open("world", wid))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 19)
		b.custom_minimum_size = Vector2(0, 84)
	_button(_content, "Назад", _back)


func _world(wid: String) -> void:
	var m := Worlds.meta(wid)
	if m.is_empty():
		_back()
		return
	_title(m.get("name", "Мир"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	var saves := Worlds.saves(wid)
	var play := _button(row, "Играть", func() -> void:
		if saves.is_empty():
			_play(wid, "", false)
		else:
			_play(wid, saves[0]["id"], saves[0]["id"] == Worlds.AUTO), Hud.ACCENT)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rename := _button(row, "Имя", func() -> void: _rename_row(wid))
	rename.custom_minimum_size.x = 120
	var del := Button.new()
	del.text = "Удалить мир"
	del.focus_mode = Control.FOCUS_NONE
	del.custom_minimum_size = Vector2(170, 64)
	del.pressed.connect(func() -> void:
		if del.text != "Точно удалить?":
			del.text = "Точно удалить?"
			del.add_theme_stylebox_override("normal", Hud.btn_box(Hud.RED))
			return
		Worlds.delete(wid)
		_back())
	row.add_child(del)
	var list := _scroll()
	var sv := SavesView.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(sv)
	sv.show_world(wid)
	sv.load_requested.connect(func(sid: String) -> void: _play(wid, sid, false))
	_button(_content, "Назад", _back)


## Переименование: поле ввода вместо кнопок мира.
func _rename_row(wid: String) -> void:
	var edit := LineEdit.new()
	edit.text = Worlds.meta(wid).get("name", "")
	edit.custom_minimum_size = Vector2(0, 58)
	edit.add_theme_font_size_override("font_size", 22)
	_content.add_child(edit)
	_content.move_child(edit, 1)
	var ok := _button(_content, "Сохранить имя", func() -> void:
		Worlds.rename(wid, edit.text)
		_show(), Hud.GREEN)
	_content.move_child(ok, 2)
	edit.grab_focus()


func _new_world() -> void:
	_title("Новый мир")
	var edit := LineEdit.new()
	edit.placeholder_text = Worlds.default_name()
	edit.custom_minimum_size = Vector2(0, 58)
	edit.add_theme_font_size_override("font_size", 22)
	_content.add_child(edit)
	var dis := CheckButton.new()
	dis.text = "Стихийные бедствия"
	dis.button_pressed = true
	dis.focus_mode = Control.FOCUS_NONE
	dis.add_theme_font_size_override("font_size", 22)
	_content.add_child(dis)
	var hint := Hud._label("Очень редкие бури (раз в 4–10 часов игры) и землетрясения (раз в 12–30 часов), с предупреждением и только пока вы в игре.", 16, Hud.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	_content.add_child(hint)
	_button(_content, "Создать и начать", func() -> void:
		var wid := Worlds.create(edit.text, dis.button_pressed)
		_play(wid, "", false), Hud.ACCENT)
	_button(_content, "Назад", _back)


func _settings() -> void:
	_title("Настройки")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, LIST_H + 40)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(sc)
	var sv := SettingsView.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(sv)
	_button(_content, "Назад", _back)


## В игру: мир wid, сохранение sid ("" — новый мир). offline — засчитать время отсутствия.
func _play(wid: String, sid: String, offline: bool) -> void:
	Worlds.launch = {"world": wid, "save": sid, "offline": offline}
	Worlds.touch(wid)
	get_tree().change_scene_to_file(GAME_SCENE)
