extends Node3D
## Shadow Protocol - 3D scene wiring (Phases 3D-1 .. 3D-5).
##
## Kept fully separate from the 2D prototype: main.tscn and its scripts are
## untouched. Owns the generated level, the 3D stealth core, the guards,
## the mission objects and the shared MissionManager state machine.

const INTERACT_RADIUS: float = 96.0
const CELL_3D: float = 48.0
const EYE_HEIGHT: float = 55.0

@onready var player: CharacterBody3D = $Player3D
@onready var touch_layer: Control = $UI/TouchLayer
@onready var hud: Hud3D = $UI/Hud3D
@onready var _debug_line: Label = $UI/Hud3D/StatusPanel/Margin/Lines/Title

var feedback_manager: FeedbackManager = null
@onready var level_root: LevelGenerator3D = $LevelRoot3D

var current_layout: String = "legacy"
var level_data: Dictionary = {}
## 3D stealth/noise core (Phase 3D-3), owned by this scene.
var stealth: StealthSystem3D = null
## Single authoritative mission state machine (shared with the 2D game).
var mission: MissionManager = null

var terminals: Array = []
var doors: Array = []
var extraction: Node3D = null
## Phase 3D-9 facility layer (cameras, tripwires, props) + weapons + cover.
var facility: Dictionary = {}
var security_cameras: Array = []
var tripwires: Array = []
var facility_props: Array = []
var weapons: WeaponSystem = null
var cover: CoverSystem = null
var alarm_count: int = 0
var _enemies: Array = []
var _level_lights: Array = []


func _ready() -> void:
	if touch_layer != null and player != null:
		touch_layer.crouch_toggled.connect(player.set_touch_crouch)
		touch_layer.sprint_toggled.connect(player.set_touch_sprint)
		touch_layer.interact_pressed.connect(_on_interact)
		# DEVICE FIX (0.2.1): without this the joystick vector never reached
		# Player3D, so the 3D build could not be moved by touch at all.
		player.set_touch_controls(touch_layer)
	stealth = StealthSystem3D.new()
	stealth.name = "StealthSystem3D"
	add_child(stealth)
	if player.has_method("set_stealth"):
		player.set_stealth(stealth)
	weapons = WeaponSystem.new()
	cover = CoverSystem.new()
	feedback_manager = FeedbackManager.new()
	feedback_manager.name = "FeedbackManager"
	add_child(feedback_manager)
	if hud != null:
		hud.bind(self)
	mission = MissionManager.new()
	mission.name = "MissionManager3D"
	add_child(mission)
	mission.zone_provider = Callable(self, "_zone_at_3d")
	mission.mission_state_changed.connect(_on_mission_state_changed)
	mission.objective_progress_changed.connect(_on_objective_progress)
	mission.extraction_availability_changed.connect(_on_extraction_availability)
	mission.mission_succeeded.connect(_on_mission_succeeded)
	mission.mission_failed.connect(_on_mission_failed)
	mission.detection_warning.connect(_on_detection_warning)
	load_layout("legacy")


## Generates a named authored layout ("legacy", "layout_b", "layout_c") or a
## seeded procedural layout ("seed:7") and places the player on its spawn.
## Everything is rebuilt from scratch: guards, mission objects, mission state.
func load_layout(key: String) -> Dictionary:
	var descriptor: Dictionary
	if key.begins_with("seed:"):
		descriptor = LevelCatalog.generate_layout(int(key.substr(5)))
	else:
		match key:
			"layout_b":
				descriptor = LevelCatalog.LAYOUT_B
			"layout_c":
				descriptor = LevelCatalog.LAYOUT_C
			_:
				descriptor = LevelCatalog.LEGACY
	current_layout = key
	level_data = level_root.generate(descriptor["rows"], descriptor.get("zones", []))
	if player != null:
		player.global_position = level_data["spawn"]
		player.velocity = Vector3.ZERO
		_face_open_corridor()
	_configure_stealth()
	_spawn_lights(descriptor)
	_spawn_enemies()
	_spawn_mission_objects()
	_spawn_facility()
	_start_mission()
	return level_data


## Guards currently alive in this scene (tests, future AI tooling).
func enemies() -> Array:
	var alive: Array = []
	for e in _enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			alive.append(e)
	return alive


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: String = OS.get_keycode_string(event.keycode)
	match key:
		"1", "2", "3":
			load_layout({"1": "legacy", "2": "layout_b", "3": "layout_c"}[key])
		"4":
			load_layout("seed:7")
		"E":
			_on_interact()
		"R":
			load_layout(current_layout)


# ------------------------------------------------------------- stealth core ---

## Points the player and the camera down the longest open run from the
## spawn cell and nudges the body half a cell into it, so the start is not
## a corner shot into a wall with a collapsed spring arm (device report).
func _face_open_corridor() -> void:
	if player == null or level_root == null:
		return
	var walls: Dictionary = level_data.get("wall_cells", {})
	var start: Vector2i = level_root.world_to_cell(player.global_position)
	var dirs: Array = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	var best_dir: Vector3 = Vector3(0, 0, -1)
	var best_run: int = -1
	var best_back: int = 0
	for dir: Vector3 in dirs:
		var run: int = 0
		for step in range(1, 5):
			var cell: Vector2i = start + Vector2i(int(dir.x) * step, int(dir.z) * step)
			if walls.has(cell):
				break
			run += 1
		# Room BEHIND matters too: the spring arm collapses against a wall.
		var back: int = 0
		for step in range(1, 4):
			var cell: Vector2i = start - Vector2i(int(dir.x) * step, int(dir.z) * step)
			if walls.has(cell):
				break
			back += 1
		var score: int = run * 2 + back
		if score > best_run:
			best_run = score
			best_dir = dir
			best_back = back
	if best_run <= 0:
		return
	# The body stays exactly on the layout spawn tile (a phase-2 invariant);
	# the camera solves the tight pocket by lifting over the wall instead.
	var yaw_value: float = atan2(-best_dir.x, -best_dir.z)
	player.rotation.y = yaw_value
	var rig: Node = player.get_node_or_null("CameraRig")
	if rig != null:
		rig.yaw = yaw_value
		rig.pitch = -0.34
		if rig.has_method("apply_rotation"):
			rig.apply_rotation()


func _configure_stealth() -> void:
	if stealth == null:
		return
	stealth.clear_doors()
	stealth.configure(
		level_data.get("lit_cells", {}),
		level_data.get("cell_size", CELL_3D),
		level_data.get("origin", Vector3.ZERO),
		level_data.get("wall_cells", {})
	)


func _zone_at_3d(pos: Vector3) -> StringName:
	var cell := Vector2i(int(floor(pos.x / CELL_3D)), int(floor(pos.z / CELL_3D)))
	for zone in level_data.get("zones", []):
		if (zone["rect"] as Rect2i).has_point(cell):
			return zone["id"]
	return &""


# ------------------------------------------------------------------- lights ---

func _spawn_lights(descriptor: Dictionary) -> void:
	for light in _level_lights:
		if is_instance_valid(light):
			light.queue_free()
	_level_lights.clear()
	for lamp: Dictionary in descriptor.get("lights", []):
		var light := LightSource3D.new()
		var p: Vector2 = lamp["pos"]
		light.position = Vector3(p.x, 0.0, p.y)
		light.light_radius = lamp["radius"]
		light.light_intensity = lamp["intensity"]
		add_child(light)
		if stealth != null:
			stealth.register_light(light)
		_level_lights.append(light)
	for ml: Dictionary in descriptor.get("moving_lights", []):
		var moving := MovingLight3D.new()
		var a: Vector2 = ml["a"]
		var b: Vector2 = ml["b"]
		moving.point_a = Vector3(a.x, 0.0, a.y)
		moving.point_b = Vector3(b.x, 0.0, b.y)
		moving.light_radius = ml["radius"]
		moving.light_intensity = ml["intensity"]
		moving.speed = ml["speed"]
		add_child(moving)
		if stealth != null:
			stealth.register_light(moving)
		_level_lights.append(moving)


# ------------------------------------------------------------------- guards ---

func _spawn_enemies() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	var spawns: Array = level_data.get("enemy_spawns", [])
	for i in range(spawns.size()):
		var enemy: Node3D = load("res://scenes/enemy3d.tscn").instantiate()
		enemy.name = "Enemy3D%d" % i
		add_child(enemy)
		enemy.global_position = spawns[i]
		enemy.set_enemy_id(StringName("enemy_%d" % i))
		enemy.set_player(player)
		enemy.set_stealth(stealth)
		enemy.set_patrol_route(_build_patrol_route(spawns[i]))
		_enemies.append(enemy)


## Deterministic BFS expansion (4 steps) + straight-line grid LOS filter.
func _build_patrol_route(spawn_world: Vector3) -> Array:
	var route: Array = []
	var start := Vector2i(int(spawn_world.x / CELL_3D), int(spawn_world.z / CELL_3D))
	var walls: Dictionary = level_data.get("wall_cells", {})
	var frontier: Array = [start]
	var seen: Dictionary = {start: true}
	while frontier.size() > 0 and route.size() < 4:
		var cell: Vector2i = frontier.pop_front()
		if _grid_los(start, cell, walls):
			route.append(level_root.cell_to_world(cell))
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if not seen.has(n) and not walls.has(n):
				seen[n] = true
				frontier.append(n)
	if route.is_empty():
		route.append(spawn_world)
	return route


func _grid_los(a: Vector2i, b: Vector2i, walls: Dictionary) -> bool:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	if steps == 0:
		return true
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var cell := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
		if walls.has(cell):
			return false
	return true


# ---------------------------------------------------------- mission objects ---

func _spawn_facility() -> void:
	_clear_facility()
	facility = FacilityCatalog.build(level_data)
	var size: float = float(level_data.get("cell_size", CELL_3D))
	var origin: Vector3 = level_data.get("origin", Vector3.ZERO)
	var walls: Dictionary = level_data.get("wall_cells", {})
	if cover != null:
		cover.configure(walls, {}, size, origin)
	for cam_def: Dictionary in facility.get("cameras", []):
		var cam := SecurityCamera3D.new()
		cam.name = String(cam_def["id"])
		cam.camera_id = cam_def["id"]
		cam.global_position = (cam_def["pos"] as Vector3) + Vector3(0, 88, 0)
		cam.base_yaw = float(cam_def["base_yaw"])
		cam.sweep_arc = float(cam_def["sweep_arc"])
		cam.sweep_speed = float(cam_def["sweep_speed"])
		cam.view_range = float(cam_def["range"])
		cam.view_fov = float(cam_def["fov"])
		cam.configure(walls, size, origin)
		add_child(cam)
		cam.spotted_player.connect(_on_camera_spotted)
		security_cameras.append(cam)
		var prop := PropFactory.make_security_camera()
		prop.global_position = cam.global_position
		add_child(prop)
		facility_props.append(prop)
	for tw_def: Dictionary in facility.get("tripwires", []):
		var tw := LaserTripwire3D.new()
		tw.name = String(tw_def["id"])
		tw.tripwire_id = tw_def["id"]
		tw.configure(tw_def["a"], tw_def["b"], float(tw_def["cycle_on"]),
			float(tw_def["cycle_off"]), float(tw_def["phase_offset"]))
		add_child(tw)
		tw.tripped.connect(_on_tripwire_tripped)
		tripwires.append(tw)
	for c: Dictionary in facility.get("containers", []):
		var prop := PropFactory.make_hide_container(String(c["kind"]))
		prop.global_position = c["pos"]
		add_child(prop)
		facility_props.append(prop)
	for b: Dictionary in facility.get("breakers", []):
		var prop := PropFactory.make_breaker_box()
		prop.global_position = (b["pos"] as Vector3) + Vector3(0, 60, 0)
		add_child(prop)
		facility_props.append(prop)
	for v: Dictionary in facility.get("vents", []):
		var prop := PropFactory.make_vent_hatch()
		prop.global_position = (v["pos"] as Vector3) + Vector3(0, 46, 0)
		add_child(prop)
		facility_props.append(prop)
	for d: Dictionary in facility.get("decoys", []):
		var prop := PropFactory.make_decoy()
		prop.global_position = d["pos"]
		add_child(prop)
		facility_props.append(prop)
	for bar: Dictionary in facility.get("barricades", []):
		var prop := PropFactory.make_barricade(float(bar["width"]), float(bar["height"]))
		prop.global_position = bar["pos"]
		add_child(prop)
		facility_props.append(prop)


func _clear_facility() -> void:
	for n in security_cameras + tripwires + facility_props:
		if is_instance_valid(n):
			n.queue_free()
	security_cameras.clear()
	tripwires.clear()
	facility_props.clear()
	alarm_count = 0


func _on_camera_spotted() -> void:
	alarm_count += 1
	if feedback_manager != null:
		feedback_manager.play_event(&"warning")
		feedback_manager.request_haptic(60)
	# Cameras feed the same awareness channel guards already use.
	stealth.publish_noise(player.global_position, 320.0, &"camera_alarm", &"alarm",
		{"source": "camera"})


func _on_tripwire_tripped() -> void:
	alarm_count += 1
	if feedback_manager != null:
		feedback_manager.play_event(&"warning")
		feedback_manager.request_haptic(80)
	if mission != null and mission.state == MissionManager.State.ACTIVE:
		mission.detection_timer = mission.detection_grace


## Fires the current weapon: emits stealth noise scaled by the weapon's
## own noise radius and returns the shot description (empty if dry).
func fire_weapon() -> Dictionary:
	if weapons == null or player == null:
		return {}
	var shot: Dictionary = weapons.fire()
	if shot.is_empty():
		return shot
	if stealth != null:
		stealth.publish_noise(player.global_position, float(shot["noise_radius"]),
			&"gunshot", &"alarm", {"weapon": shot["weapon"], "suppressed": shot["suppressed"]})
	if feedback_manager != null:
		feedback_manager.play_event(&"door" if bool(shot["suppressed"]) else &"warning")
	return shot


func _spawn_mission_objects() -> void:
	for t in terminals:
		if is_instance_valid(t):
			t.queue_free()
	for d in doors:
		if is_instance_valid(d):
			d.queue_free()
	if extraction != null and is_instance_valid(extraction):
		extraction.queue_free()
	terminals.clear()
	doors.clear()
	extraction = null

	var terminal_positions: Array = level_data.get("terminals", [])
	for i in range(terminal_positions.size()):
		var term: Node3D = load("res://scenes/terminal3d.tscn").instantiate()
		term.name = "Terminal3D%d" % (i + 1)
		add_child(term)
		term.global_position = terminal_positions[i]
		term.set_terminal_id(StringName("terminal_%d" % (i + 1)))
		term.completed.connect(_on_terminal_completed)
		terminals.append(term)

	var door_cells: Dictionary = level_data.get("door_cells", {})
	var door_keys: Array = door_cells.keys()
	door_keys.sort_custom(func(x, y): return (x.x * 1000 + x.y) < (y.x * 1000 + y.y))
	for cell: Vector2i in door_keys:
		var door: Node3D = load("res://scenes/door3d.tscn").instantiate()
		door.name = "Door3D_%d_%d" % [cell.x, cell.y]
		add_child(door)
		door.global_position = level_root.cell_to_world(cell)
		door.set_cell(cell)
		if stealth != null:
			stealth.register_door(door)
		doors.append(door)

	var ex_pos: Vector3 = level_data.get("extraction", Vector3.ZERO)
	if ex_pos != Vector3.ZERO:
		var beacon: Node3D = load("res://scenes/extraction3d.tscn").instantiate()
		beacon.name = "Extraction3D"
		add_child(beacon)
		beacon.global_position = ex_pos
		beacon.set_active(false)
		extraction = beacon


func _start_mission() -> void:
	if mission == null:
		return
	var payload: Dictionary = {
		"label": current_layout,
		"terminals": terminals,
		"extraction": extraction.global_position if extraction != null else null,
	}
	mission.start_mission(payload, level_data.get("zones", []))


# -------------------------------------------------------------- interaction ---

func _on_interact() -> void:
	var target: Node3D = find_interactable()
	if target == null:
		return
	if target is Terminal3D:
		(target as Terminal3D).complete()
		if feedback_manager != null:
			feedback_manager.play_event(&"terminal")
			feedback_manager.request_haptic(80)
	elif target is Door3D:
		(target as Door3D).toggle()
		if feedback_manager != null:
			feedback_manager.play_event(&"door")
			feedback_manager.request_haptic(50)
	# Extraction success is proximity-driven by MissionManager, not a button.


## Nearest valid interaction target: 3D distance + raycast LOS on the world
## layer (walls and closed doors block). A closed door wins exact ties.
func find_interactable() -> Node3D:
	var eye: Vector3 = player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var best: Node3D = null
	var best_dist: float = INF
	var best_prio: int = 99
	var candidates: Array = []
	for t in terminals:
		if is_instance_valid(t) and not t.is_completed():
			candidates.append([t, 0])
	for d in doors:
		if is_instance_valid(d):
			# Closed doors win ties; an open door can still be closed again.
			candidates.append([d, 1 if not d.is_open() else 2])
	if extraction != null and is_instance_valid(extraction) and mission != null and mission.extraction_available():
		candidates.append([extraction, 0])
	for entry: Array in candidates:
		var node: Node3D = entry[0]
		var prio: int = entry[1]
		var aim: Vector3 = node.global_position + Vector3(0.0, 60.0, 0.0)
		if node.has_method("interaction_position"):
			aim = node.interaction_position()
		var dist: float = player.global_position.distance_to(aim)
		if dist > INTERACT_RADIUS:
			continue
		if not _los_clear(eye, aim, node):
			continue
		var better: bool = dist < best_dist - 0.001
		var tie: bool = absf(dist - best_dist) <= 0.001
		# Priority: objective/extraction (0) > closed door (1) > open door (2).
		if better or (tie and prio < best_prio):
			best = node
			best_dist = dist
			best_prio = prio
	return best


## Contextual prompt text for the HUD ("USE: Open Door" ...). Empty when
## nothing eligible is in range and in line of sight.
func interaction_hint() -> String:
	var target: Node3D = find_interactable()
	if target == null:
		return ""
	if target is Terminal3D:
		return "USE: Hack Terminal" if not (target as Terminal3D).is_completed() else ""
	if target is Door3D:
		return "USE: Open Door" if not (target as Door3D).is_open() else ""
	if target is Extraction3D:
		return "REACH EXTRACTION"
	return ""


func _los_clear(eye: Vector3, aim: Vector3, target: Node) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, aim, 1)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == target


# ------------------------------------------------------------ mission events ---

func _on_terminal_completed(terminal_id: StringName) -> void:
	if mission != null:
		mission.on_terminal_completed(terminal_id)


func _on_objective_progress(done_count: int, total_count: int) -> void:
	pass  # HUD reads the live values each frame


func _on_extraction_availability(available: bool) -> void:
	if extraction != null and is_instance_valid(extraction):
		extraction.set_active(available)


func _on_mission_state_changed(from_state: int, to_state: int) -> void:
	if to_state == MissionManager.State.SUCCEEDED and extraction != null and is_instance_valid(extraction):
		extraction.set_completed()


func _on_detection_warning(_level: int) -> void:
	if feedback_manager != null:
		feedback_manager.play_event(&"warning")
		feedback_manager.request_haptic(40)


func _on_mission_succeeded() -> void:
	if feedback_manager != null:
		feedback_manager.play_event(&"success")
		feedback_manager.request_haptic(250)
	if hud != null:
		hud.show_success(hud.objectives_done, hud.objectives_total)
		hud.set_hud_visible(false)


func _on_mission_failed(reason: String) -> void:
	if feedback_manager != null:
		feedback_manager.play_event(&"failure")
		feedback_manager.request_haptic(180)
	if hud != null:
		hud.show_failure(reason)
		hud.set_hud_visible(false)


# --------------------------------------------------------------------- HUD ---

func _process(delta: float) -> void:
	if weapons != null:
		weapons.tick(delta)
	if player != null and not security_cameras.is_empty():
		for cam in security_cameras:
			if is_instance_valid(cam):
				cam.tick(delta, player.global_position)
	if player != null and not tripwires.is_empty():
		for tw in tripwires:
			if is_instance_valid(tw):
				tw.tick(delta, player.global_position)
	if mission != null and level_data.size() > 0:
		mission.update(delta, player.global_position, _enemies,
			level_data.get("zones", []), CELL_3D, Vector3.ZERO)
	if player == null:
		return
	var objectives: String = "0/0"
	var extraction_text: String = "LOCKED"
	var state_text: String = "READY"
	if mission != null:
		objectives = "%d/%d" % [mission.objectives_done(), mission.objectives_total()]
		extraction_text = "READY" if mission.extraction_available() else "LOCKED"
		match mission.state:
			MissionManager.State.ACTIVE:
				state_text = "ACTIVE"
			MissionManager.State.SUCCEEDED:
				state_text = "SUCCEEDED"
			MissionManager.State.FAILED:
				state_text = "FAILED"
	var rig := player.get_node_or_null("CameraRig")
	var yaw_text: String = "0"
	if rig != null and rig.has_method("get_yaw"):
		yaw_text = str(snappedf(rad_to_deg(rig.get_yaw()), 1.0))
	if _debug_line != null:
		_debug_line.text = "SHADOW PROTOCOL 3D  %s  |  %d FPS  |  yaw %s" % [
			current_layout.to_upper(), Engine.get_frames_per_second(), yaw_text]
