class_name SavesView
extends VBoxContainer
## Сохранения одного мира: имя, когда, итоги; «Загрузить» и «Удалить» (удаление —
## вторым нажатием). Одинаково в главном меню и в меню игры.

signal load_requested(sid: String)

var world_id := ""


func show_world(wid: String) -> void:
	world_id = wid
	refresh()


func refresh() -> void:
	add_theme_constant_override("separation", 8)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var list := Worlds.saves(world_id)
	if list.is_empty():
		add_child(Hud._label("Сохранений пока нет.", 18, Hud.MUTED))
		return
	for s in list:
		add_child(_row(s))


static func info_line(s: Dictionary) -> String:
	var parts: PackedStringArray = [Worlds.when(float(s.get("saved_at", 0)))]
	if s.has("units"):
		parts.append("гавриков %d" % int(s["units"]))
	if not str(s.get("date", "")).is_empty():
		parts.append(str(s["date"]))
	if int(s.get("depth", 0)) > 0:
		parts.append("глубина %d м" % int(s["depth"]))
	return " · ".join(parts)


func _row(s: Dictionary) -> Control:
	var sid: String = s["id"]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Hud._box(Color(1, 1, 1, 0.06), 14, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var auto := sid == Worlds.AUTO
	v.add_child(Hud._label(str(s.get("name", "Автосохранение" if auto else "Сохранение")), 21,
		Hud.ACCENT if auto else Color.WHITE))
	var info := Hud._label(info_line(s), 16, Hud.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	v.add_child(info)
	var load := Button.new()
	load.text = "Загрузить"
	load.focus_mode = Control.FOCUS_NONE
	load.custom_minimum_size = Vector2(150, 56)
	load.add_theme_stylebox_override("normal", Hud.btn_box(Hud.GREEN))
	load.pressed.connect(func() -> void: load_requested.emit(sid))
	h.add_child(load)
	var del := Button.new()
	del.text = "Удалить"
	del.focus_mode = Control.FOCUS_NONE
	del.custom_minimum_size = Vector2(120, 56)
	del.pressed.connect(func() -> void:
		if del.text != "Точно?":
			del.text = "Точно?"
			del.add_theme_stylebox_override("normal", Hud.btn_box(Hud.RED))
			return
		Worlds.delete_save(world_id, sid)
		refresh())
	h.add_child(del)
	return panel
