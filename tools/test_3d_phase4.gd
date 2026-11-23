extends SceneTree
## Phase 3D-4 headless acceptance test: Enemy3D FSM, 3D vision cone with
## raycast LOS, noise priority rules, patrol determinism, 8-enemy stress
## and main3d integration. The 2D prototype must stay untouched.

var _pass: int = 0
var _fail: int = 0


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


func _make_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 20, 4000)
	shape.shape = box
	shape.position = Vector3(0, -10, 0)
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	return floor_body


func _make_wall(pos: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(48, 160, 48)
	shape.shape = box
	shape.position = Vector3(0, 80, 0)
	wall.add_child(shape)
	wall.position = pos
	wall.collision_layer = 1
	return wall


func _run() -> void:
	print("3D PHASE-4 TEST: starting")
	var scene: PackedScene = load("res://scenes/enemy3d.tscn")
	_check(scene != null, "enemy3d.tscn loads")
	if scene == null:
		_finish()
		return

	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_make_floor())
	var enemy = scene.instantiate()
	world.add_child(enemy)
	enemy.global_position = Vector3(0, 1, 0)
	var player: Node3D = load("res://scenes/player3d.tscn").instantiate()
	world.add_child(player)
	player.global_position = Vector3(0, 1, -200)
	player.visibility = 1.0
	enemy.set_player(player)
	await physics_frame
	await physics_frame

	# --- FSM contract -------------------------------------------------------
	var states: Array = [Enemy3D.STATE_PATROL, Enemy3D.STATE_SUSPICIOUS, Enemy3D.STATE_INVESTIGATING,
		Enemy3D.STATE_ALERT, Enemy3D.STATE_SEARCHING, Enemy3D.STATE_RETURNING]
	_check(states.size() == 6, "six FSM states are defined")
	_check(enemy.fov_degrees == 100.0 and enemy.vision_range == 340.0, "FOV 100 deg and range 340 preserved")
	_check(enemy.suspicion_suspicious_threshold == 0.3 and enemy.suspicion_alert_threshold == 1.0,
		"suspicion thresholds 0.3 / 1.0 preserved")
	_check(enemy.ai_interval == 0.1, "ai_interval throttling preserved (0.1 s)")

	# --- Vision: front / behind / range / LOS -------------------------------
	enemy.facing = Vector3(0, 0, -1)
	var front: float = enemy.detection_strength()
	_check(front > 0.0, "player in front within range is detected (%.3f)" % front)
	enemy.facing = Vector3(0, 0, 1)
	_check(enemy.detection_strength() == 0.0, "player behind the guard is not detected")
	enemy.facing = Vector3(0, 0, -1)
	player.global_position = Vector3(0, 1, -400)
	_check(enemy.detection_strength() == 0.0, "player beyond vision range is not detected")
	player.global_position = Vector3(0, 1, -200)
	_check(enemy.detection_strength() > 0.0, "player back in range is detected again")
	player.visibility = 0.0
	_check(enemy.detection_strength() == 0.0, "zero player visibility means no detection")
	player.visibility = 1.0
	var wall := _make_wall(Vector3(0, 0, -100))
	world.add_child(wall)
	await physics_frame
	await physics_frame
	_check(enemy.detection_strength() == 0.0, "3D wall blocks line of sight (raycast LOS)")
	wall.queue_free()
	await physics_frame
	await physics_frame
	_check(enemy.detection_strength() > 0.0, "LOS restored after the wall is removed")

	# --- FSM: patrol -> suspicious -> alert -> searching -> returning -------
	enemy.set_patrol_route([Vector3(0, 1, 0), Vector3(0, 1, -100)])
	enemy.state = Enemy3D.STATE_PATROL
	enemy.suspicion = 0.0
	var transitions: Array = []
	enemy.state_changed.connect(func(from_s, to_s): transitions.append(String(to_s)))
	enemy._decide(0.1)
	_check(enemy.suspicion > 0.0, "visible player accumulates suspicion")
	for i in range(30):
		enemy._decide(0.1)
	_check(enemy.state == Enemy3D.STATE_ALERT, "suspicion drives PATROL -> ALERT (state=%s)" % enemy.state)
	_check(transitions.has("alert"), "state_changed emitted for ALERT")
	# Lose sight: ALERT -> SEARCHING after lose_target_timeout
	player.global_position = Vector3(2000, 1, 2000)
	enemy.suspicion = 0.0
	for i in range(20):
		enemy._state_timer += 0.1
		enemy._decide(0.1)
	_check(enemy.state == Enemy3D.STATE_SEARCHING, "ALERT -> SEARCHING after losing the target (state=%s)" % enemy.state)
	enemy._state_timer = 0.0
	for i in range(40):
		enemy._state_timer += 0.1
		enemy._decide(0.1)
		if enemy.state == Enemy3D.STATE_RETURNING:
			break
	_check(enemy.state == Enemy3D.STATE_RETURNING or transitions.has("returning"),
		"SEARCHING -> RETURNING after search_duration (state=%s)" % enemy.state)
	# RETURNING -> PATROL once back on route
	enemy.global_position = enemy._nearest_patrol_point()
	enemy._target = enemy.global_position
	enemy.suspicion = 0.0
	enemy._decide(0.1)
	_check(enemy.state == Enemy3D.STATE_PATROL, "RETURNING -> PATROL on arrival (state=%s)" % enemy.state)

	# --- Noise priority rules ----------------------------------------------
	var stealth := StealthSystem3D.new()
	world.add_child(stealth)
	enemy.set_stealth(stealth)
	await physics_frame
	var ev := NoiseEvent3D.new()
	ev.position = enemy.global_position + Vector3(100, 0, 0)
	ev.radius = 220.0
	ev.source_id = &"player"
	ev.movement_state = &"walking"
	stealth.emit_signal("noise_emitted", ev)
	await physics_frame
	_check(enemy.state == Enemy3D.STATE_INVESTIGATING, "in-range noise triggers INVESTIGATING (state=%s)" % enemy.state)
	var before: Vector3 = enemy.last_sound_target()
	var dup := NoiseEvent3D.new()
	dup.position = before + Vector3(5, 0, 0)
	dup.radius = 220.0
	dup.source_id = &"player"
	stealth.emit_signal("noise_emitted", dup)
	await physics_frame
	_check(enemy.last_sound_target().distance_to(before) < 0.01, "duplicate noise target does not reset the investigation")
	var weak := NoiseEvent3D.new()
	weak.position = before + Vector3(0, 0, 300)
	weak.radius = 60.0
	weak.source_id = &"player"
	stealth.emit_signal("noise_emitted", weak)
	await physics_frame
	_check(enemy.last_sound_target().distance_to(before) < 0.01, "weaker competing noise (below +40 margin) is ignored")
	enemy.state = Enemy3D.STATE_ALERT
	var alert_pos: Vector3 = enemy.last_sound_target()
	var loud := NoiseEvent3D.new()
	loud.position = before + Vector3(0, 0, 120)
	loud.radius = 320.0
	loud.source_id = &"player"
	stealth.emit_signal("noise_emitted", loud)
	await physics_frame
	_check(enemy.state == Enemy3D.STATE_ALERT and enemy.last_sound_target() == alert_pos,
		"ALERT ignores noise entirely")
	enemy.set_stealth(null)
	enemy._disconnect_noise()
	_check(not enemy._noise_connected, "noise subscription disconnects cleanly")
	world.queue_free()
	await physics_frame

	# --- main3d integration + patrol determinism ---------------------------
	var main_scene: PackedScene = load("res://scenes/main3d.tscn")
	_check(main_scene != null, "main3d.tscn loads")
	var main = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	await physics_frame
	var enemies: Array = main.enemies()
	var expected: int = main.level_data["enemy_spawns"].size()
	_check(enemies.size() == expected and expected > 0, "one Enemy3D per layout spawn marker (%d)" % enemies.size())
	var route_a: Array = main._build_patrol_route(main.level_data["enemy_spawns"][0])
	var route_b: Array = main._build_patrol_route(main.level_data["enemy_spawns"][0])
	_check(route_a.size() == route_b.size() and route_a == route_b, "patrol route generation is deterministic")
	_check(route_a.size() >= 2, "patrol route has waypoints (%d)" % route_a.size())
	var wired: bool = enemies[0].player != null and enemies[0]._stealth != null
	_check(wired, "enemies are wired to the player and the 3D stealth core")

	# --- 8-enemy stress / frame budget ------------------------------------
	# Two stable metrics (TIME_PHYSICS_PROCESS is unreliable headless):
	#  (a) direct AI decision cost: 8 enemies x 20 throttled decisions
	#  (b) the whole 240-frame loop completes inside a generous wall bound
	var stress: Array = []
	for i in range(8):
		var extra = load("res://scenes/enemy3d.tscn").instantiate()
		main.add_child(extra)
		extra.global_position = Vector3(100.0 + float(i % 4) * 120.0, 1.0, 300.0 + float(i / 4) * 160.0)
		extra.set_player(main.player)
		extra.set_stealth(main.stealth)
		extra.set_patrol_route([extra.global_position, extra.global_position + Vector3(120, 0, 0)])
		stress.append(extra)
	await physics_frame
	await physics_frame
	var decisions: int = 0
	var t_ai: int = Time.get_ticks_usec()
	for e in stress:
		for k in range(20):
			e._decide(0.1)
			decisions += 1
	var ai_usec: int = Time.get_ticks_usec() - t_ai
	var per_decision_ms: float = float(ai_usec) / float(decisions) / 1000.0
	_check(per_decision_ms < 0.5, "AI decision cost %.3f ms (%d decisions incl. vision raycast) < 0.5 ms" % [per_decision_ms, decisions])
	var frames: int = 240
	var t_loop: int = Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
	var loop_ms: float = float(Time.get_ticks_usec() - t_loop) / 1000.0
	_check(loop_ms < 10000.0, "8-enemy 240-frame loop completes in %.0f ms (stable, no stalls)" % loop_ms)
	var ticks: int = 0
	for e in stress:
		ticks = maxi(ticks, e.decision_ticks)
	var expected_ticks: int = int(float(frames) * 0.0167 / 0.1)
	_check(ticks > 0 and ticks <= expected_ticks + 8,
		"AI decisions stay throttled to ai_interval (%d ticks in %d frames)" % [ticks, frames])
	for e in stress:
		e.queue_free()

	# --- 2D untouched ------------------------------------------------------
	var p2d: PackedScene = load("res://scenes/enemy.tscn")
	_check(p2d != null and p2d.instantiate() is CharacterBody2D, "2D enemy.tscn is still a CharacterBody2D")
	_finish()


func _finish() -> void:
	print("3D PHASE-4 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	if _fail > 0:
		print("3D PHASE-4 TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D PHASE-4 TEST: all checks passed")
		quit(0)
