extends SceneTree
## Обход интерфейса для проверки дизайна (нужен дисплей, напр. xvfb-run): главное меню, «Миры»,
## экран загрузки, игровые окна (гаврики, постройки, наука, планеты, стройка), карточка гаврика.
##   xvfb-run godot --path . --resolution 1280x720 -s res://tests/ui_tour.gd -- <папка>

var _out := "user://"
var _frame := 0
var _menu: Control
var _main: Node
var _steps: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(_menu)
	_steps = [
		[20, func() -> void: _shot("menu")],
		[22, func() -> void: _menu._open("worlds")],
		[30, func() -> void: _shot("menu_worlds")],
		[32, func() -> void:
			_menu.queue_free()
			root.add_child(LoadingScreen.make())],
		[40, func() -> void: _shot("loading")],
		[42, func() -> void:
			for c in root.get_children():
				if c is LoadingScreen:
					c.queue_free()
			if FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))
			_main = load("res://scenes/main.tscn").instantiate()
			root.add_child(_main)],
		[150, func() -> void: _shot("game")],
		[152, func() -> void: _main.hud.people_pressed.emit()],
		[160, func() -> void: _shot("people")],
		[162, func() -> void:
			_main.hud.hide_info()
			_main.hud.objects_pressed.emit()],
		[170, func() -> void: _shot("objects")],
		[172, func() -> void:
			_main.hud.hide_info()
			_main.hud.science_pressed.emit()],
		[180, func() -> void: _shot("science")],
		[182, func() -> void:
			_main.hud.hide_info()
			_main.hud.worlds_pressed.emit()],
		[190, func() -> void: _shot("planets")],
		[192, func() -> void:
			_main.hud.hide_info()
			_main._select(_main.colony.units[0], null)],
		[200, func() -> void: _shot("unit")],
		[202, func() -> void:
			_main._select(null, null)
			_main.hud._build_btn.button_pressed = true],
		[210, func() -> void: _shot("build")],
	]


func _process(_delta: float) -> bool:
	_frame += 1
	for s in _steps:
		if s[0] == _frame:
			(s[1] as Callable).call()
	return _frame > 212


func _shot(name: String) -> void:
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
