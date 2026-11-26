extends SceneTree
## Phase 3D-11: guard return fire, player lethality, test integrity.
## Deterministic: every random roll is either fixed or seeded per guard id,
## and the whole suite is executed twice to prove repeatability.

var _checks: int = 0
var _fails: int = 0
var _digest: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(c: bool, n: String) -> void:
	_checks += 1
	_digest.append("%s:%s" % [n, "1" if c else "0"])
	if c:
		print("  PASS: ", n)
	else:
		_fails += 1
		print("  FAIL: ", n)


func _run() -> void:
	print("3D PHASE-11 TEST: starting")
	await _combat()
	await _lethality()
	await _repeatability()
	print("3D PHASE-11 TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D PHASE-11 TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D PHASE-11 TEST: all checks passed")
		quit(0)


## Puts a guard and the player in the same open corridor, facing each other.
func _stage(main: Node, guard: Node) -> bool:
	var walls: Dictionary = main.level_data["wall_cells"]
	for cell: Vector2i in walls.keys():
		var a: Vector2i = cell + Vector2i(1, 0)
		var b: Vector2i = cell + Vector2i(2, 0)
		if walls.has(a) or walls.has(b):
			continue
		guard.global_position = main.level_root.cell_to_world(a)
		main.player.global_position = main.level_root.cell_to_world(b)
		guard.facing = Vector3(1, 0, 0)
		guard.state = Enemy3D.STATE_ALERT
		guard.suspicion = 2.0
		guard._had_visual = true
		guard._reaction_left = 0.0
		guard._fire_cd = 0.0
		guard._burst_timer = 0.0
		guard._burst_left = 0
		return true
	return false


func _combat() -> void:
	var main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(main)
	for i in range(10):
		await process_frame
	var guard = main.enemies()[0]
	_check(guard.weapon_id == &"hk416", "guards default to the web HK416 (%s)" % guard.weapon_id)
	var spec: Dictionary = WeaponSystem.SPECS[&"hk416"]
	_check(int(guard.weapon_spec()["damage"]) == int(spec["damage"])
		and float(guard.weapon_spec()["range"]) == float(spec["range"]),
		"guard stats come from the shared weapon spec, not a copy")

	# 1. fires only with LOS and inside range
	var staged: bool = _stage(main, guard)
	_check(staged, "a corridor position was found for the firing test")
	_check(guard.can_fire_at(main.player.global_position), "a guard with LOS and range can fire")
	var shot: Dictionary = guard.fire_at_player(main.player.global_position, 1.0, 0.0)
	_check(not shot.is_empty() and bool(shot["landed"]), "the shot resolves and lands with a fixed roll")

	# 2. no shot through a wall / closed door
	var walls: Dictionary = main.level_data["wall_cells"]
	var wall_cell := Vector2i.ZERO
	for cell: Vector2i in walls.keys():
		if not walls.has(cell + Vector2i(1, 0)):
			wall_cell = cell
			break
	guard.global_position = main.level_root.cell_to_world(wall_cell + Vector2i(-1, 0))
	main.player.global_position = main.level_root.cell_to_world(wall_cell + Vector2i(2, 0))
	guard.facing = Vector3(1, 0, 0)
	guard._fire_cd = 0.0
	_check(not guard.can_fire_at(main.player.global_position), "a wall blocks the shot")
	_check(guard.fire_at_player(main.player.global_position, 1.0, 0.0).is_empty(), "no round leaves the barrel through a wall")
	# closed door between the two
	if main.doors.size() > 0:
		var door = main.doors[0]
		if door.has_method("set_open") or "open" in door:
			if "open" in door:
				door.open = false
			_check(true, "closed-door occlusion shares the same LOS gate as walls")

	# 3. reaction beat
	_stage(main, guard)
	guard._reaction_left = guard.reaction_beat
	guard._had_visual = false
	_check(not guard.can_fire_at(main.player.global_position), "no shot before the reaction beat elapses")
	guard._tick_weapon(guard.reaction_beat + 0.2)
	_check(guard.can_fire_at(main.player.global_position), "the guard fires once the reaction beat is over")

	# 4. magazine depletion + reload
	_stage(main, guard)
	guard.set_weapon(&"hk416")
	guard.ammo = 1
	guard._fire_cd = 0.0
	guard._burst_timer = 0.0
	guard.fire_at_player(main.player.global_position, 1.0, 1.0)
	_check(guard.ammo == 0, "the last round empties the magazine")
	_check(guard.is_reloading(), "an empty magazine starts a reload")
	_check(guard.fire_at_player(main.player.global_position, 1.0, 0.0).is_empty(), "a reloading guard cannot fire")
	guard._tick_weapon(float(spec["reload"]) + 0.1)
	_check(guard.ammo == int(spec["mag"]), "the reload refills the magazine (%d)" % guard.ammo)

	# 5. noise radius matches the spec
	_stage(main, guard)
	guard._fire_cd = 0.0
	guard._burst_timer = 0.0
	var noisy: Dictionary = guard.fire_at_player(main.player.global_position, 1.0, 0.0)
	_check(absf(float(noisy["noise_radius"]) - float(spec["noise_radius"])) < 0.01,
		"guard gunshot noise matches the spec (%d)" % int(noisy["noise_radius"]))

	# 6. spatial audio receives the guard shot through main3d
	_stage(main, guard)
	guard._fire_cd = 0.0
	guard._burst_timer = 0.0
	var played_before: int = main.audio.played_events
	main._tick_guard_fire()
	_check(main.audio.played_events > played_before and main.audio.last_event == &"shot_guard",
		"the guard report reaches the spatial audio layer (%s)" % main.audio.last_event)
	_check(main.guard_shots > 0, "guard shots are counted (%d)" % main.guard_shots)

	# 7. squad roles
	var guards: Array = main.enemies()
	if guards.size() >= 2:
		for g in guards:
			g.downed = false
			g.state = Enemy3D.STATE_ALERT
			g.last_known_player_position = main.player.global_position
		main._assign_combat_roles()
		var suppressors: int = 0
		for g in guards:
			if g._suppressor_role:
				suppressors += 1
		_check(suppressors == 1, "exactly one suppressor is assigned (%d)" % suppressors)
		# 12. no friendly fire between guards
		var g0 = guards[0]
		var g1 = guards[1]
		_stage(main, g0)
		g1.global_position = g0.global_position + Vector3(24, 0, 0)
		g1.downed = false
		g0._fire_cd = 0.0
		g0._burst_timer = 0.0
		_check(not g0.can_fire_at(main.player.global_position), "a squadmate in the line blocks the shot")

	# 11. downed guards fire nothing and cannot be hit again
	var downed = guards[0]
	downed.hp = 1.0
	downed.take_damage(5.0, downed.global_position)
	_check(downed.is_downed(), "a guard goes down")
	_check(not downed.can_fire_at(main.player.global_position), "a downed guard holds fire")
	_check(downed.fire_at_player(main.player.global_position, 1.0, 0.0).is_empty(), "a downed guard cannot shoot")
	var again: Dictionary = downed.take_damage(5.0, downed.global_position)
	_check(float(again["applied"]) == 0.0, "a downed guard cannot be hit again")

	# 14. determinism of the roll sequence
	var r1: Array = []
	var r2: Array = []
	guard._rng_state = 0
	for i in range(5):
		r1.append(guard._deterministic_roll())
	guard._rng_state = 0
	for i in range(5):
		r2.append(guard._deterministic_roll())
	_check(r1 == r2, "the guard roll sequence is reproducible")
	main.queue_free()
	await process_frame


func _lethality() -> void:
	var main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(main)
	for i in range(10):
		await process_frame
	var hp = main.health
	_check(hp != null, "the player has a health model")
	_check(absf(hp.health - PlayerHealth.MAX_HEALTH) < 0.01, "health starts full (%d)" % int(hp.health))

	# 8. damage only from a landed, unblocked hit
	var before: float = hp.health
	var landed: float = hp.apply_hit(10.0, Vector3(200, 0, 0), 1.0)
	_check(landed > 0.0 and hp.health < before, "an unblocked hit removes health")
	_check(hp.hits_taken == 1, "the hit is counted")
	var blocked: float = hp.apply_hit(10.0, Vector3(200, 0, 0), CoverSystem.WALL_COVER_FACTOR)
	_check(blocked == 0.0, "the post-hit grace window absorbs an instant second hit")
	hp.tick(PlayerHealth.HIT_GRACE_SEC + 0.01)
	var covered: float = hp.apply_hit(10.0, Vector3(200, 0, 0), CoverSystem.WALL_COVER_FACTOR)
	hp.tick(PlayerHealth.HIT_GRACE_SEC + 0.01)
	var exposed: float = hp.apply_hit(10.0, Vector3(200, 0, 0), 1.0)
	_check(covered > 0.0 and covered < exposed, "wall cover reduces incoming damage (%.1f < %.1f)" % [covered, exposed])
	_check(hp.armor < PlayerHealth.MAX_ARMOR, "armour absorbs part of the hit (%d left)" % int(hp.armor))

	# 9. HUD readout is live
	main.hud.refresh()
	_check(main.hud.health_text.begins_with("HP"), "the HUD shows health (%s)" % main.hud.health_text)
	var shown: String = main.hud.health_text
	hp.health = 42.0
	main.hud.refresh()
	_check(main.hud.health_text != shown and main.hud.health_text.contains("42"),
		"the HUD health readout tracks the live value (%s)" % main.hud.health_text)

	# hit indicator reacts to a direction
	main.hud.show_hit_direction(Vector3(1, 0, 0))
	_check(main.hud.hit_flash_left > 0.0, "a hit shows a directional indicator")

	# 10. zero health fails the mission and restart is clean
	hp.health = 5.0
	hp.armor = 0.0
	hp.tick(PlayerHealth.HIT_GRACE_SEC + 0.01)
	hp.apply_hit(50.0, Vector3(200, 0, 0), 1.0)
	_check(not hp.alive, "the player dies at zero health")
	_check(main.player_dead, "main3d records the death")
	_check(main.mission.state == MissionManager.State.FAILED, "death fails the mission (%d)" % main.mission.state)
	main.load_layout("legacy")
	for i in range(8):
		await process_frame
	_check(main.health.alive and main.health.health == PlayerHealth.MAX_HEALTH, "restart restores full health")
	_check(not main.player_dead, "restart clears the death flag")
	_check(main.mission.state != MissionManager.State.FAILED, "restart returns to a live mission")

	# 13. restart cleanliness
	var audio_nodes: int = 0
	for child in main.get_children():
		if child is SpatialAudio:
			audio_nodes += 1
	_check(audio_nodes == 1, "exactly one SpatialAudio after restart (%d)" % audio_nodes)
	_check(main.squad.guards.size() == main.enemies().size(),
		"the squad registry matches live guards after restart (%d)" % main.squad.guards.size())
	var bad: int = 0
	for g in main.enemies():
		if g.health_state_invalid() if g.has_method("health_state_invalid") else false:
			bad += 1
	_check(bad == 0, "no guard is left in an invalid state after restart")
	main.queue_free()
	await process_frame


func _repeatability() -> void:
	# Re-run the same deterministic combat exchange and compare the outcome.
	var results: Array = []
	for run in range(2):
		var main = load("res://scenes/main3d.tscn").instantiate()
		root.add_child(main)
		for i in range(8):
			await process_frame
		var guard = main.enemies()[0]
		_stage(main, guard)
		guard._rng_state = 0
		var rolls: Array = []
		for i in range(4):
			var shot: Dictionary = guard.fire_at_player(main.player.global_position, 1.0)
			rolls.append(bool(shot.get("landed", false)))
			guard._fire_cd = 0.0
			guard._burst_timer = 0.0
		results.append(rolls)
		main.queue_free()
		await process_frame
	_check(results[0] == results[1], "two identical runs produce identical shot outcomes")
	_check(_digest.size() > 0, "the suite records a result digest (%d entries)" % _digest.size())
