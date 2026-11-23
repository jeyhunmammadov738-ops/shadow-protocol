extends Node3D
## Shadow Protocol - Phase 3D-1/3D-2 scene wiring (main3d.tscn).
##
## Kept fully separate from the 2D prototype: main.tscn and its scripts are
## untouched. Generates the selected layout with LevelGenerator3D, spawns the
## player on the layout's spawn cell, and connects the shared touch overlay
## (scripts/mobile_controls.gd) to the 3D player.

const LAYOUTS := {
	"1": {"label": "legacy", "index": 0},
	"2": {"label": "layout_b", "index": 1},
	"3": {"label": "layout_c", "index": 2},
}

@onready var player: CharacterBody3D = $Player3D
@onready var touch_layer: Control = $UI/TouchLayer
@onready var level_root: LevelGenerator3D = $LevelRoot3D
@onready var _hud: Label = $UI/HUD

var current_layout: String = "legacy"
## 3D stealth/noise core (Phase 3D-3): owned by this scene, never global.
var stealth: StealthSystem3D = null
var _level_lights: Array = []
var level_data: Dictionary = {}
var _enemies: Array = []


func _ready() -> void:
	if player != null and player.has_method("set_touch_controls"):
		player.set_touch_controls(touch_layer)
	if touch_layer != null and player != null:
		touch_layer.crouch_toggled.connect(player.set_touch_crouch)
		touch_layer.sprint_toggled.connect(player.set_touch_sprint)
		# INTERACT has no 3D target until Phase 3D-5 (terminals/doors).
	stealth = StealthSystem3D.new()
	stealth.name = "StealthSystem3D"
	add_child(stealth)
	if player.has_method("set_stealth"):
		player.set_stealth(stealth)
	load_layout("legacy")


## Generates a named authored layout ("legacy", "layout_b", "layout_c") or a
## seeded procedural layout ("seed:7") and places the player on its spawn.
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
	_configure_stealth()
	_spawn_lights(descriptor)
	_spawn_enemies()
	return level_data


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: String = OS.get_keycode_string(event.keycode)
	match key:
		"1":
			load_layout("legacy")
		"2":
			load_layout("layout_b")
		"3":
			load_layout("layout_c")
		"4":
			load_layout("seed:7")


func _process(_delta: float) -> void:
	if _hud == null or player == null:
		return
	var rig := player.get_node_or_null("CameraRig")
	var yaw_text: String = "0"
	if rig != null and rig.has_method("get_yaw"):
		yaw_text = str(snappedf(rad_to_deg(rig.get_yaw()), 1.0))
	var counts: Dictionary = level_data.get("counts", {})
	_hud.text = "3D %s  |  FPS %d  |  yaw %s°  |  walls %d  |  gen %d µs  |  1/2/3/4 layouts" % [
		current_layout.to_upper(),
		Engine.get_frames_per_second(),
		yaw_text,
		int(counts.get("wall", 0)),
		int(level_data.get("generation_usec", 0)),
	]


## Feeds the generated level into the 3D stealth core (Phase 3D-3).
func _configure_stealth() -> void:
	if stealth == null:
		return
	stealth.configure(
		level_data.get("lit_cells", {}),
		float(level_data.get("cell_size", 48.0)),
		level_data.get("origin", Vector3.ZERO),
		level_data.get("wall_cells", {}))


## Static and moving lamps from layout metadata, registered with the 3D
## stealth core. Gameplay geometry stays on the XZ plane (y = 0) so the
## 2D formula parity holds; the visual lamp sits slightly above the floor.
func _spawn_lights(descriptor: Dictionary) -> void:
	for lamp: Node in _level_lights:
		if is_instance_valid(lamp):
			lamp.queue_free()
	_level_lights.clear()
	for lamp: Dictionary in descriptor.get("lights", []):
		var light := LightSource3D.new()
		var p: Vector2 = lamp["pos"]
		light.position = Vector3(p.x, 0.0, p.y)
		light.light_radius = lamp["radius"]
		light.light_intensity = lamp["intensity"]
		light.set_meta("visual_offset", 60.0)
		add_child(light)
		if stealth != null:
			stealth.register_light(light)
		_level_lights.append(light)
	for ml: Dictionary in descriptor.get("moving_lights", []):
		var moving := MovingLight3D.new()
		moving.light_radius = ml["radius"]
		moving.light_intensity = ml["intensity"]
		var a: Vector2 = ml["a"]
		var b: Vector2 = ml["b"]
		moving.point_a = Vector3(a.x, 0.0, a.y)
		moving.point_b = Vector3(b.x, 0.0, b.y)
		moving.speed = ml["speed"]
		add_child(moving)
		if stealth != null:
			stealth.register_light(moving)
		_level_lights.append(moving)


# ------------------------------------------------------- Phase 3D-4: guards ---

## Spawns one Enemy3D per '5' marker with a deterministic BFS + straight
## line-of-sight patrol route on the XZ grid (no randomness, no physics).
func _spawn_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
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


func enemies() -> Array:
	return _enemies


## Deterministic patrol route: BFS over open XZ cells (4 steps), then up to
## four waypoints chosen farthest-first and filtered by straight-line grid
## line of sight (walls block, doors are passable cells).
func _build_patrol_route(spawn_world: Vector3) -> Array:
	var cell_size: float = level_data["cell_size"]
	var start: Vector2i = Vector2i(int(spawn_world.x / cell_size), int(spawn_world.z / cell_size))
	var walls: Dictionary = level_data["wall_cells"]
	var open_cells: Array[Vector2i] = []
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	for step in range(4):
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: Vector2i = cell + d
				if seen.has(nc) or walls.has(nc):
					continue
				seen[nc] = true
				open_cells.append(nc)
				next.append(nc)
		frontier = next
	var route: Array[Vector3] = [spawn_world]
	var current: Vector2i = start
	var used: Dictionary = {start: true}
	while route.size() < 4 and open_cells.size() > 0:
		var best_cell: Vector2i = Vector2i(-9999, -9999)
		var best_dist: float = -1.0
		for candidate: Vector2i in open_cells:
			if used.has(candidate):
				continue
			if not _grid_los(current, candidate, walls):
				continue
			var dist: float = Vector2(candidate - current).length()
			if dist > best_dist:
				best_dist = dist
				best_cell = candidate
		if best_cell.x == -9999:
			break
		used[best_cell] = true
		current = best_cell
		route.append(Vector3((best_cell.x + 0.5) * cell_size, spawn_world.y, (best_cell.y + 0.5) * cell_size))
	return route


## Grid line-of-sight: samples the segment in quarter-cell steps.
func _grid_los(a: Vector2i, b: Vector2i, walls: Dictionary) -> bool:
	var delta: Vector2 = Vector2(b - a)
	var steps: int = int(maxf(absf(delta.x), absf(delta.y)) * 4.0)
	if steps == 0:
		return true
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var cell: Vector2i = Vector2i(int(round(a.x + delta.x * t)), int(round(a.y + delta.y * t)))
		if walls.has(cell):
			return false
	return true
