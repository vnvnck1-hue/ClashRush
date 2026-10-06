extends SceneTree
## Headless balance test: 4 bots play the whole stage.

func _init() -> void:
	var heroes := ["king", "queen", "wizard", "cleric"]
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--heroes="):
			heroes = a.substr(9).split(",")
	var map := MapDef.new()
	var slots := []
	for i in 4:
		slots.append({"hero": heroes[i], "name": "Bot%d" % i})
	var sim := Sim.new(map, slots, 12345)
	var bots := []
	for i in 4:
		bots.append(Bot.new(sim, i))
	var dt := 1.0 / 30.0
	var last_wave := -1
	var t := 0.0
	while t < 900.0 and sim.phase != "won" and sim.phase != "lost":
		for i in 4:
			sim.inputs[i] = bots[i].compute(dt)
		sim.step(dt)
		sim.events.clear()
		t += dt
		if sim.wave != last_wave:
			last_wave = sim.wave
			var lv := []
			for h in sim.heroes:
				lv.append("%s:L%d%s" % [h.kind, h.level, "(dead)" if h.dead else ""])
			print("t=%5.1f wave=%d gold=%d lives=%d towers=%d enemies=%d %s" % [t, sim.wave, sim.gold, sim.lives, sim.towers.size(), sim.enemies.size(), " ".join(lv)])
	print("RESULT phase=%s t=%.1f lives=%d gold=%d stats=%s" % [sim.phase, t, sim.lives, sim.gold, sim.stats])
	var lvls := []
	for tw in sim.towers.values():
		lvls.append("%s%d" % [tw.kind.substr(0, 3), tw.level])
	print("towers: ", " ".join(lvls))
	quit()
