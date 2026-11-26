class_name Enemy3D
extends CharacterBody3D
## Shadow Protocol - 3D guard AI (Phase 3D-4).
##
## Faithful 3D port of scripts/enemy.gd: the SAME six-state FSM, the same
## exported thresholds, the same suspicion accumulation/decay model, the
## same throttled decision interval (ai_interval) and the same noise
## priority rules. Only the spatial layer changes: Vector3 facing, XZ
## distance for the gameplay model (guards and the player share one floor)
## and a real 3D raycast for line of sight against wall layer 1.
##
## Detection formula (identical to 2D):
##   strength = player.visibility * (1 - 0.5 * clamp(dist / range, 0, 1))
##   with a close-range floor inside range * close_range_fraction.
## FOV gate: facing.dot(dir) >= cos(fov/2), plus unobstructed LOS.

signal state_changed(from_state: StringName, to_state: StringName)
## Phase 3D-11: a guard landed a shot on the player.
signal shot_player(damage: float, from_position: Vector3)

const STATE_PATROL: StringName = &"patrol"
const STATE_SUSPICIOUS: StringName = &"suspicious"
const STATE_INVESTIGATING: StringName = &"investigating"
const STATE_ALERT: StringName = &"alert"
const STATE_SEARCHING: StringName = &"searching"
const STATE_RETURNING: StringName = &"returning"
const STATE_DOWNED: StringName = &"downed"

const EYE_HEIGHT: float = 60.0
const CHEST_HEIGHT: float = 45.0
const ARRIVE_DISTANCE: float = 16.0
const DUPLICATE_NOISE_DISTANCE: float = 24.0
const NOISE_REDIRECT_MARGIN: float = 40.0

@export_range(64.0, 2048.0, 1.0) var vision_range: float = 340.0
@export_range(20.0, 360.0, 1.0) var fov_degrees: float = 100.0
@export_range(0.05, 0.9, 0.05) var close_range_fraction: float = 0.25
@export_range(0.0, 1.0, 0.05) var close_range_floor_strength: float = 0.3
@export_range(0.05, 5.0, 0.05) var suspicion_suspicious_threshold: float = 0.3
@export_range(0.1, 10.0, 0.1) var suspicion_alert_threshold: float = 1.0
@export_range(0.1, 10.0, 0.1) var suspicion_gain_per_sec: float = 1.6
@export_range(0.05, 5.0, 0.05) var suspicion_decay_per_sec: float = 0.45
@export_range(0.05, 10.0, 0.05) var lose_target_timeout: float = 0.8
@export_range(0.2, 30.0, 0.1) var search_duration: float = 3.0
@export_range(0.2, 30.0, 0.1) var investigate_timeout: float = 6.0
@export_range(0.1, 10.0, 0.1) var investigate_dwell: float = 1.2
@export_range(0.0, 3.0, 0.1) var hearing_sensitivity: float = 1.0
@export_range(20.0, 400.0, 1.0) var patrol_speed: float = 110.0
@export_range(20.0, 400.0, 1.0) var investigate_speed: float = 140.0
@export_range(20.0, 500.0, 1.0) var chase_speed: float = 210.0
@export_range(0.02, 1.0, 0.01) var ai_interval: float = 0.1

## Benchmark-only counters (mirror the 2D enemy).
static var bench_enabled: bool = false
static var bench_decision_ticks: int = 0
static var bench_noise_reactions: int = 0
static var bench_vision_rays: int = 0

var decision_ticks: int = 0
var state: StringName = STATE_PATROL
var rig = null  # untyped: avoids freed-instance assignment on restart
var suspicion: float = 0.0
var facing: Vector3 = Vector3(0, 0, -1)
var enemy_id: StringName = &"enemy"
var player = null  # duck-typed: Player3D (visibility, global_position, get_rid)
var last_known_player_position: Vector3 = Vector3.ZERO
var last_sound_position: Vector3 = Vector3.ZERO

var _patrol_route: Array[Vector3] = []
var _patrol_index: int = 0
var _target: Vector3 = Vector3.ZERO
var _state_timer: float = 0.0
var _search_center: Vector3 = Vector3.ZERO
var _search_probe_index: int = 0
var _investigation_score: float = 0.0
var _ai_accum: float = 0.0
## Phase 3D-10 combat / squad / cover state.
var hp: float = 3.0
var downed: bool = false
var squad = null   # SquadDirector (RefCounted-safe)
var cover = null   # CoverSystem
var act3: bool = false
var cover_moves: int = 0
var squad_alerts_received: int = 0
var damage_taken: float = 0.0
var _cover_target: Vector3 = Vector3.ZERO
var _cover_timer: float = 0.0
## Phase 3D-11 return fire (new feature, built on existing web primitives).
## Weapon damage is authored on the guard scale (a guard dies at hp 3.0),
## while the player uses a 100-point health pool. This keeps the web balance
## ratios between weapons while making hits meaningful against the player.
const PLAYER_DAMAGE_SCALE: float = 12.0
var weapon_id: StringName = &"hk416"   # web GuardAI default
var reaction_beat: float = 0.32        # web REACTION_BEAT_SEC
var fire_enabled: bool = true
var ammo: int = 30
var reserve: int = 60
var shots_fired: int = 0
var shots_landed: int = 0
var reload_left: float = 0.0
var _fire_cd: float = 0.0
var _burst_left: int = 0
var _burst_timer: float = 0.0
var _reaction_left: float = 0.0
var _had_visual: bool = false
var _suppressor_role: bool = false
var _stealth: Node = null
var _noise_connected: bool = false
var _noise_owner: Node = null

const SEARCH_PROBES: Array[Vector3] = [
	Vector3(96, 0, 0), Vector3(-96, 0, 0), Vector3(0, 0, 96), Vector3(0, 0, -96),
	Vector3(68, 0, 68), Vector3(-68, 0, 68), Vector3(68, 0, -68), Vector3(-68, 0, -68),
]

var STATE_COLORS: Dictionary = {
	STATE_PATROL: Palette.ENEMY_SLATE.darkened(0.25),
	STATE_SUSPICIOUS: Palette.INTERACTIVE.darkened(0.1),
	STATE_INVESTIGATING: Palette.INTERACTIVE,
	STATE_ALERT: Palette.ENEMY_ALERT,
	STATE_SEARCHING: Palette.INTERACTIVE.darkened(0.15),
	STATE_RETURNING: Palette.ENEMY_SLATE,
}

const STATE_GLYPHS: Dictionary = {
	STATE_SUSPICIOUS: "?",
	STATE_INVESTIGATING: "!",
	STATE_ALERT: "!!",
	STATE_SEARCHING: "...",
}


func _ready() -> void:
	if rig == null:
		rig = CharacterRig.build_guard(self)
	_connect_noise()
	_update_visual_state()


func _exit_tree() -> void:
	_disconnect_noise()


## Registers the 3D stealth/noise core (StealthSystem3D).
func set_stealth(system: Node) -> void:
	if system == _stealth:
		return
	_disconnect_noise()
	_stealth = system
	_connect_noise()


func set_player(p: Node) -> void:
	player = p


## Registers the SquadDirector so the guard can share threats.
func set_squad(director) -> void:
	squad = director


## Registers the CoverSystem so the guard can hunker down.
func set_cover_system(system) -> void:
	cover = system


## Act-3 escalation (web commit 88c88f6): tighter, faster patrol behaviour.
func set_act3(active: bool) -> void:
	act3 = active
	if active and _patrol_route.size() > 1:
		# Act 3 revisits every waypoint in reverse as well, so the route
		# closes a loop instead of walking a single line.
		_patrol_index = 0
		_target = _patrol_route[0]


func is_downed() -> bool:
	return downed


func can_be_hit() -> bool:
	return not downed


## Damage entry point. Downed guards stop acting, report to the squad and
## leave a body other guards can notice.
func take_damage(amount: float, source_pos: Vector3 = Vector3.ZERO) -> Dictionary:
	if downed:
		return {"applied": 0.0, "downed": true}
	damage_taken += amount
	hp -= amount
	var was_downed: bool = hp <= 0.0
	if was_downed:
		downed = true
		state = STATE_DOWNED
		velocity = Vector3.ZERO
		if rig != null and rig.has_method("set_downed"):
			rig.set_downed(true)
		_update_visual_state()
		state_changed.emit(STATE_ALERT, STATE_DOWNED)
		if squad != null and squad.has_method("report_downed"):
			squad.report_downed(self)
	else:
		# Being shot points the guard at the shooter even without line of sight.
		last_sound_position = source_pos
		_investigation_score = 999.0
		if state != STATE_ALERT:
			_enter_state(STATE_INVESTIGATING)
	return {"applied": amount, "downed": downed, "hp": hp}


## Radio callout from a squadmate: go alert on the shared threat position.
func receive_squad_alert(position: Vector3, source_id: StringName = &"") -> void:
	if downed or state == STATE_ALERT:
		return
	squad_alerts_received += 1
	last_known_player_position = position
	suspicion = maxf(suspicion, suspicion_alert_threshold)
	_enter_state(STATE_ALERT)


## A body was found nearby: investigate it, never re-report the same body.
func notice_downed_body(position: Vector3) -> void:
	if downed or state == STATE_ALERT:
		return
	last_sound_position = position
	_investigation_score = 500.0
	_enter_state(STATE_INVESTIGATING)


## Flank order from the SquadDirector: approach the threat from cover.
func order_flank(focus: Vector3) -> void:
	if downed:
		return
	if cover != null and cover.has_method("cover_positions"):
		var spots: Array = cover.cover_positions(global_position, focus, 3)
		if spots.size() > 0:
			_cover_target = spots[0]
			_cover_timer = 3.0
			cover_moves += 1
			_target = _cover_target
			return
	last_known_player_position = focus
	_enter_state(STATE_ALERT)


## Assigns a weapon from the shared spec table (never a duplicate copy).
func set_weapon(id: StringName) -> void:
	if not WeaponSystem.SPECS.has(id):
		return
	weapon_id = id
	ammo = int(WeaponSystem.SPECS[id]["mag"])
	reserve = int(WeaponSystem.SPECS[id]["start_reserve"])


func weapon_spec() -> Dictionary:
	return WeaponSystem.SPECS.get(weapon_id, WeaponSystem.SPECS[&"hk416"])


## Squad role from the director: a suppressor holds and fires.
func set_suppressor_role(active: bool) -> void:
	_suppressor_role = active


func is_reloading() -> bool:
	return reload_left > 0.0


## Reaction beat must elapse after first acquiring visual contact, so the
## player always gets a moment to break line of sight.
func reaction_ready() -> bool:
	return _had_visual and _reaction_left <= 0.0


## True when this guard may fire this frame: alive, alert, armed, has LOS,
## target inside the weapon's own range and the reaction beat has passed.
func can_fire_at(target_pos: Vector3) -> bool:
	if downed or not fire_enabled or not alive_check():
		return false
	if state != STATE_ALERT:
		return false
	if is_reloading() or ammo <= 0:
		return false
	if _fire_cd > 0.0 or _burst_timer > 0.0:
		return false
	if not reaction_ready():
		return false
	var spec: Dictionary = weapon_spec()
	if planar_distance(global_position, target_pos) > float(spec["range"]):
		return false
	if not can_see_player():
		return false
	if _guard_in_line(target_pos):
		return false
	return true


func alive_check() -> bool:
	return not downed


## Friendly fire guard: another standing guard close to the firing line.
func _guard_in_line(target_pos: Vector3) -> bool:
	if squad == null or not squad.has_method("alive_guards"):
		return false
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	var length: float = to_target.length()
	if length < 0.001:
		return false
	var dir: Vector3 = to_target / length
	for other in squad.alive_guards():
		if other == self or not is_instance_valid(other):
			continue
		var to_other: Vector3 = other.global_position - global_position
		to_other.y = 0.0
		var along: float = to_other.dot(dir)
		if along <= 8.0 or along >= length:
			continue
		var lateral: float = (to_other - dir * along).length()
		if lateral < 26.0:
			return true
	return false


## Deterministic hit chance from the perception inputs the stealth system
## already produces: closer, lit, moving targets are easier to hit, and the
## cover factors the player hides behind are honoured.
func hit_chance(target_pos: Vector3, cover_factor: float = 1.0) -> float:
	var spec: Dictionary = weapon_spec()
	var dist: float = planar_distance(global_position, target_pos)
	var range_norm: float = clampf(dist / maxf(1.0, float(spec["range"])), 0.0, 1.0)
	var base: float = lerpf(0.82, 0.28, range_norm)
	var strength: float = detection_strength()
	base *= 0.55 + 0.45 * clampf(strength, 0.0, 1.0)
	base *= clampf(cover_factor, 0.35, 1.0)
	return clampf(base, 0.08, 0.92)


## Fires one round at the player. Returns a shot description, or an empty
## dict when the gate refuses (dry, reloading, no LOS, no reaction beat).
func fire_at_player(target_pos: Vector3, cover_factor: float = 1.0,
		roll: float = -1.0) -> Dictionary:
	if not can_fire_at(target_pos):
		return {}
	var spec: Dictionary = weapon_spec()
	ammo -= 1
	shots_fired += 1
	_fire_cd = float(spec["semi_cd"])
	if _burst_left <= 0:
		_burst_left = 2
		_burst_timer = float(spec["auto_interval"])
	else:
		_burst_left -= 1
		_burst_timer = float(spec["auto_interval"])
	if ammo <= 0:
		_start_reload()
	var chance: float = hit_chance(target_pos, cover_factor)
	# Deterministic: a fixed seed sequence, never an unseeded roll.
	var r: float = roll if roll >= 0.0 else _deterministic_roll()
	var landed: bool = r < chance
	if landed:
		shots_landed += 1
		shot_player.emit(float(spec["damage"]) * PLAYER_DAMAGE_SCALE, global_position)
	return {
		"weapon": weapon_id,
		"landed": landed,
		"chance": chance,
		"damage": float(spec["damage"]) * PLAYER_DAMAGE_SCALE if landed else 0.0,
		"noise_radius": float(spec["noise_radius"]),
		"range": float(spec["range"]),
		"suppressed": bool(spec["suppressed"]),
		"from": global_position,
		"ammo_left": ammo,
	}


## Small deterministic PRNG per guard: seeded from its id, advanced per shot.
var _rng_state: int = 0

func _deterministic_roll() -> float:
	if _rng_state == 0:
		_rng_state = abs(String(enemy_id).hash()) | 1
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_rng_state % 1000) / 1000.0


func _start_reload() -> void:
	var spec: Dictionary = weapon_spec()
	if reserve <= 0:
		return
	reload_left = float(spec["reload"])


func _finish_reload() -> void:
	var spec: Dictionary = weapon_spec()
	var need: int = int(spec["mag"]) - ammo
	var take: int = mini(need, reserve)
	ammo += take
	reserve -= take


## Firing bookkeeping, driven from _physics_process.
func _tick_weapon(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_burst_timer = maxf(0.0, _burst_timer - delta)
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left == 0.0:
			_finish_reload()
	var sees: bool = state == STATE_ALERT and can_see_player()
	if sees and not _had_visual:
		# Stagger the beat per guard so a squad never fires on one frame.
		var stagger: float = 0.06 * float(abs(String(enemy_id).hash()) % 3)
		_reaction_left = reaction_beat + stagger
	_had_visual = sees
	if _reaction_left > 0.0:
		_reaction_left = maxf(0.0, _reaction_left - delta)


func set_enemy_id(id: StringName) -> void:
	enemy_id = id


func set_patrol_route(route: Array) -> void:
	_patrol_route.clear()
	for point in route:
		_patrol_route.append(point as Vector3)
	_patrol_index = 0
	if _patrol_route.size() > 0:
		_target = _patrol_route[0]


func current_target() -> Vector3:
	return _target


func patrol_route() -> Array[Vector3]:
	return _patrol_route


func last_known_position() -> Vector3:
	return last_known_player_position


func last_sound_target() -> Vector3:
	return last_sound_position


## Horizontal (XZ) distance: the gameplay plane both actors share.
static func planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------- perception ---

func can_see_player() -> bool:
	return detection_strength() > 0.0


## Detection strength 0..1, formula identical to the 2D enemy.
func detection_strength() -> float:
	if not is_instance_valid(player):
		return 0.0
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = Vector2(to_player.x, to_player.z).length()
	if dist > vision_range:
		return 0.0
	if dist > 0.001:
		var direction := Vector2(to_player.x, to_player.z) / dist
		var facing_xz := Vector2(facing.x, facing.z).normalized()
		var half_fov: float = deg_to_rad(fov_degrees * 0.5)
		if facing_xz.dot(direction) < cos(half_fov) - 1e-6:
			return 0.0
	if _obstructed_to_player():
		return 0.0
	var distance_factor: float = 1.0 - 0.5 * clampf(dist / maxf(vision_range, 1.0), 0.0, 1.0)
	var strength: float = float(player.visibility) * distance_factor
	if dist <= vision_range * close_range_fraction:
		strength = maxf(strength, close_range_floor_strength)
	return clampf(strength, 0.0, 1.0)


## 3D physics raycast against wall layer 1 (eye -> chest). Any solid hit
## means the line of sight is blocked.
func _obstructed_to_player() -> bool:
	var body := player as CollisionObject3D
	if body == null:
		return false
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid(), body.get_rid()]
	if bench_enabled:
		bench_vision_rays += 1
	var from: Vector3 = global_position + Vector3(0, EYE_HEIGHT, 0)
	var to: Vector3 = player.global_position + Vector3(0, CHEST_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	query.hit_from_inside = false
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


# ------------------------------------------------------------ noise events ---

func _connect_noise() -> void:
	if _stealth == null or _noise_connected:
		return
	if _stealth.has_signal("noise_emitted"):
		_stealth.noise_emitted.connect(_on_noise_event)
		_noise_connected = true
		_noise_owner = _stealth


func _disconnect_noise() -> void:
	if _noise_owner == null or not _noise_connected:
		_noise_connected = false
		_noise_owner = null
		return
	if is_instance_valid(_noise_owner) and _noise_owner.has_signal("noise_emitted") \
			and _noise_owner.noise_emitted.is_connected(_on_noise_event):
		_noise_owner.noise_emitted.disconnect(_on_noise_event)
	_noise_connected = false
	_noise_owner = null


## Noise reaction - identical priority rules to the 2D enemy:
##   1. ALERT ignores noise entirely.
##   2. Own-source noise is ignored.
##   3. Out-of-range events are ignored (radial approximation).
##   4. A duplicate investigation target (< 24 units) does not restart.
##   5. A competing stimulus only redirects with a > +40 score margin.
func _on_noise_event(event) -> void:
	if bench_enabled and state != STATE_ALERT and event.source_id != enemy_id:
		bench_noise_reactions += 1
	if downed or state == STATE_DOWNED:
		return
	# Priority rule (web enemyAI): an alerted guard already owns the threat,
	# so sound never redirects it. This keeps the 3D-4 behaviour intact.
	if state == STATE_ALERT:
		return
	if event.source_id == enemy_id:
		return
	var dist: float = planar_distance(global_position, event.position)
	if dist > event.radius * hearing_sensitivity:
		return
	if state == STATE_INVESTIGATING or state == STATE_SEARCHING:
		if planar_distance(event.position, last_sound_position) < DUPLICATE_NOISE_DISTANCE:
			return
		var score: float = event.radius - dist
		if score <= _investigation_score + NOISE_REDIRECT_MARGIN:
			return
	last_sound_position = event.position
	_investigation_score = event.radius - dist
	_enter_state(STATE_INVESTIGATING)


# ------------------------------------------------------ state machine core ---

func _enter_state(new_state: StringName) -> void:
	var old: StringName = state
	var is_redirect: bool = new_state == state
	state = new_state
	_state_timer = 0.0
	match new_state:
		STATE_PATROL:
			_target = _patrol_route[_patrol_index] if _patrol_route.size() > 0 else global_position
		STATE_SUSPICIOUS:
			_target = global_position
		STATE_INVESTIGATING:
			_target = last_sound_position
		STATE_ALERT:
			_target = player.global_position if is_instance_valid(player) else last_known_player_position
		STATE_SEARCHING:
			_search_center = last_known_player_position if old == STATE_ALERT else last_sound_position
			_search_probe_index = 0
			_target = _search_center + SEARCH_PROBES[0]
		STATE_RETURNING:
			_target = _nearest_patrol_point()
	if not is_redirect:
		_update_visual_state()
		state_changed.emit(old, new_state)


## Decision update, executed only on the throttled AI interval.
func _decide(dt: float) -> void:
	if bench_enabled:
		bench_decision_ticks += 1
	if downed:
		return
	# A suppressor holds its position to keep the firing line steady.
	if _suppressor_role and state == STATE_ALERT:
		_target = global_position
	# Hunker-down: while investigating/searching with no visual, use cover.
	if _cover_timer > 0.0:
		_cover_timer -= dt
		if _cover_timer > 0.0:
			return
	if (state == STATE_INVESTIGATING or state == STATE_SEARCHING) and cover != null:
		var strength_now: float = detection_strength()
		if strength_now <= 0.0 and cover.has_method("cover_positions"):
			var spots: Array = cover.cover_positions(global_position, last_sound_position, 2)
			if spots.size() > 0 and planar_distance(spots[0], global_position) > ARRIVE_DISTANCE:
				_target = spots[0]
				_cover_timer = 2.5
				cover_moves += 1
	var strength: float = detection_strength()
	var sees_player: bool = strength > 0.0
	if sees_player:
		last_known_player_position = player.global_position
		suspicion += suspicion_gain_per_sec * strength * dt
		suspicion = clampf(suspicion, 0.0, suspicion_alert_threshold * 2.0)
	else:
		suspicion = maxf(0.0, suspicion - suspicion_decay_per_sec * dt)

	if suspicion >= suspicion_alert_threshold and state != STATE_ALERT:
		_enter_state(STATE_ALERT)

	match state:
		STATE_PATROL:
			if _arrived_at(_target):
				_advance_patrol()
			if suspicion >= suspicion_suspicious_threshold:
				_enter_state(STATE_SUSPICIOUS)
		STATE_SUSPICIOUS:
			if suspicion >= suspicion_alert_threshold:
				_enter_state(STATE_ALERT)
			elif suspicion < suspicion_suspicious_threshold:
				_enter_state(STATE_RETURNING)
		STATE_INVESTIGATING:
			if suspicion >= suspicion_alert_threshold:
				_enter_state(STATE_ALERT)
			elif _arrived_at(last_sound_position):
				if _state_timer >= investigate_dwell:
					_enter_state(STATE_SEARCHING)
			elif _state_timer >= investigate_timeout:
				_enter_state(STATE_SEARCHING)
		STATE_ALERT:
			if is_instance_valid(player):
				if strength > 0.0:
					_target = player.global_position
					_state_timer = 0.0
				else:
					_target = last_known_player_position
					if _state_timer >= lose_target_timeout:
						_enter_state(STATE_SEARCHING)
		STATE_SEARCHING:
			if suspicion >= suspicion_alert_threshold:
				_enter_state(STATE_ALERT)
			elif _arrived_at(_target):
				_search_probe_index = (_search_probe_index + 1) % SEARCH_PROBES.size()
				_target = _search_center + SEARCH_PROBES[_search_probe_index]
			if _state_timer >= search_duration:
				_enter_state(STATE_RETURNING)
		STATE_RETURNING:
			if suspicion >= suspicion_alert_threshold:
				_enter_state(STATE_ALERT)
			elif suspicion >= suspicion_suspicious_threshold:
				_enter_state(STATE_SUSPICIOUS)
			elif _arrived_at(_target):
				_enter_state(STATE_PATROL)


func _advance_patrol() -> void:
	if act3 and _patrol_route.size() > 1 and _patrol_index == _patrol_route.size() - 1:
		_patrol_route.reverse()
		_patrol_index = 0
		_target = _patrol_route[0]
		return
	if _patrol_route.size() == 0:
		_target = global_position
		return
	_patrol_index = (_patrol_index + 1) % _patrol_route.size()
	_target = _patrol_route[_patrol_index]


func _nearest_patrol_point() -> Vector3:
	if _patrol_route.size() == 0:
		return global_position
	var nearest: Vector3 = _patrol_route[0]
	var best: float = planar_distance(global_position, nearest)
	for point: Vector3 in _patrol_route:
		var d: float = planar_distance(global_position, point)
		if d < best:
			best = d
			nearest = point
	return nearest


func _arrived_at(point: Vector3) -> bool:
	return planar_distance(global_position, point) < ARRIVE_DISTANCE


# -------------------------------------------------------- movement + loop ---

func _speed_for_state() -> float:
	var scale: float = 1.18 if act3 else 1.0
	return _base_speed_for_state() * scale


func _base_speed_for_state() -> float:
	match state:
		STATE_ALERT:
			return chase_speed
		STATE_INVESTIGATING, STATE_SEARCHING:
			return investigate_speed
		_:
			return patrol_speed


func _physics_process(delta: float) -> void:
	_animate_rig(delta)
	if downed:
		velocity = Vector3.ZERO
		return
	_tick_weapon(delta)
	_state_timer += delta
	var to_target: Vector3 = _target - global_position
	to_target.y = 0.0
	if to_target.length() > 2.0:
		var desired_velocity: Vector3 = to_target.normalized() * _speed_for_state()
		velocity.x = lerpf(velocity.x, desired_velocity.x, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, desired_velocity.z, clampf(delta * 10.0, 0.0, 1.0))
	else:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	if not is_on_floor():
		velocity.y -= 980.0 * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	move_and_slide()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 5.0:
		facing = horizontal.normalized()
	var cone := get_node_or_null("VisionCone")
	if cone != null:
		cone.rotation.y = atan2(-facing.x, -facing.z)
	_ai_accum += delta
	while _ai_accum >= ai_interval:
		_ai_accum -= ai_interval
		decision_ticks += 1
		_decide(ai_interval)


func _animate_rig(delta: float) -> void:
	if rig == null:
		return
	var speed: float = 0.0 if state == STATE_ALERT and suspicion >= 1.0 else 120.0
	if state == STATE_PATROL or state == STATE_INVESTIGATING:
		speed = 110.0
	rig.animate(delta, speed, false, state == STATE_ALERT)


func _update_visual_state() -> void:
	var state_color: Color = STATE_COLORS.get(state, Color.WHITE)
	if rig != null:
		rig.set_state_color(state_color)
	var body := get_node_or_null("Body") as MeshInstance3D
	if body != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = state_color
		body.material_override = mat
	var visor := get_node_or_null("Visor") as MeshInstance3D
	if visor != null:
		var vmat := StandardMaterial3D.new()
		vmat.albedo_color = Color(1.0, 0.92, 0.55) if state != STATE_ALERT else Color(1.0, 0.35, 0.30)
		vmat.emission_enabled = true
		vmat.emission = vmat.albedo_color
		vmat.emission_energy_multiplier = 1.6
		visor.material_override = vmat
	var cone := get_node_or_null("VisionCone")
	if cone != null and cone.has_method("set_tint"):
		cone.set_tint(state_color)
	var indicator := get_node_or_null("Indicator") as Label3D
	if indicator != null:
		var glyph: String = STATE_GLYPHS.get(state, "")
		indicator.text = glyph
		indicator.visible = not glyph.is_empty()
		indicator.modulate = state_color
