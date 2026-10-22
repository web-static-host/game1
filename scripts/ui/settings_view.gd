class_name SettingsView
extends VBoxContainer
## Настройки игры — одинаковые в главном меню и в меню внутри игры: автосохранение,
## сохранение при выходе, игра в фоне, 3D-модель гавриков. Пишет в Settings сразу.

signal changed(key: String, value: Variant)

const HINT_W := 460.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(Hud._label("Автосохранение", 22, Color.WHITE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var group := ButtonGroup.new()
	var cur := int(Settings.get_value("autosave_min"))
	for m in Settings.AUTOSAVE_CHOICES:
		var b := Button.new()
		b.text = "выкл" if m == 0 else "%d мин" % m
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m == cur
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_apply("autosave_min", m))
		row.add_child(b)
	_hint("Как часто игра сама сохраняется в «Автосохранение» этого мира.")
	_check("save_on_exit", "Сохранять при выходе",
		"При выходе в меню, закрытии и сворачивании игра сохраняется в «Автосохранение».")
	_check("background", "Игра в фоне",
		"Включено — пока вас нет, гаврики работают (до 1 часа). Выключено — игра на паузе, пока вы не вернётесь.")
	_check("models", "3D-модель гавриков", "Выключено — гаврики рисованные (так легче слабым телефонам).")


func _check(key: String, text: String, hint: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Settings.get_value(key))
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(func(on: bool) -> void: _apply(key, on))
	add_child(c)
	_hint(hint)


func _hint(text: String) -> void:
	var l := Hud._label(text, 16, Hud.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(HINT_W, 0)
	add_child(l)


func _apply(key: String, value: Variant) -> void:
	Settings.set_value(key, value)
	changed.emit(key, value)
