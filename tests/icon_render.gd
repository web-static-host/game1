extends SceneTree
## Иконка приложения: бирюзовый сверхюнит с одним глазом на тёплом фоне.
##   xvfb-run godot --path . --resolution 512x512 -s res://tests/icon_render.gd -- <папка>

var _node: Node2D
var _frame := 0
var _out := "res://assets/icon"
var _step := 0

const BG_TOP := Color8(255, 196, 92)
const BG_BOTTOM := Color8(244, 116, 52)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_node = Node2D.new()
	_node.draw.connect(_paint)
	root.add_child(_node)


func _paint() -> void:
	var size := root.get_visible_rect().size
	# 0 — иконка целиком, 1 — передний план адаптивной (существо мельче — в безопасной зоне),
	# 2 — фон адаптивной.
	if true:
		_node.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
		# Мягкий свет за спиной.
		var c := size * Vector2(0.5, 0.46)
		for i in 10:
			_node.draw_circle(c, size.x * (0.46 - i * 0.035), Color(1, 0.95, 0.75, 0.06))
	if _step == 2:
		return
	# Адаптивная иконка обрезается кругом/скруглённым квадратом — существо в безопасной зоне.
	var k := 0.62 if _step == 1 else 0.78
	var w := size.x * 0.5 * k
	var g := {"color": CreatureArt.SUPER_A, "shape": CreatureArt.Shape.TRIANGLE, "eyes": 1, "fingers": 4, "size": 0,
		"pattern": 0, "super": true, "female": false, "hair_color": Color8(60, 40, 30),
		"pose": {"arms": [Vector2.ZERO, Vector2(-0.1, -0.7)]}}
	for key in Genetics.DOMINANT + Genetics.RECESSIVE:
		g[key] = false
	var h := CreatureArt.height_of(w, g)
	CreatureArt.draw(_node, Vector2(size.x * 0.5, size.y * 0.5 + h * 0.5), w, g, 0.4)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 3 != 0:
		return false
	var names := ["icon_512.png", "icon_fg_432.png", "icon_bg_432.png"]
	var img := root.get_texture().get_image()
	if _step > 0:
		img.resize(432, 432, Image.INTERPOLATE_LANCZOS)
	img.save_png(_out.path_join(names[_step]))
	print("иконка: ", names[_step])
	_step += 1
	if _step >= names.size():
		return true
	_node.queue_redraw()
	return false
