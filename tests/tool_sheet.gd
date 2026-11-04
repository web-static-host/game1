extends SceneTree
## Лист инструментов: 3D-гаврик в рабочих позах с инструментом в руке, сверху — рисованный
## (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1600x900 -s res://tests/tool_sheet.gd -- <снимок.png> [форма]

var _out := "user://tools.png"
var _shape := CreatureArt.Shape.TRIANGLE
var _models: ModelSprites
var _list := []
var _frame := 0
var _shot_at := -1
var _looks := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_shape = int(args[1])
	_looks = {"color": Color(0.2, 0.45, 1.0), "shape": _shape, "eyes": 1, "fingers": 4, "size": 0, "pattern": 0}
	for t in ModelSprites.TOOL_POSES:
		for p in ModelSprites.TOOL_POSES[t]:
			_list.append([p, t])
	_models = ModelSprites.new()
	root.add_child(_models)


func _process(_delta: float) -> bool:
	_frame += 1
	if _shot_at < 0 and _models.is_baked:
		var ready := ModelSprites.fits(_looks)
		for it in _list:
			ready = _models.tool_ready(_looks, it[1], it[0]) and ready
		if ready:
			_build()
			_shot_at = _frame + 4
	if _shot_at > 0 and _frame == _shot_at:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return _frame > 6000


func _build() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.7, 0.85)
	bg.size = Vector2(2000, 1200)
	layer.add_child(bg)
	var cols := 8
	for i in _list.size():
		var x := 80.0 + (i % cols) * 150.0
		var y := 200.0 + (i / cols) * 260.0
		var pose: String = _list[i][0] + "@" + _list[i][1]
		var label: String = "%s %s" % _list[i]
		_add(layer, func(ci: CanvasItem) -> void: ModelSprites.draw_creature(ci, pose, Vector2(x, y), 70.0, _looks))
		_add(layer, func(ci: CanvasItem) -> void: ci.draw_string(ThemeDB.fallback_font, Vector2(x - 70, y + 30), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color.WHITE))


func _add(layer: CanvasLayer, f: Callable) -> void:
	var n := Node2D.new()
	n.draw.connect(f.bind(n))
	layer.add_child(n)
