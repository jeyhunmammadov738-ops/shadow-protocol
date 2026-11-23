extends SceneTree
## Phase 3D-5 headless acceptance test: 3D mission objects (terminal, door,
## extraction), MissionManager wiring (2x restricted pressure, 3 s grace),
## interaction priority and clean restarts.

var _pass: int = 0
var _fail: int = 0
var _main: Node = null

class StubGuard:
	extends RefCounted
	var sees: bool = true
	func can_see_player() -> bool:
		return sees

func _initialize() -> void:
	call_deferred("_run")

func _ok(n: String) -> void:
	print("  PASS: ", n); _pass += 1

func _bad(n: String) -> void:
	print("  FAIL: ", n); _fail += 1

func _check(c: bool, n: String) -> void:
	if c: _ok(n)
	else: _bad(n)

func _finish() -> void:
	print("3D PHASE-5 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	if _fail == 0: print("3D PHASE-5 TEST: all checks passed")
	else: print("3D PHASE-5 TEST: FAILURES PRESENT")
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	print("3D PHASE-5 TEST: starting")
	for path in ["res://scenes/terminal3d.tscn", "res://scenes/door3d.tscn", "res://scenes/extraction3d.tscn"]:
		_check(load(path) != null, "%s loads" % path.get_file())
	_main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await physics_frame
	await physics_frame
	_check(_main.mission != null, "main3d owns a MissionManager")
	_check(_main.mission.state == MissionManager.State.ACTIVE, "mission is ACTIVE on load")
	var rows: Array = LevelCatalog.LEGACY["rows"]
	var exp_t: int = 0
	var exp_d: int = 0
	for r in rows:
		exp_t += (r as String).count("3")
		exp_d += (r as String).count("7")
	_check(_main.terminals.size() == exp_t, "one Terminal3D per '3' cell (%d)" % _main.terminals.size())
	_check(_main.doors.size() == exp_d, "one Door3D per '7' cell (%d)" % _main.doors.size())
	_check(_main.extraction != null, "extraction beacon spawned")
	var t0 = _main.terminals[0]
	_check(String(t0.terminal_id) == "terminal_1", "stable terminal id (%s)" % t0.terminal_id)
	var once: Array = []
	t0.completed.connect(func(id): once.append(id))
	_check(t0.complete(), "complete() succeeds the first time")
	_check(not t0.complete(), "duplicate completion is rejected")
	_check(once.size() == 1, "completed signal fires once")

	# --- doors (LAYOUT_C has three) -------------------------------------
	_main.load_layout("layout_c")
	await physics_frame
	await physics_frame
	_check(_main.doors.size() == 3, "LAYOUT_C spawns its three doors (%d)" % _main.doors.size())
	var door = _main.doors[0]
	_check(not door.is_open(), "door starts CLOSED")
	_check(door.collision_layer == 1, "closed door blocks the world layer (movement + LOS)")
	var cell: Vector2i = door.get_cell()
	_check(_main.stealth.is_cell_blocked(cell), "closed door blocks navigation in StealthSystem3D")
	# Ray along both axes: the door sits in a wall gap, so whichever axis is
	# free of wall geometry is the honest LOS probe.
	var probe := func(axis: Vector3) -> Dictionary:
		var from: Vector3 = door.global_position + Vector3(0, 45, 0) - axis * 90.0
		var to: Vector3 = door.global_position + Vector3(0, 45, 0) + axis * 90.0
		return _main.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1))
	var closed_hits: Array = [probe.call(Vector3(0, 0, 1)), probe.call(Vector3(1, 0, 0))]
	var closed_blocks: bool = false
	for h in closed_hits:
		if not h.is_empty() and h.get("collider") == door:
			closed_blocks = true
	_check(closed_blocks, "closed door obstructs a 3D LOS ray")
	var door_signals: Array = []
	door.state_changed.connect(func(open): door_signals.append(open))
	door.toggle()
	await physics_frame
	_check(door.is_open(), "toggle() opens the door")
	_check(door.collision_layer == 0, "open door no longer blocks the world layer")
	_check(not _main.stealth.is_cell_blocked(cell), "open door is passable in navigation")
	var open_hits: Array = [probe.call(Vector3(0, 0, 1)), probe.call(Vector3(1, 0, 0))]
	var still_blocks: bool = false
	for h in open_hits:
		if not h.is_empty() and h.get("collider") == door:
			still_blocks = true
	_check(not still_blocks, "open door lets the LOS ray through")
	_check(door_signals.size() == 1 and door_signals[0] == true, "door emits state_changed(true)")
	door.toggle()
	await physics_frame
	_check(not door.is_open() and door.collision_layer == 1, "door closes again with collision restored")

	# --- extraction beacon visual states --------------------------------
	var ex = _main.extraction
	_check(ex.vis_state == 0, "extraction starts LOCKED")
	ex.set_active(true)
	_check(ex.vis_state == 1, "extraction switches to ACTIVE")
	ex.set_completed()
	_check(ex.vis_state == 2, "extraction switches to DONE")
	ex.set_active(false)
	_check(ex.vis_state == 2, "DONE is terminal (cannot regress to LOCKED)")

	# --- mission success flow -------------------------------------------
	_main.load_layout("legacy")
	await physics_frame
	var mission = _main.mission
	_check(mission.state == MissionManager.State.ACTIVE, "reload restarts the mission ACTIVE")
	var progress: Array = []
	mission.objective_progress_changed.connect(func(done, total): progress.append([done, total]))
	for t in _main.terminals:
		t.complete()
	_check(mission.extraction_available(), "completing every terminal unlocks extraction")
	_check(progress.size() == _main.terminals.size(), "objective progress emitted per terminal (%d)" % progress.size())
	_main.player.global_position = _main.extraction.global_position
	mission.update(0.1, _main.player.global_position, [], _main.level_data.get("zones", []), 48.0, Vector3.ZERO)
	_check(mission.state == MissionManager.State.SUCCEEDED, "reaching extraction with all objectives SUCCEEDS")

	# --- detection pressure: 1x vs restricted 2x, reset, grace ----------
	_main.load_layout("legacy")
	await physics_frame
	mission = _main.mission
	var zones: Array = _main.level_data.get("zones", [])
	_check(zones.size() > 0, "layout carries restricted zones (%d)" % zones.size())
	var guard := StubGuard.new()
	var outside: Vector3 = _main.level_root.cell_to_world(Vector2i(6, 13))
	var zone_rect: Rect2i = zones[0]["rect"]
	var inside: Vector3 = _main.level_root.cell_to_world(zone_rect.position + zone_rect.size / 2)
	mission.detection_timer = 0.0
	mission.update(1.0, outside, [guard], zones, 48.0, Vector3.ZERO)
	var t_out: float = mission.detection_timer
	mission.detection_timer = 0.0
	mission.update(1.0, inside, [guard], zones, 48.0, Vector3.ZERO)
	var t_in: float = mission.detection_timer
	_check(absf(t_out - 1.0) < 1e-4, "open-floor contact fills the timer at 1x (%.2f)" % t_out)
	_check(absf(t_in - 2.0) < 1e-4, "restricted-zone contact fills at 2x (%.2f)" % t_in)
	guard.sees = false
	mission.update(0.5, inside, [guard], zones, 48.0, Vector3.ZERO)
	_check(mission.detection_timer == 0.0, "losing contact resets the timer to zero")
	guard.sees = true
	mission.detection_timer = 0.0
	var fails: Array = []
	mission.mission_failed.connect(func(reason): fails.append(reason))
	for i in range(4):
		mission.update(1.0, outside, [guard], zones, 48.0, Vector3.ZERO)
	_check(mission.state == MissionManager.State.FAILED and fails.size() == 1,
		"sustained contact past the 3 s grace FAILS the mission (%s)" % (fails[0] if fails.size() > 0 else "none"))

	# --- interaction priority -------------------------------------------
	_main.load_layout("legacy")
	await physics_frame
	var target_terminal = _main.terminals[0]
	_main.player.global_position = target_terminal.global_position + Vector3(48, 0, 0)
	await physics_frame
	var found = _main.find_interactable()
	_check(found == target_terminal, "nearest terminal is the interactable target")
	_main.player.global_position = target_terminal.global_position + Vector3(400, 0, 0)
	await physics_frame
	_check(_main.find_interactable() == null, "targets beyond the interaction radius are ignored")
	_main.player.global_position = target_terminal.global_position + Vector3(48, 0, 0)
	target_terminal.complete()
	await physics_frame
	_check(_main.find_interactable() != target_terminal, "completed terminals stop being targets")

	# --- restart cleanliness + layout coverage --------------------------
	var conns_before: int = mission.objective_progress_changed.get_connections().size()
	for key in ["legacy", "layout_b", "layout_c", "seed:7"]:
		_main.load_layout(key)
		await physics_frame
		var desc: Dictionary = LevelCatalog.LEGACY if key == "legacy" else (
			LevelCatalog.LAYOUT_B if key == "layout_b" else (
			LevelCatalog.LAYOUT_C if key == "layout_c" else LevelCatalog.generate_layout(7)))
		var want_t: int = 0
		var want_d: int = 0
		for r in desc["rows"]:
			want_t += (r as String).count("3")
			want_d += (r as String).count("7")
		var all_fresh: bool = true
		for t in _main.terminals:
			if t.is_completed():
				all_fresh = false
		_check(_main.terminals.size() == want_t and _main.doors.size() == want_d and all_fresh,
			"%s: mission objects rebuilt fresh (terminals %d, doors %d)" % [key, _main.terminals.size(), _main.doors.size()])
		_check(_main.mission.state == MissionManager.State.ACTIVE and _main.enemies().size() == _main.level_data["enemy_spawns"].size(),
			"%s: mission ACTIVE and guards respawned (%d)" % [key, _main.enemies().size()])
	var conns_after: int = _main.mission.objective_progress_changed.get_connections().size()
	_check(conns_after == conns_before, "reloads never duplicate signal connections (%d -> %d)" % [conns_before, conns_after])
	_check(load("res://scenes/main.tscn") != null, "2D main.tscn still loads untouched")
	_finish()
