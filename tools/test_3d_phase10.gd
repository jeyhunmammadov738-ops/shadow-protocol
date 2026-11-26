extends SceneTree
## Phase 3D-10: playability + enemy parity tests.
## Covers inputs (keyboard + touch), weapon HUD, gunshot awareness, downed
## bodies, squad propagation, cover use, Act-3 patrol, spatial audio and the
## live SectorBlueprint.

var _checks: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(c: bool, n: String) -> void:
	_checks += 1
	if c:
		print("  PASS: ", n)
	else:
		_fails += 1
		print("  FAIL: ", n)


func _run() -> void:
	print("3D PHASE-10 TEST: starting")
	_inputs()
	_audio_math()
	await _scene()
	print("3D PHASE-10 TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D PHASE-10 TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D PHASE-10 TEST: all checks passed")
		quit(0)


# --------------------------------------------------------------- inputs ----
func _inputs() -> void:
	for action in ["fire", "reload", "cycle_fire_mode"]:
		_check(InputMap.has_action(action), "input action '%s' exists" % action)
	_check(not InputMap.action_get_events("fire").is_empty(), "fire action has bindings")

	var layer = load("res://scripts/mobile_controls.gd").new()
	root.add_child(layer)
	layer.visible = true
	for name in ["fire", "reload", "mode"]:
		_check(layer.button_center(name) != Vector2.ZERO, "touch button '%s' is laid out" % name)
	# Ownership: the FIRE button belongs to the touch layer, the left half
	# still belongs to the joystick, and no two buttons overlap.
	for res in [Vector2(1280, 720), Vector2(2340, 1080), Vector2(2400, 1080)]:
		get_root().size = Vector2i(res)
		layer._layout_buttons()
		var names: Array = layer._buttons.keys()
		var overlaps: int = 0
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var a: Dictionary = layer._buttons[names[i]]
				var b: Dictionary = layer._buttons[names[j]]
				if Vector2(a["center"]).distance_to(Vector2(b["center"])) < float(a["radius"]) + float(b["radius"]):
					overlaps += 1
		_check(overlaps == 0, "no button overlap at %dx%d (%d overlaps)" % [res.x, res.y, overlaps])
		_check(layer.is_position_owned(layer.button_center("fire")), "FIRE is owned by the touch layer at %dx%d" % [res.x, res.y])
		_check(layer.is_position_owned(Vector2(res.x * 0.2, res.y * 0.6)), "joystick zone still owned at %dx%d" % [res.x, res.y])
		_check(not layer.is_position_owned(Vector2(res.x * 0.6, res.y * 0.35)), "camera drag zone stays free at %dx%d" % [res.x, res.y])
	layer.queue_free()


# ----------------------------------------------------------- audio math ----
func _audio_math() -> void:
	var near: Dictionary = SpatialAudio.compute_spatial(Vector3(0, 0, 0), Vector3(10, 0, 0), 0.0)
	_check(absf(float(near["gain"]) - 1.0) < 0.001, "gain is 1.0 inside the minimum range")
	var far: Dictionary = SpatialAudio.compute_spatial(Vector3(0, 0, 0), Vector3(900, 0, 0), 0.0)
	_check(float(far["gain"]) == 0.0, "gain is 0 beyond the maximum range")
	var mid: Dictionary = SpatialAudio.compute_spatial(Vector3(0, 0, 0), Vector3(200, 0, 0), 0.0)
	_check(float(mid["gain"]) > 0.0 and float(mid["gain"]) < 1.0, "gain rolls off with distance (%.2f)" % float(mid["gain"]))
	var right: Dictionary = SpatialAudio.compute_spatial(Vector3(120, 0, 0), Vector3.ZERO, 0.0)
	var left: Dictionary = SpatialAudio.compute_spatial(Vector3(-120, 0, 0), Vector3.ZERO, 0.0)
	_check(float(right["pan"]) > 0.0 and float(left["pan"]) < 0.0, "stereo pan follows the source side")
	_check(absf(float(right["pan"])) <= 0.85, "pan is clamped to 0.85")
	var audio := SpatialAudio.new()
	root.add_child(audio)
	_check(audio.event_names().size() >= 10, "procedural voice bank is populated (%d)" % audio.event_names().size())
	for event in [&"shot_suppressed", &"shot_loud", &"shot_rifle", &"step_metal", &"impact"]:
		_check(audio.has_event(event), "voice bank has '%s'" % event)
	audio.queue_free()


# -------------------------------------------------------------- scene -----
func _scene() -> void:
	var main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(main)
	for i in range(12):
		await process_frame
	_check(main.weapons != null, "weapon system present")
	_check(main.squad != null, "SquadDirector present")
	_check(main.audio != null, "SpatialAudio present")

	# --- keyboard fire / reload / mode -------------------------------
	var before: int = main.weapons.shots_fired
	Input.action_press("fire")
	await process_frame
	await process_frame
	Input.action_release("fire")
	_check(main.weapons.shots_fired > before, "keyboard FIRE spends ammo (%d -> %d)" % [before, main.weapons.shots_fired])
	_check(main.shots_played > 0, "firing plays a spatial weapon report")
	main.weapons.state()["ammo"] = 3
	Input.action_press("reload")
	await process_frame
	Input.action_release("reload")
	_check(main.weapons.is_reloading(), "keyboard RELOAD starts a reload")
	main.weapons.tick(2.0)
	_check(int(main.weapons.state()["ammo"]) == 20, "reload refills the magazine")
	# Keyboard path must produce a real mode change on a multi-mode weapon.
	main.weapons.grant(&"mp5sd")
	main.weapons.select(&"mp5sd")
	var mode_before: int = main.weapons.current_mode()
	Input.action_press("cycle_fire_mode")
	await process_frame
	Input.action_release("cycle_fire_mode")
	var mode_after: int = main.weapons.current_mode()
	_check(mode_after != mode_before, "fire mode changes from the keyboard path (%d -> %d)" % [mode_before, mode_after])
	main.cycle_fire_mode()
	_check(main.weapons.current_mode() != mode_after, "a second cycle moves to the next mode again")

	# --- touch fire / reload / mode ----------------------------------
	var layer = main.touch_layer
	layer.visible = true
	layer._layout_buttons()
	var shots_before: int = main.weapons.shots_fired
	_tap(layer, layer.button_center("fire"))
	await process_frame
	_check(main.weapons.shots_fired > shots_before, "touch FIRE fires the weapon")
	var taps: Array = []
	layer.mode_pressed.connect(func(): taps.append("mode"))
	_tap(layer, layer.button_center("mode"))
	await process_frame
	_check(taps.size() == 1, "touch MODE button emits once per tap")
	var reload_taps: Array = []
	layer.reload_pressed.connect(func(): reload_taps.append("reload"))
	main.weapons.state()["ammo"] = 1
	_tap(layer, layer.button_center("reload"))
	await process_frame
	_check(reload_taps.size() == 1, "touch RELOAD button emits once per tap")

	# --- noise per weapon --------------------------------------------
	main.weapons.select(&"fiveseven")
	var quiet: Dictionary = main.fire_weapon()
	main.weapons.tick(1.0)
	main.weapons.grant(&"ak47")
	main.weapons.select(&"ak47")
	var loud: Dictionary = main.fire_weapon()
	_check(float(loud["noise_radius"]) > float(quiet["noise_radius"]) * 4.0,
		"loud rifle noise dwarfs the suppressed sidearm (%d vs %d)" % [int(loud["noise_radius"]), int(quiet["noise_radius"])])
	_check(main.audio.last_event == &"shot_rifle", "rifle report uses the rifle voice (%s)" % main.audio.last_event)
	main.weapons.select(&"fiveseven")
	main.weapons.tick(1.0)
	main.fire_weapon()
	_check(main.audio.last_event == &"shot_suppressed", "suppressed report uses the quiet voice (%s)" % main.audio.last_event)

	# --- guard gunshot awareness -------------------------------------
	var guards: Array = main.enemies()
	_check(guards.size() > 0, "guards exist (%d)" % guards.size())
	# The shots fired above may already have wounded a guard, so put the
	# squad back into a clean patrol state before testing reactions.
	for g in guards:
		g.hp = 3.0
		g.downed = false
		g.state = Enemy3D.STATE_PATROL
		g.suspicion = 0.0
		g._investigation_score = 0.0
		g._state_timer = 0.0
	var guard = guards[0]
	guard.state = Enemy3D.STATE_PATROL
	guard.suspicion = 0.0
	guard._investigation_score = 0.0
	guard._state_timer = 0.0

	var far_pos: Vector3 = guard.global_position + Vector3(60, 0, 0)
	# The noise channel deduplicates per source per frame, so let a frame
	# pass after the weapon reports above before publishing a fresh shot.
	await process_frame
	main.stealth.publish_noise(far_pos, 400.0, &"gunshot", &"alarm", {})
	await process_frame
	_check(guard.state == Enemy3D.STATE_INVESTIGATING, "a gunshot sends a guard to investigate (%s)" % guard.state)
	_check(guard.last_sound_target() == far_pos, "the guard investigates the shot position")
	# duplicate noise does not restart the investigation
	var score_before: float = guard._investigation_score
	main.stealth.publish_noise(far_pos + Vector3(2, 0, 0), 200.0, &"gunshot", &"alarm", {})
	await process_frame
	_check(absf(guard._investigation_score - score_before) < 0.01, "a duplicate quieter noise does not restart the investigation")

	# --- damage / downed body ----------------------------------------
	var witness = null
	for g in main.enemies():
		if g != guard and not g.is_downed():
			witness = g
			break
	if witness != null:
		witness.state = Enemy3D.STATE_PATROL
		witness.suspicion = 0.0
		witness._investigation_score = 0.0
		witness._state_timer = 0.0
		# A squadmate has to be in the same part of the sector to notice.
		witness.global_position = guard.global_position + Vector3(80, 0, 0)
	guard.hp = 1.0
	var result: Dictionary = guard.take_damage(2.0, guard.global_position + Vector3(10, 0, 0))
	await process_frame
	_check(bool(result["downed"]) and guard.is_downed(), "a guard goes down when hp reaches zero")
	_check(main.squad.downed_count >= 1, "the squad records the downed body (%d)" % main.squad.downed_count)
	_check(not guard.can_be_hit(), "a downed guard cannot be hit again")
	if witness != null:
		_check(witness.state == Enemy3D.STATE_INVESTIGATING,
			"a squadmate investigates the body (%s)" % witness.state)

	# --- squad alert propagation -------------------------------------
	if witness != null:
		witness.state = Enemy3D.STATE_PATROL
		witness.suspicion = 0.0
		var threat: Vector3 = witness.global_position + Vector3(90, 0, 0)
		main.squad.broadcast_alert(&"enemy_0", threat)
		await process_frame
		_check(witness.state == Enemy3D.STATE_ALERT, "a radio callout puts squadmates on alert (%s)" % witness.state)
		_check(witness.squad_alerts_received >= 1, "squad alert counter advanced")
		_check(witness.last_known_position() == threat, "squadmates receive the shared threat position")

	# --- guards use cover --------------------------------------------
	if witness != null and main.cover != null:
		# Cover only exists next to walls and only counts when it breaks the
		# line to the threat, so stand the guard off a wall face and put the
		# threat on the far side of that wall.
		var walls: Dictionary = main.level_data["wall_cells"]
		var wall_cell := Vector2i.ZERO
		var open_cell := Vector2i.ZERO
		var dir := Vector2i.ZERO
		var placed: bool = false
		for candidate: Vector2i in walls.keys():
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var oc: Vector2i = candidate + d
				if not walls.has(oc):
					wall_cell = candidate
					open_cell = oc
					dir = d
					placed = true
					break
			if placed:
				break
		var stand: Vector2i = open_cell + dir * 2
		if walls.has(stand):
			stand = open_cell
		witness.global_position = main.level_root.cell_to_world(stand)
		witness.state = Enemy3D.STATE_INVESTIGATING
		# Threat on the other side of the wall, so the wall is real cover.
		witness.last_sound_position = main.level_root.cell_to_world(open_cell - dir * 3)
		witness._cover_timer = 0.0
		var spots: Array = main.cover.cover_positions(witness.global_position, witness.last_sound_position, 3)
		_check(spots.size() > 0, "cover positions exist behind the wall (%d)" % spots.size())
		var player_saved: Vector3 = main.player.global_position
		main.player.global_position = player_saved + Vector3(0, 0, -4000)
		var cover_before: int = witness.cover_moves
		witness._decide(0.5)
		main.player.global_position = player_saved
		_check(witness.cover_moves > cover_before,
			"an investigating guard actually moves to cover (%d -> %d)" % [cover_before, witness.cover_moves])
		_check(spots.has(witness.current_target()), "the guard targets a real cover position")

	# --- act 3 patrol ------------------------------------------------
	var route_guard = main.enemies()[0]
	main.set_act3(true)
	_check(main.squad.act3_active, "act 3 flag reaches the SquadDirector")
	_check(absf(main.squad.speed_scale() - SquadDirector.ACT3_PATROL_SPEED_SCALE) < 0.001, "act 3 raises the patrol speed scale")
	_check(route_guard.act3, "act 3 flag reaches the guards")
	var route: Array = route_guard.patrol_route()
	_check(route.size() > 0, "guards keep a deterministic patrol route (%d points)" % route.size())
	main.set_act3(false)

	# --- HUD: weapon panel + blueprint -------------------------------
	var hud = main.hud
	_check(hud.weapon_panel != null, "weapon panel exists")
	_check(hud.weapon_name_label != null and hud.weapon_ammo_label != null, "weapon panel labels exist")
	hud.refresh()
	_check(hud.weapon_ammo_label.text.contains("/"), "ammo readout shows magazine / reserve (%s)" % hud.weapon_ammo_label.text)
	_check(hud.weapon_slots_label.text.contains("["), "owned-slot strip marks the current weapon (%s)" % hud.weapon_slots_label.text)
	main.weapons.state()["ammo"] = 0
	hud.refresh()
	_check(hud.weapon_ammo_label.text.begins_with("0"), "empty magazine is reflected live (%s)" % hud.weapon_ammo_label.text)
	_check(hud.blueprint != null, "SectorBlueprint exists")
	var grid: Vector2i = main.level_data["grid_size"]
	await process_frame
	_check(hud.blueprint.cells_drawn == grid.x * grid.y, "blueprint draws every sector cell (%d)" % hud.blueprint.cells_drawn)
	_check(hud.blueprint.last_draw_ms < 40, "blueprint draw stays cheap (%d ms)" % hud.blueprint.last_draw_ms)
	_check(hud.blueprint.show_guards, "blueprint shows guard positions")

	# --- restart cleanliness -----------------------------------------
	var cams_before: int = main.security_cameras.size()
	main.load_layout("layout_b")
	for i in range(6):
		await process_frame
	var squad_guards: int = main.squad.guards.size()
	_check(squad_guards == main.enemies().size(), "squad registry matches live guards after reload (%d)" % squad_guards)
	_check(main.security_cameras.size() > 0 and cams_before > 0, "facility layer survives reload")
	var audio_nodes: int = 0
	for child in main.get_children():
		if child is SpatialAudio:
			audio_nodes += 1
	_check(audio_nodes == 1, "exactly one spatial audio node after reload (%d)" % audio_nodes)


func _tap(layer: Control, pos: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = pos
	press.pressed = true
	get_root().push_input(press, true)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = pos
	release.pressed = false
	get_root().push_input(release, true)
