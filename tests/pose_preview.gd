extends SceneTree
## Все позы гаврика (ModelSprites.POSES) для проверки модели до того, как класть её в игру:
## модель .glb грузится с диска, позы ставятся так же, как в игре; тело — синее.
##   xvfb-run godot --path . --resolution 1500x1000 -s res://tests/pose_preview.gd -- <модель.glb> <снимок.png>

var _frame := 0
var _out := "user://poses.png"
var _todo := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://assets/models/blue_buddy.glb"
	if args.size() > 1:
		_out = args[1]
	# Модель — как в игре: PackedScene и новый экземпляр на позу (duplicate() теряет привязку к скелету).
	var scene: PackedScene
	if path.begins_with("res://"):
		scene = load(path)
	else:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(path, st) != OK:
			push_error("не открыть " + path)
			quit(1)
			return
		scene = PackedScene.new()
		var gen := doc.generate_scene(st)
		for n in gen.find_children("*", "", true, false):
			n.owner = gen
		scene.pack(gen)
	var names: Array = ModelSprites.POSES.keys()
	var cols := 6
	var rows := ceili(names.size() / float(cols))
	var span := ModelSprites.SPAN
	var w := cols * span
	var h := rows * span
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.82, 0.84)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.environment.ambient_light_energy = 0.55
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.1
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.45
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h
	cam.position = Vector3(0, 0, 20)
	world.add_child(cam)
	cam.current = true
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.2, 0.45, 0.95)
	blue.roughness = 0.6
	for i in names.size():
		var pose: Dictionary = ModelSprites.POSES[names[i]]
		var model: Node3D = scene.instantiate()
		world.add_child(model)
		model.position = Vector3(-w * 0.5 + (i % cols + 0.5) * span, h * 0.5 - (i / cols + 1) * span + ModelSprites.FOOT, 0)
		model.rotation_degrees.y = ModelSprites.YAW
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		_todo.append([skel, pose.get("bones", [])])
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			# Закрытый глаз — как в игре: белок цвета тела (веко), зрачка нет; ресницы игра дорисовывает.
			if mi.name == "Buddy_FinalBody" or (pose.get("closed", false) and mi.name == "Approved_EyeWhite"):
				mi.material_override = blue
			elif pose.get("closed", false) and mi.name in ModelSprites.FACE_PARTS:
				mi.visible = false
		var label := Label3D.new()
		label.text = names[i]
		label.pixel_size = 0.01
		label.modulate = Color.BLACK
		label.position = model.position + Vector3(0, -0.25, 1)
		world.add_child(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		# Позы — когда сцена уже в дереве (раньше скелет их сбрасывает).
		for t in _todo:
			ModelSprites.pose_skeleton(t[0], t[1])
	if _frame == 8:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
