extends SceneTree
## Крупно несколько 3D-гавриков (как в игре, слоями ModelSprites) — разглядеть лицо и тело
## (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1600x900 -s res://tests/model_closeup.gd -- <снимок.png> [форма] [поза]

var _out := "user://closeup.png"
var _shape := CreatureArt.Shape.TRIANGLE
var _pose := "idle"
var _models: ModelSprites
var _list := []
var _frame := 0
var _shot_at := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_shape = int(args[1])
	if args.size() > 2:
		_pose = args[2]
	# Листы чётче обычного: смотрим крупно.
	ModelSprites.detail = 3.0
	var base := {"color": Color(1.0, 0.8, 0.1), "shape": _shape, "eyes": 1, "fingers": 4, "size": 0, "pattern": 0}
	for m in [{}, {"color": Color(0.2, 0.45, 1.0)}, {"eyes": 2, "color": Color(0.3, 0.85, 0.4)},
			{"female": true, "color": Color(0.85, 0.35, 0.9)}, {"sad": true, "color": Color(1.0, 0.5, 0.3)}]:
		var g := base.duplicate()
		g.merge(m, true)
		_list.append(g)
	_models = ModelSprites.new()
	root.add_child(_models)


func _process(_delta: float) -> bool:
	_frame += 1
	if _shot_at < 0 and _models.is_baked:
		var ready := true
		for g in _list:
			ready = ModelSprites.fits(g) and ready
			for l in ModelSprites.layers_of(g, g.get("sad", false)):
				if not _models.sheets.has(l[0]):
					_models._want(l[0])
					ready = false
		if ready:
			_build()
			_shot_at = _frame + 4
	if _shot_at > 0 and _frame == _shot_at:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out, " — ", ModelSprites.status)
		return true
	if _frame > 8000:
		print("не дождались: ", ModelSprites.status)
		return true
	return false


func _build() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.7, 0.85)
	bg.size = Vector2(1600, 900)
	layer.add_child(bg)
	var node := Node2D.new()
	layer.add_child(node)
	node.draw.connect(func() -> void:
		for i in _list.size():
			var g: Dictionary = _list[i]
			var pose: String = _pose + ("|sad" if g.get("sad", false) else "")
			ModelSprites.draw_creature(node, pose, Vector2(130 + i * 255, 700), 175.0, g))
	node.queue_redraw()
