extends SceneTree
## Рендер 3D-модели гаврика из art_src (glb) в PNG: спереди, вполоборота и сбоку.
##   xvfb-run godot --path . --resolution 1500x700 -s res://tests/model_preview.gd -- <glb> <png>

var _frame := 0
var _out := "/tmp/model.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://art_src/characters/BlueBuddy.glb")
	if args.size() > 1:
		_out = args[1]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color8(214, 236, 255)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	# Три копии модели: спереди, вполоборота, сбоку.
	for i in 3:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		doc.append_from_file(path, st)
		var model := doc.generate_scene(st) as Node3D
		var stat := model.get_node_or_null("Buddy_FinalBody")
		if stat != null:
			stat.visible = false # статичная копия тела; рисуем тело со скелетом
		model.position = Vector3((i - 1) * 4.0, 0, 0)
		model.rotation_degrees = Vector3(0, [0.0, 35.0, 90.0][i], 0)
		world.add_child(model)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.6
	cam.position = Vector3(0, 1.25, 10)
	world.add_child(cam)
	cam.current = true


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	root.get_texture().get_image().save_png(_out)
	print("рендер: ", _out)
	return true
