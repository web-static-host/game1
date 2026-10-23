extends SceneTree
## Загружает сохранение игрока и смотрит, почему стройки стоят:
##   godot --headless --path . -s res://tests/save_probe.gd -- <путь к .json> [секунд]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var data = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var world := WorldData.new(WorldGen.new(int(data["seed"]), int(data.get("gen", 1))))
	var c := Colony.new(world)
	SaveSystem.apply(data, world, c)
	var secs := float(args[1]) if args.size() > 1 else 120.0
	print("жителей %d, home %s, склад: %s" % [c.units.size(), c.home, c.store_rooms().map(func(r): return [r.id, r.rect, r.held, r.store_off, r.paused])])
	var t := 0.0
	while t < secs:
		c.update(0.5)
		t += 0.5
		if fmod(t, 30.0) == 0.0:
			for p in c.projects:
				if p.paused or (p.phase == Project.Phase.DONE and not p.repairing):
					continue
				print("[%.0f] #%d %s фаза=%d принесено=%s осталось=%s рабочих=%d/%d blocked='%s'" % [t, p.id, p.title(), p.phase, p.delivered, c.remaining(p), c.workers_on(p), p.workers, p.blocked])
	print("--- гаврики:")
	for u in c.units:
		if u.child:
			continue
		var reach := c.pathing.explore(u.cell())
		print("%s роль=%s клетка=%s task=%d state=%d лестница=%s обход=%d" % [u.name, c.role_name(u), u.cell(), u.task, u.state, c.pathing.climbable(u.cell()), reach[1].size()])
	quit()
