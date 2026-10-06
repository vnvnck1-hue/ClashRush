class_name Ai
extends RefCounted
## Opponent buying & placement. Same rules as the player (elixir, 3-card tray, rerolls).

static func deploy(game: Node, team: int) -> void:
	for _iter in 10:
		var shop: Array = game.shop[team]
		var elixir: int = game.elixir[team]
		var done := false
		# 1) upgrades first
		for i in shop.size():
			var k: String = shop[i]
			if k == "":
				continue
			var cost: int = Data.get_def(k)["cost"]
			if cost > elixir:
				continue
			var u: Unit = game.find_upgradable(team, k)
			if u:
				game.buy_upgrade(team, i, u, team == Data.TEAM_ENEMY)
				done = true
				break
		if done:
			continue
		# 2) most expensive affordable, if board has room
		if game.mini_count(team) < 5:
			var best := -1
			var best_cost := -1
			for i in shop.size():
				var k: String = shop[i]
				if k == "":
					continue
				var cost: int = Data.get_def(k)["cost"]
				if cost <= elixir and cost > best_cost:
					best = i
					best_cost = cost
			if best >= 0:
				var tile := choose_tile(game, team, shop[best])
				if tile.x >= 0:
					var nu: Unit = game.buy_place(team, best, tile, team == Data.TEAM_ENEMY)
					if team == Data.TEAM_PLAYER:
						nu.drop_in(1.0)
					continue
		# 3) reroll if nothing useful
		if game.rerolls[team] > 0 and elixir >= 2:
			game.do_reroll(team)
			continue
		break

static func choose_tile(game: Node, team: int, kind: String) -> Vector2i:
	var ranged := Data.is_ranged(kind)
	var rows: Array
	if team == Data.TEAM_ENEMY:
		rows = [6, 7, 5] if ranged else [4, 5, 6]
	else:
		rows = [1, 0, 2] if ranged else [3, 2, 1]
	if kind == "goblin":
		rows = [rows[1], rows[0], rows[2]] if not ranged else rows
	var cols := [2, 1, 3, 0, 4]
	for r in rows:
		cols.shuffle()
		for c in cols:
			var t := Vector2i(c, r)
			if game.unit_at(t) == null:
				return t
	return Vector2i(-1, -1)
