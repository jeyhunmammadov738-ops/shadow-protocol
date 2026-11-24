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

const STATE_PATROL: StringName = &"patrol"
const STATE_SUSPICIOUS: StringName = &"suspicious"
const STATE_INVESTIGATING: StringName = &"investigating"
const STATE_ALERT: StringName = &"alert"
const STATE_SEARCHING: StringName = &"searching"
const STATE_RETURNING: StringName = &"returning"

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
	match state:
		STATE_ALERT:
			return chase_speed
		STATE_INVESTIGATING, STATE_SEARCHING:
			return investigate_speed
		_:
			return patrol_speed


func _physics_process(delta: float) -> void:
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


func _update_visual_state() -> void:
	var state_color: Color = STATE_COLORS.get(state, Color.WHITE)
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
