extends SceneTree
## Ищет стройки, которые стоят без людей, хотя материалы на складе есть, а гаврики без дела.
##   godot --headless --path . -s res://tests/stall_probe.gd -- <seed> <минут> [classic|opening]

const BotPlayer := preload("res://tests/bot_player.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 2024
	var minutes := int(args[1]) if args.size() > 1 else 240
	var world := WorldData.new(WorldGen.new(seed_value))
	var c := Colony.new(world)
	c.start_new(0)
	var bot = BotPlayer.new(c)
	bot.style = args[2] if args.size() > 2 else "opening"
	var t := 0.0
	var think := 0.0
	var since := {}
	var reported := {}
	while t < minutes * 60.0:
		c.update(0.5)
		t += 0.5
		think += 0.5
		bot.t = t
		if think >= 5.0:
			think = 0.0
			bot.think()
		if int(t * 2) % 20 != 0:
			continue
		var idle: Array = c.units.filter(func(u: Unit) -> bool:
			return not u.child and u.task == Unit.Task.NONE and u.state != Unit.State.FALL)
		for p in c.projects:
			var stuck := false
			if not p.paused and c.workers_on(p) == 0 and idle.size() >= 1:
				for k in c.remaining(p):
					if c.inventory.get(k, 0) > 0:
						stuck = true
			if not stuck:
				since.erase(p.id)
				continue
			if not since.has(p.id):
				since[p.id] = t
			if t - since[p.id] < 60.0 or reported.has(p.id):
				continue
			reported[p.id] = true
			print("\n[%.0f мин] СТОИТ %s фаза=%d нужно=%s сейчас=%s принесено=%s blocked='%s' рабочих=%d idle=%d" % [
				t / 60.0, p.title(), p.phase, c.remaining(p), c._needed_now(p), p.delivered, p.blocked, p.workers, idle.size()])
			for u in idle.slice(0, 4):
				var reach := c.pathing.explore(u.cell())
				var dist: Dictionary = reach[1]
				var near = c._near_rect(p.rect, dist)
				var srcs := {}
				for k in c.remaining(p):
					srcs[k] = c._haul_source(k, dist)
				print("  %s роль=%s клетка=%s state=%d рядом=%s источник=%s claimed=%s order=%s" % [
					u.name, c.role_name(u), u.cell(), u.state, near, srcs,
					c.remaining(p).keys().map(func(k): return c._claimed(k)), c._task_order(u)])
				print("    retry=%.1f fails=%d own=%s sat=%.0f обход=%d упёрся=%s склады=%s" % [u.retry, u.idle_fails, c._own_project(u), u.satiety, dist.size(), Pathing.truncated(dist), c.store_rooms().map(func(r): return [r.rect.position, c.held_in(r, "wood"), c._room_stand(r, dist)])])
				if near != null:
					var ok := c._assign(u)
					print("    _assign -> %s task=%d pid=%d key=%s" % [ok, u.task, u.project_id, u.carry_key])
	quit()
