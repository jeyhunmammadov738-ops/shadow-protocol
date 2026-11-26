class_name WeaponSystem
extends RefCounted
## Shadow Protocol - modular weapon system (Phase 3D-9).
##
## Direct port of the web build's src/game/weapons.ts (commit 6458f3b):
## six weapons across six slots, four fire modes, magazine + reserve ammo,
## reload timing, per-mode cooldowns, noise radius, damage, recoil, hip/ADS
## spread, range, suppressed flag, CCTV disable and EMP dart support.
##
## Pure logic: no nodes, no scene access, fully headless-testable. The
## caller owns presentation (muzzle flash, audio, tracer).

enum Mode { SEMI, BURST, AUTO, MELEE }

const SLOT_IDS: Array[StringName] = [
	&"fiveseven", &"p226", &"mp5sd", &"hk416", &"ak47", &"knife",
]

## Ported verbatim from WEAPON_SPECS. Values are the web build's own
## balance numbers; do not retune without changing both projects.
const SPECS: Dictionary = {
	&"fiveseven": {
		"slot": 1, "name": "FN Five-seveN", "short": "FIVE-SEVEN",
		"caliber": "5.7x28mm SUPP", "category": "pistol", "two_handed": false,
		"suppressed": true, "starts_owned": true,
		"mag": 20, "start_reserve": 60, "max_reserve": 120, "drop_ammo": 20,
		"reload": 1.35, "modes": [Mode.SEMI], "default_mode": Mode.SEMI,
		"semi_cd": 0.21, "auto_interval": 0.21, "burst_interval": 0.10,
		"burst_recovery": 0.22, "noise_radius": 62.0, "damage": 1.0,
		"can_disable_cctv": false, "supports_emp": true,
		"recoil_kick": 0.58, "recoil_pitch": 0.011,
		"hip_spread": 0.016, "ads_spread": 0.002, "range": 720.0,
	},
	&"p226": {
		"slot": 2, "name": "SIG Sauer P226", "short": "SIG P226",
		"caliber": "9x19mm TAC", "category": "pistol", "two_handed": false,
		"suppressed": false, "starts_owned": false,
		"mag": 15, "start_reserve": 45, "max_reserve": 90, "drop_ammo": 15,
		"reload": 1.45, "modes": [Mode.SEMI], "default_mode": Mode.SEMI,
		"semi_cd": 0.24, "auto_interval": 0.24, "burst_interval": 0.10,
		"burst_recovery": 0.24, "noise_radius": 235.0, "damage": 1.35,
		"can_disable_cctv": false, "supports_emp": false,
		"recoil_kick": 0.82, "recoil_pitch": 0.018,
		"hip_spread": 0.020, "ads_spread": 0.003, "range": 760.0,
	},
	&"mp5sd": {
		"slot": 3, "name": "HK MP5SD", "short": "MP5SD",
		"caliber": "9x19mm SD", "category": "smg", "two_handed": true,
		"suppressed": true, "starts_owned": false,
		"mag": 30, "start_reserve": 60, "max_reserve": 150, "drop_ammo": 30,
		"reload": 1.65, "modes": [Mode.SEMI, Mode.BURST, Mode.AUTO],
		"default_mode": Mode.BURST,
		"semi_cd": 0.16, "auto_interval": 0.088, "burst_interval": 0.072,
		"burst_recovery": 0.22, "noise_radius": 115.0, "damage": 0.85,
		"can_disable_cctv": false, "supports_emp": false,
		"recoil_kick": 0.48, "recoil_pitch": 0.010,
		"hip_spread": 0.024, "ads_spread": 0.005, "range": 780.0,
	},
	&"hk416": {
		"slot": 4, "name": "HK416 / M416", "short": "HK416",
		"caliber": "5.56x45mm", "category": "rifle", "two_handed": true,
		"suppressed": false, "starts_owned": false,
		"mag": 30, "start_reserve": 60, "max_reserve": 150, "drop_ammo": 30,
		"reload": 1.85, "modes": [Mode.SEMI, Mode.BURST, Mode.AUTO],
		"default_mode": Mode.SEMI,
		"semi_cd": 0.20, "auto_interval": 0.10, "burst_interval": 0.08,
		"burst_recovery": 0.26, "noise_radius": 380.0, "damage": 1.4,
		"can_disable_cctv": true, "supports_emp": false,
		"recoil_kick": 0.86, "recoil_pitch": 0.020,
		"hip_spread": 0.028, "ads_spread": 0.004, "range": 960.0,
	},
	&"ak47": {
		"slot": 5, "name": "AK-47", "short": "AK-47",
		"caliber": "7.62x39mm", "category": "rifle", "two_handed": true,
		"suppressed": false, "starts_owned": false,
		"mag": 30, "start_reserve": 60, "max_reserve": 150, "drop_ammo": 30,
		"reload": 2.05, "modes": [Mode.SEMI, Mode.AUTO], "default_mode": Mode.AUTO,
		"semi_cd": 0.23, "auto_interval": 0.118, "burst_interval": 0.095,
		"burst_recovery": 0.28, "noise_radius": 430.0, "damage": 2.2,
		"can_disable_cctv": true, "supports_emp": false,
		"recoil_kick": 1.0, "recoil_pitch": 0.028,
		"hip_spread": 0.036, "ads_spread": 0.007, "range": 980.0,
	},
	&"knife": {
		"slot": 6, "name": "Tactical Combat Knife", "short": "KNIFE",
		"caliber": "CQC BLADE", "category": "melee", "two_handed": false,
		"suppressed": true, "starts_owned": true,
		"mag": 0, "start_reserve": 0, "max_reserve": 0, "drop_ammo": 0,
		"reload": 0.0, "modes": [Mode.MELEE], "default_mode": Mode.MELEE,
		"semi_cd": 0.42, "auto_interval": 0.42, "burst_interval": 0.42,
		"burst_recovery": 0.42, "noise_radius": 28.0, "damage": 1.0,
		"can_disable_cctv": false, "supports_emp": false,
		"recoil_kick": 0.0, "recoil_pitch": 0.0,
		"hip_spread": 0.0, "ads_spread": 0.0, "range": 68.0,
	},
}

const BURST_COUNT: int = 3

var current_id: StringName = &"fiveseven"
var arsenal: Dictionary = {}     # id -> {owned, ammo, reserve, mode}
var time_since_shot: float = 0.0
var reload_left: float = 0.0
var burst_left: int = 0
var burst_timer: float = 0.0
var shots_fired: int = 0


func _init() -> void:
	reset()


## Fresh mission arsenal: sidearm + knife owned, everything else loot.
func reset() -> void:
	arsenal.clear()
	for id in SLOT_IDS:
		var spec: Dictionary = SPECS[id]
		var owned: bool = bool(spec["starts_owned"])
		arsenal[id] = {
			"owned": owned,
			"ammo": int(spec["mag"]) if owned else 0,
			"reserve": int(spec["start_reserve"]) if owned else 0,
			"mode": int(spec["default_mode"]),
		}
	current_id = &"fiveseven"
	time_since_shot = 99.0
	reload_left = 0.0
	burst_left = 0
	burst_timer = 0.0
	shots_fired = 0


func spec(id: StringName = &"") -> Dictionary:
	return SPECS[id if id != &"" else current_id]


func state(id: StringName = &"") -> Dictionary:
	return arsenal[id if id != &"" else current_id]


func current_mode() -> int:
	return int(state()["mode"])


func mode_label(mode: int = -1) -> String:
	match (current_mode() if mode < 0 else mode):
		Mode.BURST:
			return "3-BURST"
		Mode.AUTO:
			return "AUTO"
		Mode.MELEE:
			return "BLADE"
		_:
			return "SEMI"


func mode_short_label(mode: int = -1) -> String:
	match (current_mode() if mode < 0 else mode):
		Mode.BURST:
			return "3-BST"
		Mode.AUTO:
			return "AUTO"
		Mode.MELEE:
			return "CQC"
		_:
			return "SEMI"


func is_long_gun(id: StringName = &"") -> bool:
	var cat: String = String(spec(id)["category"])
	return cat == "smg" or cat == "rifle"


## Switches to a slot if it is owned. Returns false for locked slots.
func select(id: StringName) -> bool:
	if not arsenal.has(id) or not bool(state(id)["owned"]):
		return false
	if id == current_id:
		return true
	current_id = id
	reload_left = 0.0
	burst_left = 0
	time_since_shot = 99.0
	return true


## Grants a weapon (pickup) with its starting load.
func grant(id: StringName) -> bool:
	if not arsenal.has(id):
		return false
	if bool(state(id)["owned"]):
		return false
	var spec_d: Dictionary = SPECS[id]
	arsenal[id] = {
		"owned": true,
		"ammo": int(spec_d["mag"]),
		"reserve": int(spec_d["start_reserve"]),
		"mode": int(spec_d["default_mode"]),
	}
	return true


func owned_count() -> int:
	var n: int = 0
	for id in SLOT_IDS:
		if bool(state(id)["owned"]):
			n += 1
	return n


func cycle_fire_mode() -> int:
	var modes: Array = spec()["modes"]
	if modes.size() <= 1:
		return current_mode()
	var idx: int = modes.find(current_mode())
	var next: int = int(modes[(idx + 1) % modes.size()])
	state()["mode"] = next
	burst_left = 0
	return next


func is_reloading() -> bool:
	return reload_left > 0.0


func magazine_empty() -> bool:
	return int(state()["ammo"]) <= 0


func reserve_empty() -> bool:
	return int(state()["reserve"]) <= 0


## Starts a reload if one is possible and not already running.
func start_reload() -> bool:
	if is_reloading():
		return false
	var spec_d: Dictionary = spec()
	if String(spec_d["category"]) == "melee":
		return false
	var st: Dictionary = state()
	if int(st["ammo"]) >= int(spec_d["mag"]):
		return false
	if int(st["reserve"]) <= 0:
		return false
	reload_left = float(spec_d["reload"])
	return true


func tick(delta: float) -> void:
	time_since_shot += delta
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left == 0.0:
			_finish_reload()
	if burst_timer > 0.0:
		burst_timer = maxf(0.0, burst_timer - delta)


func _finish_reload() -> void:
	var spec_d: Dictionary = spec()
	var st: Dictionary = state()
	var need: int = int(spec_d["mag"]) - int(st["ammo"])
	var take: int = mini(need, int(st["reserve"]))
	st["ammo"] = int(st["ammo"]) + take
	st["reserve"] = int(st["reserve"]) - take


func _cooldown_for_mode() -> float:
	var spec_d: Dictionary = spec()
	match current_mode():
		Mode.AUTO:
			return float(spec_d["auto_interval"])
		Mode.BURST:
			return float(spec_d["burst_interval"])
		_:
			return float(spec_d["semi_cd"])


func can_fire() -> bool:
	if is_reloading():
		return false
	var spec_d: Dictionary = spec()
	if String(spec_d["category"]) == "melee":
		return time_since_shot >= float(spec_d["semi_cd"])
	if burst_left > 0:
		return burst_timer <= 0.0
	if magazine_empty():
		return false
	return time_since_shot >= _cooldown_for_mode()


## Fires one round (or one burst step). Returns a shot description dict,
## or an empty dict when the trigger does nothing.
func fire() -> Dictionary:
	if not can_fire():
		return {}
	var spec_d: Dictionary = spec()
	var st: Dictionary = state()
	var melee: bool = String(spec_d["category"]) == "melee"
	if not melee:
		st["ammo"] = int(st["ammo"]) - 1
	shots_fired += 1
	time_since_shot = 0.0
	var mode: int = current_mode()
	if mode == Mode.BURST and burst_left == 0:
		burst_left = BURST_COUNT - 1
		burst_timer = float(spec_d["burst_interval"])
	elif burst_left > 0:
		burst_left -= 1
		if burst_left > 0:
			burst_timer = float(spec_d["burst_interval"])
		else:
			burst_timer = float(spec_d["burst_recovery"])
			# Recovery gate: the next burst cannot start immediately.
			time_since_shot = -float(spec_d["burst_recovery"])
	return {
		"weapon": current_id,
		"mode": mode,
		"damage": float(spec_d["damage"]),
		"noise_radius": float(spec_d["noise_radius"]),
		"range": float(spec_d["range"]),
		"suppressed": bool(spec_d["suppressed"]),
		"recoil_kick": float(spec_d["recoil_kick"]),
		"recoil_pitch": float(spec_d["recoil_pitch"]),
		"melee": melee,
		"can_disable_cctv": bool(spec_d["can_disable_cctv"]),
		"supports_emp": bool(spec_d["supports_emp"]),
		"ammo_left": int(st["ammo"]),
	}


## Spread for the current stance; ADS is tighter than hip fire.
func spread(ads: bool = false) -> float:
	var spec_d: Dictionary = spec()
	return float(spec_d["ads_spread"]) if ads else float(spec_d["hip_spread"])


## Ammo box pickup: adds reserve up to the weapon's cap.
func add_reserve(id: StringName, amount: int = -1) -> int:
	if not arsenal.has(id) or not bool(state(id)["owned"]):
		return 0
	var spec_d: Dictionary = SPECS[id]
	var add: int = int(spec_d["drop_ammo"]) if amount < 0 else amount
	var st: Dictionary = state(id)
	var before: int = int(st["reserve"])
	st["reserve"] = mini(int(spec_d["max_reserve"]), before + add)
	return int(st["reserve"]) - before
