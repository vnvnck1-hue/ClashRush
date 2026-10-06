class_name Data
extends RefCounted
## Unit definitions (data-driven). Numbers follow Clash Mini's "small number" scale.

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

const COL_PLAYER := Color("3fa9f5")
const COL_ENEMY := Color("f0506e")
const COL_GOLD := Color("ffd23f")
const COL_ELIXIR := Color("e040c8")
const COL_SHADOW := Color("3b3570")

const DECK := ["brawler", "archer", "goblin", "wizard", "valkyrie", "giant"]

const UNITS := {
	"king": {
		"name": "King", "hero": true, "cost": 0,
		"hp": 40.0, "dmg": 4.0, "interval": 1.2, "range": 0.95, "speed": 1.3,
		"attack": "melee", "super": "slam", "scale": 1.18,
	},
	"queen": {
		"name": "Queen", "hero": true, "cost": 0,
		"hp": 30.0, "dmg": 3.0, "interval": 1.1, "range": 3.8, "speed": 1.3,
		"attack": "arrow", "super": "volley", "scale": 1.12,
	},
	"brawler": {
		"name": "Brawler", "cost": 2,
		"hp": 16.0, "dmg": 2.0, "interval": 0.9, "range": 0.9, "speed": 1.7,
		"attack": "melee", "passive": "rage", "scale": 1.0,
	},
	"archer": {
		"name": "Archer", "cost": 2,
		"hp": 9.0, "dmg": 2.0, "interval": 1.1, "range": 3.6, "speed": 1.4,
		"attack": "arrow", "target": "farthest", "scale": 0.95,
	},
	"goblin": {
		"name": "Goblin", "cost": 2,
		"hp": 10.0, "dmg": 2.0, "interval": 0.6, "range": 0.85, "speed": 2.5,
		"attack": "melee", "clash": "leap", "scale": 0.85,
	},
	"wizard": {
		"name": "Wizard", "cost": 3,
		"hp": 12.0, "dmg": 2.0, "interval": 1.5, "range": 3.2, "speed": 1.3,
		"attack": "fireball", "splash": 1.0, "scale": 1.0,
	},
	"valkyrie": {
		"name": "Valkyrie", "cost": 3,
		"hp": 20.0, "dmg": 2.0, "interval": 1.2, "range": 0.95, "speed": 1.5,
		"attack": "spin", "splash": 1.1, "scale": 1.02,
	},
	"giant": {
		"name": "Giant", "cost": 4,
		"hp": 34.0, "dmg": 4.0, "interval": 1.6, "range": 0.95, "speed": 0.95,
		"attack": "melee", "clash": "charge", "scale": 1.3,
	},
}

static func get_def(kind: String) -> Dictionary:
	return UNITS[kind]

static func star_mult(star: int) -> float:
	return 1.0 + 0.5 * float(star - 1)

static func is_ranged(kind: String) -> bool:
	return UNITS[kind]["range"] > 1.5
