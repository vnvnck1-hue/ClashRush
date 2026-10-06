class_name Data
extends RefCounted
## All tunable game data (Kingdom Rush style economy, 5 heroes, 4 towers, 7 enemies, 10 waves).

const COL_GOLD := Color("ffd23f")
const COL_ENEMY := Color("f0506e")
## all players are allies -> ally family only (guide colour system: red = enemy)
const PLAYER_COLORS := [Color("3fa9f5"), Color("2fd6b0"), Color("8fd14f"), Color("b07cff")]
const PLAYER_NAMES := ["P1", "P2", "P3", "P4"]
const LANE_NAMES := ["북", "동", "남", "서"]

const START_GOLD := 500
const START_LIVES := 20
const PREP_TIME := 30.0
const WAVE_GAP := 25.0
const HERO_RESPAWN := 12.0
const SELL_RATIO := 0.6
const SOLDIER_RESPAWN := 10.0
const XP_LEVELS := [0, 150, 380, 700, 1100]
const LEVEL_BONUS := 0.12

# ---------------------------------------------------------------- heroes
const HEROES := {
	"king": {
		"name": "킹", "role": "탱커", "model": "king",
		"hp": 320.0, "armor": 0.3, "speed": 4.6,
		"atk": "cleave", "dmg": 14.0, "interval": 0.75, "range": 1.9, "arc": 120.0, "dtype": "phys",
		"q": {"name": "그라운드 슬램", "cd": 9.0, "desc": "주변 적에게 피해와 기절"},
		"e": {"name": "전투 함성", "cd": 14.0, "desc": "적을 도발하고 받는 피해 감소"},
		"space": {"name": "방패 돌진", "cd": 7.0, "desc": "앞으로 돌진하며 적을 밀쳐냄"},
		"palette": [Color("45b9fd"), Color("6c2ddb"), Color("bbfbfc"), Color("f5f572")],   # ally High
		"blurb": "앞에서 버티며 적을 붙잡는 방패",
	},
	"queen": {
		"name": "퀸", "role": "원거리 딜러", "model": "queen",
		"hp": 180.0, "armor": 0.0, "speed": 5.0,
		"atk": "arrow", "dmg": 12.0, "interval": 0.45, "range": 9.0, "dtype": "phys",
		"q": {"name": "부채 연사", "cd": 7.0, "desc": "조준 방향으로 화살 7발"},
		"e": {"name": "관통 화살", "cd": 8.0, "desc": "일직선의 모든 적을 꿰뚫는 화살"},
		"space": {"name": "구르기", "cd": 5.0, "desc": "빠르게 구르고 다음 3발 강화"},
		"palette": [Color("45b9fd"), Color("4669e1"), Color("bbfbfc"), Color("3de4b4")],   # ally Medium
		"blurb": "멀리서 빠르게 쏘아붙이는 명사수",
	},
	"wizard": {
		"name": "위자드", "role": "광역 마법", "model": "wizard",
		"hp": 160.0, "armor": 0.0, "speed": 4.6,
		"atk": "fireball", "dmg": 16.0, "interval": 0.9, "range": 8.5, "splash": 1.5, "dtype": "magic",
		"q": {"name": "운석", "cd": 12.0, "desc": "조준점에 거대한 운석 낙하"},
		"e": {"name": "화염 폭발", "cd": 9.0, "desc": "주변을 태우고 느리게 만드는 불꽃 고리"},
		"space": {"name": "블링크", "cd": 7.0, "desc": "조준점으로 순간이동"},
		"palette": [Color("b475fe"), Color("6a00c3"), Color("f7edfe"), Color("f5f572")],   # ally Ultra
		"blurb": "무리를 한 번에 날려버리는 불꽃",
	},
	"valkyrie": {
		"name": "발키리", "role": "브루저", "model": "valkyrie",
		"hp": 270.0, "armor": 0.15, "speed": 4.8,
		"atk": "spin", "dmg": 10.0, "interval": 0.85, "range": 1.9, "dtype": "phys",
		"q": {"name": "회오리", "cd": 12.0, "desc": "회전하며 주변을 계속 베기"},
		"e": {"name": "도끼 투척", "cd": 7.0, "desc": "날아갔다 돌아오는 도끼"},
		"space": {"name": "도약 강타", "cd": 8.0, "desc": "조준점으로 뛰어들어 내려찍기"},
		"palette": [Color("51f7fa"), Color("4669e1"), Color("e8feff"), Color("51f7fa")],   # ally Low
		"blurb": "적진 한가운데로 뛰어드는 도끼",
	},
	"cleric": {
		"name": "클레릭", "role": "서포트", "model": "cleric",
		"hp": 190.0, "armor": 0.0, "speed": 4.9,
		"atk": "holy", "dmg": 15.0, "interval": 0.6, "range": 8.5, "dtype": "magic",
		"q": {"name": "치유의 빛", "cd": 14.0, "desc": "주변 영웅과 병사 회복"},
		"e": {"name": "성역", "cd": 12.0, "desc": "적을 느리게 하고 태우는 결계"},
		"space": {"name": "빛의 질주", "cd": 6.0, "desc": "빛이 되어 질주하고 체력 회복"},
		"palette": [Color("7fe0ff"), Color("3d6fe0"), Color("ffffff"), Color("f5f572")],   # ally holy
		"blurb": "동료를 살리고 길을 막는 빛",
	},
}
const HERO_ORDER := ["king", "queen", "wizard", "valkyrie", "cleric"]

# ---------------------------------------------------------------- towers
const TOWERS := {
	"archer": {
		"name": "궁수탑", "cost": [70, 110, 160], "range": [6.5, 7.0, 7.5],
		"dmg": [5.0, 9.0, 13.0], "interval": [0.8, 0.7, 0.6], "dtype": "phys", "air": true,
		"desc": "빠른 단일 물리 공격, 공중 가능",
	},
	"barracks": {
		"name": "병영", "cost": [70, 110, 150], "range": [3.6, 3.8, 4.0],
		"soldier_hp": [50.0, 80.0, 120.0], "dmg": [3.0, 5.0, 8.0], "armor": [0.0, 0.15, 0.3],
		"interval": [1.0, 0.95, 0.9], "dtype": "phys",
		"desc": "병사 3명이 길을 막음",
	},
	"mage": {
		"name": "마법탑", "cost": [100, 160, 240], "range": [6.0, 6.5, 7.0],
		"dmg": [12.0, 22.0, 36.0], "interval": [1.5, 1.4, 1.3], "dtype": "magic", "air": true,
		"desc": "방어를 무시하는 마법 공격",
	},
	"artillery": {
		"name": "대포", "cost": [125, 220, 320], "range": [7.0, 7.5, 8.0],
		"dmg": [10.0, 18.0, 30.0], "splash": [1.6, 1.8, 2.0], "interval": [3.0, 2.8, 2.6],
		"dtype": "phys", "pierce": 0.5, "air": false,
		"desc": "느리지만 강력한 광역 포격 (지상만)",
	},
}
const TOWER_ORDER := ["archer", "barracks", "mage", "artillery"]

# ---------------------------------------------------------------- enemies
const ENEMIES := {
	"goblin": {"name": "고블린", "hp": 20.0, "speed": 2.6, "armor": 0.0, "mr": 0.0, "gold": 3, "lives": 1, "dmg": 2.0, "interval": 1.0, "scale": 1.0},
	"orc": {"name": "오크", "hp": 60.0, "speed": 1.8, "armor": 0.3, "mr": 0.0, "gold": 8, "lives": 1, "dmg": 5.0, "interval": 1.1, "scale": 1.15},
	"wolf": {"name": "늑대", "hp": 35.0, "speed": 4.0, "armor": 0.0, "mr": 0.0, "gold": 6, "lives": 1, "dmg": 3.0, "interval": 0.8, "scale": 1.1},
	"shaman": {"name": "샤먼", "hp": 45.0, "speed": 1.8, "armor": 0.0, "mr": 0.85, "gold": 10, "lives": 1, "dmg": 2.0, "interval": 1.2, "scale": 1.0, "heal": true},
	"bat": {"name": "박쥐", "hp": 40.0, "speed": 2.8, "armor": 0.0, "mr": 0.0, "gold": 7, "lives": 1, "dmg": 0.0, "interval": 1.0, "scale": 1.0, "fly": true},
	"darkknight": {"name": "흑기사", "hp": 150.0, "speed": 1.4, "armor": 0.7, "mr": 0.0, "gold": 18, "lives": 2, "dmg": 10.0, "interval": 1.3, "scale": 1.2},
	"ogre": {"name": "오우거", "hp": 1500.0, "speed": 1.0, "armor": 0.2, "mr": 0.2, "gold": 200, "lives": 5, "dmg": 40.0, "interval": 2.2, "scale": 2.0, "boss": true},
}

# ---------------------------------------------------------------- waves
## Each wave: list of groups [kind, count, spacing_seconds, start_delay]. Applied to every lane,
## with per-lane variation from LANE_EXTRA so lanes feel different.
const WAVES := [
	[["goblin", 6, 1.1, 0.0]],
	[["goblin", 6, 1.0, 0.0], ["orc", 2, 2.0, 6.0]],
	[["orc", 4, 1.6, 0.0], ["wolf", 3, 0.8, 7.0]],
	[["goblin", 8, 0.7, 0.0], ["shaman", 2, 2.0, 4.0], ["orc", 3, 1.5, 7.0]],
	[["bat", 5, 1.0, 0.0], ["orc", 4, 1.5, 4.0]],
	[["darkknight", 2, 3.0, 0.0], ["goblin", 8, 0.6, 3.0], ["shaman", 2, 2.0, 8.0]],
	[["wolf", 8, 0.6, 0.0], ["orc", 5, 1.2, 5.0], ["bat", 4, 1.0, 9.0]],
	[["darkknight", 4, 2.2, 0.0], ["shaman", 3, 1.5, 5.0], ["orc", 6, 1.0, 9.0]],
	[["bat", 6, 0.8, 0.0], ["darkknight", 2, 2.5, 4.0], ["wolf", 6, 0.6, 9.0], ["orc", 5, 1.2, 13.0]],
	[["orc", 5, 1.2, 0.0], ["darkknight", 2, 2.5, 5.0], ["ogre", 1, 1.0, 10.0], ["goblin", 8, 0.6, 14.0]],
]
## lane-specific seasoning (index = lane), extra groups appended from wave 3 on
const LANE_EXTRA := [
	["goblin", 3, 0.8, 9.0],
	["wolf", 2, 0.7, 9.0],
	["orc", 1, 1.0, 9.0],
	["bat", 2, 1.0, 9.0],
]

static func hero_stat_mult(level: int) -> float:
	return 1.0 + LEVEL_BONUS * float(level - 1)

static func level_for_xp(xp: float) -> int:
	var lv := 1
	for i in XP_LEVELS.size():
		if xp >= XP_LEVELS[i]:
			lv = i + 1
	return lv

static func tower_total_cost(kind: String, level: int) -> int:
	var c: Array = TOWERS[kind]["cost"]
	var t := 0
	for i in level:
		t += int(c[i])
	return t
