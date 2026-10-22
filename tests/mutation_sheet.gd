extends SceneTree
## Лист мутаций: каждая мутация — рисованный гаврик и 3D рядом (нужен дисплей, напр. xvfb-run):
##   xvfb-run godot --path . --resolution 1600x1450 -s res://tests/mutation_sheet.gd -- <снимок.png> [поза] [форма] [чёткость листов]

var _out := "user://mutations.png"
var _pose := "idle"
var _shape := CreatureArt.Shape.TRIANGLE
var _models: ModelSprites
var _list := []
var _frame := 0
var _shot_at := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_pose = args[1]
	if args.size() > 2:
		_shape = int(args[2])
	if args.size() > 3:
		ModelSprites.detail = float(args[3])
	var base := {"color": Color(0.2, 0.45, 1.0), "shape": _shape, "eyes": 1, "fingers": 4, "size": 0, "pattern": 0,
		"hair_color": Genetics.HAIR_COLORS[2]}
	for m in [["обычный", {}], ["2 глаза", {"eyes": 2}], ["3 глаза", {"eyes": 3}], ["5 глаз", {"eyes": 5}],
			["без глаз", {"eyes": 0}], ["полосы", {"pattern": 1}], ["пятна", {"pattern": 2}], ["жабры", {"gills": true}],
			["волосы", {"hair": true}], ["рог", {"horn": true}], ["усики", {"antennae": true}], ["панцирь", {"shell": true}],
			["шерсть", {"fur": true}], ["длин. руки", {"long_arms": true}], ["3 пальца", {"fingers": 3}], ["6 пальцев", {"fingers": 6}],
			["светится", {"glow": true}], ["альбинос", {"albino": true}], ["меланист", {"melanist": true}],
			["самка", {"female": true}], ["самка, 2 глаза", {"female": true, "eyes": 2}], ["грустный", {"sad": true}],
			["всё сразу", {"eyes": 2, "pattern": 2, "hair": true, "horn": true, "fur": true, "gills": true}]]:
		var g := base.duplicate()
		g.merge(m[1], true)
		_list.append([m[0], g])
	_models = ModelSprites.new()
	root.add_child(_models)


func _process(_delta: float) -> bool:
	_frame += 1
	if _shot_at < 0 and _models.is_baked:
		var ready := true
		for it in _list:
			ready = ModelSprites.fits(it[1]) and ready
			# Грустное лицо игра заказывает при отрисовке — здесь заранее.
			for l in ModelSprites.layers_of(it[1], it[1].get("sad", false)):
				if not _models.sheets.has(l[0]):
					_models._want(l[0])
					ready = false
		if ready:
			_build()
			_shot_at = _frame + 4
	if _shot_at > 0 and _frame == _shot_at:
		root.get_texture().get_image().save_png(_out)
		# Рядом — сами листы (для разглядывания деталей).
		for key: String in _models.sheets:
			var img: Image = (_models.sheets[key]["tex"] as Texture2D).get_image()
			img.save_png(_out.get_base_dir().path_join("sheet_" + key.replace("/", "_") + ".png"))
		print("saved ", _out, " — ", ModelSprites.status)
		return true
	if _frame > 6000:
		print("не дождались: ", ModelSprites.status)
		return true
	return false


func _build() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.7, 0.85)
	bg.size = Vector2(1600, 1450)
	layer.add_child(bg)
	var cols := 7
	var w := 64.0
	for i in _list.size():
		var g: Dictionary = _list[i][1]
		var x := 90.0 + (i % cols) * 178.0
		var y := 110.0 + (i / cols) * 385.0
		var g2 := g.duplicate()
		g2["pose"] = UnitLayer.POSES.get(_pose, {})
		var pose := _pose + ("|sad" if g.get("sad", false) else "")
		if g.get("sad", false):
			g2["mood"] = -0.6
		_add(layer, func(ci: CanvasItem) -> void: CreatureArt.draw(ci, Vector2(x, y), w, g2, 1.0))
		_add(layer, func(ci: CanvasItem) -> void: ModelSprites.draw_creature(ci, pose, Vector2(x, y + 180), w, g))
		var name: String = _list[i][0]
		_add(layer, func(ci: CanvasItem) -> void: ci.draw_string(ThemeDB.fallback_font, Vector2(x - 70, y + 212), name, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color.WHITE))


func _add(layer: CanvasLayer, f: Callable) -> void:
	var n := Node2D.new()
	n.draw.connect(f.bind(n))
	layer.add_child(n)
