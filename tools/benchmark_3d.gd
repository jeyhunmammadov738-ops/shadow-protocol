extends SceneTree
## Shadow Protocol - Phase 3D-7 headless 3D benchmark and leak audit.
##
## HONEST LIMITATION: the headless renderer is a dummy, so draw-call and
## FPS numbers are unavailable here. This harness reports structural draw
## discipline (mesh-instance and GridMap counts) and script/physics CPU
## time, never device GPU performance.

const FRAMES: int = 180
var _checks: int = 0
var _fails: int = 0
var _main: Node3D = null


func _initialize() -> void:
	call_deferred("_run")


func _ok(n: String) -> void:
	_checks += 1
	print("  PASS: ", n)


func _bad(n: String) -> void:
	_checks += 1
	_fails += 1
	print("  FAIL: ", n)


func _check(c: bool, n: String) -> void:
	if c:
		_ok(n)
	else:
		_bad(n)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _run() -> void:
	print("3D BENCH: starting")
	_main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(_main)
	await _frames(30)
	var player: CharacterBody3D = _main.player
	player.use_input_override = true

	var budget: int = int(float(FRAMES) / 60.0 * 1000.0)
	await _scenario("steady-state", budget, func() -> void:
		player.input_override = Vector2.ZERO
		await _frames(FRAMES))
	await _scenario("active-movement", budget, func() -> void:
		player.input_override = Vector2(0.6, -0.8)
		await _frames(FRAMES))
	await _scenario("alert-stress", budget, func() -> void:
		_force_alert()
		await _frames(FRAMES))
	await _scenario("interactions", budget, func() -> void:
		player.input_override = Vector2.ZERO
		_touch_objects()
		await _frames(FRAMES))
	await _scenario("restart-cycles", budget, func() -> void:
		var keys: Array = ["legacy", "layout_b", "layout_c", "seed:7"]
		for i in range(keys.size()):
			_main.load_layout(keys[i])
			await _frames(FRAMES / keys.size()))

	_leak_audit()
	_draw_discipline()
	print("3D BENCH: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D BENCH: FAILURES PRESENT")
		quit(1)
	else:
		print("3D BENCH: all checks passed")
		quit(0)


func _scenario(tag: String, budget: int, body: Callable) -> void:
	var t0: int = Time.get_ticks_msec()
	await body.call()
	var ms: int = Time.get_ticks_msec() - t0
	print("3D BENCH[%s]: %d ms wall / %d frames (fixed-step floor %d ms)" % [tag, ms, FRAMES, budget])
	_check(ms < int(budget * 2.5), "%s keeps up with the 60 Hz step (%d ms)" % [tag, ms])


## Puts every guard into ALERT chasing the player: the worst realistic
## AI/vision load the 3D scene can produce.
func _force_alert() -> void:
	for e in _main.enemies():
		if e.player != null:
			e.last_known_player_position = e.player.global_position
		e._enter_state(Enemy3D.STATE_ALERT)


## Exercises the mission-object code paths: terminal completion and a
## door toggle (LAYOUT_C has doors), plus the interaction resolver.
func _touch_objects() -> void:
	if _main.terminals.size() > 0:
		var t = _main.terminals[0]
		t.complete()
	if _main.doors.size() == 0:
		_main.load_layout("layout_c")
	if _main.doors.size() > 0:
		var d = _main.doors[0]
		d.toggle()
		_main.find_interactable()


## Memory/signal/node audit across the restart cycles that just ran.
func _leak_audit() -> void:
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("3D BENCH: objects=%d nodes=%d static-mem=%.1f MB" % [objects, nodes, mem])
	_check(objects < 6000, "object count stays bounded (%d < 6000)" % objects)
	_check(nodes < 2000, "node count stays bounded (%d < 2000)" % nodes)
	_check(mem < 256.0, "static memory stays bounded (%.1f MB < 256 MB)" % mem)
	# Exactly one handler per mission signal, regardless of restart count.
	var dupes: int = 0
	for sig in ["mission_succeeded", "mission_failed", "objective_progress_changed"]:
		if _main.mission.get_signal_connection_list(sig).size() > 1:
			dupes += 1
	_check(dupes == 0, "no duplicated mission signal connections after restarts")
	var expected_enemies: int = (_main.level_data.get("enemy_spawns", []) as Array).size()
	_check(_main.enemies().size() == expected_enemies,
		"guard count matches the active layout (%d)" % _main.enemies().size())
	_check(_main.terminals.size() == _count_char(_main.current_layout, "3"),
		"terminal count matches the active layout (%d)" % _main.terminals.size())


## Draw discipline: one GridMap for the whole level instead of per-cell
## bodies, and a bounded number of mesh instances.
func _draw_discipline() -> void:
	var grids: int = 0
	var meshes: int = 0
	var stack: Array = [_main]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is GridMap:
			grids += 1
		elif n is MeshInstance3D:
			meshes += 1
		stack.append_array(n.get_children())
	print("3D BENCH: gridmaps=%d mesh-instances=%d" % [grids, meshes])
	_check(grids == 1, "level renders through a single GridMap (%d)" % grids)
	_check(meshes < 220, "mesh instances stay within budget (%d < 220)" % meshes)
	_check(_main.enemies().size() > 0, "stress scenario left live guards for the audit")


func _count_char(key: String, ch: String) -> int:
	var descriptor: Dictionary = LevelCatalog.LEGACY
	if key == "layout_b":
		descriptor = LevelCatalog.LAYOUT_B
	elif key == "layout_c":
		descriptor = LevelCatalog.LAYOUT_C
	elif key.begins_with("seed:"):
		descriptor = LevelCatalog.generate_layout(int(key.substr(5)))
	var total: int = 0
	for row in descriptor["rows"]:
		total += (row as String).count(ch)
	return total
