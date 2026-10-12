extends SceneTree
## Рисует карту материалов (1 пиксель = 1 м) для настройки генератора.
##   godot --headless --path . -s res://tests/render_map.gd -- <файл.png> <x0> <y0> <ширина> <высота> [seed]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var path := a[0] if a.size() > 0 else "user://map.png"
	var x0 := int(a[1]) if a.size() > 1 else -300
	var y0 := int(a[2]) if a.size() > 2 else -60
	var w := int(a[3]) if a.size() > 3 else 600
	var h := int(a[4]) if a.size() > 4 else 600
	var s := int(a[5]) if a.size() > 5 else 2024
	var gen := WorldGen.new(s)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var sky := Color(0.58, 0.78, 0.96)
	for x in w:
		for y in h:
			var m := gen.material_at(x0 + x, y0 + y)
			img.set_pixel(x, y, sky if m == Mat.AIR and y0 + y < gen.surface_y(x0 + x) else (Color(0.05, 0.05, 0.05) if m == Mat.AIR else Mat.color(m)))
	img.save_png(path)
	print("карта: ", path)
	quit()
