extends SceneTree
## Превью оформления в PNG (нужен дисплей, напр. xvfb-run).
##   xvfb-run godot --path . --resolution 2000x900 -s res://tests/style_preview.gd -- <папка>

var _node: Node2D
var _frame := 0
var _out := "user://"

const SHEETS := ["style_preview"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	# Рисуем 1:1 в пикселях окна, без растяжения базового размера проекта.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_node = Node2D.new()
	_node.set_script(load("res://tests/style_sheet.gd"))
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 3 == 0:
		var i := _frame / 3 - 1
		_save(SHEETS[i])
		if i + 1 >= SHEETS.size():
			return true
		_node.sheet = i + 1
		_node.queue_redraw()
	return false


func _save(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("превью: ", _out.path_join(name + ".png"))
