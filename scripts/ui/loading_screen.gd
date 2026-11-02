class_name LoadingScreen
extends CanvasLayer
## Экран загрузки: картинка (случайная из assets/loading/, если там есть; иначе — логотип
## на тёмном фоне), подпись и полоска. Закрывает мир, пока он догружается, — входе в игру,
## загрузке сохранения и переходе на другую планету.

const PICTURES := "res://assets/loading/"
const BG := Color(0.07, 0.08, 0.11)

var _bar: BarView
var _label: Label
var _root: Control
var _shown := 0.0
var _target := 0.0
var _closing := false


## Случайная картинка из assets/loading/ ("" — их нет).
static func pick_picture() -> String:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(PICTURES):
		for f in ResourceLoader.list_directory(PICTURES):
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				out.append(PICTURES + f)
	return out.pick_random() if not out.is_empty() else ""


static func make(picture := "") -> LoadingScreen:
	var s := LoadingScreen.new()
	s.layer = 100
	s._build(picture)
	return s


func _build(picture: String) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var tex: Texture2D = load(picture) if not picture.is_empty() and ResourceLoader.exists(picture) else null
	var img := TextureRect.new()
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		img.texture = tex
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		img.texture = load("res://assets/logo/logo.png")
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.anchor_left = 0.25
		img.anchor_right = 0.75
		img.anchor_top = 0.12
		img.anchor_bottom = 0.68
	_root.add_child(img)
	# Внизу — затемнение под подписью и полоской (на светлой картинке их видно).
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.78
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var box := VBoxContainer.new()
	box.anchor_left = 0.2
	box.anchor_right = 0.8
	box.anchor_top = 0.8
	box.anchor_bottom = 0.96
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", Fonts.black())
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_label)
	_bar = BarView.make(0.0, Color(0.96, 0.62, 0.15))
	_bar.custom_minimum_size = Vector2(0, 30)
	box.add_child(_bar)


## Сколько загружено (0..1) и что грузим. Полоска плавно догоняет.
func set_progress(v: float, text := "") -> void:
	_target = maxf(_target, clampf(v, 0.0, 1.0))
	if not text.is_empty():
		_label.text = text
	if _shown <= 0.0:
		_shown = _target
		_apply()


## Готово: полоска дотягивается, экран плавно гаснет и убирается.
func finish() -> void:
	_target = 1.0
	_closing = true


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 2.5)
	_apply()
	if _closing and _shown >= 1.0:
		_root.modulate.a -= delta * 4.0
		if _root.modulate.a <= 0.0:
			queue_free()


func _apply() -> void:
	_bar.value = _shown
	_bar.text = "%d%%" % roundi(_shown * 100.0)
	_bar.queue_redraw()
