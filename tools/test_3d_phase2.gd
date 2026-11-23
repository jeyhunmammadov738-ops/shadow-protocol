extends SceneTree
## Phase 3D-2 headless acceptance test: GridMap generation parity, wall
## collisions, spawn placement and generation performance for all authored
## layouts plus seeded procedural layouts. 2D scenes and level_catalog.gd
## data must stay untouched (main.tscn is loaded and checked read-only).

var _pass: int = 0
var _fail: int = 0
var _main: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _ok(name: String) -> void:
	print("  PASS: " + name)
	_pass += 1


func _bad(name: String) -> void:
	print("  FAIL: " + name)
	_fail += 1


func _check(cond: bool, name: String) -> void:
	if cond:
		_ok(name)
	else:
		_bad(name)


## Independent character census straight from the rows (never from the
## generator's own counters), used as the parity reference.
func _census(rows: Array) -> Dictionary:
	var c := {"floor_shadow": 0, "floor_lit": 0, "wall": 0, "terminal": 0,
		"spawn": 0, "enemy_spawn": 0, "extraction": 0, "door": 0}
	for row in rows:
		for i in range((row as String).length()):
			match (row as String)[i]:
				"0": c["floor_shadow"] += 1
				"1": c["floor_lit"] += 1
				"2": c["wall"] += 1
				"3": c["terminal"] += 1
				"4": c["spawn"] += 1
				"5": c["enemy_spawn"] += 1
				"6": c["extraction"] += 1
				"7": c["door"] += 1
	return c


func _run() -> void:
	print("3D PHASE-2 TEST: starting")
	var cases := [
		{"name": "legacy", "rows": LevelCatalog.LEGACY["rows"], "zones": LevelCatalog.LEGACY["zones"]},
		{"name": "layout_b", "rows": LevelCatalog.LAYOUT_B["rows"], "zones": LevelCatalog.LAYOUT_B["zones"]},
		{"name": "layout_c", "rows": LevelCatalog.LAYOUT_C["rows"], "zones": LevelCatalog.LAYOUT_C["zones"]},
	]
	for seed_value in [7, 42]:
		var descriptor: Dictionary = LevelCatalog.generate_layout(seed_value)
		cases.append({"name": "seed_%d" % seed_value, "rows": descriptor["rows"],
			"zones": descriptor.get("zones", [])})

	for case in cases:
		await _check_case(case)

	await _check_wiring()
	_finish()


func _check_case(case: Dictionary) -> void:
	var label: String = case["name"]
	var rows: Array = case["rows"]
	var gen := LevelGenerator3D.new()
	root.add_child(gen)
	var data: Dictionary = gen.generate(rows, case["zones"])
	await physics_frame
	await physics_frame

	var census: Dictionary = _census(rows)
	var counts: Dictionary = data["counts"]
	var parity_ok: bool = true
	for key in census:
		if int(counts.get(key, -1)) != int(census[key]):
			parity_ok = false
	_check(parity_ok, "%s: cell-count parity with the 2D rows (walls %d, floors %d)" % [
		label, census["wall"], census["floor_shadow"] + census["floor_lit"]])
	_check(int(data["gridmap_cells"]) == rows.size() * (rows[0] as String).length(),
		"%s: GridMap holds one cell per grid position (%d)" % [label, data["gridmap_cells"]])
	_check(int(data["generation_usec"]) < 150000,
		"%s: generation time %d us < 150 ms" % [label, data["generation_usec"]])

	# Spawn: exactly one spawn cell, and the reported spawn sits on it.
	var spawn_cell: Vector2i = data["spawn_cell"]
	var spawn_char: String = (rows[spawn_cell.y] as String)[spawn_cell.x]
	_check(census["spawn"] == 1 and spawn_char == "4",
		"%s: spawn cell %s is the layout's spawn tile" % [label, spawn_cell])
	_check(int(gen.grid.get_cell_item(Vector3i(spawn_cell.x, 0, spawn_cell.y))) >= 0,
		"%s: spawn cell has a GridMap item" % label)

	# Collision: every sampled wall cell blocks, every sampled floor cell
	# supports. Rays come from high above so no body can shadow the hit.
	var space := gen.get_world_3d().direct_space_state
	var wall_ok := true
	var walls: Array = data["wall_cells"].keys()
	for i in range(mini(6, walls.size())):
		var cell: Vector2i = walls[i]
		var centre: Vector3 = gen.cell_to_world(cell)
		var query := PhysicsRayQueryParameters3D.create(
			centre + Vector3(0, 300, 0), centre - Vector3(0, 300, 0), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or absf(float(hit["position"].y) - GridCellLibrary.WALL_HEIGHT) > 1.0:
			wall_ok = false
	_check(wall_ok, "%s: sampled wall cells collide at wall height (%.0f)" % [
		label, GridCellLibrary.WALL_HEIGHT])

	var floor_ok := true
	var floors: Array = data["lit_cells"].keys()
	if floors.is_empty():
		floors = data["door_cells"].keys()
	for i in range(mini(6, floors.size())):
		var cell: Vector2i = floors[i]
		var centre: Vector3 = gen.cell_to_world(cell)
		var query := PhysicsRayQueryParameters3D.create(
			centre + Vector3(0, 300, 0), centre - Vector3(0, 300, 0), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or absf(float(hit["position"].y)) > 1.0:
			floor_ok = false
	_check(floor_ok, "%s: sampled floor cells collide at y = 0" % label)

	# Doors / terminals / extraction parity is already covered by counts;
	# verify the reported world positions are inside the map bounds.
	var inside := true
	for pos in data["terminals"] + data["enemy_spawns"] + [data["extraction"], data["spawn"]]:
		var v: Vector3 = pos
		if v.x < 0.0 or v.z < 0.0 or v.x > data["bounds"].size.x or v.z > data["bounds"].size.z:
			inside = false
	_check(inside, "%s: all marker positions lie inside the level bounds" % label)

	gen.free()


func _check_wiring() -> void:
	var packed: PackedScene = load("res://scenes/main3d.tscn")
	_check(packed != null, "main3d.tscn still loads with the generator wired")
	if packed == null:
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame
	var player: CharacterBody3D = _main.get_node("Player3D")
	var level_root: LevelGenerator3D = _main.get_node("LevelRoot3D")
	var data: Dictionary = _main.level_data
	_check(level_root != null and level_root.grid != null,
		"main3d wires LevelRoot3D to a generated GridMap")
	var spawn_offset: float = Vector2(
		player.global_position.x - data["spawn"].x,
		player.global_position.z - data["spawn"].z).length()
	_check(spawn_offset < 2.0,
		"player spawns on the layout spawn cell (%.1f units off in XZ)" % spawn_offset)
	_check(player.is_on_floor() or player.global_position.y < 2.0,
		"player rests on the generated floor (y = %.2f)" % player.global_position.y)

	# Walk into a wall from the spawn cell: the body must be blocked.
	var rows: Array = LevelCatalog.LEGACY["rows"]
	var spawn_cell: Vector2i = data["spawn_cell"]
	var blocked_dir := Vector2i(0, -1)
	if spawn_cell.y == 0 or (rows[spawn_cell.y - 1] as String)[spawn_cell.x] != "2":
		blocked_dir = Vector2i(-1, 0)
	var start: Vector3 = player.global_position
	player.use_input_override = true
	player.input_override = Vector2(0, -1) if blocked_dir == Vector2i(0, -1) else Vector2(-1, 0)
	for i in range(45):
		await physics_frame
	var moved: Vector3 = player.global_position - start
	var wall_axis: float = absf(moved.z) if blocked_dir == Vector2i(0, -1) else absf(moved.x)
	_check(wall_axis < 60.0, "wall blocks the player at the spawn cell (moved %.1f units)" % wall_axis)
	_check(player.global_position.y < 2.0,
		"player did not fall through the floor while blocked (y = %.2f)" % player.global_position.y)

	# Layout switching through the public API (1/2/3/4 keys use it).
	var switched: Dictionary = _main.load_layout("layout_c")
	_check(int(switched["counts"]["wall"]) > 0 and _main.current_layout == "layout_c",
		"load_layout('layout_c') regenerates a different layout")
	var seeded: Dictionary = _main.load_layout("seed:7")
	_check(int(seeded["gridmap_cells"]) > 0, "load_layout('seed:7') generates a seeded layout")

	# 2D prototype untouched.
	var main2d: PackedScene = load("res://scenes/main.tscn")
	_check(main2d != null, "2D main.tscn still loads alongside the 3D scene")
	if main2d != null:
		var inst: Node = main2d.instantiate()
		_check(inst is Node2D, "2D main root is still Node2D")
		inst.free()
	_main.queue_free()


func _finish() -> void:
	print("3D PHASE-2 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	if _fail == 0:
		print("3D PHASE-2 TEST: all checks passed")
		quit(0)
	else:
		print("3D PHASE-2 TEST: FAILURES PRESENT")
		quit(1)
